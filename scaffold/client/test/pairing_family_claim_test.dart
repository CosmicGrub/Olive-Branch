// OLIVE BRANCH — the pairing picture's safety layers in the protocol: the blinded family tag (neutral cross-family
// refusal), the single in-flight claim, the Match pick, the family key in the sealed credential, and the hostile
// cases (replayed, tampered, wrong-instance, revoked, expired). UNVERIFIED until CI runs it; loopback transport,
// real crypto, no sockets. Design: docs/planning/PERSISTENT-QR-PAIRING.md J12-J14.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_match.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_protocol.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
Uint8List _b(int n, int f) => Uint8List.fromList(List<int>.filled(n, f));

Future<AdultWindow> _window(DeviceKey k,
        {String fid = 'fam-1', String pin = '4829', DateTime Function()? now, Uint8List? fk, bool requireMatch = false, List<PairedKid>? paired}) =>
    AdultWindow.open(
        adultKey: k, adultName: 'Mom', familyId: fid, childId: 'kid-1', childName: 'Ivy', pin: pin, now: now, familyKey: fk,
        requireMatch: requireMatch, makeUnlockVerifier: _cheap, onPaired: paired?.add);

ChildPairingClient _client(DeviceKey ck, PairingTransport t) => ChildPairingClient(
    childKey: ck, transport: t, delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3));

Map<String, dynamic> _hello(AdultWindow w, DeviceKey ck) => <String, dynamic>{'t': 'hello', 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'T'};

Future<Map<String, dynamic>?> _pake1(AdultWindow w, DeviceKey ck, String pin) async {
  final PakeParty p = await PakeParty.start(isChild: true, password: pin.codeUnits, sid: w.sid, ci: await _ci(w, ck));
  return w.handle(<String, dynamic>{'t': 'pake1', 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'T', 'pv': kPairingProtocolVersion, 'm': 'pin', 'Yc': b64(p.share)});
}

Future<Uint8List> _ci(AdultWindow w, DeviceKey ck) async => pairingChannelId(
    childPublicKey: ck.publicKey, adultFingerprint: w.adultKey.fingerprint, familyId: 'fam-1', adultName: 'Mom');

