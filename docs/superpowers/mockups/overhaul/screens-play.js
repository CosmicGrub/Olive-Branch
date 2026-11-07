/* Play: games, stories, creating. Child shell unless stated. */
(function(){
"use strict";
var K=OB,I=K.ico,D=K.def;
function ctop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.right!==undefined?o.right:K.iconBtn("volume",{kind:"tonal",label:"Hear it"})});}
function gtop(title,o){o=o||{};return K.sb()+K.top({back:true,title:title,eyebrow:o.eyebrow,right:o.right||""});}
function turn(who,txt){return '<div class="chips"><span class="chip pri">'+I("users",13,2)+' '+who+'</span><span class="chip">'+txt+'</span></div>';}
function sw(){return ["#F2B705","#E8730C","#F0757E","#E056A8","#8B6BB1","#2F8FC4","#6BB8E8","#5FC9A8","#5AA84A","#8A6244","#7C8698","#2B3358"];}

D("gamePicker","child","Game picker",{grp:"Play",since:"0.17.0",
 desc:"The one screen for every choice she has: the age-gated grid above, and the checkers, chess, battleship and word-game cluster below, all behind a single “Play together” tap. The jokebook sits below as “Just for laughs”.",
 notes:[[1,"A Recommended row first, because a long grid is a decision she does not want to make."],[2,"The grid shows only what her guardian allows and her age unlocks. Nothing is greyed out as “locked”."],[3,"“Just for laughs” is part of the same door."]],
 r:function(){return ctop("Play together")+K.page(
  K.sectionLabel("Play with Dad tonight")+'<div class="grid3"'+K.n(1)+'>'+[["grid3","Tic-tac-toe","paper"],["pawn","Checkers","hills"],["puzzle","Word chain","sea"]].map(function(g){return '<div class="card" style="padding:0;overflow:hidden;text-align:center"><div style="height:72px">'+K.scene(g[2],100,72)+'</div><div style="padding:8px 4px"><b style="font-size:12.5px">'+g[1]+'</b></div></div>';}).join("")+'</div>'+
  K.sectionLabel("All games")+'<div class="grid2"'+K.n(2)+'>'+[["dice","Dots and boxes"],["target","Battleship"],["search","Word search"],["pawn","Chess"],["image","Find the thing"],["brush","Colouring"]].map(function(g){return K.tile("feat",{ic:g[0],title:g[1]});}).join("")+'</div>'+
  K.card(K.row({ic:"smile",title:"Just for laughs",sub:"Dad jokes, riddles and knock-knocks",go:true,n:3}),"tint"));}});

D("jokebook","child","Jokebook",{grp:"Play",since:"0.49.67",desc:"A fixed, hand-written library of kid-friendly jokes, behind the same Play together door.",
 notes:[[1,"The punchline waits for a tap. She chooses when to find out."],[2,"“Another one” is the only action."]],
 r:function(){return ctop("Just for laughs")+K.page(K.card('<p style="font:800 22px/1.25 var(--font-display);color:var(--ink);margin:0 0 14px"'+K.n(1)+'>What do you call a sleeping bull?</p><div class="card flat center" style="min-height:70px;padding:14px"><b style="font-size:20px;color:var(--pri)">A bulldozer!</b></div>')+K.btn("Another one",{full:true,size:"lg",ic:"refresh",n:2})+K.btn("Tell it to Dad",{kind:"tonal",full:true,size:"lg",ic:"send"}));}});

D("handicap","guardian","Handicap",{grp:"Play",since:"0.17.0",desc:"A fair game against a grown-up, tuned without telling her.",
 notes:[[1,"The guardian tunes fairness quietly. Ivy never sees a handicap label."],[2,"The default is a fair game, which is the whole point."]],
 r:function(){return K.sb()+K.top({back:true,title:"Keep it fair"})+K.page(K.banner("pri","Ivy won’t see this. It just makes the game closer.","eye",1)+K.card('<h4>Checkers with Ivy</h4><p>Tuned for a 6-year-old playing a grown-up.</p>'+K.seg(["Closer","Fair","Harder"],1,2)+'<div class="kv" style="margin-top:12px"><span>Your thinking time</span><span>Shorter</span><span>You may</span><span>Skip a capture sometimes</span></div>'));}});

