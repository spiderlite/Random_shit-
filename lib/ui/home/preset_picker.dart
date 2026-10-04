import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';

IconData presetIcon(FormatPreset p) => switch (p) {
      FormatPreset.mp3 || FormatPreset.m4a => Icons.music_note_rounded,
      FormatPreset.best => Icons.auto_awesome_rounded,
      _ => Icons.movie_outlined,
    };

/// Shows the quality choices: a bottom sheet on phones, an anchored
/// popover on desktop.
Future<FormatPreset?> pickPreset(BuildContext context, FormatPreset current, {bool compact = false, String? title}) {
  if (compact) {
    return showModalBottomSheet<FormatPreset>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _PresetSheet(current: current, title: title),
    );
  }
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final origin = box?.localToGlobal(Offset.zero, ancestor: overlay) ?? Offset.zero;
  final size = box?.size ?? Size.zero;
  return showMenu<FormatPreset>(
    context: context,
    position: RelativeRect.fromLTRB(origin.dx, origin.dy + size.height + 6, overlay.size.width - origin.dx - size.width, 0),
    constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
    popUpAnimationStyle: const AnimationStyle(duration: Motion.normal, reverseDuration: Motion.fast),
    items: [
      for (final p in FormatPreset.values)
        PopupMenuItem(
          value: p,
          height: 50,
          child: _PresetRow(preset: p, selected: p == current),
        ),
    ],
  );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset, required this.selected});
  final FormatPreset preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(presetIcon(preset), size: 18, color: selected ? p.accent : p.ink3),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(preset.label, style: context.text.titleSmall!.copyWith(color: selected ? p.accent : p.ink)),
              Text(preset.description, style: context.text.bodySmall),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: Motion.fast,
          opacity: selected ? 1 : 0,
          child: Icon(Icons.check_rounded, size: 18, color: p.accent),
        ),
      ],
    );
  }
}

class _PresetSheet extends StatelessWidget {
  const _PresetSheet({required this.current, this.title});
  final FormatPreset current;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(title ?? 'Quality', style: context.text.titleLarge),
            ),
            for (final (i, preset) in FormatPreset.values.indexed)
              Appear(
                delay: Duration(milliseconds: 18 * i),
                offset: 6,
                child: Pressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, preset);
                  },
                  color: preset == current ? p.accentSoft : null,
                  borderRadius: BorderRadius.circular(Radii.md),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: _PresetRow(preset: preset, selected: preset == current),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(4)),
        ),
      );
}

/// The little "1080p ▾" chip.
class PresetChip extends StatelessWidget {
  const PresetChip({super.key, required this.value, required this.onChanged, this.compact = false});
  final FormatPreset value;
  final ValueChanged<FormatPreset> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Builder(
      builder: (ctx) => Pressable(
        tooltip: 'Quality for new downloads',
        onTap: () async {
          final picked = await pickPreset(ctx, value, compact: compact);
          if (picked != null) onChanged(picked);
        },
        color: p.sunken,
        borderRadius: BorderRadius.circular(compact ? 20 : 10),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 11, vertical: compact ? 8 : 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(presetIcon(value), size: 15, color: p.ink2),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: Motion.fast,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              child: Text(value.label, key: ValueKey(value), style: context.text.labelLarge!.copyWith(fontSize: 13)),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 17, color: p.ink3),
          ],
        ),
      ),
    );
  }
}
