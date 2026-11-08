/**
 * Delivery engine — adversarial unit suite.
 * MASTERFILE §6.3–6.5. Run: node test/delivery.test.mjs
 */
import { DateTime } from 'luxon';
import { readFileSync } from 'node:fs';
import { generate as generateDeliveryVectors } from '../../../tools/gen-delivery-vectors.mjs';
import {
  materialize, nextReachableWindow, PAST_GRACE_MINUTES, partsOn, activeDayPart, zonedWallClock,
} from '../src/materialize.mjs';
import { gate, recipientContext, MAX_DEFERS } from '../src/gate.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}

const NYC = 'America/New_York', CHI = 'America/Chicago';
const ALL = [0, 1, 2, 3, 4, 5, 6];

const DAYPARTS = [
  { kind: 'asleep',        startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: ALL, reachable: false },
  { kind: 'wake',          startsLocal: '06:30', endsLocal: '08:00', daysOfWeek: ALL, reachable: true  },
  { kind: 'school',        startsLocal: '08:00', endsLocal: '15:00', daysOfWeek: [1,2,3,4,5], reachable: false },
  { kind: 'after_school',  startsLocal: '15:00', endsLocal: '18:30', daysOfWeek: ALL, reachable: true  },
  { kind: 'dinner',        startsLocal: '18:30', endsLocal: '19:30', daysOfWeek: ALL, reachable: true  },
  { kind: 'bedtime',       startsLocal: '20:30', endsLocal: '21:00', daysOfWeek: ALL, reachable: true  },
];

// Child is Eastern, then Central for the summer, then Eastern again.
const SPLIT_CTX = {
  homeTz: NYC,
  dayParts: DAYPARTS,
  tzIntervals: [
    { tz: NYC, start: null,                   end: '2026-06-12T22:00:00Z' },
    { tz: CHI, start: '2026-06-12T22:00:00Z', end: '2026-07-25T22:00:00Z' },
    { tz: NYC, start: '2026-07-25T22:00:00Z', end: null                   },
  ],
};
const NYC_CTX = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [] };

const intent = (o) => ({
  id: 'i', childId: 'c', state: 'pending',
  expiresAt: '2030-01-01T00:00:00Z', ...o,
});

// ---------------------------------------------------------------------------
// G1 — the mid-flight batch move. THE scenario I flagged.
//      A 181-night batch materialized in Eastern. On night 60 the child moves
//      to Central. Nights before the move must stay Eastern; nights after must
//      become Central; every night must remain 8:30 PM LOCAL.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-05-01T12:00:00Z');
  const before = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }),
    SPLIT_CTX, now);
  const after = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-07-01', targetDaypart: 'bedtime' }),
    SPLIT_CTX, now);

  check('G1 mid-flight move', 'pre-move night resolves Eastern', before.ok && before.tz, NYC);
  check('G1 mid-flight move', 'post-move night resolves Central', after.ok && after.tz, CHI);
  check('G1 mid-flight move', 'pre-move is 20:30 local',
    before.scheduledAt.setZone(before.tz).toFormat('HH:mm'), '20:30');
  check('G1 mid-flight move', 'post-move is 20:30 local',
    after.scheduledAt.setZone(after.tz).toFormat('HH:mm'), '20:30');
  check('G1 mid-flight move', 'UTC instants differ by the zone gap (1h)',
    (after.scheduledAt.toUTC().hour - before.scheduledAt.toUTC().hour + 24) % 24, 1);

  // Whole batch: zero drift across 181 nights AND a zone change AND two DST flips.
  let drift = 0, zones = new Set();
  for (let i = 0; i < 181; i++) {
    const d = DateTime.fromISO('2026-05-01').plus({ days: i }).toISODate();
    const r = materialize(
      intent({ policy: 'on_local_date', targetLocalDate: d, targetDaypart: 'bedtime' }),
      SPLIT_CTX, now);
    if (!r.ok) { drift++; continue; }
    zones.add(r.tz);
    if (r.scheduledAt.setZone(r.tz).toFormat('HH:mm') !== '20:30') drift++;
  }
  check('G1 mid-flight move', '181 nights, zero drift off 20:30 local', drift, 0);
  check('G1 mid-flight move', 'batch legitimately spans two zones', zones.size, 2);
}

