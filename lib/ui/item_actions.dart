import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../platform/info.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import 'widgets/toast.dart';

/// Where a finished file can be reached *from this device*.
enum Reach {
  /// On this device: open, share, reveal.
  here,
  /// On the computer (remote mode); can be copied over.
  computer,
  /// In a browser: can be downloaded.
  browser,
  none,
}

Reach reachOf(AppState app, DownloadItem item) {
  if (item.status != DownloadStatus.done || item.filePath == null) return Reach.none;
  if (app.remote == null) return Reach.here;
  if (isWeb) return Reach.browser;
  return item.localPath != null ? Reach.here : Reach.computer;
}

String? localFileOf(AppState app, DownloadItem item) => app.remote == null ? item.filePath : item.localPath;

/// The one "give me my video" action, whatever the setup.
Future<void> openItem(BuildContext context, DownloadItem item) async {
  final app = AppScope.read(context);
  final toast = ToastHost.of(context);
  switch (reachOf(app, item)) {
    case Reach.here:
      final ok = await app.bridge.openFile(localFileOf(app, item)!, contentUri: item.contentUri);
      if (!ok) toast?.show(ToastData('Couldn\'t open the file. It may have been moved or deleted.', icon: Icons.error_outline_rounded));
    case Reach.computer:
      toast?.show(ToastData('Copying to this phone…', icon: Icons.download_rounded));
      final ok = await app.queue.saveToDevice(item.id);
      if (!ok) {
        toast?.show(ToastData('Couldn\'t copy it. Is your computer still on?', icon: Icons.error_outline_rounded));
      } else if (item.localPath != null) {
        await app.bridge.openFile(item.localPath!, contentUri: item.contentUri);
      }
    case Reach.browser:
      final remote = app.remote!;
      final path = item.filePath!;
      await app.bridge.downloadInBrowser(remote.fileUri(path), path.split(remote.pathSeparator).last);
    case Reach.none:
      break;
  }
}

IconData openIcon(AppState app, DownloadItem item) => switch (reachOf(app, item)) {
      Reach.here => item.isAudio ? Icons.headphones_rounded : Icons.play_arrow_rounded,
      Reach.computer || Reach.browser => Icons.download_rounded,
      Reach.none => Icons.play_arrow_rounded,
    };

String openLabel(AppState app, DownloadItem item) => switch (reachOf(app, item)) {
      Reach.here => item.isAudio ? 'Play' : 'Open',
      Reach.computer => 'Save to phone',
      Reach.browser => 'Download',
      Reach.none => 'Open',
    };

class _MenuAction {
  const _MenuAction(this.icon, this.label, this.run, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback run;
  final bool danger;
}

List<_MenuAction> _actionsFor(BuildContext context, DownloadItem item) {
  final app = AppScope.read(context);
  final q = app.queue;
  final reach = reachOf(app, item);
  final here = localFileOf(app, item);
  return [
    if (reach != Reach.none) _MenuAction(openIcon(app, item), openLabel(app, item), () => openItem(context, item)),
    if (reach == Reach.here && isDesktop) _MenuAction(Icons.folder_open_rounded, 'Show in folder', () => app.bridge.revealFile(here!)),
    if (reach == Reach.here && isHandheld)
      _MenuAction(Icons.ios_share_rounded, 'Share', () => app.bridge.shareFile(here!, contentUri: item.contentUri, title: item.title)),
    if (item.status.isActive || item.status == DownloadStatus.queued) _MenuAction(Icons.pause_rounded, 'Pause', () => q.pause(item.id)),
    if (item.status == DownloadStatus.paused) _MenuAction(Icons.play_arrow_rounded, 'Resume', () => q.resume(item.id)),
    if (item.status == DownloadStatus.failed) _MenuAction(Icons.refresh_rounded, 'Try again', () => q.retry(item.id)),
    _MenuAction(Icons.link_rounded, 'Copy link', () {
      Clipboard.setData(ClipboardData(text: item.url));
      ToastHost.of(context)?.show(ToastData('Link copied', icon: Icons.link_rounded));
    }),
    _MenuAction(Icons.open_in_new_rounded, 'Open original page', () => app.bridge.openUrl(item.url)),
    _MenuAction(Icons.delete_outline_rounded, 'Remove from list', () => q.remove(item.id), danger: true),
  ];
}

/// Every row action in one place, reachable without hover: the row's
/// "More" button (desktop), or a long press (phones).
Future<void> showItemMenu(BuildContext context, DownloadItem item, {required bool compact}) async {
  final p = context.palette;
  final actions = _actionsFor(context, item);
  if (compact) {
    final picked = await showModalBottomSheet<_MenuAction>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: ctx.text.titleSmall),
              ),
              for (final a in actions)
                ListTile(
                  leading: Icon(a.icon, color: a.danger ? p.danger : p.ink2),
                  title: Text(a.label, style: ctx.text.bodyLarge!.copyWith(color: a.danger ? p.danger : p.ink)),
                  minTileHeight: 52,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
                  onTap: () => Navigator.pop(ctx, a),
                ),
            ],
          ),
        ),
      ),
    );
    picked?.run();
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final at = box?.localToGlobal(Offset.zero, ancestor: overlay) ?? Offset.zero;
  final size = box?.size ?? Size.zero;
  final picked = await showMenu<_MenuAction>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx - 200, at.dy + size.height, overlay.size.width - at.dx - size.width, 0),
    popUpAnimationStyle: AnimationStyle(duration: Motion.fast, reverseDuration: Motion.fast),
    items: [
      for (final a in actions) ...[
        if (a.danger) const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: a,
          height: 40,
          child: Row(
            children: [
              Icon(a.icon, size: 18, color: a.danger ? p.danger : p.ink2),
              const SizedBox(width: 12),
              Text(a.label, style: context.text.bodyMedium!.copyWith(color: a.danger ? p.danger : p.ink)),
            ],
          ),
        ),
      ],
    ],
  );
  picked?.run();
}
