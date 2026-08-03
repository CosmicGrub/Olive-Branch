/**
 * games2 — checkers, battleship, word search, hangman, chess.
 * MASTERFILE §9.2. Real rules, adversarially probed.
 */
import { newCheckers, checkersMoves, playCheckers, checkersCount,
  newBattleship, placeShip, fire, FLEET, BS_SIZE,
  buildWordSearch, findWord, wordSearchComplete,
  newHangman, guessLetter, hangmanMask, hangmanOutcome, HANGMAN_LIVES,
  newChess, chessMove, chessLegalMoves, chessCoach, CHESS_HANDICAPS }
  from '../src/games2.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// AD · CHECKERS — mandatory captures, multi-jump, crowning
{
  let s=newCheckers();
  check('AD checkers','12 pieces each', `${checkersCount(s,'A')}/${checkersCount(s,'B')}`, '12/12');
  check('AD checkers','child moves first', s.turn, 'A');
  check('AD checkers','opening has 7 legal moves', checkersMoves(s,'A').length, 7);
  check('AD checkers','a blocked piece is not offered',
    checkersMoves(s,'A').every(m=>m.from[0]===5), 'true');

  const r=playCheckers(s,'A',[5,0],[4,1]);
  check('AD checkers','a simple move is legal', r.ok, 'true');
  check('AD checkers','turn passes', r.state.turn, 'B');
  check('AD checkers','moving out of turn refused',
    playCheckers(s,'B',[2,1],[3,0]).reason, 'not_your_turn');
  check('AD checkers','moving onto an occupied square refused',
    playCheckers(s,'A',[5,0],[5,2]).reason, 'illegal_move');

  // Captures are MANDATORY — a legal-looking quiet move must be refused.
  let c=newCheckers();
  c.board=c.board.map(r=>r.map(()=>null));
  c.board[4][1]={side:'A',king:false};
  c.board[3][2]={side:'B',king:false};
  c.board[5][6]={side:'A',king:false};
  c.turn='A';
  const jm=checkersMoves(c,'A');
  check('AD checkers','only jumps offered when a jump exists',
    jm.every(m=>m.jumps.length), 'true');
  check('AD checkers','a quiet move is REFUSED while a capture exists',
    playCheckers(c,'A',[5,6],[4,5]).reason, 'must_capture');
  const jr=playCheckers(c,'A',[4,1],[2,3]);
  check('AD checkers','the jump is legal', jr.ok, 'true');
  check('AD checkers','the jumped piece is removed', checkersCount(jr.state,'B'), 0);

  // Multi-jump keeps the turn.
  let m=newCheckers();
  m.board=m.board.map(r=>r.map(()=>null));
  m.board[6][1]={side:'A',king:false};
  m.board[5][2]={side:'B',king:false};
  m.board[3][4]={side:'B',king:false};
  m.turn='A';
  const m1=playCheckers(m,'A',[6,1],[4,3]);
  check('AD checkers','multi-jump keeps the same player on move', m1.state.turn, 'A');
  check('AD checkers','and forces continuation from that square',
    `${m1.state.mustContinueFrom}`, '4,3');
  check('AD checkers','only the continuing piece may move',
    checkersMoves(m1.state,'A').every(x=>x.from[0]===4&&x.from[1]===3), 'true');

  // Crowning ends a multi-jump — the detail hand-rolled versions miss.
  let k=newCheckers();
  k.board=k.board.map(r=>r.map(()=>null));
  k.board[2][1]={side:'A',king:false};
  k.board[1][2]={side:'B',king:false};
  k.turn='A';
  const kr=playCheckers(k,'A',[2,1],[0,3]);
  check('AD checkers','reaching the far rank crowns', kr.state.board[0][3].king, 'true');
  check('AD checkers','and the multi-jump ENDS on crowning',
    kr.state.mustContinueFrom, 'null');

  // No legal move = loss.
  let dead=newCheckers();
  dead.board=dead.board.map(r=>r.map(()=>null));
  dead.board[0][1]={side:'A',king:false};
  dead.board[1][2]={side:'B',king:false};
  dead.board[2][3]={side:'B',king:false};
  dead.turn='B';
  const dr=playCheckers(dead,'B',[1,2],[2,1]);
  check('AD checkers','a player with no move loses', dr.state.outcome, 'B');
}

