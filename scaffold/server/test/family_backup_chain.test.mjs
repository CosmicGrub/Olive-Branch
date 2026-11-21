/**
 * Encrypted family backup: the pure integrity layer (server/backup_chain.mjs), no database.
 * This is the check a PHONE runs on what the server lists. The server cannot be trusted to hand back
 * the history it was given, so every way a server (or a relay in front of it) could tamper must be seen:
 * an edited version, a swapped order, a hidden version, an old head served as new, another family's
 * history, a replayed restore proof. Prints "N passed, M failed" for verify.sh.
 */
import { generateKeyPairSync, sign, randomBytes, createHash } from 'node:crypto';
import { randomUUID } from 'node:crypto';
import {
  GENESIS_CHAIN, chainHash, sha256, hex32, b64, uuidBytes, verifyHistory,
  restoreChallengeMessage, ed25519Verify, newToken, tokenDigest,
} from '../backup_chain.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const rawPub = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
const otherKey = generateKeyPairSync('ed25519');
const vaultId = randomUUID();

/** Build n honest versions exactly as a phone would. Returns the list in the shape the server returns. */
function build(n, { vault = vaultId, key = privateKey } = {}) {
  const out = []; let prev = GENESIS_CHAIN;
  for (let i = 1; i <= n; i++) {
    const blob = randomBytes(200 + i);
    const manifest = randomBytes(40);
    const blobSha256 = sha256(blob);
    const chain = chainHash({ vaultId: vault, seq: i, prevChain: prev, blobSha256, size: blob.length, manifest });
    out.push({
      seq: i, prevChainHash: prev.toString('hex'), chainHash: chain.toString('hex'),
      blobSha256: blobSha256.toString('hex'), sizeBytes: blob.length,
      manifest: manifest.toString('base64'), signature: sign(null, chain, key).toString('base64') });
    prev = chain;
  }
  return out;
}
const verifySig = (chain, sig) => ed25519Verify(rawPub, chain, sig);
const run = (versions, extra = {}) => verifyHistory({ vaultId, versions, verifySignature: verifySig, ...extra });
const clone = (v) => JSON.parse(JSON.stringify(v));

// ---- an honest history passes ---------------------------------------------------------------------------
const good = build(5);
check('honest', 'an untouched five-version history verifies', run(good).ok, true);
check('honest', '...and reports its head', `${run(good).headSeq}`, '5');
check('honest', 'an empty history is fine at the start', run([]).ok, true);
check('honest', 'a window that starts later verifies when given the link it follows', run(good.slice(2), { startPrev: Buffer.from(good[1].chainHash, 'hex') }).ok, true);
check('honest', 'the phone\'s remembered newest version, seen again, is accepted', run(good, { highWater: { seq: 5, chainHash: good[4].chainHash } }).ok, true);
check('honest', 'a longer history than remembered is accepted', run(good, { highWater: { seq: 3, chainHash: good[2].chainHash } }).ok, true);
check('honest', 'the chain value is deterministic', chainHash({ vaultId, seq: 1, prevChain: GENESIS_CHAIN, blobSha256: sha256(Buffer.from('x')), size: 1, manifest: Buffer.from('m') }).toString('hex'),
  chainHash({ vaultId, seq: 1, prevChain: GENESIS_CHAIN, blobSha256: sha256(Buffer.from('x')), size: 1, manifest: Buffer.from('m') }).toString('hex'));

