/* The Olive umbrella: viewer. */
(function(){
"use strict";
var K=OB,E=K.esc;
var $=function(s,r){return (r||document).querySelector(s);},$$=function(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));};
var SUITES={
 A:{n:"Distance",b:"Staying close across miles",d:"For a parent far away: deployed, travelling, incarcerated or in hospital."},
 B:{n:"Rhythm",b:"Predictable days across two homes",d:"Routines, transitions and a calm app that feels the same everywhere."},
 C:{n:"Voice",b:"Her own safe ways to say what she needs",d:"Private feelings, a worry box, helpers she picks, and symbols for a child with little speech."},
 D:{n:"Village",b:"Everyone who loves her, sized right",d:"Grandparents, step-parents, siblings, sitters and the school."},
 E:{n:"Together",b:"Doing things side by side",d:"Cooking, planting, building, singing and reading, in two places at once."},
 F:{n:"Care",b:"Health and hard seasons",d:"A care binder, hospital mode, gentle explanations of hard things."},
 G:{n:"Growing",b:"Memory and what she keeps",d:"Time capsules, firsts, a memory box, growing marks."},
 H:{n:"Circle",b:"Professionals and fairness",d:"A therapist’s view, fair swaps, a care summary for a clinic."},
 I:{n:"Compass",b:"How the app fits each family",d:"The setup and shelf that turn suites on, per child."},
 J:{n:"Growing up",b:"An app that grows with her",d:"What changes at each age, what becomes hers, and how a birthday arrives."},
 K:{n:"Family structure",b:"Built by a parent, synced to the child",d:"Describe the family as it is. What she sees follows, when a guardian says."}};
var MAKEUPS={sep:"Two homes after a separation",mil:"A parent who is deployed",road:"A parent who travels for work",inc:"A parent who is incarcerated",hosp:"A parent or child in hospital",kin:"A grandparent or relative raising her",fost:"Foster care",blend:"Step-parents and blended family",loss:"A death in the family",vil:"A wide village of relatives and friends"};
var NEEDS={neuro:"Neurodivergent or ADHD",sens:"Sensory sensitivities",anx:"Big worries or anxiety",deaf:"Deaf or hard of hearing",blind:"Blind or low vision",aac:"Little or no speech",bil:"Another language at home",ill:"Chronic illness",grief:"Grief",school:"Extra help with school",tod:"Very young (2 to 4)",teen:"Older (13 and up)"};
var BOLD=[
 ["twoSkies","Two Skies","Makes distance feel like one shared world. “It’s the same moon.” Small to build, big to feel."],
 ["milestoneVault","Milestone vault","Recorded ahead for moments that haven’t happened: a first tooth, a hard night. She can ask for one."],
 ["needHelp","I need help","A button that connects her to a person she chose. Not a report about her. Needs clinicians and a lawyer."],
 ["oneRoutine","One routine, two houses","Both homes agree a bedtime ritual with pictures. Agreement, not scoring."],
 ["grandCorner","Grandparent corner","Four huge buttons and a phone line, so the oldest voices stay in the room."],
 ["symbols","Say it with symbols","A symbol board that turns pictures into a sentence for any reader."],
 ["timeCapsule","Time capsule","Sealed letters that open at her rungs on the maturation ladder. Sealed means sealed."],
 ["hospitalMode","Hospital mode","Her home shrinks to what matters today: the plan, who is coming, and one big call button."]];
