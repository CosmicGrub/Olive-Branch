/**
 * Phase 3 — court tier, archive, games, accessibility, SMS.
 * MASTERFILE §9.2, §9.8, §8.4, §10.8, §16.1 #3. Prohibitions P8, P9.
 */
import { DateTime } from 'luxon';
import { append, verifyChain, entryHash, GENESIS, allocate, owedTo,
  authorizeExport, certify, verifyExport, FREE_CERTIFIED_PER_YEAR }
  from '../src/ledger.mjs';
import { compileYearBook, handover, onThisDay, guardianCanReadAfterHandover }
  from '../../archive/src/archive.mjs';
import { newGame, drop, turnExpired, scheduleStrip, buildSms, auditSms,
  sendSmsGuard, DEFAULT_TURN_BUDGET_REACHABLE_HOURS } from '../../phase3/src/phase3.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const NYC='America/New_York';

const chainOf=(n)=>{let c=[];for(let i=0;i<n;i++)
  c=[...c,append(c,{childId:'m',authorId:i%2?'mom':'dad',
    at:DateTime.fromISO('2026-01-01T00:00:00Z').plus({days:i}).toISO(),
    body:`entry ${i}`})];return c;};

// L0 · SHA-256 PORTABILITY — the hand-rolled digest must match node:crypto
{
  const { createHash } = await import('node:crypto');
  const { sha256Hex } = await import('../src/sha256.mjs');
  const node = (s) => createHash('sha256').update(s).digest('hex');
  // NIST vectors.
  check('L0 sha256','empty string', sha256Hex(''), node(''));
  check('L0 sha256','"abc"', sha256Hex('abc'), node('abc'));
  check('L0 sha256','448-bit message',
    sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
    node('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'));
  // Block-boundary cases: 55, 56, 63, 64, 65 bytes exercise every padding path.
  for (const n of [55,56,63,64,65,119,120,1000]) {
    const s = 'x'.repeat(n);
    check('L0 sha256', `${n}-byte input matches node`, sha256Hex(s), node(s));
  }
  // Multi-byte UTF-8 must be encoded identically.
  check('L0 sha256','utf-8 multibyte', sha256Hex('Maya — café ✦'), node('Maya — café ✦'));
  // 500 random strings, because a single mismatch anywhere invalidates every
  // attestation this project will ever issue.
  let mismatches = 0;
  for (let i = 0; i < 500; i++) {
    const s = Math.random().toString(36) + i + '\u0000' + 'y'.repeat(i % 200);
    if (sha256Hex(s) !== node(s)) mismatches++;
  }
  check('L0 sha256','500 random inputs match node:crypto', mismatches, 0);
}

// M · TAMPER-EVIDENT LOG — P8
{
  const c=chainOf(6);
  check('M chain','a fresh chain verifies', verifyChain(c).ok, 'true');
  check('M chain','genesis links to zero', c[0].prevHash, GENESIS);
  check('M chain','each entry links to the previous',
    c.every((e,i)=>i===0||e.prevHash===c[i-1].hash), 'true');

  // Every tamper mode must be caught.
  const edited=c.map((e,i)=>i===3?{...e,body:'I never said that'}:e);
  check('M chain','EDITING a body is caught',
    verifyChain(edited).faults.some(f=>f.kind==='content_altered'&&f.seq===3), 'true');

  const deleted=c.filter((_,i)=>i!==3);
  check('M chain','DELETING an entry is caught',
    verifyChain(deleted).faults.some(f=>f.kind==='chain_broken'||f.kind==='sequence_gap'),
    'true');

  const reordered=[...c]; [reordered[2],reordered[3]]=[reordered[3],reordered[2]];
  check('M chain','REORDERING is caught', verifyChain(reordered).ok, 'false');

  const forged=append(c.slice(0,3),{childId:'m',authorId:'dad',
    at:'2026-01-04T00:00:00Z',body:'inserted'});
  const inserted=[...c.slice(0,3),forged,...c.slice(3)];
  check('M chain','INSERTING is caught', verifyChain(inserted).ok, 'false');

  const rehashed=edited.map(e=>({...e,hash:entryHash(e)}));
  check('M chain','rehashing the edit still breaks the LINK',
    verifyChain(rehashed).faults.some(f=>f.kind==='chain_broken'), 'true');

  const backdated=c.map((e,i)=>i===4?{...e,at:'2020-01-01T00:00:00Z'}:e);
  check('M chain','a backdated entry is flagged',
    verifyChain(backdated).faults.some(f=>f.kind==='time_travel'||f.kind==='content_altered'),
    'true');

  // Length-prefixed framing: field boundaries cannot be shifted.
  const a=entryHash({seq:0,childId:'m',authorId:'ab',at:'t',body:'c',prevHash:GENESIS});
  const b=entryHash({seq:0,childId:'m',authorId:'a',at:'t',body:'bc',prevHash:GENESIS});
  check('M chain','field boundaries cannot be shifted', a===b, 'false');
  check('M chain','an empty chain is vacuously valid', verifyChain([]).ok, 'true');
}

