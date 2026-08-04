// OLIVE BRANCH — the library, and the book: pure logic. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline — manually built
// and run via `flutter analyze` / `flutter test` this session).
// MASTERFILE §9.11.6.
//
// A 1:1 semantic port of packages/storyteller/src/library.ts, kept close to
// the TS original for the same reason lock_controller.dart stays close to
// lock.ts: the two should be auditable side by side.
//
// Two gestures for her, and one for him. Because a story is a six-character
// code (storyteller_logic.dart), all three below cost almost nothing: a
// bookmark is a code plus an integer, and the book is a list of codes
// regenerated at print time.
//
//  ⌾ BOOKMARK — she stops halfway. Reopens at exactly the line they stopped on.
//  ★ FAVOURITE — she stars it. Joins a list that grows for years, newest first.
//  📖 THE BOOK — he collects the favourites and prints them.
//
// No Flutter import in this file, on purpose — same posture as
// storyteller_logic.dart and lock_controller.dart.
library library_logic;

import 'storyteller_logic.dart';

// =============================================================== bookmarks ==
class Bookmark {
  const Bookmark({required this.code, required this.lineIndex,
    required this.title, required this.savedAt});
  final String code;
  /// Index of the line they stopped on. Resumes HERE, not at the start.
  final int lineIndex;
  final String title;
  final String savedAt;
}

enum BookmarkError { alreadyFinished, noSuchLine }

class BookmarkResult {
  const BookmarkResult.ok(this.bookmark) : reason = null;
  const BookmarkResult.failed(this.reason) : bookmark = null;
  final Bookmark? bookmark;
  final BookmarkError? reason;
  bool get ok => bookmark != null;
}

/// A bookmark is meaningless at the last line, so saving one there is
/// refused rather than silently stored — nothing is more annoying than a
/// bookmark that reopens on the final page.
BookmarkResult bookmark(Story story, int lineIndex, String at) {
  if (lineIndex < 0 || lineIndex >= story.lines.length) {
    return const BookmarkResult.failed(BookmarkError.noSuchLine);
  }
  if (lineIndex == story.lines.length - 1) {
    return const BookmarkResult.failed(BookmarkError.alreadyFinished);
  }
  return BookmarkResult.ok(Bookmark(
      code: story.code, lineIndex: lineIndex, title: story.title, savedAt: at));
}

class ResumeResult {
  const ResumeResult({required this.story, required this.from, required this.recap});
  final Story story;
  final int from;
  /// Non-null only if she stopped after a refrain — she needs her line to
  /// join in with again, and starting her cold on a later line of a story
  /// whose chant she has forgotten is worse than one repeated sentence.
  final String? recap;
}

/// Reopen exactly where they stopped. The refrain is deliberately re-shown
/// even if it falls before the resume point.
ResumeResult resume(Bookmark b, [Personal personal = const Personal()]) {
  final story = generate(b.code, personal);
  final before = story.lines.sublist(0, b.lineIndex);
  StoryLine? lastRefrain;
  for (final l in before.reversed) {
    if (l.isRefrain) { lastRefrain = l; break; }
  }
  return ResumeResult(story: story, from: b.lineIndex, recap: lastRefrain?.text);
}

/// One bookmark per story. A second replaces the first rather than accumulating.
List<Bookmark> saveBookmark(List<Bookmark> list, Bookmark b) =>
    [...list.where((x) => x.code != b.code), b];

List<Bookmark> clearBookmark(List<Bookmark> list, String code) =>
    list.where((x) => x.code != code).toList();

// =============================================================== favourites =
class Favourite {
  const Favourite({required this.code, required this.title,
    required this.starredAt, required this.timesRead});
  final String code;
  final String title;
  final String starredAt;
  final int timesRead;

  Favourite copyWith({int? timesRead}) => Favourite(
      code: code, title: title, starredAt: starredAt,
      timesRead: timesRead ?? this.timesRead);
}

