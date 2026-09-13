// OLIVE BRANCH — kiosk shell widget tests. §5.20, §8.3.
//
// First dedicated coverage for this file (previously exercised only
// indirectly). Focused on what this pass actually changed: the guardian
// escalation trigger/flow/exit — PIN re-entry, defeat handling, and
// break-glass are lock_controller.dart's own pure-function concern, already
// covered in lock_controller_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_escalation_screen.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:olive_client/kiosk_shell.dart';
import 'package:olive_client/pin_gate.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  const methodChannel = KioskChannel.methodChannel;
  const eventChannel = KioskChannel.eventChannel;

  setUp(() {
    // No native kiosk bridge under `flutter test` — start()/mode()/stop()
    // all degrade to their documented no-handler fallback unless a test
    // below overrides one specifically. The event channel needs SOME
    // handler registered or listening throws — an empty stream is the
    // honest "no native events arrive" case every test but the explicit
    // defeat-handling ones (lock_controller_test.dart's own territory) wants.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, _NoOpStreamHandler());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  Future<bool> alwaysTruePin(String pin) async => true;
  Future<bool> alwaysFalsePin(String pin) async => false;
  Future<bool> alwaysTrueBiometric() async => true;
  Future<bool> alwaysFalseBiometric() async => false;

  group('the escalation trigger — present but unobtrusive on the locked child surface', () {
    testWidgets('renders over the child surface, and the child surface itself is untouched',
        (t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysTruePin, verifyBiometric: alwaysTrueBiometric,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      expect(find.text('child home'), findsOneWidget);
      expect(find.byKey(const Key('guardianEscalationTrigger')), findsOneWidget);
    });
  });

  group('escalation — PIN AND biometric, §8.3', () {
    testWidgets('correct PIN and biometric lands on GuardianEscalationScreen', (t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysTruePin, verifyBiometric: alwaysTrueBiometric,
        childName: 'Ivy', child: const Text('child home'),
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      expect(find.byType(PinGate), findsOneWidget);

      for (final d in const [1, 1, 1, 1]) {
        await t.tap(find.text('$d').first);
        await t.pump();
      }
      await t.pumpAndSettle();

      expect(find.byType(GuardianEscalationScreen), findsOneWidget);
      expect(find.textContaining('Ivy'), findsOneWidget);
      expect(find.byKey(const Key('exitKioskButton')), findsOneWidget);
    });

    testWidgets('a wrong PIN never escalates, and the child surface is what shows again',
        (t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysFalsePin, verifyBiometric: alwaysTrueBiometric,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      for (final d in const [1, 1, 1, 1]) {
        await t.tap(find.text('$d').first);
        await t.pump();
      }
      // Deliberately NOT pumpAndSettle() here: the SnackBar's own 2-second
      // display duration would run to completion (and dismiss itself) before
      // settling, so this catches it still on screen instead. A single pump
      // lets the async verify/escalate chain and the SnackBar's entrance
      // animation both start.
      await t.pump();
      await t.pump();

      expect(find.byType(GuardianEscalationScreen), findsNothing);
      expect(find.text('child home'), findsOneWidget);
      expect(find.textContaining("Couldn't verify"), findsOneWidget);
    });

    testWidgets('a right PIN but a failed biometric never escalates either — PIN alone '
        'is not enough', (t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysTruePin, verifyBiometric: alwaysFalseBiometric,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      for (final d in const [1, 1, 1, 1]) {
        await t.tap(find.text('$d').first);
        await t.pump();
      }
      await t.pumpAndSettle();

      expect(find.byType(GuardianEscalationScreen), findsNothing);
      expect(find.text('child home'), findsOneWidget);
    });

    testWidgets('the denial message never says which factor failed — the child is watching '
        '(§8.3)', (t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysTruePin, verifyBiometric: alwaysFalseBiometric,
        child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      for (final d in const [1, 1, 1, 1]) {
        await t.tap(find.text('$d').first);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.textContaining('pin'), findsNothing);
      expect(find.textContaining('biometric'), findsNothing);
      expect(find.textContaining('PIN'), findsNothing);
    });
  });

  group('exiting kiosk mode — the one real action on GuardianEscalationScreen', () {
    testWidgets('calls the native stop method and returns to a real, unlocked child surface',
        (t) async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == KioskChannel.mStop) seen = call;
        return null;
      });

      await t.pumpWidget(wrap(KioskShell(
        verifyPin: alwaysTruePin, verifyBiometric: alwaysTrueBiometric,
        channel: KioskChannel(), child: const Text('child home'),
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
      await t.pumpAndSettle();
      for (final d in const [1, 1, 1, 1]) {
        await t.tap(find.text('$d').first);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.byType(GuardianEscalationScreen), findsOneWidget);

      await t.tap(find.byKey(const Key('exitKioskButton')));
      await t.pumpAndSettle();

      expect(seen, isNotNull, reason: 'KioskChannel.stop() should have been called natively');
      expect(find.byType(GuardianEscalationScreen), findsNothing);
      expect(find.text('child home'), findsOneWidget);
    });
  });
}

class _NoOpStreamHandler extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}
  @override
  void onCancel(Object? arguments) {}
}
