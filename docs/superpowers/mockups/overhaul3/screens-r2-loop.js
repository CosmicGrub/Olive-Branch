/* screens-r2-loop: Round 2, the core loop made trustworthy (messages and calls).
   Guardian: bank, queue, delivery detail, failure, notifications, push priming, calls, incoming knock, offline.
   Child: faces, player, arrival, reply, draw, who, knock, incoming, in-call, offline, queued, break.
   Sample data only: Ivy (6), Dad, Mom, Gran, Jo. Local parts use the .lp- prefix and live in one injected style block. */
(function(){"use strict";var K=OB,I=K.ico,D=K.def,E=K.esc;

/* ------------------------------------------------------------------ local css -- */
var css=[
".ob:has(.lp-g) .cbtn{width:48px;height:48px}",
".ob:has(.lp-g) .btn.sm{min-height:48px}",
".ob:has(.lp-g) .btn{min-height:48px}",
".ob.child:has(.lp-c) .cbtn{width:64px;height:64px}",
".ob .lp-face{display:inline-block;flex:none;position:relative;border-radius:50%;background:var(--surface)}",
".ob .lp-face svg{display:block;width:100%;height:100%;border-radius:50%}",
".ob .lp-face.glow{box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ok),0 0 26px 10px color-mix(in srgb,var(--ok) 38%,transparent)}",
".ob .lp-face.sel{box-shadow:0 0 0 3px var(--bg),0 0 0 7px var(--pri)}",
".ob .lp-face .lpdot{position:absolute;top:-3px;right:-3px;width:28px;height:28px;border-radius:50%;background:var(--pri);border:4px solid var(--surface)}",
".ob .lp-ft{display:grid;justify-items:center;align-content:start;gap:12px;padding:20px 8px 10px;border-radius:28px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);min-width:0}",
".ob .lp-ft.sel{border:2px solid var(--pri);background:var(--priC)}",
".ob .lp-nm{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:64px;width:100%;padding:0 8px;border-radius:20px;background:var(--priC);color:var(--onPriC);font:800 20px/1 var(--font-display);border:0;white-space:nowrap}",
".ob .lp-ft.sel .lp-nm{background:var(--pri);color:var(--onPri)}",
".ob .lp-say{display:flex;align-items:center;gap:12px;min-height:64px;width:100%;padding:0 18px;border-radius:22px;border:0;background:var(--priC);color:var(--onPriC);font:800 20px/1.1 var(--font-display);text-align:left}",
".ob .lp-say.plain{background:transparent;justify-content:center;text-align:center}",
".ob .lp-poster{position:relative;border-radius:28px;overflow:hidden;aspect-ratio:16/10;box-shadow:var(--shadow2);background:var(--priC);min-width:0}",
".ob .lp-poster.fill{aspect-ratio:auto;flex:1;min-height:0}",
".ob .lp-poster .scene{position:absolute;inset:0;width:100%;height:100%;border-radius:0}",
".ob .lp-pfc{position:absolute;left:12px;top:12px}",
".ob .lp-pfm{position:absolute;left:50%;top:46%;transform:translate(-50%,-50%)}",
".ob .lp-play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);display:grid;place-items:center;border-radius:50%;background:color-mix(in srgb,var(--surface) 94%,transparent);color:var(--pri);box-shadow:var(--shadow2)}",
".ob .lp-full{flex:1;min-height:0;display:flex;flex-direction:column;gap:12px;padding:4px 16px 18px;overflow:hidden}",
".ob .lp-full>*{min-width:0}",
".ob.f-tablet .lp-full.rw{flex-direction:row;align-items:stretch;gap:18px}",
".ob.f-tablet .lp-full.rw>*{flex:1 1 0;min-width:0}",
".ob .lp-col{display:flex;flex-direction:column;gap:12px;min-height:0;min-width:0}",
".ob .lp-col.mid{justify-content:center}",
".ob .lp-rb{display:grid;place-items:center;border-radius:50%;border:0;flex:none;padding:0;cursor:pointer}",
".ob .lp-rb.pri{background:var(--pri);color:var(--onPri);box-shadow:var(--shadow2)}",
".ob .lp-rb.tonal{background:var(--priC);color:var(--onPriC)}",
".ob .lp-rb.ok{background:var(--ok);color:var(--bg);box-shadow:var(--shadow2)}",
".ob .lp-rb.bad{background:var(--bad);color:var(--bg);box-shadow:var(--shadow2)}",
".ob .lp-rb.glass{background:rgba(255,255,255,.16);color:#fff}",
".ob .lp-row3{display:flex;align-items:center;justify-content:center;gap:16px}",
".ob .lp-wave{display:flex;align-items:center;justify-content:center;gap:4px;height:70px}",
".ob .lp-wave i{width:6px;border-radius:4px;background:var(--pri)}",
".ob .lp-wave i.o{background:var(--priC2)}",
".ob .lp-bar{height:16px;border-radius:9px;background:var(--surface3);overflow:hidden}",
".ob .lp-bar i{display:block;height:100%;border-radius:9px;background:var(--pri)}",
".ob .lp-box{border-radius:28px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);overflow:hidden;min-width:0}",
".ob .lp-bgc{background:var(--priC);color:var(--onPriC)}",
".ob .lp-kv{display:flex;gap:10px;align-items:center;justify-content:center;flex-wrap:wrap}",
".ob .lp-th{display:block;flex:none;border-radius:14px;overflow:hidden;position:relative}",
".ob .lp-th .scene{position:absolute;inset:0;width:100%;height:100%;border-radius:0}",
".ob .lp-q{display:flex;gap:12px;align-items:flex-start;padding:10px 0;min-width:0}",
".ob .card>.lp-q+.lp-q,.ob .card>.lp-q+.lp-qx,.ob .card>.lp-qx+.lp-q{border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}",
".ob .lp-q .rtxt{gap:3px}.ob .lp-q .rtxt .chip{justify-self:start;margin-top:3px}",
".ob .lp-qx{padding:0 0 10px 64px}",
".ob .lp-tl{display:grid}",
".ob .lp-tl .st{display:grid;grid-template-columns:28px minmax(0,1fr);gap:12px;position:relative;padding-bottom:16px}",
".ob .lp-tl .st::before{content:'';position:absolute;left:13px;top:30px;bottom:2px;width:2px;background:var(--outline)}",
".ob .lp-tl .st:last-child{padding-bottom:0}.ob .lp-tl .st:last-child::before{display:none}",
".ob .lp-tl .nd{width:28px;height:28px;border-radius:50%;display:grid;place-items:center;background:var(--priC);color:var(--onPriC)}",
".ob .lp-tl .st.done .nd{background:var(--pri);color:var(--onPri)}",
".ob .lp-tl .st.todo .nd{background:var(--surface2);color:var(--ink3);border:1.5px dashed var(--outline)}",
".ob .lp-tl .st.bad .nd{background:var(--bad);color:var(--bg)}",
".ob .lp-tl .st b{display:block;font-size:14.5px}.ob .lp-tl .st small{display:block;font-size:12.5px;color:var(--ink3);margin-top:1px}",
".ob .lp-rule{display:flex;gap:12px;align-items:center;padding:12px 14px;border-radius:18px;border:1.5px solid var(--outline);background:var(--surface);min-height:60px;min-width:0}",
".ob .lp-rule.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC);box-shadow:inset 0 0 0 1px var(--pri)}",
".ob .lp-rule .rtxt small{color:inherit;opacity:1}.ob .lp-rule:not(.on) .rtxt small{color:var(--ink3)}",
".ob .lp-rad{width:22px;height:22px;border-radius:50%;border:2px solid var(--ink3);flex:none;display:grid;place-items:center}",
".ob .lp-rule.on .lp-rad{border-color:var(--pri);background:var(--pri)}.ob .lp-rule.on .lp-rad::after{content:'';width:8px;height:8px;border-radius:50%;background:var(--onPri)}",
".ob .lp-trim{position:relative;height:56px;border-radius:14px;overflow:hidden;background:var(--surface3)}",
".ob .lp-trim .fs{display:flex;height:100%;gap:1px}.ob .lp-trim .fs i{flex:1;background:linear-gradient(var(--priC2),var(--priC))}",
".ob .lp-trim .sh{position:absolute;top:0;bottom:0;background:color-mix(in srgb,var(--surface) 78%,transparent)}",
".ob .lp-trim .hl{position:absolute;top:0;bottom:0;width:20px;background:var(--pri);border-radius:8px;display:grid;place-items:center}",
".ob .lp-trim .hl::after{content:'';width:3px;height:20px;border-radius:2px;background:var(--onPri)}",
".ob .lp-lock{border-radius:20px;background:var(--surface2);padding:12px 14px;display:grid;gap:8px}",
".ob .lp-lock .nt{border-radius:16px;background:var(--surface);box-shadow:var(--shadow1);padding:10px 12px;display:flex;gap:10px;align-items:center}",
".ob .lp-lock .nt b{display:block;font-size:13px}.ob .lp-lock .nt small{color:var(--ink3);font-size:12.5px}",
".ob .lp-hero{background:linear-gradient(165deg,var(--pri),var(--priD));color:var(--onPri)}",
".ob .lp-full.hero{padding-top:6px}",
".ob .lp-canvas{position:relative;border-radius:26px;background:var(--surface);border:2px solid var(--outline);box-shadow:var(--shadow1);overflow:hidden;flex:1;min-height:0}",
".ob .lp-canvas svg{position:absolute;inset:0;width:100%;height:100%}",
".ob .lp-ink{width:64px;height:64px;border-radius:50%;border:0;padding:0;flex:none;box-shadow:inset 0 0 0 3px rgba(255,255,255,.35)}",
".ob .lp-ink.on{box-shadow:0 0 0 4px var(--bg),0 0 0 8px var(--ink)}",
".ob .lp-mode{display:flex;gap:10px}.ob .lp-mode>span{flex:1;min-height:64px;border-radius:22px;background:var(--surface2);color:var(--ink2);display:flex;align-items:center;justify-content:center;gap:8px;font:800 17px var(--font-display)}",
".ob .lp-mode>span.on{background:var(--pri);color:var(--onPri)}",
".ob .lp-slip{border-radius:26px;background:var(--surface);box-shadow:var(--shadow2);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);padding:12px;display:flex;align-items:center;gap:12px}",
".ob .lp-ghost{opacity:.5;filter:saturate(.6)}",
".ob .lp-sys{border:1.5px dashed var(--outline);border-radius:18px;padding:10px 14px;color:var(--ink3);font-size:12.5px;display:flex;gap:10px;align-items:center}",
".ob .lp-big{font:800 28px/1.05 var(--font-display);letter-spacing:-.02em}",
".ob .lp-rings{position:relative;display:grid;place-items:center}",
".ob .lp-rings i{position:absolute;border-radius:50%;border:3px solid var(--priC2)}",
".ob .lp-rings .face{position:relative}",
".ob.f-cover .lp-nm{font-size:16px;gap:5px;padding:0 4px}",
".ob.f-cover .lp-nm svg{width:18px;height:18px}",
".ob .lp-inks{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:6px;justify-items:center}",
".ob .lp-inks .lp-ink{width:100%;max-width:64px;height:auto;aspect-ratio:1}",
".ob .lp-undo{position:absolute;top:10px;right:10px}",
".ob .grid4.lp-g4{gap:10px}"
].join("\n");
var st=document.createElement("style");st.id="lp-css";st.textContent=css;document.head.appendChild(st);

/* --------------------------------------------------------------------- parts -- */
var FACES={
 Mom:{bg:"var(--accentC)",skin:"#e6b48f",hair:"#5a3a2a",shape:"long",cloth:"var(--pri)"},
 Dad:{bg:"var(--priC2)",skin:"#c68e66",hair:"#2f2420",shape:"short",cloth:"var(--accent)"},
 Gran:{bg:"var(--accentC)",skin:"#f0c9a8",hair:"#b9b2ab",shape:"bob",cloth:"var(--priD)"},
 Jo:{bg:"var(--priC)",skin:"#8d5a3b",hair:"#1d1613",shape:"curly",cloth:"var(--info)"},
 Ivy:{bg:"var(--accentC)",skin:"#e0a981",hair:"#7a4a2a",shape:"pig",cloth:"var(--ok)"}};
function face(who,sz,o){o=o||{};var f=FACES[who]||FACES.Mom,back="",front="";
 if(f.shape==="long")back='<path d="M15 36c-3-17 5-26 17-26s20 9 17 26c0 7 2 12 2 12H13s2-5 2-12z" fill="'+f.hair+'"/>';
 if(f.shape==="bob")back='<path d="M16 34c-2-15 5-23 16-23s18 8 16 23c0 4 1 7 1 7H15s1-3 1-7z" fill="'+f.hair+'"/>';
 if(f.shape==="curly")back='<g fill="'+f.hair+'"><circle cx="19" cy="22" r="8"/><circle cx="45" cy="22" r="8"/><circle cx="26" cy="15" r="9"/><circle cx="38" cy="15" r="9"/></g>';
 if(f.shape==="pig")back='<g fill="'+f.hair+'"><circle cx="16" cy="30" r="6.5"/><circle cx="48" cy="30" r="6.5"/></g>';
 front=f.shape==="short"||f.shape==="pig"||f.shape==="curly"||f.shape==="long"||f.shape==="bob"?'<path d="M19.5 29c-1-11 5-16 12.5-16s13.5 5 12.5 16c-3-5-8-8-12.5-8s-9.5 3-12.5 8z" fill="'+f.hair+'"/>':"";
 var svg='<svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="32" fill="'+f.bg+'"/>'+back+'<path d="M7 64c2-14 12-19 25-19s23 5 25 19z" fill="'+f.cloth+'"/><rect x="27.5" y="36" width="9" height="11" rx="3" fill="'+f.skin+'"/><ellipse cx="32" cy="30" rx="12" ry="13" fill="'+f.skin+'"/>'+front+'<circle cx="27" cy="31.5" r="1.7" fill="#2b2220"/><circle cx="37" cy="31.5" r="1.7" fill="#2b2220"/><path d="M27.5 36.5q4.5 3.6 9 0" stroke="#2b2220" stroke-width="1.7" fill="none" stroke-linecap="round"/><circle cx="23.5" cy="35" r="2.2" fill="#e9707a" opacity=".28"/><circle cx="40.5" cy="35" r="2.2" fill="#e9707a" opacity=".28"/></svg>';
 return '<span class="lp-face'+(o.glow?" glow":"")+(o.sel?" sel":"")+'" role="img" aria-label="'+E(who)+'" style="width:'+sz+'px;height:'+sz+'px">'+svg+(o.dot?'<i class="lpdot"></i>':"")+'</span>';}
function ftile(who,o){o=o||{};return '<div class="lp-ft'+(o.sel?" sel":"")+'"'+K.n(o.n)+'>'+face(who,o.size||88,{glow:o.glow,dot:o.dot,sel:o.sel})+'<span class="lp-nm">'+I("volume",22,2)+'<b>'+E(o.label||who)+'</b></span></div>';}
function say(t,o){o=o||{};return '<button class="lp-say'+(o.plain?" plain":"")+'"'+K.n(o.n)+' aria-label="Hear: '+E(t)+'">'+I("volume",26,2)+'<span>'+E(t)+'</span></button>';}
function rb(ic,sz,kind,label,o){o=o||{};return '<button class="lp-rb '+kind+'" style="width:'+sz+'px;height:'+sz+'px" aria-label="'+E(label)+'"'+K.n(o.n)+'>'+(o.html||I(ic,Math.round(sz*.42),2))+'</button>';}
function poster(scene,who,o){o=o||{};return '<div class="lp-poster'+(o.fill?" fill":"")+'"'+K.n(o.n)+'>'+K.scene(scene,300,160)+(who?'<span class="lp-pfc">'+face(who,o.fs||48)+'</span>':"")+(o.inner||"")+'</div>';}
function playBtn(sz){return '<span class="lp-play" style="width:'+sz+'px;height:'+sz+'px">'+I("play",Math.round(sz*.46),2)+'</span>';}
function thumb(scene,sz){return '<span class="lp-th" style="width:'+sz+'px;height:'+sz+'px">'+K.scene(scene,sz,sz)+'</span>';}
function ctop(title,o){o=o||{};return K.sb()+'<i class="lp-c" hidden></i>'+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it"})});}
function gtop(title,o){o=o||{};return K.sb()+'<i class="lp-g" hidden></i>'+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function gtabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],["sliders","Settings"]],a);}
function two(c,l,r,title,fn,tab){if(c.form==="tablet")return fn(title)+'<div class="tw"><div>'+l+'</div><div>'+r+'</div></div>'+(tab||"");return fn(title)+K.page(l+r,{tab:tab});}
function full(c,l,r,o){o=o||{};if(c.form==="tablet"&&r!==undefined)return '<div class="lp-full rw"><div class="lp-col'+(o.m1?" mid":"")+'">'+l+'</div><div class="lp-col'+(o.m2===false?"":" mid")+'">'+r+'</div></div>';return '<div class="lp-full'+(o.cls?" "+o.cls:"")+'">'+l+(r||"")+'</div>';}
function pill(s){var m={queued:["Queued","clock",""],delivering:["Delivering","refresh","info"],delivered:["Delivered","check","pri"],watched:["Watched","eye","ok"],failed:["Didn’t arrive","warn","bad"],started:["Started, not finished","play","warn"]}[s];return K.chip(m[0],{tone:m[2],ic:m[1],sm:true});}
function qrow(t,sub,scene,state,n){return '<div class="lp-q"'+K.n(n)+'>'+thumb(scene,52)+'<span class="rtxt"><b>'+E(t)+'</b><small>'+E(sub)+'</small>'+pill(state)+'</span></div>';}
function tl(items){return '<div class="lp-tl">'+items.map(function(x){return '<div class="st '+x[0]+'"><span class="nd">'+I(x[1],15,2.4)+'</span><span><b>'+E(x[2])+'</b><small>'+E(x[3])+'</small></span></div>';}).join("")+'</div>';}
function rule(t,sub,on,n){return '<div class="lp-rule'+(on?" on":"")+'"'+K.n(n)+'><span class="lp-rad"></span><span class="rtxt"><b>'+E(t)+'</b><small>'+E(sub)+'</small></span></div>';}
function tgl(ic,t,sub,on,n){return K.row({ic:ic,title:t,sub:sub,trail:K.toggle(on),n:n});}
var BARS=[18,30,44,26,52,36,60,40,22,48,64,34,20,42,56,30,16,38,50,24,12];
function wave(done){return '<div class="lp-wave">'+BARS.map(function(h,i){return '<i class="'+(i>done?"o":"")+'" style="height:'+h+'px"></i>';}).join("")+'</div>';}
function ringsOf(who,sz,o){o=o||{};var f=Math.round(sz*.57);return '<div class="lp-rings" style="width:'+sz+'px;height:'+sz+'px;margin:0 auto"><i style="inset:0;opacity:.35"></i><i style="inset:'+Math.round(sz*.1)+'px;opacity:.6"></i><span class="face"'+K.n(o.n)+'>'+face(who,f,{glow:o.glow})+'</span></div>';}
function cloudScene(){return '<svg class="scene" viewBox="0 0 300 150" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="300" height="150" fill="var(--priC)"/><circle cx="238" cy="36" r="17" fill="var(--accent)" opacity=".9"/><circle cx="246" cy="31" r="15" fill="var(--priC)"/><g fill="var(--surface)" opacity=".9"><circle cx="40" cy="30" r="2"/><circle cx="84" cy="20" r="1.6"/><circle cx="196" cy="24" r="1.8"/><circle cx="270" cy="78" r="1.6"/></g><path d="M0 120Q80 98 150 116T300 106V150H0Z" fill="var(--priC2)"/><path d="M0 138Q100 120 190 136T300 130V150H0Z" fill="var(--pri)" opacity=".7"/><path d="M92 104a26 26 0 0 1 6-51 34 34 0 0 1 64-6 28 28 0 0 1 36 28 22 22 0 0 1-6 29z" fill="var(--surface)" stroke="var(--pri)" stroke-width="3" stroke-linejoin="round"/><path d="M127 80q6 5 12 0M157 80q6 5 12 0" stroke="var(--ink2)" stroke-width="3" fill="none" stroke-linecap="round"/><path d="M139 92q9 6 18 0" stroke="var(--ink2)" stroke-width="3" fill="none" stroke-linecap="round"/><path d="M204 52h12l-12 12h12M224 38h8l-8 8h8" stroke="var(--ink2)" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';}

