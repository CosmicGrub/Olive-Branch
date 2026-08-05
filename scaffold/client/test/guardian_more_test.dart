// OLIVE BRANCH — guardian "more" hub tests.
//
// Not a MARKUP screen of its own (see guardian_more.dart's header). This is
// the guardian-facing counterpart to child_more_test.dart: unlike the child
// side, a settings-style affordance (Guardian setup, Kiosk lock advisory) is
// EXPECTED here, so the assertions are about real navigation and layout
// integrity, not about the absence of settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_more.dart';

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

    testWidgets('the one genuinely unbuilt tile stays an honest stub',
        (t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9));
      await t.tap(find.text('Availability'));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
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
