/* Child surfaces, first run, setup and identity. ROUND 2.
   Sample world: Ivy (6). Her grown-ups are Marcus and Jess, plus Grandma. In the child shell a person is shown by the name Ivy
   uses, read from the family record; where the app has no name it says "your grown-up". No screen here hardcodes a role word as a name.
   Shared helpers live on OB.mk so the other round-2 screen files can reuse them. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc,D=K.def,M=K.mk=K.mk||{};
var N=M.N={kid:"Ivy",a:"Marcus",b:"Jess",gm:"Grandma"};
M.css=function(id,css){if(document.getElementById(id))return;var s=document.createElement("style");s.id=id;s.textContent=css;document.head.appendChild(s);};
M.css("r2-mk",
".ob .rr-48{width:48px;height:48px}"+
".ob .btn.rr-t48{min-height:48px;font-size:14px}"+
".ob .tabbar.rr-tb span{min-height:50px;justify-content:center}"+
".ob .rr-dot{display:inline-block;width:14px;height:14px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px var(--surface);flex:none}"+
".ob .rr-abs{position:absolute;top:10px;right:10px}.ob .rr-rel{position:relative}"+
".ob .rr-sk{display:block;background:var(--surface3);border-radius:10px;flex:none}"+
".ob .card.hero .rr-sk,.ob .rr-sk.on{background:rgba(255,255,255,.22)}"+
".ob .rr-cs{display:grid;justify-items:center;gap:12px;text-align:center;padding:4px 0 8px}"+
".ob .rr-art{position:relative;width:100%;margin-bottom:40px}.ob .rr-art .scene{border-radius:28px}"+
".ob .rr-badge{position:absolute;left:50%;bottom:-42px;transform:translateX(-50%);width:84px;height:84px;border-radius:30px;background:var(--surface);color:var(--pri);display:grid;place-items:center;box-shadow:var(--shadow2);border:4px solid var(--bg)}"+
".ob .rr-cl{font:800 24px/1.15 var(--font-display);color:var(--ink);text-wrap:balance;padding:0 6px}"+
".ob .rr-cs-s{color:var(--ink2);font-size:15px;padding:0 8px}"+
".ob .rr-acts{display:grid;gap:10px;width:100%;margin-top:4px}"+
".ob .rr-ge{display:grid;justify-items:center;gap:8px;text-align:center}.ob .rr-ge-art{width:calc(100% + 0px);border-radius:18px;overflow:hidden;margin-bottom:4px}.ob .rr-ge b{font:800 18px/1.2 var(--font-display)}.ob .rr-ge p{margin:0;max-width:30ch}"+
".ob .rr-who{display:flex;justify-content:space-between;gap:6px}.ob .rr-who>span{display:grid;justify-items:center;gap:5px;font:700 12px/1.1 var(--font-body);color:var(--ink2);min-width:0;flex:1}.ob .rr-who>span.on{color:var(--ink)}"+
".ob .rr-who .rr-w{width:min(56px,100%);aspect-ratio:1;border-radius:50%;display:grid;place-items:center;background:var(--surface2);color:var(--ink2)}.ob .rr-who .on .rr-w{box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--pri)}"+
".ob .rr-steps{display:grid;grid-template-columns:repeat(3,1fr);position:relative;gap:4px}.ob .rr-steps:before{content:\"\";position:absolute;left:16.6%;right:16.6%;top:15px;height:3px;background:var(--okC);border-radius:3px}"+
".ob .rr-steps div{display:grid;justify-items:center;gap:3px;text-align:center;position:relative;font-size:11.5px;color:var(--ink3)}.ob .rr-steps div i{width:32px;height:32px;border-radius:50%;background:var(--ok);color:#fff;display:grid;place-items:center}.ob .rr-steps div b{font-size:12.5px;color:var(--ink)}"+
".ob .rr-eb{font:700 10.5px/1 var(--font-mono);letter-spacing:.09em;text-transform:uppercase;color:var(--ink3)}"+
".ob .rr-dp{display:flex;gap:12px;align-items:center;padding:11px 0;min-width:0}.ob .card>.rr-dp+.rr-dp{border-top:1px solid color-mix(in srgb,var(--outline) 70%,transparent)}"+
".ob .rr-dp>i{width:8px;align-self:stretch;border-radius:8px;flex:none}.ob .rr-dp.now{background:var(--priC);margin:0 -14px;padding:11px 14px;border-radius:16px}"+
".ob .rr-dp .rtxt small{font-size:13px}"+
".ob .rr-ring{position:relative;display:grid;place-items:center}.ob .rr-ring svg.rg{position:absolute;inset:0}"+
".ob .rr-rest{display:flex;gap:10px;align-items:center;padding:10px 14px;border-radius:20px;background:var(--surface2);color:var(--ink2);font:700 14px/1.2 var(--font-body)}"+
".ob .rr-off{outline:2px dashed var(--outline);outline-offset:-2px}.ob .rr-cloud{position:absolute;top:8px;right:8px;color:var(--ink3);display:grid}"+
".ob .rr-letters{display:flex;gap:8px;justify-content:center}.ob .rr-letters span{width:62px;height:76px;border-radius:20px;background:var(--surface);box-shadow:var(--shadow1);display:grid;place-items:center;font:800 40px/1 var(--font-display);color:var(--pri)}"+
".ob .rr-letters span.cur{background:transparent;box-shadow:none;border:3px dashed var(--outline)}"+
".ob .rr-corner{position:absolute;width:34px;height:34px;border:5px solid #fff;border-radius:10px}"+
".ob .rr-chk{position:absolute;top:6px;right:6px;width:26px;height:26px;border-radius:50%;background:var(--bg);color:var(--ink);display:grid;place-items:center}"+
".ob .rr-pill{display:inline-flex;gap:6px;align-items:center;padding:7px 12px;border-radius:99px;font:700 12.5px/1 var(--font-body);background:var(--surface2);color:var(--ink2)}"+
".ob .rr-big{font:800 34px/1 var(--font-display);letter-spacing:-.02em}"+
".ob .rr-note{font:13.5px/1.4 var(--font-body);color:var(--ink2)}");

/* the day ribbon drawn on her real day parts: wake, before school, school, after school, dinner, wind down and bed, asleep. */
M.bands=[["dpNight",0,29],["dpMorning",29,35.4],["dpDay",35.4,62.5],["dpAfternoon",62.5,75],["dpEvening",75,79],["dpBed",79,81.3],["dpNight",81.3,100]];
M.rib=function(o){o=o||{};return K.ribbon({bands:M.bands,now:o.now===undefined?32:o.now,overlap:o.noov?null:[62.5,8.3],n:o.n});};
M.dot=function(l){return '<i class="rr-dot" role="img" aria-label="'+(l||"New")+'"></i>';};
M.sk=function(w,h,r,cls){return '<i class="rr-sk'+(cls?" "+cls:"")+'" style="width:'+w+';height:'+h+'px;border-radius:'+(r||10)+'px"></i>';};
M.ftile=function(o,dot,rest){var h=K.tile("feat",o);h=h.replace('class="tile feat','class="rr-rel tile feat'+(rest?" rr-off":""));
 var add=(dot?'<i class="rr-dot rr-abs" role="img" aria-label="New"></i>':"")+(rest?'<span class="rr-cloud">'+I("cloud",18,1.8)+'</span>':"");return add?h.replace(/<\/div>$/,add+'</div>'):h;};