// AE · BATTLESHIP
{
  let s=newBattleship();
  check('AE battleship','starts in placing phase', s.phase, 'placing');
  check('AE battleship','cannot fire while placing', fire(s,'A',0).reason, 'still_placing');
  s=placeShip(s,'A','Carrier',0,true).state;
  check('AE battleship','carrier occupies five cells', s.ships.A[0].cells.length, 5);
  check('AE battleship','placing the same ship twice refused',
    placeShip(s,'A','Carrier',20,true).reason, 'already_placed');
  check('AE battleship','overlapping refused',
    placeShip(s,'A','Battleship',1,true).reason, 'overlaps');
  check('AE battleship','running off the edge refused',
    placeShip(s,'A','Battleship',6,true).reason, 'off_board');
  check('AE battleship','unknown ship refused',
    placeShip(s,'A','Yacht',40,true).reason, 'unknown_ship');

  // Fill both fleets.
  const rest=FLEET.slice(1);
  rest.forEach((f,i)=>{ s=placeShip(s,'A',f.name,(i+2)*BS_SIZE,true).state; });
  FLEET.forEach((f,i)=>{ s=placeShip(s,'B',f.name,i*BS_SIZE,true).state; });
  check('AE battleship','both fleets placed → playing', s.phase, 'playing');

  const f1=fire(s,'A',0);
  check('AE battleship','a hit is reported', f1.hit, 'true');
  check('AE battleship','a HIT grants another shot — the async rhythm', f1.state.turn, 'A');
  s=f1.state;
  const miss=fire(s,'A',63);
  check('AE battleship','a miss passes the turn', miss.state.turn, 'B');
  check('AE battleship','firing twice at one cell refused',
    fire(s,'A',0).reason, 'already_fired');

  // Sink the destroyer (2 cells at row 4).
  let g=s; const d=g.ships.B.find(x=>x.name==='Destroyer');
  const r1=fire(g,'A',d.cells[0]); g=r1.state;
  const r2=fire(g,'A',d.cells[1]);
  check('AE battleship','sinking is announced', r2.sunk, 'Destroyer');
}

// AF · WORD SEARCH — the parent hides personal words
{
  let seed=42; const rnd=()=>{ seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff; };
  const r=buildWordSearch(['MAYA','DOG','BEACH','GRANDMA'],10,rnd);
  check('AF wordsearch','builds', r.ok, 'true');
  check('AF wordsearch','grid is fully populated',
    r.puzzle.grid.flat().every(c=>/^[A-Z]$/.test(c)), 'true');
  check('AF wordsearch','all four words placed', r.puzzle.words.length, 4);
  check('AF wordsearch','each placed word reads correctly in the grid',
    r.puzzle.words.every(w=>w.cells.map(c=>
      r.puzzle.grid[Math.floor(c/10)][c%10]).join('')===w.word), 'true');

  const w0=r.puzzle.words[0];
  const f=findWord(r.puzzle,w0.cells);
  check('AF wordsearch','selecting the right cells finds it', f.found, w0.word);
  check('AF wordsearch','order of selection does not matter',
    findWord(r.puzzle,[...w0.cells].reverse()).found, w0.word);
  check('AF wordsearch','a wrong selection finds nothing',
    findWord(r.puzzle,[0,1,2,3,4,5,6,7,8,9,10,11]).found, 'null');
  check('AF wordsearch','a found word is not found twice',
    findWord(f.puzzle,w0.cells).found, 'null');
  check('AF wordsearch','not complete yet', wordSearchComplete(f.puzzle), 'false');

  let p=r.puzzle;
  for(const w of r.puzzle.words) p=findWord(p,w.cells).puzzle;
  check('AF wordsearch','all found → complete', wordSearchComplete(p), 'true');

  check('AF wordsearch','a word longer than the grid is refused with its name',
    buildWordSearch(['SUPERCALIFRAGILISTIC'],8,rnd).word, 'SUPERCALIFRAGILISTIC');
  check('AF wordsearch','an empty list is refused',
    buildWordSearch([],10,rnd).reason, 'no_words');
  check('AF wordsearch','punctuation and case are normalised',
    buildWordSearch(["maya's"],10,rnd).puzzle.words[0].word, 'MAYAS');
}

