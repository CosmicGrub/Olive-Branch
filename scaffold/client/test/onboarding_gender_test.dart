// OLIVE BRANCH — onboarding_gender.dart / onboarding_logic.dart (acceptGender)
// tests. Onboarding & Guardian Access sub-project 1 (docs/superpowers/specs/
// 2026-09-12-onboarding-identity-pin-design.md). §8.5.
//
// Mirrors onboarding_age_test.dart's own depth for the equivalent
// tap-and-continue shape, plus a live-wiring group (mirroring
// letters_screen_test.dart's own MockClient pattern) for the one thing this
// screen does that onboarding_age.dart never has: a real tap genuinely
// persists, via a real PUT, and a Skip never does.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/onboarding_gender.dart';
import 'package:olive_client/onboarding_logic.dart';

void main() {
  Future<void> pump(WidgetTester tester, ValueChanged<GenderStep> onContinue,
      {String? baseUrl, String? sessionToken, http.Client? httpClient}) async {
    await tester.pumpWidget(MaterialApp(home: ObGenderScreen(
      onContinue: onContinue,
      childId: 'child-a', baseUrl: baseUrl, sessionToken: sessionToken,
      httpClient: httpClient)));
  }

  group('acceptGender — pure logic', () {
    test('a real tap is kept, never skipped', () {
      final boy = acceptGender('boy');
      expect(boy.selected, 'boy');
      expect(boy.skipped, isFalse);

      final girl = acceptGender('girl');
      expect(girl.selected, 'girl');
      expect(girl.skipped, isFalse);
    });

    test('no tap (Skip) is a supported, non-trapping outcome', () {
      final step = acceptGender(null);
      expect(step.skipped, isTrue);
      expect(step.selected, isNull);
    });

    test('anything other than the two real wire values is treated as a skip, '
        'never a fabricated third value', () {
      final step = acceptGender('nonbinary-typo');
      expect(step.skipped, isTrue);
      expect(step.selected, isNull);
    });
  });

  testWidgets('renders Boy, Girl, and an explicit Skip — never a forced choice',
      (tester) async {
    await pump(tester, (_) {});
    expect(find.text('Boy'), findsOneWidget);
    expect(find.text('Girl'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('tapping Girl and continuing reports a real, non-skipped step',
      (tester) async {
    GenderStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Girl'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(got!.selected, 'girl');
    expect(got!.skipped, isFalse);
  });

  testWidgets('skip button reports a skipped step, never trapping her here',
      (tester) async {
    GenderStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(got!.skipped, isTrue);
    expect(got!.selected, isNull);
  });

  testWidgets('continuing with no tap at all is the same honest skip as the '
      'explicit Skip link', (tester) async {
    GenderStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(got!.skipped, isTrue);
  });

  testWidgets('no settings affordance and no guardian-authority path exists here',
      (tester) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
    expect(find.textContaining('guardian'), findsNothing);
    expect(find.textContaining('grown-up'), findsNothing);
  });

  testWidgets('every tappable choice tile is at least 48dp on its shortest side',
      (tester) async {
    await pump(tester, (_) {});
    final tileFinder = find.ancestor(of: find.text('Boy'), matching: find.byType(InkWell)).first;
    final tileSize = tester.getSize(tileFinder);
    expect(tileSize.width, greaterThanOrEqualTo(48));
    expect(tileSize.height, greaterThanOrEqualTo(48));
  });

  group('live wiring — the real profile route (server/routes.mjs, '
      'packages/db/src/pool.ts setChildGender)', () {
    testWidgets('a real tap PUTs the real route with the real gender, and only '
        'once', (tester) async {
      final List<http.Request> puts = <http.Request>[];
      final mock = MockClient((req) async {
        if (req.method == 'PUT' && req.url.path.endsWith('/profile')) {
          puts.add(req);
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('not found', 404);
      });
      GenderStep? got;
      await pump(tester, (s) => got = s,
        baseUrl: 'http://api.test', sessionToken: 'tok', httpClient: mock);
      await tester.tap(find.text('Boy'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(puts, hasLength(1));
      expect(puts.single.url.path, '/v1/children/child-a/profile');
      expect(jsonDecode(puts.single.body), {'gender': 'boy'});
      expect(got!.selected, 'boy');
    });

    testWidgets('Skip never calls the network at all, even when live-wired',
        (tester) async {
      var called = false;
      final mock = MockClient((req) async { called = true; return http.Response('not found', 404); });
      GenderStep? got;
      await pump(tester, (s) => got = s,
        baseUrl: 'http://api.test', sessionToken: 'tok', httpClient: mock);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(called, isFalse, reason: 'a skip must never write a fabricated row');
      expect(got!.skipped, isTrue);
    });

    testWidgets('continuing with no tap (live-wired) also never calls the '
        'network — the same honest skip as the explicit Skip link',
        (tester) async {
      var called = false;
      final mock = MockClient((req) async { called = true; return http.Response('not found', 404); });
      GenderStep? got;
      await pump(tester, (s) => got = s,
        baseUrl: 'http://api.test', sessionToken: 'tok', httpClient: mock);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(got!.skipped, isTrue);
    });

    testWidgets('a failed write is swallowed, not shown, and never traps her '
        'on this screen', (tester) async {
      final mock = MockClient((req) async => http.Response('boom', 500));
      GenderStep? got;
      await pump(tester, (s) => got = s,
        baseUrl: 'http://api.test', sessionToken: 'tok', httpClient: mock);
      await tester.tap(find.text('Girl'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(got!.selected, 'girl', reason: 'she still advances even though the write failed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('without live wiring (baseUrl/sessionToken absent), a real tap '
        'still advances with no network attempted', (tester) async {
      GenderStep? got;
      await pump(tester, (s) => got = s);
      await tester.tap(find.text('Boy'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(got!.selected, 'boy');
    });
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width — the identical set onboarding_age_test.dart
    // already audits.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: ObGenderScreen(onContinue: (_) {})));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
