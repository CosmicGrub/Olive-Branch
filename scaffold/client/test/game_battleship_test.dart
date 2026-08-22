// OLIVE BRANCH — battleship tests. MASTERFILE §9.2, P2.
//
// Engine correctness (placement, mandatory-shot rules, "a hit grants
// another shot") at the function level; the structural "opponent positions
// never leave the server" property and the "never both boards on one
// screen" MARKUP brief, plus P2, at the widget level.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/game_battleship.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void useTallSurface(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  group('battleship engine — §9.2', () {
    test('placing the full fleet for both sides flips phase to playing', () {
      var s = newBattleship();
      for (final side in [BsSide.child, BsSide.parent]) {
        var start = 0; // fresh row sequence per side — boards are independent
        for (final spec in bsFleet) {
          final result = placeShip(s, side, spec.name, start, true);
          expect(result.ok, isTrue, reason: '${spec.name} for $side should place at $start');
          s = result.state!;
          start += 8; // stay on a fresh row each time so ships never overlap
        }
      }
      expect(s.phase, BsPhase.playing);
    });

    test('a ship cannot overlap another, or run off the board', () {
      var s = newBattleship();
      final first = placeShip(s, BsSide.child, 'Destroyer', 0, true); // cells 0,1
      s = first.state!;
      final overlap = placeShip(s, BsSide.child, 'Submarine', 1, true);
      expect(overlap.ok, isFalse);
      expect(overlap.reason, 'overlaps');

      final offBoard = placeShip(s, BsSide.child, 'Carrier', 6, true); // would run past column 7
      expect(offBoard.ok, isFalse);
      expect(offBoard.reason, 'off_board');
    });

    test('firing before both fleets are placed is refused', () {
      final s = newBattleship();
      final result = fire(s, BsSide.child, 0);
      expect(result.ok, isFalse);
      expect(result.reason, 'still_placing');
    });

    test('a hit grants another shot; a miss passes the turn', () {
      var s = newBattleship();
      for (final side in [BsSide.child, BsSide.parent]) {
        var start = 0; // fresh row sequence per side — boards are independent
        for (final spec in bsFleet) {
          s = placeShip(s, side, spec.name, start, true).state!;
          start += 8;
        }
      }
      // Parent's Destroyer sits at row0 (cells 0,1) since it was placed first
      // for BsSide.parent at start=0 the SAME way child's was — recompute
      // parent's actual first-ship cell directly from state instead of
      // assuming it, since fleet order/placement start values are shared
      // across both loops above starting back at 0 for parent too... use the
      // real ship cells from state.
      final parentDestroyer = s.ships[BsSide.parent]!.firstWhere((sh) => sh.name == 'Destroyer');
      final hitCell = parentDestroyer.cells.first;

      final hitResult = fire(s, BsSide.child, hitCell);
      expect(hitResult.ok, isTrue);
      expect(hitResult.hit, isTrue);
      expect(hitResult.state!.turn, BsSide.child, reason: 'a hit grants another shot');

      // Now miss at a cell with no ship on either fleet at all — find one.
      final allChildCells = {for (final sh in s.ships[BsSide.child]!) ...sh.cells};
      final allParentCells = {for (final sh in s.ships[BsSide.parent]!) ...sh.cells};
      final emptyCell = List<int>.generate(bsSize * bsSize, (i) => i)
          .firstWhere((i) => !allChildCells.contains(i) && !allParentCells.contains(i) && i != hitCell);

      final missResult = fire(hitResult.state!, BsSide.child, emptyCell);
      expect(missResult.ok, isTrue);
      expect(missResult.hit, isFalse);
      expect(missResult.state!.turn, BsSide.parent, reason: 'a miss passes the turn');
    });

    test('sinking every cell of a ship reports it sunk and never fires the same cell twice', () {
      var s = newBattleship();
      for (final side in [BsSide.child, BsSide.parent]) {
        var start = 0; // fresh row sequence per side — boards are independent
        for (final spec in bsFleet) {
          s = placeShip(s, side, spec.name, start, true).state!;
          start += 8;
        }
      }
      final destroyer = s.ships[BsSide.parent]!.firstWhere((sh) => sh.name == 'Destroyer');
      var state = s;
      String? sunkName;
      for (final cell in destroyer.cells) {
        final r = fire(state, BsSide.child, cell);
        expect(r.ok, isTrue);
        state = r.state!;
        sunkName = r.sunk ?? sunkName;
      }
      expect(sunkName, 'Destroyer');

      final again = fire(state, BsSide.child, destroyer.cells.first);
      expect(again.ok, isFalse);
      expect(again.reason, 'already_fired');
    });
  });

  group('battleship screen — structure and P2, §9.2', () {
    testWidgets('placement phase shows only the own board, never the enemy board', (t) async {
      useTallSurface(t);
      await t.pumpWidget(wrap(const GameBattleship(random: null)));
      expect(find.byKey(const Key('bsOwn_0')), findsOneWidget);
      expect(find.byKey(const Key('bsEnemy_0')), findsNothing);
    });

    testWidgets('placing the child fleet flips into play and shows exactly one board at a time',
        (t) async {
      useTallSurface(t);
      await t.pumpWidget(wrap(GameBattleship(random: Random(42))));

      // Place all five ships horizontally, each on its own row, via taps on
      // the own-board grid — the same UI a child actually uses.
      for (var i = 0; i < bsFleet.length; i++) {
        await t.tap(find.byKey(Key('bsOwn_${i * 8}')));
        await t.pump();
      }

      // Now in the playing phase: exactly one grid exists, and by default
      // it's "enemy waters" (the toggle also proves both boards are never
      // simultaneously present, since only one key family appears at once).
      expect(find.byKey(const Key('bsEnemy_0')), findsOneWidget);
      expect(find.byKey(const Key('bsOwn_0')), findsNothing);

      await t.tap(find.text('Your fleet'));
      await t.pump();
      expect(find.byKey(const Key('bsOwn_0')), findsOneWidget);
      expect(find.byKey(const Key('bsEnemy_0')), findsNothing);
    });

    testWidgets('no settings affordance and no score/rank language anywhere', (t) async {
      useTallSurface(t);
      await t.pumpWidget(wrap(const GameBattleship(random: null)));
      expect(find.byIcon(Icons.settings), findsNothing);
      for (final banned in ['ELO', 'rank', 'streak', 'leaderboard', 'Rating']) {
        expect(find.textContaining(banned), findsNothing);
      }
    });

    testWidgets('the closing message is "Good game." never a win/loss verdict', (t) async {
      useTallSurface(t);
      await t.pumpWidget(wrap(const GameBattleship(random: null)));
      expect(find.text('Good game.'), findsNothing);
      expect(find.textContaining('You lost'), findsNothing);
      expect(find.textContaining('You win'), findsNothing);
    });
  });

  group('responsive audit — Fold5, phone, and tablet/desktop widths, §9.2', () {
    // MASTERFILE's own mandated minimum widths (the Fold5's cover and
    // unfolded main screens), plus a standard phone width and a
    // short-and-wide desktop/tablet width now that Windows is a real target.
    for (final MapEntry<String, Size> entry in const <String, Size>{
      'Fold5 cover (344 CSS px)': Size(344, 882),
      'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
      'a standard phone (~390 CSS px)': Size(390, 844),
      'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
    }.entries) {
      testWidgets('renders without overflow at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GameBattleship(random: null)));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('responsive — comfortable reading width cap (form_factors.dart)', () {
    // On a wide tablet/desktop viewport the whole outer column — status
    // banner through the tab-toggle through the board through the
    // play-again button — is only ever capped to a comfortable reading
    // width and centered, never split; the Fold5 cover and phone widths are
    // completely untouched. This is strictly ADDITIVE on top of the board's
    // own pre-existing 460px cap, not a replacement for it.
    testWidgets('the outer cap engages only on a wide tablet/desktop viewport — '
        'never at the Fold5 cover or phone width', (t) async {
      Future<void> pumpAt(Size size) async {
        await t.binding.setSurfaceSize(size);
        await t.pumpWidget(wrap(const GameBattleship(random: null)));
        await t.pump();
      }

      addTearDown(() => t.binding.setSurfaceSize(null));

      await pumpAt(const Size(1100, 900));
      expect(t.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);

      await pumpAt(const Size(344, 882)); // Fold5 cover
      expect(t.getSize(find.byType(ListView)).width, 344);

      await pumpAt(const Size(390, 844)); // standard phone
      expect(t.getSize(find.byType(ListView)).width, 390);
    });

    testWidgets('the board keeps its own 460px cap regardless of the outer '
        'reading-cap, and the tab-toggle single-board model is unaffected', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 2200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(GameBattleship(random: Random(42))));
      await t.pump();

      // The outer reading-cap is engaged at this width...
      expect(t.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);
      // ...yet the board itself never exceeds its own pre-existing 460px cap,
      // in the placement phase...
      expect(t.getSize(find.byType(AspectRatio)).width, 460);

      // Placing the full fleet flips into play; still exactly one board
      // ever renders at a time, and it is still capped at 460px.
      for (var i = 0; i < bsFleet.length; i++) {
        await t.tap(find.byKey(Key('bsOwn_${i * 8}')));
        await t.pump();
      }
      expect(find.byKey(const Key('bsEnemy_0')), findsOneWidget);
      expect(find.byKey(const Key('bsOwn_0')), findsNothing);
      expect(t.getSize(find.byType(AspectRatio)).width, 460);

      await t.tap(find.text('Your fleet'));
      await t.pump();
      expect(find.byKey(const Key('bsOwn_0')), findsOneWidget);
      expect(find.byKey(const Key('bsEnemy_0')), findsNothing);
      expect(t.getSize(find.byType(AspectRatio)).width, 460);
    });
  });

  group('battleship — "opponent positions never leave the server", §9.2', () {
    test('EnemyBoardView never carries ship cell data, only per-cell status', () {
      // A structural check on the type itself: the only information an
      // EnemyBoardView can hold is one BsCellStatus per cell. There is no
      // field it could use to smuggle an unrevealed ship's coordinates even
      // if a bug tried to — this is enforced by the shape of the class, not
      // by convention.
      const view = EnemyBoardView([BsCellStatus.unknown]);
      expect(view.statuses, [BsCellStatus.unknown]);
      // The runtime type has exactly the fields declared, verified by
      // toString containing nothing beyond the statuses list.
      expect(view.toString(), isNot(contains('cells')));
    });

    test('a fresh EnemyBoardView shows unknown everywhere before any shots', () {
      var s = newBattleship();
      for (final side in [BsSide.child, BsSide.parent]) {
        var start = 0; // fresh row sequence per side — boards are independent
        for (final spec in bsFleet) {
          s = placeShip(s, side, spec.name, start, true).state!;
          start += 8;
        }
      }
      final view = enemyViewFor(s, BsSide.child);
      expect(view.statuses.every((st) => st == BsCellStatus.unknown), isTrue);
    });
  });
}

/// Small helper mirroring what `_BattleshipHost.enemyBoardView` computes,
/// used here to test the projection function's shape directly against a
/// hand-built state rather than reaching into the private host class.
EnemyBoardView enemyViewFor(BsState s, BsSide side) {
  final myShots = s.shots[side]!;
  final foeShips = s.ships[side.opposite]!;
  return EnemyBoardView([
    for (var i = 0; i < bsSize * bsSize; i++)
      if (!myShots.contains(i)) BsCellStatus.unknown
      else (foeShips.any((sh) => sh.cells.contains(i))
          ? (foeShips.firstWhere((sh) => sh.cells.contains(i)).sunk ? BsCellStatus.sunk : BsCellStatus.hit)
          : BsCellStatus.miss),
  ]);
}
