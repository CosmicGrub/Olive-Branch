// OLIVE BRANCH — the developer-only first-run preview (dev_first_run_preview.dart): off unless built with
// OLIVE_DEV_GUARDIAN_FIRST_RUN=true, runs the real first run over an in-memory store, and never touches real data.
// MASTERFILE §8.5.9. The CI guard that keeps the define out of release builds is tools/check-dev-first-run.mjs.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/dev_first_run_preview.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/local_family.dart';

import 'pin_keypad_helpers.dart';

void main() {
  test('it is OFF in any build that does not pass the define', () {
    expect(kDevGuardianFirstRunPreview, isFalse);
  });

  test('main_live.dart only branches on the constant; it never spells the define', () {
    final String src = File('lib/main_live.dart').readAsStringSync();
    expect(src, contains('if (kDevGuardianFirstRunPreview)'));
    expect(RegExp('DEV_GUARDIAN_FIRST_RUN', caseSensitive: false).hasMatch(src), isFalse);
  });

  testWidgets('the real first run runs over memory: a PIN can be chosen, nothing real is touched, it ends on a plain page', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final GuardianLocalServices mem = GuardianLocalServices.memory(pinIterations: 500);
    await t.pumpWidget(DevGuardianFirstRunPreviewApp(services: mem));
    await t.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
    await t.enterText(find.byKey(const Key('goName')), 'Sam');
    await t.tap(find.byKey(const Key('goYouNext')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
    await t.tap(find.byKey(const Key('goAge_7')));
    await t.pump();
    await t.tap(find.byKey(const Key('goHerNext')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('goZoneNext')));
    await t.pumpAndSettle();
    expect(find.text('Choose your PIN'), findsWidgets);
    await typeOnKeypad(t, '4829');
    await t.tap(find.byKey(const Key('localPinNext')));
    await t.pumpAndSettle();
    await typeOnKeypad(t, '4829');
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('localPinSave')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    expect(find.byKey(const Key('devFirstRunPreviewDone')), findsOneWidget);
    expect(find.textContaining('Nothing was saved'), findsOneWidget);
    // It ran over the in-memory services it was given, not a real store.
    final LocalFamily? kept = await t.runAsync<LocalFamily?>(mem.families.load);
    expect(kept?.childName, 'Ivy');
  });

  test('the preview builds its own in-memory services by default and imports no real store', () {
    final String src = File('lib/dev_first_run_preview.dart')
        .readAsStringSync()
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(src, contains('GuardianLocalServices.memory('));
    for (final String bad in <String>['LocalServices.current', 'LocalServices.boot', 'GuardianLocalServices.from', 'DeviceIdentityStore']) {
      expect(src.contains(bad), isFalse, reason: bad);
    }
  });
}
