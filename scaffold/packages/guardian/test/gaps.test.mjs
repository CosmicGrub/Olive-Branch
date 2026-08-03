/**
 * The thirteen gaps. MASTERFILE §9.10.7–11, §12.4–7, §9.13.
 */
import { askForShow, answerAsk, asksChildView, MAX_PENDING_ASKS, ASK_FORBIDDEN,
  replyGuidance, shelf, shelfChildView, PARENT_SHOWS, parentShowsFor,
  offerableParentShows, gallery, frameFor, hideWork, compileExhibition,
  MIN_WORKS_FOR_EXHIBITION, auditGallery }
  from '../../showcase/src/exchange.mjs';
import { briefing, MAX_BRIEFING_FACTS, auditBriefing, writeCareNote,
  careNoteVisibleTo, CARE_NOTE_TTL_DAYS, CARE_NOTE_BANNED, catchUp,
  MAX_CATCHUP_GROUPS, auditCatchUp, inbox, admitToInbox, isActionable,
  resolve, inboxVisibleTo, INBOX_ACTIONS } from '../src/guardian.mjs';
import { beginClosing, shouldOfferClosing, closingNext, skipClosing, closingLines,
  closingToAsk, GOODBYES, RITUAL_OFFER_AFTER_SECONDS,
  beginReading, turnPage, canGoBack, swapReader, bookmarkReading, readingChildView,
  requestHandoff, handoffExpired, HANDOFF_MAX_SECONDS, HANDOFF_IN_COURT_LOG,
  busyFork, auditBusyFork, attemptVisibleToChild, BUSY_BANNED }
  from '../../live/src/around.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const T='2026-07-27T18:00:00Z';

// CG · PENDING ASKS — capped, so it never becomes a backlog of guilt
{
  const mk=(i)=>({id:'a'+i,fromUserId:'dad',fromLabel:'Daddy',
    prompt:'Show me something '+i,askedAt:`2026-07-2${i}T09:00:00Z`});
  let r=askForShow([],mk(1)); let asks=r.asks;
  check('CG asks','one ask', asks.length, 1);
  asks=askForShow(asks,mk(2)).asks; asks=askForShow(asks,mk(3)).asks;
  check('CG asks',`capped at ${MAX_PENDING_ASKS}`, asks.length, 3);
  const fourth=askForShow(asks,mk(4));
  check('CG asks','a fourth does not stack', fourth.asks.length, 3);
  check('CG asks','the OLDEST is displaced', fourth.displaced.id, 'a1');
  check('CG asks','and she is never told it happened',
    'notified' in fourth, 'false');

  const v=asksChildView(fourth.asks);
  check('CG asks','she sees who asked, by his own word', v[0].line, 'Daddy asked you something');
  check('CG asks','no count reaches her', JSON.stringify(v).includes('count'), 'false');
  check('CG asks','and no age — a four-day-old ask looks like this morning\'s',
    ASK_FORBIDDEN.includes('daysAgo')&&ASK_FORBIDDEN.includes('overdue'), 'true');
  const answered=answerAsk(fourth.asks,'a2','show-9');
  check('CG asks','answering links the show', answered.find(a=>a.id==='a2').answeredWithShowId, 'show-9');
  check('CG asks','and it leaves her list', asksChildView(answered).length, 2);
}

// CH · REPLY IN KIND — nudged, never refused
{
  const g=replyGuidance('spontaneous','text');
  check('CH reply','a text reply to a spontaneous show is nudged', Boolean(g.nudge), 'true');
  check('CH reply','and the nudge names the failure mode',
    /"Nice!" is the reply that ends it/.test(g.nudge), 'true');
  check('CH reply','it is NOT refused — some reply beats none',
    'refused' in g, 'false');
  check('CH reply','an artifact reply gets no nudge',
    replyGuidance('spontaneous','artifact').nudge, 'null');
  check('CH reply','voice counts as in kind',
    replyGuidance('creation','voice').nudge, 'null');
  check('CH reply','a knowledge show is fine to answer in words',
    replyGuidance('knowledge','text').nudge, 'null');
}

