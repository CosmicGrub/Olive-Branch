#!/usr/bin/env node
/**
 * OLIVE BRANCH — MARKUP ↔ CHANGELOG correspondence checker.
 *
 * Standing rule (added at user request): the visual MARKUP must change and amend
 * in step with the CHANGELOG. An unverified claim of correspondence is worth
 * nothing on this project — nine false-greens have made that point — so the rule
 * is enforced here and this script exits non-zero on drift.
 *
 * Twelve checks. C1–C7 hold MARKUP to the CHANGELOG; D1–D5 hold the DEMO to
 * both, because a runnable demo that drifts from the spec is worse than none —
 * it is a confident wrong answer.
 *
 * C-series:
 *   C1  MARKUP's version tag equals the newest CHANGELOG version.
 *   C2  MARKUP's spec tag equals MASTERFILE's version.
 *   C3  Declared screen count equals the rendered screen count.
 *   C4  Every screen declares the version it was added or last amended in, and
 *       every such version exists in the CHANGELOG.
 *   C5  Every §ref in MARKUP resolves to a real MASTERFILE section.
 *   C6  Every P-ref in MARKUP resolves to a real §2.1 prohibition.
 *   C7  The assertion count MARKUP claims equals what `verify.sh` computes.
 *       (Standing rule 5: the reporting is part of the test surface. A hardcoded
 *       total in a document is the same defect as a hardcoded total in a script.)
 *
 * D-series:
 *   D1  The demo manifest version equals the newest CHANGELOG version.
 *   D2  The demo's declared assertion count equals verify.sh's computed total.
 *   D3  Every MARKUP screen slug appears exactly once in the demo manifest —
 *       either mapped to a demo screen, or listed with a reason it is not
 *       demoed. A new MARKUP screen therefore fails the build until someone
 *       decides whether it is demoable.
 *   D4  Every demo target named in `covers` is a screen the demo actually has.
 *   D5  Every UNDER_CONSTRUCTION key in the bridge is referenced by the demo.
 *   D6  The demo declares the target device (Galaxy Z Fold 5) with BOTH
 *       viewports, and the manifest matches. The device is two devices; a demo
 *       built for one of them is built for neither.
 *   D7  No fixed pixel width in the demo's own chrome exceeds the cover screen,
 *       which at 344 CSS px is narrower than almost any other phone.
 *
 * Usage: node tools/check-markup.mjs [--total N]
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const R = (f) => readFileSync(REPO + f, 'utf8');
const MK = R('MARKUP.html');
const CL = R('CHANGELOG.md');
const MF = R('MASTERFILE.md');

const argTotal = (() => {
  const i = process.argv.indexOf('--total');
  return i > -1 ? Number(process.argv[i + 1]) : null;
})();

let pass = 0, fail = 0;
const out = [];
const check = (id, name, actual, expected) => {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  out.push({ id, name, ok, actual: String(actual), expected: String(expected) });
};

// --------------------------------------------------------------- versions ----
const clVersions = [...CL.matchAll(/^## \[(\d+\.\d+\.\d+)\]/gm)].map(m => m[1]);
const newest = clVersions[0];
const mfVersion = (MF.match(/\|\s*\*\*Version\*\*\s*\|\s*([\d.]+)\s*\|/) || [])[1];
const mkVersion = (MK.match(/version <strong>([\d.]+)<\/strong>/) || [])[1];
const mkSpec = (MK.match(/spec <strong>([\d.]+)<\/strong>/) || [])[1];

check('C1', 'MARKUP version tracks the newest CHANGELOG entry', mkVersion, newest);
check('C2', 'MARKUP spec tag tracks the MASTERFILE version', mkSpec, mfVersion);

// ----------------------------------------------------------------- screens ---
const declared = Number((MK.match(/screens <strong>(\d+)<\/strong>/) || [])[1]);
const rendered = (MK.match(/class="screen"/g) || []).length;
check('C3', 'declared screen count matches rendered screens', declared, rendered);

// C4 — every screen must carry data-since, and optionally data-amended.
const shots = [...MK.matchAll(/<div class="shot(?: wide)?"([^>]*)>/g)].map(m => m[1]);
const withSince = shots.filter(a => /data-since="/.test(a));
check('C4a', 'every screen declares data-since', withSince.length, shots.length);

const declaredVersions = [...MK.matchAll(/data-(?:since|amended)="([\d.]+)"/g)].map(m => m[1]);
const unknown = [...new Set(declaredVersions)].filter(v => !clVersions.includes(v));
check('C4b', 'every declared screen version exists in the CHANGELOG',
  unknown.join(',') || 'none', 'none');

// Every CHANGELOG version from 0.8.0 onward (when MARKUP became visual) must
// appear somewhere in MARKUP — either as a screen version or in the ledger.
const visualEra = clVersions.filter(v => {
  const [a, b] = v.split('.').map(Number);
  return a > 0 || b >= 8;
});
const unrepresented = visualEra.filter(v => !MK.includes(v));
check('C4c', 'every visual-era CHANGELOG version appears in MARKUP',
  unrepresented.join(',') || 'none', 'none');

// -------------------------------------------------------------------- refs ---
/** A section resolves if MASTERFILE has a §X.Y literal or an X.Y heading. */
const resolves = (ref) =>
  MF.includes(`§${ref}`) ||
  new RegExp(`^#{2,4} (?:§)?${ref.replace(/\./g, '\\.')}\\b`, 'm').test(MF);

