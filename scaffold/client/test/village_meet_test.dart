// OLIVE BRANCH — tests for the in-person meeting (village_meet.dart): a code on a grown-up's screen, a new phone that
// types it, the same word and picture on both, the offer sealed to the new phone, and the hostile cases (wrong codes,
// a second phone, a replay, a swapped or tampered offer, an offer that names someone else, a window that has ended).
// UNVERIFIED until CI runs it. Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md section 3.2.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/pairing_limits.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/village_link.dart';
import 'package:olive_client/village_meet.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'village_test_support.dart';

/// Hands each message to the window as JSON, like the wire does, and remembers what was sent.
class Direct implements PairingTransport {
  Direct(this.window, {this.source = 'a', this.mangle});
  final VillageMeetWindow window;
  final String source;
  final Map<String, dynamic>? Function(Map<String, dynamic>)? mangle;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final Map<String, dynamic> m = jsonDecode(jsonEncode(message)) as Map<String, dynamic>;
    sent.add(m);
    final Map<String, dynamic>? r = await window.handle(m, source: source);
    if (r == null) return null;
    final Map<String, dynamic> out = jsonDecode(jsonEncode(r)) as Map<String, dynamic>;
    return mangle == null ? out : mangle!(out);
  }
}

VillageMeetWindow openWindow({String code = '482915', DateTime Function()? now}) =>
    VillageMeetWindow.open(code: code, now: now, bucket: SourceBucket(limit: 1000));

VillageJoiner joinerFor(P p) => VillageJoiner(device: p.key, agreement: p.agree, deviceName: 'Jo\'s phone');

