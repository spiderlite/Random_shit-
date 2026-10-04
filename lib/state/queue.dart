import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/links.dart';
import '../core/models.dart';
import '../core/ytdlp.dart';
import '../platform/info.dart';
import '../platform/io.dart' as io;
import '../services/engine.dart';
import '../services/platform_bridge.dart';
import '../services/remote_engine.dart';

/// Something worth a toast. [undo] makes it reversible.
class Notice {
  const Notice(this.message, {this.undo, this.actionLabel, this.action});
  final String message;
  final VoidCallback? undo;
  final String? actionLabel;
  final VoidCallback? action;
}

class AddResult {
  const AddResult(this.ids, this.duplicates);
  final List<String> ids;
  final int duplicates;
  int get added => ids.length;
}

/// The download queue: what's in it, what runs next, and everything that
/// happens to an item between "pasted" and "on disk".
///
/// Two pools run side by side: a small one that fetches titles and
/// thumbnails ahead of time (so a 50-link paste fills in quickly) and the
/// download pool, sized by the user's concurrency setting.
class QueueController extends ChangeNotifier {
  QueueController({
    required this.engine,
    required this.bridge,
    required this.settings,
    required this.downloadDir,
    required this.persist,
  });

  final Engine engine;
  final PlatformBridge bridge;
  final Settings Function() settings;
  final Future<String> Function() downloadDir;
  final VoidCallback persist;

  static const _probeSlots = 3;
  static const _historyLimit = 3000;

  final List<DownloadItem> _items = [];
  final Set<String> _probing = {};
  final Set<String> _running = {};
  final Set<String> _ignoreArchive = {};
  final Map<String, List<FormatChoice>> _choices = {};
  final Map<String, List<String>> _partials = {};
  final _notices = StreamController<Notice>.broadcast();

  bool _halted = true;

  List<DownloadItem> get items => List.unmodifiable(_items);
  Stream<Notice> get notices => _notices.stream;

  bool isProbing(String id) => _probing.contains(id);
  List<FormatChoice>? choicesFor(String id) => _choices[id];

  DownloadItem? byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  // ───────────────────────── stats ─────────────────────────

  int count(bool Function(DownloadItem) test) => _items.where(test).length;
  int get activeCount => count((i) => i.status.isActive);
  int get queuedCount => count((i) => i.status == DownloadStatus.queued);
  int get pendingCount => count((i) => i.status.isActive || i.status == DownloadStatus.queued);
  int get doneCount => count((i) => i.status == DownloadStatus.done);
  int get failedCount => count((i) => i.status == DownloadStatus.failed);
  int get pausedCount => count((i) => i.status == DownloadStatus.paused);

  double get totalSpeed =>
      _items.where((i) => i.status == DownloadStatus.downloading).fold(0.0, (a, i) => a + (i.speed ?? 0));

  /// Progress across everything currently in flight or waiting, for the
  /// header ring and the Android notification.
  double? get overallProgress {
    final pending = _items.where((i) => i.status.isActive || i.status == DownloadStatus.queued).toList();
    if (pending.isEmpty) return null;
    var sum = 0.0;
    for (final i in pending) {
      sum += i.status == DownloadStatus.processing ? 1 : (i.progress ?? 0);
    }
    return sum / pending.length;
  }

  // ───────────────────────── lifecycle ─────────────────────────

  void restore(List<dynamic> raw) {
    _items
      ..clear()
      ..addAll(raw.whereType<Map<String, dynamic>>().map(DownloadItem.fromJson));
    notifyListeners();
  }

  List<Map<String, dynamic>> toJson() => _items.map((i) => i.toJson()).toList();

  /// Starts processing once the engine is ready.
  void start() {
    _halted = false;
    _pump();
  }

  // ───────────────────────── adding ─────────────────────────

  AddResult addText(String text, {FormatPreset? preset}) => addUrls(extractLinks(text), preset: preset);

