// OLIVE BRANCH — the rules for CHOOSING a PIN, the lock-screen way to make one, and the source-level child-safety guards
// for the new keypad and first-run step. MASTERFILE §8.3, §8.5.9. Codes are obviously fake fixtures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/app_lock.dart';
import 'package:olive_client/app_lock_screen.dart';
import 'package:olive_client/local_pin.dart';

import 'pin_keypad_helpers.dart';

String code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('a gentle warning is not a block', () {
    test('birthdays, years, repeated blocks and well-known keypad shapes are guessable', () {
      for (final String p in <String>['0827', '2708', '1987', '2015', '1212', '4545', '123123', '270815', '20150827', '27081987', '2580', '1357']) {
        expect(isGuessableLocalPin(p), isTrue, reason: p);
      }
    });

    test('an ordinary PIN is not', () {
      for (final String p in <String>['4829', '7316', '5173', '91064', '830517']) {
        expect(isGuessableLocalPin(p), isFalse, reason: p);
      }
    });

    test('the obviously trivial ones are the REFUSED kind, not the warned kind (never both)', () {
      for (final String p in <String>['0000', '1234', '4321', '7777', '12345678', '9012']) {
        expect(isEasyGuessLocalPin(p), isTrue, reason: p);
        expect(isGuessableLocalPin(p), isFalse, reason: '$p is refused, so it is not also warned about');
      }
    });

    test('hostile input is never "guessable": not digits, too short, too long, empty', () {
      for (final String p in <String>['', '12', '123', '123456789', 'abcd', '12a4', '１２３４', ' 4829', '48 29']) {
        expect(isGuessableLocalPin(p), isFalse, reason: '"$p"');
      }
    });

    test('a warned PIN is still a valid PIN that can be stored and checked', () async {
      final LocalPinService s = LocalPinService(MemoryLocalPinRepository(), iterations: 500);
      expect(isValidLocalPin('0827'), isTrue);
      await s.setPin('0827');
      expect((await s.verify('0827')).ok, isTrue);
    });

    test('the warning is calm and says the choice stays theirs', () {
      expect(kGuessablePinMessage, contains('You can still use it'));
      expect(kGuessablePinMessage.toLowerCase(), isNot(contains('error')));
    });
  });

  group('the lock settings: no PIN is never a dead end', () {
    testWidgets('with no PIN the screen offers to choose one right there, and the card goes once it is set', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 500);
      final AppLockController c = AppLockController(pin: pin, repo: MemoryAppLockPrefsRepository(), observe: false);
      await t.pumpWidget(MaterialApp(home: AppLockSettingsScreen(controller: c, pinIsSet: false)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('appLockNeedsPin')), findsOneWidget);
      expect(find.textContaining('Set one under Change PIN'), findsNothing, reason: 'that old route led to the account PIN');
      await t.tap(find.byKey(const Key('appLockChoosePin')));
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
      expect(await t.runAsync(pin.isSet), isTrue);
      expect(find.byKey(const Key('appLockNeedsPin')), findsNothing);
      expect(find.byKey(const Key('appLockSwitch')), findsOneWidget);
      c.dispose();
    });
  });

  group('child safety: the keypad and the first-run step stay on the grown-up side (source guards)', () {
    final List<File> libFiles =
        Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
    String n(File f) => f.uri.pathSegments.last;
    bool childBuild(String name) =>
        name.startsWith('child_') ||
        name.startsWith('onboarding_') ||
        name == 'first_run_flow.dart' ||
        name == 'pairing_redeem_screen.dart' ||
        name == 'role_picker_screen.dart' ||
        name.startsWith('kiosk_');

    test('pin_keypad.dart is built only by the adult gate keypad and the grown-up PIN choice', () {
      final List<String> users = <String>[
        for (final File f in libFiles)
          if (n(f) != 'pin_keypad.dart' && RegExp(r"pin_keypad\.dart|\bPinKeypad\b").hasMatch(code(f.path))) n(f),
      ];
      expect(users.toSet(), <String>{'pin_gate.dart', 'local_pin_screens.dart'}, reason: 'got $users');
    });

    test('no child-build file reaches the keypad, the PIN choice, the onboarding or the keypad setting screens', () {
      final List<String> offenders = <String>[
        for (final File f in libFiles)
          if (childBuild(n(f)) &&
              RegExp(r"pin_keypad\.dart|local_pin_screens\.dart|guardian_onboarding\.dart|LocalPinSetup|ChoosePin|app_lock_screen\.dart")
                  .hasMatch(code(f.path)))
            n(f),
      ];
      expect(offenders, isEmpty, reason: '$offenders');
    });

    test('the child first run and the child kiosk never mention a PIN to the child', () {
      for (final String path in <String>['lib/first_run_flow.dart', 'lib/child_connect_screen.dart']) {
        final String src = code(path);
        // User-visible strings only: single- or double-quoted literals.
        final Iterable<String> literals = RegExp(r'''(?:'([^'\n]*)'|"([^"\n]*)")''').allMatches(src).map((Match m) => m.group(1) ?? m.group(2) ?? '');
        expect(literals.where((String l) => RegExp(r'\bPIN\b').hasMatch(l)), isEmpty, reason: path);
      }
    });

    test('the one PIN screen a child device can show is the grown-up gate: the keypad is reached only via AdultGate', () {
      final String shell = code('lib/kiosk_shell.dart');
      expect(shell.contains('PinGate('), isFalse, reason: 'kiosk_shell never builds a keypad directly');
      expect(code('lib/adult_gate.dart'), contains('PinGate('));
    });

    test('the guardian boot reopens a family with no PIN on "Choose your PIN", never on the home', () {
      final String boot = code('lib/guardian_boot.dart');
      expect(boot, contains('resumeFamily: pinSet ? null : family'));
      expect(boot, contains('if (family != null && pinSet)'), reason: 'the home needs BOTH a family and a PIN');
    });

    test('the keypad setting is read and written only through KeypadPrefs, never as a PIN screen on a child route', () {
      final List<String> users = <String>[
        for (final File f in libFiles)
          if (n(f) != 'keypad_prefs.dart' && RegExp(r"keypad_prefs\.dart").hasMatch(code(f.path))) n(f),
      ];
      expect(users.toSet(), <String>{'guardian_escalation_screen.dart', 'kiosk_shell.dart', 'main_live.dart'}, reason: '$users');
    });
  });
}
