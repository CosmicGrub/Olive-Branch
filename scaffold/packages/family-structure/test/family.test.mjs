/**
 * family-structure — age bands, the family structure a guardian builds, change timing,
 * and the one function that decides what the child sees. Every deny path is a real
 * assertion (same discipline as co-view and parent-learn).
 */
import * as F from '../src/family.mjs';
import { sweep } from '../../globalaudit/src/globalaudit.mjs';
import { readFileSync } from 'node:fs';
import { generate, FAMILY } from '../../../tools/gen-family-vectors.mjs';
const {
  deriveChildView, bandForYears, effectiveBand, rungsAt, canEditStructure, canReadReleased,
  parseTiming, defaultTiming, isBigChange, validateOp, validateChange, validatePerson, validateStory,
  applyOp, withBefore, invertOp, foldReleased, foldIntended, releasedIds, pendingChanges,
  birthdayInfo, birthdayLineShown, birthdayPreview, previewChange, emptyStructure, BAND_TABLE, diffBands,
} = F;

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}
const j = (o) => JSON.stringify(o);
const person = (id, label, role, homeId, contact, away = null) => ({ id, label, role, homeId, contact, away });
const home = (id, name, childSleeps = true) => ({ id, name, childSleeps });
const view = (s, band = 't57', suites = {}, rungs = [], opts = {}) => deriveChildView(s, band, suites, rungs, opts);
const TODAY = '2026-11-07';

{
  const g = 'band table is data';
  check(g, 'four bands', BAND_TABLE.length, 4);
  check(g, 'band ids in order', BAND_TABLE.map((b) => b.id).join(), 't34,t57,t812,t13');
  check(g, 'labels are family words, not clinical', BAND_TABLE.map((b) => b.label).join('|'), '3 to 4|5 to 7|8 to 12|13 and up');
  check(g, 'the bands cover every whole year with no gap or overlap',
    Array.from({ length: 30 }, (_, y) => BAND_TABLE.filter((b) => y >= b.minYears && (b.maxYears === null || y <= b.maxYears)).length).every((n) => n === 1), true);
  for (const [y, b] of [[0, 't34'], [3, 't34'], [4, 't34'], [5, 't57'], [7, 't57'], [8, 't812'], [12, 't812'], [13, 't13'], [17, 't13'], [40, 't13']])
    check(g, `${y} years -> ${b}`, bandForYears(y), b);
  check(g, 'fractional years floor (5.9 is still 5)', bandForYears(5.9), 't57');
  for (const [n, v] of [['negative', -1], ['NaN', NaN], ['null', null], ['string', '9'], ['undefined', undefined], ['Infinity', Infinity]])
    check(g, `junk (${n}) fails closed to the YOUNGEST band`, bandForYears(v), 't34');
  check(g, 'only the youngest band is icon-only three tiles', BAND_TABLE.filter((b) => b.home === 'icons3').map((b) => b.id).join(), 't34');
  check(g, 'the youngest band has exactly three tiles', BAND_TABLE[0].tiles.length, 3);
  check(g, 'every band lists plain summary lines', BAND_TABLE.every((b) => b.summary.length >= 3), true);
}

{
  const g = 'hold until I have told her (band)';
  check(g, 'no hold: she follows her natural band', effectiveBand('t812', false, 't57'), 't812');
  check(g, 'hold with a baseline: she stays at the released band', effectiveBand('t812', true, 't57'), 't57');
  check(g, 'hold with no baseline yet follows her natural band', effectiveBand('t812', true, null), 't812');
  check(g, 'a hold never makes her band higher than natural', effectiveBand('t57', true, 't13'), 't57');
  check(g, 'released equals natural: no move', effectiveBand('t57', true, 't57'), 't57');
  check(g, 'a junk released band is ignored', effectiveBand('t57', true, 'x'), 't57');
  check(g, 'hold is a real default (empty structure holds)', emptyStructure().holdBandChange, true);
  check(g, 'a birthday visible by default', emptyStructure().birthdayVisible, true);
}

{
  const g = 'F4 ladder rungs are permanent';
  check(g, 'no rungs at 9', j(rungsAt(9)), '[]');
  check(g, 'own list at 10', j(rungsAt(10)), '["own_list"]');
  check(g, 'all seven at 18', rungsAt(18).length, 7);
  check(g, 'rungs only grow with years', [9, 10, 13, 14, 15, 16, 17, 18].every((y, i, a) => i === 0 || rungsAt(y).length >= rungsAt(a[i - 1]).length), true);
  check(g, 'junk years give no rungs', j(rungsAt('x')), '[]');
  check(g, 'RUNG_AGES equals the section 21 ladder ages', F.RUNG_AGES.map((r) => r.age).join(), '10,13,14,15,16,17,18');
  const ownListBlocked = view(FAMILY, 't812', { myList: false }, rungsAt(10));
  check(g, 'a guardian cannot switch off her own list once she holds the rung', ownListBlocked.home.tiles.includes('myList'), true);
  check(g, 'the same suite switch does hide it before the rung', view(FAMILY, 't812', { myList: false }, []).home.tiles.includes('myList'), false);
  const held = view({ ...FAMILY, holdBandChange: true, releasedBand: 't34', areaBands: { reading: 't34' } }, 't34', {}, rungsAt(13));
  check(g, 'a band, a hold and an override never lower a rung (ladder fields)', Object.values(held.ladder).filter(Boolean).length, 2);
  check(g, 'journal rung is the permanent private journal', held.ladder.privateJournal, true);
  for (const y of [0, 9, 10, 13, 15, 18]) {
    const lad = view(FAMILY, 't34', { myList: false, messages: false }, rungsAt(y), {}).ladder;
    check(g, `at ${y} years the ladder fields equal exactly the rungs held`, Object.values(lad).filter(Boolean).length, rungsAt(y).length);
  }
  check(g, 'no function in the module lowers or revokes a rung', Object.keys(F).filter((k) => /revoke|lower|remove.*rung|clear.*rung/i.test(k)).length, 0);
}