// CI · THE SHELF
{
  const cols=[
    {interestId:'i1',entries:[{name:'Stegosaurus',shownAt:'2026-07-20T10:00:00Z'},
      {name:'Diplodocus',shownAt:'2026-07-26T10:00:00Z'}]},
    {interestId:'i2',entries:[{name:'Bulbasaur',shownAt:'2026-06-01T10:00:00Z'}]}];
  const ints=[{id:'i1',label:'dinosaurs'},{id:'i2',label:'Pokémon'}];
  const sh=shelf(cols,ints);
  check('CI shelf','both collections', sh.length, 2);
  check('CI shelf','most recently added to first', sh[0].label, 'dinosaurs');
  check('CI shelf','with the newest entry named', sh[0].newest, 'Diplodocus');
  check('CI shelf','counts are on the parent side', sh[0].count, 2);
  const cv=shelfChildView(sh);
  check('CI shelf','P2 — no counts in her view',
    JSON.stringify(cv).includes('count'), 'false');
  check('CI shelf','but she still sees what is newest', cv[0].newest, 'Diplodocus');
  check('CI shelf','an unknown interest degrades gracefully',
    shelf([{interestId:'zz',entries:[]}],ints)[0].label, 'things');
}

// CJ · HE SHOWS HER HIS WORLD — the gap that mattered most
{
  check('CJ reciprocity','nine things he can show her', PARENT_SHOWS.length, 9);
  check('CJ reciprocity','the first is where she sleeps', PARENT_SHOWS[0].kind, 'where_you_sleep');
  check('CJ reciprocity','and it says why it matters most',
    /arrives differently/.test(PARENT_SHOWS[0].because), 'true');
  check('CJ reciprocity','a two-year-old can receive two of them',
    parentShowsFor(2).length, 2);
  check('CJ reciprocity','and they are the two that need no words',
    parentShowsFor(2).map(s=>s.kind).join(','), 'where_you_sleep,my_room');
  check('CJ reciprocity','a five-year-old gets all nine', parentShowsFor(5).length, 9);
  check('CJ reciprocity','every one gives HIM a reason, not a label',
    PARENT_SHOWS.every(s=>/[.!]$/.test(s.because.trim())
      && s.because.length > s.title.length), 'true');
  check('CJ reciprocity','and none of the reasons is a single word',
    PARENT_SHOWS.every(s=>s.because.trim().split(/\s+/).length>=6), 'true');

  // The one the product must never suggest.
  const meet=PARENT_SHOWS.find(s=>s.kind==='someone_you_will_meet');
  check('CJ reciprocity','"someone you will meet" is not offerable', meet.offerable, 'false');
  check('CJ reciprocity','because it belongs to a conversation, not a prompt deck',
    /will not suggest/.test(meet.because), 'true');
  check('CJ reciprocity','so it never appears in an offer',
    offerableParentShows(12).some(s=>s.kind==='someone_you_will_meet'), 'false');
  check('CJ reciprocity','but it still exists for when he is ready',
    parentShowsFor(12).some(s=>s.kind==='someone_you_will_meet'), 'true');
}

