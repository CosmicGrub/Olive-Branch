// Generates packages/care/test/vectors.json: golden inputs and the outputs the
// TypeScript engine (packages/care/src/care.ts) gives for them — the medication
// safety rules (S-D6: slot validation, double-dose guard, PRN minimum gap and
// maximum per 24 h) and prnAllowed. The Dart port (client/lib/meds_care.dart) is
// tested against the SAME file (client/test/care_vectors_test.dart), so the
// server and the offline client cannot disagree about whether a dose is safe.
// The care suite asserts this file equals a fresh generation.
//
// `atLocal` (a zone-abbreviated clock string) is generated but not asserted by
// the Dart port, which has no timezone database; `by` is.
//
// usage: node tools/gen-care-vectors.mjs            (writes the file)
//        node tools/gen-care-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import { DateTime } from 'luxon';
import { checkDose, prnAllowed } from '../packages/care/src/care.mjs';

const NYC = 'America/New_York';
const T0 = DateTime.fromISO('2026-03-10T08:00:00', { zone: NYC });
const iso = (dt) => dt.toUTC().toISO();   // always '...Z'

const rec = (slot, dt, status = 'given', by = 'Dad', med = 'm') => ({
  medicationId: med, localDate: dt.toISODate(), slot, administeredAt: iso(dt), localTz: NYC, byUserName: by, status,
});
const SCHED = { slots: ['morning', 'evening'], isPrn: false, minGapHours: null, maxPer24h: null };
const prn = (o = {}) => ({ slots: ['prn'], isPrn: true, minGapHours: 4, maxPer24h: null, ...o });
const h = (n) => T0.plus({ hours: n });
const five = [0, 4, 8, 12, 16].map(n => rec('prn', h(n)));

export function generate() {
  const out = {};
  const cases = [
    // [label, med, slot, status, at, history]
    ['unknown slot', SCHED, 'lunch', 'given', T0, []],
    ['empty slot', SCHED, '   ', 'given', T0, []],
    ['unknown slot, skipped', SCHED, 'lunch', 'skipped', T0, []],
    ['case normalised', SCHED, 'Morning', 'given', T0, []],
    ['space trimmed', SCHED, '  EVENING ', 'given', T0, []],
    ['no slots', { ...SCHED, slots: [] }, 'morning', 'given', T0, []],
    ['double dose, odd case', SCHED, 'MORNING', 'given', h(1), [rec('morning', T0)]],
    ['other slot free', SCHED, 'evening', 'given', h(10), [rec('morning', T0)]],
    ['next day free', SCHED, 'morning', 'given', T0.plus({ days: 1 }), [rec('morning', T0)]],
    ['skipped does not consume', SCHED, 'morning', 'given', T0, [rec('morning', T0, 'skipped')]],
    ['refused after given', SCHED, 'morning', 'refused', h(1), [rec('morning', T0)]],
    ['prn inside gap', prn(), 'prn', 'given', h(3), [rec('prn', T0)]],
    ['prn at gap', prn(), 'prn', 'given', h(4), [rec('prn', T0)]],
    ['prn one minute short', prn(), 'prn', 'given', h(4).minus({ minutes: 1 }), [rec('prn', T0)]],
    ['prn after gap', prn(), 'prn', 'given', h(5), [rec('prn', T0)]],
    ['prn back-dated inside gap', prn(), 'prn', 'given', h(-2), [rec('prn', T0)]],
    ['prn skipped no clock', prn(), 'prn', 'given', h(1), [rec('prn', T0, 'skipped')]],
    ['prn no gap configured', prn({ minGapHours: null }), 'prn', 'given', T0.plus({ minutes: 1 }), [rec('prn', T0)]],
    ['prn refused never trips gap', prn(), 'prn', 'refused', h(1), [rec('prn', T0)]],
    ['prn latest dose in the way', prn(), 'prn', 'given', h(5), [rec('prn', T0), rec('prn', h(4))]],
    ['prn fifth of five', prn({ maxPer24h: 5 }), 'prn', 'given', h(16), five.slice(0, 4)],
    ['prn sixth refused', prn({ maxPer24h: 5 }), 'prn', 'given', h(20), five],
    ['prn window rolled', prn({ maxPer24h: 5 }), 'prn', 'given', h(24), five],
    ['prn back-dated overfills later window', prn({ maxPer24h: 5, minGapHours: 1 }), 'prn', 'given', h(-2), five],
    ['prn old violation not a lock', prn({ maxPer24h: 2, minGapHours: 1 }), 'prn', 'given', T0.plus({ days: 3 }), five],
    ['prn skipped not counted', prn({ maxPer24h: 1, minGapHours: null }), 'prn', 'given', h(1), [rec('prn', T0, 'skipped')]],
  ];
  out.checkDose = cases.map(([label, med, slot, status, at, history]) => ({
    label, med, slot, status, at: iso(at), localDate: at.toISODate(), history,
    expect: checkDose(med, slot, status, at, at.toISODate(), history),
  }));

  const prnCases = [
    [[], 'm', T0, 4], [[rec('prn', T0)], 'm', h(2), 4], [[rec('prn', T0)], 'm', h(5), 4],
    [[rec('prn', T0, 'refused')], 'm', h(1), 4], [[rec('prn', h(1))], 'm', T0, 4],
    [[rec('prn', T0, 'given', 'Dad', 'other')], 'm', T0, 4], [[rec('prn', T0)], 'm', h(4), 4],
  ];
  out.prnAllowed = prnCases.map(([existing, medicationId, at, gap]) => ({
    existing, medicationId, at: iso(at), minGapHours: gap, expect: prnAllowed(existing, medicationId, at, gap),
  }));
  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-care-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/care/test/vectors.json', import.meta.url), text); console.log('wrote packages/care/test/vectors.json', text.length, 'bytes'); }
}
