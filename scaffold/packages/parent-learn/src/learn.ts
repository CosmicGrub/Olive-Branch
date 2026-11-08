/**
 * PARENT LEARN — guardian-only education content and its privacy rules.
 * Research: docs/superpowers/specs/2026-11-07-parenting-styles-education-research.md
 * Mockups:  docs/superpowers/mockups/parent-learn-suite-mockups.html
 *
 * Pure logic only (same posture as co-view): no I/O, no clock, no storage.
 * Owner decisions 2026-11-07: the Learn tab is yes; private reflection, cultural
 * framing, the two-home rules list and the message check are each OPTIONAL
 * (a guardian opts in; the defaults are the most private choice).
 *
 *  L1  Guardian-only. A child, a sitter or any non-guardian never reads Learn
 *      content or settings. (The child shell has no Learn surface at all.)
 *  L2  A reflection belongs to the guardian who made it. Not the co-guardian,
 *      not anyone else. There is deliberately no export or share function here
 *      (a stored reflection could become evidence in a dispute).
 *  L3  Every card carries an evidence label and at least one https source, and
 *      never claims a style CAUSES an outcome or labels a person.
 *  L4  The message check is off unless the guardian turned it on, runs on the
 *      text it is handed, and returns hints only. It never stores, sends or
 *      logs anything, and it never rewrites a message by itself.
 *  L5  The two-home rules list shares only core-rule categories the guardian
 *      chose, never a style, a reflection or a setting.
 */

export type Evidence = 'strong' | 'moderate' | 'weak' | 'contested';
export const EVIDENCE_LEVELS: readonly Evidence[] = ['strong', 'moderate', 'weak', 'contested'];

export interface Source { label: string; url: string }
export interface Card {
  id: string;
  topic: 'style' | 'discipline' | 'communication' | 'conflict' | 'coparenting' | 'repair';
  title: string;
  body: string;
  evidence: Evidence;
  sources: readonly Source[];
  /** Ages (years) the card is written for; omitted = all. */
  ages?: readonly [number, number];
}

const AAP = { label: 'AAP: Disciplining Your Child', url: 'https://www.healthychildren.org/English/family-life/family-dynamics/communication-discipline/Pages/Disciplining-Your-Child.aspx' };
const CHAO = { label: 'Chao 1994', url: 'https://aacdrpubs.faculty.ucdavis.edu/wp-content/uploads/sites/211/2015/03/chao001.pdf' };
const DS93 = { label: 'Darling and Steinberg 1993', url: 'https://data.zhenzhi.com/details/1/1001468350' };
const AK14 = { label: 'Avinun and Knafo 2014', url: 'https://cris.huji.ac.il/en/publications/parenting-as-a-reaction-evoked-by-childrens-genotype-a-meta-analy/' };
const ND = { label: 'Notre Dame: couples and kids', url: 'https://shaw.nd.edu/research/couples-and-kids' };
const PD = { label: 'ParentData: is gentle parenting evidence-based', url: 'https://parentdata.org/ask/is-gentle-parenting-evidence-based-does-it-actually-work' };
const TRIPLE_P = { label: 'Emotion-enhanced Triple P thesis', url: 'https://openaccess.wgtn.ac.nz/articles/thesis/Integrating_emotion_into_behaviourally-based_parenting_programmes_can_this_enhance_outcomes_for_child_conduct_problems_/17006110' };
const BIELEFELD = { label: 'Bielefeld longitudinal study', url: 'https://pub.uni-bielefeld.de/record/1591258' };
const FATHERHOOD = { label: 'Fatherhood Institute briefing', url: 'https://fatherhoodinstitute.org/_files/ugd/efff1d_dc63e949baaa4de2ac96d5b562234262.pdf' };

