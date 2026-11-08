/**
 * custody — schedule engine. MASTERFILE §9.4, §5.4, §4.1, §8.2.5.
 */
import { DateTime } from 'luxon';
import { readFileSync } from 'node:fs';
import { generate as generateVectors } from '../../../tools/gen-custody-vectors.mjs';
import { patternSideOn, holidayOn, sideOn, blocks, exchanges,
  sleepsUntilSideChange, childCalendarLabel, freeGuardianNow,
  sideAtInstant, sideAtOrderLocal } from '../src/schedule.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const NYC='America/New_York', CHI='America/Chicago';
const XMAS={name:'Christmas',startMonthDay:'12-24',endMonthDay:'12-26',
  evenYearSide:'A',priority:10};
const THANKS={name:'Thanksgiving',startMonthDay:'11-26',endMonthDay:'11-29',
  evenYearSide:'B',priority:10};
const NEWYEAR={name:'New Year',startMonthDay:'12-31',endMonthDay:'01-02',
  evenYearSide:'B',priority:10};
const XMAS_DAY={name:'Christmas Day',startMonthDay:'12-25',endMonthDay:'12-25',
  evenYearSide:'B',priority:20};

const order=(o={})=>({pattern:'2-2-3',orderTz:NYC,anchorLocalDate:'2026-01-05',
  exchangeTime:'18:00',holidays:[XMAS,THANKS,NEWYEAR],
  effectiveFrom:'2020-01-01',effectiveTo:null,...o});

// A · ROTATION
{
  const o=order();
  // Anchor is a Monday. 2-2-3: A A B B A A A | B B A A B B B
  const week=['2026-01-05','2026-01-06','2026-01-07','2026-01-08','2026-01-09',
              '2026-01-10','2026-01-11'].map(d=>patternSideOn(o,d)).join('');
  check('A rotation','2-2-3 first week', week, 'AABBAAA');
  const week2=['2026-01-12','2026-01-13','2026-01-14','2026-01-15','2026-01-16',
               '2026-01-17','2026-01-18'].map(d=>patternSideOn(o,d)).join('');
  check('A rotation','2-2-3 second week mirrors', week2, 'BBAABBB');
  check('A rotation','cycle repeats at day 14',
    patternSideOn(o,'2026-01-19'), patternSideOn(o,'2026-01-05'));

  // Dates BEFORE the anchor must not read off the end of the array.
  check('A rotation','date before anchor resolves',
    ['A','B'].includes(patternSideOn(o,'2025-12-20')), 'true');
  check('A rotation','14 days before anchor equals anchor',
    patternSideOn(o,'2025-12-22'), patternSideOn(o,'2026-01-05'));

  const alt=order({pattern:'alternating_weeks'});
  check('A rotation','alternating weeks is 7 on 7 off',
    ['2026-01-05','2026-01-11','2026-01-12','2026-01-18']
      .map(d=>patternSideOn(alt,d)).join(''), 'AABB');

  const o55=order({pattern:'2-2-5-5'});
  check('A rotation','2-2-5-5 produces a 5-day block',
    blocks(o55,'2026-01-05','2026-01-18').some(b=>
      b.startLocalDate==='2026-01-09'&&b.endLocalDate==='2026-01-13'), 'true');
}

// B · HOLIDAY OVERRIDE — the failure that puts a child in the wrong house
{
  const o=order();
  const base=patternSideOn(o,'2026-12-25');
  const actual=sideOn(o,'2026-12-25');
  check('B holiday','Christmas is sourced from a holiday rule', actual.source, 'holiday');
  check('B holiday','2026 is even, so Christmas goes to A', actual.side, 'A');
  check('B holiday','2027 is odd, so Christmas flips to B',
    sideOn(o,'2027-12-25').side, 'B');
  check('B holiday','holiday overrides whatever the pattern said',
    actual.source==='holiday', 'true');
  check('B holiday','Thanksgiving flips independently of Christmas',
    sideOn(o,'2026-11-27').side, 'B');

  // A window wrapping the new year must cover both sides of it.
  check('B holiday','New Year covers Dec 31', holidayOn(o,'2026-12-31').rule.name, 'New Year');
  check('B holiday','New Year covers Jan 1', holidayOn(o,'2027-01-01').rule.name, 'New Year');
  check('B holiday','and not Jan 5', holidayOn(o,'2027-01-05'), 'null');

  // Overlapping rules: the higher priority, more specific one wins.
  const o2=order({holidays:[XMAS,XMAS_DAY]});
  check('B holiday','higher-priority rule wins an overlap',
    holidayOn(o2,'2026-12-25').rule.name, 'Christmas Day');
  check('B holiday','and the specific rule brings its own side',
    sideOn(o2,'2026-12-25').side, 'B');
  check('B holiday','neighbouring days still belong to the broad rule',
    holidayOn(o2,'2026-12-24').rule.name, 'Christmas');

  // Leap day must not throw or shift the cycle.
  check('B holiday','Feb 29 resolves in a leap year',
    ['A','B'].includes(sideOn(o,'2028-02-29').side), 'true');
}

