import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'kit.dart';

class ToastData {
  ToastData(this.message, {this.actionLabel, this.onAction, this.icon, this.duration = const Duration(seconds: 4)});
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final Duration duration;
  final int id = _seq++;
  static int _seq = 0;
}

/// One toast at a time, bottom centre, sliding up softly. New toasts
/// replace the current one rather than stacking into a pile.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  static ToastHostState? of(BuildContext context) => context.findAncestorStateOfType<ToastHostState>();

  static void show(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, IconData? icon}) =>
      of(context)?.show(ToastData(message, actionLabel: actionLabel, onAction: onAction, icon: icon));

  @override
  State<ToastHost> createState() => ToastHostState();
}

class ToastHostState extends State<ToastHost> {
  ToastData? _current;
  Timer? _timer;
  double _extraInset = 0;

  void show(ToastData t) {
    _timer?.cancel();
    setState(() => _current = t);
    _timer = Timer(t.duration + (t.actionLabel != null ? const Duration(seconds: 2) : Duration.zero), dismiss);
  }

  /// Lift toasts above a bottom bar (the phone composer).
  set extraInset(double v) {
    if (v == _extraInset) return;
    _extraInset = v;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void dismiss() {
    _timer?.cancel();
    if (mounted) setState(() => _current = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom + mq.viewInsets.bottom + _extraInset + 16;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          bottom: bottom,
          child: IgnorePointer(
            ignoring: _current == null,
            child: Center(
              child: AnimatedSwitcher(
                duration: Motion.normal,
                reverseDuration: Motion.fast,
                switchInCurve: Motion.ease,
                switchOutCurve: Motion.easeIn,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                    child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
                  ),
                ),
                child: _current == null
                    ? const SizedBox.shrink()
                    : _ToastCard(key: ValueKey(_current!.id), data: _current!, onClose: dismiss),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.data, required this.onClose});
  final ToastData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Inverted colours: a dark pill on light theme, a light one on dark.
    final bg = p.ink;
    final fg = p.bg;
    return Material(
      type: MaterialType.transparency,
      child: Dismissible(
      key: ValueKey(data.id),
      direction: DismissDirection.down,
      onDismissed: (_) => onClose(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 6, data.actionLabel == null ? 16 : 6, 6),
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.icon != null) ...[Icon(data.icon, size: 17, color: fg.withValues(alpha: 0.8)), const SizedBox(width: 10)],
              Flexible(
                child: Text(
                  data.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium!.copyWith(color: fg, fontWeight: FontWeight.w500),
                ),
              ),
              if (data.actionLabel != null) ...[
                const SizedBox(width: 8),
                Pressable(
                  onTap: () {
                    data.onAction?.call();
                    onClose();
                  },
                  hoverColor: fg.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(data.actionLabel!, style: context.text.labelLarge!.copyWith(color: _actionColor(context))),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  // The accent is tuned for the page background; on the inverted pill use
  // the other theme's accent so it keeps its contrast.
  Color _actionColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Palette.light.accent : Palette.dark.accent;
}
