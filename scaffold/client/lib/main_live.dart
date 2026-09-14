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
// per-call devLoginFor() (child_home_live.dart's `_load()`) is UNCHANGED by
// this pass, so a redeemed device's ongoing traffic to that screen still
// goes through DEV_LOGIN, exactly as the dart-define path always has. Only
// the boot-time helpers THIS file owns (_verifyGuardianPin/
// _fetchInitialTheme) genuinely prefer the real, deviceId-bearing session
// this device redeemed, when one exists — real, working revocation
// detection at kiosk-unlock and at next-cold-boot time, not a claim this
// pass rewired every live screen's own auth path (a real, separate,
// disclosed follow-up — see this PR's own description).
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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'child_home_live.dart';
import 'device_identity.dart';
import 'kiosk_shell.dart';
import 'onboarding_flow.dart';
import 'pairing_redeem_screen.dart';
import 'push_channel.dart';
import 'theme.dart';

const _dartDefineBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _dartDefineChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
// `bool.hasEnvironment`, NOT a defaultValue comparison — see this file's own
// header for why the two are not the same question. True on every existing
// `flutter run --dart-define=OLIVE_CHILD_ID=...` invocation, dev or CI,
// unaffected by this feature.
const _hasChildIdDartDefine = bool.hasEnvironment('OLIVE_CHILD_ID');

