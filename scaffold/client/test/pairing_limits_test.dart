// OLIVE BRANCH — the adult-side brakes against someone on the same Wi-Fi burning an open window's tries. UNVERIFIED
// until CI runs it. Pure logic with an injected clock. Design: docs/planning/PERSISTENT-QR-PAIRING.md (T8).
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/pairing_limits.dart';

void main() {
  test('the source bucket allows three per minute per source and recovers; a flood does not extend its own ban', () {
    DateTime now = DateTime(2026, 11, 14, 12);
    final SourceBucket b = SourceBucket(now: () => now);
    expect(<bool>[b.allow('a'), b.allow('a'), b.allow('a'), b.allow('a')], <bool>[true, true, true, false]);
    expect(b.allow('b'), isTrue, reason: 'another source has its own bucket');
    now = now.add(const Duration(seconds: 30));
    for (int i = 0; i < 50; i++) {
      expect(b.allow('a'), isFalse);
    }
    now = now.add(const Duration(seconds: 31));
    expect(b.allow('a'), isTrue, reason: 'refused events were not recorded, so the first three age out together');
  });

  test('the cooldown starts at ten failures in 24 hours, doubles from one minute, caps at one hour, and ages out', () {
    DateTime now = DateTime(2026, 11, 14, 12);
    final FailureCooldown c = FailureCooldown(now: () => now);
    c.record(9);
    expect(c.blockedFor(), isNull);
    c.record();
    expect(c.blockedFor(), const Duration(minutes: 1));
    c.record();
    expect(c.blockedFor(), const Duration(minutes: 2));
    c.record(2);
    expect(c.blockedFor(), const Duration(minutes: 8));
    c.record(20);
    expect(c.blockedFor(), const Duration(hours: 1), reason: 'capped');
    now = now.add(const Duration(minutes: 61));
    expect(c.blockedFor(), isNull, reason: 'the wait has passed');
    now = now.add(const Duration(hours: 24));
    expect(c.recentFailures, 0, reason: 'old failures age out');
  });

  test('clear forgets everything', () {
    final FailureCooldown c = FailureCooldown()..record(12);
    expect(c.blockedFor(), isNotNull);
    c.clear();
    expect(c.blockedFor(), isNull);
  });
}
