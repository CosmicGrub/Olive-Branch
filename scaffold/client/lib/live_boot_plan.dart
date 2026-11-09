// OLIVE BRANCH — the unified live entry's decision: which app opens. No longer
// UNVERIFIED — verified by CI (client/test/live_boot_plan_test.dart).
// MASTERFILE §8.5.8.
//
// main_live.dart is now the ONE live entry point. It reads what this device already
// knows and asks [decideBoot] which of the existing shells to open. The decision is a
// pure function so it is tested for every combination without a platform channel, and
// so the order of the rules is one reviewable list rather than nested ifs in `main()`.
//
// THE ORDER (first match wins):
//  1. A dev define. `OLIVE_CHILD_ID` boots the child shell on a dev session and
//     `OLIVE_GUARDIAN_ID` boots the guardian shell on a dev session, exactly as the two
//     separate targets did, with no identity, no role and no pairing. On the legacy
//     guardian target (main_live_guardian.dart) `OLIVE_CHILD_ID` only names the child
//     the guardian looks at, so it does not boot the child shell there.
//  2. A stored device identity (the device was connected): its own role wins, because a
//     connected device is whatever the server says it is.
//  3. No stored role: the role picker, Step 0.
//  4. Role Kid: a locally approved pairing opens her home; otherwise the child's first run (welcome questions, then Connect this device).
//  5. A grown-up role: if this device already has a local family AND a local PIN, the
//     guardian home opens WITHOUT a server; otherwise the guardian onboarding runs.
//
// A role is a question, not authority (§8.5.0). Nothing here reads a server.
import 'device_role.dart';

/// Which target launched the app. [unified] is main_live.dart; [guardianDev] is the
/// thin main_live_guardian.dart wrapper kept for dev flows and the existing tests.
enum LiveTarget { unified, guardianDev }

enum BootRoute {
  childDev,
  guardianDev,
  childPaired,
  guardianPaired,
  rolePicker,
  kidFirstRun,
  /// A Kid device a grown-up approved on the same network (pairing_protocol.dart): no server identity, a
  /// signed certificate. Opens the child's home with the grown-up's PIN verifier for the adult gate.
  childPairedLocal,
  guardianOnboarding,
  guardianOffline,
}

class BootFacts {
  const BootFacts({
    required this.target,
    this.hasChildDefine = false,
    this.hasGuardianDefine = false,
    this.storedIdentityRole,
    this.role,
    this.hasLocalFamily = false,
    this.hasLocalPin = false,
    this.hasLocalChildPairing = false,
  });

  final LiveTarget target;
  final bool hasChildDefine;
  final bool hasGuardianDefine;

  /// The role of the stored device identity ('child' or 'guardian'), or null when the
  /// device was never connected (or was cut off).
  final String? storedIdentityRole;

  /// The role chosen on Step 0, or null.
  final DeviceRole? role;
  final bool hasLocalFamily;
  final bool hasLocalPin;

  /// This Kid device holds a verified pairing certificate from a grown-up's device.
  final bool hasLocalChildPairing;
}

BootRoute decideBoot(BootFacts f) {
  if (f.target == LiveTarget.unified && f.hasChildDefine) return BootRoute.childDev;
  if (f.hasGuardianDefine) return BootRoute.guardianDev;
  final String? stored = f.storedIdentityRole;
  if (stored != null) return stored == 'guardian' ? BootRoute.guardianPaired : BootRoute.childPaired;
  final DeviceRole? role = f.role;
  if (role == null) return BootRoute.rolePicker;
  if (role == DeviceRole.kid) return f.hasLocalChildPairing ? BootRoute.childPairedLocal : BootRoute.kidFirstRun;
  return (f.hasLocalFamily && f.hasLocalPin) ? BootRoute.guardianOffline : BootRoute.guardianOnboarding;
}

/// Where the guardian shell opens once its identity is known (connected), and what
/// stands between a grown-up and their home when the server cannot be asked.
enum GuardianEntry {
  /// Go in.
  home,

  /// The server says there is no PIN (and could be asked): the server-PIN setup, exactly
  /// as before. The local PIN does not stand in for it while a session exists.
  serverPinSetup,

  /// The server could not be asked and no local PIN exists: set a local one. It works
  /// offline; this is the exit from the old undismissable server-PIN trap.
  localPinSetup,
}

/// [serverHasPin] is the server's answer, or null when it could not be asked (no
/// signal, no session token). Offline, a local PIN is sufficient to enter.
GuardianEntry resolveGuardianEntry({required bool? serverHasPin, required bool localPinSet}) {
  if (serverHasPin == true) return GuardianEntry.home;
  if (serverHasPin == false) return GuardianEntry.serverPinSetup;
  return localPinSet ? GuardianEntry.home : GuardianEntry.localPinSetup;
}
