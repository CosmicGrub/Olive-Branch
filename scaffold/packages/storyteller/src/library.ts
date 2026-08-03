import { generate, forReadingAloud, type Story } from './storyteller.ts';

/**
 * MASTERFILE §9.11.6 — the library.
 *
 * Two gestures for her, and one for him.
 *
 *  ⌾ BOOKMARK — she stops halfway. Tapping the bookmark later reopens that
 *    story at exactly the line they stopped on, so a bedtime that ran out of
 *    time is resumed rather than restarted.
 *
 *  ★ FAVOURITE — she stars it. It joins a list that grows for years.
 *
 *  📖 THE BOOK — he collects the favourites and prints them. A bound volume of
 *    the stories they read together, for Christmas.
 *
 * Because a story is a six-character code (§9.11.2), all three of these cost
 * almost nothing: a bookmark is a code plus an integer, and the book is a list of
 * codes regenerated at print time.
 */

// =============================================================== bookmarks ==
export interface Bookmark {
  code: string;
  /** Index of the line they stopped on. Resumes HERE, not at the start. */
  lineIndex: number;
  title: string;
  savedAt: string;
}

export type BookmarkError = 'already_finished' | 'no_such_line';

/**
 * A bookmark is meaningless at the last line, so saving one there is refused
 * rather than silently stored. Nothing is more annoying than a bookmark that
 * reopens on the final page.
 */
export function bookmark(
  story: Story, lineIndex: number, at: string,
): { ok: true; bookmark: Bookmark } | { ok: false; reason: BookmarkError } {
  if (lineIndex < 0 || lineIndex >= story.lines.length) {
    return { ok: false, reason: 'no_such_line' };
  }
  if (lineIndex === story.lines.length - 1) return { ok: false, reason: 'already_finished' };
  return { ok: true, bookmark: { code: story.code, lineIndex,
    title: story.title, savedAt: at } };
}

/**
 * Reopen exactly where they stopped.
 *
 * The refrain is deliberately re-shown even if it falls before the resume point:
 * she needs her line to join in with, and starting her cold on line seven of a
 * story whose chant she has forgotten is worse than one repeated sentence.
 */
export function resume(b: Bookmark, personal?: Parameters<typeof generate>[1]): {
  story: Story; from: number; recap: string | null;
} {
  const story = generate(b.code, personal);
  const before = story.lines.slice(0, b.lineIndex);
  const lastRefrain = [...before].reverse().find(l => l.isRefrain);
  return { story, from: b.lineIndex,
    recap: lastRefrain ? lastRefrain.text : null };
}

/** One bookmark per story. A second replaces the first rather than accumulating. */
export function saveBookmark(list: Bookmark[], b: Bookmark): Bookmark[] {
  return [...list.filter(x => x.code !== b.code), b];
}

export function clearBookmark(list: Bookmark[], code: string): Bookmark[] {
  return list.filter(x => x.code !== code);
}

// =============================================================== favourites =
export interface Favourite {
  code: string;
  title: string;
  starredAt: string;
  timesRead: number;
}

export function star(
  list: Favourite[], story: Story, at: string, timesRead = 1,
): { ok: true; list: Favourite[] } | { ok: false; reason: 'already_starred' } {
  if (list.some(f => f.code === story.code)) return { ok: false, reason: 'already_starred' };
  return { ok: true, list: [...list, { code: story.code, title: story.title,
    starredAt: at, timesRead }] };
}

export function unstar(list: Favourite[], code: string): Favourite[] {
  return list.filter(f => f.code !== code);
}

export function recordRead(list: Favourite[], code: string): Favourite[] {
  return list.map(f => f.code === code ? { ...f, timesRead: f.timesRead + 1 } : f);
}

export const isStarred = (list: Favourite[], code: string) =>
  list.some(f => f.code === code);

/**
 * Her list, newest first — the order a child expects, because the one she starred
 * tonight is the one she wants tomorrow.
 *
 * No counts, no ranking, no "most read". P2. The `timesRead` figure exists for
 * the book's ordering on the parent side and is not returned here.
 */
export function libraryChildView(list: Favourite[]): { title: string; code: string }[] {
  return [...list].sort((a, b) => b.starredAt.localeCompare(a.starredAt))
    .map(f => ({ title: f.title, code: f.code }));
}

