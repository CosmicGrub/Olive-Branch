/**
 * §21 built. Ten items, per the §21.10 sequencing.
 */
import { LADDER, recordGrants, holds, canGuardianRevoke, adjustRung,
  guardianAnnouncement, QUIETING, PERMANENT, scaffoldsAt, showsScaffold,
  sendGuardApplies, surfacesAt, sealLetter, openLetter, deleteLetter,
  letterGuardianView, lettersDue, MIN_SEAL_YEARS, MAX_SEAL_TO_AGE,
  bankForParent, addToBank, bankChildView, auditBank, SUGGESTED_OCCASIONS }
  from '../src/maturation.mjs';
import { publishWindow, unpublishWindow, resolveAvailability,
  availabilityGuardianLine, auditAvailabilityCopy, MINUTES_IN_DAY,
  curate, displayCaption, archiveView, authorizeExport,
  requestDeletion, deletionConfirmation, NOT_HERS_TO_DELETE,
  auditDeletionCopy, COOLING_OFF_HOURS } from '../src/rungs.mjs';
import { ageOf, openChildren, closedChildren, closeFor, staggerNotice,
  auditStagger, siblingsOf, shellTabs, teach, askAgain, lessonArtifact,
  whoTeachesWhom, auditLesson, LESSON_SEEDS } from '../src/family.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const T='2026-07-27T12:00:00Z';
const NOW=new Date(T);

// CT · 1. THE GRANT RECORD — append-only, no inverse
{
  check('CT grants','seven rungs', LADDER.length, 7);
  let g=[];
  const r10=recordGrants(g,'olive',10,T); g=r10.grants;
  check('CT grants','at ten she gets her list', r10.newly.map(x=>x.grant).join(), 'own_list');
  const again=recordGrants(g,'olive',10,T);
  check('CT grants','recording twice adds nothing', again.newly.length, 0);
  const r15=recordGrants(g,'olive',15,T); g=r15.grants;
  check('CT grants','jumping to fifteen backfills every rung passed',
    r15.newly.map(x=>x.grant).join(','),
    'journal_absolute,own_calendar,publish_availability');
  check('CT grants','and she holds them all', holds(g,'own_calendar'), 'true');
  check('CT grants','but not one she has not reached', holds(g,'own_export'), 'false');
  check('CT grants','§21.1 — there is no inverse', canGuardianRevoke(), 'false');
  check('CT grants','every grant records when it was reached',
    g.every(x=>x.reachedAt===T), 'true');

  // §21.9 answer A.
  check('CT grants','a rung may be moved LATER by both guardians',
    adjustRung(LADDER,'own_calendar',15,['mum','dad']).ok, 'true');
  check('CT grants','never earlier',
    adjustRung(LADDER,'own_calendar',12,['mum','dad']).reason, 'earlier_not_permitted');
  check('CT grants','and never by one guardian alone',
    adjustRung(LADDER,'own_calendar',15,['dad']).reason, 'needs_both_guardians');
  check('CT grants','an unknown rung is refused',
    adjustRung(LADDER,'nope',20,['mum','dad']).reason, 'unknown_rung');

  // §21.9 answer B — only view-changing rungs notify.
  check('CT grants','rung 15 notifies the guardian',
    Boolean(guardianAnnouncement(r15.newly)), 'true');
  check('CT grants','and says the ribbon now shows what she publishes',
    /she publishes/.test(guardianAnnouncement(r15.newly)), 'true');
  check('CT grants','rung 10 does not notify',
    guardianAnnouncement(r10.newly), 'null');
  check('CT grants','nor does rung 16',
    guardianAnnouncement(recordGrants(g,'olive',16,T).newly), 'null');
}

