/**
 * The global sweep. (Not §20.5 — this module's own header cited that section
 * for years; a 2026-08-24 audit found §20.5 is actually "Recommended Phase 0
 * exit order," an unrelated section. No real MASTERFILE section documents
 * this design decision; corrected here rather than propagated further —
 * see CHANGELOG for the pass that fixed it, alongside wiring this module
 * into a real production caller for the first time.)
 *
 * Twenty-three separate forbidden-field lists had accumulated across the
 * codebase, one per module, each written when that module was built. Every one of
 * them is correct. Together they are a problem:
 *
 *  · A field banned in `palette` (`mood`) was never banned in `showcase`.
 *  · `streak` is banned in six modules and absent from nine others.
 *  · A new module gets whatever list its author happened to remember.
 *
 * A per-module guard catches what its author thought of. This unions all of them
 * and applies the whole set to every child-facing payload in the product, so a
 * field one author knew was dangerous protects surfaces they never saw.
 */

/**
 * The union. Assembled by hand ONCE, from every module's list, and then held by
 * a test that fails if a module list contains something missing here.
 */
export const GLOBAL_CHILD_FORBIDDEN = [
  // scoring and comparison
  'score', 'points', 'rank', 'ranking', 'rating', 'grade', 'stars', 'level',
  'best', 'record', 'highscore', 'high_score', 'leaderboard', 'percentile',
  // pressure over time
  'streak', 'combo', 'daysinarow', 'days_in_a_row', 'consecutive',
  // completion pressure
  'percent', 'percentcomplete', 'percent_complete', 'completion', 'progress',
  'total', 'remaining', 'missing', 'goal', 'target', 'quota', 'unfinished',
  // timing pressure
  'timeleft', 'time_left', 'countdown', 'elapsed', 'seconds', 'deadline',
  'wpm', 'reactionms', 'reaction_ms', 'accuracy', 'attempts', 'misses',
  // inference about her
  'mood', 'sentiment', 'feeling', 'emotion', 'trend', 'concern', 'flag',
  'volatility', 'stability', 'risk', 'engagement',
  // guilt
  'unread', 'unanswered', 'overdue', 'ignored', 'missed', 'lastseen',
  'last_seen', 'inactive', 'absent', 'daysago', 'days_ago',
  // adult machinery
  'expenses', 'courtexport', 'court_export', 'messagelog', 'message_log',
  'carenote', 'care_note', 'custody', 'litigation', 'invoice', 'balance',
  // her own private things
  'journal', 'diary', 'privatenote', 'private_note', 'therapistnote',
  'therapist_note',

  // ─── added by the first global sweep, v0.31.0 ────────────────────────────
  // Each of these was banned in exactly ONE module and nowhere else. The two
  // that matter most are the prohibition leaks: a location field was guarded
  // only inside `care`, and a price field only inside `agency`. A new module
  // written next month would have inherited neither.

  // P3 — location. Guarded in `care` alone until now.
  'latitude', 'longitude', 'lat', 'lng', 'coords', 'coordinates',
  'address', 'postcode', 'zip', 'geo', 'placeid', 'place_id',

  // P6 — no financial surface reaches a child. Guarded in `agency` alone.
  'price', 'amount', 'cost', 'fee', 'copay', 'balance', 'total_due',
  'order_ref', 'orderref', 'invoice_id', 'card', 'payment',

  // competitive framing. Guarded in `games` alone — and `elo` is exactly the
  // sort of field that gets added to a new game by someone in a hurry.
  'elo', 'wins', 'losses', 'winrate', 'win_rate', 'skill', 'mmr', 'seed',

  // educational pressure. Guarded in `maturation/family` alone.
  'mastery', 'assessment', 'quiz', 'test_result', 'passed', 'failed',
  'reading_level', 'gpa', 'marks',

  // counting things at her. Guarded in `agency` alone.
  'count', 'completed', 'ratio', 'claimedby', 'claimed_by', 'declinedby',
  'declined_by', 'daysaway', 'days_away',

  // adult plumbing that should never be rendered to her.
  'url', 'messages', 'archive', 'expense',

  // correctness language as a FIELD name — a payload carrying `wrong: true`
  // renders as a judgement however carefully the copy around it is written.
  'wrong', 'incorrect', 'correct', 'test', 'suggested', 'expected',
  'reminder', 'incomplete', 'reconsider',

  // ─── third pass ─────────────────────────────────────────────────────────
  // The remaining four lists, folded in. `timesRead` is the one worth naming:
  // it is legitimate and necessary on the PARENT side (the Book orders by it)
  // and poisonous on hers, which is exactly the kind of field that leaks when
  // somebody reuses a view model.
  'darker', 'lighter', 'alert',
  'pending', 'waiting', 'age',
  'quality', 'featured', 'improvement',
  'timesread', 'times_read', 'mostread', 'most_read',
] as const;

