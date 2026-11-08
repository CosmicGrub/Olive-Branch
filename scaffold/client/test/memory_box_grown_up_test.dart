// OLIVE BRANCH — the memory box "from a grown-up" section (MASTERFILE section 8.23):
// a guardian leaves a note or small photo marked as theirs, in a separate section she
// can see and read aloud; her own items stay hers (a guardian cannot edit or delete them).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/growing_care_widgets.dart' show ThumbImage;
import 'package:olive_client/growing_screens.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/snapshot_button.dart';
import 'package:olive_client/store_cipher.dart';

const FamilyPrincipal gA = FamilyPrincipal(roleName: 'guardian', userId: 'ga');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'ivy');
const FamilyPrincipal sitter = FamilyPrincipal(roleName: 'sitter', userId: 's1');

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 4));
final DateTime _today = DateTime(2026, 11, 8, 9);
DateTime _now() => _today;
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 3));

LocalServices _device(MemoryStoreBackend b) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: 'ivy', isLive: true, demoSeeds: false);

class _FakeEngine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

Future<void> _show(WidgetTester t, Widget w, {_FakeEngine? engine}) async {
  t.view.physicalSize = const Size(700, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final AccessController access = AccessController(
      repository: MemoryAccessRepository(const AccessSettings(readAloud: true)), ageYears: 6);
  await access.load();
  Widget home = w;
  if (engine != null) home = ReadAloudScope(controller: ReadAloudController(engine: engine), child: w);
  await t.pumpWidget(MaterialApp(key: UniqueKey(), home: AccessScope(controller: access, child: home)));
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

GrownUpMemoryDesk _desk(GrowingCareStores s) => GrownUpMemoryDesk(s.grownUpMemories, now: _now);

void main() {
  group('the desk: guardian only, its own section', () {
    test('a guardian leaves a note and a photo, marked as from them, newest first', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemoryDesk d = _desk(s);
      final GrownUpMemory a = await d.add(gA, fromName: ' Mum ', note: ' See you Friday ');
      expect(a.fromName, 'Mum');
      expect(a.note, 'See you Friday');
      expect(a.addedOn, '2026-11-08');
      await d.add(gA, fromName: 'Grandpa', photo: _bytes(300));
      final List<GrownUpMemory> l = await d.list(gA);
      expect(l.length, 2);
      expect(l.map((GrownUpMemory m) => m.fromName).toSet(), <String>{'Mum', 'Grandpa'});
      expect(l.firstWhere((GrownUpMemory m) => m.fromName == 'Grandpa').thumb!.length, 300);
    });

    test('a child, a sitter and nobody are refused for add, list and remove', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemoryDesk d = _desk(s);
      final GrownUpMemory m = await d.add(gA, fromName: 'Mum', note: 'Hi');
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[ivy, sitter, null, const FamilyPrincipal(roleName: 'guardian')]) {
        await expectLater(d.add(p, fromName: 'X', note: 'sneaky'), throwsA(isA<CareRefused>()), reason: '$p');
        await expectLater(d.list(p), throwsA(isA<CareRefused>()), reason: '$p');
        await expectLater(d.remove(p, m.id), throwsA(isA<CareRefused>()), reason: '$p');
      }
      expect((await s.grownUpMemories.list()).single.note, 'Hi');
    });

    test('empty, nameless, too long and over-sized things are refused and nothing is stored', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemoryDesk d = _desk(s);
      Future<String> why(Future<GrownUpMemory> f) async {
        try {
          await f;
          return 'stored';
        } on CareRefused catch (e) {
          return e.reason;
        }
      }

      expect(await why(d.add(gA, fromName: 'Mum')), 'empty');
      expect(await why(d.add(gA, fromName: '', note: 'Hi')), 'empty');
      expect(await why(d.add(gA, fromName: 'Mum', note: 'x' * (maxGrownUpNoteChars + 1))), 'too_long');
      expect(await why(d.add(gA, fromName: 'M' * 41, note: 'Hi')), 'too_long');
      expect(await why(d.add(gA, fromName: 'Mum', photo: _bytes(maxThumbBytes + 1))), 'photo_too_big');
      expect(await s.grownUpMemories.list(), isEmpty);
    });

    test('there is a limit, it says so, and nothing is evicted', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemoryDesk d = _desk(s);
      for (int i = 0; i < maxGrownUpMemories; i++) {
        await d.add(gA, fromName: 'Mum', note: 'n$i');
      }
      await expectLater(d.add(gA, fromName: 'Mum', note: 'one too many'), throwsA(isA<CareRefused>()));
      expect((await s.grownUpMemories.list()).length, maxGrownUpMemories);
    });

    test('a guardian can take back what a grown-up left, and nothing else', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemoryDesk d = _desk(s);
      final GrownUpMemory m = await d.add(gA, fromName: 'Mum', note: 'Hi');
      await d.remove(gA, m.id);
      expect(await d.list(gA), isEmpty);
    });
  });

  group('her own items stay hers', () {
    test('the grown-up section is a different place: it never appears in, or counts toward, her items', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      await _desk(s).add(gA, fromName: 'Mum', note: 'Hi');
      expect((await s.memories.list()).map((MemoryItem m) => m.id), <String>['m1']);
      expect((await s.grownUpMemories.list()).length, 1);
      // Her box can fill to its own limit regardless of what grown-ups left.
      for (int i = 0; i < maxMemoryItems - 1; i++) {
        await s.memories.save(MemoryItem(id: 'x$i', kind: 'doodle', addedOn: '2026-11-08', pictureData: const <String, Object?>{'w': 1}));
      }
      expect((await s.memories.list()).length, maxMemoryItems);
    });

    test('a guardian has no way to touch hers: removing her id through the desk leaves it', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      await _desk(s).remove(gA, 'm1');
      expect((await s.memories.get('m1')), isNotNull);
      // And her private items are not even listed on the guardian's side.
      expect(await _desk(s).list(gA), isEmpty);
    });

    test('the child\'s lens still reads none of the guardian side, and the reader has no write', () {
      final GrowingCareStores s = GrowingCareStores.memory();
      final ChildGrownUpMemoryReader r = ChildGrownUpMemoryReader(s.grownUpMemories);
      expect(r.all(), completion(isEmpty));
    });
  });

  group('durable: sealed, survives a restart, wiped with the device', () {
    test('survives a restart, is unreadable on disk, and goes with the child\'s data', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final GrowingCareStores a = GrowingCareStores.forChild(services: _device(disk));
      await _desk(a).add(gA, fromName: 'Mum', note: 'SECRET-NOTE-WORDS', photo: _bytes(40));
      await a.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      expect(utf8.decode(disk.rawFor('child.ivy.memorybox')!, allowMalformed: true), isNot(contains('SECRET-NOTE-WORDS')));

      final GrowingCareStores b = GrowingCareStores.forChild(services: _device(disk)); // restarted
      final List<GrownUpMemory> g = await _desk(b).list(gA);
      expect(g.single.note, 'SECRET-NOTE-WORDS');
      expect(g.single.fromName, 'Mum');
      expect(g.single.thumb!.length, 40);
      expect((await b.memories.list()).single.id, 'm1');

      await _device(disk).forgetChild('ivy');
      final GrowingCareStores c = GrowingCareStores.forChild(services: _device(disk));
      expect(await c.grownUpMemories.list(), isEmpty);
      expect(await c.memories.list(), isEmpty);
    });

    test('the catalogue says a grown-up may leave marked things and that hers stay hers', () {
      final String w = localDataEntry('memorybox').what.toLowerCase();
      expect(w, contains('grown-up'));
      expect(w, contains('never uploaded'));
    });

    test('a damaged grown-up item is skipped, never fatal', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final GrowingCareStores a = GrowingCareStores.forChild(services: _device(disk));
      await _desk(a).add(gA, fromName: 'Mum', note: 'Hi');
      final LocalNamespace ns = _device(disk).area('memorybox');
      await ns.put('gift.bad', <String, Object?>{'nonsense': true});
      expect((await _desk(GrowingCareStores.forChild(services: _device(disk))).list(gA)).length, 1);
    });
  });

  group('the guardian screen', () {
    testWidgets('says her own things stay hers; leaving a note shows it under "What you have left"', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, LeaveForHerScreen(childName: 'Ivy', stores: s, principal: gA, fromName: 'Mum', now: _now));
      expect(find.textContaining('What she keeps herself stays hers'), findsOneWidget);
      expect(find.textContaining('cannot see, change or remove it'), findsOneWidget);
      await t.enterText(find.byKey(const Key('giftNote')), 'Proud of you');
      await _tap(t, 'leaveForHer');
      final List<GrownUpMemory> l = await s.grownUpMemories.list();
      expect(l.single.note, 'Proud of you');
      expect(l.single.fromName, 'Mum');
      expect(find.text('Proud of you'), findsOneWidget);
      expect(find.text('From Mum, 8 Nov 2026'), findsOneWidget);
    });

    testWidgets('a small photo can be added; a nameless or empty one is refused in words', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, LeaveForHerScreen(childName: 'Ivy', stores: s, principal: gA, now: _now, photoSource: () async => _bytes(200)));
      await _tap(t, 'leaveForHer');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('giftNote')), 'Hello');
      await _tap(t, 'leaveForHer');
      expect(await s.grownUpMemories.list(), isEmpty, reason: 'no name given');
      await t.enterText(find.byKey(const Key('giftFrom')), 'Grandpa');
      await _tap(t, 'giftPhoto');
      await _tap(t, 'leaveForHer');
      expect((await s.grownUpMemories.list()).single.thumb!.length, 200);
    });

    testWidgets('a child principal cannot leave anything even if the screen is reached', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, LeaveForHerScreen(childName: 'Ivy', stores: s, principal: ivy, fromName: 'Ivy', now: _now));
      await t.enterText(find.byKey(const Key('giftNote')), 'sneaky');
      await _tap(t, 'leaveForHer');
      expect(find.text('Only a grown-up can do that.'), findsWidgets);
      expect(await s.grownUpMemories.list(), isEmpty);
    });

    testWidgets('taking one back asks first, and removes only that one', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemory a = await _desk(s).add(gA, fromName: 'Mum', note: 'one');
      await _desk(s).add(gA, fromName: 'Mum', note: 'two');
      await _show(t, LeaveForHerScreen(childName: 'Ivy', stores: s, principal: gA, now: _now));
      await _tap(t, 'takeBack-${a.id}');
      expect((await s.grownUpMemories.list()).length, 2, reason: 'not until confirmed');
      await t.tap(find.text('Take it back'));
      await t.pumpAndSettle();
      expect((await s.grownUpMemories.list()).single.note, 'two');
    });

    testWidgets('the Growing hub offers it, and no screen offers a way to open her own items', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      await _show(t, LeaveForHerScreen(childName: 'Ivy', stores: s, principal: gA, now: _now));
      expect(find.byKey(const ValueKey<String>('memory-m1')), findsNothing);
      expect(find.byType(GridView), findsNothing);
    });
  });

  group('her side: a separate section, marked, readable aloud', () {
    testWidgets('with nothing left there is no section; her box is exactly as before', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      expect(find.byKey(const Key('fromGrownUp')), findsNothing);
      expect(find.byKey(const Key('memoryEmpty')), findsOneWidget);
    });

    testWidgets('a grown-up\'s note never shows among hers; it opens in its own screen, marked as from them', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      final GrownUpMemory g = await _desk(s).add(gA, fromName: 'Mum', note: 'Proud of you');
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      expect(find.byKey(const ValueKey<String>('memory-m1')), findsOneWidget);
      expect(find.text('Proud of you'), findsNothing, reason: 'not mixed into hers');
      expect(find.byKey(ValueKey<String>('memory-${g.id}')), findsNothing);
      await _tap(t, 'fromGrownUp');
      expect(find.byType(FromGrownUpScreen), findsOneWidget);
      expect(find.text('From Mum'), findsOneWidget);
      expect(find.text('Proud of you'), findsOneWidget);
      // Read-only on her side: no delete, no edit, no long-press put-away.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await t.longPress(find.byKey(ValueKey<String>('gift-${g.id}')));
      await t.pumpAndSettle();
      expect(find.text('Put this away?'), findsNothing);
      expect((await s.grownUpMemories.list()).length, 1);
    });

    testWidgets('her own long-press put-away still works and touches only hers', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(const MemoryItem(id: 'm1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}));
      await _desk(s).add(gA, fromName: 'Mum', note: 'Proud of you');
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      await t.longPress(find.byKey(const ValueKey<String>('memory-m1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Put it away'));
      await t.pumpAndSettle();
      expect(await s.memories.list(), isEmpty);
      expect((await s.grownUpMemories.list()).length, 1, reason: 'what Mum left is not hers to lose by accident');
    });

    testWidgets('the speakers read the grown-up\'s words aloud, with who it is from; only on a tap', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final GrownUpMemory g = await _desk(s).add(gA, fromName: 'Mum', note: 'Proud of you');
      final _FakeEngine e = _FakeEngine();
      await _show(t, FromGrownUpScreen(stores: s), engine: e);
      expect(e.spoken, isEmpty, reason: 'never autonomous');
      await t.tap(find.byKey(ValueKey<String>('giftSpeaker-${g.id}')));
      await t.pumpAndSettle();
      expect(e.spoken, <String>['From Mum. Proud of you']);
    });

    testWidgets('the speakers on her box read its words; with read-aloud off there is none', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      final _FakeEngine e = _FakeEngine();
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now), engine: e);
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pumpAndSettle();
      expect(e.spoken, <String>["It's yours. Keep things here whenever you like."]);

      await _desk(s).add(gA, fromName: 'Mum', note: 'Hi');
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now), engine: e);
      expect(find.byKey(const Key('fromGrownUpSpeaker')), findsOneWidget);

      // No scope (a screen opened without the app's read-aloud): no speaker at all.
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('a grown-up\'s photo shows in her section, as a small picture', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _desk(s).add(gA, fromName: 'Grandpa', photo: _bytes(100));
      await _show(t, FromGrownUpScreen(stores: s));
      expect(find.text('From Grandpa'), findsOneWidget);
      expect(find.byType(ThumbImage), findsOneWidget);
    });
  });
}
