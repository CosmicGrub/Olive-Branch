// OLIVE BRANCH — what the adult device does AFTER a pairing: who the device is (the adult's choice, never the device's),
// the "New" period (settle in), keeping watch (a changed key pauses the connection, "still yours?" after 60 days, a
// one-tap stop), the short refusal lock after a miss, and a plain-language history that is append-only and
// hash-chained. UNVERIFIED on a device; pure logic with injected clocks, headless in CI
// (client/test/pairing_trust_test.dart). Design: docs/planning/PERSISTENT-QR-PAIRING.md layers 4 and 5, J16-J18.
//
// HONEST LIMITS (do not overclaim in any screen):
//  - Every clock here is the ADULT device's clock. A child device's clock is never trusted for anything.
//  - "Stopped" works on the adult side: the key is refused from then on. A child tablet that is offline keeps its
//    certificate and what is on it until it next meets a family device; nothing here wipes it.
//  - The history is tamper-EVIDENT (a removed, reordered or edited line breaks the chain), not tamper-proof: the
//    owner of the adult device can rewrite the whole file.
//  - "Settle in" is a badge plus limits on the adult side (a New device cannot add or approve others). A child
//    tablet has no family setting this layer can restrict.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'device_keys.dart';
import 'local_store.dart';

/// Who a device is. Only the adult chooses; a device can never claim a role. v1 builds [child] only.
enum PairedRole { child, grownUp, helper }

enum TrustStatus { active, paused, stopped }

/// How long a newly added device stays "New". 0 turns the period off.
enum SettleIn { none, day, threeDays }

Duration settleDuration(SettleIn s) => switch (s) {
      SettleIn.none => Duration.zero,
      SettleIn.day => const Duration(hours: 24),
      SettleIn.threeDays => const Duration(days: 3),
    };

const Duration kStillYoursAfter = Duration(days: 60);
const Duration kAddingLockAfterMiss = Duration(minutes: 10);

/// Hostile device names (a stranger's device can send any text): control characters, bidirectional overrides and
/// zero-width characters are removed, whitespace is collapsed, the length is capped, and an empty result becomes
/// "Unknown device". The adult can rename it; this is what shows until then.
String sanitizeDeviceName(Object? raw, {int max = 32}) {
  if (raw is! String) return 'Unknown device';
  final StringBuffer b = StringBuffer();
  for (final int r in raw.runes) {
    final bool control = r < 0x20 || (r >= 0x7f && r <= 0x9f);
    final bool bidi = (r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) || r == 0x200e || r == 0x200f || r == 0x061c;
    final bool invisible = (r >= 0x200b && r <= 0x200d) || r == 0x2060 || r == 0xfeff || r == 0xad;
    if (control || bidi || invisible) {
      if (r == 0x09 || r == 0x20) b.write(' ');
      continue;
    }
    b.writeCharCode(r);
  }
  String s = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.runes.length > max) s = String.fromCharCodes(s.runes.take(max)).trim();
  return s.isEmpty ? 'Unknown device' : s;
}

/// One device the adult added. Keyed by its certificate id; its Ed25519 public key is pinned.
class TrustedDevice {
  const TrustedDevice({
    required this.certId,
    required this.deviceKey,
    required this.name,
    required this.role,
    required this.addedAtMs,
    required this.addedBy,
    required this.noviceUntilMs,
    required this.lastContactMs,
    this.status = TrustStatus.active,
  });

  final String certId, name, addedBy;
  final Uint8List deviceKey;
  final PairedRole role;
  final int addedAtMs, noviceUntilMs, lastContactMs;
  final TrustStatus status;

  bool isNew(int nowMs) => status == TrustStatus.active && nowMs < noviceUntilMs;
  Duration newTimeLeft(int nowMs) => isNew(nowMs) ? Duration(milliseconds: noviceUntilMs - nowMs) : Duration.zero;

  /// "Is this device still yours?" at 60 days without contact.
  bool needsStillYours(int nowMs) =>
      status == TrustStatus.active && nowMs - lastContactMs >= kStillYoursAfter.inMilliseconds;

  /// A New device cannot add or approve other devices; a paused or stopped one cannot either.
  bool mayApproveOthers(int nowMs) => status == TrustStatus.active && !isNew(nowMs) && role != PairedRole.child;

