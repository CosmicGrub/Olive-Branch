/**
 * The call layer. MASTERFILE §5.23, §5.24, §5.25. P10.
 */
import { setMode, modeForOther, CAUSE_NEVER_DISCLOSED, auditModeDisclosure,
  canSwitchOwnCamera, canSwitchOthersCamera, listening, WAVEFORM_HZ_CALM,
  NEVER_BLANK, bedtime, pushToTalk, PTT_MAX_SECONDS, pttChildView,
  answerOptions, optionsEquallyWeighted, troubleView, auditTrouble,
  TROUBLE_BANNED, LADDER, stepDown, stepUp, BOTTOM_ALWAYS_WORKS, rungLine,
  preserve, restore, RECONNECT_PRESERVES_STATE, resumeOffer,
  networkChangeAdvice, SURVIVES_NETWORK_CHANGE } from '../src/modes.mjs';
import { camera, flip, setZoom, MAX_ZOOM, canTorch, framing, lightingAdvice,
  auditLighting, P10_NO_APPEARANCE_MODIFICATION, BANNED_VIDEO_EFFECTS,
  ALLOWED_VIDEO_EFFECTS, admitEffect, backgroundAllowed, defaultRoute,
  headphoneNote, auditHeadphoneNote, MAX_CHILD_VOLUME, clampVolume, echoRisk,
  pipFor, pipWindow, PIP_MIN_PX, IN_LAYOUT_IS_NOT_PIP, recordingDisclosure,
  RECORDING_PREVENTABLE } from '../src/camera.mjs';
import { onPostureChange, detectPosture, HINGE_NEVER_ENDS_CALL, expandsOnUnfold,
  knock, KNOCK_WAITS_SECONDS, knockUnanswered, ANSWER_WORDS, auditAnswerWords,
  notNowOutcome, handOff, HANDOFF_MAX_GAP_SECONDS, OLD_DEVICE_RELEASES_CAPTURE,
  suggestFromOverlap, suggestionVisibleTo, waitingRoom, joinWaiting, admit,
  waitingVisibleTo, childWaitingView } from '../src/lifecycle.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const T='2026-07-27T19:00:00Z';

// DW · AUDIO-ONLY AS A CHOICE
{
  const chosen=setMode('audio_only','chosen',T);
  check('DW audio','she can choose voice only', chosen.mode, 'audio_only');
  const other=modeForOther(chosen);
  check('DW audio','he is told the mode', other.mode, 'audio_only');
  check('DW audio','and the line is neutral', other.line, 'Voice only just now.');
  check('DW audio','he is NEVER told why', JSON.stringify(other).includes('chosen'), 'false');
  check('DW audio','the rule is explicit', CAUSE_NEVER_DISCLOSED, 'true');
  check('DW audio','audit catches a cause leaking',
    auditModeDisclosure({mode:'audio_only',cause:'chosen'}).leak, 'chosen');
  check('DW audio','and catches "camera off" phrasing',
    auditModeDisclosure({line:'She turned her camera off'}).ok, 'false');
  check('DW audio','the neutral line passes', auditModeDisclosure(other).ok, 'true');
  check('DW audio','she switches her own camera', canSwitchOwnCamera(), 'true');
  check('DW audio','nobody switches anybody else\'s', canSwitchOthersCamera(), 'false');

  const l=listening('#F0757E');
  check('DW audio','never a black screen', NEVER_BLANK, 'true');
  check('DW audio','her colour is the surface', l.surface, 'her_colour');
  check('DW audio','the waveform is calm', l.waveformHz, WAVEFORM_HZ_CALM);
  check('DW audio','a fast waveform would be a stimulant at bedtime',
    WAVEFORM_HZ_CALM<=6, 'true');

  const b=bedtime('#F0757E');
  check('DW audio','bedtime is audio only', b.mode, 'audio_only');
  check('DW audio','the screen nearly goes out', b.screenBrightness<0.1, 'true');
  check('DW audio','but the call stays up', b.keepsCallAlive, 'true');
}

