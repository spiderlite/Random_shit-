import 'dart:async';

import 'package:flutter/services.dart';

import '../platform/info.dart';

/// OS integration that isn't about yt-dlp itself: opening and sharing
/// files, the Android share sheet, the background-download notification.
///
/// This base class talks to the native side over a channel (Android, iOS)
/// and compiles everywhere; desktop and web subclasses fill in the rest.
class PlatformBridge {
  static const _channel = MethodChannel('haul/platform');
  final _shared = StreamController<String>.broadcast();
  bool _listening = false;

  /// Starts receiving shares from the native side (lazily, once the
  /// binding exists).
  void _listen() {
    if (_listening || !(isAndroid || isIOS)) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        _shared.add(call.arguments as String);
      }
    });
  }

  bool get _mobileNative => isAndroid || isIOS;

  /// Text other apps shared to Haul ("Share → Haul").
  Stream<String> get sharedText {
    _listen();
    return _shared.stream;
  }

  /// Text shared before Flutter was listening (cold start from share).
  Future<String?> takeInitialShare() async {
    if (!_mobileNative) return null;
    _listen();
    try {
      return await _channel.invokeMethod<String>('takeInitialShare');
    } catch (_) {
      return null;
    }
  }

  /// Makes a finished file visible to galleries / file managers.
  /// Returns a content:// uri usable for open and share.
  Future<String?> publishFile(String path) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('scanFile', {'path': path});
    } catch (_) {
      return null;
    }
  }

  Future<bool> openFile(String path, {String? contentUri}) async {
    if (!_mobileNative) return false;
    try {
      return await _channel.invokeMethod<bool>('openFile', {'path': path, 'uri': contentUri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Desktop only: highlight the file in Finder / Explorer / Files.
  Future<bool> revealFile(String path) async => false;

  Future<bool> openFolder(String dir) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openDownloads') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> shareFile(String path, {String? contentUri, String? title}) async {
    if (!_mobileNative) return;
    try {
      await _channel.invokeMethod('shareFile', {'path': path, 'uri': contentUri, 'title': title});
    } catch (_) {}
  }

  Future<void> openUrl(String url) async {
    if (!_mobileNative) return;
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (_) {}
  }

  /// Web: hand a file to the browser's own downloader.
  Future<void> downloadInBrowser(Uri url, String name) async {}

  /// Android: keeps downloads alive in the background with a quiet
  /// progress notification. `active == 0` stops it.
  Future<void> updateBackgroundWork({required int active, required int queued, double? progress, String? title}) async {
    if (!isAndroid) return;
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
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('ensurePermissions') ?? true;
    } catch (_) {
      return true;
    }
  }
}
