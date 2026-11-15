// OLIVE BRANCH — push provider configuration (MASTERFILE §11), the sibling of
// server/call_config.mjs.
//
// Until now nothing told an operator whether the server COULD send a push: the
// FCM sender read FCM_SERVICE_ACCOUNT_JSON lazily on the first send, the
// compose files never passed it into the container, and a missing credential
// only surfaced as a per-device `fcm_config_missing` result nobody reads. This
// module makes the state visible at boot and on the operator-only metrics
// endpoint, without ever making push a boot requirement (the app is
// offline-first: a server with no Firebase project must still run).
//
// Pure functions of an env object so tests can drive them without touching
// process.env. Nothing here returns or logs a secret, a key, an e-mail, a
// project id or a file path: names and booleans only.
import { inspectFcmConfig } from '../packages/transport/src/fcm.mjs';

const APNS_KEYS = ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC'];

/** Returns { fcm: {configured, source, problem}, apns: {configured}, problems: string[] }. */
export function resolvePushConfig(env = process.env) {
  const fcm = inspectFcmConfig(env);
  const problems = [];
  if (fcm.problem) problems.push(`FCM: ${fcm.problem}`);
  const apnsSet = APNS_KEYS.filter((k) => env[k]);
  const apns = { configured: apnsSet.length === APNS_KEYS.length };
  // A half-configured APNs is an operator mistake worth naming; none at all is normal.
  if (apnsSet.length > 0 && !apns.configured) {
    problems.push(`APNs: set ${apnsSet.length} of ${APNS_KEYS.length} variables; all four are needed`);
  }
  return { fcm, apns, problems };
}

/**
 * Safe to log and to return from /internal/metrics. `androidRing` is the one
 * line an operator actually wants: can a closed Android app be woken at all.
 */
export function describePushConfig(cfg) {
  return {
    androidRing: cfg.fcm.configured ? 'ready' : 'not_configured',
    fcm: { configured: cfg.fcm.configured, source: cfg.fcm.source },
    apns: { configured: cfg.apns.configured },
    problems: cfg.problems.length,
  };
}
