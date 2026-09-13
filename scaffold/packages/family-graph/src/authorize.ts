/**
 * MASTERFILE §5.1, §8.1 — authorization over the family graph.
 *
 * Pure. Takes resolved edges as data so every deny path is unit-testable
 * without a database. The database enforces P6/P7 independently (§5.11, §5.12);
 * this layer is the second lock, not the only one.
 */

export type Role =
  | 'guardian' | 'trusted_adult' | 'step_parent' | 'sitter'
  | 'coordinator' | 'foster_parent' | 'caseworker' | 'therapist';

export type LadderStep = 'none' | 'supervised' | 'monitored' | 'time_limited' | 'open';

export type Action =
  | 'call' | 'message'
  | 'homework.view' | 'homework.annotate'
  | 'calendar.view' | 'calendar.edit'
  | 'list.view' | 'list.claim'
  | 'medication.view' | 'medication.log'
  | 'emergency_card.view' | 'emergency_card.edit'
  | 'archive.view' | 'archive.preserve'
  | 'export.raw' | 'export.certified'
  | 'expense.view' | 'expense.create' | 'expense.resolve'
  | 'care_note.view' | 'care_note.write'
  | 'ladder.advance'
  | 'settings'
  // Child-only, by construction: never listed in ANY role's ROLE_CAPS below.
  // api.ts's own outer gate calls can(action, [], childId, 'child') for a
  // child principal (empty edges, always), so this Action is unreachable
  // via the normal guardian-edge path no matter what a future edit does to
  // ROLE_CAPS elsewhere -- there is no edge to grant it through. Backs
  // letters_screen.dart's own real, structural claim: "not a guardian
  // (there is no guardian code path in this file at all) and not her,
  // either [until real]" -- see db/migrations/0028's own header.
  | 'letter'
  | 'journal.read';

export interface Edge {
  childId: string;
  userId: string;
  role: Role;
  scope: Partial<Record<Action, boolean>>;
  observerOnly: boolean;
  restricted: boolean;
  validFrom: string | null;
  validTo: string | null;
  expiresAt: string | null;
  closedAt: string | null;
  ladderStep: LadderStep | null;
}

export interface Tier { court: boolean }

export type Deny =
  | 'no_edge' | 'edge_closed' | 'edge_expired' | 'outside_validity'
  | 'restricted' | 'ladder_none' | 'observer_readonly'
  | 'role_lacks_capability' | 'scope_denied'
  | 'P6_child_financial' | 'P7_journal_never'
  | 'tier_required';

export type Decision = { allow: true } | { allow: false; reason: Deny };

const WRITES: Action[] = [
  'homework.annotate', 'calendar.edit', 'list.claim', 'medication.log',
  'emergency_card.edit', 'care_note.write',
  'archive.preserve', 'expense.create', 'expense.resolve', 'ladder.advance', 'settings',
];

const CONTACT: Action[] = ['call', 'message'];

/** What each role can do at all, before scope narrows it further. */
const ROLE_CAPS: Record<Role, Action[]> = {
  guardian: [
    'call','message','homework.view','homework.annotate','calendar.view',
    'calendar.edit','list.view','list.claim','medication.view','medication.log',
    'emergency_card.view','emergency_card.edit','archive.view','archive.preserve',
    'export.raw','export.certified','expense.view','expense.create','expense.resolve',
    'care_note.view','care_note.write','settings',
  ],
  step_parent: [
    'call','message','homework.view','calendar.view','list.view',
    'medication.view','emergency_card.view','archive.view','care_note.view',
  ],
  trusted_adult: ['call','message','calendar.view','archive.view'],
  // Time-boxed. Needs the emergency card, the medication log, and enough
  // day-to-day context to leave a real one -- "she skipped her nap" is
  // exactly what a sitter, not a step_parent, is on shift to notice.
  sitter: ['emergency_card.view','medication.view','medication.log','calendar.view',
    'care_note.view','care_note.write'],
  foster_parent: [
    'call','message','homework.view','homework.annotate','calendar.view',
    'calendar.edit','list.view','list.claim','medication.view','medication.log',
    'emergency_card.view','archive.view','care_note.view','care_note.write',
  ],
  // Court-appointed. Reads the record, advances the ladder, touches nothing
  // the child experiences. NEVER care_note.view -- care_note.dart's own file
  // header is explicit that a note is deliberately outside the §13
  // tamper-evident log precisely so it can never become a court exhibit;
  // granting a coordinator a read here would be that exact leak.
  coordinator: ['calendar.view','expense.view','export.certified','ladder.advance'],
  caseworker: ['calendar.view','medication.view','emergency_card.view',
    'care_note.view','ladder.advance'],
  therapist: ['ladder.advance'],
};

