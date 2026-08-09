/**
 * packages/auth — attestation.ts: the CBOR/COSE registration parser.
 * WebAuthn Level 2 §6.5.1, RFC 8152 §13.1.1 / RFC 9053, RFC 8949.
 *
 * The real proof this parser is correct is NOT "it doesn't throw" — it is a
 * full round trip through auth.ts's own, independently-unit-tested
 * verifyAssertion(): generate a real EC P-256 key pair, hand-encode a
 * synthetic COSE_Key CBOR buffer for its public key with a SEPARATE, local
 * encoder (not attestation.ts's own machinery — an encoder built from the
 * decoder under test would only prove the two agree with each other, not
 * that either is right), run it through parseAttestationObject() +
 * extractCredentialPublicKey(), then sign a real WebAuthn-shaped assertion
 * with the matching PRIVATE key and confirm auth.ts's verifyAssertion()
 * returns ok:true against the PEM this file produced. See section A.
 */
import { createHash, createSign, generateKeyPairSync } from 'node:crypto';
import { parseAttestationObject, extractCredentialPublicKey } from '../src/attestation.mjs';
import { verifyAssertion } from '../src/auth.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const throws = (fn) => { try { fn(); return false; } catch { return true; } };

// ============================================================================
// A tiny, STANDALONE CBOR encoder — deliberately separate code from
// attestation.ts's decoder, built only for this test file, only for the
// small shapes a COSE_Key/attestationObject actually need (unsigned/negative
// small integers, byte strings up to 255 bytes, text strings, maps).
// ============================================================================
function cborUint(n) {
  if (n < 24) return Buffer.from([n]);
  if (n < 256) return Buffer.from([24, n]);
  throw new Error('test encoder: uint too large for this harness');
}
function cborNegint(n) { // encodes CBOR value -n for n >= 1
  const arg = n - 1;
  if (arg < 24) return Buffer.from([0x20 | arg]);
  if (arg < 256) return Buffer.from([0x38, arg]);
  throw new Error('test encoder: negint too large for this harness');
}
function cborBytes(buf) {
  if (buf.length < 24) return Buffer.concat([Buffer.from([0x40 | buf.length]), buf]);
  if (buf.length < 256) return Buffer.concat([Buffer.from([0x58, buf.length]), buf]);
  return Buffer.concat([Buffer.from([0x59, buf.length >> 8, buf.length & 0xff]), buf]);
}
function cborText(s) {
  const buf = Buffer.from(s, 'utf8');
  if (buf.length < 24) return Buffer.concat([Buffer.from([0x60 | buf.length]), buf]);
  return Buffer.concat([Buffer.from([0x78, buf.length]), buf]);
}
function cborMapHeader(pairCount) {
  if (pairCount < 24) return Buffer.from([0xa0 | pairCount]);
  throw new Error('test encoder: map too large for this harness');
}

/** Encodes a synthetic COSE_Key EC2 map: {1:2, 3:-7, -1:1, -2:x, -3:y}. */
function encodeCoseKeyEc2(x, y, { alg = -7, crv = 1, kty = 2 } = {}) {
  const parts = [cborMapHeader(5)];
  parts.push(cborUint(1), kty >= 0 ? cborUint(kty) : cborNegint(-kty));
  parts.push(cborUint(3), alg >= 0 ? cborUint(alg) : cborNegint(-alg));
  parts.push(cborNegint(1), crv >= 0 ? cborUint(crv) : cborNegint(-crv)); // key -1
  parts.push(cborNegint(2), cborBytes(x)); // key -2
  parts.push(cborNegint(3), cborBytes(y)); // key -3
  return Buffer.concat(parts);
}

/** Builds a registration-shaped authData: rpIdHash|flags|signCount|aaguid|
 * credIdLen|credentialId|COSE_Key. */
function buildAuthData(credentialId, coseKeyBuf, { rpIdHash, flags = 0x41, signCount = 0 } = {}) {
  const rpHash = rpIdHash ?? Buffer.alloc(32, 0xab);
  const flagsBuf = Buffer.from([flags]);
  const signCountBuf = Buffer.alloc(4); signCountBuf.writeUInt32BE(signCount);
  const aaguid = Buffer.alloc(16, 0);
  const credIdLen = Buffer.alloc(2); credIdLen.writeUInt16BE(credentialId.length);
  return Buffer.concat([rpHash, flagsBuf, signCountBuf, aaguid, credIdLen, credentialId, coseKeyBuf]);
}

function buildAttestationObject(fmt, authData) {
  const parts = [cborMapHeader(3)];
  parts.push(cborText('fmt'), cborText(fmt));
  parts.push(cborText('attStmt'), cborMapHeader(0));
  parts.push(cborText('authData'), cborBytes(authData));
  return Buffer.concat(parts);
}

