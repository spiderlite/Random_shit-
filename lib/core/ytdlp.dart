/// Everything Haul knows about talking to yt-dlp, kept free of I/O so it
/// can be shared by the desktop (process) and Android (embedded) engines
/// and unit tested on its own.
library;

import 'dart:convert';

import 'format.dart';
import 'models.dart';

/// Engine-specific facts the argument builder needs.
class EngineCaps {
  const EngineCaps({
    required this.hasFfmpeg,
    this.jsRuntime,
    this.ffmpegLocation,
    this.supportsBrowserCookies = true,
    this.tempDir,
    this.extraArgs = const [],
  });

  final bool hasFfmpeg;
  /// Engine-specific flags added to every run.
  final List<String> extraArgs;
  /// Value for `--js-runtimes`, e.g. `deno:/path/to/deno` or `node`.
  final String? jsRuntime;
  final String? ffmpegLocation;
  final bool supportsBrowserCookies;
  /// Where yt-dlp keeps fragments and .part files (`-P temp:`).
  final String? tempDir;
}

List<String> commonArgs(Settings s, EngineCaps caps) => [
      '--no-warnings',
      '--encoding', 'utf-8',
      if (caps.jsRuntime != null) ...['--js-runtimes', caps.jsRuntime!],
      if (caps.ffmpegLocation != null) ...['--ffmpeg-location', caps.ffmpegLocation!],
      if (caps.supportsBrowserCookies && s.cookiesBrowser != null) ...['--cookies-from-browser', s.cookiesBrowser!],
      ...caps.extraArgs,
    ];

/// Metadata only. `--flat-playlist` keeps channels with thousands of videos
/// fast: we get a light list of entries and fetch each video on its own.
List<String> probeArgs(String url, Settings s, EngineCaps caps) => [
      '-J',
      '--flat-playlist',
      '--no-playlist', // a video opened from a playlist means that video
      ...commonArgs(s, caps),
      url,
    ];

const progressPrefix = 'HAUL|';
const metaPrefix = 'HAULMETA ';
const sizesPrefix = 'HAULSIZES ';
const filePrefix = 'HAULFILE ';

const _progressTemplate = '$progressPrefix'
    '%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|'
    '%(progress.speed)s|%(progress.eta)s|%(progress.status)s';

/// Format selection for a preset. Returns the `-f`/`-S`/postprocessor args.
List<String> formatArgs(FormatPreset preset, Settings s, EngineCaps caps) {
  if (preset.isAudio) {
    if (!caps.hasFfmpeg) return ['-f', 'ba[ext=m4a]/ba/b'];
    if (preset == FormatPreset.mp3) {
      return ['-f', 'ba/b', '-x', '--audio-format', 'mp3', '--audio-quality', '0'];
    }
    return ['-f', 'ba[ext=m4a]/ba/b', '-x', '--audio-format', 'm4a/best'];
  }

  final h = preset.height;
  if (!caps.hasFfmpeg) {
    // Can't merge separate streams — take the best single file.
    return ['-f', h == null ? 'b/bv*+ba' : 'b[height<=$h]/b/bv*+ba'];
  }

  final sort = <String>[
    if (h != null) 'res:$h',
    if (s.preferCompatible) ...['vcodec:h264', 'acodec:aac'],
  ];
  return [
    '-f', 'bv*+ba/b',
    if (sort.isNotEmpty) ...['-S', sort.join(',')],
    if (s.preferCompatible) ...['--merge-output-format', 'mp4', '--remux-video', 'mp4'],
  ];
}

class DownloadPlan {
  const DownloadPlan({required this.args, required this.outDir});
  final List<String> args;
  final String outDir;
}

String sanitizeFolder(String name) {
  var n = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  n = n.replaceAll(RegExp(r'\.{2,}'), '.').replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (n.length > 80) n = n.substring(0, 80).trim();
  return n.isEmpty ? 'Collection' : n;
}

