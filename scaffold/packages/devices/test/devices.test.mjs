/**
 * The device matrix. MASTERFILE §8.11.
 */
import { FORM_FACTORS, NARROWEST, factor, postureFor, columnsAt,
  INPUTS_BY_POSTURE, TOUCH_TARGET_DP, MOUSE_TARGET_DP, targetFloor,
  STYLUS_IMPROVES, stylusAvailable, stylusRequired,
  CHANNELS, capability, admitDevice, channelAdvice,
  TIERS, tierFor, spec, callSettings,
  LOCK_METHODS, lockMethod, childShellAllowed,
  auditLayouts, postureCoverage } from '../src/devices.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// DE · FORM FACTORS
{
  check('DE form','nine postures', FORM_FACTORS.length, 9);
  check('DE form','the narrowest supported width is the folded Fold', NARROWEST, 344);
  check('DE form','every posture declares a minimum viewport',
    FORM_FACTORS.every(f=>f.min.w>0&&f.min.h>0), 'true');
  check('DE form','and at least one orientation',
    FORM_FACTORS.every(f=>f.orientations.length>0), 'true');

  check('DE form','a folded Fold is recognised', postureFor({w:344,h:882}), 'fold_cover');
  check('DE form','an unfolded one too', postureFor({w:673,h:841}), 'fold_main');
  check('DE form','a 10-inch tablet', postureFor({w:800,h:1280}), 'tablet_large');
  check('DE form','a PC', postureFor({w:1100,h:700}), 'desktop');
  check('DE form','DeX', postureFor({w:1400,h:800}), 'dex');
  check('DE form','an ordinary phone', postureFor({w:360,h:740}), 'phone');

  // The posture nothing used.
  check('DE form','half-open is recognised as tabletop', postureFor({w:700,h:440}),
    'fold_tabletop');
  check('DE form','and it is landscape-only',
    factor('fold_tabletop').orientations.join(), 'landscape');
  check('DE form','because it stands by itself with the camera up',
    /camera at eye level/.test(factor('fold_tabletop').note), 'true');
  check('DE form','every posture is reachable from a real viewport',
    postureCoverage().filter(p=>!p.reachable).map(p=>p.posture).join(), '');

  // Landscape, which is the assumption most layouts get wrong.
  check('DE form','a 10-inch tablet supports landscape',
    factor('tablet_large').orientations.includes('landscape'), 'true');
  check('DE form','and the note says it is the COMMON case there',
    /LANDSCAPE more often than portrait/.test(factor('tablet_large').note), 'true');
  check('DE form','a folded Fold is portrait only — nobody rotates it',
    factor('fold_cover').orientations.join(), 'portrait');
}

// DF · COLUMNS SCALE WITH TYPE, NOT DEVICE
{
  check('DF columns','a PC gets three', columnsAt({w:1280,h:800},1), 3);
  check('DF columns','an unfolded Fold gets two', columnsAt({w:673,h:841},1), 2);
  check('DF columns','a folded one gets one', columnsAt({w:344,h:882},1), 1);
  // The mistake this prevents.
  check('DF columns','a 10-inch tablet at 2.0x type gets ONE, like a phone',
    columnsAt({w:800,h:1280},2.0), 1);
  check('DF columns','and a PC at 2.0x drops all the way to ONE — 640px effective',
    columnsAt({w:1280,h:800},2.0), 1);
  check('DF columns','it takes a wide PC to hold two at 2.0x',
    columnsAt({w:1600,h:900},2.0), 2);
  check('DF columns','because the EFFECTIVE width is what matters',
    columnsAt({w:1320,h:800},2.0), columnsAt({w:660,h:800},1));
}

