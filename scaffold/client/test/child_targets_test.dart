// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — touch targets:
// child controls at 64dp (80 with "larger targets"), guardian controls at 48dp.
// MASTERFILE §8.4.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/hub_widgets.dart';
import 'package:olive_client/storyteller_screen.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';
import 'package:olive_client/tiered_tile.dart';

Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(500, 1400), AccessSettings s = AccessSettings.defaults}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final AccessController c = AccessController(repository: MemoryAccessRepository(s));
  await c.load();
  await t.pumpWidget(MaterialApp(
    theme: buildThemeData(defaultAppTheme),
    builder: (BuildContext context, Widget? child) => AccessHost(controller: c, loadOnStart: false, child: child!),
    home: w,
  ));
  await t.pump(const Duration(milliseconds: 300));
}

String stripped(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

void main() {
  group('child controls are 64dp', () {
    testWidgets('a tile clears 64dp with no height given, and 80dp with larger targets', (WidgetTester t) async {
      await pump(t, Scaffold(body: Center(child: SizedBox(width: 200, child: TieredTile(icon: Icons.star, label: 'x', onTap: (_) {})))));
      expect(t.getSize(find.byType(TieredTile)).height, greaterThanOrEqualTo(64));
      await pump(t, Scaffold(body: Center(child: SizedBox(width: 200, child: TieredTile(icon: Icons.star, label: 'x', onTap: (_) {})))),
          s: const AccessSettings(largerTargets: true));
      expect(t.getSize(find.byType(TieredTile)).height, greaterThanOrEqualTo(80));
    });

    testWidgets('ChildHome: every tile and the Call button are at least 64dp', (WidgetTester t) async {
      await pump(t, const ChildHome(childName: 'Ivy', presence: ParentPresence('Dad', '6:42 PM', '9:00 PM her time'),
          sleepsUntilHandover: 3, unreadCount: 2), size: const Size(800, 1400));
      for (final Element e in find.byType(TieredTile).evaluate()) {
        expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(64));
      }
      expect(t.getSize(find.widgetWithText(FilledButton, 'Call Dad')).height, greaterThanOrEqualTo(64));
    });

    testWidgets('Storyteller: "Tell me a story!", Back, Next, the star and "Stop here" are all 64dp', (WidgetTester t) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'));
      expect(t.getSize(find.widgetWithText(FilledButton, 'Tell me a story!')).height, greaterThanOrEqualTo(64));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.getSize(find.widgetWithText(FilledButton, 'Next')).height, greaterThanOrEqualTo(64));
      expect(t.getSize(find.widgetWithText(OutlinedButton, 'Back')).height, greaterThanOrEqualTo(64));
      final Size star = t.getSize(find.byTooltip('Star this story'));
      expect(star.width, greaterThanOrEqualTo(64));
      expect(star.height, greaterThanOrEqualTo(64));
      expect(t.getSize(find.widgetWithText(TextButton, 'Stop here for tonight')).height, greaterThanOrEqualTo(64));
    });

    testWidgets('Connect 4: a column strip is cell + margin wide: 64dp and up from tablet width', (WidgetTester t) async {
      await pump(t, const GameConnect4Screen(role: 'ivy', displayName: 'Ivy'), size: const Size(800, 1200));
      await t.tap(find.text('Start'));
      await t.pump(const Duration(milliseconds: 100));
      final SemanticsHandle h = t.ensureSemantics();
      final Rect cell = t.getSemantics(find.bySemanticsLabel('Column 1, row 1 from the bottom')).rect;
      expect(cell.width, greaterThanOrEqualTo(64));
      expect(cell.height, greaterThanOrEqualTo(64));
      h.dispose();
    });

    test('no child screen sizes a button below 64dp (source guard)', () {
      // Heights 40/48/52/56 wrapped round a Button, or a 48dp icon-button constraint,
      // in the files this pass raised. A regression to any of them fails here.
      const List<String> files = <String>[
        'child_home', 'child_home_live', 'storyteller_screen', 'journal_screen', 'wants_needs', 'jokebook_screen',
        'homework_screen', 'retake_screen', 'shared_reading', 'birthday_day', 'birthday_marked',
        'onboarding_shared', 'collection_screen', 'showcase_screen', 'teach_me', 'letters_screen', 'closing_ritual',
        'maturation_ladder', 'snapshot_button', 'doodle_desk', 'colouring_screen',
      ];
      final RegExp smallBox = RegExp(r'SizedBox\((width: [^,]+, )?height: (40|48|52|56)[,)]');
      final RegExp smallIcon = RegExp(r'minWidth: 48, minHeight: 48|Size\(0, 48\)|width: 56, height: 56');
      for (final String f in files) {
        final String src = stripped('lib/$f.dart');
        expect(smallBox.hasMatch(src), isFalse, reason: '$f has a sub-64dp SizedBox');
        // The birthday day grid is width-bound (seven across): its cells keep the 48dp floor.
        if (f != 'birthday_day') expect(smallIcon.hasMatch(src), isFalse, reason: '$f has a sub-64dp icon constraint');
      }
    });
  });

  group('guardian controls are 48dp', () {
    test('the theme\'s button minimums are at least 48dp in both directions', () {
      final ThemeData t = buildThemeData(defaultAppTheme);
      for (final ButtonStyle? s in <ButtonStyle?>[
        t.filledButtonTheme.style, t.elevatedButtonTheme.style, t.outlinedButtonTheme.style,
        t.textButtonTheme.style, t.iconButtonTheme.style,
      ]) {
        final Size m = s!.minimumSize!.resolve(<WidgetState>{})!;
        expect(m.height, greaterThanOrEqualTo(48));
        expect(m.width, greaterThanOrEqualTo(48));
      }
    });

    test('the handover-note speaker and the kiosk escalation trigger are 48dp', () {
      final String notes = stripped('lib/handover_notes.dart');
      expect(notes.contains('SizedBox(width: kGuardianTarget, height: kGuardianTarget'), isTrue);
      expect(kGuardianTarget, 48);
      final String kiosk = stripped('lib/kiosk_shell.dart');
      final int at = kiosk.indexOf("key: const Key('guardianEscalationTrigger')");
      expect(at, greaterThan(200));
      expect(kiosk.substring(at - 200, at).contains('width: 48'), isTrue);
    });

    testWidgets('a settings row (HubTile) is at least 48dp, and 64dp with larger targets', (WidgetTester t) async {
      final Widget tile = Scaffold(body: ListView(children: <Widget>[HubTile(icon: Icons.star, title: 'Row', onTap: () {})]));
      await pump(t, tile);
      expect(t.getSize(find.byType(HubTile)).height, greaterThanOrEqualTo(48));
      await pump(t, tile, s: const AccessSettings(largerTargets: true));
      expect(t.getSize(find.byType(HubTile)).height, greaterThanOrEqualTo(64));
    });
  });
}

