/* Viewer: controls, overview, design system, atlas, flows. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc;
var $=function(s,r){return (r||document).querySelector(s);},$$=function(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));};
var EXPECTED="childHome inbox receipt pin list myday weeks journal lockAdvisory welcome guardianSetup obName obAge obGender obWho invitation addDevice pairingRedeem pairedDevicesList parentalControls colourPick colourDaily colourParent bdMonth bdDay bdMarked homework retake capture guardianHome sendguard banking meds exchange emergencyCard expenses handover briefing careNote availability busyFork deletion siblings quieting letters teachMe expiryDigest export yearbook gallery themePicker gamePicker jokebook handicap story checkers battleship wordsearch chess chain kim hunt findThing colouring doodle snapshot library theBook storyteller storySafety sharedReading liveCall liveDegrade callSecurity showcase collection showGuardian closingRitual ladder".split(" ");
var FLOWS=[
 ["First run",["welcome","obName","obAge","obGender","obWho","colourPick","bdMonth","bdDay","bdMarked"],"Eight small questions, each in her words. Skipping is always allowed."],
 ["A normal morning",["childHome","inbox","receipt","myday"],"What she opens first, in her frame, with his time as the aside."],
 ["Banking a bedtime message",["guardianHome","sendguard","banking","inbox","receipt"],"Recorded ahead, delivered by her clock, watched before school."],
 ["A call",["availability","liveCall","liveDegrade","closingRitual"],"A calm start, a kind recovery, the same goodbye every time."],
 ["Game night",["gamePicker","handicap","checkers","chain","jokebook"],"One door for everything she can play, tuned fairly in the background."],
 ["Pairing a device",["addDevice","pairingRedeem","pairedDevicesList"],"Role, code, scan, done, and revoke any time."],
 ["Show me",["showGuardian","showcase","collection","yearbook"],"He asks warmly, she shows, and it is kept."],
 ["Read together",["coViewAllowance","coViewInvite","coViewLeader","coViewChild"],"Small messages, never pixels. The child can always end it."],
 ["Colour of the day",["colourDaily","colourDayHub","colourSort","colourCritter","colourParent","colourSettings"],"Her colour is hers, a fact to everyone else, and it themes the activities."],
 ["Settings",["settingsHub","colourSettings","parentalControls","themePicker"],"Everything configurable, in one place, found by search or by group."]];
var G={tab:"overview",grp:"All",q:"",onlyNew:false,open:null,dform:null};

/* ---------------------------------------------------------- colour maths -- */
function toRGB(s){var m;if((m=/^#([0-9a-f]{6})$/i.exec(s)))return [parseInt(m[1].slice(0,2),16),parseInt(m[1].slice(2,4),16),parseInt(m[1].slice(4,6),16)];
 m=/hsl\((\d+) (\d+)% (\d+)%/.exec(s);if(!m)return [0,0,0];var h=+m[1],S=+m[2]/100,L=+m[3]/100,c=(1-Math.abs(2*L-1))*S,x=c*(1-Math.abs((h/60)%2-1)),mm=L-c/2,r=0,g=0,b=0;
 if(h<60){r=c;g=x;}else if(h<120){r=x;g=c;}else if(h<180){g=c;b=x;}else if(h<240){g=x;b=c;}else if(h<300){r=x;b=c;}else{r=c;b=x;}
 return [Math.round((r+mm)*255),Math.round((g+mm)*255),Math.round((b+mm)*255)];}
function lum(c){var a=c.map(function(v){v/=255;return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4);});return .2126*a[0]+.7152*a[1]+.0722*a[2];}
function ratio(a,b){var x=lum(toRGB(a)),y=lum(toRGB(b));return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
function vars(p,m){var o={};OB.theme(p,m).split(";").forEach(function(kv){var i=kv.indexOf(":");if(i>0)o[kv.slice(0,i).replace("--","")]=kv.slice(i+1);});return o;}
var PAIRS=[["ink on page","ink","bg"],["secondary text on card","ink2","surface"],["labels on card","ink3","surface"],["text on primary","onPri","pri"],["text on tint","onPriC","priC"],["primary as text on card","pri","surface"],["success on tint","ok","okC"],["warning on tint","warn","warnC"],["error on tint","bad","badC"],["info on tint","info","infoC"]];

/* ------------------------------------------------------------- chrome ---- */
function renderBar(){
 $("#pal").innerHTML=Object.keys(K.SEEDS).map(function(k){return '<button style="background:'+K.SEEDS[k].seed+'" data-a="pal" data-v="'+k+'" aria-pressed="'+(K.palette===k)+'" aria-label="'+K.SEEDS[k].n+'" title="'+K.SEEDS[k].n+'"></button>';}).join("");
 $("#palname").textContent=K.SEEDS[K.palette].n+" · "+K.SEEDS[K.palette].note;
 $$('[data-a="mode"]').forEach(function(b){b.setAttribute("aria-pressed",String(b.dataset.v===K.mode));});
 $$('[data-a="form"]').forEach(function(b){b.setAttribute("aria-pressed",String(b.dataset.v===K.form));});
 $('[data-a="ann"]').setAttribute("aria-pressed",String(K.annotate));
 var shipped=K.screens.filter(function(s){return !s.isNew;}).length,nw=K.screens.length-shipped;
 $("#pills").innerHTML='<span class="pill ok">'+shipped+' existing screens redrawn (79 listed in MARKUP, plus the come-back signal)</span><span class="pill acc">'+nw+' new feature screens</span><span class="pill">7 palettes × light and dark</span><span class="pill warn">Sample data: Ivy (6), Dad, Mom</span>';
 var T=[["overview","Overview"],["system","Design system"],["atlas","Screen atlas"],["flows","Flows"]];
 $("#tabs").innerHTML=T.map(function(t){return '<button role="tab" aria-selected="'+(G.tab===t[0])+'" data-a="tab" data-v="'+t[0]+'">'+t[1]+'</button>';}).join("");
 T.forEach(function(t){$("#p-"+t[0]).hidden=G.tab!==t[0];});
}
function byGrp(){var g={};K.screens.forEach(function(s){(g[s.grp]=g[s.grp]||[]).push(s);});return g;}

/* ------------------------------------------------------------ overview ---- */
function renderOverview(){
 var missing=EXPECTED.filter(function(id){return !K.byId(id);}),g=byGrp();
 var pick=["childHome","guardianHome","liveCall","coViewLeader"].map(K.byId).filter(Boolean);
 $("#p-overview").innerHTML='<h2>What changed, and what did not</h2><p class="intro">The refinement is in the craft: colour, type, depth, icons, spacing and illustration. The behaviour is untouched. Every rule the product already holds is kept and shown on the screens that rely on it.</p>'+
 '<div class="stage0" style="display:flex;flex-wrap:wrap;gap:20px 28px;justify-content:center;background:var(--bench);border-radius:22px;padding:28px 14px">'+pick.map(function(s){return '<div style="display:grid;gap:8px;justify-items:center"><div class="cell" role="button" tabindex="0" style="width:auto" data-a="open" data-v="'+s.id+'" aria-label="Open '+E(s.title)+'">'+K.frame(s,K.form,K.form==="tablet"?.62:.9)+'</div><b style="font:700 .95rem var(--font-display)">'+E(s.title)+'</b></div>';}).join("")+'</div>'+
 '<div class="cols" style="margin-top:18px">'+
 [["Premium, not loud","Soft depth from two tinted shadows, hairline borders, generous radius, and one illustration style. No gradients except on the single hero card per screen."],
  ["One system, seven palettes","The six palettes keep working. Olive is proposed as a seventh and as the new default. Day-part, overlap and warning colours are protected and never change with a palette."],
  ["Calm for her, clear for them","The child shell is larger, quieter and icon-first with a speak button on every screen. The guardian shell is denser and says things as sentences."],
  ["Motion follows the finger","No looping or attention-seeking motion anywhere. Pressed states respond within 40 ms; springs overshoot by at most 6%. Bedtime, homework, journal and emergency are still."]].map(function(c){return '<div class="card0"><h3>'+c[0]+'</h3><p style="color:var(--muted)">'+c[1]+'</p></div>';}).join("")+'</div>'+
 '<h2 style="margin-top:28px">Coverage</h2><p class="intro">Every screen in <code>MARKUP.html</code> is redrawn. '+(missing.length?'<b style="color:var(--bad)">Missing: '+missing.join(", ")+'</b>':'Nothing from the 79 is missing.')+' Plus the screens designed in the earlier rounds.</p>'+
 '<div class="tablewrap"><table style="min-width:420px"><thead><tr><th>Group</th><th>Screens</th><th>Examples</th></tr></thead><tbody>'+Object.keys(g).map(function(k){return '<tr><td><b>'+E(k)+'</b></td><td>'+g[k].length+'</td><td>'+g[k].slice(0,4).map(function(s){return E(s.title);}).join(", ")+(g[k].length>4?"…":"")+'</td></tr>';}).join("")+'<tr><td><b>Total</b></td><td><b>'+K.screens.length+'</b></td><td></td></tr></tbody></table></div>'+
 '<h2 style="margin-top:28px">Proposals to decide</h2><div class="card0"><ul style="margin:.2em 0 0;padding-left:1.1em"><li><b>Olive as the default palette.</b> Today’s default is the stock deep purple.</li><li><b>A bottom tab bar for guardians</b> (Today, Messages, Together, Family, Settings). Everything on the old home grid stays one tap away.</li><li><b>Fonts.</b> Bricolage Grotesque for headings and Atkinson Hyperlegible for text, chosen for character and legibility. Bundling them is a build decision.</li><li><b>Illustration.</b> The scenes are placeholders for commissioned art in the same flat, organic style.</li></ul></div>';
 mountOverviewHandlers();
}
function mountOverviewHandlers(){}

/* -------------------------------------------------------- design system ---- */
function renderSystem(){
 var v=vars(K.palette,K.mode),roles=[["bg","Page"],["surface","Card"],["surface2","Sunken"],["outline","Hairline"],["ink","Ink"],["ink2","Ink 2"],["ink3","Ink 3"],["pri","Primary"],["priC","Primary tint"],["accent","Her accent"]];
 var sem=[["ok","Success"],["warn","Warning"],["bad","Error"],["info","Info"]],dp=[["dpMorning","Morning"],["dpDay","School day"],["dpAfternoon","Afternoon"],["dpEvening","Evening"],["dpBed","Bedtime"],["dpNight","Night"]];
 function sw(k,l){var bg=v[k];var fg=lum(toRGB(bg))>.45?"#0d1a11":"#fff";return '<div style="background:'+bg+';color:'+fg+'"><b>'+l+'</b>'+k+'</div>';}
 var pal7=Object.keys(K.SEEDS).map(function(p){return '<div><div class="pv" style="'+K.theme(p,K.mode)+'"><span class="b">Primary</span><span class="c">Tint</span><span class="s">Card text</span></div><div class="eyebrow" style="margin-top:6px">'+K.SEEDS[p].n+'</div></div>';}).join("");
 var ctr="";Object.keys(K.SEEDS).forEach(function(p){["light","dark"].forEach(function(m){var vv=vars(p,m),worst=99,wn="";PAIRS.forEach(function(pr){var r=ratio(vv[pr[1]],vv[pr[2]]);if(r<worst){worst=r;wn=pr[0];}});ctr+='<span><b>'+K.SEEDS[p].n+'</b> '+m+'</span><span>weakest: '+wn+'</span><span class="mono">'+worst.toFixed(1)+':1</span><span class="'+(worst>=4.5?"ok":"no")+'">'+(worst>=4.5?"AA":"below AA")+'</span>';});});
 var cur="";PAIRS.forEach(function(pr){var r=ratio(v[pr[1]],v[pr[2]]);cur+='<span>'+pr[0]+'</span><span></span><span class="mono">'+r.toFixed(1)+':1</span><span class="'+(r>=4.5?"ok":"no")+'">'+(r>=4.5?"AA":"below AA")+'</span>';});
 var gal='<div class="ob gal" style="'+K.theme(K.palette,K.mode)+'">'+
  '<div class="btns" style="flex-wrap:wrap">'+K.btn("Primary",{})+K.btn("Tonal",{kind:"tonal"})+K.btn("Quiet",{kind:"ghost"})+K.btn("Remove",{kind:"danger"})+'</div><div class="btns">'+K.btn("Small",{size:"sm"})+K.btn("Child size",{size:"lg"})+'</div>'+
  '<div class="chips">'+K.chip("Neutral")+K.chip("Primary",{tone:"pri",ic:"leaf"})+K.chip("Success",{tone:"ok",ic:"check"})+K.chip("Warning",{tone:"warn",ic:"clock"})+K.chip("Error",{tone:"bad"})+K.chip("Info",{tone:"info"})+'</div>'+
  K.seg(["Visibility","Pacing"],0)+K.field("Label","Value",{ic:"user"})+'<div class="row" style="padding:0">'+K.avatar("I",{size:44,ring:true})+'<span class="rtxt"><b>Row with avatar</b><small>Secondary line</small></span>'+K.toggle(true)+K.toggle(false)+'</div>'+
  K.banner("pri","A banner explains something once.","info")+K.banner("warn","A warning looks like a warning.","warn")+K.ribbon({overlap:[40,10]})+K.dual({})+
  '<div class="grid3">'+K.tile("std",{ic:"book",title:"Standard"})+K.tile("std",{ic:"palette",title:"Standard"})+K.tile("std",{ic:"dice",title:"Standard"})+'</div>'+K.tile("feat",{ic:"chat",title:"Featured",sub:"A one-line description",badge:"2"})+K.tile("hero",{ic:"calendar",title:"Hero",sub:"The one big thing",scene:"hills"})+
  K.bubble("Goodnight, owl.",false,"7:04")+K.bubble("Goodnight, Dad.",true,"7:05")+K.progress(60)+K.empty("book","Nothing here yet","A sentence that says what will appear.")+'</div>';
 var typ=[["Display XL","800 34/1 Bricolage","The sleeps count","font:800 34px/1 var(--font-display)"],["Display L","800 26/1.05 Bricolage","Her home","font:800 26px/1.05 var(--font-display)"],["Title","800 22/1.05 Bricolage","Message banking","font:800 22px/1.1 var(--font-display)"],["Heading","800 16/1.2 Bricolage","Today","font:800 16px/1.2 var(--font-display)"],["Body","400 15/1.4 Atkinson","Ivy is getting ready for school.","font:400 15px/1.4 var(--font-body)"],["Body strong","700 14.5/1.4 Atkinson","Watched at 7:04 AM","font:700 14.5px/1.4 var(--font-body)"],["Caption","400 12.5/1.35 Atkinson","Before school","font:400 12.5px/1.35 var(--font-body)"],["Label","500 10.5/1 JetBrains Mono, caps","SATURDAY","font:500 10.5px/1 var(--font-mono);letter-spacing:.09em;text-transform:uppercase"]];
 $("#p-system").innerHTML='<h2>The design system</h2><p class="intro">Everything below is live and follows the palette, mode and device at the top.</p>'+
 '<div class="cols"><div class="card0"><h3>Colour roles</h3><p style="color:var(--muted)">Generated from one seed per palette. Light and dark are designed separately, not inverted.</p><div class="sw">'+roles.map(function(r){return sw(r[0],r[1]);}).join("")+'</div></div>'+
 '<div class="card0"><h3>Protected colours</h3><p style="color:var(--muted)">These carry meaning and never change with a palette or with her colour (§8.6.2).</p><div class="sw">'+sem.map(function(r){return sw(r[0],r[1]);}).join("")+dp.map(function(r){return sw(r[0],r[1]);}).join("")+'</div></div></div>'+
 '<h3 style="margin-top:22px">Seven palettes</h3><div class="cols" style="grid-template-columns:repeat(auto-fit,minmax(150px,1fr))">'+pal7+'</div>'+
 '<h3 style="margin-top:22px">Type</h3><div class="card0 spec-t">'+typ.map(function(t){return '<div><span class="eyebrow">'+t[0]+'</span><span><span style="'+t[3]+'">'+t[2]+'</span><br><code>'+t[1]+'</code></span></div>';}).join("")+'</div>'+
 '<div class="cols" style="margin-top:22px"><div class="card0"><h3>Spacing and shape</h3><div class="tok">'+["4","8","12","16","24","32"].map(function(s){return '<span>space '+s+'</span>';}).join("")+["radius 12","radius 16","radius 22","radius 26","pill"].map(function(s){return '<span>'+s+'</span>';}).join("")+'</div><p style="color:var(--muted)">Spacing keeps today’s 4 to 32 scale. Radii grow from 8/12/16 to 12/16/22/26 for a softer, more premium feel.</p></div>'+
 '<div class="card0"><h3>Depth</h3><div style="display:flex;gap:16px;padding:12px"><div class="ob" style="'+K.theme(K.palette,K.mode)+';height:auto;background:transparent;overflow:visible;width:90px"><div class="card" style="height:64px;display:grid;place-items:center">1</div></div><div class="ob" style="'+K.theme(K.palette,K.mode)+';height:auto;background:transparent;overflow:visible;width:90px"><div class="card" style="height:64px;display:grid;place-items:center;box-shadow:var(--shadow2)">2</div></div></div><p style="color:var(--muted)">Two elevations only, tinted by the palette and never pure black.</p></div></div>'+
 '<h3 style="margin-top:22px">Icons</h3><div class="card0"><div class="icogrid">'+K.ICONS.map(function(n){return '<div>'+I(n,26,1.8)+n+'</div>';}).join("")+'</div><p style="color:var(--muted)">One family, drawn on a 24 grid with a 1.8 stroke and round ends. There is no star, gift, cart or map pin, because the product forbids what those suggest (rewards, purchases, location).</p></div>'+
 '<h3 style="margin-top:22px">Components</h3>'+gal+
 '<h3 style="margin-top:22px">Motion</h3><div class="cols"><div class="card0"><p><b>Motion follows the finger. It never leads it.</b></p><ul style="margin:.3em 0 0;padding-left:1.1em;color:var(--muted)"><li>Driven: always. Consequence: under 400 ms. Ambient: four named surfaces. Autonomous: never.</li><li>Springs, not linear ramps; overshoot never above 6%.</li><li>A touched item moves within 40 ms, before a drag registers.</li><li>A swipeable row shows a 22 px peek of the next item.</li><li>Still surfaces crossfade: bedtime, homework, journal, emergency card.</li></ul></div>'+
 '<div class="card0"><h3>Try the press</h3><p style="color:var(--muted)">Press and hold: it responds within 40 ms.</p><div class="ob" style="'+K.theme(K.palette,K.mode)+';height:auto;background:transparent;overflow:visible"><span class="press">'+K.btn("Press me",{})+'</span></div></div></div>'+
 '<h3 style="margin-top:22px">Layout by posture</h3><div class="cols" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr))">'+[["phone","One column","1fr","150"],["foldCover","Presence + hero + More","1fr","150"],["foldMain","Two columns","1fr 1fr","150"],["foldTabletop","Content above, controls below","1fr","75"],["tablet","Two panes, or a reading column","1fr 1fr","150"]].map(function(p){return '<div><div class="postwf" style="grid-template-columns:'+p[2]+'"><div style="min-height:'+(p[0]==="foldTabletop"?60:p[3]/2)+'px">Content</div><div style="min-height:'+(p[0]==="foldTabletop"?60:p[3]/2)+'px">'+(p[2]==="1fr"?"Controls":"Detail")+'</div></div><div class="eyebrow" style="margin-top:6px">'+p[0]+'</div><small style="color:var(--muted)">'+p[1]+'</small></div>';}).join("")+'</div>'+
 '<h3 style="margin-top:22px">Accessibility, measured</h3><div class="cols"><div class="card0"><p style="color:var(--muted)">Contrast of this palette and mode (AA needs 4.5:1):</p><div class="ctr">'+cur+'</div></div><div class="card0"><p style="color:var(--muted)">The weakest pair in all 14 palette and mode combinations:</p><div class="ctr">'+ctr+'</div></div></div>'+
 '<div class="card0" style="margin-top:14px"><p style="margin:0">Targets: guardian 48 dp, child 64 dp, toddler 180 dp. Every screen has a read-aloud button on the child side. Dyslexia-friendly face, text size and reduce-motion are guardian settings. Nothing is conveyed by colour alone.</p></div>';
}

/* ---------------------------------------------------------------- atlas ---- */
function filtered(){return K.screens.filter(function(s){
 if(G.grp!=="All"&&s.grp!==G.grp)return false;if(G.onlyNew&&!s.isNew)return false;
 if(G.q&&(s.title+" "+s.id+" "+s.desc).toLowerCase().indexOf(G.q.toLowerCase())<0)return false;return true;});}
function renderAtlas(){
 var groups=["All"].concat(Object.keys(byGrp())),list=filtered(),sc={phone:.62,cover:.7,tablet:.4}[K.form];
 $("#p-atlas").innerHTML='<h2>Screen atlas</h2><p class="intro">'+K.screens.length+' screens. Click any to open it large with numbered notes, its original description and a switch between phone, cover and tablet. The palette, mode and device at the top apply to all of them.</p>'+
 '<div class="filters">'+groups.map(function(g){return '<button class="btn0" data-a="grp" data-v="'+E(g)+'" aria-pressed="'+(G.grp===g)+'">'+E(g)+'</button>';}).join("")+'</div>'+
 '<div class="filters"><input id="aq" type="search" placeholder="Search screens" aria-label="Search screens" value="'+E(G.q)+'"><button class="btn0" data-a="new" aria-pressed="'+G.onlyNew+'">Only new</button><span class="lbl">'+list.length+' shown</span></div>'+
 '<div class="atlas">'+list.map(function(s){return '<div class="cell" role="button" tabindex="0" data-a="open" data-v="'+s.id+'" aria-label="Open '+E(s.title)+'">'+K.frame(s,K.form,sc)+'<span class="cap"><b>'+E(s.title)+(s.isNew?'<span class="newtag">NEW</span>':"")+(s.wide?'<span class="newtag" style="background:var(--accent-soft);color:var(--accent)">2-PANE</span>':"")+'</b><small>'+E(s.grp)+'</small></span></div>';}).join("")+'</div>';
}
function openDetail(id){
 var s=K.byId(id);if(!s)return;G.open=id;G.dform=G.dform||K.form;
 var list=filtered(),i=list.indexOf(s),prev=list[i-1],next=list[i+1];
 var sheetW=Math.min(innerWidth-32,1100),stageMax=innerWidth<860?sheetW-80:sheetW-36-260-22-44,W0={phone:314,cover:274,tablet:714}[G.dform],sc=Math.min(1,stageMax/W0);
 var saveAnn=K.annotate;
 $("#detail").innerHTML='<div class="sheet0"><header><div><div class="eyebrow">'+E(s.grp)+' · '+E(s.shell)+' shell'+(s.since?' · since '+E(s.since):"")+'</div><h2>'+E(s.title)+'</h2></div><div class="grp">'+
  ["phone","cover","tablet"].map(function(f){return '<button class="btn0" data-a="dform" data-v="'+f+'" aria-pressed="'+(G.dform===f)+'">'+({phone:"Phone",cover:"Fold cover",tablet:"Tablet"})[f]+'</button>';}).join("")+'<button class="btn0" data-a="ann" aria-pressed="'+K.annotate+'">Notes</button>'+
  '<button class="btn0" data-a="prev" '+(prev?"":"disabled")+' aria-label="Previous screen">‹</button><button class="btn0" data-a="next" '+(next?"":"disabled")+' aria-label="Next screen">›</button><button class="btn0" data-a="close">Close</button></div></header>'+
  '<div class="dgrid"><div class="dstage">'+K.frame(s,G.dform,sc)+'</div><div class="notes"><p style="margin:0;color:var(--muted)">'+E(s.desc)+'</p>'+(s.notes.length?'<ol>'+s.notes.map(function(n){return '<li><span class="nb">'+n[0]+'</span><span>'+E(n[1])+'</span></li>';}).join("")+'</ol>':"")+
  '<div class="card0" style="margin-top:8px"><span class="eyebrow">Layout</span><p style="margin:4px 0 0;color:var(--muted)">'+(s.wide?"Two panes on tablet (columnsAt gated). One column on phone.":"One column, capped to a reading width on tablet.")+(G.dform==="cover"&&!s.cover?" Uses the phone layout at the narrower cover width.":"")+'</p></div></div></div></div>';
 $("#detail").hidden=false;$("#detail").scrollTop=0;document.body.style.overflow="hidden";
}
function closeDetail(){$("#detail").hidden=true;document.body.style.overflow="";G.open=null;}

/* ---------------------------------------------------------------- flows ---- */
function renderFlows(){
 $("#p-flows").innerHTML='<h2>Flows</h2><p class="intro">The same screens, in the order a family meets them. Click a screen to open it.</p>'+FLOWS.map(function(f){return '<div style="margin-bottom:22px"><h3>'+f[0]+'</h3><p style="color:var(--muted);margin:2px 0 8px">'+f[2]+'</p><div class="flow">'+f[1].map(function(id,i){var s=K.byId(id);if(!s)return "";return (i?'<span class="arr">›</span>':"")+'<div class="step" role="button" tabindex="0" data-a="open" data-v="'+id+'" aria-label="Open '+E(s.title)+'">'+K.frame(s,K.form,K.form==="tablet"?.3:.46)+'<small>'+E(s.title)+'</small></div>';}).join("")+'</div></div>';}).join("");
}

/* ------------------------------------------------------------- wiring ---- */
function all(){renderBar();if(G.tab==="overview")renderOverview();else if(G.tab==="system")renderSystem();else if(G.tab==="atlas")renderAtlas();else renderFlows();
 if(G.open&&!$("#detail").hidden)openDetail(G.open);}
document.addEventListener("click",function(e){
 var el=e.target.closest("[data-a]");if(!el||el.disabled)return;var a=el.dataset.a,v=el.dataset.v;
 if(a==="pal")K.palette=v;else if(a==="mode")K.mode=v;else if(a==="form"){K.form=v;G.dform=v;}
 else if(a==="ann")K.annotate=!K.annotate;else if(a==="tab")G.tab=v;else if(a==="grp")G.grp=v;else if(a==="new")G.onlyNew=!G.onlyNew;
 else if(a==="open"){openDetail(v);return;}else if(a==="close"){closeDetail();return;}
 else if(a==="dform"){G.dform=v;openDetail(G.open);return;}
 else if(a==="prev"||a==="next"){var l=filtered(),i=l.indexOf(K.byId(G.open)),t=l[i+(a==="next"?1:-1)];if(t)openDetail(t.id);return;}
 all();
});
document.addEventListener("input",function(e){if(e.target&&e.target.id==="aq"){G.q=e.target.value;renderAtlas();var q=$("#aq");q.focus();q.setSelectionRange(q.value.length,q.value.length);}});
document.addEventListener("keydown",function(e){var f=document.activeElement;if((e.key==="Enter"||e.key===" ")&&f&&f.getAttribute&&f.getAttribute("role")==="button"&&f.dataset.a){e.preventDefault();f.click();return;}if($("#detail").hidden)return;if(e.key==="Escape")closeDetail();if(e.key==="ArrowRight")$('[data-a="next"]').click();if(e.key==="ArrowLeft")$('[data-a="prev"]').click();});
/* annotation badge class is read at render time */
var _r=OB.render;OB.render=function(s,f){var h=_r(s,f);return OB.annotate?h.replace('class="ob ','class="ob ann '):h;};
all();
})();
