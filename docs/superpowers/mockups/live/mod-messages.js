/* mod-messages.js  (agent MSG)  SIMULATION: no real server.
   The whole message and call loop for the LIVE prototype: guardian banking, the delivery worker on the virtual clock,
   the queue / delivery detail / failure / notification screens, call history and calls, and the child side
   (faces, arrival, player, reply, draw, who, knock, in-call, offline, rest time).

   ---- SCREEN IDS (L.go(dev, id, params)) -------------------------------------------------------------------
   Guardian ('g'):  msg.gQueue   Banked for Ivy (the Message banking hub)      msg.gBank    Bank a message
                    msg.gDetail  {id} Delivery detail                         msg.gFail    {id} Why it didn't arrive
                    msg.gNotif   Notifications settings                       msg.gPush    Push priming (before we ask)
                    msg.gCalls   Call history                                 msg.gCall    call screen (incoming, ringing, live, ended)
                    msg.gOffline Offline, safely ("N waiting to send")
   Child ('k'):     msg.kMessages faces + newest message                      msg.kPlay    {id} the player
                    msg.kReply   record a reply (record, then review)         msg.kSent / msg.kQueued   sent / saved, waiting for signal
                    msg.kDraw    draw and send                                msg.kWho     pick who to message or call
                    msg.kCall    knock / coming / will call back / incoming / in-call (one dynamic screen)
                    msg.kOffline cloud picture, what she can still do         msg.kBreak   rest-time screen with one-tap call

   ---- ACTIONS (L.run(dev, name, arg) / L.tap(dev, name, arg); data-arg may be a JSON object string) ---------
   Guardian banking     msg.bank {title,durSec,rule:'bedtime'|'night'|'wake',night:'YYYY-MM-DD',scene}  bank at once (scenarios)
                        msg.gStart (open the bank screen)  msg.gRec (record / stop)  msg.gSample (use a 1:41 sample take)
                        msg.gScene  msg.gRule  msg.gNight  msg.gZone  msg.gTrimA  msg.gTrimB  msg.gAgain  msg.gBankIt (the Bank button)
   Delivery             msg.deliverNow [id]   jump the virtual clock to the message's delivery time and run the worker
                        msg.worker  (run the worker now)  msg.retry id  msg.resched id (arg2 night)  msg.cancel id  msg.gOpen id  msg.gWhy id
                        msg.simPushFail 'on'|'off'   msg.simSamples (add sample history)   msg.kidSync (her tablet checks in)
   Child player         msg.kOpenNewest  msg.kOpenFrom who  msg.play id   msg.playTo 'end'|seconds   msg.pause  msg.leave
                        msg.cc (captions)  msg.again (play again)  msg.arrivalLater  msg.arrivalPlay
   Child reply / draw   msg.kReplyStart [who]  msg.kMode 'voice'|'video'  msg.kRec  msg.kRecAgain  msg.kPreview  msg.kPickWho who
                        msg.replySend [who]   msg.kDrawOpen  msg.kInk  msg.kUndo  msg.kDrawWho  msg.drawSend   msg.kDone
   Notifications        msg.gNotifToggle key  msg.gPrime (show priming)  msg.gPushAsk  msg.gPushAnswer 'allow'|'deny'  msg.gPrimeLater
                        msg.gQuiet  msg.gKeep id (preserve a reply)  msg.gPlayReply id
   Calls                call.knock who (child)  call.stop (child stops knocking)  call.answer (either side)  call.later (either side)
                        call.end  call.mute  call.start (guardian calls Ivy)  call.cancel  call.misuse (child tries the guardian route)
                        call.kWho 'call'|'msg'  call.avail 'both'|'eve'|'any'|'off'  call.done (leave the finished call screen)
   Also                 msg.gResend id  msg.gMove id  msg.gCheck  msg.seek  msg.kTry id  msg.kSetTo gid  msg.kWhoMsg gid  call.kMode  call.kDismiss
   Misc                 msg.back  msg.say text (read aloud)  msg.restPreview

   ---- PROGRAMMATIC: L.msg.m() (array of banked messages, newest last)  L.msg.state() (whole S.msg)  L.msg.bank(opts)  L.msg.nights()
        L.msg.freeNow(gid)  L.msg.worker()  L.msg.inbox()  L.msg.activeCall()  L.msg.kidSync() -----------------------------------------
   Time: the delivery worker runs every VIRTUAL minute (L.every), claims ready intents with a 2 min lease, sends a content-free push, marks
   delivered only when her tablet confirms (needs the child device online), retries at +10 min then hourly, gives up after 8 tries ("didn't
   arrive", with a reason). Recording and playback run on the virtual clock capped at 8x. Calls time out after 30 virtual seconds.

   ---- SERVER ROUTES (simulated, real error codes) ---------------------------------------------------------------
   POST /v1/children/:childId/messages                       guardian   422 message_too_short|invalid_rule|night_in_past
   GET  /v1/children/:childId/messages[/:messageId]          guardian
   POST /v1/children/:childId/messages/:messageId/retry      guardian   409 not_retryable
   POST /v1/children/:childId/messages/:messageId/reschedule guardian
   POST /v1/children/:childId/messages/:messageId/cancel     guardian
   GET  /v1/children/:childId/inbox                          child      (her tablet checks in: delivers what is waiting)
   POST /v1/children/:childId/inbox/:messageId/opened|progress|watched   child   409 not_played_through
   POST /v1/children/:childId/replies                        child      422 unknown_recipient|reply_too_short
   POST /v1/children/:childId/replies/:replyId/preserve      guardian
   POST /v1/children/:childId/calls                          guardian only, a child gets 403 child_cannot_start_call
   POST /v1/children/:childId/calls/knock                    child only (guardian gets 403 not_a_child_surface)
   POST /v1/children/:childId/calls/:callId/answer|later|stop|cancel|end|mute      409 call_in_progress|call_not_active
   GET  /v1/children/:childId/calls                          guardian
   PUT  /v1/guardians/me/notification-preferences           guardian
   POST /v1/guardians/me/push-registration                  guardian

   ---- EVENTS emitted: msg:banked msg:ready msg:delivered msg:opened msg:watched msg:failed msg:reply call:knock call:ring
        call:answered call:later call:ended ---------------------------------------------------------------------- */