D("story","child","Story game",{grp:"Play",since:"0.17.0",desc:"A turn-by-turn tale between them.",
 notes:[[1,"The last sentence is the stage. Her turn adds one more."]],
 r:function(){return ctop("Our story")+K.page(turn("Dad","just added")+K.card('<p style="font:700 18px/1.5 var(--font-body);color:var(--ink);margin:0">…and then the little boat bumped into a sleepy whale, who said “<b style="color:var(--pri)">good morning</b>.”</p>',"",1)+K.sectionLabel("What happens next?")+'<div style="display:grid;gap:8px">'+["The whale tells a secret","They sail away","The boat sneezes"].map(function(t){return K.btn(t,{kind:"tonal",full:true});}).join("")+'</div>'+K.btn("Say it myself",{kind:"ghost",ic:"mic",full:true}));}});

D("checkers","child","Checkers",{grp:"Play",since:"0.17.0",desc:"The board survives a dropped call; async by nature.",
 notes:[[1,"The board is the whole screen. Whose turn it is is one line above it."],[2,"Pieces are her colour and his, never red against black."]],
 r:function(){var cells=[];for(var i=0;i<64;i++){var r=Math.floor(i/8),c=i%8;if((r+c)%2&&r<3)cells[i]=K.piece("b");if((r+c)%2&&r>4)cells[i]=K.piece("a");}return ctop("Checkers with Dad")+K.page(turn("Your turn","Dad moved 2 hours ago")+'<div'+K.n(1)+'>'+K.board(8,cells)+'</div>'+K.btn("Undo my move",{kind:"ghost",full:true}));}});

D("battleship","child","Battleship",{grp:"Play",since:"0.17.0",desc:"Hers and his boards, never both on one screen (tab-toggle).",
 notes:[[1,"Two tabs, never both boards at once, so neither of them can peek."]],
 r:function(){var cells=[];for(var i=0;i<49;i++)cells[i]="";[8,9,10,24,31,38].forEach(function(i){cells[i]='<span style="width:70%;height:70%;border-radius:6px;background:var(--priD)"></span>';});cells[17]='<b style="color:var(--bad)">'+I("x",18,2.6)+'</b>';return ctop("Battleship")+K.page(K.seg(["My ships","Dad’s sea"],0,1)+K.board(7,cells)+K.banner("pri","Dad hasn’t found your boat yet.","info"));}});

D("wordsearch","child","Word search",{grp:"Play",since:"0.18.0",desc:"Words from her own week.",
 notes:[[1,"Words come from her own week, like “heron” and “Grandma”."]],
 r:function(){var L="HERONQAPUDLEOGNANAMXTRBSPICKLEWBAN".split("");var g="";for(var i=0;i<49;i++){g+='<span style="aspect-ratio:1;display:grid;place-items:center;font:800 14px var(--font-display);border-radius:8px;'+(i>=7&&i<12?"background:var(--priC);color:var(--onPriC)":"background:var(--surface)")+'">'+L[i%L.length]+'</span>';}return ctop("Word search",{eyebrow:"From your week"})+K.page('<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px"'+K.n(1)+'>'+g+'</div><div class="chips">'+K.chip("heron",{tone:"ok",ic:"check"})+K.chip("Nana")+K.chip("pond")+K.chip("boots")+'</div>');}});