export const CARDS: readonly Card[] = [
  { id: 'two-dimensions', topic: 'style', title: 'Two things, not four boxes',
    body: 'Home feels like a mix of warmth and expectations. The four named styles are corners of that map, not types of person. Most days you move around it.',
    evidence: 'strong', sources: [DS93] },
  { id: 'warm-and-clear', topic: 'style', title: 'Warm and clear',
    body: 'Children tend to do well on school, mood and friendships when warmth and clear limits go together. This is a link in studies, not a promise, and it is not risk-free.',
    evidence: 'moderate', sources: [DS93, PD] },
  { id: 'climate-and-tools', topic: 'style', title: 'Climate and tools',
    body: 'Style is the emotional climate. Practices are the tools. The same tool, such as a time-out, lands differently in a warm home than in a cold one.',
    evidence: 'moderate', sources: [DS93] },
  { id: 'child-shapes-parent', topic: 'style', title: 'Children shape parents too',
    body: 'Twin studies estimate that about a quarter of the variation in parenting is driven by the child. Parent and child influence each other, so nobody is to blame for the whole picture.',
    evidence: 'strong', sources: [AK14] },
  { id: 'culture-changes-meaning', topic: 'style', title: 'Culture changes the meaning',
    body: 'A firm, high-expectation style can mean care and training in some families and coldness in others. Research found the same style linked to opposite school results in different communities.',
    evidence: 'contested', sources: [CHAO] },
  { id: 'gentle-with-limits', topic: 'style', title: 'Gentle means kind and firm',
    body: 'Gentle parenting has no studies of its own. Its ingredients, warmth, validation and limits that are held, match research on authoritative parenting. The risk is dropping the limits. Check: did I say the limit, and did I hold it?',
    evidence: 'weak', sources: [PD] },
  { id: 'short-time-out', topic: 'discipline', title: 'A short, calm time-out',
    body: 'Name what happened, use a boring safe spot, stay calm and quiet, then reconnect. About one minute per year of age. Skip long isolation and punishing tears.',
    evidence: 'strong', sources: [AAP], ages: [2, 8] },
  { id: 'avoid-hitting', topic: 'discipline', title: 'Hitting does not teach',
    body: 'Pediatric guidance advises against physical punishment. It is less effective than time-outs or losing a privilege and is linked to more defiance.',
    evidence: 'strong', sources: [AAP] },
  { id: 'specific-praise', topic: 'discipline', title: 'Specific praise',
    body: 'Name the thing they did. "You shared the red block" lands better than "good boy".',
    evidence: 'moderate', sources: [AAP], ages: [3, 8] },
  { id: 'plain-instructions', topic: 'communication', title: 'Say it plainly',
    body: 'If it is an instruction, say it as one, once, in specific words. "Shoes on, please" works better than "Can you put your shoes on?"',
    evidence: 'moderate', sources: [AAP] },
  { id: 'emotion-coaching', topic: 'communication', title: 'Naming feelings',
    body: "Emotion coaching reliably changes what parents do. Evidence that it improves 5 to 7 year olds' emotion skills is still thin and mostly parent-reported.",
    evidence: 'weak', sources: [TRIPLE_P], ages: [4, 8] },
  { id: 'how-parents-fight', topic: 'conflict', title: 'How you disagree matters most',
    body: 'Hostility and withdrawal between parents are linked to more child problems because a child may feel the family is unsafe. Calm disagreement that gets resolved is not harmful.',
    evidence: 'strong', sources: [ND] },
  { id: 'out-of-the-middle', topic: 'coparenting', title: 'Keep your child out of the middle',
    body: 'No messengers, no questions about the other home, no criticism of the other parent in earshot.',
    evidence: 'strong', sources: [ND] },
  { id: 'rules-that-match', topic: 'coparenting', title: 'What is worth matching',
    body: 'Core routines such as bedtime, screens, homework and safety are the better-supported place to line up. Evidence that matching whole styles matters is mixed, and low conflict matters more.',
    evidence: 'moderate', sources: [BIELEFELD, FATHERHOOD] },
  { id: 'repair', topic: 'repair', title: 'After you lost your temper',
    body: 'Calm yourself first, go back and name it, say it was yours, then reconnect. Mistakes happen. A mistake does not make anyone bad.',
    evidence: 'strong', sources: [AAP] },
  { id: 'siblings', topic: 'discipline', title: 'When siblings fight',
    body: 'Step in only if someone could be hurt. Name each feeling, ask what they could try, then notice the fix. Common practice, but no sibling-specific trials were found.',
    evidence: 'weak', sources: [AAP], ages: [4, 8] },
];

