/* screens-r3-ages: Round 3, every age band of the child shell, the matching guardian views, the ladder, the 18 handover.
   All names are sample data (Ivy at various ages, Marcus = Dad, Jess = Mom, Grandma). Local parts use the r3a- prefix and theme variables only.
   Shells: "child" for 3-4, 5-7, 8-12 (kiosk, no settings). "teen" for 13-17 (same app, a different frame: dignity first, 48 dp targets, no mascot art). */
(function(){"use strict";var K=OB,I=K.ico,D=K.def,E=K.esc,n=K.n;

var CSS=[
".ob .r3a-top{display:flex;align-items:center;gap:10px;padding:8px 16px;min-height:60px}",
".ob .r3a-top .ttl{flex:1;min-width:0}",
".ob .r3a-top .ttl small{display:block;font:500 10.5px/1.2 var(--font-mono);letter-spacing:.07em;text-transform:uppercase;color:var(--ink3)}",
".ob .r3a-top .ttl b{display:block;font:800 22px/1.1 var(--font-display);letter-spacing:-.02em;overflow-wrap:anywhere}",
".ob.child .r3a-top .ttl b{font-size:26px}",
".ob.teen .r3a-top .ttl b{font-size:28px;letter-spacing:-.03em}",
".ob .r3a-b{width:48px;height:48px;border-radius:50%;border:1px solid var(--line);background:var(--surface);box-shadow:var(--shadow1);display:grid;place-items:center;color:var(--ink);flex:none;padding:0}",
".ob.child .r3a-b{width:64px;height:64px}",
".ob .r3a-eb{font:500 10.5px/1.2 var(--font-mono);letter-spacing:.07em;text-transform:uppercase;color:var(--ink3)}",
".ob .r3a-lead{font:800 19px/1.25 var(--font-display);letter-spacing:-.015em;margin:0;color:var(--ink)}",
".ob .r3a-p{font:400 14.5px/1.5 var(--font-body);color:var(--ink2);margin:0}",
".ob .r3a-p b{color:var(--ink)}",
".ob .r3a-fine{font:400 12.5px/1.45 var(--font-body);color:var(--ink3);margin:0}",
".ob.child .r3a-p{font-size:17px;color:var(--ink)}",
".ob .r3a-h5{font:800 15px/1.2 var(--font-display);margin:0;color:var(--ink)}",
".ob .r3a-tag{display:inline-flex;align-items:center;gap:5px;border-radius:99px;padding:3px 9px;font:500 10.5px/1.3 var(--font-mono);letter-spacing:.04em;background:var(--surface3);color:var(--ink2)}",
".ob .r3a-prop{display:inline-flex;align-items:center;border-radius:99px;padding:3px 9px;font:700 10.5px/1.3 var(--font-mono);letter-spacing:.05em;text-transform:uppercase;background:var(--warnC);color:var(--warn)}",
".ob .r3a-priv{display:inline-flex;align-items:center;gap:5px;border-radius:99px;padding:3px 9px;font:700 11.5px/1.3 var(--font-body);background:var(--okC);color:var(--ok)}",
".ob .r3a-gap{height:6px}",
".ob .r3a-st{display:grid;gap:10px}",
/* toddler */
".ob .r3a-tt{position:relative;display:grid;justify-items:center;align-content:center;gap:10px;border-radius:36px;min-height:180px;padding:16px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1);color:var(--pri);min-width:0}",
".ob .r3a-tt .pl{width:96px;height:96px;border-radius:34px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center}",
".ob .r3a-tt.a .pl{background:var(--accentC);color:var(--ink)}.ob .r3a-tt.i .pl{background:var(--infoC);color:var(--info)}.ob .r3a-tt.o .pl{background:var(--okC);color:var(--ok)}",
".ob .r3a-tt.hero{min-height:236px;background:linear-gradient(155deg,var(--hero1),var(--hero2));color:var(--onPri);border:0;box-shadow:var(--shadow2)}",
".ob .r3a-tt.hero .pl{background:rgba(255,255,255,.2);color:inherit;width:112px;height:112px;border-radius:40px}",
".ob .r3a-tt .spk{position:absolute;right:12px;top:12px;width:40px;height:40px;border-radius:50%;display:grid;place-items:center;background:color-mix(in srgb,var(--surface) 82%,transparent);color:var(--ink2)}",
".ob .r3a-tt.sm{min-height:150px;border-radius:30px}.ob .r3a-tt.sm .pl{width:78px;height:78px;border-radius:28px}",
".ob .r3a-tt.off{border-style:dashed;border-color:var(--edge)}",
".ob .r3a-tt.hero.off{outline:3px dashed rgba(255,255,255,.75);outline-offset:-9px}",
".ob .r3a-tt.scan{outline:6px solid var(--pri);outline-offset:3px}",
".ob .r3a-tt.hc{background:#fff;color:#111;border:4px solid #111}.ob .r3a-tt.hc .pl{background:#111;color:#fff}",
".ob .r3a-faces{display:flex;gap:10px;justify-content:center;align-items:center}",
".ob .r3a-strip{display:grid;position:relative;gap:6px}",
".ob .r3a-strip::before{content:\"\";position:absolute;left:calc(var(--dw,88px)/2 - 2.5px);top:44px;bottom:44px;width:5px;border-radius:5px;background:var(--surface3)}",
".ob .r3a-sti{display:flex;align-items:center;gap:16px;position:relative}",
".ob .r3a-sti .dot{width:88px;height:88px;border-radius:50%;display:grid;place-items:center;color:#18211c;flex:none;box-shadow:var(--shadow1);position:relative}",
".ob .r3a-sti.done{opacity:.5}",
".ob .r3a-sti.now .dot{outline:5px solid var(--pri);outline-offset:3px}",
".ob .r3a-sti .arw{margin-left:auto;color:var(--pri);flex:none}",
".ob .r3a-sti .wd{font:800 20px/1.15 var(--font-display);color:var(--ink);min-width:0;overflow-wrap:anywhere}",
".ob .r3a-sti .wd small{display:block;font:400 14px/1.3 var(--font-body);color:var(--ink2)}",
/* paint pots and canvas */
".ob .r3a-pots{display:flex;gap:10px;justify-content:center;flex-wrap:wrap}",
".ob .r3a-pot{width:64px;height:64px;border-radius:50%;border:4px solid var(--surface);box-shadow:var(--shadow1);flex:none}",
".ob .r3a-pot.on{outline:4px solid var(--ink);outline-offset:2px}",
".ob .r3a-cv{border-radius:30px;background:var(--surface);border:2px dashed var(--edge);min-height:210px;position:relative;overflow:hidden;display:grid;place-items:center}",
".ob .r3a-cv svg.sk{position:absolute;inset:0;width:100%;height:100%}",
/* rows of choice */
".ob .r3a-opt{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:20px;background:var(--surface);border:1.5px solid var(--outline);min-height:56px;min-width:0}",
".ob .r3a-opt.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .r3a-opt .rd{width:22px;height:22px;border-radius:50%;border:2px solid var(--edge);display:grid;place-items:center;flex:none;color:var(--onPri)}",
".ob .r3a-opt.on .rd{background:var(--pri);border-color:var(--pri)}",
".ob .r3a-opt .ot{display:grid;gap:2px;min-width:0;flex:1}.ob .r3a-opt b{font:700 15px/1.2 var(--font-body);overflow-wrap:anywhere}.ob .r3a-opt small{font:400 12.5px/1.35 var(--font-body);color:var(--ink2)}",
".ob .r3a-opt.on small{color:var(--onPriC)}",
/* age row (what you can see) */
".ob .r3a-ar{display:grid;gap:8px;padding:12px 0;border-top:1px solid var(--line)}",
".ob .r3a-ar:first-child{border-top:0}",
".ob .r3a-ar b{font:700 15px/1.25 var(--font-body)}.ob .r3a-ar small{display:block;font:400 12.5px/1.4 var(--font-body);color:var(--ink3);margin-top:2px}",
".ob .r3a-ac{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px}",
".ob .r3a-ac span{display:grid;justify-items:center;gap:3px;font:500 9.5px/1.2 var(--font-mono);color:var(--ink3);letter-spacing:.03em}",
".ob .r3a-v{width:34px;height:34px;border-radius:11px;display:grid;place-items:center}",
".ob .r3a-v.see{background:var(--infoC);color:var(--info)}.ob .r3a-v.ask{background:var(--warnC);color:var(--warn)}.ob .r3a-v.no{background:var(--surface3);color:var(--ink2)}.ob .r3a-v.own{background:var(--okC);color:var(--ok)}.ob .r3a-v.na{background:transparent;color:var(--ink3);border:1px dashed var(--edge)}",
".ob .r3a-leg{display:flex;flex-wrap:wrap;gap:6px 12px;font:400 12px/1.3 var(--font-body);color:var(--ink2)}",
".ob .r3a-leg span{display:inline-flex;align-items:center;gap:6px}.ob .r3a-leg .r3a-v{width:22px;height:22px;border-radius:7px}",
/* people-by-columns matrix (teen) */
".ob .r3a-mx{display:grid;grid-template-columns:minmax(0,1.5fr) repeat(var(--cols,3),minmax(40px,1fr));font-size:13px}",
".ob .r3a-mx>*{padding:9px 3px;border-top:1px solid var(--line);display:grid;align-items:center;min-width:0}",
".ob .r3a-mx .h{font:500 9.5px/1.2 var(--font-mono);text-transform:uppercase;letter-spacing:.04em;color:var(--ink3);justify-items:center;text-align:center;border-top:0}",
".ob .r3a-mx .lb{font-weight:700;overflow-wrap:anywhere}.ob .r3a-mx .lb small{display:block;font-weight:400;color:var(--ink3);font-size:11.5px;margin-top:1px}",
".ob .r3a-mx .c{justify-items:center}",
/* ladder / map */
".ob .r3a-lad{display:grid;gap:0;position:relative;padding-left:2px}",
".ob .r3a-ld{display:grid;grid-template-columns:44px minmax(0,1fr);gap:12px;position:relative;padding-bottom:14px}",
".ob .r3a-ld::before{content:\"\";position:absolute;left:21px;top:34px;bottom:-4px;width:2px;background:var(--line)}",
".ob .r3a-ld:last-child::before{display:none}",
".ob .r3a-ld .nd{width:44px;height:44px;border-radius:50%;display:grid;place-items:center;background:var(--surface2);color:var(--ink2);border:1.5px solid var(--outline);font:800 15px/1 var(--font-display);position:relative;z-index:1}",
".ob .r3a-ld.band .nd{background:var(--priC);color:var(--onPriC);border-color:transparent}",
".ob .r3a-ld.rung .nd{background:var(--accentC);color:var(--ink);border-color:transparent;border-radius:14px}",
".ob .r3a-ld.here .nd{background:var(--pri);color:var(--onPri);box-shadow:0 0 0 4px color-mix(in srgb,var(--pri) 25%,transparent)}",
".ob .r3a-ld.end .nd{background:var(--ink);color:var(--bg)}",
".ob .r3a-ld .bd{display:grid;gap:3px;min-width:0;padding-top:2px}",
".ob .r3a-ld .bd b{font:800 16px/1.2 var(--font-display);letter-spacing:-.01em}",
".ob .r3a-ld .bd span{font:400 13px/1.45 var(--font-body);color:var(--ink2)}",
".ob .r3a-ld .bd em{font-style:normal;font:500 10.5px/1.3 var(--font-mono);letter-spacing:.05em;text-transform:uppercase;color:var(--ink3)}",
/* before / after and diffs */
".ob .r3a-pair{display:grid;grid-template-columns:minmax(0,1fr) 26px minmax(0,1fr);gap:6px;align-items:center}",
".ob .r3a-pair .ar{display:grid;place-items:center;color:var(--ink3)}",
".ob .r3a-mini{border-radius:16px;background:var(--surface2);border:1px solid var(--line);padding:8px;display:grid;gap:6px;min-width:0}",
".ob .r3a-mini i{display:block;border-radius:9px;background:var(--surface3);height:20px}",
".ob .r3a-mini i.p{background:var(--priC)}.ob .r3a-mini i.h{height:42px;background:var(--pri)}.ob .r3a-mini i.s{height:12px;width:60%}.ob .r3a-mini .g{display:grid;grid-template-columns:1fr 1fr;gap:5px}.ob .r3a-mini .g3{display:grid;grid-template-columns:repeat(3,1fr);gap:4px}.ob .r3a-mini .g3 i{height:16px}",
".ob .r3a-cap{text-align:center;font:700 12.5px/1.25 var(--font-body);color:var(--ink);margin-top:5px}.ob .r3a-cap small{display:block;font-weight:400;color:var(--ink3)}",
".ob .r3a-chg{display:grid;gap:0}.ob .r3a-chg>div{display:grid;grid-template-columns:30px minmax(0,1fr);gap:10px;padding:10px 0;border-top:1px solid var(--line)}.ob .r3a-chg>div:first-child{border-top:0}",
".ob .r3a-chg .k{width:30px;height:30px;border-radius:10px;display:grid;place-items:center}",
".ob .r3a-chg .k.add{background:var(--okC);color:var(--ok)}.ob .r3a-chg .k.fade{background:var(--surface3);color:var(--ink2)}.ob .r3a-chg .k.keep{background:var(--infoC);color:var(--info)}.ob .r3a-chg .k.hers{background:var(--accentC);color:var(--ink)}",
".ob .r3a-chg b{font:700 14.5px/1.3 var(--font-body)}.ob .r3a-chg small{display:block;font:400 12.5px/1.4 var(--font-body);color:var(--ink3);margin-top:2px}",
/* ceremony (a rung or a birthday told to her) */
".ob .r3a-cer{border-radius:30px;padding:22px 18px;display:grid;gap:12px;justify-items:start;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow2)}",
".ob .r3a-cer .seal{width:68px;height:68px;border-radius:24px;display:grid;place-items:center;background:var(--priC);color:var(--onPriC)}",
".ob.child .r3a-cer{justify-items:center;text-align:center}",
".ob .r3a-cer h3{font:800 26px/1.1 var(--font-display);letter-spacing:-.025em;margin:0}",
".ob .r3a-big{font:800 76px/1 var(--font-display);letter-spacing:-.04em;color:var(--pri)}",
/* teen */
".ob.teen{--r-card:20px}",
".ob.teen .card{border-radius:20px}",
".ob .r3a-av{display:flex;align-items:center;gap:12px;min-width:0}",
".ob .r3a-ev{display:grid;grid-template-columns:4px minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 12px;border-radius:14px;background:var(--surface);border:1px solid var(--line)}",
".ob .r3a-ev i{align-self:stretch;border-radius:4px;background:var(--pri)}.ob .r3a-ev.b i{background:var(--accent)}.ob .r3a-ev.m i{background:var(--dpBed)}.ob .r3a-ev.w i{background:var(--dpMorning)}",
".ob .r3a-ev b{font:700 14.5px/1.25 var(--font-body)}.ob .r3a-ev small{display:block;font:400 12.5px/1.35 var(--font-body);color:var(--ink3)}",
".ob .r3a-now{display:flex;align-items:center;gap:10px;padding:14px;border-radius:20px;background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow1)}",
".ob .r3a-pill{display:inline-flex;align-items:center;gap:6px;border-radius:99px;padding:6px 12px;font:700 13px/1.2 var(--font-body);background:var(--surface3);color:var(--ink)}",
".ob .r3a-pill.on{background:var(--okC);color:var(--ok)}",
".ob .r3a-dm{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:12px 14px;border-radius:18px;background:var(--surface);border:1px solid var(--line)}",
".ob .r3a-dm b{font:700 14.5px/1.25 var(--font-body)}.ob .r3a-dm small{display:block;font:400 12.5px/1.35 var(--font-body);color:var(--ink3)}",
".ob .r3a-jr{border-radius:24px;padding:22px 18px;background:var(--surface);border:1px solid var(--line);display:grid;gap:10px;justify-items:center;text-align:center}",
".ob .r3a-jr .lk{width:76px;height:76px;border-radius:26px;background:var(--ink);color:var(--bg);display:grid;place-items:center}",
".ob .r3a-lines{display:grid;gap:7px;padding:14px;border-radius:18px;background:var(--surface2)}.ob .r3a-lines i{height:9px;border-radius:5px;background:var(--surface3)}.ob .r3a-lines i:nth-child(2){width:84%}.ob .r3a-lines i:nth-child(3){width:62%}",
".ob .r3a-cloud{display:inline-flex;align-items:center;gap:6px;border-radius:99px;padding:5px 10px;background:var(--surface3);color:var(--ink2);font:700 12px/1.2 var(--font-body)}",
".ob .r3a-oq{display:grid;gap:8px;padding:12px 14px;border-radius:18px;background:var(--surface2);border:1px dashed var(--edge)}",
".ob .r3a-ph{border-radius:20px;background:var(--surface2);border:1px solid var(--line);padding:12px;display:grid;gap:8px}",
".ob .r3a-tp{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}",
".ob .r3a-tp>div{border-radius:16px;padding:12px 8px;text-align:center;background:var(--surface);border:1.5px solid var(--outline);font:700 13.5px/1.25 var(--font-body);display:grid;gap:4px;justify-items:center}",
".ob .r3a-tp>div.on{border-color:var(--pri);background:var(--priC);color:var(--onPriC)}",
".ob .r3a-cr{position:relative;border-radius:24px;overflow:hidden;min-height:150px;display:grid;align-content:end;padding:16px;color:var(--onPri);background:linear-gradient(160deg,var(--hero2),var(--hero1));box-shadow:var(--shadow2)}",
".ob .r3a-cr b{font:800 22px/1.1 var(--font-display);letter-spacing:-.02em}.ob .r3a-cr small{font:400 13px/1.4 var(--font-body);opacity:.95}",
".ob .r3a-blur{filter:blur(5px);user-select:none}",
".ob .r3a-hs{border-radius:34px;padding:16px;display:grid;gap:12px;background:var(--priC);color:var(--onPriC)}",
".ob .r3a-hs.d{background:var(--accentC);color:var(--ink)}",".ob .r3a-hs.g{background:var(--surface2);color:var(--ink)}",
".ob .r3a-hp{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:10px}"
].join("\n");
(function(){if(document.getElementById("r3a-css"))return;var s=document.createElement("style");s.id="r3a-css";s.textContent=CSS;document.head.appendChild(s);})();

/* ------------------------------------------------------------------ helpers */
var GA="R3 Ages · Guardian",GP="R3 Ages · Privacy",GL="R3 Ages · Ladder",G34="R3 Ages · 3 to 4",G57="R3 Ages · 5 to 7",G812="R3 Ages · 8 to 12",G13="R3 Ages · 13 to 17",G18="R3 Ages · 18",GB="R3 Ages · Birthdays";
function X(grp,o){o.grp=grp;o.since="new";o.isNew=true;return o;}
function eb(t){return '<span class="r3a-eb">'+E(t)+'</span>';}
function tag(t){return '<span class="r3a-tag">'+E(t)+'</span>';}
function prop(){return '<span class="r3a-prop">Proposed</span>';}
function priv(t){return '<span class="r3a-priv">'+I("lock",12,2.2)+E(t||"Only you")+'</span>';}
function lead(t,nn){return '<p class="r3a-lead"'+n(nn)+'>'+t+'</p>';}
function p(t,nn){return '<p class="r3a-p"'+n(nn)+'>'+t+'</p>';}
function fine(t,nn){return '<p class="r3a-fine"'+n(nn)+'>'+t+'</p>';}
function h5(t,nn){return '<h5 class="r3a-h5"'+n(nn)+'>'+E(t)+'</h5>';}
function gap(){return '<div class="r3a-gap"></div>';}
function row(o){return K.row(o);}
function pav(nm,s,o){var m={Mom:["M",""],Dad:["D","accent"],Dana:["Da","accent"],Grandma:["G",""],Ivy:["I",""],Marcus:["M","accent"],Jess:["J",""],Leo:["L","accent"],Coach:["Co","info"]}[nm]||[nm.charAt(0),""];o=o||{};return K.avatar(m[0],{size:s||40,tone:m[1]||undefined,ring:o.ring,label:nm,status:o.status});}
function top(title,o){o=o||{};return K.sb()+'<div class="r3a-top">'+(o.noBack?(o.logo?K.logo(28):""):'<button type="button" class="r3a-b" aria-label="'+(o.home?"Home":"Back")+'"'+n(o.nb)+'>'+I(o.home?"home":"chevL",o.home?26:20,2)+'</button>')+'<div class="ttl">'+(o.eyebrow?'<small>'+E(o.eyebrow)+'</small>':"")+'<b>'+E(title)+'</b></div>'+(o.right||"")+'</div>';}
function sp(ns){return K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:ns});}
function ctop(title,o){o=o||{};return top(title,{home:o.home,noBack:o.noBack,eyebrow:o.eyebrow,nb:o.nb,right:o.noSpeak?(o.right||""):(o.right||"")+sp(o.ns)});}
function pg(inner,o){o=o||{};return K.page(inner,{cls:"r3a"+(o.cls?" "+o.cls:""),tab:o.tab||""});}
function gtabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],["sliders","Settings"]],a==null?3:a);}
function ttabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["calendar","Calendar"],["user","Me"]],a);}
function two(c,l,r,hd,tab,cls){if(c.form==="tablet")return hd+'<div class="tw r3a '+(cls||"")+'"><div>'+l+'</div><div>'+r+'</div></div>'+(tab||"");return hd+pg(l+r,{tab:tab,cls:cls});}
function ghd(t,o){return top(t,o);}
/* toddler tile: a picture, a spoken name (visually hidden) and a small speaker mark */
function tt(ic,name,o){o=o||{};return '<div class="r3a-tt'+(o.hero?" hero":"")+(o.cls?" "+o.cls:"")+'" role="button" tabindex="0" aria-label="'+E(name)+'"'+n(o.n)+'><span class="spk" aria-hidden="true">'+I("volume",18,2)+'</span><span class="pl">'+I(ic,o.isz||(o.hero?58:48),1.7)+'</span>'+(o.extra||"")+'<span class="sr-only" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)">'+E(name)+'</span></div>';}
/* her colour of the day as a fact, a small dot */
function sw(c){return '<i style="display:inline-block;width:12px;height:12px;border-radius:50%;background:'+c+';vertical-align:-1px"></i>';}
function opt(title,sub,on,o){o=o||{};return '<div class="r3a-opt'+(on?" on":"")+'"'+n(o.n)+'><span class="rd">'+(on?I("check",12,3.4):"")+'</span><span class="ot"><b>'+E(title)+'</b>'+(sub?'<small>'+E(sub)+'</small>':"")+'</span>'+(o.trail||"")+'</div>';}
function v(code,label){var m={see:["eye","Can see"],ask:["hand","Only if she says yes"],no:["lock","Cannot see"],own:["user","Only her"],na:["x","Not at this age"]}[code];return '<span class="r3a-v '+code+'" role="img" aria-label="'+E(label||m[1])+'">'+I(m[0],17,2)+'</span>';}
function legend(nn){return '<div class="r3a-leg"'+n(nn)+'>'+[["see","Can see"],["ask","Only if she says yes"],["no","Cannot see, ever"],["own","Hers alone"]].map(function(x){return '<span>'+v(x[0],x[1])+x[1]+'</span>';}).join("")+'</div>';}
function agerow(label,sub,codes,nn){var A=["3-4","5-7","8-12","13-17","18+"];return '<div class="r3a-ar"'+n(nn)+'><div><b>'+E(label)+'</b>'+(sub?'<small>'+E(sub)+'</small>':"")+'</div><div class="r3a-ac">'+codes.map(function(c,i){return '<span>'+v(c)+A[i]+'</span>';}).join("")+'</div></div>';}
function mx(cols,rows,nn){return '<div class="r3a-mx" style="--cols:'+cols.length+'"'+n(nn)+'><span class="h"></span>'+cols.map(function(c){return '<span class="h">'+E(c)+'</span>';}).join("")+rows.map(function(r){return '<span class="lb">'+E(r[0])+(r[1]?'<small>'+E(r[1])+'</small>':"")+'</span>'+r[2].map(function(c){return '<span class="c">'+v(c)+'</span>';}).join("");}).join("")+'</div>';}
function ld(kind,nd,title,sub,em,nn){return '<div class="r3a-ld '+kind+'"'+n(nn)+'><span class="nd">'+nd+'</span><div class="bd">'+(em?'<em>'+E(em)+'</em>':"")+'<b>'+title+'</b><span>'+sub+'</span></div></div>';}
function chg(rows,nn){return '<div class="r3a-chg"'+n(nn)+'>'+rows.map(function(r){var m={add:"plus",fade:"eyeoff",keep:"check",hers:"user"}[r[0]];return '<div><span class="k '+r[0]+'">'+I(m,15,2.2)+'</span><div><b>'+r[1]+'</b>'+(r[2]?'<small>'+r[2]+'</small>':"")+'</div></div>';}).join("")+'</div>';}
function mini(kind){var m={t:'<i class="h"></i><i class="p"></i><div class="g"><i></i><i></i></div>',a:'<i class="s"></i><i class="h"></i><div class="g"><i></i><i></i><i></i><i></i></div><div class="g3"><i></i><i></i><i></i></div>',b:'<i class="s"></i><i class="p"></i><div class="g3"><i></i><i></i><i></i><i></i><i></i><i></i></div><i></i>',n:'<i class="s"></i><i></i><i></i><i></i><i class="p"></i>'}[kind]||"";return '<div class="r3a-mini" aria-hidden="true">'+m+'</div>';}
function cer(ic,eyebrow,title,body,extra,nn){return '<div class="r3a-cer"'+n(nn)+'><span class="seal">'+I(ic,34,1.7)+'</span>'+(eyebrow?eb(eyebrow):"")+'<h3>'+title+'</h3>'+(body?p(body):"")+(extra||"")+'</div>';}
function sheetOpts(rows){return '<div class="r3a-st">'+rows.join("")+'</div>';}

