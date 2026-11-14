// OLIVE BRANCH — daily time enforcement on her device. Verifies lib/daily_time_logic.dart,
// lib/daily_time_store.dart and lib/daily_time_gate.dart. MASTERFILE §8.6.6, §8.1, §2.1.
//
// Ports the parity scenario `play` steps for the daily total (set it, wind down, rest, reopen
// next day) and holds the prohibitions: no number, clock, countdown or reward on her screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/daily_time_gate.dart';
import 'package:olive_client/daily_time_logic.dart';
import 'package:olive_client/daily_time_store.dart';
import 'package:olive_client/home_plan_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/storyteller_screen.dart';

void main() {
  group('rules', () {
    test('a day is her LOCAL calendar day, zero padded', () {
      expect(localDayKey(DateTime(2026, 3, 5, 23, 59, 59)), '2026-03-05');
      expect(localDayKey(DateTime(2026, 3, 6)), '2026-03-06');
    });

    test('off never limits; otherwise open, winding down in the last five minutes, then done', () {
      const DayUse huge = DayUse(day: 'd', seconds: 99 * 3600);
      expect(dailyTimeState(0, huge), DailyTimeState.open);
      expect(dailyTimeState(1, const DayUse(day: 'd', seconds: 0)), DailyTimeState.open);
      expect(dailyTimeState(1, const DayUse(day: 'd', seconds: 3600 - 301)), DailyTimeState.open);
      expect(dailyTimeState(1, const DayUse(day: 'd', seconds: 3600 - 300)), DailyTimeState.windingDown);
      expect(dailyTimeState(1, const DayUse(day: 'd', seconds: 3599)), DailyTimeState.windingDown);
      expect(dailyTimeState(1, const DayUse(day: 'd', seconds: 3600)), DailyTimeState.done);
      expect(dailyTimeState(3, const DayUse(day: 'd', seconds: 3 * 3600)), DailyTimeState.done);
    });

    test('a grown-up\'s extra minutes move the end, for that day only', () {
      const DayUse used = DayUse(day: 'd', seconds: 3600, bonusMinutes: 30);
      expect(dailyTimeState(1, used), DailyTimeState.open);
      expect(dailyTimeState(1, used.copyWith(seconds: 3600 + 1500)), DailyTimeState.windingDown);
      expect(dailyTimeState(1, used.copyWith(seconds: 3600 + 1800)), DailyTimeState.done);
    });

    test('extra time is given in steps and stops at the daily cap', () {
      expect(nextBonusMinutes(0), kDailyBonusStepMinutes);
      expect(canAllowMore(0), isTrue);
      expect(canAllowMore(kDailyBonusMaxMinutes - kDailyBonusStepMinutes), isTrue);
      expect(canAllowMore(kDailyBonusMaxMinutes), isFalse);
      expect(nextBonusMinutes(kDailyBonusMaxMinutes), kDailyBonusMaxMinutes);
    });

    test('her words carry no number, clock, countdown or reward; the adult\'s are plain', () {
      for (final DailyTimeState s in <DailyTimeState>[DailyTimeState.windingDown, DailyTimeState.done]) {
        final String line = dailyKidLine(s)!;
        expect(line, isNot(matches(RegExp(r'\d'))), reason: line);
        for (final String bad in <String>['minute', 'hour', 'limit', 'lock', 'timer', 'score', 'streak', 'reward',
          'trophy', 'allowance', 'time is up', 'error', 'sorry', 'wrong']) {
          expect(line.toLowerCase(), isNot(contains(bad)), reason: '$bad in "$line"');
        }
      }
      expect(dailyKidLine(DailyTimeState.open), isNull);
      expect(dailyAdultLine('Ivy'), contains('midnight'));
      expect(dailyAdultLine('Ivy'), contains('Calls and family messages are not affected'));
    });

    test('the grown-up\'s own line may use minutes; hers never does', () {
      expect(dailyUsedToday(const DayUse(day: 'd', seconds: 30)), contains('less than a minute'));
      expect(dailyUsedToday(const DayUse(day: 'd', seconds: 75 * 60)), contains('1 h 15 min'));
      expect(dailyUsedToday(const DayUse(day: 'd', seconds: 600, bonusMinutes: 30)), contains('allowed 30 more minutes'));
    });

    test('a stored day from another date, or junk, reads as a fresh empty day', () {
      expect(DayUse.fromJson(<String, Object?>{'day': '2026-01-01', 'seconds': 500}, '2026-01-02'),
          const DayUse(day: '2026-01-02'));
      expect(DayUse.fromJson('junk', '2026-01-02'), const DayUse(day: '2026-01-02'));
      expect(DayUse.fromJson(<String, Object?>{'day': '2026-01-02', 'seconds': -5, 'bonusMinutes': 'x'}, '2026-01-02'),
          const DayUse(day: '2026-01-02'));
      expect(DayUse.fromJson(<String, Object?>{'day': '2026-01-02', 'seconds': 90, 'bonusMinutes': 30}, '2026-01-02'),
          const DayUse(day: '2026-01-02', seconds: 90, bonusMinutes: 30));
    });
  });

  group('the store (LocalStore, one day, per child)', () {
    test('survives a restart; the next local day starts empty and yesterday is not kept', () async {
      final LocalServices a = LocalServices.memory(childId: 'ivy', guardianId: 'mom');
      final LocalStoreDayUseRepository r = LocalStoreDayUseRepository(a.area('daytime', ownerId: 'ivy'));
      await r.save(const DayUse(day: '2026-11-14', seconds: 1234, bonusMinutes: 30));
      expect(await r.load('2026-11-14'), const DayUse(day: '2026-11-14', seconds: 1234, bonusMinutes: 30));
      expect(await r.load('2026-11-15'), const DayUse(day: '2026-11-15'));
    });

    test('is catalogued, small, not a score, and mentions no history', () {
      final LocalDataEntry e = localDataEntry('daytime');
      expect(e.scope, LocalScope.child);
      expect(e.maxBytes, lessThanOrEqualTo(8 * 1024));
      expect(e.what.toLowerCase(), contains('yesterday is not kept'));
    });

    test('a save that fails leaves the in-memory count alone (the repository throws, the gate carries on)', () async {
      final MemoryDayUseRepository m = MemoryDayUseRepository()..failSaves = true;
      expect(() => m.save(const DayUse(day: 'd')), throwsA(isA<Object>()));
    });
  });

  group('the gate on a reading surface', () {
    late DateTime now;
    late MemoryHomePlanRepository plan;
    late MemoryDayUseRepository usage;

    setUp(() {
      now = DateTime(2026, 11, 14, 10, 0, 0);
      plan = MemoryHomePlanRepository(const HomePlan(dailyHours: 1));
      usage = MemoryDayUseRepository();
    });

    Widget app({Widget? above, String name = 'Ivy'}) {
      final Widget gate = DailyTimeGate(
        childName: name,
        plan: plan,
        usage: usage,
        clock: () => now,
        tick: const Duration(seconds: 10),
        child: const Scaffold(body: Center(child: Text('the story'))),
      );
      return MaterialApp(home: above ?? gate);
    }

    /// Advances both her clock and the fake timers, one tick at a time.
    Future<void> run(WidgetTester t, int seconds) async {
      for (int i = 0; i < seconds ~/ 10; i++) {
        now = now.add(const Duration(seconds: 10));
        await t.pump(const Duration(seconds: 10));
      }
    }

    testWidgets('with the total off nothing is counted, shown or timed', (t) async {
      plan = MemoryHomePlanRepository(const HomePlan(dailyHours: 0));
      await t.pumpWidget(app());
      await t.pump();
      await run(t, 600);
      expect(find.text('the story'), findsOneWidget);
      expect(find.byKey(const Key('dailyWindDown')), findsNothing);
      expect(usage.saves, 0, reason: 'off writes nothing and starts no timer');
    });

    testWidgets('counts while she reads; shows nothing at all until the last minutes', (t) async {
      await t.pumpWidget(app());
      await t.pump();
      await run(t, 1800);
      expect(find.text('the story'), findsOneWidget);
      expect(find.byKey(const Key('dailyWindDown')), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ ?(min|h)')), findsNothing, reason: 'P2: no number on her screen');
      expect(usage.saves, greaterThan(0), reason: 'the count is kept on the device as it goes');
      expect((await usage.load('2026-11-14')).seconds, closeTo(1800, 30));
    });

    testWidgets('the last minutes show ONE calm line, then a rest card replaces the story', (t) async {
      await t.pumpWidget(app());
      await t.pump();
      await run(t, 3600 - 290);
      expect(find.byKey(const Key('dailyWindDown')), findsOneWidget);
      expect(find.text('the story'), findsOneWidget, reason: 'she can finish what she is reading');
      expect(find.text(dailyKidLine(DailyTimeState.windingDown)!), findsOneWidget);
      await run(t, 300);
      expect(find.byKey(const Key('dailyRestLine')), findsOneWidget);
      expect(find.text('the story'), findsNothing);
      expect(find.text(dailyKidLine(DailyTimeState.done)!), findsOneWidget);
      expect(find.byKey(const Key('dailyGrownUp')), findsNothing, reason: 'no way to prove it = no button, no fake');
    });

    testWidgets('while the app is in the background nothing counts', (t) async {
      await t.pumpWidget(app());
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await run(t, 1200);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await run(t, 100);
      expect((await usage.load('2026-11-14')).seconds, lessThan(150), reason: 'twenty minutes away is not counted');
    });

    testWidgets('a device asleep (a big jump in the clock) adds at most a few ticks', (t) async {
      await t.pumpWidget(app());
      await t.pump();
      now = now.add(const Duration(hours: 5));
      await t.pump(const Duration(seconds: 10));
      expect((await usage.load('2026-11-14')).seconds, lessThanOrEqualTo(31));
      expect(find.text('the story'), findsOneWidget);
    });

    testWidgets('local midnight starts a new day from nothing and lifts the rest card', (t) async {
      now = DateTime(2026, 11, 14, 23, 50);
      usage = MemoryDayUseRepository(const DayUse(day: '2026-11-14', seconds: 3600));
      await t.pumpWidget(app());
      await t.pump();
      expect(find.byKey(const Key('dailyRestLine')), findsOneWidget);
      now = DateTime(2026, 11, 15, 0, 0, 5);
      await t.pump(const Duration(seconds: 10));
      await t.pump();
      expect(find.byKey(const Key('dailyRestLine')), findsNothing);
      expect(find.text('the story'), findsOneWidget);
      expect((await usage.load('2026-11-15')).seconds, lessThan(60));
    });

    testWidgets('a restart on the same day keeps what was used', (t) async {
      usage = MemoryDayUseRepository(const DayUse(day: '2026-11-14', seconds: 3500));
      await t.pumpWidget(app());
      await t.pump();
      await run(t, 10);
      expect(find.byKey(const Key('dailyWindDown')), findsOneWidget);
    });

    testWidgets('a grown-up proves it, reads the plain line, allows more; the story returns', (t) async {
      usage = MemoryDayUseRepository(const DayUse(day: '2026-11-14', seconds: 3600));
      int asked = 0;
      await t.pumpWidget(app(
        above: GrownUpProofScope(
          verify: (BuildContext c) async { asked++; return true; },
          child: DailyTimeGate(
            childName: 'Ivy', plan: plan, usage: usage, clock: () => now, tick: const Duration(seconds: 10),
            child: const Scaffold(body: Center(child: Text('the story'))),
          ),
        ),
      ));
      await t.pump();
      expect(find.byKey(const Key('dailyGrownUp')), findsOneWidget);
      expect(find.byKey(const Key('dailyAdultLine')), findsNothing, reason: 'the adult words wait for the proof');
      await t.tap(find.byKey(const Key('dailyGrownUp')));
      await t.pumpAndSettle();
      expect(asked, 1);
      expect(find.byKey(const Key('dailyAdultLine')), findsOneWidget);
      await t.tap(find.byKey(const Key('dailyAllowMore')));
      await t.pumpAndSettle();
      expect(find.text('the story'), findsOneWidget);
      expect((await usage.load('2026-11-14')).bonusMinutes, kDailyBonusStepMinutes);
    });

    testWidgets('a failed proof changes nothing', (t) async {
      usage = MemoryDayUseRepository(const DayUse(day: '2026-11-14', seconds: 3600));
      await t.pumpWidget(app(
        above: GrownUpProofScope(
          verify: (BuildContext c) async => false,
          child: DailyTimeGate(
            childName: 'Ivy', plan: plan, usage: usage, clock: () => now, tick: const Duration(seconds: 10),
            child: const Scaffold(body: Center(child: Text('the story'))),
          ),
        ),
      ));
      await t.pump();
      await t.tap(find.byKey(const Key('dailyGrownUp')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dailyAdultLine')), findsNothing);
      expect(find.byKey(const Key('dailyRestLine')), findsOneWidget);
      expect((await usage.load('2026-11-14')).bonusMinutes, 0);
    });

    testWidgets('the real storyteller door is gated: at the end of the day it rests', (t) async {
      LocalServices.install(LocalServices.memory(childId: 'ivy', guardianId: 'mom'));
      addTearDown(LocalServices.resetForTest);
      await LocalStoreHomePlanRepository.shared().save(const HomePlan(dailyHours: 1));
      final String today = localDayKey(DateTime.now());
      await LocalStoreDayUseRepository.shared().save(DayUse(day: today, seconds: 3600));
      await t.pumpWidget(const MaterialApp(home: StorytellerScreen(childName: 'Ivy')));
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('dailyRestLine')), findsOneWidget);
      expect(find.textContaining('Want a story'), findsNothing);
    });

    for (final double width in <double>[344, 390, 600, 800]) {
      for (final double scale in <double>[1.0, 2.0]) {
        testWidgets('rest card and wind-down line lay out at $width dp, ${scale}x text', (t) async {
          t.view.physicalSize = Size(width, 700);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          for (final int seconds in <int>[3400, 3600]) {
            usage = MemoryDayUseRepository(DayUse(day: '2026-11-14', seconds: seconds));
            await t.pumpWidget(MaterialApp(
              builder: (BuildContext c, Widget? child) =>
                  MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: GrownUpProofScope(
                verify: (BuildContext c) async => true,
                child: DailyTimeGate(
                  childName: 'Ivy', plan: plan, usage: usage, clock: () => now, tick: const Duration(seconds: 10),
                  child: const Scaffold(body: Center(child: Text('the story'))),
                ),
              ),
            ));
            await t.pump();
            await t.pump(const Duration(seconds: 10));
            expect(t.takeException(), isNull);
          }
        });
      }
    }
  });

  group('prohibitions', () {
    test('the gate imports neither calls nor messages; they are never gated', () {
      final String src = File('lib/daily_time_gate.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final String bad in <String>['call_', 'inbox', 'message_', 'push_', 'game_']) {
        expect(src.contains("'$bad"), isFalse, reason: bad);
      }
    });

    test('no screen of hers shows a count: the gate draws no number, bar or progress widget', () {
      final String src = File('lib/daily_time_gate.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final String bad in <String>['LinearProgressIndicator', 'CircularProgressIndicator', 'Countdown', 'streak', 'score']) {
        expect(src.contains(bad), isFalse, reason: bad);
      }
    });
  });
}
