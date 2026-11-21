#!/usr/bin/env node
/**
 * OLIVE BRANCH - validate an update manifest file (draft or signed) against the published format, offline.
 *
 *   node tools/update/validate-manifest.mjs <file> [--pubkeys <kid:key,...>] [--channel NAME] [--installed-version-code N] [--allow-loopback-http]
 *
 * A DRAFT (`{ "manifest": { ... } }`) is checked for shape, limits, https addresses and the publishing policy (the versionCode is the
 * one derived from the versionName). A SIGNED file (`{ manifest, signature }`) is checked the same way, and with --pubkeys the
 * Ed25519 signature is verified under that public key exactly as an app would (then channel, clock, replay and rollback too).
 * The rules are docs/UPDATE-MANIFEST.md, written as JSON Schema in docs/update-manifest.schema.json. No network, no private key.
 * Exit: 0 valid, 1 not valid (every problem is printed).
 */
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { LIMITS, parseStrictJson, parseTrust, policyProblems, validateDocument, validatePayload, verifyDocument } from './manifest_lib.mjs';

export function run(argv, log = console.log) {
  const o = { file: null, pubkeys: null, channel: 'stable', installed: 0, loopback: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--pubkeys') o.pubkeys = argv[++i];
    else if (a === '--channel') o.channel = argv[++i];
    else if (a === '--installed-version-code') o.installed = Number(argv[++i]);
    else if (a === '--allow-loopback-http') o.loopback = true;
    else if (!a.startsWith('-') && !o.file) o.file = a;
    else { log(`validate-manifest: unknown argument ${a}`); return 1; }
  }
  if (!o.file) { log('usage: node tools/update/validate-manifest.mjs <file> [--pubkeys kid:key] [--channel NAME] [--installed-version-code N]'); return 1; }
  let bytes;
  try { bytes = readFileSync(o.file); } catch { log('validate-manifest: cannot read that file'); return 1; }
  if (bytes.length > LIMITS.manifestBytes) { log(`NOT VALID: larger than ${LIMITS.manifestBytes} bytes`); return 1; }
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); } catch { log('NOT VALID: not valid UTF-8'); return 1; }
  const parsed = parseStrictJson(text);
  if (!parsed.ok) { log(`NOT VALID: ${parsed.error}`); return 1; }
  const doc = parsed.value;
  const signed = doc && typeof doc === 'object' && 'signature' in doc;
  const problems = signed ? validateDocument(doc, { allowLoopbackHttp: o.loopback }) : validatePayload(doc && doc.manifest, { allowLoopbackHttp: o.loopback });
  if (!signed && !(doc && typeof doc === 'object' && Object.keys(doc).join() === 'manifest')) problems.unshift('(document): a draft is exactly { "manifest": { ... } }');
  if (doc && doc.manifest && typeof doc.manifest === 'object') problems.push(...policyProblems(doc.manifest));
  if (problems.length) { problems.forEach((p) => log(`  - ${p}`)); log(`NOT VALID: ${problems.length} problem(s)`); return 1; }
  if (signed && o.pubkeys) {
    const trust = parseTrust(o.pubkeys);
    const v = verifyDocument(bytes, { trust, channel: o.channel, installedVersionCode: o.installed, allowLoopbackHttp: o.loopback, strict: true });
    if (!v.ok) { log(`NOT VALID: the app would refuse this (${v.code}${v.detail ? `: ${v.detail}` : ''})`); return 1; }
    log(`VALID and SIGNED: the app would accept it (${v.status})`);
    return 0;
  }
  log(signed ? 'VALID in shape (signature not checked: pass --pubkeys)' : 'VALID draft (not signed)');
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = run(process.argv.slice(2));
