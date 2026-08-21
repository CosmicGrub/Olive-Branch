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
      expect(find.text('Draw together'), findsOneWidget);
      expect(find.text('Guess the doodle'), findsOneWidget);
      // Batch B — the four curated-prompt activities.
      expect(find.text('Silly sentence maker'), findsOneWidget);
      expect(find.text('Would you rather'), findsOneWidget);
      expect(find.text('Two truths and a tall tale'), findsOneWidget);
      expect(find.text('20 questions'), findsOneWidget);
    });

    testWidgets('a younger child sees fewer boards, never harder ones', (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 4)));
      await t.pumpAndSettle();
      expect(find.text('Three in a row'), findsOneWidget);
      expect(find.text('Our photos'), findsOneWidget);
      expect(find.text('Draw together'), findsOneWidget);
      expect(find.text('Dots and boxes'), findsNothing);
      expect(find.text('Make up a story'), findsNothing);
      expect(find.text('Guess the doodle'), findsNothing);
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

    testWidgets('a wired onPlay callback reaches draw together and guess the doodle too', (t) async {
      // Tall enough that all 6 cards are on-screen without scrolling — the
      // wiring is what's under test, not scroll mechanics.
      await t.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      GameKind? tapped;
      await t.pumpWidget(wrap(GamePickerScreen(childAge: 8, onPlay: (context, kind) => tapped = kind)));
      await t.pumpAndSettle();
      await t.tap(find.text('Draw together'));
      await t.pump();
      expect(tapped, GameKind.drawTogether);
      await t.tap(find.text('Guess the doodle'));
      await t.pump();
      expect(tapped, GameKind.guessDoodle);
    });

    testWidgets('a wired onPlay callback reaches all four of batch B\'s curated-prompt activities too', (t) async {
      // Tall enough that all ten cards are on-screen without scrolling —
      // the wiring is what's under test, not scroll mechanics.
      await t.binding.setSurfaceSize(const Size(800, 2200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      GameKind? tapped;
      await t.pumpWidget(wrap(GamePickerScreen(childAge: 8, onPlay: (context, kind) => tapped = kind)));
      await t.pumpAndSettle();

      await t.tap(find.text('Silly sentence maker'));
      await t.pump();
      expect(tapped, GameKind.sillySentence);

      await t.tap(find.text('Would you rather'));
      await t.pump();
      expect(tapped, GameKind.wouldYouRather);

      await t.tap(find.text('Two truths and a tall tale'));
      await t.pump();
      expect(tapped, GameKind.twoTruths);

      await t.tap(find.text('20 questions'));
      await t.pump();
      expect(tapped, GameKind.twentyQuestions);
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

    testWidgets('cards use the canonical 14dp action-tile radius, matching child_home/guardian_home',
        (t) async {
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      final container = t.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(14));
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

    testWidgets('renders at a standard phone width (~390 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (~1100 CSS px) without overflow', (t) async {
      // Short-and-wide, unlike a tall phone — now that Windows is a real
      // target, three columns must lay out at this width too (§0's note on
      // the crease gutter is Fold5-specific; a desktop has no crease).
      await t.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('game picker — column count is driven by form_factors.dart\'s columnsAt(), '
      'not a hand-rolled breakpoint', () {
    Future<int> crossAxisCountAt(WidgetTester t, Size size) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 8)));
      await t.pumpAndSettle();
      final delegate = t.widget<GridView>(find.byType(GridView)).gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    testWidgets('Fold5 cover (344px) — one column', (t) async {
      expect(await crossAxisCountAt(t, const Size(344, 882)), 1);
    });

    testWidgets('Fold5 unfolded main (~673px) — two columns, same as before this migration', (t) async {
      expect(await crossAxisCountAt(t, const Size(673, 841)), 2);
    });

    testWidgets('a 10-inch tablet (800px, tabletLarge) — two columns, not three: a real, '
        'intentional change from the old 680px breakpoint, matching FORM_FACTORS\' own '
        'tabletLarge.columns=2', (t) async {
      expect(await crossAxisCountAt(t, const Size(800, 1280)), 2);
    });

    testWidgets('genuine desktop width (1100px) — three columns', (t) async {
      expect(await crossAxisCountAt(t, const Size(1100, 800)), 3);
    });

    testWidgets('a large accessibility text scale narrows the effective width, same as '
        'court_export.dart\'s columnsAt() call', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1280));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: GamePickerScreen(childAge: 8),
      )));
      await t.pumpAndSettle();
      final delegate = t.widget<GridView>(find.byType(GridView)).gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 1);
    });
  });
}