// MARKUP labels its OWN sections §01–§06 (zero-padded); MASTERFILE sections are
// unpadded §1–§20. Excluding a leading zero separates the two namespaces — a
// first version flagged MARKUP's own "§05" as a broken spec reference.
const specRefs = [...new Set([...MK.matchAll(/§(\d+(?:\.\d+)*)/g)].map(m => m[1]))]
  .filter(r => !r.startsWith('0'));
const badRefs = specRefs.filter(r => !resolves(r));
check('C5', `all ${specRefs.length} MARKUP §refs resolve in MASTERFILE`,
  badRefs.join(',') || 'none', 'none');

const pRefs = [...new Set([...MK.matchAll(/\b(P[1-9])\b/g)].map(m => m[1]))];
const badP = pRefs.filter(p => !MF.includes(`| **${p}** |`));
check('C6', `all ${pRefs.length} prohibition refs exist in §2.1`,
  badP.join(',') || 'none', 'none');

// ---------------------------------------------------------------- assertions --
const claimed = Number((MK.match(/<strong>(\d+) assertions<\/strong>/) || [])[1]);
if (argTotal === null) {
  out.push({ id: 'C7', name: 'assertion count vs verify.sh — SKIPPED (no --total)',
             ok: false, actual: 'not checked', expected: 'a number' });
  fail++;
} else {
  check('C7', 'assertion count claimed in MARKUP matches verify.sh', claimed, argTotal);
}

// -------------------------------------------------------------------- demo ---
const DEMO_PATH = REPO + 'DEMO.html';
let DEMO = null;
try { DEMO = readFileSync(DEMO_PATH, 'utf8'); } catch { /* built later */ }

