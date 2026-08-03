/**
 * homework — capture gate + tutor guard. MASTERFILE §9.1.
 * The OCR assertions shell out to REAL tesseract against REAL generated images.
 */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { gateImage, guardHint, forbiddenFor,
  MIN_EDGE_PX, MAX_SKEW_DEG, MIN_SHARPNESS } from '../src/capture.mjs';

const resolveCmd=(candidates)=>{
  for(const c of candidates){
    try{execFileSync(c,['--version'],{stdio:'ignore'});return c;}catch{}
  }
  return candidates[0];
};
const BASH=resolveCmd([process.env.HW_BASH,'bash',
  'C:\\Program Files\\Git\\bin\\bash.exe',
  'C:\\Program Files\\Git\\usr\\bin\\bash.exe'].filter(Boolean));
const TESSERACT=resolveCmd([process.env.HW_TESSERACT,'tesseract',
  'C:\\Program Files\\Tesseract-OCR\\tesseract.exe',
  'C:\\Program Files (x86)\\Tesseract-OCR\\tesseract.exe'].filter(Boolean));

const FIXTURE_DIR=tmpdir();
const fixture=(name)=>join(FIXTURE_DIR,name);
const MAKE_FIXTURES=fileURLToPath(new URL('./make-fixtures.sh',import.meta.url));

let pass=0, fail=0; const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const stats=(o={})=>({widthPx:1200,heightPx:800,sharpness:400,clipping:0.05,
  skewDegrees:0,...o});

// J · QUALITY GATE — thresholds derived from measurement
{
  check('J gate','a clean photo passes', gateImage(stats()).ok, 'true');
  check('J gate','deskew is the negation of measured skew',
    gateImage(stats({skewDegrees:4})).deskewBy, -4);
  check('J gate',`skew beyond ${MAX_SKEW_DEG}deg refused`,
    gateImage(stats({skewDegrees:9})).reason, 'too_skewed');
  check('J gate','6deg still accepted (67% recovery, deskew fixes it)',
    gateImage(stats({skewDegrees:6})).ok, 'true');
  check('J gate',`edge under ${MIN_EDGE_PX}px refused`,
    gateImage(stats({widthPx:200,heightPx:200})).reason, 'too_small');
  check('J gate','400px accepted — measured 100% recovery',
    gateImage(stats({widthPx:600,heightPx:400})).ok, 'true');
  check('J gate',`sharpness under ${MIN_SHARPNESS} refused`,
    gateImage(stats({sharpness:20})).reason, 'too_blurred');
  check('J gate','blown highlights refused',
    gateImage(stats({clipping:0.8})).reason, 'too_clipped');
  const adv=gateImage(stats({sharpness:20})).advice;
  check('J gate','advice is plain and actionable', adv, 'Hold still and try again.');
  check('J gate','advice contains no jargon',
    /threshold|resolution|variance|px|sigma/i.test(adv), 'false');
}

// K · REAL OCR — tesseract against generated worksheets
{
  execFileSync(BASH,[MAKE_FIXTURES,FIXTURE_DIR],{stdio:'ignore'});
  for(const f of ['hw_clean.png','hw_blur.png','hw_skew.png']){
    assert.ok(existsSync(fixture(f)), `fixture not generated: ${fixture(f)}`);
  }

  const ocr=(f)=>existsSync(f)
    ? execFileSync(TESSERACT,[f,'stdout'],{encoding:'utf8',stdio:['ignore','pipe','ignore']})
    : '';
  const tokens=(t)=>['2/3','1/5','3/8','1/2'].filter(x=>t.includes(x)).length;

  const clean=ocr(fixture('hw_clean.png'));
  check('K ocr','tesseract is present and ran', clean.length>0, 'true');
  check('K ocr','clean sheet recovers all fraction tokens', tokens(clean), 4);
  check('K ocr','clean sheet recovers the integer problem', clean.includes('27'), 'true');

  const blur=ocr(fixture('hw_blur.png'));
  check('K ocr','blurred sheet recovers nothing — the gate is load-bearing',
    tokens(blur), 0);

  const skew=ocr(fixture('hw_skew.png'));
  check('K ocr','8deg skew degrades badly, as measured', tokens(skew)<3, 'true');
  check('K ocr','gate rejects the blurred case pre-OCR',
    gateImage(stats({sharpness:15})).ok, 'false');
  check('K ocr','gate rejects the 8deg case pre-OCR',
    gateImage(stats({skewDegrees:8})).ok, 'false');
}

// L · THE TUTOR GUARD — "hint, don't solve" as a control, not a request
{
  const p={text:'12 + 27 = ______', forbiddenAnswers:forbiddenFor('12 + 27 = ______')};
  check('L tutor','answer derived server-side', p.forbiddenAnswers.includes('39'), 'true');
  check('L tutor','a good hint passes',
    guardHint('Ask what happens if you add the tens first.',p).ok, 'true');
  check('L tutor','a bare answer is refused',
    guardHint('It should come to 39.',p).reason, 'contains_answer');
  check('L tutor','"the answer is" is refused',
    guardHint('The answer is what you get by adding.',p).reason, 'too_directive');
  check('L tutor','an equals-result is refused',
    guardHint('So you end up with = 40 roughly.',p).reason, 'contains_equals_result');
  check('L tutor','"just write" is refused',
    guardHint('Just write it down.',p).reason, 'too_directive');
  check('L tutor','an empty hint is refused', guardHint('',p).reason, 'empty');
  check('L tutor','every refusal offers a safe fallback',
    guardHint('It is 39.',p).safeFallback.length>10, 'true');

  const f={text:'2/3 + 1/5 = ______', forbiddenAnswers:forbiddenFor('2/3 + 1/5 = ______')};
  check('L tutor','common denominator treated as an answer',
    f.forbiddenAnswers.includes('15'), 'true');
  check('L tutor','leaking the denominator is refused',
    guardHint('Use 15 as the bottom number.',f).reason, 'contains_answer');
  check('L tutor','pointing at it without saying it passes',
    guardHint('What number can both 3 and 5 divide into?',f).ok, 'true');
  check('L tutor','a substring match does not false-positive',
    guardHint('There are 159 ways to think about this.',f).ok, 'true');
  check('L tutor','negative results are derived',
    forbiddenFor('4 - 9 = ___').includes('-5'), 'true');
}

let g='';
for(const r of rows){ if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
