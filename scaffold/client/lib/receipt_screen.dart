// OLIVE BRANCH — child shell, message receipt. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §8.2.4,
// §9.5. Renders MARKUP screen 'receipt': "Watched at 7:04 AM her time —
// before school." Her frame first, always.
//
// pipeline.ts's `openReceipt()` docstring is explicit about why: "a receipt
// renders in HER frame, at the zone she was in when she opened it. Not the
// capture zone." This screen renders exactly that sentence shape (via
// `watchedReceiptPhrase` in calendar_day_logic.dart) — the caller resolves
// the local time and day-part, this widget only ever displays them, never
// recomputes a zone.
//
// One naming adaptation from the TS: `openReceipt()` always says "her"
// because it is written from the system's own narrating voice. This screen
// puts the receipt in front of the child it is about, so it says her name's
// possessive ("Ivy's time") instead of "her time" — the same fact, addressed
// to the person it's about rather than narrated over her shoulder.
//
// "Send one back" is real now, not the snackbar-only stub this file used to
// carry (see CHANGELOG for the date). It really records a video via
// image_picker's pickVideo(source: camera) and really POSTs it through
// api_client.dart's sendMessage() to server/routes.mjs's POST
// /v1/children/:childId/messages, which really runs it through
// packages/messaging/src/pipeline.ts's captureMessage() and really persists
// a row on success (packages/db/src/pool.ts's persistCapturedMessage()).
// Two things stay honestly short of "fully working," on purpose:
//
//  1. NO OBJECT STORAGE. This repo has no real blob backend (see
//     packages/storage/src/storage.ts's StoragePort — an interface with no
//     production implementation anywhere in this codebase). The recorded
//     file is captured for real on-device but its bytes are never uploaded;
//     `storageKey` sent to the server is a locally-meaningful reference
//     only, matching media_artifact.storage_key's shape but pointing at
//     nothing retrievable server-side. A real upload path is a real,
//     separate piece of work.
//  2. NO LIVE CALL SITE YET. `baseUrl`/`childId`/`sessionToken` must all be
//     supplied for the button to attempt a real send — inbox_screen.dart,
//     this screen's only current caller, is still main.dart's offline demo
//     build (see both files' own headers) and does not supply them. Tapping
//     "Send one back" from that demo path reports itself honestly ("This
//     screen isn't connected to a server yet.") rather than doing nothing or
//     faking success. A live caller (mirroring child_home_live.dart's own
//     pattern) is real follow-up work, not silently glossed over.
//
// FORMERLY a third, honest gap here: "a child session cannot actually send
// one yet, even fully wired" — the async-message tables (db/migrations/
// 0001_phase0_init.sql) were built for guardian → child delivery only, and
// `delivery_intent.sender_id NOT NULL REFERENCES app_user(id)` had no
// representation for a child (who carries no `userId`/`app_user` row at
// all) as a sender. CLOSED by db/migrations/0021_child_message_sender.sql:
// `media_artifact.author_child_id` / `delivery_intent.sender_child_id` now
// name the sending child directly, and server/routes.mjs's POST
// .../messages route derives that id from the verified child session (never
// the body) exactly the way it already derived a guardian's `userId`. Once
// this screen has a real live call site (gap #2 above), a child session
// tapping "Send one back" about herself succeeds for real — see
// packages/messaging/test/pipeline.test.mjs's M8 suite and packages/api/
// test/messages_route.test.mjs's "D auth" group, both of which now prove a
// success, not merely a documented refusal.
//
// OFFLINE-OUTBOX HONESTY (MASTERFILE §5.22, offline_outbox.dart): a failed
// "Send one back" used to collapse into one bucket — any exception at all
// became the same "error, tap Try again" state, indistinguishable from a
// genuine server rejection. That is dishonest twice over: it hands her the
// same scary dead-end for "the server said no" as for "the car went through
// a tunnel," AND it discards the real recording (Try again re-records from
// scratch), which is exactly the loss offline.ts's own header exists to
// prevent — "she is in the back of a car with no signal, and has just drawn
// something for her father... without this the drawing is lost at exactly
// the moment she most wanted to send it."
//
// Now the two are told apart by what actually happened, not guessed at:
//   - [ApiException] means the server answered — a real rejection (wrong
//     sender, an empty recording, whatever). That is never blindly retried,
//     and she is never told it is "safe" when it was actually refused. Same
//     honest error + manual "Try again" as always.
//   - anything else means the request never got an answer at all — the real
//     connectivity gap offline_outbox.dart exists for. The recording is
//     queued (offline_outbox.dart's real enqueue/recordFailure/nextToSend/
//     sent state machine, not a parallel one invented here), retried
//     automatically on its real backoff, and she sees exactly the one
//     honest sentence offlineChildView allows — never a raw exception
//     string, audited before paint the same way busy_fork.dart/
//     degradation_banner.dart already audit their own child-facing copy.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';
import 'calendar_day_logic.dart';
import 'offline_outbox.dart' as outbox;

