// OLIVE BRANCH — the shared calm notice, the rematch bar and Finish for now, as widgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect4_play.dart';
import 'package:olive_client/play_notice.dart';
import 'package:olive_client/play_session.dart';
import 'package:olive_client/play_widgets.dart';

import 'play_harness.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// Two devices that have just finished a Connect 4 game.
Future<TwoDevices<Connect4PlayGame>> _finished() async {
  final t = TwoDevices<Connect4PlayGame>(connect4Spec);
  await t.start();
  for (var i = 0; i < 3; i++) {
    t.dealerGame.tapColumn(0);
    await pumpEventQueue();
    t.guestGame.tapColumn(1);
    await pumpEventQueue();
  }
  t.dealerGame.tapColumn(0);
  await pumpEventQueue();
  return t;
}

void main() {
  group('PlaySessionNotice', () {
    testWidgets('away shows the one calm line, with no error icon and no button', (tester) async {
      await tester.pumpWidget(_wrap(const PlaySessionNotice(kind: PlayNoticeKind.away)));
      expect(find.text(kPlayAwayLine), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.wifi_off_outlined), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('ended shows its line and, when asked, a single Okay', (tester) async {
      var left = 0;
      await tester.pumpWidget(_wrap(PlaySessionNotice(kind: PlayNoticeKind.ended, onLeave: () => left++)));
      expect(find.text(kPlayEndedLine), findsOneWidget);
      await tester.tap(find.text(kPlayOkay));
      expect(left, 1);
    });

    testWidgets('none draws nothing', (tester) async {
      await tester.pumpWidget(_wrap(const PlaySessionNotice(kind: PlayNoticeKind.none)));
      expect(find.byType(Text), findsNothing);
    });

    test('the lines carry no names, digits or countdowns', () {
      for (final s in playNoticeStrings()) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
      }
    });
  });

  group('PlayAwayBanner', () {
    testWidgets('appears while the other device is away and goes when it is back, never replacing the game', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async {
        t = TwoDevices<Connect4PlayGame>(connect4Spec);
        await t.start();
      });
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(ListenableBuilder(
        listenable: t.guest,
        builder: (c, _) => Column(mainAxisSize: MainAxisSize.min, children: [PlayAwayBanner(session: t.guest), const Text('the board')]),
      )));
      expect(find.text(kPlayAwayLine), findsNothing);
      await tester.runAsync(() async {
        t.guestT.setLinked(false);
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text(kPlayAwayLine), findsOneWidget);
      expect(find.text('the board'), findsOneWidget);
      await tester.runAsync(() async {
        t.guestT.setLinked(true);
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text(kPlayAwayLine), findsNothing);
    });
  });

  group('PlayRematchBar', () {
    testWidgets('offers Play again; asking shows the quiet "asked" line with Never mind; the other side is offered a choice', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async => t = await _finished());
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(Column(mainAxisSize: MainAxisSize.min, children: [
        ListenableBuilder(listenable: t.guest, builder: (c, _) => PlayRematchBar(session: t.guest)),
        ListenableBuilder(listenable: t.dealer, builder: (c, _) => PlayRematchBar(session: t.dealer)),
      ])));
      expect(find.text(kPlayAgain), findsNWidgets(2));
      await tester.runAsync(() async {
        await t.guest.askRematch();
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text(kPlayRematchAsked), findsOneWidget);
      expect(find.text(kPlayRematchNeverMind), findsOneWidget);
      expect(find.text(kPlayRematchOffered), findsOneWidget);
      expect(find.text(kPlayRematchYes), findsOneWidget);
      expect(find.text(kPlayRematchNotNow), findsOneWidget);
      // "Not now" is quiet: the asker still just sees that it asked.
      await tester.tap(find.text(kPlayRematchNotNow));
      await tester.pump();
      expect(find.text(kPlayRematchAsked), findsOneWidget);
      expect(t.dealer.rematch, PlayRematch.none);
    });

    testWidgets('Yes starts a fresh game on both devices', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async => t = await _finished());
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(ListenableBuilder(listenable: t.dealer, builder: (c, _) => PlayRematchBar(session: t.dealer))));
      await tester.runAsync(() async {
        await t.guest.askRematch();
        await pumpEventQueue();
      });
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text(kPlayRematchYes));
        await pumpEventQueue();
      });
      expect(t.guestGame.finished, isFalse);
      expect(t.dealerGame.finished, isFalse);
    });
  });

  group('PlayFinishButton', () {
    testWidgets('asks first, in the same calm voice, and Keep playing changes nothing', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async {
        t = TwoDevices<Connect4PlayGame>(connect4Spec);
        await t.start();
      });
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(PlayFinishButton(session: t.guest)));
      await tester.tap(find.byTooltip(kPlayFinishForNow));
      await tester.pumpAndSettle();
      expect(find.text(kPlayFinishBody), findsOneWidget);
      await tester.tap(find.text(kPlayKeepPlaying));
      await tester.pumpAndSettle();
      expect(t.guest.endedForGood, isFalse);
    });

    testWidgets('Finish for now ends both devices calmly', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async {
        t = TwoDevices<Connect4PlayGame>(connect4Spec);
        await t.start();
      });
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(PlayFinishButton(session: t.guest)));
      await tester.tap(find.byTooltip(kPlayFinishForNow));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, kPlayFinishForNow));
      await tester.pumpAndSettle();
      await tester.runAsync(() => pumpEventQueue());
      expect(t.guest.endedForGood, isTrue);
      expect(t.dealer.endedForGood, isTrue);
    });

    testWidgets('is not there before the other device has ever been found', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async {
        t = TwoDevices<Connect4PlayGame>(connect4Spec);
        t.guestT.setLinked(false);
      });
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(PlayFinishButton(session: t.guest)));
      expect(find.byType(IconButton), findsNothing);
    });
  });
}
