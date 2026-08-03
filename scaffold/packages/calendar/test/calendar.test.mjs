/**
 * calendar — the shared month grid and the birthday picker.
 * MASTERFILE §8.7, §9.4, §8.5.2.
 */
import { MONTHS, DOW_SHORT, WEEK_STARTS_ON, isLeap, daysInMonth, monthGrid,
  deriveBirthYear, hintMonth, shouldHint, HINT_FADES_AT_AGE,
  beginPicker, pickMonth, pickDay, answerYearCheck, pickedDate, resolveBirthday,
  markBirthday, occurrenceIn, sleepsUntilBirthday, firstCalendarEntry,
  LEAP_DAY_OBSERVED_ON } from '../src/calendar.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const NOW=new Date('2026-07-27T12:00:00Z');

// BK · THE SHARED GRID — one month renderer for the whole product
{
  check('BK grid','twelve months, named not numbered', MONTHS.length, 12);
  check('BK grid','US market → weeks start Sunday', WEEK_STARTS_ON, 0);
  check('BK grid','day labels align to that', DOW_SHORT[0], 'Sun');

  check('BK grid','2024 is a leap year', isLeap(2024), 'true');
  check('BK grid','1900 is NOT — the century rule', isLeap(1900), 'false');
  check('BK grid','2000 IS — the 400 rule', isLeap(2000), 'true');
  check('BK grid','February has 29 in a leap year', daysInMonth(2024,2), 29);
  check('BK grid','and 28 otherwise', daysInMonth(2025,2), 28);
  check('BK grid','April has 30', daysInMonth(2026,4), 30);

  // July 2026 starts on a Wednesday.
  const g=monthGrid(2026,7,{today:NOW});
  check('BK grid','name is carried', g.name, 'July');
  check('BK grid','grid is always a whole number of weeks', g.cells.length%7, 0);
  check('BK grid','leading blanks align the first day',
    g.cells.filter(c=>c.day===null&&g.cells.indexOf(c)<7).length, 3);
  check('BK grid','the first real day is the 1st',
    g.cells.find(c=>c.day!==null).day, 1);
  check('BK grid','31 real days in July',
    g.cells.filter(c=>c.day!==null).length, 31);
  check('BK grid','today is flagged', g.cells.find(c=>c.isToday).day, 27);
  check('BK grid','every real day has an ISO date',
    g.cells.filter(c=>c.day!==null).every(c=>/^\d{4}-\d{2}-\d{2}$/.test(c.iso)), 'true');
  check('BK grid','blanks carry no date',
    g.cells.filter(c=>c.day===null).every(c=>c.iso===null), 'true');

  // February in a leap year must render 29 and still fill whole weeks.
  const f=monthGrid(2024,2);
  check('BK grid','leap February renders 29 days',
    f.cells.filter(c=>c.day!==null).length, 29);
  check('BK grid','and still fills whole weeks', f.cells.length%7, 0);

  // Markers are how the birthday, exchanges and school events all land.
  const m=monthGrid(2026,6,{markers:{'2026-06-14':['birthday']}});
  check('BK grid','a marker lands on the right day',
    m.cells.find(c=>c.day===14).markers.join(), 'birthday');
  check('BK grid','and nowhere else',
    m.cells.filter(c=>c.markers.length).length, 1);
}

// BL · DERIVING THE YEAR — she is never asked something she cannot know
{
  check('BL year','age 6, birthday already had → 2020',
    deriveBirthYear(6,true,NOW), 2020);
  check('BL year','age 6, not yet → 2019', deriveBirthYear(6,false,NOW), 2019);
  check('BL year','age 12 not yet → 2013', deriveBirthYear(12,false,NOW), 2013);
  check('BL year','the only question is one a five-year-old can answer',
    deriveBirthYear(5,true,NOW)-deriveBirthYear(5,false,NOW), 1);
}

// BM · THE MONTH HINT — scaffolding that fades
{
  check('BM hint','a guardian date narrows the hunt', hintMonth('2019-06-14'), 6);
  check('BM hint','no date, no hint', hintMonth(null), 'null');
  check('BM hint','a young child gets the hint', shouldHint('2019-06-14',6), 'true');
  check('BM hint',`it fades at ${HINT_FADES_AT_AGE}`, shouldHint('2019-06-14',9), 'false');
  check('BM hint','and without a guardian date there is nothing to hint',
    shouldHint(null,5), 'false');
}

