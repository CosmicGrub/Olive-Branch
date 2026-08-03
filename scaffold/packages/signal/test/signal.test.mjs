/**
 * The come-back signal and the accessibility matrix.
 * MASTERFILE §5.27, §8.8b. P11.
 */
import { APPLICATIONS, application, admitApplication, MAY_SEND, canSend,
  THIRD_ADULT_REASON, activeInConfiguration, prioritise, senderFeedback,
  IGNORED_SIGNAL_IS_INVISIBLE, auditSenderView, SENDER_FORBIDDEN,
  newState, EXPIRES_AFTER_SECONDS, DAILY_CEILING, SILENT_FROM_HOUR,
  inSilentHours, deliver, expire, dismiss, act, transitionComplete,
  muteForAnHour, muteVisibleToSender, CHILD_MUTE_HOURS,
  SIGNALS_ARE_NEVER_PRESERVED, SIGNALS_IN_COURT_EXPORT, SIGNALS_IN_ARCHIVE,
  escapeHatch, firstRunLesson, MAX_DEFERRED_SIGNALS, deferSignal,
  DEFERRAL_STALE_AFTER_SECONDS, redeliverIfReachable,
  DEFERRAL_INVISIBLE_TO_SENDER, SIGNAL_SYNC_ASYNC_PAIRING } from '../src/signal.mjs';
import { FORMS, form, byReadiness, baselineForms, shippedForms, MIN_CHANNELS,
  channelsCovered, perceivable, baselineIsPerceivable, promote, rollout,
  addForm, presentSignal, auditPresentation } from '../../a11y/src/matrix.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const T='2026-07-27T15:00:00Z';
const ctx=(o={})=>({state:newState(),principal:'parent',configuration:'both_parents',
  childAge:5,windowBlocked:false,localHour:15,surfaceBusy:false,now:T,...o});
const pend=(k,o={})=>({kind:k,fromUserId:'dad',senderIsPresent:false,inCall:false,at:T,...o});

// EO · THE SIXTEEN APPLICATIONS
{
  check('EO apps','sixteen applications', APPLICATIONS.length, 16);
  check('EO apps','every one has copy in her words',
    APPLICATIONS.every(a=>a.copy.length>0&&a.copy.length<50), 'true');
  check('EO apps','every one declares interruptibility',
    APPLICATIONS.every(a=>['always','defers','never'].includes(a.interruptibility)), 'true');
  check('EO apps','and a minimum age', APPLICATIONS.every(a=>a.minAge>=2), 'true');

  // The entry gate.
  check('EO apps','every shipped application is safe if mistapped',
    APPLICATIONS.every(a=>a.safeIfTappedByAccident), 'true');
  check('EO apps','and one that is not would be REFUSED at construction',
    admitApplication({...APPLICATIONS[0],safeIfTappedByAccident:false}).reason,
    'unsafe_if_mistapped');
  check('EO apps','because a prompt in the same place gets tapped reflexively',
    admitApplication(APPLICATIONS[0]).ok, 'true');

  // §9.13.3 — only the parent in the room may invite a handoff.
  check('EO apps','"wave to Mum" comes from the PRESENT parent',
    application('wave_to_other').sender, 'present_parent');
  check('EO apps','and so does "nearly bedtime"',
    application('nearly_bedtime').sender, 'present_parent');
  check('EO apps','"can you hear me" works when audio has failed',
    application('can_you_hear_me').interruptibility, 'always');
  check('EO apps','"sorry, my end" takes the blame off her',
    application('sorry_my_end').copy, 'That was my end. Not you.');
}

// EP · WHO MAY SEND — settled: no third adults
{
  check('EP send','only a parent may send', MAY_SEND.join(), 'parent');
  check('EP send','a grandparent cannot', canSend('grandparent'), 'false');
  check('EP send','nor a stepparent', canSend('stepparent'), 'false');
  check('EP send','nor a therapist', canSend('therapist'), 'false');
  check('EP send','nor a caregiver', canSend('caregiver'), 'false');
  check('EP send','because anyone in the room can simply speak',
    /simply speak/.test(THIRD_ADULT_REASON), 'true');
  check('EP send','a non-parent is refused at delivery',
    deliver(ctx({principal:'grandparent'}),pend('come_back')).reason,
    'sender_not_permitted');
}

