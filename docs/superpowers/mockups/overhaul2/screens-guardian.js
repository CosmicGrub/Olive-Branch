/* Guardian surfaces. ROUND 2. The shell is calmer and denser than the child's, and never makes a grown-up do maths.
   Sample world: Marcus is signed in (Ivy’s dad, in another time zone, six hours behind her). Jess is the other guardian. Ivy is 6.
   These are the real, live features: emergency card, meds, handover, exchange, expenses. There are no demo tiles anywhere here. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc,D=K.def,M=K.mk,N=M.N,gtop=M.gtop,two=M.two,sk=M.sk,B=M.b48;
M.css("r2-g",
".ob .rg-cb{width:28px;height:28px;border-radius:9px;border:2px solid var(--outline);display:grid;place-items:center;flex:none;color:#fff}.ob .rg-cb.on{background:var(--ok);border-color:var(--ok)}"+
".ob .rg-rad{width:26px;height:26px;border-radius:50%;border:2px solid var(--outline);display:grid;place-items:center;flex:none}.ob .rg-rad.on{border-color:var(--pri)}.ob .rg-rad.on:after{content:\"\";width:14px;height:14px;border-radius:50%;background:var(--pri)}"+
".ob .rg-opt{display:flex;gap:12px;align-items:flex-start}.ob .rg-opt .rtxt{flex:1}.ob .rg-opt .rtxt b{font:800 16px/1.2 var(--font-display)}"+
".ob .rg-big{font:800 24px/1.15 var(--font-display);margin:4px 0;color:var(--ink)}"+
".ob .rg-ghostw{background:rgba(255,255,255,.18);color:#fff;box-shadow:none}"+
".ob .rg-dis{opacity:1;background:var(--surface3);color:var(--ink2);box-shadow:none}"+
".ob .rg-rec{width:92px;height:92px;border-radius:50%;border:0;background:var(--bad);color:#fff;box-shadow:0 10px 24px -8px var(--bad),0 0 0 8px var(--badC);display:grid;place-items:center}"+
".ob .rg-wave{display:flex;gap:3px;align-items:center;height:28px}.ob .rg-wave i{width:4px;border-radius:3px;background:var(--ink3);opacity:.5}"+
".ob .rg-ph{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}"+
".ob .rg-row2{display:flex;align-items:center;gap:10px}"+
".ob .rg-sw{width:100%;display:grid;grid-template-columns:repeat(3,1fr);gap:4px}.ob .rg-sw i{height:34px;border-radius:10px}");
function tabsN(a,n,last){var h=M.tabs(a,last);return n?h.replace('class="tabbar rr-tb"','class="tabbar rr-tb"'+K.n(n)):h;}
function cb(on){return '<span class="rg-cb'+(on?" on":"")+'">'+(on?I("check",16,3):"")+'</span>';}
function rad(on){return '<span class="rg-rad'+(on?" on":"")+'"></span>';}
function opt(ic,title,sub,on,tone,n){return K.card('<div class="rg-opt"'+K.n(n)+'>'+rad(on)+'<span class="rtxt"><b>'+title+'</b><small style="font-size:13px;color:var(--ink2)">'+sub+'</small></span><span class="ricon">'+I(ic,20,1.9)+'</span></div>',on?"tint":"");}
function offBanner(txt,n){return K.banner("warn",txt,"wifi",n);}
function errBanner(txt,n){return K.banner("bad",txt,"warn",n);}

/* ------------------------------------------------------- guardian home -- */
function gHomeBody(mode){
 var off=mode==="offline",load=mode==="loading";
 var tiles=[["swap","Exchange"],["list","Handover"],["receipt","Expenses"],["letter","Letters"],["camera","Show me"],["image","Gallery"],["book","Year book"],["sliders","Settings"]];
 if(load)return '<div class="card hero" style="padding:16px"'+K.n(1)+'><div style="display:grid;gap:10px">'+sk("92%",20,8,"on")+sk("64%",20,8,"on")+'</div><div style="height:18px"></div><div style="display:grid;grid-template-columns:1.5fr 1fr;gap:12px;align-items:end"><div style="display:grid;gap:8px">'+sk("44%",10,5,"on")+sk("70%",34,10,"on")+sk("40%",12,6,"on")+'</div><div style="display:grid;gap:8px">'+sk("50%",10,5,"on")+sk("60%",18,8,"on")+'</div></div><div style="height:14px"></div>'+sk("100%",22,12,"on")+'<div style="height:12px"></div>'+sk("100%",48,16,"on")+'</div>'+sk("100%",138,26)+'<div class="grid2">'+[0,1,2,3].map(function(){return sk("100%",84,21);}).join("")+'</div>'+K.sectionLabel("More")+'<div class="grid4">'+tiles.map(function(){return sk("100%",78,19);}).join("")+'</div>';
 var call=off?'<button class="btn full rg-dis"'+K.n(7)+' style="min-height:52px">'+I("wifi",18,2)+' Calling needs a connection</button>':'<button class="btn full rg-ghostw rr-t48" style="min-height:52px">'+I("video",18,2)+' Call Ivy at 3:00 PM</button>';
 return (off?offBanner("You’re offline. This is what was saved at 7:12 AM. Anything you do now is kept and sent when you’re back.",5)+'':"")+
  K.card('<p style="font:800 19px/1.25 var(--font-display);margin:0 0 12px;color:inherit"'+K.n(1)+'>Ivy is getting ready for school. She can talk at 3:00 PM her time.</p>'+K.dual({n:2,l1:"Ivy, her time",t1:"7:42 AM",s1:"Before school",l2:"You, your time",t2:"1:42 AM",s2:"Night"})+'<div style="height:14px"></div>'+M.rib({now:32})+'<div style="height:12px"></div>'+call,"hero")+
  (off?K.card(K.row({ic:"clock",title:"1 message waiting to send",sub:"Goodnight, owl · will go when you’re online",trail:K.chip("Queued",{tone:"warn",sm:true}),n:6}),""):"")+
  K.tile("hero",{ic:"mic",title:"Message banking",sub:"42 nights banked",scene:"night",n:4})+
  '<div class="grid2">'+K.tile("feat",{ic:"clock",title:"Availability"})+K.tile("feat",{ic:"send",title:"Send timing"})+K.tile("feat",{ic:"pill",title:"Meds & care"})+K.tile("feat",{ic:"shield",title:"Emergency"})+'</div>'+
  K.sectionLabel("More")+'<div class="grid4">'+tiles.map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>';
}
function gHomeTop(){return K.sb()+K.top({logo:true,eyebrow:"Good evening",title:"Hi, Marcus",right:K.avatar("M",{size:44})});}
D("guardianHome","guardian","Guardian home",{grp:"Guardian",since:"0.8.0",
 desc:"Her state as a sentence about her, the child’s time dominant and the grown-up’s subordinate. Three tiers: Hero (Message banking), Featured (Availability, Send timing, Meds & care, Emergency), Standard (the rest). At the Fold5 cover only the ribbon and the Hero show.",
 notes:[[1,"One sentence about her, in her frame, before any numbers. The call button states whether now is a good time and, if not, when it is."],[2,"The two clocks and the ribbon are the same component Ivy sees, drawn on the same day parts, so both grown-ups are literally looking at one day."],[3,"A bottom bar is proposed: Today, Messages, Together, Family, More. Everything on the old home grid is still one tap away."],[4,"The Hero tile is the thing most guardians do most: bank a message. Only live, shipping features sit here; nothing is a demo."]],
 r:function(){return gHomeTop()+K.page(gHomeBody(""),{tab:tabsN(0,3)});},
 cover:function(){return K.sb()+K.top({logo:true,title:"Hi, Marcus"})+K.page(K.card(K.dual({n:2,l1:"Ivy",l2:"You",t1:"7:42",t2:"1:42",s1:"",s2:""}),"hero")+K.tile("hero",{ic:"mic",title:"Message banking",sub:"",scene:"night"})+K.tile("feat",{ic:"grid",title:"More"}));}});

