/**
 * games — four titles plus the mechanics that make competitive play safe here.
 * MASTERFILE §9.2, §4.7, §9.8. Prohibition P2.
 */
import { CATALOGUE, forAge, newGame, play, setHandicap, handicapBanner,
  takeBack, childView, auditChildView, shouldOfferHandicap, handicapOffer,
  turnExpired, storyArtifact, STREAK_BEFORE_OFFER,
  DEFAULT_TURN_BUDGET_REACHABLE_HOURS } from '../src/games.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const P=(s,side,at,v)=>{const r=play(s,side,at,v); if(!r.ok) throw new Error(r.reason); return r.state;};

// S · CATALOGUE
{
  check('S catalogue','four titles ship', CATALOGUE.length, 4);
  // The stated target is 5+, where everything unlocks. Below that the two
  // simplest titles are still playable rather than the shelf being empty.
  check('S catalogue','a four-year-old still has two titles', forAge(4).length, 2);
  check('S catalogue','a five-year-old has all four', forAge(5).length, 4);
  check('S catalogue','nothing is gated above 5', Math.max(...CATALOGUE.map(g=>g.minAge)), 5);
  check('S catalogue','story is the co-op one',
    CATALOGUE.find(g=>g.kind==='story').competitive, 'false');
  check('S catalogue','co-op game offers no handicap — nothing to be behind at',
    CATALOGUE.find(g=>g.kind==='story').handicaps.length, 0);
  check('S catalogue','every competitive game offers at least one handicap',
    CATALOGUE.filter(g=>g.competitive).every(g=>g.handicaps.length>0), 'true');
}

// T · TIC-TAC-TOE
{
  let g=newGame('tictactoe','t1');
  check('T tictactoe','child moves first by default', g.turn, 'A');
  g=P(g,'A',0); g=P(g,'B',4); g=P(g,'A',1); g=P(g,'B',5);
  check('T tictactoe','no winner yet', g.outcome, 'null');
  g=P(g,'A',2);
  check('T tictactoe','top row wins for the child', g.outcome, 'A');
  check('T tictactoe','no moves after the end', play(g,'B',3).reason, 'game_over');

  let h=newGame('tictactoe','t2');
  check('T tictactoe','occupied square refused',
    (function(){h=P(h,'A',0); return play(h,'B',0).reason;})(), 'occupied');
  check('T tictactoe','out of range refused', play(h,'B',99).reason, 'out_of_range');
  check('T tictactoe','out of turn refused', play(h,'A',1).reason, 'not_your_turn');

  // A draw must not be reported as a loss for anyone.
  let d=newGame('tictactoe','t3');
  [0,4,1,2,6,3,5,8,7].forEach((i,n)=>{ d=P(d,n%2?'B':'A',i); });
  check('T tictactoe','a full board with no line is a draw', d.outcome, 'draw');
}

// U · THE HANDICAP — set by the CHILD, on the PARENT
{
  let g=newGame('tictactoe','h1');
  check('U handicap','a parent cannot handicap themselves',
    setHandicap(g,'B','no_centre').reason, 'child_only');
  check('U handicap','an unknown handicap is refused',
    setHandicap(g,'A','make_dad_lose').reason, 'unknown');
  const set=setHandicap(g,'A','no_centre');
  check('U handicap','the child may impose one', set.ok, 'true');
  g=set.state;
  check('U handicap','framed as the parent playing hard, never as charity',
    handicapBanner(g), "Dad's playing the hard way — dad can't use the middle square");
  check('U handicap','banner never says the child is worse',
    /help|easier|weaker|struggl|behind you/i.test(handicapBanner(g)), 'false');
  g=P(g,'A',0);
  check('U handicap','the ENGINE enforces it, not the UI',
    play(g,'B',4).reason, 'handicap_forbids');
  check('U handicap','the parent may still play elsewhere', play(g,'B',3).ok, 'true');

  let d=setHandicap(newGame('dotsboxes','h2'),'A','start_behind').state;
  check('U handicap','start-behind gives the child a real head start',
    `${d.scores.A}/${d.scores.B}`, '2/0');
}