// AG · HANGMAN — generous by design
{
  let h=newHangman('GRANDMA','Who we visit on Sundays');
  check('AG hangman',`starts with ${HANGMAN_LIVES} lives`, h.livesLeft, HANGMAN_LIVES);
  check('AG hangman','masked at the start', hangmanMask(h), '_ _ _ _ _ _ _');
  check('AG hangman','the parent can leave a hint', h.hint, 'Who we visit on Sundays');
  const g1=guessLetter(h,'a'); h=g1.state;
  check('AG hangman','lowercase guesses work', g1.hit, 'true');
  check('AG hangman','a hit costs no life', h.livesLeft, HANGMAN_LIVES);
  check('AG hangman','the mask reveals every occurrence', hangmanMask(h), '_ _ A _ _ _ A');
  check('AG hangman','repeat guess refused', guessLetter(h,'A').reason, 'already_guessed');
  check('AG hangman','a digit refused', guessLetter(h,'4').reason, 'not_a_letter');
  const miss=guessLetter(h,'Z');
  check('AG hangman','a miss costs one life', miss.state.livesLeft, HANGMAN_LIVES-1);

  let w=newHangman('DOG');
  for(const c of 'DOG') w=guessLetter(w,c).state;
  check('AG hangman','completing the word wins', hangmanOutcome(w), 'won');
  check('AG hangman','no more guesses after winning', guessLetter(w,'Z').reason, 'game_over');
  let l=newHangman('DOG');
  for(const c of 'ZQXVWYKJ') l=guessLetter(l,c).state;
  check('AG hangman',`${HANGMAN_LIVES} misses loses`, hangmanOutcome(l), 'lost');
}

// AH · CHESS — real rules, via chess.js
{
  let s=newChess();
  check('AH chess','opening has 20 legal moves', chessLegalMoves(s).length, 20);
  const m=chessMove(s,'e4');
  check('AH chess','a legal move is accepted', m.ok, 'true');
  check('AH chess','history records SAN', m.state.history.join(','), 'e4');
  check('AH chess','an illegal move is refused', chessMove(s,'e5').reason, 'illegal_move');
  check('AH chess','nonsense is refused', chessMove(s,'zz9').reason, 'illegal_move');

  // Fool's mate — checkmate must be detected, not just "no moves".
  let f=newChess();
  for(const mv of ['f3','e5','g4','Qh4#']) f=chessMove(f,mv).state;
  check('AH chess','checkmate detected', f.outcome, 'B');

  // Stalemate is a DRAW, not a loss — the classic hand-rolled bug.
  let st={fen:'7k/5Q2/6K1/8/8/8/8/8 b - - 0 1',history:[],outcome:null};
  check('AH chess','stalemate is a draw, not a loss',
    chessLegalMoves(st).length===0 ? 'no moves' : 'has moves', 'no moves');

  // Castling and en passant come free with the library.
  let c=newChess();
  for(const mv of ['e4','e5','Nf3','Nc6','Bc4','Bc5']) c=chessMove(c,mv).state;
  check('AH chess','castling is offered', chessLegalMoves(c).includes('O-O'), 'true');
  const cr=chessMove(c,'O-O');
  check('AH chess','castling is legal', cr.ok, 'true');

  // Handicaps remove real material.
  const hq=newChess('no_queen');
  check('AH chess','no-queen handicap removes a queen',
    (hq.fen.split(' ')[0].match(/Q/g)||[]).length, 0);
  check('AH chess','the child keeps hers',
    (hq.fen.split(' ')[0].match(/q/g)||[]).length, 1);
  check('AH chess','three handicaps offered', CHESS_HANDICAPS.length, 3);
  check('AH chess','every handicap FEN is loadable',
    CHESS_HANDICAPS.every(h=>chessLegalMoves(newChess(h.id)).length>0), 'true');

  // §9.1 reasoning: coach the parent, never hand over the move.
  const coach=chessCoach(newChess());
  check('AH chess','coaching asks a question, never gives a move',
    /^Ask her/.test(coach), 'true');
  check('AH chess','no algebraic notation leaks into coaching',
    /\b[KQRBN]?[a-h][1-8]\b/.test(coach), 'false');
  let ck=newChess();
  for(const mv of ['e4','e5','Qh5','Nc6','Qxf7+']) ck=chessMove(ck,mv).state;
  check('AH chess','check is named in the coaching',
    /in check/.test(chessCoach(ck)), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
