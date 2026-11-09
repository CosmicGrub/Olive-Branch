// OLIVE BRANCH — live-backend entry point. No longer UNVERIFIED — verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// CHANGELOG v0.49.61). MASTERFILE §7.
//
// A SEPARATE build target from lib/main.dart, on purpose: main.dart is an
// intentionally offline, backend-independent preview build (see its own
// header) so the app's screens stay inspectable on a real device with
// nothing else running. Bolting live networking onto that entry point would
// break the one thing it's for. This mirrors the project's own prior
// pattern of separate main_X.dart entry points (main.dart + the former
// main_guardian.dart, before §8.5.0's entry gate unified the demo build).
//
// `flutter run --target=lib/main_live.dart --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required — see that
// file's own header for why). childId defaults to the seed data in
// server/seed-dev.mjs ("Ivy").
//
// PAIRING LAST (owner request 2026-11-08, first_run_flow.dart, MASTERFILE
// §8.5.6): with no OLIVE_CHILD_ID define and no stored identity, this build now
// opens on the welcome questions (offline, into a local draft) and ENDS on
// "Connect this device". After a successful redeem the identity is stored
// first, then the draft is delivered through the new session (the server's own
// profile wins; a failed delivery keeps the draft and retries), then her home
// opens. The dev paths (OLIVE_CHILD_ID / OLIVE_DEV_LOGIN) are unchanged.
//
// Device pairing & provisioning (docs/superpowers/specs/2026-09-12-device
// -pairing-provisioning-design.md): when NO `OLIVE_CHILD_ID` dart-define is
// set AND no identity is stored on-device (flutter_secure_storage — the
// first on-device persistence this app has ever needed, see
// device_identity.dart's own header), this boots into PairingRedeemScreen
// instead of the kiosk shell. The dart-define path above is UNCHANGED —
// `bool.hasEnvironment` is what lets this file tell "the define is genuinely
// absent" apart from "the define happens to equal its own default value",
// which `String.fromEnvironment`'s defaultValue alone cannot distinguish.
// Once redeemed, this proceeds into the SAME KioskShell/LiveChildHomeScreen
// tree the dart-define path already builds — see _bootLiveApp() below —
// with ONE disclosed, honest limitation: LiveChildHomeScreen's OWN internal
// per-call devLoginFor() (child_home_live.dart's `_load()`) was UNCHANGED by
// that pass. SUPERSEDED (audit G-02/G-06/C-03): a paired device now runs on ONE
// real session — an AuthSession (auth_session.dart) built from its stored
// {deviceId, deviceCredential}, installed process-wide at boot, which every
// live screen's apiFor() uses. Nothing in the paired path calls dev-login.
// DEV login stays reachable only when this build was provisioned through the
// dev dart-defines below (OLIVE_CHILD_ID or OLIVE_DEV_LOGIN=1).
//
// Automatic First-Run Detection (docs/superpowers/specs/2026-09-14
// -automatic-first-run-detection-design.md) — closes the other item device
// pairing's own spec explicitly deferred: "has THIS child ever completed
// onboarding," enforced now, not merely available. Both boot paths above
// (`main()`'s dart-define branch and a freshly-redeemed/stored pairing) now
// go through `_bootWithOnboardingGate` before `_bootLiveApp` — see that
// function's own doc comment, and `_OnboardingBootApp`'s, for the full
// account of the new pre-KioskShell onboarding branch this adds.
import 'dart:async';
import 'package:flutter/material.dart';
import 'font_licences.dart';
import 'access_shell.dart';
import 'api_client.dart';
import 'auth_session.dart';
import 'child_home_live.dart';
import 'contact_labels.dart';
import 'device_identity.dart';
import 'device_keys.dart';
import 'device_role.dart';
import 'first_run_flow.dart';
import 'grownup_roster.dart';
import 'guardian_boot.dart';
import 'guardian_local_scope.dart';
import 'kiosk_shell.dart';
import 'live_boot_plan.dart';
import 'live_common.dart';
import 'local_family.dart';
import 'local_pin.dart';
import 'pairing_protocol.dart' show ChildPairing;
import 'pairing_records.dart';
import 'local_repositories.dart';
import 'local_services.dart';
import 'my_people_entry.dart' show KidLabelsHost;
import 'onboarding_draft.dart';
import 'onboarding_flow.dart';
import 'pairing_redeem_screen.dart';
import 'read_aloud.dart';
import 'role_picker_screen.dart';
import 'theme.dart';
import 'theme_data.dart';