{
  const g = 'F1 only a guardian edits the structure';
  const G = { roleName: 'guardian', userId: 'g1', childId: null };
  check(g, 'a guardian may edit', canEditStructure(G), true);
  for (const [n, p] of [['child', { roleName: 'child', userId: null, childId: 'c1' }], ['sitter', { roleName: 'sitter', userId: 's1' }],
    ['step_parent', { roleName: 'step_parent', userId: 'x' }], ['trusted_adult', { roleName: 'trusted_adult', userId: 't' }],
    ['foster_parent', { roleName: 'foster_parent', userId: 'f' }], ['caseworker', { roleName: 'caseworker', userId: 'w' }],
    ['coordinator', { roleName: 'coordinator', userId: 'k' }], ['court', { roleName: 'court', userId: 'k' }],
    ['system', { roleName: 'system', userId: null }], ['guardian with an empty user id', { roleName: 'guardian', userId: '' }],
    ['guardian with no user id', { roleName: 'guardian' }], ['null', null], ['undefined', undefined], ['a string', 'guardian'],
    ['role spoofed as a number', { roleName: 5, userId: 'g1' }]])
    check(g, `${n} may NOT edit`, canEditStructure(p), false);
  check(g, 'the child reads only her own released structure', canReadReleased({ roleName: 'child', childId: 'c1' }, 'c1'), true);
  check(g, 'a child does not read another child', canReadReleased({ roleName: 'child', childId: 'c1' }, 'c2'), false);
  for (const [n, p] of [['guardian', G], ['sitter', { roleName: 'sitter', userId: 's' }], ['system', { roleName: 'system' }], ['null', null],
    ['child with an empty id', { roleName: 'child', childId: '' }]])
    check(g, `${n} is not the released-structure reader`, canReadReleased(p, 'c1'), false);
  check(g, 'an undefined child id matches nothing', canReadReleased({ roleName: 'child', childId: 'c1' }, undefined), false);
}

{
  const g = 'F5 she sees only the labels a guardian chose';
  const v = view(FAMILY);
  const names = v.places.flatMap((p) => p.people.map((x) => x.name));
  check(g, 'the names she sees are the labels', names.sort().join(), 'Dad,Dana,Grandma,Mom');
  check(g, 'a sitter is never in her people', names.includes('Sue'), false);
  check(g, 'a therapist is never in her people', names.includes('Dr Kim'), false);
  check(g, 'a person with no label is not shown', v.places.flatMap((p) => p.people).some((x) => x.id === 'p7'), false);
  const out = j(v).toLowerCase();
  for (const w of ['step_parent', 'step', 'half', 'sitter', 'therapist', 'caseworker', 'foster', 'guardian', 'relative', 'trusted', 'role'])
    check(g, `no role word "${w}" reaches her`, out.includes(w), false);
  const caseworkerOnly = { ...emptyStructure(), homes: [home('h1', 'Home')], people: [person('p1', 'Mr Lee', 'caseworker', null, ['message'])] };
  check(g, 'a caseworker is not in her people', view(caseworkerOnly).places.length, 0);
  check(g, 'but a caseworker turns My helpers on', view(caseworkerOnly).features.myHelpers, true);
  const foster = { ...emptyStructure(), homes: [home('h1', 'Home')], people: [person('p1', 'Aunt Jo', 'foster_parent', 'h1', ['live_call'])] };
  check(g, 'a foster parent is in her people, under her label', view(foster).places[0].people[0].name, 'Aunt Jo');
  check(g, 'and turns My helpers on, with no role word', view(foster).features.myHelpers, true);
  check(g, 'with no foster parent or caseworker, no helpers', view(FAMILY).features.myHelpers, false);
  check(g, 'whitespace around a label is trimmed, not shown', view({ ...FAMILY, people: [person('p1', '  Mom  ', 'guardian', 'h1', ['message'])] }).places[0].people[0].name, 'Mom');
  check(g, 'a blank (whitespace) label hides the person', view({ ...FAMILY, people: [person('p1', '   ', 'guardian', 'h1', ['message'])] }).places.length, 0);
  check(g, 'the name she uses is exactly the label, everywhere', FAMILY.people.filter(F.shownToChild).every((p) => names.includes(p.label)), true);
}

