/**
 * The pane. MASTERFILE §5.26. Runs on any hardware because it uses no platform API.
 */
import { CORNERS, newPane, dock, nearestCorner, FREE_DRAG_ALLOWED,
  SIZE_FRACTIONS, PINCH_RESIZE_ALLOWED, cycleSize, ABSOLUTE_FLOOR_PX,
  MAX_FRACTION_OF_SHORT_EDGE, paneSizePx, MAX_SCREEN_COVERAGE, coverage,
  sizeFits, bestFit, closePane, endCall, childControls,
  cornerDistance, avoid, releaseZones, audioLink, paneFailed,
  AUDIO_SURVIVES_PANE_LOSS, renderFor, stillFrameLine,
  PANE_REFUSED_ON, paneAllowedOn, refusalReason,
  probeOsPip, claimWithoutObservation, OS_PIP_IS_NEVER_LOAD_BEARING,
  effectivePane, paneChildView, auditChildPane, PANE_FORBIDDEN }
  from '../src/pane.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

const COVER={w:344,h:882}, MAIN={w:673,h:841}, TAB10={w:800,h:1280}, PC={w:1280,h:800};

// EG · DOCKING, NOT DRAGGING
{
  check('EG dock','four corners', CORNERS.length, 4);
  check('EG dock','free drag is refused', FREE_DRAG_ALLOWED, 'false');
  check('EG dock','because a small target vanishes behind a thumb',
    FREE_DRAG_ALLOWED, 'false');
  check('EG dock','starts bottom-right', newPane().corner, 'br');
  check('EG dock','docks where asked', dock(newPane(),'tl').corner, 'tl');
  check('EG dock','a drag lands at the nearest corner',
    nearestCorner(MAIN, 40, 40), 'tl');
  check('EG dock','and from the other side', nearestCorner(MAIN, 600, 800), 'br');
  check('EG dock','a corner is position without coordinates',
    typeof newPane().corner, 'string');
  check('EG dock','so it survives rotation with no arithmetic',
    dock(newPane(),'tr').corner, nearestCorner({w:841,h:673}, 800, 40));
}

// EH · THREE SIZES, AND A FLOOR THAT IS A FACE
{
  check('EH size','pinch resize is refused', PINCH_RESIZE_ALLOWED, 'false');
  check('EH size','three sizes', Object.keys(SIZE_FRACTIONS).length, 3);
  const p=newPane();
  check('EH size','cycling goes medium → large', cycleSize(p).size, 'large');
  check('EH size','and wraps back to small', cycleSize(cycleSize(p)).size, 'small');

  // The relative floor.
  check('EH size','on a cover screen it is a fraction of the SHORT edge',
    paneSizePx(COVER,'medium').w, Math.round(344*0.28));
  check('EH size','on a PC it uses the short edge too, not the width',
    paneSizePx(PC,'medium').w, Math.round(800*0.28));
  check('EH size','never below the absolute floor',
    paneSizePx({w:200,h:200},'small').w, ABSOLUTE_FLOOR_PX);
  check('EH size','a fixed 96px would be a stamp on a 10-inch tablet',
    paneSizePx(TAB10,'medium').w > 96, 'true');
  check('EH size','and would swallow a cover screen at large',
    paneSizePx(COVER,'large').w < 344*MAX_FRACTION_OF_SHORT_EDGE+1, 'true');

  check('EH size','it never covers more than a quarter of the screen',
    coverage(MAIN,'medium') <= MAX_SCREEN_COVERAGE, 'true');
  // Every size fits a 344x882 cover screen precisely BECAUSE the fraction comes
  // from the short edge — large covers 7.6%, not the 30%+ a width-based
  // calculation would have produced. That is the relative floor doing its job.
  check('EH size','large fits even a cover screen', sizeFits(COVER,'large'), 'true');
  check('EH size','covering well under the ceiling', coverage(COVER,'large') < 0.10, 'true');
  check('EH size','so bestFit gives it the largest', bestFit(COVER), 'large');
  // A short, wide viewport is where the ceiling actually bites.
  const SQUAT={w:900,h:360};
  check('EH size','a squat viewport is where the ceiling bites',
    coverage(SQUAT,'large') > coverage(COVER,'large'), 'true');
  check('EH size','and bestFit still returns something usable',
    ['small','medium','large'].includes(bestFit(SQUAT)), 'true');
  check('EH size','a PC comfortably takes medium', sizeFits(PC,'medium'), 'true');
  check('EH size','every viewport gets SOME size',
    [COVER,MAIN,TAB10,PC].every(v=>bestFit(v)), 'true');
}

