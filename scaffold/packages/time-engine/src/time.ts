import { DateTime } from 'luxon';

export type Ambiguity = 'first' | 'last';

export interface TzInterval {
  tz: string;
  start: string | null;   // ISO instant, null = open
  end: string | null;
  confidence?: number;
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
    const s = iv.start ? DateTime.fromISO(iv.start, { zone: 'utc' }).toMillis() : -Infinity;
    const e = iv.end   ? DateTime.fromISO(iv.end,   { zone: 'utc' }).toMillis() :  Infinity;
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
 */
export function resolveWallClock(
  localDate: string,                 // 'YYYY-MM-DD'
  localTime: string,                 // 'HH:mm'
  zone: string,
  onAmbiguous: Ambiguity = 'first'
): { instant: DateTime; anomaly: 'none' | 'nonexistent' | 'ambiguous' } {
  const iso = `${localDate}T${localTime}`;
  const dt = DateTime.fromISO(iso, { zone });

  if (!dt.isValid) throw new Error(`unparsable local time: ${iso} @ ${zone}`);

  // Luxon does NOT invalidate a nonexistent local time — it silently maps it
  // forward across the gap. Relying on `isValid` here means the anomaly is
  // never detected and never logged. Round-trip instead: if formatting the
  // resulting instant back to local wall clock does not reproduce what we
  // asked for, the requested time did not exist.
  if (dt.toFormat('HH:mm') !== localTime) {
    return { instant: dt, anomaly: 'nonexistent' };
  }

  // During the repeated hour, adding 1h to the INSTANT leaves the wall clock
  // unchanged because the offset absorbs it. That is a reliable ambiguity test.
  const later = dt.plus({ hours: 1 });
  const ambiguous =
    later.toFormat('yyyy-MM-dd HH:mm') === dt.toFormat('yyyy-MM-dd HH:mm');

  if (ambiguous) {
    return { instant: onAmbiguous === 'last' ? later : dt, anomaly: 'ambiguous' };
  }
  return { instant: dt, anomaly: 'none' };
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
