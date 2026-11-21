/**
 * Shared helpers for the update-pipeline tests: a minimal APK-shaped zip, throwaway keys, a good manifest payload, local
 * loopback servers that misbehave on purpose, and a stand-in apksigner. Nothing here touches the network beyond 127.0.0.1.
 */
import { createHash, generateKeyPairSync } from 'node:crypto';
import http from 'node:http';
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as L from '../update/manifest_lib.mjs';

export const hx = (c) => c.repeat(64);
export const clone = (o) => JSON.parse(JSON.stringify(o));

export function keypair() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const raw = L.rawPublicKey(publicKey);
  const kid = L.kidOf(raw);
  const trust = L.trustEntry(kid, raw);
  return { privateKey, kid, trust, map: L.parseTrust(trust) };
}

/** A zip with a central directory, enough for inspectApkZip. Entry: { name, data?, comp?, unc? } (comp/unc lie about sizes). */
export function zip(entries) {
  const locals = [], centrals = [];
  let off = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name);
    const body = e.data ?? Buffer.alloc(0);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt32LE(body.length, 18); lh.writeUInt32LE(body.length, 22); lh.writeUInt16LE(name.length, 26);
    locals.push(lh, name, body);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0); cd.writeUInt16LE(20, 4); cd.writeUInt16LE(20, 6);
    cd.writeUInt32LE(e.comp ?? body.length, 20); cd.writeUInt32LE(e.unc ?? body.length, 24); cd.writeUInt16LE(name.length, 28); cd.writeUInt32LE(off, 42);
    centrals.push(cd, name);
    off += 30 + name.length + body.length;
  }
  const cdBuf = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(cdBuf.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...locals, cdBuf, end]);
}

/** Deterministic pseudo-random bytes (so chunk hashes differ from each other). */
export function noise(n, seed = 'x') {
  const out = Buffer.alloc(n);
  for (let o = 0; o < n; o += 32) createHash('sha256').update(`${seed}:${o}`).digest().copy(out, o, 0, Math.min(32, n - o));
  return out;
}

/** An APK-shaped zip of roughly [bytes] bytes. */
export function fakeApk(bytes = 300 * 1024, seed = 'apk') {
  return zip([
    { name: 'AndroidManifest.xml', data: Buffer.from('manifest') },
    { name: 'classes.dex', data: Buffer.from('dex') },
    { name: 'assets/blob.bin', data: noise(Math.max(0, bytes - 400), seed) },
  ]);
}

/** The apks[] entry that describes [bytes] served at [urls]. */
export async function apkEntry(path, urls, { abi = 'arm64-v8a', signer = hx('b'), chunkSize = 65536 } = {}) {
  const h = await L.hashFile(path, chunkSize);
  return { abi, size: h.size, sha256: h.sha256, signerSha256: signer, chunkSize, chunks: h.chunks, urls };
}

export const NOW = Date.UTC(2026, 11, 1);
export const ISSUED = Date.UTC(2026, 10, 21, 10);

export function payload(apks, extra = {}) {
  return {
    schema: 1, app: L.APP_ID, channel: 'stable', versionName: '0.52.0', versionCode: 5200, minSupportedVersionCode: 5100, sequence: 1000,
    issuedAt: L.formatTime(ISSUED), expiresAt: L.formatTime(ISSUED + 180 * 86400000), publishedAt: L.formatTime(ISSUED),
    headline: 'A calmer first run', notes: ['One line.'], apks, ...extra,
  };
}

/** Starts a loopback http server; handler(req,res). Returns { port, url(path), close() }. */
export async function serve(handler) {
  const server = http.createServer(handler);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  return { port, url: (p) => `http://127.0.0.1:${port}${p}`, close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }) };
}

/** A stand-in apksigner that always reports the given certificate digest (a .cmd on Windows, a shell script elsewhere). Returns its path. */
export function fakeApksigner(dir, certHex, { fail = false } = {}) {
  mkdirSync(dir, { recursive: true });
  if (process.platform === 'win32') {
    const p = join(dir, 'apksigner.cmd');
    writeFileSync(p, fail ? '@echo off\r\necho DOES NOT VERIFY 1>&2\r\nexit /b 1\r\n' : `@echo off\r\necho Signer #1 certificate DN: CN=test\r\necho Signer #1 certificate SHA-256 digest: ${certHex}\r\n`);
    return p;
  }
  const p = join(dir, 'apksigner');
  writeFileSync(p, fail ? '#!/bin/sh\necho "DOES NOT VERIFY" >&2\nexit 1\n' : `#!/bin/sh\necho "Signer #1 certificate DN: CN=test"\necho "Signer #1 certificate SHA-256 digest: ${certHex}"\n`);
  chmodSync(p, 0o755);
  return p;
}
