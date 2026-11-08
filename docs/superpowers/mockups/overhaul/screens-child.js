/* Child surfaces, first run, setup and identity. Sample data: Ivy (6), Dad, Mom. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc,D=K.def;
function ctop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:o.ns})});}
function gtop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function swatches(sel){var P=[["#F2B705","sunny yellow"],["#E8730C","orange"],["#F0757E","coral pink"],["#E056A8","bright pink"],["#8B6BB1","purple"],["#2F8FC4","sea blue"],["#6BB8E8","sky blue"],["#5FC9A8","mint"],["#5AA84A","grass green"],["#8A6244","chocolate"],["#7C8698","storm grey"],["#2B3358","midnight"]];return P;}

/* ----------------------------------------------------------- child home -- */
D("childHome","child","Her home",{grp:"Child",since:"0.8.0",
 desc:"Name, the dual clock, sleeps-countdown. No settings affordance at any depth. Three tiers: Hero (My day), Featured (Play together, Messages, Storyteller, Show & tell), Standard (the rest). At the Fold5 cover (344 px) only the presence card and the Hero tile show, with the rest behind one More tile.",
 notes:[[1,"The dual clock: her time is large, his is the quiet aside. A ribbon and the sleeps count live in the same card, so the whole picture is one glance."],[2,"Hero tile gets an illustration and a frosted caption. It is the one thing that is bigger than everything else."],[3,"Featured tiles: icon, one word, optional badge. Four, no more."],[4,"Standard tiles: a quiet grid. Nothing here moves or pulses (§8.13: nothing animates to attract her)."]],
 r:function(c){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})})+
 K.page(
  K.card(K.dual({n:1})+'<div style="height:14px"></div>'+K.ribbon({now:31,overlap:[40,10]})+'<div class="chips" style="margin-top:10px"><span class="chip" style="background:rgba(255,255,255,.18);color:inherit">'+I("moon",13,2)+' 3 sleeps until Dad’s house</span></div>',"hero")+
  K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Grandma’s",scene:"hills",n:2})+
  '<div class="grid2">'+K.tile("feat",{ic:"dice",title:"Play together",n:3})+K.tile("feat",{ic:"chat",title:"Messages",badge:"2"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"camera",title:"Show & tell"})+'</div>'+
  K.sectionLabel("More")+'<div class="grid3"'+K.n(4)+'>'+[["pencil","Homework"],["list","Wants"],["book","Journal"],["calendar","Weeks"],["palette","Colour"],["image","Photos"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>');},
 cover:function(){return K.sb()+K.top({logo:true,title:"Hi, Ivy"})+K.page(K.card(K.dual({t1:"7:42",t2:"1:42",l1:"Ivy",l2:"Dad",s1:"",s2:""}),"hero")+K.tile("hero",{ic:"calendar",title:"My day",sub:"",scene:"hills"})+K.tile("feat",{ic:"grid",title:"More",sub:"Everything else"}));}});

D("inbox","child","Inbox",{grp:"Child",since:"0.8.0",desc:"Async messages materialised by the delivery engine; receipts render in her frame. Tap to open a full-screen receipt; no persistent detail pane on tablet.",
 notes:[[1,"Messages are grouped by who, with a person filter she can read by picture."],[2,"Every message states when it reached her in her words: “before school”, “at bedtime”."],[3,"Unread is a quiet dot, never a number that grows."]],
 r:function(){return ctop("Messages",{ns:1})+K.page(
  K.seg(["Everyone","Dad","Mom","Grandma"],0,1)+
  K.card('<div style="height:92px;margin:-2px -2px 10px;border-radius:18px;overflow:hidden">'+K.scene("night",300,92)+'</div><div class="row" style="padding:0"><span class="rtxt"><b>Dad’s goodnight story</b><small'+K.n(2)+'>Waiting for you at bedtime</small></span><span class="chip pri">'+I("play",12,2)+' 2 min</span></div>',"")+
  K.card(K.row({av:K.avatar("D",{size:42,tone:"accent"}),title:"Dad",sub:"Watched at 7:04 AM, before school",trail:'<i style="width:9px;height:9px;border-radius:50%;background:var(--pri)"></i>',n:3})+K.row({av:K.avatar("G",{size:42}),title:"Grandma",sub:"A picture of the garden",go:true})+K.row({av:K.avatar("M",{size:42,tone:"accent"}),title:"Mom",sub:"See you at pickup",go:true}))+
  K.card(K.row({ic:"letter",title:"A letter from Dad",sub:"Sealed. Opens Saturday",trail:K.chip("3 sleeps",{tone:"pri",sm:true})}),"tint"));}});

D("receipt","child","Receipt",{grp:"Child",since:"0.49.49",desc:"“Watched at 7:04 AM her time, before school.” Her frame first, always. Live-wired with real baseUrl, childId and sessionToken.",
 notes:[[1,"The receipt is told in her frame: her clock, her day-part. His time is never the headline."],[2,"Replies are three big buttons. A heart is enough."],[3,"The journey of the message is shown as a short line of three steps."]],
 r:function(){return ctop("From Dad",{ns:1})+K.page(
  '<div style="position:relative;border-radius:26px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("night",300,170)+'<span style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:64px;height:64px;border-radius:50%;background:rgba(255,255,255,.92);display:grid;place-items:center;color:var(--priD)">'+I("play",28,2)+'</span></span></div>'+
  K.card('<p style="font:800 19px/1.2 var(--font-display);margin:0;color:var(--ink)"'+K.n(1)+'>Watched at 7:04 AM, before school</p><div style="height:10px"></div>'+K.progress(100,"ok")+'<div class="kv" style="margin-top:10px"><span>Recorded</span><span>Last Tuesday</span><span>Arrived</span><span>Your bedtime</span><span>Watched</span><span>This morning</span></div>')+
  '<div class="grid3"'+K.n(2)+'>'+[["heart","Love it"],["mic","Say hi"],["camera","Show Dad"]].map(function(b){return '<div class="tile std" style="padding:14px 6px"><span class="tic" style="width:48px;height:48px">'+I(b[0],24,1.9)+'</span><b>'+b[1]+'</b></div>';}).join("")+'</div>');}});

D("pin","child","PIN gate",{grp:"Child",since:"0.8.0",desc:"Nine shuffled keys, because the child is watching. No error text after a kiosk defeat. Reached by a real kiosk defeat, not only a dev button.",
 notes:[[1,"Keys are shuffled every time so a watching child cannot learn the pattern."],[2,"A wrong PIN just clears. No red, no message, no lockout theatre."]],
 r:function(){return K.sb()+K.page('<div class="center" style="min-height:520px"><span class="ricon" style="width:64px;height:64px;border-radius:22px">'+I("lock",28,1.8)+'</span><b style="font:800 24px var(--font-display)">Grown-ups only</b><small style="color:var(--ink3)">Ask a grown-up to open this.</small>'+K.dots(4,2)+'<div class="kp"'+K.n(1)+'>'+[7,3,9,1,5,8,2,6,4].map(function(n){return '<button>'+n+'</button>';}).join("")+'</div></div>');}});

D("list","child","Wants & needs",{grp:"Child",since:"0.8.0",wide:true,desc:"Two lists, structurally separate. No price field, no buy button (P4). A real two-pane split on tablet and desktop widths.",
 notes:[[1,"Needs and wants are separate lists with separate headings. They never mix."],[2,"There is no price, no link and no buy affordance anywhere (P4)."]],
 r:function(c){var needs=K.card(K.sectionLabel("Things I need")+K.row({ic:"book",title:"A new library card",n:1})+K.row({ic:"pencil",title:"Pencils for school"})+K.row({ic:"smile",title:"Rain boots"}));
  var wants=K.card(K.sectionLabel("Things I want")+K.row({ic:"puzzle",title:"A 500-piece puzzle",n:2})+K.row({ic:"palette",title:"Watercolours"})+K.row({ic:"dice",title:"Checkers"}));
  if(c.form==="tablet")return ctop("My lists",{noSpeak:true})+'<div class="tw"><div>'+needs+'</div><div>'+wants+'</div></div>';
  return ctop("My lists",{noSpeak:true})+K.page(K.seg(["Needs","Wants"],0)+needs+wants+K.btn("Add one",{kind:"tonal",ic:"plus",full:true}));}});

D("myday","child","My day",{grp:"Child",since:"0.13.0",desc:"The day ribbon, coloured by day-part (§8.2).",
 notes:[[1,"The ribbon is the semantic surface: day-part colours are protected and never take her colour (§8.6.2)."],[2,"The green band means “you can both talk right now”."],[3,"Each part of the day reads as a sentence with an icon."]],
 r:function(){return ctop("My day",{ns:1})+K.page(
  K.card('<h4>Saturday</h4>'+K.ribbon({now:31,overlap:[40,10],n:1})+'<div class="chips" style="margin-top:10px"><span class="chip ok">'+I("phone",13,2)+' You can both talk 9–11 AM</span></div>')+
  K.card(K.row({ic:"sun",title:"Wake up",sub:"7:00",tone:"warn"})+K.row({ic:"book",title:"School",sub:"8:30 to 3:00",tone:"info"})+K.row({ic:"heart",title:"Grandma’s",sub:"After school",tone:"ok"})+K.row({ic:"smile",title:"Dinner",sub:"6:00"})+K.row({ic:"moon",title:"Bedtime story",sub:"7:30"}))+
  K.btn("Call Dad",{ic:"video",full:true,size:"lg",n:2}));}});

D("weeks","child","Weeks",{grp:"Child",since:"0.13.0",desc:"Custody rhythm as she experiences it; countdowns in sleeps. A rhythm visualisation, not list and detail.",
 notes:[[1,"Two houses, two colours, one calendar. No percentages, no “custody split”."],[2,"Today is ringed. Nothing else on the page asks for her attention."]],
 r:function(){var cells="",d=0;for(var w=0;w<4;w++){for(var i=0;i<7;i++){var dad=(w===1||w===3)?true:(w===0&&i>4)||(w===2&&i>4);d++;cells+='<span style="aspect-ratio:1;border-radius:50%;background:'+(dad?"var(--accent)":"var(--pri)")+';opacity:'+(d<4?.35:1)+';'+(d===6?"box-shadow:0 0 0 3px var(--bg),0 0 0 5px var(--ink)":"")+'"></span>';}}
  return ctop("My weeks",{ns:1})+K.page(K.card('<div class="chips" style="margin-bottom:10px"><span class="chip pri"><i style="width:8px;height:8px;border-radius:50%;background:var(--pri)"></i> Mom’s house</span><span class="chip" style="background:var(--accentC);color:var(--ink)"><i style="width:8px;height:8px;border-radius:50%;background:var(--accent)"></i> Dad’s house</span></div><div style="display:grid;grid-template-columns:repeat(7,1fr);gap:8px"'+K.n(1)+'>'+cells+'</div>')+
  K.card('<div class="center" style="min-height:0;padding:4px"><span class="big" style="color:var(--pri)">3</span><b>sleeps until Dad’s house</b></div>',"tint"));}});

D("journal","child","Journal",{grp:"Child",since:"0.8.0",desc:"Hers alone. No parent path exists at any tier (P7). A permanently still surface (§8.13.5).",
 notes:[[1,"The page is deliberately plain and still. Nothing moves while she thinks."],[2,"One reassurance, once, in her words: nobody else can read this."]],
 r:function(){return ctop("My journal",{noSpeak:true})+K.page(K.banner("pri","Only you can read this. Not Mom, not Dad, not anyone.","lock",2)+
  K.card('<small class="mono" style="color:var(--ink3)">SATURDAY</small><p style="font:700 18px/1.5 var(--font-body);color:var(--ink);margin:8px 0">Today I saw a heron at the pond. It stood so still that I held my breath.</p><div style="height:90px;border-top:1px dashed var(--outline);margin-top:14px"></div>','',1)+
  '<div class="btns">'+K.btn("Draw",{kind:"tonal",ic:"brush"})+K.btn("Say it",{kind:"tonal",ic:"mic"})+'</div>');}});

D("lockAdvisory","guardian","Kiosk advisory",{grp:"Setup & identity",since:"0.11.0",desc:"Native setup flow; advises the guardian on platform kiosk state (§8.3).",
 notes:[[1,"Plain status per check. Each failing line says exactly what to do next."],[2,"One primary action. The product uses the OS lock; it never builds its own."]],
 r:function(){return gtop("Lock Ivy’s device")+K.page(K.banner("warn","Screen pinning is off. Ivy could leave the app.","warn",1)+
  K.card(K.row({ic:"shieldcheck",title:"App is her device’s only app",sub:"Checked just now",tone:"ok"})+K.row({ic:"lock",title:"Screen pinning",sub:"Turn on in Settings, Security",tone:"warn"})+K.row({ic:"bell",title:"Notifications hidden on lock",sub:"Off for everything but Olive",tone:"ok"}))+
  K.btn("Open Android settings",{full:true,n:2,ic:"sliders"})+K.btn("I’ll do this later",{kind:"ghost",full:true}));}});

/* --------------------------------------------------------- first run, id -- */
D("welcome","child","Welcome",{grp:"Setup & identity",since:"0.24.0",desc:"A role question, not an age gate. “Grown-up” grants nothing by itself; every capability passes through the real family-graph authoriser.",
 notes:[[1,"Two equal cards. The product never asks a child to prove she is one."],[2,"A tiny logo and one line of warmth. No legal wall on the first screen."]],
 r:function(){return K.sb()+K.page('<div style="display:grid;gap:14px;padding-top:12px">'+K.logo(46)+'<div class="big" style="margin-top:8px">Hello.<br>Which side are you?</div></div>'+
  '<div class="card" style="padding:0;overflow:hidden"'+K.n(1)+'>'+K.scene("paper",300,100)+'<div style="padding:12px 14px"><b style="font:800 20px var(--font-display)">I’m a kid</b><p>Play, talk and see your day.</p></div></div>'+
  '<div class="card" style="padding:0;overflow:hidden">'+K.scene("branch",300,100)+'<div style="padding:12px 14px"><b style="font:800 20px var(--font-display)">I’m a grown-up</b><p>Set things up and stay close.</p></div></div>');}});

D("guardianSetup","guardian","Grown-up account setup",{grp:"Setup & identity",since:"0.49.30",desc:"Passkey/WebAuthn sign-in and real consent continue here. Kiosk PIN setup is real, wired to the already-real route.",
 notes:[[1,"Passkey first. There is no password field anywhere."],[2,"Consent is read in plain words, one short paragraph per item."],[3,"The kiosk PIN is set last, with four dots and a numeric pad."]],
 r:function(){return gtop("Set up your account",{eyebrow:"Step 2 of 3"})+K.page(K.progress(66)+
  K.card(K.row({ic:"key",title:"Create a passkey",sub:"Use your face, finger or screen lock",trail:K.chip("Ready",{tone:"ok",sm:true}),n:1})+K.row({ic:"shieldcheck",title:"What we store",sub:"Names, schedules, messages you send",go:true,n:2})+K.row({ic:"users",title:"Who can see what",sub:"You and the other guardian, the same view",go:true}))+
  K.card('<h4>Her PIN</h4><p>Four digits only a grown-up knows.</p>'+K.dots(4,0),"",3)+K.btn("Continue",{full:true,size:"lg"}));}});

D("obName","child","First run: name",{grp:"Setup & identity",since:"0.24.0",desc:"She types or says her name; it is hers from the first screen.",
 notes:[[1,"The question is spoken and written. The microphone is as large as the keyboard."],[2,"Her name appears large as she types, so it already feels like hers."]],
 r:function(){return ctop("About you",{eyebrow:"1 of 5"})+K.page('<div class="center"><div class="big">What is your name?</div>'+K.speak("Hear it")+'<div class="card" style="width:100%;text-align:center"'+K.n(2)+'><span class="big" style="color:var(--pri)">Ivy</span></div><div class="btns" style="width:100%">'+K.btn("Say it",{kind:"tonal",ic:"mic",size:"lg",n:1})+K.btn("That’s me",{ic:"check",size:"lg"})+'</div></div>');}});

D("obAge","child","First run: age",{grp:"Setup & identity",since:"0.24.0",desc:"Age sets the capability rungs, not a reading test.",
 notes:[[1,"Numbers are big picture-friendly tiles, not a picker wheel."],[2,"It is not believed or checked. It tunes what she is offered."]],
 r:function(){var n="";for(var i=3;i<=12;i++)n+='<div class="tile std" style="padding:16px 4px;'+(i===6?"background:var(--pri);color:var(--onPri)":"")+'"><b style="font:800 26px var(--font-display)">'+i+'</b></div>';
  return ctop("About you",{eyebrow:"2 of 5"})+K.page('<div class="big" style="text-align:center;padding:6px 0 10px">How old are you?</div><div class="grid4" style="grid-template-columns:repeat(4,1fr)"'+K.n(1)+'>'+n+'</div>'+K.banner("pri","This only changes what you see first.","info",2)+K.btn("Next",{full:true,size:"lg"}));}});

D("obGender","child","First run: gender",{grp:"Setup & identity",since:"0.49.73",desc:"Boy / Girl / Skip, never a forced choice. Every real completion persists.",
 notes:[[1,"Skip is as large and as friendly as the other two."],[2,"It changes nothing about how the product treats her."]],
 r:function(){return ctop("About you",{eyebrow:"3 of 5"})+K.page('<div class="big" style="text-align:center;padding:6px 0 10px">Are you a…</div><div style="display:grid;gap:10px"'+K.n(1)+'>'+["Boy","Girl","Skip"].map(function(t,i){return K.btn(t,{kind:i===1?"pri":"tonal",full:true,size:"lg"});}).join("")+'</div><p style="text-align:center;color:var(--ink3)"'+K.n(2)+'>It’s okay to skip.</p>');}});

D("obWho","child","First run: who",{grp:"Setup & identity",since:"0.24.0",desc:"Who she talks to here, in her words.",
 notes:[[1,"People are shown as faces and the name she uses (“Dad”, “Nana”), never a role."]],
 r:function(){return ctop("About you",{eyebrow:"4 of 5"})+K.page('<div class="big" style="text-align:center;padding:6px 0 10px">Who do you talk to?</div>'+K.card(K.row({av:K.avatar("D",{size:50,tone:"accent"}),title:"Dad",sub:"Calls and stories",trail:K.toggle(true),n:1})+K.row({av:K.avatar("M",{size:50,tone:"accent"}),title:"Mom",sub:"Calls and stories",trail:K.toggle(true)})+K.row({av:K.avatar("N",{size:50}),title:"Nana",sub:"Calls",trail:K.toggle(true)}))+K.btn("Next",{full:true,size:"lg"}));}});

D("invitation","guardian","Invitation",{grp:"Setup & identity",since:"0.24.0",desc:"A second guardian accepts into an existing family.",
 notes:[[1,"The invitation says exactly what the new guardian will see: the same view, nothing hidden."],[2,"Accept and decline are equal-weight actions."]],
 r:function(){return K.sb()+K.page('<div style="padding-top:8px">'+K.logo(38)+'</div><div class="big" style="margin-top:4px">Mom invited you to Ivy’s family</div>'+K.card(K.row({ic:"eye",title:"You’ll see what she sees",sub:"The same view of the calendar, messages and notes",n:1})+K.row({ic:"shield",title:"Nothing is hidden from you",sub:"And nothing is hidden from her",go:false})+K.row({ic:"leaf",title:"Ivy comes first",sub:"Everything here is built around her day"}))+'<div class="btns">'+K.btn("Not now",{kind:"ghost",n:2})+K.btn("Join",{})+'</div>');}});

D("addDevice","guardian","Add a device",{grp:"Setup & identity",since:"0.49.74",desc:"Role, PIN, then a real QR and 6-digit code with a live countdown (§11).",
 notes:[[1,"Role is chosen first so the code can only pair what you intend."],[2,"The code shows a calm countdown ring. When it ends you simply make another."]],
 r:function(){return gtop("Add Ivy’s device")+K.page(K.seg(["Child device","My device"],0,1)+K.card('<div class="center" style="min-height:0"><div style="width:150px;height:150px;border-radius:20px;background:var(--surface2);display:grid;place-items:center;color:var(--ink)">'+I("qr",110,1.2)+'</div><b class="mono" style="font-size:30px;letter-spacing:.2em">482 917</b><span class="chip warn">'+I("hourglass",13,2)+' Expires in 8:42</span></div>',"",2)+K.banner("info","Open Olive on Ivy’s device and scan, or type the code.","info"));}});

D("pairingRedeem","child","Connect this device",{grp:"Setup & identity",since:"0.49.74",desc:"Shown at boot with no stored identity and no dart-define: scan or type.",
 notes:[[1,"A scan frame fills the screen. Typing the code is one tap away, not a separate flow."]],
 r:function(){return K.sb()+K.page('<div style="position:relative;height:300px;border-radius:26px;background:#0c140f;display:grid;place-items:center;overflow:hidden"'+K.n(1)+'><div style="width:190px;height:190px;border:3px solid #fff;border-radius:26px;opacity:.9"></div><span style="position:absolute;bottom:14px;color:#fff;font-size:13px">Point at the code on the other device</span></div>'+
  K.field("Or type the code","",{ph:"6 digits",ic:"key"})+K.btn("Connect",{full:true,size:"lg"}));}});

D("pairedDevicesList","guardian","Paired devices",{grp:"Setup & identity",since:"0.49.74",desc:"Every device paired to the family, guardian-only, with a real revoke.",
 notes:[[1,"Last seen is given in plain words. Revoke is a clear, confirmed, single action."]],
 r:function(){return gtop("Devices")+K.page(K.card(K.row({ic:"device",title:"Ivy’s Fold",sub:"Child · seen 2 minutes ago",trail:K.chip("Ivy’s",{tone:"pri",sm:true})})+K.row({ic:"tv",title:"Ivy’s tablet",sub:"Child · seen yesterday"})+K.row({ic:"device",title:"Dad’s phone",sub:"Guardian · this device",trail:K.chip("You",{sm:true})}))+K.btn("Remove a device…",{kind:"danger",full:true,n:1})+K.btn("Add a device",{kind:"tonal",ic:"plus",full:true}));}});

D("parentalControls","guardian","Parental controls",{grp:"Setup & identity",since:"0.49.75",desc:"PIN-gated, guardian-only: Visibility (hide any tile, game, joke, activity) and Pacing (raise, lower or reveal the age gate). One guardian-writable table.",
 notes:[[1,"Two tabs only, Visibility and Pacing."],[2,"Search and group headers so 88 rows never feel like 88 rows."],[3,"Each row names what it is and who it is for, with one switch."]],
 r:function(){return gtop("Parental controls")+K.page(K.seg(["Visibility","Pacing"],0,1)+'<div class="field"'+K.n(2)+'><span class="fv">'+I("search",18,2)+'<i class="ph">Search tiles, games, jokes</i></span></div>'+
  K.sectionLabel("Home tiles")+K.card(K.row({ic:"dice",title:"Play together",trail:K.toggle(true),n:3})+K.row({ic:"book",title:"Journal",trail:K.toggle(true)})+K.row({ic:"camera",title:"Show & tell",trail:K.toggle(false)}))+
  K.sectionLabel("Games · 21")+K.card(K.row({ic:"pawn",title:"Chess",sub:"From age 8",trail:K.toggle(true)})+K.row({ic:"grid3",title:"Tic-tac-toe",trail:K.toggle(true)})));}});

D("colourPick","child","Her colour",{grp:"Setup & identity",since:"0.25.0",desc:"She picks it once; the app wears it (§8.6). Twelve swatches in her words, no free picker, no pure red.",
 notes:[[1,"Twelve fixed swatches with her own words under each. No picker wheel."],[2,"Every colour is made readable by the app, so no choice is ever wrong."]],
 r:function(){return ctop("Your colour",{eyebrow:"5 of 5"})+K.page('<div class="grid3"'+K.n(1)+'>'+swatches().map(function(s,i){return '<div style="display:grid;gap:6px;justify-items:center"><span style="width:72px;height:72px;border-radius:24px;background:'+s[0]+';'+(i===5?"box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink)":"box-shadow:inset 0 -4px 0 rgba(0,0,0,.14)")+'"></span><small style="font-size:11.5px;color:var(--ink2);text-align:center">'+s[1]+'</small></div>';}).join("")+'</div>'+K.banner("pri","It will be your colour. It only shows up in a few places.","info",2));}});

D("colourDaily","child","Colour, daily",{grp:"Setup & identity",since:"0.25.0",desc:"Which do you like more today? One of the two is always her current colour, so keeping it is as easy as changing it.",
 notes:[[1,"One of the two is always her current colour, and the side is random."],[2,"There is no wrong answer and no “today’s change” score."]],
 r:function(){return K.sb()+K.page('<div class="center" style="min-height:540px"><div class="big">Which do you like more today?</div><div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;width:100%"'+K.n(1)+'><span style="aspect-ratio:1/1.2;border-radius:30px;background:#2F8FC4;display:flex;align-items:flex-end;justify-content:center;padding:14px;color:#fff;font:800 18px var(--font-display);box-shadow:inset 0 0 0 4px rgba(255,255,255,.35)">sea blue</span><span style="aspect-ratio:1/1.2;border-radius:30px;background:#E8730C;display:flex;align-items:flex-end;justify-content:center;padding:14px;color:#fff;font:800 18px var(--font-display)">orange</span></div><small style="color:var(--ink3)"'+K.n(2)+'>Tap the one you like.</small></div>');}});

D("colourParent","guardian","Colour, guardian view",{grp:"Setup & identity",since:"0.25.0",desc:"The guardian sees her choice, and cannot change it. A colour is a fact, not a mood (§8.6.4).",
 notes:[[1,"One neutral sentence. No mood, no trend, no “darker this week”."],[2,"Read-only. The guardian cannot set or override it."]],
 r:function(){return gtop("Ivy’s colour")+K.page(K.card('<div class="row" style="padding:0"><span class="av ring" style="width:54px;height:54px;background:#2F8FC4;color:#fff;font-size:22px">I</span><span class="rtxt"><b'+K.n(1)+' style="font-size:17px">Today her colour is sea blue.</b><small>Picked at 7:41 AM</small></span></div>')+K.banner("info","You can’t change this. It’s hers. If you wonder how she is, ask her.","info",2));}});

D("bdMonth","child","Birthday: month",{grp:"Setup & identity",since:"0.26.0",desc:"She places her own birthday: month first (§8.7).",
 notes:[[1,"Twelve month tiles. The year is never asked; it is not hers to get wrong."]],
 r:function(){var M=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];return ctop("My birthday")+K.page('<div class="big" style="text-align:center;padding:6px 0 10px">Which month?</div><div class="grid3"'+K.n(1)+'>'+M.map(function(m,i){return '<div class="tile std" style="padding:18px 4px;'+(i===8?"background:var(--pri);color:var(--onPri)":"")+'"><b style="font:800 20px var(--font-display)">'+m+'</b></div>';}).join("")+'</div>');}});

