import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/core/models.dart';
import 'package:haul/core/remote_protocol.dart';
import 'package:haul/core/ytdlp.dart';
import 'package:haul/services/remote_engine.dart';
import 'package:haul/services/remote_server.dart';
import 'package:haul/state/queue.dart';

import 'fake_engine.dart';

void main() {
  const info = RemoteInfo(
    name: 'pc',
    downloadDir: '/home/me/Downloads/Haul',
    pathSeparator: '/',
    hasFfmpeg: true,
    archivePath: '/home/me/.haul/archive.txt',
    jsRuntime: 'deno:/home/me/.haul/bin/deno',
    ffmpegLocation: '/home/me/.haul/bin/ffmpeg',
    tempDir: '/home/me/.haul/partial',
  );
  final caps = EngineCaps(
    hasFfmpeg: true,
    jsRuntime: info.jsRuntime,
    ffmpegLocation: info.ffmpegLocation,
    tempDir: info.tempDir,
  );

  group('validateRemoteArgs', () {
    test('accepts everything Haul itself builds', () {
      validateRemoteArgs(probeArgs('https://youtu.be/x', const Settings(), caps), info);
      for (final preset in FormatPreset.values) {
        final item = DownloadItem(url: 'https://youtu.be/x', preset: preset, collection: 'Road trip')..collection = 'My.. mix';
        final plan = downloadArgs(
          item: item,
          settings: const Settings(subtitles: true, cookiesBrowser: 'firefox'),
          caps: caps,
          baseDir: info.downloadDir,
          archivePath: info.archivePath,
        );
        validateRemoteArgs(plan.args, info);
      }
    });

    test('refuses anything that could run code or escape the folder', () {
      void bad(List<String> args) => expect(() => validateRemoteArgs(args, info), throwsA(isA<RemoteArgsError>()));
      bad(['--exec', 'rm -rf ~', 'https://a.b/c']);
      bad(['--config-location', '/tmp/x', 'https://a.b/c']);
      bad(['-P', '/etc', 'https://a.b/c']);
      bad(['-P', '/home/me/Downloads/Haul/../../.ssh', 'https://a.b/c']);
      bad(['-o', '../../x.%(ext)s', 'https://a.b/c']);
      bad(['--ffmpeg-location', '/tmp/evil', 'https://a.b/c']);
      bad(['--js-runtimes', 'node:/tmp/evil', 'https://a.b/c']);
      bad(['--print', 'video:%(title)s', 'https://a.b/c']);
      bad(['https://a.b/c', 'https://a.b/d']);
      bad(['file:///etc/passwd']);
      bad(['-f']);
    });
  });

  group('server ⇄ phone', () {
    late Directory dir;
    late RemoteServer server;
    late FakeEngine computer;
    late Uri base;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('haul_remote');
      computer = FakeEngine();
      server = RemoteServer(engine: computer, code: () => 'K7P2QX', downloadDir: () async => dir.path, port: 0);
      await server.start();
      base = Uri.parse('http://127.0.0.1:${server.boundPort}');
    });

    tearDown(() async {
      await server.stop();
      dir.deleteSync(recursive: true);
    });

    test('pairing: wrong code refused, right code connects', () async {
      final phone = RemoteEngine();
      expect(await phone.connect(base, 'AAAAAA'), contains('didn\'t match'));
      expect(phone.ready, isFalse);
      expect(await phone.connect(base, 'k7p2-qx'), isNull);
      expect(phone.ready, isTrue);
      expect(await phone.defaultDownloadDir(), dir.path);
    });

    test('a phone queue downloads through the computer', () async {
      final phone = RemoteEngine();
      await phone.connect(base, 'K7P2QX');
      final q = QueueController(
        engine: phone,
        bridge: FakeBridge(),
        settings: () => const Settings(saveToDevice: false),
        downloadDir: phone.defaultDownloadDir,
        persist: () {},
      )..start();
      q.addText('https://v.test/one https://v.test/list');
      for (var i = 0; i < 200 && (q.pendingCount > 0 || q.items.length < 4); i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(q.items.map((i) => i.title), containsAll(['Title of https://v.test/one', 'A', 'B', 'C']));
      expect(q.doneCount, 4);
      expect(q.items.firstWhere((i) => i.title == 'A').filePath, '/downloads/a.mp4');
      // Every job ran on the computer.
      expect(computer.runs.keys.where((k) => k.startsWith('remote-')), hasLength(greaterThanOrEqualTo(6)));
    });

    test('a refused job surfaces as a failure, not a hang', () async {
      final phone = RemoteEngine();
      await phone.connect(base, 'K7P2QX');
      final r = await phone.run('x', ['--exec', 'whoami', 'https://a.b/c']);
      expect(r.ok, isFalse);
      expect(r.stderr, contains('Option not allowed'));
    });

    test('files: only from the downloads folder, only with the code', () async {
      final phone = RemoteEngine();
      await phone.connect(base, 'K7P2QX');
      File('${dir.path}/clip.mp4').writeAsStringSync('video bytes');
      final outside = File('${Directory.systemTemp.path}/haul_secret.txt')..writeAsStringSync('secret');
      addTearDown(outside.deleteSync);

      final client = HttpClient();
      addTearDown(client.close);
      Future<(int, String)> get(Uri u) async {
        final res = await (await client.getUrl(u)).close();
        return (res.statusCode, await utf8.decodeStream(res));
      }

      expect(await get(phone.fileUri('${dir.path}/clip.mp4')), (200, 'video bytes'));
      expect((await get(phone.fileUri(outside.path))).$1, 403);
      expect((await get(phone.fileUri('${dir.path}/../haul_secret.txt'))).$1, anyOf(403, 404));
      final noCode = phone.fileUri('${dir.path}/clip.mp4').replace(queryParameters: {'path': '${dir.path}/clip.mp4'});
      expect((await get(noCode)).$1, 401);
    });

    test('pause on the phone stops the job on the computer', () async {
      computer.step = const Duration(milliseconds: 80);
      final phone = RemoteEngine();
      await phone.connect(base, 'K7P2QX');
      final run = phone.run('slow', ['--newline', 'https://v.test/slow']);
      await Future.delayed(const Duration(milliseconds: 150));
      await phone.cancel('slow');
      final r = await run;
      expect(r.cancelled, isTrue);
    });
  });

  test('parseHost and codes', () {
    expect(parseHost('192.168.1.20').toString(), 'http://192.168.1.20:8642');
    expect(parseHost('pc.local:9000').toString(), 'http://pc.local:9000');
    expect(parseHost('  '), isNull);
    expect(normalizeCode(' k7p2-qx '), 'K7P2QX');
    expect(newPairingCode(), matches(RegExp(r'^[A-Z0-9]{6}$')));
  });
}
