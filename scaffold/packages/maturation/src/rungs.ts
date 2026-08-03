/**
 * MASTERFILE §21.3, §21.2 rungs 16–17, §21.7 — the four hardest rungs.
 *
 * Each of these transfers something a guardian currently holds. They are in one
 * file because they share a property: **once granted, the product loses the
 * ability to take it back**, and that has to be true in the code rather than in
 * the copy.
 */

export type Side = 'A' | 'B';

// ==================================== RUNG 15 — she publishes availability ==
/**
 * §21.3, the inversion.
 *
 * For ten years the Day Ribbon has been two adults coordinating **around** a
 * child: her day-parts inferred from school hours, bedtime, a wind-down window,
 * and both parents consulting the inference to decide when to reach her.
 *
 * At fifteen she publishes, and the ribbon shows what she set. The inference does
 * not disappear — it becomes the **fallback for hours she has not spoken about**,
 * which is the right relationship between a system's guess and a person's answer.
 */
export type Availability = 'free' | 'busy' | 'asleep' | 'ask_first';

export interface PublishedWindow {
  /** 0 = Sunday, per §8.7.1. */
  weekday: number;
  startMinute: number;
  endMinute: number;
  state: Availability;
}

export interface AvailabilityBoard {
  childId: string;
  windows: PublishedWindow[];
  publishedAt: string | null;
}

export const MINUTES_IN_DAY = 1440;

export type PublishError = 'not_yet_fifteen' | 'bad_window' | 'overlaps';

/**
 * Publishing requires the rung. Before fifteen this returns `not_yet_fifteen`
 * rather than silently accepting and ignoring — a surface that lets a
 * thirteen-year-old set something the ribbon disregards is worse than one that
 * does not offer it.
 */
export function publishWindow(
  board: AvailabilityBoard, w: PublishedWindow, hasRung: boolean, at: string,
): { ok: true; board: AvailabilityBoard } | { ok: false; reason: PublishError } {
  if (!hasRung) return { ok: false, reason: 'not_yet_fifteen' };
  if (w.weekday < 0 || w.weekday > 6) return { ok: false, reason: 'bad_window' };
  if (w.startMinute < 0 || w.endMinute > MINUTES_IN_DAY || w.startMinute >= w.endMinute) {
    return { ok: false, reason: 'bad_window' };
  }
  const clash = board.windows.some(x => x.weekday === w.weekday
    && w.startMinute < x.endMinute && x.startMinute < w.endMinute);
  if (clash) return { ok: false, reason: 'overlaps' };
  return { ok: true, board: { ...board, windows: [...board.windows, w],
    publishedAt: at } };
}

export function unpublishWindow(board: AvailabilityBoard, index: number): AvailabilityBoard {
  return { ...board, windows: board.windows.filter((_, i) => i !== index) };
}

/**
 * The resolution rule, and the whole point of the rung.
 *
 * **Her answer wins wherever she has given one.** The inferred day-part is
 * consulted only for hours she has left unspoken — and the result says *which*,
 * so a parent is never left wondering whether he is reading her or the machine.
 */
export function resolveAvailability(
  board: AvailabilityBoard, weekday: number, minute: number,
  inferred: Availability,
): { state: Availability; source: 'published' | 'inferred' } {
  const w = board.windows.find(x => x.weekday === weekday
    && minute >= x.startMinute && minute < x.endMinute);
  return w ? { state: w.state, source: 'published' }
           : { state: inferred, source: 'inferred' };
}

/**
 * What the guardian sees. A parent can now be told *"she is not free"* by her,
 * rather than by a system modelling her.
 *
 * The copy never editorialises. "She has said she is busy" is a fact; "she does
 * not want to talk" is an interpretation, and it is not the product's to make.
 */
export function availabilityGuardianLine(
  r: { state: Availability; source: 'published' | 'inferred' },
): string {
  if (r.source === 'inferred') {
    return r.state === 'asleep' ? 'She is probably asleep.'
      : r.state === 'busy' ? 'She is probably busy.'
      : r.state === 'ask_first' ? 'Might be a bad time.'
      : 'Probably a good time.';
  }
  return r.state === 'asleep' ? 'She has this down as sleeping.'
    : r.state === 'busy' ? 'She has said she is busy.'
    : r.state === 'ask_first' ? 'She has asked to be asked first.'
    : 'She has said she is free.';
}

