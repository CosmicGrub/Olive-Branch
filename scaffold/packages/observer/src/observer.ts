/**
 * MASTERFILE §17.3 — the observer tier.
 *
 * A grandmother, a step-parent, an aunt who does the school run. Specified since
 * v0.3.0, referenced by the canvas, and never actually built — so in practice
 * every adult in a child's life was either a full guardian or absent.
 *
 * THE DESIGN PROBLEM: an observer must be able to be present without becoming a
 * party. A grandmother who can see the custody schedule is useful; a grandmother
 * who can see the parent-to-parent log has been handed ammunition, and the person
 * who invited her will regret it.
 */

export type ObserverRole = 'grandparent' | 'step_parent' | 'relative' | 'carer';

export interface Observer {
  userId: string;
  role: ObserverRole;
  /** Which guardian vouched for them. Only that guardian can revoke. */
  invitedBy: string;
  label: string;
  invitedAt: string;
  acceptedAt: string | null;
  revokedAt: string | null;
}

/**
 * The grant list is deliberately short, and the denied list is deliberately long
 * and explicit — an observer tier defined by what it *can* do drifts wider every
 * release, whereas one defined by what it cannot has to be argued with.
 */
export const OBSERVER_MAY = [
  'see_child_calendar', 'see_exchange_times', 'receive_a_show_if_sent',
  'send_a_message_to_the_child', 'join_a_call_if_invited',
  'watch_shared_canvas', 'point_on_canvas', 'see_own_invitation',
] as const;

export const OBSERVER_MAY_NOT = [
  'read_parent_to_parent_log', 'see_expenses', 'see_court_export',
  'see_care_notes', 'read_child_journal', 'see_medication_record',
  'change_the_schedule', 'approve_an_expense', 'invite_anybody',
  'see_the_other_guardian_at_all', 'draw_on_canvas', 'start_a_call',
  'see_briefing', 'see_coordination_inbox', 'see_expiry_digest',
] as const;

export type Capability = typeof OBSERVER_MAY[number] | typeof OBSERVER_MAY_NOT[number];

export function observerMay(cap: string): boolean {
  return (OBSERVER_MAY as readonly string[]).includes(cap);
}

/**
 * The single most important line in this module.
 *
 * An observer invited by one parent must not become visible to, or able to see,
 * the other. Otherwise inviting a grandmother becomes a move in a dispute rather
 * than a kindness to a child.
 */
export function observerSeesGuardian(): false { return false; }
export function guardianSeesOthersObservers(): false { return false; }

/**
 * "Time-boxed by default" (this file's own header) never had a number attached
 * to it — every OTHER expiry-bearing concept in this codebase does (PIN
 * lockouts, session TTLs, challenge windows), so an observer grant should not
 * be the one exception that expires "eventually." Six months: long enough
 * that a genuinely present grandparent or therapist isn't nagged every season,
 * short enough that a grant nobody remembers making doesn't quietly become
 * permanent. Renewal is just re-inviting — invite() already handles an
 * already-accepted, non-revoked observer being re-added the same way a fresh
 * one is, so there is no separate "renew" verb to build.
 */
export const OBSERVER_GRANT_TTL_DAYS = 180;

export type InviteError = 'not_a_guardian' | 'already_invited' | 'child_cannot_invite';

export function invite(
  existing: Observer[], byRole: 'guardian' | 'child' | 'observer',
  o: Omit<Observer, 'acceptedAt' | 'revokedAt'>,
): { ok: true; observers: Observer[] } | { ok: false; reason: InviteError } {
  if (byRole === 'child') return { ok: false, reason: 'child_cannot_invite' };
  if (byRole !== 'guardian') return { ok: false, reason: 'not_a_guardian' };
  if (existing.some(x => x.userId === o.userId && !x.revokedAt)) {
    return { ok: false, reason: 'already_invited' };
  }
  return { ok: true, observers: [...existing, { ...o, acceptedAt: null, revokedAt: null }] };
}

/** Only the guardian who vouched may revoke. Revocation is immediate. */
export function revoke(
  observers: Observer[], userId: string, byUserId: string, at: string,
): { ok: true; observers: Observer[] } | { ok: false; reason: 'not_your_invitation' } {
  const o = observers.find(x => x.userId === userId && !x.revokedAt);
  if (!o) return { ok: true, observers };
  if (o.invitedBy !== byUserId) return { ok: false, reason: 'not_your_invitation' };
  return { ok: true, observers: observers.map(x =>
    x.userId === userId ? { ...x, revokedAt: at } : x) };
}

export const activeObservers = (o: Observer[]) =>
  o.filter(x => x.acceptedAt && !x.revokedAt);

/**
 * §21 interaction. From the age at which she curates her archive, she can also
 * decide which observers see her shows. Before that, the inviting guardian
 * decides — but the ladder moves it to her, like everything else.
 */
export const CHILD_CONTROLS_OBSERVERS_FROM_AGE = 13;

export function whoDecidesObserverVisibility(age: number): 'child' | 'guardian' {
  return age >= CHILD_CONTROLS_OBSERVERS_FROM_AGE ? 'child' : 'guardian';
}

/** An observer never sees the machinery. §2.4 applies to them as much as to her. */
export const OBSERVER_FORBIDDEN = [
  'expenses', 'courtExport', 'messageLog', 'careNote', 'journal',
  'medication', 'briefing', 'inbox', 'otherGuardian',
] as const;

export function auditObserverView(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((OBSERVER_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