  TrustedDevice copyWith({String? name, int? noviceUntilMs, int? lastContactMs, TrustStatus? status}) => TrustedDevice(
        certId: certId, deviceKey: deviceKey, name: name ?? this.name, role: role, addedAtMs: addedAtMs, addedBy: addedBy,
        noviceUntilMs: noviceUntilMs ?? this.noviceUntilMs, lastContactMs: lastContactMs ?? this.lastContactMs,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': certId, 'k': b64(deviceKey), 'n': name, 'r': role.name, 'at': addedAtMs, 'by': addedBy,
        'nu': noviceUntilMs, 'lc': lastContactMs, 's': status.name,
      };

  static TrustedDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return TrustedDevice(
        certId: j['id'] as String,
        deviceKey: unb64(j['k'] as String),
        name: sanitizeDeviceName(j['n']),
        role: PairedRole.values.byName(j['r'] as String),
        addedAtMs: j['at'] as int,
        addedBy: (j['by'] as String?) ?? '',
        noviceUntilMs: j['nu'] as int,
        lastContactMs: j['lc'] as int,
        status: TrustStatus.values.byName(j['s'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

enum HistoryKind { opened, added, refusedOtherFamily, refusedMatch, refusedNotMine, paused, stillYours, stopped, newCode, adultStopped }

/// The history line in plain words, written for a parent. Never the words key, certificate or fingerprint.
String describeHistory(HistoryKind k, String who) => switch (k) {
      HistoryKind.opened => 'You turned on adding devices.',
      HistoryKind.added => '$who was added.',
      HistoryKind.refusedOtherFamily => 'A picture from a different family was refused. Nothing was shared.',
      HistoryKind.refusedMatch => 'The pictures did not match, so nothing was added.',
      HistoryKind.refusedNotMine => 'You said it was not yours. Nothing was added.',
      HistoryKind.paused => '$who changed, so the connection is paused until you check it.',
      HistoryKind.stillYours => 'You confirmed $who is still yours.',
      HistoryKind.stopped => 'You stopped the connection with $who.',
      HistoryKind.newCode => 'You made a new code. Old copies stopped working.',
      HistoryKind.adultStopped => 'Adding devices was turned off.',
    };

class HistoryEntry {
  const HistoryEntry({required this.seq, required this.atMs, required this.kind, required this.who, required this.prev, required this.hash});
  final int seq, atMs;
  final HistoryKind kind;
  final String who;
  final String prev, hash;

  String get text => describeHistory(kind, who);

  Map<String, Object?> toJson() => <String, Object?>{'q': seq, 't': atMs, 'k': kind.name, 'w': who, 'p': prev, 'h': hash};

  static HistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return HistoryEntry(
          seq: j['q'] as int, atMs: j['t'] as int, kind: HistoryKind.values.byName(j['k'] as String),
          who: j['w'] as String, prev: j['p'] as String, hash: j['h'] as String);
    } catch (_) {
      return null;
    }
  }
}

Future<String> _entryHash(int seq, int atMs, HistoryKind kind, String who, String prev) async {
  final Hash h = await Sha256().hash(utf8.encode('olive-history/1|$seq|$atMs|${kind.name}|$who|$prev'));
  return b64(h.bytes);
}

const String kHistoryGenesis = 'genesis';

/// Append-only list whose entries each carry the hash of the one before. [verify] fails for a removed, reordered,
/// edited or inserted entry. See the honest limit at the top of this file.
class PairingHistory {
  PairingHistory([List<HistoryEntry>? entries]) : _e = List<HistoryEntry>.of(entries ?? <HistoryEntry>[]);
  final List<HistoryEntry> _e;

  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_e);

  Future<HistoryEntry> append(HistoryKind kind, int atMs, {String who = ''}) async {
    final String clean = who.isEmpty ? 'a device' : sanitizeDeviceName(who);
    final String prev = _e.isEmpty ? kHistoryGenesis : _e.last.hash;
    final int seq = _e.length;
    final HistoryEntry e = HistoryEntry(seq: seq, atMs: atMs, kind: kind, who: clean, prev: prev, hash: await _entryHash(seq, atMs, kind, clean, prev));
    _e.add(e);
    return e;
  }

  static Future<bool> verifyEntries(List<HistoryEntry> entries) async {
    String prev = kHistoryGenesis;
    for (int i = 0; i < entries.length; i++) {
      final HistoryEntry e = entries[i];
      if (e.seq != i || e.prev != prev) return false;
      if (e.hash != await _entryHash(e.seq, e.atMs, e.kind, e.who, e.prev)) return false;
      prev = e.hash;
    }
    return true;
  }

  Future<bool> verify() => verifyEntries(_e);
}

/// A short refusal lock on adding devices (adult side, in memory). A failed Match or a "not mine" starts it.
class AddingLock {
  AddingLock({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? _until;

  void lock([Duration d = kAddingLockAfterMiss]) => _until = _now().add(d);
  void clear() => _until = null;

  /// Time left, or null when adding is allowed.
  Duration? blockedFor() {
    final DateTime? u = _until;
    if (u == null) return null;
    final Duration left = u.difference(_now());
    return left > Duration.zero ? left : null;
  }

  static final AddingLock shared = AddingLock();
}

class TrustState {
  const TrustState(this.devices, this.history, this.refusedKeys, this.settle);
  final List<TrustedDevice> devices;
  final List<HistoryEntry> history;

  /// Public keys (base64url) of stopped devices: refused from now on.
  final Set<String> refusedKeys;
  final SettleIn settle;
}

abstract class TrustRepository {
  Future<TrustState> load();
  Future<void> save(TrustState s);
}

class MemoryTrustRepository implements TrustRepository {
  TrustState _s = const TrustState(<TrustedDevice>[], <HistoryEntry>[], <String>{}, SettleIn.day);
  @override
  Future<TrustState> load() async => _s;
  @override
  Future<void> save(TrustState s) async => _s = s;
}

class LocalStoreTrustRepository implements TrustRepository {
  LocalStoreTrustRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'trust';

  @override
  Future<TrustState> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return const TrustState(<TrustedDevice>[], <HistoryEntry>[], <String>{}, SettleIn.day);
    final List<TrustedDevice> d = <TrustedDevice>[
      for (final Object? e in (raw['d'] is List ? raw['d'] as List : const <Object?>[])) ?TrustedDevice.fromJson(e),
    ];
    final List<HistoryEntry> h = <HistoryEntry>[
      for (final Object? e in (raw['h'] is List ? raw['h'] as List : const <Object?>[])) ?HistoryEntry.fromJson(e),
    ];
    final Set<String> r = <String>{for (final Object? e in (raw['r'] is List ? raw['r'] as List : const <Object?>[])) if (e is String) e};
    final SettleIn s = SettleIn.values.asNameMap()[raw['s']] ?? SettleIn.day;
    return TrustState(d, h, r, s);
  }

  @override
  Future<void> save(TrustState s) => _ns.put(_key, <String, Object?>{
        'd': <Object?>[for (final TrustedDevice t in s.devices) t.toJson()],
        'h': <Object?>[for (final HistoryEntry e in s.history) e.toJson()],
        'r': s.refusedKeys.toList(),
        's': s.settle.name,
      });
}

/// What the adult screens and the pairing flow call. All clocks are injected so the rules are testable.
class TrustBook {
  TrustBook(this.repo, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final TrustRepository repo;
  final DateTime Function() _now;

  int get _ms => _now().millisecondsSinceEpoch;

  Future<List<TrustedDevice>> devices() async => (await repo.load()).devices;
  Future<SettleIn> settleIn() async => (await repo.load()).settle;

  Future<void> setSettleIn(SettleIn v) async {
    final TrustState s = await repo.load();
    await repo.save(TrustState(s.devices, s.history, s.refusedKeys, v));
  }

  Future<PairingHistory> _history(TrustState s) async => PairingHistory(s.history);

  Future<void> _write(TrustState s, PairingHistory h, {List<TrustedDevice>? devices, Set<String>? refused}) =>
      repo.save(TrustState(devices ?? s.devices, h.entries, refused ?? s.refusedKeys, s.settle));

  /// Records a refusal or other event with no device change.
  Future<void> note(HistoryKind kind, {String who = ''}) async {
    final TrustState s = await repo.load();
    final PairingHistory h = await _history(s);
    await h.append(kind, _ms, who: who);
    await _write(s, h);
  }

  /// A key an adult stopped earlier is refused outright, before any exchange.
  Future<bool> isRefused(List<int> deviceKey) async => (await repo.load()).refusedKeys.contains(b64(deviceKey));

  /// The adult said "Yes, connect it" and chose the role. Starts the New period. [role] is the ADULT's choice.
  Future<TrustedDevice?> add({
    required String certId,
    required Uint8List deviceKey,
    required String deviceName,
    required PairedRole role,
    required String addedBy,
  }) async {
    final TrustState s = await repo.load();
    if (s.refusedKeys.contains(b64(deviceKey))) return null; // a stopped device is not re-added silently
    final int now = _ms;
    final TrustedDevice d = TrustedDevice(
      certId: certId, deviceKey: deviceKey, name: sanitizeDeviceName(deviceName), role: role, addedAtMs: now,
      addedBy: sanitizeDeviceName(addedBy, max: 32), noviceUntilMs: now + settleDuration(s.settle).inMilliseconds, lastContactMs: now,
    );
    final PairingHistory h = await _history(s);
    await h.append(HistoryKind.added, now, who: d.name);
    await _write(s, h, devices: <TrustedDevice>[...s.devices.where((TrustedDevice x) => x.certId != certId), d]);
    return d;
  }

  Future<void> rename(String certId, String name) async {
    final TrustState s = await repo.load();
    await _write(s, await _history(s), devices: <TrustedDevice>[
      for (final TrustedDevice d in s.devices) d.certId == certId ? d.copyWith(name: sanitizeDeviceName(name)) : d,
    ]);
  }

  /// A later contact on the network. The peer must have proved it holds [presentedKey] (a signed nonce, checked by
  /// the caller). A different key pauses the connection and needs full re-approval; the same key refreshes the
  /// last-contact time. Returns the device's status afterwards, or null for an unknown or stopped certificate.
  Future<TrustStatus?> observe(String certId, List<int> presentedKey) async {
    final TrustState s = await repo.load();
    final int i = s.devices.indexWhere((TrustedDevice d) => d.certId == certId);
    if (i < 0) return null;
    final TrustedDevice d = s.devices[i];
    if (d.status == TrustStatus.stopped) return null;
    final bool same = _eq(d.deviceKey, presentedKey) && !s.refusedKeys.contains(b64(presentedKey));
    final List<TrustedDevice> next = List<TrustedDevice>.of(s.devices);
    final PairingHistory h = await _history(s);
    if (!same) {
      if (d.status == TrustStatus.active) await h.append(HistoryKind.paused, _ms, who: d.name);
      next[i] = d.copyWith(status: TrustStatus.paused);
      await _write(s, h, devices: next);
      return TrustStatus.paused;
    }
    if (d.status == TrustStatus.active) {
      next[i] = d.copyWith(lastContactMs: _ms);
      await _write(s, h, devices: next);
    }
    return d.status;
  }

  /// "Yes, still mine" on the 60-day prompt.
  Future<void> confirmStillYours(String certId) async {
    final TrustState s = await repo.load();
    final PairingHistory h = await _history(s);
    String who = 'it';
    final List<TrustedDevice> next = <TrustedDevice>[
      for (final TrustedDevice d in s.devices)
        if (d.certId == certId && d.status == TrustStatus.active) () {
          who = d.name;
          return d.copyWith(lastContactMs: _ms);
        }() else d,
    ];
    await h.append(HistoryKind.stillYours, _ms, who: who);
    await _write(s, h, devices: next);
  }

  /// "Stop this connection": the caller has already checked the adult's PIN. The device's key is refused from now on.
  /// The tablet itself is not wiped (see the honest limits).
  Future<bool> stop(String certId) async {
    final TrustState s = await repo.load();
    final int i = s.devices.indexWhere((TrustedDevice d) => d.certId == certId);
    if (i < 0) return false;
    final TrustedDevice d = s.devices[i];
    final PairingHistory h = await _history(s);
    await h.append(HistoryKind.stopped, _ms, who: d.name);
    final List<TrustedDevice> next = List<TrustedDevice>.of(s.devices)..[i] = d.copyWith(status: TrustStatus.stopped);
    await _write(s, h, devices: next, refused: <String>{...s.refusedKeys, b64(d.deviceKey)});
    return true;
  }

  /// Whether the device [certId] may add or approve other devices right now.
  Future<bool> mayApproveOthers(String certId) async {
    for (final TrustedDevice d in await devices()) {
      if (d.certId == certId) return d.mayApproveOthers(_ms);
    }
    return false;
  }

  Future<bool> historyIntact() async => PairingHistory.verifyEntries((await repo.load()).history);

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
