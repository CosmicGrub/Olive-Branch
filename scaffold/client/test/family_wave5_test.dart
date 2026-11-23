// No longer UNVERIFIED — verified by CI (client/test/family_wave5_test.dart).
// OLIVE BRANCH — Wave 5 (family structure and history): the history record as the prototype shows it
// (status chips, who made the change, Release / Cancel wording), the hold -> history -> release -> My people
// chain on one device, the child-side prohibitions (P1-P11: no counts, no guardian wording, nothing held
// reaches her), and the form factors (344, 390, 600, 800 dp, 2.0x text).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_screens.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/local_services.dart';

const FamilyPrincipal _guardian = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal _child = FamilyPrincipal(roleName: 'child', childId: 'child-1');
final DateTime _now = DateTime(2026, 11, 8, 9);

FamilyService _svc() => FamilyService(MemoryFamilyStore(), clock: () => _now);
FamilyContext _ctx(FamilyService s) =>
    FamilyContext(service: s, principal: _guardian, actorName: 'Jess', childName: 'Ivy', yearsOld: 9);

Map<String, Object?> _person(String id, String label) => <String, Object?>{
      'op': 'put_person',
      'person': <String, Object?>{'id': id, 'label': label, 'role': 'relative', 'homeId': null, 'contact': <String>['message'], 'away': null},
    };

Future<String> _add(FamilyService s, String id, String label, Map<String, Object?> timing) async =>
    (await s.addChange(_guardian, actorName: 'Jess', yearsOld: 9, op: _person(id, label), timing: timing)).id!;

Future<void> _mount(WidgetTester t, Widget w, {Size size = const Size(800, 3000), double text = 1.0}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
      home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)), child: w)));
  await t.pumpAndSettle();
}

void main() {
  group('history record (g-history)', () {
    testWidgets('a held change shows Held until told, Release and Cancel; nothing has reached her', (WidgetTester t) async {
      final FamilyService s = _svc();
      final String id = await _add(s, 'p_rose', 'Grandma Rose', Timing.hold.toJson());
      await _mount(t, FamilyHistoryScreen(ctx: _ctx(s)));
      expect(find.descendant(of: find.byKey(Key('histChip_$id')), matching: find.text('Held until told')), findsOneWidget);
      expect(find.text('I have told her. Release'), findsOneWidget);
      expect(find.text('Cancel it'), findsOneWidget);
      expect(find.byKey(const Key('historyToldNote')), findsOneWidget);
      final FamilyChildSnapshot snap = await s.childSnapshot(_child, childId: 'child-1', yearsOld: 9);
      expect(<String>[for (final ChildPlace p in snap.view.places) for (final ChildPerson x in p.people) x.name], isNot(contains('Grandma Rose')));
    });

    testWidgets('releasing records a NEW entry and the chip turns to Released', (WidgetTester t) async {
      final FamilyService s = _svc();
      final String id = await _add(s, 'p_rose', 'Grandma Rose', Timing.hold.toJson());
      await _mount(t, FamilyHistoryScreen(ctx: _ctx(s)));
      final int before = (await s.store.load()).records.length;
      await t.tap(find.byKey(Key('histRelease_$id')));
      await t.pumpAndSettle();
      expect((await s.store.load()).records.length, before + 1, reason: 'a release is an extra row, never an edit');
      expect(find.descendant(of: find.byKey(Key('histChip_$id')), matching: find.text('Released')), findsOneWidget);
      expect(find.text('Held until told'), findsNothing);
    });

    testWidgets('an applied change says Applied, an undone one says Undone by a newer entry', (WidgetTester t) async {
      final FamilyService s = _svc();
      final String id = await _add(s, 'p_rose', 'Grandma Rose', Timing.now.toJson());
      await _mount(t, FamilyHistoryScreen(ctx: _ctx(s)));
      expect(find.descendant(of: find.byKey(Key('histChip_$id')), matching: find.text('Applied')), findsOneWidget);
      await t.tap(find.byKey(Key('undo_$id')));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(Key('histChip_$id')), matching: find.text('Undone by a newer entry')), findsOneWidget);
    });

    testWidgets('an empty history offers a way to start', (WidgetTester t) async {
      await _mount(t, FamilyHistoryScreen(ctx: _ctx(_svc())));
      expect(find.byKey(const Key('historyEmpty')), findsOneWidget);
      expect(find.text('Start with her people'), findsOneWidget);
    });
  });

  group('child side (P1-P11)', () {
    testWidgets('My people never shows a held change; once released it shows only her words: no counts, no guardian wording', (WidgetTester t) async {
      final FamilyService s = _svc();
      final String id = await _add(s, 'p_rose', 'Grandma Rose', Timing.hold.toJson());
      FamilyChildSnapshot snap = await s.childSnapshot(_child, childId: 'child-1', yearsOld: 9);
      await _mount(t, MyPeopleScreen(snapshot: snap, childName: 'Ivy'));
      expect(find.textContaining('Rose'), findsNothing);
      await s.release(_guardian, actorName: 'Jess', yearsOld: 9, changeId: id);
      snap = await s.childSnapshot(_child, childId: 'child-1', yearsOld: 9);
      await _mount(t, MyPeopleScreen(snapshot: snap, childName: 'Ivy'));
      expect(find.text('Grandma Rose'), findsOneWidget);
      final String all = <String>[for (final Text x in t.widgetList<Text>(find.byType(Text))) x.data ?? ''].join(' | ').toLowerCase();
      expect(RegExp(r'\d').hasMatch(all), isFalse, reason: 'no counts or dates for a child: $all');
      for (final String w in <String>['held', 'release', 'history', 'told', 'court', 'order', 'undo', 'error', 'wrong', 'failed']) {
        expect(all.contains(w), isFalse, reason: '"$w" is guardian wording, found in: $all');
      }
    });

    testWidgets('a child principal can never open the guardian screens', (WidgetTester t) async {
      final FamilyService s = _svc();
      await _add(s, 'p_rose', 'Grandma Rose', Timing.now.toJson());
      final FamilyContext c = FamilyContext(service: s, principal: _child, childName: 'Ivy', yearsOld: 9);
      await _mount(t, FamilyHistoryScreen(ctx: c));
      expect(find.textContaining('Rose'), findsNothing);
      expect(find.byKey(const Key('historyRule')), findsNothing);
    });
  });

  group('form factors', () {
    for (final Size size in const <Size>[Size(344, 700), Size(390, 800), Size(600, 900), Size(800, 1000)]) {
      testWidgets('history and the hub lay out at ${size.width.toInt()} dp with 2.0x text, no overflow', (WidgetTester t) async {
        final FamilyService s = _svc();
        await _add(s, 'p_rose', 'Grandma Rose', Timing.hold.toJson());
        await _add(s, 'p_sam', 'Uncle Sam', Timing.now.toJson());
        await _mount(t, FamilyHistoryScreen(ctx: _ctx(s)), size: size, text: 2.0);
        expect(t.takeException(), isNull);
        await _mount(t, FamilyStructureScreen(ctx: _ctx(s)), size: size, text: 2.0);
        expect(t.takeException(), isNull);
      });
    }
  });

  test('the family area is in the wipe screen catalogue (sealed, never uploaded)', () {
    final LocalDataEntry e = localDataCatalogue.firstWhere((LocalDataEntry x) => x.area == 'family');
    expect(e.encrypted, isTrue);
    expect(e.what, contains('history'));
  });
}
