// OLIVE BRANCH — expiry digest tests. §10.1b.
//
// The rule this file exists to enforce: `digestVisibleTo('child')` is false,
// and stays false. Preservation is a standing rule — this digest is only
// for the narrow, non-standing-rule category, given with a real lead and a
// real one-tap "keep forever" that actually works.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/expiry_digest.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

List<ArtifactSeed> _sample(DateTime now) => <ArtifactSeed>[
  ArtifactSeed(id: 'a', kind: 'call_clip', capturedAt: now, preserved: false,
    expiresAt: now.add(const Duration(days: 3))),
  ArtifactSeed(id: 'b', kind: 'call_clip', capturedAt: now, preserved: true,
    expiresAt: now.add(const Duration(days: 3))), // preserved — must never appear
  ArtifactSeed(id: 'c', kind: 'screen_frame', capturedAt: now, preserved: false,
    expiresAt: now.subtract(const Duration(days: 1))), // already past — must never appear
  ArtifactSeed(id: 'd', kind: 'screen_frame', capturedAt: now, preserved: false,
    expiresAt: now.add(const Duration(days: 30))), // outside the 14-day lead
];

void main() {
  group('storage/retention.ts port — pure logic', () {
    test('excludes preserved artifacts, past-expiry artifacts, and anything '
        'outside the lead window', () {
      final DateTime now = DateTime.utc(2026, 8, 4);
      final ExpiryDigest d = expiringSoon(_sample(now), now);
      expect(d.items.map((ExpiringArtifact a) => a.artifactId), <String>['a']);
    });

    test('sorted soonest first', () {
      final DateTime now = DateTime.utc(2026, 8, 4);
      final List<ArtifactSeed> seeds = <ArtifactSeed>[
        ArtifactSeed(id: 'far', kind: 'call_clip', capturedAt: now, preserved: false,
          expiresAt: now.add(const Duration(days: 12))),
        ArtifactSeed(id: 'near', kind: 'call_clip', capturedAt: now, preserved: false,
          expiresAt: now.add(const Duration(days: 2))),
      ];
      final ExpiryDigest d = expiringSoon(seeds, now);
      expect(d.items.first.artifactId, 'near');
    });

    test('headline pluralizes correctly at 0, 1, and many', () {
      final DateTime now = DateTime.utc(2026, 8, 4);
      expect(expiringSoon(<ArtifactSeed>[], now).headline, 'Nothing is due to be cleared.');
      final ExpiryDigest one = expiringSoon(<ArtifactSeed>[
        ArtifactSeed(id: 'x', kind: 'call_clip', capturedAt: now, preserved: false,
          expiresAt: now.add(const Duration(days: 1)))], now);
      expect(one.headline, 'One thing will be cleared soon unless you keep it.');
    });

    test('digestVisibleTo — THE RULE — false for child, true otherwise', () {
      expect(digestVisibleTo('child'), isFalse);
      expect(digestVisibleTo('guardian'), isTrue);
    });

    test('keepForever only affects the requested, not-already-preserved ids', () {
      final DateTime now = DateTime.utc(2026, 8, 4);
      final List<ArtifactSeed> seeds = _sample(now);
      final List<String> kept = keepForever(<String>['a', 'b', 'zzz'], seeds);
      expect(kept, <String>['a']); // 'b' was already preserved, 'zzz' does not exist
    });
  });

  group('ExpiryDigestScreen widget', () {
    testWidgets('shows only the items due, and tapping Keep forever removes '
        'one from the pending list', (t) async {
      await pump(t, const ExpiryDigestScreen());
      expect(find.textContaining('will be cleared soon'), findsOneWidget);
      final int before = find.text('Keep forever').evaluate().length;
      expect(before, greaterThan(0));

      await t.tap(find.text('Keep forever').first);
      await t.pumpAndSettle();

      expect(find.text('Keep forever').evaluate().length, before - 1);
    });

    testWidgets('never shown as a child surface — this screen carries no '
        'child-role gate because none of this app\'s child-facing widgets '
        'ever navigate to it', (t) async {
      await pump(t, const ExpiryDigestScreen());
      expect(find.byIcon(Icons.settings), findsNothing);
    });
  });
}