// C · BLOCKS
{
  const o=order();
  const bs=blocks(o,'2026-01-05','2026-01-18');
  check('C blocks','contiguous days merge into blocks', bs.length, 6);
  check('C blocks','first block is A for two days',
    `${bs[0].side}/${bs[0].startLocalDate}/${bs[0].endLocalDate}`,
    'A/2026-01-05/2026-01-06');
  check('C blocks','blocks never overlap',
    bs.every((b,i)=>i===0||b.startLocalDate>bs[i-1].endLocalDate), 'true');
  check('C blocks','blocks are gapless',
    bs.every((b,i)=>i===0||
      DateTime.fromISO(b.startLocalDate).minus({days:1}).toISODate()===bs[i-1].endLocalDate),
    'true');

  // Outside the order's effective window nothing is scheduled.
  const ended=order({effectiveTo:'2026-01-10'});
  check('C blocks','no blocks after the order ends',
    blocks(ended,'2026-01-05','2026-01-18').every(b=>b.endLocalDate<='2026-01-10'),'true');
  const future=order({effectiveFrom:'2026-06-01'});
  check('C blocks','no blocks before the order begins',
    blocks(future,'2026-01-05','2026-01-18').length, 0);

  // A holiday block is labelled as itself, not as a pattern block.
  const dec=blocks(o,'2026-12-20','2026-12-28');
  check('C blocks','holiday appears as its own block',
    dec.some(b=>b.source==='holiday'&&b.holidayName==='Christmas'), 'true');
}

// D · EXCHANGES — order-time is authoritative, verbatim
{
  const o=order();
  const tz=[{tz:NYC,start:null,end:'2026-06-12T22:00:00Z'},
            {tz:CHI,start:'2026-06-12T22:00:00Z',end:'2026-07-25T22:00:00Z'},
            {tz:NYC,start:'2026-07-25T22:00:00Z',end:null}];
  const ex=exchanges(o,'2026-01-05','2026-01-18',tz,NYC);
  check('D exchange','an exchange sits between every pair of blocks',
    ex.length, blocks(o,'2026-01-05','2026-01-18').length-1);
  check('D exchange','order time rendered verbatim with its zone',
    ex[0].orderTimeLabel, '6:00 PM EST');
  check('D exchange','from and to differ', ex[0].from!==ex[0].to, 'true');

  // Summer: the decree still says 6pm Eastern even while she is in Texas.
  const jul=exchanges(o,'2026-07-01','2026-07-06',tz,NYC);
  check('D exchange','order time stays Eastern during the Texas block',
    jul[0].orderTimeLabel, '6:00 PM EDT');
  check('D exchange','which is 5pm where she actually is',
    jul[0].instant.setZone(CHI).toFormat('h:mm a'), '5:00 PM');

  // §4.2 — the zone flip is detected at the exchange, not at midnight.
  const flip=exchanges(o,'2026-06-11','2026-06-14',tz,NYC);
  check('D exchange','a zone change is flagged on the crossing exchange',
    flip.some(e=>e.zoneFlips), 'true');

  // DST: an exchange on the spring-forward date must still resolve.
  const mar=exchanges(o,'2026-03-07','2026-03-10',tz,NYC);
  check('D exchange','exchanges resolve across spring forward',
    mar.every(e=>e.instant.isValid), 'true');
}

// E · SLEEPS — child-local day boundaries, never hours
{
  const o=order();
  const s=sleepsUntilSideChange(o,'2026-01-05');
  check('E sleeps','A holds Mon-Tue, so 2 sleeps to the change', s.sleeps, 2);
  check('E sleeps','and the next side is B', s.nextSide, 'B');
  check('E sleeps','on the right date', s.onLocalDate, '2026-01-07');
  check('E sleeps','the day before a change is 1 sleep',
    sleepsUntilSideChange(o,'2026-01-06').sleeps, 1);
  check('E sleeps','a 3-day block reads 3',
    sleepsUntilSideChange(o,'2026-01-09').sleeps, 3);
  check('E sleeps','never returns 0 — today is not a sleep',
    [...Array(14)].every((_,i)=>
      sleepsUntilSideChange(o,DateTime.fromISO('2026-01-05').plus({days:i}).toISODate()).sleeps>0),
    'true');
}

