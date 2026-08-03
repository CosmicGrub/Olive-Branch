/**
 * a11y — MASTERFILE §8.8.
 */
import { captionPolicy, captionsSurviveCall, MOTION_FULL, MOTION_REDUCED,
  motionPolicy, TEXT_SCALES, COLLAPSE_TO_ONE_COLUMN_ABOVE, BASE_TAP_PX,
  layoutFor, LABEL_BANNED, auditLabel, LABELS, READ_ALOUD_ON_DEVICE_ONLY,
  READ_ALOUD_NEVER_LOGGED, speakableText, admitSpeech,
  READ_ALOUD_DEFAULT_BELOW_AGE, readAloudDefaultOn } from '../src/a11y.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// FA · §8.8.1 CAPTIONS — on-device, retention follows the call
{
  const live=captionPolicy('live');
  check('FA captions','on-device, always', live.onDevice, 'true');
  check('FA captions','retention follows the call', live.retentionFollowsCall, 'true');
  check('FA captions','both parties are told', live.disclosedToBoth, 'true');
  check('FA captions','the mode is carried', live.mode, 'live');

  check('FA captions','a live-only caption does not survive an unrecorded call',
    captionsSurviveCall(captionPolicy('live'),false), 'false');
  check('FA captions','a saved caption survives only where the call was recorded',
    captionsSurviveCall(captionPolicy('live_and_saved'),true), 'true');
  check('FA captions','not where the call was not recorded',
    captionsSurviveCall(captionPolicy('live_and_saved'),false), 'false');
  check('FA captions','off never survives',
    captionsSurviveCall(captionPolicy('off'),true), 'false');
}

// FB · §8.8.2 MOTION — reduced is not zero
{
  check('FB motion','full motion is not reduced', MOTION_FULL.reduced, 'false');
  check('FB motion','reduced motion is reduced', MOTION_REDUCED.reduced, 'true');
  check('FB motion','a page turn is kept either way',
    MOTION_FULL.essentialMotionKept && MOTION_REDUCED.essentialMotionKept, 'true');
  check('FB motion','reduced is a shorter transition, not zero',
    MOTION_REDUCED.transitionMs>0 && MOTION_REDUCED.transitionMs<MOTION_FULL.transitionMs,
    'true');
  check('FB motion','a preference for reduced motion selects it',
    motionPolicy(true).transitionMs, MOTION_REDUCED.transitionMs);
  check('FB motion','and it is the reduced policy, not just a matching field',
    motionPolicy(true)===MOTION_REDUCED, 'true');
  check('FB motion','otherwise full motion',
    motionPolicy(false)===MOTION_FULL, 'true');
}

// FC · §8.8.3 TEXT SCALE — layout and scale decided together
{
  check('FC scale','six steps', TEXT_SCALES.length, 6);
  check('FC scale','collapses above 1.3', COLLAPSE_TO_ONE_COLUMN_ABOVE, 1.3);
  check('FC scale','a wide viewport at normal scale gets two columns',
    layoutFor(1.0,800).columns, 2);
  check('FC scale','the same viewport past the collapse point gets one',
    layoutFor(1.6,800).columns, 1);
  check('FC scale','a narrow viewport is always one column',
    layoutFor(1.0,400).columns, 1);
  check('FC scale','scale is clamped to the lowest step',
    layoutFor(0.1,800).scale, TEXT_SCALES[0]);
  check('FC scale','and to the highest',
    layoutFor(9,800).scale, TEXT_SCALES[TEXT_SCALES.length-1]);
  check('FC scale','the tap target floor scales up with text',
    layoutFor(2.0,400).minTapPx, Math.round(BASE_TAP_PX*2.0));
  check('FC scale','but never down below the floor',
    layoutFor(0.85,400).minTapPx, BASE_TAP_PX);
}

// FD · §8.8.4 LABELS — a label says what a control DOES
{
  check('FD labels','thirteen banned words', LABEL_BANNED.length, 13);
  check('FD labels','a shape word is caught', auditLabel('the star icon').ok, 'false');
  check('FD labels','so is a direction', auditLabel('the button on the left').ok, 'false');
  check('FD labels','an action-only label passes',
    auditLabel('Keep this story').ok, 'true');
  check('FD labels','the audit names what it found',
    auditLabel('tap here').found.join(','), 'tap here');
  check('FD labels','every LABELS entry itself passes the audit',
    Object.values(LABELS).every(l=>auditLabel(l).ok), 'true');
}

// FE · §8.8.5 READ-ALOUD — speaks the label, never a second copy of it
{
  check('FE speakable','an existing label is spoken verbatim',
    speakableText('star','Star'), LABELS.star);
  check('FE speakable','and it is the SAME string a screen reader gets',
    speakableText('send_show','anything'), LABELS.send_show);
  check('FE speakable','every LABELS entry round-trips through speakableText',
    Object.keys(LABELS).every(id=>speakableText(id,'fallback')===LABELS[id]), 'true');
  check('FE speakable','a control with no label falls back to visible text',
    speakableText('no_such_control','My weeks'), 'My weeks');
  check('FE speakable','an unlabelled fallback never invents a LABELS string',
    Object.values(LABELS).includes(speakableText('no_such_control','My weeks')), 'false');
}

// FF · §8.8.5 NEVER AUTONOMOUS — a tap starts it, nothing else does
{
  check('FF admit','a tap is admitted', admitSpeech('tap').ok, 'true');
  check('FF admit','autonomous speech is refused', admitSpeech('autonomous').ok, 'false');
  check('FF admit','the refusal names the reason',
    admitSpeech('autonomous').reason, 'autonomous');
  check('FF admit','and the refusal names the mechanic',
    /slot-machine/.test(admitSpeech('autonomous').note), 'true');
  check('FF admit','the refusal is unconditional, every single time',
    Array.from({length:5},()=>admitSpeech('autonomous').ok).every(v=>v===false), 'true');
}

// FG · §8.8.5 DEFAULT-ON BELOW 8 — fades like the birthday hint
{
  check('FG age','the threshold is 8', READ_ALOUD_DEFAULT_BELOW_AGE, 8);
  check('FG age','a five-year-old gets it on by default', readAloudDefaultOn(5), 'true');
  check('FG age','a seven-year-old too', readAloudDefaultOn(7), 'true');
  check('FG age','at exactly 8 it is opt-in, not default-on',
    readAloudDefaultOn(8), 'false');
  check('FG age','a nine-year-old is opt-in', readAloudDefaultOn(9), 'false');
  check('FG age','an unknown age is treated the same as young',
    readAloudDefaultOn(null), 'true');
}

// FH · §8.8.5 ON-DEVICE, NEVER LOGGED — not §8.8.1's caption pipeline
{
  check('FH posture','on-device only, always', READ_ALOUD_ON_DEVICE_ONLY, 'true');
  check('FH posture','never logged or retained', READ_ALOUD_NEVER_LOGGED, 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
