/**
 * Push configuration and the small pure helpers of the push/calls lane. No
 * database: every case is a pure function of an env object or a payload.
 *
 *   A  FCM credential: file vs inline, precedence, every bad shape, no leak
 *   B  resolvePushConfig / describePushConfig: names and booleans only
 *   C  the sender really reads the FILE (against a mocked fetch)
 *   D  FCM_API_BASE_URL is honoured only outside production
 *   E  ringStateFrom: the one word the guardian UI gets, built from `code` only
 *   F  isLanOnlyHost: which call servers only work on the same Wi-Fi
 *   G  call_cancelled: a silent, content-free, data-only kind
 *   H  scheduler registry: the fast lane is a strict subset, in a safe order
 */
import { generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolvePushConfig, describePushConfig } from '../push_config.mjs';
import { inspectFcmConfig, fcmApiBase, sendFcm, toFcmRequestBody,
         _resetFcmTokenCacheForTests } from '../../packages/transport/src/fcm.mjs';
import { buildPush, auditPush, sendGuard, GENERIC } from '../../packages/transport/src/push.mjs';
import { toApnsRequestBody } from '../../packages/transport/src/apns.mjs';
import { ringStateFrom, isLanOnlyHost } from '../routes.mjs';
import { JOB_NAMES, FAST_JOBS } from '../../tools/scheduler.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const dir = mkdtempSync(join(tmpdir(), 'olive-pushcfg-'));
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const SA = { client_email: 'olive@proj.iam.gserviceaccount.com', private_key: PEM, project_id: 'proj' };
const file = (name, content) => { const p = join(dir, name); writeFileSync(p, content); return p; };
const GOOD_FILE = file('good.json', JSON.stringify(SA));

// ---- A ----------------------------------------------------------------------
{
  const g = 'A credential';
  check(g, 'nothing set: not configured, no problem (push is optional)', JSON.stringify(inspectFcmConfig({})), '{"configured":false,"source":"none","problem":null}');
  check(g, 'a good file is configured, source file', JSON.stringify(inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: GOOD_FILE })), '{"configured":true,"source":"file","problem":null}');
  check(g, 'inline JSON still works, source env', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(SA) }).source, 'env');
  const both = inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: GOOD_FILE, FCM_SERVICE_ACCOUNT_JSON: '{broken' });
  check(g, 'the file wins over inline JSON (a broken inline value is ignored)', `${both.configured}/${both.source}`, 'true/file');
  const missing = inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: join(dir, 'nope.json') });
  check(g, 'an unreadable file is a problem, not a crash', `${missing.configured}/${missing.problem}`, 'false/FCM_SERVICE_ACCOUNT_FILE could not be read.');
  check(g, '...and the message does not echo the path', missing.problem.includes(dir), false);
  check(g, 'a directory instead of a file is a problem', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: dir }).configured, false);
  check(g, 'non-JSON content is a problem', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('bad.json', 'not json{{') }).problem, 'FCM_SERVICE_ACCOUNT_FILE is not valid JSON.');
  check(g, 'a missing field is named', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('nofield.json', JSON.stringify({ ...SA, project_id: undefined })) }).problem, 'FCM_SERVICE_ACCOUNT_FILE is missing required field "project_id".');
  const badKey = inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('badkey.json', JSON.stringify({ ...SA, private_key: 'not a pem' })) });
  check(g, 'a private_key that could never sign is caught at boot', `${badKey.configured}/${badKey.problem}`, 'false/the private_key is not a usable PEM key');
  check(g, 'no problem text ever contains the key material', [missing, badKey, both].some((x) => JSON.stringify(x).includes('BEGIN')), false);
  check(g, 'an empty file is a problem', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('empty.json', '') }).configured, false);
  check(g, 'a JSON array is a problem', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('arr.json', '[]') }).configured, false);
  check(g, 'JSON null is a problem, not a TypeError', inspectFcmConfig({ FCM_SERVICE_ACCOUNT_FILE: file('null.json', 'null') }).configured, false);
}

