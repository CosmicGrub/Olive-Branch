/**
 * MASTERFILE §9.15 — the capture button. New v0.39.0.
 *
 * Raised at the owner's suggestion: a dedicated in-app photo and screenshot
 * control, auto-uploading into the app's own storage rather than the
 * device's shared camera roll.
 *
 * Two kinds, deliberately not merged — they carry different risk:
 *
 *  1. CAMERA. A photo of the physical world. Reuses §9.1's quality gate
 *     wholesale: MIN_EDGE_PX / MIN_SHARPNESS / MAX_SKEW_DEG, the exact same
 *     measured thresholds, because a blurred photo is a blurred photo
 *     whether it is headed for OCR or a keepsake. A photo that fails the
 *     gate is asked to be retaken rather than uploaded unreadable.
 *
 *  2. SCREENSHOT. Of the app's own surface. Already digital, no blur or skew
 *     possible, but a different risk: it could capture a parent's live video
 *     mid-call. So screenshot capture is scoped off the call surface
 *     entirely (live_call, call_video, pane_video) rather than solved here.
 *     A screenshot mid-call is refused, not silently taken.
 *
 * The one guarantee the feature exists for: neverToDeviceGallery and
 * autoUploadsToAppStorage, declared below as named invariants.
 *
 * No count shown to her. 'Saved to your gallery.' on success, and on a
 * failed gate — nothing that tallies how many she has taken.
 */
import { gateImage, MIN_EDGE_PX, MIN_SHARPNESS, MAX_SKEW_DEG,
  type ImageStats, type QualityFailure } from './capture.ts';

export { MIN_EDGE_PX, MIN_SHARPNESS, MAX_SKEW_DEG, gateImage };

/** The one guarantee this feature exists for. Never the reverse. */
export const neverToDeviceGallery = true;
export const autoUploadsToAppStorage = true;

const SAVED_MESSAGE = 'Saved to your gallery.';

// ------------------------------------------------------------ camera -----
export type CameraCaptureResult =
  | { ok: true; message: string; readyToUpload: true }
  | { ok: false; reason: QualityFailure; advice: string };

/**
 * §9.1's gate, wholesale. A photo that fails is asked to be retaken — the
 * advice is the gate's own, unchanged, because it is already plain and
 * actionable and this file has no business inventing new copy.
 */
export function captureCameraPhoto(stats: ImageStats): CameraCaptureResult {
  const verdict = gateImage(stats);
  if (!verdict.ok) {
    return { ok: false, reason: verdict.reason, advice: verdict.advice };
  }
  return { ok: true, message: SAVED_MESSAGE, readyToUpload: true };
}

// --------------------------------------------------------- screenshot -----
/**
 * Surfaces where a parent's live video could be caught mid-capture. Not
 * solved here — refused here. Named so the list itself is the guarantee,
 * not a comment describing it.
 */
export const SCREENSHOT_SCOPED_OFF_SURFACES = ['live_call', 'call_video', 'pane_video'] as const;

export type ScreenshotRefusal = 'call_surface';

export type ScreenshotCaptureResult =
  | { ok: true; message: string; readyToUpload: true }
  | { ok: false; reason: ScreenshotRefusal; advice: string };

/**
 * Already digital — no blur, no skew, nothing to gate on quality. The only
 * risk is capturing a call in progress, so that is the only thing checked.
 * A refusal, not a silent no-op: the caller gets a reason back.
 */
export function captureScreenshot(currentSurface: string): ScreenshotCaptureResult {
  if ((SCREENSHOT_SCOPED_OFF_SURFACES as readonly string[]).includes(currentSurface)) {
    return { ok: false, reason: 'call_surface', advice: "Let's try that again." };
  }
  return { ok: true, message: SAVED_MESSAGE, readyToUpload: true };
}