// F · CHILD LABELS — friendly, never legal
{
  const names={A:'Dad',B:'Mom'};
  const o=order();
  const bs=blocks(o,'2026-12-24','2026-12-26');
  check('F labels','pattern block reads as a person, not a party',
    childCalendarLabel({side:'A',startLocalDate:'x',endLocalDate:'x',source:'pattern'},names),
    "Dad's time");
  check('F labels','holiday block names the holiday',
    childCalendarLabel(bs[0],names), 'Christmas with Dad');
  check('F labels','no legal vocabulary reaches the child view',
    /custody|possession|party|petitioner|respondent/i.test(
      bs.map(b=>childCalendarLabel(b,names)).join(' ')), 'false');
}

// G · FREE GUARDIAN NOW — presence design spec §3, added alongside
// server/routes.mjs's GET .../presence. A pure function (no DB) — the
// on-duty exclusion itself is the CALLER's job (that guardian is simply
// never in `candidates`); this group only proves the availability-window
// resolution and tie-break, per this function's own doc comment.
{
  const dad = { userId: 'dad-1', name: 'Dad' };
  const mom = { userId: 'mom-1', name: 'Mom' };
  const w = (guardianId, guardianName, weekday, startLocal, endLocal) =>
    ({ guardianId, guardianName, weekday, startLocal, endLocal });

  check('G free-now', 'a single active window returns that guardian',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '18:00')
      ?.guardianId, 'dad-1');
  check('G free-now', 'a window that has not started yet is not active',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '16:59'), 'null');
  check('G free-now', 'a window that has already ended is not active',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '20:00'), 'null');
  check('G free-now', 'start is inclusive',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '17:00')
      ?.guardianId, 'dad-1');
  check('G free-now', 'a window on a different weekday is ignored',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 2, '17:00', '20:00')], 1, '18:00'), 'null');
  check('G free-now', 'no candidates means no one is ever free, even with a matching window',
    freeGuardianNow([], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '18:00'), 'null');
  check('G free-now', 'a window belonging to a guardian NOT in candidates is ignored — '
    + "this is how the caller's on-duty exclusion actually takes effect",
    freeGuardianNow([mom], [w('dad-1', 'Dad', 1, '17:00', '20:00')], 1, '18:00'), 'null');
  check('G free-now', 'no windows at all means no one is free',
    freeGuardianNow([dad, mom], [], 1, '18:00'), 'null');

  // Tie-break — "no seniority, no primary/secondary, no custody weighting"
  // (MASTERFILE §5.27.4), only "then simply first" (earliest start) applies.
  check('G free-now', 'two guardians both free — the EARLIER start wins, not registration '
    + 'order or alphabetical name',
    freeGuardianNow([dad, mom],
      [w('mom-1', 'Mom', 1, '17:30', '20:00'), w('dad-1', 'Dad', 1, '17:00', '20:00')],
      1, '18:00')?.guardianId, 'dad-1');
  check('G free-now', 'an exact-tie start time falls back to guardianId, purely for '
    + 'determinism — the comment beside this code says so explicitly, not a product rule',
    freeGuardianNow([dad, mom],
      [w('mom-1', 'Mom', 1, '17:00', '20:00'), w('dad-1', 'Dad', 1, '17:00', '20:00')],
      1, '18:00')?.guardianId, 'dad-1');

  // Overnight windows — real bug found by this feature's own adversarial
  // review before shipping: the first draft's weekday pre-filter defeated
  // isWindowActiveNow()'s own wrap-aware branch the moment local time
  // crossed midnight into the window's second calendar day. Not reachable
  // via real Postgres data today (guardian_availability_window's own
  // CHECK (end_local > start_local) forbids storing such a row at all —
  // see isWindowActiveNow()'s comment) but exercised directly here as a
  // pure-function proof that the logic itself is actually correct, not
  // merely untested.
  check('G free-now', "an overnight window (22:00-06:00, dated yesterday) is still active "
    + 'after midnight, the wrap-around case', freeGuardianNow([dad],
      [w('dad-1', 'Dad', 0, '22:00', '06:00')], /* nowWeekday */ 1, '03:00')
      ?.guardianId, 'dad-1');
  check('G free-now', 'the same overnight window is correctly inactive once its post-'
    + 'midnight half has also ended', freeGuardianNow([dad],
      [w('dad-1', 'Dad', 0, '22:00', '06:00')], 1, '06:00'), 'null');
  check('G free-now', "a guardian's yesterday-dated ORDINARY (non-wrap) window must NOT "
    + 'bleed into today at the same clock time — the exact false-positive this fix had to '
    + 'avoid while adding the wrap-around case above',
    freeGuardianNow([dad], [w('dad-1', 'Dad', 0, '08:00', '09:00')], 1, '08:30'), 'null');
}


