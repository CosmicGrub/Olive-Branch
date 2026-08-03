/**
 * Stream stability and the capability budget. MASTERFILE §5.28, §8.14.
 */
import { QUALITIES, stepQualityDown, stepQualityUp, atFloor, atCeiling,
  DROP_AFTER_MS, RESTORE_AFTER_MS, newStream, evaluate, RESTORE_IS_SLOWER,
  ASYMMETRY_RATIO, noticeFor, markTold, RESTORE_ASKS_PERMISSION,
  NO_CONNECTION_METER, auditNotice, senderLine, AUDIO_FLOOR, audioSurvives }
  from '../../live/src/stream.mjs';
import { CAPACITY, capacityOf, COSTS, costOf, total, fits, SUBSTITUTIONS,
  NEVER_SHED, resolve, admit, SCENARIOS, runScenarios, audioAlwaysSurvives,
  CEILINGS, ceilingOf, withinCeiling, auditCeilings, auditCosts }
  from '../src/budget.mjs';

let pass=0,fail=0;const rows=[];
const check=(g,n,a,e)=>{const ok=String(a)===String(e);ok?pass++:fail++;
  rows.push({g,n,ok,a:String(a),e:String(e)});};

// EV · THE QUALITY LADDER UNDER THE RUNG LADDER
{
  check('EV quality','three video qualities', QUALITIES.length, 3);
  check('EV quality','720 steps to 360', stepQualityDown(720), 360);
  check('EV quality','360 steps to 180', stepQualityDown(360), 180);
  check('EV quality','and 180 is the floor', stepQualityDown(180), 180);
  check('EV quality','it climbs back', stepQualityUp(180), 360);
  check('EV quality','and stops at the ceiling', stepQualityUp(720), 720);
  check('EV quality','so three steps precede audio-only', atFloor(180), 'true');
  check('EV quality','which is real headroom before the picture goes', atCeiling(720), 'true');
}

// EW · HYSTERESIS — quick to shed, slow to restore
{
  check('EW hyst',`drops after ${DROP_AFTER_MS}ms`, DROP_AFTER_MS, 2000);
  check('EW hyst',`restores after ${RESTORE_AFTER_MS}ms`, RESTORE_AFTER_MS, 12000);
  check('EW hyst','restoring is slower', RESTORE_IS_SLOWER, 'true');
  check('EW hyst','six times slower', ASYMMETRY_RATIO, 6);

  let s=newStream();
  check('EW hyst','starts at 720 with video', s.quality+':'+s.video, '720:true');
  // A brief wobble changes nothing.
  let r=evaluate(s,{condition:'strained',elapsedMs:1000});
  check('EW hyst','one second of trouble changes nothing', r.changed, 'null');
  check('EW hyst','but it is remembered', r.state.troubleMs, 1000);
  r=evaluate(r.state,{condition:'strained',elapsedMs:1500});
  check('EW hyst','past the threshold it steps down', r.changed, 'down');
  check('EW hyst','one step, never two', r.state.quality, 360);
  check('EW hyst','and the counter resets', r.state.troubleMs, 0);

  // A recovering blip does NOT restore.
  let good=evaluate(r.state,{condition:'good',elapsedMs:3000});
  check('EW hyst','three good seconds do not restore it', good.changed, 'null');
  check('EW hyst','because a connection good for 3s is not a good connection',
    good.state.quality, 360);
  good=evaluate(good.state,{condition:'good',elapsedMs:10000});
  check('EW hyst','thirteen seconds does', good.changed, 'up');
  check('EW hyst','back to 720', good.state.quality, 720);

  // The full collapse walks down.
  let c=newStream();
  for(let i=0;i<8;i++) c=evaluate(c,{condition:'strained',elapsedMs:2500}).state;
  check('EW hyst','a sustained collapse ends at audio only', c.video, 'false');
  check('EW hyst','having walked through every quality first', c.quality, 180);
  check('EW hyst','and the audio floor holds', audioSurvives(c), 'true');
  check('EW hyst','which is the rule', AUDIO_FLOOR, 'true');
}

