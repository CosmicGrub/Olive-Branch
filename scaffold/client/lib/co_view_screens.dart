// No longer UNVERIFIED — verified by CI (co_view_screens_test.dart).
// OLIVE BRANCH — "Read together", the screens. Design: docs/superpowers/specs/
// 2026-11-07-co-viewing-design.md and the mockups beside it. Three surfaces:
//   * the CHILD's view: an invitation (one big yes, one quiet no), the story,
//     and one All done button that is always in the same place; and the three
//     kind endings;
//   * the GUARDIAN's view: start, wait, lead (page controls, time left, an
//     "in step" chip) and the endings, which never blame the child;
//   * the daily-time sheet, where lowering is free and a raise is told to the
//     other guardian.
//
// What the child never sees: a clock, a counter, a connection meter, or the
// words allowance, limit, session or synced. "Last one for today" has no
// number. Nothing here moves on its own (§8.13): there is no animation at all.
import 'package:flutter/material.dart';
import 'co_view_logic.dart';
import 'co_view_session.dart';
import 'design_tokens.dart';

String _fmtMinutes(int m) {
  if (m <= 0) return 'Off';
  final h = m ~/ 60, r = m % 60;
  return [if (h > 0) '$h h', if (r > 0) '$r min'].join(' ');
}

/// A calm, wordless picture for a page. Real artwork replaces this later; the
/// layout, not the art, is what this wave builds.
class _NightScene extends StatelessWidget {
  const _NightScene();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(painter: _NightPainter(), child: const SizedBox.expand()),
      );
}

class _NightPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF16223A));
    final star = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 14; i++) {
      c.drawCircle(Offset(s.width * ((i * 53 % 100) / 100), s.height * ((i * 37 % 60) / 100)), i % 3 == 0 ? 1.8 : 1, star);
    }
    c.drawCircle(Offset(s.width * 0.74, s.height * 0.28), s.shortestSide * 0.13, Paint()..color = const Color(0xFFF7EFC8));
    final hill = Path()
      ..moveTo(0, s.height * 0.78)
      ..quadraticBezierTo(s.width * 0.3, s.height * 0.6, s.width * 0.6, s.height * 0.76)
      ..quadraticBezierTo(s.width * 0.85, s.height * 0.86, s.width, s.height * 0.74)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(hill, Paint()..color = const Color(0xFF1F3550));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ================================================================== child ==
/// The child's whole co-viewing surface. It switches on the follower's phase, so
/// the Navigator never has to know about invitations, endings or time.
class CoViewChildScreen extends StatelessWidget {
  const CoViewChildScreen({super.key, required this.follower, this.guardianName = 'Dad', this.onClose});
  final CoViewFollower follower;
  final String guardianName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: follower,
        builder: (context, _) => switch (follower.phase) {
          CoViewPhase.idle => const SizedBox.shrink(),
          CoViewPhase.waiting => _Invitation(follower: follower, guardianName: guardianName),
          CoViewPhase.live => _Reading(follower: follower),
          CoViewPhase.ended => _ChildEnding(ending: follower.ending ?? CoViewEnding.child, guardianName: guardianName, onClose: onClose),
        },
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({super.key, required this.label, required this.onPressed, this.quiet = false});
  final String label;
  final VoidCallback onPressed;
  final bool quiet;
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(220, 64)), shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl))));
    final child = Text(label, style: Theme.of(context).textTheme.titleMedium);
    return quiet ? OutlinedButton(onPressed: onPressed, style: style, child: child) : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}

class _Invitation extends StatelessWidget {
  const _Invitation({required this.follower, required this.guardianName});
  final CoViewFollower follower;
  final String guardianName;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xl), child: const SizedBox(height: 150, width: double.infinity, child: _NightScene())),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                header: true,
                child: Text('$guardianName wants to read a story with you', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(height: AppSpacing.xl),
              _BigButton(key: const Key('coViewJoin'), label: 'Join', onPressed: follower.join),
              const SizedBox(height: AppSpacing.md),
              _BigButton(key: const Key('coViewNotNow'), label: 'Not now', quiet: true, onPressed: follower.decline),
            ]),
          ),
        ),
      );
}