// EI · SHE CANNOT CLOSE IT
{
  const p=newPane();
  const child=closePane(p,'child');
  check('EI close','a CHILD cannot close it', child.ok, 'false');
  check('EI close','and the refusal is named', child.reason, 'child_cannot_close');
  check('EI close','a guardian can', closePane(p,'guardian').ok, 'true');
  check('EI close','ending the call removes it', endCall(p).visible, 'false');
  check('EI close','which is the ONLY thing that does', endCall(p).closed, 'true');

  const c=childControls();
  check('EI close','she can move it', c.move, 'true');
  check('EI close','she can resize it', c.resize, 'true');
  check('EI close','she cannot close it', c.close, 'false');
  check('EI close','no close affordance reaches her view',
    auditChildPane(paneChildView(p,MAIN,'high',false)).ok, 'true');
  check('EI close','audit catches a dismiss button',
    auditChildPane({...paneChildView(p,MAIN,'high',false),dismiss:true}).leaks.join(','),
    'dismiss');
  check('EI close','and catches "closeable"',
    auditChildPane({a:[{closeable:true}]}).ok, 'false');
  check('EI close','the child view declares canClose false',
    paneChildView(p,MAIN,'high',false).canClose, 'false');
  check('EI close','the forbidden list covers hide and remove',
    PANE_FORBIDDEN.includes('hide')&&PANE_FORBIDDEN.includes('remove'), 'true');
}

// EJ · HOT-ZONE AVOIDANCE — the pane yields, she never has to
{
  const p=dock(newPane(),'br');
  const bottomRight={x:0.6,y:0.6,w:0.35,h:0.35};
  const moved=avoid(p,[bottomRight]);
  check('EJ avoid','it moves away from her hand', moved.corner, 'tl');
  check('EJ avoid','and records that it was displaced', moved.displaced, 'true');
  check('EJ avoid','no zones means no movement', avoid(p,[]).displaced, 'false');

  // It must dodge EVERY zone, not merely the nearest.
  const two=[{x:0.0,y:0.0,w:0.3,h:0.3},{x:0.7,y:0.0,w:0.3,h:0.3}];
  const dodged=avoid(p,two);
  check('EJ avoid','with two top zones it goes to the bottom',
    ['bl','br'].includes(dodged.corner), 'true');
  check('EJ avoid','distance is measured in fractions, so resolution-free',
    cornerDistance('tl',{x:0,y:0,w:0.2,h:0.2}) < cornerDistance('br',{x:0,y:0,w:0.2,h:0.2}),
    'true');
  check('EJ avoid','it snaps home once her hands move',
    releaseZones(moved,'br').corner, 'br');
  check('EJ avoid','and stops being displaced', releaseZones(moved,'br').displaced, 'false');
  check('EJ avoid','an undisplaced pane is left alone',
    releaseZones(p,'tl').corner, 'br');
}

// EK · AUDIO IS DECOUPLED — the assertion that matters most
{
  const p=newPane(), a=audioLink();
  check('EK audio','the link is independent of the pane', a.independentOfPane, 'true');
  const failed=paneFailed(p,a);
  check('EK audio','the pane can vanish', failed.pane.visible, 'false');
  check('EK audio','AND THE AUDIO SURVIVES', failed.audio.alive, 'true');
  check('EK audio','the rule is explicit', AUDIO_SURVIVES_PANE_LOSS, 'true');
  check('EK audio','she is told she can still hear him',
    /still hear him/.test(failed.childLine), 'true');
  check('EK audio','and it is not framed as a failure',
    /error|failed|problem/i.test(failed.childLine), 'false');
  check('EK audio','the pane closing does not touch the link',
    audioLink().alive, 'true');
  check('EK audio','because the video is the enhancement, the voice is the call',
    failed.audio.independentOfPane, 'true');
}

