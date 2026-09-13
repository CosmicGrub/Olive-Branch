// OLIVE BRANCH — guardian_home_live.dart tests. §7, §8.2, §20.2b.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/calendar_day_logic.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_home_live.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Map<String, dynamic> _dayPart(String kind, String startsLocal, String endsLocal,
        {bool reachable = true}) =>
    {'kind': kind, 'startsLocal': startsLocal, 'endsLocal': endsLocal, 'reachable': reachable};

Map<String, dynamic> _window(String startLocal, String endLocal, {String? note}) =>
    {'startLocal': startLocal, 'endLocal': endLocal, 'note': note};

/// Real server shape for GET .../now (routes.mjs's real handler — see
/// child_home_live_test.dart's own identically-shaped fixture).
Map<String, dynamic> _nowBody({String childLocalTime = '4:15 PM', String zoneAbbr = 'EDT',
        String? dayPart, bool? reachable}) =>
    {'childLocalTime': childLocalTime, 'zoneAbbr': zoneAbbr, 'zone': 'America/New_York',
      'sleepsUntilHandover': null, 'dayPart': dayPart, 'reachable': reachable};

/// Real server shape for GET .../ribbon (routes.mjs's real handler, new this
/// pass) — deliberately never includes an `overlapLabel` key at all, mirroring
/// what the real route actually sends (see that route's own comment on why).
Map<String, dynamic> _ribbonBody({
  String childName = 'Ivy',
  List<Map<String, dynamic>> dayParts = const [],
  List<Map<String, dynamic>> actorWindows = const [],
}) => {'childName': childName, 'dayParts': dayParts, 'actorWindows': actorWindows};

MockClient _mock({
  Map<String, dynamic>? now,
  Map<String, dynamic>? ribbon,
  int statusCode = 200,
}) => MockClient((req) async {
  if (statusCode != 200) {
    return http.Response(jsonEncode({'error': 'child_not_found'}), statusCode);
  }
  if (req.url.path == '/v1/auth/dev-login') {
    return http.Response(jsonEncode({'token': 'tok'}), 200);
  }
  if (req.url.path.endsWith('/now')) {
    return http.Response(jsonEncode(now ?? _nowBody()), 200);
  }
  if (req.url.path.endsWith('/ribbon')) {
    return http.Response(jsonEncode(ribbon ?? _ribbonBody()), 200);
  }
  return http.Response('not found', 404);
});

