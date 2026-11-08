// OLIVE BRANCH — the parity harness's main test: replay the prototype's seven scenarios against the real
// Flutter screens, run the rule table, write the ledger, and hold the ratchet. No longer UNVERIFIED — verified by CI.
//
//   * Each scenario replays tools/gen-parity-scenarios.mjs's scenarios.json; every action and assertion becomes a
//     ledger unit (implemented / pending / differs). Nothing here fails because a feature is missing.
//   * The last test writes test/parity/ledger.json (full detail, printed as a table) and compares the run with the
//     committed ledger_baseline.json: an implemented unit may not regress, and the pending and differs counts may
//     not rise. Progress is allowed; lock it in with
//       PARITY_UPDATE_BASELINE=1 flutter test test/parity/scenario_parity_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/parental_controls_screen.dart';

import 'fake_server.dart';
import 'parity_ledger.dart';
import 'rule_checks.dart';
import 'scenario_runner.dart';
import 'virtual_clock.dart';

final List<LedgerUnit> _units = <LedgerUnit>[];
const List<String> _ids = <String>['golden', 'offline', 'birthday', 'call', 'play', 'family', 'deletion'];

Future<void> _tall(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(800, 10000));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Future<void> _mountControls(WidgetTester t, FakeServer s) => t.pumpWidget(MaterialApp(
    home: ParentalControlsScreen(baseUrl: 'http://olive.test', childId: 'child-1', childName: 'Ivy', guardianId: 'mom', httpClient: s.clientFor('g'))));

Future<void> _enterPin(WidgetTester t, String pin) async {
  await t.enterText(find.byKey(const Key('parentalControlsPinField')), pin);
  await t.tap(find.byKey(const Key('parentalControlsVerifyButton')));
  await t.pumpAndSettle();
}

