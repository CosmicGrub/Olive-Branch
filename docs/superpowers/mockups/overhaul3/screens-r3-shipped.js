/* screens-r3-shipped: Round 3, "what is actually built". Premium refinements of the Flutter screens that shipped after Round 2.
   Every screen: OB.def id prefix r3s, group "R3 Shipped: ...". Notes read: Built (what the real code does), Refined (what the design improves), Keeps (the P-rule or rule held).
   Sample data only: Ivy (5, turns 6 on Dec 9), Jess (the signed-in guardian), Marcus (the other guardian). Local classes use the r3- prefix and theme variables only. */
(function(){"use strict";var K=OB,I=K.ico,D=K.def,E=K.esc;

/* ------------------------------------------------------------------ styles -- */
var CSSA=[];function css(s){CSSA.push(s);}
css([
".ob .r3t{padding:8px 16px}",
".ob .r3t .r3b{width:48px;height:48px;border-radius:50%;border:1px solid color-mix(in srgb,var(--outline) 80%,transparent);background:var(--surface);box-shadow:var(--shadow1);display:grid;place-items:center;color:var(--ink);flex:none;padding:0}",
".ob.child .r3t .r3b,.ob.child .r3t .cbtn{width:64px;height:64px}",
".ob .tw.r3>div{grid-auto-rows:max-content}.ob.child .r3t .ttl b{font-size:23px}",
".ob .r3-dvt{width:28px;height:28px;border-radius:50%;background:var(--surface3);color:var(--ink2);display:grid;place-items:center;flex:none}",
".ob .r3 .btn{min-height:48px;white-space:normal;text-align:center;line-height:1.15;padding-top:9px;padding-bottom:9px}",
".ob .r3 .btn.lg{min-height:56px;font-size:16px}",
".ob .r3 .btn.sm{min-height:48px;font-size:14px;border-radius:14px;padding-left:14px;padding-right:14px}",
".ob.child .r3 .btn{min-height:64px;font-size:17px;border-radius:22px}",
".ob .r3 .row{min-height:56px}.ob.child .r3 .row{min-height:72px}",
".ob .r3 .row .rtxt small{overflow-wrap:anywhere}",
".ob .r3 .seg span{min-height:48px;display:grid;place-items:center;padding:0 4px;line-height:1.15}",
".ob .r3 .ff{grid-template-columns:minmax(0,1fr)}.ob .r3 .fc input{width:0;min-width:0}.ob .r3 .fchips{margin:0;padding:0 0 4px}",
".ob .r3 .field{min-height:56px}.ob .r3 .field .fv b{white-space:normal;overflow-wrap:anywhere}",
".ob .r3 .card{min-width:0}",
".ob .r3-eb{display:block;font:700 10.5px/1 var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:var(--ink3);margin-bottom:6px}",
".ob .card.hero .r3-eb,.ob .card.tint .r3-eb{color:inherit;opacity:.8}",
".ob .r3-h{font:800 19px/1.2 var(--font-display);letter-spacing:-.012em;margin:0;color:var(--ink);text-wrap:balance}",
".ob .card.hero .r3-h,.ob .card.tint .r3-h{color:inherit}",
".ob .r3-h2{font:800 15px/1.2 var(--font-display);margin:0}",
".ob .r3-sub{margin:4px 0 0;color:var(--ink2);font-size:13.5px;line-height:1.42}",
".ob .card.hero .r3-sub,.ob .card.tint .r3-sub{color:inherit;opacity:.92}",
".ob .r3-fine{margin:0;color:var(--ink3);font-size:12.5px;line-height:1.4}",
".ob .r3-stack{display:grid;gap:10px;min-width:0}",
".ob .r3-pill{display:inline-flex;gap:5px;align-items:center;padding:4px 10px 4px 8px;border-radius:99px;font:700 12px/1.1 var(--font-body);white-space:nowrap;flex:none;background:var(--surface3);color:var(--ink2)}.ob .r3-pill.w{white-space:normal;flex:0 1 auto;max-width:100%;min-width:0;text-align:left}",
".ob .r3-pill.ok{background:var(--okC);color:var(--ok)}.ob .r3-pill.info{background:var(--infoC);color:var(--info)}.ob .r3-pill.warn{background:var(--warnC);color:var(--warn)}.ob .r3-pill.bad{background:var(--badC);color:var(--bad)}.ob .r3-pill.pri{background:var(--priC);color:var(--onPriC)}",
".ob .r3-seal{display:flex;gap:10px;align-items:center;padding:10px 12px;border-radius:16px;background:var(--surface2);border:1px dashed var(--edge);color:var(--ink2);font-size:12.5px;line-height:1.38}",
".ob .r3-seal .pl{width:30px;height:30px;border-radius:10px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;flex:none}",
".ob .r3-seal b{color:var(--ink)}",
".ob .r3-pl{width:40px;height:40px;border-radius:14px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;flex:none;box-shadow:inset 0 1px 0 var(--hiC)}",
".ob .r3-pl.ac{background:var(--accentC);color:var(--ink)}.ob .r3-pl.ok{background:var(--okC);color:var(--ok)}.ob .r3-pl.warn{background:var(--warnC);color:var(--warn)}.ob .r3-pl.info{background:var(--infoC);color:var(--info)}.ob .r3-pl.quiet{background:var(--surface3);color:var(--ink2)}",
".ob .r3-hero{position:relative;overflow:hidden}",
".ob .r3-hero .art{position:absolute;right:-8px;bottom:-12px;opacity:.95;pointer-events:none}",
".ob .r3-hero .tx{position:relative;max-width:calc(100% - 78px)}",
".ob .r3-call{display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:16px;background:var(--surface);border:1px solid var(--line);border-left:4px solid var(--pri);font-size:13.5px;line-height:1.42;color:var(--ink2)}",
".ob .r3-call.warn{border-left-color:var(--warn)}.ob .r3-call.info{border-left-color:var(--info)}.ob .r3-call.ok{border-left-color:var(--ok)}.ob .r3-call.bad{border-left-color:var(--bad)}",
".ob .r3-call .ico{flex:none;margin-top:1px}",
".ob .r3-li{display:grid;gap:9px;margin:0;padding:0;list-style:none}.ob .r3-li li{display:flex;gap:10px;align-items:flex-start;font-size:13.5px;line-height:1.4;color:var(--ink2)}.ob .r3-li li .ico{margin-top:1px;color:var(--ink3);flex:none}.ob .r3-li.ok li .ico{color:var(--ok)}",
".ob .r3-ta{border:1.5px solid var(--edge);border-radius:16px;background:var(--surface);padding:12px 14px;min-height:76px;font-size:14px;line-height:1.5;color:var(--ink);white-space:pre-wrap;background-image:repeating-linear-gradient(transparent 0 20px,color-mix(in srgb,var(--line) 70%,transparent) 20px 21px);background-position:0 11px}",
".ob .r3-ta.empty{color:var(--ink3)}",
".ob .r3-lab{display:block;font:700 12.5px/1.2 var(--font-body);color:var(--ink2);margin:0 0 6px}",
".ob .r3-two{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px}.ob .r3-two.ff2{grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}.ob .r3-two>*{min-width:0}",
".ob .r3-hd{display:flex;gap:8px;flex-wrap:wrap;align-items:center;justify-content:space-between;min-width:0}.ob .tile{position:relative}.ob .r3-udot{position:absolute;right:12px;top:12px;width:14px;height:14px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px var(--surface)}.ob .r3-sg{min-width:0}.ob .r3-sg .chip,.ob .r3-gc .chip{white-space:normal;text-align:left}.ob .r3-gg>*,.ob .r3-stack>*{min-width:0}.ob .r3-helper>span:nth-child(2){min-width:0}.ob.f-cover .r3-helper{padding:10px;gap:10px}.ob.f-cover .r3-helper .gi{width:48px;height:48px}",
".ob .r3-dim{opacity:.62}",
".ob .r3-ph{border-radius:16px;overflow:hidden;position:relative;background:repeating-linear-gradient(135deg,var(--surface3) 0 9px,var(--surface2) 9px 18px);display:grid;place-items:center;color:var(--ink3);font:700 11px/1.2 var(--font-mono);letter-spacing:.06em;text-transform:uppercase;text-align:center}",
".ob .r3-sw{width:48px;height:48px;border-radius:50%;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)}",
".ob .r3-swbig{width:64px;height:64px;border-radius:22px;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18),inset 0 2px 0 rgba(255,255,255,.28)}",
".ob .r3-kvx{display:grid;gap:0}.ob .r3-kvx>div{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent);font-size:13.5px}.ob .r3-kvx>div:first-child{border-top:0}.ob .r3-kvx dt,.ob .r3-kvx span:first-child{color:var(--ink3)}.ob .r3-kvx b{text-align:right;font-weight:700;color:var(--ink)}",
".ob .r3-dots{display:flex;gap:10px;justify-content:center}.ob .r3-dots i{width:14px;height:14px;border-radius:50%;background:var(--surface3);box-shadow:inset 0 0 0 1px var(--line)}.ob .r3-dots i.f{background:var(--pri);box-shadow:none}",
".ob .r3-seg4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:6px}",
".ob .r3-chk{display:flex;gap:12px;align-items:flex-start;min-height:48px;padding:6px 0}",
".ob .r3-motion{display:flex;gap:8px;align-items:center;padding:8px 12px;border-radius:12px;background:var(--surface2);color:var(--ink3);font:500 11.5px/1.3 var(--font-mono)}",
".ob .r3-sample{display:inline-flex;gap:5px;align-items:center;padding:3px 9px;border-radius:99px;border:1px dashed var(--edge);color:var(--ink3);font:700 11px/1.1 var(--font-mono);letter-spacing:.04em;text-transform:uppercase}"
].join("\n"));

/* ----------------------------------------------------------------- helpers -- */
function top(title,o){o=o||{};return '<div class="top r3t">'+(o.noBack?(o.logo?K.logo(28):""):'<button type="button" class="r3b" aria-label="Back"'+K.n(o.nb)+'>'+I("chevL",20,2)+'</button>')+'<div class="ttl">'+(o.eyebrow?'<small>'+E(o.eyebrow)+'</small>':"")+'<b>'+E(title)+'</b></div>'+(o.right||"")+'</div>';}
function T(title,o){return K.sb()+top(title,o);}
function P(inner,o){o=o||{};return K.page(inner,{cls:"r3"+(o.cls?" "+o.cls:""),tab:o.tab||""});}
function CT(title,o){o=o||{};return K.sb()+top(title,{noBack:o.noBack,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:o.ns})});}
function row(o){return K.row(o);}
function pill(kind,text,ic){return '<span class="r3-pill '+kind+(String(text).length>24?" w":"")+'">'+(ic?I(ic,13,2.2):"")+E(text)+'</span>';}
function eb(t){return '<span class="r3-eb">'+E(t)+'</span>';}
function pl(ic,tone,sz){return '<span class="r3-pl'+(tone?" "+tone:"")+'">'+I(ic,sz||20,1.9)+'</span>';}
function seal(text,ic,n){return '<div class="r3-seal"'+K.n(n)+'><span class="pl">'+I(ic||"lock",16,2)+'</span><span>'+text+'</span></div>';}
function call(text,tone,ic,n){return '<div class="r3-call'+(tone?" "+tone:"")+'"'+K.n(n)+'>'+I(ic||"info",18,2)+'<span>'+text+'</span></div>';}
function li(items,cls){return '<ul class="r3-li'+(cls?" "+cls:"")+'">'+items.map(function(x){return '<li>'+I(x[0],16,2)+'<span>'+x[1]+'</span></li>';}).join("")+'</ul>';}
function grp(label,rows,n){return K.sectionLabel(label)+K.card(rows,"",n);}
function lab(t){return '<span class="r3-lab">'+E(t)+'</span>';}
function ta(text,o){o=o||{};return '<div class="r3-ta'+(text?"":" empty")+'"'+K.n(o.n)+(o.h?' style="min-height:'+o.h+'px"':"")+'>'+(text?E(text):E(o.ph||""))+'</div>';}
function motion(t){return '<div class="r3-motion">'+I("sparkle",13,2)+'<span>Motion: '+E(t)+'</span></div>';}
function ph(label,h,w){return '<div class="r3-ph" style="height:'+h+'px'+(w?';width:'+w+'px':"")+'" role="img" aria-label="'+E(label)+'">'+E(label)+'</div>';}
function nn(n,built,better,keeps){return [n,"Built: "+built+" Refined: "+better+(keeps?" Keeps: "+keeps:"")];}
/* one registry call: adds group, since, isNew, sample-data line and the Dart file in refs */
function S(id,shell,title,grpName,o){o.grp="R3 Shipped: "+grpName;o.since="r3";o.isNew=true;o.desc=(o.desc||"")+" Sample data only.";D("r3s"+id,shell,title,o);}
/* guardian layout: phone/cover = one column (main, then the other states); tablet = two panes (main | other states) */
function lay(c,main,states,title,o){o=o||{};
 if(c.form==="tablet")return T(title,o)+'<div class="tw r3"><div>'+main+'</div><div>'+(states?eb(o.stLabel||"Other states")+states:"")+'</div></div>'+(o.tab||"");
 return T(title,o)+P(main+(states?K.divider(o.stLabel||"Other states")+states:""),{tab:o.tab});}
function clay(c,main,states,title,o){o=o||{};
 var tp=CT(title,o);
 if(c.form==="tablet")return tp+'<div class="tw r3"><div>'+main+'</div><div>'+(states?eb(o.stLabel||"Other states")+states:"")+'</div></div>';
 return tp+P(main+(states?K.divider(o.stLabel||"Other states")+states:""),{cls:"r3c"});}
function gtabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],["sliders","More"]],a);}

/* picture glyphs: the picture library drawn as one calm family (stroke icons, same grid as the kit) */
var PIC={
 "pyjamas":'<path d="M8 4l-5 4 3 3 2-1v10h8V10l2 1 3-3-5-4a4 4 0 01-8 0z"/><path d="M12 12v8"/>',"wake-up":"sun","lights-out":"moon","cuddle":"heart","book":"book","library-book":"book","night-light":'<path d="M9 18h6M10 21h4M12 3a6 6 0 00-3 11v2h6v-2a6 6 0 00-3-11z"/>',
 "breakfast":'<path d="M4 11h16a8 8 0 01-16 0z"/><path d="M9 7c0-1.5 1.5-1.5 1.5-3M14 7c0-1.5 1.5-1.5 1.5-3"/>',
 "teeth":'<path d="M5 20L15 10"/><rect x="13" y="3" width="7" height="7" rx="2.4" transform="rotate(45 16.5 6.5)"/>',
 "toothbrush":'<path d="M5 20L15 10"/><rect x="13" y="3" width="7" height="7" rx="2.4" transform="rotate(45 16.5 6.5)"/>',
 "shoes":'<path d="M3 16c0-3 2-4 4-5l3-5 3 3c2 1 5 2 8 3v4z"/><path d="M3 19.5h18"/>',
 "coat":'<path d="M8 4L4 8v12h16V8l-4-4-4 3z"/><path d="M12 7v13"/>',
 "bag":'<rect x="5" y="8" width="14" height="13" rx="4"/><path d="M9 8V6a3 3 0 016 0v2M9 14h6"/>',
 "get-dressed":'<path d="M8 4l-5 4 3 3 2-1v10h8V10l2 1 3-3-5-4a4 4 0 01-8 0z"/>',
 "song":'<path d="M9 18V6l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>',
 "owl":'<path d="M6 8l3 2h6l3-2v8a6 6 0 01-12 0z"/><circle cx="9.5" cy="12" r="1.5"/><circle cx="14.5" cy="12" r="1.5"/>',
 "teddy":'<circle cx="12" cy="13" r="6"/><circle cx="7" cy="7" r="2.2"/><circle cx="17" cy="7" r="2.2"/><circle cx="10" cy="12" r=".8"/><circle cx="14" cy="12" r=".8"/>',
 "blanket":'<path d="M4 6h16v12H4z"/><path d="M4 10h16M4 14h16"/>',
 "bottle":'<path d="M10 3h4v3l2 3v11a1 1 0 01-1 1H9a1 1 0 01-1-1V9l2-3z"/><path d="M8 14h8"/>',
 "lunch":'<rect x="3" y="8" width="18" height="12" rx="3"/><path d="M8 8V6h8v2M3 13h18"/>',
 "boots":'<path d="M7 3h6v9l6 3v5H6z"/><path d="M6 17h13"/>',
 "glasses":'<circle cx="7" cy="14" r="3.5"/><circle cx="17" cy="14" r="3.5"/><path d="M10.5 14h3M3.5 14L5 8M20.5 14L19 8"/>',
 "door":'<rect x="6" y="3" width="12" height="18" rx="2"/><circle cx="15" cy="12" r=".9" fill="currentColor"/>',
 "hall":'<path d="M4 20V8l8-4 8 4v12M9 20v-7h6v7"/>',
 "my-room":'<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-5h4v5"/>',
 "bed":'<path d="M3 18V8M3 14h18v4M21 14v-3a3 3 0 00-3-3h-7v6"/>',
 "kitchen":'<path d="M6 3v7a3 3 0 006 0V3M9 3v18M17 3c-2 2-2 6 0 8v10"/>',
 "bathroom":'<path d="M4 12h16v3a5 5 0 01-5 5H9a5 5 0 01-5-5zM6 12V6a2 2 0 014 0"/>',
 "garden":'<path d="M12 21v-9M12 12c-4 0-6-2-6-6 4 0 6 2 6 6zM12 14c3 0 5-1.5 5-5-3.5 0-5 1.5-5 5z"/>',
 "window":'<rect x="4" y="4" width="16" height="16" rx="2.5"/><path d="M12 4v16M4 12h16"/>',
 "sunny":"sun","cloudy":"cloud",
 "rainy":'<path d="M7 14a4 4 0 01-.5-8A5.5 5.5 0 0117 6.5 3.8 3.8 0 0117 14z"/><path d="M8 17l-1 3M12 17l-1 3M16 17l-1 3"/>',
 "stormy":'<path d="M7 13a4 4 0 01-.5-7A5.5 5.5 0 0117 5.5 3.8 3.8 0 0117 13z"/><path d="M13 13l-3 4h3l-2 4"/>',
 "windy":'<path d="M3 9h11a3 3 0 10-3-3M3 13h15a3 3 0 11-3 3M3 17h7"/>',
 "foggy":'<path d="M5 9h14M3 13h18M6 17h12"/>',
 "worry-dark":"moon","worry-noise":"volume","worry-apart":'<circle cx="6" cy="12" r="3"/><circle cx="18" cy="12" r="3"/><path d="M10 12h.01M12 12h.01M14 12h.01"/>',
 "worry-new-place":"home","worry-tummy":'<circle cx="12" cy="12" r="8"/><path d="M9 14a4 4 0 006 0M9.5 9.5h.01M14.5 9.5h.01"/>',
 "worry-storm":"cloud","worry-school":"book","worry-dream":"cloud","worry-other":"more",
 "grandparent":"users","aunt-uncle":"users","teacher":"book","friend":"heart","neighbour":"house","counsellor":"chat","sibling":"users","grown-up":"user",
 "sym-i":"user","sym-want":"hand","sym-more":"plus","sym-stop":"stop","sym-help":"hand","sym-hurt":"warn","sym-tired":"moon","sym-play":"dice","sym-yes":"check","sym-no":"x","sym-eat":"breakfast","sym-drink":"bottle","sym-toilet":"bathroom","sym-hug":"heart","sym-look":"eye","sym-all-done":"check2"
};
var PL={"wake-up":"Wake up","breakfast":"Breakfast","get-dressed":"Get dressed","teeth":"Brush teeth","shoes":"Shoes on","coat":"Coat on","bag":"Get my bag","pyjamas":"Pyjamas","book":"A book","song":"A song","cuddle":"A cuddle","lights-out":"Lights out","owl":"Owl","teddy":"Teddy","blanket":"Blanket","night-light":"Night-light","boots":"Rain boots","lunch":"Lunch box","bottle":"Water bottle","toothbrush":"Toothbrush","library-book":"Library book","glasses":"Glasses","door":"The front door","hall":"The hall","my-room":"Your room","bed":"The bed","window":"The window","kitchen":"The kitchen","bathroom":"The bathroom","garden":"The garden","sunny":"Sunny","cloudy":"Cloudy","rainy":"Rainy","stormy":"Stormy","windy":"Windy","foggy":"Foggy","worry-dark":"The dark","worry-noise":"A loud noise","worry-apart":"Being apart","worry-new-place":"A new place","worry-tummy":"A tummy ache","worry-storm":"A big storm","worry-school":"Something at school","worry-dream":"A dream","worry-other":"Something else","grandparent":"Grandparent","aunt-uncle":"Aunt or uncle","teacher":"Teacher","friend":"Family friend","neighbour":"Neighbour","counsellor":"Counsellor","sibling":"Brother or sister","grown-up":"Grown-up","sym-i":"I","sym-want":"want","sym-more":"more","sym-stop":"stop","sym-help":"help","sym-hurt":"hurt","sym-tired":"tired","sym-play":"play","sym-yes":"yes","sym-no":"no","sym-eat":"eat","sym-drink":"drink","sym-toilet":"toilet","sym-hug":"hug","sym-look":"look","sym-all-done":"all done"};
function glyph(id,sz,sw){var g=PIC[id]||id;if(typeof g==="string"&&g.charAt(0)!=="<"){if(PIC[g]&&g!==id)return glyph(g,sz,sw);return I(g,sz||24,sw||1.8);}
 return '<svg class="ico" viewBox="0 0 24 24" width="'+(sz||24)+'" height="'+(sz||24)+'" fill="none" stroke="currentColor" stroke-width="'+(sw||1.8)+'" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'+g+'</svg>';}
css([
".ob .r3-pt{display:grid;justify-items:center;align-content:center;gap:8px;position:relative;min-height:112px;padding:12px 8px;border-radius:26px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);color:var(--ink);min-width:0;text-align:center}",
".ob .r3-pt .gi{width:60px;height:60px;border-radius:21px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;box-shadow:inset 0 1px 0 var(--hiC)}",
".ob .r3-pt b{font:800 14.5px/1.15 var(--font-display);letter-spacing:-.005em;max-width:100%;overflow-wrap:anywhere}",
".ob .r3-pt.sel{border-color:var(--pri);box-shadow:0 0 0 2.5px var(--pri),var(--shadow1)}",
".ob .r3-pt.sel .gi{background:var(--pri);color:var(--onPri)}",
".ob .r3-pt .tk{position:absolute;left:8px;top:8px;width:26px;height:26px;border-radius:50%;background:var(--ok);color:var(--bg);display:grid;place-items:center}",
".ob .r3-pt.soft{opacity:.7}",
".ob .r3-pt .sp{position:absolute;right:6px;top:6px;width:36px;height:36px;border-radius:50%;display:grid;place-items:center;color:var(--ink2)}",
".ob .r3-pg{display:grid;grid-template-columns:repeat(auto-fill,minmax(88px,1fr));gap:10px}",
".ob.f-cover .r3-pg{grid-template-columns:repeat(2,minmax(0,1fr))}",
".ob .r3-quiet{display:flex;gap:10px;align-items:center;justify-content:center;padding:12px 14px;border-radius:18px;background:var(--surface2);color:var(--ink2);font-size:14px;line-height:1.4;text-align:center}"
].join("\n"));
function PT(id,o){o=o||{};return '<div class="r3-pt'+(o.sel?" sel":"")+(o.soft?" soft":"")+'" role="button" tabindex="0" aria-label="'+E(o.label||PL[id]||id)+'"'+K.n(o.n)+'>'+(o.tick?'<span class="tk">'+I("check",15,3)+'</span>':"")+(o.speak===false?"":'<span class="sp">'+I("volume",18,2)+'</span>')+'<span class="gi">'+glyph(id,30,1.8)+'</span><b>'+E(o.label||PL[id]||id)+'</b></div>';}
function quiet(t,ic){return '<div class="r3-quiet">'+I(ic||"leaf",20,1.8)+'<span>'+E(t)+'</span></div>';}

/* ============================================================ SETTINGS AND SAFETY == */
css([
".ob .r3-win{position:relative;height:34px;border-radius:13px;background:var(--surface3);overflow:hidden;box-shadow:inset 0 0 0 1px var(--line)}",
".ob .r3-win .on{position:absolute;top:0;bottom:0;background:var(--pri)}",
".ob .r3-win .tail{position:absolute;top:0;bottom:0;background:linear-gradient(90deg,var(--pri),var(--priC))}",
".ob .r3-win.bad .on{background:var(--bad)}",
".ob .r3-wt{position:relative;height:14px;font:500 9.5px var(--font-mono);color:var(--ink3);margin-top:5px}",
".ob .r3-wt span{position:absolute;transform:translateX(-50%)}.ob .r3-wt span:first-child{transform:none}.ob .r3-wt span:last-child{transform:translateX(-100%)}",
".ob .r3-gnite{display:grid;justify-items:center;gap:14px;text-align:center;padding:10px 6px}",
".ob .r3-gnite .moon{width:96px;height:96px;border-radius:50%;background:radial-gradient(circle at 34% 30%,color-mix(in srgb,var(--dpBed) 40%,#fff),var(--dpBed) 60%,var(--dpNight));color:#fff;display:grid;place-items:center;box-shadow:0 0 0 10px color-mix(in srgb,var(--dpBed) 18%,transparent),var(--shadow2)}",
".ob .r3-gnite p{font:800 22px/1.25 var(--font-display);margin:0;color:var(--ink);text-wrap:balance}",
".ob .r3-wdb{display:flex;gap:10px;align-items:center;padding:14px 16px;border-radius:20px;background:var(--accentC);color:var(--ink);font:700 16px/1.3 var(--font-body);box-shadow:var(--shadow2)}",
".ob .r3-dl{display:flex;gap:10px;align-items:flex-start;padding:10px 0;border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}.ob .r3-dl:first-child{border-top:0}",
".ob .r3-dl .pl{width:32px;height:32px;border-radius:11px;background:var(--surface3);color:var(--ink2);display:grid;place-items:center;flex:none}.ob .r3-dl.sealed .pl{background:var(--priC);color:var(--onPriC)}",
".ob .r3-dl b{display:block;font-size:14px;line-height:1.25}.ob .r3-dl small{display:block;font-size:12.5px;line-height:1.38;color:var(--ink3);margin-top:1px}",
".ob .r3-dlg{border-radius:22px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow2);padding:16px;display:grid;gap:10px}",
".ob .r3-dlg h4{font:800 18px/1.2 var(--font-display);margin:0}.ob .r3-dlg .acts{display:flex;gap:8px;flex-wrap:wrap}.ob .r3-dlg .acts .btn{flex:1 1 110px}",
".ob .r3-toast{display:flex;gap:10px;align-items:center;padding:12px 14px;border-radius:14px;background:var(--ink);color:var(--bg);font-size:13px;line-height:1.35}",
".ob .r3-sr{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:12px;align-items:center;padding:10px 0;border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}.ob .r3-sr:first-child{border-top:0}"
].join("\n"));

function localTag(c){return c.form==="cover"?"":'<span class="r3-dvt" role="img" aria-label="Kept on this device">'+I("device",14,2)+'</span>';}

S("SettingsHub","guardian","Settings hub","Settings and safety",{wide:true,refs:"guardian_settings_hub.dart, guardian_more.dart",
 desc:"The real Settings hub: five groups, every row opens a screen that already exists, a search box and a plain line that her app has none of this. Reached from More, not from a tab bar.",
 notes:[nn(1,"filters every row by title, subtitle and group name as you type.","the search sits first and the match is kept in context, so a result still shows its group.","nothing new is stored by searching."),
  nn(2,"a lock card says Ivy never sees these settings; her app has none, at any depth.","it becomes a quiet shield banner that is always visible, not a footnote.","§8.1: no settings affordance in the child shell."),
  nn(3,"rows whose subtitle ends 'on this device' keep their data on the phone.","one small device mark replaces the repeated sentence, so each row reads in one glance.","local-first (§8.16.4): nothing here is sent."),
  nn(4,"Settings is a hub reached from the guardian More screen. Round 2 drew a fifth Settings tab; the shell was not re-plumbed.","the hub is drawn as built, with a clear back to More.","one place for every choice."),
  nn(5,"Devices and Parental controls say 'needs a live session' when there is no backend.","the denial is honest and in place: a Needs a live session pill and a toast with the real wording.","no setting is faked while offline.")],
 r:function(c){var lt=localTag(c);
  function R(ic,t,s,o){o=o||{};return row({ic:ic,title:t,sub:s,trail:o.t||"",go:true,n:o.n,tone:o.tone});}
  var main=K.field("Search settings","",{ph:"Try “bedtime” or “colour”",ic:"search",n:1})+
   '<div class="card tint"'+K.n(2)+' style="display:flex;gap:12px;align-items:center"><span class="r3-pl" style="background:var(--surface);color:var(--pri)">'+I("lock",20,2)+'</span><span><b style="display:block;font:800 15px/1.25 var(--font-display)">Ivy never sees these settings</b><span class="r3-sub" style="margin:2px 0 0;display:block">Her app has none, at any depth.</span></span></div>'+
   grp("Her",R("palette","Colour and art","Colour of the day, art style, coding activities")+R("footprint","Growing","Time capsule, first times, growing marks",{t:lt,n:3})+R("leaf","How her app looks","A palette, light or dark")+R("eye","Accessibility for her device","Read aloud, motion, spacing, bigger targets, captions")+R("sparkle","Age band","Ivy is 5"))+
   grp("Family",R("shield","Care","Care binder, hospital mode, picture stories, appointment prep",{t:lt})+R("user","Adults and helpers","Invite a co-parent")+R("device","Devices","See and revoke paired devices",{n:5})+R("calendar","Routine and rhythm","Pictures for bedtime, first-then, the bag, a new place",{t:lt})+R("mic","Her voice","Her helpers and symbols; worries only if she shows you",{t:lt})+R("users","Village","Her people in pictures, a story you release, sitter pass, school summary",{t:lt})+R("target","Family compass","Two gentle questions, suggestions, the suites shelf",{t:lt}))+
   grp("Safety",R("key","Guardian PIN","Set or change your PIN")+R("shield","Parental controls","Hide or pace anything Ivy sees")+R("moon","Play window","When games are open, and the bedtime wind-down"))+
   grp("Learn",R("book","Parent Learn choices","Private to you",{t:pill("quiet","Only you","lock")}))+
   grp("Account",R("send","Sign out","Stops notifications on this device")+R("device","Data on this device","What this phone keeps, and clear it")+R("trash","Deletion","What deletion means here, stated first"));
  var st=K.card(K.field("Search settings","bed",{ic:"search"})+'<div style="height:6px"></div>'+eb("Matches")+row({ic:"moon",title:"Play window",sub:"When games are open, and the bedtime wind-down",go:true})+row({ic:"calendar",title:"Routine and rhythm",sub:"Pictures for bedtime, first-then, the bag, a new place",go:true}),"")+
   K.card(K.field("Search settings","zzz",{ic:"search"})+K.emptyState({spot:"leaf",title:"Nothing matches “zzz”",sub:"Try a word like colour, PIN or bedtime."}),"")+
   K.card(eb("With no live session")+row({ic:"device",title:"Devices",sub:"Needs a live session",trail:pill("warn","Needs a live session","wifioff"),n:5,tone:"warn"})+row({ic:"shield",title:"Parental controls",sub:"Needs a live session",trail:pill("warn","Needs a live session","wifioff"),tone:"warn"}),"")+
   '<div class="r3-toast">'+I("info",18,2)+'<span>Paired devices needs a live session — no backend in this preview build.</span></div>'+call("Round 2 drew a Settings tab. The shipped app reaches this hub from More.","info","flag",4)+motion("a row dips 3% under the finger; the toast rises 220 ms and rests 3 s.");
  return lay(c,main,st,"Settings",{noBack:false,eyebrow:"Ivy’s app",stLabel:"Search and no live session"});},
 cover:function(){return T("Settings",{eyebrow:"Ivy’s app"})+P(K.card(row({ic:"palette",title:"Her",go:true})+row({ic:"users",title:"Family",go:true})+row({ic:"shield",title:"Safety",go:true})+row({ic:"book",title:"Learn",go:true})+row({ic:"user",title:"Account",go:true})));}});

