import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ytdlp.dart';
import 'engine.dart';

/// Runs yt-dlp as a child process on macOS, Windows and Linux.
///
/// Haul keeps its own copies of yt-dlp, ffmpeg and deno in the app support
/// folder so nothing needs to be installed by hand, but happily uses tools
/// already on the system when they're there.
class DesktopEngine extends Engine {
  DesktopEngine();

  late final Directory _support;
  late final Directory _bin;
  final _processes = <String, Process>{};
  final _cancelled = <String>{};
  final _toolCtrl = StreamController<List<ToolInfo>>.broadcast();

  String? _ytdlp;
  String? _ffmpeg;
  String? _js;
  String? _jsKind;

  var _tools = <ToolInfo>[
    const ToolInfo(
      id: 'yt-dlp',
      name: 'yt-dlp',
      purpose: 'The engine that finds and downloads videos',
      state: ToolState.missing,
      required: true,
      sizeHint: '~35 MB',
    ),
    const ToolInfo(
      id: 'ffmpeg',
      name: 'ffmpeg',
      purpose: 'Joins HD video with audio, makes MP3s',
      state: ToolState.missing,
      sizeHint: '~80 MB',
    ),
    const ToolInfo(
      id: 'deno',
      name: 'JavaScript runtime',
      purpose: 'Unlocks every YouTube quality',
      state: ToolState.missing,
      sizeHint: '~40 MB',
    ),
  ];

  @override
  bool get isMobile => false;

  @override
  String get pathSeparator => Platform.pathSeparator;

  @override
  List<ToolInfo> get tools => _tools;

  @override
  Stream<List<ToolInfo>> get toolChanges => _toolCtrl.stream;

  @override
  bool get ready => _ytdlp != null;

  @override
  EngineCaps get caps => EngineCaps(
        hasFfmpeg: _ffmpeg != null,
        ffmpegLocation: _ffmpeg,
        jsRuntime: _js == null ? null : '$_jsKind:$_js',
        tempDir: '${_support.path}${Platform.pathSeparator}partial',
      );

  void _set(String id, ToolInfo Function(ToolInfo t) f) {
    _tools = [for (final t in _tools) t.id == id ? f(t) : t];
    _toolCtrl.add(_tools);
  }

  String _exe(String name) => Platform.isWindows ? '$name.exe' : name;
  String _managed(String name) => '${_bin.path}${Platform.pathSeparator}${_exe(name)}';

  // ───────────────────────── discovery ─────────────────────────

  bool _initialised = false;

  Future<void> _init() async {
    if (_initialised) return;
    _support = await getApplicationSupportDirectory();
    _bin = Directory('${_support.path}${Platform.pathSeparator}bin');
    await _bin.create(recursive: true);
    _initialised = true;
  }

  /// GUI apps on macOS don't inherit the shell PATH, so look in the usual
  /// package-manager spots too.
  List<String> get _searchDirs {
    final sep = Platform.isWindows ? ';' : ':';
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    return [
      ...?Platform.environment['PATH']?.split(sep),
      if (!Platform.isWindows) ...[
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
        '/snap/bin',
        '$home/.local/bin',
        '$home/.deno/bin',
        '$home/.bun/bin',
      ] else ...[
        '$home\\.deno\\bin',
        '$home\\scoop\\shims',
      ],
    ].where((d) => d.isNotEmpty).toList();
  }