M.ctop=function(t,o){o=o||{};return K.sb()+K.top({back:o.back!==false,title:t,eyebrow:o.eyebrow,right:o.right!==undefined?o.right:(o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:o.ns}))});};
M.gtop=function(t,o){o=o||{};return (K.sb()+K.top({back:!o.noBack,title:t,eyebrow:o.eyebrow,right:o.right||""})).replace('class="cbtn"','class="cbtn rr-48"');};
M.two=function(c,l,r,title,o){if(c.form==="tablet")return M.gtop(title,o)+'<div class="tw"><div>'+l+'</div><div>'+r+'</div></div>';return M.gtop(title,o)+K.page(l+r);};
M.tabs=function(a,last){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],last||["more","More"]],a).replace('class="tabbar"','class="tabbar rr-tb"');};
M.b48=function(t,o){return K.btn(t,o).replace('class="btn ','class="btn rr-t48 ');};
/* child state screen: picture first, one warm line, at most two big buttons. No error text and no codes. */
M.cstate=function(o){return '<div class="rr-cs"><div class="rr-art"'+K.n(o.n1)+'>'+K.scene(o.scene||"hills",300,o.h||140)+'<span class="rr-badge">'+I(o.ic,42,1.6)+'</span></div><b class="rr-cl"'+K.n(o.n2)+'>'+E(o.line)+'</b>'+(o.sub?'<span class="rr-cs-s">'+E(o.sub)+'</span>':"")+K.speak("")+'<div class="rr-acts"'+K.n(o.n3)+'>'+(o.acts||"")+'</div></div>';};
/* guardian empty state: one illustration, one sentence about what will appear, one clear next step. */
M.gempty=function(o){return K.card('<div class="rr-ge"'+K.n(o.n)+'><div class="rr-ge-art">'+K.scene(o.scene||"paper",300,96)+'</div><b>'+E(o.title)+'</b><p class="rr-note">'+E(o.sub)+'</p>'+(o.act||"")+'</div>');};
M.ring=function(p,inner,sz){sz=sz||168;var r=sz/2-7,c=2*Math.PI*r;return '<div class="rr-ring" style="width:'+sz+'px;height:'+sz+'px"><svg class="rg" viewBox="0 0 '+sz+' '+sz+'"><circle cx="'+sz/2+'" cy="'+sz/2+'" r="'+r+'" fill="none" stroke="var(--surface3)" stroke-width="8"/><circle cx="'+sz/2+'" cy="'+sz/2+'" r="'+r+'" fill="none" stroke="var(--pri)" stroke-width="8" stroke-linecap="round" stroke-dasharray="'+(c*p).toFixed(1)+' '+c.toFixed(1)+'" transform="rotate(-90 '+sz/2+' '+sz/2+')"/></svg>'+inner+'</div>';};
M.person=function(l,sz,tone){return K.avatar(l,{size:sz||42,tone:tone});};
M.NOTE_NAMES="Names come from the family record: the name Ivy uses for each person. If none is known the app says “your grown-up”.";
var ctop=M.ctop,gtop=M.gtop,sk=M.sk;
function swatches(){return [["#F2B705","sunny yellow"],["#E8730C","orange"],["#F0757E","coral pink"],["#E056A8","bright pink"],["#8B6BB1","purple"],["#2F8FC4","sea blue"],["#6BB8E8","sky blue"],["#5FC9A8","mint"],["#5AA84A","grass green"],["#8A6244","chocolate"],["#7C8698","storm grey"],["#2B3358","midnight"]];}
function dots(n,f){return '<div style="padding:2px 0 6px">'+K.dots(n,f)+'</div>';}
function skipBtn(){return K.btn("Skip for now",{kind:"ghost",full:true,size:"lg"});}
var FIRST="First-run only, done with a grown-up beside her. It is never reachable from her home, and her shell holds no setup screens. ";

/* ----------------------------------------------------------- child home -- */
function homeTop(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+K.avatar("I",{size:42,ring:true})});}
function homeBody(mode){
 var off=mode==="offline",load=mode==="loading";
 var presence=load?K.card('<div style="display:grid;gap:12px">'+sk("46%",14,8,"on")+'<div style="display:flex;justify-content:space-between;align-items:end">'+sk("52%",38,12,"on")+sk("24%",20,8,"on")+'</div>'+sk("100%",22,12,"on")+'</div>',"hero",1):
  K.card(K.dual({n:1,l1:"Ivy",t1:"7:42 AM",s1:"Before school",l2:N.a,t2:"1:42 AM",s2:"Sleeping"})+'<div style="height:14px"></div>'+M.rib({now:32})+'<div class="chips" style="margin-top:10px"><span class="chip" style="background:rgba(255,255,255,.2);color:inherit">'+I("moon",13,2)+' 3 sleeps until '+N.a+'’s house</span></div>',"hero");
 if(load)return presence+sk("100%",138,26)+'<div class="grid2">'+[0,1,2,3].map(function(){return sk("100%",76,21);}).join("")+'</div>'+K.sectionLabel("More")+'<div class="grid3">'+[0,1,2,3,4,5].map(function(){return sk("100%",84,19);}).join("")+'</div>';
 var rest=function(o,dot){return M.ftile(o,dot,off);};
 return (off?'<div class="rr-rest"'+K.n(5)+'>'+I("cloud",22,1.8)+'<span>The wifi is resting. Your things are still here.</span></div>':"")+presence+
  K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Grandma’s",scene:"hills",n:2})+
  '<div class="grid2">'+rest({ic:"dice",title:"Play together",n:3})+M.ftile({ic:"chat",title:"Messages"},!off)+M.ftile({ic:"book",title:"Stories"})+rest({ic:"camera",title:"Show & tell"})+'</div>'+
  K.sectionLabel("More")+'<div class="grid3"'+K.n(4)+'>'+[["pencil","Homework"],["list","Wants"],["book","Journal"],["calendar","Weeks"],["palette","Colour"],["image","Photos"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>';
}
D("childHome","child","Her home",{grp:"Child",since:"0.8.0",
 desc:"Her name, the two clocks, the sleeps count. Three tiers: Hero (My day), Featured (Play together, Messages, Stories, Show & tell), Standard (the rest). No settings affordance at any depth. At the Fold5 cover only the presence card and the Hero tile show, the rest behind one More tile.",
 notes:[[1,"The two clocks: her time is big, the other grown-up’s is the quiet aside. The ribbon is drawn on her real day parts and the sleeps count shares the card, so the whole day is one glance. "+M.NOTE_NAMES],[2,"One Hero tile with a picture. It is the single thing bigger than everything else, and it is her own day."],[3,"Four Featured tiles, icon and one word each. Unread is a dot on Messages, never a number (P2: nothing counts up at her)."],[4,"Standard tiles are a quiet grid. Nothing pulses, wiggles or asks for her attention (§8.13). There is no settings tile, no grown-up control and no tour here."]],
 r:function(){return homeTop()+K.page(homeBody(""));},
 cover:function(){return K.sb()+K.top({logo:true,title:"Hi, Ivy"})+K.page(K.card(K.dual({t1:"7:42",t2:"1:42",l1:"Ivy",l2:N.a,s1:"",s2:""}),"hero")+K.tile("hero",{ic:"calendar",title:"My day",sub:"",scene:"hills"})+K.tile("feat",{ic:"grid",title:"More",sub:"Everything else"}));}});

D("childHome-offline","child","Her home, offline",{grp:"Child",since:"new",isNew:true,
 desc:"No connection. Her clocks, her day, stories and journal all still work because they live on the device. Things that need another person wear a small cloud and stay put until the wifi is back.",
 notes:[[1,"The clocks and ribbon are computed on the device, so the hero card is exactly the same offline."],[2,"My day still opens: it reads from the device, so the Hero tile never needs the wifi."],[3,"Tiles that need someone else carry a quiet cloud and a dashed edge. They stay full-contrast and tappable; a tap shows a picture of the cloud napping, never a failure."],[4,"Everything she can do alone is untouched: day, stories, journal, colour, photos. Nothing is removed while offline."],[5,"One soft line with a cloud. No red, no “error”, no code, and nothing she has to fix."]],
 r:function(){return homeTop()+K.page(homeBody("offline"));}});

D("childHome-loading","child","Her home, loading",{grp:"Child",since:"new",isNew:true,
 desc:"First paint before the family record arrives. Her name is shown from the device; the shapes are exactly where the cards will land so nothing jumps.",
 notes:[[1,"Shapes, not a spinner. They are static: no shimmer and no looping motion anywhere (§8.13)."],[2,"“Hi, Ivy” is already real. It is stored on the device, so she sees her own name before anything else."],[3,"The shapes match the final layout one for one, so when data arrives the page crossfades in place and nothing moves under her finger."]],
 r:function(){return (K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.iconBtn("volume",{kind:"tonal",label:"Hear it"})+K.avatar("I",{size:42,ring:true})})).replace('<div class="ttl">','<div class="ttl"'+K.n(2)+'>')+K.page('<div'+K.n(3)+' style="display:grid;gap:12px">'+homeBody("loading")+'</div>');}});