/* ======================================================================= GUARDIAN == */
/* 1 Message banking (live) */
D("lpBank","guardian","Bank a message",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"Record, trim, name, choose when she gets it in words, review. The rule is written as a sentence in her time and yours; nothing is called a schedule or a batch. Banking is live: the message uploads and the queue shows it straight away.",
 notes:[[1,"The take is shown as a picture first. Trimming is a filmstrip with two handles, so a fumbled start or a long tail is one drag."],[2,"The name is for you. Ivy never sees it; she sees your face."],[3,"Three rules, each in a sentence. “When she wakes” is the first time her tablet is opened after her wake time, because the app cannot know she is awake."],[4,"The review says exactly what will happen and what you will see afterwards. One primary action."]],
 r:function(c){
  var l=K.card('<div class="lp-poster" style="box-shadow:none"'+K.n(1)+'>'+K.scene("night",300,160)+'<span class="lp-pfc">'+face("Dad",44)+'</span>'+playBtn(60)+'<span class="chip sm" style="position:absolute;right:10px;bottom:10px;background:rgba(0,0,0,.45);color:#fff">1:46</span></div>'+
   '<div style="margin-top:12px">'+'<div class="lp-trim"><div class="fs">'+new Array(15).join("<i></i>")+'</div><span class="sh" style="left:0;width:6%"></span><span class="sh" style="right:0;width:8%"></span><span class="hl" style="left:5%"></span><span class="hl" style="right:7%"></span></div>'+
   '<div class="row" style="padding:8px 0 0"><span class="rtxt"><small>Trimmed: keeps 1:38 of 1:46</small></span>'+K.btn("Record again",{kind:"ghost",size:"sm",ic:"refresh"})+'</div></div>')+
   K.field("Name it (only you see this)","The moon story",{ic:"pencil",n:2});
  var r=K.sectionLabel("When does Ivy get it?")+rule("At her next bedtime","Tonight, 7:30 PM her time (1:30 PM yours)",true,3)+rule("On a night I choose","Pick a night; she gets it at bedtime",false)+rule("When she wakes","The first time she opens her tablet after 6:30 AM her time",false)+
   K.card('<h4>Review</h4><p>Ivy gets <b>The moon story</b> tonight at 7:30 PM, her time. You will see when it reaches her tablet and when she plays it.</p><p>If her tablet is off then, we keep trying and tell you.</p>',"tint",4)+K.btn("Bank this message",{full:true,ic:"check"});
  return two(c,l,r,"Bank a message",gtop);},
 cover:function(){return gtop("New message")+K.page('<div class="lp-poster" style="aspect-ratio:4/3">'+K.scene("night",300,160)+'<span class="lp-pfc">'+face("Dad",40)+'</span></div><div class="lp-row3" style="padding:2px 0">'+rb("mic",72,"bad","Record",{html:'<span style="width:26px;height:26px;border-radius:50%;background:var(--bg);display:block"></span>'})+'</div>'+K.card(K.row({ic:"moon",title:"At her next bedtime",sub:"Tonight, 7:30 PM her time",go:true}),"flat"));}});

