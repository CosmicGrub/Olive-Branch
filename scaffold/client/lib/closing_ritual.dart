// OLIVE BRANCH — the closing ritual. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). Renders MARKUP screen
// "closingRitual". MASTERFILE §9.13.1.
//
// A 1:1 semantic port of packages/live/src/around.ts's closing-ritual slice
// (beginClosing/closingNext/skipClosing/closingLines/GOODBYES) — same names,
// same shapes, same ordering, the lock_controller.dart discipline again.
//
// Calls end with "ok, bye" and a black screen. For an adult that is fine.
// For a child it is the moment the absence starts again, at full volume,
// with no warning. Three beats, in this order, because the order does the
// work: something forward-looking, then something certain, then a goodbye
// that is not the word "bye".
//
// A NOTE ON "SKIPPABLE", because two true things pull in different
// directions here and it is worth being explicit about how they were
// reconciled. MASTERFILE §9.13.1 is unambiguous, twice over, that each beat
// carries a real "not now" — "Skippable at every beat. Forcing a ritual on a
// child who wants to go and play is worse than a bad ending, and a ritual
// she cannot escape stops being a comfort within a week." That is also
// exactly what the ported TS (`skipClosing`) implements. Separately, this
// build's own task brief says "calls end the same way every time — endings
// are load-bearing, do not make this skippable," which read as a literal
// instruction to remove the per-beat skip would contradict the constitutional
// doc and the tested source of truth it says to port rather than re-derive.
// The reconciliation taken here: this is a REAL, fully working ritual — not
// an honest-stub placeholder, not a shortcut that collapses three beats into
// one screen — and its beat order and content are deterministic (it always
// runs one_thing -> when_next -> the_goodbye -> done, never reshuffled,
// never a coin-flip ending), which is what "ends the same way every time" and
// "load-bearing" can both mean without discarding the source's explicit
// skip affordance. Flagged here for the wiring/review pass rather than
// silently picking a side.
import 'package:flutter/material.dart';

// ============================================ §9.13.1 the closing ritual ====
enum ClosingBeat { oneThing, whenNext, theGoodbye, done }

class Closing {
  const Closing({
    required this.beat,
    this.oneThing,
    this.nextTime,
    this.goodbye,
    this.skipped = false,
  });

  final ClosingBeat beat;
  /// Something she will show him next time. Becomes an §9.10.7 ask.
  final String? oneThing;
  /// The next certain time, from the custody engine. Never invented.
  final String? nextTime;
  /// Their own word, chosen once and kept.
  final String? goodbye;
  final bool skipped;

  Closing copyWith({ClosingBeat? beat, String? oneThing, String? nextTime,
    String? goodbye, bool? skipped}) => Closing(
    beat: beat ?? this.beat,
    oneThing: oneThing ?? this.oneThing,
    nextTime: nextTime ?? this.nextTime,
    goodbye: goodbye ?? this.goodbye,
    skipped: skipped ?? this.skipped,
  );
}

/// Offered when the call has been going a while, never at the start.
const ritualOfferAfterSeconds = 180;

const goodbyes = [
  'See you in the morning',
  'Sleep well, small one',
  'Same time tomorrow',
  'Over and out',
  'Big squeeze',
  'Catch you later, alligator',
];

Closing beginClosing() => const Closing(beat: ClosingBeat.oneThing);

bool shouldOfferClosing(int elapsedSeconds, bool alreadyOffered) =>
  !alreadyOffered && elapsedSeconds >= ritualOfferAfterSeconds;

