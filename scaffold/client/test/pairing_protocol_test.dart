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
    AdultWindow.open(requireMatch: false,
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
    final Map<String, dynamic>? crossed = await w4.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w3.sid), 'cpk': b64(c1.publicKey)});
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

  test('a QR is spent by a CONFIRMED use only; a wrong guess costs an attempt but cannot burn the QR shortcut', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak, qr: true);
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final Uri u = Uri.parse(w.qrPayload()!);
    final int before = w.attemptsLeft;
    await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: 'not-the-secret', viaQr: true);
    expect(w.attemptsLeft, before - 1, reason: 'the wrong guess is counted');
    expect(w.qrPayload(), isNotNull, reason: 'a stranger cannot destroy the QR shortcut');
    final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(
        sid: w.sid, password: u.queryParameters['q']!, viaQr: true);
    expect(r.ok, isTrue);
    expect(w.qrPayload(), isNull, reason: 'spent by the confirmed use');
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
    expect(await w.handle(<String, dynamic>{'t': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': 5}), isNull);
    expect(await w.handle(<String, dynamic>{'t': 'confirm', 'sid': b64(w.sid)}), isNull);
    expect(w.attemptsLeft, 5);
  });

  group('discovery handle: the child finds a window without the session id or the adult name in the advertisement', () {
    test('the handle is random per window and is not the session id; the label is a neutral seat name, not the adult name', () async {
      final DeviceKey ak = await _key();
      final AdultWindow a = await _window(ak, name: 'Margaret'), b = await _window(ak, name: 'Margaret');
      expect(a.discoveryHandle.length, 16);
      expect(a.discoveryHandle, isNot(a.sid));
      expect(a.discoveryHandle, isNot(b.discoveryHandle));
      expect(a.label, isIn(<String>['Player one', 'Player two']));
      expect(a.label, windowSeatLabel(a.discoveryHandle));
      expect(a.label.toLowerCase(), isNot(contains('mar')));
    });

    test('a full pairing that starts from the handle alone: the session id arrives in the hello answer', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PairingResult r =
          await _client(ck, LoopbackPairingTransport(w, log: log)).pair(handle: w.discoveryHandle, password: '4829');
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(log.first['t'], 'hello');
      expect(log.first.containsKey('sid'), isFalse, reason: 'the first message names the window by its handle only');
      expect(log.first['h'], b64(w.discoveryHandle));
    });

    test('a wrong handle gets silence and costs the window nothing', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w))
          .pair(handle: Uint8List.fromList(List<int>.filled(16, 7)), password: '4829');
      expect(r.failure, PairingFailure.unreachable);
      expect(w.attemptsLeft, 5);
    });

    test('the handle works only for the hello: every later message still needs the session id', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic>? p = await w.handle(
          <String, dynamic>{'t': 'pake1', 'pv': kPairingProtocolVersion, 'h': b64(w.discoveryHandle), 'cpk': b64(ck.publicKey), 'Yc': b64(ck.publicKey)});
      expect(p, isNull);
    });

    test('asking for neither a sid nor a handle is a programming error, not a network call', () async {
      final DeviceKey ck = await _key();
      final AdultWindow w = await _window(await _key());
      await expectLater(_client(ck, LoopbackPairingTransport(w)).pair(password: '4829'), throwsArgumentError);
    });

    test('a hello answer with a session id of the wrong size is refused', () async {
      final DeviceKey ck = await _key();
      final PairingResult r = await _client(ck, _FixedTransport(<String, dynamic>{
        't': 'hello-ok', 'pv': kPairingProtocolVersion, 'sid': b64(<int>[1, 2, 3]),
      })).pair(handle: Uint8List(16), password: '4829');
      expect(r.ok, isFalse);
      expect(r.failure, PairingFailure.malformed);
    });
  });

  group('key-exchange version (CPace draft-21 alignment): old and new builds fail calmly', () {
    test('the adult states the version in hello-ok', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic>? ok = await w.handle(<String, dynamic>{'t': 'hello', 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'T'});
      expect(ok!['pv'], kPairingProtocolVersion);
      expect(kPairingProtocolVersion, 3);
    });

    test('a new child meeting an old adult (hello-ok without a version) stops before any key-exchange message', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      final PairingResult r = await _client(ck, _OldAdultTransport(w, sent)).pair(sid: w.sid, password: '4829');
      expect(r.ok, isFalse);
      expect(r.failure, PairingFailure.versionMismatch, reason: 'the grown-up side can say why; the tablet only ever shows its one calm card');
      expect(sent.map((Map<String, dynamic> m) => m['t']), <String>['hello'], reason: 'no pake1 was sent');
      expect(w.attemptsLeft, 5);
      expect(w.isOpen, isTrue);
    });

    test('an old child meeting a new adult (pake1 without a version) is dropped silently, uncounted, and the window stays usable', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult old = await _client(ck, _OldChildTransport(w)).pair(sid: w.sid, password: '4829');
      expect(old.ok, isFalse);
      expect(old.failure, PairingFailure.notMatched);
      expect(w.attemptsLeft, 5, reason: 'a version mismatch never costs an attempt');
      expect(w.state, WindowState.open);
      // The same PIN from an up-to-date child still pairs in the same window.
      expect((await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829')).ok, isTrue);
    });

    test('a wrong version number is dropped just like a missing one', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final PakeParty p = await PakeParty.start(isChild: true, password: '4829'.codeUnits, sid: w.sid, ci: Uint8List(0));
      for (final Object? pv in <Object?>[null, 1, 2, 4, '3', 3.5, true]) {
        expect(
            await w.handle(<String, dynamic>{
              't': 'pake1', 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'm': 'pin', 'Yc': b64(p.share), 'pv': pv,
            }),
            isNull,
            reason: 'pv=$pv');
      }
      expect(w.attemptsLeft, 5);
    });
  });

  group('per-source attempt budget on the adult window', () {
    test('one source cannot burn the window: three failed confirmations and it is ignored; the window keeps two', () async {
      final DeviceKey ak = await _key(), ck = await _key(), ck2 = await _key();
      final AdultWindow w = await _window(ak);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      for (int i = 1; i <= kSourceMaxFailures; i++) {
        final PairingResult r = await _client(ck, LoopbackPairingTransport(w, source: 'burner')).pair(sid: w.sid, password: '0000');
        expect(r.failure, PairingFailure.notMatched);
        expect(w.attemptsLeft, 5 - i);
      }
      // The burner now gets silence on every message, and the window is still open with its remaining tries.
      final PairingResult more = await _client(ck, LoopbackPairingTransport(w, source: 'burner')).pair(sid: w.sid, password: '0000');
      expect(more.failure, PairingFailure.unreachable);
      expect(w.attemptsLeft, 5 - kSourceMaxFailures);
      expect(w.isOpen, isTrue);
      // Even the burner holding the RIGHT PIN is ignored (a quiet block, not a hint about the PIN).
      final PairingResult right = await _client(ck, LoopbackPairingTransport(w, source: 'burner')).pair(sid: w.sid, password: '4829');
      expect(right.failure, PairingFailure.unreachable);
      // A different source, the real child, still pairs.
      final PairingResult real = await _client(ck2, LoopbackPairingTransport(w, source: 'child')).pair(sid: w.sid, password: '4829');
      expect(real.ok, isTrue, reason: '${real.failure}');
    });

    test('the budget never makes the window easier to guess: the shared five still end it', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      for (int i = 0; i < 5; i++) {
        await _client(ck, LoopbackPairingTransport(w, source: 'src-${i ~/ 2}')).pair(sid: w.sid, password: '0000');
      }
      expect(w.isOpen, isFalse);
    });

    test('hello and pake1 are capped per source too, and other sources are unaffected', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      Future<Map<String, dynamic>?> hello(String src) =>
          w.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)}, source: src);
      for (int i = 0; i < kSourceMaxHello; i++) {
        expect(await hello('spam'), isNotNull);
      }
      expect(await hello('spam'), isNull, reason: 'over its hello budget');
      expect(await hello('other'), isNotNull);

      Future<Map<String, dynamic>?> pake1(String src) => w.handle(<String, dynamic>{
            't': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'm': 'pin',
            'Yc': b64(Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + 3) & 0xff))),
          }, source: src);
      // Only one claim is in flight at a time (a second one is dropped without being counted), so the claim is
      // cleared between tries the way "Make a new code" does; the budget then bounds how often one source may start.
      for (int i = 0; i < kSourceMaxPake1; i++) {
        expect(await pake1('p1'), isNotNull);
        w.refreshAdultPicture(Uint8List(16));
      }
      expect(await pake1('p1'), isNull, reason: 'over its pake1 budget');
      expect(await pake1('p2'), isNotNull, reason: 'another source is not starved by it');
      expect(w.attemptsLeft, 5, reason: 'none of this touched the failure count');
    });

    test('a source with no address (the in-process path) is never limited', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      for (int i = 0; i < kSourceMaxHello + 5; i++) {
        expect(await w.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)}), isNotNull);
      }
    });

    test('the table of sources is bounded, and a flood of free hellos never starves a new legitimate source', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      Future<Map<String, dynamic>?> hello(String src) =>
          w.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)}, source: src);
      for (int i = 0; i < kMaxTrackedSources * 3; i++) {
        expect(await hello('s$i'), isNotNull, reason: 'source $i is never refused for want of room');
      }
      expect(await hello('the-real-child'), isNotNull);
      expect(w.trackedSourceCount, lessThanOrEqualTo(kMaxTrackedSources), reason: 'memory stays bounded');
    });

    test('a source that has failed a confirmation keeps its block through any flood of new sources', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      for (int i = 0; i < kSourceMaxFailures; i++) {
        await _client(ck, LoopbackPairingTransport(w, source: 'burner')).pair(sid: w.sid, password: '0000');
      }
      Future<Map<String, dynamic>?> hello(String src) =>
          w.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)}, source: src);
      for (int i = 0; i < kMaxTrackedSources * 3; i++) {
        await hello('flood$i');
      }
      expect(await hello('burner'), isNull, reason: 'a flood cannot wash the burner back to a clean slate');
    });

    test('least-recently-used goes first: an active source keeps its budget while idle ones are dropped', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      Future<Map<String, dynamic>?> hello(String src) =>
          w.handle(<String, dynamic>{'t': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)}, source: src);
      for (int i = 0; i < kSourceMaxHello; i++) {
        await hello('active');
      }
      expect(await hello('active'), isNull);
      for (int i = 0; i < kMaxTrackedSources * 2; i++) {
        await hello('idle$i');
        await hello('active'); // keeps touching it
      }
      expect(await hello('active'), isNull, reason: 'still over budget: it was never the eviction victim');
    });

    test('two addresses of one dual-stack host cannot, together, burn more than the window cap leaves the real child', () async {
      expect(kSourceMaxFailures * 2, lessThan(kWindowMaxAttempts), reason: 'v4 + v6 budgets must sum below the cap');
      final DeviceKey ak = await _key(), ck = await _key(), ck2 = await _key();
      final AdultWindow w = await _window(ak);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      for (final String src in <String>['host-v4', 'host-v6']) {
        for (int i = 0; i < kSourceMaxFailures + 2; i++) {
          await _client(ck, LoopbackPairingTransport(w, source: src)).pair(sid: w.sid, password: '0000');
        }
      }
      expect(w.isOpen, isTrue);
      expect(w.attemptsLeft, greaterThanOrEqualTo(1));
      final PairingResult real = await _client(ck2, LoopbackPairingTransport(w, source: 'child')).pair(sid: w.sid, password: '4829');
      expect(real.ok, isTrue, reason: '${real.failure}');
    });

    test('a blocked source costs the child nothing visible: the result is the same quiet "unreachable"', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      for (int i = 0; i < kSourceMaxFailures; i++) {
        await _client(ck, LoopbackPairingTransport(w, source: 'b')).pair(sid: w.sid, password: '0000');
      }
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w, source: 'b', log: log)).pair(sid: w.sid, password: '0000');
      expect(r.failure, PairingFailure.unreachable);
      expect(log.length, 1, reason: 'it never got past the first message');
    });
  });
  test('the sealed credential carries her age (3 to 17 only) so a tablet can open her home with no server', () async {
    Future<ChildPairing?> pairWith(int? age) async {
      final DeviceKey ak = await _key(), ck = await _key();
      // requireMatch: false like every other test here (see _window): this one is about the sealed age, not the
      // Match step; with the default (true) approve() refuses and the child times out.
      final AdultWindow w = await AdultWindow.open(requireMatch: false,
          adultKey: ak, adultName: 'Mom', familyId: 'fam-1', childId: 'kid-1', childName: 'Ivy', childAge: age,
          pin: '4829', makeUnlockVerifier: _cheapVerifier);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue, reason: '${r.failure}');
      return r.pairing;
    }
    expect((await pairWith(9))!.childAge, 9);
    expect((await pairWith(null))!.childAge, isNull, reason: 'no age given = none sent');
    expect((await pairWith(2))!.childAge, isNull, reason: 'implausible ages are dropped, not trusted');
    expect((await pairWith(99))!.childAge, isNull);
  });
}

/// Answers every message with one canned map.
class _FixedTransport implements PairingTransport {
  _FixedTransport(this.answer);
  final Map<String, dynamic> answer;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async => answer;
}

/// An adult that predates the version field: its hello-ok carries no `pv`.
class _OldAdultTransport implements PairingTransport {
  _OldAdultTransport(this.target, this.sent);
  final AdultWindow target;
  final List<Map<String, dynamic>> sent;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    sent.add(Map<String, dynamic>.of(message));
    final Map<String, dynamic>? r = await target.handle(message);
    if (r != null && r['t'] == 'hello-ok') return <String, dynamic>{...r}..remove('pv');
    return r;
  }
}

/// A child that predates the version field: its pake1 carries no `pv`, and it ignores the adult's.
class _OldChildTransport implements PairingTransport {
  _OldChildTransport(this.target);
  final AdultWindow target;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) =>
      target.handle(<String, dynamic>{...message}..remove('pv'));
}
