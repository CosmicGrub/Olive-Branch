/**
 * MASTERFILE §8.11 — the device matrix.
 *
 * The product has been designed against two viewports: a Galaxy Z Fold 5 folded
 * and unfolded. Everything else has been assumed.
 *
 * THE FINDING THAT MATTERS MOST IS IN §8.11.4. A great many separated families
 * hand a child a cheap Amazon Fire tablet, because it is £50 and it is
 * disposable. FireOS has **no Google Play Services**, therefore **no FCM**,
 * therefore — with the transport as it stands — a push notification is
 * constructed, dispatched, and silently goes nowhere.
 *
 * The child never learns her father sent her anything. There is no error, no
 * bounce, and no way for either of them to discover it. That is the worst class
 * of defect this product can have, and it was one `Platform` union away.
 */

// ================================================== §8.11.1 form factors ====
export type Posture =
  | 'fold_cover'      // folded: 344 x 882 CSS, extremely narrow
  | 'fold_main'       // unfolded: 673 x 841 CSS, nearly square
  | 'fold_tabletop'   // half-open, camera up — see below
  | 'phone'
  | 'tablet_small'    // 7", the cheap ones
  | 'tablet_medium'   // 8–9"
  | 'tablet_large'    // 10–11", used in landscape more often than not
  | 'desktop'
  | 'dex';            // Samsung DeX — the phone driving a monitor

export type Orientation = 'portrait' | 'landscape';

export interface Viewport { w: number; h: number }

export interface FormFactor {
  posture: Posture;
  label: string;
  /** The SMALLEST viewport this posture must work at, in CSS px. */
  min: Viewport;
  /** Orientations that actually occur in the wild for this posture. */
  orientations: Orientation[];
  /** Layout columns available at scale 1. */
  columns: 1 | 2 | 3;
  note: string;
}

export const FORM_FACTORS: FormFactor[] = [
  { posture: 'fold_cover', label: 'Fold, closed', min: { w: 344, h: 882 },
    orientations: ['portrait'], columns: 1,
    note: 'The narrowest thing we support. Every layout must survive 344 px.' },

  { posture: 'fold_main', label: 'Fold, open', min: { w: 673, h: 841 },
    orientations: ['portrait', 'landscape'], columns: 2,
    note: 'Nearly square. The crease runs down the centre, so two-column gutters '
        + 'are placed there deliberately.' },

  /**
   * §8.11.2 — the posture nothing uses and everything should.
   *
   * Half-open, the Fold stands by itself with the camera at roughly eye level. It
   * is the only hands-free call posture the hardware offers, and for a child that
   * is the difference between holding a phone for eleven minutes and playing on
   * the floor while her father watches.
   */
  { posture: 'fold_tabletop', label: 'Fold, half-open', min: { w: 673, h: 420 },
    orientations: ['landscape'], columns: 2,
    note: 'Stands by itself, camera at eye level. The only hands-free call posture '
        + 'the hardware has — video above the crease, controls below.' },

  { posture: 'phone', label: 'Ordinary phone', min: { w: 360, h: 640 },
    orientations: ['portrait'], columns: 1,
    note: 'A 360 px floor covers everything still sold.' },

  { posture: 'tablet_small', label: '7-inch tablet', min: { w: 600, h: 960 },
    orientations: ['portrait', 'landscape'], columns: 1,
    note: 'The cheap ones. Often the child\'s only device, and often FireOS.' },

  { posture: 'tablet_medium', label: '8-inch tablet', min: { w: 768, h: 1024 },
    orientations: ['portrait', 'landscape'], columns: 2, note: '' },

  { posture: 'tablet_large', label: '10-inch tablet', min: { w: 800, h: 1280 },
    orientations: ['portrait', 'landscape'], columns: 2,
    note: 'Used in LANDSCAPE more often than portrait — the opposite of a phone, '
        + 'and the assumption most layouts get wrong.' },

  { posture: 'desktop', label: 'PC', min: { w: 1024, h: 640 },
    orientations: ['landscape'], columns: 3,
    note: 'Resizable, so the floor is what matters. Windows, and it is where the '
        + 'guardian shell is genuinely comfortable.' },

  { posture: 'dex', label: 'Samsung DeX', min: { w: 1280, h: 720 },
    orientations: ['landscape'], columns: 3,
    note: 'The Fold driving a monitor with a mouse. A desktop that is also a phone, '
        + 'which breaks the assumption that platform implies input.' },
];

