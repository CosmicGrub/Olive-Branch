/* Olive Branch overhaul: design kit. Themes, icons, illustration and component builders.
   Everything returns HTML strings so the screen files stay declarative. */
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
 var sd=SEEDS[pal]||SEEDS.olive,t=hsl(sd.seed),h=t[0],s=Math.max(26,Math.min(70,t[1])),dark=mode==="dark",v={};
 if(!dark){
  v.bg=H(h,22,97);v.surface="#ffffff";v.surface2=H(h,20,94);v.surface3=H(h,18,90);v.outline=H(h,14,85);
  v.ink=H(h,28,11);v.ink2=H(h,12,36);v.ink3=H(h,9,41);
  v.pri=H(h,s,Math.min(36,Math.max(26,t[2])));v.priD=H(h,s,24);v.onPri="#ffffff";
  v.priC=H(h,Math.min(60,s*1.25),90);v.onPriC=H(h,s,20);v.priC2=H(h,Math.min(60,s*1.2),82);
  v.accent=H(h+28,62,58);v.accentC=H(h+28,70,90);
  v.shadow1="0 1px 2px hsl("+Math.round(h)+" 30% 10% / .06),0 4px 14px hsl("+Math.round(h)+" 30% 10% / .07)";
  v.shadow2="0 2px 4px hsl("+Math.round(h)+" 30% 10% / .06),0 14px 34px hsl("+Math.round(h)+" 30% 10% / .14)";
  v.ok="#237a52";v.okC="#dcf3e6";v.warn="#8f6100";v.warnC="#fcefcf";v.bad="#b3322a";v.badC="#fbe3e0";v.info="#245f9c";v.infoC="#dceafa";
 }else{
  v.bg=H(h,20,8);v.surface=H(h,17,12);v.surface2=H(h,16,16);v.surface3=H(h,15,21);v.outline=H(h,13,25);
  v.ink=H(h,18,94);v.ink2=H(h,10,74);v.ink3=H(h,8,58);
  v.pri=H(h,Math.min(60,s+6),70);v.priD=H(h,s,60);v.onPri=H(h,30,10);
  v.priC=H(h,Math.min(45,s),24);v.onPriC=H(h,40,90);v.priC2=H(h,Math.min(45,s),30);
  v.accent=H(h+28,60,66);v.accentC=H(h+28,40,26);
  v.shadow1="0 1px 2px rgba(0,0,0,.35),0 4px 14px rgba(0,0,0,.25)";v.shadow2="0 2px 4px rgba(0,0,0,.4),0 14px 34px rgba(0,0,0,.45)";
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
 footprint:'<circle cx="9" cy="7" r="2.5"/><circle cx="15.5" cy="10" r="2.5"/><path d="M7 12c-1 3 0 7 2 8s3-1 3-3-.5-5-5-5zM14 15c-1 2 0 5 2 5s3-3 1-5z"/>'
};
OB.ICONS=Object.keys(IC);
OB.ico=function(n,sz,sw){sz=sz||22;return '<svg class="ico" viewBox="0 0 24 24" width="'+sz+'" height="'+sz+'" fill="none" stroke="currentColor" stroke-width="'+(sw||1.8)+'" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(IC[n]||IC.info)+'</svg>';};
var ico=OB.ico;

/* ---------------------------------------------------------- illustration -- */
/* Scenes use theme variables, so every palette gets its own illustration colours. */
OB.scene=function(kind,w,h){
 w=w||300;h=h||150;
 var S='<svg class="scene" viewBox="0 0 300 150" width="'+w+'" height="'+h+'" preserveAspectRatio="xMidYMid slice" aria-hidden="true">';
 if(kind==="hills")return S+'<defs><linearGradient id="hg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--priC2)"/><stop offset="1" stop-color="var(--priC)"/></linearGradient></defs><rect width="300" height="150" fill="url(#hg)"/><circle cx="236" cy="42" r="22" fill="var(--accent)" opacity=".9"/><circle cx="236" cy="42" r="34" fill="var(--accent)" opacity=".18"/><path d="M0 104 Q70 66 140 98 T300 84 V150 H0Z" fill="var(--priC2)"/><path d="M0 124 Q90 92 170 120 T300 112 V150 H0Z" fill="var(--pri)" opacity=".85"/><g fill="var(--priD)"><circle cx="64" cy="98" r="13"/><rect x="62" y="104" width="4" height="14" rx="2"/><circle cx="92" cy="104" r="9"/><rect x="90" y="108" width="3.4" height="11" rx="1.7"/></g></svg>';
 if(kind==="night")return S+'<rect width="300" height="150" fill="#16223a"/><g fill="#fff">'+[[30,24],[70,50],[120,18],[180,40],[250,22],[270,70],[210,64],[150,60]].map(function(p,i){return '<circle cx="'+p[0]+'" cy="'+p[1]+'" r="'+(i%3?1:1.8)+'" opacity="'+(i%2?.55:.9)+'"/>';}).join("")+'</g><circle cx="222" cy="46" r="24" fill="#f7efc8"/><circle cx="232" cy="40" r="22" fill="#16223a"/><path d="M0 118 Q80 92 160 116 T300 108 V150 H0Z" fill="#1f3550"/><path d="M0 134 Q110 112 200 132 T300 128 V150 H0Z" fill="#274463"/><g><rect x="46" y="96" width="34" height="26" fill="#2c4f72"/><polygon points="42,96 63,80 84,96" fill="#223e5c"/><rect x="58" y="104" width="10" height="12" fill="#f1c76a"/></g></svg>';
 if(kind==="sea")return S+'<rect width="300" height="150" fill="var(--priC)"/><circle cx="60" cy="38" r="18" fill="var(--accent)" opacity=".85"/><path d="M0 92 Q40 78 80 92 T160 92 T240 92 T320 92 V150 H0Z" fill="var(--priC2)"/><path d="M0 112 Q40 98 80 112 T160 112 T240 112 T320 112 V150 H0Z" fill="var(--pri)" opacity=".8"/><g transform="translate(186 62)"><path d="M0 28 Q4 0 38 2 Q64 6 70 30 Q60 52 34 52 Q8 52 0 28Z" fill="var(--priD)"/><path d="M66 30 L82 14 L82 46Z" fill="var(--priD)"/><circle cx="16" cy="22" r="3" fill="#fff"/></g></svg>';
 if(kind==="paper")return S+'<rect width="300" height="150" fill="var(--priC)"/><g opacity=".95"><circle cx="70" cy="80" r="42" fill="var(--accent)"/><rect x="120" y="40" width="80" height="80" rx="22" fill="var(--pri)" transform="rotate(10 160 80)"/><path d="M214 118 L246 36 L278 118Z" fill="var(--priD)" opacity=".9"/></g></svg>';
 if(kind==="letters")return S+'<rect width="300" height="150" fill="var(--priC)"/><g transform="rotate(-6 150 80)"><rect x="70" y="40" width="160" height="90" rx="10" fill="var(--surface)"/><path d="M70 50l80 48 80-48" fill="none" stroke="var(--pri)" stroke-width="5" stroke-linejoin="round"/></g><circle cx="238" cy="38" r="12" fill="var(--accent)"/></svg>';
 if(kind==="branch")return S+'<rect width="300" height="150" fill="var(--priD)"/><path d="M20 128 C90 118 150 92 280 30" fill="none" stroke="var(--priC)" stroke-width="5" stroke-linecap="round"/><g fill="var(--priC2)">'+[[70,112,-30],[104,102,20],[136,90,-30],[168,76,20],[204,60,-30],[238,44,20]].map(function(l){return '<ellipse cx="'+l[0]+'" cy="'+l[1]+'" rx="16" ry="7" transform="rotate('+l[2]+' '+l[0]+' '+l[1]+')"/>';}).join("")+'</g></svg>';
 return S+'<rect width="300" height="150" fill="var(--priC)"/></svg>';
};
OB.logo=function(sz){sz=sz||28;return '<svg viewBox="0 0 32 32" width="'+sz+'" height="'+sz+'" aria-hidden="true"><rect width="32" height="32" rx="9" fill="var(--pri)"/><path d="M8 24C8 14 13 9 24 8c-1 11-6 16-16 16z" fill="var(--onPri)" opacity=".95"/><path d="M8 24L17 15" stroke="var(--pri)" stroke-width="1.6" stroke-linecap="round"/></svg>';};
var HEX=function(c){return c;};

/* ------------------------------------------------------------ components -- */
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];});}
OB.esc=esc;
var N=OB.n=function(i){return i?' data-n="'+i+'"':"";};
OB.sb=function(t){return '<div class="sb"><span>'+(t||"7:42")+'</span><span class="sbi">'+ico("wifi",13,2)+'<i class="bat"></i></span></div>';};
OB.top=function(o){o=o||{};
 return '<div class="top">'+(o.back?'<button class="cbtn" aria-label="Back"'+N(o.nb)+'>'+ico("chevL",20,2)+'</button>':(o.logo?OB.logo(28):""))+
 '<div class="ttl">'+(o.eyebrow?'<small>'+esc(o.eyebrow)+'</small>':"")+'<b>'+esc(o.title||"")+'</b></div>'+(o.right||"")+'</div>';};
