// OLIVE BRANCH — archive model / Year Book compiler tests. §2.10, §9.8.2.
//
// Pure-logic tests against `compileYearBook()`, the same port-fidelity
// discipline lock_controller_test.dart applies to lock_controller.dart:
// assert the SAME properties packages/archive/test asserts against the TS
// original, against the Dart port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/archive_models.dart';

Artifact _a({
  required String id,
  required String kind,
  required DateTime capturedAt,
  String childId = 'ivy',
  String capturedTz = 'EST',
  bool preserved = true,
  String? eraTag,
}) =>
    Artifact(
      id: id, childId: childId, kind: kind, storageKey: 'demo://$id',
      capturedAt: capturedAt, capturedTz: capturedTz, preserved: preserved, eraTag: eraTag,
    );

void main() {
  group('compileYearBook — §9.8.2', () {
    test('only PRESERVED artifacts are compiled', () {
      final List<Artifact> all = <Artifact>[
        _a(id: '1', kind: 'drawing', capturedAt: DateTime(2025, 3, 1)),
        _a(id: '2', kind: 'drawing', capturedAt: DateTime(2025, 3, 2), preserved: false),
      ];
      final YearBook book = compileYearBook(all, 'ivy', 2025);
      expect(book.artifactCount, 1);
      expect(book.sections.single.artifactIds, <String>['1']);
    });

    test('only the requested child and year are included', () {
      final List<Artifact> all = <Artifact>[
        _a(id: '1', kind: 'drawing', capturedAt: DateTime(2025, 1, 1)),
        _a(id: '2', kind: 'drawing', capturedAt: DateTime(2024, 1, 1)), // wrong year
        _a(id: '3', kind: 'drawing', capturedAt: DateTime(2025, 1, 1), childId: 'sibling'), // wrong child
      ];
      final YearBook book = compileYearBook(all, 'ivy', 2025);
      expect(book.artifactCount, 1);
    });

    test('sections group by kind with the documented titles', () {
      final List<Artifact> all = <Artifact>[
        _a(id: 'said', kind: 'voice_note', capturedAt: DateTime(2025, 1, 1)),
        _a(id: 'made', kind: 'drawing', capturedAt: DateTime(2025, 1, 2)),
        _a(id: 'learned', kind: 'homework', capturedAt: DateTime(2025, 1, 3)),
        _a(id: 'moment', kind: 'photo', capturedAt: DateTime(2025, 1, 4)),
      ];
      final YearBook book = compileYearBook(all, 'ivy', 2025);
      final Map<String, List<String>> byTitle = <String, List<String>>{
        for (final YearBookSection s in book.sections) s.title: s.artifactIds,
      };
      expect(byTitle['Things you said'], <String>['said']);
      expect(byTitle['Things you made'], <String>['made']);
      expect(byTitle['Things you learned'], <String>['learned']);
      expect(byTitle['Moments'], <String>['moment']);
    });

    test('empty sections are dropped, not shown as zero-count', () {
      final List<Artifact> all = <Artifact>[
        _a(id: '1', kind: 'drawing', capturedAt: DateTime(2025, 1, 1)),
      ];
      final YearBook book = compileYearBook(all, 'ivy', 2025);
      expect(book.sections.length, 1);
      expect(book.sections.single.title, 'Things you made');
    });

    test('printable is false under twelve items, true at or above it', () {
      List<Artifact> nOf(int n) => List<Artifact>.generate(
          n, (int i) => _a(id: '$i', kind: 'drawing', capturedAt: DateTime(2025, 1, 1 + i)));

      expect(compileYearBook(nOf(11), 'ivy', 2025).printable, isFalse);
      expect(compileYearBook(nOf(12), 'ivy', 2025).printable, isTrue);
    });

    test('places counts DISTINCT captured days per zone, sorted by days descending', () {
      final List<Artifact> all = <Artifact>[
        // Two artifacts the same day in EST count as ONE day, not two.
        _a(id: '1', kind: 'drawing', capturedAt: DateTime(2025, 1, 1), capturedTz: 'EST'),
        _a(id: '2', kind: 'photo', capturedAt: DateTime(2025, 1, 1), capturedTz: 'EST'),
        _a(id: '3', kind: 'drawing', capturedAt: DateTime(2025, 2, 1), capturedTz: 'EST'),
        _a(id: '4', kind: 'photo', capturedAt: DateTime(2025, 3, 1), capturedTz: 'CST'),
      ];
      final YearBook book = compileYearBook(all, 'ivy', 2025);
      expect(book.places, <YearBookPlace>[
        const YearBookPlace(zone: 'EST', days: 2),
        const YearBookPlace(zone: 'CST', days: 1),
      ]);
    });

    test('YearBookPlace carries only a zone label and a day count — P3', () {
      // Constructing one requires exactly `zone` and `days` and nothing
      // else — there is no latitude/longitude/address parameter this test,
      // or any future caller, could even attempt to populate.
      const YearBookPlace p = YearBookPlace(zone: "Dad's — CST", days: 4);
      expect(p.zone, "Dad's — CST");
      expect(p.days, 4);
    });
  });
}
