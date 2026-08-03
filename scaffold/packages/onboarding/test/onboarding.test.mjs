/**
 * onboarding — the child's first run. MASTERFILE §8.5, §17.1, §10.2.
 */
import { acceptName, renameSelf, MAX_NAME_LENGTH,
  acceptAge, ageFrom, effectiveAge, MIN_AGE, MAX_AGE,
  whoStep, toggleWho, begin, advance, goBack, greeting, outcome,
  auditOnboardingCopy, ONBOARDING_FORBIDDEN,
  chooseEntry, suggestEntryRole, routeFromEntry,
  ENTRY_CHOICE_GRANTS_NO_AUTHORITY } from '../src/onboarding.mjs';
import { can } from '../../family-graph/src/authorize.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const NOW=new Date('2026-07-27T12:00:00Z');
const dad={userId:'dad',label:'Daddy',joined:true};
const mum={userId:'mum',label:'Mummy',joined:true};
const papa={userId:'p',label:'Papa',joined:true};
const pending={userId:'x',label:'Mama',joined:false};

// AZ · THE NAME — her spelling stands
{
  const r=acceptName('OLIVE','Olive');
  check('AZ name','she spells it, it is kept exactly', r.step.spelled, 'OLIVE');
  check('AZ name','not title-cased', acceptName('olive','Olive').step.spelled, 'olive');
  check('AZ name','a misspelling is NOT corrected',
    acceptName('OLIVEE','Olive').step.spelled, 'OLIVEE');
  check('AZ name','spacing she typed is hers',
    acceptName('O L I V E','Olive').step.spelled, 'O L I V E');
  check('AZ name','skipping falls back to what the guardian entered',
    acceptName('   ','Olive').step.spelled, 'Olive');
  check('AZ name','and is marked as skipped', acceptName('','Olive').step.skipped, 'true');
  check('AZ name',`over ${MAX_NAME_LENGTH} characters is refused, not truncated silently`,
    acceptName('x'.repeat(40),'Olive').reason, 'too_long');
  check('AZ name','she can change it later, any time',
    renameSelf(acceptName('OLIVEE','Olive').step,'Olive').spelled, 'Olive');
  check('AZ name','an empty rename leaves it alone',
    renameSelf(acceptName('OLIVE','x').step,'  ').spelled, 'OLIVE');
}

// BA · THE AGE — hers is a convenience, the guardian's is the fact
{
  check('BA age','derived from a birth date', ageFrom('2016-04-02',NOW), 10);
  check('BA age','the day before a birthday still reads younger',
    ageFrom('2016-07-28',NOW), 9);

  const honest=acceptAge(10,'2016-04-02',NOW);
  check('BA age','agreement is recorded as agreement', honest.disagrees, 'false');
  check('BA age','effective age uses the real one', effectiveAge(honest), 10);

  // The case this guard exists for.
  const optimistic=acceptAge(14,'2018-04-02',NOW);
  check('BA age','a child who taps a higher number is not believed',
    effectiveAge(optimistic), 8);
  check('BA age','and the disagreement is RECORDED, not overwritten',
    optimistic.disagrees, 'true');
  check('BA age','her tap is still kept', optimistic.selfReported, 14);
  check('BA age','nothing she taps can raise a gate',
    effectiveAge(acceptAge(17,'2020-01-01',NOW)), 6);

  check('BA age','out of range clamps rather than failing',
    acceptAge(99,null,NOW).selfReported, MAX_AGE);
  check('BA age','and at the bottom too', acceptAge(0,null,NOW).selfReported, MIN_AGE);
  check('BA age','skipping is allowed', acceptAge(null,'2016-04-02',NOW).skipped, 'true');
  check('BA age','and still yields the real age',
    effectiveAge(acceptAge(null,'2016-04-02',NOW)), 10);
  check('BA age','with no birth date at all, hers is used',
    effectiveAge(acceptAge(7,null,NOW)), 7);
}

// BB · THE WHO — §17.1, she is told, not asked
{
  const one=whoStep([dad]);
  check('BB who','one grown-up → NO choice is presented', one.kind, 'no_choice');
  check('BB who','she is simply told', one.line, "You're here to talk to Daddy.");
  check('BB who','the label is HIS word, not hard-coded',
    whoStep([papa]).only.label, 'Papa');

  const two=whoStep([dad,mum]);
  check('BB who','two grown-ups → a choice', two.kind, 'choose');
  check('BB who','both selected by default — she earns nothing',
    two.selected.length, 2);
  check('BB who','the question is who she is HERE for, not who she prefers',
    two.line, 'Who are you here to talk to?');
  check('BB who','no comparative language anywhere',
    /favourite|prefer|better|most|instead of/i.test(two.line), 'false');

  // Not-yet-joined adults are invisible. §17.5 — permanent asymmetry is supported.
  check('BB who','an unaccepted invitation does not appear',
    whoStep([dad,pending]).kind, 'no_choice');
  check('BB who','nobody joined yet is a supported state',
    whoStep([pending]).kind, 'nobody_yet');
  check('BB who','and it does not imply anything is missing',
    /missing|incomplete|add|invite|should/i.test(whoStep([pending]).line), 'false');

  const off=toggleWho(two,'mum');
  check('BB who','she can deselect one', off.selected.join(), 'dad');
  check('BB who','but §2.12 — the last one cannot be turned off',
    toggleWho(off,'dad').selected.join(), 'dad');
  check('BB who','toggling back on works', toggleWho(off,'mum').selected.length, 2);
}

