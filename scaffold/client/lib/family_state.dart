// OLIVE BRANCH — the family on one device: the ledger it holds, its keys, how a family is founded, and how an
// existing 'local-<fingerprint>' family becomes a ledger-founded one WITHOUT changing any pairing behaviour.
// UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md sections 3,
// 4.1 and 5 (steps 1 and 2), and docs/planning/VILLAGE-WELCOME-DESIGN.md section 9 (PR 2).
//
// NOT WIRED. Nothing in the app calls [FamilyFounder] yet. The live pairing flow (pairing_protocol.dart,
// lan_pairing_transport.dart, the connect screens) still computes `local-<fingerprint>` on the spot and still pins one
// grown-up key; this file changes none of that and none of those files. The wiring is a later wave. Founding takes the
// list of child devices the phone already certified as INPUT and only reads it: the paired-kids record is never
// written, so a device that migrates and then does nothing else behaves exactly as before.
//
// A child device keeps the same ledger and the family key (FK) but never the guardian-only key (GK): the repository
// refuses to store a GK for a keyring that is not a grown-up's, and drops one on load.
import 'dart:math';
import 'dart:typed_data';

import 'device_keys.dart';
import 'family_keys.dart';
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'local_store.dart';
import 'pairing_protocol.dart' show PairedKid;

/// Everything one device keeps about its family. The agreement seed and the keys are secrets: this is stored sealed.
class FamilySnapshot {
  FamilySnapshot({
    required this.entries,
    required this.votes,
    required this.agreementSeed,
    required this.guardianDevice,
    required this.fk,
    required this.gk,
  });
  final List<LedgerEntry> entries;
  final List<LedgerVote> votes;
  final Uint8List agreementSeed;
  final bool guardianDevice;
  final Map<int, Uint8List> fk, gk;
}

abstract class FamilyRepository {
  Future<FamilySnapshot?> load();

  /// True when something is stored under the family record, usable or not. [load] answers null for both "nothing
  /// stored" and "stored but unreadable"; only the first may ever lead to founding a new family.
  Future<bool> hasRecord();

  /// Throws [StateError] if [snapshot] would put a guardian-only key on a device that is not a grown-up's.
  Future<void> save(FamilySnapshot snapshot);
  Future<void> clear();
}

void _refuseGkOnChild(FamilySnapshot s) {
  if (!s.guardianDevice && s.gk.isNotEmpty) throw StateError('a child device never holds the guardian-only key');
}

class MemoryFamilyRepository implements FamilyRepository {
  FamilySnapshot? _s;
  @override
  Future<FamilySnapshot?> load() async => _s;
  @override
  Future<bool> hasRecord() async => _s != null;
  @override
  Future<void> save(FamilySnapshot snapshot) async {
    _refuseGkOnChild(snapshot);
    _s = snapshot;
  }

  @override
  Future<void> clear() async => _s = null;
}

/// Stored in the sealed 'familyledger' area (guardian scope in this wave).
class LocalStoreFamilyRepository implements FamilyRepository {
  LocalStoreFamilyRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'family';

  @override
  Future<bool> hasRecord() async => await _ns.get(_key) != null;

