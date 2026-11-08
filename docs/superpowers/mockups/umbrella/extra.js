/* The "Growing up" and "Family builder" tabs. Loaded before app.js; app.js calls OBX.renderAges / renderFamily / handle. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc;
var $=function(s,r){return (r||document).querySelector(s);};
var OBX=window.OBX=window.OBX||{};

/* ================================================================== AGES */
var AGES=[
 {id:"t",from:2,to:4,n:"Toddler",tag:"One big button",
  sees:"The toddler shell (§8.10): one control that fills most of the screen, 180-unit targets, his or her face large. No reading needed.",
  hers:"Nothing is hers yet. The guardians run everything.",
  ctl:["Which faces appear","Bedtime story voice and a replay shelf","The loudest sound, and a no-flash promise"],
  on:["Two Skies (as a sky picture)","Postcards","Bedtime story studio (listen)","Sensory profile"],
  safe:["No typing at all","No games with rules","Calls end the same way every time"],
  scen:["Seeing a face she misses, with no tapping","A goodnight story she can replay","Saying bye at the end of a call","A grandparent video that just starts","Moving between houses with a blanket","Starting daycare"]},
 {id:"a",from:5,to:6,n:"Beginning reader",tag:"Pictures lead, every word can be heard",ivy:true,
  sees:"The child home (hero, featured, standard) with large icon tiles, a speaker on every screen, and her colour of the day.",
  hers:"Her colour, her colour of the day, her favourite animal and fruit (as light interests).",
  ctl:["Everything: visibility, pacing, time together, art styles, suites","Who she can reach and how","Read-aloud language"],
  on:["Colour of the day","First, then","Packing buddy","Feelings weather (pictures)","Worry box (draw or say)","Read together","Garden along","Colour sort","Path code: arrows only"],
  safe:["Read-aloud on by default","64-unit targets","No scores, no timers, no streaks","A grown-up starts anything shared"],
  scen:["Starting kindergarten or first grade","A lost tooth, and a message from far away","A first sleepover","Big feelings at bedtime","Learning to read with Nana","A friend moves away"]},
 {id:"b",from:7,to:9,n:"Early independence",tag:"Words, making and teaching",
  sees:"Words beside the pictures. Short typed messages, strategy games, make-and-teach moves up the home screen.",
  hers:"Her art style, what she colours, her favourites. Pixel garden and repeat blocks unlock at 8 (a default, not a rung).",
  ctl:["Which games, jokes and tiles by age (pacing)","Who she can message directly","Whether reading aloud stays on"],
  on:["Path code with repeat","Pixel garden","Teach me","Cook along (kid steps)","Feelings weather","Cousin room (guardians agree)","Symbols (if useful)"],
  safe:["Voice notes first, typing second","Family-only rooms, no strangers","Games tuned quietly so a close game is a fair one"],
  scen:["A spelling test","A fight with a friend","A new step-parent","Her first rules for her own tablet time","A parent’s deployment ends","A move to a new house"]},
 {id:"c",from:10,to:12,n:"Her own list",tag:"More of it becomes hers",
  sees:"Less cute, more capable. Her own wants list, a fuller journal, her helpers, and a plain page that says what is private and what is shared.",
  hers:"Ladder rung ~10: her own list, uncurated by anyone (§21.2). The journal gets bigger and stays hers.",
  ctl:["Who her helpers are, chosen with her","Group rooms, with consent from every guardian","Her time together and art options"],
  on:["My helpers","Journal and doodle","Group play with cousins","Time capsule (she adds to it)","Explainer cards (vetted) for questions about growing up"],
  safe:["No strangers, ever","What is private is stated plainly","The first phone question is a conversation, not a toggle"],
  scen:["Starting middle school","A first phone","Questions about her changing body, with a trusted adult","What to put on her own list","Sleepover rules in both houses","A parent’s new partner"]},
 {id:"d",from:13,to:17,n:"Mostly hers",tag:"The app steps back",
  sees:"Quiet, mostly out of the way: her calendar, her availability, her private journal, and people she trusts.",
  hers:"Rung 13: the journal locks absolutely and contact limits end. 14: her own calendar. 15: she publishes her availability. 16: she curates her archive. 17: her own export.",
  ctl:["What a guardian sees shrinks as hers grows, and says so on both screens","Safety nets she and the family agreed together"],
  on:["Time capsule (opens at her rungs)","A listening line she picked","Therapist sharing, under her control","Swap requests she can raise too"],
  safe:["P7 at every tier: no parent path into her private space","No location, ever (P3), even when she drives","Nothing is a streak or a score"],
  scen:["Wanting privacy","Group chats with friends (family rooms stay)","Planning her own time","A hard conversation with a helper","A friendship ending","Her first job"]},
 {id:"e",from:18,to:18,n:"Hers entirely",tag:"Guardianship closes",
  sees:"Everything is hers. The family stays in her life only if she wants it.",
  hers:"Rung 18: everything. Her account, her data, her archive, her choice of who stays.",
  ctl:["Nothing. A guardian can keep a seat only if she invites it"],
  on:["Her own export","Her time capsules open","The year book, as hers"],
  safe:["A calm handover, with her in charge","Preservation is the default; she decides what stays"],
  scen:["Guardianship closes","Her account, her data","What she keeps","The family she keeps in touch with, her way"]}
];
function bandFor(a){for(var i=0;i<AGES.length;i++)if(a>=AGES[i].from&&a<=AGES[i].to)return AGES[i];return AGES[AGES.length-1];}
function toddlerHome(){return {shell:"child",r:function(){return K.sb()+K.page('<div class="center" style="min-height:540px"><span class="av ring" style="width:110px;height:110px;font-size:46px;background:var(--accentC);color:var(--ink)">D</span><button class="btn pri lg" style="width:100%;min-height:150px;font-size:26px;border-radius:34px">'+I("video",42,1.8)+' Dad</button></div>');}};}
function eighteenHome(){return {shell:"guardian",r:function(){return K.sb()+K.top({title:"Hers now",eyebrow:"Age 18"})+K.page(K.card('<p style="font:800 19px/1.3 var(--font-display);margin:0;color:var(--ink)">Everything is Ivy’s now.</p><p>Her account, her data and her archive are hers. Mom and Dad stay if she invites them.</p>',"tint")+K.card(K.row({ic:"download",title:"Her own export",go:true})+K.row({ic:"users",title:"Who stays in her life",go:true})+K.row({ic:"lock",title:"Her journal",sub:"Hers, as always",go:true})));}};}
function homeFor(band){
 if(band.id==="t")return toddlerHome();if(band.id==="e")return eighteenHome();
 var id={a:"ageHome5",b:"ageHome8",c:"ageHome12",d:"ageHome15"}[band.id];return K.byId(id);}