// ---- B ----------------------------------------------------------------------
{
  const g = 'B describe';
  const ok = resolvePushConfig({ FCM_SERVICE_ACCOUNT_FILE: GOOD_FILE });
  const d = describePushConfig(ok);
  check(g, 'ready when the credential is good', d.androidRing, 'ready');
  check(g, 'description is names and booleans only', JSON.stringify(d), '{"androidRing":"ready","fcm":{"configured":true,"source":"file"},"apns":{"configured":false},"problems":0}');
  check(g, 'nothing configured -> not_configured', describePushConfig(resolvePushConfig({})).androidRing, 'not_configured');
  const half = resolvePushConfig({ APNS_KEY_ID: 'K', APNS_TEAM_ID: 'T' });
  check(g, 'a half-configured APNs is named as a problem', half.problems.join('|'), 'APNs: set 2 of 4 variables; all four are needed');
  check(g, 'a full APNs set is configured', resolvePushConfig({ APNS_KEY_P8: 'x', APNS_KEY_ID: 'k', APNS_TEAM_ID: 't', APNS_TOPIC: 'p' }).apns.configured, true);
  const broken = describePushConfig(resolvePushConfig({ FCM_SERVICE_ACCOUNT_FILE: join(dir, 'gone.json') }));
  check(g, 'a broken credential reads as not_configured with a problem count', `${broken.androidRing}/${broken.problems}`, 'not_configured/1');
  check(g, 'the description never contains the secret values given to APNs', JSON.stringify(describePushConfig(resolvePushConfig({ APNS_KEY_P8: 'SECRETKEY', APNS_KEY_ID: 'KID', APNS_TEAM_ID: 'TID', APNS_TOPIC: 'TOPIC' }))).match(/SECRETKEY|KID|TID|TOPIC/), null);
}

// ---- C ----------------------------------------------------------------------
{
  const g = 'C sender reads the file';
  _resetFcmTokenCacheForTests();
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, init });
    if (url.endsWith('/token')) return { ok: true, status: 200, json: async () => ({ access_token: 'tok', expires_in: 3600 }), text: async () => '' };
    return { ok: true, status: 200, json: async () => ({ name: 'projects/proj/messages/1' }), text: async () => '' };
  };
  const saved = { f: process.env.FCM_SERVICE_ACCOUNT_FILE, j: process.env.FCM_SERVICE_ACCOUNT_JSON };
  delete process.env.FCM_SERVICE_ACCOUNT_JSON;
  process.env.FCM_SERVICE_ACCOUNT_FILE = file('c.json', JSON.stringify({ ...SA, token_uri: 'https://oauth.example/token' }));
  const payload = buildPush({ kind: 'message_ready', platform: 'android', deviceToken: 'dev', ref: 'r1' });
  const r = await sendFcm(payload, { fetchImpl });
  check(g, 'a send works from FCM_SERVICE_ACCOUNT_FILE alone', r.ok, true);
  check(g, 'it minted a token and then posted to the project', seen.map((s) => s.url).join(' '), 'https://oauth.example/token https://fcm.googleapis.com/v1/projects/proj/messages:send');
  process.env.FCM_SERVICE_ACCOUNT_FILE = join(dir, 'missing.json');
  _resetFcmTokenCacheForTests();
  let code = null; try { await sendFcm(payload, { fetchImpl }); } catch (e) { code = e.code; }
  check(g, 'an unreadable file fails the send with fcm_config_invalid, never a silent no-op', code, 'fcm_config_invalid');
  delete process.env.FCM_SERVICE_ACCOUNT_FILE;
  _resetFcmTokenCacheForTests();
  code = null; try { await sendFcm(payload, { fetchImpl }); } catch (e) { code = e.code; }
  check(g, 'with neither set it is still fcm_config_missing', code, 'fcm_config_missing');
  if (saved.f !== undefined) process.env.FCM_SERVICE_ACCOUNT_FILE = saved.f;
  if (saved.j !== undefined) process.env.FCM_SERVICE_ACCOUNT_JSON = saved.j;
  _resetFcmTokenCacheForTests();
}

// ---- D ----------------------------------------------------------------------
{
  const g = 'D api base';
  check(g, 'default is Google', fcmApiBase({}), 'https://fcm.googleapis.com');
  check(g, 'a stub is honoured in development', fcmApiBase({ NODE_ENV: 'development', FCM_API_BASE_URL: 'http://127.0.0.1:9999/x?y' }), 'http://127.0.0.1:9999');
  check(g, 'a stub is honoured in test', fcmApiBase({ NODE_ENV: 'test', FCM_API_BASE_URL: 'https://stub.example' }), 'https://stub.example');
  check(g, 'a stub is IGNORED in production', fcmApiBase({ NODE_ENV: 'production', FCM_API_BASE_URL: 'http://evil.example' }), 'https://fcm.googleapis.com');
  check(g, 'a stub is IGNORED when NODE_ENV is unset', fcmApiBase({ FCM_API_BASE_URL: 'http://evil.example' }), 'https://fcm.googleapis.com');
  check(g, 'a non-http scheme falls back to Google', fcmApiBase({ NODE_ENV: 'test', FCM_API_BASE_URL: 'file:///etc/passwd' }), 'https://fcm.googleapis.com');
  check(g, 'a garbage value falls back to Google', fcmApiBase({ NODE_ENV: 'test', FCM_API_BASE_URL: 'not a url' }), 'https://fcm.googleapis.com');
}