D("chess","child","Chess",{grp:"Play",since:"0.18.0",desc:"Real rules, real engine, patient by design.",
 notes:[[1,"Patient by design: there is no clock pressure, and a move can wait a day."]],
 r:function(){var P={0:"♜",1:"♞",2:"♝",3:"♛",4:"♚",5:"♝",6:"♞",7:"♜"};var cells=[];for(var i=0;i<64;i++){var r=Math.floor(i/8),c=i%8;if(r===0)cells[i]='<span style="font-size:22px;color:#1f2a24">'+P[c]+'</span>';if(r===1)cells[i]='<span style="font-size:22px;color:#1f2a24">♟</span>';if(r===6)cells[i]='<span style="font-size:22px;color:var(--pri)">♙</span>';if(r===7)cells[i]='<span style="font-size:22px;color:var(--pri)">'+P[c].replace("♜","♖").replace("♞","♘").replace("♝","♗").replace("♛","♕").replace("♚","♔")+'</span>';}return ctop("Chess with Dad")+K.page(turn("Your turn","No hurry")+'<div'+K.n(1)+'>'+K.board(8,cells)+'</div>');}});

D("chain","child","Word chain",{grp:"Play",since:"0.18.0",desc:"A game only this product can do: it grows across custody weeks.",
 notes:[[1,"The chain keeps growing across both houses. Its length is a story, never a score."]],
 r:function(){return ctop("Our word chain")+K.page(K.card('<small class="mono" style="color:var(--ink3)">STARTED IN MARCH</small><p style="font:800 20px var(--font-display);margin:4px 0">142 words long</p>',"tint",1)+K.card(["owl → light","light → tiger","tiger → river","river → Ivy"].map(function(w,i){return K.row({av:K.avatar(i%2?"D":"I",{size:34,tone:i%2?"accent":""}),title:w});}).join(""))+K.field("Next word starts with Y","",{ph:"Type or say it",ic:"mic"}));}});

D("kim","child","Kim’s game",{grp:"Play",since:"0.18.0",desc:"Memory play with their own shared things.",
 notes:[[1,"The objects are things she and Dad have actually shared."]],
 r:function(){var o=["book","camera","heart","palette","moon","puzzle"];return ctop("What’s missing?")+K.page('<div class="grid3"'+K.n(1)+'>'+o.map(function(n,i){return '<div class="card center" style="min-height:92px;padding:12px;'+(i===3?"background:var(--surface2);border-style:dashed;box-shadow:none":"")+'">'+(i===3?'<b style="font-size:28px;color:var(--ink3)">?</b>':I(n,34,1.6))+'</div>';}).join("")+'</div>'+K.btn("Which one is gone?",{full:true,size:"lg",kind:"tonal"}));}});

D("hunt","child","Scavenger hunt",{grp:"Play",since:"0.18.0",desc:"He hides it in her world; arrival events only, no coordinates (P3).",
 notes:[[1,"Clues are words and pictures. There is no map, because there are no coordinates anywhere (P3)."]],
 r:function(){return ctop("Dad hid something")+K.page(K.banner("info","No map and no location. Just clues.","shield",1)+K.card('<h4>Clue 2</h4><p style="font-size:17px">Look where the sunshine sleeps at lunchtime.</p>')+K.btn("I found it",{full:true,size:"lg",ic:"check"})+K.btn("Show Dad where",{kind:"tonal",full:true,ic:"camera"}));}});

D("findThing","child","Find the thing",{grp:"Play",since:"0.28.0",desc:"A packed, zoomable scene: the heaviest activity, and the budget knows it.",
 notes:[[1,"The target is named, spoken, and shown as a tiny picture, so nobody has to read."]],
 r:function(){var dots="";for(var i=0;i<26;i++){dots+='<i style="position:absolute;left:'+((i*37)%88+3)+'%;top:'+((i*53)%78+6)+'%;width:'+(18+(i%4)*6)+'px;height:'+(18+(i%4)*6)+'px;border-radius:'+(i%3?"50%":"8px")+';background:'+sw()[i%12]+';opacity:.85"></i>';}return ctop("Find the kite")+K.page('<div style="position:relative;height:340px;border-radius:24px;background:var(--priC);overflow:hidden"'+K.n(1)+'>'+dots+'</div><div class="chips"><span class="chip pri">'+I("target",13,2)+' Find the blue kite</span><span class="chip">Pinch to zoom</span></div>');}});

