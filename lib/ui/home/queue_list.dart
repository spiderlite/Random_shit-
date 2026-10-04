import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import 'queue_tile.dart';

/// The queue, with items that grow in when added and fold away when
/// removed. Works on a plain [ListView.builder], so a 2,000-video channel
/// scrolls as smoothly as five links.
class QueueList extends StatefulWidget {
  const QueueList({
    super.key,
    required this.items,
    required this.compact,
    required this.onOpenDetails,
    this.padding = EdgeInsets.zero,
    this.controller,
  });

  final List<DownloadItem> items;
  final bool compact;
  final void Function(DownloadItem) onOpenDetails;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  State<QueueList> createState() => _QueueListState();
}

class _Entry {
  _Entry(this.item);
  DownloadItem item;
  bool leaving = false;
}

class _QueueListState extends State<QueueList> {
  late List<_Entry> _entries = [for (final i in widget.items) _Entry(i)];
  /// Ids added since the last frame — only these animate in.
  final Set<String> _fresh = {};
  /// Ids swiped away; they're already gone visually.
  final Set<String> _dismissed = {};
  final Map<String, Timer> _leaveTimers = {};

  @override
  void didUpdateWidget(QueueList old) {
    super.didUpdateWidget(old);
    final nextIds = {for (final i in widget.items) i.id};
    final prev = {for (final e in _entries) e.item.id: e};

    final merged = <_Entry>[];
    for (final e in _entries) {
      if (nextIds.contains(e.item.id)) continue;
      // Leaving: keep it at its old position while it folds away.
      if (_dismissed.remove(e.item.id)) continue;
      if (!e.leaving) {
        e.leaving = true;
        _leaveTimers[e.item.id] = Timer(Motion.normal + const Duration(milliseconds: 40), () {
          if (!mounted) return;
          setState(() => _entries.removeWhere((x) => x.item.id == e.item.id && x.leaving));
          _leaveTimers.remove(e.item.id);
        });
      }
    }
    // Rebuild order from the new list, slotting leaving entries back near
    // where they were so nothing jumps.
    final leavingAt = <int, List<_Entry>>{};
    for (final (n, e) in _entries.indexed) {
      if (e.leaving && !nextIds.contains(e.item.id)) (leavingAt[n] ??= []).add(e);
    }
    var oldIndex = 0;
    for (final item in widget.items) {
      while (leavingAt.containsKey(oldIndex)) {
        merged.addAll(leavingAt.remove(oldIndex)!);
        oldIndex++;
      }
      final existing = prev[item.id];
      if (existing != null) {
        existing
          ..item = item
          ..leaving = false;
        _leaveTimers.remove(item.id)?.cancel();
        merged.add(existing);
      } else {
        _fresh.add(item.id);
        merged.add(_Entry(item));
      }
      oldIndex++;
    }
    for (final rest in leavingAt.values) {
      merged.addAll(rest);
    }
    _entries = merged;
  }

  @override
  void dispose() {
    for (final t in _leaveTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return ListView.builder(
      controller: widget.controller,
      padding: widget.padding,
      itemCount: _entries.length,
      // Rows are a fixed-ish height; this keeps long lists cheap.
      itemBuilder: (context, n) {
        final e = _entries[n];
        final animateIn = _fresh.remove(e.item.id);
        Widget tile = QueueTile(
          key: ValueKey('tile-${e.item.id}'),
          item: e.item,
          compact: widget.compact,
          onOpenDetails: () => widget.onOpenDetails(e.item),
        );
        if (widget.compact && !e.leaving) {
          tile = Dismissible(
            key: ValueKey('swipe-${e.item.id}'),
            direction: DismissDirection.endToStart,
            dismissThresholds: const {DismissDirection.endToStart: 0.35},
            movementDuration: Motion.normal,
            background: _SwipeBackground(),
            onUpdate: (d) {
              if (d.reached && !d.previousReached) HapticFeedback.selectionClick();
            },
            onDismissed: (_) {
              _dismissed.add(e.item.id);
              app.queue.remove(e.item.id);
            },
            child: tile,
          );
        }
        return _Animated(
          key: ValueKey(e.item.id),
          animateIn: animateIn,
          leaving: e.leaving,
          child: tile,
        );
      },
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
      child: Icon(Icons.delete_outline_rounded, color: p.danger),
    );
  }
}

class _Animated extends StatefulWidget {
  const _Animated({super.key, required this.child, required this.animateIn, required this.leaving});
  final Widget child;
  final bool animateIn;
  final bool leaving;

  @override
  State<_Animated> createState() => _AnimatedState();
}

class _AnimatedState extends State<_Animated> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.normal,
    value: widget.animateIn ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.leaving) {
      _c.value = 0;
    } else if (widget.animateIn) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_Animated old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _c.reverse();
    if (!widget.leaving && old.leaving) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Motion.ease, reverseCurve: Motion.easeIn);
    return IgnorePointer(
      ignoring: widget.leaving,
      child: SizeTransition(
        sizeFactor: curve,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: curve,
          child: AnimatedBuilder(
            animation: curve,
            builder: (_, c) => Transform.translate(offset: Offset(0, (1 - curve.value) * 8), child: c),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