// CU · 2. THE QUIETING
{
  check('CU quiet','seven scaffolds fade', QUIETING.length, 7);
  check('CU quiet','a five-year-old sees all of them', scaffoldsAt(5).length, 7);
  check('CU quiet','an eleven-year-old has lost the sleeps countdown',
    scaffoldsAt(11).includes('sleeps_countdown'), 'false');
  check('CU quiet','a thirteen-year-old has lost the prompt decks',
    showsScaffold('prompt_decks',13), 'false');
  check('CU quiet','a seventeen-year-old sees none of them', scaffoldsAt(17).length, 0);
  check('CU quiet','every scaffold explains itself',
    QUIETING.every(s=>s.why.length>30&&/[.]$/.test(s.why)), 'true');
  check('CU quiet','the fade ages only increase',
    QUIETING.every((s,i,a)=>i===0||s.fadesAt>=a[i-1].fadesAt), 'true');

  // THE ASYMMETRY.
  check('CU quiet','the send guard fades on HER side at 14',
    sendGuardApplies('A',14), 'false');
  check('CU quiet','but still applies to her at 13', sendGuardApplies('A',13), 'true');
  check('CU quiet','and NEVER fades on his', sendGuardApplies('B',17), 'true');
  check('CU quiet','not even at eighteen', sendGuardApplies('B',18), 'true');
  check('CU quiet','because guarding her sleep is not the same as teaching manners',
    sendGuardApplies('B',17)&&!sendGuardApplies('A',17), 'true');

  const s17=surfacesAt(17);
  check('CU quiet','at seventeen the app is calendar, call, archive, journal',
    s17.permanent.length, 5);
  check('CU quiet','with everything else faded', s17.showing.length, 0);
  check('CU quiet','the journal never fades', PERMANENT.includes('journal'), 'true');
  check('CU quiet','nor the guardian-side coordination layer',
    PERMANENT.includes('coordination_layer_guardian_side'), 'true');
}

// CV · 3a. LETTERS TO HER FUTURE SELF
{
  const l=sealLetter('l1','olive',9,18,'art-1',T);
  check('CV letter','sealed at nine for eighteen', l.ok, 'true');
  check('CV letter','and preserved as a literal', l.letter.preserved, 'true');
  check('CV letter',`under ${MIN_SEAL_YEARS} year is refused`,
    sealLetter('x','olive',9,9,'a',T).reason, 'too_soon');
  check('CV letter',`beyond ${MAX_SEAL_TO_AGE} is refused`,
    sealLetter('x','olive',9,40,'a',T).reason, 'too_far');

  // Nobody opens it early. Including her.
  const early=openLetter(l.letter,12,T);
  check('CV letter','SHE cannot open it early', early.ok, 'false');
  check('CV letter','and is told how long is left', early.yearsLeft, 6);
  const due=openLetter(l.letter,18,T);
  check('CV letter','at eighteen it opens', due.ok, 'true');
  check('CV letter','and only once', openLetter(due.letter,18,T).reason, 'already_open');

  // But she CAN delete it. Delete-without-read is the correct permission here.
  check('CV letter','she can delete a sealed letter',
    deleteLetter([l.letter],'l1','child').ok, 'true');
  check('CV letter','a guardian cannot',
    deleteLetter([l.letter],'l1','guardian').reason, 'guardian_cannot_delete');
  const gv=letterGuardianView(l.letter);
  check('CV letter','a guardian knows only that it exists', Object.keys(gv).join(), 'sealed,opensAtAge');
  check('CV letter','and never its contents', 'artifactId' in gv, 'false');

  check('CV letter','due letters surface at the right age',
    lettersDue([l.letter],18).length, 1);
  check('CV letter','and not before', lettersDue([l.letter],17).length, 0);
}

// CW · 3b. REVERSE BANKING — she banks for him
{
  check('CW bank','occasions are suggested, not required', SUGGESTED_OCCASIONS.length>=5, 'true');
  check('CW bank','including a deployment',
    SUGGESTED_OCCASIONS.some(o=>/away/i.test(o)), 'true');
  const b=bankForParent('b1','olive','dad','While you are away',T);
  check('CW bank','banked', b.ok, 'true');
  check('CW bank','an empty occasion is refused',
    bankForParent('x','olive','dad','  ',T).reason, 'no_occasion');
  let bank=b.bank;
  check('CW bank','empty invites without demanding',
    bankChildView(bank).line, 'Record something whenever you feel like it.');
  bank=addToBank(bank,'i1');
  check('CW bank','one reads singular', bankChildView(bank).line, 'One waiting for him.');
  bank=addToBank(bank,'i2');
  check('CW bank','then counts', bankChildView(bank).line, '2 waiting for him.');

  // It must never become an obligation.
  check('CW bank','no target, quota or reminder reaches her',
    auditBank(bankChildView(bank)).ok, 'true');
  check('CW bank','audit catches a target',
    auditBank({...bankChildView(bank),target:10}).leaks.join(','), 'target');
  check('CW bank','and catches "overdue"',
    auditBank({a:[{overdue:true}]}).ok, 'false');
  check('CW bank','no copy implies she owes him anything',
    /should|need to|owe|remember to|do not forget/i.test(bankChildView(bank).line), 'false');
}