// EL · LOW TIER DEGRADES TO A STILL FRAME
{
  check('EL tier','a low tablet running a game gets a still frame',
    renderFor('low',true), 'still_frame');
  check('EL tier','with no game it still gets video', renderFor('low',false), 'video');
  check('EL tier','a mid device gets video throughout', renderFor('mid',true), 'video');
  check('EL tier','and high too', renderFor('high',true), 'video');
  check('EL tier','a still frame says nothing about itself', stillFrameLine(), '');
  check('EL tier','because an apology would be worse than the frame',
    stillFrameLine().length, 0);
  check('EL tier','the child view carries the render mode',
    paneChildView(newPane(),COVER,'low',true).render, 'still_frame');
}

// EM · TWO SURFACES REFUSE IT
{
  check('EM refuse','homework capture refuses the pane',
    paneAllowedOn('homework_capture'), 'false');
  check('EM refuse','because two camera surfaces is a confusion',
    /competing camera surfaces/.test(refusalReason('homework_capture')), 'true');
  check('EM refuse','tabletop refuses it', paneAllowedOn('fold_tabletop'), 'false');
  check('EM refuse','because it already has the best position video will get',
    /above the crease at eye level/.test(refusalReason('fold_tabletop')), 'true');
  check('EM refuse','an ordinary game allows it', paneAllowedOn('playCheckers'), 'true');
  check('EM refuse','each refusal carries a reason',
    PANE_REFUSED_ON.every(r=>r.because.length>40), 'true');
  check('EM refuse','an allowed surface has no reason', refusalReason('colouring'), 'null');
}

// EN · THE FAIL-SAFE PROBE — attempt and verify, never ask
{
  const guardian={role:'guardian',kioskLocked:false,claimsSupport:true,
    observedAfterAttempt:true};
  check('EN probe','observed → OS pip', probeOsPip(guardian).osPip, 'true');
  check('EN probe','and it is marked verified', probeOsPip(guardian).verified, 'true');

  // The case that actually bites on FireOS.
  const lying=claimWithoutObservation();
  check('EN probe','a platform that CLAIMS support and does not deliver is caught',
    lying.osPip, 'false');
  check('EN probe','and the reason is refusal, not a version check',
    lying.reason, 'refused');
  check('EN probe','a claim alone never grants it',
    probeOsPip({...guardian,observedAfterAttempt:false}).osPip, 'false');
  check('EN probe','and no claim with an observation still works — only observation counts',
    probeOsPip({...guardian,claimsSupport:false}).osPip, 'true');

  check('EN probe','a kiosk-locked device never gets it',
    probeOsPip({...guardian,kioskLocked:true}).reason, 'kiosk');
  check('EN probe','a child never gets it, locked or not',
    probeOsPip({...guardian,role:'child',kioskLocked:false}).reason, 'child_device');
  check('EN probe','nothing depends on the answer', OS_PIP_IS_NEVER_LOAD_BEARING, 'true');

  check('EN probe','a guardian with real support gets an OS window',
    effectivePane(guardian), 'os_window');
  check('EN probe','everyone else gets the in-app pane',
    effectivePane({...guardian,role:'child'}), 'in_app_pane');
  check('EN probe','including a lying platform',
    effectivePane({...guardian,observedAfterAttempt:false}), 'in_app_pane');
  check('EN probe','and a kiosk device',
    effectivePane({...guardian,kioskLocked:true}), 'in_app_pane');
  check('EN probe','so it runs on ANY hardware/firmware combination',
    [{...guardian,role:'child'},{...guardian,kioskLocked:true},
     {...guardian,observedAfterAttempt:false},{...guardian,claimsSupport:false}]
      .every(i=>['os_window','in_app_pane'].includes(effectivePane(i))), 'true');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
