/**
 * MASTERFILE §11 — the single dispatch point a PushPayload leaves this
 * codebase through. Everything upstream (buildPush/auditPush/sendGuard in
 * push.ts, the device_token table in db/migrations/0008) exists to feed
 * this file; everything downstream (fcm.ts/apns.ts) exists to be called only
 * from here.
 *
 * THE ONE RULE: sendGuard() runs on every payload, no exceptions, before it
 * is ever handed to fcm.ts or apns.ts. That is the one call standing between
 * this code and a lock-screen family-structure disclosure — see push.ts's
 * own header. This file never calls buildPush() without immediately calling
 * sendGuard() on the result.
 *
 * v0.49.11 — §8.11.4 channel awareness is now real here, closing this
 * codebase's own top-ranked prior-audit finding. Before this pass,
 * `notifyDevices()` attempted FCM against EVERY `platform:'android'` row
 * unconditionally — exactly the "constructed, dispatched, and silently
 * discarded" failure mode `devices.ts`'s own §8.11.4 header describes for a
 * FireOS tablet with no Google Play Services. Now: `admitDevice()`
 * (devices.ts) runs per device before a send is attempted; a device whose
 * channel is known to be push-incapable is skipped, not fired into the
 * void, and the result carries `channelAdvice()`'s guardian-facing copy so
 * a future caller has it ready. See the per-device loop below for the exact
 * channel-resolution rule and its honesty caveat.
 */
import type pg from 'pg';
import { buildPush, sendGuard, type PushInput, type PushPayload, type PushKind } from './push.ts';
import { sendFcm } from './fcm.ts';
import { sendApns } from './apns.ts';
import {
  deviceTokensFor, removeDeviceTokenSystem,
  type DeviceOwner, type DeviceTokenRow,
} from '../../db/src/pool.ts';
import { type Channel, admitDevice, channelAdvice } from '../../devices/src/devices.ts';

export interface NotifyInput {
  kind: PushKind;
  /** Opaque ref the client resolves post-unlock. Never content. */
  ref: string;
  /** call_incoming only. */
  callRoomHandle?: string;
  collapseKey?: string;
}

export interface DeviceSendResult {
  deviceTokenId: string;
  platform: 'android' | 'ios';
  ok: boolean;
  /** Present only when ok:false — one of buildPush/sendGuard/fcm/apns's own
   * thrown `.code`s, e.g. 'fcm_config_missing', 'apns_send_failed'. */
  code?: string;
  /**
   * Present only when ok:false — `String(e.message)` from whichever of
   * buildPush/sendGuard/fcm.ts/apns.ts threw. NOT REDACTED: fcm.ts's own
   * `fcm_send_failed`/`fcm_oauth_failed` and apns.ts's own
   * `apns_send_failed` embed the third party's raw response text verbatim
   * (see each file's own `safeText()`/response-body handling) — genuinely
   * useful for server-side logs and a system-role caller debugging a send
   * failure. `notifyDevices()` gained its first real API-facing caller in
   * v0.49.33 — `POST /v1/children/:childId/calls` (server/routes.mjs) —
   * which correctly follows the rule below rather than leaking this field.
   *
   * THIS IS DELIBERATELY NOT SAFE TO RETURN VERBATIM IN AN HTTP RESPONSE.
   * The real caller above proves the rule works in practice: it derives
   * only a boolean (`rang = pushResults.some(r => r.ok)`) and serializes
   * THAT, never `results`/`results[].message` themselves. `code` above
   * remains the already-generalized, safe-to-expose signal any FUTURE
   * client-facing surface should reach for instead, should one ever need
   * more than a bare boolean.
   */
  message?: string;
  /** True when the device's row was reaped because the platform told us the
   * token is permanently dead (see fcm.ts/apns.ts's `deviceGone`). */
  pruned?: boolean;
  /**
   * Present only when the device was skipped for lacking push capability
   * (`code: 'no_push_capability'`) — `channelAdvice()`'s guardian-facing
   * copy (devices.ts), ready for whatever future caller surfaces
   * `notifyDevices()`'s results to a client. `POST /v1/children/:childId/
   * calls` (v0.49.33, see above) is the first such caller, and — same as
   * `message` above — does not surface this field either, only the derived
   * `rang` boolean; this field stays ready for whatever future surface
   * actually needs the guardian-facing copy, not invented a consumer for
   * here.
   */
  advice?: string;
}

/**
 * Test-only injection seam. Every field defaults to the REAL function this
 * file otherwise calls unconditionally — a caller that passes nothing gets
 * exactly the original, non-overridable behavior. Exists ONLY because a
 * black-box test cannot otherwise prove two of this file's own load-bearing
 * claims against a live send: (1) that sendGuard() actually runs and blocks
 * a leaky payload before fcm.ts/apns.ts ever see it — buildPush() only ever
 * produces audit-clean payloads for real kinds, so nothing short of
 * substituting buildPush() can construct the leaky payload sendGuard is
 * supposed to catch; (2) that one device's failure doesn't abort the
 * others — proving that rigorously (rather than via two real config errors,
 * which is also exercised, see notify.test.mjs) needs a sender that can be
 * made to fail for one device and succeed for another on command, which no
 * real FCM/APNs credential exists in this repo to arrange.
 */
