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
import 'year_book.dart';

void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class GuardianMoreScreen extends StatelessWidget {
  const GuardianMoreScreen({super.key, this.childName = 'Ivy', this.childAge = 9});
  final String childName;
  final int childAge;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

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
        HubSection(title: 'Not yet built', children: [
          HubTile(icon: Icons.event_available_outlined, title: 'Availability',
            subtitle: 'When he can actually be reached — no screen implements this yet',
            onTap: () => _notBuiltYet(context, 'Availability')),
        ]),
      ]),
    )),
  );
}
