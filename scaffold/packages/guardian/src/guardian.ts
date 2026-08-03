/**
 * MASTERFILE §12.4–§12.7 — the guardian shell's missing surfaces.
 *
 * The child side has had most of the attention. Four things were missing on the
 * adult side, and one of them — the pre-call briefing — is probably the
 * highest-value screen in the product, because it decides whether the call that
 * follows is any good.
 */

export type Side = 'A' | 'B';

// ============================================ §12.4 the pre-call briefing ===
/**
 * He is about to ring her. Everything he needs is currently spread across five
 * screens, so in practice he opens none of them and opens with "how was school",
 * and she says "fine", and the call dies in ninety seconds (§9.10.1).
 *
 * THE DESIGN CONSTRAINT: this must not become a script. A parent reading questions
 * off a card is worse than a parent with nothing prepared — children hear it
 * immediately. So it is capped at **three facts and one opener**, and the opener is
 * phrased as something to notice rather than something to say.
 */
export interface BriefingFact {
  kind: 'interest' | 'showed_you' | 'tomorrow' | 'homework' | 'colour' | 'sleeps';
  text: string;
}

export interface Briefing {
  childName: string;
  facts: BriefingFact[];
  /** One. Not a list of conversation starters. */
  opener: string;
  /** What he should NOT do, said once. */
  caution: string;
}

export const MAX_BRIEFING_FACTS = 3;

export interface BriefingInput {
  childName: string;
  activeInterests: string[];
  lastShow: { kind: string; caption: string | null; daysAgo: number } | null;
  tomorrow: { label: string } | null;
  stuckHomework: { subject: string } | null;
  colourLabel: string | null;
  sleepsUntilNext: number | null;
}

/**
 * Facts are chosen by RECENCY AND SPECIFICITY, not by category. "She showed you a
 * Diplodocus on Tuesday" beats "she likes dinosaurs" every time, because it is
 * something only he could know.
 */
export function briefing(i: BriefingInput): Briefing {
  const candidates: BriefingFact[] = [];
  if (i.lastShow) {
    candidates.push({ kind: 'showed_you',
      text: i.lastShow.caption
        ? `She showed you ${i.lastShow.caption} ${when(i.lastShow.daysAgo)}.`
        : `She showed you something ${when(i.lastShow.daysAgo)}.` });
  }
  if (i.stuckHomework) {
    candidates.push({ kind: 'homework',
      text: `She got stuck on ${i.stuckHomework.subject} and has not asked about it.` });
  }
  if (i.tomorrow) {
    candidates.push({ kind: 'tomorrow', text: `Tomorrow: ${i.tomorrow.label}.` });
  }
  if (i.activeInterests.length) {
    candidates.push({ kind: 'interest',
      text: `Still ${i.activeInterests[0]}${i.activeInterests[1] ? ` and ${i.activeInterests[1]}` : ''}.` });
  }
  if (i.colourLabel) {
    candidates.push({ kind: 'colour', text: `Her colour today is ${i.colourLabel}.` });
  }
  if (i.sleepsUntilNext !== null) {
    candidates.push({ kind: 'sleeps',
      text: `${i.sleepsUntilNext} sleeps until she is with you.` });
  }

  const facts = candidates.slice(0, MAX_BRIEFING_FACTS);
  return { childName: i.childName, facts,
    opener: opener(facts),
    caution: 'Do not work through this like a list. Pick one and be surprised by '
           + 'the answer.' };
}

const when = (d: number) =>
  d === 0 ? 'today' : d === 1 ? 'yesterday' : `${d} days ago`;

function opener(facts: BriefingFact[]): string {
  const show = facts.find(f => f.kind === 'showed_you');
  if (show) return 'Ask about the thing she showed you before anything else.';
  const hw = facts.find(f => f.kind === 'homework');
  if (hw) return 'Do not lead with the homework. Wait for her to raise it.';
  const t = facts.find(f => f.kind === 'tomorrow');
  if (t) return 'Ask what she is expecting to happen tomorrow.';
  return 'Ask her to show you something. It works better than a question.';
}

/**
 * P7 — a briefing may NEVER contain anything from her journal, at any age, for
 * any reason. This function exists so that is asserted rather than assumed.
 */