/* ---------------------------------------------------------------- inbox -- */
function whoRow(sel){var P=[["users","Everyone",0],["M",N.a,1],["J",N.b,2],["G","Grandma",3]];return '<div class="rr-who"'+K.n(1)+'>'+P.map(function(p,i){return '<span class="'+(i===sel?"on":"")+'"><i class="rr-w" style="font:800 20px var(--font-display)">'+(p[0].length>1?I(p[0],24,1.8):p[0])+'</i>'+p[1]+'</span>';}).join("")+'</div>';}
D("inbox","child","Inbox",{grp:"Child",since:"0.8.0",desc:"Messages the delivery engine has already delivered, told in her words. Tap one to open its receipt full screen; there is no persistent detail pane on tablet.",
 notes:[[1,"She filters by picture: a face and a name, never a dropdown or a role label. "+M.NOTE_NAMES],[2,"Every message says when it reached her in her own words: “before school”, “at bedtime”, never a clock time first."],[3,"Unread is a quiet dot beside the thing, never a number that grows (P2). Read ones simply have no dot."],[4,"A sealed letter shows when it opens, in sleeps. It cannot be opened early, and nothing counts down at her."]],
 r:function(){return ctop("Messages",{ns:1})+K.page(whoRow(0)+
  K.card('<div style="height:92px;margin:-2px -2px 10px;border-radius:20px;overflow:hidden">'+K.scene("night",300,92)+'</div><div class="row" style="padding:0"><span class="rtxt"><b style="font-size:16px">A story from '+N.a+'</b><small'+K.n(2)+'>Arrived before school</small></span><span class="chip pri">'+I("play",12,2)+' 2 min</span>'+M.dot()+'</div>')+
  K.card(K.row({av:K.avatar("G",{size:48}),title:"Grandma",sub:"A picture of the garden",trail:M.dot(),n:3})+K.row({av:K.avatar("J",{size:48,tone:"accent"}),title:N.b,sub:"See you at pickup",go:true})+K.row({av:K.avatar("M",{size:48,tone:"accent"}),title:N.a,sub:"Watched last night, at bedtime",go:true}))+
  K.card(K.row({ic:"letter",title:"A letter from "+N.a,sub:"Sealed. Opens Saturday",trail:K.chip("2 sleeps",{tone:"pri",sm:true}),n:4}),"tint"));}});

D("inbox-empty","child","Inbox, empty",{grp:"Child",since:"new",isNew:true,desc:"Nothing has arrived yet. A picture and one warm line; no instructions, no button she could get wrong.",
 notes:[[1,"A mailbox, waiting. Nothing says “empty” or “no messages”; an empty inbox is not a failure."],[2,"One short line she can have read aloud. No pressure to write first."],[3,"The only buttons lead somewhere she already likes. Nothing nudges anyone to write to her (P2)."]],
 r:function(){return ctop("Messages")+K.page(M.cstate({scene:"letters",ic:"mail",line:"Nothing here yet. Something nice will come.",sub:"",n1:1,n2:2,n3:3,acts:K.btn("See my day",{full:true,size:"lg",ic:"calendar"})+K.btn("Hear a story",{kind:"tonal",full:true,size:"lg",ic:"book"})}));}});

D("receipt","child","Receipt",{grp:"Child",since:"0.49.49",desc:"“Watched at 7:04 AM, before school.” Her frame first, always. Live-wired with the real baseUrl, childId and sessionToken.",
 notes:[[1,"The receipt is told in her frame: her clock, her day part. The other house’s time is never the headline."],[2,"The journey of the message is three steps she can follow by the ticks: recorded, arrived, watched."],[3,"Replying is three big pictures. A heart is a whole reply. Nothing needs typing."]],
 r:function(){return ctop("From "+N.a,{ns:1})+K.page(
  '<div style="position:relative;border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("night",300,170)+'<span style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:68px;height:68px;border-radius:50%;background:rgba(255,255,255,.94);display:grid;place-items:center;color:var(--priD)">'+I("play",30,2)+'</span></span></div>'+
  K.card('<p style="font:800 20px/1.2 var(--font-display);margin:0 0 14px;color:var(--ink)"'+K.n(1)+'>Watched at 7:04 AM, before school</p><div class="rr-steps"'+K.n(2)+'><div><i>'+I("check",16,2.6)+'</i><b>Made</b>Tuesday</div><div><i>'+I("check",16,2.6)+'</i><b>Came</b>Before school</div><div><i>'+I("check",16,2.6)+'</i><b>Watched</b>7:04 AM</div></div>')+
  '<div class="grid3"'+K.n(3)+'>'+[["heart","Love it"],["mic","Say hi"],["camera","Show "+N.a]].map(function(b){return '<div class="tile std" style="padding:14px 4px"><span class="tic" style="width:52px;height:52px">'+I(b[0],26,1.9)+'</span><b>'+E(b[1])+'</b></div>';}).join("")+'</div>');}});

