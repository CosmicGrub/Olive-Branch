// OLIVE BRANCH — the camera, the speaker, and P10. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §5.24.
//
// A 1:1 semantic port of packages/live/src/camera.ts — same names, same
// shapes, same ordering, the lock_controller.dart discipline this codebase
// already applies everywhere else. Not yet wired into call_screen.dart —
// see live_games.dart's own header for why shipping the logic ahead of its
// UI integration, with real tests behind it, is this pass's deliberate
// scope rather than an oversight.
library;

enum Side { a, b }

enum Posture {
  foldCover, foldMain, foldTabletop, phone,
  tabletSmall, tabletMedium, tabletLarge, desktop, dex,
}

// ================================================= §5.24.1 "show me", live ==
/// The rear camera is the showcase (§9.10) happening in real time, and it is
/// probably the highest-value thing in this whole section.
///
/// "Show me" during a call means turning the phone around. Every other
/// product treats the rear camera as an afterthought; here it is the point
/// — a child showing her father the thing she is holding is the entire
/// product in one gesture.
enum Facing { front, rear }

class CameraState {
  const CameraState({required this.facing, required this.mirrored, required this.zoom, required this.torch});
  final Facing facing;
  /// Mirroring is right for a face and wrong for writing. See [flip].
  final bool mirrored;
  final double zoom;
  final bool torch;

  CameraState copyWith({Facing? facing, bool? mirrored, double? zoom, bool? torch}) =>
    CameraState(facing: facing ?? this.facing, mirrored: mirrored ?? this.mirrored,
      zoom: zoom ?? this.zoom, torch: torch ?? this.torch);
}

const double maxZoom = 4;

CameraState newCameraState() => const CameraState(facing: Facing.front, mirrored: true, zoom: 1, torch: false);

/// Flipping to the rear camera turns mirroring OFF.
///
/// A mirrored rear camera renders every word she holds up backwards, which
/// is the single most common complaint about showing a drawing on a video
/// call — and it makes the homework case useless.
CameraState flip(CameraState c) {
  final facing = c.facing == Facing.front ? Facing.rear : Facing.front;
  return c.copyWith(facing: facing, mirrored: facing == Facing.front, zoom: 1);
}

CameraState setZoom(CameraState c, double z) => c.copyWith(zoom: z.clamp(1, maxZoom));

/// The torch is only useful behind. Offering it on the front is a flash in
/// the face.
bool canTorch(CameraState c) => c.facing == Facing.rear;

/// Auto-framing keeps her in shot while she moves, because she will not sit
/// still. It is a crop, not a subject-recognition claim, and it never
/// follows her out of frame — a camera that pans around a child's bedroom
/// is a different product.
class Framing {
  const Framing({required this.autoFrame});
  final bool autoFrame;
  /// Never true. There is no constructor parameter for it — see this
  /// class's own doc comment.
  bool get pansBeyondFrame => false;
}

Framing framing(bool on) => Framing(autoFrame: on);

/// Lighting advice is about the room, never about her.
String? lightingAdvice(double lux) {
  if (lux >= 40) return null;
  return 'It is very dark in there — is there a light you can put on?';
}

const List<String> lightingBanned = ['you look', 'we cannot see you', 'your face', 'too dark for us'];

class LightingAudit {
  const LightingAudit.ok() : found = const <String>[];
  const LightingAudit.failed(this.found);
  final List<String> found;
  bool get ok => found.isEmpty;
}

LightingAudit auditLighting(String? text) {
  if (text == null) return const LightingAudit.ok();
  final t = text.toLowerCase();
  final found = lightingBanned.where((w) => t.contains(w)).toList();
  return found.isEmpty ? const LightingAudit.ok() : LightingAudit.failed(found);
}

// ===================================================== §5.24.2 P10 ==========
/// **P10 — NO APPEARANCE MODIFICATION ON A CHILD'S VIDEO.**
///
/// No beauty filters, no smoothing, no slimming, no eye enlargement, no
/// "touch-up". Not as a default, not as an option, not as a fun sticker
/// that happens to reshape a face.
///
/// Appearance modification aimed at a child is a self-image harm wearing a
/// fun hat. It teaches a five-year-old that the version of her face the
/// software prefers is better than the one her father sees, and it does it
/// during the one activity in this product that exists so he can see her.
///
/// It costs nothing to prohibit today and becomes very expensive to remove
/// later, because by then it is a feature somebody likes.
const bool p10NoAppearanceModification = true;

const List<String> bannedVideoEffects = [
  'beauty', 'smoothing', 'skin_smooth', 'slimming', 'face_slim', 'eye_enlarge',
  'touch_up', 'retouch', 'blemish', 'whitening', 'jawline', 'nose_slim',
  'makeup', 'lipstick', 'filter_pretty',
];

/// Silly is fine. A dog nose is not a beauty filter.
const List<String> allowedVideoEffects = [
  'dog_ears', 'silly_hat', 'googly_eyes', 'rainbow', 'sparkles', 'dinosaur',
];

class EffectVerdict {
  const EffectVerdict.ok() : reason = null, effect = null;
  const EffectVerdict.failed(this.effect) : reason = 'appearance_modification';
  final String? reason;
  final String? effect;
  bool get ok => reason == null;
}

EffectVerdict admitEffect(String effect) {
  final e = effect.toLowerCase();
  if (bannedVideoEffects.any((b) => e.contains(b))) return EffectVerdict.failed(effect);
  return const EffectVerdict.ok();
}

