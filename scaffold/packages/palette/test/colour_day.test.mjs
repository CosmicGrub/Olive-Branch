/**
 * palette/colour_day — colour of the day: the sync rule, art-style settings and
 * the play window. MASTERFILE §8.6.5, §8.6.6. Design: the "one question a day,
 * latest wins, all her devices agree" rule from the colour-of-the-day mockups.
 *
 * Every deny path is a real assertion; hostile inputs are named for what they
 * are. The golden-vector drift guard at the end holds the Dart port honest.
 */
import {
  ART_STYLES, PIXEL_MIN_AGE, DEFAULT_ART_SETTINGS, COLOUR_IDS, MAX_ANSWER_AGE_MS, MAX_CLOCK_SKEW_MS,
  WIND_DOWN_CHOICES, DAY_FORBIDDEN_KEYS,
  stylesForAge, mergeArtSettings, clampAnsweredAt, isLocalDate, mergeDay, currentDay, colourToday,
  needsQuestion, deviceMatches, toChoices, guardianView, checkPlayWindow, playWindowState,
  windowLength, isLonger, playWindowLine,
} from '../src/colour_day.mjs';
import { PALETTE, auditColourPayload } from '../src/palette.mjs';
import { readFileSync } from 'node:fs';
import { generate } from '../../../tools/gen-colour-vectors.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const j = (o) => JSON.stringify(o);

const D = '2026-11-07';
const kid = (d, c, t) => ({ localDate: d, colourId: c, chosenBy: 'child', override: false, chosenAtMs: t });
const mum = (d, c, t) => ({ localDate: d, colourId: c, chosenBy: 'guardian', override: true, chosenAtMs: t });
const reason = (r) => (r.ok ? 'OK' : r.reason);

// ---- A · the colour ids ----------------------------------------------------
{
  const g = 'A colour ids';
  check(g, 'the twelve swatches, in palette order', j(COLOUR_IDS), j(PALETTE.map((s) => s.id)));
  check(g, 'exactly twelve', COLOUR_IDS.length, 12);
  check(g, 'no pure red to choose', COLOUR_IDS.includes('red'), false);
}