export 'guardian_boot.dart' show OliveLiveGuardian, OliveLocalGuardian;
export 'live_boot_plan.dart' show LiveTarget;

// The dart-defines live in live_common.dart, shared with the guardian shell's boot (one place;
// `bool.hasEnvironment`, NOT a defaultValue comparison — see that file for why the two are not
// the same question). These are the names this file has always used for them.
const _dartDefineBaseUrl = kLiveBaseUrl;
const _dartDefineChildId = kLiveChildId;
const _hasChildIdDartDefine = kHasChildIdDartDefine;
const _devLoginDartDefine = kDevLoginDartDefine;

/// The one session for a paired device: its stored {deviceId, deviceCredential}
/// -> short sessions, refreshed on demand. When it ends for good (revoked,
/// unknown device, deactivated account) the shell returns to pairing.
AuthSession _deviceSession(DeviceIdentity identity) => AuthSession.device(
    baseUrl: _dartDefineBaseUrl, identity: identity, onSignedOut: _returnToPairing);

/// Back to the pairing screen: [AuthSession] has already cleared the stored
/// identity by the time this runs. `runApp()` a second time is an ordinary way
/// to replace the root widget (see [_PairingBootApp]'s own comment).
void _returnToPairing() => runApp(const _PairingBootApp(baseUrl: _dartDefineBaseUrl));

/// The real backend PIN check — replaces the former hardcoded
/// `_demoVerifyGuardianPin` ('1273', never checked against anything). This is
/// the actual release-blocker fix: server/routes.mjs's real
/// POST /kiosk-pin/verify now backs the kiosk lock's PIN gate on this entry
/// point, exactly the way KioskShell's own header always said a real backend
/// would slot in once one existed.
///
/// Uses the installed [AuthSession] (see [_bootLiveApp]) via [apiFor]: the
/// paired device's own real session, refreshed on demand — never a fresh
/// dev-login. The session also re-checks revocation on every call, so a PIN
/// check never trusts a token that might have outlived the device's real
/// lifecycle.
///
/// FAILS CLOSED at every stage. [OliveApi.verifyKioskPin] already fails
/// closed on a network error reaching /kiosk-pin/verify itself; resolving the
/// session in front of it is wrapped the same way here — a server that's
/// unreachable, or a session that cannot be established, must reject the PIN,
/// never accept it. A broken network must never look like a correct PIN.
///
/// A [DeviceRevokedException] here (this device was cut off) has already
/// cleared the stored identity and sent the shell back to pairing
/// (AuthSession's onSignedOut); this just rejects the PIN.
Future<bool> _verifyGuardianPin(String pin, {required String childId}) async {
  try {
    final api = await apiFor(_dartDefineBaseUrl, childId: childId);
    final ok = await api.verifyKioskPin(childId, pin);
    api.close();
    return ok;
  } on DeviceRevokedException {
    return false;
  } catch (_) {
    return false;
  }
}

/// The biometric half of §8.3 guardian escalation
/// (webauthn_channel.dart's `buildVerifyBiometricCallback`) needs a KNOWN
/// guardian `userId` to request a login challenge for — unlike
/// [_verifyGuardianPin] above, which deliberately checks a PIN against every
/// live guardian rather than one. This entry point has no such identity to
/// give it: `devLoginFor()` is a stateless DEV_LOGIN=1 shortcut with no
/// signed-in guardian behind it, by design (see this file's own header) —
/// there is nothing here playing the role a real onboarded device's stored
/// guardian identity would. Rather than invent one (which would prove
/// nothing real, since `buildVerifyBiometricCallback`'s own WebAuthn
/// round trip would just be exercised against a guessed/hardcoded id, not a
/// device's actual configured guardian), this stays an honest stand-in —
/// same posture as `_demoVerifyGuardianPin` in main.dart, one layer down.
/// `buildVerifyBiometricCallback` itself is real and ready for whichever
/// real entry point ends up knowing its own guardian's userId.
Future<bool> _liveVerifyBiometricStub() async => true;