D("receipt-error","child","Receipt, trouble",{grp:"Child",since:"new",isNew:true,desc:"The message could not be opened right now. Picture first: the envelope is napping. No error text, no code, nothing blamed on her or her tablet.",
 notes:[[1,"The same picture she knows, resting. The message itself is safe and says so with an image, not a sentence of explanation."],[2,"One kind line she can have read aloud. It never says “failed”, “error” or a number (P2, §8.13)."],[3,"Try again is the big button; Back is as large and just as friendly. The app keeps retrying quietly, so tapping is optional."]],
 r:function(){return ctop("From "+N.a)+K.page(M.cstate({scene:"night",ic:"mail",line:"This one is having a little nap.",sub:"It will wake up soon.",n1:1,n2:2,n3:3,acts:K.btn("Try again",{full:true,size:"lg",ic:"refresh"})+K.btn("Back to messages",{kind:"tonal",full:true,size:"lg"})}));}});

/* ------------------------------------------------------------- pin gate -- */
function keys(){return [7,3,9,1,5,8,2,6,4,0].map(function(n,i){return '<button'+(i===9?' style="grid-column:2"':"")+'>'+n+'</button>';}).join("");}
D("pin","child","PIN gate",{grp:"Child",since:"0.8.0",desc:"The doorway into the grown-up side. Ten shuffled keys, because the child is watching. A wrong PIN just clears, with no error text. Reached by a real kiosk defeat, not only a dev button.",
 notes:[[1,"The keys are shuffled every time, because the child watching a PIN is being typed is the real threat model."],[2,"A wrong PIN clears the dots. No red, no message, no lockout theatre on this screen."],[3,"After too many tries the gate closes and shows the picture screen next, with a one-tap call to a grown-up. The other guardian is told quietly."]],
 r:function(){return K.sb()+K.page('<div class="center" style="min-height:520px"><span class="ricon" style="width:72px;height:72px;border-radius:26px">'+I("lock",32,1.8)+'</span><b style="font:800 26px/1.1 var(--font-display)"'+K.n(3)+'>Grown-ups only</b><span class="rr-note">Please ask your grown-up to open this.</span><div'+K.n(2)+'>'+K.dots(4,2)+'</div>'+'<div class="kp"'+K.n(1)+'>'+keys()+'</div></div>');}});

D("pin-lockout","child","Gate closed",{grp:"Child",since:"new",isNew:true,desc:"After too many wrong PINs the gate rests. A big picture message and a single tap to call a grown-up. No timer, no number, no mention of the PIN.",
 notes:[[1,"A big picture says it all: the gate is asleep for a while. Nothing here shows a countdown or any digit (§8.3, P2)."],[2,"“Call a grown-up” is the whole screen’s purpose. One tap, a 64 dp-plus target, and it rings the person she is with, by name."],[3,"The other guardian is notified in the background that someone tried the gate. She is never told that, and never blamed."]],
 r:function(){return K.sb()+K.page('<div class="center" style="min-height:540px;gap:14px"><div style="position:relative;width:100%;margin-bottom:34px"'+K.n(1)+'><div style="border-radius:30px;overflow:hidden">'+K.scene("night",300,170)+'</div><span style="position:absolute;left:50%;bottom:-34px;transform:translateX(-50%);width:84px;height:84px;border-radius:30px;background:var(--surface);color:var(--pri);display:grid;place-items:center;box-shadow:var(--shadow2);border:4px solid var(--bg)">'+I("lock",38,1.6)+'</span></div><b class="rr-cl">The door is resting.</b><span class="rr-cs-s"'+K.n(3)+'>Let’s get your grown-up.</span>'+K.speak("")+'<div class="rr-acts"'+K.n(2)+'>'+K.btn("Call "+N.b,{full:true,size:"lg",ic:"phone"})+'</div></div>');}});

/* -------------------------------------------------------------- wants -- */
D("list","child","Wants & needs",{grp:"Child",since:"0.8.0",wide:true,desc:"Two lists, structurally separate. No price field, no buy button, no link (P4). A real two-pane split on tablet and desktop widths.",
 notes:[[1,"Needs and wants are two lists with two headings. They never mix and nothing moves between them by itself."],[2,"There is no price, no link and no buy affordance anywhere (P4). A want is a word and a picture, not a product."],[3,"Adding is by voice or by drawing first, because typing is the slowest way for a five-year-old."]],
 r:function(c){var needs=K.card(K.sectionLabel("Things I need")+K.row({ic:"book",title:"A new library card",n:1})+K.row({ic:"pencil",title:"Pencils for school",n:2})+K.row({ic:"smile",title:"Rain boots"}));
  var wants=K.card(K.sectionLabel("Things I want")+K.row({ic:"puzzle",title:"A big puzzle"})+K.row({ic:"palette",title:"Watercolours"})+K.row({ic:"dice",title:"Checkers"}));
  var add='<div class="btns"'+K.n(3)+'>'+K.btn("Say it",{kind:"tonal",ic:"mic",size:"lg"})+K.btn("Draw it",{kind:"tonal",ic:"brush",size:"lg"})+'</div>';
  if(c.form==="tablet")return ctop("My lists",{noSpeak:true})+'<div class="tw"><div>'+needs+'</div><div>'+wants+add+'</div></div>';
  return ctop("My lists",{noSpeak:true})+K.page(K.seg(["Needs","Wants"],0)+needs+add);}});

/* --------------------------------------------------------------- my day -- */
function dp(col,ic,title,sub,now,n){return '<div class="rr-dp'+(now?" now":"")+'"'+K.n(n)+'><i style="background:var(--'+col+')"></i><span class="ricon" style="background:var(--surface2)">'+I(ic,20,1.9)+'</span><span class="rtxt"><b>'+title+'</b><small>'+sub+'</small></span>'+(now?'<span class="chip pri sm">Now</span>':"")+'</div>';}
D("myday","child","My day",{grp:"Child",since:"0.13.0",desc:"Her day as her own day parts: wake up, before school, school, after school, dinner, wind down, bedtime, asleep. Colours are protected (§8.2, §8.6.2).",
 notes:[[1,"The ribbon is the one semantic surface, drawn on her real day parts. Day-part colours are protected and never take her colour (§8.6.2). The line marks now."],[2,"The green band means “you can both talk right now”, found from her day parts and the other grown-up’s, so nobody does time-zone sums."],[3,"Each day part reads as a sentence with a colour bar and a picture, in the order she lives it. The current one is highlighted, never animated."],[4,"The call button is always there but honest: it names who she is calling and when it is a good time."]],
 r:function(){return ctop("My day",{ns:1})+K.page(
  K.card('<h4>Thursday</h4>'+M.rib({now:32,n:1})+'<div class="chips" style="margin-top:10px"><span class="chip ok"'+K.n(2)+'>'+I("phone",13,2)+' You can both talk 3 to 5 PM</span></div>')+
  K.card(dp("dpMorning","sun","Wake up","7:00",false)+dp("dpMorning","smile","Before school","7:30 to 8:30",true,3)+dp("dpDay","book","School","8:30 to 3:00",false)+dp("dpAfternoon","heart","After school","Grandma’s house",false)+dp("dpEvening","smile","Dinner","6:00",false)+dp("dpBed","moon","Wind down, then bedtime","7:00 and 7:30",false)+dp("dpNight","moon","Asleep","All night",false))+
  K.btn("Call "+N.a+" at 3 PM",{ic:"video",full:true,size:"lg",n:4}));}});