// DX · PUSH TO TALK, AND ANSWERING
{
  const n=pushToTalk('v1','A',20,T);
  check('DX ptt','a voice note records', n.ok, 'true');
  check('DX ptt',`over ${PTT_MAX_SECONDS}s is refused`,
    pushToTalk('x','A',90,T).reason, 'too_long');
  check('DX ptt','a stray tap is refused', pushToTalk('x','A',0,T).reason, 'too_short');
  check('DX ptt','no read receipt reaches her',
    JSON.stringify(pttChildView([n.note])).includes('heard'), 'false');
  check('DX ptt','she is told how many are waiting', pttChildView([n.note]).count, 1);

  const o=answerOptions();
  check('DX answer','three ways to answer', o.length, 3);
  check('DX answer','voice-only is the SAME SIZE as video', optionsEquallyWeighted(o), 'true');
  check('DX answer','"Not now" is one of them',
    o.some(x=>x.kind==='not_now'), 'true');
  check('DX answer','and nothing says decline', auditAnswerWords(ANSWER_WORDS).ok, 'true');
  check('DX answer','audit catches "Decline"',
    auditAnswerWords(['Answer','Decline']).found.join(), 'Decline');
  check('DX answer','"not now" tells him she is busy, not that she refused',
    /busy just now/.test(notNowOutcome().senderTold), 'true');
}

// DY · WHEN IT GOES WRONG
{
  check('DY trouble','frozen is not ended',
    troubleView('frozen').line, 'The picture stopped. He is still there.');
  check('DY trouble','and she is told to wait', troubleView('frozen').waiting, 'true');
  check('DY trouble','ended is the only one that is not waiting',
    troubleView('ended').waiting, 'false');
  check('DY trouble','dropped promises he is coming back',
    /getting him back/.test(troubleView('dropped').line), 'true');
  check('DY trouble','no state says "failed"',
    ['frozen','slow','dropped','reconnecting','ended']
      .every(s=>auditTrouble(troubleView(s)).ok), 'true');
  check('DY trouble','audit catches "connection failed"',
    auditTrouble({state:'dropped',line:'Connection failed.',waiting:false}).ok, 'false');
  check('DY trouble','and catches blaming her network',
    auditTrouble({state:'slow',line:'Check your network.',waiting:true}).ok, 'false');
  check('DY trouble','the banned list is substantial', TROUBLE_BANNED.length>=10, 'true');

  check('DY ladder','four rungs', LADDER.length, 4);
  check('DY ladder','hd falls to sd', stepDown('hd'), 'sd');
  check('DY ladder','sd falls to audio', stepDown('sd'), 'audio_only');
  check('DY ladder','audio falls to banked', stepDown('audio_only'), 'banked');
  check('DY ladder','and the bottom rung stays put', stepDown('banked'), 'banked');
  check('DY ladder','because the bottom always works', BOTTOM_ALWAYS_WORKS, 'true');
  check('DY ladder','it climbs back up too', stepUp('audio_only'), 'sd');
  check('DY ladder','the bottom rung explains itself',
    /record him something instead/.test(rungLine('banked')), 'true');
  check('DY ladder','and the others say nothing', rungLine('sd'), '');
}

// DZ · RECONNECTION
{
  const before={activity:'checkers',activityState:{move:14},storyLine:null,elapsedSeconds:300};
  check('DZ reconnect','state is preserved',
    JSON.stringify(restore(preserve(before),{elapsedSeconds:312}).activityState),
    '{"move":14}');
  check('DZ reconnect','and the rule is explicit', RECONNECT_PRESERVES_STATE, 'true');
  check('DZ reconnect','resuming ASKS — it does not auto-transmit',
    resumeOffer().autoResumes, 'false');
  check('DZ reconnect','because a bedroom coming back on the wifi is a privacy failure',
    /carry on/.test(resumeOffer().line), 'true');
  check('DZ reconnect','a metered network is flagged',
    /use data now/.test(networkChangeAdvice({from:'wifi',to:'lte',metered:true})), 'true');
  check('DZ reconnect','an unmetered one says nothing',
    networkChangeAdvice({from:'lte',to:'wifi',metered:false}), 'null');
  check('DZ reconnect','the call survives the switch', SURVIVES_NETWORK_CHANGE, 'true');
}