D("bdDay","child","Birthday: day",{grp:"Setup & identity",since:"0.26.0",desc:"Then the day, on a grid she can count.",
 notes:[[1,"A calendar grid she can count along. Week rows are visible, which is how she finds the 14th."]],
 r:function(){var d="";for(var i=1;i<=30;i++)d+='<span style="aspect-ratio:1;border-radius:12px;background:'+(i===14?"var(--pri)":"var(--surface)")+';color:'+(i===14?"var(--onPri)":"var(--ink)")+';display:grid;place-items:center;font:800 15px var(--font-display);box-shadow:var(--shadow1)">'+i+'</span>';return ctop("September")+K.page('<div class="big" style="text-align:center;padding:4px 0 8px">Which day?</div><div style="display:grid;grid-template-columns:repeat(7,1fr);gap:6px"'+K.n(1)+'>'+d+'</div>'+K.btn("That’s it",{full:true,size:"lg"}));}});

D("bdMarked","child","Birthday: marked",{grp:"Setup & identity",since:"0.26.0",desc:"Her mark on the calendar, celebrated without a score (P2).",
 notes:[[1,"A single mark, a single sentence. No confetti loop, no countdown pressure."]],
 r:function(){return ctop("My birthday",{noSpeak:true})+K.page('<div class="center"><div style="width:100%;border-radius:26px;overflow:hidden">'+K.scene("paper",300,150)+'</div><div class="big">September 14</div><p style="color:var(--ink2)"'+K.n(1)+'>It’s on your calendar now.</p>'+K.btn("Done",{size:"lg"})+'</div>');}});