/* ---------------------------------------------------------------- weeks -- */
D("weeks","child","Weeks",{grp:"Child",since:"0.13.0",desc:"The two homes as she lives them; countdowns in sleeps. A rhythm picture, not a list and a detail.",
 notes:[[1,"Two houses, two colours, one calendar. No percentages, no “custody split”, no counts of who has her more."],[2,"Today is ringed and past days soften. Nothing else on the page asks for her attention."],[3,"Her countdown is in sleeps, a unit she understands, and says whose house is next."]],
 r:function(){var cells="",dad={6:1,7:1,8:1,9:1,20:1,21:1,22:1,23:1},d;for(d=0;d<28;d++){var isd=!!dad[d];cells+='<span style="aspect-ratio:1;border-radius:50%;background:'+(isd?"var(--accent)":"var(--pri)")+';opacity:'+(d<3?.3:1)+';'+(d===3?"box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink)":"")+'"></span>';}
  return ctop("My weeks",{ns:1})+K.page(K.card('<div class="chips" style="margin-bottom:12px"><span class="chip pri"><i style="width:9px;height:9px;border-radius:50%;background:var(--pri)"></i> '+N.b+'’s house</span><span class="chip" style="background:var(--accentC);color:var(--ink)"><i style="width:9px;height:9px;border-radius:50%;background:var(--accent)"></i> '+N.a+'’s house</span></div><div style="display:grid;grid-template-columns:repeat(7,1fr);gap:9px"'+K.n(1)+'>'+cells+'</div><div style="margin-top:10px;font:700 11px var(--font-body);color:var(--ink3);text-align:center"'+K.n(2)+'>The ring is today</div>')+
  K.card('<div class="center" style="min-height:0;padding:6px;gap:4px"'+K.n(3)+'><span class="rr-big" style="color:var(--pri);font-size:56px">3</span><b style="font:800 18px var(--font-display)">sleeps until '+N.a+'’s house</b></div>',"tint"));}});

D("weeks-empty","child","Weeks, empty",{grp:"Child",since:"new",isNew:true,desc:"Her calendar before any plan is set. The child side never shows a hole in a schedule as a problem.",
 notes:[[1,"The grid is there, calm and neutral, so the screen still looks like a calendar and not like an absence."],[2,"One line in her words and a picture. It never says nothing is planned, and never points at a grown-up’s task."],[3,"No buttons that edit anything. She cannot change the schedule (§8.1: no settings in her shell); a grown-up sets it from their own side."]],
 r:function(){var cells="";for(var d=0;d<28;d++)cells+='<span style="aspect-ratio:1;border-radius:50%;background:var(--surface3);'+(d===3?"box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink)":"")+'"></span>';
  return ctop("My weeks")+K.page(K.card('<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:9px"'+K.n(1)+'>'+cells+'</div>')+M.cstate({scene:"hills",ic:"calendar",line:"Your days are still being drawn.",sub:"",n2:2,n3:3,acts:K.btn("See my day",{full:true,size:"lg",ic:"sun"})}));}});

/* -------------------------------------------------------------- journal -- */
D("journal","child","Journal",{grp:"Child",since:"0.8.0",desc:"Hers alone. No grown-up path exists at any tier (P7). A permanently still surface (§8.13.5).",
 notes:[[1,"Deliberately plain and still. Nothing moves, prompts or counts while she thinks. There is no streak and no “you haven’t written”."],[2,"One reassurance, once, in her words: nobody else can read this. It is true in code, not only in copy (P7)."],[3,"She can draw, say it or write. Voice and drawing come first because they are faster than letters at six."]],
 r:function(){return ctop("My journal",{noSpeak:true})+K.page(K.banner("pri","Only you can read this. Nobody else.","lock",2)+
  K.card('<small class="rr-eb">Thursday</small><p style="font:700 19px/1.5 var(--font-body);color:var(--ink);margin:8px 0">Today I saw a heron at the pond. It stood so still that I held my breath.</p><div style="height:90px;border-top:1px dashed var(--outline);margin-top:14px"></div>','',1)+
  '<div class="grid3"'+K.n(3)+'>'+[["brush","Draw"],["mic","Say it"],["pencil","Write"]].map(function(b){return '<div class="tile std" style="padding:14px 4px"><span class="tic" style="width:48px;height:48px">'+I(b[0],24,1.9)+'</span><b>'+b[1]+'</b></div>';}).join("")+'</div>');}});

D("journal-empty","child","Journal, empty",{grp:"Child",since:"new",isNew:true,desc:"A new journal. A blank page, the same three ways in, and the privacy promise. No prompt, no suggested topic, no streak.",
 notes:[[1,"A clean page with a soft lock mark. There is no “write your first entry” and no coach (P2, §8.13.5)."],[2,"Three equal doors: draw, say it, write. Whichever she picks, the page just starts."],[3,"The promise is kept in plain words and is the only text on the page."]],
 r:function(){return ctop("My journal",{noSpeak:true})+K.page(K.card('<div class="center" style="min-height:0;padding:22px 6px"><span class="ricon" style="width:72px;height:72px;border-radius:26px">'+I("book",32,1.7)+'</span><span class="rr-cs-s">Only you can read this.</span></div>','',1)+
  '<div class="grid3"'+K.n(2)+'>'+[["brush","Draw"],["mic","Say it"],["pencil","Write"]].map(function(b){return '<div class="tile std" style="padding:14px 4px"><span class="tic" style="width:52px;height:52px">'+I(b[0],26,1.9)+'</span><b>'+b[1]+'</b></div>';}).join("")+'</div>'+K.banner("pri","Not even your grown-ups.","lock",3));}});

/* ------------------------------------------------------- setup (guardian) -- */
D("lockAdvisory","guardian","Kiosk advisory",{grp:"Setup & identity",since:"0.11.0",desc:"Native setup flow that advises the grown-up on the device’s kiosk state (§8.3). Grown-up shell, shown on the grown-up’s own phone.",
 notes:[[1,"The headline says what is at stake in one sentence. Each failing line below says exactly what to do next."],[2,"One primary action, to the OS settings. The product uses the platform lock; it never builds its own."],[3,"Windows is an app-level lock, not OS Assigned Access. The screen says which kind it is, so nobody assumes more than is true."]],
 r:function(){return gtop("Lock Ivy’s device")+K.page(K.banner("warn","Screen pinning is off. Ivy could leave the app.","warn",1)+
  K.card(K.row({ic:"shieldcheck",title:"Olive is her device’s only app",sub:"Checked just now",tone:"ok",trail:K.chip("Good",{tone:"ok",sm:true})})+K.row({ic:"lock",title:"Screen pinning",sub:"Turn on in Settings, then Security",tone:"warn",trail:K.chip("Off",{tone:"warn",sm:true})})+K.row({ic:"bell",title:"Notifications hidden on lock",sub:"Off for everything but Olive",tone:"ok",trail:K.chip("Good",{tone:"ok",sm:true})}))+
  K.btn("Open Android settings",{full:true,n:2,ic:"sliders",size:"lg"})+K.btn("I’ll do this later",{kind:"ghost",full:true})+'<p class="rr-note" style="text-align:center;margin:0"'+K.n(3)+'>On Windows this is an app-level lock.</p>');}});