// CX · 4. RUNG 15 — the inversion
{
  let board={childId:'olive',windows:[],publishedAt:null};
  const noRung=publishWindow(board,{weekday:2,startMinute:540,endMinute:900,state:'busy'},false,T);
  check('CX rung15','before fifteen she cannot publish', noRung.reason, 'not_yet_fifteen');
  const p=publishWindow(board,{weekday:2,startMinute:540,endMinute:900,state:'busy'},true,T);
  check('CX rung15','with the rung she can', p.ok, 'true');
  board=p.board;
  check('CX rung15','an overlapping window is refused',
    publishWindow(board,{weekday:2,startMinute:600,endMinute:1000,state:'free'},true,T).reason,
    'overlaps');
  check('CX rung15','a backwards window is refused',
    publishWindow(board,{weekday:3,startMinute:900,endMinute:540,state:'free'},true,T).reason,
    'bad_window');
  check('CX rung15','a bad weekday is refused',
    publishWindow(board,{weekday:9,startMinute:1,endMinute:2,state:'free'},true,T).reason,
    'bad_window');
  check('CX rung15','the day is 1440 minutes', MINUTES_IN_DAY, 1440);

  // THE RESOLUTION RULE.
  const inside=resolveAvailability(board,2,600,'free');
  check('CX rung15','HER answer wins where she gave one', inside.state, 'busy');
  check('CX rung15','and the source says so', inside.source, 'published');
  const outside=resolveAvailability(board,2,1200,'asleep');
  check('CX rung15','inference fills only the hours she left unspoken', outside.state, 'asleep');
  check('CX rung15','and is labelled as inference', outside.source, 'inferred');
  check('CX rung15','a different day falls back too',
    resolveAvailability(board,4,600,'free').source, 'inferred');
  check('CX rung15','unpublishing restores the fallback',
    resolveAvailability(unpublishWindow(board,0),2,600,'free').source, 'inferred');

  // The copy never editorialises.
  check('CX rung15','published busy reads as a fact',
    availabilityGuardianLine(inside), 'She has said she is busy.');
  check('CX rung15','inferred busy is hedged',
    availabilityGuardianLine({state:'busy',source:'inferred'}), 'She is probably busy.');
  check('CX rung15','and a parent always knows which he is reading',
    availabilityGuardianLine(inside)!==availabilityGuardianLine({state:'busy',source:'inferred'}),
    'true');
  check('CX rung15','no line interprets her',
    ['free','busy','asleep','ask_first'].every(s=>
      auditAvailabilityCopy(availabilityGuardianLine({state:s,source:'published'})).ok
      && auditAvailabilityCopy(availabilityGuardianLine({state:s,source:'inferred'})).ok),
    'true');
  check('CX rung15','audit catches "does not want to talk"',
    auditAvailabilityCopy('She does not want to talk right now.').ok, 'false');
}

// CY · 5. RUNG 16 — curation
{
  const items=[{id:'a',artifactId:'x1',era:null,hiddenByChild:false,
    captionByGuardian:'Sports day',captionByChild:null},
    {id:'b',artifactId:'x2',era:null,hiddenByChild:false,
     captionByGuardian:null,captionByChild:null}];
  const hid=curate(items,'a','child',{hidden:true});
  check('CY rung16','she can hide something', hid.items[0].hiddenByChild, 'true');
  check('CY rung16','a guardian cannot',
    curate(items,'a','guardian',{hidden:true}).reason, 'guardian_cannot_curate');
  check('CY rung16','nor UN-hide what she hid',
    curate(hid.items,'a','guardian',{hidden:false}).ok, 'false');
  check('CY rung16','an unknown item is refused',
    curate(items,'zz','child',{hidden:true}).reason, 'no_such_item');

  const tagged=curate(items,'a','child',{era:'when I was small'});
  check('CY rung16','she can era-tag', tagged.items[0].era, 'when I was small');
  const retitled=curate(items,'a','child',{caption:'the day I fell over'});
  check('CY rung16','her caption wins', displayCaption(retitled.items[0]), 'the day I fell over');
  check('CY rung16','his stands until she writes one', displayCaption(items[0]), 'Sports day');
  check('CY rung16','and nothing shows where neither wrote', displayCaption(items[1]), 'null');

  check('CY rung16','she still sees what she hid', archiveView(hid.items,'child').length, 2);
  check('CY rung16','he does not', archiveView(hid.items,'guardian').length, 1);
  check('CY rung16','hiding is not deleting — it is still there',
    hid.items.find(i=>i.id==='a').artifactId, 'x1');
}

