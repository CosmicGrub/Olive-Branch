/**
 * showcase — "show me". MASTERFILE §9.10. Prohibitions P2, P5, P9.
 */
import { MATRIX, matrixForAge, childInitiated,
  activeInterests, recededInterests, markShown, RECEDE_AFTER_DAYS,
  promptsFor, GENERIC_PROMPTS, addToCollection, collectionChildView,
  auditShowcase, newShow, replyToShow, showsForYearBook,
  auditFraming, BANNED_FRAMINGS, INTEREST_FORBIDDEN_USES } from '../src/showcase.mjs';
import { MAX_PENDING_ASKS, askForShow, answerAsk, asksChildView,
  askAgeInReachableHours, DEFAULT_REACHABLE_HOURS_PER_DAY } from '../src/exchange.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const NOW='2026-07-27T12:00:00Z';
const ago=(d)=>new Date(Date.parse(NOW)-d*86400000).toISOString();

const dinos={id:'i1',label:'dinosaurs',singular:'dinosaur',addedBy:'B',
  addedAt:ago(200),lastShownAt:ago(3),enumerable:true};
const poke={id:'i2',label:'Pokémon',singular:'Pokémon',addedBy:'A',
  addedAt:ago(90),lastShownAt:ago(10),enumerable:true};
const horses={id:'i3',label:'horses',singular:'horse',addedBy:'B',
  addedAt:ago(400),lastShownAt:ago(300),enumerable:false};

// AT · THE MATRIX
{
  check('AT matrix','eight show types', MATRIX.length, 8);
  check('AT matrix','the floor is a two-year-old holding something up',
    Math.min(...MATRIX.map(m=>m.minAge)), 2);
  check('AT matrix','a four-year-old has most of it', matrixForAge(4).length, 6);
  check('AT matrix','every type says what the PARENT should do',
    MATRIX.every(m=>m.parentRole.length>30), 'true');
  check('AT matrix','most types can be started by the child',
    childInitiated().length>=6, 'true');
  check('AT matrix','"teach me" is child-initiated — the reversal',
    MATRIX.find(m=>m.kind==='teach').initiator, 'child');
  check('AT matrix','spontaneous has no prompt and no schedule',
    MATRIX.find(m=>m.kind==='spontaneous').initiator, 'child');
  check('AT matrix','showing a place is ephemeral — a room is not an artifact',
    MATRIX.find(m=>m.kind==='place').remains, 'ephemeral');
  check('AT matrix','a collection entry is its own kind of record',
    MATRIX.find(m=>m.kind==='collection').remains, 'collection_entry');

  // The framing guard applies to the matrix's own copy.
  check('AT matrix','no row describes her as shy or reluctant',
    MATRIX.every(m=>auditFraming(m.parentRole+' '+m.why).ok), 'true');
}

// AU · INTERESTS — recorded lightly, expire gently, never resurfaced
{
  const all=[dinos,poke,horses];
  check('AU interests','current interests are active', activeInterests(all,NOW).length, 2);
  check('AU interests','an old one has receded',
    recededInterests(all,NOW).map(i=>i.label).join(), 'horses');
  check('AU interests',`the line is ${RECEDE_AFTER_DAYS} days`, RECEDE_AFTER_DAYS, 120);
  check('AU interests','nothing is ever deleted — she may come back',
    all.length, 3);
  check('AU interests','showing one revives it',
    activeInterests(markShown(all,'i3',NOW),NOW).length, 3);
  check('AU interests','an interest with no shows yet is active from when it was added',
    activeInterests([{...dinos,id:'x',lastShownAt:null,addedAt:ago(5)}],NOW).length, 1);
  check('AU interests','...and receded if it was added long ago and never shown',
    activeInterests([{...dinos,id:'y',lastShownAt:null,addedAt:ago(300)}],NOW).length, 0);

  // P9 — a receded interest is never surfaced to HER.
  const prompts=promptsFor('object',all,NOW,20).join(' ');
  check('AU interests','P9 — a receded interest generates no prompt for her',
    /horse/i.test(prompts), 'false');
  check('AU interests','and the phrase "used to like" appears nowhere',
    /used to (like|love)/i.test(JSON.stringify({MATRIX,GENERIC_PROMPTS})), 'false');

  // P5 — interests are family context and nothing else.
  check('AU interests','P5 — the forbidden-uses list names ad targeting',
    INTEREST_FORBIDDEN_USES.includes('ad_targeting'), 'true');
  check('AU interests','and model training', INTEREST_FORBIDDEN_USES.includes('model_training'), 'true');
}