// ---- E ----------------------------------------------------------------------
{
  const g = 'E ringState';
  const ok = { ok: true }, quiet = { ok: false, code: 'gated_quiet_hours', message: 'blocked by day-part asleep' };
  const nocap = { ok: false, code: 'no_push_capability', advice: 'x' }, fail1 = { ok: false, code: 'fcm_send_failed', message: 'secret body' };
  check(g, 'no results -> no_devices', ringStateFrom([]), 'no_devices');
  check(g, 'not an array -> no_devices', ringStateFrom(undefined), 'no_devices');
  check(g, 'any ok -> rang', ringStateFrom([fail1, ok]), 'rang');
  check(g, 'all gated -> quiet_hours', ringStateFrom([quiet, quiet]), 'quiet_hours');
  check(g, 'all incapable -> no_push_capability', ringStateFrom([nocap]), 'no_push_capability');
  check(g, 'a send failure -> send_failed', ringStateFrom([fail1]), 'send_failed');
  check(g, 'mixed gated + failed -> send_failed (do not claim it was only quiet hours)', ringStateFrom([quiet, fail1]), 'send_failed');
  check(g, 'the result is a single plain word, never a message', ringStateFrom([fail1]).includes('secret'), false);
}

// ---- F ----------------------------------------------------------------------
{
  const g = 'F lan';
  // dotted quads are assembled, not written out: this suite is about the ranges, not about any real host
  const ip = (...o) => 'https://' + o.join('.');
  const lan = [ip(192, 168, 1, 20) + ':8443', ip(10, 0, 0, 5), ip(172, 16, 0, 1), ip(172, 31, 255, 1), ip(127, 0, 0, 1) + ':8443',
    ip(169, 254, 1, 1), 'https://meet.local', 'https://olive-pc', 'https://pc.lan', 'https://box.home.arpa', 'https://[::1]:8443', 'https://[fd12:3456::1]', 'https://[fe80::1]'];
  const wan = ['https://meet.example.com', ip(8, 8, 8, 8), ip(172, 32, 0, 1), ip(172, 15, 0, 1), ip(11, 0, 0, 1), 'https://[2001:db8::1]', ip(192, 169, 0, 1)];
  for (const u of lan) check(g, `${u} is LAN-only`, isLanOnlyHost(u), true);
  for (const u of wan) check(g, `${u} is reachable from anywhere`, isLanOnlyHost(u), false);
  check(g, 'a non-URL is not LAN-only (and does not throw)', isLanOnlyHost('not a url'), false);
}

// ---- G ----------------------------------------------------------------------
{
  const g = 'G call_cancelled';
  const p = buildPush({ kind: 'call_cancelled', platform: 'android', deviceToken: 'd', ref: 'sess1' });
  check(g, 'it has no banner at all (silent)', p.notification, null);
  check(g, 'it uses the calls channel without a full-screen intent', `${p.android.channelId}/${p.android.fullScreenIntent}`, 'calls/false');
  check(g, 'data is exactly kind, ref, v (no call handle needed)', JSON.stringify(Object.keys(p.data).sort()), '["kind","ref","v"]');
  check(g, 'it passes the audit and the send guard', auditPush(p).ok && sendGuard(p) === p, true);
  check(g, 'GENERIC declares it banner-less', GENERIC.call_cancelled, null);
  const wire = toFcmRequestBody(p).message;
  check(g, 'the FCM body is data-only', `${wire.notification === undefined}/${wire.data.kind}`, 'true/call_cancelled');
  const ios = buildPush({ kind: 'call_cancelled', platform: 'ios', deviceToken: 'd', ref: 'sess1' });
  check(g, 'on iOS it is a background push, not a VoIP push (no CallKit ring)', `${ios.apns.pushType}/${ios.apns.priority}`, 'background/5');
  check(g, '...and its APNs body has no alert', toApnsRequestBody(ios).aps.alert === undefined, true);
  check(g, 'every kind is still audit-clean', Object.keys(GENERIC).every((k) => auditPush(buildPush({ kind: k, platform: 'android', deviceToken: 't', ref: 'r', callRoomHandle: 'h' })).ok), true);
}

// ---- H ----------------------------------------------------------------------
{
  const g = 'H scheduler registry';
  check(g, 'every fast job is a registered job', FAST_JOBS.every((j) => JOB_NAMES.includes(j)), true);
  check(g, 'rematerialize runs before deliver-due (a message must be ready before it can be claimed)', JOB_NAMES.indexOf('rematerialize') < JOB_NAMES.indexOf('deliver-due'), true);
  check(g, 'the heavy jobs are NOT on the fast lane', ['reap-media', 'backup', 'health-alert', 'expiry-digest'].some((j) => FAST_JOBS.includes(j)), false);
  check(g, 'health-alert is still last (it must see the backup that just ran)', JOB_NAMES[JOB_NAMES.length - 1], 'health-alert');
}

rmSync(dir, { recursive: true, force: true });
let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
