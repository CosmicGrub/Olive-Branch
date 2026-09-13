// OLIVE BRANCH — offline outbox, the pure-logic half. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §5.22.
//
// A DELIBERATELY PARTIAL 1:1 semantic port of packages/offline/src/
// offline.ts — same names, same shapes, same ordering, so the two stay
// auditable side by side, the same discipline a11y_speech.dart already
// applies porting a11y.ts and device_channels.dart applies porting
// devices.ts. Partial on purpose, matching device_channels.dart's own stated
// reasoning: offline.ts also exports the §5.22.2 conflict-resolution half
// (Actor / Edit / resolve / conflictNotice), ported nowhere here, because no
// real Dart caller needs it yet — the day one does, port it then, against
// that caller's actual need, rather than carrying a declaration with nothing
// behind it (MASTERFILE §0).
//
// THE CASE THIS EXISTS FOR (offline.ts's own header, verbatim reasoning):
// she is in the back of a car with no signal, and has just made something
// for her father. Every previous increment assumed a network — without this
// the thing she made is lost at exactly the moment she most wanted to send
// it.
//
// receipt_screen.dart is this port's one real caller today (its "Send one
// back" video message, OutboxKind.message) — see that file's own header for
// exactly how it distinguishes queued/in-flight/confirmed-sent/failed-will-
// retry using the functions below, rather than inventing a second, parallel
// state machine of its own.
library;

enum OutboxKind { show, drawing, message, voice, colouring, journal, listItem, storyStar, ping }

/// The wire string offline.ts's own OutboxKind union uses — kept for the day
/// a real caller needs to round-trip one of these server-side; unused today,
/// same honest-gap posture device_channels.dart documents for its own
/// currently-unreachable branches.
extension OutboxKindWire on OutboxKind {
  String get wireValue => switch (this) {
        OutboxKind.show => 'show',
        OutboxKind.drawing => 'drawing',
        OutboxKind.message => 'message',
        OutboxKind.voice => 'voice',
        OutboxKind.colouring => 'colouring',
        OutboxKind.journal => 'journal',
        OutboxKind.listItem => 'list_item',
        OutboxKind.storyStar => 'story_star',
        OutboxKind.ping => 'ping',
      };
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.payload,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final OutboxKind kind;
  final DateTime createdAt;
  final Object? payload;
  final int attempts;
  final String? lastError;

  OutboxItem _withFailure(String error) => OutboxItem(
      id: id, kind: kind, createdAt: createdAt, payload: payload,
      attempts: attempts + 1, lastError: error);
}

/// Some things are meaningless late and must NOT be queued.
///
/// A ping means "I am thinking of you right now." Delivering it four hours
/// later, out of a tunnel, is a small lie — so it is dropped rather than
/// banked, and she is never told it failed. 1:1 with offline.ts's own
/// NOT_QUEUEABLE.
const List<OutboxKind> notQueueable = <OutboxKind>[OutboxKind.ping];
const int maxAttempts = 8;

class EnqueueResult {
  const EnqueueResult(this.outbox, this.dropped);
  final List<OutboxItem> outbox;
  final bool dropped;
}

EnqueueResult enqueue(List<OutboxItem> outbox, OutboxItem item) {
  if (notQueueable.contains(item.kind)) return EnqueueResult(outbox, true);
  return EnqueueResult(<OutboxItem>[...outbox, item], false);
}

/// Oldest first — what she made first should arrive first.
OutboxItem? nextToSend(List<OutboxItem> outbox) {
  final List<OutboxItem> eligible = outbox.where((OutboxItem i) => i.attempts < maxAttempts).toList()
    ..sort((OutboxItem a, OutboxItem b) => a.createdAt.compareTo(b.createdAt));
  return eligible.isEmpty ? null : eligible.first;
}

List<OutboxItem> recordFailure(List<OutboxItem> outbox, String id, String error) => <OutboxItem>[
      for (final OutboxItem i in outbox) i.id == id ? i._withFailure(error) : i,
    ];

/// Milliseconds, 1:1 with offline.ts's own backoffMs — doubling per attempt,
/// capped at six hours. Returned as a plain int (not a Duration) to keep this
/// the same literal shape as the TS original; a caller converts.
int backoffMs(int attempts) {
  final int doubled = 60000 * (1 << attempts.clamp(0, 20));
  const int sixHours = 6 * 60 * 60000;
  return doubled < sixHours ? doubled : sixHours;
}

List<OutboxItem> sent(List<OutboxItem> outbox, String id) =>
    outbox.where((OutboxItem i) => i.id != id).toList();

class ChildOfflineView {
  const ChildOfflineView({required this.line, required this.anythingWaiting});
  final String line;
  final bool anythingWaiting;
}

/// What SHE sees while offline. Deliberately not a queue.
///
/// A five-year-old shown "3 pending, 2 failed" has been handed an
/// engineering problem she cannot solve. She is told her thing is safe, and
/// nothing else. 1:1 with offline.ts's own offlineChildView.
ChildOfflineView offlineChildView(List<OutboxItem> outbox) => ChildOfflineView(
      anythingWaiting: outbox.isNotEmpty,
      line: outbox.isEmpty ? '' : 'It will go when you have internet again. It is safe.',
    );

/// 1:1 with offline.ts's own OFFLINE_FORBIDDEN — never shown to her, even by
/// a future editing mistake in a caller.
const List<String> offlineForbidden = <String>[
  'pending', 'queue', 'failed', 'retry', 'attempts', 'error', 'stuck', 'unsent', 'count',
];

/// Runtime self-check, mirroring busy_fork.dart's auditBusyFork and
/// degradation_banner.dart's auditNotice — runs on the exact string a caller
/// is about to render to her, not merely asserted in a test.
bool auditChildOfflineCopy(String line) {
  final String t = line.toLowerCase();
  return !offlineForbidden.any(t.contains);
}
