// OLIVE BRANCH — guardian shell, "more" hub. No longer UNVERIFIED — verified by
// CI (`flutter analyze` and `flutter test` run for real in tools/verify.sh and
// .github/workflows/verify.yml). Navigation-wiring-pass addition, not a MARKUP
// screen of its own.
//
// guardian_home.dart's own grid stays at the size a real dashboard can
// carry; this hub is where the wiring pass hangs the remaining
// guardian-facing screens (archive/export, live-call extras, showcase's
// guardian side, family setup) that don't have their own top-level tile, so
// "every new screen must be reachable" holds without crowding that home
// screen the way child_more.dart does for the child side.
import 'guardian_pin_recovery_screens.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_lock_screen.dart';
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'family_structure_screens.dart';
import 'family_structure_store.dart';
import 'parent_learn_logic.dart';
import 'parent_learn_screens.dart';
import 'parent_learn_store.dart';
import 'adults_helpers_screen.dart';
import 'age_lock_screens.dart';
import 'connect_child_screen.dart';
import 'connected_devices_screen.dart';
import 'unlock_challenge.dart' show UnlockResponder;
import 'unlock_child_screen.dart';
import 'device_keys.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_services.dart';
import 'pairing_records.dart';
import 'guardian_names_screen.dart';
import 'api_client.dart';
import 'auth_session.dart';
import 'availability_screen.dart';
import 'busy_fork.dart';
import 'care_local.dart' show CareService;
import 'care_local_screens.dart';
import 'care_screens.dart';
import 'call_screen.dart';
import 'call_security_info.dart';
import 'closing_ritual.dart';
import 'colour_parent.dart';
import 'court_export.dart';
import 'degradation_banner.dart';
import 'deletion_screen.dart';
import 'emergency_card.dart';
import 'emergency_card_local.dart';
import 'exchange_screen.dart';
import 'expenses_screen.dart';
import 'expiry_digest.dart';
import 'family_agreement_screen.dart';
import 'gallery_screen.dart';
import 'ui/olive_ui_gallery.dart';
import 'game_navigation.dart';
import 'game_picker.dart';
import 'games_hub.dart';
import 'guardian_local_scope.dart';
import 'guardian_setup.dart';
import 'guardian_settings_hub.dart';
import 'her_colour_guardian.dart';
import 'play_window_screen.dart';
import 'handover_notes.dart';
import 'her_suites_screen.dart';
import 'hub_widgets.dart';
import 'access_screen.dart';
import 'add_device_screen.dart';
import 'invitation_screen.dart';
import 'paired_devices_list.dart';
import 'parental_controls_screen.dart';
import 'jokebook_screen.dart';
import 'live_game_picker.dart';
import 'local_pin_screens.dart';
import 'lock_advisory_screen.dart';
import 'clear_local_data_screen.dart';
import 'maturation_ladder.dart';
import 'meds_care.dart';
import 'palette_logic.dart';
import 'push_channel.dart';
import 'compass_repositories.dart';
import 'compass_screens.dart';
import 'growing_care_store.dart' show GrowingCareStores;
import 'local_services.dart' show LocalServices;
import 'rhythm_logic.dart' show RhythmDoc, RoutineStep;
import 'rhythm_voice_guardian_screens.dart';
import 'rhythm_voice_repositories.dart';
import 'show_guardian.dart';
import 'village_guardian_screens.dart';
import 'village_repositories.dart';
import 'siblings_screen.dart';
import 'storyteller_screen.dart' show StorytellerSafetyScreen;
import 'the_book.dart';
import 'theme.dart';
import 'theme_picker_screen.dart';
import 'webauthn_channel.dart';
import 'year_book.dart';

/// server/index.mjs never got the FamilyAgreementScreen tile a real network
/// call: this hub has no baseUrl/session anywhere (it's reached from main.dart's
/// intentionally offline demo shell — see that file's own header on why
/// bolting live networking onto it would break the one thing it's for; only
/// main_live.dart's child-side screens do that today). So the default
/// [GuardianMoreScreen.fetchAgreementOrder] does not pretend to reach a
/// server that isn't there — it throws a real, honest error, which
/// FamilyAgreementScreen's own real error state then surfaces truthfully.
/// A live caller overrides this with the real thing, e.g.
/// `(id) => OliveApi(baseUrl, token).getCustodyOrder(id)`.
Future<Map<String, dynamic>> _noLiveBackendWired(String childId) async =>
    throw StateError('No live backend is wired into this preview build yet — '
        'see main_live.dart for the real network path.');

/// Real POST /v1/me/pin (OliveApi.setGuardianPin) when this hub has an
/// actual live session (baseUrl/guardianId — see GuardianMoreScreen's own
/// field doc comments); returns a callback GuardianSetupScreen can call
/// directly, or null when there's no live session to set a PIN against —
/// GuardianSetupScreen's own [_submitPin] already gives an honest "no
/// backend wired" message for a null [GuardianSetupScreen.setGuardianPin],
/// same convention [_noLiveBackendWired] above uses for its own live/offline
/// split. A fresh devLoginFor() per call, not a session cached on this
/// (stateless) widget — same posture main_live.dart's own
/// _verifyGuardianPin/_fetchInitialTheme already hold themselves to, for
/// the same reason: nothing here should trust a token that might have
/// outlived whatever this widget's own lifecycle is.
Future<void> Function(String pin)? _liveSetGuardianPin(
    {required String? baseUrl, required String? guardianId, http.Client? httpClient}) {
  if (baseUrl == null || guardianId == null) return null;
  return (String pin) async {
    final api = await apiFor(baseUrl, userId: guardianId, client: httpClient);
    try {
      await api.setGuardianPin(pin);
    } finally {
      if (httpClient == null) api.close();
    }
  };
}

/// POST /v1/me/pin with currentPin (OliveApi.changeGuardianPin) — the proved
/// replacement of an existing PIN (audit G-13); null with no live session.
Future<void> Function(String currentPin, String newPin)? _liveChangeGuardianPin(
    {required String? baseUrl, required String? guardianId, http.Client? httpClient}) {
  if (baseUrl == null || guardianId == null) return null;
  return (String currentPin, String newPin) async {
    final api = await apiFor(baseUrl, userId: guardianId, client: httpClient);
    try {
      await api.changeGuardianPin(currentPin, newPin);
    } finally {
      if (httpClient == null) api.close();
    }
  };
}

/// GuardianSetupScreen.checkExistingPin — Onboarding & Guardian Access
/// sub-project 1 (docs/superpowers/specs/2026-09-12-onboarding-identity-pin
/// -design.md). Real `GET /v1/me`'s new `hasPin` field (server/routes.mjs)
/// when this hub has an actual live session; returns a callback
/// GuardianSetupScreen resolves itself on init, or null when there's no live
/// session to check against — the identical shape [_liveSetGuardianPin]
/// above already establishes, including its own fresh-devLoginFor()-per-call
/// posture (nothing here trusts a token that might have outlived this
/// (stateless) widget's own lifecycle).
Future<bool> Function()? _liveCheckExistingPin(
    {required String? baseUrl, required String? guardianId, http.Client? httpClient}) {
  if (baseUrl == null || guardianId == null) return null;
  return () async {
    final api = await apiFor(baseUrl, userId: guardianId, client: httpClient);
    try {
      final me = await api.fetchMe();
      return me['hasPin'] == true;
    } finally {
      if (httpClient == null) api.close();
    }
  };
}

/// The PIN check behind "Clear data on this device": POST
/// /v1/me/verify-controls-pin (the same re-verification ParentalControlsScreen
/// uses) when this hub has a live session, null otherwise. FAILS CLOSED: any
/// error — wrong PIN, network, a lapsed session — is `false`, never a pass.
Future<bool> Function(String pin)? _liveVerifyWipePin(
    {required String? baseUrl, required String? guardianId, http.Client? httpClient}) {
  if (baseUrl == null || guardianId == null) return null;
  return (String pin) async {
    try {
      final api = await apiFor(baseUrl, userId: guardianId, client: httpClient);
      try {
        await api.verifyControlsPin(pin);
        return true;
      } finally {
        if (httpClient == null) api.close();
      }
    } catch (_) {
      return false;
    }
  };
}