{
  const g = 'structure drives what she sees';
  const v = view(FAMILY);
  check(g, 'homes are places, with the people who are there', v.places.map((p) => `${p.name}:${p.people.map((x) => x.name).join('+')}`).join('|'), "Mom's house:Mom|Dad's house:Dad+Dana|Near and far:Grandma");
  check(g, 'someone away sits in their own place', v.places.at(-1).kind, 'far');
  check(g, 'a person away turns Two Skies on', v.features.twoSkies, true);
  check(g, 'and the path home', v.features.pathHome, true);
  check(g, 'and Postcards', v.features.postcards, true);
  check(g, 'more than one home: Weeks', v.features.weeks, true);
  check(g, 'more than one home: Packing buddy', v.features.packingBuddy, true);
  const single = view({ ...emptyStructure(), homes: [home('h1', 'Home')], people: [person('p1', 'Mum', 'guardian', 'h1', ['live_call'])] });
  check(g, 'one home: no Weeks', single.features.weeks, false);
  check(g, 'one home, nobody away: no Two Skies', single.features.twoSkies, false);
  check(g, 'live calls give a call button by their face', j(v.places[0].people[0].buttons), '["call","chat"]');
  check(g, 'messages alone give only a message button', j(v.places[1].people[1].buttons), '["chat"]');
  const visits = view({ ...emptyStructure(), homes: [home('h1', 'H')], people: [person('p1', 'Aunt', 'relative', 'h1', ['live_call', 'supervised_visit', 'voice_line', 'postcard'])] });
  check(g, 'supervised visits replace the call button with a scheduled visit', j(visits.places[0].people[0].buttons), '["visit","postcard","voice"]');
  check(g, 'a voice line turns the voice line on', visits.features.voiceLine, true);
  check(g, 'visits turn scheduled visits on', visits.features.scheduledVisits, true);
  const ended = view({ ...FAMILY, people: FAMILY.people.map((p) => (p.id === 'p4' ? { ...p, away: { until: '2026-01-01' } } : p)) }, 't57', {}, [], { today: TODAY });
  check(g, 'an away window that has ended is no longer away', ended.features.twoSkies, false);
  const stillAway = view({ ...FAMILY, people: FAMILY.people.map((p) => (p.id === 'p4' ? { ...p, away: { until: '2027-01-01' } } : p)) }, 't57', {}, [], { today: TODAY });
  check(g, 'an away window still open is away', stillAway.features.twoSkies, true);
  check(g, 'a person with no home sits in near and far', view({ ...FAMILY, people: [person('p1', 'Nan', 'relative', null, ['message'])] }).places[0].name, 'Near and far');
  check(g, 'the same structure, derived twice, is identical (pure)', j(view(FAMILY)) === j(view(FAMILY)), true);
  check(g, 'deriving never mutates the structure', (() => { const a = j(FAMILY); view(FAMILY, 't34'); view(FAMILY, 't13'); return a === j(FAMILY); })(), true);
  check(g, 'a null structure does not throw and yields no places', view(null).places.length, 0);
}

{
  const g = 'age band home variants';
  const t34 = view(FAMILY, 't34');
  check(g, '3-4: the icon-only home', t34.home.variant, 'icons3');
  check(g, '3-4: three tiles, call first', t34.home.tiles.join(), 'call,stories,colour');
  check(g, '3-4: the call is for a person she can call (Mom)', t34.home.heroPersonId, 'p1');
  check(g, '3-4: no words to read, every word spoken', `${t34.home.wordsBesidePictures}/${t34.home.speakEveryWord}`, 'false/true');
  check(g, '3-4: no My people list, no features', `${t34.places.length}/${Object.values(t34.features).some(Boolean)}`, '0/false');
  check(g, '3-4: no hero person when nobody can be called', view({ ...emptyStructure(), people: [person('p1', 'Nan', 'relative', null, ['message'])] }, 't34').home.heroPersonId, 'null');
  check(g, '3-4: without a callable person the call tile is gone, two tiles stay', view(emptyStructure(), 't34').home.tiles.join(), 'stories,colour');
  check(g, '3-4: the calls suite off removes the call', view(FAMILY, 't34', { calls: false }).home.tiles.join(), 'stories,colour');
  const t57 = view(FAMILY, 't57');
  check(g, '5-7: pictures lead', t57.home.variant, 'pictures');
  check(g, '5-7: the current tiles plus My people', t57.home.tiles.join(), 'myDay,play,messages,stories,showTell,homework,myList,myPeople,more');
  check(g, '5-7: every word can be heard', t57.home.speakEveryWord, true);
  check(g, '5-7: greeting is not plain', t57.home.plainGreeting, false);
  const t812 = view(FAMILY, 't812');
  check(g, '8-12: words beside the pictures', `${t812.home.variant}/${t812.home.wordsBesidePictures}`, 'words/true');
  check(g, '8-12: a plain greeting', t812.home.plainGreeting, true);
  check(g, '8-12: words replace speaking every word', t812.home.speakEveryWord, false);
  const t13 = view(FAMILY, 't13');
  check(g, '13+: words', `${t13.home.variant}/${t13.areas.reading.mode}`, 'words/words');
  check(g, 'a junk band fails closed to the youngest home', view(FAMILY, 'x').home.variant, 'icons3');
  check(g, 'no My people tile when there is nobody to show', view(emptyStructure(), 't57').home.tiles.includes('myPeople'), false);
  check(g, 'the people suite off hides My people', view(FAMILY, 't57', { myPeople: false }).home.tiles.includes('myPeople'), false);
  const off = view(FAMILY, 't57', { messages: false, games: false, stories: false, showTell: false, homework: false });
  check(g, 'switched-off suites remove their tiles', off.home.tiles.join(), 'myDay,myList,myPeople,more');
  check(g, 'switching a suite off changes only that suite', view(FAMILY, 't57', { messages: false }).home.tiles.filter((t) => t !== 'messages').join(), t57.home.tiles.filter((t) => t !== 'messages').join());
}

