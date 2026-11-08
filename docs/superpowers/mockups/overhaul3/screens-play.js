/* Play: games, stories, creating. ROUND 2. Child shell unless stated. Copy is in a warm child voice, with no spec or adult words. */
(function(){
"use strict";
var K=OB,I=K.ico,E=K.esc,D=K.def,M=K.mk,N=M.N,ctop=M.ctop,gtop=M.gtop,B=M.b48;
M.css("r2-p",
".ob .rp-turn{display:flex;gap:8px;align-items:center;flex-wrap:wrap}"+
".ob .rp-chipbig{display:inline-flex;gap:8px;align-items:center;min-height:48px;padding:0 16px;border-radius:99px;background:var(--priC);color:var(--onPriC);font:700 15px/1 var(--font-body)}"+
".ob .rp-hint{display:inline-flex;align-items:center;min-height:56px;padding:0 20px;border-radius:99px;background:var(--priC);color:var(--onPriC);font:700 16px/1 var(--font-body)}"+
".ob .rp-gcard{padding:0;overflow:hidden;text-align:center}.ob .rp-gcard b{font-size:13px}"+
".ob .rp-dest{width:38%;height:38%;border-radius:50%;background:var(--ok);opacity:.75;display:block}"+
".ob .rp-pg{display:flex;gap:6px;justify-content:center}.ob .rp-pg i{width:10px;height:10px;border-radius:50%;background:var(--surface3)}.ob .rp-pg i.on{background:var(--pri);width:26px;border-radius:6px}"+
".ob .rp-cell{aspect-ratio:1;display:grid;place-items:center;font:800 15px var(--font-display);border-radius:9px;background:var(--surface)}.ob .rp-cell.f{background:var(--priC);color:var(--onPriC)}");
function turn(who,txt,n){return '<div class="rp-turn"'+K.n(n)+'><span class="chip pri">'+I("users",13,2)+' '+E(who)+'</span><span class="chip">'+E(txt)+'</span></div>';}
function sw(){return ["#F2B705","#E8730C","#F0757E","#E056A8","#8B6BB1","#2F8FC4","#6BB8E8","#5FC9A8","#5AA84A","#8A6244","#7C8698","#2B3358"];}
function three(arr){return '<div class="grid3">'+arr.map(function(b){return '<div class="tile std" style="padding:14px 4px"><span class="tic" style="width:52px;height:52px">'+I(b[0],26,1.9)+'</span><b>'+E(b[1])+'</b></div>';}).join("")+'</div>';}

D("gamePicker","child","Game picker",{grp:"Play",since:"0.17.0",
 desc:"The one door to everything she can play: the age-gated grid, then the checkers, chess, battleship and word-game cluster, all behind a single Play together tap. The jokebook sits below as Just for laughs.",
 notes:[[1,"A short row first, the games a grown-up is waiting to play with her. A long grid is a decision she does not want to make."],[2,"The grid shows only what her grown-ups allow and her age unlocks. Nothing is greyed out, locked or labelled with an age (§8.13)."],[3,"Just for laughs is part of the same door, so there is one place to go for anything playful."]],
 r:function(){return ctop("Play together")+K.page(
  K.sectionLabel("Play with "+N.a)+'<div class="grid3"'+K.n(1)+'>'+[["grid3","Tic-tac-toe","paper"],["pawn","Checkers","hills"],["puzzle","Word chain","sea"]].map(function(g){return '<div class="card rp-gcard"><div style="height:72px">'+K.scene(g[2],100,72)+'</div><div style="padding:10px 4px;min-height:48px"><b>'+g[1]+'</b></div></div>';}).join("")+'</div>'+
  K.sectionLabel("All games")+'<div class="grid2"'+K.n(2)+'>'+[["dice","Dots and boxes"],["target","Battleship"],["search","Word search"],["pawn","Chess"],["image","Find the thing"],["brush","Colouring"]].map(function(g){return K.tile("feat",{ic:g[0],title:g[1]});}).join("")+'</div>'+
  K.card(K.row({ic:"smile",title:"Just for laughs",sub:"Jokes, riddles and knock-knocks",go:true,n:3}),"tint"));}});

D("gamePicker-empty","child","Game picker, empty",{grp:"Play",since:"new",isNew:true,desc:"Nothing to play together right now. Picture first, with two doors to things that always work on her own. No locks, no list of what is missing.",
 notes:[[1,"A sleeping game box. Nothing says nothing is available, and nothing shows what was hidden or why (§8.13)."],[2,"One warm line she can have read aloud. It never mentions grown-ups, settings or age."],[3,"Two doors to things that are always there: a story and a drawing. She is never at a dead end."]],
 r:function(){return ctop("Play together")+K.page(M.cstate({scene:"sea",ic:"dice",line:"The games are having a rest.",sub:"Let’s do something else!",n1:1,n2:2,n3:3,acts:K.btn("Hear a story",{full:true,size:"lg",ic:"book"})+K.btn("Draw something",{kind:"tonal",full:true,size:"lg",ic:"brush"})}));}});

D("jokebook","child","Jokebook",{grp:"Play",since:"0.49.67",desc:"A fixed, hand-written library of kind jokes, behind the same Play together door.",
 notes:[[1,"The punchline waits for a tap. She chooses when to find out, and nothing times her."],[2,"“Another one” is the main action. Sharing is quiet and sends nothing without a tap."]],
 r:function(){return ctop("Just for laughs")+K.page(K.card('<p style="font:800 23px/1.25 var(--font-display);color:var(--ink);margin:0 0 14px"'+K.n(1)+'>What do you call a sleeping bull?</p><div class="card flat center" style="min-height:76px;padding:14px"><b style="font:800 24px var(--font-display);color:var(--pri)">A bulldozer!</b></div>')+K.btn("Another one",{full:true,size:"lg",ic:"refresh",n:2})+K.btn("Tell it to "+N.a,{kind:"tonal",full:true,size:"lg",ic:"send"}));}});

D("handicap","guardian","Handicap",{grp:"Play",since:"0.17.0",desc:"A fair game against a grown-up, tuned quietly. Grown-up shell: she never sees this.",
 notes:[[1,"The grown-up tunes fairness quietly. Ivy never sees a handicap label, a difficulty name or a hint that anything was adjusted."],[2,"The default is a fair game, which is the whole point. Closer and Harder are one tap either way."]],
 r:function(){return gtop("Keep it fair")+K.page(K.banner("pri","Ivy won’t see this. It just makes the game closer.","eye",1)+K.card('<h4>Checkers with Ivy</h4><p>Tuned for a 6-year-old playing a grown-up.</p>'+K.seg(["Closer","Fair","Harder"],1,2)+'<div class="kv" style="margin-top:12px"><span>Your thinking time</span><span>Shorter</span><span>You may</span><span>Skip a capture sometimes</span></div>'));}});

D("story","child","Story game",{grp:"Play",since:"0.17.0",desc:"A turn-by-turn tale between them.",
 notes:[[1,"The last sentence is the stage. Her turn adds one more, by tapping a choice or by saying it."],[2,"Choices are full-size buttons in plain words. She can always say her own."]],
 r:function(){return ctop("Our story")+K.page(turn(N.a,"just added")+K.card('<p style="font:700 19px/1.5 var(--font-body);color:var(--ink);margin:0">…and then the little boat bumped into a sleepy whale, who said “<b style="color:var(--pri)">good morning</b>.”</p>',"",1)+K.sectionLabel("What happens next?")+'<div style="display:grid;gap:10px"'+K.n(2)+'>'+["The whale tells a secret","They sail away","The boat sneezes"].map(function(t){return K.btn(t,{kind:"tonal",full:true});}).join("")+'</div>'+K.btn("Say it myself",{kind:"ghost",ic:"mic",full:true}));}});

D("checkers","child","Checkers",{grp:"Play",since:"0.17.0",desc:"The board is kept safe between turns, so a move can wait for a whole day.",
 notes:[[1,"The board is the screen. Whose turn it is is one line above it, in words."],[2,"Pick up a piece with one tap and only the places it can go glow. A mis-tap costs nothing."],[3,"Pieces are her colour and the other player’s, never red against black."]],
 r:function(){var cells=[];for(var i=0;i<64;i++){var r=Math.floor(i/8),c=i%8;if((r+c)%2&&r<3)cells[i]=K.piece("b");if((r+c)%2&&r>4)cells[i]=K.piece("a");}cells[40]=cells[40].replace('class="pc a"','class="pc a" style="box-shadow:0 0 0 4px var(--ok)"');cells[33]='<i class="rp-dest"></i>';
  return ctop("Checkers with "+N.a)+K.page(turn("Your turn",N.a+" moved 2 hours ago",1)+'<div'+K.n(2)+'>'+K.board(8,cells)+'</div><div'+K.n(3)+'>'+K.btn("Undo my move",{kind:"ghost",full:true})+'</div>');}});

D("battleship","child","Battleship",{grp:"Play",since:"0.17.0",desc:"Hers and theirs, never both boards on one screen (a tab toggle).",
 notes:[[1,"Two tabs, never both boards at once, so neither player can peek."]],
 r:function(){var cells=[];for(var i=0;i<49;i++)cells[i]="";[8,9,10,24,31,38].forEach(function(i){cells[i]='<span style="width:70%;height:70%;border-radius:6px;background:var(--priD)"></span>';});cells[17]='<b style="color:var(--bad)">'+I("x",18,2.6)+'</b>';return ctop("Battleship")+K.page(K.seg(["My ships",N.a+"’s sea"],0,1)+K.board(7,cells)+K.banner("pri",N.a+" hasn’t found your boat yet.","info"));}});

D("wordsearch","child","Word search",{grp:"Play",since:"0.18.0",desc:"Words from her own week.",
 notes:[[1,"The words come from her own week, like “heron” and “grandma”. Found words get a tick, never a score."]],
 r:function(){var rows=["PQXMLVB","HERONZA","BOOTSKD","GRANDMA","TPONDYU","ZKXQVMC","LDFHJWS"],g="";rows.forEach(function(r,ri){r.split("").forEach(function(ch,ci){var f=(ri===1&&ci<5);g+='<span class="rp-cell'+(f?" f":"")+'">'+ch+'</span>';});});
  return ctop("Word search",{eyebrow:"From your week"})+K.page('<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px"'+K.n(1)+'>'+g+'</div><div class="chips">'+K.chip("heron",{tone:"ok",ic:"check"})+K.chip("grandma")+K.chip("pond")+K.chip("boots")+'</div>');}});

D("chess","child","Chess",{grp:"Play",since:"0.18.0",desc:"Real rules and a real engine, patient by design.",
 notes:[[1,"Patient by design: there is no clock and a move can wait a day. The turn line says “no hurry” on purpose."]],
 r:function(){var P={0:"♜",1:"♞",2:"♝",3:"♛",4:"♚",5:"♝",6:"♞",7:"♜"};var cells=[];for(var i=0;i<64;i++){var r=Math.floor(i/8),c=i%8;if(r===0)cells[i]='<span style="font-size:22px;color:#1f2a24">'+P[c]+'</span>';if(r===1)cells[i]='<span style="font-size:22px;color:#1f2a24">♟</span>';if(r===6)cells[i]='<span style="font-size:22px;color:var(--pri)">♙</span>';if(r===7)cells[i]='<span style="font-size:22px;color:var(--pri)">'+P[c].replace("♜","♖").replace("♞","♘").replace("♝","♗").replace("♛","♕").replace("♚","♔")+'</span>';}return ctop("Chess with "+N.a)+K.page(turn("Your turn","No hurry")+'<div'+K.n(1)+'>'+K.board(8,cells)+'</div>');}});

D("chain","child","Word chain",{grp:"Play",since:"0.18.0",desc:"A game only this product can do: it grows across both homes.",
 notes:[[1,"The chain keeps growing across both homes. Its length is a story she can see, never a score or a record to beat (P2)."]],
 r:function(){return ctop("Our word chain")+K.page(K.card('<small class="rr-eb">Started in March</small><p style="font:800 22px var(--font-display);margin:4px 0">142 words long</p>',"tint",1)+K.card(["owl → light","light → tiger","tiger → river","river → Ivy"].map(function(w,i){return K.row({av:K.avatar(i%2?"M":"I",{size:40,tone:i%2?"accent":""}),title:w});}).join(""))+K.field("Next word starts with Y","",{ph:"Type or say it",ic:"mic"}));}});

D("kim","child","Kim’s game",{grp:"Play",since:"0.18.0",desc:"Memory play with things they have really shared.",
 notes:[[1,"The pictures are things she and her grown-up have actually shared. One tap on the gap is the whole answer."]],
 r:function(){var o=["book","camera","heart","palette","moon","puzzle"];return ctop("What’s missing?")+K.page('<div class="grid3"'+K.n(1)+'>'+o.map(function(n,i){return '<div class="card center" style="min-height:92px;padding:12px;'+(i===3?"background:var(--surface2);border:2.5px dashed var(--outline);box-shadow:none":"")+'">'+(i===3?'<b style="font-size:32px;color:var(--ink2)">?</b>':I(n,36,1.6))+'</div>';}).join("")+'</div>'+K.btn("Which one is gone?",{full:true,size:"lg",kind:"tonal"}));}});

D("hunt","child","Scavenger hunt",{grp:"Play",since:"0.18.0",desc:"A grown-up hides something in her world; clues are words and pictures, no coordinates (P3).",
 notes:[[1,"Clues are words and pictures. There is no map anywhere, because the product never holds a coordinate (P3)."],[2,"One clue at a time. Found-it and show-me are both full-size."]],
 r:function(){return ctop(N.a+" hid something")+K.page(K.card('<div class="row" style="padding:0 0 6px"><span class="ricon">'+I("sun",20,1.9)+'</span><b style="font:800 18px var(--font-display)"'+K.n(1)+'>Clue 2</b></div><p style="font:700 19px/1.4 var(--font-body);color:var(--ink);margin:0">Look where the sunshine sleeps at lunchtime.</p>')+K.btn("I found it",{full:true,size:"lg",ic:"check",n:2})+K.btn("Show "+N.a+" where",{kind:"tonal",full:true,ic:"camera"}));}});

D("findThing","child","Find the thing",{grp:"Play",since:"0.28.0",desc:"A packed, zoomable scene; the heaviest activity, and the budget knows it.",
 notes:[[1,"The target is spoken and shown as a small picture, so nobody has to read. Pinch to zoom."]],
 r:function(){var dots="";for(var i=0;i<26;i++){dots+='<i style="position:absolute;left:'+((i*37)%88+3)+'%;top:'+((i*53)%78+6)+'%;width:'+(20+(i%4)*6)+'px;height:'+(20+(i%4)*6)+'px;border-radius:'+(i%3?"50%":"8px")+';background:'+sw()[i%12]+';opacity:.85"></i>';}return ctop("Find the kite")+K.page('<div style="position:relative;height:340px;border-radius:26px;background:var(--priC);overflow:hidden"'+K.n(1)+'>'+dots+'</div><div class="chips"><span class="rp-chipbig">'+I("target",16,2)+' Find the blue kite</span></div>');}});

D("colouring","child","Colouring",{grp:"Play",since:"0.28.0",desc:"Vector and cheap for what it is; her finger’s motion is never shed.",
 notes:[[1,"The twelve colours are the same twelve as her colour picker. Tap one, then tap a part."]],
 r:function(){return ctop("Colouring",{right:K.iconBtn("refresh",{kind:"tonal",label:"Undo"})})+K.page('<div style="background:#fff;border-radius:26px;padding:8px;box-shadow:var(--shadow1)"><svg viewBox="0 0 100 100" width="100%" height="230"><circle cx="50" cy="55" r="30" fill="#E8730C" stroke="#26352b" stroke-width="2.4"/><path d="M36 28 L40 10 L52 24Z M64 28 L60 10 L48 24Z" fill="#fff" stroke="#26352b" stroke-width="2.4"/><circle cx="41" cy="52" r="3.5" fill="#26352b"/><circle cx="59" cy="52" r="3.5" fill="#26352b"/><ellipse cx="50" cy="64" rx="12" ry="8" fill="#fff" stroke="#26352b" stroke-width="2.4"/></svg></div><div style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:4px"'+K.n(1)+'>'+sw().map(function(c,i){return '<span style="aspect-ratio:1;border-radius:18px;background:'+c+';'+(i===1?"box-shadow:0 0 0 3px var(--bg),0 0 0 5px var(--ink)":"box-shadow:inset 0 -3px 0 rgba(0,0,0,.14)")+'"></span>';}).join("")+'</div>');}});

D("doodle","child","Doodle desk",{grp:"Play",since:"0.49.60",desc:"Free strokes plus six stamps. A blank page has no finish line, so there is no score and no done state.",
 notes:[[1,"There is no “done” button that implies a score. A drawing is never finished and never graded."],[2,"Six stamps, one tap each, each a full-size target."]],
 r:function(){return ctop("Doodle desk",{right:K.iconBtn("refresh",{kind:"tonal",label:"Undo"})})+K.page('<div style="background:#fff;border-radius:26px;height:250px;box-shadow:var(--shadow1);position:relative;overflow:hidden"'+K.n(1)+'><svg viewBox="0 0 200 200" width="100%" height="100%"><path d="M30 130 C60 60 110 170 170 70" fill="none" stroke="var(--pri)" stroke-width="7" stroke-linecap="round"/><circle cx="150" cy="150" r="16" fill="var(--accent)"/></svg></div><div style="display:grid;grid-template-columns:repeat(6,1fr);gap:6px"'+K.n(2)+'>'+["heart","sun","moon","smile","leaf","sparkle"].map(function(n){return '<span class="card center" style="min-height:48px;padding:6px;border-radius:16px">'+I(n,22,1.8)+'</span>';}).join("")+'</div>');}});

D("snapshot","child","Photo",{grp:"Play",since:"0.39.0",desc:"An in-app photo button that saves to her own gallery, never the device’s. The button is not offered on a call.",
 notes:[[1,"A photo goes to her gallery in Olive, never the device’s camera roll. She just sees “saved”."],[2,"On a call this button is not offered at all, so there is nothing to refuse."]],
 r:function(){return ctop("Photo")+K.page('<div style="height:300px;border-radius:28px;overflow:hidden;position:relative">'+K.scene("hills",300,300)+'</div><div class="center" style="min-height:0"><span class="rp-chipbig" style="background:var(--okC);color:var(--ok)"'+K.n(1)+'>'+I("check",16,2.6)+' Saved to your gallery</span></div>'+K.btn("Take another",{full:true,size:"lg",ic:"camera",n:2}));}});

D("library","child","Story library",{grp:"Play",since:"0.28.0",desc:"A shelf stays browsable to three hundred; past that it is a search problem a five-year-old cannot use.",
 notes:[[1,"Covers are big pictures with a short name. A search field appears only when the shelf is big enough to need one."]],
 r:function(){var sc=["night","sea","hills","paper","branch","letters"];return ctop("Stories")+K.page('<div class="grid2"'+K.n(1)+'>'+sc.map(function(s,i){return '<div class="card" style="padding:0;overflow:hidden"><div style="height:100px">'+K.scene(s,150,100)+'</div><div style="padding:10px;min-height:48px"><b style="font-size:14px">'+["The owl’s night","The sea-blue whale","Hill after hill","Paper boats","The olive tree","Letters home"][i]+'</b></div></div>';}).join("")+'</div>');}});

D("theBook","child","The book",{grp:"Play",since:"0.28.0",desc:"The story they made together, bound.",
 notes:[[1,"The story becomes a real book with both names on the cover. Back and Next are the only controls."]],
 r:function(){return ctop("Our book")+K.page('<div style="border-radius:24px;overflow:hidden;box-shadow:var(--shadow2)">'+K.scene("sea",300,170)+'</div>'+K.card('<p style="font:700 19px/1.5 var(--font-body);color:var(--ink);margin:0">The little boat bumped into a sleepy whale, who said “good morning.”</p>',"",1)+'<div class="rp-pg"><i></i><i class="on"></i><i></i><i></i></div><div class="btns">'+K.btn("Back",{kind:"tonal",ic:"arrowL"})+K.btn("Next page",{ic:"arrowR"})+'</div>');}});

D("storyteller","child","Storyteller",{grp:"Play",since:"0.27.0",desc:"Text-first and nearly free, which is why she can always have it. At the Fold5’s tabletop posture a reading card sits above the hinge and the hint chips below.",
 notes:[[1,"The reading card is calm and large. Nothing in it moves except the one refrain."],[2,"Hints are big chips under the card, 56 dp tall, so she steers the story with a tap."]],
 r:function(){return ctop("Storyteller")+K.page(K.card('<small class="rr-eb">Chapter 2</small><p style="font:700 20px/1.55 var(--font-body);color:var(--ink);margin:6px 0 0">The fox looked at the moon and the moon looked right back.</p>',"",1)+K.sectionLabel("What could the fox do?")+'<div class="chips" style="gap:10px"'+K.n(2)+'>'+["Wave","Hide","Sing","Ask a question"].map(function(t){return '<span class="rp-hint">'+t+'</span>';}).join("")+'</div>');}});

D("storySafety","guardian","Storyteller safety",{grp:"Play",since:"0.27.0",desc:"No synthetic parent voice, ever (P1). The engine writes; it does not impersonate. Grown-up shell.",
 notes:[[1,"The boundary is plain commitments, not terms. Green for what it does, red for what it will never do (P1)."]],
 r:function(){return gtop("How stories stay safe")+K.page(K.card(K.row({ic:"check",title:"It writes the story",sub:"Gentle, age-appropriate, no scary turns",tone:"ok",n:1})+K.row({ic:"x",title:"It never speaks as you",sub:"No cloned voice or face of a parent, ever",tone:"bad"})+K.row({ic:"x",title:"It never asks her anything personal",tone:"bad"})+K.row({ic:"check",title:"You can read every story",tone:"ok"})));}});

D("sharedReading","child","Shared reading",{grp:"Play",since:"0.49.72",desc:"One book, two screens, a real voice. Both screens are never on view at once.",
 notes:[[1,"The book leads. The other person’s face is small and calm, and the voice is a real person’s, never generated (P1)."],[2,"This is the surface the Read together co-viewing mode builds on."]],
 r:function(){return ctop("Reading with "+N.a)+K.page('<div style="position:relative;border-radius:28px;overflow:hidden">'+K.scene("night",300,190)+'<span class="av" style="position:absolute;right:12px;bottom:12px;width:58px;height:58px;background:#fff;color:var(--priD);box-shadow:var(--shadow2);font-size:24px"'+K.n(2)+'>M</span></div>'+K.card('<p style="font:700 20px/1.5 var(--font-body);color:var(--ink);margin:0">“Far above the olive grove, a small owl asked the moon a very big question.”</p>',"",1)+'<div style="display:grid;justify-items:start">'+K.chip(N.a+" is reading",{tone:"ok",ic:"volume"})+'</div>');}});
})();