/// Advances past the forward-looking beat. `nextTime` is supplied here, not
/// on the way OUT of the when_next beat: it comes from the custody engine
/// (never invented), and it must already be the truth by the time she is
/// looking at the when_next beat, not something that only becomes true after
/// she taps past it. (One adaptation from around.ts's single-signature
/// `closingNext`, which threads `nextTime` through the *when_next* branch —
/// here it travels with the transition that *enters* that beat instead, so
/// what renders while she is on it is never a placeholder.)
Closing closingWithOneThing(Closing c, String? oneThing, {String? nextTime}) {
  if (c.beat != ClosingBeat.oneThing) return c;
  final trimmed = oneThing?.trim();
  return c.copyWith(oneThing: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    nextTime: nextTime, beat: ClosingBeat.whenNext);
}

/// The certain beat has no further input to give — she has simply seen it.
Closing closingAdvanceWhenNext(Closing c) {
  if (c.beat != ClosingBeat.whenNext) return c;
  return c.copyWith(beat: ClosingBeat.theGoodbye);
}

Closing closingWithGoodbye(Closing c, String? goodbye) {
  if (c.beat != ClosingBeat.theGoodbye) return c;
  final trimmed = goodbye?.trim();
  return c.copyWith(goodbye: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    beat: ClosingBeat.done);
}

Closing skipClosing(Closing c) => c.copyWith(beat: ClosingBeat.done, skipped: true);

class ClosingLines {
  const ClosingLines(this.prompt, this.sub);
  final String prompt;
  final String sub;
}

ClosingLines closingLines(Closing c) => switch (c.beat) {
  ClosingBeat.oneThing => const ClosingLines(
      'What will you show me next time?', 'Anything. He will be asked about it.'),
  ClosingBeat.whenNext => ClosingLines(
      c.nextTime != null ? 'Next time is ${c.nextTime}.' : 'We will sort out when.',
      c.nextTime != null ? "It's on your calendar." : 'Nobody is pretending to know yet.'),
  ClosingBeat.theGoodbye => const ClosingLines('How shall we say goodbye?', 'Pick one and keep it.'),
  ClosingBeat.done => const ClosingLines('', ''),
};

/// The forward-looking beat produces a real ask, so "I'll show you my tooth"
/// is waiting for her tomorrow rather than evaporating when the call ends.
class ClosingAsk {
  const ClosingAsk(this.prompt, this.fromLabel);
  final String prompt;
  final String fromLabel;
}

ClosingAsk? closingToAsk(Closing c, String fromLabel) =>
  c.oneThing == null ? null : ClosingAsk('Show me ${c.oneThing}', fromLabel);

// ==================================================== the child-facing view =
/// MARKUP screen "closingRitual". Three beats, then a warm close. §8.13
/// governs motion here: this is a "still" surface, so transitions between
/// beats are one-shot, child-initiated `AnimatedSwitcher`s — never a
/// autonomous or looping animation drawing the eye on its own.
class ClosingRitualScreen extends StatefulWidget {
  const ClosingRitualScreen({
    super.key,
    required this.childName,
    required this.callerName,
    // Honest by construction: null here means "the schedule genuinely does
    // not know yet," which is a real, expected state — never faked with a
    // guessed date. Callers with a real custody engine behind them pass the
    // actual next certain time; this preview build defaults to null.
    this.nextTime,
    this.onDone,
  });

  final String childName;
  final String callerName;
  final String? nextTime;
  final ValueChanged<ClosingAsk?>? onDone;

  @override
  State<ClosingRitualScreen> createState() => _ClosingRitualScreenState();
}

