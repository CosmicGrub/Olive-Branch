/* Suites J (Growing up: age bands) and K (Family structure: parent-built, child-synced). Proposals. */
(function(){
"use strict";
var K=OB,I=K.ico;
function def(id,shell,title,m,r){OB.meta[id]=m;OB.def(id,shell,title,{grp:m.suite,desc:m.desc,notes:m.notes||[],isNew:true,r:r});}
function top(title,o){o=o||{};return K.sb()+K.top({back:!o.noBack,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function ctop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.noSpeak?"":K.iconBtn("volume",{kind:"tonal",label:"Hear it"})});}
function face(l,o){return K.avatar(l,Object.assign({size:46},o||{}));}

/* ========================================================== J · GROWING UP */
def("ageHome5","child","Her home at 5 to 6",{suite:"J",for:[],needs:["tod"],all:true,effort:"S",builds:"The existing child home (hero, featured, standard), read-aloud on every screen, her colour of the day",
 rails:"No settings, no scores, targets 64 and up, everything readable aloud (§8.4, §8.8.5)",
 desc:"The shell for a child who is just learning to read. Pictures lead, every word can be heard, tiles are large and few. This is the version your daughter has now, and the baseline the other ages grow from.",
 funcs:["Icon-first tiles with one word each, and a speaker on every screen","Read-aloud on by default","Games with big pieces and gentle rules, play with a grown-up first","Colour of the day, first-then, packing buddy, a picture feelings weather","A simple path-code game: arrows only"],
 open:"Where does “learning to read” begin to turn read-aloud from default to option? A per-child choice, not an age cut-off.",
 notes:[[1,"One word under each picture. The speaker reads anything on screen."],[2,"Her colour appears in at most three places (§8.6.2)."],[3,"Few tiles, big targets. No menu deeper than one tap."]]},
 function(){return K.sb()+K.top({logo:true,eyebrow:"Good morning",title:"Hi, Ivy",right:K.iconBtn("volume",{kind:"tonal",label:"Hear it",n:1})})+K.page(K.tile("hero",{ic:"calendar",title:"My day",sub:"School, then Nana’s",scene:"hills",n:2})+'<div class="grid2"'+K.n(3)+'>'+K.tile("feat",{ic:"dice",title:"Play"})+K.tile("feat",{ic:"chat",title:"Dad",badge:"1"})+K.tile("feat",{ic:"book",title:"Stories"})+K.tile("feat",{ic:"palette",title:"My colour"})+'</div>');});

def("ageHome8","child","Her home at 7 to 9",{suite:"J",for:[],needs:["school"],all:true,effort:"M",builds:"Child home hierarchy, the games catalogue, Teach me, the showcase, pacing by age",
 rails:"Read-aloud becomes an option she can turn on, never a thing taken away; coding unlocks at 8 (repeat blocks, pixel garden)",
 desc:"A confident early reader. Words appear beside the pictures, she can write a short message herself, the games get strategy, and she starts to make things and teach them.",
 funcs:["Words beside pictures; read-aloud stays one tap away","Short typed messages, with a spelling helper that never corrects out loud","Strategy games (checkers, word chain), with fairness tuned quietly","Path code with repeat blocks and the pixel garden from 8","Teach me: she shows Dad how to do something"],
 open:"How much typing is safe before she can read replies? Voice notes both ways first.",
 notes:[[1,"Words are visible now, still with pictures."],[2,"Make-and-teach moves up into the featured row."]]},
 function(){return K.sb()+K.top({logo:true,eyebrow:"Saturday",title:"Hi, Ivy"})+K.page(K.card('<div class="row" style="padding:0"><span class="rtxt"><b>Dad is asleep.</b><small>Message him. He’ll see it when he wakes.</small></span>'+K.iconBtn("chat",{kind:"pri"})+'</div>',"tint",1)+'<div class="grid3"'+K.n(2)+'>'+[["target","Path code"],["pawn","Checkers"],["brush","Make"],["book","Read"],["hand","Teach"],["camera","Show"]].map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("")+'</div>'+K.sectionLabel("New")+K.card(K.row({ic:"puzzle",title:"Pixel garden",sub:"New at 8",go:true})));});

def("ageHome12","child","Her home at 10 to 12",{suite:"J",for:[],needs:[],all:true,effort:"M",builds:"The maturation ladder (rung 10: her own list), the journal, helpers, group play",
 rails:"More of it becomes hers by rung; the product never narrows a step already given (§21.1)",
 desc:"A pre-teen. Less cute, more capable. Her own wants list is uncurated by anyone, the journal is bigger, she can message her helpers herself, and group play with cousins opens up.",
 funcs:["Her own list, written by her, uncurated by anyone (ladder rung ~10)","A fuller journal with drawing and voice","Message her chosen helpers directly","Group play and a cousins’ room, with guardians’ consent","A “what’s private” explainer so she knows exactly what is hers"],
 open:"Group chat is where children meet risk. Start with closed, family-only rooms and no strangers, ever.",
 notes:[[1,"Her list is hers. No one curates it from here."],[2,"A plain screen says what is private and what is shared."]]},
 function(){return K.sb()+K.top({logo:true,title:"Ivy"})+K.page(K.card(K.row({ic:"list",title:"My list",sub:"Only you decide what goes here",trail:K.chip("Yours",{tone:"ok",sm:true}),n:1,go:true})+K.row({ic:"book",title:"Journal",sub:"Private",go:true})+K.row({ic:"users",title:"My helpers",sub:"Nana, Aunt Mia",go:true}))+K.card(K.row({ic:"dice",title:"Cousins’ room",sub:"Both families agreed",go:true,n:2}),"tint")+K.banner("pri","What’s private and what’s shared: see it plainly.","lock",3));});

def("ageHome15","child","Her home at 13 to 17",{suite:"J",for:[],needs:["teen"],all:true,effort:"L",builds:"Ladder rungs 13 to 17: journal locks absolutely, ping limits end, calendar edit, publishing her own availability, archive curation, her own export",
 rails:"P7: the journal is hers at every tier. The shell treats her as a person with an agenda, not a kid to entertain",
 desc:"A teenager. The app is quiet and mostly out of the way: her calendar, her availability, her private journal, and a way to reach the people she trusts. Control has moved to her by the ladder.",
 funcs:["Journal locks absolutely at 13; no parent path exists","Contact limits disappear at 13","She edits her own calendar (14) and publishes when she is reachable (15)","She curates her archive (16) and can export her own data (17)","Helpers include a listening line the family picked in advance"],
 open:"What does a guardian still see at 15? Their view should shrink as hers grows, and say so on both screens.",
 notes:[[1,"The journal lock is permanent and obvious."],[2,"She sets her own availability, an inversion of the early years."]]},
 function(){return K.sb()+K.top({logo:true,title:"Ivy"})+K.page(K.card(K.row({ic:"book",title:"Journal",sub:"Locked. Only you.",trail:I("lock",18,2),n:1,go:true})+K.row({ic:"calendar",title:"My calendar",sub:"You edit it",go:true})+K.row({ic:"clock",title:"When I’m free",sub:"You set it",go:true,n:2})+K.row({ic:"image",title:"My archive",sub:"You choose what stays",go:true}))+K.card(K.row({ic:"heart",title:"I need to talk to someone",sub:"Nana, Aunt Mia, or a listening line",go:true}),"tint"));});

def("birthdayUnlocks","guardian","Ivy turns 6",{suite:"J",for:[],needs:[],all:true,effort:"M",builds:"The maturation ladder, device pacing, theme and art-style allowances",
 rails:"A rung is permanent and the guardian cannot lower it (§21.1); other age defaults are suggestions the guardian can hold",
 desc:"Before a birthday the guardian sees, in plain words, what will change for the child and which of it they can hold back. Rungs on the ladder are permanent; age-based defaults are gentler suggestions.",
 funcs:["A preview of what changes at the new age, by category","Each default can be held for a time, or accepted now","Rungs on the ladder are marked permanent so no one is surprised","A short note to write to the child to go with it"],
 open:"Birthdays vary by culture and by child. Let a guardian move the date a change takes effect.",
 notes:[[1,"What changes is listed first, in plain words."],[2,"A permanent step is marked as permanent."],[3,"Hold-for-now is a normal choice, not a failure."]]},
 function(){return top("Ivy turns 6 on Sep 14")+K.page(K.card('<h4>What changes</h4>'+K.row({ic:"book",title:"Words beside the pictures",sub:"Read-aloud stays on",trail:K.toggle(true),n:1})+K.row({ic:"target",title:"Path code, level 2",sub:"Adds a longer program",trail:K.toggle(true)})+K.row({ic:"dice",title:"Strategy games",sub:"Checkers and word chain",trail:K.toggle(false)}),"",1)+K.banner("warn","Nothing on the maturation ladder changes at 6. Those steps start near 10, and are permanent.","lock",2)+K.btn("Write her a note",{kind:"tonal",full:true,ic:"pencil"}));});

def("birthdayChild","child","You’re six!",{suite:"J",for:[],needs:[],all:true,effort:"S",builds:"Birthday marked (celebrated without a score, P2), the year book",
 rails:"P2: no score, no badge, no “unlocked!” fanfare. One calm sentence",
 desc:"When a new age arrives, one warm moment: her birthday on the calendar and a small “something new” that quietly appears. Nothing flashes and nothing counts.",
 funcs:["A single sentence of celebration in her words","A “something new” tile that appears in a quiet place, once","The year book gains a page for the year","No confetti loops"],
 open:"A family may prefer to hold the moment until the birthday party. Let the guardian time it.",
 notes:[[1,"One sentence. No loop, no sound."],[2,"What’s new is a tile, never a pop-up."]]},
 function(){return ctop("My birthday",{noSpeak:false})+K.page('<div class="center"><div style="width:100%;border-radius:26px;overflow:hidden">'+K.scene("paper",300,140)+'</div><div class="big">Hooray, Ivy! You’re 6.</div><p style="color:var(--ink2)"'+K.n(1)+'>Dad and Mom love you very much.</p>'+K.card(K.row({ic:"sparkle",title:"Something new is on your home",go:true,n:2}),"tint")+K.btn("Thank you",{size:"lg"})+'</div>');});

def("ageSettings","guardian","By age",{suite:"J",for:[],needs:[],all:true,effort:"M",builds:"Parental controls (visibility and pacing by age), the theme and art-style settings",
 rails:"Defaults, not walls; a guardian may raise, lower or hold each; ladder rungs are separate and permanent",
 desc:"One page showing the age bands the app knows, where this child is, and what each band adds or changes. A guardian can adjust a default for their own child without changing the product.",
 funcs:["Bands from 2 to 18 with a plain description","Where Ivy is, and the next change coming","Per-band defaults the guardian can raise, lower or hold","A link from every change to what it does for her"],
 open:"A child who is ahead in one area and behind in another. Defaults should be per area, not one number.",
 notes:[[1,"Ivy’s band is marked. The next change is shown."],[2,"Every default can be changed for this child."]]},
 function(){var B=[["2–4","Toddler: one big button"],["5–6","Beginning reader"],["7–9","Early independence"],["10–12","Her own list"],["13–17","Teen: mostly hers"]];return top("Growing up")+K.page(K.card(B.map(function(b,i){return K.row({av:K.avatar(b[0].split("–")[0],{size:38,ring:i===1}),title:b[0],sub:b[1],trail:i===1?K.chip("Ivy",{tone:"ok",sm:true}):I("chevR",16,2),n:i===1?1:0});}).join(""))+K.card(K.row({ic:"clock",title:"Next change: age 7",sub:"Words become the lead",go:true,n:2}),"tint"));});

def("whatsHers","guardian","What’s hers now",{suite:"J",for:[],needs:[],all:true,effort:"S",builds:"The maturation ladder (§21), the rung grant record",
 rails:"A rung is permanent: the guardian cannot take one back, and the screen says so",
 desc:"A calm page for guardians showing which steps have become Ivy’s and which are still ahead. It exists so a handover to her never comes as a surprise.",
 funcs:["A short ladder with ticks for what is hers","Plain text on what each step changes for both of you","A permanent-step banner","A conversation prompt for each coming step"],
 open:"The ladder is a ceremony, not a setting. Pair each step with a note to her, and never with a reward.",
 notes:[[1,"Ticks show what is already hers."],[2,"A conversation prompt, not a checklist."]]},
 function(){var R=[["~10","Her own list",false],["13","Journal locks",false],["14","Her calendar",false],["15","Her availability",false],["16","Her archive",false],["18","Everything",false]];return top("What’s hers")+K.page(K.banner("pri","A step is permanent. You can’t take one back.","lock",1)+K.card(R.map(function(r,i){return K.row({av:K.avatar(r[0],{size:36}),title:r[1],sub:"Not yet",trail:I("clock",16,2),n:i===0?2:0});}).join("")));});

/* ====================================================== K · FAMILY STRUCTURE */
def("structureBuilder","guardian","Our family",{suite:"K",for:[],needs:[],all:true,effort:"L",builds:"The family graph (roles and edges), the invitation flow, the custody schedule, the contact ladder",
 rails:"Only a guardian can change it; the child can never see or edit this screen; every change is dated and kept",
 desc:"Where a guardian describes the family the way it actually is: who lives where, who is in her life, and how each person is reached. It is built from simple blocks, so it fits any family, and it can change as the family does.",
 funcs:["Homes: one to four, each with who lives there","People: any number, each with a role and the name she uses for them","How each person is reached: live calls, messages, voice line, postcards, or supervised","Away status per person, with an end date if there is one","Per child: half-siblings can have different people"],
 open:"When two guardians disagree about a structural change, the product shows both views and never picks a winner. A court order, if one exists, is shown as set by order and not editable here.",
 notes:[[1,"Homes first, then people. Each person has a role and a name she uses."],[2,"Reach is a per-person choice, not a family-wide rule."],[3,"A custody order, if any, is shown as fixed."]]},
 function(){return top("Our family")+K.page(K.seg(["Ivy","Leo"],0)+K.sectionLabel("Homes")+K.card(K.row({ic:"home",title:"Mom’s house",sub:"Ivy, Mom, Jordan",go:true,n:1})+K.row({ic:"home",title:"Dad’s house",sub:"Ivy, Dad · away until Mar 14",go:true})+K.row({ic:"home",title:"Nana’s",sub:"Weekends",go:true}))+K.sectionLabel("People in her life")+K.card(K.row({av:face("M"),title:"Mom",sub:"Guardian · live calls",n:2})+K.row({av:face("D",{tone:"accent"}),title:"Dad",sub:"Guardian · messages and vault"})+K.row({av:face("J"),title:"Jordan",sub:"Step-parent · calls and messages"}))+K.banner("info","Custody schedule: set by court order. Shown, not editable.","shield",3));});

def("addPerson","guardian","Add someone to her life",{suite:"K",for:[],needs:[],all:true,effort:"M",builds:"Roles in the family graph (guardian, step-parent, trusted adult, sitter, foster parent, caseworker, therapist), invitations",
 rails:"Each person accepts; a role grants only what it should (§8.1); the child never chooses roles",
 desc:"One short flow to add a person: who they are to her, the name she uses, what they can do, and how they will reach her. Every role is a plain card with what it allows and what it never allows.",
 funcs:["Role cards with plain can and can’t lists","The name she uses, set by the guardian","Contact choices per person","An invitation they accept; nothing is shared until they do","A review date for roles that may change (step-parents, foster placements)"],
 open:"Roles are the product’s words. A family’s words (“Papa”, “Aunt Mia”) are what she sees.",
 notes:[[1,"The name she uses is the one on her side."],[2,"What each role can and can’t do is shown before it is chosen."]]},
 function(){return top("Add someone",{eyebrow:"Step 2 of 3"})+K.page(K.field("Name she uses for them","Aunt Mia",{ic:"user",n:1})+K.sectionLabel("Who they are to her")+K.card(K.row({ic:"heart",title:"A relative",sub:"Calls and messages",trail:I("check",18,2.4),tone:"ok"})+K.row({ic:"users",title:"A step-parent",sub:"Scoped by you"})+K.row({ic:"shield",title:"A trusted adult",sub:"Calls and messages only"})+K.row({ic:"clock",title:"A sitter",sub:"One evening at a time"}))+K.banner("info","They accept first. Nothing is shared until they do.","mail",2)+K.btn("Next",{full:true,size:"lg"}));});

def("homesRhythm","guardian","Homes and rhythm",{suite:"K",for:[],needs:[],all:true,effort:"M",builds:"The custody schedule (the engine is built), exchange, the weeks view",
 rails:"The schedule shown to her is her own frame (sleeps), never a split or a percentage",
 desc:"Describe the rhythm of a week in blocks, or paste the one in a court order. The app turns it into what Ivy sees: where she sleeps, and how many sleeps until the next house.",
 funcs:["Weekly patterns: 2-2-3, alternating weeks, weekends, custom","Exceptions for holidays and trips","Away blocks for a person who is deployed or travelling","A preview of Ivy’s weeks, in her frame","Order-set schedules are labelled and locked"],
 open:"Schedules change. A change must never silently alter what a child was already told to expect.",
 notes:[[1,"A pattern, plus exceptions on top."],[2,"The preview is exactly what she will see."]]},
 function(){return top("A week at a time")+K.page(K.seg(["2-2-3","Alternate","Weekends","Custom"],0,1)+K.card('<h4>What Ivy sees</h4><div style="display:grid;grid-template-columns:repeat(7,1fr);gap:6px"'+K.n(2)+'>'+[1,1,0,0,1,1,1].map(function(m){return '<span style="aspect-ratio:1;border-radius:50%;background:'+(m?"var(--pri)":"var(--accent)")+'"></span>';}).join("")+'</div><div class="chips" style="margin-top:10px">'+K.chip("Mom’s house",{tone:"pri"})+K.chip("Dad’s house")+'</div>')+K.card(K.row({ic:"flag",title:"Away block",sub:"Dad · Jan 3–Mar 14",go:true}))+K.btn("Save the pattern",{full:true}));});

def("previewChange","guardian","What changes for Ivy",{suite:"K",for:[],needs:[],all:true,effort:"M",builds:"The child home hierarchy, the delivery engine for timing, the theme-sync pattern (guardian writes, child reads)",
 rails:"Guardian-only writes; the child reads. A change reaches her only when and how the guardian chooses",
 desc:"Before any structural change reaches Ivy, the guardian sees her screens before and after, and chooses when she sees it: now, when the guardian has talked with her first, or on a date. The child’s options sync to the family only after that choice.",
 funcs:["Before and after of her home and her people","Three timings: now, hold until I’ve told her, or on a date","An optional gentle story card to go with the change","A short note the guardian can add, in their own words","The change is dated and kept in the family history"],
 open:"A change one guardian makes that the other disagrees with. Both see the preview; neither is overruled by the app.",
 notes:[[1,"Before and after, side by side, in her own screens."],[2,"“Hold until I’ve told her” is the default for big changes."],[3,"A story card can travel with the change."]]},
 function(){return top("Jordan moves in")+K.page('<div class="grid2"'+K.n(1)+'><div class="card center" style="min-height:110px;padding:8px"><small class="mono" style="color:var(--ink3)">BEFORE</small><b>Mom’s house</b><small>Mom</small></div><div class="card center" style="min-height:110px;padding:8px;border:2px solid var(--pri)"><small class="mono" style="color:var(--pri)">AFTER</small><b>Mom’s house</b><small>Mom, Jordan</small></div></div>'+K.sectionLabel("When should she see it?")+K.card(K.row({title:"Now"})+K.row({title:"After I’ve told her",sub:"I’ll switch it on",trail:I("check",18,2.4),tone:"ok",n:2})+K.row({title:"On a date"}))+K.row({ic:"book",title:"Add a story card",sub:"A gentle way to read it together",go:true,n:3}).replace('class="row"','class="row card"')+K.btn("Save the change",{full:true}));});

def("changeStory","child","Our family is changing",{suite:"K",for:[],needs:["anx","grief"],all:true,effort:"M",builds:"The explainer cards, Read together, the storyteller (guardian-reviewed)",
 rails:"A guardian reads it with her or chooses when she sees it; P1: no synthetic parent; questions go to a person",
 desc:"A short, gentle picture story about a change in her family, read together with a grown-up. It uses her words and her people, and it ends with a place to ask a question.",
 funcs:["One idea per card, pictures first","Written and checked by a guardian before she sees it","Reads together with Read together, in two places if needed","A question box that goes to a person, never a model"],
 open:"Separations, new partners and losses are very different. Each needs its own reviewed set, written with child-development experts.",
 notes:[[1,"The story is about her people, by the names she uses."],[2,"She can leave a question for a grown-up."]]},
 function(){return ctop("Jordan and Mom")+K.page('<div style="border-radius:24px;overflow:hidden">'+K.scene("hills",300,120)+'</div>'+K.card('<p style="font:800 19px/1.35 var(--font-display);margin:0;color:var(--ink)"'+K.n(1)+'>Jordan is going to live at Mom’s house with you.</p>')+'<div class="btns">'+K.btn("Back",{kind:"tonal",ic:"arrowL",size:"lg"})+K.btn("Next",{ic:"arrowR",size:"lg"})+'</div>'+K.card(K.row({ic:"chat",title:"I have a question",sub:"A grown-up will answer",go:true,n:2}),"tint"));});

def("myPeopleDerived","child","My people, from our family",{suite:"K",for:[],needs:[],all:true,effort:"M",builds:"The family graph, the names she uses, the child home hierarchy",
 rails:"Built from what the guardian set; she sees names and faces, never roles or legal terms",
 desc:"The child’s “My people” is generated from the family structure, with the names she uses and the people she can reach in the way each was set up: a call button for some, a postcard for another, a phone-line message for a third.",
 funcs:["Faces and names from the structure","The right button per person: call, message, postcard, or a voice-line story","Grouped by house, as she lives it","Updates when a guardian applies a change, never before"],
 open:"If someone leaves her life, the change needs care, not just a deleted face. Offer the memory box and a story card.",
 notes:[[1,"Each person has the button that suits how they reach her."],[2,"The list changes only when a guardian applies a change."]]},
 function(){return ctop("My people")+K.page(K.card('<div class="chips" style="margin-bottom:8px">'+K.chip("Mom’s house",{tone:"pri"})+K.chip("Dad’s house")+K.chip("Nana’s")+'</div>'+K.row({av:face("M",{ring:true}),title:"Mom",sub:"",trail:K.iconBtn("video",{kind:"tonal"}),n:1})+K.row({av:face("J"),title:"Jordan",trail:K.iconBtn("chat",{kind:"tonal"})})+K.row({av:face("D",{tone:"accent"}),title:"Dad",sub:"Far away right now",trail:K.iconBtn("mail",{kind:"tonal"}),n:2})+K.row({av:face("N"),title:"Nana",trail:K.iconBtn("phone",{kind:"tonal"})})));});

def("structureHistory","guardian","Family history",{suite:"K",for:[],needs:[],all:true,effort:"S",builds:"The preservation rule, the handover log, the court export",
 rails:"P8-style permanence for the record: changes are dated and kept; nothing is erased",
 desc:"A dated list of every change to the family structure: who was added, which home changed, when someone went away. It is the record, not a control.",
 funcs:["Each change with date and who made it","What Ivy was shown, and when","Included, if the family wants, in the court export","Cannot be edited or deleted"],
 open:"A family may want to hide a painful change from a co-guardian. The product does not offer that: nothing is hidden between guardians.",
 notes:[[1,"The date she was told is recorded, not only the date it changed."]]},
 function(){return top("Family history")+K.page(K.card(K.row({ic:"users",title:"Jordan added",sub:"Sep 2 · Mom · Ivy told Sep 4",n:1})+K.row({ic:"flag",title:"Dad away until Mar 14",sub:"Aug 20 · Dad · Ivy told Aug 21"})+K.row({ic:"home",title:"Nana’s added as a home",sub:"Jun 11 · Mom"}))+K.banner("info","Changes are kept. They can’t be edited or deleted.","lock",2));});

def("perChild","guardian","Each child’s own family",{suite:"K",for:["blend","sep","fost","kin"],needs:[],effort:"M",builds:"Siblings (links never widen authority), per-child family-graph edges",
 rails:"A guardian of one child is not a guardian of the other (§ siblings)",
 desc:"Half-siblings and step-siblings often have different people in their lives. Each child has her or his own structure, and a link between them lets the children play together without giving any adult access to the other child.",
 funcs:["Switch between children; each has their own people and homes","A shared person appears once and is shown in each child’s view","Sibling links: play, a shared room, no adult access","Age bands, suites and settings are per child"],
 open:"A step-parent is a guardian-scope for one child and a plain adult for another. Roles must be per child.",
 notes:[[1,"Ivy’s family and Leo’s overlap but are not the same."]]},
 function(){return top("Ivy and Leo")+K.page(K.seg(["Ivy","Leo"],1,1)+K.card('<h4>Leo’s people</h4>'+K.row({av:face("M"),title:"Mom",sub:"Guardian · both children"})+K.row({av:face("J"),title:"Jordan",sub:"His dad · guardian for Leo",n:1})+K.row({av:face("D",{tone:"accent"}),title:"Dad",sub:"Ivy’s dad · not Leo’s guardian"}))+K.banner("info","Ivy and Leo can play together. That does not give Dad access to Leo.","shield",0));});
})();
