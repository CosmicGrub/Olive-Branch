// OLIVE BRANCH — the guardian shell's boot, shared by the unified live entry
// (main_live.dart) and the thin legacy wrapper (main_live_guardian.dart). No longer
// UNVERIFIED as code — analysed by CI (`flutter analyze`) and its widgets and pure parts
// are tested (client/test/main_live_guardian_test.dart, guardian_boot_test.dart); the
// on-device run is manual. MASTERFILE §7, §8.5.8, §8.5.9.
//
// This is the body of what main_live_guardian.dart used to be, moved here so ONE entry
// point can reach it (owner requirement 2026-11-08: the role decides the shell; the audits
// note both targets share one package id). The behaviour below is unchanged unless it says
// otherwise:
//
//  * The live shell ([bootLiveGuardian], [OliveLiveGuardian]) is the real GuardianHome on a
//    real AuthSession (device credential -> short sessions, auth_session.dart), with the
//    server-PIN gate (`GET /v1/me` hasPin -> GuardianSetupScreen). The dev path
//    (OLIVE_GUARDIAN_ID, or OLIVE_DEV_LOGIN=1) additionally needs the server's DEV_LOGIN=1;
//    guardianId defaults to seed-dev.mjs's "Dad".
//  * A guardian pairing code binds a device to the CALLER'S OWN app_user.id, never to a child,
//    so this build's `childId` stays the pre-existing `OLIVE_CHILD_ID` default (a real,
//    disclosed gap; see docs/superpowers/specs/2026-09-12-device-pairing-provisioning-design.md).
//
// WHAT IS NEW (MASTERFILE §8.5.9):
//  * LOCAL FIRST. A grown-up who has not connected runs [bootGuardianFlow]: the guardian
//    onboarding (a local family and a local PIN), then the offline home ([OliveLocalGuardian]).
//    Connecting stays available, last in the onboarding and afterwards in Settings > Account.
//  * NO MORE OFFLINE SERVER-PIN TRAP. The boot gate used to treat "could not ask the server"
//    as "no PIN" and show a server-PIN setup that needs the server. [resolveGuardianEntry]
//    (live_boot_plan.dart) now tells the three apart: the server says yes (enter), the server
//    says no (the server-PIN setup, unchanged), the server cannot be asked (a LOCAL PIN is
//    enough to enter; without one, a local PIN is set, which works offline). While a session
//    exists and the server answers, the server PIN rules are exactly what they were.
//  * A connected grown-up who is offline and has a local family lands on the local home, not on
//    the "Couldn't reach the server" error.
import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_session.dart';
import 'device_identity.dart';
import 'device_role.dart';
import 'guardian_home_live.dart';
import 'guardian_local_scope.dart';
import 'play_notice.dart' show PlayAudience, PlayAudienceScope;
import 'guardian_onboarding.dart';
import 'guardian_setup.dart';
import 'live_boot_plan.dart';
import 'live_common.dart';
import 'local_family.dart';
import 'local_guardian_home.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_pin_screens.dart';
import 'local_services.dart';
import 'pairing_redeem_screen.dart';
import 'theme.dart';
import 'theme_data.dart';

/// The one session for a paired guardian device. When it ends (sign-out, revoked,
/// deactivated) the shell returns to pairing, or to the offline home if this device has a
/// local family ([_returnToPairing]).
AuthSession _deviceSession(DeviceIdentity identity) =>
    AuthSession.device(baseUrl: kLiveBaseUrl, identity: identity, onSignedOut: _returnToPairing);

/// Where a grown-up goes when the connection ends. With a local family and PIN the device keeps
/// working offline: back to that home. Without them, the code screen, as before.
void _returnToPairing() {
  unawaited(() async {
    try {
      final LocalServices s = LocalServices.current;
      final GuardianLocalServices local = GuardianLocalServices.from(s);
      if (await local.families.load() != null && await local.pin.isSet()) {
        await bootGuardianFlow(DeviceRole.other, reuseStorage: true);
        return;
      }
    } catch (_) {
      // Fall through to the code screen.
    }
    runApp(const _PairingBootApp(baseUrl: kLiveBaseUrl));
  }());
}

