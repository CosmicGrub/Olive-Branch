/**
 * MASTERFILE §10.5 — delivery on a device that cannot be pushed to.
 *
 * v0.32.0 declared that a FireOS tablet falls back to a foreground socket and an
 * SMS to the adult in the house. **It declared it and did not build it.** The
 * device matrix described a mechanism that did not exist, which is a worse state
 * than the original defect: the original was an oversight, this was a documented
 * assurance with nothing behind it.
 *
 * This is that mechanism.
 */

export type Channel =
  | 'android_play' | 'android_amazon' | 'android_bare' | 'ios' | 'windows' | 'web';

export type Route = 'push' | 'socket' | 'sms_to_adult' | 'none';

// ================================================== the routing decision ====
export interface RoutingInput {
  channel: Channel;
  /** Is the child's app in the foreground right now? */
  appForeground: boolean;
  /** Has a socket been established and held? */
  socketConnected: boolean;
  /** Is there an adult phone number at the house she is at? */
  adultNumberOnFile: boolean;
  /** How long since the item was queued. Drives escalation, not urgency. */
  minutesWaiting: number;
}

export interface RoutingDecision {
  route: Route;
  /** Every route that was tried and why it was not taken. Auditable. */
  rejected: { route: Route; because: string }[];
  /** Set when nothing can reach her, which must never be silent. */
  unreachable: boolean;
}

export const PUSH_CHANNELS: Channel[] = ['android_play', 'ios', 'windows'];

/**
 * Escalate to a text only after this long. A message that arrives on a parent's
 * phone thirty seconds after it was sent turns every drawing into an alarm.
 */
export const SMS_ESCALATE_AFTER_MINUTES = 90;

export function route(i: RoutingInput): RoutingDecision {
  const rejected: RoutingDecision['rejected'] = [];

  if (PUSH_CHANNELS.includes(i.channel)) {
    return { route: 'push', rejected, unreachable: false };
  }
  rejected.push({ route: 'push',
    because: `${i.channel} has no push service available to third-party apps` });

  if (i.socketConnected && i.appForeground) {
    return { route: 'socket', rejected, unreachable: false };
  }
  rejected.push({ route: 'socket',
    because: i.socketConnected ? 'app is not in the foreground' : 'no socket held' });

  if (i.adultNumberOnFile && i.minutesWaiting >= SMS_ESCALATE_AFTER_MINUTES) {
    return { route: 'sms_to_adult', rejected, unreachable: false };
  }
  rejected.push({ route: 'sms_to_adult',
    because: !i.adultNumberOnFile ? 'no adult number on file at that house'
      : `only ${i.minutesWaiting} minutes waited, escalates at ${SMS_ESCALATE_AFTER_MINUTES}` });

  return { route: 'none', rejected, unreachable: true };
}

// =========================================== telling the sender the truth ===
/**
 * THE RULE THIS MODULE EXISTS FOR: **the sender is told what actually happened.**
 *
 * The original defect was not that FCM was missing. It was that both people were
 * misled and neither could discover it. A fallback that fails quietly reproduces
 * the same defect with more machinery.
 */
export interface SenderStatus {
  delivered: boolean;
  line: string;
  /** True only where he should do something. Usually he should not. */
  actionable: boolean;
}

export function senderStatus(d: RoutingDecision, childName: string): SenderStatus {
  if (d.route === 'push' || d.route === 'socket') {
    return { delivered: true, actionable: false,
      line: d.route === 'socket'
        ? `${childName} has it open — she has it now.`
        : `Sent to ${childName}'s tablet.` };
  }
  if (d.route === 'sms_to_adult') {
    return { delivered: true, actionable: false,
      line: `${childName}'s tablet can't show alerts, so we've texted the grown-up `
          + 'there to let her know something is waiting.' };
  }
  return { delivered: false, actionable: true,
    line: `It's saved, and ${childName} will see it the moment she opens Olive. `
        + 'Her tablet can\'t alert her and we don\'t have a number for the house — '
        + 'add one and we can let someone know next time.' };
}

/** Copy that would mislead the sender about delivery. */
export const STATUS_BANNED = [
  'delivered', 'read', 'seen', 'received', 'she knows', 'notified',
] as const;

export function auditStatus(s: SenderStatus): { ok: true } | { ok: false; found: string[] } {
  // 'delivered' as a *claim* is only permissible when it is true.
  const t = s.line.toLowerCase();
  const found = (STATUS_BANNED as readonly string[])
    .filter(w => t.includes(w) && !s.delivered);
  return found.length ? { ok: false, found } : { ok: true };
}

// ================================================= the SMS to the adult =====
/**
 * The text goes to an adult, so it may be plainer than a push — but it still
 * reaches a household where the other parent may be standing in the room. §10.4's
 * reasoning applies unchanged: no name, no content, no sender.
 */
export const ADULT_SMS = 'Olive: something is waiting on the tablet.';

export const SMS_FORBIDDEN_TOKENS = [
  'from', 'dad', 'mum', 'mom', 'father', 'mother', 'said', 'wrote', 'sent you',
  'message:', 'photo', 'drawing', 'call',
] as const;

export function auditAdultSms(text: string): { ok: true } | { ok: false; found: string[] } {
  const t = text.toLowerCase();
  const found = (SMS_FORBIDDEN_TOKENS as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ====================================================== the socket =========
/**
 * A held socket is the only reliable path on a non-push device, so its lifecycle
 * matters more here than it would elsewhere.
 *
 * It is deliberately NOT kept alive in the background: a socket held by a
 * backgrounded app on a cheap tablet is a battery complaint that ends with the
 * app being uninstalled, and an uninstalled app delivers nothing at all.
 */
export interface SocketPolicy {
  holdInForeground: true;
  holdInBackground: false;
  reconnectBackoffMs: number[];
  note: string;
}

export function socketPolicy(): SocketPolicy {
  return {
    holdInForeground: true,
    holdInBackground: false,
    reconnectBackoffMs: [1000, 2000, 5000, 15000, 60000],
    note: 'Held only while she has Olive open. A background socket on a £50 tablet '
        + 'is a battery complaint that ends in an uninstall, and an uninstalled app '
        + 'delivers nothing at all.',
  };
}

/** Reachability, stated plainly, for the guardian settings screen. */
export function reachability(c: Channel): {
  channel: Channel; canAlert: boolean; line: string;
} {
  const canAlert = PUSH_CHANNELS.includes(c);
  return { channel: c, canAlert,
    line: canAlert
      ? 'Alerts arrive even when Olive is closed.'
      : 'Alerts only arrive while Olive is open. We can text the grown-up there '
      + 'if something has been waiting a while.' };
}
