/* mod-child.js : agent KID. The whole CHILD experience of the Olive Branch LIVE prototype.  SIMULATION: no real server.
   Registered with LIVE.module('child', ...).  Screen ids are 'k.*' (device 'k' only).

   ============================ ACTIONS other agents (CORE scenarios) may call (L.run('k', name, arg, arg2)) ============
   kid.open <screenId>        go to one of my screens (k.people k.day k.play k.colour k.draw k.list k.journal k.feel k.weeks k.cal k.privacy k.ladder ...)
   kid.back / kid.home        back / home on the child device          kid.tile <id>   open a home tile by id (people stories colour day play msgs ...)
   kid.play <game>            start a game: ttt c4 war mem word pict (honours the play window)      kid.g.start <game> [easy|normal|hard|two]
   kid.rename <gid> [nick]    rename a grown-up like a contact (no nick opens the picker). nick '' resets. Uses L.labels.rename (child owned)
   kid.openMyPeople           open My people                           kid.person <id>  tap a face (sheet: call / message / rename)
   kid.birthday [force]       show the 'your home grows' page for her current age (otherwise it appears on its own when the shown age crosses 5/8/10/13..18)
   kid.say <text>             speak text (speechSynthesis, quiet fallback)                  kid.msgs   open messages    kid.call <gid>   one-tap call (call.knock)
   kid.takeCopy               rung-17 export: downloads a JSON of her own data              kid.setAge <n>   guardian-only age change (needs the PIN in the Grown-up door)
   kid.lockout on|off         show / clear the kiosk lock-out screen (big picture + one-tap call)
   kid.sky <sky>  kid.worryAdd  kid.worryShow <id>  kid.worryFloat <id>  kid.wantAdd  kid.tick <id>  kid.colourPick <hex>  kid.mark (door)  kid.jSave ...

   ================================== S.kid.* KEYS I WRITE (S.kid.ga.* is GRD's and is READ ONLY for me) ===============
   S.kid.shown {age,band}     the age/band this device currently shows (follows L.grd.effectiveBand(): a held band keeps the old home)
   S.kid.lastAct              last seen shown age (to detect birthdays)    S.kid.grow {from,to,key,kind:'band'|'rung',state:'ready'|'seen'|'later'}
   S.kid.wants {needs:[],wants:[]}   items {id,text,ic}. Starts EMPTY       S.kid.feelings {day,sky}  only today is kept, no guardian view
   S.kid.worries [{id,text,state:'kept'|'shown',shownAt}]   S.kid.journal {entries:[{id,t,text}],lock:{on,code}}   PRIVATE: nobody else reads it
   S.kid.shared  {worries:[{id,text,to,t,seenAt}],showTell:[{id,name,data,to,t,seenAt}],asks:[],freeTimes,cal:[{id,y,m,d,title,to}]}  ONLY what she chose to show
   S.kid.pictures [{id,name,data,t,kind}] My saved pictures   S.kid.colourDay {day,pick}   S.kid.act {sort,path,critter}   S.kid.memories S.kid.capsules S.kid.growth
   S.kid.ticks {day,done}   S.kid.cal [{id,y,m,d,title,share}]   S.kid.freeTimes   S.kid.hidden   S.kid.story   S.kid.seen   S.kid.draft   S.kid.game (current game)
   S.kid.lockout {message,ic}|null   S.kid.tab (screen tabs)   S.kid.compass (her private answers)

   ================================== S.kid.ga.* KEYS I READ (published by GRD) ========================================
   access{readAloud,reduceMotion,roomy,larger,textSize}  play / L.grd.playState() ('open'|'winding'|'closed')  hiddenTiles[games stories draw read colour]
   art colourAsk palette people[{id,name,role,home,away,reach{messages,calls,story}}] homes[{id,name,who}] rhythm changeNote{text,t}
   routine[{text,time}] firstThen[{first,then}] packing[{text,packed}] newPlace[{place,note}] sensory{loud,bright,scratchy,crowds,surprises}
   helpers[{name,what}] symbols[{label,word}] feelings capsule[{text,openOn}] firstTimes[{text,date}] marks[{label,value,date}] poorly visit village compass shelf
   plus S.family.child {name,age,color(SEEDS key),birthday{m,d},nicknames}, S.family.pin, S.family.schedule, L.grd.houseOn(), L.grd.effectiveBand(), S.dev.k.revoked
*/
(function(){
'use strict';
if(!window.LIVE){return;}
window.LIVE.module('child',function(L){
var K=window.OB,E=K.esc,I=K.ico;

/* ------------------------------------------------------------------ small utils -- */
function pad(n){return n<10?'0'+n:''+n;}
function uid(p){return (p||'i')+Math.random().toString(36).slice(2,8);}
function clone(o){return JSON.parse(JSON.stringify(o));}
function rnd(n){return Math.floor(Math.random()*n);}
function pick(a){return a[rnd(a.length)];}
function shuffle(a){a=a.slice();for(var i=a.length-1;i>0;i--){var j=rnd(i+1),t=a[i];a[i]=a[j];a[j]=t;}return a;}
function tp(t){return L.parts(t==null?L.t():t,L.homeTz());}   /* her local clock: {y,m,d,h,min,dow} */
function dayKey(t){var p=tp(t);return p.y+'-'+pad(p.m)+'-'+pad(p.d);}
var MON=['January','February','March','April','May','June','July','August','September','October','November','December'];
var MONS=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
var DAYS=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
function P(){var k=L.S.kid;return (k&&k.ga)||{};}      /* guardian-authored content published by GRD (read only) */
function A(s){return s==null?'':E(String(s));}

/* ----------------------------------------------------------------------- styles -- */
(function css(){
 if(document.getElementById('kx-style'))return;
 var s=document.createElement('style');s.id='kx-style';
 s.textContent=[
 '.kx-grid{display:grid;gap:12px}.kx-g2{grid-template-columns:repeat(2,minmax(0,1fr))}.kx-g3{grid-template-columns:repeat(3,minmax(0,1fr))}.kx-g4{grid-template-columns:repeat(4,minmax(0,1fr))}',
 '.kx-col{display:flex;flex-direction:column;gap:12px}.kx-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}',
 '.kx-tile{appearance:none;font:700 17px/1.2 var(--font-body);color:var(--ink);background:var(--surface);border:1.5px solid var(--line);border-radius:26px;min-height:64px;padding:14px 10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;cursor:pointer;text-align:center;box-shadow:var(--shadow1);position:relative;width:100%;box-sizing:border-box}',
 '.kx-tile:focus-visible,.kx-b:focus-visible,.kx-key:focus-visible,.kx-cell:focus-visible,.kx-sw:focus-visible,.kx-rowb:focus-visible,.kx-opt:focus-visible,.kx-per:focus-visible,.kx-door:focus-visible,.kx-pad button:focus-visible,g[role=button]:focus-visible{outline:3px solid var(--focus);outline-offset:2px}',
 '.kx-tile .tic{width:56px;height:56px;border-radius:20px;display:grid;place-items:center;background:var(--priC);color:var(--onPriC)}',
 '.kx-tile small{font:500 13.5px/1.3 var(--font-body);color:var(--ink2)}',
 '.kx-tile.feat{flex-direction:row;justify-content:flex-start;text-align:left;gap:12px;min-height:84px;padding:12px 14px}.kx-tile.feat .ttx{display:flex;flex-direction:column;gap:2px}',
 '.kx-tile.huge{min-height:170px;border-radius:34px;gap:14px}.kx-tile.huge .tic{width:96px;height:96px;border-radius:32px}',
 '.kx-tile.wide{flex-direction:row;justify-content:flex-start;min-height:120px;padding:16px 20px;gap:18px;text-align:left}',
 '.kx-tile.dim{opacity:.7;background:var(--surface2)}.kx-tile.dim .tic{background:var(--surface3);color:var(--ink2)}',
 '.kx-tile.sel,.kx-sw.sel,.kx-opt.sel{outline:3px solid var(--pri);outline-offset:2px}',
 '.kx-dot{position:absolute;top:10px;right:12px;width:16px;height:16px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px var(--surface)}',
 '.kx-b{appearance:none;font:700 17px/1.2 var(--font-body);min-height:64px;padding:12px 20px;border-radius:22px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);display:inline-flex;align-items:center;justify-content:center;gap:10px;cursor:pointer;box-sizing:border-box}',
 '.kx-b.pri{background:var(--pri);color:var(--onPri);border-color:transparent}.kx-b.tonal{background:var(--priC);color:var(--onPriC);border-color:transparent}.kx-b.ghost{background:transparent}.kx-b.full{width:100%}.kx-b[disabled]{opacity:.5;cursor:default}',
 '.kx-rowb{appearance:none;font:inherit;text-align:left;width:100%;display:flex;gap:14px;align-items:center;min-height:64px;padding:10px 14px;background:var(--surface);color:var(--ink);border:1.5px solid var(--line);border-radius:22px;cursor:pointer;box-shadow:var(--shadow0);box-sizing:border-box}',
 '.kx-rowb .rt{display:flex;flex-direction:column;gap:2px;flex:1;min-width:0}.kx-rowb b{font-size:17px}.kx-rowb small{font-size:13.5px;color:var(--ink2)}.kx-rowb .ric{width:44px;height:44px;border-radius:15px;display:grid;place-items:center;background:var(--priC);color:var(--onPriC);flex:none}',
 '.kx-rowb.plain{cursor:default}',
 '.kx-h{font:700 24px/1.15 var(--font-display);margin:2px 0 0}.kx-p{font:400 17px/1.5 var(--font-body);color:var(--ink);margin:0}.kx-cap{font:500 14px/1.4 var(--font-body);color:var(--ink2);margin:0}',
 '.kx-card{background:var(--surface);border:1.5px solid var(--line);border-radius:26px;padding:16px;box-shadow:var(--shadow1);display:flex;flex-direction:column;gap:10px}.kx-card.tint{background:var(--priC);color:var(--onPriC);border-color:transparent}.kx-card.flat{box-shadow:none;background:var(--surface2)}',
 '.kx-card.tint .kx-cap,.kx-card.tint .kx-p,.kx-card.tint .kx-h{color:var(--onPriC)}',
 '.kx-sw{appearance:none;width:64px;height:64px;border-radius:50%;border:3px solid var(--surface);box-shadow:0 0 0 1.5px var(--edge);cursor:pointer;padding:0;position:relative;display:grid;place-items:center}',
 '.kx-opt{appearance:none;font:700 16px/1.2 var(--font-body);min-height:64px;padding:8px 14px;border-radius:20px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);cursor:pointer;display:inline-flex;align-items:center;gap:8px}',
 '.kx-key{appearance:none;font:700 18px/1 var(--font-body);min-height:52px;min-width:48px;border-radius:14px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);cursor:pointer;padding:0}',
 '.kx-key[disabled]{opacity:.35}',
 '.kx-board{display:grid;gap:6px;max-width:360px;margin:0 auto;width:100%}.kx-cell{appearance:none;aspect-ratio:1;border-radius:18px;border:1.5px solid var(--edge);background:var(--surface);display:grid;place-items:center;cursor:pointer;color:var(--ink);padding:0;font:700 40px/1 var(--font-display)}',
 '.kx-c4{display:grid;grid-template-columns:repeat(7,1fr);gap:4px;max-width:420px;margin:0 auto;width:100%;background:var(--pri);padding:6px;border-radius:20px;box-sizing:border-box}',
 '.kx-c4 button{appearance:none;display:flex;flex-direction:column;gap:4px;background:transparent;border:0;padding:0;cursor:pointer;min-height:64px}',
 '.kx-c4 i{display:block;aspect-ratio:1;border-radius:50%;background:var(--bg);box-shadow:inset 0 2px 3px rgba(0,0,0,.25)}',
 '.kx-c4 i.me{background:var(--accentC);border:4px solid var(--accent)}.kx-c4 i.cpu{background:var(--surface);border-radius:28%;border:4px solid var(--ink)}.kx-c4 i.win{outline:4px solid var(--focus)}',
 '.kx-card-pl{width:86px;aspect-ratio:3/4;border-radius:14px;background:var(--surface);border:2px solid var(--edge);display:grid;place-items:center;font:700 34px/1 var(--font-display);position:relative}',
 '.kx-card-pl.back{background:repeating-linear-gradient(45deg,var(--priC),var(--priC) 8px,var(--priC2) 8px,var(--priC2) 16px);color:transparent}',
 '.kx-card-pl small{position:absolute;top:5px;left:7px;font:700 14px/1 var(--font-body)}',
 '.kx-stack{display:flex;flex-direction:column;align-items:center;gap:6px}.kx-stack .st{width:70px;border-radius:12px;background:repeating-linear-gradient(45deg,var(--priC),var(--priC) 8px,var(--priC2) 8px,var(--priC2) 16px);border:2px solid var(--edge)}',
 '.kx-memc{aspect-ratio:1;min-height:64px}',
 '.kx-cv{width:100%;max-width:560px;margin:0 auto;display:block;border-radius:22px;border:2px solid var(--edge);background:#fff;touch-action:none;cursor:crosshair}',
 '.kx-art-crayon .kx-cv{border-style:dashed;border-width:3px}.kx-art-paper .kx-cv{border-radius:6px;box-shadow:3px 4px 0 var(--outline)}.kx-art-soft .kx-cv{border-color:transparent;box-shadow:var(--shadow2)}.kx-art-watercolour .kx-cv{border-color:var(--priC2);box-shadow:inset 0 0 22px var(--priC)}',
 '.kx-pal{display:flex;flex-wrap:wrap;gap:8px;justify-content:center}.kx-pal .kx-sw{width:52px;height:52px}',
 '.kx-ban{border-radius:22px;padding:14px 16px;background:var(--okC);color:var(--ink);font:700 18px/1.3 var(--font-body);display:flex;gap:12px;align-items:center}.kx-ban.soft{background:var(--infoC)}',
 '.kx-in{font:400 18px/1.4 var(--font-body);width:100%;min-height:64px;padding:12px 14px;border-radius:20px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);box-sizing:border-box}',
 'textarea.kx-in{min-height:120px;resize:vertical}',
 '.kx-pager{display:flex;gap:8px;justify-content:center}.kx-pager i{width:12px;height:12px;border-radius:50%;background:var(--outline)}.kx-pager i.f{background:var(--pri)}',
 '.kx-faces{display:flex;gap:10px;flex-wrap:wrap}',
 '.kx-per{appearance:none;display:flex;gap:12px;align-items:center;min-height:72px;padding:8px 14px;border-radius:22px;border:1.5px solid var(--line);background:var(--surface);color:var(--ink);font:700 19px/1.2 var(--font-body);cursor:pointer;width:100%;text-align:left;box-sizing:border-box}.kx-per .nm{flex:1}',
 '.kx-house{border-radius:26px;padding:12px;display:flex;flex-direction:column;gap:8px;background:var(--surface2);border:1.5px solid var(--line)}.kx-house h4{display:flex;gap:8px;align-items:center;font:700 17px var(--font-display);margin:0}',
 '.kx-lock{min-height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:22px;padding:24px;text-align:center}',
 '.kx-seal{width:110px;height:110px;border-radius:50%;display:grid;place-items:center;background:var(--priC);color:var(--onPriC)}',
 '.kx-big{font:800 84px/1 var(--font-display);color:var(--pri)}',
 '.kx-strip{display:flex;gap:8px;flex-wrap:wrap;min-height:72px;padding:10px;border-radius:22px;background:var(--surface2);border:1.5px dashed var(--edge);align-items:center}',
 '.kx-strip>span{padding:10px 14px;border-radius:16px;background:var(--priC);color:var(--onPriC);font:700 18px var(--font-body)}',
 '.kx-door{display:block;margin:0 auto;border-radius:18px;background:var(--surface2);border:2px solid var(--edge);cursor:pointer;width:100%;max-width:300px;appearance:none;padding:0}',
 '.kx-calm *{transition:none!important;animation:none!important}.kx-dim{filter:saturate(.8) brightness(.95)}.kx-roomy .col{gap:20px}',
 '.kx-hc .kx-tile,.kx-hc .kx-b,.kx-hc .kx-rowb,.kx-hc .kx-card{border-width:3px;border-color:var(--ink)}',
 '.kx-pad{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;max-width:300px;margin:0 auto;width:100%}.kx-pad button{appearance:none;min-height:64px;border-radius:20px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);font:700 26px var(--font-display);cursor:pointer;display:grid;place-items:center}',
 '.kx-dots{display:flex;gap:12px;justify-content:center}.kx-dots i{width:18px;height:18px;border-radius:50%;border:2px solid var(--edge)}.kx-dots i.f{background:var(--ink)}',
 '.kx-sky{min-height:96px}',
 '@media (max-width:480px){.kx-tile.huge{min-height:140px}.kx-tile.huge .tic{width:76px;height:76px}.kx-g4{grid-template-columns:repeat(2,minmax(0,1fr))}.kx-big{font-size:64px}}'
 ].join('\n');
 document.head.appendChild(s);
})();

/* ------------------------------------------------------------------ state ensure -- */
var BANDS=['t34','t57','t812','t1317'];
function bandOf(a){return a<=4?'t34':a<=7?'t57':a<=12?'t812':'t1317';}
function maxAge(b){return {t34:4,t57:7,t812:12,t1317:17}[b]||17;}
function realAge(){var c=(L.S.family&&L.S.family.child)||{};var a=parseInt(c.age,10);return isNaN(a)?7:a;}
function effBand(){try{if(L.grd&&L.grd.effectiveBand)return L.grd.effectiveBand();}catch(e){}return L.band();}
function dispAge(){var a=realAge(),b=effBand();return bandOf(a)===b?a:Math.min(a,maxAge(b));}   /* a held band keeps the old age's home */
var KEYS_GROW=[5,8,10,13,14,15,16,17,18];
function ens(){
 var s=L.S,k=s.kid=s.kid||{};
 k.wants=k.wants||{needs:[],wants:[]};k.wants.needs=k.wants.needs||[];k.wants.wants=k.wants.wants||[];
 k.worries=k.worries||[];
 k.shared=k.shared||{};['worries','showTell','asks','cal'].forEach(function(x){k.shared[x]=k.shared[x]||[];});
 k.journal=k.journal||{entries:[],lock:{on:false,code:''}};k.journal.entries=k.journal.entries||[];k.journal.lock=k.journal.lock||{on:false,code:''};
 k.pictures=k.pictures||[];k.memories=k.memories||[];k.capsules=k.capsules||[];k.growth=k.growth||[];k.cal=k.cal||[];
 k.act=k.act||{};k.seen=k.seen||{};k.draft=k.draft||{journal:'',want:'',worry:'',cap:'',memory:'',event:'',nick:'',compass1:'',compass2:''};
 k.story=k.story||{};k.hidden=k.hidden||{};k.freeTimes=k.freeTimes||{wd:{am:false,pm:true,eve:true},we:{am:true,pm:true,eve:true}};
 k.ticks=k.ticks||{day:'',done:{}};k.tab=k.tab||{};k.compass=k.compass||{};
 var dk=dayKey();
 if(!k.feelings||k.feelings.day!==dk)k.feelings={day:dk,sky:null};   /* only today is kept */
 if(k.ticks.day!==dk)k.ticks={day:dk,done:{}};
 if(k.colourDay&&k.colourDay.day!==dk)k.colourDay=null;
 var da=dispAge();
 if(!k.shown){k.shown={age:da,band:bandOf(da)};k.lastAct=da;}
 if(da!==k.shown.age){
  if(da>k.shown.age)growCheck(k,k.shown.age,da);else k.grow=null;
  k.shown={age:da,band:bandOf(da)};k.lastAct=da;
 }
 return k;
}
function growCheck(k,prev,a){
 var cross=KEYS_GROW.filter(function(x){return x>prev&&x<=a;});if(!cross.length)return;
 var bandC=cross.filter(function(x){return bandOf(x)!==bandOf(x-1);});
 var key=bandC.length?bandC[bandC.length-1]:cross[cross.length-1];
 k.grow={from:prev,to:a,key:key,kind:bandC.length?'band':'rung',state:'ready'};
}
function age(){return ens().shown.age;}
function eb(){return ens().shown.band;}

/* ---------------------------------------------------------------- family model -- */
function child(){return (L.S.family&&L.S.family.child)||{};}
function cname(){return child().name||'Ivy';}
function gl(){var pe=P().people;if(Array.isArray(pe)){var g=pe.filter(function(x){return x.guardian;});if(g.length)return g.map(function(x){return {id:x.id,name:x.name};});}
 var g2=(L.S.family&&L.S.family.guardians)||[];return g2.length?g2:[{id:'mom',name:'Jess'},{id:'dad',name:'Marcus'}];}
function lab(g){try{return L.labels.forChild(g);}catch(e){return g==='dad'?'Dad':'Mom';}}
function oneHome(){var hs=P().homes;if(Array.isArray(hs)&&hs.length)return hs.length<2;return gl().length<2;}
function otherOf(id){var o=gl().filter(function(x){return x.id!==id;})[0];return o?o.id:id;}
var WEEK=7*864e5;
function holderAt(t){
 var f=L.S.family,g=gl();if(g.length<2)return g[0].id;
 var cur=(f.custody&&f.custody.with)||g[0].id,anchor=L.nextAt('exchange',0);
 if(!isFinite(anchor))return cur;
 var a=Math.floor((t-anchor)/WEEK),b=Math.floor((L.t()-anchor)/WEEK);
 return ((a-b)%2===0)?cur:otherOf(cur);
}
function nightOf(y,m,d){
 try{if(L.grd&&L.grd.houseOn){var h=L.grd.houseOn(y+'-'+pad(m)+'-'+pad(d)),hs=P().homes,home=Array.isArray(hs)&&hs.filter(function(x){return x.id===h;})[0];
  var g=gl().map(function(x){return x.id;}),w=home&&home.who&&home.who.filter(function(i){return g.indexOf(i)>=0;})[0];if(w)return w;if(g.length>1)return h==='b'?g[1]:g[0];}}catch(e){}
 return holderAt(L.zoned(y,m,d,21,0,L.homeTz()));}
function tonight(){var p=tp();return nightOf(p.y,p.m,p.d);}
function sleepsTo(m,d){var p=tp(),today=Date.UTC(p.y,p.m-1,p.d),t=Date.UTC(p.y,m-1,d);if(t<today)t=Date.UTC(p.y+1,m-1,d);return Math.round((t-today)/864e5);}
function bday(){var b=child().birthday;return b&&b.m&&b.d?b:null;}
function houseName(g){return oneHome()?'Home':(lab(g)+'’s house');}
function colourHex(){var c=child().color;if(!c)return null;if(/^#/.test(c))return c;var sd=K.SEEDS&&K.SEEDS[c];return sd?sd.seed:null;}
function colourWord(){var c=child().color;if(!c||/^#/.test(c))return null;var sd=K.SEEDS&&K.SEEDS[c];return sd?sd.n:String(c);}

/* ------------------------------------------------------- guardian effects -- */
function hidden(id){if(id==='msgs')return false;if(id==='feel'&&P().feelings===false)return true;var m={play:'games',stories:'stories',storyteller:'read',draw:'draw',colour:'colour'}[id];if(!m)return false;var h=P().hiddenTiles;return Array.isArray(h)&&h.indexOf(m)>=0;}
function toMin(s){var p=String(s||'0:0').split(':');return (+p[0]||0)*60+(+p[1]||0);}
function playSt(){try{if(L.grd&&L.grd.playState)return L.grd.playState()||{state:'open'};}catch(e){}return {state:'open'};}
function playWin(){var s=playSt();return s.opensAt?{from:s.opensAt,to:s.restsAt}:null;}
function playOpen(){return playSt().state!=='closed';}
function windNote(){var s=playSt();return s.state==='winding'?banner('It is getting sleepy. One more, then goodnight.','moon','soft'):'';}
function fmt12(s){var m=toMin(s),h=Math.floor(m/60),mm=m%60;return (h%12||12)+(mm?':'+pad(mm):'')+(h<12?' AM':' PM');}
function acc(){return P().access||{};}
function zoomv(){var a=acc(),z=a.textSize==='largest'?1.4:a.textSize==='large'?1.2:1;if(a.larger&&z<1.15)z=1.15;return z;}
function offline(){return !L.online('k');}
function lockedOut(){var d=L.S.dev&&L.S.dev.k;return !!(ens().lockout||(d&&d.revoked));}
function readAloud(){return !!acc().readAloud;}
function unread(){
 try{var m=L.S.msg;if(!m||!m.intents)return false;
  return m.intents.some(function(it){return (it.state==='delivered')&&!it.openedT;});
 }catch(e){}
 return false;}

/* ----------------------------------------------------------------- speech -- */
var lastSaid='';
function say(t){
 lastSaid=String(t||'');
 try{if(window.speechSynthesis&&t){window.speechSynthesis.cancel();var u=new SpeechSynthesisUtterance(String(t));u.rate=.9;u.pitch=1.05;window.speechSynthesis.speak(u);}}catch(e){}
}
L.act('kid.say',function(c,t){say(t);});

/* ------------------------------------------------------------ page builders -- */
function page(inner){
 var z=zoomv(),sn=P().sensory||{},cls='scroll'+(acc().reduceMotion?' kx-calm':'')+(acc().roomy?' kx-roomy':'')+(sn.bright?' kx-dim':'')+(P().art?' kx-art-'+P().art:'')+((acc().contrast==='high'||acc().contrast===true)?' kx-hc':'');
 return '<div class="'+cls+'"'+(z!==1?' style="zoom:'+z+'"':'')+'><div class="col">'+inner+'</div></div>';}
function sayBtn(txt){return '<button type="button" class="cbtn tonal" data-act="kid.say" data-arg="'+A(txt)+'" aria-label="Hear it">'+I('volume',22,2)+'</button>';}
function top(title,o){o=o||{};return K.top({back:!o.noBack,eyebrow:o.eyebrow,title:title,right:(o.right||'')+(o.say?sayBtn(o.say):'')});}
function scr(title,inner,o){return top(title,o)+page(inner);}
function def(id,title,fn){L.screen(id,{dev:'k',title:title,render:fn});}
function go(id,p){L.go('k',id,p||{});}
function h2(t){return '<h2 class="kx-h">'+E(t)+'</h2>';}
function p(t){return '<p class="kx-p">'+E(t)+'</p>';}
function cap(t){return '<p class="kx-cap">'+E(t)+'</p>';}
function card(inner,cls){return '<div class="kx-card'+(cls?' '+cls:'')+'">'+inner+'</div>';}
function btn(text,act,arg,o){o=o||{};return '<button type="button" class="kx-b '+(o.kind||'pri')+(o.full?' full':'')+'" data-act="'+act+'"'+(arg!=null?' data-arg="'+A(arg)+'"':'')+(o.arg2!=null?' data-arg2="'+A(o.arg2)+'"':'')+(o.dis?' disabled':'')+(o.label?' aria-label="'+A(o.label)+'"':'')+'>'+(o.ic?I(o.ic,22,2):'')+(text?E(text):'')+'</button>';}
function rowb(o){return '<button type="button" class="kx-rowb'+(o.plain?' plain':'')+'" data-act="'+(o.act||'noop')+'"'+(o.arg!=null?' data-arg="'+A(o.arg)+'"':'')+(o.arg2!=null?' data-arg2="'+A(o.arg2)+'"':'')+'>'+(o.ic?'<span class="ric">'+I(o.ic,24,1.9)+'</span>':'')+(o.av||'')+'<span class="rt"><b>'+E(o.title)+'</b>'+(o.sub?'<small>'+E(o.sub)+'</small>':'')+'</span>'+(o.trail||'')+'</button>';}
function banner(txt,ic,cls){return '<div class="kx-ban'+(cls?' '+cls:'')+'" role="status">'+(ic?I(ic,26,2):'')+'<span>'+E(txt)+'</span></div>';}
function face(gid,size){var g=gl().filter(function(x){return x.id===gid;})[0]||{};var nm=lab(gid);return K.avatar((nm||'?').charAt(0).toUpperCase(),{size:size||52,tone:gid==='dad'?'accent':gid==='mom'?undefined:'info',label:nm});}
function sheet(html){L.sheet('k',html);}
function doneBtn(){return btn('Done','sheet.close',null,{full:true,kind:'tonal'});}
function toast(t,ic){L.toast('k',t,{ic:ic||'check'});}

/* ----------------------------------------------------------- messages / calls -- */
function firstScreen(ids){for(var i=0;i<ids.length;i++){if(L.hasScreen(ids[i],'k'))return ids[i];}return null;}
function openMsgs(){var id=firstScreen(['msg.kMessages','msg.home','messages']);if(id)go(id);else toast('Messages are on their way','chat');}
function callG(gid){
 if(isG(gid)&&L.hasAct('call.knock')){L.run('k','call.knock',gid);return;}
 L.emit('call:request',{from:'kid',to:gid});toast('Calling '+personLabel(gid),'phone');
}
L.act('kid.msgs',function(){openMsgs();});
L.act('kid.call',function(c,gid){callG(gid);});
L.act('kid.back',function(c){stopAuto();L.back('k');});
L.act('kid.home',function(){stopAuto();L.home('k');});
L.act('kid.open',function(c,id,el){stopAuto();go(id,c.arg2?safeJSON(c.arg2):{});});
function safeJSON(s){try{return JSON.parse(s);}catch(e){return {};}}

/* ----------------------------------------------------------------- tile registry -- */
var TL={
 people:{t:'My people',s:'Calls and messages',ic:'users',scr:'k.people'},
 stories:{t:'Stories',s:'Look and listen',ic:'book',scr:'k.stories'},
 colour:{t:'Colour',s:'My colour today',ic:'palette',scr:'k.colour',alt:{t1317:['Studio','k.draw']}},
 day:{t:'My day',s:'What comes next',ic:'calendar',scr:'k.day',alt:{t1317:['Today',null]}},
 play:{t:'Play together',s:'Games',ic:'dice',scr:'k.play',alt:{t812:['Games',null],t1317:['Downtime',null]}},
 msgs:{t:'Messages',s:'',ic:'chat',scr:null},
 showtell:{t:'Show & tell',s:'Share a picture',ic:'camera',scr:'k.showtell'},
 more:{t:'More',s:'',ic:'more',scr:'k.more'},
 list:{t:'My list',s:'Things I need and want',ic:'list',scr:'k.list'},
 weeks:{t:'My weeks',s:'Where I sleep',ic:'calendar',scr:'k.weeks'},
 journal:{t:'Journal',s:'Just for me',ic:'pencil',scr:'k.journal'},
 feel:{t:'Feelings',s:'When I need someone',ic:'smile',scr:'k.feel'},
 memory:{t:'Memory box',s:'Things I keep',ic:'heart',scr:'k.memory'},
 capsule:{t:'Time capsule',s:'Opens later',ic:'hourglass',scr:'k.capsule'},
 growth:{t:'Growing marks',s:'On the door',ic:'leaf',scr:'k.growth'},
 jokes:{t:'Jokebook',s:'Make me laugh',ic:'smile',scr:'k.jokes'},
 draw:{t:'Draw & colour',s:'Pictures I make',ic:'brush',scr:'k.draw',alt:{t1317:['Studio',null]}},
 storyteller:{t:'Storyteller',s:'Stories read to me',ic:'mic',scr:'k.storyteller'},
 birthday:{t:'My birthday',s:'',ic:'sparkle',scr:'k.birthday'},
 cal:{t:'My calendar',s:'Mine to fill in',ic:'calendar',scr:'k.cal'},
 privacy:{t:'Privacy',s:'What my parents can see',ic:'shield',scr:'k.privacy'},
 ladder:{t:'What is mine',s:'As I grow',ic:'key',scr:'k.ladder'},
 symbols:{t:'Symbols',s:'Tap to talk',ic:'hand',scr:'k.symbols'},
 pictures:{t:'My saved pictures',s:'',ic:'image',scr:'k.pictures'},
 helpers:{t:'My helpers',s:'People who help',ic:'shield',scr:'k.helpers'},
 routine:{t:'My routine',s:'First, then',ic:'check',scr:'k.day'},
 grownup:{t:'Grown-up things',s:'',ic:'lock',scr:null}
};
function ttitle(id,b){b=b||eb();var t=TL[id];if(!t)return id;var a=t.alt&&t.alt[b];return a?a[0]:t.t;}
function tscr(id,b){b=b||eb();var t=TL[id];var a=t.alt&&t.alt[b];return a&&a[1]?a[1]:t.scr;}
function tsub(id){var t=TL[id];if(id==='birthday'){var b=bday();if(b){var n=sleepsTo(b.m,b.d);return n===0?'Today!':n===1?'1 sleep':n+' sleeps';}}return t.s;}
var BANDSET={
 t34:['people','stories','colour'],
 t57:['day','play','msgs','stories','showtell','people','colour','more'],
 t812:['msgs','play','list','storyteller','weeks','showtell','people','journal','more'],
 t1317:['msgs','cal','journal','draw','people','play','ladder','privacy','more']
};
(function reg(){
 var n=0;Object.keys(TL).forEach(function(id){var t=TL[id];if(id==='grownup')return;n++;
  ['home','more'].forEach(function(area){
   try{L.tile({dev:'k',area:area,tier:id==='day'?'hero':'standard',id:'kid.'+id+'.'+area,title:t.t,sub:t.s,icon:t.ic,screen:t.scr||'k.more',order:n*10,
     when:function(c){return !hidden(id);},badge:id==='msgs'?function(){return unread()||null;}:null});}catch(e){}
  });});
})();
function dotHtml(id){return (id==='msgs'&&unread())?'<i class="kx-dot" role="img" aria-label="Something new"></i>':'';}
function tileHtml(id,cls,o){
 o=o||{};var t=TL[id],ti=ttitle(id),icn=o.big?46:30;var closed=(id==='play'&&!playOpen());
 var inner='<span class="tic">'+I(closed?'moon':t.ic,icn,1.8)+'</span>';
 if(o.iconOnly)inner+=K.sr(ti);
 else if(cls.indexOf('feat')>=0||cls.indexOf('wide')>=0){var s=o.sub!=null?o.sub:(closed?'Resting now':tsub(id));if(s===ti)s='';inner+='<span class="ttx"><b>'+E(ti)+'</b>'+(s?'<small>'+E(s)+'</small>':'')+'</span>';}
 else inner+='<span>'+E(ti)+'</span>';
 return '<button type="button" class="kx-tile '+cls+(closed?' dim':'')+'" data-act="kid.tile" data-arg="'+id+'" aria-label="'+A(ti)+'">'+inner+dotHtml(id)+'</button>';
}
function tiles(ids,cls,o){return ids.filter(function(i){return !hidden(i);}).map(function(i){return tileHtml(i,cls,o);}).join('');}
function openTile(id){
 var t=TL[id];if(!t||hidden(id))return;stopAuto();
 if(id==='msgs')return openMsgs();
 if(id==='grownup')return grownGate();
 if(id==='play'&&!playOpen())return restSheet();
 var s=tscr(id);if(s)go(s);
}
L.act('kid.tile',function(c,id){var b=eb();if(b==='t34')say(ttitle(id));else if(readAloud())say(ttitle(id));openTile(id);});
function restSheet(){var w=playWin();sheet('<div class="kx-col" style="text-align:center;padding:8px 4px 4px"><span class="kx-seal" style="margin:0 auto">'+I('moon',54,1.6)+'</span><h2 class="kx-h">The games are resting</h2>'+p('They wake up '+(w?'at '+fmt12(w.from):'later')+'. You can still call, send messages, draw and read.')+btn('Draw instead','kid.open','k.draw',{full:true})+btn('Okay','sheet.close',null,{full:true,kind:'tonal'})+'</div>');}

/* ------------------------------------------------------------ canvas engine -- */
/* Pixels live in an off-screen canvas per id so a re-render of the device never loses the picture. */
var CVS={},CVT={color:'#3a78c4',size:10,tool:'brush'},cur=null;
var PALETTE=['#c8473f','#e08a2e','#e6c13a','#4a8a52','#3a9a92','#3a78c4','#7a56b8','#d9679b','#8a5a3a','#2b2b2b','#9a9a9a','#ffffff'];
function hex2rgb(h){h=h.replace('#','');if(h.length===3)h=h.replace(/(.)/g,'$1$1');return [parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)];}
function cvState(id,w,h,setup){
 var st=CVS[id];
 if(!st||st.w!==w||st.h!==h){var off=document.createElement('canvas');off.width=w;off.height=h;st=CVS[id]={off:off,ctx:off.getContext('2d'),w:w,h:h,undo:[],kind:id.split(':')[0]};
  st.ctx.fillStyle='#fff';st.ctx.fillRect(0,0,w,h);if(setup)setup(st.ctx,w,h);}
 return st;}
function cvEl(id,w,h,aria){return '<canvas class="kx-cv" data-kcv="'+id+'" width="'+w+'" height="'+h+'" role="img" aria-label="'+A(aria||'Drawing area')+'"></canvas>';}
function paintAll(){
 var els=document.querySelectorAll('canvas[data-kcv]');
 for(var i=0;i<els.length;i++){var el=els[i];if(el.__kp)continue;var id=el.getAttribute('data-kcv'),st=CVS[id];if(!st)continue;el.getContext('2d').drawImage(st.off,0,0);el.__kp=1;}
}
L.afterRender.push(paintAll);
function cpt(ev,el){var r=el.getBoundingClientRect();return {x:(ev.clientX-r.left)*el.width/r.width,y:(ev.clientY-r.top)*el.height/r.height};}
function snap(st){try{st.undo.push(st.ctx.getImageData(0,0,st.w,st.h));if(st.undo.length>8)st.undo.shift();}catch(e){}}
function mirror(el,st){var c=el.getContext('2d');c.drawImage(st.off,0,0);}
function dab(st,el,a,b){
 var x=st.ctx;x.lineCap='round';x.lineJoin='round';x.strokeStyle=CVT.tool==='erase'?'#ffffff':CVT.color;x.fillStyle=x.strokeStyle;x.lineWidth=CVT.size;
 x.beginPath();x.moveTo(a.x,a.y);x.lineTo(b.x+.01,b.y+.01);x.stroke();mirror(el,st);
}
function flood(st,x,y,hex){
 var w=st.w,h=st.h,img=st.ctx.getImageData(0,0,w,h),d=img.data;x=Math.max(0,Math.min(w-1,x|0));y=Math.max(0,Math.min(h-1,y|0));
 var i0=(y*w+x)*4,tr=d[i0],tg=d[i0+1],tb=d[i0+2],c=hex2rgb(hex);
 if(tr+tg+tb<330)return false;                                  /* tapped an outline */
 if(Math.abs(tr-c[0])+Math.abs(tg-c[1])+Math.abs(tb-c[2])<12)return false;
 var seen=new Uint8Array(w*h),stack=[x,y];
 function ok(i){return Math.abs(d[i]-tr)+Math.abs(d[i+1]-tg)+Math.abs(d[i+2]-tb)<70&&(d[i]+d[i+1]+d[i+2])>330;}
 while(stack.length){var yy=stack.pop(),xx=stack.pop();var i=yy*w+xx;if(seen[i])continue;
  var l=xx;while(l>=0&&!seen[yy*w+l]&&ok((yy*w+l)*4))l--;l++;var r=xx;while(r<w&&!seen[yy*w+r]&&ok((yy*w+r)*4))r++;r--;
  for(var q=l;q<=r;q++){var j=yy*w+q;seen[j]=1;d[j*4]=c[0];d[j*4+1]=c[1];d[j*4+2]=c[2];d[j*4+3]=255;
   if(yy>0&&!seen[j-w]&&ok((j-w)*4))stack.push(q,yy-1);if(yy<h-1&&!seen[j+w]&&ok((j+w)*4))stack.push(q,yy+1);}
 }
 /* soften the halo next to outlines: paint light-grey antialias pixels bordering the fill */
 for(var n=0;n<seen.length;n++){if(seen[n])continue;var px=n*4,lum=d[px]+d[px+1]+d[px+2];if(lum>330&&lum<690){var nx=n%w,ny=(n/w)|0;
   if((nx>0&&seen[n-1])||(nx<w-1&&seen[n+1])||(ny>0&&seen[n-w])||(ny<h-1&&seen[n+w])){d[px]=(d[px]+c[0])>>1;d[px+1]=(d[px+1]+c[1])>>1;d[px+2]=(d[px+2]+c[2])>>1;}}}
 st.ctx.putImageData(img,0,0);return true;
}
function pixCell(st,el,pt){
 var n=st.cells,cs=st.w/n,cx=Math.floor(pt.x/cs),cy=Math.floor(pt.y/cs);if(cx<0||cy<0||cx>=n||cy>=n)return;
 var x=st.ctx;x.fillStyle=CVT.tool==='erase'?'#f4f1e6':CVT.color;x.fillRect(cx*cs+1,cy*cs+1,cs-1,cs-1);mirror(el,st);
}
document.addEventListener('pointerdown',function(ev){
 var el=ev.target&&ev.target.closest&&ev.target.closest('canvas[data-kcv]');if(!el)return;
 var id=el.getAttribute('data-kcv'),st=CVS[id];if(!st)return;ev.preventDefault();
 try{el.setPointerCapture(ev.pointerId);}catch(e){}
 var pt=cpt(ev,el);cur={el:el,st:st,last:pt,id:id};snap(st);
 if(st.pix){pixCell(st,el,pt);return;}
 if(CVT.tool==='fill'&&st.fillable){flood(st,pt.x,pt.y,CVT.color);mirror(el,st);cur=null;return;}
 dab(st,el,pt,pt);
});
document.addEventListener('pointermove',function(ev){
 if(!cur)return;var pt=cpt(ev,cur.el);
 if(cur.st.pix)pixCell(cur.st,cur.el,pt);else dab(cur.st,cur.el,cur.last,pt);cur.last=pt;
});
function endPt(){cur=null;}
document.addEventListener('pointerup',endPt);document.addEventListener('pointercancel',endPt);
L.act('kid.cv.undo',function(c,id){var st=CVS[id];if(!st||!st.undo.length)return;var im=st.undo.pop();st.ctx.putImageData(im,0,0);var el=document.querySelector('canvas[data-kcv="'+id+'"]');if(el)mirror(el,st);});
L.act('kid.cv.clear',function(c,id){var st=CVS[id];if(!st)return;snap(st);st.ctx.fillStyle=st.pix?'#f4f1e6':'#fff';st.ctx.fillRect(0,0,st.w,st.h);if(st.redo)st.redo(st.ctx,st.w,st.h);var el=document.querySelector('canvas[data-kcv="'+id+'"]');if(el)mirror(el,st);});
L.act('kid.cv.color',function(c,col){CVT.color=col;if(CVT.tool==='erase')CVT.tool='brush';});
L.act('kid.cv.size',function(c,n){CVT.size=+n;});
L.act('kid.cv.tool',function(c,t){CVT.tool=t;});
function toolbar(id,o){
 o=o||{};
 var pal='<div class="kx-pal" role="radiogroup" aria-label="Colours">'+PALETTE.map(function(h){return '<button type="button" class="kx-sw'+(CVT.color===h&&CVT.tool!=='erase'?' sel':'')+'" role="radio" aria-checked="'+(CVT.color===h)+'" aria-label="Colour '+h+'" style="background:'+h+'" data-act="kid.cv.color" data-arg="'+h+'"></button>';}).join('')+'</div>';
 var tools='<div class="kx-row" style="justify-content:center">';
 if(o.fill)tools+=btn('Fill','kid.cv.tool','fill',{kind:CVT.tool==='fill'?'pri':'tonal',ic:'palette'});
 tools+=btn('Brush','kid.cv.tool','brush',{kind:CVT.tool==='brush'?'pri':'tonal',ic:'brush'});
 if(o.eraser)tools+=btn('Rub out','kid.cv.tool','erase',{kind:CVT.tool==='erase'?'pri':'tonal',ic:'undo'});
 tools+=btn('Undo','kid.cv.undo',id,{kind:'ghost',ic:'rewind'})+btn('Start over','kid.cv.clear',id,{kind:'ghost',ic:'refresh'})+'</div>';
 var sizes=o.noSize?'':'<div class="kx-row" style="justify-content:center">'+[[5,'Thin'],[10,'Medium'],[20,'Wide']].map(function(s){return '<button type="button" class="kx-opt'+(CVT.size===s[0]?' sel':'')+'" data-act="kid.cv.size" data-arg="'+s[0]+'" aria-label="'+s[1]+' brush"><svg width="30" height="22" viewBox="0 0 30 22" aria-hidden="true"><line x1="3" y1="11" x2="27" y2="11" stroke="currentColor" stroke-width="'+(s[0]/2.4)+'" stroke-linecap="round"/></svg>'+s[1]+'</button>';}).join('')+'</div>';
 return pal+tools+sizes;
}
function saveCv(id,name,kind){
 var st=CVS[id];if(!st)return;var k=ens();
 var t=document.createElement('canvas'),w=260,h=Math.round(260*st.h/st.w);t.width=w;t.height=h;var x=t.getContext('2d');x.fillStyle='#fff';x.fillRect(0,0,w,h);x.drawImage(st.off,0,0,w,h);
 var data;try{data=t.toDataURL('image/jpeg',.72);}catch(e){return;}
 k.pictures.unshift({id:uid('pic'),name:name||'My picture',data:data,t:L.t(),kind:kind||'doodle'});if(k.pictures.length>12)k.pictures.length=12;
 toast('Saved in My saved pictures','image');
}
L.act('kid.cv.save',function(c,id){saveCv(id,c.arg2,id.split(':')[0]);});

/* colouring pages: black outlines, drawn once into the off-screen canvas */
var PAGES={
 house:function(x,w,h){x.lineWidth=7;x.strokeStyle='#222';x.lineJoin='round';x.strokeRect(120,170,240,150);x.beginPath();x.moveTo(100,175);x.lineTo(240,60);x.lineTo(380,175);x.closePath();x.stroke();x.strokeRect(215,230,50,90);x.strokeRect(145,200,50,50);x.strokeRect(285,200,50,50);x.beginPath();x.arc(60,70,28,0,7);x.stroke();x.beginPath();x.moveTo(20,320);x.lineTo(460,320);x.stroke();},
 fish:function(x,w,h){x.lineWidth=7;x.strokeStyle='#222';x.lineJoin='round';x.beginPath();x.ellipse(220,180,130,80,0,0,7);x.stroke();x.beginPath();x.moveTo(340,180);x.lineTo(430,110);x.lineTo(430,250);x.closePath();x.stroke();x.beginPath();x.arc(150,160,12,0,7);x.stroke();x.beginPath();x.moveTo(230,100);x.quadraticCurveTo(250,50,290,105);x.stroke();x.beginPath();x.arc(240,290,18,0,7);x.arc(280,320,12,0,7);x.stroke();},
 flower:function(x,w,h){x.lineWidth=7;x.strokeStyle='#222';x.lineJoin='round';for(var i=0;i<6;i++){var a=i*Math.PI/3;x.beginPath();x.ellipse(240+Math.cos(a)*62,130+Math.sin(a)*62,44,26,a,0,7);x.stroke();}x.beginPath();x.arc(240,130,32,0,7);x.stroke();x.beginPath();x.moveTo(240,195);x.lineTo(240,340);x.stroke();x.beginPath();x.ellipse(290,270,45,20,-.5,0,7);x.stroke();x.beginPath();x.ellipse(190,290,45,20,.5,0,7);x.stroke();},
 kite:function(x,w,h){x.lineWidth=7;x.strokeStyle='#222';x.lineJoin='round';x.beginPath();x.moveTo(240,30);x.lineTo(340,140);x.lineTo(240,250);x.lineTo(140,140);x.closePath();x.stroke();x.beginPath();x.moveTo(240,30);x.lineTo(240,250);x.moveTo(140,140);x.lineTo(340,140);x.stroke();x.beginPath();x.moveTo(240,250);x.bezierCurveTo(200,290,290,300,250,340);x.stroke();[[225,285],[262,305]].forEach(function(b){x.beginPath();x.moveTo(b[0]-14,b[1]-10);x.lineTo(b[0]+14,b[1]+10);x.moveTo(b[0]+14,b[1]-10);x.lineTo(b[0]-14,b[1]+10);x.stroke();});}
};
var PAGENAMES=[['house','House'],['fish','Fish'],['flower','Flower'],['kite','Kite']];

/* ------------------------------------------------------------- the four homes -- */
function greet(){var h=tp().h;return h<12?'Good morning':h<17?'Good afternoon':'Good evening';}
function myFace(sz){return K.avatar(cname().charAt(0).toUpperCase(),{size:sz||44,ring:true,label:cname()});}
function homeTop(title,eyebrow,say_){return '<div class="top">'+K.logo(30)+'<div class="ttl">'+(eyebrow?'<small>'+E(eyebrow)+'</small>':'')+'<b>'+E(title)+'</b></div>'+(say_?sayBtn(say_):'')+myFace(44)+'</div>';}
function parts(){ /* day parts, from her local clock */
 return [['Morning','dpMorning',6,12],['School','dpDay',8.5,15],['After school','dpAfternoon',15,18],['Evening','dpEvening',18,20],['Bedtime','dpBed',20,21],['Night','dpNight',21,30]];}
function nowPart(){var h=tp().h+tp().min/60;return h<6?'Night':h<8.5?'Morning':h<15?'School':h<18?'After school':h<20?'Evening':h<21?'Bedtime':'Night';}
function weekStrip(){
 var g=gl(),pp=tp(),out='<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:6px" role="img" aria-label="The next seven nights">';
 for(var i=0;i<7;i++){var dt=new Date(Date.UTC(pp.y,pp.m-1,pp.d+i)),y=dt.getUTCFullYear(),m=dt.getUTCMonth()+1,d=dt.getUTCDate(),who=nightOf(y,m,d),tone=oneHome()?'':(who===g[0].id?'a':'b');
  out+=K.dayCell(d,{today:i===0,tone:tone,label:DAYS[dt.getUTCDay()]+(oneHome()?', home':', '+houseName(who))});}
 return out+'</div>';}
function nextLine(){
 if(oneHome())return 'You sleep at home tonight.';
 var p0=tp(),who=tonight(),line='Tonight you sleep at '+houseName(who)+'.';
 for(var i=1;i<=15;i++){var dt=new Date(Date.UTC(p0.y,p0.m-1,p0.d+i)),w=nightOf(dt.getUTCFullYear(),dt.getUTCMonth()+1,dt.getUTCDate());
  if(w!==who){line+=' On '+DAYS[dt.getUTCDay()]+' you go to '+houseName(w)+'.';break;}}
 return line;}
function guardianRow(ids){return '';}
function birthdayWeek(){var b=bday();if(!b)return false;var n=sleepsTo(b.m,b.d);return n<=7&&n>=0;}
function laterCard(){var k=ens();return (k.grow&&k.grow.state==='later')?rowb({ic:'sparkle',title:'Your home grew',sub:'Look when you want to.',act:'kid.birthday',arg:'later'}):'';}
function storyDot(){var cn=P().changeNote;return (cn&&!ens().seen['chg'+cn.t])?'<button type="button" class="kx-tile feat" data-act="kid.open" data-arg="k.change" aria-label="A story for you"><span class="tic">'+I('book',30,1.8)+'</span><span class="ttx"><b>A story for you</b><small>From a grown-up</small></span><i class="kx-dot" role="img" aria-label="Something new"></i></button>':'';}

function homeT34(){
 var g=gl(),faces=g.map(function(x){return K.avatar(lab(x.id).charAt(0).toUpperCase(),{size:64,tone:x.id==='dad'?'accent':undefined,label:lab(x.id)});}).join('');
 var peopleTile=hidden('people')?'':'<button type="button" class="kx-tile huge" data-act="kid.tile" data-arg="people" aria-label="My people"><span class="kx-faces" style="justify-content:center">'+faces+'</span>'+I('users',34,1.8)+K.sr('My people')+'</button>';
 var row2=[];if(!hidden('stories'))row2.push('stories');if(!hidden('colour'))row2.push('colour');
 var gset=[],Pp=P();
 if((Pp.routine&&Pp.routine.length)||(Pp.firstThen&&Pp.firstThen.length))gset.push('routine');
 if(Pp.capsule&&Pp.capsule.length)gset.push('capsule');if(Pp.helpers&&Pp.helpers.length)gset.push('helpers');if(Pp.firstTimes&&Pp.firstTimes.length)gset.push('memory');
 return '<div class="top">'+myFace(56)+'<div class="ttl"><b class="sr">Hi, '+E(cname())+'</b></div>'+sayBtn('Hi '+cname()+'. Touch a picture.')+'</div>'+
  page(peopleTile+'<div class="kx-grid kx-g2">'+tiles(row2,'huge',{iconOnly:true,big:true})+'</div>'+laterCard()+storyDot()+(gset.length?'<div class="kx-grid kx-g3" aria-label="From your grown-up">'+tiles(gset,'',{iconOnly:true})+'</div>':''));
}
function homeT57(){
 var pp=tp(),pct=(pp.h*60+pp.min)/14.4,part=nowPart();
 var dual='';var away=oneHome()?null:otherOf(tonight());
 if(away){var g=L.guardian(away),tz=(g&&g.tz)||L.S.family.homeTz;dual=K.dual({l1:cname()+', now',t1:L.fmt.time(L.t(),L.homeTz()),s1:part,l2:lab(away)+', now',t2:L.fmt.time(L.t(),tz),s2:L.dayPart(L.t(),tz)});}
 var hero=card(dual+(dual?'<div style="height:6px"></div>':'')+K.ribbon({now:Math.round(pct)})+(birthdayWeek()?cap('Your birthday is this week.'):'')+'<p class="kx-p">'+E(nextLine())+'</p>','');
 var heroTile=hidden('day')?'':'<button type="button" class="kx-tile wide" data-act="kid.tile" data-arg="day" aria-label="My day"><span class="tic">'+I('calendar',44,1.8)+'</span><span class="ttx" style="display:flex;flex-direction:column;gap:4px;font-size:22px"><b>My day</b><small>'+E(part)+', then what comes next</small></span></button>';
 return homeTop('Hi, '+cname(),greet(),'Hi '+cname()+'. '+greet())+page(hero+heroTile+laterCard()+storyDot()+
  '<div class="kx-grid kx-g2">'+tiles(['play','msgs','stories','showtell'],'feat')+'</div>'+
  '<div class="kx-grid kx-g3">'+tiles(['people','colour','more'],'')+'</div>');
}
function homeT812(){
 var nextCard=card('<span class="kx-cap" style="text-transform:uppercase;letter-spacing:.08em">Next</span><p class="kx-p" style="font-size:19px;font-weight:700">'+E(nextLine())+'</p>','tint');
 var weeks=hidden('weeks')?'':'<button type="button" class="kx-rowb" style="flex-direction:column;align-items:stretch" data-act="kid.tile" data-arg="weeks" aria-label="My weeks"><b>My weeks</b>'+weekStrip()+'</button>';
 return homeTop(greet()+', '+cname(),DAYS[tp().dow])+page(nextCard+weeks+laterCard()+storyDot()+
  '<div class="kx-grid kx-g2">'+tiles(['msgs','play','list','storyteller'],'feat')+'</div>'+
  '<div class="kx-grid kx-g4">'+tiles(['people','showtell','journal','more'],'')+'</div>');
}
function calToday(){var pp=tp();return ens().cal.filter(function(e){return e.y===pp.y&&e.m===pp.m&&e.d===pp.d;});}
function homeT1317(){
 var a=age(),pp=tp(),evs=calToday(),k=ens();
 var today=card('<span class="kx-cap" style="text-transform:uppercase;letter-spacing:.08em">'+E(DAYS[pp.dow]+', '+MON[pp.m-1]+' '+pp.d)+'</span>'+
  '<div class="kx-col" style="gap:6px"><p class="kx-p"><b>'+E(oneHome()?'Home tonight':houseName(tonight())+' tonight')+'</b></p>'+(oneHome()?'':cap(nextLine().split('. ').slice(1).join('. ')))+
  evs.map(function(e){return '<p class="kx-p">'+I('calendar',16,2)+' '+E(e.title)+'</p>';}).join('')+'</div>','');
 var ids=['msgs','cal'];var std=['journal','draw','people','ladder','privacy'];if(a<14)std.unshift('play');std.push('more');
 return homeTop('Hey, '+cname(),DAYS[pp.dow]+', '+MONS[pp.m-1]+' '+pp.d)+page(today+laterCard()+storyDot()+
  '<div class="kx-grid kx-g2">'+tiles(ids,'feat')+'</div>'+'<div class="kx-grid kx-g3">'+tiles(std,'')+'</div>');
}
function offlineHome(){
 var ids=['day','draw','stories','symbols','feel'];
 var t=ids.filter(function(i){return !hidden(i);}).map(function(i){return '<button type="button" class="kx-tile huge" data-act="kid.tile" data-arg="'+i+'" aria-label="'+A(ttitle(i))+'"><span class="tic">'+I(TL[i].ic,46,1.8)+'</span>'+K.sr(ttitle(i))+'</button>';}).join('');
 var mem='<button type="button" class="kx-tile huge" data-act="kid.play" data-arg="mem" aria-label="Memory pairs"><span class="tic">'+I('puzzle',46,1.8)+'</span>'+K.sr('Memory pairs')+'</button>';
 var msg='<div class="kx-tile huge dim" role="img" aria-label="Messages are waiting for the wifi"><span class="tic">'+I('mail',46,1.8)+'</span><span>'+I('wifioff',34,1.8)+'</span></div>';
 return '<div class="top">'+myFace(56)+'<div class="ttl"><b class="sr">Offline</b></div><span class="cbtn" aria-hidden="true">'+I('wifioff',24,2)+'</span></div>'+page('<div class="kx-grid kx-g2">'+t+mem+msg+'</div>');
}
function lockScreen(){
 var k=ens().lockout||{},who=oneHome()?gl()[0].id:tonight();
 return '<div class="scroll"><div class="kx-lock"><span class="kx-seal">'+I(k.ic||'moon',62,1.6)+'</span><h1 class="kx-h" style="font-size:30px">'+E(k.message||'Quiet time. Back soon.')+'</h1>'+sayBtn(k.message||'Quiet time. Back soon.')+
  '<button type="button" class="kx-b pri full" style="max-width:360px;min-height:84px;font-size:22px" data-act="kid.call" data-arg="'+who+'">'+I('video',32,2)+face(who,48)+'</button></div></div>';
}

/* ------------------------------------------------- 'your home grows' page -- */
var GROW={
 5:{eb:'You are 5',scene:'day',lead:'Your home is growing with you.',say:'You are five. Your home is growing with you.',items:[['add','Your day','See what comes next, in pictures.'],['add','Words with your pictures','Every picture has a word too.'],['keep','Calling, stories and colour','Right where they were.']],dest:'k.day',cta:'Show me'},
 8:{eb:'You are 8',scene:'day',lead:'Your home is growing with you.',say:'You are eight. Your home is growing with you.',items:[['add','Your weeks','See where you sleep, week by week.'],['add','Your own list','Things you need and things you want.'],['add','A quiet journal','Just for you.'],['keep','Calling, stories, show and tell','Right where they were.']],dest:'k.weeks',cta:'Show me'},
 10:{eb:'You are 10',lead:'Your list is yours.',say:'Your list is yours now.',items:[['hers','Yours now','Nobody checks it first. Nobody changes it. You decide what goes on it.']],dest:'k.list',cta:'Open my list',quiet:true},
 13:{eb:'You are 13',lead:'You are 13. A few things are different now.',teen:true,items:[['hers','Your journal is locked','Only you can open it.'],['add','A different look','Calmer and plainer, with your own messages and calendar.'],['add','What your parents can see','A short list. It is the same for them as it is for you.']],dest:'k.privacy',cta:'Take a look'},
 14:{eb:'You are 14',lead:'This calendar is yours now.',teen:true,items:[['hers','Add anything','You choose whether anyone else sees it.'],['keep','Games','They moved to More. Nothing was taken away.']],dest:'k.cal',cta:'Open my calendar'},
 15:{eb:'You are 15',lead:'You decide when you are free.',teen:true,items:[['hers','Your free times','Set them. You see what Mom and Dad will see.'],['keep','Calls','A call is always one tap.']],dest:'k.free',cta:'Set my times'},
 16:{eb:'You are 16',lead:'The archive is yours to shape.',teen:true,items:[['hers','Hide what you want','Nothing is deleted. Nobody is told what you hide.']],dest:'k.archive',cta:'Look at it'},
 17:{eb:'You are 17',lead:'You can take a copy of your data.',teen:true,items:[['hers','A copy that is yours','No one has to say yes. Nobody is told you made it.']],dest:'k.copy',cta:'Make my copy'},
 18:{eb:'You are 18',lead:'This is your own space now.',teen:true,items:[['hers','Everything is yours','Guardianship has closed. You choose what happens next.']],dest:'k.handover',cta:'See my choices'}
};
function growKey(){var g=ens().grow;return g&&GROW[g.key]?g.key:null;}
function growPage(){
 var k=ens(),key=growKey();if(!key){k.grow.state='seen';return '';}
 var gp=GROW[key],by=gl()[0].id;
 var chg=gp.items.map(function(it){return '<div class="kx-row" style="flex-wrap:nowrap;align-items:flex-start;gap:12px"><span class="ric" style="width:36px;height:36px;border-radius:12px;display:grid;place-items:center;flex:none;background:'+(it[0]==='keep'?'var(--surface3)':'var(--priC)')+';color:var(--onPriC)">'+I(it[0]==='keep'?'check':it[0]==='hers'?'lock':'plus',18,2.2)+'</span><div><b>'+E(it[1])+'</b><p class="kx-cap">'+E(it[2])+'</p></div></div>';}).join('');
 var visual='';
 if(!gp.teen&&!gp.quiet)visual='<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene(gp.scene||'day',300,150)+'</div>';
 if(key===5)visual+='<div class="kx-card tint" style="align-items:center"><span class="kx-big" aria-hidden="true">5</span><div class="kx-faces" aria-hidden="true">'+[1,2,3,4,5].map(function(){return '<i style="width:18px;height:18px;border-radius:50%;background:var(--pri);display:block"></i>';}).join('')+'</div></div>';
 var from=gp.teen||gp.quiet?'':'From '+lab(by);
 return '<div class="top"><div class="ttl"><small>'+E(from||gp.eb)+'</small><b>'+E(gp.eb)+'</b></div>'+(gp.say?sayBtn(gp.say):'')+'</div>'+
  page(visual+'<h2 class="kx-h">'+E(gp.lead)+'</h2>'+card(chg)+btn(gp.cta,'kid.growShow',gp.dest,{full:true,ic:'arrowR'})+btn('Not now','kid.growLater',null,{full:true,kind:'ghost'})+(gp.teen?cap('Nobody else is told that you saw this.'):''));
}
L.act('kid.growShow',function(c,dest){var k=ens();if(k.grow)k.grow.state='seen';go(dest||'k.day');});
L.act('kid.growLater',function(){var k=ens();if(k.grow)k.grow.state='later';});
L.act('kid.birthday',function(c,arg){
 var k=ens();
 if(arg==='later'&&k.grow){k.grow.state='ready';return;}
 if(arg==='force'||!k.grow||k.grow.state!=='ready'){
  var a=realAge(),key=null;[18,17,16,15,14,13,10,8,5].some(function(x){if(a>=x){key=x;return true;}});
  if(arg==='force'||!k.grow){k.grow={from:a-1,fromBand:bandOf(a-1),to:a,key:key||5,kind:'band',state:'ready'};k.shown={age:a,band:bandOf(a)};}
 }
 L.home('k');
});
L.act('kid.lockout',function(c,v){ens().lockout=(v==='off')?null:{message:c.arg2||'Quiet time. Back soon.',ic:'moon'};});

function renderHome(){
 var k=ens();
 if(lockedOut())return lockScreen();
 if(k.grow&&k.grow.state==='ready'&&growKey())return growPage();
 if(offline())return offlineHome();
 return ({t34:homeT34,t57:homeT57,t812:homeT812,t1317:homeT1317})[eb()]();
}
BANDS.forEach(function(b){L.homeVariant(b,function(c){return renderHome();});});

/* ================================================================ MY PEOPLE == */
var BANK_MOM=['Mommy','Mama','Mum','Mom','Mummy','Mother'],BANK_DAD=['Daddy','Dada','Papa','Pop','Dad','Father'],BANK_OTHER=['Grandma','Nana','Gran','Granny','Grandpa','Papa','Pop','Auntie','Uncle'];
function ppl(){var r=P().people;return Array.isArray(r)?r:[];}
function isG(id){return gl().some(function(x){return x.id===id;});}
function pname(p){var n=child().nicknames;return (n&&n[p.id])||(isG(p.id)?lab(p.id):p.name);}
function personLabel(id){if(isG(id))return lab(id);var e=ppl().filter(function(x){return x.id===id;})[0];return e?pname(e):'Grown-up';}
function perRow(id,name,canCall,canMsg,tone){
 return '<button type="button" class="kx-per" data-act="kid.person" data-arg="'+A(id)+'" aria-label="'+A(name)+'">'+K.avatar(name.charAt(0).toUpperCase(),{size:52,tone:tone})+'<span class="nm">'+E(name)+'</span>'+(canCall?'<span aria-hidden="true">'+I('video',22,2)+'</span>':'')+(canMsg?'<span aria-hidden="true">'+I('chat',22,2)+'</span>':'')+'</button>';}
function reachOf(p,k){return !p.reach||p.reach[k]!==false;}
function homeTitle(h){var g=(h.who||[]).filter(isG)[0];return g?houseName(g):(h.name||'Home');}
def('k.people','My people',function(c){
 var pe=ppl(),hs=P().homes,out='';
 if(!pe.length){
  out+=gl().map(function(x){return perRow(x.id,lab(x.id),true,true,x.id==='dad'?'accent':undefined);}).join('');
  out+=cap('Tap a face to call, send a message, or change what you call them.');
 }else{
  var placed={};
  (Array.isArray(hs)?hs:[]).forEach(function(h){
   var inh=pe.filter(function(q){return q.home===h.id&&!q.away;});inh.forEach(function(q){placed[q.id]=1;});
   if(inh.length)out+='<div class="kx-house"><h4>'+I('home',22,2)+E(homeTitle(h))+'</h4>'+inh.map(function(q){return perRow(q.id,pname(q),reachOf(q,'calls'),reachOf(q,'messages'),q.id==='dad'?'accent':undefined);}).join('')+'</div>';
  });
  var far=pe.filter(function(q){return !placed[q.id];});
  if(far.length)out+='<div class="kx-house"><h4>'+I('heart',22,2)+'Near and far</h4>'+far.map(function(q){return perRow(q.id,pname(q),reachOf(q,'calls'),reachOf(q,'messages'));}).join('')+'</div>';
 }
 var cn=P().changeNote;if(cn)out+=btn('A story for you','kid.open','k.change',{full:true,kind:'tonal',ic:'book'});
 return scr('My people',out,{say:'My people. Touch a face.'});
});
L.act('kid.openMyPeople',function(){go('k.people');});
L.act('kid.person',function(c,id){
 L.sheet('k',function(){
  var nm=personLabel(id),q=ppl().filter(function(x){return x.id===id;})[0]||{};
  return '<div class="kx-col" style="align-items:center;text-align:center">'+K.avatar(nm.charAt(0).toUpperCase(),{size:84,tone:id==='dad'?'accent':undefined,label:nm})+'<h2 class="kx-h">'+E(nm)+'</h2>'+
   '<div class="kx-row" style="width:100%">'+(reachOf(q,'calls')?'<div style="flex:1">'+btn('Call','kid.callSheet',id,{full:true,ic:'video'})+'</div>':'')+(reachOf(q,'messages')?'<div style="flex:1">'+btn('Message','kid.msgTo',id,{full:true,kind:'tonal',ic:'chat'})+'</div>':'')+'</div>'+
   btn('Change what I call them','kid.rename',id,{full:true,kind:'ghost',ic:'pencil'})+'</div>';});
});
L.act('kid.callSheet',function(c,id){L.closeSheet('k');callG(id);});
L.act('kid.msgTo',function(c,id){L.closeSheet('k');L.emit('kid:compose',{to:id});openMsgs();});
L.act('kid.rename',function(c,gid){
 var nick=c.arg2;
 if(nick==null){ /* open the picker */
  ens().draft.nick='';
  L.sheet('k',function(){
   var bank=gid==='dad'?BANK_DAD:gid==='mom'?BANK_MOM:BANK_OTHER,cur=child().nicknames&&child().nicknames[gid];
   var q=ppl().filter(function(x){return x.id===gid;})[0]||gl().filter(function(x){return x.id===gid;})[0]||{};
   return '<div class="kx-col"><div class="kx-row" style="justify-content:center">'+K.avatar((personLabel(gid)).charAt(0).toUpperCase(),{size:64,label:personLabel(gid)})+'</div><h2 class="kx-h" style="text-align:center">What do you call '+E(q.name||'them')+'?</h2>'+
    '<div class="kx-row" style="justify-content:center">'+bank.map(function(w){return '<button type="button" class="kx-opt'+(cur===w?' sel':'')+'" data-act="kid.rename" data-arg="'+A(gid)+'" data-arg2="'+A(w)+'">'+E(w)+'</button>';}).join('')+'</div>'+
    '<label class="kx-cap" for="kx-nick">Or type your own</label><input id="kx-nick" class="kx-in" data-bind="kid.draft.nick" maxlength="24" autocomplete="off" value="'+A(ens().draft.nick)+'">'+
    btn('Use this name','kid.rename',gid,{full:true,arg2:'__typed',ic:'check'})+(cur?btn('Back to the usual','kid.rename',gid,{full:true,kind:'ghost',arg2:'__reset'}):'')+'</div>';});
  return;
 }
 if(nick==='__typed')nick=ens().draft.nick||'';
 if(nick==='__reset')nick='';
 var r=L.labels.rename(gid,nick,'child');
 L.closeSheet('k');
 if(r&&r.ok)toast(nick?('Now it says '+nick):'Back to the usual','heart');
});

/* ===================================================================== MY DAY == */
function stepDone(id){return !!ens().ticks.done[id];}
def('k.day','My day',function(c){
 var k=ens(),steps=P().routine||[],pairs=P().firstThen||[],pp=tp(),part=nowPart(),out='';
 var pct=Math.round((pp.h*60+pp.min)/14.4);
 out+=card(K.ribbon({now:pct})+'<p class="kx-p"><b>'+E(part)+'</b>. '+E(nextLine())+'</p>');
 var icons={'Morning':'sun','School':'book','After school':'puzzle','Evening':'home','Bedtime':'moon','Night':'moon'};
 out+='<div class="kx-col" role="list">'+['Morning','School','After school','Evening','Bedtime'].map(function(n){var on=n===part;return '<div class="kx-rowb plain" style="'+(on?'border-color:var(--pri);border-width:3px':'')+'" role="listitem"><span class="ric">'+I(icons[n],24,1.9)+'</span><span class="rt"><b>'+E(n)+'</b></span>'+(on?'<span class="ric" style="background:var(--pri);color:var(--onPri)" aria-label="Now">'+I('chevR',22,2.4)+'</span>':'')+'</div>';}).join('')+'</div>';
 var cur=null,ci=-1;pairs.forEach(function(q,i){if(!cur&&!stepDone('ft'+i)){cur=q;ci=i;}});if(!cur&&pairs.length){cur=pairs[pairs.length-1];ci=pairs.length-1;}
 if(cur){
  var fd=stepDone('ft'+ci);
  out+='<h2 class="kx-h">First, then</h2><div class="kx-grid kx-g2">'+
   '<button type="button" class="kx-tile" data-act="kid.tick" data-arg="ft'+ci+'" aria-pressed="'+fd+'" aria-label="First: '+A(cur.first)+'">'+I('check',42,1.8)+'<span>First</span><b>'+E(cur.first)+'</b>'+(fd?'<span class="kx-ban" style="padding:4px 10px">'+I('check',22,2.4)+'</span>':'')+'</button>'+
   '<div class="kx-tile'+(fd?' sel':' dim')+'" role="img" aria-label="Then: '+A(cur.then)+'">'+I('smile',42,1.8)+'<span>Then</span><b>'+E(cur.then)+'</b></div></div>';
 }
 if(steps.length){
  out+='<h2 class="kx-h">My routine</h2><div class="kx-col">'+steps.map(function(s,i){var d=stepDone('r'+i);
   return '<button type="button" class="kx-rowb" data-act="kid.tick" data-arg="r'+i+'" aria-pressed="'+d+'"><span class="ric">'+I('clock',24,1.9)+'</span><span class="rt"><b>'+E(s.text)+'</b>'+(s.time?'<small>'+E(s.time)+'</small>':'')+'</span><span class="ric" style="'+(d?'background:var(--ok);color:#fff':'background:var(--surface3);color:transparent')+'">'+I('check',24,2.6)+'</span></button>';}).join('')+'</div>';
 }
 if(!pairs.length&&!steps.length)out+=card(p('Your grown-up can put pictures here for your day.'),'flat');
 return scr('My day',out,{say:part+'. '+nextLine()});
});
L.act('kid.tick',function(c,id){var d=ens().ticks.done;if(d[id])delete d[id];else d[id]=true;});

/* ================================================================== GAMES == */
function stopAuto(){if(warTimer){clearInterval(warTimer);warTimer=null;}var g=L.S.kid&&L.S.kid.game;if(g&&g.auto)g.auto=false;}
var warTimer=null;
var GAMES=[
 ['ttt','Tic-tac-toe','grid3',4],['c4','Connect 4','target',5],['mem','Memory pairs','puzzle',3],['war','War','dice',5],['word','Guess the word','book',7],['pict','Draw and guess','brush',4]];
def('k.play','Games',function(c){
 var a=age(),open=playOpen(),g=GAMES.filter(function(x){return a>=x[3];});
 var out=windNote()+(open?cap('Play with the game, or take turns with a friend.'):banner('The games are resting for now. They wake up '+(playWin()?'at '+fmt12(playWin().from):'later')+'.','moon','soft'));
 out+='<div class="kx-grid kx-g2">'+g.map(function(x){return '<button type="button" class="kx-tile'+(open?'':' dim')+'" data-act="kid.play" data-arg="'+x[0]+'" aria-label="'+A(x[1])+'"><span class="tic">'+I(x[2],30,1.8)+'</span><span>'+E(x[1])+'</span></button>';}).join('')+'</div>';
 return scr(ttitle('play'),out,{say:'Pick a game.'});
});
L.act('kid.play',function(c,id){
 if(!playOpen()){restSheet();return;}
 stopAuto();var k=ens();
 k.game={type:id,phase:'setup'};
 if(id==='mem'||id==='war'||id==='word'||id==='pict')startGame(id);
 go('k.g.'+id);
});
function startGame(id){
 var k=ens(),g=k.game;if(!g||g.type!==id)g=k.game={type:id};
 g.phase='play';g.res=null;g.busy=false;
 if(id==='ttt'){g.b=['','','','','','','','',''];g.turn='x';}
 if(id==='c4'){g.b=[];for(var i=0;i<42;i++)g.b.push('');g.turn='me';g.win=null;}
 if(id==='mem'){var n=eb()==='t57'?4:eb()==='t812'?6:8,icons=['star','heart','sun','moon','leaf','bell','book','pawn','key','puzzle'],cols=['#c8473f','#3a78c4','#e08a2e','#4a8a52','#7a56b8','#d9679b','#3a9a92','#8a5a3a'];
   var set=shuffle(icons).slice(0,n),cards=[];set.forEach(function(ic,i){cards.push({ic:ic,col:cols[i%cols.length],up:false,m:false});cards.push({ic:ic,col:cols[i%cols.length],up:false,m:false});});
   g.cards=shuffle(cards);g.first=-1;}
 if(id==='war'){var deck=[];for(var s=0;s<2;s++)for(var r=1;r<=10;r++)deck.push({r:r,s:s});deck=shuffle(deck);g.a=deck.slice(0,10);g.b=deck.slice(10);g.ta=null;g.tb=null;g.pot=[];g.flips=0;g.note='';g.auto=false;}
 if(id==='word'){var W=WORDS[eb()]||WORDS.t812,w=pick(W);g.word=w[0];g.hint=w[1];g.guessed=[];g.wrong=0;}
 if(id==='pict'){g.mode=g.mode||'guess';g.pic=rnd(PICS.length);g.layers=1;g.choices=pictChoices(g.pic);g.drawing=false;g.revealed=false;}
}
L.act('kid.g.start',function(c,id){var k=ens();k.game=k.game&&k.game.type===id?k.game:{type:id};var g=k.game;if(c.arg2){if(id==='ttt'||id==='c4'){if(c.arg2==='two'){g.mode='two';g.lvl=g.lvl||'normal';}else{g.mode='cpu';g.lvl=c.arg2;}}}
 startGame(id);
 if(id==='ttt'||id==='c4'){g.mode=g.mode||'cpu';}});
L.act('kid.g.again',function(c,id){var g=ens().game;if(!g)return;var m=g.mode,l=g.lvl;if(id==='pict'){startGame('pict');return;}startGame(id);g.mode=m;g.lvl=l;});
function setupPanel(id,title){
 var g=ens().game||{},lv=['easy','normal','hard'];
 return '<div class="kx-col"><h2 class="kx-h">'+E(title)+'</h2>'+cap('You play against the game. Pick how tricky it should be.')+
  '<div class="kx-grid kx-g3">'+lv.map(function(l,i){return '<button type="button" class="kx-tile" data-act="kid.g.start" data-arg="'+id+'" data-arg2="'+l+'"><span class="tic">'+[0,1,2].slice(0,i+1).map(function(){return I('star',16,2);}).join('')+'</span><span>'+['Easy','Normal','Hard'][i]+'</span></button>';}).join('')+'</div>'+
  btn('Take turns with a friend','kid.g.start',id,{full:true,kind:'tonal',ic:'users',arg2:'two'})+'</div>';
}
function resBanner(txt,again,id){return '<div class="kx-ban" role="status">'+I('sparkle',26,2)+'<span>'+E(txt)+'</span></div><div class="kx-grid kx-g2">'+btn('Play again','kid.g.again',id,{ic:'refresh'})+btn('Other games','kid.open','k.play',{kind:'tonal',ic:'dice'})+'</div>';}
function gscreen(id,title,fn){def('k.g.'+id,title,function(c){var k=ens();if(!k.game||k.game.type!==id){k.game={type:id,phase:'setup'};if(id==='mem'||id==='war'||id==='word'||id==='pict')startGame(id);}
 if(!playOpen())return scr(title,banner('The games are resting for now.','moon','soft')+btn('Draw instead','kid.open','k.draw',{full:true}),{});
 return scr(title,windNote()+fn(k.game,c),{});});}

/* ------------------------------------------------------------ tic-tac-toe -- */
var LN3=[[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
function tRes(b){for(var i=0;i<8;i++){var l=LN3[i];if(b[l[0]]&&b[l[0]]===b[l[1]]&&b[l[1]]===b[l[2]])return {w:b[l[0]],line:l};}return b.every(function(x){return x;})?{w:'tie'}:null;}
function tMini(b,turn,me){var r=tRes(b);if(r){return r.w==='tie'?0:(r.w===me?10:-10);}var best=turn===me?-99:99;
 for(var i=0;i<9;i++){if(b[i])continue;b[i]=turn;var s=tMini(b,turn==='x'?'o':'x',me);b[i]='';if(turn===me)best=Math.max(best,s);else best=Math.min(best,s);}return best;}
function tCpu(b,lvl){
 var em=[];for(var i=0;i<9;i++)if(!b[i])em.push(i);
 function tryWin(p){for(var j=0;j<em.length;j++){var t=b.slice();t[em[j]]=p;var r=tRes(t);if(r&&r.w===p)return em[j];}return -1;}
 if(lvl==='easy')return pick(em);
 var w=tryWin('o');if(w>=0)return w;var bl=tryWin('x');if(bl>=0)return bl;
 if(lvl==='normal'){if(!b[4])return 4;return pick(em);}
 var best=-99,mv=[];em.forEach(function(m){var t=b.slice();t[m]='o';var s=tMini(t,'x','o');if(s>best){best=s;mv=[m];}else if(s===best)mv.push(m);});return pick(mv);
}
function xo(v){return v==='x'?'<span style="color:var(--pri)">'+I('x',46,3)+'</span>':v==='o'?'<span style="color:var(--accent)"><svg viewBox="0 0 24 24" width="46" height="46" fill="none" stroke="currentColor" stroke-width="3" aria-hidden="true"><circle cx="12" cy="12" r="7.5"/></svg></span>':'';}
gscreen('ttt','Tic-tac-toe',function(g){
 if(g.phase==='setup'||!g.b)return setupPanel('ttt','Tic-tac-toe');
 var cells=g.b.map(function(v,i){var win=g.res&&g.res.line&&g.res.line.indexOf(i)>=0;return '<button type="button" class="kx-cell" data-act="kid.ttt" data-arg="'+i+'" aria-label="Square '+(i+1)+', '+(v==='x'?'X':v==='o'?'O':'empty')+'" style="'+(win?'background:var(--priC);border-color:var(--pri)':'')+'"'+(v||g.res?' aria-disabled="true"':'')+'>'+xo(v)+'</button>';}).join('');
 var msg;if(g.res){var w=g.res.w;msg=resBanner(w==='tie'?'A tie. Nicely played.':g.mode==='two'?((w==='x'?'X':'O')+' got three in a row.'):w==='x'?'Three in a row. You got it.':'The game got three in a row. Nicely played.','','ttt');}
 else msg=cap(g.mode==='two'?((g.turn==='x'?'X':'O')+', your turn.'):(g.busy?'The game is thinking...':'Your turn. You are X.'));
 return '<div class="kx-board" style="grid-template-columns:repeat(3,1fr)" role="grid" aria-label="Board">'+cells+'</div>'+msg;
});
L.act('kid.ttt',function(c,i){
 var g=ens().game;if(!g||g.type!=='ttt'||g.res||g.busy)return;i=+i;if(g.b[i])return;
 g.b[i]=g.turn;g.res=tRes(g.b);
 if(g.res)return;
 if(g.mode==='two'){g.turn=g.turn==='x'?'o':'x';return;}
 g.turn='o';g.busy=true;
 setTimeout(function(){var gg=L.S.kid&&L.S.kid.game;if(!gg||gg.type!=='ttt'||gg.res||!gg.b)return;var m=tCpu(gg.b,gg.lvl||'normal');gg.b[m]='o';gg.res=tRes(gg.b);gg.turn='x';gg.busy=false;L.queueRender();},500);
});
/* ----------------------------------------------------------------- connect 4 -- */
function c4Drop(b,col,pl){for(var r=5;r>=0;r--){if(!b[r*7+col]){var nb=b.slice();nb[r*7+col]=pl;return nb;}}return null;}
function c4Line(b,pl){var D=[[0,1],[1,0],[1,1],[1,-1]];for(var r=0;r<6;r++)for(var c=0;c<7;c++)for(var d=0;d<4;d++){var dr=D[d][0],dc=D[d][1],cells=[];for(var k=0;k<4;k++){var rr=r+dr*k,cc=c+dc*k;if(rr<0||rr>5||cc<0||cc>6||b[rr*7+cc]!==pl){cells=null;break;}cells.push(rr*7+cc);}if(cells)return cells;}return null;}
function c4Eval(b,pl,op){
 var s=0,D=[[0,1],[1,0],[1,1],[1,-1]];
 for(var r=0;r<6;r++)for(var c=0;c<7;c++)for(var d=0;d<4;d++){var dr=D[d][0],dc=D[d][1],mine=0,theirs=0,ok=true;for(var k=0;k<4;k++){var rr=r+dr*k,cc=c+dc*k;if(rr<0||rr>5||cc<0||cc>6){ok=false;break;}var v=b[rr*7+cc];if(v===pl)mine++;else if(v===op)theirs++;}
  if(!ok)continue;if(mine&&!theirs)s+=[0,1,5,30,1000][mine];else if(theirs&&!mine)s-=[0,1,6,40,1000][theirs];}
 for(var q=0;q<6;q++)if(b[q*7+3]===pl)s+=3;return s;}
function c4Neg(b,depth,alpha,beta,pl,op){
 if(c4Line(b,op))return -100000-depth;if(b.every(function(x){return x;}))return 0;if(depth===0)return c4Eval(b,pl,op);
 var order=[3,2,4,1,5,0,6],best=-1e9;
 for(var i=0;i<7;i++){var nb=c4Drop(b,order[i],pl);if(!nb)continue;var s=-c4Neg(nb,depth-1,-beta,-alpha,op,pl);if(s>best)best=s;if(best>alpha)alpha=best;if(alpha>=beta)break;}
 return best;}
function c4Cpu(b,lvl){
 var cols=[];for(var c=0;c<7;c++)if(!b[c])cols.push(c);
 if(lvl==='easy')return pick(cols);
 for(var i=0;i<cols.length;i++){var nb=c4Drop(b,cols[i],'cpu');if(c4Line(nb,'cpu'))return cols[i];}
 for(var j=0;j<cols.length;j++){var nb2=c4Drop(b,cols[j],'me');if(c4Line(nb2,'me'))return cols[j];}
 if(lvl==='normal'){var safe=cols.filter(function(cc){var nb3=c4Drop(b,cc,'cpu');for(var m=0;m<7;m++){var n4=c4Drop(nb3,m,'me');if(n4&&c4Line(n4,'me'))return false;}return true;});var pool=safe.length?safe:cols;var w=[];pool.forEach(function(cc){var n=4-Math.abs(3-cc);for(var z=0;z<n;z++)w.push(cc);});return pick(w);}
 var best=-1e9,mv=[];cols.forEach(function(cc){var nb4=c4Drop(b,cc,'cpu');var s=-c4Neg(nb4,4,-1e9,1e9,'me','cpu');if(s>best){best=s;mv=[cc];}else if(s===best)mv.push(cc);});return pick(mv);}
gscreen('c4','Connect 4',function(g){
 if(g.phase==='setup'||!g.b)return setupPanel('c4','Connect 4');
 var cols='';for(var c=0;c<7;c++){var cells='';for(var r=0;r<6;r++){var v=g.b[r*7+c],w=g.win&&g.win.indexOf(r*7+c)>=0;cells+='<i class="'+(v==='me'?'me':v?'cpu':'')+(w?' win':'')+'"></i>';}
  cols+='<button type="button" data-act="kid.c4" data-arg="'+c+'" aria-label="Drop in column '+(c+1)+'">'+cells+'</button>';}
 var two=g.mode==='two',msg;
 if(g.res){msg=resBanner(g.res==='tie'?'The board is full. A tie. Nicely played.':two?((g.res==='me'?'Round pieces':'Square pieces')+' got four in a row.'):g.res==='me'?'Four in a row. You got it.':'The game got four in a row. Nicely played.','','c4');}
 else msg=cap(two?((g.turn==='me'?'Round':'Square')+' pieces, your turn.'):(g.busy?'The game is thinking...':'Your turn. You are the round pieces.'));
 return '<div class="kx-c4" role="group" aria-label="Board">'+cols+'</div>'+msg;
});
L.act('kid.c4',function(c,col){
 var g=ens().game;if(!g||g.type!=='c4'||g.res||g.busy)return;col=+col;var nb=c4Drop(g.b,col,g.turn);if(!nb)return;g.b=nb;
 var win=c4Line(g.b,g.turn);if(win){g.win=win;g.res=g.turn;return;}if(g.b.every(function(x){return x;})){g.res='tie';return;}
 if(g.mode==='two'){g.turn=g.turn==='me'?'cpu':'me';return;}
 g.turn='cpu';g.busy=true;
 setTimeout(function(){var gg=L.S.kid&&L.S.kid.game;if(!gg||gg.type!=='c4'||gg.res||!gg.b)return;var m=c4Cpu(gg.b,gg.lvl||'normal'),n2=c4Drop(gg.b,m,'cpu');if(n2){gg.b=n2;var w2=c4Line(gg.b,'cpu');if(w2){gg.win=w2;gg.res='cpu';}else if(gg.b.every(function(x){return x;}))gg.res='tie';}gg.turn='me';gg.busy=false;L.queueRender();},550);
});
/* ------------------------------------------------------------------------ war -- */
function cardHtml(cd,back){return back?'<div class="kx-card-pl back" aria-label="A face-down card"></div>':'<div class="kx-card-pl" style="color:'+(cd.s?'var(--accent)':'var(--pri)')+'" role="img" aria-label="'+cd.r+' of '+(cd.s?'circles':'squares')+'"><small>'+cd.r+'</small>'+cd.r+'</div>';}
function deckHtml(n,lbl){var h=n===0?0:Math.max(1,Math.min(5,Math.ceil(n/3)));return '<div class="kx-stack" role="img" aria-label="'+A(lbl)+'">'+(h?'<div class="st" style="height:'+(18+h*9)+'px"></div>':'<div class="st" style="height:18px;opacity:.25"></div>')+'<small class="kx-cap">'+E(lbl)+'</small></div>';}
function warFlip(g){
 if(g.res)return;
 if(!g.a.length||!g.b.length){g.res=g.a.length?'me':'cpu';return;}
 var ca=g.a.shift(),cb=g.b.shift();g.ta=ca;g.tb=cb;g.pot=g.pot.concat([ca,cb]);g.flips++;
 if(ca.r===cb.r){g.note='Same! The next flip takes them all.';}
 else if(ca.r>cb.r){g.a=g.a.concat(shuffle(g.pot));g.pot=[];g.note='You take them.';}
 else{g.b=g.b.concat(shuffle(g.pot));g.pot=[];g.note='The game takes them.';}
 if(!g.a.length||!g.b.length){if(!g.pot.length||true){g.res=g.a.length?'me':g.b.length?'cpu':'tie';}}
 if(g.flips>=120&&!g.res){g.res='tie';}
}
gscreen('war','War',function(g){
 if(!g.a)startGame('war');
 var msg;
 if(g.res)msg=resBanner(g.res==='me'?'All the cards are yours. Nicely played.':g.res==='cpu'?'The game has all the cards this time. Nicely played.':'The cards are tired. Call it even.','','war');
 else msg='<div class="kx-grid kx-g2">'+btn('Flip','kid.war.flip',null,{ic:'refresh'})+btn(g.auto?'Stop':'Keep flipping','kid.war.auto',null,{kind:'tonal',ic:g.auto?'stop':'play'})+'</div>';
 return '<div class="kx-row" style="justify-content:space-around;align-items:flex-start">'+deckHtml(g.a.length,'Your cards')+deckHtml(g.b.length,'The game’s cards')+'</div>'+
  '<div class="kx-row" style="justify-content:center;gap:28px;min-height:140px">'+(g.ta?cardHtml(g.ta):cardHtml(null,true))+(g.tb?cardHtml(g.tb):cardHtml(null,true))+'</div>'+
  (g.note&&!g.res?'<p class="kx-p" style="text-align:center" role="status">'+E(g.note)+'</p>':'')+msg;
});
L.act('kid.war.flip',function(){var g=ens().game;if(g&&g.type==='war')warFlip(g);});
L.act('kid.war.auto',function(){var g=ens().game;if(!g||g.type!=='war')return;
 if(g.auto){stopAuto();return;}
 g.auto=true;warTimer=setInterval(function(){var gg=L.S.kid&&L.S.kid.game,cur=L.current('k');if(!gg||gg.type!=='war'||!gg.auto||gg.res||!cur||cur.id!=='k.g.war'){stopAuto();L.queueRender();return;}warFlip(gg);if(gg.res)gg.auto=false;L.queueRender();},450);});
/* ---------------------------------------------------------------- memory pairs -- */
gscreen('mem','Memory pairs',function(g){
 if(!g.cards)startGame('mem');
 var n=g.cards.length,cols=n<=8?4:n<=12?4:4,done=g.cards.every(function(c){return c.m;});
 var cells=g.cards.map(function(cd,i){var show=cd.up||cd.m;return '<button type="button" class="kx-cell kx-memc" data-act="kid.mem" data-arg="'+i+'" aria-label="'+(show?cd.ic:'Card '+(i+1)+', face down')+'" style="'+(show?'color:'+cd.col+';background:var(--surface)':'background:repeating-linear-gradient(45deg,var(--priC),var(--priC) 8px,var(--priC2) 8px,var(--priC2) 16px);border-color:var(--pri)')+(cd.m?';opacity:.72':'')+'">'+(show?I(cd.ic,40,2):'')+'</button>';}).join('');
 return '<div class="kx-board" style="grid-template-columns:repeat('+cols+',1fr);max-width:440px">'+cells+'</div>'+(done?resBanner('All the pairs are together. Nicely done.','','mem'):cap('Turn two cards. Find the pairs.'));
});
L.act('kid.mem',function(c,i){
 var g=ens().game;if(!g||g.type!=='mem'||g.busy)return;i=+i;var cd=g.cards[i];if(!cd||cd.up||cd.m)return;cd.up=true;
 if(g.first<0){g.first=i;return;}
 var a=g.cards[g.first];
 if(a.ic===cd.ic){a.m=cd.m=true;a.up=cd.up=false;g.first=-1;return;}
 g.busy=true;var f=g.first;g.first=-1;
 setTimeout(function(){var gg=L.S.kid&&L.S.kid.game;if(!gg||gg.type!=='mem'||!gg.cards)return;gg.cards.forEach(function(x){if(!x.m)x.up=false;});gg.busy=false;L.queueRender();},acc().reduceMotion?1200:900);
});
/* ------------------------------------------------------------------ guess the word -- */
var WORDS={t57:[['CAT','an animal'],['DOG','an animal'],['SUN','in the sky'],['HAT','you wear it'],['BED','you sleep in it'],['FISH','swims in water'],['TREE','it has leaves'],['MOON','you see it at night'],['BOOK','you read it'],['STAR','twinkles at night']],
 t812:[['GARDEN','where plants grow'],['ORANGE','a fruit and a colour'],['PLANET','it goes around a sun'],['BRIDGE','crosses a river'],['CASTLE','a king might live there'],['RABBIT','an animal with long ears'],['BUTTER','goes on toast'],['PUZZLE','pieces fit together'],['DRAGON','in stories'],['ISLAND','water all around']],
 t1317:[['LANTERN','a light you carry'],['MOUNTAIN','very big and rocky'],['HARMONY','notes that fit together'],['JOURNEY','a long trip'],['SKETCH','a quick drawing'],['COMPASS','it points north'],['VOLCANO','it can erupt'],['LIBRARY','full of books'],['GALAXY','stars and more stars'],['BICYCLE','two wheels']]};
function wordFlower(left){var out='<svg viewBox="0 0 120 120" width="120" height="120" role="img" aria-label="A flower losing its petals" style="display:block;margin:0 auto">';for(var i=0;i<6;i++){var a=i*Math.PI/3,on=i<left;out+='<ellipse cx="'+(60+Math.cos(a)*30).toFixed(1)+'" cy="'+(55+Math.sin(a)*30).toFixed(1)+'" rx="18" ry="11" transform="rotate('+(a*180/Math.PI).toFixed(0)+' '+(60+Math.cos(a)*30).toFixed(1)+' '+(55+Math.sin(a)*30).toFixed(1)+')" fill="'+(on?'var(--accent)':'none')+'" stroke="var(--accent)" stroke-width="2" opacity="'+(on?1:.3)+'"/>';}return out+'<circle cx="60" cy="55" r="14" fill="var(--dpMorning)"/><path d="M60 70v44" stroke="var(--pri)" stroke-width="5"/></svg>';}
gscreen('word','Guess the word',function(g){
 if(!g.word)startGame('word');
 var left=6-g.wrong,won=g.word.split('').every(function(ch){return g.guessed.indexOf(ch)>=0;}),lost=g.wrong>=6;
 var blanks='<div class="kx-row" style="justify-content:center;gap:8px" aria-label="'+(won||lost?'The word is '+g.word:'A word with '+g.word.length+' letters')+'">'+g.word.split('').map(function(ch){var s=g.guessed.indexOf(ch)>=0||lost;return '<span style="width:44px;height:56px;border-bottom:4px solid var(--ink);display:grid;place-items:center;font:700 32px var(--font-display);color:'+(s&&!g.guessed.includes(ch)?'var(--accent)':'var(--ink)')+'">'+(s?ch:'')+'</span>';}).join('')+'</div>';
 var keys='<div class="kx-row" style="justify-content:center;gap:6px">'+'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').map(function(ch){var used=g.guessed.indexOf(ch)>=0;return '<button type="button" class="kx-key" data-act="kid.word" data-arg="'+ch+'"'+(used||won||lost?' disabled':'')+' aria-label="'+ch+(used?', used':'')+'" style="'+(used&&g.word.indexOf(ch)>=0?'background:var(--okC)':'')+'">'+ch+'</button>';}).join('')+'</div>';
 var msg=won?resBanner('You found it: '+g.word+'. Nicely done.','','word'):lost?resBanner('The word was '+g.word+'. Want to try another?','','word'):'';
 return wordFlower(left)+cap('Hint: '+g.hint)+blanks+(won||lost?msg:keys)+'<div class="kx-row" style="justify-content:center">'+sayBtn('The hint is: '+g.hint)+'</div>';
});
L.act('kid.word',function(c,ch){var g=ens().game;if(!g||g.type!=='word'||g.guessed.indexOf(ch)>=0)return;g.guessed.push(ch);if(g.word.indexOf(ch)<0)g.wrong++;});
/* ---------------------------------------------------------------- draw and guess -- */
var PICS=[
 {w:'sun',l:['<circle cx="100" cy="90" r="38" fill="#e6c13a" stroke="#222" stroke-width="4"/>','<g stroke="#e08a2e" stroke-width="6" stroke-linecap="round"><path d="M100 28v-16M100 168v16M38 90H20M162 90h18M56 46l-12-12M144 134l12 12M144 46l12-12M56 134l-12 12"/></g>','<g stroke="#222" stroke-width="4" stroke-linecap="round" fill="none"><circle cx="88" cy="82" r="2"/><circle cx="112" cy="82" r="2"/><path d="M86 100q14 12 28 0"/></g>']},
 {w:'house',l:['<rect x="50" y="90" width="100" height="70" fill="#d9a066" stroke="#222" stroke-width="4"/>','<path d="M40 92l60-52 60 52z" fill="#c8473f" stroke="#222" stroke-width="4" stroke-linejoin="round"/>','<rect x="90" y="118" width="22" height="42" fill="#7a5a3a" stroke="#222" stroke-width="3"/><rect x="62" y="104" width="20" height="20" fill="#9fd0f0" stroke="#222" stroke-width="3"/>']},
 {w:'fish',l:['<ellipse cx="90" cy="95" rx="55" ry="34" fill="#3a9a92" stroke="#222" stroke-width="4"/>','<path d="M140 95l38-30v60z" fill="#3a78c4" stroke="#222" stroke-width="4" stroke-linejoin="round"/>','<circle cx="65" cy="88" r="5" fill="#222"/><path d="M85 60q15-18 30 0" fill="none" stroke="#222" stroke-width="4"/>']},
 {w:'tree',l:['<rect x="92" y="110" width="18" height="55" fill="#7a5a3a" stroke="#222" stroke-width="4"/>','<circle cx="101" cy="80" r="46" fill="#4a8a52" stroke="#222" stroke-width="4"/>','<g fill="#c8473f"><circle cx="85" cy="70" r="6"/><circle cx="112" cy="88" r="6"/><circle cx="98" cy="58" r="6"/></g>']},
 {w:'boat',l:['<path d="M35 115h130l-20 36H55z" fill="#c8473f" stroke="#222" stroke-width="4" stroke-linejoin="round"/>','<path d="M100 28v84l48-12z" fill="#fff" stroke="#222" stroke-width="4" stroke-linejoin="round"/><path d="M96 38v74l-40-10z" fill="#e6c13a" stroke="#222" stroke-width="4" stroke-linejoin="round"/>','<path d="M10 165q15-12 30 0t30 0 30 0 30 0 30 0 30 0" fill="none" stroke="#3a78c4" stroke-width="5" stroke-linecap="round"/>']}
];
var PICWORDS=['sun','house','fish','tree','boat','cat','car','moon','cake','bird'];
function pictChoices(i){var w=PICS[i].w,o=shuffle(PICWORDS.filter(function(x){return x!==w;})).slice(0,3);o.push(w);return shuffle(o);}
function picSvg(i,n){return '<svg viewBox="0 0 200 180" width="100%" style="max-width:340px;display:block;margin:0 auto;background:#fff;border-radius:22px;border:2px solid var(--edge)" role="img" aria-label="A picture being drawn">'+PICS[i].l.slice(0,n).join('')+'</svg>';}
gscreen('pict','Draw and guess',function(g){
 if(g.pic==null)startGame('pict');
 var tabs='<div class="kx-grid kx-g2">'+btn('The game draws','kid.pict.mode','guess',{kind:g.mode==='guess'?'pri':'tonal'})+btn('I draw','kid.pict.mode','draw',{kind:g.mode==='draw'?'pri':'tonal'})+'</div>';
 if(g.mode==='draw'){
  var w=PICS[g.pic].w;
  var st=cvState('doodle:pict',480,330);
  if(g.revealed)return tabs+'<img alt="" style="display:none">'+'<div class="kx-card"><p class="kx-p" style="text-align:center">Show your drawing to a friend. Can they guess?</p>'+cvEl('doodle:pict',480,330,'Your drawing')+'</div>'+
   '<div class="kx-ban soft">'+I('sparkle',26,2)+'<span>It was a '+E(w)+'.</span></div>'+btn('Draw another','kid.pict.next',null,{full:true,ic:'refresh'});
  return tabs+'<div class="kx-card tint"><p class="kx-p" style="text-align:center">Draw a <b>'+E(w)+'</b>. Do not tell anyone!</p></div>'+cvEl('doodle:pict',480,330,'Drawing area')+toolbar('doodle:pict',{eraser:true})+btn('Done. Show a friend','kid.pict.show',null,{full:true,ic:'eye'});
 }
 var done=g.revealed;
 var ch='<div class="kx-grid kx-g2">'+g.choices.map(function(w){return '<button type="button" class="kx-opt" style="justify-content:center;font-size:19px" data-act="kid.pict.guess" data-arg="'+w+'"'+(done?' disabled':'')+'>'+E(w)+'</button>';}).join('')+'</div>';
 return tabs+picSvg(g.pic,done?3:g.layers)+(done?'<div class="kx-ban">'+I('sparkle',26,2)+'<span>Yes! It is a '+E(PICS[g.pic].w)+'.</span></div><div class="kx-grid kx-g2">'+btn('Another picture','kid.pict.next',null,{ic:'refresh'})+btn('Other games','kid.open','k.play',{kind:'tonal',ic:'dice'})+'</div>':cap(g.layers<3?'What is it? Guess, or ask for more lines.':'What is it?')+ch+(g.layers<3?btn('More lines','kid.pict.more',null,{full:true,kind:'tonal',ic:'plus'}):''));
});
L.act('kid.pict.mode',function(c,m){var g=ens().game;if(!g)return;g.mode=m;g.revealed=false;g.layers=1;g.pic=rnd(PICS.length);g.choices=pictChoices(g.pic);var st=CVS['doodle:pict'];if(st&&m==='draw'){st.ctx.fillStyle='#fff';st.ctx.fillRect(0,0,st.w,st.h);}});
L.act('kid.pict.more',function(){var g=ens().game;if(g&&g.layers<3)g.layers++;});
L.act('kid.pict.guess',function(c,w){var g=ens().game;if(!g)return;if(w===PICS[g.pic].w)g.revealed=true;else if(g.layers<3)g.layers++;});
L.act('kid.pict.next',function(){var g=ens().game;if(!g)return;g.pic=rnd(PICS.length);g.layers=1;g.choices=pictChoices(g.pic);g.revealed=false;var st=CVS['doodle:pict'];if(st){st.ctx.fillStyle='#fff';st.ctx.fillRect(0,0,st.w,st.h);}});
L.act('kid.pict.show',function(){var g=ens().game;if(g)g.revealed=true;});

/* ============================================================ COLOUR OF THE DAY == */
var COLOURS=[['Red','#c8473f'],['Orange','#e08a2e'],['Yellow','#e6c13a'],['Green','#4a8a52'],['Teal','#3a9a92'],['Blue','#3a78c4'],['Purple','#7a56b8'],['Pink','#d9679b']];
function colName(h){var r=COLOURS.filter(function(c){return c[1]===h;})[0];return r?r[0]:'';}
function tabOf(n,d){var k=ens();k.tab=k.tab||{};return k.tab[n]==null?d:k.tab[n];}
function setTab(n,v){var k=ens();k.tab=k.tab||{};k.tab[n]=v;}
L.act('kid.tab',function(c,v){setTab(c.arg2,v);});
def('k.colour','Colour',function(c){
 var k=ens(),cd=k.colourDay,a=age(),hx=colourHex(),out='';
 if(P().colourAsk!==false)out+='<h2 class="kx-h">Which colour do you want today?</h2><div class="kx-faces" role="radiogroup" aria-label="Colour of the day">'+COLOURS.map(function(x){var on=cd&&cd.pick===x[1];return '<button type="button" class="kx-sw'+(on?' sel':'')+'" role="radio" aria-checked="'+on+'" aria-label="'+x[0]+'" style="background:'+x[1]+'" data-act="kid.colourPick" data-arg="'+x[1]+'">'+(on?'<span style="color:#fff;display:grid;place-items:center">'+I('check',30,3)+'</span>':'')+'</button>';}).join('')+'</div>';
 if(cd&&P().colourAsk!==false)out+=card('<p class="kx-p"><b>Today is '+E(colName(cd.pick)||'your colour')+'.</b></p>'+cap('It is the pencil colour in everything you make today.'),'tint');
 if(hx)out+=rowb({plain:true,av:'<span style="width:44px;height:44px;border-radius:50%;background:'+hx+';flex:none;border:3px solid var(--surface);box-shadow:0 0 0 1.5px var(--edge)"></span>',title:'Your colour'+(colourWord()?': '+colourWord():''),sub:'This one is yours. It stays the same.'});
 var act=[['k.c.sort','Colour sort','palette'],['k.draw','Draw','brush']];
 if(a>=5)act.push(['k.c.path','Path code','target'],['k.c.critter','Colour critter','pawn']);
 if(a>=8)act.push(['k.c.pixel','Pixel garden','leaf']);
 out+='<div class="kx-grid kx-g2">'+act.map(function(x){return '<button type="button" class="kx-tile" data-act="kid.open" data-arg="'+x[0]+'" aria-label="'+A(x[1])+'"><span class="tic">'+I(x[2],30,1.8)+'</span><span>'+E(x[1])+'</span></button>';}).join('')+'</div>';
 return scr(ttitle('colour'),out,{say:'Which colour do you want today?'});
});
L.act('kid.colourPick',function(c,hx){var k=ens();k.colourDay={day:dayKey(),pick:hx};CVT.color=hx;if(CVT.tool==='erase')CVT.tool='brush';});
/* -- colour sort -- */
function newSort(){var cs=shuffle(COLOURS).slice(0,3),items=[];cs.forEach(function(x){items.push({c:x[1],on:true},{c:x[1],on:true});});return {pots:cs.map(function(x){return x[1];}),items:shuffle(items).map(function(x,i){x.i=i;return x;}),sel:-1,put:{}};}
def('k.c.sort','Colour sort',function(c){
 var k=ens(),s=k.act.sort;if(!s)s=k.act.sort=newSort();
 var done=s.items.every(function(x){return !x.on;});
 var items='<div class="kx-faces" style="justify-content:center">'+s.items.map(function(x){return x.on?'<button type="button" class="kx-sw'+(s.sel===x.i?' sel':'')+'" style="background:'+x.c+'" aria-label="A '+(colName(x.c)||'colour')+' dot" aria-pressed="'+(s.sel===x.i)+'" data-act="kid.sort.pick" data-arg="'+x.i+'"></button>':'';}).join('')+'</div>';
 var pots='<div class="kx-grid kx-g3">'+s.pots.map(function(h,i){var n=s.put[h]||0;return '<button type="button" class="kx-tile" style="border:5px solid '+h+';min-height:112px" aria-label="'+(colName(h)||'')+' pot" data-act="kid.sort.pot" data-arg="'+i+'"><span class="kx-faces" style="justify-content:center;gap:4px">'+[1,2].slice(0,n).map(function(){return '<i style="width:22px;height:22px;border-radius:50%;background:'+h+';display:block"></i>';}).join('')+'</span></button>';}).join('')+'</div>';
 return scr('Colour sort',cap('Tap a dot, then tap the pot with the same colour.')+items+pots+(done?'<div class="kx-ban">'+I('sparkle',26,2)+'<span>All sorted.</span></div>':'')+btn('New dots','kid.sort.new',null,{full:true,kind:'tonal',ic:'refresh'}));
});
L.act('kid.sort.new',function(){ens().act.sort=newSort();});
L.act('kid.sort.pick',function(c,i){var s=ens().act.sort;s.sel=s.sel===+i?-1:+i;});
L.act('kid.sort.pot',function(c,i){var s=ens().act.sort;if(s.sel<0)return;var it=s.items[s.sel],h=s.pots[+i];if(it&&it.on&&it.c===h){it.on=false;s.put[h]=(s.put[h]||0)+1;s.sel=-1;}});
/* -- path code -- */
var LEVELS=[{s:[0,4],star:[3,1],rocks:[[1,3],[2,2]]},{s:[0,4],star:[4,0],rocks:[[2,4],[2,3],[3,1]]},{s:[2,4],star:[2,0],rocks:[[2,2],[1,1],[3,3]]}];
def('k.c.path','Path code',function(c){
 var k=ens(),s=k.act.path;if(!s)s=k.act.path={lvl:0,prog:[],pos:null,trail:[],ran:false,ok:false};
 var L_=LEVELS[s.lvl%LEVELS.length],pos=s.pos||L_.s,cells='';
 function has(arr,x,y){return arr.some(function(r){return r[0]===x&&r[1]===y;});}
 for(var y=0;y<5;y++)for(var x=0;x<5;x++){var rock=has(L_.rocks,x,y),star=L_.star[0]===x&&L_.star[1]===y,me=pos[0]===x&&pos[1]===y,tr=has(s.trail,x,y);
  cells+='<div class="kx-cell" style="cursor:default;'+(tr?'background:var(--priC);':'')+(rock?'background:var(--surface3);':'')+'" role="img" aria-label="'+(me?'You are here':star?'The star':rock?'A rock':'Empty')+'">'+(me?I('pawn',34,2):star?'<span style="color:var(--dpMorning)">'+I('star',34,2)+'</span>':rock?I('layers',26,1.8):'')+'</div>';}
 var dirs={U:['Up',-90],D:['Down',90],L:['Left',180],R:['Right',0]};
 var pad_='<div class="kx-row" style="justify-content:center">'+Object.keys(dirs).map(function(d){return '<button type="button" class="kx-b tonal" aria-label="'+dirs[d][0]+'" data-act="kid.path.add" data-arg="'+d+'"'+(s.prog.length>=8?' disabled':'')+'><span style="display:inline-block;transform:rotate('+dirs[d][1]+'deg)">'+I('arrowR',26,2.4)+'</span></button>';}).join('')+'</div>';
 var strip='<div class="kx-strip" aria-label="Your steps">'+s.prog.map(function(d){return '<span aria-label="'+dirs[d][0]+'"><span style="display:inline-block;transform:rotate('+dirs[d][1]+'deg)">'+I('arrowR',20,2.6)+'</span></span>';}).join('')+'</div>';
 return scr('Path code',cap('Pick up to eight arrows, then press Go. Help the little pawn reach the star.')+'<div class="kx-board" style="grid-template-columns:repeat(5,1fr);max-width:320px;gap:4px">'+cells+'</div>'+pad_+strip+
  '<div class="kx-grid kx-g2">'+btn('Go','kid.path.go',null,{ic:'play',dis:!s.prog.length})+btn('Clear','kid.path.clear',null,{kind:'tonal',ic:'refresh'})+'</div>'+
  (s.ran?(s.ok?'<div class="kx-ban">'+I('star',26,2)+'<span>You found the star.</span></div>'+btn('Next puzzle','kid.path.next',null,{full:true,ic:'arrowR'}):'<div class="kx-ban soft">'+I('info',26,2)+'<span>Not there yet. Change the arrows and go again.</span></div>'):''));
});
L.act('kid.path.add',function(c,d){var s=ens().act.path;if(s.prog.length<8){s.prog.push(d);s.ran=false;s.pos=null;s.trail=[];}});
L.act('kid.path.clear',function(){var s=ens().act.path;s.prog=[];s.ran=false;s.pos=null;s.trail=[];s.ok=false;});
L.act('kid.path.next',function(){var s=ens().act.path;s.lvl++;s.prog=[];s.ran=false;s.pos=null;s.trail=[];s.ok=false;});
L.act('kid.path.go',function(){
 var s=ens().act.path,Lv=LEVELS[s.lvl%LEVELS.length],pos=Lv.s.slice(),trail=[pos.slice()];
 s.prog.forEach(function(d){var n=[pos[0]+(d==='R'?1:d==='L'?-1:0),pos[1]+(d==='D'?1:d==='U'?-1:0)];if(n[0]<0||n[0]>4||n[1]<0||n[1]>4)return;if(Lv.rocks.some(function(r){return r[0]===n[0]&&r[1]===n[1];}))return;pos=n;trail.push(n.slice());});
 s.pos=pos;s.trail=trail;s.ran=true;s.ok=(pos[0]===Lv.star[0]&&pos[1]===Lv.star[1]);
});
/* -- colour critter -- */
var CPART={body:'Body',belly:'Tummy',ears:'Ears',spots:'Spots'};
def('k.c.critter','Colour critter',function(c){
 var k=ens(),s=k.act.critter;if(!s)s=k.act.critter={sel:'body',c:{body:'#4a8a52',belly:'#e6c13a',ears:'#d9679b',spots:'#7a56b8'}};
 function part(id,inner){return '<g role="button" tabindex="0" aria-label="'+CPART[id]+(s.sel===id?', picked':'')+'" data-act="kid.crit.sel" data-arg="'+id+'" style="cursor:pointer">'+inner+'</g>';}
 var sel=function(id){return s.sel===id?' stroke="var(--focus)" stroke-width="6" stroke-dasharray="2 8"':' stroke="#222" stroke-width="3"';};
 var svg='<svg viewBox="0 0 240 230" width="100%" style="max-width:340px;display:block;margin:0 auto" aria-label="A critter to colour">'+
  part('ears','<ellipse cx="62" cy="48" rx="26" ry="38" fill="'+s.c.ears+'"'+sel('ears')+'/><ellipse cx="178" cy="48" rx="26" ry="38" fill="'+s.c.ears+'"'+sel('ears')+'/>')+
  part('body','<ellipse cx="120" cy="125" rx="86" ry="86" fill="'+s.c.body+'"'+sel('body')+'/>')+
  part('belly','<ellipse cx="120" cy="150" rx="46" ry="48" fill="'+s.c.belly+'"'+sel('belly')+'/>')+
  part('spots','<circle cx="76" cy="105" r="11" fill="'+s.c.spots+'"'+sel('spots')+'/><circle cx="168" cy="98" r="9" fill="'+s.c.spots+'"'+sel('spots')+'/><circle cx="150" cy="72" r="7" fill="'+s.c.spots+'"'+sel('spots')+'/>')+
  '<g aria-hidden="true"><circle cx="96" cy="108" r="8" fill="#222"/><circle cx="144" cy="108" r="8" fill="#222"/><path d="M104 126q16 14 32 0" fill="none" stroke="#222" stroke-width="4" stroke-linecap="round"/></g></svg>';
 var pal='<div class="kx-pal" role="radiogroup" aria-label="Colours for the '+CPART[s.sel]+'">'+PALETTE.map(function(h){return '<button type="button" class="kx-sw'+(s.c[s.sel]===h?' sel':'')+'" role="radio" aria-checked="'+(s.c[s.sel]===h)+'" aria-label="'+(colName(h)||h)+'" style="background:'+h+'" data-act="kid.crit.col" data-arg="'+h+'"></button>';}).join('')+'</div>';
 return scr('Colour critter',cap('Tap a part, then pick its colour.')+svg+'<div class="kx-row" style="justify-content:center">'+Object.keys(CPART).map(function(id){return '<button type="button" class="kx-opt'+(s.sel===id?' sel':'')+'" data-act="kid.crit.sel" data-arg="'+id+'">'+CPART[id]+'</button>';}).join('')+'</div>'+pal);
});
L.act('kid.crit.sel',function(c,id){ens().act.critter.sel=id;});
L.act('kid.crit.col',function(c,h){var s=ens().act.critter;s.c[s.sel]=h;});
/* -- pixel garden (age 8 and up) -- */
var GARDEN=['#4a8a52','#2f6b3a','#8fc27a','#e6c13a','#e08a2e','#c8473f','#d9679b','#7a56b8','#3a78c4','#9fd0f0','#8a5a3a','#ffffff'];
def('k.c.pixel','Pixel garden',function(c){
 var st=cvState('pix:garden',360,360,function(x,w,h){x.fillStyle='#f4f1e6';x.fillRect(0,0,w,h);x.strokeStyle='rgba(0,0,0,.12)';x.lineWidth=1;for(var i=0;i<=12;i++){x.beginPath();x.moveTo(i*30+.5,0);x.lineTo(i*30+.5,h);x.moveTo(0,i*30+.5);x.lineTo(w,i*30+.5);x.stroke();}});
 st.pix=true;st.cells=12;
 var pal='<div class="kx-pal" role="radiogroup" aria-label="Colours">'+GARDEN.map(function(h){return '<button type="button" class="kx-sw'+(CVT.color===h&&CVT.tool!=='erase'?' sel':'')+'" role="radio" aria-checked="'+(CVT.color===h)+'" aria-label="Colour '+h+'" style="background:'+h+'" data-act="kid.cv.color" data-arg="'+h+'"></button>';}).join('')+'</div>';
 return scr('Pixel garden',cap('Paint little squares to grow a garden.')+cvEl('pix:garden',360,360,'Pixel garden')+pal+'<div class="kx-row" style="justify-content:center">'+btn('Rub out','kid.cv.tool','erase',{kind:CVT.tool==='erase'?'pri':'tonal',ic:'undo'})+btn('Paint','kid.cv.tool','brush',{kind:CVT.tool!=='erase'?'pri':'tonal',ic:'brush'})+btn('Undo','kid.cv.undo','pix:garden',{kind:'ghost',ic:'rewind'})+'</div>'+btn('Keep this garden','kid.cv.save','pix:garden',{full:true,ic:'image',arg2:'My garden'}));
});

/* =============================================================== DRAW DESK == */
def('k.draw',ttitle('draw'),function(){
 return scr(ttitle('draw'),
  rowb({ic:'palette',title:'Colour a picture',sub:'Tap a space to fill it',act:'kid.draw.colouring'})+
  rowb({ic:'brush',title:'Doodle',sub:'Draw anything',act:'kid.draw.doodle'})+
  rowb({ic:'image',title:'My saved pictures',sub:'The ones I kept',act:'kid.open',arg:'k.pictures'}),{say:'Colour or draw.'});
});
L.act('kid.draw.colouring',function(){CVT.tool='fill';go('k.colouring');});
L.act('kid.draw.doodle',function(){CVT.tool='brush';go('k.doodle');});
def('k.colouring','Colour a picture',function(){
 var k=ens(),pg=tabOf('page','house'),id='colour:'+pg;
 cvState(id,480,360,function(x,w,h){PAGES[pg](x,w,h);}).fillable=true;CVS[id].redo=function(x,w,h){PAGES[pg](x,w,h);};
 return scr('Colour a picture','<div class="kx-row" style="justify-content:center">'+PAGENAMES.map(function(n){return '<button type="button" class="kx-opt'+(pg===n[0]?' sel':'')+'" data-act="kid.tab" data-arg="'+n[0]+'" data-arg2="page">'+n[1]+'</button>';}).join('')+'</div>'+
  cvEl(id,480,360,'Colouring page: '+pg)+toolbar(id,{fill:true,noSize:CVT.tool==='fill'})+btn('Keep this picture','kid.cv.save',id,{full:true,ic:'image',arg2:'Coloured '+pg}));
});
def('k.doodle','Doodle',function(){
 cvState('doodle:main',480,360);
 return scr('Doodle',cvEl('doodle:main',480,360,'Doodle area')+toolbar('doodle:main',{eraser:true})+btn('Keep this picture','kid.cv.save','doodle:main',{full:true,ic:'image',arg2:'My doodle'}));
});
def('k.pictures','My saved pictures',function(){
 var k=ens(),ps=k.pictures;
 if(!ps.length)return scr('My saved pictures',card('<div class="kx-col" style="align-items:center;text-align:center;padding:12px">'+K.spot('envelope',84)+h2('Nothing here yet')+p('Draw or colour something and keep it. It will be here.')+btn('Draw something','kid.open','k.doodle',{ic:'brush'})+'</div>'));
 return scr('My saved pictures','<div class="kx-grid kx-g2">'+ps.map(function(x){return '<button type="button" class="kx-tile" style="padding:8px" data-act="kid.pic" data-arg="'+x.id+'" aria-label="'+A(x.name)+'"><img src="'+x.data+'" alt="" style="width:100%;border-radius:16px;display:block"><span style="font-size:14px">'+E(x.name)+'</span></button>';}).join('')+'</div>');
});
L.act('kid.pic',function(c,id){
 var x=ens().pictures.filter(function(q){return q.id===id;})[0];if(!x)return;
 L.sheet('k','<div class="kx-col"><img src="'+x.data+'" alt="'+A(x.name)+'" style="width:100%;border-radius:20px"><h2 class="kx-h">'+E(x.name)+'</h2>'+btn('Show it to a grown-up','kid.stPick',id,{full:true,ic:'camera'})+btn('Take it out','kid.picDel',id,{full:true,kind:'ghost',ic:'trash'})+'</div>');
});
L.act('kid.picDel',function(c,id){var k=ens();k.pictures=k.pictures.filter(function(q){return q.id!==id;});L.closeSheet('k');toast('Taken out','trash');});

/* ===================================================== MY LIST (wants and needs) == */
var BANK_N=[['Sleep','moon'],['A hug','heart'],['Something to eat','leaf'],['Water','cloud'],['Quiet time','bell'],['My medicine','pill'],['Help','hand'],['Fresh air','sun']];
var BANK_W=[['A drawing day','brush'],['Time at the park','footprint'],['A friend over','users'],['A new book','book'],['A movie night','tv'],['Music','mic'],['A game','dice'],['A pet','pawn']];
def('k.list','My list',function(){
 var k=ens(),tab=tabOf('list','needs'),items=k.wants[tab],bank=tab==='needs'?BANK_N:BANK_W,a=age();
 var seg='<div class="kx-grid kx-g2">'+btn('Things I need','kid.tab','needs',{arg2:'list',kind:tab==='needs'?'pri':'tonal'})+btn('Things I want','kid.tab','wants',{arg2:'list',kind:tab==='wants'?'pri':'tonal'})+'</div>';
 var list=items.length?'<div class="kx-col">'+items.map(function(x){return '<div class="kx-rowb plain"><span class="ric">'+I(x.ic||'star',24,1.9)+'</span><span class="rt"><b>'+E(x.text)+'</b></span><button type="button" class="cbtn" data-act="kid.wantDel" data-arg="'+x.id+'" data-arg2="'+tab+'" aria-label="Take off: '+A(x.text)+'">'+I('x',22,2.2)+'</button></div>';}).join('')+'</div>':
  card('<div class="kx-col" style="align-items:center;text-align:center;padding:6px">'+K.spot('leaf',72)+h2('Nothing here yet')+p('Tap a picture to start your list.')+'</div>','flat');
 var picks='<h2 class="kx-h">Pick a picture</h2><div class="kx-grid kx-g4">'+bank.map(function(b){return '<button type="button" class="kx-tile" style="padding:10px 4px" data-act="kid.wantAdd" data-arg="'+A(b[0])+'" data-arg2="'+tab+'|'+b[1]+'" aria-label="Add: '+A(b[0])+'"><span class="tic" style="width:44px;height:44px">'+I(b[1],26,1.8)+'</span><span style="font-size:13px">'+E(b[0])+'</span></button>';}).join('')+'</div>';
 var typing=a>=6?'<label class="kx-cap" for="kx-want">Or write your own</label><div class="kx-row" style="flex-wrap:nowrap"><input id="kx-want" class="kx-in" data-bind="kid.draft.want" maxlength="60" autocomplete="off" value="'+A(k.draft.want)+'">'+btn('Add','kid.wantTyped',tab,{ic:'plus'})+'</div>':'';
 return scr('My list',seg+list+picks+typing,{say:'My list. Things I need. Things I want.'});
});
L.act('kid.wantAdd',function(c,t){var p_=String(c.arg2).split('|'),k=ens();k.wants[p_[0]].push({id:uid('w'),text:t,ic:p_[1]});});
L.act('kid.wantTyped',function(c,tab){var k=ens(),t=String(k.draft.want||'').trim();if(!t)return;k.wants[tab].push({id:uid('w'),text:t.slice(0,60),ic:'star'});k.draft.want='';});
L.act('kid.wantDel',function(c,id){var k=ens(),tab=c.arg2;k.wants[tab]=k.wants[tab].filter(function(x){return x.id!==id;});});

/* ============================================================== FEELINGS CORNER == */
function skySvg(kind,sz){
 var cl='<path d="M30 78a16 16 0 010-32 22 22 0 0142-6 18 18 0 0114 38z" fill="var(--surface3)" stroke="var(--ink2)" stroke-width="3"/>',sun='<circle cx="48" cy="46" r="18" fill="var(--dpMorning)" stroke="var(--ink2)" stroke-width="3"/><g stroke="var(--dpMorning)" stroke-width="5" stroke-linecap="round"><path d="M48 14v8M48 70v8M16 46h8M72 46h8M25 23l6 6M65 63l6 6M71 23l-6 6M31 63l-6 6"/></g>';
 var b={sunny:sun,partly:sun.replace(/cx="48" cy="46"/,'cx="38" cy="38"')+'<g transform="translate(14 8)">'+cl+'</g>',cloudy:cl,rainy:cl+'<g stroke="var(--info)" stroke-width="4" stroke-linecap="round"><path d="M30 86l-4 10M48 86l-4 10M66 86l-4 10"/></g>',stormy:'<g fill="var(--ink2)">'+cl.replace('var(--surface3)','var(--outline)')+'</g><path d="M52 66l-12 18h12l-6 14 20-22H54l8-10z" fill="var(--dpMorning)" stroke="var(--ink2)" stroke-width="2"/>',rainbow:'<g fill="none" stroke-width="6" stroke-linecap="round"><path d="M14 80a34 34 0 0168 0" stroke="#c8473f"/><path d="M22 80a26 26 0 0152 0" stroke="#e6c13a"/><path d="M30 80a18 18 0 0136 0" stroke="#3a78c4"/></g>'}[kind];
 return '<svg viewBox="0 0 96 100" width="'+sz+'" height="'+sz+'" aria-hidden="true" focusable="false">'+b+'</svg>';}
var SKIES=[['sunny','Sunny'],['partly','Partly cloudy'],['cloudy','Cloudy'],['rainy','Rainy'],['stormy','Stormy'],['rainbow','Rainbow']];
def('k.feel','Feelings',function(){
 var g=gl();
 var rows=rowb({ic:'cloud',title:'Feelings weather',sub:'How is it in here today?',act:'kid.open',arg:'k.weather'})+rowb({ic:'mail',title:'Worry box',sub:'Keep it here, or show a grown-up',act:'kid.open',arg:'k.worry'})+rowb({ic:'shield',title:'My helpers',sub:'People who help',act:'kid.open',arg:'k.helpers'})+rowb({ic:'hand',title:'Symbols',sub:'Tap to say it',act:'kid.open',arg:'k.symbols'});
 var tell='<h2 class="kx-h">Tell a grown-up</h2><div class="kx-col">'+g.map(function(x){return '<button type="button" class="kx-per" data-act="kid.call" data-arg="'+x.id+'" aria-label="Call '+A(lab(x.id))+'">'+face(x.id,52)+'<span class="nm">'+E(lab(x.id))+'</span>'+I('video',22,2)+'</button>';}).join('')+'</div>';
 return scr('Feelings',rows+tell,{say:'When you need someone.'});
});
def('k.weather','Feelings weather',function(){
 var f=ens().feelings;
 return scr('Feelings weather',h2('How is it in here today?')+'<div class="kx-grid kx-g3" role="radiogroup" aria-label="Sky">'+SKIES.map(function(s){var on=f.sky===s[0];return '<button type="button" class="kx-tile kx-sky'+(on?' sel':'')+'" role="radio" aria-checked="'+on+'" data-act="kid.sky" data-arg="'+s[0]+'" aria-label="'+s[1]+'">'+skySvg(s[0],64)+'<span style="font-size:14px">'+s[1]+'</span></button>';}).join('')+'</div>'+
  (f.sky?card('<p class="kx-p">Today the sky in here is <b>'+E(SKIES.filter(function(s){return s[0]===f.sky;})[0][1].toLowerCase())+'</b>.</p>'+cap('Only today is kept. Tomorrow it starts fresh. Nobody else sees this.')+btn('Clear it','kid.sky','',{kind:'ghost',ic:'refresh'}),'flat'):cap('Only today is kept. Nobody else sees this.')),{say:'How is it in here today?'});
});
L.act('kid.sky',function(c,s){ens().feelings={day:dayKey(),sky:s||null};});

/* ---- worry box ---- */
def('k.worry','Worry box',function(){
 var k=ens(),ws=k.worries;
 var form='<label class="kx-cap" for="kx-worry">Write it down, then put it in the box</label><textarea id="kx-worry" class="kx-in" data-bind="kid.draft.worry" maxlength="300" placeholder="">'+E(k.draft.worry||'')+'</textarea>'+btn('Put it in the box','kid.worryAdd',null,{full:true,ic:'mail'});
 var list=ws.length?ws.map(function(w){var sh=k.shared.worries.filter(function(x){return x.id===w.id;})[0],seen=sh&&sh.seenAt;
  return card('<p class="kx-p">'+E(w.text)+'</p>'+(w.state==='shown'?'<span class="kx-cap">'+I('eye',14,2)+' Shown to '+E(sh?sh.to.map(lab).join(' and '):'a grown-up')+(seen?'. They looked.':'. Waiting for them to look.')+'</span>':'')+
   '<div class="kx-row">'+(w.state==='shown'?'':btn('Show my grown-up','kid.worryShow',w.id,{kind:'tonal',ic:'hand'}))+btn('Float away','kid.worryFloat',w.id,{kind:'ghost',ic:'cloud'})+'</div>');}).join(''):card(cap('The box is empty. That is okay.'),'flat');
 return scr('Worry box',form+list+cap('Only you can see what is in the box, unless you choose to show a grown-up.'),{say:'The worry box.'});
});
L.act('kid.worryAdd',function(){var k=ens(),t=String(k.draft.worry||'').trim();if(!t)return;k.worries.unshift({id:uid('wr'),text:t,state:'kept',t:L.t()});k.draft.worry='';toast('Kept safe in the box','mail');});
L.act('kid.worryShow',function(c,id){
 L.sheet('k',function(){var g=gl();return '<div class="kx-col"><h2 class="kx-h">Who do you want to show?</h2>'+g.map(function(x){return '<button type="button" class="kx-per" data-act="kid.worryTo" data-arg="'+A(id)+'" data-arg2="'+x.id+'">'+face(x.id,52)+'<span class="nm">'+E(lab(x.id))+'</span></button>';}).join('')+(g.length>1?btn('Both of them','kid.worryTo',id,{full:true,kind:'tonal',arg2:'both'}):'')+'</div>';});
});
L.act('kid.worryTo',function(c,id){var k=ens(),w=k.worries.filter(function(x){return x.id===id;})[0];if(!w)return;var to=c.arg2==='both'?gl().map(function(x){return x.id;}):[c.arg2];
 w.state='shown';w.shownAt=L.t();k.shared.worries=k.shared.worries.filter(function(x){return x.id!==id;});k.shared.worries.push({id:id,text:w.text,to:to,t:L.t(),seenAt:null});
 L.emit('kid:worryShown',{id:id,to:to});L.closeSheet('k');toast('Shown. They will look when they can.','hand');});
L.act('kid.worryFloat',function(c,id){
 var k=ens(),sh=k.shared.worries.filter(function(x){return x.id===id;})[0];
 if(sh&&sh.seenAt){L.sheet('k','<div class="kx-col"><h2 class="kx-h">Float it away?</h2>'+p(sh.to.map(lab).join(' and ')+' already looked at this one. Floating it away takes it out of your box and out of their phone. It cannot make them forget what they saw.')+btn('Float it away','kid.worryGone',id,{full:true,ic:'cloud'})+btn('Keep it','sheet.close',null,{full:true,kind:'tonal'})+'</div>');return;}
 L.run('k','kid.worryGone',id);
});
L.act('kid.worryGone',function(c,id){var k=ens();k.worries=k.worries.filter(function(x){return x.id!==id;});k.shared.worries=k.shared.worries.filter(function(x){return x.id!==id;});L.closeSheet('k');toast('It floated away','cloud');});
/* ---- helpers ---- */
def('k.helpers','My helpers',function(){
 var hs=P().helpers||[],g=gl();
 var gh='<h2 class="kx-h">My grown-ups</h2>'+g.map(function(x){return perRow(x.id,lab(x.id),true,true,x.id==='dad'?'accent':undefined);}).join('');
 var more=hs.length?'<h2 class="kx-h">People who help</h2>'+hs.map(function(h){return '<div class="kx-rowb plain"><span class="ric">'+I('shield',24,1.9)+'</span><span class="rt"><b>'+E(h.name)+'</b>'+(h.what?'<small>'+E(h.what)+'</small>':'')+'</span></div>';}).join(''):card(cap('Your grown-ups can add more people who help.'),'flat');
 return scr('My helpers',gh+more,{say:'People who help you.'});
});
/* ---- symbols board: nothing she says is kept ---- */
var SYM=[['I','user'],['want','hand'],['more','plus'],['stop','stop'],['help','shield'],['yes','check'],['no','x'],['go','arrowR'],['eat','leaf'],['drink','cloud'],['play','dice'],['like','heart'],['hurt','warn'],['tired','moon'],['happy','smile'],['again','refresh']];
var symStrip=[];
def('k.symbols','Symbols',function(){
 return scr('Symbols','<div class="kx-strip" aria-live="polite" aria-label="What I am saying">'+symStrip.map(function(w){return '<span>'+E(w)+'</span>';}).join('')+'</div>'+
  '<div class="kx-row" style="flex-wrap:nowrap">'+btn('Say it','kid.symSay',null,{ic:'volume'})+btn('Clear','kid.symClear',null,{kind:'tonal',ic:'refresh'})+'</div>'+
  '<div class="kx-grid kx-g4">'+SYM.concat((P().symbols||[]).map(function(q){return [q.label||q.word,'star',q.word||q.label];})).map(function(s){return '<button type="button" class="kx-tile kx-sym" style="padding:8px 4px" data-act="kid.sym" data-arg="'+A(s[2]||s[0])+'" aria-label="'+s[0]+'"><span class="tic" style="width:44px;height:44px">'+I(s[1],26,1.9)+'</span><span style="font-size:15px">'+s[0]+'</span></button>';}).join('')+'</div>'+cap('Nothing you say here is saved.'));
});
L.act('kid.sym',function(c,w){symStrip.push(w);if(symStrip.length>10)symStrip.shift();say(w);});
L.act('kid.symSay',function(){say(symStrip.join(' '));});
L.act('kid.symClear',function(){symStrip=[];});

/* =============================================================== JOURNAL (private) == */
var jOpen=false,jCode='',jMode='enter',jFirst='';
L.afterRender.push(function(){var cu=L.current('k');if(!cu||cu.id!=='k.journal'){if(jMode==='enter')jOpen=false;}if(!cu||cu.id!=='k.symbols')symStrip=[];});
def('k.journal','Journal',function(){
 var k=ens(),J=k.journal,locked=J.lock.on&&!jOpen;
 if(locked)return scr('Journal',pad_('Enter your code','This journal is locked.'),{});
 var form='<label class="kx-cap" for="kx-j">Write something. Only you can read it.</label><textarea id="kx-j" class="kx-in" style="min-height:140px" data-bind="kid.draft.journal" maxlength="2000">'+E(k.draft.journal||'')+'</textarea>'+btn('Save this page','kid.jSave',null,{full:true,ic:'check'});
 var list=J.entries.map(function(e){var d=tp(e.t);return card('<span class="kx-cap">'+E(DAYS[d.dow]+', '+MONS[d.m-1]+' '+d.d)+'</span><p class="kx-p" style="white-space:pre-wrap">'+E(e.text)+'</p><div class="kx-row">'+btn('Take this page out','kid.jDel',e.id,{kind:'ghost',ic:'trash'})+'</div>');}).join('');
 var lockRow=rowb({ic:'lock',title:J.lock.on?'Locked with my code':'Add a lock',sub:J.lock.on?'Tap to take the lock off':'Only if I want one',act:J.lock.on?'kid.jUnlockOff':'kid.jLockOn'});
 return scr('Journal',banner('No one else can open this. Not Mom, not Dad, not the app.','lock','soft')+form+(list||cap('Your pages will be here.'))+lockRow,{});
});
function pad_(title,sub){
 var dots='<div class="kx-dots" role="img" aria-label="'+jCode.length+' of 4 entered">'+[0,1,2,3].map(function(i){return '<i class="'+(i<jCode.length?'f':'')+'"></i>';}).join('')+'</div>';
 var keys=[1,2,3,4,5,6,7,8,9,'',0,'back'].map(function(n){return n===''?'<span></span>':n==='back'?'<button type="button" data-act="kid.jKey" data-arg="back" aria-label="Delete">'+I('backspace',26,2)+'</button>':'<button type="button" data-act="kid.jKey" data-arg="'+n+'">'+n+'</button>';}).join('');
 return '<div class="kx-col" style="align-items:center;text-align:center">'+K.spot('lock',72)+h2(title)+cap(sub)+dots+'<div class="kx-pad">'+keys+'</div></div>';}
L.act('kid.jKey',function(c,n){
 var J=ens().journal;if(n==='back'){jCode=jCode.slice(0,-1);return;}if(jCode.length<4)jCode+=n;if(jCode.length<4)return;
 if(jMode==='set1'){jFirst=jCode;jCode='';jMode='set2';return;}
 if(jMode==='set2'){if(jCode===jFirst){J.lock={on:true,code:jCode};jOpen=true;L.closeSheet('k');toast('Locked','lock');}else toast('Let us try that again','info');jCode='';jMode='enter';jFirst='';return;}
 if(jCode===J.lock.code){jOpen=true;}jCode='';
});
L.act('kid.jLockOn',function(){jMode='set1';jCode='';jFirst='';L.sheet('k',function(){return pad_(jMode==='set1'?'Pick a code':'Pick it again','Four numbers only you know.');});});
L.act('kid.jUnlockOff',function(){var J=ens().journal;J.lock={on:false,code:''};jOpen=false;toast('Lock taken off','lock');});
L.act('kid.jSave',function(){var k=ens(),t=String(k.draft.journal||'').trim();if(!t)return;k.journal.entries.unshift({id:uid('j'),t:L.t(),text:t});k.draft.journal='';});
L.act('kid.jDel',function(c,id){L.sheet('k','<div class="kx-col"><h2 class="kx-h">Take this page out?</h2>'+p('It goes for good. No one can bring it back.')+btn('Take it out','kid.jDelOk',id,{full:true,ic:'trash'})+btn('Keep it','sheet.close',null,{full:true,kind:'tonal'})+'</div>');});
L.act('kid.jDelOk',function(c,id){var J=ens().journal;J.entries=J.entries.filter(function(e){return e.id!==id;});L.closeSheet('k');});

/* =========================================================== MEMORY BOX / CAPSULE / GROWTH == */
var MEM_IC=['heart','sun','leaf','star','book','smile','moon','home'];
def('k.memory','Memory box',function(){
 var k=ens(),tab=tabOf('mem','mine'),gm=(P().firstTimes||[]);
 var seg='<div class="kx-grid kx-g2">'+btn('Mine','kid.tab','mine',{arg2:'mem',kind:tab==='mine'?'pri':'tonal'})+btn('From a grown-up','kid.tab','from',{arg2:'mem',kind:tab==='from'?'pri':'tonal'})+'</div>';
 var body='';
 if(tab==='mine'){
  body+=k.memories.length?'<div class="kx-col">'+k.memories.map(function(m){return '<div class="kx-rowb plain"><span class="ric">'+I(m.ic||'heart',24,1.9)+'</span><span class="rt"><b>'+E(m.text)+'</b></span><button type="button" class="cbtn" data-act="kid.memDel" data-arg="'+m.id+'" aria-label="Take out: '+A(m.text)+'">'+I('x',22,2.2)+'</button></div>';}).join('')+'</div>':card('<div class="kx-col" style="align-items:center;text-align:center">'+K.spot('leaf',72)+h2('Nothing here yet')+p('Keep something you want to remember.')+'</div>','flat');
  body+='<label class="kx-cap" for="kx-mem">Something I want to remember</label><input id="kx-mem" class="kx-in" data-bind="kid.draft.memory" maxlength="80" autocomplete="off" value="'+A(k.draft.memory)+'"><div class="kx-row" style="justify-content:center">'+MEM_IC.map(function(ic){return '<button type="button" class="kx-opt" data-act="kid.memAdd" data-arg="'+ic+'" aria-label="Keep with a '+ic+'">'+I(ic,24,1.9)+'</button>';}).join('')+'</div>'+cap('Pick a picture to keep it.');
 }else{
  body+=gm.length?'<div class="kx-col">'+gm.map(function(m){return '<div class="kx-rowb plain"><span class="ric">'+I(m.ic||'heart',24,1.9)+'</span><span class="rt"><b>'+E(m.text)+'</b><small>From '+E(lab(m.from||gl()[0].id))+'</small></span></div>';}).join('')+'</div>':card('<p class="kx-p">When a grown-up keeps something for you, it will be here.</p>','flat');
 }
 return scr('Memory box',seg+body,{say:'Your memory box.'});
});
L.act('kid.memAdd',function(c,ic){var k=ens(),t=String(k.draft.memory||'').trim();if(!t)return;k.memories.unshift({id:uid('m'),text:t,ic:ic,t:L.t()});k.draft.memory='';});
L.act('kid.memDel',function(c,id){var k=ens();k.memories=k.memories.filter(function(m){return m.id!==id;});});
function ymd(y,m,d){var x=new Date(Date.UTC(y,m-1,d));return x.getUTCFullYear()+'-'+pad(x.getUTCMonth()+1)+'-'+pad(x.getUTCDate());}
function dateNice(s){var q=String(s).split('-');return MON[+q[1]-1]+' '+(+q[2])+', '+q[0];}
def('k.capsule','Time capsule',function(){
 var k=ens(),today=dayKey(),all=(P().capsule||[]).map(function(x,i){return {id:'g'+i,from:null,text:x.text,openOn:x.openOn,mine:false};}).concat(k.capsules.map(function(x){return {id:x.id,text:x.text,openOn:x.openOn,mine:true};}));
 var list=all.length?all.map(function(x){var open=today>=x.openOn;return '<div class="kx-rowb plain"><span class="ric">'+I(open?'mail':'hourglass',24,1.9)+'</span><span class="rt"><b>'+(open?E(x.text):'Sealed')+'</b><small>'+(x.mine?'From me':'From a grown-up')+'. '+(open?'Opened':'Opens on '+E(dateNice(x.openOn)))+'</small></span></div>';}).join(''):card(cap('Nothing is sealed yet.'),'flat');
 var pp=tp(),b=bday(),choices=[['Next month',ymd(pp.y,pp.m+1,pp.d)],['In a year',ymd(pp.y+1,pp.m,pp.d)]];
 if(b){var yy=ymd(pp.y,b.m,b.d)<=today?pp.y+1:pp.y;choices.unshift(['My next birthday',ymd(yy,b.m,b.d)]);}
 var add='<h2 class="kx-h">Seal a note for later</h2><input id="kx-cap" class="kx-in" aria-label="A note to my future self" data-bind="kid.draft.cap" maxlength="120" autocomplete="off" placeholder="" value="'+A(k.draft.cap)+'"><div class="kx-row">'+choices.map(function(ch){return '<button type="button" class="kx-opt" data-act="kid.capAdd" data-arg="'+ch[1]+'">Open on '+E(ch[0].toLowerCase())+'</button>';}).join('')+'</div>';
 return scr('Time capsule',list+add,{say:'The time capsule.'});
});
L.act('kid.capAdd',function(c,on){var k=ens(),t=String(k.draft.cap||'').trim();if(!t)return;k.capsules.push({id:uid('c'),text:t,openOn:on});k.draft.cap='';toast('Sealed','hourglass');});
def('k.growth','Growing marks',function(){
 var k=ens(),ms=k.growth.slice().sort(function(a,b){return a.t-b.t;});
 var H=300,svg='<svg viewBox="0 0 180 '+H+'" width="100%" style="display:block" aria-label="The door with your pencil marks"><rect x="30" y="4" width="120" height="'+(H-8)+'" rx="6" fill="var(--surface)" stroke="var(--edge)" stroke-width="3"/>'+
  ms.map(function(m,i){var y=Math.round(m.y*(H-30))+10,last=i===ms.length-1;return '<g><line x1="42" y1="'+y+'" x2="100" y2="'+y+'" stroke="'+(last?'var(--ink)':'var(--ink2)')+'" stroke-width="3" stroke-linecap="round"/><text x="106" y="'+(y+4)+'" font-size="12" fill="var(--ink2)" font-family="var(--font-body)">'+E(m.m)+'</text></g>';}).join('')+'</svg>';
 return scr('Growing marks',cap('Stand against the door, then tap where the top of your head is. A pencil line and the month.')+'<button type="button" class="kx-door" data-act="kid.mark" aria-label="The door. Tap to add a pencil mark.">'+svg+'</button>'+((P().marks||[]).length?'<h2 class="kx-h">From a grown-up</h2>'+(P().marks||[]).map(function(m){return rowb({plain:true,ic:'leaf',title:m.label||'A mark',sub:m.date?dateNice(m.date):''});}).join(''):'')+(ms.length?btn('Rub out the last mark','kid.markUndo',null,{full:true,kind:'ghost',ic:'undo'}):''),{say:'Growing marks on the door.'});
});
L.act('kid.mark',function(c,a,el,ev){
 var k=ens();if(!el||!ev)return;var r=el.getBoundingClientRect(),y=(ev.clientY-r.top)/r.height;y=Math.max(.04,Math.min(.96,y));
 var pp=tp();k.growth.push({id:uid('g'),t:L.t(),m:MONS[pp.m-1]+' '+pp.y,y:y});toast('Marked','check');
});
L.act('kid.markUndo',function(){var k=ens();k.growth.sort(function(a,b){return a.t-b.t;});k.growth.pop();});

/* ============================================================ STORIES / STORYTELLER == */
var STORIES=[
 {id:'moon',t:'The sleepy moon',scene:'night',pages:[['night','The moon was very tired. It had been up all night.'],['hills','It lay down on the hills and pulled a cloud up to its chin.'],['sea','The sea hummed a slow song, and the moon closed one eye.'],['night','Then both eyes. Goodnight, moon.']]},
 {id:'fox',t:'The little fox',scene:'hills',pages:[['hills','A little fox lived at the edge of the hill.'],['garden','One morning she found a garden with a gate left open.'],['garden','She did not go in. She sat and watched the bees.'],['hills','Then she went home, and told the story to the stars.']]},
 {id:'boat',t:'A boat for two',scene:'sea',pages:[['sea','Two friends built a boat out of paper.'],['sea','It was small. It was wobbly. It floated.'],['paper','They sailed it across the bath, and then across the sea of the living room rug.'],['sea','It was the best boat there ever was.']]},
 {id:'rain',t:'The garden in the rain',scene:'garden',pages:[['garden','It rained all day. The garden did not mind.'],['garden','The snail came out for a walk.'],['day','The sun came back with a rainbow in its pocket.'],['garden','Everything smelled green.']]}
];
var TELLER=[
 {id:'lantern',t:'The lantern keeper',scene:'night',pages:[['night','At the top of the hill there was a lantern, and in the lantern there was a small flame. Every evening, a girl named Mira climbed up to look after it.'],['hills','The hill was steep, but Mira knew every stone. She counted her steps the way other people count stars.'],['night','One night the wind came, and the flame leaned over. Mira cupped her hands around it and waited.'],['sea','Far below, a fishing boat turned toward the shore, following the light. Mira never saw it. She only felt the wind change its mind.'],['day','In the morning the flame was still there. So was Mira. That was the whole job, and it was enough.']]},
 {id:'map',t:'The map with one road',scene:'paper',pages:[['paper','Jonah found a map in a library book. It had only one road on it, and the road led off the edge of the page.'],['hills','He followed it as far as the hills behind his house. After that, he had to draw the rest himself.'],['garden','He drew a river, then a bridge. He drew a town with a very long name that he could not pronounce.'],['paper','When he got home, the map had grown. It had a second road now, and it started at his door.']]}
];
def('k.stories','Stories',function(){
 var all=STORIES;
 return scr('Stories','<div class="kx-grid kx-g2">'+all.map(function(s){return '<button type="button" class="kx-tile" style="padding:8px" data-act="kid.story" data-arg="'+s.id+'" aria-label="'+A(s.t)+'"><span style="display:block;width:100%;border-radius:18px;overflow:hidden">'+K.scene(s.scene,200,100)+'</span><span style="padding:2px 4px">'+E(s.t)+'</span></button>';}).join('')+'</div>',{say:'Pick a story.'});
});
def('k.storyteller','Storyteller',function(){
 return scr('Storyteller',cap('Longer stories, read to you or read by you.')+TELLER.map(function(s){return rowb({ic:'book',title:s.t,sub:'Tap to listen or read',act:'kid.story',arg:s.id});}).join('')+'<h2 class="kx-h">Picture stories</h2>'+STORIES.map(function(s){return rowb({ic:'image',title:s.t,act:'kid.story',arg:s.id});}).join(''),{say:'Storyteller.'});
});
L.act('kid.story',function(c,id){ens().story[id]=0;go('k.story',{id:id});});
def('k.story',' ',function(c){
 var id=c.params.id,s=STORIES.concat(TELLER).filter(function(x){return x.id===id;})[0],k=ens();if(!s)return scr('Story',cap('That story is resting.'));
 var pg=Math.max(0,Math.min(s.pages.length-1,k.story[id]||0)),pgd=s.pages[pg],last=pg===s.pages.length-1,teller=!!TELLER.filter(function(x){return x.id===id;})[0];
 var out='<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene(pgd[0],300,170)+'</div>'+card('<p class="kx-p" style="font-size:'+(teller?19:22)+'px;line-height:1.55">'+E(pgd[1])+'</p>')+
  '<div class="kx-pager" role="img" aria-label="Page '+(pg+1)+' of '+s.pages.length+'">'+s.pages.map(function(_,i){return '<i class="'+(i<=pg?'f':'')+'"></i>';}).join('')+'</div>'+
  '<div class="kx-row" style="flex-wrap:nowrap;justify-content:center">'+(pg>0?btn('','kid.storyPg',id,{kind:'tonal',ic:'arrowL',arg2:'-1',label:'Back a page'}):'')+btn('Read to me','kid.say',pgd[1],{kind:'tonal',ic:'volume'})+(last?btn('The end','kid.back',null,{ic:'check'}):btn('Next','kid.storyPg',id,{ic:'arrowR',arg2:'1'}))+'</div>';
 return top(s.t,{say:pgd[1]})+page(out);
});
L.act('kid.storyPg',function(c,id){var k=ens();k.story[id]=(k.story[id]||0)+(+c.arg2);if(readAloud()){}});
/* 'something is changing': a picture story a guardian released; never a surprise */
function changePages(){
 var cn=P().changeNote||{},g=gl(),pg=[];
 if(cn.text)pg.push(['hills',cn.text]);
 if(oneHome())pg.push(['day','The grown-ups you love are still your grown-ups.']);
 else{pg.push(['hills','Some nights, you sleep at '+houseName(g[0].id)+'.']);pg.push(['twohouses','Other nights, you sleep at '+houseName(g[1].id)+'.']);}
 pg.push(['day','You always have your own things, and you can always call.']);pg.push(['hills','You can ask a question any time.']);
 return pg;}
def('k.change',' ',function(c){
 var k=ens(),cs=P().changeNote;if(!cs)return scr('A story',cap('Nothing here right now.'));
 var pgs=changePages(),n=Math.min(pgs.length-1,k.story.change||0),pg=pgs[n],from=lab(gl()[0].id),last=n===pgs.length-1;
 var out='<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene(pg[0],300,170)+'</div>'+card('<p class="kx-p" style="font-size:22px">'+E(pg[1])+'</p>')+'<div class="kx-pager">'+pgs.map(function(_,i){return '<i class="'+(i<=n?'f':'')+'"></i>';}).join('')+'</div>'+
  (last?btn('Okay','kid.changeDone',null,{full:true,ic:'check'}):btn('Next','kid.storyPg',null,{full:true,ic:'arrowR',arg2:'1'}).replace('data-act="kid.storyPg"','data-act="kid.changePg"'))+'<div class="kx-grid kx-g2">'+btn('Not now','kid.changeDone',null,{kind:'ghost'})+btn('Ask','kid.changeAsk',null,{kind:'tonal',ic:'chat'})+'</div>';
 return top('From '+from,{eyebrow:'A story for you',say:pg[1]})+page(out);
});
L.act('kid.changePg',function(){var k=ens();k.story.change=(k.story.change||0)+1;});
L.act('kid.changeDone',function(){var k=ens(),cn=P().changeNote;if(cn)k.seen['chg'+cn.t]=true;k.story.change=0;L.back('k');});
L.act('kid.changeAsk',function(){var k=ens(),cn=P().changeNote;if(cn)k.seen['chg'+cn.t]=true;k.shared.asks.push({id:uid('ask'),about:'change',t:L.t()});L.emit('kid:ask',{about:'change'});toast('A grown-up will talk with you about it.','chat');});

/* ================================================================ BIRTHDAY / WEEKS == */
def('k.birthday','My birthday',function(){
 var b=bday();if(!b)return scr('My birthday',cap('Nothing here right now.'));
 var n=sleepsTo(b.m,b.d),a=age();
 var big=n===0?'<span class="kx-big" aria-hidden="true">'+I('sparkle',60,1.8)+'</span><b class="kx-h">Today is your birthday.</b>':'<span class="kx-big">'+n+'</span><b class="kx-h">'+(n===1?'sleep':'sleeps')+' until your birthday</b>';
 return scr('My birthday',card('<div class="kx-col" style="align-items:center;text-align:center;padding:10px 4px">'+big+'</div>','tint')+card(p('There is nothing to do. It will just come.'),'flat')+rowb({plain:true,ic:'calendar',title:MON[b.m-1]+' '+b.d,sub:'You will be '+(a+1)}),{say:n===0?'Today is your birthday.':n+' sleeps until your birthday.'});
});
function monthGrid(y,m,o){
 o=o||{};var first=new Date(Date.UTC(y,m-1,1)).getUTCDay(),dim=new Date(Date.UTC(y,m,0)).getUTCDate(),g=gl(),pp=tp(),cells='',hd=DAYS.map(function(d){return '<span role="columnheader" aria-label="'+d+'">'+d.charAt(0)+'</span>';}).join('');
 for(var i=0;i<first;i++)cells+='<span></span>';
 for(var d=1;d<=dim;d++){var who=nightOf(y,m,d),tone=oneHome()?'':(who===g[0].id?'a':'b'),isT=(y===pp.y&&m===pp.m&&d===pp.d),evs=o.events?o.events(y,m,d):0;
  var cell=K.dayCell(d,{today:isT,sel:o.sel===d,tone:tone,dot:!!evs,label:DAYS[new Date(Date.UTC(y,m-1,d)).getUTCDay()]+' '+d+(isT?', today':'')+(oneHome()?', home':', '+houseName(who))+(evs?', something on':'')});
  cells+=o.act?L.withAct(cell,o.act,d):cell;}
 var leg=oneHome()?'':'<div class="cal-l"><span><i class="a"></i>'+E(houseName(g[0].id))+'</span><span><i class="b"></i>'+E(houseName(g[1].id))+'</span></div>';
 return '<div class="cal" role="group" aria-label="'+MON[m-1]+' '+y+'"><div class="cal-h"><b>'+MON[m-1]+' '+y+'</b></div><div class="cal-w" role="row">'+hd+'</div><div class="cal-g" role="grid">'+cells+'</div>'+leg+'</div>';}
def('k.weeks','My weeks',function(){
 var pp=tp();
 var head=card('<p class="kx-p"><b>'+E(oneHome()?'Every night is at home.':'Tonight you sleep at '+houseName(tonight())+'.')+'</b></p>'+(oneHome()?'':cap(nextLine().split('. ').slice(1).join('. '))),'tint');
 return scr('My weeks',head+card(monthGrid(pp.y,pp.m)),{say:oneHome()?'Every night is at home.':'Tonight you sleep at '+houseName(tonight())});
});
/* =============================================================== SHOW AND TELL == */
var stSel=null;
def('k.showtell','Show & tell',function(){
 var k=ens(),sc=['garden','park','kitchen'];
 var pics=k.pictures.map(function(x){return {id:x.id,html:'<img src="'+x.data+'" alt="" style="width:100%;border-radius:14px;display:block">',name:x.name};}).concat(sc.map(function(s){return {id:'scene:'+s,html:'<span style="display:block;border-radius:14px;overflow:hidden">'+K.scene(s,160,100)+'</span>',name:'A '+s+' picture'};}));
 var pick='<div class="kx-grid kx-g3">'+pics.map(function(x){return '<button type="button" class="kx-tile'+(stSel===x.id?' sel':'')+'" style="padding:6px" data-act="kid.stPick" data-arg="'+A(x.id)+'" aria-pressed="'+(stSel===x.id)+'" aria-label="'+A(x.name)+'">'+x.html+'</button>';}).join('')+'</div>';
 var who='';
 if(stSel){who='<h2 class="kx-h">Who do you want to show?</h2><div class="kx-grid kx-g2">'+gl().map(function(x){return '<button type="button" class="kx-per" data-act="kid.stSend" data-arg="'+x.id+'">'+face(x.id,48)+'<span class="nm">'+E(lab(x.id))+'</span>'+I('send',22,2)+'</button>';}).join('')+'</div>'+(gl().length>1?btn('Both of them','kid.stSend','both',{full:true,kind:'tonal'}):'');}
 var sent=k.shared.showTell.length?'<h2 class="kx-h">I showed</h2>'+k.shared.showTell.slice().reverse().slice(0,4).map(function(s){return rowb({plain:true,ic:'camera',title:s.name||'A picture',sub:'Shown to '+s.to.map(lab).join(' and ')});}).join(''):'';
 return scr('Show & tell',cap('Pick a picture to show a grown-up.')+pick+who+sent,{say:'Pick a picture to show.'});
});
L.act('kid.stPick',function(c,id){stSel=stSel===id?null:id;if(L.current('k').id!=='k.showtell'){L.closeSheet('k');go('k.showtell');}});
L.act('kid.stSend',function(c,to){
 var k=ens();if(!stSel)return;var ids=to==='both'?gl().map(function(x){return x.id;}):[to],pic=k.pictures.filter(function(x){return x.id===stSel;})[0];
 k.shared.showTell.push({id:uid('st'),ref:stSel,name:pic?pic.name:'A '+stSel.split(':')[1]+' picture',data:pic?pic.data:null,to:ids,t:L.t(),seenAt:null});
 L.emit('kid:showtell',{to:ids});stSel=null;toast('Sent. They will see it when they look.','camera');
});
/* ===================================================================== JOKEBOOK == */
var JOKES=[
 {min:3,max:7,q:'What says moo and has wheels?',a:'A cow-ch.'},{min:3,max:7,q:'What do you call a sleeping bull?',a:'A bulldozer.'},
 {min:4,max:8,q:'Why did the banana go to the doctor?',a:'It was not peeling well.'},{min:5,max:9,q:'What is a cat’s favourite colour?',a:'Purr-ple.'},
 {min:6,max:11,q:'Why was the math book sad?',a:'It had too many problems.'},{min:6,max:12,q:'What do you call a fake noodle?',a:'An impasta.'},
 {min:8,max:13,q:'Why did the scarecrow win a prize?',a:'He was outstanding in his field.'},{min:8,max:14,q:'What has keys but cannot open locks?',a:'A piano.'},
 {min:9,max:15,q:'I used to hate facial hair.',a:'But then it grew on me.'},{min:10,max:17,q:'Why do bees have sticky hair?',a:'Because they use honeycombs.'},
 {min:12,max:17,q:'What did the ocean say to the shore?',a:'Nothing. It just waved.'},{min:13,max:17,q:'Why can’t you trust an atom?',a:'They make up everything.'}];
def('k.jokes','Jokebook',function(){
 var a=age(),k=ens(),js=JOKES.filter(function(j){return a>=j.min&&a<=j.max;});
 return scr('Jokebook',js.map(function(j,i){var open=k.seen['joke'+i];return '<button type="button" class="kx-rowb" style="flex-direction:column;align-items:flex-start" data-act="kid.joke" data-arg="'+i+'" aria-expanded="'+!!open+'"><b>'+E(j.q)+'</b>'+(open?'<span class="kx-p" style="color:var(--pri)">'+E(j.a)+'</span>':'<small>Tap for the answer</small>')+'</button>';}).join(''),{say:'Jokes.'});
});
L.act('kid.joke',function(c,i){var k=ens();k.seen['joke'+i]=!k.seen['joke'+i];});
/* ====================================================================== MORE HUB == */
var MORE={t57:['draw','memory','feel','growth','birthday','shelf','jokes'],t812:['journal','feel','memory','capsule','growth','birthday','shelf','jokes','draw'],t1317:['play','draw','memory','capsule','shelf','jokes','privacy','ladder']};
def('k.more','More',function(){
 var b=eb(),a=age(),ids=(MORE[b]||MORE.t57).filter(function(i){if(i==='play'&&a<14)return false;if(i==='shelf'&&!shelfOn())return false;if(i==='birthday'){var bb=bday();if(!bb||a>=11)return false;}return !hidden(i);});
 ids=ids.slice(0,b==='t57'?6:7);
 return scr('More',cap(b==='t1317'?'Everything else, in one place.':'Pick something.')+'<div class="kx-grid kx-g2">'+tiles(ids,'feat')+'</div>'+tileHtml('grownup','wide',{sub:'Ask a grown-up'}).replace('data-arg="grownup"','data-arg="grownup"'),{say:'More things.'});
});
/* grown-up things: a PIN pad with shuffled digits. Wrong code just clears the dots: no error text. */
var gateIn='',gateDigits=null;
function grownGate(){gateIn='';gateDigits=shuffle([1,2,3,4,5,6,7,8,9,0]);L.sheet('k',gateSheet);}
function gateSheet(){
 var f=L.S.family;
 if(gateIn==='ok'){return '<div class="kx-col"><h2 class="kx-h">Grown-up things</h2>'+cap('Only a grown-up can change this. Her age is locked.')+'<div class="kx-row">'+[3,4,5,6,7,8,9,10,11,12,13,14,15,16,17].map(function(n){return '<button type="button" class="kx-opt'+(realAge()===n?' sel':'')+'" data-act="kid.setAge" data-arg="'+n+'">'+n+'</button>';}).join('')+'</div>'+btn('Done','sheet.close',null,{full:true,kind:'tonal'})+'</div>';}
 var dots='<div class="kx-dots" role="img" aria-label="'+gateIn.length+' of 4 entered">'+[0,1,2,3].map(function(i){return '<i class="'+(i<gateIn.length?'f':'')+'"></i>';}).join('')+'</div>';
 var d=gateDigits||[1,2,3,4,5,6,7,8,9,0],keys=d.slice(0,9).map(function(n){return '<button type="button" data-act="kid.gate" data-arg="'+n+'">'+n+'</button>';}).join('')+'<button type="button" data-act="kid.gate" data-arg="back" aria-label="Delete">'+I('backspace',26,2)+'</button><button type="button" data-act="kid.gate" data-arg="'+d[9]+'">'+d[9]+'</button><span></span>';
 return '<div class="kx-col" style="align-items:center;text-align:center">'+K.spot('lock',72)+h2('Grown-ups only')+dots+'<div class="kx-pad">'+keys+'</div></div>';
}
L.act('kid.gate',function(c,n){
 if(n==='back'){gateIn=gateIn.slice(0,-1);return;}if(gateIn.length>=4||gateIn==='ok')return;gateIn+=n;
 if(gateIn.length===4){var pin=String((L.S.family&&L.S.family.pin)||'');if(pin&&gateIn===pin)gateIn='ok';else gateIn='';}
});
L.act('kid.setAge',function(c,n){L.setAge(+n);ens();});

/* ======================================================================= TEEN == */
/* own calendar (rung 14): she adds; each event is hers, and she chooses who else sees it */
var calShare='me';
function evAt(y,m,d){return ens().cal.filter(function(e){return e.y===y&&e.m===m&&e.d===d;});}
def('k.cal','My calendar',function(){
 var k=ens(),pp=tp(),sel=tabOf('calSel',pp.d),mine=age()>=14;
 var evs=evAt(pp.y,pp.m,sel);
 var intro=mine?'':banner('You can look at the calendar now. You can add your own things from 14.','calendar','soft');
 var list=evs.length?evs.map(function(e){return '<div class="kx-rowb plain"><span class="ric">'+I('calendar',22,1.9)+'</span><span class="rt"><b>'+E(e.title)+'</b><small>'+(e.share==='me'?'Only me':'Shown to '+E(e.share==='both'?gl().map(function(x){return lab(x.id);}).join(' and '):lab(e.share)))+'</small></span>'+(mine?'<button type="button" class="cbtn" data-act="kid.calDel" data-arg="'+e.id+'" aria-label="Remove '+A(e.title)+'">'+I('trash',20,2)+'</button>':'')+'</div>';}).join(''):cap('Nothing on '+MONS[pp.m-1]+' '+sel+'.');
 return scr('My calendar',intro+card(monthGrid(pp.y,pp.m,{sel:sel,act:'kid.calSel',events:function(y,m,d){return evAt(y,m,d).length;}}))+'<h2 class="kx-h">'+E(MON[pp.m-1]+' '+sel)+'</h2>'+list+(mine?btn('Add something','kid.calAdd',null,{full:true,ic:'plus'}):''));
});
L.act('kid.calSel',function(c,d){setTab('calSel',+d);});
L.act('kid.calAdd',function(){
 ens().draft.event='';calShare='me';
 L.sheet('k',function(){var g=gl(),opts=[['me','Only me']].concat(g.map(function(x){return [x.id,lab(x.id)];}));if(g.length>1)opts.push(['both','Both']);
  return '<div class="kx-col"><h2 class="kx-h">Add to '+E(MON[tp().m-1]+' '+tabOf('calSel',tp().d))+'</h2><label class="kx-cap" for="kx-ev">What is it?</label><input id="kx-ev" class="kx-in" data-bind="kid.draft.event" maxlength="60" autocomplete="off" value="'+A(ens().draft.event)+'"><p class="kx-cap">Who else sees it?</p><div class="kx-row">'+opts.map(function(o){return '<button type="button" class="kx-opt'+(calShare===o[0]?' sel':'')+'" data-act="kid.calShare" data-arg="'+o[0]+'">'+E(o[1])+'</button>';}).join('')+'</div>'+btn('Add it','kid.calSave',null,{full:true,ic:'check'})+'</div>';});
});
L.act('kid.calShare',function(c,s){calShare=s;});
L.act('kid.calSave',function(){var k=ens(),t=String(k.draft.event||'').trim();if(!t)return;var pp=tp(),d=tabOf('calSel',pp.d),e={id:uid('ev'),y:pp.y,m:pp.m,d:d,title:t,share:calShare};k.cal.push(e);
 if(calShare!=='me')k.shared.cal.push({id:e.id,y:e.y,m:e.m,d:e.d,title:e.title,to:calShare==='both'?gl().map(function(x){return x.id;}):[calShare]});
 k.draft.event='';L.closeSheet('k');});
L.act('kid.calDel',function(c,id){var k=ens();k.cal=k.cal.filter(function(e){return e.id!==id;});k.shared.cal=k.shared.cal.filter(function(e){return e.id!==id;});});

/* privacy contract: plain words, nothing hidden */
function cellHtml(v,who){var t=v==='see'?['eye','can see this','See']:v==='ask'?['hand','only if you choose','You choose']:['eyeoff','cannot see this','No'];
 return '<div role="cell" style="padding:8px 2px;text-align:center;min-width:0" aria-label="'+A(who+' '+t[1])+'"><span style="display:inline-flex;flex-direction:column;align-items:center;gap:2px;font:700 12px var(--font-body);color:'+(v==='no'?'var(--ink2)':'var(--ink)')+'">'+I(t[0],20,2)+t[2]+'</span></div>';}
def('k.privacy','What your parents can see',function(){
 var g=gl(),cols=g.map(function(x){return lab(x.id);}),n=g.length;
 function row(t,sub,vals){return '<div role="row" style="display:grid;grid-template-columns:minmax(0,1.7fr) repeat('+n+',minmax(0,1fr));align-items:center;border-top:1px solid var(--line)"><div role="rowheader" style="padding:8px 4px 8px 0;font:700 15px var(--font-body);min-width:0">'+E(t)+(sub?'<br><span style="font-weight:400;font-size:13px;color:var(--ink2)">'+E(sub)+'</span>':'')+'</div>'+vals.map(function(v,i){return cellHtml(v,cols[i]);}).join('')+'</div>';}
 var no=function(){return g.map(function(){return 'no';});};
 var table='<div role="table" aria-label="Who can see what"><div role="row" style="display:grid;grid-template-columns:minmax(0,1.7fr) repeat('+n+',minmax(0,1fr))"><div></div>'+cols.map(function(c_){return '<div role="columnheader" style="padding:6px 2px;text-align:center;font:700 14px var(--font-body);min-width:0">'+E(c_)+'</div>';}).join('')+'</div>'+
  g.map(function(x,i){return row('Messages you send to '+lab(x.id),'',g.map(function(y,j){return i===j?'see':'no';}));}).join('')+
  row('Your free times',age()>=15?'What you publish.':'From 15, what you publish.',g.map(function(){return age()>=15?'see':'no';}))+
  row('Events you add','You choose each one.',g.map(function(){return 'ask';}))+
  row('Pictures you show','You choose each one.',g.map(function(){return 'ask';}))+
  row('Your journal','',no())+row('Where you are','We never ask your device.',no())+row('Things you hide in your archive','',no())+'</div>';
 return scr('Privacy',card('<span class="kx-cap" style="text-transform:uppercase;letter-spacing:.08em">'+I('lock',12,2.2)+' Only you</span><h2 class="kx-h">Your journal is yours. Where you are is yours.</h2>'+p('No one can open your journal: not '+cols.join(', not ')+', not us, not a court. We never ask your device where you are.'),'tint')+
  card('<h3 class="kx-h" style="font-size:19px">Who can see what</h3>'+table)+
  card('<h3 class="kx-h" style="font-size:19px">What you can see of them</h3>'+p('The same rules, the other way. You never see '+(n>1?'their messages to each other, their money, or where they are':'their money or where they are')+'. You do see when they are free to talk.'))+
  card(cap('Some things the grown-ups set up for the whole family, such as handovers, school and appointments. They can see those, and so can you. Nothing here changes without you seeing it.'),'flat'),{});
});
/* the ladder: what is hers at her age. Shown honestly, with the rungs that have not opened yet marked as such */
var LADDER=[[10,'Your list','Nobody checks it first.','list','k.list'],[13,'Your journal locks','Only you can open it.','lock','k.journal'],[14,'Your calendar','You add and edit your own things.','calendar','k.cal'],[15,'Your free times','You publish when you are free.','clock','k.free'],[16,'Your archive','You choose what to hide.','image','k.archive'],[17,'Your own copy','Take a copy of your data.','download','k.copy'],[18,'Everything','Guardianship closes. It is all yours.','key','k.handover']];
def('k.ladder','What is mine',function(){
 var a=age();
 return scr('What is mine',cap('This is what is yours at your age. The rest opens as you grow, and nothing here can be taken back.')+LADDER.map(function(r){var on=a>=r[0];
  return '<button type="button" class="kx-rowb'+(on?'':' plain')+'" data-act="'+(on?'kid.open':'noop')+'"'+(on?' data-arg="'+r[4]+'"':'')+(on?'':' aria-disabled="true"')+' style="'+(on?'':'opacity:.7')+'"><span class="ric">'+I(on?r[3]:'lock',24,1.9)+'</span><span class="rt"><b>'+E(r[1])+'</b><small>'+E(on?'Yours now. '+r[2]:'Opens at '+r[0]+'. '+r[2])+'</small></span>'+(on?I('chevR',20,2):'')+'</button>';}).join('')+
  cap('Nobody is told when you open one of these.')+(a<18?btn('Show me what happens at 18','kid.open',null,{full:true,kind:'ghost',arg2:'{"preview":true}'}).replace('data-act="kid.open"','data-act="kid.open" data-arg="k.handover"'):''),{});
});
def('k.free','Your free times',function(){
 var k=ens(),ft=k.freeTimes,a=age(),parts=[['am','Before school'],['pm','After school'],['eve','Evening']];
 if(a<15)return scr('Your free times',cap('This opens at 15.'));
 function grp(key,title){return card('<h3 class="kx-h" style="font-size:19px">'+title+'</h3><div class="kx-row">'+parts.map(function(p_){var on=ft[key][p_[0]];return '<button type="button" class="kx-opt'+(on?' sel':'')+'" aria-pressed="'+on+'" data-act="kid.free" data-arg="'+key+'" data-arg2="'+p_[0]+'">'+(on?I('check',20,2.4):'')+E(p_[1])+'</button>';}).join('')+'</div>');}
 function words(key){var f=parts.filter(function(p_){return ft[key][p_[0]];}).map(function(p_){return p_[1].toLowerCase();});return f.length?'free '+f.join(', '):'nothing shown';}
 return scr('Your free times',p('You decide when you are free.')+grp('wd','School days')+grp('we','Weekends')+card('<h3 class="kx-h" style="font-size:19px">What they see</h3><p class="kx-p">'+E(gl().map(function(x){return lab(x.id);}).join(' and '))+' see: school days '+E(words('wd'))+'. Weekends '+E(words('we'))+'.</p>'+cap('They do not see why you are busy.'),'flat')+btn('Save my times','kid.freeSave',null,{full:true}),{});
});
L.act('kid.free',function(c,key){var f=ens().freeTimes;f[key][c.arg2]=!f[key][c.arg2];});
L.act('kid.freeSave',function(){var k=ens();k.shared.freeTimes=clone(k.freeTimes);toast('Saved. You can change it any minute.','check');});
def('k.archive','Your archive',function(){
 var k=ens();if(age()<16)return scr('Your archive',cap('This opens at 16.'));
 var items=k.pictures.map(function(x){return {id:x.id,t:x.name,ic:'image'};}).concat(k.memories.map(function(x){return {id:x.id,t:x.text,ic:x.ic||'heart'};}));
 return scr('Your archive',cap('Hide what you want. Nothing is deleted, and nobody is told what you hide.')+(items.length?items.map(function(x){var h=k.hidden[x.id];return '<button type="button" class="kx-rowb" aria-pressed="'+!!h+'" data-act="kid.hide" data-arg="'+x.id+'"><span class="ric">'+I(h?'eyeoff':x.ic,22,1.9)+'</span><span class="rt"><b>'+E(x.t)+'</b><small>'+(h?'Hidden. Only you can see it.':'Shown in the archive')+'</small></span></button>';}).join(''):card(cap('Pictures and memories you keep will be here.'),'flat')));
});
L.act('kid.hide',function(c,id){var h=ens().hidden;if(h[id])delete h[id];else h[id]=true;});
function buildCopy(){
 var k=ens(),c=child();
 return {about:'A copy of what is yours, made on this device. Nobody was told.',madeAt:new Date(L.t()).toISOString(),child:{name:c.name,age:realAge(),nicknames:c.nicknames||{}},
  journal:k.journal.entries,list:k.wants,memories:k.memories,capsules:k.capsules,growthMarks:k.growth,calendar:k.cal,freeTimes:k.freeTimes,hidden:k.hidden,pictures:k.pictures.map(function(p_){return {name:p_.name,kind:p_.kind,data:p_.data};}),
  notIncluded:'Messages between your parents, and anything they wrote about each other. Those are not yours.'};}
L.act('kid.takeCopy',function(){
 var data=buildCopy(),json=JSON.stringify(data,null,2);
 try{var blob=new Blob([json],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=(cname()||'my').toLowerCase().replace(/\W+/g,'-')+'-my-copy.json';document.body.appendChild(a);a.click();setTimeout(function(){document.body.removeChild(a);URL.revokeObjectURL(url);},500);}catch(e){}
 ens().seen.copyMade=true;L.__kidLastCopy=data;toast('Saved to this device. Nobody is told.','download');
});
def('k.copy','Your own copy',function(){
 var k=ens();if(age()<17)return scr('Your own copy',cap('This opens at 17.'));
 return scr('Your own copy',p('You can take a copy of your data. No one has to say yes.')+card('<h3 class="kx-h" style="font-size:19px">What is in it</h3>'+K.kv([['Your journal',k.journal.entries.length+' pages, yours only'],['Pictures you kept',String(k.pictures.length)],['Your list',String(k.wants.needs.length+k.wants.wants.length)],['Memories',String(k.memories.length)],['Your calendar',String(k.cal.length)],['Growing marks',String(k.growth.length)]],{ruled:true}))+
  card('<h3 class="kx-h" style="font-size:19px">What is not</h3>'+cap('Messages between your parents, and anything they wrote about each other. Those are not yours.'),'flat')+btn('Make my copy','kid.takeCopy',null,{full:true,ic:'download'})+cap('Nobody is told you made it.'));
});
def('k.handover','Your own space',function(c){
 var k=ens(),a=age(),pv=c.params&&c.params.preview;if(a<18&&!pv)return scr('Your own space',cap('This opens at 18.'));
 var ch=k.seen.handoverChoice;
 return scr('Your own space',(pv&&a<18?banner('A preview of what you will see at 18.','info','soft'):'')+h2('Thank you for growing up here.')+p('Guardianship has closed. These are your choices, and none of them has a deadline.')+
  rowb({ic:'download',title:'Take and go',sub:'Make a copy of everything, then close the account.',act:'kid.handover',arg:'take'})+
  rowb({ic:'leaf',title:'Keep it as an archive',sub:'You run it yourself. No one else has access.',act:'kid.handover',arg:'keep'})+
  rowb({ic:'heart',title:'Someday, for your own family',sub:'What you were handed can become the first page of theirs.',act:'kid.handover',arg:'later'})+
  (ch?banner(ch==='take'?'Your copy was saved to this device.':ch==='keep'?'Kept. It is yours to look after.':'Noted. Nothing is needed from you.','check','soft'):''));
});
L.act('kid.handover',function(c,w){var k=ens();k.seen.handoverChoice=w;if(w==='take')L.run('k','kid.takeCopy');});

/* ====================================================== MY THINGS (guardian-chosen shelf) == */
TL.shelf={t:'My things',s:'From my grown-ups',ic:'layers',scr:'k.shelf'};
function shelfOn(){var s=P().shelf||{};return Object.keys(s).some(function(x){return s[x];});}
def('k.shelf','My things',function(){
 var k=ens(),Pp=P(),sh=Pp.shelf||{},out='';
 if(sh.rhythm){
  var pk=Pp.packing||[],np=Pp.newPlace||[];
  if(pk.length)out+='<h2 class="kx-h">My bag</h2><div class="kx-col">'+pk.map(function(x,i){var d=!!k.ticks.done['pk'+i];return '<button type="button" class="kx-rowb" data-act="kid.tick" data-arg="pk'+i+'" aria-pressed="'+d+'"><span class="ric">'+I('layers',24,1.9)+'</span><span class="rt"><b>'+E(x.text)+'</b></span><span class="ric" style="'+(d?'background:var(--ok);color:#fff':'background:var(--surface3);color:transparent')+'">'+I('check',24,2.6)+'</span></button>';}).join('')+'</div>';
  if(np.length)out+='<h2 class="kx-h">A new place</h2>'+np.map(function(x){return card('<p class="kx-p"><b>'+E(x.place)+'</b></p>'+(x.note?cap(x.note):''));}).join('');
 }
 if(sh.voice){var sy=Pp.symbols||[];out+='<h2 class="kx-h">My words</h2>'+rowb({ic:'hand',title:'Symbols board',sub:sy.length?'Includes words my grown-up added':'Tap to say it',act:'kid.open',arg:'k.symbols'});}
 if(sh.growing){
  var ft=Pp.firstTimes||[],cp=Pp.capsule||[];
  out+='<h2 class="kx-h">Growing</h2>'+rowb({ic:'hourglass',title:'Time capsule',sub:cp.length?'A grown-up sealed something':'Opens later',act:'kid.open',arg:'k.capsule'})+rowb({ic:'heart',title:'Memory box',sub:ft.length?'First times from a grown-up':'Things I keep',act:'kid.open',arg:'k.memory'})+rowb({ic:'leaf',title:'Growing marks',act:'kid.open',arg:'k.growth'});
 }
 if(sh.care){
  var po=Pp.poorly||[],vi=Pp.visit||[];
  if(po.length)out+='<h2 class="kx-h">When I feel poorly</h2>'+po.map(function(x){return rowb({plain:true,ic:'heart',title:x.text});}).join('');
  if(vi.length)out+='<h2 class="kx-h">Going to visit</h2>'+vi.map(function(x){return rowb({plain:true,ic:'home',title:x.text});}).join('');
 }
 if(sh.village){
  var vg=Pp.village||{},sit=vg.sitter||{},gr=vg.grand||{},scl=vg.school||{};
  if(sit.tonight&&sit.name)out+='<h2 class="kx-h">Tonight</h2>'+card('<p class="kx-p"><b>'+E(sit.name)+'</b> is looking after you'+(sit.from?' from '+E(sit.from):'')+(sit.until?' until '+E(sit.until):'')+'.</p>'+(sit.notes?cap(sit.notes):''),'tint');
  if(gr.greeting||gr.likes)out+='<h2 class="kx-h">Grandma’s page</h2>'+card((gr.greeting?'<p class="kx-p">'+E(gr.greeting)+'</p>':'')+(gr.likes?cap('Likes: '+gr.likes):''));
  if(scl.text)out+='<h2 class="kx-h">School</h2>'+card('<p class="kx-p">'+E(scl.text)+'</p>');
 }
 if(sh.compass){
  var cm=Pp.compass||{};
  out+='<h2 class="kx-h">Just for me</h2>'+cap('Your answers stay here. You can show a grown-up if you want to.');
  [['q1','compass1'],['q2','compass2']].forEach(function(q){if(cm[q[0]])out+='<label class="kx-cap" for="kx-'+q[1]+'">'+E(cm[q[0]])+'</label><input id="kx-'+q[1]+'" class="kx-in" data-bind="kid.draft.'+q[1]+'" maxlength="140" autocomplete="off" value="'+A(k.draft[q[1]])+'">';});
 }
 if(!out)out=card(p('Your grown-ups can add things here.'),'flat');
 return scr('My things',out,{say:'My things.'});
});

/* ----------------------------------------------------------------------- boot -- */
ens();
});
})();