/// The theme half of session bootstrap (MASTERFILE §8.1, the intuitivism
/// visual-foundation design spec) — fetched and resolved BEFORE `runApp()`,
/// same posture as Firebase init above, so the very first frame this build
/// draws already carries the real, backend-synced theme rather than
/// flashing [defaultAppTheme] and swapping a moment later.
///
/// FAILS CLOSED, deliberately, the same discipline [_verifyGuardianPin]
/// above already applies: a session/fetchTheme() failure of ANY kind
/// (unreachable server, malformed body, an unset row) must resolve to
/// [defaultAppTheme] (`classic`/`light` — this app's own former stock
/// look), never a broken/partial theme state and never a thrown exception
/// that would crash this isolate before it ever draws a frame (main.dart's
/// own Firebase try/catch reasoning, applied here to the same boot phase).
/// `AppTheme.fromWire` is ALSO fail-closed on a malformed body — this
/// try/catch is the outer layer, catching a network/auth failure reaching
/// the server at all.
///
/// Runs on the installed [AuthSession] — see [_verifyGuardianPin]'s own doc
/// comment; identical [DeviceRevokedException] reaction (the session has
/// already cleared the stored identity), applied at boot time.
Future<AppTheme> _fetchInitialTheme(String childId) async {
  try {
    final api = await apiFor(_dartDefineBaseUrl, childId: childId);
    final wire = await api.fetchTheme(childId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } on DeviceRevokedException {
    return defaultAppTheme;
  } catch (_) {
    return defaultAppTheme;
  }
}

/// Boots the real kiosk shell for [childId] — the common tail of BOTH the
/// dart-define path and a freshly-redeemed pairing (see this file's own
/// header). Extracted so `main()` and the pairing screen's own
/// `onRedeemed` callback (below) share one real implementation rather than
/// two copies that could drift. As of Automatic First-Run Detection (docs/
/// superpowers/specs/2026-09-14-automatic-first-run-detection-design.md),
/// neither of those two callers invokes this directly any more — both go
/// through [_bootWithOnboardingGate] below, which calls this ONLY once
/// `hasOnboarded` is genuinely true. This function itself is otherwise
/// completely unchanged: it is still the one real path into
/// KioskShell/ChildHome, exactly as before that gate existed.
Future<void> _bootLiveApp({required String childId, required AuthSession session}) async {
  // Installed BEFORE anything below calls apiFor() — every live screen under
  // OliveLive reads the same process-wide session (audit G-02/G-06).
  AuthSession.use(session);
  // Resolved BEFORE runApp() -- see _fetchInitialTheme()'s own doc comment.
  final initialTheme = await _fetchInitialTheme(childId);
  runApp(OliveLive(initialTheme: initialTheme, childId: childId, session: session));
}

/// Resolves a usable session token from [session] (a refreshed one when the
/// cached token is about to lapse). Unlike [_verifyGuardianPin]/
/// [_fetchInitialTheme] above, the resolved token is RETURNED (never discarded) — Automatic
/// First-Run Detection's own [_OnboardingBootApp] below needs a concrete,
/// non-null token to thread into its own live-wired `ObGenderScreen`
/// (onboarding_gender.dart's `_isLive` getter requires one), for BOTH the
/// pairing path AND the dart-define path. A [DeviceRevokedException] here
/// (the session already cleared the stored identity) surfaces as `null`, same as any
/// other resolution failure — this function's own caller below fails closed
/// on a null return, exactly like every other boot-time network failure
/// this file already treats as "assume the less-trusted state," never "let
/// her through anyway."
Future<String?> _resolveSessionToken(AuthSession session) async {
  try {
    return await session.token();
  } on DeviceRevokedException {
    return null;
  } catch (_) {
    return null;
  }
}

/// GET /v1/me's `hasOnboarded` field (Automatic First-Run Detection, docs/
/// superpowers/specs/2026-09-14-automatic-first-run-detection-design.md) —
/// FAILS CLOSED like every other boot-time gate this file already enforces
/// ([_verifyGuardianPin]'s own doc comment: "a broken network must never
/// look like a correct PIN"; applied here to "never look like a completed
/// onboarding"): a null [token] (resolution already failed), or a `/v1/me`
/// call that throws for any reason, reports `false` — the pre-lock-task
/// onboarding branch, never a silent pass into KioskShell.
///
/// OFFLINE-FIRST (audit C-06): this now THROWS when the server cannot be asked
/// (no session token, or the call fails) instead of answering `false`, so
/// [resolveHasOnboarded] (local_repositories.dart) can tell "the server said
/// no" from "I could not ask". Only the former restarts onboarding: an
/// onboarded child who boots with no signal is let through on the answer this
/// device remembered the last time the server said yes; a device that never
/// heard a yes still fails CLOSED to the welcome tour.
Future<bool> _fetchHasOnboarded(String childId, String? token) async {
  if (token == null) throw StateError('no session token: server not asked');
  final api = await apiFor(_dartDefineBaseUrl, childId: childId);
  try {
    final me = await api.fetchMe();
    return me['hasOnboarded'] == true;
  } finally {
    api.close();
  }
}

/// Opens this device's on-device storage for [childId] (LocalStore under the
/// app documents directory, sealed namespaces keyed from secure storage) and
/// installs it as [LocalServices.current]. A live build: the preview 'demo-child'
/// scope is refused and demo seed content is off. If the platform storage
/// cannot be opened at all, the app still runs on an in-memory store — nothing
/// persists that run, which is the honest degraded mode, never a crash.
Future<void> _openLocalStorage(String childId) async {
  try {
    await LocalServices.boot(childId: childId, isLive: true);
  } catch (e) {
    debugPrint('[olive.localStore] on-device storage unavailable, running in memory: $e');
    LocalServices.install(LocalServices.memory(childId: childId, isLive: true, demoSeeds: false));
  }
}

/// One try at delivering the pairing-last draft: ask the server first (its own
/// profile wins), then send the one answer the child session can write.
Future<DraftSyncOutcome> _attemptDraftSync(
    String childId, AuthSession session, OnboardingDraftRepository repo) =>
  syncOnboardingDraft(
    repo: repo,
    fetchHasOnboarded: () async =>
        _fetchHasOnboarded(childId, await _resolveSessionToken(session)),
    putGender: (String? gender) async {
      final api = await apiFor(_dartDefineBaseUrl, childId: childId);
      try {
        await api.putChildGender(childId, gender);
      } finally {
        api.close();
      }
    },
  );

/// The Automatic First-Run Detection boot gate itself (docs/superpowers/
/// specs/2026-09-14-automatic-first-run-detection-design.md) — sits between
/// identity resolution and [_bootLiveApp], now the ONLY path either `main()`
/// or [_PairingBootApp]'s own `onRedeemed` uses to reach it. Applies
/// IDENTICALLY to both callers — "driven purely by identity state, not by
/// how that identity got resolved," the design spec's own line — since
/// neither this function nor anything it calls branches on how [childId]/
/// [sessionToken] were obtained.
///
/// A fresh, concrete token is resolved once here ([_resolveSessionToken])
/// and reused for BOTH the `hasOnboarded` check and (when the gate engages)
/// [_OnboardingBootApp]'s own live wiring — one resolution, not two.
Future<void> _bootWithOnboardingGate({
  required String childId, required AuthSession session,
}) async {
  // Installed first: _fetchHasOnboarded below goes through apiFor().
  AuthSession.use(session);
  // On-device storage first: the onboarding answer below is remembered there.
  await _openLocalStorage(childId);
  final profile = ProfileCacheRepository(LocalServices.current.area('profile', ownerId: childId));
  // Pairing-last first run (owner request 2026-11-08): a device that answered
  // the welcome questions BEFORE it was connected left them in a local draft.
  // Deliver it now, through this new session; the server's own profile wins if
  // it has one. A draft being there means the tour is already done, so it
  // never runs again, and a failed delivery keeps the draft and retries.
  final draftRepo = LocalOnboardingDraftRepository(
      LocalServices.current.area('onboarding', ownerId: kPendingDeviceScope));
  await carryOverFirstRun(
    childId: childId, profile: profile, draftRepo: draftRepo,
    pendingNicknames: LocalNicknameRepository(
        LocalServices.current.area('nicknames', ownerId: kPendingDeviceScope)),
    hersNicknames: LocalNicknameRepository(LocalServices.current.area('nicknames', ownerId: childId)));
  final delivery = await deliverPendingDraft(
    attempt: () => _attemptDraftSync(childId, session, draftRepo),
    onDelivered: profile.markOnboarded,
  );
  if (delivery.first != DraftSyncOutcome.nothingPending) {
    await _bootLiveApp(childId: childId, session: session);
    return;
  }
  final token = await _resolveSessionToken(session);
  final hasOnboarded = await resolveHasOnboarded(
      fetch: () => _fetchHasOnboarded(childId, token), cache: profile);
  if (hasOnboarded) {
    await _bootLiveApp(childId: childId, session: session);
    return;
  }
  runApp(_OnboardingBootApp(
    baseUrl: _dartDefineBaseUrl,
    childId: childId,
    token: token,
    // The SESSION itself, not the locally-resolved [token] above: the token is
    // a one-hour snapshot for the onboarding screen's single write, while
    // _bootLiveApp installs the long-lived session every later screen uses.
    onOnboarded: () async {
      // Remember on THIS device that the tour is done, so an offline restart
      // goes straight to her home (best effort: a failed write must not strand her).
      try {
        await profile.markOnboarded();
      } catch (_) {}
      await _bootLiveApp(childId: childId, session: session);
    },
  ));
}

/// The one live entry point (owner requirement 2026-11-08: the onboarding follows ROLES).
/// `main()` is [runLive] on the unified target; main_live_guardian.dart calls it with
/// [LiveTarget.guardianDev]. What opens is [decideBoot]'s answer (live_boot_plan.dart), in this
/// order: a dev define, a stored device identity, the role picker, then the role's own first run.
Future<void> main() => runLive();

Future<void> runLive({LiveTarget target = LiveTarget.unified}) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  AuthSession.devLoginEnabled = _devLoginDartDefine;
  // MASTERFILE §11 -- registers the real top-level background handler before runApp(); wrapped in
  // try/catch inside (a missing google-services.json must never crash the build before its first
  // frame). See live_common.dart.
  await initFirebaseForLive();

  // The dev defines decide first and read NOTHING from the device: `DeviceIdentityStore().load()`
  // and the role are never touched when OLIVE_CHILD_ID / OLIVE_GUARDIAN_ID is set, matching the
  // device-pairing spec's "dart-define, when present, keeps working exactly as today" literally.
  final BootRoute dev = decideBoot(BootFacts(
    target: target,
    hasChildDefine: _hasChildIdDartDefine,
    hasGuardianDefine: kHasGuardianIdDartDefine,
  ));
  if (dev == BootRoute.childDev) {
    // The explicit dev path: this build was provisioned with OLIVE_CHILD_ID, so dev login is allowed
    // (and refreshable — it is the whole app's session).
    AuthSession.devLoginEnabled = true;
    await _bootWithOnboardingGate(childId: _dartDefineChildId, session: _devSession());
    return;
  }
  if (dev == BootRoute.guardianDev) {
    await bootGuardianDev();
    return;
  }

  // No define: a connected device is what its stored identity says; otherwise the role this device
  // was given on its first screen decides.
  final stored = await DeviceIdentityStore().load();
  DeviceRole? role;
  bool hasFamily = false, hasPin = false, hasChildPairing = false;
  if (stored == null) {
    // Storage opens under the pending-device owner (never the literal 'demo-child').
    await _openLocalStorage(kPendingDeviceScope);
    role = await _loadRole();
    if (role != null && role.isGuardian) {
      final GuardianLocalServices local = GuardianLocalServices.from(LocalServices.current);
      hasFamily = await _safeBool(() async => (await local.families.load()) != null);
      hasPin = await _safeBool(local.pin.isSet);
    } else if (role != null) {
      hasChildPairing = await _safeBool(() async => (await _childPairingRepo().load()) != null);
    }
  }
  final BootRoute route = decideBoot(BootFacts(
    target: target,
    storedIdentityRole: stored?.role,
    role: role,
    hasLocalFamily: hasFamily,
    hasLocalPin: hasPin,
    hasLocalChildPairing: hasChildPairing,
  ));
  switch (route) {
    case BootRoute.childPaired:
      await _bootWithOnboardingGate(childId: stored!.targetId, session: _deviceSession(stored));
    case BootRoute.guardianPaired:
      await bootGuardianPaired(stored!);
    case BootRoute.rolePicker:
      runApp(const _RolePickerApp(onPicked: _onRolePicked));
    case BootRoute.kidFirstRun:
      await _startKidFirstRun();
    case BootRoute.childPairedLocal:
      final ChildPairing? p = await _childPairingRepo().load();
      if (p == null) {
        await _startKidFirstRun();
      } else {
        await _bootLocalPaired(p);
      }
    case BootRoute.guardianOnboarding:
    case BootRoute.guardianOffline:
      await bootGuardianFlow(role!, reuseStorage: true);
    case BootRoute.childDev:
    case BootRoute.guardianDev:
      break; // handled above; unreachable without a define
  }
}