// ---------------------------------------------------------------- principals
export interface Principal { kind: 'guardian' | 'child' | 'adult'; id: string }

/** L1 */
export function canReadLearn(p: Principal | null | undefined): boolean {
  return !!p && typeof p === 'object' && p.kind === 'guardian';
}

/** L2: only the guardian who made a reflection may read it. */
export function canReadReflection(p: Principal | null | undefined, ownerId: string): boolean {
  return canReadLearn(p) && typeof ownerId === 'string' && ownerId.length > 0 && p!.id === ownerId;
}

// ------------------------------------------------------------------ settings
export type ReflectionMode = 'off' | 'session' | 'saved';
export type Framing = 'neutral' | 'culture-note' | 'values-first';
export interface LearnSettings {
  reflection: ReflectionMode;
  framing: Framing;
  rulesList: boolean;
  messageCheck: boolean;
}
/** Most private choice for every optional feature. */
export const DEFAULT_SETTINGS: Readonly<LearnSettings> = Object.freeze({
  reflection: 'session', framing: 'neutral', rulesList: false, messageCheck: false,
});

const REFLECTION: readonly string[] = ['off', 'session', 'saved'];
const FRAMING: readonly string[] = ['neutral', 'culture-note', 'values-first'];

/** Untrusted input: unknown or wrongly-typed fields fall back to the default. */
export function parseSettings(raw: unknown): LearnSettings {
  const o = (raw && typeof raw === 'object' && !Array.isArray(raw)) ? raw as Record<string, unknown> : {};
  return {
    reflection: REFLECTION.includes(o.reflection as string) ? o.reflection as ReflectionMode : DEFAULT_SETTINGS.reflection,
    framing: FRAMING.includes(o.framing as string) ? o.framing as Framing : DEFAULT_SETTINGS.framing,
    rulesList: o.rulesList === true,
    messageCheck: o.messageCheck === true,
  };
}

/** Whether a reflection may be written to storage at all. */
export function mayStoreReflection(s: LearnSettings): boolean { return s.reflection === 'saved'; }

// ---------------------------------------------------------------- reflection
export interface DayMirror { headline: string; prompt: string }
const clamp100 = (n: number) => (typeof n === 'number' && Number.isFinite(n)) ? Math.min(100, Math.max(0, n)) : 50;

/** Describes the day, never the person. No label, no score. */
export function describeDay(warmth: number, expectations: number): DayMirror {
  const hw = clamp100(warmth) >= 50, he = clamp100(expectations) >= 50;
  if (hw && he) return { headline: 'Warm, with clear limits.', prompt: 'Notice: what made that possible today?' };
  if (!hw && he) return { headline: 'Firm today, with less warmth.', prompt: 'Notice: what was going on for you? One small warm moment can change the day.' };
  if (hw && !he) return { headline: 'Warm today, with looser limits.', prompt: 'Notice: was it a choice, or were you tired? One clear limit may be enough.' };
  return { headline: 'Low on both today.', prompt: 'Notice: are you okay? Support is fine to ask for. Tomorrow is a fresh day.' };
}

// -------------------------------------------------------------- card queries
/** L1 + framing: framing 'culture-note' appends the culture reminder to style cards. */
export function cardsFor(p: Principal | null | undefined, s: LearnSettings, age?: number): Card[] {
  if (!canReadLearn(p)) return [];
  return CARDS
    .filter((c) => age === undefined || !c.ages || (age >= c.ages[0] && age <= c.ages[1]))
    .map((c) => s.framing === 'culture-note' && c.topic === 'style' && c.id !== 'culture-changes-meaning'
      ? { ...c, body: c.body + ' What this means can differ by family and culture.' } : c);
}

const CAUSAL = /\b(causes?|caused|produces?|makes? your child|will make|guarantees?)\b/i;
const LABEL_PERSON = /\byou are (a|an) (permissive|authoritarian|authoritative|neglectful|bad|lazy|helicopter)\b/i;