/**
 * P7 is checked FIRST, unconditionally, for every role — before edges, before
 * scope, before anything. There is no argument to this function that returns
 * allow for 'journal.read'. The parameter exists so a caller cannot construct
 * the request in a way that looks answerable.
 */
export function can(
  action: Action,
  edges: Edge[],
  childId: string,
  now: Date,
  actorRoleName?: string,
  tier: Tier = { court: false },
): Decision {
  // ---- P7. No exceptions, no tiers, no escalation, no court order. --------
  if (action === 'journal.read') return { allow: false, reason: 'P7_journal_never' };

  // ---- P6. A child role never sees a financial surface. -------------------
  if (actorRoleName === 'child' && action.startsWith('expense.')) {
    return { allow: false, reason: 'P6_child_financial' };
  }

  const t = now.getTime();
  const forChild = edges.filter(e => e.childId === childId);
  if (forChild.length === 0) return { allow: false, reason: 'no_edge' };

  // Evaluate every edge; the actor may hold more than one. Collect the most
  // specific denial so the caller gets a useful reason rather than 'no_edge'.
  let best: Deny = 'no_edge';
  const rank: Deny[] = [
    'no_edge','edge_closed','edge_expired','outside_validity','restricted',
    'ladder_none','observer_readonly','role_lacks_capability','scope_denied',
    'tier_required',
  ];
  const worse = (a: Deny, b: Deny) => rank.indexOf(a) >= rank.indexOf(b) ? a : b;

  for (const e of forChild) {
    if (e.closedAt && new Date(e.closedAt).getTime() <= t) {
      best = worse(best, 'edge_closed'); continue;
    }
    if (e.expiresAt && new Date(e.expiresAt).getTime() <= t) {
      best = worse(best, 'edge_expired'); continue;
    }
    if (e.validFrom && new Date(e.validFrom).getTime() > t) {
      best = worse(best, 'outside_validity'); continue;
    }
    if (e.validTo && new Date(e.validTo).getTime() <= t) {
      best = worse(best, 'outside_validity'); continue;
    }
    if (e.restricted) { best = worse(best, 'restricted'); continue; }

    // Ladder step 'none' blocks contact but not, say, a coordinator's read.
    if ((e.ladderStep ?? 'open') === 'none' && CONTACT.includes(action)) {
      best = worse(best, 'ladder_none'); continue;
    }
    // §17.3 observer tier — a reluctant parent watching, not participating.
    if (e.observerOnly && WRITES.includes(action)) {
      best = worse(best, 'observer_readonly'); continue;
    }
    if (!ROLE_CAPS[e.role].includes(action)) {
      best = worse(best, 'role_lacks_capability'); continue;
    }
    // Explicit scope false overrides the role default; undefined does not.
    if (e.scope[action] === false) { best = worse(best, 'scope_denied'); continue; }

    // §16.1 #3 — certified export is Court tier. Raw export never is.
    if (action === 'export.certified' && !tier.court) {
      best = worse(best, 'tier_required'); continue;
    }
    return { allow: true };
  }
  return { allow: false, reason: best };
}

/** §17.1 — the product must be fully usable with exactly one guardian. */
export function isSingleGuardianViable(edges: Edge[], childId: string, now: Date): boolean {
  const live = edges.filter(e =>
    e.childId === childId && !e.closedAt && !e.restricted &&
    (e.ladderStep ?? 'open') !== 'none' &&
    (!e.expiresAt || new Date(e.expiresAt) > now) &&
    e.role === 'guardian');
  return live.length >= 1;
}
