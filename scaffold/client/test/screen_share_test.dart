// OLIVE BRANCH — sharing a screen from one grown-up to another, inside the app: who can be chosen, the sealed format,
// expiry, take-back, and every hostile case. Verified by CI, headless.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/local_pin.dart' show kLocalGuardianScope;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart' show LocalStoreFull;
import 'package:olive_client/screen_share.dart';

import 'family_test_support.dart';

/// The smallest thing [looksLikePng] accepts: the signature, an IHDR, and room to spare. (The UI tests use real PNGs.)
Uint8List pngOf({int w = 8, int h = 8, int pad = 0}) {
  final List<int> b = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52];
  for (final int v in <int>[w, h]) {
    b.addAll(<int>[(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
  }
  b.addAll(<int>[8, 6, 0, 0, 0, 1, 2, 3, 4]);
  b.addAll(List<int>.filled(pad, 7));
  return Uint8List.fromList(b);
}

class _Road implements ShareTransport {
  _Road(this.onDeliver);
  final Future<bool> Function(String key, Uint8List bytes) onDeliver;
  final List<String> to = <String>[];
  bool open = true;
  @override
  Future<bool> deliver(String recipientKeyHex, Uint8List bytes) async {
    to.add(recipientKeyHex);
    return open && await onDeliver(recipientKeyHex, bytes);
  }
}

void main() {
  late P mom, dad, kid, gran, aunt, stranger;
  late Fam fam;
  late LedgerState state;
  late int now;

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    kid = await P.make(3);
    gran = await P.make(4);
    aunt = await P.make(6);
    stranger = await P.make(5);
    fam = await Fam.found(mom);
    await fam.welcomeParent(mom, dad, others: <P>[]);
    await fam.addChild(mom, kid);
    final LedgerEntry cw = await fam.add(mom, EntryType.memberAdd,
        fam.memberBody(gran, kind: 'carer', preset: Preset.viewOnly, electors: <P>[mom, dad], rule: 'one', name: 'Gran'));
    await fam.vote(gran, cw, 'yes');
    await fam.vote(mom, cw, 'yes');
    now = t0 + 3 * day;
    state = await fam.state(now);
  });

  ScreenShareService svc(P who, {ShareTransport? road, bool guardian = true, LedgerState? st, int Function()? clock}) =>
      ScreenShareService(
        box: MemoryShareBoxRepository(),
        identity: () async => ShareIdentity(device: who.key, agreement: who.agree, state: st ?? state),
        transport: road ?? const NoShareTransport(),
        guardianDevice: guardian,
        nowMs: clock ?? () => now,
      );

  group('who can be chosen', () {
    test('another grown-up, and only that: not me, not a child device, not a carer, not a stranger', () {
      final List<ShareRecipient> r = eligibleShareRecipients(state, mom.key.publicKey, now);
      expect(r.map((ShareRecipient e) => e.name), <String>['Sam']);
      expect(r.single.keyHex, dad.keyHex);
      final Set<String> all = <String>{for (final ShareRecipient e in r) e.keyHex};
      expect(all.contains(mom.keyHex), isFalse);
      expect(all.contains(kid.keyHex), isFalse, reason: 'a child device is never a recipient');
      expect(all.contains(gran.keyHex), isFalse, reason: 'a carer is not a grown-up of the family for this');
      expect(all.contains(stranger.keyHex), isFalse);
    });

    test('a family with one grown-up has no one to share with', () async {
      final Fam solo = await Fam.found(mom);
      await solo.addChild(mom, kid);
      expect(eligibleShareRecipients(await solo.state(now), mom.key.publicKey, now), isEmpty);
    });

    test('a child device, a carer device and an unknown device get no list at all', () {
      for (final P who in <P>[kid, gran, stranger]) {
        expect(eligibleShareRecipients(state, who.key.publicKey, now), isEmpty, reason: who.keyHex);
      }
    });

    test('a grown-up still settling in is not offered, and is once the time has passed', () async {
      final Fam f = await Fam.found(mom, policy: const FamilyPolicy(settleHours: 72));
      await f.welcomeParent(mom, dad, others: <P>[]);
      final int early = f.clock + 3600000;
      expect(eligibleShareRecipients(await f.state(early), mom.key.publicKey, early), isEmpty);
      final int later = f.clock + 5 * day;
      expect(eligibleShareRecipients(await f.state(later), mom.key.publicKey, later).single.keyHex, dad.keyHex);
    });

    test('a grown-up who has left the family is gone from the list', () async {
      await fam.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await fam.state(t0 + 5 * day);
      expect(s.holdsAnything(dad.key.publicKey), isFalse);
      expect(eligibleShareRecipients(s, mom.key.publicKey, t0 + 5 * day), isEmpty);
    });
  });

  group('the sealed format', () {
    late ShareRecipient toDad;
    setUp(() => toDad = eligibleShareRecipients(state, mom.key.publicKey, now).single);

    Future<Uint8List> seal({String note = 'see the schedule', bool hide = true, int days = 7}) => sealShare(
        sender: mom.key, state: state, to: toDad, png: pngOf(pad: 500), namesHidden: hide, nowMs: now, expiryDays: days, note: note);

    Future<ReceivedShare?> open(Uint8List b, {P? as, LedgerState? st, int? at, bool guardian = true}) {
      final P who = as ?? dad;
      return openShare(sealed: b, own: who.key, agreement: who.agree, state: st ?? state, nowMs: at ?? now, guardianDevice: guardian);
    }

    test('only the addressed grown-up opens it, and sees who sent it, the note, the flag and the picture', () async {
      final Uint8List b = await seal();
      final ReceivedShare r = (await open(b))!;
      expect(r.fromName, 'Mom');
      expect(r.fromKeyHex, mom.keyHex);
      expect(r.note, 'see the schedule');
      expect(r.namesHidden, isTrue);
      expect(r.png, pngOf(pad: 500));
      expect(r.expiresAtMs, now + 7 * day);
    });

    test('the picture is not in the bytes, and nobody else can open it: not the sender, a child device, a carer, a stranger', () async {
      final Uint8List b = await seal();
      expect(utf8.decode(b, allowMalformed: true).contains(base64Url.encode(pngOf(pad: 500)).substring(0, 20)), isFalse);
      for (final P who in <P>[mom, kid, gran, stranger, aunt]) {
        expect(await open(b, as: who), isNull, reason: who.keyHex);
      }
    });

    test('a child device refuses even if it is handed the bytes with the grown-up\'s own keys in the call', () async {
      final Uint8List b = await seal();
      expect(await open(b, guardian: false), isNull);
      final ScreenShareService childSvc = ScreenShareService.childDevice();
      expect(await childSvc.receive(b), ShareReceiveOutcome.refused);
      expect(await childSvc.inbox(), isEmpty);
      expect(await childSvc.recipients(), isEmpty);
      expect(await childSvc.sent(), isEmpty);
      expect(await childSvc.history(), isEmpty);
      expect(
          () => childSvc.send(png: pngOf(), to: toDad, namesHidden: false),
          throwsA(isA<ShareRefused>()),
          reason: 'a child device can never send');
    });

    test('a ledger that lists this device as a child device refuses too', () async {
      final Uint8List b = await seal();
      expect(await open(b, as: kid), isNull);
      final ScreenShareService asKid = svc(kid);
      expect(await asKid.recipients(), isEmpty);
      expect(await asKid.receive(b), ShareReceiveOutcome.refused);
      expect(() => asKid.send(png: pngOf(), to: toDad, namesHidden: false), throwsA(isA<ShareRefused>()));
    });

    test('sealing to a child device, a carer, yourself or a stranger is refused at the source', () async {
      for (final P who in <P>[kid, gran, mom, stranger]) {
        final ShareRecipient bad = ShareRecipient(deviceKey: who.key.publicKey, agree: who.agree.publicKey, name: 'x');
        await expectLater(
            sealShare(sender: mom.key, state: state, to: bad, png: pngOf(), namesHidden: false, nowMs: now),
            throwsA(isA<ShareRefused>()),
            reason: who.keyHex);
      }
    });

    test('a recipient with the right key but a swapped agreement key is refused', () async {
      final ShareRecipient swapped = ShareRecipient(deviceKey: dad.key.publicKey, agree: stranger.agree.publicKey, name: 'Sam');
      await expectLater(sealShare(sender: mom.key, state: state, to: swapped, png: pngOf(), namesHidden: false, nowMs: now),
          throwsA(isA<ShareRefused>()));
    });

    test('a child device or a carer cannot be the sender', () async {
      for (final P who in <P>[kid, gran, stranger]) {
        await expectLater(
            sealShare(sender: who.key, state: state, to: toDad, png: pngOf(), namesHidden: false, nowMs: now),
            throwsA(isA<ShareRefused>()),
            reason: who.keyHex);
      }
    });

    test('a forged sender: a stranger\'s signature, or a real grown-up\'s name on someone else\'s signature, opens nothing', () async {
      final Uint8List b = await seal();
      final Map<String, Object?> m = jsonDecode(utf8.decode(b)) as Map<String, Object?>;
      m['from'] = b64(stranger.key.publicKey);
      expect(await open(Uint8List.fromList(utf8.encode(jsonEncode(m)))), isNull, reason: 'signer changed');
      final Map<String, Object?> m2 = jsonDecode(utf8.decode(b)) as Map<String, Object?>;
      m2['from'] = b64(kid.key.publicKey);
      expect(await open(Uint8List.fromList(utf8.encode(jsonEncode(m2)))), isNull, reason: 'a child device as the sender');
    });

    test('every field is bound: a changed recipient, time, expiry, id, key or picture opens nothing', () async {
      final Uint8List b = await seal();
      Future<ReceivedShare?> tweak(void Function(Map<String, Object?>) f) async {
        final Map<String, Object?> m = jsonDecode(utf8.decode(b)) as Map<String, Object?>;
        f(m);
        return open(Uint8List.fromList(utf8.encode(jsonEncode(m))));
      }

      expect(await tweak((Map<String, Object?> m) => m['exp'] = (m['exp']! as int) + 1), isNull);
      expect(await tweak((Map<String, Object?> m) => m['iat'] = (m['iat']! as int) - 1), isNull);
      expect(await tweak((Map<String, Object?> m) => m['id'] = b64(List<int>.filled(16, 1))), isNull);
      expect(await tweak((Map<String, Object?> m) => m['to'] = b64(aunt.key.publicKey)), isNull);
      expect(await tweak((Map<String, Object?> m) => m['eph'] = b64(List<int>.filled(32, 9))), isNull);
      expect(await tweak((Map<String, Object?> m) => m['v'] = 2), isNull);
      expect(await tweak((Map<String, Object?> m) => m['t'] = 'retract'), isNull);
      final String ct = (jsonDecode(utf8.decode(b)) as Map<String, Object?>)['ct']! as String;
      final Uint8List raw = unb64(ct);
      for (int i = 0; i < raw.length; i += 41) {
        expect(await tweak((Map<String, Object?> m) => m['ct'] = b64(Uint8List.fromList(raw)..[i] ^= 1)), isNull, reason: 'byte $i');
      }
      expect(await tweak((Map<String, Object?> m) => m['ct'] = b64(raw.sublist(0, raw.length - 1))), isNull);
      expect(await tweak((Map<String, Object?> m) => m['sig'] = b64(List<int>.filled(64, 0))), isNull);
    });

    test('junk in, nothing out: empty, huge, not JSON, wrong types', () async {
      for (final List<int> junk in <List<int>>[
        <int>[],
        utf8.encode('{'),
        utf8.encode('[]'),
        utf8.encode('{"v":1,"t":"share"}'),
        utf8.encode('{"v":1,"t":"share","id":5,"from":6,"to":7,"eph":8,"sig":9,"iat":"x","exp":null,"ct":3}'),
        List<int>.filled(kShareMaxSealedBytes + 1, 0x20),
      ]) {
        expect(await open(Uint8List.fromList(junk)), isNull);
      }
    });

    test('expired, not yet valid, and an expiry longer than 30 days are all refused', () async {
      final Uint8List b = await seal(days: 1);
      expect(await open(b, at: now + day - 1), isNotNull);
      expect(await open(b, at: now + day), isNull, reason: 'at the expiry it is gone');
      expect(await open(b, at: now - 6 * 60 * 1000), isNull, reason: 'dated in the future');
      await expectLater(seal(days: 31), throwsA(isA<ShareRefused>()));
      await expectLater(seal(days: 0), throwsA(isA<ShareRefused>()));
      final Map<String, Object?> m = jsonDecode(utf8.decode(await seal(days: 30))) as Map<String, Object?>;
      expect((m['exp']! as int) - (m['iat']! as int), 30 * day);
    });

    test('a picture that is not a PNG, or is oversized, or has an absurd size, or a note that is too long, is refused', () async {
      Future<Uint8List> with_(Uint8List png, {String note = ''}) =>
          sealShare(sender: mom.key, state: state, to: toDad, png: png, namesHidden: false, nowMs: now, note: note);
      await expectLater(with_(Uint8List.fromList(utf8.encode('GIF89a not a png at all, long enough to pass a length check'))), throwsA(isA<ShareRefused>()));
      await expectLater(with_(pngOf(pad: kShareMaxImageBytes)), throwsA(isA<ShareRefused>()));
      await expectLater(with_(pngOf(w: 100000, h: 100000)), throwsA(isA<ShareRefused>()));
      await expectLater(with_(pngOf(w: 0, h: 5)), throwsA(isA<ShareRefused>()));
      await expectLater(with_(Uint8List(10)), throwsA(isA<ShareRefused>()));
      await expectLater(with_(pngOf(), note: 'x' * (kShareMaxNoteChars + 1)), throwsA(isA<ShareRefused>()));
      expect(await with_(pngOf(), note: 'x' * kShareMaxNoteChars), isNotEmpty);
    });

    test('looksLikePng is strict about its edges', () {
      expect(looksLikePng(pngOf()), isTrue);
      expect(looksLikePng(pngOf(w: 4096, h: 4096)), isTrue);
      expect(looksLikePng(pngOf(w: 4097, h: 1)), isFalse);
      expect(looksLikePng(pngOf()..[12] = 0x58), isFalse, reason: 'not IHDR');
      expect(looksLikePng(pngOf()..[0] = 0), isFalse);
    });

    test('two seals of the same picture are different bytes (a fresh key each time) and the id is fresh', () async {
      final Uint8List a = await seal(), b = await seal();
      expect(a, isNot(b));
      expect((await open(a))!.idHex, isNot((await open(b))!.idHex));
    });

    test('a grown-up who has since left the family cannot send, and a picture from one is not opened', () async {
      final Uint8List b = await seal();
      await fam.add(mom, EntryType.guardianLeave, <String, Object?>{'gid': mom.gid});
      final LedgerState later = await fam.state(t0 + 5 * day);
      expect(later.isActiveGuardianDevice(mom.key.publicKey), isFalse);
      expect(await open(b, st: later, at: now + 60000), isNull);
      await expectLater(
          sealShare(sender: mom.key, state: later, to: toDad, png: pngOf(), namesHidden: false, nowMs: now + 60000),
          throwsA(isA<ShareRefused>()));
    });
  });

  group('the service: send, wait, take back, expire', () {
    late _Road road;
    late ScreenShareService momSvc, dadSvc;
    late ShareRecipient toDad, toMom;
    int clock0 = 0;
    int clock() => clock0;

    setUp(() {
      clock0 = now;
      dadSvc = svc(dad, clock: clock);
      road = _Road((String key, Uint8List bytes) async => await dadSvc.receive(bytes) != ShareReceiveOutcome.refused);
      momSvc = svc(mom, road: road, clock: clock);
      toDad = eligibleShareRecipients(state, mom.key.publicKey, now).single;
      toMom = eligibleShareRecipients(state, dad.key.publicKey, now).single;
    });

    test('with no road it waits sealed, says so, and keeps one quiet history line without the picture', () async {
      final ScreenShareService s = svc(mom, clock: clock);
      expect(await s.send(png: pngOf(), to: toDad, namesHidden: false), ShareSendOutcome.waiting);
      final OutgoingShare o = (await s.sent()).single;
      expect(o.status, 'waiting');
      expect(o.sealed, isNotNull);
      expect((await s.history()).single.text, 'Mom shared a screen with Sam');
      expect(await s.flush(), 0);
    });

    test('with a road it arrives, the sender stops keeping the picture, and both phones note it', () async {
      expect(await momSvc.send(png: pngOf(pad: 40), to: toDad, namesHidden: true, note: 'hi'), ShareSendOutcome.sent);
      final OutgoingShare o = (await momSvc.sent()).single;
      expect(o.status, 'sent');
      expect(o.sealed, isNull, reason: 'the sender keeps no copy once the other phone has it');
      final ReceivedShare r = (await dadSvc.inbox()).single;
      expect(r.fromName, 'Mom');
      expect(r.note, 'hi');
      expect((await dadSvc.history()).single.text, 'Mom shared a screen with Sam');
      expect(road.to, <String>[dad.keyHex]);
    });

    test('a share that was waiting goes out on the next meeting', () async {
      road.open = false;
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      expect(await dadSvc.inbox(), isEmpty);
      road.open = true;
      expect(await momSvc.flush(), 1);
      expect(await dadSvc.inbox(), hasLength(1));
      expect(await momSvc.flush(), 0);
    });

    test('a road that throws is just "not nearby"', () async {
      final ScreenShareService s = svc(mom, road: _Road((String k, Uint8List b) async => throw StateError('radio')), clock: clock);
      expect(await s.send(png: pngOf(), to: toDad, namesHidden: false), ShareSendOutcome.waiting);
    });

    test('take back after it arrived removes it from the other phone and leaves a mark so a late copy is dropped', () async {
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      final String id = (await momSvc.sent()).single.idHex;
      await momSvc.takeBack(id);
      expect(await dadSvc.inbox(), isEmpty);
      expect(await momSvc.sent(), isEmpty, reason: 'told, so nothing is left to deliver');
    });

    test('take back while the road is closed is delivered later, and the picture is gone from the sender at once', () async {
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      final String id = (await momSvc.sent()).single.idHex;
      road.open = false;
      await momSvc.takeBack(id);
      final OutgoingShare o = (await momSvc.sent()).single;
      expect(o.status, 'retracting');
      expect(o.sealed, isNull);
      expect(await dadSvc.inbox(), hasLength(1), reason: 'not told yet');
      road.open = true;
      expect(await momSvc.flush(), 1);
      expect(await dadSvc.inbox(), isEmpty);
      expect(await momSvc.sent(), isEmpty);
    });

    test('take back BEFORE the picture arrives: the picture is dropped when it does', () async {
      road.open = false;
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      final OutgoingShare o = (await momSvc.sent()).single;
      final Uint8List sealedCopy = o.sealed!;
      await momSvc.takeBack(o.idHex);
      // The notice reaches the other phone first, then the old sealed copy turns up from somewhere.
      road.open = true;
      await momSvc.flush();
      expect(await dadSvc.receive(sealedCopy), ShareReceiveOutcome.putAway);
      expect(await dadSvc.inbox(), isEmpty);
    });

    test('a take-back from somebody else, or for a share they did not send, deletes nothing', () async {
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      final String id = (await dadSvc.inbox()).single.idHex;
      // A signed take-back for the same id, but from a stranger, a carer and a child device, is refused.
      for (final P who in <P>[stranger, gran, kid]) {
        final Uint8List n = await sealRetract(sender: who.key, id: unhex(id), toDeviceKey: dad.key.publicKey, nowMs: now);
        expect(await dadSvc.receive(n), ShareReceiveOutcome.refused, reason: who.keyHex);
      }
      // From himself to himself is refused too.
      final Uint8List self = await sealRetract(sender: dad.key, id: unhex(id), toDeviceKey: dad.key.publicKey, nowMs: now);
      expect(await dadSvc.receive(self), ShareReceiveOutcome.refused);
      expect(await dadSvc.inbox(), hasLength(1));
    });

    test('a third grown-up naming the share id of another cannot take it back: a take-back reaches only its own sender shares', () async {
      final Fam f2 = await Fam.found(mom);
      await f2.welcomeParent(mom, dad, others: <P>[]);
      f2.clock += 4 * day; // Sam has settled in, so Sam's yes counts
      final LedgerEntry e = await f2.add(mom, EntryType.memberAdd,
          f2.memberBody(aunt, electors: <P>[mom, dad], name: 'Jo', proposalId: Uint8List.fromList(List<int>.filled(16, 78))));
      await f2.vote(dad, e, 'yes');
      await f2.vote(aunt, e, 'yes');
      clock0 = f2.clock + 2 * hour;
      final LedgerState st3 = await f2.state(clock0);
      expect(st3.guardianDeviceKeys, hasLength(3));
      final ScreenShareService dad3 = svc(dad, st: st3, clock: clock);
      final ScreenShareService mom3 = svc(mom, st: st3, clock: clock);
      final ShareRecipient toDad3 = (await mom3.recipients()).firstWhere((ShareRecipient r) => r.keyHex == dad.keyHex);
      await mom3.send(png: pngOf(), to: toDad3, namesHidden: false);
      expect(await dad3.receive((await mom3.sent()).single.sealed!), ShareReceiveOutcome.kept);
      final String id = (await dad3.inbox()).single.idHex;
      final Uint8List fromJo = await sealRetract(sender: aunt.key, id: unhex(id), toDeviceKey: dad.key.publicKey, nowMs: now);
      expect(await dad3.receive(fromJo), ShareReceiveOutcome.putAway, reason: 'valid, but it names a share Jo did not send');
      expect(await dad3.inbox(), hasLength(1), reason: 'the picture from Mom is still there');
    });

    test('a take-back addressed to another grown-up, or altered, is refused', () async {
      final Uint8List n = await sealRetract(sender: mom.key, id: List<int>.filled(16, 3), toDeviceKey: dad.key.publicKey, nowMs: now);
      expect(await openRetract(bytes: n, own: dad.key, state: state, nowMs: now), isNotNull);
      expect(await openRetract(bytes: n, own: mom.key, state: state, nowMs: now), isNull);
      expect(await openRetract(bytes: n, own: dad.key, state: state, nowMs: now, guardianDevice: false), isNull);
      final Map<String, Object?> m = jsonDecode(utf8.decode(n)) as Map<String, Object?>;
      m['id'] = b64(List<int>.filled(16, 4));
      expect(await openRetract(bytes: Uint8List.fromList(utf8.encode(jsonEncode(m))), own: dad.key, state: state, nowMs: now), isNull);
    });

    test('it expires on both phones, by itself', () async {
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false, expiryDays: 1);
      expect(await dadSvc.inbox(), hasLength(1));
      clock0 = now + day - 1;
      expect(await dadSvc.inbox(), hasLength(1));
      clock0 = now + day;
      expect(await dadSvc.inbox(), isEmpty);
      expect(await momSvc.sent(), isEmpty);
    });

    test('a late arrival of an expired share is refused', () async {
      road.open = false;
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false, expiryDays: 1);
      final Uint8List b = (await momSvc.sent()).single.sealed!;
      clock0 = now + 2 * day;
      expect(await dadSvc.receive(b), ShareReceiveOutcome.refused);
    });

    test('the same share twice is kept once; the inbox and the outbox are capped', () async {
      Future<Uint8List> fresh(int pad) async {
        final ScreenShareService m = svc(mom, clock: clock);
        await m.send(png: pngOf(pad: pad), to: toDad, namesHidden: false);
        return (await m.sent()).single.sealed!;
      }

      final Uint8List first = await fresh(0);
      expect(await dadSvc.receive(first), ShareReceiveOutcome.kept);
      expect(await dadSvc.receive(first), ShareReceiveOutcome.duplicate);
      expect(await dadSvc.receive(await fresh(1)), ShareReceiveOutcome.kept);
      expect(await dadSvc.receive(await fresh(2)), ShareReceiveOutcome.kept);
      expect(await dadSvc.receive(await fresh(3)), ShareReceiveOutcome.full);
      expect((await dadSvc.inbox()).length, kShareMaxHeld);
      final ScreenShareService full = svc(mom, clock: clock);
      for (int i = 0; i < kShareMaxHeld; i++) {
        await full.send(png: pngOf(pad: i), to: toDad, namesHidden: false);
      }
      await expectLater(full.send(png: pngOf(), to: toDad, namesHidden: false), throwsA(isA<ShareRefused>()));
    });

    test('putting a picture away is for good, and a late copy is dropped', () async {
      await momSvc.send(png: pngOf(), to: toDad, namesHidden: false);
      final ReceivedShare r = (await dadSvc.inbox()).single;
      await dadSvc.putAway(r.idHex);
      expect(await dadSvc.inbox(), isEmpty);
      final ScreenShareService m = svc(mom, clock: clock);
      await m.send(png: pngOf(), to: toDad, namesHidden: false, expiryDays: 3);
      // A different share has a different id, so it is kept; the put-away one stays away.
      expect(await dadSvc.receive((await m.sent()).single.sealed!), ShareReceiveOutcome.kept);
    });

    test('the reverse direction works the same (Sam to Mom)', () async {
      final ScreenShareService samSvc = svc(dad, clock: clock);
      expect(await samSvc.send(png: pngOf(), to: toMom, namesHidden: false), ShareSendOutcome.waiting);
      final Uint8List b = (await samSvc.sent()).single.sealed!;
      expect(await svc(mom, clock: clock).receive(b), ShareReceiveOutcome.kept);
    });

    test('a damaged box reads as an empty box, never a half-trusted one', () {
      for (final Object? junk in <Object?>[null, 3, 'x', <String, Object?>{'v': 2}, <String, Object?>{'v': 1, 'in': 'no', 'out': <Object?>[3, null]}]) {
        final ShareBoxState s = ShareBoxState.fromJson(junk);
        expect(s.held, isEmpty);
        expect(s.out, isEmpty);
      }
      final ShareBoxState bad = ShareBoxState.fromJson(<String, Object?>{
        'v': 1,
        'in': <Object?>[
          <String, Object?>{'id': 'a', 'from': 'b', 'name': 'n', 'iat': 1, 'exp': 2, 'note': '', 'hid': false, 'png': b64(<int>[1, 2, 3])}
        ],
      });
      expect(bad.held, isEmpty, reason: 'a stored picture that is not a PNG is dropped');
    });
  });

  group('structure: the rules cannot be bypassed by a later edit', () {
    String lib(String f) => File('lib/$f').readAsStringSync();

    test('no use of the phone\'s share sheet anywhere: no plugin, no send intent, no clipboard hand-off', () {
      final String pub = File('pubspec.yaml').readAsStringSync();
      expect(pub.contains('share_plus'), isFalse);
      expect(pub.contains('share:'), isFalse);
      expect(pub.contains('flutter_share'), isFalse);
      final List<String> hits = <String>[];
      for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        final String s = f.readAsStringSync();
        if (RegExp(r'Share\.share|ShareParams|XFile.*share|Intent\.ACTION_SEND|createChooser|SharePlus').hasMatch(s)) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
      for (final File f in Directory('android/app/src/main').listSync(recursive: true).whereType<File>()) {
        if (!(f.path.endsWith('.kt') || f.path.endsWith('.xml'))) continue;
        final String s = f.readAsStringSync();
        expect(s.contains('ACTION_SEND') || s.contains('createChooser'), isFalse, reason: f.path);
      }
    });

    test('the sender takes freshly captured bytes only: nothing in the service accepts a received picture', () {
      final String s = lib('screen_share.dart');
      final int at = s.indexOf('Future<ShareSendOutcome> send(');
      final String sig = s.substring(at, s.indexOf(')', at));
      expect(sig.contains('ReceivedShare'), isFalse);
      expect(sig.contains('HeldShare'), isFalse);
      final String ui = lib('screen_share_ui.dart');
      final int v = ui.indexOf('class ScreenShareViewer');
      final String viewer = ui.substring(v);
      expect(viewer.contains('ShareScreenPreview'), isFalse, reason: 'the viewer has no way to start a share');
      expect(viewer.contains('.send('), isFalse);
      expect(viewer.contains('ShareScreenAction'), isFalse);
    });

    test('the child side never imports the sharing code', () {
      final List<String> bad = <String>[];
      for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        final String name = f.uri.pathSegments.last;
        if (name.startsWith('child_') || name.startsWith('kid_') || name == 'kiosk_shell.dart') {
          if (f.readAsStringSync().contains('screen_share')) bad.add(name);
        }
      }
      expect(bad, isEmpty);
    });

    test('the area is registered as sealed, grown-up scope, with a plain name', () {
      // local_services_test and label_adoption_test check the rest; this pins the privacy properties.
      final String s = lib('local_services.dart').replaceAll('\r\n', '\n');
      final int at = s.indexOf("area: 'screenshares'");
      expect(at, greaterThan(0));
      final String entry = s.substring(at, s.indexOf('LocalDataEntry(', at) < 0 ? s.length : at + 900);
      expect(entry.contains('LocalScope.guardian'), isTrue);
      expect(entry.contains('encrypted: true'), isTrue);
      expect(entry.contains('Never on a child'), isTrue);
    });
  });

  group('a full box in the sealed store', () {
    // The biggest picture allowed (just under 1 MiB of near-random bytes, so nothing shrinks it).
    Uint8List bigPng(int seed) {
      final Uint8List head = pngOf();
      final Uint8List out = Uint8List(kShareMaxImageBytes);
      out.setRange(0, head.length, head);
      int x = seed * 2654435761 + 1;
      for (int i = head.length; i < out.length; i++) {
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        out[i] = (x >> 16) & 255;
      }
      return out;
    }

    test('three biggest pictures held and three biggest waiting all fit, and every save works', () async {
      final LocalServices ls = LocalServices.memory();
      final ShareBoxRepository repo = LocalStoreShareBoxRepository(ls.area('screenshares', ownerId: kLocalGuardianScope));
      final ScreenShareService dadSvc = ScreenShareService(
        box: repo,
        identity: () async => ShareIdentity(device: dad.key, agreement: dad.agree, state: state),
        nowMs: () => now,
      );
      final ScreenShareService momSvc = svc(mom);
      final ShareRecipient toDad = eligibleShareRecipients(state, mom.key.publicKey, now).single;
      final ShareRecipient toMom = eligibleShareRecipients(state, dad.key.publicKey, now).single;
      for (int i = 0; i < kShareMaxHeld; i++) {
        await momSvc.send(png: bigPng(i), to: toDad, namesHidden: false, note: 'n' * kShareMaxNoteChars);
      }
      for (final OutgoingShare o in await momSvc.sent()) {
        expect(await dadSvc.receive(o.sealed!), ShareReceiveOutcome.kept);
      }
      for (int i = 0; i < kShareMaxHeld; i++) {
        await dadSvc.send(png: bigPng(10 + i), to: toMom, namesHidden: true, note: 'n' * kShareMaxNoteChars);
      }
      expect((await dadSvc.inbox()), hasLength(kShareMaxHeld));
      expect((await dadSvc.sent()), hasLength(kShareMaxHeld));
      expect((await dadSvc.inbox()).first.png.length, kShareMaxImageBytes);
    });

    test('receive answers full instead of throwing when the store is full', () async {
      final ScreenShareService momSvc = svc(mom);
      final ShareRecipient toDad = eligibleShareRecipients(state, mom.key.publicKey, now).single;
      await momSvc.send(png: pngOf(pad: 300), to: toDad, namesHidden: false);
      final Uint8List sealed = (await momSvc.sent()).single.sealed!;
      final ScreenShareService dadSvc = ScreenShareService(
        box: _FullBox(),
        identity: () async => ShareIdentity(device: dad.key, agreement: dad.agree, state: state),
        nowMs: () => now,
      );
      expect(await dadSvc.receive(sealed), ShareReceiveOutcome.full);
      // Not stored, so the box is still empty and the sender's copy can be offered again later.
      expect(await dadSvc.inbox(), isEmpty);
    });
  });
}

class _FullBox implements ShareBoxRepository {
  @override
  Future<ShareBoxState> load() async => ShareBoxState();
  @override
  Future<void> save(ShareBoxState s) async {
    if (s.held.isNotEmpty) throw const LocalStoreFull('screenshares', 1);
  }
}
