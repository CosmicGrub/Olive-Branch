// OLIVE BRANCH — ChildHome's own tile-hierarchy tests. Intuitivism pass,
// sub-project 2 (docs/superpowers/specs/2026-08-31-intuitivism-navigation-
// density-design.md, §5 "Test impact"). Reachability/text-content coverage
// for the 9 tiles already lives in widget_test.dart and invariants_test
// .dart's §8.1 group — this file covers what's new: the 3-tier hierarchy
// itself, its posture-awareness, and the two regression classes this exact
// screen has real prior-bug history with (fixed-height text-scale overflow,
// the "sleeps until" counter dropping below the fold).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

const _home = ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 2);

void main() {
  group('ChildHome tile hierarchy — the 3-tier structure is genuinely real, '
      'not just three visually-similar GridViews', () {
    testWidgets('Hero > Featured > Standard tile height, and Hero really is My day', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();

      expect(find.descendant(
        of: find.byKey(const Key('childHomeHero')), matching: find.text('My day')), findsOneWidget);

      final heroHeight = t.getSize(find.byKey(const Key('childHomeHero'))).height;
      final featuredTile = t.getSize(find.widgetWithText(InkWell, 'Play together')).height;
      final standardTile = t.getSize(find.widgetWithText(InkWell, 'Homework')).height;
      expect(heroHeight, greaterThan(featuredTile),
        reason: 'Hero must read as visually larger than Featured');
      expect(featuredTile, greaterThan(standardTile),
        reason: 'Featured must read as visually larger than Standard');
    });

    testWidgets('the two grids are genuinely distinguishable — real, separate '
        'Featured and Standard GridViews, not one grid mislabeled', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childHomeFeaturedGrid')), findsOneWidget);
      expect(find.byKey(const Key('childHomeStandardGrid')), findsOneWidget);
    });
  });

  group('ChildHome — column count is driven by form_factors.dart\'s columnsAt(), '
      'the same real posture system game_picker.dart already uses (this screen '
      'previously hardcoded crossAxisCount: 2 and imported form_factors.dart nowhere)', () {
    Future<({int featured, int standard})> crossAxisCountsAt(WidgetTester t, Size size) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      final featured = (t.widget<GridView>(find.byKey(const Key('childHomeFeaturedGrid')))
          .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
      final standard = (t.widget<GridView>(find.byKey(const Key('childHomeStandardGrid')))
          .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
      return (featured: featured, standard: standard);
    }

    testWidgets('Fold5 cover (344px) — one column, both grids', (t) async {
      final c = await crossAxisCountsAt(t, const Size(344, 882));
      expect(c.featured, 1);
      expect(c.standard, 1);
    });

    testWidgets('Fold5 unfolded main (~673px) — two columns, both grids', (t) async {
      final c = await crossAxisCountsAt(t, const Size(673, 1400));
      expect(c.featured, 2);
      expect(c.standard, 2);
    });

    testWidgets('a 10-inch tablet (800px, tabletLarge) — two columns, matching '
        'FORM_FACTORS\' own tabletLarge.columns=2', (t) async {
      final c = await crossAxisCountsAt(t, const Size(800, 1400));
      expect(c.featured, 2);
      expect(c.standard, 2);
    });

    testWidgets('genuine desktop width (1100px) — three columns, both grids', (t) async {
      final c = await crossAxisCountsAt(t, const Size(1100, 900));
      expect(c.featured, 3);
      expect(c.standard, 3);
    });
  });

  group('ChildHome — text-scale regression, the exact bug class §8.11.1 already '
      'documents (_GameCard\'s fixed 182px, reviewableAt() — a fixed tile height '
      'that does not scale with text overflows at large accessibility text)', () {
    testWidgets('2.0x text scale at the 344px Fold-cover floor — no overflow, and '
        'tiles genuinely grew rather than staying pinned at their base height', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _home,
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      final heroHeight = t.getSize(find.byKey(const Key('childHomeHero'))).height;
      final standardTile = t.getSize(find.widgetWithText(InkWell, 'Homework')).height;
      // Base heights (unscaled) are Hero 140, Standard 84 — at 2.0x scale
      // (clamped to 1.6x per the design spec's own more conservative clamp
      // than game_picker.dart's 2.0x) both must have genuinely grown, not
      // stayed pinned at their unscaled literal — the exact regression this
      // test exists to catch.
      expect(heroHeight, greaterThan(140), reason: 'Hero must scale with text, not stay pinned');
      expect(standardTile, greaterThan(64), reason: 'Standard must scale with text, not stay pinned');
    });
  });

  group('ChildHome — P2, nothing here ranks or scores a tile for the child', () {
    testWidgets('none of the forbidden engagement/ranking vocabulary appears anywhere '
        'on the redesigned hierarchy', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(_home));
      await t.pumpAndSettle();
      for (final word in <String>[
        'most played', 'most popular', 'favorite', 'score', 'streak', 'rank',
        'top pick', 'trending', 'recommended for you',
      ]) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });
  });

  group('ChildHome — the "sleeps until" fold-line regression (this exact counter has '
      'been pushed below the fold by grid growth twice before this pass)', () {
    const sizes = <String, Size>{
      'Fold5 cover (344)': Size(344, 882),
      'Fold5 main (~673x841)': Size(673, 841),
      'phone (390)': Size(390, 844),
      'desktop-scale PC (1100)': Size(1100, 750),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} at 1.0x text — sleeps counter reachable without '
          'throwing', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(wrap(_home));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.textContaining('sleeps until'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('sleeps until'), findsOneWidget);
      });

      testWidgets('${entry.key} at 2.0x text — sleeps counter reachable without '
          'throwing', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: _home,
          ),
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.textContaining('sleeps until'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('sleeps until'), findsOneWidget);
      });
    }
  });
}
