// OLIVE BRANCH — boot-time check of the push credentials. Server audit G4.
//
// fcm.ts reads FCM_SERVICE_ACCOUNT_JSON at SEND time, so an operator who sets it wrongly
// (a truncated paste, the wrong file, a placeholder) found out only when a real child's
// message failed to ring, and then only as a swallowed push error. This checks it once at
// boot instead, the way server/secrets.mjs checks the session secret:
//
//   - unset                  -> push is simply off. Not an error: the inbox still fills,
//                               the child's app still polls. A one-line note says so.
//   - set and well-formed    -> "on".
//   - set and malformed      -> a boot problem (the process exits 2), because "I turned push
//                               on and it silently never fires" is the worst failure here.
//
// FCM_SERVICE_ACCOUNT_FILE is the file-secret form (a path to the Firebase service-account
// JSON, mounted from OUTSIDE the repository, e.g. a docker secret). When it is set and
// FCM_SERVICE_ACCOUNT_JSON is not, the file's content is returned for the caller to publish
// as FCM_SERVICE_ACCOUNT_JSON, the only place fcm.ts looks. The JSON variable wins if both
// are set. Nothing here ever returns, logs or echoes a key: messages name the variable and
// the missing field only.
//
// Honest scope: this validates SHAPE. It cannot prove Google accepts the key; live push is
// unverified until the owner supplies a Firebase project and a device has received one.
import { readFileSync } from 'node:fs';

const REQUIRED = ['client_email', 'private_key', 'project_id'];

/**
 * @returns {{ fcm: 'off' | 'on', problems: string[], json: string | null }}
 *   `json` is the service-account JSON to publish as FCM_SERVICE_ACCOUNT_JSON (only when it
 *   came from FCM_SERVICE_ACCOUNT_FILE); null otherwise.
 */
export function checkPushConfig(env = process.env, readFile = (p) => readFileSync(p, 'utf8')) {
  const problems = [];
  let raw = env.FCM_SERVICE_ACCOUNT_JSON;
  let fromFile = false;
  if (!raw && env.FCM_SERVICE_ACCOUNT_FILE) {
    try { raw = readFile(env.FCM_SERVICE_ACCOUNT_FILE); fromFile = true; }
    catch { problems.push('FCM_SERVICE_ACCOUNT_FILE is set but the file cannot be read'); }
  }
  if (!raw) return { fcm: 'off', problems, json: null };
  let parsed;
  try { parsed = JSON.parse(raw); }
  catch {
    problems.push(`${fromFile ? 'FCM_SERVICE_ACCOUNT_FILE' : 'FCM_SERVICE_ACCOUNT_JSON'} is not valid JSON`);
    return { fcm: 'off', problems, json: null };
  }
  if (!parsed || typeof parsed !== 'object') {
    problems.push('the FCM service account must be a JSON object');
    return { fcm: 'off', problems, json: null };
  }
  for (const k of REQUIRED) {
    if (typeof parsed[k] !== 'string' || !parsed[k].trim()) {
      problems.push(`the FCM service account is missing required field "${k}"`);
    }
  }
  if (typeof parsed.private_key === 'string' && !/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(parsed.private_key)) {
    problems.push('the FCM service account "private_key" is not a PEM private key');
  }
  if (problems.length) return { fcm: 'off', problems, json: null };
  return { fcm: 'on', problems, json: fromFile ? raw : null };
}
