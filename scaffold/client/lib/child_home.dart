// OLIVE BRANCH — child shell, home. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.1.
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
import 'package:http/http.dart' as http;
import 'calendar_day_logic.dart';
import 'call_screen.dart';
import 'child_more.dart';
import 'game_copy_pattern.dart';
import 'game_dotsboxes.dart';
import 'game_draw_together.dart';
import 'game_find_it.dart';
import 'game_guess_doodle.dart';
import 'game_logic.dart';
import 'game_picker.dart';
import 'game_silly_sentence.dart';
import 'game_story.dart';
import 'game_tictactoe.dart';
import 'game_twenty_questions.dart';
import 'game_two_truths.dart';
import 'game_would_you_rather.dart';
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
    required this.sleepsUntilHandover, required this.unreadCount,
    this.baseUrl, this.childId, this.sessionToken, this.httpClient});

  final String childName;
  final ParentPresence? presence;
  // Nullable for the same reason `presence` is: no live custody-schedule
  // source exists yet for a screen fetching real data (see
  // child_home_live.dart), and a fabricated number would look exactly as
  // real as the two fields that genuinely are. Absent, not guessed.
  final int? sleepsUntilHandover;
  final int unreadCount;

  // Real homework-capture wiring (§9.1, §20.2b) — optional and additive, so
  // every existing caller (the offline demo build's ChildHome() with no
  // arguments, and every existing test) keeps behaving exactly as before.
  // Only child_home_live.dart supplies these today; when null, the
  // Homework tile pushed below still works, just against
  // capture_gate.dart's own honest simulated fallback (see that file's own
  // header) rather than a real server.
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  final http.Client? httpClient;

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
              builder: (_) => HomeworkScreen(childName: childName,
                baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                httpClient: httpClient)))),
          _Tile(icon: Icons.extension, label: 'Play together',
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GamePickerScreen(
                childName: childName,
                onPlay: (playContext, kind) {
                  // Real cases for every game this codebase has actually
                  // built a board for — Batch C's own two (copyPattern/
                  // findIt, the closing batch of Play Together Phase 1),
                  // Batch B's four (sillySentence/wouldYouRather/twoTruths/
                  // twentyQuestions), Batch A's two (drawTogether/
                  // guessDoodle), and a parallel build's (tictactoe/
                  // dotsboxes), merged rather than any pass dropping
                  // another's work. `memory` alone stays on the honest
                  // not-built-yet fallback — a separate, still-open
                  // photo-source product decision, deliberately out of
                  // scope for this phase (see game_logic.dart's own note).
                  switch (kind) {
                    case GameKind.story:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => GameStoryScreen(childName: childName)));
                    case GameKind.tictactoe:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => GameTicTacToe(childName: childName)));
                    case GameKind.dotsboxes:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => GameDotsBoxes(childName: childName)));
                    case GameKind.drawTogether:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => DrawTogetherScreen(childName: childName)));
                    case GameKind.guessDoodle:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => GuessDoodleScreen(childName: childName)));
                    case GameKind.sillySentence:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => SillySentenceScreen(childName: childName)));
                    case GameKind.wouldYouRather:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => WouldYouRatherScreen(childName: childName)));
                    case GameKind.twoTruths:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => TwoTruthsScreen(childName: childName)));
                    case GameKind.twentyQuestions:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => TwentyQuestionsScreen(childName: childName)));
                    case GameKind.copyPattern:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => CopyPatternScreen(childName: childName)));
                    case GameKind.findIt:
                      Navigator.of(playContext).push(MaterialPageRoute<void>(
                        builder: (_) => const FindItScreen()));
                    case GameKind.memory:
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
          _Tile(icon: Icons.mail_outline, label: 'Messages', badgeCount: unreadCount,
            onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => InboxScreen(
                childName: childName, messages: List<InboxMessage>.of(demoInboxMessages),
                baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                httpClient: httpClient)))),
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
              builder: (_) => ChildMoreScreen(childName: childName,
                baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                httpClient: httpClient)))),
        ]),
      if (sleepsUntilHandover != null) ...[
        const SizedBox(height: 12),
        _Sleeps(sleepsUntilHandover!),
      ],
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
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${p.name} is free right now',
        style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600)),
      // HER frame first; his time is the aside.
      Text("It's ${p.theirLocalTime} where ${p.name} is · "
           'until ${p.freeUntilHerTime}',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
          child: Text('Call ${p.name}'))),
    ]),
  ));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, this.onTap, this.badgeCount});
  final IconData icon;
  final String label;
  // Defaults to the honest not-built-yet acknowledgment; tiles with a real
  // destination (e.g. "My list" -> WantsNeedsScreen) override it.
  final void Function(BuildContext context)? onTap;
  // Unread-style count shown on the icon corner when positive. Was accepted
  // by ChildHome (`unreadCount`) and threaded all the way to main.dart's demo
  // data but never rendered anywhere — a declaration with nothing behind it.
  // Optional — null/0 renders no badge at all, not a badge showing "0".
  final int? badgeCount;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => (onTap ?? (c) => _notBuiltYet(c, label))(context),
    child: Container(constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.primaryContainer),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 28),
          if (badgeCount != null && badgeCount! > 0) ...[
            const Spacer(),
            _UnreadBadge(count: badgeCount!),
          ],
        ]),
        const Spacer(),
        Text(label, style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600)),
      ])));
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(9)),
    alignment: Alignment.center,
    child: Text(count > 9 ? '9+' : '$count',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onError, fontWeight: FontWeight.w700)));
}

class _Sleeps extends StatelessWidget {
  const _Sleeps(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Row(children: [
    // Hand-set hero numeral, not a textTheme role — documented exception
    // (§8.2.5; kept bespoke per the UI/UX design-token audit's typography
    // finding).
    Text('$n', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
    const SizedBox(width: 12),
    // "sleeps", never hours. Children do not think in hours (§8.2.5).
    Text(n == 1 ? 'sleep until\nthe handover' : 'sleeps until\nthe handover',
      style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}