// ---- B · art styles --------------------------------------------------------
{
  const g = 'B art styles';
  check(g, 'seven styles', ART_STYLES.length, 7);
  check(g, 'pixel unlocks at 8', PIXEL_MIN_AGE, 8);
  check(g, 'a 7-year-old has no pixel', stylesForAge(7).includes('pixel'), false);
  check(g, 'an 8-year-old has pixel', stylesForAge(8).includes('pixel'), true);
  check(g, 'unknown age is treated as young', stylesForAge(null).includes('pixel'), false);
  check(g, 'defaults: paper, six styles, no pixel', j(DEFAULT_ART_SETTINGS.allowedStyles), j(['paper', 'sticker', 'crayon', 'watercolour', 'felt', 'line']));
  const cur = DEFAULT_ART_SETTINGS;
  const r = mergeArtSettings(cur, { artStyle: 'watercolour' }, 6);
  check(g, 'a guardian picks watercolour', r.ok && r.settings.artStyle, 'watercolour');
  check(g, 'the defaults object is never mutated', cur.artStyle, 'paper');
  check(g, 'pixel is refused under 8', reason(mergeArtSettings(cur, { artStyle: 'pixel' }, 6)), 'style_not_for_age');
  check(g, 'pixel needs to be allowed too', reason(mergeArtSettings(cur, { artStyle: 'pixel' }, 9)), 'style_not_allowed');
  check(g, 'pixel works at 8 with both set', reason(mergeArtSettings(cur, { artStyle: 'pixel', allowedStyles: ['pixel', 'line'] }, 8)), 'OK');
  check(g, 'pixel in the allowed list is refused under 8', reason(mergeArtSettings(cur, { artStyle: 'line', allowedStyles: ['pixel', 'line'] }, 7)), 'style_not_for_age');
  check(g, 'unknown age cannot unlock pixel', reason(mergeArtSettings(cur, { artStyle: 'pixel', allowedStyles: ['pixel'] }, null)), 'style_not_for_age');
  check(g, 'the default style must stay in the allowed list', reason(mergeArtSettings(cur, { allowedStyles: ['line'] }, 6)), 'style_not_allowed');
  check(g, 'allowed list is stored in canonical order', j(mergeArtSettings(cur, { allowedStyles: ['line', 'paper'] }, 6).settings.allowedStyles), j(['paper', 'line']));
  check(g, 'an empty allowed list is refused', reason(mergeArtSettings(cur, { allowedStyles: [] }, 6)), 'bad_allowedStyles');
  check(g, 'a duplicate allowed entry is refused', reason(mergeArtSettings(cur, { allowedStyles: ['paper', 'paper'] }, 6)), 'bad_allowedStyles');
  check(g, 'an unknown style is refused', reason(mergeArtSettings(cur, { artStyle: 'neon' }, 6)), 'bad_artStyle');
  check(g, 'a non-string style is refused', reason(mergeArtSettings(cur, { artStyle: 5 }, 6)), 'bad_artStyle');
  check(g, 'the daily question can be switched off', mergeArtSettings(cur, { dailyQuestion: false }, 6).settings.dailyQuestion, false);
  check(g, 'a non-boolean toggle is refused', reason(mergeArtSettings(cur, { dailyQuestion: 'no' }, 6)), 'bad_dailyQuestion');
  check(g, 'coding activities can be switched off', mergeArtSettings(cur, { codeActivities: false }, 6).settings.codeActivities, false);
  check(g, 'an unknown key is refused, not ignored', reason(mergeArtSettings(cur, { mood: 'x' }, 6)), 'unknown_field');
  check(g, 'an empty body is refused', reason(mergeArtSettings(cur, {}, 6)), 'empty_body');
  for (const bad of [null, [], 'x', 3]) check(g, `a body of ${j(bad)} is refused`, reason(mergeArtSettings(cur, bad, 6)), 'body_must_be_object');
}

// ---- C · the clock is not trusted ------------------------------------------
{
  const g = 'C answer time';
  const NOW = 1_700_000_000_000;
  check(g, 'a missing time is now', clampAnsweredAt(undefined, NOW), NOW);
  check(g, 'a string time is now', clampAnsweredAt('2020', NOW), NOW);
  check(g, 'NaN is now', clampAnsweredAt(NaN, NOW), NOW);
  check(g, 'Infinity is now', clampAnsweredAt(Infinity, NOW), NOW);
  check(g, 'a time from the future is now', clampAnsweredAt(NOW + 60_000, NOW), NOW);
  check(g, 'a time far in the future is now', clampAnsweredAt(NOW + 10 * MAX_CLOCK_SKEW_MS, NOW), NOW);
  check(g, 'an offline answer keeps its own time', clampAnsweredAt(NOW - 3_600_000, NOW), NOW - 3_600_000);
  check(g, 'exactly at the age limit is kept', clampAnsweredAt(NOW - MAX_ANSWER_AGE_MS, NOW), NOW - MAX_ANSWER_AGE_MS);
  check(g, 'one ms past the age limit is now', clampAnsweredAt(NOW - MAX_ANSWER_AGE_MS - 1, NOW), NOW);
  check(g, 'epoch zero cannot win every contest', clampAnsweredAt(0, NOW), NOW);
  check(g, 'fractions are floored', clampAnsweredAt(NOW - 5000.7, NOW), NOW - 5001);
  check(g, 'a real local date', isLocalDate('2026-11-07'), true);
  check(g, 'a leap day', isLocalDate('2024-02-29'), true);
  check(g, 'a leap day in a common year is not a date', isLocalDate('2026-02-29'), false);
  check(g, 'month 13 is not a date', isLocalDate('2026-13-01'), false);
  check(g, 'a timestamp is not a local date', isLocalDate('2026-11-07T00:00'), false);
  check(g, 'a number is not a local date', isLocalDate(20261107), false);
}