var ageState={age:5};

OBX.renderAges=function(G){
 var b=bandFor(ageState.age),scr=homeFor(b);
 var list=function(a){return '<ul style="margin:.2em 0 0;padding-left:1.1em">'+a.map(function(x){return '<li>'+E(x)+'</li>';}).join("")+'</ul>';};
 var next=null;for(var i=0;i<AGES.length;i++)if(AGES[i].from>ageState.age){next=AGES[i];break;}
 $("#p-ages").innerHTML='<h2>An app that grows with her</h2><p class="intro">Drag the age. The child home, what is hers, what a guardian controls and the everyday moments all change with it. Ivy is five and turning six, so she starts in the second band, and everything before and after is already planned.</p>'+
 '<div class="card0"><div class="grp" style="margin-bottom:8px"><span class="lbl">Age</span><b style="font:800 1.6rem var(--font-display)" id="agenum">'+ageState.age+'</b><button class="btn0" data-a="ageivy">Jump to Ivy (5, turning 6)</button></div><input type="range" id="agerange" min="2" max="18" value="'+ageState.age+'" style="width:100%" aria-label="Age"><div class="eyebrow" style="display:flex;justify-content:space-between;margin-top:4px"><span>2</span><span>6</span><span>10</span><span>14</span><span>18</span></div></div>'+
 '<div class="two0" style="display:grid;grid-template-columns:minmax(0,auto) minmax(260px,1fr);gap:22px;margin-top:16px;align-items:start"><div class="dstage" style="padding:20px">'+K.frame(scr,"phone",.82)+'</div><div class="det"><div class="eyebrow">Ages '+(b.from===b.to?b.from:b.from+" to "+b.to)+(b.ivy?" · Ivy is here":"")+'</div><h2 style="margin:2px 0 4px">'+E(b.n)+'</h2><p style="color:var(--muted);margin:0 0 6px">'+E(b.tag)+'</p><p style="margin:0">'+E(b.sees)+'</p>'+
 '<h4>What is hers</h4><p style="margin:0">'+E(b.hers)+'</p><h4>What a guardian controls</h4>'+list(b.ctl)+'<h4>On by default</h4><div>'+b.on.map(function(x){return '<span class="tag2">'+E(x)+'</span>';}).join("")+'</div><h4>Safety, built in</h4>'+list(b.safe)+'</div></div>'+
 '<h3 style="margin-top:22px">Everyday moments at this age</h3><div class="cols" style="margin-top:8px">'+b.scen.map(function(s){return '<div class="card0" style="padding:12px"><b>'+E(s)+'</b></div>';}).join("")+'</div>'+
 (next?'<div class="card0" style="margin-top:16px"><span class="eyebrow">Next</span><p style="margin:4px 0 0"><b>'+E(next.n)+' at '+next.from+'.</b> '+E(next.tag)+'. A guardian sees a preview before the birthday and can hold any default.</p></div>':"")+
 '<h3 style="margin-top:22px">The same ladder, end to end</h3><div class="tablewrap" style="margin-top:8px"><table style="min-width:640px"><thead><tr><th>Band</th><th>Her home</th><th>What becomes hers</th><th>Guardian view</th></tr></thead><tbody>'+AGES.map(function(x){return '<tr'+(x===b?' style="background:var(--accent-soft)"':"")+'><td><b>'+(x.from===x.to?x.from:x.from+"–"+x.to)+'</b> '+E(x.n)+'</td><td>'+E(x.tag)+'</td><td>'+E(x.hers.split(".")[0])+'.</td><td>'+(x.id==="a"||x.id==="t"?"Full":x.id==="b"?"Full, lighter":x.id==="c"?"Shrinking":x.id==="d"?"Mostly her choice":"By invitation")+'</td></tr>';}).join("")+'</tbody></table></div>'+
 '<p class="note-a" style="color:var(--muted);margin-top:10px">Only the maturation-ladder rungs (about 10, 13, 14, 15, 16, 17 and 18) are existing, permanent product rules. The other age defaults here are proposals a guardian can hold or change.</p>';
};

