/* LIVE module: SHELL. Device frames, status bars (virtual time), guardian home / More / Settings, child home scaffold. SIMULATION: no real server. */
LIVE.module("shell",function(L){
"use strict";
var K=window.OB,S=L.S,esc=L.esc;

/* ------------------------------------------------------- shared UI helpers -- */
L.ui={
  empty:function(o){return K.emptyState(o||{});},
  loading:function(kind,n){return K.skeleton(kind||"row",n||3);},
  error:function(o){return K.errorState(o||{});},
  /* a one-line page header; dev 'k' gets bigger type from the .child class */
  top:function(c,title,o){o=o||{};return K.top({back:o.back!==false&&L.S.dev[c.dev].stack.length>1,title:title,eyebrow:o.eyebrow,right:o.right});}
};
var stateLines=[];
/* L.stateLine(fn(c)) : modules add a line for the guardian home; first non-empty (by priority, lower first) wins */
L.stateLine=function(fn,priority){stateLines.push({fn:fn,p:priority==null?50:priority});stateLines.sort(function(a,b){return a.p-b.p;});};
function custodian(){var f=S.family;return L.guardian(f.custody.with)||f.guardians[0];}
function builtinState(c){
  var f=S.family,ch=f.child,nm=ch.name||"Your child",kd=S.dev.k;
  if(!kd.paired)return nm+"’s tablet isn’t connected yet. Add it when you are ready.";
  if(!L.online("k"))return nm+"’s tablet is offline. Anything you send waits safely until it is back.";
  var tz=L.homeTz(),part=L.dayPart(S.clock.t,tz),who=custodian(),w="";
  if(who&&f.guardians.length>1)w=" with "+(who.id===L.gid(c.dev)?"you":who.name)+" this week";
  var txt={ "Night":"It is night for her, and she should be asleep.","Early morning":"It is early morning for her.","Morning":"It is morning for her.","Afternoon":"It is afternoon for her.","Evening":"It is evening for her.","Bedtime":"It is bedtime for her."}[part];
  return nm+" is home"+w+". "+txt;}
L.stateText=function(c){for(var i=0;i<stateLines.length;i++){try{var s=stateLines[i].fn(c);if(s)return s;}catch(e){L.logErr("stateLine",e);}}return builtinState(c);};

/* ----------------------------------------------------------- device frames -- */
var FORMS={g:[["cover","Cover"],["phone","Phone"],["foldMain","Open"]],k:[["tablet","Tablet"],["phone","Phone width"]]};
var frameBuilt={g:null,k:null};
function sizeOf(form){return (K.FORMS[form]||K.FORMS.phone);}
function captionHtml(dev){
  var f=S.family,d=S.dev[dev],name=dev==="g"?(L.me("g")?L.me("g").name:"Guardian phone"):(f.child.name?f.child.name+"’s tablet":"Child tablet");
  var forms=FORMS[dev].map(function(x){return '<button type="button" class="pb sm" data-sact="form" data-dev-s="'+dev+'" data-v="'+x[0]+'" aria-pressed="'+(S.ui.form[dev]===x[0])+'">'+x[1]+'</button>';}).join("");
  return '<b>'+esc(dev==="g"?"Guardian phone":"Child tablet")+'</b>'+(name!=="Guardian phone"&&name!=="Child tablet"?'<span>'+esc(name)+'</span>':"")+
    '<span class="crow" role="group" aria-label="'+(dev==="g"?"Phone screen":"Tablet size")+'">'+forms+'</span>';}
function buildFrame(dev){
  var form=S.ui.form[dev],sz=sizeOf(form),box=document.getElementById("frame-"+dev);if(!box)return;
  if(!box.firstChild){
    box.innerHTML='<div class="fw"><div class="fd"><div class="ob-host" data-host="'+dev+'"></div></div></div>';}
  var fw=box.firstChild,fd=fw.firstChild;
  fd.className="fd "+form;fd.style.width=(sz[0]+14)+"px";fd.style.height=(sz[1]+14)+"px";
  frameBuilt[dev]=form;}
function layout(){
  var stage=document.getElementById("stage");if(!stage)return;
  var avail=stage.clientWidth-28,view=S.ui.view,wide=window.innerWidth>=900;
  var gShow=view!=="k",kShow=view!=="g";
  document.getElementById("col-g").hidden=!gShow;document.getElementById("col-k").hidden=!kShow;
  var wg=sizeOf(S.ui.form.g)[0]+14,wk=sizeOf(S.ui.form.k)[0]+14,scale={};
  if(gShow&&kShow&&wide){var s=Math.min(1,(avail-24)/(wg+wk));scale.g=scale.k=s;}
  else{scale.g=Math.min(1,avail/wg);scale.k=Math.min(1,avail/wk);}
  ["g","k"].forEach(function(dev){var box=document.getElementById("frame-"+dev);if(!box||!box.firstChild)return;
    var sz=sizeOf(S.ui.form[dev]),s=scale[dev],fw=box.firstChild,fd=fw.firstChild;
    fw.style.width=Math.round((sz[0]+14)*s)+"px";var col=document.getElementById("col-"+dev);if(col)col.style.width=Math.max(Math.round((sz[0]+14)*s),230)+"px";fw.style.height=Math.round((sz[1]+14)*s)+"px";fd.style.transform="scale("+s+")";});
}
function viewbar(){var vb=document.getElementById("viewbar");if(!vb)return;
  var h=[["both","Both devices"],["g","Guardian only"],["k","Child only"]].map(function(x){return '<button type="button" class="pb" data-sact="view" data-v="'+x[0]+'" aria-pressed="'+(S.ui.view===x[0])+'">'+x[1]+'</button>';}).join("");
  if(vb.getAttribute("data-h")!==h){vb.innerHTML=h;vb.setAttribute("data-h",h);}}
function shellSync(){
  ["g","k"].forEach(function(dev){
    if(frameBuilt[dev]!==S.ui.form[dev])buildFrame(dev);
    var cap=document.getElementById("cap-"+dev);if(cap){var h=captionHtml(dev);if(cap.getAttribute("data-h")!==h){var had=document.activeElement&&cap.contains(document.activeElement)?document.activeElement.getAttribute("data-v"):null;cap.innerHTML=h;cap.setAttribute("data-h",h);if(had){var n=cap.querySelector('[data-v="'+had+'"]');if(n)n.focus();}}}});
  viewbar();layout();}
document.addEventListener("click",function(ev){
  var b=ev.target.closest&&ev.target.closest("[data-sact]");if(!b)return;
  var a=b.getAttribute("data-sact"),v=b.getAttribute("data-v");
  if(a==="form"){var dev=b.getAttribute("data-dev-s");L.update(function(S){S.ui.form[dev]=v;});}
  if(a==="view"){L.update(function(S){S.ui.view=v;});}
});
window.addEventListener("resize",layout);
if(window.ResizeObserver){var ro=new ResizeObserver(function(){layout();});var st=document.getElementById("stage");if(st)ro.observe(st);}
["g","k"].forEach(buildFrame);
L.afterRender.push(shellSync);
shellSync();

/* ---------------------------------------------------------------- status bar -- */
L.hooks.statusBar=function(c){
  var dev=c.dev,tz=dev==="g"?((L.me("g")&&L.me("g").tz)||S.family.homeTz):L.homeTz(),d=S.dev[dev],on=L.online(dev);
  var bat=Math.round(d.battery);
  return '<div class="sb" role="presentation"><span><span data-clock="time|'+tz+'">'+L.fmt.time(S.clock.t,tz)+'</span>'+K.sr("Simulated time")+'</span>'+
    '<span class="sbi">'+(d.locked&&dev==="k"?'<span title="Locked in" aria-label="Locked to this app" role="img" style="display:inline-flex">'+K.ico("lock",13,2.2)+'</span>':"")+
    (on?'<span role="img" aria-label="Online" style="display:inline-flex">'+K.ico("wifi",13,2)+'</span>':'<span role="img" aria-label="Offline" style="display:inline-flex;color:var(--bad)">'+K.ico("wifioff",13,2.2)+'</span>')+
    '<span aria-label="Battery '+bat+' percent" role="img" style="display:inline-flex;align-items:center;gap:3px"><i class="bat"></i><span class="tnum" style="font-size:10px">'+bat+'</span></span></span></div>';
};
/* batteries drain slowly with virtual time and "plug in" overnight */
L.every(20*60000,function(){["g","k"].forEach(function(d){var v=S.dev[d];v.battery=v.battery<=9?100:v.battery-1;});},"battery");

/* ------------------------------------------------------------- guardian home -- */
function g_tabs(active){return L.tabbar("g",[{ic:"home",label:"Home",screen:"home"},{ic:"grid",label:"More",screen:"more"},{ic:"sliders",label:"Settings",screen:"settings"}],active);}
function dualClock(c){
  var f=S.family,her=L.homeTz(),me=L.me(c.dev),mine=(me&&me.tz)||her,nm=f.child.name||"Her";
  var herPart=L.dayPart(S.clock.t,her),myPart=L.dayPart(S.clock.t,mine);
  return '<div class="dual" role="group" aria-label="Her time and your time"><div class="d1"><small>'+esc(nm)+', her time</small><b data-clock="time|'+her+'">'+L.fmt.time(S.clock.t,her)+'</b><span>'+esc(herPart)+' · '+esc(L.tzName(her))+'</span></div>'+
    '<div class="d2"><small>Your time</small><b data-clock="time|'+mine+'">'+L.fmt.time(S.clock.t,mine)+'</b><span>'+esc(L.tzName(mine))+(her===mine?" · same zone":"")+'</span></div></div>';}
function tileGrid(c,area,o){
  o=o||{};var ts=L.tiles(c,{area:area}),h="",hero=ts.filter(function(t){return t.tier==="hero";}),feat=ts.filter(function(t){return t.tier==="featured";}),std=ts.filter(function(t){return !t.tier||t.tier==="standard";});
  hero.forEach(function(t){h+=L.renderTile(c,t);});
  if(feat.length)h+='<div class="grid2">'+feat.map(function(t){return L.renderTile(c,t);}).join("")+'</div>';
  if(std.length)h+=(o.moreLabel?K.sectionLabel(o.moreLabel):"")+'<div class="grid4">'+std.map(function(t){return L.renderTile(c,t);}).join("")+'</div>';
  return {html:h,n:ts.length};}
L.screen("home",{dev:"g",title:"Home",render:function(c){
  var f=S.family,g=L.me("g"),setup="";
  if(!S.dev.k.paired)setup='<div class="card hero warm">'+'<div style="display:flex;gap:12px;align-items:center">'+K.spot("tablet",56)+'<div><b class="t-head">Add '+esc(f.child.name||"your child")+'’s tablet</b><div class="t-cap">Make a 6-digit code here, type it on the tablet.</div></div></div><div style="height:10px"></div>'+L.btn("Make a code","go","ob.addDevice",{full:true})+'</div>';
  var tg=tileGrid(c,"home",{moreLabel:"Also here"});
  var body=tg.n?tg.html:K.emptyState({spot:"leaf",title:"Nothing here yet",sub:"Features appear here as the other parts of the prototype load."});
  return K.top({logo:true,eyebrow:"Hello, "+(g?g.name:"there"),title:"Olive Branch",right:L.iconBtn("sliders","go","settings",{label:"Settings"})})+
    K.page('<div class="card hero warm" style="padding:16px;display:grid;gap:14px"><div class="stateline" role="status">'+esc(L.stateText(c))+'</div>'+dualClock(c)+'</div>'+setup+body+
      '<div class="t-cap" style="text-align:center">SIMULATION: no real server</div>',{tab:g_tabs("home")});
}});
L.screen("more",{dev:"g",title:"More",render:function(c){
  var tg=tileGrid(c,"more");
  var body=tg.n?tg.html:K.emptyState({spot:"leaf",title:"Nothing more yet",sub:"Other features list themselves here."});
  return K.top({title:"More"})+K.page(body,{tab:g_tabs("more")});
}});
var GROUPS=["Her","Family","Safety","Learn","Account"];
L.screen("settings",{dev:"g",title:"Settings",render:function(c){
  var q=String(L.get("ui.q.g")||"").trim().toLowerCase(),f=S.family;
  var all=L.tiles(c,{area:"settings"}),h="";
  if(q)all=all.filter(function(t){var tt=(typeof t.title==="function"?t.title(c):t.title)||"",ss=(typeof t.sub==="function"?t.sub(c):t.sub)||"";return (tt+" "+ss+" "+(t.group||"")).toLowerCase().indexOf(q)>=0;});
  GROUPS.forEach(function(g){
    var rows=all.filter(function(t){return t.group===g;});if(!rows.length)return;
    var ic={Her:"smile",Family:"users",Safety:"shieldcheck",Learn:"book",Account:"user"}[g];
    h+=K.sectionLabel(g==="Her"?(f.child.name||"Her"):g)+'<div class="card" style="padding:4px 14px">'+rows.map(function(t,i){
      var b=L.tileBadge(c,t),title=typeof t.title==="function"?t.title(c):t.title,sub=typeof t.sub==="function"?t.sub(c):t.sub;
      var row=K.row({ic:t.icon||ic,title:title,sub:sub,go:true,trail:b?'<span class="chip warn sm">'+(b===true?"New":b)+'</span>':""});
      return L.withAct(row,t.act||"go",t.act?t.arg:t.screen,t.params?JSON.stringify(t.params):null);}).join("")+'</div>';});
  if(!h)h=q?K.emptyState({spot:"leaf",title:"No settings match “"+q+"”",sub:"Try a shorter word."}):K.emptyState({spot:"leaf",title:"No settings yet",sub:"Settings register themselves as modules load."});
  return K.top({title:"Settings"})+K.page(L.field({label:"Search settings",path:"ui.q.g",ph:"Try “PIN” or “devices”",ic:"search"})+h,{tab:g_tabs("settings")});
}});
/* the shell's own settings rows (GRD adds the rest) */
L.tile({dev:"g",area:"settings",group:"Her",id:"sh.names",title:function(c){return (S.family.child.name||"Her")+" calls you";},sub:function(c){var gid=L.gid("g");return gid?"“"+L.labels.forChild(gid)+"”, her word for you":"";},icon:"heart",screen:"ob.names",order:10});
L.tile({dev:"g",area:"settings",group:"Family",id:"sh.devices",title:"Paired devices",sub:function(){var n=S.family.devices.length;return n+" device"+(n===1?"":"s");},icon:"device",screen:"ob.devices",order:10});
L.tile({dev:"g",area:"settings",group:"Family",id:"sh.add",title:function(){return "Add "+(S.family.child.name||"a")+"’s tablet";},sub:"Make a 6-digit code",icon:"tablet",screen:"ob.addDevice",order:11});
L.tile({dev:"g",area:"settings",group:"Safety",id:"sh.pin",title:"Guardian PIN",sub:"Needed to make pairing codes",icon:"lock",screen:"ob.pinInfo",order:10});
L.tile({dev:"g",area:"settings",group:"Account",id:"sh.session",title:"Sign out",sub:"This phone only",icon:"key",act:"ob.signOut",order:90});
L.screen("ob.pinInfo",{dev:"g",render:function(c){return K.top({back:true,title:"Guardian PIN"})+K.page('<div class="card"><p class="t-body" style="margin:0">Your 4-digit PIN protects pairing codes and sign-in. A child can never make a pairing code. Five wrong tries lock it for 15 minutes.</p></div>',{tab:g_tabs("settings")});}});
L.screen("ob.names",{dev:"g",render:function(c){
  var gid=L.gid("g"),nm=S.family.child.name||"Your child";
  var rows=S.family.guardians.map(function(g){return K.row({ic:"heart",title:g.name+" ("+g.label+")",sub:L.labels.forGuardian(g.id,gid)});}).join("");
  return K.top({back:true,title:nm+" calls you"})+K.page('<div class="card" style="padding:4px 14px">'+rows+'</div><div class="hint-card">Names belong to '+esc(nm)+'. Only she can change what she calls you, from her own tablet.</div>',{tab:g_tabs("settings")});}});

/* --------------------------------------------------------------- child home -- */
function childDots(c){return "";}
function k_greet(c){var nm=S.family.child.name||"friend";var p=L.dayPart(S.clock.t,L.homeTz());
  return p==="Night"||p==="Bedtime"?"Sleepy time, "+nm:p==="Evening"?"Good evening, "+nm:p==="Afternoon"?"Hello, "+nm:"Good morning, "+nm;}
function lockPill(c){return S.dev.k.locked?'<span class="chip sm" role="img" aria-label="This app is locked in">'+K.ico("lock",12,2.2)+'</span>':"";}
/* default child home: picture-first tiles, no counts, no settings. KID replaces it per age band with L.homeVariant. */
function defaultChildHome(c){
  var band=c.band,ts=L.tiles(c,{area:"home"}),more=L.tiles(c,{area:"more"}).length;
  var per=band==="t34"?1:band==="t57"?2:band==="t812"?2:3;
  var h="",hero=ts.filter(function(t){return t.tier==="hero";}),rest=ts.filter(function(t){return t.tier!=="hero";});
  hero.forEach(function(t){h+=L.renderTile(c,t);});
  if(rest.length)h+='<div class="'+(per===1?"":(per===2?"grid2":"grid3"))+'" style="'+(per===1?"display:grid;gap:12px":"")+'">'+rest.map(function(t){return L.renderTile(c,Object.assign({},t,{tier:band==="t1317"?"standard":"featured"}));}).join("")+'</div>';
  if(!ts.length)h=K.emptyState({spot:"leaf",title:"Nothing here yet",sub:""});
  if(more)h+=L.withAct(K.tile("feat",{ic:"sparkle",title:"More for you",sub:""}),"go","more");
  return K.top({title:k_greet(c),right:lockPill(c)})+K.page(h,{});
}
L.screen("home",{dev:"k",title:"Home",render:function(c){
  var v=L.homeVariantFor(c);
  if(v){return v(c);}
  return defaultChildHome(c);
}});
L.screen("more",{dev:"k",title:"More for you",render:function(c){
  var ts=L.tiles(c,{area:"more"});
  var h=ts.length?'<div class="grid2">'+ts.map(function(t){return L.renderTile(c,Object.assign({},t,{tier:"featured"}));}).join("")+'</div>':K.emptyState({spot:"leaf",title:"Nothing here yet",sub:""});
  return K.top({back:true,title:"More for you"})+K.page(h,{});
}});

/* a generic "waiting for the other device" or loading screen modules can use */
L.screen("loading",{dev:"both",render:function(c){return K.top({title:"One moment"})+K.page(K.skeleton("hero",1)+K.skeleton("row",3),{});}});
});
