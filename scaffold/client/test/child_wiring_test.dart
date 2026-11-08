// OLIVE BRANCH — client wiring audit fixes (C-05, C-10, C-11, C-12, C-13,
// C-14, C-15, C-22, C-23, C-24, G-08, G-12). No longer UNVERIFIED — verified
// by CI.
//
// Each group names the audit finding it closes. The shape throughout: a
// real screen, real (mocked-transport) data, and an assertion on what the
// child (or guardian) actually sees — not on a private field.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/calendar_day_logic.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/call_screen.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/exchange_screen.dart';
import 'package:olive_client/expenses_screen.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_uno.dart';
import 'package:olive_client/games_hub.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/handover_notes.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:olive_client/kiosk_shell.dart';
import 'package:olive_client/meds_care.dart';
import 'package:olive_client/my_day.dart';
import 'package:olive_client/push_channel.dart';
import 'package:olive_client/tiered_tile.dart';
import 'package:olive_client/wear_sync_channel.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

class _NoPush extends PushChannel {
  _NoPush() : super(OliveApi('http://unused', 'unused'));
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}

class _NoWear extends WearSyncChannel {
  @override
  Future<void> syncSleepsUntilHandover(int sleepsUntilHandover) async {}
}

/// A server that answers the four reads LiveChildHomeScreen makes.
MockClient liveServer({
  int? yearsOld = 11,
  List<Map<String, dynamic>>? dayParts,
  int unread = 0,
  int opened = 0,
  Map<String, dynamic>? presenceFree,
}) =>
    MockClient((req) async {
      final p = req.url.path;
      if (p == '/v1/auth/dev-login') return http.Response(jsonEncode({'token': 'tok'}), 200);
      if (p == '/v1/me') {
        return http.Response(jsonEncode({'displayName': 'Ivy', 'yearsOld': yearsOld}), 200);
      }
      if (p.endsWith('/inbox')) {
        return http.Response(jsonEncode({'entries': [
          for (var i = 0; i < unread; i++) {'id': '$i', 'state': 'delivered'},
          for (var i = 0; i < opened; i++) {'id': 'o$i', 'state': 'opened'},
        ]}), 200);
      }
      if (p.endsWith('/now')) {
        return http.Response(jsonEncode({
          'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
          'sleepsUntilHandover': null,
          'dayParts': ?dayParts,
        }), 200);
      }
      if (p.endsWith('/presence')) {
        return http.Response(jsonEncode({'free': presenceFree}), 200);
      }
      return http.Response('not found', 404);
    });

Future<void> pumpLive(WidgetTester t, MockClient server) async {
  await t.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(wrap(LiveChildHomeScreen(
    baseUrl: 'http://api.test', childId: 'child-a', httpClient: server,
    wearSync: _NoWear(), pushChannel: _NoPush())));
  await t.pumpAndSettle();
}

