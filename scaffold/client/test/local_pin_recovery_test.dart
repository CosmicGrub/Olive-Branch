// OLIVE BRANCH — recovering a forgotten local guardian PIN from a second grown-up's phone: linking, the one-time
// challenge, replay, expiry, strangers, tampering. Verified by CI, headless. MASTERFILE section 7.12.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin_recovery.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

class _Rig {
  _Rig(this.a, this.b, this.ar, this.br, this.now);
  final DeviceKey a, b; // a forgot; b helps
  final MemoryGuardianPeerRepository ar, br;
  DateTime now;
  DateTime clock() => now;
}

Future<_Rig> _rig({bool link = true}) async {
  final DeviceKey a = await _key(), b = await _key();
  final _Rig r = _Rig(a, b, MemoryGuardianPeerRepository(), MemoryGuardianPeerRepository(), DateTime(2026, 11, 13, 9));
  if (link) {
    final GuardianLinker la = GuardianLinker(key: a, repo: r.ar, now: r.clock), lb = GuardianLinker(key: b, repo: r.br, now: r.clock);
    expect(await la.accept(await lb.offer('Dad phone')), LinkResult.linked);
    expect(await lb.accept(await la.offer('Mum phone')), LinkResult.linked);
  }
  return r;
}

void main() {
  test('linking stores the other phone, by name, once; a phone cannot link itself', () async {
    final _Rig r = await _rig();
    final GuardianLinker la = GuardianLinker(key: r.a, repo: r.ar, now: r.clock);
    final List<GuardianPeer> peers = await la.peers();
    expect(peers, hasLength(1));
    expect(peers.single.label, 'Dad phone');
    expect(peers.single.publicKey, r.b.publicKey);
    expect(await la.accept(await GuardianLinker(key: r.b, repo: r.br).offer('Dad phone')), LinkResult.alreadyLinked);
    expect(await la.accept(await la.offer('me')), LinkResult.ownKey);
  });

  test('a link picture must be signed by the key it carries (no pasting someone else key under your name)', () async {
    final _Rig r = await _rig(link: false);
    final GuardianLinker la = GuardianLinker(key: r.a, repo: r.ar, now: r.clock);
    final String good = await GuardianLinker(key: r.b, repo: r.br).offer('Dad');
    expect(await la.accept(good.replaceFirst('l=Dad', 'l=Mallory')), LinkResult.notAnOffer, reason: 'label changed after signing');
    final DeviceKey c = await _key();
    final Uri g = Uri.parse(good);
    final Uri forged = Uri(
        scheme: 'olive',
        host: 'guardian-link',
        path: '/1',
        queryParameters: <String, String>{'k': b64(c.publicKey), 'l': 'Dad', 's': g.queryParameters['s']!});
    expect(await la.accept(forged.toString()), LinkResult.notAnOffer, reason: 'signature is by a different key');
    expect(await la.accept('olive://guardian-link/1?k=zz'), LinkResult.notAnOffer);
    expect(await la.accept('hello'), LinkResult.notAnOffer);
    expect(await la.peers(), isEmpty);
  });

  test('the number of linked phones is capped, and a phone can be removed', () async {
    final _Rig r = await _rig(link: false);
    final GuardianLinker la = GuardianLinker(key: r.a, repo: r.ar, now: r.clock);
    for (int i = 0; i < kMaxGuardianPeers; i++) {
      expect(await la.accept(await GuardianLinker(key: await _key(), repo: MemoryGuardianPeerRepository()).offer('P$i')),
          LinkResult.linked);
    }
    expect(await la.accept(await GuardianLinker(key: await _key(), repo: MemoryGuardianPeerRepository()).offer('extra')),
        LinkResult.full);
    await la.remove(0);
    expect(await la.peers(), hasLength(kMaxGuardianPeers - 1));
    await la.remove(99); // out of range: nothing happens
    expect(await la.peers(), hasLength(kMaxGuardianPeers - 1));
  });

  test('happy path: the forgetful phone challenges, the helper answers after inspecting, the forgetful phone accepts once', () async {
    final _Rig r = await _rig();
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    final PinResetHelper help = PinResetHelper(key: r.b, repo: r.br, now: r.clock);
    final PinResetChallenge c = (await req.issue())!;
    final PinResetView? v = await help.inspect(c.toQr());
    expect(v, isNotNull);
    expect(v!.peer.label, 'Mum phone');
    final String grant = await help.grant(v);
    expect(await req.accept(grant), isTrue);
    expect(await req.accept(grant), isFalse, reason: 'single use');
  });

  test('no linked phone: nothing to ask, no challenge is ever issued', () async {
    final _Rig r = await _rig(link: false);
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    expect(await req.canAsk(), isFalse);
    expect(await req.issue(), isNull);
    expect(await req.accept('olive://pin-reset-ok/1?n=AAAA&h=BBBB&s=CCCC'), isFalse);
    expect(kNoRecoveryWords, contains('only way'));
    expect(kNoRecoveryWords, contains('erases the family'));
  });

  test('a stranger phone (never linked) cannot see a challenge as one for it, and a forged answer is refused', () async {
    final _Rig r = await _rig();
    final DeviceKey stranger = await _key();
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    final PinResetChallenge c = (await req.issue())!;
    final PinResetHelper strangerHelp = PinResetHelper(key: stranger, repo: MemoryGuardianPeerRepository(), now: r.clock);
    expect(await strangerHelp.inspect(c.toQr()), isNull, reason: 'the stranger was never linked to the requester');
    // A stranger who WAS linked to someone else signs anyway: the requester does not know that key.
    final GuardianPeer asA = GuardianPeer(publicKey: r.a.publicKey, label: 'x', linkedAtMs: 1);
    final MemoryGuardianPeerRepository sr = MemoryGuardianPeerRepository();
    await sr.save(<GuardianPeer>[asA]);
    final String forged = await PinResetHelper(key: stranger, repo: sr, now: r.clock).grant(PinResetView(c, asA));
    expect(await req.accept(forged), isFalse);
  });

  test('a signature over different fields (another nonce) does not verify, and a wrong answer spends the challenge', () async {
    final _Rig r = await _rig();
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    final PinResetHelper help = PinResetHelper(key: r.b, repo: r.br, now: r.clock);
    final PinResetChallenge first = (await req.issue())!;
    final String oldGrant = await help.grant((await help.inspect(first.toQr()))!);
    final PinResetChallenge second = (await req.issue())!; // the phone moved on
    expect(await req.accept(oldGrant), isFalse, reason: 'old answer names a spent challenge');
    // Tamper: keep the second nonce, swap in the first answer's signature.
    final Uri g = Uri.parse(oldGrant);
    final Uri tampered = Uri(
        scheme: 'olive',
        host: 'pin-reset-ok',
        path: '/1',
        queryParameters: <String, String>{'n': b64(second.nonce), 'h': g.queryParameters['h']!, 's': g.queryParameters['s']!});
    expect(await req.accept(tampered.toString()), isFalse);
    // The tampered try spent the second challenge: even the genuine answer to it is now refused (one try per picture).
    final String genuine = await help.grant((await help.inspect(second.toQr()))!);
    expect(await req.accept(genuine), isFalse);
  });

  test('an expired challenge is refused by the helper and by the requester', () async {
    final _Rig r = await _rig();
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    final PinResetHelper help = PinResetHelper(key: r.b, repo: r.br, now: r.clock);
    final PinResetChallenge c = (await req.issue())!;
    final PinResetView v = (await help.inspect(c.toQr()))!;
    final String grant = await help.grant(v);
    r.now = r.now.add(kPinResetTtl + const Duration(seconds: 1));
    expect(await help.inspect(c.toQr()), isNull);
    expect(await req.accept(grant), isFalse);
  });

  test('removing the link on the forgetful phone makes the helper answer worthless', () async {
    final _Rig r = await _rig();
    final PinResetRequester req = PinResetRequester(key: r.a, repo: r.ar, now: r.clock);
    final PinResetHelper help = PinResetHelper(key: r.b, repo: r.br, now: r.clock);
    final PinResetChallenge c = (await req.issue())!;
    final String grant = await help.grant((await help.inspect(c.toQr()))!);
    await GuardianLinker(key: r.a, repo: r.ar).remove(0);
    expect(await req.accept(grant), isFalse);
  });

  test('malformed pictures are refused without throwing', () async {
    final _Rig r = await _rig();
    final PinResetHelper help = PinResetHelper(key: r.b, repo: r.br, now: r.clock);
    for (final String junk in <String>[
      '',
      'olive://pin-reset/1',
      'olive://pin-reset/1?n=AA&c=BB&e=1',
      'https://x.test/',
      'olive://pin-reset/1?n=!!&c=!!&e=x',
    ]) {
      expect(await help.inspect(junk), isNull, reason: junk);
    }
    expect(PinResetChallenge.parse('olive://pin-reset/2?n=AAAAAAAAAAAAAAAAAAAAAA&c=AAAAAAAAAAAAAAAAAAAAAA&e=1'), isNull);
  });

  test('the peer record survives a round trip and damaged entries are ignored', () async {
    final GuardianPeer p = GuardianPeer(publicKey: Uint8List(32), label: 'L', linkedAtMs: 5);
    expect(GuardianPeer.fromJson(p.toJson())!.label, 'L');
    expect(GuardianPeer.fromJson(<String, Object?>{'k': 'AAAA', 'l': 'x', 't': 1}), isNull, reason: 'key is not 32 bytes');
    expect(GuardianPeer.fromJson('nope'), isNull);
  });
}
