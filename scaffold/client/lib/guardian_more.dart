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
import 'call_security_info.dart';
import 'closing_ritual.dart';
import 'colour_parent.dart';
import 'court_export.dart';
import 'degradation_banner.dart';
import 'deletion_screen.dart';
import 'expiry_digest.dart';
import 'gallery_screen.dart';
import 'guardian_setup.dart';
import 'hub_widgets.dart';
import 'invitation_screen.dart';
import 'lock_advisory_screen.dart';
import 'maturation_ladder.dart';
import 'palette_logic.dart';
import 'show_guardian.dart';
import 'siblings_screen.dart';
import 'storyteller_screen.dart' show StorytellerSafetyScreen;
import 'the_book.dart';
import 'webauthn_channel.dart';
import 'year_book.dart';

class GuardianMoreScreen extends StatelessWidget {
  const GuardianMoreScreen({
    super.key,
    this.childName = 'Ivy',
    this.childAge = 9,
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.availabilityHttpClient,
  });
  final String childName;
  final int childAge;

  /// Live-session wiring for AvailabilityScreen — all three optional and
  /// defaulted to null because nothing upstream of this hub (guardian_home.dart,
  /// main.dart's static demo data) carries a real base URL, guardian id, or
  /// child id yet; every other call site in this file is still the same
  /// pre-backend demo build LiveChildHomeScreen's own header describes for
  /// the child side. When all three ARE supplied, the Availability tile
  /// opens the real AvailabilityScreen; otherwise it gives the same honest
  /// not-connected feedback guardian_setup.dart's passkey button gives when
  /// its own real dependency isn't wired in yet — never a silent no-op, and
  /// never a screen pretending to have live data it doesn't.
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  /// Injectable for tests only (e.g. package:http/testing.dart's MockClient) —
  /// matches child_home_live.dart's LiveChildHomeScreen.httpClient. Null in
  /// every real call site; AvailabilityScreen falls back to a real
  /// http.Client() itself when this is null.
  final http.Client? availabilityHttpClient;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

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
    final url = baseUrl, gid = guardianId, cid = childId;
    if (url != null && gid != null && cid != null) {
      _open(context, AvailabilityScreen(baseUrl: url, guardianId: gid, childId: cid,
        httpClient: availabilityHttpClient));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Availability needs a live session — not connected in this preview build."),
      duration: Duration(seconds: 3)));
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
            onTap: () => _open(context, const CourtExportScreen())),
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
            subtitle: 'Passkey sign-in — an honest stub, not a faked grant',
            onTap: () => _open(context, const GuardianSetupScreen())),
          HubTile(icon: Icons.fingerprint_outlined,
            title: 'Guardian setup — passkey (dev verification)',
            subtitle: 'Real ceremony, real backend, local dev server only',
            onTap: () => _open(context,
              GuardianSetupScreen(registerPasskey: _devRegisterPasskey))),
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
      ]),
    )),
  );
}
