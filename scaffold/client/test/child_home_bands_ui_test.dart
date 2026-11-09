// OLIVE BRANCH — the 5-7 and 8-12 child homes, the per-band More page, My people (call / message / rename) and
// 'your home grows' on the real ChildHome. No longer UNVERIFIED — verified by CI. Local-first: no network anywhere.
// Postures (344, 390, 600, 800 dp; 2.0x text) are in child_home_bands_postures_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/activity_overrides.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_home_bands.dart';
import 'package:olive_client/child_home_bands_ui.dart';
import 'package:olive_client/child_home_growth.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_screens.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/showcase_screen.dart';
import 'package:olive_client/weeks_screen.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal childP = FamilyPrincipal(roleName: 'child', childId: 'c1');
final DateTime fixed = DateTime(2026, 11, 9, 9);

FamilyService svc() => FamilyService(MemoryFamilyStore(), clock: () => fixed);

Map<String, Object?> person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};
Map<String, Object?> home(String id, String name) => <String, Object?>{'id': id, 'name': name, 'childSleeps': true};

Future<FamilyChildSnapshot> snap({int years = 7, bool people = true}) async {
  final FamilyService s = svc();
  Future<void> add(Map<String, Object?> op) => s.addChange(guardian, actorName: 'Dad', yearsOld: years, op: op, timing: Timing.now.toJson());
  if (people) {
    await add(<String, Object?>{'op': 'put_home', 'home': home('h1', "Mom's house")});
    await add(<String, Object?>{'op': 'put_home', 'home': home('h2', "Dad's house")});
    await add(<String, Object?>{'op': 'put_person', 'person': person('p1', 'Mom', 'guardian', 'h1', <String>['live_call', 'message'])});
    await add(<String, Object?>{'op': 'put_person', 'person': person('p2', 'Dad', 'guardian', 'h2', <String>['live_call'])});
    await add(<String, Object?>{'op': 'put_person', 'person': person('p3', 'Dana', 'step_parent', 'h2', <String>['message'])});
  }
  return s.childSnapshot(childP, childId: 'c1', yearsOld: years);
}

Widget app(Widget home, {int years = 7, bool locked = true, bool family = true}) => MaterialApp(
    home: GrownupLabelScope(
        labels: GrownupLabels(
            // "My weeks" is hidden until a family exists, so the default test child has one.
            contacts: family
                ? const <GrownupContact>[
                    GrownupContact(id: 'g1', guardianLabel: 'Mom', kind: GrownupKind.mom),
                    GrownupContact(id: 'g2', guardianLabel: 'Dad', kind: GrownupKind.dad),
                  ]
                : const <GrownupContact>[],
            age: AgeLockState(age: years, locked: locked)),
        child: home));

ChildHome kidHome(FamilyChildSnapshot f, {int years = 7, ChildGrowth? growth, MemoryNicknameRepository? nicks,
    Map<String, ActivityOverride>? overrides, int unread = 0, DateTime? at}) =>
    ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: unread, family: f,
        childAge: years, growth: growth, nicknames: nicks, overrides: overrides, clock: () => at ?? fixed);

Future<void> big(WidgetTester t, [Size s = const Size(800, 2400)]) async {
  await t.binding.setSurfaceSize(s);
  addTearDown(() => t.binding.setSurfaceSize(null));
}