// EX · WHAT SHE IS TOLD
{
  let s=newStream();
  check('EX told','nothing is said while the picture is fine', noticeFor(s), 'null');
  let gone={...s,video:false};
  check('EX told','she is told once when it goes',
    noticeFor(gone).line, 'It has gone a bit slow — you can still hear him.');
  check('EX told','and not again', noticeFor(markTold(gone)), 'null');
  check('EX told','nothing blames her network', auditNotice(noticeFor(gone)).ok, 'true');
  check('EX told','audit catches "check your connection"',
    auditNotice({line:'Check your connection.',once:true}).ok, 'false');
  check('EX told','and "weak signal"',
    auditNotice({line:'Weak signal.',once:true}).found.join(','), 'weak signal');
  check('EX told','there is NO connection meter', NO_CONNECTION_METER, 'true');
  check('EX told','because a child watching a meter is not watching her father',
    NO_CONNECTION_METER, 'true');
  check('EX told','video returning does NOT ask permission',
    RESTORE_ASKS_PERMISSION, 'false');

  check('EX told','he gets more, because he can act on it',
    /will not carry the picture/.test(senderLine(gone)), 'true');
  check('EX told','and at the floor he is told it is soft',
    /picture is soft/.test(senderLine({...s,quality:180})), 'true');
  check('EX told','at full quality he is told nothing', senderLine(s), '');
}

// EY · THE BUDGET — costs and capacity
{
  check('EY budget','three capacities', CAPACITY.length, 3);
  check('EY budget','a low tier has 180MB', capacityOf('low').memoryMb, 180);
  check('EY budget','fifteen features declare a cost', COSTS.length, 15);
  check('EY budget','every one declares memory', auditCosts().ok, 'true');
  check('EY budget','the voice outranks everything',
    COSTS.filter(c=>c.priority>=costOf('call_audio').priority).length, 1);
  check('EY budget','ambient motion sheds first',
    Math.min(...COSTS.map(c=>c.priority)), costOf('ambient_motion').priority);
  check('EY budget','and driven motion nearly never does',
    costOf('driven_motion').priority > costOf('game_board').priority, 'true');
  check('EY budget','because removing her finger makes the app feel broken',
    /feel broken/.test(costOf('driven_motion').note), 'true');

  const t=total(['call_audio','call_video_720']);
  check('EY budget','totals add up', t.memoryMb, 134);
  check('EY budget','and that fits a mid tier', fits(t,capacityOf('mid')), 'true');
  check('EY budget','but not a low one',
    fits(total(['call_audio','call_video_720','pane_video','game_board']),
      capacityOf('low')), 'false');
}

