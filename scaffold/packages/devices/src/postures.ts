/**
 * MASTERFILE §8.12 — the layouts the postures implied.
 *
 * v0.32.0 declared nine postures and a `degradesTo` mechanism. Three of those
 * declarations had nothing behind them: the half-open Fold had no layout, tablets
 * had no landscape arrangement, and `court_export_request` — the degraded form the
 * audit demanded — existed only as a string.
 *
 * A declaration with nothing behind it is worse than an omission, because the
 * audit passes.
 */

export type Posture =
  | 'fold_cover' | 'fold_main' | 'fold_tabletop' | 'phone'
  | 'tablet_small' | 'tablet_medium' | 'tablet_large' | 'desktop' | 'dex';

export type Orientation = 'portrait' | 'landscape';

// ============================================ §8.12.1 the tabletop layout ===
/**
 * Half-open, the Fold stands by itself with the camera at eye level. The crease
 * runs horizontally across the middle in this posture, not vertically — so the
 * split is top/bottom rather than left/right, and it is a physical fold rather
 * than a design choice.
 *
 * **Video above, controls below.** Anything interactive placed above the crease
 * is on a surface angled away from her hands.
 */
export interface TabletopLayout {
  above: { region: 'video'; heightFraction: number };
  below: { region: 'controls'; heightFraction: number };
  /** The crease is a hinge, not a gutter — nothing may straddle it. */
  creaseAxis: 'horizontal';
  handsFree: true;
  note: string;
}

export const TABLETOP: TabletopLayout = {
  above: { region: 'video', heightFraction: 0.55 },
  below: { region: 'controls', heightFraction: 0.45 },
  creaseAxis: 'horizontal',
  handsFree: true,
  note: 'The only hands-free posture the hardware has. She can play on the floor '
      + 'while he watches, which is a different kind of call entirely.',
};

/** Nothing interactive above the hinge — it is angled away from her hands. */
export function tabletopPlacementOk(region: 'video' | 'controls', above: boolean): boolean {
  return above ? region === 'video' : true;
}

/** A call in tabletop mode should not end when she puts it down. */
export const TABLETOP_KEEPS_CALL_ALIVE = true;

// =========================================== §8.12.2 landscape on tablets ===
/**
 * Tablets are used in landscape more often than portrait — the opposite of a
 * phone. A portrait-only layout on a 10-inch tablet is the common case broken.
 */
export interface LandscapeArrangement {
  posture: Posture;
  /** Where the primary content goes when the device is wider than tall. */
  primary: 'left' | 'top';
  secondary: 'right' | 'bottom';
  /** Fraction given to primary. */
  split: number;
  note: string;
}

export const LANDSCAPE: LandscapeArrangement[] = [
  { posture: 'tablet_small', primary: 'left', secondary: 'right', split: 0.62,
    note: 'A 7-inch in landscape is 960x600 — one column of content and a rail.' },
  { posture: 'tablet_medium', primary: 'left', secondary: 'right', split: 0.58, note: '' },
  { posture: 'tablet_large', primary: 'left', secondary: 'right', split: 0.55,
    note: 'The common case for this size, not the exception.' },
  { posture: 'fold_main', primary: 'left', secondary: 'right', split: 0.5,
    note: 'Split on the crease, which is vertical when unfolded.' },
  { posture: 'fold_tabletop', primary: 'top', secondary: 'bottom', split: 0.55,
    note: 'The crease is HORIZONTAL here — the split follows the hinge.' },
  { posture: 'desktop', primary: 'left', secondary: 'right', split: 0.42, note: '' },
  { posture: 'dex', primary: 'left', secondary: 'right', split: 0.42, note: '' },
];

export const landscapeFor = (p: Posture) => LANDSCAPE.find(l => l.posture === p) ?? null;

/**
 * Rotating must never lose her place. Obvious, and the reason it is asserted is
 * that a child who loses a half-coloured picture by turning the tablet over does
 * not try again.
 */
export const ROTATION_PRESERVES_STATE = true;

export function onRotate<T>(state: T): T { return state; }