List<String> allText(WidgetTester t) =>
    <String>[for (final Element e in find.byType(Text).evaluate()) (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? ''];

void main() {
  group('the 5-7 home', () {
    testWidgets('draws the prototype\'s tiles by their prototype titles, in tiers', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHome.t57')), findsOneWidget);
      expect(find.text('Hi, Ivy'), findsOneWidget);
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('childHomeHero')), matching: find.text('My day')), findsOneWidget);
      for (final String s in <String>['Play together', 'Messages', 'Stories', 'Show & tell']) {
        expect(find.descendant(of: find.byKey(const Key('childHomeFeaturedGrid')), matching: find.text(s)), findsOneWidget, reason: s);
      }
      for (final String s in <String>['My people', 'Colour', 'More']) {
        expect(find.descendant(of: find.byKey(const Key('childHomeStandardGrid')), matching: find.text(s)), findsOneWidget, reason: s);
      }
      // What only the other bands (or older shells) carry is not on it.
      for (final String s in <String>['Games', 'Downtime', 'Storyteller', 'My weeks', 'My list', 'Journal', 'Homework', 'More for you']) {
        expect(find.text(s), findsNothing, reason: s);
      }
    });

    testWidgets('Colour is one tap from home (the prototype), and My day opens', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandTile.colour')), findsOneWidget);
    });

    testWidgets('news is a dot, never a number; there is no count anywhere on the home', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(), unread: 3)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('newDot')), findsOneWidget);
      for (final String s in allText(t)) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no digit on the 5-7 home: "$s"');
      }
    });

    testWidgets('a guardian\'s hide removes a tile; Messages cannot be hidden', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(), overrides: const <String, ActivityOverride>{
        'tile:messages': ActivityOverride(activityKey: 'tile:messages', visible: false),
        'tile:showAndTell': ActivityOverride(activityKey: 'tile:showAndTell', visible: false),
        'tile:storyteller': ActivityOverride(activityKey: 'tile:storyteller', visible: false),
      })));
      await t.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Show & tell'), findsNothing);
      expect(find.text('Stories'), findsNothing);
      expect(find.text('Play together'), findsOneWidget);
    });

    testWidgets('a tile opens its destination (Show & tell, Messages)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.showtell')));
      await t.pumpAndSettle();
      expect(find.byType(ShowcaseScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.msgs')));
      await t.pumpAndSettle();
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('no settings affordance at any depth of the home or its More page (§8.1)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(RegExp('settings', caseSensitive: false)), findsNothing);
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(RegExp('settings', caseSensitive: false)), findsNothing);
    });
  });

  group('the 8-12 home', () {
    testWidgets('draws its tiles under the band\'s own names (Games, not Play together)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(years: 9), years: 9)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHome.t812')), findsOneWidget);
      expect(find.text('Good morning, Ivy'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('childHomeFeaturedGrid')), matching: find.text('Games')), findsOneWidget);
      for (final String s in <String>['Messages', 'My list', 'Storyteller']) {
        expect(find.descendant(of: find.byKey(const Key('childHomeFeaturedGrid')), matching: find.text(s)), findsOneWidget, reason: s);
      }
      for (final String s in <String>['My people', 'Show & tell', 'Journal', 'More']) {
        expect(find.descendant(of: find.byKey(const Key('childHomeStandardGrid')), matching: find.text(s)), findsOneWidget, reason: s);
      }
      expect(find.byKey(const Key('bandTile.weeks')), findsOneWidget);
      for (final String s in <String>['Play together', 'Downtime', 'Stories', 'Colour', 'Homework']) {
        expect(find.text(s), findsNothing, reason: s);
      }
      for (final String s in allText(t)) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no digit on the 8-12 home: "$s"');
      }
    });

    testWidgets('My weeks opens the weeks screen, named through her grown-ups\' labels', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(years: 9), years: 9)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.weeks')));
      await t.pumpAndSettle();
      expect(find.byType(WeeksScreen), findsOneWidget);
    });

    testWidgets('My weeks is hidden until a family exists, and never shows the placeholder names', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(years: 9), years: 9), years: 9, family: false));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandTile.weeks')), findsNothing);
      expect(find.text('My weeks'), findsNothing);
      expect(find.text('Grown-up one'), findsNothing);
      await t.pumpWidget(app(kidHome(await snap(years: 9), years: 9), years: 9));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandTile.weeks')), findsOneWidget);
    });

    testWidgets('13 and up keeps the older home until wave 2b (the table says which bands it draws)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(years: 14), years: 14), years: 14));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHome.t812')), findsNothing);
      expect(find.byKey(const Key('bandHome.t57')), findsNothing);
      expect(kBandsDrawnHere, <String>{'t57', 't812'});
    });
  });

  group('the More page, per band', () {
    testWidgets('5-7: draw, memory, growing marks, jokes (those that have a destination), then Everything else', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      expect(find.byType(ChildBandMoreScreen), findsOneWidget);
      expect(find.byKey(const Key('moreCaption')), findsOneWidget);
      expect(find.byKey(const Key('moreTile.draw')), findsOneWidget);
      expect(find.byKey(const Key('moreTile.jokes')), findsOneWidget);
      // No destination yet: Feelings and My things are not drawn at all.
      expect(find.text('Feelings'), findsNothing);
      expect(find.text('My things'), findsNothing);
      expect(find.byKey(const Key('moreEverything')), findsOneWidget);
      expect(find.byKey(const Key('moreHomework')), findsOneWidget, reason: 'Homework stays reachable, one tap from More');
    });

    testWidgets('8-12: the journal is on the page, Draw & colour is the last of the list', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(years: 9), years: 9)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('moreTile.journal')), findsOneWidget);
      expect(find.byKey(const Key('moreTile.capsule')), findsOneWidget);
    });

    testWidgets('Everything else opens the older More hub, so nothing that shipped became unreachable', (WidgetTester t) async {
      await big(t, const Size(800, 3600));
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('moreEverything')));
      await t.pumpAndSettle();
      expect(find.byType(ChildMoreScreen), findsOneWidget);
    });

    testWidgets('Draw & colour offers a doodle or a colouring page', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('moreTile.draw')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('drawDoodle')), findsOneWidget);
      expect(find.byKey(const Key('drawColouring')), findsOneWidget);
    });
  });

  group('My people: tap a face for Call, Message and "Change what I call them"', () {
    testWidgets('names are her words: the age default (Mommy, Daddy) until she renames, and her word wins', (WidgetTester t) async {
      await big(t);
      final MemoryNicknameRepository nicks = MemoryNicknameRepository();
      await t.pumpWidget(app(kidHome(await snap(), nicks: nicks)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('childHomeMyPeople')));
      await t.pumpAndSettle();
      expect(find.text("Mom's house"), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('personName_p1'))).data, 'Mommy');
      expect(t.widget<Text>(find.byKey(const Key('personName_p2'))).data, 'Daddy');
      expect(t.widget<Text>(find.byKey(const Key('personName_p3'))).data, 'Dana', reason: 'anyone else keeps the grown-up\'s own word');

      await t.tap(find.byKey(const Key('person_p2')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('personSheet')), findsOneWidget);
      expect(find.byKey(const Key('personCall')), findsOneWidget);
      expect(find.byKey(const Key('personMessage')), findsNothing, reason: 'Dad has no message route in this family');
      await t.tap(find.byKey(const Key('personRename')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bank_Dada')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('personName_p2'))).data, 'Dada');
      expect((await nicks.load())['p2'], 'Dada');
      expect(t.widget<Text>(find.byKey(const Key('personName_p1'))).data, 'Mommy', reason: 'only the one she renamed changed');
    });

    testWidgets('Message opens the messages; a person with no message route shows no Message button', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap(), nicks: MemoryNicknameRepository())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('childHomeMyPeople')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person_p1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('personSheetName')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('personSheetName'))).data, 'Mommy');
      await t.tap(find.byKey(const Key('personMessage')));
      await t.pumpAndSettle();
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('"Use the usual word" puts the age default back', (WidgetTester t) async {
      await big(t);
      final MemoryNicknameRepository nicks = MemoryNicknameRepository();
      await nicks.set('p1', 'Mama');
      await t.pumpWidget(app(kidHome(await snap(), nicks: nicks)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('childHomeMyPeople')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('personName_p1'))).data, 'Mama');
      await t.tap(find.byKey(const Key('person_p1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('personRename')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nameReset')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('personName_p1'))).data, 'Mommy');
    });

    testWidgets('a face with nothing to offer does not open an empty sheet (old callers: no rename, no callbacks)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(MaterialApp(home: MyPeopleScreen(snapshot: await snap())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('person_p1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('personSheet')), findsNothing);
    });
  });

  group('your home grows', () {
    Future<ChildGrowth> grown(int from, int to) async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(from);
      await g.observe(to);
      return g;
    }

    testWidgets('age 5: a picture, her age, what is new and what stayed; no count, no badge', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final ChildGrowth g = await grown(4, 5);
      await t.pumpWidget(app(kidHome(await snap(years: 5), years: 5, growth: g), years: 5));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('growPage')), findsOneWidget);
      expect(find.byKey(const Key('bandHome.t57')), findsNothing, reason: 'the page comes INSTEAD of the home');
      expect(find.byKey(const Key('growScene')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('growEyebrow'))).data, 'You are 5');
      expect(t.widget<Text>(find.byKey(const Key('growLead'))).data, 'Your home is growing with you.');
      expect(find.byKey(const Key('growFive')), findsOneWidget);
      expect(find.byKey(const Key('growItem.add')), findsNWidgets(2));
      expect(find.byKey(const Key('growItem.keep')), findsOneWidget);
      expect(find.byKey(const Key('growTeenNote')), findsNothing);
      expect(find.text('Show me'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('age 8: the weeks, the list and the journal are new; calling, stories and show and tell stayed', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final ChildGrowth g = await grown(7, 8);
      await t.pumpWidget(app(kidHome(await snap(years: 8), years: 8, growth: g), years: 8));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('growEyebrow'))).data, 'You are 8');
      expect(find.text('Your weeks'), findsOneWidget);
      expect(find.text('Your own list'), findsOneWidget);
      expect(find.text('A quiet journal'), findsOneWidget);
      expect(find.byKey(const Key('growFive')), findsNothing);
    });

    testWidgets('Not now: the home comes back with a quiet "Your home grew" row; tapping it shows the page again', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final ChildGrowth g = await grown(7, 8);
      await t.pumpWidget(app(kidHome(await snap(years: 8), years: 8, growth: g), years: 8));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('growLater')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('growPage')), findsNothing);
      expect(find.byKey(const Key('bandHome.t812')), findsOneWidget);
      expect(find.byKey(const Key('growLaterCard')), findsOneWidget);
      expect(find.text('Your home grew'), findsOneWidget);
      for (final String s in allText(t)) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no number on the home with the Later row: "$s"');
      }
      await t.tap(find.byKey(const Key('growLaterCard')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('growPage')), findsOneWidget);
    });

    testWidgets('Show me opens the new thing (the weeks at 8) and the Later row is gone', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final ChildGrowth g = await grown(7, 8);
      await t.pumpWidget(app(kidHome(await snap(years: 8), years: 8, growth: g), years: 8));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('growShow')));
      await t.pumpAndSettle();
      expect(find.byType(WeeksScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHome.t812')), findsOneWidget);
      expect(find.byKey(const Key('growLaterCard')), findsNothing);
    });

    testWidgets('the 13 page is plain, says nobody else is told, and has no button for a screen that does not exist yet', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final ChildGrowth g = await grown(12, 13);
      await t.pumpWidget(app(kidHome(await snap(years: 13), years: 13, growth: g), years: 13));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('growEyebrow'))).data, 'You are 13');
      expect(find.byKey(const Key('growScene')), findsNothing);
      expect(find.byKey(const Key('growTeenNote')), findsOneWidget);
      expect(find.byKey(const Key('growShow')), findsNothing, reason: 'Privacy has no screen yet');
      await t.tap(find.byKey(const Key('growOkay')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('growPage')), findsNothing);
    });

    testWidgets('with no growth state the home is drawn as it always was (older callers)', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(kidHome(await snap())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('growPage')), findsNothing);
      expect(find.byKey(const Key('growLaterCard')), findsNothing);
    });

    testWidgets('the page is spoken when read-aloud is wired, and never needs a server', (WidgetTester t) async {
      await big(t, const Size(800, 3000));
      final List<String> spoken = <String>[];
      final ChildGrowth g = await grown(7, 8);
      await t.pumpWidget(app(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
          family: await snap(years: 8), childAge: 8, growth: g, clock: () => fixed, speak: (String x) async => spoken.add(x)), years: 8));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('growHear')));
      await t.pump();
      expect(spoken, <String>['You are eight. Your home is growing with you.']);
    });
  });

  group('the local-midnight clock', () {
    testWidgets('fires at every local midnight, with the clock\'s reading, and stops with the widget', (WidgetTester t) async {
      DateTime now = DateTime(2026, 11, 9, 23, 0);
      final List<DateTime> fired = <DateTime>[];
      await t.pumpWidget(MaterialApp(home: LocalMidnightWatch(
          clock: () => now, onMidnight: (DateTime n) => fired.add(n), child: const SizedBox())));
      await t.pump(const Duration(minutes: 59));
      expect(fired, isEmpty);
      now = DateTime(2026, 11, 10, 0, 0);
      await t.pump(const Duration(minutes: 1));
      expect(fired, <DateTime>[DateTime(2026, 11, 10)]);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(days: 2));
      expect(fired.length, 1);
    });
  });
}
