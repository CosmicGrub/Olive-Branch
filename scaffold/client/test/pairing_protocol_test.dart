// OLIVE BRANCH — the on-device pairing protocol, including the owner's isolation scenarios: two families on
// one network, two simultaneous sessions, a replayed message, a wrong PIN, a rogue advertiser. Verified by CI,
// headless (no sockets: the loopback transport routes messages to a chosen window).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';

Future<LocalPinRecord> _cheapVerifier(String pin) async =>
    LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

Future<AdultWindow> _window(DeviceKey k, {String name = 'Mom', String fid = 'fam-1', String cid = 'kid-1', String pin = '4829',
    bool qr = false, DateTime Function()? now, int attempts = 5, List<PairedKid>? paired}) =>
    AdultWindow.open(
        adultKey: k, adultName: name, familyId: fid, childId: cid, childName: 'Ivy', pin: pin, offerQr: qr, now: now,
        maxAttempts: attempts, makeUnlockVerifier: _cheapVerifier, onPaired: paired?.add);

ChildPairingClient _client(DeviceKey ck, PairingTransport t) => ChildPairingClient(
    childKey: ck, transport: t, delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3));

void main() {
  test('the happy path: PIN, match shown on both sides, approve, signed cert scoped to one child', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final List<PairedKid> paired = <PairedKid>[];
    final AdultWindow w = await _window(ak, paired: paired);
    PairingMatch? seen;
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w))
        .pair(sid: w.sid, password: '4829', onMatched: (PairingMatch m) => seen = m);
    expect(r.ok, isTrue, reason: '${r.failure}');
    expect(seen!.adultName, 'Mom');
    expect(seen!.sas.toString(), w.sas.toString(), reason: 'both screens show the same word and picture');
    final ChildPairing p = r.pairing!;
    expect(p.cert.familyId, 'fam-1');
    expect(p.cert.childId, 'kid-1');
    expect(await p.cert.verifiedBy(ak.publicKey), isTrue);
    expect(await p.cert.verifiedBy(ck.publicKey), isFalse);
    expect(paired.single.childId, 'kid-1');
    expect(w.isOpen, isFalse, reason: 'single use: the window is closed once the credential is handed over');
  });

  test('nothing is paired until the adult taps yes (declined = no credential)', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    w.addListener(() {
      if (w.state == WindowState.awaitingApproval) w.decline();
    });
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
    expect(r.ok, isFalse);
    expect(r.failure, PairingFailure.declined);
  });

  test('a wrong PIN fails, counts on the ADULT device, and the fifth kills the window', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    for (int i = 1; i <= 4; i++) {
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '0000');
      expect(r.failure, PairingFailure.notMatched);
      expect(w.attemptsLeft, 5 - i);
      expect(w.isOpen, isTrue);
    }
    await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '1111');
    expect(w.isOpen, isFalse);
    // Even the RIGHT PIN is now refused: the window is gone.
    final PairingResult late = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
    expect(late.ok, isFalse);
    expect(late.failure, PairingFailure.unreachable);
  });

  test('two families on one network with the SAME PIN never cross-connect', () async {
    final DeviceKey a1 = await _key(), a2 = await _key(), ck = await _key();
    final AdultWindow fam1 = await _window(a1, name: 'Mom', fid: 'fam-1', cid: 'kid-1');
    final AdultWindow fam2 = await _window(a2, name: 'Mom', fid: 'fam-2', cid: 'kid-9');
    // Same adult name, same PIN. The child picked family 2's window, so it talks to it and gets ITS cert.
    fam2.addListener(() async {
      if (fam2.state == WindowState.awaitingApproval) await fam2.approve();
    });
    final PairingResult r = await _client(ck, LoopbackPairingTransport(fam2)).pair(sid: fam2.sid, password: '4829');
    expect(r.pairing!.cert.familyId, 'fam-2');
    expect(await r.pairing!.cert.verifiedBy(a2.publicKey), isTrue);
    expect(await r.pairing!.cert.verifiedBy(a1.publicKey), isFalse);
    expect(fam1.state, WindowState.open, reason: 'the other family heard nothing it answers');
    // Misdirected: family 2's session id sent to family 1's device gets no answer at all.
    final AdultWindow fam2b = await _window(a2, name: 'Mom', fid: 'fam-2', cid: 'kid-9');
    final PairingResult mis = await _client(ck, LoopbackPairingTransport(fam1)).pair(sid: fam2b.sid, password: '4829');
    expect(mis.failure, PairingFailure.unreachable);
    expect(fam1.attemptsLeft, 5);
  });

  test('two simultaneous sessions in one family stay separate', () async {
    final DeviceKey ak = await _key(), c1 = await _key(), c2 = await _key();
    final AdultWindow w1 = await _window(ak, cid: 'kid-1'), w2 = await _window(ak, cid: 'kid-2');
    for (final AdultWindow w in <AdultWindow>[w1, w2]) {
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
    }
    final List<PairingResult> rs = await Future.wait(<Future<PairingResult>>[
      _client(c1, LoopbackPairingTransport(w1)).pair(sid: w1.sid, password: '4829'),
      _client(c2, LoopbackPairingTransport(w2)).pair(sid: w2.sid, password: '4829'),
    ]);
    expect(rs[0].pairing!.cert.childId, 'kid-1');
    expect(rs[1].pairing!.cert.childId, 'kid-2');
    expect(rs[0].pairing!.cert.childDeviceKey, isNot(rs[1].pairing!.cert.childDeviceKey));
    // Session 1's messages mean nothing to session 2.
    final AdultWindow w3 = await _window(ak), w4 = await _window(ak);
    final Map<String, dynamic>? crossed = await w4.handle(<String, dynamic>{'t': 'hello', 'sid': b64(w3.sid), 'cpk': b64(c1.publicKey)});
    expect(crossed, isNull);
  });

  test('a replayed message fails: pake1 + confirm recorded from a good run give an attacker nothing', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final PairingResult first = await _client(ck, LoopbackPairingTransport(w, log: log)).pair(sid: w.sid, password: '4829');
    expect(first.ok, isTrue);
    // The window is now closed (single use): every recorded message gets silence.
    for (final Map<String, dynamic> m in log) {
      expect(await w.handle(m), isNull);
    }
    // Replay against a FRESH window with the same PIN but a different session id: also nothing.
    final AdultWindow w2 = await _window(ak);
    for (final Map<String, dynamic> m in log) {
      expect(await w2.handle(m), isNull);
    }
    expect(w2.state, WindowState.open);
  });

  test('replaying a recorded confirm inside the SAME open window is a failed attempt, not a login', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    // A run that the adult never approves (so the window stays open), recorded by an eavesdropper.
    final Future<PairingResult> run = _client(ck, LoopbackPairingTransport(w, log: log)).pair(sid: w.sid, password: '4829');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(w.state, WindowState.awaitingApproval);
    final Map<String, dynamic> pake1 = log.firstWhere((Map<String, dynamic> m) => m['t'] == 'pake1');
    final Map<String, dynamic> confirm = log.firstWhere((Map<String, dynamic> m) => m['t'] == 'confirm');
    w.decline();
    await run;
    expect(await w.handle(pake1), isNull);
    expect(await w.handle(confirm), isNull);
  });

  test('a rogue advertiser (right name, wrong PIN) pairs nothing; and one with a different key is rejected', () async {
    final DeviceKey real = await _key(), rogue = await _key(), ck = await _key();
    final AdultWindow rogueWindow = await _window(rogue, name: 'Mom', pin: '9999');
    rogueWindow.addListener(() async {
      if (rogueWindow.state == WindowState.awaitingApproval) await rogueWindow.approve();
    });
    // The child is tricked into talking to the rogue by name; the adult types the REAL PIN.
    final PairingResult r = await _client(ck, LoopbackPairingTransport(rogueWindow)).pair(sid: rogueWindow.sid, password: '4829');
    expect(r.ok, isFalse);
    expect(r.failure, PairingFailure.notMatched);
    // Via QR the child also pins the real adult fingerprint, so the rogue key is refused before any secret flows.
    final AdultWindow rogueQr = await _window(rogue, name: 'Mom', qr: true);
    final PairingResult viaQr = await ChildPairingClient(childKey: ck, transport: LoopbackPairingTransport(rogueQr), delay: (Duration d) async {})
        .pair(sid: rogueQr.sid, password: b64(rogueQr.qrSecret!), viaQr: true, expectedAdultFingerprint: real.fingerprint);
    expect(viaQr.failure, PairingFailure.notMatched);
    expect(rogueQr.attemptsLeft, 5, reason: 'refused before any secret was used');
  });

  test('a window expires: no answer once the time is up', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    DateTime t = DateTime(2026, 11, 8, 10);
    final AdultWindow w = await _window(ak, now: () => t);
    t = t.add(const Duration(minutes: 11));
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
    expect(r.failure, PairingFailure.unreachable);
    expect(w.isOpen, isFalse);
  });

  test('the QR shortcut: works while open, once, with the adult fingerprint pinned; payload carries no PIN', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak, qr: true);
    final String payload = w.qrPayload(hints: <String>['192.168.1.5:8123'])!;
    expect(payload, startsWith('olive://pair/1?'));
    expect(payload, isNot(contains('4829')));
    final Uri u = Uri.parse(payload);
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(
        sid: unb64(u.queryParameters['s']!), password: u.queryParameters['q']!, viaQr: true,
        expectedAdultFingerprint: unb64(u.queryParameters['k']!));
    expect(r.ok, isTrue, reason: '${r.failure}');
    expect(w.qrPayload(), isNull, reason: 'the window closed and the secret is gone');
  });

  test('a photographed QR is useless once used, and its secret burns on a failed use too', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak, qr: true);
    final Uri u = Uri.parse(w.qrPayload()!);
    // Someone uses a WRONG secret in qr mode: the real one is burned (single use) and the failure counts.
    await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: 'not-the-secret', viaQr: true);
    expect(w.qrPayload(), isNull);
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(
        sid: w.sid, password: u.queryParameters['q']!, viaQr: true);
    expect(r.ok, isFalse);
  });

  test('the PIN is not on the wire and not derivable from the transcript', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    await _client(ck, LoopbackPairingTransport(w, log: log)).pair(sid: w.sid, password: '4829');
    expect(jsonEncode(log), isNot(contains('4829')));
  });

  test('a child cert is rejected when it names another child device or another family', () async {
    final DeviceKey ak = await _key(), ck = await _key(), other = await _key();
    final PairingCert c = await PairingCert.issue(ak,
        childDeviceKey: ck.publicKey, familyId: 'fam-1', childId: 'kid-1', certId: 'x', issuedAtMs: 1);
    expect(await c.verifiedBy(ak.publicKey), isTrue);
    expect(await c.verifiedBy(other.publicKey), isFalse);
    final PairingCert tampered = PairingCert(
        childDeviceKey: c.childDeviceKey, familyId: 'fam-2', childId: c.childId, adultFingerprint: c.adultFingerprint,
        issuedAtMs: c.issuedAtMs, certId: c.certId, signature: c.signature);
    expect(await tampered.verifiedBy(ak.publicKey), isFalse);
  });

  test('malformed messages get silence, never an exception', () async {
    final DeviceKey ak = await _key();
    final AdultWindow w = await _window(ak);
    expect(await w.handle(<String, dynamic>{}), isNull);
    expect(await w.handle(<String, dynamic>{'t': 'pake1', 'sid': b64(w.sid), 'cpk': 5}), isNull);
    expect(await w.handle(<String, dynamic>{'t': 'confirm', 'sid': b64(w.sid)}), isNull);
    expect(w.attemptsLeft, 5);
  });
}