// N · EXPENSE SPLITS — money must not be created or lost
{
  const even={dad:5000,mom:5000}, sixty={dad:6000,mom:4000};
  check('N splits','even split of an even amount',
    JSON.stringify(allocate(10000,even)), '{"dad":5000,"mom":5000}');
  // The classic bug: 3 cents split evenly rounds to 2+2=4.
  const three=allocate(3,even);
  check('N splits','3c split evenly sums to exactly 3',
    three.dad+three.mom, 3);
  check('N splits','and gives the odd cent to one side, not both',
    `${three.dad}/${three.mom}`, '2/1');
  check('N splits','60/40 of 10001c sums exactly',
    Object.values(allocate(10001,sixty)).reduce((a,b)=>a+b,0), 10001);
  check('N splits','1000 random amounts always sum exactly',
    [...Array(1000)].every((_,i)=>
      Object.values(allocate(i*7+1,sixty)).reduce((a,b)=>a+b,0)===i*7+1), 'true');
  check('N splits','three-way split sums exactly',
    Object.values(allocate(100,{a:3333,b:3333,c:3334})).reduce((x,y)=>x+y,0), 100);
  check('N splits','a rule not totalling 10000bp is refused',
    (()=>{try{allocate(100,{a:5000});return 'accepted';}catch{return 'refused';}})(),
    'refused');
  check('N splits','allocation is deterministic',
    JSON.stringify(allocate(3,even))===JSON.stringify(allocate(3,even)), 'true');

  const exp=[{id:'1',childId:'m',paidBy:'dad',amountCents:10000,category:'medical',
    incurredOn:'2026-01-01',status:'accepted'},
    {id:'2',childId:'m',paidBy:'mom',amountCents:6000,category:'school',
     incurredOn:'2026-01-02',status:'accepted'},
    {id:'3',childId:'m',paidBy:'dad',amountCents:9999,category:'x',
     incurredOn:'2026-01-03',status:'disputed'}];
  const net=owedTo(exp,even);
  check('N splits','net position balances to zero', net.dad+net.mom, 0);
  check('N splits','dad fronted more, so he is owed', net.dad>0, 'true');
  check('N splits','a DISPUTED expense is excluded', net.dad, 2000);
}

// O · EXPORT — §2.11 and §16.1 #3
{
  const req=(o={})=>({kind:'certified',childId:'m',requestedBy:'dad',
    courtTier:false,certifiedInLast12Months:0,...o});
  check('O export','§2.11 raw is free off-tier',
    authorizeExport(req({kind:'raw'})).free, 'true');
  check('O export','raw is free even with the allowance spent',
    authorizeExport(req({kind:'raw',certifiedInLast12Months:9})).ok, 'true');
  check('O export',`first certified is free (${FREE_CERTIFIED_PER_YEAR}/yr)`,
    authorizeExport(req()).free, 'true');
  check('O export','second certified off-tier is refused',
    authorizeExport(req({certifiedInLast12Months:1})).reason, 'tier_required');
  check('O export','second certified ON tier is allowed but paid',
    authorizeExport(req({certifiedInLast12Months:1,courtTier:true})).free, 'false');

  const c=chainOf(5);
  const att=certify(c,'m','2026-07-27T00:00:00Z');
  check('O export','attestation reports verification', att.chainVerified, 'true');
  check('O export','head hash matches the last entry', att.headHash, c[4].hash);
  check('O export','independent re-verification passes', verifyExport(c,att).ok, 'true');
  // A judge must be able to detect tampering from the FILE alone.
  const tampered=c.map((e,i)=>i===2?{...e,body:'changed'}:e);
  check('O export','re-verification from the file alone catches tampering',
    verifyExport(tampered,att).ok, 'false');
  check('O export','and says the bundle hash differs',
    verifyExport(tampered,att).reasons.includes('bundle hash differs'), 'true');
  check('O export','a broken chain produces a refusal statement, not a quiet pass',
    certify(tampered,'m','x').statement.startsWith('VERIFICATION FAILED'), 'true');
}

