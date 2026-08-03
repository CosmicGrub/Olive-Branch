/**
 * custody — schedule engine. MASTERFILE §9.4, §5.4, §4.1, §8.2.5.
 */
import { DateTime } from 'luxon';
import { patternSideOn, holidayOn, sideOn, blocks, exchanges,
  sleepsUntilSideChange, childCalendarLabel } from '../src/schedule.mjs';

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

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