/// Virtual backgrounds are a genuine tension: they hide the home, which is
/// privacy — and they hide the home, which is concealment.
///
/// SETTLED: allowed for a **guardian**, refused for a **child**. An adult
/// may have good reason not to show a room. A child's background is the one
/// thing that tells the other parent she is somewhere safe, and it is the
/// only signal that arrives without anybody choosing to send it.
enum Role { child, guardian }

bool backgroundAllowed(Role role) => role == Role.guardian;

const String backgroundNote =
    "A child's background is the only thing in a call that tells the other "
    'parent she is somewhere ordinary, and it arrives without anybody '
    'deciding to send it.';

// ===================================================== §5.24.3 audio out ====
enum Route { speaker, earpiece, wired, bluetooth }

/// Speaker by default for a child. She is not holding it to her ear — it is
/// propped on a table, or on the floor, or she has wandered off with it.
Route defaultRoute(Role role, {required bool wired, required bool bluetooth}) {
  if (wired) return Route.wired;
  if (bluetooth) return Route.bluetooth;
  return role == Role.child ? Route.speaker : Route.earpiece;
}

/// Headphones on a child's device have a meaning beyond audio: she may be at
/// the other parent's house, and headphones may be the reason she can speak
/// freely.
///
/// So the other party is told they are on — not to monitor her, but because
/// the adult should know whether they are audible to a room. It is stated
/// neutrally and never as a status about her.
String? headphoneNote(bool on) => on ? 'She has headphones in.' : null;

const List<String> headphoneNoteBanned = ['private', 'alone', 'safe to', 'nobody can hear'];

class HeadphoneNoteAudit {
  const HeadphoneNoteAudit.ok() : found = const <String>[];
  const HeadphoneNoteAudit.failed(this.found);
  final List<String> found;
  bool get ok => found.isEmpty;
}

HeadphoneNoteAudit auditHeadphoneNote(String? text) {
  if (text == null) return const HeadphoneNoteAudit.ok();
  final t = text.toLowerCase();
  final found = headphoneNoteBanned.where((w) => t.contains(w)).toList();
  return found.isEmpty ? const HeadphoneNoteAudit.ok() : HeadphoneNoteAudit.failed(found);
}

/// A hearing ceiling that a child cannot raise.
const double maxChildVolume = 0.85;

double clampVolume(double v, Role role) {
  final hi = role == Role.child ? maxChildVolume : 1.0;
  return v.clamp(0, hi);
}

/// Siblings on separate devices in one room feed back into each other, and
/// the group call (§5.14) makes that certain rather than possible.
class EchoRisk {
  const EchoRisk({required this.sameRoom, required this.devices, required this.advice});
  final bool sameRoom;
  final int devices;
  final String? advice;
}

EchoRisk echoRisk(int devices, bool sameRoom) => EchoRisk(
  sameRoom: sameRoom, devices: devices,
  advice: sameRoom && devices > 1
    ? 'Two of you are in the same room — one of you use headphones, or share a screen.'
    : null);

// ===================================================== §5.24.4 PiP ==========
/// THE FINDING: **picture-in-picture conflicts with the child lock.**
///
/// PiP exists so a call survives you leaving the app. A child in kiosk mode
/// cannot leave the app — that is what the lock is for — so on her device
/// PiP is solving a problem she does not have, and implementing it would
/// mean punching a hole in the very thing that keeps her in one place.
///
/// So PiP is **guardian-only**, and that is a structural conclusion rather
/// than a limitation. It also means what the product has been calling
/// "picture in picture" in game layouts (see live_games.dart's own
/// VideoLayout.pictureInPicture) is a *layout*, not PiP — a distinction the
/// F-series would have caught if the word had been load-bearing.
enum PipKind { osNative, inLayout, none }

class PipPolicy {
  const PipPolicy({required this.kind, required this.reason});
  final PipKind kind;
  final String reason;
}

PipPolicy pipFor(Role role, {required bool kioskLocked}) {
  if (role == Role.child) {
    return PipPolicy(
      kind: kioskLocked ? PipKind.none : PipKind.inLayout,
      reason: kioskLocked
        ? 'She cannot leave the app, so there is nothing for PiP to solve — and '
          'enabling it would mean a hole in the lock.'
        : 'An unlocked child device gets the in-layout pane, not an OS window.');
  }
  return const PipPolicy(kind: PipKind.osNative,
    reason: 'A parent takes calls while doing other things. This is the case PiP '
          'is actually for.');
}

class PipWindow {
  const PipWindow({this.corner = Corner.br});
  final Corner corner;
  /// Remembered between calls. No constructor parameter — always true, the
  /// same "the type is the guarantee" posture used elsewhere in this file.
  bool get remembered => true;
  bool get tapReturns => true;
  /// Never smaller than a recognisable face.
  double get minPx => pipMinPx;
}

enum Corner { tl, tr, bl, br }

const double pipMinPx = 96;

/// The in-layout pane is what §9.13's video-never-hidden rule already
/// guarantees. Naming it separately stops "PiP" doing work it has not
/// earned.
const bool inLayoutIsNotPip = true;

// ================================================ §5.24.5 screen recording ==
String? recordingDisclosure(String platform) => switch (platform) {
  'ios' => 'Screen recording is on at the other end.',
  'android_play' => 'Something is recording the screen at the other end.',
  _ => null,
};

const List<String> recordingDetectableOn = ['ios', 'android_play'];
const bool recordingPreventable = false;
