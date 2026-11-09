import 'dart:async';
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

  group('two voices: soft for the child, plain for the adult', () {
    const banned = ['error', 'failed', 'sorry', 'oops', 'lost', 'declined', 'refused', 'rejected', 'timed out', 'disconnected', 'hurry', 'wait'];

    test('the child voice has no digits, names, error words or blame, and never tells a no', () {
      for (final s in PlayWords.child.all()) {
        final lower = s.toLowerCase();
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
        expect(lower.contains('ivy'), isFalse, reason: s);
        for (final b in banned) {
          expect(lower.contains(b), isFalse, reason: '"$b" in "$s"');
        }
      }
      expect(PlayWords.child.rematchNotNow, 'Not now');
      expect(PlayWords.child.away, 'Your game is resting. It will wake up when you are together again.');
      expect(PlayWords.child.ended, 'All done for now. We can play again whenever you like.');
      expect(PlayWords.child.resumeFor('Uno'), 'Your Uno game is still here.');
    });

    test('the adult voice is the plain wording the owner chose', () {
      final a = PlayWords.adult;
      expect(a.away, 'The other device is out of range. The game is saved and will resume when it reconnects.');
      expect(a.ended, 'The game was ended. It is saved if you want to resume it.');
      expect(a.finishForNow, 'Finish for now');
      expect(a.keepPlaying, 'Keep playing');
      expect(a.finishBody, 'The game is saved. You can start a new one or resume it later.');
      expect(a.resumeFor('Uno'), 'A saved game of Uno was found on this device.');
      expect((a.resumeYes, a.resumeNo), ('Resume', 'Start a new game'));
      expect(a.rematchOffered, 'The other player asked to play again.');
      expect((a.rematchYes, a.rematchNotNow), ('Accept', 'Decline'));
      for (final s in a.all()) {
        expect(s.toLowerCase().contains('error'), isFalse, reason: s);
      }
    });

    testWidgets('no scope means the child voice; the adult scope switches every notice and button', (tester) async {
      await tester.pumpWidget(_wrap(const PlaySessionNotice(kind: PlayNoticeKind.away)));
      expect(find.text(PlayWords.child.away), findsOneWidget);
      await tester.pumpWidget(_wrap(const PlayAudienceScope(
          audience: PlayAudience.adult, child: PlaySessionNotice(kind: PlayNoticeKind.away))));
      expect(find.text(PlayWords.adult.away), findsOneWidget);
      expect(find.text(PlayWords.child.away), findsNothing);
      await tester.pumpWidget(_wrap(PlayAudienceScope(
          audience: PlayAudience.adult, child: PlaySessionNotice(kind: PlayNoticeKind.ended, onLeave: () {}))));
      expect(find.text(PlayWords.adult.ended), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('the adult rematch offer says Accept and Decline; the child still sees Yes and Not now', (tester) async {
      late TwoDevices<Connect4PlayGame> t;
      await tester.runAsync(() async => t = await _finished());
      addTearDown(t.dispose);
      await tester.pumpWidget(_wrap(ListenableBuilder(
          listenable: t.dealer,
          builder: (c, _) => PlayAudienceScope(audience: PlayAudience.adult, child: PlayRematchBar(session: t.dealer)))));
      await tester.runAsync(() async {
        await t.guest.askRematch();
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text('The other player asked to play again.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Yes'), findsNothing);
    });

    testWidgets('the saved-game question and Finish for now use the adult words under the adult scope', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: PlayAudienceScope(
          audience: PlayAudience.adult, child: Builder(builder: (c) { ctx = c; return const SizedBox(); }))));
      unawaited(askResumeSavedGame(ctx, 'Uno'));
      await tester.pumpAndSettle();
      expect(find.text('A saved game of Uno was found on this device.'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start a new game'), findsOneWidget);
    });
  });
}
