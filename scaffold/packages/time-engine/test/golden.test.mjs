/**
 * MASTERFILE §4.6 — the six mandatory golden fixtures.
 * These catch nearly every time bug the product can ship.
 *
 * Zero-dependency runner so this executes anywhere node does.
 *   node test/golden.test.mjs
 */
import { DateTime } from 'luxon';
import {
  resolveZone, resolveWallClock, offsetBetween, enumerateLocalDates,
} from '../src/time.mjs';

let pass = 0, fail = 0;
const results = [];

function check(fixture, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  results.push({ fixture, name, ok, actual: String(actual), expected: String(expected) });
}

const CHI = 'America/Chicago';
const NYC = 'America/New_York';
const PHX = 'America/Phoenix';
const ELP = 'America/Denver';      // El Paso & Hudspeth counties, TX

// ---------------------------------------------------------------------------
// F1 — Spring forward. 2:30 AM on 8 Mar 2026 does not exist in America/New_York.
// ---------------------------------------------------------------------------
{
  const r = resolveWallClock('2026-03-08', '02:30', NYC);
  check('F1 spring-forward', 'anomaly reported', r.anomaly, 'nonexistent');
  check('F1 spring-forward', 'shifted forward to 03:30 EDT',
    r.instant.toFormat('HH:mm ZZZZ'), '03:30 EDT');

  // A bedtime delivery on that date must be unaffected — 20:30 is nowhere near
  // the gap. This is the regression that matters in production.
  const bed = resolveWallClock('2026-03-08', '20:30', NYC);
  check('F1 spring-forward', 'bedtime unaffected', bed.anomaly, 'none');
  check('F1 spring-forward', 'bedtime still 8:30 PM local',
    bed.instant.toFormat('HH:mm'), '20:30');
}

// ---------------------------------------------------------------------------
// F2 — Fall back. 1:30 AM on 1 Nov 2026 occurs twice in America/New_York.
// ---------------------------------------------------------------------------
{
  const first = resolveWallClock('2026-11-01', '01:30', NYC, 'first');
  const last  = resolveWallClock('2026-11-01', '01:30', NYC, 'last');
  check('F2 fall-back', 'anomaly reported', first.anomaly, 'ambiguous');
  check('F2 fall-back', 'first occurrence is EDT',
    first.instant.toFormat('ZZZZ'), 'EDT');
  check('F2 fall-back', 'last occurrence is EST',
    last.instant.toFormat('ZZZZ'), 'EST');
  check('F2 fall-back', 'the two are one hour apart',
    (last.instant.toMillis() - first.instant.toMillis()) / 3600000, 1);

  const bed = resolveWallClock('2026-11-01', '20:30', NYC);
  check('F2 fall-back', 'bedtime unaffected', bed.anomaly, 'none');
}

// ---------------------------------------------------------------------------
// F3 — Chicago <-> Phoenix. Gap is 1h in winter, 2h in summer, because Arizona
//      does not observe DST. Hardcoding "1 hour" ships a bug half the year.
// ---------------------------------------------------------------------------
{
  const jan = DateTime.fromISO('2026-01-15T18:00', { zone: 'utc' });
  const jul = DateTime.fromISO('2026-07-15T18:00', { zone: 'utc' });
  check('F3 Chicago/Phoenix', 'winter gap is 1h', offsetBetween(CHI, PHX, jan), 1);
  check('F3 Chicago/Phoenix', 'summer gap is 2h', offsetBetween(CHI, PHX, jul), 2);
  check('F3 Chicago/Phoenix', 'gap is NOT constant',
    offsetBetween(CHI, PHX, jan) !== offsetBetween(CHI, PHX, jul), 'true');
}