/**
 * Not every module list is a CHILD PAYLOAD list, and folding them together would
 * be wrong. Three other categories exist and are deliberately excluded from the
 * union:
 *
 *  · `a11y/LABEL_BANNED` — screen-reader label quality. "icon" and "button" are
 *    perfectly fine as data fields; they are only wrong inside a spoken label.
 *  · Tone lists (`CARE_NOTE_BANNED`, `BUSY_BANNED`, `STAGGER_FORBIDDEN`) — those
 *    are phrases in adult-facing copy, folded into GLOBAL_CHILD_PHRASES instead.
 *  · `school/NEVER_IN_SCHOOL_LAYER` — a storage boundary, not a rendering one.
 */
export const NOT_CHILD_PAYLOAD_LISTS = [
  'LABEL_BANNED', 'CARE_NOTE_BANNED', 'BUSY_BANNED', 'STAGGER_FORBIDDEN',
  'ONBOARDING_FORBIDDEN', 'SMS_FORBIDDEN', 'BANNED', 'BANNED_FRAMINGS',
  'BANNED_CONTENT', 'INTEREST_FORBIDDEN', 'OBSERVER_FORBIDDEN',
  'FORBIDDEN_DATA_KEYS', 'NEVER_IN_SCHOOL_LAYER', 'NEVER_TRANSLATED',
  'NOT_IN_TODDLER_SHELL', 'NOT_QUEUEABLE', 'OFFLINE_FORBIDDEN',
  // `palette/FORBIDDEN_PLACEMENTS` is a LAYOUT boundary — the positions her
  // colour may not occupy. Those names ('ribbon_band', 'error') describe UI
  // slots, not payload fields, and folding them in would ban the word "error"
  // from every object in the product.
  'FORBIDDEN_PLACEMENTS', 'FORBIDDEN', 'ALLOWED_PLACEMENTS',
  'CARE_NOTE_BANNED', 'CAPTION_BANNED',
] as const;

export type Leak = { path: string; field: string };

/**
 * Walks a payload and reports every forbidden field, with the path to it.
 *
 * Paths matter: `{a:{b:[{streak:3}]}}` reporting only "streak" tells a developer
 * a field is wrong; reporting `a.b[0].streak` tells them where.
 */
export function sweep(payload: unknown, root = ''): Leak[] {
  const leaks: Leak[] = [];
  const banned = new Set<string>(
    (GLOBAL_CHILD_FORBIDDEN as readonly string[]).map(s => s.toLowerCase()));

  const walk = (x: unknown, path: string) => {
    if (Array.isArray(x)) {
      x.forEach((v, i) => walk(v, `${path}[${i}]`));
      return;
    }
    if (x && typeof x === 'object') {
      for (const [k, v] of Object.entries(x)) {
        const here = path ? `${path}.${k}` : k;
        if (banned.has(k.toLowerCase())) leaks.push({ path: here, field: k });
        walk(v, here);
      }
    }
  };
  walk(payload, root);
  return leaks;
}

export function sweepOk(payload: unknown): boolean {
  return sweep(payload).length === 0;
}

/**
 * The reverse check, and the one that keeps this honest: every field a MODULE
 * bans must appear in the global list. Otherwise the union silently rots as
 * modules add guards the global sweep does not know about.
 */
export function missingFromGlobal(moduleList: readonly string[]): string[] {
  const global = new Set<string>(
    (GLOBAL_CHILD_FORBIDDEN as readonly string[]).map(s => s.toLowerCase()));
  return moduleList.filter(f => !global.has(f.toLowerCase()));
}

/**
 * Phrases, not fields. Several modules ban *wording* rather than keys — blame,
 * correction, accusation — and the same union argument applies.
 */
export const GLOBAL_CHILD_PHRASES = [
  'you lost', 'you failed', 'wrong answer', 'incorrect', 'try again',
  'well done', 'good job', 'you missed', 'your fault', 'too slow',
  'not allowed', 'denied', 'rejected', 'declined', 'no answer',
  'you never', 'you always', 'as usual', 'used to like',
  'out of her shell', 'gets her talking', 'break the ice',
  // folded in from the tone lists during the first global sweep
  'obviously', 'i told you', 'clearly you', 'if you had',
  'you need to start', 'this is why', 'unlike at',
] as const;

export function sweepPhrases(text: string): string[] {
  const t = text.toLowerCase();
  return (GLOBAL_CHILD_PHRASES as readonly string[]).filter(p => t.includes(p));
}

/**
 * A single entry point for any surface that renders to a child. The intent is
 * that no future module writes its own — it imports this.
 */
export interface ChildSurfaceReport {
  ok: boolean;
  fieldLeaks: Leak[];
  phraseLeaks: string[];
}

export function auditChildSurface(payload: unknown, text = ''): ChildSurfaceReport {
  const fieldLeaks = sweep(payload);
  const phraseLeaks = sweepPhrases(
    text || JSON.stringify(payload ?? '').replace(/"/g, ' '));
  return { ok: fieldLeaks.length === 0 && phraseLeaks.length === 0,
    fieldLeaks, phraseLeaks };
}

/** Standing rule 2 (§20.4): a guard must be shown to fail. */
export const KNOWN_BAD_PAYLOAD = { a: { b: [{ streak: 3 }] }, score: 10 };
export const KNOWN_GOOD_PAYLOAD = { title: 'A dragon', shown: true, colour: 'coral' };
