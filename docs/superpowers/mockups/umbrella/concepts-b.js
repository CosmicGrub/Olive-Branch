/* Concept screens, suites E to I: Together, Care, Growing, Circle, and the Family Compass that ties them together. */
(function(){
"use strict";
var K=OB,I=K.ico,X=null;
function def(id,shell,title,m,r){OB.meta[id]=m;OB.def(id,shell,title,{grp:m.suite,desc:m.desc,notes:m.notes||[],isNew:true,r:r});}
function top(title,o){o=o||{};return K.sb()+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function ctop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it"})});}
function face(l,o){return K.avatar(l,Object.assign({size:48},o||{}));}
function vid(label,tone){return '<div style="position:relative;border-radius:20px;overflow:hidden;background:linear-gradient(160deg,'+(tone||"#2a3f55")+',#121b26);height:100%;min-height:90px;display:grid;place-items:center"><span class="av" style="width:44px;height:44px;font-size:18px;background:rgba(255,255,255,.14);color:#fff">'+label+'</span></div>';}

/* ================================================================ E · TOGETHER */
def("cookAlong","guardian","Cook along",{suite:"E",for:["sep","mil","road","vil","kin","blend"],needs:["tod","neuro","bil"],effort:"M",builds:"The cook-along module already named in the session runtime, the shared pane, the call",
 rails:"Grown-up steps are marked; the child only ever sees steps that are safe for her",
 desc:"Two kitchens, one recipe. Step cards stay in sync, two small video tiles show each cook, and every step says who does it: a kid step, a together step, or a grown-up step.",
 funcs:["Recipe step cards in sync on both devices","Each step tagged: kid, together, grown-up (knives and hot things)","Timers visible to both","Finished dish photo goes to the gallery and the year book","Recipes can be a grandparent’s, with their voice reading the steps"],
 open:"Safety: a child alone with a hot stove is the real risk. The product should never encourage an unsupervised step.",
 notes:[[1,"Two small video tiles keep the feeling of cooking together."],[2,"The tag on each step says who does it."],[3,"A grown-up step is shown, but locked for the child."]]},
 function(){return top("Nana’s pancakes")+K.page('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;height:92px"'+K.n(1)+'>'+vid("N","#4a3a2a")+vid("I","#2a3f55")+'</div>'+K.card('<div class="chips" style="margin-bottom:6px">'+K.chip("Step 2 of 6")+K.chip("Kid step",{tone:"ok",ic:"smile"})+'</div><p style="font:800 19px/1.3 var(--font-display);margin:0;color:var(--ink)"'+K.n(2)+'>Stir the batter until there are no lumps.</p>')+K.card(K.row({ic:"lock",title:"Next: Flip the pancakes",sub:"Grown-up step",tone:"warn",n:3})));});

def("gardenAlong","child","Garden along",{suite:"E",for:["sep","mil","road","vil","kin"],needs:["tod","anx"],effort:"S",builds:"The gallery, show me, collections with no denominator",
 rails:"P2: no growth score, no “keep it alive” pressure; a plant that dies is simply part of the story",
 desc:"Ivy and Dad each plant the same seed. A shared timeline shows both pots. There is nothing to win: they just watch.",
 funcs:["Photo timeline of two pots","A day marker, never a streak","“Water together” is a call, not a task","A seed packet picture goes to the year book"],
 open:"If one plant dies, the message must be kind and offer a second go.",
 notes:[[1,"Two pots, two homes, one picture."],[2,"The timeline is a record, not a target."]]},
 function(){return ctop("Our beans")+K.page('<div class="grid2"'+K.n(1)+'><div class="card center" style="min-height:130px;padding:8px"><span style="font-size:44px">🌱</span><b>Ivy’s pot</b><small>Day 12</small></div><div class="card center" style="min-height:130px;padding:8px"><span style="font-size:44px">🌱</span><b>Dad’s pot</b><small>Day 12</small></div></div>'+K.card('<div class="row" style="padding:0"><span class="rtxt"><b>Both sprouted</b><small>A picture for the book?</small></span>'+K.btn("Keep",{size:"sm",kind:"tonal"})+'</div>',"tint",2)+K.btn("Water together",{full:true,size:"lg",ic:"video"}));});

def("buildAlong","child","Build along",{suite:"E",for:["sep","mil","road","vil","kin"],needs:["neuro","tod"],effort:"M",builds:"Shared pane, show me, the camera capture",
 rails:"No remote control (P11): each person builds their own; they look together",
 desc:"Blocks, a paper craft or a puzzle with the same instructions at both houses. Step pictures stay in sync, and a “show me” button shows how far along each of them is.",
 funcs:["Instruction steps shared and in sync","Each person builds their own; no one touches the other’s screen","“Show me” sends a photo of the current step","The finished object photo goes to the gallery"],
 open:"Matching kits cost money. Free paper-craft templates may be the right start.",
 notes:[[1,"Everyone builds their own, so no one takes over."],[2,"Show me is one tap, one photo."]]},
 function(){return ctop("Paper boat")+K.page(K.card('<div style="height:96px;border-radius:14px;overflow:hidden">'+K.scene("paper",300,96)+'</div><p style="font:800 18px/1.3 var(--font-display);margin:8px 0 0;color:var(--ink)"'+K.n(1)+'>Step 3: Fold the corners to the middle.</p>')+'<div class="btns"'+K.n(2)+'>'+K.btn("Show Dad",{kind:"tonal",ic:"camera",size:"lg"})+K.btn("Next step",{ic:"arrowR",size:"lg"})+'</div>');});

def("musicAlong","child","Music along",{suite:"E",for:["sep","mil","road","vil","kin","blend"],needs:["tod","sens","neuro"],effort:"M",builds:"Co-listen module, shared playlist, rhythm games",
 rails:"P1: songs are real recordings or live voices, never a made-up parent voice",
 desc:"A shared playlist called “our songs” that both houses add to, and a clap-along beat game that stays in time over a call.",
 funcs:["A playlist each adds to, with who added each song","A clap-along game that keeps both devices on the same beat","A “song of the week” for the family","Lyric cards for songs in her home language"],
 open:"Music licensing. Start with tracks the family already has and a small library of cleared songs.",
 notes:[[1,"Each song shows who picked it."],[2,"The beat circles keep time together with no one being scored."]]},
 function(){return ctop("Our songs")+K.page(K.card(K.row({ic:"volume",title:"You Are My Sunshine",sub:"Added by Nana",n:1,trail:I("play",20,2)})+K.row({ic:"volume",title:"Twinkle, Twinkle",sub:"Added by Ivy",trail:I("play",20,2)})+K.row({ic:"volume",title:"Dad’s drum song",sub:"Added by Dad",trail:I("play",20,2)}))+K.card('<div class="center" style="min-height:0"><div style="display:flex;gap:12px">'+[0,1,2,3].map(function(i){return '<span style="width:'+(i===1?58:44)+'px;height:'+(i===1?58:44)+'px;border-radius:50%;background:'+(i===1?"var(--pri)":"var(--priC)")+'"></span>';}).join("")+'</div><b>Clap with Dad</b></div>',"tint",2));});

def("storyStudio","guardian","Bedtime story studio",{suite:"E",for:["mil","road","inc","sep","vil","kin","hosp"],needs:["tod","anx","bil"],effort:"M",builds:"Message banking, the storyteller, shared reading",
 rails:"P1: only the real parent’s real voice; the studio never generates a voice",
 desc:"Record a picture book page by page, in your own voice, in your own time. The pages turn on their own at bedtime, with your voice reading, and she can replay any page.",
 funcs:["Record page by page with a simple waveform","Pick a book from the library or photograph your own","The finished story sits on a shelf she can reach","Bilingual: record the same story twice","Read-aloud of one book, many nights: “Page 3 tonight”"],
 open:"Copyright for photographed books. Public-domain titles first, and a path for publishers who permit it.",
 notes:[[1,"One record button per page. Nothing else competes."],[2,"The story is hers to replay as often as she likes."]]},
 function(){return top("Record a story")+K.page(K.card('<div class="row" style="padding:0"><span class="rtxt"><b>The owl and the moon</b><small>4 of 6 pages recorded</small></span></div>'+K.progress(66)) +'<div class="grid3"'+K.n(2)+'>'+["1","2","3","4","5","6"].map(function(p,i){return '<div class="card center" style="min-height:80px;padding:6px;'+(i<4?"border-color:var(--ok)":"")+'"><b>'+p+'</b><small style="color:var(--ink3)">'+(i<4?"✓":"")+'</small></div>';}).join("")+'</div>'+K.card('<div class="center" style="min-height:0;padding:4px"><button style="width:70px;height:70px;border-radius:50%;border:0;background:var(--bad);color:#fff" aria-label="Record"'+K.n(1)+'>'+I("mic",30,1.8)+'</button><small>Record page 5</small></div>'));});

/* ==================================================================== F · CARE */
def("careBinder","guardian","Care binder",{suite:"F",for:["ill","hosp","sep","blend","kin","fost"],needs:["ill","neuro","aac"],effort:"M",builds:"Meds and care, the emergency card, sitter pass",
 rails:"Between guardians only; shared outward only through a time-boxed link; never on the child’s device",
 desc:"One organised place for a child’s medical life: conditions, medicines, appointments, contacts, allergies and what to do in an emergency. Both houses keep it, and a caregiver can see a short version for a few hours.",
 funcs:["Sections for conditions, medicines, appointments, contacts and allergies","Appointment reminders with who is taking her","A short, printable summary for a sitter or an ER","A time-boxed link for a caregiver, a school nurse, a grandparent","A visit note after each appointment, shared between guardians"],
 open:"Medical data is highly sensitive and may fall under health-privacy rules in some places. Legal review is a requirement.",
 notes:[[1,"One page per child. Both houses see exactly the same."],[2,"The short version is what a caregiver gets, and for how long."]]},
 function(){return top("Ivy’s care binder")+K.page(K.card(K.row({ic:"heart",title:"Conditions",sub:"Asthma · cashew allergy",go:true,n:1})+K.row({ic:"pill",title:"Medicines",sub:"2 active",go:true})+K.row({ic:"calendar",title:"Appointments",sub:"Pulmonologist · Oct 22",go:true})+K.row({ic:"phone",title:"Contacts",sub:"4 people",go:true}))+K.card(K.row({ic:"shield",title:"Share a short version",sub:"For 6 hours",go:true,n:2}),"tint"));});

def("hospitalMode","child","Hospital mode",{suite:"F",for:["hosp","ill"],needs:["ill","anx","sens"],effort:"M",builds:"Child home hierarchy, visual schedule, calls, quiet activities (§9.12)",
 rails:"No health scoring; no mood tracking; guardian-set only",
 desc:"When Ivy is in the hospital, or a parent is, her home becomes calmer and smaller: today’s plan in pictures, who is visiting, a quiet game, and a big call button.",
 funcs:["A “today in the hospital” picture strip (tests, rest, visitors)","Who is coming, when, shown as faces","Low-energy activities: colouring, stories, music","A large call button to the person she misses","Switches on and off by a guardian, no menus for her"],
 open:"Hospitals have their own routines and devices rules. Co-design with a child-life specialist would make this real.",
 notes:[[1,"Everything shrinks to what matters today."],[2,"Visitors are faces with times, so there are no surprises."],[3,"One big call button, always."]]},
 function(){return K.sb()+K.top({logo:true,eyebrow:"Wednesday",title:"Today"})+K.page(K.card('<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;text-align:center"'+K.n(1)+'>'+[["clock","Blood test"],["moon","Rest"],["users","Nana at 2"]].map(function(s){return '<div style="display:grid;justify-items:center;gap:4px"><span class="ricon" style="width:48px;height:48px;border-radius:16px">'+I(s[0],24,1.8)+'</span><small style="font-weight:700">'+s[1]+'</small></div>';}).join("")+'</div>')+K.card(K.row({av:face("N",{size:42}),title:"Nana is coming",sub:"At 2 o’clock",n:2}),"")+'<div class="grid2">'+K.tile("feat",{ic:"brush",title:"Colour"})+K.tile("feat",{ic:"book",title:"Stories"})+'</div>'+K.btn("Call Mom",{full:true,size:"lg",ic:"video",n:3}));});

def("explainerCards","child","When something hard happens",{suite:"F",for:["hosp","loss","sep","kin","fost","ill"],needs:["anx","grief","tod"],effort:"M",builds:"Storyteller (guardian-reviewed), story library, the book",
 rails:"P1: no synthetic parent; a guardian reviews every card before she sees it; questions go to a person, not a model",
 desc:"Short, gentle picture cards that explain hard things in her words: “Mom is in the hospital”, “Our family is changing”, “Someone has died”. A guardian picks and edits them first. She can leave a question that a person answers.",
 funcs:["A library of reviewed explainer sets, by topic and age","A guardian edits the words and adds a family photo","She can leave a question; a guardian answers in their own words","Cards can be read together, using Read together"],
 open:"This needs real child-development and clinical review for every set. Do not write them without that.",
 notes:[[1,"One idea per card. Pictures first."],[2,"A question box goes to a grown-up, never to a machine."]]},
 function(){return ctop("About Mom’s stay")+K.page('<div style="border-radius:24px;overflow:hidden">'+K.scene("hills",300,120)+'</div>'+K.card('<p style="font:800 19px/1.35 var(--font-display);margin:0;color:var(--ink)"'+K.n(1)+'>Mom is in the hospital so the doctors can help her feel better.</p>')+'<div class="btns">'+K.btn("Back",{kind:"tonal",ic:"arrowL",size:"lg"})+K.btn("Next",{ic:"arrowR",size:"lg"})+'</div>'+K.card(K.row({ic:"chat",title:"I have a question",sub:"A grown-up will answer",go:true,n:2}),"tint"));});

def("appointmentPrep","child","Doctor day",{suite:"F",for:["ill","hosp","sep"],needs:["anx","neuro","sens","tod"],effort:"S",builds:"Social-story format, the first-then board",
 rails:"No scores; she can skip any step",
 desc:"A picture story of what a visit will be like: the waiting room, the scale, the stethoscope. At the end she can record a few questions to bring.",
 funcs:["A step-by-step story with real photos of the actual clinic","“What I might feel” with no right answer","A place for her questions, as voice notes","A comfort item to bring, chosen by her"],
 open:"Photos of real clinics need the clinic’s permission.",
 notes:[[1,"Pictures of the real place, so it is not a surprise."],[2,"Her questions are saved for the visit."]]},
 function(){return ctop("Doctor day")+K.page('<div style="border-radius:22px;overflow:hidden">'+K.scene("paper",300,130)+'</div>'+K.card('<p style="font:800 18px/1.35 var(--font-display);margin:0;color:var(--ink)">First we wait in a room with books.</p>',"",1)+K.card(K.row({ic:"mic",title:"My questions",sub:"2 saved",go:true,n:2})+K.row({ic:"heart",title:"What will I bring?",sub:"The owl",go:true})));});

/* ================================================================== G · GROWING */
def("timeCapsule","guardian","Time capsule",{suite:"G",for:["mil","road","inc","sep","blend","loss","vil","kin","fost"],needs:["grief","anx"],effort:"M",builds:"Sealed letters, the maturation ladder, the year book, preservation",
 rails:"P9: she opens it, it never resurfaces; P1: only real recordings and writing",
 desc:"Letters, photos and recordings sealed for a future age: 13, 16, 18. They open at her rungs on the maturation ladder, or earlier if a guardian allows. Anyone in her village can add one.",
 funcs:["Seal for an age, a date or a rung","Add from any helper, with the family’s approval","Sealed contents are hidden from everyone, including guardians","She may open early only with a guardian’s yes","A new capsule can be started at any birthday"],
 open:"If a family’s situation changes, who owns a capsule? It should always belong to the child.",
 notes:[[1,"Each capsule opens at a rung she is already growing toward."],[2,"Sealed means sealed. The guardian who wrote it can’t peek either."]]},
 function(){return top("Time capsule")+K.page(K.card('<div class="row" style="padding:0"><span class="ricon" style="width:48px;height:48px">'+I("lock",24,1.8)+'</span><span class="rtxt"><b>Opens when Ivy turns 13</b><small>7 letters · 3 recordings</small></span></div>',"",1)+K.card(K.row({av:face("D",{size:38,tone:"accent"}),title:"Dad’s letter",sub:"Sealed · added Sep 2026"})+K.row({av:face("N",{size:38}),title:"Nana’s recipe",sub:"Sealed"})+K.row({av:face("M",{size:38}),title:"Mom’s voice note",sub:"Sealed"}))+K.btn("Add to the capsule",{full:true,ic:"plus",n:2}));});

def("firstTimes","guardian","First times",{suite:"G",for:["sep","mil","road","inc","blend","vil"],needs:["anx"],effort:"S",builds:"Year book, gallery, show me",
 rails:"Opt in; never a checklist or a scoreboard; she is never compared",
 desc:"A tender log of firsts: the first tooth, first bike ride, first sleepover. Either house can add a moment with a photo, and it flows into the year book as a chapter.",
 funcs:["One-tap “a first happened” with a photo","Either house adds; both see","Becomes a chapter in the year book","Never shows a list of firsts she has not had yet"],
 open:"Families who miss firsts may find the list painful. It must be a record of what happened, never a to-do.",
 notes:[[1,"Only what happened is shown. There is no list of things to do."]]},
 function(){return top("First times")+K.page(K.card(K.row({ic:"smile",title:"First lost tooth",sub:"Mom’s house · Sep 12",n:1,tone:"ok"})+K.row({ic:"star",title:"First time riding a bike",sub:"Dad’s house · Aug 3",tone:"ok"})+K.row({ic:"moon",title:"First sleepover",sub:"Nana’s · July 18",tone:"ok"}))+K.btn("A first happened",{full:true,ic:"plus",n:2})+K.banner("pri","These become a chapter in her year book.","book",0));});

def("memoryBox","child","Memory box",{suite:"G",for:["loss"],needs:["grief","anx","tod"],effort:"M",builds:"Gallery, preserved messages, Year book",
 rails:"P1: only real recordings, photos and writing of the person; no pretend voices or faces. P9: she chooses when to visit",
 desc:"A quiet place for a child who has lost someone: real photos, real voice messages, a recipe in their handwriting. She goes when she wants. The app never brings it up on its own.",
 funcs:["Real voice messages and photos only, added by the family","She opens it on her own; nothing resurfaces","A guardian can add, and a helper can too","Anniversaries are a family choice, off by default"],
 open:"Grief support is specialised. Partnering with a bereavement organisation, and offering families a path to professional help, matters more than any feature here.",
 notes:[[1,"Real things only. A banner says so, in her words."],[2,"No reminders, no “on this day”."]]},
 function(){return ctop("Mom’s box")+K.page(K.banner("pri","These are real. Mom made every one.","heart",1)+'<div class="grid2">'+[["night","Mom reading"],["hills","Our garden"]].map(function(s){return '<div class="card" style="padding:0;overflow:hidden"><div style="height:80px">'+K.scene(s[0],150,80)+'</div><div style="padding:8px 10px"><b style="font-size:13px">'+s[1]+'</b></div></div>';}).join("")+'</div>'+K.card(K.row({ic:"mic",title:"Mom singing",sub:"A voice message",trail:I("play",20,2),n:2}))+'<p style="text-align:center;color:var(--ink3)">It will be here whenever you want it.</p>');});

def("pencilMarks","guardian","Growing marks",{suite:"G",for:["sep","mil","road","vil","blend"],needs:[],effort:"S",builds:"Gallery, Year book",
 rails:"Neutral: a record of her own growth only, never a comparison to a chart or another child",
 desc:"The doorframe pencil marks, kept on a screen: a photo of her against the wall, with the date. Both houses add one.",
 funcs:["A photo of her next to a mark, with the date","Marks from both houses on one timeline","No percentiles, no charts, no “average”","Appears in the year book"],
 open:"Avoid anything that reads as a health measurement.",
 notes:[[1,"Dates only. No numbers that mean anything medical."]]},
 function(){return top("Growing marks")+K.page('<div class="card" style="padding:10px"'+K.n(1)+'><div style="display:flex;gap:12px;align-items:flex-end;height:150px;padding:0 10px">'+[50,64,80,98,120].map(function(h,i){return '<div style="flex:1;display:grid;gap:4px;align-items:end;justify-items:center"><div style="width:100%;height:'+h+'px;background:var(--priC);border-top:4px solid var(--pri);border-radius:6px 6px 0 0"></div><small class="mono" style="font-size:9px;color:var(--ink3)">'+["’23","’24","Feb","Jun","Now"][i]+'</small></div>';}).join("")+'</div></div>'+K.btn("Add today’s mark",{full:true,ic:"camera",n:2}));});

/* =================================================================== H · CIRCLE */
def("therapistView","guardian","Therapist view",{suite:"H",for:["sep","blend","loss","hosp","fost","kin"],needs:["anx","grief","neuro"],effort:"L",builds:"The Therapist role (contact ladder and, maybe, session metadata), consent rules",
 rails:"P7: never the private journal, the worry box or feelings; only what the guardians and, as she grows, she herself, choose to share",
 desc:"A scoped view for a family therapist: the schedule, the contact ladder, and anything the guardians or Ivy decide to share. The therapist can leave notes for the family.",
 funcs:["Contact ladder and call schedule, read-only","A “shared with my therapist” shelf the guardians or Ivy fill","Therapist notes visible to both guardians","As Ivy gets older, she controls what is shared"],
 open:"Open question #11 in the product spec: does the therapist see the contact ladder only, or session metadata too? This design says ladder only, plus what is chosen.",
 notes:[[1,"The therapist sees the shape of contact, not what was said."],[2,"Her own sharing grows with her age."]]},
 function(){return top("Dr. Lin")+K.page(K.banner("pri","Dr. Lin sees the schedule and what you choose to share. Never her journal.","shield",1)+K.card('<h4>Shared with Dr. Lin</h4>'+K.row({ic:"calendar",title:"Call schedule",tone:"ok"})+K.row({ic:"swap",title:"Contact ladder",tone:"ok"})+K.row({ic:"image",title:"A drawing Ivy chose",sub:"Shared by Ivy",tone:"ok",n:2}))+K.card(K.row({ic:"letter",title:"A note from Dr. Lin",sub:"For both of you",go:true})));});

def("swapRequest","guardian","Swap request",{suite:"H",for:["sep","blend","kin","fost"],needs:[],effort:"M",builds:"Calendar, the handover log, the busy fork",
 rails:"P2: no tally of who asked or who said yes; P8: the exchange is recorded, never edited",
 desc:"A kind way to ask for a change: “Can we swap Saturday and Sunday?” The other guardian can accept, decline, or propose a different time. The answer is recorded in the log; no one is keeping score.",
 funcs:["A short form that suggests neutral wording","Accept, decline, or counter in one tap","The accepted swap updates both calendars and Ivy’s day","No count of who requested more or less"],
 open:"The earlier decision to hold off on tone assistance still stands. This uses fixed, neutral templates, not a model.",
 notes:[[1,"Templates, written once by people, not generated."],[2,"The answer is a fact in the log, and nothing more."]]},
 function(){return top("Swap a weekend")+K.page(K.card('<h4>Can we swap Saturday and Sunday?</h4><p>I have a family thing on Saturday and I’d love Ivy with me on Sunday instead.</p>',"",1)+K.card('<div class="chips">'+K.chip("Saturday → Sunday",{tone:"pri"})+K.chip("Oct 14–15")+'</div>')+'<div class="btns"'+K.n(2)+'>'+K.btn("No, sorry",{kind:"ghost"})+K.btn("Suggest another",{kind:"tonal"})+K.btn("Yes")+'</div>');});

def("careSummary","guardian","Care summary",{suite:"H",for:["ill","hosp","sep","kin","fost"],needs:["ill","neuro"],effort:"S",builds:"Care binder, a time-boxed link",
 rails:"Time-boxed; read-only; logged",
 desc:"A one-page summary for a pediatrician, a school nurse or an emergency room, generated from the care binder and shared by a link that expires.",
 funcs:["A short summary: conditions, medicines, allergies, contacts","A link that works for a set number of hours","An access log the guardians can see","A printable version"],
 open:"Different clinics want different formats. Start with the one most families already carry on paper.",
 notes:[[1,"The link expires. The log shows if it was opened."]]},
 function(){return top("Care summary")+K.page(K.card('<h4>Ivy, 6</h4>'+'<div class="kv"><span>Allergy</span><span>Cashews</span><span>Condition</span><span>Asthma</span><span>Medicine</span><span>Inhaler as needed</span><span>Contact</span><span>Mom, 555-0142</span></div>',"",1)+K.card(K.row({ic:"link",title:"Valid for 24 hours",sub:"Opened once by Dr. Okafor’s office",tone:"info",n:2})));});

/* =================================================================== I · COMPASS */
def("compassWho","guardian","Tell us about your family",{suite:"I",all:true,for:[],needs:[],effort:"M",builds:"Onboarding, the family graph, the invitation flow",
 rails:"Optional, editable, never a label; the answers shape suggestions and nothing else",
 desc:"The first step of the Family Compass. A short list of ways families look, so the app can suggest the right tools. Choose any, or none.",
 funcs:["Pick any that fit: two homes, a parent far away, a blended family, a grandparent raising, foster care, loss in the family","“Not sure” and “skip” are first-class","Answers stay with the family and are never used for anything else","Can be changed at any time"],
 open:"Wording is everything. Families should recognise themselves without being sorted into a category.",
 notes:[[1,"Any number can be chosen. None is also fine."],[2,"A plain promise: this only shapes suggestions."]]},
 function(){return top("Your family",{eyebrow:"Step 1 of 3"})+K.page('<p style="font:700 17px/1.4 var(--font-body);margin:0">Which of these sound like your family?</p><div class="chips"'+K.n(1)+'>'+["Two homes","A parent far away","A parent who travels for work","Step-parents","A grandparent raising her","Foster care","We lost someone","Hospital stays"].map(function(c,i){return '<span class="chip '+(i===0||i===1?"pri":"")+'" style="padding:9px 13px;font-size:13.5px">'+(i<2?I("check",13,2.4)+" ":"")+c+'</span>';}).join("")+'</div>'+K.banner("pri","This only shapes the suggestions. You can change it any time.","info",2)+K.btn("Next",{full:true,size:"lg"}));});

def("compassNeeds","guardian","What would help Ivy?",{suite:"I",all:true,for:[],needs:[],effort:"M",builds:"Onboarding, accessibility settings",
 rails:"Described as things that help, never as labels or diagnoses",
 desc:"Step two: what helps her day go well. Phrased as supports, not conditions.",
 funcs:["Things that help: a predictable routine, a quiet corner, picture steps, signing, a second language","Medical needs and sensory needs are separate and optional","Nothing is called a diagnosis","Each answer maps to a suite to try, with a plain reason"],
 open:"Parents may not have language for what helps. Offer examples from real families.",
 notes:[[1,"Supports, not diagnoses."],[2,"Every choice can be skipped."]]},
 function(){return top("What helps Ivy?",{eyebrow:"Step 2 of 3"})+K.page('<p style="font:700 17px/1.4 var(--font-body);margin:0">Anything here that helps her day go well?</p><div class="chips"'+K.n(1)+'>'+["Knowing what comes next","A quiet place","Pictures, not just words","Sign language","Another language at home","Regular medicine","Big feelings sometimes","Extra reading help"].map(function(c,i){return '<span class="chip '+(i===0||i===2?"pri":"")+'" style="padding:9px 13px;font-size:13.5px">'+(i===0||i===2?I("check",13,2.4)+" ":"")+c+'</span>';}).join("")+'</div>'+K.btn("Next",{full:true,size:"lg"}));});

def("compassSuggest","guardian","Suggested for your family",{suite:"I",all:true,for:[],needs:[],effort:"M",builds:"A catalogue of suites, per-child activation",
 rails:"Suggestions only. Nothing is switched on for the child without a guardian’s yes",
 desc:"Step three: the Compass proposes a few suites, each with a reason, and the guardian switches on the ones they want. It is a shelf, not a package.",
 funcs:["Three to five suggestions at most, each with a sentence of why","One tap to try, one tap to remove","A “not now” that remembers nothing","Per child: siblings can have different suites"],
 open:"Avoid a “recommended for you” feeling that nudges more than it helps. Fewer suggestions are better.",
 notes:[[1,"Each suggestion says why, in plain words."],[2,"Try it and remove it are equally easy."]]},
 function(){return top("Suggested for Ivy",{eyebrow:"Step 3 of 3"})+K.page(K.card(K.row({ic:"moon",title:"Two Skies",sub:"Because Dad is far away",trail:K.toggle(true),n:1})+K.row({ic:"sparkle",title:"One routine, two houses",sub:"Because you have two homes",trail:K.toggle(true)})+K.row({ic:"book",title:"Bedtime story studio",sub:"Because Dad can record ahead",trail:K.toggle(false)})+K.row({ic:"layers",title:"First, then",sub:"Because knowing what’s next helps",trail:K.toggle(true)}))+K.banner("pri","Nothing turns on for Ivy until you say so. Change this any time.","shield",2)+K.btn("Done",{full:true,size:"lg"}));});

def("suitesShelf","guardian","Suites shelf",{suite:"I",all:true,for:[],needs:[],effort:"M",builds:"Settings hub, per-child settings",
 rails:"No usage scores, no “you haven’t used…” nudges",
 desc:"Where a family manages its suites later. One row per suite, per child, with a switch. It shows what is on, never how much it is used.",
 funcs:["A shelf of suites with on/off per child","A plain description of what each one adds to her home","Never a usage chart or a streak","A search across suites and settings"],
 open:"The line between a settings page and a store. This must never become a place to buy anything (P4).",
 notes:[[1,"Per child. A brother may have different suites."],[2,"No numbers about use. Just on or off."]]},
 function(){return top("Suites")+K.page(K.seg(["Ivy","Leo"],0,1)+K.card(K.row({ic:"moon",title:"Distance",sub:"Two Skies · Away mode · Vault",trail:K.toggle(true),n:2})+K.row({ic:"swap",title:"Rhythm",sub:"One routine · First, then",trail:K.toggle(true)})+K.row({ic:"heart",title:"Voice",sub:"Feelings weather · Helpers",trail:K.toggle(false)})+K.row({ic:"users",title:"Village",sub:"Grandparent corner · My people",trail:K.toggle(true)})+K.row({ic:"dice",title:"Together",sub:"Cook along · Music along",trail:K.toggle(true)})));});

def("childAwayHome","child","Her home, with a far-away parent",{suite:"I",all:false,for:["mil","road","inc"],needs:["anx"],effort:"M",builds:"Child home hierarchy: the hero tile and presence card change, nothing is added",
 rails:"No new menus; the same shell with different tiles",
 desc:"The same child home, reshaped for a family with a parent far away: Two Skies in the presence card, the path home as the hero, postcards and the vault among the featured tiles.",
 funcs:["Presence card becomes Two Skies","Hero becomes “the path home”","Featured: postcards, the vault, stories from Dad","Standard tiles unchanged"],
 open:"Keep the same layout across variants so a child who moves between households never feels lost.",
 notes:[[1,"Same shell. Different hero."],[2,"Postcards and the vault sit where the games usually are."]]},
 function(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})})+K.page(K.card('<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;height:70px"'+K.n(1)+'><div style="border-radius:14px;overflow:hidden">'+K.scene("hills",150,70)+'</div><div style="border-radius:14px;overflow:hidden">'+K.scene("night",150,70)+'</div></div><p style="margin:8px 0 0;color:inherit">Dad is asleep. Same moon tonight.</p>',"hero")+K.tile("hero",{ic:"flag",title:"The path home",sub:"3 sleeps to the next stop",scene:"hills",n:2})+'<div class="grid2">'+K.tile("feat",{ic:"mail",title:"Postcards",badge:"1"})+K.tile("feat",{ic:"heart",title:"From Dad"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"dice",title:"Play"})+'</div>');});

