// OLIVE BRANCH — live-backend GUARDIAN entry point. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §7.
//
// A THIRD build target, alongside main.dart (offline preview) and
// main_live.dart (live CHILD entry point — see that file's own header for
// why it's a separate target). Every guardian-facing live screen this repo
// already has (guardian_more.dart's hub, message banking, care note,
// emergency card, handover notes, availability, theme picker, kiosk PIN
// setup...) sat completely unreachable from any real, running build until
// this file existed — main_live.dart's own OliveLive.build() comment says so
// directly: "guardian_more.dart... is not (yet) wired into this live entry
// point's own tree." This file is that wiring, for the pieces that don't
// need a server endpoint this repo doesn't have yet.
//
// v0.49.57: now boots into the real, live GuardianHome (guardian_home_live
// .dart) — MASTERFILE §20.2b's own longest-standing tracked gap, closed.
// The `/ribbon` endpoint this file's own header used to describe as
// missing (api_client.dart's `OliveApi.childRibbon` — a dead path constant
// with no server route or client fetch method behind it) is real now
// (server/routes.mjs, GET .../ribbon); guardian_home_live.dart is what it
// unblocks. GuardianHome's own "More" tile still reaches GuardianMoreScreen
// exactly as it always has (guardian_home.dart:188-198, unmodified) — this
// file's own boot target is the only thing that changed.
//
// Real, disclosed gap this live wrapper carries forward, not invented here:
// `childStateSentence`/`overlapLabel` both render as nothing (no real
// data source for either exists yet) — see guardian_home_live.dart's own
// header for the full account of what's real and what's still an honest
// absence.
//
// `flutter run --target=lib/main_live_guardian.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required). guardianId
// defaults to the seed data in server/seed-dev.mjs ("Dad").
//
// Device pairing & provisioning (docs/superpowers/specs/2026-09-12-device
// -pairing-provisioning-design.md) — the IDENTICAL boot-branch shape
// main_live.dart's own header describes in full, applied here to
// `OLIVE_GUARDIAN_ID` instead of `OLIVE_CHILD_ID`. One disclosed, honest
// difference from that file: a guardian-role pairing code binds a device to
// the CALLER'S OWN app_user.id (POST /v1/me/device-pairing-codes), never to
// any particular child — there is no childId anywhere in a guardian-role
// redeem response for this file to resolve "which child does this guardian
// see" from. This build's own `childId` therefore stays exactly the
// pre-existing `OLIVE_CHILD_ID` default it always was, unaffected by
// pairing — resolving "which child(ren) a multi-child guardian's newly
// paired device should actually show" is a real, disclosed gap the design
// spec itself doesn't address (out of scope: see this PR's own description).
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'device_identity.dart';
import 'guardian_home_live.dart';
import 'pairing_redeem_screen.dart';
import 'push_channel.dart';
import 'theme.dart';