export const AVAILABILITY_FORBIDDEN_COPY = [
  'does not want', 'doesn\'t want', 'refusing', 'avoiding', 'ignoring',
  'blocked you', 'not interested', 'chose not',
] as const;

export function auditAvailabilityCopy(s: string): { ok: true } | { ok: false; found: string[] } {
  const t = s.toLowerCase();
  const found = (AVAILABILITY_FORBIDDEN_COPY as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ======================================== RUNG 16 — archive curation =======
export type Era = string;

export interface ArchiveItem {
  id: string;
  artifactId: string;
  era: Era | null;
  hiddenByChild: boolean;
  /** Set by a guardian at capture; she may override it from sixteen. */
  captionByGuardian: string | null;
  captionByChild: string | null;
}

export type CurateError = 'guardian_cannot_curate' | 'no_such_item';

/**
 * From sixteen the archive is hers to arrange: hide, era-tag, retitle.
 *
 * **A guardian can do none of these, in either direction**, and specifically
 * cannot un-hide something she hid. That is the whole grant — a curation a
 * parent can reverse is a suggestion.
 */
export function curate(
  items: ArchiveItem[], id: string, actor: 'child' | 'guardian',
  change: { hidden?: boolean; era?: Era | null; caption?: string },
): { ok: true; items: ArchiveItem[] } | { ok: false; reason: CurateError } {
  if (actor === 'guardian') return { ok: false, reason: 'guardian_cannot_curate' };
  if (!items.some(i => i.id === id)) return { ok: false, reason: 'no_such_item' };
  return { ok: true, items: items.map(i => i.id !== id ? i : {
    ...i,
    hiddenByChild: change.hidden ?? i.hiddenByChild,
    era: change.era !== undefined ? change.era : i.era,
    captionByChild: change.caption ?? i.captionByChild,
  })};
}

/** Her caption wins where she has written one. */
export const displayCaption = (i: ArchiveItem) =>
  i.captionByChild ?? i.captionByGuardian ?? null;

/**
 * Hiding is not deleting, and the distinction is deliberate.
 *
 * A sixteen-year-old embarrassed by something at fourteen should be able to put
 * it away without destroying it — she may want it back at twenty-five. Deletion
 * exists too (§2.10), as a separate and more serious act.
 */
export function archiveView(
  items: ArchiveItem[], viewer: 'child' | 'guardian',
): ArchiveItem[] {
  return viewer === 'child' ? items : items.filter(i => !i.hiddenByChild);
}

// ============================================ RUNG 17 — her own export =====
export type Principal = { kind: 'guardian'; userId: string }
                      | { kind: 'child'; childId: string; age: number }
                      | { kind: 'coordinator'; userId: string };

export type ExportError = 'not_yet_seventeen' | 'not_authorised';

export interface ExportGrant {
  by: Principal;
  scope: 'full';
  /** A child's export needs nobody's permission. §21.2 rung 17. */
  requiresGuardianApproval: boolean;
  includesGuardianJournals: false;
  at: string;
}

/**
 * From seventeen she can take a copy of everything **without asking**.
 *
 * `requiresGuardianApproval` is a literal `false` for a child principal — there
 * is no branch that sets it true, because a grant a guardian can withhold is not
 * a grant.
 *
 * What her export never contains: a guardian's private journal. §17's tiers run
 * both ways, and her right to her own record is not a right to theirs.
 */
export function authorizeExport(
  p: Principal, at: string,
): { ok: true; grant: ExportGrant } | { ok: false; reason: ExportError } {
  if (p.kind === 'child') {
    if (p.age < 17) return { ok: false, reason: 'not_yet_seventeen' };
    return { ok: true, grant: { by: p, scope: 'full',
      requiresGuardianApproval: false, includesGuardianJournals: false, at } };
  }
  if (p.kind === 'guardian' || p.kind === 'coordinator') {
    return { ok: true, grant: { by: p, scope: 'full',
      requiresGuardianApproval: false, includesGuardianJournals: false, at } };
  }
  return { ok: false, reason: 'not_authorised' };
}

// ========================================= RUNG 18 — the deletion ==========
/**
 * §21.7 — **the hardest button anyone builds here.**
 *
 * An eighteen-year-old who says "delete all of it" must be able to, immediately
 * and completely. If that is not real, §2.10 is decoration.
 *
 * NO COOLING-OFF PERIOD. A delay is a soft refusal dressed as care, and every
 * product that has ever added one added it to reduce the number of people who go
 * through with it. Confirmation is legitimate; delay is not.
 */
export type DeletableScope =
  | 'media_artifact' | 'message' | 'journal' | 'show' | 'story_code' | 'colour_history'
  | 'collection' | 'gallery_work' | 'letter' | 'availability' | 'calendar_child_event';

/**
 * What is NOT hers to delete, and why. This list is the honest part.
 *
 * The parent-to-parent log, the expense ledger and the custody order are records
 * **between her parents** and about a legal relationship she was the subject of
 * but not a party to. P8 makes the log append-only regardless. She can have a
 * copy of everything; she cannot erase somebody else's record of their own
 * conduct.
 */
export const NOT_HERS_TO_DELETE = [
  { table: 'message_log',
    why: 'a record between her parents, append-only under P8' },
  { table: 'expense',
    why: 'a financial record between her parents' },
  { table: 'custody_order',
    why: 'a court document; not the product\'s to destroy' },
] as const;

export interface DeletionRequest {
  childId: string;
  requestedAt: string;
  age: number;
  scopes: DeletableScope[];
  excludes: readonly { table: string; why: string }[];
  /** Deliberately absent as a concept: there is no `executeAfter`. */
  immediate: true;
}

export type DeletionError = 'not_yet_eighteen' | 'nothing_selected';

export function requestDeletion(
  childId: string, age: number, scopes: DeletableScope[], at: string,
): { ok: true; request: DeletionRequest } | { ok: false; reason: DeletionError } {
  if (age < 18) return { ok: false, reason: 'not_yet_eighteen' };
  if (!scopes.length) return { ok: false, reason: 'nothing_selected' };
  return { ok: true, request: { childId, age, scopes, requestedAt: at,
    excludes: NOT_HERS_TO_DELETE, immediate: true } };
}

/**
 * The confirmation screen. It **lists what will go and what will not**, in plain
 * words, and then does it.
 *
 * It does not ask her to reconsider, offer a lesser option, mention how long she
 * has had the account, or show her a photograph. Those are retention tactics, and
 * using them on an eighteen-year-old asking for her childhood back would be
 * contemptible.
 */
export function deletionConfirmation(r: DeletionRequest): {
  willGo: string[]; willRemain: string[]; question: string; irreversible: true;
} {
  const labels: Record<DeletableScope, string> = {
    media_artifact: 'every photo, drawing and recording',
    message: 'every message you sent or received',
    journal: 'your journal',
    show: 'everything you ever showed them',
    story_code: 'your stories',
    colour_history: 'your colours',
    collection: 'your collections',
    gallery_work: 'your gallery',
    letter: 'your letters to yourself, sealed or not',
    availability: 'your availability',
    calendar_child_event: 'the events you added',
  };
  return {
    willGo: r.scopes.map(s => labels[s]),
    willRemain: r.excludes.map(e => `${e.table.replace(/_/g, ' ')} — ${e.why}`),
    question: 'Delete all of it?',
    irreversible: true,
  };
}

/** Copy that must never appear on a deletion path. */
export const DELETION_FORBIDDEN_COPY = [
  'are you sure', 'you will lose', 'think about it', 'sleep on it',
  'we will keep it for', 'you can come back', 'reconsider', 'instead you could',
  'we are sorry to see', 'before you go', 'just deactivate', 'take a break',
  'remember when', 'years of memories',
] as const;

export function auditDeletionCopy(s: string): { ok: true } | { ok: false; found: string[] } {
  const t = s.toLowerCase();
  const found = (DELETION_FORBIDDEN_COPY as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

/** There is no delay to configure. Asserted, because the absence is the point. */
export const COOLING_OFF_HOURS = 0;
