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
 */
import type pg from 'pg';
import { buildPush, sendGuard, type PushInput, type PushPayload, type PushKind } from './push.ts';
import { sendFcm } from './fcm.ts';
import { sendApns } from './apns.ts';
import {
  deviceTokensFor, removeDeviceTokenSystem,
  type DeviceOwner, type DeviceTokenRow,
} from '../../db/src/pool.ts';

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
   * failure, which is the only kind of caller this function has today (grep
   * across server/routes.mjs confirms notifyDevices() has zero HTTP call
   * sites as of this writing).
   *
   * THIS IS DELIBERATELY NOT SAFE TO RETURN VERBATIM IN AN HTTP RESPONSE.
   * Whoever wires the first real API-facing caller of notifyDevices() MUST
   * NOT naively serialize `results`/`results[].message` into that response —
   * `code` above is the already-generalized, safe-to-expose signal a
   * client-facing surface should use instead. Caught by an adversarial
   * review while this was still a forward-looking gap, not a live one;
   * recorded here rather than "fixed" by guessing at a redaction shape the
   * real caller's actual needs (ops dashboard vs. client-facing error toast
   * likely want different things) don't exist yet to inform.
   */
  message?: string;
  /** True when the device's row was reaped because the platform told us the
   * token is permanently dead (see fcm.ts/apns.ts's `deviceGone`). */
  pruned?: boolean;
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
 */
export async function notifyDevices(
  pool: pg.Pool, target: DeviceOwner, input: NotifyInput, deps: NotifyDeviceDeps = {},
): Promise<DeviceSendResult[]> {
  const _buildPush = deps.buildPush ?? buildPush;
  const _sendGuard = deps.sendGuard ?? sendGuard;
  const _sendFcm = deps.sendFcm ?? sendFcm;
  const _sendApns = deps.sendApns ?? sendApns;

  const devices: DeviceTokenRow[] = await deviceTokensFor(pool, target);
  const results: DeviceSendResult[] = [];

  for (const device of devices) {
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
        try { pruned = await removeDeviceTokenSystem(pool, device.id); }
        catch { /* best-effort cleanup; the send failure is still reported below */ }
      }
      results.push({ deviceTokenId: device.id, platform: device.platform, ok: false, code, message, pruned });
    }
  }
  return results;
}