const _dartDefineBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _dartDefineChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const _dartDefineGuardianId = String.fromEnvironment('OLIVE_GUARDIAN_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad
// `bool.hasEnvironment`, not a defaultValue comparison — see main_live.dart's
// own header for why the two are not the same question.
const _hasGuardianIdDartDefine = bool.hasEnvironment('OLIVE_GUARDIAN_ID');

/// The theme half of session bootstrap — same posture and same fail-closed
/// discipline as main_live.dart's own [_fetchInitialTheme] (that file's own
/// doc comment explains the reasoning this mirrors verbatim); duplicated
/// rather than shared because the two files intentionally have no common
/// import between them (separate entry points, separate `void main()`s —
/// sharing a helper would mean a fourth file just for two nine-line
/// functions, more indirection than the duplication it would remove).
///
/// [sessionToken], when non-null (a redeemed, paired device), is used
/// DIRECTLY instead of a fresh `devLoginFor()` call — same reasoning
/// main_live.dart's own [_fetchInitialTheme] already documents, including
/// its [DeviceRevokedException] reaction.
Future<AppTheme> _fetchInitialTheme(String guardianId, String? sessionToken) async {
  try {
    final token = sessionToken ?? await devLoginFor(_dartDefineBaseUrl, userId: guardianId);
    final api = OliveApi(_dartDefineBaseUrl, token);
    final wire = await api.fetchTheme(_dartDefineChildId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } on DeviceRevokedException {
    await DeviceIdentityStore().clear();
    return defaultAppTheme;
  } catch (_) {
    return defaultAppTheme;
  }
}

/// Boots the real guardian shell for [guardianId] — the common tail of both
/// the dart-define path and a freshly-redeemed pairing. Mirrors
/// main_live.dart's own `_bootLiveApp` exactly.
Future<void> _bootLiveApp({required String guardianId, required String? sessionToken}) async {
  final initialTheme = await _fetchInitialTheme(guardianId, sessionToken);
  runApp(OliveLiveGuardian(initialTheme: initialTheme,
    guardianId: guardianId, sessionToken: sessionToken));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same try/catch, same reasoning, as main_live.dart's own `main()` — see
  // that file's header comment on why a missing google-services.json must
  // never crash this build before its first frame.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }

  // Device pairing & provisioning boot branch — see this file's own header.
  if (!_hasGuardianIdDartDefine) {
    final stored = await DeviceIdentityStore().load();
    if (stored == null) {
      runApp(const _PairingBootApp(baseUrl: _dartDefineBaseUrl));
      return;
    }
    await _bootLiveApp(guardianId: stored.targetId, sessionToken: stored.sessionToken);
    return;
  }
  await _bootLiveApp(guardianId: _dartDefineGuardianId, sessionToken: null);
}

/// Shown at boot when there's no dart-define AND no stored identity — see
/// main_live.dart's own [_PairingBootApp], which this mirrors exactly
/// except for `role: 'guardian'`.
class _PairingBootApp extends StatelessWidget {
  const _PairingBootApp({required this.baseUrl});
  final String baseUrl;

  Future<void> _onRedeemed(Map<String, dynamic> result) async {
    final identity = DeviceIdentity(
      sessionToken: result['sessionToken'] as String,
      deviceId: result['deviceId'] as String,
      role: result['role'] as String? ?? 'guardian',
      targetId: result['targetId'] as String,
    );
    await DeviceIdentityStore().save(identity);
    await _bootLiveApp(guardianId: identity.targetId, sessionToken: identity.sessionToken);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (pairing)',
    theme: ThemeData(colorScheme: colorSchemeFor(defaultAppTheme), useMaterial3: true),
    home: PairingRedeemScreen(baseUrl: baseUrl, role: 'guardian', onRedeemed: _onRedeemed),
  );
}

class OliveLiveGuardian extends StatefulWidget {
  const OliveLiveGuardian({super.key, this.initialTheme = defaultAppTheme,
    required this.guardianId, required this.sessionToken});
  final AppTheme initialTheme;

  /// Resolved BEFORE this widget is constructed — either the dart-define
  /// value, or a redeemed/stored identity's own targetId.
  final String guardianId;

  /// Non-null only for a redeemed, paired device.
  final String? sessionToken;

  @override
  State<OliveLiveGuardian> createState() => _OliveLiveGuardianState();
}

class _OliveLiveGuardianState extends State<OliveLiveGuardian> {
  // Same shape as main_live.dart's own _OliveLiveState — see that class's
  // own comment. Nothing in THIS build's tree updates it yet either
  // (guardian_more.dart's theme picker calls onThemeApplied, left
  // unwired here for the same reason main_live.dart's own comment names:
  // a second, separate gap, not invented shut here either).
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

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
        title: 'Olive (live guardian)',
        theme: themeData,
        darkTheme: themeData,
        themeMode: _themeController.value.brightness == ThemeBrightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => AnimatedTheme(
          data: themeData,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOut,
          child: child!,
        ),
        // LiveGuardianHomeScreen owns its own Scaffold in every _LoadState —
        // see its own build() method; no wrapping Scaffold needed here.
        // No longer `const` — guardianId is resolved at runtime now (the
        // dart-define value, or a redeemed/stored identity's own targetId).
        home: LiveGuardianHomeScreen(
          baseUrl: _dartDefineBaseUrl,
          guardianId: widget.guardianId,
          childId: _dartDefineChildId,
        ),
      );
    },
  );
}
