// OLIVE BRANCH — child shell, message receipt. No longer UNVERIFIED — verified
// by CI (`flutter analyze` and `flutter test` run for real in tools/verify.sh
// and .github/workflows/verify.yml). MASTERFILE §8.2.4, §9.5. Renders MARKUP
// screen 'receipt': "Watched at 7:04 AM her time — before school." Her frame
// first, always.
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
// possessive ("Ivy's time") instead of "her time".
//
// "Send one back" really records a video (image_picker's pickVideo, camera),
// really uploads it (api_client.dart's uploadMedia) and really records the
// message against the storage key the server returned (sendMessage). What
// makes it safe to promise "Kept safe" is that the work is not done by this
// screen at all (MASTERFILE §7.19, §5.22):
//
//   1. The moment she finishes recording, send_back_outbox.dart copies the
//      file into the app's own storage and writes one row for it (path,
//      length, and later the storage key) to her on-device outbox. "Kept
//      safe" is drawn only after that write has succeeded and read back.
//      If it did not, she gets the one calm try-again line instead, and no
//      promise was made.
//   2. The row is sent by the queue, not by this State. Closing this screen
//      (or the app) mid-retry loses nothing: her home drains the queue when
//      it loads and when the app comes back, and the Messages screen drains
//      it each time it asks again. The failure time is stored with the row,
//      so a cold start inside the backoff window spends no attempt.
//   3. A server that answers "no" (a 4xx that will never change) is told to
//      her as the same calm line as everything else; any other trouble keeps
//      the recording and tries again later. The detail (status code, error,
//      exception) goes to debugPrint only: she never reads one.
//
// A call site without a live session ([baseUrl]/[childId]/[sessionToken] all
// supplied) gets the same calm line: there is nowhere to keep or send it.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'calendar_day_logic.dart';
import 'offline_outbox.dart' as outbox;
import 'send_back_outbox.dart';

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
    this.sendBackQueue,
  });

  final String childName;
  final String senderName;
  /// Already formatted, e.g. "7:04 AM" — her frame, resolved by the caller.
  final String watchedAtLabel;
  /// e.g. 'before_school'. Nullable: a receipt is still honest with no
  /// day-part context, it just drops the "— before school" clause.
  final String? dayPartKind;

  /// Live wiring for "Send one back". All three must be supplied together
  /// for a real send to be attempted.
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
  /// Injectable for tests. Defaults to this device's queue for the child.
  final SendBackQueue? sendBackQueue;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  _SendState _state = _SendState.idle;

  /// While this screen is open it asks again when the backoff is over. When it
  /// is closed this timer goes with it, and the queue (not this State) carries
  /// on: see the file header.
  Timer? _retryTimer;

  bool get _isLive =>
      widget.baseUrl != null && widget.childId != null && widget.sessionToken != null;

  SendBackQueue get _queue => widget.sendBackQueue ?? SendBackQueue.forChild(widget.childId!);

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// The one failure state she ever sees. The cause is only logged.
  void _fail(Object why) {
    debugPrint('[olive.receipt] send one back did not go: $why');
    if (!mounted) return;
    setState(() => _state = _SendState.error);
  }

  Future<void> _sendOneBack() async {
    if (!_isLive) {
      _fail('no live session on this screen');
      return;
    }

    setState(() => _state = _SendState.busy);
    final DateTime started = DateTime.now();
    // The picker call is deliberately inside its OWN try/catch: image_picker's
    // pickVideo() can throw for real reasons (camera already in use, a denied
    // permission, a hardware fault) that have nothing to do with connectivity.
    // Letting that propagate would leave [_state] stuck at busy forever.
    final XFile? file;
    try {
      final VideoPicker pick = widget.pickVideo ?? _defaultPickVideo;
      file = await pick();
    } catch (e) {
      _fail(e);
      return;
    }
    if (file == null) {
      // The user backed out of the camera — not an error, just back to idle.
      if (!mounted) return;
      setState(() => _state = _SendState.idle);
      return;
    }

    // Real elapsed wall-clock time spent inside the camera picker — an
    // honest approximation of the clip length (no video-metadata probe exists
    // in this codebase). Floored at 1ms only so a picker that returns
    // instantly (every injected test fake) never trips captureMessage()'s own
    // `empty_recording` guard.
    final int elapsedMs = DateTime.now().difference(started).inMilliseconds;
    final int durationMs = elapsedMs > 0 ? elapsedMs : 1;

    // Durable first. Nothing below is promised to her until this returns.
    final SendBackQueue queue = _queue;
    final String id;
    try {
      id = (await queue.keep(file, durationMs)).id;
    } catch (e) {
      _fail(e);
      return;
    }
    await _attempt(queue, id);
  }

  /// One go at sending, by the queue (which outlives this screen), then
  /// whatever the queue now says about this recording.
  Future<void> _attempt(SendBackQueue queue, String id, {bool ignoreBackoff = false}) async {
    await drainSendBacks(
      baseUrl: widget.baseUrl!,
      childId: widget.childId!,
      sessionToken: widget.sessionToken!,
      httpClient: widget.httpClient,
      queue: queue,
      backoff: widget.retryBackoff,
      ignoreBackoff: ignoreBackoff,
    );
    final SendBackReport report = await queue.report(id);
    if (!mounted) return;
    switch (report.status) {
      case SendBackStatus.sent:
        setState(() => _state = _SendState.sent);
      case SendBackStatus.refused:
        _fail('the server refused it, or it was gone');
      case SendBackStatus.waiting:
        setState(() => _state = _SendState.retrying);
        final Duration wait = (widget.retryBackoff ?? sendBackBackoff)(report.attempts);
        _retryTimer?.cancel();
        _retryTimer = Timer(wait, () {
          if (!mounted) return;
          setState(() => _state = _SendState.busy);
          // Just waited out its own backoff, so asking now is the point.
          unawaited(_attempt(queue, id, ignoreBackoff: true));
        });
    }
  }

  Widget _sendButton(BuildContext context) {
    switch (_state) {
      case _SendState.idle:
        return SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
          onPressed: _sendOneBack,
          icon: const Icon(Icons.videocam_outlined),
          label: const Text('Send one back')));
      case _SendState.busy:
        return SizedBox(width: double.infinity, height: 52, child: FilledButton(
          onPressed: null,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary)),
            const SizedBox(width: 12),
            const Text('Sending…'),
          ])));
      case _SendState.retrying:
        // Drawn only once the recording is really on the device and in the
        // outbox. The one honest sentence offline_outbox.dart's
        // offlineChildView allows — audited before paint so a banned word can
        // never reach her, even by a future editing mistake here.
        const String line = 'It will go when you have internet again. It is safe.';
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
        // A picture, one calm line and a button: never a status code, an
        // exception or a word about servers.
        assert(auditSendBackCopy(kSendBackTryAgainLine),
            'try-again copy shown to her must never leak engineering vocabulary');
        return Column(children: <Widget>[
          Icon(Icons.cloud_off_outlined, size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(kSendBackTryAgainLine,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
            onPressed: _sendOneBack,
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Try again'))),
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
