import { DateTime } from 'luxon';

/**
 * MASTERFILE §9.6, §9.7 — the coordination layer.
 * Emergency card, medication log, bag manifest, arrival.
 */

// ============================================================ emergency card =
export interface EmergencyCard {
  childId: string;
  displayName: string;
  birthDate: string;
  bloodType: string | null;
  allergies: { substance: string; reaction: string; severity: 'mild' | 'severe' }[];
  conditions: string[];
  meds: { name: string; dose: string; note?: string }[];
  providers: { role: string; name: string; phone: string }[];
  guardians: { name: string; phone: string }[];
  insurance: { carrier: string; memberId: string } | null;
  updatedAt: string;
}

/**
 * §9.6.3 — built for a babysitter or an ER intake nurse, not for browsing.
 *
 * Severe allergies sort first because the reader may only get through the first
 * line. The bundle must be SELF-CONTAINED: no ids to resolve, no URLs to fetch,
 * nothing that requires a network. A card that needs connectivity is not an
 * emergency card.
 */
export function offlineBundle(card: EmergencyCard): {
  bundle: Record<string, unknown>; bytes: number;
} {
  const allergies = [...card.allergies].sort((a, b) =>
    (b.severity === 'severe' ? 1 : 0) - (a.severity === 'severe' ? 1 : 0));
  const bundle = {
    v: 1,
    child: { name: card.displayName, birthDate: card.birthDate,
             bloodType: card.bloodType },
    allergies, conditions: card.conditions, meds: card.meds,
    providers: card.providers, guardians: card.guardians,
    insurance: card.insurance,
    updatedAt: card.updatedAt,
  };
  return { bundle, bytes: Buffer.byteLength(JSON.stringify(bundle)) };
}

// §9.7.2, prohibition P3 — the same location-key list `auditArrival` below
// uses, hoisted above `CARD_FORBIDDEN` so both real guards share ONE
// definition of "this looks like a coordinate." `CARD_FORBIDDEN` used to
// maintain its own narrower duplicate (`latitude`, `longitude`, `address`
// only) — a real, live gap on the exact surface built for the LEAST
// trusted audience (a sitter/ER nurse handed the emergency card): a field
// named `lat`, `lng`, `coords`, `geohash`, `accuracy`, or `altitude` passed
// `auditBundle()` silently. Two guards duplicating the same fact drift
// apart the moment only one gets fixed — sharing the constant makes that
// structurally impossible instead of relying on remembering to update both.
const LOCATION_KEYS = ['lat', 'latitude', 'lng', 'lon', 'longitude', 'coords',
  'geohash', 'accuracy', 'altitude', 'address'];

/** Keys that must never appear in a sitter-visible bundle. */
export const CARD_FORBIDDEN = [
  'expense', 'expenses', 'amount', 'journal', 'custody', 'order_ref',
  'orderRef', 'messages', 'archive', ...LOCATION_KEYS,
] as const;

export function auditBundle(b: Record<string, unknown>):
  { ok: true } | { ok: false; leaks: string[] } {
  const flat = JSON.stringify(b).toLowerCase();
  const leaks = CARD_FORBIDDEN.filter(k => flat.includes(`"${k}"`));
  return leaks.length ? { ok: false, leaks } : { ok: true };
}

// ================================================================ medication =
export type DoseStatus = 'given' | 'skipped' | 'refused' | 'missed';

export interface DoseKey { medicationId: string; localDate: string; slot: string; }
export interface DoseRecord extends DoseKey {
  administeredAt: string; localTz: string; byUserName: string; status: DoseStatus;
}