var REFUSED=[["Live location, geofences, “find my child”","P3. Places are named by feeling (“somewhere warm”), never coordinates."],["A cloned or generated parent voice or face","P1. Memory box, stories and the vault use only real recordings."],["Mood dashboards, trend lines, “she seems low this week”","§8.6.4 and P7. A feeling is hers; nobody keeps a chart."],["Streaks, badges, “days since you called”","P2. Chapters and paths, never counts of absence."],["A parent reading her worry box, journal or feelings","P7. She chooses who sees something, each time."],["Gifting, wish-list buying, one-tap presents","P4. Nothing here has a price."],["Taking over her device to calm or guide her","P11. A request she answers, never a takeover."],["Telling a parent’s tone to “improve”","Parked by the owner. Swap requests use fixed, neutral templates instead."]];
var FAMILIES=[
 {n:"The Reyes family",d:"Dad is deployed. Mom and Nana raise Ivy, 6, who has big worries at night.",on:["twoSkies","awayMode","milestoneVault","postcard","oneRoutine","firstThen","feelingsWeather","myHelpers","grandCorner","storyStudio"]},
 {n:"The Okafors",d:"Two homes and a step-parent. Leo, 9, has ADHD and half-sister Ivy lives across town.",on:["oneRoutine","firstThen","packingBuddy","sensoryProfile","stepWelcome","siblingSpace","swapRequest","schoolBridge","firstTimes"]},
 {n:"The Lins",d:"Grandma is raising Mei, 5, who is Deaf. Dad is in the next state, Mom is no longer here.",on:["childDeafHome","grandCorner","familyTree","memoryBox","timeCapsule","needHelp","myHelpers","buildAlong","careSummary"]}];

var OBX=window.OBX=window.OBX||{};
var G={tab:"umbrella",pickM:[],pickN:[],open:null};

function renderBar(){
 $("#pal").innerHTML=Object.keys(K.SEEDS).map(function(k){return '<button style="background:'+K.SEEDS[k].seed+'" data-a="pal" data-v="'+k+'" aria-pressed="'+(K.palette===k)+'" aria-label="'+K.SEEDS[k].n+'" title="'+K.SEEDS[k].n+'"></button>';}).join("");
 $$('[data-a="mode"]').forEach(function(b){b.setAttribute("aria-pressed",String(b.dataset.v===K.mode));});
 $('[data-a="ann"]').setAttribute("aria-pressed",String(K.annotate));
 var n=K.screens.length,s=Object.keys(SUITES).length;
 $("#pills").innerHTML='<span class="pill acc">'+n+' concept screens</span><span class="pill">'+s+' suites</span><span class="pill">'+Object.keys(MAKEUPS).length+' family makeups · '+Object.keys(NEEDS).length+' child needs</span><span class="pill warn">Every idea is a proposal</span>';
 var T=[["umbrella","The umbrella"],["ages","Growing up"],["family","Family builder"],["compass","Family Compass"],["suites","All suites"],["bold","Bold bets"],["roadmap","Order and guardrails"]];
 $("#tabs").innerHTML=T.map(function(t){return '<button role="tab" aria-selected="'+(G.tab===t[0])+'" data-a="tab" data-v="'+t[0]+'">'+t[1]+'</button>';}).join("");
 T.forEach(function(t){$("#p-"+t[0]).hidden=G.tab!==t[0];});
}
function eff(e){return '<span class="tag2 '+e.toLowerCase()+'">'+({S:"SMALL",M:"MEDIUM",L:"LARGE"})[e]+'</span>';}
function tagsOf(id){var m=K.meta?K.meta[id]:null;return m;}
function card(s,why){var m=OB.meta[s.id];return '<div class="rcard" role="button" tabindex="0" data-a="open" data-v="'+s.id+'" aria-label="Open '+E(s.title)+'"><div style="display:grid;place-items:center">'+K.frame(s,"phone",.5)+'</div><div><b style="font:800 1rem var(--font-display)">'+E(s.title)+'</b><div><span class="tag2">'+SUITES[m.suite].n+'</span>'+eff(m.effort)+'</div></div>'+(why?'<div class="why">'+why+'</div>':'<div class="why">'+E(m.desc.split(". ")[0])+'.</div>')+'</div>';}