// AV · PROMPTS — parameterised, so an unanticipated interest works
{
  const p=promptsFor('object',[dinos],NOW,10);
  check('AV prompts','generated from the interest',
    p.some(x=>/favourite dinosaur/i.test(x)), 'true');
  check('AV prompts','plural and singular both used correctly',
    p.some(x=>/dinosaurs/.test(x))&&p.some(x=>/dinosaur\b/.test(x)), 'true');

  const k=promptsFor('knowledge',[poke],NOW,10);
  check('AV prompts','knowledge prompts make HER the expert',
    k.some(x=>/Teach me something about Pokémon/i.test(x)), 'true');
  check('AV prompts','"which would win" works for any set',
    k.some(x=>/Which Pokémon would win/i.test(x)), 'true');

  // The real test: something nobody anticipated.
  const odd={...dinos,id:'z',label:'washing machines',singular:'washing machine'};
  const o=promptsFor('object',[odd],NOW,10);
  check('AV prompts','an unanticipated interest generates real prompts',
    o.some(x=>/favourite washing machine/i.test(x)), 'true');
  check('AV prompts','no template leaks a placeholder',
    promptsFor('collection',[odd,dinos,poke],NOW,30).every(x=>!/[{}]/.test(x)), 'true');

  // A child with nothing recorded is never worse off.
  const none=promptsFor('creation',[],NOW,5);
  check('AV prompts','generic prompts exist with no interests at all', none.length>0, 'true');
  check('AV prompts','and they need no interest',
    none.every(x=>!/[{}]/.test(x)), 'true');
  check('AV prompts','every show kind has a generic fallback',
    MATRIX.filter(m=>m.kind!=='spontaneous')
      .every(m=>(GENERIC_PROMPTS[m.kind]||[]).length>0), 'true');
}

// AW · COLLECTIONS — a record, never a target
{
  let c={interestId:'i1',entries:[]};
  check('AW collection','an empty one invites a first', collectionChildView(c).line,
    'Show me your first one.');
  const add=(n)=>{ const r=addToCollection(c,{id:n,interestId:'i1',name:n,
    artifactId:'a-'+n,shownAt:NOW}); if(r.ok) c=r.collection; return r; };
  add('Stegosaurus');
  check('AW collection','singular reads naturally', collectionChildView(c).line,
    'You have shown me one so far.');
  add('Triceratops'); add('Diplodocus');
  check('AW collection','then counts', collectionChildView(c).line,
    'You have shown me 3 of them.');
  check('AW collection','the newest is named', collectionChildView(c).newest, 'Diplodocus');
  check('AW collection','a duplicate is refused', add('stegosaurus').reason, 'duplicate');

  // P2 — no denominator anywhere. Pokémon has over a thousand.
  const v=collectionChildView(c);
  check('AW collection','P2 — no total, no percentage, no "missing"',
    auditShowcase(v).ok, 'true');
  check('AW collection','the view has no total field at all',
    Object.keys(v).some(k=>/total|percent|goal|missing/i.test(k)), 'false');
  check('AW collection','audit catches a completion bar',
    auditShowcase({...v,percentComplete:12}).leaks.join(','), 'percentComplete');
  check('AW collection','audit walks nested payloads',
    auditShowcase({a:{b:[{remaining:900}]}}).ok, 'false');
}

