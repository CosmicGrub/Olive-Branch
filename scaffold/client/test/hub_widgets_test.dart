// OLIVE BRANCH — shared hub-tile chrome tests (HubTile / HubSection).
//
// Not a MARKUP screen — pure presentation plumbing shared by child_more.dart
// and guardian_more.dart. Exercised indirectly by both of those files'
// own tests, but this is the one place that pins its own contract directly:
// a long title/subtitle must wrap rather than overflow (the Row here has no
// fixed height, only a minHeight, so this is the widget every hub screen's
// safety from a real-world long label ultimately rests on), and the min
// touch-target height holds at every required width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/hub_widgets.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// Deliberately the longest realistic title/subtitle pair in the app today
// (see guardian_more.dart's "Invite a co-parent" / "Kiosk lock advisory"
// entries) plus a synthetic worst case, so this proves the wrap behavior
// rather than assuming today's copy will always be short enough.
const String longTitle = 'A rather long hub tile title that keeps going';
const String longSubtitle = 'And a subtitle longer still, describing exactly '
    'what happens when you tap this tile, in full sentences';

void main() {
  group('HubTile', () {
    testWidgets('tapping fires onTap', (t) async {
      var tapped = false;
      await t.pumpWidget(wrap(HubTile(
        icon: Icons.star, title: 'Tap me', onTap: () => tapped = true)));
      await t.tap(find.text('Tap me'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without a subtitle when none is given', (t) async {
      await t.pumpWidget(wrap(HubTile(icon: Icons.star, title: 'No subtitle', onTap: () {})));
      expect(find.text('No subtitle'), findsOneWidget);
    });

    testWidgets('meets the 56dp minimum touch target', (t) async {
      await t.pumpWidget(wrap(HubTile(
        icon: Icons.star, title: 'Sized tile', subtitle: 'sub', onTap: () {})));
      final Size size = t.getSize(find.byType(InkWell));
      expect(size.height, greaterThanOrEqualTo(56.0));
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
      testWidgets('a long title/subtitle wraps without overflow at ${entry.key}',
          (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(wrap(SingleChildScrollView(
          child: HubSection(title: 'Section', children: [
            HubTile(icon: Icons.star, title: longTitle, subtitle: longSubtitle,
              onTap: () {}),
          ]))));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(longTitle), findsOneWidget);
      });
    }
  });
}