/* --------------------------------------------------------- first run, id -- */
D("welcome","child","Welcome",{grp:"Setup & identity",since:"0.24.0",desc:"A role question, not an age gate. “Grown-up” grants nothing by itself; every capability passes through the real family-graph authoriser. "+FIRST,
 notes:[[1,"Two equal cards. The product never asks a child to prove she is one, and never blocks either answer."],[2,"One logo and one line of warmth. No legal wall on the first screen; consent is read later, to the grown-up."],[3,FIRST+"Choosing “grown-up” changes what is offered; it grants nothing by itself."]],
 r:function(){return K.sb()+K.page('<div style="display:grid;gap:12px;padding-top:10px">'+K.logo(48)+'<div class="big" style="margin-top:6px"'+K.n(2)+'>Hello.<br>Which side are you?</div></div>'+
  '<div class="card" style="padding:0;overflow:hidden"'+K.n(1)+'>'+K.scene("paper",300,104)+'<div style="padding:12px 14px;display:flex;align-items:center;gap:12px"><span style="flex:1"><b style="font:800 21px var(--font-display)">I’m a kid</b><p>Play, talk and see my day.</p></span>'+K.iconBtn("chevR",{kind:"pri",label:"Choose kid"})+'</div></div>'+
  '<div class="card" style="padding:0;overflow:hidden"'+K.n(3)+'>'+K.scene("branch",300,104)+'<div style="padding:12px 14px;display:flex;align-items:center;gap:12px"><span style="flex:1"><b style="font:800 21px var(--font-display)">I’m a grown-up</b><p>Set things up and stay close.</p></span>'+K.iconBtn("chevR",{kind:"pri",label:"Choose grown-up"})+'</div></div>');}});

D("guardianSetup","guardian","Grown-up account setup",{grp:"Setup & identity",since:"0.49.30",desc:"Passkey sign-in and real consent continue here. The kiosk PIN setup is real, wired to the real route. Grown-up shell.",
 notes:[[1,"Passkey first. There is no password field anywhere in the product."],[2,"Consent is read in plain words, one short paragraph per item, before anything is stored."],[3,"The kiosk PIN is set last: four dots and a numeric pad. It is the grown-ups’ gate, never Ivy’s."]],
 r:function(){return gtop("Set up your account",{eyebrow:"Step 2 of 3"})+K.page(K.progress(66)+
  K.card(K.row({ic:"key",title:"Create a passkey",sub:"Use your face, finger or screen lock",trail:K.chip("Ready",{tone:"ok",sm:true}),n:1})+K.row({ic:"shieldcheck",title:"What we store",sub:"Names, schedules, messages you send",go:true,n:2})+K.row({ic:"users",title:"Who can see what",sub:"You and the other guardian, the same view",go:true}))+
  K.card('<h4>Ivy’s device PIN</h4><p>Four digits only the grown-ups know.</p><div style="padding:6px 0 2px">'+K.dots(4,0)+'</div>',"",3)+K.btn("Continue",{full:true,size:"lg"}));}});

D("obName","child","First run: name",{grp:"Setup & identity",since:"0.24.0",desc:"She spells or says her name; it is hers from the first screen. "+FIRST,
 notes:[[1,"The question is spoken and written. The microphone is as big as the keyboard."],[2,"Her name appears in large letter tiles as she goes, so it already feels like hers."],[3,"Skip is always there, just as large. A five-year-old who cannot pass screen one has been locked out of her family (§8.5)."]],
 r:function(){return ctop("About you")+K.page(dots(5,1)+'<div class="center" style="min-height:0;gap:14px"><div class="big">What is your name?</div>'+K.speak("Hear it")+'<div class="rr-letters"'+K.n(2)+'><span>I</span><span>V</span><span>Y</span></div><div class="btns" style="width:100%">'+K.btn("Say it",{kind:"tonal",ic:"mic",size:"lg",n:1})+K.btn("That’s me",{ic:"check",size:"lg"})+'</div><div style="width:100%"'+K.n(3)+'>'+skipBtn()+'</div></div>');}});

D("obAge","child","First run: age",{grp:"Setup & identity",since:"0.24.0",desc:"Her age tunes what she is offered first, not a reading test. "+FIRST,
 notes:[[1,"Numbers are big tiles, not a picker wheel. Each is a 64 dp target."],[2,"It is not checked or believed. It only tunes what she sees first, and a grown-up can change it later."],[3,"Skip is a full-size button, never a small link."]],
 r:function(c){var n="",cols=c.form==="cover"?3:4;for(var i=3;i<=12;i++)n+='<div class="tile std" style="padding:16px 2px;min-height:64px;'+(i===6?"background:var(--pri);color:var(--onPri)":"")+'"><b style="font:800 28px var(--font-display);max-width:none">'+i+'</b></div>';
  return ctop("About you")+K.page(dots(5,2)+'<div class="big" style="text-align:center;padding:2px 0 8px">How old are you?</div><div class="grid4" style="grid-template-columns:repeat('+cols+',minmax(0,1fr));gap:4px"'+K.n(1)+'>'+n+'</div>'+K.banner("pri","This only changes what you see first.","info",2)+'<div'+K.n(3)+'>'+skipBtn()+'</div>');}});

D("obGender","child","First run: gender",{grp:"Setup & identity",since:"0.49.73",desc:"Boy, Girl or Skip, never a forced choice. Every real completion persists. "+FIRST,
 notes:[[1,"Three equal buttons. Skip is as large and as friendly as the other two, and nothing is preselected."],[2,"Her answer changes nothing about how the product treats her."]],
 r:function(){return ctop("About you")+K.page(dots(5,3)+'<div class="big" style="text-align:center;padding:2px 0 10px">Are you a…</div><div style="display:grid;gap:12px"'+K.n(1)+'>'+["Boy","Girl","Skip"].map(function(t){return K.btn(t,{kind:"tonal",full:true,size:"lg"});}).join("")+'</div><p style="text-align:center;color:var(--ink2);font-size:15px"'+K.n(2)+'>It’s okay to skip.</p>');}});

D("obWho","child","First run: who",{grp:"Setup & identity",since:"0.24.0",desc:"She is told who she can talk to here, in her words. "+FIRST,
 notes:[[1,"People are shown as faces with the name she uses, never a role word. "+M.NOTE_NAMES],[2,"She is told, not asked. There is no switch for her to get wrong; who she can reach is a grown-up’s decision."]],
 r:function(){return ctop("About you")+K.page(dots(5,4)+'<div class="big" style="text-align:center;padding:2px 0 8px">These are your people.</div>'+K.card(K.row({av:K.avatar("M",{size:56,tone:"accent"}),title:N.a,sub:"Calls and stories",n:1})+K.row({av:K.avatar("J",{size:56,tone:"accent"}),title:N.b,sub:"Calls and stories"})+K.row({av:K.avatar("G",{size:56}),title:"Grandma",sub:"Calls"}))+'<p class="rr-note" style="text-align:center;margin:0"'+K.n(2)+'>You can talk to all of them here.</p>'+K.btn("Next",{full:true,size:"lg"}));}});

