// OLIVE BRANCH — the LOCAL guardian PIN: a salted slow hash, a constant-time
// compare and a lockout. No longer UNVERIFIED — verified by CI
// (client/test/local_pin_test.dart). MASTERFILE §8.5.9.
//
// WHAT IT IS. A 4 to 8 digit code a grown-up chooses on THIS device, kept in the
// sealed `localpin` area (`guardian.local-guardian.localpin`). It gates on-device
// actions that have no server behind them when the device is offline: changing a
// locked age, "Data on this device" (the wipe) and the guardian settings hub.
//
// WHAT IT IS NOT. It is NOT the server PIN. The server PIN (`POST /v1/me/pin`,
// `hasPin` on `GET /v1/me`, scrypt on the server, the kiosk lock's
// `/kiosk-pin/verify`) is unchanged and is never faked, replaced or mirrored by
// this: when a session exists the server PIN rules apply exactly as before. The
// two are separate secrets with separate lockouts. Nothing here is ever sent to a
// server, and a server PIN is not accepted here.
//
// HOW IT IS KEPT. The PIN itself is never stored. We store
// PBKDF2-HMAC-SHA256 (the pinned, pure-Dart `cryptography` package that already
// seals the private areas) over a fresh 16-byte random salt, [kLocalPinIterations]
// rounds, plus the salt and the round count. A check recomputes the hash and
// compares in constant time ([constantTimeEquals]), so how long a wrong guess takes
// does not say how close it was. The area is sealed on the device too.
//
// HOW IT IS LIMITED. Five wrong tries lock it for 15 minutes, with the same words
// the server uses ("Too many wrong tries. Try again in 15 minutes."). As on the
// server, the count starts again at zero when a lock is imposed and when a check
// succeeds. While locked, even the RIGHT PIN is refused and nothing is counted. The
// state is kept in memory first and written second, so a store that cannot be
// written does not become a way to try forever during one run.
//
// HONEST LIMIT. A short numeric code on a phone is a deterrent against a child, a
// curious sibling or a thief with the screen on, not against someone who has copied
// the app's files AND the device's keystore: a 4 digit code has 10,000 values and
// the slow hash only makes each guess cost more. The sealing key lives in the OS
// keystore and a wipe erases it.
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'local_store.dart';

const int kLocalPinMinDigits = 4, kLocalPinMaxDigits = 8;
const int kLocalPinMaxAttempts = 5;
const Duration kLocalPinLockout = Duration(minutes: 15);

/// PBKDF2 rounds. The hash is pure Dart and runs in a BACKGROUND isolate (see
/// [kLocalPinOffThreadRounds]), so the screen keeps drawing while it works; the
/// rounds are unchanged from when it ran on the UI isolate: tens of times the
/// cost of one hash per guess, a fraction of a second per check on a phone.
const int kLocalPinIterations = 100000;

/// At or above this many rounds the hash runs in a background isolate. Below it (the
/// small counts tests pass to stay fast) it runs inline: an isolate costs more than the
/// hash, and a widget test's fake clock cannot await an isolate. The bytes are the same
/// either way; production's [kLocalPinIterations] is far above it.
const int kLocalPinOffThreadRounds = 20000;

/// PBKDF2-HMAC-SHA256, 256 bits. Top-level and closure-free so [Isolate.run] can send it.
Future<List<int>> localPinDerive(String pin, List<int> salt, int rounds) async {
  final Pbkdf2 algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256);
  final SecretKey key = await algo.deriveKeyFromPassword(password: pin, nonce: salt);
  return key.extractBytes();
}

/// The server's own wording for its lockout (guardian_setup.dart `pin_locked`).
const String kLocalPinLockedMessage = 'Too many wrong tries. Try again in 15 minutes.';

/// The owner id of the sealed `localpin` and `localfamily` areas.
const String kLocalGuardianScope = 'local-guardian';

final RegExp _pinShape = RegExp(r'^\d{4,8}$');

bool isValidLocalPin(String pin) => _pinShape.hasMatch(pin);