S("Accessibility","guardian","Accessibility for her device","Settings and safety",{wide:true,refs:"access_screen.dart, access_settings.dart",
 desc:"Six honest switches for how Ivy’s app reads, moves and alerts, kept on this phone. Captions say plainly that they are not built yet.",
 notes:[nn(1,"the intro says these are kept on this device and only read by her app; on a different phone, set them there too.","a sealed banner leads, so the limit is known before anything is changed.","local-first; no account sync."),
  nn(2,"Read aloud follows her age (on under 8, off from 8) until a guardian overrides it; a button returns to the age default.","the age default is a Following her age pill, and Follow her age again appears only once overridden.","read aloud never starts by itself."),
  nn(3,"Roomier reading adds space between letters, words and lines, text kept left, the same typeface (evidence for special fonts is mixed).","a live preview appears directly under the switch and the honest reason is in the subtitle.","nothing is label or diagnosis."),
  nn(4,"Larger targets raises her buttons from 64 dp to 80 dp.","the cost is stated: fewer tiles fit.","§8.4 target floor."),
  nn(5,"Captions: 'Not built yet. This records that you would like them; nothing shows because of it today.'","a Not built yet pill sits on the row so the switch can’t be mistaken for a working feature.","honest absence, not a fake control."),
  nn(6,"Alerts she can see: a picture and words that stay until she taps, a gentle buzz, nothing sound only, nothing flashes.","the row names all three guarantees in one line.","no flashing, ever.")],
 r:function(c){
  var main=seal("<b>Kept on this device.</b> Only Ivy’s app reads these. If her device is a different phone, set them there too.","device",1)+
   K.card(row({ic:"volume",title:"Read aloud everywhere",sub:"A small speaker on tiles and stories; long-press a tile to hear it. Never starts by itself.",trail:K.toggle(true),n:2})+'<div style="display:flex;gap:8px;align-items:center;padding:0 0 8px 50px">'+pill("pri","Following her age: on under 8","sparkle")+'</div>'+
   row({ic:"pause",title:"Reduce motion",sub:"Anything that moves after a tap just appears instead. Her phone’s own “remove animations” is always respected too.",trail:K.toggle(true)})+
   row({ic:"book",title:"Roomier reading",sub:"More space between letters, words and lines, text kept left. The same typeface: evidence for special “dyslexia fonts” is mixed.",trail:K.toggle(true),n:3})+
   '<div class="card tint" style="margin:0 0 8px 50px;padding:10px 12px"><p style="margin:0;font:700 15px/1.75 var(--font-body);letter-spacing:.05em;word-spacing:.14em">Dad’s story is ready at bedtime.</p></div>'+
   row({ic:"hand",title:"Larger targets",sub:"Her buttons and tiles at least 80 dp instead of 64 dp, for small or unsteady hands. Fewer tiles fit.",trail:K.toggle(false),n:4})+
   row({ic:"cc",title:"Captions",sub:"Not built yet. This records that you would like them; nothing shows because of it today.",trail:K.toggle(true),n:5})+
   '<div style="padding:0 0 8px 50px">'+pill("warn","Not built yet","hourglass")+'</div>'+
   row({ic:"bell",title:"Alerts she can see",sub:"A picture and words that stay until she taps it, with a gentle buzz, so nothing is ever sound only. Nothing flashes.",trail:K.toggle(true),n:6})
   ,"")+K.toast("Saved on this device.",{ic:"check",inline:true});
  var st=eb("If the phone can’t keep it")+K.notice({tone:"warn",title:"Changed for now",text:"Changed for now, but this device could not keep it. It will be lost on restart.",action:"Try again"})+
   eb("After a guardian override")+K.card(row({ic:"volume",title:"Read aloud everywhere",sub:"Set by you. Her age would have it on.",trail:K.toggle(false)})+'<div style="padding:4px 0 2px 50px"><button type="button" class="btn tonal sm">Follow her age again</button></div>')+
   K.banner("info","Her phone’s own accessibility choices are respected as well. These are added, not instead.","info");
  return lay(c,main,st,"Accessibility",{eyebrow:"Ivy’s device",stLabel:"Honest states"});}});

S("PlayWindow","guardian","Play window and wind-down","Settings and safety",{wide:true,refs:"play_window_screen.dart",
 desc:"When Ivy’s games are open, drawn on her day and in her time. Calls and family messages are never affected. The ending is a goodnight in her own frame.",
 notes:[nn(1,"Opens and Rests at are 15-minute steps; the sentence says calls and family messages are never affected.","the window is drawn as a bar on her day so the shape is seen, not decoded from times.","games rest; nothing is taken away."),
  nn(2,"Wind-down is Off, 15 min or 30 min; the last stretch fades toward goodnight and a game in progress can finish.","the fade is drawn as the bar’s soft tail.","no timer or countdown is ever shown to her."),
  nn(3,"a preview card shows exactly what Ivy sees at the wind-down start, with the real sentence and 'Nothing is taken away. Games open again at 3:30 PM.'","the preview is a small night scene with the sentence large, the same frame she gets.","P2: no red, no lock, no count."),
  nn(4,"an invalid window (rests before it opens, or too short for its wind-down) disables Save and says why in words.","the bar turns to a hatched warning tone and the reason sits right under it.","no silent clamping."),
  nn(5,"Round 2 drew a bedtime marker and a note that lengthening is shown to the other guardian; the shipped screen has neither.","drawn as built; flagged in the report for an owner decision.","")],
 r:function(c){
  function bar(from,to,tail,bad){var s=(from/15),e=(to/15);return '<div class="r3-win'+(bad?" bad":"")+'"><span class="on" style="left:'+s*100+'%;width:'+(e-s-tail)*100+'%"></span><span class="tail" style="left:'+(e-tail)*100+'%;width:'+tail*100+'%"></span></div><div class="r3-wt"><span style="left:0">6a</span><span style="left:40%">12p</span><span style="left:80%">6p</span><span style="left:100%">9p</span></div>';}
  var main=K.card(eb("Her day, her time")+'<div'+K.n(1)+'>'+bar(9.5,13,.5/15,false)+'</div><p class="r3-sub">Games open from <b>3:30 PM</b> and rest at <b>7:00 PM</b>. Calls and family messages are never affected.</p>')+
   '<div class="r3-two">'+K.field("Opens","3:30 PM",{ic:"sun"})+K.field("Rests at","7:00 PM",{ic:"moon"})+'</div>'+
   '<div class="r3-stack"><span class="r3-h2">Wind-down</span><div'+K.n(2)+'>'+K.seg(["Off","15 min","30 min"],2)+'</div><p class="r3-fine">The last stretch fades toward goodnight. A game in progress can finish.</p></div>'+
   K.card(eb("What Ivy sees at 6:30 PM")+'<div style="display:flex;gap:12px;align-items:center"'+K.n(3)+'><div style="width:84px;height:64px;border-radius:14px;overflow:hidden;flex:none">'+K.scene("night",84,64)+'</div><p class="r3-h" style="font-size:16px">It’s getting sleepy. One more, then goodnight.</p></div><p class="r3-sub">Nothing is taken away. Games open again at 3:30 PM.</p>',"tint")+
   K.btn("Save play window",{full:true,size:"lg"});
  var st=K.card(eb("A window that can’t be saved")+'<div'+K.n(4)+'>'+bar(9.5,9.9,0,true)+'</div>'+call("This window is not valid yet: games must rest after they open, with room for the wind-down.","bad","warn")+'<div style="height:8px"></div>'+K.btn("Save play window",{full:true,size:"lg",disabled:true}),"")+
   K.toast("Saved.",{ic:"check",inline:true})+K.card(eb("Other refusals, in words")+li([["info","Games have to rest after they open."],["info","That window is too short for its wind-down."],["info","That could not be saved."]]),"flat")+call("Round 2 also drew a bedtime marker and a note that a longer window is shown to the other guardian. The shipped screen has neither.","info","flag",5);
  return lay(c,main,st,"Play window",{eyebrow:"Ivy’s games",stLabel:"Invalid and refusals"});}});

S("Goodnight","child","Goodnight and wind-down","Settings and safety",{wide:true,refs:"play_window_gate.dart, colour_day_logic.dart",
 desc:"What Ivy sees when games rest: a calm Goodnight page, and before it a soft banner in the last stretch. A game in progress can finish.",
 notes:[nn(1,"when the window is resting, the whole games area is replaced by a Goodnight page with an icon and one sentence.","a small moon over her night colours, the sentence large and spoken on tap.","P2: no timer, no lock, no red, nothing taken away."),
  nn(2,"the sentence is 'Games are resting now. They’ll be back tomorrow.'","unchanged copy; only the setting around it is refined.","tomorrow, not 'locked until'."),
  nn(3,"in the wind-down the game stays on screen and a banner sits at the bottom: 'It’s getting sleepy. One more, then goodnight.'","the banner is a warm accent card, never alarm colours, and does not cover the game.","a game in progress can finish."),
  nn(4,"the gate reads the window from this device’s colour store; open means the child is shown as normal.","no extra state: 'open' draws nothing at all.","")],
 r:function(c){
  var main='<div class="card r3-hero" style="background:linear-gradient(180deg,var(--dpNight),color-mix(in srgb,var(--dpBed) 55%,var(--dpNight)));color:#fff;border:0;padding:26px 16px"><div class="r3-gnite"'+K.n(1)+'><span class="moon">'+I("moon",44,1.7)+'</span><p style="color:#fff"'+K.n(2)+'>Games are resting now. They’ll be back tomorrow.</p></div></div>'+K.speak("Hear it")+motion("the moon settles in 340 ms; reduce motion shows it at rest.");
  var st=quiet("When games are open, this page draws nothing at all.","eye")+K.card('<div style="position:relative;height:210px;overflow:hidden;border-radius:16px"><div style="position:absolute;inset:0">'+K.scene("garden",300,210)+'</div><div style="position:absolute;left:10px;right:10px;bottom:10px"><div class="r3-wdb"'+K.n(3)+'>'+I("moon",24,2)+'<span>It’s getting sleepy. One more, then goodnight.</span></div></div></div><p class="r3-fine" style="margin-top:8px"'+K.n(4)+'>The game keeps going underneath.</p>',"flat");
  return clay(c,main,st,"Goodnight",{noBack:true,stLabel:"In the wind-down"});}});

var DATA=[
 ["Private journal","Her entries, text and date. No grown-up can open them (P7).",1],["Her memory box","Pictures and photos she chose to keep, and notes grown-ups left, kept apart.",1],["Growing","Time capsules, first times, pencil marks and which suites are on.",1],["Care binder","Sections, contacts, hospital notes, appointment lists. Never in her app.",1],["Emergency card","Written by a guardian, with its version and full history. Guardian-only.",1],["Picture stories","Stories a guardian wrote and whether each is shown to her.",1],["Family structure","People, homes and the append-only history. Never uploaded.",1],["Feelings weather","Only today’s sky. No history, no count.",1],["Worry box","What she tapped or drew and what she chose to show.",1],["Village","Grandparent page, stories and release, sibling shelf, faces.",1],["Sitter pass and school summary","Guardian side only. Leaves only when you show the screen.",1],["Family compass","Your answers to two gentle questions, and two profiles.",1],["Parent Learn","Your settings and, only if you saved them, reflections and rules.",1],
 ["Wants and needs","The words she typed and what she ticked. No prices (P4).",0],["Saved pictures","Doodles and colourings she kept, as the strokes that make them.",0],["Stories she kept","A story code, title and date. No read counts.",0],["Jokes she starred","The joke and the date. No tallies.",0],["Things she taught","Title, how, and the date. No grade or score.",0],["Collections","Names she added, with the date. No totals.",0],["Growing-up steps","Which steps she reached. Only ever grows.",0],["Today’s colour","The last two weeks, art style and play window. No tally.",0],["Routine and rhythm","Cards, bag list, how the app feels, today’s ticks.",0],["A new place","Room pictures, captions and a short plan. Rooms only.",0],["Her helpers and symbols","Names, pictures, short lines. What she says is never kept.",0],["Accessibility","Five on/off switches and nothing else.",0],["Offline start-up","First name, age in years, welcome tour done.",0],["Waiting to send","Things made offline that are waiting to go.",0]];
function dRows(a,b,sealed){return DATA.slice(a,b).map(function(d){return '<div class="r3-dl'+(sealed?" sealed":"")+'"><span class="pl">'+I(sealed?"lock":"device",16,2)+'</span><span><b>'+E(d[0])+'</b><small>'+E(d[1])+'</small></span></div>';}).join("");}

S("LocalData","guardian","Data on this device","Settings and safety",{wide:true,refs:"clear_local_data_screen.dart, local_services.dart",
 desc:"Everything this phone keeps, in two honest groups: sealed with encryption, and kept plainly. Then the one way to clear it.",
 notes:[nn(1,"a catalogue lists every area the app writes, each with a lock (sealed) or phone icon and a plain line of what is kept and what is deliberately not.","two groups with counts of kinds, not of data, so sealed things are found together.","local-first (§8.16.4); no scores, streaks or counters are stored."),
  nn(2,"five areas (family, growing, care, picture stories, accessibility) have no label in the screen’s name table, so the shipped list shows their raw ids.","drawn with proper names; the missing labels are flagged for a fix.",""),
  nn(3,"'They are never uploaded, never part of the court export.'","this sentence leads the page as the promise it is.","P5: no child data leaves the device."),
  nn(4,"clearing removes everything listed, including the key that seals the private parts, and does not unpair or sign anyone out.","the effect is described before the action, in the same card.","explicit, PIN-gated destruction.")],
 r:function(c){
  var main=K.card('<div style="display:flex;gap:12px;align-items:center">'+pl("device","")+'<p class="r3-h" style="font-size:15.5px"'+K.n(3)+'>Kept here, never uploaded, never in the court export.</p></div><p class="r3-sub">No scores, streaks or counters are stored.</p>',"tint")+
   K.sectionLabel("Sealed with encryption",pill("pri","13 areas"))+K.card(dRows(0,13,true),"",1)+
   K.sectionLabel("Kept on this phone",pill("quiet","14 areas"))+K.card(dRows(13,27,false))+
   K.card('<span class="r3-h2">Clear data on this device</span><p class="r3-sub">Removes everything above, including the key that seals the private parts. It does not unpair this phone or sign anyone out.</p><div style="height:6px"></div>'+K.btn("Clear data on this device",{kind:"danger",full:true,ic:"trash"}),"",4);
  var st=call("Raw ids in the shipped list: <b>family</b>, <b>growing</b>, <b>care</b>, <b>explainers</b>, <b>access</b>. Their labels are missing from the screen’s name table.","warn","flag",2)+K.card(eb("What the shipped list shows today")+li([["info","family"],["info","growing"],["info","care"],["info","explainers"],["info","access"]]),"flat");
  return lay(c,main,st,"Data on this device",{eyebrow:"Account",stLabel:"A mismatch to fix"});}});

S("LocalDataClear","guardian","Clear data: every outcome","Settings and safety",{wide:true,refs:"clear_local_data_screen.dart",
 desc:"The clearing flow, PIN first. Every outcome is shown, including the honest one where this build cannot check the PIN.",
 notes:[nn(1,"a PIN field, then a confirmation: 'Clear everything on this device?' with Keep it and Clear it.","the confirmation names the consequence and why nothing elsewhere is touched, and Keep it is the larger, calmer button.","permanent deletion is the guardian’s act, never the app’s."),
  nn(2,"'Clearing needs your PIN, and there is no way to check it in this build yet (it is checked with the server). Nothing has been cleared.'","a pale warning block, not a disabled-looking form.","no PIN is ever accepted unverified."),
  nn(3,"a wrong PIN says 'That PIN did not match. Nothing was cleared.'","the field clears and focus stays, with no lockout language.","PIN pad keys are shuffled."),
  nn(4,"success: 'Cleared. This phone no longer holds any of the above.' Failure part-way: 'Something stopped the clearing part-way. Try again.'","two clear end states, each with the next step.","")],
 r:function(c){
  var main='<div class="r3-dlg"'+K.n(1)+'><span class="r3-pl warn">'+I("trash",20,2)+'</span><h4>Clear everything on this device?</h4><p class="r3-sub">This removes everything listed here from this phone and cannot be undone. Nothing is removed from anywhere else, because nothing here was ever sent anywhere.</p><div class="acts">'+K.btn("Keep it",{kind:"tonal"})+K.btn("Clear it",{kind:"danger"})+'</div></div>'+
   K.formField({label:"Your PIN",value:"••",hint:"Four digits",error:"",type:"password"})+
   K.card(eb("Wrong PIN")+call("That PIN did not match. Nothing was cleared.","bad","warn",3));
  var st=K.card(eb("This build cannot check a PIN")+call("Clearing needs your PIN, and there is no way to check it in this build yet (it is checked with the server). Nothing has been cleared.","warn","lock",2)+'<div style="height:8px"></div>'+K.btn("Clear data on this device",{full:true,disabled:true}))+
   K.card(eb("Cleared")+K.emptyState({spot:"shield",title:"Cleared",sub:"This phone no longer holds any of the above."}),"",4)+
   K.card(eb("Stopped part-way")+call("Something stopped the clearing part-way. Try again.","bad","warn")+'<div style="height:8px"></div>'+K.btn("Try again",{full:true}),"",4);
  return lay(c,main,st,"Clear data",{eyebrow:"Data on this device",stLabel:"Unavailable, cleared, failed"});}});

/* =============================================================== HER COLOUR == */
var SW={sunny:["#F2B705","#7A5C00","sunny yellow"],tangerine:["#E8730C","#8A4207","orange"],coral:["#F0757E","#8F2C34","coral pink"],bubblegum:["#E056A8","#8A1F62","bright pink"],grape:["#8B6BB1","#4F3670","purple"],sea:["#2F8FC4","#14536F","sea blue"],sky:["#6BB8E8","#175A80","sky blue"],mint:["#5FC9A8","#186853","mint"],grass:["#5AA84A","#2A5722","grass green"],chocolate:["#8A6244","#4E3524","chocolate"],storm:["#7C8698","#3E4653","storm grey"],midnight:["#2B3358","#1B2138","midnight"]};
css([
".ob .r3-dayrow{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:8px}.ob.f-cover .r3-dayrow{grid-template-columns:repeat(4,minmax(0,1fr))}",
".ob .r3-dayrow i{aspect-ratio:1;min-width:44px;border-radius:50%;display:grid;place-items:center;box-shadow:inset 0 0 0 1px rgba(0,0,0,.16);position:relative}",
".ob .r3-dayrow i.sel{box-shadow:0 0 0 3px var(--surface),0 0 0 6px var(--pri)}",
".ob .r3-dayrow i.sel::after{content:\"\";width:10px;height:10px;border-radius:50%;background:#fff;box-shadow:0 0 0 1.5px rgba(0,0,0,.35)}",
".ob .r3-sty{display:flex;flex-wrap:wrap;gap:8px}",
".ob .r3-sty span{display:inline-flex;gap:6px;align-items:center;min-height:44px;padding:0 14px;border-radius:99px;border:1.5px solid var(--edge);background:var(--surface);font:700 13.5px/1 var(--font-body);color:var(--ink2)}",
".ob .r3-sty span.on{background:var(--pri);border-color:var(--pri);color:var(--onPri)}",
".ob .r3-sty span.off{border-style:dashed;color:var(--ink3);background:var(--surface2)}",
".ob .r3-big2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.ob.f-cover .r3-big2{grid-template-columns:1fr}",
".ob .r3-cc{position:relative;min-height:132px;border-radius:26px;display:grid;place-items:center;align-content:center;gap:6px;font:800 20px/1.1 var(--font-display);box-shadow:var(--shadow1),inset 0 2px 0 rgba(255,255,255,.28);overflow:hidden;text-align:center;padding:12px}",
".ob .r3-cc.pk{box-shadow:0 0 0 4px var(--surface),0 0 0 7px var(--pri),var(--shadow2)}",
".ob .r3-stripe{height:4px;border-radius:3px;margin:0 0 4px}",
".ob .r3-ring{width:76px;height:76px;border-radius:50%;padding:4px;flex:none}.ob .r3-ring i{display:block;width:100%;height:100%;border-radius:50%;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)}",
".ob .r3-act{display:flex;gap:12px;align-items:center;min-height:72px;padding:10px 14px;border-radius:24px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);color:var(--ink)}",
".ob .r3-act .gi{width:52px;height:52px;border-radius:18px;display:grid;place-items:center;flex:none;box-shadow:inset 0 1px 0 var(--hiC)}",
".ob .r3-act b{font:800 17px/1.15 var(--font-display);display:block}.ob .r3-act small{display:block;font-size:13px;color:var(--ink3);margin-top:2px}",
".ob .r3-bsk{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}",
".ob .r3-bsk>div{min-height:92px;border-radius:24px;border:2.5px dashed var(--edge);display:grid;place-items:center;align-content:center;gap:4px;font:800 14px/1.1 var(--font-display);color:var(--ink2);text-align:center;background:var(--surface2)}",
".ob .r3-bsk>div.hl{border-color:var(--pri);border-style:solid;background:var(--priC);color:var(--onPriC)}",
".ob .r3-items{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}",
".ob .r3-items>div{min-height:84px;border-radius:22px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);display:grid;place-items:center;position:relative}",
".ob .r3-items>div.sel{box-shadow:0 0 0 3px var(--pri),var(--shadow1)}",
".ob .r3-items>div.gone{opacity:.28;box-shadow:none}",
".ob .r3-board{display:grid;gap:5px;padding:10px;border-radius:24px;background:var(--surface2);box-shadow:inset 0 1px 2px hsl(0 0% 0% / .08)}",
".ob .r3-board i{aspect-ratio:1;border-radius:11px;background:var(--surface);display:grid;place-items:center;box-shadow:inset 0 0 0 1px var(--line);font-style:normal}",
".ob .r3-board i.rock{background:var(--surface3);color:var(--ink3)}.ob .r3-board i.trail{background:var(--priC)}",
".ob .r3-prog{display:flex;flex-wrap:wrap;gap:8px;min-height:60px;padding:10px;border-radius:20px;background:var(--surface);border:1.5px solid var(--edge);align-items:center}",
".ob .r3-prog i{width:48px;height:48px;border-radius:15px;background:var(--pri);color:var(--onPri);display:grid;place-items:center;font-style:normal}",
".ob .r3-prog i.rep{width:auto;padding:0 14px;gap:6px;display:flex;background:var(--accent);color:var(--bg);font:800 14px var(--font-display)}",
".ob .r3-pal{display:flex;gap:12px;justify-content:center}.ob .r3-pal i{width:56px;height:56px;border-radius:50%;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18);position:relative}.ob .r3-pal i.sel{box-shadow:0 0 0 3px var(--surface),0 0 0 6px var(--pri)}",
".ob .r3-px{display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:4px;padding:10px;border-radius:24px;background:var(--surface2)}.ob .r3-px i{aspect-ratio:1;border-radius:7px;background:var(--surface);box-shadow:inset 0 0 0 1px var(--line)}",
".ob .r3-cwrap{display:grid;place-items:center;padding:8px}"
].join("\n"));

function sw(id){return SW[id];}
function critter(color,style,size){
 var c=color,d='color-mix(in srgb,'+c+' 70%,#000)',l='color-mix(in srgb,'+c+' 55%,#fff)',ink='#22282B';
 var sty=style||"sticker",fill=c,fillL=l,stroke="none",sw1=0,extra="",op=1,dash="";
 if(sty==="sticker"){stroke="#fff";sw1=5;}
 if(sty==="crayon"){stroke=d;sw1=3;dash="6 3";op=.88;}
 if(sty==="watercolour"){op=.72;fillL='color-mix(in srgb,'+c+' 80%,#fff)';}
 if(sty==="line"){fill="none";fillL="none";stroke=d;sw1=3.5;}
 if(sty==="paper"){extra='<g transform="translate(4 5)" fill="'+d+'" opacity=".5"><ellipse cx="50" cy="62" rx="30" ry="24"/><circle cx="50" cy="32" r="17"/></g>';}
 var a=' fill="'+fill+'" stroke="'+stroke+'" stroke-width="'+sw1+'" stroke-linejoin="round"'+(dash?' stroke-dasharray="'+dash+'"':"")+' opacity="'+op+'"';
 return '<svg viewBox="0 0 100 100" width="'+size+'" height="'+size+'" role="img" aria-label="A round critter in '+E(sty)+' style" focusable="false">'+extra+'<path d="M30 24L26 6L42 18z"'+a+'/><path d="M70 24L74 6L58 18z"'+a+'/><ellipse cx="50" cy="64" rx="30" ry="24"'+a+'/><circle cx="50" cy="34" r="19"'+a+'/><ellipse cx="50" cy="68" rx="16" ry="13" fill="'+fillL+'" opacity="'+(sty==="line"?0:.9)+'"/><circle cx="43" cy="32" r="3" fill="'+ink+'"/><circle cx="57" cy="32" r="3" fill="'+ink+'"/><path d="M45 41q5 4 10 0" fill="none" stroke="'+ink+'" stroke-width="2" stroke-linecap="round"/></svg>';}
function blob(k,col){var s='<svg viewBox="0 0 48 48" width="44" height="44" aria-hidden="true" focusable="false">';
 if(k==="berry")s+='<circle cx="17" cy="28" r="9" fill="'+col+'"/><circle cx="31" cy="28" r="9" fill="'+col+'"/><circle cx="24" cy="17" r="9" fill="'+col+'"/><circle cx="14" cy="25" r="2.2" fill="#fff" opacity=".6"/><path d="M24 8q3-4 7-4" stroke="#2a5722" stroke-width="3" fill="none" stroke-linecap="round"/>';
 if(k==="fish")s+='<ellipse cx="22" cy="24" rx="15" ry="10" fill="'+col+'"/><path d="M34 24l10-8v16z" fill="'+col+'"/><circle cx="14" cy="22" r="2" fill="#22282B"/>';
 if(k==="drop")s+='<path d="M24 5C16 16 11 22 11 30a13 13 0 0026 0C37 22 32 16 24 5z" fill="'+col+'"/><path d="M18 30a6 6 0 004 6" stroke="#fff" stroke-width="2.4" fill="none" stroke-linecap="round" opacity=".6"/>';
 if(k==="leaf")s+='<path d="M8 38C8 20 20 8 40 8c0 20-12 32-32 30z" fill="'+col+'"/><path d="M10 36L28 18" stroke="#fff" stroke-width="2" opacity=".6"/>';
 if(k==="whale")s+='<path d="M4 28c0-8 8-14 18-14s16 6 18 14c-6 4-14 6-22 4-6-1-10-2-14-4z" fill="'+col+'"/><path d="M40 26l6-8M40 26l6 6" stroke="'+col+'" stroke-width="4" stroke-linecap="round"/><circle cx="12" cy="24" r="1.8" fill="#22282B"/>';
 if(k==="shell")s+='<path d="M24 8c-10 4-16 12-14 22 4 6 10 8 14 8s10-2 14-8c2-10-4-18-14-22z" fill="'+col+'"/><path d="M24 12v26M16 16l4 22M32 16l-4 22" stroke="#fff" stroke-width="1.8" opacity=".55" fill="none"/>';
 return s+'</svg>';}
function dot(id,sz){var s=SW[id];return '<span class="r3-sw" style="background:'+s[0]+';width:'+(sz||48)+'px;height:'+(sz||48)+'px"></span>';}

S("ColourGuardian","guardian","Her colour and art","Her colour",{wide:true,refs:"her_colour_guardian.dart, colour_day_logic.dart, palette_logic.dart",
 desc:"Today’s colour shown as a fact, a guardian’s optional colour day, the daily question, the art styles she can pick between, and a plain you-can and you-can’t.",
 notes:[nn(1,"one neutral sentence ('Today her colour is sea blue.'), the time she chose it and that every device shows it. No mood, no trend, no history.","the swatch is a soft rounded plate with a quiet Fact label, so it can’t be read as a mood.","§8.6.4: a colour is a fact, not a mood."),
  nn(2,"a guardian may set a colour day for today from twelve swatches; it replaces her answer, she is not asked, and clearing hands the question back (her own answer is never deleted).","the twelve swatches sit in a 6-up grid with a check ring and the consequence in one sentence above them.","a colour day is a deliberate act; it never shows as her feeling."),
  nn(3,"Round 2 drew 'You can’t pick or change her colour for her'. The shipped screen has a colour day, which does exactly that for one day.","drawn as built. Flagged for an owner decision: keep the colour day, or remove it to match Round 2.",""),
  nn(4,"two switches: ask which colour she likes more each day (once, in the morning) and coding activities (Path code from 5, Pixel garden from 8).","each switch states its limit in the subtitle; turning the question off keeps her colour as it is.","no streak, no nudge to change."),
  nn(5,"art style plus 'Styles she can pick between'; Pixel opens at 8 and cannot be turned on earlier.","Pixel appears dashed and disabled at 5 with the reason beside it.","the style never changes her colour."),
  nn(6,"You can / You can’t: no reason for her colour, no history, no showing it as how she feels.","drawn as two plain lists in one card.","§8.6.4.")],
 r:function(c){
  var cur="sea";
  function head(over,none){var s=none?null:SW[cur];return K.card('<div style="display:flex;gap:14px;align-items:center"'+K.n(1)+'><span class="r3-swbig" style="background:'+(s?s[0]:"var(--surface3)")+'"></span><div style="min-width:0"><span class="r3-eb" style="margin:0 0 4px">Fact, not a mood</span><b class="r3-h">'+(none?"Ivy has not chosen a colour yet.":(over?"Today her colour is mint.":"Today her colour is sea blue."))+'</b>'+(none?'':'<p class="r3-sub">Chosen at 7:42 AM, her time.'+(over?'':'')+'</p>')+'</div></div>'+(none?'':'<div style="display:grid;gap:4px;margin-top:8px">'+(over?'<p class="r3-fine">'+I("sparkle",12,2)+' This is a colour day you set.</p>':'')+'<p class="r3-fine">'+I("device",12,2)+' Every device Ivy uses shows the same colour.</p></div>'));}
  function dayrow(sel){var ids=Object.keys(SW);return '<div class="r3-dayrow"'+K.n(2)+'>'+ids.map(function(id){return '<i class="'+(id===sel?"sel":"")+'" style="background:'+SW[id][0]+'" role="button" aria-label="Set '+SW[id][2]+' as today’s colour" tabindex="0"></i>';}).join("")+'</div>';}
  var main=head(false)+
   K.card('<h4>A colour day</h4><p>Choose a colour for today. It replaces Ivy’s answer and she is not asked. Clearing it gives the question back to her.</p><div style="height:6px"></div>'+dayrow(""),"")+
   K.card(row({ic:"sun",title:"Ask which colour she likes more each day",sub:"Once a day, in the morning. Turn it off and her colour stays as it is.",trail:K.toggle(true),n:4})+row({ic:"footprint",title:"Coding activities",sub:"Path code from 5, Pixel garden from 8.",trail:K.toggle(true)}),"")+
   K.card('<h4>Art style</h4><p>How pictures are drawn in her activities. It never changes her colour.</p><div class="r3-sty" style="margin:8px 0 12px"'+K.n(5)+'><span class="on">'+I("check",14,3)+'Sticker</span><span>Paper cut</span><span>Crayon</span><span>Watercolour</span><span>Line art</span><span class="off">'+I("lock",13,2)+'Pixel</span></div><span class="r3-lab">Styles she can pick between</span><div class="r3-sty"><span class="on">Sticker</span><span class="on">Crayon</span><span class="on">Watercolour</span><span>Paper cut</span><span>Line art</span></div><p class="r3-fine" style="margin-top:8px">Pixel opens at 8 and cannot be turned on earlier.</p>',"")+
   K.card('<div class="r3-two"><div><h4 style="font-size:14px">You can</h4>'+li([["check","Choose the art style and the styles she can pick between"],["check","Turn the daily question and coding activities off"],["check","Set a colour day for today, and clear it"]],"ok")+'</div><div><h4 style="font-size:14px">You can’t</h4>'+li([["lock","See why she chose a colour, or a history of her choices"],["lock","Show it to anyone as a reading of how she feels"]])+'</div></div>',"flat",6);
  var st=head(true)+K.card('<span class="r3-lab">Colour day set for mint</span>'+dayrow("mint")+'<div style="height:8px"></div><button type="button" class="btn ghost sm">Clear the colour day</button>',"",3)+K.toast("Colour day set for today.",{ic:"check",inline:true})+
   head(false,true)+call("Her own answer is never deleted by clearing a colour day. It is simply asked again.","info","info");
  return lay(c,main,st,"Her colour and art",{eyebrow:"Ivy",stLabel:"Colour day set, and no colour yet"});}});

