// OLIVE BRANCH — offline follow-ups to Rhythm and Voice (MASTERFILE section 8.23):
//  1. Voice starts OFF until a guardian turns it on (persisted per child);
//  2. the guardian's local "two homes" fallback for the packing buddy (off by default);
//  3. taking a worry back tells her honestly if a grown-up already saw it, gently,
//     while a guardian still sees only what she chose to show.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/picture_icons.dart' show PictureGlyph;
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_guardian_screens.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/voice_logic.dart';
import 'package:olive_client/voice_screens.dart';

import 'rv_support.dart';

const FamilyPrincipal leo = FamilyPrincipal(roleName: 'child', childId: 'leo');

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 5));
final DateTime _now = DateTime(2026, 11, 8, 19);

LocalServices _device(MemoryStoreBackend b, {String child = 'ivy'}) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: child, isLive: true, demoSeeds: false);

RhythmVoiceService _svc(MemoryStoreBackend b, {String child = 'ivy'}) =>
    RhythmVoiceService.local(_device(b, child: child), clock: () => _now);

Future<void> show(WidgetTester t, Widget w) async {
  await t.pumpWidget(app(const SizedBox()));
  await t.pumpWidget(app(w));
  await t.pumpAndSettle();
}

void main() {
  group('Voice starts OFF', () {
    test('a brand-new device: Voice is off, Rhythm is on, the two-homes setting is off', () async {
      final RhythmVoiceService s = _svc(MemoryStoreBackend());
      expect((await s.loadVoice(guardian)).suiteOn, isFalse);
      expect((await s.loadRhythm(guardian)).suiteOn, isTrue);
      expect((await s.loadRhythm(guardian)).twoHomes, isFalse);
    });

    test('a guardian turns it on and it survives a restart, per child', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      expect((await _svc(disk).setVoiceSuite(guardian, true)).ok, isTrue);
      expect((await _svc(disk).loadVoice(ivy)).suiteOn, isTrue, reason: 'after a restart');
      expect((await _svc(disk, child: 'leo').loadVoice(leo)).suiteOn, isFalse,
          reason: "another child's Voice is still off");
      expect((await _svc(disk).setVoiceSuite(guardian, false)).ok, isTrue);
      expect((await _svc(disk).loadVoice(ivy)).suiteOn, isFalse);
    });

    test('turning it on keeps what a guardian had already written, and writing helpers does not turn it on', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final RhythmVoiceService s = _svc(disk);
      await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]);
      expect((await s.loadVoice(guardian)).suiteOn, isFalse, reason: 'authoring is not switching on');
      await s.setVoiceSuite(guardian, true);
      expect((await _svc(disk).loadVoice(guardian)).helpers.single.name, 'Nana');
    });

    test('only an explicit true counts: a damaged or odd stored value is off', () {
      for (final Object? bad in <Object?>[null, 'true', 1, 'yes', <Object?>[], <String, Object?>{}]) {
        expect(VoiceDoc.fromJson(<String, Object?>{'suiteOn': bad}).suiteOn, isFalse, reason: '$bad');
      }
      expect(VoiceDoc.fromJson(jsonDecode('{"suiteOn":true}')).suiteOn, isTrue);
      expect(VoiceDoc.fromJson(const <String, Object?>{}).suiteOn, isFalse);
    });

    test('a child cannot turn it on', () async {
      final RhythmVoiceService s = _svc(MemoryStoreBackend());
      final RvResult r = await s.setVoiceSuite(ivy, true);
      expect(r.ok, isFalse);
      expect(r.reason, 'guardian_only');
      expect((await s.loadVoice(guardian)).suiteOn, isFalse);
    });

    testWidgets('the guardian switch shows OFF at first, turns on, and is still on when the screen is reopened', (WidgetTester t) async {
      await phone(t, w: 700, h: 2400);
      final RhythmVoiceService s = freshService();
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian, yearsOld: 6));
      expect(tester(t, 'voiceSuite').value, isFalse);
      await t.tap(find.byKey(const Key('voiceSuite')));
      await t.pumpAndSettle();
      expect((await s.loadVoice(guardian)).suiteOn, isTrue);
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian, yearsOld: 6));
      expect(tester(t, 'voiceSuite').value, isTrue);
    });
  });

  group('the two-homes fallback for the packing buddy', () {
    test('off by default, set only by a guardian, and it survives a restart', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      expect((await _svc(disk).setTwoHomes(ivy, true)).reason, 'guardian_only');
      expect((await _svc(disk).loadRhythm(guardian)).twoHomes, isFalse);
      expect((await _svc(disk).setTwoHomes(guardian, true)).ok, isTrue);
      expect((await _svc(disk).loadRhythm(ivy)).twoHomes, isTrue);
      expect((await _svc(disk).setTwoHomes(guardian, false)).ok, isTrue);
      expect((await _svc(disk).loadRhythm(ivy)).twoHomes, isFalse);
    });

    test('the Rhythm document keeps its other parts when the setting changes, and only true counts', () async {
      final RhythmVoiceService s = freshService();
      await s.saveRoutine(guardian, bedtime());
      await s.setTwoHomes(guardian, true);
      final RhythmDoc d = await s.loadRhythm(guardian);
      expect(d.routine!.steps.length, 3);
      for (final Object? bad in <Object?>[null, 'true', 1]) {
        expect(RhythmDoc.fromJson(<String, Object?>{'twoHomes': bad}).twoHomes, isFalse, reason: '$bad');
      }
    });

    testWidgets('the Rhythm hub carries a clearly labelled local switch, off at first', (WidgetTester t) async {
      await phone(t, w: 700, h: 2400);
      final RhythmVoiceService s = freshService();
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian, yearsOld: 6));
      expect(tester(t, 'rhythmTwoHomes').value, isFalse);
      expect(find.textContaining('kept on this device only'), findsWidgets);
      expect(find.textContaining('cannot tell how many homes'), findsOneWidget);
      await t.tap(find.byKey(const Key('rhythmTwoHomes')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).twoHomes, isTrue);
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian, yearsOld: 6));
      expect(tester(t, 'rhythmTwoHomes').value, isTrue);
    });

    testWidgets('a child principal cannot flip it', (WidgetTester t) async {
      await phone(t, w: 700, h: 2400);
      final RhythmVoiceService s = freshService();
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.tap(find.byKey(const Key('rhythmTwoHomes')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).twoHomes, isFalse);
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
    });
  });

  group('taking a worry back: the truth, gently', () {
    test('not seen by anyone: she is told nothing happened', () async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark', showGrownUp: true);
      final String id = (await s.myWorries(ivy)).single.id;
      final r = await s.takeBackWorry(ivy, id);
      expect(r.result.ok, isTrue);
      expect(r.grownUpSawIt, isFalse);
      expect((await s.myWorries(ivy)).single.shown, isFalse);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty);
    });

    test('a grown-up\'s window opened on it: taking it back says so, and it is hidden again', () async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await s.putWorryPicture(ivy, 'worry-dark'); // private, never shown
      final List<Worry> seenByGuardian = await s.worriesShownToGrownUp(guardian);
      expect(seenByGuardian.single.picture, 'worry-storm');
      expect(seenByGuardian.single.seen, isFalse, reason: 'the grown-up\'s copy carries no "seen" memory');
      final String id = seenByGuardian.single.id;
      final r = await s.takeBackWorry(ivy, id);
      expect(r.grownUpSawIt, isTrue);
      expect((await s.myWorries(ivy)).firstWhere((Worry w) => w.id == id).shown, isFalse);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty, reason: 'it is hidden from now on');
    });

    test('a private worry the grown-up window never listed is not marked seen', () async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.worriesShownToGrownUp(guardian);
      expect((await s.myWorries(ivy)).single.seen, isFalse);
    });

    test('the guardian still sees only what she chose to show: no note, tag, count or marker is added', () async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      final List<Worry> a = await s.worriesShownToGrownUp(guardian);
      final List<Worry> b = await s.worriesShownToGrownUp(guardian);
      expect(jsonEncode(a.single.toJson()), jsonEncode(b.single.toJson()));
      expect(a.single.toJson().keys.toSet(), <String>{'id', 'kind', 'madeOn', 'shown', 'picture'});
    });

    test('child only; a guardian cannot take a worry back for her, and an unknown id is refused', () async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      final String id = (await s.myWorries(ivy)).single.id;
      expect((await s.takeBackWorry(guardian, id)).result.reason, 'child_only');
      expect((await s.takeBackWorry(null, id)).result.reason, 'child_only');
      expect((await s.takeBackWorry(ivy, 'nope')).result.reason, 'unknown_worry');
      expect((await s.myWorries(ivy)).single.shown, isTrue, reason: 'nothing changed');
    });

    test('the memory is sealed and survives a restart; floating a worry away deletes it with it', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      RhythmVoiceService s = _svc(disk);
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await s.worriesShownToGrownUp(guardian);
      s = _svc(disk); // restart
      final String id = (await s.myWorries(ivy)).single.id;
      expect((await s.myWorries(ivy)).single.seen, isTrue);
      expect(utf8.decode(disk.rawFor('child.ivy.worries')!, allowMalformed: true), isNot(contains('seen')));
      await s.floatAwayWorry(ivy, id);
      expect(await s.myWorries(ivy), isEmpty);
    });

    test('an old stored worry with no memory loads as not seen', () {
      final Worry? w = Worry.tryFromJson(<String, Object?>{
        'id': 'w1', 'kind': 'picture', 'madeOn': '2026-11-08', 'shown': true, 'picture': 'worry-dark'});
      expect(w!.seen, isFalse);
    });

    Future<RhythmVoiceService> boxWith({required bool seen}) async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark', showGrownUp: true);
      if (seen) await s.worriesShownToGrownUp(guardian);
      return s;
    }

    Future<void> openFirst(WidgetTester t, RhythmVoiceService s) async {
      await phone(t);
      await t.pumpWidget(app(WorryShelfScreen(service: s)));
      await t.pumpAndSettle();
      final String id = (await s.myWorries(ivy)).single.id;
      await t.tap(find.byKey(Key('worry_$id')));
      await t.pumpAndSettle();
    }

    testWidgets('she takes it back after a grown-up saw it: a gentle, plain line with the grown-up picture', (WidgetTester t) async {
      final RhythmVoiceService s = await boxWith(seen: true);
      await openFirst(t, s);
      expect(find.byKey(const Key('worryBackNote')), findsNothing, reason: 'nothing is said until she acts');
      await t.tap(find.byKey(const Key('worryHide')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('worryPrivateNote')), findsOneWidget);
      final Finder note = find.byKey(const Key('worryBackNote'));
      expect(note, findsOneWidget);
      final Finder row = find.ancestor(of: note, matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byType(PictureGlyph)), findsOneWidget,
          reason: 'in her picture as well as her words');
      final String text = (t.widget(note) as Text).data!;
      expect(text, 'A grown-up already saw this one. It is just yours now.');
      expect(text, isNot(matches(RegExp(r'sorry|oops|should|wrong|bad|worry about|tell|!|serious|urgent', caseSensitive: false))));
      expect(find.byKey(const Key('worryShowLater')), findsOneWidget, reason: 'she can show it again whenever she likes');
    });

    testWidgets('she takes it back before anyone saw it: only "just yours", no claim about a grown-up', (WidgetTester t) async {
      final RhythmVoiceService s = await boxWith(seen: false);
      await openFirst(t, s);
      await t.tap(find.byKey(const Key('worryHide')));
      await t.pumpAndSettle();
      expect((t.widget(find.byKey(const Key('worryBackNote'))) as Text).data, 'It is just yours now.');
      expect(find.textContaining('already saw'), findsNothing);
    });

    testWidgets('the line goes away when she opens another worry or shows it again', (WidgetTester t) async {
      final RhythmVoiceService s = await boxWith(seen: true);
      await openFirst(t, s);
      await t.tap(find.byKey(const Key('worryHide')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryShowLater')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('worryBackNote')), findsNothing);
      expect(find.byKey(const Key('worryShownNote')), findsOneWidget);
    });
  });
}

SwitchListTile tester(WidgetTester t, String key) => t.widget<SwitchListTile>(find.byKey(Key(key)));
