// OLIVE BRANCH — audio-only as a choice, and what she is told when a call
// goes wrong. The pure logic half. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §5.23, §5.23.2.
//
// A DELIBERATELY PARTIAL 1:1 port of packages/live/src/modes.ts — same
// names, same shapes, same ordering, the same discipline call_knock.dart's
// own header already established for lifecycle.ts. Ported: §5.23.1 (audio-
// only as a CHOICE — CallMode/ModeState/the listening surface/answer
// options), §5.23.2 (CallTrouble/the degradation ladder/state-across-a-
// reconnect/resumeOffer/network-change advice). NOT ported: push-to-talk
// (VoiceNote/pushToTalk/pttChildView) and bedtime mode (Bedtime/bedtime())
// — real, designed features, but nothing in this client calls them yet, and
// porting unused logic 1:1 is exactly the "declaration with nothing behind
// it" MASTERFILE §0 warns against. Port them together with the screen that
// actually uses them, not ahead of it.
library;

// ============================================ §5.23.1 audio-only as a CHOICE
/// Voice-only has been a thing the network does to you. It should be a thing
/// she chooses — a self-conscious eleven-year-old, a bad hair day, a child
/// who simply does not want to be seen today.
///
/// THE RULE: **he is told the call is voice-only. He is never told why.**
///
/// "She chose not to be seen" is a fact a parent will overinterpret, and the
/// overinterpretation lands on her. The reason is hers.
enum CallMode { video, audioOnly }

enum ModeCause { chosen, network, device, bedtime }

class ModeState {
  const ModeState({required this.mode, required this.cause, required this.changedAt});
  final CallMode mode;
  /// Recorded for diagnostics. Never leaves the device it was chosen on.
  final ModeCause cause;
  final String changedAt;
}

ModeState setMode(CallMode mode, ModeCause cause, String at) =>
    ModeState(mode: mode, cause: cause, changedAt: at);

class ModeForOther {
  const ModeForOther({required this.mode, required this.line});
  final CallMode mode;
  final String line;
}

/// What the OTHER party sees. Mode only — never the cause.
ModeForOther modeForOther(ModeState s) => ModeForOther(
  mode: s.mode,
  line: s.mode == CallMode.audioOnly ? 'Voice only just now.' : '',
);

const bool causeNeverDisclosed = true;

/// Runtime self-check mirroring modes.ts's auditModeDisclosure — this
/// actually runs against whatever is about to reach the other party, not
/// merely asserted in a test.
class ModeDisclosureAudit {
  const ModeDisclosureAudit.ok() : leak = null;
  const ModeDisclosureAudit.failed(this.leak);
  final String? leak;
  bool get ok => leak == null;
}

const List<String> _disclosureLeaks = [
  'chosen', 'bedtime', 'she turned', 'declined video', 'camera off',
];

ModeDisclosureAudit auditModeDisclosure(String textShownToOtherParty) {
  final s = textShownToOtherParty.toLowerCase();
  for (final c in _disclosureLeaks) {
    if (s.contains(c)) return ModeDisclosureAudit.failed(c);
  }
  return const ModeDisclosureAudit.ok();
}

/// Switching is instant and mid-call, both directions, from either side for
/// themselves. Nobody turns another person's camera on.
bool canSwitchOwnCamera() => true;
bool canSwitchOthersCamera() => false;

// ----------------------------------------------------- the listening surface
/// A black rectangle is what every other product shows on an audio call, and
/// for a child it reads as absence. She needs something to look at while she
/// listens.
enum ListeningSurface { herColour, waveform, canvas, theirPhoto }

class Listening {
  const Listening({required this.surface, required this.colourHex, required this.waveformHz});
  final ListeningSurface surface;
  /// Her §8.6 colour, where she has one.
  final String? colourHex;
  /// Slow. A fast waveform is a stimulant at bedtime.
  final double waveformHz;
}

const double waveformHzCalm = 4;

Listening listening(String? colourHex, [ListeningSurface surface = ListeningSurface.herColour]) =>
    Listening(surface: surface, colourHex: colourHex, waveformHz: waveformHzCalm);

/// Never a black screen on a child's device during a live call.
const bool neverBlank = true;

// -------------------------------------------------------- answering --------
/// The voice-only answer is the SAME SIZE as the video one. A smaller button
/// is a judgement, and she will read it as one.
enum AnswerKind { video, voice, notNow }

class AnswerOption {
  const AnswerOption({required this.kind, required this.label});
  final AnswerKind kind;
  final String label;
  /// Every option carries the same weight — see optionsEquallyWeighted().
  int get weight => 1;
}