OB.page=function(inner,o){o=o||{};return '<div class="scroll'+(o.cls?" "+o.cls:"")+'"><div class="col">'+inner+'</div></div>'+(o.tab||"");};
OB.card=function(inner,cls,n){return '<div class="card'+(cls?" "+cls:"")+'"'+N(n)+'>'+inner+'</div>';};
OB.chip=function(text,o){o=o||{};return '<span class="chip'+(o.tone?" "+o.tone:"")+(o.sm?" sm":"")+'">'+(o.ic?ico(o.ic,o.sm?12:14,2):"")+esc(text)+'</span>';};
OB.btn=function(text,o){o=o||{};return '<button class="btn '+(o.kind||"pri")+(o.full?" full":"")+(o.size?" "+o.size:"")+'"'+N(o.n)+'>'+(o.ic?ico(o.ic,o.size==="lg"?22:18,2):"")+esc(text)+'</button>';};
OB.iconBtn=function(ic,o){o=o||{};return '<button class="cbtn'+(o.kind?" "+o.kind:"")+'" aria-label="'+esc(o.label||ic)+'"'+N(o.n)+'>'+ico(ic,o.sz||20,2)+'</button>';};
OB.row=function(o){return '<div class="row'+(o.tone?" "+o.tone:"")+'"'+N(o.n)+'>'+(o.ic?'<span class="ricon">'+ico(o.ic,20,1.9)+'</span>':"")+(o.av?o.av:"")+
 '<span class="rtxt"><b>'+esc(o.title)+'</b>'+(o.sub?'<small>'+esc(o.sub)+'</small>':"")+'</span>'+(o.trail||"")+(o.go?'<span class="go">'+ico("chevR",16,2)+'</span>':"")+'</div>';};
