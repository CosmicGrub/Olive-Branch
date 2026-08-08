// OLIVE BRANCH — retake_screen.dart tests. MASTERFILE §9.1.
//
// "Plain, actionable advice ... No jargon." This file asserts the negative
// space as much as the positive: the screen must render the gate's advice
// verbatim, and must never render the technical vocabulary that produced
// it — same "no error text" discipline pin_gate.dart's own test applies
// after a kiosk defeat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/homework_quality_gate.dart';
import 'package:olive_client/retake_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// MASTERFILE's own mandated minimum widths for a responsive audit: the
/// Fold5's cover screen and its unfolded main screen, plus a standard phone
/// width and a desktop-scale width now that Windows is a real target (§5.20).
const List<Size> kResponsiveSizes = <Size>[
  Size(344, 820), // Fold5 cover screen
  Size(673, 841), // Fold5 main screen, unfolded
  Size(390, 844), // standard phone
  Size(1100, 900), // tablet / desktop-scale, short-and-wide
];

Future<void> useSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the gate\'s advice verbatim', (t) async {
    await t.pumpWidget(wrap(RetakeScreen(
      advice: 'Hold still and try again.',
      reason: QualityFailure.tooBlurred,
      onRetry: () {})));
    expect(find.text('Hold still and try again.'), findsOneWidget);
  });

  for (final (QualityFailure reason, String advice) in <(QualityFailure, String)>[
    (QualityFailure.tooSmall, 'Move a bit closer to the page.'),
    (QualityFailure.tooBlurred, 'Hold still and try again.'),
    (QualityFailure.tooClipped, 'Try moving away from the bright light.'),
    (QualityFailure.tooSkewed, 'Line the page up straight.'),
  ]) {
    testWidgets('never leaks jargon for $reason', (t) async {
      await t.pumpWidget(wrap(RetakeScreen(advice: advice, reason: reason, onRetry: () {})));
      for (final String word in <String>[
        'blur', 'skew', 'clip', 'resolution', 'threshold', 'sharpness', 'px', 'degrees',
        'error', 'failed', 'Incorrect',
      ]) {
        expect(find.textContaining(word, findRichText: true), findsNothing,
          reason: 'unexpected jargon "$word" for $reason');
      }
    });
  }

  testWidgets('the retry button is at least 48dp and fires onRetry', (t) async {
    bool retried = false;
    await t.pumpWidget(wrap(RetakeScreen(
      advice: 'Hold still and try again.',
      reason: QualityFailure.tooBlurred,
      onRetry: () => retried = true)));
    final Size size = t.getSize(find.byKey(const Key('retakeTryAgain')));
    expect(size.height, greaterThanOrEqualTo(48));
    await t.tap(find.byKey(const Key('retakeTryAgain')));
    expect(retried, isTrue);
  });

  testWidgets('no settings affordance exists on this screen', (t) async {
    await t.pumpWidget(wrap(RetakeScreen(
      advice: 'Hold still and try again.',
      reason: QualityFailure.tooBlurred,
      onRetry: () {})));
    expect(find.byIcon(Icons.settings), findsNothing);
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (t) async {
        await useSurface(t, size);
        await t.pumpWidget(wrap(RetakeScreen(
          advice: 'Hold still and try again.',
          reason: QualityFailure.tooBlurred,
          onRetry: () {})));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
