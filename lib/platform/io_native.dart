import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/android_engine.dart';
import '../services/desktop_engine.dart';
import '../services/engine.dart';
import '../services/platform_bridge.dart';
import '../services/remote_engine.dart';
import '../services/remote_server.dart';
import '../state/store.dart';
import '../state/store_base.dart';

/// Native (dart:io) implementations of the platform layer.

KeyStore createStore() => Store();

Engine createEngine() {
  if (Platform.isAndroid) return AndroidEngine();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return DesktopEngine();
  // iOS can't run yt-dlp itself — it drives a computer instead.
  return RemoteEngine(mobile: true);
}

PlatformBridge createBridge() =>
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ? DesktopBridge() : PlatformBridge();

bool get canHostRemote => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

RemoteServer? createRemoteServer({
  required Engine engine,
  required String Function() code,
  required Future<String> Function() downloadDir,
}) {
  if (!canHostRemote) return null;
  return RemoteServer(engine: engine, code: code, downloadDir: downloadDir, webRoot: bundledWebRoot());
}

Future<List<String>> lanAddresses() => RemoteServer.lanAddresses();

/// The Flutter web build shipped next to the desktop app (see CI).
String? bundledWebRoot() {
  final exe = File(Platform.resolvedExecutable).parent.path;
  final sep = Platform.pathSeparator;
  final candidates = [
    '$exe${sep}web',
    // macOS: Haul.app/Contents/MacOS/Haul → Contents/Resources/web
    '${File(exe).parent.path}${sep}Resources${sep}web',
    // Running from a source checkout.
    '${Directory.current.path}${sep}build${sep}web',
  ];
  for (final c in candidates) {
    if (File('$c${sep}index.html').existsSync()) return c;
  }
  return null;
}

Future<void> setupWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'Haul', size: Size(1000, 760), minimumSize: Size(400, 560), center: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

Future<void> ensureDir(String path) async {
  try {
    await Directory(path).create(recursive: true);
  } catch (_) {}
}

int? fileSize(String path) {
  try {
    return File(path).lengthSync();
  } catch (_) {
    return null;
  }
}

bool fileExists(String path) => File(path).existsSync();

void deleteFiles(Iterable<String> paths) {
  for (final p in paths) {
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// Reads a dropped/opened text file, ignoring anything too large to be a
/// list of links.
Future<String?> readTextFile(String path, {int maxBytes = 20 * 1024 * 1024}) async {
  try {
    final f = File(path);
    if (await f.length() > maxBytes) return null;
    return utf8.decode(await f.readAsBytes(), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

ImageProvider? localImage(String path) => FileImage(File(path.replaceFirst('file://', '')));

String? homeDir() => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

/// Remote mode: copy a finished file from the computer onto this device.
/// iOS: the app's Documents (visible in the Files app under "Haul").
/// Android: Download/Haul. Returns the local path.
Future<String?> saveRemoteFile(Uri url, String name, void Function(double) onProgress) async {
  final Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download/Haul');
  } else {
    dir = Directory('${(await getApplicationDocumentsDirectory()).path}/Haul');
  }
  await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[/\\:]'), '_');
  final dest = File('${dir.path}/$safe');
  final part = File('${dest.path}.part');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final total = res.contentLength;
    final sink = part.openWrite();
    var got = 0;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      final now = DateTime.now();
      if (total > 0 && now.difference(last).inMilliseconds > 150) {
        last = now;
        onProgress(got / total);
      }
    }
    await sink.close();
    if (dest.existsSync()) await dest.delete();
    await part.rename(dest.path);
    onProgress(1);
    return dest.path;
  } catch (_) {
    try {
      if (part.existsSync()) await part.delete();
    } catch (_) {}
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Opening, revealing and URLs on macOS, Windows and Linux.
class DesktopBridge extends PlatformBridge {
  @override
  Future<bool> openFile(String path, {String? contentUri}) async {
    try {
      if (Platform.isMacOS) return (await Process.run('open', [path])).exitCode == 0;
      if (Platform.isWindows) return (await Process.run('cmd', ['/c', 'start', '', path])).exitCode == 0;
      return (await Process.run('xdg-open', [path])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> revealFile(String path) async {
    try {
      if (Platform.isMacOS) return (await Process.run('open', ['-R', path])).exitCode == 0;
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
        return true; // explorer.exe returns 1 even on success
      }
      // Ask the file manager to highlight the file; fall back to the folder.
      final r = await Process.run('dbus-send', [
        '--session', '--dest=org.freedesktop.FileManager1', '--type=method_call',
        '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1.ShowItems',
        'array:string:${Uri.file(path)}', 'string:',
      ]);
      if (r.exitCode == 0) return true;
      return (await Process.run('xdg-open', [File(path).parent.path])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openFolder(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      if (Platform.isMacOS) return (await Process.run('open', [dir])).exitCode == 0;
      if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
        return true;
      }
      return (await Process.run('xdg-open', [dir])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }
}
