// OLIVE BRANCH — game hub tests. Asserts what actually renders (§8.1-style
// invariants, the invariants_test.dart house convention) rather than
// re-deriving the pure logic, which game_logic_test.dart already covers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/game_picker.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

void main() {
  group('game picker — §9.2', () {
    testWidgets('every game in the demo catalogue renders a real card', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      expect(find.text('Three in a row'), findsOneWidget);
      expect(find.text('Dots and boxes'), findsOneWidget);
      expect(find.text('Our photos'), findsOneWidget);
      expect(find.text('Make up a story'), findsOneWidget);
    });

    testWidgets('a younger child sees fewer boards, never harder ones', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 4)));
      await t.pumpAndSettle();
      expect(find.text('Three in a row'), findsOneWidget);
      expect(find.text('Our photos'), findsOneWidget);
      expect(find.text('Dots and boxes'), findsNothing);
      expect(find.text('Make up a story'), findsNothing);
    });

    testWidgets('she is greeted by her own name, not an id, when given one', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childName: 'Ivy', childAge: 8)));
      expect(find.text('What do you want to play, Ivy?'), findsOneWidget);
    });

    testWidgets('tapping an unwired game is an honest not-built-yet acknowledgment, not a fabricated board',
        (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.tap(find.text('Three in a row'));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
    });

    testWidgets('a wired onPlay callback receives the tapped game kind', (t) async {
      GameKind? tapped;
      await t.pumpWidget(wrap(GamePickerScreen(childAge: 8, onPlay: (context, kind) => tapped = kind)));
      await t.tap(find.text('Make up a story'));
      await t.pump();
      expect(tapped, GameKind.story);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining('settings'), findsNothing);
    });

    testWidgets('§2.1/P2 — no score, rank, streak, or leaderboard is ever rendered', (t) async {
      // Deliberately excludes "win"/"loss" as bare words: the catalogue's own
      // ported blurbs legitimately say "can genuinely win this one" and
      // "Nobody wins" (games.ts's canonical copy) — narrative flavor text,
      // not a record. What must never appear is an actual scoreboard vocabulary.
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      for (final forbidden in ['streak', 'rank', 'score', 'elo', 'leaderboard', 'win rate']) {
        expect(
          find.textContaining(RegExp(forbidden, caseSensitive: false)),
          findsNothing,
          reason: '"$forbidden" must never appear on the game hub',
        );
      }
    });

    testWidgets('no price, currency, or purchase affordance exists anywhere on this screen', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      expect(find.textContaining(RegExp(r'\$')), findsNothing);
      expect(find.text('Buy'), findsNothing);
      expect(find.textContaining('Purchase', findRichText: true), findsNothing);
    });

    testWidgets('cards meet the 48dp+ touch target minimum for pre-readers', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      final size = t.getSize(find.byType(GestureDetector).first);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
