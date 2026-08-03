/**
 * MASTERFILE §5.21 — call security.
 *
 * THE LEAK THIS FILE EXISTS FOR:
 *
 * WebRTC prefers a peer-to-peer path. When it succeeds, each side learns the
 * other's IP address. An IP address is a coarse location — city, often
 * neighbourhood, and with a subpoena an exact one.
 *
 * Prohibition P3 forbids live location. Every previous increment enforced P3 at
 * the application layer: no coordinate columns, arrival as an event, no location
 * keys in push payloads. **And a peer-to-peer video call would have leaked it
 * anyway, through a channel nobody had looked at.**
 *
 * It is worse than a general privacy problem. `guardianship.restricted` exists
 * for protective orders — a parent whose address is legally withheld from the
 * other. A P2P call hands the restricted party a location fix on a supervised
 * one. That is not a privacy defect, it is a safety defect, and it would have
 * shipped.
 *
 * So: ALL media is relayed. Always. No exceptions, no "when needed", no
 * optimisation for the common case.
 */

export type Side = 'A' | 'B';

// ============================================================ transport =====
export type IceTransportPolicy = 'all' | 'relay';

export interface CallPolicy {
  /** Literal `'relay'`. There is no branch that sets this to 'all'. */
  iceTransportPolicy: 'relay';
  /** Media is decryptable at the SFU unless E2EE is on. See §5.21.3. */
  e2ee: boolean;
  /** A whole-screen share leaks whatever else is on the screen. §5.21.2. */
  screenShare: 'window_only' | 'disabled';
  /** Notifications are suppressed for the sharing party while sharing. */
  suppressNotificationsWhileSharing: true;
  /** Camera and mic are released the instant the app loses focus. */
  releaseCaptureOnBackground: true;
  /** Recording, if any, is disclosed before it starts. §5.15. */
  recording: 'off' | 'disclosed_supervised';
}

export const RELAY_ONLY: IceTransportPolicy = 'relay';

/**
 * The only constructor. There is deliberately no parameter that could turn the
 * relay off, so a future contributor optimising for bandwidth has to change this
 * file and fail the test rather than pass a flag.
 */
export function callPolicy(opts: {
  e2ee?: boolean;
  allowScreenShare?: boolean;
  recording?: CallPolicy['recording'];
}): CallPolicy {
  return {
    iceTransportPolicy: 'relay',
    e2ee: opts.e2ee ?? true,
    screenShare: opts.allowScreenShare ? 'window_only' : 'disabled',
    suppressNotificationsWhileSharing: true,
    releaseCaptureOnBackground: true,
    recording: opts.recording ?? 'off',
  };
}

/**
 * §5.21.1 — a protective order makes relay-only non-negotiable, and it already
 * was. This function exists so the reasoning is testable rather than implied.
 */
export function relayRequiredBecause(edges: { restricted: boolean }[]): string[] {
  const reasons = ['P3 — an IP address is a coarse location for every family'];
  if (edges.some(e => e.restricted)) {
    reasons.push('a protective order is in force; a peer path would disclose the '
      + 'protected party\'s location to the restricted one');
  }
  return reasons;
}

export type PolicyFault =
  | 'peer_to_peer_permitted' | 'whole_screen_share' | 'capture_survives_background'
  | 'undisclosed_recording' | 'notifications_visible_while_sharing';

/** Audits a policy object as it would actually be handed to the client. */
export function auditPolicy(p: CallPolicy): { ok: true } | { ok: false; faults: PolicyFault[] } {
  const faults: PolicyFault[] = [];
  if ((p.iceTransportPolicy as string) !== 'relay') faults.push('peer_to_peer_permitted');
  if ((p.screenShare as string) === 'screen' || (p.screenShare as string) === 'all') {
    faults.push('whole_screen_share');
  }
  if (!p.releaseCaptureOnBackground) faults.push('capture_survives_background');
  if (!p.suppressNotificationsWhileSharing) faults.push('notifications_visible_while_sharing');
  if ((p.recording as string) === 'on' || (p.recording as string) === 'silent') {
    faults.push('undisclosed_recording');
  }
  return faults.length ? { ok: false, faults } : { ok: true };
}

