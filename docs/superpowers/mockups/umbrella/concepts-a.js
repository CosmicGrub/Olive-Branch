/* Concept screens, suites A to D: Distance, Rhythm, Voice, Village. Every one is a PROPOSAL.
   X(id, shell, title, meta, render): meta carries who it is for and what it builds on. */
(function(){
"use strict";
var K=OB,I=K.ico;
OB.meta={};
function X(id,shell,title,m,r){
 OB.meta[id]=m;
 OB.def(id,shell,title,{grp:m.suite,desc:m.desc,notes:m.notes||[],isNew:true,wide:false,r:r});
}
function top(title,o){o=o||{};return K.sb()+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function ctop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it"})});}
function face(l,o){return K.avatar(l,Object.assign({size:48},o||{}));}

/* ================================================================ A · DISTANCE */
X("twoSkies","child","Two Skies",{suite:"A",for:["mil","road","inc","sep","vil"],needs:["anx","tod"],effort:"S",builds:"The dual clock and day-part ribbon (already built); time zones only",
 rails:"P3: no location, only each person’s day-part and the sky that goes with it",
 desc:"Ivy sees her sky and Dad’s sky side by side, drawn from the two time zones. “It’s the same moon.” It makes the distance feel like one shared world instead of a number of hours.",
 funcs:["Day, dusk and night skies drawn from each person’s local time","The moon phase is the same for both, so it is shown as one moon","A sentence in her words: “Dad is asleep. It is dark where he is.”","Tapping the moon sends a small “I see it too” with no text"],
 open:"Does a shared moon ever feel cruel when Dad is somewhere with no night sky (a ship, a base)? Offer a neutral version.",
 notes:[[1,"Two panels, one frame. Day on top, night below, with the same moon crossing both."],[2,"No place names, no map, no coordinates. Only the sky."],[3,"One tap says “I see it too”. No reply is expected."]]},
 function(){return ctop("Two Skies")+K.page('<div class="card" style="padding:0;overflow:hidden"'+K.n(1)+'><div style="height:92px;position:relative">'+K.scene("hills",300,92)+'<span class="chip" style="position:absolute;left:10px;top:10px">Ivy · 7:42 AM</span></div><div style="height:92px;position:relative">'+K.scene("night",300,92)+'<span class="chip" style="position:absolute;left:10px;top:10px">Dad · 1:42 AM</span></div></div>'+
  K.card('<p style="font:800 19px/1.25 var(--font-display);margin:0;color:var(--ink)"'+K.n(2)+'>Dad is asleep. It’s dark where he is.</p><p>You can both see the same moon tonight.</p>')+K.btn("I see the moon too",{full:true,size:"lg",ic:"moon",n:3}));});

X("awayMode","guardian","Away mode",{suite:"A",for:["mil","road","inc","hosp"],needs:["anx","tod"],effort:"M",builds:"Availability, message banking, sleeps countdown, the ladder of calls",
 rails:"P2: chapters, never a streak or a “days missed” count; P9: nothing resurfaces unasked",
 desc:"One switch that tells the whole app a guardian is away until a date. Ivy sees a path home in chapters. The guardian sees what is banked, when calls can happen, and what still needs recording.",
 funcs:["“I’m away until…” with chapters: departure, settling in, halfway, coming home","Call windows built from availability and the other time zone","A checklist of banked messages by chapter, for the guardian only","Ivy’s home shows the path home, in sleeps, with no pressure","Return day: a gentle “coming home” sequence, switched on by the guardian"],
 open:"What if the date moves? Dates slip often. The path should lengthen without any blame.",
 notes:[[1,"Chapters, not a countdown to a single date. A chapter can stretch."],[2,"What is banked is shown by chapter so gaps are easy to spot."],[3,"Ivy’s side is a path with her owl on it. No numbers beyond sleeps."]]},
 function(){return top("Away mode")+K.page(K.card('<div class="row" style="padding:0"><span class="rtxt"><b style="font:800 18px var(--font-display)">Away until March 14</b><small>Ship, no calls most days</small></span>'+K.toggle(true)+'</div>',"tint")+
  K.card('<h4>The path home</h4>'+["Leaving","Settling in","Halfway","Coming home"].map(function(c,i){return K.row({ic:i<2?"check":"flag",title:c,sub:i===0?"8 messages banked":i===1?"12 banked":i===2?"Needs 6 more":"Needs recording",tone:i<2?"ok":i===2?"warn":"",n:i===0?1:0});}).join(""),"",2)+
  K.card('<h4>What Ivy sees</h4><div style="border-radius:16px;overflow:hidden">'+K.scene("hills",300,90)+'</div><p style="margin-top:8px">A path with her owl on it, and “3 sleeps until the next stop”.</p>',"",3));});

X("milestoneVault","guardian","Milestone vault",{suite:"A",for:["mil","road","inc","hosp","loss","sep"],needs:["anx"],effort:"M",builds:"Message banking, the delivery engine, the maturation ladder, sealed letters",
 rails:"P9: she can open it, it never surprises her; P1: only real recordings",
 desc:"Messages recorded ahead for moments that have not happened yet: a first lost tooth, the first day of school, a hard night, a tenth birthday. They arrive at the moment, or when she asks.",
 funcs:["Triggers: a date, a milestone she logs, or “when I ask for it”","Preview card shows exactly what she will see","“I miss Dad” button on her side plays a message from the vault","Reminders for the guardian to record the next one","Sealed until its moment; she may open early if the guardian allows"],
 open:"Who decides a moment? A child who logs “first lost tooth” herself, or the guardians? Probably both.",
 notes:[[1,"Each message has a plain-words trigger and a status."],[2,"“When I ask” is the safest trigger: she is in control."],[3,"A nudge to record the next one, for the guardian only."]]},
 function(){return top("Milestone vault")+K.page(K.banner("pri","Recorded ahead. Delivered at the right moment, or when Ivy asks.","leaf",0)+
  K.card(K.row({ic:"smile",title:"When Ivy loses a tooth",sub:"Banked · 1 min",trail:K.chip("Ready",{tone:"ok",sm:true}),n:1})+K.row({ic:"book",title:"First day of 2nd grade",sub:"Sep 8 · Banked",trail:K.chip("Ready",{tone:"ok",sm:true})})+K.row({ic:"heart",title:"When she asks for me",sub:"3 messages",trail:K.chip("Ready",{tone:"ok",sm:true}),n:2})+K.row({ic:"star",title:"Her 10th birthday",sub:"Not recorded yet",trail:K.chip("Record",{tone:"warn",sm:true})}))+
  K.card(K.row({ic:"mic",title:"Record the next one",sub:"Suggested: a hard night",n:3,go:true}),"tint"));});

X("postcard","child","Postcards",{suite:"A",for:["mil","road","inc","vil"],needs:["tod"],effort:"S",builds:"Show me, the gallery, async delivery",
 rails:"P3: a postcard says “somewhere warm”, never where",
 desc:"A parent sends a picture with a few words. It arrives as a postcard with a stamp. The stamp names a feeling of the place, never the place.",
 funcs:["Photo plus a line of text, framed as a postcard","A stamp chosen from a fixed set: warm, snowy, busy, quiet, near the sea","Kept in a postcard rack she can flip through","She can send one back by drawing on a blank card"],
 open:"Should postcards be reviewable by the other guardian first, for sensitive circumstances?",
 notes:[[1,"The stamp is a fixed picture, never a place name."],[2,"Writing back is a drawing card, no keyboard."]]},
 function(){return ctop("Postcards")+K.page('<div class="card" style="padding:10px;background:#fff9ec;transform:rotate(-1.2deg)"'+K.n(1)+'><div style="display:grid;grid-template-columns:1fr 54px;gap:8px"><div style="border-radius:12px;overflow:hidden;height:120px">'+K.scene("sea",200,120)+'</div><div style="border:2px dashed var(--accent);border-radius:10px;display:grid;place-items:center;color:var(--accent);text-align:center;font:700 11px var(--font-mono)">'+I("sun",24,1.8)+'<br>WARM</div></div><p style="font:700 16px/1.4 var(--font-body);margin:10px 4px 2px;color:var(--ink)">Saw a whale today. Thought of you.</p><small style="color:var(--ink3)">— Dad</small></div>'+K.btn("Draw one back",{full:true,size:"lg",ic:"brush",n:2}));});

X("phoneBridge","guardian","Phone bridge",{suite:"A",for:["inc","mil","vil","kin"],needs:[],effort:"L",builds:"The SMS bridge named in the product spec, message banking, the handover log",
 rails:"P8: the log is permanent; review before delivery is a family choice, not a hidden filter",
 desc:"For a parent who cannot use the app: a text and voice line into the same conversation. Ivy gets the same message either way. Built first for parents in places with limited devices, and for grandparents with only a phone.",
 funcs:["A number that texts into Ivy’s inbox, and replies come back as text","Optional guardian review before delivery, shown to the sender honestly","A weekly voice-line slot for a recorded story","Facility or carrier rules shown as a plain note on the guardian’s side"],
 open:"Rules differ by place and carrier; this needs real vendor and legal input before any promise is made.",
 notes:[[1,"The thread reads as one conversation. The sender’s channel is a small label."],[2,"If messages are reviewed first, the sender is told, never silently dropped."]]},
 function(){return top("Dad, by phone")+K.page(K.banner("info","Dad can’t use the app. His texts and voice-line stories arrive here.","phone",1)+K.bubble("Goodnight, owl.",false,"7:04 · text")+K.bubble("I read your book today. Page 3 is my favourite.",false,"7:05 · text")+K.card(K.row({ic:"mic",title:"Voice-line story",sub:"Friday 6:30 PM · 4 min",tone:"info"}),"")+K.card(K.row({ic:"shield",title:"Review before Ivy sees it",sub:"On. Mom approves first",trail:K.toggle(true),n:2})));});

/* ================================================================== B · RHYTHM */
X("oneRoutine","guardian","One routine, two houses",{suite:"B",for:["sep","blend","kin","fost"],needs:["neuro","sens","anx","tod"],effort:"M",builds:"Day-parts, the ritual of calls ending, the visual schedule in §8.4",
 rails:"P2: agreement, not scoring; nothing counts how often either house follows it",
 desc:"Two households agree on the same bedtime ritual, so the steps feel the same in both. Each house can add one thing of its own. Ivy sees the same picture strip in both places.",
 funcs:["A shared ritual: ordered steps with pictures","Each house can add one personal step (a night-light, a song)","A request to change is a proposal the other guardian accepts","Used by the child’s “first, then” strip"],
 open:"What if the houses really disagree about bedtime? The product must hold the disagreement without taking a side.",
 notes:[[1,"Steps are pictures first, words second."],[2,"“Mom agreed” is a plain status, not a vote count."],[3,"A house’s own step is marked, so nobody mistakes it for a rule."]]},
 function(){return top("Bedtime, both houses")+K.page(K.card('<div class="chips"><span class="chip ok">'+I("check",13,2.4)+' Mom agreed</span><span class="chip ok">'+I("check",13,2.4)+' Dad agreed</span></div>',"",2)+
  K.card([["Bath","droplet"],["Pajamas","smile"],["Two books","book"],["A song","volume"],["Lights out","moon"]].map(function(s,i){return K.row({ic:s[1]==="droplet"?"sparkle":s[1],title:s[0],sub:i===3?"Dad’s house adds: the owl night-light":"",n:i===0?1:(i===3?3:0),trail:'<span class="mono" style="color:var(--ink3)">'+(i+1)+'</span>'});}).join(""))+K.btn("Propose a change",{kind:"tonal",full:true,ic:"pencil"}));});

X("firstThen","child","First, then",{suite:"B",for:["neuro","sens","tod","sep","blend"],needs:["neuro","sens","tod"],effort:"S",builds:"The visual schedule strip, “what happens next”",
 rails:"No timers that scold; “done” ticks are private to her day, never totals",
 desc:"A two-card board: what happens first, what comes next. It helps children who need to see a change coming. Used for bedtime, leaving for the other house, and a call.",
 funcs:["Two big picture cards: First and Then","Tap Done and the next card slides in, calmly","A guardian can set the cards from a picture library","Reads aloud on tap"],
 open:"Pictures need a respectful, diverse library. Do we commission one, or license a symbol set?",
 notes:[[1,"Two cards, never more at once. The next one is only a peek."],[2,"Done is a big, soft tap. There is no score."]]},
 function(){return ctop("My evening")+K.page('<div class="grid2"'+K.n(1)+'><div class="card center" style="min-height:150px;border:3px solid var(--pri)"><span class="ricon" style="width:60px;height:60px;border-radius:20px">'+I("sparkle",30,1.8)+'</span><b style="font:800 18px var(--font-display)">First</b><span>Bath</span></div><div class="card center" style="min-height:150px;background:var(--surface2);box-shadow:none"><span class="ricon" style="width:60px;height:60px;border-radius:20px">'+I("book",30,1.8)+'</span><b style="font:800 18px var(--font-display)">Then</b><span>Two books</span></div></div>'+K.btn("Done",{full:true,size:"lg",ic:"check",n:2}));});

X("packingBuddy","child","Packing buddy",{suite:"B",for:["sep","blend","kin","fost"],needs:["anx","neuro","tod"],effort:"S",builds:"Exchange screen, the bag manifest",
 rails:"No pressure, no blame about forgotten things; items that are “the same at both houses” are celebrated",
 desc:"The night before an exchange, a friendly checklist of the things she wants to bring. A short list of comfort things stays the same in both houses, so something is always familiar.",
 funcs:["Her list, in pictures","A “same at both houses” group (the owl, the night-light, the blanket)","The guardian’s list of must-bring items, kept separate","A forgotten item is never an error: the other house can lend a copy"],
 open:"Comfort items that exist twice may cost money; a shared “twin” list could help families plan.",
 notes:[[1,"Her own list, her words. The guardian list is separate."],[2,"The same-at-both-houses row is the calm part of the screen."]]},
 function(){return ctop("Going to Dad’s")+K.page(K.card('<h4>My things</h4>'+K.row({ic:"smile",title:"Owl (the soft one)",trail:I("check",20,2.2),tone:"ok",n:1})+K.row({ic:"book",title:"Library book",trail:I("check",20,2.2),tone:"ok"})+K.row({ic:"sparkle",title:"Rain boots",tone:"warn"}))+K.card('<h4>Already at Dad’s</h4><div class="chips">'+K.chip("Night-light",{tone:"ok",ic:"moon"})+K.chip("Blue blanket",{tone:"ok",ic:"heart"})+K.chip("Toothbrush",{tone:"ok"})+'</div><p>These are the same in both houses.</p>',"",2));});

X("newPlace","child","Dad’s new place",{suite:"B",for:["sep","blend","mil","fost","kin"],needs:["anx","neuro","sens"],effort:"M",builds:"Show me, the gallery, shared photos",
 rails:"No street address, no coordinates; photos of rooms only",
 desc:"Before the first visit to a new home, a short photo walk: this is the door, this is your room, this is where the owl sleeps. She can change one small thing in the picture.",
 funcs:["Five to eight photos in a fixed order, taken by the guardian","Her things appear in the pictures once he adds them","She chooses where the owl sleeps, and that choice is carried out for real","A “my room is ready” stamp the guardian can send"],
 open:"A child with trauma around moves may need a slower version; guidance from a clinician would shape this.",
 notes:[[1,"A walk, not a tour with a map. Each stop is a room."],[2,"One real choice for her, made in the picture, carried out in the house."]]},
 function(){return ctop("Dad’s new place")+K.page('<div style="border-radius:24px;overflow:hidden;position:relative;box-shadow:var(--shadow2)">'+K.scene("paper",300,170)+'<span class="chip" style="position:absolute;left:12px;top:12px">'+I("home",13,2)+' Your room</span></div>'+K.card('<p style="font:700 17px/1.4 var(--font-body);margin:0;color:var(--ink)">This is your room. Where should the owl sleep?</p>',"",1)+'<div class="grid3"'+K.n(2)+'>'+["On the bed","By the window","On the shelf"].map(function(t,i){return '<div class="tile std" style="'+(i===0?"background:var(--pri);color:var(--onPri)":"")+'"><b>'+t+'</b></div>';}).join("")+'</div>');});

X("sensoryProfile","guardian","Sensory profile",{suite:"B",for:["sep","blend","kin","fost"],needs:["sens","neuro","deaf","blind"],effort:"S",builds:"Reduce motion, read-aloud, the accessibility matrix (§8.8b)",
 rails:"A guardian sets it for her device; it is a setting, never a label or a diagnosis",
 desc:"One page of sensory settings for a child’s device: the loudest sound allowed, brightness, no flashing, no motion, a quiet-corner timer. Shared by both houses so the app feels the same in both.",
 funcs:["Loudest sound allowed and a sound-off mode","Brightness ceiling and a no-flash guarantee","Motion off and haptics off","A “quiet corner” that dims the app and offers one calm activity","Saved per child, applied on every device she uses"],
 open:"Names matter: call it “how the app feels”, not “sensory needs”, so it is not a label she can see.",
 notes:[[1,"The settings describe the app, not the child."],[2,"Quiet corner is something she can open herself."]]},
 function(){return top("How the app feels")+K.page(K.card('<h4>Sound</h4>'+K.seg(["Off","Low","Medium"],1,1)+'<h4 style="margin-top:12px">Brightness</h4>'+K.progress(55))+K.card(K.row({title:"No flashing, ever",trail:K.toggle(true)})+K.row({title:"No motion",sub:"Pages simply change",trail:K.toggle(true),n:2})+K.row({title:"No buzzing",trail:K.toggle(true)}))+K.card(K.row({ic:"moon",title:"Quiet corner",sub:"She can open it herself",trail:K.toggle(true),n:3}),"tint"));});

/* =================================================================== C · VOICE */
X("feelingsWeather","child","Feelings weather",{suite:"C",for:["sep","blend","loss","hosp","kin","fost"],needs:["anx","grief","neuro"],effort:"M",builds:"The journal’s privacy rules, her colour’s “a fact, not a mood” rule",
 rails:"§8.6.4 and P7: she picks it, it is private by default, and no one ever sees a trend, a count or a flag",
 desc:"She picks a weather picture for how she feels. That is all. It stays on her device unless she chooses to send it to someone. Nobody can see a history of it.",
 funcs:["Six weather pictures, no words required","Private by default; “Show Mom”, “Show Dad” or “Keep it” each time","No history screen, no weekly summary, no alerts to anyone","Optional: the picture sits in her journal entry"],
 open:"Clinicians often want patterns; parents often want to know. This design says no by default. A child-held export for therapy, chosen by her, could be the middle path.",
 notes:[[1,"Weather, not emotions with names. It is a picture, not a label."],[2,"The default is “keep it”. Sharing is a separate, deliberate tap."],[3,"There is no chart. There is nowhere for one to live."]]},
 function(){return ctop("How is it in you?")+K.page('<div class="grid3"'+K.n(1)+'>'+[["sun","Sunny"],["cloud","Cloudy"],["moon","Quiet night"],["sparkle","Windy"],["heart","Warm"],["warn","Stormy"]].map(function(w,i){return '<div class="card center" style="min-height:92px;padding:10px;'+(i===1?"border:3px solid var(--pri)":"")+'">'+I(w[0]==="warn"?"cloud":w[0],34,1.5)+'<b style="font-size:12px">'+w[1]+'</b></div>';}).join("")+'</div>'+K.banner("pri","Only you can see this. Nobody keeps a list.","lock",3)+'<div class="btns"'+K.n(2)+'>'+K.btn("Keep it",{size:"lg",kind:"tonal"})+K.btn("Show Mom",{size:"lg"})+'</div>');});

X("worryBox","child","Worry box",{suite:"C",for:["sep","blend","loss","hosp","kin","fost"],needs:["anx","grief"],effort:"M",builds:"Journal, doodle desk, the private-space rules",
 rails:"P7: the contents are hers; the product never reads them to anyone",
 desc:"A place to put a worry as a drawing or a few words. She decides what happens next: keep it in the box, share it with a person she chooses, or let it float away.",
 funcs:["Write, draw or say a worry into the box","Three endings: keep, share with a chosen helper, float away","“Float away” deletes it for real, with a soft animation she controls","If she shares with a helper, only that helper sees it"],
 open:"A worry that sounds like danger. The product cannot read it, so the “I need help” button (next) is the real safety path.",
 notes:[[1,"Three endings, equally easy. “Let it float away” really deletes."],[2,"Nothing here is read, scored or summarised."]]},
 function(){return ctop("My worry box",{noSpeak:false})+K.page('<div class="card center" style="min-height:130px;background:var(--surface2);box-shadow:none"><span class="ricon" style="width:70px;height:70px;border-radius:24px">'+I("lock",32,1.6)+'</span><b>Put a worry in the box</b></div><div class="grid3"'+K.n(1)+'>'+[["pencil","Write"],["brush","Draw"],["mic","Say it"]].map(function(b){return '<div class="tile std" style="padding:14px 6px"><span class="tic" style="width:46px;height:46px">'+I(b[0],22,1.9)+'</span><b>'+b[1]+'</b></div>';}).join("")+'</div>'+K.sectionLabel("Then you choose")+K.card(K.row({ic:"lock",title:"Keep it in the box"})+K.row({ic:"users",title:"Share with a helper",go:true})+K.row({ic:"cloud",title:"Let it float away",sub:"It’s gone for good",n:2})));});

X("needHelp","child","I need help",{suite:"C",for:["sep","blend","loss","hosp","kin","fost","vil"],needs:["anx","grief","teen"],effort:"L",builds:"The P7 caveat: “build the escalation path; do not build the window”; trusted adults; the come-back signal",
 rails:"P7: it routes to a human she picks. The product shows no one her words. Needs clinical and legal review before it is built",
 desc:"One calm button that is always there. It asks who she would like to talk to, from a list of helpers her guardians set up with her, and connects her. If she is older, it can offer a listening line chosen by the family. It is a way to reach a person, not a report about her.",
 funcs:["Always-available button in the same place, never hidden","“Who would you like to talk to?” shows her helpers as faces","Connects by call or message to the person she chooses","A grown-up helper is told she reached out, nothing more","For teens: a crisis or listening line the guardians pick in advance"],
 open:"This is the hardest design in the set. What a helper is told, what guardians are told, and what happens when a helper cannot be reached all need clinicians and a lawyer. Do not ship without both.",
 notes:[[1,"Always the same place, always one tap, never a menu."],[2,"Her helpers are faces she knows. She chooses, not an algorithm."],[3,"Nothing she types or says is shown to a parent."]]},
 function(){return K.sb()+K.page('<div class="center" style="min-height:520px"><span class="ricon" style="width:70px;height:70px;border-radius:24px;background:var(--priC)">'+I("heart",34,1.7)+'</span><div class="big" style="font-size:25px">Who would you like to talk to?</div><div class="grid3" style="width:100%"'+K.n(2)+'>'+[["N","Nana"],["A","Aunt Mia"],["T","Mr. Reyes"]].map(function(p){return '<div style="display:grid;justify-items:center;gap:6px">'+face(p[0],{size:68,ring:p[0]==="N"})+'<b style="font-size:13px">'+p[1]+'</b></div>';}).join("")+'</div>'+K.btn("Talk now",{size:"lg",ic:"phone",n:1})+'<small style="color:var(--ink3)"'+K.n(3)+'>Only they will know you asked.</small></div>');});

X("myHelpers","guardian","Ivy’s helpers",{suite:"C",for:["sep","blend","loss","hosp","kin","fost","vil"],needs:["anx","grief","teen"],effort:"M",builds:"Trusted adult role, the family graph, sitters",
 rails:"Chosen with her, not for her; each helper agrees; the list can grow with the maturation ladder",
 desc:"Where guardians set up, together with Ivy, the grown-ups she can reach on her own: a grandparent, a favourite aunt, a teacher or counsellor. Each one has said yes.",
 funcs:["Invite a helper; they accept and see only what the role allows","Ivy chooses her helpers from the people her guardians approve","The list grows as she does: more helpers at 10, a listening line at 13","Helpers can be paused for a time by a guardian, with a reason shown to the helper"],
 open:"Disagreement: what if one guardian does not want a particular person on the list? A two-guardian rule is needed.",
 notes:[[1,"Each helper has said yes. Nobody is added without knowing."],[2,"She sees faces and names she uses, not roles."]]},
 function(){return top("Ivy’s helpers")+K.page(K.banner("pri","Choose these with Ivy. Each person says yes first.","users",0)+K.card(K.row({av:face("N",{size:42}),title:"Nana",sub:"Grandmother · said yes",trail:K.chip("Helper",{tone:"ok",sm:true}),n:1})+K.row({av:face("A",{size:42,tone:"accent"}),title:"Aunt Mia",sub:"Said yes",trail:K.chip("Helper",{tone:"ok",sm:true})})+K.row({av:face("T",{size:42}),title:"Mr. Reyes",sub:"Counsellor · waiting for yes",trail:K.chip("Waiting",{tone:"warn",sm:true})}))+K.btn("Invite someone",{kind:"tonal",full:true,ic:"plus",n:2}));});

X("symbols","child","Say it with symbols",{suite:"C",for:["sep","blend","kin","fost","vil"],needs:["aac","tod","deaf"],effort:"L",builds:"Messaging pipeline, read-aloud, the symbol library",
 rails:"The symbols are hers; messages are never rewritten by a model",
 desc:"A symbol board for a child who speaks little or not at all. She builds a message from pictures; the other person sees both the pictures and a plain sentence. Replies can come the same way.",
 funcs:["Core words board (I, want, more, stop, help, hurt, tired, play) plus a personal board","Messages show pictures and a sentence together, for any reader","Grandparents get a simple view, with the sentence large","Pairs with a communication therapist’s existing board where the family already has one"],
 open:"Symbol sets are licensed and culturally specific. A partnership with a speech-language organisation is probably the right route.",
 notes:[[1,"Big picture buttons, one tap each. Words are small."],[2,"The sentence is built for the reader, not guessed by a model."]]},
 function(){return ctop("Tell Mom")+K.page(K.card('<div style="display:flex;gap:8px;min-height:54px;align-items:center"'+K.n(2)+'>'+["I","want","drink"].map(function(w){return '<span class="card center" style="padding:6px 12px;border-radius:16px;min-height:50px"><b>'+w+'</b></span>';}).join("")+'</div>','',2)+'<div class="grid4"'+K.n(1)+'>'+[["heart","love"],["smile","happy"],["warn","hurt"],["moon","tired"],["dice","play"],["plus","more"],["x","stop"],["hand","help"]].map(function(s){return '<div class="card center" style="min-height:70px;padding:8px;border-radius:18px">'+I(s[0],26,1.7)+'<small style="font-size:11px">'+s[1]+'</small></div>';}).join("")+'</div>'+K.btn("Send",{full:true,size:"lg",ic:"send"}));});

/* ================================================================= D · VILLAGE */
X("grandCorner","guardian","Grandparent corner",{suite:"D",for:["vil","kin","sep","mil","blend"],needs:["tod","deaf","bil"],effort:"M",builds:"The Trusted Adult role (calls and messages only), the SMS bridge, big-target accessibility",
 rails:"Scoped: calls and messages only. No calendar edit, no settings (§8.1)",
 desc:"A very simple version of the app for a grandparent or older relative. Four huge buttons, large text, and a phone-line fallback. It never shows anything they could break.",
 funcs:["Four buttons: Call Ivy, Read to Ivy, Send a picture, Ivy’s news","Text size and contrast chosen at setup, not buried","A phone-line fallback for days the app is too much","A setup done by a family member, with a one-page printed guide"],
 open:"Many grandparents are also primary carers. When a grandparent is the guardian, the full app must stay available, with the same large-target mode as an option.",
 notes:[[1,"Four buttons, large. Nothing else on the screen."],[2,"A phone line is always there as a fallback, not a failure."]]},
 function(){return K.sb()+K.top({logo:true,title:"Hello, Nana"})+K.page('<div style="display:grid;gap:10px">'+[["video","Call Ivy"],["book","Read to Ivy"],["image","Send a picture"],["chat","Ivy’s news"]].map(function(b,i){return '<div class="card" style="display:flex;gap:14px;align-items:center;min-height:84px;'+(i===0?"background:var(--pri);color:var(--onPri)":"")+'"'+(i===0?K.n(1):"")+'><span class="ricon" style="width:56px;height:56px;border-radius:18px;'+(i===0?"background:rgba(255,255,255,.2);color:inherit":"")+'">'+I(b[0],30,1.8)+'</span><b style="font:800 22px var(--font-display)">'+b[1]+'</b></div>';}).join("")+'</div>'+K.banner("info","Prefer the phone? Call 555-0199 and press 1.","phone",2));});

X("familyTree","child","My people",{suite:"D",for:["sep","blend","kin","fost","vil","loss"],needs:["tod","neuro","anx"],effort:"M",builds:"The family graph, kinship, the showcase and gallery",
 rails:"The child names her own people; the tree never implies a hierarchy or a legal status she did not choose",
 desc:"A living picture of the people in her life, drawn the way she sees them: parents in two houses, step-parents, half-siblings, grandparents, cousins, a favourite neighbour. Each face is a tap to say hi or hear their voice.",
 funcs:["Faces with the name she uses","Grouped by home, not by law: “Mom’s house”, “Dad’s house”, “Nana’s”","Tap to say hi, hear a recorded name, or start a call","Her family can be drawn however it is: the guardian adds, she arranges"],
 open:"Foster and kinship families often have changing members. The tree must allow people to leave without erasing history she wants to keep.",
 notes:[[1,"Groups are houses, not diagrams of law."],[2,"Each face is one tap away from a call or a hello."]]},
 function(){return ctop("My people")+K.page(K.card('<div class="chips">'+K.chip("Mom’s house",{tone:"pri"})+K.chip("Dad’s house")+K.chip("Nana’s")+'</div>'+'<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:12px"'+K.n(1)+'>'+[["M","Mom"],["J","Jordan"],["L","Leo"],["N","Nana"],["A","Aunt Mia"],["P","Pip (dog)"]].map(function(p,i){return '<div style="display:grid;justify-items:center;gap:5px">'+face(p[0],{size:60,tone:i%2?"accent":"",ring:i===0})+'<b style="font-size:12px;text-align:center">'+p[1]+'</b></div>';}).join("")+'</div>')+K.btn("Say hi to someone",{full:true,size:"lg",ic:"hand",n:2}));});

X("stepWelcome","guardian","Welcome, Jordan",{suite:"D",for:["blend","sep"],needs:[],effort:"M",builds:"The Step-parent role (scoped by the inviting guardian), invitations",
 rails:"Scoped by the guardian who invited them; nothing about the other house is widened",
 desc:"What a step-parent sees first. It says plainly what they can and cannot do, and gives them a short, kind way to get to know the child.",
 funcs:["A plain list of what they can see and do, set by the inviting guardian","“Getting to know Ivy”: her favourite things, what helps at bedtime, what to avoid","A first message the guardian can help them write","A review at one month: widen, keep, or narrow"],
 open:"The line between supportive and overstepping differs for every family. The scope must be easy to change without drama.",
 notes:[[1,"Clear, not cold: what you can do, what you can’t, and why."],[2,"Getting-to-know cards are written by the guardians, not guessed."]]},
 function(){return top("Welcome, Jordan")+K.page(K.card('<h4>You can</h4>'+K.row({ic:"check",title:"Call and message Ivy",tone:"ok"})+K.row({ic:"check",title:"See the calendar and pickup times",tone:"ok"})+'<h4 style="margin-top:8px">You can’t</h4>'+K.row({ic:"x",title:"Change settings or schedules",tone:"bad",n:1})+K.row({ic:"x",title:"See the other house’s notes",tone:"bad"}))+K.card('<h4>Getting to know Ivy</h4><p>Loves owls. Likes the hall light on. Needs a minute before new people.</p>',"tint",2));});

X("siblingSpace","child","Sibling space",{suite:"D",for:["blend","sep","kin","fost"],needs:["tod"],effort:"M",builds:"Siblings screen (links never widen authority), shared canvas, games",
 rails:"Both guardians consent; a link lets the children play, it grants no adult access",
 desc:"A little shared room for brothers and sisters who live in different houses. They can draw together, play a game, or leave each other a picture, with both sets of guardians agreeing first.",
 funcs:["A shared canvas and a shared game table","A “leave a picture” shelf","Each guardian can pause it without removing the link","Works across half- and step-siblings"],
 open:"Different guardians, different rules. A single shared set of time limits would be the fairest, but it needs both sides to agree.",
 notes:[[1,"Both guardians have said yes. The chip shows it."],[2,"A shared canvas is the simplest thing that is also lovely."]]},
 function(){return ctop("Ivy and Leo")+K.page('<div class="chips"><span class="chip ok">'+I("check",13,2.4)+' Both houses agreed</span></div><div style="background:#fff;border-radius:24px;height:200px;box-shadow:var(--shadow1);position:relative;overflow:hidden"'+K.n(2)+'><svg viewBox="0 0 200 200" width="100%" height="100%"><path d="M20 140 C50 60 100 160 160 70" fill="none" stroke="var(--pri)" stroke-width="7" stroke-linecap="round"/><circle cx="150" cy="150" r="18" fill="var(--accent)"/></svg><span class="av" style="position:absolute;left:10px;bottom:10px;width:34px;height:34px;font-size:15px;background:var(--priC);color:var(--onPriC)">I</span><span class="av accent" style="position:absolute;right:10px;bottom:10px;width:34px;height:34px;font-size:15px">L</span></div>'+K.btn("Play a game",{kind:"tonal",full:true,ic:"dice",n:1}));});

X("sitterPass","guardian","Sitter pass",{suite:"D",for:["sep","blend","vil","kin","road"],needs:["ill","sens","neuro"],effort:"S",builds:"The Sitter role (time-boxed link), the emergency card, medication log",
 rails:"Auto-expires; sees only what a sitter needs",
 desc:"A link for a babysitter, a neighbour or a relative for one evening. It shows the emergency card, the bedtime routine and the medication log, and it disappears on its own.",
 funcs:["Pick a window; the link works only inside it","Shows the one-page emergency card and the bedtime ritual","Can log a dose given, with a time","Ends by itself and tells the guardian it was opened"],
 open:"A sitter who needs to reach a guardian across time zones: the pass should show the best contact times.",
 notes:[[1,"The window is the whole point. It ends without anyone remembering to end it."]]},
 function(){return top("Sitter pass")+K.page(K.card('<div class="row" style="padding:0"><span class="rtxt"><b style="font-size:17px">Friday 6:00–10:00 PM</b><small>For Aunt Mia</small></span>'+K.chip("Expires itself",{tone:"warn",sm:true})+'</div>',"",1)+K.card('<h4>Shows</h4>'+K.row({ic:"shield",title:"Emergency card",tone:"ok"})+K.row({ic:"moon",title:"Bedtime ritual",tone:"ok"})+K.row({ic:"pill",title:"Medicine log",tone:"ok"}))+K.btn("Send the link",{full:true,ic:"send",n:2}));});

X("schoolBridge","guardian","School bridge",{suite:"D",for:["sep","blend","kin","fost","vil"],needs:["school","neuro"],effort:"M",builds:"Homework, calendar, the school layer (already specified)",
 rails:"No grades, no behaviour reports; a teacher sees only what the guardians share",
 desc:"One place where a teacher’s notes reach both houses at once: the test on Friday, library day, a field trip form. It stops information from reaching only one home.",
 funcs:["A teacher posts a note; both households see it","Calendar items appear on both calendars with a source label","Homework photos can be shared with a tutor circle (a grandparent, an aunt)","Guardians decide what the school sees"],
 open:"Schools use many systems. Start with a forwarding address that turns an email into a note.",
 notes:[[1,"The same note reaches both homes at once."],[2,"Nothing about grades or behaviour is carried."]]},
 function(){return top("From school")+K.page(K.card(K.row({ic:"book",title:"Spelling test Friday",sub:"Ms. Alvarez · both homes",tone:"info",n:1})+K.row({ic:"calendar",title:"Library day Thursday",sub:"Bring the book"})+K.row({ic:"file",title:"Field trip form",sub:"Due Monday · needs a signature",tone:"warn"}))+K.banner("pri","Forward a school email to this family’s address and it appears here.","mail",2));});
})();