class StarResult {
  const StarResult.ok(this.list) : alreadyStarred = false;
  const StarResult.alreadyStarred() : list = null, alreadyStarred = true;
  final List<Favourite>? list;
  final bool alreadyStarred;
  bool get ok => list != null;
}

StarResult star(List<Favourite> list, Story story, String at, [int timesRead = 1]) {
  if (list.any((f) => f.code == story.code)) return const StarResult.alreadyStarred();
  return StarResult.ok([...list,
    Favourite(code: story.code, title: story.title, starredAt: at, timesRead: timesRead)]);
}

List<Favourite> unstar(List<Favourite> list, String code) =>
    list.where((f) => f.code != code).toList();

List<Favourite> recordRead(List<Favourite> list, String code) => [
      for (final f in list) f.code == code ? f.copyWith(timesRead: f.timesRead + 1) : f,
    ];

bool isStarred(List<Favourite> list, String code) => list.any((f) => f.code == code);

/// A title/code pair only — the shape her list is allowed to reach her in.
class ChildLibraryEntry {
  const ChildLibraryEntry({required this.title, required this.code});
  final String title;
  final String code;
}

/// Her list, newest first — the order a child expects, because the one she
/// starred tonight is the one she wants tomorrow.
///
/// No counts, no ranking, no "most read". P2. `timesRead` exists for the
/// book's ordering on the parent side and is structurally absent from this
/// return type, not merely hidden by the UI.
List<ChildLibraryEntry> libraryChildView(List<Favourite> list) {
  final sorted = [...list]..sort((a, b) => b.starredAt.compareTo(a.starredAt));
  return [for (final f in sorted) ChildLibraryEntry(title: f.title, code: f.code)];
}

// ================================================================ the book ==
class BookPage {
  const BookPage({required this.number, required this.title, required this.code,
    required this.lines, required this.refrain, required this.timesRead});
  final int number;
  final String title;
  final String code;
  final List<StoryLine> lines;
  /// So a reader knows which lines were hers.
  final String refrain;
  final int timesRead;
}

class BookMeta {
  const BookMeta({required this.storyCount, required this.wordCount,
    required this.estimatedPages, required this.generatedAt, required this.year});
  final int storyCount;
  final int wordCount;
  final int estimatedPages;
  final String generatedAt;
  final int year;
}

class Book {
  const Book({required this.childName, required this.dedication,
    required this.pages, required this.meta, required this.readerNote});
  final String childName;
  final String dedication;
  /// Ordered oldest first — see compileBook — so the volume reads as a year
  /// rather than a leaderboard.
  final List<BookPage> pages;
  /// Front matter a print shop needs.
  final BookMeta meta;
  /// How to read the highlighted lines, printed inside the cover.
  final String readerNote;
}

const int wordsPerPrintedPage = 110;

enum CompileBookError { tooFew }

class CompileBookResult {
  const CompileBookResult.ok(this.book) : reason = null;
  const CompileBookResult.failed(this.reason) : book = null;
  final Book? book;
  final CompileBookError? reason;
  bool get ok => book != null;
}