// P · YEAR BOOK AND HANDOVER
{
  const art=(i,kind,y,pres=true)=>({id:`a${i}`,childId:'m',kind,storageKey:`k${i}`,
    capturedAt:`${y}-06-0${(i%9)+1}T15:00:00Z`,capturedTz:NYC,preserved:pres,
    eraTag:null,authorId:'dad'});
  const all=[...Array(14)].map((_,i)=>art(i,['video_msg','drawing','homework','photo'][i%4],2026));
  all.push(art(90,'video_msg',2026,false));          // unpreserved
  all.push(art(91,'video_msg',2025));                 // wrong year

  const yb=compileYearBook(all,'m',2026);
  check('P archive','only PRESERVED artifacts are compiled', yb.artifactCount, 14);
  check('P archive','wrong year excluded',
    yb.sections.every(s=>!s.artifactIds.includes('a91')), 'true');
  check('P archive','sections are named for a child, not a schema',
    yb.sections[0].title, 'Things you said');
  check('P archive','empty sections are dropped',
    yb.sections.every(s=>s.artifactIds.length>0), 'true');
  check('P archive','14 items is printable', yb.printable, 'true');
  check('P archive','3 items is not a book',
    compileYearBook(all.slice(0,3),'m',2026).printable, 'false');
  check('P archive','places are recorded', yb.places[0].zone, NYC);

  const child={id:'m',birthDate:'2008-04-02',majorityAge:18,handedOverAt:null};
  const before=DateTime.fromISO('2026-04-01T12:00:00Z');
  const after=DateTime.fromISO('2026-04-03T12:00:00Z');
  check('P archive','handover refused the day before the birthday',
    handover(child,all,3,before).reason, 'not_yet_of_age');
  const h=handover(child,all,3,after);
  check('P archive','handover allowed on majority', h.ok, 'true');
  check('P archive','every guardianship closes with reason majority',
    h.result.closeGuardianshipsWithReason, 'majority');
  check('P archive','the journal transfers with the archive',
    h.result.transferred.journalEntries, 3);
  check('P archive','an export bundle is generated', h.result.exportBundleRequested, 'true');
  check('P archive','it is irreversible', h.result.irreversible, 'true');
  check('P archive','a second handover is refused',
    handover({...child,handedOverAt:'x'},all,3,after).reason, 'already_handed_over');
  check('P archive','§2.10 — no guardian read path survives handover',
    guardianCanReadAfterHandover(), 'false');
  check('P archive','handover refused for a deceased child (§18.3)',
    handover({...child,deceasedAt:'x'},all,3,after).reason, 'child_deceased');

  // P9 — resurfacing is opt-in with a per-era mute.
  const old=[{...art(1,'photo',2020),eraTag:'pre-separation',
    capturedAt:'2020-07-27T15:00:00Z'}];
  const today=DateTime.fromISO('2026-07-27T15:00:00Z');
  check('P archive','P9 — off by default',
    onThisDay(old,'m',today,NYC,{enabled:false,mutedEras:[]}).length, 0);
  check('P archive','opt-in surfaces the memory',
    onThisDay(old,'m',today,NYC,{enabled:true,mutedEras:[]}).length, 1);
  check('P archive','a muted era stays muted',
    onThisDay(old,'m',today,NYC,{enabled:true,mutedEras:['pre-separation']}).length, 0);
}

// Q · GAMES — turn clocks in reachable hours
{
  const t=DateTime.fromISO('2026-07-27T20:00:00Z');
  let g=newGame('g1',t);
  check('Q games','A moves first', g.turn, 'A');
  check('Q games','B cannot move out of turn', drop(g,'B',0,t).reason, 'not_your_turn');
  g=drop(g,'A',0,t).state;
  check('Q games','turn passes to B', g.turn, 'B');
  check('Q games','out of range refused', drop(g,'B',9,t).reason, 'out_of_range');
  for(let i=0;i<6;i++){ const s=drop(g,g.turn,1,t); if(s.ok) g=s.state; }
  check('Q games','a full column is refused', drop(g,g.turn,1,t).reason, 'column_full');

  // A vertical four for A.
  let w=newGame('g2',t);
  for(let i=0;i<3;i++){ w=drop(w,'A',0,t).state; w=drop(w,'B',1,t).state; }
  w=drop(w,'A',0,t).state;
  check('Q games','a vertical four wins', w.winner, 'A');
  check('Q games','no moves after a win', drop(w,'B',2,t).reason, 'game_over');

  // §4.7 — the clock ticks in REACHABLE hours, not wall hours.
  const g2=newGame('g3',t);
  check('Q games',`budget is ${DEFAULT_TURN_BUDGET_REACHABLE_HOURS} reachable hours`,
    g2.turnBudgetHours, DEFAULT_TURN_BUDGET_REACHABLE_HOURS);
  check('Q games','24 wall hours with 2 reachable does NOT expire a turn',
    turnExpired(g2,2), 'false');
  check('Q games','8 reachable hours does', turnExpired(g2,8), 'true');
}

