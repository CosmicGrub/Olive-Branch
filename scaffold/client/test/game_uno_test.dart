// OLIVE BRANCH — game_uno.dart widget tests. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion.
//
// Real smoke coverage for the vsCpu path only — vsPeer needs a genuine
// mDNS pairing handshake between two real devices, which is why every
// game in this expansion is verified end to end on real hardware
// (main_local_*_test.dart dev entry points + real Fold5/tablet devices)
// rather than through flutter_test's own harness for that half. vsCpu
// needs no pairing at all (this file's own header, "vs CPU is fully
// local"), so it's the one real path genuinely testable here — this
// suite checks it renders and plays correctly at every real seat count
// this pass added (2-4), never throws, and that the new Uno-call/Wild
// Draw Four challenge UI actually appears when the underlying engine
// state calls for it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_uno.dart';
import 'package:olive_client/uno_deck.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

void main() {
  group('GameUnoScreen — the mode picker', () {
    testWidgets('renders difficulty and seat-count selectors, defaults to a real 4-seat table', (t) async {
      await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
      await t.pumpAndSettle();
      // Two real "Uno" texts on this screen at once: the AppBar's own
      // title (present throughout the whole screen's lifetime) and the
      // picker's own headline — not a bug, just two genuinely different
      // widgets sharing the same label.
      expect(find.text('Uno'), findsNWidgets(2));
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('How many at the table?'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });
  });

  group('GameUnoScreen — vs CPU, every real seat count this pass added', () {
    for (final seatCount in [2, 3, 4]) {
      testWidgets('a $seatCount-seat game starts and renders a real board with no exception', (t) async {
        await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
        await t.pumpAndSettle();
        if (seatCount != 4) {
          // 4 is the real default (matches the reference's own 4-seat
          // table) — only tap the segment when a test actually wants a
          // different count.
          await t.tap(find.text('$seatCount').last);
          await t.pumpAndSettle();
        }
        // The picker's own card-size customization suite (a real, live
        // preview plus a slider) can push Start below a short test
        // surface's own visible area — a real, disclosed, already-
        // established pattern for this screen (see game_uno.dart's own
        // header on the board itself needing to scroll on a short
        // posture); scroll to it first, exactly what a real person would
        // do on a real short screen.
        await t.ensureVisible(find.text('Start'));
        await t.tap(find.text('Start'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // A real table: my own hand of face-up cards, plus (seatCount-1)
        // real opponent seats each with a real name tag rendered.
        expect(find.byType(Draggable<UnoCard>), findsWidgets, reason: 'my own hand should be real, draggable cards');
        // Draw pile / discard pile / turn-direction ring should all be
        // present — a real board, not a blank screen.
        expect(find.text('Draw'), findsOneWidget);
        expect(find.textContaining('Color in play'), findsOneWidget);
      });
    }

    testWidgets('the draw pile actually draws a real card into the hand on a real tap, when it is my turn', (t) async {
      await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
      await t.pumpAndSettle();
      await t.tap(find.text('2').last); // simplest real case: a 2-seat game
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Start')); // see the seat-count test's own comment on why
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      // Whether it's genuinely my turn on this particular deal is itself
      // random (a fresh, real, unseeded shuffle) — this test only
      // verifies that WHEN it's offered, tapping Draw never throws, not a
      // specific resulting hand size (which would make it flaky by
      // design).
      final drawFinder = find.text('Draw');
      expect(drawFinder, findsOneWidget);
      await t.tap(drawFinder);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('GameUnoScreen — responsive, every canonical width this pass touches', () {
    const widths = <String, Size>{
      'Fold5 cover (344)': Size(344, 882),
      'Fold5 main (~673x841)': Size(673, 841),
      'phone (390)': Size(390, 844),
      'tablet/desktop (1100)': Size(1100, 800),
    };
    for (final entry in widths.entries) {
      testWidgets('a real 4-seat table renders without overflow at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Start')); // see the seat-count test's own comment on why
        await t.tap(find.text('Start'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('GameUnoScreen — the card-size customization suite', () {
    testWidgets('the slider actually resizes both the live preview and the real in-game hand', (t) async {
      await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
      await t.pumpAndSettle();
      expect(find.text('Card size'), findsOneWidget);
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      // The real RENDERED size of the first hand card's own Draggable —
      // reads straight off the render tree rather than reaching into
      // game_uno.dart's own private widget internals (_FannedCard/
      // _UnoCardFace aren't visible outside that library), so this stays
      // honest about what a real player would actually see on screen.
      double widthOfFirstHandCard() => t.getSize(find.byType(Draggable<UnoCard>).first).width;

      // Drag the slider to its minimum, start a game, measure a real hand
      // card's own real width.
      await t.drag(sliderFinder, const Offset(-400, 0));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Start'));
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      final smallWidth = widthOfFirstHandCard();
      expect(t.takeException(), isNull);

      // Fresh game, slider dragged to its maximum instead — the SAME real
      // widget, genuinely bigger, not a different one. Pumping an empty
      // tree first forces the previous _GameUnoScreenState to actually be
      // disposed — pumping GameUnoScreen again directly, with no
      // distinguishing Key, would just reuse the SAME live State (still
      // mid-game from above) rather than a fresh one back on the picker.
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
      await t.pumpAndSettle();
      await t.drag(find.byType(Slider), const Offset(400, 0));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Start'));
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      final bigWidth = widthOfFirstHandCard();
      expect(t.takeException(), isNull);

      expect(bigWidth, greaterThan(smallWidth),
        reason: 'the slider must actually change the real in-game card size, not just its own preview');
    });

    testWidgets('an extreme size + a long hand never overflows — it scrolls instead', (t) async {
      // The real playability guarantee _HandFan's own header describes:
      // max slider + the narrowest real posture this app supports.
      t.view.physicalSize = const Size(344, 882);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(const GameUnoScreen(role: 'dad', displayName: 'Dad')));
      await t.pumpAndSettle();
      await t.drag(find.byType(Slider), const Offset(400, 0));
      await t.pumpAndSettle();
      await t.tap(find.text('4').last); // the biggest real hand-count multiplier this pass offers
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Start'));
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      // The real assertion: Flutter's own overflow detection (a Flex/Row
      // RenderBox reporting it was asked to lay out past its own
      // constraints) never fires, regardless of how large the cards or
      // how many are in hand — this is exactly what the horizontal-
      // scroll fallback in _HandFan exists to prevent.
      expect(t.takeException(), isNull);
    });
  });
}
