/**
 * palette — her colour. MASTERFILE §8.6, §8.4, §9.8.2.
 */
import { PALETTE, swatch, ALLOWED_PLACEMENTS, FORBIDDEN_PLACEMENTS,
  MAX_PLACEMENTS_PER_SCREEN, applyColour, luminance, contrastRatio,
  AA_TEXT, textColourFor, auditPalette, dailyPair, choose, currentColour,
  parentView, auditColourPayload, coloursForYearBook, COLOUR_FORBIDDEN }
  from '../src/palette.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};
let seed=5; const rnd=()=>{seed=(seed*1103515245+12345)&0x7fffffff; return seed/0x7fffffff;};

// BE · THE PALETTE — curated, not a picker
{
  check('BE palette','twelve swatches', PALETTE.length, 12);
  check('BE palette','labels are a child\'s words, not hex',
    PALETTE.every(s=>/^[a-z ]+$/.test(s.label)), 'true');
  check('BE palette','every swatch has a derived ink colour',
    PALETTE.every(s=>/^#[0-9A-F]{6}$/i.test(s.inkHex)), 'true');
  check('BE palette','there is deliberately no pure red — it would read as a warning',
    PALETTE.some(s=>s.hex.toUpperCase()==='#FF0000'||s.label==='red'), 'false');
  check('BE palette','unknown ids resolve to null', swatch('nope'), 'null');
  check('BE palette','ids are unique',
    new Set(PALETTE.map(s=>s.id)).size, PALETTE.length);
}

// BF · CONTRAST — she is never told her favourite colour was a problem
{
  check('BF contrast','white against black is 21:1',
    Math.round(contrastRatio('#FFFFFF','#000000')), 21);
  check('BF contrast','a colour against itself is 1:1',
    Math.round(contrastRatio('#F2B705','#F2B705')), 1);
  check('BF contrast','luminance is ordered',
    luminance('#FFFFFF')>luminance('#F2B705'), 'true');

  // The case this exists for.
  const yellow=swatch('sunny');
  check('BF contrast','sunny yellow FAILS as text on white',
    contrastRatio(yellow.hex,'#FFFFFF')<AA_TEXT, 'true');
  const t=textColourFor(yellow);
  check('BF contrast','so the derived ink is used instead', t.usedInk, 'true');
  check('BF contrast','and it passes AA', t.ratio>=AA_TEXT, 'true');
  check('BF contrast','the pure hue is still what she sees in fills',
    yellow.hex, '#F2B705');

  const midnight=swatch('midnight');
  check('BF contrast','a dark colour needs no substitution',
    textColourFor(midnight).usedInk, 'false');

  // EVERY swatch must be usable, or one child gets a broken app.
  const a=auditPalette();
  check('BF contrast','every one of the twelve passes AA as ink', a.ok, 'true');
  check('BF contrast','with no failures to report', a.failures.length, 0);
}

// BG · THE PLACEMENT BUDGET — the oversaturation guard
{
  check('BG placement',`at most ${MAX_PLACEMENTS_PER_SCREEN} per screen`,
    MAX_PLACEMENTS_PER_SCREEN, 3);
  const ok=applyColour('coral',['accent_stripe','avatar_ring']);
  check('BG placement','allowed placements are accepted', ok.placements.length, 2);
  const over=applyColour('coral',['accent_stripe','avatar_ring','sleeps_number',
    'game_piece','header_flourish']);
  check('BG placement','beyond the budget it is DROPPED, not squeezed in',
    over.placements.length, 3);
  check('BG placement','and the drops are reported', over.dropped.length, 2);

  // The half that matters.
  check('BG placement','a prohibition can never take her colour',
    applyColour('coral',['prohibition']).reason, 'forbidden_placement');
  check('BG placement','nor a ribbon band — it encodes what she is doing',
    applyColour('coral',['ribbon_band']).reason, 'forbidden_placement');
  check('BG placement','nor the overlap band — it means "you can both talk now"',
    applyColour('coral',['overlap_band']).reason, 'forbidden_placement');
  check('BG placement','nor an error state', applyColour('coral',['error']).ok, 'false');
  check('BG placement','nor body text or the background',
    applyColour('coral',['body_text']).ok && applyColour('coral',['background']).ok,
    'false');
  check('BG placement','the forbidden list names the offender',
    applyColour('coral',['accent_stripe','medication_block']).offending,
    'medication_block');
  check('BG placement','an unknown colour is refused',
    applyColour('zzz',['accent_stripe']).reason, 'unknown_colour');
  check('BG placement','allowed and forbidden lists do not overlap',
    ALLOWED_PLACEMENTS.some(p=>FORBIDDEN_PLACEMENTS.includes(p)), 'false');
  check('BG placement','the forbidden list is the longer one — deliberately',
    FORBIDDEN_PLACEMENTS.length>ALLOWED_PLACEMENTS.length, 'true');
}

// BH · THE DAILY CHOICE
{
  const pair=dailyPair('coral',rnd);
  check('BH daily','two swatches offered', pair.length, 2);
  check('BH daily','one of them is always her CURRENT colour — keeping is as easy as changing',
    pair.some(s=>s.id==='coral'), 'true');
  check('BH daily','and they differ', pair[0].id===pair[1].id, 'false');
  // Side is randomised so the current one is not always first.
  const sides=new Set();
  for(let i=0;i<40;i++) sides.add(dailyPair('coral',rnd)[0].id==='coral');
  check('BH daily','the side is randomised', sides.size, 2);

  let h=[];
  h=choose(h,'sunny','2026-07-25T09:00:00Z','first_run').history;
  check('BH daily','first run recorded', h[0].via, 'first_run');
  check('BH daily','current colour reflects the latest', currentColour(h).label, 'sunny yellow');
  h=choose(h,'sea','2026-07-27T09:00:00Z').history;
  check('BH daily','a change updates it', currentColour(h).label, 'sea blue');
  check('BH daily','history is kept, not overwritten', h.length, 2);
  check('BH daily','an unknown colour is refused', choose(h,'zzz','t').reason, 'unknown_colour');
  check('BH daily','no history means no colour yet', currentColour([]), 'null');
}

// BI · THE PARENT — a colour is a fact, never a mood
{
  let h=[{colourId:'sunny',chosenAt:'2026-07-25T09:00:00Z',via:'first_run'},
         {colourId:'storm',chosenAt:'2026-07-27T08:10:00Z',via:'daily'}];
  const v=parentView(h,'2026-07-27T12:00:00Z');
  check('BI parent','he is told what she picked', v.label, 'storm grey');
  check('BI parent','and that it changed today', v.changedToday, 'true');
  check('BI parent','the line is a plain fact', v.line, 'Today her colour is storm grey.');

  // THE prohibition.
  check('BI parent','no mood, sentiment or interpretation field exists',
    auditColourPayload(v).ok, 'true');
  check('BI parent','audit catches a mood field',
    auditColourPayload({...v,mood:'low'}).leaks.join(','), 'mood');
  check('BI parent','audit catches a trend',
    auditColourPayload({a:{b:[{trend:'darker'}]}}).ok, 'false');
  check('BI parent','audit catches a concern flag',
    auditColourPayload({...v,concern:true}).ok, 'false');
  check('BI parent','the view carries no interpretation words',
    /sad|happy|low|worried|mood|seems/i.test(JSON.stringify(v)), 'false');
  check('BI parent','the forbidden list names sentiment and trend both',
    COLOUR_FORBIDDEN.includes('sentiment')&&COLOUR_FORBIDDEN.includes('trend'), 'true');

  const same=parentView([h[0]],'2026-07-27T12:00:00Z');
  check('BI parent','unchanged reads without fanfare', same.line, 'Her colour is sunny yellow.');
  check('BI parent','and is not flagged as a change', same.changedToday, 'false');
  check('BI parent','no history means nothing to show', parentView([],'t'), 'null');
}

// BJ · YEAR BOOK
{
  const h=[];
  for(let i=0;i<40;i++) h.push({colourId:'coral',
    chosenAt:`2026-0${(i%9)+1}-01T09:00:00Z`,via:'daily'});
  for(let i=0;i<12;i++) h.push({colourId:'sea',
    chosenAt:`2026-0${(i%9)+1}-02T09:00:00Z`,via:'daily'});
  h.push({colourId:'mint',chosenAt:'2025-05-01T09:00:00Z',via:'daily'});
  const yb=coloursForYearBook(h,2026);
  check('BJ yearbook','a section is produced', yb.section, 'Your colours');
  check('BJ yearbook','most-used first', yb.swatches[0].label, 'coral pink');
  check('BJ yearbook','with a day count', yb.swatches[0].days, 40);
  check('BJ yearbook','only this year', yb.swatches.some(s=>s.label==='mint'), 'false');
  check('BJ yearbook','no scoring language reaches it', auditColourPayload(yb).ok, 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
