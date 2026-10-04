import 'dart:async';
import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

import '../services/engine.dart';
import '../services/platform_bridge.dart';
import '../services/remote_engine.dart';
import '../services/remote_host.dart';
import '../state/store_base.dart';
import 'info.dart';

/// Web implementations of the platform layer. The web build is served by
/// Haul on a computer and drives that computer's engine.

KeyStore createStore() => _LocalStorageStore();

Engine createEngine() => RemoteEngine(mobile: isHandheld);

PlatformBridge createBridge() => _WebBridge();

bool get canHostRemote => false;

RemoteHost? createRemoteServer({required Engine engine, required String Function() code, required Future<String> Function() downloadDir}) =>
    null;

Future<List<String>> lanAddresses() async => const [];

Future<void> setupWindow() async {}

Future<void> ensureDir(String path) async {}

int? fileSize(String path) => null;

bool fileExists(String path) => false;

void deleteFiles(Iterable<String> paths) {}

Future<String?> readTextFile(String path, {int maxBytes = 20 * 1024 * 1024}) async => null;

ImageProvider? localImage(String path) => null;

String? homeDir() => null;

/// In a browser the "copy" is the browser's own download.
Future<String?> saveRemoteFile(Uri url, String name, void Function(double) onProgress) async {
  _download(url, name);
  onProgress(1);
  return null;
}

void _download(Uri url, String name) {
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url.toString()
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
}

class _WebBridge extends PlatformBridge {
  @override
  Future<void> openUrl(String url) async {
    web.window.open(url, '_blank', 'noopener');
  }

  @override
  Future<void> downloadInBrowser(Uri url, String name) async => _download(url, name);
}

class _LocalStorageStore implements KeyStore {
  static const _key = 'haul.state';
  Timer? _debounce;
  Map<String, dynamic> Function()? _pending;

  @override
  Future<Map<String, dynamic>> load() async {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null) return {};
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  @override
  void save(Map<String, dynamic> Function() snapshot) {
    _pending = snapshot;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), flush);
  }

  @override
  Future<void> flush() async {
    _debounce?.cancel();
    final snap = _pending;
    _pending = null;
    if (snap == null) return;
    try {
      web.window.localStorage.setItem(_key, jsonEncode(snap()));
    } catch (_) {}
  }
}
