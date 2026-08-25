/**
 * toddler.ts — MASTERFILE §8.10, the two-to-four shell. Zero test coverage
 * anywhere in this repository before this file, and not mentioned in
 * CHANGELOG.md or README.md at all — the quietest of the four zero-coverage
 * modules this pass closes.
 *
 * Every real exported function/const is exercised directly, including the
 * night/day boundary logic in toddlerScreen() (§8.10) and the absence-
 * detection threshold in absencePrompt() (§8.10.1) — the two places a
 * boundary-condition bug would be easiest to introduce silently.
 */
import {
  TODDLER_MAX_AGE, isToddler, TAP_TARGET_PX, MAX_CONTROLS_ON_SCREEN,
  toddlerScreen, ABSENCE_SECONDS_BEFORE_PROMPT, absencePrompt,
  goodbyeOnHerBehalf, NOT_IN_TODDLER_SHELL, availableToToddler, TODDLER_KEEPS,
  graduatesAt,
} from '../src/toddler.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// ===========================================================================
// A · isToddler() — the real age boundary
// ===========================================================================
{
  check('A isToddler', 'age 0 is a toddler', isToddler(0), 'true');
  check('A isToddler', 'the real max toddler age is included', isToddler(TODDLER_MAX_AGE), 'true');
  check('A isToddler', 'one year past the real max is NOT a toddler',
    isToddler(TODDLER_MAX_AGE + 1), 'false');
  check('A isToddler', 'the real documented boundary is 4, not a different number',
    TODDLER_MAX_AGE, 4);
}

// ===========================================================================
// B · toddlerScreen() — controls, face state, and the night/day boundary
// ===========================================================================
{
  // Reachable, daytime, no recording.
  const day = toddlerScreen(true, false, 14);
  check('B toddlerScreen', 'reachable + daytime offers the call control', day.controls, 'call');
  check('B toddlerScreen', 'her face shows live', day.faceState, 'live');
  check('B toddlerScreen', 'the real, warm spoken prompt for this case',
    day.spoken, 'Tap Daddy to talk to him.');
  check('B toddlerScreen', 'the real fixed tap target size is always attached',
    day.tapTargetPx, TAP_TARGET_PX);

  // Reachable but NIGHT — sleeping wins over reachable, by design.
  const night = toddlerScreen(true, false, 22);
  check('B toddlerScreen', 'reachable but NIGHT still shows sleeping, not live — '
    + '"unavailable" is an adult concept the module explicitly avoids',
    night.faceState, 'sleeping');
  check('B toddlerScreen', 'no call control is offered at night even though he is '
    + 'technically reachable', night.controls, 'nothing');
  check('B toddlerScreen', 'the real gentle night line', night.spoken,
    'Daddy is asleep. You can see him in the morning.');

  // Exact night-boundary edges: 19:00 is night, 18:59 (18) is not; 06:00 is
  // day, 05:59 (5) is still night.
  check('B toddlerScreen', 'exactly hour 19 (7pm) is already night',
    toddlerScreen(true, false, 19).faceState, 'sleeping');
  check('B toddlerScreen', 'exactly hour 18 (6pm) is still day',
    toddlerScreen(true, false, 18).faceState, 'live');
  check('B toddlerScreen', 'exactly hour 6 (6am) is already day again',
    toddlerScreen(false, false, 6).faceState, 'photo');
  check('B toddlerScreen', 'exactly hour 5 (5am) is still night',
    toddlerScreen(true, false, 5).faceState, 'sleeping');

  // Unreachable, daytime, no recording.
  const away = toddlerScreen(false, false, 12);
  check('B toddlerScreen', 'unreachable + daytime shows a still photo, not live',
    away.faceState, 'photo');
  check('B toddlerScreen', 'no controls at all when unreachable with nothing to watch',
    away.controls, 'nothing');
  check('B toddlerScreen', 'the real "busy" line, distinct from the reachable one',
    away.spoken, 'Daddy is busy. He will be back.');

  // Unreachable, but a recording exists — watch_again appears; the SPOKEN
  // line changes even though faceState stays 'photo'.
  const recording = toddlerScreen(false, true, 12);
  check('B toddlerScreen', 'an available recording adds the watch_again control',
    recording.controls, 'watch_again');
  check('B toddlerScreen', 'face state is still a photo (he is not live)',
    recording.faceState, 'photo');
  check('B toddlerScreen', 'the spoken line names the real left-something case',
    recording.spoken, 'Daddy left you something.');

  // Reachable AND a recording exists at once — both controls, in order.
  const both = toddlerScreen(true, true, 12);
  check('B toddlerScreen', 'reachable + a recording offers BOTH controls together',
    both.controls.join(','), 'call,watch_again');
  check('B toddlerScreen', 'never exceeds the real max-controls-on-screen budget',
    both.controls.length <= MAX_CONTROLS_ON_SCREEN, 'true');
}

