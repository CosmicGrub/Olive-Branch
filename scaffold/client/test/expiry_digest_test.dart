// OLIVE BRANCH — expiry digest tests. §10.1b.
//
// The rule this file exists to enforce: `digestVisibleTo('child')` is false,
// and stays false. Preservation is a standing rule — this digest is only
// for the narrow, non-standing-rule category, given with a real lead and a
// real one-tap "keep forever" that actually works.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
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

  group('readExpiryDigests', () {
    final DateTime now = DateTime.utc(2026, 11, 14, 12);
    Map<String, Object?> d(List<Map<String, Object?>> items) => <String, Object?>{'items': items};
    Map<String, Object?> it(String id, String kind, DateTime at) =>
        <String, Object?>{'artifactId': id, 'kind': kind, 'expiresAt': at.toIso8601String()};

    test('one plain list: each artifact once (soonest date wins), soonest first, past dropped', () {
      final List<DigestEntry> out = readExpiryDigests(<String, Object?>{'digests': <Object?>[
        d(<Map<String, Object?>>[it('a', 'call_clip', now.add(const Duration(days: 3))),
          it('b', 'screen_frame', now.add(const Duration(days: 9)))]),
        d(<Map<String, Object?>>[it('a', 'call_clip', now.add(const Duration(days: 5))),
          it('gone', 'session_media', now.subtract(const Duration(days: 1)))]),
      ]}, now);
      expect(out.map((DigestEntry e) => e.artifactId), <String>['a', 'b']);
      expect(out.first.daysLeft, 3);
    });

    test('tolerates junk: a malformed row is skipped, never thrown', () {
      expect(readExpiryDigests(null, now), isEmpty);
      expect(readExpiryDigests(<String, Object?>{'digests': 'x'}, now), isEmpty);
      expect(readExpiryDigests(<String, Object?>{'digests': <Object?>[5, d(<Map<String, Object?>>[
        <String, Object?>{'artifactId': 1, 'kind': 'call_clip', 'expiresAt': 'nope'},
        <String, Object?>{'artifactId': 'ok', 'kind': 'call_clip', 'expiresAt': 'nope'},
        it('fine', 'call_clip', now.add(const Duration(hours: 5)))])]}, now).map((DigestEntry e) => e.artifactId),
        <String>['fine']);
    });

    test('headline pluralizes at 0, 1 and many', () {
      expect(digestHeadline(0), 'Nothing is due to be cleared.');
      expect(digestHeadline(1), 'One thing is due to be cleared soon.');
      expect(digestHeadline(4), '4 things are due to be cleared soon.');
    });
  });

  group('ExpiryDigestScreen, the reader', () {
    final DateTime now = DateTime.utc(2026, 11, 14, 12);
    Map<String, dynamic> body(List<Map<String, Object?>> items) => <String, dynamic>{
      'digests': <Object?>[<String, Object?>{'id': 'x', 'items': items}]};
    Map<String, Object?> it(String id, String kind, int days) => <String, Object?>{
      'artifactId': id, 'kind': kind, 'expiresAt': now.add(Duration(days: days)).toIso8601String()};

    testWidgets('with no server it says plainly that it is a later thing, and invents nothing', (t) async {
      await pump(t, ExpiryDigestScreen(clock: () => now));
      expect(find.byKey(const Key('digestLater')), findsOneWidget);
      expect(find.textContaining('not connected to one yet'), findsOneWidget);
      expect(find.text('All clear.'), findsNothing);
      expect(find.byKey(const Key('digestHeadline')), findsNothing);
    });

    testWidgets('lists what the server recorded, soonest first, with no keep button and no caption', (t) async {
      await pump(t, ExpiryDigestScreen(clock: () => now, load: () async => body(<Map<String, Object?>>[
        it('b', 'screen_frame', 9), it('a', 'call_clip', 1)])));
      await t.pumpAndSettle();
      expect(find.text('2 things are due to be cleared soon.'), findsOneWidget);
      expect(find.text('Call clip'), findsOneWidget);
      expect(find.text('Clears tomorrow'), findsOneWidget);
      expect(find.text('Clears in 9 days'), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const Key('digest-a'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('digest-b'))).dy));
      expect(find.text('Keep forever'), findsNothing, reason: 'the keep route is not built; nothing fakes it');
      expect(find.byKey(const Key('digestKeepLater')), findsOneWidget);
      expect(find.textContaining('Never shown to her'), findsOneWidget);
    });

    testWidgets('an empty record is the calm all-clear', (t) async {
      await pump(t, ExpiryDigestScreen(clock: () => now, load: () async => body(<Map<String, Object?>>[])));
      await t.pumpAndSettle();
      expect(find.text('All clear.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      final Icon icon = t.widget(find.byIcon(Icons.check_circle_outline));
      expect(icon.size, 40.0);
    });

    testWidgets('when the server cannot be reached it says so, NOT all-clear, and Try again works', (t) async {
      int calls = 0;
      await pump(t, ExpiryDigestScreen(clock: () => now, load: () async {
        if (++calls == 1) throw Exception('socket');
        return body(<Map<String, Object?>>[it('a', 'call_clip', 2)]);
      }));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('digestOffline')), findsOneWidget);
      expect(find.text('All clear.'), findsNothing);
      await t.tap(find.byKey(const Key('digestRetry')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('digestOffline')), findsNothing);
      expect(find.text('One thing is due to be cleared soon.'), findsOneWidget);
    });

    testWidgets('a 403 from the server (a child session) is the same honest offline note, no error text', (t) async {
      await pump(t, ExpiryDigestScreen(clock: () => now, load: () async => throw ForbiddenException('not_a_child_surface')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('digestOffline')), findsOneWidget);
      expect(find.textContaining('not_a_child_surface'), findsNothing);
    });

    testWidgets('the whole path: OliveApi.fetchExpiryDigests over a mock server feeds the list', (t) async {
      final MockClient client = MockClient((http.Request r) async {
        expect(r.method, 'GET');
        expect(r.url.path, '/v1/children/c1/expiry-digests');
        return http.Response(jsonEncode(body(<Map<String, Object?>>[it('z', 'session_media', 4)])), 200,
            headers: <String, String>{'content-type': 'application/json'});
      });
      final OliveApi api = OliveApi('http://x.test', 'tok', client: client);
      await pump(t, ExpiryDigestScreen(clock: () => now, load: () => api.fetchExpiryDigests('c1')));
      await t.pumpAndSettle();
      expect(find.text('Session media'), findsOneWidget);
      expect(find.text('Clears in 4 days'), findsOneWidget);
    });
  });

  group('responsive, Fold5 cover and main, phone, and desktop widths, every state', () {
    final DateTime now = DateTime.utc(2026, 11, 14, 12);
    final Map<String, dynamic> full = <String, dynamic>{'digests': <Object?>[<String, Object?>{'items': <Object?>[
      for (int i = 1; i <= 6; i++)
        <String, Object?>{'artifactId': 'a$i', 'kind': 'call_clip', 'expiresAt': now.add(Duration(days: i)).toIso8601String()}]}]};
    final Map<String, ExpiryDigestLoader?> states = <String, ExpiryDigestLoader?>{
      'later': null,
      'offline': () async => throw Exception('x'),
      'list': () async => full,
    };

    for (final MapEntry<String, ExpiryDigestLoader?> st in states.entries) {
      for (final Size size in const <Size>[Size(344, 882), Size(390, 900), Size(673, 841), Size(800, 1000)]) {
        for (final double scale in <double>[1.0, 2.0]) {
          testWidgets('${st.key} at ${size.width} dp, ${scale}x text has no overflow', (t) async {
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1.0;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            await t.pumpWidget(MaterialApp(
              builder: (BuildContext c, Widget? child) =>
                  MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: ExpiryDigestScreen(load: st.value, clock: () => now),
            ));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });
}
