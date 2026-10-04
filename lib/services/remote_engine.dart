import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/remote_protocol.dart';
import '../core/ytdlp.dart';
import 'engine.dart';

/// Drives a Haul running on a computer: the phone (or browser) keeps the
/// queue and the UI, the computer runs yt-dlp. Works anywhere `http`
/// does, which is everywhere — that's how iOS and the web are covered.
class RemoteEngine extends Engine {
  RemoteEngine({http.Client? client, this.mobile = true}) : _http = client ?? http.Client();

  final http.Client _http;
  final bool mobile;
  final _toolCtrl = StreamController<List<ToolInfo>>.broadcast();
  final _cancelled = <String>{};

  Uri? _base;
  String? _code;
  RemoteInfo? _info;
  String? _error;
  bool _connecting = false;

  Uri? get base => _base;
  String? get code => _code;
  RemoteInfo? get info => _info;
  String? get lastError => _error;

  @override
  bool get isMobile => mobile;

  @override
  String get pathSeparator => _info?.pathSeparator ?? '/';

  @override
  List<ToolInfo> get tools => [
        ToolInfo(
          id: 'remote',
          name: _info?.name ?? 'Your computer',
          purpose: 'Runs the downloads for this device',
          required: true,
          state: _connecting
              ? ToolState.installing
              : (_info != null ? ToolState.ready : (_error != null ? ToolState.failed : ToolState.missing)),
          version: _info == null ? null : 'yt-dlp ${_info!.ytdlpVersion ?? ''} · ${_base?.authority ?? ''}',
          error: _error,
          managed: true,
        ),
      ];

  @override
  Stream<List<ToolInfo>> get toolChanges => _toolCtrl.stream;

  @override
  bool get ready => _info != null;

  @override
  EngineCaps get caps {
    final i = _info;
    if (i == null) return const EngineCaps(hasFfmpeg: false);
    return EngineCaps(
      hasFfmpeg: i.hasFfmpeg,
      jsRuntime: i.jsRuntime,
      ffmpegLocation: i.ffmpegLocation,
      tempDir: i.tempDir,
      // The cookie setting belongs to the computer's browsers; phones
      // don't offer it.
      supportsBrowserCookies: false,
    );
  }

  Map<String, String> get _headers => {'X-Haul-Code': _code ?? '', 'Content-Type': 'application/json'};

  Uri _api(String path, [Map<String, String>? query]) =>
      _base!.replace(path: '/api/$path', queryParameters: query);

  /// Pairs with a computer. Returns null on success, or a human message.
  Future<String?> connect(Uri base, String code) async {
    _base = base;
    _code = normalizeCode(code);
    _connecting = true;
    _error = null;
    _toolCtrl.add(tools);
    try {
      final r = await _http.get(_api('hello'), headers: _headers).timeout(const Duration(seconds: 6));
      if (r.statusCode == 401) {
        _error = 'That code didn\'t match. Check it on your computer.';
      } else if (r.statusCode != 200) {
        _error = 'Your computer answered, but not like Haul does (HTTP ${r.statusCode}).';
      } else {
        _info = RemoteInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } on TimeoutException {
      _error = 'No answer. Is Haul open on your computer, with phone access on?';
    } catch (_) {
      _error = 'Couldn\'t reach ${base.authority}. Same Wi-Fi? Phone access on?';
    }
    if (_error != null) _info = null;
    _connecting = false;
    _toolCtrl.add(tools);
    return _error;
  }

  void disconnect() {
    _info = null;
    _base = null;
    _code = null;
    _error = null;
    _toolCtrl.add(tools);
  }

  @override
  Future<void> detect() async {
    if (_base != null && _code != null && _info == null) await connect(_base!, _code!);
  }

  @override
  Future<void> install({bool extras = true}) => detect();

  @override
  Future<void> installTool(String id) => detect();

  @override
  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine}) async {
    if (_base == null) {
      return const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: Not connected to your computer.');
    }
    _cancelled.remove(jobId);
    try {
      final created = await _http
          .post(_api('jobs'), headers: _headers, body: jsonEncode({'id': jobId, 'args': args}))
          .timeout(const Duration(seconds: 15));
      if (created.statusCode != 202) {
        final msg = _message(created.body) ?? 'HTTP ${created.statusCode}';
        return RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: Your computer refused: $msg');
      }
    } catch (_) {
      return const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: Lost connection to your computer.');
    }

    final out = StringBuffer();
    var next = 0;
    var failures = 0;
    var idle = 0;
    while (true) {
      try {
        final r = await _http
            .get(_api('jobs/$jobId', {'from': '$next'}), headers: _headers)
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 404) {
          return const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: Your computer forgot this download (was Haul restarted?)');
        }
        final snap = JobSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
        failures = 0;
        for (final line in snap.lines) {
          out.writeln(line);
          onLine?.call(line);
        }
        next = snap.next;
        if (snap.done) {
          return RunResult(
            exitCode: snap.exitCode ?? 1,
            stdout: out.toString(),
            stderr: snap.stderr,
            cancelled: snap.cancelled || _cancelled.remove(jobId),
          );
        }
        idle = snap.lines.isEmpty ? idle + 1 : 0;
      } catch (_) {
        // Wi-Fi blips happen; the job keeps running on the computer.
        if (++failures > 40) {
          return const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: Lost connection to your computer.');
        }
      }
      // Quick while output flows, relaxed while waiting.
      final wait = failures > 0 ? 1000 : (idle > 8 ? 700 : 250);
      await Future.delayed(Duration(milliseconds: wait));
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    _cancelled.add(jobId);
    if (_base == null) return;
    try {
      await _http.delete(_api('jobs/$jobId'), headers: _headers).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Future<String> updateYtDlp() async {
    if (_base == null) return 'Not connected';
    try {
      final r = await _http.post(_api('update'), headers: _headers).timeout(const Duration(minutes: 3));
      await connect(_base!, _code!);
      return _message(r.body) ?? 'Done';
    } catch (_) {
      return 'Couldn\'t reach your computer';
    }
  }

  @override
  Future<String> defaultDownloadDir() async => _info?.downloadDir ?? '';

  @override
  Future<String?> archivePath() async => _info?.archivePath;

  /// Direct link to a finished file on the computer (code in the query so
  /// browsers can download it with a plain link).
  Uri fileUri(String path) => _api('file', {'path': path, 'code': _code ?? ''});

  String? _message(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] is String) return j['message'] as String;
    } catch (_) {}
    return null;
  }
}