// ============================================================================
// A · full round trip through auth.ts's own verifyAssertion() — the real proof
// ============================================================================
{
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const jwk = publicKey.export({ format: 'jwk' });
  const x = Buffer.from(jwk.x, 'base64url');
  const y = Buffer.from(jwk.y, 'base64url');
  check('A round-trip', 'generated key JWK has 32-byte x', x.length, 32);
  check('A round-trip', 'generated key JWK has 32-byte y', y.length, 32);

  const credentialIdBuf = Buffer.from('abcd1234ef567890', 'hex');
  const coseKeyBuf = encodeCoseKeyEc2(x, y);
  const rpId = 'olivebranch.local';
  const rpIdHash = createHash('sha256').update(rpId, 'utf8').digest();
  const authData = buildAuthData(credentialIdBuf, coseKeyBuf, { rpIdHash });
  const attestationObjectB64u = buildAttestationObject('none', authData).toString('base64url');

  const { fmt, authData: parsedAuthData } = parseAttestationObject(attestationObjectB64u);
  check('A round-trip', 'fmt round-trips', fmt, 'none');
  check('A round-trip', 'authData length round-trips', parsedAuthData.length, authData.length);

  const { credentialId, publicKeyPem } = extractCredentialPublicKey(parsedAuthData);
  check('A round-trip', 'credentialId round-trips as base64url',
    credentialId, credentialIdBuf.toString('base64url'));
  check('A round-trip', 'publicKeyPem looks like a real SPKI PEM',
    publicKeyPem.startsWith('-----BEGIN PUBLIC KEY-----'), 'true');

  // Now prove the PEM is genuinely usable by auth.ts's OWN verifyAssertion —
  // sign a real WebAuthn-shaped LOGIN assertion with the matching private key.
  const challenge = 'c2FtcGxlLWNoYWxsZW5nZS12YWx1ZQ'; // arbitrary base64url text
  const clientData = { type: 'webauthn.get', challenge, origin: 'https://olivebranch.local' };
  const clientDataJSONBuf = Buffer.from(JSON.stringify(clientData), 'utf8');
  const clientDataJSON = clientDataJSONBuf.toString('base64url');

  // A LOGIN authData: same rpIdHash, but the AT flag is not required (only
  // UP, bit 0x01) and signCount must exceed the stored value (0) to pass
  // auth.ts's own replay guard.
  const loginFlags = Buffer.from([0x01]);
  const loginSignCount = Buffer.alloc(4); loginSignCount.writeUInt32BE(1);
  const loginAuthData = Buffer.concat([rpIdHash, loginFlags, loginSignCount]);
  const authenticatorData = loginAuthData.toString('base64url');

  const clientHash = createHash('sha256').update(clientDataJSONBuf).digest();
  const signedPayload = Buffer.concat([loginAuthData, clientHash]);
  const signature = createSign('sha256').update(signedPayload).sign(privateKey).toString('base64url');

  const credential = { credentialId, publicKeyPem, signCount: 0, userId: 'test-guardian' };
  const result = verifyAssertion({
    assertion: { credentialId, clientDataJSON, authenticatorData, signature },
    credential,
    expectedChallenge: challenge,
    expectedOrigin: 'https://olivebranch.local',
    expectedRpIdHash: rpIdHash,
    challengeIssuedAt: Date.now() - 1000,
    now: Date.now(),
  });
  check('A round-trip', 'auth.ts verifyAssertion() accepts the extracted PEM end-to-end',
    result.ok, 'true');
  check('A round-trip', 'and reports the new sign count', result.ok ? result.newSignCount : null, 1);

  // A tampered signature must still fail — proves this is a REAL signature
  // check, not one that always returns ok:true.
  const tamperedSig = Buffer.from(signature, 'base64url'); tamperedSig[0] ^= 0xff;
  const badResult = verifyAssertion({
    assertion: { credentialId, clientDataJSON, authenticatorData,
                 signature: tamperedSig.toString('base64url') },
    credential,
    expectedChallenge: challenge,
    expectedOrigin: 'https://olivebranch.local',
    expectedRpIdHash: rpIdHash,
    challengeIssuedAt: Date.now() - 1000,
    now: Date.now(),
  });
  check('A round-trip', 'a tampered signature is rejected, not silently accepted',
    badResult.ok, 'false');
  check('A round-trip', 'and names the real reason', badResult.ok ? '' : badResult.reason, 'bad_signature');
}