// H · S-D7 — a holiday window spanning New Year is ONE holiday, keyed on the
// year it STARTS in. Keyed on each date's own year (the old behaviour) 31 Dec
// 2026 and 1-2 Jan 2027 went to opposite parents inside a single window.
{
  const o=order({holidays:[NEWYEAR]});               // 12-31 -> 01-02, even year = B
  const sides=['2026-12-30','2026-12-31','2027-01-01','2027-01-02','2027-01-03']
    .map(d=>sideOn(o,d));
  check('H new-year window','window started in an EVEN year (2026): all three days are B',
    ['2026-12-31','2027-01-01','2027-01-02'].map(d=>sideOn(o,d).side).join(''), 'BBB');
  check('H new-year window','the three days are all one holiday source',
    ['2026-12-31','2027-01-01','2027-01-02'].every(d=>sideOn(o,d).source==='holiday'), 'true');
  check('H new-year window','the day before the window is the plain pattern',
    sides[0].source, 'pattern');
  check('H new-year window','the day after the window is the plain pattern',
    sides[4].source, 'pattern');
  check('H new-year window','window started in an ODD year (2027) flips to A, all three days',
    ['2027-12-31','2028-01-01','2028-01-02'].map(d=>sideOn(o,d).side).join(''), 'AAA');
  check('H new-year window','blocks() shows ONE contiguous holiday block across the boundary',
    blocks(o,'2026-12-29','2027-01-04').filter(b=>b.source==='holiday').length, 1);
  const hb=blocks(o,'2026-12-29','2027-01-04').find(b=>b.source==='holiday');
  check('H new-year window','that block runs 12-31 through 01-02',
    `${hb.startLocalDate}..${hb.endLocalDate}`, '2026-12-31..2027-01-02');
  // A non-wrapping window keeps its own-year behaviour.
  const x=order({holidays:[XMAS]});
  check('H new-year window','non-wrapping Christmas: 2026 (even) = A, 2027 (odd) = B',
    `${sideOn(x,'2026-12-25').side}${sideOn(x,'2027-12-25').side}`, 'AB');
  const feb=order({holidays:[{name:'Winter',startMonthDay:'12-20',endMonthDay:'02-29',
    evenYearSide:'A',priority:5}]});
  check('H new-year window','long wrapped window: Feb of the following (odd) year follows the even start year',
    `${sideOn(feb,'2026-12-20').side}${sideOn(feb,'2027-02-15').side}`, 'AA');
}

// I · S-D8 — who holds her AT an instant, not on a date. Exchange is 18:00 NYC.
{
  const o=order({holidays:[]});
  // 2026-01-07 is index 2 of the cycle: B takes over from A on that date.
  check('I side at instant','precondition: 01-06 is A and 01-07 is B',
    `${patternSideOn(o,'2026-01-06')}${patternSideOn(o,'2026-01-07')}`, 'AB');
  const at=(iso)=>sideAtInstant(o, DateTime.fromISO(iso,{zone:NYC}));
  check('I side at instant','10:00 on handover day: still the PREVIOUS side (A)',
    at('2026-01-07T10:00:00').side, 'A');
  check('I side at instant','17:59 on handover day: still A', at('2026-01-07T17:59:00').side, 'A');
  check('I side at instant','18:00 on handover day: now B', at('2026-01-07T18:00:00').side, 'B');
  check('I side at instant','23:59 on handover day: B', at('2026-01-07T23:59:00').side, 'B');
  check('I side at instant','a non-handover day is the same all day (01-06 09:00)',
    at('2026-01-06T09:00:00').side, 'A');
  check('I side at instant','the instant is read in the ORDER zone, not UTC: 22:30Z is 17:30 NYC = A',
    sideAtInstant(o, DateTime.fromISO('2026-01-07T22:30:00Z',{zone:'utc'})).side, 'A');
  check('I side at instant','...and 23:00Z is 18:00 NYC = B',
    sideAtInstant(o, DateTime.fromISO('2026-01-07T23:00:00Z',{zone:'utc'})).side, 'B');
  check('I side at instant','before effectiveFrom there is no side',
    sideAtInstant(order({effectiveFrom:'2026-02-01'}), DateTime.fromISO('2026-01-07T12:00:00',{zone:NYC})), 'null');
  check('I side at instant','after effectiveTo there is no side',
    sideAtInstant(order({effectiveTo:'2026-01-06'}), DateTime.fromISO('2026-01-07T12:00:00',{zone:NYC})), 'null');
  check('I side at instant','first effective day before exchange time uses the day own side (no prior day under this order)',
    sideAtInstant(order({effectiveFrom:'2026-01-07'}), DateTime.fromISO('2026-01-07T09:00:00',{zone:NYC})).side, 'B');
  const h=order({holidays:[XMAS]});
  check('I side at instant','holiday start day, before 18:00: previous (pattern) side, not the holiday side',
    `${sideAtInstant(h, DateTime.fromISO('2026-12-24T09:00:00',{zone:NYC})).source}`, 'pattern');
  check('I side at instant','holiday start day, from 18:00: the holiday',
    `${sideAtInstant(h, DateTime.fromISO('2026-12-24T18:00:00',{zone:NYC})).source}`, 'holiday');
  check('I side at instant','sideAtOrderLocal is the pure core (no zone): 01-07 17:59 = A',
    sideAtOrderLocal(o,'2026-01-07','17:59').side, 'A');
}