// ===========================================================================
// C · absencePrompt() — §8.10.1, the real 45-second threshold
// ===========================================================================
{
  check('C absencePrompt', 'well before the threshold, no offer at all',
    absencePrompt(0).offer, 'false');
  check('C absencePrompt', 'the moment just short of the real threshold is still no offer',
    absencePrompt(ABSENCE_SECONDS_BEFORE_PROMPT - 1).offer, 'false');
  check('C absencePrompt', 'no line is attached before the threshold either',
    absencePrompt(10).line, 'null');
  check('C absencePrompt', 'the exact real threshold, inclusive, DOES offer',
    absencePrompt(ABSENCE_SECONDS_BEFORE_PROMPT).offer, 'true');
  check('C absencePrompt', 'well past the threshold still offers',
    absencePrompt(300).offer, 'true');
  check('C absencePrompt', 'the real, gentle line — never framed as her fault or a failure',
    absencePrompt(60).line,
    'She seems to have wandered off. Wait a little, or say goodnight '
    + 'and we will tell her you did.');
  check('C absencePrompt', 'the real documented threshold is 45 seconds',
    ABSENCE_SECONDS_BEFORE_PROMPT, 45);
}

// ===========================================================================
// D · goodbyeOnHerBehalf() — told he said goodbye, not simply vanished
// ===========================================================================
{
  const bye = goodbyeOnHerBehalf();
  check('D goodbyeOnHerBehalf', 'the real, warm spoken line', bye.spoken,
    'Daddy said goodnight. He will see you soon.');
  check('D goodbyeOnHerBehalf', 'it is genuinely recorded as an artifact (something she '
    + 'can be shown/replayed), not merely a transient toast', bye.artifact, 'true');
}

// ===========================================================================
// E · availableToToddler() — the deliberate exclusion list, §8.10.2
// ===========================================================================
{
  check('E availableToToddler', 'a real excluded feature (games) is refused',
    availableToToddler('games'), 'false');
  check('E availableToToddler', 'settings is refused, same as every other shell',
    availableToToddler('settings'), 'false');
  check('E availableToToddler', 'a feature not on the exclusion list is available by default',
    availableToToddler('call'), 'true');
  check('E availableToToddler', 'every real NOT_IN_TODDLER_SHELL entry is individually refused',
    NOT_IN_TODDLER_SHELL.every((f) => availableToToddler(f) === false), 'true');
  check('E availableToToddler', 'every real TODDLER_KEEPS entry is available (the two '
    + 'lists never contradict each other)',
    TODDLER_KEEPS.every((f) => availableToToddler(f) === true), 'true');
}

// ===========================================================================
// F · TODDLER_KEEPS — the one deliberate exception (shared reading)
// ===========================================================================
{
  check('F TODDLER_KEEPS', 'shared_reading is genuinely one of the kept features — '
    + 'the module\'s own stated "one exception, and it is the important one"',
    TODDLER_KEEPS.includes('shared_reading'), 'true');
  check('F TODDLER_KEEPS', 'call is kept, matching the one-big-control design',
    TODDLER_KEEPS.includes('call'), 'true');
}

// ===========================================================================
// G · graduatesAt() — age-based, not achievement-based
// ===========================================================================
{
  check('G graduatesAt', 'graduation age is exactly one year past the real max toddler age',
    graduatesAt(), TODDLER_MAX_AGE + 1);
  check('G graduatesAt', 'the child at the graduation age is genuinely no longer a toddler',
    isToddler(graduatesAt()), 'false');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