D("guardianHome-loading","guardian","Guardian home, loading",{grp:"Guardian",since:"new",isNew:true,desc:"The first moments after opening, before today’s state has arrived. Static shapes in the exact layout of the real page.",
 notes:[[1,"Shapes where the sentence, clocks and call button will be. They are static: no shimmer, no spinner, no looping motion (§8.13)."],[2,"The tab bar and the greeting are real immediately, so the grown-up always knows where they are and can leave."],[3,"Nothing is invented while waiting: no placeholder times and no guess at whether she is awake."]],
 r:function(){return (gHomeTop()).replace('<div class="ttl">','<div class="ttl"'+K.n(2)+'>')+K.page(gHomeBody("loading"),{tab:tabsN(0,3)});}});

D("guardianHome-offline","guardian","Guardian home, offline",{grp:"Guardian",since:"new",isNew:true,desc:"No connection. Everything last known stays readable; clocks keep working because they are computed on the device; what you do is queued and sent later.",
 notes:[[1,"The sentence still reads: it is built from the last saved state, so the most important glance never goes blank."],[2,"The clocks keep running because time is computed on the device, not fetched."],[4,"Banking still works: a recording is saved on the device and sent later."],[5,"The bar says exactly what is true: when this was last saved, and what happens to anything you do now."],[6,"What you did while offline is shown as queued with a pill. It sends itself on return; nothing is lost and nothing is claimed as delivered."],[7,"Calling is the one thing that truly needs a line. It says so plainly instead of failing when pressed."]],
 r:function(){return gHomeTop()+K.page(gHomeBody("offline"),{tab:tabsN(0)});}});