/** The narrowest thing supported, anywhere. Every layout is checked against it. */
export const NARROWEST = Math.min(...FORM_FACTORS.map(f => f.min.w));

export const factor = (p: Posture) => FORM_FACTORS.find(f => f.posture === p) ?? null;

export function postureFor(v: Viewport): Posture {
  const landscape = v.w > v.h;
  if (v.w >= 1280 && landscape) return 'dex';
  if (v.w >= 1024) return 'desktop';
  if (v.w >= 800) return 'tablet_large';
  if (v.w >= 768) return 'tablet_medium';
  // A short, wide, mid-size viewport is the Fold standing half-open.
  if (v.w >= 600 && landscape && v.h <= 480) return 'fold_tabletop';
  if (v.w >= 600) return v.w >= 660 && v.h < 900 ? 'fold_main' : 'tablet_small';
  if (v.w <= 400 && v.h >= 800) return 'fold_cover';
  return 'phone';
}

/**
 * Columns are computed from the EFFECTIVE width — viewport divided by text scale —
 * because a 10-inch tablet at 2.0× type has the effective width of a phone. §8.8.
 */
export function columnsAt(v: Viewport, textScale = 1): 1 | 2 | 3 {
  const eff = v.w / textScale;
  if (eff >= 1024) return 3;
  if (eff >= 660) return 2;
  return 1;
}

// ===================================================== §8.11.3 input ========
export type Input = 'touch' | 'mouse' | 'keyboard' | 'stylus' | 'dpad';

export const INPUTS_BY_POSTURE: Record<Posture, Input[]> = {
  fold_cover: ['touch'],
  fold_main: ['touch', 'stylus'],
  fold_tabletop: ['touch', 'stylus'],
  phone: ['touch'],
  tablet_small: ['touch'],
  tablet_medium: ['touch', 'stylus'],
  tablet_large: ['touch', 'stylus', 'keyboard'],
  desktop: ['mouse', 'keyboard'],
  dex: ['mouse', 'keyboard', 'touch'],
};

/**
 * Touch targets are 64 dp (§8.4). A mouse is precise, so 32 is defensible — but
 * a child using a mouse is still a child, so the floor only relaxes on surfaces
 * no child ever sees.
 */
export const TOUCH_TARGET_DP = 64;
export const MOUSE_TARGET_DP = 32;

export function targetFloor(inputs: Input[], childFacing: boolean): number {
  if (childFacing) return TOUCH_TARGET_DP;
  return inputs.includes('touch') ? TOUCH_TARGET_DP : MOUSE_TARGET_DP;
}

/**
 * The S Pen changes two features materially and nothing else. Saying so keeps it
 * from becoming a platform fork.
 */
export const STYLUS_IMPROVES = ['annotation_canvas', 'homework_markup'] as const;

export function stylusAvailable(p: Posture): boolean {
  return INPUTS_BY_POSTURE[p].includes('stylus');
}

/** No feature may REQUIRE a stylus — it is an improvement, never a gate. */
export function stylusRequired(): false { return false; }

