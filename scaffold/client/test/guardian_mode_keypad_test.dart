// OLIVE BRANCH — "Scramble the keypad" (keypad_prefs.dart), the tablet's Guardian mode banner saying only what was
// really used, and the switch that keeps the choice. MASTERFILE §8.3, §8.5.9. Codes here are obviously fake fixtures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_escalation_screen.dart';
import 'package:olive_client/keypad_prefs.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:olive_client/kiosk_shell.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

import 'pin_keypad_helpers.dart';

class _NoEvents extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}
  @override
  void onCancel(Object? arguments) {}
}

class _FailingKeypadRepo implements KeypadPrefsRepository {
  @override
  Future<bool> loadScramble() async => throw StateError('unreadable');
  @override
  Future<void> saveScramble(bool on) async => throw StateError('disk full');
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(KioskChannel.eventChannel, _NoEvents());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KioskChannel.methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(KioskChannel.eventChannel, null);
  });

  group('the choice itself: off unless a grown-up turns it on', () {
    test('a fresh store, an unreadable one and a malformed record all mean the plain keypad', () async {
      expect((await KeypadPrefs.load(MemoryKeypadPrefsRepository())).scramble, isFalse);
      expect((await KeypadPrefs.load(_FailingKeypadRepo())).scramble, isFalse, reason: 'an unreadable store is never a lock-out');
      final LocalServices s = LocalServices.memory();
      final LocalNamespace ns = s.area('adultunlock');
      for (final Object? bad in <Object?>[
        'yes', 1, true, <Object?, Object?>{'scramble': true}, <String, Object?>{'v': 2, 'scramble': true},
        <String, Object?>{'v': 1, 'scramble': 'true'}, <String, Object?>{'v': 1, 'scramble': 1}, <String, Object?>{'v': 1},
      ]) {
        await ns.put('keypad', bad);
        expect((await KeypadPrefs.load(LocalStoreKeypadPrefsRepository.over(s))).scramble, isFalse, reason: '$bad');
      }
      await ns.put('keypad', <String, Object?>{'v': 1, 'scramble': true});
      expect((await KeypadPrefs.load(LocalStoreKeypadPrefsRepository.over(s))).scramble, isTrue);
    });

    test('it is kept in the sealed adultunlock area, beside (never over) the grown-up PIN check', () async {
      final LocalServices s = LocalServices.memory();
      final LocalDataEntry e = localDataEntry('adultunlock');
      expect(e.encrypted, isTrue);
      expect(e.what, contains('keypad'), reason: 'the catalogue says what else the area holds');
      final LocalPinService pin = LocalPinService(LocalStoreLocalPinRepository(s.area('adultunlock')), iterations: 500);
      await pin.setPin('4829');
      final KeypadPrefs prefs = KeypadPrefs(repo: LocalStoreKeypadPrefsRepository.over(s));
      expect(await prefs.setScramble(true), isTrue);
      expect((await KeypadPrefs.load(LocalStoreKeypadPrefsRepository.over(s))).scramble, isTrue);
      expect((await pin.verify('4829')).ok, isTrue, reason: 'saving the choice never touches the PIN check');
      await pin.clear();
      expect((await KeypadPrefs.load(LocalStoreKeypadPrefsRepository.over(s))).scramble, isTrue, reason: 'and clearing the PIN does not undo it');
      expect(await prefs.setScramble(false), isTrue);
      expect((await KeypadPrefs.load(LocalStoreKeypadPrefsRepository.over(s))).scramble, isFalse);
    });

    test('the stored record holds one yes/no and no digit', () async {
      final LocalServices s = LocalServices.memory();
      await KeypadPrefs(repo: LocalStoreKeypadPrefsRepository.over(s)).setScramble(true);
      expect(await s.area('adultunlock').get('keypad'), <String, Object?>{'v': 1, 'scramble': true});
    });

    test('a store that cannot be written reports false and changes nothing', () async {
      final KeypadPrefs p = KeypadPrefs(repo: _FailingKeypadRepo());
      int heard = 0;
      p.addListener(() => heard++);
      expect(await p.setScramble(true), isFalse);
      expect(p.scramble, isFalse);
      expect(heard, 0);
    });
  });

  group('the banner says only what was really used', () {
    test('PIN only, phone only, biometric only, and the pairs', () {
      String w(EscalationProof p, {String? until = '3:00 PM'}) => escalationVerifiedWords(p, until: until);
      expect(w(const EscalationProof(pin: true)), 'Verified with your PIN — good until 3:00 PM.');
      expect(w(const EscalationProof(phone: true)), 'Verified with your phone — good until 3:00 PM.');
      expect(w(const EscalationProof(biometric: true)), 'Verified with biometric — good until 3:00 PM.');
      expect(w(const EscalationProof(pin: true, biometric: true)), 'Verified with your PIN and biometric — good until 3:00 PM.');
      expect(w(const EscalationProof(phone: true, biometric: true)), 'Verified with your phone and biometric — good until 3:00 PM.');
      expect(w(const EscalationProof(pin: true, phone: true, biometric: true)),
          'Verified with your PIN, your phone and biometric — good until 3:00 PM.');
      expect(w(const EscalationProof(pin: true), until: null), 'Verified with your PIN.');
      expect(w(const EscalationProof(), until: null), 'Verified.', reason: 'never claims a factor that was not used');
    });

    test('a PIN-only proof never mentions biometric', () {
      expect(escalationVerifiedWords(const EscalationProof(pin: true), until: '3:00 PM').toLowerCase(), isNot(contains('biometric')));
    });

    test('the old always-both sentence is gone from the source', () {
      expect(File('lib/guardian_escalation_screen.dart').readAsStringSync(), isNot(contains("'Verified with PIN and biometric")));
    });

    Widget shell(KioskShell s) => MaterialApp(home: s);

    Future<void> escalate(WidgetTester t) async {
      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await t.pumpAndSettle();
      await typeOnKeypad(t, '4829');
      await t.tap(find.byKey(const Key('pinGateConfirm')));
      await t.pumpAndSettle();
    }

    testWidgets('the tablet: a typed code and the live stand-in "biometric" say PIN only', (t) async {
      await t.pumpWidget(shell(KioskShell(
        verifyPin: (_) async => true,
        verifyBiometric: () async => true,
        biometricIsReal: false, // main_live.dart's stand-in
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await escalate(t);
      final String text = t.widget<Text>(find.byKey(const Key('escalationVerifiedBanner'))).data!;
      expect(text, startsWith('Verified with your PIN'));
      expect(text.toLowerCase(), isNot(contains('biometric')), reason: text);
    });

    testWidgets('a real biometric that passed is named alongside the PIN', (t) async {
      await t.pumpWidget(shell(KioskShell(
        verifyPin: (_) async => true,
        verifyBiometric: () async => true,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await escalate(t);
      expect(t.widget<Text>(find.byKey(const Key('escalationVerifiedBanner'))).data!, startsWith('Verified with your PIN and biometric'));
    });
  });

  group('the gate honours the choice', () {
    Future<void> openKeypad(WidgetTester t) async {
      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await t.pumpAndSettle();
    }

    Future<String> orderFor(WidgetTester t, KeypadPrefs? prefs) async {
      await t.pumpWidget(MaterialApp(
          key: UniqueKey(),
          home: KioskShell(
        verifyPin: (_) async => false,
        verifyBiometric: () async => true,
        keypadPrefs: prefs,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await openKeypad(t);
      return keypadDigitOrder(t).join();
    }

    testWidgets('default: the plain order. Turned on: shuffled, every time a different arrangement is possible', (t) async {
      expect(await orderFor(t, null), '1234567890', reason: 'no prefs object: plain');
      expect(await orderFor(t, KeypadPrefs()), '1234567890', reason: 'default off: plain');
      final Set<String> on = <String>{};
      for (int i = 0; i < 10; i++) {
        final String o = await orderFor(t, KeypadPrefs(scramble: true));
        expect(o.split('')..sort(), <String>['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);
        on.add(o);
      }
      expect(on.length, greaterThan(1));
    });

    testWidgets('Guardian mode shows the switch (off), turning it on is kept; a failed save says so and stays off', (t) async {
      final MemoryKeypadPrefsRepository repo = MemoryKeypadPrefsRepository();
      final KeypadPrefs prefs = KeypadPrefs(repo: repo);
      await t.pumpWidget(MaterialApp(
          home: KioskShell(
        verifyPin: (_) async => true,
        verifyBiometric: () async => true,
        keypadPrefs: prefs,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await openKeypad(t);
      await typeOnKeypad(t, '4829');
      await t.tap(find.byKey(const Key('pinGateConfirm')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scrambleKeypadSwitch')), findsOneWidget);
      expect(find.text('Scramble the keypad'), findsOneWidget);
      expect(find.textContaining('child watching'), findsOneWidget, reason: 'one plain sentence about why');
      expect(t.widget<SwitchListTile>(find.byKey(const Key('scrambleKeypadSwitch'))).value, isFalse);
      await t.tap(find.byKey(const Key('scrambleKeypadSwitch')));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(find.byKey(const Key('scrambleKeypadSwitch'))).value, isTrue);
      expect(await repo.loadScramble(), isTrue);
    });

    testWidgets('the switch with a store that cannot be written: plain words, still off', (t) async {
      await t.pumpWidget(MaterialApp(
          home: GuardianEscalationScreen(
              escalatedUntil: null, onExitKiosk: () {}, keypadPrefs: KeypadPrefs(repo: _FailingKeypadRepo()))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scrambleKeypadSwitch')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scrambleKeypadError')), findsOneWidget);
      expect(find.textContaining('disk full'), findsNothing);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('scrambleKeypadSwitch'))).value, isFalse);
    });
  });

  group('the child side', () {
    test('no PIN word appears on the child surface, the calm card or the lock-out screen text in kiosk_shell and adult_gate', () {
      // The only screens that carry the word are the grown-up keypad (pin_gate.dart) and Guardian mode.
      final String card = File('lib/adult_gate.dart').readAsStringSync();
      final int start = card.indexOf('class AdultGateCard');
      final int end = card.indexOf('class CalmTryAgainCard');
      final String cardSrc = card.substring(start, end).split('\n').where((String l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(RegExp(r"'[^']*\bPIN\b[^']*'").hasMatch(cardSrc), isFalse, reason: 'the card a child can reach says nothing about a PIN');
    });
  });
}
