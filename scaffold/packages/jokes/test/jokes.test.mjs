/**
 * jokebook — a fixed, hand-written, age-floored joke library. MASTERFILE §9.2.
 * Prohibition P2 on the favourites half.
 */
import { CATALOGUE, forAge, byId, randomJoke, isStarred, star, unstar,
  favouritesChildView, auditChildView, JOKEBOOK_FORBIDDEN } from '../src/jokes.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// A · CATALOGUE
{
  check('A catalogue','a real library, not a placeholder — at least fifty jokes', CATALOGUE.length >= 50, 'true');
  check('A catalogue','every id is unique — favourites are lists of these',
    new Set(CATALOGUE.map(j=>j.id)).size, CATALOGUE.length);
  check('A catalogue','every joke has a setup', CATALOGUE.every(j=>j.setup.trim().length>0), 'true');
  check('A catalogue','every joke has a punchline', CATALOGUE.every(j=>j.punchline.trim().length>0), 'true');
  check('A catalogue','nothing is gated above 12', Math.max(...CATALOGUE.map(j=>j.minAge)), 12);
  check('A catalogue','the floor starts at 4, same as the games catalogue', Math.min(...CATALOGUE.map(j=>j.minAge)), 4);
  const cats = new Set(CATALOGUE.map(j=>j.category));
  check('A catalogue','every category the file header promises is actually represented',
    ['dadJoke','pun','wordplay','silly','knockKnock'].every(c=>cats.has(c)), 'true');
  check('A catalogue','no category is more than half the book — the mix stays honest',
    Math.max(...[...cats].map(c=>CATALOGUE.filter(j=>j.category===c).length)) <= CATALOGUE.length/2, 'true');
}

// B · forAge — a floor, never a ceiling
{
  check('B forAge','a four-year-old still has jokes — the shelf is never empty', forAge(4).length > 0, 'true');
  check('B forAge','a four-year-old never sees a 5+ joke', forAge(4).every(j=>j.minAge<=4), 'true');
  check('B forAge','more jokes unlock at every step up to 12',
    [4,5,6,7,8,9,10,11,12].every((a,i,arr)=> i===0 || forAge(a).length > forAge(arr[i-1]).length), 'true');
  check('B forAge','a twelve-year-old has the whole book', forAge(12).length, CATALOGUE.length);
  check('B forAge','a teenager has the whole book too — nothing is ever taken away', forAge(15).length, CATALOGUE.length);
  check('B forAge','a seven-year-old already has a real choice — twenty or more', forAge(7).length >= 20, 'true');
}

// C · randomJoke — never the one she just heard
{
  check('C random','returns a joke she can get', randomJoke(6, null, ()=>0.5).minAge <= 6, 'true');
  check('C random','deterministic pick drives the choice', randomJoke(12, null, ()=>0).id, CATALOGUE[0].id);
  const first = randomJoke(4, null, ()=>0);
  const pool4 = forAge(4);
  check('C random','with the last one excluded, pick 0 lands on the NEXT joke, not the same one',
    randomJoke(4, first.id, ()=>0).id, pool4[1].id);
  let repeats=0;
  for (let i=0;i<200;i++){ const j=randomJoke(4, first.id); if(j.id===first.id) repeats++; }
  check('C random','two hundred draws never repeat the excluded joke', repeats, 0);
  check('C random','pick at the very top of the range is clamped inside the pool, never undefined',
    randomJoke(12, null, ()=>0.999999) !== null && randomJoke(12, null, ()=>0.999999) !== undefined, 'true');
  check('C random','below the youngest floor there is honestly nothing, not a crash', randomJoke(3), 'null');
}

// D · favourites — P2
{
  let list=[];
  list = star(list, 'dino-snore', '2026-09-01T20:00:00Z');
  check('D favourites','starring adds it', isStarred(list,'dino-snore'), 'true');
  const again = star(list, 'dino-snore', '2026-09-01T20:01:00Z');
  check('D favourites','starring twice is one star, not two', again.length, 1);
  check('D favourites','starring twice returns the same list — nothing to re-render', again === list, 'true');
  list = star(list, 'impasta', '2026-09-02T20:00:00Z');
  check('D favourites','newest first — tonight\'s star is tomorrow\'s first pick',
    favouritesChildView(list)[0].id, 'impasta');
  list = unstar(list, 'dino-snore');
  check('D favourites','unstar removes it', isStarred(list,'dino-snore'), 'false');
  check('D favourites','unstar leaves the others alone', list.length, 1);
  check('D favourites','a stale id (a joke removed from the book) is dropped from her view, not a crash',
    favouritesChildView([{id:'no-such-joke', starredAt:'2026-01-01T00:00:00Z'}]).length, 0);
  check('D favourites','a favourite carries no count field at all — the type cannot leak one',
    Object.keys(list[0]).sort().join(','), 'id,starredAt');
  check('D favourites','her view is clean by the same audit library.ts runs',
    auditChildView(favouritesChildView(list)).ok, 'true');
  check('D favourites','the audit really catches a leak when handed one',
    auditChildView([{ id:'x', timesRead: 3 }]).leaks.join(','), 'timesRead');
  check('D favourites','the forbidden list names the counter words', JOKEBOOK_FORBIDDEN.includes('streak'), 'true');
  check('D favourites','byId finds a real joke', byId('impasta').punchline, 'An impasta!');
  check('D favourites','byId is undefined for a stranger', byId('nope'), 'undefined');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