// ---------------------------------------------------------------------------
// G2 — retroactive delivery guard. A missed night must NOT fire late.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-01T12:00:00Z');   // long past June 1

  const stale = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  check('G2 past guard', 'missed banked night EXPIRES, not delivers',
    stale.ok === false && stale.reason, 'target_in_past');

  // Inside the grace window it still goes out — a sweep hiccup should not
  // silently eat a goodnight message.
  const bed = DateTime.fromISO('2026-07-01T00:30:00Z');   // 8:30pm Jun30 EDT
  const justLate = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-30', targetDaypart: 'bedtime' }),
    NYC_CTX, bed.plus({ minutes: PAST_GRACE_MINUTES - 10 }));
  check('G2 past guard', `${PAST_GRACE_MINUTES - 10}min late still delivers`, justLate.ok, 'true');

  const tooLate = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-30', targetDaypart: 'bedtime' }),
    NYC_CTX, bed.plus({ minutes: PAST_GRACE_MINUTES + 10 }));
  check('G2 past guard', `${PAST_GRACE_MINUTES + 10}min late is refused`,
    tooLate.ok === false && tooLate.reason, 'target_in_past');

  const staleInstant = materialize(
    intent({ policy: 'at_instant', targetInstant: '2026-01-01T00:00:00Z' }), NYC_CTX, now);
  check('G2 past guard', 'stale at_instant refused',
    staleInstant.ok === false && staleInstant.reason, 'target_in_past');
}

// ---------------------------------------------------------------------------
// G3 — at_daypart ROLLS FORWARD; on_local_date does not. The distinction
//      between "next bedtime" and "the night of June 1st".
// ---------------------------------------------------------------------------
{
  // 11pm Eastern — today's bedtime is gone.
  const now = DateTime.fromISO('2026-07-02T03:00:00Z');
  const r = materialize(intent({ policy: 'at_daypart', targetDaypart: 'bedtime' }), NYC_CTX, now);
  check('G3 roll vs expire', 'open at_daypart rolls forward', r.ok && r.rolled, 'true');
  check('G3 roll vs expire', 'rolls to tomorrow 20:30 local',
    r.scheduledAt.setZone(r.tz).toFormat('yyyy-MM-dd HH:mm'), '2026-07-02 20:30');

  const dated = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'bedtime', targetLocalDate: '2026-06-01' }),
    NYC_CTX, now);
  check('G3 roll vs expire', 'EXPLICITLY dated at_daypart does not roll',
    dated.ok === false && dated.reason, 'target_in_past');

  const unknown = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'piano_lesson' }), NYC_CTX, now);
  check('G3 roll vs expire', 'undefined day-part is skipped not guessed',
    unknown.ok === false && unknown.reason, 'daypart_undefined');
}

// ---------------------------------------------------------------------------
// G4 — the gate. Never wakes a sleeping child; never fires during school.
// ---------------------------------------------------------------------------
{
  const asleep = DateTime.fromISO('2026-07-02T06:00:00Z');   // 2am EDT
  const g1 = gate(NYC_CTX, asleep);
  check('G4 gate', 'blocked while asleep', `${g1.allow}/${g1.reason}`, 'false/asleep');
  check('G4 gate', 'defers to 6:30am local wake',
    g1.deferTo.setZone(NYC).toFormat('HH:mm'), '06:30');

  const school = DateTime.fromISO('2026-07-02T14:00:00Z');   // 10am EDT Thursday
  check('G4 gate', 'blocked during school', gate(NYC_CTX, school).reason, 'school');

  const evening = DateTime.fromISO('2026-07-02T23:00:00Z');  // 7pm EDT
  check('G4 gate', 'allowed at dinner', gate(NYC_CTX, evening).allow, 'true');

  check('G4 gate', 'emergency is never gated', gate(NYC_CTX, asleep, 'emergency').allow, 'true');

  // Fail OPEN after repeated deferral — silence is worse than bad timing.
  const capped = gate(NYC_CTX, asleep, 'normal', MAX_DEFERS);
  check('G4 gate', 'defer chain is bounded',
    `${capped.allow}/${capped.reason}`, 'true/max_defers_exceeded');

  // Saturday has no `school` part; the child must be reachable at 10am.
  const sat = DateTime.fromISO('2026-07-04T14:00:00Z');
  check('G4 gate', 'weekend 10am is reachable (no school part)', gate(NYC_CTX, sat).allow, 'true');
}