/* 2 Queue */
D("lpQueue","guardian","Banked for Ivy",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"Every banked message by night, each with one honest state. Delivering, delivered and watched are different things and are shown as different things. The panel says plainly that Ivy never sees a queue.",
 notes:[[1,"Ivy never sees this list, a count, or a gap. The statement is on the screen so a guardian does not wonder."],[2,"Five states, each with an icon as well as colour: queued, delivering, delivered, watched, didn’t arrive."],[3,"A failure is loud only here, and always with a way forward."],[4,"An empty night is an invitation, not a reproach."]],
 r:function(c){
  var l=K.banner("pri","Ivy never sees this list, a count, or a gap. A message simply arrives at its time.","eyeoff",1)+K.btn("Bank a message",{full:true,ic:"plus"})+
   K.sectionLabel("Tonight, Sat 7")+K.card(qrow("The moon story","Bedtime, 7:30 PM her time","night","delivering"))+
   K.sectionLabel("Coming up")+K.card(qrow("Counting sheep song","Sun 8, bedtime","hills","queued",2)+'<div class="lp-q" style="opacity:.8">'+'<span class="lp-th" style="width:52px;height:52px;border:1.5px dashed var(--outline);display:grid;place-items:center;color:var(--ink3)">'+I("plus",20,2)+'</span><span class="rtxt"><b>Monday has nothing yet</b><small>Add one when you have a minute</small></span></div>',"",4);
  var r=K.sectionLabel("Earlier")+K.card(qrow("Goodnight from the lake","Fri 6, she played it at 7:04 PM","sea","watched")+qrow("Tell the owl hello","Thu 5, on her tablet, not opened yet","paper","delivered")+qrow("Dad’s silly faces","Wed 4, bedtime","letters","failed",3)+'<div class="lp-qx">'+K.btn("Try again",{size:"sm",ic:"refresh",kind:"tonal"})+'</div>');
  return two(c,l,r,"Banked for Ivy",gtop,gtabs(1));},
 cover:function(){return gtop("Banked",{noBack:true})+K.page(K.banner("pri","Ivy never sees this list.","eyeoff")+K.card(qrow("The moon story","Tonight, 7:30 PM","night","delivering")+qrow("Counting sheep song","Sun 8","hills","queued")+qrow("Dad’s silly faces","Wed 4","letters","failed")+'<div class="lp-qx" style="padding-left:0">'+K.btn("Try again",{size:"sm",ic:"refresh",kind:"tonal",full:true})+'</div>'),{tab:gtabs(1)});}});

