// OLIVE BRANCH — exchange screen tests. §4, §9.7, P3.
//
// P3 is the load-bearing invariant: arrival is an event, never a place, and
// no coordinate may ever reach this screen's widget tree. The rest checks
// the ported schedule.ts / care.ts logic directly, and the bag manifest /
// running-late / arrival interactions actually work.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/exchange_screen.dart';
import 'package:olive_client/form_factors.dart' as ff;

Widget wrap(Widget child) => MaterialApp(home: child);

// Tall surface so the whole ListView is actually laid out by its sliver —
// several assertions below (bag manifest checkboxes, running late, arrival)
// sit below the fold at the default test viewport, and a widget that is not
// built cannot be told apart from one that is genuinely absent. Same fix
// emergency_card_test.dart already applies for the same reason.
Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('schedule.ts port — pure logic', () {
    final Order order = Order(
      pattern: cycle223,
      anchorLocalDate: DateTime.utc(2026, 1, 1),
      holidays: const <HolidayRule>[
        HolidayRule(name: 'Winter break', startMonthDay: '12-20', endMonthDay: '01-02',
          evenYearSide: Side.b, priority: 5),
      ],
      orderTimeLabel: '6:00 PM Central',
    );

    test('anchor date is side A, day 0 of the 14-day cycle', () {
      expect(patternSideOn(order, DateTime.utc(2026, 1, 1)), Side.a);
    });

    test('a holiday rule overrides the base pattern', () {
      final ({Side side, String source, String? holidayName}) s =
        sideOn(order, DateTime.utc(2026, 12, 25));
      expect(s.source, 'holiday');
      expect(s.holidayName, 'Winter break');
    });

    test('sleepsUntilSideChange counts child-local day boundaries', () {
      final ({int sleeps, Side nextSide, DateTime onLocalDate})? next =
        sleepsUntilSideChange(order, DateTime.utc(2026, 1, 1));
      expect(next, isNotNull);
      expect(next!.sleeps, greaterThan(0));
    });

    test('blocks() merges contiguous same-side days into one block', () {
      // Jan 5-7 fall outside the "Winter break" holiday window (which wraps
      // Dec 20 - Jan 2) and are pattern days 4, 5, 6 of cycle223 — all side A
      // — so they should merge into a single block.
      final List<Block> bs = blocks(order, DateTime.utc(2026, 1, 5), DateTime.utc(2026, 1, 7));
      expect(bs.length, 1);
      expect(bs.first.side, Side.a);
      expect(bs.first.startLocalDate, DateTime.utc(2026, 1, 5));
      expect(bs.first.endLocalDate, DateTime.utc(2026, 1, 7));
    });
  });

  group('care.ts port — bag manifest and arrival', () {
    test('manifestOrder puts essential items first', () {
      final List<BagItem> items = <BagItem>[
        BagItem(id: 'a', label: 'Toy', essential: false),
        BagItem(id: 'b', label: 'Inhaler', essential: true),
      ];
      final List<BagItem> ordered = manifestOrder(items);
      expect(ordered.first.label, 'Inhaler');
    });

    test('recordArrival never accepts or requires a location parameter', () {
      final DateTime scheduled = DateTime.utc(2026, 8, 4, 18, 0);
      final ArrivalEvent e = recordArrival('x', scheduled, scheduled.add(const Duration(minutes: 6)));
      expect(e.delayMinutes, 6);
    });

    test('auditArrivalPayload — P3 — flags any location-shaped key', () {
      final ({bool ok, List<String> leaks}) clean = auditArrivalPayload(<String, Object?>{
        'exchangeId': 'x', 'delayMinutes': 3});
      expect(clean.ok, isTrue);
      final ({bool ok, List<String> leaks}) dirty = auditArrivalPayload(<String, Object?>{
        'exchangeId': 'x', 'latitude': 35.2});
      expect(dirty.ok, isFalse);
      expect(dirty.leaks, contains('latitude'));
    });
  });

  group('ExchangeScreen widget', () {
    testWidgets('renders the handoff in sleeps, in her frame', (t) async {
      await pump(t, const ExchangeScreen(childName: 'Ivy'));
      expect(find.textContaining('Ivy goes to'), findsOneWidget);
      expect(find.textContaining('sleep'), findsWidgets);
    });

    testWidgets('P3 — no coordinate or address text ever appears', (t) async {
      await pump(t, const ExchangeScreen());
      await t.tap(find.text('Log arrival'));
      await t.pump();
      // Deliberately whole, unambiguous terms — a naive substring like "lat"
      // would false-positive on the legitimate word "late" elsewhere on
      // this very screen ("Running late").
      for (final String forbidden in <String>[
        'latitude', 'longitude', 'coordinate', 'address', 'geohash', 'accuracy']) {
        expect(find.textContaining(forbidden), findsNothing,
          reason: 'found forbidden location term "$forbidden"');
      }
    });

    testWidgets('toggling a bag item checkbox is a real interaction', (t) async {
      await pump(t, const ExchangeScreen());
      final Finder sentBoxes = find.byType(Checkbox);
      expect(sentBoxes, findsWidgets);
      final Checkbox before = t.widget(sentBoxes.first);
      await t.tap(sentBoxes.first);
      await t.pump();
      final Checkbox after = t.widget(sentBoxes.first);
      expect(after.value, isNot(equals(before.value)));
    });

    testWidgets('running late logs an immutable, appended entry', (t) async {
      await pump(t, const ExchangeScreen());
      expect(find.textContaining('ETA +'), findsNothing);
      await t.tap(find.text('Running 10 min late'));
      await t.pump();
      expect(find.textContaining('ETA +10 min'), findsOneWidget);
      // No delete/edit affordance on the running-late log.
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('logging arrival reports it as an event, never a place', (t) async {
      await pump(t, const ExchangeScreen(childName: 'Ivy'));
      await t.tap(find.text('Log arrival'));
      await t.pump();
      expect(find.textContaining('Ivy arrived'), findsOneWidget);
    });

    testWidgets('no raw arithmetic language appears anywhere', (t) async {
      await pump(t, const ExchangeScreen());
      expect(find.textContaining('+1'), findsNothing);
      expect(find.textContaining('UTC'), findsNothing);
      expect(find.textContaining('difference'), findsNothing);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop widths', () {
    Future<void> atSize(WidgetTester t, Size size, Widget child) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(child));
      await t.pumpAndSettle();
    }

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow',
        (t) async {
      await atSize(t, const Size(344, 882), const ExchangeScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const ExchangeScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const ExchangeScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const ExchangeScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });
  });

  group('responsive — comfortable reading width cap (form_factors.dart)', () {
    // Guardian-side, five stacked sections in a fixed order (see file
    // header). On a wide tablet/desktop viewport the single column is only
    // ever capped to a comfortable reading width and centered, never split
    // — section order and the manifest rows' fixed-width checkbox columns
    // are untouched either way. The Fold5 cover and phone widths are
    // completely untouched by this cap.
    testWidgets('the cap engages only on a wide tablet/desktop viewport — '
        'never at the Fold5 cover or phone width', (t) async {
      Future<void> pumpAt(Size size) async {
        await t.binding.setSurfaceSize(size);
        await t.pumpWidget(wrap(const ExchangeScreen(childName: 'Ivy')));
        await t.pump();
      }

      addTearDown(() => t.binding.setSurfaceSize(null));

      await pumpAt(const Size(1100, 1800));
      expect(t.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);

      await pumpAt(const Size(344, 1800)); // Fold5 cover
      expect(t.getSize(find.byType(ListView)).width, 344);

      await pumpAt(const Size(390, 1800)); // standard phone
      expect(t.getSize(find.byType(ListView)).width, 390);
    });
  });

  group('live wiring — the real bag-item/running-late/arrival routes '
      '(server/routes.mjs, packages/db/src/pool.ts bagItemsFor/logRunningLate/'
      'recordExchangeArrival)', () {
    testWidgets('shows a loading indicator, then real fetched bag items/late log/'
        'arrival replace the demo fixtures', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/exchange/bag-items')) {
          return http.Response(jsonEncode({'items': [
            {'id': 'i1', 'label': 'Real Backpack Item', 'essential': true,
             'sent': false, 'returned': false},
          ]}), 200);
        }
        if (req.url.path.endsWith('/exchange/running-late')) {
          return http.Response(jsonEncode({'entries': [
            {'id': 'l1', 'loggedAt': '2026-08-04T12:00:00.000Z', 'etaMinutes': 15,
             'reportedByUserId': 'dad-1', 'reportedByName': 'Dad'},
          ]}), 200);
        }
        if (req.url.path.endsWith('/exchange/arrival')) {
          return http.Response(jsonEncode({'event': null}), 200);
        }
        return http.Response('not found', 404);
      });
      await pump(t, ExchangeScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();

      expect(find.text('Real Backpack Item'), findsOneWidget);
      expect(find.text('Mr. Bramble (stuffed bear)'), findsNothing);
      expect(find.textContaining('ETA +15 min'), findsOneWidget);
      expect(find.text('Log arrival'), findsOneWidget);
    });

    testWidgets('toggling sent POSTs to the real route and reflects the response', (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST' && req.url.path.contains('/bag-items/')) {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'i1', 'label': 'Real Backpack Item', 'essential': true,
            'sent': true, 'returned': false,
          }), 200);
        }
        if (req.url.path.endsWith('/exchange/bag-items')) {
          return http.Response(jsonEncode({'items': [
            {'id': 'i1', 'label': 'Real Backpack Item', 'essential': true,
             'sent': false, 'returned': false},
          ]}), 200);
        }
        if (req.url.path.endsWith('/exchange/running-late')) {
          return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
        }
        return http.Response(jsonEncode({'event': null}), 200);
      });
      await pump(t, ExchangeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a', httpClient: mock));
      await t.pumpAndSettle();

      final Checkbox before = t.widget(find.byType(Checkbox).first);
      expect(before.value, isFalse);
      await t.tap(find.byType(Checkbox).first);
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/v1/children/child-a/exchange/bag-items/i1');
      expect(jsonDecode(posts.single.body), {'sent': true});
      final Checkbox after = t.widget(find.byType(Checkbox).first);
      expect(after.value, isTrue);
    });

    testWidgets('logging running late POSTs to the real route and appends the '
        'real entry', (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/exchange/running-late')) {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'l2', 'loggedAt': '2026-08-04T12:10:00.000Z', 'etaMinutes': 10,
            'reportedByUserId': 'dad-1', 'reportedByName': 'Dad',
          }), 201);
        }
        if (req.url.path.endsWith('/exchange/bag-items')) {
          return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
        }
        if (req.url.path.endsWith('/exchange/running-late')) {
          return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
        }
        return http.Response(jsonEncode({'event': null}), 200);
      });
      await pump(t, ExchangeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a', httpClient: mock));
      await t.pumpAndSettle();

      expect(find.textContaining('ETA +'), findsNothing);
      await t.tap(find.text('Running 10 min late'));
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {'etaMinutes': 10});
      expect(find.textContaining('ETA +10 min'), findsOneWidget);
    });

    testWidgets('logging arrival POSTs with no body field ever, and renders using '
        'the real server-computed delayMinutes', (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/exchange/arrival')) {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'a1', 'scheduledAt': '2026-08-04T18:00:00.000Z',
            'arrivedAt': '2026-08-04T18:12:00.000Z', 'delayMinutes': 12,
          }), 201);
        }
        if (req.url.path.endsWith('/exchange/bag-items')) {
          return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
        }
        if (req.url.path.endsWith('/exchange/running-late')) {
          return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
        }
        return http.Response(jsonEncode({'event': null}), 200);
      });
      await pump(t, ExchangeScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      await t.tap(find.text('Log arrival'));
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      // P3, structurally, on the live path too — the real request body
      // carries no field at all, let alone a location-shaped one.
      expect(jsonDecode(posts.single.body), <String, dynamic>{});
      expect(find.textContaining('Ivy arrived — 12 min after'), findsOneWidget);
    });

    testWidgets('a real 409 no_active_custody_order response shows an honest '
        'message, never a fabricated arrival', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/exchange/arrival')) {
          return http.Response(jsonEncode({'error': 'no_active_custody_order'}), 409);
        }
        if (req.url.path.endsWith('/exchange/bag-items')) {
          return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
        }
        if (req.url.path.endsWith('/exchange/running-late')) {
          return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
        }
        return http.Response(jsonEncode({'event': null}), 200);
      });
      await pump(t, ExchangeScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      await t.tap(find.text('Log arrival'));
      await t.pumpAndSettle();

      expect(find.textContaining('Ivy arrived'), findsNothing);
      expect(find.text('Log arrival'), findsOneWidget); // still offered, not stuck
      expect(find.textContaining('No custody schedule'), findsOneWidget);
    });

    testWidgets('with no live params supplied, the demo fixtures render exactly '
        'as before — no network call, no loading state', (t) async {
      await pump(t, const ExchangeScreen());
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Mr. Bramble (stuffed bear)'), findsOneWidget);
    });
  });
}