// ================================================================ the book ==
export interface BookPage {
  number: number;
  title: string;
  code: string;
  lines: { text: string; isRefrain: boolean }[];
  /** So a reader knows which lines were hers. */
  refrain: string;
  timesRead: number;
}

export interface Book {
  childName: string;
  dedication: string;
  /** Ordered. See below — this is not the order she starred them in. */
  pages: BookPage[];
  /** Front matter a print shop needs. */
  meta: { storyCount: number; wordCount: number; estimatedPages: number;
          generatedAt: string; year: number };
  /** How to read the highlighted lines, printed inside the cover. */
  readerNote: string;
}

export const WORDS_PER_PRINTED_PAGE = 110;

/**
 * §9.11.6 — the book.
 *
 * Stories are ordered **oldest first**, so the volume reads as a year rather than
 * a leaderboard. The `timesRead` figure is printed as a small note under each
 * title — *"you asked for this one nine times"* — which is the detail that will
 * matter to her in fifteen years and costs nothing now.
 *
 * The whole book regenerates from a list of six-character codes, so a hundred
 * stories is six hundred bytes of stored state and the printed artifact is
 * reproducible forever.
 */
export function compileBook(
  favourites: Favourite[], childName: string, at: string,
  personal?: Parameters<typeof generate>[1],
): { ok: true; book: Book } | { ok: false; reason: 'too_few' } {
  // Under five stories it is a pamphlet, and offering to print it would be a
  // poor use of a family's money. Same reasoning as the Year Book's twelve.
  if (favourites.length < 5) return { ok: false, reason: 'too_few' };

  const ordered = [...favourites].sort((a, b) => a.starredAt.localeCompare(b.starredAt));
  const pages: BookPage[] = ordered.map((f, i) => {
    const s = generate(f.code, personal);
    return { number: i + 1, title: s.title, code: f.code,
      lines: s.lines.map(l => ({ text: l.text, isRefrain: l.isRefrain })),
      refrain: s.refrain, timesRead: f.timesRead };
  });
  const words = pages.reduce((n, p) =>
    n + p.lines.reduce((m, l) => m + l.text.split(/\s+/).length, 0), 0);

  return { ok: true, book: {
    childName,
    dedication: `For ${childName}, who asked for these again.`,
    pages,
    meta: { storyCount: pages.length, wordCount: words,
      estimatedPages: Math.ceil(words / WORDS_PER_PRINTED_PAGE) + pages.length + 2,
      generatedAt: at, year: new Date(at).getUTCFullYear() },
    readerNote: 'The lines in bold are hers. Stop, look at her, and let her say '
      + 'them. She will know them all by heart.',
  }};
}

/**
 * Plain text for a print shop, or for a parent who wants to paste it into
 * anything at all. Deliberately not a proprietary format — §2.11, the family's
 * material is never held hostage by a file type.
 */
export function bookAsText(b: Book): string {
  const out: string[] = [];
  out.push(`${b.childName.toUpperCase()}'S STORIES`, '');
  out.push(b.dedication, '');
  out.push(b.readerNote, '');
  out.push('—'.repeat(46), '');
  for (const p of b.pages) {
    out.push(`${p.number}.  ${p.title}`);
    out.push(p.timesRead > 1
      ? `     you asked for this one ${p.timesRead} times`
      : '     ');
    out.push('');
    for (const l of p.lines) {
      out.push(l.isRefrain ? `     >> ${l.text}` : `     ${l.text}`);
    }
    out.push('', '—'.repeat(46), '');
  }
  out.push(`${b.meta.storyCount} stories · ${b.meta.wordCount} words · `
    + `about ${b.meta.estimatedPages} printed pages`);
  return out.join('\n');
}

/** §9.8.1 — a compiled book is preserved, and it is hers at majority (§9.8.4). */
export function bookArtifact(b: Book): {
  title: string; codes: string[]; preserved: true;
} {
  return { title: `${b.childName}'s Stories`,
    codes: b.pages.map(p => p.code), preserved: true };
}

/** Fields that must never reach her. */
export const LIBRARY_FORBIDDEN = [
  'timesRead', 'times_read', 'mostRead', 'rank', 'score', 'streak',
  'percent', 'progress', 'completion',
] as const;

export function auditLibraryChildView(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((LIBRARY_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
