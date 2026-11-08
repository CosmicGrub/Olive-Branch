/* screens-r2-grow: Round 2 screens for settings, ages and family structure, care, and Parent Learn.
   Everything here is sample data (Ivy, Dad, Mom, Dana). Local parts use the g2- prefix and theme variables only. */
(function(){"use strict";var K=OB,I=K.ico,D=K.def,E=K.esc;

/* ------------------------------------------------------------ local styles -- */
var CSS=[
".ob .g2t{padding:8px 16px}",
".ob .g2t .cbtn,.ob .g2 .cbtn{width:48px;height:48px}",
".ob.child .g2t .g2b,.ob.child .g2t .cbtn,.ob.child .g2 .cbtn{width:64px;height:64px}",
".ob .g2t .g2b{width:48px;height:48px;border-radius:50%;border:1px solid color-mix(in srgb,var(--outline) 80%,transparent);background:var(--surface);box-shadow:var(--shadow1);display:grid;place-items:center;color:var(--ink);flex:none;padding:0}",
".ob .g2 .btn{min-height:48px;white-space:normal;text-align:center;line-height:1.15;padding-top:9px;padding-bottom:9px}",
".ob .g2 .btn.lg{min-height:56px;font-size:16px}",
".ob .g2 .btn.sm{min-height:48px;padding-left:14px;padding-right:14px;font-size:14px;border-radius:14px}",
".ob .g2 .seg span{min-height:48px;display:grid;place-items:center;padding:0 4px;line-height:1.15}",
".ob .g2 .row{min-height:56px}",
".ob .g2 .field{min-height:56px}",
".ob .g2 .field .fv b{white-space:normal;overflow-wrap:anywhere}",
".ob.child .g2 .btn{min-height:64px;font-size:17px}",
".ob.child .g2 .row{min-height:72px}",
".ob .g2 h5,.ob .g2-h5{font:800 15px/1.2 var(--font-display);margin:0}",
".ob .g2-eb{display:block;font:700 10.5px/1 var(--font-mono);letter-spacing:.08em;text-transform:uppercase;color:var(--ink3);margin-bottom:6px}",
".ob .card.hero .g2-eb,.ob .card.tint .g2-eb{color:inherit;opacity:.8}",
".ob .g2-lead{font:800 19px/1.25 var(--font-display);margin:0;color:var(--ink);letter-spacing:-.005em}",
".ob .card.hero .g2-lead,.ob .card.tint .g2-lead{color:inherit}",
".ob .g2-sub{margin:4px 0 0;color:var(--ink2);font-size:13.5px;line-height:1.4}",
".ob .g2-fine{margin:0;color:var(--ink3);font-size:12.5px;line-height:1.4}",
".ob .g2-stack{display:grid;gap:10px;min-width:0}",
".ob .g2-opt{display:flex;gap:12px;align-items:flex-start;min-height:56px;padding:12px 14px;border:1.5px solid var(--outline);border-radius:16px;background:var(--surface);min-width:0}",
".ob .g2-opt.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .g2-opt .rd{width:22px;height:22px;border-radius:50%;border:2px solid var(--ink3);flex:none;margin-top:1px;display:grid;place-items:center;color:var(--onPri)}",
".ob .g2-opt.on .rd{border-color:var(--pri);background:var(--pri)}",
".ob .g2-opt .ot{display:grid;gap:2px;min-width:0;flex:1}",
".ob .g2-opt b{font:700 14.5px/1.2 var(--font-body)}",
".ob .g2-opt small{font-size:12.5px;line-height:1.35;color:var(--ink3)}",
".ob .g2-opt.on small{color:inherit;opacity:.92}",
".ob .g2-opt.lk{background:var(--surface2);border-style:dashed}",
".ob .g2-ev{display:inline-flex;gap:6px;align-items:center;padding:4px 10px 4px 8px;border-radius:99px;font:700 12px/1.1 var(--font-body);white-space:nowrap}",
".ob .g2-ev .bars{display:inline-flex;gap:2px;align-items:flex-end;height:11px}",
".ob .g2-ev .bars i{width:3px;border-radius:1px;background:currentColor;opacity:.3}",
".ob .g2-ev .bars i.f{opacity:1}",
".ob .g2-ev .bars i:nth-child(1){height:5px}.ob .g2-ev .bars i:nth-child(2){height:7px}.ob .g2-ev .bars i:nth-child(3){height:9px}.ob .g2-ev .bars i:nth-child(4){height:11px}",
".ob .g2-ev.strong{background:var(--okC);color:var(--ok)}.ob .g2-ev.moderate{background:var(--infoC);color:var(--info)}",
".ob .g2-ev.weak{background:var(--warnC);color:var(--warn)}.ob .g2-ev.contested{background:var(--priC);color:var(--onPriC)}",
".ob .g2-priv{display:inline-flex;gap:5px;align-items:center;padding:4px 9px;border-radius:99px;background:var(--surface3);color:var(--ink2);font:700 11.5px/1.1 var(--font-body);white-space:nowrap}",
".ob .g2-fc{display:inline-flex;gap:6px;align-items:center;justify-content:center;min-height:48px;padding:0 16px;border-radius:99px;background:var(--surface);border:1.5px solid var(--outline);font:700 13.5px/1 var(--font-body);color:var(--ink2)}",
".ob .g2-fc.on{background:var(--pri);border-color:var(--pri);color:var(--onPri)}",
".ob .g2-fcs{display:flex;flex-wrap:wrap;gap:8px}",
".ob .g2-li{display:grid;gap:9px;margin:0;padding:0;list-style:none}",
".ob .g2-li li{display:flex;gap:10px;align-items:flex-start;font-size:13.5px;line-height:1.4;color:var(--ink2)}",
".ob .g2-li li .ico{margin-top:1px;color:var(--ink3)}",
".ob .g2-li.ok li .ico{color:var(--ok)}",
".ob .g2-sl{position:relative;height:48px;display:block}",
".ob .g2-sl .tr{position:absolute;left:0;right:0;top:20px;height:8px;border-radius:8px;background:var(--surface3)}",
".ob .g2-sl .th{position:absolute;top:10px;width:28px;height:28px;margin-left:-14px;border-radius:50%;background:var(--surface);border:3px solid var(--pri);box-shadow:var(--shadow1)}",
".ob .g2-sle{display:flex;justify-content:space-between;font-size:12px;color:var(--ink3);margin-top:-2px}",
".ob .g2-tl{display:grid;gap:0}",
".ob .g2-tl .it{display:grid;grid-template-columns:38px minmax(0,1fr);gap:10px;padding-bottom:16px;position:relative}",
".ob .g2-tl .it::before{content:\"\";position:absolute;left:18px;top:42px;bottom:2px;width:2px;background:var(--outline)}",
".ob .g2-tl .it:last-child{padding-bottom:0}.ob .g2-tl .it:last-child::before{display:none}",
".ob .g2-tl .tx{display:grid;gap:4px;min-width:0}.ob .g2-tl .tx b{font-size:14px;line-height:1.3}.ob .g2-tl .tx small{font-size:12.5px;color:var(--ink3)}",
".ob .g2-mini{background:var(--bg);border:1.5px solid var(--outline);border-radius:16px;padding:8px;display:grid;gap:5px;align-content:start;aspect-ratio:5/7;overflow:hidden;min-width:0;position:relative}",
".ob .g2-mini.sel{border-color:var(--pri);box-shadow:0 0 0 2px var(--pri)}",
".ob .g2-mini .mh{display:flex;gap:5px;align-items:center}.ob .g2-mini .mh i{width:12px;height:12px;border-radius:50%;background:var(--priC2)}.ob .g2-mini .mh u{height:7px;width:46%;border-radius:4px;background:var(--ink3);opacity:.45;text-decoration:none}",
".ob .g2-mini .mc{height:24px;border-radius:9px;background:linear-gradient(155deg,var(--pri),var(--priD))}",
".ob .g2-mini .mt{min-height:20px;border-radius:8px;background:var(--surface3);display:grid;place-items:center;color:var(--ink2)}",
".ob .g2-mini .mt.p{background:var(--priC);color:var(--onPriC)}.ob .g2-mini .mt.s{background:var(--surface);border:1px solid var(--outline)}",
".ob .g2-mini .mg2{display:grid;grid-template-columns:repeat(2,1fr);gap:4px}.ob .g2-mini .mg3{display:grid;grid-template-columns:repeat(3,1fr);gap:4px}",
".ob .g2-mini .ml{height:6px;border-radius:3px;background:var(--ink3);opacity:.35}",
".ob .g2-mini .dots{display:grid;grid-template-columns:repeat(7,1fr);gap:2px}.ob .g2-mini .dots i{aspect-ratio:1;border-radius:50%;background:var(--priC2)}",
".ob .g2-mini .dots i.d{background:var(--accentC);box-shadow:inset 0 0 0 1px var(--accent)}",
".ob .g2-mcap{font:700 12px/1.25 var(--font-body);text-align:center;color:var(--ink);margin-top:6px}",
".ob .g2-mcap small{display:block;font-weight:400;color:var(--ink3);font-size:11.5px}",
".ob .g2-pair{display:grid;grid-template-columns:minmax(0,1fr) auto minmax(0,1fr);gap:8px;align-items:center}",
".ob .g2-pair .ar{color:var(--ink3);display:grid}",
".ob .g2-steps{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:5px}",
".ob .g2-steps i{height:6px;border-radius:4px;background:var(--surface3)}.ob .g2-steps i.f{background:var(--pri)}",
".ob .g2-wk{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:4px}",
".ob .g2-wk i{aspect-ratio:1;border-radius:9px;display:grid;place-items:center;font:700 11px/1 var(--font-body);font-style:normal;background:var(--priC);color:var(--onPriC)}",
".ob .g2-wk i.d{background:var(--accentC);color:var(--ink);box-shadow:inset 0 0 0 1.5px var(--accent)}",
".ob .g2-wk.lk i{background-image:repeating-linear-gradient(135deg,transparent 0 5px,color-mix(in srgb,var(--ink) 16%,transparent) 5px 6px)}",
".ob .g2-wk.dim i{opacity:.4}",
".ob .g2-dl{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:4px;font:700 10px/1 var(--font-mono);color:var(--ink3);text-align:center;margin-bottom:4px}",
".ob .g2-leg{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;color:var(--ink2)}.ob .g2-leg span{display:inline-flex;gap:6px;align-items:center}",
".ob .g2-leg b{width:14px;height:14px;border-radius:5px;background:var(--priC);display:inline-block}.ob .g2-leg b.d{background:var(--accentC);box-shadow:inset 0 0 0 1.5px var(--accent)}",
".ob .g2-win{position:relative;height:30px;border-radius:12px;background:var(--surface3);overflow:hidden}",
".ob .g2-win .on{position:absolute;top:0;bottom:0;background:var(--pri)}",
".ob .g2-win .tail{position:absolute;top:0;bottom:0;background:linear-gradient(90deg,var(--pri),var(--priC))}",
".ob .g2-win .bd{position:absolute;top:-2px;bottom:-2px;width:3px;margin-left:-1.5px;background:var(--dpBed);border-radius:2px}",
".ob .g2-wt{position:relative;height:14px;font:500 9.5px var(--font-mono);color:var(--ink3);margin-top:5px}",
".ob .g2-wt span{position:absolute;transform:translateX(-50%)}.ob .g2-wt span:first-child{transform:none}.ob .g2-wt span:last-child{transform:translateX(-100%)}",
".ob .g2-sw{width:48px;height:48px;border-radius:50%;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)}",
".ob .g2-swbig{width:64px;height:64px;border-radius:22px;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)}",
".ob .g2-art{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}",
".ob .g2-art .a{border:1.5px solid var(--outline);border-radius:18px;padding:6px 6px 9px;background:var(--surface);display:grid;gap:6px;min-width:0}",
".ob .g2-art .a.on{border-color:var(--pri);box-shadow:0 0 0 2px var(--pri)}",
".ob .g2-art .a .sc{height:64px;border-radius:13px;overflow:hidden}.ob .g2-art .a .sc .scene{height:64px;border-radius:0}",
".ob .g2-art .a b{font-size:13px;padding:0 4px}",
".ob .g2-sk{height:14px;border-radius:7px;background:var(--surface3)}",
".ob .g2-sk.l{height:90px;border-radius:16px}",
".ob .g2-cmp{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}",
".ob .g2-cmp>div{border:1.5px solid var(--outline);border-radius:16px;padding:10px;background:var(--surface);display:grid;gap:6px;align-content:start;min-width:0}",
".ob .g2-cmp>div.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .g2-cmp b{font-size:14px}.ob .g2-cmp small{font-size:12px;opacity:.85}",
".ob .g2-kpw .kp button{width:56px;height:56px;border-radius:18px;font-size:20px}",
".ob .g2-kpw .kp{gap:8px}",
".ob .g2-quote{border-left:4px solid var(--outline);padding:2px 0 2px 12px;font-size:14px;line-height:1.5;color:var(--ink)}",
".ob .g2-mark{background:var(--warnC);color:var(--warn);border-radius:5px;padding:0 3px;font-weight:700}",
".ob .g2-src{display:flex;gap:10px;align-items:flex-start;padding:10px 0;min-height:48px}.ob .g2-src+.g2-src{border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}",
".ob .g2-src .ico{color:var(--ink3);margin-top:2px}.ob .g2-src b{font-size:13.5px;line-height:1.3;display:block}.ob .g2-src small{font-size:12px;color:var(--ink3)}",
".ob .g2-pad{display:grid;gap:12px}",
/* child */
".ob .g2c-tile{display:grid;justify-items:center;align-content:center;gap:8px;border-radius:30px;background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow1);min-height:132px;padding:14px;color:var(--pri)}",
".ob .g2c-tile.hero{min-height:176px;background:linear-gradient(155deg,var(--pri),var(--priD));color:var(--onPri);box-shadow:var(--shadow2);border:0}",
".ob .g2c-tile .gi{width:76px;height:76px;border-radius:26px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center}",
".ob .g2c-tile.hero .gi{background:rgba(255,255,255,.2);color:inherit;width:92px;height:92px;border-radius:32px}",
".ob .g2c34 .g2c-tile{min-height:196px}.ob .g2c34 .g2c-tile.hero{min-height:236px}",
".ob .g2c-big{font:800 28px/1.15 var(--font-display);letter-spacing:-.01em;color:var(--ink);margin:0}",
".ob .g2c-p{font:700 20px/1.4 var(--font-body);color:var(--ink);margin:0}",
".ob .g2c-house{border-radius:30px;padding:14px;display:grid;gap:12px;background:var(--surface);border:1.5px solid var(--outline);min-width:0}",
".ob .g2c-house.m{background:var(--priC);color:var(--onPriC);border-color:transparent}",
".ob .g2c-house.d{background:var(--accentC);color:var(--ink);border-color:transparent}",
".ob .g2c-house h4{font:800 18px/1.1 var(--font-display);margin:0;display:flex;gap:8px;align-items:center}",
".ob .g2c-ppl{display:grid;grid-template-columns:repeat(auto-fill,minmax(88px,1fr));gap:10px}",
".ob .g2c-per{display:grid;justify-items:center;gap:6px;background:var(--surface);color:var(--ink);border-radius:22px;padding:10px 6px;min-height:104px;align-content:center;min-width:0}",
".ob .g2c-per b{font:800 15px/1.1 var(--font-display);max-width:100%;overflow:hidden;text-overflow:ellipsis}",
".ob .g2c-per .cl{display:inline-grid;place-items:center;width:40px;height:40px;border-radius:50%;background:var(--pri);color:var(--onPri)}",
".ob .g2c-pg{display:flex;gap:10px;justify-content:center}.ob .g2c-pg i{width:14px;height:14px;border-radius:50%;background:var(--surface3)}.ob .g2c-pg i.f{background:var(--pri)}",
".ob .g2c-big2{font:800 84px/1 var(--font-display);letter-spacing:-.03em;font-variant-numeric:tabular-nums}"
].join("\n");
(function(){if(document.getElementById("g2-css"))return;var s=document.createElement("style");s.id="g2-css";s.textContent=CSS;document.head.appendChild(s);})();

/* --------------------------------------------------------------- helpers -- */
function top(title,o){o=o||{};return '<div class="top g2t">'+(o.noBack?(o.logo?K.logo(28):""):'<button class="g2b" aria-label="Back"'+K.n(o.nb)+'>'+I("chevL",20,2)+'</button>')+'<div class="ttl">'+(o.eyebrow?'<small>'+E(o.eyebrow)+'</small>':"")+'<b>'+E(title)+'</b></div>'+(o.right||"")+'</div>';}
function gt(title,o){return K.sb()+top(title,o);}
function pg(inner,o){o=o||{};return K.page(inner,{cls:"g2"+(o.cls?" "+o.cls:""),tab:o.tab||""});}
function tabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],["sliders","Settings"]],a);}
function sh(inner){return '<div class="scrim"></div><div class="sheet g2"><i class="grab"></i>'+inner+'</div>';}
function two(c,l,r,title,o){o=o||{};if(c.form==="tablet")return gt(title,o)+'<div class="tw g2"><div>'+l+'</div><div>'+r+'</div></div>'+(o.tab||"");return gt(title,o)+pg(l+r,{tab:o.tab});}
function ctop(title,o){o=o||{};return gt(title,{noBack:o.noBack,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:o.ns})});}
function cpg(inner,o){return K.page(inner,{cls:"g2 g2c"+((o&&o.cls)?" "+o.cls:""),tab:(o&&o.tab)||""});}
function opt(title,sub,on,o){o=o||{};return '<div class="g2-opt'+(on?" on":"")+(o.lk?" lk":"")+'"'+K.n(o.n)+'><span class="rd">'+(on?I("check",12,3.2):"")+'</span><span class="ot"><b>'+E(title)+'</b>'+(sub?'<small>'+sub+'</small>':"")+'</span>'+(o.trail||"")+'</div>';}
function li(items,cls){return '<ul class="g2-li'+(cls?" "+cls:"")+'">'+items.map(function(x){return '<li>'+I(x[0],16,2)+'<span>'+x[1]+'</span></li>';}).join("")+'</ul>';}
function ev(kind){var m={strong:["Strong",4],moderate:["Moderate",3],weak:["Weak",2],contested:["Contested",0]}[kind];
 var g=kind==="contested"?I("swap",13,2):'<span class="bars" aria-hidden="true">'+[1,2,3,4].map(function(i){return '<i class="'+(i<=m[1]?"f":"")+'"></i>';}).join("")+'</span>';
 return '<span class="g2-ev '+kind+'">'+g+'Evidence: '+m[0]+'</span>';}