S("ColourDaily","child","Which do you like more today?","Her colour",{wide:true,refs:"colour_daily.dart",
 desc:"One question, once a day, as a two-up. One of the pair is always her current colour, so keeping it is as easy as changing it.",
 notes:[nn(1,"a two-up A/B, not twelve: 'Which do you like more today? Pick one — there is no wrong answer.'","two big colour cards with the colour’s name in its own ink, a check and a soft lift when picked.","P2: no streak, no 'N days in a row', neither option framed as new or better."),
  nn(2,"one of the pair is always her current colour, on a randomised side.","unchanged; nothing marks which is current.","no nudge toward change."),
  nn(3,"when the guardian turns the question off, her colour stays as it is and the home says 'Pick one any time.'","that quiet state is drawn instead of a missing screen.","the question is a game, not a settings screen.")],
 r:function(c){
  function card(id,pk,n){var s=SW[id];return '<div'+K.n(n)+' class="r3-cc'+(pk?" pk":"")+'" style="background:'+s[0]+';color:'+s[1]+'" role="button" tabindex="0" aria-label="'+s[2]+(pk?', picked':'')+'">'+(pk?I("check2",30,2.4):"")+'<span>'+s[2]+'</span></div>';}
  var main='<div style="text-align:center;padding:4px 0 6px"><h2 class="r3-h" style="font-size:26px">Which do you like more today?</h2><p class="r3-sub" style="margin-top:6px">Pick one — there is no wrong answer.</p></div><div class="r3-big2"'+K.n(1)+'>'+card("sea",false)+card("mint",false,2)+'</div>'+motion("the card lifts 2 px and gains its ring in 120 ms; reduce motion skips the lift.");
  var st='<div class="r3-big2">'+card("sea",true)+card("mint",false)+'</div>'+quiet("Your colour is sea blue today.","palette")+
   K.card(eb("When the question is off")+'<p class="r3-h" style="font-size:17px">Pick one any time.</p><p class="r3-sub">Her colour stays as it is until she picks again.</p>',"flat",3);
  return clay(c,main,st,"Your colour",{stLabel:"After she picks, and when it is off"});}});

S("ColourHome","child","Your colour","Her colour",{wide:true,refs:"her_colour_home.dart, her_colour_accent.dart, colour_activities_logic.dart",
 desc:"Ivy’s own colour page: one thin stripe and one ring, pictures drawn in her style, and the activities for her age.",
 notes:[nn(1,"her colour appears only in budgeted placements: a thin accent stripe under the header and a ring on her avatar.","the stripe and the ring are the only two places; nothing else is tinted.","§8.6.2 placement budget."),
  nn(2,"'Today your colour is' with its name; 'No colour yet / Pick one any time.' when she has not chosen.","big name, a small sparkle only if the flourish placement is on.","a colour is a fact."),
  nn(3,"'Pictures look like' offers only the styles a guardian allowed, with a sample picture.","the sample is large and updates as she taps a style.","she chooses among the allowed, never past them."),
  nn(4,"activities are filtered by her age and the coding switch: at 5 she sees Colour sort, Path code and Colour critter; Pixel garden opens at 8.","three large tiles, one thought each.","a hidden activity is simply absent.")],
 r:function(c){var s=SW.sea;
  var main='<div style="display:flex;gap:16px;align-items:center"'+K.n(1)+'><span class="r3-ring" style="background:'+s[0]+'"><i style="background:var(--bg)"><span style="display:block;width:100%;height:100%;border-radius:50%;background:'+s[0]+';transform:scale(.86)"></span></i></span><div><span class="r3-eb" style="margin:0">Today your colour is</span><h2 class="r3-h" style="font-size:30px;line-height:1.05"'+K.n(2)+'>Sea blue '+I("sparkle",20,2)+'</h2></div></div>'+
   '<div class="r3-stripe" style="background:'+s[0]+'"></div>'+
   K.card('<span class="r3-eb">Pictures look like</span><div class="r3-sty" style="margin-bottom:8px"'+K.n(3)+'><span class="on">Sticker</span><span>Crayon</span><span>Watercolour</span></div><div class="r3-cwrap">'+critter(s[0],"sticker",112)+'</div>')+
   '<div class="r3-stack"'+K.n(4)+'><div class="r3-act"><span class="gi" style="background:'+s[0]+'22;color:'+s[1]+'">'+I("grid",26,1.9)+'</span><span><b>Colour sort</b><small>Find things that are sea blue</small></span></div><div class="r3-act"><span class="gi" style="background:var(--priC);color:var(--onPriC)">'+I("footprint",26,1.9)+'</span><span><b>Path code</b><small>Write the steps, press Run</small></span></div><div class="r3-act"><span class="gi" style="background:var(--accentC);color:var(--ink)">'+I("brush",26,1.9)+'</span><span><b>Colour critter</b><small>Colour in an animal</small></span></div></div>';
  var st=K.card(eb("No colour yet")+'<div style="display:flex;gap:14px;align-items:center"><span class="r3-ring" style="background:var(--surface3)"><i style="background:var(--bg)"></i></span><div><b class="r3-h" style="font-size:20px">No colour yet</b><p class="r3-sub">Pick one any time.</p></div></div>',"flat")+
   K.card(eb("At 8")+'<div class="r3-act"><span class="gi" style="background:var(--okC);color:var(--ok)">'+I("grid3",26,1.9)+'</span><span><b>Pixel garden</b><small>Plant a pixel garden</small></span></div>',"flat")+
   quiet("If a guardian turns coding off, Path code and Pixel garden are simply not here.","eye");
  return clay(c,main,st,"Your colour",{stLabel:"No colour yet, and at 8"});}});

S("ColourSort","child","Colour sort","Her colour",{wide:true,refs:"colour_sort_screen.dart, colour_activities_logic.dart, colour_foods.dart",
 desc:"Tap a picture, then a basket. Things that are her colour, and things that are not, sorted into two baskets. No score, no timer.",
 notes:[nn(1,"'Let’s find things that are sea blue.' She taps a picture, then a basket.","two big baskets with dashed outlines; the chosen picture gets a ring and the target basket lights up.","P2: no points, no timer."),
  nn(2,"the helper line changes: 'Tap a picture first.', 'Now tap a basket.', 'Not quite. Let’s find another basket.', 'All sorted.'","one calm line under the baskets, spoken on tap; a wrong basket never shakes or buzzes.","a mistake is a try again, not a loss."),
  nn(3,"finishing says 'All done'.","a resting end state with a single check, no total.","finishing is not a result."),
  nn(4,"if nothing fits her colour: 'There is nothing for this colour to sort today.'","a designed empty state instead of a blank grid.","")],
 r:function(c){var s=SW.sea;
  var main='<h2 class="r3-h" style="font-size:22px;text-align:center">Let’s find things that are sea blue.</h2>'+
   '<div class="r3-items"'+K.n(1)+'><div class="gone">'+blob("berry",s[0])+'</div><div class="sel">'+blob("whale",s[0])+'</div><div>'+blob("leaf","#5AA84A")+'</div><div>'+blob("drop",s[0])+'</div><div>'+blob("shell","#E8730C")+'</div><div>'+blob("fish",s[0])+'</div></div>'+
   '<div class="r3-bsk"><div class="hl">'+I("check",22,2.4)+'<span>Sea blue</span></div><div><span>Not sea blue</span></div></div>'+quiet("Now tap a basket.","hand")+motion("a picture glides to its basket in 220 ms; reduce motion makes it appear there.");
  var st=K.card(eb("A try again")+quiet("Not quite. Let’s find another basket.","hand"),"flat",2)+K.card(eb("All sorted")+K.emptyState({spot:"leaf",title:"All done",sub:"All sorted."}),"",3)+K.card(eb("Nothing to sort")+quiet("There is nothing for this colour to sort today.","leaf"),"flat",4);
  return clay(c,main,st,"Colour sort",{stLabel:"Try again, done, nothing to sort"});}});

S("PathCode","child","Path code","Her colour",{wide:true,refs:"path_code_screen.dart, colour_activities_logic.dart",
 desc:"Help the fox get to the carrot with arrows. A first step into coding for five-year-olds; the Repeat block opens at 8.",
 notes:[nn(1,"'Help the fox get to the carrot.' A small board with a start, a goal and some rocks; every level is solvable.","the board is a soft tray; the fox and carrot are drawn, rocks are quiet.","P2: no stars, levels are not counted."),
  nn(2,"she adds arrows (up, down, left, right) and presses Run; 'Add arrows, then press Run.' and 'No arrows yet.'","big arrow keys, the program as a row of chips, Run and Clear below.","every target 64 dp or more."),
  nn(3,"'Not there yet. Add another arrow.' when the run misses.","an encouragement line, no red, no buzz.","a try again, not a fail."),
  nn(4,"Repeat opens at 8 and cannot be opened earlier; 'Another path' follows a win.","at 5 the Repeat key is simply absent.","")],
 r:function(c){
  function cell(k){return '<i class="'+(k==="rock"?"rock":k==="trail"?"trail":"")+'">'+(k==="fox"?'<svg viewBox="0 0 32 32" width="30" height="30" aria-hidden="true"><path d="M4 8l7 4 5-2 5 2 7-4-2 12a10 10 0 01-10 10 10 10 0 01-10-10z" fill="#E8730C"/><path d="M11 22q5 5 10 0" stroke="#fff" stroke-width="2" fill="none"/><circle cx="12" cy="17" r="1.6" fill="#22282B"/><circle cx="20" cy="17" r="1.6" fill="#22282B"/></svg>':k==="carrot"?'<svg viewBox="0 0 32 32" width="28" height="28" aria-hidden="true"><path d="M6 12l20 4-18 14z" fill="#E8730C" transform="rotate(-24 16 18)"/><path d="M22 6q4-2 6 2M22 6q0-4 5-4" stroke="#5AA84A" stroke-width="3" fill="none" stroke-linecap="round"/></svg>':k==="rock"?I("more",18,1.6):"")+'</i>';}
  var grid=["","","","","","","","","fox","trail","trail","carrot","","","",""];
  var main='<h2 class="r3-h" style="font-size:22px;text-align:center">Help the fox get to the carrot.</h2><div class="r3-board" style="grid-template-columns:repeat(4,minmax(0,1fr));max-width:260px;margin:0 auto;width:100%"'+K.n(1)+'>'+grid.map(cell).join("")+'</div>'+
   '<div class="r3-prog"'+K.n(2)+'><i>'+I("arrowR",24,2.4)+'</i><i>'+I("arrowR",24,2.4)+'</i><i>'+I("arrowR",24,2.4)+'</i></div>'+
   '<div class="r3-two"><button type="button" class="btn tonal">'+I("arrowL",22,2.4)+'Left</button><button type="button" class="btn tonal">'+I("arrowR",22,2.4)+'Right</button><button type="button" class="btn tonal">'+I("chevU",22,2.4)+'Up</button><button type="button" class="btn tonal">'+I("chevD",22,2.4)+'Down</button></div>'+
   '<div class="r3-two">'+K.btn("Run",{ic:"play",size:"lg"})+K.btn("Clear",{kind:"ghost"})+'</div>'+quiet("Add arrows, then press Run.","hand");
  var st=K.card(eb("A miss")+quiet("Not there yet. Add another arrow.","hand"),"flat",3)+K.card(eb("Reached the carrot")+K.emptyState({spot:"leaf",title:"Fox is home",sub:"Another path?",action:"Another path"}),"")+
   K.card(eb("From 8: Repeat")+'<div class="r3-prog"><i>'+I("arrowR",22,2.4)+'</i><i class="rep" '+K.n(4)+'>'+I("refresh",16,2.4)+' Repeat 3 <span style="display:inline-grid;gap:2px">'+I("arrowR",16,2.4)+'</span></i></div><p class="r3-fine" style="margin-top:6px">Repeat opens at 8 and cannot be opened earlier.</p>',"flat")+quiet("No arrows yet.","hand");
  return clay(c,main,st,"Path code",{stLabel:"A miss, a win, and the Repeat block"});}});

S("ColourCritter","child","Colour critter","Her colour",{wide:true,refs:"colour_critter_screen.dart, her_colour_art.dart",
 desc:"Pick an animal, tap a part to colour it. Three shades of her colour, and a preview in each art style a guardian allowed.",
 notes:[nn(1,"'Pick an animal, then tap a part to colour it.' The canvas takes her colour or a lighter or darker tint of it.","three big round paints: today’s colour and its two tints.","her colour is the palette, not a grade."),
  nn(2,"undo and clear sit beside the canvas.","two plain icon buttons, 64 dp.","nothing is lost without undo."),
  nn(3,"'How it looks in a style' previews the drawing in Paper cut, Sticker, Crayon, Watercolour or Line art.","the same critter redrawn live in the chosen style.","the art style never changes her colour."),
  nn(4,"the drawing is saved only if she keeps it; it is stored on this device as strokes and fills.","no auto-save and no gallery push.","local-first.")],
 r:function(c){var s=SW.sea;
  var main='<h2 class="r3-h" style="font-size:20px;text-align:center">Pick an animal, then tap a part to colour it.</h2><div class="r3-cwrap" style="background:var(--surface2);border-radius:28px;padding:14px"'+K.n(1)+'>'+critter(s[0],"sticker",160)+'</div>'+
   '<div class="r3-pal"'+K.n(2)+'><i style="background:color-mix(in srgb,'+s[0]+' 55%,#fff)"></i><i class="sel" style="background:'+s[0]+'"></i><i style="background:color-mix(in srgb,'+s[0]+' 70%,#000)"></i></div><div class="r3-two">'+K.btn("Undo",{kind:"ghost",ic:"undo"})+K.btn("Clear",{kind:"ghost",ic:"trash"})+'</div>';
  var st=K.card(eb("How it looks in a style")+'<div class="r3-sty" style="margin-bottom:8px"'+K.n(3)+'><span>Paper cut</span><span class="on">Sticker</span><span>Crayon</span><span>Watercolour</span><span>Line art</span></div><div class="r3-two"><div class="r3-cwrap">'+critter(s[0],"crayon",96)+'</div><div class="r3-cwrap">'+critter(s[0],"watercolour",96)+'</div><div class="r3-cwrap">'+critter(s[0],"paper",96)+'</div><div class="r3-cwrap">'+critter(s[0],"line",96)+'</div></div>')+K.card(eb("Keep it")+K.btn("Keep this picture",{full:true,ic:"download",kind:"tonal"}),"flat",4);
  return clay(c,main,st,"Colour critter",{stLabel:"In each style"});}});

S("PixelGarden","child","Pixel garden","Her colour",{wide:true,refs:"pixel_garden_screen.dart, colour_activities_logic.dart",
 desc:"From 8: plant a pixel picture with her colour and two tints. Mirror copies each tap across the middle; Repeat stamp repeats a pattern.",
 notes:[nn(1,"'Tap squares to plant.' then, with a stamp, 'Tap where your pattern ends.'","an 8-column garden on a soft tray with her three shades.","P2: no percent shown (it exists only as an accessibility label)."),
  nn(2,"Mirror: 'Each tap is copied across the middle.' Repeat stamp repeats a pattern.","two clear chips under the garden.","she can undo; nothing is final."),
  nn(3,"closed states: 'The pixel garden opens at 8.' and 'The pixel garden is resting for now.' when a guardian turned coding off.","each closed state is a quiet card with the honest reason.","a gate is a fact, not a punishment.")],
 r:function(c){var s=SW.sea,t="color-mix(in srgb,"+s[0]+" 55%,#fff)",d="color-mix(in srgb,"+s[0]+" 70%,#000)";
  var cells="",pat={1:s[0],2:s[0],5:s[0],6:s[0],9:t,10:s[0],13:s[0],14:t,17:d,18:s[0],21:s[0],22:d,26:t,29:t,33:s[0],38:s[0],42:d,45:d};
  for(var i=0;i<48;i++)cells+='<i style="background:'+(pat[i]||"")+'"></i>';
  var main='<h2 class="r3-h" style="font-size:22px;text-align:center">Tap squares to plant.</h2><div class="r3-px"'+K.n(1)+'>'+cells+'</div><div class="r3-pal"><i class="sel" style="background:'+s[0]+'"></i><i style="background:'+t+'"></i><i style="background:'+d+'"></i></div><div class="r3-sty" style="justify-content:center"'+K.n(2)+'><span class="on">'+I("swap",16,2)+'Mirror</span><span>'+I("copy",16,2)+'Repeat stamp</span></div><p class="r3-fine" style="text-align:center">Each tap is copied across the middle.</p>'+K.btn("Clear",{kind:"ghost",full:true});
  var st=K.card(eb("At 5")+K.emptyState({spot:"leaf",title:"The pixel garden opens at 8",sub:"It is not ready yet."}),"",3)+K.card(eb("Coding turned off")+K.emptyState({spot:"leaf",title:"The pixel garden is resting for now",sub:"It will be here when a grown-up opens it."}),"",3);
  return clay(c,main,st,"Pixel garden",{stLabel:"Closed states"});}});

/* ========================================================== FAMILY STRUCTURE == */
css([
".ob .r3-wk{display:grid;grid-template-columns:repeat(14,minmax(0,1fr));gap:3px}.ob .r3-wk i{aspect-ratio:1;border-radius:6px;background:var(--priC)}.ob .r3-wk i.d{background:var(--accentC);box-shadow:inset 0 0 0 1.5px var(--accent)}",
".ob .r3-opt{display:flex;gap:12px;align-items:flex-start;min-height:56px;padding:12px 14px;border:1.5px solid var(--outline);border-radius:16px;background:var(--surface);min-width:0}",
".ob .r3-opt.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .r3-opt .rd{width:22px;height:22px;border-radius:50%;border:2px solid var(--ink3);flex:none;margin-top:1px;display:grid;place-items:center;color:var(--onPri)}.ob .r3-opt.on .rd{border-color:var(--pri);background:var(--pri)}",
".ob .r3-opt .ot{display:grid;gap:3px;min-width:0;flex:1}.ob .r3-opt b{font:700 14.5px/1.2 var(--font-body)}.ob .r3-opt small{font-size:12.5px;line-height:1.35;color:var(--ink3)}.ob .r3-opt.on small{color:inherit;opacity:.92}",
".ob .r3-ba{display:grid;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);gap:8px;align-items:start}.ob .r3-ba .mid{align-self:center;color:var(--ink3)}",
".ob .r3-mh{display:grid;gap:3px;padding:10px;border-radius:14px;background:var(--surface2);min-width:0}.ob .r3-mh b{font-size:12.5px}.ob .r3-mh small{font-size:12px;color:var(--ink3);overflow-wrap:anywhere}",
".ob .r3-band{border:1.5px solid var(--outline);border-radius:18px;padding:12px 14px;background:var(--surface);display:grid;gap:6px;min-width:0}",
".ob .r3-band.here{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .r3-band h5{margin:0;font:800 15px/1.2 var(--font-display);display:flex;justify-content:space-between;gap:8px;align-items:center}",
".ob .r3-band ul{margin:0;padding-left:18px;font-size:12.5px;line-height:1.45}",
".ob .r3-hist{display:grid;gap:6px;padding:12px 14px;border-radius:18px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}",
".ob .r3-hist b{font-size:14px;line-height:1.3}.ob .r3-hist .m{display:flex;flex-wrap:wrap;gap:6px;align-items:center;font-size:12.5px;color:var(--ink3)}",
".ob .r3-hist.undone{opacity:.7}",
".ob .r3-big6{font:800 84px/1 var(--font-display);letter-spacing:-.03em;font-variant-numeric:tabular-nums;color:var(--onPri)}"
].join("\n"));
function wkStrip(seq){return '<div class="r3-wk" aria-hidden="true">'+seq.split("").map(function(c){return '<i class="'+(c==="d"?"d":"")+'"></i>';}).join("")+'</div>';}
function opt(title,sub,on,o){o=o||{};return '<div class="r3-opt'+(on?" on":"")+'"'+K.n(o.n)+'><span class="rd">'+(on?I("check",12,3.2):"")+'</span><span class="ot"><b>'+E(title)+'</b>'+(sub?'<small>'+sub+'</small>':"")+(o.extra||"")+'</span></div>';}
function stpill(s){return s==="held"?pill("info","Held until told","hourglass"):s==="scheduled"?pill("warn","Scheduled","calendar"):s==="told"?pill("pri","Told her","volume"):pill("ok","Applied","check");}
function pav(name,sz,tone){return K.avatar(name.charAt(0),{size:sz||40,tone:tone||""});}
function FamNote(){return seal("<b>Any guardian can change this alone.</b> Marcus sees every change. Ivy sees only what you release. These choices live on this device; syncing between devices comes later.","shield",1);}

S("FamilyHub","guardian","Family structure","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"One calm hub for who is in Ivy’s life, where she sleeps and how her home grows. Held and scheduled changes wait at the top until they are told to her.",
 notes:[nn(1,"'Any guardian can change this alone. The other guardian sees every change. Ivy sees only what you release.' and that syncing between devices comes later.","the rule is a sealed banner with the sync limit stated once, plainly, instead of two grey paragraphs.","a guardian sees everything; she sees only what is released."),
  nn(2,"held or scheduled changes appear as cards at the top; a held one has 'I have told her'.","each pending change is a card with a state pill, a plain sentence, and the next step.","nothing reaches her until a guardian chooses when."),
  nn(3,"four rows: People (count), Homes and rhythm (count and pattern, 'set by order' when locked), Age bands, Change history ('N entries, never edited').","each row carries its fact in the subtitle, so most checks need no tap.","history is append-only."),
  nn(4,"Round 2 drew Family builder and homes as separate screens with a Family tab; shipped, this hub is reached from the guardian More screen.","drawn as built.","")],
 r:function(c){
  var pend=K.card('<div style="display:flex;gap:10px;align-items:flex-start">'+pl("users","info")+'<div style="min-width:0;flex:1"><b style="font-size:14.5px;line-height:1.3">Jess added Grandma Rosa to the family</b><p class="r3-sub" style="margin:2px 0 8px">Held. Ivy sees nothing yet.</p><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">'+stpill("held")+'<button type="button" class="btn tonal sm">I have told her</button></div></div></div>',"",2)+
   K.card('<div style="display:flex;gap:10px;align-items:flex-start">'+pl("calendar","warn")+'<div style="min-width:0;flex:1"><b style="font-size:14.5px;line-height:1.3">Marcus changed the rhythm to Alternating weeks</b><p class="r3-sub" style="margin:2px 0 8px">Scheduled for 2026-12-09.</p>'+stpill("scheduled")+'</div></div>',"");
  var main='<div class="card hero r3-hero"><div class="tx"><span class="r3-eb">Ivy</span><b class="r3-h">Who is in her life, where she sleeps, and how her home grows.</b></div><span class="art">'+K.spot("houses",84,{plate:false})+'</span></div>'+FamNote()+pend+
   K.card(row({ic:"users",title:"People",sub:"5 in her life",go:true})+row({ic:"home",title:"Homes and rhythm",sub:"2 homes · Alternating weeks",go:true})+row({ic:"sparkle",title:"Age bands",sub:"Her home is at 5 to 7",go:true})+row({ic:"clock",title:"Change history",sub:"12 entries, never edited",go:true,n:3}));
  var st=K.card(eb("Nothing set up yet")+row({ic:"users",title:"People",sub:"0 in her life",go:true})+row({ic:"home",title:"Homes and rhythm",sub:"0 homes · No rhythm set",go:true})+row({ic:"sparkle",title:"Age bands",sub:"Her home is at 5 to 7",go:true})+row({ic:"clock",title:"Change history",sub:"0 entries, never edited",go:true}),"flat")+
   K.card(eb("Rhythm set by a court order")+row({ic:"home",title:"Homes and rhythm",sub:"2 homes · 2-2-5-5 · set by order",go:true,trail:pill("quiet","Set by order","lock")}),"flat")+call("Round 2 drew a Family tab. The shipped app reaches this from More.","info","flag",4);
  return lay(c,main,st,"Family structure",{eyebrow:"Ivy",stLabel:"Not set up yet, and locked by order"});}});

S("FamilyPeople","guardian","Who is in her life","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"Each person shows the name Ivy uses, never a role word. Roles stay in the background and only guardians see them.",
 notes:[nn(1,"'Each person shows the name Ivy uses, never a role word. Roles stay in the background.'","an opening line and a small eye-off cue on anyone with no name, so 'not shown to her' reads at a glance.","her people are as she knows them."),
  nn(2,"each row: the name, the role (guardian words), the home and how they reach her.","avatar, name, then one quiet line of role, home and channels.","a role word never reaches her."),
  nn(3,"a person with no name appears as '(not shown to her)'.","drawn with a dashed avatar and an Only you pill.","she never sees an unnamed person."),
  nn(4,"an empty list shows only the Add someone button.","a designed empty state explains what will happen and keeps the same single action.","nothing reaches her until you choose when.")],
 r:function(c){
  function p(n,role,home,ch,o){o=o||{};return '<div class="row" role="button" tabindex="0" style="min-height:64px"'+(o.noname?K.n(3):"")+'>'+(o.noname?'<span class="av" style="width:42px;height:42px;border:2px dashed var(--edge);background:transparent;color:var(--ink3);display:grid;place-items:center">?</span>':pav(n,42,o.tone))+'<span class="rtxt"><b>'+E(o.noname?"(not shown to her)":n)+'</b><small>'+E(role)+(home?" · "+home:"")+(ch?" · "+ch:"")+'</small></span>'+(o.noname?pill("quiet","Only you","eyeoff"):"")+'<span class="go">'+I("chevR",16,2)+'</span></div>';}
  var main=K.card('<p class="r3-sub" style="margin:0"'+K.n(1)+'>Each person shows the name Ivy uses, never a role word. Roles stay in the background. Nothing reaches her until you choose when.</p>',"tint")+
   K.card(p("Jess","Guardian","Jess’s house","Live calls, Messages")+p("Marcus","Guardian","Marcus’s house","Live calls, Messages",{tone:"accent"})+p("Grandma Rosa","Relative","","Live calls, Postcards",{tone:"accent"})+p("Dana","A parent’s partner","Marcus’s house","Messages",{tone:"accent"})+p("","Sitter","","",{noname:true}),"",2)+
   K.btn("Add someone",{kind:"tonal",full:true,ic:"plus"});
  var st=K.card(K.emptyState({spot:"family",title:"Nobody here yet",sub:"Add the people in Ivy’s life. Nothing reaches her until you choose when.",action:"Add someone"}),"",4)+call("The shipped empty list shows only the Add someone button; the sentence above is the refinement.","info","info");
  return lay(c,main,st,"Who is in her life",{eyebrow:"Family structure",stLabel:"Empty"});}});

S("PersonEditor","guardian","Add someone","Family structure",{wide:true,refs:"family_structure_screens.dart, family_structure_logic.dart",
 desc:"Add or change a person: the name Ivy uses, a role only guardians see, a home, how they reach her, and whether they are away.",
 notes:[nn(1,"'Leave empty to keep them out of her people.' Roles run Guardian, Parent, A parent’s partner, Relative, Trusted adult, Sitter, Foster parent, Caseworker, Therapist.","the name field leads, the role is clearly labelled (only you see this).","role words never reach her."),
  nn(2,"home can be 'No home (near and far)'.","a chip row of homes plus a distinct near-and-far choice.","a person without a home is still hers."),
  nn(3,"'How they reach her': Live calls, Messages, Postcards, A voice line, Supervised visits.","five checkable rows with a small icon each.","P11 and P3 are unaffected: no remote control, no location."),
  nn(4,"Away for a while with an optional end date ('No end date' or 'Set an end date').","a switch and a date row that opens only when needed.","the date is a fact in the family model, not a countdown."),
  nn(5,"refusals: 'The name is too long or has odd characters.' and 'That is as many people as fit.'","the message sits on the field it is about.",""),
  nn(6,"Next: preview leads to What Ivy will see; editing has Remove from her people.","a danger text button at the end, separated.","removal is a new history entry.")],
 r:function(c){
  var main=K.formField({label:"Name Ivy uses",value:"Grandma Rosa",hint:"Leave empty to keep them out of her people.",n:1})+
   K.card(lab("Role (only you see this)")+'<div class="r3-sty"><span>Guardian</span><span>Parent</span><span>A parent’s partner</span><span class="on">'+I("check",14,3)+'Relative</span><span>Trusted adult</span><span>Sitter</span></div>',"")+
   K.card(lab("Home")+'<div class="r3-sty" '+K.n(2)+'><span>Jess’s house</span><span>Marcus’s house</span><span class="on">'+I("check",14,3)+'No home (near and far)</span></div>',"")+
   K.card('<span class="r3-lab">How they reach her</span><div'+K.n(3)+'>'+[["video","Live calls",1],["chat","Messages",1],["mail","Postcards",1],["mic","A voice line",0],["calendar","Supervised visits",0]].map(function(x){return '<div class="r3-chk">'+K.check(!!x[2])+'<span style="display:flex;gap:8px;align-items:center;font-size:14px">'+I(x[0],18,1.9)+E(x[1])+'</span></div>';}).join("")+'</div>',"")+
   K.card(row({ic:"clock",title:"Away for a while",sub:"No end date",trail:K.toggle(false),n:4}),"")+
   K.btn("Next: preview",{full:true,size:"lg"})+K.btn("Remove from her people",{kind:"danger",full:true,n:6});
  var st=K.formField({label:"Name Ivy uses",value:"Grandma Rosa Elizabeth Marguerite Vandersloot the Third",error:"The name is too long or has odd characters.",n:5})+
   K.card(row({ic:"clock",title:"Away for a while",sub:"Set an end date · 2027-01-15",trail:K.toggle(true)}),"")+call("That is as many people as fit.","warn","warn",5);
  return lay(c,main,st,"Add someone",{eyebrow:"Who is in her life",stLabel:"Refusals and away"});}});

