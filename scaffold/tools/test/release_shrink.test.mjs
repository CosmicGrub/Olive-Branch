/**
 * The release resource-shrinking guard (tools/check-release-shrink.mjs): pure cases that reproduce the original
 * defect and its legitimate alternatives, plus the real tree.
 * usage: node tools/test/release_shrink.test.mjs
 */
import { shrinkProblems, realTreeProblems } from '../check-release-shrink.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const gradle = (releaseBody) => `android {\n  buildTypes {\n    release {\n${releaseBody}\n    }\n  }\n}\n`;
const KEEP_XML = '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@string/*" />';
const KEEP_JITSI_XML = '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@string/dropbox_app_key,@string/other" />';
const PRO = '-keep class org.jitsi.meet.sdk.** { *; }\n';

check('explicit isShrinkResources = false passes', shrinkProblems(gradle('isShrinkResources = false'), '').length === 0);
check('Groovy-style shrinkResources false passes', shrinkProblems(gradle('shrinkResources false'), '').length === 0);
check('line removed (Flutter then enables shrinking) FAILS', shrinkProblems(gradle('signingConfig = null'), PRO, [KEEP_XML]).length === 1);
check('flipped to true with no keep rules FAILS', shrinkProblems(gradle('isShrinkResources = true'), '').length === 2);
check('true with keep.xml but no proguard rule FAILS', shrinkProblems(gradle('isShrinkResources = true'), '', [KEEP_XML]).length === 1);
check('true with proguard rule but no keep.xml FAILS', shrinkProblems(gradle('isShrinkResources = true'), PRO).length === 1);
check('true with broad @string/* keep and proguard rule passes', shrinkProblems(gradle('isShrinkResources = true'), PRO, [KEEP_XML]).length === 0);
check('true with named Jitsi string keep and proguard rule passes', shrinkProblems(gradle('isShrinkResources = true'), PRO, [KEEP_JITSI_XML]).length === 0);
check('a commented-out "isShrinkResources = false" does not count', shrinkProblems(gradle('// isShrinkResources = false\nx = 1'), PRO, [KEEP_XML]).length === 1);
check('a commented-out proguard keep does not count', shrinkProblems(gradle('isShrinkResources = true'), '# -keep class org.jitsi.meet.sdk.** { *; }', [KEEP_XML]).length === 1);
check('false in a debug block does not satisfy the release block',
  shrinkProblems('android { buildTypes { debug { isShrinkResources = false }\n release { x = 1 } } }', PRO, [KEEP_XML]).length === 1);
check('no release block is reported, not silently passed', shrinkProblems('android { }', '').length === 1);
check('CRLF input behaves the same', shrinkProblems(gradle('isShrinkResources = false').replace(/\n/g, '\r\n'), '').length === 0);

const real = realTreeProblems();
for (const p of real) console.log(`        ${p}`);
check('the real client/android/app tree is clean', real.length === 0);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