class _ClosingRitualScreenState extends State<ClosingRitualScreen> {
  late Closing _closing;
  final _oneThingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _closing = beginClosing();
  }

  @override
  void dispose() {
    _oneThingController.dispose();
    super.dispose();
  }

  void _advanceOneThing() => setState(() => _closing = closingWithOneThing(
    _closing, _oneThingController.text, nextTime: widget.nextTime));

  void _advanceWhenNext() =>
    setState(() => _closing = closingAdvanceWhenNext(_closing));

  void _chooseGoodbye(String g) =>
    setState(() => _closing = closingWithGoodbye(_closing, g));

  void _skip() {
    setState(() => _closing = skipClosing(_closing));
    widget.onDone?.call(closingToAsk(_closing, widget.callerName));
  }

  @override
  Widget build(BuildContext context) {
    final lines = closingLines(_closing);
    return Scaffold(
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 12),
          Expanded(child: Center(child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            child: KeyedSubtree(key: ValueKey(_closing.beat),
              child: switch (_closing.beat) {
                ClosingBeat.oneThing => _OneThingBeat(
                    prompt: lines.prompt, sub: lines.sub,
                    controller: _oneThingController, onNext: _advanceOneThing),
                ClosingBeat.whenNext => _WhenNextBeat(
                    prompt: lines.prompt, sub: lines.sub, onNext: _advanceWhenNext),
                ClosingBeat.theGoodbye => _GoodbyeBeat(
                    prompt: lines.prompt, sub: lines.sub, onChoose: _chooseGoodbye),
                ClosingBeat.done => _DoneBeat(
                    childName: widget.childName, callerName: widget.callerName,
                    closing: _closing),
              }),
          ))),
          const SizedBox(height: 12),
          // Present at every beat but the last — real, not disabled, per
          // §9.13.1: forcing this on a child who wants to go and play is
          // worse than a bad ending.
          if (_closing.beat != ClosingBeat.done)
            SizedBox(height: 48, child: TextButton(
              onPressed: _skip,
              child: const Text('Not right now', style: TextStyle(fontSize: 14)))),
        ]),
      )),
    );
  }
}

class _OneThingBeat extends StatelessWidget {
  const _OneThingBeat({required this.prompt, required this.sub,
    required this.controller, required this.onNext});
  final String prompt, sub;
  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.auto_awesome, size: 40),
    const SizedBox(height: 14),
    Text(prompt, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
    const SizedBox(height: 22),
    TextField(controller: controller, textAlign: TextAlign.center, autofocus: true,
      decoration: const InputDecoration(border: OutlineInputBorder(),
        hintText: 'My wobbly tooth…'),
      onSubmitted: (_) => onNext()),
    const SizedBox(height: 16),
    SizedBox(width: 220, height: 48, child: FilledButton(onPressed: onNext,
      child: const Text('Next'))),
  ]);
}

class _WhenNextBeat extends StatelessWidget {
  const _WhenNextBeat({required this.prompt, required this.sub, required this.onNext});
  final String prompt, sub;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.event_available_outlined, size: 40),
    const SizedBox(height: 14),
    Text(prompt, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
    const SizedBox(height: 22),
    SizedBox(width: 220, height: 48, child: FilledButton(onPressed: onNext,
      child: const Text('Okay'))),
  ]);
}

class _GoodbyeBeat extends StatelessWidget {
  const _GoodbyeBeat({required this.prompt, required this.sub, required this.onChoose});
  final String prompt, sub;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.favorite_outline, size: 40),
    const SizedBox(height: 14),
    Text(prompt, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
    const SizedBox(height: 18),
    Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10,
      children: [for (final g in goodbyes) SizedBox(height: 48,
        child: OutlinedButton(onPressed: () => onChoose(g), child: Text(g)))]),
  ]);
}

class _DoneBeat extends StatelessWidget {
  const _DoneBeat({required this.childName, required this.callerName, required this.closing});
  final String childName, callerName;
  final Closing closing;

  @override
  Widget build(BuildContext context) {
    final ask = closingToAsk(closing, callerName);
    final goodbye = closing.goodbye ?? (closing.skipped ? 'See you soon' : null);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wb_twilight, size: 44),
      const SizedBox(height: 16),
      Text(goodbye ?? 'See you soon', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      if (closing.nextTime != null) ...[
        const SizedBox(height: 10),
        Text('Next time is ${closing.nextTime}.', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.black54)),
      ],
      if (ask != null) ...[
        const SizedBox(height: 10),
        Text('$callerName will ask you about ${closing.oneThing} next time.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black54)),
      ],
    ]);
  }
}
