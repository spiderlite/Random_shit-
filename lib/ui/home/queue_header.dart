import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';

enum QueueFilter { all, active, done, failed }

bool matchesFilter(QueueFilter f, DownloadItem item) => switch (f) {
      QueueFilter.all => true,
      QueueFilter.active => item.status != DownloadStatus.done && item.status != DownloadStatus.failed,
      QueueFilter.done => item.status == DownloadStatus.done,
      QueueFilter.failed => item.status == DownloadStatus.failed,
    };

/// "3 downloading · 12 waiting · 8.4 MB/s" with a ring, or a calm
/// "All done" when idle.
class QueueSummary extends StatelessWidget {
  const QueueSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final p = context.palette;
    final active = q.activeCount;
    final waiting = q.queuedCount;
    final speed = q.totalSpeed;

    final String text;
    final Widget lead;
    if (active > 0 || waiting > 0) {
      text = [
        if (active > 0) '$active downloading',
        if (waiting > 0) '$waiting waiting',
        if (speed > 0) formatSpeed(speed),
      ].join(' · ');
      lead = ProgressRing(value: q.overallProgress, size: 15, stroke: 2.2);
    } else if (q.pausedCount > 0) {
      text = '${q.pausedCount} paused';
      lead = Icon(Icons.pause_circle_outline_rounded, size: 16, color: p.ink3);
    } else if (q.doneCount > 0) {
      text = q.failedCount > 0 ? '${q.doneCount} done · ${q.failedCount} failed' : 'All done · ${plural(q.doneCount, 'video')}';
      lead = Icon(Icons.check_circle_rounded, size: 16, color: q.failedCount > 0 ? p.ink3 : p.accent);
    } else {
      text = 'Ready when you are';
      lead = Icon(Icons.circle, size: 8, color: p.accent);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, height: 16, child: Center(child: lead)),
        const SizedBox(width: 8),
        Flexible(
          child: AnimatedSwitcher(
            duration: Motion.fast,
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
            child: Text(
              text,
              key: ValueKey(text.split(' · ').first.replaceAll(RegExp(r'\d'), '')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class QueueToolbar extends StatelessWidget {
  const QueueToolbar({super.key, required this.filter, required this.onFilter, required this.compact});
  final QueueFilter filter;
  final ValueChanged<QueueFilter> onFilter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final items = q.items;
    int n(QueueFilter f) => items.where((i) => matchesFilter(f, i)).length;

    final filters = [
      (QueueFilter.all, 'All'),
      (QueueFilter.active, 'Active'),
      (QueueFilter.done, 'Done'),
      if (q.failedCount > 0 || filter == QueueFilter.failed) (QueueFilter.failed, 'Failed'),
    ];

    return Row(
      children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<QueueFilter>(
              items: filters,
              value: filter,
              onChanged: onFilter,
              counts: {
                QueueFilter.active: n(QueueFilter.active),
                QueueFilter.done: n(QueueFilter.done),
                QueueFilter.failed: n(QueueFilter.failed),
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (q.failedCount > 0 && !compact)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: HaulButton(
              label: 'Retry failed',
              icon: Icons.refresh_rounded,
              dense: true,
              tone: ButtonTone.ghost,
              onPressed: q.retryFailed,
            ),
          ),
        _MoreMenu(),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = QueueScope.of(context);
    final p = context.palette;
    final anyRunning = q.pendingCount > 0;

    PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => PopupMenuItem(
          value: onTap,
          enabled: onTap != null,
          height: 42,
          child: Row(
            children: [
              Icon(icon, size: 18, color: onTap == null ? p.ink3 : (danger ? p.danger : p.ink2)),
              const SizedBox(width: 12),
              Text(label, style: context.text.bodyMedium!.copyWith(color: onTap == null ? p.ink3 : (danger ? p.danger : p.ink))),
            ],
          ),
        );

    return Builder(
      builder: (ctx) => IconBtn(
        icon: Icons.more_horiz_rounded,
        tooltip: 'More',
        onPressed: () async {
          final box = ctx.findRenderObject() as RenderBox;
          final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
          final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
          final action = await showMenu<VoidCallback>(
            context: ctx,
            position: RelativeRect.fromLTRB(pos.dx - 180, pos.dy + box.size.height + 4, overlay.size.width - pos.dx - box.size.width, 0),
            popUpAnimationStyle: const AnimationStyle(duration: Motion.normal, reverseDuration: Motion.fast),
            items: [
              if (anyRunning) item(Icons.pause_rounded, 'Pause all', q.pauseAll),
              if (q.pausedCount > 0) item(Icons.play_arrow_rounded, 'Resume all', q.resumeAll),
              item(Icons.refresh_rounded, 'Retry failed', q.failedCount > 0 ? q.retryFailed : null),
              item(Icons.folder_open_rounded, 'Open downloads folder', () => app.bridge.openFolder(app.downloadDir)),
              const PopupMenuDivider(height: 8),
              item(Icons.cleaning_services_outlined, 'Clear finished', q.doneCount > 0 ? q.clearFinished : null, danger: true),
            ],
          );
          action?.call();
        },
      ),
    );
  }
}
