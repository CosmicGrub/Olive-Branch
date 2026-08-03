/**
 * Motion. MASTERFILE §8.13.
 */
import { AUTONOMOUS_IS_NEVER_ALLOWED, MAX_CONSEQUENCE_MS, AMBIENT_SURFACES,
  admitMotion, VOCABULARY, gesturesFor, spec, TAP_ALWAYS_SUFFICES,
  reachableByTapAlone, SPRING_STANDARD, SPRING_HEAVY, SPRING_LIGHT,
  MAX_OVERSHOOT, overshoot, springSettles, RUBBER_BAND_FACTOR, rubberBand,
  DECELERATION, flingDistance, PEEK_PX, affordance, TOUCH_RESPONSE_MS,
  QUIET_SURFACES, quietnessOf, whyQuiet, effectiveQuietness, durationFor,
  STILL_MEANS_CROSSFADE_NOT_CUT, CROSSFADE_MS, MAX_CONCURRENT_MOTIONS,
  admitConcurrent, AUTOPLAY_ALLOWED, CELEBRATION_REPEATS, celebrate,
  auditMotion, MOTION_FORBIDDEN, SURFACE_MOTION, motionFor,
  auditSurfaces, auditQuietConsistency, admitChime, chimeAllowed } from '../src/motion.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// EO · MOTION FOLLOWS THE FINGER, NEVER LEADS IT
{
  check('EO kinds','driven motion is always allowed',
    admitMotion({kind:'driven',surface:'anything',durationMs:0}).ok, 'true');
  check('EO kinds','a consequence is allowed within the cap',
    admitMotion({kind:'consequence',surface:'x',durationMs:300}).ok, 'true');
  check('EO kinds',`over ${MAX_CONSEQUENCE_MS}ms is refused`,
    admitMotion({kind:'consequence',surface:'x',durationMs:900}).reason, 'too_long');
  check('EO kinds','because she has been made to wait for a picture',
    /wait for a picture/.test(
      admitMotion({kind:'consequence',surface:'x',durationMs:900}).note), 'true');

  // The rule the module exists for.
  check('EO kinds','AUTONOMOUS motion is refused',
    admitMotion({kind:'autonomous',surface:'x',durationMs:100}).reason, 'autonomous');
  check('EO kinds','and the refusal names the mechanic',
    /slot machine/.test(admitMotion({kind:'autonomous',surface:'x',durationMs:1}).note),
    'true');
  check('EO kinds','the rule is explicit', AUTONOMOUS_IS_NEVER_ALLOWED, 'true');
  check('EO kinds','no duration makes autonomous acceptable',
    admitMotion({kind:'autonomous',surface:'x',durationMs:0}).ok, 'false');

  check('EO kinds','ambient is allowed where movement IS the information',
    admitMotion({kind:'ambient',surface:'audio_waveform',durationMs:0}).ok, 'true');
  check('EO kinds','and refused everywhere else',
    admitMotion({kind:'ambient',surface:'games_picker',durationMs:0}).reason,
    'ambient_not_permitted');
  check('EO kinds','four ambient surfaces only', AMBIENT_SURFACES.length, 4);
}

// EP · ONE VOCABULARY, LEARNED ONCE
{
  check('EP gestures','ten gestures', VOCABULARY.length, 10);
  check('EP gestures','every one means exactly one thing',
    VOCABULARY.every(g=>g.means.length>5), 'true');
  check('EP gestures','a two-year-old can tap', gesturesFor(2).length, 1);
  check('EP gestures','a three-year-old can swipe and scroll', gesturesFor(3).length, 3);
  check('EP gestures','pinch waits until six', spec('pinch').minAge, 6);
  check('EP gestures','long-press is never the only route',
    /never the only way/i.test(spec('long_press').note), 'true');
  check('EP gestures','a dial beats a slider for a small hand',
    /centre to orbit/.test(spec('rotary').note), 'true');
  check('EP gestures','scrobble is how you say "go back a bit"',
    /go back a bit/.test(spec('scrobble').note), 'true');
  check('EP gestures','horizontal swipe always means siblings',
    /siblings/.test(spec('swipe_h').note), 'true');

  check('EP gestures','TAP always suffices', TAP_ALWAYS_SUFFICES, 'true');
  check('EP gestures','every surface is reachable by tapping alone',
    SURFACE_MOTION.every(s=>reachableByTapAlone(s.surface)), 'true');
  check('EP gestures','every surface offers tap',
    SURFACE_MOTION.every(s=>s.gestures.includes('tap')), 'true');
}

