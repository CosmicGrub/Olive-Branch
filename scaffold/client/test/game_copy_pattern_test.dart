// OLIVE BRANCH — game_copy_pattern.dart tests. MASTERFILE §9.2, §8.11.1,
// §8.13, §8.4, P2.
//
// Mirrors this codebase's established depth: real pure-engine correctness
// (growth, tap-checking, and the wrong-tap "reset input progress only" case
// this file's own header names by name), the zero-text-gameplay claim
// checked directly (no tile's reference `name` is ever visible static
// label text), the device-adaptive structural test (layout ROOT Column vs
// Row — this activity changes LAYOUT, not content, unlike Find It), the P2
// forbidden-vocabulary sweep, and real navigation reachability from
// child_home.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_copy_pattern.dart';
import 'package:olive_client/game_picker.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A fully deterministic stand-in for `Random`. Tests need to know, in
/// advance, exactly which tile each `growPattern()` call will choose —
/// something a seeded `Random(n)` cannot promise cheaply without re-deriving
/// this file's own call order. Cycles through a fixed list of tile indices
/// instead, one `nextInt()` call at a time, regardless of `max`.
class _SequenceRandom implements Random {
  _SequenceRandom(this._sequence);
  final List<int> _sequence;
  int _i = 0;
  @override
  int nextInt(int max) => _sequence[_i++ % _sequence.length];
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// Zero every injectable delay — instant, deterministic playback.
CopyPatternScreen _screen({required Random random, String childName = 'Ivy'}) => CopyPatternScreen(
      childName: childName,
      random: random,
      highlightDuration: Duration.zero,
      stepGap: Duration.zero,
      wrongPauseDuration: Duration.zero,
    );

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
    await t.pumpAndSettle();
    expect(find.text('Copy the pattern'), findsOneWidget);
  });

  group('pure engine — pattern growth and tap checking', () {
    test('firstPattern is exactly one tile long', () {
      expect(firstPattern(_SequenceRandom(<int>[2])), <int>[2]);
    });

    test('growPattern appends exactly one more tile, keeping the prefix untouched', () {
      expect(growPattern(<int>[0, 1], _SequenceRandom(<int>[3])), <int>[0, 1, 3]);
    });

    test('checkTap: a correct, not-yet-last tile continues the round', () {
      expect(checkTap(pattern: <int>[0, 1, 2], inputCount: 0, tappedIndex: 0), TapOutcome.correctContinue);
    });

    test('checkTap: the correct LAST tile completes the round', () {
      expect(
          checkTap(pattern: <int>[0, 1, 2], inputCount: 2, tappedIndex: 2), TapOutcome.correctRoundComplete);
    });

    test('checkTap: a mismatched tile is wrong, regardless of position', () {
      expect(checkTap(pattern: <int>[0, 1, 2], inputCount: 1, tappedIndex: 3), TapOutcome.wrong);
    });

    test('every tile a real pattern generates is a valid patternTiles index', () {
      final _SequenceRandom r = _SequenceRandom(<int>[0, 1, 2, 3]);
      List<int> p = firstPattern(r);
      for (var i = 0; i < 10; i++) {
        p = growPattern(p, r);
      }
      for (final int idx in p) {
        expect(idx, inInclusiveRange(0, patternTiles.length - 1));
      }
    });

    test('there are exactly four tiles, each with a distinct color AND a distinct icon', () {
      expect(patternTiles.length, 4);
      expect(patternTiles.map((t) => t.color).toSet().length, 4);
      expect(patternTiles.map((t) => t.icon).toSet().length, 4);
    });
  });

  group('the widget — a genuinely growing pattern, tapped back on the tap-grid', () {
    testWidgets('after the first (instant) playback, the game is waiting for input at length 1', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(find.text('Your turn, Ivy — tap it back!'), findsOneWidget);
      expect(find.text('Pattern length: 1'), findsOneWidget);
    });

    testWidgets('tapping the single correct tile completes round 1 and GROWS the pattern to length 2', (t) async {
      // First pattern = [0] (consumes index 0); growing it on completion
      // consumes index 1 next -> [0, 1].
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0, 1]))));
      await t.pumpAndSettle();
      expect(find.text('Pattern length: 1'), findsOneWidget);

      await t.tap(find.byKey(const Key('patternTile-0')));
      await t.pumpAndSettle();
      expect(find.text('Pattern length: 2'), findsOneWidget);
      expect(find.text('Your turn, Ivy — tap it back!'), findsOneWidget);
    });

    testWidgets('a wrong tap resets INPUT PROGRESS ONLY — the pattern never shrinks or restarts at 1', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0, 1]))));
      await t.pumpAndSettle();
      expect(find.text('Pattern length: 1'), findsOneWidget);

      // pattern[0] is tile 0 — tap the WRONG one (tile 1) instead.
      await t.tap(find.byKey(const Key('patternTile-1')));
      await t.pump();
      expect(find.text("Let's watch that again!"), findsOneWidget);
      await t.pumpAndSettle();

      // The SAME pattern (still length 1, no growth consumed) replays.
      expect(find.text('Pattern length: 1'), findsOneWidget);
      expect(find.text('Your turn, Ivy — tap it back!'), findsOneWidget);

      // Tapping the ORIGINAL correct tile now completes it and grows the
      // pattern for the first time — proving the earlier wrong tap never
      // consumed a growth step or otherwise mutated the pattern.
      await t.tap(find.byKey(const Key('patternTile-0')));
      await t.pumpAndSettle();
      expect(find.text('Pattern length: 2'), findsOneWidget);
    });

    testWidgets('a tap outside the input phase is ignored — no exception, no state change', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      // Immediately after pump, before pumpAndSettle flushes the (zero-
      // duration but still async) playback chain, a tap must be a safe no-op.
      await t.tap(find.byKey(const Key('patternTile-0')));
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('zero-text gameplay — the actual minAge-2 accessibility mechanism', () {
    testWidgets('no tile\'s reference name is ever shown as static on-screen label text', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      for (final PatternTile tile in patternTiles) {
        expect(find.text(tile.name), findsNothing, reason: tile.name);
      }
    });

    testWidgets('all four tap targets exist and are reachable by key alone, no reading required', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      for (var i = 0; i < patternTiles.length; i++) {
        expect(find.byKey(Key('patternTile-$i')), findsOneWidget);
      }
    });
  });

  group('P2 — nothing here counts, ranks, or scores anything', () {
    testWidgets('none of the forbidden score/streak vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0, 1, 2]))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('patternTile-0')));
      await t.pumpAndSettle();
      for (final String word in <String>[
        'score', 'streak', 'rank', 'best', 'high score', 'level up', 'win', 'lose', 'lost',
      ]) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('no settings, price, or purchase affordance exists', (t) async {
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.textContaining(RegExp('buy|purchase', caseSensitive: false)), findsNothing);
    });
  });

  group('device-adaptive layout — pattern display and tap-grid genuinely change placement', () {
    testWidgets('at foldCover width (344px) display and grid are stacked (Column)', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());
      expect(find.byKey(const Key('patternDisplaySide')), findsNothing);
      expect(t.takeException(), isNull);

      // A real regression guard: the narrow Column must stretch its
      // children to the full available width, not just avoid overflow.
      // Without an explicit `crossAxisAlignment: stretch`, a bare Column
      // gives its children LOOSE width constraints, and
      // `_PatternDisplay`'s Container would shrink-wrap to its narrowest
      // line of text (well under 100px) instead of filling the screen.
      final double panelWidth = t.getSize(find.byKey(const Key('patternDisplayPanel'))).width;
      expect(panelWidth, greaterThan(250),
          reason: 'the display panel must fill the available width, not shrink-wrap its content');
    });

    testWidgets('at a wide posture (900px, 2+ columns) display and grid sit side by side (Row)', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
      expect(find.byKey(const Key('patternDisplaySide')), findsOneWidget);
      expect(find.byKey(const Key('tapGridSide')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_screen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Copy the pattern -> the real CopyPatternScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('Copy the pattern'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Copy the pattern'));
      await t.pumpAndSettle();
      expect(find.byType(CopyPatternScreen), findsOneWidget);

      // Reached via child_home.dart's real wiring, so this is the REAL
      // widget with its default (non-zero) playback durations, not this
      // file's zero-duration `_screen()` helper. pumpAndSettle() alone
      // does not reliably pump PAST a bare `Future.delayed` that has no
      // frame scheduled while it waits — the same reason
      // game_tictactoe_test.dart explicitly flushes a still-pending
      // simulated-delay timer rather than trusting pumpAndSettle to find
      // it. Force well past the whole playback chain so no timer is left
      // pending when the test ends.
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
    });
  });
}