// CK · THE GALLERY — cardboard counts
{
  const w=(i,medium,year,hidden=false)=>({id:'w'+i,artifactId:'art'+i,
    title:i%2?null:'A thing',medium,madeAt:`${year}-0${(i%9)+1}-11T10:00:00Z`,
    interestId:'i1',hiddenByChild:hidden,preserved:true});
  const works=[w(1,'digital_paint',2026),w(2,'photo_of_physical',2026),
    w(3,'colouring',2026),w(4,'collage',2025),w(5,'photo_she_took',2025),
    w(6,'photo_of_physical',2025),w(7,'digital_paint',2024),
    w(8,'photo_of_physical',2024),w(9,'colouring',2024,true)];

  const rooms=gallery(works,'guardian');
  check('CK gallery','grouped by year', rooms.length, 3);
  check('CK gallery','newest year first', rooms[0].year, 2026);
  check('CK gallery','a hidden work is not shown to a guardian',
    rooms.some(r=>r.works.some(x=>x.id==='w9')), 'false');
  check('CK gallery','but SHE still sees her own hidden work',
    gallery(works,'child').some(r=>r.works.some(x=>x.id==='w9')), 'true');

  // The whole point.
  const frames=works.map(frameFor);
  check('CK gallery','every medium is framed identically',
    new Set(frames.map(f=>JSON.stringify(f))).size, 1);
  check('CK gallery','photographed physical art carries no badge',
    frameFor(w(2,'photo_of_physical',2026)).badge, 'null');
  check('CK gallery','and is exactly the same size as a digital painting',
    frameFor(w(2,'photo_of_physical',2026)).width,
    frameFor(w(1,'digital_paint',2026)).width);

  // §21.2 rung 16.
  check('CK gallery','a guardian may never hide a work',
    hideWork(works,'w1','guardian',true).reason, 'guardian_cannot_curate');
  check('CK gallery','nor unhide one she hid',
    hideWork(works,'w9','guardian',false).ok, 'false');
  check('CK gallery','she can', hideWork(works,'w1','child',true).ok, 'true');

  const ex=compileExhibition(works,'Olive');
  check('CK gallery','an exhibition compiles', ex.ok, 'true');
  check('CK gallery','hidden work is excluded', ex.exhibition.meta.workCount, 8);
  check('CK gallery','oldest first — a growing-up, not a best-of',
    ex.exhibition.plates[0].artifactId, 'art7');
  check('CK gallery','the note says the thing',
    ex.exhibition.note, 'Cardboard counts. It always did.');
  check('CK gallery','all five media appear', ex.exhibition.meta.mediums.length, 5);
  check('CK gallery',`under ${MIN_WORKS_FOR_EXHIBITION} works is refused`,
    compileExhibition(works.slice(0,3),'Olive').reason, 'too_few');
  check('CK gallery','no rating, grade or quality field anywhere',
    auditGallery(ex.exhibition).ok, 'true');
  check('CK gallery','audit catches a rating',
    auditGallery({...ex.exhibition,rating:4}).ok, 'false');
  check('CK gallery','and catches "improvement", which is worse',
    auditGallery({a:[{improvement:'much better'}]}).leaks.join(','), 'improvement');
}

// CL · THE PRE-CALL BRIEFING
{
  const b=briefing({childName:'Olive',activeInterests:['dinosaurs','Pokémon'],
    lastShow:{kind:'creation',caption:'a Diplodocus',daysAgo:1},
    tomorrow:{label:'swimming'},stuckHomework:{subject:'counting to twenty'},
    colourLabel:'coral pink',sleepsUntilNext:2});
  check('CL brief',`capped at ${MAX_BRIEFING_FACTS} facts`, b.facts.length, 3);
  check('CL brief','the most specific fact leads',
    b.facts[0].text, 'She showed you a Diplodocus yesterday.');
  check('CL brief','one opener, not a list', typeof b.opener, 'string');
  check('CL brief','and it points at the show first',
    /before anything else/.test(b.opener), 'true');
  check('CL brief','it warns him not to work through it',
    /Do not work through this like a list/.test(b.caution), 'true');

  // Ordering when there is no recent show.
  const b2=briefing({childName:'Olive',activeInterests:[],lastShow:null,
    tomorrow:null,stuckHomework:{subject:'fractions'},colourLabel:null,
    sleepsUntilNext:null});
  check('CL brief','with homework and nothing else, it says DO NOT lead with it',
    /Do not lead with the homework/.test(b2.opener), 'true');
  const b3=briefing({childName:'Olive',activeInterests:[],lastShow:null,
    tomorrow:null,stuckHomework:null,colourLabel:null,sleepsUntilNext:null});
  check('CL brief','with nothing at all it falls back to "ask her to show you"',
    /show you something/.test(b3.opener), 'true');
  check('CL brief','and an empty briefing has no facts', b3.facts.length, 0);

  // P7.
  check('CL brief','P7 — nothing from her journal', auditBriefing(b).ok, 'true');
  check('CL brief','audit catches a journal leak',
    auditBriefing({...b,facts:[{kind:'interest',text:'Her journal says she is sad.'}],
      opener:'x'}).leaks.join(','), 'journal');
  check('CL brief','and catches a mood inference',
    auditBriefing({...b,opener:'Her mood has been low.'}).ok, 'false');
}

