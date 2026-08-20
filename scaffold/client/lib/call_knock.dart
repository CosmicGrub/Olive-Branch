// OLIVE BRANCH — knocking, not ringing. The pure logic half. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline — manually built
// and run via `flutter analyze` / `flutter test` this session). MASTERFILE
// §5.25.2.
//
// A DELIBERATELY PARTIAL 1:1 port of packages/live/src/lifecycle.ts — only
// its §5.25.2 "knocking" section (`Knock`/`knock()`/`knockUnanswered()`/
// `ANSWER_WORDS`/`ANSWER_BANNED`/`auditAnswerWords()`/`notNowOutcome()`).
// The rest of that file — §5.25.1 Fold posture-change, §5.25.3 device
// handoff, §5.25.4 both-free windows, and the code-comment-only "§5.25.5"
// waiting room (no matching MASTERFILE section exists for it — a real,
// separately-scoped gap, not this file's problem to solve) — is not ported
// here, because nothing in this client calls it. Porting unused logic 1:1
// is exactly the "declaration with nothing behind it" MASTERFILE §0 warns
// against.
//
// §5.25.2's own rule, carried forward unchanged: **"Not now" is a real
// answer and is not a decline.** A ring demands answering; a knock waits
// ninety seconds, never escalates, and becomes a banked message — he is
// told "she did not come to it," never that she declined. `call_knock_screen
// .dart` is the real UI built on top of this file.
library;

/// How this call attempt is presented — a knock waits, a ring demands.
/// This client only ever builds knocks (see call_knock_screen.dart's own
/// header for why); the type is ported anyway, matching lifecycle.ts's own
/// `Arrival` union, since a future ring-style surface would need it.
enum Arrival { knock, ring }

class Knock {
  const Knock({required this.from, required this.at, this.waitsSeconds = knockWaitsSeconds});
  final String from;
  final String at;

  /// How long it waits before quietly becoming a banked message.
  final int waitsSeconds;

  /// Nothing is escalated, ever.
  bool get escalates => false;
}

const int knockWaitsSeconds = 90;

Knock knock(String from, String at) => Knock(from: from, at: at);

class KnockUnanswered {
  const KnockUnanswered();
  String get becomes => 'banked_message';

  /// Never reported as missed, declined or ignored — §9.13.4 already
  /// settled that she is not shown a missed call, and this is the same
  /// rule at the other end of the wire.
  String get toldToSender =>
      'She did not come to it. It is saved for her — she will see it '
      'when she next opens Olive.';
}

const KnockUnanswered knockUnanswered = KnockUnanswered();

/// "Not now" is a real answer and it is not a decline.
const List<String> answerWords = <String>['Answer', 'Just talking', 'Not now'];

const List<String> answerBanned = <String>['decline', 'reject', 'refuse', 'dismiss', 'ignore'];

class AnswerAudit {
  const AnswerAudit.ok() : found = const <String>[];
  const AnswerAudit.failed(this.found);
  final List<String> found;
  bool get ok => found.isEmpty;
}

AnswerAudit auditAnswerWords(List<String> words) {
  final found = <String>[];
  for (final w in words) {
    final lower = w.toLowerCase();
    if (answerBanned.any((b) => lower.contains(b))) found.add(w);
  }
  return found.isEmpty ? const AnswerAudit.ok() : AnswerAudit.failed(found);
}

class NotNowOutcome {
  const NotNowOutcome();
  String get line => 'Alright. He knows you are busy.';
  String get senderTold => 'She is busy just now. Record her something?';
}

const NotNowOutcome notNowOutcome = NotNowOutcome();