function priv(t){return '<span class="g2-priv">'+I("lock",12,2.2)+E(t||"Only you")+'</span>';}
function sl(pct,l,r,n){return '<div'+K.n(n)+'><div class="g2-sl"><span class="tr"></span><span class="th" style="left:'+pct+'%"></span></div><div class="g2-sle"><span>'+E(l)+'</span><span>'+E(r)+'</span></div></div>';}
function row(o){return K.row(o);}
function grpCard(label,rows,n){return K.sectionLabel(label)+K.card(rows,"",n);}
function mini(kind,sel,o){o=o||{};var m="";
 if(kind==="t34")m='<div class="mh"><i></i></div><div class="mc" style="height:46px"></div><div class="mt p" style="min-height:34px">'+I("book",13,2)+'</div><div class="mt p" style="min-height:34px">'+I("palette",13,2)+'</div>';
 else if(kind==="t57")m='<div class="mh"><i></i><u></u></div><div class="mc"></div><div class="mt p" style="min-height:22px">'+I("calendar",11,2)+'</div><div class="mg2"><div class="mt s">'+I("dice",11,2)+'</div><div class="mt s">'+I("chat",11,2)+'</div><div class="mt s">'+I("book",11,2)+'</div><div class="mt s">'+I("camera",11,2)+'</div></div><div class="mg3"><div class="mt"></div><div class="mt"></div><div class="mt"></div></div>';
 else if(kind==="t812")m='<div class="mh"><i></i><u></u></div><div class="mc" style="height:18px"></div><div class="dots"><i></i><i></i><i class="d"></i><i class="d"></i><i></i><i></i><i></i></div><div class="ml" style="width:80%"></div><div class="ml" style="width:60%"></div><div class="ml" style="width:70%"></div><div class="mg3"><div class="mt p">'+I("puzzle",10,2)+'</div><div class="mt p">'+I("dice",10,2)+'</div><div class="mt p">'+I("pawn",10,2)+'</div></div>';
 else if(kind==="t13")m='<div class="mh"><i></i><u></u></div><div class="ml" style="width:70%"></div><div class="mt s" style="min-height:24px">'+I("calendar",11,2)+'</div><div class="mt s" style="min-height:24px">'+I("clock",11,2)+'</div><div class="mt s" style="min-height:24px">'+I("lock",11,2)+'</div><div class="ml" style="width:50%"></div>';
 else if(kind==="alt"||kind==="p2255"){var seq=kind==="alt"?"mmmmmmmddddddd":"mmddmmmmmddddd";m='<div class="mh"><i></i><u></u></div><div class="mc" style="height:16px"></div><div class="dots" style="grid-template-columns:repeat(7,1fr);gap:3px">'+seq.split("").map(function(c){return '<i class="'+(c==="d"?"d":"")+'"></i>';}).join("")+'</div><div class="ml" style="width:70%"></div><div class="mt p" style="min-height:22px">'+I("moon",11,2)+'</div>';}
 return '<div class="g2-mini'+(sel?" sel":"")+'">'+m+'</div>';}