// CM · THE HANDOFF CARE NOTE
{
  const ok=writeCareNote('n1','olive','mum',
    [{kind:'sleep',note:'She was awake until half ten, so she may be short today.'},
     {kind:'health',note:'A bit of a cough. Nothing in it.'}],T);
  check('CM care','written', ok.ok, 'true');
  check('CM care',`expires in ${CARE_NOTE_TTL_DAYS} days`,
    ok.note.expiresAt.slice(0,10), '2026-08-03');
  check('CM care','it is NOT evidence', ok.note.inCourtLog, 'false');
  check('CM care','and the child never sees it', ok.note.visibleToChild, 'false');
  check('CM care','a guardian does', careNoteVisibleTo('guardian'), 'true');
  check('CM care','a child does not', careNoteVisibleTo('child'), 'false');
  check('CM care','an empty note is refused',
    writeCareNote('n2','olive','mum',[{kind:'mood',note:'  '}],T).reason, 'empty');

  // The tone guard — a dig disguised as care is the hardest kind to call out.
  const dig=writeCareNote('n3','olive','mum',
    [{kind:'sleep',note:'She never sleeps at your house, as usual.'}],T);
  check('CM care','an accusation is REFUSED, not softened', dig.ok, 'false');
  check('CM care','and it names what tripped', dig.found.includes('as usual'), 'true');
  check('CM care','"you never" is refused',
    writeCareNote('n4','olive','mum',[{kind:'mood',note:'You never tell me anything.'}],T).ok,
    'false');
  check('CM care','"she says you" is refused — the child as ammunition',
    writeCareNote('n5','olive','mum',[{kind:'social',note:'She says you shouted.'}],T).ok,
    'false');
  check('CM care','"at your house she" is refused',
    writeCareNote('n6','olive','mum',[{kind:'appetite',note:'At your house she eats rubbish.'}],T).ok,
    'false');
  check('CM care','the banned list is substantial', CARE_NOTE_BANNED.length>=15, 'true');
  check('CM care','ordinary care passes',
    writeCareNote('n7','olive','mum',[{kind:'school',note:'Spelling test on Friday.'}],T).ok,
    'true');
}

// CN · THE CATCH-UP — never a guilt trip
{
  const ev=[
    {kind:'show',at:'2026-07-24T10:00:00Z'},{kind:'show',at:'2026-07-25T10:00:00Z'},
    {kind:'show',at:'2026-07-26T10:00:00Z'},{kind:'drawing',at:'2026-07-25T11:00:00Z'},
    {kind:'story',at:'2026-07-26T20:00:00Z'},{kind:'expense',at:'2026-07-26T09:00:00Z'},
    {kind:'calendar',at:'2026-07-27T08:00:00Z'},{kind:'care_note',at:'2026-07-27T07:00:00Z'},
    {kind:'message',at:'2026-07-20T10:00:00Z'}];
  const c=catchUp('2026-07-23T00:00:00Z',ev);
  check('CN catchup',`capped at ${MAX_CATCHUP_GROUPS} groups`, c.groups.length, 4);
  check('CN catchup','largest group first', c.groups[0].line, 'She showed you 3 things');
  check('CN catchup','older events are excluded',
    JSON.stringify(c).includes('messages from her'), 'false');
  check('CN catchup','ONE thing to do, not a list', typeof c.firstThing, 'string');
  check('CN catchup','and it is the show, not the expense',
    /showed you/.test(c.firstThing), 'true');
  check('CN catchup','singular reads correctly',
    catchUp('2026-07-26T00:00:00Z',ev).groups.some(g=>g.line==='She showed you something'),
    'true');
  check('CN catchup','no "you missed" anywhere', auditCatchUp(c).ok, 'true');
  check('CN catchup','audit catches an unread count',
    auditCatchUp({...c,unread:14}).leaks.join(','), 'unread');
  check('CN catchup','and catches lastSeen',
    auditCatchUp({a:{lastSeen:'5 days'}}).ok, 'false');
  check('CN catchup','the copy never mentions the gap itself',
    /missed|absent|away|inactive/i.test(JSON.stringify(c)), 'false');
}

