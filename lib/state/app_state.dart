import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import '../services/android_engine.dart';
import '../services/desktop_engine.dart';
import '../services/engine.dart';
import '../services/platform_bridge.dart';
import 'queue.dart';
import 'store.dart';

enum Phase { loading, setup, ready, unsupported }

/// The root of the app's state: settings, engine readiness and the queue.
class AppState extends ChangeNotifier {
  AppState({Engine? engine, PlatformBridge? bridge, Store? store})
      : engine = engine ?? _defaultEngine(),
        bridge = bridge ?? PlatformBridge(),
        _store = store ?? Store() {
    queue = QueueController(
      engine: this.engine,
      bridge: this.bridge,
      settings: () => _settings,
      downloadDir: resolvedDownloadDir,
      persist: _save,
    );
  }

  static Engine _defaultEngine() {
    if (kIsWeb) return UnsupportedEngine();
    if (Platform.isAndroid) return AndroidEngine();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return DesktopEngine();
    return UnsupportedEngine();
  }

  final Engine engine;
  final PlatformBridge bridge;
  final Store _store;
  late final QueueController queue;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  Phase _phase = Phase.loading;
  Phase get phase => _phase;

  String? _defaultDir;
  String get downloadDir => _settings.downloadDir ?? _defaultDir ?? '';

  Future<String> resolvedDownloadDir() async {
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

    await engine.detect();
    _defaultDir = await engine.defaultDownloadDir();

    if (engine.ready && (_settings.onboarded || engine.isMobile)) {
      _goReady();
    } else {
      _phase = Phase.setup;
      notifyListeners();
    }
  }

  void _goReady() {
    _phase = Phase.ready;
    if (!_settings.onboarded) update((s) => s.copyWith(onboarded: true));
    notifyListeners();
    bridge.ensurePermissions();
    queue.start();
  }

  /// Called from the setup screen once the essentials are in place.
  void finishSetup() {
    if (!engine.ready) return;
    _goReady();
  }

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
