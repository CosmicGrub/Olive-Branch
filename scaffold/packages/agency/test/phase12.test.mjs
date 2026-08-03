/**
 * Phase 1-2 features — annotation, care, agency.
 * MASTERFILE §9.1, §9.3, §9.6, §9.7, §9.9. Prohibitions P2, P3, P4, P7.
 */
import { DateTime } from 'luxon';
import { Canvas, CAN_DRAW, POINTER_TTL_MS } from '../../annotation/src/canvas.mjs';
import { offlineBundle, auditBundle, doseKey, recordDose, prnAllowed,
  manifestOrder, unpacked, recordArrival, auditArrival } from '../../care/src/care.mjs';
import { ping, PING_LIMIT_PER_DAY, pingLimitForAge, PING_BANDS,
  readJournal, ritualsForChild,
  auditChildPayload, childListView, claimNeed } from '../src/agency.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const NYC='America/New_York', CHI='America/Chicago';

// G · ANNOTATION — collaborative undo
{
  const c=new Canvas();
  const s=(actorId,kind,id)=>c.add({id,actorId,actorKind:kind,
    points:[[0,0],[1,1]],color:'#000',widthPx:2});
  s('dad','guardian','d1'); s('maya','child','m1'); s('dad','guardian','d2');
  check('G annotation','three strokes visible', c.visible().length, 3);
  check('G annotation','render order is deterministic',
    c.visible().map(x=>x.id).join(','), 'd1,m1,d2');

  // THE bug a last-on-canvas undo produces: the parent erases the child's work.
  const u=c.undo('dad',1);
  check('G annotation','undo takes the actor OWN last stroke', u.id, 'd2');
  check('G annotation',"the child's stroke survives a parent undo",
    c.visible().some(x=>x.id==='m1'), 'true');
  const u2=c.undo('dad',2);
  check('G annotation','repeated undo walks backwards', u2.id, 'd1');
  check('G annotation','and does not toggle the same stroke', c.undo('dad',3), 'null');
  check('G annotation','only the child stroke remains',
    c.visible().map(x=>x.id).join(','), 'm1');

  const r=c.redo('dad');
  check('G annotation','redo restores the most recently undone', r.id, 'd1');
  check('G annotation','redo is per-actor', c.redo('maya'), 'null');

  // Undo must not reach past another person's deliberate erase.
  const c2=new Canvas();
  c2.add({id:'x1',actorId:'dad',actorKind:'guardian',points:[[0,0]],color:'#000',widthPx:2});
  c2.erase('x1','maya');
  check('G annotation','erase hides the stroke', c2.visible().length, 0);
  check('G annotation','undo cannot resurrect what another actor erased',
    c2.undo('dad',5), 'null');

  // §17.3 — an observer may point but not draw.
  check('G annotation','observer cannot draw', CAN_DRAW.observer, 'false');
  const c3=new Canvas();
  check('G annotation','observer stroke refused',
    c3.add({id:'o',actorId:'mom',actorKind:'observer',points:[[0,0]],
      color:'#000',widthPx:2}).reason, 'observer_readonly');
  check('G annotation','empty stroke refused',
    c3.add({id:'e',actorId:'dad',actorKind:'guardian',points:[],
      color:'#000',widthPx:2}).reason, 'empty');

  // A pointer is a gesture, not ink.
  const c4=new Canvas();
  c4.point({actorId:'dad',x:1,y:2,at:1000});
  check('G annotation','pointer is live briefly', c4.activePointers(1200).length, 1);
  check('G annotation','pointer expires', c4.activePointers(1000+POINTER_TTL_MS+1).length, 0);
  check('G annotation','pointers are NOT persisted with the artifact',
    JSON.stringify(c4.serialize()).includes('pointer'), 'false');
}

// H · EMERGENCY CARD — self-contained, sitter-safe
{
  const card={childId:'c',displayName:'Maya',birthDate:'2016-04-02',bloodType:'O+',
    allergies:[{substance:'Pollen',reaction:'sneezing',severity:'mild'},
               {substance:'Peanuts',reaction:'anaphylaxis',severity:'severe'}],
    conditions:['Asthma'],meds:[{name:'Albuterol',dose:'2 puffs'}],
    providers:[{role:'Pediatrician',name:'Dr Reyes',phone:'555-0100'}],
    guardians:[{name:'Dad',phone:'555-0111'},{name:'Mom',phone:'555-0122'}],
    insurance:{carrier:'BlueCross',memberId:'X1'},updatedAt:'2026-07-01T00:00:00Z'};
  const {bundle,bytes}=offlineBundle(card);
  check('H card','SEVERE allergy sorts first — the reader may stop after line one',
    bundle.allergies[0].substance, 'Peanuts');
  check('H card','both guardians present', bundle.guardians.length, 2);
  check('H card','bundle is small enough to cache offline', bytes<4096, 'true');
  check('H card','no ids to resolve — fully self-contained',
    JSON.stringify(bundle).includes('childId'), 'false');
  check('H card','audit passes on a clean bundle', auditBundle(bundle).ok, 'true');
  check('H card','audit catches an expense leaking in',
    auditBundle({...bundle,expenses:[1]}).ok, 'false');
  check('H card','audit catches an address leaking in',
    auditBundle({...bundle,address:'1 Main St'}).leaks.join(','), 'address');
}

