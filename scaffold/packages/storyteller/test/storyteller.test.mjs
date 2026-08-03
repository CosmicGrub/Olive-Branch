/**
 * storyteller — MASTERFILE §9.11. Built for a five-year-old.
 */
import { rng, seedFromCode, codeFromSeed, MAX_SEED, CODE_LENGTH, HEROES,
  OPENINGS_LEADIN, OPENINGS_STANDALONE, COMPANIONS, SETTINGS,
  PROBLEMS, COMPLICATIONS, HELPERS, RESOLUTIONS, REFRAINS, OPENINGS, ENDINGS,
  SILLY_DETAILS, WEATHERS, SHAPES, SHAPE_TITLES, spaceSize, generate,
  freshStory, reread, auditStory, corpus, BANNED_CONTENT, forReadingAloud,
  storyArtifact, MAX_PERSONAL_TOUCHES, WORDS_PER_MINUTE_ALOUD }
  from '../src/storyteller.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// BR · THE SIZE — the promise that it never repeats
{
  const n=spaceSize();
  check('BR size','eight shapes', SHAPES.length, 8);
  check('BR size','forty heroes', HEROES.length, 40);
  check('BR size','thirty problems', PROBLEMS.length, 30);
  check('BR size','twenty refrains', REFRAINS.length, 20);
  check('BR size','the space is over ten trillion', n > 1e13, 'true');
  check('BR size',`(it is ${n.toExponential(2)})`, n>0, 'true');
  // A story a night for a whole childhood is a rounding error of it.
  check('BR size','a nightly story for 18 years uses under a billionth of it',
    (365*18)/n < 1e-9, 'true');
  check('BR size','every pool is non-trivial',
    [HEROES,COMPANIONS,SETTINGS,PROBLEMS,COMPLICATIONS,HELPERS,RESOLUTIONS,
     REFRAINS,OPENINGS,ENDINGS,SILLY_DETAILS,WEATHERS].every(p=>p.length>=16), 'true');
  check('BR size','no duplicate heroes', new Set(HEROES).size, HEROES.length);
  check('BR size','no duplicate problems', new Set(PROBLEMS).size, PROBLEMS.length);
  check('BR size','no duplicate refrains', new Set(REFRAINS).size, REFRAINS.length);
}

// BS · DETERMINISM — "read me the octopus one again"
{
  const a=generate(12345), b=generate(12345);
  check('BS reread','the same seed gives the same story',
    JSON.stringify(a.lines), JSON.stringify(b.lines));
  check('BS reread','a different seed does not',
    generate(12345).title===generate(999).title
      && generate(12345).lines[0].text===generate(999).lines[0].text, 'false');

  check('BS reread','a story is a six-character code', a.code.length, 6);
  check('BS reread','the code round-trips',
    reread(a.code).lines[0].text, a.lines[0].text);
  check('BS reread','and the code is stable', codeFromSeed(a.seed), a.code);
  check('BS reread','codes avoid confusable characters',
    /[01IOU]/.test(codeFromSeed(4242)), 'false');
  // The round trip is the assertion that caught this being broken.
  check('BS reread','code → seed → code is exact',
    codeFromSeed(seedFromCode(a.code)), a.code);
  check('BS reread','seed → code → seed is exact too',
    seedFromCode(codeFromSeed(123456)), 123456);
  check('BS reread','and it holds across the whole code space',
    [0,1,29,842,99999,594823320].every(n=>seedFromCode(codeFromSeed(n))===n), 'true');
  check('BS reread','a lowercase code still works',
    reread(a.code.toLowerCase()).lines[0].text, a.lines[0].text);

  // A saved story is six characters, not a paragraph.
  check('BS reread','so storing 1000 favourites costs 6 KB, not megabytes',
    a.code.length*1000, 6000);

  let dup=0; const seen=new Set();
  for(let i=0;i<3000;i++){
    const s=generate(i*7919+13);
    const k=s.lines.map(l=>l.text).join('|');
    if(seen.has(k)) dup++; seen.add(k);
  }
  check('BS reread','3000 seeds produce 3000 distinct stories', dup, 0);
}

