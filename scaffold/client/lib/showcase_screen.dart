// OLIVE BRANCH — child shell, "show me". UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.10. Renders MARKUP
// screen 'showcase'.
//
// She shows; he sees. Two doors in, both real:
//   - An ask waiting for her, from a parent, by name — never a count, never
//     an age. asksChildView() in showcase_logic.dart drops both on purpose:
//     an ask that has waited four days must look exactly like one from this
//     morning (exchange.ts §9.10.7). There are at most three of these ever;
//     a fourth silently retires the oldest upstream of this screen (see
//     show_guardian.dart, where that retirement is made loud instead — it
//     has to be felt SOMEWHERE, and it must not be here).
//   - A prompt she reaches for herself, drawn from what she's into lately,
//     or the always-available "Look what happened" for the thing nobody
//     asked about. Interests recede quietly after ~120 days of not being
//     shown and are never resurfaced to her as "you used to like this".
//
// No settings affordance, no score, no streak. This preview build has no
// camera plugin wired up (see pubspec.yaml — jitsi_meet_flutter_sdk is the
// only media dependency, for calls), so "capture" below is an honest
// stand-in: she picks from a small deck of things she could be holding up,
// or writes a line, rather than the app pretending to open a camera it does
// not have.
import 'package:flutter/material.dart';
import 'showcase_logic.dart';

class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key, this.childName = 'Ivy'});
  final String childName;

  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ArtifactChoice {
  const _ArtifactChoice(this.emoji, this.label);
  final String emoji, label;
}

// A stand-in for a real camera roll — see the file header.
const _artifactChoices = <_ArtifactChoice>[
  _ArtifactChoice('🦖', 'My dinosaur'),
  _ArtifactChoice('🎨', 'My drawing'),
  _ArtifactChoice('🧱', 'What I built'),
  _ArtifactChoice('📖', 'My book'),
  _ArtifactChoice('🪨', 'A rock I found'),
  _ArtifactChoice('🧦', 'Something silly'),
];

class _ShowcaseScreenState extends State<ShowcaseScreen> {
  late DateTime _now;
  late List<Ask> _asks;
  late List<Interest> _interests;

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
    _asks = [
      Ask(id: 'ask1', fromUserId: 'dad', fromLabel: 'Daddy',
        prompt: "Show me the biggest dinosaur you've got",
        askedAt: _now.subtract(const Duration(hours: 20))),
      Ask(id: 'ask2', fromUserId: 'dad', fromLabel: 'Daddy',
        prompt: 'Show me one thing that made you laugh today',
        askedAt: _now.subtract(const Duration(hours: 3))),
    ];
  }

  List<AskChildView> get _openAsks => asksChildView(_asks);

  void _openCapture({Ask? forAsk, String? prompt}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => _CaptureSheet(
        prompt: prompt,
        onSend: (label) {
          Navigator.of(sheetContext).pop();
          final toName = forAsk?.fromLabel;
          setState(() {
            if (forAsk != null) {
              _asks = answerAsk(_asks, forAsk.id, 'show-${DateTime.now().microsecondsSinceEpoch}');
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(toName != null ? 'Sent to $toName!' : 'Sent!'),
            duration: const Duration(seconds: 2)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompts = <String>{
      ...promptsFor(ShowKind.creation, _interests, _now, limit: 2),
      ...promptsFor(ShowKind.object, _interests, _now, limit: 2),
    }.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Show me')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Hi ${widget.childName}! What do you want to show today?',
          style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        // Always available — "she starts it". No prompt, no schedule.
        _SpontaneousButton(onTap: () => _openCapture()),
        const SizedBox(height: 20),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _openAsks.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Just for you',
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final a in _openAsks)
                    _AskCard(
                      key: ValueKey(a.askId),
                      ask: a,
                      onShow: () => _openCapture(
                        forAsk: _asks.firstWhere((x) => x.id == a.askId),
                        prompt: a.prompt),
                    ),
                  const SizedBox(height: 12),
                ]),
        ),
        Text('Or show something else', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in prompts)
            ActionChip(label: Text(p), onPressed: () => _openCapture(prompt: p)),
        ]),
      ])),
    );
  }
}

class _AskCard extends StatelessWidget {
  const _AskCard({super.key, required this.ask, required this.onShow});
  final AskChildView ask;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ask.line, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onTertiaryContainer)),
        const SizedBox(height: 8),
        Text(ask.prompt, style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onTertiaryContainer)),
        const SizedBox(height: 12),
        SizedBox(height: 48, width: double.infinity, child: FilledButton.icon(
          onPressed: onShow, icon: const Icon(Icons.videocam), label: const Text('Show them'))),
      ])),
  );
}

class _SpontaneousButton extends StatelessWidget {
  const _SpontaneousButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary]),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Look what happened!', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onPrimary)),
            const SizedBox(height: 4),
            Text('Show something right now — nobody has to ask',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9))),
          ])),
        ]),
      ),
    ),
  );
}

class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet({required this.onSend, this.prompt});
  final void Function(String label) onSend;
  final String? prompt;

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  String? _chosenLabel;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSend => _chosenLabel != null || _noteController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      if (widget.prompt != null) ...[
        Text(widget.prompt!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
      ],
      Text('Pick what you are showing', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final choice in _artifactChoices)
          _ArtifactTile(
            emoji: choice.emoji, label: choice.label,
            selected: _chosenLabel == choice.label,
            onTap: () => setState(() => _chosenLabel = choice.label),
          ),
      ]),
      const SizedBox(height: 16),
      TextField(controller: _noteController, minLines: 1, maxLines: 3,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Or tell them about it…'),
        onChanged: (_) => setState(() {})),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 48, child: FilledButton(
        onPressed: _canSend ? () => widget.onSend(_chosenLabel ?? _noteController.text.trim()) : null,
        child: const Text('Send it'))),
    ]),
  );
}

class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.emoji, required this.label, required this.selected, required this.onTap});
  final String emoji, label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 88, minHeight: 64),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
        border: selected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
      ]),
    ),
  );
}