class _Reading extends StatelessWidget {
  const _Reading({required this.follower});
  final CoViewFollower follower;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = follower.story.pages[follower.page];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xl), child: const SizedBox.expand(child: _NightScene())),
                if (follower.lastOne)
                  Positioned(
                    top: AppSpacing.md, left: AppSpacing.md, right: AppSpacing.md,
                    child: Container(
                      key: const Key('coViewLastOne'),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                      decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                      child: Row(children: [
                        Icon(Icons.nightlight_outlined, color: theme.colorScheme.onTertiaryContainer),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Last one for today', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              liveRegion: true,
              child: Text(page.text, key: const Key('coViewPageText'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: _BigButton(key: const Key('coViewAllDone'), label: 'All done', quiet: true, onPressed: follower.allDone),
          ),
        ]),
      ),
    );
  }
}

class _ChildEnding extends StatelessWidget {
  const _ChildEnding({required this.ending, required this.guardianName, this.onClose});
  final CoViewEnding ending;
  final String guardianName;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final (title, sub) = switch (ending) {
      CoViewEnding.child => ('All done!', 'See you soon.'),
      CoViewEnding.guardian => ('All done', '$guardianName says goodnight.'),
      CoViewEnding.budget => ("That's all for today", 'You did a great job. See you tomorrow!'),
      CoViewEnding.declined => ('Okay!', "$guardianName will be here when you're ready."),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(ending == CoViewEnding.budget ? Icons.nightlight_outlined : Icons.eco_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: AppSpacing.lg),
              Text(title, key: const Key('coViewEndTitle'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(sub, key: const Key('coViewEndSub'), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              if (onClose != null) _BigButton(key: const Key('coViewBackHome'), label: 'Back to my home', quiet: true, onPressed: onClose!),
            ]),
          ),
        ),
      ),
    );
  }
}

// =============================================================== guardian ==
class CoViewLeaderScreen extends StatelessWidget {
  const CoViewLeaderScreen({super.key, required this.leader, this.childName = 'Ivy', this.onClose, this.onChangeTime});
  final CoViewLeader leader;
  final String childName;
  final VoidCallback? onClose;
  /// Opens the daily-time sheet; supplied by the caller so this screen stays pure.
  final VoidCallback? onChangeTime;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: leader,
        builder: (context, _) {
          final theme = Theme.of(context);
          final body = switch (leader.phase) {
            CoViewPhase.idle => _idle(context),
            CoViewPhase.waiting => _waiting(context),
            CoViewPhase.live => _live(context),
            CoViewPhase.ended => _ended(context),
          };
          return Scaffold(
            appBar: AppBar(title: Text(leader.story.title), actions: [if (onChangeTime != null) IconButton(key: const Key('coViewChangeTime'), tooltip: 'Change daily time', icon: const Icon(Icons.timer_outlined), onPressed: onChangeTime)]),
            body: SafeArea(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: DefaultTextStyle(style: theme.textTheme.bodyMedium!, child: body))),
          );
        },
      );

  Widget _timeChip(BuildContext context) {
    final b = leader.budget;
    final scheme = Theme.of(context).colorScheme;
    final mins = (leader.remainingS / 60).ceil();
    final label = switch (b) {
      BudgetState.off => 'Off',
      BudgetState.exhausted => 'Used up today',
      _ => '${_fmtMinutes(mins)} left',
    };
    return Chip(
      key: const Key('coViewTimeChip'),
      avatar: b == BudgetState.lastOne ? Icon(Icons.hourglass_bottom, size: 16, color: scheme.onTertiaryContainer) : null,
      label: Text(label),
      backgroundColor: b == BudgetState.lastOne ? scheme.tertiaryContainer : null,
    );
  }

  Widget _idle(BuildContext context) {
    final b = leader.blockedBy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpacing.sm, children: [_timeChip(context)]),
      const SizedBox(height: AppSpacing.lg),
      if (b != null)
        Card(
          key: const Key('coViewBlocked'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(b == BudgetState.off ? 'Reading together is switched off for $childName.' : "Today's time is used up.", style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      const Spacer(),
      FilledButton.icon(key: const Key('coViewStart'), onPressed: leader.start, icon: const Icon(Icons.menu_book_outlined), label: Text('Read with $childName')),
    ]);
  }

  Widget _waiting(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Waiting for $childName', key: const Key('coViewWaiting'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text("$childName's device shows a big Join button. If she isn't ready, nothing happens."),
        ]))),
        const Spacer(),
        OutlinedButton(key: const Key('coViewCancel'), onPressed: leader.end, child: const Text('Cancel')),
      ]);

  Widget _live(BuildContext context) {
    final page = leader.story.pages[leader.page];
    final last = leader.page >= leader.story.pages.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpacing.sm, children: [
        Chip(key: const Key('coViewInStep'), avatar: const Icon(Icons.circle, size: 10), label: Text('In step with $childName')),
        _timeChip(context),
      ]),
      const SizedBox(height: AppSpacing.md),
      ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xl), child: const SizedBox(height: 150, child: _NightScene())),
      const SizedBox(height: AppSpacing.md),
      Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(page.text, key: const Key('coViewLeaderText')))),
      const SizedBox(height: AppSpacing.sm),
      Center(child: Text('Page ${leader.page + 1} of ${leader.story.pages.length}', key: const Key('coViewPageCount'), style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const Key('coViewBack'), onPressed: leader.page == 0 ? null : leader.prevPage, icon: const Icon(Icons.arrow_back), label: const Text('Back'))),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: FilledButton.icon(key: const Key('coViewNext'), onPressed: last ? null : leader.nextPage, icon: const Icon(Icons.arrow_forward), label: const Text('Next page'))),
      ]),
      const Spacer(),
      OutlinedButton(key: const Key('coViewEnd'), style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: leader.end, child: const Text('End for now')),
    ]);
  }

  Widget _ended(BuildContext context) {
    final (title, sub) = switch (leader.ending ?? CoViewEnding.guardian) {
      CoViewEnding.child => ('$childName is all done', 'She ended it herself. That is always fine.'),
      CoViewEnding.budget => ("Today's time is used up", "$childName's device said goodbye for you."),
      CoViewEnding.declined => ("$childName isn't ready yet", 'Nothing was started. Try again later.'),
      CoViewEnding.guardian => ('Finished', "$childName's device said goodbye."),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, key: const Key('coViewLeaderEndTitle'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(sub),
      ]))),
      if (leader.ending == CoViewEnding.budget && onChangeTime != null) ...[
        const SizedBox(height: AppSpacing.md),
        FilledButton(key: const Key('coViewChangeTimeCta'), onPressed: onChangeTime, child: const Text('Change daily time')),
      ],
      const Spacer(),
      if (onClose != null) OutlinedButton(key: const Key('coViewLeaderClose'), onPressed: onClose, child: Text('Back to $childName')),
    ]);
  }
}

