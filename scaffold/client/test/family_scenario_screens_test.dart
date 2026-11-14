// OLIVE BRANCH — Wave 5: the prototype's `family` scenario ("Family change released") replayed against the REAL
// screens, step by step, through taps (not service calls). UNVERIFIED until CI runs it. MASTERFILE §8.5.10, P2, F3.
//
//   family.01  Jess opens Family structure: Ivy's people and homes.
//   family.02  She adds Grandma Rose and HOLDS the change until she has told Ivy. Nothing reaches the tablet.
//   family.03  The history shows the change as held; nothing has changed on Ivy's side.
//   family.04  Ivy's tablet is unchanged: no badge, no surprise.
//   family.05  Jess has had the talk with Ivy. She releases the change.
//   family.06  On the tablet, My people now includes Grandma Rose, as a picture, in her own words.
//
// Plus the wording rule from the owner's decisions of 2026-11-08: family-change wording on HER screens is
// guardian-authored only. Nothing the app itself writes about a change (held, released, undone, court order, told)
// is ever drawn on a screen she can reach.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_screens.dart';
import 'package:olive_client/family_structure_store.dart';

const FamilyPrincipal jess = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'child-1');
final DateTime day = DateTime(2026, 11, 9, 9);

Map<String, Object?> person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};

Future<FamilyService> seeded() async {
  final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => day);
  Future<void> add(Map<String, Object?> op) => s.addChange(jess, actorName: 'Jess', yearsOld: 9, op: op, timing: Timing.now.toJson());
  await add(<String, Object?>{'op': 'put_home', 'home': <String, Object?>{'id': 'h1', 'name': "Mom's house", 'childSleeps': true}});
  await add(<String, Object?>{'op': 'put_home', 'home': <String, Object?>{'id': 'h2', 'name': "Dad's house", 'childSleeps': true}});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p1', 'Mama', 'guardian', 'h1', <String>['message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p2', 'Dada', 'guardian', 'h2', <String>['message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p3', 'Marcus', 'step_parent', 'h2', <String>['message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p4', 'Auntie Lou', 'relative', 'h1', <String>['message'])});
  return s;
}

Future<List<String>> herNames(FamilyService s) async {
  final FamilyChildSnapshot snap = await s.childSnapshot(ivy, childId: 'child-1', yearsOld: 9);
  return <String>[for (final ChildPlace p in snap.view.places) for (final ChildPerson x in p.people) x.name];
}

/// The words the app itself writes about a change. None may reach her.
final RegExp appChangeWords = RegExp(
    r'\b(held|release[ds]?|undo|undone|history|court|order|told her|I have told|scheduled|pending|guardian|draft)\b',
    caseSensitive: false);

/// A fresh app per screen: a MaterialApp keeps the routes pushed onto it, so swapping `home` would not swap the screen.
Future<void> show(WidgetTester t, Widget screen) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MaterialApp(home: screen));
}

void main() {
  testWidgets('the family scenario, end to end on the real screens', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FamilyService s = await seeded();
    final FamilyContext ctx = FamilyContext(service: s, principal: jess, actorName: 'Jess', childName: 'Ivy', yearsOld: 9);
    expect((await s.overview(jess, yearsOld: 9)).released.people.length, 4);

    // family.01 — Jess opens Family structure.
    await show(t, FamilyStructureScreen(ctx: ctx));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('familyOpenPeople')), findsOneWidget);
    expect(find.byKey(const Key('familyOpenHistory')), findsOneWidget);

    // family.02 — add Grandma Rose and choose HOLD.
    await t.tap(find.byKey(const Key('familyOpenPeople')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('familyAddPerson')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('personLabel')), 'Grandma Rose');
    await t.tap(find.byKey(const Key('contact_message')));
    await t.pump();
    await t.tap(find.byKey(const Key('personContinue')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('timingHold')));
    await t.pump();
    await t.tap(find.byKey(const Key('previewSave')));
    await t.pumpAndSettle();
    expect((await s.overview(jess, yearsOld: 9)).pending.length, 1);
    expect(await herNames(s), isNot(contains('Grandma Rose')), reason: 'a held change reaches nobody');

    // family.03 — the history shows the change as held.
    await show(t, FamilyHistoryScreen(ctx: ctx));
    await t.pumpAndSettle();
    expect(find.textContaining('Grandma Rose'), findsOneWidget);
    expect(find.textContaining('Held until told'), findsOneWidget);
    final Finder release = find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('histRelease_'));
    expect(release, findsOneWidget);

    // family.04 — Ivy's tablet is unchanged: My people has the same four, and nothing to notice.
    final FamilyChildSnapshot before = await s.childSnapshot(ivy, childId: 'child-1', yearsOld: 9);
    await show(t, MyPeopleScreen(snapshot: before));
    await t.pumpAndSettle();
    expect(find.text('Grandma Rose'), findsNothing);
    expect(find.text('Auntie Lou'), findsOneWidget);
    expect(find.textContaining(appChangeWords), findsNothing);

    // family.05 — Jess has had the talk. She releases it from the history.
    await show(t, FamilyHistoryScreen(ctx: ctx));
    await t.pumpAndSettle();
    await t.tap(release);
    await t.pumpAndSettle();
    expect((await s.overview(jess, yearsOld: 9)).released.people.length, 5);
    expect(find.textContaining('Held until told'), findsNothing);
    expect(find.textContaining('told Ivy'), findsOneWidget, reason: 'the guardian’s own record says who told her');

    // family.06 — on the tablet, My people includes Grandma Rose, a picture in her own words.
    final FamilyChildSnapshot after = await s.childSnapshot(ivy, childId: 'child-1', yearsOld: 9);
    await show(t, MyPeopleScreen(snapshot: after));
    await t.pumpAndSettle();
    expect(find.text('Grandma Rose'), findsOneWidget);
    expect(find.textContaining(appChangeWords), findsNothing);
    expect(find.textContaining(RegExp(r'\d')), findsNothing, reason: 'P2: no counts on her screen');
  });

  testWidgets('her screen never carries the app’s own change wording, in any state of the history', (WidgetTester t) async {
    final FamilyService s = await seeded();
    Future<FamilyWrite> add(Map<String, Object?> op, Timing timing) =>
        s.addChange(jess, actorName: 'Jess', yearsOld: 9, op: op, timing: timing.toJson());
    // A held change, a change on a date, and a released-then-undone one.
    await add(<String, Object?>{'op': 'put_person', 'person': person('p5', 'Held Hannah', 'relative', null, <String>['message'])}, Timing.hold);
    await add(<String, Object?>{'op': 'put_person', 'person': person('p6', 'Dated Dan', 'relative', null, <String>['message'])},
        const Timing('date', '2026-12-01'));
    final FamilyWrite w = await add(
        <String, Object?>{'op': 'put_person', 'person': person('p7', 'Undone Una', 'relative', null, <String>['message'])}, Timing.now);
    await s.undo(jess, actorName: 'Jess', yearsOld: 9, changeId: w.id!, timing: Timing.now.toJson());
    final FamilyChildSnapshot snap = await s.childSnapshot(ivy, childId: 'child-1', yearsOld: 9);
    await show(t, MyPeopleScreen(snapshot: snap));
    await t.pumpAndSettle();
    final List<String> names = await herNames(s);
    expect(names, isNot(contains('Held Hannah')));
    expect(names, isNot(contains('Dated Dan')));
    expect(names, isNot(contains('Undone Una')));
    expect(find.textContaining(appChangeWords), findsNothing);
    expect(find.byKey(const Key('childStory')), findsNothing);
  });
}