// CZ · 6. RUNG 17 — her own export
{
  const young=authorizeExport({kind:'child',childId:'olive',age:16},T);
  check('CZ rung17','sixteen is too early', young.reason, 'not_yet_seventeen');
  const hers=authorizeExport({kind:'child',childId:'olive',age:17},T);
  check('CZ rung17','seventeen can export', hers.ok, 'true');
  check('CZ rung17','WITHOUT anybody\'s permission',
    hers.grant.requiresGuardianApproval, 'false');
  check('CZ rung17','and it never contains a guardian journal',
    hers.grant.includesGuardianJournals, 'false');
  check('CZ rung17','a guardian can still export',
    authorizeExport({kind:'guardian',userId:'dad'},T).ok, 'true');
  check('CZ rung17','and so can a coordinator',
    authorizeExport({kind:'coordinator',userId:'c'},T).ok, 'true');
  check('CZ rung17','no principal gets guardian journals',
    [{kind:'child',childId:'o',age:18},{kind:'guardian',userId:'d'},
     {kind:'coordinator',userId:'c'}]
      .every(p=>authorizeExport(p,T).grant.includesGuardianJournals===false), 'true');
}

// DA · 7. RUNG 18 — the hardest button
{
  check('DA delete','there is NO cooling-off period', COOLING_OFF_HOURS, 0);
  const early=requestDeletion('olive',17,['journal'],T);
  check('DA delete','seventeen cannot', early.reason, 'not_yet_eighteen');
  const none=requestDeletion('olive',18,[],T);
  check('DA delete','nothing selected is refused', none.reason, 'nothing_selected');

  const all=['media_artifact','message','journal','show','story_code','colour_history',
    'collection','gallery_work','letter','availability','calendar_child_event'];
  const r=requestDeletion('olive',18,all,T);
  check('DA delete','at eighteen she can delete everything', r.ok, 'true');
  check('DA delete','and it is immediate', r.request.immediate, 'true');
  check('DA delete','there is no executeAfter field', 'executeAfter' in r.request, 'false');

  const c=deletionConfirmation(r.request);
  check('DA delete','it lists what goes, in plain words', c.willGo.length, 11);
  check('DA delete','including her sealed letters',
    c.willGo.some(x=>/sealed or not/.test(x)), 'true');
  check('DA delete','it lists what remains', c.willRemain.length, 3);
  check('DA delete','the parent log is not hers to delete',
    c.willRemain.some(x=>/message log/.test(x)), 'true');
  check('DA delete','and it says why', /append-only under P8/.test(c.willRemain[0]), 'true');
  check('DA delete','the expense ledger stays',
    NOT_HERS_TO_DELETE.some(x=>x.table==='expense'), 'true');
  check('DA delete','and the court order',
    NOT_HERS_TO_DELETE.some(x=>x.table==='custody_order'), 'true');
  check('DA delete','the question is plain', c.question, 'Delete all of it?');
  check('DA delete','and it is marked irreversible', c.irreversible, 'true');

  // No retention tactics.
  check('DA delete','the confirmation carries NO retention copy',
    auditDeletionCopy(c.question+' '+c.willGo.join(' ')+' '+c.willRemain.join(' ')).ok, 'true');
  check('DA delete','audit catches "are you sure"',
    auditDeletionCopy('Are you sure? You will lose years of memories.').found.length>=2, 'true');
  check('DA delete','and "just deactivate instead"',
    auditDeletionCopy('Instead you could just deactivate.').ok, 'false');
  check('DA delete','and "before you go"',
    auditDeletionCopy('Before you go, remember when you were six?').ok, 'false');
  check('DA delete','the banned list covers the usual dark patterns',
    ['are you sure','sleep on it','just deactivate','take a break']
      .every(w=>!auditDeletionCopy(w).ok), 'true');
}

