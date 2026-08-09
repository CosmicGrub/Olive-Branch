// OLIVE BRANCH — court export tests. §2.11, §16.1 #3, P8.
//
// Two layers: pure-logic tests against the ledger.ts port (authorizeExport,
// the hash chain, certify/verify — same properties packages/ledger/test
// asserts against the TS original), and widget tests against the actual
// rendered screen, in the style of invariants_test.dart — the load-bearing
// property being that RAW export never looks, anywhere, like it needs a plan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