function wk(seq,cls){return '<div class="g2-wk'+(cls?" "+cls:"")+'">'+seq.split("").map(function(c){return '<i class="'+(c==="d"?"d":"")+'">'+(c==="d"?"D":"M")+'</i>';}).join("")+'</div>';}
function dayLabels(){return '<div class="g2-dl">'+["MON","TUE","WED","THU","FRI","SAT","SUN"].map(function(d){return '<span>'+d+'</span>';}).join("")+'</div>';}
function legend(){return '<div class="g2-leg"><span><b></b>Mom’s house</span><span><b class="d"></b>Dad’s house</span></div>';}
function pav(n,s){var m={Mom:["M",""],Dad:["D","accent"],Dana:["Da","accent"],Grandma:["G",""],Ivy:["I",""],Leo:["L","accent"]}[n]||[n.charAt(0),""];return K.avatar(m[0],{size:s||40,tone:m[1]});}
function note1(t){return '<p class="g2-fine">'+t+'</p>';}
function sample(){return '<span class="g2-priv">Sample family</span>';}

/* ================================================================ SETTINGS == */
D("r2SettingsHub","guardian","Settings hub",{grp:"R2 Settings",since:"new",isNew:true,wide:true,
 desc:"Settings gets its own tab, with five plainly named groups. Everything configurable is one tap from here, and the child’s app has no equivalent.",
 notes:[[1,"The proposed guardian tab bar: Today, Messages, Together, Family, Settings. Settings replaces “More”."],[2,"Each row states its current value, so most checks need no tap."],[3,"Her: what Ivy’s app looks like and which age band she is in."],[4,"Safety: the PIN, parental controls and the play window."],[5,"Learn holds choices only; the cards live in Family. It is private to each guardian."]],
 r:function(c){
  var her=grpCard("Her",row({ic:"palette",title:"Colour and art",sub:"Today: sea blue · Watercolour",go:true,n:3})+row({ic:"leaf",title:"How her app looks",sub:"Olive · light",go:true})+row({ic:"sparkle",title:"Age band",sub:"5 to 7 · turns 6 on Dec 9",go:true})+row({ic:"eye",title:"Accessibility for her device",sub:"Read aloud on",go:true}));
  var fam=grpCard("Family",row({ic:"users",title:"Family structure",sub:"2 homes · 5 people",go:true})+row({ic:"calendar",title:"Homes and rhythm",sub:"Alternating weeks",go:true})+row({ic:"user",title:"Adults and helpers",sub:"Mom, Dad, Dana, Grandma",go:true})+row({ic:"device",title:"Devices",sub:"3 paired",go:true}));
  var saf=grpCard("Safety",row({ic:"key",title:"Guardian PIN",sub:"Set 12 days ago",go:true})+row({ic:"shield",title:"Parental controls",sub:"On",go:true})+row({ic:"moon",title:"Play window",sub:"3:30 to 7:00 PM · wind-down to 7:30",go:true,n:4}),"");
  var lrn=grpCard("Learn",row({ic:"book",title:"Parent Learn choices",sub:"Private to you · reflection off",go:true,n:5}));
  var acc=grpCard("Account",row({ic:"user",title:"Your account",sub:"Mom",go:true})+row({ic:"bell",title:"Notifications",sub:"Quiet 9 PM to 6 AM",go:true})+row({ic:"download",title:"Your data and export",go:true}));
  var head=K.field("Search settings","",{ph:"Try “bedtime” or “colour”",ic:"search"})+K.banner("pri","Ivy never sees these settings. Her app has none.","lock",2);
  if(c.form==="tablet")return gt("Settings",{noBack:true,eyebrow:"Ivy’s app"})+'<div class="tw g2"><div>'+head+her+fam+'</div><div>'+saf+lrn+acc+'</div></div>'+tabs(4);
  return gt("Settings",{noBack:true,eyebrow:"Ivy’s app"})+pg(head+her+fam+saf+lrn+acc,{tab:tabs(4)});},
 cover:function(){return K.sb()+top("Settings",{noBack:true})+pg(K.card(row({ic:"palette",title:"Her",go:true})+row({ic:"users",title:"Family",go:true})+row({ic:"shield",title:"Safety",go:true})+row({ic:"book",title:"Learn",go:true})+row({ic:"user",title:"Account",go:true})),{tab:tabs(4)});}});

D("r2HerColourArt","guardian","Her colour and art",{grp:"R2 Settings",since:"new",isNew:true,
 desc:"Colour of the day is hers. A guardian chooses how it is drawn and where it appears, and can turn the question off. Every device she uses ends up with the same answer.",
 notes:[[1,"Today’s colour is shown as a fact. There is no picker here because the colour is her answer to one question."],[2,"Art style is the guardian’s choice. It changes how pictures are drawn, never her colour."],[3,"One question a day. The latest answer wins, so all her devices agree."],[4,"The limits are written out, so a guardian knows what Ivy decides and what they do."]],
 r:function(){return gt("Her colour and art",{eyebrow:"Ivy"})+pg(
  K.card('<div style="display:flex;gap:14px;align-items:center"'+K.n(1)+'><span class="g2-swbig" style="background:#2F8FC4"></span><div style="min-width:0"><span class="g2-eb" style="margin:0 0 4px">Today’s colour</span><b class="g2-lead">Sea blue</b><p class="g2-sub">Ivy chose it at 7:42 AM, her time.</p></div></div>')+
  K.sectionLabel("Art style")+'<div class="g2-art"'+K.n(2)+'>'+[["hills","Watercolour",1],["paper","Paper cut",0],["sea","Soft shapes",0],["letters","Crayon",0]].map(function(a){return '<div class="a'+(a[2]?" on":"")+'"><div class="sc">'+K.scene(a[0],150,64)+'</div><b>'+a[1]+'</b></div>';}).join("")+'</div>'+note1("Drawings in activities use this style. Thumbnails here are placeholders.")+
  K.card('<h4>One question a day</h4><p>Ivy is asked once, in the morning. The latest answer wins everywhere.</p>'+row({ic:"device",title:"Ivy’s phone",sub:"Sea blue · 7:42 AM",trail:K.chip("Matches",{tone:"ok",sm:true})})+row({ic:"device",title:"Ivy’s tablet",sub:"Sea blue · 7:42 AM",trail:K.chip("Matches",{tone:"ok",sm:true})})+'<p class="g2-fine" style="margin-top:4px">If two devices are answered close together, the later answer is kept on both.</p>',"",3)+
  K.card('<h5>You can</h5>'+li([["check","Choose the art style"],["check","Choose which activities use her colour"],["check","Turn the daily question off"]],"ok")+'<div style="height:12px"></div><h5>You can’t</h5>'+li([["lock","Pick or change her colour for her"],["lock","See why she chose it, or a history of her moods"],["lock","Show it to anyone as a reading of how she feels"]]),"flat",4)+
  K.btn("Save art style",{full:true,size:"lg"}));}});

D("r2PlayWindow","guardian","Play window and wind-down",{grp:"R2 Settings",since:"new",isNew:true,
 desc:"A guardian sets when games are open. The ending is a goodnight in her own frame, never a limit she can run into.",
 notes:[[1,"The window is drawn on her day, in her time. The marker is her bedtime."],[2,"The wind-down is a gentle tail, not a cut-off. A game in progress can finish."],[3,"This is exactly what Ivy sees. One calm sentence. No timer, no red, no lock."],[4,"A longer window is shown to the other guardian, the same rule as daily time."]],
 r:function(){return gt("Play window",{eyebrow:"Ivy’s games"})+pg(
  K.card('<span class="g2-eb">Her day, her time</span><div class="g2-win"'+K.n(1)+'><span class="on" style="left:63.3%;width:23.4%"></span><span class="tail" style="left:86.7%;width:3.3%"></span><span class="bd" style="left:90%"></span></div><div class="g2-wt"><span style="left:0">6a</span><span style="left:40%">12p</span><span style="left:80%">6p</span><span style="left:100%">9p</span></div><p class="g2-sub" style="margin-top:10px">Games open from 3:30 PM and rest at 7:00 PM. Bedtime is 7:30 PM.</p>')+
  K.field("Opens","3:30 PM",{ic:"sun"})+K.field("Rests at","7:00 PM",{ic:"moon"})+
  '<div class="g2-stack"><h5 style="margin:6px 2px 0">Wind-down</h5>'+K.seg(["Off","15 min","30 min"],2,2)+note1("The last half hour fades toward goodnight. A game in progress can finish.")+'</div>'+
  K.card('<span class="g2-eb">What Ivy sees at 7:00 PM</span><div style="display:flex;gap:12px;align-items:center"'+K.n(3)+'><div style="width:84px;height:62px;border-radius:14px;overflow:hidden;flex:none">'+K.scene("night",84,62)+'</div><p style="font:800 16px/1.25 var(--font-display);color:var(--ink);margin:0">It’s getting sleepy. One more, then goodnight.</p></div><p class="g2-sub">Nothing is taken away. Games open again at 3:30 tomorrow. Messages from family still arrive.</p>',"tint")+
  K.banner("info","If you make the window longer, Dad is told. Shorter is never reported.","info",4)+K.btn("Save play window",{full:true,size:"lg"}));}});

D("r2Accessibility","guardian","Accessibility for her device",{grp:"R2 Settings",since:"new",isNew:true,
 desc:"A guardian-set panel for how the child’s app reads and moves. The child’s shell has no settings, so this is where it changes.",
 notes:[[1,"The sample line changes as options are switched, so a guardian sees the effect before saving."],[2,"Read aloud is a tap on every screen she reads. It never starts by itself."],[3,"Honest copy: the evidence for special dyslexia fonts is mixed, so this offers spacing instead."],[4,"Her device’s own system accessibility settings still apply on top."]],
 r:function(){return gt("Accessibility",{eyebrow:"Ivy’s device"})+pg(
  K.card('<span class="g2-eb">Preview</span><p style="margin:0;font:700 17px/1.7 var(--font-body);letter-spacing:.05em;word-spacing:.12em;color:var(--ink)"'+K.n(1)+'>Dad’s story is ready at bedtime.</p>',"tint")+
  K.card(row({ic:"volume",title:"Read aloud everywhere",sub:"A speaker button on every screen",trail:K.toggle(true),n:2})+row({ic:"book",title:"Easier-to-read spacing",sub:"Wider letters and lines, left aligned",trail:K.toggle(true),n:3})+row({ic:"pause",title:"Reduce motion",sub:"No movement except what her finger drives",trail:K.toggle(true)})+row({ic:"hand",title:"Larger targets",sub:"Buttons grow from 64 to 80 px. Fewer fit on screen.",trail:K.toggle(false)})+row({ic:"tv",title:"Captions",sub:"On calls and stories, where a caption exists",trail:K.toggle(true)}))+
  K.field("Text size","Standard",{ic:"pencil"})+K.banner("info","Her device’s own accessibility settings apply as well. These are added, not instead.","info",4)+K.btn("Save for Ivy’s devices",{full:true,size:"lg"})+note1("Applies the next time her app opens. No restart or sign-in needed."));}});