/** L3: returns a list of violations; an empty list means the content passes. */
export function lintCards(cards: readonly Card[]): string[] {
  const out: string[] = [];
  const ids = new Set<string>();
  for (const c of cards) {
    if (ids.has(c.id)) out.push(`${c.id}: duplicate id`);
    ids.add(c.id);
    if (!EVIDENCE_LEVELS.includes(c.evidence)) out.push(`${c.id}: bad evidence label`);
    if (!c.sources.length) out.push(`${c.id}: no source`);
    for (const s of c.sources) if (!/^https:\/\//.test(s.url)) out.push(`${c.id}: non-https source`);
    if (CAUSAL.test(c.body) || CAUSAL.test(c.title)) out.push(`${c.id}: causal claim`);
    if (LABEL_PERSON.test(c.body) || LABEL_PERSON.test(c.title)) out.push(`${c.id}: labels a person`);
    if (/\brisks?:\s*none\b|\bno risks?\b/i.test(c.body)) out.push(`${c.id}: claims no risk`);
  }
  return out;
}

// ------------------------------------------------------------- message check
export type MessageFlag = 'blame' | 'absolute' | 'contempt' | 'child-messenger' | 'questioning-child' | 'threat';
export interface MessageHint { flag: MessageFlag; hint: string }

const RULES: readonly { flag: MessageFlag; re: RegExp; hint: string }[] = [
  { flag: 'absolute', re: /\byou (always|never)\b/i, hint: 'Try the one thing that happened: "On Friday bedtime was late."' },
  { flag: 'blame', re: /\b(your fault|because of you|you('| a)re (the reason|to blame))\b/i, hint: 'Describe the effect, not who is at fault.' },
  { flag: 'contempt', re: /\b(idiot|stupid|pathetic|useless|incompetent|worthless)\b/i, hint: 'Leave out the insult. It makes the real point harder to hear.' },
  { flag: 'child-messenger', re: /\b(tell|ask) (your|the) (dad|mom|mum|mother|father|parent)\b|\bhave (her|him|them) tell\b/i, hint: 'Send this to the other guardian directly. Please keep the child out of it.' },
  { flag: 'questioning-child', re: /\bask (her|him|them|\w+) what (dad|mom|mum|mother|father|he|she)\b/i, hint: 'Please do not question the child about the other home.' },
  { flag: 'threat', re: /\b(i('| wi)ll (take|see you in)|you('| wi)ll regret|or else)\b/i, hint: 'Say what you need and by when, without a threat.' },
];
export const MAX_CHECK_CHARS = 4000;

/**
 * L4. Returns null unless the guardian opted in. Never stores or sends. Hints
 * only: a rewrite is the guardian's to write.
 */
export function checkMessage(p: Principal | null | undefined, s: LearnSettings, text: unknown): MessageHint[] | null {
  if (!canReadLearn(p) || !s.messageCheck) return null;
  if (typeof text !== 'string') return [];
  const t = text.length > MAX_CHECK_CHARS ? text.slice(0, MAX_CHECK_CHARS) : text;
  const out: MessageHint[] = [];
  for (const r of RULES) if (r.re.test(t) && !out.some((h) => h.flag === r.flag)) out.push({ flag: r.flag, hint: r.hint });
  return out;
}

// --------------------------------------------------------- two-home rules list
export const RULE_CATEGORIES = ['bedtime', 'screens', 'homework', 'safety'] as const;
export type RuleCategory = typeof RULE_CATEGORIES[number];
export interface RuleItem { category: RuleCategory; text: string }

/** L5. Empty unless the guardian opted in; only known categories, bounded text, nothing else. */
export function shareableRules(p: Principal | null | undefined, s: LearnSettings, items: unknown): RuleItem[] {
  if (!canReadLearn(p) || !s.rulesList || !Array.isArray(items)) return [];
  const out: RuleItem[] = [];
  for (const it of items.slice(0, 20)) {
    if (!it || typeof it !== 'object') continue;
    const { category, text } = it as Record<string, unknown>;
    if (typeof category !== 'string' || !(RULE_CATEGORIES as readonly string[]).includes(category)) continue;
    if (typeof text !== 'string' || !text.trim()) continue;
    out.push({ category: category as RuleCategory, text: text.trim().slice(0, 200) });
  }
  return out;
}
