// OLIVE BRANCH — the archive data model and the Year Book compiler.
// No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs for real in tools/verify.sh's
// automated pipeline — CHANGELOG v0.49.61). MASTERFILE §2.10, §9.8, §9.8.2.
//
// A 1:1 semantic port of packages/archive/src/archive.ts's `Artifact`,
// `YearBookSection`, `YearBook`, and `compileYearBook()` — same field names,
// same filtering order, same "under twelve items isn't a book" threshold —
// kept close to the TS original for the same auditability reason
// lock_controller.dart gives for lock.ts. Shared by year_book.dart and
// gallery_screen.dart, both of which render slices of the same archive.
//
// Two intentional adaptations, neither of which changes what the function
// returns for a given logical input:
//   - `capturedAt` is a Dart `DateTime` here rather than an ISO string, and it
//     is treated as ALREADY being wall-clock time in `capturedTz` — the same
//     "no zone maths on the client" posture guardian_home.dart documents for
//     §8.2.3 (times arrive pre-rendered; this client never calls a timezone
//     database). The TS version re-derives that wall-clock reading itself via
//     `luxon`'s `setZone`, which needs an IANA tz database this client has no
//     reason to carry.
//   - `capturedTz` is therefore a short DISPLAY label ("EST"), not an IANA
//     zone id — again, matching what a real backend would already have
//     rendered before this ever reached a widget.
import 'package:flutter/foundation.dart' show immutable;

@immutable
class Artifact {
  const Artifact({
    required this.id,
    required this.childId,
    required this.kind,
    required this.storageKey,
    required this.capturedAt,
    required this.capturedTz,
    required this.preserved,
    this.eraTag,
    this.authorId,
  });

  final String id;
  final String childId;
  final String kind;
  final String storageKey;
  final DateTime capturedAt;
  final String capturedTz;
  final bool preserved;
  final String? eraTag;
  final String? authorId;
}

class YearBookSection {
  const YearBookSection({required this.title, required this.artifactIds});
  final String title;
  final List<String> artifactIds;
}

/// A season she spent in one household's timezone — "she moved, and the book
/// should say so" (archive.ts). No coordinates, no address: a zone label and a
/// day count, which is the retrospective, already-happened counterpart to the
/// live-location surveillance P3 forbids, not a version of it.
@immutable
class YearBookPlace {
  const YearBookPlace({required this.zone, required this.days});
  final String zone;
  final int days;

  @override
  bool operator ==(Object other) =>
      other is YearBookPlace && other.zone == zone && other.days == days;

  @override
  int get hashCode => Object.hash(zone, days);
}

class YearBook {
  const YearBook({
    required this.childId,
    required this.year,
    required this.sections,
    required this.artifactCount,
    required this.places,
    required this.printable,
  });

  final String childId;
  final int year;
  final List<YearBookSection> sections;
  final int artifactCount;
  final List<YearBookPlace> places;
  final bool printable;
}

/// §9.8.2 — compiled from PRESERVED artifacts only.
///
/// An unpreserved artifact is on a retention clock and may already be gone by
/// the time a book is printed; including it would produce a volume with
/// holes. Ported 1:1 from `compileYearBook()` in packages/archive/src/archive.ts.
YearBook compileYearBook(List<Artifact> all, String childId, int year) {
  final List<Artifact> mine = all
      .where((Artifact a) =>
          a.childId == childId && a.preserved && a.capturedAt.year == year)
      .toList();

  List<String> by(List<String> kinds) => mine
      .where((Artifact a) => kinds.contains(a.kind))
      .map((Artifact a) => a.id)
      .toList();

  final List<YearBookSection> sections = <YearBookSection>[
    YearBookSection(title: 'Things you said', artifactIds: by(<String>['video_msg', 'voice_note'])),
    YearBookSection(title: 'Things you made', artifactIds: by(<String>['drawing'])),
    YearBookSection(title: 'Things you learned', artifactIds: by(<String>['homework'])),
    YearBookSection(title: 'Moments', artifactIds: by(<String>['photo', 'call_clip'])),
  ].where((YearBookSection s) => s.artifactIds.isNotEmpty).toList();

  final Map<String, Set<String>> daysByZone = <String, Set<String>>{};
  for (final Artifact a in mine) {
    final String isoDate =
        '${a.capturedAt.year.toString().padLeft(4, '0')}-'
        '${a.capturedAt.month.toString().padLeft(2, '0')}-'
        '${a.capturedAt.day.toString().padLeft(2, '0')}';
    (daysByZone[a.capturedTz] ??= <String>{}).add(isoDate);
  }
  final List<YearBookPlace> places = daysByZone.entries
      .map((MapEntry<String, Set<String>> e) => YearBookPlace(zone: e.key, days: e.value.length))
      .toList()
    ..sort((YearBookPlace a, YearBookPlace b) => b.days.compareTo(a.days));

  return YearBook(
    childId: childId,
    year: year,
    sections: sections,
    artifactCount: mine.length,
    places: places,
    // A book of three items is not a book. Below this it is a slideshow, and
    // offering to print it would be a poor use of a family's money.
    printable: mine.length >= 12,
  );
}