D("r2SiblingSwitcher","guardian","Sibling switcher",{grp:"R2 Settings",since:"new",isNew:true,
 desc:"Switching to another child needs the guardian PIN, so a child holding the phone cannot reach a sibling’s settings. Linking never widens authority.",
 notes:[[1,"The list shows only children this guardian already guards."],[2,"The PIN is asked for every switch. Keys are shuffled, a wrong PIN simply clears."],[3,"Switching changes who the guardian screens are about. It never merges two children."]],
 r:function(){return gt("Switch child",{noBack:true})+pg(K.card(row({av:pav("Ivy",42),title:"Ivy",sub:"Viewing now · 5 years old",trail:K.chip("Current",{tone:"pri",sm:true}),n:1})+row({av:pav("Leo",42),title:"Leo",sub:"You are a guardian · 3 years old",trail:I("lock",18,2)}))+K.banner("info","Linking Ivy and Leo lets them play together. It gives no one access to the other child.","shield"))+
  sh('<h4 style="font:800 20px var(--font-display);margin:0;text-align:center">Enter your PIN to switch to Leo</h4>'+K.dots(4,2)+'<div class="g2-kpw"'+K.n(2)+'><div class="kp">'+[7,3,9,1,5,8,2,6,4].map(function(n){return '<button>'+n+'</button>';}).join("")+'</div></div><div class="btns">'+K.btn("Cancel",{kind:"ghost"})+'</div>');}});

D("r2CoViewHub","guardian","Read together and daily time",{grp:"R2 Settings",since:"new",isNew:true,
 desc:"The entry to reading together, with the day’s total across both homes. Lowering the allowance is free; a raise is shown to the other guardian.",
 notes:[[1,"One clear action first: start reading. Ivy chooses nothing."],[2,"Time used is counted across both homes, so neither guardian does the maths."],[3,"This is a quiet gauge, not a goal. There is nothing to fill and nothing is awarded."],[4,"Raising the allowance applies at once and is shown to Dad. It is not a request he can refuse."]],
 r:function(){return gt("Read together",{eyebrow:"Ivy",noBack:true,right:K.iconBtn("sliders",{label:"Daily time",kind:"tonal"})})+pg(
  K.card('<span class="g2-eb">Ready when she is</span><p class="g2-lead">Pick a book and read it with Ivy, page by page.</p><div style="height:12px"></div>'+K.btn("Start reading",{ic:"book",full:true,size:"lg",n:1,kind:"tonal"}),"hero")+
  K.card('<h4>Today across both homes</h4>'+K.progress(52)+'<div class="kv" style="margin-top:10px"'+K.n(2)+'><span>Used</span><span>1 h 45 m of 3 h</span><span>At Mom’s house</span><span>1 h</span><span>At Dad’s house</span><span>45 m</span></div>'+note1("Reading and watching share one daily total. It starts again at 6 AM her time."))+
  K.card('<h4>Daily time</h4>'+K.seg(["Off","1 h","2 h","3 h"],3,3)+'<div style="height:10px"></div>'+K.banner("pri","You raised this from 2 h to 3 h today at 6:10 PM. Dad has been told.","info",4))+
  K.card(row({ic:"tv",title:"Watch together",sub:"Uses the same daily time",go:true})));}});

/* ===================================================== AGES AND FAMILY ===== */
D("r2AgeBands","guardian","Age bands",{grp:"R2 Ages",since:"new",isNew:true,wide:true,
 desc:"What her home looks like at each stage, a preview of her next birthday, a per-area override and a hold so nothing changes before a guardian has told her.",
 notes:[[1,"Four bands with names a family would use. Ivy is marked; nobody else is compared to anyone."],[2,"Each band is drawn as her real home, not described."],[3,"A birthday is a preview, never a surprise. Her next birthday changes nothing about her band."],[4,"A child can be ahead in reading and behind in other things, so each area can follow a different band."],[5,"The hold is the default. Nothing moves for her until a guardian says so."]],
 r:function(c){
  var bands=[["t34","3 to 4","Three big pictures",0],["t57","5 to 7","Ivy is here",1],["t812","8 to 12","Words, her own list",0],["t13","13 and up","Mostly hers",0]];
  var l=K.banner("pri","Bands are proposals. Any guardian can hold or change any of them.","info")+K.card('<div class="grid2"'+K.n(2)+'>'+bands.map(function(b){return '<div>'+mini(b[0],b[3])+'<div class="g2-mcap">'+b[1]+'<small>'+b[2]+'</small></div></div>';}).join("")+'</div>')+
   K.card('<h4>At 5 to 7</h4>'+li([["volume","Pictures lead and every word can be heard"],["palette","Her colour of the day and favourite things"],["dice","Games for two, played in turns"],["lock","No settings, no lists of her own yet"]])+'<p class="g2-fine" style="margin-top:8px">Words, her own list and her calendar arrive later, by band and by your choice.</p>',"",1);
  var r=K.card('<span class="g2-eb">Next birthday</span><p class="g2-lead">Ivy turns 6 on Dec 9. That is 32 days away.</p><p class="g2-sub">Her band stays 5 to 7, so her home does not change. One quiet line appears: “3 sleeps until your birthday” in her last week.</p>',"tint",3)+
   K.card('<h4>By area</h4><p class="g2-fine">Each area follows her band unless you set it.</p>'+row({ic:"book",title:"Reading and words",sub:"One band up: words beside pictures",go:true,n:4})+row({ic:"dice",title:"Games",sub:"Follows her band",go:true})+row({ic:"chat",title:"Messages",sub:"Follows her band",go:true})+row({ic:"calendar",title:"Calendar and weeks",sub:"Held at 5 to 7",go:true}))+
   K.card(row({ic:"hourglass",title:"Hold until I have told her",sub:"When she moves to a new band, nothing changes on her side until you release it.",trail:K.toggle(true),n:5}));
  return two(c,l,r,"Age bands",{eyebrow:"Ivy"});}});

function stepHead(i,t){return K.card('<div class="g2-steps">'+[1,2,3,4].map(function(n){return '<i class="'+(n<=i?"f":"")+'"></i>';}).join("")+'</div><p style="margin:10px 0 0;font:800 17px/1.2 var(--font-display);color:var(--ink)">Step '+i+' of 4: '+E(t)+'</p>',"flat");}
D("r2FamilyBuilder","guardian","Family structure: people",{grp:"R2 Ages",since:"new",isNew:true,wide:true,
 desc:"Step 1 of the builder: who is in her life, under the name she uses. Any guardian can edit this alone; the other guardian sees every change.",
 notes:[[1,"Four steps: people, homes, rhythm, then a preview before anything reaches her."],[2,"Each person shows the name Ivy uses, never a role word. Roles live in the background."],[3,"How they reach her decides which buttons she sees by their face."],[4,"On a tablet the right pane edits the selected person."],[5,"Nothing here reaches Ivy until the preview step."]],
 r:function(c){
  var people=K.card(row({av:pav("Mom",42),title:"Mom",sub:"Guardian · Mom’s house · calls and messages",go:true})+row({av:pav("Dad",42),title:"Dad",sub:"Guardian · Dad’s house · calls and messages",go:true})+row({av:pav("Dana",42),title:"Dana",sub:"Dad’s partner · Dad’s house · messages",go:true,n:3})+row({av:pav("Grandma",42),title:"Grandma",sub:"Relative · near and far · calls",go:true}),"",2)+K.btn("Add someone",{kind:"tonal",full:true,ic:"plus"});
  var l=stepHead(1,"Who is in her life")+K.banner("pri","You can change this on your own. Dad sees every change. Ivy sees only what you release.","eye",5)+people+K.btn("Next: homes",{full:true,size:"lg",ic:"arrowR",n:1});
  var edit=K.card('<span class="g2-eb">Editing Dana</span>'+K.field("The name Ivy uses","Dana")+'<div style="height:10px"></div>'+K.field("Role","Dad’s partner")+'<div style="height:10px"></div>'+K.field("Home","Dad’s house",{ic:"home"})+'<div style="height:10px"></div><h5>How Dana reaches Ivy</h5><div class="g2-stack" style="margin-top:8px">'+opt("Messages","A message button beside her face",true)+opt("Live calls","A call button beside her face",false)+opt("A weekly story","One story slot a week",false)+'</div>')+K.card(row({ic:"hourglass",title:"Away for a while",sub:"Not away",trail:K.toggle(false)}));
  if(c.form==="tablet")return gt("Family structure",{eyebrow:"Ivy"})+'<div class="tw g2"><div>'+l+'</div><div>'+edit+'</div></div>';
  return gt("Family structure",{eyebrow:"Ivy"})+pg(l);}});

D("r2FamilyHomes","guardian","Family structure: homes and rhythm",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"Step 2 and 3: the homes and who sleeps where, then the weekly rhythm. A rhythm set by a court order is shown as locked here.",
 notes:[[1,"One to four homes. Each lists who is there, so her weeks and packing follow."],[2,"The rhythm is summarised in a line and drawn as two weeks; the editor is its own screen."],[3,"If an order sets the rhythm, this row shows the lock instead of an edit arrow."]],
 r:function(){return gt("Family structure",{eyebrow:"Ivy"})+pg(stepHead(2,"Homes and rhythm")+
  K.card(row({ic:"home",title:"Mom’s house",sub:"Mom · Ivy sleeps here",go:true,n:1})+row({ic:"home",title:"Dad’s house",sub:"Dad, Dana · Ivy sleeps here",go:true})+row({ic:"plus",title:"Add a home",sub:"Up to four",go:true}))+
  K.card('<h4>Weekly rhythm</h4><p class="g2-sub" style="margin:0 0 10px">Alternating weeks. Exchange Sunday at 6 PM.</p>'+dayLabels()+wk("mmmmmmm")+'<div style="height:4px"></div>'+wk("ddddddd")+'<div style="height:10px"></div>'+legend()+'<div style="height:6px"></div>'+row({ic:"calendar",title:"Edit the rhythm",go:true,n:2}),"")+
  K.btn("Next: preview",{full:true,size:"lg",ic:"arrowR"})+K.btn("Back",{kind:"ghost",full:true}));}});

