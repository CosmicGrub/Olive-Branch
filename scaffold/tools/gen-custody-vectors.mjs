// Generates packages/custody/test/vectors.json: golden inputs and the outputs the
// TypeScript engine (packages/custody/src/schedule.ts) gives for them. The Dart
// port (client/lib/exchange_screen.dart) is tested against the SAME file
// (client/test/custody_vectors_test.dart), so the two implementations cannot
// drift apart silently — S-D7 (new-year holiday windows) and S-D8/S-D9 are
// exactly the kind of rule that did drift. The TS suite asserts this file equals
// a fresh generation, so editing the engine without regenerating fails CI.
//
// Only the pure, zone-free parts of schedule.ts are vectored: that is all the
// Dart port carries (it has no timezone database). The instant-based wrapper
// sideAtInstant() is covered by the TS tests; its pure core sideAtOrderLocal()
// is what is vectored.
//
// usage: node tools/gen-custody-vectors.mjs            (writes the file)
//        node tools/gen-custody-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import { DateTime } from 'luxon';
import { patternSideOn, sideOn, blocks, sleepsUntilSideChange, sideAtOrderLocal }
  from '../packages/custody/src/schedule.mjs';

const NYC = 'America/New_York';
const XMAS = { name: 'Christmas', startMonthDay: '12-24', endMonthDay: '12-26', evenYearSide: 'A', priority: 10 };
const THANKS = { name: 'Thanksgiving', startMonthDay: '11-26', endMonthDay: '11-29', evenYearSide: 'B', priority: 10 };
const NEWYEAR = { name: 'New Year', startMonthDay: '12-31', endMonthDay: '01-02', evenYearSide: 'B', priority: 10 };
const XMAS_DAY = { name: 'Christmas Day', startMonthDay: '12-25', endMonthDay: '12-25', evenYearSide: 'B', priority: 20 };
const LONG_WINTER = { name: 'Winter', startMonthDay: '12-20', endMonthDay: '02-29', evenYearSide: 'A', priority: 5 };

const order = (o = {}) => ({
  pattern: '2-2-3', orderTz: NYC, anchorLocalDate: '2026-01-05', exchangeTime: '18:00',
  holidays: [XMAS, THANKS, NEWYEAR], effectiveFrom: '2020-01-01', effectiveTo: null, ...o,
});

const addDays = (iso, n) => DateTime.fromISO(iso, { zone: 'utc' }).plus({ days: n }).toISODate();

/** The 14-day cycle of an order, read back out of the engine (so the vector
 *  carries it and the Dart port does not need the pattern-name table). */
const cycleOf = (o) => Array.from({ length: 14 }, (_, i) => patternSideOn(o, addDays(o.anchorLocalDate, i)));
const withCycle = (o) => ({ ...o, cycle: cycleOf(o) });