/* =========================================================================== GUARDIAN: THE JOURNEY, THE PLANNER */
D("r3a-map","guardian","Ages at a glance",X(GA,{wide:true,
 desc:"The whole childhood on one page: three bands of the child shell, a teen frame, six rungs of authority that move to her one at a time, and the day it all becomes hers. Written for the grown-up who is wondering what the app will be like when she is fifteen.",
 notes:[[1,"Four homes and one handover, drawn as a path. Ivy is marked; nobody is compared to anyone."],[2,"Rungs are squares, bands are circles. A band is how her home looks and is yours to time; a rung is authority and is fixed by her age."],[3,"The app gets quieter as she grows. By 17 it has withdrawn most of its scaffolding, and that is the measure of it working."],[4,"At 18 guardianship closes. She takes her data, keeps it as an archive, or both sides choose to stay in touch."]],
 r:function(c){
  var path=K.card(h5("Her path")+gap()+'<div class="r3a-lad">'+
   ld("band","3","3 to 4: three big pictures","No reading. Every tile speaks its own name. Targets are 180 dp.","Toddler home")+
   ld("band here","5","5 to 7: pictures and one word","Where Ivy is now (sample). Games for two, her colour, show and tell.","Current home",1)+
   ld("band","8","8 to 12: her weeks, her list","Words beside pictures, her own calendar view, longer games.","Growing home")+
   ld("rung","10","Her list becomes hers","Nobody edits or curates it first.","Rung")+
   ld("band","13","13 to 17: a teen frame","No mascot art, no voice-over, real messages and calendar.","Teen frame",2)+
   ld("rung","13","The journal locks, for good","Not you, not the other guardian, not a court order.","Rung")+
   ld("rung","14","She edits her own calendar","The send-time guard leaves her side. It stays on yours.","Rung")+
   ld("rung","15","She publishes her own free times","You are told once, warmly.","Rung",3)+
   ld("rung","16","She curates her archive","Hide things, tag eras, decide what belongs.","Rung")+
   ld("rung","17","She can export her own copy","Without asking anyone.","Rung")+
   ld("end","18","Everything is hers","Guardianship closes. She takes her data, keeps it, or both.","Handover",4)+'</div>');
  var side=K.card(h5("How to read this")+gap()+p("<b>Bands</b> change how her home looks. You choose when each one reaches her.")+gap()+p("<b>Rungs</b> move authority to her. They arrive at her age and nobody can lower one. Both guardians together can move one later, never earlier.",2)+gap()+fine("Sample data: Ivy, Jess, Marcus.")," ","")+
   K.btn("Open the planner",{kind:"tonal",full:true,ic:"calendar"});
  return two(c,path,side,ghd("Ages",{eyebrow:"Ivy"}),gtabs(3));}}));

D("r3a-planner","guardian","What changes at each age",X(GA,{wide:true,
 desc:"A planner, not a settings page: every change ahead of her, in order, with who decides its timing. Pick an age to see Ivy’s home as it will look then.",
 notes:[[1,"Preview as any age. The device frame below it is her screen, not yours."],[2,"Two kinds of change are kept apart on purpose: her home (your timing) and rungs (her age)."],[3,"Each row says what the change is called in her words, so you know what you are about to tell her."],[4,"Held changes wait for you. After a birthday passes, nothing happens until you release it."]],
 r:function(c){
  var l=K.segmented(["4","6","10","14","17"],2,{full:true,label:"Preview Ivy at age",n:1})+K.card('<div class="r3a-pair"><div>'+mini("a")+'<div class="r3a-cap">Now<small>5 to 7 home</small></div></div><span class="ar">'+I("arrowR",18,2)+'</span><div>'+mini("b")+'<div class="r3a-cap">At 10<small>8 to 12 home</small></div></div></div>',"")+
   K.notice({tone:"pri",title:"Your timing, not hers",text:"Her home never changes on a birthday by itself. You choose now, hold, or a date for each.",n:4});
  function pl(age,title,sub,kind,state,nn){return K.row({ic:kind==="rung"?"layers":"home",title:"At "+age+": "+title,sub:sub,go:true,n:nn,trail:state?K.chip(state,{tone:state==="Held"?"warn":(kind==="rung"?"info":"pri"),sm:true}):""});}
  var r=K.sectionLabel("Her home, your timing")+K.card(pl(8,"words and her weeks","8 to 12 home · Dec 9, 2027","home","Held",3)+pl(13,"a teen frame","Teen home · Dec 9, 2032","home","On a date")+"",""),r2="";
  r2=K.sectionLabel("Rungs, fixed by her age",null)+K.card(pl(10,"her list is hers","Told to her, not to you","rung","",2)+pl(13,"journal locked","Told to her, not to you","rung","")+pl(14,"her calendar","Told to her, not to you","rung","")+pl(15,"her free times","You are told once","rung","")+pl(16,"her archive","Told to her, not to you","rung","")+pl(17,"her own export","Told to her, not to you","rung",""))+
   K.btn("Add Marcus to this plan",{kind:"ghost",full:true,ic:"users"});
  return two(c,l,r+r2,ghd("What changes",{eyebrow:"Planner"}),gtabs(3));}}));

D("r3a-planner-8","guardian","At 8: what changes",X(GA,{
 desc:"One transition opened up: what arrives, what quietly fades, what stays exactly the same, and how it will be told to her. Before you choose a timing.",
 notes:[[1,"Her screens, before and after, drawn small. Look at what she will actually see."],[2,"Four kinds of change, each with its own mark: arrives, fades, stays, becomes hers."],[3,"How she is told: one picture page, read aloud on request, never a surprise."]],
 r:function(){return ghd("At 8",{eyebrow:"Ivy · sample"})+pg(
  K.card('<div class="r3a-pair"'+n(1)+'><div>'+mini("a")+'<div class="r3a-cap">Now<small>5 to 7</small></div></div><span class="ar">'+I("arrowR",18,2)+'</span><div>'+mini("b")+'<div class="r3a-cap">At 8<small>8 to 12</small></div></div></div>')+
  K.card(chg([["add","Her weeks, in her colours","A calendar of the next two weeks, house by house."],["add","Words beside pictures","Every tile keeps its picture and gains a word."],["fade","Sleeps counting","Fades at 11, not now. She can read a calendar."],["keep","Calling, stories, show and tell","Exactly where they are today."],["hers","Her list, from 10","Not yet. It is rung 10, and fixed by age."]],2))+
  K.card('<span class="r3a-eb">How she is told</span><p class="r3a-p" style="margin-top:6px">A short picture page from you: “Your home is growing with you.” It can be read aloud, and she can say “not now”.</p>',"tint",3)+
  K.btn("Choose when",{full:true,size:"lg",ic:"clock"})+K.btn("See her screens",{kind:"tonal",full:true,ic:"eye"}),{tab:gtabs(3)});}}));

D("r3a-timing","guardian","When she is told",X(GA,{
 desc:"The three timing choices for a change to her home. Hold is the default, because the best moment is the one a grown-up picks.",
 notes:[[1,"Now: her home changes at her next sign-in, and a picture page tells her."],[2,"Hold until I have told her: nothing changes for her. You release it when you are ready."],[3,"On a date: for a birthday, a school break, a move. She is told on that day, not before."],[4,"The other guardian sees what you chose when you save. Nobody can quietly pick a different one."],[5,"A rung never waits for this. Only the look of her home does."]],
 r:function(){return ghd("At 8",{eyebrow:"Ivy · sample"})+pg(K.card(row({ic:"home",title:"8 to 12 home",sub:"Words and her weeks"}),"")+K.bottomSheet({title:"When is she told?",close:true,inner:sheetOpts([
  opt("Now","Her home changes the next time she opens it.",false,{n:1}),
  opt("Hold until I have told her","Nothing changes for her until you release it.",true,{n:2}),
  opt("On a date","Dec 9, 2027 · her birthday",false,{n:3,trail:'<span style="color:var(--ink3)">'+I("calendar",18,2)+'</span>'}),
  K.notice({tone:"info",text:"Marcus will see this choice when you save.",n:4}),K.card(fine("Rungs, such as her own list at 10, never wait for this. Only the look of her home does."),"flat",5)]),actions:K.btn("Save",{full:true,size:"lg"})+K.btn("Cancel",{kind:"ghost",full:true})}),{tab:gtabs(3)});}}));

D("r3a-held","guardian","Held, waiting for you",X(GA,{
 desc:"The day after a birthday, when you chose to hold. A calm reminder on Today: her home is exactly as it was, and you decide the moment.",
 notes:[[1,"One notice, once a day at most, never red."],[2,"Release it, pick a date, or keep holding. All three are one tap."],[3,"Her side shows nothing. She does not know there is a decision."],[4,"The other guardian sees the same notice, so neither of you holds it alone."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Saturday",title:"Today"})+pg(
  K.notice({tone:"pri",title:"Ivy turned 8 yesterday",text:"Her home is exactly as it was. Her new home is waiting for you to tell her.",n:1})+
  K.card(row({ic:"home",title:"8 to 12 home",sub:"Held since Dec 9",n:3})+row({ic:"users",title:"Marcus sees this too",sub:"Either of you can release it",n:4}))+
  '<div class="btns"'+n(2)+'>'+K.btn("Tell her now",{ic:"send"})+K.btn("Pick a date",{kind:"tonal",ic:"calendar"})+'</div>'+K.btn("Keep holding",{kind:"ghost",full:true})+
  K.card(row({ic:"calendar",title:"Marcus has Ivy tomorrow",sub:"Handover at 6:00 PM"})+row({ic:"pill",title:"Medication",sub:"Evening dose logged"})),{tab:gtabs(0)});}}));

/* =========================================================================== PRIVACY CONTRACT */
D("r3a-contract-g","guardian","What you can see, by age",X(GP,{wide:true,
 desc:"The privacy contract in plain words, as the guardian reads it. Five ages across, the things that matter down. The same contract is shown to her, and it is symmetrical: below it, what she can and cannot see of you.",
 notes:[[1,"Every row says one thing in one line. A grown-up should be able to read it aloud."],[2,"Each age shows the same four marks, with an icon as well as a tint, so colour is never the only signal."],[3,"The journal and her location are shut at every age. There is no override, no emergency tier and no court-order route."],[4,"From 15, availability is what she publishes. What was a model becomes her word."],[5,"The second half is the same contract about you. Fairness is the point."]],
 r:function(c){
  var l=K.card(h5("What you can see of Ivy")+gap()+legend(2)+gap()+
   agerow("Handovers, school and appointments you set","Yours to manage at every age.",["see","see","see","see","na"],1)+
   agerow("Her free times","A guess from school and bedtime, until she publishes her own at 15.",["see","see","see","see","na"],4)+
   agerow("Events she adds to her calendar","From 14 they are hers; she shares each one or none.",["na","na","na","ask","na"])+
   agerow("A message between her and one grown-up","Only those two read it. The other guardian sees that it arrived, not what it says.",["see","see","see","see","na"])+
   agerow("Her journal","Locked at 13, for good. No one can open it, ever.",["na","na","no","no","no"],3)+
   agerow("Where she is","Never. Not live, not on request.",["no","no","no","no","no"])+
   agerow("What she has hidden in her archive","From 16 the hiding is hers.",["na","na","na","no","no"])+"","");
  var r=K.card(h5("What Ivy can see of you")+gap()+p("The same contract, turned around.")+gap()+
   agerow("Your free times","Shown as a soft glow when you are free to talk.",["see","see","see","see","na"],5)+
   agerow("Your messages to her","Hers to keep, play and answer.",["see","see","see","see","na"])+
   agerow("Your messages with the other guardian","Never. Not a word.",["no","no","no","no","no"])+
   agerow("Money and expenses","Never, at any age.",["no","no","no","no","no"])+
   agerow("Where you are","Never. Not live, not on request.",["no","no","no","no","no"])+"","")+
   K.notice({tone:"info",text:"Anything the app tells you about her is something she can see you were told, from 13."});
  return two(c,l,r,ghd("The contract",{eyebrow:"Ivy · sample"}),gtabs(3));}}));

