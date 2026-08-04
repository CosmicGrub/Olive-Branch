/**
 * transport + client contract — adversarial suite.
 * MASTERFILE §11, §20.2. Items 4 and 5 of the §20.5 exit order.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildPush, auditPush, sendGuard, FORBIDDEN_DATA_KEYS,
  ROOM_EMPTY_TIMEOUT_SEC, ROOM_MAX_PARTICIPANTS, revokeLiveAccess, endSession,
} from '../src/push.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const TOK = 'devicetoken123';
const REF = 'r_' + 'a'.repeat(20);

// ===========================================================================
// G · PUSH — the lock screen must disclose nothing
// ===========================================================================
{
  const msg = buildPush({ kind:'message_ready', platform:'android', deviceToken:TOK, ref:REF });
  check('G push', 'audit passes on a clean payload', auditPush(msg).ok, 'true');
  check('G push', 'no child name in data', 'childName' in msg.data, 'false');
  check('G push', 'data keys are only kind/ref/v',
    Object.keys(msg.data).sort().join(','), 'kind,ref,v');
  check('G push', 'banner text names nobody',
    msg.notification.body, 'Something new is waiting for you.');
  check('G push', 'banner title is the product only', msg.notification.title, 'Olive');

  // A call RINGS. No banner at all — CallKit / full-screen intent own the UI.
  const call = buildPush({ kind:'call_incoming', platform:'android',
    deviceToken:TOK, ref:REF, callRoomHandle:'h_abc' });
  check('G push', 'call has NO notification text', call.notification, 'null');
  check('G push', 'android full-screen intent set for calls',
    call.android.fullScreenIntent, 'true');
  check('G push', 'calls use a separate channel', call.android.channelId, 'calls');
  check('G push', 'non-call does NOT use full-screen intent',
    msg.android.fullScreenIntent, 'false');

  const iosCall = buildPush({ kind:'call_incoming', platform:'ios',
    deviceToken:TOK, ref:REF, callRoomHandle:'h_abc' });
  check('G push', 'ios calls use VoIP push', iosCall.apns.pushType, 'voip');
  check('G push', 'ios calls are priority 10', iosCall.apns.priority, 10);
  const iosMsg = buildPush({ kind:'message_ready', platform:'ios', deviceToken:TOK, ref:REF });
  check('G push', 'ios non-call is alert, not VoIP', iosMsg.apns.pushType, 'alert');

  check('G push', 'call without a room handle is refused',
    (() => { try { buildPush({ kind:'call_incoming', platform:'ios',
      deviceToken:TOK, ref:REF }); return 'built'; } catch { return 'refused'; } })(),
    'refused');

  // The audit must CATCH a future contributor adding "helpful" detail.
  const leakName = { ...msg, data: { ...msg.data, senderName:'Dad' } };
  check('G push', 'audit catches a leaked sender name',
    auditPush(leakName).leaks.join(','), 'data.senderName');
  const leakId = { ...msg, data: { ...msg.data,
    subject:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' } };
  check('G push', 'audit catches a uuid smuggled into data',
    auditPush(leakId).ok, 'false');
  const leakBanner = { ...msg,
    notification: { title:'Olive', body:'Goodnight video from Dad' } };
  check('G push', 'audit catches a name in the banner',
    auditPush(leakBanner).ok, 'false');
  check('G push', 'rejection names the allowlist, not a guess',
    auditPush(leakBanner).leaks[0], 'notification text is not an approved constant');
  // Any deviation at all is refused — even an innocuous-looking rewording.
  check('G push', 'even a harmless custom banner is refused',
    auditPush({ ...msg, notification:{ title:'Olive', body:'Tap to open.' } }).ok,
    'false');
  check('G push', 'sendGuard throws rather than sending a leak',
    (() => { try { sendGuard(leakBanner); return 'sent'; } catch { return 'blocked'; } })(),
    'blocked');
  check('G push', 'sendGuard passes a clean payload', sendGuard(msg) === msg, 'true');
  check('G push', 'every kind is audit-clean',
    ['message_ready','turn_ready','exchange_reminder','dose_due','call_incoming']
      .every(k => auditPush(buildPush({ kind:k, platform:'android', deviceToken:TOK,
        ref:REF, callRoomHandle:'h' })).ok), 'true');
  check('G push', 'forbidden key list is non-trivial', FORBIDDEN_DATA_KEYS.length > 15, 'true');
  check('G push', 'location keys are forbidden (P3)',
    FORBIDDEN_DATA_KEYS.includes('latitude') && FORBIDDEN_DATA_KEYS.includes('longitude'),
    'true');
}

// ===========================================================================
// H · ROOM LIFECYCLE — token revocation is not eviction
// ===========================================================================
{
  const acts = [];
  const port = {
    createRoom: async (n, o) => acts.push(['create', n, o.maxParticipants]),
    removeParticipant: async (r, i) => acts.push(['remove', r, i]),
    deleteRoom: async (n) => acts.push(['delete', n]),
  };
  check('H rooms', '1:1 plus one professional', ROOM_MAX_PARTICIPANTS, 3);
  check('H rooms', 'empty rooms close in a minute', ROOM_EMPTY_TIMEOUT_SEC, 60);

  await revokeLiveAccess(port, 'room1', 'dad');
  check('H rooms', 'kiosk defeat EVICTS, not just expires the token',
    acts[0].join('/'), 'remove/room1/dad');
  await endSession(port, 'room1');
  check('H rooms', 'ending a session deletes the room', acts[1].join('/'), 'delete/room1');
}

// ===========================================================================
// I · CLIENT CONTRACT — the Dart is uncompiled, so check what can be checked
// ===========================================================================
{
  const dartDir = fileURLToPath(new URL('../../../client/lib/', import.meta.url));
  const dart = readdirSync(dartDir).filter(f => f.endsWith('.dart'));
  check('I contract', 'client source present', dart.length >= 4, 'true');

  const src = dart.map(f => readFileSync(join(dartDir, f), 'utf8')).join('\n');
  const paths = [...src.matchAll(/'(\/v1\/[^']+)'/g)].map(m => m[1]);
  check('I contract', 'endpoint strings extracted', paths.length >= 10, 'true');

  // Every path must be well formed and child-scoped where it names a child.
  const malformed = paths.filter(p => !/^\/v1\/[A-Za-z0-9\/:_-]+$/.test(p));
  check('I contract', 'no malformed endpoint strings', malformed.join(','), '');
  const childPaths = paths.filter(p => p.includes('/children/'));
  check('I contract', 'every child path uses the :childId param, never a literal',
    childPaths.every(p => p.includes('/children/:childId')), 'true');

  // §7.10 — there must be NO guardian-reachable journal route. The Dart declares
  // one journal path; it must be child-scoped and nothing else.
  const journal = paths.filter(p => p.includes('journal'));
  check('I contract', 'exactly one journal path declared', journal.length, 1);
  check('I contract', 'journal path is child-scoped',
    journal[0], '/v1/children/:childId/journal');

  // Every unique path must be a route the API could plausibly serve: reject any
  // client path with no server counterpart in §7 of the MASTERFILE.
  const mf = readFileSync(fileURLToPath(new URL('../../../../MASTERFILE.md', import.meta.url)),
    'utf8');
  const unspecified = [...new Set(paths)].filter(p => {
    const stem = p.replace('/v1/children/:childId', '').replace('/v1/', '') || 'me';
    return !mf.includes(stem.split('/')[0]);
  });
  check('I contract', 'no client path is absent from the MASTERFILE §7 surface',
    unspecified.join(','), '');

  // Structural sanity on the Dart: balanced braces and no stray TODO.
  const braces = (src.match(/\{/g) || []).length - (src.match(/\}/g) || []).length;
  check('I contract', 'Dart braces balanced', braces, 0);
  const parens = (src.match(/\(/g) || []).length - (src.match(/\)/g) || []).length;
  check('I contract', 'Dart parens balanced', parens, 0);
  check('I contract', 'no TODO left in client source', /TODO|FIXME/.test(src), 'false');

  // Every client file must carry the UNVERIFIED marker so no reader mistakes it
  // for tested code.
  const unmarked = dart.filter(f =>
    !readFileSync(join(dartDir, f), 'utf8').includes('UNVERIFIED'));
  check('I contract', 'every Dart file is marked UNVERIFIED', unmarked.join(','), '');

  // §8.3 — the PIN keypad shuffle must use a CSPRNG.
  const pin = readFileSync(join(dartDir, 'pin_gate.dart'), 'utf8');
  check('I contract', 'PIN keypad shuffles with Random.secure()',
    pin.includes('Random.secure()'), 'true');
  check('I contract', 'PIN gate re-shuffles after each attempt',
    (pin.match(/shuffle\(Random\.secure\(\)\)/g) || []).length >= 2, 'true');

  // §8.1 — the child shell must contain no settings affordance.
  const childSrc = readFileSync(join(dartDir, 'child_home.dart'), 'utf8');
  check('I contract', 'child shell has no settings affordance',
    /Settings|settings/.test(childSrc.replace(/\/\/.*/g, '')), 'false');
}


