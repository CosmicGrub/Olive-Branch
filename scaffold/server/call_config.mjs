// OLIVE BRANCH — call provider configuration (MASTERFILE §16.2 #6, third
// reversal 2026-11-09). CALL_PROVIDER=jitsi|livekit, default jitsi.
//
// Pure functions of an env object so tests and registerRoutes(opts.callEnv)
// can drive them without touching process.env. Nothing here logs or returns a
// secret: callers get the secret only inside `config.jitsi.appSecret` for the
// token minter, and `describeCallConfig()` is the only thing safe to log.
//
// Validation follows server/secrets.mjs: JITSI_APP_SECRET, when set, must be
// valid hex of >= 32 bytes and, outside development/test, not a placeholder.
// A set-but-malformed value is a boot problem in every environment. An UNSET
// value is not a boot problem: the calls route then reports the provider
// unavailable, honestly (calls are switched on on demand, the rest of the
// stack must run without them).
import { parseHexSecret, looksLikePlaceholder } from './secrets.mjs';

export const CALL_PROVIDERS = ['jitsi', 'livekit'];
export const DEFAULT_CALL_PROVIDER = 'jitsi';
const RELAXED = new Set(['development', 'test']);
const APP_ID_RE = /^[A-Za-z0-9._-]{1,64}$/;
const DOMAIN_RE = /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$/;

/** Returns { provider, problems, jitsi|null, livekit|null, unavailable: string[] } */
export function resolveCallConfig(env = process.env) {
  const problems = [];
  const relaxed = RELAXED.has(env.NODE_ENV ?? '');
  const rawProvider = (env.CALL_PROVIDER ?? '').trim().toLowerCase();
  let provider = DEFAULT_CALL_PROVIDER;
  if (rawProvider) {
    if (CALL_PROVIDERS.includes(rawProvider)) provider = rawProvider;
    else problems.push(`CALL_PROVIDER must be one of ${CALL_PROVIDERS.join('|')}; got "${rawProvider}"`);
  }

  // --- Jitsi ---------------------------------------------------------------
  const jitsiTouched = ['JITSI_APP_ID', 'JITSI_APP_SECRET', 'JITSI_SERVER_URL'].some((k) => env[k]);
  let jitsi = null;
  const jitsiMissing = [];
  let secret = null, appId = null, serverURL = null;
  if (env.JITSI_APP_SECRET) {
    try {
      secret = parseHexSecret(env.JITSI_APP_SECRET, 'JITSI_APP_SECRET');
      if (!relaxed && looksLikePlaceholder(env.JITSI_APP_SECRET)) {
        throw new Error('JITSI_APP_SECRET looks like a placeholder; generate one with openssl rand -hex 32');
      }
    } catch (e) { problems.push(e.message); secret = null; }
  } else jitsiMissing.push('JITSI_APP_SECRET');
  if (env.JITSI_APP_ID) {
    if (APP_ID_RE.test(env.JITSI_APP_ID)) appId = env.JITSI_APP_ID;
    else problems.push('JITSI_APP_ID must be 1-64 characters of A-Z a-z 0-9 . _ -');
  } else jitsiMissing.push('JITSI_APP_ID');
  if (env.JITSI_SERVER_URL) {
    try {
      const u = new URL(env.JITSI_SERVER_URL);
      if (u.protocol !== 'https:' && !(relaxed && u.protocol === 'http:')) {
        throw new Error('JITSI_SERVER_URL must be an https:// URL (the LAN stack serves a self-signed cert; see tools/jitsi-selfhost/README.md)');
      }
      if (u.username || u.password || u.search || u.hash || (u.pathname && u.pathname !== '/')) {
        throw new Error('JITSI_SERVER_URL must be an origin only (scheme://host[:port]), no credentials, path or query');
      }
      serverURL = u.origin;
    } catch (e) {
      problems.push(e.message.startsWith('JITSI_SERVER_URL') ? e.message : 'JITSI_SERVER_URL is not a valid URL');
    }
  } else jitsiMissing.push('JITSI_SERVER_URL');
  const xmppDomain = (env.JITSI_XMPP_DOMAIN || 'meet.jitsi').trim();
  if (!DOMAIN_RE.test(xmppDomain)) problems.push('JITSI_XMPP_DOMAIN is not a valid host name');
  if (secret && appId && serverURL && DOMAIN_RE.test(xmppDomain)) {
    jitsi = { appId, appSecret: secret, serverURL, xmppDomain };
  }
  void jitsiTouched;

  // --- LiveKit (unchanged semantics: all three or unavailable) --------------
  const lk = { url: env.LIVEKIT_URL, apiKey: env.LIVEKIT_API_KEY, apiSecret: env.LIVEKIT_API_SECRET };
  const livekit = lk.url && lk.apiKey && lk.apiSecret ? lk : null;

  const unavailable = provider === 'jitsi'
    ? (jitsi ? [] : jitsiMissing)
    : (livekit ? [] : ['LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET'].filter((k) => !env[k]));
  return { provider, problems, jitsi, livekit, unavailable };
}

/** Safe to log: names and booleans only, never a value. */
export function describeCallConfig(cfg) {
  return {
    provider: cfg.provider,
    configured: cfg.provider === 'jitsi' ? !!cfg.jitsi : !!cfg.livekit,
    missing: cfg.unavailable,
  };
}
