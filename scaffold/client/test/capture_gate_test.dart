// OLIVE BRANCH — capture_gate.dart tests. MASTERFILE §9.1.
//
// Asserts the screen routes on the gate's own verdict rather than inventing
// any of its own pass/fail logic, and that a failing photo never surfaces
// gate jargon (that is retake_screen_test.dart's job to check more fully;
// this file only checks the hand-off is clean).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/capture_gate.dart';
import 'package:olive_client/homework_quality_gate.dart';
import 'package:olive_client/retake_screen.dart';

const ImageStats _passing =
    ImageStats(widthPx: 1200, heightPx: 800, sharpness: 400, clipping: 0.05, skewDegrees: 0);
const ImageStats _blurred =
    ImageStats(widthPx: 1200, heightPx: 800, sharpness: 20, clipping: 0.05, skewDegrees: 0);

/// Pushes the screen from a real "opener" page rather than as MaterialApp's
/// sole route, so Navigator.pop(true) on success has somewhere to land —
/// matching how homework_screen.dart actually uses this widget.
Widget harness(Widget screen) => MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'))),
      )),
    );

void main() {
  testWidgets('a passing simulated photo calls onCaptured and pops with success', (t) async {
    ImageStats? captured;
    await t.pumpWidget(harness(CaptureGateScreen(
      simulateCapture: (attempt) => _passing,
      onCaptured: (s) => captured = s,
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(CaptureGateScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('shutterButton')));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();

    expect(captured, isNotNull);
    expect(find.byType(CaptureGateScreen), findsNothing);
    expect(find.byType(RetakeScreen), findsNothing);
  });

  testWidgets('a failing simulated photo routes to RetakeScreen with the gate\'s own advice', (t) async {
    await t.pumpWidget(harness(CaptureGateScreen(simulateCapture: (attempt) => _blurred)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('shutterButton')));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();

    expect(find.byType(RetakeScreen), findsOneWidget);
    expect(find.text('Hold still and try again.'), findsOneWidget);
  });

  testWidgets('retrying from RetakeScreen returns to the capture gate', (t) async {
    int attempt = 0;
    await t.pumpWidget(harness(CaptureGateScreen(
      simulateCapture: (a) { attempt = a; return _blurred; },
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('shutterButton')));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.byType(RetakeScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();

    expect(find.byType(CaptureGateScreen), findsOneWidget);
    expect(attempt, 0, reason: 'the first attempt was recorded before retry');
  });

  testWidgets('the shutter button is at least 48dp', (t) async {
    await t.pumpWidget(harness(CaptureGateScreen(simulateCapture: (a) => _passing)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final Size size = t.getSize(find.byKey(const Key('shutterButton')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('this preview build honestly discloses the capture is simulated', (t) async {
    await t.pumpWidget(harness(CaptureGateScreen(simulateCapture: (a) => _passing)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.textContaining('simulates the photo'), findsOneWidget);
  });
}