function previewBody(n){
 return K.card('<span class="g2-eb">The change</span><p class="g2-lead">Move from alternating weeks to 2-2-5-5.</p><p class="g2-sub">Ivy is with Mom Mon–Tue, Dad Wed–Thu, then five nights at each house in turn.</p>')+
  K.card('<div class="g2-pair"'+K.n(1)+'><div>'+mini("alt")+'<div class="g2-mcap">Now<small>Weeks</small></div></div><span class="ar">'+I("arrowR",18,2)+'</span><div>'+mini("p2255",true)+'<div class="g2-mcap">After<small>Weeks</small></div></div></div>');}
D("r2ChangePreview","guardian","What Ivy will see",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"Her screens before and after, then when it reaches her. The default for a big change is to hold it until a guardian has told her.",
 notes:[[1,"Before and after are her real screens, drawn small. Look at what she will actually see."],[2,"Three timing choices. Hold is the default for big changes and says why."],[3,"A date is a promise to the calendar; she is told on that day, not before."],[4,"A picture story can travel with the change. It is opt-in and reviewed by you."],[5,"The button says exactly what will happen. Dad sees the change when you save, whichever timing you pick."]],
 r:function(){return gt("What Ivy will see",{eyebrow:"Before you save"})+pg(previewBody()+
  '<div class="g2-stack"'+K.n(2)+'>'+opt("Now","Her screens change as soon as you save.",false)+opt("Hold until I have told her","Her view stays the same. You release it when you have talked. Recommended for big changes.",true,{n:0})+opt("On a date","Her screens change on the day you pick.",false,{n:3,trail:""})+'</div>'+
  K.field("Date, if you pick one","Sat, Nov 21",{ic:"calendar"})+
  K.card(row({ic:"book",title:"Add a picture story",sub:"A short story, 4 pages, that you review first",trail:K.toggle(true),n:4}))+
  K.btn("Save and hold",{full:true,size:"lg",ic:"hourglass",n:5})+note1("Dad sees this change when you save. Nothing reaches Ivy until you release it."));}});
D("r2PreviewLoading","guardian","What Ivy will see: loading",{grp:"R2 Ages",since:"new",isNew:true,desc:"The preview is drawn from her real rules, which takes a moment. The change stays a draft meanwhile.",
 notes:[[1,"Still, calm placeholders. Nothing loops or shimmers."],[2,"The draft is safe to leave. Nothing has reached Ivy."]],
 r:function(){return gt("What Ivy will see",{eyebrow:"Before you save"})+pg(K.banner("info","Drawing Ivy’s screens. Nothing has reached her.","clock",1)+
  K.card('<div class="g2-pair"><div><div class="g2-sk l"></div><div class="g2-sk" style="margin-top:8px;width:60%;margin-left:auto;margin-right:auto"></div></div><span class="ar">'+I("arrowR",18,2)+'</span><div><div class="g2-sk l"></div><div class="g2-sk" style="margin-top:8px;width:60%;margin-left:auto;margin-right:auto"></div></div></div>')+K.card('<div class="g2-sk" style="width:70%"></div><div style="height:8px"></div><div class="g2-sk" style="width:90%"></div><div style="height:8px"></div><div class="g2-sk" style="width:55%"></div>')+K.btn("Leave it as a draft",{kind:"ghost",full:true,n:2}));}});
D("r2PreviewError","guardian","What Ivy will see: couldn’t load",{grp:"R2 Ages",since:"new",isNew:true,desc:"If the preview fails, the change is not applied and not lost.",
 notes:[[1,"Plain words: what failed, what is safe, what to do."],[2,"One primary action. Saving without a preview is not offered for big changes."]],
 r:function(){return gt("What Ivy will see",{eyebrow:"Before you save"})+pg(K.banner("bad","We couldn’t draw the preview. Check your connection and try again.","warn",1)+
  K.card('<h4>Your change is a draft</h4><p>Ivy sees nothing different. Dad has not been told yet. The draft is kept on this phone.</p>')+K.btn("Try again",{full:true,size:"lg",ic:"refresh",n:2})+K.btn("Close and keep the draft",{kind:"ghost",full:true}));}});

function hist(a,who,txt,when,chip,sub){return '<div class="it">'+pav(who,38)+'<div class="tx"><b>'+txt+'</b><small>'+when+(sub?" · "+sub:"")+'</small><span>'+chip+'</span></div></div>';}
D("r2ChangeHistory","guardian","Family change history",{grp:"R2 Ages",since:"new",isNew:true,wide:true,
 desc:"An append-only record of every change to her family structure: who, what, when, and when she was told. Nothing is edited or deleted; an undo is a new entry.",
 notes:[[1,"The rule is stated before the list, as in the shared handover log."],[2,"Every entry names the person, the change and when it took effect."],[3,"“Told Ivy” is a date a guardian recorded, not something the app guessed."],[4,"An undo is a new entry. The original stays."],[5,"A court order is shown as such and cannot be changed here."]],
 r:function(c){
  var l=K.banner("warn","This list can’t be edited or deleted. Both guardians see the same entries.","lock",1)+K.seg(["All","People","Rhythm","Homes"],0);
  var r=K.card('<div class="g2-tl"'+K.n(2)+'>'+
   hist(0,"Dad","Dad changed the rhythm to 2-2-5-5","3 days ago",K.chip("Held until told",{tone:"warn",sm:true}),"")+
   hist(0,"Mom","Mom undid “Dana, calls and messages”","3 weeks ago",K.chip("New entry; the first stays",{sm:true}),"")+
   hist(0,"Dad","Dad added Dana to Ivy’s people","3 weeks ago",K.chip("Told Ivy Oct 12",{tone:"ok",sm:true}),"")+
   hist(0,"Mom","Mom set the play window to 3:30 to 7:00 PM","2 months ago",K.chip("Applied",{tone:"ok",sm:true}),"")+
   hist(0,"Mom","Weekly rhythm set by court order","Sample date",K.chip("Locked by order",{tone:"info",sm:true}),"")+'</div>');
  return two(c,l,r,"Family history",{eyebrow:"Ivy"});}});
D("r2HistoryEmpty","guardian","Family change history: empty",{grp:"R2 Ages",since:"new",isNew:true,desc:"Before any change, the history says what it will hold and why it is permanent.",
 notes:[[1,"An empty state that teaches: what appears here and who sees it."]],
 r:function(){return gt("Family history",{eyebrow:"Ivy"})+pg(K.banner("warn","This list can’t be edited or deleted. Both guardians see the same entries.","lock")+K.card(K.empty("users","No changes yet","Every change to her people, homes and rhythm will appear here, with who made it and when she was told."),"",1)+K.btn("Start with her people",{kind:"tonal",full:true,ic:"plus"}));}});

/* ============================================================== CARE ===== */
function schedBody(locked){
 var rows=locked?
  K.banner("info","The weekly rhythm is set by a court order. It is shown here, and it can’t be edited in Olive Branch.","lock",1)+
  K.card('<span class="g2-eb">Weekly rhythm · locked</span>'+dayLabels()+wk("mmmmmmm","lk")+'<div style="height:4px"></div>'+wk("ddddddd","lk")+'<div style="height:10px"></div>'+legend()+'<p class="g2-fine" style="margin-top:10px">Set by order, sample date. Exchange Sunday 6 PM at school pickup.</p>',"",2)+
  '<div class="g2-stack">'+opt("Alternating weeks","Set by court order",true,{lk:true,trail:I("lock",16,2)})+'</div>'
 :
  K.card('<span class="g2-eb">Weekly rhythm</span>'+dayLabels()+wk("mmmmmmm")+'<div style="height:4px"></div>'+wk("ddddddd")+'<div style="height:10px"></div>'+legend(),"",2)+
  '<div class="g2-stack"'+K.n(1)+'>'+opt("Alternating weeks","One week at each house",true)+opt("2-2-5-5","Two, two, then five nights each",false)+opt("Build my own","Choose each night",false)+'</div>';
 return rows+K.field("Exchange","Sunday 6:00 PM · school pickup",{ic:"swap"})+
  K.sectionLabel("Holidays")+K.card(row({ic:"sun",title:"Winter break",sub:"Split in half. Mom first, 7 nights.",go:true,n:3})+row({ic:"leaf",title:"Spring break",sub:"Follows the weekly rhythm",go:true}))+
  K.sectionLabel("One-off exceptions")+K.card(row({ic:"calendar",title:"Dec 24, with Mom",sub:"One night only",go:true,n:4})+row({ic:"plus",title:"Add an exception",go:true}));}
D("r2Schedule","guardian","Custody schedule",{grp:"R2 Care",since:"new",isNew:true,
 desc:"The weekly rhythm, holidays and one-off exceptions. Her weeks and sleeps follow this, in her words.",
 notes:[[1,"Common patterns first; a custom build is available."],[2,"Two weeks drawn out, so the pattern is visible, with a legend for colour and letter."],[3,"Holidays override the rhythm and say how."],[4,"An exception is one night, named."],[5,"Ivy sees her weeks, never percentages or a “custody split”."]],
 r:function(){return gt("Weekly rhythm",{eyebrow:"Ivy’s weeks"})+pg(schedBody(false)+K.btn("Save rhythm",{full:true,size:"lg",n:5}));}});
D("r2ScheduleLocked","guardian","Custody schedule: set by court order",{grp:"R2 Care",since:"new",isNew:true,
 desc:"When a court order sets the rhythm, it is displayed as set by order and the editor is closed. Holidays and exceptions follow the order’s own terms.",
 notes:[[1,"The lock is stated in words first; the order wins over any edit."],[2,"The pattern is hatched as well as locked, so it does not rely on colour or an icon alone."],[3,"Holidays can only change if the order lets them. A guardian sees what is open and what is not."],[4,"Exceptions are a separate, mutual agreement, not an edit of the order."]],
 r:function(){return gt("Weekly rhythm",{eyebrow:"Ivy’s weeks"})+pg(schedBody(true)+K.btn("Ask Dad for a swap",{kind:"tonal",full:true,ic:"swap"})+note1("A swap is a one-off agreement between you. It does not change the order."));}});

D("r2SwapRequest","guardian","Swap request",{grp:"R2 Care",since:"new",isNew:true,
 desc:"Propose a swap, the other guardian accepts or declines, and the calendar changes only on acceptance. It lands in her weeks in her words.",
 notes:[[1,"Pick the nights and what you offer in return. Nothing changes yet."],[2,"The calendar shows what it would look like, before and after."],[3,"Nothing moves until Dad accepts. Ivy sees nothing before then."],[4,"After acceptance you choose how it reaches her, like any other change."]],
 r:function(){return gt("Ask for a swap",{eyebrow:"Ivy’s weeks"})+pg(
  K.card('<span class="g2-eb">You are asking</span><p class="g2-lead">Ivy at Mom’s house on Fri Nov 27 and Sat Nov 28.</p><p class="g2-sub">Those are Dad’s nights. In return, Mom takes Fri Dec 4 and Sat Dec 5.</p>',"tint")+
  K.field("Nights to swap","Fri Nov 27 and Sat Nov 28",{ic:"calendar"})+K.field("In return","Fri Dec 4 and Sat Dec 5",{ic:"calendar"})+K.field("A note for Dad","",{ph:"Optional. A reason helps.",ic:"letter"})+
  K.card('<h4>How it lands</h4><div class="g2-stack" style="margin-top:8px"'+K.n(2)+'>'+[["Fri Nov 27 and Sat Nov 28","Dad’s house","Mom’s house"],["Fri Dec 4 and Sat Dec 5","Mom’s house","Dad’s house"]].map(function(x){return '<div><small class="g2-fine" style="display:block;margin-bottom:5px">'+x[0]+'</small><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><span class="chip">'+x[1]+'</span>'+I("arrowR",16,2)+'<span class="chip pri">'+x[2]+'</span></div></div>';}).join("")+'</div>',"")+
  K.banner("info","Nothing changes until Dad accepts. Ivy sees nothing before then.","hourglass",3)+K.btn("Send to Dad",{full:true,size:"lg",ic:"send",n:1}));}});
