// Generates packages/delivery-engine/test/vectors.json: golden inputs and the
// outputs the TypeScript engine (materialize.ts, gate.ts) gives for them — the
// day-part gate, materialize() for every policy, and nextReachableWindow(),
// including the S-D10/S-D11 rules (effective ranges by target date, same-day
// travel zones, wrapped parts with start-day semantics, "now" inside a reachable
// window).
//
// There is NO Dart port of the gate/materialiser: the client deliberately does
// no zone maths (guardian_home.dart: "All times arrive pre-rendered from /now
// and /ribbon"). These vectors are the contract any future port — or a second
// implementation of the sweep — must satisfy, and the TS suite fails CI if the
// engine changes without them being regenerated.
//
// usage: node tools/gen-delivery-vectors.mjs            (writes the file)
//        node tools/gen-delivery-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import { DateTime } from 'luxon';
import { materialize, nextReachableWindow } from '../packages/delivery-engine/src/materialize.mjs';
import { gate } from '../packages/delivery-engine/src/gate.mjs';

const NYC = 'America/New_York', CHI = 'America/Chicago';
const ALL = [0, 1, 2, 3, 4, 5, 6];
const DAYPARTS = [
  { kind: 'asleep', startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: ALL, reachable: false },
  { kind: 'wake', startsLocal: '06:30', endsLocal: '08:00', daysOfWeek: ALL, reachable: true },
  { kind: 'school', startsLocal: '08:00', endsLocal: '15:00', daysOfWeek: [1, 2, 3, 4, 5], reachable: false },
  { kind: 'after_school', startsLocal: '15:00', endsLocal: '18:30', daysOfWeek: ALL, reachable: true },
  { kind: 'dinner', startsLocal: '18:30', endsLocal: '19:30', daysOfWeek: ALL, reachable: true },
  { kind: 'bedtime', startsLocal: '20:30', endsLocal: '21:00', daysOfWeek: ALL, reachable: true },
];
const FLIGHT = '2026-06-12T19:00:00Z';

const ctxs = {
  nyc: { homeTz: NYC, tzIntervals: [], dayParts: DAYPARTS },
  summerInTexas: {
    homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
      { tz: NYC, start: null, end: '2026-06-12T22:00:00Z' },
      { tz: CHI, start: '2026-06-12T22:00:00Z', end: '2026-07-25T22:00:00Z' },
      { tz: NYC, start: '2026-07-25T22:00:00Z', end: null }],
  },
  sameDayFlight: {
    homeTz: NYC, dayParts: DAYPARTS, tzIntervals: [
      { tz: CHI, start: null, end: FLIGHT }, { tz: NYC, start: FLIGHT, end: null }],
  },
  scheduleChange: {
    homeTz: NYC, tzIntervals: [], dayParts: [
      { kind: 'bedtime', startsLocal: '20:00', endsLocal: '20:30', daysOfWeek: ALL, reachable: true, effectiveFrom: null, effectiveTo: '2026-08-31' },
      { kind: 'bedtime', startsLocal: '21:00', endsLocal: '21:30', daysOfWeek: ALL, reachable: true, effectiveFrom: '2026-09-01', effectiveTo: null }],
  },
  asleepFridayOnly: {
    homeTz: NYC, tzIntervals: [], dayParts: [
      { kind: 'asleep', startsLocal: '21:00', endsLocal: '06:30', daysOfWeek: [5], reachable: false }],
  },
};

const iso = (dt) => (dt ? dt.toUTC().toISO() : null);
const fmt = (r) => (r.ok
  ? { ok: true, scheduledAt: iso(r.scheduledAt), tz: r.tz, anomaly: r.anomaly, rolled: r.rolled }
  : { ok: false, reason: r.reason });

