import 'package:flutter/material.dart';

import '../../services/engine.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';

/// Desktop first run: fetch yt-dlp (+ optional helpers) once, with a clear
/// picture of what's happening and why.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _running = false;

  Future<void> _go({required bool extras}) async {
    final app = AppScope.read(context);
    setState(() => _running = true);
    await app.engine.install(extras: extras);
    if (!mounted) return;
    setState(() => _running = false);
    if (app.engine.ready && app.engine.tools.every((t) => t.state == ToolState.ready || !extras)) {
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) app.finishSetup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tools = app.engine.tools;
    final p = context.palette;
    final ready = app.engine.ready;
    final allReady = tools.every((t) => t.state == ToolState.ready);
    final anyFailed = tools.any((t) => t.state == ToolState.failed);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HaulMark(size: 40),
                const SizedBox(height: 28),
                Text('Set up Haul', style: context.text.displaySmall),
                const SizedBox(height: 10),
                Text(
                  'Haul needs yt-dlp to download. ffmpeg and a JavaScript runtime are optional '
                  'but recommended. Haul downloads them for you and keeps them updated.',
                  style: context.text.bodyLarge!.copyWith(color: p.ink2),
                ),
                const SizedBox(height: 28),
                Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: p.line),
                  ),
                  child: Column(
                    children: [
                      for (final (i, t) in tools.indexed) ...[
                        if (i > 0) Divider(color: p.line, indent: 60),
                        _ToolRow(tool: t),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: Motion.normal,
                  child: allReady || (ready && !_running && anyFailed)
                      ? Row(
                          key: const ValueKey('done'),
                          children: [
                            Expanded(
                              child: HaulButton(
                                label: 'Continue',
                                tone: ButtonTone.primary,
                                expand: true,
                                onPressed: app.finishSetup,
                              ),
                            ),
                            if (anyFailed) ...[
                              const SizedBox(width: 10),
                              HaulButton(label: 'Retry', onPressed: () => _go(extras: true)),
                            ],
                          ],
                        )
                      : Row(
                          key: const ValueKey('go'),
                          children: [
                            Expanded(
                              child: HaulButton(
                                label: _running ? 'Downloading…' : 'Download and set up',
                                tone: ButtonTone.primary,
                                expand: true,
                                loading: _running,
                                onPressed: _running ? null : () => _go(extras: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            HaulButton(
                              label: 'yt-dlp only',
                              tone: ButtonTone.ghost,
                              onPressed: _running ? null : () => _go(extras: false),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  'You can add the optional tools later in Settings.',
                  style: context.text.bodySmall!.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});
  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = tool;
    final Widget lead = switch (t.state) {
      ToolState.ready => Container(
        key: const ValueKey('ok'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 17, color: p.onAccent),
      ),
      ToolState.installing => SizedBox(
        key: const ValueKey('busy'),
        width: 28,
        height: 28,
        child: Center(child: ProgressRing(value: t.progress, size: 24, stroke: 2.6)),
      ),
      ToolState.failed => Container(
        key: const ValueKey('fail'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: p.dangerSoft, shape: BoxShape.circle),
        child: Icon(Icons.priority_high_rounded, size: 16, color: p.danger),
      ),
      ToolState.missing => Container(
        key: const ValueKey('todo'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.line, width: 1.5),
        ),
      ),
    };

    final sub = switch (t.state) {
      ToolState.ready => t.managed ? 'Installed · ${t.version ?? ''}' : 'Already on this computer · ${t.version ?? ''}',
      ToolState.installing => t.progress == null ? 'Preparing' : 'Downloading ${(t.progress! * 100).round()}%',
      ToolState.failed => t.error ?? 'Couldn\'t install',
      ToolState.missing => t.purpose,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          AnimatedSwitcher(duration: Motion.normal, child: lead),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(t.name, style: context.text.titleSmall),
                    const SizedBox(width: 8),
                    if (t.required) const Tag('Required') else Tag('Optional', color: p.ink3),
                  ],
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: Motion.fast,
                  layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                  child: Text(
                    sub,
                    key: ValueKey(t.state),
                    style: context.text.bodySmall!.copyWith(color: t.state == ToolState.failed ? p.danger : p.ink2),
                  ),
                ),
              ],
            ),
          ),
          if (t.state == ToolState.missing && t.sizeHint != null) Text(t.sizeHint!, style: context.text.labelSmall),
        ],
      ),
    );
  }
}

/// Shown while the engine starts (Android unpacks Python on first run).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spinner(size: 22, stroke: 2.4),
            const SizedBox(height: 16),
            Text('Starting the download engine', style: context.text.bodyMedium!.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }
}

/// iOS / web: be honest instead of failing at the first download.
class UnsupportedScreen extends StatelessWidget {
  const UnsupportedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HaulMark(size: 48),
                const SizedBox(height: 24),
                Text('This device isn\'t supported', style: context.text.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'Haul runs yt-dlp right on your device. That works on Android, macOS, Windows and Linux, '
                  'but this platform doesn\'t allow apps to run it.',
                  style: context.text.bodyMedium!.copyWith(color: p.ink2),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
