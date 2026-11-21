/**
 * The update documentation says what the tools do (the standing rule: canonical docs match shipped behaviour, not just a version
 * number). A drift guard: every script the docs name exists, every flag a documented command uses exists in that script's source,
 * the limits the docs quote are the limits the validator enforces, and the files the docs promise are there.
 *
 * usage: node tools/test/update_docs.test.mjs
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { REPO } from '../release_lib.mjs';
import { LIMITS } from '../update/manifest_lib.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };
const rd = (p) => readFileSync(join(REPO, p), 'utf8').replace(/\r\n/g, '\n');

const releasing = rd('docs/RELEASING.md');
const manifestDoc = rd('docs/UPDATE-MANIFEST.md');
const notesDoc = rd('docs/release-notes/README.md');
const masterfile = rd('MASTERFILE.md');
const changelog = rd('CHANGELOG.md');
const g = 'docs';

// ---- every script named exists
const named = new Set();
for (const text of [releasing, manifestDoc, notesDoc, masterfile.slice(masterfile.indexOf('### 7.24a'), masterfile.indexOf('## §8 UI architecture')), changelog.slice(0, changelog.indexOf('## [0.5'))]) {
  for (const m of text.matchAll(/(?:tools\/update\/)([a-z_-]+\.mjs)/g)) named.add(m[1]);
}
check(g, 'the docs name every release script', ['build-update-package.mjs', 'check-release-tag.mjs', 'draft-release-notes.mjs', 'gen-update-key.mjs', 'sign-update-manifest.mjs', 'verify-update-release.mjs'].filter((n) => !named.has(n)), []);
for (const n of named) check(g, `tools/update/${n} exists`, existsSync(join(REPO, 'scaffold', 'tools', 'update', n)), true);
for (const f of ['docs/update-manifest.schema.json', 'docs/UPDATE-MANIFEST.md', 'docs/release-notes/README.md', 'scaffold/tools/update/test-vectors.json', '.github/workflows/release-artifacts.yml', 'scaffold/tools/check-flavors.mjs', 'scaffold/client/android/app/src/direct/AndroidManifest.xml', 'scaffold/client/android/app/src/play/AndroidManifest.xml']) {
  check(g, `${f} exists`, existsSync(join(REPO, f)), true);
}

// ---- every flag in a documented command exists in that script
const blocks = [...releasing.matchAll(/```bash\n([\s\S]*?)\n```/g)].map((m) => m[1]);
let flagsChecked = 0, flagsMissing = [];
for (const b of blocks) {
  const joined = b.replace(/\\\n\s*/g, ' ');
  for (const line of joined.split('\n')) {
    const m = /tools\/update\/([a-z_-]+\.mjs)\s+(.*)$/.exec(line);
    if (!m) continue;
    const src = readFileSync(join(REPO, 'scaffold', 'tools', 'update', m[1]), 'utf8');
    for (const f of m[2].match(/--[a-z][a-z0-9-]*/g) || []) { flagsChecked++; if (!src.includes(`'${f}'`)) flagsMissing.push(`${m[1]} ${f}`); }
  }
}
check(g, 'RELEASING.md documents commands with flags (so the next check means something)', flagsChecked >= 12, true);
check(g, 'every flag a documented command uses is implemented by that script', flagsMissing, []);

// ---- the limits the docs quote are the limits enforced
check(g, 'UPDATE-MANIFEST.md quotes the manifest size cap', manifestDoc.includes(`${LIMITS.manifestBytes / 1024} KiB`), true);
check(g, 'UPDATE-MANIFEST.md quotes the APK size cap in bytes', manifestDoc.includes(String(LIMITS.apkBytes)), true);
check(g, 'UPDATE-MANIFEST.md quotes the validity window', manifestDoc.includes(`${LIMITS.validityDays} days`), true);
check(g, 'UPDATE-MANIFEST.md quotes the note limits', [manifestDoc.includes(`At most ${LIMITS.notes} lines`), manifestDoc.includes(`1 to ${LIMITS.noteChars} characters`), manifestDoc.includes(`At most ${LIMITS.headlineChars} characters`)], [true, true, true]);
check(g, 'UPDATE-MANIFEST.md quotes the file and address counts', [manifestDoc.includes(`1 to ${LIMITS.apks} entries`), manifestDoc.includes(`1 to ${LIMITS.urls} addresses`), manifestDoc.includes(String(LIMITS.chunksMax))], [true, true, true]);
check(g, 'UPDATE-MANIFEST.md quotes the chunk size range', manifestDoc.includes(`${LIMITS.chunkMin / 1024} KiB to ${LIMITS.chunkMax / 1048576} MiB`), true);
check(g, 'the release-notes README quotes the same note limits', [notesDoc.includes(`at most ${LIMITS.headlineChars} characters`), notesDoc.includes(`At most ${LIMITS.noteChars} characters`), notesDoc.includes(`At most ${LIMITS.notes} of these`)], [true, true, true]);
check(g, 'RELEASING.md quotes the note limits', [releasing.includes(`${LIMITS.headlineChars}-character headline`), releasing.includes(`${LIMITS.notes} notes of ${LIMITS.noteChars} characters`)], [true, true]);

// ---- statements the docs make that tests above prove
check(g, 'RELEASING.md states the versionCode formula', releasing.includes('major*10000 + minor*100 + patch'), true);
check(g, 'the signing procedure says it runs offline and outside every repository', /offline/.test(releasing) && /outside any git working tree|outside any repo|outside[/]any[/]repo/.test(releasing), true);
check(g, 'RELEASING.md says CI signs nothing and holds no secret', /no secret and no signing step/.test(releasing), true);
check(g, 'MASTERFILE 7.24a says what is NOT built', /\*\*Not built \/ not run\.\*\*/.test(masterfile.slice(masterfile.indexOf('### 7.24a'))), true);
check(g, 'MASTERFILE 22.2 lists the app side as not built', masterfile.includes('| **In-app updates: the app side** |'), true);
check(g, 'the CHANGELOG [Unreleased] block describes the release side and what is not run', /App updates, the release side/.test(changelog) && /Not built \/ not run\./.test(changelog.slice(changelog.indexOf('App updates, the release side'), changelog.indexOf('## [0.5'))), true);
check(g, 'no document tells the owner to put the private key in the repository', /(commit|add|put|copy)[^.\n]{0,40}(private key|\.key\b)[^.\n]{0,40}(repo|repository)/i.test([releasing, manifestDoc, notesDoc].join('\n').replace(/never[^.\n]*/gi, '').replace(/not[^.\n]*inside[^.\n]*/gi, '')), false);
check(g, 'the notes folder holds only the README and published notes (no stray draft)', readdirSync(join(REPO, 'docs', 'release-notes')).filter((f) => f !== 'README.md').every((f) => /^\d+\.\d+\.\d+\.txt$/.test(f)), true);
check(g, 'no committed notes file is still a DRAFT', readdirSync(join(REPO, 'docs', 'release-notes')).filter((f) => f.endsWith('.txt')).every((f) => !/^#\s*DRAFT/m.test(rd(`docs/release-notes/${f}`))), true);

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
