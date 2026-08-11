/**
 * MASTERFILE §11 — FCM v1 HTTP API sender.
 *
 * NEVER RUN AGAINST A LIVE fcm.googleapis.com ENDPOINT IN THIS REPOSITORY.
 * No FCM_SERVICE_ACCOUNT_JSON exists anywhere in this environment and none
 * has been invented — that would be exactly the "declared it and did not
 * build it" failure mode packages/transport/src/channels.ts's own header
 * warns against, just inverted (claiming a real send that never ran, instead
 * of admitting a mechanism was never built). What is proven here instead:
 *
 *   - the OAuth2 self-signed-JWT-bearer flow (RFC 7523) that mints the
 *     bearer token FCM v1 requires, signed for real with node:crypto's
 *     RS256, against a MOCKED `fetch`;
 *   - the real FCM v1 `messages:send` request shape (URL, headers, body)
 *     built from a PushPayload, against the same mock;
 *   - that a missing/invalid FCM_SERVICE_ACCOUNT_JSON throws a clear,
 *     specific error rather than silently no-op'ing.
 *
 * packages/transport/test/fcm.test.mjs is the suite that proves all three —
 * none of it has ever touched a real Google endpoint.
 */
import { createSign } from 'node:crypto';
import type { PushPayload } from './push.ts';

// ------------------------------------------------------------- transport ---
/** Just enough of the Fetch API surface to mock in tests. */
export interface FetchResponseLike {
  ok: boolean;
  status: number;
  json(): Promise<any>;
  text(): Promise<string>;
}
export type FetchLike = (url: string, init: {
  method: string; headers: Record<string, string>; body: string;
}) => Promise<FetchResponseLike>;

const b64url = (buf: Buffer) => buf.toString('base64url');

const fcmError = (code: string, message: string, extra?: Record<string, unknown>) =>
  Object.assign(new Error(message), { code, ...extra });

// ------------------------------------------------------------ credentials --
export interface FcmServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  /** Defaults to Google's real token endpoint; overridable for a mock. */
  token_uri?: string;
}

/**
 * Read at CALL TIME, never at import time — a route registered before
 * FCM_SERVICE_ACCOUNT_JSON is set (or a process that never sets it, e.g. an
 * apns-only deploy) must not crash the whole server on module load.
 */
function readServiceAccount(): FcmServiceAccount {
  const raw = process.env.FCM_SERVICE_ACCOUNT_JSON;
  if (!raw) {
    throw fcmError('fcm_config_missing',
      'FCM_SERVICE_ACCOUNT_JSON environment variable is not set — cannot send FCM push. '
      + 'This is a real Firebase service-account JSON (Project Settings → Service '
      + 'Accounts → Generate new private key), never a placeholder.');
  }
  let parsed: any;
  try { parsed = JSON.parse(raw); }
  catch {
    throw fcmError('fcm_config_invalid', 'FCM_SERVICE_ACCOUNT_JSON is not valid JSON.');
  }
  for (const k of ['client_email', 'private_key', 'project_id']) {
    if (!parsed[k]) {
      throw fcmError('fcm_config_invalid',
        `FCM_SERVICE_ACCOUNT_JSON is missing required field "${k}".`);
    }
  }
  return parsed as FcmServiceAccount;
}

// ------------------------------------------------------- OAuth2 (RFC 7523) --
const GOOGLE_TOKEN_URI = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

interface CachedToken { key: string; accessToken: string; expiresAtMs: number }
let cachedToken: CachedToken | null = null;

/**
 * IN-FLIGHT MINT COALESCING — fixes an adversarial-review finding.
 *
 * Without this, two notifyDevices() calls landing concurrently (e.g. two
 * different households' notifications firing near-simultaneously) at a
 * moment cachedToken is null/expired would both read the same stale cache
 * BEFORE either finishes minting (there's a real network `await` between the
 * cache check and the cache write), so both independently sign an RS256 JWT
 * and POST to Google's OAuth endpoint — redundant work that scales with
 * concurrent send volume and could trip Google's own rate limits during a
 * broadcast burst. Each token minted this way is individually valid (no
 * stale-token-reuse bug), so this is a resource-efficiency fix, not a
 * correctness one.
 *
 * A second caller that arrives while a mint for the SAME service account is
 * already in flight joins that same promise instead of starting a new one.
 */