/* ============================================================ FAMILY BUILDER */
var TEMPLATES={
 two:{n:"Two homes",homes:["Mom’s house","Dad’s house"],people:[["Mom","guardian","live",0,0],["Dad","guardian","live",0,1]]},
 blend:{n:"Blended family",homes:["Mom’s house","Dad’s house"],people:[["Mom","guardian","live",0,0],["Dad","guardian","live",0,1],["Jordan","step-parent","message",0,0]]},
 kin:{n:"Grandparent raising her",homes:["Nana’s house"],people:[["Nana","guardian","live",0,0],["Mom","parent","message",0,0],["Dad","parent","postcard",0,0]]},
 away:{n:"A parent deployed",homes:["Mom’s house","Nana’s"],people:[["Mom","guardian","live",0,0],["Dad","guardian","message",1,0],["Nana","relative","live",0,1]]},
 inc:{n:"A parent incarcerated",homes:["Mom’s house"],people:[["Mom","guardian","live",0,0],["Dad","guardian","voice line",1,0],["Nana","relative","live",0,0]]},
 foster:{n:"Foster care",homes:["The Rivas home"],people:[["Ms. Rivas","foster parent","live",0,0],["Mom","parent","supervised",0,0],["Mr. Cole","caseworker","message",0,0]]},
 village:{n:"One parent and a village",homes:["Mom’s house","Nana’s"],people:[["Mom","guardian","live",0,0],["Nana","relative","live",0,1],["Aunt Mia","trusted adult","message",0,0]]}};