/// The theme half of session bootstrap — same fail-closed discipline as main_live.dart's
/// `_fetchInitialTheme`: any failure resolves to [defaultAppTheme], never a thrown
/// exception before the first frame.
Future<AppTheme> _fetchInitialTheme(String guardianId) async {
  try {
    final api = await apiFor(kLiveBaseUrl, userId: guardianId);
    final wire = await api.fetchTheme(kLiveChildId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } on DeviceRevokedException {
    return defaultAppTheme;
  } catch (_) {
    return defaultAppTheme;
  }
}

/// GET /v1/me's `hasPin` field (Automatic First-Run Detection). Three answers, not two: true,
/// false, and null when the server could not be asked (no signal, a failed call). The old
/// version folded null into false, which is what trapped an offline grown-up on a server-PIN
/// setup that needs the server ([resolveGuardianEntry] now tells them apart). A revoked
/// device still reports false (the session has already sent the shell back to pairing).
Future<bool?> _fetchServerHasPin(String guardianId) async {
  try {
    final api = await apiFor(kLiveBaseUrl, userId: guardianId);
    final me = await api.fetchMe();
    api.close();
    return me['hasPin'] == true;
  } on DeviceRevokedException {
    return false;
  } catch (_) {
    return null;
  }
}

/// Real POST /v1/me/pin for the boot-time gate. First-PIN only: the server needs no proof
/// when no PIN exists yet (the gate only shows when hasPin is false).
Future<void> Function(String pin) _liveSetGuardianPin({required String guardianId}) {
  return (String pin) async {
    final api = await apiFor(kLiveBaseUrl, userId: guardianId);
    try {
      await api.setGuardianPin(pin);
    } finally {
      api.close();
    }
  };
}

/// GuardianSetupScreen.checkExistingPin for the boot-time gate.
Future<bool> Function() _liveCheckExistingPin({required String guardianId}) {
  return () async => (await _fetchServerHasPin(guardianId)) ?? false;
}

/// Opens this device's on-device storage. If the platform storage cannot be opened the app
/// runs in memory (nothing persists that run) rather than failing to boot.
Future<void> _openLocalStorage(String guardianId) async {
  try {
    await LocalServices.boot(childId: 'guardian-device', guardianId: guardianId, isLive: true);
  } catch (e) {
    debugPrint('[olive.localStore] on-device storage unavailable, running in memory: $e');
    LocalServices.install(LocalServices.memory(
        childId: 'guardian-device', guardianId: guardianId, isLive: true, demoSeeds: false));
  }
}

/// Boots the real (connected) guardian shell for [guardianId] — the common tail of the dev path
/// and a freshly-redeemed pairing. Also what GuardianSetupScreen's `onComplete` re-invokes
/// ("the very next boot proceeds to GuardianHome normally").
Future<void> bootLiveGuardian({required String guardianId, required AuthSession session}) async {
  // Installed BEFORE anything below calls apiFor() — every live screen reads the same
  // process-wide session (audit G-02/G-06).
  AuthSession.use(session);
  // On-device storage for this grown-up (Parent Learn, sealed, keyed by their own id). The
  // local family and local PIN areas are keyed by [kLocalGuardianScope], so they survive
  // connecting.
  await _openLocalStorage(guardianId);
  final GuardianLocalServices local = GuardianLocalServices.from(LocalServices.current);
  final initialTheme = await _fetchInitialTheme(guardianId);
  final bool? serverHasPin = await _fetchServerHasPin(guardianId);
  final bool localPinSet = await _safe(local.pin.isSet, false);
  final GuardianEntry entry = resolveGuardianEntry(serverHasPin: serverHasPin, localPinSet: localPinSet);
  final LocalFamily? family = await _safe(local.families.load, null);
  final GuardianLocalController controller = GuardianLocalController(local, family: family);
  // Offline (the server could not be asked) with a local family: its own home, not an error.
  if (serverHasPin == null && entry == GuardianEntry.home && family != null) {
    runApp(OliveLocalGuardian(initialTheme: initialTheme, controller: controller));
    return;
  }
  runApp(OliveLiveGuardian(
    initialTheme: initialTheme,
    guardianId: guardianId,
    session: session,
    hasPin: entry != GuardianEntry.serverPinSetup,
    entry: entry,
    local: controller,
  ));
}

Future<T> _safe<T>(Future<T> Function() f, T fallback) async {
  try {
    return await f();
  } catch (_) {
    return fallback;
  }
}

/// The dev path (OLIVE_GUARDIAN_ID provisioned): a refreshable dev-login session.
Future<void> bootGuardianDev() async {
  AuthSession.devLoginEnabled = true;
  await bootLiveGuardian(
    guardianId: kLiveGuardianId,
    session: AuthSession.dev(baseUrl: kLiveBaseUrl, userId: kLiveGuardianId, refreshable: true),
  );
}

/// A connected guardian device (a stored identity).
Future<void> bootGuardianPaired(DeviceIdentity stored) =>
    bootLiveGuardian(guardianId: stored.targetId, session: _deviceSession(stored));

/// A successful redeem: store the identity FIRST, then boot the connected shell.
Future<void> completeGuardianRedeem(Map<String, dynamic> result) async {
  final identity = DeviceIdentity(
    sessionToken: result['sessionToken'] as String,
    deviceId: result['deviceId'] as String,
    role: result['role'] as String? ?? 'guardian',
    targetId: result['targetId'] as String,
    deviceCredential: result['deviceCredential'] as String?,
  );
  await DeviceIdentityStore().save(identity);
  await bootLiveGuardian(guardianId: identity.targetId, session: _deviceSession(identity));
}

/// A grown-up role with no identity: the local family. Runs the guardian onboarding when there
/// is no local family and PIN yet, otherwise opens the offline home. [reuseStorage] keeps the
/// already-open store (the unified entry opened it to read the role).
Future<void> bootGuardianFlow(DeviceRole role, {bool reuseStorage = false}) async {
  if (!reuseStorage) await _openLocalStorage(kLocalGuardianScope);
  final GuardianLocalServices local = GuardianLocalServices.from(LocalServices.current);
  final LocalFamily? family = await _safe(local.families.load, null);
  final bool pinSet = await _safe(local.pin.isSet, false);
  if (family != null && pinSet) {
    final GuardianLocalController controller =
        GuardianLocalController(local, family: family, onConnect: _openConnect);
    runApp(OliveLocalGuardian(initialTheme: defaultAppTheme, controller: controller));
    return;
  }
  runApp(_GuardianOnboardingApp(role: role, services: local));
}

/// Settings > Account > Connect this device: the optional code screen. "Not now" goes back.
void _openConnect(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (BuildContext routeContext) => PairingRedeemScreen(
      baseUrl: kLiveBaseUrl,
      role: 'guardian',
      localFirst: true,
      onNotNow: () => Navigator.of(routeContext).pop(),
      onRedeemed: (Map<String, dynamic> r) => unawaited(completeGuardianRedeem(r)),
    ),
  ));
}