// DB · 8. SIBLINGS, STAGGERED
{
  const set={children:[
    {id:'c1',displayName:'Maya',birthDate:'2008-06-14',guardianshipClosedAt:null,colourId:'sea'},
    {id:'c2',displayName:'Olive',birthDate:'2021-06-14',guardianshipClosedAt:null,colourId:'coral'},
    {id:'c3',displayName:'Rowan',birthDate:'2024-02-02',guardianshipClosedAt:null,colourId:'mint'}]};
  check('DB siblings','three open', openChildren(set).length, 3);
  check('DB siblings','ages computed', ageOf(set.children[0],NOW), 18);
  check('DB siblings','and the youngest', ageOf(set.children[2],NOW), 2);

  const closed=closeFor(set,'c1',T);
  check('DB siblings','closure is PER CHILD', closed.ok, 'true');
  check('DB siblings','two remain', closed.remaining, 2);
  check('DB siblings','and the parent has not lost the others',
    openChildren(closed.set).map(c=>c.displayName).join(','), 'Olive,Rowan');
  check('DB siblings','closing twice is refused',
    closeFor(closed.set,'c1',T).reason, 'already_closed');
  check('DB siblings','an unknown child is refused',
    closeFor(set,'zz',T).reason, 'unknown_child');

  const n=staggerNotice(closed.set,'c1');
  check('DB siblings','a notice is produced', Boolean(n), 'true');
  check('DB siblings','it names who is still here',
    n.line, "Maya's archive has transferred to her. Olive and Rowan are still here.");
  check('DB siblings','shown once, never again', n.showOnce, 'true');
  check('DB siblings','no offboarding language', auditStagger(n).ok, 'true');
  check('DB siblings','audit catches "no longer"',
    auditStagger({line:'You no longer have access to Maya.'}).ok, 'false');
  check('DB siblings','and catches "sorry to see"',
    auditStagger({line:'Sorry to see Maya go.'}).ok, 'false');

  let last=closeFor(closed.set,'c2',T).set;
  last=closeFor(last,'c3',T).set;
  check('DB siblings','the last one reads differently',
    staggerNotice(last,'c3').line.endsWith('That is all of them.'), 'true');
  check('DB siblings','a sibling link survives closure',
    siblingsOf(last,'c1').length, 2);

  const tabs=shellTabs(closed.set,NOW);
  check('DB siblings','the shell shows all three', tabs.length, 3);
  check('DB siblings','each with her own colour', tabs[1].colourId, 'coral');
  check('DB siblings','and the closed one is marked', tabs[0].open, 'false');
}

// DC · 9 & 10. TEACH ME SOMETHING
{
  check('DC teach','sixteen things he might know', LESSON_SEEDS.length, 16);
  check('DC teach','including one about his own work',
    LESSON_SEEDS.some(s=>/at work/.test(s)), 'true');
  const l=teach('l1','dad','How to tie a bowline','demonstrate',T);
  check('DC teach','taught', l.ok, 'true');
  check('DC teach','an empty title is refused', teach('x','dad','  ','draw',T).reason, 'no_title');
  check('DC teach','not yet an artifact', lessonArtifact(l.lesson), 'null');
  const asked=askAgain([l.lesson],'l1');
  check('DC teach','asking again is the only metric', asked[0].askedAgain, 1);
  check('DC teach','and it makes it worth keeping',
    lessonArtifact(asked[0]).preserved, 'true');

  const young=whoTeachesWhom(4);
  check('DC teach','at four, mostly him', young.childTeaches, 'false');
  check('DC teach','but it says she will start', /at about six/.test(young.note), 'true');
  const older=whoTeachesWhom(9);
  check('DC teach','at nine, both ways', older.childTeaches, 'true');
  check('DC teach','and he is told not to pretend',
    /pretending is\s+detected instantly|pretending is detected/.test(older.note), 'true');
  check('DC teach','no grading anywhere', auditLesson(asked[0]).ok, 'true');
  check('DC teach','audit catches a level',
    auditLesson({...asked[0],level:3}).leaks.join(','), 'level');
  check('DC teach','and catches "mastery"',
    auditLesson({a:[{mastery:0.8}]}).ok, 'false');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