function renderUmbrella(){
 var cells=Object.keys(SUITES).filter(function(k){return k!=="I"&&k!=="J"&&k!=="K";});
 var grid="";cells.forEach(function(k,i){
  if(i===4)grid+='<div class="core"><b>Olive core</b><span>Today · Messages · Play · Memory</span><small style="opacity:.85">The same calm home for every family</small></div>';
  var n=K.screens.filter(function(s){return OB.meta[s.id].suite===k;}).length;
  grid+='<button class="su" data-a="suite" data-v="'+k+'"><span class="k">Suite '+k+'</span><b>'+SUITES[k].n+'</b><small>'+SUITES[k].b+'</small><span class="tag2" style="justify-self:start">'+n+' concepts</span></button>';});
 $("#p-umbrella").innerHTML='<h2>One app, many suites</h2><p class="intro">The core is what every family has. Around it sit suites a guardian can switch on for a child, one at a time. A suite changes tiles and tools in the same shell, so a child who moves between two houses never feels lost.</p><div class="umb">'+grid+'</div>'+
 '<h2 style="margin-top:28px">How it works</h2><div class="cols">'+[["1. The Family Compass","Three short, skippable screens: how your family looks, what helps her, and what to try. It never labels anyone."],["2. A few suggestions","At most five, each with a reason in plain words. Nothing turns on for the child without a guardian’s yes."],["3. Per child","Siblings can have different suites. A guardian can add or remove any, any day."],["4. Her home adapts","The same shell with different tiles. A far-away parent’s family gets Two Skies and a path home; a hospital stay gets a calmer, smaller home."],["5. She grows into it","The maturation ladder hands more of it to her over time. Some things, like her helpers and her sharing choices, become hers."]].map(function(c){return '<div class="card0"><h3>'+c[0]+'</h3><p style="color:var(--muted)">'+c[1]+'</p></div>';}).join("")+'</div>'+
 '<h2 style="margin-top:28px">Three families, three apps</h2><div class="cols">'+FAMILIES.map(function(f){return '<div class="fam"><h3>'+f.n+'</h3><p style="color:var(--muted);margin:0">'+f.d+'</p><div class="chipset">'+f.on.map(function(id){var s=K.byId(id);return s?'<button class="tg" data-a="open" data-v="'+id+'">'+E(s.title)+'</button>':"";}).join("")+'</div></div>';}).join("")+'</div>';
}

function scoreFor(id){var m=OB.meta[id],mk=(m.for||[]).filter(function(x){return G.pickM.indexOf(x)>-1;}),nd=(m.needs||[]).filter(function(x){return G.pickN.indexOf(x)>-1;});return {score:mk.length+nd.length,mk:mk,nd:nd};}
function renderCompass(){
 var pickedAny=G.pickM.length||G.pickN.length;
 var rows=K.screens.filter(function(s){return !OB.meta[s.id].all&&scoreFor(s.id).score>0;}).map(function(s){return {s:s,r:scoreFor(s.id)};}).sort(function(a,b){return b.r.score-a.r.score;});
 var res="";
 if(!pickedAny)res='<p class="intro">Pick any of the above. A family can pick none.</p>';
 else if(!rows.length)res='<p class="intro">Nothing specific matches. The core is the right place to start.</p>';
 else res='<div class="res">'+rows.slice(0,12).map(function(x){var why=x.r.mk.map(function(k){return MAKEUPS[k];}).concat(x.r.nd.map(function(k){return NEEDS[k];}));return card(x.s,"Because: "+E(why.join("; ")));}).join("")+'</div>';
 var compass=["compassWho","compassNeeds","compassSuggest","suitesShelf"].map(K.byId);
 $("#p-compass").innerHTML='<h2>The Family Compass</h2><p class="intro">Try it. This is the logic behind the three setup screens: tick what fits and see which concepts it suggests, and why. The app would show at most five.</p>'+
 '<div class="card0"><h3>How does your family look?</h3><div class="chipset" style="margin:8px 0 14px">'+Object.keys(MAKEUPS).map(function(k){return '<button class="tg" data-a="pm" data-v="'+k+'" aria-pressed="'+(G.pickM.indexOf(k)>-1)+'">'+MAKEUPS[k]+'</button>';}).join("")+'</div><h3>What helps her day go well?</h3><div class="chipset" style="margin-top:8px">'+Object.keys(NEEDS).map(function(k){return '<button class="tg" data-a="pn" data-v="'+k+'" aria-pressed="'+(G.pickN.indexOf(k)>-1)+'">'+NEEDS[k]+'</button>';}).join("")+'</div></div>'+res+
 '<h2 style="margin-top:28px">The setup, as it would look</h2><div class="stage0" style="display:flex;flex-wrap:wrap;gap:20px;justify-content:center;background:var(--bench);border-radius:22px;padding:24px 12px">'+compass.map(function(s){return '<div class="cell" role="button" tabindex="0" data-a="open" data-v="'+s.id+'" style="width:auto">'+K.frame(s,"phone",.72)+'<span class="cap"><b>'+E(s.title)+'</b></span></div>';}).join("")+'</div>';
}