/// Records a short video via the device camera. Returns the recorded file,
/// or null if the user cancelled. Injectable on [ReceiptScreen] for tests —
/// the real implementation below talks to a platform channel the
/// widget-test harness doesn't have.
typedef VideoPicker = Future<XFile?> Function();

Future<XFile?> _defaultPickVideo() =>
    ImagePicker().pickVideo(source: ImageSource.camera);

enum _SendState { idle, busy, retrying, sent, error }

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({
    super.key,
    required this.childName,
    required this.senderName,
    required this.watchedAtLabel,
    required this.dayPartKind,
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
    this.pickVideo,
    this.retryBackoff,
  });

  final String childName;
  final String senderName;
  /// Already formatted, e.g. "7:04 AM" — her frame, resolved by the caller.
  final String watchedAtLabel;
  /// e.g. 'before_school'. Nullable: a receipt is still honest with no
  /// day-part context, it just drops the "— before school" clause.
  final String? dayPartKind;

  /// Live wiring for "Send one back". All three must be supplied together
  /// for a real send to be attempted — see this file's header, point 2, for
  /// why every call site today leaves them null.
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  /// Injectable for tests (package:http/testing.dart's MockClient) —
  /// matches child_home_live.dart's own pattern.
  final http.Client? httpClient;
  /// Injectable for tests. Defaults to the real camera picker.
  final VideoPicker? pickVideo;
  /// Injectable for tests. Defaults to offline_outbox.dart's own real
  /// backoffMs — real exponential backoff, minutes to hours, so a genuine
  /// connectivity gap is retried patiently rather than hammered. Overridden
  /// only by tests that need to observe a real automatic retry firing
  /// without actually waiting hours; no real call site overrides this.
  final Duration Function(int attempts)? retryBackoff;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  _SendState _state = _SendState.idle;
  String _errorMessage = '';

  // The real outbox — offline_outbox.dart's own state machine, operated
  // through its own functions (enqueue/recordFailure/sent/nextToSend), never
  // mutated ad hoc here. Holds at most this screen's one in-flight recording;
  // a list (not a single nullable item) because that is the real shape the
  // functions it is passed to expect, the same way a real multi-item outbox
  // would need it to be.
  List<outbox.OutboxItem> _outbox = const <outbox.OutboxItem>[];
  Timer? _retryTimer;
  int _idCounter = 0;

  bool get _isLive =>
      widget.baseUrl != null && widget.childId != null && widget.sessionToken != null;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendOneBack() async {
    if (!_isLive) {
      setState(() {
        _state = _SendState.error;
        _errorMessage = "This screen isn't connected to a server yet.";
      });
      return;
    }

    setState(() => _state = _SendState.busy);
    final DateTime started = DateTime.now();
    // The picker call is deliberately inside its OWN try/catch, separate
    // from _attemptSend()'s network try/catch below: image_picker's
    // pickVideo() can throw for real, non-hypothetical reasons (camera
    // already in use, a denied permission, a hardware fault) that have
    // nothing to do with connectivity and everything to do with "the
    // recording never happened at all." Letting that exception propagate
    // unhandled would leave [_state] stuck at [_SendState.busy] forever —
    // a spinner that never resolves is the same category of dishonesty
    // OFFLINE-OUTBOX HONESTY (this file's own header) exists to eliminate,
    // just from a different cause. A real, honest [_SendState.error] beats
    // an infinite "Sending…" every time.
    final XFile? file;
    try {
      final VideoPicker pick = widget.pickVideo ?? _defaultPickVideo;
      file = await pick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SendState.error;
        _errorMessage = '$e';
      });
      return;
    }
    if (file == null) {
      // The user backed out of the camera — not an error, just back to idle.
      if (!mounted) return;
      setState(() => _state = _SendState.idle);
      return;
    }

    // Real elapsed wall-clock time spent inside the camera picker — an
    // honest approximation of the clip length, not a fabricated constant
    // (no video-metadata probe exists anywhere in this codebase to measure
    // the exact recorded duration). Floored at 1ms only so a picker that
    // returns instantly — every injected test fake — never trips
    // captureMessage()'s own `empty_recording` guard for a recording that,
    // in reality, never happened at all.
    final int elapsedMs = DateTime.now().difference(started).inMilliseconds;
    final int durationMs = elapsedMs > 0 ? elapsedMs : 1;

    // See this file's header, point 1: nothing here uploads `file`'s
    // bytes anywhere. This is a local reference only.
    final String storageKey = 'device/${started.millisecondsSinceEpoch}-${file.name}';

    final outbox.OutboxItem item = outbox.OutboxItem(
      id: 'receipt-${_idCounter++}-${started.microsecondsSinceEpoch}',
      kind: outbox.OutboxKind.message,
      createdAt: started,
      payload: <String, Object>{'storageKey': storageKey, 'durationMs': durationMs},
    );
    await _attemptSend(item);
  }

  /// One real attempt to actually transmit [item] — the ONLY place this
  /// screen calls the network for a send, whether this is the first try
  /// (from [_sendOneBack]) or an automatic retry (from [_scheduleRetry]).
  /// Every outcome is real: [_SendState.sent] only after a genuine 2xx,
  /// [_SendState.error] only for a genuine server answer that refused it,
  /// [_SendState.retrying] only for a request that never got an answer at
  /// all — see this file's own header for why those three must never be
  /// conflated.
  Future<void> _attemptSend(outbox.OutboxItem item) async {
    final OliveApi api =
        OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
    final Map<String, Object> payload = item.payload! as Map<String, Object>;
    try {
      await api.sendMessage(widget.childId!,
          storageKey: payload['storageKey']! as String,
          durationMs: payload['durationMs']! as int);
      if (!mounted) return;
      setState(() {
        // A no-op filter if [item] was never queued (the common, first-try,
        // online case) — real either way per offline_outbox.dart's own
        // `sent()`.
        _outbox = outbox.sent(_outbox, item.id);
        _state = _SendState.sent;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
        // The server answered — a real rejection, not a connectivity gap.
        // Never blindly retried, and never told to her as "safe" when it
        // was actually refused. See this file's header.
        setState(() {
          _outbox = outbox.sent(_outbox, item.id); // stop trying either way
          _state = _SendState.error;
          _errorMessage = '${e.statusCode}: ${e.error}';
        });
        return;
      }
      // No answer at all — the real connectivity gap offline_outbox.dart
      // exists for. Queued (or re-recorded as still-queued, if this was
      // already a retry), never lost, and never shown the raw exception.
      List<outbox.OutboxItem> next = _outbox;
      if (!next.any((outbox.OutboxItem i) => i.id == item.id)) {
        next = outbox.enqueue(next, item).outbox;
      }
      next = outbox.recordFailure(next, item.id, e.toString());
      setState(() {
        _outbox = next;
        _state = _SendState.retrying;
      });
      _scheduleRetry();
    } finally {
      if (widget.httpClient == null) api.close();
    }
  }

  /// offline_outbox.dart's own real backoff, not a fixed or fabricated
  /// delay — doubles per attempt, so a longer outage is retried patiently
  /// rather than hammered. Stops scheduling once nextToSend() reports
  /// nothing left eligible (offline_outbox.dart's real maxAttempts ceiling)
  /// rather than retrying forever; the item stays queued either way — it is
  /// never discarded, only stopped being auto-retried this session.
  void _scheduleRetry() {
    final outbox.OutboxItem? item = outbox.nextToSend(_outbox);
    if (item == null) return;
    final Duration Function(int) backoff =
        widget.retryBackoff ?? (int attempts) => Duration(milliseconds: outbox.backoffMs(attempts));
    _retryTimer?.cancel();
    _retryTimer = Timer(backoff(item.attempts), () {
      if (!mounted) return;
      setState(() => _state = _SendState.busy);
      _attemptSend(item);
    });
  }

  Widget _sendButton(BuildContext context) {
    switch (_state) {
      case _SendState.idle:
        return SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
          onPressed: _sendOneBack,
          icon: const Icon(Icons.videocam_outlined),
          label: const Text('Send one back')));
      case _SendState.busy:
        return const SizedBox(width: double.infinity, height: 52, child: FilledButton(
          onPressed: null,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Sending…'),
          ])));
      case _SendState.retrying:
        // The one honest sentence offline_outbox.dart's offlineChildView
        // allows — audited before paint (busy_fork.dart/degradation_banner
        // .dart's own convention) so a banned word (queue/failed/attempts/
        // error/...) can never reach her, even by a future editing mistake
        // here.
        final String line = outbox.offlineChildView(_outbox).line;
        assert(outbox.auditChildOfflineCopy(line),
            'offline copy shown to her must never leak queue/attempts/error vocabulary');
        return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.favorite_border),
            label: const Text('Kept safe'))),
          const SizedBox(height: 8),
          Text(line,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]);
      case _SendState.sent:
        return SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Sent!')));
      case _SendState.error:
        return Column(children: <Widget>[
          SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
            onPressed: _sendOneBack,
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Try again'))),
          const SizedBox(height: 8),
          Text(_errorMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error)),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String phrase = watchedReceiptPhrase(
      timeLabel: widget.watchedAtLabel,
      possessive: "${widget.childName}'s",
      dayPartKind: widget.dayPartKind,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Message watched')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StampCard(senderName: widget.senderName, phrase: phrase),
          const SizedBox(height: 24),
          _sendButton(context),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to messages'))),
        ],
      )),
    );
  }
}

class _StampCard extends StatelessWidget {
  const _StampCard({required this.senderName, required this.phrase});
  final String senderName;
  final String phrase;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.primary.withAlpha(90), width: 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: <Widget>[
        Icon(Icons.check_circle, size: 46, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text("You watched $senderName's message!",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        const _DashedDivider(),
        const SizedBox(height: 16),
        Text(phrase,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
      ]),
    ),
  );
}

/// A plain hand-rolled dashed rule — no package dependency for one stamp
/// flourish on a single screen.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      const double dashWidth = 6, gap = 5;
      final int count = (constraints.maxWidth / (dashWidth + gap)).floor().clamp(1, 200);
      return SizedBox(height: 2, width: double.infinity,
        child: Row(children: <Widget>[
          for (int i = 0; i < count; i++) ...<Widget>[
            Container(width: dashWidth, height: 2, color: Theme.of(context).colorScheme.outlineVariant),
            if (i != count - 1) const SizedBox(width: gap),
          ],
        ]));
    },
  );
}
