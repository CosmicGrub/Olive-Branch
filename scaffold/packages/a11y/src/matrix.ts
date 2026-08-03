/**
 * MASTERFILE §8.8b — the accessibility matrix.
 *
 * Built to be **extended and rolled out incrementally** rather than shipped
 * complete. Each form carries a readiness state, so a form can be specified long
 * before it is built, and the build can tell the difference — which is the F-series
 * lesson applied to accessibility rather than to layout.
 *
 * The rule that shapes it: **the signal is the product's only interruption
 * pattern**, so it cannot be sight-gated or hearing-gated. Every signal must be
 * perceivable through at least two independent channels.
 */

// ==================================================== the forms =============
export type FormId =
  | 'visual_text' | 'visual_icon' | 'visual_face' | 'colour_accent'
  | 'audio_tone' | 'spoken' | 'haptic'
  | 'large_text' | 'high_contrast' | 'reduced_motion' | 'dyslexia_type'
  | 'simplified_language' | 'symbol_set' | 'sign_video' | 'braille_display'
  | 'switch_access' | 'eye_gaze' | 'one_handed' | 'slow_tap';

/** Which sense the form addresses. Used to prove two-channel coverage. */
export type Channel = 'sight' | 'hearing' | 'touch' | 'cognition' | 'motor';

/**
 * SHIPPED — built, tested, rendering.
 * SCAFFOLDED — the shape exists and is asserted; nothing renders yet.
 * SPECIFIED — decided, not started.
 * CONSIDERED — named so it is not forgotten; no decision taken.
 */
export type Readiness = 'shipped' | 'scaffolded' | 'specified' | 'considered';

export interface Form {
  id: FormId;
  label: string;
  channel: Channel;
  readiness: Readiness;
  /** True where the form must be present for the signal to be perceivable at all. */
  baseline: boolean;
  /** What it depends on. Empty where it is self-contained. */
  requires: string[];
  note: string;
}

export const FORMS: Form[] = [
  // ---- baseline: always present, on every signal, in every configuration ----
  { id: 'visual_text', label: 'Words on the prompt', channel: 'sight',
    readiness: 'shipped', baseline: true, requires: [],
    note: 'Short enough for an early reader; never the only channel.' },
  { id: 'visual_icon', label: 'An icon', channel: 'sight',
    readiness: 'shipped', baseline: true, requires: [],
    note: 'Carries the meaning for a pre-reader.' },
  { id: 'visual_face', label: 'His face', channel: 'sight',
    readiness: 'shipped', baseline: true, requires: [],
    note: 'The one element a two-year-old reads instantly.' },
  { id: 'spoken', label: 'Read aloud', channel: 'hearing',
    readiness: 'shipped', baseline: true, requires: [],
    note: 'The second independent channel. Never optional — it is what makes the '
        + 'signal non-sight-gated.' },

  // ---- shipped enhancements -------------------------------------------------
  { id: 'colour_accent', label: 'Her colour', channel: 'sight',
    readiness: 'shipped', baseline: false, requires: ['§8.6'],
    note: 'Never the ONLY difference between two states — §8.6.2 forbids colour '
        + 'carrying meaning alone.' },
  { id: 'audio_tone', label: 'A soft sound', channel: 'hearing',
    readiness: 'shipped', baseline: false, requires: [],
    note: 'Absent entirely in quiet hours.' },
  { id: 'large_text', label: 'Bigger words', channel: 'sight',
    readiness: 'shipped', baseline: false, requires: ['§8.8 text scale'],
    note: 'Up to 1.5×; the prompt reflows rather than clipping.' },
  { id: 'high_contrast', label: 'Stronger colours', channel: 'sight',
    readiness: 'shipped', baseline: false, requires: [],
    note: 'Raises contrast without recolouring the semantic set.' },
  { id: 'reduced_motion', label: 'Less movement', channel: 'cognition',
    readiness: 'shipped', baseline: false, requires: [],
    note: 'Vestibular triggers are not a preference. The prompt appears rather '
        + 'than sliding.' },

  // ---- scaffolded: shape asserted, nothing renders yet ----------------------
  { id: 'haptic', label: 'A gentle buzz', channel: 'touch',
    readiness: 'scaffolded', baseline: false, requires: ['device vibrator'],
    note: 'The third channel, and the one that works when a tablet is face down. '
        + 'Absent on most cheap tablets, so it can never be relied upon.' },
  { id: 'dyslexia_type', label: 'Easier letters', channel: 'cognition',
    readiness: 'scaffolded', baseline: false, requires: ['font bundle'],
    note: 'A typeface swap, not a rewrite. Affects every surface, not just this one.' },
  { id: 'simplified_language', label: 'Fewer words', channel: 'cognition',
    readiness: 'scaffolded', baseline: false, requires: ['copy variants'],
    note: 'A shorter variant of every string. "Dad is waiting" becomes "Dad". '
        + 'Written by hand, never generated.' },

  // ---- specified: decided, not started -------------------------------------
  { id: 'symbol_set', label: 'Picture symbols', channel: 'cognition',
    readiness: 'specified', baseline: false, requires: ['PCS or ARASAAC licence'],
    note: 'For a child who communicates with symbols. The signal is the right '
        + 'first surface for this because it is the smallest.' },
  { id: 'switch_access', label: 'Switch control', channel: 'motor',
    readiness: 'specified', baseline: false, requires: ['platform switch API'],
    note: 'One or two switches, scanning. The signal is already one target, which '
        + 'makes it the easiest surface in the product to support.' },
  { id: 'slow_tap', label: 'Longer to tap', channel: 'motor',
    readiness: 'specified', baseline: false, requires: [],
    note: 'Extends every timeout, including the 90-second expiry.' },
  { id: 'one_handed', label: 'One-handed reach', channel: 'motor',
    readiness: 'specified', baseline: false, requires: ['§5.26 docking'],
    note: 'Pins the prompt to the reachable half of the screen. The pane already '
        + 'docks, so most of this exists.' },

  // ---- considered: named so it is not forgotten -----------------------------
  { id: 'sign_video', label: 'Signed', channel: 'sight',
    readiness: 'considered', baseline: false, requires: ['recorded BSL/ASL clips'],
    note: 'Sixteen applications is a small enough vocabulary to record by hand. '
        + 'For a deaf child this is the difference between reading and being '
        + 'spoken to.' },
  { id: 'braille_display', label: 'Braille', channel: 'touch',
    readiness: 'considered', baseline: false, requires: ['BLE braille display'],
    note: 'Rare at five, not at fifteen. Named now so the string pipeline does '
        + 'not preclude it.' },
  { id: 'eye_gaze', label: 'Eye gaze', channel: 'motor',
    readiness: 'considered', baseline: false, requires: ['gaze hardware'],
    note: 'A single large dwell target is the easiest possible gaze surface.' },
];