export class AlreadyAdministered extends Error {
  // Explicit fields rather than `constructor(readonly by: string, ...)`: this
  // module is now imported by packages/db/src/pool.ts, and Node's type
  // stripping (which loads .ts imports as-is) rejects TypeScript parameter
  // properties. Keep this file to erasable syntax.
  readonly by: string;
  readonly atLocal: string;
  constructor(by: string, atLocal: string) {
    // §9.6.1 — name the parent and the local time, state what is next, stop.
    // Any further framing reads as an accusation, and none of it is the child's.
    super(`${by} gave this dose at ${atLocal}.`);
    this.by = by;
    this.atLocal = atLocal;
  }
}

/**
 * §5.8 / §6.7 — the exchange-day double-dose guard. The key is the CHILD's
 * local date: an 8am dose in Austin and "the morning dose" in Charlotte are the
 * same slot on the same child-local day, and keyed on server or actor time this
 * check silently never fires.
 */
export function doseKey(
  medicationId: string, slot: string, at: DateTime, childZone: string,
): DoseKey {
  return { medicationId, slot, localDate: at.setZone(childZone).toISODate()! };
}

export function recordDose(
  existing: DoseRecord[], k: DoseKey, rec: Omit<DoseRecord, keyof DoseKey>,
): { ok: true; record: DoseRecord } | { ok: false; error: AlreadyAdministered } {
  const clash = existing.find(d => d.medicationId === k.medicationId &&
    d.localDate === k.localDate && d.slot === k.slot && d.status === 'given');
  if (clash && rec.status === 'given') {
    return { ok: false, error: new AlreadyAdministered(clash.byUserName,
      DateTime.fromISO(clash.administeredAt).setZone(clash.localTz)
        .toFormat('h:mm a ZZZZ')) };
  }
  return { ok: true, record: { ...k, ...rec } };
}

/**
 * PRN (as-needed) doses are not slot-bound and must not collide.
 *
 * Only doses that were actually GIVEN count (S-D6): a skipped, refused or
 * missed entry administered nothing, so it must not start a minimum-gap clock.
 * The gap is checked on BOTH sides of `at` so a retroactive "given at" entry
 * cannot slip in beside a later dose either.
 */
export function prnAllowed(existing: DoseRecord[], medicationId: string,
  at: DateTime, minGapHours: number): boolean {
  return !existing.some(d => d.medicationId === medicationId && d.status === 'given' &&
    Math.abs(at.diff(DateTime.fromISO(d.administeredAt), 'hours').hours) < minGapHours);
}

// ============================================== server-side dose validation ==
/** What the server (and the Dart port) knows about a medication when a dose
 *  is logged. `maxPer24h` null = no explicit cap. */
export interface MedicationRule {
  slots: string[];
  isPrn: boolean;
  minGapHours: number | null;
  maxPer24h: number | null;
}

export type DoseCheck =
  | { ok: true; slot: string }
  | { ok: false; reason: 'unknown_slot'; allowed: string[] }
  | { ok: false; reason: 'already_administered'; by: string; atLocal: string }
  | { ok: false; reason: 'too_soon'; nextAllowedAt: string; minGapHours: number }
  | { ok: false; reason: 'daily_max'; max: number };

/**
 * S-D6 — the medication safety rules, in ONE place that the server's
 * `recordDose` and the client's offline path both run.
 *
 *   1. The slot must be one the medication actually has. Matching ignores case
 *      and surrounding space and RETURNS THE CANONICAL spelling: logging
 *      "Morning" instead of "morning" used to create a second row beside the
 *      real one and defeat the double-dose guard.
 *   2. A scheduled medication has one 'given' dose per child-local day per slot.
 *   3. A PRN medication is not slot-bound but honours its minimum gap and its
 *      maximum number of doses in any rolling 24 hours (checked around `at`,
 *      on both sides, so a back-dated entry is held to the same rules).
 *
 * Statuses other than 'given' administer nothing, so only rule 1 applies.
 * `history` is every dose of THIS medication (any status) near `at`;
 * `localDate` is the child-local date of `at`.
 */