D("colouring","child","Colouring",{grp:"Play",since:"0.28.0",desc:"Vector, cheap for what it is; her finger's motion is never shed.",
 notes:[[1,"The twelve colours are the same twelve as her palette. Tap, then tap a part."]],
 r:function(){return ctop("Colouring",{right:K.iconBtn("refresh",{kind:"tonal",label:"Undo"})})+K.page('<div style="background:#fff;border-radius:24px;padding:8px;box-shadow:var(--shadow1)"><svg viewBox="0 0 100 100" width="100%" height="230"><circle cx="50" cy="55" r="30" fill="#E8730C" stroke="#26352b" stroke-width="2.4"/><path d="M36 28 L40 10 L52 24Z M64 28 L60 10 L48 24Z" fill="#fff" stroke="#26352b" stroke-width="2.4"/><circle cx="41" cy="52" r="3.5" fill="#26352b"/><circle cx="59" cy="52" r="3.5" fill="#26352b"/><ellipse cx="50" cy="64" rx="12" ry="8" fill="#fff" stroke="#26352b" stroke-width="2.4"/></svg></div><div style="display:grid;grid-template-columns:repeat(6,1fr);gap:8px"'+K.n(1)+'>'+sw().map(function(c,i){return '<span style="aspect-ratio:1;border-radius:14px;background:'+c+';'+(i===1?"box-shadow:0 0 0 3px var(--bg),0 0 0 5px var(--ink)":"box-shadow:inset 0 -3px 0 rgba(0,0,0,.14)")+'"></span>';}).join("")+'</div>');}});

D("doodle","child","Doodle desk",{grp:"Play",since:"0.49.60",desc:"Free strokes plus six stamps. A blank canvas has no finish line, so there is no score or completion state.",
 notes:[[1,"No “done” button that implies a score. A drawing is never finished."],[2,"Six stamps, one tap each."]],
 r:function(){return ctop("Doodle desk",{right:K.iconBtn("refresh",{kind:"tonal",label:"Undo"})})+K.page('<div style="background:#fff;border-radius:24px;height:260px;box-shadow:var(--shadow1);position:relative;overflow:hidden"><svg viewBox="0 0 200 200" width="100%" height="100%"><path d="M30 130 C60 60 110 170 170 70" fill="none" stroke="var(--pri)" stroke-width="7" stroke-linecap="round"/><circle cx="150" cy="150" r="16" fill="var(--accent)"/></svg></div><div class="grid3" style="grid-template-columns:repeat(6,1fr)"'+K.n(2)+'>'+["heart","sun","moon","smile","leaf","sparkle"].map(function(n){return '<span class="card center" style="min-height:48px;padding:8px;border-radius:16px">'+I(n,22,1.8)+'</span>';}).join("")+'</div>');}});

D("snapshot","child","Photo",{grp:"Play",since:"0.39.0",desc:"A dedicated in-app photo and screenshot button, auto-uploading to her own gallery, never the device's. Screenshot is refused on the call surface.",
 notes:[[1,"A photo goes to her gallery, never her device's camera roll."],[2,"On a call the button is not offered at all."]],
 r:function(){return ctop("Photo")+K.page('<div style="height:290px;border-radius:26px;overflow:hidden;position:relative">'+K.scene("hills",300,290)+'</div><div class="center" style="min-height:0"><span class="chip ok">'+I("check",13,2.4)+' Saved to your gallery</span></div>'+K.banner("info","Photos stay in Olive. They’re never on the tablet’s camera roll.","shield",1));}});

