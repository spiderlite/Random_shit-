import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/ytdlp.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../item_actions.dart';
import '../widgets/kit.dart';
import '../widgets/thumb.dart';

/// One row in the queue: one line of status, one obvious action, and a
/// "More" menu (long press on phones) for everything else. Nothing is
/// hidden behind hover, so keyboards, touch and screen readers reach it all.
class QueueTile extends StatelessWidget {
  const QueueTile({super.key, required this.item, required this.compact, required this.onOpenDetails});
  final DownloadItem item;
  final bool compact;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final p = context.palette;
    final probing = q.isProbing(item.id);
    final status = statusText(item, probing: probing, compact: compact);
    final showBar = item.status.isActive || item.status == DownloadStatus.paused || (probing && item.status == DownloadStatus.queued);
    final pct = item.progress == null ? null : '${(item.progress! * 100).floor()}%';

    return Semantics(
      // One coherent announcement per row instead of a scatter of fragments.
      label: '${item.displayTitle}. ${status.$1}',
      value: item.status == DownloadStatus.downloading ? pct : null,
      excludeSemantics: false,
      child: Pressable(
        onTap: onOpenDetails,
        onLongPress: compact ? () => showItemMenu(context, item, compact: true) : null,
        semanticLabel: 'Details',
        pressScale: 0.99,
        borderRadius: BorderRadius.circular(Radii.md),
        hoverColor: p.ink.withValues(alpha: 0.04),
        padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 8, compact ? 0 : 4, 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Stack(
                children: [
                  Hero(
                    tag: 'thumb-${item.id}',
                    child: VideoThumb(url: item.thumbnail, link: item.url, width: compact ? 92 : 112, audio: item.isAudio),
                  ),
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
            ),
            SizedBox(width: compact ? 12 : 14),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Title(item: item, compact: compact),
                    const SizedBox(height: 3),
                    _StatusLine(item: item, text: status.$1, tone: status.$2),
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
            ),
            const SizedBox(width: 4),
            _Primary(item: item),
            if (!compact)
              Builder(
                builder: (ctx) => IconBtn(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'More',
                  onPressed: () => showItemMenu(ctx, item, compact: false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum StatusTone { normal, quiet, error }

/// What a row says about itself. Specific beats cute: "Merging video and
/// audio" tells you more than "Finishing up…".
(String, StatusTone) statusText(DownloadItem item, {required bool probing, required bool compact}) {
  final site = detectSite(item.url).label;
  String meta() => [
        if (!compact) site,
        if (item.uploader != null) item.uploader!,
        if (item.collection != null && !compact) item.collection!,
      ].join(' · ');

  return switch (item.status) {
    DownloadStatus.queued when probing => ('Fetching details', StatusTone.normal),
    DownloadStatus.queued => ([meta(), 'Queued', item.formatLabel].where((s) => s.isNotEmpty).join(' · '), StatusTone.quiet),
    DownloadStatus.fetching => ('Fetching details', StatusTone.normal),
    DownloadStatus.downloading => (
        item.progress == null && item.downloadedBytes == null
            ? 'Starting'
            : [
                if (item.progress != null) '${(item.progress! * 100).floor()}%',
                progressSummary(item),
              ].where((s) => s.isNotEmpty).join(' · '),
        StatusTone.normal
      ),
    DownloadStatus.processing => (item.isAudio ? 'Converting audio' : 'Merging video and audio', StatusTone.normal),
    DownloadStatus.paused => (
        ['Paused', if (item.progress != null && item.progress! > 0) '${(item.progress! * 100).floor()}%'].join(' · '),
        StatusTone.quiet
      ),
    DownloadStatus.done => (
        item.skippedExisting
            ? 'Skipped: already downloaded'
            : [
                if (meta().isNotEmpty) meta(),
                if (item.fileSize != null) formatBytes(item.fileSize),
                item.formatLabel,
              ].join(' · '),
        StatusTone.normal
      ),
    DownloadStatus.failed => (item.error ?? 'Failed', StatusTone.error),
  };
}

class _Title extends StatelessWidget {
  const _Title({required this.item, required this.compact});
  final DownloadItem item;
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
          fontWeight: known ? FontWeight.w600 : FontWeight.w400,
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
  const _StatusLine({required this.item, required this.text, required this.tone});
  final DownloadItem item;
  final String text;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (tone) {
      StatusTone.normal => p.ink2,
      StatusTone.quiet => p.ink3,
      StatusTone.error => p.danger,
    };
    return AnimatedSwitcher(
      duration: Motion.fast,
      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
      // Progress text changes constantly; only cross-fade on status change.
      child: Row(
        key: ValueKey(item.status),
        children: [
          // Errors carry an icon too, so colour is never the only signal.
          if (tone == StatusTone.error) ...[
            Icon(Icons.error_outline_rounded, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall!.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single most likely next step for this row.
class _Primary extends StatelessWidget {
  const _Primary({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final q = app.queue;
    final p = context.palette;

    final Widget child = switch (item.status) {
      DownloadStatus.queued || DownloadStatus.fetching || DownloadStatus.downloading =>
        IconBtn(icon: Icons.pause_rounded, tooltip: 'Pause', onPressed: () => q.pause(item.id)),
      DownloadStatus.processing => const SizedBox(width: 40, child: Center(child: Spinner(size: 16))),
      DownloadStatus.paused =>
        IconBtn(icon: Icons.play_arrow_rounded, tooltip: 'Resume', color: p.accent, onPressed: () => q.resume(item.id)),
      DownloadStatus.failed =>
        IconBtn(icon: Icons.refresh_rounded, tooltip: 'Try again', color: p.ink, onPressed: () => q.retry(item.id)),
      DownloadStatus.done when item.saveProgress != null =>
        SizedBox(width: 40, child: Center(child: ProgressRing(value: item.saveProgress, size: 18))),
      DownloadStatus.done when item.filePath != null => IconBtn(
          icon: openIcon(app, item),
          tooltip: openLabel(app, item),
          color: p.ink,
          onPressed: () => openItem(context, item),
        ),
      DownloadStatus.done => const SizedBox(width: 40),
    };

    return AnimatedSwitcher(
      duration: Motion.fast,
      child: KeyedSubtree(
        key: ValueKey('${item.status}-${item.filePath != null}-${item.saveProgress != null}-${item.localPath != null}'),
        child: child,
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: context.text.labelSmall!.copyWith(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
      );
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({super.key, required this.skipped});
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: skipped ? Colors.black.withValues(alpha: 0.72) : p.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(skipped ? Icons.history_rounded : Icons.check_rounded, size: 12, color: skipped ? Colors.white : p.onAccent),
    );
  }
}