  AddResult addUrls(List<String> urls, {FormatPreset? preset, String? collection, List<ProbeEntry>? entries, int at = 0}) {
    final existing = <String, DownloadItem>{for (final i in _items) canonicalKey(i.url): i};
    final fresh = <DownloadItem>[];
    var dupes = 0;
    final base = DateTime.now();
    for (final (n, url) in urls.indexed) {
      final key = canonicalKey(url);
      final had = existing[key];
      if (had != null) {
        // Pasting a failed link again is a retry, not a duplicate.
        if (had.status == DownloadStatus.failed) {
          _requeue(had);
        } else {
          dupes++;
        }
        continue;
      }
      final e = entries?[n];
      final item = DownloadItem(
        url: url,
        preset: preset ?? settings().preset,
        addedAt: base.add(Duration(microseconds: n)),
        collection: collection,
        title: e?.title,
        duration: e?.duration,
        thumbnail: e?.thumbnail,
        uploader: e?.uploader,
        // Playlist entries are already described; skip the extra lookup
        // unless it's a nested playlist (e.g. a channel's tabs).
        probed: e != null && e.title != null && !looksLikeCollection(url),
      );
      existing[key] = item;
      fresh.add(item);
    }
    _items.insertAll(at.clamp(0, _items.length), fresh);
    _trimHistory();
    notifyListeners();
    persist();
    _pump();
    return AddResult([for (final i in fresh) i.id], dupes);
  }

  void _trimHistory() {
    final done = _items.where((i) => i.status == DownloadStatus.done).toList();
    if (done.length <= _historyLimit) return;
    done.sort((a, b) => (a.completedAt ?? a.addedAt).compareTo(b.completedAt ?? b.addedAt));
    final drop = done.take(done.length - _historyLimit).map((i) => i.id).toSet();
    _items.removeWhere((i) => drop.contains(i.id));
  }

  // ───────────────────────── scheduling ─────────────────────────

  DownloadItem? _next(bool Function(DownloadItem) test) {
    DownloadItem? best;
    for (final i in _items) {
      if (i.status != DownloadStatus.queued || !test(i)) continue;
      if (best == null || i.addedAt.isBefore(best.addedAt)) best = i;
    }
    return best;
  }

  void _pump() {
    if (_halted || !engine.ready) return;
    while (_probing.length < _probeSlots) {
      final next = _next((i) => !i.probed && !_probing.contains(i.id) && !_running.contains(i.id));
      if (next == null) break;
      _probe(next);
    }
    final limit = settings().concurrency;
    while (_running.length < limit) {
      final next = _next((i) => i.probed && !_running.contains(i.id) && !_probing.contains(i.id));
      if (next == null) break;
      _download(next);
    }
    _syncBackground();
  }

  Future<void> _probe(DownloadItem item) async {
    _probing.add(item.id);
    notifyListeners();
    final r = await engine.run('probe-${item.id}', probeArgs(item.url, settings(), engine.caps));
    _probing.remove(item.id);

    if (!_items.contains(item)) return _pump();
    if (r.cancelled) {
      notifyListeners();
      return _pump();
    }
    if (!r.ok) {
      _fail(item, r.stderr);
      return _pump();
    }
    try {
      final p = parseProbe(r.stdout);
      if (p.isCollection) {
        _expand(item, p);
      } else {
        item
          ..title = p.title ?? item.title
          ..uploader = p.uploader ?? item.uploader
          ..thumbnail = p.thumbnail ?? item.thumbnail
          ..duration = p.duration ?? item.duration
          ..videoId = p.videoId
          ..extractor = p.extractor
          ..probed = true;
        if (p.choices.isNotEmpty) _choices[item.id] = p.choices;
      }
    } catch (e) {
      _fail(item, 'ERROR: Couldn\'t read what this link contains.');
    }
    notifyListeners();
    persist();
    _pump();
  }