/* 3 Delivery detail */
D("lpDetail","guardian","Delivery detail",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"One message, told as a timeline of things that actually happened, each with a time in her clock and yours. “Watched” is defined in one sentence: she played it through.",
 notes:[[1,"Each step is a fact the server received, never a guess. A step that has not happened yet is drawn empty."],[2,"The last step is the strict one: she played it. Not seen, not understood."],[3,"If she stops part-way the timeline says “She started it” and how far she got. It does not say watched."]],
 r:function(c){
  var l=K.card('<div class="row" style="padding:0">'+thumb("sea",56)+'<span class="rtxt"><b>Goodnight from the lake</b><small>For Fri 6, bedtime. 1:41 long</small></span></div>')+
   K.card(tl([["done","mic","Recorded","Thu 5, 2:14 PM yours"],["done","clock","Queued for Friday bedtime","Thu 5, 2:15 PM yours"],["done","device","Delivered to Ivy’s tablet","Fri 6, 6:58 PM her time. The tablet confirmed it holds the video."],["done","eye","She opened it","Fri 6, 7:02 PM her time"],["done","play","She watched it","Fri 6, 7:04 PM her time. Played through, 1:41 of 1:41."]]),"",1);
  var r=K.card('<h4>What “watched” means</h4><p>Ivy played your message through on her tablet. It does not mean she looked at the screen the whole time, or understood it.</p><p>If she stops part-way you will see <b>“She started it, 0:42 of 1:41”</b>, not “watched”.</p>',"tint",2)+
   K.card(K.row({ic:"mic",title:"Ivy sent a voice note back",sub:"Fri 6, 7:06 PM her time. 0:12",go:true,tone:"ok"}))+K.btn("Send this again",{kind:"ghost",full:true,ic:"refresh"});
  return two(c,l,r,"Delivery detail",gtop);}});

/* 4 Failure */
D("lpFail","guardian","Why it didn’t arrive",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"The honest failure screen: what happened, what the system does by itself in order, and what you can do. A message is never marked delivered until her tablet confirms it. The retry timings are proposed.",
 notes:[[1,"The reason is a sentence about the world, never a code. Nothing here blames anyone."],[2,"Automatic steps are listed in the order they run, so a guardian knows nobody needs to babysit it."],[3,"One clear action now. The message is kept safe until it lands."]],
 r:function(c){
  var l=K.banner("bad","Dad’s silly faces did not reach Ivy’s tablet on Wed 4.","warn",1)+K.card('<h4>What happened</h4><p>Her tablet was off, or had no signal, at bedtime. The message is safe on our side and has not been lost.</p><p style="color:var(--ink3);font-size:12.5px">Delivered only counts once her tablet says it holds the video.</p>')+K.btn("Try again now",{full:true,ic:"refresh"})+K.btn("Move to another night",{full:true,kind:"ghost",ic:"calendar"});
  var r=K.sectionLabel("What we do by ourselves")+K.card(K.row({ic:"refresh",title:"Retry",sub:"Again after 10 minutes, then hourly until she wakes",n:2})+K.row({ic:"bell",title:"Wake her tablet",sub:"A quiet nudge with no content, so it checks in"})+K.row({ic:"device",title:"Deliver on her next open",sub:"If it is still waiting, it arrives the first time she opens the app"})+K.row({ic:"chat",title:"Tell you",sub:"You hear when it lands, or if it still hasn’t by morning",tone:"info"}),"",3);
  return two(c,l,r,"Didn’t arrive",gtop);}});

/* 5 Notification settings */
D("lpNotif","guardian","Notifications",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"What can reach you, when, and the promise about what a notification never says. The lock screen only ever says that something is waiting.",
 notes:[[1,"Four things a co-parent actually wants to know, plus the two about messages. Each is one plain row."],[2,"Quiet hours are in your time. Ivy’s knocks can be allowed through; that is its own switch."],[3,"The lock screen shows no message text, no medicine names, no amounts. This is drawn, not just promised."]],
 r:function(c){
  var l=K.sectionLabel("Tell me when")+K.card(tgl("clock","Late notice","The other house says they are running late",true,1)+tgl("letter","New handover note","A note was added for you",true)+tgl("receipt","An expense is waiting for you","It needs your yes or no",true)+tgl("pill","A dose was logged","That a dose was given, never which one",true)+tgl("eye","Ivy played my message","When she watches it through",true)+tgl("warn","A message didn’t arrive","Only when it needs you",true))+
   K.sectionLabel("Quiet hours")+K.card(tgl("moon","Quiet hours","9:30 PM to 6:30 AM, your time",true,2)+tgl("phone","Let Ivy’s knocks through","So a call from her is never silent",true));
  var r=K.card('<h4>What a notification never contains</h4><div class="lp-lock" style="margin-top:8px"><div class="nt">'+K.logo(28)+'<span><b>Olive Branch</b><small>Something new is waiting. Open to see.</small></span></div></div><p>No message text. No names of medicines. No amounts. No pictures. Only that something is waiting.</p>',"",3)+K.card(tgl("lock","Show who it is from on the lock screen","Shows “Ivy” or “Mom”, never what it says",false));
  return two(c,l,r,"Notifications",gtop,gtabs(4));}});