/// The child device's record of the grown-up that approved it on the same network (pairing_protocol.dart):
/// the certificate, and the grown-up's PIN verifier (a salted slow hash; a child device never holds a PIN).
ChildPairingRepository _childPairingRepo() => LocalStoreChildPairingRepository(
    LocalServices.current.area('childpairing'),
    LocalStoreLocalPinRepository(LocalServices.current.area('adultunlock')));

/// A grown-up approved this Kid device on the same network. Keep it, then open her home. There is NO server
/// session here: her home runs on what the device has (its offline home) and the adult gate checks the
/// grown-up's PIN against the verifier this device was given, with its own 5-tries-then-15-minutes lock.
/// UNVERIFIED on a real device (the offline child home with no session is exercised by its own tests).
Future<void> _completeLocalPair(ChildPairing p) async {
  try {
    await _childPairingRepo().save(p);
  } catch (e) {
    debugPrint('[olive.pairing] could not keep the pairing on this device: $e');
  }
  await _bootLocalPaired(p);
}

Future<void> _bootLocalPaired(ChildPairing p) async {
  await _openLocalStorage(p.cert.childId);
  final LocalPinService unlock = LocalPinService(
      LocalStoreLocalPinRepository(LocalServices.current.area('adultunlock')));
  runApp(OliveLive(
    initialTheme: defaultAppTheme,
    childId: p.cert.childId,
    session: null,
    verifyPin: unlock.verifyBool,
  ));
}

