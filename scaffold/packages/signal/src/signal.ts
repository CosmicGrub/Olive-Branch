/**
 * MASTERFILE §5.27 — the come-back signal.
 *
 * THE MECHANIC, stated once because everything follows from it:
 *
 *   **He requests. She acts.**
 *
 * No data flows back, no control channel exists, and the child performs every
 * action herself. That single constraint is what lets this expand to sixteen
 * applications safely — each one inherits the same safety rather than needing its
 * own argument.
 *
 * It exists because the alternative was remote control of a child's device, which
 * is a stalkerware primitive however kindly it is framed. See P11.
 */

export type Side = 'A' | 'B';

// =================================================== §5.27.1 the applications
export type SignalKind =
  | 'come_back' | 'im_here' | 'look_at_this' | 'show_me_again' | 'turn_it_round'
  | 'can_you_hear_me' | 'louder' | 'nearly_bedtime' | 'your_turn' | 'wave_to_other'
  | 'running_late' | 'say_goodnight' | 'someone_says_hello' | 'sorry_my_end'
  | 'nearly_there' | 'well_done';

/** Whether an application may interrupt a surface she is in the middle of. */
export type Interruptibility = 'always' | 'defers' | 'never';

/** How it is rendered. See §8.8b for the matrix. */
export type SenderRole = 'absent_parent' | 'present_parent' | 'either_parent';

export interface Application {
  kind: SignalKind;
  /** Her words, on the prompt itself. */
  copy: string;
  sender: SenderRole;
  interruptibility: Interruptibility;
  /**
   * §5.27.4 — is the action harmless if tapped reflexively?
   *
   * A prompt that always appears in the same place WILL be tapped by accident.
   * An application whose action is not safe under that condition does not get to
   * use this pattern at all — checked at construction, not at review.
   */
  safeIfTappedByAccident: boolean;
  /** Only the emergency card outranks everything. */
  safetyCritical: boolean;
  minAge: number;
}

