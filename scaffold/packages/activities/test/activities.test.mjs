/**
 * activities + library + call security.
 * MASTERFILE §9.12, §9.11.6, §5.21. Prohibitions P2, P3.
 */
import { newColouring, fill, undoFill, colouringChildView, colouringArtifact,
  buildFindScene, tapFind, findHint, FIND_LEVELS,
  buildSpotScene, tapSpot, spotRemaining, spotComplete, spotChildView,
  nextDifficulty, SPOT_LEVELS, auditActivity, ACTIVITY_FORBIDDEN,
  DOODLE_STAMPS, newDoodle, stroke, addStamp, undoDoodle, doodleChildView,
  doodleArtifact, LIVE_DOODLE_REUSES_SHARED_CANVAS, DOODLE_PAIRING }
  from '../src/activities.mjs';
import { bookmark, resume, saveBookmark, clearBookmark, star, unstar,
  recordRead, isStarred, libraryChildView, compileBook, bookAsText,
  bookArtifact, auditLibraryChildView } from '../../storyteller/src/library.mjs';
import { generate } from '../../storyteller/src/storyteller.mjs';
import { callPolicy, auditPolicy, RELAY_ONLY, relayRequiredBecause,
  sharePreflight, decideE2ee, auditE2ee, RESIDUAL_RISKS, unfixableRisks }
  from '../../session-runtime/src/security.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
let seed=17; const rnd=()=>{seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff;};

const DRAWING={id:'d1',title:'A very tall giraffe',about:'He needs colouring in.',
  minAge:3,
  swatches:[{hex:'#F2B705',label:'yellow'},{hex:'#8A6244',label:'brown'},
            {hex:'#5AA84A',label:'green'},{hex:'#8B6BB1',label:'purple'}],
  regions:[{id:'r1',d:'M0 0',suggested:'#F2B705',number:1},
           {id:'r2',d:'M1 1',suggested:'#8A6244',number:2},
           {id:'r3',d:'M2 2',suggested:'#5AA84A',number:3}]};