// ================================= §8.12.3 the degraded court export ========
/**
 * The audit demanded this by name and it did not exist.
 *
 * A certified export is a document-production task and genuinely wants width. But
 * **requesting** one is three fields, and the real case is a parent in a
 * solicitor's waiting room with a phone.
 */
export type ExportPurpose = 'court' | 'solicitor' | 'mediation' | 'own_records';

export interface ExportRequest {
  id: string;
  requestedBy: string;
  childId: string;
  purpose: ExportPurpose;
  fromDate: string;
  toDate: string;
  requestedAt: string;
  /** Ready when the wide review surface has something to show. */
  readyAt: string | null;
}

export const REQUEST_MIN_WIDTH = 320;
export const REVIEW_MIN_WIDTH = 600;

export type RequestError = 'inverted_range' | 'future_range';

export function requestExport(
  id: string, requestedBy: string, childId: string, purpose: ExportPurpose,
  fromDate: string, toDate: string, at: string,
): { ok: true; request: ExportRequest } | { ok: false; reason: RequestError } {
  if (toDate < fromDate) return { ok: false, reason: 'inverted_range' };
  if (fromDate > at.slice(0, 10)) return { ok: false, reason: 'future_range' };
  return { ok: true, request: { id, requestedBy, childId, purpose,
    fromDate, toDate, requestedAt: at, readyAt: null } };
}

/**
 * What he is told on a phone. It does not pretend he can review it there — the
 * honest version is better than a cramped one.
 */
export function requestConfirmation(r: ExportRequest): string {
  return 'We are putting it together. It needs a bigger screen to check through, '
       + 'so open Olive on a computer or a tablet when you are ready — it will be '
       + 'waiting.';
}

export function reviewableAt(width: number): boolean {
  return width >= REVIEW_MIN_WIDTH;
}

/** Requesting works at the floor. That is the whole point of the degraded form. */
export function requestableAt(width: number): boolean {
  return width >= REQUEST_MIN_WIDTH;
}

// ==================================================== §8.12.4 the web path ==
/**
 * §8.11.6 — there is no kiosk in a browser tab, so the **web client is
 * guardian-only**. That is settled. What was missing is the path a second parent
 * takes when they will not install anything.
 *
 * This matters more than it sounds: §17's whole adoption problem is a reluctant
 * second parent, and "download our app" is where a great many of them stop.
 */
export type WebCapability =
  | 'read_messages' | 'send_message' | 'join_call' | 'view_calendar'
  | 'view_expenses' | 'respond_to_inbox';

export const WEB_ALLOWED: WebCapability[] = [
  'read_messages', 'send_message', 'join_call', 'view_calendar',
  'view_expenses', 'respond_to_inbox',
];

/** Not on the web, and each for a reason rather than a limitation. */
export const WEB_DENIED = [
  { what: 'the child shell', because: 'no kiosk exists in a browser tab' },
  { what: 'homework capture', because: 'the camera pipeline is native' },
  { what: 'the archive download', because: 'it is a signed native transfer' },
] as const;

export function webCan(c: string): boolean {
  return (WEB_ALLOWED as readonly string[]).includes(c);
}

/**
 * A reluctant parent should be able to join a call and answer a message without
 * an install. Those two are the minimum viable relationship, and gating either
 * behind an app store is how a second parent quietly never joins.
 */
export const NO_INSTALL_MINIMUM: WebCapability[] = ['join_call', 'send_message'];

export function noInstallSufficient(): boolean {
  return NO_INSTALL_MINIMUM.every(c => webCan(c));
}

export const WEB_INVITE_COPY =
  'You can open this in a browser — nothing to install. If you would rather have '
  + 'the app later, it is there.';

/** §17.2 — the invitation must not read as a demand or a legal step. */
export const INVITE_BANNED = [
  'required', 'must', 'comply', 'obligated', 'court', 'legal', 'failure to',
  'you are required', 'deadline',
] as const;

export function auditInvite(text: string): { ok: true } | { ok: false; found: string[] } {
  const t = text.toLowerCase();
  const found = (INVITE_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}
