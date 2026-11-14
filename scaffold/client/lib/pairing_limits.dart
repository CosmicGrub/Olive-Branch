// OLIVE BRANCH — the two adult-side brakes on someone on the same Wi-Fi who sends pairing messages to burn an open
// window's five tries: a per-source token bucket on `pake1`, and a cumulative failure cooldown on opening a new
// window. UNVERIFIED on a device; pure logic, headless in CI (client/test/pairing_limits_test.dart).
// Design: docs/planning/PERSISTENT-QR-PAIRING.md, threat T8, build phase 4.
//
// Honest limits: both live in memory only (a restart clears them), the bucket keys on the source address (a LAN
// attacker with several addresses gets several buckets), and neither can close the denial of service in the PIN
// and no-picture modes; only scanning the child's picture (Mode B) does that. Notices appear on the ADULT screen
// only, never on the child.

/// At most [limit] events per [window] per key (a source address).
class SourceBucket {
  SourceBucket({this.limit = 3, this.window = const Duration(minutes: 1), DateTime Function()? now}) : _now = now ?? DateTime.now;
  final int limit;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _hits = <String, List<DateTime>>{};

  /// Records one event for [key] and returns true when it is within the limit. A refused event is not recorded,
  /// so a flood does not extend its own ban.
  bool allow(String key) {
    final DateTime t = _now();
    final List<DateTime> hits = _hits.putIfAbsent(key, () => <DateTime>[]);
    hits.removeWhere((DateTime h) => t.difference(h) >= window);
    if (hits.length >= limit) return false;
    hits.add(t);
    // Bound the map: forget sources that have gone quiet.
    if (_hits.length > 256) _hits.removeWhere((String _, List<DateTime> v) => v.isEmpty);
    return true;
  }
}

/// After [threshold] failures within [horizon], opening a new window waits [base], doubling for each further
/// failure past the threshold, up to [cap].
class FailureCooldown {
  FailureCooldown({
    this.threshold = 10,
    this.horizon = const Duration(hours: 24),
    this.base = const Duration(minutes: 1),
    this.cap = const Duration(hours: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final int threshold;
  final Duration horizon, base, cap;
  final DateTime Function() _now;
  final List<DateTime> _failures = <DateTime>[];

  /// A process-wide instance for the screens (in memory only).
  static final FailureCooldown shared = FailureCooldown();

  void _trim() {
    final DateTime t = _now();
    _failures.removeWhere((DateTime f) => t.difference(f) >= horizon);
  }

  /// Records [count] failed confirmations (an adult window that ended with some wrong tries).
  void record([int count = 1]) {
    final DateTime t = _now();
    for (int i = 0; i < count; i++) {
      _failures.add(t);
    }
    _trim();
  }

  int get recentFailures {
    _trim();
    return _failures.length;
  }

  /// How long the adult must wait before opening another window, or null.
  Duration? blockedFor() {
    _trim();
    if (_failures.length < threshold) return null;
    final int over = _failures.length - threshold; // 0 for the first block
    Duration wait = base;
    for (int i = 0; i < over && wait < cap; i++) {
      wait *= 2;
    }
    if (wait > cap) wait = cap;
    final DateTime until = _failures.last.add(wait);
    final Duration left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  void clear() => _failures.clear();
}