  void _expand(DownloadItem item, ProbeResult p) {
    final at = _items.indexOf(item);
    _items.remove(item);
    if (p.entries.isEmpty) {
      _notices.add(Notice('“${p.title}” has no videos to download'));
      return;
    }
    final result = addUrls(
      [for (final e in p.entries) e.url],
      preset: item.preset,
      collection: p.title,
      entries: p.entries,
      at: at,
    );
    final title = p.title ?? 'playlist';
    final dupes = result.duplicates > 0 ? ' · ${result.duplicates} already here' : '';
    final added = result.ids.toSet();
    _notices.add(Notice(
      result.added == 0 ? 'Everything in “$title” is already here' : 'Added ${result.added} from “$title”$dupes',
      undo: result.added == 0 ? null : () => removeMany(added, silent: true),
    ));
  }

  Future<void> _download(DownloadItem item) async {
    _running.add(item.id);
    item
      ..status = DownloadStatus.downloading
      ..error = null
      ..progress = null
      ..speed = null
      ..eta = null
      ..downloadedBytes = null
      ..totalBytes = null
      ..skippedExisting = false;
    notifyListeners();

    final s = settings();
    final dir = await downloadDir();
    final plan = downloadArgs(
      item: item,
      settings: s,
      caps: engine.caps,
      baseDir: dir,
      archivePath: await engine.archivePath(),
      ignoreArchive: _ignoreArchive.contains(item.id),
      sep: engine.pathSeparator,
    );
    // Local desktop engines need the folder; yt-dlp makes it elsewhere.
    if (isDesktop && engine is! RemoteEngine) await io.ensureDir(plan.outDir);

    final parser = DownloadOutputParser();
    String? file;
    var archived = false;
    final partials = _partials[item.id] = [];

    final r = await engine.run(item.id, plan.args, onLine: (line) {
      for (final ev in parser.feed(line)) {
        switch (ev) {
          case ProgressEvent():
            if (item.status == DownloadStatus.downloading) {
              item
                ..progress = ev.fraction ?? item.progress
                ..downloadedBytes = ev.downloaded
                ..totalBytes = ev.total ?? item.totalBytes
                ..speed = ev.speed
                ..eta = ev.eta;
            }
          case MetaEvent():
            item
              ..title = ev.title ?? item.title
              ..uploader = ev.uploader ?? item.uploader
              ..thumbnail = item.thumbnail ?? ev.thumbnail
              ..duration = ev.duration ?? item.duration
              ..videoId = ev.videoId ?? item.videoId
              ..extractor = ev.extractor ?? item.extractor;
          case ProcessingEvent():
            if (item.status == DownloadStatus.downloading) {
              item
                ..status = DownloadStatus.processing
                ..progress = 1
                ..speed = null
                ..eta = null;
            }
          case FileEvent():
            file = ev.path;
          case DestinationEvent():
            partials.add(ev.path);
          case AlreadyArchivedEvent():
            archived = true;
        }
      }
      _notifySoon();
    });

    _running.remove(item.id);
    _ignoreArchive.remove(item.id);
    _partials.remove(item.id);

    if (!_items.contains(item)) {
      // Removed while running — tidy up after ourselves.
      _deletePartials(partials);
      return _pump();
    }

    if (r.cancelled) {
      if (item.status != DownloadStatus.queued) item.status = DownloadStatus.paused;
      item
        ..speed = null
        ..eta = null;
    } else if (r.ok) {
      item
        ..status = DownloadStatus.done
        ..progress = 1
        ..speed = null
        ..eta = null
        ..completedAt = DateTime.now()
        ..skippedExisting = archived && file == null
        ..filePath = file ?? item.filePath;
      final path = file;
      if (path != null) {
        item.fileSize = io.fileSize(path) ?? item.fileSize ?? item.totalBytes;
        bridge.publishFile(path).then((uri) {
          if (uri != null) {
            item.contentUri = uri;
            persist();
          }
        });
        // Remote mode on a phone: bring the file over automatically.
        if (engine is RemoteEngine && !isWeb && settings().saveToDevice) unawaited(saveToDevice(item.id));
      }
    } else {
      _fail(item, r.stderr);
    }
    notifyListeners();
    persist();
    _pump();
  }

