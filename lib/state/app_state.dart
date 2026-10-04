import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/models.dart';
import '../core/remote_protocol.dart';
import '../platform/io.dart' as io;
import '../services/engine.dart';
import '../services/platform_bridge.dart';
import '../services/remote_engine.dart';
import '../services/remote_host.dart';
import 'queue.dart';
import 'store_base.dart';

enum Phase {
  loading,
  /// Desktop first run: fetch yt-dlp and friends.
  setup,
  /// iOS / web: pair with a computer first.
  connect,
  ready,
  unsupported,
}

/// The root of the app's state: settings, engine readiness and the queue.
class AppState extends ChangeNotifier {
  AppState({Engine? engine, PlatformBridge? bridge, KeyStore? store, this.webOrigin})
      : engine = engine ?? io.createEngine(),
        bridge = bridge ?? io.createBridge(),
        _store = store ?? io.createStore() {
    queue = QueueController(
      engine: this.engine,
      bridge: this.bridge,
      settings: () => _settings,
      downloadDir: resolvedDownloadDir,
      persist: _save,
    );
  }

  final Engine engine;
  final PlatformBridge bridge;
  final KeyStore _store;
  late final QueueController queue;

  /// When this app is a web page served by Haul on a computer, that
  /// computer's address (the page's own origin).
  final Uri? webOrigin;

  /// The phone side of remote mode, when that's how this device works.
  RemoteEngine? get remote => engine is RemoteEngine ? engine as RemoteEngine : null;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  Phase _phase = Phase.loading;
  Phase get phase => _phase;

  String? _defaultDir;
  String get downloadDir => remote != null ? (_defaultDir ?? '') : (_settings.downloadDir ?? _defaultDir ?? '');

  Future<String> resolvedDownloadDir() async {
    // A remote computer decides where its files go.
    if (remote != null) return remote!.defaultDownloadDir();
    if (_settings.downloadDir != null) return _settings.downloadDir!;
    return _defaultDir ??= await engine.defaultDownloadDir();
  }

  StreamSubscription<List<ToolInfo>>? _toolSub;

  Future<void> init() async {
    if (!engine.supported) {
      _phase = Phase.unsupported;
      notifyListeners();
      return;
    }
    final data = await _store.load();
    if (data['settings'] is Map<String, dynamic>) {
      _settings = Settings.fromJson(data['settings'] as Map<String, dynamic>);
    }
    if (data['items'] is List) queue.restore(data['items'] as List);

    _toolSub = engine.toolChanges.listen((_) {
      if (_phase == Phase.ready && engine.ready) queue.start();
      notifyListeners();
    });

    if (remote != null) return _initRemote();

    await engine.detect();
    _defaultDir = await engine.defaultDownloadDir();
    if (_settings.serverEnabled) unawaited(startServer());

    if (engine.ready && (_settings.onboarded || engine.isMobile)) {
      _goReady();
    } else {
      _phase = Phase.setup;
      notifyListeners();
    }
  }

  Uri? get _savedHost => webOrigin ?? (_settings.remoteHost == null ? null : parseHost(_settings.remoteHost!));

  Future<void> _initRemote() async {
    final r = remote!;
    final host = _savedHost;
    if (host != null && _settings.remoteCode != null) {
      await r.connect(host, _settings.remoteCode!);
      _defaultDir = await r.defaultDownloadDir();
    }
    if (r.ready) {
      _goReady();
    } else {
      _phase = Phase.connect;
      notifyListeners();
    }
  }

  /// Pair with a computer (iOS / web). Returns an error message or null.
  Future<String?> connect(String hostInput, String code) async {
    final r = remote;
    if (r == null) return 'Not available here';
    final host = webOrigin ?? parseHost(hostInput);
    if (host == null) return 'That doesn\'t look like an address. Try something like 192.168.1.20';
    final err = await r.connect(host, code);
    if (err != null) {
      notifyListeners();
      return err;
    }
    update((s) => s.copyWith(
          remoteHost: () => webOrigin == null ? host.authority : null,
          remoteCode: () => normalizeCode(code),
        ));
    _defaultDir = await r.defaultDownloadDir();
    _goReady();
    return null;
  }

  Future<void> disconnect() async {
    await queue.shutdown();
    remote?.disconnect();
    update((s) => s.copyWith(remoteHost: () => null, remoteCode: () => null));
    _phase = Phase.connect;
    notifyListeners();
  }

  void _goReady() {
    _phase = Phase.ready;
    if (!_settings.onboarded) update((s) => s.copyWith(onboarded: true));
    notifyListeners();
    queue.start();
  }

  /// Phones: the built-in engine failed to start; try again.
  Future<bool> retryEngine() async {
    await engine.install();
    if (engine.ready) {
      _defaultDir = await engine.defaultDownloadDir();
      _goReady();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Called from the setup screen once the essentials are in place.
  void finishSetup() {
    if (!engine.ready) return;
    _goReady();
  }

  // ───────────────────────── phone access (computer side) ─────────────────────────

  RemoteHost? _server;
  String? _serverError;
  String? get serverError => _serverError;
  bool get serverRunning => _server?.running ?? false;
  bool get canHostRemote => io.canHostRemote;

  String get serverCode {
    final c = _settings.serverCode;
    if (c != null) return c;
    final fresh = newPairingCode();
    _settings = _settings.copyWith(serverCode: fresh);
    _save();
    return fresh;
  }

  Future<void> startServer() async {
    if (!io.canHostRemote) return;
    _server ??= io.createRemoteServer(engine: engine, code: () => serverCode, downloadDir: resolvedDownloadDir);
    try {
      await _server?.start();
      _serverError = null;
    } catch (_) {
      _serverError = 'Port $remoteDefaultPort is in use. Is another copy of Haul running?';
      _server = null;
    }
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server?.stop();
    _server = null;
    notifyListeners();
  }

  Future<void> setServerEnabled(bool on) async {
    update((s) => s.copyWith(serverEnabled: on));
    on ? await startServer() : await stopServer();
  }

  void newServerCode() => update((s) => s.copyWith(serverCode: newPairingCode()));

  // ───────────────────────── settings ─────────────────────────

  void update(Settings Function(Settings s) change) {
    final before = _settings;
    _settings = change(_settings);
    notifyListeners();
    _save();
    if (before.concurrency != _settings.concurrency) queue.onSettingsChanged();
  }

  void _save() => _store.save(() => {
        'version': 1,
        'settings': _settings.toJson(),
        'items': queue.toJson(),
      });

  Future<void> flush() => _store.flush();

  /// App quitting: stop work (partials stay for resume), close the server.
  Future<void> shutdown() async {
    await queue.shutdown();
    await _server?.stop();
    await flush();
  }

  @override
  void dispose() {
    _toolSub?.cancel();
    queue.dispose();
    super.dispose();
  }
}

/// Makes [AppState] reachable from any widget without a package.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}

/// The queue changes many times a second while downloading; widgets that
/// show it subscribe here, so settings-only widgets (and MaterialApp)
/// don't rebuild on every progress tick.
class QueueScope extends InheritedNotifier<QueueController> {
  const QueueScope({super.key, required QueueController queue, required super.child}) : super(notifier: queue);

  static QueueController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QueueScope>()!.notifier!;
}
