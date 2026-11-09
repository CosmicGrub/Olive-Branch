// OLIVE BRANCH — the adult gate: a calm card for the child, the adult-only keypad only after a deliberate tap.
// Verified by CI, headless. MASTERFILE §8.3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/adult_gate.dart';
import 'package:olive_client/pin_gate.dart';

Widget wrap(Widget c) => MaterialApp(home: c);

void main() {
  testWidgets('the child sees only a card: no keypad, no digits, no error words, no counts', (t) async {
    await t.pumpWidget(wrap(AdultGate(digits: 4, onPin: (_) {})));
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    expect(find.byType(PinGate), findsNothing);
    expect(find.byType(TextButton), findsOneWidget, reason: 'only the quiet grown-up button');
    for (int d = 0; d <= 9; d++) {
      expect(find.text('$d'), findsNothing);
    }
    for (final String w in <String>['error', 'wrong', 'Incorrect', 'failed', 'attempt', 'try again', 'minutes', 'locked']) {
      expect(find.textContaining(w, findRichText: true), findsNothing, reason: w);
    }
    expect(find.text('A grown-up does this'), findsOneWidget);
  });

  testWidgets('the keypad opens only after the deliberate grown-up tap, and then collects the code', (t) async {
    String? got;
    await t.pumpWidget(wrap(AdultGate(digits: 4, onPin: (String p) => got = p)));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    expect(find.byType(PinGate), findsOneWidget);
    for (final String d in <String>['1', '2', '3', '4']) {
      await t.tap(find.text(d));
      await t.pump();
    }
    expect(got, '1234');
  });

  testWidgets('the keypad can go back to the card', (t) async {
    await t.pumpWidget(wrap(AdultGate(digits: 4, onPin: (_) {})));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('adultGateBack')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    expect(find.byType(PinGate), findsNothing);
  });

  testWidgets('startOpen (the grown-up already chose to be here) goes straight to the keypad', (t) async {
    await t.pumpWidget(wrap(AdultGate(digits: 4, startOpen: true, onPin: (_) {})));
    expect(find.byType(PinGate), findsOneWidget);
  });

  testWidgets('askAdultPin returns the code, and null when closed', (t) async {
    String? result = 'unset';
    await t.pumpWidget(wrap(Builder(builder: (BuildContext c) => TextButton(
        onPressed: () async => result = await askAdultPin(c, digits: 4), child: const Text('go')))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    await t.tap(find.byKey(const Key('adultGateClose')));
    await t.pumpAndSettle();
    expect(result, isNull);
  });
}
