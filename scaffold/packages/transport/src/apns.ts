/**
 * MASTERFILE §11 — Apple Push Notification service sender, over real HTTP/2.
 *
 * NEVER RUN AGAINST api.push.apple.com OR api.sandbox.push.apple.com IN THIS
 * REPOSITORY. No APNS_KEY_P8 exists anywhere in this environment and none
 * has been invented. What is proven here instead:
 *
 *   - the ES256 provider-token JWT (Apple's token-based, `.p8`-key auth),
 *     signed for real with node:crypto against a synthetic EC key;
 *   - the real HTTP/2 request shape (`:path`, `apns-*` headers, JSON body)
 *     built from a PushPayload, against a MOCKED node:http2-shaped session;
 *   - that missing/invalid env vars throw a clear, specific error rather
 *     than silently no-op'ing.
 *
 * packages/transport/test/apns.test.mjs is the suite that proves all three —
 * none of it has ever opened a real HTTP/2 connection to Apple.
 */
import { sign as cryptoSign } from 'node:crypto';
import * as nodeHttp2 from 'node:http2';
import type { PushPayload } from './push.ts';

const b64url = (buf: Buffer) => buf.toString('base64url');

const apnsError = (code: string, message: string, extra?: Record<string, unknown>) =>
  Object.assign(new Error(message), { code, ...extra });

// ------------------------------------------------------------ credentials --
export interface ApnsCreds { keyP8: string; keyId: string; teamId: string }

/** Read at CALL TIME — same reasoning as fcm.ts's readServiceAccount(). */
function readCreds(): ApnsCreds {
  const keyP8 = process.env.APNS_KEY_P8;
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const missing = [
    !keyP8 && 'APNS_KEY_P8', !keyId && 'APNS_KEY_ID', !teamId && 'APNS_TEAM_ID',
  ].filter(Boolean) as string[];
  if (missing.length) {
    throw apnsError('apns_config_missing',
      `APNs is not configured — missing environment variable(s): ${missing.join(', ')}. `
      + 'APNS_KEY_P8 is the PEM contents of a real Apple .p8 auth key '
      + '(Certificates, Identifiers & Profiles → Keys), never a placeholder.',
      { missing });
  }
  return { keyP8: keyP8!, keyId: keyId!, teamId: teamId! };
}

/** apns-topic is mandatory on every real APNs request; not one of the three
 * vars MASTERFILE named, but the send is not real without it. */
function readTopic(): string {
  const topic = process.env.APNS_TOPIC;
  if (!topic) {
    throw apnsError('apns_config_missing',
      'APNs is not configured — missing environment variable APNS_TOPIC '
      + '(the app\'s bundle id; APNs rejects every request without an apns-topic header).',
      { missing: ['APNS_TOPIC'] });
  }
  return topic;
}

// ---------------------------------------------------- provider token (JWT) --
interface CachedProviderToken { key: string; jwt: string; issuedAtMs: number }
let cachedProviderToken: CachedProviderToken | null = null;

/** Apple allows reuse for up to an hour; refresh at 50 minutes to stay
 * safely inside that window under real clock drift. */
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;

export function _resetApnsTokenCacheForTests(): void { cachedProviderToken = null; }

/**
 * ES256 JWT: header {alg:'ES256', kid}, claims {iss: teamId, iat}. The
 * signature must be the raw 64-byte R||S concatenation JOSE requires, NOT
 * the DER encoding node:crypto produces by default for EC keys — `
 * dsaEncoding: 'ieee-p1363'` is exactly the built-in option that produces
 * the JOSE form directly, so no manual DER→JOSE conversion is written here.
 */
function mintProviderToken(creds: ApnsCreds, nowMs: number): string {
  const cacheKey = `${creds.teamId}:${creds.keyId}`;
  if (cachedProviderToken && cachedProviderToken.key === cacheKey
      && nowMs - cachedProviderToken.issuedAtMs < PROVIDER_TOKEN_TTL_MS) {
    return cachedProviderToken.jwt;
  }
  const header = { alg: 'ES256', kid: creds.keyId };
  const claims = { iss: creds.teamId, iat: Math.floor(nowMs / 1000) };
  const signingInput =
    `${b64url(Buffer.from(JSON.stringify(header)))}.${b64url(Buffer.from(JSON.stringify(claims)))}`;

  let signature: Buffer;
  try {
    signature = cryptoSign('sha256', Buffer.from(signingInput), {
      key: creds.keyP8, dsaEncoding: 'ieee-p1363',
    } as any);
  } catch (e: any) {
    throw apnsError('apns_config_invalid',
      `APNS_KEY_P8 could not sign a JWT (not a valid EC .p8 private key?): ${e?.message ?? e}`);
  }
  const jwt = `${signingInput}.${b64url(signature)}`;
  cachedProviderToken = { key: cacheKey, jwt, issuedAtMs: nowMs };
  return jwt;
}

