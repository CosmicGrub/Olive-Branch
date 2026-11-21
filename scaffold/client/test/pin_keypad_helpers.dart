// OLIVE BRANCH — test helper: type a code on the ordinary keypad (pin_keypad.dart) by tapping its keys.
// The codes used in tests are obviously fake fixtures (4829, 2580 ...), never a real PIN.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps each digit of [digits] on the keypad currently on screen.
Future<void> typeOnKeypad(WidgetTester t, String digits) async {
  for (final String d in digits.split('')) {
    await t.tap(find.widgetWithText(TextButton, d).first);
    await t.pump();
  }
}

/// The digits as the keypad lays them out, left to right then top to bottom (the ten digit keys only).
List<String> keypadDigitOrder(WidgetTester t) => t
    .widgetList<Text>(find.descendant(of: find.byType(TextButton), matching: find.byType(Text)))
    .map((Text w) => w.data!)
    .toList();

/// How many dots the keypad shows, and how many of them are filled (the digits typed so far).
({int total, int filled}) pinDots(WidgetTester t) {
  final Iterable<Container> dots = t
      .widgetList<Container>(find.byWidgetPredicate((Widget w) => w is Container && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('pinDot')));
  int filled = 0;
  for (final Container c in dots) {
    final BoxDecoration d = c.decoration! as BoxDecoration;
    if (d.color != null && d.color != Colors.transparent) filled++;
  }
  return (total: dots.length, filled: filled);
}