S("FamilyHomes","guardian","Homes and rhythm","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"One to four homes, who is in each, where Ivy sleeps, and the weekly rhythm. A court order locks the rhythm and says so.",
 notes:[nn(1,"'One to four homes. Her weeks and packing follow them.'","each home is a card with people as avatars and a sleeps-here pill.","packing follows homes, not the other way round."),
  nn(2,"the rhythm card shows the pattern word, the exchange time, and an Edit button.","a 14-day strip draws the pattern in house colours and shape, not only colour.","the pattern is a fact about her week."),
  nn(3,"when set by a court order: 'Set by a court order. It is shown here and cannot be changed in this app.' and the Edit button is gone.","the lock is a clear pill with its reason; the row never looks broken.","the order wins; the app never edits it."),
  nn(4,"Add a home is hidden at four homes.","the add action simply stops, with 'That is the most there is room for.' in the message.","")],
 r:function(c){
  function home(n,people,sleeps,tone){return K.card('<div class="r3-hd" style="justify-content:flex-start;margin-bottom:8px">'+pl("home",tone)+'<b class="r3-h" style="font-size:17px">'+E(n)+'</b>'+(sleeps?pill("pri","Ivy sleeps here","moon"):"")+'</div>'+K.avatarStack(people,{size:32,max:4}));}
  var main=home("Jess’s house",[["J"],["I"]],1,"")+home("Marcus’s house",[["M","accent"],["D","accent"],["I"]],1,"ac")+
   K.btn("Add a home",{kind:"tonal",full:true,ic:"plus"})+
   K.card('<h4>Weekly rhythm</h4><b class="r3-h" style="font-size:20px"'+K.n(2)+'>Alternating weeks</b><p class="r3-sub">Exchange at 18:00</p><div style="height:8px"></div>'+wkStrip("mmmmmmmddddddd")+'<div class="r3-fine" style="display:flex;gap:12px;margin-top:6px"><span>'+I("home",12,2)+' Jess’s house</span><span>'+I("home",12,2)+' Marcus’s house</span></div><div style="height:10px"></div>'+K.btn("Edit the rhythm",{kind:"ghost",full:true}),"",1);
  var st=K.card('<h4>Weekly rhythm</h4><b class="r3-h" style="font-size:20px">2-2-5-5</b><p class="r3-sub">Exchange at 18:00</p><div style="height:8px"></div>'+wkStrip("mmddmmmddmmddd")+'<div style="height:10px"></div>'+call("Set by a court order. It is shown here and cannot be changed in this app.","info","lock",3)+'<div style="margin-top:8px">'+pill("quiet","Set by order","lock")+'</div>')+
   K.card(eb("Four homes: that is the most")+K.btn("Add a home",{kind:"tonal",full:true,ic:"plus",disabled:true})+'<p class="r3-fine" style="margin-top:6px">That is the most there is room for.</p>',"flat",4);
  return lay(c,main,st,"Homes and rhythm",{eyebrow:"Family structure",stLabel:"Locked by order, and at four homes"});}});

S("RhythmEdit","guardian","Edit the rhythm","Family structure",{refs:"family_structure_screens.dart",
 desc:"Pick a weekly pattern, an exchange day and a 24-hour time. Each pattern is drawn as two weeks so it can be seen, not decoded.",
 notes:[nn(1,"patterns: No rhythm set, 2-2-3, 2-2-5-5, Alternating weeks, Week on, week off, Something else.","each is a card with a two-week strip in the two house colours, differing in shape as well as tint.","colour is never the only signal."),
  nn(2,"'Exchange day' is Not set or a weekday.","a chip row of the seven days.","a fact, not a countdown."),
  nn(3,"'Exchange time (24h, like 18:00)' with the hint 'Use 24-hour time, like 18:00'.","a plain field with the example as the hint, and a clear error under it.","")],
 r:function(c){
  var main=K.card(lab("Pattern")+'<div class="r3-stack"'+K.n(1)+'>'+opt("No rhythm set","",false)+opt("2-2-3","Two nights, two nights, three nights",false,{extra:wkStrip("mmddmmmddmmddd")})+opt("Alternating weeks","One week at each home",true,{extra:wkStrip("mmmmmmmddddddd")})+opt("Week on, week off","",false)+opt("Something else","",false)+'</div>',"")+
   K.card(lab("Exchange day")+'<div class="r3-sty"'+K.n(2)+'><span>Not set</span><span>Sun</span><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span class="on">'+I("check",14,3)+'Fri</span><span>Sat</span></div>',"")+
   K.formField({label:"Exchange time (24h, like 18:00)",value:"18:00",hint:"Use 24-hour time, like 18:00",n:3})+K.btn("Next: preview",{full:true,size:"lg"});
  return T("Edit the rhythm",{eyebrow:"Homes and rhythm"})+P(main);}});

S("ChangeTiming","guardian","What Ivy will see","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"Before any change is saved, a preview of Ivy’s home before and after, and a choice of when she sees it: now, after a guardian has told her, or on a date.",
 notes:[nn(1,"a Now and After pair of mini homes and the sentence 'Ivy’s screens change.' or 'do not change.'","the pair is two compact cards with an arrow, so the effect is seen at once.","a guardian sees the effect before it exists."),
  nn(2,"timing: Now, Hold until I have told her (Recommended for big changes), On a date.","three large radio cards; Hold is marked Recommended only for big changes.","big changes wait for a conversation."),
  nn(3,"Add a picture story: you write it, a few short pages, up to six, a blank line between pages.","the story is one plain text area with the limits written under it.","nothing is written for you (P1 spirit)."),
  nn(4,"the button label follows the choice: Save and apply, Save and hold, Save for a date; 'The other guardian sees this change when you save'.","the label is the promise; the footer repeats who sees what.","everything is visible to the other guardian."),
  nn(5,"errors in words: 'Pick a day after today. For today, choose Now.', 'That date is too far away. Pick one within two years.', 'This is set by a court order and cannot be changed here.'","each sits beside the control it is about.",""),
  nn(6,"settings changes (like a band hold) say 'This is about her settings, so it applies now.'","the choice is replaced by one sentence, not disabled radios.","")],
 r:function(c){
  function mh(t,band,rows){return '<div class="r3-mh"><b>'+t+'</b><small>'+band+' home</small>'+rows.map(function(r){return '<small>'+r+'</small>';}).join("")+'</div>';}
  var main='<b class="r3-h" style="font-size:18px">Jess added Grandma Rosa to the family</b>'+
   K.card('<div class="r3-ba"'+K.n(1)+'>'+mh("Now","5 to 7",["Jess’s house: Jess","Marcus’s house: Marcus, Dana"])+'<span class="mid">'+I("arrowR",20,2)+'</span>'+mh("After","5 to 7",["Jess’s house: Jess","Marcus’s house: Marcus, Dana","Near and far: Rosa"])+'</div><p class="r3-sub" style="margin-top:8px"><b>Ivy’s screens change.</b></p>')+
   '<span class="r3-h2">When does she see it?</span><div class="r3-stack"'+K.n(2)+'>'+opt("Now","Her screens change as soon as you save.",false)+opt("Hold until I have told her","Her view stays the same. You release it when you have talked. Recommended for big changes.",true)+opt("On a date","Her screens change on the day you pick.",false)+'</div>'+
   K.card(row({ic:"book",title:"Add a picture story",sub:"You write it, a few short pages. Nothing is written for you.",trail:K.toggle(true),n:3})+ta("Grandma Rosa lives by the sea.\n\nShe is coming to see you.",{h:84,ph:"Pages"})+'<p class="r3-fine">A blank line between pages. Up to six pages, 240 letters each.</p>',"")+
   K.btn("Save and hold",{full:true,size:"lg",n:4})+'<p class="r3-fine" style="text-align:center">The other guardian sees this change when you save, whichever timing you pick. Nothing reaches Ivy until it is released.</p>';
  var st=K.card(eb("On a date, with an error")+'<div class="r3-stack">'+opt("On a date","Her screens change on the day you pick.",true)+'<button type="button" class="btn ghost sm">'+I("calendar",16,2)+'2026-11-08</button></div>'+call("Pick a day after today. For today, choose Now.","bad","warn",5)+call("That date is too far away. Pick one within two years.","bad","warn"),"")+
   K.card(eb("A settings change")+'<p class="r3-sub" style="margin:0">This is about her settings, so it applies now.</p>'+K.btn("Save and apply",{full:true}),"flat",6)+
   K.card(eb("Locked by an order")+call("This is set by a court order and cannot be changed here.","info","lock"),"flat");
  return lay(c,main,st,"What Ivy will see",{eyebrow:"Preview",stLabel:"Date errors, settings and orders"});}});

S("FamilyHistory","guardian","Family history","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"Every change to her people, homes and rhythm, who made it, when, and when she was told. It can’t be edited or deleted; an undo is a new entry.",
 notes:[nn(1,"'This list can’t be edited or deleted. Every entry stays, and an undo is a new entry.'","the rule is a sealed banner at the top, never hidden in a footer.","history is append-only, like the court export."),
  nn(2,"filters All, People, Rhythm, Homes.","a segmented control with counts of kinds only, never totals of activity.","no engagement meter."),
  nn(3,"each entry has a state: Applied, Held until told, Scheduled, or Told her with the day.","the state is an icon-and-word pill, never colour only.","a change is visible to both guardians."),
  nn(4,"a held entry has 'I have told her'; most entries have 'Undo (as a new entry)'. A court order replies 'That is set by a court order.'","actions sit in the card as quiet text buttons; an undone entry fades and says so.","P8: nothing is deleted or edited."),
  nn(5,"empty: 'No changes yet. Every change to her people, homes and rhythm will appear here, with who made it and when she was told.'","a designed empty state with a clock illustration.","")],
 r:function(c){
  function h(txt,date,s,o){o=o||{};return '<div class="r3-hist'+(o.undone?" undone":"")+'"><b>'+E(txt)+'</b><div class="m">'+stpill(s)+'<span>'+E(date)+(o.told?" · on "+E(o.told):"")+'</span>'+(o.extra||"")+'</div>'+(o.act||"")+'</div>';}
  var main=seal("<b>This list can’t be edited or deleted.</b> Every entry stays, and an undo is a new entry.","lock",1)+K.segmented(["All","People","Rhythm","Homes"],0,{full:true,n:2})+
   '<div class="r3-stack"'+K.n(3)+'>'+h("Jess added Grandma Rosa to the family","2026-11-08","held",{act:'<div><button type="button" class="btn tonal sm">I have told her</button></div>'})+
   h("Marcus changed the rhythm to Alternating weeks","2026-11-02","scheduled",{extra:pill("quiet","for 2026-12-09","calendar")})+
   h("Jess told Ivy: Grandma Rosa was added","2026-10-30","told",{told:"2026-10-30"})+
   h("Marcus added Marcus’s house","2026-10-12","applied",{undone:true,extra:'<span>undone by a later entry</span>'})+
   h("Jess removed Marcus’s house","2026-10-14","applied",{extra:'<span>puts a change back; the first stays</span>',act:'<div><button type="button" class="btn ghost sm" '+K.n(4)+'>Undo (as a new entry)</button></div>'})+'</div>';
  var st=K.card(K.emptyState({spot:"envelope",title:"No changes yet",sub:"Every change to her people, homes and rhythm will appear here, with who made it and when she was told."}),"",5)+
   K.toast("That is set by a court order.",{ic:"lock",inline:true})+'<div class="r3-hist"><b>Jess changed the rhythm to 2-2-5-5</b><div class="m">'+pill("ok","Applied","check")+'<span>2026-09-01</span>'+pill("quiet","Set by order","lock")+'</div></div>';
  return lay(c,main,st,"Family history",{eyebrow:"Family structure",stLabel:"Empty and order-locked"});}});

S("AgeBands","guardian","Age bands","Family structure",{wide:true,refs:"family_structure_screens.dart, family_structure_logic.dart",
 desc:"Bands are proposals: a guardian can hold or change any of them, area by area. The steps on her ladder are permanent.",
 notes:[nn(1,"four bands (3 to 4 Three big pictures; 5 to 7 Pictures lead; 8 to 12 Words and her own list; 13 and up Mostly hers), each with summary lines; Ivy’s is marked.","the band cards are a light staircase with Ivy’s current card tinted and a pill.","her ladder steps are permanent and no hold can take one back."),
  nn(2,"'Bands are proposals. You can hold or change any of them.'","said once at the top in a sealed banner.","the guardian leads, the app proposes."),
  nn(3,"Next birthday: a birth date (yyyy-mm-dd, kept on this device) gives 'Ivy turns 6 on 2026-12-09. That is 31 sleeps away.' and whether her band moves.","a date field and one sentence, then the effect.","the birth date never leaves the device."),
  nn(4,"'Show Ivy a quiet line in her birthday week': one calm sentence, no counter, no tasks.","a switch with the promise in the subtitle.","no counter or task is added to a birthday."),
  nn(5,"By area (Reading and words, Games, Messages, Calendar and weeks, My people): each follows her band unless set.","five rows, each a chip showing Follows her band or a band.","a child can be ahead in reading and behind in other things."),
  nn(6,"Hold until I have told her, and a held card: 'Ivy is ready for 8 to 12, but her home is still 5 to 7. Nothing changes on her side until you release it.'","the held state is a warm card with one clear release button.","nothing changes on her side without being told.")],
 r:function(c){
  function band(l,n,sum,here){return '<div class="r3-band'+(here?" here":"")+'"><h5><span>'+l+' · '+n+'</span>'+(here?pill("pri","Ivy is here","sparkle"):"")+'</h5><ul>'+sum.map(function(s){return '<li>'+E(s)+'</li>';}).join("")+'</ul></div>';}
  var main=seal("<b>Bands are proposals.</b> You can hold or change any of them. The steps on her ladder are permanent.","sparkle",2)+
   '<div class="r3-stack"'+K.n(1)+'>'+band("3 to 4","Three big pictures",["No words to read","The call is the biggest thing"],false)+band("5 to 7","Pictures lead",["Every word can be heard","Her colour of the day","Games for two, in turns"],true)+band("8 to 12","Words and her own list",["Words beside pictures","A calendar of her weeks","Her own list arrives at 10"],false)+band("13 and up","Mostly hers",["Calendar, availability, a private journal","Each step up is hers, and permanent"],false)+'</div>'+
   K.card('<h4>Next birthday</h4>'+K.formField({label:"Ivy’s birth date (yyyy-mm-dd, kept on this device)",value:"2020-12-09",n:3})+'<div class="r3-call info" style="margin-top:8px">'+I("calendar",18,2)+'<span><b>Ivy turns 6 on 2026-12-09.</b> That is 31 sleeps away. Her band stays 5 to 7, so her home does not change.</span></div>'+row({ic:"heart",title:"Show Ivy a quiet line in her birthday week",sub:"One calm sentence in her last week. No counter, no tasks.",trail:K.toggle(true),n:4}))+
   K.card('<h4>By area</h4><p class="r3-sub">Each area follows her band unless you set it.</p>'+["Reading and words","Games","Messages","Calendar and weeks","My people"].map(function(a,i){return row({title:a,trail:'<span class="chip sm">'+(i===0?"8 to 12":"Follows her band")+'</span>',go:true,n:i===0?5:0});}).join("")+row({ic:"hourglass",title:"Hold until I have told her",sub:"When she moves to a new band, nothing changes on her side until you release it.",trail:K.toggle(true)}));
  var st=K.card('<b class="r3-h" style="font-size:16px"'+K.n(6)+'>Ivy is ready for 8 to 12, but her home is still 5 to 7.</b><p class="r3-sub">Nothing changes on her side until you release it.</p><div style="height:8px"></div>'+K.btn("I have told her: release",{full:true}),"tint")+
   K.formField({label:"Ivy’s birth date (yyyy-mm-dd, kept on this device)",value:"2026-13-40",error:"Use a real past date like 2019-04-02"})+
   K.card(eb("No birth date yet")+'<p class="r3-sub" style="margin:0">Add her birth date to see a preview of her next birthday.</p>',"flat");
  return lay(c,main,st,"Age bands",{eyebrow:"Family structure",stLabel:"Held move, bad date, no date"});}});

S("Birthday","child","My birthday","Family structure",{wide:true,refs:"family_structure_screens.dart",
 desc:"One calm page in Ivy’s birthday week. A number of sleeps and nothing to do. A guardian can hide it for the family, or in a hard year.",
 notes:[nn(1,"'N sleeps until your birthday' and 'There is nothing to do. It will just come.' Appears only in her last week and only if a guardian left it on.","the number is large and warm on her colour, the sentence under it, no confetti or task.","P2: no counter beyond sleeps, no streak, no task."),
  nn(2,"on the day: 'Today is your birthday'.","a single line and a soft illustration.","she isn’t asked to do anything."),
  nn(3,"a guardian can hide the line for the whole family.","when hidden the screen is simply not reachable.","")],
 r:function(c){
  var main='<div class="card hero r3-hero" style="text-align:center;padding:26px 16px"><div style="font:700 15px var(--font-body);opacity:.9">My birthday</div><div class="r3-big6"'+K.n(1)+'>6</div><p class="r3-h" style="font-size:20px;color:#fff">sleeps until your birthday</p></div>'+quiet("There is nothing to do. It will just come.","leaf")+K.speak("Hear it");
  var st=K.card('<div class="card tint" style="text-align:center;padding:24px 14px"><div style="display:flex;justify-content:center">'+K.spot("leaf",72)+'</div><p class="r3-h" style="font-size:24px;margin-top:8px"'+K.n(2)+'>Today is your birthday</p></div>',"")+K.card(eb("A guardian hid it")+'<p class="r3-sub" style="margin:0">The birthday line is not shown. Nothing else changes.</p>',"flat",3);
  return clay(c,main,st,"My birthday",{stLabel:"On the day, and hidden"});}});

/* ================================================================ PARENT LEARN == */
css([
".ob .r3-ev{display:inline-flex;gap:6px;align-items:center;padding:4px 10px 4px 8px;border-radius:99px;font:700 12px/1.1 var(--font-body);white-space:nowrap}",
".ob .r3-ev .bars{display:inline-flex;gap:2px;align-items:flex-end;height:11px}.ob .r3-ev .bars i{width:3px;border-radius:1px;background:currentColor;opacity:.3}.ob .r3-ev .bars i.f{opacity:1}",
".ob .r3-ev .bars i:nth-child(1){height:5px}.ob .r3-ev .bars i:nth-child(2){height:7px}.ob .r3-ev .bars i:nth-child(3){height:9px}.ob .r3-ev .bars i:nth-child(4){height:11px}",
".ob .r3-ev.strong{background:var(--okC);color:var(--ok)}.ob .r3-ev.moderate{background:var(--infoC);color:var(--info)}.ob .r3-ev.weak{background:var(--warnC);color:var(--warn)}.ob .r3-ev.contested{background:var(--priC);color:var(--onPriC)}",
".ob .r3-lc{display:grid;gap:8px;padding:14px;border-radius:20px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}.ob .r3-lc b{font:800 15.5px/1.25 var(--font-display)}.ob .r3-lc p{margin:0;font-size:13.5px;line-height:1.45;color:var(--ink2);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}",
".ob .r3-mirror{display:grid;gap:6px}",
".ob .r3-src{display:flex;gap:10px;align-items:flex-start;padding:10px 0;min-height:48px;border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}.ob .r3-src:first-of-type{border-top:0}.ob .r3-src .ico{color:var(--ink3);margin-top:2px;flex:none}.ob .r3-src b{font-size:13.5px;line-height:1.3;display:block}.ob .r3-src small{font-size:12px;color:var(--ink3);overflow-wrap:anywhere}",
".ob .r3-hint{display:grid;grid-template-columns:auto 1fr;gap:10px;padding:12px 14px;border-radius:16px;background:var(--infoC);color:var(--ink)}.ob .r3-hint .ico{color:var(--info);margin-top:2px}.ob .r3-hint b{font-size:13.5px;display:block}.ob .r3-hint span{font-size:13px;line-height:1.4;color:var(--ink2)}",
".ob .r3-mk{background:var(--warnC);color:var(--warn);border-radius:5px;padding:0 3px;font-weight:700}"
].join("\n"));
function ev(kind){var m={strong:["Strong evidence",4],moderate:["Moderate evidence",3],weak:["Weak evidence",2],contested:["Contested",0]}[kind];
 var g=kind==="contested"?I("swap",13,2):'<span class="bars" aria-hidden="true">'+[1,2,3,4].map(function(i){return '<i class="'+(i<=m[1]?"f":"")+'"></i>';}).join("")+'</span>';
 return '<span class="r3-ev '+kind+'">'+g+m[0]+'</span>';}
function priv(t){return pill("quiet",t||"Only you","lock");}
function sl(pct,label,val,n){return '<div'+K.n(n)+'><div style="display:flex;justify-content:space-between;font:700 13px var(--font-body);margin-bottom:2px"><span>'+E(label)+'</span><span class="tnum">'+val+'</span></div><div style="position:relative;height:44px"><span style="position:absolute;left:0;right:0;top:18px;height:8px;border-radius:8px;background:var(--surface3)"></span><span style="position:absolute;left:0;width:'+pct+'%;top:18px;height:8px;border-radius:8px;background:var(--pri)"></span><span style="position:absolute;top:8px;left:'+pct+'%;margin-left:-14px;width:28px;height:28px;border-radius:50%;background:var(--surface);border:3px solid var(--pri);box-shadow:var(--shadow1)"></span></div></div>';}
function lcard(t,body,e,n){return '<div class="r3-lc" role="button" tabindex="0"'+K.n(n)+'><b>'+E(t)+'</b><p>'+E(body)+'</p><div>'+ev(e)+'</div></div>';}

S("LearnHome","guardian","Learn","Parent Learn",{wide:true,refs:"parent_learn_screens.dart, parent_learn_logic.dart",
 desc:"Short, sourced, honest cards for a guardian, plus four private tools. Only the guardian sees it.",
 notes:[nn(1,"'Short, sourced, and honest about what is known.' and 'Only you can see this. Nothing here is shared with your co-parent or your child.'","a private banner with a lock pill, so the promise is seen before any card.","P7 spirit: nothing about the child’s inner life reaches a grown-up."),
  nn(2,"'Your tools' appear only when on: Where was today? (reflection not off), Check before you send, Rules that match; Your choices is always there.","each tool is a row whose subtitle states what happens to what you type.","every extra is optional and private by default."),
  nn(3,"topic chips All, style, discipline, communication, conflict, coparenting, repair; each card shows two lines and an evidence label (Strong, Moderate, Weak or Contested).","evidence is an icon-and-bars pill with its word, never colour alone.","a card never claims a style causes an outcome and never labels a person."),
  nn(4,"a non-guardian (child, sitter) sees only 'This area is for guardians.'","a plain lock card; nothing else renders.",""),
  nn(5,"the privacy line says nothing is shared, but 'Rules that match' shares a list with the other guardian.","drawn as built: flagged for an owner decision.","")],
 r:function(c){
  var tools=K.card(row({ic:"sliders",title:"Where was today?",sub:"Two sliders. Cleared when you close it.",go:true,n:2})+row({ic:"send",title:"Check before you send",sub:"A mirror, not a monitor. Nothing is sent or saved.",go:true})+row({ic:"list",title:"Rules that match",sub:"Bedtime, screens, homework, safety. You choose what to send.",go:true})+row({ic:"sliders",title:"Your choices",sub:"Each extra is optional and off or private by default.",go:true}));
  var main='<div class="card hero r3-hero"><div class="tx"><span class="r3-eb">For you</span><b class="r3-h">Short, sourced, and honest about what is known.</b></div><span class="art">'+K.spot("leaf",84,{plate:false})+'</span></div>'+
   seal("<b>Only you can see this.</b> Nothing here is shared with your co-parent or your child.","lock",1)+K.sectionLabel("Your tools")+tools+
   '<div'+K.n(3)+'>'+K.filterChips(["All","style","discipline","communication","conflict","coparenting","repair"],[0],{wrap:true})+'</div>'+
   '<div class="r3-stack">'+lcard("Two things, not four boxes","Home feels like a mix of warmth and expectations. The four named styles are corners of that map, not types of person. Most days you move around it.","strong")+lcard("Warm and clear","Children tend to do well on school, mood and friendships when warmth and clear limits go together. This is a link in studies, not a promise, and it is not risk-free.","moderate")+lcard("A short, calm time-out","A brief pause with a calm adult can help, and what matters is that it is predictable and kind.","moderate")+'</div>';
  var st=K.card('<div style="display:grid;justify-items:center;gap:8px;padding:12px 6px;text-align:center">'+K.spot("lock",72)+'<b class="r3-h" '+K.n(4)+'>This area is for guardians.</b></div>',"")+
   K.card(eb("Every extra off")+row({ic:"sliders",title:"Your choices",sub:"Each extra is optional and off or private by default.",go:true})+'<p class="r3-fine" style="margin-top:6px">With reflection off and both switches off, only Your choices remains.</p>',"flat")+call("The home line says nothing is shared. The Rules tool does share a list with the other guardian once you press Add and share.","warn","flag",5);
  return lay(c,main,st,"Learn",{eyebrow:"Parent Learn",stLabel:"Denied, and all tools off"});}});

S("LearnCard","guardian","Learn card","Parent Learn",{refs:"parent_learn_screens.dart",
 desc:"One card: the evidence label, the plain claim, sources with links, and the one honest line that this is education, not clinical advice.",
 notes:[nn(1,"every card has an evidence label and at least one source, never claims a style causes an outcome.","the evidence pill leads and the claim reads at 16 px with generous line height.","no causal claim, no person labelled."),
  nn(2,"'Sources' lists each label and URL as selectable text.","each source is a row with an external-link glyph and the URL kept small, selectable.","every claim can be checked."),
  nn(3,"'This is education, not clinical advice. If you are worried about your child, talk to your pediatrician.'","said once, in a calm card at the end, with no alarm colour.","")],
 r:function(){return T("Warm and clear",{eyebrow:"Style"})+P(
  '<div'+K.n(1)+'>'+ev("moderate")+'</div><p style="font:400 16px/1.6 var(--font-body);margin:0">Children tend to do well on school, mood and friendships when warmth and clear limits go together. This is a link in studies, not a promise, and it is not risk-free.</p>'+
  K.card('<h4>Sources</h4><div'+K.n(2)+'><div class="r3-src">'+I("link",16,2)+'<div><b>Darling and Steinberg 1993</b><small>https://data.zhenzhi.com/details/1/1001468350</small></div></div><div class="r3-src">'+I("link",16,2)+'<div><b>ParentData: is gentle parenting evidence-based</b><small>https://parentdata.org/ask/is-gentle-parenting-evidence-based-does-it-actually-work</small></div></div></div>')+
  K.card('<p class="r3-sub" style="margin:0"'+K.n(3)+'>This is education, not clinical advice. If you are worried about your child, talk to your pediatrician.</p>',"flat"));}});

S("LearnChoices","guardian","Your choices","Parent Learn",{wide:true,refs:"parent_learn_screens.dart",
 desc:"Every extra is optional and off or private by default. Nothing here is visible to the co-parent or the child.",
 notes:[nn(1,"'Where was today? (private reflection)': Off, Just for now (nothing kept) or Save privately (kept for you only, never exported).","three radio cards, each stating exactly what is kept.","P7 spirit: private by default."),
  nn(2,"'How things are framed': neutral, Add a culture note, Start from my family’s values.","three plain radio rows.","a framing never labels a person."),
  nn(3,"Message check and Rules that match are switches; turning Rules off clears your list.","the consequence is in the subtitle, before the tap.","nothing is sent or saved by the check."),
  nn(4,"'Every one of these is optional. Nothing here is visible to your co-parent or your child.'","a leading banner with a lock.","the one exception, Rules, is flagged on its own row.")],
 r:function(c){
  var main=seal("<b>Every one of these is optional.</b> Nothing here is visible to your co-parent or your child.","lock",4)+
   K.card('<h4>Where was today? (private reflection)</h4><div class="r3-stack"'+K.n(1)+' style="margin-top:8px">'+opt("Off","The tool isn’t offered.",false)+opt("Just for now","Nothing is kept. It clears when you close it.",true)+opt("Save privately","Kept for you only. Never shown to anyone else, never exported.",false)+'</div>',"")+
   K.card('<h4>How things are framed</h4><div class="r3-stack" '+K.n(2)+' style="margin-top:8px">'+opt("Neutral","",true)+opt("Add a culture note","Reminds you that what a style means can differ by family and culture.",false)+opt("Start from my family’s values","Reads the cards as ideas to weigh against what matters to you.",false)+'</div>',"")+
   K.card(row({ic:"send",title:"Message check",sub:"Offers hints before you send a message to the other guardian. Runs on this phone. Nothing is sent or saved.",trail:K.toggle(true),n:3})+row({ic:"list",title:"Rules that match",sub:"A short list of core routines you can choose to share with the other guardian. Turning it off clears your list.",trail:K.toggle(false)}),"");
  var st2=K.card(eb("Turning Rules off")+'<div class="r3-dlg" style="box-shadow:none"><span class="r3-pl warn">'+I("trash",20,2)+'</span><h4>Turn off Rules that match?</h4><p class="r3-sub">This clears your list. The other guardian’s list is theirs and stays.</p><div class="acts">'+K.btn("Keep it on",{kind:"tonal"})+K.btn("Turn off",{kind:"danger"})+'</div></div><p class="r3-fine" style="margin-top:6px">The confirmation is a refinement; the shipped switch clears the list at once.</p>',"flat");
  return lay(c,main,st2,"Your choices",{eyebrow:"Parent Learn",stLabel:"A refinement to consider"});}});

S("LearnToday","guardian","Where was today?","Parent Learn",{wide:true,refs:"parent_learn_screens.dart, parent_learn_logic.dart",
 desc:"Two sliders and a mirror. It describes the day, never the person. Kept only if you chose to save.",
 notes:[nn(1,"two sliders, Warmth and Expectations, 0 to 100, each shown with its number; 'Two sliders. No grade. Just a mirror.'","labelled with words at each end as well as the number, and the number stays small.","Round 2 said no numbers appear; the shipped screen shows them. Flagged."),
  nn(2,"the mirror gives a headline and a prompt, e.g. 'Warm today, with looser limits.' and 'Notice: was it a choice, or were you tired?'","one quiet card; no quadrant has a name and no word labels a parent.","describes the day, not the person."),
  nn(3,"if saving is on: Save privately, then a list of days with a Delete each; otherwise 'Private. Cleared when you close this. Not shared with anyone.'","the status pill says in one glance whether this will be kept.","reflections are never exported."),
  nn(4,"the four mirrors: warm with clear limits; firm with less warmth; warm with looser limits; low on both ('Are you okay? Support is fine to ask for.').","the kindness in the fourth is kept word for word.","")],
 r:function(c){
  var main=sl(72,"Warmth","72",1)+sl(35,"Expectations","35")+
   K.card('<span class="r3-eb">A mirror, not a grade</span><b class="r3-h" style="font-size:17px"'+K.n(2)+'>Warm today, with looser limits.</b><p class="r3-sub">Notice: was it a choice, or were you tired? One clear limit may be enough.</p>',"tint")+
   '<div style="display:flex;gap:8px;align-items:center"'+K.n(3)+'>'+priv("Not saved")+'<span class="r3-fine">Private. Cleared when you close this. Not shared with anyone.</span></div>'+K.btn("Done",{full:true,size:"lg",ic:"check"});
  var st=K.card(eb("With saving on")+K.btn("Save privately",{full:true,ic:"lock"})+'<p class="r3-fine" style="margin:6px 0">Saved for you.</p>'+row({title:"2026-11-07",sub:"Warm, with clear limits.",trail:K.iconBtn("trash",{label:"Delete",kind:"sm"})})+row({title:"2026-11-05",sub:"Low on both today.",trail:K.iconBtn("trash",{label:"Delete",kind:"sm"})}),"",3)+
   K.card(eb("The fourth mirror")+'<b class="r3-h" style="font-size:16px">Low on both today.</b><p class="r3-sub">Notice: are you okay? Support is fine to ask for. Tomorrow is a fresh day.</p>',"flat",4);
  return lay(c,main,st,"Where was today?",{eyebrow:"Parent Learn",stLabel:"Saved, and the fourth mirror"});}});