/* 6 Push priming */
D("lpPush","guardian","Before we ask",{grp:"R2 Messages",since:"Round 2",isNew:true,
 desc:"A priming screen shown before the system’s own question, once, at a moment that makes sense. It says what we send and what we never send, and that saying no leaves the app working, just slower to tell you.",
 notes:[[1,"The reason comes first, in the picture and in the headline."],[2,"“Not now” is as large as “Turn on”. Saying no is respected and asked about again only from Settings."],[3,"The system question is shown as a quiet placeholder, not imitated."]],
 r:function(){return gtop("",{noBack:true})+K.page('<div style="margin:0 -2px">'+K.scene("letters",300,150)+'</div><div class="big" style="font-size:26px">Know the moment something arrives</div><p style="color:var(--ink2);margin:0">We can nudge your phone when Ivy plays your message, or when a note needs you.</p>'+K.card(K.row({ic:"check",title:"Only that something is waiting",sub:"Never what it says",tone:"ok",n:1})+K.row({ic:"moon",title:"Quiet at night",sub:"Your hours, your choice",tone:"ok"}))+'<div class="lp-sys">'+I("device",18,2)+'<span>Next, your phone asks you once. Choose Allow.</span></div>'+K.btn("Turn on notifications",{full:true,ic:"bell"})+K.btn("Not now",{full:true,kind:"ghost",n:2})+'<p style="margin:0;text-align:center;color:var(--ink3);font-size:12.5px">Without them, the app checks every few minutes while it is open.</p>');}});

/* 7 Calls and history */
D("lpCalls","guardian","Calls",{grp:"R2 Calls",since:"Round 2",isNew:true,wide:true,
 desc:"Missed and past calls, with the wording that matters: not now is not a decline. Ivy is never shown a refusal, a miss, or a count of tries.",
 notes:[[1,"The promise sits at the top, because the worry a parent has here is what she saw."],[2,"A missed knock has one next step: call her back when she is free."],[3,"Ivy’s side of each row is written out, so you can see what she saw."]],
 r:function(c){
  var l=K.banner("pri","Not now is not a decline. If you choose Later, or can’t pick up, Ivy sees “Dad will call back”. She is never shown “declined”, “missed” or “no answer”.","heart",1)+K.sectionLabel("Today")+K.card(K.row({ic:"phone",title:"Ivy knocked",sub:"7:12 AM her time. You were asleep",tone:"warn",trail:K.chip("Missed",{sm:true,tone:"warn",ic:"clock"}),n:2})+'<div class="lp-qx" style="padding:0 0 10px 50px;color:var(--ink3);font-size:12.5px">Ivy saw: “Dad will call back”</div><div class="lp-qx" style="padding:0 0 4px 0">'+K.btn("Call Ivy",{full:true,ic:"video"})+'</div>',"",0);
  var r=K.sectionLabel("Yesterday")+K.card(K.row({ic:"video",title:"Video call with Ivy",sub:"6:20 PM her time. 12 min",tone:"ok",trail:K.chip("Answered",{sm:true,tone:"ok",ic:"check"})})+K.row({ic:"phone",title:"You chose Later",sub:"4:05 PM. Ivy saw “Dad will call back”",trail:K.chip("Later",{sm:true})})+K.row({ic:"video",title:"You called Ivy",sub:"3:10 PM. She wasn’t free. Nothing was shown to her",trail:K.chip("Didn’t connect",{sm:true}),n:3}));
  return two(c,l,r,"Calls",gtop,gtabs(2));}});

/* 8 Guardian incoming call */
D("lpIncoming","guardian","Ivy is calling",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"A knock from Ivy, shown as a knock: her face, her name, answer or later. Later is a kind answer with a ready sentence for her, not a refusal.",
 notes:[[1,"Her real name and face, from her profile. Never a stand-in."],[2,"Answer is the one large action. Later is equally easy to reach."],[3,"What Ivy will see is stated, so “Later” is never a worry."]],
 r:function(c){var top='<div style="display:grid;gap:8px;justify-items:center"><span class="chip" style="background:rgba(255,255,255,.18);color:inherit">'+I("hand",14,2)+'Knock knock</span>'+ringsOf("Ivy",c.form==="tablet"?150:190,{n:1})+'<div class="big" style="font-size:30px">Ivy is calling</div><small style="opacity:.9;font-size:13px">It is 7:44 AM where she is</small></div>',bt='<div style="display:grid;gap:10px;width:100%"><button class="btn lg full" style="background:var(--ok);color:var(--bg);width:100%"'+K.n(2)+'>'+I("video",22,2)+'Answer</button><button class="btn lg full" style="background:transparent;border:2px solid currentColor;color:inherit;width:100%">Later</button><small style="opacity:.92;font-size:12.5px"'+K.n(3)+'>Later tells Ivy: “Dad will call back”</small></div>';
  if(c.form==="tablet")return K.sb("1:44")+'<i class="lp-g" hidden></i><div class="lp-full rw lp-hero" style="margin:6px 10px 12px;border-radius:30px;padding:16px 20px;align-items:center;text-align:center"><div class="lp-col mid">'+top+'</div><div class="lp-col mid">'+bt+'</div></div>';
  return K.sb("1:44")+'<i class="lp-g" hidden></i><div class="lp-full lp-hero" style="margin:6px 10px 12px;border-radius:30px;padding:26px 18px;align-items:center;justify-content:space-between;text-align:center">'+top+bt+'</div>';},
 cover:function(){return K.sb("1:44")+'<i class="lp-g" hidden></i><div class="lp-full lp-hero" style="margin:4px 8px 10px;border-radius:26px;padding:20px 12px;align-items:center;justify-content:space-between;text-align:center"><div style="display:grid;gap:8px;justify-items:center">'+face("Ivy",96)+'<div class="big" style="font-size:24px">Ivy is calling</div></div><div style="display:grid;gap:10px;width:100%"><button class="btn lg" style="background:var(--ok);color:var(--bg);width:100%">'+I("video",20,2)+'Answer</button><button class="btn lg" style="background:transparent;border:2px solid currentColor;color:inherit;width:100%">Later</button></div></div>';}});

/* 9 Offline guardian */
D("lpGOffline","guardian","Offline, safely",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"What happens when the guardian has no signal: writes are kept on the phone and sent in order, and the screen says what is safe, what has to wait and how it resolves.",
 notes:[[1,"The first words are reassurance, then the count of things waiting, which is fine for a guardian to see."],[2,"Each waiting item shows exactly what it is. Notes keep the time they were written."],[3,"What cannot happen offline is said plainly, so a missing call is not a mystery."]],
 r:function(c){
  var l=K.banner("info","You’re offline. Everything you do is saved on this phone.","wifi",1)+K.card('<h4>2 waiting to send</h4>'+K.row({ic:"letter",title:"Handover note: swim bag is in the hall",sub:"Written 1:12 PM. Waiting for signal",tone:"warn",trail:K.chip("Waiting",{sm:true,tone:"warn",ic:"clock"}),n:2})+K.row({ic:"mic",title:"Message for Ivy: The moon story",sub:"Recorded 1:15 PM. Uploads when you’re back",tone:"warn",trail:K.chip("Waiting",{sm:true,tone:"warn",ic:"clock"})}))+K.btn("Check connection",{full:true,kind:"tonal",ic:"refresh"});
  var r=K.card('<h4>What is safe</h4>'+K.row({ic:"shieldcheck",title:"Nothing is lost",sub:"Even if you close the app",tone:"ok"})+K.row({ic:"clock",title:"Notes keep the time you wrote them",sub:"Not the time they send",tone:"ok"}))+K.card('<h4>What has to wait</h4>'+K.row({ic:"video",title:"Calls with Ivy",sub:"They need a connection",tone:"info",n:3})+K.row({ic:"chat",title:"New messages from Ivy",sub:"They arrive when you’re back",tone:"info"}))+K.card('<h4>How it resolves</h4><p>When you’re back, we send them in the order you wrote them. Each one turns to “Sent” and leaves this list. Anything that can’t send stays here with a reason and a Retry.</p>',"tint");
  return two(c,l,r,"Offline",function(t){return gtop(t,{noBack:true});},gtabs(0));},
 cover:function(){return gtop("Offline",{noBack:true})+K.page(K.banner("info","You’re offline. Everything is saved here.","wifi")+K.card('<h4>2 waiting to send</h4>'+K.row({ic:"letter",title:"Handover note",sub:"Waiting for signal",tone:"warn"})+K.row({ic:"mic",title:"Message for Ivy",sub:"Uploads when back",tone:"warn"}))+K.banner("pri","Nothing is lost. They send in order when you’re back.","shieldcheck"),{tab:gtabs(0)});}});

