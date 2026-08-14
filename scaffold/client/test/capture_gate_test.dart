// OLIVE BRANCH — capture_gate.dart tests. MASTERFILE §9.1, §20.2b.
//
// Asserts the screen routes on the gate's own verdict rather than inventing
// any of its own pass/fail logic, and that a failing photo never surfaces
// gate jargon (that is retake_screen_test.dart's job to check more fully;
// this file only checks the hand-off is clean). The "U real path" group
// below is new: it proves the REAL camera+network path (baseUrl/childId/
// sessionToken supplied, simulateCapture NOT supplied) actually POSTs a
// photo and renders the server's own response, using an injected
// [MockClient] and a fake [CaptureGateScreen.takePhoto] rather than a real
// device camera or a running server — the same injection pattern
// child_home_live_test.dart already uses for OliveApi.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  testWidgets('a passing simulated photo calls onCaptured and pops with success', (t) async {
    HomeworkCaptureOutcome? captured;
    await t.pumpWidget(harness(CaptureGateScreen(
      simulateCapture: (attempt) => _passing,
      onCaptured: (o) => captured = o,
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(CaptureGateScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('shutterButton')));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();

    expect(captured, isNotNull);
    // The simulated path never has a real server response to carry.
    expect(captured!.problems, isNull);
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

  group('U real path — camera + POST to /v1/children/:childId/homework/capture', () {
    testWidgets('POSTs the taken photo and pops with the server\'s own real problems', (t) async {
      HomeworkCaptureOutcome? captured;
      Uri? seenUrl;
      Map<String, dynamic>? sentBody;
      final mock = MockClient((req) async {
        seenUrl = req.url;
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({
          'ok': true,
          'deskewedBy': 0,
          'rawText': '12 + 27 = ____',
          'problems': [
            {'text': '12 + 27 = ____', 'hint': 'Start at the first number and count on.',
              'hintRefused': false},
          ],
        }), 200);
      });

      await t.pumpWidget(harness(CaptureGateScreen(
        baseUrl: 'http://test.local',
        childId: 'child-1',
        sessionToken: 'tok-1',
        httpClient: mock,
        takePhoto: () async => Uint8List.fromList(<int>[1, 2, 3]),
        onCaptured: (o) => captured = o,
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('shutterButton')));
      await t.pumpAndSettle();

      expect(seenUrl.toString(), 'http://test.local/v1/children/child-1/homework/capture');
      expect(sentBody!['image'], base64Encode(<int>[1, 2, 3]));
      expect(captured, isNotNull);
      expect(captured!.problems, isNotNull, reason: 'the real path always carries a problem list');
      expect(captured!.problems!.single.text, '12 + 27 = ____');
      expect(captured!.problems!.single.hint, 'Start at the first number and count on.');
      expect(find.byType(CaptureGateScreen), findsNothing);
      expect(find.byType(RetakeScreen), findsNothing);
    });

    testWidgets('a server-side gate refusal routes to RetakeScreen with ITS OWN advice', (t) async {
      final mock = MockClient((req) async => http.Response(jsonEncode({
        'ok': false, 'reason': 'too_blurred', 'advice': 'Hold still and try again.',
      }), 422));

      await t.pumpWidget(harness(CaptureGateScreen(
        baseUrl: 'http://test.local',
        childId: 'child-1',
        sessionToken: 'tok-1',
        httpClient: mock,
        takePhoto: () async => Uint8List.fromList(<int>[1, 2, 3]),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('shutterButton')));
      await t.pumpAndSettle();

      expect(find.byType(RetakeScreen), findsOneWidget);
      // The server's own advice, verbatim — this screen invents no wording.
      expect(find.text('Hold still and try again.'), findsOneWidget);
    });

    testWidgets('the real path is honestly disclosed, not labelled as the simulated demo', (t) async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'ok': false, 'reason': 'too_blurred', 'advice': 'x'}), 422));
      await t.pumpWidget(harness(CaptureGateScreen(
        baseUrl: 'http://test.local', childId: 'child-1', sessionToken: 'tok-1',
        httpClient: mock,
        takePhoto: () async => Uint8List.fromList(<int>[1, 2, 3]),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.textContaining('sent to the server for real'), findsOneWidget);
      expect(find.textContaining('simulates the photo'), findsNothing);
    });

    testWidgets('a network failure surfaces a plain error, never a fabricated verdict', (t) async {
      final mock = MockClient((req) async => throw Exception('connection refused'));
      await t.pumpWidget(harness(CaptureGateScreen(
        baseUrl: 'http://test.local', childId: 'child-1', sessionToken: 'tok-1',
        httpClient: mock,
        takePhoto: () async => Uint8List.fromList(<int>[1, 2, 3]),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('shutterButton')));
      await t.pumpAndSettle();

      // Neither a fake pass nor a fake gate-failure screen — a real network
      // error, said plainly, still on the capture screen so she can retry.
      expect(find.byType(RetakeScreen), findsNothing);
      expect(find.byType(CaptureGateScreen), findsOneWidget);
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    });

    testWidgets('with no baseUrl/childId/sessionToken configured, falls back to the simulated demo',
        (t) async {
      // No config, no simulateCapture override -- capture_gate.dart's file
      // header documents this as the honest fallback for a call site that
      // hasn't been wired to a live session yet (e.g. the offline demo
      // build), not a crash on a missing baseUrl.
      await t.pumpWidget(harness(const CaptureGateScreen()));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.textContaining('simulates the photo'), findsOneWidget);

      await t.tap(find.byKey(const Key('shutterButton')));
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      // demoCaptureSequence[0] is deliberately too-blurred.
      expect(find.byType(RetakeScreen), findsOneWidget);
      expect(find.text('Hold still and try again.'), findsOneWidget);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      final String label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('the viewfinder renders without overflow at $label', (t) async {
        await useSurface(t, size);
        await t.pumpWidget(harness(CaptureGateScreen(simulateCapture: (a) => _passing)));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });

      testWidgets('the checking state renders without overflow at $label', (t) async {
        await useSurface(t, size);
        await t.pumpWidget(harness(CaptureGateScreen(simulateCapture: (a) => _passing)));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('shutterButton')));
        await t.pump(); // mid-check, spinner visible
        expect(t.takeException(), isNull);
        await t.pumpAndSettle(const Duration(milliseconds: 600));
      });
    }
  });
}