// ============================================ §8.11.4 delivery channels =====
/**
 * The finding.
 *
 * This is the STATIC half of §8.11.4: given only a channel, is push even
 * possible, and what does the guardian get told. The DYNAMIC half — given a
 * channel PLUS real-time state (is the app foregrounded, is a socket held,
 * how long has an item waited), which route fires right now — lives in
 * `packages/transport/src/channels.ts`'s `route()`/`reachability()`. That
 * file imports `Channel`/`CHANNELS`/`capability` from here rather than
 * redeclaring them (fixed v0.49.11, after the redeclaration had silently
 * drifted — `channels.ts`'s own header tells that story). This file is the
 * one place a channel's push/fallback facts are decided; nowhere else
 * should declare a second copy.
 *
 * Wired into real push dispatch as of v0.49.11 —
 * `packages/transport/src/notify.ts`'s `notifyDevices()` now calls
 * `admitDevice()` per device before attempting FCM/APNs, and skips the send
 * (rather than firing it into a device that cannot receive it) when
 * `!capability.push`. What is still NOT real: `device_token` only learns a
 * device's precise channel (`android_play` vs `android_amazon` vs
 * `android_bare`) if the CLIENT reports one, and no client code anywhere
 * detects this today — `client/lib/push_channel.dart` only ever knows
 * "ios" or "android," never which flavor of Android. Real, credential-free
 * on-device APIs exist to detect it for real (`GoogleApiAvailability
 * .isGooglePlayServicesAvailable()` for Play Services presence;
 * `PackageManager.getInstallSourceInfo()`/`getInstallerPackageName()` for
 * store attribution — `com.android.vending` for Play, `com.amazon.venezia`
 * for the Amazon Appstore), and a real MethodChannel bridge for it would
 * follow the exact precedent `KioskBridge.kt`/`WearSyncBridge.kt` already
 * set. Scoped and explicitly declined this pass, for the same reason
 * `LOCK_METHODS`/`childShellAllowed()` wiring was declined in the same
 * gap-fill pass (see CHANGELOG v0.49.10's "Found, not fixed" note): every
 * existing MethodChannel bridge in this repo is `UNVERIFIED (no Flutter
 * toolchain)` by its own header, and writing a brand-new, uncompilable
 * native bridge and calling channel detection "solved" would be exactly the
 * fabrication this codebase's house rule forbids. Building it once would
 * unblock BOTH this gap and `LOCK_METHODS`' — they are blocked on the
 * identical missing piece.
 */
export type Channel =
  | 'android_play'    // FCM
  | 'android_amazon'  // FireOS — NO Play Services, NO FCM
  | 'android_bare'    // de-Googled / China / GrapheneOS — no FCM
  | 'ios'             // APNS
  | 'windows'         // WNS, or a foreground socket
  | 'web';            // Web Push, patchy

export interface ChannelCapability {
  channel: Channel;
  push: boolean;
  /** How the child hears about a message when push is unavailable. */
  fallback: 'foreground_socket_and_sms' | 'foreground_socket' | 'none';
  note: string;
}

export const CHANNELS: ChannelCapability[] = [
  { channel: 'android_play', push: true, fallback: 'foreground_socket',
    note: 'FCM.' },
  { channel: 'android_amazon', push: false, fallback: 'foreground_socket_and_sms',
    note: 'FireOS has no Play Services. A great many families use a £50 Fire '
        + 'tablet as the child\'s device, and with FCM alone every notification '
        + 'would be built, dispatched and silently discarded.' },
  { channel: 'android_bare', push: false, fallback: 'foreground_socket_and_sms',
    note: 'De-Googled Android. Same failure, rarer cause.' },
  { channel: 'ios', push: true, fallback: 'foreground_socket', note: 'APNS.' },
  { channel: 'windows', push: true, fallback: 'foreground_socket',
    note: 'WNS where available; the desktop client holds a socket regardless.' },
  { channel: 'web', push: false, fallback: 'foreground_socket',
    note: 'Web Push is too inconsistent to rely on for a child hearing from a parent.' },
];

export const capability = (c: Channel) => CHANNELS.find(x => x.channel === c)!;

export type AdmitError = 'silent_device';