// CO · THE COORDINATION INBOX — actionable only
{
  const it=(id,kind,at,by=null)=>({id,kind,summary:'Something',fromUserId:'mum',
    at,actions:INBOX_ACTIONS[kind]||[],resolvedAt:null,respondBy:by});
  const items=[it('1','expense_approval','2026-07-20T10:00:00Z'),
    it('2','schedule_change','2026-07-26T10:00:00Z','2026-07-29T00:00:00Z'),
    it('3','invitation','2026-07-22T10:00:00Z'),
    {...it('4','document_request','2026-07-19T10:00:00Z'),resolvedAt:T}];
  const box=inbox(items);
  check('CO inbox','resolved items drop out', box.length, 3);
  check('CO inbox','a real deadline comes first', box[0].id, '2');
  check('CO inbox','then oldest, because it has kept somebody waiting', box[1].id, '1');
  check('CO inbox','every item carries its actions', box.every(i=>i.actions.length>=1), 'true');
  check('CO inbox','an expense offers three', INBOX_ACTIONS.expense_approval.length, 3);
  check('CO inbox','including querying it rather than only yes/no',
    INBOX_ACTIONS.expense_approval.includes('Query it'), 'true');

  // The rule that stops it becoming a feed.
  check('CO inbox','an informational item is REFUSED entry',
    admitToInbox({kind:'she_drew_something'}).reason, 'not_actionable');
  check('CO inbox','an actionable one is admitted',
    admitToInbox({kind:'schedule_change'}).ok, 'true');
  check('CO inbox','isActionable is the single gate',
    isActionable('news_digest'), 'false');
  check('CO inbox','resolving removes it',
    inbox(resolve(items,'2',T)).length, 2);
  check('CO inbox','§2.4 — the inbox is adult-only', inboxVisibleTo('child'), 'false');
  check('CO inbox','a guardian sees it', inboxVisibleTo('guardian'), 'true');
}

// CP · THE CLOSING RITUAL
{
  check('CP closing','not offered at the start', shouldOfferClosing(30,false), 'false');
  check('CP closing',`offered after ${RITUAL_OFFER_AFTER_SECONDS}s`,
    shouldOfferClosing(200,false), 'true');
  check('CP closing','and only once', shouldOfferClosing(400,true), 'false');

  let c=beginClosing();
  check('CP closing','the forward-looking beat is first', c.beat, 'one_thing');
  check('CP closing','and it asks what she will show him',
    closingLines(c).prompt, 'What will you show me next time?');
  c=closingNext(c,{oneThing:'my wobbly tooth'});
  check('CP closing','then the certain thing', c.beat, 'when_next');
  c=closingNext(c,{nextTime:'Friday after school'});
  check('CP closing','which is never invented',
    closingNext(beginClosing(),{oneThing:'x'}).nextTime, 'null');
  // One advance lands on 'when_next', where nextTime is not yet known.
  check('CP closing','and says so honestly when unknown',
    /Nobody is pretending to know yet/.test(
      closingLines(closingNext(beginClosing(),{oneThing:'x'})).sub), 'true');
  check('CP closing','whereas a known time is stated as fact',
    closingLines(closingNext(closingNext(beginClosing(),{oneThing:'x'}),
      {nextTime:'Friday'})).prompt, 'How shall we say goodbye?');
  c=closingNext(c,{goodbye:GOODBYES[0]});
  check('CP closing','then the goodbye', c.beat, 'done');
  check('CP closing','which is not the word "bye"',
    GOODBYES.every(g=>g.toLowerCase()!=='bye'), 'true');

  check('CP closing','skippable at any beat', skipClosing(beginClosing()).beat, 'done');
  check('CP closing','and the skip is recorded, not punished',
    skipClosing(beginClosing()).skipped, 'true');

  // The forward beat becomes a real ask.
  const ask=closingToAsk(c,'dad','Daddy',T);
  check('CP closing','§9.10.7 — it becomes an ask waiting for her tomorrow',
    ask.prompt, 'Show me my wobbly tooth');
  check('CP closing','a skipped ritual produces no ask',
    closingToAsk(skipClosing(beginClosing()),'dad','Daddy',T), 'null');
}