{
  const g = 'per-area overrides';
  const ahead = view({ ...FAMILY, areaBands: { reading: 't812' } }, 't57');
  check(g, 'reading ahead: words beside pictures at a younger band', ahead.home.wordsBesidePictures, true);
  check(g, 'reading ahead: the area names the band it follows', ahead.areas.reading.band, 't812');
  check(g, 'the other areas still follow her band', ahead.areas.games.band, 't57');
  check(g, 'her home variant still follows her band', ahead.home.variant, 'pictures');
  const behind = view({ ...FAMILY, areaBands: { games: 't34' } }, 't812');
  check(g, 'games held back: no Play tile', behind.home.tiles.includes('play'), false);
  check(g, 'games held back: messages unaffected', behind.home.tiles.includes('messages'), true);
  check(g, 'calendar held to the youngest: no My day', view({ ...FAMILY, areaBands: { calendar: 't34' } }, 't57').home.tiles.includes('myDay'), false);
  check(g, 'messages held to the youngest: no Messages', view({ ...FAMILY, areaBands: { chat: 't34' } }, 't57').home.tiles.includes('messages'), false);
  check(g, 'a junk override value is ignored', view({ ...FAMILY, areaBands: { reading: 'zzz' } }, 't57').areas.reading.band, 't57');
  check(g, 'an override cannot lower a rung', view({ ...FAMILY, areaBands: { people: 't34', reading: 't34' } }, 't812', {}, rungsAt(10)).ladder.ownList, true);
  check(g, 'five areas', F.AREAS.length, 5);
}

{
  const g = 'birthday';
  check(g, 'visible by default', view(FAMILY).birthday.visible, true);
  check(g, 'a guardian can hide it', view({ ...FAMILY, birthdayVisible: false }).birthday.visible, false);
  check(g, 'the birthday suite off hides it too', view(FAMILY, 't57', { birthday: false }).birthday.visible, false);
  const a = birthdayInfo('2019-12-09', TODAY);
  check(g, 'Dec 9: 32 sleeps (the mockup)', a.sleepsUntil, 32);
  check(g, 'she will be 7 on that day', a.turnsYears, 7);
  check(g, 'she is 6 now', a.yearsOld, 6);
  check(g, 'a band change is not a birthday surprise: 6 to 7 stays 5-7', a.bandChanges, false);
  check(g, 'a birthday at 12 to 13 changes band', birthdayInfo('2013-11-20', TODAY).bandChanges, true);
  check(g, 'on the day itself: 0 sleeps, no band change flagged', `${birthdayInfo('2019-11-07', TODAY).sleepsUntil}/${birthdayInfo('2019-11-07', TODAY).yearsOld}`, '0/7');
  check(g, 'the day after: next one is almost a year away', birthdayInfo('2019-11-06', TODAY).sleepsUntil, 364);
  check(g, 'Feb 29 in a non-leap year is held on Mar 1', birthdayInfo('2020-02-29', '2027-02-20').nextOn, '2027-03-01');
  check(g, 'Feb 29 in a leap year is Feb 29', birthdayInfo('2020-02-29', '2028-02-28').nextOn, '2028-02-29');
  check(g, 'a future birth date is refused', birthdayInfo('2027-01-01', TODAY), null);
  check(g, 'junk is refused', birthdayInfo('nope', TODAY), null);
  check(g, 'one quiet line only in her last week', [32, 8, 7, 3, 0].map((n) => birthdayLineShown(n, true)).join(), 'false,false,true,true,true');
  check(g, 'hidden means no line at all', birthdayLineShown(3, false), false);
  check(g, 'a negative or fractional count never shows a line', `${birthdayLineShown(-1, true)}/${birthdayLineShown(2.5, true)}`, 'false/false');
  const p = birthdayPreview(birthdayInfo('2013-11-20', TODAY), true, 't812');
  check(g, 'the preview says what moves at a band change', p.changes.length > 0, true);
  check(g, 'with the hold on, her home stays at the released band', `${p.herBandAfter}/${p.herHomeAfter}/${p.heldAtBirthday}`, 't13/t812/true');
  const nh = birthdayPreview(birthdayInfo('2013-11-20', TODAY), false, 't812');
  check(g, 'with the hold off, her home moves', `${nh.herHomeAfter}/${nh.heldAtBirthday}`, 't13/false');
  check(g, 'a birthday inside a band changes nothing', birthdayPreview(a, true, 't57').changes.length, 0);
  check(g, 'a birthday is never a sleeps-only counter in a child payload: the key is sleepsUntil', Object.keys(a).includes('countdown'), false);
}