D("library","child","Story library",{grp:"Play",since:"0.28.0",desc:"A shelf stays browsable to three hundred; past that it is a search problem a five-year-old cannot use.",
 notes:[[1,"Covers are big pictures. Search only appears when the shelf is large enough to need it."]],
 r:function(){var sc=["night","sea","hills","paper","branch","letters"];return ctop("Stories")+K.page('<div class="grid2"'+K.n(1)+'>'+sc.map(function(s,i){return '<div class="card" style="padding:0;overflow:hidden"><div style="height:100px">'+K.scene(s,150,100)+'</div><div style="padding:8px 10px"><b style="font-size:13px">'+["The owl’s night","The sea-blue whale","Hill after hill","Paper boats","The olive tree","Letters home"][i]+'</b></div></div>';}).join("")+'</div>');}});

D("theBook","child","The book",{grp:"Play",since:"0.28.0",desc:"The story they made, bound.",
 notes:[[1,"The story becomes a real book, with both names on the cover."]],
 r:function(){return ctop("Our book")+K.page('<div style="border-radius:22px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("sea",300,170)+'</div>'+K.card('<p style="font:700 18px/1.5 var(--font-body);color:var(--ink);margin:0">The little boat bumped into a sleepy whale, who said “good morning.”</p>',"",1)+'<div class="btns">'+K.btn("Back",{kind:"tonal",ic:"arrowL"})+K.btn("Next page",{ic:"arrowR"})+'</div>');}});

D("storyteller","child","Storyteller",{grp:"Play",since:"0.27.0",desc:"Text-first and nearly free, which is why she can always have it. At the Fold5's tabletop posture a reading card sits above the hinge and hint chips below.",
 notes:[[1,"The reading card is calm and large. Nothing in it moves except the one refrain."],[2,"Hints are chips under the card, so she steers the story with a tap."]],
 r:function(){return ctop("Storyteller")+K.page(K.card('<small class="mono" style="color:var(--ink3)">CHAPTER 2</small><p style="font:700 19px/1.55 var(--font-body);color:var(--ink);margin:6px 0 0">The fox looked at the moon and the moon looked right back.</p>',"",1)+K.sectionLabel("What could the fox do?")+'<div class="chips"'+K.n(2)+'>'+["Wave","Hide","Sing","Ask a question"].map(function(t){return '<span class="chip pri" style="padding:10px 14px;font-size:14px">'+t+'</span>';}).join("")+'</div>');}});

D("storySafety","guardian","Storyteller safety",{grp:"Play",since:"0.27.0",desc:"No synthetic parent voice, ever (P1). The engine writes; it does not impersonate.",
 notes:[[1,"The boundary is stated as plain commitments, not buried in terms."]],
 r:function(){return gtop("How stories stay safe")+K.page(K.card(K.row({ic:"check",title:"It writes the story",sub:"Gentle, age-appropriate, no scary turns",tone:"ok",n:1})+K.row({ic:"x",title:"It never speaks as you",sub:"No cloned voice or face of a parent, ever",tone:"bad"})+K.row({ic:"x",title:"It never asks her anything personal",tone:"bad"})+K.row({ic:"check",title:"You can read every story",tone:"ok"})));}});

D("sharedReading","child","Shared reading",{grp:"Play",since:"0.49.72",desc:"One book, two screens, his voice. Both screens are never on view at once.",
 notes:[[1,"Dad’s face is small and calm. The book leads, the person supports."],[2,"This is the surface the new Read together co-viewing mode extends."]],
 r:function(){return ctop("Reading with Dad")+K.page('<div style="position:relative;border-radius:26px;overflow:hidden">'+K.scene("night",300,190)+'<span class="av" style="position:absolute;right:12px;bottom:12px;width:54px;height:54px;background:#fff;color:var(--priD);box-shadow:var(--shadow2);font-size:22px"'+K.n(2)+'>D</span></div>'+K.card('<p style="font:700 19px/1.5 var(--font-body);color:var(--ink);margin:0">“Far above the olive grove, a small owl asked the moon a very big question.”</p>',"",1)+K.chip("Dad is reading",{tone:"ok",ic:"volume"}));}});
})();
