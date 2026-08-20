// OLIVE BRANCH — the knock screen. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §5.25.2,
// §8.8.5, §9.13.4.
//
// The real UI on top of call_knock.dart's ported logic. "A ring demands
// answering. A knock waits" — so this screen is deliberately calm: no
// numeric countdown, no urgent color, no sound cue beyond whatever the OS
// notification itself already did. It waits `knockWaitsSeconds` (90) and,
// if she never comes to it, dismisses itself QUIETLY — no "missed call,"
// no error, nothing red. §9.13.4 already settled that rule for a
// blocked-time call attempt; `knockUnanswered()` is the same rule applied
// here.
//
// "Answer" and "Just talking" are BOTH real answers that lead to the same
// place: a real `CallScreen` join. lifecycle.ts's own `ANSWER_WORDS` names
// three words but specifies no technical difference between the first two
// — inventing an audio-only mode for "Just talking" that the TS source
// never described would be exactly the fabrication MASTERFILE §0 forbids.
// Both are honestly identical in behavior here; only the word she tapped
// differs.
//
// REACHABILITY, disclosed honestly: this screen has no live call site yet.
// A real `call_incoming` push carries only `kind`/`ref`/`callHandle` — no
// caller name (see push.ts's own `PushInput` — content-free by design) —
// so `from`/`who`/`displayName` below are supplied by whatever real caller
// eventually creates this screen, the same way `CallScreen`'s own existing
// call sites (child_home.dart, guardian_home.dart) already hardcode 'dad'/
// 'ivy' rather than resolving an arbitrary caller. `buildCallIncomingHandler`
// (this file, bottom) is real, tested wiring ready to pass as
// `PushChannel.onForegroundPointer` the day this client's root widget gains
// a `GlobalKey<NavigatorState>` — it doesn't have one yet, and neither does
// any server route actually dispatch a `call_incoming` push yet
// (`notify.ts`'s own header: `notifyDevices()` has zero HTTP call sites).
// Both are real, separate, already-disclosed gaps this pass does not close.
import 'dart:async';
import 'package:flutter/material.dart';
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'call_knock.dart';
import 'call_screen.dart';
import 'push_channel.dart' show PushPointer;

/// The on-screen reassurance line, read aloud verbatim below — a single
/// source of truth, same convention emergency_card.dart's own
/// `_cardSpokenText` header describes, so the spoken and displayed copy can
/// never drift apart.
const String _notNowHelperText = 'Not now is okay too.';

class CallKnockScreen extends StatefulWidget {
  const CallKnockScreen({
    super.key,
    required this.from,
    required this.who,
    required this.displayName,
    this.speak,
    this.onTimedOut,
  });

  /// Who's knocking, shown and spoken verbatim. See this file's own header
  /// for why this is a caller-supplied fact, not derived from push data.
  final String from;

  /// Passed straight through to [CallScreen] on Answer/Just talking — the
  /// same `who`/`displayName` shape that screen's own call sites already use.
  final String who;
  final String displayName;

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null reports
  /// itself honestly on tap, same posture as emergency_card.dart's own
  /// speaker button.
  final Future<void> Function(String text)? speak;

  /// Test seam only, called ADDITIONALLY when the real 90-second wait
  /// elapses unanswered (the real dismissal — a quiet pop — always happens
  /// regardless). No real caller needs this; it exists so a test can
  /// observe the timeout without inspecting navigator state directly.
  final VoidCallback? onTimedOut;

  @override
  State<CallKnockScreen> createState() => _CallKnockScreenState();
}

enum _KnockOutcome { waiting, notNow }