def("childDeafHome","child","Her home, with sign language",{suite:"I",all:false,for:[],needs:["deaf"],effort:"L",builds:"The call (larger video, captions), captions on every artifact, the accessibility matrix",
 rails:"Captions are never optional for a Deaf or hard-of-hearing child; no audio-only features are required",
 desc:"For a Deaf or hard-of-hearing child, the whole home is video-first: large video, live captions on every call, sign-language practice, and every message with a caption or a signed clip.",
 funcs:["Calls with the largest possible video and live captions","Messages can be a signed video, with a caption","A fingerspelling game with family","Alerts are visual and haptic, never sound only","Grandparents and cousins can learn together in a signing room"],
 open:"Co-design with Deaf community members is essential. Do not guess what a signing child needs.",
 notes:[[1,"Video-first. Everything has a caption."],[2,"A visual, haptic alert instead of a sound."]]},
 function(){return K.sb()+K.top({logo:true,title:"Hi, Ivy",right:K.avatar("I",{size:42,ring:true})})+K.page('<div style="position:relative;border-radius:26px;overflow:hidden;height:170px;background:linear-gradient(160deg,#2a3f55,#121b26);display:grid;place-items:center"'+K.n(1)+'><span class="av" style="width:90px;height:90px;font-size:38px;background:rgba(255,255,255,.14);color:#fff">D</span><div style="position:absolute;left:10px;right:10px;bottom:10px;background:rgba(0,0,0,.6);color:#fff;border-radius:12px;padding:8px 12px;font-weight:700;font-size:14px">Dad: “Did you finish the drawing?”</div></div>'+K.btn("Call Dad",{full:true,size:"lg",ic:"video"})+'<div class="grid2">'+K.tile("feat",{ic:"hand",title:"Signing"})+K.tile("feat",{ic:"chat",title:"Messages"})+'</div>'+K.banner("pri","Alerts flash and buzz. They never rely on sound.","bell",2));});
})();
