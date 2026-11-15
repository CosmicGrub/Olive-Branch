// OLIVE BRANCH — pairing hardening, part 2: certificates expire and are renewed at a meeting with the grown-up's phone;
// "Stop" and "Forget" reach the tablet at its next contact and it stops honouring its pairing; and every such meeting
// is a live "keeping watch" contact (TrustBook.observe: a changed key pauses, the 60-day prompt is measured from it).
// Hostile cases for each. UNVERIFIED until CI runs it; fake clocks, real signatures, no sockets.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';
import 'package:olive_client/unlock_challenge.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

class _Clock {
  DateTime t = DateTime.utc(2026, 11, 14, 9);
  DateTime call() => t;
  int get ms => t.millisecondsSinceEpoch;
  void add(Duration d) => t = t.add(d);
}

class _World {
  _World(this.ak, this.ck, this.clock, this.trust, this.kid, this.cert);
  final DeviceKey ak, ck;
  final _Clock clock;
  final TrustBook trust;
  final PairedKid kid;
  PairingCert cert;
  final List<PairingCert> renewed = <PairingCert>[];
  int revoked = 0, phoneOnly = 0, forgotten = 0;
  late ChildUnlockHost host = _host(cert);
  late UnlockResponder phone = _phone(ak);

  ChildUnlockHost _host(PairingCert c, {DeviceKey? childKey, Uint8List? adultPub}) => ChildUnlockHost(
        childKey: childKey ?? ck,
        adultKey: adultPub ?? ak.publicKey,
        cert: c,
        now: clock.call,
        onRenewed: (PairingCert n) async {
          cert = n;
          renewed.add(n);
        },
        onRevoked: () async => revoked++,
        onPhoneOnly: () async => phoneOnly++,
        onForget: () async => forgotten++,
      );

  UnlockResponder _phone(DeviceKey adult, {bool withTrust = true, String? familyId = 'fam-1', List<PairedKid>? kids}) => UnlockResponder(
        adultKey: adult,
        kids: () async => kids ?? <PairedKid>[kid],
        now: clock.call,
        trust: withTrust ? trust : null,
        familyId: familyId,
      );

  /// The tablet shows a signed challenge; the phone inspects it. Returns the phone's view and the challenge.
  Future<(ChallengeView?, UnlockChallenge)> show({UnlockPurpose purpose = UnlockPurpose.unlock, ChildUnlockHost? h, UnlockResponder? p}) async {
    final ChildUnlockHost hh = h ?? host;
    hh.issue(purpose);
    final UnlockChallenge c = (await hh.proveOutstanding())!;
    return ((await (p ?? phone).inspect(c.toQr())), c);
  }
}