// BN · THE PICKER — month, then day, then at most one question
{
  let p=beginPicker(null,6);
  check('BN picker','starts at the month', p.step, 'month');
  p=pickMonth(p,6);
  check('BN picker','then the day', p.step, 'day');
  check('BN picker','an impossible month is ignored', pickMonth(p,13).month, 6);

  const bad=pickDay(p,31,NOW);
  check('BN picker','June has no 31st', bad.reason, 'no_such_day');
  const ok=pickDay(p,14,NOW);
  check('BN picker','the 14th is fine', ok.ok, 'true');
  check('BN picker','with no guardian date, the year is asked', ok.picker.step, 'year_check');

  const done=answerYearCheck(ok.picker,true,NOW);
  check('BN picker','answering completes it', done.picker.step, 'done');
  check('BN picker','and yields a full date — age 6 in 2026 means born 2020',
    pickedDate(done.picker), '2020-06-14');
  const notYet=answerYearCheck(ok.picker,false,NOW);
  check('BN picker','"not yet" pushes the year back one', pickedDate(notYet.picker), '2019-06-14');

  // A future date cannot be a birthday.
  let fut=pickMonth(beginPicker(null,0),12);
  const f=pickDay(fut,25,NOW);
  check('BN picker','a future birthday is refused',
    answerYearCheck(f.picker,true,NOW).ok, 'false');
  check('BN picker','with the reason named',
    answerYearCheck(f.picker,true,NOW).reason, 'in_the_future');
  check('BN picker','while last December is perfectly valid',
    pickedDate(answerYearCheck(f.picker,false,NOW).picker), '2025-12-25');

  // 29 February must be selectable before the year is known.
  let leap=pickMonth(beginPicker(null,6),2);
  check('BN picker','29 February is selectable', pickDay(leap,29,NOW).ok, 'true');
  check('BN picker','but 30 February is not', pickDay(leap,30,NOW).reason, 'no_such_day');

  // With a guardian date, the year question disappears entirely.
  let known=pickMonth(beginPicker('2019-06-14',6),6);
  const k=pickDay(known,14,NOW);
  check('BN picker','a known year skips the question', k.picker.step, 'done');
  check('BN picker','and uses the guardian year', pickedDate(k.picker), '2019-06-14');
  check('BN picker','no age means no derivation possible',
    pickDay(pickMonth(beginPicker(null,null),6),14,NOW).reason, 'no_age');
}

// BO · SHE IS NOT CORRECTED ABOUT HER OWN BIRTHDAY
{
  let p=pickMonth(beginPicker('2019-06-14',6),6);
  p=pickDay(p,15,NOW).picker;                       // a day out
  const r=resolveBirthday(p);
  check('BO record','the guardian date is of record', r.ofRecord, '2019-06-14');
  check('BO record','hers is kept', r.asShePlacedIt, '2019-06-15');
  check('BO record','and the disagreement is recorded', r.disagrees, 'true');
  check('BO record','nothing in the result corrects her',
    /wrong|incorrect|actually|should be/i.test(JSON.stringify(r)), 'false');

  let agree=pickMonth(beginPicker('2019-06-14',6),6);
  agree=pickDay(agree,14,NOW).picker;
  check('BO record','agreement is not flagged', resolveBirthday(agree).disagrees, 'false');
  check('BO record','with no guardian date, hers IS the record',
    resolveBirthday(answerYearCheck(pickDay(pickMonth(beginPicker(null,6),3),2,NOW).picker,
      true,NOW).picker).ofRecord, '2020-03-02');
}

// BP · THE PERMANENT MARKER
{
  let p=pickMonth(beginPicker('2019-06-14',6),6);
  p=pickDay(p,14,NOW).picker;
  const m=markBirthday('olive',p,'coral','2026-07-27T12:00:00Z');
  check('BP marker','marked', m.ok, 'true');
  check('BP marker','it recurs yearly', m.event.recurrence, 'yearly');
  check('BP marker','a birthday is a fact — a guardian cannot delete it',
    m.event.deletableByGuardian, 'false');
  check('BP marker','it carries her colour', m.event.colourId, 'coral');
  check('BP marker','and records that she placed it', m.event.placedByChild, 'true');
  check('BP marker','the year is NOT on the event — it lives on the child record',
    'year' in m.event, 'false');
  check('BP marker','an incomplete pick cannot be marked',
    markBirthday('olive',beginPicker(null,6),null,'t').reason, 'incomplete');

  check('BP marker','it occurs each year', occurrenceIn(m.event,2027), '2027-06-14');
  check('BP marker','sleeps until it is computed',
    sleepsUntilBirthday(m.event,'2026-06-10'), 4);
  check('BP marker','and rolls to next year once passed',
    sleepsUntilBirthday(m.event,'2026-07-27')>300, 'true');
  check('BP marker','on the day itself it is zero',
    sleepsUntilBirthday(m.event,'2026-06-14'), 0);

  // 29 February would vanish in three years out of four without a rule.
  let lp=pickMonth(beginPicker('2020-02-29',6),2);
  lp=pickDay(lp,29,NOW).picker;
  const leap=markBirthday('olive',lp,'sea','t').event;
  check('BP marker','a leap birthday exists in a leap year',
    occurrenceIn(leap,2024), '2024-02-29');
  check('BP marker','and is observed in February otherwise, not March',
    occurrenceIn(leap,2025), '2025-02-28');
  check('BP marker','which keeps it in the right month for a child',
    Number(occurrenceIn(leap,2025).slice(5,7)), LEAP_DAY_OBSERVED_ON.month);
  check('BP marker','it never silently disappears',
    [2025,2026,2027,2028].every(y=>occurrenceIn(leap,y)), 'true');
}

// BQ · HER CALENDAR BEGINS WITH HER BIRTHDAY
{
  let p=pickMonth(beginPicker('2019-06-14',6),6);
  p=pickDay(p,14,NOW).picker;
  const e=markBirthday('olive',p,'coral','t').event;
  const first=firstCalendarEntry(e);
  check('BQ first','it reads in her voice', first.label, 'My birthday');
  check('BQ first','and lands as a marker the shared grid understands',
    monthGrid(2026,6,{markers:{[occurrenceIn(e,2026)]:first.markers}})
      .cells.find(c=>c.day===14).markers.join(), 'birthday');
  check('BQ first','no custody language anywhere near it',
    /custody|exchange|handover|possession/i.test(JSON.stringify(first)), 'false');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