// EA · THE REAR CAMERA — "show me", live
{
  let c=camera();
  check('EA camera','starts on the front', c.facing, 'front');
  check('EA camera','and mirrored, which is right for a face', c.mirrored, 'true');
  c=flip(c);
  check('EA camera','flipping goes to the rear', c.facing, 'rear');
  check('EA camera','and turns mirroring OFF', c.mirrored, 'false');
  check('EA camera','so writing is not backwards', c.mirrored, 'false');
  check('EA camera','flipping back re-mirrors', flip(c).mirrored, 'true');
  check('EA camera','zoom is bounded', setZoom(c,99).zoom, MAX_ZOOM);
  check('EA camera','and never below 1', setZoom(c,0.1).zoom, 1);
  check('EA camera','the torch is rear-only', canTorch(c), 'true');
  check('EA camera','never a flash in her face', canTorch(camera()), 'false');
  check('EA camera','auto-framing never pans out of frame',
    framing(true).pansBeyondFrame, 'false');
  check('EA camera','dark rooms get advice about the ROOM',
    /is there a light/.test(lightingAdvice(10)), 'true');
  check('EA camera','a lit room gets none', lightingAdvice(200), 'null');
  check('EA camera','and the advice never mentions how she looks',
    auditLighting(lightingAdvice(10)).ok, 'true');
  check('EA camera','audit catches "you look dark"',
    auditLighting('You look very dark').ok, 'false');
}

// EB · P10 — NO APPEARANCE MODIFICATION
{
  check('EB p10','the prohibition holds', P10_NO_APPEARANCE_MODIFICATION, 'true');
  check('EB p10','a beauty filter is refused',
    admitEffect('beauty_mode').reason, 'appearance_modification');
  check('EB p10','skin smoothing is refused', admitEffect('skin_smoothing').ok, 'false');
  check('EB p10','face slimming is refused', admitEffect('face_slim').ok, 'false');
  check('EB p10','eye enlargement is refused', admitEffect('eye_enlarge').ok, 'false');
  check('EB p10','and "touch up", however it is dressed',
    admitEffect('gentle_touch_up').ok, 'false');
  check('EB p10','fifteen named effects are banned', BANNED_VIDEO_EFFECTS.length>=14, 'true');
  check('EB p10','but silly is fine — dog ears are not a beauty filter',
    admitEffect('dog_ears').ok, 'true');
  check('EB p10','and so are googly eyes', admitEffect('googly_eyes').ok, 'true');
  check('EB p10','every allowed effect passes',
    ALLOWED_VIDEO_EFFECTS.every(e=>admitEffect(e).ok), 'true');

  check('EB p10','a guardian may use a virtual background',
    backgroundAllowed('guardian'), 'true');
  check('EB p10','a CHILD may not', backgroundAllowed('child'), 'false');
}

// EC · AUDIO ROUTING
{
  check('EC audio','a child defaults to speaker',
    defaultRoute('child',false,false), 'speaker');
  check('EC audio','a guardian to earpiece', defaultRoute('guardian',false,false), 'earpiece');
  check('EC audio','wired wins', defaultRoute('child',true,false), 'wired');
  check('EC audio','then bluetooth', defaultRoute('child',false,true), 'bluetooth');
  check('EC audio','headphones are mentioned neutrally',
    headphoneNote(true), 'She has headphones in.');
  check('EC audio','and never characterised as privacy',
    auditHeadphoneNote(headphoneNote(true)).ok, 'true');
  check('EC audio','audit catches "she is alone"',
    auditHeadphoneNote('She has headphones in, so she is alone.').ok, 'false');
  check('EC audio','no note when they are out', headphoneNote(false), 'null');
  check('EC audio','a child cannot exceed the hearing ceiling',
    clampVolume(1,'child'), MAX_CHILD_VOLUME);
  check('EC audio','an adult can', clampVolume(1,'guardian'), 1);
  check('EC audio','siblings in one room are warned',
    /use headphones/.test(echoRisk(2,true).advice), 'true');
  check('EC audio','and not when they are apart', echoRisk(2,false).advice, 'null');
}

