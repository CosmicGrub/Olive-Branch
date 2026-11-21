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
}
