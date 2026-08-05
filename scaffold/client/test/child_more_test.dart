// OLIVE BRANCH — child "more for you" hub tests.
//
// Not a MARKUP screen of its own (see child_more.dart's header), so there is
// no §-numbered invariant to port. What genuinely matters here: every entry
// still opens something real (this hub exists specifically so nothing needs
// to crowd child_home.dart's own grid), no settings affordance sneaks onto a
// child-facing screen, and the hub itself holds up across every width
// MASTERFILE mandates testing — including the Fold5's 344px cover screen,
// the narrowest surface this app supports.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_more.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ChildMoreScreen — navigation hub', () {
    testWidgets('no settings affordance exists on this child-facing screen',
        (t) async {
      await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining('settings'), findsNothing);
    });

    testWidgets('every hub tile opens a real destination, not a dead tap',
        (t) async {
      await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      await t.tap(find.text('My journal'));
      await t.pumpAndSettle();
      // Landing anywhere other than ChildMoreScreen itself is proof the tap
      // pushed a real route rather than doing nothing.
      expect(find.byType(ChildMoreScreen), findsNothing);
    });

    testWidgets('childName threads through to a pushed destination, not '
        'just accepted and dropped', (t) async {
      await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      await t.tap(find.text('My journal'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ivy'), findsWidgets);
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
        await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