class GuardianMoreScreen extends StatelessWidget {
  const GuardianMoreScreen({
    super.key,
    this.childName = 'Ivy',
    this.childAge = 9,
    this.baseUrl,
    this.guardianId,
    // seed-dev.mjs's own seeded "Ivy" — the same real id main_live.dart's
    // own _defaultChildId already uses for this exact demo child, not a
    // fabricated placeholder. Non-nullable (unlike baseUrl/guardianId below):
    // this same id doubles as the family-agreement fetch target, which needs
    // SOME concrete child in scope even before a live session exists —
    // _noLiveBackendWired is what stays honest about the backend, not this.
    this.childId = 'aaaaaaaa-0000-4000-8000-000000000001',
    this.availabilityHttpClient,
    this.fetchAgreementOrder,
    this.currentTheme = defaultAppTheme,
    this.onThemeApplied,
    this.onCallStarted,
    this.learnStore,
    this.familyService,
    this.showDemoTiles,
  });
  final String childName;
  final int childAge;
  /// G-12: whether the tiles that render INVENTED family content (a hard-
  /// coded colour history, a made-up Year book/Gallery/The book, and the
  /// "(demo)" call-feature walkthroughs) are listed. Null (the default) means
  /// "only in the offline demo build": a hub with a live session (baseUrl and
  /// guardianId) hides them, so a real parent never sees family history this
  /// app invented. A dev verification entry point can pass true explicitly.
  final bool? showDemoTiles;
  bool get _showDemo => showDemoTiles ?? !(baseUrl != null && guardianId != null);
  /// Parent Learn storage. Null = the in-process store (nothing leaves this phone); a
  /// server-backed LearnStore is passed in once a live session exists.
  final LearnStore? learnStore;

  /// Family structure and age bands, local-first. Null = the in-process [localFamilyService]
  /// (nothing leaves this device; syncing between devices comes later).
  final FamilyService? familyService;
  /// Live-session wiring for AvailabilityScreen, the family-agreement fetch,
  /// AND the Court export tile below all key off this same child —
  /// baseUrl/guardianId stay optional and default to null because nothing
  /// upstream of this hub (guardian_home.dart, main.dart's static demo data)
  /// carries a real base URL or guardian id yet; every other call site in
  /// this file is still the same pre-backend demo build LiveChildHomeScreen's
  /// own header describes for the child side. When baseUrl/guardianId ARE
  /// supplied, the Availability and Court export tiles open their real
  /// screens; otherwise each gives the same honest not-connected feedback
  /// guardian_setup.dart's passkey button gives when its own real dependency
  /// isn't wired in yet — never a silent no-op, and never a screen
  /// pretending to have live data it doesn't. One shared (baseUrl,
  /// guardianId, childId) triple, not a second `liveXxx` set per tile — see
  /// the Court export HubTile's onTap below.
  final String? baseUrl;
  final String? guardianId;
  final String childId;
  /// Injectable for tests only (e.g. package:http/testing.dart's MockClient) —
  /// matches child_home_live.dart's LiveChildHomeScreen.httpClient. Null in
  /// every real call site; AvailabilityScreen falls back to a real
  /// http.Client() itself when this is null.
  final http.Client? availabilityHttpClient;
  /// Injected the same way guardian_setup.dart's own [GuardianSetupScreen.
  /// registerPasskey] is: null in this offline preview build (see main.dart's
  /// own header — no live networking belongs here), so opening the family
  /// agreement screen shows a REAL, honest "can't load" state rather than
  /// faking one. See [_noLiveBackendWired].
  final Future<Map<String, dynamic>> Function(String childId)? fetchAgreementOrder;

  /// Best-known currently-active theme, so the picker's own preview and
  /// initial selection start from reality rather than always reopening at
  /// [defaultAppTheme] — see theme_picker_screen.dart's own [initial] field.
  /// Defaults to [defaultAppTheme] for the same reason [childName]/[childAge]
  /// default rather than requiring every existing (mostly offline-demo)
  /// call site to supply one.
  final AppTheme currentTheme;

  /// Fires when a live Apply succeeds — this hub has no `ThemeController` of
  /// its own (nothing upstream of it, in ANY current call site, holds one
  /// yet; see main_live.dart's own `_OliveLiveState` for the one that
  /// exists today and the gap in reaching it from here), so this is left
  /// optional and additive, exactly like [fetchAgreementOrder] above.
  final void Function(AppTheme)? onThemeApplied;

  /// Fires once [_startRealCall] below has a real, successfully-started
  /// call — the decoded POST calls response verbatim (token/wsURL/
  /// identity/rang). Every real call site leaves this null; it exists
  /// purely as an observation seam for a dev-only test entry point that
  /// needs to know a real call just started without this hub knowing or
  /// caring why (same additive-optional-callback shape as
  /// [fetchAgreementOrder]/[onThemeApplied] above — this hub's own real
  /// behavior is identical whether or not anything is listening).
  final void Function(Map<String, dynamic> started)? onCallStarted;