D("r3a-contract-c","teen","What your parents can see",X(GP,{wide:true,
 desc:"The same contract, in her words, on her screen. A teen frame: plain, symmetrical, with nothing hidden in a footnote. She reads it once at 13 and can open it whenever she wants.",
 notes:[[1,"It starts with what is hers. The first thing a teen reads is what nobody can see."],[2,"Three people across: Mom, Dad, Grandma. One row per thing. Each cell says it with an icon and a word for a screen reader."],[3,"The last line is the whole point: nothing here changes without her seeing it, in the consent log."],[4,"It is honest about what they do see. Hiding that would be the thing that makes a teen stop using the app."]],
 r:function(c){
  var l=K.card('<span class="r3a-priv">'+I("lock",12,2.2)+'Only you</span>'+gap()+lead("Your journal is yours. Where you are is yours.")+gap()+p("No one can open your journal: not Mom, not Dad, not us, not a court. We never ask your phone where you are.",1),"tint")+
   K.card(h5("Who can see what")+gap()+mx(["Mom","Dad","Gran"],[
    ["Messages you send to Mom","",["see","no","no"]],["Messages you send to Dad","",["no","see","no"]],["Your free times","What you publish.",["see","see","no"]],["Events you add","You choose each one.",["ask","ask","no"]],["Your journal","",["no","no","no"]],["Where you are","",["no","no","no"]],["Things you have hidden","In your archive.",["no","no","no"]]],2));
  var r=K.card(h5("What you can see of them")+gap()+p("The same rules, the other way. You never see Mom and Dad’s messages to each other, their money, or where they are. You do see when they are free to talk.",4))+
   K.card(row({ic:"receipt",title:"Your consent log",sub:"Every ask, every answer",go:true,n:3})+row({ic:"download",title:"Your data",sub:"What we keep, and how to take it",go:true}))+
   K.card(fine("Some things Mom and Dad set up for the whole family, such as handovers, school and appointments. They can see those, and so can you."),"flat");
  if(c.form==="tablet")return top("Privacy",{eyebrow:"Me"})+'<div class="tw r3a"><div>'+l+'</div><div>'+r+'</div></div>'+ttabs(3);
  return top("Privacy",{eyebrow:"Me"})+pg(l+r,{tab:ttabs(3)});}}));

D("r3a-consent-log","teen","Your consent log",X(GP,{wide:true,
 desc:"From 13 she co-governs her own data. Every request from a grown-up, every answer she gave, and every export, in order, with a way to take a standing yes back. A grown-up sees only that she answered, never why.",
 notes:[[1,"Four filters. The default is everything, newest first."],[2,"Each entry says who asked, for what, and what she answered. “Not this time” is a full answer."],[3,"A standing yes can be taken back with one tap, and it takes effect at once."],[4,"What the asker saw is written under each entry, so she knows exactly what the other side was told."]],
 r:function(c){
  function ent(ic,title,sub,ans,seen,nn,tone){return K.card('<div class="r3a-av"><span class="ricon">'+I(ic,20,1.9)+'</span><span class="rtxt" style="min-width:0"><b>'+E(title)+'</b><br><small style="color:var(--ink3)">'+E(sub)+'</small></span></div>'+gap()+'<div style="display:flex;flex-wrap:wrap;gap:6px 8px;align-items:center">'+K.chip(ans,{tone:tone||"",sm:true})+'<span class="r3a-fine">'+E(seen)+'</span></div>',"",nn);}
  var l='<div'+n(1)+'>'+K.filterChips(["Everything","Asked","Shared","Exports"],[0])+'</div>'+
   ent("eye","Dad asked to see Saturday plans","Today, 4:12 PM","You said: Once","Dad saw one event for one day.",2,"info")+
   ent("calendar","You shared “Dentist” with Mom","Oct 30","Standing yes","Mom sees it on the family calendar. Take it back anytime.",3,"ok")+
   ent("image","Mom asked to add a photo to the family album","Oct 3","You said: Not this time","Mom saw: “Ivy said not this time”. Nothing else.",4);
  var r=ent("download","You made your own copy","Sep 18","Export","Nobody was told. Exports are never reported to a grown-up.")+
   ent("clock","You turned on “Show my free times”","Sep 9, your 15th birthday","Yours","Jess and Marcus were told once, warmly.")+
   K.card(row({ic:"hand",title:"Pause all requests for a week",sub:"Grown-ups see a quiet “Ivy is taking a break from requests”. Nothing else.",go:true,trail:prop()}),"tint");
  if(c.form==="tablet")return top("Consent log",{eyebrow:"Privacy"})+'<div class="tw r3a"><div>'+l+'</div><div>'+r+'</div></div>'+ttabs(3);
  return top("Consent log",{eyebrow:"Privacy"})+pg(l+r,{tab:ttabs(3)});}}));

D("r3a-ask","guardian","Ask Ivy to share",X(GP,{
 desc:"The guardian side of the same contract. You can ask, with a reason in your own words. She can say yes once, yes for good, or not this time. You see her answer and nothing about why.",
 notes:[[1,"The thing you ask for is named plainly. There are no “monitoring” words in this app."],[2,"A reason, in your words, is required. She will read it exactly as you write it."],[3,"She can say no. The product never asks her to explain."],[4,"There is no way to ask again for a week. A no is an answer."],[5,"This is a request, never a requirement. There is no “make her” button anywhere."]],
 r:function(){return ghd("Ask Ivy",{eyebrow:"Ivy · 15, sample"})+pg(
  K.notice({tone:"info",title:"You are asking, not looking",text:"Ivy will see this, and answer in her own time.",n:5})+
  K.card(row({ic:"calendar",title:"Saturday plans",sub:"One event, one day",go:true,n:1}))+
  K.formField({label:"Why you are asking",value:"I want to plan around your cousin’s party.",req:true,n:2})+
  K.card(h5("She can answer")+gap()+'<div class="r3a-chiprow" style="display:flex;flex-wrap:wrap;gap:6px">'+K.chip("Yes, once",{tone:"ok",sm:true})+K.chip("Yes, from now on",{tone:"ok",sm:true})+K.chip("Not this time",{sm:true})+'</div>'+gap()+fine("You will see her answer. You will not see anything else.")+gap()+fine("If she says not this time, you cannot ask again for a week.")+"","",3)+
  K.btn("Send the request",{full:true,size:"lg",ic:"send",n:4}),{tab:gtabs(3)});}}));

/* =========================================================================== THE LADDER */
D("r3a-rungs","guardian","How each step is told",X(GL,{wide:true,
 desc:"The six rungs, side by side: what moves to her, how she is told, whether you are told, and that none can be lowered. Only the two rungs that change what you can see (15 and 18) notify you.",
 notes:[[1,"Nobody can lower a rung. Moving one later takes both guardians together, and is never offered for an earlier age."],[2,"Telling a parent that her journal is now permanently private would tell them something about her. So it is not told."],[3,"Rung 15 is told once, warmly, the day after. There is never a banner."]],
 r:function(c){
  function r1(age,what,her,you,nn){return K.card('<div style="display:flex;gap:10px;align-items:center;margin-bottom:6px"><span class="r3a-eb">Rung</span><b class="r3a-lead" style="font-size:22px">'+age+'</b></div><b style="font:700 15px/1.3 var(--font-body)">'+E(what)+'</b><br><small style="display:block;margin-top:6px;color:var(--ink2)">She is told: '+E(her)+'</small><small style="display:block;margin-top:2px;color:var(--ink2)">You are told: '+E(you)+'</small>',"",nn);}
  var l=r1("10","Her own list, uncurated","a quiet page and a first empty list","No")+r1("13","The journal locks, for good","one page, once","No",2)+r1("14","She edits her own calendar","a short how-to when she first adds","No");
  var rr=r1("15","She publishes her own free times","a page and a live preview of what you will see","Once, the next day",3)+r1("16","She curates her archive","a gentle page, no deadline","No")+r1("17","She can export her own copy","a page, once","No")+
   K.notice({tone:"pri",title:"Nobody can lower a rung",text:"Moving one later takes both of you, together, and is never offered for an earlier age.",n:1});
  return two(c,l,rr+K.card(row({ic:"lock",title:"Why most rungs do not tell you",sub:"Because telling you tells you about her.",n:2})),ghd("The ladder",{eyebrow:"Ivy"}),gtabs(3));}}));

D("r3a-rung10","child","Rung 10: your list",X(GL,{
 desc:"At about ten, her list is hers. This is how she is told: a page in her own frame, read aloud on request, with a first item she writes herself. Nothing is announced to anyone else.",
 notes:[[1,"A page, not a pop-up. It arrives where she already is, on the list tile, the first time she opens it."],[2,"The sentence says exactly what changes in plain words: nobody reads it before it is saved."],[3,"The first item is hers to write. Nothing is suggested."],[4,"No one is told. The rung changes who can write to a list, not what a grown-up can see."]],
 r:function(){return ctop("My list",{ns:1})+pg(cer("list","Yours now","Your list is yours.","Nobody checks it first. Nobody changes it. You decide what goes on it.",
  K.field("My first thing","",{ph:"Write something",ic:"pencil",n:3})+K.btn("Open my list",{full:true,size:"lg",ic:"arrowR"})+K.btn("Later",{kind:"ghost",full:true}),2),{cls:"r3a-c812"})+'<p class="r3a-fine" style="padding:0 16px" data-n="4">Nobody else is told.</p>';}}));