D("invitation","guardian","Invitation",{grp:"Setup & identity",since:"0.24.0",desc:"A second guardian accepts into an existing family. Grown-up shell.",
 notes:[[1,"The invitation says exactly what the new guardian will see: the same view, nothing hidden either way."],[2,"Accept and decline are equal-weight actions at the same size. Declining costs nothing."]],
 r:function(){return K.sb()+K.page('<div style="padding-top:8px">'+K.logo(40)+'</div><div class="big" style="margin-top:4px">'+N.b+' invited you to Ivy’s family</div>'+K.card(K.row({ic:"eye",title:"You’ll see what she sees",sub:"The same calendar, messages and notes",n:1})+K.row({ic:"shield",title:"Nothing is hidden from you",sub:"And nothing is hidden from her other grown-up"})+K.row({ic:"leaf",title:"Ivy comes first",sub:"Everything here is built around her day"}))+'<div class="btns"'+K.n(2)+'>'+M.b48("Not now",{kind:"ghost"})+M.b48("Join",{})+'</div>');}});

D("addDevice","guardian","Add a device",{grp:"Setup & identity",since:"0.49.74",desc:"Role, PIN, then a real QR and 6-digit code with a live countdown (§11). Grown-up shell.",
 notes:[[1,"The role is chosen first so the code can only pair what you intend."],[2,"The code sits inside a calm countdown ring. When it ends you simply make another; nothing is wrong."],[3,"The expiry is stated in words beside the ring."]],
 r:function(){return gtop("Add Ivy’s device")+K.page(K.seg(["Ivy’s device","My device"],0,1)+K.card('<div class="center" style="min-height:0;gap:10px">'+M.ring(.7,'<span style="color:var(--ink)">'+I("qr",96,1.2)+'</span>',168)+'<b class="mono" style="font-size:30px;letter-spacing:.2em">482 917</b><span class="chip warn"'+K.n(3)+'>'+I("hourglass",13,2)+' Expires in 8 minutes</span></div>',"",2)+K.banner("info","Open Olive on Ivy’s device and scan, or type the code.","info"));}});

D("pairingRedeem","child","Connect this device",{grp:"Setup & identity",since:"0.49.74",desc:"Shown once at boot with no stored identity: scan or type. A grown-up does this with the device in hand. "+FIRST,
 notes:[[1,"The scan frame fills the screen. Typing is one tap away on the same page, not a separate flow."],[2,"Written for the grown-up holding the device: short, plain, no codes explained."]],
 r:function(){return K.sb()+K.page('<div style="position:relative;height:300px;border-radius:28px;background:#0c140f;display:grid;place-items:center;overflow:hidden"'+K.n(1)+'><div style="position:relative;width:190px;height:190px"><i class="rr-corner" style="left:0;top:0;border-right:0;border-bottom:0"></i><i class="rr-corner" style="right:0;top:0;border-left:0;border-bottom:0"></i><i class="rr-corner" style="left:0;bottom:0;border-right:0;border-top:0"></i><i class="rr-corner" style="right:0;bottom:0;border-left:0;border-top:0"></i></div><span style="position:absolute;bottom:14px;color:#fff;font-size:13.5px"'+K.n(2)+'>Point at the code on the other device</span></div>'+
  K.field("Or type the code","",{ph:"6 digits",ic:"key"})+K.btn("Connect",{full:true,size:"lg"}));}});

D("pairedDevicesList","guardian","Paired devices",{grp:"Setup & identity",since:"0.49.74",desc:"Every device paired to the family, guardian-only, with a real revoke.",
 notes:[[1,"Last seen is told in plain words. Removing a device is a clear, confirmed, single action, set apart in red."],[2,"Role is a chip on each row so a grown-up can tell her devices from theirs."]],
 r:function(){return gtop("Devices")+K.page(K.card(K.row({ic:"device",title:"Ivy’s Fold",sub:"Seen 2 minutes ago",trail:K.chip("Ivy’s",{tone:"pri",sm:true}),n:2})+K.row({ic:"tv",title:"Ivy’s tablet",sub:"Seen yesterday",trail:K.chip("Ivy’s",{tone:"pri",sm:true})})+K.row({ic:"device",title:N.a+"’s phone",sub:"This device",trail:K.chip("You",{sm:true})}))+K.btn("Add a device",{kind:"tonal",ic:"plus",full:true})+K.btn("Remove a device…",{kind:"danger",full:true,n:1}));}});

D("parentalControls","guardian","Parental controls",{grp:"Setup & identity",since:"0.49.75",desc:"PIN-gated, guardian-only: Visibility (hide any tile, game, joke, activity) and Pacing (raise, lower or reveal the age gate). One guardian-writable table.",
 notes:[[1,"Two tabs only, Visibility and Pacing."],[2,"Search and group headers so 88 rows never feel like 88 rows."],[3,"Each row names what it is and who it is for, with one switch. A hidden thing simply is not on Ivy’s screen, with no gap and no greyed tile."]],
 r:function(){return gtop("Parental controls")+K.page(K.seg(["Visibility","Pacing"],0,1)+'<div class="field"'+K.n(2)+'><span class="fv">'+I("search",18,2)+'<i class="ph">Search tiles, games, jokes</i></span></div>'+
  K.sectionLabel("Home tiles")+K.card(K.row({ic:"dice",title:"Play together",trail:K.toggle(true),n:3})+K.row({ic:"book",title:"Journal",sub:"Hers alone, on or off",trail:K.toggle(true)})+K.row({ic:"camera",title:"Show & tell",trail:K.toggle(false)}))+
  K.sectionLabel("Games · 21")+K.card(K.row({ic:"pawn",title:"Chess",sub:"From age 8",trail:K.toggle(true)})+K.row({ic:"grid3",title:"Tic-tac-toe",trail:K.toggle(true)})));}});

D("colourPick","child","Her colour",{grp:"Setup & identity",since:"0.25.0",desc:"She picks it once and the app wears it (§8.6). Twelve swatches with her own words under each; no free picker, no pure red. "+FIRST,
 notes:[[1,"Twelve fixed swatches with a plain word under each. No picker wheel, no hex, no wrong choice."],[2,"Every colour is made readable by the app, so a choice can never make anything hard to see."]],
 r:function(){return ctop("Your colour")+K.page(dots(5,5)+'<div class="grid3"'+K.n(1)+'>'+swatches().map(function(s,i){return '<div style="display:grid;gap:6px;justify-items:center"><span style="position:relative;width:100%;max-width:76px;aspect-ratio:1;border-radius:26px;background:'+s[0]+';'+(i===5?"box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink)":"box-shadow:inset 0 -4px 0 rgba(0,0,0,.14)")+';display:grid;place-items:center;color:#fff">'+(i===5?I("check",32,2.6):"")+'</span><small style="font-size:12px;color:var(--ink2);text-align:center">'+s[1]+'</small></div>';}).join("")+'</div>'+K.banner("pri","It will be your colour. It shows in a few places.","info",2));}});