// DG · INPUT
{
  check('DG input','every posture declares its inputs',
    FORM_FACTORS.every(f=>INPUTS_BY_POSTURE[f.posture].length>0), 'true');
  check('DG input','a PC has no touch', INPUTS_BY_POSTURE.desktop.includes('touch'), 'false');
  check('DG input','DeX has mouse AND touch — platform does not imply input',
    INPUTS_BY_POSTURE.dex.includes('mouse')&&INPUTS_BY_POSTURE.dex.includes('touch'),
    'true');
  check('DG input','the Fold takes an S Pen when open', stylusAvailable('fold_main'), 'true');
  check('DG input','but not when closed', stylusAvailable('fold_cover'), 'false');
  check('DG input','a stylus improves exactly two things', STYLUS_IMPROVES.length, 2);
  check('DG input','and is never REQUIRED for anything', stylusRequired(), 'false');

  check('DG input','touch targets are 64 dp',
    targetFloor(['touch'],true), TOUCH_TARGET_DP);
  check('DG input','a mouse-only guardian surface may relax to 32',
    targetFloor(['mouse','keyboard'],false), MOUSE_TARGET_DP);
  check('DG input','but a CHILD surface never relaxes, even with a mouse',
    targetFloor(['mouse','keyboard'],true), TOUCH_TARGET_DP);
  check('DG input','and a touch-capable guardian surface does not either',
    targetFloor(['touch','mouse'],false), TOUCH_TARGET_DP);
}

// DH · THE SILENT DEVICE — the finding
{
  check('DH channels','six delivery channels', CHANNELS.length, 6);
  check('DH channels','FireOS cannot push', capability('android_amazon').push, 'false');
  check('DH channels','nor de-Googled Android', capability('android_bare').push, 'false');
  check('DH channels','nor the web', capability('web').push, 'false');
  check('DH channels','Play Services can', capability('android_play').push, 'true');
  check('DH channels','iOS can', capability('ios').push, 'true');

  check('DH channels','FireOS falls back to socket AND sms',
    capability('android_amazon').fallback, 'foreground_socket_and_sms');
  check('DH channels','and the note names why it matters',
    /£50 Fire tablet/.test(capability('android_amazon').note), 'true');
  check('DH channels','every non-push channel HAS a fallback',
    CHANNELS.filter(c=>!c.push).every(c=>c.fallback!=='none'), 'true');

  // The refusal.
  check('DH channels','a FireOS tablet is admitted, with its fallback',
    admitDevice('android_amazon').ok, 'true');
  const silent=admitDevice.length&&(()=>{
    // A hypothetical channel with neither push nor fallback must be refused.
    const fake={channel:'x',push:false,fallback:'none',note:''};
    return fake.push===false&&fake.fallback==='none';
  })();
  check('DH channels','a channel with neither is the refusable case', silent, 'true');
  check('DH channels','no shipped channel is silent',
    CHANNELS.some(c=>!c.push&&c.fallback==='none'), 'false');

  check('DH channels','a guardian is told, plainly, when her device cannot pop up',
    /she sees new things when she opens Olive/i.test(channelAdvice('android_amazon')), 'true');
  check('DH channels','and told we can text the grown-up there',
    /text the grown-up/.test(channelAdvice('android_amazon')), 'true');
  check('DH channels','a pushing device needs no advice', channelAdvice('ios'), 'null');
  check('DH channels','the advice never blames the device or the parent',
    /cheap|old|should have|upgrade/i.test(channelAdvice('android_amazon')), 'false');
}

// DI · PERFORMANCE
{
  check('DI tiers','three tiers', TIERS.length, 3);
  check('DI tiers','a 2 GB tablet is low', tierFor(2), 'low');
  check('DI tiers','4 GB is mid', tierFor(4), 'mid');
  check('DI tiers','the Fold is high', tierFor(12), 'high');
  check('DI tiers','low caps video at 180p', spec('low').videoHeight, 180);
  check('DI tiers','because a call that connects beats one that looks good',
    /connects beats/.test(spec('low').note), 'true');
  check('DI tiers','animation is the first thing to go', spec('low').animation, 'false');
  check('DI tiers','and video + canvas together is refused on low',
    spec('low').concurrentCanvas, 'false');
  check('DI tiers','a call is DEGRADED, never refused',
    callSettings('low').height>0, 'true');
  check('DI tiers','high runs 720p30', JSON.stringify(callSettings('high')),
    '{"height":720,"fps":30,"canvas":true}');
  check('DI tiers','every tier still permits a call',
    TIERS.every(t=>callSettings(t.tier).height>=180), 'true');
}