function renderSuites(){
 var h='<h2>All suites</h2><p class="intro">'+K.screens.length+' concept screens. Click any to see it large with what it does, what it builds on, the rules it keeps, and the question still open.</p>';
 Object.keys(SUITES).forEach(function(k){var list=K.screens.filter(function(s){return OB.meta[s.id].suite===k;});if(!list.length)return;
  h+='<div id="su-'+k+'" style="margin-top:26px"><div class="eyebrow">Suite '+k+'</div><h2>'+SUITES[k].n+'</h2><p class="intro" style="margin:2px 0 6px">'+SUITES[k].d+'</p><div class="res">'+list.map(function(s){return card(s);}).join("")+'</div></div>';});
 $("#p-suites").innerHTML=h;
}
function renderBold(){
 $("#p-bold").innerHTML='<h2>Bold bets</h2><p class="intro">The ideas I would argue for first, because each does something no co-parenting tool does, and each keeps the product’s promises.</p><div class="bold">'+BOLD.map(function(b){var s=K.byId(b[0]);return '<div class="b" role="button" tabindex="0" data-a="open" data-v="'+b[0]+'">'+K.frame(s,"phone",.46)+'<div><b style="font:800 1.15rem var(--font-display)">'+E(b[1])+'</b><p style="color:var(--muted);margin:6px 0">'+E(b[2])+'</p>'+eff(OB.meta[b[0]].effort)+'<span class="tag2">'+SUITES[OB.meta[b[0]].suite].n+'</span></div></div>';}).join("")+'</div>';
}
function renderRoadmap(){
 var tier={S:[],M:[],L:[]};K.screens.forEach(function(s){var m=OB.meta[s.id];if(!m.all)tier[m.effort].push(s);});
 var col=function(t,title,sub){return '<div class="col"><h3>'+title+'</h3><p style="color:var(--muted);margin:0 0 8px;font-size:.9rem">'+sub+'</p>'+tier[t].map(function(s){return '<div class="it" role="button" tabindex="0" data-a="open" data-v="'+s.id+'"><b>'+E(s.title)+'</b><span class="tag2">'+SUITES[OB.meta[s.id].suite].n+'</span></div>';}).join("")+'</div>';};
 $("#p-roadmap").innerHTML='<h2>A sensible order</h2><p class="intro">By effort, because each of the small ones reuses something already built. Real use of any of it still depends on the sign-in, family-creation and delivery work, which come first.</p><div class="rm">'+
  col("S","Small","Reuse what exists. Good to build first.")+col("M","Medium","A new screen or two on a proven module.")+col("L","Large","New infrastructure, or needs outside experts.")+'</div>'+
 '<h2 style="margin-top:28px">Needs experts before any build</h2><div class="card0"><ul style="margin:.2em 0 0;padding-left:1.1em"><li><b>I need help</b> and <b>Hospital mode</b>: child-life specialists, clinicians and a lawyer.</li><li><b>Explainer cards</b> and the <b>Memory box</b>: child-development and bereavement experts.</li><li><b>Say it with symbols</b> and the <b>Deaf-first home</b>: speech-language specialists and Deaf community co-designers.</li><li><b>Care binder</b> and <b>Care summary</b>: health-privacy law.</li><li><b>Phone bridge</b>: telephony vendors and the rules of each place.</li></ul></div>'+
 '<h2 style="margin-top:28px">Ideas I would refuse, and why</h2><div class="refuse">'+REFUSED.map(function(r){return '<div><b>'+E(r[0])+'</b><span>'+E(r[1])+'</span></div>';}).join("")+'</div>';
}

