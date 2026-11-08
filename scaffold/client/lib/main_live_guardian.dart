// OLIVE BRANCH — the legacy live-GUARDIAN dev target, now a thin wrapper. No longer UNVERIFIED as
// code — analysed by CI (`flutter analyze`); the on-device run of this dev-only entry point is manual
// and not part of CI. MASTERFILE §7, §8.5.8.
//
// There used to be two live targets (this one and main_live.dart's child one) that shared one package
// id and could never be installed together. The owner's requirement of 2026-11-08 is that the ROLE
// decides, so main_live.dart is now the ONE live entry point (it asks "Who is using this device?" and
// boots the child shell for a Kid or the guardian shell for a Mom, a Dad or someone else), and the
// guardian shell's boot lives in guardian_boot.dart. This file stays so that
//
//   flutter run --target=lib/main_live_guardian.dart --dart-define=OLIVE_API_BASE_URL=http://<host>:8123
//
// and every existing test import (`OliveLiveGuardian`) keep working. The one difference from the
// unified target: here OLIVE_CHILD_ID only names the child this guardian looks at (it does NOT boot the
// child shell), so the dev flows that set both defines behave as they always did. OLIVE_GUARDIAN_ID and
// OLIVE_DEV_LOGIN are unchanged. See live_boot_plan.dart `LiveTarget.guardianDev`.
import 'live_boot_plan.dart';
import 'main_live.dart' show runLive;

export 'guardian_boot.dart' show OliveLiveGuardian, OliveLocalGuardian;

Future<void> main() => runLive(target: LiveTarget.guardianDev);
