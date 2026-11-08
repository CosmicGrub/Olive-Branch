/* LIVE module: ONBOARDING. Role-first: Kid / Mom / Dad / Someone else. Pairing code generator, paired devices, sign-in, sign-out.
   SIMULATION: no real server. Screens are ob.*; every action is registered with L.act so scenarios can drive the real UI. */
LIVE.module("onboarding",function(L){
"use strict";
var K=window.OB,S=L.S,esc=L.esc;
function D(dev){return S.dev[dev];}
function dr(dev){var d=S.dev[dev];if(!d.draft)d.draft={};return d.draft;}
function dp(c,k){return "dev."+c.dev+".draft."+k;}
function famChild(){return S.family.child;}
var MONTHS=["January","February","March","April","May","June","July","August","September","October","November","December"];
var COLOURS=[["olive","Green"],["classic","Purple"],["calm","Teal"],["warm","Orange"],["playful","Coral"],["bold","Blue"]];
var ZONES=[["America/Chicago","Central time","Chicago"],["America/New_York","Eastern time","New York"],["America/Denver","Mountain time","Denver"],["America/Los_Angeles","Pacific time","Los Angeles"],["America/Phoenix","Arizona","Phoenix"],["America/Anchorage","Alaska","Anchorage"],["Pacific/Honolulu","Hawaii","Honolulu"],["Europe/London","United Kingdom","London"]];
var LABELS=["Mom","Dad","Stepmom","Stepdad","Grandma","Grandpa","Guardian"];

/* ------------------------------------------------------------ small pieces -- */
function stepper(n,total){return '<div style="padding:0 16px 4px">'+K.stepper(total,n)+'</div>';}
function page(c,title,inner,o){o=o||{};
  return K.top({back:o.back!==false&&D(c.dev).stack.length>1,title:title,eyebrow:o.eyebrow})+(o.stepper?stepper(o.stepper[0],o.stepper[1]):"")+K.page(inner,{});}
function pad(c,o){ // o:{total,filled,title,sub,zero,shuffle}
  var d=dr(c.dev);if(o.shuffle&&!d.padOrder){d.padOrder=[1,2,3,4,5,6,7,8,9].sort(function(){return Math.random()-.5;});}
  var h=K.pinPad({total:o.total,filled:o.filled,title:o.title,sub:o.sub,zero:o.zero,digits:o.shuffle?d.padOrder:[1,2,3,4,5,6,7,8,9]});
  return h.replace(/<button type="button"( class="alt")? aria-label="([^"]*)"/g,function(m,alt,lab){
    if(lab==="Use fingerprint")return '<button type="button" class="alt" aria-label="'+lab+'" disabled style="opacity:.3"';
    var arg=lab==="Delete"?"del":lab;return '<button type="button"'+(alt||"")+' data-act="ob.pad" data-arg="'+esc(arg)+'" aria-label="'+esc(lab)+'"';});}
function fmtCode(s){s=String(s||"");return s.slice(0,3)+" "+s.slice(3);}
function bigTile(ic,title,sub){return '<div class="hdr-center">'+K.spot(ic,96)+'<div class="t-title">'+esc(title)+'</div>'+(sub?'<div class="t-body" style="color:var(--ink2);max-width:36ch">'+esc(sub)+'</div>':"")+'</div>';}
function errText(code,extra){
  return {offline:"No network on this phone. This step needs the internet. Your answers are saved here.",invalid_pin:"That PIN is not right.",pin_locked:"Too many wrong PINs. Locked for 15 minutes.",not_found:"That code did not work. It may be wrong or expired.",
    role_mismatch:"This code is for a child’s tablet. A grown-up’s phone cannot use it.",rate_limited:"Too many tries. Wait a few minutes.",forbidden:"You are not allowed to do that.",validation_failed:"Something is missing.",session_expired:"Your session ended.",unauthenticated:"Sign in first."}[code]||("Something went wrong ("+code+").");}