function openDetail(id){
 var s=K.byId(id),m=OB.meta[id];if(!s)return;G.open=id;
 var sc=Math.min(1,(Math.min(innerWidth,1100)-(innerWidth<860?80:36+300+22+44))/314);
 var who=(m.for||[]).map(function(k){return MAKEUPS[k];}).concat((m.needs||[]).map(function(k){return NEEDS[k];}));
 $("#detail").innerHTML='<div class="sheet0"><header><div><div class="eyebrow">Suite '+m.suite+' · '+SUITES[m.suite].n+'</div><h2>'+E(s.title)+'</h2></div><div class="grp"><button class="btn0" data-a="ann" aria-pressed="'+K.annotate+'">Notes</button><button class="btn0" data-a="close">Close</button></div></header>'+
  '<div class="dgrid"><div class="dstage">'+K.frame(s,"phone",sc)+'</div><div class="det"><p style="margin:0;font-size:1.02rem">'+E(m.desc)+'</p>'+(s.notes.length?'<h4>On the screen</h4><ol class="notes" style="padding:0;margin:0">'+s.notes.map(function(n){return '<li style="list-style:none;display:grid;grid-template-columns:24px 1fr;gap:8px;margin:6px 0"><span class="nb">'+n[0]+'</span><span>'+E(n[1])+'</span></li>';}).join("")+'</ol>':"")+
  '<h4>What it does</h4><ul>'+(m.funcs||[]).map(function(f){return '<li>'+E(f)+'</li>';}).join("")+'</ul><h4>Who it helps</h4><div>'+(m.all?'<span class="tag2">Every family</span>':who.map(function(w){return '<span class="tag2">'+E(w)+'</span>';}).join(""))+'</div><h4>Builds on</h4><p style="margin:0">'+E(m.builds)+'</p><h4>Rules it keeps</h4><p style="margin:0">'+E(m.rails)+'</p><h4>Size</h4><p style="margin:0">'+eff(m.effort)+'</p><h4>Still open</h4><p style="margin:0;color:var(--warn)">'+E(m.open)+'</p></div></div></div>';
 $("#detail").hidden=false;$("#detail").scrollTop=0;document.body.style.overflow="hidden";
}
function closeDetail(){$("#detail").hidden=true;document.body.style.overflow="";G.open=null;}
function all(){renderBar();({umbrella:renderUmbrella,ages:function(){OBX.renderAges(G);},family:function(){OBX.renderFamily(G);},compass:renderCompass,suites:renderSuites,bold:renderBold,roadmap:renderRoadmap})[G.tab]();if(G.open&&!$("#detail").hidden)openDetail(G.open);}
document.addEventListener("click",function(e){
 var el=e.target.closest("[data-a]");if(!el)return;var a=el.dataset.a,v=el.dataset.v;
 if(a==="pal")K.palette=v;else if(a==="mode")K.mode=v;else if(a==="ann")K.annotate=!K.annotate;else if(a==="tab")G.tab=v;
 else if(a==="pm"){var i=G.pickM.indexOf(v);if(i>-1)G.pickM.splice(i,1);else G.pickM.push(v);}
 else if(a==="pn"){var j=G.pickN.indexOf(v);if(j>-1)G.pickN.splice(j,1);else G.pickN.push(v);}
 else if(OBX.handle&&OBX.handle(a,v,G)){}
 else if(a==="suite"){G.tab="suites";all();var t=$("#su-"+v);if(t)t.scrollIntoView();return;}
 else if(a==="open"){openDetail(v);return;}else if(a==="close"){closeDetail();return;}
 all();
});
document.addEventListener("keydown",function(e){var f=document.activeElement;if((e.key==="Enter"||e.key===" ")&&f&&f.getAttribute&&f.getAttribute("role")==="button"&&f.dataset.a){e.preventDefault();f.click();return;}if(e.key==="Escape"&&!$("#detail").hidden)closeDetail();});
var _r=OB.render;OB.render=function(s,f){var h=_r(s,f);return OB.annotate?h.replace('class="ob ','class="ob ann '):h;};
all();
})();
