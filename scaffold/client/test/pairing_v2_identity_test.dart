// OLIVE BRANCH — pairing hardening, part 1: protocol version 2. The grown-up's name, family id and key are no longer
// returned in the clear to a device that merely holds the public window handle; they travel only inside the key
// exchange, and the child checks them before it shows or polls anything. Also: version negotiation (an old build fails
// calmly) and the "no typed-code verifier by default" rule. UNVERIFIED until CI runs it; loopback transport, real crypto.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';

int _verifierCalls = 0;
Future<LocalPinRecord> _counting(String pin) async {
  _verifierCalls++;
  return LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
}

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
Uint8List _b(int n, int f) => Uint8List.fromList(List<int>.filled(n, f));

Future<AdultWindow> _window(DeviceKey k, {String fid = 'fam-secret-77', bool? phoneOnly, Uint8List? fk, bool qr = false, String name = 'Grandma Ottoline'}) =>
    AdultWindow.open(
        adultKey: k, adultName: name, familyId: fid, childId: 'kid-1', childName: 'Ivy', pin: '4829', offerQr: qr, familyKey: fk,
        makeUnlockVerifier: _counting, phoneOnly: phoneOnly ?? true);

ChildPairingClient _client(DeviceKey ck, PairingTransport t) => ChildPairingClient(
    childKey: ck, transport: t, delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3));

/// Records every answer the window gives, in order.
class _Recording implements PairingTransport {
  _Recording(this.inner);
  final PairingTransport inner;
  final List<Map<String, dynamic>> answers = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    sent.add(Map<String, dynamic>.of(message));
    final Map<String, dynamic>? a = await inner.send(message);
    if (a != null) answers.add(Map<String, dynamic>.of(a));
    return a;
  }
}

/// Lets a test rewrite one answer on its way back to the child.
class _Rewrite implements PairingTransport {
  _Rewrite(this.inner, this.type, this.edit);
  final PairingTransport inner;
  final String type;
  final void Function(Map<String, dynamic>) edit;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final Map<String, dynamic>? a = await inner.send(message);
    if (a != null && a['t'] == type) {
      final Map<String, dynamic> c = Map<String, dynamic>.of(a);
      edit(c);
      return c;
    }
    return a;
  }
}

class _Fixed implements PairingTransport {
  _Fixed(this.answer);
  final Map<String, dynamic>? answer;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    sent.add(message);
    return answer;
  }
}

void _approveWhenAsked(AdultWindow w) {
  w.addListener(() async {
    if (w.state == WindowState.awaitingApproval) await w.approve();
  });
}