DownloadPlan downloadArgs({
  required DownloadItem item,
  required Settings settings,
  required EngineCaps caps,
  required String baseDir,
  String? archivePath,
  bool ignoreArchive = false,
  String sep = '/',
}) {
  final outDir = (settings.collectionFolders && item.collection != null)
      ? '$baseDir$sep${sanitizeFolder(item.collection!)}'
      : baseDir;

  final custom = item.customFormat;
  final fmt = custom != null
      ? [
          '-f', custom.selector,
          if (!custom.audioOnly && caps.hasFfmpeg && settings.preferCompatible) ...['--merge-output-format', 'mp4'],
          if (custom.audioOnly && caps.hasFfmpeg) ...['-x', '--audio-format', 'mp3', '--audio-quality', '0'],
        ]
      : formatArgs(item.preset, settings, caps);

  final args = <String>[
    ...fmt,
    '--no-playlist',
    '--newline',
    // --print implies --quiet, which would hide the [Merger] lines we use
    // to show the "finishing up" phase.
    '--no-quiet',
    '--progress',
    '--progress-template', 'download:$_progressTemplate',
    '--print', 'video:$metaPrefix%(.{id,title,uploader,channel,thumbnail,duration,extractor_key})j',
    '--print', 'video:$sizesPrefix%(requested_formats.:.filesize)j|%(requested_formats.:.filesize_approx)j|%(filesize,filesize_approx)j',
    '--print', 'after_move:$filePrefix%(filepath)s',
    '--no-simulate',
    '--no-mtime',
    '--continue',
    '--retries', '10',
    '--fragment-retries', '10',
    '--concurrent-fragments', '4',
    '-P', outDir,
    if (caps.tempDir != null) ...['-P', 'temp:${caps.tempDir}'],
    '-o', settings.nameStyle.template,
    if (settings.embedMetadata && caps.hasFfmpeg) '--embed-metadata',
    if (settings.embedThumbnail && caps.hasFfmpeg) '--embed-thumbnail',
    if (settings.subtitles && !item.isAudio && caps.hasFfmpeg) ...[
      '--write-subs', '--sub-langs', 'en.*,-live_chat', '--embed-subs',
    ],
    if (settings.skipDownloaded && !ignoreArchive && archivePath != null) ...['--download-archive', archivePath],
    ...commonArgs(settings, caps),
    item.url,
  ];
  return DownloadPlan(args: args, outDir: outDir);
}

// ───────────────────────── probing ─────────────────────────

class ProbeEntry {
  const ProbeEntry({required this.url, this.title, this.duration, this.thumbnail, this.uploader});
  final String url;
  final String? title;
  final double? duration;
  final String? thumbnail;
  final String? uploader;
}

class FormatChoice {
  const FormatChoice({required this.format, this.sizeBytes, this.detail});
  final CustomFormat format;
  final int? sizeBytes;
  final String? detail;
}

class ProbeResult {
  const ProbeResult.single({
    this.title,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.videoId,
    this.extractor,
    this.choices = const [],
  })  : isCollection = false,
        entries = const [];

  const ProbeResult.collection({required this.title, required this.entries, this.uploader})
      : isCollection = true,
        thumbnail = null,
        duration = null,
        videoId = null,
        extractor = null,
        choices = const [];

