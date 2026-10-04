import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/app.dart';
import 'package:haul/core/models.dart';
import 'package:haul/state/app_state.dart';
import 'package:haul/state/store.dart';
import 'package:haul/theme/theme.dart';
import 'package:haul/ui/settings/settings_screen.dart';

import 'fake_engine.dart';

Future<void> _pumpFor(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A phone with a few downloads in different states.
Future<AppState> _phone(WidgetTester tester, {double textScale = 1, bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (reduceMotion) tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final dir = Directory.systemTemp.createTempSync('haul_a11y');
  addTearDown(() => dir.deleteSync(recursive: true));
  final engine = FakeEngine(mobile: true);
  final state = AppState(engine: engine, bridge: FakeBridge(), store: Store(dir));
  await tester.runAsync(state.init);
  engine.frozen = true;
  state.queue.restore([
    {'id': 'a', 'url': 'https://example.com/a', 'preset': 'p1080', 'status': 'downloading', 'title': 'A long video title that needs to wrap onto two lines', 'probed': true},
    {'id': 'b', 'url': 'https://example.com/b', 'preset': 'mp3', 'status': 'failed', 'title': 'Broken one', 'error': 'This video is unavailable or was removed.', 'probed': true},
    {'id': 'c', 'url': 'https://example.com/c', 'preset': 'p720', 'status': 'done', 'title': 'Finished', 'fileSize': 1000000, 'filePath': '/x/Finished.mp4', 'probed': true},
  ]);
  state.queue.items.first.progress = 0.4;
  await tester.pumpWidget(HaulApp(state: state));
  await _pumpFor(tester);
  return state;
}

void main() {
  testWidgets('touch targets meet Android (48dp) and iOS (44pt) guidelines, and are labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await _phone(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('text contrast meets WCAG AA in light and dark', (tester) async {
    final handle = tester.ensureSemantics();
    final state = await _phone(tester);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    state.update((s) => s.copyWith(theme: ThemePref.dark));
    await _pumpFor(tester, 8);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('200% text size: nothing overflows', (tester) async {
    await _phone(tester, textScale: 2);
    // RenderFlex overflows surface as test exceptions; none means it fits.
    expect(tester.takeException(), isNull);
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('reduced motion: animations collapse to instant', (tester) async {
    await _phone(tester, reduceMotion: true);
    expect(Motion.reduced, isTrue);
    expect(Motion.normal, Duration.zero);
  });

  testWidgets('keyboard only: Tab reaches Settings and Enter opens it', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('haul_kb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(engine: FakeEngine(), bridge: FakeBridge(), store: Store(dir));
    await tester.runAsync(state.init);
    state.finishSetup();
    await tester.pumpWidget(HaulApp(state: state));
    await _pumpFor(tester);

    bool settingsFocused() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      var found = false;
      ctx.visitAncestorElements((e) {
        final w = e.widget;
        if (w is Tooltip && w.message == 'Settings') found = true;
        return !found;
      });
      return found;
    }

    for (var i = 0; i < 25 && !settingsFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(settingsFocused(), isTrue, reason: 'Settings button should be reachable with Tab');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpFor(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