OB.field=function(label,val,o){o=o||{};return '<label class="field"'+N(o.n)+'><small>'+esc(label)+'</small><span class="fv">'+(o.ic?ico(o.ic,18,1.9):"")+'<b>'+(val||'<i class="ph">'+esc(o.ph||"")+'</i>')+'</b></span></label>';};
OB.seg=function(items,a,n){return '<div class="seg"'+N(n)+'>'+items.map(function(x,i){return '<span class="'+(i===a?"on":"")+'">'+esc(x)+'</span>';}).join("")+'</div>';};
OB.toggle=function(on){return '<span class="tgl'+(on?" on":"")+'"><i></i></span>';};
OB.avatar=function(l,o){o=o||{};var s=o.size||40;return '<span class="av'+(o.ring?" ring":"")+(o.tone?" "+o.tone:"")+'" style="width:'+s+'px;height:'+s+'px;font-size:'+Math.round(s*.42)+'px">'+esc(l)+'</span>';};
OB.banner=function(tone,text,ic,n){return '<div class="banner '+tone+'"'+N(n)+'>'+ico(ic||"info",18,2)+'<span>'+text+'</span></div>';};
OB.sectionLabel=function(t,right){return '<div class="sl"><span>'+esc(t)+'</span>'+(right||"")+'</div>';};
OB.progress=function(p,tone){return '<div class="prog'+(tone?" "+tone:"")+'"><i style="width:'+p+'%"></i></div>';};
OB.tabbar=function(items,a){return '<nav class="tabbar">'+items.map(function(x,i){return '<span class="'+(i===a?"on":"")+'">'+ico(x[0],22,i===a?2.1:1.8)+'<small>'+esc(x[1])+'</small></span>';}).join("")+'</nav>';};
OB.tile=function(tier,o){
 if(tier==="hero")return '<div class="tile hero"'+N(o.n)+'><div class="tbg">'+OB.scene(o.scene||"hills",300,150)+'</div><div class="tin"><span class="tic">'+ico(o.ic,26,1.8)+'</span><span class="ttx"><b>'+esc(o.title)+'</b><small>'+esc(o.sub||"")+'</small></span>'+(o.badge?'<span class="tbd">'+esc(o.badge)+'</span>':"")+'</div></div>';
 if(tier==="feat")return '<div class="tile feat'+(o.tone?" "+o.tone:"")+'"'+N(o.n)+'><span class="tic">'+ico(o.ic,24,1.9)+'</span><span class="ttx"><b>'+esc(o.title)+'</b><small>'+esc(o.sub||"")+'</small></span>'+(o.badge?'<span class="tbd">'+esc(o.badge)+'</span>':"")+'</div>';
 return '<div class="tile std"'+N(o.n)+'><span class="tic">'+ico(o.ic,22,1.9)+'</span><b>'+esc(o.title)+'</b></div>';
};
/* the day ribbon: bands coloured by day-part; the overlap band is the semantic green */
OB.ribbon=function(o){o=o||{};var bands=o.bands||[["dpNight",0,24],["dpMorning",24,38],["dpDay",38,60],["dpAfternoon",60,72],["dpEvening",72,86],["dpBed",86,92],["dpNight",92,100]];
 return '<div class="ribbon"'+N(o.n)+'><div class="rb">'+bands.map(function(b){return '<i style="left:'+b[1]+'%;width:'+(b[2]-b[1])+'%;background:var(--'+b[0]+')"></i>';}).join("")+(o.overlap?'<i class="ov" style="left:'+o.overlap[0]+'%;width:'+o.overlap[1]+'%"></i>':"")+'<u class="now" style="left:'+(o.now||31)+'%"></u></div><div class="rt"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>12a</span></div></div>';};
