// OLIVE BRANCH — entry gate tests. §8.5.0.
//
// Renders MARKUP screen "welcome". The load-bearing invariant: choosing a
// side navigates somewhere real but grants no authority by itself (see
// entry_gate.dart's header for why that's stated on-screen, not just implied
// by code elsewhere). Also the one file in this batch with an existing,
// documented layout fix (LayoutBuilder + ConstrainedBox for the Fold5's
// unfolded short-and-wide viewport) — the responsive group below is what
// actually pins that fix down across every required width, which nothing
// before this audit did.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/entry_gate.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('EntryGate — §8.5.0', () {
    testWidgets('choosing "my child\'s device" navigates to the child destination',
        (t) async {
      await t.pumpWidget(wrap(const EntryGate(
        childDestination: Text('CHILD SIDE'),
        grownupDestination: Text('GROWNUP SIDE'))));
      await t.tap(find.text("My child's device"));
      await t.pumpAndSettle();
      expect(find.text('CHILD SIDE'), findsOneWidget);
      expect(find.text('GROWNUP SIDE'), findsNothing);
    });

    testWidgets('choosing "the grown-up\'s device" navigates to the grownup destination',
        (t) async {
      await t.pumpWidget(wrap(const EntryGate(
        childDestination: Text('CHILD SIDE'),
        grownupDestination: Text('GROWNUP SIDE'))));
      await t.tap(find.text("The grown-up's device"));
      await t.pumpAndSettle();
      expect(find.text('GROWNUP SIDE'), findsOneWidget);
      expect(find.text('CHILD SIDE'), findsNothing);
    });

    testWidgets('states plainly that choosing a side grants no authority',
        (t) async {
      await t.pumpWidget(wrap(const EntryGate(
        childDestination: SizedBox(), grownupDestination: SizedBox())));
      expect(find.textContaining('unlocks nothing by itself'), findsOneWidget);
    });

    testWidgets('§8.4-style touch targets are at least 48dp for pre-readers',
        (t) async {
      await t.pumpWidget(wrap(const EntryGate(
        childDestination: SizedBox(), grownupDestination: SizedBox())));
      final Size childButton = t.getSize(find.byType(FilledButton).first);
      expect(childButton.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('the subtitle and disclaimer use the themed secondary text '
        'color, not a hardcoded black (design-token audit finding #1)',
        (t) async {
      await t.pumpWidget(wrap(const EntryGate(
        childDestination: SizedBox(), grownupDestination: SizedBox())));
      final BuildContext context = t.element(find.text('Welcome'));
      final Color onSurfaceVariant =
          Theme.of(context).colorScheme.onSurfaceVariant;
      final Text subtitle = t.widget(find.text('Which side is this?'));
      final Text disclaimer = t.widget(
          find.text('Choosing a side here unlocks nothing by itself.'));
      expect(subtitle.style!.color, onSurfaceVariant);
      expect(disclaimer.style!.color, onSurfaceVariant);
    });
  });

  group('responsive layout — phone, Fold5 (cover + main), and desktop-scale '
      'PC widths', () {
    const Map<String, Size> widths = <String, Size>{
      'Fold5 cover (344)': Size(344, 882),
      // The specific viewport this screen's own LayoutBuilder + ScrollView
      // fix was written for: short and nearly-square, where a bare centered
      // Column previously overflowed the bottom by 21px on a real device.
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
        await t.pumpWidget(wrap(const EntryGate(
          childDestination: SizedBox(), grownupDestination: SizedBox())));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