// ---- D · the merge: one question a day, latest wins ------------------------
{
  const g = 'D merge';
  let r = mergeDay(null, kid(D, 'sea', 100));
  check(g, 'her first answer is taken', r.ok && r.row.colourId, 'sea');
  check(g, 'and counts as a change', r.changed, true);
  r = mergeDay(kid(D, 'sea', 100), kid(D, 'sunny', 200));
  check(g, 'the later device wins', r.row.colourId, 'sunny');
  r = mergeDay(kid(D, 'sea', 200), kid(D, 'sunny', 100));
  check(g, 'an older answer arriving late is kept out', r.row.colourId, 'sea');
  check(g, '... and says so without an error', j([r.ok, r.changed, r.kept]), j([true, false, 'existing']));
  r = mergeDay(kid(D, 'sea', 100), kid(D, 'sunny', 100));
  check(g, 'a tie goes to the incoming write, so a replay is stable', r.row.colourId, 'sunny');
  // Two devices, two orders, one answer.
  const a = kid(D, 'sea', 100), b = kid(D, 'sunny', 200);
  const ab = mergeDay(mergeDay(null, a).row, b).row, ba = mergeDay(mergeDay(null, b).row, a).row;
  check(g, 'all her devices agree whichever order the writes arrive', j(ab), j(ba));
  r = mergeDay(kid(D, 'sea', 100), kid(D, 'sea', 150));
  check(g, 'the same colour again is not a change', r.changed, false);
  check(g, 'her tap does not replace a guardian colour day', reason(mergeDay(mum(D, 'mint', 100), kid(D, 'sea', 900))), 'override_holds');
  r = mergeDay(kid(D, 'sea', 900), mum(D, 'mint', 100));
  check(g, 'a colour day replaces her answer even if hers is later', r.row.colourId, 'mint');
  check(g, '... and is flagged as an override', r.row.override, true);
  r = mergeDay(mum(D, 'mint', 100), mum(D, 'grape', 200));
  check(g, 'a later colour day replaces an earlier one', r.row.colourId, 'grape');
  r = mergeDay(mum(D, 'grape', 200), mum(D, 'mint', 100));
  check(g, 'an earlier colour day does not replace a later one', r.row.colourId, 'grape');
  check(g, 'an unknown colour id is refused', reason(mergeDay(null, kid(D, 'chartreuse', 1))), 'unknown_colour');
  check(g, 'pure red is not a swatch, even from a guardian', reason(mergeDay(null, mum(D, '#FF0000', 1))), 'unknown_colour');
  check(g, 'a write for another day is refused', reason(mergeDay(kid('2026-11-06', 'sea', 1), kid(D, 'sea', 2))), 'wrong_day');
  check(g, 'a child cannot claim an override', reason(mergeDay(null, { ...kid(D, 'sea', 1), override: true })), 'bad_shape');
  check(g, 'a guardian write must carry the override flag', reason(mergeDay(null, { ...mum(D, 'sea', 1), override: false })), 'bad_shape');
  check(g, 'a bad date is refused', reason(mergeDay(null, kid('2026-13-40', 'sea', 1))), 'bad_shape');
  check(g, 'a non-finite time is refused', reason(mergeDay(null, kid(D, 'sea', NaN))), 'bad_shape');
  check(g, 'a sitter cannot write a colour', reason(mergeDay(null, { ...kid(D, 'sea', 1), chosenBy: 'sitter' })), 'bad_shape');
  const before = j(kid(D, 'sea', 100)); const ex = kid(D, 'sea', 100); mergeDay(ex, kid(D, 'sunny', 200));
  check(g, 'the stored row is never mutated', j(ex), before);
}