export const form = (id: FormId) => FORMS.find(f => f.id === id) ?? null;

export const byReadiness = (r: Readiness) => FORMS.filter(f => f.readiness === r);
export const baselineForms = () => FORMS.filter(f => f.baseline);
export const shippedForms = () => byReadiness('shipped');

// ================================================ the two-channel rule ======
/**
 * **Every signal must be perceivable through at least two independent channels.**
 *
 * It is the product's only interruption pattern, so a sight-gated or hearing-gated
 * signal is a child who simply never learns her father wanted her.
 */
export const MIN_CHANNELS = 2;

export function channelsCovered(ids: FormId[]): Channel[] {
  const set = new Set<Channel>();
  for (const id of ids) {
    const f = form(id);
    if (f && f.readiness === 'shipped') set.add(f.channel);
  }
  return [...set];
}

export function perceivable(ids: FormId[]): { ok: boolean; channels: Channel[] } {
  const channels = channelsCovered(ids);
  return { ok: channels.length >= MIN_CHANNELS, channels };
}

/** The baseline set alone must satisfy the rule, before any option is enabled. */
export function baselineIsPerceivable(): boolean {
  return perceivable(baselineForms().map(f => f.id)).ok;
}

// ================================================ rolling one out ===========
export type PromoteError = 'unknown_form' | 'backwards' | 'unmet_requirement';

const ORDER: Readiness[] = ['considered', 'specified', 'scaffolded', 'shipped'];

/**
 * Readiness only ever moves forward, and only when its requirements are met.
 *
 * A form marked `shipped` with an unmet requirement is exactly the class of
 * declaration-without-implementation the F-series exists to catch, so it is
 * refused here rather than found later.
 */
export function promote(
  forms: Form[], id: FormId, to: Readiness, metRequirements: string[],
): { ok: true; forms: Form[] } | { ok: false; reason: PromoteError; missing?: string[] } {
  const f = forms.find(x => x.id === id);
  if (!f) return { ok: false, reason: 'unknown_form' };
  if (ORDER.indexOf(to) <= ORDER.indexOf(f.readiness)) {
    return { ok: false, reason: 'backwards' };
  }
  if (to === 'shipped') {
    const missing = f.requires.filter(r => !metRequirements.includes(r));
    if (missing.length) return { ok: false, reason: 'unmet_requirement', missing };
  }
  return { ok: true, forms: forms.map(x => x.id === id ? { ...x, readiness: to } : x) };
}

/** What is left to do, for a roadmap that stays honest. */
export function rollout(): {
  shipped: number; scaffolded: number; specified: number; considered: number;
  nextUp: { id: FormId; label: string; requires: string[] }[];
} {
  return {
    shipped: byReadiness('shipped').length,
    scaffolded: byReadiness('scaffolded').length,
    specified: byReadiness('specified').length,
    considered: byReadiness('considered').length,
    nextUp: byReadiness('scaffolded')
      .map(f => ({ id: f.id, label: f.label, requires: f.requires })),
  };
}

/**
 * A form may be added at any time without touching anything else — the matrix is
 * data, and every consumer reads it rather than hard-coding a list.
 */
export function addForm(forms: Form[], f: Form): Form[] {
  return forms.some(x => x.id === f.id) ? forms : [...forms, f];
}

// ============================================== per-signal rendering ========
export interface SignalPresentation {
  forms: FormId[];
  channels: Channel[];
  perceivable: boolean;
  /** Never sound alone, never colour alone. */
  soundOnly: false;
  colourOnly: false;
}

export function presentSignal(enabled: FormId[]): SignalPresentation {
  const forms = [...new Set([...baselineForms().map(f => f.id), ...enabled])];
  const p = perceivable(forms);
  return { forms, channels: p.channels, perceivable: p.ok,
    soundOnly: false, colourOnly: false };
}

export const PRESENTATION_FORBIDDEN = [
  'soundOnly', 'colourOnly', 'colorOnly', 'visualOnly', 'requiresSight',
  'requiresHearing',
] as const;

export function auditPresentation(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      const bad = (PRESENTATION_FORBIDDEN as readonly string[])
        .find(f => k.toLowerCase() === f.toLowerCase());
      if (bad && (x as Record<string, unknown>)[k] === true) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