  /// The Deletion tile used to be the one sibling in this file's "Archive"
  /// section never given the live identity Court export/Availability/the
  /// real-call tiles above all already get — a bare `const DeletionScreen()`
  /// that silently fell back to demo defaults even inside a real live
  /// session, on the single screen whose action is irreversible. Same
  /// devLoginFor-per-call posture as `_startRealCall` above: a fresh token
  /// minted right before navigating, not one cached on this stateless
  /// widget that might have outlived its own session.
  Future<void> _openDeletion(BuildContext context) async {
    final url = baseUrl, gid = guardianId;
    if (url == null || gid == null) {
      _open(context, const DeletionScreen());
      return;
    }
    try {
      final api = await apiFor(url, userId: gid, client: availabilityHttpClient);
      if (availabilityHttpClient == null) api.close();
      if (context.mounted) {
        _open(context, DeletionScreen(
          childName: childName, baseUrl: url, sessionToken: api.sessionToken,
          childId: childId, guardianUserId: gid));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not reach the server. ${userMessageFor(e)}'), duration: const Duration(seconds: 3)));
      }
    }
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Real call-start — POST OliveApi.calls (server/routes.mjs's real
  /// handler), then opens the real [CallScreen] already joined to the room
  /// that call just minted (`knownToken`/`knownWsURL`, so this device never
  /// falls back to [CallScreen]'s own dev-room-server fetch). Same
  /// devLoginFor-per-call posture as [_liveSetGuardianPin] above, for the
  /// same reason: nothing here should trust a token that might have
  /// outlived this (stateless) widget's own lifecycle.
  Future<void> _startRealCall(BuildContext context) async {
    final url = baseUrl, gid = guardianId;
    if (url == null || gid == null) return; // onTap's own gate already prevents this; defensive only.
    try {
      final api = await apiFor(url, userId: gid, client: availabilityHttpClient);
      final Map<String, dynamic> started;
      try {
        started = await api.startCall(childId);
      } finally {
        if (availabilityHttpClient == null) api.close();
      }
      onCallStarted?.call(started);
      final sessionId = started['sessionId'] as String?;
      if (context.mounted) {
        _open(context, CallScreen(who: 'dad', displayName: 'Dad',
          knownToken: started['token'] as String?, knownWsURL: started['wsURL'] as String?,
          onCallEnd: sessionId == null ? null : () => _endRealCall(url, gid, childId, sessionId)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not start the call: ${e is ApiException ? e.error : userMessageFor(e)}'), duration: const Duration(seconds: 3)));
      }
    }
  }

  /// [CallScreen.onCallEnd]'s real implementation — POST OliveApi.endCall,
  /// record-keeping only (2026-08-23). A fresh devLoginFor() rather than
  /// reusing whatever token [_startRealCall] minted: the same "nothing here
  /// should trust a token that might have outlived this widget's own
  /// lifecycle" reasoning that method's own doc comment already states
  /// applies even more by the time a call has actually ended. Deliberately
  /// swallows its own failure — this is metadata bookkeeping, not something
  /// a guardian should ever see an error dialog for on top of a call that
  /// already, correctly, just ended from her point of view.
  Future<void> _endRealCall(String baseUrl, String guardianId, String childId, String sessionId) async {
    try {
      final api = await apiFor(baseUrl, userId: guardianId, client: availabilityHttpClient);
      try {
        await api.endCall(childId, sessionId);
      } finally {
        if (availabilityHttpClient == null) api.close();
      }
    } catch (_) {
      // Best-effort — see this method's own doc comment.
    }
  }

  // ===========================================================================
  // DEV VERIFICATION ONLY -- §7.1, §8.1, §11. This whole preview build has no
  // real guardian session anywhere in its widget tree yet (main.dart's own
  // header: "no backend behind it yet"), so there is no [OliveApi] instance
  // in scope for the real "Guardian setup" tile above to hand
  // guardian_setup.dart's [registerPasskey] callback. That tile is left
  // exactly as it was -- an honest stub -- rather than silently wired to
  // something that only works with a local dev server running.
  //
  // This SEPARATE tile exists purely so the real end-to-end passkey ceremony
  // (webauthn_channel.dart -> WebAuthnBridge.kt -> Android Credential
  // Manager -> server/routes.mjs's real verify) can actually be exercised on
  // real hardware, the same honest-escape-hatch shape as server/index.mjs's
  // own DEV_LOGIN: it mints a session for the real seeded 'Dad' guardian
  // (server/seed-dev.mjs) against a local dev server, and does nothing at
  // all against anything else. Delete this tile, not the plumbing it calls,
  // once a real guardian sign-in phase puts an authenticated [OliveApi]
  // somewhere this screen can actually reach.
  static const _devServerBaseUrl =
      String.fromEnvironment('OLIVE_DEV_SERVER', defaultValue: 'http://127.0.0.1:8080');
  static const _devGuardianUserId = 'aaaaaaaa-0000-4000-8000-000000000002'; // 'Dad'

  Future<PasskeyOutcome> _devRegisterPasskey() async {
    // Mirrors buildRegisterPasskeyCallback's own "never throws" contract
    // (see its doc comment) -- GuardianSetupScreen._tap() awaits
    // [registerPasskey] with no try/catch of its own, so a dev server that
    // isn't running (connection refused) or isn't DEV_LOGIN-enabled (404)
    // must resolve to a real [PasskeyOutcome], never an unhandled exception.
    try {
      final sessionToken =
          await devLoginFor(_devServerBaseUrl, userId: _devGuardianUserId);
      final api = OliveApi(_devServerBaseUrl, sessionToken);
      try {
        return await buildRegisterPasskeyCallback(api: api, userName: 'Dad')();
      } finally {
        api.close();
      }
    } catch (_) {
      return PasskeyOutcome.declined;
    }
  }

  /// The expiry digest reader's loader: the real GET .../expiry-digests when this hub has a live
  /// session (baseUrl and guardianId, the same pair every live tile here uses), otherwise null so the
  /// screen says plainly it is a later thing. A fresh session per call, like the PIN callbacks above.
  ExpiryDigestLoader? _liveExpiryDigests() {
    final url = baseUrl, gid = guardianId;
    if (url == null || gid == null) return null;
    return () async {
      final api = await apiFor(url, userId: gid, client: availabilityHttpClient);
      try {
        return await api.fetchExpiryDigests(childId);
      } finally {
        if (availabilityHttpClient == null) api.close();
      }
    };
  }

  /// Opens the real AvailabilityScreen when this hub has actually been given
  /// a live session to hand it (see the field doc comment above); otherwise
  /// gives honest feedback rather than a silent no-op or a screen built on
  /// data it doesn't have. Deliberately NOT worded "not built yet" — the
  /// screen exists and is real; what's missing here is live session wiring
  /// from this specific demo entry point, same as LiveChildHomeScreen not
  /// being threaded into main.dart's own static demo navigation either.
  void _openAvailability(BuildContext context) {
    final url = baseUrl, gid = guardianId;
    if (url != null && gid != null) {
      _open(context, AvailabilityScreen(baseUrl: url, guardianId: gid, childId: childId,
        httpClient: availabilityHttpClient));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Availability needs a live session — not connected in this preview build."),
      duration: Duration(seconds: 3)));
  }

  /// Unlike [_openAvailability] above, this ALWAYS opens the real screen —
  /// browsing/previewing a theme has no side effect (theme_picker_screen
  /// .dart's own live-preview-before-Apply design), so there is nothing to
  /// gate behind a live session the way a screen that fetches real data on
  /// open (AvailabilityScreen) needs to be. Only Apply itself needs
  /// baseUrl/guardianId/childId, and ThemePickerScreen already gives its own
  /// honest "not connected" feedback there when they're null — passed
  /// through as-is rather than duplicating that gate here.
  void _openThemePicker(BuildContext context) {
    _open(context, ThemePickerScreen(
      initial: currentTheme,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
      onApplied: onThemeApplied,
    ));
  }

  /// The on-device care records (medicines, expenses, handover log), or null in the preview build and in a
  /// live build. Only the offline guardian shell (a local scope above this hub, no session) gets them; the
  /// preview keeps its demo screens and a live session keeps the server-backed ones.
  CareService? _localCare(BuildContext context) =>
      (baseUrl == null && GuardianLocalScope.maybeOf(context) != null) ? CareService.forChild(childId) : null;

  FamilyPrincipal get _careMe => FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian');

  String? _careByName(BuildContext context) => GuardianLocalScope.maybeOf(context)?.family?.guardianName;

  /// The one care hub (the prototype's g-care): live subtitles, and the screens that live in other files.
  void _openCareHub(BuildContext context, CareService svc) {
    final EmergencyCardService card = EmergencyCardService.forChild(childId);
    _open(context, CareHubScreen(
      service: svc, principal: _careMe, childName: childName, byName: _careByName(context),
      emergencyVersion: () async => (await card.read(_careMe)).version,
      links: CareHubLinks(
        emergencyCard: (_) => EmergencyCardScreen(childName: childName, baseUrl: baseUrl, guardianId: guardianId,
            childId: childId, httpClient: availabilityHttpClient, localService: card, principal: _careMe),
        hospital: (_) => HospitalModeScreen(childName: childName, emergency: card, principal: _careMe,
            medicines: svc, openEmergencyCard: _openEmergencyCard),
        exchange: (_) => ExchangeScreen(childName: childName, baseUrl: baseUrl, guardianId: guardianId,
            childId: childId, httpClient: availabilityHttpClient),
        binder: (_) => CareBinderScreen(childName: childName),
        appointments: (_) => AppointmentPrepScreen(childName: childName),
        schedule: (_) => FamilyHomesScreen(ctx: _familyCtx()),
      ),
    ));
  }

  /// Unlike [_openAvailability] above, this ALWAYS opens the real screen —
  /// HandoverNotesScreen has a genuine, intentional offline demo mode of its
  /// own (four seeded fixture entries, real append-only invariant enforced
  /// purely client-side), not a "not connected" stub standing in for one —
  /// same reasoning [_openThemePicker] already gives for its own unconditional
  /// open. When baseUrl/guardianId ARE supplied, the screen fetches and posts
  /// against the real message_log-backed routes instead (see that file's own
  /// LIVE WIRING header); when they aren't, this is exactly the demo build
  /// this hub already was before this pass.
  void _openHandoverNotes(BuildContext context) {
    final CareService? svc = _localCare(context);
    if (svc != null) {
      _open(context, LocalHandoverScreen(service: svc, principal: _careMe, childName: childName, byName: _careByName(context)));
      return;
    }
    _open(context, HandoverNotesScreen(
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
    ));
  }

  /// Same unconditional-open reasoning as [_openHandoverNotes] — P6's own
  /// second lock (ExpensesScreen's own `viewerRole` gate, never even
  /// constructed for a non-guardian) plus this hub's own real fact (every
  /// caller of `GuardianMoreScreen` is, by construction, a guardian shell)
  /// mean there is no non-guardian path to worry about here; `viewerRole`
  /// defaults to `ViewerRole.guardian` and is never overridden by this tile.
  void _openExpenses(BuildContext context) {
    final CareService? svc = _localCare(context);
    if (svc != null) {
      _open(context, LocalExpensesScreen(service: svc, principal: _careMe, childName: childName, byName: _careByName(context)));
      return;
    }
    _open(context, ExpensesScreen(
      childName: childName,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
    ));
  }

  /// Same unconditional-open reasoning as [_openExpenses]/[_openHandoverNotes]
  /// — meds_care.dart has its own real, seeded-in-the-demo-fixture offline
  /// mode, not an honest-stub snackbar standing in for one.
  void _openMedsCare(BuildContext context) {
    final CareService? svc = _localCare(context);
    if (svc != null) {
      _open(context, LocalMedsScreen(service: svc, principal: _careMe, childName: childName, byName: _careByName(context)));
      return;
    }
    _open(context, MedsCareScreen(
      childName: childName,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
    ));
  }

  void _openEmergencyCard(BuildContext context) {
    _open(context, EmergencyCardScreen(
      childName: childName,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
      localService: EmergencyCardService.forChild(childId),
      principal: FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian'),
    ));
  }

  /// Same unconditional-open reasoning as [_openExpenses]/[_openMedsCare] —
  /// exchange_screen.dart's own demo (a seeded bag manifest, `_demoOrder`)
  /// is a genuine offline mode already, not a stub. Only the bag manifest/
  /// running-late/arrival sections go live when baseUrl/guardianId/childId
  /// are supplied — that file's own header discloses why Handoff/Coming-up
  /// stay on demo data either way.
  void _openExchange(BuildContext context) {
    _open(context, ExchangeScreen(
      childName: childName,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient,
    ));
  }

  /// Sign-out, for real (audit G-14): (1) stop this device receiving push
  /// (PushChannel.unregister(), best effort), (2) revoke THIS device on the
  /// server, clear the stored identity from secure storage and hand control
  /// back to the shell, which returns to pairing (AuthSession.signOut ->
  /// onSignedOut), and (3) leave the guardian shell — popUntil(isFirst) rather
  /// than a hardcoded target, since which screen is first differs by entry
  /// point (main.dart's EntryGate in the offline demo build, where there is no
  /// AuthSession and this is just the pop it always was).
  ///
  /// Step 1 is best-effort — same posture [_endRealCall] already holds
  /// itself to: a network hiccup unregistering push must never get in the
  /// way of actually leaving the screen, and there is nothing further a
  /// guardian could do about a background bookkeeping call failing anyway.
  Future<void> _signOut(BuildContext context) async {
    final url = baseUrl, gid = guardianId;
    if (url != null && gid != null) {
      try {
        final api = await apiFor(url, userId: gid, client: availabilityHttpClient);
        try {
          await PushChannel(api).unregister();
        } finally {
          if (availabilityHttpClient == null) api.close();
        }
      } catch (_) {
        // Best-effort — see this method's own doc comment.
      }
    }
    // Audit G-14 — sign-out used to clear nothing: the paired identity stayed in
    // secure storage and the device stayed authorized. Now the installed
    // AuthSession revokes this device server-side (best effort — offline must
    // still sign out), clears the stored identity, and fires its onSignedOut
    // hook, which the live shell uses to return to pairing. With no session
    // installed (the offline demo build, a dev-login run) there is nothing
    // stored to clear and this stays the pop it always was.
    await AuthSession.current?.signOut();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }


  void _needsLive(BuildContext context, String what) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$what needs a live session — no backend in this preview build.'),
        duration: const Duration(seconds: 3)));

  /// The PIN check behind "Clear data on this device". With a session it is the server's
  /// (unchanged). With NO session and a local PIN on this device (the offline family),
  /// it is the local PIN. With neither it is null, which the screen treats as fail closed.
  Future<bool> Function(String pin)? _wipeVerifier(BuildContext context) {
    final server = _liveVerifyWipePin(
      baseUrl: baseUrl, guardianId: guardianId, httpClient: availabilityHttpClient);
    if (server != null) return server;
    return GuardianLocalScope.maybeOf(context)?.services.pin.verifyBool;
  }

  /// Opens the settings hub. If this device has a LOCAL PIN, the hub is behind it (the
  /// offline family's guard on its own settings); with none, it opens as it always did.
  Future<void> _openSettingsHubGated(BuildContext context) async {
    final local = GuardianLocalScope.maybeOf(context);
    if (local != null && await local.services.pin.isSet()) {
      if (!context.mounted) return;
      final ok = await askLocalPin(context, local.services.pin,
        title: 'Enter your PIN', why: 'Settings are for grown-ups.');
      if (!ok || !context.mounted) return;
    }
    if (context.mounted) _openSettingsHub(context);
  }

  /// The family builder's context (who edits, as whom, for a child of what age).
  FamilyContext _familyCtx() => FamilyContext(
    service: familyService ?? localFamilyService,
    principal: FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian'),
    childName: childName, yearsOld: childAge);

  /// The Settings hub: every row opens the real screen that already exists for
  /// it (or one of the small screens this wave added: "Ivy calls you", Adults and
  /// helpers, the age planner, Change PIN). Nothing here is a new online feature.
  ///
  /// GROUPS AND ORDER follow the prototype's hub (docs/superpowers/mockups/live,
  /// mod-shell.js and mod-guardian.js `sr(...)`; test/parity/vectors/
  /// settings_hub_prototype.json holds that list and guardian_hub_parity_test.dart
  /// holds this one to it): Her, Family, Safety, Learn, Account. Rows the prototype
  /// does not have (Growing, Care, Routine and rhythm, Her voice, Village, Family
  /// compass, Connect this device, Deletion) are Flutter's own and sit after the
  /// prototype's rows in their group. Rows that need the network show an honest
  /// "needs a live session" and open nothing fake.
  void _openSettingsHub(BuildContext context) {
    final live = baseUrl != null && guardianId != null;
    final local = GuardianLocalScope.maybeOf(context);
    final lockedAge = local?.family?.age;
    final FamilyPrincipal me = FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian');
    _open(context, GuardianSettingsHubScreen(childName: childName, groups: [
      SettingsGroup('Her', [
        SettingsRow(id: 'names', icon: Icons.favorite_border, title: '$childName calls you',
          subtitle: 'Her word for each of you. Only she can change it',
          onTap: () => _open(context, GuardianNamesScreen(childName: childName, family: local?.family))),
        SettingsRow(id: 'colour', icon: Icons.palette_outlined, title: 'Colour and art',
          subtitle: 'Colour of the day, art style, coding activities',
          onTap: () => _open(context, HerColourGuardianScreen(childName: childName, childAge: childAge))),
        SettingsRow(id: 'look', icon: Icons.format_paint_outlined, title: 'How her app looks',
          subtitle: 'A palette, light or dark', onTap: () => _openThemePicker(context)),
        SettingsRow(id: 'age', icon: Icons.cake_outlined, title: 'Age band',
          subtitle: lockedAge != null
            ? '$childName is $lockedAge. Locked: your PIN changes it'
            : '$childName is $childAge',
          onTap: () => _open(context, AgeBandsScreen(ctx: _familyCtx(),
            onChangeAge: local?.family != null ? () => changeLockedAgeFlow(context, local!) : null))),
        SettingsRow(id: 'access', icon: Icons.accessibility_new_outlined, title: 'Accessibility for her device',
          subtitle: 'Text size, read aloud, motion, spacing, bigger targets, captions',
          onTap: () => _open(context, AccessScreen(childName: childName, childAge: childAge))),
        SettingsRow(id: 'window', icon: Icons.bedtime_outlined, title: 'Play window and daily time',
          subtitle: 'When games are open, the wind-down and the daily total',
          onTap: () => _open(context, PlayWindowScreen(childName: childName))),
        SettingsRow(id: 'suites', icon: Icons.view_agenda_outlined, title: 'Her suites',
          subtitle: 'Rhythm, Voice, Growing, Care, Village, Compass: what is on her shelf. On this device only',
          onTap: () => _openHerSuites(context)),
        SettingsRow(id: 'growing', icon: Icons.eco_outlined, title: 'Growing',
          subtitle: 'Time capsule, first times, growing marks. Kept on this device',
          onTap: () => _open(context, GrowingCareHubScreen(care: false, childName: childName,
            guardianId: guardianId ?? 'local-guardian'))),
        SettingsRow(id: 'rhythm', icon: Icons.checklist_outlined, title: 'Routine and rhythm',
          subtitle: 'Pictures for bedtime, first-then, the bag, a new place. On this device only',
          onTap: () => _open(context, RhythmGuardianHubScreen(childName: childName,
            service: RhythmVoiceService.forChild(childId), principal: me, yearsOld: childAge))),
        SettingsRow(id: 'voice', icon: Icons.record_voice_over_outlined, title: 'Her voice',
          subtitle: 'Her helpers and symbols; worries only if she shows you. On this device only',
          onTap: () => _open(context, VoiceGuardianHubScreen(childName: childName,
            service: RhythmVoiceService.forChild(childId), principal: me, yearsOld: childAge))),
        SettingsRow(id: 'village', icon: Icons.diversity_3_outlined, title: 'Village',
          subtitle: 'Her people in pictures, a story you release, sitter pass, school summary. On this device only',
          onTap: () => _openVillage(context)),
        SettingsRow(id: 'compass', icon: Icons.explore_outlined, title: 'Family compass',
          subtitle: 'Two gentle questions, suggestions, the suites shelf, accessibility profiles. On this device only',
          onTap: () {
            _open(context, CompassHubScreen(childName: childName, principal: me,
              service: CompassService.local(LocalServices.current, childId: childId, ports: suitePortsFor(
                rhythmVoice: RhythmVoiceService.forChild(childId), village: VillageService.forChild(childId),
                growingCare: GrowingCareStores.forChild(childId: childId), principal: me)),
              hints: () => builderHintsFor(me, childAge)));
          }),
      ]),
      SettingsGroup('Family', [
        SettingsRow(id: 'devices', icon: Icons.devices_other_outlined, title: 'Paired devices',
          subtitle: live ? 'See and revoke paired devices' : 'Needs a live session',
          onTap: () => live
            ? _open(context, PairedDevicesListScreen(baseUrl: baseUrl!, guardianId: guardianId!,
                childId: childId, httpClient: availabilityHttpClient))
            : _needsLive(context, 'Paired devices')),
        SettingsRow(id: 'addtablet', icon: Icons.qr_code_outlined, title: 'Add $childName’s tablet',
          subtitle: live ? 'Make a 6-digit code' : 'Needs a live session',
          onTap: () => live
            ? _open(context, AddDeviceScreen(baseUrl: baseUrl!, guardianId: guardianId!,
                children: [ChildOption(id: childId, name: childName)], httpClient: availabilityHttpClient))
            : _needsLive(context, 'Making a code')),
        SettingsRow(id: 'family', icon: Icons.family_restroom_outlined, title: 'Family structure',
          subtitle: 'Who is in $childName’s life, her homes and her rhythm',
          onTap: () => _open(context, FamilyStructureScreen(ctx: _familyCtx()))),
        SettingsRow(id: 'history', icon: Icons.history, title: 'Family history',
          subtitle: 'Every change, who made it, and when $childName was told',
          onTap: () => _open(context, FamilyHistoryScreen(ctx: _familyCtx()))),
        SettingsRow(id: 'weekly', icon: Icons.calendar_month_outlined, title: 'Weekly rhythm',
          subtitle: 'Where $childName sleeps, week by week',
          onTap: () => _open(context, FamilyHomesScreen(ctx: _familyCtx()))),
        // The invitee-side preview is reached from here, not as a settings row of its
        // own: Adults and helpers is the prototype's row, and it carries the preview.
        SettingsRow(id: 'adults', icon: Icons.person_add_alt_outlined, title: 'Adults and helpers',
          subtitle: 'Sitter pass, grandparent page, who else can be invited',
          onTap: () => _openAdultsAndHelpers(context)),
        SettingsRow(id: 'care', icon: Icons.health_and_safety_outlined, title: 'Care',
          subtitle: 'Care binder, hospital mode, picture stories, appointment prep. Kept on this device',
          onTap: () => _open(context, GrowingCareHubScreen(care: true, childName: childName,
            guardianId: guardianId ?? 'local-guardian', emergency: EmergencyCardService.forChild(childId),
            medicines: _localCare(context), openEmergencyCard: _openEmergencyCard))),
      ]),
      SettingsGroup('Safety', [
        SettingsRow(id: 'pin', icon: Icons.key_outlined, title: 'Change PIN',
          subtitle: 'Needs the current PIN. Five wrong tries pause it for 15 minutes',
          onTap: () => _openChangePin(context)),
        if (local?.services.recovery != null)
          SettingsRow(id: 'phones', icon: Icons.phonelink_lock_outlined, title: "Other grown-ups' phones",
            subtitle: 'Link a second phone so it can reset a forgotten PIN. Works with no internet',
            onTap: () => _open(context, GuardianPhonesScreen(pin: local!.services.pin,
              recovery: local.services.recovery!, myLabel: 'A grown-up'))),
        SettingsRow(id: 'controls', icon: Icons.shield_outlined, title: 'Parental controls',
          subtitle: live ? 'Hide or pace anything $childName sees. Messages are always on' : 'Needs a live session',
          onTap: () => live
            ? _open(context, ParentalControlsScreen(baseUrl: baseUrl!, guardianId: guardianId!,
                childId: childId, childName: childName, httpClient: availabilityHttpClient))
            : _needsLive(context, 'Parental controls')),
        SettingsRow(id: 'applock', icon: Icons.lock_clock_outlined, title: 'App lock and privacy',
          subtitle: 'Lock on leaving, hide in recent apps, quick hide',
          onTap: () => _openAppLock(context)),
        SettingsRow(id: 'devicedata', icon: Icons.phonelink_erase_outlined, title: 'Data on this phone',
          subtitle: 'What lives here, and clear it',
          onTap: () => _open(context, ClearLocalDataScreen(
            verifyPin: _wipeVerifier(context)))),
      ]),
      SettingsGroup('Learn', [
        SettingsRow(id: 'learn', icon: Icons.school_outlined, title: 'Parent Learn',
          subtitle: 'Private to you',
          onTap: () => _open(context, LearnHomeScreen(
            principal: LearnPrincipal('guardian', guardianId ?? 'local-guardian'),
            store: learnStore ?? LocalStoreLearnStore.forGuardian(guardianId), childAge: childAge))),
        SettingsRow(id: 'learnchoices', icon: Icons.tune_outlined, title: 'Your Learn choices',
          subtitle: 'Every extra is optional',
          onTap: () => _open(context, LearnSettingsScreen(
            principal: LearnPrincipal('guardian', guardianId ?? 'local-guardian'),
            store: learnStore ?? LocalStoreLearnStore.forGuardian(guardianId)))),
      ]),
      SettingsGroup('Account', [
        if (local?.onConnect != null)
          SettingsRow(id: 'connect', icon: Icons.link_rounded, title: 'Connect this device',
            subtitle: 'Optional. Share your family with your other devices',
            onTap: () => local!.onConnect!(context)),
        SettingsRow(id: 'deletion', icon: Icons.delete_outline, title: 'Deletion',
          subtitle: 'What deletion means here, stated first', onTap: () => _openDeletion(context)),
        SettingsRow(id: 'signout', icon: Icons.logout, title: 'Sign out',
          subtitle: 'Stops notifications on this device', onTap: () => _signOut(context)),
      ]),
    ]));
  }

  /// g-suites: the six suites on one page (switches are the suites' own).
  void _openHerSuites(BuildContext context) {
    final FamilyPrincipal me = FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian');
    final CompassService compass = CompassService.local(LocalServices.current, childId: childId, ports: suitePortsFor(
        rhythmVoice: RhythmVoiceService.forChild(childId), village: VillageService.forChild(childId),
        growingCare: GrowingCareStores.forChild(childId: childId), principal: me));
    _open(context, HerSuitesScreen(childName: childName, service: compass, principal: me, open: (String key) {
      switch (key) {
        case 'rhythm':
          _open(context, RhythmGuardianHubScreen(childName: childName,
            service: RhythmVoiceService.forChild(childId), principal: me, yearsOld: childAge));
        case 'voice':
          _open(context, VoiceGuardianHubScreen(childName: childName,
            service: RhythmVoiceService.forChild(childId), principal: me, yearsOld: childAge));
        case 'growing':
          _open(context, GrowingCareHubScreen(care: false, childName: childName, guardianId: guardianId ?? 'local-guardian'));
        case 'care':
          _open(context, GrowingCareHubScreen(care: true, childName: childName,
            guardianId: guardianId ?? 'local-guardian', emergency: EmergencyCardService.forChild(childId),
            medicines: _localCare(context), openEmergencyCard: _openEmergencyCard));
        case 'village':
          _openVillage(context);
        case 'compass':
          _open(context, CompassHubScreen(childName: childName, principal: me, service: compass,
            hints: () => builderHintsFor(me, childAge)));
      }
    }));
  }

  void _openVillage(BuildContext context) {
    final FamilyPrincipal me = FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian');
    _open(context, VillageGuardianHubScreen(childName: childName,
      service: VillageService.forChild(childId), principal: me, yearsOld: childAge,
      routineLines: () async {
        final RhythmDoc d = await RhythmVoiceService.forChild(childId).loadRhythm(me);
        return <String>[for (final RoutineStep st in d.routine?.steps ?? const <RoutineStep>[]) st.label];
      }));
  }

  /// Adults and helpers: the grown-ups of this family and what she calls each, a way
  /// into the family builder, the Village helpers, and the invitation PREVIEW.
  void _openAdultsAndHelpers(BuildContext context) {
    final local = GuardianLocalScope.maybeOf(context);
    final f = local?.family;
    _open(context, AdultsHelpersScreen(
      childName: childName,
      grownupLines: f == null ? const <String>[] : <String>[
        for (final g in f.grownups) '${f.guardianName} (${g.guardianLabel})',
      ],
      onChangePeople: () => _open(context, FamilyPeopleScreen(ctx: _familyCtx())),
      onHelpers: () => _openVillage(context),
      onInvitePreview: () => _openInvitationPreview(context),
    ));
  }

  /// The invitation PREVIEW: what another adult would be asked. Inviting needs the
  /// network, which is not built, so it says 'Nothing is sent' and sends nothing.
  void _openInvitationPreview(BuildContext context) {
    final f = GuardianLocalScope.maybeOf(context)?.family;
    _open(context, InvitationScreen(
      preview: true,
      childName: childName, inviterLabel: f?.guardianLabel ?? 'Your co-parent', yourLabel: 'Parent',
      onAccept: () => Navigator.of(context).pop(), onDecline: () => Navigator.of(context).pop()));
  }

  /// Change PIN: with a PIN on this device, the local change flow (current, new,
  /// confirm; easy guesses refused); otherwise the account PIN form as before.
  /// The adult-safety screen. Needs this device's local scope (the PIN it asks for lives there);
  /// without one (the preview build) it says so rather than showing a lock that cannot lock.
  Future<void> _openAppLock(BuildContext context) async {
    final local = GuardianLocalScope.maybeOf(context);
    if (local == null) {
      _needsLive(context, 'The app lock');
      return;
    }
    final bool set = await local.services.pin.isSet();
    if (!context.mounted) return;
    _open(context, AppLockSettingsScreen(controller: local.services.appLock, pinIsSet: set));
  }

  Future<void> _openChangePin(BuildContext context) async {
    final local = GuardianLocalScope.maybeOf(context);
    if (local != null && await local.services.pin.isSet()) {
      if (context.mounted) _open(context, LocalPinChangeScreen(service: local.services.pin));
      return;
    }
    if (!context.mounted) return;
    _open(context, GuardianSetupScreen(
      setGuardianPin: _liveSetGuardianPin(baseUrl: baseUrl, guardianId: guardianId, httpClient: availabilityHttpClient),
      checkExistingPin: _liveCheckExistingPin(baseUrl: baseUrl, guardianId: guardianId, httpClient: availabilityHttpClient)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HubSection(title: 'Archive', children: [
          HubTile(icon: Icons.hourglass_bottom, title: 'Expiry digest',
            subtitle: 'Preservation is the rule; this is just the 14-day reminder',
            onTap: () => _open(context, ExpiryDigestScreen(load: _liveExpiryDigests()))),
          HubTile(icon: Icons.gavel_outlined, title: 'Court export',
            subtitle: 'Chunked under the transfer ceiling',
            onTap: () => _open(context,
              (baseUrl != null && guardianId != null)
                ? LiveCourtExportScreen(
                    baseUrl: baseUrl!, guardianId: guardianId!, childId: childId)
                : const CourtExportScreen())),
          if (_showDemo) ...[
            HubTile(icon: Icons.auto_stories_outlined, title: 'Year book',
              subtitle: "A year of $childName, preserved",
              onTap: () => _open(context, const YearBookScreen())),
            HubTile(icon: Icons.photo_library_outlined, title: 'Gallery',
              subtitle: 'Year-grouped works, paginated by era',
              onTap: () => _open(context, const GalleryScreen())),
            HubTile(icon: Icons.menu_book, title: 'The book',
              subtitle: 'The stories you read together, bound',
              onTap: () => _open(context, TheBookScreen.demo(childName: childName))),
          ],
        ]),
        HubSection(title: 'Learn', children: [
          HubTile(key: const Key('moreLearn'), icon: Icons.school_outlined, title: 'Learn',
            subtitle: 'Short, sourced parenting guides. Private to you.',
            onTap: () => _open(context, LearnHomeScreen(
              principal: LearnPrincipal('guardian', guardianId ?? 'local-guardian'),
              // Parent Learn is kept on this device, sealed (LocalStore's
              // encrypted `learn` area), unless a server-backed store is passed.
              store: learnStore ?? LocalStoreLearnStore.forGuardian(guardianId),
              childAge: childAge))),
        ]),
        HubSection(title: 'Show me', children: [
          HubTile(icon: Icons.photo_camera_back_outlined, title: 'Show me — your side',
            subtitle: 'What she has shown you, and what is still waiting',
            onTap: () => _open(context, ShowGuardianScreen(childName: childName, childAge: childAge))),
        ]),
        HubSection(title: 'Play together', children: [
          // The SAME real screen her own "Play together" tile opens — see
          // game_picker.dart's own [GamePickerScreen.extraSections] and
          // game_navigation.dart's own header for why this is one shared
          // catalogue and one shared onPlay wiring, reachable from both
          // sides, rather than a second hand-copied list that could drift.
          // Real today for genuine co-located, same-room play (a weekend
          // visit, a school pickup) — these are local pass-and-play boards,
          // so opening this from a guardian's own device works exactly the
          // way opening it from hers does. What this tile does NOT yet do
          // is start a session on HER device remotely from here — that's
          // the live in-call games work (live_games.dart), not this one.
          HubTile(icon: Icons.extension_outlined, title: 'Play together',
            subtitle: 'Everything she can play, the same list she sees',
            // Intuitivism pass, sub-project 3a (docs/superpowers/specs/
            // 2026-09-12-intuitivism-gamepicker-recommended-design.md) —
            // this is this spec's ONLY guardian-driven favoriting surface:
            // wired in via LiveGamePickerScreen when a real session exists
            // (baseUrl/guardianId, the same trio _openAvailability/
            // _openThemePicker above already gate on), so the star toggle
            // actually persists rather than a UI that pretends to. Without
            // one, this renders exactly as it always has — the identical
            // "always open the real screen" posture _openThemePicker's own
            // comment already documents for a screen with no fetch-on-open
            // side effect of its own.
            onTap: () => _open(context, () {
              final gameSections = [
                MoreGamesSections(childName: childName, childAge: childAge,
                  guardianSide: true, localRole: 'dad'),
                JokebookSection(childName: childName),
              ];
              final onPlay = buildGameNavigator(childName);
              if (baseUrl != null && guardianId != null) {
                return LiveGamePickerScreen(
                  baseUrl: baseUrl!, childId: childId, guardianId: guardianId!,
                  childName: childName, httpClient: availabilityHttpClient,
                  onPlay: onPlay, extraSections: gameSections,
                );
              }
              return GamePickerScreen(
                childName: childName, onPlay: onPlay, extraSections: gameSections,
              );
            }())),
        ]),
        HubSection(title: 'Calls', children: [
          HubTile(icon: Icons.call_outlined, title: 'Call $childName',
            subtitle: baseUrl != null
              ? 'Real Jitsi room, real room-coordination server'
              // Deliberately NOT "not connected" (the substring
              // guardian_more_test.dart's Availability-tile test matches
              // on) — this subtitle renders unconditionally, unlike that
              // tile's tap-time snackbar, so reusing the same wording here
              // would make every future "not connected" assertion in this
              // file ambiguous between two ALWAYS-visible widgets, not one.
              : 'Needs a live session — no backend in this preview build',
            onTap: () => baseUrl != null && guardianId != null
              ? _startRealCall(context)
              : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Calling needs a live session — no backend in this preview build.'),
                  duration: Duration(seconds: 3)))),
          if (_showDemo)
            HubTile(icon: Icons.waving_hand_outlined, title: 'Closing ritual (demo)',
              subtitle: 'Calls end the same way every time',
              onTap: () => _open(context, ClosingRitualScreen(childName: childName, callerName: 'Dad'))),
          HubTile(icon: Icons.verified_user_outlined, title: 'Call security',
            subtitle: 'Opaque rooms, single-room tokens, verified on the wire',
            onTap: () => _open(context, const CallSecurityInfoScreen())),
          if (_showDemo) ...[
            HubTile(icon: Icons.signal_cellular_alt, title: 'Live call quality (demo)',
              subtitle: 'Quick to shed, six times slower to restore',
              onTap: () => _open(context, LiveDegradeScreen(childName: childName))),
            HubTile(icon: Icons.event_busy_outlined, title: 'Busy fork (demo)',
              subtitle: "He's busy: the ask forks to async, never silently drops",
              onTap: () => _open(context, BusyForkScreen(childName: childName))),
          ],
        ]),
        HubSection(title: 'Family setup', children: [
          // A PREVIEW until the network is built: it says 'Nothing is sent' and sends
          // nothing, with no hard-coded Dad/Mom (invitation_screen.dart, preview: true).
          HubTile(key: const Key('moreInvite'), icon: Icons.person_add_alt_outlined, title: 'Invite a co-parent (preview)',
            subtitle: 'See what another adult would be asked. Nothing is sent',
            onTap: () => _openInvitationPreview(context)),
          // Device pairing & provisioning (docs/superpowers/specs/2026-09-12
          // -device-pairing-provisioning-design.md) — PARALLEL entry point to
          // "Invite a co-parent" above: that one attaches a brand-new
          // identity; this one attaches an ALREADY-EXISTING identity to a
          // NEW DEVICE. Same live-session gate _openAvailability/
          // _openThemePicker already use — generating a real code needs a
          // real guardian session to re-verify the PIN against.
          HubTile(icon: Icons.qr_code_outlined, title: 'Add a device',
            subtitle: baseUrl != null
              ? 'A QR code and a 6-digit fallback, good for 10 minutes'
              : 'Needs a live session — no backend in this preview build',
            onTap: () => (baseUrl != null && guardianId != null)
              ? _open(context, AddDeviceScreen(
                  baseUrl: baseUrl!, guardianId: guardianId!,
                  // This hub only ever knows about ONE child at a time (the
                  // same single-child scope every other tile here already
                  // has — "Call $childName", the Court export tile, ...) —
                  // not a new limitation this screen invents.
                  children: [ChildOption(id: childId, name: childName)],
                  httpClient: availabilityHttpClient,
                ))
              : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Adding a device needs a live session — no backend in this preview build.'),
                  duration: Duration(seconds: 3)))),
          HubTile(icon: Icons.devices_other_outlined, title: 'Paired devices',
            subtitle: baseUrl != null
              ? 'See and revoke every device paired to this family'
              : 'Needs a live session — no backend in this preview build',
            onTap: () => (baseUrl != null && guardianId != null)
              ? _open(context, PairedDevicesListScreen(
                  baseUrl: baseUrl!, guardianId: guardianId!, childId: childId,
                  httpClient: availabilityHttpClient,
                ))
              : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Paired devices needs a live session — no backend in this preview build.'),
                  duration: Duration(seconds: 3)))),
          // Parental controls: visibility & pacing (docs/superpowers/specs/
          // 2026-09-13-parental-controls-pacing-design.md) — same live-
          // session gate every tile in this section already uses; the PIN
          // re-verification this screen itself does (POST /v1/me/verify-
          // controls-pin) is the real gate, not this snackbar fallback.
          HubTile(icon: Icons.shield_outlined, title: 'Parental controls',
            subtitle: baseUrl != null
              ? "Hide or pace anything $childName sees"
              : 'Needs a live session — no backend in this preview build',
            onTap: () => (baseUrl != null && guardianId != null)
              ? _open(context, ParentalControlsScreen(
                  baseUrl: baseUrl!, guardianId: guardianId!,
                  childId: childId, childName: childName,
                  httpClient: availabilityHttpClient,
                ))
              : ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Parental controls needs a live session — no backend in this preview build.'),
                  duration: Duration(seconds: 3)))),
          HubTile(icon: Icons.key_outlined, title: 'Guardian setup',
            subtitle: baseUrl != null
              ? 'Set your kiosk PIN — passkey sign-in is still an honest stub'
              : 'Passkey sign-in — an honest stub, not a faked grant',
            onTap: () => _open(context, GuardianSetupScreen(
              // Real navigation wiring — no longer a null-checked snackbar
              // fallback (see guardian_setup.dart's own _tapAgreement, which
              // still keeps that fallback for any OTHER caller that leaves
              // this null). fetchOrder itself is honest about whether a live
              // backend actually exists — see _noLiveBackendWired above.
              onOpenAgreement: () => _open(context, FamilyAgreementScreen(
                childId: childId,
                childName: childName,
                fetchOrder: fetchAgreementOrder ?? _noLiveBackendWired,
              )),
              // Real POST /v1/me/pin when this hub has a live session; null
              // (GuardianSetupScreen's own honest "no backend wired" state)
              // otherwise — see _liveSetGuardianPin's own doc comment.
              setGuardianPin: _liveSetGuardianPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
              // Real GET /v1/me's hasPin when this hub has a live session —
              // see _liveCheckExistingPin's own doc comment.
              checkExistingPin: _liveCheckExistingPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
              // Changing an EXISTING PIN needs the current one (audit G-13).
              changeGuardianPin: _liveChangeGuardianPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
            ))),
          HubTile(icon: Icons.fingerprint_outlined,
            title: 'Guardian setup — passkey (dev verification)',
            subtitle: 'Real ceremony, real backend, local dev server only',
            onTap: () => _open(context, GuardianSetupScreen(
              registerPasskey: _devRegisterPasskey,
              setGuardianPin: _liveSetGuardianPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
              checkExistingPin: _liveCheckExistingPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
              // Changing an EXISTING PIN needs the current one (audit G-13).
              changeGuardianPin: _liveChangeGuardianPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
            ))),
          HubTile(icon: Icons.push_pin_outlined, title: 'Kiosk lock advisory',
            subtitle: 'What this platform actually guarantees, honestly',
            onTap: () => _open(context, const LockAdvisoryScreen())),
          // Hard-coded colour picks and dates (invented, not hers): demo only.
          if (_showDemo)
            HubTile(icon: Icons.color_lens_outlined, title: "$childName's colour",
              subtitle: 'Her choice — you can see it, never change it',
              onTap: () => _open(context, ColourParentScreen(
                childName: childName,
                history: const <ColourChoice>[
                  ColourChoice(colourId: 'sea', chosenAt: '2026-06-02', via: 'first_run'),
                  ColourChoice(colourId: 'grape', chosenAt: '2026-07-21', via: 'daily'),
                ],
                today: '2026-08-04',
              ))),
          HubTile(icon: Icons.timeline_outlined, title: 'Growing-up ladder',
            subtitle: 'Irreversible by design — see why here',
            onTap: () => _open(context, MaturationLadderScreen(
              childName: childName, childAgeYears: childAge, viewer: LadderViewer.guardian))),
          HubTile(icon: Icons.family_restroom_outlined, title: 'Siblings',
            subtitle: 'A guardian of one is not a guardian of the other',
            onTap: () => _open(context, SiblingsScreen())),
          HubTile(icon: Icons.delete_outline, title: 'Deletion',
            subtitle: 'What deletion means here, stated before it happens',
            onTap: () => _openDeletion(context)),
          HubTile(icon: Icons.record_voice_over_outlined, title: 'Storyteller safety',
            subtitle: 'No synthetic parent voice, ever — what P1 forbids and why',
            onTap: () => _open(context, const StorytellerSafetyScreen())),
          HubTile(key: const Key('moreFamily'), icon: Icons.family_restroom_outlined, title: 'Family structure',
            subtitle: "Who is in $childName's life, her homes, and how her home grows",
            onTap: () => _open(context, FamilyStructureScreen(ctx: FamilyContext(
              service: familyService ?? localFamilyService,
              principal: FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian'),
              childName: childName, yearsOld: childAge)))),
        ]),
        HubSection(title: 'Connect a device', children: [
          HubTile(icon: Icons.lock_open_outlined, title: "Unlock a child's device with my phone",
            subtitle: 'Scan the picture on her device, type your PIN, show it the answer',
            onTap: () async {
              final local = GuardianLocalScope.maybeOf(context);
              if (local == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Unlocking needs a PIN on this device. Set one up first.'),
                  duration: Duration(seconds: 3)));
                return;
              }
              final services = LocalServices.current;
              final kids = LocalStorePairedKidsRepository(services.area('pairedkids', ownerId: kLocalGuardianScope));
              final key = await DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(services.area('devicekey')));
              if (!context.mounted) return;
              _open(context, UnlockChildScreen(
                pin: local.services.pin,
                responder: UnlockResponder(adultKey: key, kids: kids.load),
                childName: childName,
              ));
            }),
          HubTile(icon: Icons.tablet_android_outlined, title: 'Connected child devices',
            subtitle: 'Forget a tablet, or make it unlock only with your phone',
            onTap: () => _open(context, ConnectedDevicesScreen(
              kids: LocalStorePairedKidsRepository(
                LocalServices.current.area('pairedkids', ownerId: kLocalGuardianScope)),
              childName: childName))),
          // Connect a child's device on the SAME network, no account or connection needed: you type your PIN here,
          // pick your name on her device and type it there (a key exchange; the PIN is never sent), then say yes.
          // Spec 2026-11-08-adult-gate-and-simple-pairing-design.md.
          HubTile(icon: Icons.phonelink_lock_outlined, title: "Connect a child's device",
            subtitle: 'Open a short window here, then use "A grown-up does this" on her device',
            onTap: () {
              final local = GuardianLocalScope.maybeOf(context);
              if (local == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Connecting a device needs a PIN on this device. Set one up first.'),
                  duration: Duration(seconds: 3)));
                return;
              }
              final services = LocalServices.current;
              _open(context, ConnectChildScreen(
                pin: local.services.pin,
                deviceKeys: LocalStoreDeviceKeyRepository(services.area('devicekey')),
                kids: LocalStorePairedKidsRepository(services.area('pairedkids', ownerId: kLocalGuardianScope)),
                adultName: local.family?.guardianName ?? 'A grown-up',
                childName: childName,
              ));
            }),
        ]),
        HubSection(title: 'Coordination', children: [
          if (_localCare(context) != null)
            HubTile(key: const Key('moreCareHub'), icon: Icons.volunteer_activism_outlined, title: 'Care and coordination',
              subtitle: 'Medicines, expenses, handover notes and more. On this device',
              onTap: () => _openCareHub(context, _localCare(context)!)),
          HubTile(icon: Icons.event_available_outlined, title: 'Availability',
            subtitle: 'When he can actually be reached, honestly rendered',
            onTap: () => _openAvailability(context)),
          HubTile(icon: Icons.chat_outlined, title: 'Handover notes',
            subtitle: baseUrl != null
              ? 'Real, append-only — court-tier since the day it was written'
              : "Not the child's channel — it's the parents' (demo)",
            onTap: () => _openHandoverNotes(context)),
          HubTile(icon: Icons.receipt_long_outlined, title: 'Expenses',
            subtitle: baseUrl != null
              ? 'Real ledger — P6 enforced twice, in the route and in the RLS'
              : "Invisible to $childName at every depth (demo)",
            onTap: () => _openExpenses(context)),
          HubTile(icon: Icons.medication_outlined, title: 'Meds & care',
            subtitle: baseUrl != null
              ? 'Real dosing log — a real double-dose guard, enforced by Postgres'
              : "Between guardians only — $childName never sees this screen (demo)",
            onTap: () => _openMedsCare(context)),
          HubTile(icon: Icons.medical_information_outlined, title: 'Emergency card',
            subtitle: baseUrl != null
              ? 'Real, allergy-first — read once, in a hurry'
              : 'Read once, in a hurry (demo)',
            onTap: () => _openEmergencyCard(context)),
          HubTile(icon: Icons.luggage_outlined, title: 'Exchange',
            subtitle: baseUrl != null
              ? 'Real bag manifest, running-late log, arrival — never a place, P3'
              : 'An event, never a place — P3 (demo)',
            onTap: () => _openExchange(context)),
        ]),
        HubSection(title: 'Preferences', children: [
          HubTile(key: const Key('moreSettings'), icon: Icons.tune_outlined, title: 'Settings',
            subtitle: 'Her, Family, Safety, Learn, Account in one place',
            onTap: () => _openSettingsHubGated(context)),
          HubTile(icon: Icons.palette_outlined, title: 'Theme',
            subtitle: 'A real palette, guardian-only, synced across your devices',
            onTap: () => _openThemePicker(context)),
          HubTile(icon: Icons.logout, title: 'Sign out',
            subtitle: 'Stops notifications on this device and returns to the start',
            onTap: () => _signOut(context)),
        ]),
        // Offline-first foundation: see exactly what this phone keeps and clear
        // it (PIN-gated, fail closed). Always listed: it needs no session to
        // SHOW the list; only the wipe needs a checkable PIN. Its own section,
        // last, so no existing tile moves.
        HubSection(title: 'This device', children: [
          HubTile(key: const Key('moreDeviceData'), icon: Icons.phonelink_erase_outlined,
            title: 'Data on this device',
            subtitle: 'What this phone keeps, and clear it',
            onTap: () => _open(context, ClearLocalDataScreen(
              verifyPin: _wipeVerifier(context)))),
        ]),
        // Last, so it never moves the tiles above it. The design-parity component gallery: the owner's way to compare Flutter against the
        // prototype. Demo/debug builds only (the same gate as the invented-content tiles above).
        if (_showDemo)
          HubSection(title: 'Design (demo)', children: [
            HubTile(key: const Key('moreUiGallery'), icon: Icons.palette_outlined, title: 'UI gallery (demo)',
              subtitle: 'Every component, scene and icon, light and dark, text scale 1 and 2',
              onTap: () => _open(context, const OliveUiGalleryScreen())),
          ]),
      ]),
    )),
  );
}
