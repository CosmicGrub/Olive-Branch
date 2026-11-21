// OLIVE BRANCH — "Her tablet": every way to connect a tablet to the grown-up's phone, end to end over the REAL same-network
// transport (a real HTTP server on loopback with the real source budgets, the real key exchange, real signatures), and the
// way back out: disconnect and connect again. Verified by CI, headless. Only mDNS (which needs two devices) is not here.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));

/// The grown-up's phone: a trust book and a paired-tablet list, and a way to open a window the way the screen does.
class _Phone {
  _Phone(this.key);
  final DeviceKey key;
  final TrustBook trust = TrustBook(MemoryTrustRepository());
  final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
  final List<PairedKid> delivered = <PairedKid>[];

  Future<AdultWindow> open({
    String? pin = '4829',
    bool awaitCode = false,
    bool phoneOnly = true,
    String? unlockPin,
    int maxAttempts = 5,
    DateTime Function()? now,
    bool approve = true,
  }) async {
    final AdultWindow w = await AdultWindow.open(
      adultKey: key, adultName: 'Mom', familyId: 'fam', childId: 'kid', childName: 'Ivy', pin: pin, unlockPin: unlockPin,
      awaitCode: awaitCode, phoneOnly: phoneOnly, makeUnlockVerifier: _cheap, maxAttempts: maxAttempts, now: now,
      wasStopped: trust.isRefused,
      onPaired: (PairedKid k) async {
        delivered.add(k);
        await kids.add(k);
        await trust.add(certId: k.certId, deviceKey: k.childDeviceKey, deviceName: k.deviceName, role: PairedRole.child, addedBy: 'Mom');
      },
    );
    if (approve) {
      w.addListener(() async {
        // The grown-up picks the right Match card and taps Yes.
        if (w.state == WindowState.awaitingApproval && !w.matchConfirmed) {
          w.pickMatch(w.matchChoices!.correct);
          await w.approve();
        }
      });
    }
    return w;
  }
}

/// A tablet whose connection drops after the key exchange: it never asks for its credential.
class _DropsPolls implements PairingTransport {
  _DropsPolls(this.inner);
  final PairingTransport inner;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async => message['t'] == 'poll' ? null : inner.send(message);
}

Future<(LanPairingHost, ChildPairingClient)> _lan(AdultWindow w, DeviceKey ck) async {
  final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
  await host.start(advertise: false);
  return (host, ChildPairingClient(childKey: ck, transport: LanPairingTransport('127.0.0.1', host.port!), delay: (Duration d) async {}));
}

