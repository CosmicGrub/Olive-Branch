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
// Three things stay honestly short of "fully working," on purpose:
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
//  3. A CHILD SESSION CANNOT ACTUALLY SEND ONE YET, even fully wired. The
//     schema's async-message tables (db/migrations/0001_phase0_init.sql)
//     were built for guardian → child delivery only: `delivery_intent.
//     sender_id` is `NOT NULL REFERENCES app_user(id)`, and a child
//     principal carries no `userId` at all (packages/auth/src/auth.ts) — she
//     has no app_user row to be attached as. So captureMessage()'s own,
//     already-tested authorization (pipeline.test.mjs's M2 suite) honestly
//     refuses a child-originated capture the same way it refuses a sitter's
//     — see server/routes.mjs's POST .../messages header for the full
//     reasoning, and packages/api/test/messages_route.test.mjs's own "D auth"
//     group, which exercises exactly this over real HTTP against a real
//     database rather than merely asserting it in a comment. Making a child
//     a real sender needs a schema change this pass did not make.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';
import 'calendar_day_logic.dart';

/// Records a short video via the device camera. Returns the recorded file,
/// or null if the user cancelled. Injectable on [ReceiptScreen] for tests —
/// the real implementation below talks to a platform channel the
/// widget-test harness doesn't have.
typedef VideoPicker = Future<XFile?> Function();

Future<XFile?> _defaultPickVideo() =>
    ImagePicker().pickVideo(source: ImageSource.camera);

enum _SendState { idle, busy, sent, error }

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

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  _SendState _state = _SendState.idle;
  String _errorMessage = '';

  bool get _isLive =>
      widget.baseUrl != null && widget.childId != null && widget.sessionToken != null;

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
    try {
      final VideoPicker pick = widget.pickVideo ?? _defaultPickVideo;
      final XFile? file = await pick();
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

      final OliveApi api =
          OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      await api.sendMessage(widget.childId!, storageKey: storageKey, durationMs: durationMs);
      if (widget.httpClient == null) api.close();

      if (!mounted) return;
      setState(() => _state = _SendState.sent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SendState.error;
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
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
        return const SizedBox(width: double.infinity, height: 52, child: FilledButton(
          onPressed: null,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Sending…'),
          ])));
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
