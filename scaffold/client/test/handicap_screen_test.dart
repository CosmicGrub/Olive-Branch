// OLIVE BRANCH — handicap picker tests. §9.2: the child sets it, never the
// parent; the picker itself never renders the losing-streak record that may
// have triggered it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/handicap_screen.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

void main() {
  group('handicap screen — §9.2', () {
    testWidgets('offers exactly the ported catalogue handicaps for that game', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      expect(find.text("Dad can't use the middle square"), findsOneWidget);
      expect(find.text('I always go first'), findsOneWidget);
      expect(find.text('Play it straight — no handicap'), findsOneWidget);
    });

    testWidgets('the framing is a question to her, never a statement about a record', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      expect(find.textContaining('Want to make it harder'), findsOneWidget);
    });

    testWidgets('the losing-streak record is never rendered, in any form', (t) async {
      // "in a row" is deliberately excluded: the catalogue's own title is
      // "Three in a row" (tic-tac-toe), legitimate ported copy, not a streak.
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      for (final forbidden in ['streak', 'lost', 'losing', 'record', '3 games', 'win']) {
        expect(
          find.textContaining(RegExp(forbidden, caseSensitive: false)),
          findsNothing,
          reason: '"$forbidden" must never appear on the handicap screen',
        );
      }
    });

    testWidgets('exactly one option is selected by default (play it straight)', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('choosing an option selects it and calls onChanged with its id', (t) async {
      String? changed = 'unset';
      await t.pumpWidget(wrap(HandicapScreen(kind: GameKind.tictactoe, onChanged: (id) => changed = id)));
      await t.tap(find.text("Dad can't use the middle square"));
      await t.pumpAndSettle();
      expect(changed, 'no_centre');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('choosing "play it straight" clears a previously-set handicap', (t) async {
      String? changed = 'unset';
      await t.pumpWidget(wrap(HandicapScreen(
        kind: GameKind.tictactoe,
        currentHandicapId: 'no_centre',
        onChanged: (id) => changed = id,
      )));
      await t.tap(find.text('Play it straight — no handicap'));
      await t.pumpAndSettle();
      expect(changed, isNull);
    });

    testWidgets('a previously-set handicap preselects instead of resetting silently', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe, currentHandicapId: 'no_centre')));
      await t.pumpAndSettle();
      expect(find.textContaining('playing the hard way'), findsOneWidget);
    });

    testWidgets('the banner is phrased as the hard way once a handicap is chosen, never as a deficiency',
        (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      await t.tap(find.text('I always go first'));
      await t.pumpAndSettle();
      expect(find.textContaining('playing the hard way'), findsOneWidget);
      expect(find.textContaining('worse'), findsNothing);
    });

    testWidgets('a co-op game offers no handicap options — nothing to be behind at', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.story)));
      expect(find.textContaining('together game'), findsOneWidget);
      expect(find.text('Play it straight — no handicap'), findsOneWidget);
    });

    testWidgets('NO settings affordance and no role-switch exists anywhere', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining("I'm the grown-up"), findsNothing);
      expect(find.textContaining('Switch role'), findsNothing);
      expect(find.textContaining('Parent mode'), findsNothing);
    });

    testWidgets('handicap tiles meet the 48dp+ touch target minimum', (t) async {
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.tictactoe)));
      final size = t.getSize(find.byType(InkWell).first);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.dotsboxes)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.dotsboxes)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (~390 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.dotsboxes)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (~1100 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandicapScreen(kind: GameKind.dotsboxes)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('setHandicap — enforced independent of any UI (§9.2 refusal)', () {
    test('a parent role can never set a handicap, even calling the function directly', () {
      final r = setHandicap(bySide: Side.b, kind: GameKind.tictactoe, handicapId: 'no_centre');
      expect(r.ok, isFalse);
      expect(r.refusal, HandicapRefusal.childOnly);
    });
  });
}