// EQ · THE FOUR CONFIGURATIONS
{
  check('EQ config','two parents: active', activeInConfiguration('both_parents'), 'true');
  check('EQ config','one parent: active', activeInConfiguration('one_parent_only'), 'true');
  check('EQ config','sole guardian: active', activeInConfiguration('sole_guardian'), 'true');
  check('EQ config','both in the SAME HOUSE: stands down',
    activeInConfiguration('both_in_same_house'), 'false');
  check('EQ config','because a signal from the next room is absurd',
    deliver(ctx({configuration:'both_in_same_house'}),pend('come_back')).reason,
    'configuration_inactive');
  check('EQ config','and a single-parent family works identically',
    deliver(ctx({configuration:'one_parent_only'}),pend('come_back')).ok, 'true');
  check('EQ config','with nothing hinting a second sender is missing',
    deliver(ctx({configuration:'sole_guardian'}),pend('come_back')).ok, 'true');
}

// ER · PRIORITY
{
  check('ER priority','nothing pending, no winner', prioritise([]), 'null');

  // Rule 2 — presence loses to absence.
  const both=[pend('come_back',{fromUserId:'mum',senderIsPresent:true,at:'2026-07-27T14:00:00Z'}),
              pend('come_back',{fromUserId:'dad',senderIsPresent:false,at:'2026-07-27T15:00:00Z'})];
  const w=prioritise(both);
  check('ER priority','the ABSENT parent wins', w.winner.fromUserId, 'dad');
  check('ER priority','even though the other was first', w.reason, 'absence_beats_presence');
  check('ER priority','because the one she is with can simply talk to her',
    w.winner.senderIsPresent, 'false');

  // Rule 3.
  const calls=[pend('your_turn',{fromUserId:'a',at:'2026-07-27T14:00:00Z'}),
               pend('come_back',{fromUserId:'b',inCall:true,at:'2026-07-27T15:00:00Z'})];
  check('ER priority','a live call outranks a nudge', prioritise(calls).winner.fromUserId, 'b');
  check('ER priority','with the reason named', prioritise(calls).reason, 'in_call');

  // Rule 4 — and NOT seniority.
  const tie=[pend('come_back',{fromUserId:'dad',at:'2026-07-27T14:00:00Z'}),
             pend('come_back',{fromUserId:'mum',at:'2026-07-27T15:00:00Z'})];
  check('ER priority','otherwise simply first', prioritise(tie).winner.fromUserId, 'dad');
  check('ER priority','no custody weighting exists at all',
    JSON.stringify(prioritise(tie)).includes('primary'), 'false');
  check('ER priority','the loser is never told they lost',
    senderFeedback().toldTheyLost, 'false');
}

// ES · THE IGNORED SIGNAL IS INVISIBLE — settled
{
  check('ES ignored','the rule holds', IGNORED_SIGNAL_IS_INVISIBLE, 'true');
  check('ES ignored','the sender is never told she ignored it',
    senderFeedback().toldSheIgnored, 'false');
  check('ES ignored','a clean sender view passes', auditSenderView({sent:true}).ok, 'true');
  check('ES ignored','audit catches a delivery receipt',
    auditSenderView({delivered:true}).leaks.join(','), 'delivered');
  check('ES ignored','and catches an ignored count',
    auditSenderView({ignored:3}).ok, 'false');
  check('ES ignored','and a response rate',
    auditSenderView({a:[{responseRate:0.4}]}).ok, 'false');
  check('ES ignored','and lastSeen', auditSenderView({lastSeen:'2h'}).ok, 'false');
  check('ES ignored','because that is an inference drawn from a child\'s non-tap',
    SENDER_FORBIDDEN.includes('unanswered'), 'true');
}

