/**
 * server/webauthn_config.mjs — the WebAuthn relying party from the environment
 * (identity lane, audit gap 2). Pure: no database, no sockets.
 *
 *   A. resolveWebauthn: dev default unchanged; production-unset is a WARNING (not
 *      a boot failure); malformed values are PROBLEMS in every mode.
 *   B. originAllowed: exact https origin or an exact configured android origin.
 *   C. assetLinks: the Digital Asset Links document is derived from the same
 *      android origins (colon-hex SHA-256), empty when none is configured.
 *   D. verifyAssertion with an android:apk-key-hash origin: a real P-256
 *      assertion is accepted only when that exact origin is configured, and is
 *      refused for any other hash, any other string, and with no extraOrigins at
 *      all (so nothing changes for a server that never sets the variable).
 */
import { createHash, createSign, generateKeyPairSync, randomBytes } from 'node:crypto';
import { resolveWebauthn, originAllowed, assetLinks, androidOriginFor, DEV_RP_ID, DEFAULT_ANDROID_PACKAGE }
  from '../webauthn_config.mjs';
import { verifyAssertion } from '../../packages/auth/src/auth.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const cert = createHash('sha256').update('release-signing-cert').digest();
const other = createHash('sha256').update('some-other-key').digest();
const A1 = androidOriginFor(cert);
const A2 = androidOriginFor(other);

// ---- A -------------------------------------------------------------------
{
  const dev = resolveWebauthn({});
  check('A resolve', 'unset (dev) keeps the historical default exactly', `${dev.rpId}|${dev.rpOrigin}|${dev.problems.length}|${dev.warnings.length}`, `${DEV_RP_ID}|https://${DEV_RP_ID}|0|0`);
  const emptyStrings = resolveWebauthn({ WEBAUTHN_RP_ID: '', WEBAUTHN_ORIGIN: '', WEBAUTHN_ANDROID_ORIGINS: '', WEBAUTHN_ANDROID_PACKAGE: '' });
  check('A resolve', 'empty strings (docker compose passes them through) count as unset', `${emptyStrings.rpId}|${emptyStrings.problems.length}|${emptyStrings.androidPackage}`, `${DEV_RP_ID}|0|${DEFAULT_ANDROID_PACKAGE}`);
  const prodUnset = resolveWebauthn({ NODE_ENV: 'production' });
  check('A resolve', 'unset in production is a warning, not a boot problem', `${prodUnset.problems.length}|${prodUnset.warnings.length}`, '0|1');
  const ok = resolveWebauthn({ NODE_ENV: 'production', WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ANDROID_ORIGINS: `${A1}, ${A2}, ${A1}` });
  check('A resolve', 'a real domain is accepted and the origin defaults to https://<rpId>', `${ok.rpId}|${ok.rpOrigin}|${ok.problems.length}`, 'olive.example.org|https://olive.example.org|0');
  check('A resolve', 'android origins are trimmed and de-duplicated', ok.androidOrigins.length, 2);
  check('A resolve', 'default android package is the app id', ok.androidPackage, DEFAULT_ANDROID_PACKAGE);
  for (const bad of ['olivebranch.local', 'localhost', 'example', 'https://olive.example.org', 'olive.example.org:8443', ['10', '0', '0', '5'].join('.'), 'Olive.Example.Org', 'a..b.org', 'foo.test']) {
    check('A resolve', `rpId ${JSON.stringify(bad)} is a boot problem`, resolveWebauthn({ WEBAUTHN_RP_ID: bad }).problems.length > 0, true);
  }
  check('A resolve', 'an origin on another host is a problem', resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ORIGIN: 'https://evil.example.com' }).problems.length > 0, true);
  check('A resolve', 'an http origin is a problem', resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ORIGIN: 'http://olive.example.org' }).problems.length > 0, true);
  check('A resolve', 'an origin with a path is a problem', resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ORIGIN: 'https://olive.example.org/app' }).problems.length > 0, true);
  check('A resolve', 'a subdomain origin of the rpId is allowed', resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ORIGIN: 'https://app.olive.example.org' }).problems.length, 0);
  check('A resolve', 'a malformed android origin is a problem', resolveWebauthn({ WEBAUTHN_ANDROID_ORIGINS: 'android:apk-key-hash:short' }).problems.length > 0, true);
  check('A resolve', 'an https URL in the android list is a problem', resolveWebauthn({ WEBAUTHN_ANDROID_ORIGINS: 'https://x.example.org' }).problems.length > 0, true);
  check('A resolve', 'a bad package name is a problem', resolveWebauthn({ WEBAUTHN_ANDROID_PACKAGE: 'not a package' }).problems.length > 0, true);
}

