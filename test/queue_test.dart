import 'package:flutter_test/flutter_test.dart';
import 'package:haul/core/models.dart';
import 'package:haul/state/queue.dart';

import 'fake_engine.dart';

void main() {
  late FakeEngine engine;
  late QueueController q;
  var settings = const Settings(concurrency: 2);

  setUp(() {
    engine = FakeEngine();
    settings = const Settings(concurrency: 2);
    q = QueueController(
      engine: engine,
      bridge: FakeBridge(),
      settings: () => settings,
      downloadDir: () async => '/downloads',
      persist: () {},
    )..start();
  });

  Future<void> settle() async {
    for (var i = 0; i < 200; i++) {
      await Future.delayed(const Duration(milliseconds: 5));
      if (q.pendingCount == 0) return;
    }
  }

  test('downloads everything, never more than the concurrency limit', () async {
    final r = q.addText('https://v.test/1 https://v.test/2 https://v.test/3 https://v.test/4 https://v.test/5');
    expect(r.added, 5);
    await settle();
    expect(q.doneCount, 5);
    expect(engine.maxConcurrent, lessThanOrEqualTo(2));
    final first = q.items.firstWhere((i) => i.url.endsWith('/1'));
    expect(first.title, 'Title of https://v.test/1');
    expect(first.filePath, '/downloads/1.mp4');
    expect(first.progress, 1);
  });

  test('duplicates are skipped; a failed link pasted again is retried', () async {
    q.addText('https://v.test/x');
    final again = q.addText('https://v.test/x https://v.test/broken');
    expect(again.added, 1);
    expect(again.duplicates, 1);
    await settle();
    final broken = q.items.firstWhere((i) => i.url.contains('broken'));
    expect(broken.status, DownloadStatus.failed);
    expect(broken.error, contains('doesn\'t lead to a video'));

    final retry = q.addText('https://v.test/broken');
    expect(retry.added, 0);
    expect(broken.status, isNot(DownloadStatus.failed));
    await settle();
  });

  test('playlists expand in place and undo removes them all', () async {
    final notices = <Notice>[];
    q.notices.listen(notices.add);
    q.addText('https://v.test/list');
    await settle();
    expect(q.items.map((i) => i.title), containsAll(['A', 'B', 'C']));
    expect(q.items.every((i) => i.collection == 'Road trip'), isTrue);
    expect(notices.single.message, 'Added 3 from “Road trip”');

    // Entries came with metadata, so they skip the lookup step.
    expect(engine.runs.keys.where((k) => k.startsWith('probe-')), hasLength(1));

    notices.single.undo!();
    expect(q.items, isEmpty);
  });

  test('pause stops a running download and resume finishes it', () async {
    engine.step = const Duration(milliseconds: 30);
    q.addText('https://v.test/slow');
    final item = q.items.single;
    for (var i = 0; i < 100 && item.status != DownloadStatus.downloading; i++) {
      await Future.delayed(const Duration(milliseconds: 5));
    }
    q.pause(item.id);
    await Future.delayed(const Duration(milliseconds: 60));
    expect(item.status, DownloadStatus.paused);
    expect(q.activeCount, 0);

    q.resume(item.id);
    await settle();
    expect(item.status, DownloadStatus.done);
  });

  test('remove + undo puts items back where they were', () async {
    settings = const Settings(concurrency: 1);
    final notices = <Notice>[];
    q.notices.listen(notices.add);
    q.addText('https://v.test/1 https://v.test/2 https://v.test/3');
    final middle = q.items[1];
    q.remove(middle.id);
    expect(q.items.map((i) => i.id), isNot(contains(middle.id)));
    await Future<void>.delayed(Duration.zero); // notices are delivered async
    notices.last.undo!();
    expect(q.items[1].id, middle.id);
    await settle();
    expect(q.doneCount, 3);
  });

  test('changing the format of a finished item downloads it again', () async {
    q.addText('https://v.test/again');
    await settle();
    final item = q.items.single;
    expect(item.status, DownloadStatus.done);
    q.setFormat(item.id, preset: FormatPreset.mp3);
    expect(item.status, isNot(DownloadStatus.done));
    await settle();
    expect(item.status, DownloadStatus.done);
    expect(engine.runs[item.id], containsAllInOrder(['--audio-format', 'mp3']));
  });
}
