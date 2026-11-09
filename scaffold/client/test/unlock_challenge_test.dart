// OLIVE BRANCH — "use my phone to unlock": fresh signed challenge-response, replay, phone-only, forget.
// Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/unlock_challenge.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

class _Rig {
  _Rig(this.ak, this.ck, this.kid, this.now);
  final DeviceKey ak, ck;
  final PairedKid kid;
  DateTime Function() now;
}

Future<_Rig> _rig({bool phoneOnly = false}) async {
  final DeviceKey ak = await _key(), ck = await _key();
  final PairedKid kid = PairedKid(
      certId: 'c1', childDeviceKey: ck.publicKey, childId: 'kid', deviceName: 'Tablet', issuedAtMs: 1, phoneOnly: phoneOnly);
  return _Rig(ak, ck, kid, () => DateTime(2026, 11, 8, 10));
}

void main() {
  test('the happy path: the tablet issues, the phone answers after inspecting, the tablet accepts once', () async {
    final _Rig r = await _rig();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final ChallengeView? v = await phone.inspect(c.toQr());
    expect(v, isNotNull);
    expect(v!.kid.deviceName, 'Tablet');
    final String grant = await phone.grant(v);
    expect(grant, isNot(contains('4829')));
    expect(await host.accept(grant), isTrue);
    // Replay of the very same answer: the challenge was consumed.
    expect(await host.accept(grant), isFalse);
  });

  test('a photographed challenge or answer is useless: a new challenge needs a new answer', () async {
    final _Rig r = await _rig();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    final UnlockChallenge first = host.issue(UnlockPurpose.unlock);
    final String oldGrant = await phone.grant((await phone.inspect(first.toQr()))!);
    host.issue(UnlockPurpose.unlock); // the tablet moved on
    expect(await host.accept(oldGrant), isFalse);
  });

  test('an expired challenge is refused by the phone and by the tablet', () async {
    final _Rig r = await _rig();
    DateTime t = DateTime(2026, 11, 8, 10);
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => t);
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => t);
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final String grant = await phone.grant((await phone.inspect(c.toQr()))!);
    t = t.add(const Duration(minutes: 3));
    expect(await host.accept(grant), isFalse, reason: 'tablet: expired');
    expect(await phone.inspect(c.toQr()), isNull, reason: 'phone: expired');
  });

  test('a phone that did not connect this tablet, or has forgotten it, will not answer', () async {
    final _Rig r = await _rig();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final String qr = host.issue(UnlockPurpose.unlock).toQr();
    final UnlockResponder stranger = UnlockResponder(adultKey: await _key(), kids: () async => <PairedKid>[], now: () => r.now());
    expect(await stranger.inspect(qr), isNull);
    final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
    await kids.add(r.kid);
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: kids.load, now: () => r.now());
    expect(await phone.inspect(qr), isNotNull);
    await kids.forget('c1');
    expect(await phone.inspect(qr), isNull, reason: 'forgotten: no more answers for that tablet');
  });

  test('an answer signed by another adult key, or for another tablet, is refused', () async {
    final _Rig r = await _rig();
    final DeviceKey rogue = await _key(), otherTablet = await _key();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final UnlockResponder rogueP = UnlockResponder(
        adultKey: rogue, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    expect(await host.accept(await rogueP.grant((await rogueP.inspect(c.toQr()))!)), isFalse);
    // A challenge from a different tablet names a different fingerprint and is not this tablet's.
    final ChildUnlockHost host2 = ChildUnlockHost(childKey: otherTablet, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    expect(await phone.inspect(host2.issue(UnlockPurpose.unlock).toQr()), isNull);
  });

  test('a failed signature still consumes the challenge (no retry oracle)', () async {
    final _Rig r = await _rig();
    final DeviceKey rogue = await _key();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final UnlockResponder good = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    final String goodGrant = await good.grant((await good.inspect(c.toQr()))!);
    final String badGrant = await UnlockResponder(adultKey: rogue, kids: () async => <PairedKid>[r.kid], now: () => r.now())
        .grant((await good.inspect(c.toQr()))!);
    expect(await host.accept(badGrant), isFalse);
    expect(await host.accept(goodGrant), isFalse, reason: 'the nonce is spent');
  });

  test('tampering with the purpose in the answer or the challenge does not unlock', () async {
    final _Rig r = await _rig();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final UnlockChallenge asForget = UnlockChallenge(
        nonce: c.nonce, childFingerprint: c.childFingerprint, purpose: UnlockPurpose.forget, expiresMs: c.expiresMs);
    // The phone was shown a "forget" version of the tablet's challenge; its answer is for forget, not unlock.
    final String grant = await phone.grant((await phone.inspect(asForget.toQr()))!);
    expect(await host.accept(grant), isFalse);
  });

  test('malformed input is refused, never thrown', () async {
    final _Rig r = await _rig();
    final ChildUnlockHost host = ChildUnlockHost(childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now());
    host.issue(UnlockPurpose.unlock);
    for (final String junk in <String>['', 'olive://grant/1', 'olive://grant/1?n=%%%', 'https://x', 'olive://unlock/1?n=a']) {
      expect(await host.accept(junk), isFalse);
    }
    expect(UnlockChallenge.parse('nonsense'), isNull);
  });

  test('phone-only: the flag rides the signed answer, the tablet acts on it; forget clears the pairing', () async {
    final _Rig r = await _rig(phoneOnly: true);
    bool po = false, forgot = false;
    final ChildUnlockHost host = ChildUnlockHost(
        childKey: r.ck, adultKey: r.ak.publicKey, now: () => r.now(),
        onPhoneOnly: () async => po = true, onForget: () async => forgot = true);
    final UnlockResponder phone = UnlockResponder(adultKey: r.ak, kids: () async => <PairedKid>[r.kid], now: () => r.now());
    expect(await host.accept(await phone.grant((await phone.inspect(host.issue(UnlockPurpose.unlock).toQr()))!)), isTrue);
    expect(po, isTrue);
    expect(forgot, isFalse);
    expect(await host.accept(await phone.grant((await phone.inspect(host.issue(UnlockPurpose.forget).toQr()))!)), isTrue);
    expect(forgot, isTrue);
  });

  test('pairing with phone-only gives the tablet NO PIN verifier at all', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final List<PairedKid> paired = <PairedKid>[];
    final AdultWindow w = await AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'k', childName: 'Ivy', pin: '4829',
        phoneOnly: true, makeUnlockVerifier: _cheap, onPaired: paired.add);
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final PairingResult res = await ChildPairingClient(
            childKey: ck, transport: LoopbackPairingTransport(w), delay: (Duration d) async {})
        .pair(sid: w.sid, password: '4829');
    expect(res.ok, isTrue, reason: '${res.failure}');
    expect(res.pairing!.unlockVerifier, isNull);
    expect(res.pairing!.phoneOnly, isTrue);
    expect(paired.single.phoneOnly, isTrue);
  });

  test('a tablet that goes phone-only later deletes its verifier and keeps the pairing', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final PairingCert cert = await PairingCert.issue(ak,
        childDeviceKey: ck.publicKey, familyId: 'f', childId: 'k', certId: 'x', issuedAtMs: 1);
    final MemoryLocalPinRepository pinRepo = MemoryLocalPinRepository();
    await pinRepo.save(LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32)));
    final LocalStoreChildPairingRepository repo = LocalStoreChildPairingRepository(
        LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1').area('childpairing'), pinRepo);
    await repo.save(ChildPairing(
        cert: cert, adultKey: ak.publicKey, adultName: 'Mom', childName: 'Ivy', unlockVerifier: await pinRepo.load()));
    expect((await repo.load())!.phoneOnly, isFalse);
    await repo.makePhoneOnly();
    final ChildPairing? after = await repo.load();
    expect(after, isNotNull);
    expect(after!.phoneOnly, isTrue);
    expect(await pinRepo.load(), isNull);
  });

  test('paired kids: phone-only is kept and forget removes', () async {
    final MemoryPairedKidsRepository r = MemoryPairedKidsRepository();
    await r.add(PairedKid(certId: 'a', childDeviceKey: Uint8List(32), childId: 'k', deviceName: 'T', issuedAtMs: 1));
    await r.setPhoneOnly('a', true);
    expect((await r.load()).single.phoneOnly, isTrue);
    await r.forget('a');
    expect(await r.load(), isEmpty);
  });
}