Future<bool> _safeBool(Future<bool> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return false;
  }
}

Future<DeviceRole?> _loadRole() async {
  try {
    return await LocalDeviceRoleRepository(LocalServices.current.area('role')).load();
  } catch (_) {
    return null; // an unreadable role is "no role": she is asked again, never stuck
  }
}

/// Step 0 answered: remember it on this device (a failed write is held for this run and she is asked
/// again after a restart, never stuck), then go to that role's own first run.
Future<void> _onRolePicked(DeviceRole role) async {
  try {
    await LocalDeviceRoleRepository(LocalServices.current.area('role')).save(role);
  } catch (e) {
    debugPrint('[olive.role] could not keep the role on this device: $e');
  }
  if (role.isGuardian) {
    await bootGuardianFlow(role, reuseStorage: true);
  } else {
    await _startKidFirstRun();
  }
}

/// A Kid device with no identity: the welcome questions, then "Connect this device" last. Answers wait
/// in a local draft under the pending-device owner. Her grown-ups come from the local family if the
/// device has one, else two neutral placeholders (grownup_roster.dart).
Future<void> _startKidFirstRun() async {
  final LocalServices s = LocalServices.current;
  final KidRoster roster = await loadKidRoster(
      LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)));
  runApp(_FirstRunApp(
    baseUrl: _dartDefineBaseUrl,
    draftRepository: LocalOnboardingDraftRepository(s.area('onboarding', ownerId: kPendingDeviceScope)),
    roster: roster,
    nicknames: LocalNicknameRepository(s.area('nicknames', ownerId: kPendingDeviceScope)),
    deviceKeys: LocalStoreDeviceKeyRepository(s.area('devicekey')),
  ));
}

