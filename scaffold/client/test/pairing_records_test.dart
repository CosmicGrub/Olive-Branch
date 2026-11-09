// OLIVE BRANCH — what each side keeps after an on-device pairing, and the child device's unlock verifier.
// Verified by CI, headless.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';

void main() {
  test('device key: created once, kept, and the same key comes back', () async {
    final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
    final LocalStoreDeviceKeyRepository repo = LocalStoreDeviceKeyRepository(s.area('devicekey'));
    final DeviceKey a = await DeviceKey.loadOrCreate(repo);
    final DeviceKey b = await DeviceKey.loadOrCreate(repo);
    expect(b.publicKey, a.publicKey);
    expect(s.area('devicekey').spec.encrypted, isTrue);
  });

  test('a child pairing survives a restart, carries the unlock verifier, and a tampered one is "not paired"', () async {
    final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
    ChildPairingRepository repo() => LocalStoreChildPairingRepository(
        s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock')));
    final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final PairingCert cert = await PairingCert.issue(ak,
        childDeviceKey: ck.publicKey, familyId: 'fam', childId: 'kid', certId: 'x', issuedAtMs: 1);
    // The verifier for PIN 4829 with 5 rounds, made the way the adult device makes it.
    final Uint8List salt = Uint8List.fromList(List<int>.filled(16, 7));
    final SecretKey k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 5, bits: 256)
        .deriveKeyFromPassword(password: '4829', nonce: salt);
    final LocalPinRecord rec = LocalPinRecord(iterations: 5, salt: salt, hash: Uint8List.fromList(await k.extractBytes()));
    await repo().save(ChildPairing(cert: cert, adultKey: ak.publicKey, adultName: 'Mom', childName: 'Ivy', unlockVerifier: rec));
    final ChildPairing? back = await repo().load();
    expect(back!.adultName, 'Mom');
    expect(back.cert.childId, 'kid');
    // The child device's adult-gate check: right PIN passes, wrong fails, 5 wrong lock it.
    final LocalPinService unlock = LocalPinService(LocalStoreLocalPinRepository(s.area('adultunlock')));
    expect(await unlock.verifyBool('4829'), isTrue);
    expect(await unlock.verifyBool('0000'), isFalse);
    for (int i = 0; i < 4; i++) {
      await unlock.verifyBool('1111');
    }
    expect((await unlock.verify('4829')).outcome, PinOutcome.locked);

    // A stored certificate that does not verify under the stored adult key is not a pairing.
    final DeviceKey other = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    await s.area('childpairing').put('pairing', <String, Object?>{
      'cert': cert.toJson(), 'apk': b64(other.publicKey), 'an': 'Mom', 'cn': 'Ivy',
    });
    expect(await repo().load(), isNull);
  });

  test('paired kids: add, list, forget', () async {
    final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
    final LocalStorePairedKidsRepository r = LocalStorePairedKidsRepository(s.area('pairedkids', ownerId: kLocalGuardianScope));
    await r.add(PairedKid(certId: 'a', childDeviceKey: Uint8List(32), childId: 'kid', deviceName: 'Tablet', issuedAtMs: 5));
    await r.add(PairedKid(certId: 'b', childDeviceKey: Uint8List(32), childId: 'kid', deviceName: 'Phone', issuedAtMs: 6));
    expect((await r.load()).map((PairedKid k) => k.certId), <String>['a', 'b']);
    await r.forget('a');
    expect((await r.load()).single.certId, 'b');
  });
}