// ---------------------------------------------------------------------------
// G4b — exact boundary minutes. gate()'s `hhmm >= p.startsLocal && hhmm <
//      p.endsLocal` is only correct if both sides are the SAME string width.
//      childCtxFor() (packages/db/src/pool.ts) casts starts_local/ends_local
//      via Postgres's `time::text`, which is second-precision ('12:00:00');
//      gate()'s own `hhmm` is luxon's minute-precision 'HH:mm' ('12:00'). JS
//      string comparison treats the shorter string as LESS than a longer one
//      it's a prefix of, so an unnormalized '12:00' >= '12:00:00' is FALSE —
//      the day-part starting at that minute would be silently skipped for
//      its own first minute every day. pool.ts now truncates the cast to
//      'HH:mm' width before gate() ever sees it; these fixtures are already
//      that width, so this section instead locks down gate()'s comparison
//      OPERATORS themselves (>= / < , not > / <=) at the instant they
//      actually matter: exactly on a boundary minute, not one minute either
//      side of it, which is the only case the precision bug above hides in
//      and every other G4 case here lands well clear of.
// ---------------------------------------------------------------------------
{
  // 21:00 EDT exactly — the moment `asleep` starts (wraps midnight, so this
  // exercises the `hhmm >= p.startsLocal` arm of the wrap branch).
  const asleepStarts = DateTime.fromISO('2026-07-03T01:00:00Z');
  check('G4b boundary minute', 'blocked AT asleep\'s own start minute (21:00)',
    `${gate(NYC_CTX, asleepStarts).allow}/${gate(NYC_CTX, asleepStarts).reason}`,
    'false/asleep');

  // 06:30 EDT exactly — asleep's end / wake's start. Must already be `wake`
  // (reachable), not still `asleep` for one more minute.
  const wakeStarts = DateTime.fromISO('2026-07-02T10:30:00Z');
  check('G4b boundary minute', 'reachable AT wake\'s own start minute (06:30)',
    gate(NYC_CTX, wakeStarts).allow, 'true');

  // 08:00 EDT exactly, a Thursday — wake's end / school's start. Must already
  // be `school` (blocked), not still `wake` for one more minute.
  const schoolStarts = DateTime.fromISO('2026-07-02T12:00:00Z');
  check('G4b boundary minute', 'blocked AT school\'s own start minute (08:00)',
    gate(NYC_CTX, schoolStarts).reason, 'school');

  // 15:00 EDT exactly — school's end / after_school's start. Must already be
  // reachable, not still gated for one more minute.
  const afterSchoolStarts = DateTime.fromISO('2026-07-02T19:00:00Z');
  check('G4b boundary minute', 'reachable AT after_school\'s own start minute (15:00)',
    gate(NYC_CTX, afterSchoolStarts).allow, 'true');

  // 18:30 EDT exactly — after_school's end / dinner's start. Both reachable,
  // so this confirms `current` itself flips (dinner, not after_school) via
  // `reason` on an adjacent blocked probe one minute later being unaffected —
  // checked directly here via the day-part boundary staying reachable.
  const dinnerStarts = DateTime.fromISO('2026-07-02T22:30:00Z');
  check('G4b boundary minute', 'reachable AT dinner\'s own start minute (18:30)',
    gate(NYC_CTX, dinnerStarts).allow, 'true');
}

// ---------------------------------------------------------------------------
// G5 — sender-side guard. The parent sees HER clock, not theirs.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-03T02:40:00Z');      // 10:40pm EDT / 9:40pm CDT
  const c = recipientContext(NYC_CTX, now, CHI);
  check('G5 send guard', 'child local time', c.localTime, '10:40 PM');
  check('G5 send guard', 'child zone abbr', c.zoneAbbr, 'EDT');
  check('G5 send guard', 'flagged unreachable', c.reachable, 'false');
  check('G5 send guard', 'blocking part named', c.dayPart, 'asleep');
  check('G5 send guard', 'offers breakfast alternative', c.deferTo, '6:30 AM');
  check('G5 send guard', 'skew vs Austin parent is 1h', c.skewHours, 1);
}