// ---- B -------------------------------------------------------------------
{
  const cfg = resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ANDROID_ORIGINS: A1 });
  check('B origin', 'the https origin is allowed', originAllowed(cfg, 'https://olive.example.org'), true);
  check('B origin', 'the configured android origin is allowed', originAllowed(cfg, A1), true);
  check('B origin', 'a different android hash is refused', originAllowed(cfg, A2), false);
  check('B origin', 'a look-alike https origin is refused', originAllowed(cfg, 'https://olive.example.org.evil.com'), false);
  check('B origin', 'a prefix of the android origin is refused', originAllowed(cfg, A1.slice(0, -1)), false);
  check('B origin', 'undefined / non-string is refused', `${originAllowed(cfg, undefined)}|${originAllowed(cfg, 42)}|${originAllowed(cfg, null)}`, 'false|false|false');
}

// ---- C -------------------------------------------------------------------
{
  check('C assetlinks', 'no android origin configured -> an empty (valid) document', JSON.stringify(assetLinks(resolveWebauthn({}))), '[]');
  const doc = assetLinks(resolveWebauthn({ WEBAUTHN_RP_ID: 'olive.example.org', WEBAUTHN_ANDROID_ORIGINS: `${A1},${A2}` }));
  const t = doc[0].target;
  check('C assetlinks', 'one android_app statement for the app package', `${doc.length}|${t.namespace}|${t.package_name}`, `1|android_app|${DEFAULT_ANDROID_PACKAGE}`);
  check('C assetlinks', 'one fingerprint per signing key, colon-hex SHA-256 (32 bytes)', `${t.sha256_cert_fingerprints.length}|${t.sha256_cert_fingerprints[0].split(':').length}`, '2|32');
  check('C assetlinks', 'the fingerprint IS the certificate digest', t.sha256_cert_fingerprints[0].replace(/:/g, '').toLowerCase(), cert.toString('hex'));
  check('C assetlinks', 'the relation grants credential sharing', doc[0].relation.includes('delegate_permission/common.get_login_creds'), true);
}

// ---- D -------------------------------------------------------------------
{
  const rpId = 'olive.example.org';
  const rpIdHash = createHash('sha256').update(rpId, 'utf8').digest();
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const publicKeyPem = publicKey.export({ type: 'spki', format: 'pem' });
  const challenge = randomBytes(24).toString('base64url');
  const assert = (origin) => {
    const clientDataJSONBuf = Buffer.from(JSON.stringify({ type: 'webauthn.get', challenge, origin }), 'utf8');
    const authData = Buffer.concat([rpIdHash, Buffer.from([0x05]), (() => { const b = Buffer.alloc(4); b.writeUInt32BE(1); return b; })()]);
    const sig = createSign('sha256').update(Buffer.concat([authData, createHash('sha256').update(clientDataJSONBuf).digest()])).sign(privateKey);
    return { credentialId: 'cred', clientDataJSON: clientDataJSONBuf.toString('base64url'), authenticatorData: authData.toString('base64url'), signature: sig.toString('base64url') };
  };
  const verify = (origin, extraOrigins) => verifyAssertion({
    assertion: assert(origin), credential: { credentialId: 'cred', publicKeyPem, signCount: 0, userId: 'u' },
    expectedChallenge: challenge, expectedOrigin: `https://${rpId}`, extraOrigins,
    expectedRpIdHash: rpIdHash, challengeIssuedAt: Date.now(), now: Date.now() });

  check('D assertion', 'the https origin still verifies, with no extraOrigins (unchanged behaviour)', verify(`https://${rpId}`, undefined).ok, true);
  check('D assertion', 'an android origin verifies when that exact origin is configured', verify(A1, [A1]).ok, true);
  const noExtra = verify(A1, undefined);
  check('D assertion', 'the same android assertion is refused with no extraOrigins', `${noExtra.ok}|${noExtra.reason}`, 'false|origin_mismatch');
  check('D assertion', 'refused when only a different android hash is configured', verify(A1, [A2]).ok, false);
  check('D assertion', 'refused when extraOrigins is empty', verify(A1, []).ok, false);
  check('D assertion', 'an unlisted https origin is refused even if android origins are configured', verify('https://evil.example.com', [A1]).ok, false);
  check('D assertion', 'a missing origin is refused', verify(undefined, [A1]).ok, false);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