  @override
  Future<FamilySnapshot?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return null;
    try {
      final Object? es = raw['e'], vs = raw['v'], ag = raw['a'], g = raw['g'], fk = raw['fk'], gk = raw['gk'];
      if (es is! List || vs is! List || ag is! String || g is! bool || fk is! Map || gk is! Map) return null;
      final List<LedgerEntry> entries = <LedgerEntry>[];
      for (final Object? e in es) {
        final LedgerEntry? x = await LedgerEntry.fromJson(e);
        if (x != null) entries.add(x);
      }
      final List<LedgerVote> votes = <LedgerVote>[
        for (final Object? v in vs)
          if (LedgerVote.fromJson(v) != null) LedgerVote.fromJson(v)!,
      ];
      final Uint8List seed = unb64(ag);
      if (seed.length != 32 || entries.isEmpty) return null;
      Map<int, Uint8List> keys(Map<dynamic, dynamic> m) {
        final Map<int, Uint8List> out = <int, Uint8List>{};
        for (final MapEntry<dynamic, dynamic> e in m.entries) {
          final int? ep = int.tryParse('${e.key}');
          if (ep == null || ep < 0 || e.value is! String) continue;
          final Uint8List k = unb64(e.value as String);
          if (k.length == 32) out[ep] = k;
        }
        return out;
      }

      return FamilySnapshot(
        entries: entries, votes: votes, agreementSeed: seed, guardianDevice: g, fk: keys(fk),
        // Defence in depth: a guardian-only key found in a child device's record is not used.
        gk: g ? keys(gk) : <int, Uint8List>{},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(FamilySnapshot s) async {
    _refuseGkOnChild(s);
    await _ns.put(_key, <String, Object?>{
      'e': <Object?>[for (final LedgerEntry e in s.entries) e.toJson()],
      'v': <Object?>[for (final LedgerVote v in s.votes) v.toJson()],
      'a': b64(s.agreementSeed),
      'g': s.guardianDevice,
      'fk': <String, Object?>{for (final MapEntry<int, Uint8List> e in s.fk.entries) '${e.key}': b64(e.value)},
      'gk': <String, Object?>{for (final MapEntry<int, Uint8List> e in s.gk.entries) '${e.key}': b64(e.value)},
    });
  }

  /// Also forgets the put-off welcome reminders kept beside the record, so a reset leaves nothing of the family.
  @override
  Future<void> clear() async {
    await _ns.delete(_key);
    await _ns.delete(_remindersKey);
  }

  /// Must match LocalStoreWelcomeReminders.key (welcome_logic.dart); family_state.dart cannot import it without a cycle.
  static const String _remindersKey = 'welcomeasks';
}

/// One device's view of its family: its keys, its ledger, and the anchors it pinned. Immutable apart from the lists.
class FamilyContext {
  FamilyContext({
    required this.device,
    required this.agreement,
    required this.keyring,
    required this.entries,
    required this.votes,
    required this.pin,
  });
  final DeviceKey device;
  final AgreementKey agreement;
  final FamilyKeyring keyring;
  final List<LedgerEntry> entries;
  final List<LedgerVote> votes;
  final FamilyPin pin;

  String get familyId => familyIdString(pin.fid);

  Future<LedgerState> state({required int nowMs}) =>
      reduceLedger(entries: entries, votes: votes, nowMs: nowMs, pin: pin);

  FamilySnapshot snapshot() => FamilySnapshot(
        entries: List<LedgerEntry>.of(entries),
        votes: List<LedgerVote>.of(votes),
        agreementSeed: agreement.seed,
        guardianDevice: keyring.guardianDevice,
        fk: <int, Uint8List>{for (final int e in keyring.fkEpochs) e: keyring.fk(e)!},
        gk: <int, Uint8List>{for (final int e in keyring.gkEpochs) e: keyring.gk(e)!},
      );

  /// Loads a family this device already holds, or null. Fails closed: a record whose ledger no longer reduces to a
  /// family (a missing genesis, a changed genesis) is "no family", never a half-trusted one.
  static Future<FamilyContext?> load(FamilyRepository repo, DeviceKey device, {required int nowMs}) async {
    final FamilySnapshot? s = await repo.load();
    if (s == null) return null;
    final LedgerState st = await reduceLedger(entries: s.entries, votes: s.votes, nowMs: nowMs);
    if (!st.ok) return null;
    final FamilyKeyring ring = FamilyKeyring(guardianDevice: s.guardianDevice);
    s.fk.forEach(ring.putFk);
    if (s.guardianDevice) s.gk.forEach(ring.putGk);
    return FamilyContext(
      device: device, agreement: await AgreementKey.fromSeed(s.agreementSeed), keyring: ring,
      entries: List<LedgerEntry>.of(s.entries), votes: List<LedgerVote>.of(s.votes), pin: st.pin!,
    );
  }
}

/// The `local-<fingerprint>` string the live pairing code computes today for a family (connect_child_screen.dart).
String legacyFamilyId(DeviceKey adult) => 'local-${b64(adult.fingerprint)}';

/// A family record is stored on this device but cannot be used (damaged, cut short, or a ledger that no longer
/// reduces). It is never replaced by a new random family: that would destroy the old ledger and both keys.
class FamilyRecordUnusable extends StateError {
  FamilyRecordUnusable() : super('a family record is stored but cannot be read; not replacing it');
}

class FoundingResult {
  FoundingResult(this.context, this.skippedCertIds);
  final FamilyContext context;

  /// Certificate ids of paired tablets that could not be carried into the ledger (a name or child id that does not
  /// fit, or more than the family size cap). They keep working exactly as before; they are listed, not dropped quietly.
  final List<String> skippedCertIds;
}

class FamilyFounder {
  static String _clean(String s, int max) {
    final StringBuffer b = StringBuffer();
    for (final int c in s.runes) {
      if (c >= 32 && c != 127) b.writeCharCode(c);
    }
    final String t = b.toString().trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  /// Founds a brand-new family on this grown-up's device: a random 128-bit id, a signed genesis, the epoch-0 keys.
  /// No screen, no prompt. [random] and [agreementSeed] exist so a test can make the same family twice.
  static Future<FamilyContext> found({
    required DeviceKey device,
    required String guardianName,
    required int nowMs,
    required FamilyRepository repo,
    Random? random,
    FamilyPolicy policy = const FamilyPolicy(),
    List<String> legacyFids = const <String>[],
  }) async =>
      (await _found(
        device: device, guardianName: guardianName, nowMs: nowMs, repo: repo, random: random, policy: policy,
        legacyFids: legacyFids, kids: const <PairedKid>[],
      ))
          .context;

  /// Founds the ledger family for a grown-up phone that already certified child devices under today's
  /// `local-<fingerprint>` id. The genesis records that id; each paired tablet becomes a `device.add` flagged legacy,
  /// carrying its original issue time. A tablet needs no change and no prompt to keep working: its v1 certificate is
  /// recognised by [acceptsLegacyCert]. Reads [kids]; never writes any pairing record.
  static Future<FoundingResult> foundFromLegacy({
    required DeviceKey adult,
    required String adultName,
    required List<PairedKid> kids,
    required int nowMs,
    required FamilyRepository repo,
    Random? random,
    FamilyPolicy policy = const FamilyPolicy(),
  }) =>
      _found(
        device: adult, guardianName: adultName, nowMs: nowMs, repo: repo, random: random, policy: policy,
        legacyFids: <String>[legacyFamilyId(adult)], kids: kids,
      );

  /// Idempotent: returns the family this device already holds, or founds one. Safe to call on every launch once it is
  /// wired. A device that already has a family is never re-founded, so its family id never changes. If a record is
  /// stored but unusable this throws [FamilyRecordUnusable] and leaves the record exactly as it is.
  static Future<FamilyContext> ensure({
    required DeviceKey device,
    required String guardianName,
    required List<PairedKid> kids,
    required int nowMs,
    required FamilyRepository repo,
    Random? random,
  }) async {
    final FamilyContext? have = await FamilyContext.load(repo, device, nowMs: nowMs);
    if (have != null) return have;
    if (await repo.hasRecord()) throw FamilyRecordUnusable();
    return (await foundFromLegacy(
            adult: device, adultName: guardianName, kids: kids, nowMs: nowMs, repo: repo, random: random))
        .context;
  }

  static Future<FoundingResult> _found({
    required DeviceKey device,
    required String guardianName,
    required int nowMs,
    required FamilyRepository repo,
    required Random? random,
    required FamilyPolicy policy,
    required List<String> legacyFids,
    required List<PairedKid> kids,
  }) async {
    final Random r = random ?? Random.secure();
    Uint8List rb(int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
    final Uint8List fid = rb(16), gid = rb(16), fk = rb(32), gk = rb(32);
    final AgreementKey agree = await AgreementKey.fromSeed(rb(32));
    final String name = _clean(guardianName, 40).isEmpty ? 'Grown-up' : _clean(guardianName, 40);
    final LedgerEntry genesis = await LedgerEntry.sign(device,
        type: EntryType.genesis,
        prev: const <List<int>>[],
        issuedAtMs: nowMs,
        body: <String, Object?>{
          'v': 1,
          'fid': fid,
          'gid': gid,
          'name': name,
          'dev': DeviceRecord(key: device.publicKey, agree: agree.publicKey, cert: await agree.certify(device)).toValue(),
          'policy': policy.toValue(),
          'legacyFids': legacyFids,
          'fkc': await keyCommit('fk', fid, 0, fk),
          'gkc': await keyCommit('gk', fid, 0, gk),
        });
    final List<LedgerEntry> entries = <LedgerEntry>[genesis];
    final List<String> skipped = <String>[];
    final List<PairedKid> ordered = List<PairedKid>.of(kids)..sort((PairedKid a, PairedKid b) => a.certId.compareTo(b.certId));
    int added = 0;
    for (final PairedKid k in ordered) {
      final String cid = _clean(k.childId, 64);
      final String dn = _clean(k.deviceName, 40);
      if (cid.isEmpty || k.childDeviceKey.length != 32 || added >= kMaxChildDevices) {
        skipped.add(k.certId);
        continue;
      }
      entries.add(await LedgerEntry.sign(device,
          type: EntryType.deviceAdd,
          prev: <List<int>>[entries.last.hash],
          issuedAtMs: nowMs,
          body: <String, Object?>{
            'kind': 'child',
            'gid': null,
            'childId': cid,
            'name': dn.isEmpty ? 'Tablet' : dn,
            'dev': DeviceRecord(key: Uint8List.fromList(k.childDeviceKey)).toValue(),
            'legacy': true,
            'orig': k.issuedAtMs < 0 ? 0 : k.issuedAtMs,
          }));
      added++;
    }
    final FamilyKeyring ring = FamilyKeyring(guardianDevice: true)..putFk(0, fk)..putGk(0, gk);
    final FamilyContext ctx = FamilyContext(
      device: device, agreement: agree, keyring: ring, entries: entries, votes: <LedgerVote>[],
      pin: FamilyPin(fid, genesis.hash),
    );
    await repo.save(ctx.snapshot());
    return FoundingResult(ctx, skipped);
  }
}

/// True when a v1 pairing certificate is still good for this ledger family: it names a family id the genesis recorded
/// as legacy, the grown-up key it names is an active grown-up device, it verifies under that key, and the child
/// device it names is an active child device of the same child. A tampered family id fails. Nothing is accepted that
/// the same grown-up key did not already sign.
Future<bool> acceptsLegacyCert(LedgerState state, PairingCert cert) async {
  if (!state.ok || !state.recognisesLegacyFid(cert.familyId)) return false;
  final LedgerDevice? child = state.deviceFor(cert.childDeviceKey);
  if (child == null || child.kind != 'child' || child.childId != cert.childId) return false;
  for (final LedgerDevice d in state.devices) {
    if (d.kind != 'guardian') continue;
    if (!bytesEqual(await fingerprintOf(d.key), cert.adultFingerprint)) continue;
    return cert.verifiedBy(d.key);
  }
  return false;
}
