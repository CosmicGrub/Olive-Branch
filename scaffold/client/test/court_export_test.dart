// OLIVE BRANCH — court export tests. §2.11, §16.1 #3, P8.
//
// Two layers: pure-logic tests against the ledger.ts port (authorizeExport,
// the hash chain, certify/verify — same properties packages/ledger/test
// asserts against the TS original), and widget tests against the actual
// rendered screen, in the style of invariants_test.dart — the load-bearing
// property being that RAW export never looks, anywhere, like it needs a plan.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/court_export.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('authorizeExport — §2.11 / §16.1 #3', () {
    test('raw export is always free, regardless of tier or history', () {
      final ExportAuthorization a = authorizeExport(const ExportRequest(
          kind: ExportKind.raw, courtTier: false, certifiedInLast12Months: 99));
      expect(a.ok, isTrue);
      expect(a.free, isTrue);
    });

    test('the first certified export this year is free even off Court tier', () {
      final ExportAuthorization a = authorizeExport(const ExportRequest(
          kind: ExportKind.certified, courtTier: false, certifiedInLast12Months: 0));
      expect(a.ok, isTrue);
      expect(a.free, isTrue);
    });

    test('a second certified export this year requires Court tier', () {
      final ExportAuthorization denied = authorizeExport(const ExportRequest(
          kind: ExportKind.certified, courtTier: false, certifiedInLast12Months: 1));
      expect(denied.ok, isFalse);
      expect(denied.denial, ExportDenial.tierRequired);

      final ExportAuthorization allowed = authorizeExport(const ExportRequest(
          kind: ExportKind.certified, courtTier: true, certifiedInLast12Months: 1));
      expect(allowed.ok, isTrue);
      expect(allowed.free, isFalse);
    });
  });

  group('hash chain — P8 / §16.1 #3', () {
    test('append builds a genesis-rooted chain with real, verifiable hashes', () {
      List<LogEntry> chain = <LogEntry>[];
      chain = <LogEntry>[
        ...chain,
        appendEntry(chain, childId: 'ivy', authorId: 'mom', at: 't0', body: 'first'),
      ];
      chain = <LogEntry>[
        ...chain,
        appendEntry(chain, childId: 'ivy', authorId: 'dad', at: 't1', body: 'second'),
      ];
      expect(chain[0].prevHash, genesisHash);
      expect(chain[1].prevHash, chain[0].hash);
      expect(verifyChain(chain).ok, isTrue);
    });

    test('altering an entry after the fact is caught, not silently accepted', () {
      List<LogEntry> chain = <LogEntry>[];
      chain = <LogEntry>[appendEntry(chain, childId: 'ivy', authorId: 'mom', at: 't0', body: 'first')];
      chain = <LogEntry>[
        ...chain,
        appendEntry(chain, childId: 'ivy', authorId: 'dad', at: 't1', body: 'second'),
      ];
      final LogEntry tampered = chain[0];
      final List<LogEntry> corrupted = <LogEntry>[
        LogEntry(seq: tampered.seq, childId: tampered.childId, authorId: tampered.authorId,
            at: tampered.at, body: 'edited after the fact', prevHash: tampered.prevHash, hash: tampered.hash),
        chain[1],
      ];
      final ChainVerification v = verifyChain(corrupted);
      expect(v.ok, isFalse);
      expect(v.faults.any((ChainFault f) => f.kind == ChainFaultKind.contentAltered), isTrue);
    });

    test('certify() produces a statement that changes when the chain is broken', () {
      List<LogEntry> good = <LogEntry>[];
      good = <LogEntry>[appendEntry(good, childId: 'ivy', authorId: 'mom', at: 't0', body: 'first')];
      final Attestation okAtt = certify(good, 'ivy', 'now');
      expect(okAtt.chainVerified, isTrue);
      expect(okAtt.statement, isNot(contains('FAILED')));

      final LogEntry e = good[0];
      final List<LogEntry> broken = <LogEntry>[
        LogEntry(seq: e.seq, childId: e.childId, authorId: e.authorId, at: e.at,
            body: 'altered', prevHash: e.prevHash, hash: e.hash),
      ];
      final Attestation badAtt = certify(broken, 'ivy', 'now');
      expect(badAtt.chainVerified, isFalse);
      expect(badAtt.statement, contains('FAILED'));
    });
  });

  group('planChunks — "chunked under the transfer ceiling"', () {
    test('a file under the ceiling is a single chunk', () {
      final ExportChunkPlan plan = planChunks(10 * 1024 * 1024, ceilingBytes: 25 * 1024 * 1024);
      expect(plan.chunkCount, 1);
      expect(plan.chunkSizes.single, 10 * 1024 * 1024);
    });

    test('chunk sizes always sum back to the exact total', () {
      const int ceiling = 25 * 1024 * 1024;
      for (final int total in <int>[1, ceiling - 1, ceiling, ceiling + 1, ceiling * 7 + 12345]) {
        final ExportChunkPlan plan = planChunks(total, ceilingBytes: ceiling);
        expect(plan.chunkSizes.fold<int>(0, (int a, int b) => a + b), total);
        for (final int size in plan.chunkSizes) {
          expect(size, lessThanOrEqualTo(ceiling));
          expect(size, greaterThan(0));
        }
      }
    });

    test('an empty archive produces no chunks', () {
      expect(planChunks(0).chunkCount, 0);
    });
  });

  group('CourtExportScreen — the widget itself', () {
    // A generous, bounded surface so the whole screen — both cards, the
    // manifest list, the attestation panel once generated — is genuinely
    // laid out and built by the ListView's sliver, not left off-screen where
    // "not found" would be indistinguishable from "not rendered" (same
    // reasoning emergency_card_test.dart documents for its own tall screen).
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const CourtExportScreen()));
    }

    testWidgets('raw export copy is unmistakably free — no paywall language near it',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('Raw export'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('EVERY TIER'), findsOneWidget);
      expect(find.text('EVEN AFTER CANCELLATION'), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing, reason: 'no price is ever shown on this screen');

      final Finder rawCard = find.ancestor(of: find.text('Raw export'), matching: find.byType(Card));
      expect(find.descendant(of: rawCard, matching: find.byIcon(Icons.lock_outline)), findsNothing);
      expect(find.descendant(of: rawCard, matching: find.textContaining('Upgrade')), findsNothing);
    });

    testWidgets('preparing the raw export reveals the chunk plan, no gate in the way',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('chunked under the transfer ceiling'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Prepare raw export'));
      await tester.pump();
      expect(find.textContaining('Part 1 of'), findsOneWidget);
    });

    testWidgets('certified export is free the first time, by default', (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('Included — this one is free.'), findsOneWidget);
      final Finder generate = find.widgetWithText(FilledButton, 'Generate certified export');
      final FilledButton button = tester.widget(generate);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a second certified export this year is denied without Court tier',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      // Bump "certified exports used this year" from 0 to 1 via the demo stepper.
      await tester.tap(find.byIcon(Icons.add_circle_outline).last);
      await tester.pump();
      expect(find.textContaining("already used"), findsOneWidget);
      final FilledButton button =
          tester.widget(find.widgetWithText(FilledButton, 'Generate certified export'));
      expect(button.onPressed, isNull);
    });

    testWidgets('choosing Court tier unlocks the second certified export', (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline).last);
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Court'));
      await tester.pump();
      expect(find.text('Included with Court tier.'), findsOneWidget);
      final FilledButton button =
          tester.widget(find.widgetWithText(FilledButton, 'Generate certified export'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('generating shows a verified attestation with a real hash', (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Generate certified export'));
      await tester.pump();
      expect(find.text('Chain verified'), findsOneWidget);
      expect(find.text('VERIFICATION FAILED'), findsNothing);
    });

    testWidgets('the tamper preview shows detection working, not a silent pass',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Preview: a file altered after export'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Generate certified export'));
      await tester.pump();
      expect(find.text('VERIFICATION FAILED'), findsOneWidget);
      expect(find.text('Chain verified'), findsNothing);
    });

    testWidgets('there is no edit control anywhere on this screen — P8', (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });
  });

  group('CourtExportScreen — responsive widths (phone/Fold5/tablet/desktop)', () {
    // MASTERFILE's own mandated minimums (Fold5 cover/main), a standard phone
    // width, and — now that Windows is a real target — a short-and-wide
    // desktop-scale width that also crosses this screen's own 760px
    // two-column breakpoint.
    const Map<String, Size> widths = <String, Size>{
      'Fold5 cover (344px)': Size(344, 820),
      'Fold5 main (~673x841)': Size(673, 841),
      'phone (390px)': Size(390, 844),
      'tablet/desktop (1100px)': Size(1100, 900),
    };

    for (final MapEntry<String, Size> entry in widths.entries) {
      testWidgets('renders with no overflow/layout exception at ${entry.key}',
          (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(const CourtExportScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('LiveCourtExportScreen — real network wiring', () {
    // charset=utf-8 explicit, matching the real fix in server/index.mjs /
    // packages/api/src/api.ts (found via this exact suite): without it,
    // package:http's Response constructor encodes the body as latin1 by
    // default and throws on the em dash EXPORT_DENIAL_MESSAGES actually use.
    http.Response jsonRes(Object body, int status) => http.Response(
        jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

    Map<String, dynamic> fakeAttestation({bool verified = true}) => <String, dynamic>{
          'childId': 'child-a',
          'generatedAt': '2026-08-11T00:00:00.000Z',
          'entryCount': 2,
          'firstSeq': 0,
          'lastSeq': 1,
          'headHash': 'a' * 64,
          'bundleHash': 'b' * 64,
          'chainVerified': verified,
          'statement': verified ? 'Each entry carries a SHA-256 hash...' : 'VERIFICATION FAILED.',
        };

    testWidgets('shows a loading indicator before the fetch resolves', (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return jsonRes(<String, String>{'token': 'tok'}, 200);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a real successful certified export renders the real attestation',
        (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        if (req.url.path == '/v1/children/child-a/export') {
          expect(req.url.queryParameters['kind'], 'certified');
          return jsonRes(<String, dynamic>{
            'kind': 'certified', 'free': true,
            'chain': <dynamic>[], 'attestation': fakeAttestation(),
            'bundleHash': 'c' * 64, 'exportRecordId': 'rec-1',
          }, 200);
        }
        return http.Response('not found', 404);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text('Included — this one is free.'), findsOneWidget);
      expect(find.text('Chain verified'), findsOneWidget);
      expect(find.textContaining('Live:'), findsOneWidget);
      expect(find.text('a' * 64), findsOneWidget); // the real head hash, not a demo one
    });

    testWidgets('a paid (not-free) certified export says so, not "free"',
        (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        return jsonRes(<String, dynamic>{
          'kind': 'certified', 'free': false,
          'chain': <dynamic>[], 'attestation': fakeAttestation(),
          'bundleHash': 'c' * 64, 'exportRecordId': 'rec-2',
        }, 200);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text('Included with Court tier.'), findsOneWidget);
      expect(find.text('Included — this one is free.'), findsNothing);
    });

    testWidgets('a REAL denial (annual allowance used, no Court tier) renders honestly — '
        'not a crash, not a silent success', (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        return jsonRes(<String, dynamic>{
          'error': 'annual_allowance_used',
          'message': "This year's free certified export has already been used. "
              'Court tier covers any additional ones — there is no payment flow '
              'in this build to upgrade, so a Court-tier flag has to be set by '
              'an admin, by hand, until one exists.',
        }, 403);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text('Certified export not authorized'), findsOneWidget);
      expect(find.textContaining('REASON: annual_allowance_used'), findsOneWidget);
      expect(find.textContaining("already been used"), findsOneWidget);
      // Never claims a certified export was produced when it was denied.
      expect(find.text('Chain verified'), findsNothing);
      expect(find.text('VERIFICATION FAILED'), findsNothing);
    });

    testWidgets('a REAL denial (not a guardian of this child) renders honestly',
        (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        return jsonRes(<String, dynamic>{
          'error': 'no_edge',
          'message': 'You are not a guardian of this child.',
        }, 403);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'mom', childId: 'not-her-child', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text('Certified export not authorized'), findsOneWidget);
      expect(find.textContaining('REASON: no_edge'), findsOneWidget);
    });

    testWidgets('a tampered/broken chain denial is refused, not silently exported',
        (WidgetTester tester) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        return jsonRes(<String, dynamic>{
          'error': 'chain_broken',
          'message': "This child's handover log did not verify as an unbroken "
              'chain, so no certified export was produced. Raw export is '
              'unaffected and remains free and unlimited.',
        }, 403);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text('Certified export not authorized'), findsOneWidget);
      expect(find.textContaining('REASON: chain_broken'), findsOneWidget);
      // Two widgets legitimately contain this phrase — the server's own
      // denial message AND this screen's own static reassurance footer —
      // so "at least one", not "exactly one", is the real property.
      expect(find.textContaining('Raw export is unaffected'), findsWidgets);
    });

    testWidgets('shows a retry affordance on a real network/server error, distinct from a denial',
        (WidgetTester tester) async {
      final MockClient mock =
          MockClient((http.Request req) async => jsonRes(<String, String>{'error': 'internal'}, 500));
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Certified export not authorized'), findsNothing);
    });

    testWidgets('retry re-runs the fetch and can recover from denied into ready',
        (WidgetTester tester) async {
      int attempt = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return jsonRes(<String, String>{'token': 'tok'}, 200);
        }
        attempt++;
        if (attempt == 1) {
          return jsonRes(<String, dynamic>{
            'error': 'annual_allowance_used', 'message': 'already used',
          }, 403);
        }
        return jsonRes(<String, dynamic>{
          'kind': 'certified', 'free': false,
          'chain': <dynamic>[], 'attestation': fakeAttestation(),
          'bundleHash': 'c' * 64, 'exportRecordId': 'rec-3',
        }, 200);
      });
      await tester.pumpWidget(wrap(LiveCourtExportScreen(
          baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
      await tester.pumpAndSettle();
      expect(find.text('Certified export not authorized'), findsOneWidget);

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text('Included with Court tier.'), findsOneWidget);
    });
  });
}
