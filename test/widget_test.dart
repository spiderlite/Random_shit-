import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/app.dart';
import 'package:haul/state/app_state.dart';
import 'package:haul/state/store.dart';
import 'package:haul/ui/settings/settings_screen.dart';

import 'fake_engine.dart';

/// The empty state gently loops forever, so never wait for "settled".
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<AppState> _boot(WidgetTester tester, Size size, {bool mobile = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('haul_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final state = AppState(engine: FakeEngine(mobile: mobile), bridge: FakeBridge(), store: Store(dir));
  await tester.runAsync(state.init);
  await tester.pumpWidget(HaulApp(state: state));
  await _settle(tester);
  if (mobile) {
    // Phones never see setup: the engine is built in.
    expect(state.phase, Phase.ready);
    return state;
  }
  // Desktop first run: the setup screen, with everything already found.
  expect(state.phase, Phase.setup);
  expect(find.text('Set up Haul'), findsOneWidget);
  await tester.tap(find.text('Continue'));
  await _settle(tester);
  expect(state.phase, Phase.ready);
  return state;
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _settle(tester);
}

void main() {
  testWidgets('phone: paste links, watch them download', (tester) async {
    final state = await _boot(tester, const Size(390, 844), mobile: true);

    expect(find.text('No downloads yet'), findsOneWidget);
    expect(find.text('In any app, tap Share on a video'), findsOneWidget);
    expect(find.text('Paste and download'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'look https://v.test/one and https://v.test/two');
    await tester.pump();
    expect(find.text('2 links'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await _drain(tester);

    expect(state.queue.doneCount, 2);
    expect(find.text('Title of https://v.test/one'), findsOneWidget);
    expect(find.text('2 downloads finished'), findsOneWidget);
  });

  testWidgets('desktop: playlist expands and details open', (tester) async {
    final state = await _boot(tester, const Size(1100, 800));

    await tester.enterText(find.byType(TextField), 'https://v.test/list');
    await tester.pump();
    expect(find.text('Download'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await _drain(tester);

    expect(state.queue.items.length, 3);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.text('A'));
    await _settle(tester);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Show in folder'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('settings open and the theme can change', (tester) async {
    final state = await _boot(tester, const Size(1100, 800));
    await tester.tap(find.byTooltip('Settings'));
    await _settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dark'),
      300,
      scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first,
    );
    await _settle(tester);
    await tester.tap(find.text('Dark'));
    await _settle(tester);
    expect(state.settings.theme.name, 'dark');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('phone: engine fails to start, error is shown, Try again recovers', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('haul_engine_fail');
    addTearDown(() => dir.deleteSync(recursive: true));
    final engine = FakeEngine(mobile: true)..failStarts = 1;
    final state = AppState(engine: engine, bridge: FakeBridge(), store: Store(dir));
    await tester.runAsync(state.init);
    await tester.pumpWidget(HaulApp(state: state));
    await _settle(tester);

    // Not the desktop setup wizard: an honest error with the real cause.
    expect(find.text('Set up Haul'), findsNothing);
    expect(find.text('The download engine didn\'t start'), findsOneWidget);
    expect(find.textContaining('ClassNotFoundException'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await _settle(tester);
    expect(state.phase, Phase.ready);
    expect(find.text('No downloads yet'), findsOneWidget);
  });
}