/* ---------------------------------------------------------------- role first -- */
L.screen("ob.role",{dev:"both",title:"Who is using this device?",render:function(c){
  var kid=c.dev==="k";
  var h='<div class="hdr-center" style="padding-top:6px">'+K.logo(40)+'<div class="t-display" style="font-size:'+(kid?"38px":"32px")+';text-wrap:balance">Who is using this device?</div></div>'+
   '<button type="button" class="rolebtn" data-act="ob.pickRole" data-arg="kid"><span class="rav">K</span>Kid</button>'+
   '<button type="button" class="rolebtn" data-act="ob.pickRole" data-arg="mom"><span class="rav">M</span>Mom</button>'+
   '<button type="button" class="rolebtn" data-act="ob.pickRole" data-arg="dad"><span class="rav">D</span>Dad</button>'+
   '<div style="text-align:center"><button type="button" class="linkbtn" data-act="ob.pickRole" data-arg="other">Someone else</button></div>';
  return K.top({title:""})+K.page(h,{});
}});
var PATHS={kid:"ob.kid.name",mom:"ob.g.you",dad:"ob.g.you",other:"ob.other"};
L.act("ob.pickRole",function(c,role){var d=D(c.dev);d.role=role;
  var g=dr(c.dev);
  if(role==="mom"||role==="dad"){g.gname=g.gname||(role==="mom"?"Jess":"Marcus");g.glabel=role==="mom"?"Mom":"Dad";g.tz=role==="mom"?"America/Chicago":"America/New_York";}
  L.go(c.dev,PATHS[role]);});

/* ---------------------------------------------------------------- kid path -- */
var KSTEPS=["name","age","color","birthday","names","connect"];
L.screen("ob.kid.name",{dev:"both",render:function(c){var d=dr(c.dev),ok=!!(d.name&&d.name.trim());
  return page(c,"What is your name?",'<div class="hdr-center">'+K.spot("leaf",88)+'</div>'+L.field({label:"My name",path:dp(c,"name"),ph:"Ivy",autocomplete:false,maxlength:20})+
    '<div class="t-cap" style="text-align:center">Only you and your grown-ups will see this.</div>'+L.btn("Next","go","ob.kid.age",{full:true,size:"lg",disabled:!ok}),{stepper:[1,6]});}});
L.screen("ob.kid.age",{dev:"both",render:function(c){var d=dr(c.dev),lock=!!d.ageLocked,btns="";
  for(var a=5;a<=15;a++)btns+='<button type="button" data-act="ob.kid.pickAge" data-arg="'+a+'" aria-pressed="'+(d.age===a)+'"'+(lock&&d.age!==a?" disabled":"")+'>'+a+'</button>';
  var body='<div class="t-body" style="text-align:center">How old are you?</div><div class="agegrid" role="group" aria-label="Pick your age">'+btns+'</div>'+
    (lock?'<div class="hint-card" role="status">'+K.ico("lock",16,2)+' Your age is locked in: '+d.age+'.</div>':(d.age?L.btn("Lock in "+d.age,"ob.kid.askLock",null,{full:true,kind:"tonal"}):'<div class="t-cap" style="text-align:center">Pick a number. Then you lock it.</div>'))+
    L.btn("Next","go","ob.kid.color",{full:true,size:"lg",disabled:!lock});
  return page(c,"How old are you?",body,{stepper:[2,6]});}});
L.act("ob.kid.pickAge",function(c,a){var d=dr(c.dev);if(d.ageLocked)return;d.age=+a;});
L.act("ob.kid.askLock",function(c){var d=dr(c.dev);if(!d.age)return;
  L.sheet(c.dev,'<div class="hdr-center">'+K.spot("lock",80)+'<div class="t-title">Lock in '+d.age+'?</div><div class="t-body">After this you cannot change your age. If it is wrong, a grown-up can help.</div></div>'+
    L.btn("Yes, lock it","ob.kid.lockAge",null,{full:true,size:"lg"})+L.btn("Not yet","sheet.close",null,{full:true,kind:"ghost"}));});
L.act("ob.kid.lockAge",function(c){var d=dr(c.dev);d.ageLocked=true;L.closeSheet(c.dev);});
L.screen("ob.kid.color",{dev:"both",render:function(c){var d=dr(c.dev);
  var sw=COLOURS.map(function(x){var seed=K.SEEDS[x[0]].seed;return '<button type="button" class="swatch" role="radio" aria-checked="'+(d.color===x[0])+'" aria-label="'+x[1]+'" data-act="ob.kid.pickColor" data-arg="'+x[0]+'" style="background:'+seed+'">'+(d.color===x[0]?K.ico("check",28,3):"")+'</button>';}).join("");
  return page(c,"Pick your colour",'<div style="display:flex;flex-wrap:wrap;gap:14px;justify-content:center" role="radiogroup" aria-label="Colour">'+sw+'</div>'+
    '<div class="card"><div class="t-head">Your app will look like this</div><div class="t-cap">Soft, calm, yours.</div></div>'+L.btn("Next","go","ob.kid.birthday",{full:true,size:"lg",disabled:!d.color}),{stepper:[3,6]});}});
