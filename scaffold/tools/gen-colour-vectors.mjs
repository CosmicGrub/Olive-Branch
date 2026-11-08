// Generates packages/palette/test/colour_day_vectors.json: golden inputs and the outputs the
// TypeScript module (packages/palette/src/colour_day.ts) gives for them. The Dart port
// (client/lib/colour_day_logic.dart) is tested against the SAME file, and the TS suite fails
// if the file is stale, so neither implementation can drift without CI noticing.
//
// usage: node tools/gen-colour-vectors.mjs            (writes the file)
//        node tools/gen-colour-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import * as C from '../packages/palette/src/colour_day.mjs';

const NOW = 1_700_000_000_000;
const row = (localDate, colourId, chosenBy, override, chosenAtMs) => ({ localDate, colourId, chosenBy, override, chosenAtMs });
const kid = (d, c, t) => row(d, c, 'child', false, t);
const mum = (d, c, t) => row(d, c, 'guardian', true, t);

export function generate() {
  const out = {};

  out.constants = {
    artStyles: C.ART_STYLES, pixelMinAge: C.PIXEL_MIN_AGE, defaultArtStyle: C.DEFAULT_ART_STYLE,
    defaultArtSettings: C.DEFAULT_ART_SETTINGS, colourIds: C.COLOUR_IDS,
    maxAnswerAgeMs: C.MAX_ANSWER_AGE_MS, maxClockSkewMs: C.MAX_CLOCK_SKEW_MS, windDownChoices: C.WIND_DOWN_CHOICES,
  };

  out.stylesForAge = [null, 0, 5, 7, 8, 9, 12].map((age) => ({ age, styles: C.stylesForAge(age) }));

  const cur = C.DEFAULT_ART_SETTINGS;
  const artPatches = [
    [{ artStyle: 'watercolour' }, 6], [{ artStyle: 'pixel' }, 6], [{ artStyle: 'pixel', allowedStyles: ['pixel', 'line'] }, 8],
    [{ artStyle: 'pixel', allowedStyles: ['pixel', 'line'] }, 7], [{ allowedStyles: ['line'] }, 6], [{ allowedStyles: ['line', 'felt'], artStyle: 'felt' }, 6],
    [{ allowedStyles: ['felt', 'line', 'felt'] }, 6], [{ allowedStyles: [] }, 6], [{ allowedStyles: 'paper' }, 6], [{ allowedStyles: ['neon'] }, 6],
    [{ artStyle: 'neon' }, 6], [{ artStyle: 5 }, 6], [{ dailyQuestion: false }, 6], [{ dailyQuestion: 'no' }, 6],
    [{ codeActivities: false, dailyQuestion: false }, null], [{ codeActivities: 1 }, 6], [{ mood: 'x' }, 6], [{}, 6], [null, 6], [[], 6], ['x', 6],
    [{ allowedStyles: ['sticker', 'paper'] }, 6], [{ artStyle: 'line' }, null],
  ];
  out.artPatches = artPatches.map(([patch, age]) => ({ patch, age, expect: C.mergeArtSettings(cur, patch, age) }));
  const narrowed = { ...cur, artStyle: 'line', allowedStyles: ['line', 'felt'] };
  out.artPatchesFromNarrow = [[{ artStyle: 'paper' }, 6], [{ artStyle: 'felt' }, 6], [{ allowedStyles: ['felt'] }, 6]]
    .map(([patch, age]) => ({ current: narrowed, patch, age, expect: C.mergeArtSettings(narrowed, patch, age) }));

  const answered = [undefined, null, 'x', NaN, 'NaN', NOW, NOW - 1, NOW + 1, NOW + C.MAX_CLOCK_SKEW_MS, NOW + C.MAX_CLOCK_SKEW_MS + 1,
    NOW - C.MAX_ANSWER_AGE_MS, NOW - C.MAX_ANSWER_AGE_MS - 1, NOW - 5000.7, 0, -5];
  out.clamp = answered.map((a) => ({ answered: a === undefined ? '__undefined__' : a === null ? null : (typeof a === 'number' && Number.isNaN(a)) ? '__nan__' : a, nowMs: NOW,
    expect: C.clampAnsweredAt(a === undefined ? undefined : a, NOW) }));

  out.localDates = ['2026-11-07', '2026-02-29', '2024-02-29', '2026-13-01', '2026-1-1', '', 5, null, '2026-11-07T00:00']
    .map((s) => ({ s, expect: C.isLocalDate(s) }));

  const D = '2026-11-07';
  const merges = [
    ['first answer', null, kid(D, 'sea', 100)],
    ['later device wins', kid(D, 'sea', 100), kid(D, 'sunny', 200)],
    ['earlier device is kept out', kid(D, 'sea', 200), kid(D, 'sunny', 100)],
    ['tie goes to the incoming write', kid(D, 'sea', 100), kid(D, 'sunny', 100)],
    ['same colour again changes nothing', kid(D, 'sea', 100), kid(D, 'sea', 150)],
    ['colour day over her answer', kid(D, 'sea', 900), mum(D, 'mint', 100)],
    ['colour day when nothing yet', null, mum(D, 'mint', 100)],
    ['her tap does not replace a colour day', mum(D, 'mint', 100), kid(D, 'sea', 900)],
    ['later colour day replaces earlier', mum(D, 'mint', 100), mum(D, 'grape', 200)],
    ['earlier colour day does not replace later', mum(D, 'grape', 200), mum(D, 'mint', 100)],
    ['unknown colour', null, kid(D, 'red', 1)],
    ['pure red is not a swatch', kid(D, 'sea', 1), mum(D, '#FF0000', 2)],
    ['wrong day', kid('2026-11-06', 'sea', 1), kid(D, 'sea', 2)],
    ['child cannot claim override', null, row(D, 'sea', 'child', true, 1)],
    ['guardian without override flag', null, row(D, 'sea', 'guardian', false, 1)],
    ['bad date', null, kid('2026-13-40', 'sea', 1)],
    ['bad time', null, kid(D, 'sea', NaN)],
    ['bad actor', null, row(D, 'sea', 'sitter', false, 1)],
  ];
  out.merge = merges.map(([name, existing, incoming]) => ({ name, existing, incoming,
    expect: JSON.parse(JSON.stringify(C.mergeDay(existing, incoming), (_k, v) => (typeof v === 'number' && !Number.isFinite(v) ? 'NaN' : v))) }));
  // NaN cannot be written in JSON; the one case that uses it spells it as a string and the Dart runner maps it back.
  for (const m of out.merge) if (m.incoming && Number.isNaN(m.incoming.chosenAtMs)) m.incoming = { ...m.incoming, chosenAtMs: 'NaN' };

  const days = [kid('2026-11-05', 'grass', 10), kid('2026-11-06', 'storm', 20), kid('2026-11-06', 'sky', 30), kid('2026-11-07', 'sea', 40)];
  out.days = days;
  out.currentDay = [[], days, days.slice(0, 2), [days[1], days[2]], [mum('2026-11-07', 'mint', 1), kid('2026-11-07', 'sea', 5)]]
    .map((d) => ({ days: d, expect: C.currentDay(d) }));
  out.colourToday = [['2026-11-07', days], ['2026-11-08', days], ['2026-11-06', days], ['2026-11-04', days], ['2026-11-07', []]]
    .map(([localDate, d]) => ({ days: d, localDate, expect: C.colourToday(d, localDate) }));
  out.needsQuestion = [['2026-11-07', days, true], ['2026-11-08', days, true], ['2026-11-08', days, false], ['2026-11-07', [], true], ['2026-11-07', [mum('2026-11-07', 'mint', 1)], true]]
    .map(([localDate, d, on]) => ({ days: d, localDate, dailyQuestion: on, expect: C.needsQuestion(d, localDate, on) }));
  out.deviceMatches = [
    ['2026-11-07', days, { localDate: '2026-11-07', colourId: 'sea' }], ['2026-11-07', days, { localDate: '2026-11-06', colourId: 'sky' }],
    ['2026-11-07', days, null], ['2026-11-07', [], { localDate: '2026-11-07', colourId: 'sea' }], ['2026-11-08', days, { localDate: '2026-11-07', colourId: 'sea' }],
  ].map(([localDate, d, seen]) => ({ days: d, localDate, seen, expect: C.deviceMatches(d, localDate, seen) }));
  out.toChoices = [[], days, [days[3], days[0]]].map((d) => ({ days: d, expect: C.toChoices(d) }));
  out.guardianView = [['2026-11-07', days], ['2026-11-07', days.slice(0, 2)], ['2026-11-06', days], ['2026-11-07', []], ['2026-11-07', [kid('2026-11-06', 'sea', 1), kid('2026-11-07', 'sea', 2)]], ['2026-11-07', [mum('2026-11-07', 'mint', 5)]]]
    .map(([localDate, d]) => ({ days: d, localDate, expect: C.guardianView(d, localDate) }));

  const w = (o = 930, r = 1140, d = 30) => ({ opensMin: o, restsMin: r, windDownMin: d });
  const windows = [w(), w(0, 1439, 0), w(0, 15, 0), w(0, 30, 15), w(0, 44, 30), w(0, 45, 30), w(600, 600, 0), w(700, 600, 0), w(-1, 600, 0), w(0, 1440, 0), w(0, 600, 10),
    w(1.5, 600, 0), { opensMin: '0', restsMin: 600, windDownMin: 0 }, { opensMin: 0, restsMin: 600 }, { ...w(), mood: 'x' }, null, [], 'x'];
  out.checkWindow = windows.map((x) => ({ input: x, expect: C.checkPlayWindow(x) }));
  const real = w();
  out.windowState = [0, 929, 930, 1000, 1109, 1110, 1111, 1139, 1140, 1141, 1439].map((m) => ({ window: real, minute: m, expect: C.playWindowState(real, m) }))
    .concat([w(930, 1140, 0)].flatMap((ww) => [1139, 1140].map((m) => ({ window: ww, minute: m, expect: C.playWindowState(ww, m) }))))
    .concat([{ window: null, minute: 5, expect: C.playWindowState(null, 5) }]);
  out.windowLength = [real, w(0, 1439, 0), w(600, 615, 0)].map((ww) => ({ window: ww, expect: C.windowLength(ww) }));
  out.isLonger = [[real, w(900, 1140, 30)], [real, w(930, 1200, 30)], [real, w(960, 1140, 30)], [real, w(930, 1110, 30)], [real, w(930, 1140, 15)], [null, real], [real, real]]
    .map(([a, b]) => ({ prev: a, next: b, expect: C.isLonger(a, b) }));
  out.lines = ['open', 'winding_down', 'resting'].map((s) => ({ state: s, expect: C.playWindowLine(s) }));

  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-colour-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/palette/test/colour_day_vectors.json', import.meta.url), text); console.log('wrote packages/palette/test/colour_day_vectors.json', text.length, 'bytes'); }
}