// BC · THE FLOW — nothing can fail, nothing can trap her
{
  let o=begin();
  check('BC flow','starts at the name', o.step, 'name');
  o=advance(o,{name:'OLIVE'});
  check('BC flow','then age', o.step, 'age');
  o=advance(o,{age:6,birthDate:'2020-03-01',now:NOW});
  check('BC flow','then colour', o.step, 'colour');
  o=advance(o,{colourId:'coral'});
  check('BC flow','then birthday', o.step, 'birthday');
  o=advance(o,{birthday:'2020-06-14'});
  check('BC flow','then who', o.step, 'who');
  o=advance(o,{grownups:[dad]});
  check('BC flow','then done', o.step, 'done');

  const out=outcome(o);
  check('BC flow','her spelling is the display name', out.displayName, 'OLIVE');
  check('BC flow','the guardian birth date decides the age', out.effectiveAge, 6);
  check('BC flow','and she is talking to Dad', out.talkingTo.join(), 'dad');
  check('BC flow','her colour is carried out of onboarding', out.colourId, 'coral');
  check('BC flow','and the birthday she placed', out.birthday, '2020-06-14');
  check('BC flow','greeting uses her name', greeting(o), 'Hi OLIVE');

  // Skipping everything must still land somewhere usable.
  let s=begin();
  s=advance(s,{name:''}); s=advance(s,{age:null,birthDate:null});
  s=advance(s,{colourId:null}); s=advance(s,{birthday:null});
  s=advance(s,{grownups:[dad]});
  check('BC flow','skipping every step still completes', s.step, 'done');
  check('BC flow','and the greeting degrades gracefully', greeting(s), 'Hi');
  check('BC flow','with no age known', outcome(s).effectiveAge, 'null');
  check('BC flow','and a flag that it was never established',
    outcome(s).ageWasSelfReportedOnly, 'false');
  check('BC flow','skipping the colour leaves her without one, which is fine',
    outcome(s).colourId, 'null');
  check('BC flow','and skipping the birthday costs only the act of placing it',
    outcome(s).birthday, 'null');
  check('BC flow','self-reported-only is flagged for the guardian',
    outcome(advance(advance(advance(advance(advance(begin(),{name:'O'}),
      {age:7,birthDate:null}),{colourId:null}),{birthday:null}),
      {grownups:[dad]})).ageWasSelfReportedOnly, 'true');

  check('BC flow','she can go back', goBack({...o,step:'who'}).step, 'birthday');
  check('BC flow','but not before the beginning', goBack(begin()).step, 'name');
}

// BD · THE COPY — she is not being tested
{
  check('BD copy','a neutral line passes',
    auditOnboardingCopy('How do you spell your name?').ok, 'true');
  check('BD copy','"try again" is refused',
    auditOnboardingCopy('That is not right, try again').ok, 'false');
  check('BD copy','"well done" is refused too — this is not a test to pass',
    auditOnboardingCopy('Well done!').found.join(','), 'well done');
  check('BD copy','"invalid" is refused', auditOnboardingCopy('Invalid name').ok, 'false');
  check('BD copy','the banned list covers praise and correction alike',
    ONBOARDING_FORBIDDEN.length>=10, 'true');
  check('BD copy','no line the module itself produces trips the guard',
    [whoStep([dad]).line, whoStep([dad,mum]).line, whoStep([pending]).line,
     greeting(begin())].every(l=>auditOnboardingCopy(l).ok), 'true');
}

// BE · THE ENTRY GATE — §8.5.0, a role question, not an age gate
{
  check('BE gate','a device with a child birth date on record suggests "child"',
    suggestEntryRole(true), 'child');
  check('BE gate','a device with no birth date suggests neither',
    suggestEntryRole(false), 'null');
  check('BE gate','absence of a birth date never defaults toward grownup',
    suggestEntryRole(false) === 'grownup', 'false');

  check('BE gate','choosing "my child\'s device" records child',
    chooseEntry('child').role, 'child');
  check('BE gate','choosing "the grown-up\'s device" records grownup',
    chooseEntry('grownup').role, 'grownup');

  check('BE gate','child routes, unchanged, into the existing kiosk/begin() flow',
    routeFromEntry('child'), 'child_kiosk');
  check('BE gate','grownup routes to real account setup, not straight into the app',
    routeFromEntry('grownup'), 'grownup_account_setup');
  check('BE gate','the two routes are distinct',
    routeFromEntry('child') !== routeFromEntry('grownup'), 'true');

  check('BE gate','choosing child does not disturb the existing first-run flow',
    begin().step, 'name');

  check('BE gate','the named invariant is asserted, not just documented',
    ENTRY_CHOICE_GRANTS_NO_AUTHORITY, 'true');

  // The proof that matters, run against the REAL authorizer rather than a
  // same-file stub: a tap of "the grown-up's device" is a routing decision,
  // not a credential. Feed it, with zero family-graph edges, into the actual
  // can() from family-graph/authorize.ts and confirm it is denied exactly as
  // any stranger would be — this screen has never heard of an edge, and
  // cannot manufacture one.
  const tapped = chooseEntry('grownup');
  routeFromEntry(tapped.role);
  const decision = can('settings', [], 'olive-child-1', NOW, tapped.role);
  check('BE gate','the real authorizer denies a guardian-role tap with zero edges',
    decision.allow, 'false');
  check('BE gate','and the reason is exactly no_edge — only real edges grant anything',
    decision.allow ? undefined : decision.reason, 'no_edge');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
