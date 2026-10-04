// Renders the real UI to docs/screenshots/*.png with the real fonts.
//
//   HAUL_SCREENSHOTS=1 flutter test test/screenshots_test.dart
//
// Skipped otherwise (pixels differ a little between machines, so these are
// pictures for the README, not golden tests).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/app.dart';
import 'package:haul/core/models.dart';
import 'package:haul/state/app_state.dart';
import 'package:haul/state/store.dart';
import 'package:haul/ui/details/item_sheet.dart';
import 'package:haul/ui/settings/settings_screen.dart';

import 'fake_engine.dart';

final _enabled = Platform.environment['HAUL_SCREENSHOTS'] == '1';
final _out = Directory('docs/screenshots');
final _shotKey = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Plex');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/IBMPlexSans-$w.ttf'));
  }
  await inter.load();
  final mono = FontLoader('PlexMono');
  for (final w in ['Regular', 'Medium']) {
    mono.addFont(rootBundle.load('assets/fonts/IBMPlexMono-$w.ttf'));
  }
  await mono.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
}

/// Soft abstract thumbnails, drawn here so the screenshots contain no one
/// else's artwork.
Future<List<String>> _thumbs(Directory dir) async {
  const palettes = [
    // Natural, varied tones (dawn, sea, dusk, slate, desert, meadow, fog)
    // rather than the purple-blue gradients generated UIs default to.
    [Color(0xFFF2C79B), Color(0xFF8C5A3C)],
    [Color(0xFFA9D6CF), Color(0xFF2F6B6A)],
    [Color(0xFFF6D58E), Color(0xFFC0563A)],
    [Color(0xFFB9C3C9), Color(0xFF3B4A55)],
    [Color(0xFFE9D3B4), Color(0xFF9A6B45)],
    [Color(0xFFCFE3B5), Color(0xFF55703A)],
    [Color(0xFFDDE3E6), Color(0xFF7D8C93)],
  ];
  final paths = <String>[];
  for (final (i, c) in palettes.indexed) {
    const w = 640.0, h = 360.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), c),
    );
    final rnd = math.Random(i * 7 + 3);
    // Rolling hills + a sun: reads as "a video" without being anything.
    canvas.drawCircle(Offset(w * (0.25 + rnd.nextDouble() * 0.5), h * 0.35), 46 + rnd.nextDouble() * 20,
        Paint()..color = Colors.white.withValues(alpha: 0.55));
    for (var layer = 0; layer < 3; layer++) {
      final path = Path()..moveTo(0, h);
      final base = h * (0.62 + layer * 0.1);
      for (var x = 0.0; x <= w; x += 20) {
        path.lineTo(x, base + math.sin(x / (90 + layer * 30) + i + layer) * (18 - layer * 4));
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.10 + layer * 0.08));
    }
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${dir.path}/thumb$i.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
    paths.add(f.path);
  }
  return paths;
}

List<Map<String, dynamic>> _demoItems(List<String> t) {
  final now = DateTime.now();
  Map<String, dynamic> item(String id, String title, String status, int thumb,
          {String? uploader, double? dur, String preset = 'p1080', String? collection, int? size, String? error, int ago = 0}) =>
      {
        'id': id,
        'url': 'https://example.com/watch/$id',
        'preset': preset,
        'addedAt': now.subtract(Duration(minutes: ago)).toIso8601String(),
        'status': status,
        'title': title,
        'uploader': uploader,
        'thumbnail': t[thumb],
        'duration': dur,
        'collection': collection,
        'fileSize': size,
        'error': error,
        'probed': true,
        'filePath': status == 'done' ? '/home/you/Downloads/Haul/$title.mp4' : null,
        'completedAt': status == 'done' ? now.subtract(Duration(minutes: ago)).toIso8601String() : null,
      };
  return [
    item('a1', 'Slow morning in the mountains', 'downloading', 0, uploader: 'Quiet Trails', dur: 1325),
    item('a2', 'Building a tiny cabin, day 3', 'downloading', 1, uploader: 'Handmade Haus', dur: 2011, collection: 'Cabin build'),
    item('a3', 'Rainy night synth session', 'processing', 4, uploader: 'Night Loops', dur: 3600, preset: 'mp3'),
    item('a4', 'How suspension bridges stay up', 'queued', 3, uploader: 'Pocket Physics', dur: 845, collection: 'Cabin build'),
    item('a5', 'Street food tour after dark', 'failed', 2, uploader: 'Wander Bites', dur: 1490,
        error: 'This video is unavailable or was removed.'),
    item('a6', 'Ocean waves for focus', 'done', 6, uploader: 'Soft Noise', dur: 5400, size: 812 * 1024 * 1024, ago: 12),
    item('a7', 'Sourdough, explained simply', 'done', 5, uploader: 'Crumb Club', dur: 734, size: 96 * 1024 * 1024, ago: 40),
  ];
}

