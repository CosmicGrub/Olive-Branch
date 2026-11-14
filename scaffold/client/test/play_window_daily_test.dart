// OLIVE BRANCH — the play window and daily time (the prototype's g-play and scenario `play`).
// No longer UNVERIFIED — verified by CI (this file). MASTERFILE §8.6.6, §8.1.
//
// Holds: the use-a-window switch (off = open all day), the order of the ending (rest time
// FIRST, wind-down AFTER it: the prototype's order, parity ledger rule playWindow.states),
// the live "on her tablet right now" line, the honest "nothing was sent" when a window is
// made longer, and the daily time total, now enforced on her device (daily_time_test.dart), with its plain description.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/daily_time_logic.dart';
import 'package:olive_client/daily_time_store.dart';
import 'package:olive_client/her_colour_store.dart';
import 'package:olive_client/home_plan_store.dart';
import 'package:olive_client/play_window_gate.dart';
import 'package:olive_client/play_window_screen.dart';

Future<void> _size(WidgetTester t, double w, {double h = 3000}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

MemoryColourStore _store({DateTime? at, PlayWindow? window}) =>
    MemoryColourStore(now: () => at ?? DateTime(2026, 11, 7, 16, 0), window: window);

void main() {
  const PlayWindow w = PlayWindow(opensMin: 7 * 60 + 30, restsMin: 19 * 60 + 30, windDownMin: 15);

  group('the order of the ending (scenario play): rest time first, wind-down after', () {
    test('open until the rest time, winding down for the tail that follows it, then resting until morning', () {
      String at(int h, int m) => playWindowState(w, h * 60 + m);
      expect(at(7, 29), 'resting', reason: 'before it opens');
      expect(at(7, 30), 'open');
      expect(at(19, 15), 'open', reason: '15 minutes BEFORE the rest time is still plain open (the old order wound down here)');
      expect(at(19, 29), 'open');
      expect(at(19, 30), 'winding_down', reason: 'the tail starts AT the rest time');
      expect(at(19, 44), 'winding_down');
      expect(at(19, 45), 'resting');
      expect(at(23, 59), 'resting');
    });

    test('wind-down off: the door closes at the rest time', () {
      const PlayWindow off = PlayWindow(opensMin: 450, restsMin: 1170, windDownMin: 0);
      expect(playWindowState(off, 1169), 'open');
      expect(playWindowState(off, 1170), 'resting');
    });

    test('a short window is fine: the tail is not inside it', () {
      expect(checkPlayWindow(const PlayWindow(opensMin: 600, restsMin: 615, windDownMin: 30).toJson()).ok, isTrue);
      expect(checkPlayWindow(const PlayWindow(opensMin: 600, restsMin: 600, windDownMin: 0).toJson()).reason, 'bad_restsMin');
    });

    testWidgets('the child\'s gate follows it: games stay through the tail with one calm line, then a goodnight', (t) async {
      Widget gate(MemoryColourStore s) => MaterialApp(home: PlayWindowGate(key: UniqueKey(), store: s, child: const Scaffold(body: Text('the games'))));
      await t.pumpWidget(gate(_store(at: DateTime(2026, 11, 7, 19, 20), window: w)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('windDownBanner')), findsNothing, reason: 'before the rest time: nothing yet');
      await t.pumpWidget(gate(_store(at: DateTime(2026, 11, 7, 19, 35), window: w)));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsOneWidget, reason: 'a game in progress is never cut off');
      expect(find.byKey(const Key('windDownBanner')), findsOneWidget);
      await t.pumpWidget(gate(_store(at: DateTime(2026, 11, 7, 19, 50), window: w)));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsNothing);
      expect(find.byKey(const Key('goodnightLine')), findsOneWidget);
    });
  });

  group('the guardian screen', () {
    Future<void> open(WidgetTester t, MemoryColourStore s, MemoryHomePlanRepository plan, {double width = 500}) async {
      await _size(t, width);
      await t.pumpWidget(MaterialApp(home: PlayWindowScreen(key: UniqueKey(), childName: 'Ivy', store: s, plan: plan)));
      await t.pumpAndSettle();
    }

    testWidgets('the title names both halves', (t) async {
      await open(t, _store(), MemoryHomePlanRepository());
      expect(find.text('Play window and daily time'), findsOneWidget);
    });

    testWidgets('use a play window: off by default (open all day), on offers the form and a timeline', (t) async {
      final MemoryColourStore s = _store();
      await open(t, s, MemoryHomePlanRepository());
      expect(find.text('Games are open all day'), findsOneWidget);
      expect(find.byKey(const Key('windowTimeline')), findsNothing);
      await t.tap(find.byKey(const Key('useWindow')));
      await t.pumpAndSettle();
      expect(find.text('Games follow the window below'), findsOneWidget);
      expect(find.byKey(const Key('windowTimeline')), findsOneWidget);
      expect(find.byKey(const Key('opensDrop')), findsOneWidget);
    });

    testWidgets('switching it off and saving clears the window: games are open all day again', (t) async {
      final MemoryColourStore s = _store(window: w);
      await open(t, s, MemoryHomePlanRepository());
      expect(find.text('Games follow the window below'), findsOneWidget);
      await t.tap(find.byKey(const Key('useWindow')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('saveWindow')));
      await t.pumpAndSettle();
      expect(find.text('Saved. Games are open all day.'), findsOneWidget);
      expect((await s.playWindow()).window, isNull);
      expect((await s.playWindow()).state, 'open');
    });

    testWidgets('the live line says what her tablet is doing right now, from the saved window', (t) async {
      await open(t, _store(at: DateTime(2026, 11, 7, 19, 35), window: w), MemoryHomePlanRepository());
      expect(find.text('On Ivy’s tablet right now: games are winding down'), findsOneWidget);
      await open(t, _store(at: DateTime(2026, 11, 7, 22, 0), window: w), MemoryHomePlanRepository());
      expect(find.text('On Ivy’s tablet right now: games are resting'), findsOneWidget);
    });

    testWidgets('what she sees is shown at the REST time, in her words, with nothing taken away', (t) async {
      await open(t, _store(window: w), MemoryHomePlanRepository());
      expect(find.text('What Ivy sees at 7:30 PM'), findsOneWidget);
      expect(find.byKey(const Key('windPreview')), findsOneWidget);
      expect(find.textContaining('Nothing is taken away. Games open again at 7:30 AM'), findsOneWidget);
      expect(find.textContaining('Calls and family messages are never affected'), findsWidgets);
    });

    testWidgets('making the window longer is saved, and says plainly that nothing was sent to the other guardian', (t) async {
      final MemoryColourStore s = _store(window: w);
      await open(t, s, MemoryHomePlanRepository());
      await t.tap(find.byKey(const Key('restsDrop')));
      await t.pumpAndSettle();
      await t.tap(find.text('9:00 PM').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('saveWindow')));
      await t.pumpAndSettle();
      final String note = t.widget<Text>(find.byKey(const Key('windNote'))).data!;
      expect(note, contains('longer than before'));
      expect(note, contains('nothing was sent'), reason: 'never fake a notification');
      expect((await s.playWindow()).window!.restsMin, 21 * 60);
    });

    testWidgets('a shorter window is saved with no such line', (t) async {
      final MemoryColourStore s = _store(window: w);
      await open(t, s, MemoryHomePlanRepository());
      await t.tap(find.byKey(const Key('restsDrop')));
      await t.pumpAndSettle();
      await t.tap(find.text('6:00 PM').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('saveWindow')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('windNote'))).data, 'Saved.');
    });

    testWidgets('daily time: off, 1, 2 or 3 hours; kept; a raise says the other guardian cannot be told yet', (t) async {
      final MemoryHomePlanRepository plan = MemoryHomePlanRepository();
      await open(t, _store(), plan);
      Finder seg(String label) => find.descendant(of: find.byKey(const Key('dailySeg')), matching: find.text(label));
      for (final String l in <String>['Off', '1 h', '2 h', '3 h']) {
        expect(seg(l), findsOneWidget, reason: l);
      }
      await t.ensureVisible(seg('1 h'));
      await t.tap(seg('1 h'));
      await t.pumpAndSettle();
      expect((await plan.load()).dailyHours, 1);
      expect(find.text('Saved on this device. A raise is something the other guardian will be told; that needs the network, which is not built yet.'), findsOneWidget);
      expect(find.text('You raised this from Off to 1 h.'), findsOneWidget);
      await t.tap(seg('Off'));
      await t.pumpAndSettle();
      expect((await plan.load()).dailyHours, 0);
      expect(find.byKey(const Key('dailyMsg')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('dailyMsg'))).data, 'Saved on this device.', reason: 'lowering is free and never reported');
    });

    testWidgets('daily time is honest about what it does: it rests her reading and watching, shows her no number, and is per device', (t) async {
      await open(t, _store(), MemoryHomePlanRepository());
      expect(find.textContaining('rest gently once it is used up'), findsOneWidget);
      expect(find.textContaining('She is never shown a number'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('dailyHonest'))).data, contains('are never touched by it'));
      expect(find.textContaining('needs the network, which is not built yet'), findsWidgets);
      expect(find.textContaining('do not count minutes yet'), findsNothing, reason: 'the old "nothing stops" line is gone');
    });

    testWidgets('with the total off there is no use line and no allow button; with it on the grown-up sees today\'s use on this device and can allow 30 more minutes', (t) async {
      final MemoryDayUseRepository usage = MemoryDayUseRepository(
          DayUse(day: localDayKey(DateTime(2026, 11, 7, 16)), seconds: 40 * 60));
      Future<void> openWith(MemoryHomePlanRepository plan) async {
        await _size(t, 500);
        await t.pumpWidget(MaterialApp(home: PlayWindowScreen(key: UniqueKey(), childName: 'Ivy', store: _store(), plan: plan,
            usage: usage, clock: () => DateTime(2026, 11, 7, 16))));
        await t.pumpAndSettle();
      }

      await openWith(MemoryHomePlanRepository());
      expect(find.byKey(const Key('dailyUsed')), findsNothing);
      expect(find.byKey(const Key('dailyAllowMoreHere')), findsNothing);

      await openWith(MemoryHomePlanRepository(const HomePlan(dailyHours: 1)));
      expect(t.widget<Text>(find.byKey(const Key('dailyUsed'))).data, contains('40 min'));
      await t.ensureVisible(find.byKey(const Key('dailyAllowMoreHere')));
      await t.tap(find.byKey(const Key('dailyAllowMoreHere')));
      await t.pumpAndSettle();
      expect((await usage.load(localDayKey(DateTime(2026, 11, 7, 16)))).bonusMinutes, kDailyBonusStepMinutes);
      expect(t.widget<Text>(find.byKey(const Key('dailyMsg'))).data, contains('Allowed 30 more minutes for today'));
      expect(t.widget<Text>(find.byKey(const Key('dailyUsed'))).data, contains('You allowed 30 more minutes today'));
    });

    testWidgets('a daily-time save that fails is said', (t) async {
      final MemoryHomePlanRepository plan = MemoryHomePlanRepository()..failSaves = true;
      await open(t, _store(), plan);
      await t.ensureVisible(find.descendant(of: find.byKey(const Key('dailySeg')), matching: find.text('2 h')));
      await t.tap(find.descendant(of: find.byKey(const Key('dailySeg')), matching: find.text('2 h')));
      await t.pumpAndSettle();
      expect(find.textContaining('could not keep it'), findsOneWidget);
    });

    for (final double width in <double>[344, 390, 600, 800]) {
      for (final double scale in <double>[1.0, 2.0]) {
        testWidgets('lays out with no overflow at $width dp, ${scale}x text', (t) async {
          await _size(t, width, h: 4000);
          await t.pumpWidget(MaterialApp(
            builder: (BuildContext c, Widget? child) =>
                MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: PlayWindowScreen(childName: 'Ivy', store: _store(window: w), plan: MemoryHomePlanRepository()),
          ));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('prohibitions', () {
    test('the guardian screen imports neither calls nor messages (they are never gated, P-calls)', () {
      final String src = File('lib/play_window_screen.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final String bad in <String>['call_', 'inbox', 'message_', 'push_']) {
        expect(src.contains("'$bad"), isFalse, reason: bad);
      }
    });
  });
}