// AX · THE SHOW ITSELF
{
  const s=newShow('s1','creation','maya',NOW,{prompt:'Show me what you made',
    artifactId:'art-1',interestId:'i1'});
  check('AX show','§9.8.1 — a show is preserved', s.preserved, 'true');
  check('AX show','an unprompted show has no prompt — the best case',
    newShow('s2','spontaneous','maya',NOW).prompt, 'null');

  const r=replyToShow(s,{artifactId:'reply-1'},NOW);
  check('AX show','the parent can reply in kind', r.ok, 'true');
  check('AX show','an empty reply is refused', replyToShow(s,{text:'  '}).reason, 'empty');
  check('AX show','replying twice is refused',
    replyToShow(r.show,{text:'again'},NOW).reason, 'already_replied');

  const shows=[
    newShow('a','creation','maya','2026-03-01T10:00:00Z',{artifactId:'x1'}),
    newShow('b','creation','maya','2026-04-01T10:00:00Z',{artifactId:'x2'}),
    newShow('c','knowledge','maya','2026-05-01T10:00:00Z',{artifactId:'x3'}),
    newShow('d','creation','maya','2025-05-01T10:00:00Z',{artifactId:'old'}),
    newShow('e','object','maya','2026-06-01T10:00:00Z'),   // no artifact
  ];
  const yb=showsForYearBook(shows,2026);
  check('AX show','§9.8.2 — grouped for the Year Book', yb.length, 2);
  check('AX show','biggest section first', yb[0].section, 'Things you made');
  check('AX show','and it counts only this year', yb[0].count, 2);
  check('AX show','a show with no artifact is not counted',
    yb.some(x=>x.section==='Things you showed me'), 'false');
  check('AX show','the knowledge section is named from HER side',
    yb[1].section, 'Things you taught me');
}

// AY · THE FRAMING GUARD
{
  check('AY framing','a neutral sentence passes',
    auditFraming('Show me your favourite dinosaur').ok, 'true');
  check('AY framing','"gets her talking" is refused',
    auditFraming('A game that gets her talking').ok, 'false');
  check('AY framing','and so does the past tense — stems, not conjugations',
    auditFraming('It got her talking').ok, 'false');
  check('AY framing','"won\'t talk" is refused',
    auditFraming("for a child who won't talk").ok, 'false');
  check('AY framing','but ordinary uses of "talk" are fine',
    auditFraming('You can talk while you draw').ok, 'true');
  check('AY framing','"draw her out" is refused',
    auditFraming('a gentle way to draw her out').ok, 'false');
  check('AY framing','"comes out of her shell" is refused',
    auditFraming('Watch her come out of her shell').ok, 'false');
  check('AY framing','"shy" is refused', auditFraming('perfect for a shy child').ok, 'false');
  check('AY framing','"break the ice" is refused',
    auditFraming('a great way to break the ice').ok, 'false');
  check('AY framing','the banned list is substantial', BANNED_FRAMINGS.length>=15, 'true');
  check('AY framing','no generic prompt trips the guard',
    Object.values(GENERIC_PROMPTS).flat().every(p=>auditFraming(p).ok), 'true');
}

// AZ · ASKFORSHOW — the three-slot FIFO cap
{
  const mk=(id,askedAt)=>({id,fromUserId:'B',fromLabel:'Daddy',prompt:`prompt ${id}`,askedAt});
  let pending=[];
  let r=askForShow(pending,mk('a1',ago(4)));
  check('AZ askForShow','the first ask is never displaced', r.displaced, 'null');
  pending=r.asks;
  r=askForShow(pending,mk('a2',ago(3))); pending=r.asks;
  r=askForShow(pending,mk('a3',ago(2))); pending=r.asks;
  check('AZ askForShow',`a third ask fills the cap at ${MAX_PENDING_ASKS}`, pending.length, MAX_PENDING_ASKS);
  check('AZ askForShow','nothing displaced yet', r.displaced, 'null');

  r=askForShow(pending,mk('a4',ago(1)));
  check('AZ askForShow','a fourth push displaces the oldest silently', r.displaced.id, 'a1');
  check('AZ askForShow','the list stays capped at three', r.asks.length, MAX_PENDING_ASKS);
  check('AZ askForShow','the survivors are the three most recent, oldest first',
    r.asks.map(a=>a.id).join(','), 'a2,a3,a4');
  check('AZ askForShow','the newest ask is present', r.asks.some(a=>a.id==='a4'), 'true');
  check('AZ askForShow','the displaced ask is gone from the list',
    r.asks.some(a=>a.id==='a1'), 'false');

  // Already-answered asks are open no longer — they should never count toward
  // the cap, so a full house of ANSWERED asks does not displace anything.
  const answered=[mk('b1',ago(9)),mk('b2',ago(8)),mk('b3',ago(7))]
    .map(a=>({...a,answeredWithShowId:'some-show'}));
  const r2=askForShow(answered,mk('b4',ago(1)));
  check('AZ askForShow','answered asks do not count toward the cap',
    r2.displaced, 'null');
  check('AZ askForShow','and askForShow only ever tracks the OPEN asks going forward',
    r2.asks.map(a=>a.id).join(','), 'b4');
}