/* ========================================================================= CHILD == */
/* 10 Messages list */
D("lpCMsgs","child","Messages",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"A row of grown-up faces. A dot on a face means something new from them; no numbers, no list of what she has missed. The newest message waits below as a picture with one big play.",
 notes:[[1,"Faces are the navigation. The name pill reads the name aloud when tapped."],[2,"A dot, never a number. Mom has nothing new and nothing says so."],[3,"The newest message is a picture to press. Older ones are small pictures with no states or marks."]],
 r:function(c){
  var faces='<div class="grid2">'+ftile("Mom",{n:1})+ftile("Dad",{dot:true,n:2})+'</div>';
  var late=say("New from Dad")+poster("night","Dad",{n:3,inner:playBtn(72)})+'<div class="lp-row3" style="justify-content:flex-start;gap:10px">'+[["sea","Mom"],["paper","Dad"],["hills","Mom"]].map(function(p){return '<span class="lp-th" style="width:72px;height:72px;opacity:.9">'+K.scene(p[0],72,72)+'</span>';}).join("")+'</div>';
  if(c.form==="tablet")return ctop("Messages")+full(c,faces,late,{m2:false});
  return ctop("Messages")+K.page(faces+late);}});

/* 11 Player */
D("lpCPlay","child","Dad’s message",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"The message actually plays. A big play button, an optional thick scrubber, captions, and play again. Leaving halfway does not mark it watched; only playing it through does.",
 notes:[[1,"The picture is the message. Controls sit under it, never over his face."],[2,"The scrubber is optional and wordless: no times, no numbers."],[3,"Captions are a button for a grown-up or an early reader. Play again is always there."],[4,"She can go back at any moment. Only playing it through tells Dad she watched it."]],
 r:function(c){
  var pic='<div class="lp-poster fill"'+K.n(1)+'>'+K.scene("night",300,160)+'<span class="lp-pfm">'+face("Dad",c.form==="tablet"?120:104)+'</span></div>';
  var ctl='<div class="lp-bar"'+K.n(2)+'><i style="width:38%"></i></div><div class="lp-row3"'+K.n(3)+'>'+rb("","64","tonal","Captions",{html:'<b style="font:800 17px var(--font-display)">CC</b>'})+rb("pause",92,"pri","Pause")+rb("refresh",64,"tonal","Play again")+'</div>';
  var from=say("From Dad",{plain:true});
  if(c.form==="tablet")return ctop("Dad’s message")+full(c,pic,from+ctl,{m2:true});
  return ctop("Dad’s message")+'<div class="lp-full">'+pic+ctl+'</div>';}});

/* 12 Arrival */
D("lpCArrive","child","Something arrived",{grp:"R2 Messages",since:"Round 2",isNew:true,
 desc:"A message arrives as a soft card that slides in over whatever she is doing. No scrim, no sound that demands, nothing blocks her. If she ignores it, it tucks itself into the Messages tile as a dot.",
 notes:[[1,"Her home keeps working underneath. Nothing is blocked or dimmed."],[2,"The card is a face and a play button. Opening it takes her to the player."],[3,"Later is a clear round button, as easy as play. It is never a mistake to ignore it."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})})+'<i class="lp-c" hidden></i>'+
  '<div style="position:relative;flex:1;min-height:0"><div class="scroll" style="height:100%"><div class="col"><div class="tile hero" style="height:116px"><div class="tbg">'+K.scene("hills",300,150)+'</div></div><div class="grid2"><div class="tile feat" style="min-height:76px"><span class="tic">'+I("chat",24,1.9)+'</span><span class="ttx"><b>Messages</b></span></div><div class="tile feat" style="min-height:76px"><span class="tic">'+I("book",24,1.9)+'</span><span class="ttx"><b>Stories</b></span></div></div></div></div>'+
  '<div class="lp-slip" style="position:absolute;left:14px;right:14px;top:6px;z-index:5"'+K.n(2)+'>'+face("Dad",64,{dot:true})+'<span class="rtxt" style="min-width:0"><b style="font:800 19px var(--font-display)">Dad left you something</b></span>'+rb("play",64,"pri","Play",{n:2})+'</div>'+
  '<div style="position:absolute;left:0;right:0;bottom:12px;display:flex;justify-content:center"'+K.n(3)+'>'+rb("x",64,"tonal","Later")+'</div></div>';}});

/* 13a Reply: record */
D("lpCReply","child","Say hi back",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"Reply with her voice or her face. One big round button: tap to start, tap to stop, or hold. The ring fills as she goes; there are no numbers. When she stops, she can listen, record again, or send.",
 notes:[[1,"Voice or video is two big picture buttons, not a menu."],[2,"The record button is the only thing that wants a press. Tap or hold both work."],[3,"The ring shows how much room is left; no digits, no countdown."]],
 r:function(c){
  var mode='<div class="lp-mode"'+K.n(1)+'><span class="on">'+I("mic",24,2)+'Voice</span><span>'+I("camera",24,2)+'Video</span></div>';
  var pic='<div class="lp-box" style="padding:14px 10px;display:grid;justify-items:center;gap:6px">'+face("Ivy",c.form==="tablet"?64:72)+wave(10)+'</div>';
  var rec='<div class="lp-row3"'+K.n(2)+'><div class="lp-rings" style="width:136px;height:136px"><svg width="136" height="136" viewBox="0 0 136 136" style="position:absolute;inset:0" aria-hidden="true"><circle cx="68" cy="68" r="63" fill="none" stroke="var(--surface3)" stroke-width="7"/><circle cx="68" cy="68" r="63" fill="none" stroke="var(--bad)" stroke-width="7" stroke-linecap="round" stroke-dasharray="396" stroke-dashoffset="238" transform="rotate(-90 68 68)"'+K.n(3)+'/></svg>'+rb("","104","bad","Stop recording",{html:'<span style="width:34px;height:34px;border-radius:9px;background:var(--bg);display:block"></span>'})+'</div></div>';
  var hint='<div class="lp-kv" style="color:var(--ink2)">'+I("hand",26,1.8)+I("arrowR",20,2)+I("mic",26,1.8)+'</div>';
  if(c.form==="tablet")return ctop("Say hi back")+full(c,mode+pic,rec+hint,{m1:true});
  return ctop("Say hi back")+'<div class="lp-full">'+mode+pic+'<div style="flex:1"></div>'+rec+hint+'</div>';}});

