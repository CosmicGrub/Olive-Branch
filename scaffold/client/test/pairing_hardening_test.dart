// OLIVE BRANCH — regression tests for the red-team findings on the persistent-QR pairing branch: junk pake1 cannot kill
// a window, a stranger cannot burn the QR secret, a sniffed poll cannot take the sealed credential, and a replayed
// hello cannot take a scanned window's single claim slot. UNVERIFIED until CI runs it; loopback transport, real crypto.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_protocol.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

Future<AdultWindow> _window(DeviceKey k, {bool qr = false}) => AdultWindow.open(requireMatch: false,
    adultKey: k, adultName: 'Mom', familyId: 'fam-1', childId: 'kid-1', childName: 'Ivy', pin: '4829',
    offerQr: qr, makeUnlockVerifier: _cheap);

ChildPairingClient _client(DeviceKey ck, PairingTransport t) => ChildPairingClient(
    childKey: ck, transport: t, delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3));

Uint8List _salt(int f) => Uint8List.fromList(List<int>.filled(16, f));

void main() {
  test('RT1: malformed pake1 messages are not counted, so 25 of them leave the window usable', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    for (int i = 0; i < 25; i++) {
      expect(await w.handle(<String, dynamic>{'t': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid)}), isNull);
      expect(await w.handle(<String, dynamic>{'t': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': 'x', 'Yc': 5}), isNull);
    }
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    expect((await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829')).ok, isTrue);
  });

  test('RT2: a stranger who knows only the window id cannot burn the QR secret', () async {
    final DeviceKey ak = await _key(), stranger = await _key();
    final AdultWindow w = await _window(ak, qr: true);
    expect(w.qrPayload(), isNotNull);
    await _client(stranger, LoopbackPairingTransport(w)).pair(sid: w.sid, password: 'guess', viaQr: true);
    expect(w.qrPayload(), isNotNull);
  });

  test('RT3: a poll that repeats only the sniffed tagC (no proof) gets nothing, and the real child still receives the credential', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    final LoopbackPairingTransport t = LoopbackPairingTransport(w, log: log);
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) {
        await w.approve();
        // The thief saw the confirm on the wire and now repeats it as a poll, with and without a made-up proof.
        final Map<String, dynamic> confirm = log.firstWhere((Map<String, dynamic> m) => m['t'] == 'confirm');
        expect(await w.handle(<String, dynamic>{'t': 'poll', 'sid': b64(w.sid), 'tagC': confirm['tagC']}), isNull);
        expect(await w.handle(<String, dynamic>{'t': 'poll', 'sid': b64(w.sid), 'tagC': confirm['tagC'], 'tagP': b64(Uint8List(32))}), isNull);
        expect(w.state, WindowState.approved, reason: 'a failed thief poll neither closes the window nor takes the credential');
      }
    });
    final PairingResult r = await _client(ck, t).pair(sid: w.sid, password: '4829');
    expect(r.ok, isTrue);
  });

  test('RT3: a replayed (already used) poll proof does not work a second time', () async {
    final DeviceKey ak = await _key(), ck = await _key();
    final AdultWindow w = await _window(ak);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    final LoopbackPairingTransport t = LoopbackPairingTransport(w, log: log);
    // Pair but approve only after two polls, so a good poll is on the wire to replay.
    int polls = 0;
    final ChildPairingClient c = ChildPairingClient(
        childKey: ck, transport: t, delay: (Duration d) async {
      polls++;
      if (polls == 1) {
        final Map<String, dynamic> good = log.lastWhere((Map<String, dynamic> m) => m['t'] == 'poll');
        expect(await w.handle(good), isNull, reason: 'the first good poll was already used by the child; the nonce moved on');
      }
      if (polls == 2) await w.approve();
    }, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 10));
    final PairingResult r = await c.pair(sid: w.sid, password: '4829');
    // The replay was refused without disturbing the child's own next poll, so the real child still gets its credential.
    expect(r.ok, isTrue);
  });

  test('RT6: a stranger who replays the scanned child\'s hello cannot take the claim slot with pake1', () async {
    final DeviceKey ak = await _key(), ck = await _key(), stranger = await _key();
    final AdultWindow w = await _window(ak);
    w.allowChild(childKey: ck.publicKey, childSalt: _salt(3));
    final LoopbackPairingTransport t = LoopbackPairingTransport(w);
    final Map<String, dynamic> hello = <String, dynamic>{
      't': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'hs': b64(await signHello(ck, w.sid)),
    };
    final Map<String, dynamic>? ok = await t.send(hello); // the sniffed hello, replayed
    expect(ok, isNotNull);
    final PakeParty p = await PakeParty.start(isChild: true, password: '4829'.codeUnits, sid: w.sid, ci: Uint8List(0));
    final Map<String, dynamic> claim = <String, dynamic>{
      't': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'x', 'm': 'pin', 'Yc': b64(p.share),
    };
    // No signature, a signature by another key, and a signature over a made-up nonce: all dropped.
    expect(await t.send(claim), isNull);
    final Uint8List hn = unb64(ok!['hn'] as String);
    expect(await t.send(<String, dynamic>{...claim, 'hn': b64(hn), 'ps': b64(await signPake1(stranger, w.sid, hn, p.share))}), isNull);
    expect(await t.send(<String, dynamic>{...claim, 'hn': b64(Uint8List(16)), 'ps': b64(await signPake1(stranger, w.sid, Uint8List(16), p.share))}), isNull);
    // The real child, signing with its own key, still gets through afterwards.
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    expect((await _client(ck, t).pair(sid: w.sid, password: '4829')).ok, isTrue);
  });
}