// BA · ANSWERASK
{
  const mk=(id,askedAt)=>({id,fromUserId:'B',fromLabel:'Daddy',prompt:`prompt ${id}`,askedAt,answeredWithShowId:null});
  const pending=[mk('x1',ago(2)),mk('x2',ago(1))];
  const answered=answerAsk(pending,'x1','show-99');
  check('BA answerAsk','the matching ask is answered',
    answered.find(a=>a.id==='x1').answeredWithShowId, 'show-99');
  check('BA answerAsk','the other ask is untouched',
    answered.find(a=>a.id==='x2').answeredWithShowId, 'null');
  check('BA answerAsk','the input array is not mutated',
    pending.find(a=>a.id==='x1').answeredWithShowId, 'null');
  check('BA answerAsk','an answered ask drops out of the child view',
    asksChildView(answered).length, 1);
  check('BA answerAsk','an unknown askId is a no-op',
    answerAsk(pending,'nope','show-1').every(a=>a.answeredWithShowId===null), 'true');
}

// BB · ASKAGEINREACHABLEHOURS — the v0.42.0 amendment (§9.10.7, §8.15)
{
  check('BB reachable age',`the default mirrors phase3's turn budget of 8`,
    DEFAULT_REACHABLE_HOURS_PER_DAY, 8);

  const mk=(id,askedAt)=>({id,fromUserId:'B',fromLabel:'Daddy',prompt:'p',askedAt,answeredWithShowId:null});

  // Ask A: made 30 wall-clock hours ago, right before a long school-and-sleep
  // stretch — she has had almost no REACHABLE exposure to it since.
  const askA=mk('ra',ago(30/24));
  // Ask B: made only 6 wall-clock hours ago, during her free time — nearly
  // all of that time has actually been reachable.
  const askB=mk('rb',ago(6/24));

  const wallHoursA=(Date.parse(NOW)-Date.parse(askA.askedAt))/3600000;
  const wallHoursB=(Date.parse(NOW)-Date.parse(askB.askedAt))/3600000;
  check('BB reachable age','sanity — wall clock alone puts A (30h) older than B (6h)',
    wallHoursA>wallHoursB, 'true');

  const reachableA=askAgeInReachableHours(askA,NOW,2);   // 2 reachable h/day
  const reachableB=askAgeInReachableHours(askB,NOW,20);  // 20 reachable h/day
  check('BB reachable age','A ages to far less than its 30 wall-clock hours',
    reachableA, 2.5);
  check('BB reachable age','B ages close to its 6 wall-clock hours',
    reachableB, 5);
  check('BB reachable age','reachable-hours weighting REORDERS which ask looks oldest — '
    +'B now outranks A despite being wall-clock younger',
    reachableB>reachableA, 'true');

  check('BB reachable age','an ask with no elapsed time has zero age',
    askAgeInReachableHours(mk('rc',NOW),NOW,DEFAULT_REACHABLE_HOURS_PER_DAY), 0);
  check('BB reachable age','an askedAt after now clamps to zero, never negative',
    askAgeInReachableHours(mk('rd',ago(-2)),NOW,DEFAULT_REACHABLE_HOURS_PER_DAY), 0);
  check('BB reachable age','a full reachable day (24h/day) matches wall-clock hours exactly',
    askAgeInReachableHours(mk('re',ago(3)),NOW,24), 72);
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