/// The pairing screen alone, for a device that was connected and has been cut off and has no
/// local family to fall back to.
class _PairingBootApp extends StatelessWidget {
  const _PairingBootApp({required this.baseUrl});
  final String baseUrl;

  Future<void> _onRedeemed(Map<String, dynamic> result) => completeGuardianRedeem(result);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (pairing)',
    theme: buildThemeData(defaultAppTheme),
    home: PairingRedeemScreen(baseUrl: baseUrl, role: 'guardian', onRedeemed: _onRedeemed),
  );
}

/// The guardian onboarding in a bare MaterialApp (no shell exists yet). On finish it boots the
/// local flow again, which now finds the family and PIN and opens the offline home.
class _GuardianOnboardingApp extends StatelessWidget {
  const _GuardianOnboardingApp({required this.role, required this.services});
  final DeviceRole role;
  final GuardianLocalServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (set up)',
    theme: buildThemeData(defaultAppTheme),
    home: GuardianOnboardingFlow(
      role: role,
      services: services,
      serverAvailable: true,
      baseUrl: kLiveBaseUrl,
      onRedeemed: (Map<String, dynamic> r) => unawaited(completeGuardianRedeem(r)),
      onFinished: (LocalFamily _) => unawaited(bootGuardianFlow(role, reuseStorage: true)),
    ),
  );
}

