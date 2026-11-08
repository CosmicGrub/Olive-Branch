/* mod-guardian.js  (agent GRD)  LIVE prototype, guardian-side features. SIMULATION: no real server.
 *
 * KEYS THIS MODULE WRITES FOR THE CHILD DEVICE (agent KID reads them). All live under S.kid.ga.* ("guardian-authored"; NOT S.kid.g, which KID uses for game state).
 * Every key is written ONLY by a simulated server route (PUT /v1/child-content/:key) after the guardian publishes it,
 * so a guardian who is offline queues the change (S.grd.outbox) and Ivy's tablet does not see it until it is delivered.
 * Each write bumps S.kid.ga.rev and sets S.kid.ga.updated[key]=virtual ms, then emits 'grd:published' {key}.
 *   access     {readAloud,reduceMotion,roomy,larger,textSize:'standard|large|largest'}   (captions are NOT built: never present)
 *   play       {on,open:'HH:MM',rest:'HH:MM',wind:0|15|30,bed:'HH:MM'}  her time. Use L.grd.playState().
 *   playNow    'open'|'winding'|'closed'  (derived, refreshed on time:tick; emits 'grd:play' when it changes)
 *   art        'watercolour'|'paper'|'soft'|'crayon'      colourAsk bool (daily colour question on/off)
 *   palette    key of OB.SEEDS   mode 'light'|'dark'  (the look of HER app, chosen by a guardian)
 *   people     [{id,name,role,home:'a'|'b'|'',away,reach:{messages,calls,story}}]  homes [{id,name,who:[ids]}]
 *   rhythm     {kind:'alt'|'2255'|'own',pattern:'14 letters m/d',anchor,exchange,locked}   (released family structure = 'My people')
 *   bandHold   {on,from,to}|null    L.grd.effectiveBand() returns the band her home should still show
 *   hiddenTiles [tileId]   pace {tileId:minutes}   (tile ids: games stories draw read colour; messages can never be hidden)
 *   routine [{text,time}]  firstThen [{first,then}]  packing [{text,packed}]  newPlace [{place,note}]  sensory {loud,bright,scratchy,crowds,surprises}
 *   helpers [{name,what}]  symbols [{label,word}]  feelings bool
 *   capsule [{text,openOn}]  firstTimes [{text,date}]  marks [{label,value,date}]
 *   poorly [{text}]  visit [{text}]
 *   village {sitter:{name,from,until,notes,tonight:bool}, grand:{greeting,likes,bedtime}, school:{text}}
 *   compass {q1,q2}   shelf {rhythm,voice,growing,care,village,compass:bool}   profiles {dhh,away}
 * Public helpers (on L.grd, because core owns L.guardian): L.grd.playState(), L.grd.effectiveBand(), L.grd.houseOn('YYYY-MM-DD'), L.grd.partnerName().
 * Events emitted: 'family:changed' {what:'structure',by,source:'guardian',entry}, 'grd:published' {key}, 'grd:play' {state}, 'grd:notify' {to,text},
 *   'device:revoked' (core's). Writes to CORE-owned fields: S.family.pin on PIN change; S.dev.g.sessionOk=false on sign out / account deletion.
 * Screens (dev 'g'): g-colour g-look g-band g-access g-play g-family g-fam-person g-fam-preview g-history g-planner g-devices g-adults
 *   g-partner g-pin g-controls g-data g-delete g-hold g-session g-learn g-learn-choices g-learn-day g-learn-check g-learn-rules
 *   g-care g-emergency g-hospital g-meds g-med g-bag g-binder g-appt g-handover g-schedule g-swap g-expenses g-overlap
 *   g-suites g-s-rhythm g-s-voice g-s-growing g-s-care g-s-village g-s-compass
 * Server routes (/v1/...): emergency-card, medications(+doses,retire), handover-notes, swaps(+respond), expenses(+accept,dispute,reimburse),
 *   family-changes(+release,undo), guardian/devices/:id/revoke, parental-controls, play-window, daily-time, child-content/:key, account/delete, account/recover, guardian/pin.
 * Scratch form fields live in S.grd.f (bound with data-bind="grd.f.<name>"). Nothing about the child's private journal, worry box
 * or feelings is ever read or stored here (P7). No scores, streaks or counts are sent to the child device (P2). No money moves (P4/P6).
 */