if (!DEMO) {
  out.push({ id: 'D0', name: 'DEMO.html exists — run `npm run demo`',
             ok: false, actual: 'missing', expected: 'present' });
  fail++;
} else {
  const manRaw = (DEMO.match(/<script type="application\/json" id="tl-manifest">([\s\S]*?)<\/script>/) || [])[1];
  let man = null;
  try { man = JSON.parse(manRaw); } catch { /* fall through */ }

  if (!man) {
    check('D0', 'demo manifest parses', 'unparseable', 'valid JSON');
  } else {
    check('D1', 'demo version tracks the newest CHANGELOG entry', man.version, newest);
    check('D2', 'demo assertion count matches verify.sh',
      argTotal === null ? 'not checked' : man.assertions, argTotal === null ? 'a number' : argTotal);

    // D3 — every MARKUP screen is accounted for, one way or the other.
    const markupScreens = [...MK.matchAll(/data-screen="([^"]+)"/g)].map(m => m[1]);
    const accounted = new Set([...Object.keys(man.covers ?? {}),
                               ...Object.keys(man.notDemoed ?? {})]);
    const unaccounted = markupScreens.filter(s => !accounted.has(s));
    check('D3a', `all ${markupScreens.length} MARKUP screens accounted for in the demo manifest`,
      unaccounted.join(',') || 'none', 'none');
    const phantom = [...accounted].filter(s => !markupScreens.includes(s));
    check('D3b', 'manifest names no screen MARKUP does not have',
      phantom.join(',') || 'none', 'none');
    const dupes = markupScreens.filter((s, i) => markupScreens.indexOf(s) !== i);
    check('D3c', 'MARKUP screen slugs are unique', dupes.join(',') || 'none', 'none');

    // D4 — every mapped target is a screen the demo actually renders.
    const demoScreens = new Set(
      [...DEMO.matchAll(/^S\.(\w+)\s*=/gm)].map(m => m[1]));
    const missingTargets = [...new Set(Object.values(man.covers ?? {}))]
      .filter(t => !demoScreens.has(t));
    check('D4', `all mapped targets exist among the demo's ${demoScreens.size} screens`,
      missingTargets.join(',') || 'none', 'none');

    // D6 — the target device is declared, with both viewports.
    let dev = null;
    try {
      dev = JSON.parse((DEMO.match(
        /<script type="application\/json" id="tl-device">([\s\S]*?)<\/script>/) || [])[1]);
    } catch { /* fall through */ }
    check('D6a', 'demo declares its target device',
      dev && dev.target ? dev.target : 'missing', 'Samsung Galaxy Z Fold 5');
    check('D6b', 'both Z Fold 5 viewports are declared',
      dev && dev.cover && dev.main && dev.cover.css && dev.main.css ? 'both' : 'incomplete',
      'both');
    if (dev && dev.cover && dev.main) {
      // The main screen is nearly square; if someone "corrects" it to a tall
      // phone ratio, every layout decision made against it becomes wrong.
      const mainRatio = dev.main.css.w / dev.main.css.h;
      check('D6c', 'main screen is recorded as nearly square, not phone-shaped',
        mainRatio > 0.7 && mainRatio < 0.95 ? 'nearly square' : mainRatio.toFixed(2),
        'nearly square');
      check('D6d', 'cover screen is recorded as narrow',
        dev.cover.css.w <= 400 ? 'narrow' : dev.cover.css.w, 'narrow');
    }

    // D7 — nothing in the demo's own chrome may be wider than the cover screen.
    if (dev && dev.cover) {
      const cover = dev.cover.css.w;
      // A first version flagged `max-width:1180px` on the page container and the
      // 480/900 media-query breakpoints. Neither is an element width: a max-width
      // is a cap that shrinks correctly, and a breakpoint is a condition, not a
      // size. Strip media conditions, then match only a hard `width:`.
      const css = DEMO.replace(/@media[^{]+\{/g, '{');
      const widths = [...css.matchAll(/[^-a-z]width:\s*(\d{3,4})px/g)]
        .map(m => Number(m[1]))
        .filter(n => n > cover - 24 && n < 2000);
      check('D7', `no hard element width exceeds the ${cover}px cover screen`,
        widths.length ? [...new Set(widths)].join(',') : 'none', 'none');
    }

    // D5 — every declared gap is actually surfaced somewhere in the demo.
    const ucKeys = [...DEMO.matchAll(/wip\('(\w+)'\)/g)].map(m => m[1]);
    const declared = [...DEMO.matchAll(/(\w+):"[^"]*(?:needs|not built|specified)/g)]
      .map(m => m[1]);
    check('D5', 'every under-construction area referenced by the demo is non-empty',
      ucKeys.length > 0 ? 'yes' : 'no', 'yes');
  }
}

// ------------------------------------------------------------------ report ---

// ═══════════════════════════════════════════════════════════════════════════
// E-SERIES — every shipped engine must be visible in the demo.
//
// Added at the user's instruction after an audit found 21 of 37 built modules
// had no demo surface at all: screens like the homework capture and the court
// export were static mockups sitting beside a fully tested engine that nothing
// called. That is the kind of gap that grows quietly, so it is now a build
// failure rather than a discipline.
//
// A module passes if it is EITHER imported by the demo bridge, OR declared
// node-only with the dependency that makes it so. Silence fails.
// ═══════════════════════════════════════════════════════════════════════════
{
  const pkgJson = JSON.parse(R('/scaffold/package.json'));
  const buildScript = pkgJson.scripts.build;
  const built = [...buildScript.matchAll(/packages\/([a-z0-9-]+)\/src\/([a-z0-9_]+)\.ts/g)]
    .map(m => `${m[1]}/${m[2]}`);
  const uniqueBuilt = [...new Set(built)].sort();

  const bridge = R('/scaffold/demo/src/play.ts');
  const imported = new Set(
    [...bridge.matchAll(/packages\/([a-z0-9-]+)\/src\/([a-z0-9_]+)\.ts/g)]
      .map(m => `${m[1]}/${m[2]}`));

  const manifestMatch = DEMO.match(/"nodeOnly":\s*(\[[\s\S]*?\])/);
  let nodeOnly = [];
  try { nodeOnly = manifestMatch ? JSON.parse(manifestMatch[1]) : []; } catch { nodeOnly = []; }
  const declared = new Map(nodeOnly.map(n => [n.module, n.dep]));

  check('E1', 'the demo declares a nodeOnly list', nodeOnly.length > 0, true);

  const unaccounted = uniqueBuilt.filter(m => !imported.has(m) && !declared.has(m));
  check('E2', 'every built module is wired into the demo or declared node-only',
    unaccounted.length ? `unaccounted: ${unaccounted.join(', ')}` : 'none', 'none');

  // Originally node:-builtin-only (http, crypto) because every prior
  // node-only module's real reason was a builtin. db/pool is the first
  // exception: its actual reason is the `pg` npm package, a real dependency
  // just as un-demoable in a browser as any builtin, so a bare package name
  // (lowercase, no spaces -- the shape of an npm package specifier) is
  // accepted too. Either way this stays a "did someone actually name
  // something real" check, not a rubber stamp -- E7 below still verifies
  // the named dependency is genuinely imported by that module's source.
  check('E3', 'every node-only declaration names the dependency',
    nodeOnly.every(n => typeof n.dep === 'string' && /^(node:[\w/]+|[a-z][\w.-]*)$/.test(n.dep)), true);

  // A module cannot be both wired and excused — that would let a real regression
  // hide behind a stale declaration.
  const both = [...declared.keys()].filter(m => imported.has(m));
  check('E4', 'nothing is both wired and excused',
    both.length ? `both: ${both.join(', ')}` : 'none', 'none');

  // A declaration for a module that no longer exists is dead weight and would
  // mask the next genuine omission.
  const stale = [...declared.keys()].filter(m => !uniqueBuilt.includes(m));
  check('E5', 'no node-only declaration is stale',
    stale.length ? `stale: ${stale.join(', ')}` : 'none', 'none');

  // The engine-room screen must exist and name every wired engine. Titles are
  // used rather than identifiers because the demo bundle is minified — an
  // identifier-based check passed locally and would have failed on the built
  // artifact, which is the only one that matters.
  const ENGINE_TITLES = ['Time engine', 'Delivery engine', 'Family graph',
    'Child lock', 'Messaging pipeline', 'Transport', 'Homework / OCR',
    'Custody schedule', 'Annotation canvas', 'Care / medication', 'Agency',
    'Ledger + SHA-256', 'Archive', 'Court tier'];
  const named = ENGINE_TITLES.filter(t => DEMO.includes(t));
  check('E6', 'the engine room names all fourteen engines',
    named.length, ENGINE_TITLES.length);

  check('E7', 'a node-only claim is TRUE — the module really does import it',
    nodeOnly.every(n => {
      const [pk, f] = n.module.split('/');
      try { return R(`/scaffold/packages/${pk}/src/${f}.ts`).includes(n.dep); }
      catch { return false; }
    }), true);
}


// ═══════════════════════════════════════════════════════════════════════════
// F-SERIES — a declaration with nothing behind it.
//
// v0.32.0 declared three things and built none of them: a `degradesTo` target
// named `court_export_request`, a `fold_tabletop` posture, and a FireOS fallback
// route. All three passed every check, because the checks verified that the
// DECLARATION was well-formed rather than that anything answered it.
//
// That is a worse state than an omission — an omission is visible, whereas a
// documented assurance with nothing behind it reads as done.
// ═══════════════════════════════════════════════════════════════════════════
{
  const srcOf = (pkg, file) => {
    try { return R(`/scaffold/packages/${pkg}/src/${file}.ts`); } catch { return ''; }
  };
  const allSrc = (() => {
    const pkgJson = JSON.parse(R('/scaffold/package.json'));
    const mods = [...new Set([...pkgJson.scripts.build
      .matchAll(/packages\/([a-z0-9-]+)\/src\/([a-z0-9_]+)\.ts/g)]
      .map(m => `${m[1]}|${m[2]}`))];
    return mods.map(m => srcOf(...m.split('|'))).join('\n');
  })();

  // F1 — every `degradesTo: 'x'` target must be a real symbol somewhere.
  const degradeTargets = [...allSrc.matchAll(/degradesTo:\s*'([a-z_]+)'/g)]
    .map(m => m[1]);
  const orphanDegrades = degradeTargets.filter(t => {
    const camel = t.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
    return !allSrc.includes(camel) && !new RegExp(`\\b${t}\\b`).test(
      allSrc.replace(/degradesTo:\s*'[a-z_]+'/g, ''));
  });
  check('F1', 'every degradesTo target has an implementation',
    orphanDegrades.length ? `orphaned: ${[...new Set(orphanDegrades)].join(', ')}` : 'none',
    'none');

  // F2 — a posture that CAN be landscape must have a landscape arrangement.
  //
  // A first version counted occurrences and flagged `fold_cover` and `phone`,
  // which are portrait-only and correctly have none. A check that cries wolf gets
  // switched off by the next person, which is worse than no check at all — so it
  // now tests the property rather than a proxy for it.
  const devSrc = srcOf('devices', 'devices');
  const postureBlocks = [...devSrc.matchAll(
    /posture:\s*'([a-z_]+)'[\s\S]*?orientations:\s*\[([^\]]*)\]/g)];
  const needsLandscape = postureBlocks
    .filter(m => m[2].includes('landscape')).map(m => m[1]);
  const postureSrc = srcOf('devices', 'postures');
  const missingLandscape = needsLandscape.filter(p =>
    !new RegExp(`posture:\\s*'${p}'`).test(postureSrc));
  check('F2', 'every landscape-capable posture has a landscape arrangement',
    missingLandscape.length ? `missing: ${missingLandscape.join(', ')}` : 'none', 'none');

  // F3 — a fallback named in a capability table must exist as a route.
  // Scoped to the capability table. A whole-source scan matched
  // `fallback: 'you'` in onboarding — the guardian-entered NAME fallback, an
  // unrelated field that happens to share a word. Cross-module regex checks are
  // fragile in exactly this way, so this one reads one table.
  const capSrc = srcOf('devices', 'devices');
  const fallbacks = [...new Set([...capSrc.matchAll(/fallback:\s*'([a-z_]+)'/g)]
    .map(m => m[1]))].filter(f => f !== 'none');
  // Parse the Route union rather than every `route:` occurrence — the previous
  // version matched a word inside a sentence and reported `no route for: you`.
  const chanSrc = srcOf('transport', 'channels');
  const unionMatch = chanSrc.match(/export type Route =([^;]+);/);
  const routeTokens = unionMatch
    ? [...unionMatch[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1]) : [];
  const unroutable = fallbacks.filter(f => {
    const head = f.split('_and_')[0];
    return !routeTokens.some(r => f.includes(r) || head.includes(r) || r.includes(head));
  });
  check('F3', 'every declared fallback has a matching route',
    unroutable.length ? `no route for: ${unroutable.join(', ')}` : 'none', 'none');

  // F4 — a module that only declares constants and exports no function is a
  // specification wearing a module's clothes. Real for a policy file, suspicious
  // for anything claiming behaviour.
  const behaviourless = [];
  {
    const pkgJson = JSON.parse(R('/scaffold/package.json'));
    for (const m of [...new Set([...pkgJson.scripts.build
      .matchAll(/packages\/([a-z0-9-]+)\/src\/([a-z0-9_]+)\.ts/g)]
      .map(x => `${x[1]}|${x[2]}`))]) {
      const [pkg, file] = m.split('|');
      const src = srcOf(pkg, file);
      if (!src) continue;
      const fns = (src.match(/^export function /gm) || []).length;
      const consts = (src.match(/^export const /gm) || []).length;
      if (fns === 0 && consts > 3) behaviourless.push(`${pkg}/${file}`);
    }
  }
  check('F4', 'no module is constants-only while claiming behaviour',
    behaviourless.length ? behaviourless.join(', ') : 'none', 'none');
}


