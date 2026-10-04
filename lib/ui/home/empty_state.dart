import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../widgets/kit.dart';
import 'queue_header.dart';

/// What an empty list says depends on which list it is. The "all" version
/// doubles as a two-line tutorial.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.filter, required this.compact, required this.canShare, required this.canDrop});
  final QueueFilter filter;
  /// Phone-width layout: the paste box sits below the list.
  final bool compact;
  /// Android: other apps can share links straight to Haul.
  final bool canShare;
  /// Desktop: files can be dropped on the window.
  final bool canDrop;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, String title, String body) = switch (filter) {
      QueueFilter.all => (
          Icons.south_rounded,
          'Nothing here yet',
          canShare
              ? 'Share a video to Haul from YouTube, Instagram, TikTok or your browser — or paste links below.'
              : [
                  'Paste a link, a playlist or a whole channel ${compact ? 'below' : 'above'}.',
                  if (canDrop) 'You can also drop a text file full of links anywhere on this window.',
                ].join(' '),
        ),
      QueueFilter.active => (Icons.bedtime_outlined, 'All quiet', 'Nothing is downloading right now.'),
      QueueFilter.done => (Icons.inventory_2_outlined, 'No downloads yet', 'Finished videos will show up here.'),
      QueueFilter.failed => (Icons.check_rounded, 'No failures', 'Everything that was tried, worked.'),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Appear(
          offset: 14,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bob(
                  enabled: filter == QueueFilter.all,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(18)),
                    child: Icon(icon, color: p.accent, size: 26),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(body, style: context.text.bodyMedium!.copyWith(color: p.ink2), textAlign: TextAlign.center),
                if (filter == QueueFilter.all && canShare) ...[
                  const SizedBox(height: 22),
                  const _ShareHint(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slow, small float — enough to feel alive, not enough to distract.
class _Bob extends StatefulWidget {
  const _Bob({required this.child, required this.enabled});
  final Widget child;
  final bool enabled;
  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, c) => Transform.translate(offset: Offset(0, Curves.easeInOut.transform(_c.value) * 5 - 2.5), child: c),
        child: widget.child,
      );
}

class _ShareHint extends StatelessWidget {
  const _ShareHint();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget step(String n, String text) => Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.sunken, shape: BoxShape.circle),
              child: Text(n, style: context.text.labelSmall!.copyWith(color: p.ink2, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: context.text.bodyMedium)),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.line),
      ),
      child: Column(
        children: [
          step('1', 'Tap Share on any video'),
          const SizedBox(height: 10),
          step('2', 'Choose Haul'),
          const SizedBox(height: 10),
          step('3', 'That\'s it — it\'s downloading'),
        ],
      ),
    );
  }
}
