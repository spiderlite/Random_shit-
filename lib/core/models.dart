import 'dart:math';

/// What the user wants out of a link. Presets keep bulk downloading
/// one-tap: nobody wants a format picker for each of 200 videos.
enum FormatPreset {
  best('Best', 'Highest quality available', null, false),
  p2160('4K', '2160p video', 2160, false),
  p1440('1440p', 'Quad HD video', 1440, false),
  p1080('1080p', 'Full HD video', 1080, false),
  p720('720p', 'HD video · smaller files', 720, false),
  p480('480p', 'Data saver', 480, false),
  mp3('MP3', 'Audio only · plays anywhere', null, true),
  m4a('M4A', 'Audio only · original quality', null, true);

  const FormatPreset(this.label, this.description, this.height, this.isAudio);
  final String label;
  final String description;
  final int? height;
  final bool isAudio;

  static FormatPreset byName(String? name, [FormatPreset fallback = FormatPreset.p1080]) =>
      FormatPreset.values.firstWhere((p) => p.name == name, orElse: () => fallback);
}

enum DownloadStatus {
  queued,
  fetching,
  downloading,
  processing,
  paused,
  done,
  failed;

  bool get isActive => this == fetching || this == downloading || this == processing;
  bool get isFinished => this == done;
  bool get canStart => this == queued;
}

/// A format picked by hand from the details sheet, overriding the preset.
class CustomFormat {
  const CustomFormat({required this.selector, required this.label, this.audioOnly = false});
  final String selector;
  final String label;
  final bool audioOnly;

  Map<String, dynamic> toJson() => {'selector': selector, 'label': label, 'audioOnly': audioOnly};
  static CustomFormat? fromJson(Object? j) {
    if (j is! Map) return null;
    return CustomFormat(
      selector: j['selector'] as String,
      label: j['label'] as String,
      audioOnly: j['audioOnly'] as bool? ?? false,
    );
  }
}

class DownloadItem {
  DownloadItem({
    String? id,
    required this.url,
    required this.preset,
    DateTime? addedAt,
    this.status = DownloadStatus.queued,
    this.title,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.videoId,
    this.extractor,
    this.collection,
    this.customFormat,
    this.filePath,
    this.contentUri,
    this.fileSize,
    this.error,
    this.completedAt,
    this.skippedExisting = false,
    this.probed = false,
  })  : id = id ?? newId(),
        addedAt = addedAt ?? DateTime.now();

  final String id;
  final String url;
  FormatPreset preset;
  final DateTime addedAt;

  DownloadStatus status;
  String? title;
  String? uploader;
  String? thumbnail;
  double? duration;
  String? videoId;
  String? extractor;

  /// Name of the playlist / channel this item was expanded from.
  String? collection;
  CustomFormat? customFormat;

  // Live progress — not persisted.
  double? progress;
  double? speed;
  double? eta;
  int? downloadedBytes;
  int? totalBytes;

  String? filePath;
  /// Android: the MediaStore uri of the finished file, for open/share.
  String? contentUri;
  int? fileSize;
  String? error;
  DateTime? completedAt;
  bool skippedExisting;

  /// Metadata is known (from a probe or a playlist listing), so the item
  /// can go straight to downloading.
  bool probed;

  bool get isAudio => customFormat?.audioOnly ?? preset.isAudio;
  String get formatLabel => customFormat?.label ?? preset.label;
  String get displayTitle => (title == null || title!.isEmpty) ? url : title!;

  static final _rand = Random();
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'preset': preset.name,
        'addedAt': addedAt.toIso8601String(),
        // In-flight work resumes as queued on next launch.
        'status': (status.isActive ? DownloadStatus.queued : status).name,
        'title': title,
        'uploader': uploader,
        'thumbnail': thumbnail,
        'duration': duration,
        'videoId': videoId,
        'extractor': extractor,
        'collection': collection,
        'customFormat': customFormat?.toJson(),
        'filePath': filePath,
        'contentUri': contentUri,
        'fileSize': fileSize,
        'error': error,
        'completedAt': completedAt?.toIso8601String(),
        'skippedExisting': skippedExisting,
        'probed': probed,
      };

  static DownloadItem fromJson(Map<String, dynamic> j) => DownloadItem(
        id: j['id'] as String,
        url: j['url'] as String,
        preset: FormatPreset.byName(j['preset'] as String?),
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DownloadStatus.queued,
        ),
        title: j['title'] as String?,
        uploader: j['uploader'] as String?,
        thumbnail: j['thumbnail'] as String?,
        duration: (j['duration'] as num?)?.toDouble(),
        videoId: j['videoId'] as String?,
        extractor: j['extractor'] as String?,
        collection: j['collection'] as String?,
        customFormat: CustomFormat.fromJson(j['customFormat']),
        filePath: j['filePath'] as String?,
        contentUri: j['contentUri'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt(),
        error: j['error'] as String?,
        completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
        skippedExisting: j['skippedExisting'] as bool? ?? false,
        probed: j['probed'] as bool? ?? false,
      );
}

