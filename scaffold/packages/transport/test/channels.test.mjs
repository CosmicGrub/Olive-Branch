/**
 * packages/transport/src/channels.ts — the DYNAMIC routing decision for
 * §8.11.4's "silent device" problem (push vs. socket vs. SMS-to-adult vs.
 * unreachable, given real-time state). MASTERFILE §8.11.4.
 *
 * This file did not exist before v0.49.11 — channels.ts's only prior test
 * exposure was transitive, via packages/devices/test/postures.test.mjs
 * importing it alongside unrelated posture/tabletop/court-export coverage.
 * That gap is exactly how a real bug shipped unnoticed: route()/reachability()
 * independently re-derived a channel's SMS eligibility instead of reading it
 * from devices.ts's own CHANNELS, and 'web' — which devices.ts explicitly
 * declares has NO sms fallback — could still be routed/advised straight to
 * sms_to_adult. Section C below proves that bug is fixed, not just that the
 * happy path works.
 *
 * Same local check()/pass/fail convention as fcm.test.mjs/apns.test.mjs, this
 * package's own established pattern.
 */
import {
  PUSH_CHANNELS, SMS_ESCALATE_AFTER_MINUTES, route, senderStatus, auditStatus,
  STATUS_BANNED, ADULT_SMS, SMS_FORBIDDEN_TOKENS, auditAdultSms, socketPolicy,
  reachability,
} from '../src/channels.mjs';
import { CHANNELS, capability } from '../../devices/src/devices.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// A · PUSH_CHANNELS is derived, not redeclared ================================
{
  check('A derivation', 'PUSH_CHANNELS matches devices.ts CHANNELS exactly, channel-for-channel',
    PUSH_CHANNELS.slice().sort().join(','),
    CHANNELS.filter(c => c.push).map(c => c.channel).sort().join(','));
  check('A derivation', 'android_play is push-capable', PUSH_CHANNELS.includes('android_play'), 'true');
  check('A derivation', 'ios is push-capable', PUSH_CHANNELS.includes('ios'), 'true');
  check('A derivation', 'windows is push-capable', PUSH_CHANNELS.includes('windows'), 'true');
  check('A derivation', 'android_amazon is NOT push-capable', PUSH_CHANNELS.includes('android_amazon'), 'false');
  check('A derivation', 'android_bare is NOT push-capable', PUSH_CHANNELS.includes('android_bare'), 'false');
  check('A derivation', 'web is NOT push-capable', PUSH_CHANNELS.includes('web'), 'false');
}

// B · route() — the full cascade, one push-capable channel ====================
{
  const base = { channel: 'android_amazon', appForeground: false, socketConnected: false,
    adultNumberOnFile: true, minutesWaiting: 0 };

  check('B cascade', 'a push-capable channel always routes push, regardless of other state',
    route({ ...base, channel: 'android_play', appForeground: false, socketConnected: false,
      adultNumberOnFile: false, minutesWaiting: 0 }).route, 'push');
  check('B cascade', 'push short-circuits with an empty rejected list',
    route({ ...base, channel: 'ios' }).rejected.length, 0);

  check('B cascade', 'foreground + held socket routes socket',
    route({ ...base, appForeground: true, socketConnected: true }).route, 'socket');
  check('B cascade', 'a held socket while backgrounded does not route socket',
    route({ ...base, appForeground: false, socketConnected: true }).route !== 'socket', 'true');
  check('B cascade', 'and says why: not foregrounded',
    route({ ...base, appForeground: false, socketConnected: true })
      .rejected.find(r => r.route === 'socket').because, 'app is not in the foreground');
  check('B cascade', 'no socket held at all says why: no socket held',
    route({ ...base, appForeground: true, socketConnected: false })
      .rejected.find(r => r.route === 'socket').because, 'no socket held');

  check('B cascade', 'sms-eligible, adult on file, past the escalation minute: sms_to_adult',
    route({ ...base, minutesWaiting: SMS_ESCALATE_AFTER_MINUTES }).route, 'sms_to_adult');
  check('B cascade', 'one minute short of escalation: not yet',
    route({ ...base, minutesWaiting: SMS_ESCALATE_AFTER_MINUTES - 1 }).route, 'none');
  check('B cascade', 'no adult number on file: none, unreachable',
    route({ ...base, adultNumberOnFile: false, minutesWaiting: 500 }).route, 'none');
  check('B cascade', 'and unreachable is set true',
    route({ ...base, adultNumberOnFile: false, minutesWaiting: 500 }).unreachable, 'true');
  check('B cascade', 'the fully-rejected case records all three attempts',
    route(base).rejected.map(r => r.route).join(','), 'push,socket,sms_to_adult');
  check('B cascade', 'a resolved route is never marked unreachable',
    route({ ...base, appForeground: true, socketConnected: true }).unreachable, 'false');
}

// C · the web/SMS bug — route() must NOT offer SMS to a channel devices.ts ====
//     never declared eligible for it. This is the fix v0.49.11 makes real.
{
  const webBase = { channel: 'web', appForeground: false, socketConnected: false,
    adultNumberOnFile: true, minutesWaiting: 500 };

  check('C web/sms bug', "devices.ts declares web's fallback as socket-only, never sms",
    capability('web').fallback, 'foreground_socket');
  check('C web/sms bug', 'a web device with an adult on file and a long wait still does NOT escalate to sms',
    route(webBase).route, 'none');
  check('C web/sms bug', 'and is marked unreachable rather than silently fine',
    route(webBase).unreachable, 'true');
  check('C web/sms bug', "the sms rejection reason names web's own missing fallback, not a generic wait reason",
    route(webBase).rejected.find(r => r.route === 'sms_to_adult').because,
    'web has no SMS fallback declared');

  // The two channels devices.ts DOES grant SMS eligibility to must still get it.
  check('C web/sms bug', 'android_amazon (foreground_socket_and_sms) still escalates to sms',
    route({ ...webBase, channel: 'android_amazon' }).route, 'sms_to_adult');
  check('C web/sms bug', 'android_bare (foreground_socket_and_sms) still escalates to sms',
    route({ ...webBase, channel: 'android_bare' }).route, 'sms_to_adult');
}