  String? _which(String name) {
    for (final dir in _searchDirs) {
      final f = File('$dir${Platform.pathSeparator}${_exe(name)}');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<String?> _version(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8)
          .timeout(const Duration(seconds: 20));
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).trim();
      return out.isEmpty ? '' : const LineSplitter().convert(out).first.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> detect() async {
    await _init();

    // yt-dlp: our own copy first (we can keep it fresh), then the system's.
    for (final (path, managed) in [(_managed('yt-dlp'), true), (_which('yt-dlp'), false)]) {
      if (path == null || !File(path).existsSync()) continue;
      final v = await _version(path, ['--version']);
      if (v != null) {
        _ytdlp = path;
        _set('yt-dlp', (t) => t.copyWith(state: ToolState.ready, version: v, location: path, managed: managed));
        break;
      }
    }

    for (final (path, managed) in [(_managed('ffmpeg'), true), (_which('ffmpeg'), false)]) {
      if (path == null || !File(path).existsSync()) continue;
      final v = await _version(path, ['-version']);
      if (v != null) {
        _ffmpeg = path;
        final short = RegExp(r'ffmpeg version (\S+)').firstMatch(v)?.group(1) ?? v;
        _set('ffmpeg', (t) => t.copyWith(state: ToolState.ready, version: short, location: path, managed: managed));
        break;
      }
    }

    // Any JS runtime yt-dlp understands will do for YouTube.
    for (final (kind, path, managed) in [
      ('deno', _managed('deno'), true),
      ('deno', _which('deno'), false),
      ('node', _which('node'), false),
      ('bun', _which('bun'), false),
    ]) {
      if (path == null || !File(path).existsSync()) continue;
      final v = await _version(path, ['--version']);
      if (v != null) {
        _js = path;
        _jsKind = kind;
        final label = kind == 'deno' ? 'Deno ${v.replaceFirst('deno ', '').split(' ').first}' : '${kind[0].toUpperCase()}${kind.substring(1)} ${v.replaceFirst('v', '')}';
        _set('deno', (t) => t.copyWith(state: ToolState.ready, version: label, location: path, managed: managed));
        break;
      }
    }
  }

  // ───────────────────────── installing ─────────────────────────

  Abi get _abi => Abi.current();
  bool get _arm => _abi == Abi.macosArm64 || _abi == Abi.linuxArm64 || _abi == Abi.windowsArm64;

  String get _ytdlpUrl {
    const base = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download';
    if (Platform.isWindows) return '$base/yt-dlp.exe';
    if (Platform.isMacOS) return '$base/yt-dlp_macos';
    return _arm ? '$base/yt-dlp_linux_aarch64' : '$base/yt-dlp_linux';
  }

  @override
  Future<void> install({bool extras = true}) async {
    await _init();
    if (_ytdlp == null) await installTool('yt-dlp');
    if (!extras) return;
    // Independent downloads — do them side by side.
    await Future.wait([
      if (_ffmpeg == null) installTool('ffmpeg'),
      if (_js == null) installTool('deno'),
    ]);
  }

  @override
  Future<void> installTool(String id) async {
    await _init();
    _set(id, (t) => t.copyWith(state: ToolState.installing, progress: 0));
    try {
      switch (id) {
        case 'yt-dlp':
          await _installYtDlp();
        case 'ffmpeg':
          await _installFfmpeg();
        case 'deno':
          await _installDeno();
      }
      await detect();
      final t = _tools.firstWhere((t) => t.id == id);
      if (t.state != ToolState.ready) {
        _set(id, (t) => t.copyWith(state: ToolState.failed, error: 'Installed, but it wouldn\'t start.'));
      }
    } catch (e) {
      _set(id, (t) => t.copyWith(state: ToolState.failed, error: _describe(e)));
    }
  }

  String _describe(Object e) {
    if (e is SocketException || e is HttpException || e is TimeoutException) {
      return 'Couldn\'t download. Check your connection.';
    }
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 119)}…' : s;
  }

  Future<void> _installYtDlp() async {
    final dest = _managed('yt-dlp');
    await _download(_ytdlpUrl, '$dest.download', (p) => _set('yt-dlp', (t) => t.copyWith(progress: p)));
    await _finalise('$dest.download', dest);
  }

  Future<void> _installFfmpeg() async {
    final tmp = await Directory('${_support.path}${Platform.pathSeparator}tmp').create(recursive: true);
    void progress(double p) => _set('ffmpeg', (t) => t.copyWith(progress: p));

    if (Platform.isMacOS) {
      final arch = _arm ? 'arm64' : 'amd64';
      for (final (i, name) in ['ffmpeg', 'ffprobe'].indexed) {
        final zip = '${tmp.path}/$name.zip';
        await _download('https://ffmpeg.martin-riedl.de/redirect/latest/macos/$arch/release/$name.zip', zip,
            (p) => progress((i + p) / 2));
        await _extractZip(zip, {name: _managed(name)});
        await File(zip).delete();
      }
      return;
    }

    const base = 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest';
    if (Platform.isWindows) {
      final zip = '${tmp.path}\\ffmpeg.zip';
      final build = _arm ? 'winarm64' : 'win64';
      await _download('$base/ffmpeg-master-latest-$build-gpl.zip', zip, progress);
      await _extractZip(zip, {'ffmpeg.exe': _managed('ffmpeg'), 'ffprobe.exe': _managed('ffprobe')});
      await File(zip).delete();
      return;
    }

    final archive = '${tmp.path}/ffmpeg.tar.xz';
    final build = _arm ? 'linuxarm64' : 'linux64';
    await _download('$base/ffmpeg-master-latest-$build-gpl.tar.xz', archive, progress);
    final out = await Directory('${tmp.path}/ffmpeg').create(recursive: true);
    final r = await Process.run('tar', ['-xJf', archive, '-C', out.path]);
    if (r.exitCode != 0) throw Exception('Couldn\'t unpack ffmpeg: ${r.stderr}');
    for (final name in ['ffmpeg', 'ffprobe']) {
      final found = out
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('/bin/$name'), orElse: () => throw Exception('$name missing from archive'));
      await _finalise(found.path, _managed(name), move: true);
    }
    await out.delete(recursive: true);
    await File(archive).delete();
  }

  Future<void> _installDeno() async {
    final target = switch (_abi) {
      Abi.macosArm64 => 'aarch64-apple-darwin',
      Abi.macosX64 => 'x86_64-apple-darwin',
      Abi.linuxArm64 => 'aarch64-unknown-linux-gnu',
      Abi.windowsX64 || Abi.windowsArm64 => 'x86_64-pc-windows-msvc',
      _ => 'x86_64-unknown-linux-gnu',
    };
    final tmp = await Directory('${_support.path}${Platform.pathSeparator}tmp').create(recursive: true);
    final zip = '${tmp.path}${Platform.pathSeparator}deno.zip';
    await _download('https://github.com/denoland/deno/releases/latest/download/deno-$target.zip', zip,
        (p) => _set('deno', (t) => t.copyWith(progress: p)));
    await _extractZip(zip, {_exe('deno'): _managed('deno')});
    await File(zip).delete();
  }

  Future<void> _extractZip(String zipPath, Map<String, String> wanted) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final base = entry.name.split('/').last;
        final dest = wanted[base];
        if (dest == null) continue;
        final out = OutputFileStream('$dest.download');
        entry.writeContent(out);
        await out.close();
        await _finalise('$dest.download', dest);
      }
    } finally {
      await input.close();
    }
    for (final dest in wanted.values) {
      if (!File(dest).existsSync()) throw Exception('${dest.split(Platform.pathSeparator).last} missing from archive');
    }
  }

  Future<void> _finalise(String from, String to, {bool move = false}) async {
    final target = File(to);
    if (target.existsSync()) await target.delete();
    if (move) {
      await File(from).copy(to);
      await File(from).delete();
    } else {
      await File(from).rename(to);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', to]);
    }
    if (Platform.isMacOS) {
      await Process.run('xattr', ['-d', 'com.apple.quarantine', to]);
    }
  }

  Future<void> _download(String url, String dest, void Function(double) onProgress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Haul');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} for $url');
      final total = res.contentLength;
      final sink = File(dest).openWrite();
      var received = 0;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (total > 0 && now.difference(lastReport).inMilliseconds > 100) {
          lastReport = now;
          onProgress(received / total);
        }
      }
      await sink.close();
      onProgress(1);
    } finally {
      client.close(force: true);
    }
  }

  // ───────────────────────── running ─────────────────────────

  @override
  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine}) async {
    final exe = _ytdlp;
    if (exe == null) {
      return const RunResult(exitCode: 127, stdout: '', stderr: 'ERROR: yt-dlp isn\'t installed yet.');
    }
    _cancelled.remove(jobId);
    final process = await Process.start(
      exe,
      args,
      environment: const {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'},
    );
    _processes[jobId] = process;

    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
      out.writeln(line);
      onLine?.call(line);
    });
    final errDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(err.write);

    final code = await process.exitCode;
    await Future.wait([outDone, errDone]);
    _processes.remove(jobId);
    return RunResult(
      exitCode: code,
      stdout: out.toString(),
      stderr: err.toString(),
      cancelled: _cancelled.remove(jobId),
    );
  }

  @override
  Future<void> cancel(String jobId) async {
    final p = _processes[jobId];
    if (p == null) return;
    _cancelled.add(jobId);
    if (Platform.isWindows) {
      // The standalone yt-dlp.exe is a launcher with a child process;
      // kill the whole tree or the download keeps going.
      await Process.run('taskkill', ['/pid', '${p.pid}', '/t', '/f']);
    } else {
      p.kill(ProcessSignal.sigterm);
      Future.delayed(const Duration(seconds: 4), () => p.kill(ProcessSignal.sigkill));
    }
  }

  @override
  Future<String> updateYtDlp() async {
    await _init();
    final t = _tools.firstWhere((t) => t.id == 'yt-dlp');
    if (_ytdlp == null || !t.managed) {
      await installTool('yt-dlp');
      final now = _tools.firstWhere((t) => t.id == 'yt-dlp');
      return now.state == ToolState.ready ? 'Installed yt-dlp ${now.version}' : (now.error ?? 'Couldn\'t install yt-dlp');
    }
    _set('yt-dlp', (t) => t.copyWith(state: ToolState.installing));
    final r = await Process.run(_ytdlp!, ['-U'], stdoutEncoding: utf8, stderrEncoding: utf8);
    await detect();
    final v = _tools.firstWhere((t) => t.id == 'yt-dlp').version;
    final text = '${r.stdout}\n${r.stderr}';
    if (text.contains('up to date')) return 'Already on the latest version ($v)';
    if (r.exitCode == 0) return 'Updated to $v';
    return cleanError(r.stderr as String).isEmpty ? 'Update failed' : cleanError(r.stderr as String);
  }

  @override
  Future<String> defaultDownloadDir() async {
    final dl = await getDownloadsDirectory();
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final base = dl?.path ?? '$home${Platform.pathSeparator}Downloads';
    return '$base${Platform.pathSeparator}Haul';
  }

  @override
  Future<String?> archivePath() async {
    await _init();
    return '${_support.path}${Platform.pathSeparator}archive.txt';
  }
}