let inFlightMint: { key: string; promise: Promise<string> } | null = null;

/** Test-only: cache + in-flight state are both module-level, so a suite that
 * changes the service account between cases must be able to clear both. */
export function _resetFcmTokenCacheForTests(): void {
  cachedToken = null;
  inFlightMint = null;
}

async function safeText(res: FetchResponseLike): Promise<string> {
  try { return await res.text(); } catch { return '<unreadable body>'; }
}

/**
 * Self-signed JWT → POST to Google's OAuth token endpoint → bearer token,
 * cached until near expiry. RS256 over `header.claims`, signed with the
 * service account's RSA private key via node:crypto — no shortcut library,
 * no invented signing scheme.
 */
async function mintAccessToken(
  sa: FcmServiceAccount, fetchImpl: FetchLike, nowMs: number,
): Promise<string> {
  const cacheKey = sa.client_email + '|' + sa.project_id;
  // 60s safety margin before Google's own expiry — never send a token that
  // might lapse mid-flight.
  if (cachedToken && cachedToken.key === cacheKey && cachedToken.expiresAtMs - 60_000 > nowMs) {
    return cachedToken.accessToken;
  }

  // COALESCE: a mint for this exact service account is already in flight —
  // join it rather than signing and POSTing a second, redundant JWT. This
  // check (and the inFlightMint assignment below, once a fresh mint starts)
  // both happen synchronously, with no `await` between them, so two callers
  // racing on the same tick can never both fall through to a fresh mint.
  if (inFlightMint && inFlightMint.key === cacheKey) {
    return inFlightMint.promise;
  }

  const promise = doMintAccessToken(sa, fetchImpl, nowMs, cacheKey);
  inFlightMint = { key: cacheKey, promise };
  try {
    return await promise;
  } finally {
    // Only clear if we're still the current in-flight entry for this key —
    // a later mint (e.g. after this one failed and a retry started) must not
    // have its own in-flight marker wiped out by this settling late.
    if (inFlightMint && inFlightMint.promise === promise) inFlightMint = null;
  }
}

/** The actual JWT-sign + OAuth POST, extracted so mintAccessToken() above can
 * assign its Promise to `inFlightMint` BEFORE awaiting it — that ordering is
 * what lets a second concurrent caller find and join it instead of starting
 * its own. */
async function doMintAccessToken(
  sa: FcmServiceAccount, fetchImpl: FetchLike, nowMs: number, cacheKey: string,
): Promise<string> {
  const tokenUri = sa.token_uri ?? GOOGLE_TOKEN_URI;
  const iat = Math.floor(nowMs / 1000);
  const exp = iat + 3600; // Google's own maximum for this grant type.
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = { iss: sa.client_email, scope: FCM_SCOPE, aud: tokenUri, iat, exp };
  const signingInput =
    `${b64url(Buffer.from(JSON.stringify(header)))}.${b64url(Buffer.from(JSON.stringify(claims)))}`;

  const signer = createSign('RSA-SHA256');
  signer.update(signingInput);
  signer.end();
  let signature: Buffer;
  try {
    signature = signer.sign(sa.private_key);
  } catch (e: any) {
    throw fcmError('fcm_config_invalid',
      `FCM_SERVICE_ACCOUNT_JSON's private_key could not sign a JWT: ${e?.message ?? e}`);
  }
  const assertion = `${signingInput}.${b64url(signature)}`;

  const res = await fetchImpl(tokenUri, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });
  if (!res.ok) {
    throw fcmError('fcm_oauth_failed',
      `FCM OAuth token request failed: ${res.status} ${await safeText(res)}`, { status: res.status });
  }
  const json = await res.json();
  if (!json?.access_token) {
    throw fcmError('fcm_oauth_failed', 'FCM OAuth response had no access_token.');
  }
  cachedToken = {
    key: cacheKey, accessToken: json.access_token,
    expiresAtMs: nowMs + (Number(json.expires_in) || 3600) * 1000,
  };
  return json.access_token;
}

