/* Guardian surfaces. The shell is calmer and denser than the child's, and never makes a parent do maths. */
(function(){
"use strict";
var K=OB,I=K.ico,D=K.def;
function gtop(title,o){o=o||{};return K.sb()+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function tabs(a){return K.tabbar([["home","Today"],["chat","Messages"],["dice","Together"],["users","Family"],["more","More"]],a);}
function two(c,l,r,title,o){if(c.form==="tablet")return gtop(title,o)+'<div class="tw"><div>'+l+'</div><div>'+r+'</div></div>';return gtop(title,o)+K.page(l+r);}

D("guardianHome","guardian","Guardian home",{grp:"Guardian",since:"0.8.0",
 desc:"Her state as a sentence about her. The child's time dominant, the actor's subordinate. Never make a parent do maths. Three tiers: Hero (Message banking), Featured (Availability, Send-time guard, Meds & care, Emergency card), Standard (the rest). At the Fold5 cover only the ribbon and the Hero show.",
 notes:[[1,"One sentence about her, in her frame, then the numbers. The call button states whether now is a good time."],[2,"The dual clock and ribbon are the same component Ivy sees, so both parents are literally looking at the same day."],[3,"A tab bar is proposed: Today, Messages, Together, Family, More. Everything on the old home grid is still one tap from here."],[4,"Hero tile is the one thing most guardians do most: bank a message."]],
 r:function(){return K.sb()+K.top({logo:true,eyebrow:"Good evening",title:"Hi, Marcus",right:K.avatar("M",{size:40})})+
  K.page(K.card('<p style="font:800 19px/1.25 var(--font-display);margin:0 0 12px;color:inherit"'+K.n(1)+'>Ivy is getting ready for school. She can talk at 3:00 PM her time.</p>'+K.dual({n:2,l1:"Ivy, her time",t1:"7:42 AM",s1:"Before school",l2:"You, your time",t2:"1:42 AM",s2:""})+'<div style="height:14px"></div>'+K.ribbon({now:31,overlap:[40,10]})+'<div style="height:12px"></div><button class="btn full" style="background:rgba(255,255,255,.18);color:#fff;box-shadow:none">'+I("video",18,2)+' Call Ivy at 3:00 PM</button>',"hero")+
  K.tile("hero",{ic:"mic",title:"Message banking",sub:"42 nights banked",scene:"night",n:4})+
  '<div class="grid2">'+K.tile("feat",{ic:"clock",title:"Availability"})+K.tile("feat",{ic:"send",title:"Send timing"})+K.tile("feat",{ic:"pill",title:"Meds & care"})+K.tile("feat",{ic:"shield",title:"Emergency"})+'</div>'+
  K.sectionLabel("More")+'<div class="grid4">'+[["swap","Exchange"],["list","Handover"],["receipt","Expenses"],["letter","Letters"],["camera","Show me"],["image","Gallery"],["book","Year book"],["sliders","Settings"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>',{tab:tabs(0)});},
 cover:function(){return K.sb()+K.top({logo:true,title:"Hi, Marcus"})+K.page(K.card(K.dual({n:2}),"hero")+K.tile("hero",{ic:"mic",title:"Message banking",sub:"",scene:"night"})+K.tile("feat",{ic:"grid",title:"More"}));}});

D("sendguard","guardian","Send-time guard",{grp:"Guardian",since:"0.33.0",desc:"“Next bedtime” and “the night of June 1st” are different promises; only the first may move.",
 notes:[[1,"Two promises, described in words and drawn on a timeline. The choice is a decision, not a date field."],[2,"Only the movable promise can shift if her schedule changes."]],
 r:function(){return gtop("When should it arrive?")+K.page(
  K.card('<div class="row" style="padding:0"><span class="ricon">'+I("moon",20,1.9)+'</span><span class="rtxt"><b>At her next bedtime</b><small>Moves with her schedule. If bedtime shifts, so does this.</small></span>'+K.toggle(true)+'</div>',"tint",1)+
  K.card('<div class="row" style="padding:0"><span class="ricon">'+I("calendar",20,1.9)+'</span><span class="rtxt"><b>The night of June 1</b><small>A fixed promise. It will not move.</small></span>'+K.toggle(false)+'</div>',"",2)+
  K.card('<h4>What Ivy will see</h4>'+K.ribbon({now:70,overlap:[82,8]})+'<p style="margin-top:8px">It arrives at her bedtime, 7:30 PM her time (6:30 AM yours).</p>')+K.btn("Bank it",{full:true,size:"lg",ic:"check"}));}});

D("banking","guardian","Message banking",{grp:"Guardian",since:"0.13.0",wide:true,desc:"Recorded ahead, delivered by her clock. Batch progress is parent-side only. A real two-pane compose/list split on tablet and desktop.",
 notes:[[1,"Progress is a reassurance for you. Ivy never sees a counter."],[2,"Each banked message states its delivery rule in plain words."],[3,"Recording is one large control. Everything else waits behind it."]],
 r:function(c){var l=K.card('<h4>New message</h4><div class="center" style="min-height:0;padding:6px"><button style="width:88px;height:88px;border-radius:50%;border:0;background:var(--bad);color:#fff;box-shadow:0 10px 24px -8px var(--bad)" aria-label="Record"'+K.n(3)+'>'+I("mic",36,1.8)+'</button><small style="color:var(--ink3)">Tap to record a goodnight</small></div>'+K.field("Arrives","At her bedtime",{ic:"moon"})+K.btn("Bank it",{full:true,ic:"check"}));
  var r=K.card('<div class="row" style="padding:0"><span class="rtxt"><b>Deployment batch</b><small>42 of 60 nights banked</small></span>'+K.chip("Only you see this",{sm:true})+'</div>'+K.progress(70)+'',"",1)+K.card(K.row({ic:"moon",title:"Goodnight, owl",sub:"Bedtime · Tue",n:2,trail:K.chip("Banked",{tone:"ok",sm:true})})+K.row({ic:"sun",title:"Good morning, sunshine",sub:"Wake-up · Wed",trail:K.chip("Banked",{tone:"ok",sm:true})})+K.row({ic:"heart",title:"Before your test",sub:"Fri, 7:30 AM",trail:K.chip("Banked",{tone:"ok",sm:true})}));
  return two(c,l,r,"Message banking");}});

D("meds","guardian","Meds & care",{grp:"Guardian",since:"0.13.0",desc:"Care information between guardians; never a surface the child carries.",
 notes:[[1,"Who gave what, and when, as a calm log. No red unless something was actually missed."],[2,"Clear banner: this never appears on Ivy’s device."]],
 r:function(){return gtop("Meds & care")+K.page(K.banner("pri","Between guardians only. Ivy never sees this.","lock",2)+
  K.card('<h4>Today</h4>'+K.row({ic:"pill",title:"Focalin 10 mg",sub:"Given 7:50 AM by Mom",tone:"ok",trail:I("check",18,2.2),n:1})+K.row({ic:"pill",title:"Vitamin D",sub:"Due with dinner",tone:"warn"}))+
  K.card('<h4>Notes for the other house</h4><p>Sleeps better with the hall light on. Allergic to cashews.</p>')+K.btn("Log a dose",{full:true,ic:"plus"}));}});

D("exchange","guardian","Exchange",{grp:"Guardian",since:"0.13.0",desc:"The handoff, in her frame; the zone flips at the exchange, not at midnight.",
 notes:[[1,"The exchange is the headline. Her day is described, then yours."],[2,"The bag checklist is shared, so nothing is forgotten in either direction."]],
 r:function(){return gtop("Exchange")+K.page(K.card('<small class="mono" style="opacity:.8">FRIDAY 6:00 PM</small><p style="font:800 22px/1.15 var(--font-display);color:inherit;margin:6px 0">School pickup, then Dad’s house</p><p>For 4 sleeps.</p>',"hero",1)+
  K.card('<h4>Her bag</h4>'+K.row({ic:"check",title:"Rain boots",tone:"ok"})+K.row({ic:"check",title:"Library book",tone:"ok"})+K.row({ic:"book",title:"Reading log",tone:"warn"})+K.row({ic:"heart",title:"Owl (the soft one)",tone:"ok"}),"",2));}});

D("emergencyCard","guardian","Emergency card",{grp:"Guardian",since:"0.13.0",desc:"What a third adult needs in a moment, and nothing more. A still surface, read once, possibly in a hurry (§8.13.5).",
 notes:[[1,"Read once, in a hurry. Large type, strong contrast, no motion."],[2,"Every phone number is one tap."]],
 r:function(){return gtop("Emergency card",{noBack:true})+K.page(K.card('<small class="mono" style="color:var(--bad);font-weight:700">ALLERGIES</small><p style="font:800 24px/1.15 var(--font-display);margin:4px 0;color:var(--ink)"'+K.n(1)+'>Cashews. Carries an EpiPen.</p>')+
  K.card(K.row({ic:"phone",title:"Mom",sub:"555-0142",trail:K.iconBtn("phone",{kind:"pri"}),n:2})+K.row({ic:"phone",title:"Dad",sub:"Overseas · message only"})+K.row({ic:"shield",title:"Dr. Okafor",sub:"555-0170",trail:K.iconBtn("phone",{kind:"tonal"})}))+K.card('<small class="mono" style="color:var(--ink3)">BLOOD TYPE · INSURANCE</small><p>O positive · Plan 4471-92</p>'));}});

D("expenses","guardian","Expenses",{grp:"Guardian",since:"0.13.0",wide:true,desc:"Guardian to guardian only. No financial surface is visible to a child role (P6). A two-pane split: approvals | ledger.",
 notes:[[1,"Approvals first: the thing someone is waiting on."],[2,"A banner states the P6 rule so a guardian knows what Ivy can and cannot see."]],
 r:function(c){var l=K.banner("pri","Only guardians see this. Ivy never does.","lock",2)+K.card('<h4>Waiting for you</h4>'+K.row({ic:"receipt",title:"Soccer cleats",sub:"$48 · split 50/50",trail:K.btn("Approve",{size:"sm"}),n:1})+K.row({ic:"receipt",title:"School photos",sub:"$32 · split 50/50",trail:K.btn("Approve",{size:"sm"})}));
  var r=K.card('<h4>Ledger</h4>'+K.row({ic:"receipt",title:"Dentist",sub:"Mom paid $85 · settled",tone:"ok"})+K.row({ic:"receipt",title:"Swim class",sub:"Dad paid $120 · settled",tone:"ok"})+K.row({ic:"receipt",title:"Winter coat",sub:"Mom paid $64 · you owe $32"}));return two(c,l,r,"Expenses");}});

D("handover","guardian","Handover notes",{grp:"Guardian",since:"0.8.0",wide:true,desc:"Parent-to-parent log; entries cannot be deleted or edited (P8). A real two-pane split.",
 notes:[[1,"Entries are a permanent record. The lock icon and the line say so before she writes."],[2,"Newest first, with who and when."]],
 r:function(c){var l=K.banner("warn","Entries can’t be edited or deleted. Write what you’d be happy to read again.","lock",1)+K.card('<div class="field" style="border:0;padding:0"><small>New note</small><span class="fv"><i class="ph">Slept badly Tuesday. Cut the nap short.</i></span></div>'+K.btn("Add to the log",{full:true,ic:"send"}));
  var r=K.card(K.row({av:K.avatar("M",{size:38}),title:"Mom · Today 6:10 AM",sub:"Reading log needs a signature. Tired but happy.",n:2})+K.row({av:K.avatar("D",{size:38,tone:"accent"}),title:"Dad · Yesterday",sub:"Ivy lost a tooth! Left it under the pillow."})+K.row({av:K.avatar("M",{size:38}),title:"Mom · Tuesday",sub:"Library book is due Friday."}));return two(c,l,r,"Handover");}});

D("briefing","guardian","Morning briefing",{grp:"Guardian",since:"0.33.0",desc:"What matters today, composed for the guardian who wakes to it.",
 notes:[[1,"Four lines, in order of importance. No dashboard, no totals."]],
 r:function(){return gtop("Good morning",{noBack:true,eyebrow:"Saturday"})+K.page(K.card('<p style="font:800 20px/1.25 var(--font-display);margin:0;color:inherit">Ivy had a good night. You have one message waiting.</p>',"hero")+K.card(K.row({ic:"chat",title:"Ivy sent a drawing",sub:"At 6:48 AM her time",tone:"ok",n:1})+K.row({ic:"calendar",title:"Pickup at 3:00 PM",sub:"Grandma is collecting her"})+K.row({ic:"pill",title:"Medication was given",sub:"7:50 AM by Mom",tone:"ok"})+K.row({ic:"clock",title:"Best time to call",sub:"3:30–4:30 PM her time"})));}});

D("careNote","guardian","Care note",{grp:"Guardian",since:"0.33.0",wide:true,desc:"A soft channel for the hard days. A real two-pane split (compose | sent notes).",
 notes:[[1,"Prompts are gentle suggestions, never templates that put words in a guardian's mouth."]],
 r:function(c){var l=K.card('<h4>A note for Marcus</h4><p>Tough morning. Want to share how it went?</p><div class="chips">'+K.chip("A hard morning")+K.chip("A small win")+K.chip("Could use a hand")+'</div>'+K.field("Your note","",{ph:"Write as much as you like",n:1})+K.btn("Send",{full:true,ic:"send"}));
  var r=K.card(K.row({ic:"heart",title:"A small win",sub:"Ivy tried the spinach. Yesterday",tone:"ok"})+K.row({ic:"heart",title:"Thank you",sub:"For the late call. Sunday"}));return two(c,l,r,"Care note");}});

D("availability","guardian","Availability",{grp:"Guardian",since:"0.33.0",wide:true,desc:"When he can actually be reached, honestly rendered. Editable weekly hours | read-only co-guardians list.",
 notes:[[1,"Hours are shown in both timezones so nobody does the maths."],[2,"“Busy” is a first-class state, not a missing slot."]],
 r:function(c){var days=["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];var l=K.card('<h4>Your hours</h4>'+days.map(function(d,i){return K.row({title:d,sub:i<5?"6:00–9:00 PM":"All day",trail:K.toggle(i!==5),n:i===0?1:0});}).join(""));
  var r=K.card('<h4>When others can reach you</h4>'+K.row({av:K.avatar("M",{size:38}),title:"Mom",sub:"Weekdays 7–9 AM her time"})+K.row({av:K.avatar("G",{size:38,tone:"accent"}),title:"Grandma",sub:"Evenings"}))+K.banner("info","Ivy sees only “Dad can talk now” or “Dad is busy”.","info",2);return two(c,l,r,"Availability");}});

D("busyFork","guardian","Busy fork",{grp:"Guardian",since:"0.33.0",desc:"He is busy: the ask forks to async instead of failing silently.",
 notes:[[1,"The call never just fails. It turns into a message that arrives when he is free."]],
 r:function(){return gtop("Dad is busy")+K.page('<div class="center" style="min-height:460px"><span class="ricon" style="width:64px;height:64px;border-radius:22px">'+I("clock",30,1.8)+'</span><div class="big" style="font-size:24px">Dad is busy until 4:00 PM</div><p style="color:var(--ink2)"'+K.n(1)+'>Leave something for him. It will arrive when he can see it.</p>'+K.btn("Leave a message",{full:true,ic:"mic"})+K.btn("Ask him to call me",{kind:"tonal",full:true,ic:"phone"})+'</div>');}});

D("deletion","guardian","Deletion",{grp:"Guardian",since:"0.29.0",desc:"What deletion means here, stated before it happens. Delivered messages belong to the child.",
 notes:[[1,"The consequences come first, each in a plain sentence."],[2,"The destructive button is separate and stays disabled until the name is typed."]],
 r:function(){return gtop("Delete your account")+K.page(K.banner("bad","Before you do this, here is what it means.","warn")+K.card(K.row({ic:"check",title:"Messages Ivy already received stay with her",tone:"ok",n:1})+K.row({ic:"x",title:"Messages you banked but not delivered are removed",tone:"warn"})+K.row({ic:"x",title:"Your sign-in stops working",tone:"warn"})+K.row({ic:"lock",title:"The shared log with Mom is kept",sub:"Entries can’t be deleted",tone:"info"}))+K.field("Type your name to confirm","",{ph:"Marcus"})+K.btn("Delete my account",{kind:"danger",full:true,n:2}));}});

D("siblings","guardian","Siblings",{grp:"Guardian",since:"0.29.0",desc:"Sibling links never widen authority: a guardian of one is not a guardian of the other.",
 notes:[[1,"Each child is separate. A link only lets the two children play together."]],
 r:function(){return gtop("Siblings")+K.page(K.card(K.row({av:K.avatar("I",{size:42}),title:"Ivy",sub:"You are a guardian",trail:K.chip("Guardian",{tone:"ok",sm:true})})+K.row({av:K.avatar("L",{size:42,tone:"accent"}),title:"Leo",sub:"Half-brother · Mom’s family",trail:K.chip("Linked",{sm:true}),n:1}))+K.banner("info","Linking lets Ivy and Leo play together. It does not give you access to Leo.","shield"));}});

D("quieting","guardian","Quieting",{grp:"Guardian",since:"0.29.0",desc:"The app goes quiet without scoring her absence (P2).",
 notes:[[1,"When a child is away or busy, the product simply gets quieter. It never reports a streak or a gap."]],
 r:function(){return gtop("Quiet times")+K.page(K.banner("pri","Quiet never counts anything and never tells Ivy.","moon",1)+K.card(K.row({ic:"moon",title:"Bedtime wind-down",sub:"7:00–7:30 PM her time",trail:K.toggle(true)})+K.row({ic:"book",title:"School hours",sub:"No games or jokes",trail:K.toggle(true)})+K.row({ic:"heart",title:"When she’s been away",sub:"Fewer reminders after 3 days",trail:K.toggle(true)})));}});

D("letters","guardian","Letters",{grp:"Guardian",since:"0.29.0",wide:true,desc:"Long-form, slow, keepable. A real two-pane split (compose | sealed letters).",
 notes:[[1,"A letter is sealed until its day. The page is quiet and wide, built for writing."]],
 r:function(c){var l=K.card('<h4>Dear Ivy,</h4><p style="min-height:110px;color:var(--ink2)">I watched the herons this morning and thought of the pond…</p>'+K.field("Opens","Saturday morning",{ic:"calendar",n:1})+K.btn("Seal it",{full:true,ic:"lock"}));
  var r=K.card('<div style="height:90px;margin:-2px -2px 10px;border-radius:16px;overflow:hidden">'+K.scene("letters",300,90)+'</div>'+K.row({ic:"letter",title:"To Ivy · Saturday",sub:"Sealed",trail:K.chip("3 days",{sm:true})})+K.row({ic:"letter",title:"To Ivy · her birthday",sub:"Sealed",trail:K.chip("Sep 14",{sm:true})}));return two(c,l,r,"Letters");}});

D("teachMe","guardian","Teach me",{grp:"Guardian",since:"0.29.0",desc:"She teaches him something from her week.",
 notes:[[1,"She is the expert. The guardian is invited to learn, and replies in kind."]],
 r:function(){return gtop("Ivy is teaching you")+K.page('<div style="position:relative;border-radius:24px;overflow:hidden">'+K.scene("paper",300,160)+'<span style="position:absolute;inset:0;display:grid;place-items:center"><span style="width:60px;height:60px;border-radius:50%;background:rgba(255,255,255,.92);display:grid;place-items:center;color:var(--priD)">'+I("play",26,2)+'</span></span></div>'+K.card('<h4'+K.n(1)+'>How to fold a paper boat</h4><p>Ivy · 1 min</p>')+K.btn("Try it and show her",{full:true,ic:"camera"}));}});

D("expiryDigest","guardian","Expiry digest",{grp:"Guardian",since:"0.22.0",desc:"Preservation is a standing rule; the 14-day digest is the only reminder surface.",
 notes:[[1,"Only incidental things expire, and each says plainly what is about to go."]],
 r:function(){return gtop("In the next 14 days")+K.page(K.banner("pri","Everything meaningful is kept. These few things are temporary.","leaf",1)+K.card(K.row({ic:"video",title:"Call clip, Tuesday",sub:"Goes in 9 days",trail:K.btn("Keep",{size:"sm",kind:"tonal"}),n:1})+K.row({ic:"image",title:"A screen-share frame",sub:"Goes in 12 days",trail:K.btn("Keep",{size:"sm",kind:"tonal"})})));}});

D("export","guardian","Court export",{grp:"Guardian",since:"0.14.0",desc:"The archive assembled for the one reader who must trust it; chunked under the transfer ceiling.",
 notes:[[1,"Progress is shown by chunk, because that is what a court clerk will receive."],[2,"The seal is the last step, with what it proves written beside it."]],
 r:function(){return gtop("Court export")+K.page(K.card('<h4>Assembling</h4><p>Handover log, calendar, messages</p>'+K.progress(72)+'<div class="kv" style="margin-top:10px"><span>Chunks</span><span>9 of 12</span><span>Entries</span><span>1,482</span><span>Size</span><span>38 MB</span></div>',"",1)+K.card(K.row({ic:"shieldcheck",title:"Seal and certify",sub:"Adds a signature the other side can verify",tone:"info",n:2}))+K.btn("Wait for it to finish",{full:true,kind:"tonal"}));}});

D("yearbook","guardian","Year book",{grp:"Guardian",since:"0.28.0",desc:"A year of her, preserved.",
 notes:[[1,"Chapters are titled from her side: things you made, things you taught me, things that happened."],[2,"Her year of colours is twelve swatches and a count, nothing else."]],
 r:function(){return gtop("Ivy, age 6")+K.page('<div style="border-radius:26px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("hills",300,150)+'</div>'+K.card(K.row({ic:"brush",title:"Things you made",sub:"31 pictures",go:true,n:1})+K.row({ic:"smile",title:"Things you taught me",sub:"12",go:true})+K.row({ic:"heart",title:"Things that happened",sub:"23",go:true}))+K.card('<h4>Her colours</h4><div class="chips">'+["#2F8FC4","#E8730C","#5AA84A","#8B6BB1","#F2B705"].map(function(c){return '<i style="width:30px;height:30px;border-radius:50%;background:'+c+'"></i>';}).join("")+'</div>',"",2));}});

D("gallery","guardian","Gallery",{grp:"Guardian",since:"0.28.0",desc:"Year-grouped works; past two thousand, paginate by era.",
 notes:[[1,"Works sit in a calm grid grouped by year. Eras appear only when there are enough to need them."]],
 r:function(){var cells="";var sc=["paper","sea","hills","night","branch","letters"];for(var i=0;i<6;i++)cells+='<div style="border-radius:18px;overflow:hidden;aspect-ratio:1;box-shadow:var(--shadow1)">'+K.scene(sc[i],150,150)+'</div>';return gtop("Gallery")+K.page(K.seg(["2026","2025","2024"],0,1)+'<div class="grid2">'+cells+'</div>');}});

D("themePicker","guardian","Theme",{grp:"Guardian",since:"0.49.19",desc:"Seven palettes by light and dark, guardian-only, backend-synced. She never sees a way to reach it. Olive is proposed as the new default.",
 notes:[[1,"Each palette card previews real UI, not a flat swatch. Olive is the proposed brand default."],[2,"Nothing changes on her device until Apply."]],
 r:function(){var P=[["olive","Olive"],["calm","Calm modern"],["warm","Warm grounded"],["playful","Soft playful"],["cozy","Deep cozy"],["bold","Bright bold"]];var cards=P.map(function(p,i){return '<div class="card" style="padding:10px;'+(i===0?"box-shadow:0 0 0 2.5px var(--pri)":"")+'"><div style="display:flex;gap:4px;margin-bottom:8px"><i style="flex:1;height:34px;border-radius:10px;background:'+K.SEEDS[p[0]].seed+'"></i><i style="flex:1;height:34px;border-radius:10px;background:'+K.SEEDS[p[0]].seed+';opacity:.45"></i><i style="flex:1;height:34px;border-radius:10px;background:'+K.SEEDS[p[0]].seed+';opacity:.2"></i></div><b style="font-size:13px">'+p[1]+'</b></div>';}).join("");
  return gtop("How Ivy’s app looks")+K.page(K.seg(["Light","Dark"],0)+'<div class="grid2"'+K.n(1)+'>'+cards+'</div>'+K.btn("Apply",{full:true,n:2}));}});
})();
