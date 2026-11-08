// OLIVE BRANCH — local_pin_screens.dart tests: choosing the local PIN and being asked for it.
// No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.9.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_screens.dart';

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

  group('the setup form', () {
    Future<void> pumpForm(WidgetTester t, LocalPinService s, VoidCallback onSaved) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: LocalPinSetupForm(service: s, onSaved: onSaved)))));
    }

    testWidgets('a short PIN is refused in the account PIN\'s own words', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await t.enterText(find.byKey(const Key('localPinNew')), '12');
      await t.enterText(find.byKey(const Key('localPinConfirm')), '12');
      await t.tap(find.byKey(const Key('localPinSave')));
      await t.pump();
      expect(find.text('Enter a 4-8 digit PIN.'), findsOneWidget);
      expect(saved, isFalse);
      expect(await s.isSet(), isFalse);
    });

    testWidgets('two different PINs are refused', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await pumpForm(t, s, () => saved = true);
      await t.enterText(find.byKey(const Key('localPinNew')), '1234');
      await t.enterText(find.byKey(const Key('localPinConfirm')), '1235');
      await t.tap(find.byKey(const Key('localPinSave')));
      await t.pump();
      expect(find.text("The two PINs don't match."), findsOneWidget);
      expect(saved, isFalse);
      expect(await s.isSet(), isFalse);
    });

    testWidgets('letters cannot be typed into the PIN field', (t) async {
      await pumpForm(t, service(), () {});
      await t.enterText(find.byKey(const Key('localPinNew')), 'ab12cd34');
      expect(fieldText(t, const Key('localPinNew')), '1234');
    });

    testWidgets('a good PIN is stored (as a hash), the fields are cleared, and onSaved fires', (t) async {
      bool saved = false;
      final LocalPinService s = service();
      await t.runAsync(() async {
        await pumpForm(t, s, () => saved = true);
        await t.enterText(find.byKey(const Key('localPinNew')), '4821');
        await t.enterText(find.byKey(const Key('localPinConfirm')), '4821');
        await t.tap(find.byKey(const Key('localPinSave')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(saved, isTrue);
      expect(await t.runAsync(s.isSet), isTrue);
      expect(fieldText(t, const Key('localPinNew')), '');
      expect(find.byKey(const Key('localPinError')), findsNothing);
    });

    testWidgets('a store that cannot be written says so plainly and does NOT call onSaved', (t) async {
      bool saved = false;
      final LocalPinService s = LocalPinService(_FailingRepo(), iterations: 500);
      await t.runAsync(() async {
        await pumpForm(t, s, () => saved = true);
        await t.enterText(find.byKey(const Key('localPinNew')), '4821');
        await t.enterText(find.byKey(const Key('localPinConfirm')), '4821');
        await t.tap(find.byKey(const Key('localPinSave')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(saved, isFalse);
      expect(find.text('Could not keep your PIN on this device. Please try again.'), findsOneWidget);
      expect(find.textContaining('disk full'), findsNothing, reason: 'no raw error text');
    });
  });

  group('the setup screen (the exit from the offline server-PIN trap)', () {
    testWidgets('says it is for this device only and works with no connection; saving continues', (t) async {
      bool done = false;
      final LocalPinService s = service();
      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(home: LocalPinSetupScreen(service: s, onDone: () => done = true)));
        expect(find.text('Choose a PIN for this device'), findsOneWidget);
        expect(find.textContaining('only for this device'), findsOneWidget);
        expect(find.textContaining('works with no connection'), findsOneWidget);
        await t.enterText(find.byKey(const Key('localPinNew')), '2468');
        await t.enterText(find.byKey(const Key('localPinConfirm')), '2468');
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
