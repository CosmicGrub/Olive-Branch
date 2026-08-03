/**
 * live — games played during a call. MASTERFILE §9.2, §3.1, §5.19.
 * The three constraints are tested as constraints, not as documentation.
 */
import { LIVE_GAMES, liveForAge, register, auditLive, MIN_VIABLE_LATENCY_MS,
  UnplayableOverNetwork, DECKS, newDeck, draw, startLive, nextRound,
  connectionMessage, degradeToAsync, isDegraded, liveLayout, auditLiveView,
  newPictionary, guessDrawing } from '../src/live.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
let seed=11; const rnd=()=>{seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff;};

// AL · CONSTRAINT 1 — nothing sub-200ms
{
  check('AL latency','ten live games registered', LIVE_GAMES.length, 10);
  check('AL latency','every one clears the floor',
    LIVE_GAMES.every(g=>g.minViableLatencyMs>=MIN_VIABLE_LATENCY_MS), 'true');
  check('AL latency',`floor is ${MIN_VIABLE_LATENCY_MS}ms`, MIN_VIABLE_LATENCY_MS, 200);

  // A reflex game must be REFUSED at registration, not merely discouraged.
  let threw=null;
  try{ register({kind:'whack',title:'Whack-a-mole',minAge:5,minViableLatencyMs:80,
    videoLayout:'side_by_side',degradesToAsync:false,blurb:'x'}); }
  catch(e){ threw=e; }
  check('AL latency','a reflex game is refused at registration',
    threw instanceof UnplayableOverNetwork, 'true');
  check('AL latency','and the refusal names WHY it matters',
    /child takes the blame/.test(threw.message), 'true');
  check('AL latency','the registry did not grow', LIVE_GAMES.length, 10);
  check('AL latency','freeze dance tolerates the worst connection',
    LIVE_GAMES.find(g=>g.kind==='freeze_dance').minViableLatencyMs, 1000);
}

// AM · CONSTRAINT 2 — the face is never hidden
{
  check('AM video','no game hides the parent',
    LIVE_GAMES.every(g=>['side_by_side','picture_in_picture'].includes(g.videoLayout)), 'true');
  check('AM video','every game audits clean', LIVE_GAMES.every(g=>auditLive(g).ok), 'true');
  check('AM video','audit catches a fullscreen game',
    auditLive({...LIVE_GAMES[0],videoLayout:'fullscreen'}).problems.join(''),
    'hides the parent — the product is inverted');
  check('AM video','audit catches a hidden video',
    auditLive({...LIVE_GAMES[0],videoLayout:'hidden'}).ok, 'false');
  // Pictionary needs the board bigger, but still keeps him on screen.
  check('AM video','pictionary uses PiP, never fullscreen',
    LIVE_GAMES.find(g=>g.kind==='pictionary').videoLayout, 'picture_in_picture');
}

// AN · LAYOUT — the Fold is genuinely better at this
{
  const main=liveLayout(673,841), cover=liveLayout(344,882);
  check('AN layout','unfolded main screen puts them SIDE BY SIDE',
    main.arrangement, 'side_by_side');
  check('AN layout','with an even split', main.videoFraction, 0.5);
  check('AN layout','and says why', /crease/.test(main.reason), 'true');
  check('AN layout','the narrow cover screen stacks', cover.arrangement, 'stacked');
  check('AN layout','a tall phone also stacks', liveLayout(390,844).arrangement, 'stacked');
  check('AN layout','video is visible in EVERY arrangement',
    [main,cover,liveLayout(390,844),liveLayout(1200,800)].every(l=>l.videoVisible===true), 'true');
}

// AO · PROMPT DECKS
{
  check('AO decks','decks exist for the prompt games', DECKS.length>=9, 'true');
  const d=newDeck('charades',rnd);
  check('AO decks','charades has prompts', d.remaining.length>=8, 'true');
  check('AO decks','shuffled — two decks differ',
    newDeck('charades',rnd).remaining.join()===newDeck('charades',rnd).remaining.join(), 'false');

  let deck=newDeck('show_me',rnd), seen=[];
  for(let i=0;i<7;i++){ const r=draw(deck); if(!r) break; deck=r.deck; seen.push(r.prompt); }
  check('AO decks','no repeats within a pass', new Set(seen).size, seen.length);

  // Running out must RESHUFFLE, never end the call early.
  let small=newDeck('two_truths',rnd);
  for(let i=0;i<12;i++){ const r=draw(small); if(!r){ small=null; break; } small=r.deck; }
  check('AO decks','a deck never runs dry mid-call', small===null, 'false');
  check('AO decks','an unknown deck returns null', draw(newDeck('nope',rnd)), 'null');

  check('AO decks','"show me" prompts get her moving',
    DECKS.find(x=>x.kind==='show_me').prompts.some(p=>/Show me/.test(p)), 'true');
  check('AO decks','i spy prompts point at HIS room too',
    DECKS.find(x=>x.kind==='i_spy').prompts.some(p=>/my room|behind me/.test(p)), 'true');
}