export const APPLICATIONS: Application[] = [
  { kind: 'come_back', copy: 'Dad is waiting. Tap to go back.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 2 },
  { kind: 'im_here', copy: 'Dad is here.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 2 },
  { kind: 'look_at_this', copy: 'Dad sent you something.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'show_me_again', copy: 'Can you hold it up again?',
    sender: 'absent_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'turn_it_round', copy: 'Turn the camera round?',
    sender: 'absent_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 4 },
  // Visual by necessity: it is the only channel that survives the failure it
  // is diagnosing.
  { kind: 'can_you_hear_me', copy: 'Can you hear me?',
    sender: 'either_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'louder', copy: 'Come a bit closer?',
    sender: 'either_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'nearly_bedtime', copy: 'Nearly bedtime.',
    sender: 'present_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'your_turn', copy: 'Your turn.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 4 },
  // §9.13.3 — only the parent physically present may invite a handoff.
  { kind: 'wave_to_other', copy: 'Wave to Mum?',
    sender: 'present_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'running_late', copy: 'Dad is running a bit late.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 4 },
  { kind: 'say_goodnight', copy: 'Time to say goodnight.',
    sender: 'present_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'someone_says_hello', copy: 'Someone wants to say hello.',
    sender: 'absent_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'sorry_my_end', copy: 'That was my end. Not you.',
    sender: 'absent_parent', interruptibility: 'always',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 4 },
  { kind: 'nearly_there', copy: 'Dad is nearly there.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 3 },
  { kind: 'well_done', copy: 'Dad heard about today. Well done.',
    sender: 'absent_parent', interruptibility: 'defers',
    safeIfTappedByAccident: true, safetyCritical: false, minAge: 4 },
];

export const application = (k: SignalKind) => APPLICATIONS.find(a => a.kind === k)!;

/**
 * §5.27.4 — the entry gate. An application whose action is not safe when tapped
 * by accident cannot use this pattern, and this is where that is refused rather
 * than noticed in review.
 */
export type AdmitError = 'unsafe_if_mistapped' | 'unknown_kind';

export function admitApplication(
  a: Application,
): { ok: true } | { ok: false; reason: AdmitError } {
  return a.safeIfTappedByAccident ? { ok: true } : { ok: false, reason: 'unsafe_if_mistapped' };
}

// ================================================= §5.27.2 who may send =====
/**
 * §17 family configurations. The signal behaves identically in all four, and
 * **never reveals the family's shape to the child** — one parent or two,
 * restricted or not, present or absent, it looks the same.
 */
export type Configuration =
  | 'both_parents' | 'one_parent_only' | 'sole_guardian' | 'both_in_same_house';

/** Settled: third adults cannot send. A stepparent in the room can speak. */
export type Principal =
  | 'parent' | 'grandparent' | 'stepparent' | 'caregiver' | 'therapist'
  | 'coordinator' | 'supervisor';

export const MAY_SEND: Principal[] = ['parent'];

export function canSend(p: Principal): boolean {
  return (MAY_SEND as readonly string[]).includes(p);
}

export const THIRD_ADULT_REASON =
  'The signal is a parent-child channel. Widening it makes it a household '
  + 'broadcast — and anyone in the room with her can simply speak.';

/**
 * Both parents in the same house: the whole mechanic stands down. A signal from
 * somebody in the next room is absurd, and a product looking absurd there is how
 * a family stops trusting it.
 */
export function activeInConfiguration(c: Configuration): boolean {
  return c !== 'both_in_same_house';
}

// ================================================= §5.27.3 priority =========
export interface Pending {
  kind: SignalKind;
  fromUserId: string;
  /** Is this sender the parent she is physically with right now? */
  senderIsPresent: boolean;
  inCall: boolean;
  at: string;
}

export type PriorityReason =
  | 'safety' | 'absence_beats_presence' | 'in_call' | 'first';

/**
 * 1. Safety overrides everything.
 * 2. Presence LOSES to absence — the parent she is with can simply talk to her.
 * 3. In-call beats out-of-call.
 * 4. Then simply first.
 *
 * **No seniority, no primary/secondary, no custody weighting.** Under no
 * circumstances does the order of a court order become the order of a prompt on
 * a child's screen.
 */
export function prioritise(
  pending: Pending[],
): { winner: Pending; reason: PriorityReason } | null {
  if (!pending.length) return null;
  const safety = pending.filter(p => application(p.kind).safetyCritical);
  if (safety.length) return { winner: safety[0], reason: 'safety' };

  const absent = pending.filter(p => !p.senderIsPresent);
  const pool = absent.length ? absent : pending;
  const reason: PriorityReason = absent.length && absent.length < pending.length
    ? 'absence_beats_presence' : 'first';

  const inCall = pool.filter(p => p.inCall);
  if (inCall.length && inCall.length < pool.length) {
    return { winner: [...inCall].sort((a, b) => a.at.localeCompare(b.at))[0],
      reason: 'in_call' };
  }
  return { winner: [...pool].sort((a, b) => a.at.localeCompare(b.at))[0], reason };
}

/** The loser is never told they lost. That is a competition she would be the prize in. */
export function senderFeedback(): { toldTheyLost: false; toldSheIgnored: false } {
  return { toldTheyLost: false, toldSheIgnored: false };
}

/**
 * §5.27.6, settled: **the sender sees nothing, ever.** Not a count, not a badge,
 * not "she has not responded". If he needs to know she is alright, that is a
 * phone call to the other adult — not an inference drawn from a child's non-tap.
 */
export const IGNORED_SIGNAL_IS_INVISIBLE = true;

export const SENDER_FORBIDDEN = [
  'delivered', 'seen', 'read', 'ignored', 'dismissed', 'unanswered',
  'responseRate', 'count', 'attempts', 'lastSeen',
] as const;

export function auditSenderView(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((SENDER_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ================================================= §5.27.5 the rules ========
/** One at a time. A second replaces the first — a queue is a demand list. */
export interface SignalState {
  current: Pending | null;
  mutedUntil: string | null;
  sentToday: number;
  /** Set while she is already acting on one. */
  transitioning: boolean;
}

export const EXPIRES_AFTER_SECONDS = 90;

/**
 * A hard daily ceiling **independent of the age bands.** Sixteen applications
 * across two parents could deliver forty prompts a day while satisfying every
 * individual rule.
 */
export const DAILY_CEILING = 12;

export function newState(): SignalState {
  return { current: null, mutedUntil: null, sentToday: 0, transitioning: false };
}

export type DeliverError =
  | 'muted' | 'daily_ceiling' | 'silent_hours' | 'blocked_window'
  | 'mid_transition' | 'not_interruptible' | 'sender_not_permitted'
  | 'configuration_inactive' | 'too_young';

export interface DeliverContext {
  state: SignalState;
  principal: Principal;
  configuration: Configuration;
  childAge: number;
  /** From §9.9's day-parts: school, asleep, wind-down, quiet hours. */
  windowBlocked: boolean;
  /** Her local hour, for the silent-hours floor. */
  localHour: number;
  /** What she is doing right now, if it declares itself uninterruptible. */
  surfaceBusy: boolean;
  now: string;
}

/** Nothing fires between these hours but the emergency card. */
export const SILENT_FROM_HOUR = 20;
export const SILENT_TO_HOUR = 7;

export function inSilentHours(hour: number): boolean {
  return hour >= SILENT_FROM_HOUR || hour < SILENT_TO_HOUR;
}

export function deliver(
  ctx: DeliverContext, p: Pending,
): { ok: true; state: SignalState } | { ok: false; reason: DeliverError } {
  const app = application(p.kind);

  if (!canSend(ctx.principal)) return { ok: false, reason: 'sender_not_permitted' };
  if (!activeInConfiguration(ctx.configuration)) {
    return { ok: false, reason: 'configuration_inactive' };
  }
  if (ctx.childAge < app.minAge) return { ok: false, reason: 'too_young' };
  if (ctx.state.mutedUntil && ctx.now < ctx.state.mutedUntil) {
    return { ok: false, reason: 'muted' };
  }
  if (ctx.state.sentToday >= DAILY_CEILING && !app.safetyCritical) {
    return { ok: false, reason: 'daily_ceiling' };
  }
  if (inSilentHours(ctx.localHour) && !app.safetyCritical) {
    return { ok: false, reason: 'silent_hours' };
  }
  if (ctx.windowBlocked && !app.safetyCritical) {
    return { ok: false, reason: 'blocked_window' };
  }
  // A signal arriving while she is already acting on one is DROPPED, not queued.
  if (ctx.state.transitioning) return { ok: false, reason: 'mid_transition' };
  if (ctx.surfaceBusy && app.interruptibility !== 'always') {
    return { ok: false, reason: 'not_interruptible' };
  }
  // One at a time: this replaces whatever was there.
  return { ok: true, state: { ...ctx.state, current: p,
    sentToday: ctx.state.sentToday + 1 } };
}

/** Silently, after 90 seconds. A prompt still there twenty minutes later is a reproach. */
export function expire(s: SignalState): SignalState {
  return { ...s, current: null };
}

/** Free, silent, and a real answer. If dismissal costs her anything, it is a command. */
export function dismiss(s: SignalState): SignalState {
  return { ...s, current: null };
}

export function act(s: SignalState): SignalState {
  return { ...s, current: null, transitioning: true };
}

export function transitionComplete(s: SignalState): SignalState {
  return { ...s, transitioning: false };
}

/** One tap, no reason given, nobody told. If she cannot opt out, it is not a request. */
export const CHILD_MUTE_HOURS = 1;

export function muteForAnHour(s: SignalState, now: string): SignalState {
  return { ...s, current: null,
    mutedUntil: new Date(Date.parse(now) + CHILD_MUTE_HOURS * 3600_000).toISOString() };
}

export function muteVisibleToSender(): false { return false; }

/** Signals are gestures. Minuting gestures changes what people send. */
export const SIGNALS_ARE_NEVER_PRESERVED = true;
export const SIGNALS_IN_COURT_EXPORT = false;
export const SIGNALS_IN_ARCHIVE = false;

// ============================================= §5.27.7 the escape hatch =====
/**
 * From any surface, during any call, one unmissable control returns her to the
 * call. Reachable in one tap, from anywhere, always — the signal's structural
 * counterpart, and the reason a "come back" is usually unnecessary.
 */
export interface EscapeHatch {
  reachableInTaps: 1;
  presentOnEverySurface: true;
  /** She can never lose it, exactly as she can never close the pane. */
  dismissible: false;
  label: string;
}

export function escapeHatch(): EscapeHatch {
  return { reachableInTaps: 1, presentOnEverySurface: true, dismissible: false,
    label: 'Back to Dad' };
}

// ============================================= §5.27.8 first-run teaching ===
/**
 * She meets the signal once, deliberately, during onboarding — her father sends
 * the first one and she taps it. A pattern learned in a calm moment is one she
 * recognises in a confused one.
 */
export interface FirstRunLesson {
  kind: 'come_back';
  copy: string;
  /** She must actually tap it. It cannot be skipped by waiting. */
  requiresTap: true;
}

export function firstRunLesson(): FirstRunLesson {
  return { kind: 'come_back',
    copy: 'This is what it looks like when Dad wants you. Give it a tap.',
    requiresTap: true };
}
