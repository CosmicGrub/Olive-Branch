// OLIVE BRANCH — the WebAuthn relying party, from the environment (identity
// lane, audit gap 2).
//
// routes.mjs used to hard-code RP_ID = 'olivebranch.local' with a comment saying
// it must change before shipping and no way to change it. A real Android phone
// can only register or assert a passkey for an rpId that is a real domain the
// server serves /.well-known/assetlinks.json for, and Credential Manager reports
// the ceremony origin as `android:apk-key-hash:<base64url sha256 of the signing
// cert>`, not an https URL. This module makes all three configurable and
// validated, and builds the assetlinks document from the same values.
//
//   WEBAUTHN_RP_ID           the registrable domain, e.g. olive.example.org
//   WEBAUTHN_ORIGIN          the web origin (default https://<rpId>)
//   WEBAUTHN_ANDROID_ORIGINS comma list of android:apk-key-hash:<43 chars> (one per
//                            signing key: debug, release, Play app signing)
//   WEBAUTHN_ANDROID_PACKAGE the applicationId (default com.olivebranch.olive_client)
//
// Unset outside production keeps the historical dev default so every existing
// test and `docker compose up` behaves exactly as before. Unset IN production is
// a boot WARNING, not an exit: an operator with no domain yet still has the
// device-credential sign-in (POST /v1/auth/session/refresh), and a passkey
// ceremony against the unusable dev default cannot succeed anyway. A value that
// IS set but malformed is a boot problem in every mode.
export const DEV_RP_ID = 'olivebranch.local';
export const DEFAULT_ANDROID_PACKAGE = 'com.olivebranch.olive_client';
const ANDROID_ORIGIN_RE = /^android:apk-key-hash:[A-Za-z0-9_-]{43}$/;
const HOST_RE = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

/** Pure. Returns { rpId, rpOrigin, androidOrigins: string[], androidPackage, problems, warnings }. */
export function resolveWebauthn(env = process.env) {
  const problems = [], warnings = [];
  const prod = env.NODE_ENV === 'production';
  const rawId = (env.WEBAUTHN_RP_ID ?? '').trim();
  let rpId = DEV_RP_ID;
  if (rawId) {
    if (!HOST_RE.test(rawId) || rawId.endsWith('.local') || rawId.endsWith('.localhost') ||
        rawId.endsWith('.test') || rawId.endsWith('.invalid') || /^\d+(\.\d+){3}$/.test(rawId)) {
      problems.push('WEBAUTHN_RP_ID must be a real lowercase domain name (no scheme, port, IP address or .local/.test name)');
    } else rpId = rawId;
  } else if (prod) {
    warnings.push('WEBAUTHN_RP_ID is not set: passkeys are unusable (the development default cannot match a real device). ' +
      'Device-credential sign-in still works. Set WEBAUTHN_RP_ID to your domain to enable passkeys.');
  }

  let rpOrigin = `https://${rpId}`;
  const rawOrigin = (env.WEBAUTHN_ORIGIN ?? '').trim();
  if (rawOrigin) {
    let u = null;
    try { u = new URL(rawOrigin); } catch { /* reported below */ }
    if (!u || u.protocol !== 'https:' || u.origin !== rawOrigin ||
        !(u.hostname === rpId || u.hostname.endsWith(`.${rpId}`))) {
      problems.push('WEBAUTHN_ORIGIN must be an https origin (no path) whose host is the rpId or a subdomain of it');
    } else rpOrigin = rawOrigin;
  }

  const androidOrigins = [];
  for (const part of (env.WEBAUTHN_ANDROID_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean)) {
    if (!ANDROID_ORIGIN_RE.test(part)) {
      problems.push('WEBAUTHN_ANDROID_ORIGINS entries must look like android:apk-key-hash:<43-char base64url SHA-256 of the signing certificate>');
    } else if (!androidOrigins.includes(part)) androidOrigins.push(part);
  }
  const androidPackage = ((env.WEBAUTHN_ANDROID_PACKAGE ?? '').trim() || DEFAULT_ANDROID_PACKAGE);
  if (!/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/.test(androidPackage)) {
    problems.push('WEBAUTHN_ANDROID_PACKAGE is not a valid Android applicationId');
  }
  if (androidOrigins.length && !rawId) {
    warnings.push('WEBAUTHN_ANDROID_ORIGINS is set without WEBAUTHN_RP_ID: Android origins are accepted but the rpId is still the development default');
  }
  return { rpId, rpOrigin, androidOrigins, androidPackage, problems, warnings };
}

/** Is this clientDataJSON origin one the server will accept for a ceremony? */
export function originAllowed(cfg, origin) {
  return typeof origin === 'string' && (origin === cfg.rpOrigin || cfg.androidOrigins.includes(origin));
}

/**
 * The Digital Asset Links document for GET /.well-known/assetlinks.json. The
 * fingerprint is the colon-hex SHA-256 of the signing certificate, recovered
 * from the same base64url hash the android origin carries, so there is exactly
 * one value to configure per signing key. Returns [] when no Android origin is
 * configured (an empty, valid document: nothing is claimed).
 */
export function assetLinks(cfg) {
  const fingerprints = cfg.androidOrigins.map((o) => {
    const hex = Buffer.from(o.slice('android:apk-key-hash:'.length), 'base64url').toString('hex').toUpperCase();
    return hex.match(/../g).join(':');
  });
  if (!fingerprints.length) return [];
  return [{
    relation: ['delegate_permission/common.get_login_creds', 'delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name: cfg.androidPackage, sha256_cert_fingerprints: fingerprints },
  }];
}

/** For tests/tools: the android origin string for a certificate's SHA-256 digest (Buffer). */
export function androidOriginFor(certSha256) {
  return `android:apk-key-hash:${Buffer.from(certSha256).toString('base64url')}`;
}
