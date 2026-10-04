import 'package:flutter_test/flutter_test.dart';
import 'package:haul/core/format.dart';
import 'package:haul/core/links.dart';
import 'package:haul/core/models.dart';
import 'package:haul/core/ytdlp.dart';

void main() {
  group('extractLinks', () {
    test('finds links in messy text, in order, without duplicates', () {
      const text = '''
check these out: https://youtu.be/dQw4w9WgXcQ?si=abc, and
https://www.youtube.com/watch?v=dQw4w9WgXcQ (same video)
[a thread](https://x.com/someone/status/123).
<https://vimeo.com/76979871>
www.tiktok.com/@user/video/7300000000000000000!
not a link: example dot com
''';
      expect(extractLinks(text), [
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
        'https://x.com/someone/status/123',
        'https://vimeo.com/76979871',
        'https://www.tiktok.com/@user/video/7300000000000000000',
      ]);
    });

    test('ignores things that are not web links', () {
      expect(extractLinks('ftp://x.y/z mailto:a@b.c http://localhost'), isEmpty);
    });
  });

  group('canonicalKey', () {
    test('youtube variants collapse to the same key', () {
      final keys = {
        canonicalKey('https://youtu.be/abc123?si=xyz'),
        canonicalKey('https://www.youtube.com/watch?v=abc123&feature=share'),
        canonicalKey('https://m.youtube.com/watch?v=abc123'),
        canonicalKey('https://youtube.com/shorts/abc123'),
      };
      expect(keys, hasLength(1));
    });

    test('tracking params are ignored, meaningful ones kept', () {
      expect(
        canonicalKey('https://www.instagram.com/reel/XYZ/?igsh=123'),
        canonicalKey('https://instagram.com/reel/XYZ'),
      );
      expect(canonicalKey('https://site.com/v?id=1'), isNot(canonicalKey('https://site.com/v?id=2')));
    });
  });

  test('detectSite', () {
    expect(detectSite('https://music.youtube.com/watch?v=1').label, 'YouTube');
    expect(detectSite('https://x.com/a/status/1').key, 'x');
    expect(detectSite('https://www.example.org/video').label, 'example.org');
  });

  group('formatArgs', () {
    const s = Settings();
    const caps = EngineCaps(hasFfmpeg: true);

    test('resolution presets cap height and prefer compatible codecs', () {
      final a = formatArgs(FormatPreset.p720, s, caps);
      expect(a, containsAllInOrder(['-f', 'bv*+ba/b', '-S', 'res:720,vcodec:h264,acodec:aac']));
      expect(a, contains('--merge-output-format'));
    });

    test('best quality without compatibility has no codec preference', () {
      final a = formatArgs(FormatPreset.best, s.copyWith(preferCompatible: false), caps);
      expect(a, ['-f', 'bv*+ba/b']);
    });

    test('mp3 extracts audio', () {
      expect(formatArgs(FormatPreset.mp3, s, caps), containsAllInOrder(['-x', '--audio-format', 'mp3']));
    });

    test('without ffmpeg we only pick single files', () {
      const none = EngineCaps(hasFfmpeg: false);
      expect(formatArgs(FormatPreset.p1080, s, none), ['-f', 'b[height<=1080]/b/bv*+ba']);
      expect(formatArgs(FormatPreset.mp3, s, none).contains('-x'), isFalse);
    });
  });

  test('downloadArgs puts playlist items in their own folder and ends with the url', () {
    final item = DownloadItem(url: 'https://youtu.be/x', preset: FormatPreset.p1080, collection: 'My: Mix/2024');
    final plan = downloadArgs(
      item: item,
      settings: const Settings(),
      caps: const EngineCaps(hasFfmpeg: true, tempDir: '/tmp/p'),
      baseDir: '/dl',
      archivePath: '/a.txt',
    );
    expect(plan.outDir, '/dl/My Mix 2024');
    expect(plan.args.last, 'https://youtu.be/x');
    expect(plan.args, containsAllInOrder(['-P', '/dl/My Mix 2024', '-P', 'temp:/tmp/p']));
    expect(plan.args, containsAllInOrder(['--download-archive', '/a.txt']));

    final again = downloadArgs(
      item: item,
      settings: const Settings(),
      caps: const EngineCaps(hasFfmpeg: true),
      baseDir: '/dl',
      archivePath: '/a.txt',
      ignoreArchive: true,
    );
    expect(again.args.contains('--download-archive'), isFalse);
  });

  group('DownloadOutputParser', () {
    test('merges a two-part download into one smooth fraction', () {
      final p = DownloadOutputParser();
      expect(p.feed('HAULSIZES [800, 200]|[801, 201]|1000'), isEmpty);
      ProgressEvent prog(String l) => p.feed(l).single as ProgressEvent;

      expect(prog('HAUL|400|800|NA|1000.5|3|downloading').fraction, closeTo(0.4, 1e-9));
      expect(prog('HAUL|800|800|NA|NA|NA|finished').fraction, closeTo(0.8, 1e-9));
      // Audio part starts: byte counter resets.
      final audio = prog('HAUL|100|200|NA|500|1|downloading');
      expect(audio.fraction, closeTo(0.9, 1e-9));
      expect(audio.total, 1000);
      expect(audio.downloaded, 900);
      expect(audio.speed, 500);
    });

    test('single file with only an estimate', () {
      final p = DownloadOutputParser();
      p.feed('HAULSIZES []|[]|NA');
      final e = p.feed('HAUL|50|NA|200|NA|NA|downloading').single as ProgressEvent;
      expect(e.fraction, 0.25);
    });

    test('meta, processing, file and archive lines', () {
      final p = DownloadOutputParser();
      final meta = p.feed('HAULMETA {"id": "abc", "title": "Me at the zoo", "uploader": "jawed", "duration": 19}').single as MetaEvent;
      expect(meta.title, 'Me at the zoo');
      expect(meta.duration, 19);
      expect(p.feed('[Merger] Merging formats into "/x/y.mp4"').single, isA<ProcessingEvent>());
      expect((p.feed('HAULFILE /x/y.mp4').single as FileEvent).path, '/x/y.mp4');
      expect(p.feed('[download] abc: has already been recorded in the archive').single, isA<AlreadyArchivedEvent>());
      expect((p.feed('[download] Destination: /t/a.f137.mp4').single as DestinationEvent).path, '/t/a.f137.mp4');
      expect(p.feed('[youtube] abc: Downloading webpage'), isEmpty);
    });
  });

  group('parseProbe', () {
    test('playlist entries become links', () {
      const json = '{"_type": "playlist", "title": "Mix", "entries": ['
          '{"_type": "url", "ie_key": "Youtube", "id": "aaa", "url": "https://www.youtube.com/watch?v=aaa", "title": "One", "duration": 61},'
          '{"_type": "url", "ie_key": "Youtube", "id": "bbb", "url": "bbb", "title": "Two"}]}';
      final r = parseProbe(json);
      expect(r.isCollection, isTrue);
      expect(r.title, 'Mix');
      expect(r.entries.map((e) => e.url), ['https://www.youtube.com/watch?v=aaa', 'https://www.youtube.com/watch?v=bbb']);
      expect(r.entries.first.duration, 61);
    });

    test('single video builds per-resolution choices', () {
      const json = '{"id": "z", "title": "T", "uploader": "U", "duration": 10, "thumbnail": "http://t", "formats": ['
          '{"format_id": "140", "acodec": "mp4a.40.2", "vcodec": "none", "abr": 128, "filesize": 100},'
          '{"format_id": "137", "acodec": "none", "vcodec": "avc1.640028", "height": 1080, "tbr": 4000, "ext": "mp4", "filesize": 1000},'
          '{"format_id": "248", "acodec": "none", "vcodec": "vp9", "height": 1080, "tbr": 3000, "ext": "webm"},'
          '{"format_id": "18", "acodec": "mp4a.40.2", "vcodec": "avc1.42001E", "height": 360, "tbr": 500, "ext": "mp4", "filesize": 50}]}';
      final r = parseProbe('WARNING: noise\n$json');
      expect(r.isCollection, isFalse);
      expect(r.title, 'T');
      expect(r.choices.map((c) => c.format.label), ['1080p', '360p', 'Audio']);
      expect(r.choices.first.sizeBytes, 1100);
      expect(r.choices[1].sizeBytes, 50); // muxed: no extra audio
    });
  });

  group('errors', () {
    test('cleanError keeps the last ERROR line without prefixes', () {
      expect(
        cleanError('WARNING: x\nERROR: [youtube] abc: Video unavailable. This video is private\n'),
        'Video unavailable. This video is private',
      );
    });

    test('friendly messages with actions', () {
      expect(friendlyError('ERROR: [youtube] x: Sign in to confirm you’re not a bot').action, ErrorAction.cookies);
      expect(friendlyError('ERROR: [youtube] x: Sign in to confirm you’re not a bot', mobile: true).action, ErrorAction.none);
      expect(friendlyError('ERROR: Unsupported URL: https://a.b').message, contains('doesn\'t lead to a video'));
      expect(friendlyError('ERROR: unable to download video data: HTTP Error 403: Forbidden').action, ErrorAction.updateEngine);
      expect(friendlyError('ERROR: Requested format is not available').action, ErrorAction.retryBest);
      expect(friendlyError('').message, 'Something went wrong. Try again.');
    });
  });

  group('format', () {
    test('bytes', () {
      expect(formatBytes(0), '');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
    });
    test('durations and etas', () {
      expect(formatDuration(19), '0:19');
      expect(formatDuration(3725), '1:02:05');
      expect(formatEta(42), '42s');
      expect(formatEta(130), '2m 10s');
      expect(formatEta(3700), '1h 1m');
    });
  });

  test('items survive a save/load round trip and resume as queued', () {
    final i = DownloadItem(url: 'https://a.b/c', preset: FormatPreset.mp3, title: 'T', collection: 'C')
      ..status = DownloadStatus.downloading
      ..progress = 0.5
      ..customFormat = const CustomFormat(selector: 'ba/b', label: 'Audio', audioOnly: true);
    final back = DownloadItem.fromJson(i.toJson());
    expect(back.status, DownloadStatus.queued);
    expect(back.preset, FormatPreset.mp3);
    expect(back.customFormat?.audioOnly, isTrue);
    expect(back.title, 'T');
    expect(back.id, i.id);
  });

  test('settings round trip tolerates junk', () {
    final s = Settings.fromJson({'concurrency': 99, 'preset': 'nope', 'theme': 'dark', 'cookiesBrowser': 'firefox'});
    expect(s.concurrency, 8);
    expect(s.preset, FormatPreset.p1080);
    expect(s.theme, ThemePref.dark);
    expect(Settings.fromJson(s.toJson()).cookiesBrowser, 'firefox');
  });
}
