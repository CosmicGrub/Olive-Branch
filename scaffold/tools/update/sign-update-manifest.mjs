#!/usr/bin/env node
/**
 * OLIVE BRANCH - sign an update manifest, locally, with the offline key (docs/RELEASING.md, "Signing an update").
 *
 *   node tools/update/sign-update-manifest.mjs --draft update-manifest.draft.json --key /abs/path/olive-update.key \
 *        --out update-manifest.json [--passphrase-env NAME] [--prev previously-published-update-manifest.json] [--force]
 *
 * Reads the draft that build-update-package.mjs wrote (`{ "manifest": { ... } }`, no signature), checks it against the same
 * rules the app applies (shape, limits, https addresses, the version policy), signs the CANONICAL form of the manifest object
 * with the Ed25519 key, then verifies its own output the way an app would before writing it. It refuses:
 *   - a key file inside any git working tree (the key must live outside every repository);
 *   - a draft that is not valid, is already signed, or whose version does not follow the policy in RELEASING.md;
 *   - a manifest that is not newer than --prev (its `sequence` must rise, its `versionCode` must not fall: no rollback);
 *   - writing over an existing --out unless --force.
 * It never prints the key, never reads the network, and never runs in CI: the workflow in this repository has no secret by design.
 *
 * Exit: 0 signed, 1 refused or failed.
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { loadUpdateKey } from './key_lib.mjs';
import { parseStrictJson, policyProblems, signPayload, validatePayload, verifyDocument, parseTrust, parseTime, LIMITS } from './manifest_lib.mjs';

function parse(argv) {
  const o = { draft: null, key: null, out: null, passphraseEnv: null, prev: null, force: false, allowLoopbackHttp: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--draft') o.draft = argv[++i];
    else if (a === '--key') o.key = argv[++i];
    else if (a === '--out') o.out = argv[++i];
    else if (a === '--passphrase-env') o.passphraseEnv = argv[++i];
    else if (a === '--prev') o.prev = argv[++i];
    else if (a === '--force') o.force = true;
    else if (a === '--allow-loopback-http') o.allowLoopbackHttp = true;
    else if (a === '-h' || a === '--help') o.help = true;
    else throw new Error(`unknown argument: ${a}`);
  }
  return o;
}

const readJson = (path, what) => {
  const r = parseStrictJson(readFileSync(path, 'utf8'));
  if (!r.ok) throw new Error(`${what} is not valid JSON for a manifest: ${r.error}`);
  return r.value;
};

export function run(argv, env = process.env, log = console.log) {
  let o;
  try { o = parse(argv); } catch (e) { log(`sign-update-manifest: ${e.message}`); return 1; }
  if (o.help || !o.draft || !o.key || !o.out) {
    log('usage: node tools/update/sign-update-manifest.mjs --draft <draft.json> --key </abs/path/key> --out <update-manifest.json> [--passphrase-env NAME] [--prev <published.json>] [--force]');
    return o.help ? 0 : 1;
  }
  try {
    if (existsSync(o.out) && !o.force) throw new Error('the --out file already exists (use --force to replace it)');
    const draft = readJson(o.draft, 'the draft');
    if (draft === null || typeof draft !== 'object' || Array.isArray(draft) || Object.keys(draft).join() !== 'manifest') {
      throw new Error('the draft must be exactly { "manifest": { ... } } with no signature (an already signed file is never re-signed)');
    }
    const payload = draft.manifest;
    const problems = [...validatePayload(payload, { strict: true, allowLoopbackHttp: o.allowLoopbackHttp }), ...policyProblems(payload)];
    if (problems.length) throw new Error(`the draft is not publishable:\n  - ${problems.join('\n  - ')}`);
    if (parseTime(payload.expiresAt) < Date.now()) throw new Error('the draft has already expired (expiresAt is in the past)');

    let passphrase = null;
    if (o.passphraseEnv) { passphrase = env[o.passphraseEnv]; if (!passphrase) throw new Error(`environment variable ${o.passphraseEnv} is empty`); }
    const key = loadUpdateKey(o.key, passphrase);

    if (o.prev) {
      const prev = readJson(o.prev, '--prev');
      const pm = prev && prev.manifest;
      if (!pm || !Number.isSafeInteger(pm.sequence) || !Number.isSafeInteger(pm.versionCode)) throw new Error('--prev is not a signed manifest');
      if (payload.sequence <= pm.sequence) throw new Error(`sequence ${payload.sequence} is not above the previous manifest's ${pm.sequence}; a re-issue needs a higher sequence`);
      if (payload.versionCode < pm.versionCode) throw new Error(`versionCode ${payload.versionCode} is below the previous manifest's ${pm.versionCode}: that would be a rollback`);
      if (payload.channel !== pm.channel) throw new Error('the channel differs from --prev; a manifest never changes channel');
    }

    const doc = signPayload(payload, key.privateKey, key.kid);
    const text = `${JSON.stringify(doc, null, 2)}\n`;
    const check = verifyDocument(text, {
      trust: parseTrust(key.trust), channel: payload.channel, installedVersionCode: 1, allowLoopbackHttp: o.allowLoopbackHttp,
      now: Math.max(Date.now(), parseTime(payload.issuedAt)),
    });
    if (!check.ok) throw new Error(`the signed output failed its own check (${check.code}: ${check.detail}); nothing was written`);
    if (Buffer.byteLength(text) > LIMITS.manifestBytes) throw new Error(`the signed manifest is larger than the ${LIMITS.manifestBytes}-byte cap the app enforces`);
    writeFileSync(o.out, text, { flag: o.force ? 'w' : 'wx' });
    log(`Signed ${payload.versionName} (versionCode ${payload.versionCode}, sequence ${payload.sequence}, channel ${payload.channel}).`);
    log(`  key id   ${key.kid}`);
    log(`  written  ${o.out}`);
    log('Upload this file with the APKs. Then run tools/update/verify-update-release.mjs against the published address.');
    return 0;
  } catch (e) {
    log(`sign-update-manifest: REFUSED. ${e.message}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = run(process.argv.slice(2));
