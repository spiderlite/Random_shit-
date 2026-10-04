import 'dart:async';

import '../core/ytdlp.dart';

class RunResult {
  const RunResult({required this.exitCode, required this.stdout, required this.stderr, this.cancelled = false});
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool cancelled;
  bool get ok => exitCode == 0 && !cancelled;
}

enum ToolState { missing, installing, ready, failed }

/// One external piece the engine depends on, as shown on the setup screen.
class ToolInfo {
  const ToolInfo({
    required this.id,
    required this.name,
    required this.purpose,
    required this.state,
    this.required = false,
    this.version,
    this.location,
    this.progress,
    this.sizeHint,
    this.error,
    this.managed = false,
  });

  final String id;
  final String name;
  final String purpose;
  final ToolState state;
  final bool required;
  final String? version;
  final String? location;
  final double? progress;
  final String? sizeHint;
  final String? error;
  /// True when Haul installed it and can update/replace it.
  final bool managed;

  ToolInfo copyWith({ToolState? state, String? version, String? location, double? progress, String? error, bool? managed}) => ToolInfo(
        id: id,
        name: name,
        purpose: purpose,
        required: required,
        sizeHint: sizeHint,
        state: state ?? this.state,
        version: version ?? this.version,
        location: location ?? this.location,
        progress: progress,
        error: error,
        managed: managed ?? this.managed,
      );
}

/// The thing that actually runs yt-dlp. Desktop spawns a process; Android
/// talks to an embedded Python build over a platform channel.
abstract class Engine {
  /// Phones get share-sheet flows, bottom sheets and no browser cookies.
  bool get isMobile;

  /// Whether this platform can run yt-dlp at all.
  bool get supported => true;

  String get pathSeparator;

  /// Current tool status, for setup + settings.
  List<ToolInfo> get tools;
  Stream<List<ToolInfo>> get toolChanges;

  /// Find what's already there. Cheap; never downloads.
  Future<void> detect();

  /// Make the engine usable, downloading whatever is missing. When
  /// [extras] is false only the bare minimum is installed.
  Future<void> install({bool extras = true});

  /// Install or refresh a single tool.
  Future<void> installTool(String id);

  bool get ready;

  EngineCaps get caps;

  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine});

  Future<void> cancel(String jobId);

  /// Updates yt-dlp. Returns a short human message.
  Future<String> updateYtDlp();

  Future<String> defaultDownloadDir();

  Future<String?> archivePath();
}