// ================================================================ allowance ==
/// The daily-time sheet. Quick choices, a 15-minute stepper, and a line that says
/// what the change will do BEFORE Save: lowering takes effect now and is not
/// asked of anyone; a raise tells the other guardian.
class CoViewAllowanceSheet extends StatefulWidget {
  const CoViewAllowanceSheet({super.key, required this.currentMin, required this.onSave, this.childName = 'Ivy'});
  final int currentMin;
  final String childName;
  final AllowanceChange Function(int requestedMin) onSave;
  @override
  State<CoViewAllowanceSheet> createState() => _CoViewAllowanceSheetState();
}

class _CoViewAllowanceSheetState extends State<CoViewAllowanceSheet> {
  late int _value = widget.currentMin;
  String? _result;

  AllowanceDirection get _direction => _value > widget.currentMin ? AllowanceDirection.raise : (_value < widget.currentMin ? AllowanceDirection.lower : AllowanceDirection.same);

  String get _line => switch (_direction) {
        AllowanceDirection.raise => 'The other guardian will be told about this change.',
        AllowanceDirection.lower => 'Takes effect right away. The other guardian is not asked.',
        _ => 'No change.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text("${widget.childName}'s daily time", style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Counted across both homes, so two houses cannot add up to double.', style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, children: [
          for (final m in const [0, 60, 120, 180])
            ChoiceChip(key: Key('coViewChip$m'), label: Text(_fmtMinutes(m)), selected: _value == m, onSelected: (_) => setState(() => _value = m)),
        ]),
        const SizedBox(height: AppSpacing.md),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton.filledTonal(key: const Key('coViewLess'), tooltip: '15 minutes less', onPressed: _value <= minAllowanceMin ? null : () => setState(() => _value = (_value - 15).clamp(minAllowanceMin, maxAllowanceMin)), icon: const Icon(Icons.remove)),
          Text(_fmtMinutes(_value), key: const Key('coViewValue'), style: theme.textTheme.headlineMedium),
          IconButton.filledTonal(key: const Key('coViewMore'), tooltip: '15 minutes more', onPressed: _value >= maxAllowanceMin ? null : () => setState(() => _value = (_value + 15).clamp(minAllowanceMin, maxAllowanceMin)), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Text(_result ?? _line, key: const Key('coViewLine'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const Key('coViewSave'),
          onPressed: _direction == AllowanceDirection.same ? null : () {
            final r = widget.onSave(_value);
            setState(() => _result = r.ok ? 'Saved.' : 'That change was not allowed.');
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
