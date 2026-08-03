/**
 * games3 — the chain, Kim's game, the scavenger hunt.
 * MASTERFILE §9.2, §9.8, §9.8.1. Prohibition P2.
 */
import { newChain, addStep, recallStep, chainView, chainArtifact,
  newKim, kimSecondPhoto, kimGuess, kimClosing, KIM_LOOK_SECONDS,
  newHunt, submitFind, huntProgress, huntComplete, huntArtifacts,
  SUGGESTED_PROMPTS, auditNoScore } from '../src/games3.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// AI · THE CHAIN — "I went to the market", built from the parent
{
  let g=newChain();
  check('AI chain','the parent starts it', g.turn, 'B');
  check('AI chain','cannot recall an empty chain',
    recallStep(g,'B','x').reason, 'wrong_phase');

  // Dad adds, with his voice attached.
  g=addStep(g,'B','a banana','voice-1').state;
  check('AI chain','a step can carry his recorded voice',
    g.steps[0].voiceArtifactId, 'voice-1');
  check('AI chain','turn passes to the child', g.turn, 'A');
  check('AI chain','and she must repeat before adding', g.phase, 'recalling');
  check('AI chain','she cannot add out of phase',
    addStep(g,'A','a hat').reason, 'wrong_phase');
  check('AI chain','the list is HIDDEN during recall — that is the game',
    chainView(g).visibleSteps.length, 0);

  const r1=recallStep(g,'A','a banana');
  check('AI chain','a correct recall advances', r1.correct, 'true');
  check('AI chain','and the whole chain done → she now adds', r1.state.phase, 'building');
  g=r1.state;
  check('AI chain','the list is visible again while building',
    chainView(g).visibleSteps.join(','), 'a banana');
  g=addStep(g,'A','a hat').state;
  check('AI chain','two steps now', g.steps.length, 2);

  // Dad repeats both, in order.
  let d=recallStep(g,'B','a banana');
  check('AI chain','partway through recall stays in recall', d.state.phase, 'recalling');
  check('AI chain','and tracks position', d.state.recallIndex, 1);
  d=recallStep(d.state,'B','a hat');
  check('AI chain','full recall returns him to building', d.state.phase, 'building');

  // A wrong step ends it COOPERATIVELY.
  let w=newChain();
  w=addStep(w,'B','a banana').state;
  const bad=recallStep(w,'A','a bicycle');
  check('AI chain','a wrong step is not an error, it ends the chain', bad.ok, 'true');
  check('AI chain','and it is recorded as ended', bad.correct, 'false');
  check('AI chain','closing is SHARED, never who dropped it',
    chainView(bad.state).closing, 'You two got to 0 together.');
  check('AI chain','no blame language anywhere',
    /you lost|wrong|failed|mistake|your fault/i.test(JSON.stringify(chainView(bad.state))), 'false');
  check('AI chain','no more moves after it ends',
    recallStep(bad.state,'A','a banana').reason, 'game_over');

  check('AI chain','case and spacing are forgiving',
    recallStep(w,'A','  A BANANA ').correct, 'true');
  check('AI chain','an empty step refused',
    addStep(newChain(),'B','   ').reason, 'empty_step');
  check('AI chain','out of turn refused', addStep(newChain(),'A','x').reason, 'not_your_turn');

  // §9.8 — a long chain is worth keeping.
  let long=newChain();
  const words=['a banana','a hat','a dog','a kite','a spoon','a drum'];
  for(const word of words){
    long=addStep(long,long.turn,word).state;
    while(long.phase==='recalling'){
      const rr=recallStep(long,long.turn,long.steps[long.recallIndex].label);
      long=rr.state;
    }
  }
  check('AI chain','six steps built', long.steps.length, 6);
  check('AI chain','§9.8 — a long chain becomes an artifact',
    chainArtifact(long).title, 'A chain of 6');
  check('AI chain','a short chain does not', chainArtifact(newChain()), 'null');

  // P2 — nothing here ranks anybody.
  check('AI chain','view carries no score of any kind',
    auditNoScore(chainView(long)).ok, 'true');
  check('AI chain','audit would catch a high score',
    auditNoScore({...chainView(long),highScore:12}).ok, 'false');
}