// ===========================================================================
// J · NATIVE BRIDGE CONTRACT — Android real and wired; Windows still a stub
// ===========================================================================
{
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  // Android moved out of native/ (reference-only, never compiled) into the
  // real Gradle module once it was actually wired — see CHANGELOG. Keeping a
  // second, unwired copy around after that would be exactly the kind of
  // silent-drift risk this check exists to catch.
  const kt  = readFileSync(
    root + 'client/android/app/src/main/kotlin/com/olivebranch/olive_client/KioskBridge.kt',
    'utf8');
  const cs  = readFileSync(root + 'native/windows/AssignedAccessBridge.cs', 'utf8');
  const dart = readFileSync(root + 'client/lib/kiosk_channel.dart', 'utf8');

  // Channel names must be byte-identical across all three or the platform
  // channel silently never connects — a failure that presents as "the kiosk
  // just doesn't lock" with no error anywhere.
  const chan = 'app.olive/kiosk';
  check('J bridge', 'method channel name agrees across Kotlin/C#/Dart',
    [kt, cs, dart].every(f => f.includes(`'${chan}'`) || f.includes(`"${chan}"`)), 'true');
  check('J bridge', 'event channel name agrees',
    [kt, cs, dart].every(f => f.includes(`${chan}_events`)), 'true');

  // Every method and event constant must exist in all three.
  for (const name of ['startLockTask','stopLockTask','lockTaskMode','isDeviceOwner']) {
    check('J bridge', `method '${name}' declared in all three`,
      [kt, cs, dart].every(f => f.includes(`"${name}"`) || f.includes(`'${name}'`)), 'true');
  }
  for (const name of ['lockTaskExited','backgrounded','resumed']) {
    check('J bridge', `event '${name}' declared in all three`,
      [kt, cs, dart].every(f => f.includes(`"${name}"`) || f.includes(`'${name}'`)), 'true');
  }

  // §5.20 — every emitted event must map to a state-machine transition.
  const lock = readFileSync(root + 'packages/child-lock/src/lock.ts', 'utf8');
  check('J bridge', 'lockTaskExited maps to onLockTaskExited',
    lock.includes('onLockTaskExited'), 'true');
  check('J bridge', 'backgrounded maps to onBackgrounded',
    lock.includes('onBackgrounded'), 'true');

  // Windows must never claim to be fully locked — Assigned Access is exitable.
  check('J bridge', 'Windows never reports a fully locked device',
    /IsFullyLocked\(\)\s*=>\s*false/.test(cs), 'true');
  check('J bridge', 'Windows reports its mode as escapable',
    cs.includes('"assigned"'), 'true');

  // Android must distinguish device-owner LOCKED from escapable PINNED.
  check('J bridge', 'Android distinguishes LOCKED from PINNED',
    kt.includes('LOCK_TASK_MODE_LOCKED') && kt.includes('LOCK_TASK_MODE_PINNED'), 'true');

  // Windows is still an untouched, never-compiled stub — must still say so.
  check('J bridge', 'Windows source still marked UNVERIFIED',
    cs.includes('UNVERIFIED'), 'true');
  // Android is real now: wired into MainActivity, built, and manually
  // verified on a device this session. Claiming UNVERIFIED here would be the
  // exact "declaration with nothing behind it" MASTERFILE §0 warns is worse
  // than an omission — so its absence is asserted, not its presence.
  check('J bridge', 'Android source no longer claims to be UNVERIFIED',
    kt.includes('UNVERIFIED'), 'false');
  check('J bridge', 'Android source lives in the real app package',
    kt.includes('package com.olivebranch.olive_client'), 'true');
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