D("homework","child","Homework",{grp:"Child",since:"0.11.0",desc:"Photograph the sheet; the quality gate refuses blur and skew before OCR runs. The sparsest surface in the product (§8.13.5).",
 notes:[[1,"The guide frame turns green only when the page is flat, sharp and lit."],[2,"A single large shutter. Nothing else competes for attention."]],
 r:function(){return ctop("Homework",{noSpeak:true})+'<div style="flex:1;padding:6px 16px 18px;display:grid;gap:12px;align-content:start"><div style="height:360px;border-radius:26px;background:#11191a;position:relative;overflow:hidden"'+K.n(1)+'><div style="position:absolute;inset:22px;border:3px solid var(--ok);border-radius:18px"></div><span style="position:absolute;top:14px;left:50%;transform:translateX(-50%)" class="chip ok">'+I("check",12,2.4)+' Flat, sharp, bright</span></div><div style="display:grid;place-items:center"><button style="width:76px;height:76px;border-radius:50%;border:5px solid var(--pri);background:var(--surface);box-shadow:var(--shadow2)" aria-label="Take photo"'+K.n(2)+'></button></div></div>';}});

D("retake","child","Retake",{grp:"Child",since:"0.11.0",desc:"Plain, actionable advice. “Hold still and try again.” No jargon.",
 notes:[[1,"One sentence of advice in her words. No “blur score 0.42”."]],
 r:function(){return ctop("Homework",{noSpeak:true})+K.page('<div style="height:230px;border-radius:26px;background:linear-gradient(135deg,#b9c1bb,#8f9a93);filter:blur(4px)"></div><div class="center" style="min-height:0"><b class="big" style="font-size:24px"'+K.n(1)+'>Hold still and try again.</b><p style="color:var(--ink2)">The picture is a little blurry.</p></div>'+K.btn("Try again",{full:true,size:"lg",ic:"camera"}));}});

D("capture","child","Capture gate",{grp:"Child",since:"0.11.0",desc:"Thresholds derived from measurement, not taste.",
 notes:[[1,"The shutter stays quiet until the three checks pass. Each check is one word."]],
 r:function(){return ctop("Homework",{noSpeak:true})+K.page(K.card('<h4>Ready when you are</h4>'+K.row({ic:"check",title:"Sharp",tone:"ok"})+K.row({ic:"check",title:"Straight",tone:"ok"})+K.row({ic:"sun",title:"A bit dark",sub:"Move near a window",tone:"warn"}),"",1)+K.btn("Take photo",{full:true,size:"lg",ic:"camera"}));}});
})();
