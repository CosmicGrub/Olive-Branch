/**
 * The ten items. MASTERFILE §10.5, §8.12, §12.8–§12.11.
 */
import { PUSH_CHANNELS, SMS_ESCALATE_AFTER_MINUTES, route, senderStatus,
  auditStatus, ADULT_SMS, auditAdultSms, socketPolicy, reachability }
  from '../../transport/src/channels.mjs';
import { TABLETOP, tabletopPlacementOk, TABLETOP_KEEPS_CALL_ALIVE,
  LANDSCAPE, landscapeFor, ROTATION_PRESERVES_STATE, onRotate,
  requestExport, requestConfirmation, reviewableAt, requestableAt,
  REQUEST_MIN_WIDTH, REVIEW_MIN_WIDTH,
  WEB_ALLOWED, WEB_DENIED, webCan, NO_INSTALL_MINIMUM, noInstallSufficient,
  WEB_INVITE_COPY, auditInvite } from '../src/postures.mjs';
import { startGroupCall, soloOrder, nextSolo, waitingView, auditGroup,
  SOLO_SECONDS_EACH, MAX_CHILDREN_ON_A_CALL,
  therapistView, auditTherapist, THERAPIST_FORBIDDEN,
  shouldPrompt, promptCopy, answerPrompt, auditPrompt, PROMPTABLE_KINDS,
  tapPing, SAME_LINE, guardianPingView, auditAtLimit }
  from '../../guardian/src/pending.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
const T='2026-07-27T12:00:00Z';

// DL · THE FALLBACK THAT WAS DECLARED AND NOT BUILT
{
  const base={channel:'android_amazon',appForeground:false,socketConnected:false,
    adultNumberOnFile:true,minutesWaiting:0};
  check('DL route','a Play device pushes',
    route({...base,channel:'android_play'}).route, 'push');
  check('DL route','iOS pushes', route({...base,channel:'ios'}).route, 'push');
  check('DL route','FireOS does not', PUSH_CHANNELS.includes('android_amazon'), 'false');

  check('DL route','with the app open, the socket carries it',
    route({...base,appForeground:true,socketConnected:true}).route, 'socket');
  check('DL route','a socket without foreground does not count',
    route({...base,socketConnected:true}).route, 'none');
  check('DL route','and it says why',
    route({...base,socketConnected:true}).rejected.find(r=>r.route==='socket').because,
    'app is not in the foreground');

  check('DL route','a text escalates only after 90 minutes',
    route({...base,minutesWaiting:120}).route, 'sms_to_adult');
  check('DL route',`not at ${SMS_ESCALATE_AFTER_MINUTES-1}`,
    route({...base,minutesWaiting:89}).route, 'none');
  check('DL route','because a text 30 seconds later turns a drawing into an alarm',
    SMS_ESCALATE_AFTER_MINUTES>=60, 'true');
  check('DL route','no adult number means no text',
    route({...base,adultNumberOnFile:false,minutesWaiting:500}).route, 'none');
  check('DL route','and that state is marked unreachable',
    route({...base,adultNumberOnFile:false,minutesWaiting:500}).unreachable, 'true');
  check('DL route','every rejection is recorded for audit',
    route(base).rejected.length, 3);
}

