// OLIVE BRANCH — what she CALLS her grown-ups, adopted by the child-facing screens. No longer UNVERIFIED — verified by CI.
// MASTERFILE §8.5.7. Every screen that used to hard-code 'Dad' or 'Mom' now reads her word
// through grownup_labels.dart (contact_labels.dart underneath): her nickname first, else the
// age default (Mommy/Daddy for a locked age 5 to 15), else the guardian's label, and with no
// family known the neutral 'your grown-up'. Three cases for each touched screen.
//
// Also here: the on-device data catalogue must have a plain-words name for EVERY area (a raw
// area id such as 'explainers' once reached a grown-up's screen).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/a11y_speech.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/clear_local_data_screen.dart';
import 'package:olive_client/co_view_logic.dart';
import 'package:olive_client/co_view_screens.dart';
import 'package:olive_client/co_view_session.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/degradation_banner.dart';
import 'package:olive_client/exchange_screen.dart';
import 'package:olive_client/game_hunt.dart';
import 'package:olive_client/game_logic.dart' hide Side;
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_tictactoe.dart';
import 'package:olive_client/games_hub.dart';
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/handicap_screen.dart';
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/weeks_screen.dart';

const GrownupContact _dad = GrownupContact(id: 'g-dad', guardianLabel: 'Dad', kind: GrownupKind.dad);
const GrownupContact _mom = GrownupContact(id: 'g-mom', guardianLabel: 'Mom', kind: GrownupKind.mom);
const AgeLockState _nine = AgeLockState(age: 9, locked: true);

/// Her nickname for Dad is set.
const GrownupLabels _nick = GrownupLabels(
    contacts: <GrownupContact>[_dad, _mom], age: _nine, primaryId: 'g-dad',
    nicknames: <String, String>{'g-dad': 'Dada', 'g-mom': 'Mama'});

/// No nickname: the age default applies (locked, age 9).
const GrownupLabels _ageDefault =
    GrownupLabels(contacts: <GrownupContact>[_dad, _mom], age: _nine, primaryId: 'g-dad');

/// No family yet.
const GrownupLabels _noFamily = GrownupLabels.none;

Widget _scoped(GrownupLabels l, Widget child) =>
    MaterialApp(home: GrownupLabelScope(labels: l, child: child));