// ====================================================== the share surface ===
/**
 * §5.21.2 — screen sharing is the second leak, and it is the one parents cause
 * themselves.
 *
 * A father shares his screen to help with fractions. Along the top of it: a text
 * from his lawyer, an email subject line, a browser tab, a notification from a
 * dating app. He is not careless — a whole-screen share simply shows everything,
 * and the child is looking straight at it.
 *
 * So sharing is scoped to ONE window, notifications are suppressed for the
 * duration, and the app names what is about to be visible before it starts.
 */
export interface SharePreflight {
  windowTitle: string;
  /** What the other side will actually see, in plain words. */
  disclosure: string;
  notificationsSuppressed: true;
  wholeScreenAvailable: false;
}

export function sharePreflight(windowTitle: string): SharePreflight {
  return {
    windowTitle,
    disclosure: `Maya will see this one window — "${windowTitle}" — and nothing `
      + 'else. Your notifications are paused until you stop.',
    notificationsSuppressed: true,
    wholeScreenAvailable: false,
  };
}

// ============================================================== E2EE ========
/**
 * §5.21.3 — end-to-end encryption, and the tension it creates.
 *
 * With E2EE on, the SFU forwards ciphertext it cannot read. That is the right
 * default for a child's face and voice.
 *
 * It also makes SERVER-SIDE RECORDING IMPOSSIBLE, and §5.15 supervised visitation
 * depends on recording. The two cannot both be true for one call, and pretending
 * otherwise would be the kind of quiet contradiction that ships.
 *
 * The resolution: E2EE is the default and recording is the exception. A
 * supervised call disables E2EE and says so, on screen, before it starts. The
 * institutional tier (§14) buys recording by giving up encryption, deliberately
 * and visibly — never silently.
 */
export type E2eeDecision =
  | { e2ee: true; recording: 'off'; note: string }
  | { e2ee: false; recording: 'disclosed_supervised'; note: string };

export function decideE2ee(supervisedRecordingRequired: boolean): E2eeDecision {
  return supervisedRecordingRequired
    ? { e2ee: false, recording: 'disclosed_supervised',
        note: 'This call is being recorded for the supervision order, so it is not '
            + 'end-to-end encrypted. Both of you are told this before it starts.' }
    : { e2ee: true, recording: 'off',
        note: 'This call is end-to-end encrypted. Nobody, including us, can see or '
            + 'hear it.' };
}

/** A silent combination of both is unrepresentable. */
export function auditE2ee(d: { e2ee: boolean; recording: string }):
  { ok: true } | { ok: false; reason: string } {
  if (d.e2ee && d.recording !== 'off') {
    return { ok: false, reason: 'E2EE and recording cannot both be on — one of '
      + 'them is a lie to somebody' };
  }
  if (!d.e2ee && d.recording === 'off') {
    return { ok: false, reason: 'encryption was given up for nothing' };
  }
  return { ok: true };
}

// ==================================================== what still leaks =====
/**
 * §5.21.4 — an honest register of what relay-only does NOT solve.
 *
 * A security section that lists only what it fixed is marketing. Each of these
 * is real, and three of them cannot be fixed by us at all.
 */
export const RESIDUAL_RISKS = [
  { risk: 'The relay sees IP addresses',
    mitigation: 'We do. Both parties are exposed to us rather than to each other, '
      + 'which is the trade being made deliberately.',
    fixable: true },
  { risk: 'The SFU can decrypt media when E2EE is off for a supervised call',
    mitigation: 'Disclosed on screen before the call starts. §5.21.3.',
    fixable: true },
  { risk: 'Either party can point a second phone at the screen',
    mitigation: 'None possible. No software prevents a camera.',
    fixable: false },
  { risk: 'OS-level screen recording',
    mitigation: 'Detectable on iOS and partially on Android; disclosed to the '
      + 'other party where the platform allows it. Not preventable.',
    fixable: false },
  { risk: 'Call metadata — who called whom, when, for how long',
    mitigation: 'Retained, because §14 court export needs it. §16.2 #11 is still '
      + 'open on whether a therapist sees it.',
    fixable: true },
  { risk: 'A parent standing behind the child during a call with the other parent',
    mitigation: 'None, and not ours to solve. Worth naming because it is the most '
      + 'common real breach of a child\'s privacy in this product, and no amount of '
      + 'transport security touches it.',
    fixable: false },
] as const;

export const unfixableRisks = () => RESIDUAL_RISKS.filter(r => !r.fixable).length;