L.act("ob.kid.pickColor",function(c,v){dr(c.dev).color=v;});
L.screen("ob.kid.birthday",{dev:"both",render:function(c){var d=dr(c.dev);
  var mo='<option value="">Month</option>'+MONTHS.map(function(m,i){return '<option value="'+(i+1)+'"'+(+d.bm===i+1?" selected":"")+'>'+m+'</option>';}).join("");
  var days='<option value="">Day</option>';for(var i=1;i<=31;i++)days+='<option value="'+i+'"'+(+d.bd===i?" selected":"")+'>'+i+'</option>';
  var ok=d.bm&&d.bd;
  return page(c,"When is your birthday?",'<div class="hdr-center">'+K.spot("leaf",80)+'</div><label class="t-cap">Month<select class="sel" data-act="ob.kid.setBM" aria-label="Month">'+mo+'</select></label><label class="t-cap">Day<select class="sel" data-act="ob.kid.setBD" aria-label="Day">'+days+'</select></label>'+
    L.btn("Next","go","ob.kid.names",{full:true,size:"lg",disabled:!ok})+'<div style="text-align:center"><button type="button" class="linkbtn" data-act="go" data-arg="ob.kid.names">Skip for now</button></div>',{stepper:[4,6]});}});
L.act("ob.kid.setBM",function(c,v){dr(c.dev).bm=v;});
L.act("ob.kid.setBD",function(c,v){dr(c.dev).bd=v;});
function defaultWord(d,gid){return d.ageLocked&&d.age&&d.age<=15?(gid==="mom"?"Mommy":"Daddy"):(gid==="mom"?"Mom":"Dad");}
L.screen("ob.kid.names",{dev:"both",render:function(c){var d=dr(c.dev);
  function row(gid,ini){return '<div class="card" style="display:grid;gap:8px"><div style="display:flex;gap:12px;align-items:center">'+K.avatar(ini,{size:48,tone:"accent"})+'<b class="t-head">'+(gid==="mom"?"Mom":"Dad")+'</b></div>'+
     L.field({label:"I call them",path:dp(c,"nick."+gid),ph:defaultWord(d,gid),autocomplete:false,maxlength:20})+'</div>';}
  return page(c,"What do you call your grown-ups?",'<div class="t-body" style="color:var(--ink2)">Like names in a phone. You can call them anything. Only you can change these.</div>'+row("mom","M")+row("dad","D")+
    L.btn("Next","go","ob.kid.connect",{full:true,size:"lg"}),{stepper:[5,6]});}});
/* LAST step: connect this device (needs the network). Draft answers are already saved on this device. */
function conn(dev){var d=dr(dev);if(!d.conn)d.conn={code:"",status:"idle"};return d.conn;}
L.screen("ob.kid.connect",{dev:"both",render:function(c){var cn=conn(c.dev),st=cn.status,body;
  if(!L.online(c.dev)&&st==="idle"&&cn.code.length<6)st="idle";
  if(st==="busy")body='<div class="hdr-center">'+K.spot("tablet",96)+'<div class="t-title">Connecting…</div></div>'+K.skeleton("row",2);
  else if(st==="offline")body='<div class="hdr-center"><span class="eplate" style="width:96px;height:96px;display:grid;place-items:center;border-radius:30px;background:var(--surface2);color:var(--ink2)">'+K.ico("wifioff",52,1.6)+'</span><div class="t-title">No internet right now</div><div class="t-body" style="color:var(--ink2)">Your answers are safe on this tablet.</div></div>'+L.btn("Try again","ob.kid.submit",null,{full:true,size:"lg",ic:"refresh"});
  else if(st==="bad")body='<div class="hdr-center">'+K.spot("key",96)+'<div class="t-title">That code did not work</div></div>'+L.btn("Try again","ob.kid.retry",null,{full:true,size:"lg",ic:"refresh"});
  else if(st==="help")body='<div class="hdr-center">'+K.spot("family",96)+'<div class="t-title">Let us ask a grown-up</div></div>'+L.btn("Try again later","ob.kid.retry",null,{full:true,size:"lg",kind:"tonal"});
  else body='<div class="hdr-center">'+K.spot("tablet",88)+'<div class="t-title">Connect this tablet</div><div class="t-body" style="color:var(--ink2);max-width:34ch">Ask a grown-up to make a code on their phone. Type it here.</div></div>'+pad(c,{total:6,filled:cn.code.length,shuffle:true});
  return page(c,"Connect this device",body,{stepper:[6,6]});}});
