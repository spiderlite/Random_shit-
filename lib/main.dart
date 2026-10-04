import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final desktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Haul',
        size: Size(1000, 760),
        minimumSize: Size(400, 560),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final state = AppState();
  runApp(HaulApp(state: state));
  // Load and probe tools after the first frame so the window paints at once.
  state.init();

  // Don't leave yt-dlp processes or unsaved state behind on quit.
  AppLifecycleListener(
    onExitRequested: () async {
      await state.queue.shutdown();
      await state.flush();
      return AppExitResponse.exit;
    },
    onStateChange: (s) {
      if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) state.flush();
    },
  );
}
