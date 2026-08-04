// OLIVE BRANCH — the library / the book pure-logic tests. MASTERFILE §9.11.6.
//
// Same posture as storyteller_logic_test.dart. The load-bearing property
// here is P2: `libraryChildView()` must return a shape that CANNOT carry
// `timesRead`/rank/score — checked both structurally (the return type has no
// such field) and via `auditLibraryChildView()` against loosely-typed data,
// mirroring library.ts's own shape-agnostic runtime audit.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/library_logic.dart';
import 'package:olive_client/storyteller_logic.dart' as story;

void main() {
  final s = story.generate(1);

  group('bookmark — a bedtime that ran out of time, §9.11.6', () {
    test('refuses a bookmark on the last line', () {
      final r = bookmark(s, s.lines.length - 1, 'now');
      expect(r.ok, isFalse);
      expect(r.reason, BookmarkError.alreadyFinished);
    });

    test('refuses an out-of-range line', () {
      expect(bookmark(s, -1, 'now').ok, isFalse);
      expect(bookmark(s, s.lines.length, 'now').ok, isFalse);
    });

    test('succeeds mid-story', () {
      final r = bookmark(s, 2, 'now');
      expect(r.ok, isTrue);
      expect(r.bookmark!.code, s.code);
      expect(r.bookmark!.lineIndex, 2);
    });

    test('resume recaps the last refrain seen before the stop point', () {
      // Index 4 IS the first refrain (see storyteller_logic.dart's
      // `generate`: chant() is the 5th line, index 4) — `resume` looks at
      // lines strictly BEFORE the stop point, so stopping at index 5 is what
      // puts that refrain in the recap window.
      expect(s.lines[4].isRefrain, isTrue);
      final b = bookmark(s, 5, 'now').bookmark!;
      final r = resume(b);
      expect(r.from, 5);
      expect(r.recap, s.refrain);
    });

    test('resume before any refrain has no recap', () {
      final b = bookmark(s, 1, 'now').bookmark!;
      final r = resume(b);
      expect(r.recap, isNull);
    });

    test('saveBookmark replaces rather than accumulates for the same code', () {
      final first = bookmark(s, 1, 't1').bookmark!;
      final second = bookmark(s, 3, 't2').bookmark!;
      final list = saveBookmark(saveBookmark(<Bookmark>[], first), second);
      expect(list.length, 1);
      expect(list.single.lineIndex, 3);
    });

    test('clearBookmark removes only the matching code', () {
      final other = story.generate(2);
      final list = [bookmark(s, 1, 't').bookmark!, bookmark(other, 1, 't').bookmark!];
      final cleared = clearBookmark(list, s.code);
      expect(cleared.length, 1);
      expect(cleared.single.code, other.code);
    });
  });

  group('favourites — the star, §9.11.6', () {
    test('starring adds an entry with timesRead defaulted to 1', () {
      final r = star(<Favourite>[], s, 'now');
      expect(r.ok, isTrue);
      expect(r.list!.single.timesRead, 1);
    });

    test('starring the same code twice is refused', () {
      final once = star(<Favourite>[], s, 'now').list!;
      final twice = star(once, s, 'later');
      expect(twice.ok, isFalse);
      expect(twice.alreadyStarred, isTrue);
    });

    test('unstar removes only the matching code', () {
      final other = story.generate(3);
      var list = star(<Favourite>[], s, 'now').list!;
      list = star(list, other, 'now').list!;
      final after = unstar(list, s.code);
      expect(after.length, 1);
      expect(after.single.code, other.code);
    });

    test('recordRead increments only the matching entry', () {
      var list = star(<Favourite>[], s, 'now').list!;
      list = recordRead(list, s.code);
      list = recordRead(list, s.code);
      expect(list.single.timesRead, 3); // starred at 1, then +1 twice
    });

    test('isStarred reflects membership', () {
      final list = star(<Favourite>[], s, 'now').list!;
      expect(isStarred(list, s.code), isTrue);
      expect(isStarred(list, 'NOTACD'), isFalse);
    });
  });

  group('libraryChildView — P2, no counts ever reach her', () {
    test('is ordered newest-starred-first', () {
      const a = Favourite(code: 'AAAAAA', title: 'A', starredAt: '2020-01-01', timesRead: 9);
      const b = Favourite(code: 'BBBBBB', title: 'B', starredAt: '2022-06-01', timesRead: 1);
      final view = libraryChildView([a, b]);
      expect(view.map((e) => e.code).toList(), ['BBBBBB', 'AAAAAA']);
    });

    test('the returned shape structurally has no timesRead field to leak', () {
      const f = Favourite(code: 'AAAAAA', title: 'A', starredAt: '2020-01-01', timesRead: 42);
      final entry = libraryChildView([f]).single;
      // ChildLibraryEntry only exposes title/code — there is no `.timesRead`
      // accessor to even attempt calling here, which is the point.
      expect(entry.title, 'A');
      expect(entry.code, 'AAAAAA');
    });

    test('auditLibraryChildView passes a clean title/code map', () {
      final result = auditLibraryChildView([
        {'title': 'A Very Silly Day', 'code': 'AAAAAA'},
      ]);
      expect(result.ok, isTrue);
    });

    test('auditLibraryChildView catches a forbidden key leaking in, case-insensitively', () {
      final result = auditLibraryChildView([
        {'title': 'A Very Silly Day', 'code': 'AAAAAA', 'TimesRead': 9},
      ]);
      expect(result.ok, isFalse);
      expect(result.leaks, contains('TimesRead'));
    });

    test('auditLibraryChildView walks nested structures', () {
      final result = auditLibraryChildView({
        'shelf': [
          {'title': 'A', 'code': 'AAAAAA'},
          {'nested': {'streak': 3}},
        ],
      });
      expect(result.ok, isFalse);
      expect(result.leaks, contains('streak'));
    });
  });

  group('the book — oldest first, §9.11.6', () {
    List<Favourite> fourOnly() => [
      for (int i = 0; i < 4; i++)
        Favourite(code: story.generate(i).code, title: story.generate(i).title,
          starredAt: '2024-01-0${i + 1}', timesRead: 1),
    ];

    List<Favourite> fiveWithRepeats() => [
      Favourite(code: story.generate(10).code, title: story.generate(10).title,
        starredAt: '2024-03-01', timesRead: 9),
      Favourite(code: story.generate(11).code, title: story.generate(11).title,
        starredAt: '2024-01-01', timesRead: 1),
      Favourite(code: story.generate(12).code, title: story.generate(12).title,
        starredAt: '2024-02-01', timesRead: 2),
      Favourite(code: story.generate(13).code, title: story.generate(13).title,
        starredAt: '2024-05-01', timesRead: 1),
      Favourite(code: story.generate(14).code, title: story.generate(14).title,
        starredAt: '2024-04-01', timesRead: 1),
    ];

    test('under five stories, compileBook refuses — "it is a pamphlet"', () {
      final r = compileBook(fourOnly(), 'Ivy', '2024-06-01T00:00:00Z');
      expect(r.ok, isFalse);
      expect(r.reason, CompileBookError.tooFew);
    });

    test('five or more compiles, ordered oldest-starred-first (not a leaderboard)', () {
      final favourites = fiveWithRepeats();
      final r = compileBook(favourites, 'Ivy', '2024-06-01T00:00:00Z');
      expect(r.ok, isTrue);
      final pages = r.book!.pages;
      expect(pages.length, 5);
      // The 2024-01-01 entry (timesRead: 1) was starred earliest, so it must
      // be page 1; the 2024-05-01 entry (timesRead: 1) was starred latest,
      // so it must be the last page — oldest first, not most-read first.
      final earliest = favourites.firstWhere((f) => f.starredAt == '2024-01-01');
      final latest = favourites.firstWhere((f) => f.starredAt == '2024-05-01');
      expect(pages.first.code, earliest.code);
      expect(pages.last.code, latest.code);
      expect(pages.map((p) => p.number).toList(), [1, 2, 3, 4, 5]);
      expect(r.book!.dedication, contains('Ivy'));
      expect(r.book!.meta.storyCount, 5);
      expect(r.book!.meta.wordCount, greaterThan(0));
      expect(r.book!.meta.estimatedPages, greaterThanOrEqualTo(pages.length + 2));
    });

    test('bookAsText prints "asked for this one N times" only when N > 1', () {
      final book = compileBook(fiveWithRepeats(), 'Ivy', '2024-06-01T00:00:00Z').book!;
      final text = bookAsText(book);
      expect(text, contains('asked for this one 9 times'));
      expect(text, contains("IVY'S STORIES"));
      expect(text, isNot(contains('asked for this one 1 times')));
    });

    test('bookArtifact carries exactly the pages\' codes, in book order', () {
      final book = compileBook(fiveWithRepeats(), 'Ivy', '2024-06-01T00:00:00Z').book!;
      final artifact = bookArtifact(book);
      expect(artifact.codes, book.pages.map((p) => p.code).toList());
      expect(artifact.title, contains('Ivy'));
    });
  });
}