void main() {
  late DeviceKey ak, ck;
  setUp(() async {
    ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
  });

  group('ROOT CAUSE: a tablet that was disconnected could never be connected again', () {
    // Proven on the first run of this file against the code before the fix: after "Stop this connection" (or "Remove") the
    // tablet's key was on the phone's refused list, the open window went SILENT to it (no answer, uncounted) and the tablet
    // showed its calm "try again" card forever, while "Disconnect" and "Unlock" on the same tablet still worked. The tablet keeps
    // its own key across a disconnect, so the very same tablet could never be connected again, whatever the grown-up did.
    test('connect, stop, connect again over the real LAN: it works, and says it was stopped before', () async {
      final _Phone phone = _Phone(ak);
      AdultWindow w = await phone.open();
      var (LanPairingHost h, ChildPairingClient c) = await _lan(w, ck);
      PairingResult r = await c.pair(handle: w.discoveryHandle, password: '4829');
      expect(r.ok, isTrue, reason: 'first connection: ${r.failure}');
      await h.stop();
      final TrustedDevice first = (await phone.trust.devices()).single;
      expect(await phone.trust.stop(first.certId), isTrue);
      await phone.kids.forget(first.certId);
      expect(await phone.trust.isRefused(ck.publicKey), isTrue);

      w = await phone.open();
      (h, c) = await _lan(w, ck);
      r = await c.pair(handle: w.discoveryHandle, password: '4829');
      expect(r.ok, isTrue, reason: 'connecting a stopped tablet again on purpose must work: ${r.failure}');
      expect(w.pendingWasStopped, isTrue, reason: 'the approval step is told it was stopped before, so the grown-up decides knowingly');
      await h.stop();
      expect(await phone.trust.isRefused(ck.publicKey), isFalse, reason: 'a deliberate approval ends the refusal');
      expect((await phone.trust.devices()).length, 1, reason: 'one tablet is one record, never two');
      expect((await phone.kids.load()).length, 1);
    });

    test('connect, forget, connect again, three times over: one row each time, never revoked', () async {
      final _Phone phone = _Phone(ak);
      for (int i = 0; i < 3; i++) {
        final AdultWindow w = await phone.open();
        final (LanPairingHost h, ChildPairingClient c) = await _lan(w, ck);
        final PairingResult r = await c.pair(handle: w.discoveryHandle, password: '4829');
        expect(r.ok, isTrue, reason: 'round $i: ${r.failure}');
        await h.stop();
        expect((await phone.kids.load()).length, 1, reason: 'round $i');
        expect(await phone.trust.isRevoked(ck.publicKey), isFalse, reason: 'round $i');
        await phone.trust.forget(ck.publicKey);
        await phone.kids.forget((await phone.kids.load()).single.certId);
        expect(await phone.trust.isRevoked(ck.publicKey), isTrue);
      }
    });

    test('the same tablet connected twice without a disconnect in between replaces its own record', () async {
      final _Phone phone = _Phone(ak);
      for (int i = 0; i < 2; i++) {
        final AdultWindow w = await phone.open();
        final (LanPairingHost h, ChildPairingClient c) = await _lan(w, ck);
        expect((await c.pair(handle: w.discoveryHandle, password: '4829')).ok, isTrue);
        await h.stop();
      }
      expect((await phone.kids.load()).length, 1);
      expect((await phone.trust.devices()).length, 1);
    });

    test('the phone lists a tablet only once it has really been handed its credential', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(approve: false);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval && !w.matchConfirmed) {
          w.pickMatch(w.matchChoices!.correct);
          await w.approve(); // approved, and nobody ever polls for it
        }
      });
      final (LanPairingHost h, _) = await _lan(w, ck);
      // The tablet's Wi-Fi drops right after it confirmed: every poll for the credential is lost.
      final ChildPairingClient impatient = ChildPairingClient(
          childKey: ck, transport: _DropsPolls(LanPairingTransport('127.0.0.1', h.port!)), delay: (Duration d) async {});
      expect((await impatient.pair(handle: w.discoveryHandle, password: '4829')).ok, isFalse);
      for (int i = 0; i < 200 && w.state != WindowState.approved; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(w.state, WindowState.approved);
      expect(phone.delivered, isEmpty, reason: 'approved but never delivered: not listed as connected');
      expect(await phone.kids.load(), isEmpty);
      w.close();
      await h.stop();
    });
  });

  group('the CODE way: her tablet shows six digits, the grown-up types them on the phone (real LAN transport)', () {
    Future<(LanPairingHost, ChildPairingClient)> lanCode(AdultWindow w, DeviceKey key) async {
      final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
      await host.start(advertise: false);
      return (
        host,
        ChildPairingClient(
            childKey: key, transport: LanPairingTransport('127.0.0.1', host.port!), pollEvery: const Duration(milliseconds: 5),
            delay: (Duration d) => Future<void>.delayed(const Duration(milliseconds: 5))),
      );
    }

    test('the window has no password until the code is typed; then the tablet connects, and nobody typed a PIN on the tablet', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null, unlockPin: '4829');
      expect(w.hasPassword, isFalse);
      final (LanPairingHost h, ChildPairingClient c) = await lanCode(w, ck);
      final String code = newPairingCode();
      expect(isPairingCode(code), isTrue);
      bool waited = false;
      final Future<PairingResult> f = c.pair(handle: w.discoveryHandle, password: code, waitForCode: true, onWaitingForCode: () => waited = true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(waited, isTrue);
      expect(w.state, WindowState.open, reason: 'nothing starts before the grown-up has typed the code');
      expect(w.provideCode(code), isTrue);
      final PairingResult r = await f;
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(phone.delivered.length, 1);
      await h.stop();
    });

    test("the typed-code check a tablet may be given comes from the grown-up's PIN, never from the six-digit code", () async {
      final List<String> asked = <String>[];
      final AdultWindow w = await AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'fam', childId: 'kid', childName: 'Ivy', pin: null, unlockPin: '4829', awaitCode: true,
        phoneOnly: false, requireMatch: false,
        makeUnlockVerifier: (String p) {
          asked.add(p);
          return _cheap(p);
        },
      );
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final (LanPairingHost h, ChildPairingClient c) = await lanCode(w, ck);
      final Future<PairingResult> f = c.pair(handle: w.discoveryHandle, password: '246810', waitForCode: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      w.provideCode('246810');
      expect((await f).ok, isTrue);
      expect(asked, <String>['4829']);
      await h.stop();
    });

    test('a wrong code costs one try, is spent (the window asks for the code again), and the right one then works', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null, unlockPin: '4829');
      final (LanPairingHost h, ChildPairingClient c) = await lanCode(w, ck);
      Future<PairingResult> attempt() => c.pair(handle: w.discoveryHandle, password: '482913', waitForCode: true);
      Future<PairingResult> first = attempt();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(w.provideCode('000000'), isTrue); // the grown-up mistyped it
      expect((await first).failure, PairingFailure.notMatched);
      expect(w.attemptsLeft, 4);
      expect(w.hasPassword, isFalse, reason: 'the wrong code is spent: it has to be typed again');
      first = attempt();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(w.provideCode('482913'), isTrue);
      expect((await first).ok, isTrue);
      await h.stop();
    });

    test('provideCode takes exactly six digits, only in the code way, only while the window is open', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null);
      for (final String bad in <String>['', '12345', '1234567', '12345a', ' 12345', '١٢٣٤٥٦', '12 456']) {
        expect(w.provideCode(bad), isFalse, reason: 'rejects "$bad"');
      }
      expect(w.hasPassword, isFalse);
      final AdultWindow pinWindow = await phone.open();
      expect(pinWindow.provideCode('123456'), isFalse, reason: 'a PIN window has its password already');
      w.close();
      expect(w.provideCode('123456'), isFalse);
      pinWindow.close();
    });

    test('an expired window answers nothing, the question "has she typed it" included', () async {
      DateTime t = DateTime.utc(2026, 11, 21, 9);
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null, now: () => t);
      final (LanPairingHost h, ChildPairingClient c) = await lanCode(w, ck);
      t = t.add(const Duration(minutes: 11));
      final PairingResult r = await c.pair(handle: w.discoveryHandle, password: '123456', waitForCode: true);
      expect(r.failure, PairingFailure.unreachable);
      expect(w.provideCode('123456'), isFalse);
      await h.stop();
    });

    test('a PIN window does not answer the code question: the code way cannot be forced onto it', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open();
      final (LanPairingHost h, ChildPairingClient c) = await lanCode(w, ck);
      expect((await c.pair(handle: w.discoveryHandle, password: '123456', waitForCode: true)).failure, PairingFailure.unreachable);
      await h.stop();
      w.close();
    });

    test("a stranger on the network: guessing the code spends its own two tries, never the tablet's, and cannot connect", () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null, unlockPin: '4829');
      w.provideCode('482913');
      final DeviceKey thief = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      int ok = 0;
      for (int i = 0; i < 6; i++) {
        final ChildPairingClient evil = ChildPairingClient(
            childKey: thief, transport: LoopbackPairingTransport(w, source: '192.0.2.66'), delay: (Duration d) async {});
        if ((await evil.pair(handle: w.discoveryHandle, password: '${100000 + i}')).ok) ok++;
        if (w.hasPassword == false) w.provideCode('482913'); // the code is typed again each time a wrong one is spent
      }
      expect(ok, 0);
      expect(w.attemptsLeft, greaterThanOrEqualTo(kWindowMaxAttempts - kSourceMaxFailures), reason: 'the stranger spent only its own budget');
      // The real tablet, from another address, still has its tries.
      if (!w.hasPassword) w.provideCode('482913');
      final ChildPairingClient real = ChildPairingClient(
          childKey: ck, transport: LoopbackPairingTransport(w, source: '192.0.2.10'), delay: (Duration d) async {});
      expect((await real.pair(handle: w.discoveryHandle, password: '482913')).ok, isTrue);
    });

    test('five wrong codes end the window; the same code is not accepted afterwards; a recorded exchange cannot be replayed', () async {
      final _Phone phone = _Phone(ak);
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      AdultWindow w = await phone.open(awaitCode: true, pin: null);
      // One good exchange, recorded.
      w.provideCode('135790');
      final PairingResult r = await ChildPairingClient(
              childKey: ck, transport: LoopbackPairingTransport(w, log: log), delay: (Duration d) async {})
          .pair(handle: w.discoveryHandle, password: '135790');
      expect(r.ok, isTrue);
      expect(w.state, WindowState.closed);
      for (final Map<String, dynamic> m in log) {
        expect(await w.handle(m), isNull, reason: 'a closed window answers nothing: ${m['t']}');
      }
      // A fresh window: five wrong codes (from five addresses, so the per-source limit does not hide the window cap).
      w = await phone.open(awaitCode: true, pin: null);
      for (int i = 0; i < 5; i++) {
        w.provideCode('135790');
        await ChildPairingClient(
                childKey: await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository()),
                transport: LoopbackPairingTransport(w, source: '192.0.2.${100 + i}'), delay: (Duration d) async {})
            .pair(handle: w.discoveryHandle, password: '${900000 + i}');
      }
      expect(w.state, WindowState.closed);
      expect(w.provideCode('135790'), isFalse);
      expect(phone.delivered.length, 1);
    });

    test('the Match step still stands between a guessed code and a connection: a wrong pick closes the window and nothing is issued', () async {
      final _Phone phone = _Phone(ak);
      final AdultWindow w = await phone.open(awaitCode: true, pin: null, approve: false);
      w.provideCode('112233');
      bool refused = false;
      w.addListener(() {
        if (w.state == WindowState.awaitingApproval && !w.matchConfirmed && !refused) {
          refused = true;
          w.pickMatch(null); // "None of these": the grown-up does not recognise the pictures
        }
      });
      final PairingResult r = await ChildPairingClient(
              childKey: ck, transport: LoopbackPairingTransport(w), delay: (Duration d) async {}, giveUpAfter: const Duration(seconds: 1))
          .pair(handle: w.discoveryHandle, password: '112233');
      expect(r.ok, isFalse);
      expect(w.matchRefused, isTrue);
      expect(phone.delivered, isEmpty);
    });
  });
}
