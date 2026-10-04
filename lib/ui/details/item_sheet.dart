import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/ytdlp.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../platform/info.dart';
import '../home/preset_picker.dart';
import '../item_actions.dart';
import '../settings/settings_screen.dart';
import '../widgets/kit.dart';
import '../widgets/thumb.dart';
import '../widgets/toast.dart';

/// Opens the details for one item: a bottom sheet on phones, a centred
/// dialog on wider windows.
Future<void> showItemDetails(BuildContext context, String id, {required bool compact}) {
  if (compact) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ItemDetails(id: id, scroll: scroll, compact: true),
      ),
    );
  }
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.3),
    transitionDuration: Motion.normal,
    pageBuilder: (ctx, _, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: ctx.palette.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            clipBehavior: Clip.antiAlias,
            child: ItemDetails(id: id, compact: false),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Motion.ease, reverseCurve: Motion.easeIn);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(c), child: child),
      );
    },
  );
}

class ItemDetails extends StatefulWidget {
  const ItemDetails({super.key, required this.id, required this.compact, this.scroll});
  final String id;
  final bool compact;
  final ScrollController? scroll;

  @override
  State<ItemDetails> createState() => _ItemDetailsState();
}

class _ItemDetailsState extends State<ItemDetails> {
  Future<List<FormatChoice>>? _choices;