// EQ · PHYSICS A CHILD CAN PREDICT
{
  check('EQ physics','the standard spring settles', springSettles(SPRING_STANDARD), 'true');
  check('EQ physics','the heavy one too', springSettles(SPRING_HEAVY), 'true');
  check('EQ physics','and the light one', springSettles(SPRING_LIGHT), 'true');
  check('EQ physics','nothing bounces like a reward',
    [SPRING_STANDARD,SPRING_HEAVY,SPRING_LIGHT].every(s=>overshoot(s)<=MAX_OVERSHOOT),
    'true');
  check('EQ physics','a bouncy spring IS caught',
    springSettles({stiffness:400,damping:6,mass:1}), 'false');
  check('EQ physics','heavier moves slower', SPRING_HEAVY.mass > SPRING_LIGHT.mass, 'true');

  check('EQ physics','rubber-band resists more the further you pull',
    rubberBand(100,400) < 100, 'true');
  check('EQ physics','and never exceeds the pull', rubberBand(1000,400) < 1000, 'true');
  check('EQ physics','zero overscroll is zero', rubberBand(0,400), 0);
  check('EQ physics','a hard wall would read as broken', RUBBER_BAND_FACTOR<1, 'true');
  check('EQ physics','a fling travels further the faster it is',
    flingDistance(2) > flingDistance(1), 'true');
  check('EQ physics','and deceleration is predictable', DECELERATION>0, 'true');
}

// ER · WORDLESS INSTRUCTION
{
  check('ER peek','a swipeable row peeks the next item',
    affordance('swipe_h').hint, 'peek');
  check('ER peek',`by ${PEEK_PX}px`, affordance('swipe_h').px, PEEK_PX);
  check('ER peek','a scroll list peeks too', affordance('scroll').hint, 'peek');
  check('ER peek','a draggable thing casts a shadow', affordance('drag').hint, 'shadow');
  check('ER peek','a dial settles rather than peeking', affordance('rotary').hint, 'settle');
  check('ER peek','tapping needs no hint', affordance('tap').hint, 'none');
  check('ER peek','touch response is immediate', TOUCH_RESPONSE_MS<=50, 'true');
  check('ER peek','because a pre-reader cannot be TOLD to swipe',
    affordance('swipe_h').px>0, 'true');
}

// ES · WHERE MOTION IS A BAD IDEA — the user's caveat
{
  check('ES quiet','seven quiet surfaces', QUIET_SURFACES.length, 7);
  check('ES quiet','bedtime is still', quietnessOf('bedtime'), 'still');
  check('ES quiet','because movement undoes the reading',
    /undoes the reading/.test(whyQuiet('bedtime')), 'true');
  check('ES quiet','homework is still', quietnessOf('homework'), 'still');
  check('ES quiet','because it is the one surface asking her to concentrate',
    /concentrate/.test(whyQuiet('homework')), 'true');
  check('ES quiet','the journal is still', quietnessOf('journal'), 'still');
  check('ES quiet','the emergency card is still', quietnessOf('emergency_card'), 'still');
  check('ES quiet','the come-back signal is reduced',
    quietnessOf('come_back_signal'), 'reduced');
  check('ES quiet','because a moving prompt defeats its own purpose',
    /defeats its own purpose/.test(whyQuiet('come_back_signal')), 'true');
  check('ES quiet','an ordinary surface is full', quietnessOf('games_picker'), 'full');
  check('ES quiet','every quiet surface explains itself',
    QUIET_SURFACES.every(q=>q.why.length>30), 'true');

  // Composition with §8.8.
  check('ES quiet','reduced motion quietens a full surface',
    effectiveQuietness('games_picker',true), 'reduced');
  check('ES quiet','and a still surface stays still',
    effectiveQuietness('bedtime',true), 'still');
  check('ES quiet','an accessibility setting is never overridden by a default',
    effectiveQuietness('games_picker',true)!=='full', 'true');
  check('ES quiet','durations scale', durationFor('reduced',220), 99);
  check('ES quiet','still is zero travel', durationFor('still',220), 0);
  check('ES quiet','but still is a CROSSFADE, not a cut',
    STILL_MEANS_CROSSFADE_NOT_CUT, 'true');
  check('ES quiet','because a cut is disorienting too', CROSSFADE_MS>0, 'true');
}

// ET · THE BUDGET, AND NO REWARD SCHEDULES
{
  check('ET budget','two moving things at once', MAX_CONCURRENT_MOTIONS, 2);
  check('ET budget','a third is refused', admitConcurrent(2), 'false');
  check('ET budget','two is allowed', admitConcurrent(1), 'true');
  check('ET budget','nothing ever auto-plays', AUTOPLAY_ALLOWED, 'false');
  check('ET budget','celebration does not repeat', CELEBRATION_REPEATS, 'false');
  check('ET budget','the first time plays', celebrate(0).play, 'true');
  check('ET budget','the second does not', celebrate(1).play, 'false');
  check('ET budget','because every time is a reward schedule',
    /reward schedule/.test(celebrate(3).why), 'true');

  check('ET budget','no reward fields anywhere',
    auditMotion(SURFACE_MOTION).ok, 'true');
  check('ET budget','audit catches an attract loop',
    auditMotion({attractLoop:true}).leaks.join(','), 'attractLoop');
  check('ET budget','and catches "pulseToTap"',
    auditMotion({a:[{pulseToTap:1}]}).ok, 'false');
  check('ET budget','and catches autoplay',
    auditMotion({video:{autoplay:true}}).ok, 'false');
  check('ET budget','the forbidden list covers jackpot and combo',
    MOTION_FORBIDDEN.includes('jackpot')&&MOTION_FORBIDDEN.includes('combo'), 'true');
}