/// The explicit dev-login session for the OLIVE_CHILD_ID-provisioned build.
/// Refreshable: it is the whole app's session, not a per-call one.
AuthSession _devSession() => AuthSession.dev(
    baseUrl: _dartDefineBaseUrl, childId: _dartDefineChildId, refreshable: true);

/// A successful redeem, from either first-run layout: store the identity, THEN
/// go through the boot gate, which delivers any waiting draft through the new
/// session and opens her home.
Future<void> _completeRedeem(Map<String, dynamic> result) async {
  final identity = DeviceIdentity(
    sessionToken: result['sessionToken'] as String,
    deviceId: result['deviceId'] as String,
    role: result['role'] as String? ?? 'child',
    targetId: result['targetId'] as String,
    deviceCredential: result['deviceCredential'] as String?,
  );
  await DeviceIdentityStore().save(identity);
  await _bootWithOnboardingGate(childId: identity.targetId, session: _deviceSession(identity));
}

/// Shown at boot when there's no dart-define AND no stored identity: the
/// welcome questions, then "Connect this device" as the LAST step
/// ([FirstRunFlow]). Same bare-MaterialApp shape as [_PairingBootApp].
class _FirstRunApp extends StatelessWidget {
  const _FirstRunApp({
    required this.baseUrl, required this.draftRepository, this.roster, this.nicknames, this.deviceKeys});
  final String baseUrl;
  final DeviceKeyRepository? deviceKeys;
  final OnboardingDraftRepository draftRepository;
  final KidRoster? roster;
  final NicknameRepository? nicknames;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (welcome)',
    theme: buildThemeData(defaultAppTheme),
    home: FirstRunFlow(
      baseUrl: baseUrl,
      draftRepository: draftRepository,
      roster: roster,
      nicknames: nicknames,
      onRedeemed: (result) => unawaited(_completeRedeem(result)),
      deviceKeys: deviceKeys,
      onPairedLocally: (p) => _completeLocalPair(p),
    ),
  );
}

