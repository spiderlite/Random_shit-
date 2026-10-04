import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ytdlp.dart';
import 'engine.dart';

/// yt-dlp on Android, via the bundled Python + ffmpeg from
/// youtubedl-android (see `android/app/src/main/kotlin/.../HaulEngine.kt`).
class AndroidEngine extends Engine {
  AndroidEngine() {
    _lines.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final id = event['id'] as String?;
        final line = event['line'] as String?;
        if (id != null && line != null) _listeners[id]?.call(line);
      }
    });
  }

  static const _channel = MethodChannel('haul/engine');
  static const _lines = EventChannel('haul/engine/lines');

  final _listeners = <String, void Function(String)>{};
  final _cancelled = <String>{};
  final _toolCtrl = StreamController<List<ToolInfo>>.broadcast();
  bool _ready = false;

  /// Technical details of the last start-up failure (for "Copy details").
  @override
  String? errorDetail;
  String? _downloadDir;
  String? _cacheDir;
  String? _jsRuntime;

  var _tools = <ToolInfo>[
    const ToolInfo(
      id: 'yt-dlp',
      name: 'Download engine',
      purpose: 'yt-dlp, Python and ffmpeg, built in',
      state: ToolState.missing,
      required: true,
    ),
  ];

  @override
  bool get isMobile => true;

  @override
  String get pathSeparator => '/';

  @override
  List<ToolInfo> get tools => _tools;

  @override
  Stream<List<ToolInfo>> get toolChanges => _toolCtrl.stream;

  @override
  bool get ready => _ready;

  @override
  EngineCaps get caps => EngineCaps(
        hasFfmpeg: true,
        jsRuntime: _jsRuntime,
        // The Python build of yt-dlp may lack the bundled YouTube challenge
        // solver; let it fetch the official one when it needs it.
        extraArgs: _jsRuntime == null ? const [] : const ['--remote-components', 'ejs:github'],
        supportsBrowserCookies: false,
        tempDir: _cacheDir == null ? null : '$_cacheDir/partial',
      );

  void _set(ToolInfo Function(ToolInfo) f) {
    _tools = [f(_tools.first)];
    _toolCtrl.add(_tools);
  }

  @override
  Future<void> detect() async {
    // Unpacking Python takes a moment on first launch; everything else is
    // instant. Do it eagerly so the first download starts right away.
    await install();
  }

  @override
  Future<void> install({bool extras = true}) async {
    if (_ready) return;
    _set((t) => t.copyWith(state: ToolState.installing));
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('init');
      _downloadDir = info?['downloadDir'] as String?;
      _cacheDir = info?['cacheDir'] as String? ?? (await getTemporaryDirectory()).path;
      _jsRuntime = info?['jsRuntime'] as String?;
      _ready = true;
      _set((t) => t.copyWith(state: ToolState.ready, version: info?['version'] as String?, managed: true));
    } on PlatformException catch (e) {
      errorDetail = e.details is String ? e.details as String : null;
      _set((t) => t.copyWith(state: ToolState.failed, error: e.message ?? 'Couldn\'t start the download engine.'));
    }
  }

  @override
  Future<void> installTool(String id) => install();

  @override
  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine}) async {
    if (!_ready) await install();
    _cancelled.remove(jobId);
    if (onLine != null) _listeners[jobId] = onLine;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('run', {'id': jobId, 'args': args});
      return RunResult(
        exitCode: (r?['exitCode'] as int?) ?? 1,
        stdout: r?['out'] as String? ?? '',
        stderr: r?['err'] as String? ?? '',
        cancelled: _cancelled.remove(jobId) || (r?['cancelled'] as bool? ?? false),
      );
    } on PlatformException catch (e) {
      return RunResult(
        exitCode: 1,
        stdout: '',
        stderr: e.message ?? 'ERROR: engine failure',
        cancelled: _cancelled.remove(jobId),
      );
    } finally {
      _listeners.remove(jobId);
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    _cancelled.add(jobId);
    await _channel.invokeMethod('cancel', {'id': jobId});
  }

  @override
  Future<String> updateYtDlp() async {
    _set((t) => t.copyWith(state: ToolState.installing));
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('update');
      final v = r?['version'] as String?;
      _set((t) => t.copyWith(state: ToolState.ready, version: v));
      return r?['status'] == 'ALREADY_UP_TO_DATE' ? 'Already on the latest version ($v)' : 'Updated to $v';
    } on PlatformException catch (e) {
      _set((t) => t.copyWith(state: ToolState.ready));
      return e.message ?? 'Update failed. Check your connection.';
    }
  }

  @override
  Future<String> defaultDownloadDir() async {
    if (_downloadDir == null) await install();
    return _downloadDir ?? '/storage/emulated/0/Download/Haul';
  }

  @override
  Future<String?> archivePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/archive.txt';
  }
}

/// iOS and the web can't run yt-dlp; the UI explains instead of failing.
class UnsupportedEngine extends Engine {
  @override
  bool get supported => false;
  @override
  bool get isMobile => true;
  @override
  String get pathSeparator => '/';
  @override
  List<ToolInfo> get tools => const [];
  @override
  Stream<List<ToolInfo>> get toolChanges => const Stream.empty();
  @override
  bool get ready => false;
  @override
  EngineCaps get caps => const EngineCaps(hasFfmpeg: false);
  @override
  Future<void> detect() async {}
  @override
  Future<void> install({bool extras = true}) async {}
  @override
  Future<void> installTool(String id) async {}
  @override
  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine}) async =>
      const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: This device can\'t run the download engine.');
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<String> updateYtDlp() async => 'Not available here';
  @override
  Future<String> defaultDownloadDir() async => '';
  @override
  Future<String?> archivePath() async => null;
}
