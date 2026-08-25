// OLIVE BRANCH — guardian shell, "more" hub. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). Navigation-wiring-pass
// addition, not a MARKUP screen of its own.
//
// guardian_home.dart's own grid stays at the size a real dashboard can
// carry; this hub is where the wiring pass hangs the remaining
// guardian-facing screens (archive/export, live-call extras, showcase's
// guardian side, family setup) that don't have their own top-level tile, so
// "every new screen must be reachable" holds without crowding that home
// screen the way child_more.dart does for the child side.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'availability_screen.dart';
import 'busy_fork.dart';
import 'call_screen.dart';
import 'call_security_info.dart';
import 'closing_ritual.dart';
import 'colour_parent.dart';
import 'court_export.dart';
import 'degradation_banner.dart';
import 'deletion_screen.dart';
import 'expiry_digest.dart';
import 'family_agreement_screen.dart';
import 'gallery_screen.dart';
import 'guardian_setup.dart';
import 'hub_widgets.dart';
import 'invitation_screen.dart';
import 'lock_advisory_screen.dart';
import 'maturation_ladder.dart';
import 'palette_logic.dart';
import 'push_channel.dart';
import 'show_guardian.dart';
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
    final token = await devLoginFor(baseUrl, userId: guardianId, client: httpClient);
    final api = OliveApi(baseUrl, token, client: httpClient);
    try {
      await api.setGuardianPin(pin);
    } finally {
      if (httpClient == null) api.close();
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
  });
  final String childName;
  final int childAge;
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
  /// call — the decoded POST calls response verbatim (room/serverURL/
  /// identity/rang). Every real call site leaves this null; it exists
  /// purely as an observation seam for a dev-only test entry point that
  /// needs to know a real call just started without this hub knowing or
  /// caring why (same additive-optional-callback shape as
  /// [fetchAgreementOrder]/[onThemeApplied] above — this hub's own real
  /// behavior is identical whether or not anything is listening).
  final void Function(Map<String, dynamic> started)? onCallStarted;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Real call-start — POST OliveApi.calls (server/routes.mjs's real
  /// handler), then opens the real [CallScreen] already joined to the room
  /// that call just minted (`knownRoom`/`knownServerURL`, so this device
  /// never falls back to [CallScreen]'s own dev-room-server fetch). Same
  /// devLoginFor-per-call posture as [_liveSetGuardianPin] above, for the
  /// same reason: nothing here should trust a token that might have
  /// outlived this (stateless) widget's own lifecycle.
  Future<void> _startRealCall(BuildContext context) async {
    final url = baseUrl, gid = guardianId;
    if (url == null || gid == null) return; // onTap's own gate already prevents this; defensive only.
    try {
      final token = await devLoginFor(url, userId: gid, client: availabilityHttpClient);
      final api = OliveApi(url, token, client: availabilityHttpClient);
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
          knownRoom: started['room'] as String?, knownServerURL: started['serverURL'] as String?,
          onCallEnd: sessionId == null ? null : () => _endRealCall(url, gid, childId, sessionId)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not start the call: $e'), duration: const Duration(seconds: 3)));
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
      final token = await devLoginFor(baseUrl, userId: guardianId, client: availabilityHttpClient);
      final api = OliveApi(baseUrl, token, client: availabilityHttpClient);
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

  /// There is no persisted client-side session anywhere in this codebase to
  /// clear (every screen calls devLoginFor() fresh — see push_channel.dart's
  /// own "no sign-out/log-out flow anywhere in lib/" note, which this tile
  /// closes). So the real, honest actions a sign-out can take here are: (1)
  /// stop this device from receiving push (PushChannel.unregister(), real
  /// and already tested, with no caller anywhere until now), and (2) leave
  /// the guardian shell — popUntil(isFirst) rather than a hardcoded target,
  /// since which screen is actually first differs by entry point
  /// (main.dart's EntryGate in the offline demo build; GuardianMoreScreen
  /// itself in main_live_guardian.dart's live build, where this is already
  /// the root and popUntil is a harmless no-op).
  ///
  /// Step 1 is best-effort — same posture [_endRealCall] already holds
  /// itself to: a network hiccup unregistering push must never get in the
  /// way of actually leaving the screen, and there is nothing further a
  /// guardian could do about a background bookkeeping call failing anyway.
  Future<void> _signOut(BuildContext context) async {
    final url = baseUrl, gid = guardianId;
    if (url != null && gid != null) {
      try {
        final token = await devLoginFor(url, userId: gid, client: availabilityHttpClient);
        final api = OliveApi(url, token, client: availabilityHttpClient);
        try {
          await PushChannel(api).unregister();
        } finally {
          if (availabilityHttpClient == null) api.close();
        }
      } catch (_) {
        // Best-effort — see this method's own doc comment.
      }
    }
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
            onTap: () => _open(context, const ExpiryDigestScreen())),
          HubTile(icon: Icons.gavel_outlined, title: 'Court export',
            subtitle: 'Chunked under the transfer ceiling',
            onTap: () => _open(context,
              (baseUrl != null && guardianId != null)
                ? LiveCourtExportScreen(
                    baseUrl: baseUrl!, guardianId: guardianId!, childId: childId)
                : const CourtExportScreen())),
          HubTile(icon: Icons.auto_stories_outlined, title: 'Year book',
            subtitle: "A year of $childName, preserved",
            onTap: () => _open(context, const YearBookScreen())),
          HubTile(icon: Icons.photo_library_outlined, title: 'Gallery',
            subtitle: 'Year-grouped works, paginated by era',
            onTap: () => _open(context, const GalleryScreen())),
          HubTile(icon: Icons.menu_book, title: 'The book',
            subtitle: 'The stories you read together, bound',
            onTap: () => _open(context, TheBookScreen.demo(childName: childName))),
        ]),
        HubSection(title: 'Show me', children: [
          HubTile(icon: Icons.photo_camera_back_outlined, title: 'Show me — your side',
            subtitle: 'What she has shown you, and what is still waiting',
            onTap: () => _open(context, ShowGuardianScreen(childName: childName, childAge: childAge))),
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
          HubTile(icon: Icons.waving_hand_outlined, title: 'Closing ritual (demo)',
            subtitle: 'Calls end the same way every time',
            onTap: () => _open(context, ClosingRitualScreen(childName: childName, callerName: 'Dad'))),
          HubTile(icon: Icons.verified_user_outlined, title: 'Call security',
            subtitle: 'Opaque rooms, single-room tokens, verified on the wire',
            onTap: () => _open(context, const CallSecurityInfoScreen())),
          HubTile(icon: Icons.signal_cellular_alt, title: 'Live call quality (demo)',
            subtitle: 'Quick to shed, six times slower to restore',
            onTap: () => _open(context, LiveDegradeScreen(childName: childName))),
          HubTile(icon: Icons.event_busy_outlined, title: 'Busy fork (demo)',
            subtitle: "He's busy: the ask forks to async, never silently drops",
            onTap: () => _open(context, BusyForkScreen(childName: childName))),
        ]),
        HubSection(title: 'Family setup', children: [
          HubTile(icon: Icons.person_add_alt_outlined, title: 'Invite a co-parent',
            subtitle: 'The same view you already have — nothing hidden',
            onTap: () => _open(context, InvitationScreen(
              childName: childName, inviterLabel: 'Dad', yourLabel: 'Mom',
              onAccept: () => Navigator.of(context).pop(),
              onDecline: () => Navigator.of(context).pop(),
            ))),
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
            ))),
          HubTile(icon: Icons.fingerprint_outlined,
            title: 'Guardian setup — passkey (dev verification)',
            subtitle: 'Real ceremony, real backend, local dev server only',
            onTap: () => _open(context, GuardianSetupScreen(
              registerPasskey: _devRegisterPasskey,
              setGuardianPin: _liveSetGuardianPin(
                baseUrl: baseUrl, guardianId: guardianId,
                httpClient: availabilityHttpClient),
            ))),
          HubTile(icon: Icons.push_pin_outlined, title: 'Kiosk lock advisory',
            subtitle: 'What this platform actually guarantees, honestly',
            onTap: () => _open(context, const LockAdvisoryScreen())),
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
            onTap: () => _open(context, const DeletionScreen())),
          HubTile(icon: Icons.record_voice_over_outlined, title: 'Storyteller safety',
            subtitle: 'No synthetic parent voice, ever — what P1 forbids and why',
            onTap: () => _open(context, const StorytellerSafetyScreen())),
        ]),
        HubSection(title: 'Coordination', children: [
          HubTile(icon: Icons.event_available_outlined, title: 'Availability',
            subtitle: 'When he can actually be reached, honestly rendered',
            onTap: () => _openAvailability(context)),
        ]),
        HubSection(title: 'Preferences', children: [
          HubTile(icon: Icons.palette_outlined, title: 'Theme',
            subtitle: 'A real palette, guardian-only, synced across your devices',
            onTap: () => _openThemePicker(context)),
          HubTile(icon: Icons.logout, title: 'Sign out',
            subtitle: 'Stops notifications on this device and returns to the start',
            onTap: () => _signOut(context)),
        ]),
      ]),
    )),
  );
}
