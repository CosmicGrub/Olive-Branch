// OLIVE BRANCH — expenses screen tests. P6.
//
// This is the single most safety-critical test file in this batch. P6 says
// "any financial or expense surface visible to a child role" is prohibited
// by design, and the group brief calls this screen out as needing to be
// PROVABLY unreachable from a child role — so every assertion here checks
// something real, not something assumed:
//   1. child_home.dart's actual source text never mentions ExpensesScreen —
//      read from disk, not inferred from "well, nobody wired it up".
//   2. Even handed a child viewerRole directly, the widget constructs and
//      renders zero financial content — no dollar figures, no ledger, no
//      approval actions, nothing to scrape even by a routing mistake.
//   3. inboxVisibleTo(), the ported §12.7 guard, agrees.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/expenses_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('expenses screen — P6', () {
    test('child_home.dart never references ExpensesScreen, on disk, today', () {
      // Walk up from the test file to find lib/child_home.dart regardless of
      // the working directory `flutter test` is invoked from.
      Directory dir = Directory.current;
      File? found;
      for (int i = 0; i < 6 && found == null; i++) {
        final File candidate = File('${dir.path}/lib/child_home.dart');
        if (candidate.existsSync()) found = candidate;
        dir = dir.parent;
      }
      expect(found, isNotNull, reason: 'could not locate lib/child_home.dart to audit');
      final String source = found!.readAsStringSync();
      expect(source.contains('ExpensesScreen'), isFalse,
        reason: 'a child-facing file must never reference ExpensesScreen');
      expect(source.toLowerCase().contains('expense'), isFalse,
        reason: 'a child-facing file must never mention expenses at all');
    });

    test('inboxVisibleTo agrees with P6: guardian yes, child no', () {
      expect(inboxVisibleTo(ViewerRole.guardian), isTrue);
      expect(inboxVisibleTo(ViewerRole.child), isFalse);
    });

    testWidgets('a child viewer sees no financial content whatsoever', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen(viewerRole: ViewerRole.child)));

      // No dollar figures, no ledger, no approval actions, no title.
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.text('Agree'), findsNothing);
      expect(find.text('Query it'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.textContaining('Ledger'), findsNothing);
      expect(find.textContaining('Expenses'), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('the guardian viewer sees the real ledger and approvals', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen()));
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.textContaining('Orthodontist co-pay'), findsOneWidget);
      expect(find.text('Agree'), findsWidgets);
      expect(find.textContaining(r'$'), findsWidgets);
    });

    testWidgets('agreeing to an approval removes it from the pending list', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen()));
      // Section labels render upper-cased (see _SectionLabel).
      expect(find.textContaining('NEEDS YOUR ANSWER (2)'), findsOneWidget);

      await t.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await t.pump();

      expect(find.textContaining('NEEDS YOUR ANSWER (1)'), findsOneWidget);
    });

    testWidgets('the child-role fallback never contains an interactive '
        'financial control', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen(viewerRole: ViewerRole.child)));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('resolving every approval shows a calm, honest empty state — '
        'a real icon and message, not a bare label', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen()));
      await t.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await t.pump();
      await t.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await t.pump();
      expect(find.textContaining('NEEDS YOUR ANSWER (0)'), findsOneWidget);
      expect(find.text('Nothing waiting.'), findsOneWidget);
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
    });

    testWidgets('approval action buttons meet the 48dp minimum tap target',
        (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen()));
      final Size size = t.getSize(find.ancestor(
        of: find.text('Agree').first,
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton)));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop widths', () {
    Future<void> atSize(WidgetTester t, Size size, Widget child) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(child));
      await t.pumpAndSettle();
    }

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow',
        (t) async {
      await atSize(t, const Size(344, 882), const ExpensesScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const ExpensesScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const ExpensesScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const ExpensesScreen());
      expect(t.takeException(), isNull);
    });
  });
}
