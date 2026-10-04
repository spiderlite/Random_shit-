import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';

/// Phones and tablets get 48dp touch targets; mouse-driven layouts can be
/// tighter. (Material: 48dp; Apple HIG: 44pt; WCAG 2.2: 24px minimum.)
bool get _touch => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// The base of every tappable thing: hover tint, a small press scale, and
/// full keyboard support (Tab to focus, a visible 2px focus ring,
/// Enter/Space to activate). No Material ink ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.md)),
    this.hoverColor,
    this.color,
    this.pressScale = 0.97,
    this.tooltip,
    this.semanticLabel,
    this.padding,
    this.cursor,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Color? hoverColor;
  final Color? color;
  final double pressScale;
  final String? tooltip;
  final String? semanticLabel;
  final EdgeInsetsGeometry? padding;
  final MouseCursor? cursor;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = widget.color ?? Colors.transparent;
    final hover = widget.hoverColor ?? p.ink.withValues(alpha: 0.05);
    final bg = _enabled && (_hover || _down) ? Color.alphaBlend(hover, base) : base;

    Widget child = AnimatedScale(
      scale: _down ? widget.pressScale : 1,
      duration: Motion.fast,
      curve: Motion.easeOut,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.easeOut,
        padding: widget.padding,
        decoration: BoxDecoration(color: bg, borderRadius: widget.borderRadius),
        // Keyboard focus: a solid 2px ring in the accent (WCAG 2.4.7/2.4.13).
        foregroundDecoration: _focus
            ? BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: p.accent, width: 2))
            : null,
        child: widget.child,
      ),
    );

    child = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: _enabled ? (widget.cursor ?? SystemMouseCursors.click) : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() {
        _hover = v;
        if (!v) _down = false;
      }),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          (widget.onTap ?? widget.onLongPress)?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: child,
      ),
    );

    child = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.tooltip,
      onLongPressHint: widget.onLongPress == null ? null : 'More actions',
      child: child,
    );
    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return child;
  }
}

enum ButtonTone { primary, secondary, ghost, danger }

class HaulButton extends StatelessWidget {
  const HaulButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = ButtonTone.secondary,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final bool loading;
  final bool expand;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;
    final (bg, fg) = switch (tone) {
      ButtonTone.primary => (p.accent, p.onAccent),
      ButtonTone.secondary => (p.sunken, p.ink),
      ButtonTone.ghost => (Colors.transparent, p.ink),
      ButtonTone.danger => (Colors.transparent, p.danger),
    };
    // Minimum heights, not fixed ones, so large system text still fits.
    final minH = dense ? (_touch ? 40.0 : 34.0) : (_touch ? 48.0 : 40.0);
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: enabled || loading ? 1 : 0.5,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        tooltip: tooltip,
        semanticLabel: label,
        color: bg,
        hoverColor: tone == ButtonTone.primary ? Colors.black.withValues(alpha: 0.12) : p.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minH, minWidth: expand ? double.infinity : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: 8),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  Padding(padding: const EdgeInsets.only(right: 8), child: Spinner(size: 15, color: fg))
                else if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: Icon(icon, size: dense ? 16 : 18, color: fg),
                  ),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: context.text.labelLarge!.copyWith(color: fg, fontSize: dense ? 13 : 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size,
    this.iconSize = 20,
    this.color,
    this.background,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  /// Hit-target size. Defaults to 48 on touch devices, 36 with a mouse.
  final double? size;
  final double iconSize;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = size ?? (_touch ? 48.0 : 36.0);
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      color: background,
      borderRadius: BorderRadius.circular(s / 2),
      pressScale: 0.92,
      child: SizedBox(
        width: s,
        height: s,
        child: Icon(icon, size: iconSize, color: onPressed == null ? p.ink3 : (color ?? p.ink2)),
      ),
    );
  }
}

/// A calm, thin spinner — the default one is too heavy for this UI.
class Spinner extends StatefulWidget {
  const Spinner({super.key, this.size = 16, this.color, this.stroke = 2});
  final double size;
  final Color? color;
  final double stroke;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.palette.ink2;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _ArcPainter(_c.value, color, widget.stroke)),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.t, this.color, this.stroke);
  final double t;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(stroke / 2), t * 2 * math.pi, math.pi * 1.3, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.t != t || old.color != color;
}

/// A thin progress bar that glides between values. `null` value shows a
/// soft travelling highlight (indeterminate).
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color, this.height = 3, this.track});
  final double? value;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: track ?? p.ink.withValues(alpha: 0.07),
          child: value == null
              ? _Indeterminate(color: c)
              : TweenAnimationBuilder<double>(
                  tween: Tween(end: value!.clamp(0, 1)),
                  duration: Motion.slow,
                  curve: Motion.easeOut,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: ColoredBox(color: c),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Indeterminate extends StatefulWidget {
  const _Indeterminate({required this.color});
  final Color color;
  @override
  State<_Indeterminate> createState() => _IndeterminateState();
}

class _IndeterminateState extends State<_Indeterminate> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return FractionallySizedBox(
          widthFactor: 1,
          child: CustomPaint(painter: _SweepPainter(t, widget.color)),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.35;
    final x = -w + (size.width + w) * t;
    final rect = Rect.fromLTWH(x, 0, w, size.height);
    final paint = Paint()
      ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)]).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t;
}

/// Circular progress for the header summary.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 18, this.stroke = 2.4, this.color});
  final double? value;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (value == null) return Spinner(size: size, color: color ?? p.accent, stroke: stroke);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value!.clamp(0, 1)),
      duration: Motion.slow,
      curve: Motion.easeOut,
      builder: (_, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _RingPainter(v, color ?? p.accent, p.ink.withValues(alpha: 0.1), stroke)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, paint..color = track);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Fades and lifts its child in once, when first built.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.delay = Duration.zero, this.offset = 10, this.duration});
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration? duration;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration ?? Motion.normal);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Motion.ease);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, (1 - a.value) * widget.offset), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Segmented control with a sliding indicator.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChanged, this.counts});

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, int>? counts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in items)
            _SegmentChip(
              label: label,
              count: counts?[v],
              selected: v == value,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      pressScale: 0.96,
      borderRadius: BorderRadius.circular(8),
      hoverColor: selected ? Colors.transparent : p.ink.withValues(alpha: 0.04),
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: Motion.fast,
              style: context.text.labelMedium!.copyWith(
                color: selected ? p.ink : p.ink2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
            AnimatedSize(
              duration: Motion.normal,
              curve: Motion.ease,
              child: count == null || count == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text('$count', style: context.text.labelSmall!.copyWith(color: selected ? p.ink2 : p.ink3)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(label, style: context.text.labelSmall!.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The Haul mark: a downward stroke landing on a line.
class HaulMark extends StatelessWidget {
  const HaulMark({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color ?? context.palette.accent),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.3));
    canvas.drawRRect(r, Paint()..color = color);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width;
    canvas.drawLine(Offset(w * .5, w * .24), Offset(w * .5, w * .6), paint);
    canvas.drawPath(
      Path()
        ..moveTo(w * .33, w * .45)
        ..lineTo(w * .5, w * .62)
        ..lineTo(w * .67, w * .45),
      paint,
    );
    canvas.drawLine(Offset(w * .3, w * .77), Offset(w * .7, w * .77), paint);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HaulMark(size: size),
        SizedBox(width: size * 0.4),
        Text('haul', style: context.text.titleLarge!.copyWith(fontSize: size * 0.9, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
      ],
    );
  }
}