export const BRIEFING_FORBIDDEN_SOURCES = [
  'journal', 'private_note', 'diary', 'therapist_note', 'mood', 'sentiment',
] as const;

export function auditBriefing(b: Briefing): { ok: true } | { ok: false; leaks: string[] } {
  const text = (b.facts.map(f => f.text).join(' ') + ' ' + b.opener).toLowerCase();
  const leaks = (BRIEFING_FORBIDDEN_SOURCES as readonly string[])
    .filter(w => text.includes(w));
  return leaks.length ? { ok: false, leaks } : { ok: true };
}

// ================================================ §12.5 the handoff note ====
/**
 * *"She has a cough, she did not sleep well, she is upset about a friend."*
 *
 * The single most requested feature in this category in the real world, and it was
 * not here. The bag manifest handles objects; nothing handled the child.
 *
 * TWO DECISIONS THAT MATTER MORE THAN THE FEATURE:
 *
 * 1. **A care note is NOT evidence.** It is deliberately outside the §13
 *    tamper-evident log and expires in seven days. If every "she has a cough"
 *    became a court exhibit, parents would stop writing them honestly — and an
 *    honest one is worth more than a preserved one.
 *
 * 2. **The child never sees it.** "Mum said you were in a bad mood" is poison, and
 *    a child who knows her parents file notes about her stops telling either of
 *    them anything.
 */
export type CareKind = 'sleep' | 'appetite' | 'mood' | 'health' | 'school' | 'social' | 'other';

export interface CareItem { kind: CareKind; note: string }

export interface CareNote {
  id: string;
  childId: string;
  fromUserId: string;
  at: string;
  items: CareItem[];
  /** Operational, not evidentiary. */
  expiresAt: string;
  inCourtLog: false;
  visibleToChild: false;
}

export const CARE_NOTE_TTL_DAYS = 7;

/**
 * The tone guard. A care note is the obvious place for a dig, and a dig disguised
 * as care is the hardest kind to call out — which is exactly why the product
 * should refuse it rather than leave it to the other parent to absorb.
 */
export const CARE_NOTE_BANNED = [
  'you never', 'you always', 'your fault', 'as usual', 'once again',
  'i told you', 'obviously', 'clearly you', 'if you had', 'you failed',
  'she says you', 'she told me you', 'unlike at', 'at your house she',
  'you need to start', 'this is why',
] as const;

export function writeCareNote(
  id: string, childId: string, fromUserId: string, items: CareItem[], at: string,
): { ok: true; note: CareNote } | { ok: false; reason: 'empty' | 'accusatory'; found?: string[] } {
  const clean = items.filter(i => i.note.trim());
  if (!clean.length) return { ok: false, reason: 'empty' };
  const text = clean.map(i => i.note).join(' ').toLowerCase();
  const found = (CARE_NOTE_BANNED as readonly string[]).filter(w => text.includes(w));
  if (found.length) return { ok: false, reason: 'accusatory', found };
  return { ok: true, note: {
    id, childId, fromUserId, at, items: clean,
    expiresAt: new Date(Date.parse(at) + CARE_NOTE_TTL_DAYS * 86_400_000).toISOString(),
    inCourtLog: false, visibleToChild: false,
  }};
}

export function careNoteVisibleTo(role: string): boolean {
  return role === 'guardian' || role === 'caregiver';
}

// ================================================ §12.6 the catch-up ========
/**
 * A parent who has not opened the app in five days currently gets a home screen.
 *
 * THE RULE: a catch-up must never be a guilt trip. No "you missed 14 things", no
 * unread badge in the hundreds, no oldest-first ordering that makes him scroll
 * through his own absence. Grouped, capped, newest first, and silent about the
 * gap itself.
 */
export interface CatchUpGroup { kind: string; count: number; line: string }

export interface CatchUp {
  since: string;
  groups: CatchUpGroup[];
  /** One thing to do, if there is one. Never a list. */
  firstThing: string | null;
}

export const MAX_CATCHUP_GROUPS = 4;