// -------------------------------------------------------- request shape ----
/**
 * PushPayload → real FCM v1 `messages:send` body.
 *
 * call_incoming's payload has notification:null (buildPush()'s own doing —
 * a call must RING, not display a banner). That is translated here to a
 * DATA-ONLY message: no `notification` block at all, so there is no FCM
 * wire field to set for "full-screen intent" — that is not a real FCM v1
 * field. Android's actual mechanism is client-side: a data-only message
 * always reaches the app's FirebaseMessagingService (subject to OS
 * constraints), and the client builds the full-screen notification itself
 * from data.kind === 'call_incoming', using
 * NotificationCompat.Builder.setFullScreenIntent(). Inventing an FCM field
 * that doesn't exist would be worse than this comment; the real mechanism is
 * client-side and out of scope for this server-side sender.
 */
export function toFcmRequestBody(payload: PushPayload): { message: Record<string, unknown> } {
  const message: Record<string, unknown> = { token: payload.token, data: payload.data };
  if (payload.notification) {
    message.notification = { title: payload.notification.title, body: payload.notification.body };
  }
  if (payload.android) {
    const android: Record<string, unknown> = {
      priority: payload.android.priority === 'high' ? 'HIGH' : 'NORMAL',
    };
    if (payload.android.collapseKey) android.collapse_key = payload.android.collapseKey;
    if (payload.notification) android.notification = { channel_id: payload.android.channelId };
    message.android = android;
  }
  return { message };
}

// ------------------------------------------------------------------ send ---
export interface FcmSendOk { ok: true; name: string }

/**
 * Sends one push via FCM v1. THROWS on any failure — config errors
 * (fcm_config_missing / fcm_config_invalid), OAuth errors (fcm_oauth_failed),
 * and API-level send errors (fcm_send_failed) alike, all as
 * `Error & { code: string }` so a caller (packages/transport/src/notify.ts)
 * can catch per-device without one device's failure aborting the rest.
 *
 * `err.deviceGone === true` marks FCM's own signal that the token is
 * permanently invalid (UNREGISTERED, or a 404) — notify.ts uses this to
 * prune the row via removeDeviceTokenSystem().
 */
export async function sendFcm(
  payload: PushPayload,
  opts: { fetchImpl?: FetchLike; now?: number } = {},
): Promise<FcmSendOk> {
  const fetchImpl = opts.fetchImpl ?? (globalThis.fetch as unknown as FetchLike | undefined);
  if (!fetchImpl) {
    throw fcmError('fcm_no_transport', 'No fetch implementation available to send FCM push.');
  }
  const now = opts.now ?? Date.now();
  const sa = readServiceAccount();
  const accessToken = await mintAccessToken(sa, fetchImpl, now);

  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  const res = await fetchImpl(url, {
    method: 'POST',
    headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify(toFcmRequestBody(payload)),
  });
  if (!res.ok) {
    let reason = 'UNKNOWN';
    try {
      const body = await res.json();
      reason = body?.error?.details?.find((d: any) => d.errorCode)?.errorCode
        ?? body?.error?.status ?? 'UNKNOWN';
    } catch { /* body wasn't JSON; fall through with UNKNOWN */ }
    throw fcmError('fcm_send_failed', `FCM send failed: ${res.status} ${reason}`, {
      status: res.status, reason,
      deviceGone: reason === 'UNREGISTERED' || res.status === 404,
    });
  }
  const json = await res.json();
  return { ok: true, name: json?.name ?? '' };
}
