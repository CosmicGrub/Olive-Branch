// Generates packages/family-structure/test/vectors.json: golden inputs and the outputs the
// TypeScript module (packages/family-structure/src/family.ts) gives for them. The Dart port
// (client/lib/family_structure_logic.dart) is tested against this file, and the TS test fails if
// it is stale, so neither side can drift without the other noticing.
//
// usage: node tools/gen-family-vectors.mjs            (writes the file)
//        node tools/gen-family-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import * as F from '../packages/family-structure/src/family.mjs';

const home = (id, name, childSleeps = true) => ({ id, name, childSleeps });
const person = (id, label, role, homeId, contact, away = null) => ({ id, label, role, homeId, contact, away });

export const FAMILY = {
  ...F.emptyStructure(),
  homes: [home('h1', "Mom's house"), home('h2', "Dad's house")],
  people: [
    person('p1', 'Mom', 'guardian', 'h1', ['live_call', 'message']),
    person('p2', 'Dad', 'guardian', 'h2', ['live_call', 'message']),
    person('p3', 'Dana', 'step_parent', 'h2', ['message']),
    person('p4', 'Grandma', 'relative', null, ['live_call', 'postcard'], { until: null }),
    person('p5', 'Sue', 'sitter', 'h1', ['message']),
    person('p6', 'Dr Kim', 'therapist', null, ['live_call']),
    person('p7', '', 'trusted_adult', 'h1', ['message']),
  ],
  rhythm: { pattern: 'alternating_weeks', exchangeDay: 0, exchangeTime: '18:00', source: 'guardian' },
};
const FOSTER = {
  ...F.emptyStructure(),
  homes: [home('h1', 'My house')],
  people: [person('p1', 'Aunt Jo', 'foster_parent', 'h1', ['live_call', 'supervised_visit', 'voice_line']),
    person('p2', 'Mr Lee', 'caseworker', null, ['message'])],
};
const SINGLE = { ...F.emptyStructure(), homes: [home('h1', 'Home')], people: [person('p1', 'Mum', 'guardian', 'h1', ['live_call'])] };

const lad = (y) => F.rungsAt(y);
const principals = [
  ['guardian', { roleName: 'guardian', userId: 'g1', childId: null }],
  ['guardian no id', { roleName: 'guardian', userId: '', childId: null }],
  ['child', { roleName: 'child', userId: null, childId: 'c1' }],
  ['sitter', { roleName: 'sitter', userId: 's1', childId: null }],
  ['step_parent', { roleName: 'step_parent', userId: 'x1', childId: null }],
  ['trusted_adult', { roleName: 'trusted_adult', userId: 't1', childId: null }],
  ['coordinator', { roleName: 'coordinator', userId: 'k1', childId: null }],
  ['system', { roleName: 'system', userId: null, childId: null }],
];