// ED · PiP CONFLICTS WITH THE LOCK
{
  const locked=pipFor('child',true);
  check('ED pip','a locked child gets NO pip', locked.kind, 'none');
  check('ED pip','because there is nothing for it to solve',
    /nothing for PiP to solve/.test(locked.reason), 'true');
  check('ED pip','and enabling it would hole the lock',
    /hole in the lock/.test(locked.reason), 'true');
  check('ED pip','an unlocked child device gets the in-layout pane',
    pipFor('child',false).kind, 'in_layout');
  check('ED pip','a guardian gets real OS pip', pipFor('guardian',false).kind, 'os_native');
  check('ED pip','which is the case pip is actually for',
    /while doing other things/.test(pipFor('guardian',false).reason), 'true');
  check('ED pip','the window is remembered', pipWindow().remembered, 'true');
  check('ED pip','tapping returns to the call', pipWindow().tapReturns, 'true');
  check('ED pip','never smaller than a recognisable face', pipWindow().minPx, PIP_MIN_PX);
  check('ED pip','and an in-layout pane is NOT called pip', IN_LAYOUT_IS_NOT_PIP, 'true');
  check('ED pip','recording is disclosed where detectable',
    /recording/.test(recordingDisclosure('ios')), 'true');
  check('ED pip','and never claimed to be preventable', RECORDING_PREVENTABLE, 'false');
}

// EE · THE FOLD, MID-CALL
{
  check('EE fold','a hinge never ends a call', HINGE_NEVER_ENDS_CALL, 'true');
  const p=onPostureChange('fold_cover','fold_main');
  check('EE fold','unfolding keeps the call', p.callSurvives, 'true');
  check('EE fold','and relays out side by side', p.relayout, 'side_by_side');
  check('EE fold','opening from folded expands the same session',
    expandsOnUnfold('fold_cover','fold_main'), 'true');
  const t=onPostureChange('fold_main','fold_tabletop');
  check('EE fold','half-open relayouts to tabletop', t.relayout, 'tabletop');
  check('EE fold','and it is the ONLY posture that announces itself',
    t.announce, 'You can put it down now — he can still see you.');
  check('EE fold','the others are silent', p.announce, 'null');

  check('EE fold','tabletop is detected from the viewport',
    detectPosture(700,440), 'fold_tabletop');
  check('EE fold','folded too', detectPosture(344,882), 'fold_cover');
  check('EE fold','unfolded too', detectPosture(673,841), 'fold_main');
  check('EE fold','so it works without a vendor hinge API',
    detectPosture(1400,800), 'dex');
}

// EF · KNOCKING, HANDOFF, SUGGESTIONS, WAITING
{
  const k=knock('dad',T);
  check('EF knock',`a knock waits ${KNOCK_WAITS_SECONDS}s`, k.waitsSeconds, 90);
  check('EF knock','and never escalates', k.escalates, 'false');
  check('EF knock','unanswered, it becomes a banked message',
    knockUnanswered().becomes, 'banked_message');
  check('EF knock','and he is told she did not come, not that she refused',
    /did not come to it/.test(knockUnanswered().toldToSender), 'true');
  check('EF knock','nothing says missed or declined',
    /missed|declined|rejected/i.test(knockUnanswered().toldToSender), 'false');

  const h=handOff('tablet','phone',['tablet','phone']);
  check('EF handoff','she moves between her own devices', h.ok, 'true');
  check('EF handoff','it is the same session', h.handoff.sameSession, 'true');
  check('EF handoff',`with at most a ${HANDOFF_MAX_GAP_SECONDS}s gap`,
    h.handoff.maxGapSeconds, 6);
  check('EF handoff','not to a device that is not hers',
    handOff('tablet','someone_elses',['tablet','phone']).reason, 'not_her_device');
  check('EF handoff','the old device releases capture', OLD_DEVICE_RELEASES_CAPTURE, 'true');

  const s=suggestFromOverlap({dow:2,startMinute:1020,endMinute:1080},'Olive');
  check('EF suggest','the overlap is finally used for something',
    s.line, 'Olive is free then, and so are you.');
  check('EF suggest','it goes to the guardian', s.audience, 'guardian');
  check('EF suggest','and NEVER to the child', suggestionVisibleTo('child'), 'false');
  check('EF suggest','because his availability is not her responsibility',
    suggestionVisibleTo('guardian'), 'true');

  let w=waitingRoom('r1','sup');
  check('EF waiting','she is admitted first', w.childAdmittedFirst, 'true');
  w=joinWaiting(w,'dad',T);
  check('EF waiting','the supervised party waits', w.waiting.length, 1);
  check('EF waiting','and can be admitted', admit(w,'dad').waiting.length, 0);
  check('EF waiting','she never sees who is waiting', waitingVisibleTo('child'), 'false');
  check('EF waiting','the supervisor does', waitingVisibleTo('supervisor'), 'true');
  check('EF waiting','she just sees "nearly ready"', childWaitingView().line, 'Nearly ready.');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