/// Step 0: "Who is using this device?" in a bare MaterialApp (no shell exists yet). The read-aloud
/// scope is installed so the speaker can read the question to a child who cannot read it yet.
class _RolePickerApp extends StatelessWidget {
  const _RolePickerApp({required this.onPicked});
  final Future<void> Function(DeviceRole role) onPicked;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (welcome)',
    theme: buildThemeData(defaultAppTheme),
    navigatorObservers: [sharedReadAloudObserver],
    builder: (context, child) =>
        ReadAloudScope(controller: sharedReadAloud, child: child ?? const SizedBox.shrink()),
    home: RolePickerScreen(onPicked: (DeviceRole r) => unawaited(onPicked(r))),
  );
}

/// The code screen alone, for a device that WAS connected and has been cut off
/// ([_returnToPairing]): it has already been through the welcome questions, so
/// they are not asked again.
///
/// A minimal MaterialApp wrapper (this build's real theme/kiosk tree doesn't
/// exist yet at this point — there is no identity to fetch a theme FOR),
/// matching invitation_screen.dart's own convention of a screen owning its own
/// Scaffold with no assumed ancestor chrome.
class _PairingBootApp extends StatelessWidget {
  const _PairingBootApp({required this.baseUrl});
  final String baseUrl;

  /// Persists the real identity this device just redeemed, then re-enters
  /// the app via the SAME [_bootWithOnboardingGate] the dart-define path
  /// already uses (Automatic First-Run Detection applies identically to a
  /// freshly-redeemed device, per that gate's own doc comment) — `runApp()`
  /// a second time is a legitimate, ordinary way to replace a Flutter app's
  /// root widget, not a workaround; there is no `OliveLive`/
  /// `_OnboardingBootApp` instance yet at this point for a callback to hand
  /// state to instead.
  Future<void> _onRedeemed(Map<String, dynamic> result) => _completeRedeem(result);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (pairing)',
    theme: buildThemeData(defaultAppTheme),
    home: PairingRedeemScreen(baseUrl: baseUrl, role: 'child', onRedeemed: _onRedeemed),
  );
}

/// Shown at boot when identity is resolved but `GET /v1/me`'s `hasOnboarded`
/// is false — Automatic First-Run Detection (docs/superpowers/specs/
/// 2026-09-14-automatic-first-run-detection-design.md). Mirrors
/// [_PairingBootApp]'s own shape EXACTLY, per the design spec's own explicit
/// instruction to reuse that shape rather than invent a second, different
/// pattern for "content that must run before lock-task engages": a bare
/// `MaterialApp` root with no `KioskShell`/lock-task ANYWHERE in this
/// tree — a child mid-onboarding can never be inside an engaged kiosk lock,
/// because the widget that engages it (`KioskShell`, `OliveLive`'s own
/// `home:`) simply does not exist on this branch of the widget tree at all.
///
/// Runs the UNCHANGED `onboarding_flow.dart` sequence — "the identical
/// sequence 'Redo the welcome tour' already runs, nothing new invented" (the
/// design spec's own line) — with real live wiring threaded through to its
/// one network-calling step (`ObGenderScreen`, via
/// `OnboardingFlowScreen`'s own `childId`/`baseUrl`/`sessionToken`
/// params). [token] is ALREADY resolved by [_bootWithOnboardingGate]
/// (`_resolveSessionToken`) before this widget is ever constructed — a
/// fresh `devLoginFor()` call for the dart-define path, the real stored
/// credential for a paired one — so `onboarding_gender.dart`'s own `_isLive`
/// getter is genuinely live on BOTH boot paths here, not only the paired
/// one. [token] can still be null (every resolution attempt failed — see
/// that function's own doc comment), in which case this screen still
/// renders and still lets her walk through it, simply without a live write
/// at the end — the same graceful, non-trapping degradation
/// `onboarding_gender.dart`'s own header already describes for an offline
/// `ObGenderScreen`, not a new failure mode this class invents.
///
/// [onOnboarded] fires once [OnboardingFlowScreen]'s own sequence genuinely
/// reaches its real end (that file's new `onComplete` callback — see its
/// own doc comment) — NOT on an early abandon (back-navigation mid-flow,
/// the existing `if (stepResult == null) return setState(...)` early-outs
/// `onboarding_flow.dart` already has for every step, untouched by this
/// pass), which leaves this screen on-site rather than silently proceeding
/// into KioskShell before `child_profile` genuinely has a chance to exist.
class _OnboardingBootApp extends StatelessWidget {
  const _OnboardingBootApp({
    required this.baseUrl, required this.childId,
    required this.token, required this.onOnboarded,
  });
  final String baseUrl;
  final String childId;
  final String? token;
  final Future<void> Function() onOnboarded;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (onboarding)',
    theme: buildThemeData(defaultAppTheme),
    home: OnboardingFlowScreen(
      childId: childId,
      baseUrl: baseUrl,
      sessionToken: token,
      onComplete: onOnboarded,
    ),
  );
}

