// OLIVE BRANCH — availability_screen.dart tests. MASTERFILE §9.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/availability_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// 7 day rows + the save button + the co-guardian section together run past
/// the default 800x600 test surface — matches guardian_more_test.dart's own
/// documented reason for doing the same (SingleChildScrollView still needs a
/// tall enough surface for `tap()` to reach what's rendered but scrolled out
/// of the default viewport).
Future<void> pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

http.Client mockFor({
  List<Map<String, dynamic>> windows = const <Map<String, dynamic>>[],
  int getStatus = 200,
  int devLoginStatus = 200,
  List<Map<String, dynamic>>? capturedPuts,
}) {
  return MockClient((req) async {
    if (req.url.path == '/v1/auth/dev-login') {
      return devLoginStatus >= 400
          ? http.Response(jsonEncode({'error': 'user_not_found'}), devLoginStatus)
          : http.Response(jsonEncode({'token': 'tok'}), 200);
    }
    if (req.method == 'GET' && req.url.path.endsWith('/availability')) {
      return getStatus >= 400
          ? http.Response(jsonEncode({'error': 'no_edge'}), getStatus)
          : http.Response(jsonEncode({'windows': windows}), 200);
    }
    if (req.method == 'PUT' && req.url.path == '/v1/me/availability') {
      if (capturedPuts != null) {
        final body = jsonDecode(req.body) as List<dynamic>;
        capturedPuts.addAll(body.cast<Map<String, dynamic>>());
      }
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('AvailabilityScreen — loading and error states', () {
    testWidgets('shows a loading indicator before the fetch resolves', (t) async {
      final mock = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      });
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1', httpClient: mock)));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('a real network failure shows the real error screen, not a fake state', (t) async {
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor(getStatus: 403))));
      await t.pumpAndSettle();
      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Try again re-fetches for real', (t) async {
      var calls = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode({'token': 'tok'}), 200);
        calls++;
        if (calls == 1) return http.Response(jsonEncode({'error': 'boom'}), 500);
        return http.Response(jsonEncode({'windows': <dynamic>[]}), 200);
      });
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1', httpClient: mock)));
      await t.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('When you can be reached'), findsOneWidget);
    });
  });

  group('AvailabilityScreen — real fetched data', () {
    testWidgets('renders the caller\'s own windows and co-guardians\' windows, real names, no ids on screen', (t) async {
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor(windows: <Map<String, dynamic>>[
          {'guardianId': 'dad-1', 'guardianName': 'Dad', 'weekday': 1,
            'startLocal': '09:00', 'endLocal': '12:00', 'note': 'mornings'},
          {'guardianId': 'mom-1', 'guardianName': 'Mom', 'weekday': 2,
            'startLocal': '13:00', 'endLocal': '15:00', 'note': null},
        ]))));
      await t.pumpAndSettle();
      // Her own row shows real times, not a placeholder.
      expect(find.text('Monday'), findsOneWidget);
      expect(find.textContaining('9:00'), findsWidgets);
      expect(find.textContaining('12:00'), findsWidgets);
      // The co-guardian section shows the real name, not a raw uuid.
      expect(find.textContaining('Mom'), findsOneWidget);
      expect(find.textContaining('mom-1'), findsNothing);
      expect(find.textContaining('dad-1'), findsNothing);
    });

    testWidgets('an empty co-guardian list says so honestly, not a blank space', (t) async {
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor(windows: const <Map<String, dynamic>>[]))));
      await t.pumpAndSettle();
      expect(find.text('No co-guardian has set their availability yet.'), findsOneWidget);
      // Every day shows the empty affordance, not a stray range.
      expect(find.text('Set a window'), findsNWidgets(7));
    });
  });

  group('AvailabilityScreen — editing and saving', () {
    testWidgets('clearing a day removes it from what gets saved', (t) async {
      final captured = <Map<String, dynamic>>[];
      await pumpTall(t, AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor(
          windows: <Map<String, dynamic>>[
            {'guardianId': 'dad-1', 'guardianName': 'Dad', 'weekday': 1,
              'startLocal': '09:00', 'endLocal': '12:00', 'note': null},
            {'guardianId': 'dad-1', 'guardianName': 'Dad', 'weekday': 3,
              'startLocal': '17:00', 'endLocal': '20:00', 'note': null},
          ],
          capturedPuts: captured,
        )));
      await t.pumpAndSettle();

      // Clear Monday's window. Only Monday (1) and Wednesday (3) had data,
      // so before this tap there are 5 blank days; after it, 6 (every day
      // but Wednesday).
      await t.tap(find.widgetWithIcon(IconButton, Icons.close).first);
      await t.pump();
      expect(find.text('Set a window'), findsNWidgets(6));

      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      expect(find.text('Availability saved.'), findsOneWidget);
      expect(captured.length, 1); // only Wednesday's window remains
      expect(captured.single['weekday'], 3);
    });

    testWidgets('opening the time picker for an unset day shows the real Material time picker',
        (t) async {
      await t.pumpWidget(wrap(AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor())));
      await t.pumpAndSettle();
      await t.tap(find.text('Set a window').first);
      await t.pumpAndSettle();
      // A real showTimePicker() call, not a fake dialog — proven by the
      // actual Material widget appearing, not a hand-rolled substitute.
      expect(find.byType(TimePickerDialog), findsOneWidget);
      // Cancel it — this test's job is proving the real picker opens, not
      // re-testing Flutter's own time-picker widget.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Set a window'), findsWidgets); // still unset — cancelled, not silently set
    });

    testWidgets('Save round-trips real weekday/startLocal/endLocal/note to PUT /v1/me/availability',
        (t) async {
      final captured = <Map<String, dynamic>>[];
      await pumpTall(t, AvailabilityScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: mockFor(
          windows: <Map<String, dynamic>>[
            {'guardianId': 'dad-1', 'guardianName': 'Dad', 'weekday': 5,
              'startLocal': '08:00', 'endLocal': '10:00', 'note': 'school run'},
          ],
          capturedPuts: captured,
        )));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(captured.single, <String, dynamic>{
        'weekday': 5, 'startLocal': '08:00', 'endLocal': '10:00', 'note': 'school run',
      });
    });
  });
}