OB.dual=function(o){return '<div class="dual"'+N(o.n)+'><div class="d1"><small>'+esc(o.l1||"Ivy, her time")+'</small><b>'+esc(o.t1||"7:42 AM")+'</b><span>'+esc(o.s1||"Before school")+'</span></div><div class="d2"><small>'+esc(o.l2||"Dad, his time")+'</small><b>'+esc(o.t2||"1:42 AM")+'</b><span>'+esc(o.s2||"Asleep")+'</span></div></div>';};
OB.bubble=function(txt,me,time){return '<div class="bub '+(me?"me":"them")+'"><span>'+esc(txt)+'</span>'+(time?'<small>'+esc(time)+'</small>':"")+'</div>';};
OB.keypad=function(){var k=[7,3,9,1,5,0,8,2,6,4];return '<div class="kp">'+k.map(function(n){return '<button>'+n+'</button>';}).join("")+'</div>';};
OB.dots=function(n,f){var s="";for(var i=0;i<n;i++)s+='<i class="'+(i<f?"f":"")+'"></i>';return '<div class="pdots">'+s+'</div>';};
OB.speak=function(t){return '<button class="speak" aria-label="Hear it">'+ico("volume",20,2)+(t?'<span>'+esc(t)+'</span>':"")+'</button>';};
OB.sheet=function(inner){return '<div class="scrim"></div><div class="sheet"><i class="grab"></i>'+inner+'</div>';};
OB.empty=function(ic,t,s){return '<div class="empty"><span>'+ico(ic,28,1.6)+'</span><b>'+esc(t)+'</b><small>'+esc(s||"")+'</small></div>';};
OB.board=function(n,cells){var s='<div class="board" style="grid-template-columns:repeat('+n+',1fr)">';for(var i=0;i<n*n;i++){var c=cells&&cells[i];s+='<i class="'+((Math.floor(i/n)+i%n)%2?"d":"")+'">'+(c||"")+'</i>';}return s+'</div>';};
OB.piece=function(c){return '<b class="pc '+c+'"></b>';};

/* ----------------------------------------------------- registry + frames -- */
OB.def=function(id,shell,title,o){o=o||{};OB.screens.push({id:id,shell:shell,title:title,grp:o.grp||"",desc:o.desc||"",since:o.since||"",wide:!!o.wide,notes:o.notes||[],r:o.r,cover:o.cover||null,isNew:!!o.isNew,refs:o.refs||""});};
OB.byId=function(id){for(var i=0;i<OB.screens.length;i++)if(OB.screens[i].id===id)return OB.screens[i];return null;};
OB.render=function(s,form){
 form=form||OB.form;
 var inner=(form==="cover"&&s.cover)?s.cover():s.r({form:form});
 return '<div class="ob '+s.shell+" f-"+form+'" style="'+OB.theme(OB.palette,OB.mode)+'">'+inner+'</div>';
};
OB.frame=function(s,form,scale){
 form=form||OB.form;scale=scale||1;
 var W={phone:300,cover:260,tablet:700}[form],Hh={phone:600,cover:560,tablet:440}[form];
 return '<div class="fw" style="width:'+Math.round((W+14)*scale)+'px;height:'+Math.round((Hh+14)*scale)+'px"><div class="fd '+form+'" style="width:'+(W+14)+'px;height:'+(Hh+14)+'px;transform:scale('+scale+')">'+OB.render(s,form)+'</div></div>';
};
})();
