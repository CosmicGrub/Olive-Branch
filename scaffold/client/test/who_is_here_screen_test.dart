// OLIVE BRANCH — who is here tests. MASTERFILE §17.1, §8.5.3.
//
// The invariant this screen exists to enforce: a solo guardian is stated,
// never chosen between; a pending invite is informational, never a nudge;
// the last selected guardian can never be deselected. Each is asserted
// directly against the widget tree, not inferred from the predicate alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/who_is_here_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

final DateTime _now = DateTime.utc(2028, 1, 10);

void main() {
  group('isSingleGuardianViable port — §17.1', () {
    test('true with exactly one live, accepted guardian', () {
      final edges = <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
      ];
      expect(isSingleGuardianViable(edges, _now), isTrue);
    });

    test('false when the only guardian has not accepted yet', () {
      final edges = <GuardianEdge>[
        const GuardianEdge(userId: 'dad', label: 'Daddy'),
      ];
      expect(isSingleGuardianViable(edges, _now), isFalse);
    });

    test('false when the only guardian edge is closed', () {
      final edges = <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy',
          acceptedAt: DateTime.utc(2024, 1, 1), closedAt: DateTime.utc(2027, 1, 1)),
      ];
      expect(isSingleGuardianViable(edges, _now), isFalse);
    });

    test('false when the ladder step is none', () {
      final edges = <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy',
          acceptedAt: DateTime.utc(2024, 1, 1), ladderStep: 'none'),
      ];
      expect(isSingleGuardianViable(edges, _now), isFalse);
    });

    test('true with two live guardians (>= 1, not == 1)', () {
      final edges = <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
        GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
      ];
      expect(isSingleGuardianViable(edges, _now), isTrue);
    });
  });

  group('solo guardian — no choice presented, §8.5.3', () {
    testWidgets('a single accepted guardian renders a plain statement, no chooser', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
      ], now: _now)));
      expect(find.byKey(const Key('soloGuardian')), findsOneWidget);
      expect(find.text('Daddy'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('a pending second guardian appears greyed alongside a solo guardian, '
        'never turning the solo statement into a chooser', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
        const GuardianEdge(userId: 'mum', label: 'Mama'),
      ], now: _now)));
      expect(find.byKey(const Key('soloGuardian')), findsOneWidget);
      expect(find.byKey(const Key('pendingChip_mum')), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing, reason: 'a pending invite is not a choice');
    });

    testWidgets('uses each guardian\'s own word, never a hard-coded label', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'g1', label: 'Baba', acceptedAt: DateTime.utc(2024, 1, 1)),
      ], now: _now)));
      expect(find.text('Baba'), findsOneWidget);
      expect(find.text('Mommy'), findsNothing);
      expect(find.text('Daddy'), findsNothing);
    });
  });

  group('nobody here yet — a supported, neutral state', () {
    testWidgets('shows neutral copy, no error, when no guardian has accepted', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: const <GuardianEdge>[], now: _now)));
      expect(find.byKey(const Key('nobodyHereYet')), findsOneWidget);
      expect(find.textContaining('Nobody is here yet'), findsOneWidget);
    });

    testWidgets('a pending-only invite is still "nobody here yet", shown greyed', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: const <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy'),
      ], now: _now)));
      expect(find.byKey(const Key('nobodyHereYet')), findsOneWidget);
      expect(find.byKey(const Key('pendingChip_dad')), findsOneWidget);
    });
  });

  group('two guardians — both selected by default, last cannot be deselected', () {
    testWidgets('both chips start selected', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
        GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
      ], now: _now)));
      final dad = findChip(t, 'guardianChip_dad');
      final mum = findChip(t, 'guardianChip_mum');
      expect(dad.selected, isTrue);
      expect(mum.selected, isTrue);
    });

    testWidgets('deselecting one leaves the other selected', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
        GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
      ], now: _now)));
      await t.tap(find.byKey(const Key('guardianChip_dad')));
      await t.pump();
      expect(findChip(t, 'guardianChip_dad').selected, isFalse);
      expect(findChip(t, 'guardianChip_mum').selected, isTrue);
    });

    testWidgets('the last selected guardian refuses to be deselected — she may never '
        'end up with nobody', (t) async {
      await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
        GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
        GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
      ], now: _now)));
      await t.tap(find.byKey(const Key('guardianChip_dad')));
      await t.pump();
      await t.tap(find.byKey(const Key('guardianChip_mum')));
      await t.pump();
      // Still selected — the tap on the last remaining one was refused.
      expect(findChip(t, 'guardianChip_mum').selected, isTrue);
    });

    testWidgets('reports the selection back to the caller', (t) async {
      Set<String>? reported;
      await t.pumpWidget(wrap(WhoIsHereScreen(
        edges: <GuardianEdge>[
          GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
          GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
        ],
        now: _now,
        onSelectionChanged: (s) => reported = s,
      )));
      await t.tap(find.byKey(const Key('guardianChip_dad')));
      await t.pump();
      expect(reported, <String>{'mum'});
    });
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
        await t.pumpWidget(wrap(WhoIsHereScreen(edges: <GuardianEdge>[
          GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
          GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 1)),
          const GuardianEdge(userId: 'aunt', label: 'Auntie Jo'),
        ], now: _now)));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });
}

FilterChip findChip(WidgetTester t, String key) =>
    t.widget<FilterChip>(find.byKey(Key(key)));
