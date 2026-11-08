/* screens-r2-start: Round 2, "Start". The flows a real family needs before anything else works:
   sign in, create a family, invite the other parent, pair her tablet, and the quiet account moments around them.
   Owned by one agent. Local helpers and one injected <style> block (classes prefixed r2s-); nothing outside .ob is touched.
   All colours are theme variables, except the QR code, which must stay dark-on-light to be scannable. */
(function(){"use strict";var K=OB,I=K.ico,D=K.def,E=K.esc,N=K.n;

/* ------------------------------------------------------------------ local styles -- */
var CSS=[
".ob .r2s{display:contents}",
".ob .r2s .btn{white-space:normal;text-align:center;line-height:1.15;padding-top:10px;padding-bottom:10px;height:auto}",
".ob .r2s .btn{min-height:48px}",
".ob .r2s .btn.lg{font-size:16.5px;min-height:56px;padding-left:16px;padding-right:16px}",
".ob.f-cover .r2s .btn.lg{font-size:15px}",
".ob .r2s .r2s-top{display:flex;gap:12px;align-items:center;padding:6px 14px;flex:none;min-height:58px}",
".ob .r2s .r2s-top .cbtn{width:48px;height:48px}",
".ob .r2s .r2s-top .ttl b{font-size:21px}",
".ob .r2s .r2s-stp{flex:1;min-width:0;display:grid;gap:6px}",
".ob .r2s .r2s-bars{display:grid;grid-auto-flow:column;grid-auto-columns:1fr;gap:5px}",
".ob .r2s .r2s-bars i{height:5px;border-radius:5px;background:var(--surface3)}",
".ob .r2s .r2s-bars i.d{background:var(--pri)}",
".ob.f-tablet .r2s .r2s-stp{max-width:420px}",
".ob .r2s .r2s-stp small{font:700 11.5px/1 var(--font-body);color:var(--ink3)}",
".ob .r2s .r2s-h{display:grid;gap:7px;padding:4px 2px 2px}",
".ob .r2s .r2s-eye{font:700 10.5px/1 var(--font-mono);letter-spacing:.09em;text-transform:uppercase;color:var(--ink3)}",
".ob .r2s .r2s-h1{font:800 27px/1.08 var(--font-display);letter-spacing:-.02em;margin:0;color:var(--ink);text-wrap:balance}",
".ob.f-cover .r2s .r2s-h1{font-size:22px}",
".ob .r2s .r2s-lede{margin:0;font-size:14.5px;line-height:1.45;color:var(--ink2)}",
".ob .r2s .r2s-foot{flex:none;padding:10px 16px 18px;display:grid;gap:4px;background:linear-gradient(to top,var(--bg) 82%,transparent)}",
".ob .r2s .r2s-link{background:none;border:0;min-height:48px;padding:0 12px;font:700 14.5px/1.2 var(--font-body);color:var(--pri);border-radius:14px;display:inline-flex;gap:7px;align-items:center;justify-content:center;text-align:center;cursor:pointer}",
".ob .r2s .r2s-link.bad{color:var(--bad)}",
".ob .r2s .r2s-link.mute{color:var(--ink2)}",
".ob .r2s .r2s-fine{font-size:12.5px;line-height:1.4;color:var(--ink3);text-align:center;margin:0}",
".ob .r2s .r2s-f .field{min-height:58px;align-content:center}",
".ob .r2s .r2s-f.on .field{border-color:var(--pri);box-shadow:0 0 0 3px color-mix(in srgb,var(--pri) 22%,transparent)}",
".ob .r2s .r2s-f.ok .field{border-color:var(--ok)}",
".ob .r2s .r2s-f.bad .field{border-color:var(--bad)}",
".ob .r2s .r2s-f.lock .field{background:var(--surface2);border-color:transparent}",
".ob .r2s .r2s-caret{display:inline-block;width:2px;height:18px;background:var(--pri);margin-left:2px;vertical-align:-3px;border-radius:2px}",
".ob .r2s .r2s-help{display:flex;gap:5px;align-items:flex-start;margin:6px 4px 0;font-size:12.5px;line-height:1.4;color:var(--ink3)}",
".ob .r2s .r2s-f.ok .r2s-help{color:var(--ok)}",
".ob .r2s .r2s-f.bad .r2s-help{color:var(--bad)}",
".ob .r2s .r2s-lab{font:700 12.5px/1.2 var(--font-body);color:var(--ink2);margin:2px 4px 8px}",
".ob .r2s .r2s-pick{display:flex;flex-wrap:wrap;gap:8px}",
".ob .r2s .r2s-opt{min-height:48px;padding:0 16px;border-radius:99px;border:1.5px solid var(--outline);background:var(--surface);font:700 14.5px/1 var(--font-body);color:var(--ink);display:inline-flex;gap:6px;align-items:center}",
".ob .r2s .r2s-opt.on{background:var(--priC);color:var(--onPriC);border-color:var(--pri)}",
".ob .r2s .r2s-rc{display:flex;gap:12px;align-items:flex-start;padding:13px 14px;border-radius:18px;border:1.5px solid var(--outline);background:var(--surface);min-height:56px}",
".ob .r2s .r2s-rc.on{border-color:var(--pri);background:color-mix(in srgb,var(--priC) 55%,var(--surface))}",
".ob .r2s .r2s-rc>span:nth-child(2){display:grid;gap:2px;min-width:0;flex:1}",
".ob .r2s .r2s-rc b{font-size:14.5px;font-weight:700}",
".ob .r2s .r2s-rc small{font-size:12.5px;color:var(--ink2);line-height:1.4}",
".ob .r2s .r2s-rd{width:22px;height:22px;border-radius:50%;border:2px solid var(--ink3);flex:none;margin-top:1px;display:grid;place-items:center}",
".ob .r2s .r2s-rc.on .r2s-rd{border-color:var(--pri)}",
".ob .r2s .r2s-rc.on .r2s-rd::after{content:\"\";width:10px;height:10px;border-radius:50%;background:var(--pri)}",
".ob .r2s .r2s-cb{display:flex;gap:12px;align-items:flex-start;padding:4px 2px;min-height:48px}",
".ob .r2s .r2s-cb .bx{width:24px;height:24px;border-radius:8px;border:2px solid var(--ink3);flex:none;display:grid;place-items:center;margin-top:1px}",
".ob .r2s .r2s-cb.on .bx{background:var(--pri);border-color:var(--pri);color:var(--onPri)}",
".ob .r2s .r2s-cb span.t{font-size:13.5px;line-height:1.42;color:var(--ink)}",
".ob .r2s .r2s-kp{display:grid;grid-template-columns:repeat(3,minmax(0,64px));gap:8px 14px;justify-content:center}",
".ob .r2s .r2s-kp button{height:52px;border-radius:18px;border:0;background:var(--surface);box-shadow:var(--shadow1);font:800 22px var(--font-display);color:var(--ink);display:grid;place-items:center;padding:0}",
".ob .r2s .r2s-kp i{display:block}",
".ob.f-cover .r2s .r2s-kp{gap:6px 10px}",
".ob .r2s .r2s-hero{position:relative;height:84px;border-radius:26px;overflow:hidden;box-shadow:var(--shadow2)}",
".ob.f-cover .r2s .r2s-hero{height:92px}",
".ob .r2s .r2s-hero .scene{height:100%;width:100%;border-radius:0}",
".ob .r2s .r2s-hero .lg{position:absolute;left:12px;top:12px;filter:drop-shadow(0 2px 6px rgba(0,0,0,.25))}",
".ob .r2s .r2s-tabl{display:grid;grid-template-columns:minmax(0,.82fr) minmax(0,1.18fr);gap:16px;padding:0 16px 14px;flex:1;min-height:0}",
".ob .r2s .r2s-aside{border-radius:var(--r3);background:var(--priC);color:var(--onPriC);padding:16px;display:grid;gap:12px;align-content:start;overflow:hidden;min-height:0}",
".ob .r2s .r2s-aside .scene{border-radius:16px}",
".ob .r2s .r2s-aside h4{font:800 17px/1.2 var(--font-display);margin:0}",
".ob .r2s .r2s-aside p{margin:0;font-size:13.5px;line-height:1.45}",
".ob .r2s .r2s-ar{display:flex;gap:9px;align-items:flex-start;font-size:13px;line-height:1.4}",
".ob .r2s .r2s-ar .ico{margin-top:1px}",
".ob .r2s .r2s-main{display:flex;flex-direction:column;min-height:0}",
".ob .r2s .r2s-main .scroll{padding-left:0;padding-right:0}",
".ob .r2s .r2s-main .r2s-foot{padding-left:0;padding-right:0}",
".ob .r2s .r2s-code{font:800 34px/1 var(--font-mono);letter-spacing:.12em;color:var(--ink);font-variant-numeric:tabular-nums}",
".ob.f-cover .r2s .r2s-code{font-size:28px}",
".ob .r2s .r2s-qrc{display:grid;justify-items:center;gap:10px;padding:16px;border-radius:var(--r3);background:var(--surface);border:1px solid color-mix(in srgb,var(--outline) 70%,transparent);box-shadow:var(--shadow2)}",
".ob .r2s .r2s-qrf{background:#fff;padding:10px;border-radius:18px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.08)}",
".ob .r2s .r2s-qrf svg{display:block}",
".ob .r2s .r2s-num{width:28px;height:28px;border-radius:50%;background:var(--priC);color:var(--onPriC);font:800 13px var(--font-display);display:grid;place-items:center;flex:none}",
".ob .r2s .r2s-step{display:flex;gap:12px;align-items:flex-start;padding:9px 0;font-size:14px;line-height:1.4;color:var(--ink)}",
".ob .r2s .r2s-wait{display:flex;gap:10px;align-items:center;justify-content:center;font:700 13.5px/1.2 var(--font-body);color:var(--ink2)}",
".ob .r2s .r2s-wait i{width:8px;height:8px;border-radius:50%;background:var(--pri);opacity:.35;display:inline-block}",
".ob .r2s .r2s-wait i:nth-child(2){opacity:.6}.ob .r2s .r2s-wait i:nth-child(3){opacity:.9}",
"@media (prefers-reduced-motion:no-preference){.ob .r2s .r2s-wait i{animation:r2sw 1.6s ease-in-out infinite}.ob .r2s .r2s-wait i:nth-child(2){animation-delay:.2s}.ob .r2s .r2s-wait i:nth-child(3){animation-delay:.4s}@keyframes r2sw{0%,100%{opacity:.3}50%{opacity:1}}}",
".ob .r2s .r2s-leaf{border-radius:var(--r3);background:var(--priC);overflow:hidden;display:grid;justify-items:center;padding:10px 10px 14px;gap:6px}",
".ob .r2s .r2s-leaf svg{display:block;width:100%;height:auto;max-height:150px}",
".ob .r2s .r2s-pair{display:flex;gap:14px;align-items:center;justify-content:center;margin-top:-6px}",
".ob .r2s .r2s-dev{display:grid;gap:10px}",
".ob .r2s .r2s-dev .hd{display:flex;gap:12px;align-items:center;min-width:0}",
".ob .r2s .r2s-dev .act{display:flex;gap:8px;justify-content:space-between;align-items:center;border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent);padding-top:8px;margin-top:2px}",
".ob .r2s .r2s-dev .act span{font-size:12.5px;color:var(--ink3);flex:1;min-width:0}",
".ob .r2s .r2s-rm{min-height:48px;padding:0 16px;border-radius:14px;border:0;background:var(--badC);color:var(--bad);font:700 14px var(--font-body);display:inline-flex;gap:6px;align-items:center;flex:none}",
".ob .r2s .r2s-tl{display:grid;gap:0}",
".ob .r2s .r2s-tl>div{display:grid;grid-template-columns:28px 1fr;gap:12px;padding:0 0 14px;position:relative}",
".ob .r2s .r2s-tl>div:last-child{padding-bottom:0}",
".ob .r2s .r2s-tl>div::before{content:\"\";position:absolute;left:13px;top:28px;bottom:2px;width:2px;background:var(--outline)}",
".ob .r2s .r2s-tl>div:last-child::before{display:none}",
".ob .r2s .r2s-tl b{font-size:14.5px;display:block}.ob .r2s .r2s-tl small{font-size:13px;color:var(--ink2);line-height:1.4;display:block;margin-top:1px}",
".ob .r2s .r2s-quote{border-left:3px solid var(--pri);padding:2px 0 2px 12px;font-size:13.5px;line-height:1.45;color:var(--ink);margin:6px 0 0}",
".ob .r2s .r2s-sh{left:50%;right:auto;width:100%;max-width:460px;transform:translateX(-50%);gap:12px;padding-bottom:22px}",
".ob .r2s .r2s-dim{opacity:.9}",
/* child */
".ob.child .r2s .r2s-ch{font:800 36px/1.05 var(--font-display);letter-spacing:-.02em;margin:0;color:var(--ink);text-align:center}",
".ob.child .r2s .r2s-chero{position:relative;border-radius:30px;overflow:hidden;box-shadow:var(--shadow2);height:150px}",
".ob.child .r2s .r2s-chero .scene{height:100%;width:100%;border-radius:0}",
".ob.child .r2s .r2s-wave{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:84px;height:84px;border-radius:50%;background:var(--surface);color:var(--priD);display:grid;place-items:center;box-shadow:var(--shadow2)}",
".ob.child .r2s .r2s-cwrap{flex:1;min-height:0;display:grid;align-content:center;justify-items:center;gap:14px;padding:6px 20px 12px}",
".ob.child .r2s .r2s-cwrap>*{max-width:100%}",
".ob.child .r2s .r2s-cwrap .r2s-chero{width:100%}",
".ob.child .r2s .r2s-who{display:flex;gap:12px;align-items:center;justify-content:center;color:var(--pri)}",
".ob.child .r2s .r2s-cl{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:22px;align-items:center;flex:1;min-height:0;padding:6px 26px 18px}",
".ob.child .r2s .r2s-cl .r2s-cwrap{padding:0}",
".ob.child .r2s .r2s-cl .r2s-chero{height:100%;min-height:260px}",
".ob.child .r2s .r2s-big{width:112px;height:112px;border-radius:36px;background:var(--priC);color:var(--onPriC);display:grid;place-items:center}",
".ob.child .r2s .r2s-cfoot{flex:none;padding:6px 20px 20px;display:grid;gap:8px}",
".ob.child .r2s .btn{min-height:64px}",
".ob.child .r2s .speak{min-height:64px;padding:0 22px;font-size:16px}"
].join("\n");
if(typeof document!=="undefined"&&!document.getElementById("r2s-style")){var st=document.createElement("style");st.id="r2s-style";st.textContent=CSS;document.head.appendChild(st);}

/* --------------------------------------------------------------------- helpers -- */
function W(x){return '<div class="r2s">'+x+'</div>';}
function rtop(o){o=o||{};
 var mid=o.step?'<div class="r2s-stp" role="img" aria-label="Step '+o.step[0]+' of '+o.step[1]+'"><div class="r2s-bars">'+(function(){var s="";for(var i=1;i<=o.step[1];i++)s+='<i class="'+(i<=o.step[0]?"d":"")+'"></i>';return s;})()+'</div><small>Step '+o.step[0]+' of '+o.step[1]+(o.stepName?' · '+E(o.stepName):"")+'</small></div>'
  :'<div class="ttl">'+(o.eyebrow?'<small>'+E(o.eyebrow)+'</small>':"")+'<b>'+E(o.title||"")+'</b></div>';
 return K.sb()+'<div class="r2s-top">'+(o.back===false?"":'<button class="cbtn" aria-label="Back">'+I("chevL",20,2)+'</button>')+mid+(o.right||"")+'</div>';}
function H(title,lede,eyebrow,n){return '<div class="r2s-h"'+N(n)+'>'+(eyebrow?'<div class="r2s-eye">'+E(eyebrow)+'</div>':"")+'<h1 class="r2s-h1">'+E(title)+'</h1>'+(lede?'<p class="r2s-lede">'+E(lede)+'</p>':"")+'</div>';}
function F(label,val,o){o=o||{};var caret='<span class="r2s-caret"></span>';
 var v=val?E(val)+(o.state==="on"?caret:""):(o.state==="on"?caret+'<i class="ph">'+E(o.ph||"")+'</i>':"");
 return '<div class="r2s-f'+(o.state?" "+o.state:"")+'"'+N(o.n)+'>'+K.field(label,v,{ic:o.ic,ph:o.ph})+(o.help?'<p class="r2s-help">'+(o.state==="ok"?I("check",14,2.4):o.state==="bad"?I("warn",14,2):"")+'<span>'+E(o.help)+'</span></p>':"")+'</div>';}
function pick(label,items,a,n){return '<div'+N(n)+'><div class="r2s-lab">'+E(label)+'</div><div class="r2s-pick">'+items.map(function(t,i){return '<span class="r2s-opt'+(i===a?" on":"")+'">'+(i===a?I("check",15,2.4):"")+E(t)+'</span>';}).join("")+'</div></div>';}
function rc(title,sub,on,n){return '<div class="r2s-rc'+(on?" on":"")+'"'+N(n)+'><span class="r2s-rd"></span><span><b>'+E(title)+'</b><small>'+E(sub)+'</small></span></div>';}
function cb(text,on,n){return '<div class="r2s-cb'+(on?" on":"")+'"'+N(n)+'><span class="bx">'+(on?I("check",16,2.8):"")+'</span><span class="t">'+text+'</span></div>';}
function kp(){var k=[1,2,3,4,5,6,7,8,9,"",0,"del"];return '<div class="r2s-kp">'+k.map(function(n){return n===""?'<i></i>':n==="del"?'<button aria-label="Delete the last digit">'+I("arrowL",22,2)+'</button>':'<button>'+n+'</button>';}).join("")+'</div>';}
function link(t,o){o=o||{};return '<button class="r2s-link'+(o.cls?" "+o.cls:"")+'"'+N(o.n)+'>'+(o.ic?I(o.ic,17,2):"")+E(t)+'</button>';}
function foot(inner){return '<div class="r2s-foot">'+inner+'</div>';}
function P(t,ic,n){return K.btn(t,{full:true,size:"lg",ic:ic,n:n});}
function ar(ic,t){return '<div class="r2s-ar">'+I(ic,17,2)+'<span>'+t+'</span></div>';}
function aside(scene,title,text,lines){return '<aside class="r2s-aside">'+K.scene(scene,300,150)+'<h4>'+E(title)+'</h4>'+(text?'<p>'+E(text)+'</p>':"")+(lines||[]).map(function(l){return ar(l[0],E(l[1]));}).join("")+'</aside>';}
/* generic frame: phone and cover are one scrolling column with a pinned action; the tablet may add a left aside */
function shell(c,o){var top=o.top;
 var ft=o.foot?foot(o.foot):"";
 if(c.form==="tablet"&&o.aside)return top+'<div class="r2s-tabl">'+o.aside+'<div class="r2s-main"><div class="scroll"><div class="col">'+o.body+'<div class="r2s-foot" style="padding:6px 0 0;background:none">'+(o.foot||"")+'</div></div></div></div></div>';
 return top+K.page(o.body)+ft;}
function leaves(){var P=[[26,130],[74,122],[116,92],[150,40]];
 function pt(t){var u=1-t;return [u*u*u*P[0][0]+3*u*u*t*P[1][0]+3*u*t*t*P[2][0]+t*t*t*P[3][0],u*u*u*P[0][1]+3*u*u*t*P[1][1]+3*u*t*t*P[2][1]+t*t*t*P[3][1]];}
 function tg(t){var u=1-t;return [3*u*u*(P[1][0]-P[0][0])+6*u*t*(P[2][0]-P[1][0])+3*t*t*(P[3][0]-P[2][0]),3*u*u*(P[1][1]-P[0][1])+6*u*t*(P[2][1]-P[1][1])+3*t*t*(P[3][1]-P[2][1])];}
 var s='<svg viewBox="0 0 300 132" aria-hidden="true"><path d="M26 130 C 74 122 116 92 150 40" fill="none" stroke="var(--priD)" stroke-width="3.4" stroke-linecap="round"/><path d="M274 130 C 226 122 184 92 150 40" fill="none" stroke="var(--priD)" stroke-width="3.4" stroke-linecap="round"/>';
 [.14,.28,.42,.56,.7,.84].forEach(function(t,i){var p=pt(t),g=tg(t),ang=Math.atan2(g[1],g[0])*180/Math.PI,side=i%2?1:-1,rot=ang+side*38,nx=-g[1],ny=g[0],ln=Math.sqrt(nx*nx+ny*ny),ox=side*-nx/ln*9,oy=side*-ny/ln*9,x=p[0]+ox,y=p[1]+oy,rx=14-i*.6,fl=i%2?"var(--priC2)":"var(--pri)";
  s+='<ellipse cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" rx="'+rx+'" ry="6" transform="rotate('+rot.toFixed(1)+' '+x.toFixed(1)+' '+y.toFixed(1)+')" fill="'+fl+'"/>';
  var mx=300-x,mr=-rot;s+='<ellipse cx="'+mx.toFixed(1)+'" cy="'+y.toFixed(1)+'" rx="'+rx+'" ry="6" transform="rotate('+(180-rot).toFixed(1)+' '+mx.toFixed(1)+' '+y.toFixed(1)+')" fill="'+(i%2?"var(--pri)":"var(--priC2)")+'"/>';});
 return s+'<ellipse cx="150" cy="24" rx="6.5" ry="15" fill="var(--pri)"/><circle cx="150" cy="42" r="4.5" fill="var(--priD)"/></svg>';}
function qr(sz){var n=25,s=7,cells="",x,y;function rnd(){s=(s*16807)%2147483647;return s;}
 function fin(a,b){return '<rect x="'+a+'" y="'+b+'" width="7" height="7" fill="#14201a"/><rect x="'+(a+1)+'" y="'+(b+1)+'" width="5" height="5" fill="#fff"/><rect x="'+(a+2)+'" y="'+(b+2)+'" width="3" height="3" fill="#14201a"/>';}
 for(y=0;y<n;y++)for(x=0;x<n;x++){if((x<8&&y<8)||(x>n-9&&y<8)||(x<8&&y>n-9)||(x>9&&x<15&&y>9&&y<15))continue;if(rnd()%100<48)cells+='<rect x="'+x+'" y="'+y+'" width="1.04" height="1.04"/>';}
 return '<svg viewBox="0 0 25 25" width="'+sz+'" height="'+sz+'" role="img" aria-label="Sample QR code. Not scannable."><g fill="#14201a">'+cells+'</g>'+fin(0,0)+fin(n-7,0)+fin(0,n-7)+'<rect x="10" y="10" width="5" height="5" rx="1.2" fill="#fff"/><path d="M11.2 13.8c0-1.8 1-2.6 2.8-2.8-.2 1.9-1 2.8-2.8 2.8z" fill="var(--pri)"/></svg>';}

var SIGN_IN="R2 Start: Sign in and account",FAM="R2 Start: Your family",INV="R2 Start: Inviting the other parent",DEV="R2 Start: Devices",CH="R2 Start: Ivy’s tablet";
var COMMON={since:"Round 2",isNew:true};
function def(id,shell,title,o){o.since=COMMON.since;o.isNew=true;D(id,shell,title,o);}

/* ================================================================ 1. welcome ==== */
function welcome(c){var cv=c.form==="cover";
 var body=(c.form==="tablet"?'<span style="display:block;margin-bottom:-4px">'+K.logo(36)+'</span>':'<div class="r2s-hero">'+K.scene("hills",300,150)+'<span class="lg">'+K.logo(34)+'</span></div>')+
  H("Welcome to Olive Branch",cv?"A calm, shared space for the grown-ups who love one child.":"A calm, shared space for the grown-ups who love one child. Start here, and bring the other parent when you’re ready.",null,1)+
  '<div class="card flat"'+N(2)+'><div class="row" style="padding:0;align-items:flex-start"><span class="ricon">'+I("key",20,1.9)+'</span><span class="rtxt"><b>What’s a passkey?</b><small style="line-height:1.4">It lets you sign in with your fingerprint, face or screen lock. There’s no password to remember or guess.</small></span></div></div>'+
  ((cv||c.form==="tablet")?"":'<div style="display:grid;justify-items:center">'+link("Have an invitation code?",{ic:"mail",n:5})+'</div>');
 var f=P("Sign in with a passkey","key",3)+K.btn("Create an account",{kind:"tonal",full:true,size:"lg"})+link("No passkey? Email me a sign-in link",{cls:"mute",n:4})+(c.form==="tablet"?link("Have an invitation code?",{ic:"mail",n:5}):"");
 var a=aside("hills","One calm place for both homes",null,[["users","You, the other parent and your child, on one shared page."],["shieldcheck","Built for kids first. No ads, no scores, no tracking."],["lock","Nothing is hidden from either guardian."]]);
 return W(shell(c,{top:K.sb(),body:body,foot:f,aside:a}));}
def("r2sWelcome","guardian","Welcome and sign in",{grp:SIGN_IN,
 desc:"First thing a grown-up sees on a fresh install. A passkey is the front door; everything else is a clearly smaller way in.",
 notes:[[1,"One plain sentence about what the app is, no feature list. A stressed parent needs to know they are in the right place."],[2,"“Passkey” is explained once, in one sentence of plain words, right where the word first appears."],[3,"One primary action: sign in with a passkey. Create an account is the tonal second choice, so a returning parent never taps the wrong one."],[4,"The fallback is named and honest: an emailed sign-in link. It is smaller, not hidden, so nobody is locked out because their phone has no biometrics."],[5,"People arriving from an invitation get their own quiet door instead of a second account form."]],
 r:welcome,cover:function(){return welcome({form:"cover"});}});

/* ============================================================ 2. create account == */
function account(c){
 var top=rtop({step:[1,5],stepName:"About you"});
 var body=H("Create your account","So you and Ivy’s other parent can find each other.","About you",1)+
  F("Your name","Marcus",{state:"ok",n:2,help:"This is the name the other parent sees."})+
  F("Email","marcus@example.com",{state:"on",ic:"mail",n:3,help:"Only for signing in and important notices about your account."})+
  '<div class="card flat"'+N(4)+'><div class="row" style="padding:0;align-items:flex-start"><span class="ricon">'+I("lock",20,1.9)+'</span><span class="rtxt"><b>Your privacy</b><small style="line-height:1.4">We never sell your details, show ads or use anything about you or your child to train a model. Your child never sees your email.</small></span></div></div>'+'<p class="r2s-fine" style="text-align:left;padding:0 4px">By continuing you accept the Terms and the Privacy notice.</p>';
 var f=P("Continue",null,5)+'<p class="r2s-fine">Next: a passkey, made with your fingerprint or screen lock.</p>';
 return W(shell(c,{top:top,body:body,foot:f,aside:aside("branch","Why we ask",null,[["user","Your name helps the other parent recognise you."],["mail","Your email is how you get back in."],["shield","Nothing here is shared outside your family."]])}));}
def("r2sAccount","guardian","Create your account",{grp:SIGN_IN,desc:"Two fields, a privacy promise in plain words, and no password.",
 notes:[[1,"Step 1 of 5 is shown as five quiet bars, not a percentage. It tells a parent how much is left without turning setup into a score."],[2,"A valid field turns green with a short reason, never a bare tick."],[3,"The field in use has a clear focus ring. The help line says exactly what the email is for."],[4,"The privacy line keeps P5: no ads, no data brokerage, no training on child data."],[5,"No password field at all. The passkey is created next, so the sentence under the button says so before it happens."]],
 r:account});

/* ================================================================= 3. set PIN ==== */
function setPin(c){var cv=c.form==="cover";
 var top=rtop({step:[2,5],stepName:"Your PIN"});
 var body=H("Choose a PIN",cv?"4 digits, for confirming sensitive things.":"4 digits. It confirms sensitive things, like inviting someone, and opens the grown-up area on a shared tablet.","Your PIN",1)+
  '<div style="display:grid;justify-items:center;gap:6px;padding:4px 0 0" aria-label="2 of 4 digits entered"'+N(4)+'>'+K.dots(4,2)+'<small style="color:var(--ink3);font-size:12.5px">Enter it twice. We’ll ask again to be sure.</small></div>'+
  '<div'+N(2)+'>'+kp()+'</div>'+
  '<div style="display:grid;justify-items:center">'+link("What if I forget it?",{ic:"info",n:3})+'</div>';
 return W(shell(c,{top:top,body:body,aside:aside("night","Your PIN stays with you",null,[["eyeoff","It is never shown, never emailed and never visible to the other parent."],["lock","You use it to confirm things like inviting an adult or deleting your account."],["refresh","Forgotten it? Your passkey gets you back in."]])}));}
def("r2sPin","guardian","Set your PIN",{grp:SIGN_IN,desc:"A short PIN for confirming sensitive actions. Recovery is explained before it is needed.",
 notes:[[1,"Says what the PIN is for in one sentence, and what it is not for: it is not the way in. The passkey is."],[2,"The keys are in order here because this is a private moment. Her kiosk gate stays shuffled, because a child may be watching."],[3,"Recovery is one tap away, before anyone has forgotten anything."],[4,"No strength meter and no rules about digits. A PIN is only a confirmation step."]],
 r:setPin,cover:function(){return setPin({form:"cover"});}});

/* ============================================================== 3b. forgot PIN === */
function forgotPin(c){
 var top=rtop({title:"Reset your PIN"});
 var body=H("We’ll check it’s you first","Your PIN is never shown or emailed. You’ll choose a new one.",null,1)+
  K.card('<div class="r2s-step" style="padding-top:2px"><span class="r2s-num">1</span><span><b>Confirm with your passkey</b><br><small style="color:var(--ink2)">Fingerprint, face or screen lock.</small></span></div><div class="r2s-step" style="padding-bottom:2px"><span class="r2s-num">2</span><span><b>Choose a new PIN</b><br><small style="color:var(--ink2)">Four digits, entered twice.</small></span></div>',"",2)+
  K.banner("info","Mom will see a line in the shared log that your PIN was reset, never the PIN itself. Nothing is hidden between guardians.","eye",3);
 var f=P("Confirm with my passkey","key")+link("No passkey on this phone? Email me a link",{cls:"mute",n:4});
 return W(shell(c,{top:top,body:body,foot:f}));}
def("r2sForgotPin","guardian","Forgot your PIN",{grp:SIGN_IN,desc:"Recovery path for a forgotten PIN. The passkey proves who you are; the PIN is replaced, never revealed.",
 notes:[[1,"Reassurance first: nothing is lost, and the PIN is never sent anywhere."],[2,"Two steps, named in plain words, with the real proof of identity (the passkey) doing the work."],[3,"PROPOSED, needs an owner decision: the other guardian sees that a reset happened. It keeps the “nothing hidden” rule, but it is a new log line."],[4,"The email link is the honest fallback for a phone without a passkey. It is a quiet link, not a button."]],
 r:forgotPin});

/* ================================================================= 4. family ==== */
function family(c){
 var top=rtop({step:[3,5],stepName:"Your family"});
 var body=H("Set up your family","This is what you and the other parent will both see.","Your family",1)+
  F("Family name","The Hartley family",{state:"on",ic:"users",n:2,help:"Just for the two of you. Your child doesn’t see it."})+
  pick("What your child calls you",["Mom","Dad","Grandma","Other"],1,3)+
  F("Your home","Dad’s place",{ic:"home",n:4,help:"Where your child stays with you."})+
  K.card(K.row({ic:"globe",title:"Time zone",sub:"Mountain Time, found automatically",trail:'<span class="r2s-link" style="min-height:48px">Change</span>'}),"flat")+
  '<p class="r2s-fine" style="text-align:left;padding:0 4px">Time zones let you both see the same day, each in your own time. Nobody does the maths.</p>';
 return W(shell(c,{top:top,body:body,foot:P("Continue"),aside:aside("hills","Her word for you",null,[["volume","Your child hears this word read aloud on her own tablet."],["home","Each home is named, so “Dad’s place” and “Mom’s place” are both just home."],["clock","Two time zones, one shared day."]])}));}
def("r2sFamily","guardian","Create the family",{grp:FAM,desc:"Family name, the word your child uses for you, and your home. Plain nouns, no accounts-and-groups language.",
 notes:[[1,"A family is a family. No “workspace”, no “group”."],[2,"The family name is for the grown-ups only. The help line says so."],[3,"The label is the word she hears and sees. Choosing “Dad” here means she is never shown “Guardian 1”."],[4,"Homes are named from the child’s point of view. Neither home is the default home."]],
 r:family});

/* ================================================================= 5. add child === */
function addChild(c){
 var top=rtop({step:[4,5],stepName:"Your child"});
 var body=H("Add your child","Just a first name and a birthday.","Your child",1)+
  F("First name","Ivy",{state:"ok",n:2,help:"Ivy sees and hears this. Use the name she knows."})+
  F("Birthday","March 3, 2021",{state:"on",ic:"calendar",n:3})+
  '<div class="chips" style="padding:0 2px">'+K.chip("Age worked out for you: 5",{tone:"pri",ic:"sparkle"})+'</div>'+
  K.card('<h4>What we do with this</h4>'+K.row({ic:"puzzle",title:"Choose activities that fit her age"})+K.row({ic:"shield",title:"Follow the right privacy rules for her age"})+K.row({ic:"eyeoff",title:"Never show her age as a number",sub:"Only guardians see it"}),"",4)+
  cb("I’m Ivy’s parent or legal guardian. I agree that Olive Branch keeps her first name and birthday to run her app. They are never used for ads or shared.",true,5);
 return W(shell(c,{top:top,body:body,foot:P("Add Ivy","plus"),aside:aside("paper","Why a birthday",null,[["sparkle","It picks the right games and stories, so nothing is too young or too old."],["shield","It sets the privacy rules that fit her age as she grows."],["eyeoff","She never sees it as a number, and neither does anyone outside the family."]])}));}
def("r2sChild","guardian","Add your child",{grp:FAM,desc:"First name and birthday, with the reason stated. Age is derived for guardians and never shown to the child as a number.",
 notes:[[1,"Two fields, no photo, no extras. Less to type, less to hold."],[2,"The name is what she will see and hear, so the help line says that."],[3,"A birthday, not an age: age is worked out from it and changes by itself."],[4,"“What we do with this” is three plain sentences, including the one parents need most: she never sees her age as a number."],[5,"A child’s data needs a parent’s consent. It is a real checkbox with a real sentence, not a buried link."]],
 r:addChild});

/* ============================================================ 6. invite other parent == */
function invite(c){
 var top=rtop({step:[5,5],stepName:"The other parent"});
 var vis=K.card('<h4>What Mom will and won’t see</h4>'+K.row({ic:"eye",title:"Everything you see about Ivy",sub:"Her days, messages, hand-over notes, expenses and care",tone:"ok"})+K.row({ic:"eyeoff",title:"Not your sign-in details",sub:"Your passkey and PIN stay yours",tone:"info"})+K.row({ic:"lock",title:"Not Ivy’s private journal",sub:"Nobody sees that, on purpose",tone:"info"}),"",5);
 var note=K.banner("pri","An invitation is only an invitation. It is never used to start a dispute, and it is not a legal notice.","heart",7);
 var body=H("Invite Ivy’s other parent","They’ll see everything you see, and you’ll see everything they do.","The other parent",1)+
  rc("Co-parent (guardian)","Full access, the same as you.",true,2)+rc("Step-parent","Sees only what you choose. Add them later from Family.",false)+
  pick("What Ivy calls them",["Mom","Dad","Grandma","Other"],0,3)+
  F("Their email","mom@example.com",{state:"on",ic:"mail",n:4,help:"We’ll email the invitation. It works once, for 7 days."})+
  '<div class="btns" style="margin-top:-2px"><button class="btn ghost sm" style="min-height:48px">'+I("link",17,2)+' Copy link</button><button class="btn ghost sm" style="min-height:48px">'+I("key",17,2)+' Show code</button></div>'+
  (c.form==="tablet"?"":vis)+
  cb("I understand everything in Ivy’s app is visible to both of us. Nothing is hidden from either guardian.",true,6)+
  (c.form==="tablet"?"":note);
 var asideHtml='<aside class="r2s-aside">'+'<h4>What Mom will and won’t see</h4>'+ar("eye","<b>Everything you see about Ivy:</b> her days, messages, hand-over notes, expenses and care.")+ar("eyeoff","<b>Not your sign-in details.</b> Your passkey and PIN stay yours.")+ar("lock","<b>Not Ivy’s private journal.</b> Nobody sees that, on purpose.")+'<div style="height:2px"></div>'+ar("heart","An invitation is only an invitation. It is never used to start a dispute, and it is not a legal notice.")+'</aside>';
 return W(shell(c,{top:top,body:body,foot:P("Send invitation","send",8)+link("Skip for now",{cls:"mute"}),aside:asideHtml}));}
def("r2sInvite","guardian","Invite the other parent",{grp:INV,wide:true,desc:"Role, label, email, or a link or code to share yourself. Says plainly what each guardian sees, asks for consent to that, and says what the invitation is not.",
 notes:[[1,"The headline states the symmetry: they see what you see, you see what they do."],[2,"Role is a choice with its meaning written beside it. Step-parents are scoped and added later, so the default is the honest one."],[3,"The label is the word Ivy will see for this person. It is set by you, and they can’t change it on their own."],[4,"Email is the main route. The invitation works once and expires, and the help line says how long."],[5,"Visibility before sending: what they will see, and the two things they won’t. Nothing about the other parent is hidden from you either."],[6,"The consent line is a real checkbox: everything is visible to both guardians, nothing hidden."],[7,"A clear note that an invitation is never used to start a dispute. This calms the most likely fear before the button is tapped."],[8,"One primary action. “Skip for now” is allowed and says nothing guilt-making."]],
 r:invite});

/* ============================================================== 7. invite sent ==== */
function inviteSent(c){var cv=c.form==="cover";
 var top=rtop({title:"Invitation sent",back:false});
 var body='<div class="r2s-hero">'+K.scene("letters",300,150)+'</div>'+
  H("We’ve sent it to Mom","mom@example.com. She can open it on any phone.",null,1)+
  K.card(K.row({ic:"hourglass",title:"Waiting for Mom",sub:"Expires Saturday, Nov 14 (in 7 days)",tone:"info",n:2})+'<div style="padding:8px 0 2px"><div class="r2s-wait" aria-label="Waiting"><i></i><i></i><i></i><span>Nothing for you to do</span></div></div>')+
  K.card('<div class="r2s-eye" style="margin-bottom:6px">Or tell her this code</div><div class="r2s-code"'+N(3)+'>K7M 29Q</div><p style="margin:6px 0 0;font-size:12.5px;color:var(--ink3)">Works once. Sample code.</p>',"flat")+
  '<div class="btns" style="flex-wrap:wrap"><button class="btn tonal sm" style="min-height:48px"'+N(4)+'>'+I("refresh",17,2)+' Resend</button><button class="btn ghost sm" style="min-height:48px">'+I("link",17,2)+' Copy link</button></div>';
 return W(shell(c,{top:top,body:body,foot:P("Continue to Today",null,5)+link("Cancel this invitation",{cls:"bad",n:6}),aside:aside("letters","While you wait",null,[["check","You can start using Olive Branch now. Mom joins when she’s ready."],["clock","The invitation ends on its own after 7 days. You can send another."],["lock","Only the person with the link or code can accept it, and only once."]])}));}
def("r2sInviteSent","guardian","Invitation sent",{grp:INV,desc:"A waiting state that asks nothing of you. Resend, share another way, or cancel, with a short, visible expiry.",
 notes:[[1,"The state in one sentence. Nothing is pending on you."],[2,"The expiry is a real date as well as a count, so it can’t be misread."],[3,"A code is offered as a second way to share, with its single-use nature said aloud."],[4,"Resend is a tonal button. If it is pressed twice in a row, the second press waits a minute rather than failing."],[5,"One primary action: carry on. She does not have to sit here."],[6,"Cancel is quiet and red, and it is available at any time before she accepts."]],
 r:inviteSent});

/* ================================================================ 8. invitee: open === */
function inviteOpen(c){var cv=c.form==="cover";
 var body='<div style="display:grid;justify-items:center;gap:10px;padding-top:6px">'+K.avatar("D",{size:64,ring:true,tone:"accent"})+'<div class="r2s-eye">Invitation</div></div>'+
  '<div class="r2s-h" style="text-align:center"'+N(1)+'><h1 class="r2s-h1">Marcus has invited you to Ivy’s family</h1><p class="r2s-lede">He’d like you to join as Ivy’s Mom, a guardian.</p></div>'+
  (cv?"":K.card('<h4>If you accept</h4>'+K.row({ic:"eye",title:"You’ll see what Marcus sees",sub:"Her days, messages, notes, expenses and care",tone:"ok"})+K.row({ic:"users",title:"Marcus will see what you do",sub:"Nothing is hidden from either of you",tone:"info"})+K.row({ic:"lock",title:"Your sign-in stays private",sub:"Only you have your passkey and PIN",tone:"info"}),"",2))+
  '<p class="r2s-fine"'+N(3)+'>Sent to mom@example.com. Expires Saturday, Nov 14. You’ll only see Ivy’s first name until you accept.</p>';
 var f=P("Accept and continue",null,4)+K.btn("Decline",{kind:"ghost",full:true,size:"lg"})+(cv?"":'<p class="r2s-fine" style="margin-top:4px">If you decline, Marcus will see that you did.</p>');
 return W(shell(c,{top:K.sb(),body:body,foot:f,aside:aside("branch","Before you decide",null,[["info","You haven’t shared anything yet. You can say no."],["eye","Both guardians see the same things about Ivy."],["heart","This is only an invitation. It is never used to start a dispute."]])}));}
def("r2sInviteOpen","guardian","Open the invitation",{grp:INV,desc:"What the invited parent sees before any account exists: who invited them, what joining means, and a real choice.",
 notes:[[1,"Who is asking, in a sentence, by name and role. The sender is a person, not a system."],[2,"What joining means, on both sides: you’ll see what he sees, he’ll see what you do. This is what they most need to hear."],[3,"Which address this was sent to, the expiry, and that only Ivy’s first name is visible until they accept."],[4,"Accept is the primary action. Decline is the same size and a real button, because a calm “no” must be as easy as “yes”."]],
 r:inviteOpen,cover:function(){return inviteOpen({form:"cover"});}});

/* ============================================================ 9. invitee: account + PIN === */
function inviteeAccount(c){
 var top=rtop({step:[1,2],stepName:"Your account"});
 var body=H("Make your account","You’re joining Ivy’s family as Mom.",null,1)+
  F("Your name","Mom",{state:"on",n:2,help:"The name Marcus sees."})+
  F("Email","mom@example.com",{state:"lock",ic:"lock",n:3,help:"From your invitation. It can’t be changed here."})+
  K.card('<h4'+N(4)+'>Choose a PIN</h4><p>4 digits. It confirms sensitive things. Your passkey comes next.</p><div style="display:grid;justify-items:center;gap:10px;padding:6px 0 4px">'+K.dots(4,3)+kp()+'</div>',"");
 var f=P("Create my account",null,5)+'<p class="r2s-fine">Then you’ll make a passkey with your fingerprint, face or screen lock.</p>';
 return W(shell(c,{top:top,body:body,foot:f}));}
def("r2sInviteeAccount","guardian","Join: account and PIN",{grp:INV,wide:true,desc:"The invitee’s two steps in one place, with the facts from the invitation already filled in.",
 notes:[[1,"Two steps, not five. Family and child already exist, so nothing else is asked."],[2,"Their name is what the other guardian sees."],[3,"The email is locked to the invitation. That is how it proves it was meant for them."],[4,"A PIN with the same plain explanation and the same recovery as everyone else."],[5,"A passkey is made on the next screen. Nothing here asks for a password."]],
 r:inviteeAccount});

/* ============================================================= 10. both connected === */
function connected(c){var cv=c.form==="cover",tab=c.form==="tablet";
 var next=K.card(K.row({ic:"device",title:"Pair Ivy’s tablet",sub:"So she can open her own app",go:true,n:3})+K.row({ic:"clock",title:"Share when you’re free to talk",sub:"Your weekly hours",go:true})+K.row({ic:"mic",title:"Record a first goodnight",sub:"For a night you’ll be away",go:true})+K.row({ic:"user",title:"Add Grandma or a sitter",go:true}),"",4);
 var lf='<div class="r2s-leaf"'+N(1)+'>'+leaves()+'</div>'+'<div class="r2s-pair">'+K.avatar("D",{size:46,tone:"accent"})+'<span style="color:var(--pri);display:grid">'+I("leaf",22,1.8)+'</span>'+K.avatar("M",{size:46})+'</div>';
 var hd='<div class="r2s-h" style="text-align:center"'+N(2)+'><h1 class="r2s-h1">Dad and Mom are connected</h1>'+(cv?"":'<p class="r2s-lede">You now see the same days, messages and notes for Ivy. Nothing is hidden from either of you.</p>')+'</div>';
 var lst=K.sectionLabel("Whenever you like")+next+'<p class="r2s-fine"'+N(5)+'>None of this is required, and nothing is counted.</p>';
 if(tab)return W(K.sb()+'<div class="r2s-tabl" style="grid-template-columns:minmax(0,1fr) minmax(0,1fr);padding-top:6px"><div class="r2s-main"><div class="scroll" style="padding-left:0;padding-right:0"><div class="col">'+lf+hd+'</div></div></div><div class="r2s-main"><div class="scroll"><div class="col">'+lst+'</div></div>'+foot(P("Go to Today"))+'</div></div>');
 return W(shell(c,{top:K.sb(),body:lf+hd+(cv?"":lst),foot:P("Go to Today")}));}
def("r2sConnected","guardian","Both guardians connected",{grp:FAM,desc:"A calm moment, not a spectacle. A small leaf motif, one sentence, and a few suggestions that are not a score.",
 notes:[[1,"Two branches meet. The motif is still, drawn in the theme colours, and there’s no confetti and no motion."],[2,"The sentence says what changed in plain words: same days, same messages, nothing hidden."],[3,"The first suggestion is the one with a real dependency: she can’t open her own app until her tablet is paired."],[4,"This is a list of ideas, not a checklist. There are no ticks, no “2 of 4”, no bar. Each row goes somewhere real."],[5,"The footer says out loud that none of it is required and nothing is counted (P2)."]],
 r:connected,cover:function(){return connected({form:"cover"});}});

/* ============================================================== 11. add another adult === */
function addAdult(c){
 var top=rtop({title:"Add an adult",eyebrow:"Family"});
 var body=H("Who’s helping?","Pick a role. You’ll see exactly what they can and can’t do.",null,1)+
  F("Their name","Priya (sitter)",{state:"on",ic:"user",n:2})+
  rc("Grandparent or trusted adult","Calls and messages with Ivy. Stays until you remove them.",false,3)+
  rc("Sitter","For a few hours or days. Gets a link, not an account.",true,4)+
  K.card('<h4>What Priya can do</h4>'+K.row({ic:"shield",title:"See the emergency card",tone:"ok"})+K.row({ic:"pill",title:"Write down a dose that was given",tone:"ok"})+K.row({ic:"calendar",title:"See the calendar",tone:"ok"})+'<h4 style="margin-top:8px">What she can’t</h4>'+K.row({ic:"eyeoff",title:"Messages, pictures, expenses and notes",tone:"warn"}),"",5)+
  pick("Access ends",["Tonight","This weekend","Pick a date"],1,6)+
  K.banner("info","Mom sees this too. You can remove Priya at any time.","eye",7);
 return W(shell(c,{top:top,body:body,foot:P("Send link","send"),aside:aside("paper","Plain words, not settings",null,[["check","Each role lists what it can do, in sentences."],["hourglass","A sitter’s link always ends. It can’t be made permanent."],["eye","Both guardians see who has access."]])}));}
def("r2sAddAdult","guardian","Add another adult",{grp:FAM,wide:true,desc:"A sitter or grandparent, with the permissions in sentences and an end date. Roles follow MASTERFILE 8.1 and nothing wider.",
 notes:[[1,"A question, not a form. The page is about who is helping."],[2,"A name for you to recognise them by. It isn’t shown to your child unless you choose a label later."],[3,"Grandparent or trusted adult: calls and messages only, as in 8.1."],[4,"Sitter: a time-boxed link with no account. Emergency card, dose log and calendar only."],[5,"Permissions as two short lists: what they can do and what they can’t. No toggles to misread."],[6,"A sitter must have an end. The choices are short; there is no “forever”."],[7,"The other guardian sees it too. Nothing about who has access is hidden from either of you."]],
 r:addAdult});

/* ================================================================== 12. pair tablet === */
function pairTablet(c){var cv=c.form==="cover";
 var top=rtop({title:"Pair Ivy’s tablet",back:true});
 var qrc='<div class="r2s-qrc"'+N(1)+'><div class="r2s-qrf">'+qr(cv?140:c.form==="tablet"?136:132)+'</div><small style="color:var(--ink3);font-size:12.5px">Sample code, not scannable</small></div>';
 var code='<div class="card flat" style="text-align:center"'+N(2)+'><div class="r2s-eye" style="margin-bottom:6px">Or type this code</div><div class="r2s-code">482 913</div><p style="margin:6px 0 0;font-size:12.5px;color:var(--ink3)">Works once. Ends in 10:00.</p></div>';
 var steps=K.card('<div class="r2s-step" style="padding-top:2px"'+N(5)+'><span class="r2s-num">1</span><span>Open Olive Branch on Ivy’s tablet.</span></div><div class="r2s-step"><span class="r2s-num">2</span><span>Choose <b>Set up this tablet</b>.</span></div><div class="r2s-step" style="padding-bottom:2px"><span class="r2s-num">3</span><span>Scan the square, or type the 6 digits.</span></div>',"",3);
 var wait='<div class="r2s-wait"'+N(4)+' role="status"><i></i><i></i><i></i><span>Waiting for the tablet</span></div>';
 var f=K.btn("Make a new code",{kind:"tonal",full:true,ic:"refresh"})+link("Cancel",{cls:"mute"});
 if(cv)return W(shell(c,{top:top,body:qrc+code+wait,foot:f}));
 if(c.form==="tablet")return W(top+'<div class="r2s-tabl" style="grid-template-columns:minmax(0,1fr) minmax(0,1fr)"><div class="r2s-main"><div class="scroll"><div class="col">'+qrc+code+'</div></div></div><div class="r2s-main"><div class="scroll"><div class="col">'+'<p class="r2s-lede" style="padding:0 2px">Do this with her tablet in your hand.</p>'+steps+wait+'</div></div>'+foot(K.btn("Make a new code",{kind:"tonal",full:true,ic:"refresh"}))+'</div></div>');
 return W(shell(c,{top:top,body:'<p class="r2s-lede" style="padding:0 2px">Do this with her tablet in your hand.</p>'+qrc+code+steps+wait,foot:f}));}
def("r2sPairTablet","guardian","Pair Ivy’s tablet",{grp:DEV,desc:"A QR card, a six-digit code for when the camera won’t cooperate, three steps and an honest waiting state.",
 notes:[[1,"The QR is large, on a white card, so it scans in a dim room. The code in this mock is a sample and does not scan."],[2,"A six-digit code is the fallback for a cracked camera or a poor screen. It works once and ends."],[3,"Three steps, written the way you’d say them aloud, with the real button name in bold."],[4,"“Waiting for the tablet” stays calm and has no timeout theatre. It turns into a confirmation when the tablet reports in."],[5,"Pairing gives the tablet its own sign-in. It doesn’t let anyone control the tablet remotely (P11)."]],
 r:pairTablet,cover:function(){return pairTablet({form:"cover"});}});

/* ================================================================ 13. paired devices === */
function devices(c){
 var top=rtop({title:"Your devices",eyebrow:"Account"});
 function dev(ic,name,sub,chip,act,n){return '<div class="card r2s-dev"'+N(n)+'><div class="hd"><span class="ricon">'+I(ic,20,1.9)+'</span><span class="rtxt"><b>'+E(name)+'</b><small>'+E(sub)+'</small></span>'+(chip||"")+'</div>'+(act||"")+'</div>';}
 var body=H("Where you’re signed in","Remove anything you don’t use or don’t recognise.",null,1)+
  dev("device","Galaxy Z Fold5","This phone · signed in today",K.chip("This device",{tone:"pri",sm:true}),null,2)+
  dev("device","Galaxy Tab S9 FE","Ivy’s tablet · paired Sep 12 · seen today",null,'<div class="act"><span>Ivy would see “Ask a grown-up” again.</span><button class="r2s-rm" aria-label="Remove Ivy’s tablet">'+I("x",16,2.2)+'Remove</button></div>',3)+
  dev("clock","Wear watch","Your watch · paired Oct 3 · seen 3 weeks ago",K.chip("Not seen lately",{tone:"warn",sm:true}),'<div class="act"><span>Not used lately. Safe to remove.</span><button class="r2s-rm" aria-label="Remove Wear watch">'+I("x",16,2.2)+'Remove</button></div>',4)+
  K.banner("info","Removing a device signs it out as soon as it’s online. Messages and pictures stay with Ivy.","info",5);
 return W(shell(c,{top:top,body:body,foot:P("Pair a new device","qr",6)}));}
def("r2sDevices","guardian","Paired devices",{grp:DEV,desc:"Every device that can sign in to this family, with a plain way to remove one. The sample shows the Fold5, Ivy’s Tab S9 FE and a Wear watch.",
 notes:[[1,"The list is short and written for recognition. A parent should know every row."],[2,"This phone is marked, and has no Remove. Signing out of this phone is its own screen."],[3,"Removing Ivy’s tablet says what she will see afterwards, so it can’t come as a surprise."],[4,"A device not seen for weeks is flagged quietly, in amber, with a suggestion and not an alarm."],[5,"Honest about timing: removal takes effect the next time the device is online."],[6,"Adding a device is the one primary action."]],
 r:devices});

/* =============================================================== 14. session expired === */
function expired(c){var cv=c.form==="cover";
 var bg=rtop({title:"Note to Mom",eyebrow:"Care note"})+K.page(K.card('<h4>Your note</h4><p style="color:var(--ink);font-size:14px;line-height:1.45">Tough morning, but she tried the spinach. Reading log still needs a signature…</p>')+K.btn("Send",{full:true,ic:"send"}));
 var sheet='<div class="scrim"></div><div class="sheet r2s-sh">'+'<i class="grab"></i>'+
  '<div style="display:grid;grid-template-columns:auto 1fr;gap:12px;align-items:center"><span class="ricon" style="width:44px;height:44px;border-radius:15px">'+I("lock",22,1.9)+'</span><div><h4 style="margin:0;font:800 19px/1.15 var(--font-display)"'+N(1)+'>Welcome back, Marcus</h4><small style="color:var(--ink2);font-size:13px">You were signed out to keep things safe.</small></div></div>'+
  (cv?"":K.card(K.row({ic:"file",title:"Your note is safe",sub:"Saved on this phone. It’ll be here when you’re back.",tone:"ok",n:2}),"flat"))+
  K.btn("Continue with my passkey",{full:true,size:"lg",ic:"key",n:3})+
  '<div style="display:grid;justify-items:center">'+link("Email me a sign-in link",{cls:"mute",n:4})+'</div></div>';
 return W(bg+sheet);}
def("r2sSessionExpired","guardian","Session expired",{grp:SIGN_IN,desc:"Signed out mid-task. Re-sign-in happens in a sheet over the page, so what you were typing is still right there.",
 notes:[[1,"First words are friendly and give the reason in plain terms. No “401”, no “token expired”."],[2,"The most important reassurance: your note is safe. The page behind is still there, dimmed, not replaced."],[3,"One primary action: the passkey. It is the same one-touch sign-in as day one."],[4,"The fallback is quiet but present."]],
 r:expired,cover:function(){return expired({form:"cover"});}});

/* ================================================================= 15. sign out === */
function signOut(c){
 var top=rtop({title:"Sign out",eyebrow:"Account"});
 var body=H("Sign out on this phone?","You’ll use your passkey to come back.",null,1)+
  K.banner("warn","You have 1 note you haven’t sent. Signing out removes it from this phone.","warn",2)+
  K.card('<h4>Removed from this phone</h4>'+K.row({ic:"key",title:"Your sign-in and PIN on this phone"})+K.row({ic:"image",title:"Downloaded copies of messages and pictures"})+K.row({ic:"file",title:"Unsent notes (1)"}),"",3)+
  K.card('<h4>Stays safe on our servers</h4>'+K.row({ic:"check",title:"Ivy’s messages, pictures and the shared log",tone:"ok"})+K.row({ic:"moon",title:"Banked messages still arrive on time",tone:"ok"})+K.row({ic:"device",title:"Ivy’s tablet keeps working",tone:"ok"})+K.row({ic:"users",title:"Mom’s access isn’t affected",tone:"ok"}),"",4);
 return W(shell(c,{top:top,body:body,foot:P("Sign out")+link("Stay signed in",{n:5})}));}
def("r2sSignOut","guardian","Sign out",{grp:SIGN_IN,desc:"What signing out removes from the phone and what stays on the server, in two short lists.",
 notes:[[1,"The answer to the real question is the headline: you can come back with a passkey."],[2,"A warning only if it applies: an unsent note would be removed. A parent can choose to go back and send it."],[3,"What leaves the phone, itemised. It’s the local copy only."],[4,"What stays, itemised, including the two things a parent worries about: banked messages and Ivy’s tablet."],[5,"Staying signed in is the quiet way out, with a real 48 px target."]],
 r:signOut});

/* ================================================================ 16. change PIN === */
function changePin(c){
 var top=rtop({title:"Change PIN",eyebrow:"Account"});
 var body=K.seg(["Current","New","Confirm"],0,1)+
  H("Enter your current PIN","Then you’ll choose a new one.",null,2)+
  '<div style="display:grid;justify-items:center;gap:8px" aria-label="2 of 4 digits entered">'+K.dots(4,2)+'<small style="color:var(--ink3);font-size:12.5px;min-height:15px"> </small></div>'+
  '<div'+N(3)+'>'+kp()+'</div>'+
  '<div style="display:grid;justify-items:center">'+link("Forgot your PIN?",{n:4})+'</div>';
 return W(shell(c,{top:top,body:body}));}
def("r2sChangePin","guardian","Change PIN",{grp:SIGN_IN,desc:"Asks for the current PIN first, then the new one twice. The wrong PIN never locks you out of anything but this.",
 notes:[[1,"Three steps in a plain segmented control: current, new, confirm. It shows where you are, not how well you’re doing."],[2,"One sentence says what is asked now and what comes next."],[3,"The same keypad as everywhere else, so the muscle memory carries over."],[4,"“Forgot your PIN?” goes to the same recovery as day one."]],
 r:changePin});

/* ================================================================ 17. delete intent === */
function deleteIntent(c){
 var top=rtop({title:"Leave Olive Branch",eyebrow:"Account"});
 var body=H("Thinking of leaving?","We make this slow on purpose. Leaving changes things for Ivy and for Mom, and it can’t be undone.",null,1)+
  K.card('<h4>What happens</h4><div class="r2s-tl" style="margin-top:8px"><div><span class="r2s-num">1</span><span><b>Today</b><small>You ask. Nothing is removed yet. Mom is told, so she can plan.</small></span></div><div><span class="r2s-num">2</span><span><b>For 7 days</b><small>You can change your mind from any signed-in device. Your banked messages keep arriving.</small></span></div><div><span class="r2s-num">3</span><span><b>Day 8</b><small>Your sign-in is removed, and messages that haven’t been delivered are cancelled.</small></span></div></div>',"",2)+
  K.card('<h4>What stays</h4>'+K.row({ic:"check",title:"Messages Ivy already has",tone:"ok"})+K.row({ic:"lock",title:"The shared log with Mom",sub:"Entries can’t be deleted",tone:"info"}),"",3)+
  K.card('<h4>What Mom is told</h4><p class="r2s-quote">“Marcus has asked to leave Olive Branch. Nothing changes until Nov 14. You may want to talk to him first.”</p>',"flat",4);
 var f=P("Keep my account")+K.btn("Start the 7-day wait",{kind:"danger",full:true,n:5})+'<p class="r2s-fine">You’ll confirm with your PIN.</p>';
 return W(shell(c,{top:top,body:body,foot:f}));}
def("r2sDeleteIntent","guardian","Account deletion intent",{grp:SIGN_IN,desc:"Leaving is a request with a wait, not a button. The other guardian is told the same day. Honest about what stays and why.",
 notes:[[1,"Calm, plain first words. It says why it is slow: it can’t be undone, and it affects more people than you."],[2,"A three-step timeline with real dates. The sample uses 7 days. PROPOSED: today the app removes the sign-in immediately, so this wait is a new owner decision."],[3,"What stays is stated: messages Ivy already has, and the shared log (P8, entries can’t be deleted)."],[4,"The other guardian’s message is shown in full. A parent should know exactly what will be said about them."],[5,"The safe choice is the filled button. Leaving is possible, plain, and one step away, never hidden."]],
 r:deleteIntent});

/* =================================================================== child 18: hello === */
function hello(c){var tab=c.form==="tablet",cv=c.form==="cover";
 var hero='<div class="r2s-chero"'+N(1)+'>'+K.scene("hills",300,150)+'<span class="r2s-wave">'+I("hand",44,1.8)+'</span></div>';
 var txt='<h1 class="r2s-ch"'+N(2)+'>Hello, Ivy!</h1>'+K.speak(cv?"":"Hear it")+
  '<div class="r2s-who"'+N(3)+'>'+K.avatar("D",{size:48,tone:"accent"})+I("heart",24,1.9)+K.avatar("M",{size:48})+'</div>';
 var f='<div class="r2s-cfoot">'+K.btn("Let’s go",{full:true,size:"lg",ic:"play",n:4})+'</div>';
 if(tab)return W(K.sb()+'<div class="r2s-cl"><div class="r2s-cwrap">'+hero+'</div><div class="r2s-cwrap">'+txt+'<div style="width:100%">'+K.btn("Let’s go",{full:true,size:"lg",ic:"play",n:4})+'</div></div></div>');
 return W(K.sb()+'<div class="r2s-cwrap">'+hero+txt+'</div>'+f);}
def("r2sChildHello","child","First hello on her tablet",{grp:CH,desc:"The first thing she sees after a grown-up pairs her tablet. Pictures, her name, her voice. It asks for nothing she cannot do.",
 notes:[[1,"A big friendly picture with a hand wave. No text she needs to read."],[2,"Her name is shown and spoken. The grown-up typed it; she is never asked to."],[3,"Dad and Mom, as the two faces who set this up. A heart between them, no count, no message."],[4,"One 64 px button with a picture on it. There is no settings icon, no keyboard, no way to get lost (MASTERFILE 8.1)."]],
 r:hello,cover:null});

/* ============================================================== child 19: ask a grown-up === */
function askGrownup(c){var tab=c.form==="tablet";
 var ill='<div class="r2s-big"'+N(1)+'>'+I("users",58,1.6)+'</div>';
 var txt='<h1 class="r2s-ch"'+N(2)+'>Ask a grown-up</h1>'+K.speak("Hear it")+'<p style="margin:0;text-align:center;color:var(--ink2);font-size:16px;line-height:1.4">This tablet needs a grown-up to set it up.</p>';
 var btn=K.btn("I’m a grown-up",{kind:"tonal",full:true,size:"lg",ic:"key",n:3});
 if(tab)return W(K.sb()+'<div class="r2s-cl"><div class="r2s-cwrap">'+ill+'</div><div class="r2s-cwrap">'+txt+'<div style="width:100%">'+btn+'</div></div></div>');
 return W(K.sb()+'<div class="r2s-cwrap">'+ill+txt+'</div><div class="r2s-cfoot">'+btn+'</div>');}
def("r2sChildLock","child","Ask a grown-up (not paired)",{grp:CH,desc:"What the tablet shows before it is paired, and again if a guardian removes it. A hand-off, not a dead end.",
 notes:[[1,"A picture of grown-ups, not a lock and not an error. Nothing is wrong."],[2,"One short line, spoken aloud as well. “Ask a grown-up” is the whole message."],[3,"“I’m a grown-up” leads only to the pairing screen, where a code from a guardian’s phone is needed. A child can tap it and nothing happens. PRODUCT QUESTION: confirm this one button is allowed on an unpaired device."]],
 r:askGrownup,cover:null});
})();