// V · DOTS AND BOXES — completing a box gives another turn
{
  let g=newGame('dotsboxes','d1');
  // Close the top-left box: h(0,0), h(1,0), v(0,0), v(0,1).
  g=P(g,'A',['h',0,0]); check('V dotsboxes','turn passes normally', g.turn, 'B');
  g=P(g,'B',['h',1,0]); g=P(g,'A',['v',0,0]);
  check('V dotsboxes','still no box', g.scores.B, 0);
  const before=g.turn;
  g=P(g,'B',['v',0,1]);
  check('V dotsboxes','the box is claimed', g.scores.B, 1);
  check('V dotsboxes','and the SAME player moves again — the rule that makes it deep',
    g.turn, before);
  check('V dotsboxes','an already-drawn line is refused',
    play(g,'B',['h',0,0]).reason, 'occupied');
  check('V dotsboxes','out of range refused', play(g,'B',['h',99,0]).reason, 'out_of_range');
}

// W · MEMORY — from their own photos
{
  let g=newGame('memory','m1',['dog','house','beach']);
  check('W memory','deck is pairs', g.board.deck.length, 6);
  const idx=(n)=>g.board.deck.map((d,i)=>[d,i]).filter(x=>x[0]===n).map(x=>x[1]);
  const [d1,d2]=idx('dog');
  g=P(g,'A',d1);
  check('W memory','one card up keeps the turn', g.turn, 'A');
  g=P(g,'A',d2);
  check('W memory','a match scores', g.scores.A, 1);
  check('W memory','and keeps the turn', g.turn, 'A');
  check('W memory','a matched card cannot be flipped again',
    play(g,'A',d1).reason, 'occupied');
  const [h1]=idx('house'); const [b1]=idx('beach');
  g=P(g,'A',h1); g=P(g,'A',b1);
  check('W memory','a mismatch hides both again', g.board.revealed.length, 0);
  check('W memory','and passes the turn', g.turn, 'B');
}

// X · STORY — co-op, and there is no winner
{
  let g=newGame('story','s1');
  g=P(g,'A','Once there was a dog who could drive.');
  check('X story','turn alternates', g.turn, 'B');
  g=P(g,'B','He was not very good at parking.');
  check('X story','two lines recorded', g.board.lines.length, 2);
  check('X story','no winner while playing', g.outcome, 'null');
  check('X story','an empty line is refused', play(g,'A','   ').reason, 'empty_contribution');
  for(let i=0;i<18;i++) g=P(g,g.turn,'And then something happened.');
  check('X story','it ends as done, never as a win', g.outcome, 'done');
  check('X story','no side ever wins a story',
    ['A','B'].includes(g.outcome), 'false');
  const art=storyArtifact(g);
  check('X story','§9.8 — a finished story is worth keeping',
    art.title, 'A story we made up');
  check('X story','and carries the whole text', art.body.includes('could drive'), 'true');
  check('X story','no artifact from a non-story', storyArtifact(newGame('tictactoe','z')), 'null');
}

// Y · TAKEBACKS — free, unlimited, either side
{
  let g=newGame('tictactoe','tb');
  g=P(g,'A',0); g=P(g,'B',4); g=P(g,'A',1);
  const back=takeBack(g);
  check('Y takeback','allowed', back.ok, 'true');
  check('Y takeback','restores the board exactly',
    JSON.stringify(back.state.board), JSON.stringify([ 'A',null,null,null,'B',null,null,null,null]));
  check('Y takeback','restores whose turn it was', back.state.turn, 'A');
  check('Y takeback','and the move history', back.state.moves.length, 2);

  let s=back.state; let n=0;
  while(true){ const r=takeBack(s); if(!r.ok) break; s=r.state; n++; }
  check('Y takeback','unlimited, all the way to an empty board', n, 2);
  check('Y takeback','an empty board says so', takeBack(s).reason, 'nothing_to_take_back');

  // The hard case: undoing a move that granted an extra turn.
  let d=newGame('dotsboxes','tb2');
  d=P(d,'A',['h',0,0]); d=P(d,'B',['h',1,0]); d=P(d,'A',['v',0,0]);
  d=P(d,'B',['v',0,1]);
  check('Y takeback','extra-turn state before undo', `${d.scores.B}/${d.turn}`, '1/B');
  const u=takeBack(d).state;
  check('Y takeback','undoing a box-completing move restores the score',
    u.scores.B, 0);
  check('Y takeback','and hands the turn back correctly', u.turn, 'B');

  // A handicap survives a takeback.
  let hg=setHandicap(newGame('tictactoe','tb3'),'A','no_centre').state;
  hg=P(hg,'A',0);
  check('Y takeback','the handicap survives an undo', takeBack(hg).state.handicap, 'no_centre');
}

