// OLIVE BRANCH — guardian shell, "show me" (his side). UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §9.10, §9.10.7–§9.10.9. Renders MARKUP screen 'showGuardian'.
//
// Three invariants this widget tree enforces, all ported from
// packages/showcase/src/exchange.ts via showcase_logic.dart:
//
//   - At most three asks are ever pending (maxPendingAsks). exchange.ts's
//     own askForShow() drops the oldest SILENTLY once a fourth arrives, and
//     she is never told. That silence is correct for her screen and wrong
//     for his: hiding the cap from the one person capable of feeling it
//     would just move the "backlog of disappointment" the TS doc-comment
//     warns about from her side to nobody's side at all. So here the cap is
//     loud — a running "n of 3 waiting" badge, and a confirmation naming
//     exactly which ask is about to be retired before it happens.
//
//   - A text-only reply to a thing she made, sent spontaneously, or added
//     to a collection gets nudged toward replying in kind
//     (replyGuidance()), never blocked. Refusing would mean some shows go
//     unanswered, which is worse than a tired "nice!" at eleven at night —
//     the TS module already settled on nudge-once as the compromise.
//
//   - Counts ARE shown here (the shelf, the pending-asks badge). P2 forbids
//     showing a score or streak TO THE CHILD, not a parent glancing at what
//     she has been into. shelfChildView() in the TS original strips counts
//     for her side; this screen is deliberately the one place they survive.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'showcase_logic.dart';

class ShowGuardianScreen extends StatefulWidget {
  const ShowGuardianScreen({
    super.key,
    this.childName = 'Ivy',
    this.guardianLabel = 'Daddy', // his own word, §8.5.3 — not editable here
    this.childAge = 6,
    // Preview/test-only override of the seeded pending-asks list — null
    // means "use the two realistic seed asks" (the normal, shipped path).
    // Exists so the empty "nothing waiting" state below is actually
    // reachable and provable in a widget test, not just a branch nobody
    // exercises.
    this.initialAsks,
  });
  final String childName;
  final String guardianLabel;
  final int childAge;
  final List<Ask>? initialAsks;

  @override
  State<ShowGuardianScreen> createState() => _ShowGuardianScreenState();
}

/// A show she has already sent, waiting on a reply. Local to this preview
/// build — packages/showcase/src/showcase.ts's `Show` carries more (artifact
/// ids, preservation flag) than a screen with no backend behind it needs to
/// round-trip.
class _ReceivedShow {
  _ReceivedShow({
    required this.id, required this.kind, required this.summary,
    required this.emoji, required this.shownAgo,
  });
  final String id;
  final ShowKind kind;
  final String summary;
  final String emoji;
  final String shownAgo;
  bool replied = false;
}