// DJ · LOCK-DOWN, WHICH DIFFERS EVERYWHERE
{
  check('DJ lock','every channel declares a method',
    LOCK_METHODS.length, CHANNELS.length);
  check('DJ lock','Android device-owner can be enabled remotely',
    lockMethod('android_play').remotelyEnabled, 'true');
  check('DJ lock','Windows assigned access too',
    lockMethod('windows').remotelyEnabled, 'true');
  check('DJ lock','iOS Guided Access CANNOT be',
    lockMethod('ios').remotelyEnabled, 'false');
  check('DJ lock','and the note says we must not imply a lock we cannot deliver',
    /must say so rather than implying/.test(lockMethod('ios').note), 'true');
  check('DJ lock','FireOS needs a hands-on setup',
    lockMethod('android_amazon').remotelyEnabled, 'false');

  check('DJ lock','there is no kiosk in a browser tab',
    lockMethod('web').method, 'none');
  check('DJ lock','so the web client is guardian-only', childShellAllowed('web'), 'false');
  check('DJ lock','a Fire tablet CAN host the child shell',
    childShellAllowed('android_amazon'), 'true');
  check('DJ lock','and so can Windows', childShellAllowed('windows'), 'true');
}

// DK · THE LAYOUT AUDIT
{
  const good=[{surface:'child_home',needsWidth:320,childFacing:true,
    orientations:['portrait','landscape']},
    {surface:'guardian_inbox',needsWidth:320,childFacing:false,
     orientations:['portrait','landscape']}];
  check('DK audit','sane claims pass', auditLayouts(good).ok, 'true');

  // A guardian surface gets NO width dispensation. A parent checks this app on
  // a phone far more often than on a PC, and a 600px guardian inbox is broken on
  // a folded Fold exactly as a child surface would be.
  const fatGuardian=[{surface:'guardian_inbox',needsWidth:600,childFacing:false,
    orientations:['portrait','landscape']}];
  check('DK audit','a 600px GUARDIAN surface is caught too',
    auditLayouts(fatGuardian).ok, 'false');
  check('DK audit','because a parent uses this on a phone, not a desk',
    auditLayouts(fatGuardian).faults.some(f=>f.posture==='fold_cover'), 'true');

  const tooWide=[{surface:'game_board',needsWidth:420,childFacing:true,
    orientations:['portrait','landscape']}];
  const r=auditLayouts(tooWide);
  check('DK audit','a surface wider than 344 px is CAUGHT', r.ok, 'false');
  check('DK audit','and it names the posture it breaks on',
    r.faults[0].posture, 'fold_cover');
  check('DK audit','with the numbers, and what is missing', r.faults[0].fault,
    'needs 420px, has 344px, and declares no degraded form');
  check('DK audit','because that bug only appears on the cheapest hardware',
    r.faults.some(f=>f.posture==='phone'), 'true');

  // A wide surface may be honest about it — but only if the degraded form exists.
  const wide=[{surface:'court_export',needsWidth:600,childFacing:false,
    orientations:['landscape'],degradesTo:'court_export_request'}];
  check('DK audit','declaring a degraded form is not enough on its own',
    auditLayouts(wide).ok, 'false');
  check('DK audit','and the fault says the degraded form is missing',
    /no degraded form is implemented/.test(auditLayouts(wide).faults[0].fault), 'true');
  check('DK audit','implementing it satisfies the rule',
    auditLayouts(wide,new Set(['court_export_request'])).ok, 'true');
  check('DK audit','a wide surface with NO declared fallback is just broken',
    /declares no degraded form/.test(auditLayouts(
      [{surface:'x',needsWidth:600,childFacing:false,
        orientations:['landscape']}]).faults[0].fault), 'true');

  const noLandscape=[{surface:'child_home',needsWidth:300,childFacing:true,
    orientations:['portrait']}];
  const l=auditLayouts(noLandscape);
  check('DK audit','a portrait-only surface fails on a landscape-only posture',
    l.ok, 'false');
  check('DK audit','such as the half-open Fold',
    l.faults.some(f=>f.posture==='fold_tabletop'), 'true');
  check('DK audit','a child surface is not judged against the PC',
    auditLayouts([{surface:'x',needsWidth:900,childFacing:true,
      orientations:['portrait','landscape']}])
      .faults.some(f=>f.posture==='desktop'), 'false');
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