void main() {
  group('LiveGuardianHomeScreen', () {
    testWidgets('shows a loading indicator before the fetch resolves', (t) async {
      final mock = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      });
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Drain the pending delayed response so no timer survives past teardown.
      await t.pumpAndSettle();
    });

    testWidgets('renders real fetched childName, clock, and day-parts '
        'through the real GuardianHome', (t) async {
      final mock = _mock(
        now: _nowBody(childLocalTime: '9:14 PM', zoneAbbr: 'EST'),
        ribbon: _ribbonBody(childName: 'Ivy', dayParts: [
          _dayPart('school', '08:00', '15:00'),
          _dayPart('dinner', '18:00', '18:30'),
        ]),
      );
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('9:14 PM'), findsOneWidget);
      expect(find.text('EST'), findsOneWidget);
      // The two real day-parts rendered as real ribbon bands, labelled with
      // calendar_day_logic.dart's own dayPartLabel() text — the same shared
      // lookup my_day.dart's own Day Ribbon uses.
      expect(find.byTooltip(dayPartLabel('school')), findsOneWidget);
      expect(find.byTooltip(dayPartLabel('dinner')), findsOneWidget);
    });

    testWidgets('renders the caller\'s own real availability window as a '
        'band, labelled by its own note', (t) async {
      final mock = _mock(ribbon: _ribbonBody(actorWindows: [
        _window('17:00', '20:00', note: 'evenings'),
      ]));
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.byTooltip('evenings'), findsOneWidget);
    });

    testWidgets('a window with no note falls back to an honest generic label, '
        'never a blank tooltip', (t) async {
      final mock = _mock(ribbon: _ribbonBody(actorWindows: [
        _window('17:00', '20:00'),
      ]));
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.byTooltip('available'), findsOneWidget);
    });

    testWidgets('childStateSentence and overlapLabel render as nothing — '
        'no real source exists yet, and this screen never fabricates one',
        (t) async {
      final mock = _mock();
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      // Direct proof, not just an absence-of-text guess: the real
      // GuardianHome instance this screen constructed genuinely has both
      // fields null, not a fabricated placeholder string.
      final home = t.widget<GuardianHome>(find.byType(GuardianHome));
      expect(home.childStateSentence, isNull);
      expect(home.overlapLabel, isNull);
      // And GuardianHome's own conditional rendering (both fields already
      // tested at the static-widget level in invariants_test.dart) still
      // renders nothing for either — no exception, no placeholder text.
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('an overnight (wrap-past-midnight) day-part renders as two '
        'contiguous bands, same technique as my_day.dart\'s own ribbon',
        (t) async {
      final mock = _mock(ribbon: _ribbonBody(dayParts: [
        _dayPart('asleep', '20:00', '06:30'),
      ]));
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      // Exactly TWO RibbonBand widgets, both carrying the SAME label/
      // tooltip — bandsFromDayParts() splits an overnight part into two
      // contiguous rectangles (my_day.dart's own _bandRects precedent), one
      // logical band, not two different day-parts.
      expect(find.byTooltip(dayPartLabel('asleep')), findsNWidgets(2));
    });

    testWidgets('real dayPart/reachable from /now thread through to the '
        'real GuardianHome instance, not fabricated or dropped', (t) async {
      final mock = _mock(now: _nowBody(dayPart: 'school', reachable: false));
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      final home = t.widget<GuardianHome>(find.byType(GuardianHome));
      expect(home.dayPart, 'school');
      expect(home.reachable, isFalse);
    });

    testWidgets('reaches the real, live SendTimeGuardScreen end to end — '
        'GET /now\'s real dayPart/reachable render there, not the demo '
        'ChoiceChip hour-toggle', (t) async {
      final mock = _mock(now: _nowBody(
        childLocalTime: '9:14 PM', zoneAbbr: 'EST', dayPart: 'asleep', reachable: false));
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Send-time guard'));
      await t.pumpAndSettle();
      await t.tap(find.text('Send-time guard'));
      await t.pumpAndSettle();

      expect(find.textContaining("It's 9:14 PM for Ivy — she is sleep."), findsOneWidget);
      expect(find.text('Send now anyway'), findsOneWidget);
      // The demo hour chips must not appear on the real live path.
      expect(find.text('10:40 PM'), findsNothing);
    });

    testWidgets('shows a retry affordance when the server is unreachable, never a crash',
        (t) async {
      final mock = _mock(statusCode: 404);
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'nope',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('404'), findsOneWidget);
    });

    testWidgets('a real 403 (not a parent of this child) shows the same honest '
        'error state, not a crash or a silent blank screen', (t) async {
      final mock = _mock(statusCode: 403);
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
    });

    testWidgets('the error icon and message use the themed secondary color, '
        'not a hardcoded black — same design-token discipline '
        'child_home_live_test.dart already established', (t) async {
      final mock = _mock(statusCode: 404);
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'nope',
        httpClient: mock)));
      await t.pumpAndSettle();

      final BuildContext context = t.element(find.text("Couldn't reach the server"));
      final Color onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
      final Icon icon = t.widget<Icon>(find.byIcon(Icons.cloud_off));
      expect(icon.color, onSurfaceVariant);
    });

    testWidgets('retry re-runs the fetch and can recover into the ready state', (t) async {
      // Mirrors child_home_live_test.dart's own retry test exactly: fails
      // only on the very first dev-login attempt, succeeds on every request
      // after that (including the retry's own dev-login, attempt == 2).
      var attempt = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          attempt++;
          if (attempt == 1) return http.Response(jsonEncode({'error': 'boom'}), 500);
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/now')) {
          return http.Response(jsonEncode(_nowBody()), 200);
        }
        if (req.url.path.endsWith('/ribbon')) {
          return http.Response(jsonEncode(_ribbonBody(childName: 'Ivy')), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
        baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a',
        httpClient: mock)));
      await t.pumpAndSettle();
      expect(find.text("Couldn't reach the server"), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text("Couldn't reach the server"), findsNothing);
    });
  });
}