// J · S-D9 — "N sleeps" must not read past where the order ends.
{
  const o=order({holidays:[],effectiveTo:'2026-01-06'});   // 01-06 is A, 01-07 would be B
  check('J sleeps vs effectiveTo','the order ends before the rotation changes: no countdown to a handover it will never perform',
    sleepsUntilSideChange(o,'2026-01-05'), 'null');
  check('J sleeps vs effectiveTo','with no end date the same query still counts (2 sleeps to B)',
    sleepsUntilSideChange(order({holidays:[]}),'2026-01-05').sleeps, 2);
  const succ=order({holidays:[],pattern:'alternating_weeks',effectiveFrom:'2026-01-07',effectiveTo:null,
    anchorLocalDate:'2026-01-07'});                          // starts on A for 7 days
  const r=sleepsUntilSideChange(o,'2026-01-05',60,succ);
  check('J sleeps vs effectiveTo','a successor that starts on A: first change is when its week ends',
    `${r.sleeps}:${r.nextSide}`, '9:B');
  const succB=order({holidays:[],pattern:'alternating_weeks',effectiveFrom:'2026-01-07',effectiveTo:null,
    anchorLocalDate:'2025-12-31'});                          // 01-07 is index 7 = B
  const r2=sleepsUntilSideChange(o,'2026-01-05',60,succB);
  check('J sleeps vs effectiveTo','a successor that starts on the other side: the next sleep is the successor side',
    `${r2.sleeps}:${r2.nextSide}:${r2.onLocalDate}`, '2:B:2026-01-07');
  check('J sleeps vs effectiveTo','a gap between the orders (successor starts later) is unknown, not a guess',
    sleepsUntilSideChange(o,'2026-01-05',60,order({holidays:[],effectiveFrom:'2026-01-20'})), 'null');
  check('J sleeps vs effectiveTo','a change that happens BEFORE the end date is still reported',
    sleepsUntilSideChange(order({holidays:[],effectiveTo:'2026-01-10'}),'2026-01-05').sleeps, 2);
}

// K · golden vectors shared with the Dart port (client/test/custody_vectors_test.dart)
{
  const g = 'K golden vectors';
  const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
  check(g, 'vectors.json equals a fresh generation (run: node tools/gen-custody-vectors.mjs)',
    JSON.stringify(onDisk) === JSON.stringify(generateVectors()), true);
  check(g, 'the vectors carry the new-year boundary days for the wrapped window',
    onDisk.sideOn.filter(v => v.order === 'newYearOnly' && ['2026-12-31', '2027-01-01', '2027-01-02'].includes(v.date))
      .map(v => v.expect.side).join(''), 'BBB');
  check(g, 'the vectors include a sleeps case that stops at effectiveTo',
    onDisk.sleeps.some(v => v.order === 'ends' && v.successor === null && v.expect === null), true);
  check(g, 'the vectors include a sleeps case answered by the successor order',
    onDisk.sleeps.some(v => v.successor === 'successorB' && v.expect && v.expect.nextSide === 'B'), true);
  check(g, 'the vectors include a before-exchange-time side-at case',
    onDisk.sideAtOrderLocal.some(v => v.order === 'plain' && v.hhmm === '17:59' && v.expect.side === 'A'), true);
}
let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