void main() {
  group('hello-ok reveals nothing about the grown-up', () {
    test('a device holding only the handle gets a bare answer: no name, no family id, no key, no fingerprint', () async {
      final DeviceKey ak = await _key(), stranger = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic>? a = await w.handle(<String, dynamic>{
        't': 'hello', 'pv': 2, 'h': b64(w.discoveryHandle), 'cpk': b64(stranger.publicKey), 'dn': 'x',
      });
      expect(a!['t'], 'hello-ok');
      expect(a.keys.toSet().difference(<String>{'t', 'pv', 'sid', 'ft', 'fa', 'hn'}), isEmpty, reason: 'only these fields may exist: ${a.keys}');
      final String wire = jsonEncode(a);
      expect(wire, isNot(contains('Ottoline')));
      expect(wire, isNot(contains('fam-secret-77')));
      expect(wire, isNot(contains(b64(ak.publicKey))));
      expect(wire, isNot(contains(b64(ak.fingerprint))));
    });

    test('a whole successful pairing: nothing before the key confirmation names the grown-up; afterwards it is sealed', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      _approveWhenAsked(w);
      final _Recording t = _Recording(LoopbackPairingTransport(w));
      final PairingResult r = await _client(ck, t).pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(r.pairing!.adultName, 'Grandma Ottoline', reason: 'the child still learns it, from inside the channel');
      expect(r.pairing!.cert.familyId, 'fam-secret-77');
      for (final Map<String, dynamic> a in t.answers) {
        final String wire = jsonEncode(a);
        expect(wire, isNot(contains('Ottoline')), reason: 'answer ${a['t']}');
        expect(wire, isNot(contains('fam-secret-77')), reason: 'answer ${a['t']}');
        expect(wire, isNot(contains(b64(ak.publicKey))), reason: 'answer ${a['t']}');
      }
      final Map<String, dynamic> confirmOk = t.answers.firstWhere((Map<String, dynamic> a) => a['t'] == 'confirm-ok');
      expect(confirmOk['id'], isA<String>(), reason: 'the identity rides in the sealed field');
    });

    test('the QR path and the scanned-fingerprint path still pair', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, qr: true);
      _approveWhenAsked(w);
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w))
          .pair(sid: w.sid, password: b64(w.qrSecret!), viaQr: true, expectedAdultFingerprint: ak.fingerprint);
      expect(r.ok, isTrue, reason: '${r.failure}');
      final AdultWindow w2 = await _window(ak);
      _approveWhenAsked(w2);
      final PairingResult r2 = await _client(await _key(), LoopbackPairingTransport(w2))
          .pair(sid: w2.sid, password: '4829', expectedAdultFingerprint: ak.fingerprint);
      expect(r2.ok, isTrue, reason: '${r2.failure}');
    });

    test('hostile: the sealed identity is tampered with -> the child refuses and never shows the match step', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      bool shown = false;
      final PairingResult r = await _client(
              ck,
              _Rewrite(LoopbackPairingTransport(w), 'confirm-ok', (Map<String, dynamic> a) {
                final Uint8List id = unb64(a['id'] as String);
                id[id.length ~/ 2] ^= 1;
                a['id'] = b64(id);
              }))
          .pair(sid: w.sid, password: '4829', onMatched: (PairingMatch m) => shown = true);
      expect(r.ok, isFalse);
      expect(shown, isFalse);
    });

    test('hostile: an identity sealed in an EARLIER session is replayed into a later one -> refused', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w1 = await _window(ak);
      final _Recording t1 = _Recording(LoopbackPairingTransport(w1));
      await _client(ck, t1).pair(sid: w1.sid, password: '4829'); // never approved: the sealed identity is still produced
      final String oldId = t1.answers.firstWhere((Map<String, dynamic> a) => a['t'] == 'confirm-ok')['id'] as String;
      final AdultWindow w2 = await _window(ak);
      bool shown = false;
      final PairingResult r = await _client(ck, _Rewrite(LoopbackPairingTransport(w2), 'confirm-ok', (Map<String, dynamic> a) => a['id'] = oldId))
          .pair(sid: w2.sid, password: '4829', onMatched: (PairingMatch m) => shown = true);
      expect(r.ok, isFalse);
      expect(shown, isFalse);
    });

    test('hostile: a missing sealed identity is refused (it cannot be skipped)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final PairingResult r = await _client(ck, _Rewrite(LoopbackPairingTransport(w), 'confirm-ok', (Map<String, dynamic> a) => a.remove('id')))
          .pair(sid: w.sid, password: '4829');
      expect(r.ok, isFalse);
    });

    test('a window whose grown-up is not the one expected (PIN path with a scanned fingerprint) is refused before any key exchange', () async {
      final DeviceKey ak = await _key(), other = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      bool shown = false;
      final _Recording t = _Recording(LoopbackPairingTransport(w));
      final PairingResult r = await _client(ck, t)
          .pair(sid: w.sid, password: '4829', expectedAdultFingerprint: other.fingerprint, onMatched: (PairingMatch m) => shown = true);
      expect(r.ok, isFalse);
      expect(r.failure, PairingFailure.notMatched);
      expect(shown, isFalse);
      expect(t.sent.map((Map<String, dynamic> m) => m['t']), <String>['hello']);
      expect(w.attemptsLeft, 5);
    });

    test('the adult hint is useless without the fingerprint: it differs per device and per window and is not the fingerprint', () async {
      final DeviceKey ak = await _key(), c1 = await _key(), c2 = await _key();
      final AdultWindow w = await _window(ak), w2 = await _window(ak);
      Future<String> fa(AdultWindow win, DeviceKey c) async => (await win.handle(<String, dynamic>{
            't': 'hello', 'pv': 2, 'sid': b64(win.sid), 'cpk': b64(c.publicKey), 'dn': 'x',
          }))!['fa'] as String;
      expect(await fa(w, c1), isNot(await fa(w, c2)));
      expect(await fa(w, c1), isNot(await fa(w2, c1)));
      expect(await fa(w, c1), isNot(contains(b64(ak.fingerprint))));
    });

    test('hostile: a window that hides the adult hint from a child that holds the fingerprint is refused (no downgrade)', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final PairingResult r = await _client(ck, _Rewrite(LoopbackPairingTransport(w), 'hello-ok', (Map<String, dynamic> a) => a.remove('fa')))
          .pair(sid: w.sid, password: '4829', expectedAdultFingerprint: ak.fingerprint);
      expect(r.failure, PairingFailure.notMatched);
    });

    test('a claimed child meeting a window of another family: stopped on the blinded hint, nothing but the hello is sent', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, fk: _b(16, 1));
      final _Recording t = _Recording(LoopbackPairingTransport(w));
      final PairingResult r = await _client(ck, t).pair(sid: w.sid, password: '4829', expectedFamilyKey: _b(16, 2));
      expect(r.ok, isFalse);
      expect(t.sent.map((Map<String, dynamic> m) => m['t']), <String>['hello']);
      expect(w.attemptsLeft, 5);
    });

    test('the blinded hint is useless to a stranger: it differs per device and per window, and is not the family key', () async {
      final DeviceKey ak = await _key(), c1 = await _key(), c2 = await _key();
      final Uint8List fk = _b(16, 5);
      final AdultWindow w = await _window(ak, fk: fk);
      Future<String> hint(DeviceKey c) async => (await w.handle(<String, dynamic>{
            't': 'hello', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(c.publicKey), 'dn': 'x',
          }))!['ft'] as String;
      expect(await hint(c1), isNot(await hint(c2)));
      final AdultWindow w2 = await _window(ak, fk: fk);
      final String other = (await w2.handle(<String, dynamic>{
        't': 'hello', 'pv': 2, 'sid': b64(w2.sid), 'cpk': b64(c1.publicKey), 'dn': 'x',
      }))!['ft'] as String;
      expect(other, isNot(await hint(c1)));
      expect(await hint(c1), isNot(contains(b64(fk))));
    });
  });

  group('version negotiation: an old build fails calmly', () {
    test('a version 1 child (no pv in its hello) gets silence and costs the window nothing', () async {
      final DeviceKey ak = await _key(), old = await _key();
      final AdultWindow w = await _window(ak);
      expect(await w.handle(<String, dynamic>{'t': 'hello', 'sid': b64(w.sid), 'cpk': b64(old.publicKey), 'dn': 'x'}), isNull);
      expect(await w.handle(<String, dynamic>{'t': 'hello', 'pv': 1, 'sid': b64(w.sid), 'cpk': b64(old.publicKey), 'dn': 'x'}), isNull);
      expect(await w.handle(<String, dynamic>{'t': 'hello', 'pv': 'two', 'sid': b64(w.sid), 'cpk': b64(old.publicKey)}), isNull);
      expect(w.attemptsLeft, 5);
      expect(w.state, WindowState.open);
    });

    test('a version 1 child that skips the hello and sends a key exchange is dropped, uncounted', () async {
      final DeviceKey ak = await _key(), old = await _key();
      final AdultWindow w = await _window(ak);
      expect(
          await w.handle(<String, dynamic>{
            't': 'pake1', 'sid': b64(w.sid), 'cpk': b64(old.publicKey), 'dn': 'x', 'm': 'pin', 'Yc': b64(_b(32, 9)),
          }),
          isNull);
      expect(w.attemptsLeft, 5);
    });

    test('a window that answers like version 1 (details in the clear, no version) -> versionMismatch, no further message sent', () async {
      final DeviceKey ck = await _key();
      final _Fixed t = _Fixed(<String, dynamic>{
        't': 'hello-ok', 'sid': b64(_b(16, 1)), 'afp': 'x', 'apk': 'x', 'an': 'Mom', 'fid': 'f',
      });
      final PairingResult r = await _client(ck, t).pair(sid: _b(16, 1), password: '4829');
      expect(r.failure, PairingFailure.versionMismatch);
      expect(t.sent.length, 1);
    });

    test('a window announcing a future version this build does not speak -> versionMismatch', () async {
      final DeviceKey ck = await _key();
      final PairingResult r = await _client(ck, _Fixed(<String, dynamic>{'t': 'hello-ok', 'pv': 3, 'sid': b64(_b(16, 1))}))
          .pair(sid: _b(16, 1), password: '4829');
      expect(r.failure, PairingFailure.versionMismatch);
    });

    test('a child announcing a higher version than the window speaks is answered with the window\'s own version', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak);
      final Map<String, dynamic>? a = await w.handle(<String, dynamic>{'t': 'hello', 'pv': 9, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)});
      expect(a!['pv'], kPairingProtocolVersion);
    });
  });

  group('no typed-code verifier by default', () {
    test('a newly paired tablet is given none: the credential, the child record and the key-derivation are all absent', () async {
      _verifierCalls = 0;
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak); // default
      expect(w.phoneOnly, isTrue);
      _approveWhenAsked(w);
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue);
      expect(r.pairing!.unlockVerifier, isNull);
      expect(r.pairing!.phoneOnly, isTrue);
      expect(_verifierCalls, 0, reason: 'the PIN is never turned into a stored verifier');
    });

    test('a grown-up can still opt in to the keypad, explicitly', () async {
      _verifierCalls = 0;
      final DeviceKey ak = await _key(), ck = await _key();
      final AdultWindow w = await _window(ak, phoneOnly: false);
      _approveWhenAsked(w);
      final PairingResult r = await _client(ck, LoopbackPairingTransport(w)).pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue);
      expect(r.pairing!.unlockVerifier, isNotNull);
      expect(_verifierCalls, 1);
    });
  });
}