  void _fail(DownloadItem item, String stderr) {
    final f = friendlyError(stderr, mobile: engine.isMobile);
    item
      ..status = DownloadStatus.failed
      ..error = f.message
      ..speed = null
      ..eta = null;
    _errorDetail[item.id] = f;
  }

  final Map<String, FriendlyError> _errorDetail = {};
  FriendlyError? errorFor(String id) => _errorDetail[id];

  void _deletePartials(List<String> paths) {
    if (engine is RemoteEngine) return; // the computer tidies its own files
    io.deleteFiles([
      for (final p in paths) ...[p, '$p.part', '$p.ytdl', '$p.part-Frag1'],
    ]);
  }

  /// Remote mode: copy a finished download from the computer to this
  /// device (or, in a browser, hand it to the browser's downloads).
  Future<bool> saveToDevice(String id) async {
    final item = byId(id);
    final remote = engine is RemoteEngine ? engine as RemoteEngine : null;
    final path = item?.filePath;
    if (item == null || remote == null || path == null || item.saveProgress != null) return false;
    final name = path.split(remote.pathSeparator).last;
    item.saveProgress = 0;
    notifyListeners();
    final local = await io.saveRemoteFile(remote.fileUri(path), name, (p) {
      item.saveProgress = p;
      _notifySoon();
    });
    item.saveProgress = null;
    if (local != null) {
      item.localPath = local;
      final uri = await bridge.publishFile(local);
      if (uri != null) item.contentUri = uri;
    }
    notifyListeners();
    persist();
    return local != null || isWeb;
  }