export interface NotifyDeviceDeps {
  buildPush?: (input: PushInput) => PushPayload;
  sendGuard?: (p: PushPayload) => PushPayload;
  sendFcm?: (p: PushPayload) => Promise<unknown>;
  sendApns?: (p: PushPayload) => Promise<unknown>;
  /**
   * Test-only injection seam, added v0.49.14. `admitDevice()`'s `ok:false`
   * ("silent_device") branch cannot currently be reached with real data —
   * every channel devices.ts's own `CHANNELS` table declares has either
   * `push:true` or a real (non-`'none'`) fallback — but it is live code in
   * the exact path devices.ts's own header calls "the worst class of
   * defect this product can have," and an adversarial audit found it had
   * never executed once under test. Same shape as buildPush/sendGuard/
   * sendFcm/sendApns above: defaults to the real `admitDevice`, so a
   * caller that passes nothing gets exactly the original, non-overridable
   * behavior.
   */
  admitDevice?: typeof admitDevice;
  /**
   * Test-only injection seam, added v0.49.14, same reasoning as
   * `admitDevice` above: the `catch { }` around `removeDeviceTokenSystem()`
   * below (best-effort prune-on-deviceGone cleanup) had never been
   * exercised with a THROWING prune — an adversarial audit found it
   * untested, not that it was wrong; JS try/catch semantics already
   * guarantee `pruned` stays `false` and the outer result still pushes
   * correctly if this throws, but "guaranteed by language semantics" and
   * "proven by a real test" are not the same claim, and this codebase does
   * not treat them as interchangeable elsewhere.
   */
  removeDeviceTokenSystem?: typeof removeDeviceTokenSystem;
}

/**
 * Resolves a device's real §8.11.4 channel for the `admitDevice()` check
 * below. `device.channel` (0015) is used when the client reported one;
 * otherwise this falls back to a conservative, EXPLICITLY-NAMED assumption
 * — never a value written into storage (0015's own migration comment
 * explains why NULL, not a guess, is what's persisted there).
 *
 * The assumption: an unknown Android device is assumed 'android_play'. This
 * is the OPTIMISTIC direction, not the safe one — a real FireOS/bare-Android
 * device that has not yet reported a channel still gets FCM attempted
 * against it, exactly the pre-v0.49.11 behavior, until it reports a real
 * one. That is a genuine, known limitation, not a fix posing as complete:
 * closing it needs the native install-source detection `devices.ts`'s own
 * §8.11.4 header names and explicitly defers this pass. The alternative —
 * defaulting pessimistically and skipping every unknown Android device —
 * would trade one real failure mode (push attempted, might silently fail on
 * the FireOS minority) for a worse one (push withheld from the Play-
 * Services-capable majority on pure precaution). iOS/Windows/Web need no
 * such guess: nothing is ambiguous about "this is iOS," and push_channel.dart
 * reports it for real as of v0.49.11.
 */
function resolveChannel(device: DeviceTokenRow): Channel {
  if (device.channel) return device.channel;
  return device.platform === 'ios' ? 'ios' : 'android_play';
}

/**
 * Looks up `target`'s device_token rows (deviceTokensFor — system-role only,
 * never reachable from a client-facing route) and sends one push per device.
 *
 * A send failure for ONE device must never abort the others: every device is
 * tried, every result is collected, nothing is thrown away. The function
 * itself never throws for a per-device failure — only for a genuinely
 * unrecoverable input (see the `target` validation below, which mirrors
 * withSession()'s own "reject nonsense rather than match nothing").
 *
 * v0.49.11: a device resolved to a push-incapable channel is now SKIPPED
 * here — never handed to fcm.ts/apns.ts at all — rather than fired into the
 * void and left for the platform to (maybe) report back as a failure. See
 * `resolveChannel()` above for the exact, honestly-limited resolution rule.
 */
export async function notifyDevices(
  pool: pg.Pool, target: DeviceOwner, input: NotifyInput, deps: NotifyDeviceDeps = {},
): Promise<DeviceSendResult[]> {
  const _buildPush = deps.buildPush ?? buildPush;
  const _sendGuard = deps.sendGuard ?? sendGuard;
  const _sendFcm = deps.sendFcm ?? sendFcm;
  const _sendApns = deps.sendApns ?? sendApns;
  const _admitDevice = deps.admitDevice ?? admitDevice;
  const _removeDeviceTokenSystem = deps.removeDeviceTokenSystem ?? removeDeviceTokenSystem;

  const devices: DeviceTokenRow[] = await deviceTokensFor(pool, target);
  const results: DeviceSendResult[] = [];

  for (const device of devices) {
    const channel = resolveChannel(device);
    const admission = _admitDevice(channel);
    const canPush = admission.ok && admission.capability.push;
    if (!canPush) {
      results.push({
        deviceTokenId: device.id, platform: device.platform, ok: false,
        code: 'no_push_capability',
        advice: admission.ok ? (channelAdvice(channel) ?? undefined) : admission.note,
      });
      continue;
    }

    try {
      const payload = _buildPush({
        kind: input.kind,
        platform: device.platform,
        deviceToken: device.token,
        ref: input.ref,
        callRoomHandle: input.callRoomHandle,
        collapseKey: input.collapseKey,
      });
      // THE GUARD. Never call fcm.ts/apns.ts with a payload that has not
      // passed through this.
      _sendGuard(payload);

      if (device.platform === 'android') await _sendFcm(payload);
      else await _sendApns(payload);

      results.push({ deviceTokenId: device.id, platform: device.platform, ok: true });
    } catch (e: any) {
      const code = e?.code ?? 'unknown_error';
      const message = String(e?.message ?? e);
      let pruned = false;
      // Only a platform's own definitive "this token is dead" signal prunes
      // the row — never a config/transport error, which says nothing about
      // whether the DEVICE is still real.
      if (e?.deviceGone === true) {
        try { pruned = await _removeDeviceTokenSystem(pool, device.id); }
        catch { /* best-effort cleanup; the send failure is still reported below */ }
      }
      results.push({ deviceTokenId: device.id, platform: device.platform, ok: false, code, message, pruned });
    }
  }
  return results;
}
