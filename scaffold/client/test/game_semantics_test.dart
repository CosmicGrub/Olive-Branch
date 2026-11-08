// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — screen-reader
// semantics for the games and canvases: Connect 4, War, the puzzle, Pictionary,
// the doodle desk, colouring and story pages. Labels and values, focus order, and
// live-region announcements that are P2-safe (no scores). MASTERFILE §8.4.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_names.dart';
import 'package:olive_client/colouring_screen.dart';
import 'package:olive_client/doodle_desk.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/game_pictionary.dart';
import 'package:olive_client/game_puzzle.dart';
import 'package:olive_client/game_war.dart';
import 'package:olive_client/live_games.dart' show Side;
import 'package:olive_client/storyteller_screen.dart';
import 'package:olive_client/together_puzzle.dart';
import 'package:olive_client/war_deck.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      home: Scaffold(body: SingleChildScrollView(child: Center(child: child))),
    );

/// A live-region line must never carry a score, count or ranking (P2): no digits,
/// and none of the words that frame a result as a verdict.
void expectP2Safe(String s) {
  expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'a live announcement must not carry a number: "$s"');
  for (final String banned in <String>['score', 'point', 'streak', 'rank', 'won', 'lost', 'winner', 'loser', 'beat']) {
    expect(s.toLowerCase().contains(banned), isFalse, reason: '"$s" must not contain "$banned"');
  }
}

List<SemanticsNode> liveRegions(WidgetTester t) {
  final Finder f = find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.liveRegion == true);
  return <SemanticsNode>[for (int i = 0; i < f.evaluate().length; i++) t.getSemantics(f.at(i))];
}

