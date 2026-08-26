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
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

      // 40, matching the house "nothing pending" empty-state idiom used
      // throughout (journal_screen.dart, letters_screen.dart, teach_me.dart,
      // weeks_screen.dart, inbox_screen.dart, etc.), not a one-off size.
      final Icon icon = t.widget(find.byIcon(Icons.mark_email_read_outlined));
      expect(icon.size, 40.0);
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

  group('expenses — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    // Real columnsAt()-driven threshold (form_factors.dart), matching
    // message_banking.dart's own two-pane pattern — not an invented number.
    // Every case here uses the default guardian viewerRole: this is a
    // guardian-only feature by definition (P6), so there is no
    // "child role + wide viewport" case to test.
    testWidgets('a genuinely wide viewport (tablet/desktop, >=660px effective) '
        "renders 'Needs your answer' and 'Ledger' as two side-by-side panes",
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const ExpensesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expensesTwoPaneRow')), findsOneWidget);
      // Both panes' real content is still genuinely present, just rearranged.
      expect(find.textContaining('Orthodontist co-pay'), findsOneWidget);
      expect(find.text('Winter coat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single '
        "column unchanged — no two-pane Row at all", (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const ExpensesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expensesTwoPaneRow')), findsNothing);
      expect(find.textContaining('Orthodontist co-pay'), findsOneWidget);
      expect(find.text('Winter coat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single '
        'column, not the two-pane Row', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const ExpensesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expensesTwoPaneRow')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('agreeing to a pending approval still works correctly inside '
        'the wide two-pane layout', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const ExpensesScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('NEEDS YOUR ANSWER (2)'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await tester.pump();

      expect(find.textContaining('NEEDS YOUR ANSWER (1)'), findsOneWidget);
      // The agreed item lands in the Ledger pane, confirming both panes
      // still read from the same state inside the wide two-pane layout.
      expect(find.text('Soccer cleats, size 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('live wiring — the real expense-backed routes (server/routes.mjs, '
      'packages/db/src/pool.ts proposeExpense/expensesFor/resolveExpense)', () {
    testWidgets('a child viewer sees no financial content even when live params are '
        'supplied — P6 runs before _load() is ever called', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        fail('no network call should ever happen for a child viewerRole');
      });
      await t.pumpWidget(wrap(ExpensesScreen(viewerRole: ViewerRole.child,
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pump();
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('Expenses'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a loading indicator, then real fetched expenses replace the '
        'demo fixtures, split into pending vs. ledger by real status', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        expect(req.url.path, '/v1/children/child-a/expenses');
        return http.Response(jsonEncode({'entries': [
          {'id': 'e1', 'paidById': 'dad-1', 'paidByName': 'Dad',
           'description': 'Real orthodontist bill', 'amountCents': 12000,
           'category': 'medical', 'incurredOn': '2026-07-01', 'receiptKey': null,
           'payerSharePercent': 50, 'status': 'proposed', 'createdAt': '2026-07-01T12:00:00.000Z'},
          {'id': 'e2', 'paidById': 'mom-1', 'paidByName': 'Mom',
           'description': 'Real winter coat', 'amountCents': 8900,
           'category': 'clothing', 'incurredOn': '2026-06-15', 'receiptKey': null,
           'payerSharePercent': 50, 'status': 'reimbursed', 'createdAt': '2026-06-15T12:00:00.000Z'},
        ]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();

      // Real data, not the demo fixtures.
      expect(find.textContaining('Real orthodontist bill'), findsOneWidget);
      expect(find.textContaining('Real winter coat'), findsOneWidget);
      expect(find.textContaining('Orthodontist co-pay'), findsNothing);
      // status='proposed' -> pending pane; status!='proposed' -> ledger pane.
      expect(find.textContaining('NEEDS YOUR ANSWER (1)'), findsOneWidget);
      // paidById 'mom-1' != the threaded-in guardianId 'dad-1' -> real name.
      expect(find.textContaining('Mom paid'), findsOneWidget);
      expect(find.textContaining(r'$89.00'), findsOneWidget);
    });

    testWidgets("Agree POSTs 'accept' and renders the SERVER's own returned amount, "
        "fixing the demo's own hardcoded amountCents: 0 bug", (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'e1', 'paidById': 'mom-1', 'description': 'Real orthodontist bill',
            'amountCents': 12000, 'category': 'medical', 'incurredOn': '2026-07-01',
            'receiptKey': null, 'payerSharePercent': 50, 'status': 'accepted',
            'createdAt': '2026-07-01T12:00:00.000Z',
          }), 200);
        }
        return http.Response(jsonEncode({'entries': [
          {'id': 'e1', 'paidById': 'mom-1', 'paidByName': 'Mom',
           'description': 'Real orthodontist bill', 'amountCents': 12000,
           'category': 'medical', 'incurredOn': '2026-07-01', 'receiptKey': null,
           'payerSharePercent': 50, 'status': 'proposed', 'createdAt': '2026-07-01T12:00:00.000Z'},
        ]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/v1/children/child-a/expenses/e1/accept');
      expect(find.textContaining('NEEDS YOUR ANSWER (0)'), findsOneWidget);
      // The real server-returned amount, not the demo's hardcoded 0.
      expect(find.textContaining(r'$120.00'), findsOneWidget);
    });

    testWidgets("Decline POSTs 'dispute' — the real closest status, not an invented "
        "'declined' value", (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'e1', 'paidById': 'mom-1', 'description': 'A disputed charge',
            'amountCents': 500, 'category': 'other', 'incurredOn': '2026-07-01',
            'receiptKey': null, 'payerSharePercent': 50, 'status': 'disputed',
            'createdAt': '2026-07-01T12:00:00.000Z',
          }), 200);
        }
        return http.Response(jsonEncode({'entries': [
          {'id': 'e1', 'paidById': 'mom-1', 'paidByName': 'Mom',
           'description': 'A disputed charge', 'amountCents': 500,
           'category': 'other', 'incurredOn': '2026-07-01', 'receiptKey': null,
           'payerSharePercent': 50, 'status': 'proposed', 'createdAt': '2026-07-01T12:00:00.000Z'},
        ]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(OutlinedButton, 'Decline').first);
      await t.pumpAndSettle();

      expect(posts.single.url.path, '/v1/children/child-a/expenses/e1/dispute');
      expect(find.textContaining('50/50 split · disputed'), findsOneWidget);
    });

    testWidgets("Query it fires no network call and shows an honest 'not built' "
        'message, never silently mapped to accept/dispute', (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') { posts.add(req); return http.Response('{}', 200); }
        return http.Response(jsonEncode({'entries': [
          {'id': 'e1', 'paidById': 'mom-1', 'paidByName': 'Mom',
           'description': 'Query me', 'amountCents': 500, 'category': 'other',
           'incurredOn': '2026-07-01', 'receiptKey': null, 'payerSharePercent': 50,
           'status': 'proposed', 'createdAt': '2026-07-01T12:00:00.000Z'},
        ]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(OutlinedButton, 'Query it').first);
      await t.pump();

      expect(posts, isEmpty);
      expect(find.textContaining("isn't built yet"), findsOneWidget);
      // Still pending — Query it never resolves the item.
      expect(find.textContaining('NEEDS YOUR ANSWER (1)'), findsOneWidget);
    });

    testWidgets('a real resolve FAILURE shows a visible error and leaves the item '
        'pending — never a silent no-op', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') return http.Response('server error', 500);
        return http.Response(jsonEncode({'entries': [
          {'id': 'e1', 'paidById': 'mom-1', 'paidByName': 'Mom',
           'description': 'Will fail to resolve', 'amountCents': 500, 'category': 'other',
           'incurredOn': '2026-07-01', 'receiptKey': null, 'payerSharePercent': 50,
           'status': 'proposed', 'createdAt': '2026-07-01T12:00:00.000Z'},
        ]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(OutlinedButton, 'Agree').first);
      await t.pumpAndSettle();

      expect(find.textContaining("Couldn't send that response"), findsOneWidget);
      expect(find.textContaining('NEEDS YOUR ANSWER (1)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a real fetch failure is an honest error with a working retry, never '
        'a crash or a silent fallback to the demo fixtures', (t) async {
      int calls = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        calls++;
        if (calls == 1) return http.Response('server error', 500);
        return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
      });
      await t.pumpWidget(wrap(ExpensesScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.textContaining('NEEDS YOUR ANSWER (0)'), findsOneWidget);
      expect(find.text('Nothing waiting.'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('with no live params supplied, the demo fixtures render exactly '
        'as before — no network call, no loading state', (t) async {
      await t.pumpWidget(wrap(const ExpensesScreen()));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Orthodontist co-pay'), findsOneWidget);
    });
  });
}
