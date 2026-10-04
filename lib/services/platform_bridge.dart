import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// OS integration that isn't about yt-dlp itself: opening files, the
/// Android share sheet, the background-download notification.
class PlatformBridge {
  PlatformBridge() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sharedText' && call.arguments is String) {
          _shared.add(call.arguments as String);
        }
      });
    }
  }

  static const _channel = MethodChannel('haul/platform');
  final _shared = StreamController<String>.broadcast();

  /// Text other apps shared to Haul (Android "Share → Haul").
  Stream<String> get sharedText => _shared.stream;

  /// Text shared before Flutter was listening (cold start from share).
  Future<String?> takeInitialShare() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeInitialShare');
    } catch (_) {
      return null;
    }
  }

  /// Makes a finished file visible to galleries / file managers.
  /// Returns a content:// uri usable for open and share.
  Future<String?> publishFile(String path) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('scanFile', {'path': path});
    } catch (_) {
      return null;
    }
  }

  Future<bool> openFile(String path, {String? contentUri}) async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('openFile', {'path': path, 'uri': contentUri}) ?? false;
      }
      if (Platform.isMacOS) return (await Process.run('open', [path])).exitCode == 0;
      if (Platform.isWindows) return (await Process.run('cmd', ['/c', 'start', '', path])).exitCode == 0;
      return (await Process.run('xdg-open', [path])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> revealFile(String path) async {
    try {
      if (Platform.isMacOS) return (await Process.run('open', ['-R', path])).exitCode == 0;
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
        return true; // explorer.exe returns 1 even on success
      }
      if (Platform.isLinux) {
        // Ask the file manager to highlight the file; fall back to the folder.
        final r = await Process.run('dbus-send', [
          '--session', '--dest=org.freedesktop.FileManager1', '--type=method_call',
          '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1.ShowItems',
          'array:string:${Uri.file(path)}', 'string:',
        ]);
        if (r.exitCode == 0) return true;
        return (await Process.run('xdg-open', [File(path).parent.path])).exitCode == 0;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> openFolder(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      if (Platform.isAndroid) return await _channel.invokeMethod<bool>('openDownloads') ?? false;
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

  Future<void> shareFile(String path, {String? contentUri, String? title}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('shareFile', {'path': path, 'uri': contentUri, 'title': title});
  }

  Future<void> openUrl(String url) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('openUrl', {'url': url});
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  /// Android: keeps downloads alive in the background with a quiet
  /// progress notification. `active == 0` stops it.
  Future<void> updateBackgroundWork({required int active, required int queued, double? progress, String? title}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('background', {
        'active': active,
        'queued': queued,
        'progress': progress,
        'title': title,
      });
    } catch (_) {}
  }

  /// Android 13+ asks before showing notifications; older storage asks
  /// before writing to Downloads. Returns whether we may write.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('ensurePermissions') ?? true;
    } catch (_) {
      return true;
    }
  }
}
