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

/** Keys that must never appear in a sitter-visible bundle. */
export const CARD_FORBIDDEN = [
  'expense', 'expenses', 'amount', 'journal', 'custody', 'order_ref',
  'orderRef', 'messages', 'archive', 'latitude', 'longitude', 'address',
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
  constructor(readonly by: string, readonly atLocal: string) {
    // §9.6.1 — name the parent and the local time, state what is next, stop.
    // Any further framing reads as an accusation, and none of it is the child's.
    super(`${by} gave this dose at ${atLocal}.`);
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

/** PRN (as-needed) doses are not slot-bound and must not collide. */
export function prnAllowed(existing: DoseRecord[], medicationId: string,
  at: DateTime, minGapHours: number): boolean {
  const last = existing.filter(d => d.medicationId === medicationId)
    .sort((a, b) => b.administeredAt.localeCompare(a.administeredAt))[0];
  if (!last) return true;
  return at.diff(DateTime.fromISO(last.administeredAt), 'hours').hours >= minGapHours;
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

const LOCATION_KEYS = ['lat','latitude','lng','lon','longitude','coords',
  'geohash','accuracy','altitude','address'];

export function auditArrival(e: Record<string, unknown>):
  { ok: true } | { ok: false; leaks: string[] } {
  const leaks = Object.keys(e).filter(k => LOCATION_KEYS.includes(k.toLowerCase()));
  return leaks.length ? { ok: false, leaks } : { ok: true };
}