/* 13b Reply: review and send */
D("lpCReview","child","Send it to…",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"She listens to her own message, then chooses a face to send it to. Sending is one big button. She can record again without any penalty.",
 notes:[[1,"Her own message, ready to play. Record again is one round button."],[2,"Choosing who is a face tap with a clear ring. There is no group send."],[3,"Send stays calm and large. It works with no signal; the next screens say so without words."]],
 r:function(c){
  var pv='<div class="lp-box" style="padding:12px;display:flex;align-items:center;gap:12px"'+K.n(1)+'>'+rb("play",64,"pri","Play my message")+'<div style="flex:1;min-width:0">'+wave(21).replace('height:70px','')+'</div>'+rb("refresh",64,"tonal","Record again")+'</div>';
  var who='<div class="grid2"'+K.n(2)+'>'+ftile("Mom",{size:72})+ftile("Dad",{size:72,sel:true})+'</div>';
  var send='<button class="btn pri lg full" style="min-height:72px"'+K.n(3)+'>'+I("send",24,2)+'Send to Dad</button>';
  if(c.form==="tablet")return ctop("Send it to…")+full(c,pv,who+send,{m1:true,m2:false});
  return ctop("Send it to…")+K.page(pv+who+send);}});

/* 13c Sent */
D("lpCSent","child","Sent",{grp:"R2 Messages",since:"Round 2",isNew:true,
 desc:"A warm, wordless sent state: her message flying to Dad’s face. No “delivered”, no ticks, no waiting for a read. One round button takes her home.",
 notes:[[1,"The picture does the talking: it went to Dad."],[2,"Nothing here promises he will answer, and nothing counts or rewards."]],
 r:function(){return ctop("",{noBack:true,noSpeak:false})+'<div class="lp-full" style="align-items:center;justify-content:space-between;text-align:center"><div class="lp-poster" style="width:100%;aspect-ratio:16/11"'+K.n(1)+'>'+K.scene("letters",300,160)+'<span style="position:absolute;right:14px;bottom:12px">'+face("Dad",84)+'</span></div><div class="lp-kv" style="color:var(--pri)">'+I("heart",44,1.8)+'</div>'+say("It’s on its way to Dad",{plain:true})+rb("check",96,"pri","Done",{n:2})+'</div>';}});

/* 14 Draw and send */
D("lpCDraw","child","Draw for them",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"A small canvas, four big colours, undo, and a face to send to. Nothing to read and nothing to configure; the drawing goes straight to the grown-up she chooses.",
 notes:[[1,"Four colours only, each with a thick ring when chosen."],[2,"Undo is one round arrow on the canvas. There is no eraser to learn."],[3,"Send goes to Mom or Dad; the chosen face is ringed."]],
 r:function(c){
  var cv='<div class="lp-canvas"'+K.n(1)+'><svg viewBox="0 0 240 280" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><circle cx="186" cy="56" r="26" fill="var(--dpMorning)"/><path d="M0 214Q70 180 130 206T240 196V280H0Z" fill="var(--ok)" opacity=".8"/><rect x="46" y="136" width="96" height="72" rx="5" fill="var(--accent)"/><path d="M36 140L94 92L152 140z" fill="var(--pri)"/><rect x="80" y="166" width="22" height="42" fill="var(--surface)"/><path d="M24 78c16-18 32 10 50-6" fill="none" stroke="var(--info)" stroke-width="7" stroke-linecap="round"/></svg><span class="lp-undo">'+rb("arrowL",64,"tonal","Undo")+'</span></div>';
  var inks='<div class="lp-inks"'+K.n(2)+'>'+[["pri",1],["accent",0],["info",0],["dpMorning",0]].map(function(x){return '<button class="lp-ink'+(x[1]?" on":"")+'" style="background:var(--'+x[0]+')" aria-label="Colour"></button>';}).join("")+'</div>';
  var snd='<div class="lp-row3"'+K.n(3)+'><span>'+face("Mom",64)+'</span><span>'+face("Dad",64,{sel:true})+'</span><button class="btn pri lg" style="flex:1;min-height:72px;min-width:0">'+I("send",22,2)+'Send</button></div>';
  if(c.form==="tablet")return ctop("Draw for them")+full(c,cv,inks+snd,{m2:true});
  return ctop("Draw for them")+'<div class="lp-full">'+cv+inks+snd+'</div>';}});

/* 15 Pick who */
D("lpCWho","child","Who?",{grp:"R2 Calls",since:"Round 2",isNew:true,wide:true,
 desc:"Choose a person to message or to call. Faces she may reach are shown; a soft green glow means that person is free now. There is no text for “busy” and no one is ever greyed out as unavailable.",
 notes:[[1,"Two picture buttons choose what to do: message or call. The chosen one is filled."],[2,"A glow means free now. No glow is not a refusal; the call will still ask kindly."],[3,"Only people a guardian has approved appear. She cannot add anyone."]],
 r:function(c){
  var mode='<div class="lp-mode"'+K.n(1)+'><span>'+I("mail",24,2)+'Message</span><span class="on">'+I("video",24,2)+'Call</span></div>';
  var faces='<div class="grid2"'+K.n(2)+'>'+ftile("Mom",{glow:true,n:2})+ftile("Dad")+ftile("Gran",{n:3})+ftile("Jo")+'</div>';
  if(c.form==="tablet")return ctop("Who?")+'<div class="lp-full">'+mode+'<div class="grid4 lp-g4"'+K.n(2)+'>'+ftile("Mom",{glow:true,size:72,n:2})+ftile("Dad",{size:72})+ftile("Gran",{size:72,n:3})+ftile("Jo",{size:72})+'</div></div>';
  return ctop("Who?")+K.page(mode+faces);}});

/* 16 Knock */
D("lpCKnock","child","Knocking",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"She tapped Mom’s face and it rings softly. Soft rings around Mom’s picture show it is trying; nothing counts down and she can stop any time.",
 notes:[[1,"Mom’s real face and name. Quiet rings, still, no pulsing."],[2,"One big round stop. Stopping is fine and says nothing."]],
 r:function(c){var tab=c.form==="tablet";if(tab)return ctop("")+full(c,ringsOf("Mom",210,{n:1}),say("Knocking on Mom",{plain:true})+'<div class="lp-row3">'+rb("x",80,"tonal","Stop",{n:2})+'</div>',{});return ctop("")+'<div class="lp-full" style="align-items:center;justify-content:space-between;text-align:center">'+ringsOf("Mom",230,{n:1})+say("Knocking on Mom",{plain:true})+rb("x",80,"tonal","Stop",{n:2})+'</div>';}});

/* 16b Will call back */
D("lpCCallback","child","Mom will call back",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"When a grown-up chooses Later or can’t pick up, Ivy sees a kind picture and the words “Mom will call back”. Never “declined”, “missed” or “no answer”. Something gentle to do while she waits.",
 notes:[[1,"The same sentence for every reason. It never says why."],[2,"Two things she can do now: draw, or leave a message."]],
 r:function(){return ctop("")+'<div class="lp-full" style="align-items:center;text-align:center"><div class="lp-box lp-bgc" style="width:100%;padding:18px 10px;display:grid;justify-items:center;gap:8px"'+K.n(1)+'>'+face("Mom",96)+'<div class="lp-kv">'+I("clock",30,1.8)+I("arrowR",24,2)+I("phone",30,1.8)+'</div></div>'+say("Mom will call back",{plain:true})+'<div class="grid2" style="width:100%"'+K.n(2)+'>'+[["brush","Draw"],["mail","Message"]].map(function(b){return '<div class="lp-ft" style="padding:14px 6px"><span class="av" style="width:64px;height:64px">'+I(b[0],30,1.8)+'</span><span class="lp-nm" style="font-size:17px;gap:5px;padding:0 4px">'+I("volume",18,2)+'<b>'+b[1]+'</b></span></div>';}).join("")+'</div></div>';}});