L.act("ob.kid.retry",function(c){var cn=conn(c.dev);cn.code="";cn.status="idle";});
L.act("ob.kid.submit",function(c){var dev=c.dev,cn=conn(dev);if(cn.status==="busy"||cn.code.length<6)return;cn.status="busy";L.queueRender();
  L.api(dev,"POST","/v1/device-pairing/redeem",{code:cn.code,role:"child"}).then(function(r){
    L.update(function(S){var cn=conn(dev);
      if(r.ok){cn.status="ok";dr(dev).childId=r.body.childId;dr(dev).pending=true;S.dev[dev].onboarded=true;L.go(dev,"ob.kid.welcome");}
      else if(r.status===0)cn.status="offline";
      else if(r.status===404){cn.status="bad";cn.code="";}
      else{cn.status="help";cn.code="";}});
    if(r.ok)uploadDraft(dev);});});
function uploadDraft(dev){
  var d=dr(dev),nick={};["mom","dad"].forEach(function(g){var v=d.nick&&d.nick[g];if(v&&v.trim())nick[g]=v.trim();});
  var body={name:d.name,age:d.ageLocked?d.age:null,color:d.color,birthday:d.bm&&d.bd?{m:+d.bm,d:+d.bd}:null,nicknames:nick};
  return L.api(dev,"PUT","/v1/children/"+(d.childId||famChild().id)+"/profile",body).then(function(r){
    L.update(function(S){var d=dr(dev);d.pending=!r.ok;if(r.ok){d.uploaded=true;}});return r;});}
/* retry a pending draft upload when the network returns, and every so often */
function retryPending(){["k","g"].forEach(function(dev){var d=D(dev),x=d.draft;if(x&&x.pending&&d.paired&&d.role==="kid"&&L.online(dev)&&!x.uploading){x.uploading=true;uploadDraft(dev).then(function(){L.update(function(){dr(dev).uploading=false;});});}});}
L.on("net:change",retryPending);L.every(30000,retryPending,"draft-upload");
L.screen("ob.kid.welcome",{dev:"both",render:function(c){var d=dr(c.dev),nm=d.name||famChild().name||"friend";
  var sync=d.pending?'<div class="t-cap" style="text-align:center" role="status">'+K.ico("cloud",14,2)+' Saving your answers…</div>':"";
  return K.top({title:""})+K.page('<div class="hdr-center" style="padding-top:20px">'+K.spot("leaf",120)+'<div class="t-display" style="font-size:34px">You are all set, '+esc(nm)+'.</div></div>'+sync+L.btn("Let’s go","ob.kid.finish",null,{full:true,size:"lg"}),{});}});
L.act("ob.kid.finish",function(c){var d=D(c.dev);d.onboarded=true;d.locked=true;L.reroot(c.dev,"home");});
L.screen("ob.revoked",{dev:"both",render:function(c){return K.top({title:""})+K.page('<div class="hdr-center" style="padding-top:30px">'+K.spot("family",120)+'<div class="t-title">This tablet needs a grown-up</div></div>'+L.btn("Start again","ob.restart",null,{full:true,size:"lg",kind:"tonal"}),{});}});
L.act("ob.restart",function(c){var d=D(c.dev);d.role=null;d.draft={};d.onboarded=false;L.reroot(c.dev,"ob.role");});

/* ------------------------------------------------------------ guardian path -- */
L.screen("ob.g.you",{dev:"both",render:function(c){var d=dr(c.dev),ok=!!(d.gname&&d.gname.trim());
  var chips=L.chips(LABELS,LABELS.indexOf(d.glabel),"ob.g.label",{args:LABELS,wrap:true,label:"Your label"});
  return page(c,"About you",L.field({label:"Your name",path:dp(c,"gname"),ph:"Jess",req:true,autocomplete:false,maxlength:24})+
    '<div class="t-label">Your label in the app</div>'+chips+
    L.btn("Next","go","ob.g.child",{full:true,disabled:!ok})+
    '<div style="text-align:center"><button type="button" class="linkbtn" data-act="go" data-arg="ob.g.join">Already set up on another phone? Enter a code</button></div>',{stepper:[1,5]});}});