/* -------------------------------------------------------- send timing -- */
D("sendguard","guardian","Send-time guard",{grp:"Guardian",since:"0.33.0",desc:"“Next bedtime” and “the night of June 1st” are different promises; only the first may move.",
 notes:[[1,"Two promises, in words and on a timeline. The choice is a decision with a clear selected state, not a date field."],[2,"Only the movable promise can shift if her schedule changes. The fixed one never will."],[3,"A preview in her frame shows what Ivy will see and when, using her real day parts."]],
 r:function(){return gtop("When should it arrive?")+K.page(
  opt("moon","At her next bedtime","Moves with her schedule. If bedtime shifts, so does this.",true,"",1)+
  opt("calendar","The night of June 1","A fixed promise. It will not move.",false,"",2)+
  K.card('<h4>What Ivy will see</h4>'+M.rib({now:70,overlap:null,n:3})+'<p style="margin-top:10px">It arrives at her bedtime, 7:30 PM her time (1:30 PM yours).</p>')+B("Bank it",{full:true,ic:"check"}));}});

/* ------------------------------------------------------------ banking -- */
D("banking","guardian","Message banking",{grp:"Guardian",since:"0.13.0",wide:true,desc:"Recorded ahead, delivered by her clock. Batch progress is grown-up side only. A real two-pane compose and list split on tablet and desktop.",
 notes:[[1,"Progress is a reassurance for you. Ivy never sees a counter (P2)."],[2,"Each banked message states its delivery rule in plain words and wears a state pill."],[3,"Recording is one large control with the rule beside it. Everything else waits behind it."]],
 r:function(c){var bars="";[8,14,22,12,26,18,10,24,16,8,20,12].forEach(function(h){bars+='<i style="height:'+h+'px"></i>';});
  var l=K.card('<h4>New message</h4><div class="center" style="min-height:0;padding:6px;gap:10px"><button class="rg-rec" aria-label="Record"'+K.n(3)+'>'+I("mic",38,1.8)+'</button><div class="rg-wave">'+bars+'</div><small class="rr-note">Tap to record a goodnight</small></div>'+K.field("Arrives","At her bedtime",{ic:"moon"})+'<div style="height:10px"></div>'+B("Bank it",{full:true,ic:"check"}));
  var r=K.card('<div class="row" style="padding:0"><span class="rtxt"><b>Batch</b><small>42 of 60 nights banked</small></span>'+K.chip("Only you see this",{sm:true})+'</div>'+K.progress(70),"",1)+K.card(K.row({ic:"moon",title:"Goodnight, owl",sub:"Bedtime · Tuesday",n:2,trail:K.chip("Banked",{tone:"ok",sm:true})})+K.row({ic:"sun",title:"Good morning, sunshine",sub:"Wake-up · Wednesday",trail:K.chip("Banked",{tone:"ok",sm:true})})+K.row({ic:"heart",title:"Before your test",sub:"Friday, 7:30 AM",trail:K.chip("Banked",{tone:"ok",sm:true})}));
  return two(c,l,r,"Message banking");}});

/* -------------------------------------------------------------- meds -- */
D("meds","guardian","Meds & care",{grp:"Guardian",since:"0.13.0",desc:"Real, live care information between guardians. Never a surface the child carries.",
 notes:[[1,"Who gave what and when, as a calm log. Red appears only if a dose was actually missed."],[2,"A clear line says this never appears on Ivy’s device, with the reason."],[3,"Logging a dose is one big button; the other guardian sees it at once, so nobody doubles up."]],
 r:function(){return gtop("Meds & care")+K.page(K.banner("pri","Between guardians only. Ivy never sees this.","lock",2)+
  K.card('<h4>Today</h4>'+K.row({ic:"pill",title:"Focalin 10 mg",sub:"Given 7:50 AM by "+N.b,tone:"ok",trail:I("check",20,2.4),n:1})+K.row({ic:"pill",title:"Vitamin D",sub:"Due with dinner",tone:"warn",trail:K.chip("Due",{tone:"warn",sm:true})}))+
  K.card('<h4>Notes for the other house</h4><p>Sleeps better with the hall light on. Allergic to cashews.</p>')+B("Log a dose",{full:true,ic:"plus",n:3}));}});