// ---- E · reading the days --------------------------------------------------
{
  const g = 'E reading';
  const days = [kid('2026-11-05', 'grass', 10), kid('2026-11-06', 'storm', 20), kid('2026-11-06', 'sky', 30), kid(D, 'sea', 40)];
  check(g, 'no days, no colour', currentDay([]), 'null');
  check(g, 'the newest day is current', currentDay(days).colourId, 'sea');
  check(g, 'within a day the later answer is current', currentDay([days[1], days[2]]).colourId, 'sky');
  check(g, 'today\'s row is today\'s colour', colourToday(days, D).colourId, 'sea');
  check(g, 'before she answers, yesterday\'s colour carries over', colourToday(days, '2026-11-08').colourId, 'sea');
  check(g, 'an earlier date sees only what came before it', colourToday(days, '2026-11-06').colourId, 'sky');
  check(g, 'nothing before the first day', colourToday(days, '2026-11-04'), 'null');
  check(g, 'the question is asked when today has no row', needsQuestion(days, '2026-11-08', true), true);
  check(g, 'one answer on any device ends the question everywhere', needsQuestion(days, D, true), false);
  check(g, 'a guardian colour day also ends it', needsQuestion([mum(D, 'mint', 1)], D, true), false);
  check(g, 'the question is never asked when switched off', needsQuestion(days, '2026-11-08', false), false);
  check(g, 'a device showing the answer matches', deviceMatches(days, D, { localDate: D, colourId: 'sea' }), true);
  check(g, 'a device showing yesterday\'s does not', deviceMatches(days, D, { localDate: '2026-11-06', colourId: 'sky' }), false);
  check(g, 'a device that has not reported does not match', deviceMatches(days, D, null), false);
  check(g, 'one neutral choice per day, dated at her local noon', j(toChoices(days).map((c) => c.chosenAt.slice(0, 10))), j(['2026-11-05', '2026-11-06', '2026-11-06', D]));
  const v = guardianView(days, D);
  check(g, 'the guardian is told what, in one sentence', v.line, 'Today her colour is sea blue.');
  check(g, 'unchanged since yesterday reads as a plain fact', guardianView([kid('2026-11-06', 'sea', 1), kid(D, 'sea', 2)], D).line, 'Her colour is sea blue.');
  check(g, 'no days, nothing to show', guardianView([], D), 'null');
  check(g, 'the guardian view carries no inference (§8.6.4)', auditColourPayload(v).ok, true);
  check(g, 'a mood field would be caught by the audit', auditColourPayload({ ...v, mood: 'sad' }).ok, false);
  check(g, 'the forbidden keys include the mood family', ['mood', 'sentiment', 'trend', 'why'].every((k) => DAY_FORBIDDEN_KEYS.includes(k)), true);
}