var ROLES=["guardian","parent","step-parent","relative","trusted adult","sitter","foster parent","caseworker","therapist"];
var CONTACTS=["live","message","postcard","voice line","supervised"];
var ADD=[["Aunt Mia","trusted adult","message"],["Jordan","step-parent","message"],["Grandpa Lou","relative","live"],["Ms. Okafor","sitter","message"]];
var F={tpl:"away",draft:null,applied:null,hold:false,msg:""};
function clone(t){return JSON.parse(JSON.stringify(t));}
function load(k){F.tpl=k;var t=TEMPLATES[k];F.draft={homes:t.homes.slice(),people:t.people.map(function(p){return {name:p[0],role:p[1],contact:p[2],away:!!p[3],home:p[4]};})};F.applied=clone(F.draft);F.hold=false;F.msg="";}
function derive(s){
 var away=s.people.filter(function(p){return p.away;}),tiles=[],hero="My day",heroSub="School, then home",notes=[];
 tiles.push(["dice","Play"],["book","Stories"],["palette","My colour"]);
 if(away.length){hero="The path home";heroSub=away[0].name+" is far away";tiles.unshift(["moon","Two Skies"]);notes.push("Away status turns on Two Skies and the path home.");}
 if(s.people.some(function(p){return p.contact==="postcard"||p.away;})){tiles.push(["mail","Postcards"]);notes.push("A far-away or postcard contact adds Postcards.");}
 if(s.people.some(function(p){return p.contact==="voice line";})){tiles.push(["phone","Voice line"]);notes.push("A voice-line contact adds a weekly story slot.");}
 if(s.homes.length>1){tiles.push(["calendar","Weeks"],["layers","Packing"]);notes.push("More than one home adds Weeks and Packing buddy.");}
 if(s.people.some(function(p){return p.role==="foster parent"||p.role==="caseworker";})){tiles.push(["heart","My helpers"]);notes.push("A foster placement puts My helpers in front.");}
 if(s.people.some(function(p){return p.contact==="supervised";})){notes.push("A supervised contact shows calls as scheduled visits.");}
 var people=s.people.filter(function(p){return p.role!=="caseworker"&&p.role!=="therapist"&&p.role!=="sitter";});
 return {tiles:tiles.slice(0,7),hero:hero,heroSub:heroSub,people:people,notes:notes};
}
function icFor(c){return {live:"video",message:"chat",postcard:"mail","voice line":"phone",supervised:"calendar"}[c]||"chat";}
function childScreen(s){var d=derive(s);return {shell:"child",r:function(){
 var tiles=d.tiles.slice(0,6).map(function(t){return K.tile("std",{ic:t[0],title:t[1]});}).join("");
 var people=d.people.slice(0,4).map(function(p){return K.row({av:K.avatar(p.name.charAt(0),{size:36}),title:p.name,sub:p.away?"Far away right now":"",trail:K.iconBtn(icFor(p.contact),{kind:"tonal"})});}).join("");
 return K.sb()+K.top({logo:true,title:"Hi, Ivy",right:K.avatar("I",{size:40,ring:true})})+K.page(K.tile("hero",{ic:"calendar",title:d.hero,sub:d.heroSub,scene:d.hero==="The path home"?"hills":"paper"})+'<div class="grid3">'+tiles+'</div>'+K.sectionLabel("My people")+K.card(people));}};}