enum ThemePref { system, light, dark }

enum NameStyle {
  title('Title', '%(title).150B.%(ext)s'),
  titleId('Title [id]', '%(title).140B [%(id)s].%(ext)s'),
  uploaderTitle('Creator – Title', '%(uploader,channel|Unknown).60B – %(title).120B.%(ext)s'),
  dateTitle('Date – Title', '%(upload_date>%Y-%m-%d|)s %(title).140B.%(ext)s');

  const NameStyle(this.label, this.template);
  final String label;
  final String template;
}

class Settings {
  const Settings({
    this.preset = FormatPreset.p1080,
    this.downloadDir,
    this.concurrency = 3,
    this.preferCompatible = true,
    this.nameStyle = NameStyle.title,
    this.collectionFolders = true,
    this.embedMetadata = true,
    this.embedThumbnail = true,
    this.subtitles = false,
    this.skipDownloaded = true,
    this.cookiesBrowser,
    this.theme = ThemePref.system,
    this.watchClipboard = true,
    this.onboarded = false,
  });

  final FormatPreset preset;
  final String? downloadDir;
  final int concurrency;
  /// H.264/AAC in MP4 — plays in every gallery, editor and phone.
  final bool preferCompatible;
  final NameStyle nameStyle;
  final bool collectionFolders;
  final bool embedMetadata;
  final bool embedThumbnail;
  final bool subtitles;
  final bool skipDownloaded;
  final String? cookiesBrowser;
  final ThemePref theme;
  final bool watchClipboard;
  final bool onboarded;

  Settings copyWith({
    FormatPreset? preset,
    String? downloadDir,
    int? concurrency,
    bool? preferCompatible,
    NameStyle? nameStyle,
    bool? collectionFolders,
    bool? embedMetadata,
    bool? embedThumbnail,
    bool? subtitles,
    bool? skipDownloaded,
    String? Function()? cookiesBrowser,
    ThemePref? theme,
    bool? watchClipboard,
    bool? onboarded,
  }) =>
      Settings(
        preset: preset ?? this.preset,
        downloadDir: downloadDir ?? this.downloadDir,
        concurrency: concurrency ?? this.concurrency,
        preferCompatible: preferCompatible ?? this.preferCompatible,
        nameStyle: nameStyle ?? this.nameStyle,
        collectionFolders: collectionFolders ?? this.collectionFolders,
        embedMetadata: embedMetadata ?? this.embedMetadata,
        embedThumbnail: embedThumbnail ?? this.embedThumbnail,
        subtitles: subtitles ?? this.subtitles,
        skipDownloaded: skipDownloaded ?? this.skipDownloaded,
        cookiesBrowser: cookiesBrowser != null ? cookiesBrowser() : this.cookiesBrowser,
        theme: theme ?? this.theme,
        watchClipboard: watchClipboard ?? this.watchClipboard,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'downloadDir': downloadDir,
        'concurrency': concurrency,
        'preferCompatible': preferCompatible,
        'nameStyle': nameStyle.name,
        'collectionFolders': collectionFolders,
        'embedMetadata': embedMetadata,
        'embedThumbnail': embedThumbnail,
        'subtitles': subtitles,
        'skipDownloaded': skipDownloaded,
        'cookiesBrowser': cookiesBrowser,
        'theme': theme.name,
        'watchClipboard': watchClipboard,
        'onboarded': onboarded,
      };

  static Settings fromJson(Map<String, dynamic> j) {
    const d = Settings();
    T pick<T>(String key, T fallback) => j[key] is T ? j[key] as T : fallback;
    return Settings(
      preset: FormatPreset.byName(j['preset'] as String?, d.preset),
      downloadDir: j['downloadDir'] as String?,
      concurrency: pick<int>('concurrency', d.concurrency).clamp(1, 8),
      preferCompatible: pick('preferCompatible', d.preferCompatible),
      nameStyle: NameStyle.values.firstWhere((n) => n.name == j['nameStyle'], orElse: () => d.nameStyle),
      collectionFolders: pick('collectionFolders', d.collectionFolders),
      embedMetadata: pick('embedMetadata', d.embedMetadata),
      embedThumbnail: pick('embedThumbnail', d.embedThumbnail),
      subtitles: pick('subtitles', d.subtitles),
      skipDownloaded: pick('skipDownloaded', d.skipDownloaded),
      cookiesBrowser: j['cookiesBrowser'] as String?,
      theme: ThemePref.values.firstWhere((t) => t.name == j['theme'], orElse: () => d.theme),
      watchClipboard: pick('watchClipboard', d.watchClipboard),
      onboarded: pick('onboarded', d.onboarded),
    );
  }
}