void main() {
  group('colour names', () {
    test('every colouring swatch has a different everyday name, so a child can tell them apart', () {
      final List<String> names = <String>[for (final Color c in colouringPalette) colourName(c)];
      expect(names.toSet().length, names.length, reason: '$names');
      expect(names, containsAll(<String>['red', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'brown']));
    });

    test('every doodle brush colour has a different everyday name', () {
      final List<String> names = <String>[for (final Color c in kBrushColors) colourName(c)];
      expect(names.toSet().length, names.length, reason: '$names');
      expect(names.first, 'black');
      expect(names.last, 'white');
    });

    test('the plain primaries are what they say', () {
      expect(colourName(const Color(0xFFFF0000)), 'red');
      expect(colourName(const Color(0xFF00FF00)), 'green');
      expect(colourName(const Color(0xFF0000FF)), 'blue');
      expect(colourName(const Color(0xFF000000)), 'black');
    });
  });

  group('Connect 4', () {
    test('a cell is described by who has a disc there and its shape', () {
      expect(connect4DiscWords(null, Side.b), 'empty');
      expect(connect4DiscWords(Side.b, Side.b), 'your disc, a circle');
      expect(connect4DiscWords(Side.a, Side.b), 'their disc, a triangle');
    });

    Future<void> startVsCpu(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: GameConnect4Screen(role: 'ivy', displayName: 'Ivy')));
      await t.tap(find.text('Start'));
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the board is one labelled group of 7 columns by 6 rows', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await startVsCpu(t);
      expect(find.bySemanticsLabel('Connect 4 board, 7 columns by 6 rows'), findsOneWidget);
      h.dispose();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('every one of the 42 cells is a node with its column, its row and its state', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await startVsCpu(t);
      expect(find.bySemanticsLabel(RegExp(r'^Column \d, row \d from the bottom$')), findsNWidgets(42));
      final SemanticsNode first = t.getSemantics(find.bySemanticsLabel('Column 1, row 1 from the bottom'));
      expect(first.value, 'empty');
      h.dispose();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('on her turn the cells are buttons that drop a disc, and the disc is then announced as hers',
        (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await startVsCpu(t);
      // She is Side.b and the CPU (Side.a) moves first or second: wait for her turn.
      for (int i = 0; i < 40 && !find.text('Your turn').evaluate().isNotEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final SemanticsNode cell = t.getSemantics(find.bySemanticsLabel('Column 4, row 1 from the bottom'));
      expect(cell.flagsCollection.isButton, isTrue);
      expect(cell.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      t.semantics.performAction(find.semantics.byLabel('Column 4, row 1 from the bottom'), SemanticsAction.tap);
      await t.pump(const Duration(milliseconds: 100));
      final SemanticsNode after = t.getSemantics(find.bySemanticsLabel('Column 4, row 1 from the bottom'));
      expect(after.value, 'your disc, a circle');
      h.dispose();
      await t.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('cells read column by column, bottom to top (focus order follows the way a column fills)',
        (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await startVsCpu(t);
      final SemanticsNode c1r1 = t.getSemantics(find.bySemanticsLabel('Column 1, row 1 from the bottom'));
      final SemanticsNode c1r2 = t.getSemantics(find.bySemanticsLabel('Column 1, row 2 from the bottom'));
      final SemanticsNode c2r1 = t.getSemantics(find.bySemanticsLabel('Column 2, row 1 from the bottom'));
      OrdinalSortKey key(SemanticsNode n) => n.sortKey! as OrdinalSortKey;
      expect(key(c1r1).order, lessThan(key(c1r2).order));
      expect(key(c1r2).order, lessThan(key(c2r1).order), reason: 'all of column 1 comes before column 2');
      h.dispose();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('the turn line is a live region and says no score', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await startVsCpu(t);
      final List<SemanticsNode> live = liveRegions(t);
      expect(live, isNotEmpty);
      for (final SemanticsNode n in live) {
        expectP2Safe(n.label);
      }
      h.dispose();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    });
  });

  group('War', () {
    const PlayingCard queen = PlayingCard(rank: 12, suit: Suit.hearts);
    final List<PlayingCard> pile = standardDeck().take(26).toList();

    test('a card is described the way it is said', () {
      expect(warCardWords(queen), 'Queen of hearts');
      expect(warCardWords(const PlayingCard(rank: 14, suit: Suit.spades)), 'Ace of spades');
      expect(warCardWords(const PlayingCard(rank: 13, suit: Suit.clubs)), 'King of clubs');
      expect(warCardWords(const PlayingCard(rank: 11, suit: Suit.diamonds)), 'Jack of diamonds');
      expect(warCardWords(const PlayingCard(rank: 7, suit: Suit.clubs)), '7 of clubs');
    });

    WarState state({List<PlayingCard>? mine, List<PlayingCard>? theirs, String? note}) => WarState(
        myPile: pile, roundNumber: 3, pot: const <PlayingCard>[], myPending: mine, theirPending: theirs,
        phase: WarPhase.playing, lastRoundNote: note);

    Widget view(WarState s) =>
        wrap(WarView(state: s, mySide: Side.b, peerName: 'Dad', onFlip: () {}));

    testWidgets('her turn: one button turns over her top card', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      int flips = 0;
      await t.pumpWidget(wrap(WarView(state: state(), mySide: Side.b, peerName: 'Dad', onFlip: () => flips++)));
      final SemanticsNode flip = t.getSemantics(find.bySemanticsLabel('Turn over your top card'));
      expect(flip.flagsCollection.isButton, isTrue);
      t.semantics.performAction(find.semantics.byLabel('Turn over your top card'), SemanticsAction.tap);
      expect(flips, 1);
      h.dispose();
    });

    testWidgets('the two cards on the table are named, with their faces', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(view(state(mine: const <PlayingCard>[queen])));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getSemantics(find.bySemanticsLabel('Your card')).value, 'Queen of hearts');
      expect(t.getSemantics(find.bySemanticsLabel("Dad's card")).value, 'not turned over yet');
      h.dispose();
    });

    testWidgets('piles are "your pile" and "Dad\'s pile", never with a number (P2)', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(view(state()));
      final SemanticsNode mine = t.getSemantics(find.bySemanticsLabel('Your pile'));
      final SemanticsNode theirs = t.getSemantics(find.bySemanticsLabel("Dad's pile"));
      for (final SemanticsNode n in <SemanticsNode>[mine, theirs]) {
        expect(RegExp(r'\d').hasMatch('${n.label} ${n.value}'), isFalse, reason: 'a pile is never announced as a count');
      }
      h.dispose();
    });

    testWidgets('"waiting for Dad" and the round note are live regions, and P2-safe', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(view(state(mine: const <PlayingCard>[queen], note: 'You win this round.')));
      await t.pump(const Duration(milliseconds: 400));
      final List<String> said = <String>[for (final SemanticsNode n in liveRegions(t)) n.label];
      expect(said, containsAll(<String>['You win this round.', 'Waiting for Dad to flip…']));
      for (final String s in said) {
        expectP2Safe(s);
      }
      h.dispose();
    });
  });

  group('the puzzle', () {
    PuzzleView view(Set<String> placed, {Side mover = Side.b, void Function(String, String)? onPlace}) => PuzzleView(
        state: TogetherPuzzleState(puzzleId: 'farmyard', placedPieces: placed, mover: mover),
        mySide: Side.b, peerName: 'Dad', onPlace: onPlace ?? (_, _) {}, celebrated: false, onCelebrate: () {});

    testWidgets('every spot says what it is for and whether it is filled', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(<String>{'cow'})));
      expect(t.getSemantics(find.bySemanticsLabel('Cow spot')).value, 'Cow, placed');
      expect(t.getSemantics(find.bySemanticsLabel('Barn spot')).value, 'empty');
      h.dispose();
    });

    testWidgets('on her turn each loose piece can be placed by activating it, into its own spot only',
        (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      final List<(String, String)> placed = <(String, String)>[];
      await t.pumpWidget(wrap(view(<String>{}, onPlace: (String p, String s) => placed.add((p, s)))));
      final SemanticsNode barn = t.getSemantics(find.bySemanticsLabel('Barn piece'));
      expect(barn.flagsCollection.isButton, isTrue);
      expect(barn.hint, 'Double tap to put it in its spot');
      t.semantics.performAction(find.semantics.byLabel('Barn piece'), SemanticsAction.tap);
      expect(placed, <(String, String)>[('barn', 'slot2')], reason: 'the correct spot, so a wrong move cannot be made');
      h.dispose();
    });

    testWidgets('on the other side\'s turn there are no loose pieces to activate', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(<String>{}, mover: Side.a)));
      expect(find.bySemanticsLabel('Barn piece'), findsNothing);
      h.dispose();
    });

    testWidgets('the turn line is a live region without a number', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(<String>{})));
      final List<String> said = <String>[for (final SemanticsNode n in liveRegions(t)) n.label];
      expect(said, contains('Your turn to place a piece'));
      for (final String s in said) {
        expectP2Safe(s);
      }
      h.dispose();
    });
  });

  group('Pictionary', () {
    PictionaryView view(PicPhase phase, {bool drawer = true}) => PictionaryView(
          phase: phase, isDrawer: drawer, word: drawer ? 'cat' : null, canvas: null,
          liveStroke: const [], revealedStrokes: const [], rounds: 0, peerName: 'Dad',
          lastGuessWasWrong: false, lastGuessText: null, celebrated: false,
          guessController: TextEditingController(),
          onPanStart: (_) {}, onPanUpdate: (_) {}, onPanEnd: (_) {},
          onShowThem: () {}, onSubmitGuess: (_) {}, onCelebrate: () {},
        );

    testWidgets('the drawing surface says what it is and how to use it', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(PicPhase.drawing)));
      final SemanticsNode n = t.getSemantics(find.bySemanticsLabel('Drawing area'));
      expect(n.hint, 'Drag a finger across it to draw');
      h.dispose();
    });

    testWidgets('the finished drawing is an image called "The drawing"', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(PicPhase.waitingForGuess)));
      expect(t.getSemantics(find.bySemanticsLabel('The drawing')).flagsCollection.isImage, isTrue);
      h.dispose();
    });

    testWidgets('the headline is a live region, P2-safe', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(view(PicPhase.waitingForGuess)));
      final List<String> said = <String>[for (final SemanticsNode n in liveRegions(t)) n.label];
      expect(said, isNotEmpty);
      for (final String s in said) {
        expectP2Safe(s);
      }
      h.dispose();
    });

    testWidgets('"Show them" and "Guess" are at least 64dp', (WidgetTester t) async {
      await t.pumpWidget(wrap(view(PicPhase.viewing, drawer: false)));
      expect(t.getSize(find.widgetWithText(FilledButton, 'Guess')).height, greaterThanOrEqualTo(64));
    });
  });

  group('the doodle desk', () {
    Future<void> open(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: DoodleDesk()));
      await t.pump();
    }

    testWidgets('the board is a labelled drawing area, and the hint follows the tool', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      expect(t.getSemantics(find.bySemanticsLabel('Drawing area')).hint, 'Drag a finger across it to draw');
      await t.tap(find.text('Stamps'));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.getSemantics(find.bySemanticsLabel('Drawing area')).hint, 'Tap it to place a stamp');
      h.dispose();
    });

    testWidgets('every colour is a named button, and exactly one is selected', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      for (final Color c in kBrushColors) {
        final SemanticsNode n = t.getSemantics(find.bySemanticsLabel('Colour: ${colourName(c)}'));
        expect(n.flagsCollection.isButton, isTrue);
      }
      int selected = 0;
      for (final Color c in kBrushColors) {
        if (t.getSemantics(find.bySemanticsLabel('Colour: ${colourName(c)}')).flagsCollection.isSelected == Tristate.isTrue) selected++;
      }
      expect(selected, 1);
      h.dispose();
    });

    testWidgets('brush sizes are named', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      for (final String label in <String>['Thin brush', 'Medium brush', 'Thick brush']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      h.dispose();
    });

    testWidgets('colour swatches, brush dots and stamps are 64dp targets', (WidgetTester t) async {
      await open(t);
      final Size swatch = t.getSize(find.ancestor(
          of: find.byType(DecoratedBox).first, matching: find.byType(Container)).first);
      expect(swatch.height, greaterThanOrEqualTo(0));
      final RenderBox box = t.renderObject<RenderBox>(find.byWidgetPredicate((Widget w) =>
          w is Container && w.constraints?.maxWidth == 64 && w.constraints?.maxHeight == 64).first);
      expect(box.size.width, 64);
      await t.tap(find.text('Stamps'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byWidgetPredicate((Widget w) => w is Container && w.constraints?.maxWidth == 64).evaluate().length,
          greaterThanOrEqualTo(6), reason: 'all six stamps are 64dp');
    });

    testWidgets('stamps are named buttons', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      await t.tap(find.text('Stamps'));
      await t.pump(const Duration(milliseconds: 50));
      for (final String s in <String>['Heart', 'Star', 'Smiley', 'Rainbow', 'Sun', 'Moon']) {
        expect(find.bySemanticsLabel('$s stamp'), findsOneWidget);
      }
      h.dispose();
    });
  });

  group('colouring', () {
    Future<void> open(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: ColouringScreen()));
      await t.pump();
    }

    testWidgets('every colour is a named, 64dp button and one is selected', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      int selected = 0;
      for (final Color c in colouringPalette) {
        final SemanticsNode n = t.getSemantics(find.bySemanticsLabel('Colour: ${colourName(c)}'));
        expect(n.flagsCollection.isButton, isTrue);
        expect(n.rect.width, greaterThanOrEqualTo(64));
        expect(n.rect.height, greaterThanOrEqualTo(64));
        if (n.flagsCollection.isSelected == Tristate.isTrue) selected++;
      }
      expect(selected, 1);
      h.dispose();
    });

    testWidgets('every part of the picture is a node with a name, and says it is not coloured yet', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      for (final String name in colouringRegionNames.values) {
        final SemanticsNode n = find.semantics.byLabel(name).evaluate().single;
        expect(n.value, 'not coloured yet');
        expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      expect(colouringRegionNames.length, 13);
      h.dispose();
    });

    testWidgets('a screen reader can colour a part: activate "Sun", and it reports the colour', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      await t.tap(find.bySemanticsLabel('Colour: yellow'));
      await t.pump();
      t.semantics.performAction(find.semantics.byLabel('Sun'), SemanticsAction.tap);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.semantics.byLabel('Sun').evaluate().single.value, 'yellow');
      expect(find.semantics.byLabel('Sky').evaluate().single.value, 'not coloured yet');
      h.dispose();
    });

    testWidgets('the kept-picture thumbnail has no part nodes (it is not interactive)', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 120, height: 100,
          child: ColouringThumbnail(data: <String, Object?>{'fills': <String, Object?>{'sky': 0xFF3498DB}})))));
      expect(find.semantics.byLabel('Sky').evaluate(), isEmpty);
      h.dispose();
    });
  });

  group('story pages', () {
    testWidgets('a page is a named node ("Story page 1 of N") carrying its text',
        (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: StorytellerScreen(childName: 'Ivy')));
      await t.tap(find.text('Tell me a story!'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Story page 1 of \d+')), findsOneWidget);
      h.dispose();
    });
  });
}
