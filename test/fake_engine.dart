import 'dart:async';

import 'package:haul/core/ytdlp.dart';
import 'package:haul/services/engine.dart';
import 'package:haul/services/platform_bridge.dart';

/// Pretends to be yt-dlp. URLs containing "list" are playlists of three,
/// URLs containing "broken" fail, everything else downloads in a few steps.
class FakeEngine extends Engine {
  FakeEngine({this.mobile = false});
  final bool mobile;
  final runs = <String, List<String>>{};
  final _cancel = <String, Completer<void>>{};
  /// When frozen the queue never starts anything (for screenshots).
  bool frozen = false;

  /// Start-ups that should fail before one succeeds (like 0.1.0's "r8").
  int failStarts = 0;
  bool _started = true;

  void _start() {
    if (failStarts > 0) {
      failStarts--;
      _started = false;
    } else {
      _started = true;
    }
  }

  @override
  String? get errorDetail => _started ? null : 'java.lang.ClassNotFoundException: r8';
  int maxConcurrent = 0;
  int _live = 0;
  Duration step = const Duration(milliseconds: 5);

  @override
  bool get isMobile => mobile;
  @override
  String get pathSeparator => '/';
  @override
  List<ToolInfo> get tools => [
        _started
            ? const ToolInfo(id: 'yt-dlp', name: 'yt-dlp', purpose: '', state: ToolState.ready, required: true, version: '2026.01.01', managed: true)
            : const ToolInfo(id: 'yt-dlp', name: 'yt-dlp', purpose: '', state: ToolState.failed, required: true, error: 'Couldn\'t start the download engine.'),
      ];
  @override
  Stream<List<ToolInfo>> get toolChanges => const Stream.empty();
  @override
  bool get ready => !frozen && _started;
  @override
  EngineCaps get caps => const EngineCaps(hasFfmpeg: true);
  @override
  Future<void> detect() async => _start();
  @override
  Future<void> install({bool extras = true}) async => _start();
  @override
  Future<void> installTool(String id) async {}
  @override
  Future<String> updateYtDlp() async => 'Already on the latest version';
  @override
  Future<String> defaultDownloadDir() async => '/downloads';
  @override
  Future<String?> archivePath() async => null;

  @override
  Future<void> cancel(String jobId) async => _cancel[jobId]?.complete();

  @override
  Future<RunResult> run(String jobId, List<String> args, {void Function(String line)? onLine}) async {
    runs[jobId] = args;
    final url = args.last;
    if (args.contains('-J')) {
      await Future.delayed(step);
      if (url.contains('broken')) return const RunResult(exitCode: 1, stdout: '', stderr: 'ERROR: [generic] x: Unsupported URL: x');
      if (url.contains('list')) {
        return const RunResult(
          exitCode: 0,
          stderr: '',
          stdout: '{"_type":"playlist","title":"Road trip","entries":['
              '{"url":"https://v.test/a","title":"A"},{"url":"https://v.test/b","title":"B"},{"url":"https://v.test/c","title":"C"}]}',
        );
      }
      return RunResult(exitCode: 0, stderr: '', stdout: '{"id":"id","title":"Title of $url","duration":12}');
    }

    _live++;
    if (_live > maxConcurrent) maxConcurrent = _live;
    final cancel = _cancel[jobId] = Completer<void>();
    try {
      onLine?.call('HAULSIZES []|[]|1000');
      for (var i = 1; i <= 4; i++) {
        final stop = await Future.any([Future.delayed(step, () => false), cancel.future.then((_) => true)]);
        if (stop) return const RunResult(exitCode: 1, stdout: '', stderr: '', cancelled: true);
        onLine?.call('HAUL|${i * 250}|1000|NA|2048|${4 - i}|downloading');
      }
      onLine?.call('HAULFILE /downloads/${Uri.parse(url).pathSegments.last}.mp4');
      return const RunResult(exitCode: 0, stdout: '', stderr: '');
    } finally {
      _live--;
      _cancel.remove(jobId);
    }
  }
}

class FakeBridge extends PlatformBridge {
  final background = <int>[];
  @override
  Future<String?> publishFile(String path) async => null;
  @override
  Future<void> updateBackgroundWork({required int active, required int queued, double? progress, String? title}) async =>
      background.add(active);
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<String?> takeInitialShare() async => null;
}