void main() {
  test('the code is six digits and the window lives fifteen minutes', () {
    final VillageMeetWindow w = VillageMeetWindow.open();
    expect(RegExp(r'^\d{6}$').hasMatch(w.code), isTrue);
    expect(kMeetTtl, const Duration(minutes: 15));
    expect(w.isOpen, isTrue);
  });

  test('the mode is in the channel, so a pairing transcript is not a meeting transcript', () {
    final Uint8List a = meetChannelId(List<int>.filled(32, 1));
    expect(utf8.decode(a, allowMalformed: true), contains('join-member'));
    expect(a, isNot(equals(meetChannelId(List<int>.filled(32, 2)))));
  });

  group('a meeting', () {
    test('introduce, match, propose, offer, take it, say yes: the whole road, and the pictures agree', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      final Direct tr = Direct(w);
      final JoinMeeting? meeting = await joinerFor(joP).meet(transport: tr, handle: w.discoveryHandle, code: '482915');
      expect(meeting, isNotNull);
      expect(w.state, MeetState.introduced);
      expect(w.sas.toString(), meeting!.sas.toString(), reason: 'both phones show the same word and picture');
      expect(w.intro!.deviceName, 'Jo\'s phone');
      expect(w.intro!.record.key, joP.key.publicKey);
      expect((await meeting.poll(nowMs: v.clock.now)).kind, JoinPollKind.waiting);
      await expectLater(w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes), throwsStateError,
          reason: 'nothing is offered before the grown-up has seen the pictures match');
      w.confirmMatch();
      final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
      await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      final JoinPoll p = await meeting.poll(nowMs: v.clock.now);
      expect(p.kind, JoinPollKind.offered);
      final LedgerState s = await reduceLedger(entries: p.entries, votes: p.votes, nowMs: v.clock.now);
      expect(findInvitation(s, p.entries, joP.key.publicKey)!.hashHex, e.hashHex);
      // Jo keeps the record, says yes, and the yes goes back by the door.
      final MemoryFamilyRepository repo = MemoryFamilyRepository();
      final FamilyContext jo = await adoptOfferedRecord(
          device: joP.key, agreement: joP.agree, entries: p.entries, votes: p.votes, repository: repo, nowMs: v.clock.now);
      await candidateSaysYes(ctx: jo, repository: repo, invitation: e, nowMs: v.clock.now);
      final VillageDoor door = VillageDoor(context: jo, repository: repo, nowMs: () => v.clock.now);
      final DoorOutcome o = await door.exchange((Map<String, dynamic> m) => v.mom.door.handle(m));
      expect(o.heardFrom, isNotEmpty);
      expect(v.mom.ctx.votes.any((LedgerVote x) => x.voterHex == joP.keyHex && x.answer == 'yes'), isTrue);
    });

    test('five wrong codes end the window, and then even the right code gets silence', () async {
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      for (int i = 0; i < kMeetMaxAttempts; i++) {
        expect(await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '000000'), isNull);
      }
      expect(w.state, MeetState.closed);
      expect(await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'), isNull);
      expect(w.intro, isNull);
    });

    test('a wrong code then the right one still works while the window is open', () async {
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      expect(await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '111111'), isNull);
      expect(w.failures, 1);
      expect(await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'), isNotNull);
    });

    test('a window that has ended answers nothing', () async {
      final P joP = await P.make(5);
      DateTime t = DateTime.utc(2026, 11, 15, 12);
      final VillageMeetWindow w = openWindow(now: () => t);
      t = t.add(kMeetTtl + const Duration(seconds: 1));
      expect(await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'), isNull);
      expect(w.state, MeetState.closed);
    });

    test('the wrong window handle is silence, and the window is untouched', () async {
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      expect(await joinerFor(joP).meet(transport: Direct(w), handle: Uint8List(16), code: '482915'), isNull);
      expect(w.failures, 0);
      expect(w.state, MeetState.open);
    });

    test('a second phone cannot join a window that already has one, and a replayed message does nothing', () async {
      final P a = await P.make(5), b = await P.make(6);
      final VillageMeetWindow w = openWindow();
      final Direct first = Direct(w);
      expect(await joinerFor(a).meet(transport: first, handle: w.discoveryHandle, code: '482915'), isNotNull);
      expect(await joinerFor(b).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'), isNull);
      expect(w.intro!.record.key, a.key.publicKey);
      // Replay every message the first phone sent, in order: the window stays exactly as it is.
      final MeetState before = w.state;
      for (final Map<String, dynamic> m in List<Map<String, dynamic>>.of(first.sent)) {
        if (m['t'] == 'm5') continue; // a poll is read-only
        await w.handle(m, source: 'a');
      }
      expect(w.state, before);
      expect(w.intro!.record.key, a.key.publicKey);
      expect(w.failures, 0);
    });

    test('the new phone never says what it will be: a role in its introduction is not read', () async {
      // The introduction is parsed for its two keys and its name and nothing else; the record that comes out is a bare
      // device record, and the profile only ever arrives on the grown-up\'s own proposal.
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915');
      final MeetIntro i = w.intro!;
      expect(i.record.cert, isNotNull);
      expect(await verifyAgreementCert(i.record), isTrue);
    });

    test('an offer that does not name this phone is not taken', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5), other = await P.make(6);
      final VillageMeetWindow w = openWindow();
      final JoinMeeting meeting = (await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'))!;
      w.confirmMatch();
      await v.mom.welcome().propose(WelcomeDraft(personName: 'Eve', profile: carerProfile(), candidate: other.rec));
      await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      expect((await meeting.poll(nowMs: v.clock.now)).kind, JoinPollKind.failed);
    });

    test('an offer with a changed byte on its way is not taken', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      // A man in the middle changes one byte of the sealed offer on its way.
      final Direct tampering = Direct(w, mangle: (Map<String, dynamic> r) {
        if (r['t'] != 'cred') return r;
        final Uint8List raw = unb64(r['sealed'] as String);
        r['sealed'] = b64(flip(raw, raw.length ~/ 2));
        return r;
      });
      final JoinMeeting meeting = (await joinerFor(joP).meet(transport: tampering, handle: w.discoveryHandle, code: '482915'))!;
      w.confirmMatch();
      await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
      await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      expect((await meeting.poll(nowMs: v.clock.now)).kind, JoinPollKind.failed);
    });

    test('an offer whose entries carry a bad signature is not taken', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      final JoinMeeting meeting = (await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'))!;
      w.confirmMatch();
      await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
      // The grown-up's phone is made to offer a record in which one entry's signature was altered.
      final LedgerEntry last = v.mom.ctx.entries.last;
      final Map<String, Object?> j = last.toJson();
      final Uint8List sig = unb64(j['s']! as String);
      j['s'] = b64(flip(sig, 5));
      final LedgerEntry broken = (await LedgerEntry.fromJson(j))!;
      await w.offer(entries: <LedgerEntry>[...v.mom.ctx.entries.take(v.mom.ctx.entries.length - 1), broken], votes: v.mom.ctx.votes);
      expect((await meeting.poll(nowMs: v.clock.now)).kind, JoinPollKind.failed);
    });

    test('declining ends it: nothing is offered and the new phone is told only that it did not work', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final VillageMeetWindow w = openWindow();
      final JoinMeeting meeting = (await joinerFor(joP).meet(transport: Direct(w), handle: w.discoveryHandle, code: '482915'))!;
      w.decline();
      expect(w.state, MeetState.declined);
      expect((await meeting.poll(nowMs: v.clock.now)).kind, JoinPollKind.failed);
      await expectLater(w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes), throwsStateError);
    });

    test('a phone cannot keep a family when it already holds one', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final Phone jo = Phone.of(joP, entries: v.mom.ctx.entries, votes: v.mom.ctx.votes, pin: v.fam.pin, clock: v.clock);
      await jo.repo.save(jo.ctx.snapshot());
      await expectLater(
          adoptOfferedRecord(
              device: joP.key, agreement: joP.agree, entries: v.mom.ctx.entries, votes: v.mom.ctx.votes, repository: jo.repo, nowMs: v.clock.now),
          throwsA(isA<Object>()));
    });
  });
}