// I · MEDICATION — the exchange-day double dose
{
  const zone=NYC;
  const at8=DateTime.fromISO('2026-07-02T12:00:00Z');       // 8am EDT
  const k=doseKey('m1','morning',at8,zone);
  check('I meds','slot key uses the CHILD local date', k.localDate, '2026-07-02');

  const given=[{...k,administeredAt:at8.toISO(),localTz:CHI,
    byUserName:'Dad',status:'given'}];
  // Mom, in Charlotte, reaches for "the morning dose" four hours later.
  const noon=DateTime.fromISO('2026-07-02T16:00:00Z');
  const k2=doseKey('m1','morning',noon,zone);
  const r=recordDose(given,k2,{administeredAt:noon.toISO(),localTz:NYC,
    byUserName:'Mom',status:'given'});
  check('I meds','second dose in the same child-local slot REFUSED', r.ok, 'false');
  check('I meds','message names the parent and their local time',
    r.error.message, 'Dad gave this dose at 7:00 AM CDT.');
  check('I meds','no blame framing in the message',
    /wrong|error|failed|already been|mistake/i.test(r.error.message), 'false');

  // The next day is a different slot.
  const next=DateTime.fromISO('2026-07-03T12:00:00Z');
  check('I meds','next day is a fresh slot',
    recordDose(given,doseKey('m1','morning',next,zone),
      {administeredAt:next.toISO(),localTz:NYC,byUserName:'Mom',status:'given'}).ok,'true');
  // A skipped dose does not block a later given one.
  check('I meds','a skip does not consume the slot',
    recordDose([{...k,administeredAt:at8.toISO(),localTz:NYC,byUserName:'Dad',
      status:'skipped'}],k2,{administeredAt:noon.toISO(),localTz:NYC,
      byUserName:'Mom',status:'given'}).ok, 'true');
  // PRN is not slot-bound but has a minimum gap.
  check('I meds','PRN allowed when no prior dose', prnAllowed([],'m2',at8,4), 'true');
  check('I meds','PRN refused inside the minimum gap',
    prnAllowed([{medicationId:'m2',localDate:'x',slot:'prn',
      administeredAt:at8.toISO(),localTz:NYC,byUserName:'Dad',status:'given'}],
      'm2',at8.plus({hours:2}),4), 'false');
  check('I meds','PRN allowed after the gap',
    prnAllowed([{medicationId:'m2',localDate:'x',slot:'prn',
      administeredAt:at8.toISO(),localTz:NYC,byUserName:'Dad',status:'given'}],
      'm2',at8.plus({hours:5}),4), 'true');
}

// J · EXCHANGE — manifest and arrival, P3
{
  const items=[{id:'1',label:'Blue rabbit',essential:false,sent:false,returned:false},
    {id:'2',label:'Inhaler',essential:true,sent:false,returned:false},
    {id:'3',label:'Retainer',essential:true,sent:true,returned:false}];
  check('J exchange','essentials sort first',
    manifestOrder(items).slice(0,2).every(i=>i.essential), 'true');
  check('J exchange','essentials sort alphabetically among themselves',
    manifestOrder(items)[0].label, 'Inhaler');
  check('J exchange','unpacked list keeps essentials first',
    unpacked(items)[0].label, 'Inhaler');

  const sched=DateTime.fromISO('2026-07-03T22:00:00Z');
  const a=recordArrival('e1',sched,sched.plus({minutes:4}));
  check('J exchange','delay recorded in minutes', a.delayMinutes, 4);
  check('J exchange','early arrival is not negative delay',
    recordArrival('e1',sched,sched.minus({minutes:10})).delayMinutes, 0);
  check('J exchange','P3 — arrival carries NO location',
    auditArrival(a).ok, 'true');
  check('J exchange','audit catches a latitude smuggled in',
    auditArrival({...a,latitude:35.2}).leaks.join(','), 'latitude');
  check('J exchange','audit catches coords under any casing',
    auditArrival({...a,Coords:'x'}).ok, 'false');
}