L.act("ob.g.label",function(c,v){dr(c.dev).glabel=v;});
L.screen("ob.g.child",{dev:"both",render:function(c){var d=dr(c.dev),a,btns="",ok=!!(d.cname&&d.cname.trim()&&d.cage);
  for(a=3;a<=17;a++)btns+='<button type="button" data-act="ob.g.pickAge" data-arg="'+a+'" aria-pressed="'+(+d.cage===a)+'" style="min-height:52px;font-size:22px">'+a+'</button>';
  return page(c,"About your child",L.field({label:"Child’s name",path:dp(c,"cname"),ph:"Ivy",req:true,autocomplete:false,maxlength:20})+
    '<div class="t-label">Age</div><div class="agegrid" role="group" aria-label="Age" style="grid-template-columns:repeat(5,minmax(0,1fr))">'+btns+'</div>'+
    K.notice({tone:"info",title:"Her age locks",text:"Once you finish setup the age cannot be changed here. It grows with her birthday."})+
    L.btn("Next","go","ob.g.zone",{full:true,disabled:!ok}),{stepper:[2,5]});}});
L.act("ob.g.pickAge",function(c,a){dr(c.dev).cage=+a;});
L.screen("ob.g.zone",{dev:"both",render:function(c){var d=dr(c.dev);
  var rows=ZONES.map(function(z){return L.withAct(K.radioRow({title:z[1],sub:z[2]+" · "+L.tzName(z[0]),on:d.tz===z[0]}),"ob.g.zone",z[0]);}).join("");
  return page(c,"Home time zone",'<div class="t-body" style="color:var(--ink2)">Pick the zone where '+esc(d.cname||"your child")+' is usually. The app shows “hers” and “yours” side by side.</div><div class="card" style="padding:4px 14px">'+rows+'</div>'+L.btn("Next","go","ob.g.pin",{full:true}),{stepper:[3,5]});}});
L.act("ob.g.zone",function(c,v){dr(c.dev).tz=v;});
L.screen("ob.g.pin",{dev:"both",render:function(c){var d=dr(c.dev),stage=d.pin1?2:1,cur=d.pinCur||"";
  var msg=d.pinErr?K.notice({tone:"bad",title:"Those did not match",text:"Let us try again."}):"";
  return page(c,"Make a PIN",msg+'<div class="t-body" style="color:var(--ink2)">Four digits. You need it to make pairing codes and to sign back in.</div>'+pad(c,{total:4,filled:cur.length,zero:true,title:stage===1?"Choose a PIN":"Type it again"}),{stepper:[4,5]});}});
L.act("ob.g.pinNext",function(c){var d=dr(c.dev);
  if(!d.pin1){d.pin1=d.pinCur;d.pinCur="";d.pinErr=false;return;}
  if(d.pinCur===d.pin1){d.pin=d.pin1;d.pinOk=true;d.pin1=null;d.pinCur="";d.pinErr=false;L.go(c.dev,"ob.g.connect");}
  else{d.pin1=null;d.pinCur="";d.pinErr=true;}});
L.screen("ob.g.connect",{dev:"both",render:function(c){var d=dr(c.dev),tz=d.tz||"America/Chicago";
  var st=d.creating?K.skeleton("row",3):"";
  var err=d.err?(d.err==="offline"?K.offlineBanner({text:"No network",sub:"Your answers are saved here. Connect, then try again.",action:"Retry"}).replace("<button",'<button data-act="ob.g.create"'):K.notice({tone:"bad",title:"Could not finish",text:errText(d.err)})):"";
  return page(c,"Connect this device",err+'<div class="card" style="padding:4px 14px">'+K.kv([["You",(d.gname||"")+" ("+(d.glabel||"")+")"],["Child",(d.cname||"")+", "+d.cage],["Home time zone",L.tzName(tz)],["PIN","••••"]])+'</div>'+
    '<div class="t-cap">The last step needs the internet. This is the first time anything leaves this phone.</div>'+st+L.btn(d.creating?"Connecting…":"Create our family","ob.g.create",null,{full:true,size:"lg",disabled:!!d.creating,ic:"shieldcheck"}),{stepper:[5,5]});}});