  final bool isCollection;
  final String? title;
  final String? uploader;
  final String? thumbnail;
  final double? duration;
  final String? videoId;
  final String? extractor;
  final List<ProbeEntry> entries;
  final List<FormatChoice> choices;
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
double? _num(Object? v) => v is num ? v.toDouble() : null;

String? pickThumbnail(Map<String, dynamic> j) {
  final direct = _str(j['thumbnail']);
  if (direct != null) return direct;
  final thumbs = j['thumbnails'];
  if (thumbs is List && thumbs.isNotEmpty) {
    // Prefer something around 480px wide: sharp in a list, cheap to load.
    Map? best;
    var bestScore = double.infinity;
    for (final t in thumbs) {
      if (t is! Map || _str(t['url']) == null) continue;
      final w = _num(t['width']) ?? 320;
      final score = (w - 480).abs();
      if (score < bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best?['url'] as String? ?? (thumbs.last is Map ? (thumbs.last as Map)['url'] as String? : null);
  }
  return null;
}

ProbeResult parseProbe(String stdout) {
  final start = stdout.indexOf('{');
  if (start < 0) throw const FormatException('yt-dlp returned no metadata');
  final j = jsonDecode(stdout.substring(start)) as Map<String, dynamic>;
  final type = j['_type'];
  final entries = j['entries'];
  if ((type == 'playlist' || type == 'multi_video') && entries is List) {
    final list = <ProbeEntry>[];
    for (final e in entries) {
      if (e is! Map<String, dynamic>) continue;
      var url = _str(e['webpage_url']) ?? _str(e['url']) ?? _str(e['original_url']);
      if (url == null) continue;
      if (!url.startsWith('http')) {
        final id = _str(e['id']);
        if (e['ie_key'] == 'Youtube' && id != null) {
          url = 'https://www.youtube.com/watch?v=$id';
        } else {
          continue;
        }
      }
      list.add(ProbeEntry(
        url: url,
        title: _str(e['title']),
        duration: _num(e['duration']),
        thumbnail: pickThumbnail(e),
        uploader: _str(e['uploader']) ?? _str(e['channel']),
      ));
    }
    return ProbeResult.collection(
      title: _str(j['title']) ?? _str(j['id']) ?? 'Playlist',
      uploader: _str(j['uploader']) ?? _str(j['channel']),
      entries: list,
    );
  }
  return ProbeResult.single(
    title: _str(j['title']) ?? _str(j['fulltitle']),
    uploader: _str(j['uploader']) ?? _str(j['channel']) ?? _str(j['creator']),
    thumbnail: pickThumbnail(j),
    duration: _num(j['duration']),
    videoId: _str(j['id']),
    extractor: _str(j['extractor_key']),
    choices: buildChoices(j['formats']),
  );
}

/// Per-video quality options for the details sheet: one per resolution,
/// best-looking stream at each, plus an audio-only option.
List<FormatChoice> buildChoices(Object? rawFormats) {
  if (rawFormats is! List) return const [];
  final formats = rawFormats.whereType<Map>().toList();
  bool has(Object? codec) => codec is String && codec != 'none';

  final audio = formats.where((f) => has(f['acodec']) && !has(f['vcodec'])).toList()
    ..sort((a, b) => (_num(b['abr']) ?? _num(b['tbr']) ?? 0).compareTo(_num(a['abr']) ?? _num(a['tbr']) ?? 0));
  final bestAudio = audio.isEmpty ? null : audio.first;
  int? size(Map f) => (_num(f['filesize']) ?? _num(f['filesize_approx']))?.round();
  final audioSize = bestAudio == null ? null : size(bestAudio);

  final videos = formats.where((f) => has(f['vcodec']) && f['height'] is num).toList();
  final heights = videos.map((f) => (f['height'] as num).toInt()).toSet().toList()..sort((a, b) => b - a);

  double score(Map f) {
    var s = _num(f['tbr']) ?? 0;
    if (f['ext'] == 'mp4') s += 10000;
    if ((f['vcodec'] as String).startsWith('avc')) s += 5000;
    return s;
  }

  final out = <FormatChoice>[];
  for (final h in heights.take(8)) {
    final c = videos.where((f) => (f['height'] as num).toInt() == h).toList()..sort((a, b) => score(b).compareTo(score(a)));
    final best = c.first;
    final muxed = has(best['acodec']);
    final vs = size(best);
    final total = vs == null ? null : vs + (muxed ? 0 : (audioSize ?? 0));
    final fps = _num(best['fps']);
    out.add(FormatChoice(
      format: CustomFormat(
        selector: 'bv*[height=$h]+ba/b[height=$h]/bv*[height<=$h]+ba/b',
        label: '${h}p',
      ),
      sizeBytes: total,
      detail: [
        if (fps != null && fps > 30) '${fps.round()}fps',
        _codecName(best['vcodec'] as String),
      ].join(' · '),
    ));
  }
  if (bestAudio != null || out.isNotEmpty) {
    out.add(FormatChoice(
      format: const CustomFormat(selector: 'ba/b', label: 'Audio', audioOnly: true),
      sizeBytes: audioSize,
      detail: 'mp3',
    ));
  }
  return out;
}

String _codecName(String vcodec) {
  final c = vcodec.toLowerCase();
  if (c.startsWith('avc') || c.startsWith('h264')) return 'H.264';
  if (c.startsWith('vp09') || c.startsWith('vp9')) return 'VP9';
  if (c.startsWith('av01')) return 'AV1';
  if (c.startsWith('hev') || c.startsWith('hvc') || c.startsWith('h265')) return 'HEVC';
  return vcodec.split('.').first;
}

// ───────────────────────── download output ─────────────────────────

sealed class DownloadEvent {
  const DownloadEvent();
}

class MetaEvent extends DownloadEvent {
  const MetaEvent({this.title, this.uploader, this.thumbnail, this.duration, this.videoId, this.extractor});
  final String? title, uploader, thumbnail, videoId, extractor;
  final double? duration;
}

class ProgressEvent extends DownloadEvent {
  const ProgressEvent({this.fraction, this.downloaded, this.total, this.speed, this.eta});
  final double? fraction;
  final int? downloaded;
  final int? total;
  final double? speed;
  final double? eta;
}

class ProcessingEvent extends DownloadEvent {
  const ProcessingEvent(this.label);
  final String label;
}

class FileEvent extends DownloadEvent {
  const FileEvent(this.path);
  final String path;
}

/// A file yt-dlp is writing; remembered so a removed download can clean
/// up its half-finished pieces.
class DestinationEvent extends DownloadEvent {
  const DestinationEvent(this.path);
  final String path;
}

class AlreadyArchivedEvent extends DownloadEvent {
  const AlreadyArchivedEvent();
}

/// Feeds on yt-dlp stdout, one line at a time, and turns it into events.
/// Stateful because a "1080p" download is often two files (video, then
/// audio) that we present as one smooth progress bar.
class DownloadOutputParser {
  List<int?> _partSizes = const [];
  int _part = 0;
  int _lastDownloaded = -1;
  int _completedBytes = 0;
  int? _lastTotal;

  List<DownloadEvent> feed(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return const [];

    if (line.startsWith(progressPrefix)) {
      final p = line.substring(progressPrefix.length).split('|');
      double? n(int i) => i < p.length ? _parseNum(p[i]) : null;
      final downloaded = n(0)?.round() ?? 0;
      final total = (n(1) ?? n(2))?.round();
      if (_lastDownloaded >= 0 && downloaded < _lastDownloaded) {
        // A new file started (e.g. the audio track after the video).
        _completedBytes += _lastTotal ?? _lastDownloaded;
        _part++;
      }
      _lastDownloaded = downloaded;
      _lastTotal = total;
      return [
        ProgressEvent(
          fraction: _overall(downloaded, total),
          downloaded: _completedBytes + downloaded,
          total: _expectedTotal(total),
          speed: n(3),
          eta: n(4),
        ),
      ];
    }

    if (line.startsWith(metaPrefix)) {
      try {
        final j = jsonDecode(line.substring(metaPrefix.length));
        if (j is Map<String, dynamic>) {
          return [
            MetaEvent(
              title: _str(j['title']),
              uploader: _str(j['uploader']) ?? _str(j['channel']),
              thumbnail: _str(j['thumbnail']),
              duration: _num(j['duration']),
              videoId: _str(j['id']),
              extractor: _str(j['extractor_key']),
            ),
          ];
        }
      } catch (_) {}
      return const [];
    }

    if (line.startsWith(sizesPrefix)) {
      final parts = line.substring(sizesPrefix.length).split('|');
      final exact = _parseList(parts.isNotEmpty ? parts[0] : null);
      final approx = _parseList(parts.length > 1 ? parts[1] : null);
      if (exact != null || approx != null) {
        final count = (exact ?? approx)!.length;
        _partSizes = List.generate(count, (i) {
          final e = exact != null && i < exact.length ? exact[i] : null;
          final a = approx != null && i < approx.length ? approx[i] : null;
          return e ?? a;
        });
      } else {
        final single = parts.length > 2 ? _parseNum(parts[2].replaceAll('"', ''))?.round() : null;
        _partSizes = [single];
      }
      return const [];
    }

    if (line.startsWith(filePrefix)) {
      return [FileEvent(line.substring(filePrefix.length).trim())];
    }

    if (line.startsWith('[download] Destination: ')) {
      return [DestinationEvent(line.substring('[download] Destination: '.length).trim())];
    }

    if (line.contains('has already been recorded in the archive')) {
      return const [AlreadyArchivedEvent()];
    }

    for (final (tag, label) in _phases) {
      if (line.startsWith(tag)) return [ProcessingEvent(label)];
    }
    return const [];
  }

  static const _phases = [
    ('[Merger]', 'Merging'),
    ('[ExtractAudio]', 'Converting'),
    ('[VideoRemuxer]', 'Finishing'),
    ('[VideoConvertor]', 'Converting'),
    ('[EmbedThumbnail]', 'Finishing'),
    ('[Metadata]', 'Finishing'),
    ('[EmbedSubtitle]', 'Finishing'),
    ('[FixupM3u8]', 'Finishing'),
    ('[FixupM4a]', 'Finishing'),
    ('[MoveFiles]', 'Finishing'),
  ];

  int? _expectedTotal(int? currentTotal) {
    if (_partSizes.isNotEmpty && _partSizes.every((s) => s != null)) {
      return _partSizes.fold<int>(0, (a, b) => a + b!);
    }
    if (currentTotal == null) return null;
    return _completedBytes + currentTotal;
  }

  double? _overall(int downloaded, int? total) {
    final parts = _partSizes.length;
    if (parts > 1 && _partSizes.every((s) => s != null && s > 0)) {
      final all = _partSizes.fold<int>(0, (a, b) => a + b!);
      final done = _partSizes.take(_part.clamp(0, parts)).fold<int>(0, (a, b) => a + b!);
      final current = total != null && total > 0 && _part < parts
          ? downloaded / total * _partSizes[_part]!
          : downloaded.toDouble();
      return ((done + current) / all).clamp(0.0, 1.0);
    }
    if (total == null || total <= 0) return null;
    final frac = (downloaded / total).clamp(0.0, 1.0);
    if (parts > 1) return ((_part + frac) / parts).clamp(0.0, 1.0);
    return frac;
  }
}

double? _parseNum(String? v) {
  if (v == null) return null;
  final t = v.trim();
  if (t.isEmpty || t == 'NA' || t == 'None' || t == 'null') return null;
  final n = double.tryParse(t);
  return n != null && n.isFinite ? n : null;
}

List<int?>? _parseList(String? v) {
  if (v == null) return null;
  try {
    final j = jsonDecode(v.trim());
    if (j is List && j.isNotEmpty) return j.map((e) => e is num ? e.round() : null).toList();
  } catch (_) {}
  return null;
}

// ───────────────────────── errors ─────────────────────────

enum ErrorAction { none, retryBest, updateEngine, cookies, installFfmpeg }

class FriendlyError {
  const FriendlyError(this.message, {this.raw, this.action = ErrorAction.none});
  final String message;
  final String? raw;
  final ErrorAction action;
}

/// The last `ERROR:` line yt-dlp printed, minus its noisy prefixes.
String cleanError(String stderr) {
  final lines = const LineSplitter().convert(stderr).map((l) => l.trim()).where((l) => l.startsWith('ERROR:')).toList();
  if (lines.isEmpty) {
    final rest = const LineSplitter().convert(stderr).map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('WARNING:')).toList();
    return rest.isEmpty ? '' : rest.last;
  }
  return lines.last.replaceFirst(RegExp(r'^ERROR:\s*(\[[^\]]+\]\s*)?([\w-]+:\s)?'), '').trim();
}

FriendlyError friendlyError(String stderr, {bool mobile = false}) {
  final raw = cleanError(stderr);
  final l = raw.toLowerCase();
  FriendlyError f(String m, [ErrorAction a = ErrorAction.none]) => FriendlyError(m, raw: raw, action: a);

  if (l.contains('not a bot') || l.contains('sign in to confirm') || l.contains('login required') ||
      l.contains('log in') || l.contains('cookies') || l.contains('registered users') ||
      l.contains('age-restricted') || l.contains('confirm your age') || l.contains('private')) {
    return mobile
        ? f('This video needs a signed-in account, so it can\'t be downloaded here.')
        : f('This site wants you signed in. Use your browser\'s cookies in Settings.', ErrorAction.cookies);
  }
  if (l.contains('unsupported url')) return f('This link doesn\'t lead to a video Haul can download.');
  if (l.contains('requested format is not available') || l.contains('requested format not available')) {
    return f('That quality isn\'t available for this video.', ErrorAction.retryBest);
  }
  if (l.contains('ffmpeg') || l.contains('ffprobe')) {
    return f('This needs ffmpeg to merge video and audio.', ErrorAction.installFfmpeg);
  }
  if (l.contains('unable to download webpage') || l.contains('getaddrinfo') || l.contains('timed out') ||
      l.contains('network is unreachable') || l.contains('connection reset') || l.contains('name or service not known') ||
      l.contains('temporary failure in name resolution') || l.contains('no address associated')) {
    return f('Couldn\'t reach the site. Check your connection and retry.');
  }
  if (l.contains('video unavailable') || l.contains('not available') || l.contains('has been removed') ||
      l.contains('does not exist') || l.contains('404')) {
    return f('This video is unavailable or was removed.');
  }
  if (l.contains('live event') || l.contains('premieres in') || l.contains('is upcoming')) {
    return f('This stream hasn\'t started yet.');
  }
  if (l.contains('403') || l.contains('nsig') || l.contains('unable to extract') || l.contains('signature') ||
      l.contains('no video formats') || l.contains('only images are available')) {
    return f('The site changed something. Updating the engine usually fixes this.', ErrorAction.updateEngine);
  }
  if (l.contains('no space left')) return f('Your storage is full.');
  if (raw.isEmpty) return const FriendlyError('Something went wrong. Try again.');
  return f(raw.length > 160 ? '${raw.substring(0, 159)}…' : raw);
}

/// Short human summary of a running download for subtitles.
String progressSummary(DownloadItem i) {
  final parts = <String>[];
  if (i.downloadedBytes != null && i.totalBytes != null && i.totalBytes! > 0) {
    parts.add('${formatBytes(i.downloadedBytes)} of ${formatBytes(i.totalBytes)}');
  } else if (i.downloadedBytes != null && i.downloadedBytes! > 0) {
    parts.add(formatBytes(i.downloadedBytes));
  }
  final sp = formatSpeed(i.speed);
  if (sp.isNotEmpty) parts.add(sp);
  final eta = formatEta(i.eta);
  if (eta.isNotEmpty) parts.add('$eta left');
  return parts.join(' · ');
}
