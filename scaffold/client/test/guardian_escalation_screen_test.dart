// OLIVE BRANCH — guardian escalation screen tests. §5.20, §8.3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_escalation_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('GuardianEscalationScreen', () {
    testWidgets('states verification plainly, names the real child, and offers '
        'exactly one real action', (t) async {
      await t.pumpWidget(wrap(GuardianEscalationScreen(
        escalatedUntil: DateTime.now().add(const Duration(minutes: 15)),
        onExitKiosk: () {},
        childName: 'Wren',
      )));
      expect(find.textContaining('PIN and biometric'), findsOneWidget);
      expect(find.textContaining('Wren'), findsOneWidget);
      expect(find.byKey(const Key('exitKioskButton')), findsOneWidget);
      expect(find.text('Exit kiosk mode'), findsOneWidget);
    });

    testWidgets('tapping exit calls the real callback exactly once', (t) async {
      var calls = 0;
      await t.pumpWidget(wrap(GuardianEscalationScreen(
        escalatedUntil: DateTime.now().add(const Duration(minutes: 15)),
        onExitKiosk: () => calls++,
      )));
      await t.tap(find.byKey(const Key('exitKioskButton')));
      await t.pump();
      expect(calls, 1);
    });

    testWidgets('handles a null expiry without crashing — the type only allows it '
        'because it is threaded through, canRender already requires a live one', (t) async {
      await t.pumpWidget(wrap(GuardianEscalationScreen(
        escalatedUntil: null,
        onExitKiosk: () {},
      )));
      expect(t.takeException(), isNull);
      expect(find.textContaining('Verified with PIN and biometric'), findsOneWidget);
    });

    testWidgets('defaults childName sensibly when not supplied', (t) async {
      await t.pumpWidget(wrap(GuardianEscalationScreen(
        escalatedUntil: DateTime.now().add(const Duration(minutes: 15)),
        onExitKiosk: () {},
      )));
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('exitKioskButton')), findsOneWidget);
    });

    group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
      for (final MapEntry<String, Size> entry in const <String, Size>{
        'Fold5 cover (344 CSS px)': Size(344, 882),
        'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
        'a standard phone (~390 CSS px)': Size(390, 844),
        'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
      }.entries) {
        testWidgets('renders without overflow at ${entry.key}', (t) async {
          await t.binding.setSurfaceSize(entry.value);
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(wrap(GuardianEscalationScreen(
            escalatedUntil: DateTime.now().add(const Duration(minutes: 15)),
            onExitKiosk: () {},
            childName: 'Ivy',
          )));
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    });
  });
}