void main() {
  group('the catalogue names every area (so a raw id never reaches the screen)', () {
    test('every localDataCatalogue area has a plain-words display name', () {
      final List<String> missing = <String>[
        for (final LocalDataEntry e in localDataCatalogue)
          if (!kLocalDataAreaNames.containsKey(e.area) || kLocalDataAreaNames[e.area]!.trim().isEmpty) e.area,
      ];
      expect(missing, isEmpty, reason: 'add a display name to kLocalDataAreaNames for: $missing');
    });

    test('no name is just the raw area id, and the table has no stale extras', () {
      for (final LocalDataEntry e in localDataCatalogue) {
        expect(kLocalDataAreaNames[e.area], isNot(e.area), reason: e.area);
      }
      final Set<String> areas = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};
      expect(kLocalDataAreaNames.keys.where((String k) => !areas.contains(k)), isEmpty);
    });

    testWidgets('the screen shows the five that were raw ids (family, growing, care, explainers, access)',
        (t) async {
      final LocalServices services = LocalServices.memory();
      t.view.physicalSize = const Size(900, 24000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          home: ClearLocalDataScreen(verifyPin: (String _) async => true, services: services)));
      for (final String area in <String>['family', 'growing', 'care', 'explainers', 'access']) {
        expect(find.text(kLocalDataAreaNames[area]!), findsOneWidget, reason: area);
        expect(find.text(area), findsNothing, reason: 'the raw id "$area" must not be a title');
      }
    });
  });

  group('GrownupLabels: nickname, then age default, then guardian label, else neutral', () {
    test('her nickname wins; then Mommy/Daddy at a locked 5 to 15; then neutral with no family', () {
      expect(_nick.nameFor('g-dad'), 'Dada');
      expect(_nick.nameFor(), 'Dada', reason: 'no id means the primary grown-up');
      expect(_ageDefault.nameFor('g-dad'), 'Daddy');
      expect(_ageDefault.nameFor('g-mom'), 'Mommy');
      expect(_noFamily.nameFor(), neutralGrownUp);
      expect(_nick.nameFor('not-a-contact'), neutralGrownUp, reason: 'an unknown id is never guessed');
    });

    test('an unlocked or 16+ age keeps Mom and Dad; a non-parent keeps the guardian label', () {
      const GrownupContact gran = GrownupContact(id: 'g-gran', guardianLabel: 'Nana');
      const GrownupLabels teen = GrownupLabels(
          contacts: <GrownupContact>[_dad, gran], age: AgeLockState(age: 16, locked: true), primaryId: 'g-dad');
      expect(teen.nameFor('g-dad'), 'Dad');
      expect(teen.nameFor('g-gran'), 'Nana');
      expect(const GrownupLabels(contacts: <GrownupContact>[_dad]).nameFor(), 'Dad', reason: 'only one: the primary');
    });

    test('a guardian sees both where a nickname exists', () {
      expect(_nick.forGuardian('g-dad', childName: 'Ivy'), 'Ivy calls you Dada');
      expect(_ageDefault.forGuardian('g-dad', childName: 'Ivy'), 'Dad');
    });

    test('two home names follow her words and pad with neutral placeholders', () {
      expect(_nick.twoNames(), <String>['Dada', 'Mama']);
      expect(_noFamily.twoNames(), kNeutralHomeNames);
    });

    test('asSubject only raises the first letter', () {
      expect(asSubject('your grown-up'), 'Your grown-up');
      expect(asSubject('Dada'), 'Dada');
      expect(asSubject(''), '');
    });

    test('the handicap wording reads in her words, at the start of a sentence too', () {
      expect(withParentName("Dad can't use the middle square", neutralGrownUp),
          "Your grown-up can't use the middle square");
      expect(withParentName("Dad can't use the middle square", 'Dada'), "Dada can't use the middle square");
      expect(handicapBanner(GameKind.tictactoe, 'no_centre', parentName: neutralGrownUp),
          "Your grown-up's playing the hard way — your grown-up can't use the middle square");
      expect(handicapOffer(GameKind.tictactoe).prompt, 'Want to make it harder for your grown-up?');
    });

    test('the read-aloud label never hard-codes a name', () {
      expect(speakableText('send_show', 'x'), 'Send this to your grown-up');
      expect(speakableText('send_show', 'x', grownUp: 'Dada'), 'Send this to Dada');
      expect(labels.values.any((String v) => RegExp(r'\b(Mom|Dad|Mommy|Daddy)\b').hasMatch(v)), isFalse);
    });
  });

  group('the provider only READS her nicknames', () {
    testWidgets('it shows the nickname from the child\'s own store and writes nothing', (t) async {
      final LocalServices services = LocalServices.memory(childId: 'c-1');
      final LocalNicknameRepository hers = LocalNicknameRepository(services.area('nicknames', ownerId: 'c-1'));
      await t.runAsync(() => hers.set('g-dad', 'Papa'));
      late BuildContext inner;
      await t.pumpWidget(MaterialApp(
        home: GrownupLabelsProvider(
          contacts: const <GrownupContact>[_dad],
          primaryId: 'g-dad',
          age: _nine,
          services: services,
          childId: 'c-1',
          child: Builder(builder: (BuildContext c) {
            inner = c;
            return Text(GrownupLabelScope.of(c).nameFor());
          }),
        ),
      ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
      expect(find.text('Papa'), findsOneWidget);
      expect(GrownupLabelScope.read(inner).nicknames, <String, String>{'g-dad': 'Papa'});
      expect(await t.runAsync(hers.load), <String, String>{'g-dad': 'Papa'}, reason: 'unchanged');
    });

    testWidgets('a store that cannot be read shows the defaults, never a crash', (t) async {
      await t.pumpWidget(MaterialApp(
        home: GrownupLabelsProvider(
          contacts: const <GrownupContact>[_dad],
          primaryId: 'g-dad',
          age: _nine,
          reader: _BrokenReader(),
          child: Builder(builder: (BuildContext c) => Text(GrownupLabelScope.of(c).nameFor())),
        ),
      ));
      await t.pump();
      expect(find.text('Daddy'), findsOneWidget);
    });
  });

  group('games hub: "Make it harder for ___"', () {
    testWidgets('nickname', (t) async {
      await t.pumpWidget(_scoped(_nick, const GamesHubScreen()));
      expect(find.text('Make it harder for Dada'), findsOneWidget);
    });
    testWidgets('age default', (t) async {
      await t.pumpWidget(_scoped(_ageDefault, const GamesHubScreen()));
      expect(find.text('Make it harder for Daddy'), findsOneWidget);
    });
    testWidgets('no family: neutral', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const GamesHubScreen()));
      expect(find.text('Make it harder for your grown-up'), findsOneWidget);
      expect(find.textContaining('Dad'), findsNothing);
    });
    testWidgets('a name passed in still wins, as before', (t) async {
      await t.pumpWidget(_scoped(_nick, const GamesHubScreen(parentName: 'Nana')));
      expect(find.text('Make it harder for Nana'), findsOneWidget);
    });
  });

  group('game picker: "Play against ___"', () {
    testWidgets('nickname / age default / no family', (t) async {
      t.view.physicalSize = const Size(1200, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_scoped(_nick, const GamePickerScreen()));
      expect(find.text('Play against Dada'), findsWidgets);
      await t.pumpWidget(_scoped(_ageDefault, const GamePickerScreen()));
      expect(find.text('Play against Daddy'), findsWidgets);
      await t.pumpWidget(_scoped(_noFamily, const GamePickerScreen()));
      expect(find.text('Play against your grown-up'), findsWidgets);
      expect(find.textContaining('Dad'), findsNothing);
    });
  });

  group('games and the handicap screen default to the neutral phrase, and take her word when given', () {
    testWidgets('handicap screen', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const HandicapScreen(kind: GameKind.tictactoe)));
      expect(find.textContaining('Pick something tricky for your grown-up to deal with'), findsOneWidget);
      expect(find.text("Your grown-up can't use the middle square"), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const HandicapScreen(kind: GameKind.tictactoe, parentName: 'Dada')));
      expect(find.text("Dada can't use the middle square"), findsOneWidget);
    });

    testWidgets('hunt', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const GameHuntScreen()));
      expect(find.text('Your grown-up hid these around the house'), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const GameHuntScreen(parentName: 'Daddy')));
      expect(find.text('Daddy hid these around the house'), findsOneWidget);
    });

    testWidgets('tic-tac-toe turn line', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const GameTicTacToe()));
      expect(find.textContaining('Dad'), findsNothing);
      await t.pumpWidget(_scoped(_noFamily, const GameTicTacToe(parentName: 'Dada')));
      expect(find.textContaining('Dad'), findsNothing, reason: '"Dada" is not the word Dad, and no Dad is left');
    });
  });

  group('child home: the presence card and the Play-together / More doors', () {
    testWidgets('presence card uses her word when the grown-up\'s id is known', (t) async {
      const ParentPresence p = ParentPresence('Dad', '6:42 PM', '9:00 PM her time', userId: 'g-dad');
      const ChildHome home =
          ChildHome(childName: 'Ivy', presence: p, sleepsUntilHandover: 3, unreadCount: 0);
      await t.pumpWidget(_scoped(_nick, home));
      expect(find.text('Dada is free right now'), findsOneWidget);
      expect(find.text('Call Dada'), findsOneWidget);
      await t.pumpWidget(_scoped(_ageDefault, home));
      expect(find.text('Daddy is free right now'), findsOneWidget);
      expect(find.text('Call Daddy'), findsOneWidget);
    });

    testWidgets('presence card with no family keeps the live display name it was given', (t) async {
      const ChildHome home = ChildHome(
          childName: 'Ivy',
          presence: ParentPresence('Dad', '6:42 PM', '9:00 PM her time', userId: 'g-dad'),
          sleepsUntilHandover: 3,
          unreadCount: 0);
      await t.pumpWidget(_scoped(_noFamily, home));
      expect(find.text('Dad is free right now'), findsOneWidget);
    });

    testWidgets('More for you: "Teach ___ something" in her words, neutral with no family', (t) async {
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_scoped(_nick, const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.text('Teach Dada something'), findsOneWidget);
      await t.pumpWidget(_scoped(_ageDefault, const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.text('Teach Daddy something'), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.text('Teach your grown-up something'), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const ChildMoreScreen(childName: 'Ivy', childAge: 9, guardianName: 'Nana')));
      expect(find.text('Teach Nana something'), findsOneWidget, reason: 'a live name is used when no family is in scope');
    });
  });

  group('co-viewing invitation', () {
    Future<CoViewFollower> pumpIt(WidgetTester t, GrownupLabels l) async {
      const Principal g = Principal(kind: 'guardian', role: 'guardian');
      const Principal c = Principal(kind: 'child');
      const CoViewStory story = CoViewStory(id: 'owl-1', title: 'The owl', pages: <CoViewStoryPage>[CoViewStoryPage('Far above.')]);
      final (gt, ct) = LoopbackTransport.pair(g, c);
      final CoViewLeader leader =
          CoViewLeader(transport: gt, me: g, story: story, limitMin: 120, usedSeconds: 0, nowMs: () => 0);
      final CoViewFollower follower = CoViewFollower(transport: ct, me: c, story: story, budget: () => leader.budget);
      await t.pumpWidget(_scoped(l, CoViewChildScreen(follower: follower)));
      leader.start();
      await t.pump();
      return follower;
    }

    testWidgets('nickname', (t) async {
      await pumpIt(t, _nick);
      expect(find.text('Dada wants to read a story with you'), findsOneWidget);
    });
    testWidgets('age default', (t) async {
      await pumpIt(t, _ageDefault);
      expect(find.text('Daddy wants to read a story with you'), findsOneWidget);
    });
    testWidgets('no family: neutral, starting a sentence', (t) async {
      await pumpIt(t, _noFamily);
      expect(find.text('Your grown-up wants to read a story with you'), findsOneWidget);
    });
  });

  group('call degradation screen: "Call with ___"', () {
    testWidgets('nickname / age default / neutral / a given name when no family is in scope', (t) async {
      await t.pumpWidget(_scoped(_nick, const LiveDegradeScreen()));
      expect(find.text('Call with Dada'), findsOneWidget);
      await t.pumpWidget(_scoped(_ageDefault, const LiveDegradeScreen()));
      expect(find.text('Call with Daddy'), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const LiveDegradeScreen()));
      expect(find.text('Call with your grown-up'), findsOneWidget);
      await t.pumpWidget(_scoped(_noFamily, const LiveDegradeScreen(callerName: 'Nana')));
      expect(find.text('Call with Nana'), findsOneWidget);
      // dispose the periodic timer
      await t.pumpWidget(const SizedBox());
    });
  });

  group('inbox: "___ sent a video"', () {
    const List<InboxMessage> withId = <InboxMessage>[
      InboxMessage(id: '1', senderName: 'Dad', senderId: 'g-dad', deliveredAtLabel: '7:04 AM'),
    ];
    testWidgets('nickname / age default', (t) async {
      await t.pumpWidget(_scoped(_nick, const InboxScreen(childName: 'Ivy', messages: withId)));
      expect(find.text('Dada sent a video'), findsOneWidget);
      await t.pumpWidget(_scoped(_ageDefault, const InboxScreen(childName: 'Ivy', messages: withId)));
      expect(find.text('Daddy sent a video'), findsOneWidget);
    });
    testWidgets('no family: the demo fixture is neutral, a live sender keeps the name the server gave', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const InboxScreen(childName: 'Ivy', messages: demoInboxMessages)));
      expect(find.text('Your grown-up sent a video'), findsNWidgets(2));
      expect(find.textContaining('Dad'), findsNothing);
      expect(find.textContaining('Grandma'), findsNothing);
      await t.pumpWidget(const SizedBox()); // a fresh screen: it keeps its first list in state
      await t.pumpWidget(_scoped(_noFamily, const InboxScreen(childName: 'Ivy', messages: withId)));
      expect(find.text('Dad sent a video'), findsOneWidget);
    });
  });

  group('journal privacy banner: "not ___, not ___, not anyone"', () {
    testWidgets('nickname', (t) async {
      await t.pumpWidget(_scoped(_nick, const JournalScreen(childName: 'Maya')));
      expect(find.textContaining('not Dada, not Mama, not anyone.'), findsOneWidget);
    });
    testWidgets('age default', (t) async {
      await t.pumpWidget(_scoped(_ageDefault, const JournalScreen(childName: 'Maya')));
      expect(find.textContaining('not Daddy, not Mommy, not anyone.'), findsOneWidget);
    });
    testWidgets('no family: neutral', (t) async {
      await t.pumpWidget(_scoped(_noFamily, const JournalScreen(childName: 'Maya')));
      expect(find.textContaining('not your grown-ups, not anyone.'), findsOneWidget);
      expect(find.textContaining('mom'), findsNothing);
      expect(find.textContaining('dad'), findsNothing);
    });
  });

  group('my weeks: the two homes in her words', () {
    Widget weeks(GrownupLabels l) {
      final List<String> names = l.twoNames();
      return WeeksScreen(
          childName: 'Ivy',
          nights: demoCustodyNights(today: DateTime(2026, 8, 4), names: names),
          guardianColors: demoGuardianColorsFor(names));
    }

    testWidgets('nickname', (t) async {
      await t.pumpWidget(_scoped(_nick, weeks(_nick)));
      expect(find.textContaining("You're with Dada right now"), findsOneWidget);
    });
    testWidgets('age default', (t) async {
      await t.pumpWidget(_scoped(_ageDefault, weeks(_ageDefault)));
      expect(find.textContaining("You're with Daddy right now"), findsOneWidget);
    });
    testWidgets('no family: neutral placeholders, never Mom and Dad', (t) async {
      await t.pumpWidget(_scoped(_noFamily, weeks(_noFamily)));
      expect(find.textContaining("You're with Grown-up one right now"), findsOneWidget);
      expect(find.textContaining('Mom'), findsNothing);
      expect(find.textContaining('Dad'), findsNothing);
    });
  });

  group('exchange (a guardian screen): the two sides use the guardians\' own labels', () {
    testWidgets('with a family: their labels', (t) async {
      t.view.physicalSize = const Size(900, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_scoped(_nick, const ExchangeScreen()));
      expect(find.textContaining("Mom's time"), findsWidgets);
    });
    testWidgets('no family: neutral', (t) async {
      t.view.physicalSize = const Size(900, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_scoped(_noFamily, const ExchangeScreen()));
      expect(find.textContaining("Grown-up one's time"), findsWidgets);
      expect(find.textContaining('Mom'), findsNothing);
    });
    testWidgets('a given map wins', (t) async {
      t.view.physicalSize = const Size(900, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_scoped(_noFamily, const ExchangeScreen(sideNames: <Side, String>{Side.a: 'Nana', Side.b: 'Papa'})));
      expect(find.textContaining("Nana's time"), findsWidgets);
    });
  });
}

class _BrokenReader implements NicknameReader {
  @override
  Future<Map<String, String>> load() async => throw StateError('store unreadable');
}
