// OLIVE BRANCH — GuardianHome's own tile-hierarchy tests. Intuitivism pass,
// sub-project 3b (docs/superpowers/specs/2026-09-12-intuitivism-
// guardianhome-tiering-design.md, §Testing). Reachability/text-content
// coverage for the 11 tiles and the ribbon already lives in widget_test.dart
// and invariants_test.dart's own groups; this file covers what's new: the
// real Hero/Featured/Standard hierarchy itself, proof each tile lands in
// its ACTUAL assigned tier (not just "11 tiles render somewhere"), each
// tier's fill color, and the exact overflow class this screen has real
// prior-bug history with, now retested against the tiered layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_home.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

const _bands = <RibbonBand>[
  RibbonBand(0, 0.5, Colors.blue, 'school'),
  RibbonBand(0.5, 0.5, Colors.green, 'home time'),
];

const _home = GuardianHome(
  childName: 'Ivy', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
  actorLocalTime: '3:12 PM CDT', childStateSentence: 'Ivy is just home from school',
  childBands: _bands, actorBands: _bands, overlapLabel: 'both free 4:00-5:00 PM');

const _heroKey = Key('guardianHomeHero');
const _featuredKey = Key('guardianHomeFeaturedGrid');
const _standardKey = Key('guardianHomeStandardGrid');
const _tierKeys = <Key>[_heroKey, _featuredKey, _standardKey];

/// Every real destination this screen has, mapped to the ONE tier key it
/// must render inside — the spec's own tier table, restated as data so the
/// test below can prove membership AND non-membership for each.
const Map<String, Key> _expectedTier = {
  'Message banking': _heroKey,
  'Availability': _featuredKey,
  'Send-time guard': _featuredKey,
  'Meds & care': _featuredKey,
  'Emergency card': _featuredKey,
  'Handover notes': _standardKey,
  'Exchange': _standardKey,
  'Expenses': _standardKey,
  'Morning briefing': _standardKey,
  'Care note': _standardKey,
  'More': _standardKey,
};