/// Compares in time that depends only on the longer length, never on where the
/// first difference is.
bool constantTimeEquals(List<int> a, List<int> b) {
  int diff = a.length ^ b.length;
  final int n = max(a.length, b.length);
  for (int i = 0; i < n; i++) {
    final int x = i < a.length ? a[i] : 0;
    final int y = i < b.length ? b[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

class LocalPinRecord {
  const LocalPinRecord({
    required this.iterations,
    required this.salt,
    required this.hash,
    this.failures = 0,
    this.lockedUntilMs,
  });
  final int iterations;
  final Uint8List salt;
  final Uint8List hash;
  final int failures;
  final int? lockedUntilMs;

  LocalPinRecord copyWith({int? failures, int? lockedUntilMs, bool clearLock = false}) => LocalPinRecord(
        iterations: iterations,
        salt: salt,
        hash: hash,
        failures: failures ?? this.failures,
        lockedUntilMs: clearLock ? null : (lockedUntilMs ?? this.lockedUntilMs),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'algo': 'pbkdf2-hmac-sha256',
        'iter': iterations,
        'salt': base64.encode(salt),
        'hash': base64.encode(hash),
        'failures': failures,
        if (lockedUntilMs != null) 'lockedUntil': lockedUntilMs,
      };

  /// Fail-closed decode: a record that is not exactly what [toJson] writes is "no PIN
  /// set", never a PIN that accepts anything.
  static LocalPinRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      if (raw['v'] != 1 || raw['algo'] != 'pbkdf2-hmac-sha256') return null;
      final Object? it = raw['iter'], s = raw['salt'], h = raw['hash'];
      if (it is! int || it < 1 || s is! String || h is! String) return null;
      final Uint8List salt = base64.decode(s), hash = base64.decode(h);
      if (salt.length < 8 || hash.length != 32) return null;
      final Object? f = raw['failures'], l = raw['lockedUntil'];
      return LocalPinRecord(
        iterations: it,
        salt: salt,
        hash: hash,
        failures: f is int && f >= 0 ? f : 0,
        lockedUntilMs: l is int ? l : null,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract class LocalPinRepository {
  Future<LocalPinRecord?> load();
  Future<void> save(LocalPinRecord record);
  Future<void> clear();
}

class MemoryLocalPinRepository implements LocalPinRepository {
  LocalPinRecord? _r;
  @override
  Future<LocalPinRecord?> load() async => _r;
  @override
  Future<void> save(LocalPinRecord record) async => _r = record;
  @override
  Future<void> clear() async => _r = null;
}

class LocalStoreLocalPinRepository implements LocalPinRepository {
  LocalStoreLocalPinRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'pin';
  @override
  Future<LocalPinRecord?> load() async => LocalPinRecord.fromJson(await _ns.get(_key));
  @override
  Future<void> save(LocalPinRecord record) => _ns.put(_key, record.toJson());
  @override
  Future<void> clear() => _ns.delete(_key);
}

enum PinOutcome { ok, wrong, locked, notSet }

class PinCheck {
  const PinCheck(this.outcome, {this.attemptsLeft = 0, this.lockedFor});
  final PinOutcome outcome;
  final int attemptsLeft;
  final Duration? lockedFor;
  bool get ok => outcome == PinOutcome.ok;
}

class LocalPinService {
  LocalPinService(
    this._repo, {
    DateTime Function()? now,
    this.iterations = kLocalPinIterations,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final LocalPinRepository _repo;
  final DateTime Function() _now;
  final Random _random;

  /// Rounds for a NEW PIN. Tests pass a small number; an existing PIN is always checked
  /// with the number it was made with.
  final int iterations;

  LocalPinRecord? _cache;
  bool _loaded = false;

  Future<LocalPinRecord?> _record() async {
    if (_loaded) return _cache;
    try {
      _cache = await _repo.load();
    } catch (_) {
      _cache = null;
    }
    _loaded = true;
    return _cache;
  }

  Future<bool> isSet() async => (await _record()) != null;

  Future<List<int>> _derive(String pin, List<int> salt, int rounds) {
    if (rounds < kLocalPinOffThreadRounds) return localPinDerive(pin, salt, rounds);
    final List<int> s = List<int>.of(salt);
    return Isolate.run<List<int>>(() => localPinDerive(pin, s, rounds));
  }

  /// Sets the PIN (or replaces it). Throws [ArgumentError] for a code that is not 4 to
  /// 8 digits, and whatever the store throws if it cannot be written (the caller must
  /// not report a PIN as set when it was not). Proof of the OLD PIN is the caller's
  /// job ([change] does it).
  Future<void> setPin(String pin) async {
    if (!isValidLocalPin(pin)) {
      throw ArgumentError('A PIN is $kLocalPinMinDigits to $kLocalPinMaxDigits digits.');
    }
    final Uint8List salt = Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));
    final Uint8List hash = Uint8List.fromList(await _derive(pin, salt, iterations));
    final LocalPinRecord next = LocalPinRecord(iterations: iterations, salt: salt, hash: hash);
    await _repo.save(next);
    _cache = next;
    _loaded = true;
  }

  /// Checks [pin]. See the file header for the lockout rules.
  Future<PinCheck> verify(String pin) async {
    final LocalPinRecord? rec = await _record();
    if (rec == null) return const PinCheck(PinOutcome.notSet);
    final int nowMs = _now().millisecondsSinceEpoch;
    final int? until = rec.lockedUntilMs;
    if (until != null && nowMs < until) {
      return PinCheck(PinOutcome.locked, lockedFor: Duration(milliseconds: until - nowMs));
    }
    // An expired lock is forgotten; the count was already zero when it was imposed.
    LocalPinRecord live = (until != null) ? rec.copyWith(failures: 0, clearLock: true) : rec;
    final bool shaped = isValidLocalPin(pin);
    final List<int> got = await _derive(shaped ? pin : '', rec.salt, rec.iterations);
    final bool match = constantTimeEquals(got, rec.hash) && shaped;
    if (match) {
      live = live.copyWith(failures: 0, clearLock: true);
      await _remember(live, force: rec.failures != 0 || until != null);
      return const PinCheck(PinOutcome.ok);
    }
    final int failures = live.failures + 1;
    if (failures >= kLocalPinMaxAttempts) {
      live = live.copyWith(failures: 0, lockedUntilMs: nowMs + kLocalPinLockout.inMilliseconds);
      await _remember(live, force: true);
      return const PinCheck(PinOutcome.locked, lockedFor: kLocalPinLockout);
    }
    live = live.copyWith(failures: failures, clearLock: true);
    await _remember(live, force: true);
    return PinCheck(PinOutcome.wrong, attemptsLeft: kLocalPinMaxAttempts - failures);
  }

  /// A `Future<bool> Function(String)` for the screens that take one (the wipe).
  Future<bool> verifyBool(String pin) async => (await verify(pin)).ok;

  /// Replaces the PIN, proving the current one first. Returns the check of the OLD pin;
  /// the new one is only set when that is ok.
  Future<PinCheck> change(String current, String next) async {
    final PinCheck c = await verify(current);
    if (c.ok) await setPin(next);
    return c;
  }

  /// Whether the PIN is locked right now (and for how long).
  Future<Duration?> lockedFor() async {
    final LocalPinRecord? rec = await _record();
    final int? until = rec?.lockedUntilMs;
    if (until == null) return null;
    final int left = until - _now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : null;
  }

  /// Memory first (so an unwritable store cannot become unlimited tries), then the
  /// store, best effort.
  Future<void> _remember(LocalPinRecord r, {required bool force}) async {
    _cache = r;
    if (!force) return;
    try {
      await _repo.save(r);
    } catch (_) {
      // Held for this run only.
    }
  }

  /// Removes the PIN (the device wipe does this by deleting the sealed area).
  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    await _repo.clear();
  }
}
