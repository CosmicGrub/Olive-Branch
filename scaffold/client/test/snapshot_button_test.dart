// OLIVE BRANCH — snapshot_button.dart tests. MASTERFILE §9.15.
//
// Mirrors packages/homework/test/snapshot.test.mjs's sections N and O
// against the Dart port and widget, plus the "visibly absent, not merely
// disabled" requirement that is specific to a UI (the TS suite only checks
// the logic function, since it has no widget layer).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/snapshot_button.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// MASTERFILE's own mandated minimum widths for a responsive audit: the
/// Fold5's cover screen and its unfolded main screen, plus a standard phone
/// width and a desktop-scale width now that Windows is a real target (§5.20).
const List<Size> kResponsiveSizes = <Size>[
  Size(344, 820), // Fold5 cover screen
  Size(673, 841), // Fold5 main screen, unfolded
  Size(390, 844), // standard phone
  Size(1100, 900), // tablet / desktop-scale, short-and-wide
];

Future<void> useSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('N — screenshot capture: refused on the call surface, not silently taken', () {
    test('exactly the three call surfaces are scoped off', () {
      final List<String> sorted = screenshotScopedOffSurfaces.toList()..sort();
      expect(sorted, <String>['call_video', 'live_call', 'pane_video']);
    });

    test('each call surface is refused with a plain retry message', () {
      for (final String surface in screenshotScopedOffSurfaces) {
        final ScreenshotCaptureResult r = captureScreenshot(surface);
        expect(r.ok, isFalse, reason: surface);
        expect(r.reason, ScreenshotRefusal.callSurface, reason: surface);
        expect(r.advice, "Let's try that again.", reason: surface);
      }
    });

    test('an ordinary surface is allowed and marked saved', () {
      final ScreenshotCaptureResult r = captureScreenshot('home');
      expect(r.ok, isTrue);
      expect(r.message, 'Saved to your gallery.');
    });
  });

  group('O — the one guarantee, and no tally shown to her', () {
    test('neverToDeviceGallery and autoUploadsToAppStorage hold', () {
      expect(neverToDeviceGallery, isTrue);
      expect(autoUploadsToAppStorage, isTrue);
    });

    test('the gallery holds what was added, newest first', () {
      final AppGallery gallery = AppGallery();
      gallery.add(AppPhoto(id: '1', surface: 'home', savedAt: DateTime(2026, 1, 1)));
      gallery.add(AppPhoto(id: '2', surface: 'my_day', savedAt: DateTime(2026, 1, 2)));
      expect(gallery.photos.map((p) => p.id).toList(), <String>['2', '1']);
    });
  });

  group('SnapshotButton — visibly absent, never merely disabled, on a call surface', () {
    testWidgets('renders a real button on an ordinary surface', (t) async {
      final AppGallery gallery = AppGallery();
      await t.pumpWidget(wrap(SnapshotButton(currentSurface: 'home', gallery: gallery)));
      expect(find.byKey(const Key('snapshotButton')), findsOneWidget);
    });

    testWidgets('is entirely absent on every scoped-off call surface', (t) async {
      final AppGallery gallery = AppGallery();
      for (final String surface in screenshotScopedOffSurfaces) {
        await t.pumpWidget(wrap(SnapshotButton(currentSurface: surface, gallery: gallery)));
        expect(find.byKey(const Key('snapshotButton')), findsNothing, reason: surface);
        expect(find.byType(FloatingActionButton), findsNothing, reason: surface);
      }
    });

    testWidgets('tapping saves into the AppGallery, never a device path', (t) async {
      final AppGallery gallery = AppGallery();
      await t.pumpWidget(wrap(SnapshotButton(currentSurface: 'my_day', gallery: gallery)));
      expect(gallery.photos, isEmpty);
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pump();
      expect(gallery.photos, hasLength(1));
      expect(gallery.photos.single.surface, 'my_day');
    });

    testWidgets('the button shows no numeric badge or count', (t) async {
      final AppGallery gallery = AppGallery();
      gallery.add(AppPhoto(id: '1', surface: 'home', savedAt: DateTime.now()));
      gallery.add(AppPhoto(id: '2', surface: 'home', savedAt: DateTime.now()));
      await t.pumpWidget(wrap(SnapshotButton(currentSurface: 'home', gallery: gallery)));
      expect(find.text('2'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ photo')), findsNothing);
    });

    testWidgets('the touch target is at least 48dp', (t) async {
      final AppGallery gallery = AppGallery();
      await t.pumpWidget(wrap(SnapshotButton(currentSurface: 'home', gallery: gallery)));
      final Size size = t.getSize(find.byKey(const Key('snapshotButton')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('AppGalleryScreen — her own gallery, never the device roll', () {
    testWidgets('shows an honest empty state before anything is saved', (t) async {
      final AppGallery gallery = AppGallery();
      await t.pumpWidget(MaterialApp(home: AppGalleryScreen(gallery: gallery)));
      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
    });

    testWidgets('renders one tile per saved photo', (t) async {
      final AppGallery gallery = AppGallery()
        ..add(AppPhoto(id: '1', surface: 'home', savedAt: DateTime.now()))
        ..add(AppPhoto(id: '2', surface: 'home', savedAt: DateTime.now()));
      await t.pumpWidget(MaterialApp(home: AppGalleryScreen(gallery: gallery)));
      expect(find.byIcon(Icons.image_outlined), findsNWidgets(2));
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      final String label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('the button on an ordinary surface renders without overflow at $label',
          (t) async {
        await useSurface(t, size);
        final AppGallery gallery = AppGallery();
        await t.pumpWidget(wrap(SnapshotButton(currentSurface: 'home', gallery: gallery)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });

      testWidgets('the gallery (with photos) renders without overflow at $label', (t) async {
        await useSurface(t, size);
        final AppGallery gallery = AppGallery()
          ..add(AppPhoto(id: '1', surface: 'home', savedAt: DateTime.now()))
          ..add(AppPhoto(id: '2', surface: 'home', savedAt: DateTime.now()));
        await t.pumpWidget(MaterialApp(home: AppGalleryScreen(gallery: gallery)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