L.act("ob.g.create",function(c){var dev=c.dev,d=dr(dev);if(d.creating)return;d.creating=true;d.err=null;L.queueRender();
  L.api(dev,"POST","/v1/families",{guardian:{role:D(dev).role,name:d.gname,label:d.glabel,tz:d.tz},child:{name:d.cname,age:d.cage},pin:d.pin,homeTz:d.tz}).then(function(r){
    L.update(function(S){var d=dr(dev);d.creating=false;
      if(r.ok){d.err=null;S.dev[dev].onboarded=true;L.go(dev,"ob.g.done");}else d.err=r.status===0?"offline":(r.code||"error");});});});
L.screen("ob.g.done",{dev:"both",render:function(c){var nm=famChild().name||"your child";
  return K.top({title:""})+K.page('<div class="hdr-center" style="padding-top:12px">'+K.spot("family",110)+'<div class="t-title">Your family is ready</div><div class="t-body" style="color:var(--ink2);max-width:34ch">Next, connect '+esc(nm)+'’s tablet with a 6-digit code.</div></div>'+
    L.btn("Add "+nm+"’s tablet","go","ob.addDevice",{full:true,size:"lg",ic:"tablet"})+L.btn("Not now","ob.g.finish",null,{full:true,kind:"ghost"}),{});}});
L.act("ob.g.finish",function(c){var d=D(c.dev);d.draft={};L.reroot(c.dev,"home");});
/* a grown-up phone typing a pairing code: this is how a child's code is refused (role mismatch) */
L.screen("ob.g.join",{dev:"both",render:function(c){var d=dr(c.dev),res=d.joinErr?K.notice({tone:"bad",title:"Code refused",text:errText(d.joinErr)}):"";
  return page(c,"Enter a code",res+'<div class="t-body" style="color:var(--ink2)">Type a code made on another grown-up’s phone.</div>'+pad(c,{total:6,filled:(d.joinCode||"").length,zero:true}),{});}});
L.act("ob.join.go",function(c){var dev=c.dev,d=dr(dev);var code=d.joinCode;d.joinErr=null;
  L.api(dev,"POST","/v1/device-pairing/redeem",{code:code,role:"guardian"}).then(function(r){L.update(function(){var d=dr(dev);d.joinCode="";d.joinErr=r.ok?null:(r.status===0?"offline":r.code);});});});
L.screen("ob.other",{dev:"both",render:function(c){var d=dr(c.dev),res=d.otherErr?K.notice({tone:"warn",title:"Could not join",text:errText(d.otherErr)}):"";
  return page(c,"Someone else",res+'<div class="hdr-center">'+K.spot("key",88)+'<div class="t-body" style="color:var(--ink2);max-width:34ch">Grandparents, sitters and other helpers join with an invite from a family guardian.</div></div>'+
    L.field({label:"Invite code",path:dp(c,"inviteCode"),ph:"6 digits",inputmode:"numeric",maxlength:6,autocomplete:false})+L.btn("Join","ob.other.join",null,{full:true,disabled:!(d.inviteCode&&d.inviteCode.length===6)}),{});}});
L.act("ob.other.join",function(c){var dev=c.dev,d=dr(dev);
  L.api(dev,"POST","/v1/device-pairing/redeem",{code:d.inviteCode,role:"other"}).then(function(r){L.update(function(){dr(dev).otherErr=r.ok?null:(r.status===0?"offline":r.code);});});});

/* -------------------------------------------------------- generic pin pad -- */
var PADS={"ob.kid.connect":{path:"conn.code",max:6,submit:"ob.kid.submit"},"ob.g.pin":{path:"pinCur",max:4,submit:"ob.g.pinNext"},"ob.addDevice":{path:"pair.pin",max:4,submit:"ob.add.make"},
  "ob.signin":{path:"sign.pin",max:4,submit:"ob.signin.go"},"ob.g.join":{path:"joinCode",max:6,submit:"ob.join.go"}};
L.act("ob.pad",function(c,arg){var P=PADS[c.screenId];if(!P)return;var d=dr(c.dev);if(c.screenId==="ob.kid.connect")conn(c.dev);if(c.screenId==="ob.addDevice"&&!d.pair)d.pair={pin:""};if(c.screenId==="ob.signin"&&!d.sign)d.sign={pin:""};
  var cur=String(L.get(P.path,d)||"");
  if(arg==="del")cur=cur.slice(0,-1);else if(cur.length<P.max)cur+=arg;else return;
  L.set(P.path,cur,d);
  if(arg!=="del"&&cur.length===P.max){L.run(c.dev,P.submit);}});