S("LearnCheck","guardian","Check before you send","Parent Learn",{wide:true,refs:"parent_learn_screens.dart, parent_learn_logic.dart",
 desc:"An optional mirror for a message to the other guardian. It shows patterns and suggestions, never rewrites or sends, and keeps nothing.",
 notes:[nn(1,"off unless opted in: 'Turn on the message check in Your choices to use this.'","the off state is a designed card with a direct way to the switch.","the check runs on this phone only."),
  nn(2,"a draft up to 4000 characters, then Check; hints name six patterns (absolutes, blame, contempt, using the child as messenger, questioning the child, threats).","patterns are marked in the draft, each with one alternative.","a mirror, not a monitor."),
  nn(3,"'Nothing to flag. Brief, clear and friendly is a good place to be.' when clean; 'These are suggestions. The words are yours to change.'","both are kind and brief.","nothing is sent, saved or shared; closing clears it."),
  nn(4,"Clear empties the draft.","a quiet ghost button next to Check.","")],
 r:function(c){
  var main=seal("<b>A mirror, not a monitor.</b> Runs on this phone. Nothing is sent, saved or shared. Closing this clears it.","lock",3)+
   K.card(lab("Your draft")+'<p class="g" style="margin:0;font-size:14.5px;line-height:1.6"'+K.n(1)+'>You <span class="r3-mk">never</span> read the reading log. Ivy was upset <span class="r3-mk">because of you</span> on Tuesday.</p>')+
   '<div class="r3-two">'+K.btn("Check",{ic:"check"})+K.btn("Clear",{kind:"ghost",n:4})+'</div>'+
   '<div class="r3-stack"'+K.n(2)+'><div class="r3-hint">'+I("info",18,2)+'<div><b>An absolute</b><span>Try the one thing that happened: “On Friday bedtime was late.”</span></div></div><div class="r3-hint">'+I("info",18,2)+'<div><b>Blame</b><span>Describe the effect, not who is at fault.</span></div></div></div><p class="r3-fine">These are suggestions. The words are yours to change.</p>';
  var st=K.card(eb("Switched off")+K.emptyState({spot:"envelope",title:"Check before you send",sub:"Turn on the message check in Your choices to use this.",action:"Open Your choices"}),"",1)+K.card(eb("Nothing to flag")+quiet("Nothing to flag. Brief, clear and friendly is a good place to be.","check"),"flat");
  return lay(c,main,st,"Check before you send",{eyebrow:"To Marcus",stLabel:"Off, and clean"});}});

S("LearnRules","guardian","Rules that match","Parent Learn",{wide:true,refs:"parent_learn_screens.dart",
 desc:"A short list of core routines you choose to share with the other guardian. Only four kinds of rule can be shared, never a style or a reflection.",
 notes:[nn(1,"'Optional. You edit your own list. Nothing is compared for you. Only these four kinds of rule can be shared, never a style or a reflection.'","the limit leads, then the list.","sharing is a deliberate tap, never automatic."),
  nn(2,"categories Bedtime, Screens, Homework, Safety; a rule up to 200 characters; Add and share, then 'Added. The other guardian can now see it.'","the button says exactly what it does and the confirmation follows in place.","what is shared is shown before it is sent."),
  nn(3,"'Nothing yet.' and 'They have not shared a list.' when empty.","two designed empty states.",""),
  nn(4,"the other guardian’s list is read-only: 'Differences are fine when it is calm. Low conflict matters more than matching.'","a calm card, no comparison or match score.","no scoring of agreement.")],
 r:function(c){
  var main=seal("<b>Optional.</b> You edit your own list. Nothing is compared for you. Only these four kinds of rule can be shared, never a style or a reflection.","list",1)+
   K.sectionLabel("Your list")+K.card(row({title:"Lights out by 7:30",sub:"Bedtime",trail:K.iconBtn("x",{label:"Remove",kind:"sm"})})+row({title:"Tablet off at dinner",sub:"Screens",trail:K.iconBtn("x",{label:"Remove",kind:"sm"})}))+
   K.card('<div class="r3-sty" '+K.n(2)+' style="margin-bottom:8px"><span class="on">Bedtime</span><span>Screens</span><span>Homework</span><span>Safety</span></div>'+K.formField({label:"A rule at your house",value:"Reading log signed on Thursdays",hint:"Up to 200 letters"})+'<div style="height:8px"></div>'+K.btn("Add and share",{full:true})+'<p class="r3-fine" style="margin-top:6px">Added. The other guardian can now see it.</p>')+
   K.sectionLabel("The other guardian’s list")+K.card('<b style="font-size:13px"'+K.n(4)+'>Marcus</b>'+row({title:"Bedtime story every night",sub:"Bedtime"})+row({title:"Homework before games",sub:"Homework"}))+'<p class="r3-fine">Differences are fine when it is calm. Low conflict matters more than matching.</p>';
  var st=K.card(eb("Your list is empty")+quiet("Nothing yet.","list"),"flat",3)+K.card(eb("Marcus has not shared")+quiet("They have not shared a list.","users"),"flat",3)+K.card(eb("Switched off")+K.emptyState({spot:"leaf",title:"Rules that match",sub:"Turn on “Rules that match” in Your choices to use this."}),"");
  return lay(c,main,st,"Rules that match",{eyebrow:"Parent Learn",stLabel:"Empty and off"});}});

/* ======================================================== RHYTHM AND VOICE == */
css([
".ob .r3-bc{display:grid;justify-items:center;gap:10px;padding:54px 14px 20px;border-radius:30px;text-align:center;position:relative}",
".ob .r3-bc.first{background:radial-gradient(90% 70% at 100% 0%,rgba(255,255,255,var(--sheen,.07)),transparent 62%),linear-gradient(155deg,var(--hero1),var(--hero2));color:var(--onPri);box-shadow:var(--shadow2)}",
".ob .r3-bc.then{background:var(--surface);border:1.5px solid var(--outline);color:var(--ink);box-shadow:var(--shadow1)}",
".ob .r3-bc .hd{position:absolute;left:16px;top:20px;font:700 12px/1 var(--font-mono);letter-spacing:.12em;text-transform:uppercase;opacity:.88}",
".ob .r3-bc .gi{width:104px;height:104px;border-radius:34px;background:rgba(255,255,255,.2);display:grid;place-items:center}.ob .r3-bc.then .gi{background:var(--priC);color:var(--onPriC)}",
".ob .r3-bc b{font:800 26px/1.1 var(--font-display);letter-spacing:-.015em}",
".ob .r3-bc .sp{position:absolute;right:10px;top:10px;width:48px;height:48px;border-radius:50%;display:grid;place-items:center;background:rgba(255,255,255,.18)}.ob .r3-bc.then .sp{background:var(--surface2);color:var(--ink2)}",
".ob .r3-bc .ck{position:absolute;left:12px;bottom:12px;width:34px;height:34px;border-radius:50%;background:var(--ok);color:var(--bg);display:grid;place-items:center}",
".ob .r3-strip{display:flex;gap:8px;justify-content:center;flex-wrap:wrap}",
".ob .r3-strip>span{position:relative;width:56px;height:56px;border-radius:19px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center}",
".ob .r3-strip>span.cur{box-shadow:0 0 0 3px var(--pri)}.ob .r3-strip>span.dn{opacity:.55}.ob .r3-strip>span .tk{position:absolute;right:-3px;bottom:-3px;width:22px;height:22px;border-radius:50%;background:var(--ok);color:var(--bg);display:grid;place-items:center}",
".ob .r3-chipsame{display:inline-flex;gap:8px;align-items:center;min-height:48px;padding:0 14px 0 10px;border-radius:99px;background:var(--surface2);border:1px solid var(--line);font:700 14px var(--font-body);color:var(--ink2)}",
".ob .r3-room{border-radius:28px;display:grid;place-items:center;min-height:190px;background:linear-gradient(160deg,var(--priC),var(--priC2));color:var(--onPriC);box-shadow:var(--shadow1)}",
".ob .r3-plan{display:grid;gap:8px;padding:16px;border-radius:24px;background:var(--surface2)}.ob .r3-plan>div{display:flex;gap:10px;align-items:center;font:700 17px/1.3 var(--font-body)}",
".ob .r3-nav{display:grid;grid-template-columns:1fr 1fr;gap:10px}",
".ob .r3-tool{display:flex;gap:14px;align-items:center;min-height:84px;padding:12px 16px;border-radius:26px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);font:800 18px/1.15 var(--font-display);color:var(--ink)}",
".ob .r3-tool .gi{width:56px;height:56px;border-radius:19px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;flex:none}",
".ob .r3-choose{display:grid;gap:10px}.ob .r3-choose .btn{justify-content:flex-start;gap:12px;text-align:left}",
".ob .r3-pad{height:200px;border-radius:24px;background:var(--surface);border:2px dashed var(--edge);position:relative;overflow:hidden}",
".ob .r3-sent{display:flex;gap:8px;flex-wrap:wrap;min-height:84px;padding:12px;border-radius:24px;background:var(--surface);border:1.5px solid var(--edge);align-items:center;justify-content:center}",
".ob .r3-sent span{display:grid;justify-items:center;gap:2px;width:60px;font:800 13px/1.1 var(--font-display)}.ob .r3-sent span i{width:44px;height:44px;border-radius:15px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;font-style:normal}",
".ob .r3-sym{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.ob.f-cover .r3-sym{grid-template-columns:repeat(3,minmax(0,1fr))}",
".ob .r3-sym>div{min-height:72px;border-radius:20px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);display:grid;place-items:center;align-content:center;gap:2px;font:800 12.5px/1.1 var(--font-display);text-align:center;padding:6px 2px}.ob .r3-sym>div.x{background:var(--accentC)}",
".ob .r3-helper{display:flex;gap:14px;align-items:center;padding:14px;border-radius:26px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}.ob .r3-helper .gi{width:64px;height:64px;border-radius:22px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;flex:none}.ob .r3-helper b{font:800 19px/1.15 var(--font-display);display:block}.ob .r3-helper small{font-size:14px;color:var(--ink2)}",
".ob .r3-wthumb{border-radius:22px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);display:grid;place-items:center;align-content:center;gap:4px;min-height:96px;font:700 12.5px var(--font-body);color:var(--ink2);text-align:center;padding:6px;position:relative}",
".ob .r3-wthumb.sel{box-shadow:0 0 0 3px var(--pri),var(--shadow1)}.ob .r3-wthumb .eye{position:absolute;right:6px;top:6px;color:var(--ink3)}",
".ob .r3-brs{position:relative;height:44px}.ob .r3-brs .tr{position:absolute;left:0;right:0;top:18px;height:8px;border-radius:8px;background:var(--surface3)}.ob .r3-brs .fl{position:absolute;left:0;top:18px;height:8px;border-radius:8px;background:var(--pri)}.ob .r3-brs .th{position:absolute;top:8px;width:28px;height:28px;margin-left:-14px;border-radius:50%;background:var(--surface);border:3px solid var(--pri);box-shadow:var(--shadow1)}"
].join("\n"));
function bc(kind,head,id,label,o){o=o||{};return '<div class="r3-bc '+kind+'"'+K.n(o.n)+'>'+(o.check?'<span class="ck">'+I("check",20,3)+'</span>':"")+'<span class="sp">'+I("volume",22,2)+'</span><span class="hd">'+E(head)+'</span><span class="gi">'+glyph(id,56,1.7)+'</span><b>'+E(label)+'</b></div>';}
function strip(items,cur){return '<div class="r3-strip" aria-label="Today’s steps">'+items.map(function(x,i){return '<span class="'+(x[1]?"dn":"")+(i===cur?" cur":"")+'" role="img" aria-label="'+E(PL[x[0]]+(x[1]?", done":""))+'">'+glyph(x[0],28,1.8)+(x[1]?'<i class="tk">'+I("check",13,3.2)+'</i>':"")+'</span>';}).join("")+'</div>';}

S("Routine","child","My routine","Rhythm and voice",{wide:true,refs:"rhythm_screens.dart, rhythm_logic.dart",
 desc:"One routine in pictures, one step at a time: First and Then, one big Done. Finishing is a calm resting state, not a result.",
 notes:[nn(1,"First and Then cards from the guardian’s ordered picture steps (up to 8, each with a name).","First is a large lit card; Then is a quiet card beside or below it, so the next thing is known without being pressed on her.","P2: no 'step 3 of 8', no bar, no star, no streak."),
  nn(2,"one big Done (72 dp) ticks the step she is on; she can only tick the step she is on.","Done is the only action; a tick appears on the strip and the card changes in 250 ms.","a tick is a private bit for today and is dropped tomorrow."),
  nn(3,"the whole routine as a quiet picture strip, a ticked step paler with a check.","the strip is small and unnumbered; the current step carries a ring.","no count anywhere."),
  nn(4,"finished: 'All done' with a check and Again.","a resting page; Again starts it over.","finishing is calm, not a result."),
  nn(5,"if a guardian hasn’t made one: 'Your grown-up has not made one yet.'","a friendly quiet note with the picture of a checklist.","absent, not broken.")],
 r:function(c){
  var steps=[["teeth",1],["pyjamas",0],["book",0],["lights-out",0]];
  var main='<h2 class="r3-h" style="text-align:center;font-size:22px">Bedtime</h2><div class="r3-two">'+bc("first","First","pyjamas","Pyjamas",{n:1})+bc("then","Then","book","A book")+'</div>'+K.btn("Done",{ic:"check",full:true,size:"lg",n:2})+'<div'+K.n(3)+'>'+strip(steps,1)+'</div>'+motion("the card changes in 250 ms; reduce motion makes it appear.");
  var st=K.card('<div style="display:grid;justify-items:center;gap:10px;padding:14px"'+K.n(4)+'><span class="r3-pl ok" style="width:84px;height:84px;border-radius:50%">'+I("check",44,2.4)+'</span><b class="r3-h" style="font-size:26px">All done</b></div>'+K.btn("Again",{kind:"tonal",full:true,ic:"refresh",size:"lg"}),"")+K.card(eb("Not made yet")+quiet("Your grown-up has not made one yet.","list")+'',"flat",5);
  return clay(c,main,st,"My routine",{stLabel:"All done, and not made yet"});}});

S("FirstThen","child","First, then","Rhythm and voice",{refs:"rhythm_screens.dart",
 desc:"Two cards a guardian chose: what comes first, what comes next. Done turns Then into Now, for today only.",
 notes:[nn(1,"First and Then, two cards from the picture library.","stacked, big, spoken on tap; First is lit until it is done.","no timer, no countdown."),
  nn(2,"Done turns Then into Now and shows a check on First, for today only.","the check is a green round badge, not a score.","resets tomorrow."),
  nn(3,"'Your grown-up has not set this up yet.'","the quiet note keeps the page, with a swap glyph.","")],
 r:function(c){
  return CT("First, then")+P(bc("first","First","shoes","Shoes on",{n:1,check:true})+bc("then","Now","car","Car ride",{n:2})+K.card(eb("Not set up")+quiet("Your grown-up has not set this up yet.","swap"),"flat",3)+motion("Then becomes Now with a 250 ms fade."),{cls:"r3c"});}});

S("Bag","child","My bag","Rhythm and voice",{wide:true,refs:"rhythm_screens.dart",
 desc:"The picture list for the exchange bag. Things to bring are tickable; things that are the same in both homes are shown calmly and can never be ticked.",
 notes:[nn(1,"'My things': a grid of pictures she can tick and un-tick (kept three days, then dropped).","big picture tiles, a green check on a packed one, nothing says forgotten or missing.","P2: no 'forgotten', no count, no stars."),
  nn(2,"'Always the same': chips that can’t be ticked. 'These stay the same wherever you sleep.'","soft chips, quiet by design, with the sentence kept.","a thing that is always there can’t be 'forgotten'."),
  nn(3,"shown only for two sleeping homes (or a guardian’s local setting); otherwise absent.","no empty tile; the tile simply isn't offered.","absent, not broken."),
  nn(4,"'Your grown-up has not made a bag list yet.'","quiet note with a bag.","")],
 r:function(c){
  var main='<h2 class="r3-h" style="font-size:22px">My things</h2><div class="r3-pg" '+K.n(1)+'>'+PT("owl",{tick:true,sel:true})+PT("teddy",{tick:true,sel:true})+PT("boots")+PT("lunch")+PT("glasses")+PT("library-book")+'</div>'+
   '<h2 class="r3-h" style="font-size:22px">Always the same</h2><div style="display:flex;flex-wrap:wrap;gap:8px"'+K.n(2)+'><span class="r3-chipsame">'+glyph("toothbrush",22)+'Toothbrush</span><span class="r3-chipsame">'+glyph("night-light",22)+'Night-light</span><span class="r3-chipsame">'+glyph("blanket",22)+'Blanket</span></div><p class="r3-sub">These stay the same wherever you sleep.</p>';
  var st=K.card(eb("No list yet")+quiet("Your grown-up has not made a bag list yet.","layers"),"flat",4)+K.card(eb("One home only")+'<p class="r3-sub" style="margin:0">The bag isn’t offered. There is nothing to carry between homes.</p>',"flat",3);
  return clay(c,main,st,"My bag",{stLabel:"Not made yet, and one home"});}});

S("NewPlace","child","A new place","Rhythm and voice",{wide:true,refs:"rhythm_screens.dart, rhythm_voice_guardian_screens.dart",
 desc:"A gentle walk through a place before she goes: a few rooms in pictures or small photos, each with a short caption, then a short plan.",
 notes:[nn(1,"up to eight rooms, each a room picture or a small photo with a caption, read aloud on tap.","one big picture per screen, the caption large; Back and Next 64 dp.","P3: rooms only, no address, no map, no coordinates."),
  nn(2,"after the last room, 'What will happen': up to four plan lines, each can be heard.","a calm list with arrows and speaker buttons; All done ends it.","nothing says what to feel."),
  nn(3,"a photo is a small JPEG or PNG (150 KB at most); without one, a room picture draws.","the photo has a rounded frame, the picture version a soft gradient plate.","photos stay on this device."),
  nn(4,"'Your grown-up has not got this ready yet.'","a quiet note with a house.","")],
 r:function(c){
  var main='<div class="r3-room"'+K.n(1)+' style="min-height:200px">'+glyph("my-room",96,1.5)+'</div><div style="display:flex;gap:10px;align-items:center"><b class="r3-h" style="font-size:24px;flex:1">This is the room where you will sleep.</b>'+K.iconBtn("volume",{kind:"tonal",label:"Hear this"})+'</div><div class="r3-nav"><button type="button" class="btn ghost">'+I("arrowL",22,2.2)+'Back</button><button type="button" class="btn pri">Next'+I("arrowR",22,2.2)+'</button></div>';
  var st=K.card(eb("A room with a photo")+ph("Room photo, sample",150)+'<p class="r3-h" style="font-size:20px;margin-top:8px">Here is the kitchen.</p>',"",3)+
   K.card(eb("The plan")+'<div class="r3-plan"'+K.n(2)+'><div>'+I("arrowR",20,2.2)+'<span style="flex:1">We drive there after school.</span>'+K.iconBtn("volume",{kind:"sm",label:"Hear this"})+'</div><div>'+I("arrowR",20,2.2)+'<span style="flex:1">Dinner, then a story.</span>'+K.iconBtn("volume",{kind:"sm",label:"Hear this"})+'</div></div>'+K.btn("All done",{full:true,ic:"check",size:"lg"}),"")+
   K.card(eb("Not ready")+quiet("Your grown-up has not got this ready yet.","home"),"flat",4);
  return clay(c,main,st,"Grandma Rosa’s house",{stLabel:"A photo room, the plan, not ready"});}});

S("RhythmHub","guardian","Routine and rhythm","Rhythm and voice",{wide:true,refs:"rhythm_voice_guardian_screens.dart, rhythm_voice_gate.dart",
 desc:"The guardian hub for Ivy’s routine, first-then cards, bag, a new place, and how the app feels. All of it stays on this device.",
 notes:[nn(1,"'Kept on this device only. It is not shared with Ivy’s other home yet.'","a sealed banner leading the screen.","local-first; sharing between homes is parked."),
  nn(2,"'Show on Ivy’s device' (the Rhythm suite) and 'Ivy sleeps in two homes' (a local fallback so the packing buddy can show when the app can’t tell).","each switch says exactly when it matters; the fallback says it is off unless you turn it on.","the family model wins when it has an answer."),
  nn(3,"five rows: One routine, First then, Packing buddy, A new place, How the app feels.","each row has a picture-first icon and the one thing it holds.","every word is the guardian’s; the app adds none."),
  nn(4,"the routine editor: a name, up to eight steps (each a picture and a short name), reorder, remove, and 'Remove the routine from her device'.","steps are draggable rows with the picture on the left; the limit message is kind.","a name that looks like an address or number is refused (P3)."),
  nn(5,"the youngest band (3 to 4) gets nothing from Rhythm.","said in the age note, not hidden.","")],
 r:function(c){
  var main=seal("<b>Kept on this device only.</b> It is not shared with Ivy’s other home yet.","device",1)+
   '<p class="r3-sub" style="margin:0">Ivy is 5, so Rhythm can show on her device, and only when the switch below is on.</p>'+
   K.card(row({ic:"sun",title:"Show on Ivy’s device",trail:K.toggle(true),n:2})+row({ic:"home",title:"Ivy sleeps in two homes",sub:"A setting kept on this device only. It lets the packing buddy show when the app cannot tell how many homes she has. Off unless you turn it on.",trail:K.toggle(false)}),"")+
   K.card(row({ic:"list",title:"One routine",sub:"Pictures in order, like bedtime",go:true,n:3})+row({ic:"swap",title:"First, then",sub:"Two cards: what happens first, what next",go:true})+row({ic:"layers",title:"Packing buddy",sub:"The picture list for the exchange bag",go:true})+row({ic:"home",title:"A new place",sub:"A gentle preview: rooms and a short plan",go:true})+row({ic:"sliders",title:"How the app feels",sub:"Sound, motion and brightness on her device",go:true}),"");
  var st=K.card(eb("One routine, edited")+K.formField({label:"Name of the routine",value:"Bedtime"})+'<div style="height:8px"></div>'+["teeth|Brush teeth","pyjamas|Pyjamas","book|A book"].map(function(x){var p=x.split("|");return '<div class="r3-sr"><span class="r3-pl">'+glyph(p[0],20)+'</span><b style="font-size:14.5px">'+E(p[1])+'</b><span style="display:flex;gap:4px">'+K.iconBtn("chevU",{kind:"sm",label:"Move up"})+K.iconBtn("chevD",{kind:"sm",label:"Move down"})+K.iconBtn("x",{kind:"sm",label:"Remove"})+'</span></div>';}).join("")+'<div style="height:8px"></div>'+K.btn("Add a step",{kind:"tonal",full:true,ic:"plus"})+'<div style="height:8px"></div>'+K.btn("Save",{full:true})+K.btn("Remove the routine from her device",{kind:"danger",full:true}),"",4)+
   K.toast("Saved on this device.",{ic:"check",inline:true})+call("Please leave out addresses and places. Rooms only.","warn","warn")+call("That is the most there is room for.","warn","info")+call("The youngest band (3 to 4) gets nothing from Rhythm: no More hub, no settings.","info","info",5);
  return lay(c,main,st,"Routine and rhythm",{eyebrow:"Ivy’s device",stLabel:"The routine editor and its limits"});}});

S("Sensory","guardian","How the app feels","Rhythm and voice",{refs:"rhythm_voice_guardian_screens.dart, rhythm_screens.dart",
 desc:"Sound, motion, buzzing and a brightness ceiling for Ivy’s device. It describes the app, never the child, and carries no label.",
 notes:[nn(1,"'These describe the app on her device, not her. Nothing here is a label.'","said first, in a quiet banner.","no diagnosis, no label, no free text."),
  nn(2,"Sound is Off, Low, Medium or Full; No motion ('Pages simply change'); No buzzing.","a four-segment control and two switches, 48 dp.","reduce only: this can never turn motion back on."),
  nn(3,"'No flashing, ever. This is always so.' is a fact, not a setting.","drawn as a fixed row with a lock, so it can’t be mistaken for a switch.","nothing ever flashes."),
  nn(4,"'Brightest the app may be': 30 to 100 in steps of 10, applied as a soft dim layer.","the slider shows the value as a word-and-number and previews the dim.","")],
 r:function(){return T("How the app feels",{eyebrow:"Ivy’s device"})+P(
  seal("<b>These describe the app on her device, not her.</b> Nothing here is a label.","info",1)+
  K.card(lab("Sound")+K.segmented(["Off","Low","Medium","Full"],2,{full:true,n:2}),"")+
  K.card(row({ic:"pause",title:"No motion",sub:"Pages simply change",trail:K.toggle(true)})+row({ic:"hand",title:"No buzzing",trail:K.toggle(false)})+row({ic:"lock",title:"No flashing, ever",sub:"This is always so.",trail:pill("ok","Always","check"),n:3}),"")+
  K.card(lab("Brightest the app may be")+'<div class="r3-brs"'+K.n(4)+'><span class="tr"></span><span class="fl" style="width:60%"></span><span class="th" style="left:60%"></span></div><div style="display:flex;justify-content:space-between" class="r3-fine"><span>30%</span><span><b>72%</b></span><span>100%</span></div>')+
  K.toast("Saved on this device.",{ic:"check",inline:true}));}});

S("Weather","child","The sky in me","Rhythm and voice",{wide:true,refs:"voice_screens.dart, voice_logic.dart, picture_library.dart",
 desc:"A picture of weather for how today feels. Only Ivy can see it; there is no show button, no history and no count.",
 notes:[nn(1,"six skies: Sunny, Cloudy, Rainy, Stormy, Windy, Foggy; 'What is the sky like in you today?'","six big picture tiles, each spoken on tap; the picked one has a ring and no ‘good/bad’ order.","no sky is good or bad; a test checks the names."),
  nn(2,"'Only you can see this. It stays on this device.' and a Clear it button.","the promise is a calm note; Clear it appears only after a pick.","there is no show or send control at all (P7)."),
  nn(3,"only today’s pick is kept, two fields (weather, day); a guardian read is refused.","no past days anywhere.","no history to chart."),
  nn(4,"Voice starts off: until a guardian turns it on, this tile doesn’t exist for her.","absent, not disabled.","§8.24.1 fail closed.")],
 r:function(c){
  var main='<h2 class="r3-h" style="font-size:22px;text-align:center">What is the sky like in you today?</h2><div class="r3-pg"'+K.n(1)+'>'+PT("sunny")+PT("cloudy")+PT("rainy",{sel:true})+PT("stormy")+PT("windy")+PT("foggy")+'</div>'+quiet("Only you can see this. It stays on this device.","lock")+'<div'+K.n(2)+'>'+K.btn("Clear it",{kind:"ghost",full:true,ic:"x"})+'</div>';
  var st=K.card(eb("Nothing picked")+'<div class="r3-pg">'+PT("sunny")+PT("cloudy")+PT("rainy")+'</div>'+quiet("Only you can see this. It stays on this device.","lock"),"flat",3)+K.card(eb("What a guardian sees")+K.emptyState({spot:"lock",title:"Nothing",sub:"This is hers. A grown-up cannot open it."}),"",3)+K.card(eb("Voice is off")+'<p class="r3-sub" style="margin:0">This tile isn’t on her page at all until a guardian turns Voice on.</p>',"flat",4);
  return clay(c,main,st,"The sky in me",{stLabel:"Nothing picked, and the guardian’s view"});}});

S("WorryBox","child","My worry box","Rhythm and voice",{wide:true,refs:"voice_screens.dart, voice_logic.dart",
 desc:"She taps a picture or draws. Then she chooses: keep it in the box, show my grown-up, or let it float away. The app never reads or counts a worry.",
 notes:[nn(1,"home: 'Put a worry in the box' with Pick a picture, Draw it, Look in the box.","three large tool tiles with a clear picture each.","the product never reads, interprets or scores a worry (P7)."),
  nn(2,"'Then you choose': Keep it in the box, Show my grown-up, Let it float away.","three equal buttons, each with its own picture; none is the default.","she decides who sees it."),
  nn(3,"Show my grown-up writes a note: 'Your grown-up can see this one.' Let it float away deletes for real: 'It floated away.' A new worry that floats away writes nothing at all.","each outcome says in plain words what happened.","float means gone."),
  nn(4,"the box holds 24; when full: 'The box is full. Let one float away first.' and it never drops one itself.","the denial is kind and offers the next step.","no silent loss."),
  nn(5,"a drawing is bounded to 40 strokes of 120 points.","the pad is a plain paper tray; 'I have drawn it' ends.","")],
 r:function(c){
  var main='<h2 class="r3-h" style="font-size:22px;text-align:center">Then you choose</h2><div class="r3-pt" style="margin:0 auto;width:130px">'+'<span class="gi">'+glyph("worry-dark",30)+'</span><b>The dark</b></div><div class="r3-choose"'+K.n(2)+'><button type="button" class="btn pri lg">'+I("lock",22,2)+'Keep it in the box</button><button type="button" class="btn tonal lg">'+I("user",22,2)+'Show my grown-up</button><button type="button" class="btn ghost lg">'+I("cloud",22,2)+'Let it float away</button></div>';
  var st=K.card(eb("Home")+'<div class="r3-stack"'+K.n(1)+'><div class="r3-tool"><span class="gi">'+I("grid",26,1.9)+'</span>Pick a picture</div><div class="r3-tool"><span class="gi">'+I("pencil",26,1.9)+'</span>Draw it</div><div class="r3-tool"><span class="gi">'+I("inbox",26,1.9)+'</span>Look in the box</div></div>',"flat")+
   K.card(eb("Draw it")+'<p class="r3-h" style="font-size:18px;text-align:center">Draw it however you like.</p><div class="r3-pad" '+K.n(5)+' role="img" aria-label="Drawing area"></div><div style="height:8px"></div>'+K.btn("I have drawn it",{full:true,ic:"check"}),"")+
   K.card(eb("Outcomes")+quiet("It is in the box.","inbox")+'<div style="height:6px"></div>'+quiet("Your grown-up can see this one.","user")+'<div style="height:6px"></div>'+quiet("It floated away.","cloud"),"flat",3)+
   K.card(eb("Full")+call("The box is full. Let one float away first.","warn","info",4)+'<div style="height:6px"></div>'+call("That did not go in. Try again.","warn","info"),"flat");
  return clay(c,main,st,"My worry box",{stLabel:"Home, drawing, outcomes, full"});}});

