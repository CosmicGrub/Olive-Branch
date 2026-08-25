// OLIVE BRANCH — child shell, inbox. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §8.2, §9.5. Renders
// MARKUP screen 'inbox': "Async messages materialised by the delivery
// engine; receipts render in her frame."
//
// Opening an unwatched message is the one real mutation this screen makes
// (marks it watched, in-memory) and the one place it hands off to
// receipt_screen.dart — classifying "right now" against the SAME
// `demoDayParts` schedule my_day.dart renders, rather than guessing a
// day-part independently. Two lookups drifting apart is exactly the failure
// phase3.ts's DAY_PART_META already guards against for label/glyph; using
// one shared classification here extends that same discipline across files.
//
// An already-watched message still opens its receipt — showing what was
// already recorded, never re-deriving "now" for something that already
// happened. No settings affordance exists at any depth (matches
// child_home.dart), and nothing here is a score: `watched`/unread state is
// informational, not a streak.
//
// LIVE WIRING (baseUrl/childId/sessionToken/httpClient, all optional and
// additive — same convention HomeworkScreen/ReceiptScreen already use):
// when supplied, this screen fetches its OWN real inbox via
// OliveApi.fetchInbox() on init, mirroring HomeworkScreen's own self-
// fetching pattern rather than requiring a caller to pre-fetch and pass
// down a messages list. `deliveredAtLabel` for a real fetched entry is
// ALREADY formatted in her real frame server-side (server/routes.mjs's own
// relativeInboxLabel()) — this screen never does its own timezone math, the
// same "conversion belongs on the server side of the wire" discipline every
// other live-wired screen in this client already follows (no timezone
// package exists in client/pubspec.yaml). `dayPartKind` is honestly left
// null for a real fetched entry (the server route does not compute one —
// a separate, still-open gap, matching ChildHome's own presence field) —
// receipt_screen.dart's own dayPartKind is already nullable and handles
// that absence honestly, same as it always has for the demo path.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'calendar_day_logic.dart';
import 'form_factors.dart' as ff;
import 'receipt_screen.dart';

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.senderName,
    required this.deliveredAtLabel,
    this.dayPartKind,
    this.watched = false,
  });

  /// A real fetched message's id is a real database UUID, not a small int —
  /// hence String, not int (the demo fixtures below use string literals of
  /// the same small numbers for exactly this reason).
  final String id;
  final String senderName;
  /// Already formatted, her frame, e.g. "7:04 AM" or "Yesterday, 7:58 PM".
  /// Relative wording only — never a calendar date (§8.2.5's "sleeps, not
  /// dates" rule extends to every child-facing timestamp, not just
  /// countdowns).
  final String deliveredAtLabel;
  final String? dayPartKind;
  final bool watched;

  InboxMessage markWatched() => InboxMessage(
    id: id, senderName: senderName, deliveredAtLabel: deliveredAtLabel,
    dayPartKind: dayPartKind, watched: true,
  );
}

/// Demo-only inbox contents. No live delivery-engine backend exists yet (see
/// api_client.dart / packages/delivery-engine) — this stands in for it.
const List<InboxMessage> demoInboxMessages = <InboxMessage>[
  InboxMessage(id: '1', senderName: 'Dad', deliveredAtLabel: '7:04 AM', dayPartKind: 'before_school'),
  InboxMessage(id: '2', senderName: 'Dad', deliveredAtLabel: 'Yesterday, 7:58 PM',
    dayPartKind: 'wind_down', watched: true),
  InboxMessage(id: '3', senderName: 'Grandma', deliveredAtLabel: '2 days ago, 6:10 PM',
    dayPartKind: 'dinner', watched: true),
];