export function generate() {
  const out = { ctxs };

  const gateAt = [
    ['nyc', '2026-06-10T10:00:00', NYC], ['nyc', '2026-06-10T16:00:00', NYC], ['nyc', '2026-06-10T22:00:00', NYC],
    ['nyc', '2026-06-13T10:00:00', NYC], ['nyc', '2026-06-10T06:29:00', NYC], ['nyc', '2026-06-10T06:30:00', NYC],
    ['asleepFridayOnly', '2026-06-12T21:30:00', NYC], ['asleepFridayOnly', '2026-06-13T02:00:00', NYC],
    ['asleepFridayOnly', '2026-06-13T06:30:00', NYC], ['asleepFridayOnly', '2026-06-13T21:30:00', NYC],
    ['asleepFridayOnly', '2026-06-12T02:00:00', NYC],
  ];
  out.gate = gateAt.flatMap(([c, local, zone]) => ['normal', 'emergency'].map((priority) => {
    const g = gate(ctxs[c], DateTime.fromISO(local, { zone }), priority);
    return { ctx: c, local, zone, priority,
      expect: { allow: g.allow, reason: g.reason ?? null, deferTo: iso(g.deferTo), deferCount: g.deferCount ?? null } };
  }));
  out.gateDeferCap = [0, 1, 2, 3, 4].map((n) => {
    const g = gate(ctxs.nyc, DateTime.fromISO('2026-06-10T10:00:00', { zone: NYC }), 'normal', n);
    return { deferCount: n, expect: { allow: g.allow, reason: g.reason ?? null, deferCount: g.deferCount ?? null } };
  });

  const base = { id: 'i', childId: 'c', state: 'pending', expiresAt: '2030-01-01T00:00:00Z' };
  const NOW = '2026-05-01T12:00:00Z';
  const mats = [
    ['nyc', { policy: 'immediate' }, NOW],
    ['nyc', { policy: 'at_instant', targetInstant: '2026-06-01T12:00:00Z' }, NOW],
    ['nyc', { policy: 'at_instant', targetInstant: '2026-04-01T12:00:00Z' }, NOW],
    ['nyc', { policy: 'at_instant', targetInstant: '2026-05-01T10:30:00Z' }, NOW],
    ['nyc', { policy: 'at_daypart', targetDaypart: 'bedtime' }, '2026-06-10T14:00:00Z'],
    ['nyc', { policy: 'at_daypart', targetDaypart: 'bedtime' }, '2026-06-11T03:00:00Z'],
    ['nyc', { policy: 'at_daypart', targetDaypart: 'bedtime', targetLocalDate: '2026-06-01' }, '2026-06-10T14:00:00Z'],
    ['nyc', { policy: 'at_daypart', targetDaypart: 'nonexistent_kind' }, NOW],
    ['nyc', { policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }, NOW],
    ['nyc', { policy: 'on_local_date', targetLocalDate: '2026-04-01', targetDaypart: 'bedtime' }, NOW],
    ['nyc', { policy: 'on_local_date', targetLocalDate: '2026-11-01', targetDaypart: 'bedtime' }, NOW],
    ['nyc', { policy: 'on_local_date', targetLocalDate: '2026-03-08', targetDaypart: 'bedtime' }, '2026-02-01T00:00:00Z'],
    ['nyc', { policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'nope' }, NOW],
    ['nyc', { policy: 'when_reachable' }, '2026-06-10T20:00:00Z'],          // 16:00 NYC, inside after_school
    ['nyc', { policy: 'when_reachable' }, '2026-06-10T14:00:00Z'],          // 10:00 NYC, in school
    ['nyc', { policy: 'when_reachable' }, '2026-06-11T02:00:00Z'],          // 22:00 NYC, asleep
    ['nyc', { policy: 'on_event', targetEventId: 'x' }, NOW],
    ['nyc', { policy: 'immediate', state: 'delivered' }, NOW],
    ['nyc', { policy: 'immediate', expiresAt: '2026-04-30T00:00:00Z' }, NOW],
    ['summerInTexas', { policy: 'on_local_date', targetLocalDate: '2026-06-01', targetDaypart: 'bedtime' }, NOW],
    ['summerInTexas', { policy: 'on_local_date', targetLocalDate: '2026-07-01', targetDaypart: 'bedtime' }, NOW],
    ['summerInTexas', { policy: 'on_local_date', targetLocalDate: '2026-08-01', targetDaypart: 'bedtime' }, NOW],
    ['sameDayFlight', { policy: 'on_local_date', targetLocalDate: '2026-06-11', targetDaypart: 'bedtime' }, '2026-06-01T12:00:00Z'],
    ['sameDayFlight', { policy: 'on_local_date', targetLocalDate: '2026-06-12', targetDaypart: 'bedtime' }, '2026-06-01T12:00:00Z'],
    ['sameDayFlight', { policy: 'on_local_date', targetLocalDate: '2026-06-13', targetDaypart: 'bedtime' }, '2026-06-01T12:00:00Z'],
    ['scheduleChange', { policy: 'on_local_date', targetLocalDate: '2026-08-31', targetDaypart: 'bedtime' }, NOW],
    ['scheduleChange', { policy: 'on_local_date', targetLocalDate: '2026-09-01', targetDaypart: 'bedtime' }, NOW],
    ['scheduleChange', { policy: 'on_local_date', targetLocalDate: '2026-12-25', targetDaypart: 'bedtime' }, NOW],
    ['scheduleChange', { policy: 'at_daypart', targetDaypart: 'bedtime' }, '2026-08-31T02:00:00Z'],
    ['scheduleChange', { policy: 'at_daypart', targetDaypart: 'bedtime' }, '2026-09-01T02:00:00Z'],
  ];
  out.materialize = mats.map(([c, intent, now]) => ({
    ctx: c, intent: { ...base, ...intent }, now,
    expect: fmt(materialize({ ...base, ...intent }, ctxs[c], DateTime.fromISO(now, { zone: 'utc' }))),
  }));

  const windows = [
    ['nyc', '2026-06-10T16:00:00', NYC], ['nyc', '2026-06-10T10:00:00', NYC], ['nyc', '2026-06-10T22:00:00', NYC],
    ['nyc', '2026-06-10T23:30:00', NYC], ['nyc', '2026-06-12T16:00:00', NYC], ['nyc', '2026-06-13T10:00:00', NYC],
    ['nyc', '2026-11-01T01:30:00', NYC], ['nyc', '2026-03-08T01:59:00', NYC],
    ['summerInTexas', '2026-06-20T10:00:00', CHI], ['sameDayFlight', '2026-06-12T08:00:00', CHI],
    ['asleepFridayOnly', '2026-06-13T02:00:00', NYC],
  ];
  out.nextReachableWindow = windows.map(([c, local, zone]) => {
    const from = DateTime.fromISO(local, { zone });
    const w = nextReachableWindow(ctxs[c], from);
    return { ctx: c, from: iso(from), expect: w ? { start: iso(w.start), tz: w.tz, anomaly: w.anomaly } : null };
  });

  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-delivery-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/delivery-engine/test/vectors.json', import.meta.url), text); console.log('wrote packages/delivery-engine/test/vectors.json', text.length, 'bytes'); }
}
