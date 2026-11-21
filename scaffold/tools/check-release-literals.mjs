#!/usr/bin/env node
/**
 * OLIVE BRANCH - the built release must contain none of the invented demo content (ISS-092).
 *
 * Invented medicines, an invented emergency card and a fixed demo PIN exist for the offline preview and for tests
 * (client/lib/demo_fixtures.dart). They sit behind a compile-time debug switch, so a release build should not carry
 * them. "Should not" is not a check: this reads the BUILT artifact and fails if any literal listed in
 * tools/demo-literals.json is in it.
 *
 * It reads what is really inside the thing a family would install:
 *   - an .apk / .aab / .zip / .jar: every entry is opened (stored or deflated) and searched, native libraries included.
 *     libapp.so, the compiled Dart, is where an invented string would be.
 *   - a directory: every file under it (a `flutter build` output folder, or an unpacked apk).
 *   - any other file: searched as it is.
 * Each literal is looked for as UTF-8, as UTF-16LE and as Latin-1 (Dart keeps ASCII strings one byte wide, UTF-16 strings
 * two), so a string cannot hide by being stored the other way.
 *
 * Exit 0 clean, 1 a demo literal was found (each hit prints the literal and the entry), 2 could not run. It fails CLOSED:
 * an unreadable artifact, an empty literal list, or an apk with no entries is exit 2, never "clean".
 *
 * usage: node tools/check-release-literals.mjs <apk|aab|dir|file> [more ...] [--literals file.json]
 */
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';

const HERE = dirname(fileURLToPath(import.meta.url));

/** The literals, from the shared list. Throws on an unreadable or empty list (fail closed). */
export function loadLiterals(path = join(HERE, 'demo-literals.json')) {
  const j = JSON.parse(readFileSync(path, 'utf8'));
  const list = Array.isArray(j) ? j : j.literals;
  if (!Array.isArray(list) || list.length === 0 || list.some((x) => typeof x !== 'string' || x.length < 4)) {
    throw new Error(`${path}: needs a non-empty list of strings of at least 4 characters`);
  }
  return list;
}

/** Every entry of a zip (apk/aab/jar) as {name, data}. Stored and deflated entries; anything else throws. */
export function zipEntries(buf) {
  // End Of Central Directory record: signature 0x06054b50, within the last 64 KiB + 22 bytes.
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('not a zip (no end-of-central-directory record)');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = [];
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('corrupt central directory');
    const method = buf.readUInt16LE(p + 10);
    const csize = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28), extraLen = buf.readUInt16LE(p + 30), commentLen = buf.readUInt16LE(p + 32);
    const localOff = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    p += 46 + nameLen + extraLen + commentLen;
    if (name.endsWith('/')) continue;
    if (buf.readUInt32LE(localOff) !== 0x04034b50) throw new Error(`corrupt local header for ${name}`);
    const dataStart = localOff + 30 + buf.readUInt16LE(localOff + 26) + buf.readUInt16LE(localOff + 28);
    const raw = buf.subarray(dataStart, dataStart + csize);
    if (method === 0) out.push({ name, data: raw });
    else if (method === 8) out.push({ name, data: inflateRawSync(raw) });
    else throw new Error(`${name}: unsupported compression method ${method}`);
  }
  return out;
}

const forms = (lit) => [Buffer.from(lit, 'utf8'), Buffer.from(lit, 'utf16le'), Buffer.from(lit, 'latin1')];

/** Literals found in one buffer. */
export function findLiterals(data, literals) {
  const hits = [];
  for (const lit of literals) {
    if (forms(lit).some((f) => data.includes(f))) hits.push(lit);
  }
  return hits;
}

function* walk(dir) {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) yield* walk(p); else yield p;
  }
}

/** Scans one target. Returns {scanned, hits:[{literal, entry}]}. Throws if nothing could be scanned. */
export function scanTarget(target, literals) {
  if (!existsSync(target)) throw new Error(`${target}: no such file or directory`);
  const hits = [];
  let scanned = 0;
  const scanBuf = (entry, data) => { scanned++; for (const literal of findLiterals(data, literals)) hits.push({ literal, entry }); };
  if (statSync(target).isDirectory()) {
    for (const f of walk(target)) {
      if (/\.(apk|aab|zip|jar)$/i.test(f)) {
        for (const e of zipEntries(readFileSync(f))) scanBuf(`${f}!${e.name}`, e.data);
      } else scanBuf(f, readFileSync(f));
    }
  } else if (/\.(apk|aab|zip|jar)$/i.test(target)) {
    for (const e of zipEntries(readFileSync(target))) scanBuf(e.name, e.data);
  } else scanBuf(target, readFileSync(target));
  if (scanned === 0) throw new Error(`${target}: nothing to scan (an empty artifact is not a clean one)`);
  return { scanned, hits };
}

function main() {
  const args = process.argv.slice(2);
  let lf; const targets = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--literals') lf = args[++i]; else targets.push(args[i]);
  }
  if (targets.length === 0) { console.error('usage: check-release-literals.mjs <apk|aab|dir|file> [...] [--literals file.json]'); process.exit(2); }
  let literals;
  try { literals = loadLiterals(lf); } catch (e) { console.error(`  FAIL  cannot read the literal list: ${e.message}`); process.exit(2); }
  let bad = 0;
  for (const t of targets) {
    let r;
    try { r = scanTarget(t, literals); } catch (e) { console.error(`  FAIL  ${e.message}`); process.exit(2); }
    if (r.hits.length === 0) console.log(`  PASS  ${t}: ${r.scanned} file(s) searched for ${literals.length} demo literal(s), none found`);
    else {
      bad++;
      for (const h of r.hits) console.log(`  FAIL  ${t}: demo literal "${h.literal}" is in ${h.entry}`);
    }
  }
  process.exit(bad === 0 ? 0 : 1);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) main();
