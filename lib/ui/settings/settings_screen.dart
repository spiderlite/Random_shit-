import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../platform/info.dart';
import '../../platform/io.dart' as io;
import '../../services/engine.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../home/preset_picker.dart';
import '../widgets/kit.dart';
import '../widgets/toast.dart';
import 'phone_access.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
        transitionDuration: Motion.normal,
        reverseTransitionDuration: Motion.fast,
        pageBuilder: (_, _, _) => const SettingsScreen(),
        transitionsBuilder: (_, a, _, child) {
          final c = CurvedAnimation(parent: a, curve: Motion.ease, reverseCurve: Motion.easeIn);
          return FadeTransition(
            opacity: c,
            child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(c), child: child),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final mobile = app.engine.isMobile;
    final remote = app.remote;
    // Only a local desktop engine can choose its own folder.
    final pickable = !mobile && remote == null;
    final p = context.palette;

    final sections = <Widget>[
      _Section(
        title: 'Downloads',
        children: [
          _Row(
            title: 'Default quality',
            subtitle: s.preset.description,
            trailing: PresetChip(
              value: s.preset,
              compact: mobile,
              onChanged: (v) => app.update((s) => s.copyWith(preset: v)),
            ),
          ),
          _Row(
            title: remote != null ? 'Saved on ${remote.info?.name ?? 'your computer'} in' : 'Save to',
            subtitle: prettyPath(app.downloadDir, _home),
            onTap: pickable ? () => _pickFolder(context) : null,
            trailing: !pickable
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s.downloadDir != null)
                        IconBtn(
                          icon: Icons.undo_rounded,
                          tooltip: 'Back to default',
                          onPressed: () => app.update((s) => Settings.fromJson({...s.toJson(), 'downloadDir': null})),
                        ),
                      HaulButton(label: 'Change', dense: true, onPressed: () => _pickFolder(context)),
                    ],
                  ),
          ),
          if (remote != null && !isWeb)
            _Switch(
              title: 'Copy to this phone',
              subtitle: 'Finished videos come over automatically and appear in the Files app.',
              value: s.saveToDevice,
              onChanged: (v) => app.update((s) => s.copyWith(saveToDevice: v)),
            ),
          _Row(
            title: 'Simultaneous downloads',
            subtitle: s.concurrency == 1 ? '1 at a time' : '${s.concurrency} at a time',
            below: Slider(
              value: s.concurrency.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              label: '${s.concurrency}',
              onChanged: (v) => app.update((s) => s.copyWith(concurrency: v.round())),
            ),
          ),
          _Switch(
            title: 'Most compatible format',
            subtitle: 'Saves H.264 video in MP4, which every phone, TV and editor can play. Turn off for the highest quality (VP9 or AV1).',
            value: s.preferCompatible,
            onChanged: (v) => app.update((s) => s.copyWith(preferCompatible: v)),
          ),
          _Switch(
            title: 'Skip videos you already downloaded',
            subtitle: 'Adding a playlist or channel again only fetches its new videos.',
            value: s.skipDownloaded,
            onChanged: (v) => app.update((s) => s.copyWith(skipDownloaded: v)),
          ),
        ],
      ),
      _Section(
        title: 'Files',
        children: [
          _Row(
            title: 'File names',
            subtitle: _example(s.nameStyle),
            below: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in NameStyle.values)
                    _Pill(label: n.label, selected: s.nameStyle == n, onTap: () => app.update((s) => s.copyWith(nameStyle: n))),
                ],
              ),
            ),
          ),
          _Switch(
            title: 'Folder per playlist',
            subtitle: 'Videos from a playlist or channel go into their own folder.',
            value: s.collectionFolders,
            onChanged: (v) => app.update((s) => s.copyWith(collectionFolders: v)),
          ),
          _Switch(
            title: 'Embed thumbnail',
            subtitle: 'Players and file browsers show it as cover art.',
            value: s.embedThumbnail,
            onChanged: (v) => app.update((s) => s.copyWith(embedThumbnail: v)),
          ),
          _Switch(
            title: 'Embed title and creator',
            subtitle: 'Stored inside the file, so it stays with it when moved.',
            value: s.embedMetadata,
            onChanged: (v) => app.update((s) => s.copyWith(embedMetadata: v)),
          ),
          _Switch(
            title: 'Subtitles',
            subtitle: 'Include English subtitles when available.',
            value: s.subtitles,
            onChanged: (v) => app.update((s) => s.copyWith(subtitles: v)),
          ),
        ],
      ),
      if (isDesktop && remote == null)
        _Section(
          title: 'Convenience',
          children: [
            _Switch(
              title: 'Offer copied links',
              subtitle: 'When you switch to Haul with a link on your clipboard, show a button to download it.',
              value: s.watchClipboard,
              onChanged: (v) => app.update((s) => s.copyWith(watchClipboard: v)),
            ),
            _Row(
              title: 'Use a browser\'s login',
              subtitle: 'Needed for private, age-restricted or members-only videos. Haul reads that browser\'s cookies when downloading.',
              below: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in [null, 'chrome', 'firefox', 'safari', 'edge', 'brave', 'chromium', 'opera', 'vivaldi'])
                      _Pill(
                        label: b == null ? 'Off' : b[0].toUpperCase() + b.substring(1),
                        selected: s.cookiesBrowser == b,
                        onTap: () => app.update((s) => s.copyWith(cookiesBrowser: () => b)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      _Section(
        title: 'Appearance',
        children: [
          _Row(
            title: 'Theme',
            trailing: Segmented<ThemePref>(
              items: const [(ThemePref.system, 'System'), (ThemePref.light, 'Light'), (ThemePref.dark, 'Dark')],
              value: s.theme,
              onChanged: (v) => app.update((s) => s.copyWith(theme: v)),
            ),
          ),
        ],
      ),
      if (app.canHostRemote) const _Section(title: 'Use from your phone', children: [PhoneAccess()]),
      if (remote != null)
        _Section(
          title: 'Computer',
          children: [
            _Row(
              title: remote.info?.name ?? 'Your computer',
              subtitle: isWeb ? 'This page is served by it' : 'Connected at ${remote.base?.authority ?? ''}',
              trailing: isWeb
                  ? null
                  : HaulButton(
                      label: 'Disconnect',
                      dense: true,
                      tone: ButtonTone.danger,
                      onPressed: () {
                        Navigator.of(context).pop();
                        app.disconnect();
                      },
                    ),
            ),
          ],
        ),
      _Section(title: 'Engine', children: [const _EngineTools()]),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          'Haul runs on yt-dlp. Only download what you have the right to keep.',
          style: context.text.bodySmall!.copyWith(color: p.ink3),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconBtn(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  Text('Settings', style: context.text.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    itemCount: sections.length,
                    itemBuilder: (_, i) => sections[i],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? get _home => homeDirectory;

  static String _example(NameStyle n) => switch (n) {
        NameStyle.title => 'Ocean waves for focus.mp4',
        NameStyle.titleId => 'Ocean waves for focus [x7Gk2pQ].mp4',
        NameStyle.uploaderTitle => 'Soft Noise – Ocean waves for focus.mp4',
        NameStyle.dateTitle => '2026-05-20 Ocean waves for focus.mp4',
      };

  Future<void> _pickFolder(BuildContext context) async {
    final app = AppScope.read(context);
    final dir = await getDirectoryPath(initialDirectory: app.downloadDir, confirmButtonText: 'Save here');
    if (dir != null) {
      app.update((s) => s.copyWith(downloadDir: dir));
      if (context.mounted) ToastHost.show(context, 'New downloads go to ${prettyPath(dir, homeDirectory)}', icon: Icons.folder_rounded);
    }
  }
}

String? get homeDirectory => io.homeDir();

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: context.text.labelMedium!.copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: p.line),
            ),
            child: Column(
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Divider(color: p.line)),
                  c,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing, this.below, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.text.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          ?below,
        ],
      ),
    );
    return onTap == null ? content : Pressable(onTap: onTap, pressScale: 1, borderRadius: BorderRadius.circular(Radii.lg), child: content);
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => onChanged(!value),
        pressScale: 1,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: _Row(
          title: title,
          subtitle: subtitle,
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : p.sunken,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? p.accent.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Text(label, style: context.text.labelMedium!.copyWith(color: selected ? p.accent : p.ink, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _EngineTools extends StatefulWidget {
  const _EngineTools();
  @override
  State<_EngineTools> createState() => _EngineToolsState();
}

class _EngineToolsState extends State<_EngineTools> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final tools = app.engine.tools;
    final p = context.palette;
    return Column(
      children: [
        for (final (i, t) in tools.indexed) ...[
          if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Divider(color: p.line)),
          _Row(
            title: t.name,
            subtitle: switch (t.state) {
              ToolState.ready => [t.version ?? 'Ready', if (!t.managed && !app.engine.isMobile) 'from your system'].join(' · '),
              ToolState.installing => t.progress == null ? 'Working…' : 'Downloading… ${(t.progress! * 100).round()}%',
              ToolState.missing => '${t.purpose}${t.sizeHint == null ? '' : ' · ${t.sizeHint}'}',
              ToolState.failed => t.error ?? 'Couldn\'t install',
            },
            trailing: switch (t.state) {
              ToolState.installing => const Padding(padding: EdgeInsets.all(8), child: Spinner()),
              ToolState.ready when t.id == 'yt-dlp' => HaulButton(
                  label: 'Update',
                  dense: true,
                  loading: _updating,
                  onPressed: () async {
                    setState(() => _updating = true);
                    final msg = await app.engine.updateYtDlp();
                    if (!context.mounted) return;
                    setState(() => _updating = false);
                    ToastHost.show(context, msg, icon: Icons.system_update_alt_rounded);
                  },
                ),
              ToolState.ready => Icon(Icons.check_circle_rounded, color: p.accent, size: 20),
              _ => HaulButton(label: 'Install', dense: true, tone: ButtonTone.primary, onPressed: () => app.engine.installTool(t.id)),
            },
          ),
        ],
      ],
    );
  }
}