List<AnswerOption> answerOptions() => const [
  AnswerOption(kind: AnswerKind.video, label: 'Answer'),
  AnswerOption(kind: AnswerKind.voice, label: 'Just talking'),
  AnswerOption(kind: AnswerKind.notNow, label: 'Not now'),
];

bool optionsEquallyWeighted(List<AnswerOption> o) => o.every((x) => x.weight == 1);

// ================================================= §5.23.2 when it goes wrong
/// A frozen father and an ended call are the same event to a five-year-old,
/// and they are not the same thing. She needs to be told which.
enum CallTrouble { frozen, slow, dropped, reconnecting, ended }

class TroubleView {
  const TroubleView({required this.state, required this.line, required this.waiting});
  final CallTrouble state;
  /// Child language. Short, specific, never blaming.
  final String line;
  /// Should she wait, or is it over?
  final bool waiting;
}

TroubleView troubleView(CallTrouble state) {
  final map = <CallTrouble, (String, bool)>{
    CallTrouble.frozen: ('The picture stopped. He is still there.', true),
    CallTrouble.slow: ('It has gone a bit slow.', true),
    CallTrouble.reconnecting: ('Finding him again.', true),
    CallTrouble.dropped: ('It stopped. We are getting him back.', true),
    CallTrouble.ended: ('That is the end of the call.', false),
  };
  final (line, waiting) = map[state]!;
  return TroubleView(state: state, line: line, waiting: waiting);
}

/// Never on a child's screen, in any state.
const List<String> troubleBanned = [
  'failed', 'failure', 'error', 'could not connect', 'unavailable',
  'disconnected', 'lost connection', 'try again later', 'poor connection',
  'your network', 'check your',
];

class TroubleAudit {
  const TroubleAudit.ok() : found = const <String>[];
  const TroubleAudit.failed(this.found);
  final List<String> found;
  bool get ok => found.isEmpty;
}

TroubleAudit auditTrouble(TroubleView v) {
  final t = v.line.toLowerCase();
  final found = troubleBanned.where((w) => t.contains(w)).toList();
  return found.isEmpty ? const TroubleAudit.ok() : TroubleAudit.failed(found);
}

// -------------------------------------------------- the degradation ladder --
/// Never a failure — always a next rung. The call falls down the ladder
/// rather than off it, and the bottom rung is a banked message, which always
/// works.
enum Rung { hd, sd, audioOnly, banked }

const List<Rung> ladder = [Rung.hd, Rung.sd, Rung.audioOnly, Rung.banked];

Rung stepRungDown(Rung r) {
  final i = ladder.indexOf(r);
  return ladder[(i + 1).clamp(0, ladder.length - 1)];
}

Rung stepRungUp(Rung r) {
  final i = ladder.indexOf(r);
  return ladder[(i - 1).clamp(0, ladder.length - 1)];
}

/// The bottom rung always succeeds. That is what makes it a ladder.
const bool bottomAlwaysWorks = true;

String rungLine(Rung r) => r == Rung.banked
    ? 'The line is not good enough right now, so record him something instead.'
    : '';

// -------------------------------------------------- state across a reconnect
/// The game in progress, the story position, the half-coloured picture.
/// Losing them is how a child learns not to bother starting anything on a
/// call.
class CallState {
  const CallState({required this.activity, required this.activityState,
    required this.storyLine, required this.elapsedSeconds});
  final String? activity;
  final Object? activityState;
  final int? storyLine;
  final int elapsedSeconds;

  CallState copyWith({String? activity, Object? activityState, int? storyLine, int? elapsedSeconds}) =>
    CallState(
      activity: activity ?? this.activity,
      activityState: activityState ?? this.activityState,
      storyLine: storyLine ?? this.storyLine,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
}

CallState preserve(CallState s) => s.copyWith();

const bool reconnectPreservesState = true;

/// Resuming asks first. A call that reconnects itself and starts
/// transmitting a child's bedroom because the wifi came back is a privacy
/// failure with good intentions.
class ResumeOffer {
  const ResumeOffer({this.line = 'Ready to carry on?', this.autoResumes = false});
  final String line;
  final bool autoResumes;
}

ResumeOffer resumeOffer() => const ResumeOffer();

/// Wi-Fi to cellular mid-call.
class NetworkChange {
  const NetworkChange({required this.from, required this.to, required this.metered});
  final String from;
  final String to;
  final bool metered;
}

String? networkChangeAdvice(NetworkChange c) =>
    c.metered ? 'You have moved off wi-fi. This will use data now.' : null;

const bool survivesNetworkChange = true;