  Timer? _notifyTimer;
  void _notifySoon() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 120), () {
      notifyListeners();
      _syncBackground();
    });
  }

  DateTime _lastBg = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastBgActive = -1;
  void _syncBackground() {
    final active = _running.length + _probing.length;
    final now = DateTime.now();
    // Throttle, but always report transitions to/from idle immediately.
    if (active == _lastBgActive && now.difference(_lastBg).inMilliseconds < 1000) return;
    _lastBg = now;
    _lastBgActive = active;
    DownloadItem? first;
    for (final i in _items) {
      if (i.status == DownloadStatus.downloading) {
        first = i;
        break;
      }
    }
    bridge.updateBackgroundWork(
      active: active,
      queued: queuedCount,
      progress: overallProgress,
      title: first?.title,
    );
  }

  // ───────────────────────── user actions ─────────────────────────

  void _requeue(DownloadItem item) {
    item
      ..status = DownloadStatus.queued
      ..error = null
      ..progress = null;
    _errorDetail.remove(item.id);
  }

  void pause(String id) {
    final item = byId(id);
    if (item == null) return;
    if (_running.contains(id)) {
      item.status = DownloadStatus.paused;
      engine.cancel(id);
    } else if (item.status == DownloadStatus.queued) {
      item.status = DownloadStatus.paused;
    }
    notifyListeners();
    persist();
  }

  void resume(String id) {
    final item = byId(id);
    if (item == null || item.status != DownloadStatus.paused) return;
    item.status = DownloadStatus.queued;
    notifyListeners();
    persist();
    _pump();
  }

  void retry(String id, {FormatPreset? preset}) {
    final item = byId(id);
    if (item == null) return;
    if (preset != null) {
      item
        ..preset = preset
        ..customFormat = null;
    }
    _requeue(item);
    notifyListeners();
    persist();
    _pump();
  }

  /// Download again — even if the archive says we already have it.
  void redownload(String id) {
    final item = byId(id);
    if (item == null || _running.contains(id)) return;
    _ignoreArchive.add(id);
    item
      ..filePath = null
      ..contentUri = null
      ..completedAt = null
      ..skippedExisting = false;
    _requeue(item);
    notifyListeners();
    persist();
    _pump();
  }

  void setFormat(String id, {FormatPreset? preset, CustomFormat? custom}) {
    final item = byId(id);
    if (item == null) return;
    item
      ..preset = preset ?? item.preset
      ..customFormat = custom;
    final wasRunning = _running.contains(id);
    if (wasRunning) {
      item.status = DownloadStatus.queued;
      engine.cancel(id);
    }
    if (item.status == DownloadStatus.done) {
      _ignoreArchive.add(id);
      item
        ..filePath = null
        ..contentUri = null;
    }
    if (!wasRunning && item.status != DownloadStatus.paused) _requeue(item);
    notifyListeners();
    persist();
    _pump();
  }

  void pauseAll() {
    for (final i in _items) {
      if (i.status == DownloadStatus.queued || i.status.isActive) pause(i.id);
    }
  }

  void resumeAll() {
    for (final i in _items) {
      if (i.status == DownloadStatus.paused) i.status = DownloadStatus.queued;
    }
    notifyListeners();
    persist();
    _pump();
  }

  void retryFailed() {
    for (final i in _items.where((i) => i.status == DownloadStatus.failed)) {
      _requeue(i);
    }
    notifyListeners();
    persist();
    _pump();
  }

  /// Removes from the list. In-flight work is stopped and its partial
  /// files deleted; finished files on disk are never touched.
  void remove(String id) => removeMany({id});

  void removeMany(Set<String> ids, {bool silent = false}) {
    final removed = <(int, DownloadItem)>[];
    for (var n = 0; n < _items.length; n++) {
      if (ids.contains(_items[n].id)) removed.add((n, _items[n]));
    }
    if (removed.isEmpty) return;
    for (final (_, item) in removed) {
      if (_running.contains(item.id)) engine.cancel(item.id);
      if (_probing.contains(item.id)) engine.cancel('probe-${item.id}');
    }
    _items.removeWhere((i) => ids.contains(i.id));
    notifyListeners();
    persist();
    _pump();
    if (silent) return;
    _notices.add(Notice(
      removed.length == 1 ? 'Removed “${_short(removed.first.$2.displayTitle)}”' : 'Removed ${removed.length} items',
      undo: () {
        for (final (n, item) in removed) {
          if (item.status.isActive) item.status = DownloadStatus.queued;
          item
            ..speed = null
            ..eta = null;
          _items.insert(n.clamp(0, _items.length), item);
        }
        notifyListeners();
        persist();
        _pump();
      },
    ));
  }

  void clearFinished() {
    final ids = _items.where((i) => i.status == DownloadStatus.done).map((i) => i.id).toSet();
    if (ids.isEmpty) return;
    removeMany(ids);
  }

  /// Fetches format choices for the details sheet when we don't have them.
  Future<List<FormatChoice>> loadChoices(String id) async {
    final cached = _choices[id];
    if (cached != null) return cached;
    final item = byId(id);
    if (item == null) return const [];
    final r = await engine.run('formats-$id', probeArgs(item.url, settings(), engine.caps));
    if (!r.ok) return const [];
    try {
      final p = parseProbe(r.stdout);
      return _choices[id] = p.choices;
    } catch (_) {
      return const [];
    }
  }

  void onSettingsChanged() => _pump();

  /// Stops all running work (app quitting). Partial files stay, so the
  /// next launch resumes where we left off.
  Future<void> shutdown() async {
    _halted = true;
    await Future.wait([
      for (final id in _running) engine.cancel(id),
      for (final id in _probing) engine.cancel('probe-$id'),
    ]);
  }

  String _short(String s) => s.length > 40 ? '${s.substring(0, 39)}…' : s;

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _notices.close();
    super.dispose();
  }
}