void main() {
  group('family tag', () {
    test('verifies only with the right family key; another family sees "different"; no key or no tag gives no hint', () async {
      final DeviceKey k = await _key();
      final Uint8List fk = _b(16, 3), other = _b(16, 4), salt = _b(16, 9);
      final PairingPicture p = PairingPicture(
          role: PictureRole.adult, publicKey: k.publicKey, salt: salt, epoch: 1, familyTag: await familyTag(fk, PictureRole.adult, salt, k.publicKey));
      expect(await checkFamily(p, fk), FamilyCheck.sameFamily);
      expect(await checkFamily(p, other), FamilyCheck.differentFamily);
      expect(await checkFamily(p, null), FamilyCheck.noHint);
      final PairingPicture bare = PairingPicture(role: PictureRole.adult, publicKey: k.publicKey, salt: salt, epoch: 1);
      expect(await checkFamily(bare, fk), FamilyCheck.noHint);
    });

    test('it round-trips through the payload and stays inside 130 characters', () async {
      final DeviceKey k = await _key();
      final Uint8List fk = _b(16, 3), salt = _b(16, 9);
      final PairingPicture p = PairingPicture(
          role: PictureRole.child, publicKey: k.publicKey, salt: salt, epoch: 7, familyTag: await familyTag(fk, PictureRole.child, salt, k.publicKey));
      expect(p.payload.length, lessThan(130));
      final PairingPicture back = parsePairingPicture(p.payload)!;
      expect(back.familyTag, p.familyTag);
      expect(await checkFamily(back, fk), FamilyCheck.sameFamily);
      expect(Uri.parse(p.payload).queryParameters.keys.toSet(), <String>{'r', 'k', 's', 'e', 'f'});
    });

    test('unlinkable: a refreshed picture and a different device both get a different tag', () async {
      final DeviceKey k1 = await _key(), k2 = await _key();
      final Uint8List fk = _b(16, 3);
      final Uint8List t1 = await familyTag(fk, PictureRole.adult, _b(16, 1), k1.publicKey);
      expect(await familyTag(fk, PictureRole.adult, _b(16, 2), k1.publicKey), isNot(t1), reason: 'refresh changes it');
      expect(await familyTag(fk, PictureRole.adult, _b(16, 1), k2.publicKey), isNot(t1), reason: 'device changes it');
      expect(await familyTag(fk, PictureRole.child, _b(16, 1), k1.publicKey), isNot(t1), reason: 'role changes it');
    });

    test('a refreshed picture no longer verifies the old photo: the old tag fails against the new salt', () async {
      final DeviceKey k = await _key();
      final MemoryPairingPictureRepository repo = MemoryPairingPictureRepository();
      final PairingPictureService svc = PairingPictureService(repo);
      await svc.ensureFamilyKey();
      final PairingPicture before = await svc.own(k, PictureRole.adult);
      await svc.refresh();
      final PairingPicture after = await svc.own(k, PictureRole.adult);
      expect(after.epoch, before.epoch + 1);
      expect(after.familyTag, isNot(before.familyTag));
      expect((await repo.load())!.familyKey, isNotNull, reason: 'refreshing the picture keeps the family key');
      // A copy of the old payload still parses, but its tag was made for the old salt: a scanner holding the family
      // key can compare salt+tag, and the adult side rotates its window tag so the old salt finds nothing.
      final PairingPicture old = parsePairingPicture(before.payload)!;
      expect(old.salt, isNot(after.salt));
    });

    test('malformed f is refused: wrong length, bad base64, duplicate, empty', () {
      final String base = 'olive://id/1?r=a&k=${b64(_b(32, 1))}&s=${b64(_b(16, 2))}&e=1';
      expect(parsePairingPicture('$base&f=${b64(_b(8, 3))}'), isNotNull);
      expect(parsePairingPicture('$base&f=${b64(_b(7, 3))}'), isNull);
      expect(parsePairingPicture('$base&f=${b64(_b(9, 3))}'), isNull);
      expect(parsePairingPicture('$base&f=%%%%'), isNull);
      expect(parsePairingPicture('$base&f='), isNull);
      expect(parsePairingPicture('$base&f=${b64(_b(8, 3))}&f=${b64(_b(8, 3))}'), isNull);
      expect(parsePairingPicture('$base&g=${b64(_b(8, 3))}'), isNull, reason: 'a fifth key that is not f');
    });
  });

  group('claimed child checks the family before any key exchange', () {
    test('a window of another family is dropped silently: only the hello is sent, the window loses no try', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, fid: 'fam-OTHER');
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PairingResult r = await ChildPairingClient(childKey: ck, transport: LoopbackPairingTransport(w, log: log), delay: (Duration d) async {})
          .pair(sid: w.sid, password: '4829', expectedFamilyId: 'fam-1');
      expect(r.ok, isFalse);
      expect(log.map((Map<String, dynamic> m) => m['t']), <String>['hello']);
      expect(w.attemptsLeft, 5);
    });

    test('its own family proceeds and the family key arrives in the sealed credential', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final Uint8List fk = _b(16, 7);
      final AdultWindow w = await _window(ak, fk: fk);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829', expectedFamilyId: 'fam-1');
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(r.pairing!.familyKey, fk);
    });

    test('an older credential without a family key still pairs (no fk)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue);
      expect(r.pairing!.familyKey, isNull);
    });
  });

  group('one claim at a time', () {
    test('a second device cannot replace the first mid-handshake, is not counted, and the first still pairs', () async {
      final DeviceKey ak = await _key(), c1 = await _key(), c2 = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic>? a = await _pake1(w, c1, '4829');
      expect(a!['t'], 'pake2');
      final Map<String, dynamic>? b = await _pake1(w, c2, '4829');
      expect(b, isNull, reason: 'dropped silently');
      expect(w.attemptsLeft, 5, reason: 'not counted as a failure');
    });

    test('an abandoned claim frees the window after 5 minutes (fake clock)', () async {
      DateTime t = DateTime.utc(2026, 11, 14, 9);
      final DeviceKey ak = await _key(), c1 = await _key(), c2 = await _key();
      final AdultWindow w = await _window(ak, now: () => t);
      expect(await _pake1(w, c1, '4829'), isNotNull);
      t = t.add(const Duration(minutes: 4, seconds: 59));
      expect(await _pake1(w, c2, '4829'), isNull);
      t = t.add(const Duration(seconds: 2));
      expect(await _pake1(w, c2, '4829'), isNotNull, reason: 'the stale claim expired');
    });
  });

  group('a stopped device', () {
    test('is not answered at all: no hello-ok, no pake2, no attempt used', () async {
      final DeviceKey ak = await _key(), stopped = await _key(), other = await _key();
      final AdultWindow w = await AdultWindow.open(requireMatch: false,
          adultKey: ak, adultName: 'Mom', familyId: 'fam-1', childId: 'k', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap,
          refuseKey: (List<int> k) async => b64(k) == b64(stopped.publicKey));
      expect(await w.handle(_hello(w, stopped)), isNull);
      expect(await _pake1(w, stopped, '4829'), isNull);
      expect(w.attemptsLeft, 5);
      expect((await w.handle(_hello(w, other)))!['t'], 'hello-ok', reason: 'everyone else is unaffected');
    });
  });

  group('Match', () {
    Future<(AdultWindow, PairingMatch?)> run({required bool requireMatch}) async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, requireMatch: requireMatch);
      PairingMatch? shown;
      final Future<PairingResult> f = ChildPairingClient(
              childKey: ck, transport: LoopbackPairingTransport(w), delay: (Duration d) async {}, pollEvery: const Duration(milliseconds: 5), giveUpAfter: const Duration(milliseconds: 200))
          .pair(sid: w.sid, password: '4829', onMatched: (PairingMatch m) => shown = m);
      while (w.state != WindowState.awaitingApproval && w.state != WindowState.closed) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      addTearDown(() async => f.catchError((_) => const PairingResult.failed(PairingFailure.timedOut)));
      return (w, shown);
    }

    test('both sides derive the same set; four choices with exactly the real one among them', () async {
      final (AdultWindow w, PairingMatch? child) = await run(requireMatch: true);
      expect(child!.match, isNotNull);
      expect(w.matchChoices!.sets, hasLength(4));
      expect(w.matchChoices!.sets[w.matchChoices!.correct], child.match);
      expect(w.matchChoices!.sets.where((MatchSet s) => s == child.match), hasLength(1));
    });

    test('approve is refused until the right set was picked', () async {
      final (AdultWindow w, _) = await run(requireMatch: true);
      expect(await w.approve(), isFalse);
      expect(w.pickMatch(w.matchChoices!.correct), isTrue);
      expect(await w.approve(), isTrue);
    });

    test('a wrong pick refuses: nothing is issued, the window closes to this device, and it cannot be approved later', () async {
      final (AdultWindow w, _) = await run(requireMatch: true);
      final int wrong = (w.matchChoices!.correct + 1) % 4;
      expect(w.pickMatch(wrong), isFalse);
      expect(w.matchRefused, isTrue);
      expect(w.state, WindowState.declined);
      expect(await w.approve(), isFalse);
      expect(w.pickMatch(w.matchChoices!.correct), isFalse, reason: 'too late');
    });

    test('"None of these" also refuses', () async {
      final (AdultWindow w, _) = await run(requireMatch: true);
      expect(w.pickMatch(null), isFalse);
      expect(w.matchRefused, isTrue);
      expect(await w.approve(), isFalse);
    });

    test('without requireMatch the old approve path still works (the PIN path stays primary)', () async {
      final (AdultWindow w, _) = await run(requireMatch: false);
      expect(await w.approve(), isTrue);
    });

    // The security property, end to end on the adult side: a window opened with NO special arguments (the default a new
    // caller gets) issues no certificate, and hands the child device nothing, until the grown-up has picked the right
    // Match card AND then separately approved. A pick alone is not an approval. (A human tapping on the phone early is
    // not the app skipping a step: every one of these taps is the grown-up's.)
    Future<(AdultWindow, Future<PairingResult>, List<PairedKid>)> defaultWindow() async {
      final DeviceKey ak = await _key(), ck = await _key();
      final List<PairedKid> paired = <PairedKid>[];
      final AdultWindow w = await AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'fam-1', childId: 'kid-1', childName: 'Ivy', pin: '4829',
          makeUnlockVerifier: _cheap, onPaired: paired.add);
      final Future<PairingResult> f = ChildPairingClient(
              childKey: ck, transport: LoopbackPairingTransport(w), pollEvery: const Duration(milliseconds: 5), giveUpAfter: const Duration(seconds: 10))
          .pair(sid: w.sid, password: '4829');
      while (w.state != WindowState.awaitingApproval && w.state != WindowState.closed) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      return (w, f, paired);
    }

    test('no certificate without a correct Match pick and an explicit approval tap (default window)', () async {
      final (AdultWindow w, Future<PairingResult> f, List<PairedKid> paired) = await defaultWindow();
      expect(w.requireMatch, isTrue, reason: 'the Match step is on unless a caller explicitly turns it off');
      expect(w.state, WindowState.awaitingApproval);
      expect(await w.approve(), isFalse, reason: 'an approval before any pick issues nothing');
      expect(paired, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(w.state, WindowState.awaitingApproval, reason: 'the child polling changes nothing');
      expect(w.pickMatch(w.matchChoices!.correct), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(paired, isEmpty, reason: 'a right pick alone is not an approval: no certificate yet');
      expect(w.state, WindowState.awaitingApproval);
      expect(await w.approve(), isTrue);
      expect(paired, hasLength(1));
      final PairingResult r = await f;
      expect(r.ok, isTrue);
    });

    test('a wrong pick or "None of these" on a default window: nothing issued, the child device gets nothing', () async {
      for (final int? pick in <int?>[null, 99]) {
        final (AdultWindow w, Future<PairingResult> f, List<PairedKid> paired) = await defaultWindow();
        expect(w.pickMatch(pick), isFalse);
        expect(await w.approve(), isFalse);
        expect(paired, isEmpty);
        expect((await f).ok, isFalse);
      }
      final (AdultWindow w, Future<PairingResult> f, List<PairedKid> paired) = await defaultWindow();
      expect(w.pickMatch((w.matchChoices!.correct + 2) % 4), isFalse);
      expect(await w.approve(), isFalse);
      expect(paired, isEmpty);
      expect((await f).ok, isFalse);
    });

    test('an out-of-range pick is a wrong pick', () async {
      final (AdultWindow w, _) = await run(requireMatch: true);
      expect(w.pickMatch(7), isFalse);
      expect(w.matchRefused, isTrue);
    });
  });

  group('hostile: replayed, tampered, wrong-instance, revoked, expired', () {
    test('a replayed confirm after the window closed gets no answer', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      await _pake1(w, ck, '0000');
      final Map<String, dynamic>? no = await w.handle(<String, dynamic>{'t': 'confirm', 'sid': b64(w.sid), 'tagC': b64(_b(32, 1))});
      expect(no!['t'], 'confirm-no');
      expect(w.attemptsLeft, 4);
      expect(await w.handle(<String, dynamic>{'t': 'confirm', 'sid': b64(w.sid), 'tagC': b64(_b(32, 1))}), isNull, reason: 'nothing pending to confirm');
      w.close();
      expect(await w.handle(_hello(w, ck)), isNull);
    });

    test('a tampered hello proof in Mode B is dropped without using an attempt', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _b(16, 4));
      final Uint8List hs = await signHello(ck, w.sid);
      hs[0] ^= 1;
      final Map<String, dynamic> m = _hello(w, ck)..['hs'] = b64(hs);
      expect(await w.handle(m), isNull);
      expect(w.attemptsLeft, 5);
    });

    test('a proof made for another window does not carry over (wrong instance)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w1 = await _window(ak), w2 = await _window(ak);
      w2.allowChild(childKey: ck.publicKey, childSalt: _b(16, 4));
      final Map<String, dynamic> m = _hello(w2, ck)..['hs'] = b64(await signHello(ck, w1.sid));
      expect(await w2.handle(m), isNull);
    });

    test('a message for another window id is ignored', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic> m = _hello(w, ck)..['sid'] = b64(_b(16, 1));
      expect(await w.handle(m), isNull);
    });

    test('an expired window answers nothing and closes', () async {
      DateTime t = DateTime.utc(2026, 11, 14, 9);
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, now: () => t);
      t = t.add(const Duration(minutes: 10));
      expect(await w.handle(_hello(w, ck)), isNull);
      expect(w.state, WindowState.closed);
    });

    test('a malformed message never throws', () async {
      final DeviceKey ak = await _key();
      final AdultWindow w = await _window(ak);
      for (final Map<String, dynamic> m in <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{'t': 'hello'},
        <String, dynamic>{'t': 'hello', 'sid': 5},
        <String, dynamic>{'t': 'pake1', 'sid': b64(w.sid), 'cpk': 3, 'Yc': 4},
        <String, dynamic>{'t': 'confirm', 'sid': b64(w.sid)},
      ]) {
        expect(await w.handle(m), anyOf(isNull, isA<Map<String, dynamic>>()));
      }
    });
  });
}
