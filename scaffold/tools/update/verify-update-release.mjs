#!/usr/bin/env node
/**
 * OLIVE BRANCH - check a PUBLISHED update end to end, with the same checks the app makes (docs/RELEASING.md, step "verify").
 *
 *   node tools/update/verify-update-release.mjs --manifest <https address | file> --pubkeys <kid:key,...> [options]
 *
 * It fetches the manifest and every APK address in it (primary and mirrors) and answers one question: would a phone that
 * follows this manifest install a good build, and refuse a bad one? Checks, in the app's order:
 *   manifest   size cap, strict JSON, the Ed25519 signature under the PUBLIC key you pass, shape and limits, app id, channel,
 *              not from the future, not expired, not replayed (--highest-sequence), not a rollback (--installed-version-code)
 *   policy     the versionCode is the one derived from the versionName; a mirror exists; the signed version is not below its floor
 *   each file  every address answers with exactly the bytes the manifest signs: size, every chunk hash, the SHA-256; the zip
 *              is sound (no duplicate entries, no zip bomb); the signing certificate is the one pinned in the manifest (and, with
 *              --installed-apk, the one on the build you have installed); the package and versionCode inside match
 * Redirects are judged hop by hop (https only, no credentials, only the hosts of the manifest's own addresses plus GitHub's
 * asset hosts, at most five hops). Plain http is refused except to a literal loopback address with --allow-loopback-http.
 *
 * Options
 *   --channel NAME                 channel the app follows (default stable)
 *   --installed-version-code N     the versionCode installed (default 0, so any manifest counts as an update)
 *   --installed-apk FILE           an APK of the installed build: its certificate must equal the manifest's pinned one
 *   --highest-sequence N           the largest sequence an app has already accepted (replay check)
 *   --apk-dir DIR                  read the files from DIR (by the last part of each address) instead of downloading them: check before uploading
 *   --allow-redirect-host HOST     another host a redirect may land on (repeatable)
 *   --allow-unchecked-signer       do not fail when apksigner is missing (the certificate is then reported as NOT CHECKED)
 *   --now ISO                      the clock to judge expiry against (tests)
 *   --allow-loopback-http          developer lane and tests only
 * Exit: 0 every check passed (warnings allowed), 1 any failure.
 */
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { basename, join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { apkBadging, apkSigners } from './apk_tools.mjs';
import { download } from './net_lib.mjs';
import {
  GITHUB_ASSET_HOSTS, LIMITS, Refusal, inspectApkZip, parseTime, parseTrust, policyProblems, supportStatus, urlProblem, validatePayload, verifyApkFile, verifyDocument,
} from './manifest_lib.mjs';

function parseArgs(argv) {
  const o = { channel: 'stable', installedVersionCode: 0, extraHosts: [], allowUnchecked: false, allowLoopbackHttp: false };
  const need = (i, a) => { if (i >= argv.length) throw new Error(`${a} needs a value`); return argv[i]; };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--manifest') o.manifest = need(++i, a);
    else if (a === '--pubkeys') o.pubkeys = need(++i, a);
    else if (a === '--channel') o.channel = need(++i, a);
    else if (a === '--installed-version-code') o.installedVersionCode = Number(need(++i, a));
    else if (a === '--installed-apk') o.installedApk = need(++i, a);
    else if (a === '--highest-sequence') o.highestSequence = Number(need(++i, a));
    else if (a === '--apk-dir') o.apkDir = need(++i, a);
    else if (a === '--allow-redirect-host') o.extraHosts.push(need(++i, a).toLowerCase());
    else if (a === '--allow-unchecked-signer') o.allowUnchecked = true;
    else if (a === '--now') { o.now = parseTime(need(++i, a)); if (o.now === null) throw new Error('--now must be a UTC time'); }
    else if (a === '--allow-loopback-http') o.allowLoopbackHttp = true;
    else if (a === '-h' || a === '--help') o.help = true;
    else throw new Error(`unknown argument: ${a}`);
  }
  return o;
}

/**
 * The whole verification. Returns { ok, checks:[{ name, status:'pass'|'fail'|'warn'|'skip', detail }] }.
 * Pure of the console; `env` is where apksigner and aapt2 are looked for.
 */