class _ShowGuardianScreenState extends State<ShowGuardianScreen> {
  late DateTime _now;
  ShowKind _kind = ShowKind.object;
  final _promptController = TextEditingController();
  late List<Interest> _interests;
  late List<Ask> _asks;
  late List<Collection> _collections;
  static const _interestLabels = <String, String>{'dino': 'Dinosaurs', 'rocks': 'Rocks'};
  late List<_ReceivedShow> _shows;
  final Map<String, TextEditingController> _replyControllers = {};

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _interests = [
      Interest(id: 'dino', label: 'dinosaurs', addedBy: Side.child,
        addedAt: _now.subtract(const Duration(days: 40)),
        lastShownAt: _now.subtract(const Duration(days: 3))),
    ];
    // Oldest first — askForShow()'s FIFO displacement depends on that order.
    // Deliberately worded differently from anything promptsFor() would
    // generate below, so a seeded ask and an auto-suggested chip never
    // collide on the exact same text.
    _asks = widget.initialAsks ?? [
      Ask(id: 'ask1', fromUserId: 'dad', fromLabel: widget.guardianLabel,
        prompt: "Show me the biggest dinosaur you've got",
        askedAt: _now.subtract(const Duration(hours: 20))),
      Ask(id: 'ask2', fromUserId: 'dad', fromLabel: widget.guardianLabel,
        prompt: 'Show me one thing that made you laugh today',
        askedAt: _now.subtract(const Duration(hours: 3))),
    ];
    _collections = [
      Collection(interestId: 'dino', entries: [
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus',
          shownAt: _now.subtract(const Duration(days: 30))),
        CollectionEntry(id: 'e2', interestId: 'dino', name: 'Triceratops',
          shownAt: _now.subtract(const Duration(days: 12))),
        CollectionEntry(id: 'e3', interestId: 'dino', name: 'T. Rex',
          shownAt: _now.subtract(const Duration(days: 2))),
      ]),
      Collection(interestId: 'rocks', entries: [
        CollectionEntry(id: 'e4', interestId: 'rocks', name: 'The sparkly one',
          shownAt: _now.subtract(const Duration(days: 6))),
      ]),
    ];
    _shows = [
      _ReceivedShow(id: 's1', kind: ShowKind.creation, summary: 'A drawing of a Stegosaurus',
        emoji: '🎨', shownAgo: 'this morning, her time'),
      _ReceivedShow(id: 's2', kind: ShowKind.spontaneous, summary: 'Look what happened — a wobbly tooth!',
        emoji: '⚡', shownAgo: 'yesterday evening, her time'),
    ];
  }

  @override
  void dispose() {
    _promptController.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _suggested => promptsFor(_kind, _interests, _now, limit: 4);

  int get _openAskCount => _asks.where((a) => !a.answered).length;

  void _commitAsk(Ask ask) {
    final result = askForShow(_asks, ask);
    setState(() {
      _asks = result.asks;
      _promptController.clear();
    });
    final displaced = result.displaced;
    if (displaced != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Retired: "${displaced.prompt}" — it was never shown to ${widget.childName}.'),
        duration: const Duration(seconds: 3)));
    }
  }

  Future<void> _sendAsk() async {
    final typed = _promptController.text.trim();
    final prompt = typed.isNotEmpty ? typed : (_suggested.isNotEmpty ? _suggested.first : 'Show me something');
    final ask = Ask(id: 'ask-${DateTime.now().microsecondsSinceEpoch}', fromUserId: 'dad',
      fromLabel: widget.guardianLabel, prompt: prompt, askedAt: DateTime.now());

    if (_openAskCount < maxPendingAsks) {
      _commitAsk(ask);
      return;
    }
    final oldest = _asks.where((a) => !a.answered).first;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Three are already waiting'),
        content: Text('${widget.childName} already has three things waiting to show you. '
          'Sending this one retires the oldest — "${oldest.prompt}" — before she ever '
          'answers it. She is never told an ask was dropped, so this is the moment that has to carry it.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Send anyway')),
        ],
      ),
    );
    if (!mounted) return;
    if (proceed ?? false) _commitAsk(ask);
  }

  String _agePhrase(Ask a) {
    final hours = askAgeInReachableHours(a, DateTime.now(), defaultReachableHoursPerDay.toDouble());
    if (hours < 1) return 'sent moments ago, on her clock';
    final rounded = hours.round();
    return 'about $rounded reachable ${rounded == 1 ? 'hour' : 'hours'} of hers so far';
  }

  TextEditingController _controllerFor(String showId) =>
      _replyControllers.putIfAbsent(showId, TextEditingController.new);

  void _sendReply(_ReceivedShow show) {
    final controller = _controllerFor(show.id);
    final text = controller.text.trim();
    final guidance = replyGuidance(show.kind, ReplyKind.text);
    if (text.isNotEmpty && guidance.nudge != null) {
      showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Reply in kind?'),
        content: Text(guidance.nudge!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Attach something instead')),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() => show.replied = true);
            },
            child: const Text('Send the words anyway')),
        ],
      ));
      return;
    }
    setState(() => show.replied = true);
  }

  @override
  Widget build(BuildContext context) {
    final shelfEntries = shelf(_collections, _interestLabels);
    final openAsks = _asks.where((a) => !a.answered).toList();

    // Pane A — the ask composer, verbatim. Only ever pulled into a named
    // list so the wide/narrow branches below can share it rather than
    // diverging — same discipline message_banking.dart/letters_screen.dart
    // use for their own two panes.
    final List<Widget> composeChildren = <Widget>[
      _AskComposer(
        kind: _kind, onKindChanged: (k) => setState(() => _kind = k),
        suggested: _suggested, controller: _promptController,
        openCount: _openAskCount, onSend: _sendAsk,
      ),
    ];

    // Pane B — the activity/reply feed: pending asks, the shelf, and the
    // received-show reply tiles, stacked together as a unit in the same
    // order this screen always rendered them.
    final List<Widget> listChildren = <Widget>[
      Text('Waiting to hear back', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (openAsks.isEmpty)
        const _NothingWaitingNotice()
      else
        for (final a in openAsks) _PendingAskTile(ask: a, agePhrase: _agePhrase(a)),
      const SizedBox(height: 20),
      Text('What she has been collecting', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SizedBox(height: 104, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shelfEntries.length,
        separatorBuilder: (context, i) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _ShelfCard(entry: shelfEntries[i]),
      )),
      const SizedBox(height: 20),
      Text('What she has shown you', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final s in _shows)
        _ReceivedShowTile(show: s, controller: _controllerFor(s.id), onSend: () => _sendReply(s)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s show & tell")),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // pending asks/shelf/received-show tiles scrolled below the fold from
      // the widget tree. Same fix message_banking.dart/letters_screen.dart
      // already document for the same bug class.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same threshold message_banking.dart/letters_screen.dart
        // use for their own two-pane splits.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: wide
            ? Row(key: const Key('showGuardianTwoPaneRow'),
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: composeChildren)),
                  const SizedBox(width: 24),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: listChildren)),
                ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...composeChildren,
                const SizedBox(height: 20),
                ...listChildren,
              ]),
        );
      })),
    );
  }
}

