import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/form_factors.dart' as ff;

void main() {
  // Tall surface so every section is actually laid out by the ListView's
  // sliver — a viewport too short leaves off-screen sections unbuilt, which
  // would make "not found" indistinguishable from "not rendered".
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: EmergencyCardScreen()));
  }

  testWidgets('allergy warning renders with the specific demo allergy',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('allergyCard')), findsOneWidget);
    expect(find.textContaining('Peanuts'), findsOneWidget);
    expect(find.textContaining('EpiPen'), findsOneWidget);
  });

  testWidgets('allergy card sits above every other section on screen',
      (tester) async {
    await pump(tester);
    final allergyTop = tester.getTopLeft(find.byKey(const Key('allergyCard'))).dy;

    for (final laterText in [
      'Blood type', 'Current medications', 'Guardians',
      'Pediatrician', 'Insurance',
    ]) {
      final sectionTop = tester.getTopLeft(find.text(laterText.toUpperCase())).dy;
      expect(allergyTop, lessThan(sectionTop),
        reason: '$laterText header should be below the allergy card');
    }
  });

  testWidgets('blood type renders with a real demo value', (tester) async {
    await pump(tester);
    expect(find.text('O positive'), findsOneWidget);
  });

  testWidgets('medications render with name, dose, and schedule', (tester) async {
    await pump(tester);
    expect(find.text('Cetirizine'), findsOneWidget);
    expect(find.textContaining('5 mg'), findsOneWidget);
    expect(find.text('Albuterol inhaler'), findsOneWidget);
    expect(find.textContaining('as needed'), findsOneWidget);
  });

  testWidgets('both guardians render with names and phone numbers',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('Claire Solomon'), findsOneWidget);
    expect(find.textContaining('Marcus Solomon'), findsOneWidget);
    expect(find.text('(617) 555-0142'), findsOneWidget);
    expect(find.text('(617) 555-0198'), findsOneWidget);
  });

  testWidgets('pediatrician renders with name and phone', (tester) async {
    await pump(tester);
    expect(find.textContaining('Dr. Priya Nair'), findsOneWidget);
    expect(find.text('(617) 555-0177'), findsOneWidget);
  });

  testWidgets('insurance renders with provider and member ID', (tester) async {
    await pump(tester);
    expect(find.text('BlueBridge Family Health'), findsOneWidget);
    expect(find.textContaining('BBH-7734-2201'), findsOneWidget);
  });

  testWidgets('everything fits on one screen with no tabs or expand/collapse',
      (tester) async {
    await pump(tester);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('has no interactive form fields — this is a read-only screen',
      (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Radio), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('the non-functional Call button reports itself honestly',
      (tester) async {
    await pump(tester);
    final callButtons = find.byIcon(Icons.call);
    expect(callButtons, findsWidgets);

    await tester.tap(callButtons.first);
    await tester.pump();
    expect(find.textContaining('not built yet.'), findsOneWidget);
  });

  testWidgets('no animated widgets are used anywhere on this still surface',
      (tester) async {
    await pump(tester);
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byType(AnimatedPositioned), findsNothing);
  });

  group('read aloud — §8.8.5', () {
    testWidgets('absent speak reports itself honestly, exactly like the Call buttons',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EmergencyCardScreen()));
      await tester.tap(find.byKey(const Key('readAloudButton')));
      await tester.pump();
      expect(find.textContaining('Read aloud — not built yet.'), findsOneWidget);
    });

    testWidgets('a real speak callback is called once, allergy-first, verbatim',
        (tester) async {
      final List<String> spoken = [];
      await tester.pumpWidget(MaterialApp(home: EmergencyCardScreen(
        speak: (text) async => spoken.add(text))));
      await tester.tap(find.byKey(const Key('readAloudButton')));
      await tester.pump();

      expect(spoken, hasLength(1));
      final String text = spoken.single;
      expect(text.indexOf('Allergies'), lessThan(text.indexOf('Blood type')),
        reason: 'allergy-first, matching the on-screen reading order');
      expect(text, contains('Peanuts'));
      expect(text, contains('EpiPen'));
      expect(text, contains('Claire Solomon'));
      expect(text, contains('Marcus Solomon'));
      expect(text, contains('BBH-7734-2201'));
    });

    testWidgets('does not fire the not-built-yet message when a real speak exists',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: EmergencyCardScreen(
        speak: (text) async {})));
      await tester.tap(find.byKey(const Key('readAloudButton')));
      await tester.pump();
      expect(find.textContaining('not built yet'), findsNothing);
    });
  });

  testWidgets('allergy card uses theme error roles, not raw red literals — '
      'so it stays legible in dark theme', (tester) async {
    await pump(tester);
    final BuildContext context = tester.element(find.text('ALLERGIES'));
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Card card = tester.widget(find.byKey(const Key('allergyCard')));
    expect(card.color, scheme.errorContainer);
    final RoundedRectangleBorder shape = card.shape! as RoundedRectangleBorder;
    expect(shape.side.color, scheme.error);

    final Icon warningIcon = tester.widget(find.byIcon(Icons.warning_rounded));
    expect(warningIcon.color, scheme.error);

    final Text allergiesLabel = tester.widget(find.text('ALLERGIES'));
    expect(allergiesLabel.style!.color, scheme.onErrorContainer);
  });

  group('responsive — comfortable reading width cap (form_factors.dart)', () {
    // §8.13.5 "still" surface, read once, possibly in a hurry (see file
    // header). On a wide tablet/desktop viewport the single column is only
    // ever capped to a comfortable reading width and centered, never split —
    // the allergy-first scan order is untouched either way. The Fold5 cover
    // and phone widths are completely untouched by this cap.
    testWidgets('the cap engages only on a wide tablet/desktop viewport — '
        'never at the Fold5 cover or phone width', (tester) async {
      Future<void> pumpAt(Size size) async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(const MaterialApp(home: EmergencyCardScreen()));
        await tester.pump();
      }

      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpAt(const Size(1100, 1600));
      expect(tester.getSize(find.byKey(const Key('emergencyCardList'))).width,
          ff.comfortableReadingWidth);

      await pumpAt(const Size(344, 1600)); // Fold5 cover
      expect(tester.getSize(find.byKey(const Key('emergencyCardList'))).width, 344);

      await pumpAt(const Size(390, 1600)); // standard phone
      expect(tester.getSize(find.byKey(const Key('emergencyCardList'))).width, 390);
    });
  });

  group('live wiring — the real medical_record-backed emergency card '
      '(server/routes.mjs, packages/db/src/pool.ts medicalRecordFor)', () {
    Future<void> pumpTall(WidgetTester t, Widget child) async {
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: child));
    }

    testWidgets('shows a loading indicator, then real fetched fields replace the '
        'demo fixtures, including a real, LIVE-derived guardian phone', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        expect(req.url.path, '/v1/children/child-a/emergency-card');
        return http.Response(jsonEncode({
          'bloodType': 'AB negative', 'allergies': ['Real shellfish allergy'],
          'conditions': <dynamic>[], 'pediatricianName': 'Dr. Real Doctor',
          'pediatricianPractice': 'Real Pediatrics', 'pediatricianPhone': '(555) 000-1111',
          'insuranceProvider': 'RealCare Health', 'insuranceMemberId': 'RC-0001',
          'guardians': [
            {'userId': 'dad-1', 'name': 'Real Dad', 'phone': '+15555550001'},
          ],
          'medications': [
            {'id': 'm1', 'name': 'Real Medicine', 'dose': '1 tablet', 'slots': ['morning'],
             'isPrn': false},
          ],
        }), 200);
      });
      await pumpTall(t, EmergencyCardScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();

      expect(find.textContaining('Real shellfish allergy'), findsOneWidget);
      expect(find.textContaining('Peanuts'), findsNothing);
      expect(find.text('AB negative'), findsOneWidget);
      expect(find.text('Real Medicine'), findsOneWidget);
      expect(find.textContaining('Real Dad'), findsOneWidget);
      expect(find.text('+15555550001'), findsOneWidget);
      expect(find.textContaining('Claire Solomon'), findsNothing);
      expect(find.text('Dr. Real Doctor — Real Pediatrics'), findsOneWidget);
      expect(find.text('RealCare Health'), findsOneWidget);
      expect(find.textContaining('RC-0001'), findsOneWidget);
    });

    testWidgets('the real live speak callback reads the real fetched fields, '
        'allergy-first, not the demo const text', (t) async {
      final List<String> spoken = <String>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode({
          'bloodType': 'AB negative', 'allergies': ['Real shellfish allergy'],
          'conditions': <dynamic>[], 'pediatricianName': null, 'pediatricianPractice': null,
          'pediatricianPhone': null, 'insuranceProvider': null, 'insuranceMemberId': null,
          'guardians': [
            {'userId': 'dad-1', 'name': 'Real Dad', 'phone': '+15555550001'},
          ],
          'medications': <dynamic>[],
        }), 200);
      });
      await pumpTall(t, EmergencyCardScreen(
        speak: (text) async => spoken.add(text),
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('readAloudButton')));
      await t.pump();

      expect(spoken, hasLength(1));
      final String text = spoken.single;
      expect(text.indexOf('Allergies'), lessThan(text.indexOf('Blood type')));
      expect(text, contains('Real shellfish allergy'));
      expect(text, contains('Real Dad'));
      expect(text, isNot(contains('Claire Solomon')));
    });

    testWidgets('a real fetch failure is an honest error with a working retry, never '
        'a crash or a silent fallback to the demo fixtures', (t) async {
      int calls = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        calls++;
        if (calls == 1) return http.Response('server error', 500);
        return http.Response(jsonEncode({
          'bloodType': null, 'allergies': <dynamic>[], 'conditions': <dynamic>[],
          'pediatricianName': null, 'pediatricianPractice': null, 'pediatricianPhone': null,
          'insuranceProvider': null, 'insuranceMemberId': null,
          'guardians': <dynamic>[], 'medications': <dynamic>[],
        }), 200);
      });
      await pumpTall(t, EmergencyCardScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-a',
        httpClient: mock));
      await t.pumpAndSettle();

      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('allergyCard')), findsOneWidget);
      expect(find.textContaining('None on file'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('with no live params supplied, the demo fixtures render exactly '
        'as before — no network call, no loading state', (t) async {
      await pumpTall(t, const EmergencyCardScreen());
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Peanuts'), findsOneWidget);
      expect(find.textContaining('Claire Solomon'), findsOneWidget);
    });
  });
}
