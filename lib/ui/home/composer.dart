import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/links.dart';
import '../../core/models.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';
import '../widgets/toast.dart';
import 'preset_picker.dart';

/// Where links go in. One field for one link or a hundred: anything with
/// URLs in it is fine, we pull them out.
///
/// With an empty field the main button becomes "Paste", which reads the
/// clipboard and starts immediately — the fastest path from "copied a
/// link" to "downloading".
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.preset,
    required this.onPresetChanged,
    required this.onSubmit,
    required this.focusNode,
    this.compact = false,
  });

  final FormatPreset preset;
  final ValueChanged<FormatPreset> onPresetChanged;
  /// Returns true if something was added, so the field can clear.
  final bool Function(String text) onSubmit;
  final FocusNode focusNode;
  final bool compact;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  int _links = 0;
  bool _shake = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final n = extractLinks(_controller.text).length;
      if (n != _links) setState(() => _links = n);
      if (_controller.text.isEmpty != _wasEmpty) setState(() => _wasEmpty = _controller.text.isEmpty);
    });
    widget.focusNode.addListener(_onFocus);
  }

  bool _wasEmpty = true;

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _primary() async {
    if (_controller.text.trim().isEmpty) {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text ?? '';
      if (extractLinks(text).isEmpty) {
        _nudge(text.trim().isEmpty ? 'Your clipboard is empty. Copy a link first.' : 'No links in what you copied.');
        if (mounted && text.trim().isEmpty) {
          widget.focusNode.requestFocus();
        } else if (mounted) {
          _controller.text = text;
        }
        return;
      }
      HapticFeedback.lightImpact();
      widget.onSubmit(text);
      return;
    }
    if (_links == 0) {
      _nudge('No links found. Links start with http:// or https://');
      return;
    }
    HapticFeedback.lightImpact();
    if (widget.onSubmit(_controller.text)) {
      _controller.clear();
    }
  }

  /// Says what's wrong (a toast, which screen readers announce) and gives
  /// a small shake, unless the user asked for reduced motion.
  void _nudge(String message) {
    HapticFeedback.heavyImpact();
    ToastHost.of(context)?.show(ToastData(message, icon: Icons.link_off_rounded));
    if (Motion.reduced) return;
    setState(() => _shake = true);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _shake = false);
    });
  }

  /// For drag & drop / external callers.
  void insert(String text) {
    final cur = _controller.text.trimRight();
    _controller.text = cur.isEmpty ? text : '$cur\n$text';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  String get _buttonLabel {
    if (_controller.text.trim().isEmpty) return 'Paste and download';
    if (_links <= 1) return 'Download';
    return 'Download $_links';
  }

  @override
  Widget build(BuildContext context) => widget.compact ? _buildCompact(context) : _buildWide(context);

  Widget _field(BuildContext context, {required String hint, required int maxLines, double vPad = 0}) {
    final p = context.palette;
    return Shortcuts(
      shortcuts: {
        // Enter downloads; Shift+Enter makes a new line.
        const SingleActivator(LogicalKeyboardKey.enter): const _SubmitIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): const _SubmitIntent(),
      },
      child: Actions(
        actions: {_SubmitIntent: CallbackAction<_SubmitIntent>(onInvoke: (_) => _primary())},
        child: TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          minLines: 1,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: context.text.bodyLarge,
          cursorWidth: 1.6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            isCollapsed: true,
            // On phones the field itself is a 48dp touch target.
            contentPadding: EdgeInsets.symmetric(vertical: vPad),
            border: InputBorder.none,
            hintText: hint,
            hintStyle: context.text.bodyLarge!.copyWith(color: p.ink3),
          ),
        ),
      ),
    );
  }

  Widget _shakeWrap(Widget child) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _shake ? 1 : 0),
        duration: const Duration(milliseconds: 400),
        builder: (_, t, c) {
          // A small damped wobble: "nothing to download here".
          final dx = _shake ? math.sin(t * math.pi * 6) * 7 * (1 - t) : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: c);
        },
        child: child,
      );

  Widget _buildWide(BuildContext context) {
    final p = context.palette;
    final focused = widget.focusNode.hasFocus;
    return _shakeWrap(
      AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.ease,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          // Focus is a solid border change; no coloured glow.
          border: Border.all(color: focused ? p.accent : p.line, width: focused ? 2 : 1),
        ),
        padding: EdgeInsets.fromLTRB(focused ? 17 : 18, focused ? 15 : 16, focused ? 9 : 10, focused ? 9 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _field(context, hint: 'Paste one link or many', maxLines: 7),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _LinkCount(count: _links, empty: _controller.text.isEmpty)),
                PresetChip(value: widget.preset, onChanged: widget.onPresetChanged),
                const SizedBox(width: 8),
                AnimatedSize(
                  duration: Motion.normal,
                  curve: Motion.ease,
                  child: HaulButton(
                    label: _buttonLabel,
                    icon: _controller.text.trim().isEmpty ? Icons.content_paste_rounded : Icons.arrow_downward_rounded,
                    tone: ButtonTone.primary,
                    onPressed: _primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final p = context.palette;
    final empty = _controller.text.trim().isEmpty;
    return _shakeWrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: Motion.normal,
            curve: Motion.ease,
            alignment: Alignment.bottomCenter,
            child: _links > 1 || (widget.focusNode.hasFocus && !empty)
                ? Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 8),
                    child: _LinkCount(count: _links, empty: empty),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.normal,
                  curve: Motion.ease,
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.fromLTRB(14, 0, 2, 0),
                  decoration: BoxDecoration(
                    color: p.sunken,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(
                      color: widget.focusNode.hasFocus ? p.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _field(context, hint: 'Paste links', maxLines: 5, vPad: 14)),
                      PresetChip(value: widget.preset, onChanged: widget.onPresetChanged, compact: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: _primary,
                semanticLabel: empty ? 'Paste from clipboard and download' : 'Download',
                color: p.accent,
                hoverColor: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.lg),
                pressScale: 0.94,
                tooltip: empty ? 'Paste and download' : 'Download',
                child: SizedBox.square(
                  dimension: 52,
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Icon(
                      empty ? Icons.content_paste_rounded : Icons.arrow_downward_rounded,
                      key: ValueKey(empty),
                      color: p.onAccent,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _LinkCount extends StatelessWidget {
  const _LinkCount({required this.count, required this.empty});
  final int count;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (text, color) = empty
        ? ('Video, playlist or channel links from most sites', p.ink3)
        : count == 0
            ? ('No links yet', p.ink2)
            : (count == 1 ? '1 link' : '$count links', p.accent);
    return AnimatedSwitcher(
      duration: Motion.fast,
      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: c),
      ),
      child: Row(
        key: ValueKey(text),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!empty && count > 0) ...[Icon(Icons.link_rounded, size: 15, color: color), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium!.copyWith(color: color, fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