Future<AppState> _setUp(WidgetTester tester, {required Size size, required double dpr, required bool mobile, required ThemePref theme, bool empty = false}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  final dir = Directory.systemTemp.createTempSync('haul_shots');
  addTearDown(() => dir.deleteSync(recursive: true));
  final thumbs = (await tester.runAsync(() => _thumbs(dir)))!;

  final engine = FakeEngine(mobile: mobile);
  final state = AppState(engine: engine, bridge: FakeBridge(), store: Store(dir));
  await tester.runAsync(state.init);
  if (!mobile) state.finishSetup();
  state.update((s) => s.copyWith(theme: theme, onboarded: true));
  // Freeze the queue so the demo states stay exactly as written.
  engine.frozen = true;
  if (!empty) {
    state.queue.restore(_demoItems(thumbs));
    final items = state.queue.items;
    items[0]
      ..progress = 0.62
      ..downloadedBytes = 214 * 1024 * 1024
      ..totalBytes = 345 * 1024 * 1024
      ..speed = 8.4 * 1024 * 1024
      ..eta = 15;
    items[1]
      ..progress = 0.18
      ..downloadedBytes = 61 * 1024 * 1024
      ..totalBytes = 338 * 1024 * 1024
      ..speed = 5.1 * 1024 * 1024
      ..eta = 54;
    items[2].progress = 1;
  }

  await tester.pumpWidget(RepaintBoundary(key: _shotKey, child: HaulApp(state: state)));
  // Let images decode (real async) and entrance animations finish.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  return state;
}

Future<void> _snap(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 250));
  }
  final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: tester.view.devicePixelRatio)))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  _out.createSync(recursive: true);
  File('${_out.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  const phone = Size(390, 844);
  const desktop = Size(1180, 820);

  testWidgets('phone light', (tester) async {
    await _setUp(tester, size: phone, dpr: 3, mobile: true, theme: ThemePref.light);
    await _snap(tester, 'phone-queue-light');
  }, skip: !_enabled);

  testWidgets('phone dark', (tester) async {
    await _setUp(tester, size: phone, dpr: 3, mobile: true, theme: ThemePref.dark);
    await _snap(tester, 'phone-queue-dark');
  }, skip: !_enabled);

  testWidgets('phone empty', (tester) async {
    await _setUp(tester, size: phone, dpr: 3, mobile: true, theme: ThemePref.light, empty: true);
    await _snap(tester, 'phone-empty');
  }, skip: !_enabled);

  testWidgets('phone details', (tester) async {
    final state = await _setUp(tester, size: phone, dpr: 3, mobile: true, theme: ThemePref.light);
    final ctx = tester.element(find.byType(Scaffold).first);
    showItemDetails(ctx, state.queue.items[5].id, compact: true);
    // The large thumbnail decodes after the sheet slides in.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _snap(tester, 'phone-details');
  }, skip: !_enabled);

  testWidgets('phone settings', (tester) async {
    await _setUp(tester, size: phone, dpr: 3, mobile: true, theme: ThemePref.dark);
    final ctx = tester.element(find.byType(Scaffold).first);
    Navigator.of(ctx).push(SettingsScreen.route());
    await _snap(tester, 'phone-settings-dark');
  }, skip: !_enabled);

  testWidgets('desktop light', (tester) async {
    await _setUp(tester, size: desktop, dpr: 2, mobile: false, theme: ThemePref.light);
    await _snap(tester, 'desktop-light');
  }, skip: !_enabled);

  testWidgets('desktop dark', (tester) async {
    await _setUp(tester, size: desktop, dpr: 2, mobile: false, theme: ThemePref.dark);
    await _snap(tester, 'desktop-dark');
  }, skip: !_enabled);
}