// CQ · SHARED READING — she turns the pages
{
  let s=beginReading('The Tiger Who Came to Tea',32,'B');
  check('CQ reading','he reads', s.reader, 'B');
  check('CQ reading','SHE turns', s.turner, 'A');
  check('CQ reading','starts at page one', s.page, 1);
  check('CQ reading','he cannot turn her page',
    turnPage(s,'B',1).reason, 'not_your_page_to_turn');
  const t=turnPage(s,'A',1);
  check('CQ reading','she can', t.ok, 'true');
  s=t.session;
  check('CQ reading','turning BACK is allowed and not an error',
    turnPage(s,'A',-1).ok, 'true');
  check('CQ reading','because children do it constantly', canGoBack(s), 'true');
  check('CQ reading','not before page one',
    turnPage(beginReading('B',10),'A',-1).reason, 'at_the_start');
  check('CQ reading','nor past the end',
    turnPage(beginReading('B',3,'B',3),'A',1).reason, 'at_the_end');

  const sw=swapReader(s);
  check('CQ reading','some nights she reads', sw.reader, 'A');
  check('CQ reading','and then he turns', sw.turner, 'B');
  check('CQ reading','a bookmark remembers the page', bookmarkReading(s).bookmarkedAt, s.page);
  check('CQ reading','resuming starts there',
    beginReading('X',32,'B',14).page, 14);
  check('CQ reading','out-of-range resume is clamped, not an error',
    beginReading('X',32,'B',99).page, 32);

  const cv=readingChildView(s);
  check('CQ reading','no page count reaches her',
    JSON.stringify(cv).includes('totalPages'), 'false');
  check('CQ reading','and no percentage',
    /percent|progress|remaining/i.test(JSON.stringify(cv)), 'false');
  check('CQ reading','her line is carried when the book has one',
    readingChildView(beginReading('X',10,'B',1,'And he ate ALL the buns!')).herLine,
    'And he ate ALL the buns!');
}

// CR · THE MID-CALL HANDOFF — the remote parent can never ask
{
  const byChild=requestHandoff('child',T);
  check('CR handoff','she can hand the phone over', byChild.ok, 'true');
  check('CR handoff','so can the parent in the room',
    requestHandoff('present_parent',T).ok, 'true');
  const remote=requestHandoff('remote_parent',T);
  check('CR handoff','the REMOTE parent cannot', remote.ok, 'false');
  check('CR handoff','and the refusal says why',
    /not the child/.test(remote.note), 'true');
  check('CR handoff','it points at the coordination layer instead',
    /coordination layer/.test(remote.note), 'true');

  check('CR handoff','it is announced — no ambush', byChild.handoff.announced, 'true');
  check('CR handoff',`time-boxed to ${HANDOFF_MAX_SECONDS}s`,
    byChild.handoff.maxSeconds, HANDOFF_MAX_SECONDS);
  check('CR handoff','and it expires',
    handoffExpired(byChild.handoff,'2026-07-27T18:03:00Z'), 'true');
  check('CR handoff','but not early',
    handoffExpired(byChild.handoff,'2026-07-27T18:01:00Z'), 'false');
  check('CR handoff','a hello in a hallway is not minuted', HANDOFF_IN_COURT_LOG, 'false');
}

// CS · SHE IS BUSY, SO BANK IT
{
  const f=busyFork('school','tomorrow at four');
  check('CS busy','it states the fact plainly', f.line, 'She is at school.');
  check('CS busy','banking is always offered', f.offerBanking, 'true');
  check('CS busy','and the next real window is named', f.nextWindow, 'tomorrow at four');
  check('CS busy','no urgent path unless warranted', f.urgentPath, 'null');
  check('CS busy','and one when it is',
    /emergency card/.test(busyFork('asleep',null,true).urgentPath), 'true');

  // Nothing may read as rejection.
  for(const r of ['school','asleep','wind_down','with_other_parent','quiet_hours']){
    const x=busyFork(r,null);
    if(!auditBusyFork(x).ok) check('CS busy','clean: '+r, auditBusyFork(x).found.join(), '');
  }
  check('CS busy','every reason audits clean',
    ['school','asleep','wind_down','with_other_parent','quiet_hours']
      .every(r=>auditBusyFork(busyFork(r,null)).ok), 'true');
  check('CS busy','audit catches "declined"',
    auditBusyFork({line:'She declined the call.',urgentPath:null}).ok, 'false');
  check('CS busy','and "missed call"',
    auditBusyFork({line:'Missed call.',urgentPath:null}).found.join(','), 'missed call');
  check('CS busy','nothing implies she chose it',
    BUSY_BANNED.includes('rejected')&&BUSY_BANNED.includes('no answer'), 'true');

  // The other half.
  check('CS busy','she is NEVER shown a missed call', attemptVisibleToChild(), 'false');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