void main() {
  group('C-05 — the age gate is real: the live child home passes her real age', () {
    testWidgets('a 5-year-old live session never sees the ladder tiles in More for you', (t) async {
      await pumpLive(t, liveServer(yearsOld: 5));
      await t.tap(find.text('More for you'));
      await t.pumpAndSettle();
      expect(find.text('My journal'), findsOneWidget);
      expect(find.text('Growing up'), findsNothing);
      expect(find.text('The quiet corner'), findsNothing);
      expect(find.text('Take your things with you'), findsNothing);
      expect(find.textContaining('Take your data'), findsNothing);
    });

    testWidgets('an 11-year-old live session does see them', (t) async {
      await pumpLive(t, liveServer(yearsOld: 11));
      await t.tap(find.text('More for you'));
      await t.pumpAndSettle();
      expect(find.text('Growing up'), findsOneWidget);
      expect(find.text('The quiet corner'), findsOneWidget);
      expect(find.text('Take your things with you'), findsOneWidget);
    });

    testWidgets('a 5-year-old gets the 5-year-old catalogue; an 11-year-old gets chess', (t) async {
      await pumpLive(t, liveServer(yearsOld: 5));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);
      expect(find.text('Chess'), findsNothing);
      expect(find.text('Battleship'), findsNothing);
    });

    testWidgets('a missing yearsOld fails CLOSED to the youngest catalogue, never open', (t) async {
      await pumpLive(t, liveServer(yearsOld: null));
      await t.tap(find.text('More for you'));
      await t.pumpAndSettle();
      expect(find.text('Growing up'), findsNothing);
    });

    testWidgets('a live older child sees chess in the picker', (t) async {
      await pumpLive(t, liveServer(yearsOld: 11));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.text('Chess'), findsOneWidget);
    });
  });

  group('C-10 — My day shows her real day parts', () {
    MyDayScreen myDay(WidgetTester t) => t.widget<MyDayScreen>(find.byType(MyDayScreen));

    testWidgets('live: the parts come from /now, not the demo hours', (t) async {
      await pumpLive(t, liveServer(dayParts: [
        {'kind': 'school', 'startsLocal': '08:15', 'endsLocal': '15:10', 'reachable': false},
        {'kind': 'dinner', 'startsLocal': '17:30', 'endsLocal': '18:30', 'reachable': true},
      ]));
      await t.tap(find.byKey(const Key('childHomeHero')));
      await t.pumpAndSettle();
      expect(myDay(t).parts.map((p) => p.kind).toList(), ['school', 'dinner']);
      expect(myDay(t).parts.first.startsLocal, '08:15');
      expect(myDay(t).parts.first.reachable, isFalse);
    });

    testWidgets('live with no schedule: an honest empty day, never invented hours', (t) async {
      await pumpLive(t, liveServer(dayParts: <Map<String, dynamic>>[]));
      await t.tap(find.byKey(const Key('childHomeHero')));
      await t.pumpAndSettle();
      expect(myDay(t).parts, isEmpty);
    });

    testWidgets('live with a server that predates dayParts: still empty, never the demo', (t) async {
      await pumpLive(t, liveServer());
      await t.tap(find.byKey(const Key('childHomeHero')));
      await t.pumpAndSettle();
      expect(myDay(t).parts, isEmpty);
    });

    testWidgets('the offline demo build keeps the demo hours', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0)));
      await t.tap(find.byKey(const Key('childHomeHero')));
      await t.pumpAndSettle();
      expect(myDay(t).parts.length, demoDayParts.length);
    });
  });

  group('C-23 / C-24 — no developer banner, and an unread DOT not a number', () {
    testWidgets('the live banner is gone', (t) async {
      await pumpLive(t, liveServer());
      expect(find.textContaining('Live:'), findsNothing);
      expect(find.textContaining('fetched from the server'), findsNothing);
    });

    testWidgets('unread messages show a dot with no number', (t) async {
      await pumpLive(t, liveServer(unread: 3));
      expect(find.byKey(const Key('newDot')), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('only already-opened messages: no dot (she has seen them all)', (t) async {
      await pumpLive(t, liveServer(unread: 0, opened: 4));
      expect(find.byKey(const Key('newDot')), findsNothing);
      expect(find.text('4'), findsNothing);
    });

    testWidgets('no unread, no dot', (t) async {
      await pumpLive(t, liveServer(unread: 0));
      expect(find.byKey(const Key('newDot')), findsNothing);
    });

    testWidgets('TieredTile.unreadDot draws a shape, announced as "Something new"', (t) async {
      final SemanticsHandle semantics = t.ensureSemantics();
      await t.pumpWidget(wrap(Scaffold(body: TieredTile(
        icon: Icons.mail, label: 'Messages', unreadDot: true, badgeCount: 9, onTap: (_) {}))));
      expect(find.byKey(const Key('newDot')), findsOneWidget);
      expect(find.text('9'), findsNothing);
      expect(find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == 'Something new'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('C-13 — no hard-coded "Dad" shown to the child', () {
    testWidgets('with no known grown-up the child hub says "your grown-up"', (t) async {
      await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.text('Teach your grown-up something'), findsOneWidget);
      expect(find.textContaining('Dad'), findsNothing);
    });

    testWidgets('with a real name it is used', (t) async {
      await t.pumpWidget(wrap(const ChildMoreScreen(
        childName: 'Ivy', childAge: 9, guardianName: 'Nana')));
      expect(find.text('Teach Nana something'), findsOneWidget);
      expect(find.textContaining('Dad'), findsNothing);
    });

    testWidgets('the live home threads the real free parent through to More', (t) async {
      await pumpLive(t, liveServer(presenceFree: {
        'name': 'Marcus', 'theirLocalTime': '6:40 PM', 'freeUntilHerTime': '9:00 PM'}));
      await t.tap(find.text('More for you'));
      await t.pumpAndSettle();
      expect(find.text('Teach Marcus something'), findsOneWidget);
    });

    testWidgets('the child games hub names no Dad when given the neutral name', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen(parentName: neutralGrownUp)));
      expect(find.textContaining('Dad'), findsNothing);
      expect(find.text('Make it harder for your grown-up'), findsOneWidget);
    });

    test('the handicap banner and offer use the real name when given one', () {
      expect(handicapBanner(GameKind.tictactoe, 'no_centre', parentName: 'Nana'),
        "Nana's playing the hard way — Nana can't use the middle square");
      expect(handicapBanner(GameKind.tictactoe, 'no_centre'),
        "Dad's playing the hard way — dad can't use the middle square");
      expect(handicapOffer(GameKind.tictactoe, parentName: 'Nana').prompt,
        'Want to make it harder for Nana?');
      expect(withParentName("Dad can't use the middle square", 'Nana'),
        "Nana can't use the middle square");
    });

    testWidgets('no adult/spec wording survives on the child hubs', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(parentName: neutralGrownUp)));
      for (final String banned in <String>[
        'Async by nature', 'custody weeks', 'Hers and his boards', 'He hides it in her world',
        'family’s own server', '(demo)', 'her own week',
      ]) {
        expect(find.textContaining(banned), findsNothing, reason: '"$banned" is adult wording');
      }
      await t.pumpWidget(wrap(const ChildMoreScreen(childAge: 12)));
      for (final String banned in <String>[
        'Irreversible', 'guardian access', 'preserved', 'Nobody else can read it — ever',
      ]) {
        expect(find.textContaining(banned), findsNothing, reason: '"$banned" is adult wording');
      }
    });
  });

  group('C-14 — nothing guardian-facing or settings-like reachable from the child shell', () {
    testWidgets('the Demo section and "Redo the welcome tour" are gone', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildMoreScreen(childAge: 12)));
      expect(find.text('DEMO'), findsNothing);
      expect(find.text('Redo the welcome tour'), findsNothing);
      expect(find.textContaining('welcome tour'), findsNothing);
    });

    testWidgets('the child games hub never lists the guardian-side setup games', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(parentName: neutralGrownUp)));
      expect(find.text('Word search'), findsNothing);
      expect(find.text('Guess the word'), findsNothing);
      // ...but the rest of the hub is intact.
      expect(find.text('Checkers'), findsOneWidget);
    });

    testWidgets('the guardian side still gets them', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(guardianSide: true, localRole: 'dad')));
      expect(find.text('Word search'), findsOneWidget);
      expect(find.text('Guess the word'), findsOneWidget);
      // A grown-up never sets a handicap on themselves (§9.2).
      expect(find.textContaining('Make it harder'), findsNothing);
    });
  });

  group('C-12 — no card that answers "not built yet"; honest hot-seat wording', () {
    testWidgets('the picker never offers the unbuilt memory game', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamePickerScreen(childAge: 9)));
      expect(unbuiltGameKinds, contains(GameKind.memory));
      expect(find.text(catalogueFor(GameKind.memory).title), findsNothing);
    });

    testWidgets('Surprise me never lands on an unbuilt game', (t) async {
      GameKind? opened;
      int asked = 0;
      await t.pumpWidget(wrap(GamePickerScreen(
        childAge: 9,
        onPlay: (c, k) => opened = k,
        // First answer is the unbuilt kind, then a real one.
        onSurpriseMe: () => catalogueFor(asked++ == 0 ? GameKind.memory : GameKind.story),
      )));
      await t.tap(find.byKey(const Key('surpriseMeButton')));
      await t.pump();
      expect(opened, GameKind.story);
    });

    testWidgets('board games say plainly they are against the game, on this screen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(parentName: neutralGrownUp)));
      expect(find.textContaining('on this screen'), findsNWidgets(3));
    });
  });

  group('C-11 — the ad-hoc table games are reachable from the Play together hub', () {
    testWidgets('the section lists all five for a 7-year-old', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(childAge: 7)));
      expect(find.text('PLAY TOGETHER ON THIS TABLE'), findsOneWidget);
      for (final String title in <String>[
        'War', 'Connect 4', 'Uno', 'Draw and guess', 'Puzzle together']) {
        expect(find.text(title), findsOneWidget, reason: '$title missing');
      }
    });

    testWidgets('it is age-aware: a 4-year-old only gets the puzzle', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(childAge: 4)));
      expect(find.text('Puzzle together'), findsOneWidget);
      expect(find.text('War'), findsNothing);
      expect(find.text('Uno'), findsNothing);
      expect(find.text('Connect 4'), findsNothing);
    });

    testWidgets('tapping Connect 4 opens the real local-play screen as the child (ivy)', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(childName: 'Ivy', childAge: 7)));
      await t.tap(find.text('Connect 4'));
      await t.pumpAndSettle();
      final GameConnect4Screen s = t.widget(find.byType(GameConnect4Screen));
      expect(s.role, 'ivy');
      expect(s.displayName, 'Ivy');
    });

    testWidgets('tapping Uno from the guardian hub plays as the grown-up side', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GamesHubScreen(
        parentName: 'Marcus', childAge: 9, guardianSide: true, localRole: 'dad')));
      await t.tap(find.text('Uno'));
      await t.pumpAndSettle();
      final GameUnoScreen s = t.widget(find.byType(GameUnoScreen));
      expect(s.role, 'dad');
      expect(s.displayName, 'Marcus');
    });

    testWidgets('it is the same hub the child home Play together opens', (t) async {
      await pumpLive(t, liveServer(yearsOld: 7));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.text('PLAY TOGETHER ON THIS TABLE'), findsOneWidget);
    });

    testWidgets('posture-aware: the table section fits the Fold5 cover width without overflow', (t) async {
      for (final Size size in const <Size>[Size(344, 800), Size(673, 841), Size(1000, 700)]) {
        await t.binding.setSurfaceSize(size);
        await t.pumpWidget(wrap(const GamesHubScreen(childAge: 9)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'overflow at $size');
        expect(find.text('PLAY TOGETHER ON THIS TABLE'), findsOneWidget);
      }
      await t.binding.setSurfaceSize(null);
    });
  });

  group('C-22 — the kiosk lock-out screen: picture first, one tap to call, still fail-closed', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(KioskChannel.eventChannel, _NoOpStream());
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(KioskChannel.eventChannel, null);
    });

    Future<void> lockOut(WidgetTester t) async {
      await t.pumpWidget(wrap(KioskShell(
        verifyPin: (_) async => false, verifyBiometric: () async => false,
        callerName: 'Ivy', child: const Text('child home'))));
      await t.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byKey(const Key('guardianEscalationTrigger')));
        await t.pumpAndSettle();
        for (var d = 0; d < 4; d++) {
          await t.tap(find.text('1').first);
          await t.pump();
        }
        await t.pumpAndSettle(const Duration(seconds: 3));
      }
    }

    testWidgets('shows a big picture, big words and a Call button', (t) async {
      await lockOut(t);
      expect(find.text('Take a little break'), findsOneWidget);
      expect(find.text('child home'), findsNothing);
      final Icon pic = t.widget(find.byIcon(Icons.bedtime_outlined));
      expect(pic.size, greaterThanOrEqualTo(80));
      final Text title = t.widget(find.text('Take a little break'));
      expect(title.style!.fontSize, greaterThanOrEqualTo(28));
      expect(t.getSize(find.byKey(const Key('lockedOutCall'))).height, greaterThanOrEqualTo(64));
    });

    testWidgets('one tap on Call opens her call screen, and the lock stays closed', (t) async {
      await lockOut(t);
      await t.tap(find.byKey(const Key('lockedOutCall')));
      await t.pump();
      await t.pump();
      final CallScreen call = t.widget(find.byType(CallScreen));
      expect(call.who, 'ivy');
      expect(call.displayName, 'Ivy');
    });

    testWidgets('the grown-up way back in is still there and still needs the PIN', (t) async {
      await lockOut(t);
      expect(find.text("I'm the grown-up"), findsOneWidget);
      expect(find.text('child home'), findsNothing);
    });
  });

  group('G-08 — guardian home tiles carry the live identity, never the demo fixture', () {
    GuardianHome home({String? baseUrl, String? guardianId, String? childId, http.Client? client}) =>
        GuardianHome(
          childName: 'Ivy', childLocalTime: '9:14 PM', childZoneAbbr: 'EST', actorLocalTime: '6:14 PM',
          childStateSentence: null, childBands: const <RibbonBand>[], actorBands: const <RibbonBand>[],
          baseUrl: baseUrl, guardianId: guardianId, childId: childId, availabilityHttpClient: client);

    MockClient liveGuardianServer(List<String> paths) => MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode({'token': 'g'}), 200);
          if (req.url.path.endsWith('/emergency-card')) {
            return http.Response(jsonEncode({
              'allergies': <String>['kiwi'], 'conditions': <String>[], 'version': 2,
              'lastChange': {'byName': 'Marcus', 'at': '2026-11-01T10:00:00.000Z'},
            }), 200);
          }
          if (req.url.path.endsWith('/medications')) {
            return http.Response(jsonEncode({'medications': <dynamic>[], 'doses': <dynamic>[]}), 200);
          }
          return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
        });

    testWidgets('Emergency card on the home grid fetches the REAL card, not the demo peanut allergy',
        (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final paths = <String>[];
      await t.pumpWidget(wrap(home(
        baseUrl: 'http://api.test', guardianId: 'g-1', childId: 'c-1', client: liveGuardianServer(paths))));
      await t.tap(find.text('Emergency card'));
      await t.pumpAndSettle();
      final EmergencyCardScreen s = t.widget(find.byType(EmergencyCardScreen));
      expect(s.baseUrl, 'http://api.test');
      expect(s.guardianId, 'g-1');
      expect(s.childId, 'c-1');
      expect(paths.any((p) => p == '/v1/children/c-1/emergency-card'), isTrue);
      expect(find.textContaining('kiwi'), findsWidgets);
      expect(find.textContaining('eanut'), findsNothing);
    });

    testWidgets('all five coordination tiles hand the live triple to their screen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final paths = <String>[];
      final client = liveGuardianServer(paths);
      for (final entry in <(String, Type)>[
        ('Meds & care', MedsCareScreen), ('Emergency card', EmergencyCardScreen),
        ('Handover notes', HandoverNotesScreen), ('Exchange', ExchangeScreen),
        ('Expenses', ExpensesScreen),
      ]) {
        // A fresh tree each time, or MaterialApp keeps the previous pushed route.
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(wrap(home(
          baseUrl: 'http://api.test', guardianId: 'g-1', childId: 'c-1', client: client)));
        await t.tap(find.text(entry.$1));
        await t.pumpAndSettle();
        final Widget w = t.widget(find.byType(entry.$2));
        final (String?, String?, String?) triple = switch (w) {
          final MedsCareScreen s => (s.baseUrl, s.guardianId, s.childId),
          final EmergencyCardScreen s => (s.baseUrl, s.guardianId, s.childId),
          final HandoverNotesScreen s => (s.baseUrl, s.guardianId, s.childId),
          final ExchangeScreen s => (s.baseUrl, s.guardianId, s.childId),
          final ExpensesScreen s => (s.baseUrl, s.guardianId, s.childId),
          _ => (null, null, null),
        };
        expect(triple, ('http://api.test', 'g-1', 'c-1'), reason: entry.$1);
      }
    });

    testWidgets('a half-wired live session (baseUrl but no ids) refuses instead of opening demo data',
        (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home(baseUrl: 'http://api.test')));
      await t.tap(find.text('Emergency card'));
      await t.pump();
      await t.pump();
      expect(find.byType(EmergencyCardScreen), findsNothing);
      expect(find.textContaining('not connected'), findsOneWidget);
    });

    testWidgets('the offline demo build still opens the demo card', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home()));
      await t.tap(find.text('Emergency card'));
      await t.pumpAndSettle();
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
    });
  });

  group('G-12 — a live guardian More hub never shows invented family history', () {
    const demoTitles = <String>[
      'Year book', 'Gallery', 'The book', 'Closing ritual (demo)',
      'Live call quality (demo)', 'Busy fork (demo)',
    ];

    Future<void> pumpMore(WidgetTester t, GuardianMoreScreen s) async {
      await t.binding.setSurfaceSize(const Size(900, 6000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(s));
    }

    testWidgets('live session: none of the demo tiles, and not the hard-coded colour history', (t) async {
      await pumpMore(t, const GuardianMoreScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'g-1'));
      for (final title in demoTitles) {
        expect(find.text(title), findsNothing, reason: '$title is invented content');
      }
      expect(find.text("Ivy's colour"), findsNothing);
      // The real tiles are untouched.
      expect(find.text('Court export'), findsOneWidget);
      expect(find.text('Emergency card'), findsOneWidget);
    });

    testWidgets('offline demo build: they are all still there', (t) async {
      await pumpMore(t, const GuardianMoreScreen(childName: 'Ivy'));
      for (final title in demoTitles) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text("Ivy's colour"), findsOneWidget);
    });

    testWidgets('a dev entry point can still opt in explicitly', (t) async {
      await pumpMore(t, const GuardianMoreScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'g-1', showDemoTiles: true));
      expect(find.text('Year book'), findsOneWidget);
    });
  });
}

class _NoOpStream extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}
  @override
  void onCancel(Object? arguments) {}
}