// ET · THE RULES
{
  check('ET rules',`expires after ${EXPIRES_AFTER_SECONDS}s`, EXPIRES_AFTER_SECONDS, 90);
  check('ET rules','expiry is silent', expire({...newState(),current:pend('come_back')}).current,
    'null');
  check('ET rules','dismissal is free and leaves nothing',
    dismiss({...newState(),current:pend('come_back')}).current, 'null');

  // One at a time.
  let s=deliver(ctx(),pend('come_back')).state;
  const second=deliver(ctx({state:s}),pend('your_turn'));
  check('ET rules','a second REPLACES the first', second.state.current.kind, 'your_turn');
  check('ET rules','a queue would be a demand list', second.state.sentToday, 2);

  // Mid-transition.
  const mid=act(s);
  check('ET rules','she is marked transitioning', mid.transitioning, 'true');
  check('ET rules','a signal mid-transition is DROPPED',
    deliver(ctx({state:mid}),pend('im_here')).reason, 'mid_transition');
  check('ET rules','and accepted once the transition completes',
    deliver(ctx({state:transitionComplete(mid)}),pend('im_here')).ok, 'true');

  // Interruptibility.
  check('ET rules','a "defers" signal waits for a busy surface',
    deliver(ctx({surfaceBusy:true}),pend('come_back')).reason, 'not_interruptible');
  check('ET rules','but an "always" one gets through',
    deliver(ctx({surfaceBusy:true}),pend('can_you_hear_me')).ok, 'true');

  // The ceilings.
  check('ET rules',`a hard daily ceiling of ${DAILY_CEILING}`, DAILY_CEILING, 12);
  check('ET rules','independent of the age bands',
    deliver(ctx({state:{...newState(),sentToday:12}}),pend('come_back')).reason,
    'daily_ceiling');
  check('ET rules','because 16 applications x 2 parents could satisfy every other rule',
    APPLICATIONS.length*2 > DAILY_CEILING, 'true');
  check('ET rules',`silent from ${SILENT_FROM_HOUR}:00`, inSilentHours(21), 'true');
  check('ET rules','and through the night', inSilentHours(3), 'true');
  check('ET rules','not in the afternoon', inSilentHours(15), 'false');
  check('ET rules','nothing fires in silent hours',
    deliver(ctx({localHour:22}),pend('come_back')).reason, 'silent_hours');
  check('ET rules','a blocked window blocks it',
    deliver(ctx({windowBlocked:true}),pend('come_back')).reason, 'blocked_window');
  check('ET rules','too young is refused',
    deliver(ctx({childAge:2}),pend('turn_it_round')).reason, 'too_young');

  // She can mute.
  const muted=muteForAnHour(newState(),T);
  check('ET rules',`she can mute everything for ${CHILD_MUTE_HOURS}h`,
    deliver(ctx({state:muted}),pend('come_back')).reason, 'muted');
  check('ET rules','nobody is told she muted', muteVisibleToSender(), 'false');
  check('ET rules','because if she cannot opt out it is not a request',
    muted.mutedUntil>T, 'true');

  // Never preserved.
  check('ET rules','signals are gestures, not messages', SIGNALS_ARE_NEVER_PRESERVED, 'true');
  check('ET rules','never in a court export', SIGNALS_IN_COURT_EXPORT, 'false');
  check('ET rules','never in the archive', SIGNALS_IN_ARCHIVE, 'false');
}

// EU · THE ESCAPE HATCH AND FIRST RUN
{
  const e=escapeHatch();
  check('EU hatch','reachable in one tap', e.reachableInTaps, 1);
  check('EU hatch','on every surface', e.presentOnEverySurface, 'true');
  check('EU hatch','and she can never lose it', e.dismissible, 'false');
  check('EU hatch','which is why "come back" is usually unnecessary',
    e.label, 'Back to Dad');

  const l=firstRunLesson();
  check('EU hatch','she meets it once in onboarding', l.kind, 'come_back');
  check('EU hatch','and must actually tap it', l.requiresTap, 'true');
  check('EU hatch','a pattern learned calm is recognised confused',
    /Give it a tap/.test(l.copy), 'true');
}

