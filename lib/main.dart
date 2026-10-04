import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/io.dart' as io;
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await io.setupWindow();

  // On the web, Haul is served by a computer running Haul: talk to it.
  final state = AppState(
    webOrigin: kIsWeb ? Uri(scheme: Uri.base.scheme, host: Uri.base.host, port: Uri.base.port) : null,
  );
  runApp(HaulApp(state: state));
  // Load and probe tools after the first frame so the window paints at once.
  state.init();

  // Don't leave yt-dlp processes or unsaved state behind on quit.
  AppLifecycleListener(
    onExitRequested: () async {
      await state.shutdown();
      return AppExitResponse.exit;
    },
    onStateChange: (s) {
      if (s == AppLifecycleState.paused || s == AppLifecycleState.detached || s == AppLifecycleState.hidden) {
        state.flush();
      }
    },
  );
}