// DM · THE SENDER IS TOLD THE TRUTH
{
  const s1=senderStatus(route({channel:'ios',appForeground:false,
    socketConnected:false,adultNumberOnFile:true,minutesWaiting:0}),'Olive');
  check('DM truth','a push says sent', s1.delivered, 'true');
  const s2=senderStatus(route({channel:'android_amazon',appForeground:true,
    socketConnected:true,adultNumberOnFile:true,minutesWaiting:0}),'Olive');
  check('DM truth','a socket says she has it now',
    /she has it now/.test(s2.line), 'true');
  const s3=senderStatus(route({channel:'android_amazon',appForeground:false,
    socketConnected:false,adultNumberOnFile:true,minutesWaiting:120}),'Olive');
  check('DM truth','a text says exactly what happened',
    /texted the grown-up/.test(s3.line), 'true');

  const s4=senderStatus(route({channel:'android_amazon',appForeground:false,
    socketConnected:false,adultNumberOnFile:false,minutesWaiting:500}),'Olive');
  check('DM truth','unreachable is NOT reported as delivered', s4.delivered, 'false');
  check('DM truth','he is told it is saved and when she will see it',
    /the moment she opens Olive/.test(s4.line), 'true');
  check('DM truth','and given the one thing he can do', s4.actionable, 'true');
  check('DM truth','no undelivered status claims delivery', auditStatus(s4).ok, 'true');
  check('DM truth','audit catches a false claim',
    auditStatus({delivered:false,actionable:false,line:'Delivered to Olive.'}).ok,
    'false');
  check('DM truth','a delivered one may say so',
    auditStatus({delivered:true,actionable:false,line:'Delivered.'}).ok, 'true');
}

// DN · THE TEXT TO THE ADULT
{
  check('DN sms','it names nobody and says nothing', auditAdultSms(ADULT_SMS).ok, 'true');
  check('DN sms','audit catches a sender',
    auditAdultSms('Olive: a message from Dad is waiting.').ok, 'false');
  check('DN sms','and catches content',
    auditAdultSms('Olive: new photo waiting.').found.includes('photo'), 'true');
  check('DN sms','because the other parent may be in the room',
    ADULT_SMS.length<60, 'true');

  const p=socketPolicy();
  check('DN sms','the socket is held only in the foreground', p.holdInBackground, 'false');
  check('DN sms','because a background socket ends in an uninstall',
    /ends in an uninstall/.test(p.note), 'true');
  check('DN sms','backoff is bounded', p.reconnectBackoffMs.length, 5);
  check('DN sms','a guardian is told plainly what alerts do',
    /only arrive while Olive is open/.test(reachability('android_amazon').line), 'true');
  check('DN sms','and for a push device, that it works when closed',
    /even when Olive is closed/.test(reachability('ios').line), 'true');
}

// DO · THE TABLETOP LAYOUT
{
  check('DO tabletop','video above, controls below', TABLETOP.above.region, 'video');
  check('DO tabletop','the crease is HORIZONTAL in this posture',
    TABLETOP.creaseAxis, 'horizontal');
  check('DO tabletop','the fractions sum to one',
    TABLETOP.above.heightFraction+TABLETOP.below.heightFraction, 1);
  check('DO tabletop','nothing interactive above the hinge',
    tabletopPlacementOk('controls',true), 'false');
  check('DO tabletop','video above is fine', tabletopPlacementOk('video',true), 'true');
  check('DO tabletop','anything below is fine', tabletopPlacementOk('controls',false), 'true');
  check('DO tabletop','putting it down does not end the call',
    TABLETOP_KEEPS_CALL_ALIVE, 'true');
  check('DO tabletop','and the note says why the posture matters',
    /play on the floor/.test(TABLETOP.note), 'true');
}

// DP · LANDSCAPE
{
  check('DP landscape','seven postures have an arrangement', LANDSCAPE.length, 7);
  check('DP landscape','a 10-inch tablet splits left/right',
    landscapeFor('tablet_large').primary, 'left');
  check('DP landscape','and it is the common case there',
    /common case for this size, not the exception/.test(landscapeFor('tablet_large').note),
    'true');
  check('DP landscape','the unfolded Fold splits on its vertical crease',
    landscapeFor('fold_main').split, 0.5);
  check('DP landscape','but tabletop splits TOP/BOTTOM — the hinge is horizontal',
    landscapeFor('fold_tabletop').primary, 'top');
  check('DP landscape','every split is a real fraction',
    LANDSCAPE.every(l=>l.split>0&&l.split<1), 'true');
  check('DP landscape','a folded Fold has no landscape arrangement',
    landscapeFor('fold_cover'), 'null');
  check('DP landscape','rotating never loses her place', ROTATION_PRESERVES_STATE, 'true');
  check('DP landscape','state survives rotation',
    JSON.stringify(onRotate({half:'coloured'})), '{"half":"coloured"}');
}

