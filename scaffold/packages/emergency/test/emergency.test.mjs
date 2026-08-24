/**
 * emergency — the emergency card. MASTERFILE §11.4.
 *
 * Real, live gap this file closes: `packages/emergency/src/emergency.ts` had
 * ZERO test coverage anywhere in this repo before this pass — not referenced
 * by any test file, not wired into `tools/verify.sh`'s own suite list —
 * despite this file's own header calling it "the one surface in this
 * product that might matter at 3 a.m." Found by a fresh 2026-08-24 audit
 * while fixing a real bug in `buildCard()` (see the "H buildCard override"
 * group below); rather than leave the rest of the module still untested,
 * this covers the whole real surface.
 */
import { orderContacts, orderMedical, buildCard, needsReview, childCard,
  auditCard, US_EMERGENCY, US_POISON_CONTROL, REVIEW_AFTER_DAYS }
  from '../src/emergency.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const contact=(kind,label,number,note=null)=>({kind,label,number,note});

// G · ORDERING — the feature. In an emergency nobody reads a list.
{
  const shuffled=[
    contact('insurance','Ins','1'), contact('dentist','Dent','2'),
    contact('guardian','Mom','3'), contact('emergency_services','911','911'),
    contact('poison_control','Poison','1-800'), contact('doctor','Doc','4'),
  ];
  const ordered=orderContacts(shuffled).map(c=>c.kind);
  check('G order','services first', ordered[0], 'emergency_services');
  check('G order','poison control second', ordered[1], 'poison_control');
  check('G order','guardian third', ordered[2], 'guardian');
  check('G order','insurance sorts last (not in the priority list)', ordered[5], 'insurance');
  check('G order','original array is not mutated',
    shuffled[0].kind, 'insurance');

  const meds=[
    { kind:'note', text:'sees well', critical:false },
    { kind:'allergy', text:'Peanuts', critical:true },
    { kind:'condition', text:'asthma', critical:false },
  ];
  check('G order','critical medical facts sort first',
    orderMedical(meds)[0].text, 'Peanuts');
}

// H · buildCard — real defaults, real override fix
{
  const guardian=contact('guardian','Mom','555-1000');
  const base=buildCard('Ivy','2018-01-01',[guardian],[],null);
  check('H buildCard','US emergency default is present when none supplied',
    base.contacts.some(c=>c.kind==='emergency_services' && c.number===US_EMERGENCY), 'true');
  check('H buildCard','US poison control default is present when none supplied',
    base.contacts.some(c=>c.kind==='poison_control' && c.number===US_POISON_CONTROL), 'true');
  check('H buildCard','a supplied guardian contact passes through',
    base.contacts.some(c=>c.number==='555-1000'), 'true');
  check('H buildCard','requiresAuth is always false — must work when everything else does not',
    base.requiresAuth, 'false');
  check('H buildCard','requiresNetwork is always false',
    base.requiresNetwork, 'false');

  // Real, live bug fixed 2026-08-24 (fresh audit finding): buildCard() used
  // to unconditionally overwrite ANY guardian-supplied emergency_services/
  // poison_control contact with the hardcoded US default, silently — no
  // error, no warning. A corrected local number, a non-US emergency line,
  // or a building-specific line was dropped with zero trace.
  const localEmergency=contact('emergency_services','Local fire dept','555-9111','call this one, not 911');
  const overridden=buildCard('Ivy','2018-01-01',[guardian,localEmergency],[],null);
  check('H buildCard override','a guardian-supplied emergency_services contact wins over the US default',
    overridden.contacts.find(c=>c.kind==='emergency_services').number, '555-9111');
  check('H buildCard override','its note survives too — not silently discarded',
    overridden.contacts.find(c=>c.kind==='emergency_services').note,
    'call this one, not 911');
  check('H buildCard override','the US default is not ALSO present — one real winner, not two contacts',
    overridden.contacts.filter(c=>c.kind==='emergency_services').length, 1);

  const localPoison=contact('poison_control','Regional poison line','555-8222');
  const overriddenPoison=buildCard('Ivy','2018-01-01',[guardian,localPoison],[],null);
  check('H buildCard override','a guardian-supplied poison_control contact wins too',
    overriddenPoison.contacts.find(c=>c.kind==='poison_control').number, '555-8222');

  // Supplying only ONE of the two overridable kinds must not disturb the
  // other's real, honest US default.
  const onlyEmergencyOverridden=buildCard('Ivy','2018-01-01',[guardian,localEmergency],[],null);
  check('H buildCard override','overriding one kind leaves the other kind\'s default intact',
    onlyEmergencyOverridden.contacts.find(c=>c.kind==='poison_control').number, US_POISON_CONTROL);
}

// I · needsReview — a card nobody has looked at in a year is probably wrong
{
  check('I review','never reviewed needs review', needsReview({lastReviewedAt:null}, '2026-08-24T00:00:00Z'), 'true');
  check('I review','reviewed yesterday does not need review',
    needsReview({lastReviewedAt:'2026-08-23T00:00:00Z'}, '2026-08-24T00:00:00Z'), 'false');
  const stale=new Date(Date.parse('2026-08-24T00:00:00Z') - (REVIEW_AFTER_DAYS+1)*86_400_000).toISOString();
  check('I review',`stale past REVIEW_AFTER_DAYS (${REVIEW_AFTER_DAYS}d) needs review`,
    needsReview({lastReviewedAt:stale}, '2026-08-24T00:00:00Z'), 'true');
}

// J · childCard — nothing clinical, just who to call
{
  const card=buildCard('Ivy','2018-01-01',
    [contact('guardian','Dad','555-2000'), contact('doctor','Dr. Lee','555-3000'),
     contact('named_adult','Aunt Sue','555-4000')],
    [{kind:'allergy',text:'Peanuts — SEVERE reaction',critical:true}], null);
  const kid=childCard(card);
  check('J child','emergency services, guardian, and named_adult all reach the child view',
    kid.people.map(p=>p.label).sort().join(','),
    'Aunt Sue,Dad,Emergency');
  check('J child','the doctor does NOT reach the child view — clinical contacts stay adult-only',
    kid.people.some(p=>p.label==='Dr. Lee'), 'false');
  check('J child','no clinical/allergy detail leaks into the child-facing text',
    JSON.stringify(kid).match(/allerg|peanut/i), null);
  check('J child','the reassurance line is present and unconditional',
    kid.line, 'If you need a grown-up, tap one of these. It is never the wrong thing to do.');
}

// K · auditCard — a wrong card is worse than no card
{
  const good=buildCard('Ivy','2018-01-01',[contact('guardian','Dad','555-2000')],[],null);
  check('K audit','a real card with a guardian and the US default passes clean',
    auditCard(good).ok, 'true');
  const noGuardian=buildCard('Ivy','2018-01-01',[],[],null);
  check('K audit','no guardian contact at all is a real fault',
    auditCard(noGuardian).faults.includes('no_guardian'), 'true');
  check('K audit','requiresAuth is structurally always false, so that fault never fires on a real card',
    auditCard(good).ok===true || !auditCard(good).faults.includes('requires_auth'), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