(function(){
"use strict";
if(!window.LIVE||!window.OB){try{console.error("[mod-messages] LIVE or OB missing");}catch(e){}return;}
window.LIVE.module("messages",function(L){
var K=window.OB,I=K.ico,E=K.esc;

/* ================================================================= basics == */
function S(){return L.S;}
function T(){return S().clock.t;}
function cid(){return S().family.child.id;}
function cname(){return S().family.child.name||"Ivy";}
function homeTz(){return L.homeTz();}
function meTz(){var g=L.me("g");return (g&&g.tz)||S().family.homeTz;}
function myId(){return L.gid("g");}
function sched(){var sc=S().family.schedule||{};return {bed:sc.bedtime||"19:30",morn:sc.morning||"07:00"};}
function hmOf(s){var a=String(s).split(":");return [+a[0]||0,+a[1]||0];}
function pad(n){return n<10?"0"+n:""+n;}
function mss(ms){return L.fmt.mss(ms);}
function guardians(){var gs=S().family.guardians||[];return gs.filter(function(g){return g.id==="mom"||g.id==="dad";});}
function gName(id){var g=L.guardian(id);return (g&&g.name)||(id==="dad"?"Dad":"Mom");}
function kidWord(id){return L.labels.forChild(id);}       /* what Ivy calls them */
function grWord(id){return id==="dad"?"Dad":id==="mom"?"Mom":gName(id);} /* what a guardian screen calls them */
function online(dev){return L.online(dev);}
function topId(dev){var st=S().dev[dev].stack;return st.length?st[st.length-1].id:"";}
function topParams(dev){var st=S().dev[dev].stack;return st.length?(st[st.length-1].params||{}):{};}
function parseArg(a){if(a==null)return null;if(typeof a==="object")return a;var s=String(a);if(s.charAt(0)==="{"||s.charAt(0)==="["){try{return JSON.parse(s);}catch(e){}}return s;}
var MS={min:60000,hour:3600000,day:86400000};

/* ---------- time words ---------- */
function dayWord(t,tz,now){var a=L.parts(t,tz),b=L.parts(now,tz);var diff=Math.round((Date.UTC(a.y,a.m-1,a.d)-Date.UTC(b.y,b.m-1,b.d))/MS.day);
  if(diff===0)return a.h>=17?"Tonight":"Today";if(diff===1)return a.h>=17?"Tomorrow night":"Tomorrow";return L.fmt.day(t,tz)+" "+a.d;}
function dateShort(t,tz){var p=L.parts(t,tz);return L.fmt.day(t,tz)+" "+p.d;}
function bothTimes(t,zone){var h=homeTz(),m=meTz(),a=L.fmt.time(t,h),b=L.fmt.time(t,m);
  if(zone==="mine")return b+" your time"+(a!==b?" ("+a+" her time)":"");
  return a+" her time"+(a!==b?" ("+b+" yours)":"");}
function whenLong(t,zone){var base=zone==="mine"?meTz():homeTz();return dayWord(t,base,T())+", "+bothTimes(t,zone);}
function stampBoth(t){var h=homeTz(),m=meTz(),a=L.fmt.time(t,h),b=L.fmt.time(t,m);return dateShort(t,h)+", "+a+" her time"+(a!==b?" ("+b+" yours)":"");}

/* ================================================================== state == */
function init(){return {v:2,seq:1,rseq:1,cseq:1,intents:[],replies:[],calls:[],outbox:[],kidQ:[],pushLog:[],
  sim:{pushFail:false},
  notif:{late:true,handover:true,expense:true,dose:true,played:true,failed:true,reply:true,quiet:true,qFrom:"21:30",qTo:"06:30",knocks:true,showFrom:false,permission:"unknown",primed:false,dismissed:false},
  avail:{mom:"both",dad:"both"},
  draft:null,rec:null,
  kd:{stage:"idle",mode:"voice",ms:0,to:null,replyTo:null,pv:0,pvOn:false},
  draw:{strokes:[],ink:"pri",to:null},
  play:null,call:null,arrival:null,kidSeenT:0,wmode:"call",rest:false,lastW:0,gSheetReply:null};}
L.state("msg",init);
function M(){var s=S();if(!s.msg||s.msg.v!==2)s.msg=init();return s.msg;}
var CAP=8;               /* delivery attempts before "didn't arrive" */
var SCENES=["night","sea","hills","paper","garden","letters"];

/* ============================================================ intent logic == */
function logI(it,text,t){it.log.push({t:t==null?T():t,text:text});if(it.log.length>40)it.log.shift();}
function findI(id){var a=M().intents;for(var i=0;i<a.length;i++)if(a[i].id===id)return a[i];return null;}
function uiState(it){
  if(it.state==="watched")return "watched";if(it.state==="failed")return "failed";if(it.state==="cancelled")return "cancelled";
  if(it.state==="pending"||it.state==="ready")return "queued";if(it.state==="delivering")return "delivering";
  if(it.playedMs>0)return "started";if(it.openedT)return "opened";return "delivered";}
function onTablet(it){return it.state==="delivered"||it.state==="watched";}
function readyFor(rule,anchor){
  if(rule.type==="night"){var q=String(rule.night||"").split("-");if(q.length===3){var hb=hmOf(sched().bed);return L.zoned(+q[0],+q[1],+q[2],hb[0],hb[1],homeTz());}}
  if(rule.type==="wake")return L.nextAt("morning",anchor);
  return L.nextAt("bedtime",anchor);}
/* the next seven nights (her local dates) whose bedtime is still ahead */
function nights(){var out=[],h=homeTz(),p0=L.parts(T(),h),hb=hmOf(sched().bed);
  for(var i=0;i<9&&out.length<7;i++){var d=new Date(Date.UTC(p0.y,p0.m-1,p0.d+i)),y=d.getUTCFullYear(),m=d.getUTCMonth()+1,dd=d.getUTCDate();
    var t=L.zoned(y,m,dd,hb[0],hb[1],h);if(t>T())out.push({key:y+"-"+pad(m)+"-"+pad(dd),t:t});}
  return out;}
function ruleName(r){return r.type==="wake"?"When she wakes":r.type==="night"?"On a night chosen":"At her bedtime";}

function pushToKid(at){var m=M(),ok=!m.sim.pushFail;
  m.pushLog.push({to:"k",at:at,ok:ok,text:"Something new is waiting",why:ok?null:"push_rejected"});if(m.pushLog.length>60)m.pushLog.shift();return ok;}

function confirmDelivery(it,at,via){var m=M();it.state="delivered";it.deliveredT=at;it.lease=null;it.nextAt=0;it.failWhy=null;
  logI(it,via==="pull"?"She opened her tablet and it fetched the message":"Her tablet confirmed it holds the video",at);
  m.arrival={id:it.id,t:at,seen:false};
  L.emit("msg:delivered",{id:it.id,childId:it.childId,t:at,via:via||"push"});}

function failIntent(it,at,why){it.state="failed";it.failT=at;it.failWhy=why;it.lease=null;it.nextAt=0;
  logI(it,"Gave up for now after "+it.attempts+" tries. It is safe on our side.",at);
  notifyG("failed",at,it.by);L.emit("msg:failed",{id:it.id,why:why});}

function attempt(it,at){
  it.attempts++;it.lease={owner:"worker-1",until:at+2*MS.min};
  logI(it,"Try "+it.attempts+": claimed it, sent a quiet notification with no content",at);
  var pushOk=pushToKid(at),kidOn=online("k");
  if(it.rule.type==="wake"){it.state="delivering";it.lease=null;it.nextAt=0;it.gate="open";it.pushAcceptedT=at;
    logI(it,"Waiting for her to open her tablet after she wakes",at);return;}
  if(pushOk){it.pushAcceptedT=at;}
  if(pushOk&&kidOn){confirmDelivery(it,at,"push");return;}
  it.lease=null;it.failWhy=pushOk?"device_offline":"push_rejected";
  logI(it,pushOk?"The notification was accepted, but her tablet is off or has no signal":"The notification service did not accept it, so her tablet was not woken",at);
  if(it.attempts>=CAP){failIntent(it,at,it.failWhy);return;}
  it.state="delivering";it.nextAt=at+(it.attempts===1?10*MS.min:MS.hour);
  logI(it,"Will try again at "+L.fmt.time(it.nextAt,homeTz())+" her time",at);}

function worker(){
  var s=S();if(!s.family||!s.family.created)return;
  var m=M(),now=T();m.lastW=now;
  m.intents.forEach(function(it){
    if(it.state==="pending"){it.readyAt=readyFor(it.rule,it.anchorT);
      if(it.readyAt<=now){it.state="ready";it.nextAt=it.readyAt;logI(it,"Her time arrived. Preparing to send",it.readyAt);L.emit("msg:ready",{id:it.id});}}
    var g=0;while((it.state==="ready"||it.state==="delivering")&&it.nextAt&&it.nextAt<=now&&g++<12)attempt(it,it.nextAt);
  });
  callMaintenance(now);expirySweep(now);}

/* her tablet checks in (opens the app, comes back online): delivers whatever is waiting */
function pull(at,opened){var m=M(),n=0;
  m.intents.forEach(function(it){
    if(it.state!=="delivering"&&it.state!=="failed"&&it.state!=="ready")return;
    if(it.readyAt>at)return;
    if(it.failWhy==="push_rejected"&&!opened)return;
    if(it.gate==="open"&&!(opened&&m.kidSeenT>=it.readyAt))return;
    confirmDelivery(it,at,"pull");n++;});
  return n;}
function waitingForKid(){return M().intents.some(function(it){return it.state==="delivering"||it.state==="failed"||it.state==="ready";});}

/* ---- expiry: guardian-sent messages are preserved; her replies expire in 14 days unless a grown-up keeps them ---- */
function expirySweep(now){var m=M();m.replies.forEach(function(r){if(!r.preserved&&!r.expired&&r.expiresAt<=now){r.expired=true;}});}
function digest(){var m=M(),me=myId();return m.replies.filter(function(r){return !r.preserved&&!r.expired&&(r.to===me||me==="other");}).sort(function(a,b){return a.expiresAt-b.expiresAt;});}

/* ---- notifications to a guardian: content free, quiet hours respected ---- */
function inQuiet(at,tz,from,to){var p=L.parts(at,tz),mins=p.h*60+p.min,f=hmOf(from),t=hmOf(to),a=f[0]*60+f[1],b=t[0]*60+t[1];return a<=b?(mins>=a&&mins<b):(mins>=a||mins<b);}
var Q=[]; /* things to do right after a mutation (toasts, navigation) */
function flushQ(){var q=Q.splice(0,Q.length);q.forEach(function(f){try{f();}catch(e){L.logErr("msg queue",e);}});}
function notifyG(pref,at,target,isKnock){var m=M(),n=m.notif;
  if(pref&&n[pref]===false)return;
  var quiet=n.quiet&&inQuiet(at,meTz(),n.qFrom,n.qTo);
  var text=n.showFrom?cname()+": something new is waiting":"Something new is waiting. Open to see.";
  if(quiet&&!(isKnock&&n.knocks)){m.pushLog.push({to:"g",at:at,ok:false,text:text,why:"quiet_hours"});return;}
  var mine=!target||target===myId();
  m.pushLog.push({to:"g",at:at,ok:n.permission==="granted",text:text,why:n.permission==="granted"?null:"no_permission",kind:pref||"call"});
  if(m.pushLog.length>60)m.pushLog.shift();
  if(n.permission==="granted"&&mine&&S().dev.g.sessionOk)Q.push(function(){L.toast("g",text,{ic:"bell",ms:4200});});}

/* ================================================================== routes == */
function isG(req){return req.principal.kind==="guardian";}
function notMine(req){return req.params.childId!==cid();}
function view(it){return JSON.parse(JSON.stringify(it));}
function okMsg(m){return L.ok({message:view(m)});}

L.route("POST","/v1/children/:childId/messages",function(req){
  if(notMine(req))return L.fail(404,"not_found","No such child");
  var b=req.body||{},rule=b.rule||{type:"bedtime"},m=M();
  if(!(b.durMs>=3000))return L.fail(422,"message_too_short","A message needs at least 3 seconds");
  if(b.durMs>600000)return L.fail(422,"message_too_long","Messages can be up to 10 minutes");
  if(["bedtime","night","wake"].indexOf(rule.type)<0)return L.fail(422,"invalid_rule","Choose when she gets it");
  var title=String(b.title||"").trim().slice(0,80)||("Message from "+L.fmt.dayFull(T(),meTz()));
  var anchor=T();
  if(rule.type==="night"){var ok=nights().some(function(n){return n.key===rule.night;});if(!ok)return L.fail(422,"night_in_past","That night has already passed or is too far ahead");}
  var it={id:"msg_"+(m.seq++),childId:cid(),kind:"video",title:title,by:req.principal.id,durMs:Math.round(b.durMs),scene:b.scene||"night",rule:{type:rule.type,night:rule.night||null},
    zone:b.zone==="mine"?"mine":"her",anchorT:anchor,recordedT:b.recordedT||anchor,bankedT:anchor,readyAt:0,state:"pending",attempts:0,nextAt:0,lease:null,preserved:true,
    playedMs:0,openedT:0,startedT:0,watchedT:0,deliveredT:0,log:[]};
  it.readyAt=readyFor(it.rule,anchor);
  logI(it,"Recorded and uploaded to the server",it.recordedT);
  logI(it,"Banked: "+ruleName(it.rule)+", "+whenLong(it.readyAt,it.zone),anchor);
  m.intents.push(it);L.emit("msg:banked",{id:it.id,readyAt:it.readyAt,rule:it.rule});
  return L.ok({message:view(it)},201);},{principals:["guardian"]});
L.route("GET","/v1/children/:childId/messages",function(req){if(notMine(req))return L.fail(404,"not_found","No such child");return L.ok({messages:M().intents.map(view)});},{principals:["guardian"]});
L.route("GET","/v1/children/:childId/messages/:messageId",function(req){var it=findI(req.params.messageId);if(!it)return L.fail(404,"not_found","No such message");return okMsg(it);},{principals:["guardian"]});
L.route("POST","/v1/children/:childId/messages/:messageId/retry",function(req){var it=findI(req.params.messageId);if(!it)return L.fail(404,"not_found","No such message");
  if(it.state!=="failed"&&it.state!=="delivering")return L.fail(409,"not_retryable","Only a message that has not arrived can be tried again");
  it.attempts=0;it.state="ready";it.nextAt=T();it.failWhy=null;it.gate=null;logI(it,"You asked us to try again");worker();return okMsg(it);},{principals:["guardian"]});
L.route("POST","/v1/children/:childId/messages/:messageId/reschedule",function(req){var it=findI(req.params.messageId);if(!it)return L.fail(404,"not_found","No such message");
  if(it.state==="delivered"||it.state==="watched")return L.fail(409,"already_delivered","It is already on her tablet");
  var night=(req.body||{}).night;if(!nights().some(function(n){return n.key===night;}))return L.fail(422,"night_in_past","That night has already passed or is too far ahead");
  it.rule={type:"night",night:night};it.anchorT=T();it.attempts=0;it.state="pending";it.failWhy=null;it.gate=null;it.nextAt=0;it.readyAt=readyFor(it.rule,it.anchorT);
  logI(it,"Moved to "+whenLong(it.readyAt,it.zone));worker();return okMsg(it);},{principals:["guardian"]});
L.route("POST","/v1/children/:childId/messages/:messageId/cancel",function(req){var it=findI(req.params.messageId);if(!it)return L.fail(404,"not_found","No such message");
  if(it.state==="delivered"||it.state==="watched")return L.fail(409,"already_delivered","It is already on her tablet");
  it.state="cancelled";logI(it,"Taken out of the queue");return okMsg(it);},{principals:["guardian"]});

/* ---- her tablet ---- */
L.route("GET","/v1/children/:childId/inbox",function(req){var n=pull(T(),req.query&&req.query.open==="1");
  var items=M().intents.filter(onTablet).map(function(it){return {id:it.id,by:it.by,durMs:it.durMs,scene:it.scene,deliveredT:it.deliveredT,opened:!!it.openedT,watched:it.state==="watched"};});
  return L.ok({pulled:n,items:items});},{principals:["child"]});
function inboxItem(req){var it=findI(req.params.messageId);return it&&onTablet(it)?it:null;}
L.route("POST","/v1/children/:childId/inbox/:messageId/opened",function(req){var it=inboxItem(req);if(!it)return L.fail(404,"not_found","No such message");
  if(!it.openedT){it.openedT=T();logI(it,"She opened it");L.emit("msg:opened",{id:it.id,t:it.openedT});}return L.ok({openedAt:it.openedT});},{principals:["child"]});
L.route("POST","/v1/children/:childId/inbox/:messageId/progress",function(req){var it=inboxItem(req);if(!it)return L.fail(404,"not_found","No such message");
  var ms=Math.max(0,Math.min(it.durMs,+((req.body||{}).playedMs)||0));
  if(it.state!=="watched"&&ms>it.playedMs){if(!it.startedT){it.startedT=T();logI(it,"She started it");}it.playedMs=ms;}
  return L.ok({playedMs:it.playedMs});},{principals:["child"]});
L.route("POST","/v1/children/:childId/inbox/:messageId/watched",function(req){var it=inboxItem(req);if(!it)return L.fail(404,"not_found","No such message");
  var ms=+((req.body||{}).playedMs)||0;
  if(ms<it.durMs-1500)return L.fail(409,"not_played_through","Watched means played through to the end",{playedMs:ms,durMs:it.durMs});
  if(it.state!=="watched"){it.state="watched";it.watchedT=T();it.playedMs=it.durMs;if(!it.openedT)it.openedT=it.watchedT;logI(it,"She played it through to the end");
    notifyG("played",it.watchedT,it.by);L.emit("msg:watched",{id:it.id,childId:it.childId,t:it.watchedT});}
  return L.ok({watchedAt:it.watchedT});},{principals:["child"]});
L.route("POST","/v1/children/:childId/replies",function(req){var b=req.body||{},m=M();
  var ids=guardians().map(function(g){return g.id;});
  if(ids.indexOf(b.to)<0)return L.fail(422,"unknown_recipient","She can only message her own grown-ups");
  if(["voice","video","drawing"].indexOf(b.mode)<0)return L.fail(422,"invalid_mode","Voice, video or a drawing");
  if(b.mode!=="drawing"&&!(b.durMs>=800))return L.fail(422,"reply_too_short","That was too short to send");
  var r={id:"rep_"+(m.rseq++),to:b.to,mode:b.mode,durMs:Math.round(b.durMs||0),t:b.sentT||T(),receivedT:T(),replyTo:b.replyTo||null,strokes:b.mode==="drawing"?(b.strokes||[]):null,
    preserved:false,expiresAt:T()+14*MS.day,expired:false,playedByG:false};
  m.replies.push(r);notifyG("reply",T(),b.to);L.emit("msg:reply",{id:r.id,to:r.to,mode:r.mode});return L.ok({reply:r},201);},{principals:["child"]});
L.route("POST","/v1/children/:childId/replies/:replyId/preserve",function(req){var r=M().replies.filter(function(x){return x.id===req.params.replyId;})[0];
  if(!r)return L.fail(404,"not_found","No such reply");r.preserved=true;return L.ok({reply:r});},{principals:["guardian"]});
L.route("PUT","/v1/guardians/me/notification-preferences",function(req){var n=M().notif,b=req.body||{};
  Object.keys(b).forEach(function(k){if(k in n&&k!=="permission")n[k]=b[k];});return L.ok({preferences:n});},{principals:["guardian"]});
L.route("POST","/v1/guardians/me/push-registration",function(req){var n=M().notif,b=req.body||{};n.permission=b.granted?"granted":"denied";n.primed=true;return L.ok({permission:n.permission});},{principals:["guardian"]});

/* ----------------------------------------------------------------- calls -- */
var RING_MS=30000,NOCONNECT_MS=25000;
function activeCall(){var c=M().call;return c&&(c.state==="ringing"||c.state==="connecting"||c.state==="live")?c:null;}
function callById(id){var c=M().call;return c&&c.id===id?c:null;}
function endHistory(c,outcome){c.outcome=outcome;c.endT=T();
  if(c.state==="live"||c.liveT)c.durMs=Math.max(0,T()-c.liveT);
  var m=M();m.calls.unshift({id:c.id,dir:c.dir,who:c.who,outcome:outcome,startedT:c.startedT,durMs:c.durMs||0});if(m.calls.length>40)m.calls.pop();}
function setCallState(c,st,outcome){c.state=st;if(outcome)endHistory(c,outcome);}
function toLive(c){if(!c||c.state!=="connecting")return;c.state="live";c.liveT=T();c.mute={g:false,k:false};L.emit("call:answered",{id:c.id,dir:c.dir});}
function callMaintenance(now){var c=M().call;if(!c)return;
  if(c.state==="ringing"){
    if(c.dir==="in"&&now-c.startedT>=RING_MS){setCallState(c,"later","missed");L.emit("call:later",{id:c.id,by:"timeout"});}
    else if(c.dir==="out"&&now-c.startedT>=NOCONNECT_MS){setCallState(c,"ended","noconnect");L.emit("call:ended",{id:c.id,outcome:"noconnect"});kidLeaveCall();}}
  if(c.state==="connecting"&&now-c.connectT>=6000)toLive(c);}
function kidLeaveCall(){Q.push(function(){if(topId("k")==="msg.kCall")L.home("k");});}
function callPrincipalOk(req,c){return c.dir==="in"?(req.principal.kind==="guardian"&&req.principal.id===c.who):req.principal.kind==="child";}

L.route("POST","/v1/children/:childId/calls",function(req){
  if(req.principal.kind==="child")return L.fail(403,"child_cannot_start_call","A child can’t start a call. She can knock instead.",{use:"POST /v1/children/:childId/calls/knock"});
  if(req.principal.kind!=="guardian")return L.fail(403,"forbidden","Only a guardian can call");
  if(notMine(req))return L.fail(404,"not_found","No such child");
  if(activeCall())return L.fail(409,"call_in_progress","There is already a call going");
  var m=M(),c={id:"call_"+(m.cseq++),dir:"out",who:req.principal.id,state:"ringing",startedT:T(),liveT:0,connectT:0,mute:{g:false,k:false},recorded:false};
  m.call=c;L.emit("call:ring",{id:c.id,who:c.who});
  if(online("k")){Q.push(function(){if(!(topId("k")==="msg.kCall"))L.go("k","msg.kCall");});}
  L.after(NOCONNECT_MS,function(){callMaintenance(T());},"call-noconnect");
  return L.ok({call:c},201);});
L.route("POST","/v1/children/:childId/calls/knock",function(req){
  if(req.principal.kind!=="child")return L.fail(403,"not_a_child_surface","Only the child’s tablet can knock");
  var to=(req.body||{}).to;if(!guardians().some(function(g){return g.id===to;}))return L.fail(422,"unknown_recipient","She can only call her own grown-ups");
  if(activeCall())return L.fail(409,"call_in_progress","There is already a call going");
  var m=M(),c={id:"call_"+(m.cseq++),dir:"in",who:to,state:"ringing",startedT:T(),liveT:0,connectT:0,mute:{g:false,k:false},recorded:false};
  m.call=c;L.emit("call:knock",{id:c.id,to:to});notifyG("knocks",T(),to,true);
  if(myId()===to&&S().dev.g.sessionOk){Q.push(function(){if(topId("g")!=="msg.gCall")L.go("g","msg.gCall");});}
  L.after(RING_MS,function(){callMaintenance(T());},"call-ring");
  return L.ok({call:c},201);},{principals:["child"]});
function callRoute(verb,fn){L.route("POST","/v1/children/:childId/calls/:callId/"+verb,function(req){
  var c=callById(req.params.callId);if(!c)return L.fail(404,"not_found","No such call");return fn(req,c);});}
callRoute("answer",function(req,c){
  if(c.state!=="ringing")return L.fail(409,"call_not_active","That call is not ringing any more");
  if(!callPrincipalOk(req,c))return L.fail(403,"forbidden","That call is not for you");
  c.state="connecting";c.connectT=T();c.answeredBy=req.principal.kind;
  setTimeout(function(){if(callById(c.id)&&c.state==="connecting"){toLive(c);L.queueRender();}},1600);
  return L.ok({call:c});});
callRoute("later",function(req,c){
  if(c.state!=="ringing")return L.fail(409,"call_not_active","That call is not ringing any more");
  if(!callPrincipalOk(req,c))return L.fail(403,"forbidden","That call is not for you");
  setCallState(c,"later","later");L.emit("call:later",{id:c.id,by:req.principal.kind});
  if(c.dir==="out")kidLeaveCall();return L.ok({call:c});});
callRoute("stop",function(req,c){
  if(req.principal.kind!=="child"||c.dir!=="in")return L.fail(403,"forbidden","Only Ivy can stop her own knock");
  if(c.state!=="ringing"&&c.state!=="connecting")return L.fail(409,"call_not_active","That call is not ringing any more");
  setCallState(c,"ended","stopped");L.emit("call:ended",{id:c.id,outcome:"stopped"});return L.ok({call:c});});
callRoute("cancel",function(req,c){
  if(req.principal.kind!=="guardian"||c.dir!=="out")return L.fail(403,"forbidden","Only the caller can cancel");
  if(c.state!=="ringing")return L.fail(409,"call_not_active","That call is not ringing any more");
  setCallState(c,"ended","cancelled");L.emit("call:ended",{id:c.id,outcome:"cancelled"});kidLeaveCall();return L.ok({call:c});});
callRoute("end",function(req,c){
  if(c.state!=="live"&&c.state!=="connecting")return L.fail(409,"call_not_active","That call is not going");
  setCallState(c,"ended","answered");L.emit("call:ended",{id:c.id,outcome:"answered",durMs:c.durMs});kidLeaveCall();return L.ok({call:c});});
callRoute("mute",function(req,c){if(c.state!=="live")return L.fail(409,"call_not_active","That call is not going");
  var side=req.principal.kind==="child"?"k":"g";c.mute[side]=!!(req.body||{}).muted;return L.ok({call:c});});
L.route("GET","/v1/children/:childId/calls",function(req){return L.ok({calls:M().calls});},{principals:["guardian"]});

/* ============================================================ API wrapper == */
function api(dev,method,path,body){return L.api(dev,method,path,body);}
function base(){return "/v1/children/"+cid();}
function done(){L.queueRender();flushQ();}


/* ================================================================== styles == */
var css=[
".ob:has(.lm-g) .cbtn{width:48px;height:48px}",
".ob:has(.lm-g) .btn{min-height:48px}",
".ob.child:has(.lm-c) .cbtn{width:64px;height:64px}",
".ob .lm-b{background:none;border:0;font:inherit;color:inherit;text-align:left;width:100%;cursor:pointer;padding:0;display:flex;align-items:center;gap:12px;min-width:0}",
".ob .lm-b.row{padding:12px 0;min-height:56px}",
".ob .lm-face{display:inline-block;flex:none;position:relative;border-radius:50%;background:var(--surface)}",
".ob .lm-face svg{display:block;width:100%;height:100%;border-radius:50%}",
".ob .lm-face.glow{box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ok),0 0 26px 10px color-mix(in srgb,var(--ok) 38%,transparent)}",
".ob .lm-face.sel{box-shadow:0 0 0 3px var(--bg),0 0 0 7px var(--pri)}",
".ob .lm-face .lmdot{position:absolute;top:-3px;right:-3px;width:26px;height:26px;border-radius:50%;background:var(--accent);border:4px solid var(--surface)}",
".ob .lm-ft{display:grid;justify-items:center;align-content:start;gap:12px;padding:18px 8px 10px;border-radius:28px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);min-width:0;cursor:pointer;font:inherit;color:inherit}",
".ob .lm-ft.sel{border:2px solid var(--pri);background:var(--priC)}",
".ob .lm-nm{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:64px;width:100%;padding:0 8px;border-radius:20px;background:var(--priC);color:var(--onPriC);font:800 20px/1 var(--font-display);white-space:nowrap;overflow:hidden}",
".ob .lm-ft.sel .lm-nm{background:var(--pri);color:var(--onPri)}",
".ob .lm-say{display:flex;align-items:center;gap:12px;min-height:64px;width:100%;padding:0 18px;border-radius:22px;border:0;background:var(--priC);color:var(--onPriC);font:800 20px/1.1 var(--font-display);text-align:left;cursor:pointer}",
".ob .lm-say.plain{background:transparent;justify-content:center;text-align:center}",
".ob .speaking,.ob .lm-say.speaking{outline:3px solid var(--focus);outline-offset:2px}",
".ob .lm-poster{position:relative;border-radius:28px;overflow:hidden;aspect-ratio:16/10;box-shadow:var(--shadow2);background:var(--priC);min-width:0;border:0;padding:0;display:block;width:100%;font:inherit;color:inherit}",
".ob .lm-poster.fill{aspect-ratio:auto;flex:1;min-height:150px}",
".ob .lm-poster .scene{position:absolute;inset:0;width:100%;height:100%;border-radius:0}",
".ob .lm-pfc{position:absolute;left:12px;top:12px}",
".ob .lm-pfm{position:absolute;left:50%;top:46%;transform:translate(-50%,-50%)}",
".ob .lm-play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);display:grid;place-items:center;border-radius:50%;background:color-mix(in srgb,var(--surface) 94%,transparent);color:var(--pri);box-shadow:var(--shadow2)}",
".ob .lm-full{flex:1;min-height:0;display:flex;flex-direction:column;gap:12px;padding:4px 16px 18px;overflow:hidden auto}",
".ob .lm-full>*{min-width:0}",
".ob.f-tablet .lm-full.rw{flex-direction:row;align-items:stretch;gap:18px}",
".ob.f-tablet .lm-full.rw>*{flex:1 1 0;min-width:0}",
".ob .lm-col{display:flex;flex-direction:column;gap:12px;min-height:0;min-width:0;overflow-y:auto;scrollbar-width:none}",
".ob .lm-col.mid{justify-content:center}",
".ob .lm-rb{display:grid;place-items:center;border-radius:50%;border:0;flex:none;padding:0;cursor:pointer}",
".ob .lm-rb.pri{background:var(--pri);color:var(--onPri);box-shadow:var(--shadow2)}",
".ob .lm-rb.tonal{background:var(--priC);color:var(--onPriC)}",
".ob .lm-rb.ok{background:var(--ok);color:var(--bg);box-shadow:var(--shadow2)}",
".ob .lm-rb.bad{background:var(--bad);color:var(--bg);box-shadow:var(--shadow2)}",
".ob .lm-rb:disabled{opacity:.5;cursor:default}",
".ob .lm-row3{display:flex;align-items:center;justify-content:center;gap:16px;flex-wrap:wrap}",
".ob .lm-wave{display:flex;align-items:center;justify-content:center;gap:4px;height:70px;overflow:hidden}",
".ob .lm-wave i{width:6px;border-radius:4px;background:var(--pri);flex:none}",
".ob .lm-wave i.o{background:var(--priC2)}",
".ob .lm-seek{display:block;width:100%;padding:20px 0;background:none;border:0;cursor:pointer}",
".ob .lm-bar{display:block;height:16px;border-radius:9px;background:var(--surface3);overflow:hidden}",
".ob .lm-bar i{display:block;height:100%;border-radius:9px;background:var(--pri)}",
".ob .lm-box{border-radius:28px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);overflow:hidden;min-width:0}",
".ob .lm-bgc{background:var(--priC);color:var(--onPriC)}",
".ob .lm-kv{display:flex;gap:10px;align-items:center;justify-content:center;flex-wrap:wrap}",
".ob .lm-th{display:block;flex:none;border-radius:14px;overflow:hidden;position:relative}",
".ob .lm-th .scene{position:absolute;inset:0;width:100%;height:100%;border-radius:0}",
".ob button.lm-th{border:0;padding:0;cursor:pointer;background:var(--priC)}",
".ob .lm-q{display:flex;gap:12px;align-items:flex-start;padding:10px 0;min-width:0;width:100%;background:none;border:0;font:inherit;color:inherit;text-align:left;cursor:pointer;min-height:56px}",
".ob .card>.lm-q+.lm-q,.ob .card>.lm-q+.lm-qx,.ob .card>.lm-qx+.lm-q{border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}",
".ob .lm-q .rtxt{display:grid;gap:3px;min-width:0;flex:1}.ob .lm-q .rtxt b{font-size:14.5px}.ob .lm-q .rtxt small{color:var(--ink3);font-size:12.5px}.ob .lm-q .rtxt .chip{justify-self:start;margin-top:3px}",
".ob .lm-qx{padding:0 0 10px 64px}",
".ob .lm-rule{display:flex;gap:12px;align-items:center;padding:12px 14px;border-radius:18px;border:1.5px solid var(--outline);background:var(--surface);min-height:60px;min-width:0;width:100%;font:inherit;color:inherit;text-align:left;cursor:pointer}",
".ob .lm-rule.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC);box-shadow:inset 0 0 0 1px var(--pri)}",
".ob .lm-rule .rtxt{display:grid;gap:2px;min-width:0}.ob .lm-rule .rtxt small{color:inherit;opacity:.9;font-size:12.5px}.ob .lm-rule:not(.on) .rtxt small{color:var(--ink3);opacity:1}",
".ob .lm-rad{width:22px;height:22px;border-radius:50%;border:2px solid var(--ink3);flex:none;display:grid;place-items:center}",
".ob .lm-rule.on .lm-rad{border-color:var(--pri);background:var(--pri)}.ob .lm-rule.on .lm-rad::after{content:'';width:8px;height:8px;border-radius:50%;background:var(--onPri)}",
".ob .lm-trim{position:relative;height:56px;border-radius:14px;overflow:hidden;background:var(--surface3)}",
".ob .lm-trim .fs{display:flex;height:100%;gap:1px}.ob .lm-trim .fs i{flex:1;background:linear-gradient(var(--priC2),var(--priC))}",
".ob .lm-trim .sh{position:absolute;top:0;bottom:0;background:color-mix(in srgb,var(--surface) 78%,transparent)}",
".ob .lm-trim .hl{position:absolute;top:0;bottom:0;width:6px;background:var(--pri)}",
".ob input.lm-range{width:100%;min-height:48px;accent-color:var(--pri);margin:0}",
".ob .lm-lock{border-radius:20px;background:var(--surface2);padding:12px 14px;display:grid;gap:8px}",
".ob .lm-lock .nt{border-radius:16px;background:var(--surface);box-shadow:var(--shadow1);padding:10px 12px;display:flex;gap:10px;align-items:center}",
".ob .lm-lock .nt b{display:block;font-size:13px}.ob .lm-lock .nt small{color:var(--ink3);font-size:12.5px}",
".ob .lm-hero{background:linear-gradient(165deg,var(--pri),var(--priD));color:var(--onPri)}",
".ob .lm-canvas{position:relative;border-radius:26px;background:var(--surface);border:2px solid var(--outline);box-shadow:var(--shadow1);overflow:hidden;flex:1;min-height:170px;touch-action:none}",
".ob .lm-canvas canvas{position:absolute;inset:0;width:100%;height:100%;touch-action:none;cursor:crosshair}",
".ob .lm-ink{width:64px;height:64px;border-radius:50%;border:0;padding:0;flex:none;box-shadow:inset 0 0 0 3px rgba(255,255,255,.35);cursor:pointer}",
".ob .lm-ink.on{box-shadow:0 0 0 4px var(--bg),0 0 0 8px var(--ink)}",
".ob .lm-inks{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:6px;justify-items:center}",
".ob .lm-inks .lm-ink{width:100%;max-width:64px;height:auto;aspect-ratio:1}",
".ob .lm-undo{position:absolute;top:10px;right:10px}",
".ob .lm-mode{display:flex;gap:10px}.ob .lm-mode>button{flex:1;min-height:64px;border-radius:22px;background:var(--surface2);color:var(--ink2);display:flex;align-items:center;justify-content:center;gap:8px;font:800 17px var(--font-display);border:0;cursor:pointer}",
".ob .lm-mode>button.on{background:var(--pri);color:var(--onPri)}",
".ob .lm-slip{position:absolute;left:12px;right:12px;top:60px;z-index:7;border-radius:26px;background:var(--surface);box-shadow:var(--shadow3);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);padding:10px 12px;display:flex;align-items:center;gap:12px}",
".ob .lm-slip b{font:800 19px/1.15 var(--font-display);flex:1;min-width:0}",
".ob .lm-slip.sm{gap:8px;padding:8px}.ob .lm-slip.sm b{font-size:15px}",
".ob .lm-sys{border:1.5px dashed var(--outline);border-radius:18px;padding:10px 14px;color:var(--ink3);font-size:12.5px;display:flex;gap:10px;align-items:center}",
".ob .lm-rings{position:relative;display:grid;place-items:center;margin:0 auto}",
".ob .lm-rings i{position:absolute;border-radius:50%;border:3px solid var(--priC2)}",
".ob .lm-rings .face{position:relative}",
".ob .lm-big{font:800 28px/1.05 var(--font-display);letter-spacing:-.02em}",
".ob .lm-seg{display:flex;gap:6px;background:var(--surface2);border-radius:16px;padding:4px}",
".ob .lm-seg button{flex:1;min-height:44px;border:0;border-radius:12px;background:transparent;color:var(--ink2);font:700 13.5px var(--font-body);cursor:pointer;padding:0 8px}",
".ob .lm-seg button.on{background:var(--surface);color:var(--ink);box-shadow:var(--shadow1)}",
".ob .lm-sim{border:1.5px dashed var(--edge);border-radius:18px;padding:12px;display:grid;gap:8px;background:transparent}",
".ob .lm-sim h4{margin:0;font:700 11px var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:var(--ink3)}",
".ob .lm-hint{margin:0;color:var(--ink3);font-size:12.5px;line-height:1.4}",
".ob .lm-chips{display:flex;gap:8px;flex-wrap:wrap}",
".ob .lm-spacer{flex:1;min-height:0}",
".ob .lm-timer{font:800 34px/1 var(--font-mono);letter-spacing:-.02em;text-align:center}",
".ob .lm-rec-dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--bad);margin-right:6px}",
".ob .lm-draw-thumb{display:block;border-radius:12px;background:var(--surface);border:1px solid var(--outline)}"
].join("\n");
(function(){var st=document.getElementById("lm-css");if(!st){st=document.createElement("style");st.id="lm-css";document.head.appendChild(st);}st.textContent=css;})();

/* ================================================================== parts == */
var FACES={
 mom:{bg:"var(--accentC)",skin:"#e6b48f",hair:"#5a3a2a",shape:"long",cloth:"var(--pri)"},
 dad:{bg:"var(--priC2)",skin:"#c68e66",hair:"#2f2420",shape:"short",cloth:"var(--accent)"},
 other:{bg:"var(--priC)",skin:"#8d5a3b",hair:"#1d1613",shape:"curly",cloth:"var(--info)"},
 kid:{bg:"var(--accentC)",skin:"#e0a981",hair:"#7a4a2a",shape:"pig",cloth:"var(--ok)"}};
function face(who,sz,o){o=o||{};var f=FACES[who]||FACES.other,back="",front="";
 if(f.shape==="long")back='<path d="M15 36c-3-17 5-26 17-26s20 9 17 26c0 7 2 12 2 12H13s2-5 2-12z" fill="'+f.hair+'"/>';
 if(f.shape==="curly")back='<g fill="'+f.hair+'"><circle cx="19" cy="22" r="8"/><circle cx="45" cy="22" r="8"/><circle cx="26" cy="15" r="9"/><circle cx="38" cy="15" r="9"/></g>';
 if(f.shape==="pig")back='<g fill="'+f.hair+'"><circle cx="16" cy="30" r="6.5"/><circle cx="48" cy="30" r="6.5"/></g>';
 front='<path d="M19.5 29c-1-11 5-16 12.5-16s13.5 5 12.5 16c-3-5-8-8-12.5-8s-9.5 3-12.5 8z" fill="'+f.hair+'"/>';
 var svg='<svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="32" fill="'+f.bg+'"/>'+back+'<path d="M7 64c2-14 12-19 25-19s23 5 25 19z" fill="'+f.cloth+'"/><rect x="27.5" y="36" width="9" height="11" rx="3" fill="'+f.skin+'"/><ellipse cx="32" cy="30" rx="12" ry="13" fill="'+f.skin+'"/>'+front+'<circle cx="27" cy="31.5" r="1.7" fill="#2b2220"/><circle cx="37" cy="31.5" r="1.7" fill="#2b2220"/><path d="M28 37.5q4 3 8 0" fill="none" stroke="#2b2220" stroke-width="1.6" stroke-linecap="round"/></svg>';
 return '<span class="lm-face'+(o.glow?" glow":"")+(o.sel?" sel":"")+'" role="img" aria-label="'+E(o.label||who)+'" style="width:'+sz+'px;height:'+sz+'px">'+svg+(o.dot?'<i class="lmdot" role="img" aria-label="Something new"></i>':"")+'</span>';}
function ctop(title,o){o=o||{};return '<i class="lm-c" hidden></i>'+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":L.iconBtn("volume","msg.say",title||"Hello",{kind:"tonal",label:"Hear it"})});}
function gtop(title,o){o=o||{};return '<i class="lm-g" hidden></i>'+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function ftile(gid,o){o=o||{};var nm=kidWord(gid);
  return '<button type="button" class="lm-ft'+(o.sel?" sel":"")+'"'+(o.compact?' style="padding:12px 6px 8px;gap:8px"':"")+L.a(o.act||"msg.kPickWho",gid)+' aria-label="'+E(nm)+'">'+face(gid,o.size||88,{glow:o.glow,dot:o.dot,sel:o.sel,label:nm})+'<span class="lm-nm"'+(o.compact?' style="min-height:56px"':"")+'>'+I("volume",22,2)+'<b>'+E(nm)+'</b></span></button>';}
function say(t,o){o=o||{};return '<button type="button" class="lm-say'+(o.plain?" plain":"")+'"'+L.a("msg.say",t)+' aria-label="Hear: '+E(t)+'">'+I("volume",26,2)+'<span>'+E(t)+'</span></button>';}
function rb(ic,sz,kind,label,act,arg,o){o=o||{};return '<button type="button" class="lm-rb '+kind+'" style="width:'+sz+'px;height:'+sz+'px" aria-label="'+E(label)+'"'+(act?L.a(act,arg,o.arg2):"")+(o.disabled?" disabled":"")+'>'+(o.html||I(ic,Math.round(sz*.42),2))+'</button>';}
function poster(scene,who,o){o=o||{};var tag=o.act?"button":"div";return '<'+tag+(o.act?' type="button"'+L.a(o.act,o.arg):"")+' class="lm-poster'+(o.fill?" fill":"")+'"'+(o.act?' aria-label="'+E(o.label||"Play")+'"':"")+'>'+K.scene(scene,300,160)+(who?'<span class="lm-pfc">'+face(who,o.fs||48,{label:kidWord(who)})+'</span>':"")+(o.inner||"")+'</'+tag+'>';}
function playBtn(sz){return '<span class="lm-play" style="width:'+sz+'px;height:'+sz+'px">'+I("play",Math.round(sz*.46),2)+'</span>';}
function thumb(scene,sz){return '<span class="lm-th" style="width:'+sz+'px;height:'+sz+'px">'+K.scene(scene,sz,sz)+'</span>';}
function ringsOf(who,sz,glow){var f=Math.round(sz*.57);return '<div class="lm-rings" style="width:'+sz+'px;height:'+sz+'px"><i style="inset:0;opacity:.35"></i><i style="inset:'+Math.round(sz*.1)+'px;opacity:.6"></i><span class="face">'+face(who,f,{glow:glow,label:who==="kid"?cname():kidWord(who)})+'</span></div>';}
function full(c,l,r,o){o=o||{};if(c.form==="tablet"&&r!==undefined)return '<div class="lm-full rw"><div class="lm-col'+(o.m1?" mid":"")+'">'+l+'</div><div class="lm-col'+(o.m2===false?"":" mid")+'">'+r+'</div></div>';return '<div class="lm-full">'+l+(r||"")+'</div>';}
function rowb(o){ /* a real <button> list row */
  return '<button type="button" class="row lm-b'+(o.tone?" "+o.tone:"")+'"'+(o.act?L.a(o.act,o.arg,o.arg2):"")+'>'+(o.ic?'<span class="ricon">'+I(o.ic,20,1.9)+'</span>':"")+'<span class="rtxt"><b>'+E(o.title)+'</b>'+(o.sub?'<small>'+E(o.sub)+'</small>':"")+'</span>'+(o.trail||"")+(o.go?'<span class="go">'+I("chevR",16,2)+'</span>':"")+'</button>';}
function togglerow(o){return '<button type="button" class="row lm-b" role="switch" aria-checked="'+(!!o.on)+'"'+L.a(o.act,o.arg)+'>'+(o.ic?'<span class="ricon">'+I(o.ic,20,1.9)+'</span>':"")+'<span class="rtxt"><b>'+E(o.title)+'</b>'+(o.sub?'<small>'+E(o.sub)+'</small>':"")+'</span><span class="tgl'+(o.on?" on":"")+'" aria-hidden="true"><i></i></span></button>';}
function segb(items,active,act,args,label){return '<div class="lm-seg" role="radiogroup"'+(label?' aria-label="'+E(label)+'"':"")+'>'+items.map(function(x,i){return '<button type="button" role="radio" aria-checked="'+(i===active)+'" class="'+(i===active?"on":"")+'"'+L.a(act,args?args[i]:i)+'>'+E(x)+'</button>';}).join("")+'</div>';}
function pill(st){var m={queued:["Queued","clock",""],delivering:["Delivering","refresh","info"],delivered:["Delivered","check","pri"],opened:["Opened","check2","pri"],started:["Started, not finished","play","warn"],watched:["Watched","eye","ok"],failed:["Didn’t arrive","warn","bad"],cancelled:["Taken out","x",""]}[st]||["","",""];return K.chip(m[0],{tone:m[2],ic:m[1],sm:true});}
function waveBars(ms,n){n=n||28;var s="";for(var i=0;i<n;i++){var h=10+Math.abs(Math.sin(ms/230+i*.7))*(.5+.5*Math.sin(ms/611+i*1.3))*46;s+='<i style="height:'+Math.round(h)+'px"></i>';}return s;}
var BARS=[18,30,44,26,52,36,60,40,22,48,64,34,20,42,56,30,16,38,50,24,12];
function wavePlayed(frac){return '<div class="lm-wave" data-lm="kPv">'+BARS.map(function(h,i){return '<i class="'+(i/BARS.length>frac?"o":"")+'" style="height:'+h+'px"></i>';}).join("")+'</div>';}
function speak(txt,el){try{if(window.speechSynthesis&&window.SpeechSynthesisUtterance){window.speechSynthesis.cancel();var u=new window.SpeechSynthesisUtterance(String(txt));u.rate=.92;window.speechSynthesis.speak(u);}}catch(e){}
  if(el&&el.classList){el.classList.add("speaking");setTimeout(function(){try{el.classList.remove("speaking");}catch(e){}},1000);}}
function freeNow(gid){var m=M(),p=m.avail[gid]||"both";if(p==="off")return false;if(p==="any")return true;var g=L.guardian(gid),tz=(g&&g.tz)||S().family.homeTz,q=L.parts(T(),tz),x=q.h*60+q.min;
  var morning=x>=390&&x<510,evening=x>=1020&&x<1260;return p==="eve"?evening:(morning||evening);}
function unreadFrom(gid){return M().intents.some(function(it){return it.by===gid&&it.state==="delivered"&&!it.openedT;});}
function unreadAny(){return M().intents.some(function(it){return it.state==="delivered"&&!it.openedT;});}
function inbox(){return M().intents.filter(onTablet).sort(function(a,b){return b.deliveredT-a.deliveredT;});}
function failedCount(){return M().intents.filter(function(it){return it.state==="failed";}).length;}
function ago(t){var d=T()-t;return d<MS.min?"just now":d<MS.hour?Math.round(d/MS.min)+" min ago":d<MS.day?Math.round(d/MS.hour)+" h ago":Math.round(d/MS.day)+" d ago";}


/* ============================================ device-side behaviour (client) == */
var KMAX=60000,GMAX=300000;
function A(name,fn){L.act(name,fn);}
function tg(dev,text,o){L.toast(dev,text,o);}

/* ---- queues that wait for signal ---- */
var flG=false,flK=false,kSyncing=false;
function flushOutbox(){var m=M();if(flG||!m.outbox.length)return;flG=true;
  (function next(){var o=M().outbox[0];if(!o){flG=false;done();return;}
    api("g","POST",base()+"/messages",o.body).then(function(r){
      if(r.status===0){flG=false;return;}
      M().outbox.shift();if(r.ok)Q.push(function(){tg("g","Sent: "+(o.body.title||"your message"),{ic:"check"});});else Q.push(function(){tg("g","One message could not be sent: "+(r.code||"error"),{ic:"warn",tone:"bad"});});
      done();next();});})();}
function kidReport(kind,id,ms){var m=M();
  if(kind==="progress"){m.kidQ=m.kidQ.filter(function(q){return !(q.kind==="progress"&&q.id===id);});}
  api("k","POST",base()+"/inbox/"+id+"/"+kind,{playedMs:Math.round(ms||0)}).then(function(r){
    if(r.status===0||r.status===429||r.status>=500){var q=M().kidQ;if(!q.some(function(x){return x.kind===kind&&x.id===id;}))q.push({kind:kind,id:id,ms:Math.round(ms||0)});}
    done();});}
function flushKidQ(){var m=M();if(flK||!m.kidQ.length)return;flK=true;
  (function next(){var q=M().kidQ[0];if(!q){flK=false;done();return;}
    var req=q.kind==="reply"?api("k","POST",base()+"/replies",q.body):api("k","POST",base()+"/inbox/"+q.id+"/"+q.kind,{playedMs:q.ms});
    req.then(function(r){if(r.status===0||r.status===429||r.status>=500){flK=false;return;}M().kidQ.shift();done();next();});})();}
function kidSync(open){if(kSyncing)return;kSyncing=true;
  api("k","GET",base()+"/inbox"+(open?"?open=1":"")).then(function(r){kSyncing=false;done();});}
var lastHK=0;
function housekeeping(){var m=M(),s=S();
  if(m.outbox.length&&online("g")&&s.dev.g.sessionOk)flushOutbox();
  if(online("k")&&s.dev.k.sessionOk){
    if(m.kidQ.length)flushKidQ();
    if(m.intents.some(function(it){return (it.state==="delivering"||it.state==="failed")&&it.failWhy==="device_offline";}))kidSync(false);}}

/* ---- the media clock: recording and playback advance with virtual time (capped at 8x so it stays watchable) ---- */
var lastReal=Date.now();
setInterval(function(){
  try{
    var s=S();if(!s||!s.clock||!s.family)return;
    var now=Date.now(),dr=Math.min(now-lastReal,1000);lastReal=now;
    var m=M(),rate=s.clock.paused?0:Math.min(s.clock.speed||1,8),d=dr*rate,trans=false;
    if(m.rec&&m.rec.on){m.rec.ms+=d;if(m.rec.ms>=GMAX){stopGRec();trans=true;}}
    if(m.kd.stage==="rec"){m.kd.ms+=d;if(m.kd.ms>=KMAX){stopKRec();trans=true;}}
    if(m.kd.pvOn){m.kd.pv+=d;if(m.kd.pv>=m.kd.ms){m.kd.pvOn=false;m.kd.pv=0;trans=true;}}
    if(m.play&&m.play.playing){
      if(topId("k")!=="msg.kPlay"){pausePlay(true);trans=true;}
      else{var it=findI(m.play.id);if(!it){m.play.playing=false;}else{m.play.pos+=d;
        if(m.play.pos-m.play.rep>=5000){m.play.rep=m.play.pos;kidReport("progress",it.id,m.play.pos);}
        if(m.play.pos>=it.durMs){endPlay(it);trans=true;}}}}
    if(now-lastHK>1000){lastHK=now;housekeeping();}
    paintLive();
    if(trans){L.queueRender();flushQ();}
  }catch(e){L.logErr("msg media clock",e);}
},250);
function paintLive(){
  var m=M(),els=document.querySelectorAll("[data-lm]"),i,e,k,v;
  for(i=0;i<els.length;i++){e=els[i];k=e.getAttribute("data-lm");
    if(k==="gRecT"){v=mss(m.rec?m.rec.ms:0);if(e.textContent!==v)e.textContent=v;}
    else if(k==="gWave"){e.innerHTML=waveBars(m.rec?m.rec.ms:0,32);}
    else if(k==="kBar"&&m.play){var it=findI(m.play.id);if(it){var p=Math.min(100,m.play.pos/it.durMs*100).toFixed(1)+"%";if(e.style.width!==p)e.style.width=p;}}
    else if(k==="kCap"&&m.play){e.textContent=captionAt(m.play.pos);}
    else if(k==="kRing"){var f=Math.min(1,m.kd.ms/KMAX);e.setAttribute("stroke-dashoffset",String(Math.round(396*(1-f))));}
    else if(k==="kWaveRec"){e.innerHTML=waveBars(m.kd.ms,22);}
    else if(k==="kPv"){var fr=m.kd.ms?m.kd.pv/m.kd.ms:0;var bs=e.children;for(var j=0;j<bs.length;j++){var on=j/bs.length<=fr&&m.kd.pvOn;bs[j].className=on||!m.kd.pvOn?"":"o";}}
    else if(k==="callT"){var c=M().call;v=c&&c.state==="live"?mss(T()-c.liveT):"0:00";if(e.textContent!==v)e.textContent=v;}}}
var CAPS=["Goodnight, my love.","I was thinking of you today.","Sleep well. I love you.","See you very soon."];
function captionAt(pos){return CAPS[Math.floor(pos/6000)%CAPS.length];}

/* ---- guardian recording ---- */
function stopGRec(){var m=M();if(!m.rec)return;var ms=m.rec.ms;m.rec=null;
  if(ms<3000){Q.push(function(){tg("g","That was very short. Hold on a little longer.",{ic:"info"});});return;}
  m.draft=newDraft(Math.round(ms));}
function newDraft(ms){var m=M();return {take:{ms:ms,recordedT:T()},scene:m.recScene||"night",a:0,b:100,name:"",rule:"bedtime",night:null,zone:"her",busy:false,err:null};}
function draftLen(d){return Math.round(d.take.ms*(d.b-d.a)/100);}

/* ---- the player ---- */
function openMsg(id,from){var m=M(),it=findI(id);if(!it||!onTablet(it))return;
  m.play={id:id,pos:0,playing:true,cc:false,ended:false,rep:0};
  if(m.arrival&&m.arrival.id===id)m.arrival.seen=true;
  if(!it.openedT)kidReport("opened",id,0);
  if(topId("k")==="msg.kPlay")L.replace("k","msg.kPlay",{id:id});else L.go("k","msg.kPlay",{id:id});}
function pausePlay(leave){var m=M();if(!m.play)return;m.play.playing=false;var it=findI(m.play.id);
  if(it&&!m.play.ended&&m.play.pos>0)kidReport("progress",it.id,m.play.pos);}
function endPlay(it){var m=M();m.play.pos=it.durMs;m.play.playing=false;m.play.ended=true;kidReport("watched",it.id,it.durMs);}

/* ---- child canvas ---- */
var drawing=null;
function inkColor(cv,tok){var v="";try{v=getComputedStyle(cv).getPropertyValue("--"+tok).trim();}catch(e){}return v||"#4a6b4f";}
function paintCanvas(){var cvs=document.querySelectorAll('canvas[data-lm="draw"]');
  for(var i=0;i<cvs.length;i++){var cv=cvs[i],r=cv.getBoundingClientRect(),dpr=window.devicePixelRatio||1,w=Math.max(1,Math.round(r.width*dpr)),h=Math.max(1,Math.round(r.height*dpr));
    if(cv.width!==w||cv.height!==h){cv.width=w;cv.height=h;}
    var g=cv.getContext("2d");g.clearRect(0,0,w,h);g.lineCap="round";g.lineJoin="round";g.lineWidth=Math.max(6,w/38);
    M().draw.strokes.forEach(function(st){g.strokeStyle=inkColor(cv,st.c);g.fillStyle=g.strokeStyle;
      if(st.pts.length===1){g.beginPath();g.arc(st.pts[0][0]*w,st.pts[0][1]*h,g.lineWidth/2,0,6.3);g.fill();return;}
      g.beginPath();st.pts.forEach(function(p,j){if(j)g.lineTo(p[0]*w,p[1]*h);else g.moveTo(p[0]*w,p[1]*h);});g.stroke();});}}
document.addEventListener("pointerdown",function(ev){var t=ev.target;if(!t||!t.closest)return;
  var cv=t.closest('canvas[data-lm="draw"]');
  if(cv){ev.preventDefault();var r=cv.getBoundingClientRect(),st={c:M().draw.ink,pts:[[(ev.clientX-r.left)/r.width,(ev.clientY-r.top)/r.height]]};
    M().draw.strokes.push(st);drawing={cv:cv,st:st};try{cv.setPointerCapture(ev.pointerId);}catch(e){}paintCanvas();}
  if(t.closest('[data-dev="k"]')){var m=M();m.kidSeenT=T();if(waitingForKid()&&online("k"))kidSync(true);}},true);
document.addEventListener("pointermove",function(ev){if(!drawing)return;var r=drawing.cv.getBoundingClientRect();
  drawing.st.pts.push([Math.max(0,Math.min(1,(ev.clientX-r.left)/r.width)),Math.max(0,Math.min(1,(ev.clientY-r.top)/r.height))]);paintCanvas();});
function endDraw(){if(drawing){drawing=null;L.save();}}
document.addEventListener("pointerup",endDraw);document.addEventListener("pointercancel",endDraw);

/* ---- the soft arrival slip on her tablet (an overlay, never a takeover) ---- */
function slipOverlay(){
  var host=document.querySelector('[data-host="k"] .ob');if(!host)return;
  var m=M(),a=m.arrival,tp=topId("k"),it=a&&findI(a.id);
  var want=!!(a&&!a.seen&&it&&!it.openedT&&T()-a.t<2*MS.min&&S().dev.k.role==="kid"&&["msg.kPlay","msg.kCall","msg.kReply","msg.kDraw","msg.kSent","msg.kQueued","msg.kBreak","msg.kWho"].indexOf(tp)<0&&tp.indexOf("ob.")!==0&&!S().ui.k.sheet);
  var ex=host.querySelector(".lm-slip");
  if(!want){if(ex)ex.parentNode.removeChild(ex);return;}
  if(ex&&ex.getAttribute("data-id")===a.id)return;
  if(ex)ex.parentNode.removeChild(ex);
  var d=document.createElement("div");var sm=host.clientWidth<460;d.className="lm-slip"+(sm?" sm":"");d.setAttribute("data-id",a.id);d.setAttribute("role","status");
  d.innerHTML=face(it.by,sm?52:64,{dot:true,label:kidWord(it.by)})+"<b>"+E(kidWord(it.by))+" left you something</b>"+rb("play",64,"pri","Play","msg.arrivalPlay",a.id)+rb("x",64,"tonal","Later","msg.arrivalLater",a.id);
  host.appendChild(d);}
L.afterRender.push(function(){paintCanvas();slipOverlay();paintLive();});

/* ===================================================== guardian-side actions == */
A("msg.back",function(c){L.back(c.dev);});
A("msg.say",function(c,arg,el){speak(arg,el);});
A("msg.gStart",function(c){var m=M();m.rec=null;L.go("g","msg.gBank");});
A("msg.gRec",function(c){var m=M();
  if(m.rec&&m.rec.on){stopGRec();flushQ();}
  else{m.rec={on:true,ms:0};m.draft=null;}});
A("msg.gSample",function(c){var m=M();m.rec=null;m.draft=newDraft(101000);});
A("msg.gAgain",function(c){var m=M();m.rec=null;m.draft=null;});
A("msg.gScene",function(c,arg){var m=M();m.recScene=arg;if(m.draft)m.draft.scene=arg;});
A("msg.gRule",function(c,arg){var d=M().draft;if(!d)return;d.rule=arg;if(arg==="night"&&!d.night){var n=nights();d.night=n.length?n[Math.min(1,n.length-1)].key:null;}});
A("msg.gNight",function(c,arg){var d=M().draft;if(d){d.night=arg;d.rule="night";}});
A("msg.gZone",function(c,arg){var d=M().draft;if(d)d.zone=arg;});
A("msg.gTrimA",function(c,arg){var d=M().draft;if(!d)return;var v=Math.max(0,Math.min(100,+arg||0));d.a=Math.min(v,d.b-Math.ceil(3000/d.take.ms*100));d.a=Math.max(0,d.a);});
A("msg.gTrimB",function(c,arg){var d=M().draft;if(!d)return;var v=Math.max(0,Math.min(100,+arg||0));d.b=Math.max(v,d.a+Math.ceil(3000/d.take.ms*100));d.b=Math.min(100,d.b);});
function bankNow(o){
  var body={title:o.title,durMs:o.durMs,rule:{type:o.rule||"bedtime",night:o.night||null},scene:o.scene||"night",zone:o.zone||"her",recordedT:o.recordedT||T()};
  return api("g","POST",base()+"/messages",body).then(function(r){
    if(r.status===0){M().outbox.push({lid:"out_"+Date.now(),body:body,t:T()});Q.push(function(){tg("g","Saved on this phone. It sends when you are back online.",{ic:"wifioff"});});}
    else if(r.ok){Q.push(function(){tg("g","Banked "+(r.body.message?whenShort(r.body.message):""),{ic:"check"});});}
    else{Q.push(function(){tg("g",friendly(r),{ic:"warn",tone:"bad"});});}
    done();return r;});}
function whenShort(it){return dayWord(it.readyAt,homeTz(),T()).toLowerCase()+" at "+L.fmt.time(it.readyAt,homeTz());}
function friendly(r){var c=r.code;return c==="message_too_short"?"That message is very short. Record a little more.":c==="night_in_past"?"That night has passed. Pick another.":c==="rate_limited"?"Slow down a moment, then try again.":c==="unauthenticated"||c==="session_expired"?"Please sign in again.":"That did not work ("+(c||r.status)+"). Nothing was lost.";}
A("msg.gBankIt",function(c){var m=M(),d=m.draft;if(!d||d.busy)return;d.busy=true;
  var title=(d.name||"").trim()||("Message from "+L.fmt.dayFull(d.take.recordedT,meTz()));
  bankNow({title:title,durMs:draftLen(d),rule:d.rule,night:d.night,scene:d.scene,zone:d.zone,recordedT:d.take.recordedT}).then(function(r){
    var m2=M();if(m2.draft)m2.draft.busy=false;
    if(r.ok||r.status===0){m2.draft=null;m2.rec=null;L.replace("g","msg.gQueue");}
    done();});});
A("msg.bank",function(c,arg){var o=parseArg(arg)||{};if(typeof o==="string")o={title:o};
  return bankNow({title:o.title||"Goodnight, Ivy",durMs:(o.durSec||101)*1000,rule:o.rule||"bedtime",night:o.night,scene:o.scene||"night",zone:o.zone});});
A("msg.gOpen",function(c,arg){var it=findI(arg);if(!it)return;L.go("g",it.state==="failed"?"msg.gFail":"msg.gDetail",{id:arg});});
A("msg.gWhy",function(c,arg){L.go("g","msg.gFail",{id:arg});});
A("msg.retry",function(c,arg){var id=arg||(M().intents.filter(function(i){return i.state==="failed";})[0]||{}).id;if(!id)return;
  api("g","POST",base()+"/messages/"+id+"/retry").then(function(r){Q.push(function(){tg("g",r.ok?"Trying again now":friendly(r),{ic:r.ok?"refresh":"warn"});});done();});});
A("msg.gMove",function(c,arg){var id=arg;
  L.sheet("g",function(){var ns=nights();return '<div style="display:grid;gap:12px;padding:4px 4px 10px"><b style="font:800 18px var(--font-display)">Move to another night</b><p class="lm-hint">She gets it at her bedtime that night.</p><div class="lm-chips">'+ns.map(function(n){return '<button type="button" class="btn tonal"'+L.a("msg.resched",id,n.key)+'>'+E(dateShort(n.t,homeTz()))+'</button>';}).join("")+'</div></div>';});});
A("msg.resched",function(c,arg){var key=c.arg2;
  api("g","POST",base()+"/messages/"+arg+"/reschedule",{night:key}).then(function(r){L.closeSheet("g");Q.push(function(){tg("g",r.ok?"Moved":friendly(r),{ic:r.ok?"check":"warn"});});done();});});
A("msg.cancel",function(c,arg){api("g","POST",base()+"/messages/"+arg+"/cancel").then(function(r){Q.push(function(){tg("g",r.ok?"Taken out of the queue":friendly(r));});done();});});
A("msg.worker",function(){worker();});
A("msg.deliverNow",function(c,arg){var m=M(),it=arg?findI(arg):m.intents.filter(function(i){return i.state==="pending"||i.state==="ready"||(i.state==="delivering"&&i.nextAt);}).sort(function(a,b){return (a.readyAt||0)-(b.readyAt||0);})[0];
  if(!it){return;}
  if(it.state==="pending"||it.state==="ready"){var at=it.readyAt||T();if(at>T())L.jumpTo(at+1000);}
  worker();});
A("msg.simPushFail",function(c,arg){var m=M();m.sim.pushFail=arg==="on"?true:arg==="off"?false:!m.sim.pushFail;});
A("msg.kidSync",function(){kidSync(true);});
A("msg.simSamples",function(){var m=M(),now=T(),h=homeTz();
  function mk(title,by,scene,dtDays,state,extra){var it={id:"msg_"+(m.seq++),childId:cid(),kind:"video",title:title,by:by,durMs:101000,scene:scene,rule:{type:"bedtime",night:null},zone:"her",anchorT:now+dtDays*MS.day-3*MS.hour,recordedT:now+dtDays*MS.day-20*MS.hour,bankedT:now+dtDays*MS.day-20*MS.hour,readyAt:L.zoned(L.parts(now+dtDays*MS.day,h).y,L.parts(now+dtDays*MS.day,h).m,L.parts(now+dtDays*MS.day,h).d,19,30,h),state:state,attempts:1,nextAt:0,lease:null,preserved:true,playedMs:0,openedT:0,startedT:0,watchedT:0,deliveredT:0,log:[]};
    for(var k in extra)it[k]=extra[k];logI(it,"Recorded and uploaded",it.recordedT);logI(it,"Banked for bedtime",it.bankedT);m.intents.push(it);return it;}
  var by=myId()==="dad"?"dad":"mom";
  var a=mk("Goodnight from the lake",by,"sea",-3,"watched");a.deliveredT=a.readyAt;a.openedT=a.readyAt+240000;a.startedT=a.openedT;a.watchedT=a.readyAt+360000;a.playedMs=a.durMs;logI(a,"Her tablet confirmed it holds the video",a.deliveredT);logI(a,"She played it through to the end",a.watchedT);
  var b=mk("Tell the owl hello",by,"paper",-4,"delivered");b.deliveredT=b.readyAt;logI(b,"Her tablet confirmed it holds the video",b.deliveredT);
  var f=mk("Silly faces",by,"letters",-5,"failed",{failWhy:"device_offline",attempts:CAP,failT:now-5*MS.day});logI(f,"Gave up for now after 8 tries. It is safe on our side.",f.failT);
  var p=mk("Counting sheep song",by,"hills",1,"pending");p.anchorT=now;p.readyAt=readyFor(p.rule,now);});

/* ---- notifications ---- */
A("msg.gNotifToggle",function(c,arg){var n=M().notif;n[arg]=!n[arg];});
A("msg.gQuiet",function(c,arg){var n=M().notif;if(arg==="late"){n.qFrom="22:30";n.qTo="07:00";}else if(arg==="early"){n.qFrom="20:30";n.qTo="06:00";}else{n.qFrom="21:30";n.qTo="06:30";}});
A("msg.gPrime",function(c){L.go("g","msg.gPush");});
A("msg.gPrimeLater",function(c){var n=M().notif;n.dismissed=true;n.primed=true;if(topId("g")==="msg.gPush")L.back("g");});
A("msg.gPushAsk",function(c){
  L.sheet("g",function(){return '<div style="display:grid;gap:12px;padding:6px 4px 10px"><b style="font:800 18px var(--font-display)">Allow Olive Branch to send you notifications?</b><p class="lm-hint">This is your phone’s own question (simulated).</p><div class="lm-sys">'+I("device",18,2)+'<span>Notifications from Olive Branch will say only that something is waiting.</span></div>'+L.btn("Allow","msg.gPushAnswer","allow",{full:true})+L.btn("Don’t allow","msg.gPushAnswer","deny",{full:true,kind:"ghost"})+'</div>';});});
A("msg.gPushAnswer",function(c,arg){L.closeSheet("g");
  api("g","POST","/v1/guardians/me/push-registration",{granted:arg==="allow"}).then(function(r){
    if(r.status===0){M().notif.permission=arg==="allow"?"granted":"denied";M().notif.primed=true;}
    Q.push(function(){tg("g",arg==="allow"?"Notifications are on":"No problem. The app checks while it is open.",{ic:"bell"});if(topId("g")==="msg.gPush")L.back("g");});done();});});
A("msg.gKeep",function(c,arg){api("g","POST",base()+"/replies/"+arg+"/preserve").then(function(r){Q.push(function(){tg("g",r.ok?"Kept":friendly(r),{ic:"check"});});done();});});
A("msg.gPlayReply",function(c,arg){var r=M().replies.filter(function(x){return x.id===arg;})[0];if(!r)return;r.playedByG=true;
  L.sheet("g",function(){var rr=M().replies.filter(function(x){return x.id===arg;})[0];if(!rr)return "";
    var pic=rr.mode==="drawing"?drawingSvg(rr.strokes,240,150):'<div class="lm-box" style="padding:14px;display:grid;justify-items:center;gap:6px">'+face("kid",64,{label:cname()})+wavePlayed(.4)+'</div>';
    return '<div style="display:grid;gap:12px;padding:4px 4px 10px"><b style="font:800 18px var(--font-display)">'+E(cname())+(rr.mode==="drawing"?" drew you a picture":rr.mode==="video"?" sent you a video":" sent you a voice note")+'</b>'+pic+'<p class="lm-hint">'+(rr.mode==="drawing"?"":"Playing "+mss(rr.durMs)+" (simulated). ")+(rr.preserved?"Kept for good.":"It goes away after 14 days unless you keep it.")+'</p>'+(rr.preserved?"":L.btn("Keep this","msg.gKeep",rr.id,{full:true,ic:"check"}))+'</div>';});});
function drawingSvg(strokes,w,h){strokes=strokes||[];var paths=strokes.map(function(s){var cols={pri:"var(--pri)",accent:"var(--accent)",info:"var(--info)",dpMorning:"var(--dpMorning)"};
  var d=s.pts.map(function(p,i){return (i?"L":"M")+(p[0]*100).toFixed(1)+" "+(p[1]*100).toFixed(1);}).join("");if(s.pts.length===1)d+="l.1 .1";
  return '<path d="'+d+'" fill="none" stroke="'+(cols[s.c]||"var(--pri)")+'" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>';}).join("");
  return '<svg class="lm-draw-thumb" viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet" width="'+w+'" height="'+h+'" role="img" aria-label="A drawing from '+E(cname())+'">'+paths+'</svg>';}

/* ======================================================== child-side actions == */
function dflTo(){var gs=guardians();var last=M().kd.to;if(last&&gs.some(function(g){return g.id===last;}))return last;return gs.length?gs[0].id:null;}
A("msg.kOpenNewest",function(c){var l=inbox();if(l.length)openMsg(l[0].id);});
A("msg.kOpenFrom",function(c,arg){var l=inbox().filter(function(i){return i.by===arg;});if(l.length)openMsg(l[0].id);else{M().kd.to=arg;startReply(arg);}});
A("msg.play",function(c,arg){openMsg(arg||(inbox()[0]||{}).id);});
A("msg.arrivalPlay",function(c,arg){openMsg(arg);});
A("msg.arrivalLater",function(c){var a=M().arrival;if(a)a.seen=true;});
A("msg.pause",function(c){var p=M().play;if(!p)return;if(p.ended){p.pos=0;p.ended=false;p.rep=0;p.playing=true;return;}if(p.playing)pausePlay();else p.playing=true;});
A("msg.again",function(c){var p=M().play;if(!p)return;p.pos=0;p.rep=0;p.ended=false;p.playing=true;});
A("msg.cc",function(c){var p=M().play;if(p)p.cc=!p.cc;});
A("msg.seek",function(c,arg,el,ev){var p=M().play;if(!p||!el)return;var it=findI(p.id);if(!it)return;var r=el.getBoundingClientRect(),f=ev&&ev.clientX!=null&&r.width?(ev.clientX-r.left)/r.width:.5;
  f=Math.max(0,Math.min(.97,f));p.pos=it.durMs*f;p.rep=p.pos;p.ended=false;if(!p.playing)p.playing=true;});
A("msg.playTo",function(c,arg){var p=M().play;if(!p)return;var it=findI(p.id);if(!it)return;var a=String(arg);
  var pos=a==="end"?it.durMs-1500:/%$/.test(a)?it.durMs*parseFloat(a)/100:(parseFloat(a)||0)*1000;p.pos=Math.max(0,Math.min(it.durMs-1500,pos));p.rep=p.pos;p.ended=false;p.playing=true;kidReport("progress",it.id,p.pos);});
A("msg.leave",function(c){pausePlay();L.back("k");});

function startReply(to,replyTo){var m=M();m.kd={stage:"idle",mode:m.kd.mode||"voice",ms:0,to:to||dflTo(),replyTo:replyTo||null,pv:0,pvOn:false};L.go("k","msg.kReply");}
A("msg.kReplyStart",function(c,arg){var pl=M().play,pit=pl&&findI(pl.id),to=arg||(pit?pit.by:null);startReply(to,pit&&pit.by===to?pit.id:null);});
A("msg.kMode",function(c,arg){var k=M().kd;if(k.stage==="rec")return;k.mode=arg==="video"?"video":"voice";});
function stopKRec(){var k=M().kd;if(k.ms<800){k.stage="idle";k.ms=0;return;}k.stage="review";k.pv=0;k.pvOn=false;}
A("msg.kRec",function(c){var k=M().kd;if(k.stage==="rec"){stopKRec();}else if(k.stage==="idle"){k.stage="rec";k.ms=0;k.pvOn=false;}});
A("msg.kRecAgain",function(c){var k=M().kd;k.stage="idle";k.ms=0;k.pv=0;k.pvOn=false;});
A("msg.kPreview",function(c){var k=M().kd;if(k.pvOn){k.pvOn=false;k.pv=0;}else{k.pv=0;k.pvOn=true;}});
A("msg.kSetTo",function(c,arg){var m=M();m.kd.to=arg;m.draw.to=arg;});
A("msg.kWhoMsg",function(c,arg){startReply(arg);});
function sendReply(body){
  return api("k","POST",base()+"/replies",body).then(function(r){
    if(!r.ok){M().kidQ.push({kind:"reply",body:body});L.replace("k","msg.kQueued");}
    else L.replace("k","msg.kSent");
    done();return r;});}
A("msg.replySend",function(c,arg){var m=M(),k=m.kd,o=parseArg(arg);var to=(typeof o==="string"?o:o&&o.to)||k.to||dflTo();
  var dur=(o&&o.durSec)?o.durSec*1000:k.ms;if(k.stage!=="review"&&!(o&&o.durSec))return;
  var body={to:to,mode:(o&&o.mode)||k.mode,durMs:dur,replyTo:k.replyTo,sentT:T()};k.to=to;
  m.kd={stage:"idle",mode:k.mode,ms:0,to:to,replyTo:null,pv:0,pvOn:false};
  sendReply(body);});
A("msg.kDrawOpen",function(c){var m=M();m.draw.to=m.draw.to||dflTo();L.go("k","msg.kDraw");});
A("msg.kInk",function(c,arg){M().draw.ink=arg;});
A("msg.kUndo",function(c){M().draw.strokes.pop();});
A("msg.kDrawWho",function(c,arg){M().draw.to=arg;M().kd.to=arg;});
A("msg.drawSend",function(c,arg){var m=M(),d=m.draw;if(!d.strokes.length)return;var to=(arg&&typeof arg==="string"&&arg!=="")?arg:(d.to||dflTo());
  var body={to:to,mode:"drawing",durMs:0,strokes:d.strokes.slice(0,60),sentT:T()};d.strokes=[];d.to=to;sendReply(body);});
A("msg.kDone",function(c){L.home("k");});
A("msg.restPreview",function(c){L.go("k","msg.kBreak");});

/* ----------------------------------------------------------------- calls -- */
A("call.kWho",function(c,arg){M().wmode=arg==="msg"?"msg":"call";L.go("k","msg.kWho");});
A("call.kMode",function(c,arg){M().wmode=arg==="msg"?"msg":"call";});
A("call.knock",function(c,arg){var to=arg||dflTo();
  api("k","POST",base()+"/calls/knock",{to:to}).then(function(r){
    if(r.status===0){L.go("k","msg.kOffline");}
    else if(r.ok||r.code==="call_in_progress"){if(topId("k")!=="msg.kCall")L.go("k","msg.kCall");}
    else{L.go("k","msg.kOffline");}
    done();});});
A("call.stop",function(c){var cl=M().call;if(!cl)return;
  api("k","POST",base()+"/calls/"+cl.id+"/stop").then(function(r){kidLeaveCall();done();});});
A("call.answer",function(c){var cl=M().call;if(!cl)return;
  api(c.dev,"POST",base()+"/calls/"+cl.id+"/answer").then(function(r){if(!r.ok&&r.status!==0)Q.push(function(){tg(c.dev,c.dev==="k"?"Hmm":friendly(r));});done();});});
A("call.later",function(c){var cl=M().call;if(!cl)return;
  api(c.dev,"POST",base()+"/calls/"+cl.id+"/later").then(function(r){if(c.dev==="k"&&r.ok)Q.push(function(){L.home("k");});done();});});
A("call.end",function(c){var cl=M().call;if(!cl)return;
  api(c.dev,"POST",base()+"/calls/"+cl.id+"/end").then(function(r){done();});});
A("call.mute",function(c){var cl=M().call;if(!cl)return;var side=c.dev;
  api(c.dev,"POST",base()+"/calls/"+cl.id+"/mute",{muted:!(cl.mute&&cl.mute[side])}).then(function(){done();});});
A("call.start",function(c){
  if(!online("g")){tg("g","Calls need a connection. Everything else is saved on this phone.",{ic:"wifioff"});return;}
  api("g","POST",base()+"/calls",{}).then(function(r){
    if(r.ok||r.code==="call_in_progress")L.go("g","msg.gCall");else Q.push(function(){tg("g",friendly(r),{ic:"warn",tone:"bad"});});done();});});
A("call.cancel",function(c){var cl=M().call;if(!cl)return;api("g","POST",base()+"/calls/"+cl.id+"/cancel").then(function(){done();});});
A("call.misuse",function(c){
  api("k","POST",base()+"/calls",{}).then(function(r){var msg=(r.status?r.status+" ":"")+(r.code||"ok");
    Q.push(function(){tg("g","Server said: "+msg,{ic:r.ok?"check":"shield",ms:5200});});M().lastMisuse={status:r.status,code:r.code,t:T()};done();});});
A("call.done",function(c){if(c.dev==="k")L.home("k");else L.back("g");});
A("call.avail",function(c,arg){var id=myId();if(id)M().avail[id]=arg;});
A("call.kDismiss",function(c){var cl=M().call;if(cl)cl.kDone=true;L.home("k");});

/* ---- programmatic access for scenarios/console ---- */
L.msg={m:function(){return M().intents;},state:M,nights:nights,freeNow:freeNow,worker:worker,uiState:uiState,bank:function(o){return bankNow(o||{title:"Goodnight, Ivy",durMs:101000,rule:"bedtime"});},
  find:findI,inbox:inbox,activeCall:activeCall,whenLong:whenLong,openMsg:openMsg,kidSync:function(){kidSync(true);}};

/* ---- the delivery worker runs on the VIRTUAL clock, every virtual minute (idempotent, so jumps are safe) ---- */
L.every(MS.min,function(){worker();},"msg-worker");
L.on("time:bedtime",function(){worker();});L.on("time:morning",function(){worker();});L.on("time:jump",function(){worker();flushQ();});
L.on("time:tick",function(){if(Q.length)flushQ();});


/* ================================================================ GUARDIAN SCREENS == */
var AP="’";
function kname(){return cname();}
function offlineCard(){var n=M().outbox.length;return K.card(rowb({ic:"wifioff",title:"You are offline",sub:(n?n+" waiting to send. ":"")+"Everything is saved on this phone.",tone:"warn",act:"go",arg:"msg.gOffline",go:true}),"flat");}
function qsub(it){
  var h=homeTz(),st=uiState(it);
  if(st==="queued")return ruleName(it.rule)+": "+whenLong(it.readyAt,it.zone);
  if(st==="delivering")return it.gate==="open"?"Waiting for "+kname()+" to open her tablet":it.nextAt?"Trying again at "+L.fmt.time(it.nextAt,h)+" her time":"Delivering now";
  if(st==="delivered")return "On "+kname()+AP+"s tablet, not opened yet";
  if(st==="opened")return "She opened it at "+L.fmt.time(it.openedT,h)+" her time";
  if(st==="started")return "She started it, "+mss(it.playedMs)+" of "+mss(it.durMs);
  if(st==="watched")return "She played it through at "+L.fmt.time(it.watchedT,h)+" her time";
  if(st==="failed")return it.failWhy==="push_rejected"?"Her tablet could not be woken":"Her tablet was off or had no signal";
  return "Taken out of the queue";}
function qrow(it){return '<button type="button" class="lm-q"'+L.a("msg.gOpen",it.id)+'>'+thumb(it.scene,52)+'<span class="rtxt"><b>'+E(it.title)+'</b><small>'+E(qsub(it))+'</small>'+pill(uiState(it))+'</span></button>';}
function replyRows(list){return list.map(function(r){var lab=r.mode==="drawing"?"drew you a picture":r.mode==="video"?"sent you a video":"sent you a voice note";
  return '<div class="row"><span class="ricon">'+I(r.mode==="drawing"?"brush":r.mode==="video"?"video":"mic",20,1.9)+'</span><span class="rtxt"><b>'+E(kname())+" "+lab+'</b><small>'+E(stampBoth(r.t))+(r.mode==="drawing"?"":". "+mss(r.durMs))+'</small></span>'+L.btn("Open","msg.gPlayReply",r.id,{size:"sm",kind:"tonal"})+'</div>';}).join("");}

L.screen("msg.gQueue",{dev:"g",title:"Banked messages",render:function(c){
  var m=M(),kid=kname(),b="";
  if(!online("g"))b+=offlineCard();
  b+=K.banner("pri",E(kid)+" never sees this list, a count, or a gap. A message simply arrives at its time.","eyeoff");
  b+=L.btn("Bank a message","msg.gStart",null,{full:true,ic:"plus"});
  if(m.notif.permission==="unknown"&&!m.notif.dismissed)
    b+=K.card('<h4>Know the moment she watches</h4><p>We can nudge your phone when '+E(kid)+' plays your message. A notification never says what it was.</p><div class="lm-chips" style="margin-top:8px">'+L.btn("Turn on","msg.gPrime",null,{size:"sm",ic:"bell"})+L.btn("Not now","msg.gPrimeLater",null,{size:"sm",kind:"ghost"})+'</div>',"tint");
  if(m.outbox.length)b+=K.sectionLabel("Waiting to send")+K.card(m.outbox.map(function(o){return rowb({ic:"mic",title:o.body.title,sub:"Recorded "+L.fmt.time(o.t,meTz())+". Uploads when you are back",tone:"warn",act:"go",arg:"msg.gOffline",trail:K.chip("Waiting",{sm:true,tone:"warn",ic:"clock"})});}).join(""));
  var all=m.intents.filter(function(i){return i.state!=="cancelled";});
  var failed=all.filter(function(i){return i.state==="failed";}).sort(function(a,b2){return b2.failT-a.failT;});
  var upcoming=all.filter(function(i){return i.state==="pending"||i.state==="ready"||i.state==="delivering";}).sort(function(a,b2){return a.readyAt-b2.readyAt;});
  var earlier=all.filter(function(i){return onTablet(i);}).sort(function(a,b2){return b2.deliveredT-a.deliveredT;});
  if(failed.length)b+=K.sectionLabel("Needs you")+K.card(failed.map(function(it){return qrow(it)+'<div class="lm-qx">'+L.btn("Try again","msg.retry",it.id,{size:"sm",kind:"tonal",ic:"refresh"})+'</div>';}).join(""));
  if(upcoming.length)b+=K.sectionLabel(dayWord(upcoming[0].readyAt,homeTz(),T())==="Tonight"?"Tonight and coming up":"Coming up")+K.card(upcoming.map(qrow).join(""));
  if(earlier.length)b+=K.sectionLabel("Earlier")+K.card(earlier.slice(0,8).map(qrow).join(""));
  if(!all.length&&!m.outbox.length)b+=K.emptyState({spot:"envelope",title:"Nothing banked yet",sub:"Record a message, choose when "+kid+" gets it, and it arrives by itself."});
  var rep=m.replies.filter(function(r){return !r.expired&&(r.to===myId()||myId()==="other");}).sort(function(a,b2){return b2.t-a.t;});
  if(rep.length)b+=K.sectionLabel("From "+kid)+K.card(replyRows(rep.slice(0,4)));
  var dg=digest();
  if(dg.length)b+=K.card('<h4>Going away soon</h4><p>'+E(kid)+AP+'s replies are kept for 14 days. Messages you send are always kept. Keep any of these to save them.</p>'+dg.map(function(r){var d=Math.max(1,Math.ceil((r.expiresAt-T())/MS.day));
    return '<div class="row"><span class="ricon">'+I("hourglass",20,1.9)+'</span><span class="rtxt"><b>'+(r.mode==="drawing"?"A drawing":r.mode==="video"?"A video":"A voice note")+'</b><small>Goes away in '+d+' day'+(d===1?"":"s")+'</small></span>'+L.btn("Keep","msg.gKeep",r.id,{size:"sm",kind:"tonal"})+'</div>';}).join(""),"flat");
  b+='<div class="lm-sim"><h4>Simulation controls</h4>'+togglerow({ic:"bell",title:"Her tablet turns away our notification",sub:"Shows how a failed push becomes “didn’t arrive” with a reason",on:m.sim.pushFail,act:"msg.simPushFail",arg:"toggle"})+
    '<div class="lm-chips">'+L.btn("Deliver the next one now","msg.deliverNow",null,{size:"sm",kind:"tonal",ic:"clock"})+L.btn("Add sample history","msg.simSamples",null,{size:"sm",kind:"ghost"})+'</div><p class="lm-hint">Not part of the real app. The delivery worker runs every virtual minute.</p></div>';
  return gtop("Banked for "+kid,{eyebrow:"Message banking"})+K.page(b);}});

/* ---- Bank a message ---- */
function ruleBtn(t,sub,on,arg){return '<button type="button" class="lm-rule'+(on?" on":"")+'" role="radio" aria-checked="'+on+'"'+L.a("msg.gRule",arg)+'><span class="lm-rad"></span><span class="rtxt"><b>'+E(t)+'</b><small>'+E(sub)+'</small></span></button>';}
L.screen("msg.gBank",{dev:"g",title:"Bank a message",render:function(c){
  var m=M(),kid=kname(),d=m.draft,b="",scenes=SCENES.map(function(s){return K.filterChip(s.charAt(0).toUpperCase()+s.slice(1),{on:((d?d.scene:m.recScene)||"night")===s}).replace("<button",'<button'+L.a("msg.gScene",s));}).join("");
  var me=myId()||"mom";
  if(!d){
    var rec=m.rec&&m.rec.on;
    b+=K.card('<div class="lm-poster" style="box-shadow:none">'+K.scene((m.recScene||"night"),300,160)+'<span class="lm-pfc">'+face(me,44,{label:grWord(me)})+'</span>'+(rec?'<span class="chip sm" style="position:absolute;right:10px;top:12px;background:rgba(0,0,0,.55);color:#fff"><span class="lm-rec-dot"></span>Recording</span>':"")+'</div>'+
      '<div class="lm-timer" style="margin-top:12px" data-lm="gRecT" aria-live="off">'+mss(m.rec?m.rec.ms:0)+'</div><div class="lm-wave" data-lm="gWave" aria-hidden="true">'+(rec?waveBars(m.rec.ms,32):BARS.map(function(h){return '<i class="o" style="height:'+Math.round(h/2)+'px"></i>';}).join(""))+'</div>'+
      '<div class="lm-row3">'+rb("","88",rec?"bad":"bad",rec?"Stop recording":"Start recording","msg.gRec",null,{html:rec?'<span style="width:30px;height:30px;border-radius:8px;background:var(--bg);display:block"></span>':'<span style="width:30px;height:30px;border-radius:50%;background:var(--bg);display:block"></span>'})+'</div>'+
      '<p class="lm-hint" style="text-align:center">'+(rec?"Tap again when you are done.":"Tap to start. Say it the way you would at the end of her bed.")+'</p>');
    b+=K.sectionLabel("Backdrop")+'<div class="lm-chips">'+scenes+'</div>';
    b+=L.btn("Use a sample take (1:41)","msg.gSample",null,{full:true,kind:"ghost",ic:"play"});
    return gtop("Bank a message",{eyebrow:"Step 1 of 2"})+K.page(b);}
  var len=draftLen(d),keepsTxt="Trimmed: keeps "+mss(len)+" of "+mss(d.take.ms);
  var shL=d.a,shR=100-d.b;
  b+=K.card('<div class="lm-poster" style="box-shadow:none">'+K.scene(d.scene,300,160)+'<span class="lm-pfc">'+face(me,44,{label:grWord(me)})+'</span>'+playBtn(60)+'<span class="chip sm" style="position:absolute;right:10px;bottom:10px;background:rgba(0,0,0,.55);color:#fff">'+mss(len)+'</span></div>'+
    '<div style="margin-top:12px"><div class="lm-trim"><div class="fs">'+new Array(15).join("<i></i>")+'</div><span class="sh" style="left:0;width:'+shL+'%"></span><span class="sh" style="right:0;width:'+shR+'%"></span><span class="hl" style="left:'+d.a+'%"></span><span class="hl" style="right:'+shR+'%"></span></div>'+
    '<label class="lm-hint" style="display:block;margin-top:8px">Start<input class="lm-range" type="range" min="0" max="100" step="1" value="'+d.a+'" aria-label="Trim the start"'+L.a("msg.gTrimA")+'></label>'+
    '<label class="lm-hint" style="display:block">End<input class="lm-range" type="range" min="0" max="100" step="1" value="'+d.b+'" aria-label="Trim the end"'+L.a("msg.gTrimB")+'></label>'+
    '<div class="row" style="padding:4px 0 0"><span class="rtxt"><small>'+E(keepsTxt)+'</small></span>'+L.btn("Record again","msg.gAgain",null,{kind:"ghost",size:"sm",ic:"refresh"})+'</div></div>');
  b+=L.field({label:"Name it (only you see this)",path:"msg.draft.name",ph:"The moon story",ic:"edit",maxlength:60,autocomplete:false});
  var nx=nights(),first=nx.length?nx[0]:null;
  var bedAt=readyFor({type:"bedtime"},T()),wakeAt=readyFor({type:"wake"},T());
  b+=K.sectionLabel("When does "+kid+" get it?");
  b+=segb(["Her time","My time"],d.zone==="mine"?1:0,"msg.gZone",["her","mine"],"Show times in");
  b+='<div role="radiogroup" aria-label="When she gets it" style="display:grid;gap:10px">'+
    ruleBtn("At her next bedtime",whenLong(bedAt,d.zone),d.rule==="bedtime","bedtime")+
    ruleBtn("On a night I choose",d.rule==="night"&&d.night?"Chosen: "+whenLong(((nx.filter(function(n){return n.key===d.night;})[0])||{t:bedAt}).t,d.zone):"Pick a night; she gets it at bedtime",d.rule==="night","night")+
    ruleBtn("When she wakes","The first time she opens her tablet after "+L.fmt.time(wakeAt,homeTz())+" her time",d.rule==="wake","wake")+'</div>';
  if(d.rule==="night")b+='<div class="lm-chips" role="group" aria-label="Choose a night">'+nx.map(function(n){return K.filterChip(dateShort(n.t,homeTz()),{on:d.night===n.key}).replace("<button",'<button'+L.a("msg.gNight",n.key));}).join("")+'</div>';
  var when=d.rule==="wake"?wakeAt:d.rule==="night"&&d.night?(nx.filter(function(n){return n.key===d.night;})[0]||{t:bedAt}).t:bedAt;
  b+=K.card('<h4>Review</h4><p>'+E(kid)+' gets <b>'+E((d.name||"").trim()||"your message")+'</b> '+(d.rule==="wake"?"after she wakes, ":"")+E(lc1(whenLong(when,d.zone)))+'. You will see when it reaches her tablet and when she plays it through.</p><p>If her tablet is off then, we keep trying and tell you. Messages you send are always kept.</p>',"tint");
  b+=L.btn(d.busy?"Banking...":"Bank this message","msg.gBankIt",null,{full:true,ic:"check",disabled:d.busy});
  return gtop("Bank a message",{eyebrow:"Step 2 of 2"})+K.page(b);}});

/* ---- Delivery detail ---- */
function lc1(s){return String(s).replace(/^(Tonight|Today|Tomorrow night|Tomorrow)/,function(w){return w.toLowerCase();});}
function tlTime(t){return t?L.fmt.time(t,homeTz()):"";}
L.screen("msg.gDetail",{dev:"g",title:"Delivery detail",render:function(c){
  var it=findI(c.params.id),kid=kname();
  if(!it)return gtop("Delivery detail")+K.page(K.emptyState({spot:"envelope",title:"That message is not here",sub:"It may have been taken out of the queue."}));
  var st=uiState(it),items=[];
  items.push({title:"Recorded",sub:stampBoth(it.recordedT),ic:"mic",state:"done",time:tlTime(it.recordedT)});
  items.push({title:"Queued for "+(it.rule.type==="wake"?"when she wakes":it.rule.type==="night"?"a chosen night":"bedtime"),sub:it.readyAt?"Due "+whenLong(it.readyAt,it.zone):"",ic:"clock",state:"done",time:tlTime(it.bankedT)});
  if(it.deliveredT)items.push({title:"Delivered to "+kid+AP+"s tablet",sub:stampBoth(it.deliveredT)+". The tablet confirmed it holds the video.",ic:"device",state:"done",time:tlTime(it.deliveredT)});
  else if(st==="failed")items.push({title:"Didn"+AP+"t arrive",sub:qsub(it)+". Tried "+it.attempts+" times.",ic:"warn",state:"done",tone:"bad",time:tlTime(it.failT)});
  else items.push({title:"Delivered to "+kid+AP+"s tablet",sub:st==="delivering"?qsub(it):"Not yet",ic:"device",state:st==="delivering"?"now":"next"});
  items.push(it.openedT?{title:"She opened it",sub:stampBoth(it.openedT),ic:"eye",state:"done",time:tlTime(it.openedT)}:{title:"She opens it",sub:"Not yet",ic:"eye",state:"next"});
  if(it.state==="watched")items.push({title:"She watched it",sub:stampBoth(it.watchedT)+". Played through, "+mss(it.durMs)+" of "+mss(it.durMs)+".",ic:"play",state:"done",tone:"ok",time:tlTime(it.watchedT)});
  else if(it.playedMs>0)items.push({title:"She started it",sub:mss(it.playedMs)+" of "+mss(it.durMs)+". Not watched yet.",ic:"play",state:"now",tone:"warn"});
  else items.push({title:"She watches it",sub:"Played through to the end",ic:"play",state:"next"});
  var b=K.card('<div class="row" style="padding:0">'+thumb(it.scene,56)+'<span class="rtxt"><b>'+E(it.title)+'</b><small>'+mss(it.durMs)+' long. '+(it.preserved?"Kept for good":"")+'</small></span>'+pill(st)+'</div>');
  b+=K.card(K.timeline(items));
  b+=K.card('<h4>What “watched” means</h4><p>'+E(kid)+' played your message through on her tablet. It does not mean she looked at the screen the whole time, or understood it.</p><p>If she stops part-way you will see <b>“She started it, 0:42 of 1:41”</b>, not “watched”.</p>',"tint");
  var reps=M().replies.filter(function(r){return r.replyTo===it.id;});
  if(reps.length)b+=K.card(replyRows(reps));
  b+=K.card('<h4>What we did</h4>'+it.log.map(function(l){return '<p style="margin:3px 0"><span class="tnum" style="color:var(--ink3)">'+E(L.fmt.dayTime(l.t,homeTz()))+'</span> '+E(l.text)+'</p>';}).join(""),"flat");
  b+=L.btn("Send this again, tonight","msg.gResend",it.id,{full:true,kind:"ghost",ic:"refresh"});
  if(it.state==="pending"||it.state==="ready"||it.state==="delivering")b+=L.btn("Take it out of the queue","msg.cancel",it.id,{full:true,kind:"ghost",ic:"trash"});
  return gtop("Delivery detail")+K.page(b);}});
A("msg.gResend",function(c,arg){var it=findI(arg);if(!it)return;bankNow({title:it.title,durMs:it.durMs,rule:"bedtime",scene:it.scene,zone:it.zone}).then(function(r){if(r.ok)L.replace("g","msg.gQueue");done();});});

/* ---- Why it didn't arrive ---- */
L.screen("msg.gFail",{dev:"g",title:"Why it didn’t arrive",render:function(c){
  var it=findI(c.params.id),kid=kname();
  if(!it)return gtop("Didn"+AP+"t arrive")+K.page(K.emptyState({spot:"envelope",title:"That message is not here"}));
  var ok=it.state==="delivered"||it.state==="watched";
  var reason=it.failWhy==="push_rejected"?"Our nudge could not wake her tablet, so it did not check in. The message is safe on our side and has not been lost.":"Her tablet was off, or had no signal, at bedtime. The message is safe on our side and has not been lost.";
  var b=ok?K.banner("ok",E(it.title)+" has now reached "+E(kid)+AP+"s tablet.","check"):K.banner("bad",E(it.title)+" did not reach "+E(kid)+AP+"s tablet on "+E(dateShort(it.readyAt,homeTz()))+".","warn");
  b+=K.card('<h4>What happened</h4><p>'+E(reason)+'</p><p class="lm-hint">Delivered only counts once her tablet says it holds the video.</p>');
  if(!ok){b+=L.btn("Try again now","msg.retry",it.id,{full:true,ic:"refresh"})+L.btn("Move to another night","msg.gMove",it.id,{full:true,kind:"ghost",ic:"calendar"});}
  b+=K.sectionLabel("What we do by ourselves")+K.card(rowb({ic:"refresh",title:"Retry",sub:"Again after 10 minutes, then hourly, up to "+CAP+" tries"})+rowb({ic:"bell",title:"Wake her tablet",sub:"A quiet nudge with no content, so it checks in"})+rowb({ic:"device",title:"Deliver on her next open",sub:"If it is still waiting, it arrives the first time she opens the app"})+rowb({ic:"chat",title:"Tell you",sub:"You hear when it lands, or if it still has not",tone:"info"}));
  return gtop(ok?"It arrived":"Didn"+AP+"t arrive")+K.page(b);}});

/* ---- Notifications ---- */
L.screen("msg.gNotif",{dev:"g",title:"Notifications",render:function(c){
  var m=M(),n=m.notif,kid=kname(),b="";
  b+=K.card(rowb({ic:"bell",title:"Notifications on this phone",sub:n.permission==="granted"?"On. They only say that something is waiting.":n.permission==="denied"?"Off. The app checks every few minutes while it is open.":"Not asked yet",tone:n.permission==="granted"?"ok":"info",act:n.permission==="granted"?null:"msg.gPrime",go:n.permission!=="granted",trail:n.permission==="granted"?K.chip("On",{sm:true,tone:"ok",ic:"check"}):""}));
  b+=K.sectionLabel("Tell me when")+K.card(
    togglerow({ic:"clock",title:"Late notice",sub:"The other house says they are running late",on:n.late,act:"msg.gNotifToggle",arg:"late"})+
    togglerow({ic:"letter",title:"New handover note",sub:"A note was added for you",on:n.handover,act:"msg.gNotifToggle",arg:"handover"})+
    togglerow({ic:"receipt",title:"An expense is waiting for you",sub:"It needs your yes or no",on:n.expense,act:"msg.gNotifToggle",arg:"expense"})+
    togglerow({ic:"pill",title:"A dose was logged",sub:"That a dose was given, never which one",on:n.dose,act:"msg.gNotifToggle",arg:"dose"})+
    togglerow({ic:"eye",title:kid+" played my message",sub:"When she watches it through",on:n.played,act:"msg.gNotifToggle",arg:"played"})+
    togglerow({ic:"mic",title:kid+" sent me something",sub:"A voice note, video or drawing",on:n.reply,act:"msg.gNotifToggle",arg:"reply"})+
    togglerow({ic:"warn",title:"A message didn"+AP+"t arrive",sub:"Only when it needs you",on:n.failed,act:"msg.gNotifToggle",arg:"failed"}));
  b+=K.sectionLabel("Quiet hours")+K.card(
    togglerow({ic:"moon",title:"Quiet hours",sub:L.fmt.time(L.zoned(2026,1,1,hmOf(n.qFrom)[0],hmOf(n.qFrom)[1],meTz()),meTz())+" to "+L.fmt.time(L.zoned(2026,1,1,hmOf(n.qTo)[0],hmOf(n.qTo)[1],meTz()),meTz())+", your time",on:n.quiet,act:"msg.gNotifToggle",arg:"quiet"})+
    togglerow({ic:"phone",title:"Let "+kid+AP+"s knocks through",sub:"So a call from her is never silent",on:n.knocks,act:"msg.gNotifToggle",arg:"knocks"}));
  b+=segb(["8:30 PM to 6 AM","9:30 PM to 6:30 AM","10:30 PM to 7 AM"],n.qFrom==="20:30"?0:n.qFrom==="22:30"?2:1,"msg.gQuiet",["early","normal","late"],"Quiet hours window");
  b+=K.card('<h4>What a notification never contains</h4><div class="lm-lock" style="margin-top:8px"><div class="nt">'+K.logo(28)+'<span><b>Olive Branch</b><small>'+(n.showFrom?E(kid)+": something new is waiting":"Something new is waiting. Open to see.")+'</small></span></div></div><p>No message text. No names of medicines. No amounts. No pictures. Only that something is waiting.</p>');
  b+=K.card(togglerow({ic:"lock",title:"Show who it is from on the lock screen",sub:"Shows “"+E(kid)+"”, never what it says",on:n.showFrom,act:"msg.gNotifToggle",arg:"showFrom"}),"flat");
  var recent=m.pushLog.filter(function(p){return p.to==="g";}).slice(-4).reverse();
  b+=K.sectionLabel("What was sent to this phone")+(recent.length?K.card(recent.map(function(p){return '<div class="row"><span class="ricon">'+I(p.ok?"bell":"moon",20,1.9)+'</span><span class="rtxt"><b>'+E(p.text)+'</b><small>'+E(L.fmt.dayTime(p.at,meTz()))+(p.ok?"":p.why==="quiet_hours"?". Held for quiet hours":". Not shown (notifications are off)")+'</small></span></div>';}).join("")):K.card('<p class="lm-hint">Nothing yet. Every notification would appear here, word for word.</p>',"flat"));
  return gtop("Notifications")+K.page(b);}});

/* ---- Push priming ---- */
L.screen("msg.gPush",{dev:"g",title:"Before we ask",render:function(c){var kid=kname();
  return gtop("",{})+K.page('<div style="margin:0 -2px">'+K.scene("letters",300,150)+'</div><div class="big" style="font-size:26px">Know the moment something arrives</div><p style="color:var(--ink2);margin:0">We can nudge your phone when '+E(kid)+' plays your message, or when a note needs you.</p>'+
    K.card(rowb({ic:"check",title:"Only that something is waiting",sub:"Never what it says",tone:"ok"})+rowb({ic:"moon",title:"Quiet at night",sub:"Your hours, your choice",tone:"ok"}))+'<div class="lm-sys">'+I("device",18,2)+'<span>Next, your phone asks you once. Choose Allow.</span></div>'+
    L.btn("Turn on notifications","msg.gPushAsk",null,{full:true,ic:"bell"})+L.btn("Not now","msg.gPrimeLater",null,{full:true,kind:"ghost"})+'<p class="lm-hint" style="text-align:center">Without them, the app checks every few minutes while it is open.</p>');}});

/* ---- Calls and history ---- */
function callOutcomeRow(h){var who=grWord(h.who),kid=kname(),when=L.fmt.dayTime(h.startedT,homeTz())+" her time";
  if(h.outcome==="answered")return rowb({ic:"video",title:h.dir==="in"?kid+" knocked, you answered":"Video call with "+kid,sub:when+". "+L.fmt.dur(h.durMs),tone:"ok",trail:K.chip("Answered",{sm:true,tone:"ok",ic:"check"})});
  if(h.outcome==="missed")return rowb({ic:"phone",title:kid+" knocked",sub:when+". You could not pick up. "+kid+" saw: “"+kidWord(h.who)+" will call back”",tone:"warn",trail:K.chip("Missed",{sm:true,tone:"warn",ic:"clock"})});
  if(h.outcome==="later")return rowb({ic:"phone",title:h.dir==="in"?"You chose Later":kid+" chose Later",sub:when+". "+(h.dir==="in"?kid+" saw “"+kidWord(h.who)+" will call back”":"She will call you back"),trail:K.chip("Later",{sm:true})});
  if(h.outcome==="stopped")return rowb({ic:"phone",title:kid+" knocked, then stopped",sub:when,trail:K.chip("Ended",{sm:true})});
  if(h.outcome==="noconnect")return rowb({ic:"video",title:"You called "+kid,sub:when+". She was not free. Nothing was shown to her",trail:K.chip("Didn"+AP+"t connect",{sm:true})});
  return rowb({ic:"video",title:"You ended the call before it connected",sub:when,trail:K.chip("Ended",{sm:true})});}
L.screen("msg.gCalls",{dev:"g",title:"Calls",render:function(c){
  var m=M(),kid=kname(),me=myId(),b="",mine=m.calls.filter(function(h){return h.who===me||me==="other";});
  b+=K.banner("pri","Not now is not a decline. If you choose Later, or cannot pick up, "+E(kid)+" sees “"+E(me?kidWord(me):"Mom")+" will call back”. She is never shown “declined”, “missed” or “no answer”.","heart");
  b+=L.btn("Call "+kid,"call.start",null,{full:true,ic:"video",disabled:!online("g")});
  if(!online("g"))b+='<p class="lm-hint">Calls need a connection. Everything else is saved on this phone.</p>';
  if(activeCall())b+=K.card(rowb({ic:"video",title:"A call is going on",sub:"Tap to open it",tone:"ok",act:"go",arg:"msg.gCall",go:true}));
  b+=K.sectionLabel("Recent")+(mine.length?K.card(mine.slice(0,8).map(callOutcomeRow).join("")):K.card('<p class="lm-hint">No calls yet. When '+E(kid)+' knocks, or you call her, it shows here.</p>',"flat"));
  b+=K.sectionLabel("When you are free for "+kid+AP+"s calls")+segb(["Mornings and evenings","Evenings","Any time","Not now"],["both","eve","any","off"].indexOf(m.avail[me]||"both"),"call.avail",["both","eve","any","off"],"When you are free")+
    '<p class="lm-hint">She sees a soft glow on your face when you are probably free. It comes from these hours, never from whether you are online.</p>';
  b+=K.card(rowb({ic:"shieldcheck",title:"Calls are never recorded",sub:"No audio or video is kept. Only that a call happened and how long it was.",tone:"ok"}),"flat");
  var lm=m.lastMisuse;
  b+='<div class="lm-sim"><h4>Simulation controls</h4><p class="lm-hint">Try the route a child must never use to start a call.</p>'+L.btn("Start a call from "+kid+AP+"s tablet","call.misuse",null,{size:"sm",kind:"tonal",ic:"shield"})+(lm?'<p class="lm-hint">Server said: <code class="mono">'+E(lm.status+" "+lm.code)+'</code></p>':"")+L.btn("Show rest time on her tablet","msg.restPreview",null,{size:"sm",kind:"ghost",ic:"moon"})+'</div>';
  return gtop("Calls")+K.page(b);}});

function callHero(top,bt){return '<i class="lm-g" hidden></i><div class="lm-full lm-hero" style="margin:6px 10px 12px;border-radius:30px;padding:26px 18px;align-items:center;justify-content:space-between;text-align:center">'+top+bt+'</div>';}
L.screen("msg.gCall",{dev:"g",title:"Call",render:function(c){
  var cl=M().call,kid=kname(),me=myId();
  if(!cl)return gtop("Call")+K.page(K.emptyState({spot:"phone",title:"No call right now",sub:"When "+kid+" knocks, you will see it here."}));
  var hero=function(title,sub,mid){return '<div style="display:grid;gap:8px;justify-items:center">'+(mid||"")+'<div class="big" style="font-size:30px">'+E(title)+'</div>'+(sub?'<small style="opacity:.92;font-size:13px">'+E(sub)+'</small>':"")+'</div>';};
  var herTime="It is "+L.fmt.time(T(),homeTz())+" where she is";
  var big=function(label,ic,act,cls){return '<button type="button" class="btn lg full" style="'+cls+'"'+L.a(act)+'>'+I(ic,22,2)+E(label)+'</button>';};
  if(cl.state==="ringing"&&cl.dir==="in"){
    if(cl.who!==me)return gtop("Call")+K.page(K.card(rowb({ic:"phone",title:kid+" is knocking on "+grWord(cl.who),sub:"It is ringing on their phone, not yours.",tone:"info"})));
    return callHero(hero(kid+" is calling",herTime,'<span class="chip" style="background:rgba(255,255,255,.18);color:inherit">'+I("hand",14,2)+'Knock knock</span>'+ringsOf("kid",c.form==="tablet"?150:170)),
      '<div style="display:grid;gap:10px;width:100%">'+big("Answer","video","call.answer","background:var(--ok);color:var(--bg);width:100%")+big("Later","clock","call.later","background:transparent;border:2px solid currentColor;color:inherit;width:100%")+'<small style="opacity:.92;font-size:12.5px">Later tells '+E(kid)+': “'+E(kidWord(me))+' will call back”</small></div>');}
  if(cl.state==="ringing")return callHero(hero("Calling "+kid+"...","She will see who is calling and can answer or choose not now.",ringsOf("kid",170)),'<div style="display:grid;gap:10px;width:100%">'+big("Cancel","x","call.cancel","background:transparent;border:2px solid currentColor;color:inherit;width:100%")+'</div>');
  if(cl.state==="connecting")return callHero(hero("Connecting...","One moment",ringsOf("kid",170,true)),"<span></span>");
  if(cl.state==="live"){var side=cl.mute&&cl.mute.g;
    return callHero(hero("With "+kid,"Not recorded",ringsOf("kid",150,true)+'<div class="lm-timer" data-lm="callT">'+mss(T()-cl.liveT)+'</div>'+(cl.mute&&cl.mute.k?'<span class="chip" style="background:rgba(255,255,255,.18);color:inherit">'+kid+AP+'s microphone is off</span>':"")),
      '<div class="lm-row3">'+rb("mic",72,side?"bad":"tonal",side?"Unmute":"Mute","call.mute",null)+rb("","88","bad","End call","call.end",null,{html:'<span style="transform:rotate(135deg);display:grid">'+I("phone",36,2)+'</span>'})+'</div>');}
  /* finished */
  var txt={answered:"The call ended. "+L.fmt.dur(cl.durMs||0)+". Calls are never recorded.",later:cl.dir==="in"?(cl.endT-cl.startedT>=RING_MS-1000?"You did not pick up. ":"You chose Later. ")+kid+" sees “"+kidWord(cl.who)+" will call back”.":kid+" will call you back.",missed:"You did not pick up. "+kid+" sees “"+kidWord(cl.who)+" will call back”.",stopped:kid+" stopped knocking.",noconnect:kid+AP+"s tablet did not pick up. Nothing was shown to her.",cancelled:"You ended the call before it connected."}[cl.outcome]||"The call is over.";
  return gtop("Call")+K.page(K.card('<h4>'+(cl.outcome==="answered"?"Call ended":cl.outcome==="later"?"Later":"Done")+'</h4><p>'+E(txt)+'</p>',"tint")+L.btn("Done","call.done",null,{full:true,ic:"check"}));}});

/* ---- Offline, safely ---- */
L.screen("msg.gOffline",{dev:"g",title:"Offline, safely",render:function(c){
  var m=M(),n=m.outbox.length,on=online("g"),b="";
  b+=on?K.banner("ok","You are back online. Anything waiting is being sent in order.","wifi"):K.banner("info","You are offline. Everything you do is saved on this phone.","wifioff");
  b+=K.card('<h4>'+n+' waiting to send</h4>'+(n?m.outbox.map(function(o){return rowb({ic:"mic",title:"Message for "+kname()+": "+o.body.title,sub:"Recorded "+L.fmt.time(o.t,meTz())+". Uploads when you are back",tone:"warn",trail:K.chip("Waiting",{sm:true,tone:"warn",ic:"clock"})});}).join(""):'<p class="lm-hint">Nothing waiting.</p>'));
  b+=L.btn("Check connection","msg.gCheck",null,{full:true,kind:"tonal",ic:"refresh"});
  b+=K.card('<h4>What is safe</h4>'+rowb({ic:"shieldcheck",title:"Nothing is lost",sub:"Even if you close the app",tone:"ok"})+rowb({ic:"clock",title:"Messages keep the time you recorded them",sub:"Not the time they send",tone:"ok"}));
  b+=K.card('<h4>What has to wait</h4>'+rowb({ic:"video",title:"Calls with "+kname(),sub:"They need a connection",tone:"info"})+rowb({ic:"chat",title:"New messages from "+kname(),sub:"They arrive when you are back",tone:"info"}));
  b+=K.card('<h4>How it resolves</h4><p>When you are back, we send them in the order you made them. Each one turns to “Sent” and leaves this list. Anything that cannot send stays here with a reason.</p>',"tint");
  return gtop("Offline")+K.page(b);}});
A("msg.gCheck",function(c){if(online("g")){flushOutbox();tg("g","Connected",{ic:"wifi"});}else tg("g","Still offline. Everything is saved here.",{ic:"wifioff"});});


/* ================================================================ CHILD SCREENS == */
function cloudScene(){return '<svg class="scene" viewBox="0 0 300 150" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="300" height="150" fill="var(--priC)"/><circle cx="238" cy="36" r="17" fill="var(--accent)" opacity=".9"/><circle cx="246" cy="31" r="15" fill="var(--priC)"/><g fill="var(--surface)" opacity=".9"><circle cx="40" cy="30" r="2"/><circle cx="84" cy="20" r="1.6"/><circle cx="170" cy="22" r="2"/></g><g fill="var(--surface)"><ellipse cx="130" cy="96" rx="54" ry="22"/><ellipse cx="100" cy="84" rx="28" ry="20"/><ellipse cx="156" cy="80" rx="34" ry="24"/></g><g fill="none" stroke="var(--ink3)" stroke-width="3" stroke-linecap="round"><path d="M112 92q4 4 8 0M140 92q4 4 8 0"/></g></svg>';}
function actTile(ic,label,act,arg,cmp){return '<button type="button" class="lm-ft" style="padding:'+(cmp?"8px 4px 6px":"14px 4px 6px")+';gap:'+(cmp?6:8)+'px"'+L.a(act,arg)+' aria-label="'+E(label)+'"><span class="av" style="width:56px;height:56px;display:grid;place-items:center">'+I(ic,28,1.8)+'</span><span class="lm-nm" style="padding:0 2px;gap:4px;font-size:15px;min-height:'+(cmp?48:64)+'px">'+I("volume",16,2)+'<b>'+E(label)+'</b></span></button>';}
function facesRow(act,sizeOpt,sel,compact){var gs=guardians();
  var tiles=gs.map(function(g){return ftile(g.id,{compact:compact,act:act,dot:act==="msg.kOpenFrom"&&unreadFrom(g.id),glow:freeNow(g.id)&&act!=="msg.kOpenFrom"&&act!=="msg.kSetTo",size:sizeOpt,sel:sel===g.id});});
  return gs.length>1?'<div class="grid2">'+tiles.join("")+'</div>':'<div style="max-width:230px;width:100%;margin:0 auto">'+tiles.join("")+'</div>';}
function offlineKid(){return '<div class="lm-poster">'+cloudScene()+'</div>';}

L.screen("msg.kMessages",{dev:"k",title:"Messages",render:function(c){
  var list=inbox(),off=!online("k"),tab=c.form==="tablet",newest=list[0],h="";
  var faces=facesRow("msg.kOpenFrom",tab?72:88,null,tab);
  var late="";
  if(off)late+=offlineKid()+say("Messages find you when the signal comes back",{plain:true});
  if(newest){var unread=newest.state==="delivered"&&!newest.openedT;
    late+=say((unread?"New from ":"From ")+kidWord(newest.by))+poster(newest.scene,newest.by,{act:"msg.play",arg:newest.id,inner:playBtn(72),label:"Play the message from "+kidWord(newest.by)});
    if(list.length>1)late+='<div class="lm-row3" style="justify-content:flex-start;gap:10px">'+list.slice(1,5).map(function(it){return '<button type="button" class="lm-th" style="width:'+(tab?56:72)+'px;height:'+(tab?56:72)+'px"'+L.a("msg.play",it.id)+' aria-label="Play an earlier message">'+K.scene(it.scene,72,72)+'</button>';}).join("")+'</div>';}
  var acts='<div class="grid3">'+actTile("mic","Say hi","msg.kReplyStart",null,tab)+actTile("brush","Draw","msg.kDrawOpen",null,tab)+actTile("phone","Call","call.kWho","call",tab)+'</div>';
  if(tab)return ctop("Messages")+full(c,faces+acts,late||say("Say hi to someone",{plain:true}),{m1:false,m2:false});
  return ctop("Messages")+K.page(faces+late+acts);}});

L.screen("msg.kPlay",{dev:"k",title:"Message",render:function(c){
  var it=findI(c.params.id),m=M(),p=m.play,tab=c.form==="tablet";
  if(!it||!onTablet(it))return ctop("")+'<div class="lm-full" style="align-items:center;justify-content:center">'+say("Nothing here",{plain:true})+rb("check",96,"pri","OK","call.done")+'</div>';
  var mine=p&&p.id===it.id,playing=mine&&p.playing,pct=mine?Math.min(100,p.pos/it.durMs*100):0;
  var pic='<div class="lm-poster fill">'+K.scene(it.scene,300,160)+'<span class="lm-pfm">'+face(it.by,tab?120:104,{label:kidWord(it.by)})+'</span>'+(mine&&p.cc?'<div data-lm="kCap" style="position:absolute;left:10px;right:10px;bottom:10px;background:rgba(0,0,0,.62);color:#fff;border-radius:14px;padding:8px 12px;font:700 15px var(--font-body);text-align:center">'+E(captionAt(p.pos))+'</div>':"")+'</div>';
  var bar='<button type="button" class="lm-seek"'+L.a("msg.seek")+' aria-label="Move along the message"><span class="lm-bar"><i data-lm="kBar" style="width:'+pct.toFixed(1)+'%"></i></span></button>';
  var ctl=bar+'<div class="lm-row3"'+(tab?' style="gap:10px"':"")+'>'+rb("","64",mine&&p.cc?"pri":"tonal","Captions","msg.cc",null,{html:'<b style="font:800 17px var(--font-display)">CC</b>'})+
    rb(!mine||!playing?"play":"pause",92,"pri",!mine||!playing?(mine&&p.ended?"Play again":"Play"):"Pause",mine?"msg.pause":"msg.play",mine?null:it.id)+rb("refresh",64,"tonal","Play again","msg.again",null,{disabled:!mine})+'</div>'+
    '<div class="lm-row3">'+rb("mic",64,"tonal","Say hi back","msg.kReplyStart",it.by)+'</div>';
  var from=say("From "+kidWord(it.by),{plain:true});
  if(tab)return ctop("Message")+full(c,pic,from+ctl,{m2:true});
  return ctop("Message")+'<div class="lm-full">'+pic+ctl+'</div>';}});

L.screen("msg.kReply",{dev:"k",title:"Say hi back",render:function(c){
  var k=M().kd,tab=c.form==="tablet",to=k.to||dflTo();
  if(k.stage==="review"){
    var frac=k.ms?k.pv/k.ms:0;
    var pv='<div class="lm-box" style="padding:12px;display:flex;align-items:center;gap:12px">'+rb(k.pvOn?"pause":"play",64,"pri",k.pvOn?"Stop":"Play my message","msg.kPreview")+'<div style="flex:1;min-width:0">'+wavePlayed(k.pvOn?frac:0).replace("height:70px","")+'</div>'+rb("refresh",64,"tonal","Record again","msg.kRecAgain")+'</div>';
    var who=facesRow("msg.kSetTo",72,to);
    var send='<button type="button" class="btn pri lg full" style="min-height:72px"'+L.a("msg.replySend")+'>'+I("send",24,2)+'Send to '+E(kidWord(to))+'</button>';
    if(tab)return ctop("Send it to...")+full(c,pv,who+send,{m1:true,m2:false});
    return ctop("Send it to...")+K.page(pv+who+send);}
  var rec=k.stage==="rec",f=Math.min(1,k.ms/KMAX);
  var mode='<div class="lm-mode" role="radiogroup" aria-label="Voice or video"><button type="button" role="radio" aria-checked="'+(k.mode==="voice")+'" class="'+(k.mode==="voice"?"on":"")+'"'+L.a("msg.kMode","voice")+'>'+I("mic",24,2)+'Voice</button><button type="button" role="radio" aria-checked="'+(k.mode==="video")+'" class="'+(k.mode==="video"?"on":"")+'"'+L.a("msg.kMode","video")+'>'+I("video",24,2)+'Video</button></div>';
  var pic='<div class="lm-box" style="padding:14px 10px;display:grid;justify-items:center;gap:6px">'+face("kid",tab?64:72,{label:cname()})+'<div class="lm-wave" data-lm="kWaveRec">'+(rec?waveBars(k.ms,22):BARS.map(function(h){return '<i class="o" style="height:'+Math.round(h/2)+'px"></i>';}).join(""))+'</div></div>';
  var ring='<div class="lm-row3"><div class="lm-rings" style="width:136px;height:136px"><svg width="136" height="136" viewBox="0 0 136 136" style="position:absolute;inset:0" aria-hidden="true"><circle cx="68" cy="68" r="63" fill="none" stroke="var(--surface3)" stroke-width="7"/><circle data-lm="kRing" cx="68" cy="68" r="63" fill="none" stroke="var(--bad)" stroke-width="7" stroke-linecap="round" stroke-dasharray="396" stroke-dashoffset="'+Math.round(396*(1-f))+'" transform="rotate(-90 68 68)"/></svg>'+
    rb("","104","bad",rec?"Stop recording":"Start recording","msg.kRec",null,{html:rec?'<span style="width:34px;height:34px;border-radius:9px;background:var(--bg);display:block"></span>':'<span style="width:34px;height:34px;border-radius:50%;background:var(--bg);display:block"></span>'})+'</div></div>';
  var hint='<div class="lm-kv" style="color:var(--ink2)">'+I("hand",26,1.8)+I("arrowR",20,2)+I("mic",26,1.8)+'</div>';
  if(tab)return ctop("Say hi back")+full(c,mode+pic,ring+hint,{m1:true});
  return ctop("Say hi back")+'<div class="lm-full">'+mode+pic+'<div class="lm-spacer"></div>'+ring+hint+'</div>';}});

L.screen("msg.kSent",{dev:"k",title:"Sent",render:function(c){var to=M().kd.to||dflTo();
  return ctop("",{noBack:true})+'<div class="lm-full" style="align-items:center;justify-content:space-between;text-align:center"><div class="lm-poster" style="width:100%;aspect-ratio:16/11">'+K.scene("letters",300,160)+'<span style="position:absolute;right:14px;bottom:12px">'+face(to,84,{label:kidWord(to)})+'</span></div><div class="lm-kv" style="color:var(--pri)">'+I("heart",44,1.8)+'</div>'+say("It"+AP+"s on its way to "+kidWord(to),{plain:true})+rb("check",96,"pri","Done","msg.kDone")+'</div>';}});
L.screen("msg.kQueued",{dev:"k",title:"Waiting for signal",render:function(c){var to=M().kd.to||dflTo();
  return ctop("",{noBack:true})+'<div class="lm-full" style="align-items:center;justify-content:space-between;text-align:center"><div class="lm-poster" style="width:100%;aspect-ratio:16/11">'+K.scene("letters",300,160)+'<span style="position:absolute;left:12px;top:12px;width:58px;height:58px;border-radius:50%;background:var(--surface);color:var(--ink2);display:grid;place-items:center;box-shadow:var(--shadow1)">'+I("cloud",30,1.8)+'</span><span style="position:absolute;right:14px;bottom:12px;opacity:.85">'+face(to,76,{label:kidWord(to)})+'</span></div>'+say("It will go when the signal comes back",{plain:true})+rb("check",96,"pri","OK","msg.kDone")+'</div>';}});

L.screen("msg.kDraw",{dev:"k",title:"Draw for them",render:function(c){
  var d=M().draw,tab=c.form==="tablet",to=d.to||dflTo(),gs=guardians();
  var cv='<div class="lm-canvas"><canvas data-lm="draw" aria-label="Drawing area. Draw with your finger."></canvas><span class="lm-undo">'+rb("arrowL",64,"tonal","Undo","msg.kUndo")+'</span></div>';
  var inks='<div class="lm-inks">'+["pri","accent","info","dpMorning"].map(function(t){return '<button type="button" class="lm-ink'+(d.ink===t?" on":"")+'" style="background:var(--'+t+')" aria-label="Colour" aria-pressed="'+(d.ink===t)+'"'+L.a("msg.kInk",t)+'></button>';}).join("")+'</div>';
  var snd='<div class="lm-row3">'+gs.map(function(g){return '<button type="button" class="lm-b" style="width:auto;padding:6px;border-radius:50%"'+L.a("msg.kDrawWho",g.id)+' aria-label="Send to '+E(kidWord(g.id))+'" aria-pressed="'+(to===g.id)+'">'+face(g.id,64,{sel:to===g.id,label:kidWord(g.id)})+'</button>';}).join("")+'<button type="button" class="btn pri lg" style="flex:1;min-height:72px;min-width:0"'+L.a("msg.drawSend",to)+'>'+I("send",22,2)+'Send</button></div>';
  if(tab)return ctop("Draw for them")+full(c,cv,inks+snd,{m2:true});
  return ctop("Draw for them")+'<div class="lm-full">'+cv+inks+snd+'</div>';}});

L.screen("msg.kWho",{dev:"k",title:"Who?",render:function(c){
  var m=M(),tab=c.form==="tablet",call=m.wmode!=="msg";
  var mode='<div class="lm-mode" role="radiogroup" aria-label="Message or call"><button type="button" role="radio" aria-checked="'+(!call)+'" class="'+(!call?"":"")+(call?"":"on")+'"'+L.a("call.kMode","msg")+'>'+I("mail",24,2)+'Message</button><button type="button" role="radio" aria-checked="'+call+'" class="'+(call?"on":"")+'"'+L.a("call.kMode","call")+'>'+I("video",24,2)+'Call</button></div>';
  var faces=facesRow(call?"call.knock":"msg.kWhoMsg",tab?72:88);
  return ctop("Who?")+(tab?'<div class="lm-full">'+mode+faces+'</div>':K.page(mode+faces));}});

L.screen("msg.kOffline",{dev:"k",title:"No signal",render:function(c){
  var acts='<div class="grid3">'+actTile("brush","Draw","msg.kDrawOpen",null)+actTile("mic","Say hi","msg.kReplyStart",null)+actTile("dice","Play","msg.kTry","games")+'</div>';
  var pic=offlineKid();
  if(c.form==="tablet")return ctop("",{noSpeak:false})+full(c,pic+say("Your messages will find you",{plain:true}),acts,{m1:true,m2:true});
  return ctop("")+'<div class="lm-full">'+pic+say("Your messages will find you",{plain:true})+'<div class="lm-spacer"></div>'+acts+'</div>';}});
A("msg.kTry",function(c,arg){var ids=[arg,"games","play","activities","child.games","k.games"];for(var i=0;i<ids.length;i++){if(ids[i]&&L.hasScreen(ids[i],"k")){L.go("k",ids[i]);return;}}L.home("k");});

function kCallBody(c){
  var cl=M().call,tab=c.form==="tablet";
  if(!cl)return ctop("",{noSpeak:true})+'<div class="lm-full" style="align-items:center;justify-content:center">'+say("All done",{plain:true})+rb("check",96,"pri","OK","call.done")+'</div>';
  var nm=kidWord(cl.who),arr='<div class="lm-kv" style="color:var(--ok)">'+I("arrowR",34,2.2)+I("phone",34,1.8)+'</div>';
  var stop=rb("x",80,"tonal","Stop","call.stop");
  if(cl.dir==="in"&&cl.state==="ringing")return ctop("")+(tab?full(c,ringsOf(cl.who,210),say("Knocking on "+nm,{plain:true})+'<div class="lm-row3">'+stop+'</div>'):'<div class="lm-full" style="align-items:center;justify-content:space-between;text-align:center">'+ringsOf(cl.who,230)+say("Knocking on "+nm,{plain:true})+stop+'</div>');
  if(cl.state==="connecting"&&cl.dir==="in")return ctop("")+(tab?full(c,ringsOf(cl.who,210,true),arr+say(nm+" is coming",{plain:true})+'<div class="lm-row3">'+stop+'</div>'):'<div class="lm-full" style="align-items:center;justify-content:space-between;text-align:center">'+ringsOf(cl.who,230,true)+arr+say(nm+" is coming",{plain:true})+stop+'</div>');
  if(cl.state==="connecting")return ctop("",{noBack:true,noSpeak:true})+'<div class="lm-full" style="align-items:center;justify-content:center;text-align:center">'+ringsOf(cl.who,210,true)+say(nm,{plain:true})+'</div>';
  if(cl.dir==="in"&&cl.state==="later"&&!cl.kDone){
    var box='<div class="lm-box lm-bgc" style="width:100%;padding:18px 10px;display:grid;justify-items:center;gap:8px">'+face(cl.who,96,{label:nm})+'<div class="lm-kv">'+I("clock",30,1.8)+I("arrowR",24,2)+I("phone",30,1.8)+'</div></div>';
    var two='<div class="grid2" style="width:100%">'+actTile("brush","Draw","msg.kDrawOpen",null)+actTile("mail","Message","msg.kReplyStart",cl.who)+'</div>';
    return ctop("")+(tab?full(c,box+say(nm+" will call back",{plain:true}),two+'<div class="lm-row3">'+rb("check",80,"pri","OK","call.kDismiss")+'</div>',{m1:true,m2:true}):'<div class="lm-full" style="align-items:center;text-align:center">'+box+say(nm+" will call back",{plain:true})+two+rb("check",80,"pri","OK","call.kDismiss")+'</div>');}
  if(cl.dir==="out"&&cl.state==="ringing"){
    var nameBtn='<button type="button" class="lm-say plain" style="font-size:30px"'+L.a("msg.say",nm+" is calling")+' aria-label="Hear: '+E(nm)+' is calling">'+I("volume",28,2)+'<span>'+E(nm)+'</span></button>';
    var ans='<button type="button" class="btn lg full" style="background:var(--ok);color:var(--bg);min-height:96px;font-size:22px"'+L.a("call.answer")+'>'+I("phone",34,2)+'Answer</button>';
    var no='<div class="lm-row3">'+rb("x",64,"tonal","Not now","call.later")+'</div>';
    return ctop("",{noBack:true,noSpeak:true})+(tab?'<div class="lm-full rw lm-bgc" style="margin:0 10px 12px;border-radius:30px;align-items:center;padding:18px"><div class="lm-col mid" style="text-align:center">'+ringsOf(cl.who,200)+nameBtn+'</div><div class="lm-col mid">'+ans+no+'</div></div>':'<div class="lm-full lm-bgc" style="margin:0 10px 12px;border-radius:30px;align-items:center;justify-content:space-between;text-align:center;padding:22px 14px">'+ringsOf(cl.who,210)+nameBtn+ans+no+'</div>');}
  if(cl.state==="live"){var muted=cl.mute&&cl.mute.k;
    return '<i class="lm-c" hidden></i><div class="lm-full" style="padding-top:4px"><div style="position:relative;flex:1;min-height:150px;border-radius:30px;overflow:hidden;background:linear-gradient(160deg,#2a3f55,#121b26)"><div style="position:absolute;inset:0;display:grid;place-items:center">'+face(cl.who,124,{label:nm})+'</div><span class="chip" style="position:absolute;top:12px;left:12px;background:rgba(0,0,0,.4);color:#fff">'+E(nm)+'</span><div style="position:absolute;right:12px;bottom:12px;width:72px;height:96px;border-radius:20px;background:linear-gradient(160deg,var(--pri),var(--priD));box-shadow:var(--shadow2);display:grid;place-items:center">'+face("kid",44,{label:cname()})+'</div></div><div class="lm-row3">'+rb("mic",72,muted?"bad":"tonal",muted?"Unmute":"Mute","call.mute")+rb("","88","bad","End call","call.end",null,{html:'<span style="transform:rotate(135deg);display:grid">'+I("phone",36,2)+'</span>'})+'</div></div>';}
  return ctop("",{noBack:true,noSpeak:true})+'<div class="lm-full" style="align-items:center;justify-content:center;text-align:center">'+ringsOf(cl.who,190)+say("Bye bye",{plain:true})+rb("check",96,"pri","OK","call.done")+'</div>';}
L.screen("msg.kCall",{dev:"k",title:"Call",render:kCallBody});

L.screen("msg.kBreak",{dev:"k",title:"Rest time",render:function(c){
  var tab=c.form==="tablet",list=inbox(),gs=guardians(),last=list[0];
  var by=last?last.by:(gs[0]?gs[0].id:"mom");
  var pic='<div class="lm-poster">'+K.scene(last?last.scene:"paper",300,160)+'<span class="lm-pfc">'+face(by,56,{label:kidWord(by)})+'</span><span style="position:absolute;right:12px;bottom:10px;width:54px;height:54px;border-radius:50%;background:var(--surface);color:var(--pri);display:grid;place-items:center;box-shadow:var(--shadow1)">'+I("moon",28,1.8)+'</span></div>';
  var calls=facesRow("call.knock",72);
  if(tab)return ctop("")+full(c,pic+say(kidWord(by)+" is thinking of you",{plain:true}),calls,{m1:true,m2:true});
  return ctop("")+'<div class="lm-full">'+pic+say(kidWord(by)+" is thinking of you",{plain:true})+calls+'</div>';}});

/* ================================================================ TILES AND ROWS == */
L.tile({dev:"g",area:"home",tier:"hero",id:"msg-bank",title:"Message banking",sub:"Record a message and choose when she gets it",icon:"mic",screen:"msg.gQueue",order:30,scene:"night",
  when:function(c){return !!S().family.created;},badge:function(c){var n=failedCount();return n||null;}});
L.tile({dev:"g",area:"home",tier:"featured",id:"msg-calls",title:"Calls",sub:"Ivy can knock. Not now is not a decline",icon:"video",screen:"msg.gCalls",order:31,
  when:function(c){return !!S().family.created;},badge:function(c){var cl=M().call;return cl&&cl.state==="ringing"&&cl.dir==="in"&&cl.who===myId()?true:null;}});
L.tile({dev:"g",area:"more",tier:"standard",id:"msg-offline",title:"Waiting to send",icon:"wifioff",screen:"msg.gOffline",order:60,when:function(c){return !!M().outbox.length||!online("g");}});
L.tile({dev:"g",area:"settings",group:"Account",id:"msg-notif",title:"Notifications",sub:"What reaches you, and when",icon:"bell",screen:"msg.gNotif",order:20});
/* the child home (KID) registers its own Messages / People / Draw tiles; mine only appear if KID is not loaded */
function noKid(){return !L.hasAct("kid.msgs");}
L.tile({dev:"k",area:"home",tier:"featured",id:"k-msgs",title:"Messages",sub:"",icon:"chat",screen:"msg.kMessages",order:20,when:noKid,badge:function(c){return unreadAny()?true:null;}});
L.tile({dev:"k",area:"home",tier:"standard",id:"k-people",title:"Call",icon:"phone",act:"call.kWho",arg:"call",order:21,when:noKid});
L.tile({dev:"k",area:"more",tier:"standard",id:"k-draw",title:"Draw for them",icon:"brush",act:"msg.kDrawOpen",order:22,when:noKid});

}); /* module */
})();