// EV · THE ACCESSIBILITY MATRIX
{
  check('EV matrix','nineteen forms declared', FORMS.length, 19);
  check('EV matrix','four readiness states',
    new Set(FORMS.map(f=>f.readiness)).size, 4);
  check('EV matrix','four baseline forms', baselineForms().length, 4);
  check('EV matrix','nine shipped', shippedForms().length, 9);
  check('EV matrix','three scaffolded', byReadiness('scaffolded').length, 3);
  check('EV matrix','four specified', byReadiness('specified').length, 4);
  check('EV matrix','three considered', byReadiness('considered').length, 3);
  check('EV matrix','every form names its channel',
    FORMS.every(f=>['sight','hearing','touch','cognition','motor'].includes(f.channel)),
    'true');
  check('EV matrix','and carries a note', FORMS.every(f=>f.note.length>20), 'true');

  // The rule that shapes it.
  check('EV matrix',`at least ${MIN_CHANNELS} independent channels`, MIN_CHANNELS, 2);
  check('EV matrix','the BASELINE alone satisfies it', baselineIsPerceivable(), 'true');
  check('EV matrix','covering sight and hearing',
    channelsCovered(baselineForms().map(f=>f.id)).sort().join(), 'hearing,sight');
  check('EV matrix','text alone is NOT perceivable',
    perceivable(['visual_text']).ok, 'false');
  check('EV matrix','nor sound alone', perceivable(['spoken']).ok, 'false');
  check('EV matrix','text plus spoken is', perceivable(['visual_text','spoken']).ok, 'true');
  check('EV matrix','a scaffolded form does not count toward coverage',
    channelsCovered(['haptic']).length, 0);
  check('EV matrix','because it does not render yet', form('haptic').readiness, 'scaffolded');

  // Rolling one out.
  const r=promote(FORMS,'haptic','shipped',[]);
  check('EV matrix','shipping with an unmet requirement is REFUSED', r.reason,
    'unmet_requirement');
  check('EV matrix','and it names what is missing', r.missing.join(), 'device vibrator');
  check('EV matrix','meeting it allows the promotion',
    promote(FORMS,'haptic','shipped',['device vibrator']).ok, 'true');
  check('EV matrix','readiness never moves backwards',
    promote(FORMS,'spoken','specified',[]).reason, 'backwards');
  check('EV matrix','an unknown form is refused',
    promote(FORMS,'nope','shipped',[]).reason, 'unknown_form');
  check('EV matrix','promoting to scaffolded needs nothing',
    promote(FORMS,'sign_video','specified',[]).ok, 'true');

  // Extensible.
  const extra={id:'braille_note',label:'Braille note-taker',channel:'touch',
    readiness:'considered',baseline:false,requires:[],
    note:'Added later without touching any consumer, because the matrix is data.'};
  check('EV matrix','a form can be added at any time', addForm(FORMS,extra).length, 20);
  check('EV matrix','and adding twice is idempotent',
    addForm(addForm(FORMS,extra),extra).length, 20);

  const roll=rollout();
  check('EV matrix','the roadmap stays honest', roll.shipped, 9);
  check('EV matrix','and names what is next up', roll.nextUp.length, 3);
  check('EV matrix','with its requirements',
    roll.nextUp.every(n=>Array.isArray(n.requires)), 'true');
}

// EW · PRESENTATION
{
  const p=presentSignal(['haptic','large_text']);
  check('EW present','the baseline is always included', p.forms.length>=4, 'true');
  check('EW present','it is perceivable', p.perceivable, 'true');
  check('EW present','never sound alone', p.soundOnly, 'false');
  check('EW present','never colour alone', p.colourOnly, 'false');
  check('EW present','audit passes', auditPresentation(p).ok, 'true');
  check('EW present','audit catches a sound-only presentation',
    auditPresentation({...p,soundOnly:true}).leaks.join(','), 'soundOnly');
  check('EW present','and a colour-only one',
    auditPresentation({...p,colourOnly:true}).ok, 'false');
  check('EW present','and one requiring sight',
    auditPresentation({requiresSight:true}).ok, 'false');
  check('EW present','enabling nothing still works',
    presentSignal([]).perceivable, 'true');
}

