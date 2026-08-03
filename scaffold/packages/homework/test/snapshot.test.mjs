/**
 * homework — the capture button. MASTERFILE §9.15.
 */
import { captureCameraPhoto, captureScreenshot, gateImage,
  SCREENSHOT_SCOPED_OFF_SURFACES, neverToDeviceGallery, autoUploadsToAppStorage,
  MIN_EDGE_PX, MAX_SKEW_DEG, MIN_SHARPNESS } from '../src/snapshot.mjs';
import { MIN_EDGE_PX as CAPTURE_MIN_EDGE_PX, MIN_SHARPNESS as CAPTURE_MIN_SHARPNESS,
  MAX_SKEW_DEG as CAPTURE_MAX_SKEW_DEG } from '../src/capture.mjs';

let pass=0, fail=0; const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const stats=(o={})=>({widthPx:1200,heightPx:800,sharpness:400,clipping:0.05,
  skewDegrees:0,...o});

// M · CAMERA CAPTURE — reuses §9.1's gate wholesale
{
  check('M camera','MIN_EDGE_PX is reused from capture.ts, not duplicated',
    MIN_EDGE_PX, CAPTURE_MIN_EDGE_PX);
  check('M camera','MIN_SHARPNESS is reused from capture.ts, not duplicated',
    MIN_SHARPNESS, CAPTURE_MIN_SHARPNESS);
  check('M camera','MAX_SKEW_DEG is reused from capture.ts, not duplicated',
    MAX_SKEW_DEG, CAPTURE_MAX_SKEW_DEG);

  const clean=captureCameraPhoto(stats());
  check('M camera','a sharp well-lit photo passes the gate', clean.ok, 'true');
  check('M camera','a passing photo is marked ready to upload', clean.readyToUpload, 'true');
  check('M camera','a passing photo says it was saved', clean.message, 'Saved to your gallery.');

  const blurred=captureCameraPhoto(stats({sharpness:20}));
  check('M camera','a blurred photo is refused, not uploaded', blurred.ok, 'false');
  check('M camera','a blurred photo reason is the gate\'s own reason',
    blurred.reason, 'too_blurred');
  check('M camera','a blurred photo carries the gate\'s own advice, verbatim',
    blurred.advice, gateImage(stats({sharpness:20})).advice);

  const skewed=captureCameraPhoto(stats({skewDegrees:9}));
  check('M camera',`skew beyond ${MAX_SKEW_DEG}deg is refused`, skewed.ok, 'false');
  check('M camera','a skewed photo carries the gate\'s own advice, verbatim',
    skewed.advice, 'Line the page up straight.');

  const tooSmall=captureCameraPhoto(stats({widthPx:200,heightPx:200}));
  check('M camera',`edge under ${MIN_EDGE_PX}px is refused`, tooSmall.ok, 'false');
  check('M camera','a too-small photo carries the gate\'s own advice, verbatim',
    tooSmall.advice, 'Move a bit closer to the page.');

  const sixDeg=captureCameraPhoto(stats({skewDegrees:6}));
  check('M camera',`${MAX_SKEW_DEG}deg itself still passes — same boundary as the gate`,
    sixDeg.ok, 'true');
}

// N · SCREENSHOT CAPTURE — refused on the call surface, not silently taken
{
  check('N screenshot','exactly the three call surfaces are scoped off',
    [...SCREENSHOT_SCOPED_OFF_SURFACES].sort().join(','),
    'call_video,live_call,pane_video');

  for (const surface of SCREENSHOT_SCOPED_OFF_SURFACES) {
    const r=captureScreenshot(surface);
    check('N screenshot',`${surface} is refused, not silently taken`, r.ok, 'false');
    check('N screenshot',`${surface} refusal reason is call_surface`, r.reason, 'call_surface');
    check('N screenshot',`${surface} refusal carries a plain retry message`,
      r.advice, "Let's try that again.");
  }

  const ok=captureScreenshot('home');
  check('N screenshot','an ordinary surface is allowed', ok.ok, 'true');
  check('N screenshot','an allowed screenshot is marked ready to upload', ok.readyToUpload, 'true');
  check('N screenshot','an allowed screenshot says it was saved',
    ok.message, 'Saved to your gallery.');
}

// O · THE ONE GUARANTEE — named invariants, and no tally shown to her
{
  check('O invariants','neverToDeviceGallery holds', neverToDeviceGallery, 'true');
  check('O invariants','autoUploadsToAppStorage holds', autoUploadsToAppStorage, 'true');

  const results=[
    captureCameraPhoto(stats()),
    captureCameraPhoto(stats({sharpness:20})),
    captureCameraPhoto(stats({skewDegrees:9})),
    captureCameraPhoto(stats({widthPx:200,heightPx:200})),
    captureScreenshot('live_call'),
    captureScreenshot('call_video'),
    captureScreenshot('pane_video'),
    captureScreenshot('home'),
  ];
  const noNumericField = results.every(r => Object.values(r).every(v => typeof v !== 'number'));
  check('O invariants','no child-facing result carries any numeric field, let alone a tally',
    noNumericField, 'true');
}

let g='';
for(const r of rows){ if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