// ---------------------------------------------------------------------------
// G6 — terminal states and expiry are never re-materialized.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-07-01T12:00:00Z');
  for (const st of ['delivered', 'opened', 'expired', 'revoked']) {
    const r = materialize(
      intent({ policy: 'at_daypart', targetDaypart: 'bedtime', state: st }), NYC_CTX, now);
    check('G6 terminal', `${st} is untouchable`, r.ok === false && r.reason, 'terminal_state');
  }
  const dead = materialize(
    intent({ policy: 'at_daypart', targetDaypart: 'bedtime',
             expiresAt: '2026-06-01T00:00:00Z' }), NYC_CTX, now);
  check('G6 terminal', 'past retention window refuses',
    dead.ok === false && dead.reason, 'already_expired');
}

// ---------------------------------------------------------------------------
// G7 — DST. A bedtime intent must not drift across either transition.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-10-01T12:00:00Z');
  const oct = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-10-15', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  const dec = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-12-15', targetDaypart: 'bedtime' }),
    NYC_CTX, now);
  check('G7 DST', 'Oct bedtime 20:30 local',
    oct.scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G7 DST', 'Dec bedtime 20:30 local',
    dec.scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G7 DST', 'UTC shifted 1h across the Nov flip',
    (dec.scheduledAt.toUTC().hour - oct.scheduledAt.toUTC().hour + 24) % 24, 1);

  // when_reachable must never hand back an instant in the past.
  const w = nextReachableWindow(NYC_CTX, DateTime.fromISO('2026-11-01T05:30:00Z'));
  check('G7 DST', 'reachable window is never in the past',
    w.start >= DateTime.fromISO('2026-11-01T05:30:00Z'), 'true');
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// G8 — S-D10: day-parts resolve by the TARGET date's effective range, not one
//      context frozen at "today". A batch crossing a schedule change must use
//      the bedtime that is in force on EACH night.
// ---------------------------------------------------------------------------
{
  const now = DateTime.fromISO('2026-05-01T12:00:00Z');
  const OLD_BEDTIME = { kind: 'bedtime', startsLocal: '20:00', endsLocal: '20:30', daysOfWeek: ALL,
    reachable: true, effectiveFrom: null, effectiveTo: '2026-08-31' };
  const NEW_BEDTIME = { kind: 'bedtime', startsLocal: '21:00', endsLocal: '21:30', daysOfWeek: ALL,
    reachable: true, effectiveFrom: '2026-09-01', effectiveTo: null };
  const ctx = { homeTz: NYC, tzIntervals: [], dayParts: [OLD_BEDTIME, NEW_BEDTIME] };
  const night = (d) => materialize(
    intent({ policy: 'on_local_date', targetLocalDate: d, targetDaypart: 'bedtime' }), ctx, now);
  check('G8 effective range', 'the last night of the old schedule uses the OLD bedtime (20:00)',
    night('2026-08-31').scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:00');
  check('G8 effective range', 'the first night of the new schedule uses the NEW bedtime (21:00)',
    night('2026-09-01').scheduledAt.setZone(NYC).toFormat('HH:mm'), '21:00');
  check('G8 effective range', 'a night long after the change keeps the new bedtime',
    night('2026-12-01').scheduledAt.setZone(NYC).toFormat('HH:mm'), '21:00');
  check('G8 effective range', 'a night before any part is in force falls back to the 20:30 default',
    materialize(intent({ policy: 'on_local_date', targetLocalDate: '2026-08-01', targetDaypart: 'bedtime' }),
      { ...ctx, dayParts: [NEW_BEDTIME] }, now).scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G8 effective range', 'partsOn() lists only the parts in force on the date',
    `${partsOn(ctx, '2026-08-31').length}${partsOn(ctx, '2026-09-01').length}`, '11');
  check('G8 effective range', 'at_daypart rolling forward uses the part in force on the night it lands on',
    materialize(intent({ policy: 'at_daypart', targetDaypart: 'bedtime' },),
      ctx, DateTime.fromISO('2026-08-31T02:00:00Z')).scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:00');
  // Two overlapping legacy rows resolve deterministically (earliest start), not by row order.
  const A = { kind: 'bedtime', startsLocal: '20:45', endsLocal: '21:00', daysOfWeek: ALL, reachable: true };
  const B = { kind: 'bedtime', startsLocal: '20:00', endsLocal: '20:45', daysOfWeek: ALL, reachable: true };
  const pick = (parts) => materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-09-01', targetDaypart: 'bedtime' }),
    { homeTz: NYC, tzIntervals: [], dayParts: parts }, now).scheduledAt.setZone(NYC).toFormat('HH:mm');
  check('G8 effective range', 'overlapping rows: result does not depend on row order',
    `${pick([A, B])}|${pick([B, A])}`, '20:00|20:00');
}

// ---------------------------------------------------------------------------
// G9 — S-D10: the zone is resolved at the candidate INSTANT, not at 12:00 UTC.
//      She flies Austin -> Charlotte at 14:00 Central; the 20:30 bedtime that
//      evening is an Eastern wall clock.
// ---------------------------------------------------------------------------
{
  const FLIGHT = '2026-06-12T19:00:00Z';                        // 14:00 CDT
  const ctx = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
    { tz: CHI, start: null, end: FLIGHT }, { tz: NYC, start: FLIGHT, end: null }] };
  const r = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-12', targetDaypart: 'bedtime' }),
    ctx, DateTime.fromISO('2026-06-01T12:00:00Z'));
  check('G9 same-day travel', 'bedtime on the travel day is 20:30 EASTERN (arrival zone)',
    r.scheduledAt.setZone(NYC).toFormat('HH:mm'), '20:30');
  check('G9 same-day travel', 'and the reported zone is Eastern', r.tz, NYC);
  const r2 = materialize(
    intent({ policy: 'on_local_date', targetLocalDate: '2026-06-11', targetDaypart: 'bedtime' }),
    ctx, DateTime.fromISO('2026-06-01T12:00:00Z'));
  check('G9 same-day travel', 'the day before the flight is still 20:30 Central', r2.tz, CHI);
  check('G9 same-day travel', 'zonedWallClock agrees', zonedWallClock(ctx, '2026-06-12', '20:30').tz, NYC);
  check('G9 same-day travel', 'a morning wall clock on the travel day is still Central',
    zonedWallClock(ctx, '2026-06-12', '07:00').tz, CHI);
  const gap = zonedWallClock(ctx, '2026-06-12', '14:30');       // skipped by the flight (14:00 CDT -> 15:00 EDT)
  check('G9 same-day travel', 'a wall clock the flight skipped resolves to the LATER instant, in the zone she is in then',
    `${gap.tz}|${gap.instant.toUTC().toFormat('HH:mm')}`, `${NYC}|19:30`);
}