{
  const g = 'F3 change timing';
  check(g, 'now parses', j(parseTiming({ kind: 'now' }, TODAY)), j({ ok: true, timing: { kind: 'now' } }));
  check(g, 'hold parses', parseTiming({ kind: 'hold' }, TODAY).ok, true);
  check(g, 'a date tomorrow parses', parseTiming({ kind: 'date', on: '2026-11-08' }, TODAY).ok, true);
  check(g, 'a date today is refused: that is "now"', parseTiming({ kind: 'date', on: TODAY }, TODAY).reason, 'date_not_future');
  check(g, 'a past date is refused', parseTiming({ kind: 'date', on: '2026-11-06' }, TODAY).reason, 'date_not_future');
  check(g, 'a date two years and a day away is refused', parseTiming({ kind: 'date', on: '2028-11-08' }, TODAY).reason, 'date_too_far');
  check(g, 'an impossible date is refused', parseTiming({ kind: 'date', on: '2027-02-30' }, TODAY).reason, 'bad_date');
  check(g, 'a date with no day is refused', parseTiming({ kind: 'date' }, TODAY).reason, 'bad_date');
  check(g, 'now with a stray date is refused', parseTiming({ kind: 'now', on: '2026-11-08' }, TODAY).reason, 'bad_timing');
  check(g, 'an unknown kind is refused', parseTiming({ kind: 'later' }, TODAY).reason, 'bad_timing');
  for (const [n, v] of [['string', 'now'], ['null', null], ['array', []], ['number', 5]])
    check(g, `a ${n} is refused`, parseTiming(v, TODAY).ok, false);
  const ex = (o) => withBefore(FAMILY, o);
  check(g, 'adding a person is big: hold is the default', j(defaultTiming(ex({ op: 'put_person', person: person('n', 'N', 'relative', null, []) }))), '{"kind":"hold"}');
  check(g, 'removing a person is big', isBigChange(ex({ op: 'remove_person', personId: 'p3' })), true);
  check(g, 'a rhythm change is big', isBigChange(ex({ op: 'set_rhythm', rhythm: { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00', source: 'guardian' } })), true);
  check(g, 'moving someone to another home is big', isBigChange(ex({ op: 'put_person', person: person('p3', 'Dana', 'step_parent', 'h1', ['message']) })), true);
  check(g, 'a person going away is big', isBigChange(ex({ op: 'put_person', person: person('p3', 'Dana', 'step_parent', 'h2', ['message'], { until: null }) })), true);
  check(g, 'removing a home is big', isBigChange(ex({ op: 'remove_home', homeId: 'h2' })), true);
  check(g, 'a new home is big', isBigChange(ex({ op: 'put_home', home: home('h3', 'New') })), true);
  check(g, 'a relabel is small: now', j(defaultTiming(ex({ op: 'put_person', person: person('p3', 'Dani', 'step_parent', 'h2', ['message']) }))), '{"kind":"now"}');
  check(g, 'a contact tweak is small', isBigChange(ex({ op: 'put_person', person: person('p3', 'Dana', 'step_parent', 'h2', ['message', 'live_call']) })), false);
  check(g, 'an area override is small', isBigChange(ex({ op: 'set_area_band', area: 'reading', band: 't812' })), false);
  check(g, 'settings ops default to now', ['set_birthday_visible', 'set_band_hold', 'release_band'].every((k) => defaultTiming(ex({ op: k, visible: false, hold: false, band: 't812' })).kind === 'now'), true);
  for (const op of [{ op: 'set_birthday_visible', visible: false }, { op: 'set_band_hold', hold: false }, { op: 'release_band', band: 't812' }]) {
    check(g, `${op.op} cannot be held`, validateChange(FAMILY, op, { kind: 'hold' }, TODAY).reason, 'settings_now_only');
    check(g, `${op.op} cannot be dated`, validateChange(FAMILY, op, { kind: 'date', on: '2026-12-01' }, TODAY).reason, 'settings_now_only');
    check(g, `${op.op} can be now`, validateChange(FAMILY, op, { kind: 'now' }, TODAY).ok, true);
  }
  check(g, 'a people change can be held', validateChange(FAMILY, { op: 'remove_person', personId: 'p3' }, { kind: 'hold' }, TODAY).ok, true);
}

{
  const g = 'F2 she sees only what is released';
  const c = (id, seq, op, timing) => ({ entry: 'change', id, seq, op: withBefore(FAMILY, op), timing });
  const add = { op: 'put_person', person: person('p9', 'Pat', 'relative', 'h1', ['message']) };
  const entries = [
    c('c1', 1, add, { kind: 'hold' }),
    c('c2', 2, { op: 'set_area_band', area: 'reading', band: 't812' }, { kind: 'date', on: '2026-11-21' }),
    c('c3', 3, { op: 'set_birthday_visible', visible: false }, { kind: 'now' }),
  ];
  const names = (s) => s.people.map((p) => p.label).join();
  check(g, 'a held change is invisible to her', names(foldReleased(FAMILY, entries, TODAY)).includes('Pat'), false);
  check(g, 'but a guardian sees it in what they intended', names(foldIntended(FAMILY, entries)).includes('Pat'), true);
  check(g, 'a now change reaches her at once', foldReleased(FAMILY, entries, TODAY).birthdayVisible, false);
  check(g, 'a dated change has not reached her before its day', foldReleased(FAMILY, entries, '2026-11-20').areaBands.reading, undefined);
  check(g, 'a dated change reaches her ON its day', foldReleased(FAMILY, entries, '2026-11-21').areaBands.reading, 't812');
  check(g, 'and stays after it', foldReleased(FAMILY, entries, '2027-06-01').areaBands.reading, 't812');
  check(g, 'a held change is still hidden long after a date', names(foldReleased(FAMILY, entries, '2027-06-01')).includes('Pat'), false);
  const withRelease = [...entries, { entry: 'release', id: 'r1', seq: 4, ref: 'c1' }];
  check(g, 'releasing it reaches her', names(foldReleased(FAMILY, withRelease, TODAY)).includes('Pat'), true);
  check(g, 'a release for another change releases nothing else', j([...releasedIds([...entries, { entry: 'release', id: 'r', seq: 9, ref: 'nope' }], TODAY)].sort()), '["c3"]');
  check(g, 'pending lists what is still waiting', pendingChanges(entries, TODAY).map((e) => e.id).join(), 'c1,c2');
  check(g, 'after release and the date, nothing is pending', pendingChanges(withRelease, '2026-11-21').length, 0);
  check(g, 'what she saw before a hold is exactly the base (before == base when nothing is released)', j(foldReleased(FAMILY, [entries[0]], TODAY)), j(FAMILY));
  check(g, 'her derived view does not change while a change is held', j(view(foldReleased(FAMILY, [entries[0]], TODAY))), j(view(FAMILY)));
  check(g, 'her derived view changes after release', j(view(foldReleased(FAMILY, withRelease, TODAY))) === j(view(FAMILY)), false);
  check(g, 'folding is by seq, not array order', j(foldReleased(FAMILY, [...entries].reverse(), TODAY)), j(foldReleased(FAMILY, entries, TODAY)));
  check(g, 'a malformed date in a stored change never releases it', releasedIds([{ entry: 'change', id: 'x', seq: 1, op: entries[0].op, timing: { kind: 'date', on: 'zzz' } }], TODAY).size, 0);
  const rm = foldReleased(FAMILY, [{ entry: 'change', id: 'd', seq: 1, op: withBefore(FAMILY, { op: 'remove_home', homeId: 'h2' }), timing: { kind: 'now' } }], TODAY);
  check(g, 'removing a home unlinks its people (they are not deleted)', `${rm.homes.length}/${rm.people.find((p) => p.id === 'p2').homeId}`, '1/null');
}

{
  const g = 'undo is a new entry';
  const op = withBefore(FAMILY, { op: 'put_person', person: person('p3', 'Dani', 'step_parent', 'h2', ['message']) });
  const after = applyOp(FAMILY, op);
  const inv = invertOp(op, after);
  check(g, 'undoing a relabel puts the old label back', applyOp(after, inv).people.find((p) => p.id === 'p3').label, 'Dana');
  const add = withBefore(FAMILY, { op: 'put_person', person: person('p9', 'Pat', 'relative', null, []) });
  check(g, 'undoing an add removes the person', applyOp(applyOp(FAMILY, add), invertOp(add, applyOp(FAMILY, add))).people.some((p) => p.id === 'p9'), false);
  const rm = withBefore(FAMILY, { op: 'remove_person', personId: 'p3' });
  check(g, 'undoing a removal restores the person', applyOp(applyOp(FAMILY, rm), invertOp(rm, applyOp(FAMILY, rm))).people.some((p) => p.id === 'p3'), true);
  const rh = withBefore(FAMILY, { op: 'set_rhythm', rhythm: { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00', source: 'guardian' } });
  check(g, 'undoing a rhythm restores the pattern', applyOp(applyOp(FAMILY, rh), invertOp(rh, applyOp(FAMILY, rh))).rhythm.pattern, 'alternating_weeks');
  const bd = withBefore(FAMILY, { op: 'set_area_band', area: 'reading', band: 't812' });
  check(g, 'undoing an override clears it', applyOp(applyOp(FAMILY, bd), invertOp(bd, applyOp(FAMILY, bd))).areaBands.reading, undefined);
  check(g, 'the inverse is itself a valid op', validateOp(after, inv).ok, true);
  check(g, 'applying never mutates its input', j(FAMILY) === j(generate().structures.family), true);
  check(g, 'an op for a missing person is ignored, not thrown', applyOp(FAMILY, { op: 'remove_person', personId: 'zzz', before: null }).people.length, FAMILY.people.length);
}

{
  const g = 'validation: every deny path';
  const bad = (op, s = FAMILY) => validateOp(s, op).reason;
  check(g, 'junk op kind', bad({ op: 'rm_rf' }), 'bad_op');
  check(g, 'null op', bad(null), 'bad_op');
  check(g, 'array op', bad([]), 'bad_op');
  check(g, 'no op key', bad({ person: {} }), 'bad_op');
  check(g, 'an op with a field its kind does not have is refused (untrusted bodies are bounded)', bad({ op: 'remove_person', personId: 'p3', note: 'x'.repeat(5000) }), 'bad_op');
  check(g, 'a client-supplied before is tolerated but never trusted', withBefore(FAMILY, { op: 'remove_person', personId: 'p3', before: { evil: 1 } }).before.label, 'Dana');
  const pp = (p) => bad({ op: 'put_person', person: p });
  check(g, 'a good person', validateOp(FAMILY, { op: 'put_person', person: person('a', 'Ok', 'relative', 'h1', ['message']) }).ok, true);
  check(g, 'label over 30 chars', pp(person('a', 'x'.repeat(31), 'relative', null, [])), 'bad_label');
  check(g, 'label of exactly 30 chars', pp(person('a', 'x'.repeat(30), 'relative', null, [])), undefined);
  check(g, 'label with a control character', pp(person('a', 'a\u0007b', 'relative', null, [])), 'bad_label');
  check(g, 'label with a line separator', pp(person('a', 'a b', 'relative', null, [])), 'bad_label');
  check(g, 'label not a string', pp({ ...person('a', 'x', 'relative', null, []), label: 7 }), 'bad_label');
  check(g, 'unknown role', pp(person('a', 'Ok', 'overlord', null, [])), 'bad_role');
  check(g, 'unknown contact mode', pp(person('a', 'Ok', 'relative', null, ['telepathy'])), 'bad_contact');
  check(g, 'duplicate contact mode', pp(person('a', 'Ok', 'relative', null, ['message', 'message'])), 'bad_contact');
  check(g, 'contact not an array', pp({ ...person('a', 'Ok', 'relative', null, []), contact: 'message' }), 'bad_contact');
  check(g, 'a home that does not exist', pp(person('a', 'Ok', 'relative', 'nope', [])), 'unknown_home');
  check(g, 'away with an impossible date', pp(person('a', 'Ok', 'relative', null, [], { until: '2026-02-30' })), 'bad_away');
  check(g, 'away with an extra key', pp(person('a', 'Ok', 'relative', null, [], { until: null, why: 'x' })), 'bad_away');
  check(g, 'away with no end date is allowed', pp(person('a', 'Ok', 'relative', null, [], { until: null })), undefined);
  check(g, 'a bad id', pp(person('a b', 'Ok', 'relative', null, [])), 'bad_id');
  check(g, 'an extra field on a person (e.g. an age) is refused', pp({ ...person('a', 'Ok', 'relative', null, []), age: 4 }), 'bad_person');
  check(g, 'person not an object', pp('Dana'), 'bad_person');
  const full = { ...FAMILY, people: Array.from({ length: 24 }, (_, i) => person(`x${i}`, `P${i}`, 'relative', null, [])) };
  check(g, 'a 25th person', bad({ op: 'put_person', person: person('new', 'N', 'relative', null, []) }, full), 'too_many_people');
  check(g, 'but editing an existing person at the limit is allowed', bad({ op: 'put_person', person: person('x1', 'New name', 'relative', null, []) }, full), undefined);
  check(g, 'removing someone who is not there', bad({ op: 'remove_person', personId: 'zzz' }), 'unknown_person');
  const fh = { ...FAMILY, homes: ['a', 'b', 'c', 'd'].map((x) => home(x, x.toUpperCase())) };
  check(g, 'a fifth home', bad({ op: 'put_home', home: home('e', 'E') }, fh), 'too_many_homes');
  check(g, 'four homes is fine', bad({ op: 'put_home', home: home('a', 'Renamed') }, fh), undefined);
  check(g, 'a home with no name', bad({ op: 'put_home', home: home('e', '  ') }), 'bad_home');
  check(g, 'a home name over 40 chars', bad({ op: 'put_home', home: home('e', 'x'.repeat(41)) }), 'bad_home');
  check(g, 'a home with a non-boolean childSleeps', bad({ op: 'put_home', home: { id: 'e', name: 'E', childSleeps: 'yes' } }), 'bad_home');
  check(g, 'removing a home that is not there', bad({ op: 'remove_home', homeId: 'zzz' }), 'unknown_home');
  const rh = (r) => bad({ op: 'set_rhythm', rhythm: r });
  const good = { pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00', source: 'guardian' };
  check(g, 'a good rhythm', rh(good), undefined);
  check(g, 'a rhythm with an impossible time', rh({ ...good, exchangeTime: '25:00' }), 'bad_rhythm');
  check(g, 'a rhythm with an impossible day', rh({ ...good, exchangeDay: 7 }), 'bad_rhythm');
  check(g, 'a rhythm with an unknown pattern', rh({ ...good, pattern: 'whenever' }), 'bad_rhythm');
  check(g, 'a guardian cannot CLAIM a court order', rh({ ...good, source: 'court_order' }), 'bad_rhythm');
  check(g, 'a rhythm with an extra key', rh({ ...good, note: 'x' }), 'bad_rhythm');
  const locked = { ...FAMILY, rhythm: { pattern: '2-2-3', exchangeDay: 5, exchangeTime: '17:00', source: 'court_order' } };
  check(g, 'F6: a rhythm set by an order is NOT editable', bad({ op: 'set_rhythm', rhythm: good }, locked), 'locked_by_order');
  check(g, 'F6: applying a rhythm over an order changes nothing even if it got through', applyOp(locked, { op: 'set_rhythm', rhythm: good, before: null }).rhythm.pattern, '2-2-3');
  check(g, 'F6: other changes are still allowed while the rhythm is locked', bad({ op: 'put_person', person: person('a', 'Ok', 'relative', null, []) }, locked), undefined);
  check(g, 'an area override with an unknown area', bad({ op: 'set_area_band', area: 'weather', band: 't57' }), 'bad_area');
  check(g, 'an area override with an unknown band', bad({ op: 'set_area_band', area: 'reading', band: 't99' }), 'bad_band');
  check(g, 'clearing an override (null) is fine', bad({ op: 'set_area_band', area: 'reading', band: null }), undefined);
  check(g, 'birthday visibility must be a boolean', bad({ op: 'set_birthday_visible', visible: 'no' }), 'bad_op');
  check(g, 'band hold must be a boolean', bad({ op: 'set_band_hold', hold: 1 }), 'bad_op');
  check(g, 'releasing a band needs a real band', bad({ op: 'release_band', band: 'x' }), 'bad_band');
  check(g, 'validatePerson alone mirrors the same rules', validatePerson(person('a', 'x'.repeat(31), 'relative', null, []), []).reason, 'bad_label');
}

{
  const g = 'F7 stories are guardian-authored text, bounded';
  check(g, 'one short page is fine', validateStory({ pages: ['Some weeks you will sleep at Mom\'s house.'] }).ok, true);
  check(g, 'six pages is fine', validateStory({ pages: Array(6).fill('a') }).ok, true);
  check(g, 'no pages', validateStory({ pages: [] }).reason, 'bad_story');
  check(g, 'seven pages', validateStory({ pages: Array(7).fill('a') }).reason, 'bad_story');
  check(g, 'a page over 240 characters', validateStory({ pages: ['x'.repeat(241)] }).reason, 'bad_story');
  check(g, 'a blank page', validateStory({ pages: ['  '] }).reason, 'bad_story');
  check(g, 'a non-string page', validateStory({ pages: [3] }).reason, 'bad_story');
  check(g, 'an extra key (e.g. a generated flag)', validateStory({ pages: ['a'], generated: true }).reason, 'bad_story');
  check(g, 'null', validateStory(null).reason, 'bad_story');
  check(g, 'a control character in a page', validateStory({ pages: ['a\u0007b'] }).reason, 'bad_story');
  check(g, 'a newline inside a page is fine', validateStory({ pages: ['one\ntwo'] }).ok, true);
  check(g, 'the module exports NO story generator, template or partner content', Object.keys(F).filter((k) => typeof F[k] === 'function' && /story|partner|template|generate|compose|write/i.test(k)).join(), 'validateStory');
  check(g, 'no export mentions a partner', Object.keys(F).some((k) => /partner|stepmom|stepdad|girlfriend|boyfriend/i.test(k)), false);
}

{
  const g = 'previewing before a change';
  const r = previewChange(FAMILY, { op: 'put_person', person: person('p9', 'Pat', 'relative', 'h1', ['message']) }, { kind: 'hold' }, 't57', {}, [], TODAY);
  check(g, 'before is what she sees now', j(r.before) === j(view(FAMILY, 't57', {}, [], { today: TODAY })), true);
  check(g, 'after shows the new person', r.after.places[0].people.some((p) => p.name === 'Pat'), true);
  check(g, 'before does not', r.before.places[0].people.some((p) => p.name === 'Pat'), false);
  check(g, 'it says the view differs', r.differs, true);
  check(g, 'a big change recommends hold', j(r.recommended), '{"kind":"hold"}');
  check(g, 'a held change reaches her when told', r.reaches, 'when_told');
  const same = previewChange(FAMILY, { op: 'put_person', person: person('p5', 'Sue', 'sitter', 'h1', ['message', 'live_call']) }, { kind: 'now' }, 't57', {}, [], TODAY);
  check(g, 'changing a background person does not change her screens', same.differs, false);
  check(g, 'now reaches her now', same.reaches, 'now');
  check(g, 'a dated change says on a date', previewChange(FAMILY, { op: 'remove_person', personId: 'p3' }, { kind: 'date', on: '2026-12-01' }, 't57', {}, [], TODAY).reaches, 'on_date');
  check(g, 'bands diff: 3-4 to 5-7 changes areas', diffBands('t34', 't57').length > 0, true);
  check(g, 'bands diff: a band with itself changes nothing', diffBands('t57', 't57').length, 0);
}

{
  const g = 'child payload sweep (no banned keys)';
  const views = generate().views;
  const leaks = views.flatMap((v) => sweep(v.out).map((l) => `${v.name}:${l.path}`));
  check(g, `no derived view (${views.length}) carries a key the global child sweep bans`, leaks.join(',') || 'none', 'none');
  check(g, 'the birthday info keys pass the sweep', sweep(birthdayInfo('2019-12-09', TODAY)).length, 0);
  check(g, 'the preview payload passes the sweep', sweep(previewChange(FAMILY, { op: 'remove_person', personId: 'p3' }, { kind: 'now' }, 't57', {}, [], TODAY)).length, 0);
}

{
  const g = 'golden vectors';
  const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
  check(g, 'vectors.json equals a fresh generation (run: node tools/gen-family-vectors.mjs)', JSON.stringify(onDisk) === JSON.stringify(JSON.parse(JSON.stringify(generate()))), true);
  for (const k of ['bandTable', 'bandForYears', 'effectiveBand', 'rungsAt', 'views', 'canEdit', 'ops', 'persons', 'timing', 'folds', 'stories', 'birthdays', 'diffs'])
    check(g, `section "${k}" is present and non-empty`, Array.isArray(onDisk[k]) && onDisk[k].length > 0, true);
  check(g, 'NaN and null inputs are spelled as markers, never lost', onDisk.bandForYears.some((x) => x.years === '__nan__') && onDisk.bandForYears.some((x) => x.years === '__null__'), true);
}

// ---------------------------------------------------------------------------
let gname = '';
for (const r of rows) {
  if (r.group !== gname) { gname = r.group; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
