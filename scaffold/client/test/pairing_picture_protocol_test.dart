// OLIVE BRANCH — the pairing picture inside the pairing protocol: Mode A (adult picture pinned by the child), Mode B
// (child picture scanned by the adult, with the hello proof of possession), the recognition tag, and the hostile
// cases: replayed, tampered, wrong-instance, refreshed and expired. UNVERIFIED until CI runs it; no sockets
// (loopback transport). The PIN stays the PAKE password in every mode. Design: docs/planning/PERSISTENT-QR-PAIRING.md.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart' show pairingSeatLabel, pairingTxt;
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_protocol.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
Uint8List _salt(int f) => Uint8List.fromList(List<int>.filled(16, f));

Future<AdultWindow> _window(DeviceKey k, {String name = 'Mom', String fid = 'fam-1', String pin = '4829', DateTime Function()? now, List<PairedKid>? paired}) =>
    AdultWindow.open(adultKey: k, adultName: name, familyId: fid, childId: 'kid-1', childName: 'Ivy', pin: pin, now: now, makeUnlockVerifier: _cheap, onPaired: paired?.add);

ChildPairingClient _client(DeviceKey ck, PairingTransport t) => ChildPairingClient(
    childKey: ck, transport: t, delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3));

void _autoApprove(AdultWindow w) => w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });

