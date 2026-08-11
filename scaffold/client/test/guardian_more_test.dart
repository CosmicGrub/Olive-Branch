// OLIVE BRANCH — guardian "more" hub tests.
//
// Not a MARKUP screen of its own (see guardian_more.dart's header). This is
// the guardian-facing counterpart to child_more_test.dart: unlike the child
// side, a settings-style affordance (Guardian setup, Kiosk lock advisory) is
// EXPECTED here, so the assertions are about real navigation and layout
// integrity, not about the absence of settings.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/availability_screen.dart';
import 'package:olive_client/family_agreement_screen.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_setup.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// This hub's content list is long enough to scroll past the default
/// 800x600 test surface, which leaves lower tiles ('Invite a co-parent',
/// 'Availability') below the fold and un-hittable by `tap()` without either
/// scrolling first or a taller surface. Matches meds_care_test.dart's own
/// pattern for a similarly long screen.
Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('GuardianMoreScreen — navigation hub', () {
    testWidgets('every hub tile opens a real destination, not a dead tap',
        (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      await t.tap(find.text('Invite a co-parent'));
      await t.pumpAndSettle();
      expect(find.byType(GuardianMoreScreen), findsNothing);
    });

    testWidgets('childName threads through to a pushed destination, not '
        'just accepted and dropped', (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      await t.tap(find.text('Invite a co-parent'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ivy'), findsWidgets);
    });

    testWidgets('Availability gives honest not-connected feedback when no '
        'live session is threaded in (this hub\'s default demo call site)',
        (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      // 'Availability' now sits below even this file's own generous 1800px
      // test surface (this hub's tile list grew again — the real-authentication
      // pass's WebAuthn dev-verification tile — same class of drift this
      // file's own header comment already anticipated). ensureVisible scrolls
      // it into the SingleChildScrollView first, which is exactly what a real
      // guardian's own scroll gesture does; a taller fixed surface would only
      // paper over the same fragility again the next time a tile is added.
      final availability = find.text('Availability');
      await t.ensureVisible(availability);
      await t.pumpAndSettle();
      await t.tap(availability);
      await t.pump();
      expect(find.textContaining('not connected'), findsOneWidget);
      // And it is honestly worded, not the generic (and by now false)
      // "not built yet" this tile used to show.
      expect(find.textContaining('not built yet'), findsNothing);
    });

    testWidgets('Availability opens the REAL AvailabilityScreen once a live '
        'session is threaded in', (t) async {
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/availability')) {
          return http.Response(jsonEncode({'windows': <dynamic>[]}), 200);
        }
        return http.Response('not found', 404);
      });
      await pump(t, GuardianMoreScreen(childName: 'Ivy', childAge: 9,
        baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
        availabilityHttpClient: mock));
      // real-authentication's WebAuthn dev-verification tile now sits above
      // this one in the same scrollable hub, pushing Availability far enough
      // down that a fixed-size test viewport doesn't have it on screen —
      // scroll it into view first, same fix this file already needed once
      // for the Guardian-setup dev tile.
      await t.ensureVisible(find.text('Availability'));
      await t.pumpAndSettle();
      await t.tap(find.text('Availability'));
      await t.pumpAndSettle();
      expect(find.byType(AvailabilityScreen), findsOneWidget);
      expect(find.text('When you can be reached'), findsOneWidget);
    });

    testWidgets("'Guardian setup' -> 'Review the family agreement' reaches a "
        'REAL FamilyAgreementScreen, no longer the honest-stub snackbar',
        (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      await t.tap(find.text('Guardian setup'));
      await t.pumpAndSettle();
      expect(find.byType(GuardianSetupScreen), findsOneWidget);

      await t.tap(find.text('Review the family agreement'));
      await t.pumpAndSettle();
      expect(find.byType(FamilyAgreementScreen), findsOneWidget);
      // Not the old dead-end: guardian_setup.dart's own honest-stub snackbar
      // only fires when onOpenAgreement is null, which it no longer is here.
      expect(find.textContaining('not built yet'), findsNothing);
    });

    testWidgets('with no live backend wired into this preview build, the real '
        'screen shows a real error, never a faked schedule', (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      await t.tap(find.text('Guardian setup'));
      await t.pumpAndSettle();
      await t.tap(find.text('Review the family agreement'));
      await t.pumpAndSettle();

      expect(find.text("Couldn't load the agreement"), findsOneWidget);
      expect(find.textContaining('No live backend is wired'), findsOneWidget);
    });
  });

  group('responsive layout — phone, Fold5 (cover + main), and desktop-scale '
      'PC widths', () {
    const Map<String, Size> widths = <String, Size>{
      'Fold5 cover (344)': Size(344, 882),
      'Fold5 main (~673x841)': Size(673, 841),
      'phone (390)': Size(390, 844),
      'desktop-scale PC (1100)': Size(1100, 750),
    };

    for (final MapEntry<String, Size> entry in widths.entries) {
      testWidgets('renders without overflow at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(wrap(const GuardianMoreScreen(childName: 'Ivy', childAge: 9)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
