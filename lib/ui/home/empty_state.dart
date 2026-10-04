import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../widgets/kit.dart';
import 'queue_header.dart';

/// An empty list is a starting point, not decoration: say what goes here
/// and offer the one action that fills it. No floating icon tile.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.filter,
    required this.compact,
    required this.canShare,
    required this.canDrop,
    this.onPaste,
  });

  final QueueFilter filter;
  /// Phone-width layout: the paste box sits below the list.
  final bool compact;
  /// Android: other apps can share links straight to Haul.
  final bool canShare;
  /// Desktop: files can be dropped on the window.
  final bool canDrop;
  /// Paste from the clipboard and start.
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (String title, String body) = switch (filter) {
      QueueFilter.all => (
          'No downloads yet',
          canShare
              ? 'Share a video to Haul from YouTube, Instagram, TikTok or your browser. You can also paste links below.'
              : [
                  'Paste a link to a video, playlist or channel ${compact ? 'below' : 'above'}.',
                  if (canDrop) 'Or drop a text file of links onto this window.',
                ].join(' '),
        ),
      QueueFilter.active => ('Nothing downloading', 'Downloads in progress and waiting show up here.'),
      QueueFilter.done => ('Nothing finished yet', 'Finished downloads show up here.'),
      QueueFilter.failed => ('No failed downloads', 'Anything that fails shows up here, with a way to retry.'),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(body, style: context.text.bodyMedium!.copyWith(color: p.ink2), textAlign: TextAlign.center),
              if (filter == QueueFilter.all && onPaste != null) ...[
                const SizedBox(height: 20),
                HaulButton(label: 'Paste and download', icon: Icons.content_paste_rounded, onPressed: onPaste),
              ],
              if (filter == QueueFilter.all && canShare) ...[
                const SizedBox(height: 28),
                const _ShareSteps(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareSteps extends StatelessWidget {
  const _ShareSteps();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(n, style: context.text.labelLarge!.copyWith(color: p.accent)),
              ),
              Expanded(child: Text(text, style: context.text.bodyMedium)),
            ],
          ),
        );
    // A plain numbered list: no card, no icon circles.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step('1', 'In any app, tap Share on a video'),
        step('2', 'Choose Haul'),
        step('3', 'The download starts right away'),
      ],
    );
  }
}