/**
 * **A device that can neither push nor fall back is refused.**
 *
 * Not warned about — refused. A silent device is worse than no device: the parent
 * believes he is reaching her, she believes he has not written, and nothing in
 * either interface says otherwise. It is the one failure mode where both people
 * are misled at once and neither can discover it.
 */
export function admitDevice(
  c: Channel,
): { ok: true; capability: ChannelCapability } | { ok: false; reason: AdmitError; note: string } {
  const cap = capability(c);
  if (!cap.push && cap.fallback === 'none') {
    return { ok: false, reason: 'silent_device',
      note: 'This device cannot receive a notification and has no fallback. She '
          + 'would never know he had written, and he would never know she had not '
          + 'been told.' };
  }
  return { ok: true, capability: cap };
}

/** What a guardian is told when the child's device cannot push. Plain, not alarming. */
export function channelAdvice(c: Channel): string | null {
  const cap = capability(c);
  if (cap.push) return null;
  return cap.fallback === 'foreground_socket_and_sms'
    ? 'Her tablet cannot show pop-up alerts, so she sees new things when she opens '
    + 'Olive — and we can text the grown-up there if something is waiting.'
    : 'Her device cannot show pop-up alerts. She sees new things when she opens Olive.';
}

// ================================================ §8.11.5 performance =======
/**
 * A £50 tablet with 2 GB of RAM is a real device in this market, and a video call
 * at 720p will drop frames on it until the child gives up.
 *
 * Tiers cap what is attempted rather than letting it fail at runtime.
 */
export type Tier = 'low' | 'mid' | 'high';

export interface TierSpec {
  tier: Tier;
  ramGb: number;
  videoHeight: 180 | 360 | 720;
  fps: 15 | 24 | 30;
  /** Animation is the first thing to go, and nothing in this product needs it. */
  animation: boolean;
  /** Simultaneous video + a shared canvas is genuinely heavy. */
  concurrentCanvas: boolean;
  note: string;
}

export const TIERS: TierSpec[] = [
  { tier: 'low', ramGb: 2, videoHeight: 180, fps: 15, animation: false,
    concurrentCanvas: false,
    note: 'A cheap 7-inch tablet. 180p at 15 fps is a recognisable face, which is '
        + 'the whole requirement — a call that connects beats a call that looks good.' },
  { tier: 'mid', ramGb: 4, videoHeight: 360, fps: 24, animation: true,
    concurrentCanvas: true, note: '' },
  { tier: 'high', ramGb: 6, videoHeight: 720, fps: 30, animation: true,
    concurrentCanvas: true, note: 'Fold 5, current tablets, any PC.' },
];

export function tierFor(ramGb: number): Tier {
  return ramGb >= 6 ? 'high' : ramGb >= 4 ? 'mid' : 'low';
}

export const spec = (t: Tier) => TIERS.find(x => x.tier === t)!;

/** Degrade the call, never refuse it. A blurry parent is a parent. */
export function callSettings(t: Tier): { height: number; fps: number; canvas: boolean } {
  const s = spec(t);
  return { height: s.videoHeight, fps: s.fps, canvas: s.concurrentCanvas };
}

// ================================================= §8.11.6 lock-down ========
/**
 * Kiosk works differently on every platform, and one of them cannot be enabled
 * remotely at all — which is a product constraint, not a footnote.
 */
export interface LockMethod {
  channel: Channel;
  method: string;
  /** Can a parent turn this on from their own device? */
  remotelyEnabled: boolean;
  note: string;
}

