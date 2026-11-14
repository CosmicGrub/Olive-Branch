// OLIVE BRANCH — wave 2b: the 13 to 17 home, her screens and the 18 handover, at every posture that has produced an
// overflow bug before (344 / 390 / 600 / 800 dp, 1.0x and 2.0x text), plus the rules each screen keeps: nothing counted
// (P1-P11), the journal has no reader, nothing shown to a grown-up until she picks who, a no is final for seven days,
// and nothing here pretends the network is there. UNVERIFIED until CI runs it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/handover18_screens.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/teen_logic.dart';
import 'package:olive_client/teen_screens.dart';
import 'package:olive_client/teen_store.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal childP = FamilyPrincipal(roleName: 'child', childId: 'c1');
final DateTime now = DateTime(2026, 11, 9, 9);

/// The real cipher (AES-GCM) cannot finish under the widget tester's fake clock, so the screens run over a store with a
/// pass-through cipher here; the sealed store itself is proven with the real cipher in teen_store_test.dart.
class _PlainCipher implements StoreCipher {
  @override
  Future<Uint8List> seal(Uint8List plain, List<int> aad) async => plain;
  @override
  Future<Uint8List> open(Uint8List box, List<int> aad) async => box;
}

Future<FamilyChildSnapshot> snap(int years) async {
  final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => now);
  Future<void> add(Map<String, Object?> op) => s.addChange(guardian, actorName: 'Dad', yearsOld: years, op: op, timing: Timing.now.toJson());
  await add(<String, Object?>{'op': 'put_home', 'home': <String, Object?>{'id': 'h1', 'name': "Mom's house", 'childSleeps': true}});
  await add(<String, Object?>{'op': 'put_person', 'person': <String, Object?>{
    'id': 'p1', 'label': 'Mom', 'role': 'guardian', 'homeId': 'h1', 'contact': <String>['live_call', 'message'], 'away': null}});
  return s.childSnapshot(childP, childId: 'c1', yearsOld: years);
}

Widget app(Widget home, double scale, int years) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      builder: (BuildContext c, Widget? w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: GrownupLabelScope(
          labels: GrownupLabels(
              contacts: const <GrownupContact>[
                GrownupContact(id: 'mom', guardianLabel: 'Mom', kind: GrownupKind.mom),
                GrownupContact(id: 'dad', guardianLabel: 'Dad', kind: GrownupKind.dad),
              ],
              age: AgeLockState(age: years, locked: true)),
          child: home),
    );

Future<void> size(WidgetTester t, double w, double h) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

const List<(double, double, String)> kSizes = <(double, double, String)>[
  (344, 882, 'Fold cover 344'),
  (390, 844, 'phone 390'),
  (600, 960, '7-inch tablet 600'),
  (800, 1280, '10-inch tablet 800'),
];

bool _cover(double w, double h) => ff.postureFor(ff.Viewport(w: w, h: h)) == ff.Posture.foldCover;

/// Words that would count, rank or reward her. None may appear on any teen screen.
final RegExp banned = RegExp(r'\b(streak|score|points?|trophy|trophies|reward|badge|level|rank|leaderboard|you have \d+)\b',
    caseSensitive: false);

/// Reads from the store while the widget tester owns the clock: the future is driven by pumping, not by awaiting.
Future<T> viaPump<T>(WidgetTester t, Future<T> Function() read) async {
  late T out;
  bool done = false;
  unawaited(read().then((T v) {
    out = v;
    done = true;
  }));
  for (int i = 0; i < 100 && !done; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue, reason: 'the store answered');
  return out;
}

void expectNothingCounted(WidgetTester t) {
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    final String s = w.data ?? w.textSpan?.toPlainText() ?? '';
    expect(banned.hasMatch(s), isFalse, reason: 'counts or rewards her: "$s"');
  }
}

// Built lazily INSIDE each test: a namespace made in setUp chains its futures on the real microtask queue, which the
// widget tester's fake clock never runs.
LocalServices? svc;
TeenRepository? rep;
LocalServices get services => svc ??= LocalServices(
    store: LocalStore(backend: MemoryStoreBackend(), cipher: _PlainCipher()),
    childId: 'c1', guardianId: 'g1', isLive: true, demoSeeds: false);