void main() {
  group('Mode A: the child pinned the adult picture', () {
    test('right picture and right PIN pair once; the picture alone gains nothing', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final PairingPicture pic = PairingPicture(role: PictureRole.adult, publicKey: ak.publicKey, salt: _salt(1), epoch: 0);
      final List<PairedKid> paired = <PairedKid>[];
      final AdultWindow w = await _window(ak, paired: paired);
      w.showAdultPicture(pic.salt);
      _autoApprove(w);
      // With the picture but a wrong PIN: the window counts it, nothing pairs.
      final PairingResult bad = await _client(ck, LoopbackPairingTransport(w))
          .pair(sid: w.sid, password: '0000', expectedAdultFingerprint: await pic.fingerprint());
      expect(bad.ok, isFalse);
      expect(w.attemptsLeft, 4);
      expect(paired, isEmpty);
      final PairingResult good = await _client(ck, LoopbackPairingTransport(w))
          .pair(sid: w.sid, password: '4829', expectedAdultFingerprint: await pic.fingerprint());
      expect(good.ok, isTrue, reason: '${good.failure}');
      expect(paired, hasLength(1));
    });

    test('a wrong-adult picture aborts BEFORE any key-exchange message and costs the adult zero attempts', () async {
      final DeviceKey ak = await _key(), rogue = await _key(), ck = await _key();
      final AdultWindow w = await _window(rogue, name: 'Mom'); // a rogue/other adult with the same name and PIN
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w, log: log))
          .pair(sid: w.sid, password: '4829', expectedAdultFingerprint: ak.fingerprint);
      expect(r.ok, isFalse);
      expect(r.failure, PairingFailure.notMatched);
      expect(log.map((Map<String, dynamic> m) => m['t']), <String>['hello'], reason: 'nothing but the hello was sent');
      expect(w.attemptsLeft, 5);
    });

    test('two families with the same PIN: the pinned key keeps the child on its own adult', () async {
      final DeviceKey a1 = await _key(), a2 = await _key(), ck = await _key();
      final AdultWindow w1 = await _window(a1, fid: 'fam-1'), w2 = await _window(a2, fid: 'fam-2');
      _autoApprove(w1);
      _autoApprove(w2);
      final Uint8List fp1 = a1.fingerprint;
      expect((await _client(ck, LoopbackPairingTransport(w2)).pair(sid: w2.sid, password: '4829', expectedAdultFingerprint: fp1)).ok, isFalse);
      expect(w2.attemptsLeft, 5);
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w1)).pair(sid: w1.sid, password: '4829', expectedAdultFingerprint: fp1);
      expect(r.ok, isTrue);
      expect(r.pairing!.cert.familyId, 'fam-1');
    });

    test('a picture of the adult copied from an old session finds no window once the adult refreshed', () async {
      final DeviceKey ak = await _key();
      final AdultWindow w = await _window(ak);
      final Uint8List oldSalt = _salt(1), newSalt = _salt(2);
      w.showAdultPicture(newSalt); // the adult refreshed; this window is addressed to the new salt
      final Uint8List advertised = await w.windowTag();
      expect(await tagMatches(newSalt, w.discoveryHandle, advertised), isTrue);
      expect(await tagMatches(oldSalt, w.discoveryHandle, advertised), isFalse, reason: 'the old photo recognises nothing');
    });
  });

  group('Mode B: the adult scanned the child picture', () {
    test('only the scanned child, with its proof, can reach the PIN; then PIN, SAS and approval run as always', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final List<PairedKid> paired = <PairedKid>[];
      final AdultWindow w = await _window(ak, paired: paired);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      _autoApprove(w);
      PairingMatch? seen;
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829', onMatched: (PairingMatch m) => seen = m);
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(seen!.sas.toString(), w.sas.toString());
      expect(paired.single.childDeviceKey, ck.publicKey);
    });

    test('another device is dropped silently and burns no attempt, however many times it tries', () async {
      final DeviceKey ak = await _key(), ck = await _key(), attacker = await _key();
      final AdultWindow w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      for (int i = 0; i < 40; i++) {
        final PairingResult r = await _client(attacker, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '0000');
        expect(r.ok, isFalse);
      }
      expect(w.attemptsLeft, 5);
      expect(w.isOpen, isTrue, reason: 'a flood from a stranger does not kill the window');
    });

    test('an attacker holding only the PHOTOGRAPHED child key (no private key) cannot get a hello answered or a pake1 counted', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final LoopbackPairingTransport t = LoopbackPairingTransport(w);
      // hello with the right public key but no signature, and with a garbage signature
      expect(await t.send(<String, dynamic>{'t': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x'}), isNull);
      expect(await t.send(<String, dynamic>{'t': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'hs': b64(Uint8List(64))}), isNull);
      // pake1 straight away, skipping hello, 30 times: the budget must not move
      for (int i = 0; i < 30; i++) {
        expect(await t.send(<String, dynamic>{'t': 'pake1', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'm': 'pin', 'Yc': b64(Uint8List(32))}), isNull);
      }
      expect(w.attemptsLeft, 5);
      // and a real pairing still works afterwards, so the flood did not use up the 20-pake1 cap either
      _autoApprove(w);
      expect((await _client(ck, t).pair(sid: w.sid, password: '4829')).ok, isTrue);
    });

    test('a hello signature captured from ANOTHER window does not work here (replay across windows)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow other = await _window(ak), w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final Uint8List hsForOther = await signHello(ck, other.sid);
      final Map<String, dynamic> replay = <String, dynamic>{
        't': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'hs': b64(hsForOther),
      };
      expect(await LoopbackPairingTransport(w).send(replay), isNull);
    });

    test('found by the advertised handle (no session id known): the scanned child still pairs; a proof made for another id or window is refused', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak), other = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final LoopbackPairingTransport t = LoopbackPairingTransport(w);
      Future<Map<String, dynamic>> byHandle(AdultWindow to, Uint8List signedOver) async => <String, dynamic>{
            't': 'hello', 'pv': 2, 'h': b64(to.discoveryHandle), 'cpk': b64(ck.publicKey), 'dn': 'x', 'hs': b64(await signHello(ck, signedOver)),
          };
      // The child signs over the handle it addressed the window by; a proof over the session id, or over another
      // window's handle, is not what a handle-addressed hello carries.
      expect(await t.send(await byHandle(w, w.sid)), isNull);
      expect(await t.send(await byHandle(w, other.discoveryHandle)), isNull);
      expect(await t.send(await byHandle(w, w.discoveryHandle)), isNotNull);
      _autoApprove(w);
      expect((await _client(ck, t).pair(handle: w.discoveryHandle, password: '4829')).ok, isTrue);
    });

    test('a tampered cpk or a signature over a different key is refused', () async {
      final DeviceKey ak = await _key(), ck = await _key(), other = await _key();
      final AdultWindow w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final LoopbackPairingTransport t = LoopbackPairingTransport(w);
      // the other device signs for itself but presents the scanned key
      expect(await t.send(<String, dynamic>{'t': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'hs': b64(await signHello(other, w.sid))}), isNull);
      // presenting its own key with its own valid signature: valid proof, but not the scanned device
      expect(await t.send(<String, dynamic>{'t': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(other.publicKey), 'hs': b64(await signHello(other, w.sid))}), isNull);
      // a hello whose cpk field is not even a string
      expect(await t.send(<String, dynamic>{'t': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': 5, 'hs': 7}), isNull);
    });

    test('the right child but a wrong PIN counts normally, on the adult device only', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      expect((await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '1111')).ok, isFalse);
      expect(w.attemptsLeft, 4);
    });

    test('the window is addressed to the child salt (preferred over the adult salt); a refreshed child picture is invisible to it', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.showAdultPicture(_salt(1));
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final Uint8List tag = await w.windowTag();
      expect(await tagMatches(_salt(3), w.discoveryHandle, tag), isTrue);
      expect(await tagMatches(_salt(1), w.discoveryHandle, tag), isFalse);
      expect(await tagMatches(_salt(4), w.discoveryHandle, tag), isFalse, reason: 'the child refreshed its picture; the old copy the adult scanned no longer matches the child');
    });

    test('a closed or expired window answers nothing, picture or not (no replay)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      DateTime now = DateTime(2026, 11, 14, 12);
      final AdultWindow w = await _window(ak, now: () => now);
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      final Map<String, dynamic> hello = <String, dynamic>{
        't': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'hs': b64(await signHello(ck, w.sid)),
      };
      expect(await w.handle(hello), isNotNull);
      now = now.add(const Duration(minutes: 11));
      expect(await w.handle(hello), isNull, reason: 'expired');
      expect(w.isOpen, isFalse);
      expect(w.allowedChildKey, isNull, reason: 'the scanned key is forgotten with the window');
      expect(await w.handle(hello), isNull, reason: 'a replay after close');
    });

    test('allowChild is ignored once the window is no longer open', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak)..close();
      w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
      expect(w.allowedChildKey, isNull);
    });
  });

  group('nothing identifying is advertised', () {
    test('the TXT record is exactly v, h and t, and no name, key, fingerprint, address or session id is in it', () async {
      final DeviceKey ak = await _key();
      final AdultWindow w = await _window(ak, name: 'Dana Whitfield');
      final Map<String, String> txt = pairingTxt(w.discoveryHandle, await w.windowTag());
      expect(txt.keys.toSet(), <String>{'v', 'h', 't'});
      expect(txt['v'], '1');
      final String all = '${txt.values.join(' ')} ${pairingSeatLabel(w.discoveryHandle)}';
      expect(all, isNot(contains('Dana')));
      expect(all, isNot(contains(b64(w.sid))), reason: 'the session id is not advertised in any form');
      expect(all, isNot(contains(b64(ak.publicKey))));
      expect(all, isNot(contains(b64(ak.fingerprint))));
      expect(<String>['Player one', 'Player two'], contains(pairingSeatLabel(w.discoveryHandle)));
    });

    test('with no picture the tag is random per window and stable within one; with a picture it is the HMAC', () async {
      final DeviceKey ak = await _key();
      final AdultWindow a = await _window(ak), b = await _window(ak);
      expect(await a.windowTag(), await a.windowTag());
      expect(await a.windowTag(), isNot(await b.windowTag()));
      expect(a.hasPicture, isFalse);
      a.showAdultPicture(_salt(1));
      expect(a.hasPicture, isTrue);
      expect(await a.windowTag(), await rendezvousTag(_salt(1), a.discoveryHandle));
      expect(await a.windowTag(), isNot(await rendezvousTag(_salt(1), a.sid)), reason: 'the tag is not keyed on the session id');
    });
  });
}