// -------------------------------------------------------- request shape ----
export const APNS_HOST_PRODUCTION = 'https://api.push.apple.com';
export const APNS_HOST_SANDBOX = 'https://api.sandbox.push.apple.com';

/**
 * PushPayload → the APNs JSON body. `aps.alert` mirrors call_incoming's own
 * notification:null (a VoIP push carries no alert — CallKit builds the UI
 * from the custom data instead); custom keys (kind/ref/v/callHandle) sit as
 * SIBLINGS of `aps` at the top level, exactly Apple's own convention.
 */
export function toApnsRequestBody(payload: PushPayload): Record<string, unknown> {
  const aps: Record<string, unknown> = {};
  if (payload.notification) {
    aps.alert = { title: payload.notification.title, body: payload.notification.body };
  }
  if (payload.apns?.contentAvailable) aps['content-available'] = 1;
  if (payload.apns?.interruptionLevel) aps['interruption-level'] = payload.apns.interruptionLevel;
  return { aps, ...payload.data };
}

// --------------------------------------------------- HTTP/2 transport ------
/** Just enough of node:http2's surface to mock in tests. */
export interface Http2StreamLike {
  setEncoding(enc: string): void;
  on(event: 'response', cb: (headers: Record<string, string | string[] | undefined>) => void): void;
  on(event: 'data', cb: (chunk: string) => void): void;
  on(event: 'end', cb: () => void): void;
  on(event: 'error', cb: (err: Error) => void): void;
  end(body: string): void;
}
export interface Http2SessionLike {
  request(headers: Record<string, string>): Http2StreamLike;
  on(event: 'error', cb: (err: Error) => void): void;
  close(): void;
}
export interface Http2Like {
  connect(authority: string): Http2SessionLike;
}

export interface ApnsSendOk { ok: true; apnsId: string | null }

/**
 * Sends one push via APNs HTTP/2. THROWS on any failure — config
 * (apns_config_missing/invalid), transport (apns_connect_failed/
 * apns_stream_failed) and API-level (apns_send_failed) alike, all as
 * `Error & { code: string }`, same convention as fcm.ts's sendFcm().
 *
 * `err.deviceGone === true` marks Apple's own definitive dead-token signals
 * (Unregistered, BadDeviceToken) — notify.ts prunes the row on these.
 */
export function sendApns(
  payload: PushPayload,
  opts: { host?: string; http2Impl?: Http2Like; now?: number } = {},
): Promise<ApnsSendOk> {
  const creds = readCreds();
  const topic = readTopic();
  const now = opts.now ?? Date.now();
  const jwt = mintProviderToken(creds, now);
  const host = opts.host ?? process.env.APNS_HOST ?? APNS_HOST_PRODUCTION;
  const h2: Http2Like = opts.http2Impl ?? (nodeHttp2 as unknown as Http2Like);
  const apnsTopic = payload.apns?.topicSuffix ? `${topic}${payload.apns.topicSuffix}` : topic;
  const body = JSON.stringify(toApnsRequestBody(payload));

  return new Promise<ApnsSendOk>((resolve, reject) => {
    let session: Http2SessionLike;
    try {
      session = h2.connect(host);
    } catch (e: any) {
      reject(apnsError('apns_connect_failed', `APNs HTTP/2 connect failed: ${e?.message ?? e}`));
      return;
    }
    session.on('error', (err: Error) => {
      reject(apnsError('apns_connect_failed', `APNs HTTP/2 session error: ${err.message}`));
    });

    const req = session.request({
      ':method': 'POST',
      ':path': `/3/device/${payload.token}`,
      'authorization': `bearer ${jwt}`,
      'apns-topic': apnsTopic,
      'apns-push-type': payload.apns?.pushType ?? 'alert',
      'apns-priority': String(payload.apns?.priority ?? 10),
      'content-type': 'application/json',
    });

    let status = 0;
    let responseBody = '';
    req.on('response', (headers) => {
      status = Number(headers[':status']);
    });
    req.setEncoding('utf8');
    req.on('data', (chunk: string) => { responseBody += chunk; });
    req.on('error', (err: Error) => {
      reject(apnsError('apns_stream_failed', `APNs HTTP/2 stream error: ${err.message}`));
    });
    req.on('end', () => {
      session.close();
      if (status === 200) {
        resolve({ ok: true, apnsId: null });
        return;
      }
      let reason = 'Unknown';
      try { reason = JSON.parse(responseBody || '{}').reason ?? 'Unknown'; } catch { /* non-JSON body */ }
      reject(apnsError('apns_send_failed', `APNs send failed: ${status} ${reason}`, {
        status, reason,
        deviceGone: reason === 'Unregistered' || reason === 'BadDeviceToken',
      }));
    });
    req.end(body);
  });
}
