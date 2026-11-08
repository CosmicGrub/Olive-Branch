/* Olive Branch overhaul, ROUND 2 design kit. Themes, icons, illustration and component builders.
   Everything returns HTML strings so the screen files stay declarative. K = OB.

   ADDITIVE and backward compatible with round 1: every earlier helper keeps its name and arguments.
   Some earlier helpers gained optional arguments and a11y attributes (role, aria-*, tabindex).

   ---- NEW THEME TOKENS (CSS variables set on .ob by OB.theme) --------------------------------------------
   --line     decorative hairline (cards, dividers). Not for control edges.
   --edge     control border / unchecked-box / off-track; >= 3:1 on bg, surface and surface2 (WCAG 1.4.11)
   --track    off-state track of toggles (= edge)
   --focus    focus ring colour, >= 3:1 on bg, surfaces and primary
   --hiC      inner top highlight colour, --hero1/--hero2 hero gradient stops
   --shadow0..3  elevation 0 (hairline) .. 3 (modal). shadow1/shadow2 keep their round-1 meaning.
   Day-part colours (--dpMorning ... --dpNight) and ok/warn/bad/info are protected and unchanged in role.

   ---- NEW HELPERS (signature, then what it renders) -----------------------------------------------------
   Forms / controls
   K.segmented(items,a,o)        segmented control; items are strings or {l,ic,count}; o:{full,sm,n,label}
   K.filterChip(text,o)          filter chip button; o:{on,ic,count,n}      K.filterChips(items,active,o)  scroll row
   K.check(on) K.radio(on)       bare checkbox / radio glyphs              K.slider(pct,o) bare slider {label,min,max,text}
   K.toggleRow(o)  K.radioRow(o)  K.checkRow(o)   o:{title,sub,on,ic,n}    K.sliderRow(o) o:{title,sub,value,l,r,text}
   K.formField(o)                o:{label,value,ph,hint,error,ic,req,suffix,focus,id,type,disabled,n}
   K.keypad2 -> use K.pinPad(o)  PIN pad with dots and delete, o:{filled,total,digits,zero,bio,title,sub}
   Identity
   K.avatar(l,o)                 (extended) o:{size,ring,tone:"accent|ok|info|warn|quiet",status:"on|away",label}
   K.avatarStack(list,o)         list of letters or [letter,tone]; o:{size,max,label}
   Status and feedback
   K.status(kind,text,o)         pill: queued|sent|delivered|watched|failed|banked ; shape + icon + word, never colour alone
   K.notice(o)                   rich banner o:{tone,title,text,ic,action,dismiss,n}
   K.offlineBanner(o)            o:{text,sub,action}
   K.toast(text,o)               snackbar o:{ic,tone,action,inline}
   K.emptyState(o)               o:{spot,title,sub,action}   (illustrated; K.empty still works)
   K.errorState(o)               o:{title,sub,action,detail}
   K.skeleton(kind,n)            kind: row|card|text|tile|hero (static, no shimmer: no autonomous motion)
   K.permission(o)               permission prompt card o:{ic,title,body,why:[..],allow,deny}
   Layers
   K.bottomSheet(o)              o:{title,inner,actions,detent:"half|full",close}   (K.sheet(inner) still works)
   K.modal(o)                    centred dialog o:{ic,title,body,actions,tone,id}
   Lists and flow
   K.swipe(rowHtml,o)            list row with swipe peek o:{actions:[{l,ic,tone}],open}
   K.stepper(total,active,o)     progress pills (aria progressbar)         K.steps(labels,active) labelled stepper
   K.kv(rows,o)                  key-value rows o:{ruled}                  K.divider(text)
   K.stat(o)                     stat tile o:{label,value,unit,note,ic}. Never a score, rank or streak (P2).
   K.timeline(items,o)           items [{time,title,sub,ic,tone,state:"done|now|next"}]
   K.schedule(blocks,o)          day grid o:{from,to,hourH,now}; block {s,e,title,sub,tone,col,cols}   K.scheduleBlock(o)
   K.calMonth(o)                 month grid o:{y,m,today,sel,marks:{day:"a|b|mix|ev"},lead,names:{a,b},label}
   K.dayCell(n,o)                one day cell o:{today,sel,tone,dot,dim,label}
   Media
   K.recordBtn(o)                big circular record button o:{state:"idle|rec|done",time,size,label}
   K.waveform(o)                 o:{bars,played(0-1),seed,h,tone,label}
   K.player(o)                   video chrome o:{scene,time,dur,progress,playing,captions,caption,title}
   K.qrCard(o)                   code card o:{code,title,sub,expires,copy}
   Illustration
   K.scene(kind,w,h)             kinds: hills night sea paper letters branch (round 1) + day garden kitchen car
                                 classroom bedroom park twohouses (alias houses, home-two-houses)
   K.spot(kind,size,o)           spot illustrations: family houses envelope key shield lock phone tablet video mic leaf
                                 o:{plate:false,tone:"accent"}.  K.SPOTS lists them.
   Misc
   K.sr(text)                    visually hidden text for screen readers
   K.FORMS                       device sizes {form:[w,h]}; extra postures foldMain, foldTabletop (frame only)
   Type classes: t-display t-title t-head t-body t-cap t-label t-mono tnum  (see overhaul.css)
*/
(function(){
"use strict";
var OB=window.OB={screens:[],form:"phone",palette:"olive",mode:"light",annotate:false};

/* ---------------------------------------------------------------- themes -- */
var SEEDS={
 olive:{n:"Olive",seed:"#4A6B4F",note:"Proposed new default: the brand colour"},
 classic:{n:"Classic",seed:"#673AB7",note:"Today’s default (stock deep purple)"},
 calm:{n:"Calm modern",seed:"#4A7C74",note:"Muted teal, low arousal"},
 warm:{n:"Warm grounded",seed:"#B5651D",note:"Terracotta and amber"},
 playful:{n:"Soft playful",seed:"#E8683F",note:"Coral. The most overtly kid"},
 cozy:{n:"Deep cozy",seed:"#2E5339",note:"Forest green, evening friendly"},
 bold:{n:"Bright bold",seed:"#1565C0",note:"Saturated blue for older kids"}};
OB.SEEDS=SEEDS;
function rgb(h){return [parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];}
function hsl(h){var c=rgb(h).map(function(v){return v/255;}),mx=Math.max.apply(null,c),mn=Math.min.apply(null,c),l=(mx+mn)/2,d=mx-mn,hh=0,s=0;
 if(d){s=d/(1-Math.abs(2*l-1));if(mx===c[0])hh=((c[1]-c[2])/d)%6;else if(mx===c[1])hh=(c[2]-c[0])/d+2;else hh=(c[0]-c[1])/d+4;hh*=60;if(hh<0)hh+=360;}
 return [hh,s*100,l*100];}
function H(h,s,l){return "hsl("+Math.round(h)+" "+Math.round(Math.max(0,Math.min(100,s)))+"% "+Math.round(Math.max(0,Math.min(100,l)))+"%)";}
OB.theme=function(pal,mode){
 var sd=SEEDS[pal]||SEEDS.olive,t=hsl(sd.seed),h=t[0],s=Math.max(26,Math.min(70,t[1])),dark=mode==="dark",v={},hr=Math.round(h);
 if(!dark){
  v.bg=H(h,22,97);v.surface="#ffffff";v.surface2=H(h,20,94);v.surface3=H(h,18,90);v.outline=H(h,14,85);
  v.line=H(h,16,89);v.edge=H(h,9,47);v.track=v.edge;
  v.ink=H(h,28,11);v.ink2=H(h,12,33);v.ink3=H(h,10,37);
  v.pri=H(h,s,Math.min(36,Math.max(26,t[2])));v.priD=H(h,s,23);v.onPri="#ffffff";
  v.priC=H(h,Math.min(60,s*1.25),90);v.onPriC=H(h,s,20);v.priC2=H(h,Math.min(60,s*1.2),82);
  v.accent=H(h+28,62,58);v.accentC=H(h+28,70,90);
  v.focus=H(h,Math.max(s,50),30);v.hiC="rgba(255,255,255,.75)";
  v.hero1=v.pri;v.hero2=v.priD;v.sheen=".07";
  v.shadow0="0 1px 1px hsl("+hr+" 30% 10% / .05)";
  v.shadow1="0 0 0 .5px hsl("+hr+" 24% 20% / .04),0 1px 2px hsl("+hr+" 30% 10% / .06),0 5px 14px -2px hsl("+hr+" 30% 10% / .08),inset 0 1px 0 rgba(255,255,255,.8)";
  v.shadow2="0 1px 2px hsl("+hr+" 30% 10% / .07),0 8px 16px -4px hsl("+hr+" 30% 10% / .10),0 22px 40px -8px hsl("+hr+" 30% 10% / .16),inset 0 1px 0 rgba(255,255,255,.55)";
  v.shadow3="0 2px 4px hsl("+hr+" 30% 10% / .08),0 16px 30px -6px hsl("+hr+" 30% 10% / .18),0 36px 70px -14px hsl("+hr+" 30% 10% / .30)";
  v.ok="#237a52";v.okC="#dcf3e6";v.warn="#8f6100";v.warnC="#fcefcf";v.bad="#b3322a";v.badC="#fbe3e0";v.info="#245f9c";v.infoC="#dceafa";
 }else{
  v.bg=H(h,20,8);v.surface=H(h,17,12);v.surface2=H(h,16,16);v.surface3=H(h,15,21);v.outline=H(h,13,25);
  v.line=H(h,13,19);v.edge=H(h,9,52);v.track=v.edge;
  v.ink=H(h,18,94);v.ink2=H(h,10,80);v.ink3=H(h,9,66);
  v.pri=H(h,Math.min(60,s+6),70);v.priD=H(h,s,64);v.onPri=H(h,30,10);
  v.priC=H(h,Math.min(45,s),24);v.onPriC=H(h,40,90);v.priC2=H(h,Math.min(45,s),30);
  v.accent=H(h+28,60,66);v.accentC=H(h+28,40,26);
  v.focus=H(h,Math.min(80,s+16),72);v.hiC="rgba(255,255,255,.06)";
  v.hero1=v.pri;v.hero2=v.priD;v.sheen=".05";
  v.shadow0="0 1px 1px rgba(0,0,0,.35)";
  v.shadow1="0 0 0 .5px rgba(255,255,255,.04),0 1px 2px rgba(0,0,0,.4),0 6px 16px -2px rgba(0,0,0,.35),inset 0 1px 0 rgba(255,255,255,.05)";
  v.shadow2="0 1px 2px rgba(0,0,0,.45),0 10px 20px -4px rgba(0,0,0,.45),0 26px 48px -8px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.06)";
  v.shadow3="0 2px 4px rgba(0,0,0,.5),0 18px 34px -6px rgba(0,0,0,.55),0 40px 80px -14px rgba(0,0,0,.65)";
  v.ok="#6ccf9d";v.okC="#12301f";v.warn="#ecc15c";v.warnC="#34290c";v.bad="#f2a59d";v.badC="#3a1a17";v.info="#8bbdf0";v.infoC="#122a44";
 }
 /* Protected semantic colours: never taken from a palette (MASTERFILE 8.6.2). */
 v.dpMorning=dark?"#e9b955":"#f2bd4e";v.dpDay=dark?"#6fa9de":"#78b6e8";v.dpAfternoon=dark?"#7fc08a":"#88c98f";
 v.dpEvening=dark?"#dc8f62":"#e59a6b";v.dpBed=dark?"#8d93d6":"#7d84c9";v.dpNight=dark?"#4a5399":"#3e4580";
 var out="";for(var k in v)out+="--"+k+":"+v[k]+";";return out;
};
OB.themeCss=OB.theme;

/* ----------------------------------------------------------------- icons -- */
var IC={
 home:'<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
 calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 chat:'<path d="M5 4h14a2 2 0 012 2v9a2 2 0 01-2 2h-8l-5 4v-4H5a2 2 0 01-2-2V6a2 2 0 012-2z"/>',
 mail:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 8l9 6 9-6"/>',
 phone:'<path d="M5 4h4l2 5-2.5 1.5a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z"/>',
 video:'<rect x="3" y="6" width="12" height="12" rx="3"/><path d="M15 10l6-3v10l-6-3"/>',
 mic:'<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/>',
 micoff:'<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3M4 4l16 16"/>',
 camera:'<path d="M4 8h3l2-3h6l2 3h3a1 1 0 011 1v9a1 1 0 01-1 1H4a1 1 0 01-1-1V9a1 1 0 011-1z"/><circle cx="12" cy="13" r="3.5"/>',
 image:'<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="M4 18l5-5 4 4 3-3 4 4"/>',
 book:'<path d="M4 5a2 2 0 012-2h13v16H6a2 2 0 00-2 2z"/><path d="M4 19a2 2 0 012-2h13"/>',
 pencil:'<path d="M4 20l1-4L16 5l3 3L8 19z"/><path d="M14 7l3 3"/>',
 palette:'<path d="M12 3a9 9 0 100 18c1.5 0 2-1 1.5-2s0-2 1.5-2h2a3 3 0 003-3c0-5-4-11-8-11z"/><circle cx="8" cy="11" r="1"/><circle cx="12" cy="7.5" r="1"/><circle cx="16" cy="10" r="1"/>',
 puzzle:'<path d="M10 4a2 2 0 114 0v2h4v4h-2a2 2 0 100 4h2v4h-4v-2a2 2 0 10-4 0v2H6v-4h2a2 2 0 100-4H6V6h4z"/>',
 dice:'<rect x="4" y="4" width="16" height="16" rx="4"/><circle cx="9" cy="9" r="1" fill="currentColor"/><circle cx="15" cy="15" r="1" fill="currentColor"/><circle cx="15" cy="9" r="1" fill="currentColor"/><circle cx="9" cy="15" r="1" fill="currentColor"/>',
 heart:'<path d="M12 20s-8-5-8-11a4.5 4.5 0 018-2.5A4.5 4.5 0 0120 9c0 6-8 11-8 11z"/>',
 smile:'<circle cx="12" cy="12" r="9"/><path d="M8 14a5 5 0 008 0"/><circle cx="9" cy="10" r=".8" fill="currentColor"/><circle cx="15" cy="10" r=".8" fill="currentColor"/>',
 sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
 moon:'<path d="M20 14A8 8 0 0110 4a8 8 0 1010 10z"/>',
 bell:'<path d="M6 17v-6a6 6 0 0112 0v6l2 2H4z"/><path d="M10 21a2 2 0 004 0"/>',
 lock:'<rect x="5" y="11" width="14" height="10" rx="3"/><path d="M8 11V8a4 4 0 018 0v3"/>',
 key:'<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M16 7l3 3"/>',
 shield:'<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
 shieldcheck:'<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M8.5 12l2.5 2.5L16 9.5"/>',
 user:'<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0116 0"/>',
 users:'<circle cx="9" cy="8" r="3.5"/><path d="M2 20a7 7 0 0114 0"/><circle cx="17" cy="9" r="2.5"/><path d="M17 14a5 5 0 015 5"/>',
 plus:'<path d="M12 5v14M5 12h14"/>',check:'<path d="M5 12l5 5 9-10"/>',x:'<path d="M6 6l12 12M18 6L6 18"/>',
 chevR:'<path d="M9 6l6 6-6 6"/>',chevL:'<path d="M15 6l-6 6 6 6"/>',chevD:'<path d="M6 9l6 6 6-6"/>',chevU:'<path d="M6 15l6-6 6 6"/>',
 search:'<circle cx="11" cy="11" r="7"/><path d="M16 16l5 5"/>',
 sliders:'<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
 qr:'<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h3v3h-3zM20 14v6M14 20h3"/>',
 link:'<path d="M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7l-1 1M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7l1-1"/>',
 download:'<path d="M12 4v11M7 11l5 5 5-5M5 20h14"/>',send:'<path d="M3 11l18-8-8 18-2-8z"/>',
 play:'<path d="M8 5l11 7-11 7z" fill="currentColor"/>',pause:'<rect x="7" y="5" width="3.6" height="14" rx="1" fill="currentColor"/><rect x="13.4" y="5" width="3.6" height="14" rx="1" fill="currentColor"/>',
 volume:'<path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16 9a4 4 0 010 6M18.5 6.5a8 8 0 010 11"/>',
 eye:'<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
 eyeoff:'<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/><path d="M4 4l16 16"/>',
 globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 010 18M12 3a14 14 0 000 18"/>',
 file:'<path d="M6 3h8l5 5v13H6z"/><path d="M14 3v5h5"/>',
 letter:'<path d="M5 4h12a2 2 0 012 2v12a2 2 0 01-2 2H7a2 2 0 01-2-2z"/><path d="M9 9h6M9 13h6"/>',
 pill:'<path d="M10.5 3.5a4.5 4.5 0 016.4 6.4l-7 7a4.5 4.5 0 01-6.4-6.4z"/><path d="M8 8l8 8"/>',
 hand:'<path d="M7 12V6a1.5 1.5 0 013 0v5V4a1.5 1.5 0 013 0v7V5a1.5 1.5 0 013 0v8c0 5-3 8-7 8-3 0-5-2-6-5l-1-3a1.5 1.5 0 013-.5z"/>',
 more:'<circle cx="5" cy="12" r="1.4" fill="currentColor"/><circle cx="12" cy="12" r="1.4" fill="currentColor"/><circle cx="19" cy="12" r="1.4" fill="currentColor"/>',
 arrowR:'<path d="M5 12h14M13 6l6 6-6 6"/>',arrowL:'<path d="M19 12H5M11 6l-6 6 6 6"/>',
 hourglass:'<path d="M6 3h12M6 21h12M7 3c0 5 5 6 5 9s-5 4-5 9M17 3c0 5-5 6-5 9s5 4 5 9"/>',
 receipt:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
 list:'<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1" fill="currentColor"/><circle cx="4" cy="12" r="1" fill="currentColor"/><circle cx="4" cy="18" r="1" fill="currentColor"/>',
 grid:'<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
 device:'<rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/>',
 wifi:'<path d="M2 9a15 15 0 0120 0M5.5 12.5a10 10 0 0113 0M9 16a5 5 0 016 0"/><circle cx="12" cy="19.5" r=".9" fill="currentColor"/>',
 trash:'<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',flag:'<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
 leaf:'<path d="M4 20C4 10 10 4 20 4c0 10-6 16-16 16z"/><path d="M4 20L14 10"/>',
 sparkle:'<path d="M12 3l2 6 6 2-6 2-2 6-2-6-6-2 6-2z"/>',
 swap:'<path d="M7 4L3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7"/>',
 info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/>',
 warn:'<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18h.01"/>',
 refresh:'<path d="M20 11a8 8 0 00-14-4L4 9M4 4v5h5M4 13a8 8 0 0014 4l2-2M20 20v-5h-5"/>',
 pawn:'<circle cx="12" cy="7" r="3"/><path d="M9 21h6M10 21l.5-7h3l.5 7M8.5 14h7"/>',
 tv:'<rect x="3" y="5" width="18" height="12" rx="3"/><path d="M8 21h8M12 17v4"/>',
 grid3:'<path d="M4 4h16v16H4zM4 9.3h16M4 14.7h16M9.3 4v16M14.7 4v16"/>',
 brush:'<path d="M14 4l6 6-8 8c-2 2-5 2-7 1 1-2 0-3 1-5z"/><path d="M13 7l4 4"/>',
 star:'<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>',
 target:'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/>',
 layers:'<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
 cloud:'<path d="M7 18a4 4 0 01-.5-8A5.5 5.5 0 0117 9.5 3.8 3.8 0 0117 18z"/>',
 footprint:'<circle cx="9" cy="7" r="2.5"/><circle cx="15.5" cy="10" r="2.5"/><path d="M7 12c-1 3 0 7 2 8s3-1 3-3-.5-5-5-5zM14 15c-1 2 0 5 2 5s3-3 1-5z"/>',
 /* round 2 additions */
 tablet:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M19 12h.01"/>',
 cc:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 10a2.5 2.5 0 100 4M17 10a2.5 2.5 0 100 4"/>',
 expand:'<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
 backspace:'<path d="M9 5h10a2 2 0 012 2v10a2 2 0 01-2 2H9l-6-7z"/><path d="M13 10l4 4M17 10l-4 4"/>',
 stop:'<rect x="6" y="6" width="12" height="12" rx="3" fill="currentColor"/>',
 copy:'<rect x="8" y="8" width="12" height="12" rx="3"/><path d="M16 8V6a2 2 0 00-2-2H6a2 2 0 00-2 2v8a2 2 0 002 2h2"/>',
 share:'<path d="M12 15V4M8 8l4-4 4 4M5 13v5a2 2 0 002 2h10a2 2 0 002-2v-5"/>',
 wifioff:'<path d="M2 9a15 15 0 018-4M22 9a15 15 0 00-4-3M5.5 12.5a10 10 0 015-2.6M18.5 12.5a10 10 0 00-2-1.6M9 16a5 5 0 016 0"/><circle cx="12" cy="19.5" r=".9" fill="currentColor"/><path d="M4 4l16 16"/>',
 undo:'<path d="M9 7L4 12l5 5M4 12h10a6 6 0 010 12"/>',
 fingerprint:'<path d="M6 11a6 6 0 0112 0v2M9 20c-1-2-1.5-4-1.5-7a4.5 4.5 0 019 0c0 2 .5 4 1.5 6M12 13c0 3 .5 5 1.5 7M3 9a9 9 0 0118 0"/>',
 check2:'<path d="M2 12.5l5 5 9-10M12 16.5l1 1 9-10"/>',
 inbox:'<path d="M4 14l2-9h12l2 9v5H4z"/><path d="M4 14h5l1 2h4l1-2h5"/>',
 house:'<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/>',
 filter:'<path d="M4 5h16l-6 8v6l-4-2v-4z"/>',
 edit:'<path d="M4 20l1-4L16 5l3 3L8 19z"/>',
 rewind:'<path d="M3 12a9 9 0 109-9H8M8 3L5 6l3 3"/>',
 skip:'<path d="M21 12a9 9 0 11-9-9h4M16 3l3 3-3 3"/>'
};
OB.ICONS=Object.keys(IC);
OB.ico=function(n,sz,sw){sz=sz||22;return '<svg class="ico" viewBox="0 0 24 24" width="'+sz+'" height="'+sz+'" fill="none" stroke="currentColor" stroke-width="'+(sw||1.8)+'" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'+(IC[n]||IC.info)+'</svg>';};
var ico=OB.ico;

/* ---------------------------------------------------------- illustration -- */
/* Scenes use theme variables, so every palette gets its own illustration colours.
   Gradient ids are unique per call so two palettes on one page never share a definition. */
var _gid=0;function gid(){return "kg"+(++_gid);}
function SV(inner,w,h,defs){return '<svg class="scene" viewBox="0 0 300 150" width="'+(w||300)+'" height="'+(h||150)+'" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">'+(defs?'<defs>'+defs+'</defs>':"")+inner+'</svg>';}
function LG(id,a,b){return '<linearGradient id="'+id+'" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="'+a+'"/><stop offset="1" stop-color="'+b+'"/></linearGradient>';}
function mix(a,p,b){return 'color-mix(in srgb,'+a+' '+p+'%,'+b+')';}
function cloud(x,y,s,o){return '<g transform="translate('+x+' '+y+') scale('+s+')" fill="#fff" opacity="'+(o||.85)+'"><ellipse cx="0" cy="0" rx="22" ry="8"/><ellipse cx="-10" cy="-6" rx="12" ry="8"/><ellipse cx="8" cy="-8" rx="14" ry="10"/></g>';}
OB.scene=function(kind,w,h){
 var g=gid(),g2=gid();
 if(kind==="hills")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="236" cy="42" r="34" fill="var(--accent)" opacity=".16"/><circle cx="236" cy="42" r="22" fill="var(--accent)" opacity=".92"/>'+cloud(70,34,.9,.7)+'<path d="M0 104 Q70 66 140 98 T300 84 V150 H0Z" fill="var(--priC2)"/><path d="M0 124 Q90 92 170 120 T300 112 V150 H0Z" fill="var(--pri)" opacity=".88"/><path d="M0 140 Q100 122 190 138 T300 134 V150 H0Z" fill="var(--priD)" opacity=".5"/><g fill="var(--priD)"><circle cx="64" cy="98" r="13"/><rect x="62" y="104" width="4" height="14" rx="2"/><circle cx="92" cy="104" r="9"/><rect x="90" y="108" width="3.4" height="11" rx="1.7"/></g>',w,h,LG(g,"var(--priC2)","var(--priC)"));
 if(kind==="night")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><g fill="#fff">'+[[30,24],[70,50],[120,18],[180,40],[250,22],[270,70],[210,64],[150,60]].map(function(p,i){return '<circle cx="'+p[0]+'" cy="'+p[1]+'" r="'+(i%3?1:1.8)+'" opacity="'+(i%2?.55:.9)+'"/>';}).join("")+'</g><circle cx="222" cy="46" r="34" fill="#f7efc8" opacity=".12"/><circle cx="222" cy="46" r="24" fill="#f7efc8"/><circle cx="232" cy="40" r="22" fill="#16223a"/><path d="M0 118 Q80 92 160 116 T300 108 V150 H0Z" fill="#1f3550"/><path d="M0 134 Q110 112 200 132 T300 128 V150 H0Z" fill="#274463"/><g><rect x="46" y="96" width="34" height="26" fill="#2c4f72"/><polygon points="42,96 63,80 84,96" fill="#223e5c"/><rect x="58" y="104" width="10" height="12" fill="#f1c76a"/><rect x="58" y="104" width="10" height="12" fill="#f1c76a" opacity=".25" transform="translate(-1 -1) scale(1.1)"/></g>',w,h,LG(g,"#111b30","#1c2c47"));
 if(kind==="sea")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="60" cy="38" r="28" fill="var(--accent)" opacity=".16"/><circle cx="60" cy="38" r="18" fill="var(--accent)" opacity=".9"/>'+cloud(150,30,.8,.6)+'<path d="M0 92 Q40 78 80 92 T160 92 T240 92 T320 92 V150 H0Z" fill="var(--priC2)"/><path d="M0 112 Q40 98 80 112 T160 112 T240 112 T320 112 V150 H0Z" fill="var(--pri)" opacity=".8"/><path d="M0 132 Q40 120 80 132 T160 132 T240 132 T320 132 V150 H0Z" fill="var(--priD)" opacity=".45"/><g transform="translate(186 62)"><path d="M0 28 Q4 0 38 2 Q64 6 70 30 Q60 52 34 52 Q8 52 0 28Z" fill="var(--priD)"/><path d="M66 30 L82 14 L82 46Z" fill="var(--priD)"/><circle cx="16" cy="22" r="3" fill="#fff"/></g>',w,h,LG(g,"var(--priC)",mix("var(--priC)",70,"var(--priC2)")));
 if(kind==="paper")return SV('<rect width="300" height="150" fill="var(--priC)"/><g opacity=".95"><circle cx="70" cy="80" r="42" fill="var(--accent)"/><rect x="120" y="40" width="80" height="80" rx="22" fill="var(--pri)" transform="rotate(10 160 80)"/><path d="M214 118 L246 36 L278 118Z" fill="var(--priD)" opacity=".9"/></g>',w,h);
 if(kind==="letters")return SV('<rect width="300" height="150" fill="var(--priC)"/><g transform="rotate(-6 150 80)"><rect x="70" y="40" width="160" height="90" rx="10" fill="var(--surface)"/><path d="M70 50l80 48 80-48" fill="none" stroke="var(--pri)" stroke-width="5" stroke-linejoin="round"/></g><circle cx="238" cy="38" r="12" fill="var(--accent)"/>',w,h);
 if(kind==="branch")return SV('<rect width="300" height="150" fill="var(--priD)"/><path d="M20 128 C90 118 150 92 280 30" fill="none" stroke="var(--priC)" stroke-width="5" stroke-linecap="round"/><g fill="var(--priC2)">'+[[70,112,-30],[104,102,20],[136,90,-30],[168,76,20],[204,60,-30],[238,44,20]].map(function(l){return '<ellipse cx="'+l[0]+'" cy="'+l[1]+'" rx="16" ry="7" transform="rotate('+l[2]+' '+l[0]+' '+l[1]+')"/>';}).join("")+'</g>',w,h);
 if(kind==="day")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="226" cy="40" r="40" fill="var(--accent)" opacity=".14"/><circle cx="226" cy="40" r="26" fill="var(--accent)" opacity=".2"/><circle cx="226" cy="40" r="17" fill="var(--accent)"/>'+cloud(66,38,1,.9)+cloud(150,22,.7,.75)+'<path d="M0 98 Q60 62 130 92 T300 78 V150 H0Z" fill="var(--priC2)"/><path d="M0 116 Q80 88 160 112 T300 102 V150 H0Z" fill="var(--pri)" opacity=".9"/><path d="M120 150 Q150 128 176 118 Q196 112 232 116 Q196 122 170 132 Q150 142 148 150Z" fill="var(--surface)" opacity=".55"/><path d="M0 138 Q100 124 200 138 T300 134 V150 H0Z" fill="var(--priD)" opacity=".5"/><g fill="var(--priD)"><circle cx="46" cy="96" r="11"/><rect x="44.2" y="100" width="3.6" height="12" rx="1.8"/><circle cx="260" cy="100" r="8"/><rect x="258.4" y="103" width="3.2" height="10" rx="1.6"/></g>',w,h,LG(g,mix("var(--dpDay)",78,"#fff"),mix("var(--dpDay)",30,"#fff")));
 if(kind==="garden"){var fl=[[34,100,"accent"],[64,108,"surface"],[96,98,"accent"],[150,106,"surface"],[184,96,"accent"],[268,104,"surface"]];
  return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="46" cy="34" r="14" fill="var(--accent)" opacity=".85"/><circle cx="46" cy="34" r="24" fill="var(--accent)" opacity=".16"/><g fill="'+mix("var(--surface)",72,"var(--priC2)")+'">'+[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14].map(function(i){return '<rect x="'+(i*21+2)+'" y="62" width="14" height="48" rx="5"/>';}).join("")+'<rect x="0" y="76" width="300" height="5"/><rect x="0" y="94" width="300" height="5"/></g><path d="M0 108 Q80 96 160 106 T300 100 V150 H0Z" fill="var(--priC2)"/><path d="M0 124 Q90 108 180 122 T300 118 V150 H0Z" fill="var(--pri)" opacity=".92"/><g><circle cx="262" cy="86" r="16" fill="var(--priD)"/><circle cx="244" cy="96" r="12" fill="var(--priD)" opacity=".85"/></g><g stroke="var(--priD)" stroke-width="2.2" stroke-linecap="round">'+fl.map(function(f){return '<path d="M'+f[0]+' '+(f[1]+8)+' V'+(f[1]+30)+'"/>';}).join("")+'<path d="M222 98 V136"/></g>'+fl.map(function(f){return '<g><circle cx="'+f[0]+'" cy="'+f[1]+'" r="7.5" fill="var(--'+f[2]+')"/><circle cx="'+f[0]+'" cy="'+f[1]+'" r="3" fill="var(--priD)" opacity=".7"/></g>';}).join("")+'<g><circle cx="222" cy="86" r="14" fill="var(--accent)"/><circle cx="222" cy="86" r="6.5" fill="var(--priD)"/></g><g transform="translate(120 52)" fill="var(--accent)"><ellipse cx="-5" cy="0" rx="6" ry="4" transform="rotate(-20)"/><ellipse cx="5" cy="0" rx="6" ry="4" transform="rotate(20)"/><rect x="-1" y="-3" width="2" height="8" rx="1" fill="var(--priD)"/></g>',w,h,LG(g,"var(--priC)",mix("var(--priC)",60,"var(--surface)")));}
 if(kind==="kitchen")return SV('<rect width="300" height="150" fill="var(--priC)"/><rect y="98" width="300" height="52" fill="'+mix("var(--surface)",55,"var(--priC2)")+'"/><g stroke="var(--priC2)" stroke-width="1" opacity=".7"><path d="M0 98H300M0 112H300"/>'+[0,1,2,3,4,5,6,7,8,9,10,11,12,13].map(function(i){return '<path d="M'+(i*24)+' 98V112"/>';}).join("")+'</g><rect x="196" y="16" width="70" height="58" rx="10" fill="url(#'+g+')"/><rect x="196" y="16" width="70" height="58" rx="10" fill="none" stroke="var(--surface)" stroke-width="5"/><path d="M231 16V74M196 45H266" stroke="var(--surface)" stroke-width="3"/><circle cx="214" cy="30" r="5" fill="#fff" opacity=".7"/><g><rect x="18" y="44" width="124" height="6" rx="3" fill="var(--priD)"/><rect x="26" y="22" width="16" height="22" rx="4" fill="var(--accent)"/><rect x="26" y="18" width="16" height="5" rx="2" fill="var(--priD)"/><rect x="48" y="26" width="14" height="18" rx="4" fill="var(--surface)"/><rect x="48" y="22" width="14" height="5" rx="2" fill="var(--priD)"/><rect x="68" y="20" width="18" height="24" rx="4" fill="var(--priC2)"/><rect x="68" y="16" width="18" height="5" rx="2" fill="var(--priD)"/><rect x="92" y="28" width="12" height="16" rx="4" fill="var(--accentC)"/></g><path d="M170 0V22" stroke="var(--priD)" stroke-width="2"/><path d="M154 36Q170 14 186 36Z" fill="var(--accent)"/><circle cx="170" cy="38" r="9" fill="var(--accent)" opacity=".16"/><rect y="104" width="300" height="46" fill="var(--priD)"/><rect y="100" width="300" height="8" fill="var(--surface)"/><g><rect x="58" y="78" width="52" height="24" rx="6" fill="var(--pri)"/><rect x="54" y="74" width="60" height="7" rx="3.5" fill="var(--priD)"/><rect x="108" y="84" width="14" height="4" rx="2" fill="var(--priD)"/><path d="M72 66Q76 58 72 50M88 66Q92 56 88 46M100 66Q104 60 100 54" fill="none" stroke="var(--surface)" stroke-width="3" stroke-linecap="round" opacity=".6"/></g><g><ellipse cx="226" cy="98" rx="26" ry="5" fill="var(--priD)" opacity=".3"/><path d="M202 82Q226 108 250 82Z" fill="var(--surface)"/><circle cx="216" cy="82" r="8" fill="var(--accent)"/><circle cx="231" cy="80" r="8" fill="var(--pri)"/><circle cx="240" cy="85" r="6" fill="var(--accent)" opacity=".8"/></g>',w,h,LG(g,mix("var(--dpDay)",70,"#fff"),mix("var(--dpDay)",30,"#fff")));
 if(kind==="car")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="54" cy="36" r="24" fill="var(--accent)" opacity=".16"/><circle cx="54" cy="36" r="15" fill="var(--accent)" opacity=".92"/>'+cloud(200,30,.8,.7)+'<path d="M0 98 Q70 64 150 94 T300 84 V150 H0Z" fill="var(--priC2)"/><path d="M0 108 Q100 90 200 106 T300 100 V150 H0Z" fill="var(--pri)" opacity=".8"/><rect y="116" width="300" height="34" fill="var(--priD)"/><rect y="114" width="300" height="4" fill="var(--priC2)" opacity=".5"/><path d="M10 134H290" stroke="var(--surface)" stroke-width="3" stroke-dasharray="18 14" stroke-linecap="round" opacity=".8"/><g transform="translate(84 66)"><path d="M0 46Q0 32 14 30L32 12Q38 6 48 6H82Q94 6 100 17L110 30Q124 32 124 46V56H0Z" fill="var(--accent)"/><path d="M36 14L22 30H60V10H46Q40 10 36 14ZM66 10V30H100L92 18Q88 10 80 10Z" fill="'+mix("var(--surface)",80,"var(--priC)")+'"/><circle cx="46" cy="24" r="6" fill="var(--priD)"/><circle cx="82" cy="22" r="7" fill="var(--priD)" opacity=".9"/><rect x="0" y="42" width="124" height="5" fill="var(--priD)" opacity=".18"/><circle cx="118" cy="44" r="4" fill="#fff6c8"/><g><circle cx="30" cy="58" r="13" fill="var(--priD)"/><circle cx="30" cy="58" r="5.5" fill="var(--surface)"/><circle cx="96" cy="58" r="13" fill="var(--priD)"/><circle cx="96" cy="58" r="5.5" fill="var(--surface)"/></g></g>',w,h,LG(g,mix("var(--dpDay)",74,"#fff"),mix("var(--dpDay)",30,"#fff")));
 if(kind==="classroom")return SV('<rect width="300" height="150" fill="var(--priC)"/><rect y="112" width="300" height="38" fill="var(--priC2)"/><rect y="110" width="300" height="3" fill="var(--priD)" opacity=".25"/><rect x="34" y="18" width="156" height="76" rx="7" fill="var(--priD)"/><rect x="34" y="18" width="156" height="76" rx="7" fill="none" stroke="'+mix("var(--accent)",70,"var(--priC2)")+'" stroke-width="5"/><g fill="none" stroke="var(--surface)" stroke-width="2.5" stroke-linecap="round" opacity=".85"><circle cx="66" cy="50" r="12"/><path d="M92 62Q104 38 118 56T146 46"/><path d="M62 78H120"/><path d="M142 70l12-12 12 12z" fill="var(--surface)" fill-opacity=".25"/></g><rect x="56" y="94" width="76" height="5" rx="2.5" fill="var(--accent)"/><rect x="214" y="22" width="56" height="64" rx="8" fill="url(#'+g+')"/><rect x="214" y="22" width="56" height="64" rx="8" fill="none" stroke="var(--surface)" stroke-width="4"/><path d="M242 22V86M214 54H270" stroke="var(--surface)" stroke-width="2.5"/><path d="M204 24Q212 40 214 60V24Z" fill="var(--accent)" opacity=".8"/><g>'+[[48,0],[150,1]].map(function(d){return '<g><rect x="'+d[0]+'" y="108" width="64" height="9" rx="4" fill="'+(d[1]?"var(--pri)":"var(--accent)")+'"/><rect x="'+(d[0]+6)+'" y="117" width="5" height="22" rx="2" fill="var(--priD)"/><rect x="'+(d[0]+53)+'" y="117" width="5" height="22" rx="2" fill="var(--priD)"/><rect x="'+(d[0]+14)+'" y="100" width="14" height="8" rx="2" fill="var(--surface)"/><rect x="'+(d[0]+32)+'" y="98" width="12" height="10" rx="2" fill="var(--priD)" opacity=".8"/></g>';}).join("")+'</g>',w,h,LG(g,mix("var(--dpDay)",70,"#fff"),mix("var(--dpDay)",30,"#fff")));
 if(kind==="bedroom")return SV('<rect width="300" height="150" fill="var(--priC)"/><rect y="114" width="300" height="36" fill="var(--priC2)"/><path d="M214 84V46a28 28 0 0156 0V84Z" fill="url(#'+g+')"/><path d="M214 84V46a28 28 0 0156 0V84Z" fill="none" stroke="var(--surface)" stroke-width="4"/><circle cx="256" cy="44" r="10" fill="#f7efc8"/><circle cx="260" cy="41" r="9" fill="var(--dpNight)"/><g fill="#fff"><circle cx="228" cy="38" r="1.4"/><circle cx="240" cy="54" r="1.1" opacity=".7"/><circle cx="232" cy="68" r="1.2" opacity=".8"/></g><path d="M198 20Q208 52 204 86H196V20Z" fill="var(--accent)" opacity=".75"/><ellipse cx="124" cy="138" rx="78" ry="8" fill="var(--accentC)"/><g><rect x="22" y="58" width="12" height="70" rx="5" fill="var(--priD)"/><rect x="30" y="84" width="158" height="32" rx="11" fill="var(--surface)"/><rect x="62" y="78" width="130" height="42" rx="13" fill="var(--pri)"/><path d="M62 92H190" stroke="var(--priD)" stroke-width="2" opacity=".35"/><rect x="36" y="72" width="42" height="20" rx="10" fill="var(--surface2)"/><rect x="36" y="72" width="42" height="20" rx="10" fill="none" stroke="var(--line)"/><rect x="34" y="116" width="6" height="14" rx="2" fill="var(--priD)"/><rect x="178" y="116" width="6" height="14" rx="2" fill="var(--priD)"/><g fill="var(--accentC)"><circle cx="104" cy="74" r="9"/><circle cx="98" cy="66" r="4"/><circle cx="110" cy="66" r="4"/></g><circle cx="102" cy="73" r="1.2" fill="var(--priD)"/><circle cx="107" cy="73" r="1.2" fill="var(--priD)"/></g><circle cx="150" cy="100" r="0" fill="none"/><g><rect x="196" y="104" width="54" height="8" rx="3" fill="var(--priD)"/><rect x="202" y="112" width="6" height="22" rx="2" fill="var(--priD)"/><rect x="238" y="112" width="6" height="22" rx="2" fill="var(--priD)"/><circle cx="222" cy="86" r="30" fill="var(--accent)" opacity=".16"/><path d="M212 100L216 82H228L232 100Z" fill="var(--accent)"/><rect x="220" y="100" width="4" height="4" fill="var(--priD)"/></g>',w,h,LG(g,"var(--dpNight)",mix("var(--dpNight)",70,"var(--dpBed)")));
 if(kind==="park")return SV('<rect width="300" height="150" fill="url(#'+g+')"/>'+cloud(60,28,.9,.8)+cloud(190,18,.7,.65)+'<path d="M0 90 Q70 62 140 88 T300 78 V150 H0Z" fill="var(--priC2)"/><path d="M0 104 Q90 84 180 102 T300 96 V150 H0Z" fill="var(--pri)" opacity=".9"/><path d="M0 130 Q100 110 200 128 T300 122 V150 H0Z" fill="var(--priD)" opacity=".45"/><path d="M96 150Q124 126 154 120Q196 112 244 118Q190 124 160 134Q138 144 140 150Z" fill="var(--surface)" opacity=".6"/><g><rect x="44" y="64" width="9" height="52" rx="4" fill="'+mix("var(--priD)",60,"#6b4a2f")+'"/><circle cx="48" cy="52" r="26" fill="var(--priD)"/><circle cx="30" cy="66" r="16" fill="var(--priD)" opacity=".9"/><circle cx="66" cy="64" r="17" fill="var(--pri)"/><circle cx="46" cy="40" r="12" fill="var(--pri)" opacity=".7"/></g><g stroke="var(--priD)" stroke-width="3.5" stroke-linecap="round"><path d="M180 44H262M184 44L174 122M258 44L268 122"/></g><g stroke="var(--surface)" stroke-width="1.6" opacity=".9"><path d="M200 44V96M226 44V104"/></g><rect x="190" y="96" width="20" height="5" rx="2.5" fill="var(--accent)"/><rect x="216" y="104" width="20" height="5" rx="2.5" fill="var(--accent)"/><g><rect x="128" y="108" width="34" height="5" rx="2" fill="var(--priD)"/><rect x="130" y="100" width="30" height="4" rx="2" fill="var(--priD)" opacity=".8"/><rect x="132" y="113" width="3" height="10" fill="var(--priD)"/><rect x="155" y="113" width="3" height="10" fill="var(--priD)"/></g>',w,h,LG(g,mix("var(--dpDay)",74,"#fff"),mix("var(--dpDay)",30,"#fff")));
 if(kind==="twohouses"||kind==="houses"||kind==="home-two-houses")return SV('<rect width="300" height="150" fill="url(#'+g+')"/><circle cx="44" cy="30" r="12" fill="var(--accent)" opacity=".9"/><circle cx="44" cy="30" r="20" fill="var(--accent)" opacity=".14"/>'+cloud(236,28,.8,.7)+'<path d="M0 104Q80 90 150 102T300 98V150H0Z" fill="var(--priC2)"/><path d="M0 124Q100 108 200 124T300 120V150H0Z" fill="var(--pri)" opacity=".85"/><g><rect x="34" y="68" width="62" height="42" rx="3" fill="var(--pri)"/><polygon points="28,70 65,42 102,70" fill="var(--priD)"/><rect x="58" y="84" width="14" height="26" rx="4" fill="var(--surface)"/><rect x="40" y="78" width="12" height="12" rx="3" fill="var(--priC)"/><rect x="78" y="78" width="12" height="12" rx="3" fill="var(--priC)"/><rect x="80" y="48" width="8" height="16" fill="var(--priD)"/></g><g><rect x="196" y="62" width="70" height="48" rx="3" fill="var(--accent)"/><polygon points="190,64 231,34 272,64" fill="'+mix("var(--accent)",55,"var(--priD)")+'"/><rect x="224" y="82" width="15" height="28" rx="4" fill="var(--surface)"/><rect x="204" y="74" width="13" height="13" rx="3" fill="var(--accentC)"/><rect x="246" y="74" width="13" height="13" rx="3" fill="var(--accentC)"/></g><path d="M65 112Q110 134 150 122T231 112" fill="none" stroke="var(--surface)" stroke-width="4" stroke-linecap="round" stroke-dasharray="1 9" opacity=".95"/><path d="M96 36Q150 6 196 34" fill="none" stroke="var(--surface)" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="1 7" opacity=".8"/><path d="M150 40C150 40 138 32 138 24a6 6 0 0112-2 6 6 0 0112 2c0 8-12 16-12 16z" transform="translate(-6 -2)" fill="var(--accent)"/><g fill="var(--priD)"><circle cx="150" cy="104" r="8"/><rect x="148.5" y="108" width="3" height="10" rx="1.5"/></g>',w,h,LG(g,"var(--priC)",mix("var(--priC)",60,"var(--surface)")));
 return SV('<rect width="300" height="150" fill="var(--priC)"/>',w,h);
};
OB.SCENES="hills night sea paper letters branch day garden kitchen car classroom bedroom park twohouses".split(" ");
OB.logo=function(sz){sz=sz||28;return '<svg viewBox="0 0 32 32" width="'+sz+'" height="'+sz+'" aria-hidden="true" focusable="false"><rect width="32" height="32" rx="9" fill="var(--pri)"/><path d="M8 24C8 14 13 9 24 8c-1 11-6 16-16 16z" fill="var(--onPri)" opacity=".95"/><path d="M8 24L17 15" stroke="var(--pri)" stroke-width="1.6" stroke-linecap="round"/></svg>';};

/* spot illustrations: 96 x 96, a soft plate, palette aware. No trophies, stars or scores (P2). */
var SP={
 family:'<rect x="19" y="45" width="26" height="33" rx="13" fill="var(--pri)"/><circle cx="32" cy="33" r="10" fill="var(--pri)"/><rect x="51" y="45" width="26" height="33" rx="13" fill="var(--accent)"/><circle cx="64" cy="33" r="10" fill="var(--accent)"/><rect x="39" y="58" width="18" height="22" rx="9" fill="var(--priD)"/><circle cx="48" cy="52" r="8" fill="var(--priD)"/><path d="M14 82H82" stroke="var(--priD)" stroke-width="3" stroke-linecap="round" opacity=".35"/>',
 houses:'<rect x="14" y="48" width="30" height="28" rx="3" fill="var(--pri)"/><polygon points="10,50 29,32 48,50" fill="var(--priD)"/><rect x="25" y="60" width="8" height="16" rx="2.5" fill="var(--surface)"/><rect x="52" y="42" width="30" height="34" rx="3" fill="var(--accent)"/><polygon points="48,44 67,26 86,44" fill="'+mix("var(--accent)",55,"var(--priD)")+'"/><rect x="63" y="58" width="8" height="18" rx="2.5" fill="var(--surface)"/><path d="M29 24Q48 8 67 20" fill="none" stroke="var(--priD)" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="1 6"/><path d="M48 24c0 0-7-4-7-9a3.6 3.6 0 017-1.4 3.6 3.6 0 017 1.4c0 5-7 9-7 9z" fill="var(--accent)"/><path d="M10 80H86" stroke="var(--priD)" stroke-width="3" stroke-linecap="round" opacity=".3"/>',
 envelope:'<rect x="14" y="26" width="68" height="46" rx="9" fill="var(--surface)" stroke="var(--pri)" stroke-width="4"/><path d="M16 32L48 54 80 32" fill="none" stroke="var(--pri)" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/><circle cx="48" cy="56" r="8" fill="var(--accent)"/><path d="M44 60C44 54 47 52 52 52 52 57 49 60 44 60Z" fill="var(--surface)"/>',
 key:'<g transform="rotate(-35 48 48)"><circle cx="30" cy="48" r="15" fill="none" stroke="var(--pri)" stroke-width="8"/><rect x="42" y="44" width="40" height="9" rx="4.5" fill="var(--pri)"/><rect x="62" y="52" width="7" height="12" rx="2.5" fill="var(--pri)"/><rect x="73" y="52" width="7" height="8" rx="2.5" fill="var(--pri)"/><circle cx="30" cy="48" r="3.4" fill="var(--accent)"/></g>',
 shield:'<path d="M48 12L77 23V46C77 66 65 78 48 85 31 78 19 66 19 46V23Z" fill="var(--pri)"/><path d="M48 12L77 23V46C77 66 65 78 48 85Z" fill="var(--priD)" opacity=".35"/><path d="M35 48l9 9 17-18" fill="none" stroke="var(--onPri)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>',
 lock:'<path d="M33 45V35a15 15 0 0130 0V45" fill="none" stroke="var(--priD)" stroke-width="7" stroke-linecap="round"/><rect x="24" y="44" width="48" height="36" rx="10" fill="var(--pri)"/><circle cx="48" cy="58" r="5.5" fill="var(--onPri)"/><rect x="46" y="60" width="4" height="10" rx="2" fill="var(--onPri)"/>',
 phone:'<rect x="29" y="11" width="38" height="74" rx="11" fill="var(--priD)"/><rect x="33" y="19" width="30" height="58" rx="5" fill="var(--surface)"/><rect x="37" y="26" width="21" height="13" rx="6.5" fill="var(--priC2)"/><rect x="40" y="45" width="19" height="13" rx="6.5" fill="var(--pri)"/><circle cx="48" cy="68" r="4" fill="var(--accent)"/><rect x="42" y="14" width="12" height="3" rx="1.5" fill="var(--priC2)" opacity=".6"/>',
 tablet:'<rect x="9" y="22" width="78" height="52" rx="11" fill="var(--priD)"/><rect x="15" y="28" width="66" height="40" rx="5" fill="var(--surface)"/><circle cx="32" cy="46" r="9" fill="var(--accent)"/><rect x="48" y="36" width="26" height="8" rx="4" fill="var(--priC2)"/><rect x="48" y="50" width="20" height="8" rx="4" fill="var(--pri)"/>',
 video:'<rect x="11" y="26" width="52" height="44" rx="11" fill="var(--pri)"/><path d="M67 40L86 29V67L67 56Z" fill="var(--priD)"/><path d="M30 38L46 48 30 58Z" fill="var(--onPri)" stroke="var(--onPri)" stroke-width="3" stroke-linejoin="round"/>',
 mic:'<rect x="37" y="12" width="22" height="38" rx="11" fill="var(--pri)"/><path d="M27 42a21 21 0 0042 0" fill="none" stroke="var(--priD)" stroke-width="6" stroke-linecap="round"/><rect x="45" y="64" width="6" height="14" rx="3" fill="var(--priD)"/><rect x="33" y="77" width="30" height="7" rx="3.5" fill="var(--priD)"/><path d="M44 22H52M44 29H52" stroke="var(--onPri)" stroke-width="3" stroke-linecap="round" opacity=".7"/>',
 leaf:'<path d="M18 74C18 40 40 18 78 18C78 56 56 78 18 74Z" fill="var(--pri)"/><path d="M48 46L78 18C78 56 56 78 18 74Z" fill="var(--priD)" opacity=".28"/><path d="M22 70L58 34" stroke="var(--onPri)" stroke-width="2.6" stroke-linecap="round" opacity=".85"/><circle cx="22" cy="22" r="3.5" fill="var(--accent)"/><circle cx="80" cy="66" r="3" fill="var(--accent)"/><circle cx="66" cy="10" r="2.5" fill="var(--priD)"/><circle cx="12" cy="52" r="2.5" fill="var(--priD)"/><circle cx="84" cy="40" r="2" fill="var(--accent)" opacity=".7"/>'
};
OB.SPOTS=Object.keys(SP);
OB.spot=function(kind,size,o){o=o||{};size=size||96;
 var plate=o.plate===false?"":'<rect width="96" height="96" rx="28" fill="'+(o.tone==="accent"?"var(--accentC)":"var(--priC)")+'"/>';
 return '<svg class="spot" viewBox="0 0 96 96" width="'+size+'" height="'+size+'" aria-hidden="true" focusable="false">'+plate+(SP[kind]||SP.leaf)+'</svg>';};

/* ------------------------------------------------------------ components -- */
function esc(s){return String(s==null?"":s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];});}
OB.esc=esc;
var _uid=0;function uid(p){return (p||"u")+(++_uid);}
var N=OB.n=function(i){return i?' data-n="'+i+'"':"";};
OB.sr=function(t){return '<span class="sr">'+esc(t)+'</span>';};
OB.sb=function(t){return '<div class="sb"><span>'+(t||"7:42")+'</span><span class="sbi">'+ico("wifi",13,2)+'<i class="bat"></i></span></div>';};
OB.top=function(o){o=o||{};
 return '<div class="top">'+(o.back?'<button type="button" class="cbtn" aria-label="Back"'+N(o.nb)+'>'+ico("chevL",20,2)+'</button>':(o.logo?OB.logo(28):""))+
 '<div class="ttl">'+(o.eyebrow?'<small>'+esc(o.eyebrow)+'</small>':"")+'<b>'+esc(o.title||"")+'</b></div>'+(o.right||"")+'</div>';};
OB.page=function(inner,o){o=o||{};return '<div class="scroll'+(o.cls?" "+o.cls:"")+'"><div class="col">'+inner+'</div></div>'+(o.tab||"");};
OB.card=function(inner,cls,n){return '<div class="card'+(cls?" "+cls:"")+'"'+N(n)+'>'+inner+'</div>';};
OB.chip=function(text,o){o=o||{};return '<span class="chip'+(o.tone?" "+o.tone:"")+(o.sm?" sm":"")+'">'+(o.ic?ico(o.ic,o.sm?12:14,2):"")+esc(text)+'</span>';};
OB.btn=function(text,o){o=o||{};return '<button type="button" class="btn '+(o.kind||"pri")+(o.full?" full":"")+(o.size?" "+o.size:"")+'"'+(o.disabled?" disabled":"")+(o.label?' aria-label="'+esc(o.label)+'"':"")+N(o.n)+'>'+(o.ic?ico(o.ic,o.size==="lg"?22:18,2):"")+esc(text)+'</button>';};
OB.iconBtn=function(ic,o){o=o||{};return '<button type="button" class="cbtn'+(o.kind?" "+o.kind:"")+'" aria-label="'+esc(o.label||ic)+'"'+N(o.n)+'>'+ico(ic,o.sz||20,2)+'</button>';};
OB.row=function(o){var act=o.go||o.act;return '<div class="row'+(o.tone?" "+o.tone:"")+'"'+(act?' role="button" tabindex="0"':"")+N(o.n)+'>'+(o.ic?'<span class="ricon">'+ico(o.ic,20,1.9)+'</span>':"")+(o.av?o.av:"")+
 '<span class="rtxt"><b>'+esc(o.title)+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+'</span>'+(o.trail||"")+(o.go?'<span class="go">'+ico("chevR",16,2)+'</span>':"")+'</div>';};
OB.field=function(label,val,o){o=o||{};return '<label class="field"'+N(o.n)+'><small>'+esc(label)+'</small><span class="fv">'+(o.ic?ico(o.ic,18,1.9):"")+'<b>'+(val||'<i class="ph">'+esc(o.ph||"")+'</i>')+'</b></span></label>';};
OB.seg=function(items,a,n){return '<div class="seg" role="radiogroup"'+N(n)+'>'+items.map(function(x,i){return '<span role="radio" aria-checked="'+(i===a)+'" tabindex="'+(i===a?0:-1)+'" class="'+(i===a?"on":"")+'">'+esc(x)+'</span>';}).join("")+'</div>';};
OB.toggle=function(on,o){o=o||{};return '<span class="tgl'+(on?" on":"")+'" role="switch" aria-checked="'+(!!on)+'" tabindex="0"'+(o.label?' aria-label="'+esc(o.label)+'"':"")+'><i></i></span>';};
OB.avatar=function(l,o){o=o||{};var s=o.size||40;return '<span class="av'+(o.ring?" ring":"")+(o.tone?" "+o.tone:"")+'" role="img" aria-label="'+esc(o.label||l)+'" style="width:'+s+'px;height:'+s+'px;font-size:'+Math.round(s*.42)+'px">'+esc(l)+(o.status?'<i class="avs '+o.status+'"></i>':"")+'</span>';};
OB.banner=function(tone,text,ic,n){return '<div class="banner '+tone+'" role="'+(tone==="bad"?"alert":"status")+'"'+N(n)+'>'+ico(ic||"info",18,2)+'<span>'+text+'</span></div>';};
OB.sectionLabel=function(t,right){return '<div class="sl"><span>'+esc(t)+'</span>'+(right||"")+'</div>';};
OB.progress=function(p,tone){return '<div class="prog'+(tone?" "+tone:"")+'" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+p+'"><i style="width:'+p+'%"></i></div>';};
OB.tabbar=function(items,a){return '<nav class="tabbar" aria-label="Main">'+items.map(function(x,i){return '<span role="link" tabindex="0"'+(i===a?' aria-current="page"':"")+' class="'+(i===a?"on":"")+'">'+ico(x[0],22,i===a?2.1:1.8)+'<small>'+esc(x[1])+'</small></span>';}).join("")+'</nav>';};
OB.tile=function(tier,o){
 if(tier==="hero")return '<div class="tile hero" role="button" tabindex="0"'+N(o.n)+'><div class="tbg">'+OB.scene(o.scene||"hills",300,150)+'</div><div class="tin"><span class="tic">'+ico(o.ic,26,1.8)+'</span><span class="ttx"><b>'+esc(o.title)+'</b><small>'+esc(o.sub||"")+'</small></span>'+(o.badge?'<span class="tbd">'+esc(o.badge)+'</span>':"")+'</div></div>';
 if(tier==="feat")return '<div class="tile feat'+(o.tone?" "+o.tone:"")+'" role="button" tabindex="0"'+N(o.n)+'><span class="tic">'+ico(o.ic,24,1.9)+'</span><span class="ttx"><b>'+esc(o.title)+'</b><small>'+esc(o.sub||"")+'</small></span>'+(o.badge?'<span class="tbd">'+esc(o.badge)+'</span>':"")+'</div>';
 return '<div class="tile std" role="button" tabindex="0"'+N(o.n)+'><span class="tic">'+ico(o.ic,22,1.9)+'</span><b>'+esc(o.title)+'</b></div>';
};
/* the day ribbon: bands coloured by day-part; the overlap band is the semantic green */
OB.ribbon=function(o){o=o||{};var bands=o.bands||[["dpNight",0,24],["dpMorning",24,38],["dpDay",38,60],["dpAfternoon",60,72],["dpEvening",72,86],["dpBed",86,92],["dpNight",92,100]];
 return '<div class="ribbon" role="img" aria-label="Day ribbon"'+N(o.n)+'><div class="rb">'+bands.map(function(b){return '<i style="left:'+b[1]+'%;width:'+(b[2]-b[1])+'%;background:var(--'+b[0]+')"></i>';}).join("")+(o.overlap?'<i class="ov" style="left:'+o.overlap[0]+'%;width:'+o.overlap[1]+'%"></i>':"")+'<u class="now" style="left:'+(o.now||31)+'%"></u></div><div class="rt"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>12a</span></div></div>';};
OB.dual=function(o){return '<div class="dual"'+N(o.n)+'><div class="d1"><small>'+esc(o.l1||"Ivy, her time")+'</small><b>'+esc(o.t1||"7:42 AM")+'</b><span>'+esc(o.s1||"Before school")+'</span></div><div class="d2"><small>'+esc(o.l2||"Dad, his time")+'</small><b>'+esc(o.t2||"1:42 AM")+'</b><span>'+esc(o.s2||"Asleep")+'</span></div></div>';};
OB.bubble=function(txt,me,time){return '<div class="bub '+(me?"me":"them")+'"><span>'+esc(txt)+'</span>'+(time?'<small>'+esc(time)+'</small>':"")+'</div>';};
OB.keypad=function(){var k=[7,3,9,1,5,0,8,2,6,4];return '<div class="kp">'+k.map(function(n){return '<button type="button" aria-label="'+n+'">'+n+'</button>';}).join("")+'</div>';};
OB.dots=function(n,f){var s="";for(var i=0;i<n;i++)s+='<i class="'+(i<f?"f":"")+'"></i>';return '<div class="pdots" role="img" aria-label="'+f+' of '+n+' entered">'+s+'</div>';};
OB.speak=function(t){return '<button type="button" class="speak" aria-label="Hear it">'+ico("volume",20,2)+(t?'<span>'+esc(t)+'</span>':"")+'</button>';};
OB.sheet=function(inner){return '<div class="scrim"></div><div class="sheet" role="dialog" aria-modal="true"><i class="grab"></i>'+inner+'</div>';};
OB.empty=function(ic,t,s){return '<div class="empty"><span>'+ico(ic,28,1.6)+'</span><b>'+esc(t)+'</b><small>'+esc(s||"")+'</small></div>';};
OB.board=function(n,cells){var s='<div class="board" style="grid-template-columns:repeat('+n+',1fr)">';for(var i=0;i<n*n;i++){var c=cells&&cells[i];s+='<i class="'+((Math.floor(i/n)+i%n)%2?"d":"")+'">'+(c||"")+'</i>';}return s+'</div>';};
OB.piece=function(c){return '<b class="pc '+c+'"></b>';};

/* ===================================================== ROUND 2 components == */
/* ---- controls ---- */
OB.segmented=function(items,a,o){o=o||{};
 return '<div class="seg2'+(o.full===false?"":" full")+(o.sm?" sm":"")+'" role="radiogroup"'+(o.label?' aria-label="'+esc(o.label)+'"':"")+N(o.n)+'>'+items.map(function(x,i){
  var it=typeof x==="string"?{l:x}:x;
  return '<span role="radio" aria-checked="'+(i===a)+'" tabindex="'+(i===a?0:-1)+'" class="'+(i===a?"on":"")+'">'+(it.ic?ico(it.ic,16,2):"")+'<em>'+esc(it.l)+'</em>'+(it.count!=null?'<u>'+esc(it.count)+'</u>':"")+'</span>';}).join("")+'</div>';};
OB.filterChip=function(text,o){o=o||{};
 return '<button type="button" class="fchip'+(o.on?" on":"")+'" aria-pressed="'+(!!o.on)+'"'+N(o.n)+'>'+(o.on?ico("check",14,2.4):(o.ic?ico(o.ic,14,2):""))+'<span>'+esc(text)+'</span>'+(o.count!=null?'<u>'+esc(o.count)+'</u>':"")+'</button>';};
OB.filterChips=function(items,active,o){o=o||{};var set=Array.isArray(active)?active:[active];
 return '<div class="fchips'+(o.wrap?" wrap":"")+'" role="group"'+(o.label?' aria-label="'+esc(o.label)+'"':"")+'>'+items.map(function(x,i){var it=typeof x==="string"?{l:x}:x;return OB.filterChip(it.l,{on:set.indexOf(i)>=0,ic:it.ic,count:it.count});}).join("")+'</div>';};
OB.check=function(on){return '<span class="chk'+(on?" on":"")+'" role="checkbox" aria-checked="'+(!!on)+'" tabindex="0">'+(on?ico("check",14,3):"")+'</span>';};
OB.radio=function(on){return '<span class="rad'+(on?" on":"")+'" role="radio" aria-checked="'+(!!on)+'" tabindex="0"><i></i></span>';};
OB.slider=function(p,o){o=o||{};p=Math.max(0,Math.min(100,p));var mn=o.min==null?0:o.min,mx=o.max==null?100:o.max;
 return '<span class="sld" role="slider" tabindex="0" aria-valuemin="'+mn+'" aria-valuemax="'+mx+'" aria-valuenow="'+Math.round(mn+(mx-mn)*p/100)+'"'+(o.text?' aria-valuetext="'+esc(o.text)+'"':"")+(o.label?' aria-label="'+esc(o.label)+'"':"")+'><b style="width:'+p+'%"></b><i style="left:'+p+'%"></i></span>';};
function ctlRow(o,ctl,kind){return '<div class="row ctl'+(o.tone?" "+o.tone:"")+'" data-kind="'+kind+'"'+N(o.n)+'>'+(o.ic?'<span class="ricon">'+ico(o.ic,20,1.9)+'</span>':"")+'<span class="rtxt"><b>'+esc(o.title)+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+'</span>'+ctl+'</div>';}
OB.toggleRow=function(o){return ctlRow(o,OB.toggle(o.on,{label:o.title}),"toggle");};
OB.radioRow=function(o){return ctlRow(o,OB.radio(o.on),"radio");};
OB.checkRow=function(o){return ctlRow(o,OB.check(o.on),"check");};
OB.sliderRow=function(o){return '<div class="ctl-slider"'+N(o.n)+'><div class="row" style="padding:0">'+(o.ic?'<span class="ricon">'+ico(o.ic,20,1.9)+'</span>':"")+'<span class="rtxt"><b>'+esc(o.title)+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+'</span>'+(o.text?'<span class="chip pri sm tnum">'+esc(o.text)+'</span>':"")+'</div>'+OB.slider(o.value==null?50:o.value,{label:o.title,text:o.text})+((o.l||o.r)?'<div class="sld-ends"><span>'+esc(o.l||"")+'</span><span>'+esc(o.r||"")+'</span></div>':"")+'</div>';};
OB.formField=function(o){o=o||{};var id=o.id||uid("ff"),hid=id+"-h",st=o.error?" err":(o.focus?" focus":"")+(o.disabled?" dis":"");
 return '<div class="ff'+st+'"'+N(o.n)+'><label for="'+id+'">'+esc(o.label)+(o.req?'<span class="req" aria-hidden="true"> *</span>':"")+'</label>'+
  '<div class="fc">'+(o.ic?ico(o.ic,18,1.9):"")+'<input id="'+id+'" type="'+(o.type||"text")+'" value="'+esc(o.value||"")+'" placeholder="'+esc(o.ph||"")+'"'+(o.req?" required":"")+(o.disabled?" disabled":"")+(o.error?' aria-invalid="true"':"")+((o.hint||o.error)?' aria-describedby="'+hid+'"':"")+'>'+(o.suffix?'<span class="sfx">'+esc(o.suffix)+'</span>':"")+(o.error?ico("warn",18,2):"")+'</div>'+
  ((o.hint||o.error)?'<small id="'+hid+'" class="fh">'+(o.error?ico("warn",13,2.2)+esc(o.error):esc(o.hint))+'</small>':"")+'</div>';};
OB.pinPad=function(o){o=o||{};var d=o.digits||[7,3,9,1,5,8,2,6,4],tot=o.total||4;
 var keys=d.map(function(n){return '<button type="button" aria-label="'+n+'">'+n+'</button>';}).join("");
 var last=(o.bio?'<button type="button" class="alt" aria-label="Use fingerprint">'+ico("fingerprint",26,1.8)+'</button>':'<span></span>')+(o.zero?'<button type="button" aria-label="0">0</button>':'<span></span>')+'<button type="button" class="alt" aria-label="Delete">'+ico("backspace",26,1.8)+'</button>';
 return '<div class="pinpad">'+(o.title?'<b class="pp-t">'+esc(o.title)+'</b>':"")+(o.sub?'<small class="pp-s">'+esc(o.sub)+'</small>':"")+OB.dots(tot,o.filled||0)+'<div class="kp"'+N(o.n)+'>'+keys+last+'</div></div>';};

/* ---- identity ---- */
OB.avatarStack=function(list,o){o=o||{};var s=o.size||32,max=o.max||4,shown=list.slice(0,max),more=list.length-shown.length;
 return '<span class="avstack" role="img" aria-label="'+esc(o.label||(list.length+" people"))+'" style="--s:'+s+'px">'+shown.map(function(x){var l=Array.isArray(x)?x[0]:x,t=Array.isArray(x)?x[1]:"";return OB.avatar(l,{size:s,tone:t,label:l});}).join("")+(more>0?'<span class="av more" style="width:'+s+'px;height:'+s+'px;font-size:'+Math.round(s*.36)+'px">+'+more+'</span>':"")+'</span>';};

/* ---- status and feedback ---- */
var STAT={queued:["clock","Queued","info"],sent:["check","Sent","pri"],delivered:["check2","Delivered","pri"],watched:["eye","Watched","ok"],failed:["warn","Failed","bad"],banked:["hourglass","Banked","warn"]};
OB.status=function(kind,text,o){o=o||{};var d=STAT[kind]||STAT.sent;return '<span class="stat-pill '+d[2]+(o.sm?" sm":"")+'" data-k="'+kind+'">'+ico(d[0],o.sm?12:14,2.2)+esc(text||d[1])+'</span>';};
OB.notice=function(o){o=o||{};var t=o.tone||"info";
 return '<div class="notice '+t+'" role="'+(t==="bad"?"alert":"status")+'"'+N(o.n)+'><span class="nic">'+ico(o.ic||({ok:"check",warn:"warn",bad:"warn",info:"info",pri:"leaf"})[t]||"info",20,2)+'</span><span class="ntx">'+(o.title?'<b>'+esc(o.title)+'</b>':"")+(o.text?'<span>'+o.text+'</span>':"")+(o.action?'<button type="button" class="nact">'+esc(o.action)+'</button>':"")+'</span>'+(o.dismiss?'<button type="button" class="ndis" aria-label="Dismiss">'+ico("x",16,2.2)+'</button>':"")+'</div>';};
OB.offlineBanner=function(o){o=o||{};return '<div class="offline" role="status">'+ico("wifioff",20,2)+'<span class="ntx"><b>'+esc(o.text||"You are offline")+'</b><small>'+esc(o.sub||"Messages are kept safe and will go when you are back.")+'</small></span>'+(o.action?'<button type="button" class="nact">'+esc(o.action)+'</button>':"")+'</div>';};
OB.toast=function(text,o){o=o||{};return '<div class="toast'+(o.tone?" "+o.tone:"")+(o.inline?" inline":"")+'" role="status" aria-live="polite">'+(o.ic?ico(o.ic,18,2):"")+'<span>'+esc(text)+'</span>'+(o.action?'<button type="button" class="tact">'+esc(o.action)+'</button>':"")+'</div>';};
OB.emptyState=function(o){o=o||{};return '<div class="empty2">'+OB.spot(o.spot||"leaf",96)+'<b>'+esc(o.title||"")+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+(o.action?OB.btn(o.action,{kind:"tonal"}):"")+'</div>';};
OB.errorState=function(o){o=o||{};return '<div class="empty2 errs" role="alert"><span class="eplate">'+ico("warn",30,1.7)+'</span><b>'+esc(o.title||"That did not work")+'</b><small>'+esc(o.sub||"Nothing was lost. Try again in a moment.")+'</small>'+(o.action===false?"":OB.btn(o.action||"Try again",{kind:"tonal",ic:"refresh"}))+(o.detail?'<code class="mono dtl">'+esc(o.detail)+'</code>':"")+'</div>';};
OB.skeleton=function(kind,n){n=n||1;var s="";
 for(var i=0;i<n;i++){
  if(kind==="card")s+='<div class="skel-card" aria-hidden="true"><i class="sk w40"></i><i class="sk w90"></i><i class="sk w70"></i></div>';
  else if(kind==="text")s+='<i class="sk w'+([90,100,60][i%3])+'" aria-hidden="true"></i>';
  else if(kind==="tile")s+='<div class="skel-tile" aria-hidden="true"><i class="sk circ"></i><i class="sk w60"></i></div>';
  else if(kind==="hero")s+='<div class="skel-hero" aria-hidden="true"></div>';
  else s+='<div class="skel-row" aria-hidden="true"><i class="sk circ"></i><span><i class="sk w60"></i><i class="sk w40"></i></span></div>';}
 return '<div class="skel" role="status" aria-busy="true">'+OB.sr("Loading")+s+'</div>';};
OB.permission=function(o){o=o||{};var id=uid("pm");
 return '<div class="perm card" role="group" aria-labelledby="'+id+'"'+N(o.n)+'><span class="pic">'+ico(o.ic||"camera",28,1.8)+'</span><b id="'+id+'">'+esc(o.title||"Allow the camera?")+'</b><p>'+esc(o.body||"So she can show Dad what she made.")+'</p>'+
  (o.why&&o.why.length?'<ul>'+o.why.map(function(w){return '<li>'+ico("check",14,2.4)+'<span>'+esc(w)+'</span></li>';}).join("")+'</ul>':"")+
  '<div class="btns">'+OB.btn(o.deny||"Not now",{kind:"ghost"})+OB.btn(o.allow||"Allow",{})+'</div></div>';};

/* ---- layers ---- */
OB.bottomSheet=function(o){o=o||{};var id=uid("bs");
 return '<div class="scrim"></div><div class="sheet'+(o.detent==="full"?" full":"")+'" role="dialog" aria-modal="true"'+(o.title?' aria-labelledby="'+id+'"':"")+'><i class="grab"></i>'+((o.title||o.close)?'<div class="sh-h">'+(o.title?'<b id="'+id+'">'+esc(o.title)+'</b>':"<span></span>")+(o.close?'<button type="button" class="cbtn sm" aria-label="Close">'+ico("x",16,2.2)+'</button>':"")+'</div>':"")+'<div class="sh-b">'+(o.inner||"")+'</div>'+(o.actions?'<div class="btns">'+o.actions+'</div>':"")+'</div>';};
OB.modal=function(o){o=o||{};var id=uid("md");
 return '<div class="scrim"></div><div class="modal '+(o.tone||"")+'" role="dialog" aria-modal="true" aria-labelledby="'+id+'">'+(o.ic?'<span class="mic">'+ico(o.ic,26,1.8)+'</span>':"")+'<b id="'+id+'">'+esc(o.title||"")+'</b>'+(o.body?'<p>'+esc(o.body)+'</p>':"")+'<div class="m-act'+(o.stack?" stack":"")+'">'+(o.actions||"")+'</div></div>';};

/* ---- lists and flow ---- */
OB.swipe=function(rowHtml,o){o=o||{};var acts=o.actions||[{l:"Delete",ic:"trash",tone:"bad"}],w=acts.length*72,peek=o.open?w:22;
 return '<div class="swipe" style="--w:'+w+'px;--peek:'+peek+'px"><div class="sw-main">'+rowHtml+'</div><div class="sw-act">'+acts.map(function(a){return '<button type="button" class="'+(a.tone||"")+'" aria-label="'+esc(a.l)+'">'+ico(a.ic||"more",18,2)+'<small>'+esc(a.l)+'</small></button>';}).join("")+'</div></div>';};
OB.stepper=function(total,active,o){o=o||{};var s="";for(var i=1;i<=total;i++)s+='<i class="'+(i<active?"done":i===active?"cur":"")+'"></i>';
 return '<div class="stepper" role="progressbar" aria-valuemin="1" aria-valuemax="'+total+'" aria-valuenow="'+active+'" aria-label="Step '+active+' of '+total+'"'+N(o.n)+'>'+s+'</div>';};
OB.steps=function(labels,active){return '<ol class="steps">'+labels.map(function(l,i){var st=i<active?"done":i===active?"cur":"";return '<li class="'+st+'"'+(i===active?' aria-current="step"':"")+'><b>'+(i<active?ico("check",14,3):(i+1))+'</b><span>'+esc(l)+'</span></li>';}).join("")+'</ol>';};
OB.kv=function(rows,o){o=o||{};return '<dl class="kvl'+(o.ruled===false?"":" ruled")+'">'+rows.map(function(r){return '<div><dt>'+esc(r[0])+'</dt><dd>'+(r[2]?r[1]:esc(r[1]))+'</dd></div>';}).join("")+'</dl>';};
OB.divider=function(t){return t?'<div class="hdiv"><i></i><span>'+esc(t)+'</span><i></i></div>':'<hr class="hdiv0">';};
OB.stat=function(o){o=o||{};return '<div class="stat"'+N(o.n)+'>'+(o.ic?'<span class="sic">'+ico(o.ic,18,2)+'</span>':"")+'<small>'+esc(o.label||"")+'</small><b class="tnum">'+esc(o.value)+(o.unit?'<u>'+esc(o.unit)+'</u>':"")+'</b>'+(o.note?'<span class="snote">'+esc(o.note)+'</span>':"")+'</div>';};
OB.timeline=function(items,o){o=o||{};return '<ol class="tl"'+N(o.n)+'>'+items.map(function(it){var st=it.state||"done";return '<li class="'+st+(it.tone?" "+it.tone:"")+'"'+(st==="now"?' aria-current="step"':"")+'><span class="tn">'+(it.ic?ico(it.ic,15,2):(st==="done"?ico("check",14,3):""))+'</span><span class="tb"><b>'+esc(it.title)+'</b>'+(it.sub?'<small>'+esc(it.sub)+'</small>':"")+'</span>'+(it.time?'<time class="tnum">'+esc(it.time)+'</time>':"")+'</li>';}).join("")+'</ol>';};
function hh(x){var h=Math.floor(x),m=Math.round((x-h)*60),ap=h>=12?"p":"a",h12=h%12||12;return h12+(m?":"+(m<10?"0":"")+m:"")+ap;}
OB.scheduleBlock=function(o){o=o||{};return '<div class="sblock '+(o.tone||"pri")+'" role="group" aria-label="'+esc(o.title||"")+'"><b>'+esc(o.title||"")+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+(o.s!=null?'<time class="tnum">'+hh(o.s)+' to '+hh(o.e)+'</time>':"")+'</div>';};
OB.schedule=function(blocks,o){o=o||{};var f=o.from==null?7:o.from,t=o.to==null?20:o.to,hH=o.hourH||40,hrs="";
 for(var i=f;i<=t;i++)hrs+='<div class="sh" style="top:'+((i-f)*hH)+'px"><span class="tnum">'+hh(i)+'</span><i></i></div>';
 return '<div class="sched" style="height:'+((t-f)*hH+14)+'px"'+N(o.n)+'>'+hrs+'<div class="sbl">'+blocks.map(function(b){var cols=b.cols||1,c=b.col||0;return '<div class="sb-abs" style="top:'+((b.s-f)*hH+1)+'px;height:'+((b.e-b.s)*hH-3)+'px;left:'+(c*100/cols)+'%;width:calc('+(100/cols)+'% - 4px)">'+OB.scheduleBlock(b)+'</div>';}).join("")+(o.now!=null?'<u class="snow" style="top:'+((o.now-f)*hH)+'px"></u>':"")+'</div></div>';};
var MON=["January","February","March","April","May","June","July","August","September","October","November","December"],DOW=["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
OB.dayCell=function(n,o){o=o||{};var t=o.tone||"";var lab=o.label||(n+(o.today?", today":"")+(t==="a"?", Mom’s house":t==="b"?", Dad’s house":t==="mix"?", handover day":""));
 return '<button type="button" class="dc'+(o.dim?" dim":"")+(o.today?" today":"")+(o.sel?" sel":"")+(t?" "+t:"")+'" aria-label="'+esc(lab)+'"'+(o.sel?' aria-pressed="true"':"")+(o.today?' aria-current="date"':"")+'><span class="tnum">'+n+'</span>'+(o.dot?'<i class="dd"></i>':"")+'</button>';};
OB.calMonth=function(o){o=o||{};var y=o.y==null?2026:o.y,m=o.m==null?10:o.m,lead=o.lead||0,first=new Date(y,m,1).getDay(),dim=new Date(y,m+1,0).getDate(),pad=(first-lead+7)%7,marks=o.marks||{},names=o.names||{a:"Mom’s house",b:"Dad’s house"};
 var hd="";for(var i=0;i<7;i++){var d=(i+lead)%7;hd+='<span role="columnheader" aria-label="'+DOW[d]+'">'+DOW[d].charAt(0)+'</span>';}
 var cells="",prev=new Date(y,m,0).getDate();for(var p=0;p<pad;p++)cells+=OB.dayCell(prev-pad+p+1,{dim:true});
 for(var d2=1;d2<=dim;d2++){var mk=marks[d2]||"";cells+=OB.dayCell(d2,{today:o.today===d2,sel:o.sel===d2,tone:mk==="ev"?"":mk,dot:mk==="ev"||(o.dots&&o.dots.indexOf(d2)>=0)});}
 var tot=pad+dim,tail=(7-tot%7)%7;for(var q=1;q<=tail;q++)cells+=OB.dayCell(q,{dim:true});
 return '<div class="cal"'+N(o.n)+' role="group" aria-label="'+(o.label||MON[m]+" "+y)+'"><div class="cal-h"><button type="button" class="cbtn sm" aria-label="Previous month">'+ico("chevL",16,2.2)+'</button><b>'+(o.label||MON[m]+" "+y)+'</b><button type="button" class="cbtn sm" aria-label="Next month">'+ico("chevR",16,2.2)+'</button></div><div class="cal-w" role="row">'+hd+'</div><div class="cal-g" role="grid">'+cells+'</div>'+(o.legend===false?"":'<div class="cal-l"><span><i class="a"></i>'+esc(names.a)+'</span><span><i class="b"></i>'+esc(names.b)+'</span><span><i class="mix"></i>Handover</span></div>')+'</div>';};

/* ---- media ---- */
OB.recordBtn=function(o){o=o||{};var st=o.state||"idle",sz=o.size||88;
 return '<div class="rec '+st+'" style="--sz:'+sz+'px"'+N(o.n)+'><button type="button" class="rb2" aria-pressed="'+(st==="rec")+'" aria-label="'+esc(o.label||(st==="rec"?"Stop recording":st==="done"?"Record again":"Start recording"))+'"><span class="ring"></span><span class="core">'+(st==="rec"?"":st==="done"?ico("refresh",30,2):ico("mic",30,1.9))+'</span></button>'+(o.time?'<time class="mono tnum rtime">'+esc(o.time)+'</time>':"")+'</div>';};
OB.waveform=function(o){o=o||{};var n=o.bars||36,seed=(o.seed==null?7:o.seed)>>>0||7,pl=o.played==null?0:o.played,s="",hh2=o.h||44;
 for(var i=0;i<n;i++){seed=(seed*1664525+1013904223)>>>0;var env=Math.sin((i+.5)/n*Math.PI),r=((seed>>>8)&255)/255,v=Math.max(.14,Math.min(1,.18+env*.5+r*.38));s+='<i class="'+(i/n<pl?"p":"")+'" style="height:'+Math.round(v*100)+'%"></i>';}
 return '<div class="wave'+(o.tone?" "+o.tone:"")+'" role="img" aria-label="'+esc(o.label||"Audio")+'" style="height:'+hh2+'px">'+s+'</div>';};
OB.player=function(o){o=o||{};var pr=o.progress==null?35:o.progress,pl=!!o.playing;
 return '<div class="player"'+N(o.n)+' role="group" aria-label="'+esc(o.title||"Video")+'"><div class="pv-bg">'+OB.scene(o.scene||"day",300,170)+'</div><div class="pv-shade"></div>'+
  (pl?"":'<button type="button" class="pv-play" aria-label="Play">'+ico("play",30,2)+'</button>')+
  (o.captions!==false&&o.caption?'<div class="pv-cap"><span>'+esc(o.caption)+'</span></div>':"")+
  '<div class="pv-bar"><button type="button" class="pv-b" aria-label="'+(pl?"Pause":"Play")+'">'+ico(pl?"pause":"play",18,2)+'</button><span class="pv-scrub" role="slider" tabindex="0" aria-label="Seek" aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+pr+'"><b style="width:'+pr+'%"></b><i style="left:'+pr+'%"></i></span><time class="mono tnum">'+esc(o.time||"0:24")+' / '+esc(o.dur||"1:10")+'</time><button type="button" class="pv-b'+(o.captions!==false?" on":"")+'" aria-pressed="'+(o.captions!==false)+'" aria-label="Captions">'+ico("cc",18,1.9)+'</button><button type="button" class="pv-b" aria-label="Full screen">'+ico("expand",16,2)+'</button></div></div>';};
OB.qrCard=function(o){o=o||{};var code=o.code||"OLIVE-7K4P",n=21,seed=2166136261;
 for(var i=0;i<code.length;i++){seed^=code.charCodeAt(i);seed=Math.imul(seed,16777619)>>>0;}
 function fin(x,y){return (x<7&&y<7)||(x>=n-7&&y<7)||(x<7&&y>=n-7);}
 var cells="";for(var y=0;y<n;y++)for(var x=0;x<n;x++){
  if(fin(x,y)){var fx=x>=n-7?x-(n-7):x,fy=y>=n-7?y-(n-7):y,on=(fx===0||fx===6||fy===0||fy===6)||(fx>=2&&fx<=4&&fy>=2&&fy<=4);if(on)cells+='<rect x="'+x+'" y="'+y+'" width="1.02" height="1.02"/>';}
  else{seed=(Math.imul(seed,1103515245)+12345)>>>0;if((seed>>>16)&1)cells+='<rect x="'+x+'" y="'+y+'" width="1.02" height="1.02"/>';}}
 return '<div class="qrc"'+N(o.n)+'><div class="qr" role="img" aria-label="Pairing code, sample only"><svg viewBox="-1 -1 '+(n+2)+' '+(n+2)+'" shape-rendering="crispEdges" aria-hidden="true" focusable="false"><rect x="-1" y="-1" width="'+(n+2)+'" height="'+(n+2)+'" fill="#fff"/><g fill="#14201a">'+cells+'</g></svg></div><div class="qr-t">'+(o.title?'<b>'+esc(o.title)+'</b>':"")+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+'<code class="mono qcode">'+esc(code)+'</code>'+(o.expires?'<small class="qexp">'+ico("clock",12,2)+esc(o.expires)+'</small>':"")+'</div>'+(o.copy===false?"":'<button type="button" class="btn tonal sm">'+ico("copy",16,2)+'Copy code</button>')+'</div>';};

/* ----------------------------------------------------- registry + frames -- */
OB.def=function(id,shell,title,o){o=o||{};OB.screens.push({id:id,shell:shell,title:title,grp:o.grp||"",desc:o.desc||"",since:o.since||"",wide:!!o.wide,notes:o.notes||[],r:o.r,cover:o.cover||null,isNew:!!o.isNew,refs:o.refs||""});};
OB.byId=function(id){for(var i=0;i<OB.screens.length;i++)if(OB.screens[i].id===id)return OB.screens[i];return null;};
OB.render=function(s,form){
 form=form||OB.form;
 var inner=(form==="cover"&&s.cover)?s.cover():s.r({form:form});
 return '<div class="ob '+s.shell+" f-"+form+'" style="'+OB.theme(OB.palette,OB.mode)+'">'+inner+'</div>';
};
/* content sizes in px (the frame adds 14 for the bezel). phone, cover and tablet are contracts the screens rely on. */
OB.FORMS={phone:[300,600],cover:[260,560],tablet:[700,440],foldMain:[520,620],foldTabletop:[520,600]};
OB.frame=function(s,form,scale){
 form=form||OB.form;scale=scale||1;
 var sz=OB.FORMS[form]||OB.FORMS.phone,W=sz[0],Hh=sz[1];
 return '<div class="fw" style="width:'+Math.round((W+14)*scale)+'px;height:'+Math.round((Hh+14)*scale)+'px"><div class="fd '+form+'" style="width:'+(W+14)+'px;height:'+(Hh+14)+'px;transform:scale('+scale+')">'+OB.render(s,form)+'</div></div>';
};
})();
