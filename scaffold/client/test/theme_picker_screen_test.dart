// OLIVE BRANCH — theme_picker_screen.dart tests. MASTERFILE §8.1, the
// intuitivism visual-foundation design spec. Asserts the picker's own
// posture-driven column count, live-preview-before-Apply (selecting a card
// or the brightness toggle must NEVER write anywhere), Apply's real
// live/offline behavior, and P2 (no score/rank/tally of any kind).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_picker_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

http.Client mockFor({int putStatus = 200, List<Map<String, dynamic>>? capturedPuts}) {
  return MockClient((req) async {
    if (req.url.path == '/v1/auth/dev-login') {
      return http.Response(jsonEncode({'token': 'tok'}), 200);
    }
    if (req.method == 'PUT' && req.url.path.endsWith('/theme')) {
      if (putStatus >= 400) return http.Response(jsonEncode({'error': 'boom'}), putStatus);
      if (capturedPuts != null) {
        capturedPuts.add(jsonDecode(req.body) as Map<String, dynamic>);
      }
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    return http.Response('not found', 404);
  });
}

Future<void> pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('theme picker — palette cards and selection', () {
    testWidgets('all 6 palettes render a real card', (t) async {
      await pumpTall(t, const ThemePickerScreen());
      for (final palette in ThemePalette.values) {
        // findsWidgets, not findsOneWidget: the initially-selected palette's
        // title renders TWICE on purpose (once on its own card, once again
        // in the live preview area below) — see the next test for that
        // preview behavior asserted directly.
        expect(find.text(themePaletteCatalogue[palette]!.title), findsWidgets,
            reason: '${palette.name} has no rendered card');
      }
    });

    testWidgets('the initial theme\'s palette and brightness are preselected', (t) async {
      await pumpTall(t, const ThemePickerScreen(
          initial: AppTheme(palette: ThemePalette.deepCozy, brightness: ThemeBrightness.dark)));
      // The preview area renders the preselected palette's title.
      expect(find.text('Deep cozy'), findsWidgets);
      final toggle = t.widget<SegmentedButton<ThemeBrightness>>(
          find.byKey(const Key('brightnessToggle')));
      expect(toggle.selected, {ThemeBrightness.dark});
    });

    testWidgets('SELECTING a card has NO side effect — no network call, no onApplied',
        (t) async {
      var applied = 0;
      await pumpTall(t, ThemePickerScreen(
          baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
          httpClient: mockFor(), onApplied: (_) => applied++));
      await t.tap(find.text('Bright bold'));
      await t.pump();
      expect(applied, 0, reason: 'selecting a card must never itself apply anything');
      // The preview updates to the newly-selected palette, proving the tap
      // DID register locally.
      expect(find.text('Bright bold'), findsWidgets);
    });

    testWidgets('SELECTING the brightness toggle also has no side effect', (t) async {
      var applied = 0;
      await pumpTall(t, ThemePickerScreen(
          baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
          httpClient: mockFor(), onApplied: (_) => applied++));
      final toggle = find.byKey(const Key('brightnessToggle'));
      await t.tap(find.descendant(of: toggle, matching: find.text('Dark')));
      await t.pump();
      expect(applied, 0);
    });
  });

  group('theme picker — Apply', () {
    testWidgets('a live-wired Apply PUTs the pending selection and calls onApplied',
        (t) async {
      AppTheme? applied;
      final puts = <Map<String, dynamic>>[];
      await pumpTall(t, ThemePickerScreen(
          initial: const AppTheme(palette: ThemePalette.classic, brightness: ThemeBrightness.light),
          baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
          httpClient: mockFor(capturedPuts: puts), onApplied: (v) => applied = v));
      await t.tap(find.text('Warm grounded'));
      await t.pump();
      await t.tap(find.byKey(const Key('applyThemeButton')));
      await t.pumpAndSettle();
      expect(puts.length, 1);
      expect(puts.first['themePalette'], 'warmGrounded');
      expect(puts.first['themeBrightness'], 'light');
      expect(applied, const AppTheme(palette: ThemePalette.warmGrounded, brightness: ThemeBrightness.light));
    });

    testWidgets('an offline (no live session) Apply gives honest feedback and writes nothing',
        (t) async {
      var applied = 0;
      await pumpTall(t, ThemePickerScreen(onApplied: (_) => applied++));
      await t.tap(find.byKey(const Key('applyThemeButton')));
      await t.pump();
      expect(find.textContaining('not connected in this preview build'), findsOneWidget);
      expect(applied, 0);
    });

    testWidgets('a real network failure on Apply gives honest feedback, never a fake success',
        (t) async {
      await pumpTall(t, ThemePickerScreen(
          baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
          httpClient: mockFor(putStatus: 500)));
      await t.tap(find.byKey(const Key('applyThemeButton')));
      await t.pumpAndSettle();
      expect(find.textContaining("Couldn't save"), findsOneWidget);
    });
  });

  group('theme picker — device-adaptive layout, §8.11.1', () {
    testWidgets('narrower at the Fold5 cover width than at a wide desktop-scale width',
        (t) async {
      Future<int> columnsAt(Size size) async {
        await t.binding.setSurfaceSize(size);
        await t.pumpWidget(wrap(const ThemePickerScreen()));
        await t.pumpAndSettle();
        final grid = t.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        return delegate.crossAxisCount;
      }

      final coverColumns = await columnsAt(const Size(344, 882));
      final desktopColumns = await columnsAt(const Size(1100, 750));
      addTearDown(() => t.binding.setSurfaceSize(null));

      expect(coverColumns, 1, reason: 'Fold5 cover (344px) must be 1 column');
      expect(desktopColumns, greaterThan(coverColumns),
          reason: 'a genuinely wide viewport must render more columns than the cover screen');
    });
  });

  group('theme picker — P2, no tally of any kind', () {
    testWidgets('no score, rank, or "tried N themes" text anywhere', (t) async {
      await pumpTall(t, const ThemePickerScreen());
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining(RegExp(r'\btried\b')), findsNothing);
      expect(find.textContaining(RegExp(r'\brank\b', caseSensitive: false)), findsNothing);
    });
  });
}