// EX · §5.27.9 REACHABLE-HOURS DEFERRAL
{
  const nowSec=Math.floor(Date.parse(T)/1000);

  // Silent hours: blocked, then deferred, then redelivered once reachable.
  const blockedSilent=deliver(ctx({localHour:22}),pend('come_back'));
  check('EX defer','still blocked in silent hours', blockedSilent.reason, 'silent_hours');
  const deferredSilent=deferSignal(pend('come_back'),blockedSilent.reason,T);
  check('EX defer','recorded, not dropped', deferredSilent.pending.kind, 'come_back');
  check('EX defer','with the reason it was blocked for', deferredSilent.reason, 'silent_hours');
  const redeliveredSilent=redeliverIfReachable(deferredSilent,nowSec+60);
  check('EX defer','redelivered once she is reachable', redeliveredSilent.ok, 'true');
  check('EX defer','carrying the original signal', redeliveredSilent.pending.kind, 'come_back');

  // A blocked window defers the same way.
  const blockedWindow=deliver(ctx({windowBlocked:true}),pend('nearly_there'));
  check('EX defer','a blocked window is also deferred, not dropped',
    blockedWindow.reason, 'blocked_window');
  const deferredWindow=deferSignal(pend('nearly_there'),blockedWindow.reason,T);
  const redeliveredWindow=redeliverIfReachable(deferredWindow,nowSec+10);
  check('EX defer','and redelivers once the window clears', redeliveredWindow.ok, 'true');

  // Capped at one — a second deferral replaces, never queues.
  check('EX defer','capped at one, never a queue', MAX_DEFERRED_SIGNALS, 1);
  let slot=deferSignal(pend('come_back'),'silent_hours',T);
  slot=deferSignal(pend('your_turn'),'blocked_window',T);
  check('EX defer','a second deferral REPLACES the first', slot.pending.kind, 'your_turn');
  check('EX defer','with the newer reason, not the older one', slot.reason, 'blocked_window');

  // Stale after DEFERRAL_STALE_AFTER_SECONDS.
  check('EX defer',`stale after ${DEFERRAL_STALE_AFTER_SECONDS}s`,
    DEFERRAL_STALE_AFTER_SECONDS, 3600);
  const stillFresh=redeliverIfReachable(deferredSilent,nowSec+DEFERRAL_STALE_AFTER_SECONDS);
  check('EX defer','still redeliverable exactly at the boundary', stillFresh.ok, 'true');
  const goneStale=redeliverIfReachable(deferredSilent,
    nowSec+DEFERRAL_STALE_AFTER_SECONDS+1);
  check('EX defer','a stale deferral refuses redelivery', goneStale.ok, 'false');
  check('EX defer','naming why', goneStale.reason, 'stale');

  // Invisible to the sender — same as ignored, same as dropped.
  check('EX defer','a deferral is not a delivery receipt',
    DEFERRAL_INVISIBLE_TO_SENDER, 'true');
  check('EX defer','its shape never leaks into the sender view',
    auditSenderView(deferredSilent).ok, 'true');
  check('EX defer','not even when it is nested inside other state',
    auditSenderView({state:{deferred:deferredSilent}}).ok, 'true');
  check('EX defer','no forbidden key sneaks in under a new name',
    auditSenderView(deferredSilent).ok===false
      ? auditSenderView(deferredSilent).leaks.join(',') : 'none', 'none');

  // Named for §8.15's sync/async pairing table.
  check('EX defer','names the synchronous form',
    typeof SIGNAL_SYNC_ASYNC_PAIRING.sync, 'string');
  check('EX defer','and the asynchronous form',
    typeof SIGNAL_SYNC_ASYNC_PAIRING.async, 'string');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