  void _loadChoices() {
    setState(() => _choices = AppScope.read(context).queue.loadChoices(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final item = q.byId(widget.id);
    final p = context.palette;

    if (item == null) {
      // Removed while open — close quietly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
      return const SizedBox(height: 120);
    }

    final site = detectSite(item.url);
    final meta = [
      site.label,
      if (item.uploader != null) item.uploader!,
      if (item.duration != null) formatDuration(item.duration),
    ].join(' · ');

    return ListView(
      controller: widget.scroll,
      shrinkWrap: !widget.compact,
      padding: EdgeInsets.fromLTRB(20, widget.compact ? 10 : 20, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (widget.compact) ...[const SheetHandle(), const SizedBox(height: 16)],
        Hero(
          tag: 'thumb-${item.id}',
          child: LayoutBuilder(
            builder: (ctx, c) => VideoThumb(url: item.thumbnail, link: item.url, width: c.maxWidth, radius: 14, audio: item.isAudio),
          ),
        ),
        const SizedBox(height: 16),
        Text(item.displayTitle, style: context.text.titleLarge, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(meta, style: context.text.bodySmall),
        if (item.collection != null) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: Tag(item.collection!, icon: Icons.playlist_play_rounded)),
        ],
        const SizedBox(height: 18),
        AnimatedSize(
          duration: Motion.normal,
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: _StatusBlock(item: item),
        ),
        const SizedBox(height: 18),
        _Actions(item: item, compact: widget.compact),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Quality', style: context.text.titleSmall),
            const Spacer(),
            if (_choices == null && item.status != DownloadStatus.downloading)
              HaulButton(
                label: 'Show all formats',
                dense: true,
                tone: ButtonTone.ghost,
                icon: Icons.tune_rounded,
                onPressed: _loadChoices,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in FormatPreset.values)
              _Choice(
                label: preset.label,
                selected: item.customFormat == null && item.preset == preset,
                onTap: () => _apply(item, preset: preset),
              ),
          ],
        ),
        if (_choices != null)
          FutureBuilder<List<FormatChoice>>(
            future: _choices,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Spinner()));
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('This site offers a single format, so the presets above are all there is.', style: context.text.bodySmall),
                );
              }
              return Appear(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Column(
                      children: [
                        for (final (i, c) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _FormatRow(
                            choice: c,
                            selected: item.customFormat?.selector == c.format.selector,
                            onTap: () => _apply(item, custom: c.format),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 24),
        Text('Link', style: context.text.titleSmall),
        const SizedBox(height: 6),
        SelectableText(item.url, style: context.text.bodySmall),
        if (item.filePath != null) ...[
          const SizedBox(height: 14),
          Text(AppScope.of(context).remote != null ? 'On your computer' : 'Saved to', style: context.text.titleSmall),
          const SizedBox(height: 6),
          SelectableText(item.filePath!, style: context.text.bodySmall),
        ],
        if (item.localPath != null) ...[
          const SizedBox(height: 14),
          Text('On this phone', style: context.text.titleSmall),
          const SizedBox(height: 6),
          Text('Files app → On My iPhone → Haul', style: context.text.bodySmall),
        ],
      ],
    );
  }

  void _apply(DownloadItem item, {FormatPreset? preset, CustomFormat? custom}) {
    final q = AppScope.read(context).queue;
    final same = custom == null ? item.customFormat == null && item.preset == preset : item.customFormat?.selector == custom.selector;
    if (same && item.status != DownloadStatus.failed) return;
    HapticFeedback.selectionClick();
    final wasDone = item.status == DownloadStatus.done;
    q.setFormat(item.id, preset: preset, custom: custom);
    ToastHost.show(
      context,
      wasDone ? 'Downloading again as ${custom?.label ?? preset!.label}' : 'Switched to ${custom?.label ?? preset!.label}',
      icon: Icons.tune_rounded,
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final q = QueueScope.of(context);
    final p = context.palette;

    if (item.status == DownloadStatus.failed) {
      final err = q.errorFor(item.id);
      final action = err?.action ?? ErrorAction.none;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
                const SizedBox(width: 10),
                Expanded(child: Text(item.error ?? 'Download failed', style: context.text.bodyMedium!.copyWith(color: p.ink))),
              ],
            ),
            if (err?.raw != null && err!.raw != err.message) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: SelectableText(err.raw!, style: context.mono.copyWith(fontSize: 12, color: p.ink), maxLines: 4),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HaulButton(label: 'Try again', icon: Icons.refresh_rounded, dense: true, tone: ButtonTone.primary, onPressed: () => q.retry(item.id)),
                  if (action == ErrorAction.retryBest)
                    HaulButton(label: 'Use best available', dense: true, onPressed: () => q.retry(item.id, preset: FormatPreset.best)),
                  if (action == ErrorAction.updateEngine)
                    _UpdateEngineButton(onDone: () => q.retry(item.id)),
                  if (action == ErrorAction.cookies || action == ErrorAction.installFfmpeg)
                    HaulButton(
                      label: 'Open settings',
                      dense: true,
                      onPressed: () => Navigator.of(context).push(SettingsScreen.route()),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final (String label, double? value, bool show) = switch (item.status) {
      DownloadStatus.queued => (q.isProbing(item.id) ? 'Fetching details' : 'Queued. Starts when another download finishes.', null, true),
      DownloadStatus.fetching => ('Fetching details', null, true),
      DownloadStatus.downloading => (
          [
            if (item.progress != null) '${(item.progress! * 100).toStringAsFixed(0)}%',
            progressSummary(item),
          ].where((s) => s.isNotEmpty).join(' · ').ifEmpty('Starting…'),
          item.progress,
          true
        ),
      DownloadStatus.processing => (item.isAudio ? 'Converting audio' : 'Merging video and audio', null, true),
      DownloadStatus.paused => ('Paused', item.progress ?? 0, true),
      DownloadStatus.done => (
          item.skippedExisting
              ? 'Skipped because you downloaded it before. Use Download anyway to get it again.'
              : 'Downloaded ${item.completedAt == null ? '' : relativeTime(item.completedAt!)}${item.fileSize == null ? '' : ' · ${formatBytes(item.fileSize)}'}',
          1.0,
          false
        ),
      DownloadStatus.failed => ('', null, false),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.status == DownloadStatus.done)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(item.skippedExisting ? Icons.history_rounded : Icons.check_circle_rounded, size: 18, color: p.accent),
              ),
            Expanded(child: Text(label, style: context.text.bodyMedium!.copyWith(color: p.ink2))),
          ],
        ),
        if (show) ...[
          const SizedBox(height: 10),
          ProgressLine(value: value, height: 5, color: item.status == DownloadStatus.paused ? p.ink3 : p.accent),
        ],
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _UpdateEngineButton extends StatefulWidget {
  const _UpdateEngineButton({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_UpdateEngineButton> createState() => _UpdateEngineButtonState();
}

class _UpdateEngineButtonState extends State<_UpdateEngineButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => HaulButton(
        label: 'Update engine',
        icon: Icons.system_update_alt_rounded,
        dense: true,
        loading: _busy,
        onPressed: () async {
          setState(() => _busy = true);
          final toast = ToastHost.of(context);
          final msg = await AppScope.read(context).engine.updateYtDlp();
          if (!mounted) return;
          setState(() => _busy = false);
          toast?.show(ToastData(msg, icon: Icons.system_update_alt_rounded));
          widget.onDone();
        },
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.item, required this.compact});
  final DownloadItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = QueueScope.of(context);

    final reach = reachOf(app, item);
    final here = localFileOf(app, item);
    final primary = <Widget>[
      if (item.saveProgress != null)
        HaulButton(label: 'Copying ${(item.saveProgress! * 100).round()}%', icon: Icons.download_rounded, loading: true, onPressed: null)
      else if (reach != Reach.none)
        HaulButton(
          label: openLabel(app, item),
          icon: openIcon(app, item),
          tone: ButtonTone.primary,
          onPressed: () => openItem(context, item),
        ),
      if (reach == Reach.here && isHandheld)
        HaulButton(label: 'Share', icon: Icons.ios_share_rounded, onPressed: () => app.bridge.shareFile(here!, contentUri: item.contentUri, title: item.title)),
      if (reach == Reach.here && isDesktop)
        HaulButton(label: 'Show in folder', icon: Icons.folder_open_rounded, onPressed: () => app.bridge.revealFile(here!)),
      if (item.status == DownloadStatus.done && item.skippedExisting)
        HaulButton(label: 'Download anyway', icon: Icons.download_rounded, tone: ButtonTone.primary, onPressed: () => q.redownload(item.id)),
      if (item.status.isActive || item.status == DownloadStatus.queued)
        HaulButton(label: 'Pause', icon: Icons.pause_rounded, onPressed: () => q.pause(item.id)),
      if (item.status == DownloadStatus.paused)
        HaulButton(label: 'Resume', icon: Icons.play_arrow_rounded, tone: ButtonTone.primary, onPressed: () => q.resume(item.id)),
    ];

    final secondary = <Widget>[
      HaulButton(
        label: 'Copy link',
        icon: Icons.link_rounded,
        tone: ButtonTone.ghost,
        dense: true,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: item.url));
          ToastHost.show(context, 'Link copied', icon: Icons.link_rounded);
        },
      ),
      HaulButton(label: 'Open page', icon: Icons.open_in_new_rounded, tone: ButtonTone.ghost, dense: true, onPressed: () => app.bridge.openUrl(item.url)),
      HaulButton(
        label: 'Remove',
        icon: Icons.delete_outline_rounded,
        tone: ButtonTone.ghost,
        dense: true,
        onPressed: () {
          Navigator.pop(context);
          q.remove(item.id);
        },
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (primary.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: primary),
          const SizedBox(height: 10),
        ],
        Transform.translate(
          offset: const Offset(-6, 0),
          child: Wrap(spacing: 2, runSpacing: 4, children: secondary),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.accent : p.sunken,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: context.text.labelLarge!.copyWith(fontSize: 13, color: selected ? p.onAccent : p.ink),
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.choice, required this.selected, required this.onTap});
  final FormatChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      pressScale: 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(choice.format.audioOnly ? Icons.music_note_rounded : Icons.movie_outlined, size: 17, color: selected ? p.accent : p.ink3),
          const SizedBox(width: 12),
          Text(choice.format.label, style: context.text.titleSmall!.copyWith(color: selected ? p.accent : p.ink)),
          const SizedBox(width: 8),
          if (choice.detail != null && choice.detail!.isNotEmpty) Text(choice.detail!, style: context.text.bodySmall),
          const Spacer(),
          if (choice.sizeBytes != null) Text('~${formatBytes(choice.sizeBytes)}', style: context.text.labelMedium),
          AnimatedSize(
            duration: Motion.fast,
            child: selected
                ? Padding(padding: const EdgeInsets.only(left: 10), child: Icon(Icons.check_rounded, size: 18, color: p.accent))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
