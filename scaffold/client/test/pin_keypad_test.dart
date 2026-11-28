// OLIVE BRANCH — the ordinary PIN keypad (pin_keypad.dart): layout, dots, length rules, OK, delete, the optional scramble,
// spoken labels, light and dark, narrow screens, and that no digit is ever logged or written. MASTERFILE §8.3, §8.5.9.
// Every code typed here is an obviously fake fixture.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/pin_keypad.dart';

import 'pin_keypad_helpers.dart';

/// A random source that always answers the same way, so a test can tell a layout change from luck.
class _Fixed implements Random {
  _Fixed(this.v);
  final int v;
  @override
  int nextInt(int max) => v % max;
  @override
  bool nextBool() => v.isEven;
  @override
  double nextDouble() => 0.5;
}

void main() {
  Widget host(Widget child, {ThemeData? theme, double width = 420}) => MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
      );

  Future<void> tall(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  group('layout: the keypad every phone and tablet has', () {
    testWidgets('1 2 3 / 4 5 6 / 7 8 9 / blank 0 delete, in that order', (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
      expect(keypadDigitOrder(t), <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']);
      // Rows: three keys wide, 0 sits in the middle of the bottom row with delete to its right and nothing to its left.
      double y(String d) => t.getCenter(find.widgetWithText(TextButton, d)).dy;
      double x(String d) => t.getCenter(find.widgetWithText(TextButton, d)).dx;
      expect(y('1'), y('2'));
      expect(y('2'), y('3'));
      expect(y('4'), greaterThan(y('1')));
      expect(y('7'), greaterThan(y('4')));
      expect(y('0'), greaterThan(y('7')));
      expect(x('0'), x('2'), reason: '0 is under 8, in the middle');
      expect(x('1'), x('4'));
      final Offset del = t.getCenter(find.byKey(const Key('pinKeypadBackspace')));
      expect(del.dy, y('0'));
      expect(del.dx, x('3'), reason: 'delete is in the bottom right corner');
      expect(find.text('keypad order changes every time'), findsNothing, reason: 'no stray caption');
    });

    testWidgets('it is the same on a phone, a Fold cover (344dp, big text) and a tablet, with no overflow', (t) async {
      for (final double w in <double>[344, 390, 600, 800]) {
        for (final double scale in <double>[1.0, 2.0]) {
          await t.binding.setSurfaceSize(Size(w, 1600));
          await t.pumpWidget(MediaQuery(
              data: MediaQueryData(size: Size(w, 1600), textScaler: TextScaler.linear(scale)),
              child: host(PinKeypad(onSubmit: (_) {}), width: w)));
          expect(t.takeException(), isNull, reason: 'width $w at ${scale}x');
          expect(keypadDigitOrder(t).join(), '1234567890', reason: 'width $w at ${scale}x');
        }
      }
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('the keys are big touch targets: at least 56 logical pixels square', (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
      for (final String d in <String>['1', '5', '9', '0']) {
        final Size s = t.getSize(find.widgetWithText(TextButton, d));
        expect(s.width, greaterThanOrEqualTo(56), reason: d);
        expect(s.height, greaterThanOrEqualTo(56), reason: d);
      }
      expect(t.getSize(find.byKey(const Key('pinKeypadBackspace'))).height, greaterThanOrEqualTo(56));
      expect(t.getSize(find.byKey(const Key('pinKeypadSubmit'))).height, greaterThanOrEqualTo(56));
    });

    testWidgets('light and dark themes both draw it', (t) async {
      await tall(t);
      for (final ThemeData th in <ThemeData>[ThemeData.light(useMaterial3: true), ThemeData.dark(useMaterial3: true)]) {
        await t.pumpWidget(host(PinKeypad(onSubmit: (_) {}), theme: th));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('OK'), findsOneWidget);
        final Text zero = t.widget<Text>(find.descendant(of: find.widgetWithText(TextButton, '0'), matching: find.text('0')));
        expect(zero.style!.color, th.colorScheme.onSurface);
      }
    });
  });

  group('dots follow what was typed, in the 4 to 8 range', () {
    testWidgets('four empty dots to begin with, not eight; one fills per digit; a fifth place appears after the fourth',
        (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
      expect(pinDots(t), (total: 4, filled: 0));
      await typeOnKeypad(t, '48');
      expect(pinDots(t), (total: 4, filled: 2));
      await typeOnKeypad(t, '29');
      expect(pinDots(t), (total: 4, filled: 4));
      await typeOnKeypad(t, '7');
      expect(pinDots(t), (total: 5, filled: 5), reason: 'the row grows as the code does');
      await typeOnKeypad(t, '316');
      expect(pinDots(t), (total: 8, filled: 8));
    });

    testWidgets('a ninth digit is ignored: never more than 8', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(onSubmit: (String v) => got = v)));
      await typeOnKeypad(t, '123456789');
      expect(pinDots(t), (total: 8, filled: 8));
      await t.tap(find.byKey(const Key('pinKeypadSubmit')));
      expect(got, '12345678');
    });

    testWidgets('a fixed-length keypad (older shape) shows all its places and submits at the last digit, no OK', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(maxDigits: 4, submitAtMax: true, onSubmit: (String v) => got = v)));
      expect(find.byKey(const Key('pinKeypadSubmit')), findsNothing);
      expect(pinDots(t).total, 4);
      await typeOnKeypad(t, '482');
      expect(got, isNull);
      await typeOnKeypad(t, '9');
      expect(got, '4829');
      expect(pinDots(t).filled, 0, reason: 'cleared after the try');
    });
  });

  group('OK, delete and length rules', () {
    testWidgets('OK is off until four digits are in, then on; three digits never submit', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(onSubmit: (String v) => got = v)));
      FilledButton ok() => t.widget<FilledButton>(find.byKey(const Key('pinKeypadSubmit')));
      expect(ok().onPressed, isNull);
      await typeOnKeypad(t, '482');
      expect(ok().onPressed, isNull);
      await t.tap(find.byKey(const Key('pinKeypadSubmit')), warnIfMissed: false);
      expect(got, isNull);
      await typeOnKeypad(t, '9');
      expect(ok().onPressed, isNotNull);
      await t.tap(find.byKey(const Key('pinKeypadSubmit')));
      expect(got, '4829');
    });

    testWidgets('a code with zeros is typed and handed over exactly', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(onSubmit: (String v) => got = v)));
      await typeOnKeypad(t, '1020987');
      await t.tap(find.byKey(const Key('pinKeypadSubmit')));
      expect(got, '1020987');
    });

    testWidgets('after OK the keypad is empty again; nothing is left typed', (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
      await typeOnKeypad(t, '4829');
      await t.tap(find.byKey(const Key('pinKeypadSubmit')));
      await t.pump();
      expect(pinDots(t), (total: 4, filled: 0));
      expect(t.widget<FilledButton>(find.byKey(const Key('pinKeypadSubmit'))).onPressed, isNull);
    });

    testWidgets('delete removes one digit; on an empty pad it does nothing; press and hold clears all', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(onSubmit: (String v) => got = v)));
      await t.tap(find.byKey(const Key('pinKeypadBackspace')), warnIfMissed: false);
      expect(pinDots(t).filled, 0);
      await typeOnKeypad(t, '4829');
      await t.tap(find.byKey(const Key('pinKeypadBackspace')));
      await t.pump();
      expect(pinDots(t).filled, 3);
      await typeOnKeypad(t, '1');
      await t.tap(find.byKey(const Key('pinKeypadSubmit')));
      expect(got, '4821', reason: 'the deleted 9 is gone');
      await typeOnKeypad(t, '4829');
      await t.longPress(find.byKey(const Key('pinKeypadBackspace')));
      await t.pump();
      expect(pinDots(t).filled, 0);
    });

    testWidgets('a hardware keyboard works too: digits, backspace, enter', (t) async {
      await tall(t);
      String? got;
      await t.pumpWidget(host(PinKeypad(onSubmit: (String v) => got = v)));
      await t.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
      await t.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
      await t.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await t.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(got, '4829');
    });
  });

  group('the optional scramble', () {
    testWidgets('off is the default and is the plain order every time', (t) async {
      await tall(t);
      for (int i = 0; i < 6; i++) {
        await t.pumpWidget(host(PinKeypad(key: ValueKey<int>(i), onSubmit: (_) {})));
        expect(keypadDigitOrder(t).join(), '1234567890');
      }
    });

    testWidgets('on: the digits move, every digit is still there exactly once, and it changes after a try', (t) async {
      await tall(t);
      final Set<String> orders = <String>{};
      for (int i = 0; i < 12; i++) {
        await t.pumpWidget(host(PinKeypad(key: ValueKey<int>(i), scramble: true, random: Random(i), onSubmit: (_) {})));
        final List<String> o = keypadDigitOrder(t);
        expect(List<String>.of(o)..sort(), <String>['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);
        orders.add(o.join());
      }
      expect(orders.length, greaterThan(1), reason: 'twelve identical layouts would mean no scramble');
      expect(orders.contains('1234567890') && orders.length == 1, isFalse);

      // A new layout after every try.
      await t.pumpWidget(host(PinKeypad(key: const ValueKey<String>('again'), scramble: true, onSubmit: (_) {})));
      final List<String> seen = <String>[];
      for (int i = 0; i < 8; i++) {
        seen.add(keypadDigitOrder(t).join());
        // Type four of whatever digits are in the first four slots (the labels follow the layout).
        for (final String d in seen.last.substring(0, 4).split('')) {
          await t.tap(find.widgetWithText(TextButton, d).first);
          await t.pump();
        }
        await t.tap(find.byKey(const Key('pinKeypadSubmit')));
        await t.pump();
      }
      expect(seen.toSet().length, greaterThan(1), reason: 'the layout changes between tries');
    });

    testWidgets('turning it on or off while open re-lays the keys', (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(key: const ValueKey<String>('k'), scramble: true, random: _Fixed(3), onSubmit: (_) {})));
      expect(keypadDigitOrder(t).join(), isNot('1234567890'));
      await t.pumpWidget(host(PinKeypad(key: const ValueKey<String>('k'), onSubmit: (_) {})));
      expect(keypadDigitOrder(t).join(), '1234567890');
    });

    test('the shuffle comes from the platform CSPRNG, never a seeded or clock source', () {
      final String src = File('lib/pin_keypad.dart').readAsStringSync();
      expect(src, contains('Random.secure()'));
      expect(RegExp(r'Random\(\s*[^)\s]').hasMatch(src), isFalse, reason: 'no seeded Random');
      expect(src.contains('DateTime'), isFalse, reason: 'no clock-derived order');
    });
  });

  group('spoken labels', () {
    testWidgets('every key says what it is; the dots say how many, never which', (t) async {
      await tall(t);
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
      for (final String d in <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        expect(find.bySemanticsLabel(d), findsWidgets, reason: 'key $d is spoken');
      }
      expect(find.bySemanticsLabel('Delete last digit'), findsOneWidget);
      expect(find.bySemanticsLabel('No digits entered'), findsOneWidget);
      await typeOnKeypad(t, '4829');
      expect(find.bySemanticsLabel('4 digits entered'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('4829')), findsNothing, reason: 'the code itself is never announced');
      h.dispose();
    });

    testWidgets('the OK button carries its own words, and can be renamed', (t) async {
      await tall(t);
      await t.pumpWidget(host(PinKeypad(submitLabel: 'Save PIN', onSubmit: (_) {})));
      expect(find.text('Save PIN'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });
  });

  group('no digit is ever logged or written', () {
    testWidgets('typing, deleting and submitting prints and logs nothing', (t) async {
      await tall(t);
      final List<String> out = <String>[];
      final void Function(String?, {int? wrapWidth}) old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => out.add(m ?? '');
      try {
        await runZoned(() async {
          await t.pumpWidget(host(PinKeypad(onSubmit: (_) {})));
          await typeOnKeypad(t, '4829');
          await t.tap(find.byKey(const Key('pinKeypadBackspace')));
          await typeOnKeypad(t, '1');
          await t.tap(find.byKey(const Key('pinKeypadSubmit')));
          await t.pump();
        }, zoneSpecification: ZoneSpecification(print: (Zone self, ZoneDelegate p, Zone z, String line) => out.add(line)));
      } finally {
        debugPrint = old;
      }
      expect(out.where((String l) => RegExp(r'\d').hasMatch(l)), isEmpty, reason: 'nothing with a digit was printed: $out');
    });

    test('the keypad source has no logger, no file, no store, no clipboard and no network', () {
      final String src = File('lib/pin_keypad.dart')
          .readAsStringSync()
          .split('\n')
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final String bad in <String>[
        'print(', 'debugPrint', 'developer.log', 'dart:io', 'dart:developer', 'LocalStore', 'LocalNamespace', 'SharedPreferences',
        'Clipboard', 'http', 'File(', 'FlutterSecureStorage',
      ]) {
        expect(src.contains(bad), isFalse, reason: 'pin_keypad.dart must not use $bad');
      }
    });

    test('the screens that carry a PIN pad take no store for the digits: only the PIN service hashes it', () {
      final String gate = File('lib/pin_gate.dart').readAsStringSync();
      expect(gate.contains('LocalStore'), isFalse);
      expect(gate.contains('SharedPreferences'), isFalse);
    });
  });
}