// K · CHILD AGENCY — ping, journal, rituals
{
  const now=DateTime.fromISO('2026-07-02T20:00:00Z');
  let hist=[];
  for(let i=0;i<PING_LIMIT_PER_DAY;i++){
    const r=ping(hist,'maya','dad',now,NYC);
    if(r.sent) hist.push({childId:'maya',toUserId:'dad',localDate:'2026-07-02'});
  }
  check('K agency',`first ${PING_LIMIT_PER_DAY} pings send`, hist.length, PING_LIMIT_PER_DAY);
  const over=ping(hist,'maya','dad',now,NYC);
  check('K agency','the fourth is refused', over.sent, 'false');
  check('K agency','and is SILENT — she is never told she used up contact',
    over.silent, 'true');
  check('K agency','no message field exists to scold her',
    'message' in over || 'reason' in over, 'false');
  check('K agency','the other parent has their own budget',
    ping(hist,'maya','mom',now,NYC).sent, 'true');
  check('K agency','a ping respects the recipient day-parts, never overrides',
    ping([], 'maya','dad',now,NYC).policy, 'when_reachable');
  // Tomorrow, in HER zone, resets.
  check('K agency','budget resets on her local day, not UTC',
    ping(hist,'maya','dad',DateTime.fromISO('2026-07-03T05:00:00Z'),NYC).sent, 'true');

  // P7 end to end.
  const entries=[{id:'j1',childId:'maya',body:'private',createdAt:'x'}];
  check('K agency','the child reads her own journal',
    readJournal(entries,'child','maya','maya').entries.length, 1);
  check('K agency','a guardian cannot',
    readJournal(entries,'guardian',null,'maya').reason, 'P7_journal_never');
  check('K agency','nor can another child',
    readJournal(entries,'child','eli','maya').reason, 'P7_journal_never');

  // P2 — rituals carry no score.
  const view=ritualsForChild([{id:'r',childId:'maya',withUserId:'dad',
    label:'Sunday pancakes',daypart:'wake',daysOfWeek:[0],active:true}],
    ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']);
  check('K agency','ritual reads plainly', view[0].whenLabel, 'Sunday at wake');
  check('K agency','P2 — no score reaches the child', auditChildPayload(view).ok, 'true');
  check('K agency','audit catches a streak field',
    auditChildPayload([{...view[0],streak:4}]).leaks.join(','), 'streak');
  check('K agency','audit walks nested objects',
    auditChildPayload({a:{b:[{missed:1}]}}).ok, 'false');
}

// K2 · THE PING SCALE — §16.2 #4, settled
{
  check('K2 ping scale','a five-year-old gets 3', pingLimitForAge(5), 3);
  check('K2 ping scale','an eight-year-old gets 5', pingLimitForAge(8), 5);
  check('K2 ping scale','an eleven-year-old gets 8', pingLimitForAge(11), 8);
  check('K2 ping scale','§21.5 — from 13 there is NO limit', pingLimitForAge(13), 'null');
  check('K2 ping scale','and none at 17 either', pingLimitForAge(17), 'null');
  check('K2 ping scale','the bands only ever increase',
    PING_BANDS.slice(0,3).every((b,i,a)=>i===0||b.perDay>a[i-1].perDay), 'true');

  const now=DateTime.fromISO('2026-07-02T20:00:00Z');
  // A thirteen-year-old is never refused, however many she sends.
  let h=[];
  for(let i=0;i<40;i++) h.push({childId:'maya',toUserId:'dad',localDate:'2026-07-02'});
  check('K2 ping scale','40 pings from a 13-year-old all send',
    ping(h,'maya','dad',now,NYC,13).sent, 'true');
  check('K2 ping scale','but a 6-year-old is still bounded',
    ping(h,'maya','dad',now,NYC,6).sent, 'false');
  check('K2 ping scale','and the refusal is still SILENT',
    ping(h,'maya','dad',now,NYC,6).silent, 'true');
  check('K2 ping scale','an unlimited outcome carries no counter to compare against',
    'silent' in ping([],'maya','dad',now,NYC,15), 'false');
  check('K2 ping scale','omitting age falls back to the safest band',
    ping(h,'maya','dad',now,NYC).sent, 'false');
}

// L · WANTS AND NEEDS — P4 and §2.1
{
  const items=[
    {id:'1',childId:'m',kind:'need',title:'Soccer cleats',claimedBy:'dad'},
    {id:'2',childId:'m',kind:'need',title:'Winter coat',claimedBy:null},
    {id:'3',childId:'m',kind:'want',title:'A bigger sketchbook'}];
  const view=childListView(items);
  check('L list','claimed need reads as handled', view[0].status, 'handled');
  check('L list','unclaimed reads as on the list', view[1].status, 'on the list');
  check('L list','§2.1 — the child never learns WHICH parent claimed',
    JSON.stringify(view).includes('dad'), 'false');
  check('L list','no claim field in the child view at all',
    auditChildPayload(view).ok, 'true');
  check('L list','P4 — no price anywhere in the child view',
    /price|cost|\$|buy/i.test(JSON.stringify(view)), 'false');

  check('L list','a need can be claimed once', claimNeed(items[1],'mom').ok, 'true');
  check('L list','a second claim is refused, not overwritten',
    claimNeed(items[0],'mom').reason, 'already_claimed');
  check('L list','P4 — wants are not claimable',
    claimNeed(items[2],'dad').reason, 'wants_are_not_claimable');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