// BT · SAFE FOR FIVE — the guard runs on OUTPUT
{
  // The whole vocabulary, swept.
  const bad=corpus().filter(line=>{
    const t=line.toLowerCase();
    return BANNED_CONTENT.some(w=> w.includes(' ')
      ? t.includes(w)
      : new RegExp('\\b'+w+'\\b').test(t));
  });
  check('BT safe','no banned content anywhere in the corpus', bad.join(' | '), '');
  // "begun" contains "gun". A word guard must match word boundaries.
  check('BT safe','"begun" does not trip the "gun" rule',
    auditStory({code:'X',seed:0,shape:'the_swap',title:'T',refrain:'r',
      readSeconds:60,personalTouches:0,
      lines:[{text:'The day had begun so well.',isRefrain:false}]}).ok, 'true');
  check('BT safe','but an actual gun does',
    auditStory({code:'X',seed:0,shape:'the_swap',title:'T',refrain:'r',
      readSeconds:60,personalTouches:0,
      lines:[{text:'He had a gun.',isRefrain:false}]}).ok, 'false');
  check('BT safe','and "diet" does not trip "die"',
    auditStory({code:'X',seed:0,shape:'the_swap',title:'T',refrain:'r',
      readSeconds:60,personalTouches:0,
      lines:[{text:'She was on a strict diet of biscuits.',isRefrain:false}]}).ok,
    'true');

  // 4000 generated stories, audited as output.
  let fails=[];
  for(let i=0;i<4000;i++){
    const s=generate(i*104729+7);
    const a=auditStory(s);
    if(!a.ok) fails.push(s.code+': '+a.found.join(','));
  }
  check('BT safe','4000 generated stories all pass the audit',
    fails.slice(0,2).join(' | '), '');

  // The guard must be able to fail, or it is not a guard.
  const planted={code:'X',seed:0,shape:'the_swap',title:'T',refrain:'r',
    readSeconds:60,personalTouches:0,
    lines:[{text:'The monster was terrified and the dog died.',isRefrain:false}]};
  check('BT safe','the audit CATCHES frightening content',
    auditStory(planted).ok, 'false');
  check('BT safe','and names what it found',
    auditStory(planted).found.includes('monster'), 'true');

  // The guard that matters most in THIS product.
  const family={...planted,lines:[{text:'She lived in two houses, one with Mummy and Daddy apart.',isRefrain:false}]};
  check('BT safe','§9.11.4 — a story about her parents is REFUSED',
    auditStory(family).ok, 'false');
  check('BT safe','"two houses" is on the banned list',
    BANNED_CONTENT.includes('two houses'), 'true');
  check('BT safe','so is divorce', BANNED_CONTENT.includes('divorce'), 'true');
  check('BT safe','and custody', BANNED_CONTENT.includes('custody'), 'true');
  const adult={...planted,lines:[{text:'They had wine and talked about rent.',isRefrain:false}]};
  check('BT safe','adult subject matter is refused', auditStory(adult).ok, 'false');
  check('BT safe','the banned list is substantial', BANNED_CONTENT.length>=50, 'true');
}

// BU · THE REFRAIN — the thing most generators leave out
{
  const s=generate(777);
  const refrains=s.lines.filter(l=>l.isRefrain);
  check('BU refrain','a story has a refrain', refrains.length>0, 'true');
  check('BU refrain','and it repeats three times', refrains.length, 3);
  check('BU refrain','always the same words',
    new Set(refrains.map(l=>l.text)).size, 1);
  check('BU refrain','it matches the story\'s declared refrain', refrains[0].text, s.refrain);
  check('BU refrain','refrains are short enough to shout',
    REFRAINS.every(r=>r.length<=48), 'true');
  check('BU refrain','every seed gets one',
    [1,2,3,4,5,99,1000].every(n=>generate(n).lines.some(l=>l.isRefrain)), 'true');
}

