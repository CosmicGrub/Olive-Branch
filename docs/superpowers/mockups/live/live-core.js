/* Olive Branch LIVE prototype: CORE.
   SIMULATION: no real server. State store, renderer, navigation, actions, tiles, labels, virtual clock,
   scheduler, event bus, simulated server (routes + api()), module loader.  See LIVE-API.md. */
(function(){
"use strict";
var K=window.OB||{};
var L=window.LIVE={version:"1.0"};
var KEY="olive-live-v1",PREF="olive-live-pref";
var mods=[],booted=false,bootHooks=[];
var S=null;
L.errors=[];

/* ------------------------------------------------------------- utilities -- */
function esc(s){return String(s==null?"":s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");}
L.esc=esc;
function logErr(where,e){var msg=String(e&&e.message||e),last=L.errors[L.errors.length-1];
  if(last&&last.where===where&&last.msg===msg){last.n=(last.n||1)+1;last.t=Date.now();}
  else{L.errors.push({where:where,msg:msg,t:Date.now(),n:1});if(L.errors.length>60)L.errors.shift();}
  try{if(!last||last.where!==where||last.msg!==msg)console.error("[LIVE] "+where,e);}catch(_){}} /* never schedules a render: a throwing screen must not loop */
L.logErr=logErr;
L.safe=function(where,fn){try{return fn();}catch(e){logErr(where,e);}};
function clone(o){return o==null?o:JSON.parse(JSON.stringify(o));}
L.clone=clone;
function merge(base,over){ // deep merge plain objects, arrays replaced
  if(over==null)return base;
  if(typeof base!=="object"||base===null||Array.isArray(base)||typeof over!=="object"||Array.isArray(over))return over;
  var out={},k;for(k in base)out[k]=base[k];
  for(k in over)out[k]=(k in base)?merge(base[k],over[k]):over[k];
  return out;}
L.get=function(path,obj){var o=obj||S,p=String(path).split(".");for(var i=0;i<p.length;i++){if(o==null)return undefined;o=o[p[i]];}return o;};
L.set=function(path,val,obj){var o=obj||S,p=String(path).split(".");for(var i=0;i<p.length-1;i++){if(o[p[i]]==null||typeof o[p[i]]!=="object")o[p[i]]={};o=o[p[i]];}o[p[p.length-1]]=val;return val;};
var idSeq=0;
L.id=function(p){idSeq++;return (p||"id")+"_"+Date.now().toString(36).slice(-4)+idSeq.toString(36);};

/* --------------------------------------------------------------- defaults -- */
function mkDev(dev){return {role:null,stack:[{id:"ob.role",params:{}}],paired:false,onboarded:false,deviceId:null,sessionOk:false,battery:dev==="g"?82:64,locked:false,draft:{}};}
function defaults(){
  return {
    clock:{t:Date.UTC(2026,10,9,23,30,0),speed:1,paused:false}, /* Mon 9 Nov 2026, 17:30 in Chicago */
    net:{g:{online:true},k:{online:true},latencyMs:350,failNext:{g:null,k:null},rate:{limit:60,windowMs:10000}},
    server:{log:[],events:[],seq:0,pairing:[],sessions:{},pinFails:0,pinLockUntil:0,redeemFails:{g:0,k:0,lockUntil:{g:0,k:0}},revoked:{}},
    family:{id:null,created:false,homeTz:"America/Chicago",guardians:[],
      child:{id:"child_1",name:"",age:null,ageLocked:false,color:null,birthday:null,nicknames:{}},
      schedule:{bedtime:"19:30",morning:"07:00",exchange:{dow:5,time:"17:00"}},
      custody:{with:"mom",since:0},pin:null,devices:[]},
    dev:{g:mkDev("g"),k:mkDev("k")},
    ui:{palette:"olive",mode:"light",form:{g:"phone",k:"tablet"},view:"both",persist:false,g:{sheet:null,toast:null},k:{sheet:null,toast:null}}
  };}
L.defaults=defaults;
var stateFactories={};
/* L.state('msg', function(){return {...}}): default for a module namespace, applied if S[ns] is missing (also after a restore). */
L.state=function(ns,factory){stateFactories[ns]=factory;if(S&&S[ns]==null)S[ns]=typeof factory==="function"?factory():clone(factory);return S&&S[ns];};

/* ------------------------------------------------------- persistence/pref -- */
function readPref(){try{return JSON.parse(localStorage.getItem(PREF)||"{}")||{};}catch(e){return {};}}
function writePref(p){try{localStorage.setItem(PREF,JSON.stringify(p));}catch(e){}}
var saveT=null;
L.save=function(){if(!S||!S.ui.persist||saveT)return;saveT=setTimeout(function(){saveT=null;try{localStorage.setItem(KEY,JSON.stringify(S));}catch(e){}},400);};
L.setPersist=function(on){S.ui.persist=!!on;var p=readPref();p.persist=!!on;writePref(p);if(on)L.save();else try{localStorage.removeItem(KEY);}catch(e){}queueRender();};
/* Reset reloads the page (every module re-initialises its own namespace cleanly). opts.scenario auto-starts a scenario after reload. */
L.reset=function(opts){opts=opts||{};try{localStorage.removeItem(KEY);}catch(e){}
  try{if(opts.scenario)sessionStorage.setItem("olive-live-autostart",opts.scenario);else sessionStorage.removeItem("olive-live-autostart");}catch(e){}
  location.reload();};

/* ------------------------------------------------------------ time zones -- */
var dtfCache={};
function dtf(tz,opt){var k=tz+"|"+opt;if(!dtfCache[k]){var o={timeZone:tz,hourCycle:"h23"};
  if(opt==="parts"){o.year="numeric";o.month="numeric";o.day="numeric";o.hour="numeric";o.minute="numeric";o.second="numeric";o.weekday="short";}
  else if(opt==="time"){o.hour="numeric";o.minute="2-digit";o.hourCycle="h12";}
  else if(opt==="day"){o.weekday="short";}
  else if(opt==="dayfull"){o.weekday="long";o.month="short";o.day="numeric";}
  else if(opt==="datetime"){o.weekday="short";o.hour="numeric";o.minute="2-digit";o.hourCycle="h12";}
  else if(opt==="short"){o.month="short";o.day="numeric";}
  dtfCache[k]=new Intl.DateTimeFormat("en-US",o);}return dtfCache[k];}
var DOW={Sun:0,Mon:1,Tue:2,Wed:3,Thu:4,Fri:5,Sat:6};
L.parts=function(t,tz){var o={};dtf(tz||S.family.homeTz,"parts").formatToParts(new Date(t)).forEach(function(p){o[p.type]=p.value;});
  return {y:+o.year,m:+o.month,d:+o.day,h:(+o.hour)%24,min:+o.minute,s:+o.second,dow:DOW[o.weekday]};};
function offsetAt(t,tz){var p=L.parts(t,tz);return Date.UTC(p.y,p.m-1,p.d,p.h,p.min,p.s)-Math.floor(t/1000)*1000;}
L.zoned=function(y,m,d,h,min,tz){var guess=Date.UTC(y,m-1,d,h,min,0);var off=offsetAt(guess,tz);var r=guess-off;var off2=offsetAt(r,tz);if(off2!==off)r=guess-off2;return r;};
var TZN={"America/Chicago":"CT","America/New_York":"ET","America/Denver":"MT","America/Phoenix":"MST","America/Los_Angeles":"PT","America/Anchorage":"AKT","Pacific/Honolulu":"HT","Europe/London":"UK","Europe/Paris":"CET","Australia/Sydney":"AEST"};
L.TZ=TZN;L.tzName=function(tz){return TZN[tz]||tz;};
L.fmt={
  time:function(t,tz){return dtf(tz||S.family.homeTz,"time").format(new Date(t)).replace(/\u202f/g," ");},
  day:function(t,tz){return dtf(tz||S.family.homeTz,"day").format(new Date(t));},
  dayFull:function(t,tz){return dtf(tz||S.family.homeTz,"dayfull").format(new Date(t));},
  dayTime:function(t,tz){return dtf(tz||S.family.homeTz,"datetime").format(new Date(t)).replace(/\u202f/g," ").replace(",","");},
  short:function(t,tz){return dtf(tz||S.family.homeTz,"short").format(new Date(t));},
  dur:function(ms){ms=Math.max(0,Math.round(ms/1000));var h=Math.floor(ms/3600),m=Math.floor(ms%3600/60),s=ms%60;return h?h+"h "+(m<10&&h?"0":"")+m+"m":(m?m+"m "+(s<10?"0":"")+s+"s":s+"s");},
  mss:function(ms){ms=Math.max(0,Math.round(ms/1000));var m=Math.floor(ms/60),s=ms%60;return m+":"+(s<10?"0":"")+s;}
};
L.dayPart=function(t,tz){var h=L.parts(t,tz).h;return h<5?"Night":h<8?"Early morning":h<12?"Morning":h<17?"Afternoon":h<20?"Evening":h<21?"Bedtime":"Night";};

/* ----------------------------------------------------------- clock/timers -- */
L.now=function(){return new Date(S.clock.t);};
L.t=function(){return S.clock.t;};
var timers=[],timerSeq=0,evHandlers={},renderPending=false;
L.after=function(ms,fn,name){var tm={id:++timerSeq,due:S.clock.t+ms,every:0,fn:fn,name:name||"after"};timers.push(tm);return tm.id;};
L.every=function(ms,fn,name){var tm={id:++timerSeq,due:S.clock.t+ms,every:Math.max(1000,ms),fn:fn,name:name||"every"};timers.push(tm);return tm.id;};
L.cancel=function(id){timers=timers.filter(function(t){return t.id!==id;});};
L.homeTz=function(){var f=S.family,g=f.guardians.filter(function(x){return x.id===f.custody.with;})[0]||f.guardians[0];return (g&&g.tz)||f.homeTz;};
/* next occurrence of a schedule point strictly after `from` (ms). kind: bedtime | morning | exchange | birthday */
L.nextAt=function(kind,from){
  from=from==null?S.clock.t:from;var tz=L.homeTz(),f=S.family,sc=f.schedule,p0=L.parts(from,tz),hh,mm,i,c,pp;
  if(kind==="birthday"){var b=f.child.birthday;if(!b||!f.created)return Infinity;
    for(i=0;i<3;i++){c=L.zoned(p0.y+i,b.m,b.d,0,0,tz);if(c>from)return c;}return Infinity;}
  var spec=kind==="exchange"?sc.exchange.time:(kind==="bedtime"?sc.bedtime:sc.morning);
  hh=+spec.split(":")[0];mm=+spec.split(":")[1];
  for(i=0;i<15;i++){var dd=new Date(Date.UTC(p0.y,p0.m-1,p0.d+i));c=L.zoned(dd.getUTCFullYear(),dd.getUTCMonth()+1,dd.getUTCDate(),hh,mm,tz);
    if(c<=from)continue;if(kind==="exchange"){pp=L.parts(c,tz);if(pp.dow!==sc.exchange.dow)continue;}return c;}
  return Infinity;};
function crossings(from){var o={};["bedtime","morning","exchange","birthday"].forEach(function(k){o[k]=S.family.created?L.nextAt(k,from):Infinity;});return o;}
function nextEvent(cr){var best=null,i;for(i=0;i<timers.length;i++){if(!best||timers[i].due<best.at)best={at:timers[i].due,kind:"timer",ref:timers[i]};}
  for(var k in cr){if(cr[k]<Infinity&&(!best||cr[k]<best.at))best={at:cr[k],kind:"cross",ref:k};}return best;}
function fireCross(k,at){
  if(k==="bedtime")L.emit("time:bedtime",{at:at});
  else if(k==="morning")L.emit("time:morning",{at:at});
  else if(k==="exchange"){var f=S.family,gs=f.guardians,from=f.custody.with,to=from;
    if(gs.length>1){to=gs.filter(function(g){return g.id!==from;})[0].id;f.custody={with:to,since:at};}
    L.emit("time:exchange",{at:at,from:from,to:to});if(to!==from)L.emit("family:changed",{what:"custody",from:from,to:to});}
  else if(k==="birthday"){var c=S.family.child;if(c.age!=null&&c.age<17)L.setAge(c.age+1,{birthday:true});}}
L.advance=function(ms){
  if(!(ms>0))return;var target=S.clock.t+ms,guard=0,counts={};
  while(guard++<4000){
    var cr=crossings(S.clock.t),ev=nextEvent(cr);if(!ev||ev.at>target)break;
    S.clock.t=Math.max(S.clock.t,ev.at);
    if(ev.kind==="timer"){var tm=ev.ref;
      if(tm.every){counts[tm.id]=(counts[tm.id]||0)+1;tm.due=counts[tm.id]>60?target+tm.every:tm.due+tm.every;}else timers=timers.filter(function(x){return x!==tm;});
      try{tm.fn(S.clock.t);}catch(e){logErr("timer "+tm.name,e);}
    }else{
      /* make sure a crossing is not re-found at the same instant */
      S.clock.t=ev.at+1;fireCross(ev.ref,ev.at);}
  }
  S.clock.t=Math.max(S.clock.t,target);
};
L.setClock=function(o){L.update(function(S){if(o.speed!=null)S.clock.speed=o.speed;if(o.paused!=null)S.clock.paused=!!o.paused;});};
L.jumpTo=function(t){if(t>S.clock.t){L.advance(t-S.clock.t);}L.emit("time:jump",{t:S.clock.t});queueRender();};
L.jumpToNext=function(kind){var at=L.nextAt(kind,S.clock.t);if(at===Infinity)return false;L.jumpTo(at);return true;};
var lastReal=Date.now();
function tick(){
  var n=Date.now(),dt=Math.min(n-lastReal,2000);lastReal=n;
  if(!S||S.clock.paused||!booted)return;
  L.advance(dt*S.clock.speed);
  L.emit("time:tick",{t:S.clock.t});updateLive();
  if(S.clock.speed>=600||(Math.floor(S.clock.t/60000)!==L._lastMin)){L._lastMin=Math.floor(S.clock.t/60000);queueRender();}
  L.save();
}
function updateLive(){
  var els=document.querySelectorAll("[data-clock],[data-countdown]"),i,e,a,p,v;
  for(i=0;i<els.length;i++){e=els[i];
    if((a=e.getAttribute("data-clock"))){p=a.split("|");v=L.fmt[p[0]]?L.fmt[p[0]](S.clock.t,p[1]):L.fmt.time(S.clock.t,p[1]);if(e.textContent!==v)e.textContent=v;}
    if((a=e.getAttribute("data-countdown"))){var left=+a-S.clock.t;v=left>0?L.fmt.mss(left):(e.getAttribute("data-done")||"0:00");if(e.textContent!==v)e.textContent=v;}}
}
L.updateLive=updateLive;

/* ---------------------------------------------------------------- events -- */
L.on=function(type,fn){(evHandlers[type]=evHandlers[type]||[]).push(fn);return fn;};
L.off=function(type,fn){if(!evHandlers[type])return;evHandlers[type]=evHandlers[type].filter(function(f){return f!==fn;});};
L.emit=function(type,payload){
  if(type!=="time:tick"&&S){var ev=S.server.events;ev.push({t:S.clock.t,type:type,payload:payload==null?null:payload});if(ev.length>400)ev.splice(0,ev.length-400);}
  var hs=(evHandlers[type]||[]).concat(evHandlers["*"]||[]);
  for(var i=0;i<hs.length;i++){try{hs[i](payload,type);}catch(e){logErr("event "+type,e);}}
  if(type!=="time:tick")queueRender();};

/* ---------------------------------------------------------------- family -- */
function bandOf(age){return age<=4?"t34":age<=7?"t57":age<=12?"t812":"t1317";}
L.bandOf=bandOf;
L.band=function(){var a=S.family.child.age;return bandOf(a==null?10:a);};
L.setAge=function(n,o){n=Math.max(3,Math.min(17,Math.round(+n)));var c=S.family.child,from=L.band(),old=c.age;c.age=n;var to=L.band();
  if(old!==n)L.emit("family:changed",{what:"age",age:n,from:old,birthday:!!(o&&o.birthday)});
  if(from!==to)L.emit("age:band",{from:from,to:to,age:n});queueRender();};
L.guardian=function(id){return S.family.guardians.filter(function(g){return g.id===id;})[0]||null;};
L.gid=function(dev){var r=S.dev[dev].role;return r==="mom"||r==="dad"||r==="other"?r:null;};
L.me=function(dev){return L.guardian(L.gid(dev));};
L.labels={
  forChild:function(gid){var f=S.family,c=f.child,nick=c.nicknames&&c.nicknames[gid];if(nick)return nick;
    var g=L.guardian(gid);if(gid!=="mom"&&gid!=="dad")return (g&&g.name)||"Grown-up";
    var word=gid==="mom"?"Mom":"Dad";
    if(c.ageLocked&&c.age!=null&&c.age<=15)return gid==="mom"?"Mommy":"Daddy";
    return word;},
  forGuardian:function(gid,viewer){var f=S.family,c=f.child,g=L.guardian(gid),you=viewer===undefined?null:viewer;
    var nm=c.name||"Your child";var l=L.labels.forChild(gid);
    return nm+" calls "+(you===gid?"you":(g&&g.name)||"them")+" "+l;},
  rename:function(gid,nick,by){by=by||"child";
    if(by!=="child")return {ok:false,reason:"child_owned"};
    nick=String(nick==null?"":nick).trim().slice(0,24);var c=S.family.child;c.nicknames=c.nicknames||{};
    if(!nick)delete c.nicknames[gid];else c.nicknames[gid]=nick;
    L.emit("family:changed",{what:"nickname",guardian:gid,nick:nick});queueRender();return {ok:true,nick:nick};}
};

/* ------------------------------------------------------------- navigation -- */
var screens={};
L.screen=function(id,def){def=def||{};var devs=def.dev==="both"||!def.dev?["g","k"]:[def.dev];screens[id]=screens[id]||{};devs.forEach(function(d){screens[id][d]=def;});return def;};
L.hasScreen=function(id,dev){return !!(screens[id]&&(!dev||screens[id][dev]));};
L.screenDef=function(id,dev){return screens[id]&&screens[id][dev];};
function stackOf(dev){return S.dev[dev].stack;}
L.go=function(dev,id,params){var st=stackOf(dev);var top=st[st.length-1];S.ui[dev].sheet=null;delete sheetFns[dev];
  if(top&&top.id===id&&JSON.stringify(top.params||{})===JSON.stringify(params||{})){queueRender();return;}
  st.push({id:id,params:params||{}});if(st.length>40)st.splice(0,st.length-40);queueRender();};
L.replace=function(dev,id,params){var st=stackOf(dev);st[st.length-1]={id:id,params:params||{}};S.ui[dev].sheet=null;delete sheetFns[dev];queueRender();};
L.reroot=function(dev,id,params){S.dev[dev].stack=[{id:id,params:params||{}}];S.ui[dev].sheet=null;delete sheetFns[dev];queueRender();};
L.back=function(dev){var st=stackOf(dev);S.ui[dev].sheet=null;delete sheetFns[dev];if(st.length>1)st.pop();queueRender();};
L.home=function(dev){var d=S.dev[dev];L.reroot(dev,(d.role&&d.onboarded)?"home":"ob.role");};
L.current=function(dev){var st=stackOf(dev);return st[st.length-1];};
var sheetFns={},toastTimers={},sheetFresh={};
L.sheet=function(dev,html){if(typeof html==="function"){sheetFns[dev]=html;S.ui[dev].sheet={fn:true};}else{delete sheetFns[dev];S.ui[dev].sheet={html:html};}sheetFresh[dev]=true;queueRender();};
L.closeSheet=function(dev){S.ui[dev].sheet=null;delete sheetFns[dev];queueRender();};
L.toast=function(dev,text,o){o=o||{};S.ui[dev].toast={text:text,ic:o.ic||"check",tone:o.tone||""};clearTimeout(toastTimers[dev]);
  toastTimers[dev]=setTimeout(function(){S.ui[dev].toast=null;queueRender();},o.ms||3600);queueRender();};

/* ----------------------------------------------------------------- tiles -- */
var tileReg=[];
L.tile=function(t){t.order=t.order==null?50:t.order;tileReg.push(t);return t;};
L.tiles=function(c,q){q=q||{};return tileReg.filter(function(t){
  if(t.dev!==c.dev&&t.dev!=="both")return false;if(q.area&&t.area!==q.area)return false;if(q.tier&&t.tier!==q.tier)return false;if(q.group&&t.group!==q.group)return false;
  if(t.when){try{if(!t.when(c))return false;}catch(e){logErr("tile when "+t.id,e);return false;}}return true;}).sort(function(a,b){return a.order-b.order;});};
L.tileBadge=function(c,t){if(!t.badge)return null;try{return t.badge(c);}catch(e){logErr("tile badge "+t.id,e);return null;}};
var homeVariants={};
L.homeVariant=function(band,fn){homeVariants[band]=fn;};
L.hasHomeVariant=function(band){return !!homeVariants[band];};
L.homeVariantFor=function(c){return homeVariants[c.band]||null;};

/* ----------------------------------------------------------- html helpers -- */
var acts={};
L.act=function(name,fn){acts[name]=fn;};
L.hasAct=function(name){return !!acts[name];};
L.acts=function(){return Object.keys(acts).sort();};
L.a=function(name,arg,arg2){return ' data-act="'+esc(name)+'"'+(arg!=null?' data-arg="'+esc(arg)+'"':"")+(arg2!=null?' data-arg2="'+esc(arg2)+'"':"");};
L.withAttr=function(html,attrs){return String(html).replace(/^(\s*<[a-zA-Z0-9]+)/,"$1"+attrs);};
L.withAct=function(html,name,arg,arg2){return L.withAttr(html,L.a(name,arg,arg2));};
L.btn=function(text,act,arg,o){o=o||{};return L.withAct(K.btn(text,o),act,arg,o.arg2);};
L.iconBtn=function(ic,act,arg,o){return L.withAct(K.iconBtn(ic,o),act,arg,o&&o.arg2);};
L.row=function(o){var h=K.row(o);return o.act?L.withAct(h,o.act,o.arg,o.arg2):h;};
L.tileEl=function(tier,o,act,arg,arg2){return L.withAct(K.tile(tier,o),act,arg,arg2);};
/* text input bound into S: L.field({label,path,ph,hint,error,type,ic,req,suffix}) */
L.field=function(o){var h=K.formField(o);return h.replace("<input",'<input data-bind="'+esc(o.path||"")+'"'+(o.maxlength?' maxlength="'+o.maxlength+'"':"")+(o.inputmode?' inputmode="'+o.inputmode+'"':"")+(o.autocomplete===false?' autocomplete="off"':"")).replace(/value="[^"]*"/,function(){return 'value="'+esc(o.value!=null?o.value:(L.get(o.path)||""))+'"';});};
/* segmented control where each option runs an action: L.seg(items, activeIndex, 'act', {args:[...], label, sm}) */
L.seg=function(items,active,act,o){o=o||{};var i=0;return K.segmented(items,active,o).replace(/<span role="radio"/g,function(){var arg=o.args?o.args[i]:i;i++;return '<span data-act="'+esc(act)+'" data-arg="'+esc(arg)+'" role="radio"';});};
L.chips=function(items,active,act,o){o=o||{};var i=0;return K.filterChips(items,active,o).replace(/<button type="button" class="fchip/g,function(){var arg=o.args?o.args[i]:i;i++;return '<button data-act="'+esc(act)+'" data-arg="'+esc(arg)+'" type="button" class="fchip';});};
L.toggle=function(on,act,arg,o){return L.withAct(K.toggle(on,o),act,arg);};
L.toggleRow=function(o){return L.withAct(K.toggleRow(o),o.act,o.arg,o.arg2);};
L.tabbar=function(dev,items,active){ // items: [{ic,label,screen,act,arg,badge}]
  return '<nav class="tabbar" aria-label="Main">'+items.map(function(x,i){var on=x.screen===active||i===active;
    return '<span role="link" tabindex="0"'+(on?' aria-current="page"':"")+' class="'+(on?"on":"")+'"'+(x.act?L.a(x.act,x.arg):L.a("go",x.screen))+'>'+K.ico(x.ic,22,on?2.1:1.8)+'<small>'+esc(x.label)+'</small>'+(x.badge?'<i class="live-dot" aria-hidden="true"></i>':"")+'</span>';}).join("")+'</nav>';};
L.renderTile=function(c,t){ // renders a registered tile as K.tile with navigation
  var b=L.tileBadge(c,t),child=c.dev==="k";
  var o={ic:t.icon||"leaf",title:typeof t.title==="function"?t.title(c):t.title,sub:typeof t.sub==="function"?t.sub(c):t.sub,scene:t.scene,tone:t.tone,badge:(!child&&b)?(b===true?"New":String(b)):null};
  var h=K.tile(t.tier==="hero"?"hero":t.tier==="featured"?"feat":"std",o);
  if(child&&b)h=h.replace(/(<span class="tic">)/,'<i class="live-dot" role="img" aria-label="Something new"></i>$1');
  return L.withAct(h,t.act||"go",t.act?t.arg:t.screen,t.params?JSON.stringify(t.params):null);};

/* ------------------------------------------------------------------ hooks -- */
L.hooks={statusBar:null};
L.afterRender=[];
L.formOf=function(dev){return S.ui.form[dev]||(dev==="g"?"phone":"tablet");};
L.setOnline=function(dev,on){var was=L.online(dev);S.net[dev].online=!!on;if(was!==!!on)L.emit("net:change",{dev:dev,online:!!on});queueRender();};
L.online=function(dev){return S.net[dev].online!==false&&S.net.online!==false;};
L.ctx=function(dev){
  var d=S.dev[dev],top=d.stack[d.stack.length-1]||{id:"home",params:{}},form=L.formOf(dev);
  return {dev:dev,S:S,params:top.params||{},screenId:top.id,role:d.role,L:L,labels:L.labels,band:L.band(),now:L.now(),t:S.clock.t,form:form,
    posture:form,online:L.online(dev),child:dev==="k",guardianId:L.gid(dev)};};

/* ---------------------------------------------------------------- render -- */
var lastHtml={g:null,k:null},lastKey={g:null,k:null};
function focusables(root){return Array.prototype.slice.call(root.querySelectorAll('button,input,select,textarea,[tabindex="0"],[role=button],a[href]')).filter(function(e){return !e.disabled;});}
function missingHtml(c){return '<div class="scroll"><div class="col" style="padding-top:20px">'+(K.errorState?K.errorState({title:"Screen not available yet",sub:"No module has registered \u201c"+esc(c.screenId)+"\u201d for this device.",detail:c.screenId}):"")+
  '<button type="button" class="btn tonal full" data-act="home">Back to start</button></div></div>';}
function errorHtml(c,e){return '<div class="scroll"><div class="col" style="padding-top:20px">'+(K.errorState?K.errorState({title:c.dev==="k"?"Something went wrong":"This screen hit an error",sub:c.dev==="k"?"Ask a grown-up to look.":esc(String(e&&e.message||e)),detail:c.screenId}):"")+
  '<button type="button" class="btn tonal full" data-act="back">Go back</button></div></div>';}
function buildDev(dev){
  var c=L.ctx(dev),def=L.screenDef(c.screenId,dev),inner;
  if(!def)inner=missingHtml(c);else{try{inner=def.render(c);}catch(e){logErr("render "+c.screenId+"/"+dev,e);inner=errorHtml(c,e);}}
  var sb="";if(L.hooks.statusBar){try{sb=L.hooks.statusBar(c);}catch(e){logErr("statusBar",e);}}
  var ov="",u=S.ui[dev];
  if(u.sheet){var sh="";if(u.sheet.fn){var f=sheetFns[dev];if(f){try{sh=f(c);}catch(e){logErr("sheet",e);sh="";}}else{u.sheet=null;}}else sh=u.sheet.html||"";
    if(u.sheet)ov+='<div class="scrim'+(sheetFresh[dev]?" enter":"")+'" data-act="sheet.close" role="presentation"></div><div class="sheet'+(sheetFresh[dev]?" enter":"")+'" role="dialog" aria-modal="true" aria-label="Details"><i class="grab"></i>'+sh+'</div>';}
  if(u.toast)ov+=K.toast(u.toast.text,{ic:u.toast.ic,tone:u.toast.tone});
  var key=c.screenId+"|"+dev;
  var pal=S.ui.palette;if(dev==="k"&&S.ui.childColour!==false&&S.family.child.color&&K.SEEDS&&K.SEEDS[S.family.child.color])pal=S.family.child.color;if(dev==="k"&&S.dev.k.draft&&S.dev.k.draft.color&&!S.dev.k.paired&&K.SEEDS&&K.SEEDS[S.dev.k.draft.color])pal=S.dev.k.draft.color;
  var theme=K.theme?K.theme(pal,S.ui.mode):"";
  return {html:'<div class="ob '+(dev==="k"?"child":"guardian")+" f-"+c.form+'" data-dev="'+dev+'" data-screen="'+esc(c.screenId)+'" style="'+theme+'">'+sb+inner+ov+'</div>',key:key,hadSheet:!!u.sheet};
}
function renderDev(dev){
  var host=document.querySelector('[data-host="'+dev+'"]');if(!host)return;
  var b=buildDev(dev);if(b.html===lastHtml[dev])return;
  var old=host.querySelector(".ob"),act=document.activeElement,fi=-1,sel=null,scr=0,mine=false;
  if(old){var sc=old.querySelector(".scroll");scr=sc?sc.scrollTop:0;
    if(act&&old.contains(act)){mine=true;fi=focusables(old).indexOf(act);if(act.setSelectionRange&&act.type!=="checkbox"){try{sel=[act.selectionStart,act.selectionEnd];}catch(e){}}}}
  host.innerHTML=b.html;lastHtml[dev]=b.html;
  var nw=host.querySelector(".ob");
  if(nw){
    if(lastKey[dev]===b.key){var s2=nw.querySelector(".scroll");if(s2)s2.scrollTop=scr;}
    if(sheetFresh[dev]&&b.hadSheet){var first=nw.querySelector(".sheet button,.sheet input,.sheet [role=button]");if(first&&first.focus)first.focus({preventScroll:true});}
    else if(mine&&fi>=0){var f2=focusables(nw)[fi];if(f2){f2.focus({preventScroll:true});if(sel&&f2.setSelectionRange){try{f2.setSelectionRange(sel[0],sel[1]);}catch(e){}}}}
    else if(lastKey[dev]!==b.key&&lastKey[dev]!=null&&mine){var h=nw.querySelector("h1,h2,.ttl b");}
  }
  sheetFresh[dev]=false;lastKey[dev]=b.key;
}
L.render=function(){
  if(!booted)return;
  ["g","k"].forEach(function(d){try{renderDev(d);}catch(e){logErr("renderDev "+d,e);}});
  document.documentElement.setAttribute("data-theme",S.ui.mode);
  for(var i=0;i<L.afterRender.length;i++){try{L.afterRender[i](S);}catch(e){console.error(e);}}
  updateLive();
};
function queueRender(){if(renderPending)return;renderPending=true;Promise.resolve().then(function(){renderPending=false;L.render();});}
L.queueRender=queueRender;
L.update=function(fn){var r;try{r=fn(S);}catch(e){logErr("update",e);}L.save();queueRender();return r;};

/* -------------------------------------------------- actions + delegation -- */
function devOf(el){var o=el.closest&&el.closest("[data-dev]");return o?o.getAttribute("data-dev"):null;}
function runAct(dev,name,arg,el,ev,arg2){
  var fn=acts[name];if(!fn){L.toast(dev,"Not available yet: "+name);return {missing:true};}
  var c=L.ctx(dev);if(arg2!==undefined&&arg2!==null)c.arg2=arg2;
  var r;try{r=fn(c,arg,el||null,ev||null);}catch(e){logErr("act "+name,e);}
  L.save();queueRender();return r;}
L.run=function(dev,name,arg,arg2){return runAct(dev,name,arg,null,null,arg2);};
function elArg2(el){return el&&el.getAttribute?el.getAttribute("data-arg2"):null;}
document.addEventListener("click",function(ev){
  var t=ev.target;if(!t.closest)return;
  var el=t.closest("[data-act]");
  if(!el){var bb=t.closest('.ob button.cbtn[aria-label="Back"]');if(bb){var dv=devOf(bb);if(dv){ev.preventDefault();L.back(dv);}}return;}
  if(el.disabled||el.getAttribute("aria-disabled")==="true")return;
  var tag=el.tagName;if(tag==="INPUT"||tag==="SELECT"||tag==="TEXTAREA")return; /* handled on change */
  var dev=devOf(el);if(!dev)return;
  ev.preventDefault();
  /* sheet scrim is data-act too, but a click inside .sheet must not close */
  runAct(dev,el.getAttribute("data-act"),el.getAttribute("data-arg"),el,ev,elArg2(el));
});
document.addEventListener("keydown",function(ev){
  var t=ev.target;if(!t||!t.closest)return;
  if(ev.key==="Escape"){var o=t.closest&&t.closest("[data-dev]");var dv=o?o.getAttribute("data-dev"):null;
    if(dv&&S.ui[dv].sheet){ev.preventDefault();L.closeSheet(dv);return;}}
  if((ev.key==="Enter"||ev.key===" ")&&t.getAttribute&&/^(button|link|radio|switch|checkbox)$/.test(t.getAttribute("role")||"")&&t.tagName!=="BUTTON"&&t.tagName!=="INPUT"){
    if(t.closest("[data-dev]")){ev.preventDefault();t.click();}}
  /* arrow keys inside radio groups */
  if((ev.key==="ArrowRight"||ev.key==="ArrowLeft"||ev.key==="ArrowDown"||ev.key==="ArrowUp")&&t.getAttribute&&t.getAttribute("role")==="radio"){
    var grp=t.parentNode,rs=Array.prototype.slice.call(grp.querySelectorAll('[role=radio]')),i=rs.indexOf(t),n=(ev.key==="ArrowRight"||ev.key==="ArrowDown")?i+1:i-1;
    if(n>=0&&n<rs.length){ev.preventDefault();rs[n].focus();}}
});
document.addEventListener("input",function(ev){
  var el=ev.target;if(!el||!el.getAttribute)return;var p=el.getAttribute("data-bind");
  if(p&&devOf(el)){L.set(p,el.type==="checkbox"?el.checked:el.value);L.save();}
});
document.addEventListener("change",function(ev){
  var el=ev.target;if(!el||!el.getAttribute)return;var dev=devOf(el);if(!dev)return;
  var p=el.getAttribute("data-bind");if(p){L.set(p,el.type==="checkbox"?el.checked:el.value);L.save();}
  var a=el.getAttribute("data-act");if(a){runAct(dev,a,el.type==="checkbox"?el.checked:el.value,el,ev,elArg2(el));}else if(p){setTimeout(queueRender,0);}
});
/* built-in actions */
L.act("go",function(c,arg){var p=null;try{p=c.arg2?JSON.parse(c.arg2):null;}catch(e){}L.go(c.dev,arg,p||{});});
L.act("back",function(c){L.back(c.dev);});
L.act("home",function(c){L.home(c.dev);});
L.act("sheet.close",function(c){L.closeSheet(c.dev);});
L.act("noop",function(){});
L.act("toast",function(c,arg){L.toast(c.dev,arg);});
/* Drive the REAL UI from scripts: click the element if it is on screen (with a visible pulse), else run the action directly. */
L.tap=function(dev,name,arg){
  var host=document.querySelector('[data-host="'+dev+'"]');var sel='[data-act="'+name+'"]'+(arg!=null?'[data-arg="'+String(arg).replace(/"/g,'\\"')+'"]':"");
  var el=host&&host.querySelector(sel);
  if(el){el.classList.add("live-pulse");setTimeout(function(){el.classList.remove("live-pulse");},700);try{el.scrollIntoView({block:"nearest"});}catch(e){}el.click();return {via:"dom"};}
  if(acts[name]){runAct(dev,name,arg==null?null:String(arg),null,null);return {via:"act"};}
  return {via:"missing"};};
/* Type into a data-bind input (real DOM if present, else straight into S). */
L.type=function(dev,path,value){
  var host=document.querySelector('[data-host="'+dev+'"]');var el=host&&host.querySelector('[data-bind="'+path+'"]');
  L.set(path,value);if(el&&el.tagName){el.value=value;el.classList.add("live-pulse");setTimeout(function(){el.classList.remove("live-pulse");},700);}queueRender();};

/* ------------------------------------------------------ simulated server -- */
var routes=[],rateBuckets={};
function compile(path){var keys=[];var re=new RegExp("^"+path.replace(/[.*+?^${}()|[\]\\]/g,"\\$&").replace(/:([a-zA-Z_]+)/g,function(_,k){keys.push(k);return "([^/]+)";})+"$");return {re:re,keys:keys};}
L.route=function(method,path,fn,opts){var c=compile(path);routes.push({m:String(method).toUpperCase(),path:path,re:c.re,keys:c.keys,fn:fn,opts:opts||{}});};
L.fail=function(status,code,message,extra){var b={error:{code:code,message:message||code}};if(extra)for(var k in extra)b.error[k]=extra[k];return {status:status,body:b};};
L.ok=function(body,status){return {status:status||200,body:body==null?{}:body};};
function principal(dev){var d=S.dev[dev],r=d.role;var kind=r==="kid"?"child":r==="other"?"sitter":r?"guardian":"anonymous";
  return {kind:kind,id:kind==="child"?S.family.child.id:r,deviceId:d.deviceId,role:r,dev:dev};}
L.principal=principal;
function findRoute(m,p){for(var i=routes.length-1;i>=0;i--){ /* a later registration overrides an earlier one */var r=routes[i];if(r.m!==m)continue;var x=r.re.exec(p);if(x){var params={};r.keys.forEach(function(k,j){params[k]=decodeURIComponent(x[j+1]);});return {r:r,params:params};}}return null;}
function pushLog(e){var lg=S.server.log;lg.push(e);if(lg.length>400)lg.splice(0,lg.length-400);}
L.api=function(dev,method,path,body){
  method=String(method).toUpperCase();
  return new Promise(function(resolve){
    var reqId="req_"+(++S.server.seq).toString(36).padStart(4,"0"),started=Date.now(),p0=path.split("?")[0],query={};
    (path.split("?")[1]||"").split("&").forEach(function(kv){if(kv){var a=kv.split("=");query[decodeURIComponent(a[0])]=decodeURIComponent(a[1]||"");}});
    function finish(status,rb,extra){
      var code=rb&&rb.error&&rb.error.code||null,ms=Date.now()-started;
      var e={t:S.clock.t,dev:dev,method:method,path:p0,status:status,ms:ms,reqId:reqId,code:code};if(extra)for(var k in extra)e[k]=extra[k];pushLog(e);
      var res={ok:status>=200&&status<300,status:status,body:rb||{},code:code,error:code,message:rb&&rb.error&&rb.error.message||null,reqId:reqId,ms:ms};
      queueRender();resolve(res);}
    if(!L.online(dev)){setTimeout(function(){finish(0,{error:{code:"offline",message:"No network on this device"}});},180);return;}
    var lat=Math.max(0,S.net.latencyMs||0);lat=lat*(0.6+Math.random()*0.8);
    setTimeout(function(){
      try{
        /* simulated rate limit: per device, rolling real-time window */
        var rl=S.net.rate||{limit:60,windowMs:10000},now=Date.now(),bk=rateBuckets[dev]=(rateBuckets[dev]||[]).filter(function(x){return now-x<rl.windowMs;});bk.push(now);
        if(bk.length>rl.limit){finish(429,L.fail(429,"rate_limited","Too many requests. Slow down.",{retryAfterMs:rl.windowMs}).body);return;}
        var fn=S.net.failNext&&S.net.failNext[dev];if(fn){S.net.failNext[dev]=null;finish(+fn||503,L.fail(+fn||503,+fn===429?"rate_limited":"server_unavailable","Simulated failure").body);return;}
        var mt=findRoute(method,p0);if(!mt){finish(404,L.fail(404,"not_found","No such route").body);return;}
        var r=mt.r,pr=principal(dev),d=S.dev[dev];
        if(!r.opts.public){
          if((d.deviceId&&S.server.revoked[d.deviceId])||d.revoked){finish(401,L.fail(401,"device_revoked","This device was removed").body);return;}
          if(!d.sessionOk){finish(401,L.fail(401,"unauthenticated","Sign in first").body);return;}
          var ss=S.server.sessions[dev];if(ss&&ss.expiresAt&&ss.expiresAt<=S.clock.t){d.sessionOk=false;finish(401,L.fail(401,"session_expired","Your session ended").body);L.emit("auth:expired",{dev:dev});return;}
          if(r.opts.principals&&r.opts.principals.indexOf(pr.kind)<0){
            if(r.opts.principals.length===1&&r.opts.principals[0]==="child")finish(403,L.fail(403,"not_a_child_surface","This is only for the child's tablet").body);
            else finish(403,L.fail(403,"forbidden","Only "+r.opts.principals.join(" or ")+" can do this",{reason:pr.kind==="child"?"not_a_guardian_surface":"principal"}).body);return;}
        }
        var req={dev:dev,principal:pr,body:body==null?{}:body,params:mt.params,query:query,method:method,path:p0,reqId:reqId,L:L};
        var out=r.fn(req);
        Promise.resolve(out).then(function(o){o=o||{status:200,body:{}};if(o.error&&!o.body)o=L.fail(o.status||400,o.error);finish(o.status||200,o.body||{});},function(e){logErr("route "+method+" "+p0,e);finish(500,L.fail(500,"internal_error","Server error").body);});
      }catch(e){logErr("route "+method+" "+p0,e);finish(500,L.fail(500,"internal_error","Server error").body);}
    },lat);
  });};

/* ---- built-in routes ---------------------------------------------------- */
function newSession(dev,days){S.server.sessions[dev]={token:L.id("tok"),expiresAt:S.clock.t+(days||14)*86400000};S.dev[dev].sessionOk=true;}
L.newSession=newSession;
function codeOf(){var o="";for(var i=0;i<6;i++)o+=1+Math.floor(Math.random()*9);return o;} /* digits 1-9 only, so the child’s nine-digit pad can type any code */
L.route("GET","/v1/now",function(){return L.ok({now:S.clock.t,iso:new Date(S.clock.t).toISOString(),speed:S.clock.speed});},{public:true});
L.route("GET","/v1/me",function(req){var pr=req.principal,f=S.family;
  return L.ok({principal:pr,family:{id:f.id,child:{id:f.child.id,name:f.child.name,age:f.child.age,ageLocked:f.child.ageLocked},guardians:f.guardians.map(function(g){return {id:g.id,name:g.name,label:g.label,tz:g.tz};}),custody:f.custody},device:{id:S.dev[req.dev].deviceId,paired:S.dev[req.dev].paired}});});
/* Guardian creates the family (first guardian). body: {guardian:{role,name,label,tz}, child:{name,age}, pin, homeTz} */
L.route("POST","/v1/families",function(req){var b=req.body,g=b.guardian||{},ch=b.child||{};
  if(!g.name||!ch.name)return L.fail(422,"validation_failed","Names are needed");
  if(!/^\d{4}$/.test(String(b.pin||"")))return L.fail(422,"invalid_pin","PIN must be 4 digits");
  var age=+ch.age;if(!(age>=3&&age<=17))return L.fail(422,"validation_failed","Age out of range");
  var f=S.family;f.id=L.id("fam");f.created=true;f.homeTz=b.homeTz||g.tz||f.homeTz;f.pin=String(b.pin);
  var gid=(g.role==="dad"||g.role==="other")?g.role:"mom";
  f.guardians=[{id:gid,name:g.name,label:g.label||(gid==="dad"?"Dad":"Mom"),tz:g.tz||f.homeTz,devices:[req.dev],joinedAt:S.clock.t,pinSet:true}];
  f.custody={with:gid,since:S.clock.t};
  f.child.name=ch.name;f.child.age=age;f.child.ageLocked=true;
  var dv=S.dev[req.dev];dv.role=gid;dv.paired=true;dv.deviceId=L.id("dev");newSession(req.dev);
  f.devices.push({dev:req.dev,deviceId:dv.deviceId,kind:"guardian",name:g.name+"\u2019s phone",pairedAt:S.clock.t});
  L.emit("family:changed",{what:"created"});L.emit("device:paired",{dev:req.dev,kind:"guardian",deviceId:dv.deviceId});
  return L.ok({familyId:f.id,guardianId:gid,deviceId:dv.deviceId,childId:f.child.id},201);},{public:true});
L.route("POST","/v1/children/:childId/device-pairing-codes",function(req){
  if(req.principal.kind==="child")return L.fail(403,"forbidden","A child can never create a pairing code",{reason:"not_a_guardian_surface"});
  if(req.principal.kind!=="guardian")return L.fail(403,"forbidden","Only a guardian can create a pairing code");
  if(req.params.childId!==S.family.child.id)return L.fail(404,"not_found","No such child");
  var sv=S.server;if(sv.pinLockUntil>S.clock.t)return L.fail(423,"pin_locked","Too many wrong PINs",{retryAt:sv.pinLockUntil});
  if(!S.family.pin)return L.fail(409,"pin_not_set","Set a PIN first");
  if(String(req.body.pin||"")!==S.family.pin){sv.pinFails++;if(sv.pinFails>=5){sv.pinLockUntil=S.clock.t+15*60000;sv.pinFails=0;return L.fail(423,"pin_locked","Too many wrong PINs",{retryAt:sv.pinLockUntil});}
    return L.fail(403,"invalid_pin","That PIN is not right",{attemptsLeft:5-sv.pinFails});}
  sv.pinFails=0;
  sv.pairing.forEach(function(p){if(!p.redeemedBy&&!p.revoked&&p.expiresAt>S.clock.t)p.revoked=true;}); /* a new code replaces older open codes */
  var rec={code:codeOf(),childId:S.family.child.id,createdBy:req.principal.id,createdAt:S.clock.t,expiresAt:S.clock.t+10*60000,failed_attempts:0,redeemedBy:null,revoked:false};
  sv.pairing.push(rec);L.emit("pairing:code",{code:rec.code,expiresAt:rec.expiresAt});
  return L.ok({code:rec.code,expiresAt:rec.expiresAt,ttlMs:600000,childId:rec.childId,qr:"OLIVE-"+rec.code},201);});
L.route("POST","/v1/device-pairing/redeem",function(req){
  var dev=req.dev,sv=S.server,b=req.body||{},role=b.role||(S.dev[dev].role==="kid"?"child":"guardian");
  if(sv.redeemFails.lockUntil[dev]>S.clock.t)return L.fail(429,"rate_limited","Too many tries",{retryAt:sv.redeemFails.lockUntil[dev]});
  var rec=sv.pairing.filter(function(p){return p.code===String(b.code||"");})[0];
  function bad(){sv.redeemFails[dev]=(sv.redeemFails[dev]||0)+1;if(sv.redeemFails[dev]>=5){sv.redeemFails[dev]=0;sv.redeemFails.lockUntil[dev]=S.clock.t+5*60000;}}
  if(!rec||rec.revoked||rec.redeemedBy||rec.expiresAt<=S.clock.t){bad();return L.fail(404,"not_found","No such code");}
  if(role!=="child"||S.dev[dev].role!=="kid"){rec.failed_attempts++;if(rec.failed_attempts>=5)rec.revoked=true;L.emit("pairing:mismatch",{dev:dev});return L.fail(409,"role_mismatch","This code is for a child's tablet",{failed_attempts:rec.failed_attempts});}
  rec.redeemedBy=dev;var d=S.dev[dev];d.paired=true;d.deviceId=L.id("dev");newSession(dev,3650);d.locked=true;
  S.family.devices.push({dev:dev,deviceId:d.deviceId,kind:"child",name:S.family.child.name+"\u2019s tablet",pairedAt:S.clock.t});
  L.emit("device:paired",{dev:dev,kind:"child",deviceId:d.deviceId,childId:rec.childId});L.emit("family:changed",{what:"device",dev:dev});
  var f=S.family;
  return L.ok({deviceId:d.deviceId,childId:rec.childId,child:{id:f.child.id,name:f.child.name,age:f.child.age,ageLocked:f.child.ageLocked},guardians:f.guardians.map(function(g){return {id:g.id,name:g.name,label:g.label};})},201);},{public:true});
/* Child's local draft answers, uploaded after pairing. Server merges: a locked age is never overwritten. */
L.route("PUT","/v1/children/:childId/profile",function(req){var c=S.family.child,b=req.body||{};
  if(req.principal.kind!=="child")return L.fail(403,"not_a_child_surface","Only the child's tablet sends this");
  if(b.name&&!c.name)c.name=b.name;
  if(b.age!=null&&!c.ageLocked){c.age=+b.age;c.ageLocked=true;}
  if(b.color)c.color=b.color;if(b.birthday)c.birthday=b.birthday;
  if(b.nicknames)for(var k in b.nicknames){c.nicknames[k]=b.nicknames[k];}
  L.emit("family:changed",{what:"profile"});
  return L.ok({child:{name:c.name,age:c.age,ageLocked:c.ageLocked,color:c.color,birthday:c.birthday,nicknames:c.nicknames}});},{principals:["child"]});
L.route("POST","/v1/auth/session/refresh",function(req){var d=S.dev[req.dev];
  if(!d.deviceId)return L.fail(401,"invalid_device_credential","This device is not paired");
  if(S.server.revoked[d.deviceId])return L.fail(401,"device_revoked","This device was removed");
  newSession(req.dev,d.role==="kid"?3650:14);return L.ok({expiresAt:S.server.sessions[req.dev].expiresAt});},{public:true});
L.route("POST","/v1/auth/session",function(req){var d=S.dev[req.dev],sv=S.server; /* sign back in with the guardian PIN */
  if(!d.deviceId||d.role==="kid"||!d.role)return L.fail(401,"invalid_device_credential","This device is not paired");
  if(sv.pinLockUntil>S.clock.t)return L.fail(423,"pin_locked","Too many wrong PINs",{retryAt:sv.pinLockUntil});
  if(String(req.body.pin||"")!==S.family.pin){sv.pinFails++;if(sv.pinFails>=5){sv.pinLockUntil=S.clock.t+15*60000;sv.pinFails=0;return L.fail(423,"pin_locked","Too many wrong PINs",{retryAt:sv.pinLockUntil});}return L.fail(403,"invalid_pin","That PIN is not right",{attemptsLeft:5-sv.pinFails});}
  sv.pinFails=0;newSession(req.dev);L.emit("auth:signin",{dev:req.dev});return L.ok({expiresAt:sv.sessions[req.dev].expiresAt});},{public:true});
L.route("POST","/v1/auth/session/sign-out",function(req){var d=S.dev[req.dev];d.sessionOk=false;delete S.server.sessions[req.dev];L.emit("auth:signout",{dev:req.dev});return L.ok({});});
L.route("DELETE","/v1/devices/:deviceId",function(req){ /* guardian removes a paired device */
  var id=req.params.deviceId,f=S.family;S.server.revoked[id]=true;f.devices=f.devices.filter(function(x){return x.deviceId!==id;});
  L.emit("device:revoked",{deviceId:id});return L.ok({});},{principals:["guardian"]});

/* ------------------------------------------------------------- boot/modules -- */
L.module=function(name,fn){mods.push({name:name,fn:fn});if(booted)runModule(mods[mods.length-1]);};
L.onBoot=function(fn){if(booted)fn();else bootHooks.push(fn);};
function runModule(m){try{m.fn(L);}catch(e){logErr("module "+m.name,e);}L.modules=L.modules||[];L.modules.push(m.name);}
function boot(){
  var pref=readPref();S=defaults();
  if(pref.persist){try{var raw=localStorage.getItem(KEY);if(raw){S=merge(S,JSON.parse(raw));S.dev.g.stack=S.dev.g.stack&&S.dev.g.stack.length?S.dev.g.stack:[{id:"ob.role",params:{}}];S.dev.k.stack=S.dev.k.stack&&S.dev.k.stack.length?S.dev.k.stack:[{id:"ob.role",params:{}}];S.ui.g.sheet=null;S.ui.k.sheet=null;S.ui.g.toast=null;S.ui.k.toast=null;}}catch(e){logErr("restore",e);}
    S.ui.persist=true;}
  L.S=S;
  mods.forEach(function(m){if(m.core)runModule(m);});
  mods.filter(function(m){return !m.core;}).forEach(runModule);
  for(var ns in stateFactories)if(S[ns]==null){var f=stateFactories[ns];S[ns]=typeof f==="function"?f():clone(f);}
  booted=true;
  /* expose S for devtools; guard against modules that replaced S entirely */
  L.render();
  setInterval(tick,250);
  bootHooks.forEach(function(fn){try{fn();}catch(e){logErr("boot hook",e);}});
  L.emit("booted",{});
}
Object.defineProperty(L,"S",{get:function(){return S;},set:function(v){S=v;},configurable:true});
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot);else setTimeout(boot,0);
window.addEventListener("error",function(e){if(e&&e.message)logErr("window",e.message);});
})();