void main() {
  group('GuardianHome tile hierarchy — the 3-tier structure is genuinely real, '
      'not just three visually-similar containers', () {
    testWidgets('all 11 tiles render, and each renders in its assigned tier '
        'ONLY — never also in one of the other two', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();

      for (final entry in _expectedTier.entries) {
        for (final key in _tierKeys) {
          final matcher = key == entry.value ? findsOneWidget : findsNothing;
          expect(
            find.descendant(of: find.byKey(key), matching: find.text(entry.key)),
            matcher,
            reason: '"${entry.key}" should render inside ${entry.value} and nowhere else',
          );
        }
      }
    });

    testWidgets('Hero sits above the Featured grid, and both sit above Standard', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();

      final heroY = t.getTopLeft(find.byKey(_heroKey)).dy;
      final featuredY = t.getTopLeft(find.byKey(_featuredKey)).dy;
      final standardY = t.getTopLeft(find.byKey(_standardKey)).dy;
      expect(heroY, lessThan(featuredY), reason: 'Hero must render above Featured');
      expect(featuredY, lessThan(standardY), reason: 'Featured must render above Standard');
    });

    testWidgets('Hero reads as visually larger (taller) than a Featured or Standard tile',
        (t) async {
      await t.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();

      final heroHeight = t.getSize(find.byKey(_heroKey)).height;
      final featuredTile = t.getSize(find.widgetWithText(InkWell, 'Availability')).height;
      final standardTile = t.getSize(find.widgetWithText(InkWell, 'Handover notes')).height;
      expect(heroHeight, greaterThan(featuredTile),
          reason: 'Hero must read as visually larger than Featured');
      // Unlike ChildHome's own two-height-tier grids, GuardianHome's
      // Featured and Standard grids deliberately share ONE mainAxisExtent
      // (the spec's own "only which tiles land in which grid, and each
      // grid's fill color, changes") — hierarchy between those two reads
      // through fill/icon/type-scale, not cell size.
      expect(featuredTile, equals(standardTile),
          reason: 'Featured and Standard share one cell height by design in this screen');
    });
  });

  group('GuardianHome tile hierarchy — fill color matches the assigned '
      'ColorScheme role (§4, never a chosen accent — P2)', () {
    testWidgets('Hero (Message banking) uses tertiaryContainer', (t) async {
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      final container = t.widget<Container>(find.widgetWithText(Container, 'Message banking'));
      final decoration = container.decoration! as BoxDecoration;
      final context = t.element(find.text('Message banking'));
      expect(decoration.color, Theme.of(context).colorScheme.tertiaryContainer);
    });

    testWidgets('Featured (Availability) uses secondaryContainer', (t) async {
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      final container = t.widget<Container>(find.widgetWithText(Container, 'Availability'));
      final decoration = container.decoration! as BoxDecoration;
      final context = t.element(find.text('Availability'));
      expect(decoration.color, Theme.of(context).colorScheme.secondaryContainer);
    });

    testWidgets('Standard (Handover notes) uses primaryContainer, unchanged from before this pass',
        (t) async {
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      final container = t.widget<Container>(find.widgetWithText(Container, 'Handover notes'));
      final decoration = container.decoration! as BoxDecoration;
      final context = t.element(find.text('Handover notes'));
      expect(decoration.color, Theme.of(context).colorScheme.primaryContainer);
    });
  });

  group('GuardianHome — the ribbon (Ivy\'s day bars, Call Ivy button) renders '
      'completely unchanged — a regression guard for this pass, not a new behavior', () {
    testWidgets('dual clock, the dominant state sentence, the subordinate actor '
        'line, and the Call button all still render', (t) async {
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('4:12 PM'), findsOneWidget);
      expect(find.text('EDT'), findsOneWidget);
      expect(find.text('Ivy is just home from school'), findsOneWidget);
      expect(find.text('you · 3:12 PM CDT'), findsOneWidget);
      expect(find.text('Call Ivy'), findsOneWidget);
    });

    testWidgets('both day-ribbon bands still render, each labelled by its own tooltip, '
        'and the overlap label still renders', (t) async {
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      // _home passes the same band list to both childBands and actorBands
      // (the same fixture shape invariants_test.dart's own GuardianHome
      // group already uses), so each label renders once per ribbon — two
      // real bands, not a duplicate.
      expect(find.byTooltip('school'), findsNWidgets(2));
      expect(find.byTooltip('home time'), findsNWidgets(2));
      expect(find.text('both free 4:00-5:00 PM'), findsOneWidget);
    });
  });

  group('GuardianHome — Fold5 cover-screen (344px) Hero band, the same overflow '
      'class the per-tile grid comment already documents, now rechecked for the '
      'Hero tile itself and for the Featured grid\'s own bigger icon/type-scale', () {
    // At 344px, intuitivism pass, sub-project 3c's own CoverCollapse (docs/
    // superpowers/specs/2026-09-12-intuitivism-fold5-layout-design.md, Part 1)
    // now replaces the Featured/Standard grids with its own collapsed
    // ribbon+Hero+"More" layout — neither grid exists in the tree at this
    // exact width any more to measure directly. See fold5_layout_test.dart's
    // own "GuardianHome — CoverCollapse, real at foldCover" group for the
    // collapse behavior itself; this group keeps its original job (the
    // Hero-vs-Featured overflow/height-ordering regression this screen has
    // real prior-bug history with) by reaching the SAME full layout the "More"
    // tile opens — relocated, not weakened or dropped.
    testWidgets('344px width — Hero renders "Message banking" with no overflow '
        'in the collapsed view', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 1700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      expect(
        find.descendant(of: find.byKey(_heroKey), matching: find.text('Message banking')),
        findsOneWidget,
      );
      expect(t.getSize(find.byKey(_heroKey)).height, greaterThan(0));
    });

    testWidgets('344px width, via "More" — Hero still reads taller than a Featured '
        'or Standard tile, and Featured/Standard heights still match, in the full '
        'layout the collapsed view opens', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 1700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();

      await t.tap(find.text('More'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      final heroHeight = t.getSize(find.byKey(_heroKey)).height;
      final featuredTile = t.getSize(find.widgetWithText(InkWell, 'Send-time guard')).height;
      final standardTile = t.getSize(find.widgetWithText(InkWell, 'Handover notes')).height;
      expect(heroHeight, greaterThan(featuredTile));
      expect(featuredTile, equals(standardTile));
    });
  });
}
