/* LIVE module: CONSOLE. Virtual time, network, age/palette, request log, event timeline, state inspector, reset, SCENARIO engine.
   SIMULATION: no real server. Scenarios drive the real UI through registered actions (L.tap) with on-screen captions. */
LIVE.module("console",function(L){
"use strict";
var K=window.OB,S=L.S,esc=L.esc;
var root=document.getElementById("console"),capEl=document.getElementById("caption");
var F={dev:"",method:"",status:""},openSet={},lastSync=0,syncT=null,note="";
var PALS=Object.keys(K.SEEDS);

/* ----------------------------------------------------------- static layout -- */
function btn(cc,v,text,o){o=o||{};return '<button type="button" class="pb'+(o.sm?" sm":"")+'" data-cc="'+cc+'"'+(v!=null?' data-v="'+esc(v)+'"':"")+(o.title?' title="'+esc(o.title)+'"':"")+' aria-pressed="false">'+esc(text)+'</button>';}
function build(){
  root.innerHTML=
  '<div class="cp"><h2>Virtual time <span class="csub">SIMULATION: no real server</span></h2>'+
    '<div data-spot="clocks"></div>'+
    '<div class="crow" role="group" aria-label="Clock controls">'+btn("pp",null,"Pause")+btn("speed",1,"1x")+btn("speed",60,"1 min per second")+btn("speed",600,"10 min per second")+btn("speed",3600,"1 hour per second")+'</div>'+
    '<div class="crow" role="group" aria-label="Jump">'+btn("jump","bedtime","Next bedtime")+btn("jump","morning","Next morning")+btn("jump","exchange","Next exchange")+btn("jump","m10","+10 min")+btn("jump","h1","+1 hour")+btn("jump","d1","+1 day")+'</div>'+
    '<div class="csub" data-spot="next"></div></div>'+
  '<div class="cp"><h2>Devices and network</h2>'+
    '<div class="crow">'+btn("net","g","Guardian phone: online")+btn("net","k","Child tablet: online")+'</div>'+
    '<label class="rng">Server latency <span data-spot="lat"></span><input type="range" min="0" max="3000" step="50" data-cc="lat" aria-label="Server latency in milliseconds"></label>'+
    '<label class="rng">Next request fails with<select data-cc="failnext" aria-label="Fail next request"><option value="">nothing</option><option value="503">503 unavailable</option><option value="429">429 rate limited</option><option value="500">500 error</option></select></label>'+
    '<div class="crow">'+btn("expire",null,"Expire guardian session",{sm:true})+btn("revoke",null,"Revoke child device",{sm:true})+'</div><div class="csub" data-spot="sess"></div></div>'+
  '<div class="cp"><h2>Look and age</h2>'+
    '<label class="rng">Child age <span data-spot="ageL"></span><input type="range" min="3" max="17" step="1" data-cc="age" aria-label="Child age"></label>'+
    '<div class="crow"><label class="rng" style="grid-auto-flow:column;align-items:center;gap:8px">Palette <select data-cc="palette" aria-label="Palette">'+PALS.map(function(p){return '<option value="'+p+'">'+esc(K.SEEDS[p].n)+'</option>';}).join("")+'</select></label>'+btn("mode","light","Light")+btn("mode","dark","Dark")+'</div>'+
    '<label class="crow" style="gap:8px;font-size:.86rem;font-weight:700"><input type="checkbox" data-cc="childcol"> Tablet uses the child’s own colour</label></div>'+
  '<div class="cp"><h2>Session</h2>'+
    '<label class="crow" style="gap:8px;font-size:.86rem;font-weight:700"><input type="checkbox" data-cc="persist"> Remember between reloads</label>'+
    '<div class="crow">'+btn("reset",null,"Reset everything",{title:"Clears the state and reloads"})+'</div>'+
    '<div class="csub" data-spot="mods"></div><div data-spot="errs"></div></div>'+
  '<div class="cp wide"><h2>Scenarios <span class="csub">scripted walkthroughs that tap the real UI</span></h2><div class="crow" data-spot="scen"></div><div class="csub" data-spot="scendesc"></div></div>'+
  '<div class="cp wide"><h2>Server request log <span class="csub">SIMULATION: no real server</span></h2>'+
    '<div class="crow"><label class="crow" style="gap:6px;font-size:.84rem">Device <select data-cc="fdev" aria-label="Filter by device"><option value="">all</option><option value="g">guardian</option><option value="k">child</option></select></label>'+
    '<label class="crow" style="gap:6px;font-size:.84rem">Method <select data-cc="fmethod" aria-label="Filter by method"><option value="">all</option><option>GET</option><option>POST</option><option>PUT</option><option>DELETE</option></select></label>'+
    '<label class="crow" style="gap:6px;font-size:.84rem">Status <select data-cc="fstatus" aria-label="Filter by status"><option value="">all</option><option value="2">2xx ok</option><option value="4">4xx refused</option><option value="5">5xx server</option><option value="0">0 offline</option></select></label><span class="csub" data-spot="logn"></span></div>'+
    '<div class="logbox" data-spot="log" tabindex="0" role="region" aria-label="Request log"></div></div>'+
  '<div class="cp"><h2>Event timeline</h2><div class="tl2" data-spot="events" tabindex="0" role="region" aria-label="Event timeline"></div></div>'+
  '<div class="cp"><h2>State inspector</h2><details data-insp><summary class="pb sm" style="display:inline-flex;align-items:center;list-style:none">Show state</summary><div class="insp" data-spot="insp"></div></details></div>';
}
build();
function spot(n){return root.querySelector('[data-spot="'+n+'"]');}
function put(n,html){var e=spot(n);if(e&&e.getAttribute("data-h")!==html){var a=document.activeElement,k=a&&e.contains(a)?a.getAttribute("data-fk"):null;e.innerHTML=html;e.setAttribute("data-h",html);if(k){var t=e.querySelector('[data-fk="'+k+'"]');if(t)t.focus();}}}

/* ------------------------------------------------------------------- sync -- */
function pressed(cc,v){
  if(cc==="pp")return S.clock.paused;if(cc==="speed")return !S.clock.paused&&S.clock.speed===+v;
  if(cc==="net")return !L.online(v);if(cc==="mode")return S.ui.mode===v;return false;}
function tree(o,path,depth){
  if(o===null||typeof o!=="object")return '<span>'+esc(typeof o==="string"?'"'+o+'"':String(o))+'</span>';
  var keys=Object.keys(o),isA=Array.isArray(o),h="",n=0;
  keys.forEach(function(k){if(n++>=40)return;var v=o[k],p=path+"."+k;
    if(v!==null&&typeof v==="object"){var c=Object.keys(v).length;h+='<details data-p="'+esc(p)+'"'+(openSet[p]?" open":"")+'><summary><span class="k">'+esc(k)+'</span> '+(Array.isArray(v)?"[ "+c+" ]":"{ "+c+" }")+'</summary>'+(openSet[p]&&depth<8?tree(v,p,depth+1):"")+'</details>';}
    else h+='<div style="margin-left:14px"><span class="k">'+esc(k)+':</span> '+tree(v,p,depth)+'</div>';});
  if(keys.length>40)h+='<div class="k" style="margin-left:14px">… '+(keys.length-40)+' more</div>';
  return h;}
function sync(){
  lastSync=Date.now();
  var tzH=L.homeTz(),me=L.me("g"),tzG=(me&&me.tz)||tzH,nm=S.family.child.name||"Her";
  put("clocks",'<div class="clock" data-clock="dayTime|'+tzH+'">'+L.fmt.dayTime(S.clock.t,tzH)+'</div><div class="csub">'+esc(nm)+', her time ('+esc(L.tzName(tzH))+') · your time <b data-clock="dayTime|'+tzG+'">'+L.fmt.dayTime(S.clock.t,tzG)+'</b> ('+esc(L.tzName(tzG))+') · '+(S.clock.paused?"paused":"running at "+S.clock.speed+"x")+'</div>');
  if(S.family.created){var f=function(k){var t=L.nextAt(k);return t===Infinity?"—":L.fmt.dayTime(t,tzH);};put("next","Next bedtime "+f("bedtime")+" · next morning "+f("morning")+" · next exchange "+f("exchange")+(note?' · <b>'+esc(note)+'</b>':""));}
  else put("next","Jumps unlock once a family exists."+(note?' <b>'+esc(note)+'</b>':""));
  Array.prototype.forEach.call(root.querySelectorAll("[data-cc]"),function(b){var cc=b.getAttribute("data-cc"),v=b.getAttribute("data-v");
    if(b.tagName==="BUTTON"){if(cc==="pp")b.textContent=S.clock.paused?"Play":"Pause";
      if(cc==="net")b.textContent=(v==="g"?"Guardian phone":"Child tablet")+": "+(L.online(v)?"online":"OFFLINE");
      b.setAttribute("aria-pressed",String(pressed(cc,v)));b.classList.toggle("on",!!pressed(cc,v));}});
  var lat=root.querySelector('[data-cc="lat"]'),age=root.querySelector('[data-cc="age"]'),pal=root.querySelector('[data-cc="palette"]'),fn=root.querySelector('[data-cc="failnext"]'),per=root.querySelector('[data-cc="persist"]'),cc2=root.querySelector('[data-cc="childcol"]');
  if(document.activeElement!==lat)lat.value=S.net.latencyMs;if(document.activeElement!==age)age.value=S.family.child.age==null?10:S.family.child.age;
  pal.value=S.ui.palette;fn.value=S.net.failNext.g||S.net.failNext.k||"";per.checked=!!S.ui.persist;cc2.checked=S.ui.childColour!==false;
  put("lat",S.net.latencyMs+" ms");
  var a=S.family.child.age==null?10:S.family.child.age;put("ageL",a+" · band "+L.band()+" ("+{t34:"3 to 4",t57:"5 to 7",t812:"8 to 12",t1317:"13 to 17"}[L.band()]+")");
  var ss=S.server.sessions.g;put("sess","Guardian session: "+(S.dev.g.sessionOk?(ss?"signed in, ends "+L.fmt.dayTime(ss.expiresAt,tzH):"signed in"):"none")+" · Child device: "+(S.dev.k.paired?"paired":"not paired"));
  put("mods","Modules loaded: "+(L.modules||[]).join(", "));
  put("errs",L.errors.length?L.errors.slice(-6).map(function(e){return '<div class="errbox">'+esc(e.where)+": "+esc(e.msg)+(e.n>1?" (x"+e.n+")":"")+'</div>';}).join(""):"");
  /* log */
  var rows=S.server.log.filter(function(e){return (!F.dev||e.dev===F.dev)&&(!F.method||e.method===F.method)&&(!F.status||String(e.status).charAt(0)===F.status);}).slice(-80).reverse();
  put("logn",rows.length+" shown of "+S.server.log.length);
  put("log",'<table><thead><tr><th>virtual time</th><th>dev</th><th>method</th><th>path</th><th>status</th><th>ms</th><th>code</th><th>id</th></tr></thead><tbody>'+rows.map(function(e){return '<tr><td>'+L.fmt.dayTime(e.t,tzH)+'</td><td>'+e.dev+'</td><td>'+e.method+'</td><td>'+esc(e.path)+'</td><td class="s'+String(e.status).charAt(0)+'">'+e.status+'</td><td>'+e.ms+'</td><td>'+esc(e.code||"")+'</td><td>'+e.reqId+'</td></tr>';}).join("")+'</tbody></table>');
  put("events",S.server.events.slice(-60).reverse().map(function(e){return '<div><span class="tt">'+L.fmt.dayTime(e.t,tzH)+'</span><b>'+esc(e.type)+'</b><span>'+esc(e.payload==null?"":JSON.stringify(e.payload).slice(0,90))+'</span></div>';}).join("")||'<div class="csub">No events yet.</div>');
  var d=root.querySelector("[data-insp]");if(d&&d.open){var snap=Object.assign({},S);snap=JSON.parse(JSON.stringify(S));put("insp",tree(snap,"S",0));}
  /* scenario list */
  put("scen",Object.keys(SC).map(function(id){return '<button type="button" class="pb'+(run&&run.id===id?" on":"")+'" data-cc="scen" data-v="'+id+'" title="'+esc(SC[id].desc)+'" data-fk="sc-'+id+'">'+esc(SC[id].title)+'</button>';}).join(""));
  put("scendesc",run?"Running: "+esc(SC[run.id].title):"Pick one. The captions appear at the bottom of the page.");
}
function schedSync(){var d=Date.now()-lastSync;if(d>=300)sync();else if(!syncT)syncT=setTimeout(function(){syncT=null;sync();},300-d);}
L.afterRender.push(schedSync);
setInterval(function(){sync();},1000);

/* --------------------------------------------------------------- commands -- */
var CMD={
  pp:function(){L.setClock({paused:!S.clock.paused});},
  speed:function(v){L.setClock({speed:+v,paused:false});},
  jump:function(v){note="";
    if(v==="bedtime"||v==="morning"||v==="exchange"){if(!L.jumpToNext(v))note="Create a family first";}
    else L.jumpTo(S.clock.t+({m10:600000,h1:3600000,d1:86400000}[v]));sync();},
  net:function(v){L.setOnline(v,!L.online(v));},
  expire:function(){var ss=S.server.sessions.g;if(!ss){note="Guardian is not signed in";sync();return;}ss.expiresAt=S.clock.t-1;L.api("g","GET","/v1/me");},
  revoke:function(){var id=S.dev.k.deviceId;if(!id){note="Child device is not paired";sync();return;}S.server.revoked[id]=true;S.family.devices=S.family.devices.filter(function(x){return x.deviceId!==id;});L.emit("device:revoked",{deviceId:id});},
  mode:function(v){L.update(function(S){S.ui.mode=v;});},
  reset:function(){L.reset();}
};
document.addEventListener("click",function(ev){var b=ev.target.closest&&ev.target.closest("[data-cc]");if(!b||b.tagName!=="BUTTON")return;
  var cc=b.getAttribute("data-cc"),v=b.getAttribute("data-v");
  if(cc==="scen"){startScenario(v);return;}
  if(CMD[cc]){CMD[cc](v);L.queueRender();sync();}});
document.addEventListener("input",function(ev){var e=ev.target,cc=e.getAttribute&&e.getAttribute("data-cc");if(!cc)return;
  if(cc==="lat"){S.net.latencyMs=+e.value;put("lat",S.net.latencyMs+" ms");}
  if(cc==="age"){L.setAge(+e.value);}});
document.addEventListener("change",function(ev){var e=ev.target,cc=e.getAttribute&&e.getAttribute("data-cc");if(!cc)return;
  if(cc==="failnext"){S.net.failNext.g=e.value||null;S.net.failNext.k=e.value||null;}
  if(cc==="palette")L.update(function(S){S.ui.palette=e.value;});
  if(cc==="persist")L.setPersist(e.checked);
  if(cc==="childcol")L.update(function(S){S.ui.childColour=e.checked;});
  if(cc==="fdev"){F.dev=e.value;sync();}if(cc==="fmethod"){F.method=e.value;sync();}if(cc==="fstatus"){F.status=e.value;sync();}});
document.addEventListener("toggle",function(ev){var d=ev.target;if(d&&d.getAttribute&&d.getAttribute("data-p")){openSet[d.getAttribute("data-p")]=d.open;sync();}else if(d&&d.hasAttribute&&d.hasAttribute("data-insp"))sync();},true);

/* ================================================================ SCENARIOS == */
var SC={},run=null;
function sleep(ms){return new Promise(function(r){setTimeout(r,ms);});}
function until(fn,ms){return new Promise(function(res){var t0=Date.now();(function poll(){var ok=false;try{ok=fn();}catch(e){}if(ok||Date.now()-t0>(ms||8000))res(ok);else setTimeout(poll,100);})();});}
/* DSL */
function tap(dev,name,arg,gap){return {t:"tap",dev:dev,name:name,arg:arg,gap:gap};}
function type(dev,path,val){return {t:"type",dev:dev,path:path,val:val};}
function call(fn,gap){return {t:"call",fn:fn,gap:gap};}
function wait(ms){return {t:"wait",ms:ms};}
function waitFor(fn,ms){return {t:"until",fn:fn,ms:ms};}
function padSeq(dev,digits){return String(digits).split("").map(function(d){return tap(dev,"ob.pad",d,260);});}
function step(cap,dev,acts,o){o=o||{};return {cap:cap,dev:dev,acts:acts||[],hold:o.hold};}
function go(dev,screen){return tap(dev,"go",screen);}
function lastCode(){var p=S.server.pairing;return p.length?p[p.length-1].code:"";}
function missingNote(m){return m.length?"Not available yet: "+m.join(", "):"";}

/* Build a ready family quickly (through the real server routes) for scenarios that start after onboarding. */
function fastFamily(){
  if(S.family.created&&S.dev.k.paired)return Promise.resolve();
  S.net.g.online=true;S.net.k.online=true;
  var g=S.dev.g,k=S.dev.k;g.role="mom";k.role="kid";
  return L.api("g","POST","/v1/families",{guardian:{role:"mom",name:"Jess",label:"Mom",tz:"America/Chicago"},child:{name:"Ivy",age:9},pin:"2468",homeTz:"America/Chicago"}).then(function(){
    g.onboarded=true;return L.api("g","POST","/v1/children/"+S.family.child.id+"/device-pairing-codes",{pin:"2468"});}).then(function(r){
    return L.api("k","POST","/v1/device-pairing/redeem",{code:r.body.code,role:"child"});}).then(function(){
    k.onboarded=true;k.locked=true;
    return L.api("k","PUT","/v1/children/"+S.family.child.id+"/profile",{name:"Ivy",age:9,color:"warm",birthday:{m:3,d:14},nicknames:{mom:"Mama",dad:"Dada"}});}).then(function(){
    return (L.fastExtras?Promise.resolve(L.fastExtras()):Promise.resolve());}).then(function(){L.reroot("g","home");L.reroot("k","home");});
}
L.fastFamily=fastFamily;

/* the player */
function caption(){
  if(!run){capEl.hidden=true;capEl.innerHTML="";return;}
  var sc=SC[run.id],st=sc.steps[run.i]||{cap:"Getting a ready family set up through the real server routes…",dev:null},last=run.i>=sc.steps.length-1;
  capEl.hidden=false;
  var h='<div class="cs">SIMULATION: no real server · '+esc(sc.title)+' · step '+(run.i+1)+' of '+sc.steps.length+(st.dev?' · '+(st.dev==="g"?"guardian phone":st.dev==="k"?"child tablet":"both"):"")+'</div><p>'+esc(st.cap)+'</p>'+(run.miss?'<div class="errbox" role="status">'+esc(run.miss)+'</div>':"")+
    '<div class="crow"><button type="button" class="pb sm pri" data-sc="next"'+(last&&!run.busy?' data-last="1"':"")+'>'+(last&&!run.busy?"Finish":"Next")+'</button><button type="button" class="pb sm" data-sc="auto" aria-pressed="'+run.auto+'">'+(run.auto?"Pause":"Auto-play")+'</button><button type="button" class="pb sm" data-sc="stop">Stop</button>'+(run.busy?'<span class="cs">working…</span>':"")+'</div>';
  if(capEl.getAttribute("data-h")!==h){var f=document.activeElement&&capEl.contains(document.activeElement)?document.activeElement.getAttribute("data-sc"):null;capEl.innerHTML=h;capEl.setAttribute("data-h",h);if(f){var t=capEl.querySelector('[data-sc="'+f+'"]');if(t)t.focus();}}
}
function execAct(a,run0){
  if(a.t==="tap"){if(a.name==="go"&&!L.hasScreen(a.arg,a.dev)){run0.m.push("screen "+a.arg);return;}if(!L.hasAct(a.name)&&!document.querySelector('[data-act="'+a.name+'"]')){run0.m.push(a.name+(a.arg!=null?" "+a.arg:""));return;}var r=L.tap(a.dev,a.name,a.arg);if(r.via==="missing")run0.m.push(a.name+(a.arg!=null?" "+a.arg:""));return;}
  if(a.t==="type"){L.type(a.dev,a.path,a.val);return;}
  if(a.t==="call")return Promise.resolve(a.fn(run0));
  if(a.t==="until")return until(a.fn,a.ms);
  if(a.t==="wait")return sleep(a.ms);}
function enter(i){
  if(!run)return;var r=run,sc=SC[r.id],st=sc.steps[i];r.i=i;r.busy=true;r.miss="";r.m=[];caption();
  var p=Promise.resolve();
  st.acts.forEach(function(a){p=p.then(function(){if(run!==r)return;return execAct(a,r);}).then(function(){return a.t==="wait"||a.t==="until"?null:sleep(a.gap==null?380:a.gap);});});
  p.then(function(){if(run!==r)return;r.busy=false;r.miss=missingNote(r.m);caption();
    if(r.pendingNext){r.pendingNext=false;advance();}else if(r.auto){clearTimeout(r.t);r.t=setTimeout(function(){if(run===r)advance();},Math.max(1500,st.cap.length*38));}
  },function(e){L.logErr("scenario step",e);if(run===r){r.busy=false;r.miss="Step failed: "+e;caption();}});
}
function advance(){if(!run)return;if(run.busy){run.pendingNext=true;return;}var sc=SC[run.id];if(run.i>=sc.steps.length-1){stopScenario();return;}enter(run.i+1);}
function stopScenario(){if(run){clearTimeout(run.t);}run=null;caption();sync();}
function startScenario(id){
  var sc=SC[id];if(!sc)return;
  if(run)stopScenario();
  var pristine=!S.family.created&&!S.dev.g.role&&!S.dev.k.role;
  if(sc.fresh&&!pristine){L.reset({scenario:id});return;}
  run={id:id,i:-1,auto:false,busy:false,m:[],miss:""};
  if(!sc.fresh&&!(S.family.created&&S.dev.k.paired)){run.busy=true;caption();fastFamily().then(function(){if(run&&run.id===id){run.busy=false;enter(0);}});return;}
  enter(0);sync();}
document.addEventListener("click",function(ev){var b=ev.target.closest&&ev.target.closest("[data-sc]");if(!b)return;var a=b.getAttribute("data-sc");
  if(a==="next")advance();if(a==="stop")stopScenario();
  if(a==="auto"&&run){run.auto=!run.auto;if(run.auto&&!run.busy)advance();caption();}});
document.addEventListener("keydown",function(ev){if(ev.key==="Escape"&&run&&!document.querySelector(".ob .sheet:focus-within"))return;});
L.onBoot(function(){var id=null;try{id=sessionStorage.getItem("olive-live-autostart");sessionStorage.removeItem("olive-live-autostart");}catch(e){}if(id&&SC[id])setTimeout(function(){startScenario(id);},400);});

/* ---- scenario definitions ---------------------------------------------------- */
L.scenarios=SC;
L.scenario=function(id,def){SC[id]=def;sync();};  /* other modules may add their own */
var DAD="Marcus";
SC.golden={title:"Golden path",fresh:true,desc:"From a blank state: onboard both devices, pair the tablet, bank a message, jump to bedtime, watch it arrive and play, see 'watched' on the guardian phone.",steps:[
  step("Both devices start blank. The first question on each is role first: who is using this device?","both",[wait(900)]),
  step("On Jess’s phone, pick Mom.","g",[tap("g","ob.pickRole","mom")]),
  step("She confirms her name and label.","g",[type("g","dev.g.draft.gname","Jess"),tap("g","ob.g.label","Mom"),go("g","ob.g.child")]),
  step("Next, the child: name and age. The age locks once setup finishes.","g",[type("g","dev.g.draft.cname","Ivy"),tap("g","ob.g.pickAge","9"),go("g","ob.g.zone")]),
  step("Home time zone, so the app can show “hers” and “yours” side by side.","g",[tap("g","ob.g.zone","America/Chicago"),go("g","ob.g.pin")]),
  step("A four-digit PIN, typed twice. It guards pairing codes.","g",padSeq("g","2468").concat([wait(300)],padSeq("g","2468"))),
  step("Connect this device is the last step, because it needs the internet. This creates the family on the (simulated) server.","g",[tap("g","ob.g.create"),waitFor(function(){return S.family.created;},9000)]),
  step("Now the tablet. A grown-up makes a pairing code; the PIN is required and a child can never make one.","g",[go("g","ob.addDevice")].concat(padSeq("g","2468"),[waitFor(function(){return !!lastCode();},6000)])),
  step("On Ivy’s tablet the same question comes first. She picks Kid.","k",[tap("k","ob.pickRole","kid")]),
  step("She types her name.","k",[type("k","dev.k.draft.name","Ivy"),go("k","ob.kid.age")]),
  step("She picks her age, then locks it. It cannot be changed from the tablet.","k",[tap("k","ob.kid.pickAge","9"),tap("k","ob.kid.askLock"),wait(700),tap("k","ob.kid.lockAge"),go("k","ob.kid.color")]),
  step("A colour and a birthday.","k",[tap("k","ob.kid.pickColor","warm"),go("k","ob.kid.birthday"),tap("k","ob.kid.setBM","3"),tap("k","ob.kid.setBD","14"),go("k","ob.kid.names")]),
  step("What does she call her grown-ups? Like contacts. This belongs to her; a guardian can never overwrite it.","k",[type("k","dev.k.draft.nick.mom","Mama"),type("k","dev.k.draft.nick.dad","Dada")]),
  step("Connect this device is LAST. Her answers are already saved on the tablet. She types the 6-digit code from the phone.","k",[go("k","ob.kid.connect"),call(function(){var p=Promise.resolve();lastCode().split("").forEach(function(d){p=p.then(function(){L.tap("k","ob.pad",d);return sleep(260);});});return p;}),waitFor(function(){return S.dev.k.paired;},9000)]),
  step("Paired. Her draft answers upload now, and the tablet is locked in to the app.","k",[waitFor(function(){return S.dev.k.draft&&S.dev.k.draft.uploaded;},9000),tap("k","ob.kid.finish")]),
  step("Back on the guardian phone, Home now shows one sentence about her state and the two clocks.","g",[tap("g","ob.add.done")])
]};
/* the remaining scenarios are filled in by SCENARIOS_LATE below once other modules' action names are known */
/* helpers shared by the later scenarios */
function intents(){try{var st=S.msg;if(st&&Array.isArray(st.intents))return st.intents;var m=L.msg&&L.msg.m&&L.msg.m();if(Array.isArray(m))return m;if(m&&Array.isArray(m.intents))return m.intents;}catch(e){}return [];}
function msgCount(){return intents().length;}
function newestMsg(){var a=intents();return a[a.length-1]||null;}
function bankStep(rule){var n0=0;return [call(function(){n0=msgCount();}),tap("g","msg.gStart"),tap("g","msg.gSample"),tap("g","msg.gBankIt"),
  waitFor(function(){return msgCount()>n0;},3500),
  call(function(){if(msgCount()<=n0)return L.run("g","msg.bank",JSON.stringify({title:"Goodnight, Ivy",durSec:101,rule:rule||"bedtime"}));}),
  waitFor(function(){return msgCount()>n0;},4000)];}
function openMsg(){var m=newestMsg();return m?String(m.id):null;}
/* ---- Golden path, second half: message banked -> bedtime -> arrival -> played -> watched ---- */
SC.golden.steps=SC.golden.steps.concat([
  step("Jess banks a goodnight message. Banking means: recorded now, delivered later, when Ivy can actually receive it.","g",bankStep("bedtime")),
  step("Nothing reaches the tablet yet. The delivery worker waits for bedtime on Ivy\u2019s side of the clock. Let us jump the virtual clock to her bedtime.","g",[call(function(){L.setClock({speed:1,paused:false});L.jumpToNext("bedtime");}),wait(700),tap("g","msg.worker"),tap("k","msg.kidSync")]),
  step("It arrives on the tablet as a picture, not a number. She opens it.","k",[tap("k","msg.kOpenNewest")]),
  step("She watches it all the way through. Only a full play counts as \u201cwatched\u201d.","k",[call(function(){var m=newestMsg();return m?L.run("k","msg.playTo","end"):null;}),wait(1200)]),
  step("Back on the guardian phone: Watched. Delivered, opened and watched are three different facts.","g",[tap("g","go","msg.gQueue")])
]);
SC.offline={title:"Offline night",fresh:false,desc:"The tablet loses its network at night. The message is safe on the server and arrives when the tablet is back.",steps:[
  step("A ready family. Jess banks a message for tonight.","g",bankStep("bedtime")),
  step("Ivy\u2019s tablet goes offline (flat battery, bad wifi, a road trip). The guardian phone stays online.","k",[call(function(){L.setOnline("k",false);})]),
  step("Bedtime arrives. The server tries to deliver; the tablet cannot receive it. The guardian sees an honest status, not a false \u201cdelivered\u201d.","g",[call(function(){L.jumpToNext("bedtime");}),wait(600),tap("g","msg.worker"),tap("g","go","msg.gQueue")]),
  step("On the tablet the offline state is a picture, with no error code and no counts.","k",[tap("k","go","msg.kOffline")]),
  step("The network returns. The tablet checks in and the message arrives.","k",[call(function(){L.setOnline("k",true);}),wait(500),tap("k","msg.kidSync"),wait(900),tap("k","go","msg.kMessages")]),
  step("Nothing was lost and nothing was sent twice.","g",[tap("g","go","msg.gQueue")])
]};
SC.birthday={title:"Birthday band change",fresh:false,desc:"Ivy turns 13 at local midnight. The age increments and the child home changes shape.",steps:[
  step("Ivy is 12. The tablet shows the 8 to 12 layout.","k",[call(function(){var p=L.parts(S.clock.t+86400000,L.homeTz());S.family.child.birthday={m:p.m,d:p.d};L.setAge(12);L.reroot("k","home");})]),
  step("Her birthday is tomorrow. Let us jump the virtual clock to local midnight.","both",[call(function(){L.jumpToNext("birthday");})]),
  step("She is 13. The age band moved to 13 to 17, and the home re-lays itself out on its own. No badge, no reward, no confetti count (prohibitions P1 to P3).","k",[call(function(){L.reroot("k","home");}),wait(600)]),
  step("The console slider shows the derived band. Drag it to see every band live.","both",[wait(400)])
]};
SC.call={title:"Call knock",fresh:false,desc:"Ivy knocks to call a grown-up; the guardian phone rings and answers. A child can never start a call the other way round.",steps:[
  step("Ivy taps the picture of Mom to knock. A knock is not a call: it asks, it does not ring.","k",[tap("k","call.knock","mom")]),
  step("On Jess\u2019s phone the knock shows up and it rings.","g",[wait(900)]),
  step("Jess answers.","g",[tap("g","call.answer")]),
  step("They talk. A child tablet has no way to place a call at the guardian; guardians call, children knock.","both",[wait(1500)]),
  step("Jess ends the call.","g",[tap("g","call.end")])
]};
function tzAt(h,m){var tz=L.homeTz(),p=L.parts(S.clock.t,tz),t=L.zoned(p.y,p.m,p.d,h,m,tz);return t<=S.clock.t?L.zoned(p.y,p.m,p.d+1,h,m,tz):t;}
function playNow(){try{return L.guardian.playState().state;}catch(e){return "unknown";}}
SC.play={title:"Play window",fresh:false,desc:"A guardian sets a play window; the tablet's games wind down and rest on schedule, then open again in the morning.",steps:[
  step("Jess opens Play window and daily time. Times are in Ivy\u2019s time zone, not hers.","g",[go("g","g-play")]),
  step("She turns the window on and picks when games open and rest, with a gentle wind-down.","g",[call(function(){if(S.grd&&S.grd.play&&!S.grd.play.on)L.tap("g","gPlayOn");}),type("g","grd.play.open","07:30"),type("g","grd.play.rest","19:30"),tap("g","gWind","15")]),
  step("Saved. A longer window would tell the other guardian; a shorter one never does.","g",[tap("g","gPlaySave")]),
  step("On the tablet the games are open right now. Nothing counts down, and there is no timer on screen.","k",[call(function(){L.reroot("k","home");})]),
  step("Jump to the start of the wind-down (15 minutes before rest). A game in progress can finish; new ones wait.","both",[call(function(){L.jumpTo(tzAt(19,15));}),wait(500)]),
  step("Rest time. The games tile goes quiet, with a moon, and a plain picture tells her why.","k",[call(function(){L.jumpTo(tzAt(19,30)+1000);L.reroot("k","home");}),wait(500)]),
  step("Next morning, at 7:30, the window opens again by itself.","both",[call(function(){L.jumpTo(tzAt(7,31));}),wait(500)])
]};
SC.family={title:"Family change released",fresh:false,desc:"A guardian saves a change to Ivy's people but holds it until she has been told; releasing it updates her tablet.",steps:[
  step("Jess opens Family structure: Ivy\u2019s people and homes.","g",[go("g","g-family"),wait(400)]),
  step("She adds Grandma Rose and chooses to HOLD the change until she has told Ivy. Nothing reaches the tablet yet.","g",[call(function(){var g=S.grd;if(!g||!g.fam)return;var d=JSON.parse(JSON.stringify(g.fam));d.people.push({id:"p_rose",name:"Grandma Rose",role:"Grandma",home:"",away:false,reach:{messages:true,calls:false,story:true}});
    return L.api("g","POST","/v1/family-changes",{draft:d,baseV:g.famV||0,mode:"hold",note:"Grandma Rose is joining for weekly stories."});}),waitFor(function(){return S.grd&&S.grd.hist&&S.grd.hist.some(function(e){return e.kind==="family";});},3000)]),
  step("The history shows the change as held. Marcus is told the same day. Nothing has changed on Ivy\u2019s side.","g",[go("g","g-history")]),
  step("Ivy\u2019s tablet is unchanged: no badge, no surprise.","k",[call(function(){L.reroot("k","home");})]),
  step("Jess has had the talk with Ivy. She releases the change.","g",[call(function(){var h=S.grd&&S.grd.hist||[];var e=h.filter(function(x){return x.kind==="family";}).pop();if(e)return L.run("g","gRelease",e.id);})]),
  step("On the tablet, My people now includes Grandma Rose, as a picture, in her own words.","k",[tap("k","kid.openMyPeople"),wait(500)])
]};
SC.deletion={title:"Account deletion hold",fresh:false,desc:"Deleting an account pauses sign-in and starts a 6 to 12 month recovery window. Ivy's tablet keeps working.",steps:[
  step("Jess opens Delete my account. The screen says what will happen before anything does.","g",[go("g","g-delete")]),
  step("She taps Delete and must enter her PIN.","g",[tap("g","gDelAsk")].concat(padKeys("g","gPinKey","2468"))),
  step("A last confirmation. Deleting does not erase: it starts the recovery window.","g",[tap("g","gDelGo"),wait(900)]),
  step("Her sign-in is paused. Ivy\u2019s tablet keeps working, and the shared log stays.","k",[call(function(){L.reroot("k","home");return L.api("k","GET","/v1/me");})]),
  step("Seven months later the guaranteed part of the window has ended but recovery is still possible.","g",[call(function(){L.jumpTo(S.clock.t+210*86400000);})]),
  step("She enters her PIN on the hold screen and everything comes back.","g",padKeys("g","gRecKey","2468").concat([waitFor(function(){return S.dev.g.sessionOk;},4000)]))
]};
function padKeys(dev,act,digits){return String(digits).split("").map(function(d){return tap(dev,act,d,300);});}
if(window.LIVE_SCENARIOS_LATE)window.LIVE_SCENARIOS_LATE(L,{SC:SC,step:step,tap:tap,type:type,call:call,wait:wait,waitFor:waitFor,go:go,padSeq:padSeq,sleep:sleep,until:until});

sync();
});
