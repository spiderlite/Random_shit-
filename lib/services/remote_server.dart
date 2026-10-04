import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/remote_protocol.dart';
import 'engine.dart';
import 'remote_host.dart';

class _Job {
  final lines = <String>[];
  bool done = false;
  int? exitCode;
  String stderr = '';
  bool cancelled = false;
  DateTime touched = DateTime.now();
}

/// Lets phones and browsers on the same network use this computer's Haul.
///
/// Phones send exactly the yt-dlp arguments Haul builds; every job is
/// checked by [validateRemoteArgs] against this machine's folders and
/// tools before anything runs. Files are only served from the downloads
/// folder. All of it sits behind a pairing code.
class RemoteServer implements RemoteHost {
  RemoteServer({
    required this.engine,
    required this.code,
    required this.downloadDir,
    this.webRoot,
    this.port = remoteDefaultPort,
  });

  final Engine engine;
  final String Function() code;
  final Future<String> Function() downloadDir;
  /// Folder holding the Flutter web build, served at `/`.
  final String? webRoot;
  final int port;

  HttpServer? _server;
  final _jobs = <String, _Job>{};
  Timer? _gc;
  int _badAttempts = 0;

  @override
  bool get running => _server != null;
  int? get boundPort => _server?.port;

  @override
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.autoCompress = true;
    _server!.listen((req) => _handle(req).catchError((Object e) => _send(req, 500, {'message': '$e'})));
    _gc = Timer.periodic(const Duration(minutes: 2), (_) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
      _jobs.removeWhere((_, j) => j.done && j.touched.isBefore(cutoff));
    });
  }

  @override
  Future<void> stop() async {
    _gc?.cancel();
    await _server?.close(force: true);
    _server = null;
  }

  /// LAN addresses to show the user ("type this on your phone").
  static Future<List<String>> lanAddresses() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final out = <String>[];
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) out.add(a.address);
        }
      }
      // Home networks first.
      out.sort((a, b) => (a.startsWith('192.168.') ? 0 : 1).compareTo(b.startsWith('192.168.') ? 0 : 1));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<RemoteInfo> info() async {
    final caps = engine.caps;
    final yt = engine.tools.where((t) => t.id == 'yt-dlp').firstOrNull;
    return RemoteInfo(
      name: Platform.localHostname,
      downloadDir: await downloadDir(),
      pathSeparator: engine.pathSeparator,
      hasFfmpeg: caps.hasFfmpeg,
      archivePath: await engine.archivePath(),
      jsRuntime: caps.jsRuntime,
      ffmpegLocation: caps.ffmpegLocation,
      tempDir: caps.tempDir,
      ytdlpVersion: yt?.version,
    );
  }

  bool _authorised(HttpRequest req) {
    final given = req.headers.value('x-haul-code') ?? req.uri.queryParameters['code'] ?? '';
    return given.isNotEmpty && normalizeCode(given) == normalizeCode(code());
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (!path.startsWith('/api/')) return _static(req);

    if (!_authorised(req)) {
      // Slow down guessing.
      _badAttempts++;
      await Future.delayed(Duration(milliseconds: 400 * _badAttempts.clamp(1, 10)));
      return _send(req, 401, {'message': 'Wrong code'});
    }
    _badAttempts = 0;

    final seg = req.uri.pathSegments.skip(1).toList();
    switch ((req.method, seg)) {
      case ('GET', ['hello']):
        return _send(req, 200, (await info()).toJson());

      case ('POST', ['jobs']):
        final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        final id = body['id'] as String? ?? '';
        final args = (body['args'] as List? ?? const []).cast<String>();
        if (id.isEmpty || id.length > 80) return _send(req, 400, {'message': 'Bad job id'});
        if (!engine.ready) return _send(req, 503, {'message': 'yt-dlp isn\'t set up on the computer yet'});
        try {
          validateRemoteArgs(args, await info());
        } on RemoteArgsError catch (e) {
          return _send(req, 400, {'message': e.message});
        }
        final job = _jobs[id] = _Job();
        unawaited(engine.run('remote-$id', args, onLine: job.lines.add).then((r) {
          // Engines that only hand back output at the end still get heard.
          if (job.lines.isEmpty && r.stdout.isNotEmpty) job.lines.addAll(const LineSplitter().convert(r.stdout));
          job
            ..done = true
            ..exitCode = r.exitCode
            ..stderr = r.stderr
            ..cancelled = r.cancelled
            ..touched = DateTime.now();
        }));
        return _send(req, 202, {'ok': true});

      case ('GET', ['jobs', final id]):
        final job = _jobs[id];
        if (job == null) return _send(req, 404, {'message': 'No such job'});
        job.touched = DateTime.now();
        final from = int.tryParse(req.uri.queryParameters['from'] ?? '') ?? 0;
        final start = from.clamp(0, job.lines.length);
        return _send(
          req,
          200,
          JobSnapshot(
            lines: job.lines.sublist(start),
            next: job.lines.length,
            done: job.done,
            exitCode: job.exitCode,
            stderr: job.done ? job.stderr : '',
            cancelled: job.cancelled,
          ).toJson(),
        );

      case ('DELETE', ['jobs', final id]):
        await engine.cancel('remote-$id');
        return _send(req, 200, {'ok': true});

      case ('POST', ['update']):
        return _send(req, 200, {'message': await engine.updateYtDlp()});

      case ('GET', ['file']):
        return _file(req);
    }
    return _send(req, 404, {'message': 'Not found'});
  }

  Future<void> _file(HttpRequest req) async {
    final requested = req.uri.queryParameters['path'] ?? '';
    final root = await Directory(await downloadDir()).resolveSymbolicLinks().catchError((_) => '');
    final file = File(requested);
    if (requested.isEmpty || root.isEmpty || !file.existsSync()) {
      return _send(req, 404, {'message': 'File not found'});
    }
    final real = await file.resolveSymbolicLinks();
    final sep = Platform.pathSeparator;
    if (!real.startsWith(root.endsWith(sep) ? root : '$root$sep')) {
      return _send(req, 403, {'message': 'Only files in the downloads folder'});
    }
    final name = real.split(sep).last;
    final length = await file.length();
    req.response
      ..statusCode = 200
      ..headers.contentType = _mime(name)
      ..headers.contentLength = length
      ..headers.set('Content-Disposition', 'attachment; filename="${name.replaceAll('"', '')}"; filename*=UTF-8\'\'${Uri.encodeComponent(name)}');
    // Files are already compressed; don't gzip a 2 GB video.
    req.response.headers.set(HttpHeaders.contentEncodingHeader, 'identity');
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  Future<void> _static(HttpRequest req) async {
    final root = webRoot;
    if (root == null || !Directory(root).existsSync()) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_noWebPage);
      return req.response.close();
    }
    var rel = req.uri.path == '/' ? '/index.html' : req.uri.path;
    if (rel.contains('..')) return _send(req, 400, {'message': 'Bad path'});
    var f = File('$root${rel.replaceAll('/', Platform.pathSeparator)}');
    if (!f.existsSync()) f = File('$root${Platform.pathSeparator}index.html'); // SPA fallback
    req.response
      ..statusCode = 200
      ..headers.contentType = _mime(f.path)
      ..headers.set(HttpHeaders.cacheControlHeader, rel == '/index.html' ? 'no-cache' : 'public, max-age=3600');
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  Future<void> _send(HttpRequest req, int status, Map<String, dynamic> body) async {
    try {
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(jsonEncode(body));
      await req.response.close();
    } catch (_) {}
  }

  static ContentType _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' => ContentType.json,
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'ico' => ContentType('image', 'x-icon'),
      'wasm' => ContentType('application', 'wasm'),
      'ttf' => ContentType('font', 'ttf'),
      'otf' => ContentType('font', 'otf'),
      'mp4' || 'm4v' => ContentType('video', 'mp4'),
      'webm' => ContentType('video', 'webm'),
      'mkv' => ContentType('video', 'x-matroska'),
      'mp3' => ContentType('audio', 'mpeg'),
      'm4a' => ContentType('audio', 'mp4'),
      'opus' || 'ogg' => ContentType('audio', 'ogg'),
      _ => ContentType.binary,
    };
  }

  static const _noWebPage = '''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Haul</title><body style="font-family:system-ui;max-width:420px;margin:15vh auto;padding:0 24px;color:#151515">
<h2>Haul is running here</h2><p>Open the Haul app on your phone and connect to this computer with the code shown in Haul's settings.</p></body>''';
}
