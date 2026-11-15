/**
 * Family-sim day plan: the seeded day-parts must not depend on the hour the suite runs.
 * No database, no wall clock: the clock is a fixed instant swept across a whole UTC day.
 *
 * Regression for the CI failure "A flow: family 3: a message banks" (400 daypart_undefined) that
 * only happened when the run landed within ~10 minutes before a family's LOCAL midnight (for
 * Europe/Stockholm in winter: 21:56-22:05 UTC). The seeder skipped a part that crossed local
 * midnight, so that child had no bedtime. Run: node tools/family-sim/test/dayplan_clock.test.mjs
 */
import { DateTime } from 'luxon';
import { materialize } from '../../../packages/delivery-engine/src/materialize.mjs';
import { dayPlan, dayPartRows } from '../lib/seed.mjs';
import { buildFamilies } from '../lib/families.mjs';

let pass = 0, fail = 0; const bad = [];
const check = (name, ok) => { ok ? pass++ : (fail++, bad.push(name)); };
// the sweep is ~317k minute-level probes; each probe kind is rolled up to one assertion per zone and
// day (failing minutes are still named) so the suite total stays readable
const roll = new Map();
const probe = (key, tag, ok) => { const r = roll.get(key) || { n: 0, bad: [] }; r.n++; if (!ok) r.bad.push(tag); roll.set(key, r); };

const zones = [...new Set(buildFamilies(10).map((f) => f.tz))];
// a plain winter day, both DST changes in the northern hemisphere, and the southern ones
const days = [[2026, 11, 14], [2026, 3, 8], [2026, 3, 29], [2026, 10, 25], [2026, 11, 1], [2026, 4, 5], [2026, 9, 27]];
const KINDS = ['after_school', 'dinner', 'wind_down', 'bedtime'];
const wrapsMidnight = (r) => r[1] > r[2];
let wrapped = 0, stockholmWrapMinutes = [];

for (const tz of zones) for (const [y, mo, d] of days) for (let minute = 0; minute < 1440; minute++) {
  const t = Date.UTC(y, mo - 1, d, 0, minute);
  const plan = dayPlan(t - 60000, 600000);        // exactly what isolation_ci.test.mjs uses
  const rows = dayPartRows(plan, tz);
  const tag = `${tz} ${y}-${mo}-${d} ${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}Z`;
  probe(`${tz} ${y}-${mo}-${d}: all four parts are seeded`, tag, KINDS.every((k) => rows.some((r) => r[0] === k)));
  probe(`${tz} ${y}-${mo}-${d}: no empty range`, tag, rows.every((r) => r[1] !== r[2]));
  if (rows.some(wrapsMidnight)) {
    wrapped++;
    if (tz === 'Europe/Stockholm' && y === 2026 && mo === 11) stockholmWrapMinutes.push(minute);
  }
  const plain = y === 2026 && mo === 11 && d === 14;
  const parts = rows.map(([kind, startsLocal, endsLocal, reachable]) =>
    ({ kind, startsLocal, endsLocal, reachable, daysOfWeek: [0, 1, 2, 3, 4, 5, 6] }));
  const now = DateTime.fromMillis(t, { zone: 'utc' });
  const r = materialize({ id: 'p', childId: 'c', state: 'pending', policy: 'at_daypart', targetDaypart: 'bedtime',
    expiresAt: now.plus({ days: 97 }).toISO() }, { homeTz: tz, tzIntervals: [], dayParts: parts }, now);
  probe(`${tz} ${y}-${mo}-${d}: bedtime can be banked`, `${tag} (${r.ok ? '' : r.reason})`, r.ok);
  // the bedtime of this plan starts ~54 minutes from now. On a DST-change day a wall clock inside the
  // repeated/skipped hour is legitimately resolved to another instant (rolled a day), so only the plain day is exact.
  if (r.ok && plain) probe(`${tz} ${y}-${mo}-${d}: bedtime lands within the next two hours`, tag,
    r.scheduledAt.toMillis() >= t && r.scheduledAt.toMillis() <= t + 2 * 3600000);
}

for (const [key, r] of roll) check(r.bad.length ? `${key} -> ${r.bad.slice(0, 3).join('; ')}` : key, r.bad.length === 0);
check('the sweep really exercised the midnight-straddling case', wrapped > 0 && stockholmWrapMinutes.length > 0);
// the exact CI failure: Stockholm, 21:56Z on a November day, is 22:56 local; bedtime is 23:50 -> 00:00
check('CI repro (Stockholm 21:56Z) seeds a wrapped bedtime',
  stockholmWrapMinutes.includes(21 * 60 + 56));

// verify.sh reads exactly "<n> passed, <n> failed" at the start of a line
console.log(`${pass} passed, ${fail} failed`);
if (fail) { console.log(bad.slice(0, 20).join('\n')); process.exit(1); }
