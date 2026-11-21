// OLIVE BRANCH — the grown-up's tablet-update screens: nothing without the machinery, the plain adult words, the
// confirm-before-install path, and the line that no child surface can ever reach any of it. Headless.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tablet_update_screens.dart';
import 'package:olive_client/tablet_update_service.dart';

import 'tablet_update_service_test.dart' show Setup;

/// Real file work started from a tap finishes on the real clock but its continuations run in the test's fake zone, so
/// wait a little for real and pump between waits.
Future<void> settle(WidgetTester t, bool Function() done) async {
  for (int i = 0; i < 400 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
  await t.pump();
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('with no update machinery on this build the card draws nothing at all', (WidgetTester t) async {
    TabletUpdateService.current = null;
    await t.pumpWidget(host(TabletUpdateCard(adultPresent: () => true)));
    expect(find.byKey(const Key('tabletUpdateCard')), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a staged update reads "An update is ready" with the notes, the pin sentence and an Install button', (WidgetTester t) async {
    final Setup s = await t.runAsync(Setup.make) as Setup;
    await t.pumpWidget(host(TabletUpdateCard(service: s.service, adultPresent: () => true)));
    await t.pump();
    expect(find.text('An update is ready'), findsOneWidget);
    expect(find.textContaining('Install it?'), findsOneWidget);
    expect(find.textContaining('Calmer pairing.'), findsOneWidget);
    expect(find.textContaining('App is pinned'), findsOneWidget, reason: 'the kiosk is explained in plain words');
    expect(find.byKey(const Key('tabletUpdateInstall')), findsOneWidget);
    // The words a child must never see: no count, no badge, no error code.
    expect(find.textContaining(RegExp(r'\b(error|failed|exception)\b', caseSensitive: false)), findsNothing);
  });

  testWidgets('Install while no grown-up is proved does nothing: the lock is not released and nothing is shown', (WidgetTester t) async {
    final Setup s = await t.runAsync(Setup.make) as Setup;
    s.adult = false;
    await t.pumpWidget(host(TabletUpdateCard(service: s.service, adultPresent: () => s.adult)));
    await t.pump();
    await t.tap(find.byKey(const Key('tabletUpdateInstall')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(s.log, isNot(contains('kiosk.begin')), reason: 'the pin is only let go for a proved grown-up');
    expect(s.log, isNot(contains('engine.install')));
  });

  testWidgets('a grown-up tapping Install runs the checks, lets the lock go and shows Android\'s steps in words', (WidgetTester t) async {
    final Setup s = await t.runAsync(Setup.make) as Setup;
    await t.pumpWidget(host(TabletUpdateCard(service: s.service, adultPresent: () => true)));
    await t.pump();
    await t.tap(find.byKey(const Key('tabletUpdateInstall')));
    await settle(t, () => s.log.contains('engine.install'));
    expect(s.log, <String>['engine.verify.install', 'kiosk.begin', 'engine.install']);
    expect(find.text('Follow Android on the screen'), findsOneWidget);
  });

  testWidgets('"Not now" removes the staged update quietly', (WidgetTester t) async {
    final Setup s = await t.runAsync(Setup.make) as Setup;
    await t.pumpWidget(host(TabletUpdateCard(service: s.service, adultPresent: () => true)));
    await t.pump();
    await t.tap(find.byKey(const Key('tabletUpdateDiscard')));
    await settle(t, () => s.service.staged == null);
    expect(find.text('An update is ready'), findsNothing);
    expect(await t.runAsync(() => s.store.loadStaged()), isNull);
  });

  test('no child surface can reach the update screens: only the Guardian-mode screens import them', () {
    final Directory lib = Directory('lib');
    final List<String> importers = <String>[];
    for (final File f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final String name = f.uri.pathSegments.last;
      if (name.startsWith('tablet_update_')) continue;
      final String src = f.readAsStringSync();
      if (src.contains("tablet_update_screens.dart")) importers.add(name);
    }
    importers.sort();
    expect(importers, <String>['guardian_escalation_screen.dart', 'guardian_more.dart'],
        reason: 'the card lives in Guardian mode and the phone\'s Settings, nowhere a child can open');
    // And the words of this feature are not in any child file.
    for (final File f in lib.listSync(recursive: true).whereType<File>()) {
      final String name = f.uri.pathSegments.last;
      if (!(name.startsWith('child_') || name.startsWith('kid_'))) continue;
      final String src = f.readAsStringSync();
      expect(src.contains('An update is ready'), isFalse, reason: name);
      expect(src.contains('TabletUpdateService'), isFalse, reason: name);
    }
  });
}