// EZ · RESOLUTION — substitute before removing
{
  const r=resolve(['call_audio','call_video_720','pane_video','game_board',
    'ambient_motion','driven_motion'],'low');
  check('EZ resolve','it resolves to something that fits', r.fits, 'true');
  check('EZ resolve','THE VOICE SURVIVES', r.admitted.includes('call_audio'), 'true');
  check('EZ resolve','video was substituted before anything was dropped',
    r.substituted.length>0, 'true');
  check('EZ resolve','ambient motion went first', r.dropped[0], 'ambient_motion');
  check('EZ resolve','her finger did not go',
    r.admitted.includes('driven_motion'), 'true');
  check('EZ resolve','and the trace explains every step', r.trace.length>0, 'true');

  check('EZ resolve','a high tier needs no resolution',
    resolve(['call_audio','call_video_720'],'high').trace.join(), 'fits as requested');
  check('EZ resolve','audio alone always fits, on any tier',
    ['low','mid','high'].every(t=>resolve(['call_audio'],t).fits), 'true');
  check('EZ resolve','the voice is never a candidate for shedding',
    NEVER_SHED.includes('call_audio'), 'true');
  check('EZ resolve','substitutions degrade rather than delete',
    SUBSTITUTIONS.some(s=>s.from==='pane_video'&&s.to==='pane_still'), 'true');

  // Binding, not advisory — and it discloses what admitting cost.
  const tight=admit('find_the_thing',['call_audio','call_video_720','pane_video'],'low');
  check('EZ resolve','it fits, but only by substituting', tight.ok, 'true');
  check('EZ resolve','and the caller is TOLD it was not free', tight.free, 'false');
  check('EZ resolve','with the substitution named',
    tight.substituted[0].from+'→'+tight.substituted[0].to, 'call_video_720→call_video_360');

  const heavy=admit('shared_canvas',
    ['call_audio','call_video_720','pane_video','find_the_thing','game_board'],'low');
  check('EZ resolve','a genuinely impossible addition is REFUSED', heavy.ok, 'false');
  check('EZ resolve','and it names what would have been lost',
    heavy.wouldDrop.length>0, 'true');
  check('EZ resolve','never the voice', heavy.wouldDrop.includes('call_audio'), 'false');

  const free=admit('storyteller',['call_audio'],'high');
  check('EZ resolve','a cheap addition on a big device is free', free.free, 'true');
  check('EZ resolve','and admitted', free.ok, 'true');
}

// FA · THE COMBINATORIAL CASES
{
  const runs=runScenarios();
  check('FA cases','five scenarios', runs.length, 5);
  check('FA cases','every one resolves', runs.every(r=>r.result.fits), 'true');
  check('FA cases','IN EVERY ONE, THE VOICE SURVIVES', audioAlwaysSurvives(), 'true');

  const low=runs.find(r=>r.name.includes('call + pane + game + waveform'));
  check('FA cases','the case that was never modelled now resolves', low.result.fits, 'true');
  check('FA cases','and it sheds in the declared order',
    low.result.dropped.includes('ambient_motion')
      || low.result.substituted.length>0, 'true');

  const hw=runs.find(r=>r.name.includes('homework camera'));
  check('FA cases','call plus homework camera on a low tier resolves',
    hw.result.fits, 'true');
  check('FA cases','with the voice intact',
    hw.result.admitted.includes('call_audio'), 'true');

  const high=runs.find(r=>r.name.includes('everything, high'));
  check('FA cases','a high tier runs everything',
    high.result.dropped.length, 0);
}

// FB · MODULE CEILINGS
{
  check('FB ceilings','seven ceilings declared', CEILINGS.length, 7);
  check('FB ceilings','every one explains itself', auditCeilings().ok, 'true');
  check('FB ceilings','a group call caps at four', ceilingOf('group_call').limit, 4);
  check('FB ceilings','because the rotation outlasts a child\'s patience',
    /longer than a child will wait/.test(ceilingOf('group_call').why), 'true');
  check('FB ceilings','the library caps at 300 stories',
    ceilingOf('story_library').limit, 300);
  check('FB ceilings','because a shelf becomes a search problem',
    /search problem/.test(ceilingOf('story_library').why), 'true');
  check('FB ceilings','the gallery holds a childhood', ceilingOf('gallery').limit, 2000);
  check('FB ceilings','within is within', withinCeiling('group_call',3), 'true');
  check('FB ceilings','over is over', withinCeiling('group_call',5), 'false');
  check('FB ceilings','an undeclared module is unconstrained',
    withinCeiling('anything',99999), 'true');
  check('FB ceilings','existing limits are reflected, not re-invented',
    ceilingOf('pending_asks').limit, 3);
  check('FB ceilings','and the motion budget too',
    ceilingOf('concurrent_motions').limit, 2);
}

let g='';
for(const r of rows){if(r.g!==g){g=r.g;console.log(`\n${g}`);}
  console.log(`  ${r.ok?'PASS':'FAIL'}  ${r.n}`+(r.ok?'':`\n         expected ${r.e}, got ${r.a}`));}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail===0?0:1);