// DQ · THE DEGRADED EXPORT — the thing the audit demanded by name
{
  const r=requestExport('e1','dad','olive','solicitor','2026-01-01','2026-06-30',T);
  check('DQ export','a request builds', r.ok, 'true');
  check('DQ export','it is not ready yet', r.request.readyAt, 'null');
  check('DQ export','an inverted range is refused',
    requestExport('x','dad','olive','court','2026-06-30','2026-01-01',T).reason,
    'inverted_range');
  check('DQ export','a future range is refused',
    requestExport('x','dad','olive','court','2027-01-01','2027-02-01',T).reason,
    'future_range');

  check('DQ export',`requesting works at ${REQUEST_MIN_WIDTH}px`,
    requestableAt(REQUEST_MIN_WIDTH), 'true');
  check('DQ export','and on a folded Fold', requestableAt(344), 'true');
  check('DQ export','reviewing needs more room', reviewableAt(344), 'false');
  check('DQ export',`which is ${REVIEW_MIN_WIDTH}px`, reviewableAt(REVIEW_MIN_WIDTH), 'true');
  check('DQ export','the confirmation does not pretend he can review it there',
    /needs a bigger screen/.test(requestConfirmation(r.request)), 'true');
  check('DQ export','and tells him it will be waiting',
    /it will be waiting/.test(requestConfirmation(r.request)), 'true');
}

// DR · THE NO-INSTALL WEB PATH
{
  check('DR web','six capabilities on the web', WEB_ALLOWED.length, 6);
  check('DR web','joining a call needs no install', webCan('join_call'), 'true');
  check('DR web','so does replying', webCan('send_message'), 'true');
  check('DR web','the child shell is not on the web', webCan('child_shell'), 'false');
  check('DR web','three things are denied, each with a reason', WEB_DENIED.length, 3);
  check('DR web','and the child shell reason is the kiosk',
    /no kiosk exists in a browser tab/.test(WEB_DENIED[0].because), 'true');
  check('DR web','the minimum viable relationship is reachable without an app',
    noInstallSufficient(), 'true');
  check('DR web','which is a call and a reply', NO_INSTALL_MINIMUM.length, 2);
  check('DR web','the invitation reads as an offer',
    /nothing to install/.test(WEB_INVITE_COPY), 'true');
  check('DR web','and never as a demand', auditInvite(WEB_INVITE_COPY).ok, 'true');
  check('DR web','audit catches a legal framing',
    auditInvite('You are required to respond by the court deadline.').ok, 'false');
}

// DS · THE SIBLING GROUP CALL
{
  const g=startGroupCall('dad',['olive','sam'],T);
  check('DS group','two children start one', g.ok, 'true');
  check('DS group','one child is not a group', startGroupCall('dad',['olive'],T).reason,
    'need_two');
  check('DS group',`more than ${MAX_CHILDREN_ON_A_CALL} is refused`,
    startGroupCall('dad',['a','b','c','d','e'],T).reason, 'too_many');
  check('DS group','each gets four minutes alone', SOLO_SECONDS_EACH, 240);

  // The mechanic.
  const order=soloOrder([{id:'sam',age:13},{id:'olive',age:5},{id:'rae',age:9}]);
  check('DS group','the YOUNGEST goes first', order[0], 'olive');
  check('DS group','then the middle', order[1], 'rae');
  check('DS group','because by minute ten she has left the room',
    order[order.length-1], 'sam');
  check('DS group','an unknown age sorts last',
    soloOrder([{id:'x',age:null},{id:'y',age:8}])[0], 'y');

  let call=g.call;
  call=nextSolo(call,order);
  check('DS group','the first solo turn is hers', call.soloTurn, 'olive');
  call=nextSolo(call,order);
  check('DS group','then it rotates', call.soloTurn, 'rae');

  const w=waitingView('Olive');
  check('DS group','a waiting sibling is told to go and do something',
    /Go and do something/.test(w.line), 'true');
  check('DS group','and may leave', w.canLeave, 'true');
  check('DS group','no queue position reaches a child', auditGroup(w).ok, 'true');
  check('DS group','audit catches a countdown',
    auditGroup({...w,countdown:180}).leaks.join(','), 'countdown');
}

