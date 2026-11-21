/**
 * Notification payload contract (ISS-107): no notification, on any platform, built by the server OR by the client, may
 * carry medicine, allergy, condition or dose text, and every one that has any text at all is private on a lock screen.
 *
 * A push is a pointer, not a message (MASTERFILE section 11). The server builds it in packages/transport/src/push.ts and
 * sends it through fcm.ts / apns.ts; the phone builds its own notifications in client/android (OliveNotifications.kt, with
 * its words in strings.xml). This suite reads BOTH sides:
 *
 *   A. server: every push kind on every platform. Data keys come from a closed list; no value or text looks like health
 *      content; the text is one of the approved constants; fields smuggled in through the input are never copied out.
 *   B. the wire: the FCM v1 body and the APNs body built from each payload carry none of it either, and an FCM body with
 *      any visible text says visibility PRIVATE.
 *   C. client: every string the notification builder can show is free of health content, the builder takes its words only
 *      from strings.xml (no literal, no concatenation, no push field), and every channel and notification it builds is
 *      VISIBILITY_PRIVATE.
 *   D. the vocabulary detector itself: positive and negative vectors, so a silent detector cannot pass this suite.
 *
 * usage: node tools/test/notification_payload_contract.test.mjs   (after `npm run build`)
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildPush, auditPush, GENERIC } from '../../packages/transport/src/push.mjs';
import { toFcmRequestBody } from '../../packages/transport/src/fcm.mjs';
import { toApnsRequestBody } from '../../packages/transport/src/apns.mjs';

let pass = 0, fail = 0;
const check = (name, ok, detail = '') => {
  if (ok) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name}${detail ? `\n        ${detail}` : ''}`); }
};

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const rd = (p) => readFileSync(join(ROOT, p), 'utf8').replace(/\r\n/g, '\n');

// ---------------------------------------------------------------- the detector
// Health content: a medicine, an allergy, a condition, or a dose. Words and shapes, case-insensitive. Deliberately wide.
const HEALTH_WORDS = [
  'medicine', 'medicines', 'medication', 'medications', 'meds', 'pill', 'pills', 'tablet', 'tablets', 'capsule', 'inhaler',
  'puff', 'puffs', 'dose', 'doses', 'dosage', 'prescription', 'allergy', 'allergies', 'allergic', 'anaphylaxis', 'epipen',
  'condition', 'conditions', 'diagnosis', 'asthma', 'diabetes', 'diabetic', 'insulin', 'epilepsy', 'seizure', 'adhd',
  'autism', 'cancer', 'peanut', 'peanuts', 'ibuprofen', 'paracetamol', 'acetaminophen', 'cetirizine', 'albuterol',
  'methylphenidate', 'amoxicillin', 'symptom', 'symptoms', 'fever',
];
const HEALTH_WORD_RE = new RegExp(`\\b(?:${HEALTH_WORDS.join('|')})\\b`, 'i');
const DOSE_SHAPE_RE = /(?<![\w.])(?:\d+(?:[.,]\d+)?|a|an|one|two|three|half)\s*-?\s*(?:mg|mcg|ug|g|ml|cc|iu|units?|tablets?|pills?|puffs?|drops?|tsp|tbsp)\b|\/\s*kg\b|\bevery\s+\d+\s*(?:hours?|hrs?|h)\b/i;
const healthHits = (s) => {
  const hits = [];
  const w = HEALTH_WORD_RE.exec(s); if (w) hits.push(`word:${w[0]}`);
  const d = DOSE_SHAPE_RE.exec(s); if (d) hits.push(`dose:${d[0]}`);
  return hits;
};

// D. the detector works (positive and negative vectors).
for (const bad of ['Time for the 5 mg tablet', 'Albuterol inhaler due', 'Peanut allergy reminder', 'dose due', 'take 2 puffs',
  'asthma plan', 'every 4 hours', '10mg/kg', 'her medication', 'EpiPen']) {
  check(`detector flags: ${bad}`, healthHits(bad).length > 0);
}
for (const ok of ['Something new is waiting for you.', "It's your turn.", 'A reminder is ready.', 'Someone would like to talk.', 'Olive',
  'Calls', 'A quiet knock when a grown-up would like to talk.', 'A gentle note that something new is waiting.']) {
  check(`detector passes: ${ok}`, healthHits(ok).length === 0, healthHits(ok).join(','));
}

// ---------------------------------------------------------------- A. the server builder
const KINDS = ['call_incoming', 'call_cancelled', 'message_ready', 'turn_ready', 'exchange_reminder', 'dose_due'];
const ALLOWED_DATA_KEYS = new Set(['kind', 'ref', 'v', 'callHandle']);
const REF = 'r_0123456789abcdef';
const HANDLE = 'h_0123456789abcdef';
const flat = (o) => JSON.stringify(o);

let payloads = 0;
for (const platform of ['android', 'ios']) {
  for (const kind of KINDS) {
    const p = buildPush({ kind, platform, deviceToken: 'device-token-1', ref: REF, callRoomHandle: kind === 'call_incoming' ? HANDLE : undefined });
    payloads++;
    const tag = `${platform}/${kind}`;
    check(`A ${tag}: data keys are only ${[...ALLOWED_DATA_KEYS].join('/')}`, Object.keys(p.data).every((k) => ALLOWED_DATA_KEYS.has(k)), Object.keys(p.data).join(','));
    check(`A ${tag}: no health text anywhere in the payload`, healthHits(flat(p)).length === 0, healthHits(flat(p)).join(','));
    check(`A ${tag}: the repo's own audit passes`, auditPush(p).ok === true);
    if (p.notification) {
      const approved = Object.values(GENERIC).filter(Boolean).some((a) => a.title === p.notification.title && a.body === p.notification.body);
      check(`A ${tag}: visible text is an approved generic constant`, approved);
    } else {
      check(`A ${tag}: no visible text at all`, kind === 'call_incoming' || kind === 'call_cancelled');
    }
  }
}
check('A all 12 kind x platform payloads were built', payloads === 12, String(payloads));

// Fields a careless caller might pass must never be copied into the payload.
{
  const dirty = buildPush({
    kind: 'dose_due', platform: 'android', deviceToken: 'device-token-1', ref: REF,
    medicationName: 'Albuterol inhaler', allergy: 'Peanuts', condition: 'Asthma', doseText: '2 puffs, 5 mg', body: 'Time for the Albuterol',
    title: 'Ivy: medicine', notification: { title: 'Albuterol', body: '5 mg now' },
  });
  check('A extra input fields (medicine, allergy, condition, dose, body, title) never reach the payload', healthHits(flat(dirty)).length === 0 && !/Ivy|Albuterol|Peanut/.test(flat(dirty)), flat(dirty));
}

// The audit is a real lock: a payload that DOES carry health text is refused.
{
  const base = buildPush({ kind: 'dose_due', platform: 'android', deviceToken: 'device-token-1', ref: REF });
  check('A the audit refuses a hand-built payload with medicine text', auditPush({ ...base, notification: { title: 'Olive', body: 'Albuterol 2 puffs now' } }).ok === false);
  check('A the audit refuses a medication data key', auditPush({ ...base, data: { ...base.data, medication: 'Albuterol' } }).ok === false);
}

// ---------------------------------------------------------------- B. the wire
for (const kind of KINDS) {
  const pa = buildPush({ kind, platform: 'android', deviceToken: 'device-token-1', ref: REF, callRoomHandle: kind === 'call_incoming' ? HANDLE : undefined });
  const fcm = toFcmRequestBody(pa);
  check(`B fcm/${kind}: wire body carries no health text`, healthHits(flat(fcm)).length === 0, healthHits(flat(fcm)).join(','));
  if (fcm.message.notification) {
    check(`B fcm/${kind}: visible text means android.notification.visibility is PRIVATE`, fcm.message.android?.notification?.visibility === 'PRIVATE', flat(fcm.message.android));
  } else {
    check(`B fcm/${kind}: data-only message has no text to hide`, fcm.message.android?.notification === undefined);
  }
  const pi = buildPush({ kind, platform: 'ios', deviceToken: 'device-token-1', ref: REF, callRoomHandle: kind === 'call_incoming' ? HANDLE : undefined });
  const apns = toApnsRequestBody(pi);
  check(`B apns/${kind}: wire body carries no health text`, healthHits(flat(apns)).length === 0, healthHits(flat(apns)).join(','));
}

// ---------------------------------------------------------------- C. the client builder (Android)
const KT = 'scaffold/client/android/app/src/main/kotlin/com/olivebranch/olive_client';
const ktPath = (f) => `${KT}/${f}`.replace(/^scaffold\//, '');
const kotlin = rd(ktPath('OliveNotifications.kt'));
const receiver = rd(ktPath('OlivePushReceiver.kt'));
const strings = rd('client/android/app/src/main/res/values/strings.xml');
const code = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const kt = code(kotlin);

// every olive_* string the builder can show
const oliveStrings = [...strings.matchAll(/<string name="(olive_[a-z_]+)"[^>]*>([^<]*)<\/string>/g)].map((m) => ({ name: m[1], text: m[2] }));
check('C strings.xml has the notification strings (channel names/descriptions and the ring)', oliveStrings.length >= 6, String(oliveStrings.length));
for (const { name, text } of oliveStrings) {
  if (!/^olive_(channel|ring)/.test(name)) continue;
  check(`C ${name}: no health text`, healthHits(text).length === 0, `${text} -> ${healthHits(text).join(',')}`);
}

// the builder takes its words only from string resources: no quoted literal or concatenation in a title/text/name/description call
const textCalls = [...kt.matchAll(/\.(setContentTitle|setContentText|setSubText|setTicker)\((?:[^()]|\([^()]*\))*\)/g)];
check('C the ring sets a title and a text', textCalls.length >= 2, String(textCalls.length));
for (const m of textCalls) {
  check(`C ${m[1]} comes from a string resource only`, /^\.\w+\(context\.getString\(R\.string\.olive_[a-z_]+\)\)$/.test(m[0]), m[0]);
}
check('C NotificationChannel names and descriptions come from string resources', (kt.match(/context\.getString\(R\.string\.olive_channel_[a-z_]+\)/g) || []).length === 4);
check('C no string literal is ever passed to a Notification builder call', !/\.set(?:ContentTitle|ContentText|SubText|Ticker|BigText|Style)\(\s*"/.test(kt));
check('C no BigTextStyle / InboxStyle / MessagingStyle (they carry content)', !/BigTextStyle|InboxStyle|MessagingStyle|setStyle\(/.test(kt));

// lock-screen visibility: every channel and the notification are PRIVATE, none is PUBLIC
const lockVis = [...kt.matchAll(/(?:lockscreenVisibility\s*=|\.setVisibility\()\s*Notification\.(VISIBILITY_\w+)/g)].map((m) => m[1]);
check('C there are three visibility settings (two channels, the ring)', lockVis.length === 3, lockVis.join(','));
check('C every one is VISIBILITY_PRIVATE', lockVis.every((v) => v === 'VISIBILITY_PRIVATE'), lockVis.join(','));
check('C VISIBILITY_PUBLIC appears nowhere in the builder code', !/VISIBILITY_PUBLIC/.test(kt));

// the receiver reads only what a content-free push carries
const extras = [...code(receiver).matchAll(/\bget\w*\(\s*(OliveNotifications\.EXTRA_\w+|"[^"]*")\s*\)/g)].map((m) => m[1]);
check('C the receiver reads only kind and ref from a push', extras.length >= 1 && extras.every((k) => k === 'OliveNotifications.EXTRA_KIND' || k === 'OliveNotifications.EXTRA_REF'), extras.join(','));

// ---------------------------------------------------------------- the push.ts declaration of intent matches
const pushTs = rd('packages/transport/src/push.ts');
check('A push.ts still declares no health key may ride in data (medication is on the forbidden list)', /'medication'/.test(pushTs));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
