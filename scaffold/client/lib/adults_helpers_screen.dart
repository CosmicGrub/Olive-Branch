// OLIVE BRANCH — Adults and helpers (the prototype's g-adults). No longer
// UNVERIFIED — verified by CI (client/test/guardian_hub_parity_test.dart).
// MASTERFILE §8.5, §8.6.
//
// One place for the people around her: the grown-ups of this family and what she
// calls each, a way into "who is in her life" (the family builder), the helpers
// you can write for (a sitter pass, a grandparent page, a school summary: all
// written by you and shown on a screen, never sent or saved by anyone), and inviting
// another adult. Inviting needs the network, which is not built, so that row opens
// a PREVIEW that says "Nothing is sent" and sends nothing.
//
// This screen builds nothing of its own: every row opens the screen that already
// exists, through a callback the settings hub supplies.
import 'package:flutter/material.dart';

import 'ui/olive_ui.dart';

class AdultsHelpersScreen extends StatelessWidget {
  const AdultsHelpersScreen({
    super.key,
    required this.childName,
    required this.grownupLines,
    required this.onChangePeople,
    required this.onHelpers,
    required this.onInvitePreview,
  });

  final String childName;

  /// One plain line per grown-up in this family, e.g. 'Jess (Mom): Ivy calls you Mommy'.
  final List<String> grownupLines;

  /// Opens the family builder's People screen. Null hides the row (no family builder here).
  final VoidCallback? onChangePeople;

  /// Opens the Village hub, where the sitter pass, grandparent page and school summary
  /// are written.
  final VoidCallback onHelpers;

  /// Opens the invitation PREVIEW.
  final VoidCallback onInvitePreview;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Adults and helpers')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('Grown-ups', style: t.titleSmall),
            const SizedBox(height: 6),
            if (grownupLines.isEmpty)
              const EmptyState(
                key: Key('adultsNone'),
                title: 'No grown-ups listed on this phone yet',
                sub: 'They show here once a family is set up on this phone.',
              )
            else
              OliveCard(
                child: Column(children: <Widget>[
                  for (int i = 0; i < grownupLines.length; i++)
                    OliveRow(key: Key('adultsGrownup_$i'), icon: OliveIcons.user, title: grownupLines[i]),
                ]),
              ),
            const SizedBox(height: 8),
            if (onChangePeople != null)
              OliveCard(
                child: OliveRow(
                  key: const Key('adultsChangePeople'),
                  icon: OliveIcons.users,
                  title: 'Change who is in $childName’s life',
                  sub: 'Goes through the preview and your timing',
                  onTap: onChangePeople,
                ),
              ),
            const SizedBox(height: 16),
            Text('Helpers', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: OliveRow(
                key: const Key('adultsHelpers'),
                icon: OliveIcons.file,
                title: 'Sitter pass, grandparent page, school summary',
                sub: 'Written by you. Shown on this screen only: it is not sent, saved by the sitter or shared as a link.',
                onTap: onHelpers,
              ),
            ),
            const SizedBox(height: 16),
            Text('Another adult', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: OliveRow(
                key: const Key('adultsInvite'),
                icon: OliveIcons.mail,
                title: 'Invite a co-parent (preview)',
                sub: 'See what another adult would be asked. Nothing is sent',
                onTap: onInvitePreview,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