(function(){"use strict";
LIVE.module('guardian',function(L){
var K=window.OB,I=K.ico,E=K.esc,VER=3;
var TZ={mom:'America/Chicago',dad:'America/New_York'};
var NAMES={mom:'Jess',dad:'Marcus'};
var DAY=86400000,MIN=60000;

/* ------------------------------------------------------------------ time helpers */
function T(){return L.now().getTime();}
function parts(t,tz){var o={};new Intl.DateTimeFormat('en-US',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(t).forEach(function(p){o[p.type]=p.value;});return {y:+o.year,m:+o.month,d:+o.day,h:+o.hour%24,mi:+o.minute,s:+o.second};}
function tzOff(t,tz){var p=parts(t,tz);return Date.UTC(p.y,p.m-1,p.d,p.h,p.mi,p.s)-Math.floor(t/1000)*1000;}
function zoned(y,m,d,h,mi,tz){var u=Date.UTC(y,m-1,d,h,mi);var t=u-tzOff(u,tz);return u-tzOff(t,tz);}
function fT(t,tz){return new Intl.DateTimeFormat('en-US',{timeZone:tz,hour:'numeric',minute:'2-digit'}).format(t);}
function fD(t,tz){return new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'short',month:'short',day:'numeric'}).format(t);}
function fDY(t,tz){return new Intl.DateTimeFormat('en-US',{timeZone:tz,month:'short',day:'numeric',year:'numeric'}).format(t);}
function ymd(t,tz){var p=parts(t,tz||TZ.mom);return p.y+'-'+('0'+p.m).slice(-2)+'-'+('0'+p.d).slice(-2);}
function ymdMs(s){var a=s.split('-');return Date.UTC(+a[0],+a[1]-1,+a[2]);}
function addDays(s,n){var d=new Date(ymdMs(s)+n*DAY);return d.getUTCFullYear()+'-'+('0'+(d.getUTCMonth()+1)).slice(-2)+'-'+('0'+d.getUTCDate()).slice(-2);}
function fYmd(s){return new Intl.DateTimeFormat('en-US',{timeZone:'UTC',weekday:'short',month:'short',day:'numeric'}).format(ymdMs(s));}
function hmToMin(s){var a=String(s||'0:0').split(':');return (+a[0]||0)*60+(+a[1]||0);}
function f12(hm){var m=hmToMin(hm),h=Math.floor(m/60)%24,mi=m%60;return (h%12||12)+(mi?':'+('0'+mi).slice(-2):':00')+' '+(h<12?'AM':'PM');}
function ago(t){var d=T()-t;if(d<MIN)return 'just now';if(d<60*MIN)return Math.round(d/MIN)+' min ago';if(d<DAY)return Math.round(d/(60*MIN))+' h ago';return Math.round(d/DAY)+' days ago';}
function fnv(str){var h=2166136261;for(var i=0;i<str.length;i++){h^=str.charCodeAt(i);h=Math.imul(h,16777619)>>>0;}return ('00000000'+h.toString(16)).slice(-8);}
function clone(o){return o===undefined?o:JSON.parse(JSON.stringify(o));}

/* ------------------------------------------------------------------ identity */
function sx(){return L.S;}
function gid(){var r=sx().dev&&sx().dev.g&&sx().dev.g.role;return r==='dad'?'dad':'mom';}
function pid(){return gid()==='mom'?'dad':'mom';}
function gName(id){var g=null;try{g=L.guardian(id);}catch(e){}return (g&&g.name)||NAMES[id];}
function myName(){return gName(gid());}
function pName(){return gName(pid());}
function myTz(){var g=null;try{g=L.guardian(gid());}catch(e){}return (g&&g.tz)||TZ[gid()];}
function pTz(){return TZ[pid()]&&pid()==='dad'?TZ.dad:TZ.mom;}
function herTz(){try{return L.homeTz();}catch(e){return TZ.mom;}}
function child(){var c=(sx().family&&sx().family.child)||{};return {name:c.name||'Ivy',age:c.age||6,bday:c.birthday||null};}
function cname(){return child().name;}
function kg(){var s=sx();if(!s.kid)s.kid={};if(!s.kid.ga)s.kid.ga={rev:0,updated:{}};return s.kid.ga;}
function labelFor(id){try{return L.labels.forChild(id);}catch(e){return id==='mom'?'Mom':'Dad';}}
function exch(){var e=(sx().family&&sx().family.schedule&&sx().family.schedule.exchange)||{dow:5,time:'17:00'};return e;}
var DOW=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
function exchText(){var e=exch();return DOW[e.dow]+' '+f12(e.time);}

function ensurePartner(){var s=sx();if(!s.family||!s.family.created||!s.family.guardians)return;
 if(s.family.guardians.length>=2||!s.family.guardians.length)return;var me=gid(),o=pid();
 s.family.guardians.push({id:o,name:NAMES[o],label:o==='dad'?'Dad':'Mom',tz:TZ[o],devices:[],joinedAt:T(),pinSet:true,simulated:true});}
function signedOutScreen(){return L.hasScreen('ob.signedout','g')?'ob.signedout':'g-session';}
/* ------------------------------------------------------------------ default state */
var EMERG_FIELDS=[['allergies','Allergies'],['conditions','Conditions'],['meds','Medicines she takes'],['doctor','Doctor'],['insurance','Insurance'],['contacts','Who to call'],['notes','Notes for a stranger']];
function mkAnchor(){var today=ymd(T(),TZ.mom),dow=new Date(ymdMs(today)).getUTCDay();return addDays(today,-((dow-exch().dow+7)%7));}
function altPattern(first){return first==='d'?'dddddddmmmmmmm':'mmmmmmmddddddd';}
function defFam(){var w=(sx().family&&sx().family.custody&&sx().family.custody.with)==='dad'?'d':'m';return {
 people:[
  {id:'mom',name:'Mom',role:'Guardian',home:'a',away:false,guardian:true,reach:{messages:true,calls:true,story:true}},
  {id:'dad',name:'Dad',role:'Guardian',home:'b',away:false,guardian:true,reach:{messages:true,calls:true,story:true}},
  {id:'dana',name:'Dana',role:'Dad’s partner',home:'b',away:false,reach:{messages:true,calls:false,story:false}},
  {id:'gran',name:'Grandma',role:'Relative',home:'',away:false,reach:{messages:false,calls:true,story:true}}],
 homes:[{id:'a',name:'Mom’s house',who:['mom']},{id:'b',name:'Dad’s house',who:['dad','dana']}],
 rhythm:{kind:'alt',pattern:altPattern(w),anchor:mkAnchor(),locked:false}};}
function freshLearn(){return {settings:{reflection:'session',framing:'neutral',rulesList:false,messageCheck:false},saved:[],rules:[],ageAll:false,topic:'all'};}
function freshGrd(){var t=T();return {v:VER,n:1,
 ui:{modal:null,fstep:1,suite:null,hosp:false},f:{},
 her:{colour:{phone:{name:'Sea blue',hex:'#2F8FC4',t:t-8*3600000},tablet:{name:'Sea blue',hex:'#2F8FC4',t:t-8*3600000}},ask:true,art:'watercolour',palette:'olive',mode:'light'},
 access:{readAloud:true,roomy:false,reduceMotion:false,larger:false,textSize:'standard'},accDirty:false,
 band:{hold:true,area:{reading:0,games:0,messages:0,calendar:0},ack:null},
 play:{on:true,open:'15:30',rest:'19:00',wind:30,bed:'19:30'},playDirty:false,
 fam:defFam(),fdraft:null,ftiming:'hold',fdate:'',fstory:false,
 hist:[],exceptions:[],
 extraDev:[{id:'dev-k-old',owner:'kid',name:'Ivy’s old phone',kind:'phone',since:t-90*DAY}],otherDevices:1,
 pin:{fails:[],changedAt:t-12*DAY},
 ctl:{tiles:{},changed:{}},
 acct:{state:'active'},
 learn:{mom:freshLearn(),dad:freshLearn()},
 srv:{emerg:{v:3,data:{allergies:'Penicillin',conditions:'Mild asthma',meds:'Albuterol inhaler when wheezy; Vitamin D each morning',doctor:'Dr. Okafor, Lakeview Pediatrics 555-0142',insurance:'Sample Health, member SAMPLE-0000',contacts:'Jess (Mom) 555-0101; Marcus (Dad) 555-0102',notes:'Blue inhaler is in the front pocket of her school bag.'},hist:[{v:1,by:'mom',t:t-9*DAY,fields:['all'],summary:'Card created'},{v:2,by:'dad',t:t-6*DAY,fields:['doctor'],summary:'Doctor updated'},{v:3,by:'mom',t:t-3*DAY,fields:['notes'],summary:'Notes updated'}]},
  meds:[{id:'m1',name:'Albuterol inhaler',dose:'2 puffs',kind:'prn',times:[],gap:4,note:'Only when wheezy. Check the label.',retired:false,doses:[]},{id:'m2',name:'Vitamin D gummy',dose:'1 gummy',kind:'scheduled',times:['08:00'],gap:0,note:'With breakfast.',retired:false,doses:[]}],
  notes:[],swaps:[],exp:[],dailyH:3},
 emed:null,econflict:null,
 binder:[{id:'b1',title:'School',body:'Pickup is at the side gate. Teacher: Ms. Rivera.'},{id:'b2',title:'Routines',body:'Reads two pages, then lights out.'}],
 appts:[],
 content:{},outbox:[],
 partner:{told:[],rulesList:true,rules:[{category:'bedtime',text:'Lights out at 7:30 on school nights.'},{category:'screens',text:'Screens off an hour before bed.'}],ctl:{}},
 notes:[],
 local:{drafts:3,cache:true,wiped:0}
};}
var sessionReflection=null; /* Learn 'session' mode: kept in memory only, never in S, gone on reload */
var checkText=''; /* Learn message check: never stored in S, never sent */

function G(){
 var s=sx(),g=s.grd;
 if(!g||g.v!==VER)g=s.grd=freshGrd();
 var k=kg();
 if(!k.seeded){k.seeded=true;seedKid(g,k);}
 return g;
}
function seedKid(g,k){
 k.access=clone(g.access);k.play=clone(g.play);k.art=g.her.art;k.colourAsk=g.her.ask;k.palette=g.her.palette;k.mode=g.her.mode;
 k.people=clone(g.fam.people);k.homes=clone(g.fam.homes);k.rhythm=clone(g.fam.rhythm);k.bandHold=null;k.hiddenTiles=[];k.pace={};
 k.routine=[{text:'Brush teeth',time:'7:15'},{text:'Get dressed',time:'7:25'},{text:'Breakfast',time:'7:40'}];
 k.firstThen=[];k.packing=[{text:'Pyjamas',packed:false},{text:'Blue bunny',packed:false},{text:'Reading book',packed:false}];
 ['newPlace','helpers','symbols','capsule','firstTimes','marks','poorly','visit'].forEach(function(n){k[n]=[];});
 k.sensory={loud:false,bright:false,scratchy:false,crowds:false,surprises:false};k.feelings=true;
 k.village={sitter:{name:'',from:'',until:'',notes:'',tonight:false},grand:{greeting:'',likes:'',bedtime:''},school:{text:''}};
 k.compass={q1:'What made you smile today?',q2:'Is there anything you would like to ask?'};
 k.shelf={rhythm:true,voice:false,growing:true,care:false,village:false,compass:false};k.profiles={dhh:false,away:false};
 ['routine','firstThen','packing','newPlace','sensory','helpers','symbols','feelings','capsule','firstTimes','marks','poorly','visit','village','compass','shelf','profiles'].forEach(function(n){g.content[n]=clone(k[n]);});
}
function uid(p){var g=sx().grd;g.n=(g.n||1)+1;return p+g.n;}

/* ------------------------------------------------------------------ actions, updates, notifications */
function def(name,fn){L.act(name,function(c,arg,el,ev){G();return fn(c,arg,el,ev);});}
function U(fn){return L.update(function(){var g=G();return fn(sx(),g);});}
function toast(c,t,o){try{L.toast((c&&c.dev)||'g',t,o);}catch(e){}}
function notifyPartner(text,kind){var g=G();g.partner.told.unshift({t:T(),text:text,kind:kind||'info'});if(g.partner.told.length>40)g.partner.told.length=40;L.emit('grd:notify',{to:pid(),text:text});}
function notifyMe(text,kind,by){var g=G();g.notes.unshift({t:T(),text:text,kind:kind||'info',by:by||pid(),read:false});if(g.notes.length>40)g.notes.length=40;}
function unread(){return G().notes.filter(function(n){return !n.read;}).length;}
function ok(body,st){return L.ok(body||{ok:true},st);}
function fail(status,code,msg,extra){return L.fail(status,code,msg,extra);}

/* call the simulated server; cb(ok:boolean, res)  (res = core's {ok,status,body,code,message}) */
function call(c,method,path,body,cb){
 var p;try{p=L.api((c&&c.dev)||'g',method,path,body);}catch(e){cb(false,{status:0,code:'offline',body:{}});return;}
 Promise.resolve(p).then(function(r){r=r||{};cb(!!r.ok,r);},function(){cb(false,{status:0,code:'offline',body:{}});});
}
function friendly(res){var e=res.code||'';if(res.status===0||e==='offline')return 'You are offline. Nothing was sent.';if(res.status===429)return 'Too many tries. Wait a moment.';if(res.status===401||e==='device_revoked'||e==='session_expired'||e==='unauthenticated')return 'Your session ended. Sign in again.';return res.message||('That did not go through ('+e+').');}
/* authored content: keep the guardian copy, then publish through the server so Ivy's tablet gets it */
function publish(c,key,value,okText){
 var g=G();g.content[key]=clone(value);
 call(c,'PUT','/v1/child-content/'+key,{value:value},function(good,res){
  if(good){g.outbox=g.outbox.filter(function(o){return o.key!==key;});if(okText)toast(c,okText);L.queueRender();}
  else if(res.status===0||res.code==='offline'){g.outbox=g.outbox.filter(function(o){return o.key!==key;});g.outbox.push({key:key,value:clone(value)});L.queueRender();toast(c,'Saved on this phone. It goes to '+cname()+'’s tablet when you are back online.');}
  else toast(c,friendly(res));
 });
 if(!g.outbox.some(function(o){return o.key===key;})&&!L.online((c&&c.dev)||'g')){g.outbox.push({key:key,value:clone(value)});}
}
function pending(key){return G().outbox.some(function(o){return o.key===key;});}
function flushOutbox(){var g=G(),q=g.outbox.slice();if(!q.length)return;q.forEach(function(o){call({dev:'g'},'PUT','/v1/child-content/'+o.key,{value:o.value},function(good){if(good){var gg=G();gg.outbox=gg.outbox.filter(function(x){return x.key!==o.key;});L.queueRender();}});});}

/* ------------------------------------------------------------------ PIN */
function pinOf(){var s=sx();return (s.family&&s.family.pin)||'1234';}
function lockInfo(){var g=G(),t=T(),sv=sx().server||{};var recent=g.pin.fails.filter(function(x){return t-x<15*MIN;});var until=0;if(recent.length>=5)until=recent[recent.length-5]+15*MIN;if(sv.pinLockUntil>t&&sv.pinLockUntil>until)until=sv.pinLockUntil;if(until>t)return {locked:true,until:until,left:Math.max(1,Math.ceil((until-t)/MIN))};return {locked:false,tries:Math.max(0,5-recent.length)};}
var GATED={};
function gate(c,reason,then,arg,arg2){U(function(s,g){g.ui.modal={kind:'pin',screen:L.current('g').id,reason:reason,then:then,arg:arg,arg2:arg2,entered:'',wrong:false};});}

/* ------------------------------------------------------------------ UI primitives */
function inj(html,attrs){return L.withAttr(html,' '+attrs);}
function A(html,name,arg,arg2){return L.withAct(html,name,arg,arg2);}
function btn(text,name,arg,o,arg2){return A(K.btn(text,o||{}),name,arg,arg2);}
function rowA(o,name,arg,arg2){return A(K.row(o),name,arg,arg2);}
function tgl(on,label,name,arg,arg2){return A(K.toggle(on,{label:label}),name,arg,arg2);}
function trow(o,name,arg,arg2){return '<div class="row"><span class="ricon">'+I(o.ic||'sliders',20,1.9)+'</span><span class="rtxt"><b>'+E(o.title)+'</b>'+(o.sub?'<small>'+E(o.sub)+'</small>':'')+'</span>'+(o.dis?'<span class="chip sm">'+I('lock',12,2)+E(o.dis)+'</span>':tgl(o.on,o.title,name,arg,arg2))+'</div>';}
function seg(items,a,name,o){o=o||{};return '<div class="seg" role="radiogroup"'+(o.label?' aria-label="'+E(o.label)+'"':'')+'>'+items.map(function(x,i){return '<span role="radio" aria-checked="'+(i===a)+'" tabindex="0" class="'+(i===a?'on':'')+'" data-act="'+name+'" data-arg="'+E(o.vals?o.vals[i]:i)+'"'+(o.arg2!=null?' data-arg2="'+E(o.arg2)+'"':'')+'>'+E(x)+'</span>';}).join('')+'</div>';}
function chips(items,active,name,vals){return '<div class="gx-chips" role="group">'+items.map(function(x,i){var v=vals?vals[i]:i,on=v===active;return '<button type="button" class="gx-chip'+(on?' on':'')+'" aria-pressed="'+on+'" data-act="'+name+'" data-arg="'+E(v)+'">'+E(x)+'</button>';}).join('')+'</div>';}
function opt(title,sub,on,name,arg,o){o=o||{};return '<button type="button" class="gx-opt'+(on?' on':'')+'" role="radio" aria-checked="'+(!!on)+'"'+(o.dis?' disabled':'')+(name?L.a(name,arg,o.arg2):'')+'><span class="rd">'+(on?I('check',12,3.2):'')+'</span><span><b>'+E(title)+'</b>'+(sub?'<small>'+E(sub)+'</small>':'')+'</span>'+(o.trail||'')+'</button>';}
function pathGet(path){var v=L.get(path);return v;}
function inp(path,label,o){o=o||{};var id='gx-'+path.replace(/\W/g,'_');var v=pathGet(path);
 return '<div class="ff"><label for="'+id+'">'+E(label)+'</label><div class="fc">'+(o.ic?I(o.ic,18,1.9):'')+'<input id="'+id+'" type="'+(o.type||'text')+'" data-bind="'+path+'"'+(o.enter?' data-enter="'+o.enter+'"':'')+' value="'+E(v==null?'':v)+'" placeholder="'+E(o.ph||'')+'"'+(o.min?' min="'+o.min+'"':'')+(o.max?' max="'+o.max+'"':'')+(o.inputmode?' inputmode="'+o.inputmode+'"':'')+' autocomplete="off"></div>'+(o.hint?'<small class="fh">'+E(o.hint)+'</small>':'')+'</div>';}
function area(path,label,o){o=o||{};var id='gx-'+path.replace(/\W/g,'_');var v=pathGet(path);return '<div class="ff"><label for="'+id+'">'+E(label)+'</label><div class="fc gx-ta"><textarea id="'+id+'" data-bind="'+path+'" rows="'+(o.rows||3)+'" placeholder="'+E(o.ph||'')+'">'+E(v==null?'':v)+'</textarea></div>'+(o.hint?'<small class="fh">'+E(o.hint)+'</small>':'')+'</div>';}
function fval(name){var v=G().f[name];return v==null?'':String(v).trim();}
function fclear(){for(var i=0;i<arguments.length;i++)delete G().f[arguments[i]];}
function card(html,cls){return K.card(html,cls||'');}
function sec(t,right){return K.sectionLabel(t,right);}
function note(t){return '<p class="gx-fine">'+t+'</p>';}
function rv(t){return '<span class="gx-nr" title="Wording flagged for clinical review before release">'+I('eye',11,2.2)+E(t||'needs review')+'</span>';}
function lead(t,s){return '<b class="gx-lead">'+E(t)+'</b>'+(s?'<p class="gx-sub">'+E(s)+'</p>':'');}
function priv(t){return '<span class="gx-priv">'+I('lock',12,2.2)+E(t||'Only you')+'</span>';}
function av(id,s){var m={mom:['M',''],dad:['D','accent'],dana:['Da','accent'],gran:['G',''],kid:['I','']}[id]||[String(id).charAt(0).toUpperCase(),''];return K.avatar(m[0],{size:s||40,tone:m[1]});}
function sentTag(key){return pending(key)?'<span class="gx-sent wait">'+I('clock',12,2.2)+'Waiting to send</span>':'<span class="gx-sent">'+I('check',12,2.6)+'On '+E(cname())+'’s tablet</span>';}
function who(id){return id==='mom'||id==='dad'?(id===gid()?'You':gName(id)):(id==='sys'?'Olive Branch':id);}

/* screen wrapper: top bar + scroll page + overlay layer (core adds status bar, sheet host, toast) */
function scr(id,title,fn,o){o=o||{};
 L.screen(id,{dev:'g',title:typeof title==='function'?'':title,render:function(c){var g=G();var inner=fn(c,g);
  var tt=typeof title==='function'?title(c):title;var top=K.top({back:!o.root,title:tt,eyebrow:o.eyebrow===undefined?cname():o.eyebrow,right:o.right||''});
  return top+K.page(inner,{cls:'gx'})+overlay(c,g);}});}
function overlay(c,g){var m=g.ui.modal;if(!m||!MODALS[m.kind]||m.screen!==c.screenId)return '';return MODALS[m.kind](c,g,m);}
var MODALS={};
function sheet(title,inner,actions){return K.bottomSheet({title:title,inner:inner,actions:actions,close:true}).replace('<button type="button" class="cbtn sm" aria-label="Close">','<button type="button" class="cbtn sm" aria-label="Close" data-act="gClose">').replace('<div class="scrim">','<div class="scrim" data-act="gClose">');}
function closeM(){U(function(s,g){g.ui.modal=null;});}
function openM(kind,data){U(function(s,g){var m=data||{};m.kind=kind;m.screen=L.current('g').id;g.ui.modal=m;});}

/* injected styles (gx- prefix; tokens from the kit) */
(function(){if(document.getElementById('gx-style'))return;var st=document.createElement('style');st.id='gx-style';st.textContent=
'.ob .gx .gx-lead{display:block;font:800 18px/1.25 var(--font-display,inherit);color:var(--ink);margin:0}.ob .gx .gx-sub{margin:4px 0 0;font:500 14px/1.45 var(--font-body,inherit);color:var(--ink2)}'+
'.ob .gx-fine{margin:6px 2px 0;font:500 12.5px/1.45 var(--font-body,inherit);color:var(--ink3)}'+
'.ob .gx-priv{display:inline-flex;gap:4px;align-items:center;font:700 11px/1 var(--font-body,inherit);padding:4px 8px;border-radius:99px;background:var(--surface3);color:var(--ink2)}'+
'.ob .gx-nr{display:inline-flex;gap:4px;align-items:center;font:700 10.5px/1 var(--font-body,inherit);padding:3px 7px;border-radius:99px;border:1px dashed var(--warn);color:var(--warn);background:var(--warnC);vertical-align:middle}'+
'.ob .gx-chips{display:flex;flex-wrap:wrap;gap:8px}.ob .gx-chip{min-height:48px;padding:0 14px;border-radius:99px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);font:700 13.5px/1 var(--font-body,inherit);cursor:pointer}.ob .gx-chip.on{background:var(--priC);color:var(--onPriC);border-color:var(--pri)}'+
'.ob .gx-sent{display:inline-flex;gap:4px;align-items:center;font:700 11.5px/1 var(--font-body,inherit);color:var(--ok);background:var(--okC);padding:4px 8px;border-radius:99px}.ob .gx-sent.wait{color:var(--warn);background:var(--warnC)}'+
'.ob .gx-ta textarea{width:100%;min-height:84px;border:0;background:transparent;color:var(--ink);font:500 15px/1.45 var(--font-body,inherit);resize:vertical;padding:10px 12px;outline:none}'+
'.ob .gx-sw{display:inline-block;width:54px;height:54px;border-radius:18px;flex:none;box-shadow:inset 0 0 0 1px rgba(0,0,0,.12)}'+
'.ob .gx-art{display:grid;grid-template-columns:1fr 1fr;gap:10px}.ob .gx-art button{border:2px solid var(--edge);border-radius:16px;background:var(--surface);padding:8px;text-align:left;cursor:pointer;color:var(--ink);min-height:48px;font:700 13.5px/1.2 var(--font-body,inherit)}.ob .gx-art button.on{border-color:var(--pri);background:var(--priC)}.ob .gx-art .sc{border-radius:10px;overflow:hidden;margin-bottom:6px;height:64px}.ob .gx-art .sc svg{width:100%;height:100%}'+
'.ob .gx-opt{display:flex;gap:12px;align-items:flex-start;width:100%;text-align:left;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);border-radius:16px;padding:12px 14px;min-height:56px;cursor:pointer;font:inherit}.ob .gx-opt.on{border-color:var(--pri);background:var(--priC)}.ob .gx-opt .rd{flex:none;width:22px;height:22px;border-radius:99px;border:2px solid var(--edge);display:grid;place-items:center;margin-top:1px}.ob .gx-opt.on .rd{background:var(--pri);border-color:var(--pri);color:var(--onPri)}.ob .gx-opt b{display:block;font:700 15px/1.3 var(--font-body,inherit)}.ob .gx-opt small{display:block;font:500 13px/1.4 var(--font-body,inherit);color:var(--ink2);margin-top:2px}.ob .gx-opt[disabled]{opacity:.7;cursor:not-allowed}'+
'.ob .gx-stack{display:grid;gap:8px}'+
'.ob .gx-ev{display:inline-flex;gap:6px;align-items:center;font:700 11.5px/1 var(--font-body,inherit);padding:5px 9px;border-radius:99px;background:var(--surface3);color:var(--ink)}.ob .gx-ev i{display:inline-block;width:7px;height:7px;border-radius:99px;background:var(--edge)}.ob .gx-ev i.f{background:var(--pri)}.ob .gx-ev.con i.f{background:var(--warn)}'+
'.ob .gx-src{display:block;font:500 12.5px/1.5 var(--font-body,inherit);color:var(--ink2)}.ob .gx-src a{color:var(--pri);text-decoration:underline;word-break:break-all}'+
'.ob .gx-wk{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}.ob .gx-wk i,.ob .gx-wk button{font-style:normal;display:grid;place-items:center;height:34px;border:0;border-radius:9px;font:800 12px/1 var(--font-body,inherit);background:var(--priC);color:var(--onPriC)}.ob .gx-wk .d{background:var(--accentC);color:var(--ink)}.ob .gx-wk.lk i{background-image:repeating-linear-gradient(45deg,transparent 0 5px,rgba(0,0,0,.14) 5px 7px)}.ob .gx-wk button{height:48px;cursor:pointer}'+
'.ob .gx-dl{display:grid;grid-template-columns:repeat(7,1fr);gap:4px;text-align:center;font:700 10px/1 var(--font-body,inherit);color:var(--ink3);margin-bottom:4px}'+
'.ob .gx-leg{display:flex;gap:14px;flex-wrap:wrap;font:600 12.5px/1 var(--font-body,inherit);color:var(--ink2)}.ob .gx-leg b{display:inline-block;width:12px;height:12px;border-radius:4px;background:var(--priC);margin-right:6px;vertical-align:-1px}.ob .gx-leg b.d{background:var(--accentC)}'+
'.ob .gx-hosp{background:#fff;color:#000;border-radius:18px;padding:16px;border:3px solid #000}.ob .gx-hosp h3{margin:0;font:900 20px/1.2 var(--font-body,inherit);color:#000;text-transform:uppercase;letter-spacing:.04em}.ob .gx-hosp p{margin:2px 0 14px;font:700 22px/1.3 var(--font-body,inherit);color:#000}'+
'.ob .gx-it{display:flex;gap:10px;align-items:flex-start;padding:10px 0;border-top:1px solid var(--line)}.ob .gx-it:first-child{border-top:0}.ob .gx-it .tx{min-width:0;flex:1}.ob .gx-it .tx b{display:block;font:700 14.5px/1.35 var(--font-body,inherit);color:var(--ink)}.ob .gx-it .tx small{display:block;font:500 12.5px/1.4 var(--font-body,inherit);color:var(--ink3)}'+
'.ob .gx-diff{display:grid;grid-template-columns:1fr 1fr;gap:10px}.ob .gx-diff>div{background:var(--surface2);border-radius:14px;padding:10px;min-width:0}.ob .gx-diff small{font:700 10.5px/1 var(--font-body,inherit);text-transform:uppercase;letter-spacing:.06em;color:var(--ink3)}.ob .gx-diff .pp{display:flex;align-items:center;gap:8px;margin-top:8px;font:600 13px/1.2 var(--font-body,inherit)}'+
'.ob .gx-win{position:relative;height:30px;border-radius:10px;background:var(--surface3);overflow:hidden}.ob .gx-win span{position:absolute;top:0;bottom:0}.ob .gx-win .on{background:var(--ok);opacity:.75}.ob .gx-win .tail{background:var(--warn);opacity:.55}.ob .gx-win .bd{width:3px;background:var(--ink)}'+
'.ob .gx-wt{position:relative;height:16px;font:600 11px/1 var(--font-body,inherit);color:var(--ink3);margin-top:3px}.ob .gx-wt span{position:absolute;transform:translateX(-50%)}'+
'.ob .gx-mirror{background:var(--priC);color:var(--onPriC);border-radius:16px;padding:14px}.ob .gx-mirror b{display:block;font:800 17px/1.3 var(--font-display,inherit)}.ob .gx-mirror p{margin:4px 0 0;font:500 14px/1.45 var(--font-body,inherit)}'+
'.ob input[type=range].gx-rng{width:100%;min-height:48px;accent-color:var(--pri)}'+
'.ob .gx-kp{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;max-width:280px;margin:10px auto 0}.ob .gx-kp button{min-height:56px;border-radius:16px;border:1.5px solid var(--edge);background:var(--surface);color:var(--ink);font:800 22px/1 var(--font-body,inherit);cursor:pointer}'+
'.ob .gx-hatch{background-image:repeating-linear-gradient(45deg,transparent 0 6px,rgba(0,0,0,.08) 6px 8px)}'+
'.ob .gx-chain{font:600 11.5px/1.3 ui-monospace,Menlo,Consolas,monospace;color:var(--ink3);word-break:break-all}'+
'.ob .gx-full{position:absolute;inset:0;z-index:30;background:var(--bg);overflow:auto;padding:16px;display:grid;align-content:start;gap:12px}'+
'.ob .gx h4{margin:0 0 4px;font:800 16px/1.25 var(--font-display,inherit);color:var(--ink)}.ob .gx h5{margin:0 0 6px;font:700 13px/1.2 var(--font-body,inherit);color:var(--ink2)}.ob .gx p{margin:0}'+
'.ob .gx-li{list-style:none;margin:6px 0 0;padding:0;display:grid;gap:6px}.ob .gx-li li{display:flex;gap:8px;align-items:flex-start;font:500 14px/1.4 var(--font-body,inherit);color:var(--ink)}.ob .gx-li li svg{flex:none;margin-top:2px;color:var(--ok)}.ob .gx-li.no li svg{color:var(--ink3)}'+
'.ob .gx-two{display:grid;grid-template-columns:minmax(0,1fr);gap:12px}.ob .gx-actions{display:flex;gap:8px;flex-wrap:wrap}.ob .gx-actions>*{flex:1 1 140px}'+
'.ob .gx-rmv{border:0;background:transparent;color:var(--ink2);min-width:48px;min-height:48px;border-radius:12px;cursor:pointer;display:grid;place-items:center}';
document.head.appendChild(st);})();

/* delegated Enter on inputs with data-enter="actName": sync the bound value, then press that action's button */
document.addEventListener('keydown',function(ev){var t=ev.target;if(ev.key!=='Enter'||!t||!t.getAttribute||t.tagName==='TEXTAREA'||ev.__gx)return;ev.__gx=1;var a=t.getAttribute('data-enter');if(!a)return;
 try{L.set(t.getAttribute('data-bind'),t.value);}catch(e){}
 var root=t.closest('.ob')||document;var ap=a.split('|');var b=root.querySelector('[data-act="'+ap[0]+'"]'+(ap[1]!=null?'[data-arg="'+ap[1]+'"]':''));if(b){ev.preventDefault();setTimeout(function(){b.click();},0);}},true);
/* Learn message check: text lives only in this closure; typing updates the hint box directly (nothing in S, nothing sent) */
document.addEventListener('input',function(ev){var t=ev.target;if(!t||t.id!=='gx-check-text'||ev.__gx)return;ev.__gx=1;checkText=t.value;var box=(t.closest('.ob')||document).querySelector('#gx-check-out');if(box)box.innerHTML=checkHintsHtml();},true);

/* ================================================================================ HER: colour, look, band, access, play */
var BANDS=[['t34','3 to 4','Three big pictures'],['t57','5 to 7','Words beside pictures'],['t812','8 to 12','Words and her own list'],['t1317','13 to 17','Mostly hers']];
function bandName(b){for(var i=0;i<BANDS.length;i++)if(BANDS[i][0]===b)return BANDS[i][1];return b;}
var BAND_LIST={
 t34:['Big pictures lead and every word can be heard','Her colour of the day','Simple games for two, played in turns','No settings and no lists of her own'],
 t57:['Pictures lead, with words beside them','Her colour of the day and favourite things','Games for two and a simple weekly view','No settings and no lists of her own yet'],
 t812:['Words lead, with her own list','Reading together and stories','Her calendar of weeks and exchanges','A private place only she can open'],
 t1317:['Mostly hers: she sets her own look','Her journal stays private from everyone','Calendar and plans she can edit','More say over messages, never over safety']};
var ART=[['watercolour','Watercolour','hills'],['paper','Paper cut','paper'],['soft','Soft shapes','sea'],['crayon','Crayon','letters']];
var SWATCH=[['Sea blue','#2F8FC4'],['Sunny yellow','#E3A92E'],['Leaf green','#4C9A5F'],['Sunset orange','#E2683C'],['Berry','#A23B72'],['Lilac','#8E7CC3']];
function nextBirthday(){
 var b=child().bday,today=ymd(T(),herTz()),y=+today.slice(0,4),m=12,d=9;
 if(typeof b==='string'){var x=b.match(/(\d{1,2})-(\d{1,2})$/);if(x){m=+x[1];d=+x[2];}}else if(b&&b.m){m=+b.m;d=+b.d;}
 function mk(yy){return yy+'-'+('0'+m).slice(-2)+'-'+('0'+d).slice(-2);}
 var s=mk(y);if(s<today)s=mk(y+1);
 return {ymd:s,days:Math.round((ymdMs(s)-ymdMs(today))/DAY),turns:child().age+1};}
function ageToBand(a){return L.bandOf?L.bandOf(a):(a<=4?'t34':a<=7?'t57':a<=12?'t812':'t1317');}
function effBand(){var k=kg();return (k.bandHold&&k.bandHold.on&&k.bandHold.from)?k.bandHold.from:L.band();}
function playState(t){
 var g=G(),k=kg(),p=k.play||g.play;t=t==null?T():t;
 var q=parts(t,herTz()),m=q.h*60+q.mi;
 if(!p||!p.on)return {state:'open',text:'',opensAt:null};
 var o=hmToMin(p.open),r=hmToMin(p.rest),w=+p.wind||0;
 if(m>=o&&m<r)return {state:'open',text:'Games are open.',opensAt:p.open,restsAt:p.rest};
 if(w&&m>=r&&m<r+w)return {state:'winding',text:'It\u2019s getting sleepy. One more, then goodnight.',opensAt:p.open,restsAt:p.rest};
 return {state:'closed',text:'Games are resting. They open again at '+f12(p.open)+'.',opensAt:p.open,restsAt:p.rest};}
L.grd={playState:function(t){return L.safe('grd.playState',function(){return playState(t);});},effectiveBand:function(){return effBand();},partnerName:function(){return pName();},houseOn:function(s){return houseOn(s);}};
/* derived play flag + scheduled family changes follow the virtual clock */
L.on('time:tick',function(){L.safe('grd tick',function(){
 if(!sx().grd||sx().grd.v!==VER)return;var k=kg();if(!k.seeded)return;
 var ps=playState().state;if(k.playNow!==ps){k.playNow=ps;L.emit('grd:play',{state:ps});L.queueRender();}
 applyDueChanges();});});
L.on('age:band',function(p){L.safe('grd age:band',function(){var g=G(),k=kg();
 var hold=g.band.holdAt?g.band.holdAt[p.to]!==false:g.band.hold;
 if(g.band.hold&&hold&&p.from&&p.to&&p.from!==p.to){k.bandHold={on:true,from:p.from,to:p.to};histAdd({kind:'band',by:'sys',text:cname()+' reached '+bandName(p.to)+'. Her home stays at '+bandName(p.from)+' until you release it.',status:'held',timing:{mode:'hold'}});notifyMe(cname()+' reached the '+bandName(p.to)+' band. Her home is held at '+bandName(p.from)+' until you have told her.','band','sys');}
 else{k.bandHold=null;histAdd({kind:'band',by:'sys',text:cname()+' moved to '+bandName(p.to)+'. Her home changed with her age.',status:'applied',timing:{mode:'now'}});}
 L.queueRender();});});

scr('g-colour','Colour and art',function(c,g){
 var k=kg(),ph=g.her.colour.phone,tb=g.her.colour.tablet;
 var latest=(ph.t||0)>=(tb.t||0)?ph:tb,same=ph.hex===tb.hex;
 var cur=k.colour||latest;
 var devRow=function(nm,d){var m=d.hex===cur.hex;return K.row({ic:'device',title:nm,sub:d.name+(d.t?' \u00b7 '+fT(d.t,herTz())+', her time':' \u00b7 not answered yet'),trail:m?K.chip('Matches',{tone:'ok',sm:true}):K.chip('Syncing',{tone:'warn',sm:true})});};
 return card('<div style="display:flex;gap:14px;align-items:center"><span class="gx-sw" style="background:'+E(cur.hex)+'"></span><div style="min-width:0"><span class="t-label">Today\u2019s colour</span><b class="gx-lead">'+E(cur.name)+'</b><p class="gx-sub">'+(cur.t?E(cname())+' chose it at '+fT(cur.t,herTz())+', her time.':E(cname())+' has not been asked yet today.')+'</p></div></div>')+
 note('Her colour is her answer to one question. There is no picker here for a grown-up.')+
 sec('Art style')+'<div class="gx-art" role="radiogroup" aria-label="Art style">'+ART.map(function(a){var on=g.her.art===a[0];return '<button type="button" role="radio" aria-checked="'+on+'" class="'+(on?'on':'')+'"'+L.a('gArt',a[0])+'><div class="sc">'+K.scene(a[2],150,64)+'</div>'+E(a[1])+'</button>';}).join('')+'</div>'+
 note('Drawings in activities use this style. It changes how pictures are drawn, never her colour. '+sentTag('art').replace('class="gx-sent','class="gx-sent'))+
 card('<h4>One question a day</h4><p class="gx-sub">'+E(cname())+' is asked once, in the morning. The latest answer wins everywhere, so all her devices agree.</p>'+devRow(cname()+'\u2019s phone',ph)+devRow(cname()+'\u2019s tablet',tb)+
  (g.her.sync?'<p class="gx-fine">'+E(g.her.sync)+'</p>':'<p class="gx-fine">If two devices are answered close together, the later answer is kept on both.</p>')+
  trow({ic:'sparkle',title:'Ask the daily question',sub:'Turn it off if she would rather not be asked',on:g.her.ask},'gAsk'))+
 card('<h4>Try the sync rule</h4><p class="gx-sub">This stands in for '+E(cname())+' answering on one of her devices.</p><div class="gx-actions">'+btn(cname()+' answers on her phone','gColourSim','phone',{kind:'tonal'})+btn(cname()+' answers on her tablet','gColourSim','tablet',{kind:'tonal'})+'</div>')+
 card('<h5>You can</h5><ul class="gx-li">'+['Choose the art style','Turn the daily question off'].map(function(x){return '<li>'+I('check',16,2.4)+'<span>'+x+'</span></li>';}).join('')+'</ul><div style="height:10px"></div><h5>You can\u2019t</h5><ul class="gx-li no">'+['Pick or change her colour for her','See why she chose it, or a history of her moods','Show it to anyone as a reading of how she feels'].map(function(x){return '<li>'+I('lock',16,2)+'<span>'+x+'</span></li>';}).join('')+'</ul>');
});
def('gArt',function(c,a){U(function(s,g){g.her.art=a;});publish(c,'art',a,'Art style saved for '+cname());});
def('gAsk',function(c){var g=G();var v=!g.her.ask;U(function(s,g2){g2.her.ask=v;});publish(c,'colourAsk',v,v?'Daily question on':'Daily question off');});
var colourIdx=0;
def('gColourSim',function(c,dev){var g=G();var col=SWATCH[(colourIdx++)%SWATCH.length];var t=T();
 g.her.colour[dev]={name:col[0],hex:col[1],t:t};
 call(c,'PUT','/v1/colour-of-day',{device:dev,name:col[0],hex:col[1],t:t},function(good,res){
  if(!good){toast(c,friendly(res));return;}
  var b=res.body,gg=G();gg.her.colour.phone={name:b.name,hex:b.hex,t:b.t};gg.her.colour.tablet={name:b.name,hex:b.hex,t:b.t};
  gg.her.sync=b.superseded?('Two answers came close together. The later one, '+b.name+' at '+fT(b.t,herTz())+', is kept on both devices.'):('Both devices now show '+b.name+'.');L.queueRender();});
 U(function(){});});
L.route('PUT','/v1/colour-of-day',function(req){var g=G(),k=kg(),b=req.body||{},cur=k.colour;
 var superseded=false,keep={name:b.name,hex:b.hex,t:b.t};
 if(cur&&cur.t&&cur.t>b.t){keep=cur;superseded=true;}else if(cur&&cur.t&&Math.abs(cur.t-b.t)<10*MIN&&cur.hex!==b.hex)superseded=true;
 k.colour=keep;k.updated=k.updated||{};
 return ok({name:keep.name,hex:keep.hex,t:keep.t,superseded:superseded});},{principals:['guardian','child']});

/* ---- how her app looks */
function priOf(pal,mode){var s=K.theme(pal,mode)||'';var m=/--pri:\s*([^;]+);/.exec(s);return m?m[1]:'#4A6B4F';}
scr('g-look','How her app looks',function(c,g){
 var pals=Object.keys(K.SEEDS);
 return banner0('Only a grown-up sets this. '+cname()+'\u2019s app has no settings.')+
 sec('Palette')+'<div class="gx-stack" role="radiogroup" aria-label="Palette">'+pals.map(function(p){return opt(K.SEEDS[p].n,K.SEEDS[p].note,g.her.palette===p,'gPalette',p,{trail:'<span class="gx-sw" style="width:34px;height:34px;border-radius:12px;background:'+priOf(p,g.her.mode)+'"></span>'});}).join('')+'</div>'+
 sec('Mode')+seg(['Light','Dark'],g.her.mode==='dark'?1:0,'gMode',{vals:['light','dark'],label:'Mode'})+
 note('This changes her app only. The picture-first layout, the sizes and the words stay the same. '+sentTag('palette'))+
 card('<h4>Right now on her tablet</h4><p class="gx-sub">Palette: '+E(K.SEEDS[(kg().palette)||'olive'].n)+', '+E(kg().mode||'light')+'.</p>');});
function banner0(t,ic){return K.banner('pri',t,ic||'lock');}
def('gPalette',function(c,p){U(function(s,g){g.her.palette=p;});publish(c,'palette',p,'Palette saved for '+cname());});
def('gMode',function(c,m){U(function(s,g){g.her.mode=m;});publish(c,'mode',m,'Mode saved for '+cname());});

/* ---- age band */
scr('g-band','Age bands',function(c,g){
 var k=kg(),cur=L.band(),eff=effBand(),nb=nextBirthday(),toBand=ageToBand(nb.turns);
 var held=k.bandHold&&k.bandHold.on;
 var h=K.banner('pri','Bands are proposals. Any guardian can hold or change any of them.','info');
 if(held)h+=K.notice({tone:'warn',title:cname()+' reached '+bandName(k.bandHold.to),text:'Her home still shows '+bandName(k.bandHold.from)+'. Nothing changes on her side until you have told her.',ic:'hourglass'})+btn('I have told her. Release it.','gBandRelease',null,{full:true,size:'lg',ic:'check'});
 h+='<div class="gx-stack">'+BANDS.map(function(b){var isCur=b[0]===cur;return card('<div style="display:flex;justify-content:space-between;gap:8px;align-items:center"><div><b class="gx-lead">'+b[1]+'</b><p class="gx-sub">'+b[2]+'</p></div>'+(b[0]===eff?K.chip(held&&b[0]===eff?'Her home shows this':cname()+' is here',{tone:'pri',sm:true}):(isCur?K.chip('Her age says this',{sm:true}):''))+'</div><ul class="gx-li">'+BAND_LIST[b[0]].map(function(x){return '<li>'+I('check',16,2.4)+'<span>'+x+'</span></li>';}).join('')+'</ul>');}).join('')+'</div>';
 h+=card('<span class="t-label">Next birthday</span><b class="gx-lead">'+E(cname())+' turns '+nb.turns+' on '+fYmd(nb.ymd)+'. That is '+nb.days+' day'+(nb.days===1?'':'s')+' away.</b><p class="gx-sub">'+(toBand===cur?'Her band stays '+bandName(cur)+', so her home does not change.':'At '+nb.turns+' she moves to '+bandName(toBand)+'. '+(g.band.hold?'With the hold on, her home stays the same until you release it.':'With the hold off, her home changes that day.'))+'</p>'+
  (nb.days<=7&&nb.days>0?'<p class="gx-fine">One quiet line appears on her tablet: \u201c'+nb.days+' sleeps until your birthday\u201d.</p>':'<p class="gx-fine">In her last week a quiet line appears: \u201c3 sleeps until your birthday\u201d. No count, no prize.</p>'));
 h+=card('<h4>By area</h4><p class="gx-fine">Each area follows her band unless you set it. A child can be ahead in one thing and not in another.</p>'+[['reading','book','Reading and words'],['games','dice','Games'],['messages','chat','Messages'],['calendar','calendar','Calendar and weeks']].map(function(a){var off=g.band.area[a[0]]||0;return '<div style="padding:8px 0;border-top:1px solid var(--line)"><b class="t-body">'+a[2]+'</b>'+seg(['One band down','Follows her band','One band up'],off+1,'gArea',{vals:[-1,0,1],arg2:a[0],label:a[2]})+'</div>';}).join(''));
 h+=card(trow({ic:'hourglass',title:'Hold until I have told her',sub:'When she moves to a new band, nothing changes on her side until you release it.',on:g.band.hold},'gBandHold'));
 h+=rowA({ic:'calendar',title:'What changes at each age',sub:'The planner, band by band',go:true},'go','g-planner');
 return h;});
def('gBandHold',function(c){var g=G();var v=!g.band.hold;U(function(s,g2){g2.band.hold=v;if(!v){var k=kg();if(k.bandHold){k.bandHold=null;}}});toast(c,v?'Holding at her current band':'Her home will follow her age');});
def('gArea',function(c,v,el){var a=c.arg2;var g=G();U(function(s,g2){g2.band.area[a]=+v;});var o={};for(var n in g.band.area)o[n]=g.band.area[n];o[a]=+v;publish(c,'areaOffset',o,'Saved');});
def('gBandRelease',function(c){var g=G(),k=kg();var from=k.bandHold&&k.bandHold.from,to=k.bandHold&&k.bandHold.to;
 U(function(){k.bandHold=null;histAdd({kind:'band',by:gid(),text:myName()+' released the move to '+bandName(to)+' after telling '+cname(),status:'applied',timing:{mode:'now'},told:T()});});
 L.emit('family:changed',{what:'bandRelease',by:gid(),source:'guardian',from:from,to:to});notifyPartner(myName()+' released '+cname()+'\u2019s move to '+bandName(to)+'.','band');toast(c,'Released. Her home now shows '+bandName(to)+'.');});

scr('g-planner','What changes at each age',function(c,g){
 g.band.holdAt=g.band.holdAt||{};g.band.remind=g.band.remind||{};
 return K.banner('pri','A plan, not a schedule. Nothing here moves until she reaches the age and you say so.','info')+
 BANDS.slice(1).map(function(b){var ageFrom={t57:5,t812:8,t1317:13}[b[0]];var hold=g.band.holdAt[b[0]]!==false;
  return card('<div style="display:flex;justify-content:space-between;gap:8px"><div><b class="gx-lead">'+b[1]+'</b><p class="gx-sub">From age '+ageFrom+'</p></div>'+(L.band()===b[0]?K.chip(cname()+' is here',{tone:'pri',sm:true}):'')+'</div><ul class="gx-li">'+BAND_LIST[b[0]].map(function(x){return '<li>'+I('check',16,2.4)+'<span>'+x+'</span></li>';}).join('')+'</ul>'+
   trow({ic:'hourglass',title:'Hold when she arrives',sub:'Her home stays until you release it',on:hold},'gHoldAt',b[0])+
   trow({ic:'bell',title:'Remind me a week before',sub:'A note to you. Nothing goes to '+cname()+'.',on:!!g.band.remind[b[0]]},'gRemind',b[0]));}).join('')+
 note('Her age is chosen once by her and then locked. Bands follow the age.');});
def('gHoldAt',function(c,b){U(function(s,g){g.band.holdAt=g.band.holdAt||{};g.band.holdAt[b]=g.band.holdAt[b]===false;});});
def('gRemind',function(c,b){U(function(s,g){g.band.remind=g.band.remind||{};g.band.remind[b]=!g.band.remind[b];});});

/* ---- accessibility for her device */
scr('g-access','Accessibility for her device',function(c,g){
 var a=g.access,k=kg().access||{},dirty=JSON.stringify(a)!==JSON.stringify(k);
 var fs={standard:17,large:20,largest:24}[a.textSize]||17;
 return card('<span class="t-label">Preview</span><p style="margin:6px 0 0;font:700 '+fs+'px/'+(a.roomy?1.9:1.5)+' var(--font-body,inherit);'+(a.roomy?'letter-spacing:.05em;word-spacing:.14em;':'')+'color:var(--ink)">Dad\u2019s story is ready at bedtime.</p>','tint')+
 card(trow({ic:'volume',title:'Read aloud everywhere',sub:'A speaker button on every screen. It never starts by itself.',on:a.readAloud},'gAcc','readAloud')+
  trow({ic:'book',title:'Roomier reading',sub:'Wider letters and lines, left aligned. The evidence for special dyslexia fonts is mixed, so this offers spacing instead.',on:a.roomy},'gAcc','roomy')+
  trow({ic:'pause',title:'Reduce motion',sub:'No movement except what her finger drives',on:a.reduceMotion},'gAcc','reduceMotion')+
  trow({ic:'hand',title:'Larger targets',sub:'Buttons grow from 64 to 80 px. Fewer fit on screen.',on:a.larger},'gAcc','larger')+
  trow({ic:'tv',title:'Captions',sub:'Captions are not built yet. This switch will appear when they are.',dis:'Not built yet'},''))+
 '<div style="margin:-4px 2px 0">'+rv('needs review')+'</div>'+
 sec('Text size')+seg(['Standard','Large','Largest'],{standard:0,large:1,largest:2}[a.textSize]||0,'gTextSize',{vals:['standard','large','largest'],label:'Text size'})+
 K.banner('info','Her device\u2019s own accessibility settings apply as well. These are added, not instead.','info')+
 btn(dirty?'Save for '+cname()+'\u2019s devices':'Saved','gAccSave',null,{full:true,size:'lg',disabled:!dirty})+
 note('Applies the next time her app opens. No restart or sign-in needed. '+sentTag('access'));});
def('gAcc',function(c,k){U(function(s,g){g.access[k]=!g.access[k];});});
def('gTextSize',function(c,v){U(function(s,g){g.access.textSize=v;});});
def('gAccSave',function(c){var g=G();publish(c,'access',clone(g.access),'Saved for '+cname()+'\u2019s devices');U(function(){});});

/* ---- play window and wind-down */
function winLen(p){return hmToMin(p.rest)-hmToMin(p.open);}
scr('g-play','Play window and daily time',function(c,g){
 var p=g.play,live=kg().play||p,dirty=JSON.stringify(p)!==JSON.stringify(live);
 var o=hmToMin(p.open),r=hmToMin(p.rest),w=+p.wind||0,b=hmToMin((sx().family&&sx().family.schedule&&sx().family.schedule.bedtime)||p.bed);
 var pc=function(m){return Math.max(0,Math.min(100,(m-360)/9));};
 var ps=playState();
 var invalid=o>=r;
 return card('<span class="t-label">Her day, her time ('+E(L.tzName?L.tzName(herTz()):herTz())+')</span><div class="gx-win" role="img" aria-label="Games open from '+f12(p.open)+' to '+f12(p.rest)+'"><span class="on" style="left:'+pc(o)+'%;width:'+Math.max(0,pc(r)-pc(o))+'%"></span><span class="tail" style="left:'+pc(r)+'%;width:'+Math.max(0,pc(r+w)-pc(r))+'%"></span><span class="bd" style="left:'+pc(b)+'%"></span></div><div class="gx-wt"><span style="left:0">6a</span><span style="left:33%">12p</span><span style="left:67%">6p</span><span style="left:100%">9p</span></div><p class="gx-sub" style="margin-top:6px">Games open from '+f12(p.open)+' and rest at '+f12(p.rest)+'. Bedtime is '+f12(minToHmx(b))+'.</p>')+
 card(trow({ic:'moon',title:'Use a play window',sub:p.on?'Games follow the window below':'Games are open all day',on:p.on},'gPlayOn'))+
 (p.on?inp('grd.play.open','Opens',{type:'time',ic:'sun'})+inp('grd.play.rest','Rests at',{type:'time',ic:'moon'})+
 '<div class="gx-stack"><h5 style="margin:6px 2px 0">Wind-down</h5>'+seg(['Off','15 min','30 min'],{0:0,15:1,30:2}[w]||0,'gWind',{vals:[0,15,30],label:'Wind-down'})+note('After the rest time a game in progress can finish. The door to new games closes gently.')+'</div>':'')+
 (invalid?K.notice({tone:'warn',title:'Opens must be before rests',text:'Pick an opening time earlier than the resting time.',ic:'warn'}):'')+
 card('<span class="t-label">What '+E(cname())+' sees at '+f12(p.rest)+'</span><div style="display:flex;gap:12px;align-items:center"><div style="width:84px;height:62px;border-radius:14px;overflow:hidden;flex:none">'+K.scene('night',84,62)+'</div><p style="font:800 16px/1.25 var(--font-display,inherit);color:var(--ink)">It\u2019s getting sleepy. One more, then goodnight.</p></div><p class="gx-sub">Nothing is taken away. Games open again at '+f12(p.open)+'. Calls and family messages are never closed by the window.</p>','tint')+
 K.notice({tone:ps.state==='open'?'ok':'info',title:'On her tablet right now: '+(ps.state==='open'?'games are open':ps.state==='winding'?'winding down':'games are resting'),text:'It is '+fT(T(),herTz())+' for '+cname()+'. Use the time controls to watch the door close.',ic:'clock'})+
 K.banner('info','If you make the window longer, '+pName()+' is told. Shorter is never reported.','info')+
 btn(dirty?'Save play window':'Saved','gPlaySave',null,{full:true,size:'lg',disabled:!dirty||invalid})+
 note(sentTag('play'))+
 card('<h4>Daily time</h4><p class="gx-sub">Reading and watching share one daily total across both homes.</p>'+seg(['Off','1 h','2 h','3 h'],g.srv.dailyH,'gDaily',{vals:[0,1,2,3],label:'Daily time'})+(g.srv.dailyBy?'<p class="gx-fine">'+E(g.srv.dailyBy)+'</p>':'<p class="gx-fine">Lowering is free. A raise is shown to '+E(pName())+' right away.</p>'));});
function minToHmx(m){return ('0'+Math.floor(m/60)%24).slice(-2)+':'+('0'+m%60).slice(-2);}
def('gPlayOn',function(c){U(function(s,g){g.play.on=!g.play.on;});});
def('gWind',function(c,v){U(function(s,g){g.play.wind=+v;});});
def('gPlaySave',function(c){var g=G(),p=clone(g.play),live=kg().play||p;
 if(hmToMin(p.open)>=hmToMin(p.rest)){toast(c,'Opens must be before rests.');return;}
 call(c,'PUT','/v1/play-window',{play:p},function(good,res){if(!good){if(res.status===0)publish(c,'play',p);else toast(c,friendly(res));return;}toast(c,'Saved. '+cname()+'\u2019s games follow it now.');L.queueRender();});});
L.route('PUT','/v1/play-window',function(req){var p=req.body.play;if(!p||!/^\d\d:\d\d$/.test(p.open)||!/^\d\d:\d\d$/.test(p.rest))return fail(422,'validation_failed','Times look wrong');
 var k=kg(),g=G(),old=k.play||{on:false,open:'00:00',rest:'23:59'};
 var longer=!old.on?false:(hmToMin(p.rest)-hmToMin(p.open))>(hmToMin(old.rest)-hmToMin(old.open));
 k.play=clone(p);k.updated=k.updated||{};k.updated.play=T();k.rev=(k.rev||0)+1;k.playNow=playState().state;
 if(longer||(!old.on&&p.on===false))notifyPartner(myName()+' made '+cname()+'\u2019s play window longer: '+f12(p.open)+' to '+f12(p.rest)+'.','play');
 L.emit('grd:published',{key:'play'});return ok({longer:longer});},{principals:['guardian']});
def('gDaily',function(c,h){var g=G(),old=g.srv.dailyH,nh=+h;
 call(c,'PUT','/v1/daily-time',{hours:nh,by:gid()},function(good,res){if(!good){toast(c,friendly(res));return;}toast(c,nh>old?'Raised. '+pName()+' has been told.':'Saved.');L.queueRender();});});
L.route('PUT','/v1/daily-time',function(req){var g=G(),by=req.body.by||gid(),old=g.srv.dailyH,nh=+req.body.hours;
 g.srv.dailyH=nh;g.srv.dailyBy=(by===gid()?'You':gName(by))+(nh>old?' raised':' changed')+' this from '+(old?old+' h':'off')+' to '+(nh?nh+' h':'off')+' at '+fT(T(),myTz())+'.';
 var k=kg();k.dailyH=nh;k.updated=k.updated||{};k.updated.dailyH=T();
 if(nh>old){if(by===gid())notifyPartner(myName()+' raised daily time from '+old+' h to '+nh+' h.','daily');else notifyMe(gName(by)+' raised daily time from '+old+' h to '+nh+' h. You have been told, it is not a request.','daily',by);}
 L.emit('grd:published',{key:'dailyH'});return ok({hours:nh});},{principals:['guardian']});

L.route('PUT','/v1/child-content/:key',function(req){var k=kg(),key=req.params.key;if(!/^[a-zA-Z]+$/.test(key))return fail(400,'bad_key','Unknown key');
 k[key]=clone(req.body.value);k.rev=(k.rev||0)+1;k.updated=k.updated||{};k.updated[key]=T();
 if(key==='play')k.playNow=playState().state;
 L.emit('grd:published',{key:key});return ok({key:key,rev:k.rev});},{principals:['guardian']});
L.on('net:change',function(){L.safe('grd outbox',function(){if(sx().grd)flushOutbox();});});

/* ================================================================================ FAMILY: schedule maths, builder, history */
function houseOn(s){var g=G(),r=g.fam.rhythm,ex=g.exceptions.filter(function(x){return x.date===s;})[0];if(ex)return ex.house;
 var d=Math.round((ymdMs(s)-ymdMs(r.anchor))/DAY),i=((d%14)+14)%14;return r.pattern.charAt(i)==='d'?'b':'a';}
function patternFor(kind,first){if(kind==='alt')return first==='d'?'dddddddmmmmmmm':'mmmmmmmddddddd';if(kind==='2255')return first==='d'?'ddmmdddddmmmmm':'mmddmmmmmddddd';return null;}
var DN=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
function dayHeads(r){var d0=new Date(ymdMs(r.anchor)).getUTCDay();var h='<div class="gx-dl" aria-hidden="true">';for(var i=0;i<7;i++)h+='<span>'+DN[(d0+i)%7].toUpperCase()+'</span>';return h+'</div>';}
function weekRow(pat,cls,act){var h='<div class="gx-wk'+(cls?' '+cls:'')+'" role="img" aria-label="Rhythm: '+pat.split('').map(function(x){return x==='m'?'Mom’s house':'Dad’s house';}).join(', ')+'">';
 for(var i=0;i<7;i++){var ch=pat.charAt(i);h+=act?'<button type="button" class="'+(ch==='d'?'d':'')+'" aria-label="Day '+(i+1)+': '+(ch==='d'?'Dad':'Mom')+'’s house"'+L.a(act,i)+'>'+(ch==='d'?'D':'M')+'</button>':'<i class="'+(ch==='d'?'d':'')+'">'+(ch==='d'?'D':'M')+'</i>';}
 return h+'</div>';}
function rhythmBlock(r,own){var p=r.pattern;return dayHeads(r)+weekRow(p.slice(0,7),r.locked?'lk':'',own?'gOwn':null)+'<div style="height:4px"></div>'+weekRow(p.slice(7),r.locked?'lk':'',own?'gOwn2':null)+'<div style="height:10px"></div><div class="gx-leg"><span><b></b>Mom’s house</span><span><b class="d"></b>Dad’s house</span></div>';}
function rhythmWords(r){return r.kind==='alt'?'Alternating weeks':r.kind==='2255'?'2-2-5-5':'Built by hand';}

/* ---- diff + history */
function pDesc(p,fam){var h=fam.homes.filter(function(x){return x.id===p.home;})[0];var r=[];if(p.reach.messages)r.push('messages');if(p.reach.calls)r.push('calls');if(p.reach.story)r.push('a weekly story');return p.role+(h?' · '+h.name:' · near and far')+(r.length?' · '+r.join(', '):' · no contact yet')+(p.away?' · away for a while':'');}
function diffFam(a,b){var out=[];
 var am={},bm={};a.people.forEach(function(p){am[p.id]=p;});b.people.forEach(function(p){bm[p.id]=p;});
 b.people.forEach(function(p){var o=am[p.id];if(!o){out.push({cat:'people',text:'Add '+p.name+' ('+p.role+')'});return;}
  if(o.name!==p.name)out.push({cat:'people',text:'Rename '+o.name+' to '+p.name});
  if(o.role!==p.role)out.push({cat:'people',text:p.name+': role is now “'+p.role+'”'});
  if(o.home!==p.home)out.push({cat:'people',text:p.name+' moves to '+((b.homes.filter(function(h){return h.id===p.home;})[0]||{name:'near and far'}).name)});
  ['messages','calls','story'].forEach(function(k){if(o.reach[k]!==p.reach[k])out.push({cat:'people',text:p.name+(p.reach[k]?' can now reach her with ':' no longer has ')+({messages:'messages',calls:'calls',story:'a weekly story'}[k])});});
  if(o.away!==p.away)out.push({cat:'people',text:p.name+(p.away?' is away for a while':' is back')});});
 a.people.forEach(function(p){if(!bm[p.id])out.push({cat:'people',text:'Remove '+p.name});});
 var ah={},bh={};a.homes.forEach(function(h){ah[h.id]=h;});b.homes.forEach(function(h){bh[h.id]=h;});
 b.homes.forEach(function(h){if(!ah[h.id])out.push({cat:'homes',text:'Add a home: '+h.name});else if(ah[h.id].name!==h.name)out.push({cat:'homes',text:'Rename '+ah[h.id].name+' to '+h.name});});
 a.homes.forEach(function(h){if(!bh[h.id])out.push({cat:'homes',text:'Remove '+h.name});});
 if(a.rhythm.kind!==b.rhythm.kind||a.rhythm.pattern!==b.rhythm.pattern)out.push({cat:'rhythm',text:'Change the rhythm from '+rhythmWords(a.rhythm)+' to '+rhythmWords(b.rhythm)});
 return out;}
function histAdd(e){var g=G();e.id=uid('h');e.seq=g.hist.length+1;e.t=T();g.hist.push(e);return e;}
function hstat(e){var g=G();var rel=g.hist.filter(function(x){return x.releases===e.id;})[0],und=g.hist.filter(function(x){return x.undoes===e.id;})[0];
 if(e.kind==='release'||e.kind==='undo'||e.kind==='court'||e.kind==='band'){return und&&e.applied?'undone':(e.status||'applied');}
 if(rel)return 'released';if(und)return e.applied?'undone':'cancelled';return e.status;}
function latestEffect(){var g=G();for(var i=g.hist.length-1;i>=0;i--){var e=g.hist[i];if(e.applied&&hstat(e)!=='undone')return e;}return null;}
function applyEntry(e,source){var g=G(),k=kg();g.fam=clone(e.after);g.famV=(g.famV||0)+1;
 k.people=clone(g.fam.people);k.homes=clone(g.fam.homes);k.rhythm=clone(g.fam.rhythm);k.rev=(k.rev||0)+1;k.updated=k.updated||{};k.updated.people=T();k.updated.rhythm=T();
 if(e.note)k.changeNote={text:e.note,t:T()};
 L.emit('grd:published',{key:'people'});L.emit('family:changed',{what:'structure',by:e.by,source:'guardian',entry:e.id,via:source||'release'});}
function applyDueChanges(){var g=sx().grd;if(!g||g.v!==VER)return;var today=ymd(T(),herTz());
 g.hist.slice().forEach(function(e){if(e.kind==='family'&&e.timing&&e.timing.mode==='date'&&hstat(e)==='scheduled'&&e.timing.date<=today){
  if(JSON.stringify(g.fam)!==JSON.stringify(e.before)){histAdd({kind:'cancel',by:'sys',undoes:e.id,text:'The scheduled change could not be applied because the family changed since. It was cancelled.',status:'cancelled',changes:[]});return;}
  var r=histAdd({kind:'release',by:'sys',releases:e.id,text:'Applied on the day you chose: '+e.text,before:e.before,after:e.after,changes:e.changes,applied:true,status:'applied',note:e.note});applyEntry(r,'schedule');notifyMe('The change you scheduled reached '+cname()+' today.','family','sys');L.queueRender();}});}

/* ---- server: family changes */
function minDate(){return addDays(ymd(T(),herTz()),1);}
function maxDate(){return addDays(ymd(T(),herTz()),730);}
function srvFamChange(by,b){var g=G();
 if(b.baseV!==(g.famV||0))return fail(409,'stale_version','The family changed since you started',{current:g.famV||0});
 var ch=diffFam(g.fam,b.draft);if(!ch.length)return fail(422,'nothing_to_release','Nothing has changed');
 if(g.fam.rhythm.locked&&ch.some(function(x){return x.cat==='rhythm';}))return fail(409,'locked_by_order','The rhythm is set by a court order');
 if(g.fam.homes.length>4||b.draft.homes.length>4||b.draft.homes.length<1)return fail(422,'validation_failed','One to four homes');
 var mode=b.mode;if(['now','hold','date'].indexOf(mode)<0)return fail(422,'validation_failed','Pick a timing');
 if(mode==='date'&&(!b.date||b.date<minDate()||b.date>maxDate()))return fail(422,'date_out_of_range','Pick tomorrow or later, up to two years ahead',{min:minDate(),max:maxDate()});
 var text=(by===gid()?myName():gName(by))+': '+ch.map(function(x){return x.text;}).slice(0,3).join('; ')+(ch.length>3?' and '+(ch.length-3)+' more':'');
 var e=histAdd({kind:'family',by:by,text:text,changes:ch,before:clone(g.fam),after:clone(b.draft),timing:{mode:mode,date:mode==='date'?b.date:null},note:(b.note||'').slice(0,200),applied:mode==='now',status:mode==='now'?'applied':mode==='hold'?'held':'scheduled'});
 if(mode==='now')applyEntry(e,'now');
 if(by===gid())notifyPartner(myName()+' changed '+cname()+'’s family: '+ch.map(function(x){return x.text;}).slice(0,2).join('; ')+(mode==='hold'?' (held until '+myName()+' has told her)':mode==='date'?' (on '+fYmd(b.date)+')':'')+'.','family');
 else notifyMe(gName(by)+' changed '+cname()+'’s family: '+ch.map(function(x){return x.text;}).slice(0,2).join('; ')+'.','family',by);
 return ok({id:e.id,status:e.status});}
L.route('POST','/v1/family-changes',function(req){return srvFamChange(gid(),req.body);},{principals:['guardian']});
function srvRelease(by,id){var g=G(),e=g.hist.filter(function(x){return x.id===id;})[0];if(!e)return fail(404,'not_found','No such change');
 var st=hstat(e);if(st!=='held'&&st!=='scheduled')return fail(409,'not_pending','This change is not waiting');
 if(JSON.stringify(g.fam)!==JSON.stringify(e.before))return fail(409,'stale_version','The family changed since this was saved. Cancel it and start again.');
 var r=histAdd({kind:'release',by:by,releases:id,text:(by===gid()?myName():gName(by))+' told '+cname()+' and released: '+e.text.replace(/^[^:]*: /,''),before:e.before,after:e.after,changes:e.changes,applied:true,status:'applied',told:T(),note:e.note});
 applyEntry(r,'release');if(by===gid())notifyPartner(myName()+' released a held change to '+cname()+'’s family.','family');return ok({id:r.id});}
L.route('POST','/v1/family-changes/:id/release',function(req){return srvRelease(gid(),req.params.id);},{principals:['guardian']});
function srvUndo(by,id){var g=G(),e=g.hist.filter(function(x){return x.id===id;})[0];if(!e)return fail(404,'not_found','No such change');
 var st=hstat(e);
 if(e.kind==='family'&&(st==='held'||st==='scheduled')){histAdd({kind:'cancel',by:by,undoes:id,text:(by===gid()?myName():gName(by))+' cancelled: '+e.text.replace(/^[^:]*: /,''),status:'cancelled',changes:[]});return ok({cancelled:true});}
 if(!e.applied||st==='undone')return fail(409,'not_undoable','This can’t be undone');
 var le=latestEffect();if(!le||le.id!==e.id)return fail(409,'not_latest','Undo the newest change first');
 var u=histAdd({kind:'undo',by:by,undoes:id,text:(by===gid()?myName():gName(by))+' undid: '+e.text.replace(/^[^:]*: /,''),before:clone(g.fam),after:clone(e.before),changes:diffFam(g.fam,e.before),applied:true,status:'applied'});
 applyEntry(u,'undo');if(by===gid())notifyPartner(myName()+' undid a change to '+cname()+'’s family. The first entry stays in the history.','family');return ok({id:u.id});}
L.route('POST','/v1/family-changes/:id/undo',function(req){return srvUndo(gid(),req.params.id);},{principals:['guardian']});

/* ---- builder */
function draft(){var g=G();if(!g.fdraft){g.fdraft=clone(g.fam);g.fdraftV=g.famV||0;g.fnote='';g.ftiming='hold';g.fdate='';}return g.fdraft;}
function dirtyDraft(){var g=G();return g.fdraft&&JSON.stringify(g.fdraft)!==JSON.stringify(g.fam);}
function stepHead(i,t){return card('<div class="stepper" role="progressbar" aria-valuemin="1" aria-valuemax="4" aria-valuenow="'+i+'" style="display:flex;gap:6px">'+[1,2,3,4].map(function(n){return '<i style="flex:1;height:6px;border-radius:9px;background:'+(n<=i?'var(--pri)':'var(--track)')+'"></i>';}).join('')+'</div><p class="gx-lead" style="margin-top:10px">Step '+i+' of 4: '+E(t)+'</p>','flat');}
function homeName(d,id){var h=d.homes.filter(function(x){return x.id===id;})[0];return h?h.name:'';}
scr('g-family','Family structure',function(c,g){
 var d=draft(),step=g.ui.fstep||1,lock=g.fam.rhythm.locked;
 var h='';
 if(g.famV!==g.fdraftV&&g.fdraft){h+=K.notice({tone:'warn',title:'The family changed since you started',text:'Someone else saved a change. Start again from the latest version so nothing is overwritten.',ic:'warn',action:null})+btn('Start again from the latest','gFamRebase',null,{kind:'tonal',full:true,ic:'refresh'});}
 if(step===1){
  h+=stepHead(1,'Who is in her life')+K.banner('pri','You can change this on your own. '+pName()+' sees every change. '+cname()+' sees only what you release.','eye')+
   card(d.people.map(function(p){return rowA({av:av(p.id,42),title:p.name+(p.guardian?'':''),sub:pDesc(p,d),go:true},'gPerson',p.id);}).join(''))+
   btn('Add someone','gPersonNew',null,{kind:'tonal',full:true,ic:'plus'})+
   note('Each person shows the name '+E(cname())+' uses, not a role word. For '+E(myName())+' and '+E(pName())+' that name is '+E(cname())+'’s own choice: '+E(labelFor('mom'))+' and '+E(labelFor('dad'))+'.')+
   btn('Next: homes','gStep',2,{full:true,size:'lg',ic:'arrowR'});
 }else if(step===2){
  h+=stepHead(2,'Homes')+card(d.homes.map(function(hm,i){var inn=d.people.filter(function(p){return p.home===hm.id;}).map(function(p){return p.name;});
    return '<div style="padding:8px 0;border-top:'+(i?'1px solid var(--line)':'0')+'">'+inp('grd.fdraft.homes.'+i+'.name','Home '+(i+1)+' name',{ic:'house'})+'<p class="gx-sub">'+(inn.length?E(inn.join(', '))+' live here.':'Nobody is placed here yet.')+'</p>'+(d.homes.length>1&&i>1?btn('Remove this home','gHomeDel',i,{kind:'ghost',ic:'trash'}):'')+'</div>';}).join(''))+
   (d.homes.length<4?btn('Add a home','gHomeAdd',null,{kind:'tonal',full:true,ic:'plus'}):note('Up to four homes.'))+
   note('Who is at each home is set on each person. Her weeks and packing follow it.')+
   btn('Next: rhythm','gStep',3,{full:true,size:'lg',ic:'arrowR'})+btn('Back','gStep',1,{kind:'ghost',full:true});
 }else if(step===3){
  var r=d.rhythm,first=r.pattern.charAt(0);
  h+=stepHead(3,'The weekly rhythm')+
   (lock?K.banner('info','The weekly rhythm is set by a court order. It is shown here and can’t be edited in Olive Branch.','lock'):'')+
   card('<span class="t-label">Two weeks'+(lock?' · locked by order':'')+'</span>'+rhythmBlock(r,r.kind==='own'&&!lock))+
   '<div class="gx-stack" role="radiogroup" aria-label="Pattern">'+opt('Alternating weeks','One week at each house',r.kind==='alt','gKind','alt',{dis:lock})+opt('2-2-5-5','Two, two, then five nights each',r.kind==='2255','gKind','2255',{dis:lock})+opt('Build my own','Tap each night to switch the house',r.kind==='own','gKind','own',{dis:lock})+'</div>'+
   (r.kind!=='own'?'<h5 style="margin:6px 2px 0">Who starts</h5>'+seg(['Mom’s house first','Dad’s house first'],first==='d'?1:0,'gFirst',{vals:['m','d'],label:'Who starts'}):'')+
   card('<span class="t-label">Exchange</span><b class="gx-lead">'+E(exchText())+'</b><p class="gx-sub">From the family’s schedule. The exchange time is set where pairing and the schedule are set up.</p>')+
   (g.exceptions.length?card('<h4>One-off nights</h4>'+g.exceptions.map(function(x){return '<div class="gx-it"><div class="tx"><b>'+fYmd(x.date)+' at '+E(x.house==='a'?'Mom’s house':'Dad’s house')+'</b><small>'+E(x.why||'Agreed swap')+'</small></div></div>';}).join('')):'')+
   btn('Next: see what '+cname()+' will see','gStep',4,{full:true,size:'lg',ic:'arrowR'})+btn('Back','gStep',2,{kind:'ghost',full:true});
 }else{
  var ch=diffFam(g.fam,d);
  h+=stepHead(4,'What '+cname()+' will see');
  if(!ch.length)h+=K.emptyState({spot:'family',title:'Nothing has changed',sub:'Go back and change who is in her life, her homes or the rhythm. Nothing reaches her until you release it.'})+btn('Back','gStep',1,{kind:'ghost',full:true});
  else{
   h+=card('<span class="t-label">The change</span>'+ch.map(function(x){return '<p class="gx-sub" style="margin-top:6px">'+I(x.cat==='rhythm'?'calendar':x.cat==='homes'?'house':'users',14,2)+' '+E(x.text)+'</p>';}).join(''))+
   card('<div class="gx-diff"><div><small>Now</small>'+peopleMini(g.fam)+'</div><div><small>After</small>'+peopleMini(d)+'</div></div>'+(ch.some(function(x){return x.cat==='rhythm';})?'<div class="gx-diff" style="margin-top:10px"><div>'+weekRow(g.fam.rhythm.pattern.slice(0,7))+'</div><div>'+weekRow(d.rhythm.pattern.slice(0,7))+'</div></div>':''));
   h+='<div class="gx-stack" role="radiogroup" aria-label="When it reaches her">'+opt('Now','Her screens change as soon as you save.',g.ftiming==='now','gTiming','now')+opt('Hold until I have told her','Her view stays the same. You release it when you have talked. Recommended for big changes.',g.ftiming==='hold','gTiming','hold')+opt('On a date','Her screens change on the day you pick, tomorrow or later, up to two years ahead.',g.ftiming==='date','gTiming','date')+'</div>';
   if(g.ftiming==='date')h+=inp('grd.fdate','Date',{type:'date',min:minDate(),max:maxDate(),ic:'calendar',hint:'Her time. She is told on that day, not before.'});
   h+=area('grd.fnote','A line in your own words (optional)',{rows:2,ph:'For example: Dana will be at Dad’s house on weekends.',hint:'Shown to her with the change. Only what you write, nothing is generated.'})+
    K.banner('info',pName()+' sees this change when you save, whichever timing you pick.','info')+
    btn(g.ftiming==='now'?'Save and show her now':g.ftiming==='date'?'Save for that date':'Save and hold','gFamSave',null,{full:true,size:'lg',ic:g.ftiming==='hold'?'hourglass':'check'})+
    btn('Back','gStep',3,{kind:'ghost',full:true});}
 }
 h+=dirtyDraft()||step!==1?'<div class="gx-actions">'+btn('Discard this draft','gFamDiscard',null,{kind:'ghost',ic:'trash'})+'</div>':'';
 h+=rowA({ic:'clock',title:'Family history',sub:'Every change, who made it, and when '+cname()+' was told',go:true},'go','g-history');
 return h;});
function peopleMini(d){return d.people.map(function(p){var r=[];if(p.reach.messages)r.push('chat');if(p.reach.calls)r.push('phone');if(p.reach.story)r.push('book');return '<div class="pp">'+av(p.id,26)+'<span style="flex:1;min-width:0;overflow-wrap:anywhere">'+E(p.name)+(p.away?' (away)':'')+'</span>'+r.map(function(x){return I(x,14,2);}).join('')+'</div>';}).join('');}
def('gStep',function(c,n){U(function(s,g){g.ui.fstep=+n;});});
def('gKind',function(c,k){U(function(s,g){var d=draft();var first=d.rhythm.pattern.charAt(0);d.rhythm.kind=k;if(k!=='own')d.rhythm.pattern=patternFor(k,first);});});
def('gFirst',function(c,f){U(function(s,g){var d=draft();d.rhythm.pattern=patternFor(d.rhythm.kind,f)||d.rhythm.pattern;});});
def('gOwn',function(c,i){U(function(s,g){var d=draft(),p=d.rhythm.pattern.split('');p[+i]=p[+i]==='m'?'d':'m';d.rhythm.pattern=p.join('');});});
def('gOwn2',function(c,i){U(function(s,g){var d=draft(),p=d.rhythm.pattern.split('');p[7+ +i]=p[7+ +i]==='m'?'d':'m';d.rhythm.pattern=p.join('');});});
def('gTiming',function(c,t){U(function(s,g){g.ftiming=t;});});
def('gHomeAdd',function(c){U(function(s,g){var d=draft();var id='h'+(d.homes.length+1)+uid('');d.homes.push({id:id,name:'Home '+(d.homes.length+1),who:[]});});});
def('gHomeDel',function(c,i){U(function(s,g){var d=draft();var h=d.homes.splice(+i,1)[0];d.people.forEach(function(p){if(h&&p.home===h.id)p.home='';});});});
def('gFamDiscard',function(c){U(function(s,g){g.fdraft=null;g.ui.fstep=1;});toast(c,'Draft discarded. Nothing changed.');});
def('gFamRebase',function(c){U(function(s,g){g.fdraft=null;g.ui.fstep=1;});toast(c,'Started again from the latest.');});
def('gFamSave',function(c){var g=G(),d=g.fdraft;if(!d)return;
 call(c,'POST','/v1/family-changes',{draft:d,baseV:g.fdraftV,mode:g.ftiming,date:g.fdate,note:g.fnote},function(good,res){
  if(!good){var m=res.code==='date_out_of_range'?'Pick tomorrow or later, up to two years ahead.':res.code==='stale_version'?'The family changed since you started. Start again from the latest.':res.code==='locked_by_order'?'The rhythm is set by a court order and can’t be changed here.':friendly(res);toast(c,m);return;}
  U(function(s,gg){gg.fdraft=null;gg.ui.fstep=1;gg.fnote='';});
  toast(c,g.ftiming==='now'?'Saved. '+cname()+'’s people updated.':g.ftiming==='hold'?'Saved and held. Nothing has reached '+cname()+'.':'Saved for '+fYmd(g.fdate)+'.');L.go('g','g-history');});});

/* ---- person editor */
scr('g-fam-person','Edit a person',function(c,g){
 var d=draft(),p=g.pedit;if(!p){return K.emptyState({spot:'family',title:'Nobody selected',sub:'Go back and pick a person.'});}
 var isG=!!p.guardian;
 return card('<span class="t-label">'+(p.isNew?'Adding someone':'Editing '+E(p.name))+'</span>'+
  (isG?'<b class="gx-lead">'+E(labelFor(p.id))+'</b><p class="gx-sub">'+E(cname())+' chooses what she calls '+E(gName(p.id))+'. A grown-up can’t rename a parent.</p>':inp('grd.pedit.name','The name '+cname()+' uses',{ic:'user',hint:'Use the name she says out loud.'})+'<div style="height:8px"></div>'+inp('grd.pedit.role','Role',{ic:'heart',hint:'For example: Dad’s partner, Grandma, a neighbour.'}))+'<div style="height:8px"></div>')+
 card('<h4>Where they are</h4>'+seg(d.homes.map(function(h){return h.name;}).concat(['Near and far']),(function(){var i=d.homes.map(function(h){return h.id;}).indexOf(p.home);return i<0?d.homes.length:i;})(),'gPHome',{vals:d.homes.map(function(h){return h.id;}).concat(['']),label:'Home'}))+
 card('<h4>How they reach '+E(cname())+'</h4>'+
  trow({ic:'chat',title:'Messages',sub:'A message button beside their face',on:p.reach.messages},'gPReach','messages')+
  trow({ic:'video',title:'Live calls',sub:'A call button beside their face',on:p.reach.calls},'gPReach','calls')+
  trow({ic:'book',title:'A weekly story',sub:'One story slot a week',on:p.reach.story},'gPReach','story'))+
 card(trow({ic:'hourglass',title:'Away for a while',sub:'Her tablet shows a gentle picture of them being away. No dates.',on:p.away},'gPAway'))+
 btn('Save this person','gPSave',null,{full:true,size:'lg',ic:'check'})+
 (!isG&&!p.isNew?btn('Remove from her people','gPDel',null,{kind:'danger',full:true,ic:'trash'}):'')+
 note('Nothing here reaches '+E(cname())+' until you save the change and release it.');},{});
def('gPerson',function(c,id){var d=draft();var p=d.people.filter(function(x){return x.id===id;})[0];U(function(s,g){g.pedit=clone(p);});L.go('g','g-fam-person');});
def('gPersonNew',function(c){draft();U(function(s,g){g.pedit={id:uid('p'),name:'',role:'',home:'',away:false,isNew:true,reach:{messages:true,calls:false,story:false}};});L.go('g','g-fam-person');});
def('gPHome',function(c,v){U(function(s,g){g.pedit.home=v;});});
def('gPReach',function(c,k){U(function(s,g){g.pedit.reach[k]=!g.pedit.reach[k];});});
def('gPAway',function(c){U(function(s,g){g.pedit.away=!g.pedit.away;});});
def('gPSave',function(c){var g=G(),p=g.pedit;if(!p.guardian&&!String(p.name).trim()){toast(c,'Give them the name '+cname()+' uses.');return;}
 U(function(s,gg){var d=draft();var i=-1;d.people.forEach(function(x,j){if(x.id===p.id)i=j;});var np=clone(p);delete np.isNew;np.name=String(np.name).trim();np.role=String(np.role||'Family').trim();if(i<0)d.people.push(np);else d.people[i]=np;gg.pedit=null;gg.ui.fstep=1;});
 L.back('g');toast(c,'Added to your draft. Nothing has reached '+cname()+'.');});
def('gPDel',function(c){var g=G(),p=g.pedit;U(function(s,gg){var d=draft();d.people=d.people.filter(function(x){return x.id!==p.id;});gg.pedit=null;});L.back('g');toast(c,'Removed in your draft.');});

/* ---- history */
scr('g-history','Family history',function(c,g){
 var f=g.ui.hfilter||'all',list=g.hist.slice().reverse().filter(function(e){if(f==='all')return true;return (e.changes||[]).some(function(x){return x.cat===f;});});
 var le=latestEffect();
 var h=K.banner('warn','This list can’t be edited or deleted. Both guardians see the same entries. An undo is a new entry; the first one stays.','lock')+
  seg(['All','People','Rhythm','Homes'],['all','people','rhythm','homes'].indexOf(f),'gHFilter',{vals:['all','people','rhythm','homes'],label:'Filter'});
 if(!list.length)return h+card(K.empty('users','No changes yet','Every change to her people, homes and rhythm will appear here, with who made it and when she was told.'))+btn('Start with her people','go','g-family',{kind:'tonal',full:true,ic:'plus'});
 h+=card(list.map(function(e){var st=hstat(e),pend=(st==='held'||st==='scheduled');
  var chip={held:K.chip('Held until told',{tone:'warn',sm:true}),scheduled:K.chip('On '+(e.timing&&e.timing.date?fYmd(e.timing.date):'a date'),{tone:'info',sm:true}),released:K.chip('Released',{tone:'ok',sm:true}),applied:K.chip('Applied',{tone:'ok',sm:true}),undone:K.chip('Undone by a newer entry',{sm:true}),cancelled:K.chip('Cancelled',{sm:true})}[st]||'';
  var by=e.by==='sys'?'sys':e.by;
  return '<div class="gx-it">'+(by==='sys'?K.avatar('O',{size:38,tone:'quiet'}):av(by,38))+'<div class="tx"><b>'+E(e.text)+'</b><small>'+ago(e.t)+' · '+fT(e.t,myTz())+(e.told?' · Told '+E(cname())+' '+fD(e.told,myTz()):'')+'</small><div style="margin-top:6px;display:flex;gap:6px;flex-wrap:wrap;align-items:center">'+chip+
   (pend?btn('I have told her. Release','gRelease',e.id,{kind:'tonal',size:'sm',ic:'check'})+btn('Cancel it','gUndo',e.id,{kind:'ghost',size:'sm'}):'')+
   (!pend&&le&&le.id===e.id&&st!=='undone'?btn('Undo','gUndo',e.id,{kind:'ghost',size:'sm',ic:'undo'}):'')+'</div></div></div>';}).join(''));
 return h+note('Court orders are shown as such and can’t be changed here. “Told” is a date a guardian recorded, not something the app guessed.');});
def('gHFilter',function(c,v){U(function(s,g){g.ui.hfilter=v;});});
def('gRelease',function(c,id){call(c,'POST','/v1/family-changes/'+id+'/release',{},function(good,res){toast(c,good?'Released. '+cname()+'’s people updated.':(res.code==='stale_version'?'The family changed since this was saved. Cancel it and start again.':friendly(res)));L.queueRender();});});
def('gUndo',function(c,id){call(c,'POST','/v1/family-changes/'+id+'/undo',{},function(good,res){toast(c,good?'Done. It is a new entry; the first one stays.':(res.code==='not_latest'?'Undo the newest change first.':friendly(res)));L.queueRender();});});

/* ================================================================================ DEVICES + ADULTS AND HELPERS */
function allDevices(){var s=sx(),g=G();var out=[];(s.family.devices||[]).forEach(function(d){out.push({id:d.deviceId,owner:d.kind==='child'?'kid':'self',name:d.name,kind:d.kind==='child'?'tablet':'phone',since:d.pairedAt,real:true});});
 g.extraDev.forEach(function(d){out.push({id:d.id,owner:d.owner,name:d.name,kind:d.kind,since:d.since,real:false});});return out;}
scr('g-devices','Paired devices',function(c,g){
 var ds=allDevices(),mine=ds.filter(function(d){return d.owner==='self';}),kids=ds.filter(function(d){return d.owner==='kid';});
 var line=function(d,me){return rowA({ic:d.kind==='tablet'?'tablet':'phone',title:d.name+(me?' (this phone)':''),sub:'Paired '+ago(d.since||T()),trail:btn(me?'Sign out here':'Remove','gRevoke',d.id,{kind:'ghost',size:'sm'})},'noop');};
 return K.banner('pri','Each guardian can remove only their own devices and '+cname()+'’s. You can’t see or remove '+pName()+'’s.','shield')+
  sec('Yours')+card(mine.length?mine.map(function(d){return line(d,true);}).join(''):K.empty('phone','No device listed','Pair this phone again to see it here.'))+
  sec(cname()+'’s devices')+card(kids.length?kids.map(function(d){return line(d,false);}).join(''):K.empty('tablet','No devices for '+cname(),'Make a pairing code to add her tablet.'))+
  sec(pName())+card(rowA({ic:'users',title:pName()+' has '+g.otherDevices+' device'+(g.otherDevices===1?'':'s')+' paired',sub:'You can’t see which, or remove them. '+pName()+' can.'},'noop'))+
  rowA({ic:'tablet',title:'Add '+cname()+'’s tablet',sub:'Make a 6-digit code',go:true},'go','ob.addDevice')+
  note('Removing a device needs your PIN. The other guardian is told, and the device is signed out on its next request.');});
def('gRevoke',function(c,id){var d=allDevices().filter(function(x){return x.id===id;})[0];gate(c,'Remove '+(d?d.name:'this device'),'gRevokeDo',id);});
GATED.gRevokeDo=function(c,id){var d=allDevices().filter(function(x){return x.id===id;})[0];
 call(c,'POST','/v1/guardian/devices/'+id+'/revoke',{},function(good,res){
  if(!good){toast(c,res.code==='not_your_device'?'That device belongs to '+pName()+'. Only they can remove it.':friendly(res));return;}
  toast(c,(d?d.name:'The device')+' was removed. '+pName()+' was told.');
  if(d&&d.owner==='self'){L.reroot('g',L.hasScreen('ob.revoked','g')?'ob.revoked':signedOutScreen());}L.queueRender();});};
L.route('POST','/v1/guardian/devices/:id/revoke',function(req){var s=sx(),g=G(),id=req.params.id;
 var d=allDevices().filter(function(x){return x.id===id;})[0];
 if(!d){if(id==='dev-p-1'||/^dev-p/.test(id))return fail(403,'not_your_device','Only the guardian who paired a device can remove it');return fail(404,'not_found','No such device');}
 s.server.revoked[id]=true;s.family.devices=(s.family.devices||[]).filter(function(x){return x.deviceId!==id;});g.extraDev=g.extraDev.filter(function(x){return x.id!==id;});
 notifyPartner(myName()+' removed '+d.name+'.','device');L.emit('device:revoked',{deviceId:id,by:gid(),owner:d.owner});
 if(d.owner==='self'){s.dev.g.sessionOk=false;}if(d.owner==='kid'&&s.dev.k.deviceId===id){s.dev.k.revoked=true;s.dev.k.sessionOk=false;}
 return ok({revoked:id});},{principals:['guardian']});

scr('g-adults','Adults and helpers',function(c,g){
 var k=kg(),v=k.village||{};var others=g.fam.people.filter(function(p){return !p.guardian;});
 return sec('Guardians')+card(['mom','dad'].map(function(id){return K.row({av:av(id,40),title:gName(id)+(id===gid()?' (you)':''),sub:cname()+' calls '+(id===gid()?'you ':'')+labelFor(id)+(id===gid()?'':'')});}).join(''))+
  sec('People in her life')+card(others.length?others.map(function(p){return K.row({av:av(p.id,40),title:p.name,sub:p.role});}).join(''):K.empty('users','Nobody else yet','Add people in the family structure.'))+
  rowA({ic:'users',title:'Change who is in her life',sub:'Goes through the preview and your timing',go:true},'go','g-family')+
  sec('Helpers')+card('<h4>Sitter pass</h4><p class="gx-sub">'+(v.sitter&&v.sitter.name?E(v.sitter.name)+(v.sitter.from?' · '+E(v.sitter.from)+' to '+E(v.sitter.until):''):'No pass written yet.')+'</p><p class="gx-fine">Written by you. Shown on this screen only: it is not sent, saved by the sitter or shared as a link.</p><div class="gx-actions">'+btn('Write or edit','go','g-s-village',{kind:'tonal'})+btn('Show on screen','gShowPass',null,{kind:'ghost',ic:'eye'})+'</div>')+
  card('<h4>Grandparent page</h4><p class="gx-sub">'+(v.grand&&v.grand.greeting?E(v.grand.greeting):'A page you write for a grandparent who is visiting.')+'</p><div class="gx-actions">'+btn('Write or edit','go','g-s-village',{kind:'tonal'})+btn('Show on screen','gShowGrand',null,{kind:'ghost',ic:'eye'})+'</div>')+
  card('<h4>School summary</h4><p class="gx-sub">'+(v.school&&v.school.text?E(v.school.text):'A short note about what her school needs to know.')+'</p>'+btn('Write or edit','go','g-s-village',{kind:'tonal',full:true}))+
  rowA({ic:'users',title:pName()+' (simulated co-guardian)',sub:'Try swaps, conflicts and notifications',go:true},'go','g-partner');});
def('gShowPass',function(c){openM('pass',{which:'sitter'});});
def('gShowGrand',function(c){openM('pass',{which:'grand'});});
MODALS.pass=function(c,g,m){var v=(kg().village)||{},e=g.srv.emerg.data;
 var body=m.which==='sitter'?'<h3 style="margin:0;font:800 22px var(--font-display,inherit)">Looking after '+E(cname())+'</h3>'+K.kv([['Sitter',(v.sitter&&v.sitter.name)||'Not written yet'],['When',v.sitter&&v.sitter.from?v.sitter.from+' to '+v.sitter.until:'Not set'],['Allergies',e.allergies],['Conditions',e.conditions],['Who to call',e.contacts],['Bedtime',f12((kg().play||g.play).bed||'19:30')]])+'<p class="gx-sub">'+E((v.sitter&&v.sitter.notes)||'No extra notes.')+'</p>'
  :'<h3 style="margin:0;font:800 22px var(--font-display,inherit)">Welcome</h3><p class="gx-lead">'+E((v.grand&&v.grand.greeting)||'No greeting written yet.')+'</p>'+K.kv([['What '+cname()+' likes',(v.grand&&v.grand.likes)||'Not written yet'],['Bedtime',(v.grand&&v.grand.bedtime)||f12((kg().play||g.play).bed||'19:30')],['Who to call',e.contacts]]);
 return '<div class="gx-full" role="dialog" aria-modal="true" aria-label="Pass">'+K.banner('info','Written by '+E(myName())+'. Shown on this screen only. It can’t be sent or saved from here.','eye')+card(body)+btn('Done','gClose',null,{full:true,size:'lg'})+'</div>';};
def('gClose',function(c){closeM();});

/* ================================================================================ SAFETY: PIN, controls, data, deletion, session */
function pinTry(entered){var g=G(),sv=sx().server,t=T();var li=lockInfo();if(li.locked)return {ok:false,locked:true,left:li.left};
 if(entered===pinOf()){g.pin.fails=[];sv.pinFails=0;return {ok:true};}
 g.pin.fails.push(t);g.pin.fails=g.pin.fails.filter(function(x){return t-x<15*MIN;});
 var li2=lockInfo();if(li2.locked){sv.pinLockUntil=li2.until;return {ok:false,locked:true,left:li2.left};}
 return {ok:false,tries:li2.tries};}
var KEYS=[7,3,9,1,5,8,2,6,4];
function padHtml(len,act,arg){var dots=K.dots(4,len);return dots+'<div class="gx-kp" role="group" aria-label="PIN pad">'+KEYS.map(function(n){return '<button type="button" aria-label="'+n+'"'+L.a(act,n,arg)+'>'+n+'</button>';}).join('')+'<span></span><button type="button" aria-label="0"'+L.a(act,0,arg)+'>0</button><button type="button" aria-label="Delete"'+L.a(act,'del',arg)+'>'+I('backspace',24,1.8)+'</button></div>';}
function lockMsg(li){return 'Too many wrong PINs. Try again in '+li.left+' minute'+(li.left===1?'':'s')+' (virtual time).';}
MODALS.pin=function(c,g,m){var li=lockInfo();
 var inner='<p class="gx-sub" style="text-align:center">'+E(m.reason)+'</p>'+(li.locked?K.notice({tone:'bad',title:'Locked for now',text:lockMsg(li),ic:'lock'}):padHtml(m.entered.length,'gPinKey')+(m.wrong?'<p class="gx-sub" role="alert" style="text-align:center;color:var(--bad)">That PIN is not right. '+li.tries+' '+(li.tries===1?'try':'tries')+' left before a 15 minute pause.</p>':''));
 return sheet('Enter your PIN',inner,btn('Cancel','gClose',null,{kind:'ghost'}));};
def('gPinKey',function(c,k){var g=G(),m=g.ui.modal;if(!m||m.kind!=='pin')return;
 U(function(){if(k==='del'){m.entered=m.entered.slice(0,-1);m.wrong=false;return;}
  if(m.entered.length>=4)return;m.entered+=String(k);m.wrong=false;
  if(m.entered.length===4){var r=pinTry(m.entered);if(r.ok){var then=m.then,arg=m.arg,arg2=m.arg2;g.ui.modal=null;setTimeout(function(){var f=GATED[then];if(f){G();f({dev:'g',arg2:arg2},arg,arg2);L.queueRender();}},0);}else{m.entered='';m.wrong=true;}}});});

/* ---- change PIN: current, new, confirm (inline pad) */
scr('g-pin','Guardian PIN',function(c,g){
 var st=g.ui.pinStep||'cur',buf=g.ui.pinBuf||'',li=lockInfo();
 var title={cur:'Enter your current PIN',new:'Choose a new PIN',confirm:'Type the new PIN again'}[st];
 return card('<p class="gx-sub">Set '+Math.max(0,Math.round((T()-g.pin.changedAt)/DAY))+' days ago. It protects pairing codes, removing devices, wiping this phone and deleting your account. '+E(cname())+' never sees it.</p>')+
  (li.locked?K.notice({tone:'bad',title:'Locked for now',text:lockMsg(li),ic:'lock'}):card('<b class="gx-lead" style="text-align:center">'+E(title)+'</b>'+padHtml(buf.length,'gPin2')+(g.ui.pinErr?'<p class="gx-sub" role="alert" style="text-align:center;color:var(--bad)">'+E(g.ui.pinErr)+'</p>':'')))+
  K.steps(['Current','New','Confirm'],{cur:0,new:1,confirm:2}[st])+
  note('Five wrong tries in 15 minutes pause every PIN check for 15 minutes. A new PIN works at once on this phone. '+pName()+' keeps their own PIN.');});
def('gPin2',function(c,k){var g=G();
 U(function(){var st=g.ui.pinStep||'cur',buf=g.ui.pinBuf||'';g.ui.pinErr='';
  if(k==='del'){g.ui.pinBuf=buf.slice(0,-1);return;}
  if(buf.length>=4)return;buf+=String(k);g.ui.pinBuf=buf;if(buf.length<4)return;
  if(st==='cur'){var r=pinTry(buf);if(r.ok){g.ui.pinCur=buf;g.ui.pinStep='new';}else g.ui.pinErr=r.locked?lockMsg(r):'That is not your PIN. '+r.tries+' tries left.';g.ui.pinBuf='';}
  else if(st==='new'){if(buf===g.ui.pinCur){g.ui.pinErr='Pick a different PIN from the old one.';}else if(/^(\d)\1{3}$/.test(buf)||buf==='1234'||buf==='4321'){g.ui.pinErr='That one is easy to guess. Pick another.';}else{g.ui.pinNew=buf;g.ui.pinStep='confirm';}g.ui.pinBuf='';}
  else{if(buf!==g.ui.pinNew){g.ui.pinErr='They did not match. Start the new PIN again.';g.ui.pinStep='new';g.ui.pinBuf='';return;}
   var cur=g.ui.pinCur,nw=buf;g.ui.pinBuf='';
   setTimeout(function(){call(c,'POST','/v1/guardian/pin',{current:cur,next:nw},function(good,res){G();U(function(s,gg){gg.ui.pinStep='cur';gg.ui.pinCur='';gg.ui.pinNew='';gg.ui.pinBuf='';});if(good){toast(c,'PIN changed. Use the new one from now on.');L.back('g');}else toast(c,res.code==='invalid_pin'?'The current PIN was not right.':res.code==='pin_locked'?'Too many wrong PINs. Wait 15 minutes.':friendly(res));});},0);}});});
L.route('POST','/v1/guardian/pin',function(req){var g=G(),b=req.body||{};
 if(!/^\d{4}$/.test(String(b.next||'')))return fail(422,'invalid_pin','PIN must be 4 digits');
 var r=pinTry(String(b.current||''));if(r.locked)return fail(423,'pin_locked','Too many wrong PINs',{retryAfterMin:r.left});if(!r.ok)return fail(403,'invalid_pin','That PIN is not right',{attemptsLeft:r.tries});
 sx().family.pin=String(b.next);g.pin.changedAt=T();return ok({changed:true});},{principals:['guardian']});

/* ---- parental controls */
var CTL=[['games','dice','Games'],['stories','book','Stories and reading'],['draw','brush','Draw and colour'],['colour','palette','Colour of the day'],['together','tv','Watch together']];
var PACE=[[0,'No limit'],[30,'30 min a day'],[60,'1 hour a day'],[120,'2 hours a day']];
function srvCtl(by,b){var g=G(),k=kg(),tile=b.tile;
 if(tile==='messages'&&b.hidden)return fail(403,'cannot_hide_messages','Messages can never be hidden. Family must always be able to reach '+cname()+'.');
 if(!CTL.some(function(x){return x[0]===tile;}))return fail(404,'not_found','No such tile');
 var cur=g.ctl.tiles[tile]||{hidden:false,pace:0},nx=clone(cur),what=[];
 if(b.hidden!==undefined){nx.hidden=!!b.hidden;what.push(nx.hidden?'hid it':'showed it');}
 if(b.pace!==undefined){nx.pace=+b.pace;what.push(nx.pace?'paced it to '+nx.pace+' min a day':'removed the pace');}
 g.ctl.tiles[tile]=nx;g.ctl.changed[tile]={by:by,t:T(),what:what.join(' and ')};
 k.hiddenTiles=Object.keys(g.ctl.tiles).filter(function(x){return g.ctl.tiles[x].hidden;});k.pace={};Object.keys(g.ctl.tiles).forEach(function(x){if(g.ctl.tiles[x].pace)k.pace[x]=g.ctl.tiles[x].pace;});
 k.rev=(k.rev||0)+1;k.updated=k.updated||{};k.updated.hiddenTiles=T();L.emit('grd:published',{key:'hiddenTiles'});
 var nm=CTL.filter(function(x){return x[0]===tile;})[0][2];
 if(by===gid())notifyPartner(myName()+' '+what.join(' and ')+': '+nm+'.','control');else notifyMe(gName(by)+' '+what.join(' and ')+': '+nm+'.','control',by);
 return ok({tile:tile,state:nx});}
L.route('PUT','/v1/parental-controls',function(req){return srvCtl(gid(),req.body);},{principals:['guardian']});
scr('g-controls','Parental controls',function(c,g){
 var h=K.banner('pri','These shape what '+cname()+' sees. Her app never shows that a tile was hidden or paced, and has no settings.','shield');
 h+=card('<div class="row"><span class="ricon">'+I('chat',20,1.9)+'</span><span class="rtxt"><b>Messages</b><small>Can never be hidden or paced. Family must always be able to reach her.</small></span><span class="chip sm">'+I('lock',12,2)+'Always on</span></div>');
 CTL.forEach(function(t){var cur=g.ctl.tiles[t[0]]||{hidden:false,pace:0},ch=g.ctl.changed[t[0]];
  h+=card('<div class="row" style="padding:0"><span class="ricon">'+I(t[1],20,1.9)+'</span><span class="rtxt"><b>'+t[2]+'</b><small>'+(cur.hidden?'Hidden from '+E(cname()):cur.pace?'Paced to '+cur.pace+' min a day':'Shown, no limit')+'</small></span>'+tgl(!cur.hidden,'Show '+t[2],'gCtlHide',t[0])+'</div>'+
   (cur.hidden?'':'<div style="margin-top:8px">'+seg(PACE.map(function(p){return p[1];}),Math.max(0,PACE.map(function(p){return p[0];}).indexOf(cur.pace||0)),'gCtlPace',{vals:PACE.map(function(p){return p[0];}),arg2:t[0],label:'Pace for '+t[2]})+'</div>')+
   (ch?'<p class="gx-fine">'+I('user',12,2)+' Changed by '+(ch.by===gid()?'you':E(gName(ch.by)))+' '+ago(ch.t)+': '+E(ch.what)+'.</p>':'<p class="gx-fine">Not changed yet.</p>'));});
 return h+note('A change by one guardian shows who made it, and when, to the other. '+E(pName())+' sees what you change here.');});
def('gCtlHide',function(c,t){var g=G();var cur=g.ctl.tiles[t]||{hidden:false};call(c,'PUT','/v1/parental-controls',{tile:t,hidden:!cur.hidden},function(good,res){toast(c,good?(cur.hidden?'Shown again':'Hidden from '+cname()):(res.code==='cannot_hide_messages'?'Messages can never be hidden.':friendly(res)));L.queueRender();});});
def('gCtlPace',function(c,v){var t=c.arg2;call(c,'PUT','/v1/parental-controls',{tile:t,pace:+v},function(good,res){toast(c,good?'Saved':friendly(res));L.queueRender();});});

/* ---- data on this device, wipe, download */
function dlJson(name,obj){try{var b=new Blob([JSON.stringify(obj,null,2)],{type:'application/json'});var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=name;document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove();},500);return true;}catch(e){return false;}}
scr('g-data','Data on this phone',function(c,g){
 var s=sx(),msgN=0;try{msgN=((s.msg&&s.msg.items)||(s.msg&&s.msg.messages)||[]).length;}catch(e){}
 return K.banner('pri','This is what lives on this phone, and what lives on the server. Be clear which is which before you wipe.','shield')+
  sec('On this phone only')+card(K.kv([['Your PIN','Stored as a hash. Never sent.'],['Unsent drafts',(g.fdraft?1:0)+g.local.drafts+' item'+(g.fdraft||g.local.drafts!==1?'s':'')],['Waiting to send',g.outbox.length?g.outbox.length+' change'+(g.outbox.length===1?'':'s')+' (lost if you wipe)':'Nothing'],['Cached messages',msgN?msgN+' (re-downloaded after sign-in)':'A short cache'],['Session',s.dev.g.sessionOk?'Signed in':'Signed out'],['Times wiped',String(g.local.wiped)]],{ruled:true}))+
  sec('On the server (not affected by a wipe)')+card(K.kv([['Family record','Both guardians, '+cname()],['Shared log','Handover notes, family history'],['Emergency card','Version '+g.srv.emerg.v],['Medications','Names, doses and the dose log']],{ruled:true}))+
  card('<h4>Download</h4><p class="gx-sub">A copy of what you can see, as a file. It leaves out '+E(cname())+'’s private journal and worry box, which you never had.</p>'+btn('Download a copy','gDownload',null,{kind:'tonal',full:true,ic:'download'}))+
  card('<h4>Wipe this phone</h4><p class="gx-sub">Clears drafts and anything waiting to send, and signs this phone out. Nothing on the server is deleted. You can sign in again with your PIN.</p>'+btn('Wipe this phone','gWipe',null,{kind:'danger',full:true,ic:'trash'}))+
  rowA({ic:'trash',title:'Delete my account',sub:'A 6 to 12 month recovery window',go:true},'go','g-delete');});
def('gDownload',function(c){var g=G();var ok0=dlJson('olive-branch-my-copy.json',{exportedAt:new Date(T()).toISOString(),by:myName(),family:g.fam,history:g.hist,emergencyCard:g.srv.emerg.data,medications:g.srv.meds.map(function(m){return {name:m.name,dose:m.dose,kind:m.kind};}),handoverNotes:g.srv.notes,note:'Simulation data. Contains nothing from the private journal or worry box.'});toast(c,ok0?'Copy saved as a file.':'Your browser blocked the download.');});
def('gWipe',function(c){gate(c,'Wipe this phone','gWipeDo');});
GATED.gWipeDo=function(c){openM('wipe',{});};
MODALS.wipe=function(c,g,m){return K.modal({ic:'trash',tone:'bad',title:'Wipe this phone?',body:'Unsent drafts and anything waiting to send ('+g.outbox.length+') are lost. You will be signed out. Nothing on the server is deleted.',actions:btn('Keep things as they are','gClose',null,{kind:'ghost'})+btn('Wipe this phone','gWipeGo',null,{kind:'danger'}),stack:true}).replace('<div class="scrim">','<div class="scrim" data-act="gClose">');};
def('gWipeGo',function(c){U(function(s,g){g.ui.modal=null;g.outbox=[];g.fdraft=null;g.f={};g.local.drafts=0;g.local.wiped++;});
 call(c,'POST','/v1/auth/session/sign-out',{},function(){});L.reroot('g',signedOutScreen());toast(c,'Wiped. Sign in again with your PIN.');});

/* ---- account deletion with the 6 to 12 month recovery window */
function acctPhase(){var a=G().acct,t=T();if(a.state!=='pending')return 'active';if(t>=a.maxEnd)return 'erased';if(t>=a.minEnd)return 'late';return 'window';}
scr('g-delete','Delete my account',function(c,g){
 var a=g.acct,t=T();
 return K.notice({tone:'warn',title:'Read this first',text:'This pauses your sign-in at once. Your data is kept for between 6 and 12 months, and you can recover it or download it until the window ends.',ic:'warn'})+' '+rv('needs legal review')+
  card('<h4>What happens</h4><ol class="gx-li no" style="counter-reset:n">'+[
   ['Today','Your sign-in is paused on every device you own. '+cname()+'’s tablet and '+pName()+'’s phone keep working.'],
   ['Today, same day',pName()+' is told that you deleted your account.'],
   ['Months 0 to 6','Your account and data are kept. You can recover it or download everything.'],
   ['Months 6 to 12','Recovery stays possible until the window ends. We do not promise the exact day.'],
   ['After the window','Your account is erased. The shared log stays: handover notes and family history are a record both guardians share, and are never deleted.']].map(function(x,i){return '<li>'+I('clock',16,2)+'<span><b>'+x[0]+'.</b> '+E(x[1])+'</span></li>';}).join('')+'</ol>')+
  card('<h4>Before you go</h4><p class="gx-sub">You can download a copy first. It leaves out anything private to '+E(cname())+'.</p>'+btn('Download a copy','gDownload',null,{kind:'tonal',full:true,ic:'download'}))+
  (a.state==='pending'?K.banner('info','Deletion already started '+ago(a.at)+'.','info'):btn('Delete my account','gDelAsk',null,{kind:'danger',full:true,size:'lg',ic:'trash'}))+
  note('Needs your PIN. Wiping only this phone is a separate choice in Data on this phone.');});
def('gDelAsk',function(c){gate(c,'Delete your account','gDelDo');});
GATED.gDelDo=function(c){openM('delconfirm',{});};
MODALS.delconfirm=function(c,g,m){return K.modal({ic:'trash',tone:'bad',title:'Start the recovery window?',body:'Your sign-in pauses now. '+pName()+' is told today. Your data is kept for 6 to 12 months and you can recover it.',actions:btn('Not now','gClose',null,{kind:'ghost'})+btn('Delete my account','gDelGo',null,{kind:'danger'}),stack:true}).replace('<div class="scrim">','<div class="scrim" data-act="gClose">');};
def('gDelGo',function(c){U(function(s,g){g.ui.modal=null;});call(c,'POST','/v1/account/delete',{},function(good,res){if(!good){toast(c,friendly(res));return;}L.reroot('g','g-hold');});});
L.route('POST','/v1/account/delete',function(req){var g=G(),t=T();if(g.acct.state==='pending')return fail(409,'already_pending','Deletion already started');
 g.acct={state:'pending',at:t,minEnd:t+182*DAY,maxEnd:t+365*DAY,by:gid()};sx().dev.g.sessionOk=false;
 notifyPartner(myName()+' deleted their account today. Their data is kept for 6 to 12 months and they can recover it. The shared log (handover notes, family history) stays.','account');
 L.emit('account:deletion',{by:gid(),minEnd:g.acct.minEnd,maxEnd:g.acct.maxEnd});return ok({minEnd:g.acct.minEnd,maxEnd:g.acct.maxEnd});},{principals:['guardian']});
L.route('POST','/v1/account/recover',function(req){var g=G();if(g.acct.state!=='pending')return fail(409,'not_pending','Nothing to recover');
 if(T()>=g.acct.maxEnd)return fail(410,'erased','The recovery window has ended');
 var r=pinTry(String(req.body.pin||''));if(r.locked)return fail(423,'pin_locked','Too many wrong PINs');if(!r.ok)return fail(403,'invalid_pin','That PIN is not right',{attemptsLeft:r.tries});
 g.acct={state:'active'};try{L.newSession('g');}catch(e){sx().dev.g.sessionOk=true;}
 notifyPartner(myName()+' recovered their account.','account');return ok({recovered:true});},{public:true});
scr('g-hold','Account on hold',function(c,g){
 var a=g.acct,ph=acctPhase();
 if(ph==='active')return K.emptyState({spot:'leaf',title:'Your account is active',sub:'Nothing is on hold.'})+btn('Back to start','home',null,{full:true});
 if(ph==='erased')return K.errorState({title:'This account has been erased',sub:'The recovery window ended. The shared log stays with the family.',action:false})+card('<p class="gx-sub">Anyone can still make a new account. '+E(pName())+' and '+E(cname())+' are not affected.</p>');
 var dl=btn('Download everything','gDownload',null,{kind:'tonal',full:true,ic:'download'});
 return K.notice({tone:'info',title:'Your sign-in is paused',text:'You deleted your account '+ago(a.at)+'. Your data is kept for between 6 and 12 months.',ic:'lock'})+
  card('<h4>The window</h4>'+K.kv([['Started',fDY(a.at,myTz())],['Kept at least until',fDY(a.minEnd,myTz())],['Erased by',fDY(a.maxEnd,myTz())]],{ruled:true})+(ph==='late'?'<p class="gx-sub" style="color:var(--warn)">The guaranteed part has ended. Recovery may stop any day now.</p>':'<p class="gx-sub">Recovery is guaranteed until the first date.</p>'))+
  card('<h4>Recover</h4><p class="gx-sub">Enter your PIN to bring everything back.</p>'+padHtml((g.ui.recBuf||'').length,'gRecKey')+(g.ui.recErr?'<p class="gx-sub" role="alert" style="color:var(--bad);text-align:center">'+E(g.ui.recErr)+'</p>':''))+dl+
  card('<p class="gx-sub">'+E(pName())+' was told the same day. '+E(cname())+'’s tablet and '+E(pName())+'’s phone keep working. The shared log stays whatever you choose.</p>');});
def('gRecKey',function(c,k){var g=G();U(function(){var b=g.ui.recBuf||'';g.ui.recErr='';if(k==='del'){g.ui.recBuf=b.slice(0,-1);return;}if(b.length>=4)return;b+=String(k);g.ui.recBuf=b;if(b.length<4)return;g.ui.recBuf='';
 setTimeout(function(){call(c,'POST','/v1/account/recover',{pin:b},function(good,res){if(good){toast(c,'Welcome back. Everything is as you left it.');L.reroot('g','home');}else{U(function(s,gg){gg.ui.recErr=res.code==='invalid_pin'?'That PIN is not right.':res.code==='erased'?'The window has ended.':friendly(res);});}});},0);});});

/* ---- session expired / sign out */
scr('g-session','Signed out',function(c,g){
 if(acctPhase()!=='active'&&g.acct.state==='pending'){return btn('Go to account on hold','go','g-hold',{full:true});}
 var s=sx();
 return K.emptyState({spot:'key',title:s.dev.g.sessionOk?'You are signed in':'You are signed out',sub:s.dev.g.sessionOk?'Nothing to do.':'Your session ended on this phone. Enter your PIN to sign in again. '+cname()+' is not affected.'})+
  (s.dev.g.sessionOk?btn('Back to start','home',null,{full:true}):card('<b class="gx-lead" style="text-align:center">Your PIN</b>'+padHtml((g.ui.sessBuf||'').length,'gSessKey')+(g.ui.sessErr?'<p class="gx-sub" role="alert" style="text-align:center;color:var(--bad)">'+E(g.ui.sessErr)+'</p>':'')))+
  note('Your PIN is checked on the server. Five wrong tries pause sign-in for 15 minutes.');},{root:true,eyebrow:null});
def('gSessKey',function(c,k){var g=G();U(function(){var b=g.ui.sessBuf||'';g.ui.sessErr='';if(k==='del'){g.ui.sessBuf=b.slice(0,-1);return;}if(b.length>=4)return;b+=String(k);g.ui.sessBuf=b;if(b.length<4)return;g.ui.sessBuf='';
 setTimeout(function(){call(c,'POST','/v1/auth/session',{pin:b},function(good,res){if(good){toast(c,'Signed in');L.reroot('g','home');}else{U(function(s,gg){gg.ui.sessErr=res.code==='invalid_pin'?'That PIN is not right. '+((res.body&&res.body.error&&res.body.error.attemptsLeft)!=null?res.body.error.attemptsLeft+' tries left.':''):res.code==='pin_locked'?'Too many wrong PINs. Wait 15 minutes.':friendly(res);});}});},0);});});
def('gSignOut',function(c){call(c,'POST','/v1/auth/session/sign-out',{},function(){L.reroot('g','g-session');});});


/* ================================================================================ THE SIMULATED CO-GUARDIAN */
var BOTLOG=['Marcus','Jess'];
scr('g-partner',function(){return pName();},function(c,g){
 var P=pName();var h='';
 g.notes.forEach(function(n){n.read=true;});
 h+=K.notice({tone:'info',title:P+' is simulated',text:'This stands in for the other guardian so you can see how swaps, conflicts and notifications behave. Nothing here is a real person or a real account.',ic:'users'});
 h+=sec('Things '+P+' might do')+card(
  rowA({ic:'pencil',title:P+' edits the emergency card',sub:'Makes a version conflict if you have it open',go:true},'gBot','card')+
  rowA({ic:'pill',title:P+' logs a Vitamin D dose',sub:'Triggers the double-dose guard if you log it too',go:true},'gBot','dose')+
  rowA({ic:'swap',title:P+' asks to swap a night',sub:'You can accept or decline',go:true},'gBot','swapAsk')+
  rowA({ic:'check',title:P+' accepts your swap',sub:'If you proposed one',go:true},'gBot','swapYes')+
  rowA({ic:'x',title:P+' declines your swap',go:true},'gBot','swapNo')+
  rowA({ic:'receipt',title:P+' proposes an expense',sub:'You can accept, or dispute it',go:true},'gBot','exp')+
  rowA({ic:'check',title:P+' accepts or reimburses your expense',go:true},'gBot','expYes')+
  rowA({ic:'letter',title:P+' writes a handover note',go:true},'gBot','note')+
  rowA({ic:'clock',title:P+' raises daily time by an hour',sub:'You are told it is not a request',go:true},'gBot','daily')+
  rowA({ic:'dice',title:P+' paces Games to 1 hour',sub:'Shows “changed by” on parental controls',go:true},'gBot','pace')+
  rowA({ic:'shield',title:P+' tries to hide Messages',sub:'The server refuses',go:true},'gBot','hideMsg')+
  rowA({ic:'phone',title:P+' tries to remove your device',sub:'Each guardian can only remove their own',go:true},'gBot','revoke')+
  rowA({ic:'users',title:P+' adds someone to '+cname()+'’s people',sub:'Makes your family draft stale',go:true},'gBot','fam')+
  rowA({ic:'phone',title:P+' removes a device of their own',sub:'You are told',go:true},'gBot','revokeOwn'));
 h+=sec('Switches')+card(trow({ic:'lock',title:'Rhythm is set by a court order',sub:'The weekly rhythm becomes read-only with a lock',on:g.fam.rhythm.locked},'gLockToggle')+trow({ic:'book',title:P+' shares a two-home rules list',sub:'Read-only on your Learn screen',on:g.partner.rulesList},'gPRules'));
 h+=sec('What you have been told')+card(g.notes.length?g.notes.slice(0,12).map(function(n){return '<div class="gx-it">'+(n.by==='sys'?K.avatar('O',{size:34,tone:'quiet'}):av(n.by,34))+'<div class="tx"><b>'+E(n.text)+'</b><small>'+ago(n.t)+'</small></div></div>';}).join(''):K.empty('bell','Nothing yet','When '+P+' changes something that touches you, it appears here.'));
 h+=sec('What '+P+' has been told')+card(g.partner.told.length?g.partner.told.slice(0,12).map(function(n){return '<div class="gx-it">'+av(gid(),34)+'<div class="tx"><b>'+E(n.text)+'</b><small>'+ago(n.t)+'</small></div></div>';}).join(''):K.empty('bell','Nothing yet','Changes you make that '+P+' should know about show here.'));
 return h;},{eyebrow:'Simulation'});
def('gLockToggle',function(c){U(function(s,g){var v=!g.fam.rhythm.locked;g.fam.rhythm.locked=v;if(g.fdraft)g.fdraft.rhythm.locked=v;kg().rhythm=clone(g.fam.rhythm);if(v)histAdd({kind:'court',by:'sys',text:'Weekly rhythm set by court order (sample date)',status:'locked',changes:[{cat:'rhythm',text:'Locked by order'}]});});});
def('gPRules',function(c){U(function(s,g){g.partner.rulesList=!g.partner.rulesList;});});
def('gBot',function(c,k){var g=G(),P=pName();
 var res=botDo(k);if(res&&res.msg)toast(c,res.msg);L.queueRender();});

/* ================================================================================ PARENT LEARN (port of scaffold/packages/parent-learn/src/learn.ts) */
var SRC={
 AAP:{label:'AAP: Disciplining Your Child',url:'https://www.healthychildren.org/English/family-life/family-dynamics/communication-discipline/Pages/Disciplining-Your-Child.aspx'},
 CHAO:{label:'Chao 1994',url:'https://aacdrpubs.faculty.ucdavis.edu/wp-content/uploads/sites/211/2015/03/chao001.pdf'},
 DS93:{label:'Darling and Steinberg 1993',url:'https://data.zhenzhi.com/details/1/1001468350'},
 AK14:{label:'Avinun and Knafo 2014',url:'https://cris.huji.ac.il/en/publications/parenting-as-a-reaction-evoked-by-childrens-genotype-a-meta-analy/'},
 ND:{label:'Notre Dame: couples and kids',url:'https://shaw.nd.edu/research/couples-and-kids'},
 PD:{label:'ParentData: is gentle parenting evidence-based',url:'https://parentdata.org/ask/is-gentle-parenting-evidence-based-does-it-actually-work'},
 TRIPLE_P:{label:'Emotion-enhanced Triple P thesis',url:'https://openaccess.wgtn.ac.nz/articles/thesis/Integrating_emotion_into_behaviourally-based_parenting_programmes_can_this_enhance_outcomes_for_child_conduct_problems_/17006110'},
 BIELEFELD:{label:'Bielefeld longitudinal study',url:'https://pub.uni-bielefeld.de/record/1591258'},
 FATHERHOOD:{label:'Fatherhood Institute briefing',url:'https://fatherhoodinstitute.org/_files/ugd/efff1d_dc63e949baaa4de2ac96d5b562234262.pdf'}};
var CARDS=[
 {id:'two-dimensions',topic:'style',title:'Two things, not four boxes',body:'Home feels like a mix of warmth and expectations. The four named styles are corners of that map, not types of person. Most days you move around it.',evidence:'strong',sources:[SRC.DS93]},
 {id:'warm-and-clear',topic:'style',title:'Warm and clear',body:'Children tend to do well on school, mood and friendships when warmth and clear limits go together. This is a link in studies, not a promise, and it is not risk-free.',evidence:'moderate',sources:[SRC.DS93,SRC.PD]},
 {id:'climate-and-tools',topic:'style',title:'Climate and tools',body:'Style is the emotional climate. Practices are the tools. The same tool, such as a time-out, lands differently in a warm home than in a cold one.',evidence:'moderate',sources:[SRC.DS93]},
 {id:'child-shapes-parent',topic:'style',title:'Children shape parents too',body:'Twin studies estimate that about a quarter of the variation in parenting is driven by the child. Parent and child influence each other, so nobody is to blame for the whole picture.',evidence:'strong',sources:[SRC.AK14]},
 {id:'culture-changes-meaning',topic:'style',title:'Culture changes the meaning',body:'A firm, high-expectation style can mean care and training in some families and coldness in others. Research found the same style linked to opposite school results in different communities.',evidence:'contested',sources:[SRC.CHAO]},
 {id:'gentle-with-limits',topic:'style',title:'Gentle means kind and firm',body:'Gentle parenting has no studies of its own. Its ingredients, warmth, validation and limits that are held, match research on authoritative parenting. The risk is dropping the limits. Check: did I say the limit, and did I hold it?',evidence:'weak',sources:[SRC.PD]},
 {id:'short-time-out',topic:'discipline',title:'A short, calm time-out',body:'Name what happened, use a boring safe spot, stay calm and quiet, then reconnect. About one minute per year of age. Skip long isolation and punishing tears.',evidence:'strong',sources:[SRC.AAP],ages:[2,8]},
 {id:'avoid-hitting',topic:'discipline',title:'Hitting does not teach',body:'Pediatric guidance advises against physical punishment. It is less effective than time-outs or losing a privilege and is linked to more defiance.',evidence:'strong',sources:[SRC.AAP]},
 {id:'specific-praise',topic:'discipline',title:'Specific praise',body:'Name the thing they did. "You shared the red block" lands better than "good boy".',evidence:'moderate',sources:[SRC.AAP],ages:[3,8]},
 {id:'plain-instructions',topic:'communication',title:'Say it plainly',body:'If it is an instruction, say it as one, once, in specific words. "Shoes on, please" works better than "Can you put your shoes on?"',evidence:'moderate',sources:[SRC.AAP]},
 {id:'emotion-coaching',topic:'communication',title:'Naming feelings',body:"Emotion coaching reliably changes what parents do. Evidence that it improves 5 to 7 year olds' emotion skills is still thin and mostly parent-reported.",evidence:'weak',sources:[SRC.TRIPLE_P],ages:[4,8]},
 {id:'how-parents-fight',topic:'conflict',title:'How you disagree matters most',body:'Hostility and withdrawal between parents are linked to more child problems because a child may feel the family is unsafe. Calm disagreement that gets resolved is not harmful.',evidence:'strong',sources:[SRC.ND]},
 {id:'out-of-the-middle',topic:'coparenting',title:'Keep your child out of the middle',body:'No messengers, no questions about the other home, no criticism of the other parent in earshot.',evidence:'strong',sources:[SRC.ND]},
 {id:'rules-that-match',topic:'coparenting',title:'What is worth matching',body:'Core routines such as bedtime, screens, homework and safety are the better-supported place to line up. Evidence that matching whole styles matters is mixed, and low conflict matters more.',evidence:'moderate',sources:[SRC.BIELEFELD,SRC.FATHERHOOD]},
 {id:'repair',topic:'repair',title:'After you lost your temper',body:'Calm yourself first, go back and name it, say it was yours, then reconnect. Mistakes happen. A mistake does not make anyone bad.',evidence:'strong',sources:[SRC.AAP]},
 {id:'siblings',topic:'discipline',title:'When siblings fight',body:'Step in only if someone could be hurt. Name each feeling, ask what they could try, then notice the fix. Common practice, but no sibling-specific trials were found.',evidence:'weak',sources:[SRC.AAP],ages:[4,8]}];
var TOPICS=[['all','All'],['style','Style'],['discipline','Discipline'],['communication','Talking'],['conflict','Conflict'],['coparenting','Two homes'],['repair','Repair']];
var EVIDENCE={strong:['Strong',4,'Many studies point the same way.'],moderate:['Moderate',3,'Several studies, some limits.'],weak:['Weak',2,'Thin or indirect. Treat as an idea.'],contested:['Contested',1,'Studies disagree, or it depends on context.']};
function evChip(k){var m=EVIDENCE[k];return '<span class="gx-ev'+(k==='contested'?' con':'')+'" title="'+E(m[2])+'"><span>'+m[0]+'</span>'+[1,2,3,4].map(function(i){return '<i class="'+(i<=m[1]?'f':'')+'"></i>';}).join('')+'</span>';}
function isGuardianP(){return true;} /* Learn exists only on the guardian shell (L1) */
function cardsFor(st,age){return CARDS.filter(function(c){return age===undefined||!c.ages||(age>=c.ages[0]&&age<=c.ages[1]);}).map(function(c){return (st.framing==='culture-note'&&c.topic==='style'&&c.id!=='culture-changes-meaning')?{id:c.id,topic:c.topic,title:c.title,body:c.body+' What this means can differ by family and culture.',evidence:c.evidence,sources:c.sources,ages:c.ages}:c;});}
function describeDay(w,e){var hw=w>=50,he=e>=50;
 if(hw&&he)return {headline:'Warm, with clear limits.',prompt:'Notice: what made that possible today?'};
 if(!hw&&he)return {headline:'Firm today, with less warmth.',prompt:'Notice: what was going on for you? One small warm moment can change the day.'};
 if(hw&&!he)return {headline:'Warm today, with looser limits.',prompt:'Notice: was it a choice, or were you tired? One clear limit may be enough.'};
 return {headline:'Low on both today.',prompt:'Notice: are you okay? Support is fine to ask for. Tomorrow is a fresh day.'};}
var RULESRE=[
 {flag:'absolute',re:/\byou (always|never)\b/i,hint:'Try the one thing that happened: "On Friday bedtime was late."'},
 {flag:'blame',re:/\b(your fault|because of you|you('| a)re (the reason|to blame))\b/i,hint:'Describe the effect, not who is at fault.'},
 {flag:'contempt',re:/\b(idiot|stupid|pathetic|useless|incompetent|worthless)\b/i,hint:'Leave out the insult. It makes the real point harder to hear.'},
 {flag:'child-messenger',re:/\b(tell|ask) (your|the) (dad|mom|mum|mother|father|parent)\b|\bhave (her|him|them) tell\b/i,hint:'Send this to the other guardian directly. Please keep the child out of it.'},
 {flag:'questioning-child',re:/\bask (her|him|them|\w+) what (dad|mom|mum|mother|father|he|she)\b/i,hint:'Please do not question the child about the other home.'},
 {flag:'threat',re:/\b(i('| wi)ll (take|see you in)|you('| wi)ll regret|or else)\b/i,hint:'Say what you need and by when, without a threat.'}];
function checkMessage(st,text){if(!st.messageCheck)return null;if(typeof text!=='string')return [];var t=text.length>4000?text.slice(0,4000):text,out=[];RULESRE.forEach(function(r){if(r.re.test(t)&&!out.some(function(h){return h.flag===r.flag;}))out.push({flag:r.flag,hint:r.hint});});return out;}
var RULE_CATS=['bedtime','screens','homework','safety'];
function shareableRules(st,items){if(!st.rulesList||!Array.isArray(items))return [];var out=[];items.slice(0,20).forEach(function(it){if(!it||typeof it!=='object')return;if(RULE_CATS.indexOf(it.category)<0)return;if(typeof it.text!=='string'||!it.text.trim())return;out.push({category:it.category,text:it.text.trim().slice(0,200)});});return out;}
function lintCards(cards){var out=[],ids={},CAUSAL=/\b(causes?|caused|produces?|makes? your child|will make|guarantees?)\b/i,LABEL=/\byou are (a|an) (permissive|authoritarian|authoritative|neglectful|bad|lazy|helicopter)\b/i;
 cards.forEach(function(c){if(ids[c.id])out.push(c.id+': duplicate id');ids[c.id]=1;if(!EVIDENCE[c.evidence])out.push(c.id+': bad evidence');if(!c.sources.length)out.push(c.id+': no source');c.sources.forEach(function(s){if(!/^https:\/\//.test(s.url))out.push(c.id+': non-https');});if(CAUSAL.test(c.body)||CAUSAL.test(c.title))out.push(c.id+': causal');if(LABEL.test(c.body)||LABEL.test(c.title))out.push(c.id+': labels a person');});return out;}
function LS(){var g=G();if(!g.learn[gid()])g.learn[gid()]=freshLearn();return g.learn[gid()];}
function checkHintsHtml(){var st=LS().settings;if(!st.messageCheck)return '';var t=checkText;if(!t.trim())return '<p class="gx-sub">Type or paste a message you are about to send. Hints appear as you type.</p>';
 var r=checkMessage(st,t)||[];if(!r.length)return '<p class="gx-sub">'+I('check',14,2.4)+' No hints. That reads plainly.</p>';
 return r.map(function(h){return '<div class="gx-it">'+I('sparkle',16,2)+'<div class="tx"><b>'+E(h.hint)+'</b><small>'+E(h.flag.replace(/-/g,' '))+'</small></div></div>';}).join('')+'<p class="gx-fine">Hints only. You write the message. '+rv('needs review')+'</p>';}

scr('g-learn','Parent Learn',function(c,g){
 var ls=LS(),st=ls.settings,age=child().age,list=cardsFor(st,ls.ageAll?undefined:age).filter(function(x){return ls.topic==='all'||x.topic===ls.topic;});
 var h=K.banner('pri','Only you can read Learn. '+cname()+'’s app has none, and '+pName()+' can’t see what you read or choose.','lock');
 if(st.framing==='values-first')h+=card('<span class="t-label">Start with your values</span><p class="gx-lead">What matters most in your home?</p><p class="gx-sub">The cards below are research, not rules. Your family decides what to use.</p>','tint');
 h+=card('<span class="t-label">How to read the labels</span><div style="display:grid;gap:6px;margin-top:6px">'+Object.keys(EVIDENCE).map(function(k){return '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">'+evChip(k)+'<span class="gx-sub" style="margin:0">'+E(EVIDENCE[k][2])+'</span></div>';}).join('')+'</div>');
 h+=seg(['For '+cname()+'’s age ('+age+')','All ages'],ls.ageAll?1:0,'gLAge',{vals:[0,1],label:'Age filter'});
 h+=chips(TOPICS.map(function(t){return t[1];}),ls.topic,'gLTopic',TOPICS.map(function(t){return t[0];}));
 h+=list.length?list.map(function(cd){return card('<div style="display:flex;justify-content:space-between;gap:8px;align-items:flex-start"><h4>'+E(cd.title)+'</h4>'+evChip(cd.evidence)+'</div><p class="gx-sub">'+E(cd.body)+'</p>'+(cd.ages?'<p class="gx-fine">Written for ages '+cd.ages[0]+' to '+cd.ages[1]+'.</p>':'')+'<div style="margin-top:6px">'+cd.sources.map(function(s){return '<span class="gx-src">'+I('link',12,2)+' <a href="'+E(s.url)+'" target="_blank" rel="noopener noreferrer">'+E(s.label)+'</a></span>';}).join('')+'</div>');}).join(''):K.emptyState({spot:'leaf',title:'No cards for this filter',sub:'Try All ages or another topic.'});
 h+=note(list.length+' of '+CARDS.length+' cards. Cards describe links found in studies. None says a style causes an outcome or labels a person.');
 h+=sec('Your tools, all optional')+card(
  rowA({ic:'sliders',title:'Your choices',sub:'Everything below is off or private until you turn it on',go:true},'go','g-learn-choices')+
  (st.reflection!=='off'?rowA({ic:'sun',title:'Where was today',sub:st.reflection==='saved'?'Saved on this phone, only you':'This session only, nothing saved',go:true},'go','g-learn-day'):'')+
  (st.messageCheck?rowA({ic:'letter',title:'Check before you send',sub:'Hints only, nothing stored',go:true},'go','g-learn-check'):'')+
  (st.rulesList?rowA({ic:'list',title:'Rules that match',sub:'Four core categories, read-only for '+pName(),go:true},'go','g-learn-rules'):''));
 return h;});
def('gLAge',function(c,v){U(function(){LS().ageAll=(+v===1);});});
def('gLTopic',function(c,v){U(function(){LS().topic=v;});});

scr('g-learn-choices','Your Learn choices',function(c,g){
 var st=LS().settings;
 return K.banner('pri','Private to you. Every extra is optional, and each starts at the most private choice.','lock')+
  sec('Private reflection')+'<div class="gx-stack" role="radiogroup" aria-label="Reflection">'+opt('Off','No Where was today screen.',st.reflection==='off','gLSet','reflection',{arg2:'off'})+opt('This session only','Kept in memory while this page is open. Nothing is saved.',st.reflection==='session','gLSet','reflection',{arg2:'session'})+opt('Save on this phone','Saved for you only. Not shared, not exported, not visible to '+pName()+'.',st.reflection==='saved','gLSet','reflection',{arg2:'saved'})+'</div>'+
  sec('Cultural framing')+'<div class="gx-stack" role="radiogroup" aria-label="Framing">'+opt('Neutral','Cards as written.',st.framing==='neutral','gLSet','framing',{arg2:'neutral'})+opt('Add a culture note','Style cards add: what this means can differ by family and culture.',st.framing==='culture-note','gLSet','framing',{arg2:'culture-note'})+opt('Values first','Start the page with a question about your own values.',st.framing==='values-first','gLSet','framing',{arg2:'values-first'})+'</div>'+
  sec('Two-home tools')+card(trow({ic:'list',title:'Rules that match',sub:'Share a short list of core rules with '+pName()+'. Off by default.',on:st.rulesList},'gLToggle','rulesList')+trow({ic:'letter',title:'Check before you send',sub:'Hints on a message you are about to write. Nothing is stored or sent. Off by default.',on:st.messageCheck},'gLToggle','messageCheck'))+
  btn('Back to the most private choices','gLReset',null,{kind:'ghost',full:true,ic:'undo'})+
  note('There is no export and no share button for a reflection. A saved note could become evidence in a dispute, so it stays here.');});
L.act('gLSet',function(c,k){G();var v=c.arg2;L.update(function(){LS().settings[k]=v;if(k==='reflection'&&v!=='saved')LS().saved=LS().saved;});});
def('gLToggle',function(c,k){U(function(){var s=LS().settings;s[k]=!s[k];});});
def('gLReset',function(c){U(function(){LS().settings={reflection:'session',framing:'neutral',rulesList:false,messageCheck:false};});toast(c,'Back to the most private choices');});

scr('g-learn-day','Where was today',function(c,g){
 var ls=LS(),st=ls.settings;if(st.reflection==='off')return K.emptyState({spot:'leaf',title:'Turned off',sub:'You chose not to use this. You can turn it on in Your choices.'})+btn('Open your choices','go','g-learn-choices',{full:true,kind:'tonal'});
 var w=g.f.warm==null?50:+g.f.warm,e=g.f.expect==null?50:+g.f.expect,m=describeDay(w,e);
 var saved=ls.saved;
 return K.banner('pri',st.reflection==='saved'?'Saved on this phone for you only.':'This session only. Nothing is saved.','lock')+
  card('<h4>Warmth today</h4><input class="gx-rng" type="range" min="0" max="100" step="5" data-bind="grd.f.warm" value="'+w+'" aria-label="Warmth today, from cooler to warmer"><div class="sld-ends" style="display:flex;justify-content:space-between;font:600 12px var(--font-body,inherit);color:var(--ink3)"><span>Cooler</span><span>Warmer</span></div>'+
   '<h4 style="margin-top:12px">Expectations today</h4><input class="gx-rng" type="range" min="0" max="100" step="5" data-bind="grd.f.expect" value="'+e+'" aria-label="Expectations today, from looser to clearer"><div style="display:flex;justify-content:space-between;font:600 12px var(--font-body,inherit);color:var(--ink3)"><span>Looser</span><span>Clearer</span></div>')+
  '<div class="gx-mirror" role="status"><b>'+E(m.headline)+'</b><p>'+E(m.prompt)+'</p></div>'+
  note('A mirror for the day, not a verdict on you. There is no score and no label. '+rv('needs review'))+
  btn(st.reflection==='saved'?'Keep this on my phone':'Keep for this session','gLKeep',null,{full:true,kind:'tonal',ic:'check'})+
  (st.reflection==='session'&&sessionReflection?card('<h4>This session</h4><p class="gx-sub">'+E(sessionReflection.headline)+'</p>'+btn('Clear it','gLClear',null,{kind:'ghost',size:'sm'})):'')+
  (st.reflection==='saved'&&saved.length?card('<h4>Saved for you</h4>'+saved.slice().reverse().map(function(s,i){var idx=saved.length-1-i;return '<div class="gx-it"><div class="tx"><b>'+E(s.headline)+'</b><small>'+fDY(s.t,myTz())+'</small></div><button type="button" class="gx-rmv" aria-label="Delete this note"'+L.a('gLDel',idx)+'>'+I('trash',18,2)+'</button></div>';}).join('')):'');});
def('gLKeep',function(c){var g=G(),ls=LS(),w=g.f.warm==null?50:+g.f.warm,e=g.f.expect==null?50:+g.f.expect,m=describeDay(w,e);
 U(function(){if(ls.settings.reflection==='saved')ls.saved.push({t:T(),w:w,e:e,headline:m.headline});else sessionReflection={headline:m.headline,w:w,e:e};});toast(c,ls.settings.reflection==='saved'?'Saved for you only':'Kept for this session');});
def('gLClear',function(c){sessionReflection=null;U(function(){});});
def('gLDel',function(c,i){U(function(){LS().saved.splice(+i,1);});});

scr('g-learn-check','Check before you send',function(c,g){
 var st=LS().settings;
 if(!st.messageCheck)return K.emptyState({spot:'envelope',title:'This is off',sub:'It only runs if you turn it on. Nothing is read until then.'})+btn('Open your choices','go','g-learn-choices',{full:true,kind:'tonal'});
 return K.banner('pri','Nothing you type here is stored, sent or logged. It stays on this screen.','lock')+
  '<div class="ff"><label for="gx-check-text">A message you are about to send to '+E(pName())+'</label><div class="fc gx-ta"><textarea id="gx-check-text" rows="6" maxlength="4000" placeholder="Type or paste here">'+E(checkText)+'</textarea></div></div>'+
  card('<h4>Hints '+rv('needs review')+'</h4><div id="gx-check-out" aria-live="polite">'+checkHintsHtml()+'</div>')+
  btn('Clear','gLCheckClear',null,{kind:'ghost',full:true,ic:'trash'})+note('It never rewrites your message and never sends anything. The wording is yours.');});
def('gLCheckClear',function(c){checkText='';U(function(){});});

scr('g-learn-rules','Rules that match',function(c,g){
 var ls=LS(),st=ls.settings;if(!st.rulesList)return K.emptyState({spot:'family',title:'This is off',sub:'Sharing a rules list is your choice. Turn it on in Your choices.'})+btn('Open your choices','go','g-learn-choices',{full:true,kind:'tonal'});
 var mine=shareableRules(st,ls.rules),theirs=shareableRules({rulesList:g.partner.rulesList},g.partner.rules);
 var cat=g.f.rcat||'bedtime';
 var h=K.banner('pri','You share only the core rules you write here. Never a style, a reflection or any setting.','lock');
 h+=card('<h4>Add a rule</h4>'+chips(RULE_CATS.map(function(x){return x.charAt(0).toUpperCase()+x.slice(1);}),cat,'gRCat',RULE_CATS)+'<div style="height:8px"></div>'+inp('grd.f.rtext','The rule, in a few words',{ic:'pencil',enter:'gRAdd',hint:'Up to 200 characters.'})+btn('Add to my list','gRAdd',null,{full:true,kind:'tonal',ic:'plus'}));
 h+=sec('Your list ('+mine.length+')')+card(mine.length?mine.map(function(r,i){return '<div class="gx-it"><div class="tx"><b>'+E(r.text)+'</b><small>'+E(r.category)+'</small></div><button type="button" class="gx-rmv" aria-label="Remove this rule"'+L.a('gRDel',i)+'>'+I('trash',18,2)+'</button></div>';}).join(''):K.empty('list','No rules yet','Add one above. Only these four categories can be shared: bedtime, screens, homework, safety.'));
 h+=sec(pName()+'’s list (read-only)')+card(theirs.length?theirs.map(function(r){return '<div class="gx-it"><div class="tx"><b>'+E(r.text)+'</b><small>'+E(r.category)+'</small></div></div>';}).join(''):K.empty('lock',pName()+' has not shared a list','If they turn it on it appears here. You can’t edit it.'));
 h+=card('<h4>Where they line up</h4>'+RULE_CATS.map(function(k){var a=mine.some(function(r){return r.category===k;}),b=theirs.some(function(r){return r.category===k;});return '<div class="gx-it"><div class="tx"><b>'+k.charAt(0).toUpperCase()+k.slice(1)+'</b><small>'+(a&&b?'Both lists have this. Compare the wording together.':a?'Only your list has this.':b?'Only '+E(pName())+'’s list has this.':'Neither list has this yet.')+'</small></div></div>';}).join('')+note('Low conflict matters more than matching everything. This is a prompt to talk, not a score.'));
 return h;});
def('gRCat',function(c,v){U(function(s,g){g.f.rcat=v;});});
def('gRAdd',function(c){var g=G(),t=fval('rtext'),ls=LS();if(!t){toast(c,'Write the rule first.');return;}if(ls.rules.length>=20){toast(c,'Twenty rules is the most.');return;}
 U(function(){ls.rules.push({category:g.f.rcat||'bedtime',text:t.slice(0,200)});delete g.f.rtext;});});
def('gRDel',function(c,i){U(function(){LS().rules.splice(+i,1);});});
(function(){var bad=lintCards(CARDS);if(bad.length)console.warn('[guardian] Learn content lint:',bad);})();

/* ================================================================================ CARE: emergency card */
function efields(){return EMERG_FIELDS;}
function srvEmerg(by,b){var g=G(),em=g.srv.emerg,bs=b.base;
 if(bs!==em.v){var last=em.hist[em.hist.length-1];return fail(409,'stale_version','The card changed since you opened it',{current:{v:em.v,data:clone(em.data),by:last&&last.by,t:last&&last.t}});}
 var d=b.data||{},ch=[];EMERG_FIELDS.forEach(function(f){var nv=String(d[f[0]]==null?'':d[f[0]]).slice(0,400);if(nv!==em.data[f[0]]){ch.push(f[0]);em.data[f[0]]=nv;}});
 if(!ch.length)return ok({v:em.v,unchanged:true});
 em.v++;em.hist.push({v:em.v,by:by,t:T(),fields:ch,summary:ch.map(function(k){return EMERG_FIELDS.filter(function(f){return f[0]===k;})[0][1];}).join(', ')+' updated',snap:clone(em.data)});
 if(by===gid())notifyPartner(myName()+' updated the emergency card ('+ch.length+' field'+(ch.length===1?'':'s')+').','card');else notifyMe(gName(by)+' updated the emergency card: '+ch.map(function(k){return EMERG_FIELDS.filter(function(f){return f[0]===k;})[0][1];}).join(', ')+'.','card',by);
 return ok({v:em.v});}
L.route('PUT','/v1/emergency-card',function(req){return srvEmerg(gid(),req.body);},{principals:['guardian']});
function mergePlan(emed,theirs){var plan={auto:{},conflicts:[]};EMERG_FIELDS.forEach(function(f){var k=f[0],o=emed.orig[k]||'',m=emed.data[k]||'',t=theirs.data[k]||'';
 if(m===t)plan.auto[k]=m;else if(m===o)plan.auto[k]=t;else if(t===o)plan.auto[k]=m;else plan.conflicts.push(k);});return plan;}
scr('g-emergency','Emergency card',function(c,g){
 var em=g.srv.emerg,ed=g.emed,cf=g.econflict,h='';
 if(cf){var plan=mergePlan(ed,cf.theirs);
  h+=K.notice({tone:'warn',title:(cf.theirs.by?gName(cf.theirs.by):pName())+' saved a newer version first',text:'Version '+cf.theirs.v+' was saved '+(cf.theirs.t?ago(cf.theirs.t):'a moment ago')+'. Nothing of yours was lost. Where you both changed the same thing, pick which to keep.',ic:'warn'});
  h+=plan.conflicts.length?plan.conflicts.map(function(k){var lab=EMERG_FIELDS.filter(function(f){return f[0]===k;})[0][1];var pick=cf.pick[k];return card('<h4>'+E(lab)+'</h4><div class="gx-stack">'+opt('Yours',ed.data[k]||'(empty)',pick==='mine','gPick',k,{arg2:'mine'})+opt((cf.theirs.by?gName(cf.theirs.by):pName())+'\u2019s',cf.theirs.data[k]||'(empty)',pick==='theirs','gPick',k,{arg2:'theirs'})+'</div>');}).join(''):card('<p class="gx-sub">Your changes and '+E(pName())+'\u2019s do not overlap. They can be combined.</p>');
  var all=plan.conflicts.every(function(k){return cf.pick[k];});
  h+=btn('Save the combined card','gMergeSave',null,{full:true,size:'lg',ic:'check',disabled:!all})+btn('Discard my edits','gEmedDiscard',null,{kind:'ghost',full:true});
  return h;}
 if(ed){
  h+=K.banner('pri','Editing version '+ed.base+'. If someone saves first you will be asked how to combine.','pencil');
  EMERG_FIELDS.forEach(function(f){h+=area('grd.emed.data.'+f[0],f[1],{rows:2});});
  h+=btn('Save','gEmedSave',null,{full:true,size:'lg',ic:'check'})+btn('Cancel','gEmedDiscard',null,{kind:'ghost',full:true});return h;}
 var last=em.hist[em.hist.length-1];
 h+=K.banner('warn','Shown to a doctor or sitter on your screen only. It is not sent, and not shared as a link.','eye');
 h+=card('<div style="display:flex;justify-content:space-between;align-items:center"><b class="gx-lead">'+E(cname())+'\u2019s emergency card</b><span class="chip sm">v'+em.v+'</span></div>'+K.kv(EMERG_FIELDS.map(function(f){return [f[1],em.data[f[0]]||'Not filled in'];}),{ruled:true})+'<p class="gx-fine">Last saved '+ago(last.t)+' by '+(last.by===gid()?'you':E(gName(last.by)))+'.</p>');
 h+=btn('Edit the card','gEmedStart',null,{full:true,size:'lg',ic:'pencil'})+btn('Hospital mode','go','g-hospital',{kind:'tonal',full:true,ic:'eye'});
 h+=sec('History (append-only)')+card(em.hist.slice().reverse().map(function(x){return '<div class="gx-it">'+av(x.by,34)+'<div class="tx"><b>v'+x.v+' \u00b7 '+E(x.summary)+'</b><small>'+(x.by===gid()?'You':E(gName(x.by)))+' \u00b7 '+ago(x.t)+'</small>'+(x.snap&&x.v!==em.v?btn('Restore as a new version','gRestoreV',x.v,{kind:'ghost',size:'sm',ic:'undo'}):'')+'</div></div>';}).join(''))+note('Versions are never deleted. Restoring makes a new one.');
 return h;});
def('gEmedStart',function(c){U(function(s,g){g.emed={base:g.srv.emerg.v,orig:clone(g.srv.emerg.data),data:clone(g.srv.emerg.data)};g.econflict=null;});});
def('gEmedDiscard',function(c){U(function(s,g){g.emed=null;g.econflict=null;});});
def('gEmedSave',function(c){var g=G(),ed=g.emed;call(c,'PUT','/v1/emergency-card',{base:ed.base,data:ed.data},function(good,res){
 if(good){U(function(s,gg){gg.emed=null;gg.econflict=null;});toast(c,res.body.unchanged?'Nothing had changed':'Saved as version '+res.body.v);return;}
 if(res.code==='stale_version'){var cur=res.body.error&&res.body.error.current;U(function(s,gg){gg.econflict={theirs:cur,pick:{}};});toast(c,'A newer version exists. Pick how to combine.',{tone:'warn',ic:'warn'});return;}
 toast(c,friendly(res));});});
def('gPick',function(c,k){var v=c.arg2;U(function(s,g){g.econflict.pick[k]=v;});});
def('gMergeSave',function(c){var g=G(),ed=g.emed,cf=g.econflict,plan=mergePlan(ed,cf.theirs);var data={};EMERG_FIELDS.forEach(function(f){var k=f[0];data[k]=plan.auto[k]!==undefined?plan.auto[k]:(cf.pick[k]==='mine'?ed.data[k]:cf.theirs.data[k]);});
 call(c,'PUT','/v1/emergency-card',{base:cf.theirs.v,data:data},function(good,res){if(good){U(function(s,gg){gg.emed=null;gg.econflict=null;});toast(c,'Combined and saved as version '+res.body.v);}else if(res.code==='stale_version'){var cur=res.body.error&&res.body.error.current;U(function(s,gg){gg.econflict={theirs:cur,pick:{}};});toast(c,'It changed again. Pick once more.',{tone:'warn',ic:'warn'});}else toast(c,friendly(res));});});
def('gRestoreV',function(c,v){var g=G(),h=g.srv.emerg.hist.filter(function(x){return x.v===+v;})[0];if(!h)return;call(c,'PUT','/v1/emergency-card',{base:g.srv.emerg.v,data:h.snap},function(good,res){toast(c,good?'Restored as version '+res.body.v:friendly(res));L.queueRender();});});
scr('g-hospital','Hospital mode',function(c,g){var d=g.srv.emerg.data;var meds=g.srv.meds.filter(function(m){return !m.retired;});
 return K.banner('warn','Shown on your screen only. '+rv('needs review'),'eye')+
  '<div class="gx-hosp" role="region" aria-label="Emergency information">'+
  '<h3>Patient</h3><p>'+E(cname())+', age '+child().age+'</p><h3>Allergies</h3><p>'+E(d.allergies||'None recorded')+'</p><h3>Conditions</h3><p>'+E(d.conditions||'None recorded')+'</p>'+
  '<h3>Medicines</h3><p>'+(meds.length?meds.map(function(m){return E(m.name)+' '+E(m.dose)+(m.kind==='prn'?' (as needed)':'');}).join('<br>'):'None')+'</p><h3>Doctor</h3><p>'+E(d.doctor||'Not recorded')+'</p><h3>Call</h3><p>'+E(d.contacts||'Not recorded')+'</p></div>'+
  note('This is what you wrote on the card, as large text. It is not medical advice.');});

/* ================================================================================ CARE: medications */
function slotsFor(m,t){var tz=herTz(),today=ymd(t,tz),out=[];[-1,0,1].forEach(function(dd){m.times.forEach(function(hm){var d=addDays(today,dd).split('-'),h=hmToMin(hm);out.push(zoned(+d[0],+d[1],+d[2],Math.floor(h/60),h%60,tz));});});return out.sort(function(a,b){return a-b;});}
function medState(m,t){t=t==null?T():t;var last=m.doses[m.doses.length-1];
 if(m.kind==='prn'){var next=last?last.t+m.gap*60*MIN:0;return {given:!!last&&t<next,last:last,next:next,due:false};}
 var sl=slotsFor(m,t),past=sl.filter(function(x){return x<=t;}),slot=past.length?past[past.length-1]:null;
 var dose=slot?m.doses.filter(function(d){return d.t>=slot-30*MIN;})[0]:null;
 return {slot:slot,given:!!dose,dose:dose,due:!!slot&&!dose&&t-slot<8*3600000,next:sl.filter(function(x){return x>t;})[0]};}
function medsDue(){return G().srv.meds.filter(function(m){return !m.retired&&medState(m).due;}).length;}
function srvDose(by,id){var g=G(),m=g.srv.meds.filter(function(x){return x.id===id;})[0];if(!m)return fail(404,'not_found','No such medicine');if(m.retired)return fail(409,'retired','This medicine was retired');
 var st=medState(m),t=T();
 if(st.given){var d=m.kind==='prn'?st.last:st.dose;return fail(409,'already_given',m.name+' was already given',{by:d.by,at:d.t,nextAllowed:m.kind==='prn'?st.next:null});}
 m.doses.push({t:t,by:by});if(by===gid())notifyPartner(myName()+' gave '+m.name+' ('+m.dose+') at '+fT(t,herTz())+'.','dose');else notifyMe(gName(by)+' gave '+m.name+' at '+fT(t,herTz())+'.','dose',by);
 return ok({at:t,nextAllowed:m.kind==='prn'?t+m.gap*60*MIN:null});}
L.route('POST','/v1/medications/:id/doses',function(req){return srvDose(gid(),req.params.id);},{principals:['guardian']});
L.route('POST','/v1/medications',function(req){var g=G(),b=req.body||{};if(!String(b.name||'').trim())return fail(422,'validation_failed','A name is needed');
 var times=(b.times||[]).filter(function(x){return /^\d\d:\d\d$/.test(x);});if(b.kind==='scheduled'&&!times.length)return fail(422,'validation_failed','Add at least one time');
 var m={id:uid('m'),name:String(b.name).trim().slice(0,60),dose:String(b.dose||'').slice(0,60),kind:b.kind==='prn'?'prn':'scheduled',times:times,gap:Math.max(1,+b.gap||4),note:String(b.note||'').slice(0,200),retired:false,doses:[]};g.srv.meds.push(m);notifyPartner(myName()+' added '+m.name+' to the medicines.','med');return ok({id:m.id},201);},{principals:['guardian']});
L.route('PATCH','/v1/medications/:id',function(req){var g=G(),m=g.srv.meds.filter(function(x){return x.id===req.params.id;})[0];if(!m)return fail(404,'not_found','No such medicine');var b=req.body||{};
 ['name','dose','note'].forEach(function(k){if(b[k]!=null)m[k]=String(b[k]).slice(0,k==='note'?200:60);});if(b.times)m.times=b.times.filter(function(x){return /^\d\d:\d\d$/.test(x);});if(b.gap)m.gap=Math.max(1,+b.gap);notifyPartner(myName()+' edited '+m.name+'. Past doses are unchanged.','med');return ok({id:m.id});},{principals:['guardian']});
L.route('POST','/v1/medications/:id/retire',function(req){var g=G(),m=g.srv.meds.filter(function(x){return x.id===req.params.id;})[0];if(!m)return fail(404,'not_found','No such medicine');m.retired=true;notifyPartner(myName()+' retired '+m.name+'. Its dose log stays.','med');return ok({id:m.id});},{principals:['guardian']});
scr('g-meds','Medications',function(c,g){var act=g.srv.meds.filter(function(m){return !m.retired;}),ret=g.srv.meds.filter(function(m){return m.retired;});
 var line=function(m){var st=medState(m);var sub=m.kind==='prn'?(st.last?'Last: '+ago(st.last.t)+' by '+(st.last.by===gid()?'you':gName(st.last.by))+(st.given?' \u00b7 next allowed '+fT(st.next,herTz()):' \u00b7 can be given'):'As needed \u00b7 not given yet')
  :(st.given?'Given '+fT(st.dose.t,herTz())+' by '+(st.dose.by===gid()?'you':gName(st.dose.by)):st.due?'Due since '+fT(st.slot,herTz()):'Next '+(st.next?fT(st.next,herTz()):''));
  return rowA({ic:'pill',title:m.name+' \u00b7 '+m.dose,sub:sub,go:true,trail:st.due?K.chip('Due',{tone:'warn',sm:true}):st.given?K.chip('Given',{tone:'ok',sm:true}):''},'gMedOpen',m.id);};
 return K.banner('warn','A record of what a guardian logged, shared by both. It is not medical advice.','pill')+card(act.length?act.map(line).join(''):K.empty('pill','No medicines','Add one to start a shared dose log.'))+
  btn('Add a medicine','gMedNew',null,{kind:'tonal',full:true,ic:'plus'})+
  (ret.length?sec('Retired')+card(ret.map(function(m){return rowA({ic:'pill',title:m.name,sub:'Retired \u00b7 '+m.doses.length+' dose'+(m.doses.length===1?'':'s')+' kept',go:true},'gMedOpen',m.id);}).join('')):'')+
  note('Her time: '+fT(T(),herTz())+'. Doses are shown in her time.');});
def('gMedOpen',function(c,id){U(function(s,g){var m=g.srv.meds.filter(function(x){return x.id===id;})[0];g.medForm={id:id,isNew:false};g.f.med_name=m.name;g.f.med_dose=m.dose;g.f.med_t1=m.times[0]||'';g.f.med_t2=m.times[1]||'';g.f.med_gap=m.gap;g.f.med_note=m.note;});L.go('g','g-med');});
def('gMedNew',function(c){U(function(s,g){g.medForm={id:null,isNew:true,kind:'scheduled'};fclear('med_name','med_dose','med_t1','med_t2','med_gap','med_note');g.f.med_gap=4;});L.go('g','g-med');});
scr('g-med','Medicine',function(c,g){var mf=g.medForm;if(!mf)return K.emptyState({spot:'leaf',title:'Nothing open',sub:'Go back and pick a medicine.'});
 var m=mf.isNew?null:g.srv.meds.filter(function(x){return x.id===mf.id;})[0];var kind=m?m.kind:(mf.kind||'scheduled');var h='';
 if(m&&!m.retired){var st=medState(m);
  h+=card('<span class="t-label">'+E(m.name)+'</span><b class="gx-lead">'+(st.given?(m.kind==='prn'?'Given '+ago(st.last.t)+'. Next allowed '+fT(st.next,herTz()):'Given '+fT(st.dose.t,herTz())+' by '+(st.dose.by===gid()?'you':E(gName(st.dose.by)))):(st.due?'Due since '+fT(st.slot,herTz()):'Can be given'))+'</b><p class="gx-sub">'+(m.kind==='prn'?'At least '+m.gap+' h between doses.':'Daily at '+m.times.map(f12).join(', ')+'.')+'</p>'+btn('Log a dose I just gave','gDose',m.id,{full:true,size:'lg',ic:'check'})+'<p class="gx-fine">If someone already logged it, you will be told who and when. There is no override.</p>');}
 h+=card('<h4>'+(mf.isNew?'New medicine':m&&m.retired?'Retired':'Details')+'</h4>'+inp('grd.f.med_name','Name',{ic:'pill'})+'<div style="height:8px"></div>'+inp('grd.f.med_dose','Dose',{ph:'2 puffs'})+'<div style="height:8px"></div>'+(mf.isNew?seg(['Every day','Only when needed'],kind==='prn'?1:0,'gMedKind',{vals:['scheduled','prn'],label:'Kind'})+'<div style="height:8px"></div>':'')+
  (kind==='scheduled'?inp('grd.f.med_t1','Time',{type:'time',ic:'clock'})+'<div style="height:8px"></div>'+inp('grd.f.med_t2','Second time (optional)',{type:'time'}):inp('grd.f.med_gap','Hours between doses',{type:'number',inputmode:'numeric',min:1,max:24}))+'<div style="height:8px"></div>'+inp('grd.f.med_note','Note',{ph:'With breakfast'}));
 if(!m||!m.retired)h+=btn(mf.isNew?'Add this medicine':'Save changes','gMedSave',null,{full:true,size:'lg',ic:'check'});
 if(m&&!m.retired)h+=btn('Retire this medicine','gMedRetire',m.id,{kind:'ghost',full:true,ic:'x'});
 if(m)h+=sec('Dose log')+card(m.doses.length?m.doses.slice().reverse().map(function(d){return '<div class="gx-it"><div class="tx"><b>'+fT(d.t,herTz())+' on '+fD(d.t,herTz())+'</b><small>Given by '+(d.by===gid()?'you':E(gName(d.by)))+' \u00b7 your time '+fT(d.t,myTz())+'</small></div></div>';}).join(''):'<p class="gx-sub">Nothing logged yet.</p>')+note('The dose log is never edited or deleted. A mistake is explained in a handover note.');
 return h;});
def('gMedKind',function(c,v){U(function(s,g){g.medForm.kind=v;});});
def('gMedSave',function(c){var g=G(),mf=g.medForm,m=mf.isNew?null:g.srv.meds.filter(function(x){return x.id===mf.id;})[0];var kind=m?m.kind:(mf.kind||'scheduled');
 var body={name:g.f.med_name,dose:g.f.med_dose,note:g.f.med_note,kind:kind,times:[g.f.med_t1,g.f.med_t2].filter(Boolean),gap:+g.f.med_gap||4};
 call(c,mf.isNew?'POST':'PATCH',mf.isNew?'/v1/medications':'/v1/medications/'+mf.id,body,function(good,res){if(good){toast(c,mf.isNew?'Added':'Saved');L.back('g');}else toast(c,res.code==='validation_failed'?(res.message||'Check the fields'):friendly(res));L.queueRender();});});
def('gMedRetire',function(c,id){call(c,'POST','/v1/medications/'+id+'/retire',{},function(good,res){toast(c,good?'Retired. Its dose log stays.':friendly(res));L.queueRender();});});
def('gDose',function(c,id){call(c,'POST','/v1/medications/'+id+'/doses',{},function(good,res){
 if(good){toast(c,'Logged. '+pName()+' can see it.');L.queueRender();return;}
 if(res.code==='already_given'){var e=res.body.error||{};openM('dosewarn',{by:e.by,at:e.at,next:e.nextAllowed,name:(g0().srv.meds.filter(function(x){return x.id===id;})[0]||{}).name});return;}
 toast(c,friendly(res));});});
function g0(){return G();}
MODALS.dosewarn=function(c,g,m){return K.modal({ic:'warn',tone:'bad',title:'Already given',body:(m.name||'This')+' was given at '+fT(m.at,herTz())+' on '+fD(m.at,herTz())+' by '+(m.by===gid()?'you':gName(m.by))+'.'+(m.next?' The next dose is allowed from '+fT(m.next,herTz())+'.':'')+' Nothing was logged. If you think it was a mistake, call '+pName()+' and leave a handover note.',actions:btn('Understood','gClose',null,{kind:'pri'}),stack:true}).replace('<div class="scrim">','<div class="scrim" data-act="gClose">');};

/* ================================================================================ CARE: handover notes (append-only, hash-chained) */
function chainCheck(){var ns=G().srv.notes,prev='genesis',bad=-1;for(var i=0;i<ns.length;i++){var n=ns[i];if(n.prev!==prev||n.hash!==fnv(prev+'|'+n.seq+'|'+n.by+'|'+n.t+'|'+n.text)){bad=i;break;}prev=n.hash;}return {ok:bad<0,bad:bad,n:ns.length};}
function srvNote(by,text){var g=G(),ns=g.srv.notes;text=String(text||'').trim();if(!text)return fail(422,'validation_failed','Write something first');if(text.length>1000)return fail(422,'too_long','Up to 1000 characters');
 var prev=ns.length?ns[ns.length-1].hash:'genesis',seq=ns.length+1,t=T();var n={seq:seq,by:by,t:t,text:text,prev:prev,hash:fnv(prev+'|'+seq+'|'+by+'|'+t+'|'+text)};ns.push(n);
 if(by===gid())notifyPartner(myName()+' added handover note #'+seq+'.','note');else notifyMe(gName(by)+' added handover note #'+seq+'.','note',by);return ok({seq:seq,hash:n.hash},201);}
L.route('POST','/v1/handover-notes',function(req){return srvNote(gid(),req.body.text);},{principals:['guardian']});
scr('g-handover','Handover notes',function(c,g){var ns=g.srv.notes,ch=chainCheck(),q=g.noteQueue||[];
 return K.banner('warn','Notes can never be edited or deleted. Both guardians see the same list. To fix a mistake, add a correction.','lock')+
  card('<span class="t-label">Chain</span><b class="gx-lead">'+(ch.ok?I('check',16,2.6)+' Intact, '+ch.n+' note'+(ch.n===1?'':'s'):I('warn',16,2.6)+' Broken at note '+(ch.bad+1))+'</b><p class="gx-sub">Each note carries a fingerprint of the one before it, so a change anywhere would show.</p>')+
  area('grd.f.note','A note for '+pName(),{rows:3,ph:'Ivy had a late snack. Blue bunny is in her bag.',hint:'Up to 1000 characters.'})+
  btn('Review and send','gNoteAsk',null,{full:true,size:'lg',ic:'send'})+
  (q.length?card('<h4>Waiting for a connection</h4>'+q.map(function(x){return '<div class="gx-it"><div class="tx"><b>'+E(x.text)+'</b><small>'+K.status('banked','Banked, will be added in order')+'</small></div></div>';}).join('')):'')+
  sec('The log')+(ns.length?card(ns.slice().reverse().map(function(n){return '<div class="gx-it">'+av(n.by,34)+'<div class="tx"><b>#'+n.seq+' \u00b7 '+E(n.text)+'</b><small>'+(n.by===gid()?'You':E(gName(n.by)))+' \u00b7 her time '+fT(n.t,herTz())+', '+fD(n.t,herTz())+' \u00b7 your time '+fT(n.t,myTz())+'</small><span class="gx-chain">'+I('link',11,2)+' '+n.hash+' after '+n.prev.slice(0,8)+'</span><div>'+btn('Add a correction','gNoteFix',n.seq,{kind:'ghost',size:'sm',ic:'pencil'})+'</div></div></div>';}).join('')):card(K.empty('letter','No notes yet','Notes you both leave about handovers appear here, in order.')));});
def('gNoteAsk',function(c){var g=G();if(!String(g.f.note||'').trim()){toast(c,'Write the note first.');return;}openM('notesend',{});});
MODALS.notesend=function(c,g,m){return K.modal({ic:'lock',title:'This can never be changed',body:'A handover note cannot be edited or deleted by anyone, including you. '+pName()+' will see it. Send it?',actions:btn('Keep editing','gClose',null,{kind:'ghost'})+btn('Send, for good','gNoteSend',null,{kind:'pri'}),stack:true}).replace('<div class="scrim">','<div class="scrim" data-act="gClose">');};
def('gNoteSend',function(c){var g=G(),text=g.f.note;U(function(s,gg){gg.ui.modal=null;});
 call(c,'POST','/v1/handover-notes',{text:text},function(good,res){
  if(good){U(function(s,gg){delete gg.f.note;});toast(c,'Added as note #'+res.body.seq+'.');return;}
  if(res.status===0||res.code==='offline'){U(function(s,gg){gg.noteQueue=(gg.noteQueue||[]).concat([{text:text,t:T()}]);delete gg.f.note;});toast(c,'Banked. It is added in order when you are back online.');return;}
  toast(c,res.code==='validation_failed'||res.code==='too_long'?(res.message||'Check the note'):friendly(res));});});
def('gNoteFix',function(c,seq){U(function(s,g){g.f.note='Correction to note #'+seq+': ';});toast(c,'A correction is a new note. Finish it above.');});
L.on('net:change',function(){L.safe('grd noteQueue',function(){var g=sx().grd;if(!g||!g.noteQueue||!g.noteQueue.length)return;var q=g.noteQueue.slice();g.noteQueue=[];q.forEach(function(x){srvNote(gid(),x.text);});L.queueRender();});});

/* ================================================================================ CARE: schedule viewer/editor, swaps, overlap */
function upcoming(n){var out=[],t=ymd(T(),herTz());for(var i=0;i<n;i++){var d=addDays(t,i);out.push({date:d,house:houseOn(d),prev:houseOn(addDays(d,-1))});}return out;}
function nextExchange(){var up=upcoming(60);for(var i=0;i<up.length;i++)if(up[i].house!==up[i].prev)return up[i];return null;}
scr('g-schedule','Custody schedule',function(c,g){var r=g.fam.rhythm,lock=r.locked,ne=nextExchange(),up=upcoming(14);
 var h=lock?K.banner('info','The weekly rhythm is set by a court order. It is shown here and can\u2019t be edited in Olive Branch.','lock'):'';
 h+=card('<span class="t-label">Weekly rhythm'+(lock?' \u00b7 locked':'')+'</span>'+rhythmBlock(r,false)+'<p class="gx-sub" style="margin-top:8px">'+E(rhythmWords(r))+'. Exchange '+E(exchText())+'.</p>'+(lock?'<p class="gx-fine">Set by order, sample date.</p>':''));
 if(ne)h+=card('<span class="t-label">Next exchange</span><b class="gx-lead">'+fYmd(ne.date)+' to '+E(ne.house==='a'?'Mom\u2019s house':'Dad\u2019s house')+'</b><p class="gx-sub">'+Math.max(0,Math.round((ymdMs(ne.date)-ymdMs(ymd(T(),herTz())))/DAY))+' sleeps. '+E(cname())+' sees her weeks and sleeps, never percentages.</p>');
 h+=card('<h4>Next two weeks</h4>'+up.map(function(d){var ex=g.exceptions.filter(function(x){return x.date===d.date;})[0];return '<div class="gx-it"><div class="tx"><b>'+fYmd(d.date)+'</b><small>'+(d.house==='a'?'Mom\u2019s house':'Dad\u2019s house')+(ex?' \u00b7 '+E(ex.why||'swap'):'')+'</small></div>'+(ex?K.chip('Swap',{tone:'info',sm:true}):'')+'</div>';}).join(''));
 h+=lock?btn('Ask '+pName()+' for a swap','go','g-swap',{kind:'tonal',full:true,ic:'swap'})+note('A swap is a one-off agreement between you. It does not change the order.'):btn('Edit the rhythm','gEditRhythm',null,{full:true,size:'lg',ic:'pencil'})+btn('Ask for a swap','go','g-swap',{kind:'tonal',full:true,ic:'swap'})+note('Changes go through the preview and your timing choice, and '+E(pName())+' sees them.');
 return h;});
def('gEditRhythm',function(c){U(function(s,g){draft();g.ui.fstep=3;});L.go('g','g-family');});

function srvSwap(by,b){var g=G(),t=ymd(T(),herTz());if(!b.date||b.date<=t)return fail(422,'date_in_past','Pick tomorrow or later');if(b.date>addDays(t,365))return fail(422,'date_out_of_range','Up to a year ahead');
 if(b.ret&&(b.ret<=t||b.ret===b.date))return fail(422,'date_in_past','The return night must be a different future night');
 if(g.srv.swaps.some(function(x){return x.state==='pending'&&x.date===b.date;}))return fail(409,'conflict','A swap for that night is already waiting');
 var sw={id:uid('sw'),by:by,date:b.date,ret:b.ret||null,note:String(b.note||'').slice(0,200),state:'pending',t:T(),from:houseOn(b.date)};g.srv.swaps.push(sw);
 var txt=gName(by)+' asked to swap '+fYmd(sw.date)+(sw.ret?' and give back '+fYmd(sw.ret):'')+'.';if(by===gid())notifyPartner(txt,'swap');else notifyMe(txt,'swap',by);
 if(by===gid()){var id=sw.id;L.after(5*MIN,function(){L.safe('grd bot swap',function(){var s2=G().srv.swaps.filter(function(x){return x.id===id;})[0];if(s2&&s2.state==='pending'){var soon=ymdMs(s2.date)-ymdMs(ymd(T(),herTz()))<3*DAY;srvSwapRespond(pid(),id,{accept:!soon,note:soon?'That is too soon for me, sorry.':'Works for me.'});L.queueRender();}});},'bot-swap');}
 return ok({id:sw.id},201);}
function srvSwapRespond(by,id,b){var g=G(),sw=g.srv.swaps.filter(function(x){return x.id===id;})[0];if(!sw)return fail(404,'not_found','No such swap');if(sw.state!=='pending')return fail(409,'not_pending','Already answered');
 if(b.withdraw){if(sw.by!==by)return fail(403,'forbidden','Only the person who asked can withdraw');sw.state='withdrawn';return ok({state:sw.state});}
 if(sw.by===by)return fail(403,'cannot_respond_own','You can\u2019t answer your own request');
 sw.answeredBy=by;sw.answerNote=String(b.note||'').slice(0,200);sw.state=b.accept?'accepted':'declined';sw.answeredAt=T();
 if(b.accept){var flip=function(d){return houseOn(d)==='a'?'b':'a';};g.exceptions.push({date:sw.date,house:flip(sw.date),why:'Swap agreed with '+gName(sw.by===gid()?pid():sw.by),swap:sw.id});if(sw.ret)g.exceptions.push({date:sw.ret,house:flip(sw.ret),why:'Returned swap',swap:sw.id});
  var k=kg();k.rev=(k.rev||0)+1;k.exceptions=clone(g.exceptions);L.emit('grd:published',{key:'exceptions'});}
 var txt=gName(by)+(b.accept?' accepted':' declined')+' the swap for '+fYmd(sw.date)+'.';if(by===gid())notifyPartner(txt,'swap');else notifyMe(txt,'swap',by);return ok({state:sw.state});}
L.route('POST','/v1/swaps',function(req){return srvSwap(gid(),req.body);},{principals:['guardian']});
L.route('POST','/v1/swaps/:id/respond',function(req){return srvSwapRespond(gid(),req.params.id,req.body||{});},{principals:['guardian']});
scr('g-swap','Swap a night',function(c,g){var me=gid(),sw=g.srv.swaps.slice().reverse();var incoming=sw.filter(function(x){return x.state==='pending'&&x.by!==me;}),outgoing=sw.filter(function(x){return x.state==='pending'&&x.by===me;}),done=sw.filter(function(x){return x.state!=='pending';});
 var up=upcoming(30).slice(1);var sel=g.f.swdate||'',ret=g.f.swret||'';
 var h='';
 incoming.forEach(function(x){h+=card('<span class="t-label">'+E(gName(x.by))+' asks</span><b class="gx-lead">Swap '+fYmd(x.date)+(x.ret?' and return '+fYmd(x.ret):'')+'</b><p class="gx-sub">'+cname()+' would sleep at '+(houseOn(x.date)==='a'?'Dad\u2019s':'Mom\u2019s')+' house instead.'+(x.note?' \u201c'+E(x.note)+'\u201d':'')+'</p><div class="gx-actions">'+btn('Accept','gSwapAns',x.id,{ic:'check'},'1')+btn('Decline','gSwapAns',x.id,{kind:'ghost',ic:'x'},'0')+'</div>');});
 outgoing.forEach(function(x){h+=card('<span class="t-label">Waiting for '+E(pName())+'</span><b class="gx-lead">'+fYmd(x.date)+(x.ret?' and '+fYmd(x.ret):'')+'</b><p class="gx-sub">You can\u2019t answer your own request. '+E(pName())+' will see it.</p>'+btn('Withdraw','gSwapWd',x.id,{kind:'ghost',size:'sm'}));});
 h+=card('<h4>Ask for a swap</h4><p class="gx-sub">Pick a night to flip. '+E(cname())+' would sleep at the other home that night.</p>'+chips(up.slice(0,14).map(function(d){return fYmd(d.date).replace(/,/g,'')+' '+(d.house==='a'?'(Mom)':'(Dad)');}),sel,'gSwapPick',up.slice(0,14).map(function(d){return d.date;}))+
  (sel?'<p class="gx-fine">Optional: a night to give back.</p>'+chips(up.filter(function(d){return d.date!==sel;}).slice(0,14).map(function(d){return fYmd(d.date).replace(/,/g,'');}),ret,'gSwapRet',up.filter(function(d){return d.date!==sel;}).slice(0,14).map(function(d){return d.date;})):'')+
  '<div style="height:8px"></div>'+inp('grd.f.swnote','A line for '+pName()+' (optional)',{ic:'chat'})+btn('Send the request','gSwapSend',null,{full:true,ic:'send',disabled:!sel}));
 if(done.length)h+=sec('Earlier')+card(done.map(function(x){return '<div class="gx-it"><div class="tx"><b>'+fYmd(x.date)+(x.ret?' + '+fYmd(x.ret):'')+'</b><small>'+E(gName(x.by))+' asked \u00b7 '+(x.state==='accepted'?'Accepted, on the calendar':x.state==='declined'?'Declined'+(x.answerNote?': '+E(x.answerNote):''):'Withdrawn')+'</small></div></div>';}).join(''));
 return h+note('When one of you accepts, the night lands on the calendar and in the schedule. The proposer can\u2019t accept their own request.');});
def('gSwapPick',function(c,d){U(function(s,g){g.f.swdate=g.f.swdate===d?'':d;});});
def('gSwapRet',function(c,d){U(function(s,g){g.f.swret=g.f.swret===d?'':d;});});
def('gSwapSend',function(c){var g=G();call(c,'POST','/v1/swaps',{date:g.f.swdate,ret:g.f.swret,note:g.f.swnote},function(good,res){if(good){U(function(s,gg){fclear('swdate','swret','swnote');});toast(c,'Sent. '+pName()+' will answer.');}else toast(c,res.code==='date_in_past'?'Pick tomorrow or later.':res.code==='conflict'?'A swap for that night is already waiting.':friendly(res));L.queueRender();});});
def('gSwapAns',function(c,id){var acc=c.arg2==='1';call(c,'POST','/v1/swaps/'+id+'/respond',{accept:acc},function(good,res){toast(c,good?(acc?'Accepted. It is on the calendar.':'Declined.'):(res.code==='cannot_respond_own'?'You can\u2019t answer your own request.':friendly(res)));L.queueRender();});});
def('gSwapWd',function(c,id){call(c,'POST','/v1/swaps/'+id+'/respond',{withdraw:true},function(good,res){toast(c,good?'Withdrawn':friendly(res));L.queueRender();});});

/* overlap windows: her time / your time */
function awakeWindowMine(){ /* minutes in MY local day when both of us are in 07:00-21:00 */
 var t=T(),mine=tzOff(t,myTz()),his=tzOff(t,pTz()),d=(his-mine)/MIN; /* partner clock = my clock + d */
 var a=Math.max(7*60,7*60-d),b=Math.min(21*60,21*60-d);return b>a?[a,b]:null;}
scr('g-overlap','Her time, your time',function(c,g){var t=T(),her=herTz(),mine=myTz(),win=awakeWindowMine();
 var now=parts(t,mine),nowPct=((now.h*60+now.mi)/1440*100).toFixed(1);var ne=nextExchange();
 var up=upcoming(35),today=ymd(t,her),tp=today.split('-');var marks={};up.forEach(function(d){var p=d.date.split('-');if(+p[1]===+tp[1])marks[+p[2]]=d.house;});
 g.exceptions.forEach(function(x){var p=x.date.split('-');if(+p[1]===+tp[1])marks[+p[2]]='ev';});
 var hm=function(m){var h=Math.floor(m/60),mi=m%60;return (h%12||12)+(mi?':'+('0'+mi).slice(-2):'')+' '+(h<12?'AM':'PM');};
 return '<div class="dual" role="group" aria-label="Her time and your time"><div class="d1"><small>'+E(cname())+', her time</small><b>'+fT(t,her)+'</b><span>'+E(L.tzName?L.tzName(her):her)+'</span></div><div class="d2"><small>You, your time</small><b>'+fT(t,mine)+'</b><span>'+E(L.tzName?L.tzName(mine):mine)+(her===mine?' \u00b7 same':'')+'</span></div></div>'+
  card('<span class="t-label">When you can both talk (your time)</span>'+K.ribbon({now:+nowPct,overlap:win?[(win[0]/1440*100).toFixed(1),((win[1]-win[0])/1440*100).toFixed(1)]:null})+'<p class="gx-sub">'+(win?'Both awake, 7 AM to 9 PM each, from '+hm(win[0])+' to '+hm(win[1])+' your time. The green band on the ribbon.':'No shared waking hours.')+'</p>')+
  (ne?K.stat({label:'Next exchange',value:String(Math.max(0,Math.round((ymdMs(ne.date)-ymdMs(today))/DAY))),unit:'sleeps',note:fYmd(ne.date)+' \u00b7 '+exchText(),ic:'calendar'}):'')+
  card('<span class="t-label">This month</span>'+K.calMonth({y:+tp[0],m:+tp[1]-1,today:+tp[2],marks:marks,names:{a:'Mom\u2019s house',b:'Dad\u2019s house'}})+'<p class="gx-fine">Shape and tint show whose house. A dotted day is a swap.</p>')+
  rowA({ic:'calendar',title:'Custody schedule',go:true},'go','g-schedule');});

/* ================================================================================ CARE: expenses (records only; never visible to the child) */
function money(c){return '$'+(c/100).toFixed(2);}
function srvExp(by,b){var g=G(),cents=Math.round(parseFloat(b.amount)*100);if(!String(b.title||'').trim())return fail(422,'validation_failed','Say what it was for');if(!(cents>0)||cents>1000000)return fail(422,'validation_failed','Amount looks wrong');
 var e={id:uid('ex'),by:by,title:String(b.title).trim().slice(0,80),cents:cents,t:T(),state:'proposed',log:[{t:T(),by:by,what:'proposed'}]};g.srv.exp.push(e);
 var txt=gName(by)+' proposed an expense: '+e.title+', '+money(cents)+'.';if(by===gid())notifyPartner(txt,'expense');else notifyMe(txt,'expense',by);return ok({id:e.id},201);}
function srvExpAct(by,id,what,b){var g=G(),e=g.srv.exp.filter(function(x){return x.id===id;})[0];if(!e)return fail(404,'not_found','No such expense');
 if(what==='accept'){if(e.by===by)return fail(403,'cannot_accept_own','You can\u2019t accept your own expense');if(e.state!=='proposed'&&e.state!=='disputed')return fail(409,'not_pending','Already settled');e.state='accepted';}
 else if(what==='dispute'){if(e.by===by)return fail(403,'cannot_dispute_own','You can\u2019t dispute your own expense');if(e.state!=='proposed')return fail(409,'not_pending','Already settled');if(!String(b.reason||'').trim())return fail(422,'validation_failed','Say briefly why');e.state='disputed';e.reason=String(b.reason).slice(0,200);}
 else if(what==='reimburse'){if(e.by!==by)return fail(403,'forbidden','Only the person who paid can mark it reimbursed');if(e.state!=='accepted')return fail(409,'not_pending','Accept it first');e.state='reimbursed';}
 e.log.push({t:T(),by:by,what:what});var txt=gName(by)+' '+(what==='accept'?'accepted':what==='dispute'?'disputed':'marked reimbursed')+': '+e.title+'.';if(by===gid())notifyPartner(txt,'expense');else notifyMe(txt,'expense',by);return ok({state:e.state});}
L.route('POST','/v1/expenses',function(req){return srvExp(gid(),req.body);},{principals:['guardian']});
L.route('POST','/v1/expenses/:id/accept',function(req){return srvExpAct(gid(),req.params.id,'accept',req.body||{});},{principals:['guardian']});
L.route('POST','/v1/expenses/:id/dispute',function(req){return srvExpAct(gid(),req.params.id,'dispute',req.body||{});},{principals:['guardian']});
L.route('POST','/v1/expenses/:id/reimburse',function(req){return srvExpAct(gid(),req.params.id,'reimburse',req.body||{});},{principals:['guardian']});
scr('g-expenses','Shared expenses',function(c,g){var me=gid(),list=g.srv.exp.slice().reverse();var open=g.srv.exp.filter(function(e){return e.state==='accepted';}).reduce(function(s,e){return s+(e.by===me?e.cents/2:-e.cents/2);},0);
 var h=K.banner('pri','Olive Branch keeps the record only. It never moves money, and '+cname()+' can\u2019t see any of this.','receipt');
 h+=card('<span class="t-label">Accepted, not yet reimbursed</span><b class="gx-lead">'+(open===0?'Even':(open>0?E(pName())+' owes you ':'You owe '+E(pName())+' ')+money(Math.abs(open)))+'</b><p class="gx-sub">Half each. A record, not a bill.</p>');
 h+=card('<h4>Propose an expense</h4>'+inp('grd.f.extitle','What it was for',{ic:'receipt',ph:'School shoes'})+'<div style="height:8px"></div>'+inp('grd.f.examt','Amount',{type:'number',inputmode:'decimal',ph:'48.00'})+btn('Propose it','gExpSend',null,{full:true,kind:'tonal',ic:'plus'})+'<p class="gx-fine">'+E(pName())+' decides. You can\u2019t accept your own.</p>');
 h+=list.length?list.map(function(e){var mineE=e.by===me,st={proposed:'Waiting for '+(mineE?pName():'you'),accepted:'Accepted',disputed:'Disputed'+(e.reason?': '+e.reason:''),reimbursed:'Reimbursed'}[e.state];
  return card('<div style="display:flex;justify-content:space-between;gap:8px"><div><b class="gx-lead">'+E(e.title)+'</b><p class="gx-sub">'+money(e.cents)+' \u00b7 proposed by '+(mineE?'you':E(gName(e.by)))+' \u00b7 '+ago(e.t)+'</p></div>'+K.chip(e.state==='reimbursed'?'Reimbursed':e.state==='accepted'?'Accepted':e.state==='disputed'?'Disputed':'Proposed',{tone:e.state==='accepted'||e.state==='reimbursed'?'ok':e.state==='disputed'?'bad':'info',sm:true})+'</div><p class="gx-fine">'+E(st)+'</p>'+
   (e.state==='proposed'&&!mineE?'<div class="gx-actions">'+btn('Accept','gExpAct',e.id,{ic:'check'},'accept')+btn('Dispute','gExpDisp',e.id,{kind:'ghost',ic:'flag'})+'</div>':'')+
   (e.state==='disputed'&&!mineE?btn('Accept after all','gExpAct',e.id,{kind:'tonal',size:'sm'},'accept'):'')+
   (e.state==='accepted'&&mineE?btn('Mark reimbursed','gExpAct',e.id,{kind:'tonal',size:'sm',ic:'check'},'reimburse'):'')+
   (g.ui.disputing===e.id?inp('grd.f.exreason','Why? (brief and factual)',{enter:'gExpDispGo'})+btn('Send dispute','gExpDispGo',e.id,{kind:'danger',full:true}):''));}).join(''):K.emptyState({spot:'envelope',title:'No expenses yet',sub:'Propose one above. The other guardian accepts or disputes it.'});
 return h;});
def('gExpSend',function(c){var g=G();call(c,'POST','/v1/expenses',{title:g.f.extitle,amount:g.f.examt},function(good,res){if(good){U(function(s,gg){fclear('extitle','examt');});toast(c,'Proposed. '+pName()+' decides.');}else toast(c,res.code==='validation_failed'?(res.message||'Check the fields'):friendly(res));L.queueRender();});});
def('gExpAct',function(c,id){var what=c.arg2;call(c,'POST','/v1/expenses/'+id+'/'+what,{},function(good,res){toast(c,good?'Done':(res.code==='cannot_accept_own'?'You can\u2019t accept your own expense.':friendly(res)));L.queueRender();});});
def('gExpDisp',function(c,id){U(function(s,g){g.ui.disputing=g.ui.disputing===id?null:id;});});
def('gExpDispGo',function(c,id){var g=G();id=id||g.ui.disputing;call(c,'POST','/v1/expenses/'+id+'/dispute',{reason:g.f.exreason},function(good,res){if(good){U(function(s,gg){gg.ui.disputing=null;fclear('exreason');});toast(c,'Dispute sent');}else toast(c,res.code==='validation_failed'?'Say briefly why.':friendly(res));L.queueRender();});});

/* ================================================================================ THE BOT'S REPERTOIRE */
function botDo(k){var g=G(),P=pName(),by=pid(),r;
 switch(k){
  case 'card':{var em=g.srv.emerg,d=clone(em.data);d.doctor=d.doctor.indexOf('(new number')>=0?'Dr. Okafor, Lakeview Pediatrics 555-0142':d.doctor+' (new number 555-0177)';d.notes=d.notes.indexOf('Spare inhaler')>=0?'Blue inhaler is in the front pocket of her school bag.':d.notes+' Spare inhaler is at Dad\u2019s house.';
   r=srvEmerg(by,{base:em.v,data:d});return {msg:P+' saved the emergency card as version '+em.v+'.'};}
  case 'dose':{var m=g.srv.meds.filter(function(x){return x.id==='m2'&&!x.retired;})[0]||g.srv.meds.filter(function(x){return !x.retired;})[0];if(!m)return {msg:'No active medicine.'};r=srvDose(by,m.id);return {msg:r.status===200?P+' logged '+m.name+'.':P+' tried to log '+m.name+' but it was already given.'};}
  case 'swapAsk':{var up=upcoming(30).slice(5);var pick=up.filter(function(d){return d.house==='a'&&pid()==='dad'||d.house==='b'&&pid()==='mom';})[0]||up[0];r=srvSwap(by,{date:pick.date,note:'Could we swap this one? I have a work trip.'});return {msg:r.status===201?P+' asked to swap '+fYmd(pick.date)+'.':'Could not ask: '+(r.body.error&&r.body.error.message)};}
  case 'swapYes':case 'swapNo':{var sw=g.srv.swaps.filter(function(x){return x.state==='pending'&&x.by===gid();})[0];if(!sw)return {msg:'You have no swap waiting for '+P+'.'};r=srvSwapRespond(by,sw.id,{accept:k==='swapYes',note:k==='swapYes'?'Works for me.':'I can\u2019t that night, sorry.'});return {msg:P+(k==='swapYes'?' accepted':' declined')+' your swap.'};}
  case 'exp':{r=srvExp(by,{title:'Swimming lessons',amount:'60.00'});return {msg:P+' proposed an expense.'};}
  case 'expYes':{var e=g.srv.exp.filter(function(x){return x.by===gid()&&(x.state==='proposed'||x.state==='accepted');})[0];if(!e)return {msg:'You have no expense waiting for '+P+'.'};r=srvExpAct(by,e.id,e.state==='proposed'?'accept':'reimburse',{});return {msg:r.status===200?P+' accepted your expense.':'Only the person who paid can mark it reimbursed: '+(r.body.error&&r.body.error.message)};}
  case 'note':{r=srvNote(by,'Ivy ate dinner at 6. She is tired, so earlier bed would help. Blue bunny is in the green bag.');return {msg:P+' added a handover note.'};}
  case 'daily':{var nh=Math.min(3,g.srv.dailyH+1);if(nh===g.srv.dailyH)return {msg:'Daily time is already at the top (3 h).'};g.srv.dailyBy=P+' raised this from '+g.srv.dailyH+' h to '+nh+' h at '+fT(T(),myTz())+'.';notifyMe(P+' raised daily time from '+g.srv.dailyH+' h to '+nh+' h. It is a notice, not a request.','daily',by);g.srv.dailyH=nh;kg().dailyH=nh;L.emit('grd:published',{key:'dailyH'});return {msg:P+' raised daily time to '+nh+' h.'};}
  case 'pace':{r=srvCtl(by,{tile:'games',pace:60});return {msg:P+' paced Games to 1 hour.'};}
  case 'hideMsg':{r=srvCtl(by,{tile:'messages',hidden:true});return {msg:r.status===403?'The server refused: Messages can never be hidden.':'Unexpected.',};}
  case 'revoke':{r=fail(403,'not_your_device','Only the guardian who paired a device can remove it');return {msg:'The server refused: '+P+' can\u2019t remove your device.'};}
  case 'fam':{var d2=clone(g.fam);if(!d2.people.some(function(p){return p.id==='gpa';})){d2.people.push({id:'gpa',name:'Grandpa',role:'Relative',home:'',away:false,reach:{messages:false,calls:true,story:false}});}else d2.people=d2.people.filter(function(p){return p.id!=='gpa';});
   r=srvFamChange(by,{draft:d2,baseV:g.famV||0,mode:'now',note:''});return {msg:r.status===200?P+' changed '+cname()+'\u2019s people. Your open draft (if any) is now out of date.':'Could not change: '+(r.body.error&&r.body.error.message)};}
  case 'revokeOwn':{if(g.otherDevices<1)return {msg:P+' has no devices left.'};g.otherDevices--;notifyMe(P+' removed one of their own devices.','device',by);return {msg:P+' removed one of their devices.'};}
 }
 return {msg:'Done'};}

/* ================================================================================ BINDER, APPOINTMENTS, BAG */
scr('g-binder','Care binder',function(c,g){
 return K.banner('pri','Pages you write for yourselves and for a sitter you choose to show them to. Only guardians see this. It is shown on screen, never sent.','file')+
  g.binder.map(function(p){return card('<div style="display:flex;justify-content:space-between;gap:8px"><b class="gx-lead">'+E(p.title)+'</b><button type="button" class="gx-rmv" aria-label="Remove page '+E(p.title)+'"'+L.a('gBinderDel',p.id)+'>'+I('trash',18,2)+'</button></div><p class="gx-sub" style="white-space:pre-wrap">'+E(p.body)+'</p>');}).join('')+
  card('<h4>New page</h4>'+inp('grd.f.bn_title','Title',{ic:'file'})+'<div style="height:8px"></div>'+area('grd.f.bn_body','What goes on it',{rows:3})+btn('Add the page','gBinderAdd',null,{full:true,kind:'tonal',ic:'plus'}));});
def('gBinderAdd',function(c){var g=G(),t=fval('bn_title'),b=fval('bn_body');if(!t){toast(c,'Give the page a title.');return;}U(function(){g.binder.push({id:uid('bp'),title:t.slice(0,60),body:b.slice(0,800)});fclear('bn_title','bn_body');});});
def('gBinderDel',function(c,id){U(function(s,g){g.binder=g.binder.filter(function(p){return p.id!==id;});});});
function splitList(s){return String(s||'').split(/[;\n]/).map(function(x){return x.trim();}).filter(Boolean).slice(0,12).map(function(t){return {t:t.slice(0,100),done:false};});}
scr('g-appt','Appointment prep',function(c,g){
 return K.banner('pri','A short list for each visit. Separate items with a semicolon.','calendar')+
  (g.appts.length?g.appts.map(function(a){return card('<div style="display:flex;justify-content:space-between;gap:8px"><div><b class="gx-lead">'+E(a.what)+'</b><p class="gx-sub">'+(a.when?fYmd(a.when):'No date yet')+'</p></div><button type="button" class="gx-rmv" aria-label="Remove '+E(a.what)+'"'+L.a('gApptDel',a.id)+'>'+I('trash',18,2)+'</button></div>'+
   (a.qs.length?'<h5 style="margin-top:8px">Questions to ask</h5>'+a.qs.map(function(q,i){return A('<div class="row">'+K.check(q.done)+'<span class="rtxt"><b style="'+(q.done?'text-decoration:line-through;color:var(--ink3)':'')+'">'+E(q.t)+'</b></span></div>','gApptTick',a.id,'qs:'+i);}).join(''):'')+
   (a.bring.length?'<h5 style="margin-top:8px">Bring</h5>'+a.bring.map(function(q,i){return A('<div class="row">'+K.check(q.done)+'<span class="rtxt"><b style="'+(q.done?'text-decoration:line-through;color:var(--ink3)':'')+'">'+E(q.t)+'</b></span></div>','gApptTick',a.id,'bring:'+i);}).join(''):''));}).join(''):K.emptyState({spot:'leaf',title:'No visits planned',sub:'Add one to keep your questions in one place.'}))+
  card('<h4>New visit</h4>'+inp('grd.f.ap_what','What is it?',{ic:'calendar',ph:'Dentist check-up'})+'<div style="height:8px"></div>'+inp('grd.f.ap_when','Date',{type:'date'})+'<div style="height:8px"></div>'+inp('grd.f.ap_qs','Questions to ask',{ph:'Is the cough normal; Next check-up?'})+'<div style="height:8px"></div>'+inp('grd.f.ap_bring','Bring',{ph:'Insurance card; Blue bunny'})+btn('Add the visit','gApptAdd',null,{full:true,kind:'tonal',ic:'plus'}));});
def('gApptAdd',function(c){var g=G(),w=fval('ap_what');if(!w){toast(c,'Say what the visit is.');return;}U(function(){g.appts.push({id:uid('ap'),what:w.slice(0,60),when:fval('ap_when'),qs:splitList(fval('ap_qs')),bring:splitList(fval('ap_bring'))});fclear('ap_what','ap_when','ap_qs','ap_bring');});});
def('gApptDel',function(c,id){U(function(s,g){g.appts=g.appts.filter(function(a){return a.id!==id;});});});
def('gApptTick',function(c,id){var p=String(c.arg2).split(':');U(function(s,g){var a=g.appts.filter(function(x){return x.id===id;})[0];if(a)a[p[0]][+p[1]].done=!a[p[0]][+p[1]].done;});});

/* ---- generic authored-content helpers (publish through the server) */
function curVal(key){var g=G();if(key==='packing'&&!pending(key)&&kg().packing)return clone(kg().packing);return clone(g.content[key]!==undefined?g.content[key]:kg()[key]);}
function curList(key){var v=curVal(key);return Array.isArray(v)?v:[];}
function curObj(key){var v=curVal(key);return v&&typeof v==='object'&&!Array.isArray(v)?v:{};}
function listBlock(g,key,cfg){var items=curList(key);
 var h='<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><h4 style="margin:0">'+E(cfg.title)+'</h4>'+sentTag(key)+'</div>'+(cfg.help?'<p class="gx-sub">'+E(cfg.help)+'</p>':'');
 h+=items.length?items.map(function(it,i){var main=it[cfg.fields[0].k],sub=cfg.fields.slice(1).map(function(f){return it[f.k];}).filter(Boolean).join(' · ');
  return '<div class="gx-it"><div class="tx"><b>'+E(main)+'</b>'+(sub?'<small>'+E(sub)+'</small>':'')+'</div><button type="button" class="gx-rmv" aria-label="Remove '+E(main)+'"'+L.a('gListDel',key,i)+'>'+I('trash',18,2)+'</button></div>';}).join(''):'<p class="gx-fine">'+E(cfg.empty||'Nothing yet.')+'</p>';
 h+='<div style="margin-top:8px">'+cfg.fields.map(function(f,i){return (i?'<div style="height:8px"></div>':'')+inp('grd.f.'+key+'_'+f.k,f.label,{type:f.type||'text',ph:f.ph,enter:i===cfg.fields.length-1?'gListAdd|'+key:undefined});}).join('')+'<div style="height:8px"></div>'+btn('Add','gListAdd',key,{kind:'tonal',full:true,ic:'plus'})+'</div>';
 return card(h);}
def('gListAdd',function(c,key){var cfg=LISTCFG[key];if(!cfg)return;var g=G(),it={};cfg.fields.forEach(function(f){it[f.k]=fval(key+'_'+f.k).slice(0,120);});
 if(!it[cfg.fields[0].k]){toast(c,'Fill in "'+cfg.fields[0].label+'" first.');return;}
 var list=curList(key);if(list.length>=(cfg.max||30)){toast(c,'That is the most this list holds.');return;}
 if(key==='packing')it.packed=false;list.push(it);U(function(){cfg.fields.forEach(function(f){delete g.f[key+'_'+f.k];});g.content[key]=clone(list);});publish(c,key,list,'Added. It reaches '+cname()+'’s tablet in a moment.');});
def('gListDel',function(c,key){var i=+c.arg2;var list=curList(key);list.splice(i,1);U(function(s,g){g.content[key]=clone(list);});publish(c,key,list,'Removed');});
var LISTCFG={
 routine:{title:'Daily routine',help:'Appears as picture steps on her tablet, in this order.',fields:[{k:'text',label:'Step',ph:'Brush teeth'},{k:'time',label:'Time (optional)',ph:'7:15'}],empty:'No steps yet.'},
 firstThen:{title:'First, then',help:'Two pictures: what comes first, and what comes next.',fields:[{k:'first',label:'First',ph:'Shoes on'},{k:'then',label:'Then',ph:'Park'}],empty:'No pairs yet.'},
 packing:{title:'Packing buddy',help:'The things that travel between homes. She ticks them off on her tablet.',fields:[{k:'text',label:'Item',ph:'Blue bunny'}],empty:'No items yet.',max:30},
 newPlace:{title:'New place stories',help:'What she can expect somewhere new. Written by you.',fields:[{k:'place',label:'Where',ph:'The dentist'},{k:'note',label:'What to expect',ph:'A big chair that goes up and down'}],empty:'No places yet.'},
 helpers:{title:'My helpers',help:'People and what each one helps with. She sees a face and a job.',fields:[{k:'name',label:'Who',ph:'Ms. Rivera'},{k:'what',label:'Helps with',ph:'Class questions'}],empty:'No helpers yet.'},
 symbols:{title:'Symbols',help:'Words that appear with a picture and are read aloud.',fields:[{k:'label',label:'Word',ph:'Drink'},{k:'word',label:'Said aloud',ph:'I would like a drink, please'}],empty:'No symbols yet.'},
 capsule:{title:'Time capsule',help:'A note she can open on a date you choose. It stays sealed until then.',fields:[{k:'text',label:'The note',ph:'I was so proud of you today'},{k:'openOn',label:'Open on',type:'date'}],empty:'No notes sealed yet.'},
 firstTimes:{title:'First times',help:'Things she did for the first time, in your words.',fields:[{k:'text',label:'What happened',ph:'Rode a bike without help'},{k:'date',label:'When',type:'date'}],empty:'No firsts yet.'},
 marks:{title:'Growing marks',help:'Height, shoe size, anything you measure. No comparison with anyone else.',fields:[{k:'label',label:'What',ph:'Height'},{k:'value',label:'How much',ph:'112 cm'},{k:'date',label:'When',type:'date'}],empty:'No marks yet.'},
 poorly:{title:'When I feel poorly',help:'Things that help her. She sees them as pictures and short words.',fields:[{k:'text',label:'What helps',ph:'A warm drink'}],empty:'Nothing yet.'},
 visit:{title:'A doctor visit, step by step',help:'A short story of what happens, so it feels less new.',fields:[{k:'text',label:'A step',ph:'We wait in the waiting room'}],empty:'No steps yet.'}};
function flagsBlock(g,key,title,help,items,reviewed){var o=curObj(key);
 return card('<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><h4 style="margin:0">'+E(title)+(reviewed?' '+rv('needs review'):'')+'</h4>'+sentTag(key)+'</div>'+(help?'<p class="gx-sub">'+E(help)+'</p>':'')+items.map(function(it){return trow({ic:it[3]||'sliders',title:it[1],sub:it[2],on:!!o[it[0]]},'gFlag',key,it[0]);}).join(''));}
def('gFlag',function(c,key){var k=c.arg2;var o=curObj(key);o[k]=!o[k];U(function(s,g){g.content[key]=clone(o);});publish(c,key,o);});
function boolBlock(g,key,title,sub,reviewed){var v=!!curVal(key);return card(trow({ic:'smile',title:title+(reviewed?'':''),sub:sub,on:v},'gBool',key)+(reviewed?'<div style="margin-top:6px">'+rv('needs review')+' '+sentTag(key)+'</div>':'<div style="margin-top:6px">'+sentTag(key)+'</div>'));}
def('gBool',function(c,key){var v=!curVal(key);U(function(s,g){g.content[key]=v;});publish(c,key,v,v?'On':'Off');});
function formBlock(g,key,sub,title,help,fields,flag){var base=curObj(key),o=sub?(base[sub]||{}):base,tag=key+(sub?'_'+sub:'');
 if(g.f['i_'+tag]!==1){fields.forEach(function(f){g.f[tag+'_'+f.k]=o[f.k]||'';});g.f['i_'+tag]=1;}
 return card('<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><h4 style="margin:0">'+E(title)+'</h4>'+sentTag(key)+'</div>'+(help?'<p class="gx-sub">'+E(help)+'</p>':'')+
  fields.map(function(f,i){return '<div style="height:8px"></div>'+(f.area?area('grd.f.'+tag+'_'+f.k,f.label,{rows:3,ph:f.ph}):inp('grd.f.'+tag+'_'+f.k,f.label,{type:f.type||'text',ph:f.ph}));}).join('')+
  (flag?trow({ic:'smile',title:flag[1],sub:flag[2],on:!!o[flag[0]]},'gFormFlag',key,sub||''):'')+
  '<div style="height:8px"></div>'+btn('Save and send','gFormSave',key,{full:true,kind:'tonal',ic:'check'},sub||''));}
var FORMF={sitter:['name','from','until','notes'],grand:['greeting','likes','bedtime'],school:['text'],_:['q1','q2']};
def('gFormSave',function(c,key){var sub=c.arg2||'',g=G(),tag=key+(sub?'_'+sub:''),fl=sub?FORMF[sub]:FORMF._,base=curObj(key),o={};
 var cur=sub?(base[sub]||{}):base;for(var k in cur)o[k]=cur[k];fl.forEach(function(f){o[f]=fval(tag+'_'+f).slice(0,400);});
 if(sub)base[sub]=o;else base=o;U(function(){g.content[key]=clone(base);g.f['i_'+tag]=0;});publish(c,key,base,'Saved. It reaches '+cname()+'’s tablet in a moment.');});
def('gFormFlag',function(c,key){var sub=c.arg2||'',base=curObj(key);var o=sub?(base[sub]||(base[sub]={})):base;o.tonight=!o.tonight;U(function(s,g){g.content[key]=clone(base);});publish(c,key,base,o.tonight?cname()+' will see who is looking after her':'Hidden');});

/* ---- exchange bag (shares the packing buddy list with Rhythm) */
scr('g-bag','Exchange bag',function(c,g){var items=curList('packing'),ne=nextExchange(),meds=g.srv.meds.filter(function(m){return !m.retired;});
 var done=items.filter(function(i){return i.packed;}).length;
 return (ne?K.stat({label:'Next exchange',value:String(Math.max(0,Math.round((ymdMs(ne.date)-ymdMs(ymd(T(),herTz())))/DAY))),unit:'sleeps',note:fYmd(ne.date)+' · to '+(ne.house==='a'?'Mom’s house':'Dad’s house'),ic:'calendar'}):'')+
  card('<div style="display:flex;justify-content:space-between;align-items:center"><h4 style="margin:0">What goes in the bag</h4>'+sentTag('packing')+'</div><p class="gx-sub">'+E(cname())+' sees this as her packing buddy and ticks things off herself. You can tick too.</p>'+
   (items.length?items.map(function(it,i){return '<div class="row" style="padding:2px 0">'+A('<span class="chk'+(it.packed?' on':'')+'" role="checkbox" aria-checked="'+!!it.packed+'" aria-label="'+E(it.text)+' packed" tabindex="0">'+(it.packed?I('check',14,3):'')+'</span>','gBagTick',i)+'<span class="rtxt"><b style="'+(it.packed?'color:var(--ink3);text-decoration:line-through':'')+'">'+E(it.text)+'</b></span><button type="button" class="gx-rmv" aria-label="Remove '+E(it.text)+'"'+L.a('gListDel','packing',i)+'>'+I('trash',18,2)+'</button></div>';}).join(''):'<p class="gx-fine">Nothing yet.</p>')+
   '<div style="height:8px"></div>'+inp('grd.f.packing_text','Add an item',{ic:'plus',enter:'gListAdd|packing'})+'<div style="height:8px"></div>'+btn('Add to the bag','gListAdd','packing',{full:true,kind:'tonal',ic:'plus'}))+
  card('<h4>Medicines that travel</h4>'+(meds.length?meds.map(function(m){return '<p class="gx-sub">'+I('pill',14,2)+' '+E(m.name)+' · '+E(m.dose)+'</p>';}).join(''):'<p class="gx-sub">None.</p>')+'<p class="gx-fine">Check these are in the bag. Doses are logged under Medications.</p>')+
  K.progress(items.length?Math.round(done/items.length*100):0)+note(done+' of '+items.length+' ticked. A checklist for you, not a score for '+E(cname())+'.');});
def('gBagTick',function(c,i){var list=curList('packing');if(!list[+i])return;list[+i].packed=!list[+i].packed;U(function(s,g){g.content.packing=clone(list);});publish(c,'packing',list);});

/* ================================================================================ SUITES AUTHORED FOR HER DEVICE */
var SUITES=[
 {id:'rhythm',title:'Rhythm',ic:'clock',blurb:'Routines, first-then, packing, new places, sensory profile',build:function(g){return listBlock(g,'routine',LISTCFG.routine)+listBlock(g,'firstThen',LISTCFG.firstThen)+listBlock(g,'packing',LISTCFG.packing)+listBlock(g,'newPlace',LISTCFG.newPlace)+
   flagsBlock(g,'sensory','Sensory profile','Things that may need a quiet warning. Her tablet adds gentler pictures and a heads-up. Not a diagnosis.',[['loud','Loud places','Warn her first',  'volume'],['bright','Bright lights','Warn her first','sun'],['scratchy','Scratchy or tight clothes','Offer a choice','hand'],['crowds','Crowds','Give her an exit picture','users'],['surprises','Surprises','Say what is coming','sparkle']],true);}},
 {id:'voice',title:'Voice',ic:'mic',blurb:'My helpers, symbols setup, feelings check-in on or off',build:function(g){return listBlock(g,'helpers',LISTCFG.helpers)+listBlock(g,'symbols',LISTCFG.symbols)+
   boolBlock(g,'feelings','Feelings check-in on her tablet','She can tell her tablet how she feels. Her answers belong to her. You will never see them, and nothing is sent to anyone.',true);}},
 {id:'growing',title:'Growing',ic:'leaf',blurb:'Time capsule, first times, growing marks',build:function(g){return listBlock(g,'capsule',LISTCFG.capsule)+listBlock(g,'firstTimes',LISTCFG.firstTimes)+listBlock(g,'marks',LISTCFG.marks);}},
 {id:'care',title:'Care',ic:'heart',blurb:'When I feel poorly, a doctor visit step by step',build:function(g){return listBlock(g,'poorly',LISTCFG.poorly)+listBlock(g,'visit',LISTCFG.visit)+'<p class="gx-fine">Medicines and the emergency card are for grown-ups only. They are never shown on her tablet.</p>';}},
 {id:'village',title:'Village',ic:'users',blurb:'Sitter pass, grandparent page, school summary',build:function(g){return formBlock(g,'village','sitter','Sitter pass','Written by you. Shown on your screen to the sitter, never sent.',[{k:'name',label:'Sitter’s name',ph:'Sam'},{k:'from',label:'From',type:'date'},{k:'until',label:'Until',type:'date'},{k:'notes',label:'Notes for the sitter',area:true,ph:'Bedtime story, then lights out at 7:30.'}],['tonight','Tell '+cname()+' who is looking after her','A name and a friendly picture on her tablet. Nothing else.'])+
   formBlock(g,'village','grand','Grandparent page','Written by you for a visiting grandparent.',[{k:'greeting',label:'A welcome',area:true,ph:'Ivy loves to show you her drawings.'},{k:'likes',label:'What she likes',ph:'Pancakes, the park'},{k:'bedtime',label:'Bedtime',ph:'7:30'}])+
   formBlock(g,'village','school','School summary','A short note about what her school needs to know.',[{k:'text',label:'The note',area:true,ph:'Allergic to penicillin. Inhaler is in her bag.'}]);}},
 {id:'compass',title:'Compass',ic:'target',blurb:'Two gentle questions, the suites shelf, hearing and travel profiles',build:function(g){return formBlock(g,'compass',null,'Two gentle questions','She can answer or skip. Her answers stay with her.',[{k:'q1',label:'Question one'},{k:'q2',label:'Question two'}])+
   card('<div style="display:flex;justify-content:space-between;align-items:center"><h4 style="margin:0">Suites shelf</h4>'+sentTag('shelf')+'</div><p class="gx-sub">Each switch belongs to its own suite. It is the same switch you see on that suite’s page.</p>'+SUITES.filter(function(s){return s.id!=='compass';}).concat([SUITES[5]]).map(function(s){var on=!!curObj('shelf')[s.id];return trow({ic:s.ic,title:s.title,sub:s.blurb,on:on},'gShelf',s.id);}).join(''))+
   flagsBlock(g,'profiles','Profiles','Switch these on if they fit. Each changes how her tablet speaks to her.',[['dhh','Deaf or hard of hearing','Visual alerts and no sound-only cues. Captions are not built yet, so they are not promised.','eye'],['away','Away from home','A quiet pack for trips: calmer, fewer online things.','house']],true);}}];
scr('g-suites','Her suites',function(c,g){var shelf=curObj('shelf');
 return K.banner('pri','Things you write for '+cname()+'’s tablet. Each suite has its own switch. Nothing here reads anything from her.','sparkle')+
  SUITES.map(function(s){return rowA({ic:s.ic,title:s.title,sub:s.blurb,go:true,trail:shelf[s.id]?K.chip('On her shelf',{tone:'ok',sm:true}):K.chip('Off',{sm:true})},'go','g-s-'+s.id);}).join('')+note('A suite on her shelf shows up on her tablet. Off means she does not see it at all.');});
SUITES.forEach(function(s){scr('g-s-'+s.id,s.title,function(c,g){var shelf=curObj('shelf');
 return card(trow({ic:s.ic,title:'Show '+s.title+' on '+cname()+'’s shelf',sub:s.blurb,on:!!shelf[s.id]},'gShelf',s.id))+s.build(g);});});
def('gShelf',function(c,id){var o=curObj('shelf');o[id]=!o[id];U(function(s,g){g.content.shelf=clone(o);});publish(c,'shelf',o,o[id]?'On '+cname()+'’s shelf':'Off her shelf');});

/* ================================================================================ CARE HUB + TILES */
scr('g-care','Care and coordination',function(c,g){
 var h=K.banner('pri','Records both guardians share. Nothing here is ever shown on '+cname()+'’s tablet.','shield');
 h+=card(
  rowA({ic:'shield',title:'Emergency card',sub:'Version '+g.srv.emerg.v+' · shown on screen only',go:true},'go','g-emergency')+
  rowA({ic:'eye',title:'Hospital mode',sub:'Large, plain text for a doctor',go:true},'go','g-hospital')+
  rowA({ic:'pill',title:'Medications',sub:medsDue()?medsDue()+' due now':'Dose log and double-dose guard',go:true},'go','g-meds')+
  rowA({ic:'file',title:'Exchange bag',sub:'What travels between homes',go:true},'go','g-bag')+
  rowA({ic:'list',title:'Care binder',sub:'Pages for you and a sitter',go:true},'go','g-binder')+
  rowA({ic:'calendar',title:'Appointment prep',sub:'Questions and things to bring',go:true},'go','g-appt'));
 h+=card(
  rowA({ic:'letter',title:'Handover notes',sub:'Append-only, never deletable',go:true},'go','g-handover')+
  rowA({ic:'calendar',title:'Custody schedule',sub:rhythmWords(g.fam.rhythm)+(g.fam.rhythm.locked?' · locked by order':''),go:true},'go','g-schedule')+
  rowA({ic:'swap',title:'Swap a night',sub:swapsIn()?swapsIn()+' waiting for you':'Ask or answer',go:true},'go','g-swap')+
  rowA({ic:'receipt',title:'Shared expenses',sub:'Propose, accept, dispute, reimburse',go:true},'go','g-expenses')+
  rowA({ic:'clock',title:'Her time, your time',sub:'Overlap windows and the month',go:true},'go','g-overlap'));
 return h;},{root:false});
function swapsIn(){var g=G();return g.srv.swaps.filter(function(x){return x.state==='pending'&&x.by!==gid();}).length;}
function expIn(){var g=G();return g.srv.exp.filter(function(x){return x.state==='proposed'&&x.by!==gid();}).length;}

function T2(o){o.dev='g';return L.tile(o);}
/* Home: the four things a guardian reaches for most */
T2({area:'home',tier:'featured',id:'grd.card',title:'Emergency card',sub:function(){return 'Version '+G().srv.emerg.v;},icon:'shield',screen:'g-emergency',order:30});
T2({area:'home',tier:'featured',id:'grd.meds',title:'Medications',sub:function(){var n=medsDue();return n?n+' due now':'Dose log';},icon:'pill',screen:'g-meds',order:31,badge:function(){var n=medsDue();return n?n:null;}});
T2({area:'home',tier:'featured',id:'grd.swap',title:'Swap a night',sub:function(){var n=swapsIn();return n?n+' waiting for you':'Ask or answer';},icon:'swap',screen:'g-swap',order:32,badge:function(){var n=swapsIn();return n?n:null;}});
T2({area:'home',tier:'featured',id:'grd.handover',title:'Handover notes',sub:function(){var n=G().srv.notes.length;return n?n+' in the log':'Start the log';},icon:'letter',screen:'g-handover',order:33});
/* More hub */
[['care','Care','heart','g-care',40],['suites','Her suites','sparkle','g-suites',41],['exp','Expenses','receipt','g-expenses',42,function(){var n=expIn();return n?n:null;}],['bag','Exchange bag','file','g-bag',43],['binder','Care binder','list','g-binder',44],['appt','Appointments','calendar','g-appt',45],['overlap','Her time, your time','clock','g-overlap',46],['sched','Schedule','calendar','g-schedule',47],['hosp','Hospital mode','eye','g-hospital',48],['learn','Parent Learn','book','g-learn',49],['hist','Family history','users','g-history',50],['adults','Adults and helpers','user','g-adults',51],['partner','Co-guardian (simulated)','users','g-partner',52,function(){var n=unread();return n?n:null;}]].forEach(function(t){
 T2({area:'more',tier:'standard',id:'grd.m.'+t[0],title:t[1],icon:t[2],screen:t[3],order:t[4],badge:t[5]});});
/* Settings rows by group */
function sr(group,id,title,sub,icon,screen,order,extra){var o={area:'settings',group:group,id:'grd.s.'+id,title:title,sub:sub,icon:icon,screen:screen,order:order};if(extra)for(var k in extra)o[k]=extra[k];T2(o);}
sr('Her','colour','Colour and art',function(){var g=G(),k=kg();return (k.colour?k.colour.name:'Not asked yet')+' · '+(ART.filter(function(a){return a[0]===g.her.art;})[0]||ART[0])[1];},'palette','g-colour',11);
sr('Her','look','How her app looks',function(){var g=G();return K.SEEDS[g.her.palette].n+' · '+g.her.mode;},'leaf','g-look',12);
sr('Her','band','Age band',function(){var k=kg();return bandName(effBand())+(k.bandHold&&k.bandHold.on?' · held':'');},'sparkle','g-band',13,{badge:function(){var k=kg();return k.bandHold&&k.bandHold.on?true:null;}});
sr('Her','access','Accessibility for her device',function(){var a=G().access;var n=['readAloud','roomy','reduceMotion','larger'].filter(function(x){return a[x];}).length;return n+' on';},'eye','g-access',14);
sr('Her','play','Play window and daily time',function(){var p=G().play;return p.on?f12(p.open)+' to '+f12(p.rest)+' · wind-down '+(p.wind||'off')+(p.wind?' min':''):'Open all day';},'moon','g-play',15);
sr('Her','suites','Her suites',function(){var o=curObj('shelf');var n=Object.keys(o).filter(function(k){return o[k];}).length;return n+' on her shelf';},'sparkle','g-suites',16);
sr('Family','family','Family structure',function(){var g=G();return g.fam.homes.length+' homes · '+g.fam.people.length+' people'+(dirtyDraft()?' · draft open':'');},'users','g-family',12);
sr('Family','history','Family history',function(){var n=G().hist.length;return n?n+' entr'+(n===1?'y':'ies'):'Nothing yet';},'clock','g-history',13,{badge:function(){var g=G();return g.hist.some(function(e){var s=hstat(e);return e.kind==='family'&&(s==='held'||s==='scheduled');})?true:null;}});
sr('Family','rhythm','Weekly rhythm',function(){var r=G().fam.rhythm;return rhythmWords(r)+(r.locked?' · locked by order':'');},'calendar','g-schedule',14);
sr('Family','adults','Adults and helpers',function(){return 'Sitter pass, grandparent page';},'user','g-adults',15);
sr('Family','devices','Remove a device',function(){return 'Yours and '+cname()+'’s, never '+pName()+'’s';},'device','g-devices',16);
sr('Family','partner',function(){return pName()+' (simulated co-guardian)';},'Notices, swaps, conflicts','users','g-partner',17,{badge:function(){var n=unread();return n?n:null;}});
sr('Safety','pin','Change PIN','Needs the current PIN','key','g-pin',11);
sr('Safety','controls','Parental controls',function(){var g=G();var n=Object.keys(g.ctl.tiles).filter(function(k){return g.ctl.tiles[k].hidden||g.ctl.tiles[k].pace;}).length;return n?n+' tile'+(n===1?'':'s')+' changed':'Messages are always on';},'shield','g-controls',12);
sr('Safety','data','Data on this phone','What lives here and what lives on the server','download','g-data',13);
sr('Learn','learn','Parent Learn',function(){var s=LS().settings;return 'Private to you · reflection '+(s.reflection==='off'?'off':s.reflection==='saved'?'saved':'this session');},'book','g-learn',10);
sr('Learn','choices','Your Learn choices','Every extra is optional','sliders','g-learn-choices',11);
sr('Account','delete','Delete my account','A 6 to 12 month recovery window','trash','g-delete',80,{when:function(){return G().acct.state!=='pending';}});
sr('Account','hold','Account on hold',function(){return 'Recover or download';},'lock','g-hold',81,{when:function(){return G().acct.state==='pending';}});
sr('Account','session','Session',function(){return sx().dev.g.sessionOk?'Signed in':'Signed out';},'key','g-session',89);

L.on('family:changed',function(p){L.safe('grd partner',function(){if(p&&p.what==='created')ensurePartner();});});
L.onBoot(function(){L.safe('grd boot partner',ensurePartner);});
var prevFast=L.fastExtras;L.fastExtras=function(){try{ensurePartner();}catch(e){}return prevFast?prevFast():undefined;};
});})();