/* ------------------------------------------------------ pairing code maker -- */
L.screen("ob.addDevice",{dev:"g",render:function(c){var d=dr(c.dev);if(!d.pair)d.pair={pin:""};var p=d.pair,nm=famChild().name||"your child",kd=S.dev.k;
  var tabs=L.tabbar("g",[{ic:"home",label:"Home",screen:"home"},{ic:"grid",label:"More",screen:"more"},{ic:"sliders",label:"Settings",screen:"settings"}],"");
  var body;
  if(kd.paired&&p.done)body='<div class="hdr-center">'+K.spot("tablet",96)+'<div class="t-title">'+esc(nm)+'’s tablet is connected</div><div class="t-body" style="color:var(--ink2)">It will keep working when the internet drops.</div></div>'+L.btn("Done","ob.add.done",null,{full:true});
  else if(p.code&&p.expiresAt>S.clock.t&&!kd.paired){
    body=K.qrCard({code:"OLIVE-"+p.code,title:"Scan on "+nm+"’s tablet",sub:"Or type the 6 digits on the tablet",copy:false})+
     '<div class="card hero warm" style="text-align:center;display:grid;gap:6px"><div class="t-label" style="color:inherit;opacity:.8">Pairing code</div><div class="bigcode" aria-label="Code '+p.code.split("").join(" ")+'">'+fmtCode(p.code)+'</div>'+
     '<div class="t-cap" style="color:inherit">Expires in <b class="tnum" data-countdown="'+p.expiresAt+'">'+L.fmt.mss(p.expiresAt-S.clock.t)+'</b></div></div>'+
     '<div class="t-cap">Only you can make a code. The code works once.</div>'+L.btn("Make a new code","ob.add.again",null,{full:true,kind:"tonal"});}
  else if(p.code&&!kd.paired&&p.expiresAt<=S.clock.t){
    body='<div class="hdr-center">'+K.spot("key",88)+'<div class="t-title">That code expired</div><div class="t-body" style="color:var(--ink2)">Codes last 10 minutes.</div></div>'+L.btn("Make a new code","ob.add.again",null,{full:true});}
  else{
    var msg=p.err?K.notice({tone:"bad",title:p.err==="offline"?"No network":"Could not make a code",text:errText(p.err,p)}):"";
    body=msg+'<div class="t-body" style="color:var(--ink2)">Enter your PIN to make a code for '+esc(nm)+'’s tablet.</div>'+(p.busy?K.skeleton("row",1):"")+pad(c,{total:4,filled:(p.pin||"").length,zero:true,title:"Grown-ups only"});}
  return K.top({back:true,title:"Add "+nm+"’s tablet"})+K.page(body,{tab:tabs});}});
L.act("ob.add.make",function(c){var dev=c.dev,d=dr(dev),p=d.pair;if(!p||p.busy)return;p.busy=true;p.err=null;L.queueRender();
  L.api(dev,"POST","/v1/children/"+famChild().id+"/device-pairing-codes",{pin:p.pin}).then(function(r){
    L.update(function(){var p=dr(dev).pair;p.busy=false;p.pin="";p.done=false;
      if(r.ok){p.code=r.body.code;p.expiresAt=r.body.expiresAt;p.err=null;L.after(r.body.ttlMs+500,function(){L.queueRender();},"code-expiry");}
      else p.err=r.status===0?"offline":r.code;});});});
L.act("ob.add.again",function(c){var p=dr(c.dev).pair||(dr(c.dev).pair={});p.code=null;p.pin="";p.err=null;p.done=false;});
L.act("ob.add.done",function(c){var p=dr(c.dev).pair;if(p){p.code=null;p.done=false;}L.reroot(c.dev,"home");});
L.on("device:paired",function(p){if(p.kind!=="child")return;var g=dr("g");if(g.pair)g.pair.done=true;L.toast("g",(famChild().name||"Her")+"’s tablet is connected");});

