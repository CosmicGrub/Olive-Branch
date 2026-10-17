import { DateTime } from 'luxon';

export type Ambiguity = 'first' | 'last';

export interface TzInterval {
  tz: string;
  start: string | null;   // ISO instant, null = open
  end: string | null;
  confidence?: number;
}

/**
 * An interval bound, as epoch millis — and a LOUD failure if it is not a
 * parseable ISO-8601 instant. Luxon returns an invalid DateTime (NaN millis)
 * for a malformed string, and `t >= NaN` is simply false, so without this
 * check a bound in the wrong shape made its whole interval silently match
 * nothing and resolveZone() quietly fall back to the home zone. That is the
 * exact "silent corruption" this module exists to refuse (§6.2): a child's
 * bedtime message resolved in the wrong zone, with nothing logged. It really
 * happened — db/pool.ts's childCtxFor() once handed this function Postgres's
 * '2026-06-01 00:00:00+00' text, which Luxon's fromISO() rejects. Throwing
 * turns that whole class of data bug into an immediate, attributable error.
 */
function boundMillis(value: string, which: 'start' | 'end'): number {
  const ms = DateTime.fromISO(value, { zone: 'utc' }).toMillis();
  if (Number.isNaN(ms)) {
    throw new Error(
      `resolveZone: unparsable tz interval ${which} ${JSON.stringify(value)} — expected an ISO-8601 instant`);
  }
  return ms;
}

/**
 * MASTERFILE §4.2 — the child's zone is a lookup against a timeline, not a
 * field read. A child is in NC during the school year and TX for six weeks
 * each summer; that is the product, not an edge case.
 *
 * Pure function here so it is testable without a database. The service
 * wrapper does the `valid @> $2::timestamptz` query and passes the rows in.
 */
export function resolveZone(
  intervals: TzInterval[],
  at: DateTime,
  fallbackTz: string
): string {
  const t = at.toMillis();
  const hits = intervals.filter(iv => {
    const s = iv.start ? boundMillis(iv.start, 'start') : -Infinity;
    const e = iv.end   ? boundMillis(iv.end,   'end')   :  Infinity;
    return t >= s && t < e;                        // [start, end)
  });
  if (hits.length === 0) return fallbackTz;
  hits.sort((a, b) => (b.confidence ?? 100) - (a.confidence ?? 100));
  return hits[0].tz;
}

/**
 * MASTERFILE §6.2 — resolve a wall-clock local time to an absolute instant.
 *
 *   Spring forward (2nd Sun in March): 2:30 AM does not exist.
 *   Fall back      (1st Sun in Nov):   1:30 AM exists twice.
 *
 * Both are silent-corruption bugs if the library chooses for you. We choose,
 * and we report which pathology fired so the caller can log it.
 *
 * DELIBERATELY NOT `DateTime.fromISO(iso, { zone })`. Real bug, found by a
 * golden fixture that went red the day the calendar passed 1 Nov 2026: Luxon
 * seeds its guess for a local time from the zone's offset at the CURRENT
 * moment (Settings.now), and for an ambiguous time that guess decides which of
 * the two instants it returns. While "now" was still EDT it returned the first
 * occurrence, which is what the old code assumed; once "now" was EST it
 * returned the second — so `'first'` silently returned the wrong instant and
 * the ambiguity test below it saw nothing wrong. A function that exists to
 * refuse silent choices gave a different answer depending on the date it ran.
 *
 * So the instants are derived here, from the zone's offset table alone, with no
 * reference to the clock: read the wall time as if it were UTC, collect the
 * offsets in force a day either side (a zone changes offset at most once in
 * that span), and keep each candidate whose offset really is in force at the
 * instant it implies. Two survivors = the repeated hour; none = the gap.
 */
export function resolveWallClock(
  localDate: string,                 // 'YYYY-MM-DD'
  localTime: string,                 // 'HH:mm'
  zone: string,
  onAmbiguous: Ambiguity = 'first'
): { instant: DateTime; anomaly: 'none' | 'nonexistent' | 'ambiguous' } {
  const iso = `${localDate}T${localTime}`;
  const wall = DateTime.fromISO(iso, { zone: 'utc' });   // wall clock read as UTC
  if (!wall.isValid || !DateTime.fromMillis(0, { zone }).isValid) {
    throw new Error(`unparsable local time: ${iso} @ ${zone}`);
  }

  const DAY = 86_400_000;
  const wallMs = wall.toMillis();
  const offsetAt = (ts: number) => DateTime.fromMillis(ts, { zone }).offset;   // minutes east of UTC
  const before = offsetAt(wallMs - DAY);
  const after = offsetAt(wallMs + DAY);

  // An instant is a real reading of this wall time only if the zone's offset AT
  // that instant is the very offset we subtracted to get there.
  const instants = [...new Set([before, after])]
    .map(o => wallMs - o * 60_000)
    .filter(ts => offsetAt(ts) === (wallMs - ts) / 60_000)
    .sort((a, b) => a - b);

  const at = (ts: number) => DateTime.fromMillis(ts, { zone });

  if (instants.length === 0) {
    // The gap. Shift FORWARD across it by reading the wall time with the offset
    // that was in force just before the transition — 02:30 EST is 03:30 EDT.
    return { instant: at(wallMs - before * 60_000), anomaly: 'nonexistent' };
  }
  if (instants.length === 2) {
    return { instant: at(onAmbiguous === 'last' ? instants[1] : instants[0]), anomaly: 'ambiguous' };
  }
  return { instant: at(instants[0]), anomaly: 'none' };
}

/** Offset in hours between two zones AT A GIVEN INSTANT. Never cached. */
export function offsetBetween(zoneA: string, zoneB: string, at: DateTime): number {
  return (at.setZone(zoneA).offset - at.setZone(zoneB).offset) / 60;
}

/** MASTERFILE §6.5 — enumerate child-local dates for a banked batch. */
export function enumerateLocalDates(
  startLocal: string,
  endLocal: string,
  cadence: 'daily' | 'weekdays' | 'weekly'
): string[] {
  const out: string[] = [];
  let d = DateTime.fromISO(startLocal, { zone: 'utc' });
  const end = DateTime.fromISO(endLocal, { zone: 'utc' });
  while (d <= end) {
    const dow = d.weekday;                          // 1=Mon .. 7=Sun
    const keep =
      cadence === 'daily'    ? true :
      cadence === 'weekdays' ? dow <= 5 :
                               d.toMillis() === DateTime.fromISO(startLocal, { zone: 'utc' }).toMillis()
                                 || d.weekday === DateTime.fromISO(startLocal, { zone: 'utc' }).weekday;
    if (keep) out.push(d.toISODate()!);
    d = d.plus({ days: 1 });
  }
  return out;
}