export function catchUp(
  since: string,
  events: { kind: string; at: string }[],
): CatchUp {
  const after = events.filter(e => e.at > since);
  const counts = new Map<string, number>();
  for (const e of after) counts.set(e.kind, (counts.get(e.kind) ?? 0) + 1);

  const label: Record<string, (n: number) => string> = {
    show:      n => n === 1 ? 'She showed you something' : `She showed you ${n} things`,
    drawing:   n => n === 1 ? 'A new drawing' : `${n} new drawings`,
    story:     n => n === 1 ? 'She kept a story' : `She kept ${n} stories`,
    message:   n => n === 1 ? 'A message from her' : `${n} messages from her`,
    calendar:  n => n === 1 ? 'One calendar change' : `${n} calendar changes`,
    care_note: n => n === 1 ? 'A note from her other house' : `${n} notes from her other house`,
    expense:   n => n === 1 ? 'One expense to look at' : `${n} expenses to look at`,
  };

  const groups = [...counts.entries()]
    .map(([kind, count]) => ({ kind, count,
      line: (label[kind] ?? ((n: number) => `${n} × ${kind}`))(count) }))
    .sort((a, b) => b.count - a.count)
    .slice(0, MAX_CATCHUP_GROUPS);

  const priority = ['show', 'message', 'care_note', 'expense'];
  const first = priority.map(k => groups.find(g => g.kind === k)).find(Boolean);
  return { since, groups,
    firstThing: first ? first.line : null };
}

/** Never in a catch-up. */
export const CATCHUP_FORBIDDEN = [
  'missed', 'unread', 'ignored', 'overdue', 'daysAway', 'absent',
  'lastSeen', 'streak', 'inactive',
] as const;

export function auditCatchUp(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((CATCHUP_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ============================================ §12.7 the coordination inbox ==
/**
 * One place for things that need his answer.
 *
 * THE RULE THAT KEEPS IT USABLE: **only actionable items.** An inbox that also
 * carries informational items is a feed, and a feed is something you scroll past.
 * If it cannot be answered, it does not belong here — it belongs in the catch-up.
 */
export type InboxKind =
  | 'expense_approval' | 'schedule_change' | 'invitation' | 'document_request'
  | 'medication_change' | 'coordinator_question';

export interface InboxItem {
  id: string;
  kind: InboxKind;
  /** Plain, and never accusatory — it goes through the same tone guard. */
  summary: string;
  fromUserId: string;
  at: string;
  /** The two or three things he can actually do. */
  actions: string[];
  /** Set when it stops needing him. */
  resolvedAt: string | null;
  /** Present only where a real deadline exists in the world. */
  respondBy: string | null;
}

export const INBOX_ACTIONS: Record<InboxKind, string[]> = {
  expense_approval:     ['Agree', 'Query it', 'Decline'],
  schedule_change:      ['Accept', 'Propose another time', 'Decline'],
  invitation:           ['Accept', 'Not now'],
  document_request:     ['Send it', 'I do not have it'],
  medication_change:    ['Acknowledge', 'Query it'],
  coordinator_question: ['Answer'],
};

export function inbox(items: InboxItem[]): InboxItem[] {
  return items.filter(i => !i.resolvedAt)
    // A real deadline first, then oldest — because the oldest is the one that has
    // been making the other parent wait.
    .sort((a, b) => {
      if (a.respondBy && b.respondBy) return a.respondBy.localeCompare(b.respondBy);
      if (a.respondBy) return -1;
      if (b.respondBy) return 1;
      return a.at.localeCompare(b.at);
    });
}

export function isActionable(kind: string): boolean {
  return kind in INBOX_ACTIONS;
}

/**
 * Informational things are refused entry. This is the check that stops the inbox
 * becoming a feed six months from now.
 */
export function admitToInbox(item: { kind: string }):
  { ok: true } | { ok: false; reason: 'not_actionable' } {
  return isActionable(item.kind) ? { ok: true } : { ok: false, reason: 'not_actionable' };
}

export function resolve(items: InboxItem[], id: string, at: string): InboxItem[] {
  return items.map(i => i.id === id ? { ...i, resolvedAt: at } : i);
}

/** The inbox is adult-only. It is the machinery of coordination — §2.4. */
export function inboxVisibleTo(role: string): boolean {
  return role !== 'child';
}
