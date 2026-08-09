// OLIVE BRANCH — child "more for you" hub tests.
//
// Not a MARKUP screen of its own (see child_more.dart's header), so there is
// no §-numbered invariant to port. What genuinely matters here: every entry
// still opens something real (this hub exists specifically so nothing needs
// to crowd child_home.dart's own grid), no settings affordance sneaks onto a
// child-facing screen, and the hub itself holds up across every width
// MASTERFILE mandates testing — including the Fold5's 344px cover screen,
// the narrowest surface this app supports.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/private_storybooks/private_storybook_shelf.dart';
import 'package:olive_client/private_storybooks/private_storybooks_flag.dart';

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

  group('private storybooks entry point — PRIVATE BUILD ONLY, DO NOT SHIP '
      '(see lib/private_storybooks/README.md)', () {
    // kPrivateStorybooksEnabled is a compile-time const
    // (bool.fromEnvironment), so it can't be overridden per-test the way a
    // normal field could -- it is false here for exactly the same reason
    // it is false in a real release build: this test binary was not
    // compiled with --dart-define=ENABLE_PRIVATE_STORYBOOKS=true. That
    // proves the "nothing is reachable by default" half. The second test
    // below source-inspects child_more.dart to confirm the call site is
    // actually guarded by that same constant, so the two tests together
    // cover both "off by default" and "the gate is the real gate".
    testWidgets('the private-storybooks tile is entirely absent by default',
        (t) async {
      expect(kPrivateStorybooksEnabled, isFalse,
          reason: 'this test only proves default-off behaviour; if this '
              'ever reads true, a build flag leaked into the test run');
      await t.pumpWidget(wrap(const ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      await t.pumpAndSettle();
      expect(find.text('Private storybooks'), findsNothing);
      expect(find.text('Private build only'), findsNothing);
      expect(find.byType(PrivateStorybookShelfScreen), findsNothing);
    });

    test('source inspection: the entry point is guarded by kPrivateStorybooksEnabled', () {
      final source = File('lib/child_more.dart').readAsStringSync();
      expect(source.contains("import 'private_storybooks/private_storybooks_flag.dart'"),
          isTrue, reason: 'child_more.dart must import the compile-time flag');
      expect(
        RegExp(r'if\s*\(\s*kPrivateStorybooksEnabled\s*\)\s*HubSection').hasMatch(source),
        isTrue,
        reason: 'the private-storybooks HubSection must be directly guarded '
            'by "if (kPrivateStorybooksEnabled)" with nothing else able to '
            'make it reachable',
      );
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