S("WorryShelf","child","Look in the box","Rhythm and voice",{wide:true,refs:"voice_screens.dart, voice_logic.dart",
 desc:"What she put in the box, as she made it. She can keep one just hers, show it, take a show back, or let it float away.",
 notes:[nn(1,"'In the box': her worries as thumbnails; a small eye shows the ones she chose to show; 'The box is empty.' when none.","a quiet shelf of picture cards; nothing counts them.","there is no number of worries on screen."),
  nn(2,"taking a show back tells the truth, gently: 'A grown-up already saw this one. It is just yours now.' if the window had opened on it, otherwise 'It is just yours now.'","two kind lines with the grown-up glyph; no alarm, no blame.","§8.24.3: the truth, not a false comfort; the private 'seen' bit never reaches a guardian."),
  nn(3,"per worry: Keep it just mine, Show my grown-up, Let it float away.","three buttons, the one that fits the worry's state shown.","only what she chose to show is ever visible to a grown-up."),
  nn(4,"empty box: 'The box is empty.'","an empty shelf illustration with no instruction to fill it.","")],
 r:function(c){
  function th(id,sel,shown){return '<div class="r3-wthumb'+(sel?" sel":"")+'">'+(shown?'<span class="eye">'+I("eye",16,2)+'</span>':"")+glyph(id,30)+'<span>'+E(PL[id])+'</span></div>';}
  var main='<h2 class="r3-h" style="font-size:22px">In the box</h2><div class="r3-pg"'+K.n(1)+'>'+th("worry-dark",true,true)+th("worry-noise")+th("worry-storm")+th("worry-apart",false,true)+'</div>'+
   K.card('<b class="r3-h" style="font-size:18px">The dark</b><p class="r3-sub">Your grown-up can see this one.</p><div class="r3-choose" '+K.n(3)+' style="margin-top:8px"><button type="button" class="btn tonal">'+I("lock",20,2)+'Keep it just mine</button><button type="button" class="btn ghost">'+I("cloud",20,2)+'Let it float away</button></div>');
  var st=K.card(eb("Taking a show back")+K.avatar("G",{size:40})+'<p class="r3-h" style="font-size:18px;margin-top:8px"'+K.n(2)+'>A grown-up already saw this one. It is just yours now.</p><p class="r3-fine" style="margin-top:6px">If no grown-up had looked: “It is just yours now.”</p>',"tint")+K.card(eb("Empty")+K.emptyState({spot:"envelope",title:"The box is empty",sub:""}),"",4);
  return clay(c,main,st,"Look in the box",{stLabel:"Taking back, and empty"});}});

S("Helpers","child","My helpers","Rhythm and voice",{refs:"voice_screens.dart, voice_logic.dart",
 desc:"The grown-ups she can go to, written by a guardian with a picture each. A name and a line. No call button, no message, no map.",
 notes:[nn(1,"'The grown-ups you can go to': a name, a person picture and an optional short line (e.g. 'Knock on the door at the end of the hall').","each helper is a large card; the line is large and can be heard.","nothing here goes online: no call, no message, no map, no number (P3)."),
  nn(2,"a helper shows only after a guardian ticks that they have said yes.","nobody appears until they have agreed.","consent before presence."),
  nn(3,"'Your grown-up will add the people you can go to.' when none.","a friendly empty note.","")],
 r:function(){return CT("My helpers")+P(
  '<h2 class="r3-h" style="font-size:22px">The grown-ups you can go to</h2>'+
  '<div class="r3-helper"'+K.n(1)+'><span class="gi">'+glyph("teacher",34)+'</span><span style="flex:1"><b>Ms. Okafor</b><small>She is in the room by the front door.</small></span>'+K.iconBtn("volume",{kind:"tonal",label:"Hear this"})+'</div>'+
  '<div class="r3-helper"'+K.n(2)+'><span class="gi">'+glyph("grandparent",34)+'</span><span style="flex:1"><b>Grandma Rosa</b><small>Knock on the door at the end of the hall.</small></span>'+K.iconBtn("volume",{kind:"tonal",label:"Hear this"})+'</div>'+
  K.card(eb("Nobody yet")+quiet("Your grown-up will add the people you can go to.","users"),"flat",3),{cls:"r3c"});}});

S("Symbols","child","Say it with pictures","Rhythm and voice",{wide:true,refs:"voice_screens.dart, voice_logic.dart",
 desc:"A small picture board: sixteen core words always, plus up to eight a guardian adds. Tap to build a short sentence, in the order tapped, word for word.",
 notes:[nn(1,"tapping builds a strip of up to six; the sentence is exactly the words tapped, never rewritten.","the strip is large, and Say it speaks it; 'Take one back' and 'Start again' are quiet.","what she says is never stored."),
  nn(2,"'That is a full sentence. Say it, or take one back.' at six.","the tiles dim at six, with the sentence kept.","no hidden limit."),
  nn(3,"core words: I, want, more, stop, help, hurt, tired, play, yes, no, eat, drink, toilet, hug, look, all done; a guardian may add bath, book, music, outside, sleep, blanket, owl, home.","core tiles are neutral; added ones are warm-tinted so a guardian’s additions are visible.","pictures lead; every word can be heard.")],
 r:function(c){
  var core=["sym-i","sym-want","sym-more","sym-stop","sym-help","sym-hurt","sym-tired","sym-play","sym-yes","sym-no","sym-eat","sym-drink","sym-toilet","sym-hug","sym-look","sym-all-done"],ex=["sym-bath","sym-sleep"];
  function tile(id,x){var g=id==="sym-bath"?"bathroom":id==="sym-sleep"?"moon":id;return '<div class="'+(x?"x":"")+'">'+glyph(g,24)+'<span>'+E(PL[id]||id.replace("sym-",""))+'</span></div>';}
  var main='<div class="r3-sent"'+K.n(1)+'><span><i>'+glyph("sym-i",24)+'</i>I</span><span><i>'+glyph("sym-want",24)+'</i>want</span><span><i>'+glyph("sym-drink",24)+'</i>drink</span></div><div class="r3-two">'+K.btn("Say it",{ic:"volume",size:"lg"})+K.btn("Take one back",{kind:"ghost"})+'</div><div class="r3-sym"'+K.n(3)+'>'+core.map(function(i){return tile(i);}).join("")+ex.map(function(i){return tile(i,true);}).join("")+'</div>';
  var st=K.card(eb("Six words")+'<div class="r3-sent" style="opacity:.95"><span><i>'+glyph("sym-i",24)+'</i>I</span><span><i>'+glyph("sym-want",24)+'</i>want</span><span><i>'+glyph("sym-more",24)+'</i>more</span><span><i>'+glyph("sym-eat",24)+'</i>eat</span><span><i>'+glyph("sym-play",24)+'</i>play</span><span><i>'+glyph("sym-all-done",24)+'</i>all done</span></div>'+quiet("That is a full sentence. Say it, or take one back.","volume")+'<div style="height:8px"></div>'+K.btn("Start again",{kind:"ghost",full:true,n:2}),"",2);
  return clay(c,main,st,"Say it with pictures",{stLabel:"A full sentence"});}});

S("VoiceHub","guardian","Her voice","Rhythm and voice",{wide:true,refs:"rhythm_voice_guardian_screens.dart, rhythm_voice_gate.dart",
 desc:"The guardian hub for Ivy’s helpers, symbols and the worries she chose to show. Voice starts off and stays off until a guardian turns it on.",
 notes:[nn(1,"'Show on Ivy’s device' is off until you turn it on: 'Nothing from Voice shows on her device before then.'","the off state is the main state: a calm illustrated card, with the switch above it.","§8.24.1: Voice starts off and fails closed."),
  nn(2,"three rows: Ivy’s helpers, Her symbols, Worries she chose to show you.","each states what it holds.","the weather and the worry box are hers; you can’t open them."),
  nn(3,"'The weather picture and the worry box are hers. You cannot open them; only the worries she chooses to show you appear here.'","a lock note in plain words at the bottom of the hub.","P7."),
  nn(4,"helpers: choose these with her; each person should say yes first; she only sees people who have said yes; at most eight.","each helper row has a They have said yes check and a clear Not visible to her yet pill when unchecked.","consent before presence.")],
 r:function(c){
  var main=seal("<b>Kept on this device only.</b> It is not shared with Ivy’s other home yet.","device")+
   '<p class="r3-sub" style="margin:0">Ivy is 5, so Voice can show on her device from now, and only when the switch below is on.</p>'+
   K.card(row({ic:"mic",title:"Show on Ivy’s device",sub:"Off until you turn it on. Nothing from Voice shows on her device before then.",trail:K.toggle(false),n:1}),"")+
   K.card(row({ic:"users",title:"Ivy’s helpers",sub:"The grown-ups she can go to",go:true,n:2})+row({ic:"mic",title:"Her symbols",sub:"Add a few words to her picture board",go:true})+row({ic:"inbox",title:"Worries she chose to show you",sub:"Only what she picked “show my grown-up” for",go:true}),"")+
   call("The weather picture and the worry box are hers. You cannot open them; only the worries she chooses to show you appear here.","info","lock",3);
  var st=K.card(eb("Helpers")+'<p class="r3-sub" style="margin:0 0 8px">Choose these with her. Each person should say yes first; tick the box when they have. She only sees people who have said yes.</p>'+'<div class="r3-helper" style="box-shadow:none"><span class="gi">'+glyph("teacher",28)+'</span><span style="flex:1"><b style="font-size:16px">Ms. Okafor</b><small>She is in the room by the front door.</small></span></div><div class="r3-chk">'+K.check(true)+'<span>They have said yes</span></div>'+
   '<div class="r3-helper" style="box-shadow:none"><span class="gi">'+glyph("friend",28)+'</span><span style="flex:1"><b style="font-size:16px">Aunt Lena</b><small>A family friend</small></span></div><div class="r3-chk">'+K.check(false)+'<span>They have said yes</span></div>'+pill("warn","Not visible to her yet","eyeoff")+'<div style="height:8px"></div>'+K.btn("Add someone",{kind:"tonal",full:true,ic:"plus"}),"",4);
  return lay(c,main,st,"Her voice",{eyebrow:"Ivy’s device",stLabel:"Helpers and consent"});}});

S("SharedWorries","guardian","Worries she chose to show you","Rhythm and voice",{refs:"rhythm_voice_guardian_screens.dart",
 desc:"Only what Ivy picked “show my grown-up” for, exactly as she made it. No note, no tag, no count, no delete.",
 notes:[nn(1,"'Only worries Ivy chose to show you appear here. They are exactly as she made them. Nothing here is read, tagged or counted, and the box stays hers.'","opening line in a heart-tinted note, then only her pictures.","P7: nothing is read or interpreted."),
  nn(2,"each shown worry is a thumbnail with its picture label (for a picture) or her drawing.","big thumbnails, no timestamps, no ordering by time.","no history for the guardian to study."),
  nn(3,"if she took one back it vanishes, and nothing says it was there.","no 'removed' trace for the guardian.","she decides, always."),
  nn(4,"empty: 'Nothing here right now. That is her choice.'","a respectful empty state that treats empty as healthy.","")],
 r:function(){return T("Worries she chose to show you",{eyebrow:"Her voice"})+P(
  K.card('<div style="display:flex;gap:10px;align-items:flex-start">'+pl("heart","")+'<p class="r3-sub" style="margin:0"'+K.n(1)+'>Only worries Ivy chose to show you appear here. They are exactly as she made them. Nothing here is read, tagged or counted, and the box stays hers.</p></div>',"tint")+
  '<div class="r3-two" '+K.n(2)+'><div class="r3-wthumb" style="min-height:130px">'+glyph("worry-dark",36)+'<span>The dark</span></div><div class="r3-wthumb" style="min-height:130px"><svg viewBox="0 0 100 60" width="90" height="54" aria-label="A drawing"><path d="M8 40q18-34 36 0t34-4" fill="none" stroke="var(--pri)" stroke-width="5" stroke-linecap="round"/></svg><span>A drawing</span></div></div>'+
  K.card(eb("If she takes one back")+quiet("It is gone from here, and nothing says it was there.","eyeoff"),"flat",3)+K.card(eb("Nothing shown")+K.emptyState({spot:"leaf",title:"Nothing here right now",sub:"That is her choice."}),"",4));}});

/* ====================================================== GROWING AND CARE == */
css([
".ob .r3-door{position:relative;height:210px;border-radius:22px;background:linear-gradient(180deg,var(--surface2),var(--surface3));border:1px solid var(--line);overflow:hidden}",
".ob .r3-door .post{position:absolute;left:26px;top:10px;bottom:10px;width:12px;border-radius:5px;background:linear-gradient(90deg,var(--priC2),var(--priC))}",
".ob .r3-door .mk{position:absolute;left:26px;right:14px;display:flex;gap:8px;align-items:center;font:700 12px var(--font-body);color:var(--ink2)}.ob .r3-door .mk i{width:46px;height:4px;border-radius:2px;background:var(--pri);margin-left:-12px}",
".ob .r3-door .empty{position:absolute;inset:0;display:grid;place-items:center;padding:0 24px 0 56px;text-align:center;font-size:13.5px;color:var(--ink3)}",
".ob .r3-seal2{display:grid;grid-template-columns:auto 1fr;gap:12px;align-items:center}",
".ob .r3-env{width:64px;height:64px;border-radius:22px;background:linear-gradient(155deg,var(--accentC),color-mix(in srgb,var(--accent) 35%,var(--accentC)));display:grid;place-items:center;color:var(--ink);position:relative;box-shadow:inset 0 1px 0 var(--hiC)}",
".ob .r3-env .lk{position:absolute;right:-5px;bottom:-5px;width:28px;height:28px;border-radius:50%;background:var(--ink);color:var(--bg);display:grid;place-items:center}",
".ob .r3-mem{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.ob.f-cover .r3-mem{grid-template-columns:1fr}.ob .r3-mem>div{aspect-ratio:1;border-radius:22px;overflow:hidden;position:relative;display:grid;place-items:center;background:var(--priC);color:var(--onPriC);box-shadow:var(--shadow1)}",
".ob .r3-mem>div span{position:absolute;left:8px;right:8px;bottom:8px;padding:5px 9px;border-radius:12px;background:color-mix(in srgb,var(--surface) 88%,transparent);color:var(--ink);font:700 12.5px/1.2 var(--font-body)}",
".ob .r3-gift{border-radius:22px;padding:14px;background:var(--accentC);color:var(--ink);display:grid;gap:4px}.ob .r3-gift small{font:700 11.5px/1 var(--font-mono);letter-spacing:.06em;text-transform:uppercase;opacity:.75}.ob .r3-gift b{font:800 17px/1.3 var(--font-display)}",
".ob .r3-sec{display:grid;gap:6px}.ob .r3-sec b{font:800 15px/1.2 var(--font-display)}.ob .r3-sec p{margin:0;font-size:13.5px;line-height:1.5;color:var(--ink2)}.ob .r3-sec .e{color:var(--ink3);font-style:italic}",
".ob .r3-door2{display:flex;gap:14px;align-items:center;min-height:84px;padding:14px 16px;border-radius:26px;background:linear-gradient(155deg,var(--hero1),var(--hero2));color:var(--onPri);box-shadow:var(--shadow2)}.ob .r3-door2 .gi{width:52px;height:52px;border-radius:18px;background:rgba(255,255,255,.2);display:grid;place-items:center;flex:none}.ob .r3-door2 b{font:800 18px/1.15 var(--font-display);display:block}.ob .r3-door2 small{opacity:.9;font-size:13px}",
".ob .r3-ec{display:grid;gap:6px}.ob .r3-ec .h{font:700 11px/1 var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:var(--ink3)}.ob .r3-ec .v{font-size:14.5px;line-height:1.45}",
".ob .r3-chk2{display:flex;gap:12px;align-items:flex-start;min-height:48px;padding:4px 0}.ob .r3-chk2.dn span:last-child{text-decoration:line-through;color:var(--ink3)}",
".ob .r3-ver{display:flex;gap:10px;align-items:center;padding:12px 14px;border-radius:18px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}",
".ob .r3-pg6{display:flex;gap:10px;justify-content:center}.ob .r3-pg6 i{width:14px;height:14px;border-radius:50%;background:var(--surface3);box-shadow:inset 0 0 0 1px var(--line)}.ob .r3-pg6 i.f{background:var(--pri);box-shadow:none}",
".ob .r3-pgtx{font:700 24px/1.45 var(--font-body);text-align:center;color:var(--ink);padding:18px 8px;text-wrap:balance}"
].join("\n"));
function door(marks,h){h=h||210;return '<div class="r3-door" style="height:'+h+'px" role="img" aria-label="Her doorframe: a pencil line for each mark, with a month, no numbers"><span class="post"></span>'+(marks.length?marks.map(function(m){return '<span class="mk" style="bottom:'+(14+(h-48)*m[1])+'px"><i></i>'+E(m[0])+'</span>';}).join(""):'<span class="empty">The doorframe is waiting for its first mark.</span>')+'</div>';}
function togl(on,label){return K.toggle(on,{label:label});}

S("GrowingCareHub","guardian","Growing and Care hubs","Growing and care",{wide:true,refs:"care_screens.dart, growing_care_logic.dart",
 desc:"Two small hubs gather the Growing and Care suites. Each suite has its own switch, and a suite that is switched off is not offered. All of it stays on this device.",
 notes:[nn(1,"'Kept on this device only. Nothing here is sent anywhere.' plus, for Growing, that Ivy sees only what you choose to show.","one banner leads each hub with the right second sentence.","local-first; sharing between homes is parked."),
  nn(2,"Growing offers Time capsule, First times, Growing marks and Leave something for her; Care offers Care binder, Hospital mode, Picture stories, Appointment prep.","each tile is a row with a one-line promise and a small device mark.","the app adds no medical content."),
  nn(3,"'Switch on or off' has a switch per suite; Memory box says 'Hers to fill. You can only leave a marked note or photo in its own section.'","switches sit in their own card below the doors, so turning one off never feels like a delete.","switching off hides and deletes nothing."),
  nn(4,"when every suite is off: 'Everything here is switched off.'","an empty state that points to the switches.",""),
  nn(5,"Care says Ivy never sees it, except a picture story you choose to show.","said on the Care banner.","guardian-only.")],
 r:function(c){var lt=localTag(c);
  function tile(ic,t,s,tone){return row({ic:ic,title:t,sub:s,go:true,trail:lt,tone:tone});}
  var main=seal("<b>Kept on this device only.</b> Nothing here is sent anywhere. Ivy sees only what you choose to show.","device",1)+
   K.card(tile("clock","Time capsule","Seal a note for a day to come")+tile("star","First times","A record of what happened for the first time")+tile("footprint","Growing marks","The doorframe, kept on a screen")+tile("heart","Leave something for her","A note or photo marked as from you, in its own place in her memory box"),"",2)+
   K.sectionLabel("Switch on or off")+K.card(row({title:"Time capsule",trail:togl(true,"Time capsule")})+row({title:"First times",trail:togl(true,"First times")})+row({title:"Memory box",sub:"Hers to fill. You can only leave a marked note or photo in its own section.",trail:togl(true,"Memory box")})+row({title:"Growing marks",trail:togl(true,"Growing marks")}),"",3);
  var st=eb("Care")+seal("<b>Kept on this device only.</b> Only grown-ups see these. Ivy never does, except a picture story you choose to show.","shield",5)+
   K.card(tile("file","Care binder","Routines, allergies, contacts, school: in your words")+tile("shield","Hospital mode","One calm page for a stressed adult")+tile("book","Picture stories","Short stories you write for her, shown only if you choose")+tile("list","Appointment prep","Your checklist and questions before a visit"))+
   K.card(eb("Everything switched off")+K.emptyState({spot:"leaf",title:"Everything here is switched off",sub:"Use the switches below to bring a suite back. Nothing was deleted."}),"flat",4);
  return lay(c,main,st,"Growing",{eyebrow:"Her",stLabel:"The Care hub, and all off"});}});

S("TimeCapsule","guardian","Time capsule","Growing and care",{wide:true,refs:"growing_screens.dart, growing_care_logic.dart",
 desc:"A note and a small photo sealed for a day to come. While sealed, even the guardian sees only the title and dates. Ivy sees an opened letter only.",
 notes:[nn(1,"a sealed card shows 'Sealed. Opens on <date>.' and 'The words stay hidden, even from you, until it opens.'","an envelope with a lock and the date large; the hidden words are an honest empty block.","her side shows no title, no date and no countdown."),
  nn(2,"it opens on or after its date by this device’s clock; 'Changing the clock would open it early.' A guardian can Open it early (asked first, stays open) or Remove.","the clock fact is in the form banner, the early-open question is a calm dialog.","opening early is deliberate and permanent."),
  nn(3,"Seal something: a name (60), what you want to say (2000), Opens on (a future date, up to 18 years), an optional small photo.","a simple three-field form with the limits written under each.","no reminder or notification."),
  nn(4,"an opened capsule shows the note and photo.","the card changes to an open envelope with the words in a quote.",""),
  nn(5,"empty: 'Nothing sealed yet. Write a note for a day to come, and it stays closed until then.'","a designed empty state with the seal action.","")],
 r:function(c){
  function cap(t,date,open){return K.card('<div class="r3-seal2"><span class="r3-env">'+I(open?"letter":"mail",28,1.8)+'<i class="lk">'+I(open?"check":"lock",14,2.4)+'</i></span><div><b class="r3-h" style="font-size:17px">'+E(t)+'</b><p class="r3-sub" style="margin:2px 0 0">'+(open?"Opened (it opens on "+date+")":"Sealed. Opens on "+date+".")+'</p></div></div>'+(open?'<p class="r3-call" style="margin-top:10px;border-left-color:var(--accent)">You were so small when we wrote this. Today you lost your first tooth.</p>':'<p class="r3-fine" style="margin-top:8px">'+I("lock",12,2)+' The words stay hidden, even from you, until it opens.</p><div style="display:flex;gap:8px;margin-top:10px"><button type="button" class="btn ghost sm">Open it early</button><button type="button" class="btn danger sm">Remove</button></div>'),"",open?4:1);}
  var main=cap("For when she is eight","9 Dec 2028",false)+cap("Dad’s letter, for her first day at school","9 Sep 2026",true)+K.btn("Seal something for later",{full:true,size:"lg",ic:"plus"});
  var st=K.card(eb("Seal something")+seal("A capsule opens by this device’s clock. Changing the clock would open it early, so keep that in mind. It is kept on this device only.","clock",2)+'<div class="r3-stack" '+K.n(3)+' style="margin-top:8px">'+K.formField({label:"A name for it",value:"For when she is eight"})+lab("What you want to say")+ta("Ivy, the day you read this…",{h:84})+K.formField({label:"Opens on",value:"2028-12-09",hint:"A date up to 18 years ahead"})+'<div class="r3-ph" style="height:70px">Add a small photo (optional)</div>'+K.btn("Seal it",{full:true})+'</div>',"")+
   '<div class="r3-dlg"><span class="r3-pl warn">'+I("hourglass",20,2)+'</span><h4>Open this early?</h4><p class="r3-sub">Once opened, it stays open. Only do this if you mean to.</p><div class="acts">'+K.btn("Keep it sealed",{kind:"tonal"})+K.btn("Open it",{kind:"ghost"})+'</div></div>'+
   K.card(eb("Nothing sealed")+K.emptyState({spot:"envelope",title:"Nothing sealed yet",sub:"Write a note for a day to come, and it stays closed until then.",action:"Seal something for later"}),"",5);
  return lay(c,main,st,"Time capsule",{eyebrow:"Growing",stLabel:"The form, the early-open question, empty"});}});

S("FirstTimes","guardian","First times","Growing and care",{wide:true,refs:"growing_screens.dart",
 desc:"A guardian-kept record of firsts: a title, a date, a few words, a small photo. Each has Show her this one, off by default.",
 notes:[nn(1,"'A record of what happened, never a to-do list.' No count, no streak, no list of firsts still to come.","the record is a soft timeline, newest first, with no totals.","P2: nothing to complete, nothing to beat."),
  nn(2,"each first has a title, a date, a few words (500), a small photo and a switch 'Show her this one'.","the photo leads, the switch is a quiet row.","she sees only what you choose to show."),
  nn(3,"the form: What happened, a date (not in the future), A few words (optional), Show her this one, a photo.","a sheet with limits under each field and the date error in words.",""),
  nn(4,"Ivy’s side: 'Something new — Times you did something new', month and year, picture first, no total; empty is 'Nothing here yet.'","drawn as a gentle row of memory cards.","no number of firsts anywhere.")],
 r:function(c){
  function f(t,d,note,show,photo){return K.card('<div style="display:flex;gap:10px;align-items:flex-start">'+(photo?'<div class="r3-ph" style="width:64px;height:64px;flex:none;border-radius:16px">photo</div>':pl("star","ac"))+'<div style="min-width:0;flex:1"><b class="r3-h" style="font-size:16px">'+E(t)+'</b><p class="r3-sub" style="margin:0">'+E(d)+'</p>'+(note?'<p class="r3-sub">'+E(note)+'</p>':"")+'</div></div>'+row({title:"Show her this one",trail:togl(show,"Show her this one"),n:2}));}
  var main=seal("<b>Kept on this device only.</b> A record of what happened, never a to-do list.","star",1)+f("Rode a two-wheeler","12 Oct 2026","Marcus held the seat for the first lap.",true,true)+f("Lost a tooth","3 Sep 2026","",false,false)+K.btn("A first happened",{full:true,size:"lg",ic:"plus"});
  var st=K.card(eb("Ivy’s side: Something new")+'<div class="r3-stack" '+K.n(4)+'><div class="r3-helper"><span class="gi">'+I("star",30,1.8)+'</span><span style="flex:1"><b>Rode a two-wheeler</b><small>October 2026</small></span></div></div>',"flat")+K.card(eb("Ivy’s side, nothing shown yet")+quiet("Nothing here yet.","leaf"),"flat")+K.card(eb("Empty for the guardian")+K.emptyState({spot:"leaf",title:"Nothing yet",sub:"When something happens for the first time, add it here."}),"",3)+K.formField({label:"Date",value:"2027-03-01",error:"That day hasn’t happened yet."});
  return lay(c,main,st,"First times",{eyebrow:"Growing",stLabel:"Her side, empty, and a date error"});}});

S("GrowingMarks","guardian","Growing marks","Growing and care",{wide:true,refs:"growing_screens.dart, growing_care_logic.dart",
 desc:"The doorframe, kept on a screen. Heights are the guardian’s private record. Ivy’s own doorframe shows only a pencil line and a month for each mark.",
 notes:[nn(1,"'These heights are your own record. Her app shows her only a picture of her marks, with no numbers and no one to compare with.'","the doorframe is the centre of the page, with the cm only in the list below.","no centimetres, percentile, average or other child on her side."),
  nn(2,"Height (cm) 30 to 220, a date, an optional photo by the doorframe, then Add today’s mark.","big numeric field and date side by side, errors in words.","a mark is a fact, not a target."),
  nn(3,"lines are placed only against her other marks, lowest 0.25 to highest 1.0.","drawn as pencil lines with a month; no scale.","no outside reference."),
  nn(4,"her side: 'My doorframe' — and 'The doorframe is waiting for its first mark.' when empty.","the same picture with months only.",""),
  nn(5,"refusals: a height outside 30 to 220, or a future date, in plain words.","each under its own field.","")],
 r:function(c){
  var marks=[["Dec 2025",.18],["Mar 2026",.4],["Jul 2026",.62],["Oct 2026",.86]];
  var main=seal("<b>Kept on this device only.</b> These heights are your own record. Her app shows her only a picture of her marks, with no numbers and no one to compare with.","footprint",1)+'<div'+K.n(3)+'>'+door(marks,210)+'</div>'+
   '<div class="r3-two ff2">'+K.formField({label:"Height (cm)",value:"112",n:2})+K.formField({label:"Date",value:"2026-11-08"})+'</div><div class="r3-ph" style="height:56px">Add a photo by the doorframe (optional)</div>'+K.btn("Add today’s mark",{full:true,size:"lg",ic:"plus"})+
   K.card(row({title:"112 cm",sub:"8 Nov 2026",trail:K.iconBtn("trash",{kind:"sm",label:"Remove"})})+row({title:"109 cm",sub:"12 Oct 2026",trail:K.iconBtn("trash",{kind:"sm",label:"Remove"})})+row({title:"103 cm",sub:"1 Jul 2026",trail:K.iconBtn("trash",{kind:"sm",label:"Remove"})}));
  var st=K.card(eb("Ivy’s side: My doorframe")+door(marks,170),"flat",4)+K.card(eb("Nothing marked yet")+door([],150),"flat",4)+K.formField({label:"Height (cm)",value:"12",error:"Heights run from 30 to 220 cm.",n:5})+K.formField({label:"Date",value:"2027-01-01",error:"That day hasn’t happened yet."});
  return lay(c,main,st,"Growing marks",{eyebrow:"Growing",stLabel:"Her doorframe, empty, and refusals"});}});

S("MemoryBox","child","My memory box","Growing and care",{wide:true,refs:"growing_screens.dart, growing_care_logic.dart",
 desc:"Hers: pictures she chose to keep, and small photos. A guardian can’t edit or remove what she keeps. Nothing resurfaces and nothing counts.",
 notes:[nn(1,"'Things you chose to keep. They stay on this device.' A 2-up grid; long-press to put one away (asked first: 'Put this away?').","big rounded keepsakes with a small optional caption; no counts.","P9: nothing resurfaces on its own."),
  nn(2,"two 64 dp buttons: A picture I made and A photo.","the two buttons are the only actions, pinned at the bottom.","audio does not exist yet, so only pictures and photos."),
  nn(3,"'From a grown-up' appears only when a grown-up left something; it opens its own read-only screen, apart from her own.","a separate warm button so it is never mixed in with hers.","a grown-up can’t edit or delete hers."),
  nn(4,"empty: 'It’s yours. Keep things here whenever you like.' read aloud; and 'Make a picture first, then you can keep it here.' when she has none to keep.","a welcoming empty state with the speaker.","")],
 r:function(c){
  var main='<div class="r3-mem"'+K.n(1)+'><div>'+critter(SW.sea[0],"sticker",96)+'<span>Fox, my best</span></div><div><div class="r3-ph" style="position:absolute;inset:0;border-radius:0">my photo</div></div><div>'+glyph("garden",70,1.4)+'<span>The garden</span></div><div>'+critter(SW.mint[0],"watercolour",90)+'</div></div>'+
   '<div class="r3-two">'+K.btn("A picture I made",{ic:"brush",n:2})+K.btn("A photo",{ic:"image"})+'</div>'+'<div style="display:flex;gap:8px"><button type="button" class="btn ghost" style="flex:1" '+K.n(3)+'>'+I("heart",22,2)+'From a grown-up</button>'+K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+'</div>';
  var st=K.card(eb("Empty")+K.emptyState({spot:"leaf",title:"It’s yours",sub:"Keep things here whenever you like."})+'<div style="display:flex;justify-content:center">'+K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+'</div>',"",4)+
   '<div class="r3-dlg"><span class="r3-pl warn">'+I("trash",20,2)+'</span><h4>Put this away?</h4><div class="acts">'+K.btn("Keep it",{kind:"tonal"})+K.btn("Put it away",{kind:"ghost"})+'</div></div>'+
   K.card(eb("From a grown-up")+'<div class="r3-gift"><small>From Jess</small><b>Proud of you.</b></div><div style="height:8px"></div><div class="r3-gift"><small>From Marcus</small><b>I saw your drawing on the fridge.</b></div><p class="r3-fine" style="margin-top:8px">Nothing here right now. (When there is nothing left.)</p>',"flat",3);
  return clay(c,main,st,"My memory box",{stLabel:"Empty, put away, from a grown-up"});}});