// D · senderStatus() — what the sender is told, per route =====================
{
  const childName = 'Ivy';
  const s1 = senderStatus(route({ channel: 'ios', appForeground: false, socketConnected: false,
    adultNumberOnFile: false, minutesWaiting: 0 }), childName);
  check('D sender', 'push route: delivered, not actionable', `${s1.delivered},${s1.actionable}`, 'true,false');

  const s2 = senderStatus(route({ channel: 'android_amazon', appForeground: true, socketConnected: true,
    adultNumberOnFile: false, minutesWaiting: 0 }), childName);
  check('D sender', 'socket route: delivered, names her having it now',
    `${s2.delivered},${/has it now/.test(s2.line)}`, 'true,true');

  const s3 = senderStatus(route({ channel: 'android_amazon', appForeground: false, socketConnected: false,
    adultNumberOnFile: true, minutesWaiting: 500 }), childName);
  check('D sender', 'sms_to_adult route: delivered, mentions the grown-up',
    `${s3.delivered},${/grown-up/.test(s3.line)}`, 'true,true');

  const s4 = senderStatus(route({ channel: 'android_amazon', appForeground: false, socketConnected: false,
    adultNumberOnFile: false, minutesWaiting: 0 }), childName);
  check('D sender', 'none route: not delivered, actionable',
    `${s4.delivered},${s4.actionable}`, 'false,true');

  const s5 = senderStatus(route({ channel: 'web', appForeground: false, socketConnected: false,
    adultNumberOnFile: true, minutesWaiting: 500 }), childName);
  check('D sender', 'the web/sms-bug case: not delivered, actionable (never falsely claims delivery)',
    `${s5.delivered},${s5.actionable}`, 'false,true');
}

// E · auditStatus() — banned words only forbidden when NOT actually delivered =
{
  check('E audit', 'a true delivered claim passes',
    auditStatus({ delivered: true, actionable: false, line: 'Sent to her tablet.' }).ok, 'true');
  check('E audit', 'a false claim using a banned word fails',
    auditStatus({ delivered: false, actionable: true, line: 'She has been notified.' }).ok, 'false');
  check('E audit', 'and names the offending word',
    auditStatus({ delivered: false, actionable: true, line: 'She has been notified.' }).found.join(),
    'notified');
  check('E audit', 'STATUS_BANNED has real entries', STATUS_BANNED.length > 0, 'true');
}

// F · the adult SMS — content-blind by construction ============================
{
  check('F sms content', 'the shipped ADULT_SMS text itself passes its own audit',
    auditAdultSms(ADULT_SMS).ok, 'true');
  check('F sms content', 'names nobody, says nothing about content',
    auditAdultSms(ADULT_SMS).ok, 'true');
  check('F sms content', 'a name leak is caught', auditAdultSms('A message from Dad is waiting.').ok, 'false');
  check('F sms content', 'a content-type leak is caught', auditAdultSms('New photo waiting.').found.includes('photo'), 'true');
  check('F sms content', 'SMS_FORBIDDEN_TOKENS has real entries', SMS_FORBIDDEN_TOKENS.length > 0, 'true');
  check('F sms content', 'ADULT_SMS stays short — a text, not a paragraph', ADULT_SMS.length < 60, 'true');
}

// G · socketPolicy() — foreground-only, real backoff =============================
{
  const p = socketPolicy();
  check('G socket policy', 'held in foreground', p.holdInForeground, 'true');
  check('G socket policy', 'never held in background', p.holdInBackground, 'false');
  check('G socket policy', 'backoff is a real increasing sequence',
    p.reconnectBackoffMs.every((v, i) => i === 0 || v >= p.reconnectBackoffMs[i - 1]), 'true');
  check('G socket policy', 'the note explains why, not just what', p.note.length > 20, 'true');
}

// H · reachability() — guardian-settings copy, same fixed eligibility as route() =
{
  check('H reachability', 'a push channel can alert even when closed',
    reachability('ios').canAlert, 'true');
  check('H reachability', 'and the line says so', /even when Olive is closed/.test(reachability('ios').line), 'true');

  check('H reachability', 'FireOS cannot alert when closed', reachability('android_amazon').canAlert, 'false');
  check('H reachability', 'but its line still mentions texting the grown-up (sms-eligible)',
    /text the grown-up/.test(reachability('android_amazon').line), 'true');

  check('H reachability', 'web cannot alert when closed either', reachability('web').canAlert, 'false');
  check('H reachability', 'but its line must NOT promise sms — it is not eligible (the v0.49.11 fix)',
    /text the grown-up/.test(reachability('web').line), 'false');
  check('H reachability', "web's line still tells the truth about foreground-only delivery",
    /only arrive while Olive is open/.test(reachability('web').line), 'true');

  check('H reachability', 'reachability().channel echoes the input', reachability('windows').channel, 'windows');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