// ---- a dishonest server is caught ---------------------------------------------------------------------------
{
  const v = clone(good); v[2].manifest = randomBytes(40).toString('base64');
  check('tamper', 'an edited manifest is caught (chain value no longer matches)', run(v).reason, 'chain_value_wrong');
}
{
  const v = clone(good); v[2].blobSha256 = sha256(Buffer.from('other')).toString('hex');
  check('tamper', 'a swapped ciphertext hash is caught', run(v).reason, 'chain_value_wrong');
}
{
  const v = clone(good); v[2].sizeBytes += 1;
  check('tamper', 'a changed size is caught', run(v).reason, 'chain_value_wrong');
}
{
  const v = clone(good); [v[1], v[2]] = [v[2], v[1]];
  check('tamper', 'two versions swapped are caught', run(v).ok, false);
}
{
  const v = clone(good); v.splice(2, 1);
  check('tamper', 'a version hidden from the middle is a gap', run(v).reason, 'gap');
}
{
  const v = clone(good).slice(0, 3);
  check('tamper', 'the newest versions hidden (an old head served as new) is a rollback against what the phone has seen',
    run(v, { highWater: { seq: 5, chainHash: good[4].chainHash } }).reason, 'rollback');
}
{
  const v = clone(good); v[3].prevChainHash = v[1].chainHash;
  check('tamper', 'a rewired link is caught', run(v).ok, false);
}
{
  const forged = build(5);
  check('tamper', 'a different history under the same numbers is caught against the phone\'s memory (high water changed)',
    run(forged, { highWater: { seq: 5, chainHash: good[4].chainHash } }).reason, 'high_water_changed');
}
{
  const other = build(5, { key: otherKey.privateKey });
  check('tamper', 'versions signed by a key that is not the family\'s fail the signature check', run(other).reason, 'bad_signature');
}
{
  const v = clone(good); v[1].signature = Buffer.alloc(64, 7).toString('base64');
  check('tamper', 'a garbage signature is caught', run(v).reason, 'bad_signature');
}
{
  const elsewhere = build(3, { vault: randomUUID() });
  check('tamper', 'another family\'s history (a different vault id) does not verify as ours', run(elsewhere).reason, 'chain_value_wrong');
}
{
  const v = clone(good); v[0].prevChainHash = sha256(Buffer.from('not genesis')).toString('hex');
  check('tamper', 'a first version that does not start from the genesis link is caught', run(v).reason, 'chain_broken');
}

// ---- the restore proof binds everything ----------------------------------------------------------------------
{
  const u = randomUUID(), d = randomUUID(), nonce = randomBytes(32);
  const msg = restoreChallengeMessage({ vaultId, userId: u, deviceId: d, nonce });
  const sig = sign(null, msg, privateKey);
  check('proof', 'a restore proof by the family key verifies', ed25519Verify(rawPub, msg, sig), true);
  const variants = [
    ['another vault', { vaultId: randomUUID(), userId: u, deviceId: d, nonce }],
    ['another person', { vaultId, userId: randomUUID(), deviceId: d, nonce }],
    ['another phone', { vaultId, userId: u, deviceId: randomUUID(), nonce }],
    ['another nonce', { vaultId, userId: u, deviceId: d, nonce: randomBytes(32) }],
  ];
  for (const [name, args] of variants) {
    check('proof', `the same signature cannot be replayed for ${name}`, ed25519Verify(rawPub, restoreChallengeMessage(args), sig), false);
  }
  check('proof', 'a chain signature is not a valid restore proof (domains differ)', ed25519Verify(rawPub, msg, sign(null, Buffer.from(good[0].chainHash, 'hex'), privateKey)), false);
  check('proof', 'a malformed key never throws, it just fails', ed25519Verify(Buffer.alloc(5), msg, sig), false);
  check('proof', 'a malformed signature never throws, it just fails', ed25519Verify(rawPub, msg, Buffer.alloc(63)), false);
  check('proof', 'a non-buffer signature never throws', ed25519Verify(rawPub, msg, 'nope'), false);
}

// ---- strict parsing ---------------------------------------------------------------------------------------------
check('parse', 'hex32 accepts exactly 64 lowercase hex', Boolean(hex32('a'.repeat(64))), true);
check('parse', 'hex32 refuses uppercase', hex32('A'.repeat(64)), null);
check('parse', 'hex32 refuses 63 characters', hex32('a'.repeat(63)), null);
check('parse', 'hex32 refuses a non-string', hex32(12), null);
check('parse', 'b64 accepts canonical base64 in the window', Boolean(b64(Buffer.alloc(40, 1).toString('base64'), 1, 64)), true);
check('parse', 'b64 refuses whitespace', b64('AAAA AAAA', 1, 64), null);
check('parse', 'b64 refuses non-canonical padding', b64('AAB=', 1, 64), null);
check('parse', 'b64 refuses a value over the window', b64(Buffer.alloc(65).toString('base64'), 1, 64), null);
check('parse', 'b64 refuses the empty string', b64('', 0, 64), null);
check('parse', 'uuidBytes refuses a non-uuid', (() => { try { uuidBytes('nope'); return 'accepted'; } catch { return 'refused'; } })(), 'refused');
check('parse', 'a one-time token is 256 bits and only its digest is kept', (() => {
  const t = newToken(); return t.token.length >= 43 && t.digest === tokenDigest(t.token) && /^[0-9a-f]{64}$/.test(t.digest); })(), true);
check('parse', 'two tokens never repeat', newToken().token === newToken().token, false);
check('parse', 'the digest is plain SHA-256', tokenDigest('abc'), createHash('sha256').update('abc').digest('hex'));

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