// Z · VOICE NOTES
{
  let g=newGame('tictactoe','v1');
  g=P(g,'A',0,{artifactId:'a1',durationMs:4200});
  check('Z voice','a move can carry a voice note', g.moves[0].voice.artifactId, 'a1');
  check('Z voice','and it is optional', P(g,'B',4).moves[1].voice, 'undefined');
  check('Z voice','it survives a takeback replay',
    takeBack(P(g,'B',4)).state.moves[0].voice.artifactId, 'a1');
}

// AA · P2 — nothing that ranks a child reaches her
{
  let g=newGame('tictactoe','p1');
  g=P(g,'A',0); g=P(g,'B',4);
  const v=childView(g);
  check('AA P2','child view audits clean', auditChildView(v).ok, 'true');
  check('AA P2','audit catches an ELO',
    auditChildView({...v,elo:1200}).leaks.join(','), 'elo');
  check('AA P2','audit catches a win record',
    auditChildView({nested:[{wins:4,losses:9}]}).ok, 'false');
  check('AA P2','no streak or record field exists at all',
    Object.keys(v).some(k=>/streak|record|wins|losses|rank/i.test(k)), 'false');

  // Losing must not be narrated to her.
  let l=newGame('tictactoe','p2');
  [4,0,0,1,8,2].forEach(()=>{}); // parent takes the diagonal
  l=P(l,'A',0); l=P(l,'B',4); l=P(l,'A',1); l=P(l,'B',3);
  l=P(l,'A',7); l=P(l,'B',5);
  check('AA P2','parent won', l.outcome, 'B');
  check('AA P2','the child is told "Good game", never that she lost',
    childView(l).closing, 'Good game.');
  check('AA P2','no losing language anywhere in her view',
    /lost|lose|defeat|beaten|better/i.test(JSON.stringify(childView(l))), 'false');
  check('AA P2','a story closes warmly, not with a result',
    childView({...newGame('story','x'),outcome:'done'}).closing, 'What a story.');
}

// AB · THE LOSING STREAK — the offer surfaces itself
{
  check('AB streak','no offer after one loss',
    shouldOfferHandicap(['B'],'tictactoe'), 'false');
  check('AB streak',`offer after ${STREAK_BEFORE_OFFER} straight losses`,
    shouldOfferHandicap(['B','B','B'],'tictactoe'), 'true');
  check('AB streak','a win in between resets it',
    shouldOfferHandicap(['B','B','A','B'],'tictactoe'), 'false');
  check('AB streak','draws do not count as losses',
    shouldOfferHandicap(['B','draw','B','draw','B'],'tictactoe'), 'true');
  check('AB streak','co-op games never trigger it',
    shouldOfferHandicap(['B','B','B'],'story'), 'false');

  const o=handicapOffer('tictactoe');
  check('AB streak','the prompt is her choosing, not the product noticing',
    o.prompt, 'Want to make it harder for Dad?');
  check('AB streak','it never mentions losing',
    /lost|losing|keep|struggl|help you/i.test(o.prompt), 'false');
  check('AB streak','and offers real options', o.options.length, 2);
}

// AC · TURN CLOCKS — §4.7
{
  const g=newGame('tictactoe','c1');
  check('AC clocks',`budget is ${DEFAULT_TURN_BUDGET_REACHABLE_HOURS} reachable hours`,
    g.turnBudgetHours, DEFAULT_TURN_BUDGET_REACHABLE_HOURS);
  check('AC clocks','24 wall hours with 2 reachable does not expire a turn',
    turnExpired(g,2), 'false');
  check('AC clocks','8 reachable hours does', turnExpired(g,8), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