export function generate() {
  const out = {};

  const orders = {
    plain: order({ holidays: [] }),
    holidays: order(),
    newYearOnly: order({ holidays: [NEWYEAR] }),
    stacked: order({ holidays: [XMAS, XMAS_DAY, NEWYEAR] }),
    longWinter: order({ holidays: [LONG_WINTER] }),
    alternating: order({ pattern: 'alternating_weeks', holidays: [] }),
    ends: order({ holidays: [], effectiveTo: '2026-01-06' }),
    endsLater: order({ holidays: [], effectiveTo: '2026-01-10' }),
    starts: order({ holidays: [], effectiveFrom: '2026-01-07' }),
    successorA: order({ holidays: [], pattern: 'alternating_weeks', effectiveFrom: '2026-01-07', anchorLocalDate: '2026-01-07' }),
    successorB: order({ holidays: [], pattern: 'alternating_weeks', effectiveFrom: '2026-01-07', anchorLocalDate: '2025-12-31' }),
    successorLate: order({ holidays: [], effectiveFrom: '2026-01-20' }),
  };
  out.orders = Object.fromEntries(Object.entries(orders).map(([k, o]) => [k, withCycle(o)]));

  // sideOn over a spread of dates, including every new-year boundary day.
  const dates = [
    '2025-12-30', '2025-12-31', '2026-01-01', '2026-01-02', '2026-01-03', '2026-01-05', '2026-01-07', '2026-01-19',
    '2026-02-15', '2026-02-28', '2026-11-26', '2026-11-29', '2026-11-30', '2026-12-20', '2026-12-24', '2026-12-25',
    '2026-12-26', '2026-12-27', '2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02', '2027-01-03', '2027-02-15',
    '2027-12-24', '2027-12-25', '2027-12-31', '2028-01-01', '2028-01-02', '2028-02-29', '2028-03-01',
  ];
  out.sideOn = [];
  for (const name of ['plain', 'holidays', 'newYearOnly', 'stacked', 'longWinter', 'alternating']) {
    for (const d of dates) {
      const s = sideOn(orders[name], d);
      out.sideOn.push({ order: name, date: d, expect: { side: s.side, source: s.source, holidayName: s.holidayName ?? null } });
    }
  }

  // blocks over ranges (effectiveFrom/effectiveTo clipping included).
  const ranges = [
    ['holidays', '2026-12-20', '2027-01-06'],
    ['newYearOnly', '2026-12-29', '2027-01-04'],
    ['plain', '2026-01-05', '2026-01-31'],
    ['alternating', '2026-01-05', '2026-02-08'],
    ['ends', '2026-01-01', '2026-01-12'],
    ['starts', '2026-01-01', '2026-01-12'],
  ];
  out.blocks = ranges.map(([name, from, to]) => ({
    order: name, from, to,
    expect: blocks(orders[name], from, to).map(b => ({
      side: b.side, start: b.startLocalDate, end: b.endLocalDate, source: b.source, holidayName: b.holidayName ?? null,
    })),
  }));

  // "N sleeps" — incl. stopping at effectiveTo and the successor order's side.
  const sl = [
    ['plain', '2026-01-05', null], ['plain', '2026-01-07', null], ['alternating', '2026-01-05', null],
    ['holidays', '2026-12-23', null], ['newYearOnly', '2026-12-30', null],
    ['ends', '2026-01-05', null], ['ends', '2026-01-05', 'successorA'], ['ends', '2026-01-05', 'successorB'],
    ['ends', '2026-01-05', 'successorLate'], ['endsLater', '2026-01-05', null], ['endsLater', '2026-01-09', 'successorB'],
  ];
  out.sleeps = sl.map(([name, today, succ]) => {
    const r = sleepsUntilSideChange(orders[name], today, 60, succ ? orders[succ] : null);
    return { order: name, today, successor: succ, expect: r ? { sleeps: r.sleeps, nextSide: r.nextSide, onLocalDate: r.onLocalDate } : null };
  });

  // side at a wall-clock moment of the order zone (the pure core).
  const moments = [
    ['plain', '2026-01-06', '09:00'], ['plain', '2026-01-07', '00:00'], ['plain', '2026-01-07', '10:00'],
    ['plain', '2026-01-07', '17:59'], ['plain', '2026-01-07', '18:00'], ['plain', '2026-01-07', '23:59'],
    ['plain', '2026-01-08', '17:59'], ['plain', '2026-01-09', '17:59'], ['plain', '2026-01-09', '18:00'],
    ['holidays', '2026-12-24', '09:00'], ['holidays', '2026-12-24', '18:00'], ['holidays', '2026-12-27', '09:00'],
    ['holidays', '2026-12-27', '18:00'], ['newYearOnly', '2026-12-31', '17:59'], ['newYearOnly', '2026-12-31', '18:00'],
    ['newYearOnly', '2027-01-01', '09:00'], ['newYearOnly', '2027-01-03', '09:00'], ['newYearOnly', '2027-01-03', '18:00'],
    ['ends', '2026-01-06', '23:59'], ['ends', '2026-01-07', '09:00'], ['starts', '2026-01-06', '23:00'],
    ['starts', '2026-01-07', '09:00'], ['starts', '2026-01-07', '18:00'],
  ];
  out.sideAtOrderLocal = moments.map(([name, date, hhmm]) => {
    const r = sideAtOrderLocal(orders[name], date, hhmm);
    return { order: name, date, hhmm, expect: r ? { side: r.side, source: r.source, holidayName: r.holidayName ?? null } : null };
  });

  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-custody-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/custody/test/vectors.json', import.meta.url), text); console.log('wrote packages/custody/test/vectors.json', text.length, 'bytes'); }
}