Future<_World> _world({int certDays = 180, bool withExp = true}) async {
  final DeviceKey ak = await _key(), ck = await _key();
  final _Clock clock = _Clock();
  final PairingCert cert = await PairingCert.issue(ak,
      childDeviceKey: ck.publicKey, familyId: 'fam-1', childId: 'kid', certId: 'c1', issuedAtMs: clock.ms,
      expiresAtMs: withExp ? clock.ms + Duration(days: certDays).inMilliseconds : null);
  final PairedKid kid = PairedKid(certId: 'c1', childDeviceKey: ck.publicKey, childId: 'kid', deviceName: 'Ivy tablet', issuedAtMs: clock.ms, phoneOnly: true);
  final TrustBook trust = TrustBook(MemoryTrustRepository(), now: clock.call);
  await trust.add(certId: 'c1', deviceKey: ck.publicKey, deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam');
  return _World(ak, ck, clock, trust, kid, cert);
}

void main() {
  group('certificate expiry', () {
    test('a v2 certificate verifies; its end date cannot be stripped, changed or added to a v1 certificate', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final PairingCert v2 = await PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'c', certId: 'x', issuedAtMs: 1000, expiresAtMs: 5000);
      expect(await v2.verifiedBy(ak.publicKey), isTrue);
      expect(v2.isExpired(4999), isFalse);
      expect(v2.isExpired(5000), isTrue);
      // Stripped: the JSON without exp is read as a v1 certificate and the v2 signature does not verify as v1.
      final Map<String, Object?> j = v2.toJson()..remove('exp');
      expect(await PairingCert.fromJson(j)!.verifiedBy(ak.publicKey), isFalse);
      // Extended.
      final Map<String, Object?> j2 = v2.toJson()..['exp'] = 999999999;
      expect(await PairingCert.fromJson(j2)!.verifiedBy(ak.publicKey), isFalse);
      // A v1 certificate with an end date bolted on.
      final PairingCert v1 = await PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'c', certId: 'x', issuedAtMs: 1000);
      expect(await v1.verifiedBy(ak.publicKey), isTrue);
      expect(v1.expiresAtMs, isNull);
      expect(v1.isExpired(1 << 50), isFalse, reason: 'a v1 certificate has no end date of its own (see the grace below)');
      final Map<String, Object?> j3 = v1.toJson()..['exp'] = 1;
      expect(await PairingCert.fromJson(j3)!.verifiedBy(ak.publicKey), isFalse);
      // An end date that is not a number is a damaged certificate.
      expect(PairingCert.fromJson(v2.toJson()..['exp'] = 'soon'), isNull);
    });

    test('approve() issues a certificate that ends 180 days after it was issued', () async {
      final DeviceKey ak = await _key(), ck = await _key();
      final _Clock clock = _Clock();
      final AdultWindow w = await AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'fam-1', childId: 'kid-1', childName: 'Ivy', pin: '4829', now: clock.call);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult r = await ChildPairingClient(childKey: ck, transport: LoopbackPairingTransport(w), delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3))
          .pair(sid: w.sid, password: '4829');
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(r.pairing!.cert.expiresAtMs, clock.ms + kCertLifetime.inMilliseconds);
      expect(r.pairing!.isLapsed(clock.ms), isFalse);
      expect(r.pairing!.isLapsed(clock.ms + kCertLifetime.inMilliseconds), isTrue);
    });

    test('a lapsed pairing is lapsed on the tablet clock; a legacy one uses its grace', () async {
      final _World w = await _world(withExp: false);
      final ChildPairing legacy = ChildPairing(cert: w.cert, adultKey: w.ak.publicKey, adultName: 'M', childName: 'I', unlockVerifier: null, graceUntilMs: w.clock.ms + 1000);
      expect(legacy.isLapsed(w.clock.ms), isFalse);
      expect(legacy.isLapsed(w.clock.ms + 1000), isTrue);
      final ChildPairing noGrace = ChildPairing(cert: w.cert, adultKey: w.ak.publicKey, adultName: 'M', childName: 'I', unlockVerifier: null);
      expect(noGrace.isLapsed(1 << 50), isFalse, reason: 'cannot judge a legacy certificate with no grace recorded yet');
    });

    test('migration: a pairing made before expiry gets a fixed grace on first load, remembered, and not extended by restarts', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final _Clock clock = _Clock();
      ChildPairingRepository repo() => LocalStoreChildPairingRepository(s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock')), now: clock.call);
      final DeviceKey ak = await _key(), ck = await _key();
      final PairingCert v1 = await PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'kid', certId: 'x', issuedAtMs: 1);
      await repo().save(ChildPairing(cert: v1, adultKey: ak.publicKey, adultName: 'Mom', childName: 'Ivy', unlockVerifier: null));
      final ChildPairing first = (await repo().load())!;
      expect(first.graceUntilMs, clock.ms + kLegacyCertGrace.inMilliseconds);
      clock.add(const Duration(days: 40));
      final ChildPairing second = (await repo().load())!;
      expect(second.graceUntilMs, first.graceUntilMs, reason: 'restarting the app does not restart the grace');
      clock.add(const Duration(days: 60));
      expect((await repo().load())!.isLapsed(clock.ms), isTrue);
      // A renewal replaces the certificate and ends the grace.
      final PairingCert renewed = await v1.renewed(ak, clock.ms + kCertLifetime.inMilliseconds);
      await (repo() as LocalStoreChildPairingRepository).replaceCert(renewed);
      final ChildPairing after = (await repo().load())!;
      expect(after.graceUntilMs, isNull);
      expect(after.cert.expiresAtMs, renewed.expiresAtMs);
      expect(after.isLapsed(clock.ms), isFalse);
    });

    test('a stored renewal that does not verify under the pinned adult key is "not paired" (fails closed)', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      ChildPairingRepository repo() => LocalStoreChildPairingRepository(s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock')));
      final DeviceKey ak = await _key(), ck = await _key(), thief = await _key();
      final PairingCert good = await PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'kid', certId: 'x', issuedAtMs: 1, expiresAtMs: 10);
      await repo().save(ChildPairing(cert: good, adultKey: ak.publicKey, adultName: 'Mom', childName: 'Ivy', unlockVerifier: null));
      final PairingCert forged = await good.renewed(thief, 1 << 50);
      await (repo() as LocalStoreChildPairingRepository).replaceCert(forged);
      expect(await repo().load(), isNull);
    });
  });

  group('renewal at a meeting with the phone', () {
    test('within 90 days of the end the grant carries a renewed certificate; the tablet keeps it', () async {
      final _World w = await _world(certDays: 60);
      final (ChallengeView? v, _) = await w.show();
      expect(v!.verdict, UnlockVerdict.ok);
      expect(v.renewToMs, w.clock.ms + kCertLifetime.inMilliseconds);
      expect(await w.host.accept(await w.phone.grant(v)), isTrue);
      expect(w.renewed.single.expiresAtMs, w.clock.ms + kCertLifetime.inMilliseconds);
      expect(await w.renewed.single.verifiedBy(w.ak.publicKey), isTrue);
    });

    test('far from the end nothing is renewed', () async {
      final _World w = await _world(certDays: 170);
      final (ChallengeView? v, _) = await w.show();
      expect(v!.renewToMs, isNull);
      expect(await w.host.accept(await w.phone.grant(v)), isTrue);
      expect(w.renewed, isEmpty);
    });

    test('a LAPSED tablet is still unlocked by the phone, and the same meeting renews it', () async {
      final _World w = await _world(certDays: 10);
      w.clock.add(const Duration(days: 20));
      final (ChallengeView? v, _) = await w.show();
      expect(await w.host.accept(await w.phone.grant(v!)), isTrue);
      expect(w.renewed, hasLength(1));
      expect(w.renewed.single.isExpired(w.clock.ms), isFalse);
    });

    test('a legacy (v1) certificate is upgraded at its first meeting', () async {
      final _World w = await _world(withExp: false);
      final (ChallengeView? v, UnlockChallenge c) = await w.show();
      expect(c.certExpiresMs, isNull);
      expect(await w.host.accept(await w.phone.grant(v!)), isTrue);
      expect(w.renewed.single.expiresAtMs, isNotNull);
    });

    test('a phone with no family id never renews (it could not reproduce the certificate)', () async {
      final _World w = await _world(certDays: 5);
      final UnlockResponder p = w._phone(w.ak, familyId: null);
      final (ChallengeView? v, _) = await w.show(p: p);
      expect(v!.renewToMs, isNull);
      expect(await w.host.accept(await p.grant(v)), isTrue);
      expect(w.renewed, isEmpty);
    });

    test('hostile: a tampered renewal signature, a bumped end date, or another adult\'s signature is ignored (the unlock itself still works)', () async {
      for (final String attack in <String>['sig', 'date', 'otherAdult']) {
        final _World w = await _world(certDays: 5);
        final (ChallengeView? v, _) = await w.show();
        final Uri g = Uri.parse(await w.phone.grant(v!));
        final Map<String, String> q = Map<String, String>.of(g.queryParameters);
        if (attack == 'sig') {
          final Uint8List s = unb64(q['cs']!);
          s[3] ^= 1;
          q['cs'] = b64(s);
        } else if (attack == 'date') {
          q['x'] = '${int.parse(q['x']!) + 1000}';
        } else {
          final DeviceKey mallory = await _key();
          q['cs'] = b64((await w.cert.renewed(mallory, int.parse(q['x']!))).signature);
        }
        expect(await w.host.accept(Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: q).toString()), isTrue, reason: attack);
        expect(w.renewed, isEmpty, reason: attack);
      }
    });

    test('hostile: an OLDER renewal replayed later does not move the end date backwards', () async {
      final _World w = await _world(certDays: 5);
      final (ChallengeView? v, _) = await w.show();
      final String first = await w.phone.grant(v!);
      expect(await w.host.accept(first), isTrue);
      final int have = w.cert.expiresAtMs!;
      // A second tablet challenge gets the replayed renewal values inside a fresh, valid grant.
      w.clock.add(const Duration(days: 100));
      final (ChallengeView? v2, UnlockChallenge c2) = await w.show();
      final Uri fresh = Uri.parse(await w.phone.grant(v2!));
      final Map<String, String> q = Map<String, String>.of(fresh.queryParameters);
      final Uri old = Uri.parse(first);
      q['x'] = old.queryParameters['x']!;
      q['cs'] = old.queryParameters['cs']!;
      expect(c2.nonce, isNotEmpty);
      final int before = w.renewed.length;
      await w.host.accept(Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: q).toString());
      expect(w.renewed.length, before, reason: 'the old end date is not newer than the one held');
      expect(w.cert.expiresAtMs, greaterThanOrEqualTo(have));
    });

    test('a renewal never rides on a "disconnect" request, and a renewal alone (no valid grant) is nothing', () async {
      final _World w = await _world(certDays: 5);
      final (ChallengeView? v, _) = await w.show(purpose: UnlockPurpose.forget);
      final Uri g = Uri.parse(await w.phone.grant(v!));
      expect(g.queryParameters.containsKey('x'), isFalse);
      // Strip 's' from a normal grant: the tablet refuses everything.
      final (ChallengeView? v2, _) = await w.show();
      final Map<String, String> q = Map<String, String>.of(Uri.parse(await w.phone.grant(v2!)).queryParameters)..remove('s');
      expect(await w.host.accept(Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: q).toString()), isFalse);
      expect(w.renewed, isEmpty);
    });
  });

  group('revocation reaches the tablet at its next meeting with the phone', () {
    test('after Stop the phone answers with a signed notice, never an unlock; the tablet drops its pairing', () async {
      final _World w = await _world();
      expect(await w.trust.stop('c1'), isTrue);
      final (ChallengeView? v, _) = await w.show(p: w._phone(w.ak, kids: <PairedKid>[])); // Stop also forgets the kid
      expect(v!.verdict, UnlockVerdict.revoked);
      final String notice = await w.phone.grant(v);
      expect(Uri.parse(notice).queryParameters.containsKey('s'), isFalse, reason: 'no unlock signature in a revocation');
      expect(await w.host.accept(notice), isFalse, reason: 'a notice never unlocks');
      expect(w.revoked, 1);
      expect(w.phoneOnly + w.forgotten, 0);
    });

    test('after Forget the key is refused too, and the tablet is told', () async {
      final _World w = await _world();
      await w.trust.forget(w.ck.publicKey, who: 'Ivy tablet');
      expect(await w.trust.isRevoked(w.ck.publicKey), isTrue);
      expect(await w.trust.isRefused(w.ck.publicKey), isFalse, reason: 'forgetting is not the same as turning it away for good');
      final (ChallengeView? v, _) = await w.show(p: w._phone(w.ak, kids: <PairedKid>[]));
      expect(v!.verdict, UnlockVerdict.revoked);
      expect(await w.host.accept(await w.phone.grant(v)), isFalse);
      expect(w.revoked, 1);
      expect((await w.trust.repo.load()).history.last.kind, HistoryKind.forgot);
      expect(await w.trust.historyIntact(), isTrue);
    });

    test('even a tablet that forgot its certificate details (an older build, no proof) is told, by key fingerprint', () async {
      final _World w = await _world();
      await w.trust.forget(w.ck.publicKey);
      final ChildUnlockHost legacy = ChildUnlockHost(childKey: w.ck, adultKey: w.ak.publicKey, now: w.clock.call, onRevoked: () async => w.revoked++);
      final UnlockChallenge c = legacy.issue(UnlockPurpose.unlock);
      expect(c.hasProof, isFalse);
      final ChallengeView? v = await w.phone.inspect(c.toQr());
      expect(v!.verdict, UnlockVerdict.revoked);
      expect(await legacy.accept(await w.phone.grant(v)), isFalse);
      expect(w.revoked, 1);
    });

    test('hostile: a notice signed by someone else, a replayed notice, or one meant for another tablet changes nothing', () async {
      final _World w = await _world();
      await w.trust.forget(w.ck.publicKey);
      final DeviceKey mallory = await _key();
      final (ChallengeView? v, _) = await w.show();
      expect(v!.verdict, UnlockVerdict.revoked);
      final String real = await w.phone.grant(v);

      // 1. signed by another key
      final UnlockResponder fake = UnlockResponder(adultKey: mallory, kids: () async => <PairedKid>[], now: w.clock.call, trust: w.trust);
      final (ChallengeView? fv, _) = await w.show(p: fake);
      expect(await w.host.accept(await fake.grant(fv!)), isFalse);
      expect(w.revoked, 0);

      // 2. replay of an earlier genuine notice against a new challenge
      final (ChallengeView? v2, _) = await w.show();
      expect(v2, isNotNull);
      expect(await w.host.accept(real), isFalse);
      expect(w.revoked, 0);

      // 3. a genuine notice for tablet A offered to tablet B (different key, different outstanding nonce)
      final DeviceKey other = await _key();
      final ChildUnlockHost b = w._host(w.cert, childKey: other);
      b.issue(UnlockPurpose.unlock);
      expect(await b.accept(real), isFalse);
      expect(w.revoked, 0);

      // 4. no signature at all
      final (ChallengeView? v3, UnlockChallenge c3) = await w.show();
      expect(v3, isNotNull);
      expect(await w.host.accept(Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: <String, String>{'n': b64(c3.nonce), 'rv': '1'}).toString()), isFalse);
      expect(w.revoked, 0);
    });

    test('a forgotten tablet connected again on purpose is no longer treated as disconnected', () async {
      final _World w = await _world();
      await w.trust.forget(w.ck.publicKey);
      await w.trust.add(certId: 'c2', deviceKey: w.ck.publicKey, deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam');
      expect(await w.trust.isRevoked(w.ck.publicKey), isFalse);
    });

    test('a STOPPED tablet stays turned away even if it is added again by accident', () async {
      final _World w = await _world();
      await w.trust.stop('c1');
      expect(await w.trust.add(certId: 'c2', deviceKey: w.ck.publicKey, deviceName: 'x', role: PairedRole.child, addedBy: 'Sam'), isNull);
      expect(await w.trust.isRefused(w.ck.publicKey), isTrue);
    });

    test('forgetting is idempotent and survives a reload of the book', () async {
      final _World w = await _world();
      await w.trust.forget(w.ck.publicKey, who: 'a');
      await w.trust.forget(w.ck.publicKey, who: 'a');
      expect((await w.trust.repo.load()).history.where((HistoryEntry e) => e.kind == HistoryKind.forgot), hasLength(1));
      final TrustBook again = TrustBook(w.trust.repo, now: w.clock.call);
      expect(await again.isRevoked(w.ck.publicKey), isTrue);
    });

    test('the local store keeps the forgotten list across a restart', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final DeviceKey ck = await _key();
      await TrustBook(LocalStoreTrustRepository(s.area('trust', ownerId: kLocalGuardianScope))).forget(ck.publicKey);
      expect(await TrustBook(LocalStoreTrustRepository(s.area('trust', ownerId: kLocalGuardianScope))).isRevoked(ck.publicKey), isTrue);
    });
  });

  group('every meeting is a live keeping-watch contact (TrustBook.observe)', () {
    test('the 60-day "still yours?" prompt is measured from the last meeting, and a meeting resets it', () async {
      final _World w = await _world();
      w.clock.add(const Duration(days: 61));
      expect((await w.trust.devices()).single.needsStillYours(w.clock.ms), isTrue);
      final (ChallengeView? v, _) = await w.show();
      expect(v!.verdict, UnlockVerdict.ok);
      expect((await w.trust.devices()).single.needsStillYours(w.clock.ms), isFalse);
      expect((await w.trust.devices()).single.lastContactMs, w.clock.ms);
    });

    test('a tablet that proves a DIFFERENT key for the same certificate is paused, never granted, and recorded', () async {
      final _World w = await _world();
      final DeviceKey impostor = await _key();
      // The impostor holds a copy of the certificate and signs with its own key.
      final ChildUnlockHost h = w._host(w.cert, childKey: impostor);
      final (ChallengeView? v, _) = await w.show(h: h);
      expect(v!.verdict, UnlockVerdict.paused);
      expect(v.pausedName, 'Ivy tablet');
      await expectLater(w.phone.grant(v), throwsStateError);
      final TrustedDevice d = (await w.trust.devices()).single;
      expect(d.status, TrustStatus.paused);
      expect((await w.trust.repo.load()).history.last.kind, HistoryKind.paused);
      // The real tablet is paused too until the grown-up reconnects it: nothing slips through afterwards.
      final (ChallengeView? again, _) = await w.show();
      expect(again!.verdict, UnlockVerdict.paused);
    });

    test('hostile: a forged or damaged proof gets nothing and does not touch the book', () async {
      final _World w = await _world();
      w.clock.add(const Duration(days: 30));
      final ChildUnlockHost h = w._host(w.cert);
      h.issue(UnlockPurpose.unlock);
      final UnlockChallenge c = (await h.proveOutstanding())!;
      final Map<String, String> q = Map<String, String>.of(Uri.parse(c.toQr()).queryParameters);
      Future<void> expectNothing(Map<String, String> m, String why) async {
        expect(await w.phone.inspect(Uri(scheme: 'olive', host: 'unlock', path: '/1', queryParameters: m).toString()), isNull, reason: why);
      }

      await expectNothing(<String, String>{...q, 'e': '${int.parse(q['e']!) + 1}'}, 'expiry changed after signing');
      await expectNothing(<String, String>{...q, 'p': 'forget'}, 'purpose changed after signing');
      await expectNothing(<String, String>{...q, 'i': 'c2'}, 'certificate id changed after signing');
      await expectNothing(<String, String>{...q, 'x': '5'}, 'end date changed after signing');
      await expectNothing(<String, String>{...q, 'n': b64(Uint8List(16))}, 'nonce changed after signing');
      final DeviceKey other = await _key();
      await expectNothing(<String, String>{...q, 'k': b64(other.publicKey)}, 'someone else\'s key under this fingerprint');
      await expectNothing(<String, String>{...q}..remove('cs'), 'half a proof');
      await expectNothing(<String, String>{...q}..remove('k'), 'half a proof');
      await expectNothing(<String, String>{...q, 'cs': b64(Uint8List(10))}, 'short signature');
      expect((await w.trust.devices()).single.lastContactMs, isNot(w.clock.ms), reason: 'none of that counted as a meeting');
      expect((await w.trust.devices()).single.status, TrustStatus.active);
    });

    test('a tablet from before the proof existed is answered as before, but it is not a "meeting" (nothing proved)', () async {
      final _World w = await _world();
      final int before = (await w.trust.devices()).single.lastContactMs;
      w.clock.add(const Duration(days: 30));
      final ChildUnlockHost legacy = ChildUnlockHost(childKey: w.ck, adultKey: w.ak.publicKey, now: w.clock.call);
      final UnlockChallenge c = legacy.issue(UnlockPurpose.unlock);
      final ChallengeView? v = await w.phone.inspect(c.toQr());
      expect(v!.verdict, UnlockVerdict.ok);
      expect(v.renewToMs, isNull, reason: 'an unproved tablet is never renewed');
      expect(await legacy.accept(await w.phone.grant(v)), isTrue);
      expect((await w.trust.devices()).single.lastContactMs, before);
    });

    test('a tablet the phone never connected gets no answer, proved or not', () async {
      final _World w = await _world();
      final DeviceKey stranger = await _key();
      final PairingCert theirs = await PairingCert.issue(w.ak, childDeviceKey: stranger.publicKey, familyId: 'fam-1', childId: 'kid', certId: 'zz', issuedAtMs: 1);
      final (ChallengeView? v, _) = await w.show(h: w._host(theirs, childKey: stranger));
      expect(v, isNull);
    });

    test('the proved challenge still fits comfortably in a scannable picture', () async {
      final _World w = await _world();
      w.host.issue(UnlockPurpose.unlock);
      final UnlockChallenge c = (await w.host.proveOutstanding())!;
      expect(c.hasProof, isTrue);
      expect(await c.proofValid(), isTrue);
      expect(c.toQr().length, lessThan(450));
    });

    test('proving a challenge keeps its one-time nonce, and a newer challenge replaces the older one', () async {
      final _World w = await _world();
      final UnlockChallenge plain = w.host.issue(UnlockPurpose.unlock);
      final UnlockChallenge proved = (await w.host.proveOutstanding())!;
      expect(proved.nonce, plain.nonce);
      final (ChallengeView? v, _) = (await w.phone.inspect(proved.toQr()), proved);
      final String grant = await w.phone.grant(v!);
      w.host.issue(UnlockPurpose.unlock); // the tablet moved on
      expect(await w.host.accept(grant), isFalse);
    });
  });

  group('the tablet side of the store', () {
    test('a typed-code verifier is absent from a default pairing; opting out of phone-only is only by an explicit pairing choice', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final DeviceKey ak = await _key(), ck = await _key();
      final _Clock clock = _Clock();
      final AdultWindow w = await AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'fam-1', childId: 'kid-1', childName: 'Ivy', pin: '4829', now: clock.call);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final PairingResult r = await ChildPairingClient(childKey: ck, transport: LoopbackPairingTransport(w), delay: (Duration d) async {}, pollEvery: const Duration(seconds: 1), giveUpAfter: const Duration(seconds: 3))
          .pair(sid: w.sid, password: '4829');
      final LocalStorePinRepoProbe probe = LocalStorePinRepoProbe(s);
      await LocalStoreChildPairingRepository(s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock'))).save(r.pairing!);
      expect(await probe.verifierPresent(), isFalse, reason: 'nothing on the tablet can be brute-forced offline');
      expect((await LocalStoreChildPairingRepository(s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock'))).load())!.phoneOnly, isTrue);
    });

    test('migration of a tablet that already holds a verifier is explicit: it keeps working until the phone sends the phone-only flag', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final DeviceKey ak = await _key(), ck = await _key();
      final PairingCert cert = await PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'kid', certId: 'x', issuedAtMs: 1, expiresAtMs: 1 << 50);
      final LocalPinService setup = LocalPinService(LocalStoreLocalPinRepository(s.area('adultunlock')), iterations: 2);
      await setup.setPin('4829');
      final LocalStoreChildPairingRepository repo = LocalStoreChildPairingRepository(s.area('childpairing'), LocalStoreLocalPinRepository(s.area('adultunlock')));
      await repo.save(ChildPairing(cert: cert, adultKey: ak.publicKey, adultName: 'Mom', childName: 'Ivy', unlockVerifier: await LocalStoreLocalPinRepository(s.area('adultunlock')).load()));
      expect((await repo.load())!.phoneOnly, isFalse, reason: 'nothing changes silently');
      await repo.makePhoneOnly();
      final ChildPairing after = (await repo.load())!;
      expect(after.phoneOnly, isTrue);
      expect(await LocalStoreLocalPinRepository(s.area('adultunlock')).load(), isNull, reason: 'the verifier is gone, not just hidden');
    });
  });
}

class LocalStorePinRepoProbe {
  LocalStorePinRepoProbe(this.s);
  final LocalServices s;
  Future<bool> verifierPresent() async => (await LocalStoreLocalPinRepository(s.area('adultunlock')).load()) != null;
}
