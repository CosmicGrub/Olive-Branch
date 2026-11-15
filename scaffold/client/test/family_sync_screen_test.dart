// OLIVE BRANCH — the grown-ups' sharing screen: sharing a card, copying and pasting an update, choosing between two
// cards, plain words only, and nothing at all for a child. Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/family_sync_bundle.dart';
import 'package:olive_client/family_sync_emergency.dart';
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';
import 'package:olive_client/family_sync_screen.dart';

import 'family_sync_test_support.dart';

const FamilyPrincipal _mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal _dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal _kid = FamilyPrincipal(roleName: 'child', childId: 'ivy');

class FakeClipboard implements SyncClipboardPort {
  String? text;
  @override
  Future<void> write(String t) async => text = t;
  @override
  Future<String?> read() async => text;
}

LocalEmergencyCard card({String allergy = 'penicillin', String doctor = 'Dr A'}) => LocalEmergencyCard(
      allergies: <String>[allergy],
      doctor: EcDoctor(name: doctor, phone: '555-0100'),
      contacts: const <EcContact>[EcContact(name: 'Nan', relation: 'grandmother', phone: '555-0101')],
    );

final RegExp _technical = RegExp(r'\b(ledger|keys?|sync(ed|ing)?|epoch|events?|mailbox|bundle|encrypt\w*|cipher\w*|hash|signature|seal)\b', caseSensitive: false);