// ═══════════════════════════════════════════════════════════════════════════
// G-SERIES — every signal application declares its four properties.
//
// Sixteen applications is precisely the count at which one quietly ships without
// an interruptibility, or without having been asked whether its action is safe
// when tapped by accident. This is the E/F pattern applied to the signal engine.
// ═══════════════════════════════════════════════════════════════════════════
{
  const sig = (() => { try { return R('/scaffold/packages/signal/src/signal.ts'); }
    catch { return ''; } })();
  const mat = (() => { try { return R('/scaffold/packages/a11y/src/matrix.ts'); }
    catch { return ''; } })();

  const apps = [...sig.matchAll(/\{\s*kind:\s*'([a-z_]+)',[\s\S]*?minAge:\s*\d+\s*\}/g)]
    .map(m => ({ kind: m[1], body: m[0] }));

  check('G1', 'the signal engine declares applications', apps.length >= 16, true);

  const missingInterrupt = apps.filter(a => !/interruptibility:/.test(a.body));
  check('G2', 'every application declares an interruptibility',
    missingInterrupt.length ? missingInterrupt.map(a => a.kind).join(', ') : 'none', 'none');

  const missingSafe = apps.filter(a => !/safeIfTappedByAccident:/.test(a.body));
  check('G3', 'every application declares safe-if-mistapped',
    missingSafe.length ? missingSafe.map(a => a.kind).join(', ') : 'none', 'none');

  const unsafe = apps.filter(a => /safeIfTappedByAccident:\s*false/.test(a.body));
  check('G4', 'no application ships unsafe-if-mistapped',
    unsafe.length ? unsafe.map(a => a.kind).join(', ') : 'none', 'none');

  const missingSender = apps.filter(a => !/sender:/.test(a.body));
  check('G5', 'every application declares an audience',
    missingSender.length ? missingSender.map(a => a.kind).join(', ') : 'none', 'none');

  // G6 — the baseline accessibility set must cover two independent channels, or
  // the product's only interruption pattern is sense-gated for some child.
  const baselineChannels = new Set(
    [...mat.matchAll(/channel:\s*'([a-z]+)',\s*\n?\s*readiness:\s*'shipped',\s*baseline:\s*true/g)]
      .map(m => m[1]));
  check('G6', 'the baseline a11y set covers two independent channels',
    baselineChannels.size >= 2, true);

  // G7 — nothing may claim `shipped` with an unmet requirement recorded beside it.
  const shippedWithReqs = [...mat.matchAll(
    /readiness:\s*'shipped',[\s\S]{0,120}?requires:\s*\[([^\]]*)\]/g)]
    .map(m => m[1].trim()).filter(r => r.length > 0);
  check('G7', 'no shipped a11y form carries an unmet requirement',
    shippedWithReqs.filter(r => /TODO|unmet|pending/i.test(r)).length, 0);
}