D("r2SwapRespond","guardian","Swap request: Dad’s reply",{grp:"R2 Care",since:"new",isNew:true,
 desc:"The other guardian’s side: accept, decline or suggest another night. Acceptance is what moves the calendar.",
 notes:[[1,"The ask, the offer and the note are all on one card."],[2,"Both sit side by side at the same size. Declining needs no reason."],[3,"Accepting leads to the timing choice, the same one used for every change."]],
 r:function(){return gt("A swap from Mom",{eyebrow:"Ivy’s weeks"})+pg(
  K.card('<div class="row" style="padding:0">'+pav("Mom",42)+'<span class="rtxt"><b>Mom asks to swap two nights</b><small>Sent today, 6:10 PM</small></span></div><div style="height:10px"></div><div class="g2-quote" style="margin:0 0 10px">“Her recital is Friday at Mom’s end of town. Could she stay both nights?”</div><div class="kv"><span>Ivy at Mom’s</span><span>Fri Nov 27, Sat Nov 28</span><span>Ivy at Dad’s</span><span>Fri Dec 4, Sat Dec 5</span></div>',"",1)+
  '<div class="btns" style="gap:10px"'+K.n(2)+'>'+K.btn("Decline",{kind:"ghost",size:"lg"})+K.btn("Accept",{size:"lg"})+'</div>'+K.btn("Suggest other nights",{kind:"tonal",full:true,ic:"calendar"})+
  K.banner("info","If you accept, the calendar changes. Then you choose when Ivy sees it.","info",3));}});
D("r2SwapFailed","guardian","Swap request: couldn’t send",{grp:"R2 Care",since:"new",isNew:true,desc:"If a request can’t be sent, it is kept as a draft and nothing is pending on the other side.",
 notes:[[1,"Say what happened to the request, not just that something failed."],[2,"Try again is the one primary action. The calendar is untouched."]],
 r:function(){return gt("Ask for a swap",{eyebrow:"Ivy’s weeks"})+pg(K.banner("bad","We couldn’t send your request. You’re offline.","warn",1)+K.card('<h4>Saved as a draft</h4><p>Dad has not seen it. The calendar has not changed. Send it when you’re back online.</p><div class="kv" style="margin-top:8px"><span>Ivy at Mom’s</span><span>Fri Nov 27, Sat Nov 28</span><span>In return</span><span>Fri Dec 4, Sat Dec 5</span></div>')+K.btn("Try again",{full:true,size:"lg",ic:"refresh",n:2})+K.btn("Close and keep the draft",{kind:"ghost",full:true}));}});

D("r2MedEdit","guardian","Medication: add or edit",{grp:"R2 Care",since:"new",isNew:true,
 desc:"Add, change or retire a medication. Dose changes are shown to the other guardian and kept in history. Never a surface Ivy carries.",
 notes:[[1,"Between guardians only, stated first."],[2,"The log is a record of what was given. This app does not advise on doses."],[3,"A dose change is shown to Dad and kept, so both houses give the same dose."],[4,"Retiring stops reminders and keeps every past entry."]],
 r:function(){return gt("Edit medication",{eyebrow:"Meds and care"})+pg(
  K.banner("pri","Between guardians only. Ivy never sees this.","lock",1)+
  K.field("Name","Vitamin D")+K.field("Dose","1 tablet, 400 IU")+K.field("When","Daily with dinner",{ic:"clock"})+K.field("Kept at","Both houses. Travels in her bag.",{ic:"home"})+K.field("Prescribed by","Not prescription",{ic:"user"})+K.field("Note for the other house","",{ph:"For example, with food",ic:"letter"})+
  K.banner("info","If you change the dose, Dad sees it right away. Check dose changes with her doctor. This app doesn’t advise.","info",3)+
  K.btn("Save",{full:true,size:"lg",n:2})+K.btn("Retire this medication",{kind:"danger",full:true,ic:"hourglass",n:4}));}});
D("r2MedRetire","guardian","Medication: retire",{grp:"R2 Care",since:"new",isNew:true,desc:"Retiring a medication says plainly what stops and what stays.",
 notes:[[1,"Consequences first, each in one sentence."],[2,"Retire keeps the record; nothing is deleted."]],
 r:function(){return gt("Meds and care",{eyebrow:"Ivy"})+pg(K.card(row({ic:"pill",title:"Vitamin D",sub:"Daily with dinner",tone:"warn"})))+
  sh('<h4 style="font:800 20px var(--font-display);margin:0">Retire Vitamin D?</h4>'+li([["check","Reminders stop at both houses"],["check","Every past entry stays in the log"],["info","Dad is told today"]],"ok")+'<div class="btns"'+K.n(1)+'>'+K.btn("Keep it",{kind:"ghost"})+K.btn("Retire",{kind:"danger",n:2})+'</div>');}});

D("r2BagAdd","guardian","Exchange bag: add an item",{grp:"R2 Care",since:"new",isNew:true,
 desc:"Add something to her bag. It is either travelling with her or staying at one house, so nothing is forgotten in either direction.",
 notes:[[1,"Quick suggestions from past bags save typing."],[2,"Travels with her, or stays at one house. That decides where it is checked."],[3,"Both houses see the same bag. Ticking it off is shared."]],
 r:function(){return gt("Add to her bag",{eyebrow:"Exchange"})+pg(
  K.field("Item","Swim goggles",{ic:"list"})+'<div class="g2-fcs"'+K.n(1)+'>'+["Library book","Rain boots","Soft owl","Reading log"].map(function(t){return '<span class="g2-fc">'+E(t)+'</span>';}).join("")+'</div>'+
  '<div class="g2-stack"'+K.n(2)+'><h5 style="margin:4px 2px 0">Where it lives</h5>'+opt("Travels with her","Checked at every exchange",true)+opt("Stays at Dad’s house","Not checked at exchange",false)+opt("Stays at Mom’s house","Not checked at exchange",false)+'</div>'+
  K.card(row({ic:"bell",title:"Remind us when we pack",sub:"One reminder, at the exchange",trail:K.toggle(true)}))+K.btn("Add to bag",{full:true,size:"lg",ic:"plus",n:3}));}});

D("r2EmergencyCard","guardian","Emergency card: versions",{grp:"R2 Care",since:"new",isNew:true,
 desc:"The card stays a still, readable surface. Every change is a new version with who made it and when, and either guardian can see the earlier ones.",
 notes:[[1,"The current version is named at the top: number, who, when."],[2,"Large type, strong contrast, no motion. Unchanged from the earlier card."],[3,"Version history is a list, newest first. Nothing is overwritten."],[4,"Compare shows two versions side by side; restoring makes a new version."]],
 r:function(){return gt("Emergency card",{noBack:true,eyebrow:"Ivy"})+pg(
  K.card('<div class="row" style="padding:0">'+pav("Dad",38)+'<span class="rtxt"><b>Version 7</b><small>Changed by Dad, 3 days ago</small></span>'+K.chip("Current",{tone:"ok",sm:true})+'</div>',"flat",1)+
  K.card('<span class="g2-eb" style="color:var(--bad)">Allergies</span><p style="font:800 22px/1.15 var(--font-display);margin:0;color:var(--ink)"'+K.n(2)+'>Cashews. EpiPen in the front pocket of her backpack.</p>')+
  K.card(row({ic:"phone",title:"Mom",sub:"555-0142",trail:K.iconBtn("phone",{kind:"pri"})})+row({ic:"phone",title:"Dad",sub:"Message only until 9 AM",trail:K.iconBtn("phone",{kind:"tonal"})})+row({ic:"shield",title:"Dr. Okafor",sub:"555-0170",trail:K.iconBtn("phone",{kind:"tonal"})}))+
  K.sectionLabel("Earlier versions")+K.card(row({av:pav("Mom",36),title:"Version 6 · Mom",sub:"3 weeks ago · changed the doctor’s number",trail:K.btn("Compare",{kind:"ghost",size:"sm"}),n:4})+row({av:pav("Dad",36),title:"Version 5 · Dad",sub:"2 months ago · added insurance plan",trail:K.btn("Compare",{kind:"ghost",size:"sm"})}),"",3));}});
D("r2EmergencyConflict","guardian","Emergency card: two edits at once",{grp:"R2 Care",since:"new",isNew:true,
 desc:"When two guardians change the same line at once, neither is saved over the other. Both are shown and a guardian chooses.",
 notes:[[1,"Explains what happened in a sentence, without blame."],[2,"Both edits are shown as written, with who and when. No default is chosen for you."],[3,"A third option: write the value yourself."],[4,"Both edits stay in history. The chosen value becomes version 8."]],
 r:function(){return gt("Two changes to one line",{eyebrow:"Emergency card"})+pg(
  K.banner("warn","You and Dad both changed the insurance plan number from version 7. Pick the one to keep.","warn",1)+
  '<div class="g2-cmp"'+K.n(2)+'><div class="on"><small>Mom, 10:02 AM</small><b>4471-92</b><small>Was 4471-29</small></div><div><small>Dad, 10:04 AM</small><b>4471-82</b><small>Was 4471-29</small></div></div>'+
  '<div class="g2-stack">'+opt("Keep Mom’s: 4471-92","",true)+opt("Keep Dad’s: 4471-82","",false)+opt("Write another number","Use this if neither is right",false,{n:3})+'</div>'+
  K.banner("info","Both edits stay in the history. Call the clinic if you’re not sure which is right.","info",4)+K.btn("Save as version 8",{full:true,size:"lg"}));}});