// BZ · COLOURING — tap a bit, it fills
{
  let s=newColouring(DRAWING);
  check('BZ colour','starts empty', Object.keys(s.filled).length, 0);
  check('BZ colour','and invites her in',
    colouringChildView(s,DRAWING).line, 'Pick a colour and tap a bit of the picture.');

  const r=fill(s,DRAWING,'r1','#F2B705');
  check('BZ colour','a tap fills a whole region', r.state.filled.r1, '#F2B705');
  check('BZ colour','and it matched the suggestion', r.matchedSuggestion, 'true');
  s=r.state;

  // THE rule: a "wrong" colour still fills.
  const purple=fill(s,DRAWING,'r2','#8B6BB1');
  check('BZ colour','a purple elephant is allowed', purple.ok, 'true');
  check('BZ colour','it just fills, with no correction', purple.state.filled.r2, '#8B6BB1');
  check('BZ colour','the mismatch is recorded but never shown to her',
    purple.matchedSuggestion, 'false');
  s=purple.state;

  check('BZ colour','an unknown region is refused',
    fill(s,DRAWING,'nope','#F2B705').reason, 'no_such_region');
  check('BZ colour','a colour outside the palette is refused',
    fill(s,DRAWING,'r3','#123456').reason, 'not_a_palette_colour');

  check('BZ colour','recolouring the same region works',
    fill(s,DRAWING,'r1','#5AA84A').state.filled.r1, '#5AA84A');
  const back=undoFill(fill(s,DRAWING,'r1','#5AA84A').state);
  check('BZ colour','undo restores the PREVIOUS colour, not empty', back.filled.r1, '#F2B705');
  let empty=newColouring(DRAWING);
  empty=fill(empty,DRAWING,'r1','#F2B705').state;
  check('BZ colour','undo on a first fill clears it',
    'r1' in undoFill(empty).filled, 'false');
  check('BZ colour','undo on an empty picture is safe',
    Object.keys(undoFill(newColouring(DRAWING)).filled).length, 0);

  s=fill(s,DRAWING,'r3','#5AA84A').state;
  check('BZ colour','finished when every region has a colour',
    colouringChildView(s,DRAWING).finished, 'true');
  check('BZ colour','and it offers to send it to Dad',
    /send it to Dad/.test(colouringChildView(s,DRAWING).line), 'true');
  check('BZ colour','§9.8.1 — a finished picture is preserved',
    colouringArtifact(s,DRAWING).preserved, 'true');
  check('BZ colour','an unfinished one is not', colouringArtifact(newColouring(DRAWING),DRAWING), 'null');

  // P2 — a colouring book with a completion bar is a worksheet.
  check('BZ colour','no percentage reaches her',
    auditActivity(colouringChildView(s,DRAWING)).ok, 'true');
  check('BZ colour','audit catches a completion field',
    auditActivity({...colouringChildView(s,DRAWING),percentComplete:66}).ok, 'false');
  check('BZ colour','numbered mode is a mode, not a rule',
    newColouring(DRAWING,'numbered').mode, 'numbered');
  check('BZ colour','every region carries a suggestion for it',
    DRAWING.regions.every(r=>/^#[0-9A-F]{6}$/i.test(r.suggested)), 'true');
}

// CA · FIND THE THING — the parent chooses what is hidden
{
  const target={label:'a stegosaurus',glyph:'🦕'};
  const decoys=['🦖','🦎','🐊','🐢','🐉','🐛','🌿','🪨','🌳'];
  const g=buildFindScene('f1',target,decoys,'gentle',rnd);
  check('CA find','builds', g.ok, 'true');
  check('CA find','exactly one target',
    g.scene.items.filter(i=>i.isTarget).length, 1);
  check('CA find','gentle has 24 decoys plus the target',
    g.scene.items.length, FIND_LEVELS.gentle.decoys+1);
  check('CA find','everything is on the canvas',
    g.scene.items.every(i=>i.x>=0&&i.x<=1&&i.y>=0&&i.y<=1), 'true');
  check('CA find','no decoys is refused', buildFindScene('x',target,[],'gentle',rnd).reason,
    'no_decoys');

  const f=buildFindScene('f2',target,decoys,'fiendish',rnd);
  check('CA find','fiendish is far denser', f.scene.items.length, FIND_LEVELS.fiendish.decoys+1);
  check('CA find','and zooms further', f.scene.maxZoom>g.scene.maxZoom, 'true');
  check('CA find','difficulty is decoys and similarity, NEVER a timer',
    Object.values(FIND_LEVELS).every(l=>!('seconds' in l)&&!('timer' in l)), 'true');
  check('CA find','the target is not always last — it is spliced in',
    g.scene.items[g.scene.items.length-1].isTarget, 'false');

  const t=g.scene.items.find(i=>i.isTarget);
  check('CA find','tapping the target finds it', tapFind(g.scene,t.id).found, 'true');
  const miss=g.scene.items.find(i=>!i.isTarget);
  check('CA find','a miss does nothing at all', tapFind(g.scene,miss.id).found, 'false');
  check('CA find','and there is no nudge, buzz or counter on a miss',
    tapFind(g.scene,miss.id).nudge, 'null');
  check('CA find','a hint gives a quadrant, never the answer',
    /^Try the (top|bottom) (left|right)\.$/.test(findHint(g.scene)), 'true');
  check('CA find','no scoring anywhere', auditActivity(g.scene).ok, 'true');
}

// CB · SPOT THE DIFFERENCE — subtlety scaled, not time
{
  const s=buildSpotScene('s1','gentle',rnd);
  check('CB spot','gentle has three differences', s.differences.length, 3);
  check('CB spot','and they are obvious',
    s.differences.every(d=>d.subtlety>=SPOT_LEVELS.gentle.minSubtlety), 'true');
  const f=buildSpotScene('s2','fiendish',rnd);
  check('CB spot','fiendish has ten', f.differences.length, 10);
  check('CB spot','and they are subtle',
    f.differences.every(d=>d.subtlety<=SPOT_LEVELS.fiendish.maxSubtlety), 'true');
  check('CB spot','difficulty is count and subtlety, never a countdown',
    Object.values(SPOT_LEVELS).every(l=>!('seconds' in l)), 'true');
  check('CB spot','the tap radius is generous — she aims with a whole finger',
    s.differences.every(d=>d.radius>=0.08), 'true');

  const d0=s.differences[0];
  const hit=tapSpot(s,d0.x,d0.y);
  check('CB spot','tapping near one finds it', hit.found.id, d0.id);
  check('CB spot','and it stays found', spotRemaining(hit.scene), 2);
  check('CB spot','tapping it again does nothing',
    tapSpot(hit.scene,d0.x,d0.y).found, 'null');
  check('CB spot','a miss finds nothing', tapSpot(s,0.999,0.999).found, 'null');

  let all=s;
  for(const d of s.differences) all=tapSpot(all,d.x,d.y).scene;
  check('CB spot','all found → complete', spotComplete(all), 'true');
  check('CB spot','and said warmly', spotChildView(all).line, 'You found them all.');
  check('CB spot','one left reads singular',
    spotChildView(tapSpot(tapSpot(s,s.differences[0].x,s.differences[0].y).scene,
      s.differences[1].x,s.differences[1].y).scene).line, 'One more to find.');
  check('CB spot','how many are LEFT is a goal, not a score',
    auditActivity(spotChildView(s)).ok, 'true');
  check('CB spot','escalation is manual and stops at the top',
    nextDifficulty(nextDifficulty(nextDifficulty(nextDifficulty('gentle')))), 'fiendish');
  check('CB spot','the forbidden list covers timers and accuracy alike',
    ACTIVITY_FORBIDDEN.includes('timeLeft')&&ACTIVITY_FORBIDDEN.includes('accuracy'), 'true');
}

// CG · DOODLE DESK — free strokes and six fixed stamps, no finish line
{
  let s=newDoodle();
  check('CG doodle','starts blank', s.marks.length, 0);
  check('CG doodle','a blank page invites her to draw',
    doodleChildView(s).line, 'Draw anything you want.');

  const r1=stroke(s,'k1',[[0.1,0.1],[0.2,0.2],[0.3,0.1]],'#F2B705',6);
  check('CG doodle','a free stroke is recorded', r1.ok, 'true');
  s=r1.state;
  check('CG doodle','it lands on the canvas', s.marks.length, 1);
  check('CG doodle','as a stroke, not a stamp', s.marks[0].kind, 'stroke');
  check('CG doodle','with her exact points kept, not simplified',
    JSON.stringify(s.marks[0].stroke.points),
    JSON.stringify([[0.1,0.1],[0.2,0.2],[0.3,0.1]]));
  check('CG doodle','an empty stroke — no points — is refused',
    stroke(s,'k2',[],'#000000',6).reason, 'empty');

  for (const st of DOODLE_STAMPS) {
    const placed=addStamp(s,`stamp-${st}`,st,0.5,0.5,1);
    check('CG doodle',`the ${st} stamp can be placed`, placed.ok, 'true');
    s=placed.state;
  }
  check('CG doodle','all six fixed stamps exist', DOODLE_STAMPS.length, 6);
  check('CG doodle','one stroke plus six stamps are all on the canvas', s.marks.length, 7);
  check('CG doodle','a stamp outside the fixed six is refused',
    addStamp(s,'x','glitter',0.5,0.5).reason, 'not_a_stamp');

  // Undo — free, unlimited, exact history, same pattern as everywhere in §9.2.
  const before=s;
  const afterOneUndo=undoDoodle(s);
  check('CG doodle','undo removes exactly the last mark',
    afterOneUndo.marks.length, before.marks.length-1);
  check('CG doodle','and restores the exact prior state, not an approximation',
    JSON.stringify(afterOneUndo.marks), JSON.stringify(before.marks.slice(0,-1)));

  let emptied=s;
  for (let i=0;i<20;i++) emptied=undoDoodle(emptied);
  check('CG doodle','unlimited undo empties the canvas and then stops safely',
    emptied.marks.length, 0);
  check('CG doodle','undo on a blank canvas is a no-op, not an error',
    undoDoodle(newDoodle()).marks.length, 0);

  check('CG doodle','a doodle with anything on it at all is preservable',
    doodleArtifact(r1.state).preserved, 'true');
  check('CG doodle','a single stamp with nothing else is preservable too',
    doodleArtifact(addStamp(newDoodle(),'m1','heart',0.5,0.5).state).preserved, 'true');
  check('CG doodle','a blank canvas is not preserved', doodleArtifact(newDoodle()), 'null');

  check('CG doodle','a doodle in progress invites her to keep going or send it',
    doodleChildView(s).line, 'Keep going, or send it when you like.');

  // §9.12 preamble — nothing here has a timer, a score, or a wrong answer.
  check('CG doodle','no forbidden field reaches the child view',
    auditActivity(doodleChildView(s)).ok, 'true');
  check('CG doodle','audit would catch a completion percentage if one ever leaked in',
    auditActivity({...doodleChildView(s), percentComplete:50}).ok, 'false');
  check('CG doodle','no forbidden field reaches the artifact either',
    auditActivity(doodleArtifact(r1.state)).ok, 'true');
  check('CG doodle','there is no "finished" concept — a blank page has no finish line',
    'finished' in doodleChildView(s), 'false');
  check('CG doodle','and no count of marks is shown to her',
    'coloured' in doodleChildView(s) || 'count' in doodleChildView(s), 'false');
}

// CH · DOODLE — LIVE PAIRING (§8.15, v0.42.0)
{
  check('CH pairing','the live form reuses the shared canvas, not a new engine',
    LIVE_DOODLE_REUSES_SHARED_CANVAS, 'true');
  check('CH pairing','the async form is named the doodle desk',
    DOODLE_PAIRING.async.form, 'doodle desk');
  check('CH pairing','and it is solo', DOODLE_PAIRING.async.mode, 'solo');
  check('CH pairing','with no timer, score, or completion concept',
    DOODLE_PAIRING.async.hasTimerScoreOrCompletion, 'false');
  check('CH pairing','the sync form is named live doodle',
    DOODLE_PAIRING.sync.form, 'live doodle');
  check('CH pairing','and it points at the shared annotation canvas, not a new one',
    /annotation\/canvas/.test(DOODLE_PAIRING.sync.engine), 'true');
  check('CH pairing',"its undo is per-actor, so a parent cannot erase the child's stroke",
    /per-actor/.test(DOODLE_PAIRING.sync.undoScoping), 'true');
}

// CC · BOOKMARKS — reopen exactly where they stopped
{
  const s=generate(90210);
  const b=bookmark(s,4,'2026-07-27T20:10:00Z');
  check('CC bookmark','saved', b.ok, 'true');
  check('CC bookmark','it remembers the line', b.bookmark.lineIndex, 4);
  check('CC bookmark','and the story, as six characters', b.bookmark.code, s.code);
  check('CC bookmark','a bookmark on the last line is refused',
    bookmark(s,s.lines.length-1,'t').reason, 'already_finished');
  check('CC bookmark','out of range refused', bookmark(s,99,'t').reason, 'no_such_line');

  const r=resume(b.bookmark);
  check('CC bookmark','resuming regenerates the SAME story',
    r.story.lines[0].text, s.lines[0].text);
  check('CC bookmark','and reopens at the stored line', r.from, 4);
  // Line 4 is the FIRST refrain, so nothing precedes it to recap. That is
  // correct: there is no chant she has heard yet.
  check('CC bookmark','no recap when she has not reached a refrain', r.recap, 'null');
  // Stopping later, after she has heard it, recaps her line.
  const later=bookmark(s,8,'2026-07-27T20:20:00Z');
  check('CC bookmark','her refrain IS recapped once she has heard it',
    resume(later.bookmark).recap, s.refrain);
  check('CC bookmark','because starting her cold on line eight is worse',
    resume(later.bookmark).from, 8);

  let list=saveBookmark([],b.bookmark);
  const b2=bookmark(s,6,'2026-07-28T20:10:00Z').bookmark;
  list=saveBookmark(list,b2);
  check('CC bookmark','one bookmark per story — the second replaces the first',
    list.length, 1);
  check('CC bookmark','and it is the newer position', list[0].lineIndex, 6);
  check('CC bookmark','clearing works', clearBookmark(list,s.code).length, 0);
}

// CD · FAVOURITES — a list that grows for years
{
  const a=generate(111), b=generate(222);
  let list=star([],a,'2026-01-05T20:00:00Z',3).list;
  check('CD star','starred', list.length, 1);
  check('CD star','starring twice is refused', star(list,a,'t').reason, 'already_starred');
  check('CD star','isStarred works', isStarred(list,a.code), 'true');
  list=star(list,b,'2026-03-09T20:00:00Z',1).list;
  list=recordRead(list,b.code);
  check('CD star','reads are counted for the book', list.find(f=>f.code===b.code).timesRead, 2);

  const view=libraryChildView(list);
  check('CD star','her list is newest first', view[0].code, b.code);
  check('CD star','P2 — no read counts reach her', auditLibraryChildView(view).ok, 'true');
  check('CD star','audit catches timesRead leaking in',
    auditLibraryChildView([{...view[0],timesRead:9}]).leaks.join(','), 'timesRead');
  check('CD star','unstarring works', unstar(list,a.code).length, 1);
}

// CE · THE BOOK — for Christmas
{
  let favs=[];
  for(let i=0;i<7;i++){
    const st=generate(1000+i*37);
    favs=star(favs,st,`2026-0${i+1}-15T20:00:00Z`,i+1).list;
  }
  const tooFew=compileBook(favs.slice(0,3),'Olive','2026-12-01T09:00:00Z');
  check('CE book','under five stories is a pamphlet, and refused', tooFew.reason, 'too_few');

  const r=compileBook(favs,'Olive','2026-12-01T09:00:00Z');
  check('CE book','compiles', r.ok, 'true');
  const bk=r.book;
  check('CE book','seven pages', bk.pages.length, 7);
  check('CE book','ordered OLDEST first — a year, not a leaderboard',
    bk.pages[0].code, favs[0].code);
  check('CE book','the dedication is in his voice',
    bk.dedication, 'For Olive, who asked for these again.');
  check('CE book','it tells the reader what the bold lines are',
    /let her say them/.test(bk.readerNote), 'true');
  check('CE book','print metadata is present', bk.meta.estimatedPages>0, 'true');
  check('CE book','and a word count for a print shop', bk.meta.wordCount>200, 'true');
  check('CE book','every page carries its refrain',
    bk.pages.every(p=>p.refrain.length>0), 'true');
  check('CE book','and the times she asked for it',
    bk.pages.some(p=>p.timesRead>1), 'true');

  const txt=bookAsText(bk);
  check('CE book','plain text, not a proprietary format', typeof txt, 'string');
  check('CE book','§2.11 — it is never held hostage by a file type',
    txt.includes("OLIVE'S STORIES"), 'true');
  check('CE book','her lines are marked in the print', txt.includes('>> '), 'true');
  check('CE book','the "asked for this nine times" note is printed',
    /asked for this one \d+ times/.test(txt), 'true');

  const art=bookArtifact(bk);
  check('CE book','§9.8.1 — the book is preserved', art.preserved, 'true');
  check('CE book','stored as codes, so a hundred stories is 600 bytes',
    art.codes.length*6, 42);
  check('CE book','and it is hers at majority (§9.8.4)',
    art.title, "Olive's Stories");
}

// CF · CALL SECURITY — the IP leak that would have shipped
{
  const p=callPolicy({});
  check('CF calls','relay-only, always', p.iceTransportPolicy, 'relay');
  check('CF calls','the constant says so too', RELAY_ONLY, 'relay');
  check('CF calls','there is no option that turns it off',
    callPolicy({e2ee:false,allowScreenShare:true}).iceTransportPolicy, 'relay');
  check('CF calls','P3 is the primary reason',
    /coarse location/.test(relayRequiredBecause([{restricted:false}])[0]), 'true');
  check('CF calls','a protective order adds a second, sharper reason',
    relayRequiredBecause([{restricted:true}]).length, 2);
  check('CF calls','and it names the disclosure',
    /protected party/.test(relayRequiredBecause([{restricted:true}])[1]), 'true');

  check('CF calls','audit passes a correct policy', auditPolicy(p).ok, 'true');
  check('CF calls','audit CATCHES peer-to-peer',
    auditPolicy({...p,iceTransportPolicy:'all'}).faults.join(','), 'peer_to_peer_permitted');
  check('CF calls','audit catches a whole-screen share',
    auditPolicy({...p,screenShare:'screen'}).faults.includes('whole_screen_share'), 'true');
  check('CF calls','audit catches capture surviving a background',
    auditPolicy({...p,releaseCaptureOnBackground:false}).ok, 'false');
  check('CF calls','audit catches silent recording',
    auditPolicy({...p,recording:'silent'}).faults.includes('undisclosed_recording'), 'true');

  check('CF calls','screen share is off by default', p.screenShare, 'disabled');
  check('CF calls','and window-only when enabled',
    callPolicy({allowScreenShare:true}).screenShare, 'window_only');
  const pre=sharePreflight('Fractions worksheet.pdf');
  check('CF calls','a preflight names exactly what she will see',
    /one window — "Fractions worksheet.pdf" — and nothing else/.test(pre.disclosure), 'true');
  check('CF calls','notifications are paused for the duration',
    /notifications are paused/.test(pre.disclosure), 'true');
  check('CF calls','whole screen is not even offered', pre.wholeScreenAvailable, 'false');

  // The tension named rather than hidden.
  const enc=decideE2ee(false), rec=decideE2ee(true);
  check('CF calls','E2EE is the default', enc.e2ee, 'true');
  check('CF calls','and recording is off with it', enc.recording, 'off');
  check('CF calls','supervised recording gives up E2EE', rec.e2ee, 'false');
  check('CF calls','and says so before the call starts',
    /not end-to-end encrypted/.test(rec.note), 'true');
  check('CF calls','both-on is refused — one of them is a lie',
    auditE2ee({e2ee:true,recording:'disclosed_supervised'}).ok, 'false');
  check('CF calls','and encryption given up for nothing is refused too',
    auditE2ee({e2ee:false,recording:'off'}).ok, 'false');

  check('CF calls','residual risks are listed honestly', RESIDUAL_RISKS.length, 6);
  check('CF calls','three of them cannot be fixed by us', unfixableRisks(), 3);
  check('CF calls','including a parent standing behind her',
    RESIDUAL_RISKS.some(r=>/standing behind/.test(r.risk)), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