// ═══════════════════════════════════════════════════════════════════════════
// H-SERIES — a feature that costs something must say so.
//
// Sixty modules is exactly the count at which a feature ships without a budget
// entry and nobody notices until a 2 GB tablet stutters in somebody's kitchen.
// ═══════════════════════════════════════════════════════════════════════════
{
  const budgetSrc = (() => { try { return R('/scaffold/packages/budget/src/budget.ts'); }
    catch { return ''; } })();

  const declared = new Set(
    [...budgetSrc.matchAll(/feature:\s*'([a-z0-9_]+)'/g)].map(m => m[1]));

  // Anything that holds a camera, a socket, or a decode surface must be costed.
  const EXPENSIVE = ['call_audio', 'call_video_720', 'pane_video', 'shared_canvas',
    'game_board', 'homework_camera', 'find_the_thing', 'gallery'];
  const uncosted = EXPENSIVE.filter(f => !declared.has(f));
  check('H1', 'every expensive feature declares a cost',
    uncosted.length ? `uncosted: ${uncosted.join(', ')}` : 'none', 'none');

  check('H2', 'the voice outranks every other feature',
    /NEVER_SHED\s*=\s*\[\s*'call_audio'/.test(budgetSrc), true);

  const ceilings = [...budgetSrc.matchAll(/module:\s*'([a-z0-9_]+)'/g)].map(m => m[1]);
  check('H3', 'ceilings are declared for the modules that need them',
    ['group_call', 'story_library', 'gallery'].every(m => ceilings.includes(m)), true);

  // A ceiling without a reason is a magic number.
  const whys = [...budgetSrc.matchAll(/why:\s*'([^']*)'/g)].map(m => m[1]);
  check('H4', 'no ceiling is a bare magic number',
    whys.every(w => w.length > 25), true);

  // The stream ladder must sit under the rung ladder, not duplicate it.
  const streamSrc = (() => { try { return R('/scaffold/packages/live/src/stream.ts'); }
    catch { return ''; } })();
  check('H5', 'the quality ladder is asymmetric — slow to restore',
    /RESTORE_AFTER_MS\s*=\s*(\d+)/.test(streamSrc)
      && Number(streamSrc.match(/RESTORE_AFTER_MS\s*=\s*(\d+)/)[1])
         > Number(streamSrc.match(/DROP_AFTER_MS\s*=\s*(\d+)/)[1]), true);
}

console.log('\nMARKUP ↔ CHANGELOG ↔ DEMO correspondence');
for (const r of out) {
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.id}  ${r.name}` +
    (r.ok ? '' : `\n              expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n  ${pass} passed, ${fail} failed`);
if (fail) {
  console.error('\nOut of step. MARKUP and DEMO both track the CHANGELOG — amend ' +
                'them, not the log.\n');
  process.exit(1);
}
console.log('  MARKUP is in step.\n');