/// §9.11.6 — the book. Stories are ordered OLDEST FIRST, so the volume reads
/// as a year rather than a leaderboard. `timesRead` is printed as a small
/// note under each title — the detail that will matter to her in fifteen
/// years and costs nothing now. The whole book regenerates from a list of
/// six-character codes, so a hundred stories is six hundred bytes of stored
/// state and the printed artifact is reproducible forever.
CompileBookResult compileBook(List<Favourite> favourites, String childName, String at,
    [Personal personal = const Personal()]) {
  // Under five stories it is a pamphlet, and offering to print it would be a
  // poor use of a family's money. Same reasoning as the Year Book's twelve.
  if (favourites.length < 5) return const CompileBookResult.failed(CompileBookError.tooFew);

  final ordered = [...favourites]..sort((a, b) => a.starredAt.compareTo(b.starredAt));
  final pages = <BookPage>[];
  for (int i = 0; i < ordered.length; i++) {
    final f = ordered[i];
    final s = generate(f.code, personal);
    pages.add(BookPage(number: i + 1, title: s.title, code: f.code,
        lines: s.lines, refrain: s.refrain, timesRead: f.timesRead));
  }
  final words = pages.fold<int>(0, (n, p) =>
      n + p.lines.fold<int>(0, (m, l) => m + l.text.trim().split(RegExp(r'\s+')).length));

  final year = DateTime.tryParse(at)?.toUtc().year ?? DateTime.now().toUtc().year;
  return CompileBookResult.ok(Book(
    childName: childName,
    dedication: 'For $childName, who asked for these again.',
    pages: pages,
    meta: BookMeta(storyCount: pages.length, wordCount: words,
        estimatedPages: (words / wordsPerPrintedPage).ceil() + pages.length + 2,
        generatedAt: at, year: year),
    readerNote: 'The lines in bold are hers. Stop, look at her, and let her say '
        'them. She will know them all by heart.',
  ));
}

/// Plain text for a print shop, or for a parent who wants to paste it into
/// anything at all. Deliberately not a proprietary format — §2.11, a
/// family's material is never held hostage by a file type.
String bookAsText(Book b) {
  final out = <String>[];
  out.addAll(["${b.childName.toUpperCase()}'S STORIES", '']);
  out.addAll([b.dedication, '']);
  out.addAll([b.readerNote, '']);
  out.addAll(['—' * 46, '']);
  for (final p in b.pages) {
    out.add('${p.number}.  ${p.title}');
    out.add(p.timesRead > 1
        ? '     you asked for this one ${p.timesRead} times'
        : '     ');
    out.add('');
    for (final l in p.lines) {
      out.add(l.isRefrain ? '     >> ${l.text}' : '     ${l.text}');
    }
    out.addAll(['', '—' * 46, '']);
  }
  out.add('${b.meta.storyCount} stories · ${b.meta.wordCount} words · '
      'about ${b.meta.estimatedPages} printed pages');
  return out.join('\n');
}

/// §9.8.1 — a compiled book is preserved, and it is hers at majority (§9.8.4).
class BookArtifact {
  const BookArtifact({required this.title, required this.codes});
  final String title;
  final List<String> codes;
}

BookArtifact bookArtifact(Book b) => BookArtifact(
    title: "${b.childName}'s Stories", codes: [for (final p in b.pages) p.code]);

/// Fields that must never reach her — kept as a runtime-checkable list (in
/// addition to ChildLibraryEntry's own narrow shape) so a test can assert the
/// same invariant the TS suite asserts, against loosely-typed data.
const List<String> libraryForbidden = [
  'timesRead', 'times_read', 'mostRead', 'rank', 'score', 'streak',
  'percent', 'progress', 'completion',
];

class LibraryAuditResult {
  const LibraryAuditResult.ok() : ok = true, leaks = const [];
  const LibraryAuditResult.failed(this.leaks) : ok = false;
  final bool ok;
  final List<String> leaks;
}

/// Walks an arbitrary Map/List structure looking for a forbidden key,
/// case-insensitively — the same shape-agnostic audit library.ts runs, for
/// use against `Map`-shaped test fixtures rather than the strongly-typed
/// [ChildLibraryEntry] this file actually returns to a child screen.
LibraryAuditResult auditLibraryChildView(Object? v) {
  final leaks = <String>{};
  void walk(Object? x) {
    if (x is List) {
      for (final e in x) {
        walk(e);
      }
      return;
    }
    if (x is Map) {
      x.forEach((key, val) {
        final k = key.toString();
        if (libraryForbidden.any((f) => f.toLowerCase() == k.toLowerCase())) leaks.add(k);
        walk(val);
      });
    }
  }
  walk(v);
  return leaks.isEmpty ? const LibraryAuditResult.ok() : LibraryAuditResult.failed(leaks.toList());
}