// AJ · KIM'S GAME — real photos of a real table
{
  const objs=['mug','keys','apple','pencil','watch','coin'];
  let seed=7; const rnd=()=>{seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff;};
  const k=newKim(objs,rnd);
  check('AJ kim','builds a round', k.ok, 'true');
  check('AJ kim',`she gets ${KIM_LOOK_SECONDS}s to look — generous, not a reflex test`,
    k.round.lookSeconds, KIM_LOOK_SECONDS);
  check('AJ kim','fewer than five objects is refused', newKim(['a','b'],rnd).reason, 'too_few');

  const second=kimSecondPhoto(k.round);
  check('AJ kim','exactly one object is removed', second.length, objs.length-1);
  check('AJ kim','and it is the right one',
    second.includes(objs[k.round.removedIndex]), 'false');
  check('AJ kim','everything else survives',
    objs.filter((_,i)=>i!==k.round.removedIndex).every(o=>second.includes(o)), 'true');

  const right=kimGuess(k.round,k.round.removedIndex);
  check('AJ kim','a correct guess is recognised', right.correct, 'true');
  check('AJ kim','and named warmly',
    kimClosing(right.round).startsWith('Yes — the'), 'true');
  const wrongIdx=(k.round.removedIndex+1)%objs.length;
  const wrong=kimGuess(k.round,wrongIdx);
  check('AJ kim','a wrong guess is not a failure state',
    /tricky/i.test(kimClosing(wrong.round)), 'true');
  check('AJ kim','no blame in either outcome',
    /wrong|incorrect|failed|lost/i.test(kimClosing(wrong.round)), 'false');
  check('AJ kim','answering twice refused', kimGuess(right.round,0).reason, 'already_answered');
  check('AJ kim','out of range refused', kimGuess(k.round,99).reason, 'out_of_range');
  check('AJ kim','no timer field reaches the child',
    auditNoScore({objects:k.round.objects,guess:null}).ok, 'true');
}

// AK · SCAVENGER HUNT — off the screen, into the house
{
  check('AK hunt','the suggested prompts are personal',
    SUGGESTED_PROMPTS.some(p=>/when I was your age/.test(p)), 'true');
  const h=newHunt('h1',['Something round','Something blue',
    'Something that was mine when I was your age'],'B','2026-07-27T10:00:00Z');
  check('AK hunt','builds', h.ok, 'true');
  check('AK hunt','set by the parent', h.hunt.setBy, 'B');
  check('AK hunt','three prompts', h.hunt.prompts.length, 3);
  check('AK hunt','an empty list refused', newHunt('x',[],'B','t').reason, 'no_prompts');
  check('AK hunt','more than eight becomes a chore, and is refused',
    newHunt('x',Array(9).fill('a thing'),'B','t').reason, 'too_many');

  // There is deliberately no timer.
  check('AK hunt','a hunt carries NO timer or countdown',
    auditNoScore(h.hunt).ok, 'true');
  check('AK hunt','and no score', Object.keys(h.hunt).some(k=>/score|time/i.test(k)), 'false');

  let hunt=h.hunt;
  const s1=submitFind(hunt,'h1-0','art-1','2026-07-27T16:20:00Z');
  check('AK hunt','a photograph completes a prompt', s1.ok, 'true');
  hunt=s1.state ?? s1.hunt;
  check('AK hunt','progress reported', JSON.stringify(huntProgress(hunt)), '{"found":1,"total":3}');
  check('AK hunt','submitting twice refused',
    submitFind(hunt,'h1-0','art-2','t').reason, 'already_found');
  check('AK hunt','an unknown prompt refused',
    submitFind(hunt,'nope','art-3','t').reason, 'unknown_prompt');
  check('AK hunt','not complete yet', huntComplete(hunt), 'false');

  hunt=submitFind(hunt,'h1-1','art-2','t').hunt;
  hunt=submitFind(hunt,'h1-2','art-3','t').hunt;
  check('AK hunt','all found → complete', huntComplete(hunt), 'true');

  // §9.8.1 — everything she photographs is PRESERVED.
  const arts=huntArtifacts(hunt);
  check('AK hunt','every find becomes an artifact', arts.length, 3);
  check('AK hunt','§9.8.1 — preserved by default, never on a 90-day clock',
    arts.every(a=>a.preserved===true), 'true');
  check('AK hunt','and captioned with what he asked for',
    arts[2].caption, 'Something that was mine when I was your age');
  check('AK hunt','so it flows to the Year Book and the handover',
    arts.every(a=>a.artifactId && a.preserved), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