S("LeaveForHer","guardian","Leave something for her","Growing and care",{refs:"growing_screens.dart",
 desc:"A short note or a small photo, marked as from you, left in its own place in Ivy’s memory box. It is never mixed in with hers.",
 notes:[nn(1,"From (a name she knows), A short note (300), Add a photo, Leave it for her.","three plain fields; the sender name is what she will see, so it is first.","she can’t be shown it among her own pictures."),
  nn(2,"'What you have left': your own notes, each with 'Take this back?' (Leave it / Take it back). Up to 30.","a list of what you left; you can take back only what a grown-up left.","a guardian can’t touch her own items."),
  nn(3,"she can’t remove or hide a note a grown-up left; an owner decision is open.","drawn as built and flagged.","")],
 r:function(){return T("Leave something for her",{eyebrow:"Growing"})+P(
  seal("It goes into a separate “From a grown-up” section. She can’t be shown it among her own pictures, and nothing resurfaces on its own.","heart",1)+
  K.formField({label:"From (a name she knows)",value:"Jess"})+lab("A short note")+ta("Proud of you.",{h:76})+'<p class="r3-fine">300 letters at most.</p><div class="r3-ph" style="height:56px">Add a photo</div>'+K.btn("Leave it for her",{full:true,size:"lg",ic:"heart"})+
  K.sectionLabel("What you have left")+K.card(row({title:"Proud of you.",sub:"From Jess",trail:K.iconBtn("trash",{kind:"sm",label:"Take back"}),n:2}))+
  '<div class="r3-dlg"><span class="r3-pl warn">'+I("undo",20,2)+'</span><h4>Take this back?</h4><div class="acts">'+K.btn("Leave it",{kind:"tonal"})+K.btn("Take it back",{kind:"ghost"})+'</div></div>'+call("She can’t hide or remove a note a grown-up left. An owner decision is still open.","info","flag",3));}});

S("CareBinder","guardian","Care binder","Growing and care",{wide:true,refs:"care_screens.dart, growing_care_logic.dart",
 desc:"Sections a guardian writes in their own words, and contacts. The app adds no medical content. It is never on Ivy’s device.",
 notes:[nn(1,"'Written by a guardian. The app adds no medical content, and this is never on her device.'","the promise is a banner at the top.","guardian-only; no type her side holds can read it."),
  nn(2,"Add a section asks 'What kind of section?': Routines, Allergies (written by a guardian), School, Notes. A body starts empty: '(nothing written yet)'.","kinds are four picture tiles; the empty body is shown honestly.","neutral labels only; no suggested text."),
  nn(3,"Contacts: a name, 'Who they are (optional)', 'Phone (optional)'.","contacts in a compact list with a call-free phone line (it is text).","the app never dials."),
  nn(4,"Print view and Copy this text ('Copied to this phone’s clipboard').","a clean black-on-white sheet that copies or prints.","nothing leaves unless a guardian copies it."),
  nn(5,"empty: 'Nothing written yet. Add a section and write it in your own words.' Limits: 12 sections, 20 contacts.","empty and full are both in words.","")],
 r:function(c){
  function sec(t,b,k){return K.card('<div class="r3-sec"><div class="r3-hd"><b>'+E(t)+'</b>'+pill("quiet",k)+'</div>'+(b?'<p>'+E(b)+'</p>':'<p class="e">(nothing written yet)</p>')+'<div style="display:flex;gap:6px"><button type="button" class="btn ghost sm">Edit</button><button type="button" class="btn ghost sm">Remove</button></div></div>');}
  var main=seal("<b>Written by a guardian.</b> The app adds no medical content, and this is never on Ivy’s device.","lock",1)+sec("Bedtime","Bath, two books, lights out at 7:30. The owl night-light stays on.","Routines")+sec("Allergies","","Allergies (written by a guardian)")+sec("School","Ms. Okafor’s class. Pick-up is at 3:15.","School")+K.btn("Add a section",{kind:"tonal",full:true,ic:"plus",n:2})+
   K.sectionLabel("Contacts")+K.card(row({ic:"user",title:"Dr. Singh",sub:"Her doctor · 555 0101"})+row({ic:"user",title:"Grandma Rosa",sub:"Marcus’s mother · 555 0144"}),"",3)+K.btn("Add a contact",{kind:"ghost",full:true,ic:"plus"});
  var st=K.card(eb("What kind of section?")+'<div class="r3-sty"><span>Routines</span><span>Allergies (written by a guardian)</span><span>School</span><span>Notes</span></div>',"flat",2)+
   K.card(eb("Print view")+'<div style="background:#fff;color:#14201a;border-radius:12px;padding:14px;font:500 12.5px/1.5 var(--font-mono)"'+K.n(4)+'>Ivy’s care binder<br>Routines: Bedtime…<br>Contacts: Dr. Singh…</div><div style="height:8px"></div>'+K.btn("Copy this text",{kind:"tonal",full:true,ic:"copy"})+K.toast("Copied to this phone’s clipboard.",{ic:"check",inline:true}),"")+
   K.card(eb("Empty")+K.emptyState({spot:"shield",title:"Nothing written yet",sub:"Add a section and write it in your own words."}),"",5);
  return lay(c,main,st,"Care binder",{eyebrow:"Care",stLabel:"Kinds, print, empty"});}});

S("HospitalMode","guardian","Hospital mode","Growing and care",{wide:true,refs:"care_screens.dart, emergency_card_local.dart",
 desc:"One calm page for a stressed adult: a big door to the emergency card, the allergy and medical lines a guardian wrote, four notes, and who to call.",
 notes:[nn(1,"a big door to the existing emergency card, with a pencil to write it.","the door is the first and largest element, high contrast, one hand.","guardian-only."),
  nn(2,"shows the local card’s allergies, conditions, medicines, doctor and contacts when written; four guardian notes: Happening today, Staff should know, What helps her, To bring.","four labelled blocks in one reading column, large type.","every word typed by a guardian; no suggestions."),
  nn(3,"empty: 'Nothing written yet. Tap the pencil to write what you would want at hand. Allergies and contacts come from your care binder.'","a calm empty state, never an alarm.","the app adds no clinical content."),
  nn(4,"'Write notes' opens a four-field form with Keep these.","fields have the same four headings so the page and the form match.","")],
 r:function(c){
  var main='<a class="r3-door2" role="button" tabindex="0"'+K.n(1)+'><span class="gi">'+I("shield",28,1.9)+'</span><span style="flex:1"><b>Ivy’s emergency card</b><small>Allergies, medicines, her doctor, contacts</small></span>'+I("chevR",20,2)+'</a>'+
   K.card('<div class="r3-ec"><span class="h">Allergies (emergency card)</span><span class="v">Penicillin. Tree nuts.</span><span class="h" style="margin-top:6px">Medicines</span><span class="v">Inhaler, two puffs when needed.</span><span class="h" style="margin-top:6px">Her doctor</span><span class="v">Dr. Singh · Maple Street Practice · 555 0101</span></div>',"",2)+
   K.card('<div class="r3-ec"><span class="h">Happening today</span><span class="v">Tonsil check, 2:30 PM.</span><span class="h" style="margin-top:6px">Staff should know</span><span class="v">She is nervous about needles.</span><span class="h" style="margin-top:6px">What helps her</span><span class="v">Owl, and a song while we wait.</span><span class="h" style="margin-top:6px">To bring</span><span class="v">Owl. Blanket. Library book.</span></div>',"",3)+
   K.sectionLabel("Who to call")+K.card(row({ic:"user",title:"Marcus",sub:"555 0123"})+row({ic:"user",title:"Grandma Rosa",sub:"555 0144"}));
  var st=K.card(eb("Nothing written yet")+K.emptyState({spot:"shield",title:"Nothing written yet",sub:"Tap the pencil to write what you would want at hand. Allergies and contacts come from your care binder."}),"",3)+
   K.card(eb("Write notes")+K.formField({label:"Happening today",value:"Tonsil check, 2:30 PM."})+K.formField({label:"Staff should know",value:""})+K.formField({label:"What helps her",value:""})+K.formField({label:"To bring",value:""})+K.btn("Keep these",{full:true}),"flat",4);
  return lay(c,main,st,"Hospital mode",{eyebrow:"Care",stLabel:"Empty, and writing notes"});}});

S("PictureStories","guardian","Picture stories","Growing and care",{wide:true,refs:"care_screens.dart, child_explainer_screens.dart",
 desc:"Short stories a guardian writes for Ivy, shown only if chosen. She reads one page at a time with big Back and Next. The app writes none.",
 notes:[nn(1,"a story has a title, one to six pages of at most 240 characters, an optional picture, and Show her (off by default).","a calm editor: pages as stacked cards with a counter of letters left.","the app writes none and generates none."),
  nn(2,"'Read it as she would' previews the child’s reader.","the preview is the next card on the right.","what you see is what she sees."),
  nn(3,"Ivy’s reader: a page at a time, big Back and Next, dots (no ‘page 2 of 5’), a calm 'All done', read aloud when speech is wired.","a large type page on a quiet plate.","P2: no counters."),
  nn(4,"empty: 'No stories yet. Write one in your own words.' (guardian) and 'Nothing here yet.' (Ivy).","both are friendly and short.","")],
 r:function(c){
  var main=seal("<b>Kept on this device only.</b> You write every word. A story is shown to Ivy only when you choose.","book",1)+
   K.card(row({ic:"book",title:"Grandma Rosa is coming",sub:"3 pages",trail:togl(true,"Show her"),n:2})+row({ic:"book",title:"The new house",sub:"2 pages",trail:togl(false,"Show her")}),"")+K.btn("Write a story",{full:true,size:"lg",ic:"plus"})+
   K.card(eb("Write a story")+K.formField({label:"Title",value:"Grandma Rosa is coming"})+lab("Page 1")+ta("Grandma Rosa is coming on the train.",{h:60})+'<p class="r3-fine">Up to 6 pages, 240 letters each.</p>'+K.btn("Add a page",{kind:"tonal",full:true,ic:"plus"})+K.btn("Keep it",{full:true}),"flat");
  var st=K.card(eb("Ivy’s reader")+'<div class="r3-pgtx" '+K.n(3)+'>Grandma Rosa is coming on the train.</div><div class="r3-pg6"><i class="f"></i><i></i><i></i></div><div style="height:12px"></div><div class="r3-nav"><button type="button" class="btn ghost">'+I("arrowL",22,2.2)+'Back</button><button type="button" class="btn pri">Next'+I("arrowR",22,2.2)+'</button></div><div style="height:6px"></div>'+K.speak("Hear it"),"")+
   K.card(eb("Last page")+'<div class="r3-pgtx">Then she gives you the biggest hug.</div><div class="r3-pg6"><i></i><i></i><i class="f"></i></div><div style="height:12px"></div>'+K.btn("All done",{full:true,ic:"check",size:"lg"}),"flat")+
   K.card(eb("Empty")+K.emptyState({spot:"envelope",title:"No stories yet",sub:"Write one in your own words."}),"",4)+quiet("Nothing here yet.","leaf");
  return lay(c,main,st,"Picture stories",{eyebrow:"Care",stLabel:"Ivy reads one, and empty"});}});

S("AppointmentPrep","guardian","Appointment prep","Growing and care",{refs:"care_screens.dart, growing_care_logic.dart",
 desc:"A checklist and a question list a guardian writes before a visit. It sets no reminder and sends nothing; the date is only something written down.",
 notes:[nn(1,"'This sets no reminder and sends nothing.'","said first, with a bell-off glyph.","nothing is scheduled."),
  nn(2,"a list: 'What is the visit?', an optional date, 'To bring or do' (ticked as you go), 'My questions'.","two clear groups, ticks that strike lines through, no progress bar.","there are no suggested questions."),
  nn(3,"up to 20 lists, 30 lines each of 200 characters.","limits are shown when reached, kindly.","the app adds no medical content."),
  nn(4,"empty: 'Nothing here yet. Start a list for the next visit.'","an empty state with one action.","")],
 r:function(){return T("Appointment prep",{eyebrow:"Care"})+P(
  call("This sets no reminder and sends nothing.","info","bell",1)+
  K.card('<b class="r3-h" style="font-size:17px">Dr. Singh — tonsil check</b><p class="r3-sub">Fri 14 Nov (written down only)</p><span class="r3-lab" style="margin-top:8px">To bring or do</span><div class="r3-chk2 dn">'+K.check(true)+'<span>Insurance card</span></div><div class="r3-chk2">'+K.check(false)+'<span>Owl, for the waiting room</span></div><div class="r3-chk2">'+K.check(false)+'<span>Note the dates of the last two colds</span></div><span class="r3-lab" style="margin-top:8px">My questions</span><div class="r3-chk2"><span class="r3-pl quiet" style="width:28px;height:28px;border-radius:9px">'+I("chat",14,2)+'</span><span>How long before she can swim again?</span></div>',"",2)+
  K.btn("Start a list",{full:true,size:"lg",ic:"plus"})+'<p class="r3-fine"'+K.n(3)+'>Up to 20 lists of 30 lines, 200 letters each.</p>'+K.card(eb("Empty")+K.emptyState({spot:"leaf",title:"Nothing here yet",sub:"Start a list for the next visit.",action:"Start a list"}),"flat",4));}});

S("EmergencyCardEdit","guardian","Emergency card","Growing and care",{wide:true,refs:"emergency_card_editor_screen.dart, emergency_card_local.dart",
 desc:"The guardian-only local emergency card: allergies, conditions, medicines, her doctor and contacts, every word typed by a guardian. Saving carries the version it loaded.",
 notes:[nn(1,"'Written by a guardian, in your own words. The app adds nothing to it. Kept on this device only, sealed. Every change is kept in a history.'","said once at the top, with a sealed lock.","the app adds no clinical content, suggestions or examples."),
  nn(2,"fields: your name (shown in the history), Allergies and Conditions (one per line), Medicines (name and how much and when), Her doctor (name, practice, phone), Contacts (name, who they are, phone). Limits 20/20/20/10.","a steady single column with clear sections and add/remove rows.","every field starts empty."),
  nn(3,"if another guardian saved first: 'Someone changed this card while you were editing. Open it again to see their change.' and the card reloads rather than overwrites.","a clear conflict banner at the top, the other change visible beneath.","P8 spirit: no silent overwrite."),
  nn(4,"a non-guardian: 'Only a grown-up can change the emergency card.'","a plain lock card.","guardian-only, twice (screen and service)."),
  nn(5,"Round 2 drew 'Emergency card: two edits at once' as a side-by-side merge; the shipped screen reloads the other guardian’s change instead.","drawn as built; flagged.","")],
 r:function(c){
  var main=seal("<b>Written by a guardian, in your own words.</b> The app adds nothing to it. Kept on this device only, sealed. Every change is kept in a history.","lock",1)+
   K.formField({label:"Your name (shown in the history)",value:"Jess"})+
   K.card(lab("Allergies (written by a guardian)")+ta("Penicillin\nTree nuts",{h:64,ph:"One per line"})+lab("Conditions")+ta("",{h:48,ph:"One per line"}),"",2)+
   K.card(lab("Medicines")+'<div class="r3-two ff2">'+K.formField({label:"Name",value:"Inhaler"})+K.formField({label:"How much and when",value:"2 puffs when needed"})+'</div><div style="height:6px"></div>'+K.btn("Add a medicine",{kind:"tonal",full:true,ic:"plus"}),"")+
   K.card(lab("Her doctor")+K.formField({label:"Name",value:"Dr. Singh"})+K.formField({label:"Practice",value:"Maple Street Practice"})+K.formField({label:"Phone",value:"555 0101"}),"")+
   K.card(lab("Contacts")+K.formField({label:"Name",value:"Marcus"})+K.formField({label:"Who they are",value:"Her dad"})+K.formField({label:"Phone",value:"555 0123"})+K.btn("Add a contact",{kind:"tonal",full:true,ic:"plus"}),"")+K.btn("Save on this device",{full:true,size:"lg"});
  var st=K.notice({tone:"warn",title:"Someone changed this card",text:"Someone changed this card while you were editing. Open it again to see their change.",action:"Open it again"})+
   K.card(eb("Not a guardian")+K.emptyState({spot:"lock",title:"Only a grown-up can change the emergency card",sub:""}),"",4)+
   call("Round 2 drew a side-by-side merge for two edits at once. The shipped app reloads the other guardian’s change and asks you to edit again.","info","flag",5)+
   K.card(eb("Too many rows")+call("There are more rows than fit. Remove one to make room.","warn","warn"),"flat",3);
  return lay(c,main,st,"Ivy’s emergency card",{eyebrow:"Care",stLabel:"A conflict, a refusal, a limit",right:K.iconBtn("clock",{label:"History of changes"})});}});

S("EmergencyHistory","guardian","History of changes","Growing and care",{refs:"emergency_card_editor_screen.dart",
 desc:"Who changed the emergency card, when, and what it said before. Newest first, with no edit and no delete.",
 notes:[nn(1,"'Changed by Jess' and 'Version 3, 2026-11-07'; expand for the previous card in full.","each version is an expandable card with the previous values quoted.","P8 spirit: append-only."),
  nn(2,"first entry: 'Nothing was written before this.' An emptied card: 'The card was empty before this.'","both are said in words, not blank.","nothing is hidden."),
  nn(3,"empty: 'Nothing has been saved yet.' A non-guardian: 'Only a grown-up can see this.'","two quiet states.","guardian-only.")],
 r:function(){return T("History of changes",{eyebrow:"Ivy’s emergency card"})+P(
  '<div class="r3-ver"'+K.n(1)+'>'+pl("clock","")+'<div style="flex:1"><b>Changed by Jess</b><br><small style="color:var(--ink3)">Version 3, 2026-11-07</small></div>'+I("chevD",18,2)+'</div><p class="r3-call" style="margin:-4px 0 0 8px"><span>Before this change: Allergies: Penicillin. Medicines: inhaler, 2 puffs when needed. Her doctor: Dr. Singh.</span></p>'+
  '<div class="r3-ver">'+pl("clock","")+'<div style="flex:1"><b>Changed by Marcus</b><br><small style="color:var(--ink3)">Version 2, 2026-10-30</small></div>'+I("chevR",18,2)+'</div>'+
  '<div class="r3-ver">'+pl("clock","")+'<div style="flex:1"><b>Changed by Jess</b><br><small style="color:var(--ink3)">Version 1, 2026-10-02</small></div>'+I("chevR",18,2)+'</div><p class="r3-fine" style="padding-left:6px"'+K.n(2)+'>Version 1: Nothing was written before this.</p>'+
  K.card(eb("Nothing saved yet")+quiet("Nothing has been saved yet.","clock"),"flat",3)+K.card(eb("Not a guardian")+quiet("Only a grown-up can see this.","lock"),"flat"));}});

/* =========================================================== VILLAGE AND COMPASS == */
css([
".ob .r3-face{display:grid;justify-items:center;gap:6px;min-height:104px;padding:10px 6px;border-radius:24px;background:var(--surface);color:var(--ink);box-shadow:var(--shadow1);border:1px solid var(--line);min-width:0}",
".ob .r3-face .fc{width:60px;height:60px;border-radius:50%;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;font:800 24px var(--font-display);box-shadow:inset 0 1px 0 var(--hiC)}.ob .r3-face .fc.ac{background:var(--accentC);color:var(--ink)}",
".ob .r3-face b{font:800 15px/1.1 var(--font-display);max-width:100%;overflow:hidden;text-overflow:ellipsis}",
".ob .r3-place{border-radius:30px;padding:14px;display:grid;gap:12px;background:var(--priC);color:var(--onPriC);min-width:0}.ob .r3-place.d{background:var(--accentC);color:var(--ink)}",
".ob .r3-place h4{font:800 18px/1.1 var(--font-display);margin:0;display:flex;gap:8px;align-items:center}",
".ob .r3-ppl{display:grid;grid-template-columns:repeat(auto-fill,minmax(88px,1fr));gap:10px}.ob.f-cover .r3-ppl{grid-template-columns:repeat(2,minmax(0,1fr))}",
".ob .r3-reach{display:flex;flex-wrap:wrap;gap:4px;justify-content:center}.ob .r3-reach span{width:30px;height:30px;border-radius:50%;background:var(--surface2);color:var(--ink2);display:grid;place-items:center}",
".ob .r3-print{background:#fff;color:#111;border-radius:18px;padding:18px;display:grid;gap:10px;box-shadow:var(--shadow1);border:1px solid #ddd}",
".ob .r3-print h3{margin:0;font:800 26px/1.1 var(--font-display);color:#111}.ob .r3-print h5{margin:6px 0 0;font:700 12px var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:#444}.ob .r3-print p{margin:0;font:500 17px/1.45 var(--font-body);color:#111}.ob .r3-print .ft{font:500 12px/1.4 var(--font-body);color:#555;border-top:1px solid #ddd;padding-top:8px}",
".ob .r3-big{display:flex;gap:14px;align-items:center;min-height:92px;padding:14px 18px;border-radius:26px;background:var(--priC);color:var(--onPriC);font:800 24px/1.15 var(--font-display);box-shadow:var(--shadow1)}.ob .r3-big .gi{width:60px;height:60px;border-radius:20px;background:var(--surface);color:var(--pri);display:grid;place-items:center;flex:none}",
".ob .r3-held{display:flex;gap:10px;align-items:center;justify-content:space-between}",
".ob .r3-shelf{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.ob.f-cover .r3-shelf{grid-template-columns:repeat(2,minmax(0,1fr))}.ob .r3-shelf>div{aspect-ratio:1;border-radius:24px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;box-shadow:var(--shadow1)}.ob .r3-shelf>div.x{background:var(--accentC);color:var(--ink)}",
".ob .r3-cue{display:flex;gap:12px;align-items:center;padding:14px 16px;border-radius:22px;background:var(--infoC);color:var(--ink);font:700 16px/1.3 var(--font-body);box-shadow:var(--shadow2)}",
".ob .r3-sg{display:grid;gap:8px;padding:14px;border-radius:20px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}.ob .r3-sg b{font:800 16px/1.2 var(--font-display)}.ob .r3-sg p{margin:0;font-size:13.5px;line-height:1.45;color:var(--ink2)}.ob .r3-sg .why{font-size:12.5px;color:var(--ink3);display:flex;gap:6px;flex-wrap:wrap}",
".ob .r3-pr{display:grid;gap:8px;padding:14px;border-radius:20px;background:var(--surface);border:1.5px solid var(--outline)}.ob .r3-pr.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}.ob .r3-pr b{font:800 16px/1.2 var(--font-display)}.ob .r3-pr small{font-size:12.5px;opacity:.85}",
".ob .r3-ht{display:flex;gap:12px;align-items:center;min-height:68px;padding:10px 12px;border-radius:22px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);color:var(--ink);min-width:0}.ob .r3-ht .gi{width:46px;height:46px;border-radius:16px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center;flex:none}.ob .r3-ht b{font:800 16px/1.15 var(--font-display);display:block}.ob .r3-ht small{font-size:12.5px;color:var(--ink3);display:block}.ob .r3-ht .sp{margin-left:auto;color:var(--ink3);flex:none}",
".ob .r3-hs{font:800 13px/1 var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:var(--ink3);margin:6px 2px 0}",
".ob .r3-gc{display:grid;gap:6px;padding:12px;border-radius:22px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);min-width:0}.ob .r3-gc .gi{width:44px;height:44px;border-radius:15px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center}.ob .r3-gc b{font:800 15px/1.15 var(--font-display)}.ob .r3-gc small{font-size:12px;color:var(--ink3)}",
".ob .r3-gg{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.ob.f-cover .r3-gg{grid-template-columns:minmax(0,1fr)}",
".ob .r3-sleep{display:flex;gap:10px;align-items:center;justify-content:center;padding:12px;border-radius:18px;background:var(--surface2);font:700 15px var(--font-body);color:var(--ink2)}",
".ob .r3-rad{display:flex;gap:8px;align-items:center;justify-content:center;min-height:72px;border-radius:26px;background:radial-gradient(circle at 50% 50%,var(--priC),var(--priC2));color:var(--onPriC);font:800 18px var(--font-display)}"
].join("\n"));
function face(n,o){o=o||{};return '<div class="r3-face" role="button" tabindex="0" aria-label="'+E(n)+'"'+K.n(o.n)+'><span class="fc'+(o.ac?" ac":"")+'">'+(o.g?glyph(o.g,28):E(n.charAt(0)))+'</span><b>'+E(n)+'</b>'+(o.reach?'<span class="r3-reach">'+o.reach.map(function(x){return '<span>'+I(x,15,2)+'</span>';}).join("")+'</span>':"")+'</div>';}
function ht(ic,t,s,n){return '<div class="r3-ht" role="button" tabindex="0"'+K.n(n)+'><span class="gi">'+I(ic,24,1.9)+'</span><span style="min-width:0"><b>'+E(t)+'</b>'+(s?'<small>'+E(s)+'</small>':"")+'</span><span class="sp">'+I("volume",18,2)+'</span></div>';}

S("VillageHub","guardian","Village","Village and compass",{wide:true,refs:"village_guardian_screens.dart, village_logic.dart",
 desc:"The guardian hub for Ivy’s village: a large-print grandparent corner, her people in pictures, a story you release, a sibling shelf, a sitter pass and a school summary. No school, sitter or relative is ever contacted.",
 notes:[nn(1,"'No school, sitter or relative is ever contacted.' and 'Only her pictures, faces and released stories. The pages for grown-ups are not affected.'","one sealed line says both, so the limits are clear before the first tap.","P3: no address, no location; nothing leaves the device."),
  nn(2,"'Show on Ivy’s device' (the Village suite) from age five; the sitter pass, school summary and grandparent page are only ever for grown-ups.","the switch and a short age note lead; the grown-up pages carry a small lock, her pages a small phone.","what a child can reach is a short, explicit list."),
  nn(3,"six rows: Grandparent corner, Her people in pictures, A story for her, Sibling shelf, Sitter pass, School summary.","each row has one line of what it is and who it is for.","a held story is never returned to her side."),
  nn(4,"a guardian-only denial everywhere: 'Only a grown-up can change this.'","drawn as a quiet toast when a non-guardian tries.","guardian-only writes.")],
 r:function(c){
  function R(ic,t,s,tag){return row({ic:ic,title:t,sub:s,go:true,trail:c.form==="cover"?"":'<span class="r3-dvt" role="img" aria-label="'+(tag==="g"?"For grown-ups":"On her device")+'">'+I(tag==="g"?"lock":"phone",14,2)+'</span>'});}
  var main=seal("<b>No school, sitter or relative is ever contacted.</b> Only her pictures, faces and released stories reach Ivy. The pages for grown-ups are not affected.","users",1)+
   K.card(row({ic:"users",title:"Show on Ivy’s device",sub:"Ivy is 5, so Village can show from now.",trail:K.toggle(true),n:2}))+
   K.card(R("heart","Grandparent corner","A large-print page you write, to hand a grandparent the device","g")+R("users","Her people, in pictures","Choose a face for each person in your family builder","c")+R("book","A story for her","A picture story you write, shown to her only when you release it","c")+R("image","Sibling shelf","Brothers and sisters on this device leave each other pictures","c")+R("file","Sitter pass","One page for a trusted adult: routine, allergies, who to reach. You show the screen","g")+R("list","School summary","One page about what helps at school, kept here. The school is not contacted","g"),"",3);
  var st=K.toast("Only a grown-up can change this.",{ic:"lock",inline:true})+K.card(eb("Switched off")+K.emptyState({spot:"houses",title:"Village is off on Ivy’s device",sub:"Nothing you wrote is deleted. Ivy sees none of it until you switch it on."}),"flat",4);
  return lay(c,main,st,"Village",{eyebrow:"Family",stLabel:"Denied and off"});}});

S("GrandCorner","guardian","Grandparent corner","Village and compass",{wide:true,refs:"village_guardian_screens.dart",
 desc:"A large-print page you write to hand a grandparent the device: up to four huge buttons that open in very large type, and a phone line written down as text.",
 notes:[nn(1,"'Hello, <name>' and up to four huge buttons, each a picture, a title and up to 200 characters that open in very large type.","the page is black-on-light, one thought per button, built for a hand that isn’t used to a phone.","nothing calls or sends."),
  nn(2,"a phone line is a name, 7 to 15 digits and a note, shown as text: 'Prefer the phone?' The app never dials it.","the number is printed large; there is no call button.","P3 and P11: no remote action."),
  nn(3,"'Calling and sending pictures are not built; this page only shows what you write.'","the editor says so first, in a plain note.","honest absence."),
  nn(4,"limits and errors: 'Four cards is the most there is room for.' and 'Please write a phone number with digits only (7 to 15 digits).'","each beside its field.",""),
  nn(5,"empty: 'Nothing has been written here yet.'","an empty state with one action.","")],
 r:function(c){
  var main='<div class="r3-print" style="gap:12px"><h3 style="font-size:32px"'+K.n(1)+'>Hello, Nana</h3><div class="r3-stack">'+[["heart","What Ivy likes"],["clock","Bedtime"],["book","The reading book"]].map(function(x){return '<div class="r3-big"><span class="gi">'+I(x[0],34,1.8)+'</span>'+E(x[1])+'</div>';}).join("")+'</div><h5>Prefer the phone?</h5><p style="font-size:24px;font-weight:800"'+K.n(2)+'>Marcus: 555 0123</p><p class="ft">Shown as large text. The app never dials it.</p></div>';
  var st=K.card(eb("The editor")+call("Calling and sending pictures are not built; this page only shows what you write.","info","info",3)+K.formField({label:"What do you call them? (for “Hello, …”)",value:"Nana"})+'<div style="height:6px"></div>'+K.btn("Add a big button",{kind:"tonal",full:true,ic:"plus"})+'<div style="height:6px"></div>'+K.formField({label:"Number",value:"555 0123"})+K.formField({label:"Whose number",value:"Marcus"})+'<div style="height:8px"></div>'+K.btn("Show it large",{full:true})+K.btn("Clear this page",{kind:"danger",full:true}),"")+
   K.formField({label:"Number",value:"call me",error:"Please write a phone number with digits only (7 to 15 digits).",n:4})+call("Four cards is the most there is room for.","warn","info")+K.card(eb("Empty")+K.emptyState({spot:"houses",title:"Nothing has been written here yet",sub:"",action:"Add a big button"}),"flat",5);
  return lay(c,main,st,"Grandparent corner",{eyebrow:"Village",stLabel:"The editor and its limits"});}});

S("MyPeople","child","My people","Village and compass",{wide:true,refs:"family_structure_screens.dart, village_screens.dart",
 desc:"Ivy’s family as she knows it, by place, with the buttons that fit each person. The names she uses, nothing else: no role words. Faces of my people is the village version.",
 notes:[nn(1,"her people grouped by the homes a guardian built, each under a place name; the name is the one she uses.","each home is a soft coloured place; people are big faces with their own way to reach them.","no step, half or role word unless a guardian chose it."),
  nn(2,"each person offers only the ways a guardian allowed: Call, Message, Postcard, Voice line, Visit.","small round glyphs under the name, never a row of disabled buttons.","P11: nothing here remote-controls anything."),
  nn(3,"Faces of my people (Village): a face a guardian picked, else her first letter; tapping says the name.","drawn as the second state.","she doesn’t arrange it."),
  nn(4,"'Nobody is here yet.' when none are released.","a quiet empty state.","a guardian releases people when they choose.")],
 r:function(c){
  var main='<div class="r3-place"'+K.n(1)+'><h4>'+I("home",20,2)+'Jess’s house</h4><div class="r3-ppl">'+face("Jess",{reach:["video","chat"],n:2})+'</div></div><div class="r3-place d"><h4>'+I("home",20,2)+'Marcus’s house</h4><div class="r3-ppl">'+face("Marcus",{ac:1,reach:["video","chat","mail"]})+face("Dana",{ac:1,reach:["chat"]})+'</div></div><div class="r3-place" style="background:var(--surface2);color:var(--ink)"><h4>'+I("globe",20,2)+'Near and far</h4><div class="r3-ppl">'+face("Grandma Rosa",{reach:["video","mail"]})+'</div></div>';
  var st=K.card(eb("Faces of my people")+'<div class="r3-ppl" '+K.n(3)+'>'+face("Jess",{g:"grown-up"})+face("Marcus",{g:"grown-up",ac:1})+face("Rosa",{g:"grandparent"})+face("Dana")+'</div>',"flat")+K.card(eb("Empty")+quiet("Nobody is here yet.","users"),"flat",4);
  return clay(c,main,st,"My people",{stLabel:"Faces, and empty"});}});