// ---------------------------------------------------------------------------
// F4 — El Paso. Texas is Central EXCEPT El Paso and Hudspeth counties, which
//      are Mountain. Never infer a zone from a state.
// ---------------------------------------------------------------------------
{
  const t = DateTime.fromISO('2026-07-15T18:00', { zone: 'utc' });
  check('F4 El Paso', 'El Paso is one hour behind the rest of Texas',
    offsetBetween(CHI, ELP, t), 1);
  check('F4 El Paso', 'El Paso vs Charlotte is two hours',
    offsetBetween(NYC, ELP, t), 2);
}

// ---------------------------------------------------------------------------
// F5 — Summer TX<->NC handoff. The child's zone flips AT THE EXCHANGE EVENT,
//      not at midnight. A bedtime video on either side of the handoff must
//      resolve in the correct zone.
// ---------------------------------------------------------------------------
{
  const intervals = [
    { tz: NYC, start: null,                   end: '2026-06-12T22:00:00Z' },  // school year
    { tz: CHI, start: '2026-06-12T22:00:00Z', end: '2026-07-25T22:00:00Z' },  // summer in TX
    { tz: NYC, start: '2026-07-25T22:00:00Z', end: null                   },
  ];
  const before = DateTime.fromISO('2026-06-12T12:00:00Z');
  const after  = DateTime.fromISO('2026-06-13T12:00:00Z');

  check('F5 TX/NC handoff', 'before exchange the child is Eastern',
    resolveZone(intervals, before, NYC), NYC);
  check('F5 TX/NC handoff', 'after exchange the child is Central',
    resolveZone(intervals, after, CHI), CHI);

  // Same nominal bedtime, two different absolute instants.
  const bedNC = resolveWallClock('2026-06-11', '20:30', NYC).instant;
  const bedTX = resolveWallClock('2026-06-13', '20:30', CHI).instant;
  check('F5 TX/NC handoff', 'bedtime is 20:30 local on BOTH sides',
    `${bedNC.toFormat('HH:mm')}/${bedTX.toFormat('HH:mm')}`, '20:30/20:30');
  check('F5 TX/NC handoff', 'but the UTC instants differ by the zone gap',
    bedNC.toUTC().toFormat('HH:mm') !== bedTX.toUTC().toFormat('HH:mm'), 'true');

  // Unknown instant falls back rather than throwing.
  check('F5 TX/NC handoff', 'empty timeline falls back to home_tz',
    resolveZone([], before, NYC), NYC);
}

// ---------------------------------------------------------------------------
// F6 — A 180-night banked batch spanning BOTH DST transitions. One stale batch
//      can mis-deliver every night of a deployment window.
// ---------------------------------------------------------------------------
{
  const dates = enumerateLocalDates('2026-09-01', '2027-02-28', 'daily');
  check('F6 banked batch', 'night count', dates.length, 181);

  let drifted = 0, anomalies = 0;
  for (const d of dates) {
    const r = resolveWallClock(d, '20:30', NYC);
    if (r.anomaly !== 'none') anomalies++;
    if (r.instant.toFormat('HH:mm') !== '20:30') drifted++;
  }
  check('F6 banked batch', 'ZERO nights drift off 8:30 PM local', drifted, 0);
  check('F6 banked batch', 'no DST anomalies at bedtime', anomalies, 0);

  // The UTC instants MUST shift by an hour across the November transition —
  // that is the proof the wall clock was held, not the offset.
  const oct = resolveWallClock('2026-10-15', '20:30', NYC).instant.toUTC();
  const dec = resolveWallClock('2026-12-15', '20:30', NYC).instant.toUTC();
  check('F6 banked batch', 'UTC shifts 1h across the Nov transition',
    (dec.hour - oct.hour + 24) % 24, 1);

  // Weekday cadence must skip weekends.
  const wd = enumerateLocalDates('2026-09-01', '2026-09-14', 'weekdays');
  check('F6 banked batch', 'weekday cadence skips weekends', wd.length, 10);
}

// ---------------------------------------------------------------------------

const width = Math.max(...results.map(r => r.fixture.length));
let current = '';
for (const r of results) {
  if (r.fixture !== current) { current = r.fixture; console.log(`\n${current}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(46)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
