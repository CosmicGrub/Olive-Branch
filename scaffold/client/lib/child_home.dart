// OLIVE BRANCH — child shell, home. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.1.
//
// Renders MARKUP screen 01. Three invariants the widget tree must preserve:
//   - Availability is stated in HER frame; his time is the aside. (§4.1)
//   - Countdown is in sleeps, computed on her local day boundary. (§8.2.5)
//   - No settings affordance exists at any depth. (§8.1)
//
// The kiosk lock (§5.20) that used to be a dev-preview-only stub here is now
// real — see kiosk_shell.dart, which wraps this widget from entry_gate.dart
// rather than living inside it. ChildHome itself stays lock-agnostic.
import 'package:flutter/material.dart';
import 'calendar_day_logic.dart';
import 'call_screen.dart';
import 'child_more.dart';
import 'game_logic.dart';
import 'game_picker.dart';
import 'game_story.dart';
import 'games_hub.dart';
import 'homework_screen.dart';
import 'inbox_screen.dart';
import 'my_day.dart';
import 'showcase_screen.dart';
import 'storyteller_screen.dart';
import 'wants_needs.dart';

/// Honest acknowledgment for a feature this preview build doesn't implement
/// yet, rather than a silent no-op — the same "recorded, not glossed over"
/// posture the rest of this project already takes for unbuilt surfaces.
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class ChildHome extends StatelessWidget {
  const ChildHome({super.key, required this.childName, required this.presence,
    required this.sleepsUntilHandover, required this.unreadCount});

  final String childName;
  final ParentPresence? presence;
  final int sleepsUntilHandover;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => Scaffold(
    // SingleChildScrollView + Column, NOT ListView: a sliver-backed list only
    // realizes children near the viewport, silently dropping ones scrolled
    // below the fold from the widget/element tree entirely — the exact bug
    // several of the parallel groups independently hit and documented (e.g.
    // message_banking.dart, letters_screen.dart). This wiring pass's own grid
    // expansion (adding tiles for every newly-wired screen) pushed the
    // "sleeps until" counter below the default test viewport and made it
    // invisible to `find.text`, which is what surfaced this for real rather
    // than by inspection — same discovery path those groups describe.
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hi $childName', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      if (presence != null) _PresenceCard(presence!, childName: childName),
      const SizedBox(height: 12),
      // 64dp minimum targets for pre-readers (§8.4), but a FIXED tile height.
      //
      // This was `GridView.count` with the default aspect ratio of 1, which
      // makes tile height scale with device WIDTH. On a tablet — the actual
      // target device for a child — two rows of square tiles consumed the whole
      // viewport and pushed the "sleeps until" counter below the fold, where a
      // child would never scroll to find it. Caught the first time these
      // widgets were rendered rather than contract-checked.
      GridView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
          mainAxisExtent: 108),
        children: [
          _Tile(icon: Icons.edit, label: 'Homework',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HomeworkScreen(childName: childName)))),
          _Tile(icon: Icons.extension, label: 'Play together',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GamePickerScreen(
                childName: childName,
                onPlay: (playContext, kind) {
                  if (kind == GameKind.story) {
                    Navigator.of(playContext).push(MaterialPageRoute<void>(
                      builder: (_) => GameStoryScreen(childName: childName)));
                  } else {
                    _notBuiltYet(playContext, 'That game');
                  }
                },
              )))),
          _Tile(icon: Icons.casino_outlined, label: 'More games',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GamesHubScreen(childName: childName)))),
          _Tile(icon: Icons.star_border, label: 'My list',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const WantsNeedsScreen()))),
          _Tile(icon: Icons.mail_outline, label: 'Messages',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => InboxScreen(
                childName: childName, messages: List<InboxMessage>.of(demoInboxMessages))))),
          _Tile(icon: Icons.wb_sunny_outlined, label: 'My day',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MyDayScreen(
                childName: childName, parts: demoDayParts, nowLocal: hhmmNow())))),
          _Tile(icon: Icons.auto_stories_outlined, label: 'Storyteller',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => StorytellerScreen(childName: childName)))),
          _Tile(icon: Icons.photo_camera_outlined, label: 'Show & tell',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ShowcaseScreen(childName: childName)))),
          _Tile(icon: Icons.more_horiz, label: 'More for you',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ChildMoreScreen(childName: childName)))),
        ]),
      const SizedBox(height: 12),
      _Sleeps(sleepsUntilHandover),
    ]))),
  );
}

class ParentPresence {
  const ParentPresence(this.name, this.theirLocalTime, this.freeUntilHerTime);
  final String name, theirLocalTime, freeUntilHerTime;
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard(this.p, {required this.childName});
  final ParentPresence p;
  final String childName;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${p.name} is free right now',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      // HER frame first; his time is the aside.
      Text("It's ${p.theirLocalTime} where ${p.name} is · "
           'until ${p.freeUntilHerTime}',
        style: const TextStyle(fontSize: 12.5)),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
          child: Text('Call ${p.name}'))),
    ]),
  ));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  // Defaults to the honest not-built-yet acknowledgment; tiles with a real
  // destination (e.g. "My list" -> WantsNeedsScreen) override it.
  final void Function(BuildContext context)? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => (onTap ?? (c) => _notBuiltYet(c, label))(context),
    child: Container(constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.primaryContainer),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 28), const Spacer(),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])));
}

class _Sleeps extends StatelessWidget {
  const _Sleeps(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$n', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
    const SizedBox(width: 10),
    // "sleeps", never hours. Children do not think in hours (§8.2.5).
    Text(n == 1 ? 'sleep until\nthe handover' : 'sleeps until\nthe handover',
      style: const TextStyle(fontSize: 12.5)),
  ]);
}