export const LOCK_METHODS: LockMethod[] = [
  { channel: 'android_play', method: 'Device Owner / screen pinning',
    remotelyEnabled: true, note: 'Full lock where the app is device owner.' },
  { channel: 'android_amazon', method: 'Amazon Kids profile',
    remotelyEnabled: false,
    note: 'Set up once, on the device, by the adult holding it. FireOS does not '
        + 'expose Device Owner to third-party apps.' },
  { channel: 'android_bare', method: 'screen pinning', remotelyEnabled: false,
    note: '' },
  { channel: 'ios', method: 'Guided Access', remotelyEnabled: false,
    note: 'Guided Access CANNOT be enabled remotely or programmatically. A parent '
        + 'must switch it on by hand, and the product must say so rather than '
        + 'implying a lock it cannot deliver.' },
  { channel: 'windows', method: 'Assigned Access', remotelyEnabled: true, note: '' },
  { channel: 'web', method: 'none', remotelyEnabled: false,
    note: 'There is no kiosk in a browser tab. The web client is guardian-only.' },
];

export const lockMethod = (c: Channel) => LOCK_METHODS.find(x => x.channel === c)!;

/**
 * The web client is guardian-only, and that is a rule rather than a gap: a child
 * shell with no lock is a child shell that can be navigated out of in one tap.
 */
export function childShellAllowed(c: Channel): boolean {
  return lockMethod(c).method !== 'none';
}

// =================================================== §8.11.7 the audit ======
export interface LayoutClaim {
  surface: string;
  /** Minimum CSS width this surface needs, at scale 1. */
  needsWidth: number;
  childFacing: boolean;
  orientations: Orientation[];
  /**
   * Some surfaces genuinely are not for a 344 px screen — a certified court
   * export is a document-production task. Saying so is honest; **breaking is
   * not.** A wide surface must declare what it degrades to, and the audit fails
   * it otherwise.
   *
   * The real case: a parent needs to produce an export in a solicitor's waiting
   * room, on a phone. Requesting it must work there even if reviewing it does
   * not.
   */
  degradesTo?: string;
}

export interface MatrixFault { surface: string; posture: Posture; fault: string }

/**
 * The whole point of declaring the matrix: a surface that needs more room than
 * the narrowest supported device is a bug that only appears on the cheapest
 * hardware, in the poorest household, on the child's side.
 */
export function auditLayouts(
  claims: LayoutClaim[], implemented: Set<string> = new Set(),
): { ok: boolean; faults: MatrixFault[] } {
  const faults: MatrixFault[] = [];
  for (const c of claims) {
    // A declared degraded form that IS implemented satisfies the width rule.
    const covered = Boolean(c.degradesTo && implemented.has(c.degradesTo));
    for (const f of FORM_FACTORS) {
      if (c.childFacing && f.posture === 'desktop') continue;   // guardian-only
      if (covered && c.needsWidth > f.min.w) continue;
      if (c.needsWidth > f.min.w) {
        faults.push({ surface: c.surface, posture: f.posture,
          fault: c.degradesTo
            ? `needs ${c.needsWidth}px, has ${f.min.w}px — and no degraded form `
              + `is implemented for "${c.degradesTo}"`
            : `needs ${c.needsWidth}px, has ${f.min.w}px, and declares no degraded form` });
      }
      const landscapeOnly = f.orientations.length === 1 && f.orientations[0] === 'landscape';
      if (landscapeOnly && !c.orientations.includes('landscape')) {
        faults.push({ surface: c.surface, posture: f.posture,
          fault: 'no landscape layout, and this posture is landscape-only' });
      }
    }
  }
  return { ok: faults.length === 0, faults };
}

/** Every posture must be reachable from a viewport, or it is decorative. */
export function postureCoverage(): { posture: Posture; reachable: boolean }[] {
  const probes: Viewport[] = [
    { w: 344, h: 882 }, { w: 673, h: 841 }, { w: 700, h: 440 },
    { w: 360, h: 740 }, { w: 600, h: 1024 }, { w: 768, h: 1024 },
    { w: 800, h: 1280 }, { w: 1100, h: 700 }, { w: 1400, h: 800 },
  ];
  const hit = new Set(probes.map(postureFor));
  return FORM_FACTORS.map(f => ({ posture: f.posture, reachable: hit.has(f.posture) }));
}