/* ----------------------------------------------------------- exchange -- */
D("exchange","guardian","Exchange",{grp:"Guardian",since:"0.13.0",desc:"The handoff, in her frame; the clock zone flips at the exchange, not at midnight. Real and live.",
 notes:[[1,"The exchange is the headline, with her next days in a sentence. Her day is described first, then yours."],[2,"The bag checklist is shared, so nothing is forgotten in either direction. A ticked row is green with a tick, never colour alone."],[3,"Time zones flip at the handoff, so her clocks always match where she is."]],
 r:function(){var it=[["Rain boots",1],["Library book",1],["Reading log",0],["Her owl, the soft one",1]];return gtop("Exchange")+K.page(K.card('<small class="rr-eb" style="color:inherit;opacity:.8">Sunday, 6:00 PM</small><p style="font:800 22px/1.15 var(--font-display);color:inherit;margin:6px 0">'+N.b+' brings Ivy to '+N.a+'</p><p>Then four sleeps at '+N.a+'’s house.</p><div class="chips" style="margin-top:8px"><span class="chip" style="background:rgba(255,255,255,.2);color:inherit">'+I("swap",13,2)+' Her clock moves 6 hours</span></div>',"hero",1)+
  K.card('<h4>Her bag</h4>'+it.map(function(x,i){return K.row({title:x[0],trail:cb(x[1]),tone:x[1]?"":"warn",n:i===2?2:0});}).join(""))+K.banner("info","Her clocks switch to "+N.a+"’s zone at 6:00 PM, not at midnight.","clock",3));}});

D("exchange-empty","guardian","Exchange, empty",{grp:"Guardian",since:"new",isNew:true,desc:"No handoff is planned. A guardian is invited to plan one; nothing here implies a failure.",
 notes:[[1,"A calm illustration and one sentence about what will appear here."],[2,"The single next step, in the grown-up’s own verb. Both guardians see the plan the moment it exists."]],
 r:function(){return gtop("Exchange")+K.page(M.gempty({n:1,scene:"hills",title:"No handoff planned",sub:"When you plan one it appears here for both of you, with the bag list and Ivy’s clocks.",act:B("Plan an exchange",{ic:"plus",n:2})}));}});

/* ---------------------------------------------------------- emergency -- */
D("emergencyCard","guardian","Emergency card",{grp:"Guardian",since:"0.13.0",desc:"What a third adult needs in a moment, and nothing more. A still surface, read once, possibly in a hurry (§8.13.5). Real and live; also reachable by a sitter’s time-boxed link.",
 notes:[[1,"Read once, in a hurry. Large type, strong contrast, no motion and nothing to scroll for the essentials."],[2,"Every phone number is one tap on a 48 dp-plus button, with the person’s name before the number."],[3,"Only what a stranger needs: allergies, contacts, doctor, blood type and insurance. No address trail, no history (P3)."]],
 r:function(){var ph=function(t,tn){return K.iconBtn("phone",{kind:tn,label:"Call"}).replace('class="cbtn','class="cbtn rr-48');};return gtop("Emergency card",{noBack:true})+K.page(K.card('<small class="rr-eb" style="color:var(--bad)">Allergies</small><p class="rg-big"'+K.n(1)+' style="font-size:26px">Cashews. Carries an EpiPen.</p>')+
  K.card(K.row({ic:"phone",title:N.b,sub:"555-0142",trail:ph("","pri"),n:2})+K.row({ic:"phone",title:N.a,sub:"555-0138",trail:ph("","tonal")})+K.row({ic:"shield",title:"Dr. Okafor",sub:"Her doctor · 555-0170",trail:ph("","tonal")}))+K.card('<small class="rr-eb">Blood type · Insurance</small><p style="font-size:16px;margin:6px 0 0;color:var(--ink)"'+K.n(3)+'>O positive · Plan 4471-92</p>'));}});

/* ----------------------------------------------------------- expenses -- */
D("expenses","guardian","Expenses",{grp:"Guardian",since:"0.13.0",wide:true,desc:"Real and live, guardian to guardian only. No financial surface is visible to a child role (P6). A two-pane split: approvals | ledger.",
 notes:[[1,"Approvals first: the thing someone is waiting on. Approve is a full 48 dp button."],[2,"A line states the P6 rule, so a guardian knows what Ivy can and cannot see: nothing, at any depth."],[3,"The ledger shows who paid and what is settled, in plain money words and with a state pill, never a score."]],
 r:function(c){var l=K.banner("pri","Only guardians see this. Ivy never does.","lock",2)+K.card('<h4>Waiting for you</h4>'+K.row({ic:"receipt",title:"Soccer cleats",sub:"$48 · split 50/50",trail:B("Approve",{size:"sm"}),n:1})+K.row({ic:"receipt",title:"School photos",sub:"$32 · split 50/50",trail:B("Approve",{size:"sm"})}));
  var r=K.card('<h4>Ledger</h4>'+K.row({ic:"receipt",title:"Dentist",sub:N.b+" paid $85",tone:"ok",trail:K.chip("Settled",{tone:"ok",sm:true}),n:3})+K.row({ic:"receipt",title:"Swim class",sub:"You paid $120",tone:"ok",trail:K.chip("Settled",{tone:"ok",sm:true})})+K.row({ic:"receipt",title:"Winter coat",sub:N.b+" paid $64 · you owe $32",trail:K.chip("Open",{tone:"warn",sm:true})}));return two(c,l,r,"Expenses");}});