/* ======================================================== PARENT LEARN === */
var LRN_BANNER=function(n){return K.banner("pri","Private to you. Dad and Ivy never see what you read, save or choose.","lock",n);};
function lcard(title,sub,kind,meta,n){return K.card('<h4 style="font-size:16px">'+E(title)+'</h4><p class="g2-sub" style="margin:2px 0 10px">'+E(sub)+'</p><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">'+ev(kind)+'<span class="g2-fine">'+E(meta)+'</span></div>',"",n);}
D("r2LearnHome","guardian","Learn home",{grp:"R2 Learn",since:"new",isNew:true,wide:true,
 desc:"Short, sourced cards for a guardian, private by default. Every card carries an evidence label and its sources. Nothing is scored, ranked or tracked.",
 notes:[[1,"Said first and kept in view: private to this guardian. The co-parent and the child never see it."],[2,"Filter by her age. Ivy’s band is chosen for you, and you can change it."],[3,"Every card shows how strong the evidence is, in words and a glyph, plus how long it takes to read."],[4,"Nothing is marked read, saved-count or completed. There are no streaks."],[5,"Tools are optional and each is private. They sit below the cards."]],
 r:function(c){
  var l=LRN_BANNER(1)+K.field("Search Learn","",{ph:"Try “bedtime” or “fighting”",ic:"search"})+
   '<div class="g2-fcs"'+K.n(2)+'>'+["All","3 to 4","5 to 7","8 to 12","13+"].map(function(t,i){return '<span class="g2-fc'+(i===2?" on":"")+'">'+t+'</span>';}).join("")+'</div>'+
   K.field("Evidence","Any strength",{ic:"sliders"})+
   lcard("Warmth and clear limits, together","The pairing the research supports most.","strong","3 min · 4 sources",3)+lcard("Explain the rule, then hold it","Say why once, calmly, then follow through.","moderate","3 min · 3 sources")+lcard("A calm time-out","About a minute for each year of age, then reconnect.","strong","2 min · 3 sources");
  var r=lcard("Emotion coaching at 5 to 7","Naming feelings changes what parents do. Child outcomes are less clear.","weak","3 min · 3 sources")+lcard("Styles are a map, not a label","Why labels travel badly between families and cultures.","contested","4 min · 4 sources")+lcard("Keep Ivy out of the middle","How parents handle conflict matters more than whether it happens.","strong","3 min · 3 sources")+
   K.sectionLabel("Tools, all optional")+'<div class="grid2"'+K.n(5)+'>'+K.tile("feat",{ic:"sliders",title:"Your choices"})+K.tile("feat",{ic:"target",title:"Where was today"})+K.tile("feat",{ic:"send",title:"Check before you send"})+K.tile("feat",{ic:"list",title:"Rules that match"})+'</div>';
  return two(c,l,r,"Learn",{eyebrow:"Parent Learn"});}});

D("r2LearnCard","guardian","Learn card",{grp:"R2 Learn",since:"new",isNew:true,
 desc:"One idea, in plain words, with its evidence label explained and its sources listed. It says what the research does not say, and it is not clinical advice.",
 notes:[[1,"The label comes with a sentence saying what it means for this card."],[2,"Each practice is something to do, not a type of parent to be."],[3,"“What it doesn’t say” is on every card, and always includes that style does not cause outcomes."],[4,"Sources are real, named and dated, so a guardian can check them. Sample list here; verify before release."],[5,"The footer is fixed: education, not clinical advice."],[6,"There is no share button. Saving is private."]],
 r:function(){return gt("Learn",{eyebrow:"Parent Learn",right:K.iconBtn("heart",{label:"Save privately",kind:"tonal",n:6})})+pg(
  '<h4 style="font:800 22px/1.15 var(--font-display);margin:0">Warmth and clear limits, together</h4><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"'+K.n(1)+'>'+ev("strong")+'<span class="g2-fine">3 min read · ages 5 to 7</span></div>'+
  K.card('<p>Strong here means many studies point the same way. It is still a link, not a cause, and most of it comes from Western samples.</p>',"flat")+
  K.card('<h5>What the research says</h5><p>Children tend to do well when adults are warm and also clear about what is expected. Warmth without limits, or limits without warmth, is linked to harder days for many families.</p><div style="height:6px"></div><h5>What it can look like at 5 to 7</h5>'+li([["check","Say the limit once, in a calm voice: “Shoes on, then we go.”"],["check","Name what you see: “You’re upset the game ended.”"],["check","Hold the limit, and stay kind while you do"]],"ok"),"",2)+
  K.card('<h5>What it doesn’t say</h5><p>It doesn’t say one style causes how a child turns out. A child’s temperament shapes how adults respond, and what a style means differs between families and cultures.</p>',"tint",3)+
  K.card('<h5>Sources</h5><div'+K.n(4)+'>'+[["Baumrind, 1966","Effects of authoritative parental control on child behavior","Primary paper"],["Darling and Steinberg, 1993","Parenting style as context: an integrative model","Review"],["American Academy of Pediatrics","Disciplining your child","Guidance, healthychildren.org"]].map(function(s){return '<div class="g2-src">'+I("file",18,1.9)+'<span><b>'+s[1]+'</b><small>'+s[0]+' · '+s[2]+'</small></span></div>';}).join("")+'</div>')+
  '<p class="g2-fine"'+K.n(5)+'>General education, not clinical advice. If you’re worried about Ivy’s behaviour, talk to her doctor.</p>');}});

D("r2LearnChoices","guardian","Parent Learn: your choices",{grp:"R2 Learn",since:"new",isNew:true,
 desc:"Every extra is optional and starts off or private. A guardian decides about reflection, framing, the message check and matching rules.",
 notes:[[1,"Each choice shows its default. Off and private are always the start."],[2,"Reflection has three levels. “Just for now” keeps nothing."],[3,"DECIDED by the owner: saved reflections live on this phone and in your account (both). Only you can read them. They are never in the court export and never shown to Dad. Backups do contain them today, so encrypting them is a build requirement."],[4,"Framing: practices (what you do) or climate (how it feels to a child). Never a label for a parent."],[5,"Deleting what you saved is one tap, and says what it removes."]],
 r:function(){return gt("Your choices",{eyebrow:"Parent Learn"})+pg(LRN_BANNER()+
  K.card('<h4>Reflection</h4><p class="g2-fine" style="margin:0 0 10px">A private check on how a day felt. Default: off.</p><div class="g2-stack"'+K.n(2)+'>'+opt("Off","No reflection prompts",false)+opt("Just for now","You see it, nothing is kept",true)+opt("Save privately","Kept on this phone and in your account, so a new phone can restore it. Only you can read it. Never exported, never shared.",false,{n:3})+'</div>',"",1)+
  K.card('<h4>How cards are framed</h4><div class="g2-stack" style="margin-top:8px"'+K.n(4)+'>'+opt("Practices","What you can do, in small steps",true)+opt("Climate","How things tend to feel for a child",false)+'</div>'+row({ic:"globe",title:"Add a culture note",sub:"What this can mean in your family’s culture",trail:K.toggle(true)}))+
  K.card(row({ic:"send",title:"Message check",sub:"Hints before you send to Dad. Default: off.",trail:K.toggle(false)})+row({ic:"list",title:"Rules that match",sub:"A short list for both homes. Default: off.",trail:K.toggle(false)}))+
  K.card(row({ic:"trash",title:"Delete what I saved",sub:"Removes saved notes on this phone and in your account. Can’t be undone.",go:true,n:5}),"flat"));}});

D("r2LearnToday","guardian","Where was today",{grp:"R2 Learn",since:"new",isNew:true,
 desc:"Two sliders and a mirror. It describes the day, not the person, and keeps nothing unless the guardian chose to save.",
 notes:[[1,"Two questions, in plain words. No numbers appear and no quadrant has a name."],[2,"The mirror describes today in a sentence. It never says what kind of parent you are."],[3,"A gentle optional idea, framed as something to try, never a correction."],[4,"The status line says what will happen to this reflection. Here: nothing is kept."]],
 r:function(){return gt("Where was today",{eyebrow:"Parent Learn"})+pg(
  K.card('<h4>How warm did the day feel?</h4><p class="g2-fine" style="margin:0 0 4px">Moments of closeness, comfort, play.</p>'+sl(72,"Less","More",1)+'<div style="height:10px"></div><h4>How many limits did you hold?</h4><p class="g2-fine" style="margin:0 0 4px">Bedtime, screens, “not today”.</p>'+sl(35,"Fewer","More"))+
  K.card('<span class="g2-eb">A mirror, not a grade</span><p class="g2-lead" style="font-size:17px"'+K.n(2)+'>Today had a lot of warmth and a few limits. Days move around, and this is one of them.</p><p class="g2-sub">One idea for tomorrow, if you want it: say one limit once, calmly, and keep it.</p>',"tint",3)+
  '<div style="display:flex;gap:8px;align-items:center"'+K.n(4)+'>'+priv("Not saved")+'<span class="g2-fine">This stays on your screen and is then gone.</span></div>'+K.btn("Done",{full:true,size:"lg",ic:"check"})+K.btn("Save privately instead",{kind:"ghost",full:true}));}});

D("r2LearnCheck","guardian","Check before you send",{grp:"R2 Learn",since:"new",isNew:true,
 desc:"Optional hints for a message to the other guardian. It shows patterns, never rewrites or sends, and stores nothing.",
 notes:[[1,"Your words, with the patterns marked. Nothing is changed for you."],[2,"Each hint says what the pattern can do, and one alternative you may use."],[3,"Send as it is stays one tap. This is a mirror, not a monitor."],[4,"The line states plainly what is and isn’t kept."]],
 r:function(){return gt("Check before you send",{eyebrow:"To Dad"})+pg(
  K.card('<span class="g2-eb">Your message</span><p class="g2-quote" style="margin:0"'+K.n(1)+'><span class="g2-mark">You never</span> read the reading log. Ivy was upset <span class="g2-mark">because of you</span> on Tuesday.</p>')+
  K.card('<h5>Two things you may want to look at</h5><div style="height:6px"></div>'+row({ic:"info",title:"“You never”",sub:"Words like never and always can start an argument. A single day is easier to answer.",n:2})+row({ic:"heart",title:"Ivy as the reason",sub:"Using her feelings to make a point can leave her in the middle.",tone:"info"})+'<div style="height:8px"></div><p class="g2-sub" style="margin:0"><b>One way to say it:</b> “Tuesday’s reading log wasn’t signed. Could we both check it at pickup?”</p>',"flat")+
  K.btn("Edit my message",{full:true,size:"lg",ic:"pencil"})+K.btn("Send as written",{kind:"ghost",full:true,ic:"send",n:3})+'<div style="display:flex;justify-content:center"'+K.n(4)+'>'+priv("Checked on this phone, nothing stored")+'</div>');}});

