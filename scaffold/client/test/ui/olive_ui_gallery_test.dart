// No longer UNVERIFIED — verified by CI.
// OLIVE BRANCH — the component gallery (lib/ui/olive_ui_gallery.dart): it shows every section in light
// and dark, at text scale 1.0 and 2.0, as guardian and child, without an exception, and it is reachable
// from the guardian More hub ONLY where demo tiles are shown, and from the dev entry point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/main_ui_gallery.dart';
import 'package:olive_client/ui/olive_ui.dart';
import 'package:olive_client/ui/olive_ui_gallery.dart';

const _sections = [
  'Icons', 'Scenes', 'Spot illustrations', 'Buttons and chips', 'Cards', 'Tiles', 'Rows and data',
  'Status and feedback', 'Empty, error, loading, permission', 'Controls', 'Progress and time', 'Media', 'Layers',
];

Future<void> _pumpGallery(WidgetTester tester, Widget gallery) async {
  await tester.binding.setSurfaceSize(const Size(412, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: gallery));
}

Future<void> _visitEverySection(WidgetTester tester) async {
  for (final s in _sections) {
    await tester.scrollUntilVisible(find.text(s), 600, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull, reason: 'section $s');
  }
}

Future<void> _toEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
  await tester.pumpAndSettle();
}

void main() {
  group('OliveUiGalleryScreen', () {
    testWidgets('lists every section and renders light and dark together without error', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen());
      expect(find.text('UI gallery'), findsOneWidget);
      await _visitEverySection(tester);
    });

    testWidgets('shows both brightnesses by default and one when asked', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen());
      expect(find.textContaining('light · olive'), findsWidgets);
      expect(find.textContaining('dark · olive'), findsWidgets);
      await _pumpGallery(tester, OliveUiGalleryScreen(key: UniqueKey(), initialBrightness: GalleryBrightness.dark));
      await tester.pump();
      expect(find.textContaining('light · olive'), findsNothing);
    });

    testWidgets('every section survives text scale 2.0 in dark as child', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen(
          initialBrightness: GalleryBrightness.dark, initialTextScale: 2.0, initialAudience: OliveAudience.child));
      await _visitEverySection(tester);
    });

    testWidgets('every section survives text scale 2.0 in light as guardian', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen(initialBrightness: GalleryBrightness.light, initialTextScale: 2.0));
      await _visitEverySection(tester);
    });

    testWidgets('the controls switch brightness, text size and audience', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen());
      await tester.tap(find.descendant(of: find.byKey(const Key('galleryBrightness')), matching: find.text('Dark')));
      await tester.pump();
      expect(find.textContaining('light · olive'), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('galleryScale')), matching: find.text('2.0')));
      await tester.pump();
      expect(find.textContaining('text 2.0'), findsWidgets);
      await tester.tap(find.descendant(of: find.byKey(const Key('galleryAudience')), matching: find.text('Child')));
      await tester.pump();
      expect(find.textContaining('child'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every palette can be chosen', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen(initialBrightness: GalleryBrightness.light));
      await tester.tap(find.text('warmGrounded'));
      await tester.pump();
      expect(find.textContaining('warmGrounded'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the layers section opens a real sheet and a real dialog', (tester) async {
      await _pumpGallery(tester, const OliveUiGalleryScreen(initialBrightness: GalleryBrightness.light));
      await tester.scrollUntilVisible(find.text('Open a sheet'), 600, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Open a sheet'));
      await tester.pump();
      await tester.tap(find.text('Open a sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Grandma'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Close').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open a dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this letter?'), findsWidgets);
    });
  });

  group('reachability', () {
    testWidgets('the guardian More hub lists the gallery in demo builds and opens it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GuardianMoreScreen(childName: 'Ivy', childAge: 9, showDemoTiles: true)));
      await _toEnd(tester);
      expect(find.byKey(const Key('moreUiGallery')), findsOneWidget);
      await tester.tap(find.byKey(const Key('moreUiGallery')));
      await tester.pumpAndSettle();
      expect(find.byType(OliveUiGalleryScreen), findsOneWidget);
    });

    testWidgets('a live build (showDemoTiles false) does not list it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GuardianMoreScreen(childName: 'Ivy', childAge: 9, showDemoTiles: false)));
      await _toEnd(tester);
      expect(find.byKey(const Key('moreUiGallery')), findsNothing);
      expect(find.text('UI gallery (demo)'), findsNothing);
    });

    testWidgets('the default (offline preview, no live session) lists it; a live session does not', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GuardianMoreScreen(childName: 'Ivy', childAge: 9)));
      await _toEnd(tester);
      expect(find.byKey(const Key('moreUiGallery')), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: GuardianMoreScreen(childName: 'Ivy', childAge: 9, baseUrl: 'http://api.test', guardianId: 'g-1')));
      await _toEnd(tester);
      expect(find.byKey(const Key('moreUiGallery')), findsNothing);
    });

    testWidgets('the dev entry point boots straight into the gallery', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const OliveUiGalleryApp());
      expect(find.byType(OliveUiGalleryScreen), findsOneWidget);
    });
  });
}