// AP · AGE GATING
{
  check('AP ages','a four-year-old has five live games', liveForAge(4).length, 5);
  check('AP ages','an eight-year-old has more', liveForAge(8).length>liveForAge(4).length, 'true');
  check('AP ages','two truths is 11+',
    LIVE_GAMES.find(g=>g.kind==='two_truths').minAge, 11);
  check('AP ages','nothing for a four-year-old needs reading',
    liveForAge(4).every(g=>['simon_says','copy_me','freeze_dance','i_spy','show_me']
      .includes(g.kind)), 'true');
}

// AQ · THE SESSION
{
  const s=startLive('charades','B','2026-07-27T20:00:00Z',rnd);
  check('AQ session','starts', s.ok, 'true');
  check('AQ session','opens with a prompt already drawn', Boolean(s.session.currentPrompt), 'true');
  check('AQ session','unknown game refused', startLive('nope','A','t',rnd).reason, 'unknown_game');

  const n=nextRound(s.session,rnd);
  check('AQ session','the lead ALTERNATES — she is not always the one tested',
    n.leader, 'A');
  check('AQ session','rounds counted for the transcript only', n.rounds, 1);
  check('AQ session','no score reaches the child', auditLiveView(n).ok, 'true');
  check('AQ session','audit catches a reaction time',
    auditLiveView({...n,reactionMs:340}).leaks.join(','), 'reactionMs');
  check('AQ session','audit catches a streak',
    auditLiveView({a:{b:[{streak:3}]}}).ok, 'false');
}

// AR · CONSTRAINT 3 — degrade, do not die. And never blame the child.
{
  check('AR degrade','a good connection says nothing', connectionMessage('good'), 'null');
  check('AR degrade','a poor one blames the NETWORK, explicitly',
    connectionMessage('poor'), 'The connection is slow right now — not you.');
  check('AR degrade','a dropped call reassures', connectionMessage('lost'),
    'The call dropped. Nothing is lost.');
  check('AR degrade','no message blames the child',
    ['good','poor','lost'].every(q=>!/you are|too slow|your fault|missed it/i
      .test(connectionMessage(q)||'')), 'true');

  const q=startLive('twenty_questions','A','t',rnd).session;
  const d=degradeToAsync(q,'2026-07-27T20:11:00Z');
  check('AR degrade','a conversation game survives the call dropping', d.ok, 'true');
  check('AR degrade','and waits rather than vanishing',
    /waiting for you both/.test(d.note), 'true');
  check('AR degrade','progress is preserved', d.session.rounds, q.rounds);
  check('AR degrade','it is marked degraded', isDegraded(d.session), 'true');

  const ss=startLive('simon_says','B','t',rnd).session;
  const sd=degradeToAsync(ss,'t');
  check('AR degrade','a camera game admits it cannot continue', sd.ok, 'false');
  check('AR degrade','and says so honestly rather than pretending',
    /needs to see each other/.test(sd.note), 'true');
  check('AR degrade','it is saved, not discarded', /next time/.test(sd.note), 'true');
}

// AS · PICTIONARY — on the canvas that already exists
{
  let p=newPictionary('a dog wearing a hat','B');
  check('AS pictionary','the drawer is set', p.drawer, 'B');
  check('AS pictionary','the drawer cannot guess',
    guessDrawing(p,'B','a dog').reason, 'drawer_cannot_guess');
  check('AS pictionary','an empty guess refused', guessDrawing(p,'A','  ').reason, 'empty_guess');
  const wrong=guessDrawing(p,'A','a cat');
  check('AS pictionary','a wrong guess is recorded, not punished', wrong.correct, 'false');
  check('AS pictionary','and the game continues', wrong.state.solved, 'false');
  p=wrong.state;
  const right=guessDrawing(p,'A','A Dog Wearing A Hat');
  check('AS pictionary','case-insensitive match', right.correct, 'true');
  check('AS pictionary','solved', right.state.solved, 'true');
  check('AS pictionary','no more guesses once solved',
    guessDrawing(right.state,'A','x').reason, 'already_solved');
  check('AS pictionary','every guess is kept for the transcript',
    right.state.guesses.length, 2);
  check('AS pictionary','no score anywhere', auditLiveView(right.state).ok, 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