/* 16c Is coming */
D("lpCComing","child","Mom is coming",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"When a grown-up taps “coming”, the knock turns into a warm wait. Mom is on her way to the call; Ivy keeps her face and one thing to hold.",
 notes:[[1,"“Coming” and “will call back” look different so she knows which is happening."],[2,"She can wait with Mom’s face or stop; no countdown."]],
 r:function(c){var arr='<div class="lp-kv" style="color:var(--ok)">'+I("arrowR",34,2.2)+I("phone",34,1.8)+'</div>';if(c.form==="tablet")return ctop("")+full(c,ringsOf("Mom",210,{n:1,glow:true}),arr+say("Mom is coming",{plain:true})+'<div class="lp-row3">'+rb("x",80,"tonal","Stop",{n:2})+'</div>',{});return ctop("")+'<div class="lp-full" style="align-items:center;justify-content:space-between;text-align:center">'+ringsOf("Mom",230,{n:1,glow:true})+arr+say("Mom is coming",{plain:true})+rb("x",80,"tonal","Stop",{n:2})+'</div>';}});

/* 17 Incoming to Ivy */
D("lpCIncoming","child","Mom is calling",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"A grown-up is calling Ivy. The caller’s real face and name come from the call itself, not from a default. Answer is one huge button; a quiet round button says not now.",
 notes:[[1,"Real caller, real face. It is whoever is calling, never a hard-coded name."],[2,"Answer is the only big thing."],[3,"Not now is easy and kind; the caller sees “Ivy will call back”, never a refusal."]],
 r:function(c){var nm='<button class="lp-say plain" style="font-size:30px" aria-label="Hear: Mom is calling">'+I("volume",28,2)+'<span>Mom</span></button>',ans='<button class="btn lg full" style="background:var(--ok);color:var(--bg);min-height:96px;font-size:22px"'+K.n(2)+'>'+I("phone",34,2)+'Answer</button>',no='<div class="lp-row3">'+rb("x",64,"tonal","Not now",{n:3})+'</div>';
  if(c.form==="tablet")return ctop("",{noBack:true,noSpeak:true})+'<div class="lp-full rw lp-bgc" style="margin:0 10px 12px;border-radius:30px;align-items:center;padding:18px"><div class="lp-col mid" style="text-align:center">'+ringsOf("Mom",200,{n:1})+nm+'</div><div class="lp-col mid">'+ans+no+'</div></div>';
  return ctop("",{noBack:true,noSpeak:true})+'<div class="lp-full lp-bgc" style="margin:0 10px 12px;border-radius:30px;align-items:center;justify-content:space-between;text-align:center;padding:22px 14px">'+ringsOf("Mom",210,{n:1})+nm+ans+no+'</div>';}});

/* 18 In call */
D("lpCInCall","child","In a call",{grp:"R2 Calls",since:"Round 2",isNew:true,
 desc:"Her in-call view: Mom’s picture is the screen, her own picture is small, and there are two controls. Mute and end. Nothing else is on the screen, and there is no recording.",
 notes:[[1,"Mom’s name and face, from the call."],[2,"Mute and end. End is clearly separate and red."]],
 r:function(){return K.sb()+'<div class="lp-full" style="padding-top:4px"><div style="position:relative;flex:1;min-height:0;border-radius:30px;overflow:hidden;background:linear-gradient(160deg,#2a3f55,#121b26)"'+K.n(1)+'><div style="position:absolute;inset:0;display:grid;place-items:center">'+face("Mom",124)+'</div><span class="chip" style="position:absolute;top:12px;left:12px;background:rgba(0,0,0,.4);color:#fff">Mom</span><div style="position:absolute;right:12px;bottom:12px;width:72px;height:96px;border-radius:20px;background:linear-gradient(160deg,var(--pri),var(--priD));box-shadow:var(--shadow2)"></div></div><div class="lp-row3"'+K.n(2)+'>'+rb("mic",72,"tonal","Mute")+rb("","88","bad","End call",{html:'<span style="transform:rotate(135deg);display:grid">'+I("phone",36,2)+'</span>'})+'</div></div>';}});

/* 19 Child offline */
D("lpCOffline","child","No signal",{grp:"R2 Messages",since:"Round 2",isNew:true,wide:true,
 desc:"With no signal she sees a sleepy cloud, not an error. Below it, the things she can still do on this tablet: draw, colour, play together here. Messages find her when the signal returns.",
 notes:[[1,"A picture, no words, no code, no warning colours."],[2,"Three real things to do, all of which work with no signal."],[3,"Nothing says she is offline or has missed anything."]],
 r:function(c){
  var pic='<div class="lp-poster"'+K.n(1)+'>'+cloudScene()+'</div>';
  var acts='<div class="grid3"'+K.n(2)+'>'+[["brush","Draw"],["palette","Colour"],["dice","Play"]].map(function(b){return '<div class="lp-ft" style="padding:14px 4px 6px;gap:8px"><span class="av" style="width:56px;height:56px">'+I(b[0],28,1.8)+'</span><span class="lp-nm" style="padding:0 2px;gap:4px;font-size:15px;min-height:64px">'+I("volume",16,2)+'<b>'+b[1]+'</b></span></div>';}).join("")+'</div>';
  if(c.form==="tablet")return ctop("")+full(c,pic,acts,{m1:true,m2:true});
  return ctop("")+'<div class="lp-full">'+pic+'<div style="flex:1"></div>'+acts+'</div>';}});

/* 20 Queued reply */
D("lpCQueued","child","Waiting for signal",{grp:"R2 Messages",since:"Round 2",isNew:true,
 desc:"Her reply is saved on the tablet and will go by itself. The picture shows her message sitting snug in an envelope with a small cloud; nothing reads as an error and there is nothing to retry.",
 notes:[[1,"The envelope is held, not lost. A soft cloud says “when the sky clears”."],[2,"No retry button and no error. It goes by itself."]],
 r:function(){return ctop("")+'<div class="lp-full" style="align-items:center;justify-content:space-between;text-align:center"><div class="lp-poster" style="width:100%;aspect-ratio:16/11"'+K.n(1)+'>'+K.scene("letters",300,160)+'<span style="position:absolute;left:12px;top:12px;width:58px;height:58px;border-radius:50%;background:var(--surface);color:var(--ink2);display:grid;place-items:center;box-shadow:var(--shadow1)">'+I("cloud",30,1.8)+'</span><span style="position:absolute;right:14px;bottom:12px;opacity:.85">'+face("Dad",76)+'</span></div>'+say("It will go when the signal comes back",{plain:true})+rb("check",96,"pri","OK",{n:2})+'</div>';}});

/* 21 Break */
D("lpCBreak","child","Rest time",{grp:"R2 Calls",since:"Round 2",isNew:true,wide:true,
 desc:"The tablet is resting for a break. A big picture message from a grown-up sits on top, and two big faces call Mom or Dad in one tap. Nothing tiny, and nothing only a grown-up can reach.",
 notes:[[1,"A picture from a grown-up is the message; it takes the room."],[2,"Calling Mom or Dad is always one tap, even while it rests."],[3,"No settings, no timer and no unlock code on her side."]],
 r:function(c){
  var pic='<div class="lp-poster"'+K.n(1)+'>'+K.scene("paper",300,160)+'<span class="lp-pfc">'+face("Dad",56)+'</span><span style="position:absolute;right:12px;bottom:10px;width:54px;height:54px;border-radius:50%;background:var(--surface);color:var(--pri);display:grid;place-items:center;box-shadow:var(--shadow1)">'+I("moon",28,1.8)+'</span></div>';
  var calls='<div class="grid2"'+K.n(2)+'>'+ftile("Mom",{size:72,glow:true})+ftile("Dad",{size:72})+'</div>';
  if(c.form==="tablet")return ctop("")+full(c,pic+say("Dad drew you a picture",{plain:true}),calls,{m1:true,m2:true});
  return ctop("")+'<div class="lp-full">'+pic+say("Call Mom or Dad",{plain:true})+calls+'</div>';}});

})();
