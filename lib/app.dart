import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/models.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/setup/connect_screen.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/widgets/toast.dart';

class HaulApp extends StatelessWidget {
  const HaulApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: QueueScope(
        queue: state.queue,
        child: Builder(
        builder: (context) {
          final theme = AppScope.of(context).settings.theme;
          return MaterialApp(
            title: 'Haul',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: switch (theme) {
              ThemePref.system => ThemeMode.system,
              ThemePref.light => ThemeMode.light,
              ThemePref.dark => ThemeMode.dark,
            },
            themeAnimationDuration: Motion.slow,
            themeAnimationCurve: Motion.ease,
            builder: (context, child) {
              final dark = Theme.of(context).brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: context.palette.bg,
                ),
                child: ToastHost(child: child!),
              );
            },
            home: const _Root(),
          );
        },
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final phase = AppScope.of(context).phase;
    return AnimatedSwitcher(
      duration: Motion.slow,
      switchInCurve: Motion.ease,
      switchOutCurve: Motion.easeIn,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(a), child: child),
      ),
      child: switch (phase) {
        Phase.loading => const LoadingScreen(key: ValueKey('loading')),
        Phase.setup => const SetupScreen(key: ValueKey('setup')),
        Phase.connect => const ConnectScreen(key: ValueKey('connect')),
        Phase.ready => const HomeScreen(key: ValueKey('home')),
        Phase.unsupported => const UnsupportedScreen(key: ValueKey('unsupported')),
      },
    );
  }
}
