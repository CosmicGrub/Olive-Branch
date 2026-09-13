// OLIVE BRANCH — meds & care tests. §9.6.1, §5.8, §6.7.
//
// The load-bearing invariant is the exchange-day double-dose guard: a second
// "given" dose in the same slot on the same child-local day must be refused,
// and the refusal message must name the parent and the local time — nothing
// else, no blame framing.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/meds_care.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('care.ts medication port — pure logic', () {
    test('doseKey is keyed on the CHILD-local date', () {
      final DateTime childLocal = DateTime.utc(2026, 8, 4);
      final DoseKey k = doseKey('med-1', 'morning', childLocal);
      expect(k.localDate, '2026-08-04');
    });

    test('the second "given" dose in the same slot/day is blocked', () {
      final DateTime t1 = DateTime.utc(2026, 8, 4, 8, 0);
      final DoseKey key = doseKey('med-1', 'morning', t1);
      final RecordDoseResult first = recordDose(<DoseRecord>[], key,
        administeredAt: t1, byUserName: 'Mom', status: DoseStatus.given);
      expect(first.ok, isTrue);

      final RecordDoseResult second = recordDose(<DoseRecord>[first.record!], key,
        administeredAt: t1.add(const Duration(hours: 2)), byUserName: 'Dad',
        status: DoseStatus.given);
      expect(second.ok, isFalse);
      // Names the parent and the local time. Nothing else.
      expect(second.error!.message, 'Mom gave this dose at 8:00 AM.');
      expect(second.error!.message.toLowerCase(), isNot(contains('fault')));
      expect(second.error!.message.toLowerCase(), isNot(contains('wrong')));
      expect(second.error!.message.toLowerCase(), isNot(contains('again')));
    });

    test('a non-"given" status never collides even in the same slot/day', () {
      final DateTime t1 = DateTime.utc(2026, 8, 4, 8, 0);
      final DoseKey key = doseKey('med-1', 'morning', t1);
      final RecordDoseResult first = recordDose(<DoseRecord>[], key,
        administeredAt: t1, byUserName: 'Mom', status: DoseStatus.given);
      final RecordDoseResult skip = recordDose(<DoseRecord>[first.record!], key,
        administeredAt: t1, byUserName: 'Dad', status: DoseStatus.skipped);
      expect(skip.ok, isTrue);
    });

    test('prnAllowed refuses a second dose inside the minimum gap', () {
      final DateTime t1 = DateTime.utc(2026, 8, 4, 8, 0);
      final List<DoseRecord> existing = <DoseRecord>[
        DoseRecord(medicationId: 'albuterol', localDate: '2026-08-04', slot: 'prn',
          administeredAt: t1, byUserName: 'Mom', status: DoseStatus.given)];
      expect(prnAllowed(existing, 'albuterol', t1.add(const Duration(hours: 1)), 4), isFalse);
      expect(prnAllowed(existing, 'albuterol', t1.add(const Duration(hours: 5)), 4), isTrue);
    });

    test('prnAllowed is permissive with no prior dose', () {
      expect(prnAllowed(<DoseRecord>[], 'albuterol', DateTime.utc(2026, 8, 4), 4), isTrue);
    });
  });

  group('MedsCareScreen widget', () {
    test('child_home.dart never references MedsCareScreen, on disk, today', () {
      Directory dir = Directory.current;
      File? found;
      for (int i = 0; i < 6 && found == null; i++) {
        final File candidate = File('${dir.path}/lib/child_home.dart');
        if (candidate.existsSync()) found = candidate;
        dir = dir.parent;
      }
      expect(found, isNotNull, reason: 'could not locate lib/child_home.dart to audit');
      expect(found!.readAsStringSync().contains('MedsCareScreen'), isFalse);
    });

    testWidgets('logging the morning dose shows it as given, and the log '
        'control is then replaced rather than left tappable again', (t) async {
      await pump(t, const MedsCareScreen());
      expect(find.text('Given today'), findsNothing);
      await t.tap(find.widgetWithText(FilledButton, 'Log dose').first);
      await t.pump();
      expect(find.text('Given today'), findsWidgets);
      // The scheduled-dose collision guard (recordDose/AlreadyAdministered)
      // is proven at the pure-logic level above with the exact message; at
      // the UI layer the control itself disappears once given today, which
      // is the first line of defense against a same-session double-log.
      expect(find.widgetWithText(FilledButton, 'Log dose'), findsNWidgets(1));
    });

    testWidgets('a second PRN dose inside the minimum gap is refused, no '
        'blame language', (t) async {
      await pump(t, const MedsCareScreen());
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pump();
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pump();
      expect(find.textContaining('Too soon'), findsOneWidget);
      expect(find.textContaining('fault'), findsNothing);
      expect(find.textContaining('wrong'), findsNothing);
    });

    testWidgets('shared medical record shows allergies and conditions', (t) async {
      await pump(t, const MedsCareScreen());
      expect(find.textContaining('Peanuts'), findsOneWidget);
      expect(find.textContaining('asthma'), findsOneWidget);
    });

    testWidgets('no settings affordance on this guardian screen either', (t) async {
      await pump(t, const MedsCareScreen());
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('the log-dose and log-PRN-dose buttons meet the 48dp minimum '
        'tap target', (t) async {
      await pump(t, const MedsCareScreen());
      final Size doseSize = t.getSize(find.ancestor(
        of: find.text('Log dose').first,
        matching: find.byWidgetPredicate((Widget w) => w is FilledButton)));
      expect(doseSize.height, greaterThanOrEqualTo(48));
      final Size prnSize = t.getSize(find.ancestor(
        of: find.text('Log PRN dose'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton)));
      expect(prnSize.height, greaterThanOrEqualTo(48));
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
      await atSize(t, const Size(344, 882), const MedsCareScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const MedsCareScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const MedsCareScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const MedsCareScreen());
      expect(t.takeException(), isNull);
    });
  });

  group('responsive — comfortable reading width cap (form_factors.dart)', () {
    // Guardian-only (see file header). On a wide tablet/desktop viewport
    // the single column is only ever capped to a comfortable reading width
    // and centered, never split. The Fold5 cover and phone widths are
    // completely untouched by this cap.
    testWidgets('the cap engages only on a wide tablet/desktop viewport — '
        'never at the Fold5 cover or phone width', (t) async {
      Future<void> pumpAt(Size size) async {
        await t.binding.setSurfaceSize(size);
        await t.pumpWidget(wrap(const MedsCareScreen()));
        await t.pump();
      }

      addTearDown(() => t.binding.setSurfaceSize(null));

      await pumpAt(const Size(1100, 1600));
      expect(t.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);

      await pumpAt(const Size(344, 1600)); // Fold5 cover
      expect(t.getSize(find.byType(ListView)).width, 344);

      await pumpAt(const Size(390, 1600)); // standard phone
      expect(t.getSize(find.byType(ListView)).width, 390);
    });
  });

  group('live wiring — the real medication/emergency-card routes '
      '(server/routes.mjs, packages/db/src/pool.ts recordDose/medicationsFor)', () {
    testWidgets('shows a loading indicator, then real fetched medications/doses/'
        'allergies replace the demo fixtures', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/medications')) {
          return http.Response(jsonEncode({
            'localDate': '2026-08-04',
            'medications': [
              {'id': 'm1', 'name': 'Real Med', 'dose': '10 mg', 'slots': ['morning'],
               'isPrn': false, 'minGapHours': null},
            ],
            'doses': <dynamic>[],
          }), 200);
        }
        if (req.url.path.endsWith('/emergency-card')) {
          return http.Response(jsonEncode({
            'bloodType': 'O positive', 'allergies': ['Real allergy'],
            'conditions': ['Real condition'], 'pediatricianName': null,
            'pediatricianPractice': null, 'pediatricianPhone': null,
            'insuranceProvider': null, 'insuranceMemberId': null,
            'guardians': <dynamic>[], 'medications': <dynamic>[],
          }), 200);
        }
        return http.Response('not found', 404);
      });
      await pump(t, MedsCareScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();

      expect(find.textContaining('Real Med'), findsOneWidget);
      expect(find.textContaining('Methylphenidate'), findsNothing);
      expect(find.text('Real allergy'), findsOneWidget);
      expect(find.text('Real condition'), findsOneWidget);
    });

    testWidgets('logging a dose POSTs to the real route and marks it given', (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') {
          posts.add(req);
          return http.Response(jsonEncode({
            'id': 'd1', 'medicationId': 'm1', 'localDate': '2026-08-04',
            'slot': 'morning', 'administeredAt': '2026-08-04T12:00:00.000Z', 'status': 'given',
          }), 201);
        }
        if (req.url.path.endsWith('/medications')) {
          return http.Response(jsonEncode({
            'localDate': '2026-08-04',
            'medications': [
              {'id': 'm1', 'name': 'Real Med', 'dose': '10 mg', 'slots': ['morning'],
               'isPrn': false, 'minGapHours': null},
            ],
            'doses': <dynamic>[],
          }), 200);
        }
        return http.Response(jsonEncode({'allergies': <dynamic>[], 'conditions': <dynamic>[],
          'guardians': <dynamic>[], 'medications': <dynamic>[]}), 200);
      });
      await pump(t, MedsCareScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      await t.tap(find.text('Log dose'));
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/v1/children/child-a/medications/m1/doses');
      expect(jsonDecode(posts.single.body), {'slot': 'morning', 'status': 'given'});
      expect(find.text('Given today'), findsOneWidget);
    });

    testWidgets('a real 409 already_administered response is decoded into the same '
        'names-the-parent-and-time banner text the demo path already renders', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') {
          return http.Response(jsonEncode({
            'error': 'already_administered', 'by': 'Mom', 'atIso': '2026-08-04T13:05:00.000Z',
          }), 409);
        }
        if (req.url.path.endsWith('/medications')) {
          return http.Response(jsonEncode({
            'localDate': '2026-08-04',
            'medications': [
              {'id': 'm1', 'name': 'Real Med', 'dose': '10 mg', 'slots': ['morning'],
               'isPrn': false, 'minGapHours': null},
            ],
            'doses': <dynamic>[],
          }), 200);
        }
        return http.Response(jsonEncode({'allergies': <dynamic>[], 'conditions': <dynamic>[],
          'guardians': <dynamic>[], 'medications': <dynamic>[]}), 200);
      });
      await pump(t, MedsCareScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      await t.tap(find.text('Log dose'));
      await t.pumpAndSettle();

      expect(find.textContaining('Mom gave this dose at'), findsOneWidget);
      // Still shows the Log dose control -- the refused attempt never
      // marked it given.
      expect(find.text('Given today'), findsNothing);
    });

    testWidgets('with no live params supplied, the demo fixtures render exactly '
        'as before — no network call, no loading state', (t) async {
      await pump(t, const MedsCareScreen());
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Methylphenidate'), findsOneWidget);
    });
  });
}
