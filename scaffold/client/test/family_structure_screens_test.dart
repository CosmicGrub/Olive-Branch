// OLIVE BRANCH — Family structure screens (guardian builder, preview and timing, history,
// age bands; child My people, birthday, the youngest band's home) and their wiring into the
// real child home. Local-first: no network anywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_screens.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/guardian_more.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal child = FamilyPrincipal(roleName: 'child', childId: 'c1');
final DateTime fixed = DateTime(2026, 11, 7, 9);

Widget wrap(Widget w) => MaterialApp(home: w);

FamilyService svc() => FamilyService(MemoryFamilyStore(), clock: () => fixed);
FamilyContext ctx(FamilyService s, {FamilyPrincipal p = guardian, int years = 7}) =>
    FamilyContext(service: s, principal: p, actorName: 'Dad', childName: 'Ivy', yearsOld: years);

Map<String, Object?> person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};
Map<String, Object?> home(String id, String name) => <String, Object?>{'id': id, 'name': name, 'childSleeps': true};

Future<void> seed(FamilyService s, {int years = 7}) async {
  Future<void> add(Map<String, Object?> op) => s.addChange(guardian, actorName: 'Dad', yearsOld: years, op: op, timing: Timing.now.toJson());
  await add(<String, Object?>{'op': 'put_home', 'home': home('h1', "Mom's house")});
  await add(<String, Object?>{'op': 'put_home', 'home': home('h2', "Dad's house")});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p1', 'Mom', 'guardian', 'h1', <String>['live_call', 'message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p2', 'Dad', 'guardian', 'h2', <String>['live_call'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p3', 'Dana', 'step_parent', 'h2', <String>['message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p4', 'Sue', 'sitter', 'h1', <String>['message'])});
}

Future<FamilyChildSnapshot> kid(FamilyService s, {int years = 7}) => s.childSnapshot(child, childId: 'c1', yearsOld: years);