// ---- F · the play window ---------------------------------------------------
{
  const g = 'F play window';
  const w = { opensMin: 930, restsMin: 1140, windDownMin: 30 };
  check(g, 'wind-down choices are off, 15 and 30', j(WIND_DOWN_CHOICES), j([0, 15, 30]));
  check(g, 'a sensible window is accepted', reason(checkPlayWindow(w)), 'OK');
  check(g, 'the whole day with no wind-down is accepted', reason(checkPlayWindow({ opensMin: 0, restsMin: 1439, windDownMin: 0 })), 'OK');
  check(g, 'resting before it opens', reason(checkPlayWindow({ opensMin: 700, restsMin: 600, windDownMin: 0 })), 'bad_restsMin');
  check(g, 'an empty window is refused', reason(checkPlayWindow({ opensMin: 600, restsMin: 600, windDownMin: 0 })), 'bad_restsMin');
  check(g, 'a negative minute is refused', reason(checkPlayWindow({ opensMin: -1, restsMin: 600, windDownMin: 0 })), 'bad_opensMin');
  check(g, 'minute 1440 is refused', reason(checkPlayWindow({ opensMin: 0, restsMin: 1440, windDownMin: 0 })), 'bad_restsMin');
  check(g, 'a fractional minute is refused', reason(checkPlayWindow({ opensMin: 1.5, restsMin: 600, windDownMin: 0 })), 'bad_opensMin');
  check(g, 'a string minute is refused', reason(checkPlayWindow({ opensMin: '0', restsMin: 600, windDownMin: 0 })), 'bad_opensMin');
  check(g, 'a wind-down of 10 is refused', reason(checkPlayWindow({ opensMin: 0, restsMin: 600, windDownMin: 10 })), 'bad_windDownMin');
  check(g, 'a missing wind-down is refused', reason(checkPlayWindow({ opensMin: 0, restsMin: 600 })), 'bad_windDownMin');
  check(g, 'a window shorter than its own tail plus 15 min is refused', reason(checkPlayWindow({ opensMin: 0, restsMin: 44, windDownMin: 30 })), 'window_too_short');
  check(g, 'an unknown key is refused', reason(checkPlayWindow({ ...w, mood: 'x' })), 'unknown_field');
  check(g, 'null is refused', reason(checkPlayWindow(null)), 'body_must_be_object');
  check(g, 'before it opens, games rest', playWindowState(w, 929), 'resting');
  check(g, 'at opening, games are open', playWindowState(w, 930), 'open');
  check(g, 'one minute before the tail, still plain open', playWindowState(w, 1109), 'open');
  check(g, 'the tail starts 30 minutes before resting', playWindowState(w, 1110), 'winding_down');
  check(g, 'the last minute is still the tail', playWindowState(w, 1139), 'winding_down');
  check(g, 'at the rest time, games rest', playWindowState(w, 1140), 'resting');
  check(g, 'late evening is resting', playWindowState(w, 1439), 'resting');
  check(g, 'with wind-down off there is no tail', playWindowState({ ...w, windDownMin: 0 }, 1139), 'open');
  check(g, 'no window set means always open', playWindowState(null, 3), 'open');
  check(g, 'window length', windowLength(w), 210);
  check(g, 'opening earlier is longer', isLonger(w, { ...w, opensMin: 900 }), true);
  check(g, 'resting later is longer', isLonger(w, { ...w, restsMin: 1200 }), true);
  check(g, 'a shorter window is never reported as longer', isLonger(w, { ...w, opensMin: 960, restsMin: 1110 }), false);
  check(g, 'a different wind-down alone is not longer', isLonger(w, { ...w, windDownMin: 15 }), false);
  check(g, 'a first window is not "longer"', isLonger(null, w), false);
  check(g, 'open says nothing', playWindowLine('open'), 'null');
  check(g, 'winding down is one calm sentence', playWindowLine('winding_down'), 'It’s getting sleepy. One more, then goodnight.');
  check(g, 'the resting line promises tomorrow', /tomorrow/.test(playWindowLine('resting')), true);
  check(g, 'neither line carries a number, a timer or a threat', /[0-9]|timer|locked|limit|time\'s up|no more/i.test(playWindowLine('resting') + playWindowLine('winding_down')), false);
}

// ---- G · golden vectors ----------------------------------------------------
{
  const g = 'G golden vectors';
  const onDisk = JSON.parse(readFileSync(new URL('./colour_day_vectors.json', import.meta.url), 'utf8'));
  check(g, 'colour_day_vectors.json equals a fresh generation (run: node tools/gen-colour-vectors.mjs)',
    JSON.stringify(onDisk) === JSON.stringify(JSON.parse(JSON.stringify(generate()))), true);
  check(g, 'the vectors carry every group the Dart port reads', ['constants', 'stylesForAge', 'artPatches', 'clamp', 'merge', 'currentDay', 'colourToday', 'needsQuestion', 'deviceMatches', 'toChoices', 'guardianView', 'checkWindow', 'windowState', 'isLonger']
    .every((k) => Array.isArray(onDisk[k]) || typeof onDisk[k] === 'object'), true);
  check(g, 'enough merge cases to mean something', onDisk.merge.length >= 15, true);
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
