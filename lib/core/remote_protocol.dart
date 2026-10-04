/// The phone ⇄ computer protocol: a phone (or any browser) drives the
/// queue, the computer runs yt-dlp. Pure Dart, shared by both ends.
library;

import 'dart:math';

const remoteDefaultPort = 8642;
const remoteApiVersion = 1;

/// Unambiguous characters only — easy to read off a screen and type.
const _codeAlphabet = 'ACDEFGHJKMNPQRTUVWXY34679';

String newPairingCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)]).join();
}

String normalizeCode(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// "192.168.1.20", "192.168.1.20:8642", "http://pc.local:9000/" → base uri.
Uri? parseHost(String input) {
  var t = input.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'http://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty) return null;
  return Uri(scheme: u.scheme == 'https' ? 'https' : 'http', host: u.host, port: u.hasPort ? u.port : remoteDefaultPort);
}

/// What the computer's engine looks like, sent to a connecting phone so it
/// can build arguments that are valid *there*.
class RemoteInfo {
  const RemoteInfo({
    required this.name,
    required this.downloadDir,
    required this.pathSeparator,
    required this.hasFfmpeg,
    this.archivePath,
    this.jsRuntime,
    this.ffmpegLocation,
    this.tempDir,
    this.ytdlpVersion,
    this.apiVersion = remoteApiVersion,
  });

  final String name;
  final String downloadDir;
  final String pathSeparator;
  final bool hasFfmpeg;
  final String? archivePath;
  final String? jsRuntime;
  final String? ffmpegLocation;
  final String? tempDir;
  final String? ytdlpVersion;
  final int apiVersion;

  Map<String, dynamic> toJson() => {
        'name': name,
        'downloadDir': downloadDir,
        'pathSeparator': pathSeparator,
        'hasFfmpeg': hasFfmpeg,
        'archivePath': archivePath,
        'jsRuntime': jsRuntime,
        'ffmpegLocation': ffmpegLocation,
        'tempDir': tempDir,
        'ytdlpVersion': ytdlpVersion,
        'apiVersion': apiVersion,
      };

  static RemoteInfo fromJson(Map<String, dynamic> j) => RemoteInfo(
        name: j['name'] as String? ?? 'Computer',
        downloadDir: j['downloadDir'] as String? ?? '',
        pathSeparator: j['pathSeparator'] as String? ?? '/',
        hasFfmpeg: j['hasFfmpeg'] as bool? ?? false,
        archivePath: j['archivePath'] as String?,
        jsRuntime: j['jsRuntime'] as String?,
        ffmpegLocation: j['ffmpegLocation'] as String?,
        tempDir: j['tempDir'] as String?,
        ytdlpVersion: j['ytdlpVersion'] as String?,
        apiVersion: j['apiVersion'] as int? ?? 1,
      );
}

/// Options Haul itself generates (see `ytdlp.dart`). Anything else from a
/// remote client is refused — notably `--exec`, `--config-location`,
/// `--batch-file` or `--plugin-dirs`, which could run code on the computer.
const _flags = {
  '-J', '--flat-playlist', '--no-playlist', '--no-warnings', '--newline', '--no-quiet', '--progress',
  '--no-simulate', '--no-mtime', '--continue', '-x', '--embed-metadata', '--embed-thumbnail',
  '--write-subs', '--embed-subs',
};

const _freeValue = {
  '-f', '-S', '--merge-output-format', '--remux-video', '--audio-format', '--audio-quality',
  '--retries', '--fragment-retries', '--concurrent-fragments', '--sub-langs', '--encoding',
};

const _browsers = {'chrome', 'firefox', 'safari', 'edge', 'brave', 'chromium', 'opera', 'vivaldi'};

class RemoteArgsError implements Exception {
  RemoteArgsError(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _within(String path, String root, String sep) {
  if (path.contains('..')) return false;
  final r = root.endsWith(sep) ? root : '$root$sep';
  return path == root || path.startsWith(r);
}

/// Throws [RemoteArgsError] unless [args] is something Haul would have
/// built for *this* computer.
void validateRemoteArgs(List<String> args, RemoteInfo info) {
  var positional = 0;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value() {
      if (i + 1 >= args.length) throw RemoteArgsError('Missing value for $a');
      return args[++i];
    }

    if (!a.startsWith('-')) {
      final u = Uri.tryParse(a);
      if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
        throw RemoteArgsError('Not a web link: $a');
      }
      if (++positional > 1) throw RemoteArgsError('One link per job');
      continue;
    }
    if (_flags.contains(a)) continue;
    if (_freeValue.contains(a)) {
      final v = value();
      if (v.startsWith('-') && a != '-S') throw RemoteArgsError('Bad value for $a');
      continue;
    }
    switch (a) {
      case '--progress-template':
        if (!value().startsWith('download:HAUL|')) throw RemoteArgsError('Bad progress template');
      case '--print':
        final v = value();
        if (!(v.startsWith('video:HAUL') || v.startsWith('after_move:HAUL'))) throw RemoteArgsError('Bad print template');
      case '-o':
        final v = value();
        if (v.contains('/') || v.contains('\\') || v.contains('..') || v.contains(':')) {
          throw RemoteArgsError('File names only, no paths');
        }
      case '-P':
        final v = value();
        if (v.startsWith('temp:')) {
          if (info.tempDir == null || v.substring(5) != info.tempDir) throw RemoteArgsError('Bad temp folder');
        } else if (!_within(v, info.downloadDir, info.pathSeparator)) {
          throw RemoteArgsError('Downloads must stay in ${info.downloadDir}');
        }
      case '--download-archive':
        if (value() != info.archivePath) throw RemoteArgsError('Bad archive');
      case '--ffmpeg-location':
        if (value() != info.ffmpegLocation) throw RemoteArgsError('Bad ffmpeg location');
      case '--js-runtimes':
        if (value() != info.jsRuntime) throw RemoteArgsError('Bad JS runtime');
      case '--remote-components':
        if (value() != 'ejs:github') throw RemoteArgsError('Bad component');
      case '--cookies-from-browser':
        if (!_browsers.contains(value())) throw RemoteArgsError('Unknown browser');
      default:
        throw RemoteArgsError('Option not allowed: $a');
    }
  }
  if (positional != 1) throw RemoteArgsError('Exactly one link per job');
}

/// One poll's worth of a job's output.
class JobSnapshot {
  const JobSnapshot({required this.lines, required this.next, required this.done, this.exitCode, this.stderr = '', this.cancelled = false});
  final List<String> lines;
  final int next;
  final bool done;
  final int? exitCode;
  final String stderr;
  final bool cancelled;

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'next': next,
        'done': done,
        'exitCode': exitCode,
        'stderr': stderr,
        'cancelled': cancelled,
      };

  static JobSnapshot fromJson(Map<String, dynamic> j) => JobSnapshot(
        lines: (j['lines'] as List? ?? const []).cast<String>(),
        next: j['next'] as int? ?? 0,
        done: j['done'] as bool? ?? false,
        exitCode: j['exitCode'] as int?,
        stderr: j['stderr'] as String? ?? '',
        cancelled: j['cancelled'] as bool? ?? false,
      );
}
