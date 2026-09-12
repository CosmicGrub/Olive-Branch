// OLIVE BRANCH — TieredTile's own independent unit test suite. Intuitivism
// pass, sub-project 3b (docs/superpowers/specs/2026-09-12-intuitivism-
// guardianhome-tiering-design.md, §Testing). child_home_test.dart and
// guardian_home_test.dart both cover TieredTile in the context of a real
// screen; this file covers the widget in isolation — featured/hero drive
// the right icon size/fill/text style on their own, independent of either
// caller, and badgeCount null/0 render no badge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tiered_tile.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: Scaffold(body: child),
    );

Color _fillOf(WidgetTester t, String label) =>
    (t.widget<Container>(find.widgetWithText(Container, label)).decoration! as BoxDecoration).color!;

void main() {
  group('TieredTile — standard (default) tier', () {
    testWidgets('28px icon, titleSmall text, primaryContainer fill', (t) async {
      await t.pumpWidget(wrap(TieredTile(icon: Icons.star, label: 'Standard tile', onTap: (_) {})));
      await t.pumpAndSettle();

      final icon = t.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.size, 28);

      final context = t.element(find.text('Standard tile'));
      final text = t.widget<Text>(find.text('Standard tile'));
      expect(text.style!.fontSize, Theme.of(context).textTheme.titleSmall!.fontSize);

      expect(_fillOf(t, 'Standard tile'), Theme.of(context).colorScheme.primaryContainer);
    });
  });

  group('TieredTile — featured tier', () {
    testWidgets('36px icon, titleMedium text, secondaryContainer fill', (t) async {
      await t.pumpWidget(wrap(
          TieredTile(icon: Icons.star, label: 'Featured tile', featured: true, onTap: (_) {})));
      await t.pumpAndSettle();

      final icon = t.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.size, 36);

      final context = t.element(find.text('Featured tile'));
      final text = t.widget<Text>(find.text('Featured tile'));
      expect(text.style!.fontSize, Theme.of(context).textTheme.titleMedium!.fontSize);

      expect(_fillOf(t, 'Featured tile'), Theme.of(context).colorScheme.secondaryContainer);
    });
  });

  group('TieredTile — hero tier', () {
    testWidgets('hero alone (no featured) keeps the 28px/titleSmall styling but switches '
        'the fill to tertiaryContainer — hero only ever changes fill on its own', (t) async {
      await t.pumpWidget(
          wrap(TieredTile(icon: Icons.star, label: 'Bare hero', hero: true, onTap: (_) {})));
      await t.pumpAndSettle();

      final icon = t.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.size, 28);
      expect(_fillOf(t, 'Bare hero'),
          Theme.of(t.element(find.text('Bare hero'))).colorScheme.tertiaryContainer);
    });

    testWidgets('featured + hero together (the real Hero-tile combination both screens use) — '
        '36px icon, titleMedium text, tertiaryContainer fill', (t) async {
      await t.pumpWidget(wrap(TieredTile(icon: Icons.star, label: 'Real hero',
          featured: true, hero: true, height: 140, onTap: (_) {})));
      await t.pumpAndSettle();

      final icon = t.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.size, 36);

      final context = t.element(find.text('Real hero'));
      final text = t.widget<Text>(find.text('Real hero'));
      expect(text.style!.fontSize, Theme.of(context).textTheme.titleMedium!.fontSize);
      expect(_fillOf(t, 'Real hero'), Theme.of(context).colorScheme.tertiaryContainer);
    });

    testWidgets('renders full-width via its own SizedBox wrapper, unlike non-hero tiles',
        (t) async {
      await t.pumpWidget(wrap(TieredTile(icon: Icons.star, label: 'Wide hero', hero: true, onTap: (_) {})));
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('Wide hero'),
          matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == double.infinity),
        ),
        findsOneWidget,
      );

      await t.pumpWidget(wrap(TieredTile(icon: Icons.star, label: 'Narrow tile', onTap: (_) {})));
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('Narrow tile'),
          matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == double.infinity),
        ),
        findsNothing,
      );
    });
  });

  group('TieredTile — badgeCount', () {
    testWidgets('null renders no badge at all', (t) async {
      await t.pumpWidget(wrap(TieredTile(icon: Icons.star, label: 'No badge', onTap: (_) {})));
      await t.pumpAndSettle();
      expect(find.text('0'), findsNothing);
    });

    testWidgets('0 renders no badge — not a badge showing "0"', (t) async {
      await t.pumpWidget(
          wrap(TieredTile(icon: Icons.star, label: 'Zero badge', badgeCount: 0, onTap: (_) {})));
      await t.pumpAndSettle();
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a positive count renders the number', (t) async {
      await t.pumpWidget(
          wrap(TieredTile(icon: Icons.star, label: 'Real badge', badgeCount: 3, onTap: (_) {})));
      await t.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a count over 9 renders as "9+"', (t) async {
      await t.pumpWidget(
          wrap(TieredTile(icon: Icons.star, label: 'Big badge', badgeCount: 15, onTap: (_) {})));
      await t.pumpAndSettle();
      expect(find.text('9+'), findsOneWidget);
    });
  });

  group('TieredTile — onTap', () {
    testWidgets('a null onTap falls back to the honest not-built-yet acknowledgment', (t) async {
      await t.pumpWidget(wrap(const TieredTile(icon: Icons.star, label: 'Unbuilt tile')));
      await t.tap(find.text('Unbuilt tile'));
      await t.pump();
      expect(find.textContaining('Unbuilt tile — not built yet.'), findsOneWidget);
    });

    testWidgets('a real onTap runs instead of the fallback', (t) async {
      var tapped = false;
      await t.pumpWidget(
          wrap(TieredTile(icon: Icons.star, label: 'Real tile', onTap: (_) => tapped = true)));
      await t.tap(find.text('Real tile'));
      await t.pump();
      expect(tapped, isTrue);
      expect(find.textContaining('not built yet'), findsNothing);
    });
  });

  group('TieredTile — §8.4 touch target floor', () {
    testWidgets('every tier clears the 64dp minimum height, with no explicit height supplied',
        (t) async {
      await t.pumpWidget(wrap(const TieredTile(icon: Icons.star, label: 'Floor check')));
      await t.pumpAndSettle();
      final size = t.getSize(find.widgetWithText(InkWell, 'Floor check'));
      expect(size.height, greaterThanOrEqualTo(64));
    });
  });
}