/* ---------------------------------------------------------- paired devices -- */
L.screen("ob.devices",{dev:"g",render:function(c){var f=S.family;
  var rows=f.devices.length?f.devices.map(function(x){var me=x.deviceId===S.dev.g.deviceId,online=L.online(x.dev);
    var row=K.row({ic:x.kind==="child"?"tablet":"phone",title:x.name,sub:(me?"This phone · ":"")+"Paired "+L.fmt.dayTime(x.pairedAt,L.homeTz())+" · "+(online?"Online":"Offline"),go:!me});
    return me?row:L.withAct(row,"ob.dev.ask",x.deviceId);}).join(""):K.emptyState({spot:"tablet",title:"No devices yet",sub:"Add the tablet with a pairing code."});
  return K.top({back:true,title:"Paired devices"})+K.page('<div class="card" style="padding:4px 14px">'+rows+'</div>'+L.btn("Add "+(f.child.name||"a")+"’s tablet","go","ob.addDevice",{full:true,kind:"tonal"}),{});}});
L.act("ob.dev.ask",function(c,id){var x=S.family.devices.filter(function(d){return d.deviceId===id;})[0];if(!x)return;
  L.sheet(c.dev,'<div class="hdr-center">'+K.spot("tablet",72)+'<div class="t-title">Remove '+esc(x.name)+'?</div><div class="t-body">It stops working with Olive Branch until you pair it again.</div></div>'+L.btn("Remove","ob.dev.remove",id,{full:true,kind:"danger"})+L.btn("Keep it","sheet.close",null,{full:true,kind:"ghost"}));});
L.act("ob.dev.remove",function(c,id){L.closeSheet(c.dev);L.api(c.dev,"DELETE","/v1/devices/"+id).then(function(r){L.update(function(){L.toast("g",r.ok?"Device removed":errText(r.status===0?"offline":r.code));});});});
L.on("device:revoked",function(p){var rid=p.deviceId||p.id;["g","k"].forEach(function(dev){var d=D(dev);if((rid&&d.deviceId===rid)||d.revoked){d.revoked=false;d.paired=false;d.sessionOk=false;d.locked=false;d.onboarded=false;d.deviceId=null;d.draft={};L.reroot(dev,dev==="k"||d.role==="kid"?"ob.revoked":"ob.role");if(dev==="k")d.role="kid";}});});

/* ----------------------------------------------------- sign-in / out / expiry -- */
function signin(c){var d=dr(c.dev);if(!d.sign)d.sign={pin:""};var why=c.params.why||"signedout",s=d.sign;
  var err=s.err?K.notice({tone:"bad",title:s.err==="offline"?"No network":"Could not sign in",text:errText(s.err)}):"";
  return K.top({title:why==="expired"?"Session ended":"Signed out"})+K.page('<div class="hdr-center">'+K.spot("lock",80)+'<div class="t-body" style="color:var(--ink2);max-width:34ch">'+(why==="expired"?"For safety, your session ended. Enter your PIN to carry on.":"You are signed out on this phone. Enter your PIN to sign back in.")+'</div></div>'+err+pad(c,{total:4,filled:(s.pin||"").length,zero:true,title:"Your PIN"}),{});}
L.screen("ob.signin",{dev:"g",render:signin});L.screen("ob.expired",{dev:"g",render:function(c){c.params=Object.assign({why:"expired"},c.params);return signin(c);}});
L.screen("ob.signedout",{dev:"g",render:function(c){c.params=Object.assign({why:"signedout"},c.params);return signin(c);}});
PADS["ob.expired"]=PADS["ob.signedout"]=PADS["ob.signin"];
L.act("ob.signin.go",function(c){var dev=c.dev,d=dr(dev),pin=d.sign.pin,why=c.params.why||(c.screenId==="ob.expired"?"expired":"signedout");
  L.api(dev,"POST","/v1/auth/session",{pin:pin}).then(function(r){L.update(function(){var s=dr(dev).sign;s.pin="";s.err=r.ok?null:(r.status===0?"offline":r.code);
    if(r.ok){if(why==="expired"||c.screenId==="ob.expired")L.back(dev);else L.reroot(dev,"home");}});});});
L.act("ob.signOut",function(c){var dev=c.dev;L.api(dev,"POST","/v1/auth/session/sign-out",{}).then(function(r){L.update(function(){if(r.ok||r.status===401){D(dev).sessionOk=false;L.reroot(dev,"ob.signedout");}else L.toast(dev,errText(r.status===0?"offline":r.code));});});});
L.on("auth:expired",function(p){var d=D(p.dev);if(!d.role||d.role==="kid")return;var cur=L.current(p.dev);if(cur&&cur.id==="ob.expired")return;L.go(p.dev,"ob.expired",{why:"expired"});});
});
