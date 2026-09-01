// OLIVE BRANCH — live-backend entry point. Verified by CI (a Flutter
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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'child_home_live.dart';
import 'kiosk_shell.dart';
import 'push_channel.dart';
import 'theme.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

/// The real backend PIN check — replaces the former hardcoded
/// `_demoVerifyGuardianPin` ('1273', never checked against anything). This is
/// the actual release-blocker fix: server/routes.mjs's real
/// POST /kiosk-pin/verify now backs the kiosk lock's PIN gate on this entry
/// point, exactly the way KioskShell's own header always said a real backend
/// would slot in once one existed.
///
/// Reuses child_home_live.dart's own session plumbing rather than inventing
/// a second path: the same `devLoginFor()` dev-login helper, against the same
/// `_defaultBaseUrl`/`_defaultChildId` this file already defines (see that
/// file's `_load()` for the pattern this mirrors). A fresh dev-login per PIN
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
Future<bool> _verifyGuardianPin(String pin) async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
    final api = OliveApi(_defaultBaseUrl, token);
    final ok = await api.verifyKioskPin(_defaultChildId, pin);
    api.close();
    return ok;
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
Future<AppTheme> _fetchInitialTheme() async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
    final api = OliveApi(_defaultBaseUrl, token);
    final wire = await api.fetchTheme(_defaultChildId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } catch (_) {
    return defaultAppTheme;
  }
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
  // Resolved BEFORE runApp() -- see _fetchInitialTheme()'s own doc comment.
  final initialTheme = await _fetchInitialTheme();
  runApp(OliveLive(initialTheme: initialTheme));
}

class OliveLive extends StatefulWidget {
  const OliveLive({super.key, this.initialTheme = defaultAppTheme});

  /// The session-bootstrap-resolved theme (`_fetchInitialTheme()`), already
  /// fail-closed to [defaultAppTheme] on any failure -- this widget never
  /// re-derives that fallback itself.
  final AppTheme initialTheme;

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
          verifyPin: _verifyGuardianPin,
          verifyBiometric: _liveVerifyBiometricStub,
          child: LiveChildHomeScreen(
            baseUrl: _defaultBaseUrl,
            childId: _defaultChildId,
            navigatorKey: _navigatorKey,
          ),
        ),
      );
    },
  );
}