// R · SCHEDULE STRIP AND SMS
{
  const parts=[{kind:'asleep',startsLocal:'21:00',endsLocal:'06:30',reachable:false},
    {kind:'wake',startsLocal:'06:30',endsLocal:'08:00',reachable:true},
    {kind:'school',startsLocal:'08:00',endsLocal:'15:00',reachable:false},
    {kind:'after_school',startsLocal:'15:00',endsLocal:'18:30',reachable:true}];
  const strip=scheduleStrip(parts,'09:30');
  check('R strip','ordered by start', strip.map(s=>s.kind).join(','),
    'wake,school,after_school,asleep');
  check('R strip','current segment identified',
    strip.find(s=>s.current).kind, 'school');
  check('R strip','what happens next is marked',
    strip.find(s=>s.next).kind, 'after_school');
  check('R strip','labels are friendly, not schema names',
    strip.find(s=>s.kind==='after_school').label, 'home time');
  check('R strip','a midnight-wrapping part is handled',
    scheduleStrip(parts,'23:30').find(s=>s.current).kind, 'asleep');

  // §8.2.2 (v0.39.0) — a static day-part icon lives in the same table as the
  // friendly label, so the two cannot drift apart.
  check('R strip','wake carries the sun-rising glyph',
    strip.find(s=>s.kind==='wake').icon, '🌅');
  check('R strip','school carries the sun glyph',
    strip.find(s=>s.kind==='school').icon, '☀️');
  check('R strip','asleep carries the moon glyph',
    strip.find(s=>s.kind==='asleep').icon, '🌙');
  check('R strip','icon and label are declared for the same day-part',
    strip.every(s=>typeof s.icon==='string'&&s.icon.length>0&&typeof s.label==='string'&&s.label.length>0),
    'true');
  check('R strip','icons are deterministic across repeated calls',
    JSON.stringify(scheduleStrip(parts,'09:30').map(s=>s.icon)),
    JSON.stringify(scheduleStrip(parts,'09:30').map(s=>s.icon)));
  check('R strip','an unrecognised day-part still gets a static fallback icon',
    scheduleStrip([...parts,{kind:'mystery',startsLocal:'19:00',endsLocal:'20:00',reachable:true}],'19:30')
      .find(s=>s.kind==='mystery').icon,
    '•');
  check('R strip','no segment carries an animation/pulse flag on its icon',
    strip.every(s=>!('animated' in s)&&!('pulsing' in s)&&!('pulse' in s)), 'true');

  const sms=buildSms('message_waiting','+15550100');
  check('R sms','audit passes an approved template', auditSms(sms).ok, 'true');
  check('R sms','body names nobody', /Dad|Mom|Maya/.test(sms.body), 'false');
  check('R sms','a custom body is refused',
    auditSms({to:'x',body:'Maya needs her inhaler'}).ok, 'false');
  check('R sms','§10.8 — never the emergency card',
    auditSms({to:'x',body:'Allergic to peanuts'}).ok, 'false');
  check('R sms','never a link',
    auditSms({to:'x',body:'See https://x.example'}).ok, 'false');
  check('R sms','never an amount', auditSms({to:'x',body:'You owe $40'}).ok, 'false');
  check('R sms','guard throws rather than sending a leak',
    (()=>{try{sendSmsGuard({to:'x',body:'Maya is sick'});return 'sent';}
      catch{return 'blocked';}})(), 'blocked');
  check('R sms','every template is audit-clean',
    ['message_waiting','exchange_reminder','call_missed','dose_reminder','schedule_change']
      .every(k=>auditSms(buildSms(k,'+1')).ok), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