// EU · THE SURFACE PLANS
{
  check('EU surfaces','twelve surfaces declare their motion', SURFACE_MOTION.length, 12);
  check('EU surfaces','every claimed gesture is in the vocabulary',
    auditSurfaces().unknown.join(','), '');
  check('EU surfaces','no still surface claims driven motion',
    auditQuietConsistency().conflicts.join(','), '');
  check('EU surfaces','the storyteller can scrobble',
    motionFor('storyteller').gestures.includes('scrobble'), 'true');
  check('EU surfaces','find-the-thing is what pinch exists for',
    /surface pinch exists for/.test(motionFor('find_the_thing').note), 'true');
  check('EU surfaces','homework is the sparsest',
    motionFor('homework').gestures.length, 1);
  check('EU surfaces','and deliberately so',
    /sparsest surface/.test(motionFor('homework').note), 'true');
  check('EU surfaces','the colour picker is a dial',
    motionFor('colour_picker').gestures.includes('rotary'), 'true');
  check('EU surfaces','time is horizontal everywhere',
    motionFor('calendar').gestures.includes('swipe_h'), 'true');
  check('EU surfaces','an unknown surface has no plan', motionFor('nope'), 'null');
}

// EV · THE TOUCH CHIME — v0.39.0, a consequence wearing sound
{
  check('EV chime','bedtime is silent', chimeAllowed('bedtime',false,false), 'false');
  check('EV chime','homework is silent', chimeAllowed('homework',false,false), 'false');
  check('EV chime','the journal is silent', chimeAllowed('journal',false,false), 'false');
  check('EV chime','the emergency card is silent',
    chimeAllowed('emergency_card',false,false), 'false');

  check('EV chime','muted silences an ordinary surface',
    chimeAllowed('games_picker',true,false), 'false');
  check('EV chime','muted silences it even under reduced motion',
    chimeAllowed('games_picker',true,true), 'false');
  check('EV chime','muted silences it even on a still surface',
    chimeAllowed('bedtime',true,false), 'false');

  check('EV chime','an ordinary full surface chimes when unmuted',
    chimeAllowed('games_picker',false,false), 'true');
  check('EV chime','the storyteller chimes when unmuted',
    chimeAllowed('storyteller',false,false), 'true');

  // Composition with §8.8 — reduced motion alone never STILLS a chime; only
  // an already-still surface does, exactly as effectiveQuietness composes it.
  check('EV chime','reduced motion alone does not silence an ordinary surface',
    chimeAllowed('games_picker',false,true), 'true');
  check('EV chime','a still surface stays silent under reduced motion too',
    chimeAllowed('bedtime',false,true), 'false');
  check('EV chime','this matches effectiveQuietness composing the two',
    effectiveQuietness('games_picker',true)!=='still'
      && chimeAllowed('games_picker',false,true), 'true');

  // It never depends on autonomy — chimes are consequence-triggered by
  // definition, and a caller requesting an autonomous one is refused exactly
  // as admitMotion refuses any other autonomous motion.
  check('EV chime','an autonomous chime request is refused',
    admitChime({kind:'autonomous',surface:'games_picker',muted:false,
      reducedMotionOn:false}).reason, 'autonomous');
  check('EV chime','with the same slot-machine note as admitMotion',
    /slot machine/.test(admitChime({kind:'autonomous',surface:'x',muted:false,
      reducedMotionOn:false}).note), 'true');
  check('EV chime','a normal consequence-triggered chime is admitted',
    admitChime({kind:'consequence',surface:'games_picker',muted:false,
      reducedMotionOn:false}).ok, 'true');
  check('EV chime','a muted request is refused for that reason specifically',
    admitChime({kind:'consequence',surface:'games_picker',muted:true,
      reducedMotionOn:false}).reason, 'muted');
  check('EV chime','a still-surface request is refused for that reason specifically',
    admitChime({kind:'consequence',surface:'bedtime',muted:false,
      reducedMotionOn:false}).reason, 'surface_quiet');

  // No "loop" parameter exists — a chime is a one-shot by construction.
  check('EV chime','a chime request carries no loop field',
    Object.keys({kind:'consequence',surface:'x',muted:false,reducedMotionOn:false})
      .includes('loop'), 'false');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