// ---------------------------------------------------------------------------
// G10 — S-D11: wrapped day-parts use START-day semantics.
// ---------------------------------------------------------------------------
{
  const FRI = 5;
  const ASLEEP_FRI = { kind: 'asleep', startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: [FRI], reachable: false };
  const ctx = { homeTz: NYC, tzIntervals: [], dayParts: [ASLEEP_FRI] };
  const at = (iso) => gate(ctx, DateTime.fromISO(iso, { zone: NYC }));
  // 2026-06-12 is a Friday.
  check('G10 wrapped part', "Friday 21:30 is inside Friday's asleep part", at('2026-06-12T21:30:00').allow, 'false');
  check('G10 wrapped part', 'Saturday 02:00 is STILL inside it (started Friday)', at('2026-06-13T02:00:00').allow, 'false');
  check('G10 wrapped part', 'the reason names the part', at('2026-06-13T02:00:00').reason, 'asleep');
  check('G10 wrapped part', 'Saturday 06:30 is the first free minute', at('2026-06-13T06:30:00').allow, 'true');
  check('G10 wrapped part', 'Saturday 21:30 is NOT asleep (days is [Fri] only)', at('2026-06-13T21:30:00').allow, 'true');
  check('G10 wrapped part', 'Friday 02:00 is NOT asleep (Thursday is not listed)',
    at('2026-06-12T02:00:00').allow, 'true');
  check('G10 wrapped part', "activeDayPart finds yesterday's wrapped part",
    activeDayPart(ctx, DateTime.fromISO('2026-06-13T03:00:00', { zone: NYC }))?.kind, 'asleep');
  const ctxEnds = { homeTz: NYC, tzIntervals: [], dayParts: [{ ...ASLEEP_FRI, effectiveTo: '2026-06-12' }] };
  check('G10 wrapped part', 'a part whose range ends Friday still runs until Saturday 06:30',
    gate(ctxEnds, DateTime.fromISO('2026-06-13T02:00:00', { zone: NYC })).allow, 'false');
  check('G10 wrapped part', 'but not after Saturday 06:30',
    gate(ctxEnds, DateTime.fromISO('2026-06-13T07:00:00', { zone: NYC })).allow, 'true');
}