// DT · THE THERAPIST'S VIEW
{
  const v=therapistView('Olive',[
    {date:'2026-07-20',direction:'child_to_parent',otherParty:'Dad',landed:true},
    {date:'2026-07-22',direction:'parent_to_child',otherParty:'Dad',landed:false}]);
  check('DT therapist','entries are shown', v.entries.length, 2);
  check('DT therapist','the scope is stated on the surface',
    /Nothing else/.test(v.scopeNote), 'true');
  check('DT therapist','and what is NOT visible is named', v.notVisible.length, 5);
  check('DT therapist','including her journal',
    v.notVisible.some(x=>/journal/.test(x)), 'true');
  check('DT therapist','and her sealed letters',
    v.notVisible.some(x=>/sealed letters/.test(x)), 'true');
  check('DT therapist','the view carries no content', auditTherapist(v).ok, 'true');
  check('DT therapist','audit catches a duration leaking in',
    auditTherapist({...v,entries:[{...v.entries[0],duration:412}]}).leaks.join(','),
    'duration');
  check('DT therapist','and catches a transcript',
    auditTherapist({a:[{transcript:'...'}]}).ok, 'false');
  check('DT therapist','the forbidden list covers sentiment too',
    THERAPIST_FORBIDDEN.includes('sentiment'), 'true');
}

// DU · THE PRESERVATION PROMPT
{
  check('DU prompt','a call clip is promptable', shouldPrompt('call_clip',false), 'true');
  check('DU prompt','but never twice', shouldPrompt('call_clip',true), 'false');
  check('DU prompt','something already kept forever is NOT prompted',
    shouldPrompt('video_msg',false), 'false');
  check('DU prompt','because asking would train her to dismiss it',
    PROMPTABLE_KINDS.length, 3);
  check('DU prompt','the copy is short and warm', promptCopy('call_clip'),
    'Keep this bit of the call?');
  check('DU prompt','no is a real answer',
    answerPrompt({artifactId:'a',kind:'call_clip',asked:false,keep:null},false).keep,
    'false');
  check('DU prompt','and it is recorded as asked',
    answerPrompt({artifactId:'a',kind:'call_clip',asked:false,keep:null},false).asked,
    'true');
  check('DU prompt','the copy never threatens', auditPrompt(promptCopy('call_clip')).ok,
    'true');
  check('DU prompt','audit catches "gone forever"',
    auditPrompt('Keep this? It will be gone forever.').ok, 'false');
  check('DU prompt','and "are you sure"',
    auditPrompt('Are you sure you do not want it?').ok, 'false');
}

// DV · AT THE PING LIMIT
{
  const within=tapPing(true), atLimit=tapPing(false);
  check('DV limit','within the limit it pings', within.pinged, 'true');
  check('DV limit','at the limit it BANKS instead of nothing', atLimit.banked, 'true');
  check('DV limit','she cannot tell which she got', within.line, atLimit.line);
  check('DV limit','because a child who can tell has been told off by a counter',
    atLimit.line, SAME_LINE);
  check('DV limit','the line is warm and forward-looking',
    /thinking of him/.test(SAME_LINE), 'true');
  check('DV limit','the audit enforces the sameness', auditAtLimit(atLimit).ok, 'true');
  check('DV limit','and catches a divergent line',
    auditAtLimit({pinged:false,banked:true,line:'You have reached your limit.'}).ok,
    'false');

  check('DV limit','the GUARDIAN is told the truth, because he needs it',
    guardianPingView(3,2), 'She reached for you 2 more times after that.');
  check('DV limit','singular reads correctly',
    guardianPingView(3,1), 'She reached for you once more after that.');
  check('DV limit','and nothing is said when nothing was banked',
    guardianPingView(3,0), '');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
