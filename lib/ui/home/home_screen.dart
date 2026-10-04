import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/links.dart';
import '../../platform/info.dart';
import '../../platform/io.dart' as io;
import '../../state/app_state.dart';
import '../../state/queue.dart';
import '../../theme/theme.dart';
import '../details/item_sheet.dart';
import '../settings/settings_screen.dart';
import '../widgets/kit.dart';
import '../widgets/toast.dart';
import 'composer.dart';
import 'empty_state.dart';
import 'queue_header.dart';
import 'queue_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  QueueFilter _filter = QueueFilter.all;
  bool _dragging = false;
  StreamSubscription<Notice>? _noticeSub;
  StreamSubscription<String>? _shareSub;
  AppLifecycleListener? _lifecycle;

  /// Links found on the clipboard that we're offering to add.
  List<String> _clipLinks = const [];
  final Set<String> _clipSeen = {};

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _noticeSub = app.queue.notices.listen(_showNotice);

    // Android: "Share → Haul" from any app.
    _shareSub = app.bridge.sharedText.listen(_receiveShare);
    app.bridge.takeInitialShare().then((t) {
      if (t != null) _receiveShare(t);
    });

    if (!app.engine.isMobile) {
      _lifecycle = AppLifecycleListener(onResume: _checkClipboard);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    }
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    _shareSub?.cancel();
    _lifecycle?.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ToastHostState? get _toast => ToastHost.of(context);

  void _showNotice(Notice n) {
    _toast?.show(ToastData(
      n.message,
      icon: Icons.playlist_add_check_rounded,
      actionLabel: n.undo != null ? 'Undo' : n.actionLabel,
      onAction: n.undo ?? n.action,
    ));
    // Expanded playlists land in "all"; make sure they're visible.
    if (_filter == QueueFilter.done || _filter == QueueFilter.failed) setState(() => _filter = QueueFilter.all);
  }

  void _receiveShare(String text) {
    final links = extractLinks(text);
    if (links.isEmpty) {
      _toast?.show(ToastData('That share didn\'t contain a link', icon: Icons.link_off_rounded));
      return;
    }
    _add(links, fromShare: true);
  }

  /// The single entry point for "the user wants these downloaded".
  bool _add(List<String> links, {bool fromShare = false, String? source}) {
    final app = AppScope.read(context);
    if (links.isEmpty) {
      _toast?.show(ToastData('No links found in that', icon: Icons.link_off_rounded));
      return false;
    }
    // Ask for notification (and, on old Android, storage) access in
    // context — the first time something is actually downloading.
    app.bridge.ensurePermissions();
    final r = app.queue.addUrls(links);
    _clipSeen.addAll(links.map(canonicalKey));
    if (_clipLinks.isNotEmpty) setState(() => _clipLinks = const []);
    if (_filter != QueueFilter.all && _filter != QueueFilter.active) setState(() => _filter = QueueFilter.all);
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: Motion.slow, curve: Motion.ease);
    }

    if (r.added == 0) {
      _toast?.show(ToastData(
        links.length == 1 ? 'Already in your list' : 'All ${links.length} are already in your list',
        icon: Icons.inbox_rounded,
      ));
    } else if (r.added > 1 || r.duplicates > 0 || fromShare || source != null) {
      final what = r.added == 1 ? '1 link' : '${r.added} links';
      final extra = r.duplicates > 0 ? ' · ${r.duplicates} already here' : '';
      _toast?.show(ToastData(
        '${source == null ? 'Added' : 'Added from $source:'} $what$extra',
        icon: Icons.south_rounded,
        actionLabel: 'Undo',
        onAction: () => app.queue.removeMany(r.ids.toSet(), silent: true),
      ));
    }
    HapticFeedback.lightImpact();
    return r.added > 0 || r.duplicates > 0;
  }

  Future<void> _checkClipboard() async {
    final app = AppScope.read(context);
    if (!app.settings.watchClipboard || !mounted) return;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      final known = {for (final i in app.queue.items) canonicalKey(i.url)};
      final fresh = extractLinks(text).where((l) {
        final k = canonicalKey(l);
        return !known.contains(k) && !_clipSeen.contains(k);
      }).toList();
      if (mounted) setState(() => _clipLinks = fresh);
    } catch (_) {}
  }

  void _dismissClip() {
    _clipSeen.addAll(_clipLinks.map(canonicalKey));
    setState(() => _clipLinks = const []);
  }

  Future<void> _pasteAnywhere() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    _add(extractLinks(text));
  }

  Future<void> _onDrop(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final links = <String>[];
    var files = 0;
    for (final f in d.files) {
      final path = f.path;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        links.add(path);
        continue;
      }
      final text = await io.readTextFile(path);
      if (text == null) continue;
      final found = extractLinks(text);
      if (found.isNotEmpty) files++;
      links.addAll(found);
    }
    if (!mounted) return;
    _add(links, source: files == 1 ? d.files.first.name : (files > 1 ? '$files files' : null));
  }

  void _openSettings() => Navigator.of(context).push(SettingsScreen.route());

  @override
  Widget build(BuildContext context) {
    // Subscribe to settings too (e.g. the quality chip in the composer).
    AppScope.of(context);
    final q = QueueScope.of(context);

    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 640;
        final items = q.items.where((i) => matchesFilter(_filter, i)).toList();

        final list = AnimatedSwitcher(
          duration: Motion.normal,
          switchInCurve: Motion.ease,
          child: items.isEmpty
              ? EmptyState(key: ValueKey('empty-$_filter'), filter: _filter, compact: compact, canShare: isAndroid, canDrop: isDesktop)
              : QueueList(
                  key: ValueKey('list-$_filter'),
                  items: items,
                  compact: compact,
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(compact ? 8 : 0, 4, compact ? 8 : 0, compact ? 16 : 32),
                  onOpenDetails: (i) => showItemDetails(context, i.id, compact: compact),
                ),
        );

        Widget body = compact ? _compact(context, list) : _wide(context, list);

        _toast?.extraInset = compact ? 76 : 0;

        if (isDesktop) {
          body = DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: _onDrop,
            child: Stack(children: [body, _DropOverlay(visible: _dragging)]),
          );
        }

        final mod = defaultTargetPlatform == TargetPlatform.macOS;
        return CallbackShortcuts(
          bindings: {
            SingleActivator(LogicalKeyboardKey.keyV, meta: mod, control: !mod): () {
              if (!_composerFocus.hasFocus) _pasteAnywhere();
            },
            SingleActivator(LogicalKeyboardKey.comma, meta: mod, control: !mod): _openSettings,
            SingleActivator(LogicalKeyboardKey.keyL, meta: mod, control: !mod): _composerFocus.requestFocus,
            const SingleActivator(LogicalKeyboardKey.escape): () => _composerFocus.unfocus(),
          },
          child: Focus(autofocus: true, child: body),
        );
      },
    );
  }

  Composer _composer({required bool compact}) {
    final app = AppScope.read(context);
    return Composer(
      compact: compact,
      focusNode: _composerFocus,
      preset: app.settings.preset,
      onPresetChanged: (v) {
        app.update((s) => s.copyWith(preset: v));
        _toast?.show(ToastData('New downloads: ${v.label} — ${v.description.toLowerCase()}', icon: Icons.tune_rounded));
      },
      onSubmit: (text) => _add(extractLinks(text)),
    );
  }

  Widget _wide(BuildContext context, Widget list) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Wordmark(),
                      const SizedBox(width: 20),
                      const Expanded(child: Align(alignment: Alignment.centerRight, child: QueueSummary())),
                      const SizedBox(width: 12),
                      IconBtn(icon: Icons.tune_rounded, tooltip: 'Settings', onPressed: _openSettings),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _composer(compact: false),
                  _ClipboardBanner(links: _clipLinks, onAdd: () => _add(_clipLinks), onDismiss: _dismissClip),
                  const SizedBox(height: 26),
                  QueueToolbar(filter: _filter, onFilter: (f) => setState(() => _filter = f), compact: false),
                  const SizedBox(height: 10),
                  Expanded(child: list),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, Widget list) {
    final p = context.palette;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
              child: Row(
                children: [
                  const Wordmark(size: 20),
                  const Spacer(),
                  IconBtn(icon: Icons.tune_rounded, tooltip: 'Settings', onPressed: _openSettings),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(18, 2, 18, 0), child: QueueSummary()),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: QueueToolbar(filter: _filter, onFilter: (f) => setState(() => _filter = f), compact: true),
            ),
            const SizedBox(height: 6),
            Expanded(child: list),
            // Bottom composer: within thumb reach, rides above the keyboard.
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.bg,
                border: Border(top: BorderSide(color: p.line.withValues(alpha: 0.6))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: _composer(compact: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipboardBanner extends StatelessWidget {
  const _ClipboardBanner({required this.links, required this.onAdd, required this.onDismiss});
  final List<String> links;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedSize(
      duration: Motion.normal,
      curve: Motion.ease,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Motion.normal,
        child: links.isEmpty
            ? const SizedBox(width: double.infinity, key: ValueKey('none'))
            : Padding(
                key: ValueKey(links.join()),
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                  child: Row(
                    children: [
                      Icon(Icons.content_paste_go_rounded, size: 18, color: p.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: links.length == 1 ? 'You copied a link  ' : 'You copied ${links.length} links  ',
                              style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                            ),
                            TextSpan(text: links.length == 1 ? _short(links.first) : detectSite(links.first).label),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium!.copyWith(color: p.ink2),
                        ),
                      ),
                      HaulButton(label: 'Download', dense: true, tone: ButtonTone.primary, onPressed: onAdd),
                      IconBtn(icon: Icons.close_rounded, tooltip: 'Not now', size: 32, iconSize: 17, onPressed: onDismiss),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  static String _short(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final host = u.host.startsWith('www.') ? u.host.substring(4) : u.host;
    return '$host${u.path}${u.query.isEmpty ? '' : '?${u.query}'}';
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.normal,
        curve: Motion.ease,
        child: Container(
          color: p.bg.withValues(alpha: 0.86),
          padding: const EdgeInsets.all(20),
          child: AnimatedScale(
            scale: visible ? 1 : 0.97,
            duration: Motion.normal,
            curve: Motion.ease,
            child: CustomPaint(
              painter: _DashedBorder(color: p.accent),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(20)),
                      child: Icon(Icons.south_rounded, color: p.accent, size: 28),
                    ),
                    const SizedBox(height: 16),
                    Text('Drop to download', style: context.text.titleLarge),
                    const SizedBox(height: 4),
                    Text('Text files, link lists, bookmarks — we\'ll find the links', style: context.text.bodyMedium!.copyWith(color: p.ink2)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.xl)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