OBX.renderFamily=function(G){
 if(!F.draft)load(F.tpl);
 var changed=JSON.stringify(F.draft)!==JSON.stringify(F.applied),d=derive(F.draft),show=F.hold&&changed?F.applied:F.draft;
 var rows=F.draft.people.map(function(p,i){return '<div class="card0" style="padding:10px;display:grid;gap:6px"><div style="display:flex;gap:8px;align-items:center;justify-content:space-between"><b>'+E(p.name)+'</b><button class="btn0" data-a="fdel" data-v="'+i+'" aria-label="Remove '+E(p.name)+'">Remove</button></div><div class="grp"><span class="lbl">Role</span><select data-a="frole" data-i="'+i+'" aria-label="Role for '+E(p.name)+'">'+ROLES.map(function(r){return '<option'+(r===p.role?" selected":"")+'>'+r+'</option>';}).join("")+'</select><span class="lbl">Reached by</span><select data-a="fcontact" data-i="'+i+'" aria-label="Contact for '+E(p.name)+'">'+CONTACTS.map(function(r){return '<option'+(r===p.contact?" selected":"")+'>'+r+'</option>';}).join("")+'</select><label style="display:flex;gap:6px;align-items:center"><input type="checkbox" data-a="faway" data-i="'+i+'"'+(p.away?" checked":"")+'> Away</label></div></div>';}).join("");
 $("#p-family").innerHTML='<h2>A family, built by a parent</h2><p class="intro">Only a guardian can change this, at any time, as the family changes. The child can never see or edit it. What she sees is worked out from it, and reaches her only when a guardian says so. Pick a starting point, change anything, and watch her home follow.</p>'+
 '<div class="card0"><div class="grp"><span class="lbl">Start from</span>'+Object.keys(TEMPLATES).map(function(k){return '<button class="btn0" data-a="ftpl" data-v="'+k+'" aria-pressed="'+(F.tpl===k)+'">'+TEMPLATES[k].n+'</button>';}).join("")+'</div></div>'+
 '<div style="display:grid;grid-template-columns:minmax(0,1fr);gap:16px;margin-top:14px"><div class="card0"><h3>Homes and people</h3><p style="color:var(--muted);margin:2px 0 8px">Homes: '+F.draft.homes.map(E).join(" · ")+'</p><div style="display:grid;gap:8px">'+rows+'</div><div class="grp" style="margin-top:10px"><span class="lbl">Add</span>'+ADD.map(function(a,i){return '<button class="btn0" data-a="fadd" data-v="'+i+'">'+a[0]+' ('+a[1]+')</button>';}).join("")+'</div></div></div>'+
 '<div class="card0" style="margin-top:14px"><div class="grp"><label style="display:flex;gap:8px;align-items:center;font-weight:700"><input type="checkbox" data-a="fhold"'+(F.hold?" checked":"")+'> Hold until I’ve told her</label><button class="btn0" data-a="fapply" aria-pressed="false"'+(changed?"":" disabled")+'>Apply to Ivy</button><span class="lbl" id="fmsg">'+E(F.msg||(changed?(F.hold?"Held. Ivy still sees the old family.":"Not applied yet."):"Nothing to apply."))+'</span></div></div>'+
 '<div class="stage0" style="display:flex;flex-wrap:wrap;justify-content:center;gap:24px;background:var(--bench);border-radius:22px;padding:22px 12px;margin-top:14px"><div style="display:grid;gap:8px;justify-items:center"><span class="eyebrow">What Ivy sees now</span>'+K.frame(childScreen(F.applied),"phone",.8)+'</div><div style="display:grid;gap:8px;justify-items:center"><span class="eyebrow">After you apply</span>'+K.frame(childScreen(F.draft),"phone",.8)+'</div></div>'+
 '<h3 style="margin-top:20px">What in the structure drives what she sees</h3><div class="tablewrap" style="margin-top:8px"><table style="min-width:620px"><thead><tr><th>In the structure</th><th>On her side</th></tr></thead><tbody>'+
 [["A person away (with or without an end date)","Two Skies, the path home, Postcards"],["Reached by live calls","A call button next to their face"],["Reached by messages, postcards or a voice line","The matching button, or a weekly story slot"],["Reached by supervised visits","Calls appear as scheduled visits"],["More than one home","Weeks and Packing buddy"],["A foster parent or caseworker","My helpers in front; no role words shown to her"],["A role of caseworker, therapist or sitter","Not shown in her people; the role works in the background"],["The name she uses for someone","Exactly that name, on every screen"]].map(function(r){return '<tr><td>'+E(r[0])+'</td><td>'+E(r[1])+'</td></tr>';}).join("")+'</tbody></table></div>'+
 (d.notes.length?'<div class="card0" style="margin-top:14px"><b>This draft:</b><ul style="margin:.3em 0 0;padding-left:1.1em">'+d.notes.map(function(n){return '<li>'+E(n)+'</li>';}).join("")+'</ul></div>':"")+
 '<h3 style="margin-top:20px">Rules for the builder</h3><div class="cols" style="margin-top:8px">'+[["Parent only","Any guardian can edit. A child, a sitter, a step-parent or a helper never can. The other guardian sees every change at once; nothing is hidden between them."],["She is told on the parent’s terms","Big changes default to “hold until I’ve told her”. A story card can travel with the change, and the date she was told is kept."],["Orders are respected","If a court order sets a schedule, it is shown as set by order and is not editable here."],["Nothing is erased","Every change is dated and kept in the family history. Removing someone offers the memory box, not just a deleted face."],["Her words, not ours","She sees the names she uses and never roles, ladders or legal terms."],["Per child","Half-siblings each have their own structure. A link lets them play; it gives no adult any access to the other child."]].map(function(c){return '<div class="card0"><h3>'+c[0]+'</h3><p style="color:var(--muted);margin:0">'+c[1]+'</p></div>';}).join("")+'</div>';
};

OBX.handle=function(a,v,G){
 if(a==="ftpl"){load(v);return true;}
 if(a==="fhold"){F.hold=!F.hold;F.msg="";return true;}
 if(a==="fapply"){F.applied=clone(F.draft);F.msg="Applied. Ivy’s home now matches.";return true;}
 if(a==="fdel"){F.draft.people.splice(+v,1);F.msg="";return true;}
 if(a==="fadd"){var x=ADD[+v];if(!F.draft.people.some(function(p){return p.name===x[0];}))F.draft.people.push({name:x[0],role:x[1],contact:x[2],away:false,home:0});F.msg="";return true;}
 if(a==="ageivy"){ageState.age=5;return true;}
 return false;
};
document.addEventListener("change",function(e){var t=e.target;if(!t||!t.dataset)return;var i=+t.dataset.i;
 if(t.dataset.a==="frole"){F.draft.people[i].role=t.value;F.msg="";}
 else if(t.dataset.a==="fcontact"){F.draft.people[i].contact=t.value;F.msg="";}
 else if(t.dataset.a==="faway"){F.draft.people[i].away=t.checked;F.msg="";}
 else return;
 OBX.renderFamily({});});
document.addEventListener("input",function(e){if(e.target&&e.target.id==="agerange"){ageState.age=+e.target.value;OBX.renderAges({});var r=document.getElementById("agerange");if(r)r.focus();}});
})();