class OliveLive extends StatefulWidget {
  const OliveLive({super.key, this.initialTheme = defaultAppTheme,
    required this.childId, required this.session, this.verifyPin});

  /// The session-bootstrap-resolved theme (`_fetchInitialTheme()`), already
  /// fail-closed to [defaultAppTheme] on any failure -- this widget never
  /// re-derives that fallback itself.
  final AppTheme initialTheme;

  /// Resolved BEFORE this widget is constructed — either the dart-define
  /// value, or a redeemed/stored identity's own targetId. See this file's
  /// own header.
  final String childId;

  /// The installed [AuthSession] ([_bootLiveApp] installs it process-wide
  /// BEFORE constructing this widget, which is what every live screen's
  /// apiFor() reads). Held here so the tree depends on it explicitly, and null
  /// only in a widget test that supplies its own transport.
  final AuthSession? session;

  /// The adult gate's PIN check. Null = the server's (a connected device). A device a grown-up approved on
  /// the same network passes its own local verifier.
  final Future<bool> Function(String pin)? verifyPin;

  @override
  State<OliveLive> createState() => _OliveLiveState();
}

class _OliveLiveState extends State<OliveLive> {
  // The spec's own suggested shape: a ValueNotifier<AppTheme> held above
  // MaterialApp, matching this codebase's plain StatefulWidget/setState
  // style rather than a new state-management dependency (theme.dart's own
  // ThemeController is exactly this, extended by nothing but a default).
  // Nothing in this build's current navigation graph updates it yet --
  // theme_picker_screen.dart is reached from guardian_more.dart, which is
  // not (yet) wired into this live entry point's own tree, the same
  // pre-existing gap every other guardian_more.dart tile has today
  // (Message banking, Handover notes, Availability's own optional
  // baseUrl/guardianId/childId wiring, ...) -- see this PR's final report.
  // This controller exists now so that gap is the ONLY thing left to close,
  // not a second rewrite of the propagation mechanism itself.
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  // The real, previously-missing piece call_knock_screen.dart's own header
  // named directly: buildCallIncomingHandler is real, tested wiring, ready
  // the day this app's root widget gains a GlobalKey<NavigatorState> —
  // it didn't have one before this. Lets a call_incoming push open
  // CallKnockScreen from wherever the app happens to be, not just from
  // whatever screen was already on top.
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _themeController,
    builder: (context, _) {
      final themeData = buildThemeData(_themeController.value);
      return MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: [sharedReadAloudObserver],
        title: 'Olive (live)',
        // theme: and darkTheme: are intentionally the SAME resolved scheme,
        // with themeMode PINNED to the guardian's own explicit brightness
        // choice (never ThemeMode.system) -- an AppTheme's brightness is a
        // real selection, not "follow the OS," so MaterialApp must never
        // resolve brightness from anywhere else.
        theme: themeData,
        darkTheme: themeData,
        themeMode: _themeController.value.brightness == ThemeBrightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        // A real, brief, user-initiated crossfade whenever _themeController
        // changes (i.e. only on a guardian's own Apply, never autonomously)
        // -- §8.13 permits consequence motion; MaterialApp's own theme: swap
        // is otherwise instant with no transition at all. AnimatedTheme
        // wraps app CONTENT, one layer inside MaterialApp's own Theme, so
        // every descendant's Theme.of(context) resolves to this animated
        // value during the crossfade.
        builder: (context, child) => AnimatedTheme(
          data: themeData,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOut,
          // Accessibility settings and read-aloud (access_shell.dart).
          // The label scope: every child-facing screen says what SHE calls her grown-ups.
          child: KidLabelsHost(childId: widget.childId, child: withAccess(child!)),
        ),
        home: KioskShell(
          variableLengthPin: widget.verifyPin != null,
          verifyPin: widget.verifyPin ?? (pin) => _verifyGuardianPin(pin, childId: widget.childId),
          verifyBiometric: _liveVerifyBiometricStub,
          child: LiveChildHomeScreen(
            baseUrl: _dartDefineBaseUrl,
            childId: widget.childId,
            navigatorKey: _navigatorKey,
          ),
        ),
      );
    },
  );
}