export function checkDose(
  med: MedicationRule, slot: string, status: DoseStatus, at: DateTime,
  localDate: string, history: DoseRecord[],
): DoseCheck {
  const want = slot.trim().toLowerCase();
  const canonical = med.slots.find(s => s.trim().toLowerCase() === want);
  if (!canonical) return { ok: false, reason: 'unknown_slot', allowed: [...med.slots] };
  if (status !== 'given') return { ok: true, slot: canonical };

  const given = history.filter(d => d.status === 'given');
  if (!med.isPrn) {
    const clash = given.find(d => d.localDate === localDate && d.slot === canonical);
    if (clash) {
      return { ok: false, reason: 'already_administered', by: clash.byUserName,
        atLocal: DateTime.fromISO(clash.administeredAt).setZone(clash.localTz)
          .toFormat('h:mm a ZZZZ') };
    }
    return { ok: true, slot: canonical };
  }

  const gap = med.minGapHours;
  if (gap !== null && gap > 0) {
    const near = given.filter(d =>
      Math.abs(at.diff(DateTime.fromISO(d.administeredAt), 'hours').hours) < gap);
    if (near.length) {
      // The earliest moment this entry could stand: the gap after the LATEST
      // of the doses in the way.
      const latest = Math.max(...near.map(d => DateTime.fromISO(d.administeredAt).toMillis()));
      return { ok: false, reason: 'too_soon', minGapHours: gap,
        nextAllowedAt: DateTime.fromMillis(latest).plus({ hours: gap }).toUTC().toISO()! };
    }
  }
  if (med.maxPer24h !== null && med.maxPer24h > 0) {
    const times = [...given.map(d => DateTime.fromISO(d.administeredAt).toMillis()),
      at.toMillis()].sort((x, y) => x - y);
    const DAY = 24 * 3600 * 1000;
    // Every 24h window (t - 24h, t] that ends on a dose time AND contains this
    // entry: only those can be made worse by it (history that already broke
    // the cap elsewhere must not lock the medication forever).
    const atMs = at.toMillis();
    for (const t of times.filter(x => x >= atMs && x < atMs + DAY)) {
      const n = times.filter(x => x > t - DAY && x <= t).length;
      if (n > med.maxPer24h) return { ok: false, reason: 'daily_max', max: med.maxPer24h };
    }
  }
  return { ok: true, slot: canonical };
}

// =============================================================== the exchange =
export interface BagItem { id: string; label: string; essential: boolean;
  sent: boolean; returned: boolean; }

/** §9.7.1 — essential items first; the reader may only scan the top. */
export function manifestOrder(items: BagItem[]): BagItem[] {
  return [...items].sort((a, b) =>
    (b.essential ? 1 : 0) - (a.essential ? 1 : 0) || a.label.localeCompare(b.label));
}

export function unpacked(items: BagItem[]): BagItem[] {
  return manifestOrder(items.filter(i => !i.sent));
}

export interface ArrivalEvent {
  exchangeId: string;
  arrivedAt: string;
  delayMinutes: number;
}

/**
 * §9.7.2, prohibition P3 — arrival is an EVENT. A geofence may fire it
 * on-device; coordinates never leave. This function accepts no location
 * parameter, and `auditArrival` refuses any payload carrying one, so a future
 * contributor cannot add it "just for accuracy".
 */
export function recordArrival(
  exchangeId: string, scheduledAt: DateTime, arrivedAt: DateTime,
): ArrivalEvent {
  return {
    exchangeId,
    arrivedAt: arrivedAt.toISO()!,
    delayMinutes: Math.max(0, Math.round(arrivedAt.diff(scheduledAt, 'minutes').minutes)),
  };
}

export function auditArrival(e: Record<string, unknown>):
  { ok: true } | { ok: false; leaks: string[] } {
  const leaks = Object.keys(e).filter(k => LOCATION_KEYS.includes(k.toLowerCase()));
  return leaks.length ? { ok: false, leaks } : { ok: true };
}