function rule(t,s){return row({title:t,sub:s});}
D("r2LearnRules","guardian","Rules that match",{grp:"R2 Learn",since:"new",isNew:true,wide:true,
 desc:"An optional short list in four core areas for each home. Each guardian edits only their own. Nothing is compared or scored.",
 notes:[[1,"Four core areas only: the ones where consistency has the better support."],[2,"My list is editable. It is saved to your account and visible to Dad only if you choose."],[3,"Dad’s list is read-only here. He edits his own copy."],[4,"No match percentage, no highlighted differences. Two lists, read by two people."]],
 r:function(c){
  var mine=K.card('<h4>My list</h4>'+row({ic:"moon",title:"Bedtime",sub:"Lights out 7:30 on school nights.",go:true,n:2})+row({ic:"tv",title:"Screens",sub:"None at meals. Off by 7:00.",go:true})+row({ic:"pencil",title:"Homework",sub:"Reading log signed before play.",go:true})+row({ic:"shield",title:"Safety",sub:"Helmet on every ride.",go:true}),"");
  var his=K.card('<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:2px"><h4 style="margin:0">Dad’s list</h4><span class="g2-priv">'+I("eye",12,2.2)+'Read only</span></div>'+row({ic:"moon",title:"Bedtime",sub:"Lights out 7:30 on school nights.",n:3})+row({ic:"tv",title:"Screens",sub:"One show after dinner.",})+row({ic:"pencil",title:"Homework",sub:"Done before dinner.",})+row({ic:"shield",title:"Safety",sub:"Helmet on every ride."}),"flat");
  var head=K.banner("pri","Optional. Four areas, one list per home. Nothing here is compared for you.","info",1);
  if(c.form==="tablet")return gt("Rules that match",{eyebrow:"Parent Learn"})+'<div class="tw g2"><div>'+head+mine+'</div><div>'+his+K.banner("info","Dad chose to share his list. He can stop at any time.","eye",4)+'</div></div>';
  return gt("Rules that match",{eyebrow:"Parent Learn"})+pg(head+mine+his+K.banner("info","Dad chose to share his list. Reading it doesn’t change either list.","eye",4));}});

/* ================================================================ CHILD == */
function ctile(ic,label,o){o=o||{};return '<div class="g2c-tile'+(o.hero?" hero":"")+'" role="button" aria-label="'+E(label)+'"'+K.n(o.n)+'>'+(o.extra?'<div style="display:flex;gap:14px;align-items:center"><span class="gi">'+I(ic,o.hero?44:36,1.8)+'</span>'+o.extra+'</div>':'<span class="gi">'+I(ic,o.hero?44:36,1.8)+'</span>')+'</div>';}
D("r2AgeHome34","child","Her home, ages 3 to 4",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"For the youngest band: no words to read, three big pictures. Every tile has a spoken name, and Dad’s face is on the call.",
 notes:[[1,"Her face and one speaker. No title to read."],[2,"The call is the biggest thing, with the face of the person she is calling."],[3,"Two more: stories and colour. Three tiles in all, and nothing moves."],[4,"Each tile speaks its own name when touched, and can be named to a screen reader."]],
 r:function(){return K.sb()+'<div class="top g2t" style="justify-content:space-between">'+K.avatar("I",{size:56,ring:true})+K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+'</div>'+cpg(
  ctile("video","Call Dad",{hero:true,n:2,extra:K.avatar("D",{size:64,tone:"accent"})})+'<div class="grid2"'+K.n(3)+'>'+ctile("book","Stories")+ctile("palette","Colour")+'</div>',{cls:"g2c34"});},
 cover:function(){return K.sb()+'<div class="top g2t" style="justify-content:space-between">'+K.avatar("I",{size:48,ring:true})+K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+'</div>'+cpg(ctile("video","Call Dad",{hero:true,extra:K.avatar("D",{size:56,tone:"accent"})})+'<div class="grid2">'+ctile("book","Stories")+ctile("palette","Colour")+'</div>',{cls:"g2c34"});}});

D("r2AgeHome57","child","Her home, ages 5 to 7",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"The home Ivy has now: pictures lead, every word can be heard, three tiers of tiles. Shown here so the three bands can be compared.",
 notes:[[1,"Her name and the day, as today."],[2,"One hero tile, four featured, then a quiet grid."],[3,"A quiet line appears only in her birthday week; no tile, no fanfare."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})})+cpg(
  K.card(K.dual({n:1})+'<div style="height:14px"></div>'+K.ribbon({now:31,overlap:[40,10]}),"hero")+K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Grandma’s",scene:"hills",n:2})+
  '<div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play together"})+K.tile("feat",{ic:"chat",title:"Messages"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>'+
  K.sectionLabel("More")+'<div class="grid3">'+[["pencil","Homework"],["users","My people"],["palette","Colour"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>');}});

D("r2AgeHome812","child","Her home, ages 8 to 12",{grp:"R2 Ages",since:"new",isNew:true,wide:true,
 desc:"Less cute, more capable: her own list, a calendar of her weeks, more games. Words sit beside the pictures.",
 notes:[[1,"A plain greeting. The next thing that matters is first."],[2,"Her calendar shows her weeks in her colours. No percentages, no labels."],[3,"Her own list arrives at this stage, as the wants and needs she keeps herself."],[4,"More games, in a quiet grid. The same rules hold: no scores, no streaks."]],
 r:function(c){
  var a=K.card('<span class="g2-eb">Next</span><p class="g2c-p" style="font-size:18px">Call with Dad at 3:00 PM</p><p class="g2-sub">In 2 hours, after school.</p>',"tint",1)+K.card('<h4>My weeks</h4>'+dayLabels()+wk("mmmmmdd")+'<div style="height:8px"></div>'+legend(),"",2);
  var b=K.card(row({ic:"list",title:"My list",sub:"Things I need · Things I want",go:true,n:3}))+K.sectionLabel("Games")+'<div class="grid3"'+K.n(4)+'>'+[["pawn","Chess"],["puzzle","Puzzles"],["dice","Dice"],["grid","Word grid"],["pencil","Draw"],["target","Code"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>';
  var tp=K.sb()+K.top({eyebrow:"Saturday",title:"Hey, Ivy",right:K.avatar("I",{size:42,ring:true})});
  if(c.form==="tablet")return tp+'<div class="tw g2 g2c"><div>'+a+'</div><div>'+b+'</div></div>';
  return tp+cpg(a+b);}});

D("r2MyPeople","child","My people",{grp:"R2 Ages",since:"new",isNew:true,wide:true,
 desc:"Her family as she knows it, drawn from the structure a guardian built. The names she uses, nothing else: no step, half or role words unless a guardian chose them.",
 notes:[[1,"Each home is a place with the people who are there, under the names she uses."],[2,"A video glyph means she can call; a speech glyph means she can send a message."],[3,"Anyone she is far from sits in their own place, with the same buttons."],[4,"A guardian can change this alone. She sees a change only when it is released to her."]],
 r:function(c){
  function per(n,mode,lbl){return '<div class="g2c-per" role="button" aria-label="'+E(lbl)+'">'+pav(n,52)+'<b>'+E(n)+'</b><span style="color:var(--ink3)">'+I(mode==="call"?"video":"chat",18,2)+'</span></div>';}
  var d='<div class="g2c-house d"><h4>'+I("home",22,2)+' Dad’s house</h4><div class="g2c-ppl">'+per("Dad","call","Call Dad")+per("Dana","msg","Message Dana")+'</div></div>';
  var g='<div class="g2c-house"'+K.n(3)+'><h4>'+I("heart",22,2)+' Near and far</h4><div class="g2c-ppl">'+per("Grandma","call","Call Grandma")+'</div></div>';
  var mm='<div class="g2c-house m"'+K.n(1)+'><h4>'+I("home",22,2)+' Mom’s house</h4><div class="g2c-ppl"'+K.n(2)+'>'+per("Mom","call","Call Mom")+'</div></div>';
  if(c.form==="tablet")return ctop("My people",{ns:1})+'<div class="tw g2 g2c"><div>'+mm+d+'</div><div>'+g+'</div></div>';
  return ctop("My people",{ns:1})+cpg(mm+d+g);}});

D("r2ChangeStory","child","Something is changing",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"A short picture story a guardian chose to release, after telling her. It is never a surprise, and she can leave it, listen again or ask a person a question.",
 notes:[[1,"It says who it is from. A guardian released it; the app did not decide."],[2,"One picture and two sentences per page, read aloud on request."],[3,"Four pages. The dots show where she is, nothing more."],[4,"Not now is always there and just closes it. Asking a question goes to a person."]],
 r:function(){return ctop("From Mom",{ns:2,eyebrow:"A story for you"})+cpg(
  '<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)"'+K.n(1)+'>'+K.scene("hills",300,170)+'</div>'+
  K.card('<p class="g2c-p"'+K.n(2)+'>Some weeks, you will sleep at Mom’s house for a few nights, then at Dad’s house for a few nights.</p>',"")+
  '<div class="g2c-pg"'+K.n(3)+'><i class="f"></i><i class="f"></i><i></i><i></i></div>'+K.btn("Next",{full:true,size:"lg",ic:"arrowR"})+'<div class="btns"'+K.n(4)+' style="gap:10px">'+K.btn("Not now",{kind:"ghost"})+K.btn("Ask",{kind:"tonal",ic:"chat"})+'</div>');},
 cover:function(){return ctop("From Mom",{noSpeak:true})+cpg('<div style="border-radius:24px;overflow:hidden">'+K.scene("hills",300,110)+'</div>'+K.card('<p class="g2c-p" style="font-size:17px">Some weeks, you will sleep at Mom’s house for a few nights, then at Dad’s.</p>')+K.btn("Next",{full:true,ic:"arrowR"}));}});

D("r2Birthday","child","Birthday countdown",{grp:"R2 Ages",since:"new",isNew:true,
 desc:"Sleeps until her birthday, said once and softly. Nothing to do, nothing to earn, no pressure.",
 notes:[[1,"One number, in her own unit: sleeps."],[2,"The date and the age she will be, said plainly."],[3,"No tasks, wishes, rewards or ticking. It is information, nothing more."],[4,"A guardian can hide it for the family, or in a hard year. She never sees an option."]],
 r:function(){return ctop("My birthday",{ns:1})+cpg(
  K.card('<div class="center" style="min-height:0;padding:14px 4px"><span class="g2c-big2" style="color:var(--pri)"'+K.n(1)+'>32</span><b class="g2c-big" style="font-size:24px">sleeps until your birthday</b></div>',"tint")+
  K.card('<p class="g2c-p" style="font-size:19px"'+K.n(3)+'>There is nothing to do. It will just come.</p>',"flat")+K.card(row({ic:"calendar",title:"December 9",sub:"You will be 6",n:2})));},
 cover:function(){return ctop("My birthday",{noSpeak:true})+cpg(K.card('<div class="center" style="min-height:0;padding:10px 4px"><span class="g2c-big2" style="color:var(--pri);font-size:64px">32</span><b class="g2c-big" style="font-size:20px">sleeps until your birthday</b></div>',"tint")+K.card(row({ic:"calendar",title:"December 9",sub:"You will be 6"})));}});
})();