D("expenses-empty","guardian","Expenses, empty",{grp:"Guardian",since:"new",isNew:true,desc:"No shared costs yet. One sentence, one next step. The privacy line stays, because it is part of the screen’s promise.",
 notes:[[1,"The P6 line stays even when empty: this is a place only guardians can ever see."],[2,"One illustration and one sentence saying what will appear."],[3,"A single clear action. Adding an expense notifies only the other guardian."]],
 r:function(){return gtop("Expenses")+K.page(K.banner("pri","Only guardians see this. Ivy never does.","lock",1)+M.gempty({n:2,scene:"paper",title:"Nothing to split yet",sub:"Costs you share, like clubs or school things, appear here for both of you.",act:B("Add an expense",{ic:"plus",n:3})}));}});

D("expenses-error","guardian","Expenses, can’t load",{grp:"Guardian",since:"new",isNew:true,desc:"The ledger could not be fetched. Says what is safe, what was last seen, and what to do. Nothing is changed by a failed load.",
 notes:[[1,"The first sentence says what is true: nothing was changed. A shared money record must never leave anyone unsure."],[2,"The last good copy is shown with its time, clearly marked as saved, so a guardian can still read it."],[3,"One retry and one way out. Approve is disabled while the ledger is not live, so nobody approves against old numbers."]],
 r:function(){return gtop("Expenses")+K.page(errBanner("Couldn’t load the ledger. Nothing was changed.",1)+K.card('<div class="row" style="padding:0 0 4px"><span class="rtxt"><b>Last saved copy</b><small>From 6:40 AM today</small></span>'+K.chip("Saved",{sm:true})+'</div>'+K.row({ic:"receipt",title:"Dentist",sub:N.b+" paid $85",tone:"ok",trail:K.chip("Settled",{tone:"ok",sm:true}),n:2})+K.row({ic:"receipt",title:"Winter coat",sub:N.b+" paid $64 · you owe $32"}))+
  '<div class="btns"'+K.n(3)+'>'+B("Try again",{ic:"refresh"})+B("Not now",{kind:"ghost"})+'</div>');}});

/* ----------------------------------------------------------- handover -- */
D("handover","guardian","Handover notes",{grp:"Guardian",since:"0.8.0",wide:true,desc:"Real and live. The log between the grown-ups; entries cannot be deleted or edited (P8). A real two-pane split.",
 notes:[[1,"Entries are a permanent record. The lock and the line say so before anyone writes (P8)."],[2,"Newest first, with who and when. Both guardians read the same log."]],
 r:function(c){var l=K.banner("warn","Entries can’t be edited or deleted. Write what you’d be happy to read again.","lock",1)+K.card('<div class="field" style="border:0;padding:0"><small>New note</small><span class="fv" style="min-height:44px"><i class="ph">Slept badly Tuesday. Cut the nap short.</i></span></div>'+B("Add to the log",{full:true,ic:"send"}));
  var r=K.card(K.row({av:K.avatar("J",{size:40}),title:N.b+" · Today 6:10 AM",sub:"Reading log needs a signature. Tired but happy.",n:2})+K.row({av:K.avatar("M",{size:40,tone:"accent"}),title:N.a+" · Yesterday",sub:"Ivy lost a tooth! Left it under the pillow."})+K.row({av:K.avatar("J",{size:40}),title:N.b+" · Tuesday",sub:"Library book is due Friday."}));return two(c,l,r,"Handover");}});

D("handover-empty","guardian","Handover, empty",{grp:"Guardian",since:"new",isNew:true,desc:"A new log. The first entry is invited, and the permanence rule is told once, before anything is written.",
 notes:[[1,"The permanence rule comes first: entries can’t be edited or deleted (P8). Better to be told here than after sending."],[2,"One sentence of what the log is for, one clear action."]],
 r:function(){return gtop("Handover")+K.page(K.banner("warn","Entries can’t be edited or deleted. Write what you’d be happy to read again.","lock",1)+M.gempty({n:2,scene:"letters",title:"No notes yet",sub:"A short note about her day, for the other house. They see it the moment you add it.",act:B("Write the first note",{ic:"pencil"})}));}});