/// The MaterialApp both guardian apps share: the same theme handling the live guardian always
/// had, plus the local scope above the Navigator so pushed screens can reach it.
Widget _guardianApp({
  required ThemeController theme,
  required String title,
  required Widget home,
  GuardianLocalController? local,
}) =>
    AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        final scheme = colorSchemeFor(theme.value);
        final themeData = ThemeData(colorScheme: scheme, useMaterial3: true);
        return MaterialApp(
          title: title,
          theme: themeData,
          darkTheme: themeData,
          themeMode: theme.value.brightness == ThemeBrightness.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final Widget animated = AnimatedTheme(
              data: themeData,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOut,
              child: child!,
            );
            // The guardian shell speaks the adult's voice in the ad-hoc play notices (play_notice.dart).
            final Widget voiced = PlayAudienceScope(audience: PlayAudience.adult, child: animated);
            return local == null ? voiced : GuardianLocalScope(controller: local, child: voiced);
          },
          home: home,
        );
      },
    );

class OliveLiveGuardian extends StatefulWidget {
  const OliveLiveGuardian({super.key, this.initialTheme = defaultAppTheme,
    required this.guardianId, required this.session, required this.hasPin,
    this.entry, this.local});
  final AppTheme initialTheme;

  /// Resolved BEFORE this widget is constructed — either the dart-define value, or a
  /// redeemed/stored identity's own targetId.
  final String guardianId;

  /// The installed [AuthSession] ([bootLiveGuardian] installs it process-wide BEFORE
  /// constructing this widget) — real for a paired device and for the explicit dev path; null
  /// only in a widget test that supplies its own transport.
  final AuthSession? session;

  /// GET /v1/me's `hasPin`, resolved BEFORE construction. `false` renders [GuardianSetupScreen]
  /// in place of the home — a hard, non-dismissible gate, re-resolved on every launch. Applies
  /// identically whether [guardianId] came from a dart-define or a redeemed pairing.
  final bool hasPin;

  /// Overrides [hasPin] with the three-way boot answer ([resolveGuardianEntry]). Null keeps the
  /// two-way behaviour tests and older callers use.
  final GuardianEntry? entry;

  /// The local family, PIN and connect hook, offered to screens below via [GuardianLocalScope].
  final GuardianLocalController? local;

  @override
  State<OliveLiveGuardian> createState() => _OliveLiveGuardianState();
}

class _OliveLiveGuardianState extends State<OliveLiveGuardian> {
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Widget _home() {
    final GuardianEntry entry =
        widget.entry ?? (widget.hasPin ? GuardianEntry.home : GuardianEntry.serverPinSetup);
    switch (entry) {
      case GuardianEntry.home:
        return LiveGuardianHomeScreen(
          baseUrl: kLiveBaseUrl,
          guardianId: widget.guardianId,
          childId: kLiveChildId,
        );
      case GuardianEntry.serverPinSetup:
        return GuardianSetupScreen(
          setGuardianPin: _liveSetGuardianPin(guardianId: widget.guardianId),
          checkExistingPin: _liveCheckExistingPin(guardianId: widget.guardianId),
          onComplete: () => bootLiveGuardian(guardianId: widget.guardianId, session: widget.session!),
        );
      case GuardianEntry.localPinSetup:
        return LocalPinSetupScreen(
          service: widget.local!.services.pin,
          onDone: () => unawaited(bootLiveGuardian(guardianId: widget.guardianId, session: widget.session!)),
        );
    }
  }

  @override
  Widget build(BuildContext context) => _guardianApp(
        theme: _themeController,
        title: 'Olive (live guardian)',
        home: _home(),
        local: widget.local,
      );
}

/// The offline guardian: the local family's home, no server and no session. Same theme handling
/// as [OliveLiveGuardian].
class OliveLocalGuardian extends StatefulWidget {
  const OliveLocalGuardian({super.key, this.initialTheme = defaultAppTheme, required this.controller});
  final AppTheme initialTheme;
  final GuardianLocalController controller;

  @override
  State<OliveLocalGuardian> createState() => _OliveLocalGuardianState();
}

class _OliveLocalGuardianState extends State<OliveLocalGuardian> {
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _guardianApp(
        theme: _themeController,
        title: 'Olive (guardian)',
        local: widget.controller,
        home: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, Widget? _) {
            final LocalFamily? f = widget.controller.family;
            return f == null ? const Scaffold(body: Center(child: CircularProgressIndicator())) : LocalGuardianHome(family: f);
          },
        ),
      );
}