S("VillageStories","guardian","A story for her","Village and compass",{wide:true,refs:"village_guardian_screens.dart, village_screens.dart, village_logic.dart",
 desc:"A picture story you write, held until you press Show her. A held story is never returned to Ivy’s side, not even by id. Editing a released story holds it again.",
 notes:[nn(1,"'You write every word. Nothing is suggested or filled in for you. A story stays held, and she cannot see it, until you release it.'","a Held pill and a Released pill carry the state so it is clear at a glance.","a held story is never returned to her side."),
  nn(2,"Show her asks: 'It will appear on her device, in her village, until you hold it again. Release it when you are ready for her to see it.' (Not yet / Show her). Hold it again takes it back.","the confirmation names what happens; Hold it again is always one tap.","the guardian chooses when."),
  nn(3,"up to three stories of up to six pages; each page a library picture and up to 160 characters.","limits in words; 'Save (held until you release it)'.","editing a released story holds it again."),
  nn(4,"her side: one page at a time with Back and Next, a calm 'All done', no page counts; 'This story is not here.' if it was held again.","a big page on a quiet plate with a picture.","P2: no 'page 2 of 6'.")],
 r:function(c){
  var main=seal("<b>You write every word.</b> Nothing is suggested or filled in for you. A story stays held, and Ivy cannot see it, until you release it.","book",1)+
   K.card('<div class="r3-held"><div><b class="r3-h" style="font-size:16px">Grandma Rosa is coming</b><p class="r3-sub" style="margin:0">3 pages</p></div>'+pill("ok","Released","check")+'</div><div style="display:flex;gap:6px;margin-top:8px"><button type="button" class="btn ghost sm">Edit</button><button type="button" class="btn tonal sm">Hold it again</button><button type="button" class="btn danger sm">Remove</button></div>',"",2)+
   K.card('<div class="r3-held"><div><b class="r3-h" style="font-size:16px">The new house</b><p class="r3-sub" style="margin:0">2 pages · edited just now</p></div>'+pill("info","Held","hourglass")+'</div><div style="display:flex;gap:6px;margin-top:8px"><button type="button" class="btn ghost sm">Edit</button><button type="button" class="btn pri sm">Show her</button></div>',"")+K.btn("Write a story",{full:true,size:"lg",ic:"plus"});
  var st=K.card('<div class="r3-dlg" style="box-shadow:none"><span class="r3-pl">'+I("eye",20,2)+'</span><h4>Show her “The new house”?</h4><p class="r3-sub">It will appear on her device, in her village, until you hold it again. Release it when you are ready for her to see it.</p><div class="acts">'+K.btn("Not yet",{kind:"tonal"})+K.btn("Show her",{kind:"pri"})+'</div></div>',"flat")+
   K.card(eb("Ivy’s side")+'<div class="r3-pgtx" '+K.n(4)+'>Grandma Rosa is coming on the train.</div><div class="r3-pg6"><i class="f"></i><i></i><i></i></div><div style="height:10px"></div><div class="r3-nav"><button type="button" class="btn ghost">'+I("arrowL",22,2.2)+'Back</button><button type="button" class="btn pri">Next'+I("arrowR",22,2.2)+'</button></div>',"")+quiet("This story is not here.","book")+K.card(eb("Write a story")+K.formField({label:"Title",value:"The new house"})+lab("What does this page say?")+ta("This is the front door.",{h:56})+K.btn("Save (held until you release it)",{full:true}),"flat",3);
  return lay(c,main,st,"A story for her",{eyebrow:"Village",stLabel:"Release, Ivy reads it, editor"});}});

S("SiblingShelf","child","Our shelf","Village and compass",{wide:true,refs:"village_screens.dart, village_guardian_screens.dart, visual_alert.dart",
 desc:"Brothers and sisters who use this device leave each other small pictures. No author, no time, no read mark and no count are stored or shown.",
 notes:[nn(1,"children who use the device leave each other a picture from a small kit; up to six per sibling, the oldest drops off, so it never says 'full'.","a plain shelf of picture squares with no numbers and no names of who left them.","P2: no author, time, read mark or count."),
  nn(2,"tapping a picture asks 'Take this picture down?' (Keep it / Take it down).","a calm confirmation sheet.","the only removal is a deliberate one."),
  nn(3,"leaving a picture raises a visual cue: a picture and words that stay until tapped, with a gentle buzz.","'A picture is on the shelf' is a quiet banner; it never flashes and is never sound only.","§8.22.2: nothing is sound only."),
  nn(4,"'Your grown-up has not set this up yet.' when no siblings are listed.","a friendly note.","")],
 r:function(c){
  var main='<div class="r3-shelf"'+K.n(1)+'><div>'+glyph("sunny",44)+'</div><div class="x">'+glyph("owl",44)+'</div><div>'+glyph("teddy",44)+'</div><div class="x">'+glyph("rainy",44)+'</div><div>'+glyph("night-light",44)+'</div><div class="x">'+I("heart",44,1.7)+'</div></div><p class="r3-sub" style="text-align:center">Tap a picture to take it down.</p>';
  var st='<div class="r3-cue" '+K.n(3)+'>'+I("image",26,1.9)+'<span>A picture is on the shelf</span><button type="button" class="btn tonal sm" style="margin-left:auto">OK</button></div>'+
   '<div class="r3-dlg"><span class="r3-pl warn">'+I("trash",20,2)+'</span><h4>Take this picture down?</h4><div class="acts">'+K.btn("Keep it",{kind:"tonal"})+K.btn("Take it down",{kind:"ghost"})+'</div></div>'+K.card(eb("Not set up")+quiet("Your grown-up has not set this up yet.","image"),"flat",4)+
   K.card(eb("Guardian: Sibling shelf")+'<p class="r3-sub" style="margin:0 0 8px">Names are exactly what you type. The shelf never shows how many pictures it holds, and keeps no record of who left one.</p>'+K.formField({label:"Their name, as you write it",value:"Leo"})+K.btn("Add a brother or sister",{kind:"tonal",full:true,ic:"plus"})+K.btn("Take every picture down",{kind:"ghost",full:true}),"flat",2);
  return clay(c,main,st,"Our shelf",{stLabel:"The cue, taking one down, the editor"});}});

S("SitterPass","guardian","Sitter pass","Village and compass",{wide:true,refs:"village_guardian_screens.dart, village_logic.dart",
 desc:"One page for a trusted adult, black on white in large type, shown on your screen. No link, no expiry, no “opened” notice, no medicine log. A school summary is the same kind of page.",
 notes:[nn(1,"a title, who it is for, when (in words), allergies in your own words, a routine, good-to-know lines and up to five contacts; up to eight lines of 80 characters.","a clean page that a photo of the screen or a printed copy reads the same.","P3: an address is refused; the app adds and checks nothing."),
  nn(2,"'Written by a grown-up on <day>. Kept on this device; shown only when it is held up.'","said in the footer of the page itself.","it leaves the device only when you hold the screen up."),
  nn(3,"'Copy the step names from her routine' reads your own Rhythm routine at write time.","a single secondary button in the editor.","nothing is shared."),
  nn(4,"School summary: a school name only, class or teacher, what helps, allergies, who collects her, up to four contacts; 'The school is not contacted and nothing arrives from it.'","same page style, same footer.","nothing about grades or behaviour is carried.")],
 r:function(c){
  var main='<div class="r3-print"'+K.n(1)+'><h3>Tonight</h3><p>For Dana · Fri 6 to 10 PM</p><h5>Allergies</h5><p>Penicillin. Tree nuts.</p><h5>Routine</h5><p>Bath, two books, lights out at 7:30. Owl night-light stays on.</p><h5>Good to know</h5><p>She may ask for water once. That is fine.</p><h5>Who to reach</h5><p>Marcus · 555 0123<br>Jess · 555 0188</p><p class="ft"'+K.n(2)+'>Written by a grown-up on 8 Nov 2026. Kept on this device; shown only when it is held up.</p></div>'+K.btn("Show the page",{full:true,size:"lg",ic:"eye"});
  var st=K.card(eb("The editor")+K.formField({label:"Page title",value:"Tonight"})+K.formField({label:"For (a name, optional)",value:"Dana"})+K.formField({label:"When (words, optional)",value:"Fri 6 to 10 PM"})+lab("Allergies, in your own words")+ta("Penicillin\nTree nuts",{h:56,ph:"One on each line. The app adds and checks nothing."})+'<div style="height:6px"></div><button type="button" class="btn ghost sm" '+K.n(3)+'>Copy the step names from her routine</button><div style="height:8px"></div>'+K.btn("Save",{full:true})+K.btn("Clear this page",{kind:"danger",full:true}),"")+
   K.card(eb("School summary")+'<p class="r3-sub" style="margin:0 0 8px" '+K.n(4)+'>The school is not contacted and nothing arrives from it. You show or hand over this page.</p>'+K.formField({label:"School name (no address)",value:"Maple Street School"})+K.formField({label:"Class or teacher (optional)",value:"Ms. Okafor"})+K.formField({label:"Who collects her",value:"Marcus, Jess, Dana"}),"flat")+call("Please leave out addresses and places.","warn","warn");
  return lay(c,main,st,"Sitter pass",{eyebrow:"Village",stLabel:"The editor and the school summary"});}});

function copt(t,on){return '<div class="r3-chk">'+K.check(on)+'<span style="font-size:14px;line-height:1.35">'+E(t)+'</span></div>';}
S("CompassHub","guardian","Family compass","Village and compass",{wide:true,refs:"compass_screens.dart, compass_logic.dart",
 desc:"Two gentle questions about Ivy’s days so the app can point at tools that may help. It only shapes suggestions; skip, change or forget any time.",
 notes:[nn(1,"'Two gentle questions… This only shapes suggestions. You can skip, change or forget your answers at any time.'","the promise opens the hub, in two sentences.","answers are ids only, sealed, forgettable."),
  nn(2,"five rows: Who is in her life (Step 1), What would help her (Step 2), Suggested for your family, Suites shelf, Accessibility profiles.","a quiet two-step lead-in, then three destinations.","guardian-only; no child-side Compass."),
  nn(3,"questions list ways families look and things that help, never conditions; any number or none, 'Not sure' and 'Skip for now' are complete answers.","tickable cards, the two escape hatches as equal buttons.","no condition, diagnosis, need-level or type is named."),
  nn(4,"the family builder’s own facts show as a quiet hint and are never ticked for her.","a small hint chip on the matching option.","")],
 r:function(c){
  var main=seal("<b>Kept on this device only.</b> Nothing here is sent, and nothing is switched on without you.","lock",1)+
   K.card('<p class="r3-sub" style="margin:0">Two gentle questions about Ivy’s days, so the app can point at tools that may help. This only shapes suggestions. You can skip, change or forget your answers at any time.</p>',"tint")+
   K.card(row({ic:"users",title:"Who is in her life",sub:"Step 1: ways families look",go:true,n:2})+row({ic:"heart",title:"What would help her",sub:"Step 2: things that help her day go well",go:true})+row({ic:"sparkle",title:"Suggested for your family",sub:"A few suites to look at, each with a reason",go:true})+row({ic:"layers",title:"Suites shelf",sub:"What is on and off for her",go:true})+row({ic:"eye",title:"Accessibility profiles",sub:"Away from home; alerts she can see",go:true}));
  var st=K.card(eb("Step 1: Who is in her life")+'<p class="r3-h" style="font-size:16px">Who is in Ivy’s family?</p><p class="r3-fine">Choose any, or none. This only shapes suggestions.</p>'+copt("She sleeps in more than one home",true)+'<div style="padding-left:34px;margin-top:-2px"'+K.n(4)+'>'+pill("quiet","Your family builder shows two homes","home")+'</div>'+copt("This device goes with her to another home",true)+copt("A parent who is away for a while (work, service, distance)",false)+copt("A step-parent or a parent’s partner is part of her days",false)+copt("A grandparent or another relative helps look after her",false)+copt("We have lost someone close",false)+'<div class="r3-two" style="margin-top:8px">'+K.btn("Save",{n:3})+K.btn("Not sure",{kind:"ghost"})+'</div>'+K.btn("Skip for now",{kind:"ghost",full:true}),"",3);
  return lay(c,main,st,"Family compass",{eyebrow:"Ivy",stLabel:"The first question"});}});

S("CompassSuggest","guardian","Suggested for your family","Village and compass",{wide:true,refs:"compass_screens.dart, compass_logic.dart",
 desc:"A short list from a plain table, each with a sentence of why and the answers that led to it. Nothing is switched on by looking; Not now remembers nothing.",
 notes:[nn(1,"'Nothing is switched on for her until you switch it. These come from a short, plain list, in the same order every time.'","said at the top, then the list.","no weights, no numbers, no learning, no scoring of the child or family."),
  nn(2,"each suggestion has the table’s own sentence of why and the answers that led to it; at most five.","a card with the reason and a row of small chips for the answers.","no label about the child, no diagnosis."),
  nn(3,"Not now remembers nothing: no 'dismissed' record exists.","Not now just closes the card.","the guardian’s tap is the yes."),
  nn(4,"empty: 'Nothing to suggest from what you have chosen. You can still look at everything on the suites shelf.'","a gentle empty state pointing at the shelf.","")],
 r:function(c){
  function sg(t,p,why){return '<div class="r3-sg"><b>'+E(t)+'</b><p>'+E(p)+'</p><div class="why">'+why.map(function(w){return '<span class="chip sm">'+E(w)+'</span>';}).join("")+'</div><div style="display:flex;gap:8px"><button type="button" class="btn tonal sm">Look at it</button><button type="button" class="btn ghost sm">Not now</button></div></div>';}
  var main=call("Nothing is switched on for her until you switch it. These come from a short, plain list, in the same order every time.","info","info",1)+
   '<div class="r3-stack"'+K.n(2)+'>'+sg("Routine and rhythm","A routine, a first-then card and a bag list in pictures show what comes next. Kept on this device.",["She sleeps in more than one home","Knowing what comes next"])+sg("Village","A shelf where brothers and sisters who share this device leave each other pictures.",["Brothers or sisters"])+sg("Device used in another home","Calmer defaults for a device used in another home: words can be heard and motion is reduced.",["This device goes with her to another home"])+'</div>';
  var st=K.card(eb("No suggestions")+K.emptyState({spot:"leaf",title:"Nothing to suggest",sub:"You can still look at everything on the suites shelf.",action:"Open the suites shelf"}),"",4)+'<div'+K.n(3)+'>'+quiet("Not now remembers nothing.","leaf")+'</div>';
  return lay(c,main,st,"Suggested for your family",{eyebrow:"Family compass",stLabel:"Empty"});}});

S("SuitesShelf","guardian","Suites shelf and profiles","Village and compass",{wide:true,refs:"compass_screens.dart, compass_logic.dart",
 desc:"Rhythm, Voice, Village, Growing and Care, each with its own switch and one plain line of what it adds. Then two accessibility profiles that only change how the device looks and behaves.",
 notes:[nn(1,"each switch is the suite’s own (the shelf keeps no copy); it shows on or off and never use.","five rows with a switch and a line, no counts or dates.","P4: it is not a store; P2: no usage."),
  nn(2,"'A suite shows her nothing until you have written something for it. Voice starts off and stays off until you switch it on.'","said as the page intro, with Voice’s off state obvious.","§8.24.1."),
  nn(3,"Growing and Care are groups of four switches; the row is on while any is on.","those two rows show a small 'on while any is on' pill.","switching off hides and deletes nothing."),
  nn(4,"two profiles, Device used in another home and Alerts she can see; each lists 'It changes:' and ends 'Turning it off leaves the settings as they are now.'","each profile is a card whose changed settings are listed; an alert preview shows the visible cue.","a profile only changes presentation and never labels her."),
  nn(5,"live captions are not built; a profile records the wish only.","said in the profile list.","honest absence.")],
 r:function(c){
  var main=call("A suite shows Ivy nothing until you have written something for it. Voice starts off and stays off until you switch it on.","info","info",2)+
   K.card(row({ic:"list",title:"Rhythm",sub:"Routine, first-then, bag, a new place",trail:K.toggle(true),n:1})+row({ic:"mic",title:"Voice",sub:"Her helpers and symbols; weather and worry box are hers",trail:K.toggle(false)})+row({ic:"users",title:"Village",sub:"Her people, a story you release, sitter pass, school summary",trail:K.toggle(true)})+row({ic:"footprint",title:"Growing",sub:"Time capsule, first times, memory box, growing marks",trail:K.toggle(true),n:3})+row({ic:"shield",title:"Care",sub:"Care binder, hospital mode, picture stories, appointment prep",trail:K.toggle(false)}));
  var st=eb("Accessibility profiles")+call("A profile only changes how this device looks and behaves. It changes nothing about what is shown or who sees what, and it never labels her.","info","shield",4)+
   '<div class="r3-pr"><b>Device used in another home</b><small>For a device she uses away from where she usually lives. Only presentation changes.</small>'+li([["check","Words can be heard (read aloud on)"],["check","Motion reduced"]],"ok")+K.toggle(false,{label:"Device used in another home"})+'</div>'+
   '<div class="r3-pr on"><b>Alerts she can see</b><small>For a child who is deaf or hard of hearing. Pictures and words lead; no cue is sound only.</small>'+li([["check","Read aloud off (pictures and words lead)"],["check","Roomier reading, ready for captions"],["clock","A captions wish is recorded (live captions are not built yet)"],["bell","Alerts show a picture and words that stay until tapped, with a gentle buzz"]],"ok")+'<div class="r3-cue" style="margin-top:6px" '+K.n(5)+'>'+I("image",22,1.9)+'<span>A picture is on the shelf</span></div><p class="r3-fine" style="margin-top:6px">Turning it off leaves the settings as they are now; change them under Accessibility.</p></div>';
  return lay(c,main,st,"Suites shelf",{eyebrow:"Family compass",stLabel:"Accessibility profiles"});}});

/* ================================================= CHILD TIERS, GAMES, PAIRING == */
function gcard(ic,t,s,tag,n){return '<div class="r3-gc" role="button" tabindex="0"'+K.n(n)+'><span class="gi">'+I(ic,24,1.9)+'</span><b>'+E(t)+'</b><small>'+E(s)+'</small><span class="chip sm" style="justify-self:start">'+I(tag==="a"?"pawn":"users",12,2)+(tag==="a"?"Play against Dad":"Just for fun, together")+'</span></div>';}
function hs(t){return '<div class="r3-hs">'+E(t)+'</div>';}

S("ChildHome","child","Her home: three tiers","Child tiers and games",{wide:true,refs:"child_home.dart, tiered_tile.dart, family_structure_logic.dart",
 desc:"Ivy’s home as built: one Hero tile (My day), four Featured, a quiet Standard grid, and a sleeps line. A tile the family model or a guardian hides is simply absent.",
 notes:[nn(1,"Hero is My day, 140 dp; Featured are Play together, Messages, Storyteller, Show & tell (132 dp); Standard are My people, Homework, My list, More for you (84 dp).","three clear levels with depth and size doing the ranking, not colour.","§8.4 target floor 64 dp; sizes grow with text."),
  nn(2,"a tile appears only if her band and a guardian allow it; no disabled or greyed tiles.","the grid reflows; nothing is locked-looking.","absent, not broken."),
  nn(3,"Messages shows a plain dot when something is unread, no number.","a small dot only, spoken as 'Something new'.","P2: no unread count, no badge numbers."),
  nn(4,"in her birthday week a quiet line appears under the greeting; a 'sleeps until' line closes the page.","one calm text line each, no confetti, no counter beyond sleeps.","a line, not a task."),
  nn(5,"ages 3 to 4 get only three big pictures (call, stories, colour); the home grows with her band.","drawn beside the 5-to-7 home so the band step is clear.","the ladder is permanent.")],
 r:function(c){
  var ctop=K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})});
  var main='<button type="button" class="btn tonal sm" style="justify-self:start">A quiet line: 6 sleeps to your birthday</button>'+K.tile("hero",{ic:"sun",title:"My day",sub:"School, then Marcus’s",scene:"hills",n:1})+
   '<div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play together"})+K.tile("feat",{ic:"chat",title:"Messages",n:3}).replace(/<\/div>$/,'<i class="r3-udot" role="img" aria-label="Something new"></i></div>')+K.tile("feat",{ic:"book",title:"Storyteller"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>'+
   '<div class="grid2">'+K.tile("std",{ic:"users",title:"My people"})+K.tile("std",{ic:"pencil",title:"Homework"})+K.tile("std",{ic:"list",title:"My list"})+K.tile("std",{ic:"more",title:"More for you"})+'</div>'+'<div class="r3-sleep"'+K.n(4)+'>'+I("moon",18,2)+'<span>3 sleeps until Marcus’s</span></div>';
  var st=K.card(eb("Ages 3 to 4")+'<div class="grid3">'+K.tile("std",{ic:"video",title:"Call"})+K.tile("std",{ic:"book",title:"Stories"})+K.tile("std",{ic:"palette",title:"Colour"})+'</div><p class="r3-fine" style="margin-top:6px">Three big pictures. No settings, no More.</p>',"flat",5)+
   K.card(eb("A guardian hid Messages")+'<div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play together"})+K.tile("feat",{ic:"book",title:"Storyteller"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>',"flat",2);
  return c.form==="tablet"?ctop+'<div class="tw r3"><div>'+main+'</div><div>'+eb("Other states")+st+'</div></div>':ctop+P(main+K.divider("Other states")+st,{cls:"r3c"});},
 cover:function(){return K.sb()+K.top({logo:true,title:"Hi, Ivy"})+P(K.tile("hero",{ic:"sun",title:"My day",scene:"hills"})+'<div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play"})+K.tile("feat",{ic:"chat",title:"Messages"})+'</div>'+K.tile("std",{ic:"more",title:"More for you"}),{cls:"r3c"});}});

S("ChildMore","child","More for you","Child tiers and games",{wide:true,refs:"child_more.dart, rhythm_voice_sections.dart, village_sections.dart",
 desc:"Ivy’s second page: every section a guardian or her band opens, as plain tiles. Sections appear only when there is something to see; nothing guardian-facing is reachable.",
 notes:[nn(1,"sections: Just yours, Together, Keep and grow, My day, My voice, My village, Make things, Show & tell, Stories, Colour.","each section has a quiet label and big rows; every tile can be heard.","§8.1: no settings affordance anywhere here."),
  nn(2,"Keep and grow shows My memory box, My doorframe, Something new, A letter for you, Stories for you only when there is something to see.","absent tiles don’t leave gaps.","fail closed."),
  nn(3,"My voice (The sky in me, Worry box, My helpers, Say it with pictures) appears only after a guardian turns Voice on.","the whole section is absent while Voice is off.","§8.24.1."),
  nn(4,"Growing up, The quiet corner and Take your things with you appear from 10 (the ladder’s first rung).","drawn in the second state so the 5-year-old’s page stays short.","age is relevance, never a legal gate."),
  nn(5,"the Colour tile is the one tile with her colour on its border.","one placement only.","§8.6.2 placement budget.")],
 r:function(c){
  function sec(t,tiles){return hs(t)+'<div class="r3-stack">'+tiles.map(function(x,i){return ht(x[0],x[1],x[2],x[3]);}).join("")+'</div>';}
  var main=sec("Just yours",[["book","My journal","Just for you",1],["mail","Letters to me","Write now, open later"]])+sec("Together",[["moon","My weeks","Where you sleep, night by night"],["pencil","Teach Dad something","You be the teacher"],["book","Read together","One book, two of you"]])+
   sec("Keep and grow",[["image","My memory box","Things you chose to keep"],["footprint","My doorframe","Look how you are growing",2],["star","Something new","Times you did something new"]])+
   sec("My day",[["list","My routine","Bedtime"],["swap","First, then","What comes next"],["layers","My bag","My things"],["home","A new place","Before we go"]])+
   sec("My voice",[["cloud","The sky in me","How today feels"],["inbox","My worry box","Put one in"],["users","My helpers","The grown-ups you can go to"],["mic","Say it with pictures","Tap to say it"]])+
   sec("My village",[["users","Faces of my people",""],["image","Our shelf","Pictures for each other"]])+
   sec("Make things",[["brush","Doodle desk","Draw anything"],["palette","Colouring","Colour a picture"]]);
  var st=K.card(eb("From 10")+'<div class="r3-stack">'+ht("sparkle","Growing up","What comes next")+ht("leaf","The quiet corner","Things that fade as you grow")+ht("download","Take your things with you","For when you are grown up")+'</div>',"flat",4)+
   K.card(eb("Voice is off")+'<p class="r3-sub" style="margin:0">“My voice” isn’t on her page at all. Nothing is greyed out.</p>',"flat",3)+
   K.card(eb("Colour")+'<div class="r3-ht" style="border:3px solid '+SW.sea[0]+'" '+K.n(5)+'><span class="gi" style="background:'+SW.sea[0]+'33;color:'+SW.sea[1]+'">'+I("palette",24,1.9)+'</span><span><b>Today’s colour</b><small>Sea blue</small></span></div>',"flat");
  return clay(c,main,st,"More for you",{noBack:false,stLabel:"From 10, voice off, colour"});}});

S("GamePicker","child","Play together","Child tiers and games",{wide:true,refs:"game_picker.dart, games_hub.dart, game_logic.dart",
 desc:"One door onto everything she can play, filtered by her age and a guardian’s choices, with a Play together on this table section for two screens in the same room.",
 notes:[nn(1,"'What do you want to play, Ivy? Something to play, just the two of you.'","a warm title, then a short, ranked set; no sea of cards.","P2: no leaderboards, no wins."),
  nn(2,"a Recommended row (guardian favourites first, then newly unlocked by age) and a Surprise me button, only with a live session.","drawn as a single warm row; absent when there is nothing to recommend.","she sees the result of a favourite, never the mechanism."),
  nn(3,"each game card says who it is for: Play against Dad, or Just for fun, together.","a small chip, not a caption.","honest about who she plays against."),
  nn(4,"'Play together on this table': War (5+), Draw and guess (5+), Puzzle together (4+), Connect 4 (6+), Uno (6+), two devices in the same room, no internet.","five rows gated by her age: at 5 she sees three; Connect 4 and Uno arrive on her birthday.","no scores, no records."),
  nn(5,"word search and Guess the word start with a grown-up’s setup, so they are guardian-only and never listed here.","just absent.","§8.1."),
  nn(6,"a game in progress can finish at the play window; the picker is replaced by Goodnight when it rests.","the resting screen is its own design.","")],
 r:function(c){
  var main='<div'+K.n(1)+'><h2 class="r3-h" style="font-size:24px">What do you want to play, Ivy?</h2><p class="r3-sub">Something to play, just the two of you.</p></div>'+
   hs("Recommended")+'<div class="r3-gg" '+K.n(2)+'>'+gcard("pawn","War","Flip your cards, biggest card wins","t",3)+gcard("puzzle","Puzzle together","Put the pieces in, side by side","t")+'</div>'+K.btn("Surprise me",{kind:"tonal",full:true,ic:"sparkle"})+
   hs("Play together on this table")+'<div class="r3-stack" '+K.n(4)+'>'+ht("dice","War","Flip your cards, biggest card wins")+ht("pencil","Draw and guess","One draws, the other guesses")+ht("puzzle","Puzzle together","Put the pieces in, side by side")+'</div>'+
   hs("Board games")+'<div class="r3-stack">'+ht("grid3","Checkers","You against the game, on this screen")+ht("target","Battleship","Hunt for hidden ships, on this screen")+'</div>'+hs("On your own")+ht("search","Find the thing","Spot things in a busy picture");
  var st=K.card(eb("On her birthday")+'<p class="r3-sub" style="margin:0 0 8px">At 6, Connect 4 and Uno join the table section, and arrive in Recommended first.</p><div class="r3-stack">'+ht("grid","Connect 4","Drop discs, get four in a row")+ht("layers","Uno","Match the colour or the number")+'</div>',"flat",4)+
   K.card(eb("Nothing yet")+K.emptyState({spot:"leaf",title:"Nothing to play yet",sub:"A grown-up can open more games."}),"flat")+call("Word search and Guess the word start with a grown-up’s setup, so they are never listed here.","info","lock",5)+call("When the play window rests, this page is replaced by Goodnight.","info","moon",6);
  return clay(c,main,st,"Play together",{stLabel:"When she turns 6, and empty"});}});

S("LocalPlay","child","Play nearby","Child tiers and games",{wide:true,refs:"local_pairing.dart, local_play_screen.dart, game_war.dart, local_discovery.dart",
 desc:"Two screens in the same room find each other with no internet and no account. Every state is calm, and a lost connection never blames either device.",
 notes:[nn(1,"'Looking nearby…' while the two devices find each other over the local network.","a still ring pattern, not a spinner: nothing animates on its own.","no media path, no account, no internet."),
  nn(2,"'Found Dad nearby' then a start button (Deal the cards for War), or 'Waiting for Dad to deal…' on the other side.","a big warm card with both names and one action.","the child may not be left holding a stuck screen."),
  nn(3,"'Dad stepped out of range. Nothing is lost — find each other again to keep playing.'","a reassuring card with a soft wifi glyph; the game state is kept.","state the fact, reassure, never blame."),
  nn(4,"'Can’t find a local network to play on right now.'","a calm error with one next step.","honest, no banned phrases."),
  nn(5,"the shipped War screen shows a number under each pile (cards held).","drawn without a number: a stack of cards.","P2 spirit: no counts shown to her; flagged for an owner decision.")],
 r:function(c){
  var main='<div class="card tint" style="text-align:center;padding:22px 14px;display:grid;gap:10px;justify-items:center"'+K.n(2)+'><span class="r3-pl" style="width:76px;height:76px;border-radius:50%;background:var(--surface);color:var(--pri)">'+I("users",38,1.8)+'</span><h2 class="r3-h" style="font-size:24px">Found Dad nearby</h2></div>'+K.btn("Deal the cards",{full:true,size:"lg",ic:"play"});
  var st=K.card(eb("Looking")+'<div style="display:grid;place-items:center;padding:14px" '+K.n(1)+'><svg viewBox="0 0 120 120" width="110" height="110" aria-hidden="true"><circle cx="60" cy="60" r="12" fill="var(--pri)"/><circle cx="60" cy="60" r="28" fill="none" stroke="var(--pri)" stroke-width="3" opacity=".6"/><circle cx="60" cy="60" r="46" fill="none" stroke="var(--pri)" stroke-width="3" opacity=".3"/></svg><b class="r3-h" style="font-size:18px">Looking nearby…</b></div>',"flat")+
   K.card(eb("Waiting")+quiet("Waiting for Dad to deal…","hourglass"),"flat")+
   K.card(eb("Out of range")+'<div style="display:flex;gap:10px;align-items:flex-start" '+K.n(3)+'>'+pl("wifioff","info")+'<p class="r3-sub" style="margin:0">Dad stepped out of range. Nothing is lost — find each other again to keep playing.</p></div>',"")+
   K.card(eb("No local network")+call("Can’t find a local network to play on right now.","warn","wifioff",4),"flat")+call("The shipped War screen shows a number under each pile. This redesign shows a stack of cards without one.","warn","flag",5);
  return clay(c,main,st,"War",{noBack:false,stLabel:"Looking, waiting, out of range, no network"});}});

/* ------------------------------------------------------------------ inject -- */
(function(){if(document.getElementById("r3s-css"))return;var s=document.createElement("style");s.id="r3s-css";s.textContent=CSSA.join("\n");document.head.appendChild(s);})();
})();