// BV · READ ALOUD — for a parent at bedtime
{
  const s=generate(31337);
  check('BV aloud','a story is short enough for bedtime', s.lines.length<=12, 'true');
  check('BV aloud','read time is estimated', s.readSeconds>=30, 'true');
  check('BV aloud','and it is under two minutes', s.readSeconds<=120, 'true');
  check('BV aloud',`at ${WORDS_PER_MINUTE_ALOUD} words a minute aloud`,
    WORDS_PER_MINUTE_ALOUD, 130);

  const ra=forReadingAloud(s);
  check('BV aloud','her line is marked for him',
    ra.blocks.filter(b=>b.herLine).length, 3);
  check('BV aloud','with a pause after it',
    ra.blocks.filter(b=>b.herLine).every(b=>b.pauseAfter), 'true');
  check('BV aloud','and a hint that tells him what to do',
    /let her say it/.test(ra.hint), 'true');
  check('BV aloud','the title is human', ra.title.length>3, 'true');
  check('BV aloud','every shape has a title',
    SHAPES.every(sh=>SHAPE_TITLES[sh]&&SHAPE_TITLES[sh].length>3), 'true');
  check('BV aloud','no line is a wall of text',
    s.lines.every(l=>l.text.length<=180), 'true');

  // Grammar, checked across many seeds — the failures only show when read aloud.
  const grammar=[];
  for(let i=0;i<800;i++){
    const st=generate(i*7717+3,{childName:'OLIVE',colour:'coral pink'});
    for(const l of st.lines){
      if(/\.\s+[a-z]/.test(l.text)) grammar.push('lowercase after full stop: '+l.text);
      if(/\bfound,\s/.test(l.text)) grammar.push('mangled helper line: '+l.text);
      if(/,\s+who was no help/.test(l.text)) grammar.push('who/which agreement: '+l.text);
      if(/\s{2,}/.test(l.text)) grammar.push('double space: '+l.text);
      if(!/[.!?]$/.test(l.text.trim())) grammar.push('no terminal punctuation: '+l.text);
    }
  }
  check('BV aloud','800 stories, no grammatical breakage',
    grammar.slice(0,2).join(' | '), '');
  check('BV aloud','lead-in openings flow into the clause',
    OPENINGS_LEADIN.every(o=>!/[.!?]$/.test(o)), 'true');
  check('BV aloud','standalone openings are complete sentences',
    OPENINGS_STANDALONE.every(o=>/[.!?]$/.test(o)), 'true');
}

// BW · PERSONALISATION — one mention is delightful, six is a mail merge
{
  const p={childName:'OLIVE',colour:'coral pink',interests:['dinosaurs','Pokémon']};
  const s=generate(555,p);
  check('BW personal',`at most ${MAX_PERSONAL_TOUCHES} touches`,
    s.personalTouches<=MAX_PERSONAL_TOUCHES, 'true');
  const text=s.lines.map(l=>l.text).join(' ');
  check('BW personal','her name appears at most once',
    (text.match(/OLIVE/g)||[]).length<=1, 'true');
  check('BW personal','the story is still about the animal, not her',
    text.includes(HEROES.find(h=>text.includes(h))||'@@'), 'true');
  check('BW personal','with no personalisation it still works',
    generate(555).lines.length, s.lines.length);
  check('BW personal','and the refrain is never personalised',
    generate(555,p).lines.filter(l=>l.isRefrain)
      .every(l=>!l.text.includes('OLIVE')), 'true');
  check('BW personal','her spelling is used verbatim, however she spelled it',
    generate(555,{childName:'OLIVEE'}).lines.some(l=>l.text.includes('OLIVEE'))
      || generate(555,{childName:'OLIVEE'}).personalTouches===0, 'true');
}

// BX · KEEPING ONE
{
  const s=generate(2468);
  check('BX keep','asked for once, not yet kept', storyArtifact(s,1), 'null');
  check('BX keep','asked for twice, kept', storyArtifact(s,2).preserved, 'true');
  check('BX keep','and it is stored as six characters',
    storyArtifact(s,3).code.length, 6);
  check('BX keep','with its title', storyArtifact(s,2).title, s.title);
}

// BY · A FRESH ONE EVERY TIME
{
  let seed=1; const rnd=()=>{seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff;};
  const codes=new Set();
  for(let i=0;i<200;i++) codes.add(freshStory({},rnd).code);
  check('BY fresh','200 fresh stories, 200 distinct codes', codes.size, 200);
  check('BY fresh','and all of them audit clean',
    [...Array(200)].every(()=>auditStory(freshStory({},rnd)).ok), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