/// The real backend PIN check — replaces the former hardcoded
/// `_demoVerifyGuardianPin` ('1273', never checked against anything). This is
/// the actual release-blocker fix: server/routes.mjs's real
/// POST /kiosk-pin/verify now backs the kiosk lock's PIN gate on this entry
/// point, exactly the way KioskShell's own header always said a real backend
/// would slot in once one existed.
///
/// Reuses child_home_live.dart's own session plumbing rather than inventing
/// a second path: the same `devLoginFor()` dev-login helper, against the same
/// `_dartDefineBaseUrl`/[childId] this file already resolves at boot (see
/// that file's `_load()` for the pattern this mirrors). A fresh dev-login per PIN
/// attempt, not a token cached across this screen's lifetime: dev-login is a
/// stateless, side-effect-free shortcut fenced behind DEV_LOGIN=1 (see
/// server/index.mjs's own header) with nothing worth preserving between
/// attempts, and re-authenticating here means a PIN check never trusts a
/// token that might have outlived whatever this session's real lifecycle
/// should be.
///
/// FAILS CLOSED at every stage. [OliveApi.verifyKioskPin] already fails
/// closed on a network error reaching /kiosk-pin/verify itself; the
/// `devLoginFor()` call in front of it is wrapped the same way here — a
/// server that's unreachable, or a dev-login that 404s/500s, must reject the
/// PIN, never accept it. A broken network must never look like a correct PIN.
///
/// [sessionToken], when non-null (a redeemed, paired device — see this
/// file's own header), is used DIRECTLY instead of a fresh `devLoginFor()`
/// call — the real, deviceId-bearing credential this device actually holds,
/// which a DEV_LOGIN-only deployment may not even accept. A real
/// [DeviceRevokedException] here (this device was cut off since it last
/// booted) clears the stored identity so the NEXT cold boot lands back on
/// the pairing screen — see this file's own header for the honest limit of
/// that reaction (it does not hot-swap the CURRENTLY running app).
Future<bool> _verifyGuardianPin(String pin,
    {required String childId, required String? sessionToken}) async {
  try {
    final token = sessionToken ?? await devLoginFor(_dartDefineBaseUrl, childId: childId);
    final api = OliveApi(_dartDefineBaseUrl, token);
    final ok = await api.verifyKioskPin(childId, pin);
    api.close();
    return ok;
  } on DeviceRevokedException {
    unawaited(DeviceIdentityStore().clear());
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
/// above already applies: a devLoginFor()/fetchTheme() failure of ANY kind
/// (unreachable server, malformed body, an unset row) must resolve to
/// [defaultAppTheme] (`classic`/`light` — this app's own former stock
/// look), never a broken/partial theme state and never a thrown exception
/// that would crash this isolate before it ever draws a frame (main.dart's
/// own Firebase try/catch reasoning, applied here to the same boot phase).
/// `AppTheme.fromWire` is ALSO fail-closed on a malformed body — this
/// try/catch is the outer layer, catching a network/auth failure reaching
/// the server at all.
///
/// [sessionToken] — see [_verifyGuardianPin]'s own doc comment; identical
/// reasoning and identical [DeviceRevokedException] reaction, applied here
/// at boot time rather than at kiosk-unlock time.
Future<AppTheme> _fetchInitialTheme(String childId, String? sessionToken) async {
  try {
    final token = sessionToken ?? await devLoginFor(_dartDefineBaseUrl, childId: childId);
    final api = OliveApi(_dartDefineBaseUrl, token);
    final wire = await api.fetchTheme(childId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } on DeviceRevokedException {
    await DeviceIdentityStore().clear();
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
Future<void> _bootLiveApp({required String childId, required String? sessionToken}) async {
  // Resolved BEFORE runApp() -- see _fetchInitialTheme()'s own doc comment.
  final initialTheme = await _fetchInitialTheme(childId, sessionToken);
  runApp(OliveLive(initialTheme: initialTheme, childId: childId, sessionToken: sessionToken));
}

/// Resolves a usable session token for [childId] — [sessionToken] when
/// non-null (a redeemed, paired device), else a fresh `devLoginFor()` call,
/// the identical `sessionToken ?? await devLoginFor(...)` pattern
/// [_verifyGuardianPin]/[_fetchInitialTheme] above already establish. Unlike
/// those two, the resolved token is RETURNED (never discarded) — Automatic
/// First-Run Detection's own [_OnboardingBootApp] below needs a concrete,
/// non-null token to thread into its own live-wired `ObGenderScreen`
/// (onboarding_gender.dart's `_isLive` getter requires one), for BOTH the
/// pairing path (already non-null) AND the dart-define path (always null
/// until this function resolves one). A [DeviceRevokedException] here
/// reacts the same honest way those two already do (clears the stored
/// identity for the next cold boot) and surfaces as `null`, same as any
/// other resolution failure — this function's own caller below fails closed
/// on a null return, exactly like every other boot-time network failure
/// this file already treats as "assume the less-trusted state," never "let
/// her through anyway."
Future<String?> _resolveSessionToken(String childId, String? sessionToken) async {
  if (sessionToken != null) return sessionToken;
  try {
    return await devLoginFor(_dartDefineBaseUrl, childId: childId);
  } on DeviceRevokedException {
    unawaited(DeviceIdentityStore().clear());
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
Future<bool> _fetchHasOnboarded(String childId, String? token) async {
  if (token == null) return false;
  try {
    final api = OliveApi(_dartDefineBaseUrl, token);
    final me = await api.fetchMe();
    api.close();
    return me['hasOnboarded'] == true;
  } catch (_) {
    return false;
  }
}

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
  required String childId, required String? sessionToken,
}) async {
  final token = await _resolveSessionToken(childId, sessionToken);
  final hasOnboarded = await _fetchHasOnboarded(childId, token);
  if (hasOnboarded) {
    await _bootLiveApp(childId: childId, sessionToken: sessionToken);
    return;
  }
  runApp(_OnboardingBootApp(
    baseUrl: _dartDefineBaseUrl,
    childId: childId,
    token: token,
    // The ORIGINAL sessionToken (possibly null), not the locally-resolved
    // [token] above — _bootLiveApp's own downstream helpers already know
    // how to resolve a null sessionToken themselves (their own
    // `sessionToken ?? devLoginFor(...)` pattern), so there is nothing
    // gained by threading the already-resolved one through, and doing so
    // would be the one place in this file where a boot helper receives a
    // token it did not resolve itself.
    onOnboarded: () => _bootLiveApp(childId: childId, sessionToken: sessionToken),
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // MASTERFILE §11 -- registers the real top-level background handler
  // (push_channel.dart's firebaseMessagingBackgroundHandler) at the one
  // place FlutterFire's own docs require it: before runApp(), so a
  // background/terminated-state push tap has a real callback waiting for it
  // from the moment this isolate exists.
  //
  // Wrapped in try/catch because Firebase.initializeApp() genuinely fails in
  // this checkout -- no real android/app/google-services.json exists here
  // (see pubspec.yaml's own comment on why one is not fabricated). Letting
  // that exception escape would crash this entire preview build before it
  // ever draws a frame, which would defeat main_live.dart's whole purpose
  // (see this file's own header -- a real device/emulator target meant to
  // stay inspectable). push_channel.dart's PushChannel.initialize(), called
  // later from child_home_live.dart once a real session exists, is the
  // second, independent attempt -- THAT failure is the one surfaced (as
  // PushInitializationError) rather than silently caught, per house style;
  // this one is intentionally the boot-time exception.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }

  // Device pairing & provisioning boot branch — see this file's own header.
  // The dart-define path below is completely unchanged when the define IS
  // set; `DeviceIdentityStore().load()` is never even called in that case,
  // matching the design spec's own "dart-define, when present, keeps
  // working exactly as today" line literally, not just in effect.
  if (!_hasChildIdDartDefine) {
    final stored = await DeviceIdentityStore().load();
    if (stored == null) {
      runApp(const _PairingBootApp(baseUrl: _dartDefineBaseUrl));
      return;
    }
    await _bootWithOnboardingGate(childId: stored.targetId, sessionToken: stored.sessionToken);
    return;
  }
  // Automatic First-Run Detection applies HERE too — the dart-define path
  // is otherwise completely unchanged (identity resolution itself is
  // untouched, matching device pairing's own precedent above), but it now
  // goes through the SAME gate the paired path does, not straight to
  // _bootLiveApp — see _bootWithOnboardingGate's own doc comment for why
  // that is the point, not an oversight.
  await _bootWithOnboardingGate(childId: _dartDefineChildId, sessionToken: null);
}

/// Shown at boot when there's no dart-define AND no stored identity — see
/// this file's own header. A minimal MaterialApp wrapper (this build's real
/// theme/kiosk tree doesn't exist yet at this point — there is no identity
/// to fetch a theme FOR), matching invitation_screen.dart's own convention
/// of a screen owning its own Scaffold with no assumed ancestor chrome.
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
  Future<void> _onRedeemed(Map<String, dynamic> result) async {
    final identity = DeviceIdentity(
      sessionToken: result['sessionToken'] as String,
      deviceId: result['deviceId'] as String,
      role: result['role'] as String? ?? 'child',
      targetId: result['targetId'] as String,
    );
    await DeviceIdentityStore().save(identity);
    await _bootWithOnboardingGate(childId: identity.targetId, sessionToken: identity.sessionToken);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (pairing)',
    theme: ThemeData(colorScheme: colorSchemeFor(defaultAppTheme), useMaterial3: true),
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
    theme: ThemeData(colorScheme: colorSchemeFor(defaultAppTheme), useMaterial3: true),
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
    required this.childId, required this.sessionToken});

  /// The session-bootstrap-resolved theme (`_fetchInitialTheme()`), already
  /// fail-closed to [defaultAppTheme] on any failure -- this widget never
  /// re-derives that fallback itself.
  final AppTheme initialTheme;

  /// Resolved BEFORE this widget is constructed — either the dart-define
  /// value, or a redeemed/stored identity's own targetId. See this file's
  /// own header.
  final String childId;

  /// Non-null only for a redeemed, paired device — see [_verifyGuardianPin]/
  /// [_fetchInitialTheme]'s own doc comments for how this is used instead
  /// of a fresh `devLoginFor()` call at THIS file's own boot-time call
  /// sites.
  final String? sessionToken;

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
      final scheme = colorSchemeFor(_themeController.value);
      final themeData = ThemeData(colorScheme: scheme, useMaterial3: true);
      return MaterialApp(
        navigatorKey: _navigatorKey,
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
          child: child!,
        ),
        home: KioskShell(
          verifyPin: (pin) => _verifyGuardianPin(pin,
            childId: widget.childId, sessionToken: widget.sessionToken),
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