D("r3a-rung13","teen","Rung 13: your journal",X(GL,{
 desc:"At thirteen the journal locks absolutely. She is told in plain words, once, and that is all. No parent is told. The ladder never says out loud to a grown-up that a girl’s journal is now closed to them.",
 notes:[[1,"A lock, not a mascot. A teen frame never uses a cartoon where a symbol will do."],[2,"The sentence names who cannot open it, including the app and a court. It does not use the word “privacy”."],[3,"A real option: a backup that she makes and holds. It never goes to a parent."],[4,"Nobody else is notified. Not a banner, not a line in an email."]],
 r:function(){return top("Journal",{eyebrow:"Rung 13"})+pg(
  '<div class="r3a-jr"'+n(1)+'><span class="lk">'+I("lock",36,1.7)+'</span><h3 class="r3a-lead" style="font-size:24px">Your journal is locked, for good.</h3>'+p("No one can open it. Not Mom, not Dad, not us. Not a court.",2)+'</div>'+
  K.card(row({ic:"download",title:"Keep your own backup",sub:"Saved to your device only. We never send it to a grown-up.",go:true,n:3}))+
  K.btn("Open my journal",{full:true,size:"lg"})+K.btn("Not now",{kind:"ghost",full:true})+fine("Nobody is told that this happened.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{tab:ttabs(3)});}}));

D("r3a-rung14","teen","Rung 14: your calendar",X(GL,{
 desc:"At fourteen she edits her own calendar. She is told by an empty slot that is hers: tap and add. The send-time guard leaves her side; it stays on a parent’s side permanently.",
 notes:[[1,"The first time she opens the calendar: one line, one example, gone."],[2,"Her events are marked as hers. Whether a parent sees one is her call, per event."],[3,"She sees the house colours as facts: Mom’s week, Dad’s week."],[4,"No send-time guard on her side from now on. She knows what time it is where Dad lives."]],
 r:function(){return top("Calendar",{eyebrow:"Rung 14"})+pg(
  K.notice({tone:"pri",title:"This calendar is yours now",text:"Tap any day to add something. You choose whether anyone else sees it.",dismiss:true,n:1})+
  K.calMonth({today:8,sel:14,marks:{1:"a",2:"a",3:"a",4:"b",5:"b",6:"b",7:"b",9:"mix",14:"ev"},names:{a:"Mom’s",b:"Dad’s"},n:3})+
  K.card(row({ic:"plus",title:"Add to Saturday",sub:"Only you, or share it",go:true,n:2}))+K.card(fine("You know what time it is where Dad is, so Olive Branch does not remind you. It still tells him."),"flat",4),{tab:ttabs(2)});}}));

D("r3a-rung15","teen","Rung 15: your free times",X(GL,{
 desc:"The inversion. For ten years the app guessed when she was free. Now she says. She edits her windows and sees, live, exactly what her parents will see.",
 notes:[[1,"The first screen she sees after the page. Her windows, in her own words."],[2,"A live preview of what Mom and Dad will see: a soft glow when free, nothing when not. Never a reason."],[3,"She can change it any minute. Changes apply at once."],[4,"Free is never reported as “ignoring”. A parent sees a window, not a silence."]],
 r:function(){return top("Free times",{eyebrow:"Rung 15"})+pg(
  lead("You decide when you are free.")+p("Set your times. This is what Mom and Dad will see.")+
  K.card(h5("Your weekdays")+gap()+K.schedule([{s:7,e:8,title:"Before school",tone:"info"},{s:15.5,e:17,title:"Free",tone:"ok"},{s:19,e:21,title:"Free",tone:"ok"}],{from:7,to:22,hourH:26,now:null}),"",1)+
  K.card(h5("What they see")+gap()+'<div class="r3a-now"'+n(2)+'>'+pav("Ivy",36)+'<span class="rtxt"><b>Ivy is free from 7:00 PM</b><small>Tap to call or message</small></span>'+K.chip("Free",{tone:"ok",ic:"check",sm:true})+'</div>'+gap()+fine("They do not see why you are busy."))+
  K.btn("Save my times",{full:true,size:"lg",n:3})+fine("You can change this any minute.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{tab:ttabs(3)});}}));

D("r3a-rung15g","guardian","Ivy sets her own free times",X(GL,{
 desc:"The one note a guardian gets about rung 15, the day after, warmly. It states what changes for them and what does not, then never appears again. No banner, no reminder.",
 notes:[[1,"A card on Today, once. Not a banner, not a badge."],[2,"It says the truth: from now on you see her free times instead of a guess."],[3,"What stays the same is said as clearly as what changes."],[4,"Dismissing it removes it for good. Nothing returns it."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Wednesday",title:"Today"})+pg(
  K.notice({tone:"pri",title:"Ivy now sets her own free times",text:"She turned 15 yesterday. When you want to reach her, you will see the times she chose, not a guess.",dismiss:true,n:1})+
  K.card(chg([["hers","She decides when she is free","You see a soft glow when she is, and nothing when she is not."],["keep","You can still call","A call is always one tap."],["keep","Everything else is the same","Handovers, school, medication, your messages."]],2),"",3)+
  K.btn("Got it",{full:true,ic:"check",n:4})+K.btn("See what she sees",{kind:"tonal",full:true})+fine("This is the only time Olive Branch will mention it."),{tab:gtabs(0)});}}));

D("r3a-rung16","teen","Rung 16: your archive",X(GL,{
 desc:"At sixteen she curates the archive: hide things, tag eras, mute eras she does not want to meet by accident. Nothing is deleted; it simply stops being shown to anyone else.",
 notes:[[1,"Everything in the archive is hers to hide, one item or a whole era."],[2,"Eras are named by her, not by the app. “Before the move”, “the beach summer”."],[3,"Muting an era means it does not appear in any reminder, ever (P9)."],[4,"A hidden item is kept. She can bring it back, and nobody is told it was hidden."]],
 r:function(){return top("Archive",{eyebrow:"Rung 16"})+pg(
  K.notice({tone:"pri",title:"The archive is yours to shape",text:"Hide what you want, tag eras, decide what belongs.",dismiss:true,n:1})+
  K.card(h5("Eras")+gap()+row({ic:"image",title:"The beach summer",sub:"38 items · shown",trail:K.toggle(true,{label:"Show"}),n:2})+row({ic:"image",title:"Before the move",sub:"212 items · muted, no reminders",trail:K.toggle(false,{label:"Show"}),n:3}),"")+
  K.card(row({ic:"eyeoff",title:"Hidden",sub:"14 items only you can see",go:true,n:4})+row({ic:"plus",title:"Name a new era",go:true}))+fine("Nothing is deleted. Nobody is told what you hide."),{tab:ttabs(3)});}}));

D("r3a-rung17","teen","Rung 17: your own copy",X(GL,{
 desc:"At seventeen she can export her own data without asking anyone. This is that page, in plain words, with exactly what is in the copy and what is not.",
 notes:[[1,"Her copy is hers: a file on her device, in formats she can open anywhere."],[2,"A list of what is in it, with counts. Nothing is hidden in an “other” row."],[3,"What is not in it is just as clear: the other guardian’s messages, which are not hers."],[4,"Nobody is told she made a copy. Exports are never reported."]],
 r:function(){return top("Your own copy",{eyebrow:"Rung 17"})+pg(
  lead("You can take a copy of your data.")+p("No one has to say yes.")+
  K.card(h5("What is in it")+gap()+K.kv([["Messages you sent and received","1,204"],["Photos and drawings","386"],["Your calendar","All of it"],["Your journal","Yours only, encrypted"],["Letters to your future self","3"]],{ruled:true}),"",2)+
  K.card(h5("What is not")+gap()+fine("Messages between your parents, and anything they wrote about each other. Those are not yours."),"flat",3)+
  K.btn("Make my copy",{full:true,size:"lg",ic:"download",n:1})+fine("Nobody is told you made it.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{tab:ttabs(3)});}}));

/* =========================================================================== BIRTHDAYS, IN HER FRAME */
D("r3a-bd34","child","Birthday: from 4 to 5",X(GB,{
 desc:"The first change, drawn for a child who cannot read yet. A grown-up has chosen the moment (now, after telling her, or on a date). Her frame stays calm: one picture, a number she can count, and her new home.",
 notes:[[1,"Five dots to count. A numeral beside it, large, because she is starting to recognise them."],[2,"One new thing, shown, not announced. A soft marker, never a flash."],[3,"She is shown her new home by touching it. Her old home does not vanish."],[4,"There is no “you have unlocked”. A birthday is not a level."]],
 r:function(){return ctop("My birthday",{noBack:true,ns:1})+pg(
  '<div class="r3a-cer"'+n(1)+'><span class="seal">'+I("heart",36,1.7)+'</span><span class="r3a-big">5</span><div class="r3a-faces">'+[1,2,3,4,5].map(function(){return '<i style="width:18px;height:18px;border-radius:50%;background:var(--pri);display:block"></i>';}).join("")+'</div></div>'+
  '<div class="r3a-tt hero" style="min-height:150px"'+n(2)+'><span class="spk">'+I("volume",18,2)+'</span><span class="pl" style="width:84px;height:84px">'+I("book",40,1.7)+'</span></div>'+
  K.btn("Show me",{full:true,size:"lg",ic:"arrowR",n:3})+K.btn("Not now",{kind:"ghost",full:true,n:4}),{cls:"r3a-c34"});},
 cover:function(){return ctop("My birthday",{noBack:true,noSpeak:true})+pg('<div class="r3a-cer"><span class="seal">'+I("heart",30,1.7)+'</span><span class="r3a-big" style="font-size:60px">5</span></div>'+K.btn("Show me",{full:true,ic:"arrowR"}),{cls:"r3a-c34"});}}));

D("r3a-bd57","child","Birthday: from 7 to 8",X(GB,{
 desc:"Her home grows with her, told in her own frame. A short picture page from the grown-up who chose the moment, a plain list of what is new, and a real way to say not now.",
 notes:[[1,"It says who it is from. A grown-up chose the moment; the app did not decide."],[2,"What is new is a short list she can have read aloud. Pictures lead."],[3,"Nothing she loved is taken away without a line that says so."],[4,"Not now is a full answer; it waits for her."]],
 r:function(){return ctop("From Mom",{eyebrow:"You are 8",ns:1})+pg(
  '<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("day",300,150)+'</div>'+
  K.card('<p class="r3a-p"'+n(1)+'>Your home is growing with you. Here is what is new:</p>'+gap()+chg([["add","Your weeks","See where you sleep, week by week."],["add","Words with your pictures","Every picture has a word too."],["keep","Calling, stories, show and tell","Right where they were."]],2),"",3)+
  K.btn("Show me",{full:true,size:"lg",ic:"arrowR"})+K.btn("Not now",{kind:"ghost",full:true,n:4}),{cls:"r3a-c57"});}}));

D("r3a-bd13","teen","Birthday: you are 13",X(GB,{
 desc:"The most delicate one. No confetti, no mascot, no “you are a big kid now”. A plain page that says what is different, what is hers, and what she can read for herself. She can postpone looking; the changes themselves do not wait.",
 notes:[[1,"The first line is a fact, said once. No exclamation mark."],[2,"Three things, named. The journal is on the list because it is the biggest."],[3,"A real link to what her parents can see. She will not have to look for it."],[4,"Not today postpones looking at the page, not the change."]],
 r:function(){return top("You are 13",{noBack:true})+pg(
  lead("You are 13. A few things are different now.").replace("<p ",'<p data-n="1" ')+
  K.card(chg([["hers","Your journal is locked","Only you can open it."],["add","A different look","Calmer, plainer, with your own messages and calendar."],["add","See what your parents can see","It is a short list, and it is the same for them as for you."]],2))+
  K.card(row({ic:"eye",title:"What Mom and Dad can see",sub:"Read it now or later",go:true,n:3}))+
  K.btn("Take a look",{full:true,size:"lg"})+K.btn("Not today",{kind:"ghost",full:true,n:4}),{tab:ttabs(3)});}}));

/* =========================================================================== SHARED PIECES FOR THE BANDS */
function fc(kind,s){var m={happy:"M8.5 14c1 2.2 6 2.2 7 0",calm:"M9 15h6",sad:"M8.5 16.5c1-2.2 6-2.2 7 0",cross:"M8.5 16c1-1.6 6-1.6 7 0M7.5 7.5l3.2 1.6M16.5 7.5l-3.2 1.6",worry:"M9 15.6c1-1 5-1 6 0M8 8.6l2.8-1.2M16 8.6l-2.8-1.2"}[kind];
 return '<svg viewBox="0 0 24 24" width="'+s+'" height="'+s+'" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="9.6"/><circle cx="9" cy="10.4" r=".7" fill="currentColor"/><circle cx="15" cy="10.4" r=".7" fill="currentColor"/><path d="'+m+'"/></svg>';}
function sketch(){return '<svg class="sk" viewBox="0 0 300 210" preserveAspectRatio="xMidYMid meet" aria-hidden="true" focusable="false"><path d="M60 150c20-70 70-90 110-60s30 80 70 40" fill="none" stroke="var(--pri)" stroke-width="14" stroke-linecap="round"/><path d="M90 170c40 10 90 10 130-6" fill="none" stroke="var(--accent)" stroke-width="12" stroke-linecap="round"/><circle cx="210" cy="70" r="20" fill="var(--dpMorning)"/></svg>';}
function pots(on){var C=["var(--pri)","var(--accent)","var(--dpMorning)","var(--dpDay)","var(--dpAfternoon)","var(--dpBed)"];return '<div class="r3a-pots" role="radiogroup" aria-label="Colours">'+C.map(function(c,i){return '<span class="r3a-pot'+(i===on?" on":"")+'" role="radio" aria-checked="'+(i===on)+'" style="background:'+c+'"></span>';}).join("")+'</div>';}
function cloudNote(txt){return '<span class="r3a-cloud">'+I("cloud",14,2)+(txt?E(txt):"")+'</span>';}
function stateRow(ic,title,sub,chip,nn){return K.row({ic:ic,title:title,sub:(chip?chip.t+(sub&&sub!==chip.t?" \u00b7 "+sub:""):sub),go:true,n:nn});}

/* A guardian screen shows the matching view for a band: what the grown-up decides, in order. */
function gband(id,title,age,sub,rows,notes,extra){
 D(id,"guardian",title,X(GA,{desc:sub,notes:notes,r:function(c){var l=K.card(h5("What Ivy has")+gap()+rows[0],"",1),r=K.card(h5("What you decide")+gap()+rows[1],"",2);return two(c,l+(extra?extra.a:""),r+(extra?extra.b:""),ghd(title,{eyebrow:"Ivy · "+age+" · sample"}),gtabs(3));},wide:true}));}

/* =========================================================================== 3 TO 4 */
D("r3a-34-home","child","3 to 4: her home",X(G34,{wide:true,
 desc:"Three pictures and her own face. Nothing to read, nothing that counts, nothing that moves. Every tile says its own name when touched, and Dad’s face is on the call.",
 notes:[[1,"Her face and one speaker. No title, no clock."],[2,"The call is the biggest thing, with the face of the person she is calling. A small envelope shape says something has arrived; it is a shape, not a number."],[3,"Two more: stories and drawing. Three tiles in all."],[4,"Each tile has a small speaker mark and speaks its own name; it also has a name for a screen reader."]],
 r:function(c){
  var hd=K.sb()+'<div class="r3a-top" style="justify-content:space-between">'+K.avatar("I",{size:64,ring:true,label:"Ivy"})+sp(1)+'</div>';
  var call=tt("video","Call Dad",{hero:true,n:2,extra:'<div class="r3a-faces">'+pav("Dad",72,{ring:true})+'<span style="display:grid;place-items:center;width:40px;height:40px;border-radius:50%;background:rgba(255,255,255,.25)">'+I("mail",20,2)+'</span></div>'});
  var two2='<div class="grid2"'+n(3)+'>'+tt("book","Stories",{cls:"a",n:4})+tt("brush","Draw",{cls:"i"})+'</div>';
  if(c.form==="tablet")return hd+'<div class="tw r3a r3a-c34"><div>'+call+'</div><div>'+two2+'</div></div>';
  return hd+pg(call+two2,{cls:"r3a-c34"});},
 cover:function(){return K.sb()+'<div class="r3a-top" style="justify-content:space-between">'+K.avatar("I",{size:48,ring:true})+sp()+'</div>'+pg(tt("video","Call Dad",{hero:true,extra:pav("Dad",56,{ring:true})})+'<div class="grid2">'+tt("book","Stories",{cls:"a sm"})+tt("brush","Draw",{cls:"i sm"})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-msgs","child","3 to 4: something from Dad",X(G34,{
 desc:"A message is one picture she can press. Dad’s face, a big play, and two answers that need no words: a heart and a voice. If nothing has arrived there is simply nothing, never an empty-inbox message.",
 notes:[[1,"The face is the label. Whoever sent it, she knows by their face."],[2,"One big play. Nothing else on the screen competes with it."],[3,"A heart is a whole answer. A voice is another. Neither needs her to read or write."]],
 r:function(){return ctop("",{home:true,ns:1})+pg(
  '<div style="position:relative;border-radius:34px;overflow:hidden;box-shadow:var(--shadow2)"'+n(1)+'>'+K.scene("night",300,200)+'<span style="position:absolute;left:14px;top:14px">'+pav("Dad",64,{ring:true})+'</span><span style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:104px;height:104px;border-radius:50%;background:rgba(255,255,255,.95);display:grid;place-items:center;color:var(--priD)"'+n(2)+'>'+I("play",50,2)+'</span></span></div>'+
  '<div class="grid2"'+n(3)+'>'+tt("heart","Love it",{cls:"a sm"})+tt("mic","Say hi",{cls:"sm"})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-day","child","3 to 4: my day",X(G34,{
 desc:"Her day as a picture path. Each stop is a colour from the day (morning, day, afternoon, evening, bed), a picture of the thing and the face of who she is with. No clock, no numbers: where she is now has a ring, and the next thing has an arrow.",
 notes:[[1,"The colours are the same day-part colours as everywhere else in the app, so a child who learns them at three still knows them at ten."],[2,"A face under each stop says who is there. That is the answer to “who is picking me up?”."],[3,"A ring says now. Past stops are quieter; nothing ticks or fills as if it were a score."],[4,"The speaker reads the day aloud, in order, in a voice that is not anyone’s parent (P1)."]],
 r:function(){function st(cls,col,ic,face,nn){return '<div class="r3a-sti '+cls+'"'+n(nn)+'><span class="dot" style="background:'+col+'">'+I(ic,40,1.7)+'</span>'+(face?'<span class="wd">'+face+'</span>':"")+(cls==="now"?'<span class="arw">'+I("arrowR",32,2.2)+'</span>':"")+'</div>';}
  return ctop("",{home:true,ns:4})+pg('<div class="r3a-strip">'+st("done","var(--dpMorning)","sun",pav("Mom",56))+st("done","var(--dpDay)","puzzle","",1)+st("now","var(--dpAfternoon)","users",pav("Grandma",56),3)+st("","var(--dpEvening)","house",pav("Dad",56),2)+st("","var(--dpBed)","moon",pav("Dad",56))+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-play","child","3 to 4: play",X(G34,{
 desc:"Four things to play with, each with one rule she can see. No scores, no winning and no losing. Together-play is turns with Dad, shown as two faces, one lit.",
 notes:[[1,"Together play is the biggest tile: two faces, and the lit one is whose turn it is."],[2,"Find the thing: a picture is named aloud and she finds it among three. Nothing marks a wrong tap."],[3,"Colour sort and Kim’s game are in the repo as pictured activities; at this age they run with three pieces only."],[4,"No timer anywhere. A finished game just ends, and says it was a good one."]],
 r:function(){return ctop("",{home:true,ns:4})+pg(
  '<div class="r3a-tt hero" style="min-height:200px"'+n(1)+' role="button" tabindex="0" aria-label="Play with Dad"><span class="spk">'+I("volume",18,2)+'</span><div class="r3a-faces">'+pav("Ivy",64,{ring:true})+'<span style="opacity:.8">'+I("swap",30,2)+'</span>'+pav("Dad",64)+'</div><span class="pl" style="width:76px;height:76px">'+I("dice",38,1.7)+'</span></div>'+
  '<div class="grid2"'+n(2)+'>'+tt("search","Find the thing",{cls:"sm a"})+tt("palette","Colour sort",{cls:"sm",n:3})+tt("eye","Kim’s game",{cls:"sm i"})+tt("puzzle","Puzzle",{cls:"sm o"})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-make","child","3 to 4: draw",X(G34,{
 desc:"A fat brush, six colours, and a big keep. She cannot get lost: there is no menu, no layers and nothing to save as. Undo is one big picture.",
 notes:[[1,"Six paint pots. The one she is using has a ring; nothing else about it is a setting."],[2,"One brush size, chosen for small hands. No eraser, no menu."],[3,"Keep puts it in her collection and tells Dad it is there. She can send it with a heart."]],
 r:function(){return ctop("",{home:true,ns:1})+pg('<div class="r3a-cv"'+n(2)+'>'+sketch()+'</div>'+pots(0).replace('class="r3a-pots"','class="r3a-pots"'+n(1))+'<div class="grid2"'+n(3)+'>'+tt("undo","Undo",{cls:"sm",isz:40})+tt("check","Keep it",{cls:"sm o",isz:40})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-feel","child","3 to 4: when I need someone",X(G34,{
 desc:"Not a feelings chart. Three things she can ask for when she needs a person or a quiet minute: a hug from the grown-up in her house, a quiet corner, or her far-away parent. Nothing is recorded as a mood, and nothing is read about her.",
 notes:[[1,"“A hug please” is a request to the grown-up in the same house. It lands on that grown-up’s phone as a plain “Ivy would like you”."],[2,"The quiet corner is a picture and a slow voice. It has no meter, no cartoon face to match, and no “well done”."],[3,"Calling the far-away parent is always here, in the same place."],[4,"Nothing is logged as a feeling. A grown-up never sees a mood chart, because there is no mood data (§8.6.4)."]],
 r:function(){return ctop("",{home:true,ns:4})+pg(tt("heart","A hug please",{hero:true,n:1})+'<div class="grid2">'+tt("moon","Quiet corner",{cls:"sm i",n:2})+tt("video","Call Dad",{cls:"sm a",n:3})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-people","child","3 to 4: my people",X(G34,{
 desc:"Two houses, drawn as places, with the people who are there as big faces. Touch a face and she hears the name and can call. It is her family exactly as a guardian built it, with no role words.",
 notes:[[1,"Two places, two colours. Mom’s house is tinted, Dad’s is warm. Never the same shade in two houses."],[2,"A face is a button. Touch to hear the name, touch again to call."],[3,"Someone far away sits in their own place, with the same big face."],[4,"A guardian builds this. She sees a change only when it is released to her."]],
 r:function(c){function per(nm,nn){return '<div class="g2c-per" style="display:grid;justify-items:center;gap:6px;background:var(--surface);color:var(--ink);border-radius:26px;padding:14px 8px;min-height:140px;align-content:center" role="button" tabindex="0" aria-label="Call '+E(nm)+'"'+n(nn)+'>'+pav(nm,76)+'<span style="color:var(--pri)">'+I("video",28,2)+'</span></div>';}
  function hs(cls,ic,ppl,nn){return '<div class="r3a-hs '+cls+'"'+n(nn)+'><h4 style="margin:0;display:flex;gap:8px;align-items:center">'+I(ic,28,2)+'</h4><div class="r3a-hp">'+ppl+'</div></div>';}
  return ctop("",{home:true,ns:4})+pg(hs("","home",per("Mom",2),1)+hs("d","home",per("Dad"),1)+hs("g","heart",per("Grandma",3),3),{cls:"r3a-c34"});}}));

D("r3a-34-door","child","3 to 4: the grown-ups’ door",X(G34,{
 desc:"The only privacy surface a toddler sees: a closed door. If she finds the corner a grown-up uses, she gets a picture and a way back, never a PIN pad. The child shell has no settings, and at this age she does not even meet the idea.",
 notes:[[1,"A door with a lock, drawn kindly. It says it is for grown-ups by picture and voice."],[2,"The two ways out are both big: go back, or find Dad. She is not told off and not told no."],[3,"The PIN pad, with shuffled digits, is behind the door and she never sees it (§8.3)."]],
 r:function(){return ctop("",{home:true,ns:2})+pg('<div style="position:relative;margin-bottom:34px"'+n(1)+'><div style="border-radius:34px;overflow:hidden">'+K.scene("night",300,190)+'</div>'+'<span '+n(3)+' style="position:absolute;left:50%;bottom:-34px;transform:translateX(-50%);width:92px;height:92px;border-radius:34px;background:var(--surface);color:var(--pri);display:grid;place-items:center;box-shadow:var(--shadow2);border:4px solid var(--bg)">'+I("lock",44,1.6)+'</span></div><div style="height:6px"></div><div class="grid2"'+n(2)+'>'+tt("arrowL","Go back",{cls:"sm",isz:40})+tt("video","Find Dad",{cls:"sm a",isz:40})+'</div>',{cls:"r3a-c34"});}}));

D("r3a-34-listen","child","3 to 4: listen and scan",X(G34,{
 desc:"The accessibility variant. Everything on screen is spoken as a ring moves from tile to tile, and one big button chooses. High contrast, no motion apart from the ring stepping. For a child who cannot touch small targets, or who uses a single switch.",
 notes:[[1,"The ring steps from tile to tile every few seconds, and each tile speaks as the ring arrives. Speed is a guardian choice, and reduce motion makes it a press-to-step with no timer."],[2,"One huge “choose” button works anywhere on the lower half of the screen, or a switch."],[3,"High contrast: black and white, thick border, no thin type, nothing that depends on a tint."]],
 r:function(){return ctop("",{home:true,ns:1})+pg(tt("video","Call Dad",{cls:"hc scan",hero:false,n:1,isz:56})+tt("book","Stories",{cls:"hc sm",n:3})+tt("brush","Draw",{cls:"hc sm"})+'<button type="button" class="btn pri full lg" style="min-height:96px;border-radius:34px"'+n(2)+'>'+I("check",44,2.4)+'</button>',{cls:"r3a-c34"});}}));

D("r3a-34-offline","child","3 to 4: no wifi",X(G34,{
 desc:"No connection. Stories and drawing still work because they live on the device. The call tile wears a small sleeping cloud and a dashed edge. A tap shows a picture of the cloud napping, and a way to do something else; never a failure.",
 notes:[[1,"The call tile keeps its face and its full contrast. Only a dashed edge and a small cloud say it is waiting. A tap shows a picture, with no words, and never an error."],[2,"Stories and drawing are untouched. Nothing she can do alone is removed."]],
 r:function(){return K.sb()+'<div class="r3a-top" style="justify-content:space-between">'+K.avatar("I",{size:64,ring:true})+sp()+'</div>'+pg(
  tt("video","Call Dad",{hero:true,cls:"off",n:1,extra:'<div class="r3a-faces">'+pav("Dad",72)+cloudNote("")+'</div>'}).replace("hero off","hero off")+'<div class="grid2"'+n(2)+'>'+tt("book","Stories",{cls:"a"})+tt("brush","Draw",{cls:"i"})+'</div>',{cls:"r3a-c34"});}}));

gband("r3a-34-guardian","Ivy at 4: what you decide","4","What the grown-up decides for a toddler’s frame: who she can call, which three things are on her home, and whose voice says the words. Nothing needs her consent, and nothing is hidden from the other guardian.",
 [row({ic:"video",title:"Three tiles",sub:"Call, stories, draw"})+row({ic:"users",title:"Faces she can call",sub:"Mom, Dad, Grandma"})+row({ic:"volume",title:"The voice",sub:"App voice, or yours"}),
  row({ic:"users",title:"Faces she can call",sub:"Mom · Dad · Grandma",go:true,n:3})+row({ic:"sliders",title:"Pick her three tiles",sub:"Call, stories, draw are on",go:true})+row({ic:"mic",title:"Say the words yourself",sub:"Record each tile name. Your own recording, never a copy.",go:true,trail:K.toggle(false,{label:"Use my voice"}),n:4})],
 [[1,"What is on her home today, in her words."],[2,"Every choice is a grown-up’s. Nothing here asks her."],[3,"Who she can call. Adding a face adds a button, nothing else."],[4,"A recording is you, not a synthetic copy. The product does not make one (P1)."]],
 {a:K.notice({tone:"pri",text:"At 5 her home grows to pictures and one word. You choose when."}),b:K.btn("See what changes at 5",{kind:"tonal",full:true,ic:"calendar"})});

/* =========================================================================== 5 TO 7 */
function c57top(title,o){o=o||{};return ctop(title,{noBack:o.noBack,eyebrow:o.eyebrow,ns:o.ns,noSpeak:o.noSpeak});}
D("r3a-57-home","child","5 to 7: her home",X(G57,{wide:true,
 desc:"Pictures lead, one word under each, every word can be heard. Her next thing is the first thing; the rest is a quiet grid. This is the home Ivy has now (sample), drawn for the new system.",
 notes:[[1,"Her name and a plain greeting. Today’s colour is a small fact beside it, never a mood."],[2,"What happens next, in her words. Not a time first."],[3,"Four featured things, each a picture and a word. A dot on Messages is the only unread signal."],[4,"The rest sit quietly. No settings tile at any depth; none of this moves by itself."]],
 r:function(c){
  var hd=K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:sp()+K.avatar("I",{size:44,ring:true})});
  var a=K.card('<span class="r3a-eb" '+n(1)+'>Today’s colour '+sw("var(--accent)")+'</span>'+gap()+'<p class="r3a-lead" style="font-size:22px"'+n(2)+'>Next: Dad calls after school.</p><p class="r3a-p">Then dinner at Mom’s.</p>',"tint");
  var b=K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Dad",scene:"hills"})+'<div class="grid2"'+n(3)+'>'+K.tile("feat",{ic:"dice",title:"Play"})+K.tile("feat",{ic:"chat",title:"Messages",badge:"•"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>'+K.sectionLabel("More")+'<div class="grid3"'+n(4)+'>'+[["brush","Draw"],["users","My people"],["lock","Mine"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>';
  if(c.form==="tablet")return hd+'<div class="tw r3a"><div>'+a+K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Dad",scene:"hills"})+'</div><div><div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play"})+K.tile("feat",{ic:"chat",title:"Messages"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>'+K.sectionLabel("More")+'<div class="grid3">'+[["brush","Draw"],["users","My people"],["lock","Mine"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div></div></div>';
  return hd+pg(a+b);}}));

D("r3a-57-msgs","child","5 to 7: messages",X(G57,{
 desc:"Faces first, then what arrived, in her own words. A video from Dad, a picture from Grandma, a sealed letter that opens in sleeps. Answers are pictures and her voice. No typing.",
 notes:[[1,"She picks a person by face. No dropdown and no role word."],[2,"“Arrived before school”, not 7:04 AM. Her frame comes first."],[3,"A sealed letter says when it opens in sleeps. It cannot be opened early, and nothing counts down at her."],[4,"Answering is three pictures: a heart, a voice, a picture. A heart is a whole answer."]],
 r:function(){return c57top("Messages",{ns:4})+pg(
  '<div class="r3a-faces" style="justify-content:space-around"'+n(1)+'>'+[["Dad",1],["Mom",0],["Grandma",0]].map(function(f){return '<div style="display:grid;justify-items:center;gap:4px">'+pav(f[0],62,{ring:f[1]})+'<b style="font:800 14px var(--font-display)">'+f[0]+'</b></div>';}).join("")+'</div>'+
  K.card('<div style="height:90px;border-radius:20px;overflow:hidden;margin-bottom:10px">'+K.scene("night",300,90)+'</div><div class="row" style="padding:0"><span class="rtxt"><b style="font-size:17px">A story from Dad</b><small'+n(2)+'>Arrived before school</small></span>'+K.chip("2 min",{tone:"pri",ic:"play",sm:true})+'</div>')+
  K.card(row({av:pav("Grandma",48),title:"Grandma",sub:"A picture of the garden",go:true})+row({ic:"letter",title:"A letter from Mom",sub:"Opens Saturday",trail:K.chip("2 sleeps",{tone:"pri",sm:true}),n:3}))+
  '<div class="grid3"'+n(4)+'>'+[["heart","Love it"],["mic","Say hi"],["camera","Show"]].map(function(b){return '<div class="tile std" style="padding:14px 4px"><span class="tic" style="width:52px;height:52px">'+I(b[0],26,1.9)+'</span><b>'+b[1]+'</b></div>';}).join("")+'</div>',{cls:"r3a-c57"});}}));

D("r3a-57-day","child","5 to 7: my day",X(G57,{
 desc:"Her day as pictures with one word each, who she is with, and a week strip that shows where she sleeps. Past things are quieter; the next thing has a ring. The numbers are there for the grown-ups who read over her shoulder.",
 notes:[[1,"The week strip is where she sleeps each night, in the two house colours. A letter as well as a colour, so it is never colour alone."],[2,"Each stop is a picture, a word, and a face."],[3,"The ring is now. Nothing counts down and nothing fills as a score."],[4,"The clock time is small and last. Her frame comes first, the other house’s time is not on this page."]],
 r:function(){function st(done,now,col,ic,wd,face,t){return '<div class="r3a-sti '+(done?"done ":"")+(now?"now":"")+'"'+(now?n(3):"")+'><span class="dot" style="background:'+col+';width:68px;height:68px">'+I(ic,32,1.7)+'</span><span class="wd">'+wd+'<small>'+face+' · '+t+'</small></span>'+(now?'<span class="arw">'+I("arrowR",28,2.2)+'</span>':"")+'</div>';}
  var wk='<div style="display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:4px"'+n(1)+'>'+["M","T","W","T","F","S","S"].map(function(d,i){var h=i<4?"M":"D";return '<span style="display:grid;justify-items:center;gap:3px;font:500 10px var(--font-mono);color:var(--ink3)">'+d+'<i style="width:100%;height:34px;border-radius:12px;display:grid;place-items:center;font:800 14px var(--font-display);font-style:normal;'+(h==="M"?"background:var(--priC);color:var(--onPriC)":"background:var(--accentC);color:var(--ink)")+'">'+h+'</i></span>';}).join("")+'</div>';
  return c57top("My day",{ns:4})+pg(K.card(wk+gap()+fine("M is Mom’s house. D is Dad’s house.")+'')+'<div class="r3a-strip" style="--dw:68px"'+n(2)+'>'+st(1,0,"var(--dpMorning)","sun","Wake up","Mom","7:15")+st(1,0,"var(--dpDay)","book","School","","8:30")+st(0,1,"var(--dpAfternoon)","users","Grandma","Grandma","3:30")+st(0,0,"var(--dpEvening)","video","Dad calls","Dad","6:00")+st(0,0,"var(--dpBed)","moon","Bed","Mom","7:45")+'</div>',{cls:"r3a-c57"});}}));

D("r3a-57-play","child","5 to 7: play together",X(G57,{
 desc:"Games for two, played in turns. Uno, Connect Four, Checkers, War and Word search, each between her and a person. A game waits for her without a timer, and finishing one just says it was a good game.",
 notes:[[1,"Whose turn it is, in words and a face. It never says “waiting for you” in red."],[2,"Games she can start: a picture and a name. Uno and Connect Four have a computer partner for when nobody is online."],[3,"No score, no streak, no “best”. A finished game says good game (P2)."],[4,"A quiet shelf for playing on her own: Colour sort, Find the thing, Kim’s game."]],
 r:function(){return c57top("Play",{ns:2})+pg(
  K.sectionLabel("Games with people")+K.card(stateRow("dice","Uno with Dad","Your turn",{t:"Your turn",tone:"pri",ic:"play"},1)+stateRow("grid","Connect Four with Mom","Mom’s turn",{t:"Mom’s turn",tone:"",ic:"clock"})+stateRow("pawn","Checkers with Grandma","Good game",{t:"Done",tone:"ok",ic:"check"},3),"")+
  K.sectionLabel("Start a game")+'<div class="grid3"'+n(2)+'>'+[["dice","Uno"],["grid","Connect Four"],["pawn","Checkers"],["layers","War"],["search","Word search"],["users","Draw & guess"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>'+
  K.sectionLabel("On my own")+K.card(row({ic:"palette",title:"Colour sort",go:true})+row({ic:"eye",title:"Kim’s game",go:true,n:4})),{cls:"r3a-c57"});}}));

D("r3a-57-make","child","5 to 7: colour a critter",X(G57,{
 desc:"A line drawing she colours in, stickers to add, and a way to keep it or send it to Dad. Her colour of the day is simply the first pot. No grades, no “well done!” meter.",
 notes:[[1,"The first pot is today’s colour, shown as a fact. She can pick any of the six."],[2,"A sticker row with plain shapes. No fruit-machine rewards."],[3,"Keep puts it in her collection. Send to Dad puts it in a message."]],
 r:function(){return c57top("Colour",{ns:3})+pg('<div class="r3a-cv">'+sketch()+'</div>'+pots(0).replace('class="r3a-pots"','class="r3a-pots"'+n(1))+'<div class="r3a-faces"'+n(2)+'>'+["leaf","heart","sun","sparkle"].map(function(i){return '<span class="r3a-pot" style="display:grid;place-items:center;background:var(--surface);color:var(--pri);width:56px;height:56px">'+I(i,26,1.8)+'</span>';}).join("")+'</div><div class="btns"'+n(3)+'>'+K.btn("Keep it",{ic:"check"})+K.btn("Send to Dad",{kind:"tonal",ic:"send"})+'</div>',{cls:"r3a-c57"});}}));

D("r3a-57-feel","child","5 to 7: my feelings corner",X(G57,{
 desc:"A place to show how it is, not a place to be measured. Five faces with names, a choice of who to tell, a quiet corner and a way to ask for a grown-up now. Nothing is logged. A grown-up never sees a chart, only a picture she chose to send.",
 notes:[[1,"Faces with names, in no order that implies good or bad. Tapping one is a way to say, not a reading."],[2,"She picks who to tell. If she tells no one, nobody knows, and that is allowed."],[3,"I need a grown-up now rings the one in her house, as a plain call, with no diagnosis."],[4,"No history, no trend and no summary exist, so nothing can be shown to a parent or to anyone else."]],
 r:function(){return c57top("How it is",{ns:1})+pg(
  '<div class="r3a-tp"'+n(1)+'>'+[["happy","Happy"],["calm","Calm"],["sad","Sad"],["cross","Cross"],["worry","Worried"]].map(function(f,i){return '<div role="button" tabindex="0">'+fc(f[0],40)+f[1]+'</div>';}).join("")+'</div>'+
  K.card(h5("Show someone?")+gap()+'<div class="r3a-faces" style="justify-content:space-around">'+["Dad","Mom","Grandma"].map(function(nm){return '<div style="display:grid;justify-items:center;gap:4px">'+pav(nm,56)+'<b style="font:800 13px var(--font-display)">'+nm+'</b></div>';}).join("")+'</div>'+gap()+K.btn("No one, just me",{kind:"ghost",full:true}),"",2)+
  '<div class="grid2">'+K.tile("feat",{ic:"moon",title:"Quiet corner"})+K.tile("feat",{ic:"hand",title:"I need someone now",n:3})+'</div>'+fine("Only what you choose to send goes anywhere.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{cls:"r3a-c57"});}}));

D("r3a-57-people","child","5 to 7: my people",X(G57,{wide:true,
 desc:"Her family as she knows it, under the names she uses, with a glyph for what she can do: call, or send a message. Where she sleeps tonight has a soft ring.",
 notes:[[1,"Each home is a place, with the people there. The name is the one she uses; no step, half or role words."],[2,"A video glyph means she can call. A speech glyph means she can send a message."],[3,"Tonight’s house is marked with a ring and a moon, a fact she can look up when she wants it."],[4,"A guardian builds this alone. The other guardian sees every change."]],
 r:function(c){function per(nm,mode,nn){return '<div style="display:grid;justify-items:center;gap:6px;background:var(--surface);border-radius:22px;padding:10px 6px;min-height:104px;align-content:center" role="button" tabindex="0" aria-label="'+(mode==="call"?"Call ":"Message ")+E(nm)+'"'+n(nn)+'>'+pav(nm,52)+'<b style="font:800 15px var(--font-display)">'+E(nm)+'</b><span style="color:var(--ink3)">'+I(mode==="call"?"video":"chat",18,2)+'</span></div>';}
  function hs(cls,t,ppl,nn,tonight){return '<div class="r3a-hs '+cls+'"'+n(nn)+(tonight?' style="outline:3px solid var(--pri);outline-offset:2px"':"")+'><h4 style="margin:0;font:800 18px var(--font-display);display:flex;gap:8px;align-items:center">'+I("home",22,2)+E(t)+(tonight?'<span style="margin-left:auto">'+I("moon",20,2)+'</span>':"")+'</h4><div class="r3a-hp">'+ppl+'</div></div>';}
  var m=hs("","Mom’s house",per("Mom","call",2),1,true),d=hs("d","Dad’s house",per("Dad","call")+per("Dana","msg"),1),g=hs("g","Near and far",per("Grandma","call"),4);
  if(c.form==="tablet")return c57top("My people",{ns:1})+'<div class="tw r3a"><div>'+m+d+'</div><div>'+g+K.card(fine("Tonight you sleep at Mom’s."),"flat",3)+'</div></div>';
  return c57top("My people",{ns:1})+pg(m+d+g+K.card(fine("Tonight you sleep at Mom’s."),"flat",3),{cls:"r3a-c57"});}}));

D("r3a-57-mine","child","5 to 7: just for me",X(G57,{
 desc:"The privacy surface for this age: three shelves, each showing who can see what is on it, as faces. She can look but not change: the child shell has no settings. A button asks a grown-up, and nothing more.",
 notes:[[1,"A shelf is a place. The faces on it are the people who can see its things."],[2,"The secret book has a lock and no faces. It is only hers."],[3,"There are no switches here. At this age the grown-ups decide, and she is shown honestly what they decided."],[4,"Ask my grown-up sends a plain request. It is a question, never a complaint."]],
 r:function(){function sh(ic,t,ppl,nn,lock){return K.card('<div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap"'+n(nn)+'><span class="ricon" style="width:52px;height:52px;border-radius:18px">'+I(ic,26,1.8)+'</span><b style="font:800 18px var(--font-display);flex:1">'+t+'</b>'+(lock?'<span style="color:var(--ink2)">'+I("lock",24,2)+'</span>':K.avatarStack(ppl,{size:34,max:4}))+'</div>');}
  return c57top("Mine",{ns:4})+pg(sh("image","My drawings",[["M"],["D","accent"],"G"],1)+sh("camera","Show & tell",[["D","accent"]],0)+sh("book","My secret book",[],2,true)+K.btn("Ask my grown-up",{kind:"tonal",full:true,size:"lg",ic:"hand",n:4})+fine("Nothing here can be changed from this screen.").replace('class="r3a-fine"','class="r3a-fine" data-n="3"'),{cls:"r3a-c57"});}}));

D("r3a-57-read","child","5 to 7: reading help",X(G57,{
 desc:"The accessibility variant. A story page with a dyslexia-friendly face, larger type and wide spacing, the word being read lit as it is spoken, and captions on every video. All set by a grown-up, shown honestly to her.",
 notes:[[1,"A reading face made for dyslexia, with extra spacing between letters and lines."],[2,"The word being read is lit. Nothing else moves."],[3,"Slower and faster are pictures, not the words slow and fast. A rewind goes back one sentence."],[4,"Captions on every video, from the start. Not a setting she has to find."]],
 r:function(){return c57top("The little fox",{ns:3})+pg(
  '<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("garden",300,130)+'</div>'+
  K.card('<p style="font:700 24px/1.9 var(--font-body);letter-spacing:.08em;margin:0;color:var(--ink)"'+n(1)+'>The fox looked at the <mark style="background:var(--dpMorning);color:#18211c;border-radius:6px;padding:0 6px"'+n(2)+'>moon</mark> and waited for Dad.</p>')+
  '<div class="r3a-faces" style="gap:12px"'+n(3)+'>'+[["rewind","Back"],["pause","Pause"],["skip","Next"]].map(function(b){return K.iconBtn(b[0],{kind:"tonal",label:b[1],sz:26});}).join("")+'</div>'+
  K.notice({tone:"info",text:"Reading help is on. A grown-up chose it for you.",ic:"eye",n:4}),{cls:"r3a-c57"});}}));

D("r3a-57-offline","child","5 to 7: no wifi",X(G57,{
 desc:"No connection. Her day, stories, drawing and secret book still work. Things that need another person wear a small cloud and stay put. A tap shows a napping cloud, never an error.",
 notes:[[1,"Her day opens from the device. It is the same offline."],[2,"Tiles that need someone else carry a quiet cloud and a dashed edge, at full contrast and still tappable."],[3,"Everything she can do alone is untouched."],[4,"One soft line with a cloud. No red, no code."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:sp()+K.avatar("I",{size:44,ring:true})})+pg(
  K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Dad",scene:"hills",n:1})+
  '<div class="grid2"'+n(2)+'>'+'<div style="position:relative">'+K.tile("feat",{ic:"chat",title:"Messages"})+'<span style="position:absolute;right:8px;bottom:5px;color:var(--ink2)">'+I("cloud",16,2)+'</span></div>'+'<div style="position:relative">'+K.tile("feat",{ic:"dice",title:"Play"})+'<span style="position:absolute;right:8px;bottom:5px;color:var(--ink2)">'+I("cloud",16,2)+'</span></div>'+K.tile("feat",{ic:"book",title:"Stories",n:3})+K.tile("feat",{ic:"brush",title:"Draw"})+'</div>'+
  K.notice({tone:"info",text:"The wifi is having a nap. Your stories and drawings are here.",ic:"cloud",n:4}),{cls:"r3a-c57"});}}));

gband("r3a-57-guardian","Ivy at 6: what you decide","6","What the grown-up decides at five to seven: which areas follow the band, which are held, who she can reach and the pace of a change. Her side stays free of settings.",
 [row({ic:"dice",title:"Games for two",sub:"Uno, Connect Four, Checkers"})+row({ic:"chat",title:"Messages",sub:"Pictures and her voice"})+row({ic:"lock",title:"Just for me",sub:"Secret book, only hers"}),
  row({ic:"book",title:"Reading and words",sub:"One band up: words beside pictures",go:true,n:3})+row({ic:"dice",title:"Games",sub:"Follows her band",go:true})+row({ic:"hourglass",title:"Hold the next band",sub:"Until you have told her",trail:K.toggle(true,{label:"Hold"}),n:4})],
 [[1,"What is on her home, in her words, with the same icons she sees."],[2,"Every item is yours to change. She cannot, and cannot see that you can."],[3,"A child can be ahead in reading and not elsewhere. Each area follows a band you set."],[4,"The hold is the default. Nothing moves until you say so."]],
 {a:K.notice({tone:"pri",text:"Her secret book is hers alone. Nobody can open it."}),b:K.btn("See what changes at 8",{kind:"tonal",full:true,ic:"calendar"})});

/* =========================================================================== 8 TO 12 */
function c812top(title,o){o=o||{};return top(title,{noBack:o.noBack,eyebrow:o.eyebrow,nb:o.nb,right:(o.right||"")+(o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:o.ns}))});}
function wk2(seq){return '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px">'+seq.split("").map(function(ch,i){var m=ch==="m";return '<i style="height:34px;border-radius:10px;display:grid;place-items:center;font:800 13px var(--font-display);font-style:normal;'+(m?"background:var(--priC);color:var(--onPriC)":"background:var(--accentC);color:var(--ink)")+'" aria-label="'+(m?"Mom’s":"Dad’s")+'">'+(m?"M":"D")+'</i>';}).join("")+'</div>';}
function dl(){return '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;font:500 9.5px var(--font-mono);color:var(--ink3);text-align:center;margin-bottom:3px">'+["MON","TUE","WED","THU","FRI","SAT","SUN"].map(function(d){return '<span>'+d+'</span>';}).join("")+'</div>';}

D("r3a-812-home","child","8 to 12: her home",X(G812,{wide:true,
 desc:"Less cute, more capable. What matters next comes first, her weeks are on the page, her own list is a row and the games are a quiet shelf. Words sit beside every picture, and the speaker is small and optional.",
 notes:[[1,"A plain greeting and the next thing that matters. No mascot."],[2,"Her two weeks in her house colours. A letter as well as a colour. This is her view of her own life."],[3,"Her list arrives as a row from about ten. From rung 10 nobody curates it."],[4,"Three games and the creative corner on a quiet shelf. The same rules hold: nothing scores, nothing streaks."]],
 r:function(c){
  var a=K.card('<span class="r3a-eb">Next</span><p class="r3a-lead" style="margin-top:4px"'+n(1)+'>Call with Dad at 3:00 PM</p><p class="r3a-p">In two hours, after school.</p>',"tint")+K.card(h5("My weeks")+gap()+dl()+wk2("mmmmmdd")+gap()+wk2("ddddddd")+gap()+fine("M is Mom’s house · D is Dad’s house"),"",2);
  var b=K.card(row({ic:"list",title:"My list",sub:"Things I need · things I want",go:true,n:3})+row({ic:"chat",title:"Messages",sub:"Dad: see you Friday",go:true,trail:'<span class="dot" style="width:10px;height:10px;border-radius:50%;background:var(--pri)"></span>'}))+K.sectionLabel("Play and make")+'<div class="grid3"'+n(4)+'>'+[["grid","Chess"],["dice","Uno"],["puzzle","Puzzles"],["brush","Pixel garden"],["book","Storyteller"],["search","Word chain"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>';
  var hd=K.sb()+K.top({eyebrow:"Saturday",title:"Hey, Ivy",right:K.avatar("I",{size:44,ring:true})});
  if(c.form==="tablet")return hd+'<div class="tw r3a"><div>'+a+'</div><div>'+b+'</div></div>';
  return hd+pg(a+b,{cls:"r3a-c812"});}}));

D("r3a-812-msgs","child","8 to 12: messages",X(G812,{wide:true,
 desc:"A real conversation. She reads and writes, sends a voice note or a drawing, and chooses who she is talking to. When it is very late where Dad is, the app says when he will see it; it does not stop her.",
 notes:[[1,"A thread with one person at a time. The whole conversation, in order."],[2,"She can write, speak or draw. Text appears next to the voice note, so nothing needs listening to."],[3,"A late-hour line says when it will arrive. The send-time guard is on her side until 14, as a note and not a block."],[4,"Only the two of them read this thread. The other guardian sees that it happened, not what it says."]],
 r:function(c){
  var list=K.filterChips(["Dad",{l:"Mom"},"Grandma"],[0])+K.card(K.row({av:pav("Dad",46),title:"Dad",sub:"See you Friday",trail:'<span class="dot" style="width:10px;height:10px;border-radius:50%;background:var(--pri)"></span>',go:true})+K.row({av:pav("Mom",46),title:"Mom",sub:"Have a good day"})+K.row({av:pav("Grandma",46),title:"Grandma",sub:"A picture of the garden"}));
  var th=K.bubble("I made a new level on the pixel garden.",true,"7:02 AM")+K.bubble("Show me on Friday! I want to see it.",false,"7:04 AM")+'<div class="bub them" style="max-width:86%"><span style="display:flex;align-items:center;gap:8px">'+I("play",16,2)+K.waveform({bars:22,played:.3,h:24,seed:4,label:"Voice note"})+'</span><small>0:14 · 7:05 AM</small></div>'+
   K.notice({tone:"info",title:"It is 1 AM where Dad is",text:"He will see this in the morning.",n:3})+
   K.field("Message","",{ph:"Write to Dad",n:2})+'<div class="btns" style="gap:8px">'+K.iconBtn("mic",{kind:"tonal",label:"Voice",sz:22})+K.iconBtn("brush",{kind:"tonal",label:"Draw",sz:22})+'</div>';
  if(c.form==="tablet")return c812top("Messages",{ns:0,noSpeak:true,noBack:true})+'<div class="tw r3a"><div>'+list+'</div><div>'+K.card(th,"",1)+'</div></div>';
  return c812top("Dad",{eyebrow:"Messages",noSpeak:true})+pg(K.card(th,"",1)+fine("Only you and Dad can read this.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{cls:"r3a-c812"});}}));

D("r3a-812-cal","child","8 to 12: my weeks and calendar",X(G812,{wide:true,
 desc:"Her own calendar to read. A month in her two house colours, what is on the selected day and a plain way to ask a grown-up to add something. She cannot edit it until fourteen; she can always ask.",
 notes:[[1,"The month in two house colours, with a letter on each day as well, so it never relies on colour."],[2,"The selected day, in the order it will happen."],[3,"She can ask to add an idea. It goes to a guardian as a question. Editing is rung 14."],[4,"The other house’s clock is a small aside, not a headline."]],
 r:function(c){
  var l=K.calMonth({today:8,sel:12,marks:{1:"a",2:"a",3:"a",4:"b",5:"b",6:"b",7:"b",9:"mix",12:"ev"},names:{a:"Mom’s",b:"Dad’s"},n:1});
  var r=K.card(h5("Thursday 12")+gap()+K.timeline([{time:"8:30",title:"School",state:"done"},{time:"3:30",title:"Grandma picks you up",state:"now",ic:"users"},{time:"6:00",title:"Dad calls",state:"next",ic:"video"},{time:"7:45",title:"Bedtime at Mom’s",state:"next",ic:"moon"}],{n:2}))+K.btn("Ask to add something",{kind:"tonal",full:true,ic:"hand",n:3})+fine("It is 1:15 AM where Dad is.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"');
  return two(c,l,r,c812top("My weeks",{noSpeak:true}),"","r3a-c812");}}));

D("r3a-812-play","child","8 to 12: play",X(G812,{wide:true,
 desc:"Longer games, saved and picked up again. Chess and Battleship with Dad across a week, Uno on a team with Grandma, Word chain, a scavenger hunt in the house. Computer partners are always there. Nothing scores and nothing streaks.",
 notes:[[1,"Games waiting for her, with the person and a plain word. There is no timer and no “you are slow”."],[2,"Longer games save themselves and are picked up whenever. A move can sit for a week."],[3,"Teams are a choice: two players each, or all together against the computer."],[4,"Finishing says it was a good game. No tallies, medals or ranks (P2)."]],
 r:function(c){
  var l=K.sectionLabel("Waiting for you")+K.card(stateRow("grid","Chess with Dad","saved 2 days",{t:"Your move",tone:"pri"},1)+stateRow("target","Battleship with Mom","Mom’s move",{t:"Mom’s move"})+stateRow("dice","Uno with Grandma and Dad","",{t:"Team game"},3));
  var r=K.sectionLabel("Start")+'<div class="grid3"'+n(2)+'>'+[["grid","Chess"],["target","Battleship"],["dice","Uno"],["layers","Connect Four"],["search","Word chain"],["footprint","Scavenger hunt"],["users","Draw & guess"],["puzzle","Path code"],["eye","Kim’s game"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>'+K.card(row({ic:"device",title:"Play the computer",sub:"Easy, medium or tricky",go:true}),"",4);
  return two(c,l,r,c812top("Play",{noSpeak:true}),"","r3a-c812");}}));

D("r3a-812-make","child","8 to 12: storyteller",X(G812,{
 desc:"A creative corner for ideas of her own: stories, comics, a pixel garden. A story with a picture strip, her words and a way to read it to Dad. The helper suggests, never writes it for her, and never reads anything she has not shared.",
 notes:[[1,"Her words, her picture strip. The page is hers."],[2,"A suggestion box with three ideas she can ignore. It does not rewrite her sentences."],[3,"Read to Dad sends a recording of her own voice, not a generated one (P1)."],[4,"Keep puts it in her collection. Nothing is rated and nothing is shared unless she sends it."]],
 r:function(){return c812top("The fox and the moon",{eyebrow:"Storyteller",noSpeak:true})+pg(
  '<div style="border-radius:22px;overflow:hidden;box-shadow:var(--shadow1)">'+K.scene("night",300,100)+'</div>'+
  K.card('<p style="font:500 17px/1.6 var(--font-body);margin:0;color:var(--ink)"'+n(1)+'>The fox sat on the hill and watched the moon get bigger. She had promised to wait until the stars came out.<span style="border-left:2px solid var(--pri);margin-left:2px"></span></p>')+
  K.card(h5("Ideas, if you want them")+gap()+'<div style="display:flex;flex-wrap:wrap;gap:6px">'+K.chip("Who comes along?",{sm:true})+K.chip("What does she hear?",{sm:true})+K.chip("Where is home?",{sm:true})+'</div>',"flat",2)+
  '<div class="btns" style="gap:8px">'+K.btn("Read to Dad",{ic:"mic",n:3})+K.btn("Keep it",{kind:"tonal",ic:"check",n:4})+'</div>',{cls:"r3a-c812"});}}));

D("r3a-812-help","child","8 to 12: when it is hard",X(G812,{
 desc:"Words for hard feelings, things to try, and people to tell. It is never a questionnaire, a score or a diagnosis. What she taps is not saved and not shown to anyone. A grown-up sees nothing unless she chooses to tell them.",
 notes:[[1,"Sentences she can borrow: “I’m worried”, “I’m angry”, “I miss someone”. They are words for her, not a reading about her."],[2,"Things to try, in plain words: breathe, draw it out, move, tell someone. Each is a short, kind page."],[3,"People to tell, as faces she already knows, and a line for someone outside the family."],[4,"The last line says it plainly: nobody sees what you tap here. There is no history to find."]],
 r:function(){return c812top("When it is hard",{ns:4})+pg(
  K.card(h5("Words you can use")+gap()+'<div style="display:flex;flex-wrap:wrap;gap:6px"'+n(1)+'>'+["I’m worried","I’m angry","I’m tired","I miss someone","I don’t know"].map(function(t,i){return K.chip(t,{});}).join("")+'</div>')+
  K.card(row({ic:"leaf",title:"Breathe with me",sub:"One minute",go:true,n:2})+row({ic:"brush",title:"Draw it out",sub:"No one sees it unless you show them",go:true})+row({ic:"footprint",title:"Move for a bit",sub:"Three ideas",go:true}))+
  K.card(h5("Tell someone")+gap()+'<div class="r3a-faces" style="justify-content:space-around"'+n(3)+'>'+["Dad","Mom","Grandma"].map(function(nm){return '<div style="display:grid;justify-items:center;gap:4px">'+pav(nm,54)+'<b style="font:800 13px var(--font-display)">'+nm+'</b></div>';}).join("")+'</div>'+gap()+row({ic:"phone",title:"Talk to someone outside the family",sub:"A free kids’ helpline (sample, set by your country)",go:true}))+
  K.card(row({ic:"lock",title:"Nobody sees what you tap here",sub:"It is not saved.",n:4}),"flat"),{cls:"r3a-c812"});}}));

D("r3a-812-people","child","8 to 12: my people",X(G812,{wide:true,
 desc:"Her family as she knows it, under the names she uses, and the grown-ups she can tell anything to. A short page of facts about how it works, written by a guardian, in words she can read herself.",
 notes:[[1,"Places and people, as before. Names are the ones she uses."],[2,"A short note, written by Mom and Dad, about how the weeks work. It says so: it is theirs, in their words. The app wrote nothing."],[3,"People she can always reach, however things change. This is not a rank."],[4,"She can ask a question about any of it. It goes to both guardians together."]],
 r:function(c){function per(nm,mode){return '<div style="display:grid;justify-items:center;gap:6px;background:var(--surface);border-radius:22px;padding:10px 6px;min-height:104px;align-content:center" role="button" tabindex="0" aria-label="'+(mode==="call"?"Call ":"Message ")+E(nm)+'">'+pav(nm,52)+'<b style="font:800 15px var(--font-display)">'+E(nm)+'</b><span style="color:var(--ink3)">'+I(mode==="call"?"video":"chat",18,2)+'</span></div>';}
  function hs(cls,t,ppl,nn){return '<div class="r3a-hs '+cls+'"'+n(nn)+'><h4 style="margin:0;font:800 18px var(--font-display);display:flex;gap:8px;align-items:center">'+I("home",22,2)+E(t)+'</h4><div class="r3a-hp">'+ppl+'</div></div>';}
  var l=hs("","Mom’s house",per("Mom","call"),1)+hs("d","Dad’s house",per("Dad","call")+per("Dana","msg"))+hs("g","Near and far",per("Grandma","call"));
  var r=K.card('<span class="r3a-eb">From Mom and Dad</span>'+gap()+p("“You have two homes and you are loved in both. We wrote this together so you do not have to guess how it works.”")+gap()+fine("Written by Jess and Marcus. Olive Branch did not write this."),"tint",2)+K.card(row({ic:"hand",title:"Always here for you",sub:"Mom, Dad and Grandma, any time",n:3})+row({ic:"chat",title:"Ask a question",sub:"It goes to both of them",go:true,n:4}));
  return two(c,l,r,c812top("My people",{noSpeak:true}),"","r3a-c812");}}));

D("r3a-812-mine","child","8 to 12: what is mine",X(G812,{wide:true,
 desc:"The privacy surface at this age. A plain list of what grown-ups can see about her and what only she can, and an honest page about what becomes hers and when. She can read all of it. She can change none of it yet, because the child shell has no settings, and it says exactly where each change comes from.",
 notes:[[1,"Each line says what a thing is and who can see it, in one sentence."],[2,"Her list is hers from ten. Until then she is shown that the day is coming."],[3,"Some things never change at any age: where she is, her journal. They are listed under the same heading as the rest."],[4,"The ladder, in her words: what becomes hers, at what age. No one can take a step back (§21)."]],
 r:function(c){function line(ic,t,s,nn,mark){return K.row({ic:ic,title:t,sub:s,n:nn,trail:mark||""});}
  var l=K.card(h5("Who can see what")+gap()+line("calendar","My weeks","Mom and Dad",1)+line("list","My list","Only me from 10. Now: Mom or Dad can help",2,K.chip("At 10",{tone:"info",sm:true}))+line("book","My journal","Only me. No one else, ever",3,v("no"))+line("image","My drawings","Only ones I show",0)+line("eye","Where I am","Nobody, ever",3,v("no")));
  var r=K.card(h5("What gets to be mine")+gap()+K.timeline([{time:"10",title:"My list is mine",state:"next"},{time:"13",title:"My journal locks",state:"next"},{time:"14",title:"I edit my calendar",state:"next"},{time:"15",title:"I say when I am free",state:"next"},{time:"16",title:"I choose what stays in the archive",state:"next"},{time:"17",title:"I can take a copy of everything",state:"next"}],{n:4}))+K.btn("Ask a grown-up a question",{kind:"tonal",full:true,ic:"hand"});
  return two(c,l,r,c812top("What is mine",{noSpeak:true}),"","r3a-c812");}}));

D("r3a-812-ease","child","8 to 12: make it easier to read",X(G812,{
 desc:"The accessibility variant. Reading help she can try at once, without a settings screen: bigger words, a reading face, fewer moving things, read it to me. It applies on this device immediately and is reported to no one. A guardian can set the defaults.",
 notes:[[1,"A short panel from the corner of any page. Four big choices, each a picture and a word."],[2,"Applies at once, on this device. No Save, no account change."],[3,"Marked Proposed: today these are guardian settings. A product decision is needed on whether a child may adjust them herself."]],
 r:function(){return c812top("Make it easier",{ns:1})+pg(
  K.card('<p class="r3a-p" style="font-size:17px">The fox sat on the hill and watched the moon get bigger.</p>')+
  '<div class="grid2"'+n(1)+'>'+[["search","Bigger words",1],["book","Reading face",1],["volume","Read it to me",0],["hand","Fewer moving things",0]].map(function(t){return '<div class="tile std" style="padding:14px 6px;'+(t[2]?"outline:3px solid var(--pri);outline-offset:-3px":"")+'" role="button" aria-pressed="'+(!!t[2])+'" tabindex="0"><span class="tic" style="width:52px;height:52px">'+I(t[0],26,1.9)+'</span><b>'+t[1]+'</b></div>';}).join("")+'</div>'+
  K.notice({tone:"info",text:"It changes right now, on this device only.",ic:"check",n:2})+'<div style="text-align:center"'+n(3)+'>'+prop()+'</div>',{cls:"r3a-c812"});}}));

D("r3a-812-offline","child","8 to 12: offline",X(G812,{
 desc:"No connection. Her weeks, her list, her stories and any saved game still work. A message she writes waits in the outbox and says plainly that it will go when the wifi is back. Nothing she has made is lost.",
 notes:[[1,"A quiet line, not an alarm. It says what still works first."],[2,"A message waits. It says “will go when wifi is back” and shows a queued mark with an icon and a word."],[3,"Her saved chess game opens and she can play her move; it syncs later."],[4,"Everything she makes is on the device first. Nothing disappears."]],
 r:function(){return c812top("Hey, Ivy",{noBack:true,noSpeak:true})+pg(
  K.offlineBanner({text:"The wifi is away",sub:"Your weeks, list and games still work."}).replace('class="offline"','class="offline" data-n="1"')+
  K.card(row({av:pav("Dad",46),title:"Dad",sub:"See you Friday! I made a new level.",n:2})+'<div style="padding:0 0 4px 58px">'+K.status("queued","Queued")+' <span class="r3a-fine">Goes when wifi is back</span></div>')+
  K.card(stateRow("grid","Chess with Dad","Saved on this device",{t:"Playable",tone:"ok",ic:"check"},3)+stateRow("list","My list","On this device",{t:"Here",tone:"ok",ic:"check"}),"")+
  K.card(fine("Everything you make is saved on this device first."),"flat",4),{cls:"r3a-c812"});}}));

gband("r3a-812-guardian","Ivy at 10: what you decide","10","What a guardian still decides at eight to twelve, what has moved to her, and what the quiet fading of scaffolds looks like. Her list is hers; her weeks are yours to set.",
 [row({ic:"calendar",title:"Her weeks",sub:"She reads them; you set them"})+row({ic:"list",title:"Her list",sub:"Hers from 10. You cannot edit it"})+row({ic:"dice",title:"Longer games",sub:"Chess, Battleship, Uno"})+row({ic:"lock",title:"Her journal",sub:"Locked at 13. Nobody can open it"}),
  row({ic:"clock",title:"Send-time guard on her side",sub:"Fades at 14. It stays on yours forever",go:true,n:3})+row({ic:"hourglass",title:"Sleeps counting",sub:"Fades at 11. She can read a calendar",go:true})+row({ic:"hand",title:"Her requests to add things",sub:"2 waiting, from this week",go:true,n:4})],
 [[1,"What she has now, as she sees it."],[2,"These are the levers that still belong to you."],[3,"Scaffolds fade on a schedule. The app is meant to need you less and her less."],[4,"Her requests arrive here as questions. You answer each in your own words."]],
 {a:K.notice({tone:"pri",text:"Her list is hers from ten. You will not see it."}),b:K.btn("See what changes at 13",{kind:"tonal",full:true,ic:"calendar"})});

/* =========================================================================== 13 TO 17: THE TEEN FRAME */
function thd(title,o){o=o||{};return K.sb()+'<div class="r3a-top">'+(o.back?'<button type="button" class="r3a-b" aria-label="'+(o.home?"Home":"Back")+'"'+n(o.nb)+'>'+I(o.home?"home":"chevL",o.home?26:20,2)+'</button>':"")+'<div class="ttl">'+(o.eyebrow?'<small>'+E(o.eyebrow)+'</small>':"")+'<b>'+E(title)+'</b></div>'+(o.right||"")+'</div>';}
function ev(t,s,cls,nn,trail){return '<div class="r3a-ev '+(cls||"")+'"'+n(nn)+'><i></i><div><b>'+E(t)+'</b><small>'+E(s)+'</small></div>'+(trail||"")+'</div>';}
function tpair(c,l,r,hd,tab,cls){return two(c,l,r,hd,tab,cls);}
function frow(ic,t,s,nn,trail,go){return K.row({ic:ic,title:t,sub:s,go:go!==false,n:nn,trail:trail||""});}

D("r3a-13-home","teen","13 to 17: today",X(G13,{wide:true,
 desc:"A calm page for a person with a life. What is next, who has written, whether she is free, and Downtime a tap away rather than front and centre. No mascot, no voice-over, no tiles of different weights: a list that reads like her calendar.",
 notes:[[1,"Her availability is hers from 15. This pill is the one control on the page: tap to change it. It is not a mood and not a status line for anyone else."],[2,"Today in order. Her events, school, work and the family handover, all in one list."],[3,"A message preview, not a badge. It says what was said."],[4,"Downtime is a row, not a tile. Games move to the back of the app at 14, not out of it."]],
 r:function(c){
  var a='<div class="r3a-now"'+n(1)+'>'+pav("Ivy",40)+'<span class="rtxt" style="min-width:0"><b>You are free from 7:00 PM</b><br><small style="color:var(--ink3)">Mom and Dad see this</small></span><span class="r3a-pill on">'+I("check",14,2.4)+'On</span></div>'+
   K.sectionLabel("Today")+'<div style="display:grid;gap:8px"'+n(2)+'>'+ev("Chemistry lab","10:00 · School","")+ev("Café shift","12:00–4:00 · Work","w")+ev("Driving lesson with Dad","4:30 · He picks you up","b")+ev("Handover to Dad","Sunday 6:00 PM","m")+'</div>';
  var b=K.sectionLabel("Messages")+K.card(K.row({av:pav("Dad",44),title:"Dad",sub:"Can we do 5:00 instead?",go:true,n:3})+K.row({av:pav("Mom",44),title:"Mom",sub:"Sent a photo",go:true}))+
   K.sectionLabel("Later")+K.card(frow("dice","Downtime","Chess with Dad · your move",4)+frow("pencil","Studio","Voice, photos, words, letters",0));
  var hd=thd("Good morning, Ivy",{eyebrow:"Saturday",right:K.avatar("I",{size:44,label:"Me"})});
  if(c.form==="tablet")return hd+'<div class="tw r3a"><div>'+a+'</div><div>'+b+'</div></div>'+ttabs(0);
  return hd+pg(a+b,{tab:ttabs(0)});}}));

D("r3a-13-msgs","teen","13 to 17: messages",X(G13,{wide:true,
 desc:"Real messages, as in any messaging app she already uses, but with the house rules intact: only the two people read a thread, a message delivered says delivered, and nothing is read for her. No send-time guard on her side from 14.",
 notes:[[1,"Threads by person. She chooses whom to write to; the other guardian is not a recipient."],[2,"Delivered, not “watched”. A teen’s message is not a video to be played through."],[3,"Send now or send later is her choice. The guard is off her side; it stays on theirs."],[4,"The thread says who can read it. Honesty at the top beats a policy page."]],
 r:function(c){
  var list=K.card(K.row({av:pav("Dad",46),title:"Dad",sub:"Can we do 5:00 instead?",trail:'<small class="tnum" style="color:var(--ink3)">9:12</small>',go:true,n:1})+K.row({av:pav("Mom",46),title:"Mom",sub:"Sent a photo",trail:'<small class="tnum" style="color:var(--ink3)">8:40</small>',go:true})+K.row({av:pav("Grandma",46),title:"Grandma",sub:"Thinking of you x",trail:'<small class="tnum" style="color:var(--ink3)">Mon</small>',go:true}));
  var th=K.card('<div style="display:flex;gap:6px;align-items:center;margin-bottom:8px">'+pav("Dad",32)+'<b style="font:700 14.5px var(--font-body)">Dad</b><span style="margin-left:auto">'+priv("Just you and Dad")+'</span></div>'+K.bubble("Is the lesson still on at 4:30?",true,"9:08")+K.bubble("Can we do 5:00 instead? I have a call.",false,"9:12")+K.bubble("Fine. Can I drive the whole way?",true,"9:12")+'<div'+n(2)+'>'+K.status("delivered","Delivered")+'</div>'+gap()+K.field("Message","",{ph:"Write to Dad",n:3})+'<div class="btns" style="gap:8px">'+K.iconBtn("mic",{kind:"tonal",label:"Voice note"})+K.iconBtn("camera",{kind:"tonal",label:"Photo"})+K.iconBtn("send",{label:"Send"})+'</div>',"",4);
  if(c.form==="tablet")return thd("Messages",{right:K.iconBtn("plus",{kind:"tonal",label:"New"})})+'<div class="tw r3a"><div>'+list+'</div><div>'+th+'</div></div>'+ttabs(1);
  return thd("Messages",{right:K.iconBtn("plus",{kind:"tonal",label:"New"})})+pg(K.filterChips(["All","Dad","Mom","Grandma"],[0])+list+th,{tab:ttabs(1)});}}));

D("r3a-13-cal","teen","13 to 17: calendar",X(G13,{wide:true,
 desc:"A real calendar she edits from fourteen. House weeks sit as quiet colour behind her own events; each event she adds is hers until she chooses to share it. Work, school and driving land here, each with its own mark.",
 notes:[[1,"Month with the two house weeks as a fact, letter as well as colour."],[2,"Her events are marked as hers. Family events a guardian set are marked too."],[3,"Share with: Nobody, Mom, Dad, Both. Nobody is the default."],[4,"Nothing appears to anyone else until she says so."]],
 r:function(c){
  var l=K.calMonth({today:8,sel:14,marks:{1:"a",2:"a",3:"a",4:"b",5:"b",6:"b",7:"b",9:"mix",14:"ev",21:"ev"},names:{a:"Mom’s",b:"Dad’s"},n:1});
  var r=K.card(h5("Saturday 14")+gap()+'<div style="display:grid;gap:8px"'+n(2)+'>'+ev("Café shift","12:00–4:00","w",0,'<span class="r3a-priv">'+I("lock",11,2.2)+'Only me</span>')+ev("Driving lesson","5:00 · With Dad","b")+ev("Cousin’s party","7:00 · Family event","m")+'</div>')+
   K.card(h5("Add something")+gap()+K.formField({label:"What",value:"Study group"})+gap()+'<span class="r3a-eb">Share with</span>'+gap()+K.segmented(["Nobody","Mom","Dad","Both"],0,{full:true,n:3}),"",4);
  return tpair(c,l,r,thd("Calendar",{right:K.iconBtn("plus",{kind:"tonal",label:"Add"})}),ttabs(2));}}));

D("r3a-13-life","teen","13 to 17: school, work, driving",X(G13,{
 desc:"The concerns a fifteen-year-old actually has: a timetable and exam weeks, a part-time job, and learning to drive. They land in her calendar under her rules. Money is never shown (P6) and where she is is never shown (P3), in a car or anywhere.",
 notes:[[1,"School: her timetable, plus exam weeks as one quiet band. A parent sees it only if she shares it."],[2,"Work: shifts she types in. There is no pay and no money anywhere in the product."],[3,"Driving: lessons and a test date. Lessons with Dad are shared by both of them."],[4,"Said plainly on the page: the app never shows anyone where she is, driving or not."]],
 r:function(){return thd("School, work, driving",{back:true})+pg(
  K.card(h5("School")+gap()+frow("book","Timetable","Imported by you",1,K.chip("Mine",{tone:"ok",sm:true}),false)+frow("calendar","Exam weeks","Nov 24 to 27",0,K.toggle(false,{label:"Share exam weeks"}),false))+
  K.card(h5("Work")+gap()+frow("clock","Café","Sat 12:00–4:00 · Tue 4:30–8:00",2,K.toggle(false,{label:"Share shifts"}),false)+fine("Pay and money are not in Olive Branch."))+
  K.card(h5("Driving")+gap()+frow("calendar","Lessons with Dad","Saturdays 5:00 · shared",3,K.chip("Dad too",{sm:true}),false)+frow("flag","Test","Mar 4 · only you",0,"",false))+
  K.card(row({ic:"shield",title:"We never show where you are",sub:"Not while driving, not ever.",n:4}),"flat"),{tab:ttabs(3)});}}));

D("r3a-13-play","teen","13 to 17: downtime",X(G13,{
 desc:"Games, moved to the back and made plain. Chess with Dad across a week, Sunday Uno with Mom and Grandma, crosswords for one. A list, not a tile grid. She can hide the whole section from her Today.",
 notes:[[1,"Open games, with the person and the state in words. No timers, no “you are keeping him waiting”."],[2,"Things to start, in a list. Same games as the younger bands, without mascots or cheering."],[3,"Nothing is scored, ranked or streaked (P2). A finished game is simply finished."],[4,"A switch to hide Downtime from Today. Proposed: it is hers to hide, not a guardian setting."]],
 r:function(){return thd("Downtime",{back:true,eyebrow:"Today"})+pg(
  K.sectionLabel("Open")+K.card(frow("grid","Chess with Dad","Your move · saved 3 days",1)+frow("dice","Uno, Sunday","Mom and Grandma · 6:00 PM",0)+frow("target","Battleship with Mom","Her move",0))+
  K.sectionLabel("Start")+K.card(frow("search","Word chain","With anyone",2)+frow("layers","Connect Four","Two players",0)+frow("puzzle","Crossword","Just you",3)+frow("footprint","Scavenger hunt","In the house",0))+
  K.card(row({ic:"eyeoff",title:"Hide Downtime from Today",sub:"It stays under Me.",trail:K.toggle(false,{label:"Hide"}),n:4}),"flat"),{tab:ttabs(0)});}}));

D("r3a-13-studio","teen","13 to 17: studio",X(G13,{
 desc:"The creative space, where she is the author. A voice memo, a photo, a few lines, a drawing, a letter to herself at eighteen, a message banked for a parent’s birthday or deployment. The direction reverses: she makes it, they receive it.",
 notes:[[1,"Five ways to make something. No suggestions, no templates, no “inspiration”."],[2,"A sealed letter to herself opens on a date she picks, at least a year away. It is always kept (§21.4)."],[3,"Banking for a parent: she records ahead for a birthday or a time he is away. Delivered on her schedule."],[4,"What she makes is hers. Sharing is a separate, deliberate step."]],
 r:function(){return thd("Studio",{eyebrow:"Make",right:K.avatar("I",{size:44})})+pg(
  '<div class="grid3"'+n(1)+'>'+[["mic","Voice"],["camera","Photo"],["pencil","Write"],["brush","Draw"],["letter","Letter"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>'+
  K.sectionLabel("Sealed")+K.card(frow("letter","To me at 18","Opens when you are 18 · sealed",2,K.chip("Sealed",{ic:"lock",sm:true}),false),"",2)+
  K.sectionLabel("For someone")+K.card(frow("send","For Dad’s birthday","Banked · delivers Mar 4",3,K.status("banked","Banked"),false)+frow("plus","Bank a message","For a birthday or a week away",0))+
  K.card(fine("What you make here is yours. Nothing is sent until you send it."),"flat",4),{tab:ttabs(3)});}}));

D("r3a-13-journal","teen","13 to 17: journal",X(G13,{
 desc:"Locked at thirteen, absolutely. No prompts, no moods, no streaks, no suggestions. A page that opens when she opens it and shows nothing to anyone else. If she wants a backup, she makes and holds it.",
 notes:[[1,"The state of the lock is the first thing: Only you. It is a fact on the page, not a promise in a policy."],[2,"Entries show a date and a few lines that only she can see. In the mock they are blurred."],[3,"No prompts and no “how are you feeling?”. Nothing suggests what to write, and nothing reads what she wrote."],[4,"A backup she holds. It is never sent to a parent, and no export route exists for anyone else (P7)."]],
 r:function(){return thd("Journal",{back:true,right:'<span class="r3a-priv"'+n(1)+'>'+I("lock",12,2.2)+'Only you</span>'})+pg(
  K.card('<div style="display:grid;gap:12px"'+n(2)+'>'+["Nov 7","Nov 3","Oct 29"].map(function(d){return '<div><span class="r3a-eb">'+d+'</span><div class="r3a-lines r3a-blur" style="margin-top:6px"><i></i><i></i><i></i></div></div>';}).join("")+'</div>')+
  K.btn("New entry",{full:true,size:"lg",ic:"pencil",n:3})+K.card(frow("download","Keep your own backup","On your device only",4),"flat")+fine("Nobody suggests what to write. Nothing here is read."),{tab:ttabs(3)});}}));

D("r3a-13-support","teen","13 to 17: support",X(G13,{
 desc:"A page for when things are heavy. It names no condition and gives no assessment. It lists people she picked, a few outside services, and the emergency number. Opening it leaves no trace anyone else can see.",
 notes:[[1,"The first thing is people she chose, with a plain “message”. She sets them from Me, not a parent."],[2,"Outside services in her country, labelled by what they are, with sample numbers here."],[3,"Things people find helpful: not exercises assigned to her. Short, kind, optional."],[4,"The last line: opening this page is not recorded or reported. There is no history on her side or theirs."]],
 r:function(){return thd("Support",{back:true})+pg(
  K.card(h5("People you chose")+gap()+K.row({av:pav("Mom",44),title:"Mom",sub:"Message or call",go:true,n:1})+K.row({av:pav("Grandma",44),title:"Grandma",sub:"Message or call",go:true})+K.row({av:K.avatar("Co",{size:44,tone:"info"}),title:"Coach Reyes",sub:"A trusted adult you added",go:true}))+
  K.card(h5("Someone outside the family")+gap()+frow("phone","Teen helpline","Free, any hour (sample)",2)+frow("chat","Text a counsellor","Sample number",0)+frow("warn","If you are in danger now","Your local emergency number",0),"",2)+
  K.card(h5("Things that help")+gap()+'<div style="display:flex;flex-wrap:wrap;gap:6px"'+n(3)+'>'+["Breathe","Walk","Music","Write it down","Talk it out"].map(function(t){return K.chip(t,{sm:true});}).join("")+'</div>')+
  K.card(row({ic:"lock",title:"Not recorded, not reported",sub:"No one sees that you opened this page.",n:4}),"flat"),{tab:ttabs(3)});}}));

D("r3a-13-people","teen","13 to 17: my people",X(G13,{wide:true,
 desc:"Family structure, told straight. Who lives where, how the weeks work, why it is that way, in her guardians’ own words and nobody else’s. She can say how it is working for her, and the note goes to both of them together.",
 notes:[[1,"Homes and people under the names she uses, with a plain line about how each can reach her."],[2,"The rhythm as a fact with its source: alternating weeks. If a court order sets it, that is said, as a guardian wrote it."],[3,"A note from Jess and Marcus, written by them. The app generates nothing about the family, a partner or a change."],[4,"“Tell us how it is going” goes to both guardians at once. She is never asked to take a side."]],
 r:function(c){
  var l=K.card(h5("Where you live")+gap()+frow("home","Mom’s house","Mom · you sleep here Mon to Thu",1)+frow("home","Dad’s house","Dad, Dana · Fri to Sun",0)+frow("heart","Near and far","Grandma, Aunt Rae",0),"")+K.card('<span class="r3a-eb">How the weeks work</span>'+gap()+p("Alternating weeks, with the exchange on Sunday at 6:00 PM.")+gap()+fine("Set by your parents’ agreement, March 2025."),"",2);
  var r=K.card('<span class="r3a-eb">From Mom and Dad</span>'+gap()+p("“We agreed this together. It can change when you are 16, and we will ask you first.”")+gap()+fine("Written by Jess and Marcus. Olive Branch did not write this."),"tint",3)+K.card(h5("Tell us how it is going")+gap()+p("This goes to both of them at once. You do not have to explain.")+gap()+K.btn("Write a note",{kind:"tonal",full:true,ic:"pencil",n:4}));
  return tpair(c,l,r,thd("My people",{back:true}),ttabs(3));}}));

D("r3a-13-me","teen","13 to 17: me",X(G13,{
 desc:"Where the settings-like things live, because the child shell has none. Each row is something that has become hers by a rung, and says which one. A row for a rung she has not reached is plainly listed, with its age, not hidden.",
 notes:[[1,"Her photo and name come from her. A name she sets is not corrected by anyone."],[2,"Each row carries the rung that gave it to her. The row for a later rung shows its age, in grey, and nothing else."],[3,"Privacy and the consent log are the two honest rows: what they can see, and what she was asked."],[4,"Display and access settings are hers: text size, a reading face, reduced motion. Proposed."]],
 r:function(){return thd("Me",{right:'<span'+n(1)+'>'+K.avatar("I",{size:44})+'</span>'})+pg(
  K.card(frow("eye","Privacy","What Mom and Dad can see",3)+frow("receipt","Consent log","Every ask and every answer",3)+frow("clock","Free times","Rung 15 · you decide",2,K.chip("Mine",{tone:"ok",sm:true})),"",3)+
  K.card(frow("book","Journal","Rung 13 · only you",2,K.chip("Mine",{tone:"ok",sm:true}))+frow("calendar","Calendar","Rung 14 · you edit it",2,K.chip("Mine",{tone:"ok",sm:true}))+frow("image","Archive","Rung 16 · opens at 16",2,K.chip("At 16",{sm:true}))+frow("download","Your own copy","Rung 17 · opens at 17",2,K.chip("At 17",{sm:true})),"",2)+
  K.card(frow("sliders","Display and access","Text, reading face, motion",4,prop()))+K.card(frow("layers","What is yours, and when","The whole ladder",0),"flat"),{tab:ttabs(3)});}}));

D("r3a-13-ladder","teen","13 to 17: what is yours",X(G13,{wide:true,
 desc:"The ladder as she sees it at fifteen: each step, what it gave her, how she was told, and what is next. Honest about the next ones, and about the one that stays with her guardians forever.",
 notes:[[1,"Done, now and next. Each step says how she was told, so she can find the page again."],[2,"Rung 15 is marked as the one her guardians were told about. Telling her this is part of the honesty."],[3,"Nothing here can be lowered by anyone. Moving a rung later takes both guardians together."],[4,"The last row is the one that stays with her guardians: the send-time guard, on their side, forever."]],
 r:function(c){
  var l=K.card(K.timeline([{time:"10",title:"Your list",sub:"Told to you on the list tile",state:"done"},{time:"13",title:"Your journal",sub:"A page, once. Nobody else was told",state:"done"},{time:"14",title:"Your calendar",sub:"A line on the calendar. Nobody else was told",state:"done"},{time:"15",title:"Your free times",sub:"A page and a preview. Mom and Dad were told once, the next day",state:"now"}],{n:1}),"",2);
  var r=K.card(K.timeline([{time:"16",title:"Your archive",sub:"Opens on your 16th birthday",state:"next"},{time:"17",title:"Your own copy",sub:"Opens on your 17th birthday",state:"next"},{time:"18",title:"Everything",sub:"Guardianship closes",state:"next"}]))+K.notice({tone:"info",text:"Nobody can lower a step. Both of your guardians together can ask to move one later; never earlier.",n:3})+K.card(row({ic:"clock",title:"Send-time guard",sub:"Stays on your guardians’ side, always",n:4}),"flat");
  return tpair(c,l,r,thd("What is yours",{back:true}),ttabs(3));}}));

D("r3a-13-ease","teen","13 to 17: display and access",X(G13,{
 desc:"Accessibility as hers. Text size, a reading face, reduced motion, high contrast, captions, and screen reader hints, on a preview that updates as she goes. Proposed: from thirteen these are her own choices and nobody is told, because they say nothing about her but how she reads.",
 notes:[[1,"The preview is live. Move a slider, the sentence changes."],[2,"A reading face made for dyslexia, with spacing options. One switch."],[3,"Reduced motion and high contrast, separate. Nothing is bundled into a profile."],[4,"Marked Proposed: today these are guardian settings. Whether a teen owns them is a product decision."]],
 r:function(){return thd("Display",{back:true,eyebrow:"Access"})+pg('<div>'+prop()+'</div>'+
  K.card('<p style="font:500 17px/1.6 var(--font-body);margin:0" data-n="1">The fox sat on the hill and watched the moon get bigger.</p>')+
  K.card(K.sliderRow({title:"Text size",value:62,text:"Large",l:"A",r:"A"})+K.toggleRow({title:"Reading face",sub:"Wider spacing, made for dyslexia",on:true,ic:"book",n:2})+K.toggleRow({title:"Reduce motion",sub:"No sliding or fading",on:false,ic:"hand",n:3})+K.toggleRow({title:"High contrast",on:false,ic:"eye"})+K.toggleRow({title:"Captions on video",on:true,ic:"cc"}))+
  K.card(fine("These are yours. No one is told you changed them."),"flat",4),{tab:ttabs(3)});}}));

D("r3a-13-offline","teen","13 to 17: offline",X(G13,{
 desc:"No connection, said plainly. Her calendar, journal and saved games open. A message she writes waits in the outbox with its status in words and an icon. Nothing is lost and nothing is hidden.",
 notes:[[1,"One line at the top that says what is true and what still works."],[2,"Her message waits. It is marked queued, with an icon and a word, and a way to cancel it."],[3,"The calendar is fully usable offline, because it is stored on the device first."]],
 r:function(){return thd("Messages",{right:K.iconBtn("plus",{kind:"tonal",label:"New"})})+pg(
  K.offlineBanner({text:"You are offline",sub:"Your calendar, journal and games still work.",action:"Retry"}).replace('class="offline"','class="offline" data-n="1"')+
  K.card(K.row({av:pav("Dad",44),title:"Dad",sub:"Fine. Can I drive the whole way?",go:true,n:2})+'<div style="padding:0 0 4px 56px">'+K.status("queued","Queued")+' <span class="r3a-fine">Sends when you are online</span></div>'+K.row({av:pav("Mom",44),title:"Mom",sub:"Sent a photo",go:true}))+
  K.card(frow("calendar","Calendar","Works offline",3)+frow("book","Journal","Works offline",0)),{tab:ttabs(1)});}}));

D("r3a-13-guardian","guardian","Ivy at 15: what you see",X(GA,{wide:true,
 desc:"The guardian’s view of a fifteen-year-old, with the contract on the page. You see her free times as a soft glow, events she chose to share, and the things you set. You do not see her messages with anyone else, her journal, or where she is.",
 notes:[[1,"Her free times, as she published them. A glow, never a reason."],[2,"Events she shared with you. A shared event says so."],[3,"The things you cannot see are listed under the same heading as the things you can, with locks."],[4,"You can ask. She can say no, and the answer is final for a week."]],
 r:function(c){
  var l='<div class="r3a-now" data-n="1">'+pav("Ivy",40)+'<span class="rtxt" style="min-width:0"><b>Ivy is free from 7:00 PM</b><br><small style="color:var(--ink3)">She published this</small></span>'+K.chip("Free",{tone:"ok",ic:"check",sm:true})+'</div>'+K.card(h5("Shared with you")+gap()+'<div style="display:grid;gap:8px"'+n(2)+'>'+ev("Dentist","Tue 3:00 · Shared by Ivy","")+ev("Driving lesson","Sat 5:00 · With you","b")+'</div>');
  var r=K.card(h5("What stays with Ivy")+gap()+row({ic:"lock",title:"Her journal",sub:"Nobody can open it",trail:v("no")})+row({ic:"lock",title:"Her messages with Jess",sub:"Only the two of them",trail:v("no")})+row({ic:"lock",title:"Where she is",sub:"Never",trail:v("no")}),"",3)+K.btn("Ask Ivy to share something",{kind:"tonal",full:true,ic:"hand",n:4});
  return two(c,l,r,ghd("Ivy at 15",{eyebrow:"Sample"}),gtabs(3));}}));

/* =========================================================================== 18: TAKE YOUR DATA AND GO */
D("r3a-18-heads-g","guardian","Ivy turns 18 in 90 days",X(G18,{wide:true,
 desc:"Ninety days before, both guardians are told the same thing in the same words. What will close, what stays, and what is Ivy’s to decide. Nothing here asks the guardians to do anything except, if they want, to write her a note.",
 notes:[[1,"Both guardians get this at once, with the same words. Nobody is told first."],[2,"A plain list of what will change on the day. Her data is hers; the guardian shell closes."],[3,"What stays with you: your own account, your own messages as sent, the record of what you agreed."],[4,"A note to her, in your own words, kept for the day. Optional, and she can read it or not."]],
 r:function(c){
  var l=K.notice({tone:"pri",title:"Ivy turns 18 on Dec 9",text:"Guardianship closes that day. Marcus has the same note.",n:1})+K.card(h5("On the day")+gap()+chg([["hers","Everything becomes hers","Her messages, photos, archive and journal."],["fade","Guardian tools close","Her calendar, her devices and her availability are no longer yours to manage."],["keep","Your account stays","So do your own messages, as you sent them."]],2));
  var r=K.card(h5("Write her a note")+gap()+K.formField({label:"For the day she is 18",value:"",ph:"In your own words"})+gap()+fine("She can read it, or not, and it is kept with her archive. Marcus can write one too."),"",4)+K.card(frow("download","What she gets","Plain list of everything",3)+frow("users","Staying in touch","Only if you both choose",0));
  return two(c,l,r,ghd("Ivy turns 18",{eyebrow:"90 days"}),gtabs(3));}}));

D("r3a-18-heads-c","teen","18: in 90 days",X(G18,{wide:true,
 desc:"From her side: ninety days before, a quiet page that says what will be hers and that nothing has to be decided now. She can read it, or not. Neither guardian is told whether she has.",
 notes:[[1,"The first line is a fact, said once."],[2,"Three paths, listed. She does not have to pick one today."],[3,"What she gets is a link away, in plain words."],[4,"No one is told that she opened this page."]],
 r:function(c){
  var l=lead("In 90 days, this is all yours.").replace("<p ",'<p data-n="1" ')+p("Your messages, photos, archive and journal. You decide what happens to them. Nobody else.")+K.card(frow("download","Take your data and go","You keep a copy. We delete ours.",2)+frow("leaf","Keep it as your archive","You look after it. Your parents cannot open it.",2)+frow("users","Stay in touch","Only if you and they both choose",2),"",2);
  var r=K.card(frow("receipt","What you get, in plain words","Counts, formats, what is not included",3))+K.notice({tone:"info",text:"No one is told whether you read this.",n:4});
  return tpair(c,l,r,thd("Turning 18",{back:true}),ttabs(3));}}));

D("r3a-18-paths","teen","18: your choices",X(G18,{
 desc:"The three paths, equally respected. Plain consequences for each, no default and no nudge. A fourth, staying in touch, is separate from the others and needs both sides.",
 notes:[[1,"None is marked recommended. The product serves all three equally (§21.6)."],[2,"Each says what happens to her data and what happens to her guardians’ view in one line."],[3,"Take and go deletes our copy after thirty days. She can still come back within that window."],[4,"Staying in touch is a different question and has its own page. It does not depend on which path she took."]],
 r:function(){return thd("Your choices",{back:true})+pg(
  sheetOpts([opt("Take your data and go","You get everything. Thirty days later we delete our copy.",false,{n:1}),opt("Keep it as your archive","You look after it. Your parents cannot open it.",false,{n:2}),opt("Both","Take a copy now and keep the archive going.",false)])+
  K.notice({tone:"info",text:"None of these is marked as better. Moving between them is fine for thirty days.",n:3})+K.card(frow("users","Staying in touch","Separate. Needs both sides.",4)),{tab:ttabs(3)});}}));

D("r3a-18-whatyouget","teen","18: what you get",X(G18,{wide:true,
 desc:"The plain-words list of what is in her copy and what is not, with the amount, the formats and the place it goes. Nothing is hidden in an “other” row. Taking it does not notify anyone.",
 notes:[[1,"Counts, not categories. She sees the size of the thing."],[2,"Formats she can open anywhere: a folder of ordinary files, a web page, a spreadsheet."],[3,"What is not included, and why: messages between her parents are theirs."],[4,"It goes to her device or her own cloud. It does not go to any grown-up."]],
 r:function(c){
  var l=K.card(h5("What is in it")+gap()+K.kv([["Messages","4,812"],["Photos and drawings","1,206"],["Voice notes","212"],["Videos from Mom and Dad","148"],["Letters to yourself","3"],["Your journal","Yours only"],["Your calendar","Since you were 14"]],{ruled:true}),"",1);
  var r=K.card(h5("The shape of it")+gap()+K.kv([["Format","Folders, web page, spreadsheet"],["Size","About 3.4 GB"],["Goes to","Your device, or your own cloud"]],{ruled:true}),"",2)+K.card(h5("What is not")+gap()+fine("Messages between your parents, anything they wrote about each other, and what they agreed about money. Those are theirs."),"flat",3)+K.btn("Make my copy",{full:true,size:"lg",ic:"download"})+fine("Nobody is told.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"');
  return tpair(c,l,r,thd("What you get",{back:true}),ttabs(3));}}));

D("r3a-18-stay","teen","18: staying in touch",X(G18,{wide:true,
 desc:"If both sides choose it. She offers what she is willing to share, they offer what they would like, and only the overlap happens. Either side can end it with one tap, with no reason asked.",
 notes:[[1,"She goes first. What she offers is on the left; what they asked for is on the right."],[2,"Only what both sides choose goes live. Everything else stays shut."],[3,"The state is plain: waiting for Marcus, ready, ended. No guilt, no nudging."],[4,"One tap ends it, either side, any time. No reason, no notice period."]],
 r:function(c){
  var l=K.card(h5("What you offer")+gap()+K.checkRow({title:"Messages",sub:"A thread with Mom and one with Dad",on:true})+K.checkRow({title:"Calls",sub:"They can ring you",on:true})+K.checkRow({title:"A shared calendar",sub:"Dates you both choose",on:false}),"",1);
  var r=K.card(h5("What they asked for")+gap()+row({av:pav("Mom",44),title:"Mom",sub:"Messages, calls",trail:K.status("sent","Ready")})+row({av:pav("Dad",44),title:"Dad",sub:"Messages, calls, calendar",trail:K.status("queued","Waiting")}),"",3)+K.notice({tone:"info",text:"Only what you both choose goes live.",n:2})+K.btn("End this any time",{kind:"ghost",full:true,n:4});
  return tpair(c,l,r,thd("Staying in touch",{back:true}),ttabs(3));}}));

D("r3a-18-goodbye","teen","18: your last day here",X(G18,{
 desc:"A dignified goodbye, not a sale. A quiet scene, the notes her guardians wrote in their own words, her copy ready and a clear next step. Nothing asks her to stay and nothing counts what she did here.",
 notes:[[1,"One scene she knows, with the last line in plain words. No confetti, no mascot."],[2,"Notes from her guardians, if they wrote any. They are in their words, not the app’s."],[3,"Two clear choices: take and go, or keep going as her own archive."],[4,"No numbers, no summary of what she did, no “your year in review”. It is a goodbye, not a scoreboard."]],
 r:function(){return thd("",{})+pg(
  '<div class="r3a-cr"'+n(1)+'><b>You grew up here.</b><small>It is yours now.</small></div>'+
  K.card('<span class="r3a-eb">From Mom</span>'+gap()+p("“I am so proud of you. Call me tomorrow.”")+gap()+'<span class="r3a-eb">From Dad</span>'+gap()+p("“Drive safe. I mean it.”")+gap()+fine("Written by Jess and Marcus."),"tint",2)+
  K.btn("Take my data and go",{full:true,size:"lg",ic:"download",n:3})+K.btn("Keep it as my archive",{kind:"tonal",full:true,ic:"leaf"})+fine("Nothing is counted or summarised.").replace('class="r3a-fine"','class="r3a-fine" data-n="4"'),{tab:""});}}));

D("r3a-18-after-g","guardian","After 18, for you",X(G18,{
 desc:"What the guardian sees the day after: Ivy’s account is hers, the guardian shell is closed and, if she chose it, a channel to her stays open. What you keep is stated plainly, including the record of what the two of you agreed.",
 notes:[[1,"A calm summary, no feelings engineering. It says what is closed and what is yours."],[2,"The parent-to-parent record stays, unchanged (P8). It is not Ivy’s, and no one can edit it."],[3,"If she chose to stay in touch, it appears here as a thread. Nothing else of hers does."],[4,"A note she left for you, if she did. Optional, hers to write."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Dec 10",title:"Today"})+pg(
  K.notice({tone:"pri",title:"Ivy is 18",text:"Her account is hers now. Guardian tools for Ivy have closed.",n:1})+
  K.card(chg([["keep","Your record with Jess stays","What the two of you agreed and logged is unchanged."],["keep","Your own account stays","So do the messages you sent her, as you sent them."],["fade","Ivy’s calendar, devices and free times","No longer in your hands."]],2))+
  K.card(row({av:pav("Ivy",46),title:"Ivy",sub:"Messages and calls, by her choice",go:true,n:3})+row({ic:"letter",title:"A note from Ivy",sub:"If she wrote one",go:true,n:4})),{tab:gtabs(0)});}}));

})();
