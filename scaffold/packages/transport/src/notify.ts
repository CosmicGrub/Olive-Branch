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
 *
 * THE §6.4 GATE, NOW REAL HERE TOO. Before this pass, `gate()`
 * (packages/delivery-engine/src/gate.ts) was wired into exactly one real
 * surface: the read-only `GET /v1/children/:childId/now` route (see
 * server/routes.mjs's own top-of-file comment and MASTERFILE §6.4's
 * v0.49.63 status note) — a client-side send-time-guard display, not the
 * actual push-dispatch path. `notifyDevices()` itself never consulted it:
 * the one real production caller (the calls route, `call_incoming`) rang a
 * child's device with no asleep/school check at all. Now: for a
 * CHILD-targeted `target` (this gate has no guardian-side equivalent —
 * `childCtxFor()`'s day-part rows are keyed by `child_id`; see its own
 * header), `childCtxFor()` + `gate()` run once, before the per-device loop,
 * exactly matching the `/now` route's own real primitives (not
 * reimplemented). A blocked batch is skipped entirely — every device gets
 * `code: 'gated_quiet_hours'`, mirroring the existing `no_push_capability`
 * skip shape below — rather than fired into a sleeping child's lock screen.
 *
 * SCOPE, DISCLOSED: this is a HARD skip, not the deferred-retry
 * `gate()`/`GateResult.deferTo` otherwise supports. There is no queue or
 * scheduler anywhere in this codebase that could re-attempt a deferred push
 * later (tools/scheduler.mjs's own header names exactly this — "a real
 * delivery/send worker that actually pushes a `ready` intent to a device"
 * — as a separate, still-open gap, not something this pass invents). A
 * `call_incoming` push is also, structurally, not a good candidate for
 * "deliver 8 hours later" even once such a worker exists — the guardian is
 * calling NOW, not composing a message for later — so a hard skip is the
 * honest behavior today, not a placeholder for one this file pretends to
 * have built.
 *
 * ALSO DISCLOSED: `NotifyInput.priority` defaults to `'normal'`, so a
 * `call_incoming` push is now itself subject to the asleep/school gate like
 * any other arrival. Nothing in this codebase has ever set `'emergency'`
 * priority anywhere, and MASTERFILE §6.4's own gate() contract names
 * `'emergency'` as the ONLY bypass that exists — inventing a
 * calls-always-bypass rule here, with no product decision on record for it,
 * would be exactly the kind of unscoped call this codebase's own established
 * practice (see RLS-01's scoping, this same batch) argues against. A future
 * caller that has an actual emergency-call concept sets `priority:
 * 'emergency'` explicitly; nothing here decides that concept exists.
 */
import { DateTime } from 'luxon';
import type pg from 'pg';
import { buildPush, sendGuard, type PushInput, type PushPayload, type PushKind } from './push.ts';
import { sendFcm } from './fcm.ts';
import { sendApns, openApnsSession, type ApnsSession, type Http2SessionLike } from './apns.ts';
import {
  deviceTokensFor, removeDeviceTokenSystem, childCtxFor,
  type DeviceOwner, type DeviceTokenRow,
} from '../../db/src/pool.ts';
import { type Channel, admitDevice, channelAdvice } from '../../devices/src/devices.ts';
import { gate, type Priority } from '../../delivery-engine/src/gate.ts';

export interface NotifyInput {
  kind: PushKind;
  /** Opaque ref the client resolves post-unlock. Never content. */
  ref: string;
  /** call_incoming only. */
  callRoomHandle?: string;
  collapseKey?: string;
  /**
   * MASTERFILE §6.4's gate() contract: `'emergency'` is the one priority the
   * asleep/school gate never blocks. Defaults to `'normal'` — see this
   * file's own header for why nothing here invents an automatic bypass for
   * `call_incoming`.
   */
  priority?: Priority;
}

export interface DeviceSendResult {
  deviceTokenId: string;
  platform: 'android' | 'ios';
  ok: boolean;
  /** Present only when ok:false — one of buildPush/sendGuard/fcm/apns's own
   * thrown `.code`s, e.g. 'fcm_config_missing', 'apns_send_failed'; or
   * 'no_push_capability' (admitDevice() skip, below) or
   * 'gated_quiet_hours' (MASTERFILE §6.4 gate() skip, this file's own
   * header) — neither of which reaches fcm.ts/apns.ts at all. */
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
  /**
   * `opts.session` is P2's batch-level shared-session param (apns.ts's own
   * `sendApns()` header) — declared here too so a real, non-overridden
   * `sendApns` can still be called with it below without an arity error;
   * a test override that ignores the second parameter (every existing one
   * in notify.test.mjs) remains perfectly valid, same as before this pass.
   */
  sendApns?: (p: PushPayload, opts?: { session?: Http2SessionLike }) => Promise<unknown>;
  /**
   * Test-only injection seam, added this pass (P2). Defaults to the real
   * `openApnsSession` — same "pass nothing, get the real thing" rule as
   * every other seam here. Exists so a test can prove the actual
   * session-sharing behavior (one object handed to every iOS sendApns()
   * call in a batch, closed exactly once) without needing a real Apple
   * credential or a real HTTP/2 socket — see notify.test.mjs's own new
   * section for what this seam is used to prove.
   */
  openApnsSession?: typeof openApnsSession;
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
 *
 * P1 (this pass): for a CHILD-targeted `target`, the MASTERFILE §6.4
 * asleep/school gate now runs ONCE, before any device is touched — see this
 * file's own header for the full reasoning, the hard-skip-not-defer scope,
 * and why `call_incoming` gets no automatic bypass.
 *
 * P2 (this pass): the per-device sends now run CONCURRENTLY
 * (`Promise.all`), not one at a time, and every iOS send in the batch shares
 * one real HTTP/2 session (`openApnsSession()`, apns.ts) instead of each
 * paying for its own connect/close — see apns.ts's own header for the
 * ownership contract. Neither change alters this function's own contract
 * above: one result per device, one device's failure never touches another's.
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
  const _openApnsSession = deps.openApnsSession ?? openApnsSession;

  const devices: DeviceTokenRow[] = await deviceTokensFor(pool, target);

  // ---- P1: MASTERFILE §6.4 recipient-side gate — see this file's header --
  if ('childId' in target) {
    const ctx = await childCtxFor(pool, target.childId);
    const g = ctx ? gate(ctx, DateTime.utc(), input.priority ?? 'normal') : null;
    if (g && !g.allow) {
      return devices.map((device): DeviceSendResult => ({
        deviceTokenId: device.id, platform: device.platform, ok: false,
        code: 'gated_quiet_hours',
        message: `blocked by day-part '${g.reason}'`
          + (g.deferTo ? `; next reachable window starts ${g.deferTo.toUTC().toISO()}` : ''),
      }));
    }
  }

  // ---- admission pass: resolve each device's real §8.11.4 channel now, so
  // the concurrent send pass below only ever touches devices already known
  // capable of push. Order of `results` does not need to match `devices` —
  // every existing caller (notify.test.mjs) looks results up by
  // deviceTokenId, never by array position, for exactly this reason.
  const results: DeviceSendResult[] = [];
  const admitted: DeviceTokenRow[] = [];
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
    } else {
      admitted.push(device);
    }
  }

  // ---- P2: one shared APNs session for this batch's iOS sends. Best-effort
  // ONLY — if opening it throws for any reason (missing credentials, a real
  // connect failure), this silently falls back to no shared session, and
  // each iOS send below opens/closes its own exactly as it always has.
  // Nothing downstream needs to know which happened: sendApns() without
  // `opts.session` is byte-for-byte its pre-P2 behavior, so a batch that
  // couldn't get a shared session is not a batch that failed, only one that
  // didn't get the optimization. This is deliberate, not an oversight — see
  // notify.test.mjs's own "no override" section (E), which depends on a
  // missing-credential environment producing the SAME apns_config_missing
  // per device it always has, not a new batch-level failure shape.
  let apnsSession: ApnsSession | null = null;
  if (admitted.some((d) => d.platform === 'ios')) {
    try { apnsSession = _openApnsSession(); } catch { apnsSession = null; }
  }

  const sendToOneDevice = async (device: DeviceTokenRow): Promise<DeviceSendResult> => {
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
      else await _sendApns(payload, apnsSession ? { session: apnsSession.session } : {});

      return { deviceTokenId: device.id, platform: device.platform, ok: true };
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
      return { deviceTokenId: device.id, platform: device.platform, ok: false, code, message, pruned };
    }
  };

  try {
    const sent = await Promise.all(admitted.map(sendToOneDevice));
    results.push(...sent);
  } finally {
    // Whichever devices settled — Promise.all above only resolves once ALL
    // of them have, success or reported-failure alike; sendToOneDevice()
    // itself never rejects — so by the time control reaches here, nothing
    // is still using this session.
    apnsSession?.close();
  }
  return results;
}
