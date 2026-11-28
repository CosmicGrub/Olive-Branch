// OLIVE BRANCH — local_pin_screens.dart tests: choosing the local PIN and being asked for it.
// No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.9.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_screens.dart';

import 'pin_keypad_helpers.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 8, 12);
  DateTime call() => now;
}

class _FailingRepo implements LocalPinRepository {
  @override
  Future<LocalPinRecord?> load() async => null;
  @override
  Future<void> save(LocalPinRecord r) async => throw StateError('disk full');
  @override
  Future<void> clear() async {}
}

void main() {
  LocalPinService service([_Clock? c]) =>
      LocalPinService(MemoryLocalPinRepository(), now: (c ?? _Clock()).call, iterations: 500);

  group('the setup form (the ordinary keypad, typed twice)', () {
    Future<void> pumpForm(WidgetTester t, LocalPinService s, VoidCallback onSaved) async {
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: LocalPinSetupForm(service: s, onSaved: onSaved)))));
    }

    Future<void> next(WidgetTester t) async {
      await t.tap(find.byKey(const Key('localPinNext')));
      await t.pump();
    }

    Future<void> save(WidgetTester t) async {
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('localPinSave')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
    }

    testWidgets('it uses the ordinary keypad and says what a good PIN is, in plain words', (t) async {
      await pumpForm(t, service(), () {});
      expect(keypadDigitOrder(t), <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']);
      expect(find.text('Choose your PIN'), findsOneWidget);
      expect(find.textContaining('4 to 8 digits'), findsOneWidget);
      expect(find.textContaining('birthday'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no text box: the keypad is the only way in');
    });

    testWidgets('a short PIN cannot be submitted: Next stays off until four digits are in', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await typeOnKeypad(t, '258');
      expect(t.widget<FilledButton>(find.byKey(const Key('localPinNext'))).onPressed, isNull);
      expect(saved, isFalse);
      expect(await s.isSet(), isFalse);
    });

    testWidgets('an easy-guess PIN is refused gently at setup, and nothing is stored', (t) async {
      for (final String easy in <String>['0000', '1234', '4321', '7777', '12345678']) {
        bool saved = false;
        final LocalPinService s = service();
        await pumpForm(t, s, () => saved = true);
        await typeOnKeypad(t, easy);
        await next(t);
        expect(find.text(kEasyGuessPinMessage), findsOneWidget, reason: easy);
        expect(find.text('Type it once more to confirm'), findsNothing, reason: '$easy never reaches confirm');
        expect(saved, isFalse, reason: easy);
        expect(await s.isSet(), isFalse, reason: easy);
      }
    });

    testWidgets('a date-like or patterned PIN gets ONE gentle warning and may be kept', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await typeOnKeypad(t, '0827'); // looks like a birthday
      await next(t);
      expect(find.byKey(const Key('localPinGuessable')), findsOneWidget);
      expect(find.text(kGuessablePinMessage), findsOneWidget);
      expect(await s.isSet(), isFalse, reason: 'the warning stores nothing');
      // Choosing another goes back to a fresh keypad.
      await t.tap(find.byKey(const Key('localPinChooseAnother')));
      await t.pump();
      expect(find.text('Choose your PIN'), findsOneWidget);
      // Keeping it is the grown-up's call.
      await typeOnKeypad(t, '0827');
      await next(t);
      await t.tap(find.byKey(const Key('localPinUseAnyway')));
      await t.pump();
      expect(find.text('Type it once more to confirm'), findsOneWidget);
      await typeOnKeypad(t, '0827');
      await save(t);
      expect(saved, isTrue);
      expect(await t.runAsync(s.isSet), isTrue);
    });

    testWidgets('an ordinary PIN gets no warning at all', (t) async {
      await pumpForm(t, service(), () {});
      await typeOnKeypad(t, '4829');
      await next(t);
      expect(find.byKey(const Key('localPinGuessable')), findsNothing);
      expect(find.text('Type it once more to confirm'), findsOneWidget);
    });

    testWidgets('two different PINs are refused and the grown-up starts again, nothing stored', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await typeOnKeypad(t, '4829');
      await next(t);
      await typeOnKeypad(t, '4828');
      await save(t);
      expect(find.textContaining("The two PINs don't match"), findsOneWidget);
      expect(find.text('Choose your PIN'), findsOneWidget, reason: 'back at the first step with an empty keypad');
      expect(saved, isFalse);
      expect(await s.isSet(), isFalse);
    });

    testWidgets('Start over drops what was typed', (t) async {
      final LocalPinService s = service();
      await pumpForm(t, s, () {});
      await typeOnKeypad(t, '4829');
      await next(t);
      await t.tap(find.byKey(const Key('localPinStartOver')));
      await t.pump();
      expect(find.text('Choose your PIN'), findsOneWidget);
      expect(pinDots(t).filled, 0);
    });

    testWidgets('a good PIN is stored (as a hash only), and onSaved fires', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await typeOnKeypad(t, '4829');
      await next(t);
      await typeOnKeypad(t, '4829');
      await save(t);
      expect(saved, isTrue);
      expect(await t.runAsync(s.isSet), isTrue);
      expect((await t.runAsync(() => s.verify('4829')))!.ok, isTrue);
      expect(find.byKey(const Key('localPinError')), findsNothing);
    });

    testWidgets('a store that cannot be written says so plainly and does NOT call onSaved', (t) async {
      bool saved = false;
      final LocalPinService s = LocalPinService(_FailingRepo(), iterations: 500);
      await pumpForm(t, s, () => saved = true);
      await typeOnKeypad(t, '4829');
      await next(t);
      await typeOnKeypad(t, '4829');
      await save(t);
      expect(saved, isFalse);
      expect(find.text('Could not keep your PIN on this device. Please try again.'), findsOneWidget);
      expect(find.textContaining('disk full'), findsNothing, reason: 'no raw error text');
    });
  });

  group('the setup screen (the exit from the offline server-PIN trap)', () {
    testWidgets('says it is for this device only and works with no connection; saving continues', (t) async {
      bool done = false;
      final LocalPinService s = service();
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: LocalPinSetupScreen(service: s, onDone: () => done = true)));
      expect(find.text('Choose your PIN'), findsWidgets);
      expect(find.textContaining('only for this device'), findsOneWidget);
      expect(find.textContaining('works with no connection'), findsOneWidget);
      await typeOnKeypad(t, '4829');
      await t.tap(find.byKey(const Key('localPinNext')));
      await t.pump();
      await typeOnKeypad(t, '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('localPinSave')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(done, isTrue);
    });
  });

  group('the gate', () {
    Future<void> type(WidgetTester t, String pin) async {
      await t.runAsync(() async {
        await t.enterText(find.byKey(const Key('localPinField')), pin);
        await t.tap(find.byKey(const Key('localPinOk')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pumpAndSettle();
    }

    testWidgets('the right PIN closes it with true', (t) async {
      final LocalPinService s = service();
      await t.runAsync(() => s.setPin('1234'));
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
            body: Center(child: FilledButton(
              onPressed: () async => result = await askLocalPin(context, s, why: 'Because.'),
              child: const Text('go')))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Because.'), findsOneWidget);
      await type(t, '1234');
      expect(result, isTrue);
      expect(find.byKey(const Key('localPinField')), findsNothing);
    });

    testWidgets('a wrong PIN says so and stays; the field is cleared; Cancel returns false', (t) async {
      final LocalPinService s = service();
      await t.runAsync(() => s.setPin('1234'));
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
            body: Center(child: FilledButton(
              onPressed: () async => result = await askLocalPin(context, s),
              child: const Text('go')))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await type(t, '9999');
      expect(find.text('That is not your PIN.'), findsOneWidget);
      expect(result, isNull, reason: 'the dialog is still open');
      expect(fieldText(t, const Key('localPinField')), '');
      await t.tap(find.byKey(const Key('localPinCancel')));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('five wrong tries show the lockout line in the server\'s words; even the right PIN is refused', (t) async {
      final LocalPinService s = service();
      await t.runAsync(() => s.setPin('1234'));
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
            body: Center(child: FilledButton(
              onPressed: () async => result = await askLocalPin(context, s),
              child: const Text('go')))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        await type(t, '0000');
      }
      expect(find.text('Too many wrong tries. Try again in 15 minutes.'), findsOneWidget);
      await type(t, '1234');
      expect(find.text('Too many wrong tries. Try again in 15 minutes.'), findsOneWidget);
      expect(result, isNull, reason: 'the right PIN did not get in while locked');
      await t.tap(find.byKey(const Key('localPinCancel')));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('with no PIN set the gate says so and does not let anyone through', (t) async {
      final LocalPinService s = service();
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext context) => Scaffold(
            body: Center(child: FilledButton(
              onPressed: () async => result = await askLocalPin(context, s),
              child: const Text('go')))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await type(t, '1234');
      expect(find.text('No PIN is set on this device yet.'), findsOneWidget);
      expect(result, isNull);
    });
  });
}

String fieldText(WidgetTester t, Key k) => t.widget<TextField>(find.byKey(k)).controller!.text;