/* ----------------------------------------------------------- the rest -- */
D("briefing","guardian","Morning briefing",{grp:"Guardian",since:"0.33.0",desc:"What matters today, composed for the guardian who wakes to it.",
 notes:[[1,"Four lines in order of importance. No dashboard, no totals, no moods and no score."],[2,"Each line is a fact in her frame, with a time she can check."]],
 r:function(){return gtop("Good morning",{noBack:true,eyebrow:"Thursday"})+K.page(K.card('<p style="font:800 21px/1.25 var(--font-display);margin:0;color:inherit">Ivy is up and getting ready. You have one message waiting.</p>',"hero")+K.card(K.row({ic:"chat",title:"Ivy sent a drawing",sub:"At 6:48 AM her time",tone:"ok",n:1})+K.row({ic:"calendar",title:"Pickup at 3:00 PM",sub:"Grandma is collecting her",n:2})+K.row({ic:"pill",title:"Medication was given",sub:"7:50 AM by "+N.b,tone:"ok"})+K.row({ic:"clock",title:"Best time to call",sub:"3:30 to 4:30 PM her time"})));}});

D("careNote","guardian","Care note",{grp:"Guardian",since:"0.33.0",wide:true,desc:"A soft channel for the hard days. A real two-pane split (compose | sent notes).",
 notes:[[1,"Prompts are gentle suggestions, never templates that put words in a guardian’s mouth. The field is wide, and there is no length rule."]],
 r:function(c){var l=K.card('<h4>A note for '+N.b+'</h4><p>Tough morning? Want to share how it went?</p><div class="chips">'+K.chip("A hard morning")+K.chip("A small win")+K.chip("Could use a hand")+'</div>'+K.field("Your note","",{ph:"Write as much as you like",n:1})+'<div style="height:6px"></div>'+B("Send",{full:true,ic:"send"}));
  var r=K.card(K.row({ic:"heart",title:"A small win",sub:"Ivy tried the spinach · yesterday",tone:"ok"})+K.row({ic:"heart",title:"Thank you",sub:"For the late call · Sunday",tone:"ok"}));return two(c,l,r,"Care note");}});