TeenRepository get repo => rep ??= TeenRepository(services.area('teen'));
void main() {
  setUp(() {
    svc = null;
    rep = null;
  });
  testWidgets('installs its services', (WidgetTester t) async {
    LocalServices.install(services);
    expect(LocalServices.current, same(services));
  });

  for (final (double w, double h, String name) in kSizes) {
    for (final double scale in <double>[1.0, 2.0]) {
      final String tag = 'at $name dp, ${scale}x text';

      for (final int years in <int>[13, 15, 17, 18]) {
        testWidgets('home, age $years $tag', (WidgetTester t) async {
          LocalServices.install(services);
          await size(t, w, h);
          final FamilyChildSnapshot f = await snap(years);
          await t.pumpWidget(app(
              ChildHome(
                  childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 2, family: f, childAge: years,
                  teenRepository: repo, clock: () => now, handoverPurge: null),
              scale, years));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'no overflow');
          expect(find.byKey(const Key('bandHome.t1317')), findsOneWidget);
          if (_cover(w, h)) {
            await t.tap(find.byKey(const Key('bandCollapsedMore')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }
          expect(find.byKey(const Key('teenToday')), findsOneWidget);
          expect(find.textContaining('sleeps'), findsNothing, reason: 'no countdown for her');
          expect(find.byKey(const Key('handoverCard')), years >= 18 ? findsOneWidget : findsNothing);
          expectNothingCounted(t);
        });
      }

      Future<void> shows(WidgetTester t, Widget screen, int years, Key key, {Future<void> Function()? then}) async {
        await size(t, w, h);
        await t.pumpWidget(app(screen, scale, years));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'no overflow');
        expect(find.byKey(key), findsOneWidget);
        if (then != null) {
          await then();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'no overflow after interacting');
        }
        expectNothingCounted(t);
      }

      testWidgets('calendar and its add sheet $tag', (WidgetTester t) async {
        await shows(t, TeenCalendarScreen(age: 15, repository: repo, clock: () => now), 15, const Key('teenCalendar'), then: () async {
          await t.tap(find.byKey(const Key('teenCalendarAdd')));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('shareOnlyMe')), findsOneWidget);
          expect(find.byKey(const Key('shareBoth')), findsOneWidget);
        });
      });

      testWidgets('free times $tag', (WidgetTester t) async {
        await shows(t, TeenFreeTimesScreen(age: 16, repository: repo), 16, const Key('teenFreeTimes'));
      });

      testWidgets('privacy contract $tag', (WidgetTester t) async {
        await shows(t, TeenPrivacyScreen(age: 15, onConsentLog: () {}, onFreeTimes: () {}), 15, const Key('teenPrivacy'));
        expect(find.byKey(const Key('privacyTable')), findsOneWidget);
        expect(find.byKey(const Key('privacyReverse')), findsOneWidget);
      });

      testWidgets('consent log with an open ask $tag', (WidgetTester t) async {
        await repo.saveAsks(const AskLedger().ask('a1', 'mom', 'calendar', now, herAge: 15)!);
        await shows(t, ConsentLogScreen(age: 15, repository: repo, clock: () => now), 15, const Key('consentLog'));
        expect(find.byKey(const Key('askYes.a1')), findsOneWidget);
        expect(find.byKey(const Key('askNo.a1')), findsOneWidget);
      });

      testWidgets('journal $tag', (WidgetTester t) async {
        LocalServices.install(services);
        await shows(t, const TeenJournalScreen(childName: 'Ivy', childId: 'c1'), 15, const Key('teenJournal'));
        expect(find.byKey(const Key('journalOnlyYou')), findsOneWidget);
      });

      testWidgets('ladder $tag', (WidgetTester t) async {
        LocalServices.install(services);
        await shows(t, TeenLadderScreen(age: 15, destination: (BuildContext c, g) => null, onPreview: () {}, onFullLadder: () {}), 15, const Key('teenLadder'));
        expect(find.byKey(const Key('ladderGuard')), findsOneWidget, reason: 'honest about the one step that stays with guardians');
      });

      testWidgets('heads-up, choices, copy, staying in touch and goodbye $tag', (WidgetTester t) async {
        await shows(t, HandoverHeadsUpScreen(monthDay: '12-09', onChoices: () {}, onWhatYouGet: () {}, onStayInTouch: () {}), 17, const Key('handoverHeadsUp'));
        await shows(t, HandoverPathsScreen(childName: 'Ivy', repository: repo, clock: () => now), 18, const Key('handoverPaths'));
        await shows(t, WhatYouGetScreen(childName: 'Ivy', repository: repo, clock: () => now, services: services, childId: 'c1'), 18, const Key('whatYouGet'));
        await shows(t, StayInTouchScreen(repository: repo), 18, const Key('stayInTouch'));
        await shows(t, HandoverGoodbyeScreen(childName: 'Ivy', repository: repo), 18, const Key('handoverGoodbye'));
      });
    }
  }

  group('rules', () {
    testWidgets('an event starts private: only her', (WidgetTester t) async {
      await t.pumpWidget(app(TeenCalendarScreen(age: 15, repository: repo, clock: () => now), 1.0, 15));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('teenCalendarAdd')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Dentist');
      await t.pump();
      await t.tap(find.byKey(const Key('teenEventSave')));
      await t.pumpAndSettle();
      final List<TeenEvent> all = await viaPump(t, repo.events);
      expect(all.single.title, 'Dentist');
      expect(all.single.share.isPrivate, isTrue, reason: 'nothing is shown to anyone until she picks who');
    });

    testWidgets('13 looks at the calendar, 14 edits it', (WidgetTester t) async {
      await t.pumpWidget(app(TeenCalendarScreen(age: 13, repository: repo, clock: () => now), 1.0, 13));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('teenCalendarLookOnly')), findsOneWidget);
      expect(find.byKey(const Key('teenCalendarAdd')), findsNothing);
      await t.pumpWidget(app(TeenCalendarScreen(age: 14, repository: repo, clock: () => now), 1.0, 14));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('teenCalendarAdd')), findsOneWidget);
    });

    testWidgets('free times wait until 15', (WidgetTester t) async {
      await t.pumpWidget(app(TeenFreeTimesScreen(age: 14, repository: repo), 1.0, 14));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('freeTimesLocked')), findsOneWidget);
    });

    testWidgets('answering no keeps the ask closed for seven days and is in the log', (WidgetTester t) async {
      await repo.saveAsks(const AskLedger().ask('a1', 'mom', 'calendar', now, herAge: 15)!);
      await t.pumpWidget(app(ConsentLogScreen(age: 15, repository: repo, clock: () => now), 1.0, 15));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('askNo.a1')));
      await t.pumpAndSettle();
      final AskLedger l = await viaPump(t, repo.asks);
      expect(l.open, isEmpty);
      final AskCheck again = l.canAsk('mom', 'calendar', now.add(const Duration(days: 6)), herAge: 15);
      expect(again.ok, isFalse, reason: 'a no holds for seven days');
      expect(l.canAsk('mom', 'calendar', now.add(const Duration(days: 8)), herAge: 15).ok, isTrue);
    });

    testWidgets('preview of the choices cannot be chosen from', (WidgetTester t) async {
      await t.pumpWidget(app(HandoverPathsScreen(childName: 'Ivy', preview: true, repository: repo, clock: () => now), 1.0, 17));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('handoverPreviewBanner')), findsOneWidget);
      await t.tap(find.byKey(const Key('path.keep')));
      await t.pumpAndSettle();
      final HandoverRecord r = await viaPump(t, repo.handover);
      expect(r.chosen, isFalse, reason: 'a preview changes nothing');
    });

    testWidgets('keep is kept, and can be moved within 30 days', (WidgetTester t) async {
      await t.pumpWidget(app(HandoverPathsScreen(childName: 'Ivy', repository: repo, clock: () => now), 1.0, 18));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('path.keep')));
      await t.pumpAndSettle();
      expect((await viaPump(t, repo.handover)).choice, HandoverChoice.keep);
      await t.tap(find.byKey(const Key('path.later')));
      await t.pumpAndSettle();
      expect((await viaPump(t, repo.handover)).choice, HandoverChoice.later);
    });

    testWidgets('take-and-go makes her copy for real and is honest that nothing online is in it', (WidgetTester t) async {
      final Directory dir = Directory.systemTemp.createTempSync('own_copy_widget');
      addTearDown(() => dir.deleteSync(recursive: true));
      await t.pumpWidget(app(
          WhatYouGetScreen(
              childName: 'Ivy', repository: repo, clock: () => now, services: services, childId: 'c1',
              documentsDirectory: () async => dir),
          1.0, 18));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('copyNotHere')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('makeCopy')), 200);
      await t.tap(find.byKey(const Key('makeCopy')));
      for (int i = 0; i < 40 && find.byKey(const Key('copySaved')).evaluate().isEmpty && find.byKey(const Key('copyFailed')).evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('copyFailed')), findsNothing);
      await t.scrollUntilVisible(find.byKey(const Key('copySaved')), 200);
      expect(find.byKey(const Key('copySaved')), findsOneWidget);
      expect(dir.listSync(recursive: true).whereType<File>(), isNotEmpty, reason: 'a real file was written');
    });

    testWidgets('staying in touch needs both sides: her offer alone is waiting, not ready', (WidgetTester t) async {
      await t.pumpWidget(app(StayInTouchScreen(repository: repo), 1.0, 18));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('offer.messages')));
      await t.pumpAndSettle();
      expect((await viaPump(t, repo.touch)).offered, <Channel>{Channel.messages});
      expect(find.byKey(const Key('touchBothSides')), findsOneWidget);
      expect(find.textContaining('connected'), findsNothing, reason: 'no fake success');
    });
  });
}