void main() {
  final Map<String, Object?> doc = loadScenarios();
  final Map<String, Map<String, Object?>> byId = <String, Map<String, Object?>>{
    for (final Object? s in doc['scenarios']! as List<Object?>) (s! as Map<String, Object?>)['id']! as String: s as Map<String, Object?>,
  };

  test('scenarios.json has the seven prototype scenarios', () {
    expect(byId.keys.toList(), _ids);
  });

  for (final String id in _ids) {
    testWidgets('replay scenario "$id" against the real screens', (WidgetTester tester) async {
      final List<LedgerUnit> units = await runScenario(tester, byId[id]!);
      expect(units, isNotEmpty);
      _units.addAll(units);
    });
  }

  testWidgets('rules: the Flutter parental-controls screen against the FakeServer (Messages not hideable, PIN lockout)', (WidgetTester tester) async {
    await _tall(tester);
    final VirtualClock clock = VirtualClock(tester);
    final FakeServer s = FakeServer(clock);
    await _mountControls(tester, s);
    await _enterPin(tester, '2468');
    final bool hideable = find.byKey(const Key('visible_tile:messages')).evaluate().isNotEmpty;
    _units.add(LedgerUnit('rules#controls.messagesNotHideable', 'rules', 'rule', 'Messages can never be hidden or paced (ParentalControlsScreen)',
        hideable ? UnitStatus.differs : UnitStatus.implemented,
        rows: <String>['tile:msgs'], note: hideable ? 'the Flutter screen offers a visibility switch for Messages (visible_tile:messages); wave 1a removes it' : ''));

    // Five wrong PINs through the REAL screen, then the lock, then the unlock after 15 virtual minutes.
    final FakeServer s2 = FakeServer(clock);
    await tester.pumpWidget(const SizedBox.shrink()); // a fresh screen, back at its PIN step
    await _mountControls(tester, s2);
    for (int i = 0; i < 5; i++) {
      await _enterPin(tester, '0000');
    }
    final bool lockedShown = find.textContaining('Too many tries').evaluate().isNotEmpty;
    await _enterPin(tester, '2468');
    final bool stillLocked = find.byKey(const Key('parentalControlsTabSwitch')).evaluate().isEmpty;
    await tester.pump(const Duration(minutes: 16));
    await _enterPin(tester, '2468');
    final bool unlocked = find.byKey(const Key('parentalControlsTabSwitch')).evaluate().isNotEmpty;
    final bool ok = lockedShown && stillLocked && unlocked;
    _units.add(LedgerUnit('rules#pin.lockoutThroughTheRealScreen', 'rules', 'rule', '5 wrong PINs lock the PIN gate for 15 minutes (ParentalControlsScreen)',
        ok ? UnitStatus.implemented : UnitStatus.differs,
        rows: <String>['sub:PIN rate limit (5 wrong)'], note: ok ? '' : 'locked message shown: $lockedShown, right PIN refused while locked: $stillLocked, opens after 16 min: $unlocked'));
    expect(ok, isTrue, reason: 'the real screen must honour the lock the server reports');
  });

  test('rules: the rule table', () async {
    final Map<String, Object?> rules = doc['rules']! as Map<String, Object?>;
    for (final RuleCheck c in ruleChecks) {
      final Res r = await c.run(rules);
      _units.add(LedgerUnit('rules#${c.id}', 'rules', 'rule', c.id, r.status, rows: c.rows, note: r.note));
    }
  });

  test('ledger: write ledger.json, print the counts, hold the ratchet', () {
    if (_units.length < 50) {
      markTestSkipped('partial run (a filtered subset of the parity tests): the ledger is only judged on a full run');
      return;
    }
    _units.sort((LedgerUnit a, LedgerUnit b) => a.id.compareTo(b.id));
    final Ledger ledger = Ledger(_units);
    writeIfChanged(File('test/parity/ledger.json'), prettyJson(ledger.toJson()));

    final StringBuffer b = StringBuffer('\nPARITY LEDGER (units: implemented / pending / differs)\n');
    for (final String g in <String>[..._ids, 'rules']) {
      b.writeln('  ${g.padRight(9)} ${ledger.count(UnitStatus.implemented, group: g).toString().padLeft(4)} / ${ledger.count(UnitStatus.pending, group: g).toString().padLeft(4)} / ${ledger.count(UnitStatus.differs, group: g).toString().padLeft(4)}'
          '${g == 'rules' ? '' : '   steps ${((ledger.toJson()['groups']! as Map<String, Object?>)[g]! as Map<String, Object?>)['steps']}'}');
    }
    b.writeln('  ${'TOTAL'.padRight(9)} ${ledger.count(UnitStatus.implemented).toString().padLeft(4)} / ${ledger.count(UnitStatus.pending).toString().padLeft(4)} / ${ledger.count(UnitStatus.differs).toString().padLeft(4)}');
    // ignore: avoid_print
    print(b);

    final File baseline = File('test/parity/ledger_baseline.json');
    if (Platform.environment['PARITY_UPDATE_BASELINE'] == '1') {
      writeIfChanged(baseline, prettyJson(ledger.baselineJson()));
      return;
    }
    expect(baseline.existsSync(), isTrue, reason: 'ledger_baseline.json is missing: run with PARITY_UPDATE_BASELINE=1 and commit it');
    final Map<String, Object?> base = jsonDecode(baseline.readAsStringSync()) as Map<String, Object?>;
    final List<String> failures = ratchetFailures(ledger, base);
    expect(failures, isEmpty, reason: failures.join('\n'));
    final Map<String, Object?> t = base['totals']! as Map<String, Object?>;
    if (ledger.count(UnitStatus.pending) < (t['pending']! as int) || ledger.count(UnitStatus.differs) < (t['differs']! as int) ||
        ledger.count(UnitStatus.implemented) > (t['implemented']! as int)) {
      // ignore: avoid_print
      print('Parity progressed past the committed baseline. Lock it in: PARITY_UPDATE_BASELINE=1 flutter test test/parity/scenario_parity_test.dart');
    }
  });
}