export async function verifyRelease(o, env = process.env) {
  const checks = [];
  const add = (name, status, detail = '') => { checks.push({ name, status, detail }); return status !== 'fail'; };
  const trust = parseTrust(o.pubkeys || '');
  if (trust.size === 0) { add('public key', 'fail', 'no usable "kid:key" entry in --pubkeys'); return { ok: false, checks }; }

  // ---- the manifest
  let bytes;
  let manifestHosts = [];
  try {
    if (/^https?:\/\//i.test(o.manifest || '')) {
      const why = urlProblem(o.manifest, { allowLoopbackHttp: o.allowLoopbackHttp });
      if (why) { add('manifest address', 'fail', why); return { ok: false, checks }; }
      manifestHosts = [new URL(o.manifest).hostname.toLowerCase()];
      const hosts = hostsFor(manifestHosts, o);
      const r = await download(o.manifest, { maxBytes: LIMITS.manifestBytes, allowLoopbackHttp: o.allowLoopbackHttp, allowedHosts: hosts });
      bytes = r.bytes;
      add('manifest download', 'pass', `${r.length} bytes${r.hops.length ? `, ${r.hops.length} redirect(s) all inside the trusted hosts` : ''}`);
    } else {
      if (!o.manifest || !existsSync(o.manifest)) { add('manifest file', 'fail', 'not found'); return { ok: false, checks }; }
      bytes = readFileSync(o.manifest);
      add('manifest file', 'pass', `${bytes.length} bytes`);
    }
  } catch (e) { add('manifest download', 'fail', e instanceof Refusal ? `${e.code}: ${e.detail}` : e.message); return { ok: false, checks }; }

  const now = o.now ?? Date.now();
  const v = verifyDocument(bytes, {
    trust, channel: o.channel, installedVersionCode: o.installedVersionCode, highestSeenSequence: o.highestSequence, now, allowLoopbackHttp: o.allowLoopbackHttp, strict: false,
  });
  if (!v.ok) { add('manifest accepted by the app', 'fail', `${v.code}${v.detail ? `: ${v.detail}` : ''}`); return { ok: false, checks }; }
  const m = v.manifest;
  add('manifest accepted by the app', 'pass', `signature, shape, app, channel, clock, replay and rollback checks all pass (${v.status})`);

  const strict = validatePayload(m, { strict: true, allowLoopbackHttp: o.allowLoopbackHttp });
  strict.length ? add('manifest is exactly the published format', 'warn', strict.slice(0, 3).join('; ')) : add('manifest is exactly the published format', 'pass');
  const pol = policyProblems(m);
  pol.length ? add('release policy', 'fail', pol.join('; ')) : add('release policy', 'pass', `versionCode ${m.versionCode} is derived from ${m.versionName}`);
  if (m.apks.some((a) => a.urls.length < 2)) add('a mirror is named', 'warn', 'some file has a single address'); else add('a mirror is named', 'pass');
  add('minimum-supported floor', 'pass', supportStatus(m, o.installedVersionCode) === 'below-minimum' ? 'the installed build is below the floor: adults would see "Please update"' : 'the installed build is supported');

  // ---- the installed build's certificate, when given
  let installedCerts = null;
  if (o.installedApk) {
    const s = apkSigners(o.installedApk, env);
    if (s.missing) add('installed build certificate', o.allowUnchecked ? 'warn' : 'fail', 'apksigner not found: NOT CHECKED');
    else if (!s.ok) add('installed build certificate', 'fail', s.detail);
    else installedCerts = s.certs;
  }

  // ---- every file at every address
  const work = mkdtempSync(join(tmpdir(), 'olive-verify-'));
  try {
    for (const apk of m.apks) {
      const label = `${apk.abi}`;
      const allHosts = hostsFor([...manifestHosts, ...apk.urls.map((u) => new URL(u).hostname.toLowerCase())], o);
      let signerChecked = false;
      for (const [k, url] of apk.urls.entries()) {
        const tag = `${label} address ${k + 1}${k === 0 ? ' (primary)' : ' (mirror)'}`;
        const dest = join(work, `${apk.abi}-${k}.apk`);
        try {
          if (o.apkDir) {
            const local = join(o.apkDir, basename(new URL(url).pathname));
            if (!existsSync(local)) { add(`${tag} download`, 'fail', `${basename(local)} is not in --apk-dir`); continue; }
            copyFileSync(local, dest);
          } else {
            const r = await download(url, { maxBytes: apk.size + 1, to: 'file', path: dest, allowLoopbackHttp: o.allowLoopbackHttp, allowedHosts: allHosts, timeoutMs: 120000 });
            add(`${tag} download`, 'pass', `${r.length} bytes${r.hops.length ? `, ${r.hops.length} redirect(s) inside the trusted hosts` : ''}`);
          }
        } catch (e) { add(`${tag} download`, 'fail', e instanceof Refusal ? `${e.code}: ${e.detail}` : e.message); continue; }
        const f = await verifyApkFile(dest, apk);
        if (!add(`${tag} bytes match the signed manifest`, f.ok ? 'pass' : 'fail', f.ok ? f.detail : `${f.code}: ${f.detail}`)) continue;
        if (signerChecked) continue; // identical bytes (same SHA-256): one structural and certificate pass per file is enough
        signerChecked = true;
        const z = await inspectApkZip(dest);
        add(`${label} zip structure`, z.ok ? 'pass' : 'fail', z.ok ? `${z.entries} entries, ${z.uncompressedBytes} bytes uncompressed` : z.problems.join('; '));
        const s = apkSigners(dest, env);
        if (s.missing) add(`${label} signing certificate`, o.allowUnchecked ? 'warn' : 'fail', 'apksigner not found: the certificate is NOT CHECKED');
        else if (!s.ok) add(`${label} signing certificate`, 'fail', s.detail);
        else if (s.certs.length !== 1 || s.certs[0] !== apk.signerSha256) add(`${label} signing certificate`, 'fail', 'the file is signed by a different certificate than the one pinned in the manifest');
        else {
          add(`${label} signing certificate`, 'pass', 'equals the one pinned in the manifest');
          if (installedCerts) add(`${label} same signer as the installed build`, installedCerts.length === 1 && installedCerts[0] === s.certs[0] ? 'pass' : 'fail', installedCerts[0] === s.certs[0] ? 'Android will update in place' : 'a different certificate: Android would refuse the update and the app must too');
        }
        const b = apkBadging(dest, env);
        if (b.ok) add(`${label} package and version inside the file`, b.pkg === m.app && b.versionCode === m.versionCode && b.versionName === m.versionName ? 'pass' : 'fail', `${b.pkg} ${b.versionName} (${b.versionCode})`);
        else add(`${label} package and version inside the file`, 'warn', 'aapt2 not found: NOT CHECKED');
      }
    }
  } finally { rmSync(work, { recursive: true, force: true }); }
  return { ok: !checks.some((c) => c.status === 'fail'), checks };
}

