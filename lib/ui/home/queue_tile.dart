import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/ytdlp.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';
import '../widgets/thumb.dart';

/// One row in the queue. Shows exactly one line of status at a time and
/// one obvious action; everything else lives in the details sheet.
class QueueTile extends StatefulWidget {
  const QueueTile({super.key, required this.item, required this.compact, required this.onOpenDetails});
  final DownloadItem item;
  final bool compact;
  final VoidCallback onOpenDetails;

  @override
  State<QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<QueueTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final item = widget.item;
    final p = context.palette;
    final probing = q.isProbing(item.id);
    final active = item.status.isActive;
    final compact = widget.compact;

    final thumb = Hero(
      tag: 'thumb-${item.id}',
      child: VideoThumb(url: item.thumbnail, link: item.url, width: compact ? 92 : 112, audio: item.isAudio),
    );

    final showBar = active || item.status == DownloadStatus.paused || (probing && item.status == DownloadStatus.queued);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onTap: widget.onOpenDetails,
        pressScale: 0.99,
        borderRadius: BorderRadius.circular(Radii.md),
        hoverColor: p.ink.withValues(alpha: 0.035),
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 8 : 9),
        child: Row(
          children: [
            Stack(
              children: [
                thumb,
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: AnimatedSwitcher(
                    duration: Motion.normal,
                    child: item.status == DownloadStatus.done
                        ? _DoneBadge(key: const ValueKey('d'), skipped: item.skippedExisting)
                        : (item.duration != null
                            ? _DurationBadge(key: const ValueKey('t'), text: formatDuration(item.duration))
                            : const SizedBox.shrink()),
                  ),
                ),
              ],
            ),
            SizedBox(width: compact ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Title(item: item, probing: probing, compact: compact),
                  const SizedBox(height: 3),
                  _StatusLine(item: item, probing: probing, compact: compact),
                  AnimatedSize(
                    duration: Motion.normal,
                    curve: Motion.ease,
                    child: showBar
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8, right: 4),
                            child: ProgressLine(
                              value: item.status == DownloadStatus.processing || (probing && item.status == DownloadStatus.queued)
                                  ? null
                                  : (item.progress ?? (item.status == DownloadStatus.paused ? 0 : null)),
                              color: item.status == DownloadStatus.paused ? p.ink3 : p.accent,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 10),
            _Trailing(item: item, hover: _hover || compact, compact: compact),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.item, required this.probing, required this.compact});
  final DownloadItem item;
  final bool probing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final known = item.title != null && item.title!.isNotEmpty;
    final text = known ? item.title! : _prettyUrl(item.url);
    return AnimatedSwitcher(
      duration: Motion.normal,
      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
      child: Text(
        text,
        key: ValueKey(text),
        maxLines: compact ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.titleSmall!.copyWith(
          color: known ? p.ink : p.ink2,
          fontWeight: known ? FontWeight.w600 : FontWeight.w500,
          height: 1.3,
        ),
      ),
    );
  }

  static String _prettyUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    var host = u.host;
    if (host.startsWith('www.')) host = host.substring(4);
    final path = u.path.length > 1 ? u.path : '';
    final q = u.query.isNotEmpty ? '?${u.query}' : '';
    return '$host$path$q';
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.item, required this.probing, required this.compact});
  final DownloadItem item;
  final bool probing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.text.bodySmall!;
    final site = detectSite(item.url).label;

    String meta() => [
          if (!compact) site,
          if (item.uploader != null) item.uploader!,
          if (item.collection != null && !compact) item.collection!,
        ].join(' · ');

    final (String text, Color color) = switch (item.status) {
      DownloadStatus.queued when probing => ('Looking it up…', p.ink2),
      DownloadStatus.queued => ([meta(), 'Waiting', item.formatLabel].where((s) => s.isNotEmpty).join(' · '), p.ink3),
      DownloadStatus.fetching => ('Looking it up…', p.ink2),
      DownloadStatus.downloading => (
          item.progress == null && item.downloadedBytes == null
              ? 'Starting…'
              : [
                  if (item.progress != null) '${(item.progress! * 100).floor()}%',
                  progressSummary(item),
                ].where((s) => s.isNotEmpty).join(' · '),
          p.ink2
        ),
      DownloadStatus.processing => (item.isAudio ? 'Converting…' : 'Finishing up…', p.ink2),
      DownloadStatus.paused => (
          ['Paused', if (item.progress != null && item.progress! > 0) '${(item.progress! * 100).floor()}%'].join(' · '),
          p.ink3
        ),
      DownloadStatus.done => (
          item.skippedExisting
              ? 'Already in your library'
              : [
                  if (meta().isNotEmpty) meta(),
                  if (item.fileSize != null) formatBytes(item.fileSize),
                  item.formatLabel,
                ].join(' · '),
          p.ink2
        ),
      DownloadStatus.failed => (item.error ?? 'Failed', p.danger),
    };

    return AnimatedSwitcher(
      duration: Motion.fast,
      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
      child: Text(
        text,
        // Progress text changes constantly — only cross-fade on status change.
        key: ValueKey(item.status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: color),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.item, required this.hover, required this.compact});
  final DownloadItem item;
  final bool hover;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final q = app.queue;
    final p = context.palette;

    final primary = switch (item.status) {
      DownloadStatus.queued || DownloadStatus.fetching || DownloadStatus.downloading => IconBtn(
          icon: Icons.pause_rounded,
          tooltip: 'Pause',
          onPressed: () => q.pause(item.id),
        ),
      DownloadStatus.processing => const Padding(padding: EdgeInsets.all(10), child: Spinner(size: 16)),
      DownloadStatus.paused => IconBtn(
          icon: Icons.play_arrow_rounded,
          tooltip: 'Resume',
          color: p.accent,
          onPressed: () => q.resume(item.id),
        ),
      DownloadStatus.failed => IconBtn(
          icon: Icons.refresh_rounded,
          tooltip: 'Try again',
          color: p.ink,
          onPressed: () => q.retry(item.id),
        ),
      DownloadStatus.done when item.filePath != null => IconBtn(
          icon: item.isAudio ? Icons.headphones_rounded : Icons.play_arrow_rounded,
          tooltip: 'Open',
          color: p.ink,
          onPressed: () => app.bridge.openFile(item.filePath!, contentUri: item.contentUri),
        ),
      DownloadStatus.done => const SizedBox(width: 36),
    };

    final showRemove = !compact && hover;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact && item.status == DownloadStatus.done && item.filePath != null)
          _Fade(
            visible: hover,
            child: IconBtn(
              icon: Icons.folder_open_rounded,
              tooltip: 'Show in folder',
              onPressed: () => app.bridge.revealFile(item.filePath!),
            ),
          ),
        AnimatedSwitcher(
          duration: Motion.normal,
          transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
          child: KeyedSubtree(key: ValueKey('${item.status}-${item.filePath != null}'), child: primary),
        ),
        if (!compact)
          _Fade(
            visible: showRemove,
            child: IconBtn(icon: Icons.close_rounded, tooltip: 'Remove', onPressed: () => q.remove(item.id)),
          ),
      ],
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.fast,
        child: IgnorePointer(ignoring: !visible, child: child),
      );
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.68), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: context.text.labelSmall!.copyWith(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({super.key, required this.skipped});
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: Motion.slow,
      curve: Curves.easeOutBack,
      builder: (_, s, c) => Transform.scale(scale: s, child: c),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: skipped ? Colors.black.withValues(alpha: 0.68) : p.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
        ),
        child: Icon(skipped ? Icons.history_rounded : Icons.check_rounded, size: 12, color: Colors.white),
      ),
    );
  }
}
