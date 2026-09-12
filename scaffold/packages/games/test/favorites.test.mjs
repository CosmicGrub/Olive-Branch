/**
 * favorites — guardian-curated favourites, age-unlock, and "surprise me" for
 * GamePickerScreen's Recommended row. MASTERFILE §9.2. Prohibition P2.
 * docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-design.md.
 *
 * Own small GameMeta fixtures, deliberately not the real CATALOGUE from
 * games.ts — the same posture jokes.test.mjs takes with its own inline
 * favourite fixtures rather than reaching into the real jokebook. `handicaps`
 * is always `[]` here; nothing in this file exercises it.
 */
import { star, unstar, favouritesFor, newlyUnlocked, randomGame } from '../src/favorites.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const meta = (kind, minAge) => ({ kind, title: kind, minAge, competitive: false, handicaps: [], blurb: kind });
const CATALOGUE = [
  meta('tictactoe', 4), meta('dotsboxes', 5), meta('memory', 4), meta('story', 5),
  meta('chess', 8),
];

// A · star / unstar — idempotent, no duplicates
{
  let list = [];
  list = star(list, 'tictactoe');
  check('A star/unstar','starring adds it', list.includes('tictactoe'), 'true');
  const again = star(list, 'tictactoe');
  check('A star/unstar','starring twice is one star, not two', again.length, 1);
  check('A star/unstar','starring an already-starred kind returns the SAME list — nothing to re-render',
    again === list, 'true');
  list = star(list, 'chess');
  check('A star/unstar','a second, different star is added', list.length, 2);
  list = unstar(list, 'tictactoe');
  check('A star/unstar','unstar removes it', list.includes('tictactoe'), 'false');
  check('A star/unstar','unstar leaves the others alone', list.join(','), 'chess');
  check('A star/unstar','unstarring something never starred is a harmless no-op',
    unstar(list, 'nope').join(','), 'chess');
}

// B · favouritesFor — resolves against the live catalogue, no dangling refs
{
  const result = favouritesFor(CATALOGUE, ['tictactoe', 'chess', 'no-such-game']);
  check('B favouritesFor','a stale kind (removed from the catalogue) is dropped, not a crash',
    result.some(g => g.kind === 'no-such-game'), 'false');
  check('B favouritesFor','a real starred kind resolves to its full GameMeta',
    result.find(g => g.kind === 'chess')?.title, 'chess');
  check('B favouritesFor','exactly the two real starred kinds come back, no more, no fewer',
    result.length, 2);
  check('B favouritesFor','order follows the catalogue, not the starred list',
    result.map(g => g.kind).join(','), 'tictactoe,chess');
  check('B favouritesFor','no starred kinds at all resolves to an empty list, not null',
    favouritesFor(CATALOGUE, []).length, 0);
  check('B favouritesFor','the same kind listed twice in starred never produces a duplicate GameMeta',
    favouritesFor(CATALOGUE, ['chess', 'chess']).length, 1);
}

// C · newlyUnlocked — the age-crossed-since-last-open rule
{
  check('C newlyUnlocked','a null ageAtLastOpen (first-ever open) returns nothing — no fabricated "all new"',
    newlyUnlocked(CATALOGUE, 8, null).length, 0);
  check('C newlyUnlocked','a game whose minAge sits strictly between ageAtLastOpen and her real age is newly unlocked',
    newlyUnlocked(CATALOGUE, 8, 6).map(g => g.kind).sort().join(','), 'chess');
  check('C newlyUnlocked','a game she already had at ageAtLastOpen is NOT newly unlocked',
    newlyUnlocked(CATALOGUE, 8, 6).some(g => g.kind === 'tictactoe'), 'false');
  check('C newlyUnlocked','a game still above her current age never shows, unlocked or not',
    newlyUnlocked(CATALOGUE, 7, 4).some(g => g.kind === 'chess'), 'false');
  check('C newlyUnlocked','no age crossed since last open (age unchanged) returns nothing',
    newlyUnlocked(CATALOGUE, 6, 6).length, 0);
  check('C newlyUnlocked','a birthday that crosses no new minAge threshold still returns nothing',
    newlyUnlocked(CATALOGUE, 4, 4).length, 0);
  check('C newlyUnlocked','crossing every threshold at once (a long-absent visit) surfaces all of them',
    newlyUnlocked(CATALOGUE, 8, 3).map(g => g.kind).sort().join(','),
    ['tictactoe','dotsboxes','memory','story','chess'].sort().join(','));
}

// D · randomGame — never the one she just left, same shape as jokes.ts's randomJoke
{
  check('D randomGame','returns a game she can play', randomGame(CATALOGUE, 6, null, ()=>0.5).minAge <= 6, 'true');
  check('D randomGame','deterministic pick drives the choice',
    randomGame(CATALOGUE, 8, null, ()=>0).kind, CATALOGUE.filter(g=>g.minAge<=8)[0].kind);
  const pool6 = CATALOGUE.filter(g => g.minAge <= 6);
  const first = randomGame(CATALOGUE, 6, null, ()=>0);
  check('D randomGame','with the last pick excluded, choosing index 0 lands on the NEXT game, not the same one',
    randomGame(CATALOGUE, 6, first.kind, ()=>0).kind, pool6[1].kind);
  let repeats = 0;
  for (let i = 0; i < 200; i++) {
    const g = randomGame(CATALOGUE, 6, first.kind);
    if (g.kind === first.kind) repeats++;
  }
  check('D randomGame','two hundred draws never repeat the excluded kind', repeats, 0);
  check('D randomGame','pick at the very top of the range is clamped inside the pool, never undefined',
    randomGame(CATALOGUE, 8, null, ()=>0.999999) !== null
      && randomGame(CATALOGUE, 8, null, ()=>0.999999) !== undefined, 'true');
  check('D randomGame','below the youngest floor there is honestly nothing, not a crash',
    randomGame(CATALOGUE, 3, null), 'null');
  check('D randomGame','no default `pick` argument still returns a real, real-catalogue game (Math.random path)',
    CATALOGUE.some(g => g.kind === randomGame(CATALOGUE, 8, null).kind), 'true');
}

// E · P2 — nothing here carries a count, order, or streak
{
  check('E P2','a favourite is a bare kind string — the type has no field to leak a count',
    typeof star([], 'chess')[0], 'string');
  check('E P2','favouritesFor never adds a rank/position field to the resolved GameMeta',
    Object.keys(favouritesFor(CATALOGUE, ['chess'])[0]).sort().join(','),
    'blurb,competitive,handicaps,kind,minAge,title');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