const ops = {
  addDana: { op: 'put_person', person: person('p9', 'Dana', 'step_parent', 'h2', ['message']) },
  relabel: { op: 'put_person', person: person('p3', 'Dani', 'step_parent', 'h2', ['message']) },
  moveHome: { op: 'put_person', person: person('p3', 'Dana', 'step_parent', 'h1', ['message']) },
  rmDana: { op: 'remove_person', personId: 'p3' },
  rhythm: { op: 'set_rhythm', rhythm: { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00', source: 'guardian' } },
  courtRhythm: { op: 'set_rhythm', rhythm: { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00', source: 'court_order' } },
  badTime: { op: 'set_rhythm', rhythm: { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '25:00', source: 'guardian' } },
  addHome: { op: 'put_home', home: home('h3', 'Grandma\'s', false) },
  rmHome: { op: 'remove_home', homeId: 'h2' },
  band: { op: 'set_area_band', area: 'reading', band: 't812' },
  badBand: { op: 'set_area_band', area: 'reading', band: 't99' },
  badArea: { op: 'set_area_band', area: 'weather', band: 't57' },
  birthday: { op: 'set_birthday_visible', visible: false },
  hold: { op: 'set_band_hold', hold: false },
  release: { op: 'release_band', band: 't812' },
  junk: { op: 'rm_rf' },
  extraKey: { op: 'remove_person', personId: 'p3', note: 'x'.repeat(50) },
};

export function generate() {
  const noRungs = [];
  const views = [];
  const viewCase = (name, structure, band, suites, rungs, opts) =>
    views.push({ name, structure, band, suites, rungs, opts: opts ?? {}, out: F.deriveChildView(structure, band, suites, rungs, opts ?? {}) });
  for (const b of F.AGE_BANDS) viewCase(`family at ${b}`, FAMILY, b, {}, lad(b === 't13' ? 13 : b === 't812' ? 9 : 6));
  viewCase('empty at t57', F.emptyStructure(), 't57', {}, noRungs);
  viewCase('foster at t57 (helpers, visits, no role words)', FOSTER, 't57', {}, noRungs);
  viewCase('single home at t57 (no weeks)', SINGLE, 't57', {}, noRungs);
  viewCase('suites off at t57', FAMILY, 't57', { messages: false, games: false, stories: false, showTell: false, homework: false, myList: false, myPeople: false }, noRungs);
  viewCase('suites off but own_list rung held (permanent)', FAMILY, 't812', { myList: false }, lad(10));
  viewCase('calls suite off at t34 (no hero)', FAMILY, 't34', { calls: false }, noRungs);
  viewCase('reading override up at t57', { ...FAMILY, areaBands: { reading: 't812' } }, 't57', {}, noRungs);
  viewCase('games override down at t812', { ...FAMILY, areaBands: { games: 't34' } }, 't812', {}, lad(9));
  viewCase('birthday hidden', { ...FAMILY, birthdayVisible: false }, 't57', {}, noRungs);
  viewCase('away ended before today', FAMILY, 't57', {}, noRungs, { today: '2026-11-07' });
  viewCase('away with a future end', { ...FAMILY, people: FAMILY.people.map((p) => (p.id === 'p4' ? { ...p, away: { until: '2027-01-01' } } : p)) }, 't57', {}, noRungs, { today: '2026-11-07' });
  viewCase('away ended (until passed)', { ...FAMILY, people: FAMILY.people.map((p) => (p.id === 'p4' ? { ...p, away: { until: '2026-01-01' } } : p)) }, 't57', {}, noRungs, { today: '2026-11-07' });
  viewCase('junk band fails closed to the youngest', FAMILY, 'x', {}, noRungs);
  for (const y of [0, 5, 10, 13, 15, 18]) viewCase(`rungs at ${y} years`, FAMILY, F.bandForYears(y), {}, lad(y));

  const entries = [
    { entry: 'change', id: 'c1', seq: 1, op: F.withBefore(FAMILY, ops.addDana), timing: { kind: 'now' } },
    { entry: 'change', id: 'c2', seq: 2, op: F.withBefore(FAMILY, ops.rhythm), timing: { kind: 'hold' } },
    { entry: 'change', id: 'c3', seq: 3, op: F.withBefore(FAMILY, ops.band), timing: { kind: 'date', on: '2026-11-21' } },
    { entry: 'change', id: 'c4', seq: 4, op: F.withBefore(FAMILY, ops.rmDana), timing: { kind: 'hold' } },
    { entry: 'release', id: 'r1', seq: 5, ref: 'c4' },
  ];
  const folds = ['2026-11-07', '2026-11-20', '2026-11-21', '2026-12-31'].map((today) => ({
    today,
    entries,
    released: F.foldReleased(FAMILY, entries, today),
    intended: F.foldIntended(FAMILY, entries),
    releasedIds: [...F.releasedIds(entries, today)].sort(),
    pending: F.pendingChanges(entries, today).map((e) => e.id),
  }));
  const noRelease = entries.slice(0, 4);
  folds.push({ today: '2026-11-07', entries: noRelease, released: F.foldReleased(FAMILY, noRelease, '2026-11-07'),
    intended: F.foldIntended(FAMILY, noRelease), releasedIds: [...F.releasedIds(noRelease, '2026-11-07')].sort(),
    pending: F.pendingChanges(noRelease, '2026-11-07').map((e) => e.id) });

  const timing = [
    { raw: { kind: 'now' } }, { raw: { kind: 'hold' } }, { raw: { kind: 'date', on: '2026-11-08' } },
    { raw: { kind: 'date', on: '2026-11-07' } }, { raw: { kind: 'date', on: '2026-11-06' } },
    { raw: { kind: 'date', on: '2028-11-08' } }, { raw: { kind: 'date', on: '2027-02-30' } },
    { raw: { kind: 'date' } }, { raw: { kind: 'now', on: '2026-11-08' } }, { raw: { kind: 'later' } },
    { raw: 'now' }, { raw: null }, { raw: [] },
  ].map((c) => ({ ...c, today: '2026-11-07', out: F.parseTiming(c.raw, '2026-11-07') }));

  const opCases = Object.entries(ops).map(([name, op]) => ({
    name, op, structure: FAMILY, verdict: F.validateOp(FAMILY, op),
    big: F.validateOp(FAMILY, op).ok ? F.isBigChange(F.withBefore(FAMILY, op)) : null,
    recommended: F.validateOp(FAMILY, op).ok ? F.defaultTiming(F.withBefore(FAMILY, op)) : null,
    applied: F.validateOp(FAMILY, op).ok ? F.applyOp(FAMILY, F.withBefore(FAMILY, op)) : null,
    inverse: F.validateOp(FAMILY, op).ok ? F.invertOp(F.withBefore(FAMILY, op), F.applyOp(FAMILY, F.withBefore(FAMILY, op))) : null,
  }));
  // a court-ordered rhythm refuses an edit
  const locked = { ...FAMILY, rhythm: { pattern: '2-2-3', exchangeDay: 5, exchangeTime: '17:00', source: 'court_order' } };
  opCases.push({ name: 'rhythm while locked by order', op: ops.rhythm, structure: locked, verdict: F.validateOp(locked, ops.rhythm), big: null, recommended: null, applied: null, inverse: null });
  // limits
  const fullHomes = { ...FAMILY, homes: [home('a', 'A'), home('b', 'B'), home('c', 'C'), home('d', 'D')], people: [] };
  opCases.push({ name: 'a fifth home', op: { op: 'put_home', home: home('e', 'E') }, structure: fullHomes, verdict: F.validateOp(fullHomes, { op: 'put_home', home: home('e', 'E') }), big: null, recommended: null, applied: null, inverse: null });
  const manyPeople = { ...FAMILY, people: Array.from({ length: 24 }, (_, i) => person(`x${i}`, `P${i}`, 'relative', null, [])) };
  opCases.push({ name: 'a 25th person', op: { op: 'put_person', person: person('new', 'N', 'relative', null, []) }, structure: manyPeople, verdict: F.validateOp(manyPeople, { op: 'put_person', person: person('new', 'N', 'relative', null, []) }), big: null, recommended: null, applied: null, inverse: null });
  const personCases = [
    ['good', person('a', 'Ok', 'relative', null, [])],
    ['label too long', person('a', 'x'.repeat(31), 'relative', null, [])],
    ['label with a control char', person('a', 'a\u0007b', 'relative', null, [])],
    ['unknown role', person('a', 'Ok', 'overlord', null, [])],
    ['unknown contact', person('a', 'Ok', 'relative', null, ['telepathy'])],
    ['duplicate contact', person('a', 'Ok', 'relative', null, ['message', 'message'])],
    ['unknown home', person('a', 'Ok', 'relative', 'nope', [])],
    ['bad away date', person('a', 'Ok', 'relative', null, [], { until: '2026-02-30' })],
    ['bad id', person('a b', 'Ok', 'relative', null, [])],
    ['extra field', { ...person('a', 'Ok', 'relative', null, []), age: 4 }],
  ].map(([name, p]) => ({ name, person: p, homes: FAMILY.homes, verdict: F.validatePerson(p, FAMILY.homes) }));

  const stories = [
    ['one page', { pages: ['Some weeks you sleep at Mom\'s.'] }], ['no pages', { pages: [] }],
    ['seven pages', { pages: Array(7).fill('a') }], ['page too long', { pages: ['x'.repeat(241)] }],
    ['blank page', { pages: ['  '] }], ['not a string', { pages: [3] }], ['extra key', { pages: ['a'], generated: true }],
    ['null', null],
  ].map(([name, s]) => ({ name, story: s, verdict: F.validateStory(s) }));

  const birthdays = [
    ['2019-04-02', '2026-11-07'], ['2019-12-09', '2026-11-07'], ['2019-11-07', '2026-11-07'],
    ['2019-11-08', '2026-11-07'], ['2018-12-09', '2026-11-07'], ['2020-02-29', '2027-02-20'],
    ['2020-02-29', '2028-02-28'], ['2014-11-20', '2026-11-07'], ['2008-11-10', '2026-11-07'],
    ['2026-11-07', '2026-11-07'], ['2027-01-01', '2026-11-07'], ['nope', '2026-11-07'],
  ].map(([b, t]) => {
    const info = F.birthdayInfo(b, t);
    return { birthDate: b, today: t, info, line: info ? F.birthdayLineShown(info.sleepsUntil, true) : null,
      lineHidden: info ? F.birthdayLineShown(info.sleepsUntil, false) : null,
      preview: info ? F.birthdayPreview(info, true, info.bandNow) : null,
      previewNoHold: info ? F.birthdayPreview(info, false, info.bandNow) : null };
  });

  const effective = [];
  for (const n of F.AGE_BANDS) for (const r of [...F.AGE_BANDS, null]) for (const h of [true, false])
    effective.push({ natural: n, released: r, hold: h, out: F.effectiveBand(n, h, r) });

  return {
    bandTable: F.BAND_TABLE,
    constants: { maxHomes: F.MAX_HOMES, maxPeople: F.MAX_PEOPLE, maxLabel: F.MAX_LABEL, maxHomeName: F.MAX_HOME_NAME,
      maxStoryPages: F.MAX_STORY_PAGES, maxStoryPageChars: F.MAX_STORY_PAGE_CHARS, maxDateAheadDays: F.MAX_DATE_AHEAD_DAYS,
      storyShownDays: F.STORY_SHOWN_DAYS, farPlaceName: F.FAR_PLACE_NAME, rungAges: F.RUNG_AGES,
      roles: F.ROLES, backgroundRoles: F.BACKGROUND_ROLES, contactModes: F.CONTACT_MODES, patterns: F.PATTERNS,
      areas: F.AREAS, bands: F.AGE_BANDS, tileKeys: F.TILE_KEYS, suiteKeys: F.SUITE_KEYS },
    bandForYears: [-1, 0, 2, 3, 4, 5, 7, 8, 12, 13, 17, 18, 40, 5.9, null, 'x', NaN]
      .map((y) => ({ years: y === null ? '__null__' : Number.isNaN(y) ? '__nan__' : y, out: F.bandForYears(y) })),
    effectiveBand: effective,
    rungsAt: [0, 9, 10, 12, 13, 14, 15, 16, 17, 18, 30, null].map((y) => ({ years: y === null ? '__null__' : y, out: F.rungsAt(y) })),
    views,
    structures: { family: FAMILY, foster: FOSTER, single: SINGLE, locked },
    canEdit: principals.map(([name, p]) => ({ name, principal: p, edit: F.canEditStructure(p), read: F.canReadReleased(p, 'c1'), readOther: F.canReadReleased(p, 'c2') })),
    ops: opCases,
    persons: personCases,
    timing,
    folds,
    stories,
    birthdays,
    diffs: [['t34', 't57'], ['t57', 't812'], ['t812', 't13'], ['t57', 't57']].map(([a, b]) => ({ from: a, to: b, out: F.diffBands(a, b) })),
    preview: (() => {
      const r = F.previewChange(FAMILY, ops.addDana, { kind: 'hold' }, 't57', {}, [], '2026-11-07');
      return { op: ops.addDana, timing: { kind: 'hold' }, band: 't57', today: '2026-11-07', out: r };
    })(),
  };
}

if (process.argv[1] && process.argv[1].endsWith('gen-family-vectors.mjs')) {
  const json = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(json);
  else {
    writeFileSync(new URL('../packages/family-structure/test/vectors.json', import.meta.url), json);
    console.log('wrote packages/family-structure/test/vectors.json');
  }
}
