// OLIVE BRANCH — gallery tests. MASTERFILE §9.10.11.
//
// Pure-logic tests for the grouping/pagination helpers and `frameFor()`
// (the exact function MASTERFILE names as "the difference between an
// aspiration and a testable claim"), plus widget tests against the real
// screen for the two properties that matter most: a hidden work leaves no
// trace anywhere, and a collection past two thousand pieces paginates by era
// instead of trying to lay out the whole archive at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/archive_models.dart';
import 'package:olive_client/gallery_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Artifact _artifact(String id, DateTime capturedAt, {String kind = 'drawing'}) => Artifact(
      id: id, childId: 'ivy', kind: kind, storageKey: 'demo://$id',
      capturedAt: capturedAt, capturedTz: 'local', preserved: true,
    );

void main() {
  group('eraForYear', () {
    test('buckets by the documented age bands', () {
      expect(eraForYear(2018), 'Little one');
      expect(eraForYear(2020), 'Little one');
      expect(eraForYear(2021), 'Growing up');
      expect(eraForYear(2023), 'Growing up');
      expect(eraForYear(2024), 'These days');
      expect(eraForYear(2026), 'These days');
    });
  });

  group('generateGalleryDemo', () {
    test('returns exactly the requested count', () {
      expect(generateGalleryDemo(count: 500, seed: 1).length, 500);
      expect(generateGalleryDemo(count: 0, seed: 1).length, 0);
    });

    test('is deterministic for a given seed — same run, same collection', () {
      final List<GalleryPiece> a = generateGalleryDemo(count: 200, seed: 42);
      final List<GalleryPiece> b = generateGalleryDemo(count: 200, seed: 42);
      for (int i = 0; i < a.length; i++) {
        expect(a[i].artifact.capturedAt, b[i].artifact.capturedAt);
        expect(a[i].artifact.kind, b[i].artifact.kind);
        expect(a[i].hiddenFromGuardian, b[i].hiddenFromGuardian);
      }
    });
  });

  group('visiblePieces — §21.2', () {
    test('excludes hidden works entirely and sorts the rest oldest-first', () {
      final List<GalleryPiece> pieces = <GalleryPiece>[
        GalleryPiece(artifact: _artifact('c', DateTime(2025, 1, 1))),
        GalleryPiece(artifact: _artifact('a', DateTime(2020, 1, 1))),
        GalleryPiece(artifact: _artifact('hidden', DateTime(2019, 1, 1)), hiddenFromGuardian: true),
      ];
      final List<String> ids =
          visiblePieces(pieces).map((GalleryPiece p) => p.artifact.id).toList();
      expect(ids, <String>['a', 'c']);
    });
  });

  group('groupByYear / groupByEra', () {
    test('groupByYear buckets by capture year and sorts each bucket oldest-first', () {
      final List<GalleryPiece> pieces = <GalleryPiece>[
        GalleryPiece(artifact: _artifact('late-2025', DateTime(2025, 12, 1))),
        GalleryPiece(artifact: _artifact('early-2025', DateTime(2025, 1, 1))),
        GalleryPiece(artifact: _artifact('2024', DateTime(2024, 6, 1))),
      ];
      final Map<int, List<GalleryPiece>> byYear = groupByYear(pieces);
      expect(byYear.keys.toSet(), <int>{2024, 2025});
      expect(byYear[2025]!.map((GalleryPiece p) => p.artifact.id).toList(),
          <String>['early-2025', 'late-2025']);
    });

    test('groupByEra buckets every piece into exactly one named era', () {
      final List<GalleryPiece> pieces = <GalleryPiece>[
        GalleryPiece(artifact: _artifact('a', DateTime(2019, 1, 1))),
        GalleryPiece(artifact: _artifact('b', DateTime(2022, 1, 1))),
        GalleryPiece(artifact: _artifact('c', DateTime(2025, 1, 1))),
      ];
      final Map<String, List<GalleryPiece>> byEra = groupByEra(pieces);
      expect(byEra['Little one']!.single.artifact.id, 'a');
      expect(byEra['Growing up']!.single.artifact.id, 'b');
      expect(byEra['These days']!.single.artifact.id, 'c');
    });
  });

  group('frameFor — §9.10.11, "identical frame for every medium"', () {
    test('returns a structurally identical decoration regardless of kind', () {
      final ColorScheme scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      final BoxDecoration drawing = frameFor(scheme, 'drawing');
      final BoxDecoration photo = frameFor(scheme, 'photo');
      final BoxDecoration photoOfObject = frameFor(scheme, 'photo_of_object');
      final BoxDecoration collage = frameFor(scheme, 'collage');
      expect(drawing, photo, reason: 'a drawing and a photo must hang identically framed');
      expect(photo, photoOfObject,
          reason: 'a photographed physical work gets no different treatment than a photo');
      expect(photoOfObject, collage);
    });
  });

  group('GalleryScreen — the widget itself', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const GalleryScreen()));
    }

    testWidgets('defaults to the full demo collection, paginated by era',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('Full (2,200+)'), findsOneWidget);
      // Era chips, oldest era first, each carrying its own item count.
      expect(find.textContaining('Little one'), findsOneWidget);
      expect(find.textContaining('Growing up'), findsOneWidget);
      expect(find.textContaining('These days'), findsOneWidget);
      // Oldest era opens by default — its minimum year is the first header.
      expect(find.text('2018'), findsOneWidget);
    });

    testWidgets('switching era changes which years are shown, not just a count',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('2018'), findsOneWidget);

      await tester.tap(find.textContaining('These days'));
      await tester.pumpAndSettle();

      expect(find.text('2018'), findsNothing);
      expect(find.text('2024'), findsOneWidget);
    });

    testWidgets('no "hidden" count or hint ever appears — a hide is invisible, not flagged',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining(RegExp('hidden', caseSensitive: false)), findsNothing);

      await tester.tap(find.textContaining('Growing up'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp('hidden', caseSensitive: false)), findsNothing);
    });

    testWidgets('the small preview collection does not paginate by era',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Little one'), findsNothing);
      expect(find.textContaining('Growing up'), findsNothing);
      expect(find.textContaining('These days'), findsNothing);
    });

    testWidgets('no price, no settings affordance anywhere on this screen',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('closes with "Cardboard counts. It always did."', (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('Cardboard counts. It always did.'), findsOneWidget);
    });
  });
}