void main() {
  group('F1 guardian screens refuse everyone else', () {
    for (final FamilyPrincipal p in <FamilyPrincipal>[
      child, const FamilyPrincipal(roleName: 'sitter', userId: 's'), const FamilyPrincipal(roleName: 'step_parent', userId: 'x'),
      const FamilyPrincipal(),
    ]) {
      testWidgets('${p.roleName} sees only the guardians-only line', (WidgetTester t) async {
        final FamilyService s = svc();
        await seed(s);
        await t.pumpWidget(wrap(FamilyStructureScreen(ctx: ctx(s, p: p))));
        await t.pump();
        expect(find.byKey(const Key('familyGuardiansOnly')), findsOneWidget);
        expect(find.textContaining('Dana'), findsNothing);
        expect(find.byKey(const Key('familyOpenPeople')), findsNothing);
      });
    }
  });

  group('guardian builder', () {
    testWidgets('the hub says plainly that syncing between devices comes later, and lists the four areas', (WidgetTester t) async {
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(FamilyStructureScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('familySyncNote')), findsOneWidget);
      expect(find.textContaining('Syncing between devices comes later'), findsOneWidget);
      for (final String k in <String>['familyOpenPeople', 'familyOpenHomes', 'familyOpenBands', 'familyOpenHistory']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('people list shows labels and roles to the guardian, but a sitter with no label is flagged as not shown to her', (WidgetTester t) async {
      final FamilyService s = svc();
      await seed(s);
      await s.addChange(guardian, actorName: 'Dad', yearsOld: 7, timing: Timing.now.toJson(),
          op: <String, Object?>{'op': 'put_person', 'person': person('p9', '', 'trusted_adult', null, <String>[])});
      await t.pumpWidget(wrap(FamilyPeopleScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.text('Dana'), findsOneWidget);
      expect(find.textContaining("A parent's partner"), findsOneWidget);
      expect(find.text('(not shown to her)'), findsOneWidget);
    });

    testWidgets('adding a person: new people default to HOLD, nothing reaches her, then "I have told her" releases', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(FamilyStructureScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('familyOpenPeople')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('familyAddPerson')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('personLabel')), 'Grandma');
      await t.tap(find.byKey(const Key('contact_live_call')));
      await t.pump();
      await t.tap(find.byKey(const Key('personContinue')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('previewSummary')), findsOneWidget);
      expect(find.textContaining('added Grandma'), findsOneWidget);
      expect(find.byKey(const Key('previewDiffers')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('previewDiffers'))) as Text).data, contains('screens change'));
      expect(find.text('Save and hold'), findsOneWidget, reason: 'a big change defaults to hold');
      expect(find.textContaining('Recommended for big changes'), findsOneWidget);
      await t.tap(find.byKey(const Key('previewSave')));
      await t.pumpAndSettle();
      expect((await kid(s)).view.places.expand((ChildPlace p) => p.people).map((ChildPerson x) => x.name), isNot(contains('Grandma')));
      final FamilyOverview o = await s.overview(guardian, yearsOld: 7);
      expect(o.pending.length, 1);
      await s.release(guardian, actorName: 'Mom', yearsOld: 7, changeId: o.pending.first);
      expect((await kid(s)).view.places.expand((ChildPlace p) => p.people).map((ChildPerson x) => x.name), contains('Grandma'));
    });

    testWidgets('a small change (a new label) defaults to NOW', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      final FamilyOverview o = await s.overview(guardian, yearsOld: 7);
      await t.pumpWidget(wrap(PersonEditorScreen(ctx: ctx(s), intended: o.intended, existing: o.intended.people[2])));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('personLabel')), 'Dani');
      await t.tap(find.byKey(const Key('personContinue')));
      await t.pumpAndSettle();
      expect(find.text('Save and apply'), findsOneWidget);
      await t.tap(find.byKey(const Key('previewSave')));
      await t.pumpAndSettle();
      expect((await kid(s)).view.places.expand((ChildPlace p) => p.people).map((ChildPerson x) => x.name), contains('Dani'));
    });

    testWidgets('a dated change without a date is refused in plain words and writes nothing', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      final int before = (await s.store.load()).records.length;
      final FamilyOverview o = await s.overview(guardian, yearsOld: 7);
      await t.pumpWidget(wrap(ChangePreviewScreen(ctx: ctx(s), intended: o.intended, op: <String, Object?>{'op': 'remove_person', 'personId': 'p3'})));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('timingDate')));
      await t.pump();
      await t.tap(find.byKey(const Key('previewSave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('previewError')), findsOneWidget);
      expect((await s.store.load()).records.length, before);
    });

    testWidgets('a story is a few guardian-typed pages; an over-long page is refused', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 2200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      final FamilyOverview o = await s.overview(guardian, yearsOld: 7);
      await t.pumpWidget(wrap(ChangePreviewScreen(ctx: ctx(s), intended: o.intended, op: <String, Object?>{'op': 'remove_person', 'personId': 'p3'})));
      await t.pumpAndSettle();
      expect(find.textContaining('Nothing is written for you'), findsOneWidget);
      await t.tap(find.byKey(const Key('storyToggle')));
      await t.pump();
      await t.enterText(find.byKey(const Key('storyPages')), 'x' * 300);
      await t.tap(find.byKey(const Key('previewSave')));
      await t.pumpAndSettle();
      expect(find.textContaining('1 to $maxStoryPages pages'), findsOneWidget);
    });

    testWidgets('homes: a court-ordered rhythm is shown locked with no edit button', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(FamilyHomesScreen(ctx: FamilyContext(service: s, principal: guardian, order: const Rhythm(pattern: '2-2-3', exchangeTime: '17:00', source: 'court_order')))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rhythmLocked')), findsOneWidget);
      expect(find.byKey(const Key('rhythmEdit')), findsNothing);
      expect(find.text('2-2-3'), findsOneWidget);
    });

    testWidgets('homes: without an order the rhythm can be edited, and a bad time is caught', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(FamilyHomesScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rhythmLocked')), findsNothing);
      expect(find.text("Mom's house"), findsOneWidget);
      await t.tap(find.byKey(const Key('rhythmEdit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('rhythmTime')), '25:00');
      await t.tap(find.byKey(const Key('rhythmContinue')));
      await t.pump();
      expect(find.textContaining('24-hour'), findsOneWidget);
    });

    testWidgets('the fifth home is not offered', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      for (final String id in <String>['h3', 'h4']) {
        await s.addChange(guardian, actorName: 'Dad', yearsOld: 7, timing: Timing.now.toJson(), op: <String, Object?>{'op': 'put_home', 'home': home(id, 'Home $id')});
      }
      await t.pumpWidget(wrap(FamilyHomesScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('familyAddHome')), findsNothing);
    });
  });

  group('history', () {
    testWidgets('empty history teaches what it will hold', (WidgetTester t) async {
      final FamilyService s = svc();
      await t.pumpWidget(wrap(FamilyHistoryScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('historyEmpty')), findsOneWidget);
      expect(find.byKey(const Key('historyRule')), findsOneWidget);
    });

    testWidgets('an undo is a NEW entry: the original stays, and the filters work', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(FamilyHistoryScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      final int before = (await s.store.load()).records.length;
      expect(find.textContaining('Dad added Dana'), findsOneWidget);
      await t.tap(find.byKey(const Key('undo_c5')));
      await t.pumpAndSettle();
      expect((await s.store.load()).records.length, before + 1);
      expect(find.textContaining('Dad added Dana'), findsOneWidget, reason: 'the first stays');
      expect(find.textContaining('undone by a later entry'), findsOneWidget);
      expect(find.byKey(const Key('undo_c5')), findsNothing, reason: 'it cannot be undone twice');
      await t.tap(find.text('Homes'));
      await t.pumpAndSettle();
      expect(find.textContaining('added Mom'), findsOneWidget);
      expect(find.textContaining('added Dana'), findsNothing);
    });
  });

  group('age bands', () {
    testWidgets('four bands with family names, her band marked, and the permanent-ladder note', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(AgeBandsScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      for (final String b in ageBands) {
        expect(find.byKey(Key('band_$b')), findsOneWidget);
      }
      expect(find.textContaining('Ivy is here'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('bandsNote')), matching: find.textContaining('permanent')), findsOneWidget);
      expect(find.byKey(const Key('noBirthDate')), findsOneWidget);
    });

    testWidgets('a birth date shows the next-birthday preview, and a band move is held until released', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await s.setBirthDate(guardian, '2018-11-20', yearsOld: 7);
      await t.pumpWidget(wrap(AgeBandsScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('birthdayCard')), findsOneWidget);
      expect(find.textContaining('13 sleeps away'), findsOneWidget);
      expect(find.byKey(const Key('birthdayBandMove')), findsOneWidget);
      expect(find.textContaining('You are holding it'), findsOneWidget);
    });

    testWidgets('the hold toggle and the birthday toggle write now; an area override is a change', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 3200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(AgeBandsScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('birthdayVisible')));
      await t.pumpAndSettle();
      expect((await s.overview(guardian, yearsOld: 7)).released.birthdayVisible, isFalse);
      await t.tap(find.byKey(const Key('bandHold')));
      await t.pumpAndSettle();
      expect((await s.overview(guardian, yearsOld: 7)).released.holdBandChange, isFalse);
      await t.tap(find.byKey(const Key('areaDrop_reading')));
      await t.pumpAndSettle();
      await t.tap(find.text('8 to 12').last);
      await t.pumpAndSettle();
      expect((await s.overview(guardian, yearsOld: 7)).released.areaBands['reading'], 't812');
    });

    testWidgets('a held band move shows the release card; releasing moves her home', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      DateTime day = fixed;
      final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => day);
      await s.setBirthDate(guardian, '2019-04-02', yearsOld: 7);
      await s.overview(guardian, yearsOld: 7);
      day = DateTime(2027, 6, 1, 9);
      await t.pumpWidget(wrap(AgeBandsScreen(ctx: ctx(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHeldCard')), findsOneWidget);
      expect((await kid(s)).view.band, 't57');
      await t.tap(find.byKey(const Key('bandRelease')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bandHeldCard')), findsNothing);
      expect((await kid(s)).view.band, 't812');
    });
  });

  group('child screens', () {
    testWidgets('My people shows the names she uses under each home, never a role word or a sitter', (WidgetTester t) async {
      final SemanticsHandle sem = t.ensureSemantics();
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(MyPeopleScreen(snapshot: await kid(s))));
      await t.pumpAndSettle();
      expect(find.text("Mom's house"), findsOneWidget);
      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('Sue'), findsNothing);
      for (final String w in <String>['step', 'sitter', 'guardian', 'Guardian', 'partner']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
      expect(find.bySemanticsLabel('Call Mom'), findsOneWidget);
      expect(find.bySemanticsLabel('Message Dana'), findsOneWidget);
      sem.dispose();
    });

    testWidgets('a released story pages through, and "Not now" just closes it', (WidgetTester t) async {
      final FamilyService s = svc();
      await seed(s);
      final FamilyWrite w = await s.addChange(guardian, actorName: 'Mom', yearsOld: 7, timing: Timing.hold.toJson(),
          op: <String, Object?>{'op': 'put_person', 'person': person('p8', 'Nan', 'relative', null, <String>['message'])},
          story: <String, Object?>{'pages': <String>['Page one.', 'Page two.']});
      expect((await kid(s)).story, isNull);
      await s.release(guardian, actorName: 'Mom', yearsOld: 7, changeId: w.id!);
      await t.pumpWidget(wrap(MyPeopleScreen(snapshot: await kid(s))));
      await t.pumpAndSettle();
      expect(find.text('A story from Mom'), findsOneWidget);
      expect(find.text('Page one.'), findsOneWidget);
      await t.tap(find.byKey(const Key('storyNext')));
      await t.pump();
      expect(find.text('Page two.'), findsOneWidget);
      await t.tap(find.byKey(const Key('storyNotNow')));
      await t.pump();
      expect(find.byKey(const Key('childStory')), findsNothing);
    });

    testWidgets('birthday: sleeps, the date, the age, and nothing to do (no score, no streak)', (WidgetTester t) async {
      await t.pumpWidget(wrap(const BirthdayScreen(birthday: ChildBirthday(sleepsUntil: 3, turnsYears: 6, monthDay: '12-09', lineShown: true))));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('sleeps until your birthday'), findsOneWidget);
      expect(find.text('December 9'), findsOneWidget);
      expect(find.text('You will be 6'), findsOneWidget);
      expect(find.byKey(const Key('birthdayCalm')), findsOneWidget);
      for (final String w in <String>['streak', 'score', 'points', 'wish', 'reward']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
    });

    testWidgets('birthday today and one sleep read naturally', (WidgetTester t) async {
      await t.pumpWidget(wrap(const BirthdayScreen(birthday: ChildBirthday(sleepsUntil: 0, turnsYears: 6, monthDay: '11-07', lineShown: true))));
      expect(find.byKey(const Key('birthdayToday')), findsOneWidget);
      await t.pumpWidget(wrap(const BirthdayScreen(birthday: ChildBirthday(sleepsUntil: 1, turnsYears: 6, monthDay: '11-08', lineShown: true))));
      expect(find.text('sleep until your birthday'), findsOneWidget);
    });
  });

  group('the real child home, driven by the derived model', () {
    testWidgets('3-4: three icon-only tiles, the call is for a person she can call, names are spoken', (WidgetTester t) async {
      final FamilyService s = svc();
      await seed(s, years: 4);
      final FamilyChildSnapshot snap = await kid(s, years: 4);
      final List<String> spoken = <String>[];
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0, family: snap,
          speak: (String x) async => spoken.add(x))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('age34Call')), findsOneWidget);
      expect(find.byKey(const Key('age34Stories')), findsOneWidget);
      expect(find.byKey(const Key('age34Colour')), findsOneWidget);
      expect(find.textContaining('Hi Ivy'), findsNothing);
      expect(find.byType(Text).evaluate().map((Element e) => (e.widget as Text).data).whereType<String>().where((String d) => d.length > 3), isEmpty,
          reason: 'no words to read on the youngest home');
      expect(find.bySemanticsLabel('Call Mom'), findsOneWidget);
      await t.tap(find.byKey(const Key('age34Stories')));
      await t.pump();
      expect(spoken, contains('Stories'));
    });

    testWidgets('5-7: the current home, plus My people when there is someone to show', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(673, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s);
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0, family: await kid(s))));
      await t.pumpAndSettle();
      // Wave 2a: the 5-7 home is drawn from the prototype's table ('Hi, Ivy' with a greeting above it).
      expect(find.text('Hi, Ivy'), findsOneWidget);
      expect(find.text('Play together'), findsOneWidget);
      expect(find.byKey(const Key('childHomeMyPeople')), findsOneWidget);
      await t.tap(find.byKey(const Key('childHomeMyPeople')));
      await t.pumpAndSettle();
      expect(find.text("Dad's house"), findsOneWidget);
    });

    testWidgets('with no family built the home is exactly as before (no My people tile)', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(673, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0, family: await kid(s))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childHomeMyPeople')), findsNothing);
      expect(find.text('Hi, Ivy'), findsOneWidget);
    });

    testWidgets('8-12: a plain greeting (good-part-of-day line, no Hi)', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(673, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s, years: 9);
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
          clock: () => DateTime(2026, 11, 9, 9), family: await kid(s, years: 9))));
      await t.pumpAndSettle();
      expect(find.text('Good morning, Ivy'), findsOneWidget);
      expect(find.text('Hi, Ivy'), findsNothing);
    });

    testWidgets('a guardian holding games at the youngest level removes Play together on her real home', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(673, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await seed(s, years: 9);
      await s.addChange(guardian, actorName: 'Dad', yearsOld: 9, timing: Timing.now.toJson(), op: <String, Object?>{'op': 'set_area_band', 'area': 'games', 'band': 't34'});
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0, family: await kid(s, years: 9))));
      await t.pumpAndSettle();
      expect(find.text('Play together'), findsNothing);
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('her quiet birthday line appears only in her birthday week and opens the birthday screen', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(673, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => DateTime(2026, 12, 4, 9));
      await s.setBirthDate(guardian, '2019-12-09', yearsOld: 6);
      await t.pumpWidget(wrap(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
          family: await s.childSnapshot(child, childId: 'c1', yearsOld: 6))));
      await t.pumpAndSettle();
      expect(find.text('Your birthday is this week.'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsNothing, reason: 'the home shows a caption, never the count');
      await t.tap(find.byKey(const Key('birthdayLine')));
      await t.pumpAndSettle();
      expect(find.text('December 9'), findsOneWidget);
    });
  });

  group('reachable from the guardian More screen', () {
    testWidgets('the Family tile opens the builder, on this device only', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(800, 3200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FamilyService s = svc();
      await t.pumpWidget(MaterialApp(home: GuardianMoreScreen(familyService: s)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('moreFamily')), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('moreFamily')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('familySyncNote')), findsOneWidget);
    });
  });
}