/// The honest empty state for "waiting to hear back": genuinely nothing
/// pending is a calm, good state (not an error, nothing to fix), so this
/// stays a small icon + the same plain sentence rather than a bare Text
/// node or anything implying she owes a reply.
class _NothingWaitingNotice extends StatelessWidget {
  const _NothingWaitingNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(Icons.check_circle_outline, size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(child: Text('Nothing waiting right now.',
        style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]),
  );
}

class _AskComposer extends StatelessWidget {
  const _AskComposer({
    required this.kind, required this.onKindChanged, required this.suggested,
    required this.controller, required this.openCount, required this.onSend,
  });
  final ShowKind kind;
  final ValueChanged<ShowKind> onKindChanged;
  final List<String> suggested;
  final TextEditingController controller;
  final int openCount;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    // Both chip rows scroll horizontally rather than wrapping — with eight
    // kind labels and up to four generated prompts, a Wrap would turn this
    // card into most of a phone screen before the actual text field or send
    // button ever appeared. A single scrollable strip keeps the whole
    // composer compact regardless of how many kinds or prompts exist.
    final kinds = ShowKind.values.where((k) => k != ShowKind.spontaneous).toList();
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Ask her to show you something',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            _CapBadge(openCount: openCount),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 32, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kinds.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ChoiceChip(
              label: Text(kinds[i].title), selected: kinds[i] == kind,
              onSelected: (_) => onKindChanged(kinds[i])),
          )),
          const SizedBox(height: 12),
          if (suggested.isNotEmpty)
            SizedBox(height: 32, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggested.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ActionChip(
                label: Text(suggested[i], style: Theme.of(context).textTheme.bodySmall),
                onPressed: () => controller.text = suggested[i]),
            )),
          const SizedBox(height: 12),
          TextField(controller: controller, decoration: const InputDecoration(
            border: OutlineInputBorder(), hintText: 'Or write your own ask…')),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: FilledButton(
            onPressed: onSend, child: const Text('Send the ask'))),
        ])),
    );
  }
}

class _CapBadge extends StatelessWidget {
  const _CapBadge({required this.openCount});
  final int openCount;

  @override
  Widget build(BuildContext context) {
    final atCap = openCount >= maxPendingAsks;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: atCap ? scheme.errorContainer : scheme.secondaryContainer),
      child: Text('$openCount of $maxPendingAsks waiting',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700,
          color: atCap ? scheme.onErrorContainer : scheme.onSecondaryContainer)),
    );
  }
}

class _PendingAskTile extends StatelessWidget {
  const _PendingAskTile({required this.ask, required this.agePhrase});
  final Ask ask;
  final String agePhrase;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.hourglass_top),
      title: Text(ask.prompt),
      subtitle: Text(agePhrase),
    ),
  );
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.entry});
  final ShelfEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(entry.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${entry.count} shown', style: Theme.of(context).textTheme.bodySmall),
        if (entry.newest != null)
          Text('newest: ${entry.newest}', overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
  );
}

class _ReceivedShowTile extends StatelessWidget {
  const _ReceivedShowTile({required this.show, required this.controller, required this.onSend});
  final _ReceivedShow show;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(show.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(child: Text(show.summary, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Text(show.shownAgo, style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 12),
        if (show.replied)
          Row(children: [
            Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Replied', style: TextStyle(fontWeight: FontWeight.w600)),
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: TextField(controller: controller,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Reply…'))),
            const SizedBox(width: 8),
            // Was 44dp — under this app's 48dp tap-target floor. This is a
            // genuine interactive control (send this reply), not a dense
            // board-game cell, so it gets the real minimum.
            SizedBox(height: 48, child: FilledButton(onPressed: onSend, child: const Text('Send'))),
          ]),
      ])),
  );
}