class _CallKnockScreenState extends State<CallKnockScreen> {
  _KnockOutcome _outcome = _KnockOutcome.waiting;
  Timer? _timeoutTimer;
  Timer? _notNowDismissTimer;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: knockWaitsSeconds), _handleTimeout);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _notNowDismissTimer?.cancel();
    super.dispose();
  }

  String get _promptText => '${widget.from} would like to talk.';

  /// Genuinely verbatim: the prompt, the on-screen reassurance line, and the
  /// three real button labels (`answerWords`) — nothing composed or
  /// paraphrased. v0.49.14 fix: this used to append a hand-written
  /// instructional sentence ("You can answer, say you are just talking, or
  /// say not now.") that appeared nowhere on screen, breaking the exact
  /// "never composes, always reads back verbatim" guarantee this feature
  /// exists to make — see a11y_speech.dart's own header and MASTERFILE
  /// §5.25.2/§8.8.5's "reads the prompt and every answer option back
  /// verbatim" claim, which the shipped code did not actually honor.
  String get _spokenText =>
      '$_promptText $_notNowHelperText ${answerWords.join(". ")}.';

  void _handleTimeout() {
    // knockUnanswered() — never reported as missed, declined, or ignored.
    // Quiet, not an error state: no setState into an alarming screen, just
    // leave whichever screen was underneath.
    widget.onTimedOut?.call();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _handleAnswer() {
    _timeoutTimer?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => CallScreen(who: widget.who, displayName: widget.displayName)));
  }

  void _handleNotNow() {
    _timeoutTimer?.cancel();
    setState(() => _outcome = _KnockOutcome.notNow);
    _notNowDismissTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _readAloud(BuildContext context) {
    if (widget.speak == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Read aloud — not built yet.'), duration: Duration(seconds: 2)));
      return;
    }
    // v0.49.14 fix: every other real speak() call site in this client
    // (emergency_card.dart, handover_notes.dart) routes through
    // admitSpeech() first — a structural guarantee that an autonomous
    // trigger is refused for real, not just by convention, the moment one
    // is ever passed here. This screen shipped without it; harmless today
    // (the only call site is this real tap), but the safety net every
    // sibling screen relies on was silently absent.
    if (admitSpeech(SpeechTrigger.tap) != null) return;
    widget.speak!(_spokenText);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Incoming'),
      actions: [
        IconButton(
          key: const Key('readAloudButton'),
          icon: const Icon(Icons.volume_up_outlined),
          tooltip: 'Read this aloud',
          onPressed: () => _readAloud(context),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _outcome == _KnockOutcome.notNow ? _notNowBody() : _waitingBody(),
        ),
      ),
    ),
  );

  Widget _waitingBody() => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.chat_bubble_outline, size: 40),
    const SizedBox(height: 16),
    Text(_promptText, textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text(_notNowHelperText, textAlign: TextAlign.center),
    const SizedBox(height: 32),
    ...answerWords.map((word) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 220,
        child: word == 'Not now'
            ? OutlinedButton(key: Key('answerButton_$word'),
                onPressed: _handleNotNow, child: Text(word))
            : FilledButton(key: Key('answerButton_$word'),
                onPressed: _handleAnswer, child: Text(word)),
      ),
    )),
  ]);

  Widget _notNowBody() => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.check_circle_outline, size: 40),
    const SizedBox(height: 16),
    Text(notNowOutcome.line, key: const Key('notNowLine'),
      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
  ]);
}

/// The real, tested integration point for `PushChannel.onForegroundPointer`
/// — see this file's own header for exactly what's real (this function) and
/// what isn't yet (a navigator key in the app root; a server route that
/// actually triggers a `call_incoming` push).
///
/// `displayName` is supplied by the caller, matching the same fixed-caller
/// assumption `CallScreen`'s own existing call sites already make — a real
/// push carries no caller identity to resolve one from (push.ts's own
/// content-free `PushInput` shape).
void Function(PushPointer pointer) buildCallIncomingHandler({
  required GlobalKey<NavigatorState> navigatorKey,
  required String from,
  required String who,
  required String displayName,
}) {
  return (PushPointer pointer) {
    if (pointer.kind != 'call_incoming') return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => CallKnockScreen(from: from, who: who, displayName: displayName)));
  };
}