// ============================================================================
// B · malformed CBOR is REJECTED, not crashed — real inputs, real try/catch
// ============================================================================
{
  check('B malformed', 'empty attestationObject throws a catchable Error',
    throws(() => parseAttestationObject('')), 'true');
  check('B malformed', 'not-base64url throws a catchable Error',
    throws(() => parseAttestationObject('!!!not base64url!!!')), 'true');
  check('B malformed', 'random garbage bytes throw a catchable Error, not a crash',
    throws(() => parseAttestationObject(Buffer.from([0xff, 0xff, 0xff, 0xff]).toString('base64url'))),
    'true');
  // A truncated map: says "3 pairs follow" (map header for 3 pairs) but the
  // buffer ends immediately after.
  const truncatedMap = Buffer.from([0xa3]);
  check('B malformed', 'a map header with no following pairs throws, not crashes',
    throws(() => parseAttestationObject(truncatedMap.toString('base64url'))), 'true');
  // A byte string claiming a length longer than the remaining buffer.
  const truncatedBytes = Buffer.concat([cborMapHeader(1), cborText('fmt'), Buffer.from([0x58, 0xff])]);
  check('B malformed', 'a byte string with an out-of-bounds length throws, not crashes',
    throws(() => parseAttestationObject(truncatedBytes.toString('base64url'))), 'true');
  // A valid-looking map missing the required authData key.
  const missingAuthData = Buffer.concat([
    cborMapHeader(2), cborText('fmt'), cborText('none'), cborText('attStmt'), cborMapHeader(0),
  ]);
  check('B malformed', 'a well-formed CBOR map missing authData is rejected',
    throws(() => parseAttestationObject(missingAuthData.toString('base64url'))), 'true');
  // An indefinite-length item (additionalInfo=31) — explicitly unsupported.
  const indefinite = Buffer.from([0xbf]); // map, indefinite length
  check('B malformed', 'an indefinite-length CBOR item is rejected, not mis-parsed',
    throws(() => parseAttestationObject(indefinite.toString('base64url'))), 'true');
  // extractCredentialPublicKey on garbage/short authData.
  check('B malformed', 'a too-short authData throws rather than reading out of bounds',
    throws(() => extractCredentialPublicKey(Buffer.alloc(10))), 'true');
  check('B malformed', 'a login-shaped authData (no AT flag) is rejected for registration',
    throws(() => extractCredentialPublicKey(Buffer.concat([Buffer.alloc(32), Buffer.from([0x01]), Buffer.alloc(4)]))),
    'true');
}

// ============================================================================
// C · a COSE_Key with the wrong curve/alg/kty is rejected, not silently stored
// ============================================================================
{
  const { publicKey: p384Pub } = generateKeyPairSync('ec', { namedCurve: 'P-384' });
  const jwk384 = p384Pub.export({ format: 'jwk' });
  const x384 = Buffer.from(jwk384.x, 'base64url');
  const y384 = Buffer.from(jwk384.y, 'base64url');

  // Wrong curve, correctly-sized-for-P384 coordinates (48 bytes) — must be
  // refused outright since this parser only ever claims P-256, whatever the
  // claimed crv value says.
  const wrongCrvKey = encodeCoseKeyEc2(x384, y384, { crv: 2 }); // crv=2 would be P-384 if it existed in our subset
  const authDataWrongCrv = buildAuthData(Buffer.from('id1'), wrongCrvKey);
  check('C wrong curve', 'a non-P-256 crv is rejected',
    throws(() => extractCredentialPublicKey(authDataWrongCrv)), 'true');

  const { publicKey: p256Pub } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const jwk256 = p256Pub.export({ format: 'jwk' });
  const x256 = Buffer.from(jwk256.x, 'base64url');
  const y256 = Buffer.from(jwk256.y, 'base64url');

  const wrongAlgKey = encodeCoseKeyEc2(x256, y256, { alg: -35 }); // ES384, not ES256
  const authDataWrongAlg = buildAuthData(Buffer.from('id2'), wrongAlgKey);
  check('C wrong alg', 'a non-ES256 alg is rejected',
    throws(() => extractCredentialPublicKey(authDataWrongAlg)), 'true');

  const wrongKtyKey = encodeCoseKeyEc2(x256, y256, { kty: 1 }); // OKP, not EC2
  const authDataWrongKty = buildAuthData(Buffer.from('id3'), wrongKtyKey);
  check('C wrong kty', 'a non-EC2 kty is rejected',
    throws(() => extractCredentialPublicKey(authDataWrongKty)), 'true');

  // Sanity: the SAME encoder with correct alg/crv/kty is accepted (proves the
  // three checks above fail because of the specific field, not because the
  // synthetic encoder itself produces unparseable output).
  const rightKey = encodeCoseKeyEc2(x256, y256);
  const authDataRight = buildAuthData(Buffer.from('id4'), rightKey);
  check('C sanity', 'the same shape with correct alg/crv/kty is accepted',
    throws(() => extractCredentialPublicKey(authDataRight)), 'false');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
