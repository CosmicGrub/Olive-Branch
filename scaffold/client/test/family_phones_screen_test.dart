// OLIVE BRANCH — the "Share with another grown-up" screens: what a grown-up reads and taps, in plain words; the way in from
// More; and the road keeper that brings the Wi-Fi road up and down with the app. Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart' show GrownupKind;
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_hub.dart';
import 'package:olive_client/family_join.dart';
import 'package:olive_client/family_phones_screen.dart';
import 'package:olive_client/family_state.dart' show FamilySnapshot, MemoryFamilyRepository;
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/family_sync_lan.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/screen_privacy.dart' show SensitiveScreen;
import 'package:olive_client/screen_share.dart' show ScreenShareService;
import 'package:olive_client/screen_share_ui.dart' show ShareCaptureScope, ShareScreenAction;

import 'family_hub_test_support.dart';

const FamilyPrincipal _mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');

final RegExp _technical = RegExp(
  r'\b(ledger|keys?|sync(ed|ing)?|epoch|events?|mailbox|bundle|encrypt\w*|cipher\w*|hash|signature|seal(ed)?|pake|mdns|http|port|handshake|token|protocol)\b',
  caseSensitive: false,
);

List<String> allText(WidgetTester t) => <String>[
  for (final Text w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
  for (final TextField f in t.widgetList<TextField>(find.byType(TextField))) f.decoration?.labelText ?? '',
];

/// Lets real time pass (sockets, crypto) between frames.
Future<void> settle(WidgetTester t, {int rounds = 10}) async {
  for (int i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late Clk clock;
  final List<Phone> up = <Phone>[];
  Future<Phone> mk(WidgetTester t, int n) async {
    final Phone p = (await t.runAsync(() => phone(n, clock)))!;
    up.add(p);
    return p;
  }

  setUp(() => clock = Clk(DateTime.now().millisecondsSinceEpoch));
  tearDown(() async {
    for (final Phone p in up) {
      await p.hub.stopRoad();
    }
    up.clear();
  });

  Future<void> show(WidgetTester t, Phone p, {String name = 'Mom'}) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: FamilyPhonesScreen(
          hub: p.hub,
          childId: 'ivy',
          principal: _mom,
          cardService: EmergencyCardService.memory(),
          defaultName: name,
          childName: 'Ivy',
        ),
      ),
    );
    await settle(t, rounds: 4);
  }

  group('syncRunText', () {
    test('says each outcome in plain words', () {
      expect(syncRunText(const SyncRun(noWifi: true)), contains('not on a Wi-Fi network'));
      expect(syncRunText(const SyncRun()), contains('was not found'));
      expect(syncRunText(const SyncRun(failed: 1)), contains('did not answer'));
      expect(syncRunText(const SyncRun(met: 1)), 'Both phones are up to date.');
      expect(syncRunText(const SyncRun(met: 1, updates: 1)), 'Got 1 update.');
      expect(syncRunText(const SyncRun(met: 1, updates: 3, sent: 2)), 'Got 3 updates. Screens were sent.');
      for (final SyncRun r in const <SyncRun>[
        SyncRun(noWifi: true),
        SyncRun(),
        SyncRun(failed: 2),
        SyncRun(met: 1, updates: 2, sent: 1),
      ]) {
        expect(syncRunText(r).contains(_technical), isFalse);
        expect(syncRunText(r).contains(RegExp(r'\d{3,}')), isFalse, reason: 'no counts beyond a small number');
      }
    });
  });

  testWidgets('before anyone is added: says so, offers to add or join, and uses no technical word', (
    WidgetTester t,
  ) async {
    final Phone mom = await mk(t, 1);
    await show(t, mom);
    expect(find.text('This phone is not sharing with anyone yet.'), findsOneWidget);
    expect(find.byKey(const Key('phonesAdd')), findsOneWidget);
    expect(find.byKey(const Key('phonesJoin')), findsOneWidget);
    expect(find.byKey(const Key('phonesShareNow')), findsNothing);
    expect(allText(t).where((String s) => s.contains(_technical)), isEmpty);
    expect(find.byKey(const Key('phonesIntro')), findsOneWidget);
  });

  testWidgets('the screens that show or take a code can never be captured, whatever the phone allows', (WidgetTester t) async {
    final Phone mom = await mk(t, 1);
    await show(t, mom);
    expect(find.byType(SensitiveScreen), findsNothing, reason: 'the plain list is not a code screen');
    await t.tap(find.byKey(const Key('phonesAdd')));
    await settle(t, rounds: 3);
    expect(find.byType(SensitiveScreen), findsOneWidget);
    await t.pageBack();
    await settle(t, rounds: 3);
    await t.tap(find.byKey(const Key('phonesJoin')));
    await settle(t, rounds: 3);
    expect(find.byType(SensitiveScreen), findsOneWidget);
  });

  testWidgets('add a grown-up: a code and a two-word label appear, and leaving the screen closes the window', (
    WidgetTester t,
  ) async {
    final Phone mom = await mk(t, 1);
    await show(t, mom);
    await t.tap(find.byKey(const Key('phonesAdd')));
    await settle(t, rounds: 3);
    await t.enterText(find.byKey(const Key('addName')), 'Mom');
    await t.tap(find.byKey(const Key('addStart')));
    await settle(t, rounds: 12);
    final String code = t.widget<Text>(find.byKey(const Key('addCode'))).data!;
    expect(code, matches(RegExp(r'^\d{6}$')));
    expect(t.widget<Text>(find.byKey(const Key('addLabel'))).data, isNotEmpty);
    expect(mom.hub.joinWindow, isNotNull);
    expect(mom.hub.roadUp, isTrue);
    expect(allText(t).where((String s) => s.contains(_technical)), isEmpty);
    // The code is on the screen and in the window, and nowhere an observer can see.
    expect(mom.disc.adverts.map((a) => '${a.handle}${a.tag}').join().contains(code), isFalse);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await settle(t, rounds: 4);
    expect(mom.hub.joinWindow, isNull, reason: 'closing the screen closed the window');
  });

  testWidgets(
    'the whole add, on screen: the other phone joins, the grown-up sees the name and the words and says yes',
    (WidgetTester t) async {
      final Phone mom = await mk(t, 1), dad = await mk(t, 2);
      await show(t, mom);
      await t.tap(find.byKey(const Key('phonesAdd')));
      await settle(t, rounds: 3);
      await t.tap(find.byKey(const Key('addStart')));
      await settle(t, rounds: 12);
      final FamilyJoinWindow w = mom.hub.joinWindow!;
      final Future<JoinOutcome?> joined = t.runAsync(
        () => dad.hub.joinFamily(
          window: RoadPeer(host: '127.0.0.1', port: mom.hub.port!, handle: w.handle, tag: Uint8List(8), join: true),
          code: w.code,
          myName: 'Dad',
          pollEvery: const Duration(milliseconds: 20),
        ),
      );
      await settle(t, rounds: 25);
      expect(find.byKey(const Key('addWho')), findsOneWidget);
      expect(find.text('Dad wants to join your family.'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('addWords'))).data, '${w.sas}');
      expect(find.textContaining('see what you share with grown-ups'), findsOneWidget);
      expect(allText(t).where((String s) => s.contains(_technical)), isEmpty);
      await t.tap(find.byKey(const Key('addApprove')));
      await settle(t, rounds: 30);
      final JoinOutcome o = (await t.runAsync(() async => (await joined)!))!;
      expect(o.ok, isTrue, reason: o.reason);
      await settle(t, rounds: 6);
      expect(find.byKey(const Key('addDone')), findsOneWidget);
      expect((await t.runAsync(() => mom.hub.status()))!.others, <String>['Dad']);
    },
  );

  testWidgets('saying no sends the other phone away with nothing', (WidgetTester t) async {
    final Phone mom = await mk(t, 1), dad = await mk(t, 2);
    await show(t, mom);
    await t.tap(find.byKey(const Key('phonesAdd')));
    await settle(t, rounds: 3);
    await t.tap(find.byKey(const Key('addStart')));
    await settle(t, rounds: 12);
    final FamilyJoinWindow w = mom.hub.joinWindow!;
    final Future<JoinOutcome?> joined = t.runAsync(
      () => dad.hub.joinFamily(
        window: RoadPeer(host: '127.0.0.1', port: mom.hub.port!, handle: w.handle, tag: Uint8List(8), join: true),
        code: w.code,
        myName: 'Dad',
        pollEvery: const Duration(milliseconds: 20),
      ),
    );
    await settle(t, rounds: 25);
    await t.tap(find.byKey(const Key('addDecline')));
    await settle(t, rounds: 20);
    final JoinOutcome o = (await t.runAsync(() async => (await joined)!))!;
    expect(o.ok, isFalse);
    expect(o.reason, 'declined');
    expect((await t.runAsync(() => dad.fam.hasRecord()))!, isFalse);
  });

  testWidgets(
    'once paired: who it is shared with, a settling note, Share now with a plain result, the card and the screens',
    (WidgetTester t) async {
      final Phone mom = await mk(t, 1), dad = await mk(t, 2);
      await t.runAsync(() => pairUp(mom, dad));
      await show(t, mom);
      expect(find.text('Shared with Dad.'), findsOneWidget);
      expect(find.byKey(const Key('phonesSettling')), findsOneWidget);
      expect(find.byKey(const Key('phonesAdd')), findsNothing);
      expect(find.byKey(const Key('phonesJoin')), findsNothing);
      expect(find.byKey(const Key('phonesCard')), findsOneWidget);
      expect(find.byKey(const Key('phonesScreens')), findsOneWidget);
      await t.tap(find.byKey(const Key('phonesShareNow')));
      await settle(t, rounds: 20);
      expect(
        t.widget<Text>(find.byKey(const Key('phonesLine'))).data,
        contains('was not found'),
        reason: 'Dad is not in sight',
      );
      expect(allText(t).where((String s) => s.contains(_technical)), isEmpty);
      // The emergency card opens, with the Wi-Fi button.
      await t.tap(find.byKey(const Key('phonesCard')));
      await settle(t, rounds: 10);
      expect(find.byKey(const Key('sync-wifi')), findsOneWidget);
    },
  );

  testWidgets('a family record that cannot be read: one sentence, no buttons, nothing changed', (WidgetTester t) async {
    final Phone mom = await mk(t, 1), dad = await mk(t, 2);
    await t.runAsync(() => pairUp(mom, dad));
    final Phone broken = (await t.runAsync(() async {
      final FamilySnapshot g = (await mom.fam.load())!;
      final MemoryFamilyRepository bad = MemoryFamilyRepository();
      await bad.save(
        FamilySnapshot(
          entries: g.entries.sublist(1),
          votes: g.votes,
          agreementSeed: g.agreementSeed,
          guardianDevice: true,
          fk: g.fk,
          gk: g.gk,
        ),
      );
      final Phone p = await phone(1, clock, fam: bad);
      up.add(p);
      return p;
    }))!;
    await show(t, broken);
    expect(find.byKey(const Key('phonesUnusable')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets(
    'join screen: looks for a window, takes only six digits, and cannot go until a window and a code are there',
    (WidgetTester t) async {
      final Phone dad = await mk(t, 2);
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: JoinGrownUpScreen(hub: dad.hub, defaultName: 'Dad'),
        ),
      );
      await settle(t, rounds: 4);
      expect(find.byKey(const Key('joinNone')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('joinGo'))).onPressed, isNull);
      await t.enterText(find.byKey(const Key('joinCode')), '12ab3456789');
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('joinCode'))).controller!.text, '123456');
      expect(
        t.widget<FilledButton>(find.byKey(const Key('joinGo'))).onPressed,
        isNull,
        reason: 'no window to pick yet',
      );
      expect(allText(t).where((String s) => s.contains(_technical)), isEmpty);
    },
  );

  group('the way in from More', () {
    Future<void> more(WidgetTester t, GuardianLocalServices svc) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final GuardianLocalController ctl = GuardianLocalController(
        svc,
        family: LocalFamily.fromAnswers(
          guardianName: 'Sam',
          guardianLabel: 'Dad',
          guardianKind: GrownupKind.dad,
          childName: 'Ivy',
          age: 7,
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: ctl, child: child!),
          home: const GuardianMoreScreen(childName: 'Ivy', childAge: 7),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
    }

    testWidgets('Safety lists "Share with another grown-up" when the app has a family hub, and it opens the screen', (
      WidgetTester t,
    ) async {
      final Phone mom = await mk(t, 1);
      await more(t, GuardianLocalServices.memory(pinIterations: 100, familyHub: mom.hub));
      final Finder row = find.text('Share with another grown-up');
      await t.ensureVisible(row);
      expect(row, findsOneWidget);
      await t.tap(row);
      await settle(t, rounds: 6);
      expect(find.byType(FamilyPhonesScreen), findsOneWidget);
      expect(find.byKey(const Key('phonesAdd')), findsOneWidget);
      // The name box starts with the grown-up's label on this phone.
      await t.tap(find.byKey(const Key('phonesAdd')));
      await settle(t, rounds: 4);
      expect(t.widget<TextField>(find.byKey(const Key('addName'))).controller!.text, 'Dad');
    });

    testWidgets('without a hub (the preview, an old tree) the row is not there and nothing else changes', (
      WidgetTester t,
    ) async {
      await more(t, GuardianLocalServices.memory(pinIterations: 100));
      expect(find.text('Share with another grown-up'), findsNothing);
      expect(find.text('App lock and privacy'), findsOneWidget);
    });
  });

  group('the screen share action and the screenshot setting', () {
    Future<void> bar(WidgetTester t, ScreenShareService? svc) async {
      await t.pumpWidget(
        MaterialApp(
          builder: (BuildContext c, Widget? child) => ShareCaptureScope(service: svc, child: child!),
          home: Scaffold(
            appBar: AppBar(title: const Text('Medications'), actions: const <Widget>[ShareScreenAction()]),
          ),
        ),
      );
      await settle(t, rounds: 8);
    }

    testWidgets('"Share this screen" appears only once there is a grown-up who has settled in to send to', (
      WidgetTester t,
    ) async {
      final Phone mom = await mk(t, 1), dad = await mk(t, 2);
      await bar(t, mom.hub.shares);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing, reason: 'no family yet: nobody to send to');
      await t.runAsync(() => pairUp(mom, dad));
      await bar(t, mom.hub.shares);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing, reason: 'the new phone is still settling in');
      clock.ms += 25 * 3600 * 1000;
      await bar(t, mom.hub.shares);
      expect(find.byKey(const Key('shareScreenAction')), findsOneWidget);
      // And on the new phone too: it can send to Mom as soon as it is itself past settling in.
      await bar(t, dad.hub.shares);
      expect(find.byKey(const Key('shareScreenAction')), findsOneWidget);
    });

    testWidgets('a child device never shows it, whatever else is true', (WidgetTester t) async {
      await bar(t, ScreenShareService.childDevice());
      expect(find.byKey(const Key('shareScreenAction')), findsNothing);
      await bar(t, null);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing);
    });

    testWidgets(
      'Screens on this phone: reached from Safety, Private by default, and Screenshots allowed needs a PIN first',
      (WidgetTester t) async {
        await t.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final GuardianLocalServices svc = GuardianLocalServices.memory(pinIterations: 100);
        final GuardianLocalController ctl = GuardianLocalController(svc);
        await t.pumpWidget(
          MaterialApp(
            builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: ctl, child: child!),
            home: const GuardianMoreScreen(childName: 'Ivy', childAge: 7),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('moreSettings')));
        await t.tap(find.byKey(const Key('moreSettings')));
        await t.pumpAndSettle();
        final Finder row = find.text('App lock and privacy');
        await t.ensureVisible(row);
        await t.tap(row);
        await t.pumpAndSettle();
        expect(
          t.widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>)).groupValue,
          isFalse,
          reason: 'Private is the default',
        );
        await t.tap(find.byKey(const Key('screensAllowed')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('appLockError')),
          findsOneWidget,
          reason: 'no PIN yet: it stays Private and says why',
        );
        expect(t.widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>)).groupValue, isFalse);
      },
    );
  });

  group('the road keeper', () {
    testWidgets(
      'brings the road up for a family of two grown-ups, takes it down in the background, and back on return',
      (WidgetTester t) async {
        final Phone mom = await mk(t, 1), dad = await mk(t, 2);
        await t.runAsync(() => pairUp(mom, dad));
        await t.runAsync(() => mom.hub.stopRoad());
        expect(mom.hub.roadUp, isFalse);
        await t.pumpWidget(
          MaterialApp(
            home: FamilyRoadKeeper(hub: mom.hub, child: const Text('home')),
          ),
        );
        await settle(t, rounds: 8);
        expect(mom.hub.roadUp, isTrue);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await settle(t, rounds: 8);
        expect(mom.hub.roadUp, isFalse, reason: 'nothing is listening while the app is in the background');
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settle(t, rounds: 8);
        expect(mom.hub.roadUp, isTrue);
      },
    );

    testWidgets('does nothing for a phone with no other grown-up, and nothing at all without a hub', (
      WidgetTester t,
    ) async {
      final Phone mom = await mk(t, 1);
      await t.pumpWidget(
        MaterialApp(
          home: FamilyRoadKeeper(hub: mom.hub, child: const Text('home')),
        ),
      );
      await settle(t, rounds: 6);
      expect(mom.hub.roadUp, isFalse);
      expect(mom.disc.adverts, isEmpty);
      await t.pumpWidget(const MaterialApp(home: FamilyRoadKeeper(hub: null, child: Text('home'))));
      expect(find.text('home'), findsOneWidget);
    });
  });
}