enum _LoadState { ready, loading, error }

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.childName,
    required this.messages,
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
  });
  final String childName;
  /// The demo/offline fixture — also what renders for one frame before a
  /// live fetch (below) resolves, when live params are supplied.
  final List<InboxMessage> messages;
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  /// Injectable for tests (package:http/testing.dart's MockClient) — matches
  /// HomeworkScreen/ReceiptScreen/child_home_live.dart's own convention.
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && childId != null && sessionToken != null;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late List<InboxMessage> _messages;
  _LoadState _loadState = _LoadState.ready;

  @override
  void initState() {
    super.initState();
    _messages = List<InboxMessage>.of(widget.messages);
    if (widget._isLive) _load();
  }

  /// The ONLY place this screen calls the network — mirrors HomeworkScreen's
  /// own self-fetching pattern rather than requiring a pre-fetched list from
  /// a caller. A failure here is a real, honest error state with a retry
  /// affordance (child_home_live.dart's own established shape), never a
  /// silent fall-back to the demo fixture and never an unhandled exception.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    final OliveApi api =
        OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
    try {
      final Map<String, dynamic> result = await api.fetchInbox(widget.childId!);
      final List<dynamic> raw = result['entries'] as List<dynamic>? ?? <dynamic>[];
      final List<InboxMessage> fetched = raw.map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        return InboxMessage(
          id: row['id'] as String,
          senderName: row['sender_name'] as String,
          // Already formatted in her real frame, server-side — see this
          // file's own header for why no client-side timezone math happens
          // here.
          deliveredAtLabel: row['deliveredAtLabel'] as String? ?? '',
          // Not returned by the real route yet — a separate, still-open gap
          // (see this file's header); left honestly null, same as
          // receipt_screen.dart already handles for the demo path.
          dayPartKind: null,
          watched: row['state'] == 'opened',
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _messages = fetched;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    } finally {
      if (widget.httpClient == null) api.close();
    }
  }

  /// Best-effort — mirrors [OliveApi.endCall]'s own posture exactly (see
  /// that method's own doc comment): record-keeping only, never allowed to
  /// block or delay the real screen transition [_open] is already mid-tap
  /// on, and never surfaced to the child as an error. A real gap this
  /// closes, found by this project's own post-tier audit: MASTERFILE §7.3
  /// declared POST .../inbox/:id/opened as part of the API surface for as
  /// long as this document has had an API reference section, but nothing
  /// anywhere ever called it — this screen only ever flipped `watched` in
  /// LOCAL widget state, invisible to the server past this one screen
  /// instance, so a fresh [_load] on the next visit re-showed every
  /// previously-watched message as "New."
  Future<void> _markOpenedRemote(String messageId) async {
    final OliveApi api =
        OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
    try {
      await api.markInboxOpened(widget.childId!, messageId);
    } catch (e) {
      debugPrint('[olive.inbox] markInboxOpened failed (best-effort, not shown to her): $e');
    } finally {
      if (widget.httpClient == null) api.close();
    }
  }

  void _open(InboxMessage m) {
    final bool wasUnwatched = !m.watched;
    String watchedAtLabel = m.deliveredAtLabel;
    String? dayPartKind = m.dayPartKind;

    if (wasUnwatched) {
      final String nowHhmm = hhmmNow();
      watchedAtLabel = formatTimeOfDay(nowHhmm);
      // demoDayParts is a fixed DEMO schedule — real for the offline/demo
      // path, but classifying a REAL live-fetched message against it would
      // present a fabricated day-part as if it were hers. No real day-part
      // source exists server-side yet for a live message (the same gap
      // ChildHome's own `presence` field discloses) — honestly left null
      // there, same as receipt_screen.dart's own dayPartKind already
      // handles a genuine absence for.
      if (!widget._isLive) {
        final List<StripSegment> segments = scheduleStrip(demoDayParts, nowHhmm);
        dayPartKind = currentSegment(segments)?.kind;
      } else {
        dayPartKind = null;
      }
      final int i = _messages.indexWhere((InboxMessage x) => x.id == m.id);
      setState(() => _messages[i] = m.markWatched());
      // Fire-and-forget — not awaited, deliberately: see _markOpenedRemote's
      // own doc comment for why this must never delay the Navigator.push
      // just below, which happens unconditionally either way.
      if (widget._isLive) unawaited(_markOpenedRemote(m.id));
    }

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(
      childName: widget.childName,
      senderName: m.senderName,
      watchedAtLabel: watchedAtLabel,
      dayPartKind: dayPartKind,
      baseUrl: widget.baseUrl,
      childId: widget.childId,
      sessionToken: widget.sessionToken,
      httpClient: widget.httpClient,
    )));
  }

  @override
  Widget build(BuildContext context) {
    // Loading/error UI mirrors child_home_live.dart's own established
    // shape (same icon, same wording pattern, same real retry action) —
    // both only ever reachable when this screen is live-wired; the pure
    // demo path (no live params) never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )),
      );
    }
    final int unread = _messages.where((InboxMessage m) => !m.watched).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // The only "detail" relationship here is tap-to-push a full-screen
        // ReceiptScreen (see file header) — no persistent second pane. On a
        // wide tablet/desktop viewport the single column is only ever capped
        // to a comfortable reading width and centered; tap-to-navigate is
        // completely untouched. Same real columnsAt() gate every other width
        // decision in the app uses.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = _messages.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined, size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('Nothing here yet.', style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ])))
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                Text(unread == 0
                  ? 'Hi ${widget.childName}, all caught up'
                  : "Hi ${widget.childName}, you've got $unread new "
                    '${unread == 1 ? 'message' : 'messages'}',
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                for (final InboxMessage m in _messages) _InboxTile(message: m, onTap: () => _open(m)),
              ]);
        return capWidth
            ? Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                    child: content))
            : content;
      })),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.message, required this.onTap});
  final InboxMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: message.watched ? scheme.surface : scheme.primaryContainer,
            border: message.watched ? Border.all(color: scheme.outlineVariant) : null,
          ),
          child: Row(children: <Widget>[
            CircleAvatar(radius: 22,
              backgroundColor: message.watched ? scheme.outlineVariant : scheme.primary,
              child: Icon(Icons.play_arrow_rounded,
                color: message.watched ? scheme.onSurfaceVariant : scheme.onPrimary)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${message.senderName} sent a video',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(message.watched ? 'Watched · ${message.deliveredAtLabel}' : 'New — tap to watch',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
            if (!message.watched)
              Container(width: 10, height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.error)),
          ]),
        ),
      ),
    );
  }
}