D("colourDaily","child","Colour, daily",{grp:"Setup & identity",since:"0.25.0",desc:"Which do you like more today? One of the two is always her current colour, so keeping it is as easy as changing it.",
 notes:[[1,"One of the two is always her current colour, and the side is random. Keeping it costs one tap, the same as changing it."],[2,"There is no wrong answer, no “today’s change” and nothing recorded as a mood (§8.6.4)."]],
 r:function(){return K.sb()+K.page('<div class="center" style="min-height:540px"><div class="big">Which do you like more today?</div><div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;width:100%"'+K.n(1)+'><span style="aspect-ratio:1/1.2;border-radius:32px;background:#2F8FC4;display:flex;align-items:flex-end;justify-content:center;padding:14px;color:#fff;font:800 19px var(--font-display);box-shadow:0 10px 24px -10px #2F8FC4">sea blue</span><span style="aspect-ratio:1/1.2;border-radius:32px;background:#E8730C;display:flex;align-items:flex-end;justify-content:center;padding:14px;color:#fff;font:800 19px var(--font-display);box-shadow:0 10px 24px -10px #E8730C">orange</span></div><small style="color:var(--ink2);font-size:15px"'+K.n(2)+'>Tap the one you like.</small></div>');}});

D("colourParent","guardian","Colour, guardian view",{grp:"Setup & identity",since:"0.25.0",desc:"The grown-up sees her choice and cannot change it. A colour is a fact, not a mood (§8.6.4).",
 notes:[[1,"One neutral sentence. No mood, no trend, no “darker this week”."],[2,"Read-only. The guardian cannot set or override it. If you wonder how she is, ask her."]],
 r:function(){return gtop("Ivy’s colour")+K.page(K.card('<div class="row" style="padding:0"><span class="av ring" style="width:56px;height:56px;background:#2F8FC4;color:#fff;font-size:22px">I</span><span class="rtxt"><b'+K.n(1)+' style="font-size:17px">Today her colour is sea blue.</b><small>Picked at 7:41 AM</small></span></div>')+K.banner("info","You can’t change this. It’s hers. If you wonder how she is, ask her.","info",2));}});

D("bdMonth","child","Birthday: month",{grp:"Setup & identity",since:"0.26.0",desc:"She places her own birthday, month first (§8.7). Set up once with a grown-up.",
 notes:[[1,"Twelve month tiles, 64 dp each. The year is never asked; it is not hers to get wrong."]],
 r:function(){var Mo=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];return ctop("My birthday")+K.page('<div class="big" style="text-align:center;padding:2px 0 8px">Which month?</div><div class="grid3"'+K.n(1)+'>'+Mo.map(function(m,i){return '<div class="tile std" style="padding:18px 4px;min-height:64px;'+(i===8?"background:var(--pri);color:var(--onPri)":"")+'"><b style="font:800 21px var(--font-display);max-width:none">'+m+'</b></div>';}).join("")+'</div>');}});

D("bdDay","child","Birthday: day",{grp:"Setup & identity",since:"0.26.0",desc:"Then the day, laid out so she can count down the page.",
 notes:[[1,"Four across so every number is a full-size target, counted down the page. The day she picks is shown huge at the top."]],
 r:function(c){var d="",cols=c.form==="cover"?3:4;for(var i=1;i<=30;i++)d+='<span style="min-height:64px;border-radius:18px;background:'+(i===14?"var(--pri)":"var(--surface)")+';color:'+(i===14?"var(--onPri)":"var(--ink)")+';display:grid;place-items:center;font:800 24px var(--font-display);box-shadow:var(--shadow1)">'+i+'</span>';
  return ctop("September")+K.page('<div class="center" style="min-height:0;padding:0;grid-template-columns:minmax(0,1fr)"><span class="rr-big" style="font-size:64px;color:var(--pri)">14</span></div><div style="display:grid;grid-template-columns:repeat('+cols+',minmax(0,1fr));gap:4px"'+K.n(1)+'>'+d+'</div>'+K.btn("That’s it",{full:true,size:"lg"}));}});

D("bdMarked","child","Birthday: marked",{grp:"Setup & identity",since:"0.26.0",desc:"Her mark on the calendar, celebrated without a score (P2).",
 notes:[[1,"One mark and one sentence. No confetti loop, no countdown pressure, no count of days."]],
 r:function(){return ctop("My birthday",{noSpeak:true})+K.page('<div class="center"><div style="width:100%;border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("paper",300,150)+'</div><div class="big">September 14</div><p style="color:var(--ink2);font-size:16px;margin:0"'+K.n(1)+'>It’s on your calendar now.</p>'+K.btn("Done",{size:"lg",full:true})+'</div>');}});

/* ------------------------------------------------------------- homework -- */
D("homework","child","Homework",{grp:"Child",since:"0.11.0",desc:"Photograph the sheet; the quality gate refuses blur and skew before OCR runs. The sparsest surface in the product (§8.13.5).",
 notes:[[1,"The guide frame turns green only when the page is flat, sharp and lit, so the picture is right before she presses anything."],[2,"A single large shutter. Nothing else competes for attention, and nothing is scored."]],
 r:function(){return ctop("Homework",{noSpeak:true})+'<div style="flex:1;padding:6px 16px 18px;display:grid;gap:14px;align-content:start"><div style="height:352px;border-radius:28px;background:#11191a;position:relative;overflow:hidden"'+K.n(1)+'><div style="position:absolute;inset:26px;border:4px solid var(--ok);border-radius:20px"></div><span style="position:absolute;top:12px;left:50%;transform:translateX(-50%)" class="chip ok">'+I("check",12,2.4)+' Flat, sharp, bright</span></div><div style="display:grid;place-items:center"><button style="width:84px;height:84px;border-radius:50%;border:6px solid var(--pri);background:var(--surface);box-shadow:var(--shadow2)" aria-label="Take photo"'+K.n(2)+'></button></div></div>';}});

D("retake","child","Retake",{grp:"Child",since:"0.11.0",desc:"Plain, actionable advice. “Hold still and try again.” No jargon.",
 notes:[[1,"One sentence of advice in her words. No “blur score 0.42”, no percentages."],[2,"The next step is the whole screen: one big button to try again."]],
 r:function(){return ctop("Homework",{noSpeak:true})+K.page('<div style="height:230px;border-radius:28px;background:linear-gradient(135deg,#b9c1bb,#8f9a93);filter:blur(4px)"></div><div class="center" style="min-height:0"><b class="big" style="font-size:25px"'+K.n(1)+'>Hold still and try again.</b><p style="color:var(--ink2);margin:0">The picture is a little blurry.</p></div>'+K.btn("Try again",{full:true,size:"lg",ic:"camera",n:2}));}});

D("capture","child","Capture gate",{grp:"Child",since:"0.11.0",desc:"Thresholds derived from measurement, not taste.",
 notes:[[1,"The shutter waits until the three checks pass. Each check is one word and one picture, and a failing one says what to do in four words."]],
 r:function(){return ctop("Homework",{noSpeak:true})+K.page(K.card('<h4>Ready when you are</h4>'+K.row({ic:"check",title:"Sharp",tone:"ok"})+K.row({ic:"check",title:"Straight",tone:"ok"})+K.row({ic:"sun",title:"A bit dark",sub:"Move near a window",tone:"warn"}),"",1)+K.btn("Take photo",{full:true,size:"lg",ic:"camera"}));}});
})();