/// The engine's crypto runs on real time, so let real time pass between frames.
Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> allText(WidgetTester t) => <String>[
      for (final Text w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

void main() {
  late SyncRig rig;
  late Clock clock;
  late SyncEngine m, d;
  late EmergencyCardService momCard, dadCard;
  late FakeClipboard momClip, dadClip;

  // Everything is built INSIDE the test body, in the test's own zone: a service or engine made in setUp keeps a
  // future from the outer zone and an await on it would never finish under a widget test.
  Future<void> boot() async {
    rig = await SyncRig.make();
    clock = Clock(1800000000000 + 10 * 86400000);
    m = rig.engine(rig.mom, clock: clock);
    d = rig.engine(rig.dad, clock: clock);
    momCard = EmergencyCardService.memory(clock: () => DateTime.utc(2026, 11, 14));
    dadCard = EmergencyCardService.memory(clock: () => DateTime.utc(2026, 11, 14));
    momClip = FakeClipboard();
    dadClip = FakeClipboard();
  }

  Future<void> show(WidgetTester t, {required SyncEngine e, required FamilyPrincipal? p, required EmergencyCardService s, required FakeClipboard c, String name = 'Mom'}) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: FamilySyncScreen(
        engine: e, childId: 'ivy', principal: p, cardService: s, ledger: () async => rig.state, myName: name, clipboard: c,
      ),
    ));
    await settle(t);
  }

  Future<void> tap(WidgetTester t, Key k) async {
    await t.tap(find.byKey(k));
    await settle(t);
  }

  testWidgets('a child, or nobody, gets an empty page: no text, no button, nothing to tap', (WidgetTester t) async {
    await boot();
    for (final FamilyPrincipal? p in <FamilyPrincipal?>[_kid, null, const FamilyPrincipal(roleName: 'guardian')]) {
      await show(t, e: m, p: p, s: momCard, c: momClip);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    }
  });

  testWidgets('before anything is shared: says so, and cannot share a card that has not been written', (WidgetTester t) async {
    await boot();
    await show(t, e: m, p: _mom, s: momCard, c: momClip);
    expect(find.text('Nothing has been shared yet.'), findsOneWidget);
    expect(find.text('Write the card on this phone first.'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('sync-share-mine'))).onPressed, isNull);
  });

  testWidgets('share on one phone, copy, paste on the other, and use it there: the whole road, in plain words', (WidgetTester t) async {
    await boot();
    await momCard.save(_mom, card(), expectedVersion: 0);
    await show(t, e: m, p: _mom, s: momCard, c: momClip, name: 'Mom');
    await tap(t, const Key('sync-share-mine'));
    expect(find.byKey(const Key('sync-status')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, startsWith('Saved on this phone.'));
    expect(find.textContaining('Shared by Mom'), findsOneWidget);
    expect(find.byKey(const Key('sync-same')), findsOneWidget);
    await tap(t, const Key('sync-copy'));
    expect(momClip.text, startsWith('OLIVE-UPDATE-1.'));
    expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, 'Copied. Paste it on the other phone.');

    // The other phone, with its own different card.
    await dadCard.save(_dad, card(allergy: 'dust', doctor: 'Dr B'), expectedVersion: 0);
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip, name: 'Dad');
    await tap(t, const Key('sync-paste'));
    await t.enterText(find.byKey(const Key('sync-paste-field')), momClip.text!);
    await tap(t, const Key('sync-paste-add'));
    expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, 'Added 1 update.');
    expect(find.byKey(const Key('sync-differs')), findsOneWidget);
    expect((await dadCard.read(_dad)).card!.allergies, <String>['dust'], reason: 'the pasted card did not replace theirs');
    await tap(t, const Key('sync-use-here'));
    expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, 'The shared card is now the card on this phone.');
    expect((await dadCard.read(_dad)).card!.allergies, <String>['penicillin']);
    expect(find.byKey(const Key('sync-same')), findsOneWidget);
  });

  testWidgets('two different cards: both are shown, nothing is changed, and keeping one settles it', (WidgetTester t) async {
    await boot();
    await momCard.save(_mom, card(), expectedVersion: 0);
    await dadCard.save(_dad, card(allergy: 'dust', doctor: 'Dr B'), expectedVersion: 0);
    await show(t, e: m, p: _mom, s: momCard, c: momClip, name: 'Mom');
    await tap(t, const Key('sync-share-mine'));
    clock.ms += 1000;
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip, name: 'Dad');
    await tap(t, const Key('sync-share-mine'));
    // Each hands the other an update.
    await tap(t, const Key('sync-copy'));
    final String fromDad = dadClip.text!;
    await show(t, e: m, p: _mom, s: momCard, c: momClip, name: 'Mom');
    await tap(t, const Key('sync-copy'));
    final String fromMom = momClip.text!;
    await tap(t, const Key('sync-paste'));
    await t.enterText(find.byKey(const Key('sync-paste-field')), fromDad);
    await tap(t, const Key('sync-paste-add'));
    expect(find.byKey(const Key('sync-forked')), findsOneWidget);
    expect(find.text('Keep this card'), findsNWidgets(2));
    expect(find.textContaining('From Mom'), findsOneWidget);
    expect(find.textContaining('From Dad'), findsOneWidget);
    expect((await momCard.read(_mom)).card!.allergies, <String>['penicillin'], reason: 'nothing changed on this phone');
    // Mom keeps Dad's card.
    final Finder keepDad = find.descendant(of: find.ancestor(of: find.textContaining('From Dad'), matching: find.byType(Card)), matching: find.byType(FilledButton));
    await t.tap(keepDad);
    await settle(t);
    expect(find.byKey(const Key('sync-forked')), findsNothing);
    expect(find.textContaining('dust'), findsWidgets);
    // Dad receives the choice.
    await tap(t, const Key('sync-copy'));
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip, name: 'Dad');
    await tap(t, const Key('sync-paste'));
    await t.enterText(find.byKey(const Key('sync-paste-field')), momClip.text!);
    await tap(t, const Key('sync-paste-add'));
    expect(find.byKey(const Key('sync-forked')), findsNothing);
    expect(fromMom, isNotEmpty);
  });

  testWidgets('two different updates under one number: said in plain words with no numbers, and nothing on this phone changes', (WidgetTester t) async {
    await boot();
    Future<SyncEvent> one(String text) async => SyncEvent.create(
          device: rig.mom.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: await syncStreamId(rig.fid, 'emergencycard', 'ivy'),
          seq: 1, hlcMs: clock.ms, hlcC: 0, prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': text},
        );
    final SyncEvent x = await t.runAsync(() => one('x')) as SyncEvent, y = await t.runAsync(() => one('y')) as SyncEvent;
    await t.runAsync(() => d.ingest(<Uint8List>[x.wire], state: rig.state));
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip, name: 'Dad');
    expect(find.byKey(const Key('sync-conflict')), findsNothing);
    // The second update arrives in a pasted text that holds nothing else.
    final SyncEngine relay = rig.engine(rig.mom, clock: clock);
    await t.runAsync(() => relay.ingest(<Uint8List>[y.wire], state: rig.state));
    final String text = (await t.runAsync(() => exportBundle(relay, force: true)))!.text;
    await tap(t, const Key('sync-paste'));
    await t.enterText(find.byKey(const Key('sync-paste-field')), text);
    await tap(t, const Key('sync-paste-add'));
    expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, kSyncConflictText);
    expect(find.byKey(const Key('sync-conflict')), findsOneWidget);
    expect(d.equivocations.length, 1);
    expect(allText(t).where(_technical.hasMatch), isEmpty);
    expect(allText(t).where(RegExp(r'\d').hasMatch), isEmpty, reason: 'no counts or numbers on the page');
    expect((await dadCard.read(_dad)).card, isNull, reason: 'nothing on this phone changed');
  });

  testWidgets('pasting something that is not an update says so gently and changes nothing', (WidgetTester t) async {
    await boot();
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip);
    for (final String junk in <String>['hello', 'OLIVE-UPDATE-1.garbage', 'OLIVE-UPDATE-1.']) {
      await tap(t, const Key('sync-paste'));
      await t.enterText(find.byKey(const Key('sync-paste-field')), junk);
      await tap(t, const Key('sync-paste-add'));
      expect(t.widget<Text>(find.byKey(const Key('sync-status'))).data, 'That does not look like an update from your family. Nothing was changed.');
    }
    expect(d.eventCount, 0);
  });

  testWidgets('the first copy always goes (so the other phone learns what this one holds); an update waiting on a missing piece is reported', (WidgetTester t) async {
    await boot();
    await show(t, e: m, p: _mom, s: momCard, c: momClip);
    await tap(t, const Key('sync-copy'));
    expect(momClip.text, isNotNull, reason: 'the first copy always goes, so the other phone learns what this one holds');
    // A phone that has been told of a later event but not an earlier one.
    await momCard.save(_mom, card(), expectedVersion: 0);
    await m.append(kind: 'emergency.set', streamId: await EmergencySync(m, 'ivy').streamId(), payload: <String, Object?>{'t': 1}, state: rig.state);
    await m.append(kind: 'emergency.set', streamId: await EmergencySync(m, 'ivy').streamId(), payload: <String, Object?>{'t': 2}, state: rig.state);
    final List<List<int>> wires = m.eventsFor(null).wires;
    await d.ingest(<List<int>>[wires[1]], state: rig.state);
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip);
    expect(find.byKey(const Key('sync-missing')), findsOneWidget);
  });

  testWidgets('every word on the page, in every state, is plain: no technical word, no count, no score', (WidgetTester t) async {
    await boot();
    final List<String> seen = <String>[];
    await momCard.save(_mom, card(), expectedVersion: 0);
    await show(t, e: m, p: _mom, s: momCard, c: momClip);
    seen.addAll(allText(t));
    await tap(t, const Key('sync-share-mine'));
    seen.addAll(allText(t));
    await tap(t, const Key('sync-copy'));
    seen.addAll(allText(t));
    await dadCard.save(_dad, card(allergy: 'dust'), expectedVersion: 0);
    await show(t, e: d, p: _dad, s: dadCard, c: dadClip);
    await tap(t, const Key('sync-paste'));
    await t.enterText(find.byKey(const Key('sync-paste-field')), momClip.text!);
    await tap(t, const Key('sync-paste-add'));
    seen.addAll(allText(t));
    for (final String s in syncRefusalTexts) {
      seen.add(s);
    }
    expect(seen.where((String s) => s.isNotEmpty), isNotEmpty);
    for (final String s in seen) {
      expect(_technical.hasMatch(s), isFalse, reason: s);
    }
  });
}

/// Every refusal sentence the screen can show.
List<String> get syncRefusalTexts => <String>[
      for (final String r in <String>['empty', 'forked', 'unreadable', 'same', 'not_member', 'no_key', 'full', 'moved', 'stale_version', 'guardian_only', '?'])
        syncRefusalText(r),
    ];