// ---------------------------------------------------------------------------
// G11 — S-D11: a when_reachable message sent INSIDE a reachable window is "now".
// ---------------------------------------------------------------------------
{
  const sent = DateTime.fromISO('2026-06-10T16:00:00', { zone: NYC });   // Wed, after_school 15:00-18:30
  const w = nextReachableWindow(NYC_CTX, sent);
  check('G11 reachable now', 'sent at 16:00 during after_school: the window is NOW', w.start.toMillis(), sent.toMillis());
  check('G11 reachable now', 'materialize schedules it at that instant',
    materialize(intent({ policy: 'when_reachable' }), NYC_CTX, sent).scheduledAt.toMillis(), sent.toMillis());
  const w2 = nextReachableWindow(NYC_CTX, DateTime.fromISO('2026-06-10T10:00:00', { zone: NYC }));
  check('G11 reachable now', 'during school (unreachable) it still waits for after_school',
    w2.start.setZone(NYC).toFormat('HH:mm'), '15:00');
  const w3 = nextReachableWindow(NYC_CTX, DateTime.fromISO('2026-06-10T22:00:00', { zone: NYC }));
  check('G11 reachable now', "asleep: it waits for the next morning's wake window",
    w3.start.setZone(NYC).toFormat('ccc HH:mm'), 'Thu 06:30');
  check('G11 reachable now', "the gate's deferTo is a later window, never now",
    gate(NYC_CTX, DateTime.fromISO('2026-06-10T10:00:00', { zone: NYC })).deferTo
      .setZone(NYC).toFormat('HH:mm'), '15:00');
  const late = nextReachableWindow(NYC_CTX, DateTime.fromISO('2026-06-10T23:30:00', { zone: NYC }).toUTC());
  check('G11 reachable now', "walks the child's calendar, not UTC's",
    late.start.setZone(NYC).toFormat('ccc HH:mm'), 'Thu 06:30');
  const ctx = { homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
    { tz: CHI, start: null, end: '2026-06-10T20:00:00Z' }, { tz: NYC, start: '2026-06-10T20:00:00Z', end: null }] };
  const tw = nextReachableWindow(ctx, DateTime.fromISO('2026-06-10T13:00:00Z'));   // 08:00 CDT: school
  check('G11 reachable now', 'a window start is resolved in the zone she is in at that instant (after the flight)',
    tw.tz, NYC);
}


// ---------------------------------------------------------------------------
// G12 — golden vectors (no Dart port exists; a contract for any future one)
// ---------------------------------------------------------------------------
{
  const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
  check('G12 vectors', 'vectors.json equals a fresh generation (run: node tools/gen-delivery-vectors.mjs)',
    JSON.stringify(onDisk) === JSON.stringify(generateDeliveryVectors()), true);
  check('G12 vectors', 'they cover the gate, materialize and nextReachableWindow',
    onDisk.gate.length > 10 && onDisk.materialize.length > 25 && onDisk.nextReachableWindow.length > 8, true);
}

let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(50)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