function hostsFor(own, o) {
  const hosts = new Set([...own, ...o.extraHosts]);
  if (hosts.has('github.com')) GITHUB_ASSET_HOSTS.forEach((h) => hosts.add(h));
  if (o.allowLoopbackHttp) { hosts.add('127.0.0.1'); hosts.add('[::1]'); }
  return [...hosts];
}

export async function run(argv, { log = console.log, env = process.env } = {}) {
  let o;
  try { o = parseArgs(argv); } catch (e) { log(`verify-update-release: ${e.message}`); return 1; }
  if (o.help || !o.manifest || !o.pubkeys) {
    log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0].replace(/^\/\*\*\n|^ \* ?/gm, ''));
    return o.help ? 0 : 1;
  }
  const r = await verifyRelease(o, env);
  const mark = { pass: 'PASS', fail: 'FAIL', warn: 'WARN', skip: 'SKIP' };
  for (const c of r.checks) log(`  ${mark[c.status]}  ${c.name}${c.detail ? `  -  ${c.detail}` : ''}`);
  log(`\n${r.ok ? 'VERIFIED' : 'NOT VERIFIED'}: ${r.checks.filter((c) => c.status === 'pass').length} passed, ${r.checks.filter((c) => c.status === 'fail').length} failed, ${r.checks.filter((c) => c.status === 'warn').length} warning(s)`);
  return r.ok ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) run(process.argv.slice(2)).then((c) => { process.exitCode = c; });
