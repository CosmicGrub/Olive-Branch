/**
 * Child-home vectors drift guard (wave 2a). The live prototype (docs/superpowers/mockups/live/mod-child.js) is the
 * REFERENCE for the per-age child homes; client/lib/child_home_bands.dart is asserted equal to
 * client/test/parity/vectors/child_home_bands.json by client/test/child_home_bands_test.dart, and this fails if that
 * file is stale against a fresh headless render of the prototype, or if a rule the vector states stopped holding.
 *
 *   regenerate: cd scaffold && node tools/gen-child-home-vectors.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { render, OUT } from '../gen-child-home-vectors.mjs';

const SCAFFOLD = fileURLToPath(new URL('../../', import.meta.url));
const rd = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };

const fresh = await render();
const D = JSON.parse(fresh);
const ids = (age) => D.homes[age].tiles.map((t) => t.id);

{
  const g = 'A drift';
  check(g, 'child_home_bands.json exists', existsSync(OUT), true);
  check(g, 'child_home_bands.json equals a fresh render of the prototype (run: node tools/gen-child-home-vectors.mjs)', rd(OUT) === fresh, true);
  check(g, 'the generator is deterministic (two runs, identical bytes)', (await render()) === fresh, true);
}
{
  const g = 'B the four homes (what the prototype actually draws)';
  check(g, '3-4: three huge picture tiles (people, stories, colour) and nothing else of the table', ids(4).slice(0, 3), ['people', 'stories', 'colour']);
  check(g, '5-7: day, then play msgs stories showtell, then people colour more', ids(6), ['day', 'play', 'msgs', 'stories', 'showtell', 'people', 'colour', 'more']);
  check(g, '8-12: weeks, then msgs play list storyteller, then people showtell journal more', ids(10), ['weeks', 'msgs', 'play', 'list', 'storyteller', 'people', 'showtell', 'journal', 'more']);
  check(g, '13-17 (wave 2b): msgs cal play(13 only) journal draw people ladder privacy more', ids(13), ['msgs', 'cal', 'play', 'journal', 'draw', 'people', 'ladder', 'privacy', 'more']);
  check(g, '14: Play has moved to More', ids(14).includes('play'), false);
  check(g, 'the band changes exactly at 5, 8 and 13', [4, 5, 7, 8, 12, 13, 17].map((a) => D.homes[a].band), ['t34', 't57', 't57', 't812', 't812', 't1317', 't1317']);
  for (const [b, ages] of [['t57', [5, 6, 7]], ['t812', [8, 9, 10, 11, 12]]])
    check(g, `${b}: every age of the band draws the identical home`, new Set(ages.map((a) => ids(a).join())).size, 1);
  for (const a of [5, 8, 13]) check(g, `age ${a}: the table's bandset is the set of tiles drawn`, [...new Set(ids(a))].sort().join(), [...D.bandset[D.homes[a].band]].sort().join());
  check(g, 'Messages is on every home from 5 up', [5, 8, 13].every((a) => ids(a).includes('msgs')), true);
}
{
  const g = 'C renames per band';
  const title = (age, id) => D.homes[age].tiles.find((t) => t.id === id).title;
  check(g, 'Play together is Play together (5-7), Games (8-12), Downtime (13-17)', [title(6, 'play'), title(10, 'play'), title(13, 'play')], ['Play together', 'Games', 'Downtime']);
  check(g, 'Colour/Draw & colour become Studio at 13-17', [D.mores[6].find((t) => t.id === 'draw').title, D.mores[13].find((t) => t.id === 'draw').title], ['Draw & colour', 'Studio']);
  check(g, 'My day becomes Today at 13-17 (registry)', D.tiles.day.alt.t1317[0], 'Today');
}
{
  const g = 'D the More page';
  const m = (a) => D.mores[a].map((t) => t.id);
  check(g, 'a Ask-a-grown-up door ends every More page', [6, 9, 13].every((a) => m(a).at(-1) === 'grownup'), true);
  check(g, '5-7 shows at most six of the list, 8-12 and 13-17 at most seven, plus the door', [m(6).length - 1, m(9).length - 1, m(13).length - 1].map((n) => n <= 7), [true, true, true]);
  check(g, 'limits are 6, 7, 7', [D.moreLimit.t57, D.moreLimit.t812, D.moreLimit.t1317], [6, 7, 7]);
  check(g, 'the birthday tile appears under 11 with a birthday on file, never from 11', [D.moresWithBirthday[10].includes('birthday'), D.moresWithBirthday[11].includes('birthday'), m(6).includes('birthday')], [true, false, false]);
  check(g, 'Play is in More from 14 only', [m(13).includes('play'), m(14).includes('play')], [false, true]);
}
{
  const g = 'E your home grows';
  check(g, 'a page is ready at the ages she crosses a key', D.growBandAges, { 5: 5, 8: 8, 10: 10, 13: 13, 14: 14, 15: 15, 16: 16, 17: 17 });
  check(g, 'the keys', D.growKeys, [5, 8, 10, 13, 14, 15, 16, 17, 18]);
  check(g, 'the age-5 and age-8 pages are pictures with a lead line, changes and a button', [5, 8].map((k) => [!!D.grow[k].scene, D.grow[k].items.length >= 3, D.grow[k].cta]), [[true, true, 'Show me'], [true, true, 'Show me']]);
  check(g, 'teen pages (13+) have no scene and say so', [13, 14, 15, 16, 17, 18].every((k) => D.grow[k].teen === true && !D.grow[k].scene), true);
}
{
  const g = 'F wiring';
  const pkg = JSON.parse(rd(SCAFFOLD + 'package.json'));
  check(g, 'package.json has test:child-home-vectors, part of npm test', !!pkg.scripts['test:child-home-vectors'] && pkg.scripts.test.includes('test:child-home-vectors'), true);
  check(g, 'verify.sh runs this test', rd(SCAFFOLD + 'tools/verify.sh').includes('tools/test/child_home_vectors.test.mjs'), true);
  for (const f of ['lib/child_home_bands.dart', 'lib/child_home_bands_ui.dart', 'lib/child_home_growth.dart', 'test/child_home_bands_test.dart', 'test/child_home_bands_ui_test.dart', 'test/child_home_growth_test.dart', 'test/child_home_bands_postures_test.dart'])
    check(g, `client/${f} is committed`, existsSync(SCAFFOLD + 'client/' + f), true);
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