D("availability","guardian","Availability",{grp:"Guardian",since:"0.33.0",wide:true,desc:"When you can actually be reached, honestly rendered. Editable weekly hours | read-only co-guardians list.",
 notes:[[1,"Hours are shown in both zones so nobody does the maths: your morning is her afternoon."],[2,"“Busy” is a first-class state, not a missing slot. Ivy only ever sees “can talk now” or “is busy”."]],
 r:function(c){var days=["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];var l=K.card('<h4>Your hours</h4>'+days.map(function(d,i){return K.row({title:d,sub:i<5?"9 to 11 AM · her 3 to 5 PM":"All day",trail:K.toggle(i!==5),n:i===0?1:0});}).join(""));
  var r=K.card('<h4>When others can reach you</h4>'+K.row({av:K.avatar("J",{size:40}),title:N.b,sub:"Weekdays 7 to 9 AM her time"})+K.row({av:K.avatar("G",{size:40,tone:"accent"}),title:"Grandma",sub:"Evenings"}))+K.banner("info","Ivy sees only “"+N.a+" can talk now” or “"+N.a+" is busy”.","info",2);return two(c,l,r,"Availability");}});

D("busyFork","guardian","Busy fork",{grp:"Guardian",since:"0.33.0",desc:"They are busy: the ask forks to a message instead of failing silently.",
 notes:[[1,"The call never just fails. It becomes a message that arrives when they are free, with both times written out."],[2,"Two equal choices, each a full-size button."]],
 r:function(){return gtop(N.a+" is busy")+K.page('<div class="center" style="min-height:460px"><span class="ricon" style="width:68px;height:68px;border-radius:24px">'+I("clock",30,1.8)+'</span><div class="big" style="font-size:24px">'+N.a+' is busy until 4:00 PM his time</div><p style="color:var(--ink2);margin:0"'+K.n(1)+'>That is 10:00 PM yours. Leave something and it will arrive when he can see it.</p><div style="display:grid;gap:10px;width:100%"'+K.n(2)+'>'+K.btn("Leave a message",{full:true,ic:"mic",size:"lg"})+K.btn("Ask him to call me",{kind:"tonal",full:true,ic:"phone",size:"lg"})+'</div></div>');}});

D("deletion","guardian","Deletion",{grp:"Guardian",since:"0.29.0",desc:"What deletion means here, stated before it happens. Delivered messages belong to the child.",
 notes:[[1,"The consequences come first, each in a plain sentence and a state colour."],[2,"The destructive button is set apart and stays disabled until the name is typed."]],
 r:function(){return gtop("Delete your account")+K.page(K.banner("bad","Before you do this, here is what it means.","warn")+K.card(K.row({ic:"check",title:"Messages Ivy already received stay with her",tone:"ok",n:1})+K.row({ic:"x",title:"Messages you banked but not delivered are removed",tone:"warn"})+K.row({ic:"x",title:"Your sign-in stops working",tone:"warn"})+K.row({ic:"lock",title:"The shared log with "+N.b+" is kept",sub:"Entries can’t be deleted",tone:"info"}))+K.field("Type your name to confirm","",{ph:"Marcus"})+B("Delete my account",{kind:"danger",full:true,n:2}));}});

D("siblings","guardian","Siblings",{grp:"Guardian",since:"0.29.0",desc:"Sibling links never widen authority: a guardian of one is not a guardian of the other.",
 notes:[[1,"Each child stands alone. A link only lets the two children play together; it grants nothing to a grown-up."]],
 r:function(){return gtop("Siblings")+K.page(K.card(K.row({av:K.avatar("I",{size:44}),title:"Ivy",sub:"You are a guardian",trail:K.chip("Guardian",{tone:"ok",sm:true})})+K.row({av:K.avatar("L",{size:44,tone:"accent"}),title:"Leo",sub:"Half-brother · "+N.b+"’s family",trail:K.chip("Linked",{sm:true}),n:1}))+K.banner("info","Linking lets Ivy and Leo play together. It does not give you access to Leo.","shield"));}});

D("quieting","guardian","Quieting",{grp:"Guardian",since:"0.29.0",desc:"The app goes quiet without scoring her absence (P2).",
 notes:[[1,"When a child is away or busy, the product simply gets quieter. It never reports a streak or a gap, to her or about her (P2)."]],
 r:function(){return gtop("Quiet times")+K.page(K.banner("pri","Quiet never counts anything and never tells Ivy.","moon",1)+K.card(K.row({ic:"moon",title:"Bedtime wind-down",sub:"7:00 to 7:30 PM her time",trail:K.toggle(true)})+K.row({ic:"book",title:"School hours",sub:"No games or jokes",trail:K.toggle(true)})+K.row({ic:"heart",title:"When she’s been away",sub:"Fewer reminders after 3 days",trail:K.toggle(true)})));}});

D("letters","guardian","Letters",{grp:"Guardian",since:"0.29.0",wide:true,desc:"Long-form, slow, keepable. A real two-pane split (compose | sealed letters).",
 notes:[[1,"A letter is sealed until its day. The page is quiet and wide, built for writing, and sealing is the only way to send."]],
 r:function(c){var l=K.card('<h4>Dear Ivy,</h4><p style="min-height:110px;color:var(--ink2)">I watched the herons this morning and thought of the pond…</p>'+K.field("Opens","Saturday morning",{ic:"calendar",n:1})+'<div style="height:6px"></div>'+B("Seal it",{full:true,ic:"lock"}));
  var r=K.card('<div style="height:90px;margin:-2px -2px 10px;border-radius:18px;overflow:hidden">'+K.scene("letters",300,90)+'</div>'+K.row({ic:"letter",title:"To Ivy · Saturday",sub:"Sealed",trail:K.chip("2 days",{sm:true})})+K.row({ic:"letter",title:"To Ivy · her birthday",sub:"Sealed",trail:K.chip("Sep 14",{sm:true})}));return two(c,l,r,"Letters");}});

D("teachMe","guardian","Teach me",{grp:"Guardian",since:"0.29.0",desc:"She teaches a grown-up something from her week.",
 notes:[[1,"She is the expert. The grown-up is invited to learn and replies in kind, with a photo, never a grade."]],
 r:function(){return gtop("Ivy is teaching you")+K.page('<div style="position:relative;border-radius:26px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("paper",300,160)+'<span style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:64px;height:64px;border-radius:50%;background:rgba(255,255,255,.94);display:grid;place-items:center;color:var(--priD)">'+I("play",28,2)+'</span></span></div>'+K.card('<h4'+K.n(1)+'>How to fold a paper boat</h4><p>Ivy · 1 min</p>')+B("Try it and show her",{full:true,ic:"camera"}));}});

D("expiryDigest","guardian","Expiry digest",{grp:"Guardian",since:"0.22.0",desc:"Preservation is a standing rule; the 14-day digest is the only reminder surface.",
 notes:[[1,"Only incidental things expire, and each says plainly what is about to go. Keep is a full-size action."]],
 r:function(){return gtop("In the next 14 days")+K.page(K.banner("pri","Everything meaningful is kept. These few things are temporary.","leaf",1)+K.card(K.row({ic:"video",title:"Call clip, Tuesday",sub:"Goes in 9 days",trail:B("Keep",{size:"sm",kind:"tonal"}),n:1})+K.row({ic:"image",title:"A screen-share frame",sub:"Goes in 12 days",trail:B("Keep",{size:"sm",kind:"tonal"})})));}});

D("export","guardian","Court export",{grp:"Guardian",since:"0.14.0",desc:"The archive assembled for the one reader who must trust it; chunked under the transfer ceiling.",
 notes:[[1,"Progress is shown by chunk, because that is what a court clerk will receive."],[2,"The seal is the last step, with what it proves written beside it."]],
 r:function(){return gtop("Court export")+K.page(K.card('<h4>Assembling</h4><p>Handover log, calendar, messages</p>'+K.progress(72)+'<div class="kv" style="margin-top:10px"><span>Chunks</span><span>9 of 12</span><span>Entries</span><span>1,482</span><span>Size</span><span>38 MB</span></div>',"",1)+K.card(K.row({ic:"shieldcheck",title:"Seal and certify",sub:"Adds a signature the other side can verify",tone:"info",n:2}))+B("Wait for it to finish",{full:true,kind:"tonal"}));}});

D("yearbook","guardian","Year book",{grp:"Guardian",since:"0.28.0",desc:"A year of her, preserved.",
 notes:[[1,"Chapters are titled from her side: things you made, things you taught me, things that happened."],[2,"Her year of colours is five swatches, a quiet record and not a chart."]],
 r:function(){return gtop("Ivy, age 6")+K.page('<div style="border-radius:28px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("hills",300,150)+'</div>'+K.card(K.row({ic:"brush",title:"Things you made",sub:"31 pictures",go:true,n:1})+K.row({ic:"smile",title:"Things you taught me",sub:"12",go:true})+K.row({ic:"heart",title:"Things that happened",sub:"23",go:true}))+K.card('<h4>Her colours</h4><div class="chips">'+["#2F8FC4","#E8730C","#5AA84A","#8B6BB1","#F2B705"].map(function(c){return '<i style="width:34px;height:34px;border-radius:50%;background:'+c+'"></i>';}).join("")+'</div>',"",2));}});

D("gallery","guardian","Gallery",{grp:"Guardian",since:"0.28.0",desc:"Year-grouped works; past two thousand, paginate by era.",
 notes:[[1,"Works sit in a calm grid grouped by year. Eras appear only when there are enough to need them."]],
 r:function(){var cells="",sc=["paper","sea","hills","night","branch","letters"];for(var i=0;i<6;i++)cells+='<div style="border-radius:20px;overflow:hidden;aspect-ratio:1;box-shadow:var(--shadow1)">'+K.scene(sc[i],150,150)+'</div>';return gtop("Gallery")+K.page(K.seg(["2026","2025","2024"],0,1)+'<div class="grid2">'+cells+'</div>');}});

D("gallery-empty","guardian","Gallery, empty",{grp:"Guardian",since:"new",isNew:true,desc:"Nothing has been made or shown yet. The sentence says what will be kept, and promises nothing is ever removed to make space.",
 notes:[[1,"The year tabs wait, so the page already has its shape."],[2,"One sentence about what lands here, and the promise that it is kept."]],
 r:function(){return gtop("Gallery")+K.page(K.seg(["2026","2025","2024"],0,1)+M.gempty({n:2,scene:"paper",title:"Nothing here yet",sub:"What Ivy draws, photographs or shows you is kept here. Nothing is ever removed to make room."}));}});

D("themePicker","guardian","Theme",{grp:"Guardian",since:"0.49.19",desc:"Seven palettes by light and dark, guardian-only, backend-synced. She never sees a way to reach it. Olive is proposed as the new default.",
 notes:[[1,"Each palette card previews real colour. Olive is the proposed brand default."],[2,"Nothing changes on her device until Apply."]],
 r:function(){var P=[["olive","Olive"],["classic","Classic"],["calm","Calm modern"],["warm","Warm grounded"],["playful","Soft playful"],["cozy","Deep cozy"],["bold","Bright bold"]];var cards=P.map(function(p,i){var sd=K.SEEDS[p[0]].seed;return '<div class="card" style="padding:12px;min-height:70px;'+(i===0?"box-shadow:0 0 0 2.5px var(--pri)":"")+'"><div class="rg-sw" style="margin-bottom:8px"><i style="background:'+sd+'"></i><i style="background:'+sd+';opacity:.45"></i><i style="background:'+sd+';opacity:.2"></i></div><b style="font-size:13.5px">'+p[1]+(i===0?" · proposed":"")+'</b></div>';}).join("");
  return gtop("How Ivy’s app looks")+K.page(K.seg(["Light","Dark"],0)+'<div class="grid2"'+K.n(1)+'>'+cards+'</div>'+B("Apply",{full:true,n:2}));}});
})();
