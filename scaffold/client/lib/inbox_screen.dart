// OLIVE BRANCH — child shell, inbox. No longer UNVERIFIED — verified by CI (client/test/inbox_screen_test.dart).
// MASTERFILE §8.2, §9.5, §7.19. Renders MARKUP screen 'inbox': "Async messages materialised by the delivery
// engine; receipts render in her frame."
//
// WHAT SHE SEES. A quiet list of what has arrived: one tile per message, "<her word for the grown-up> sent a video".
// A message she has not opened is a filled tile; one she has opened is a plain one. That is all: no dot, no "New",
// no greeting that counts or comforts, no number anywhere. When nothing has arrived the screen is simply empty, and
// it is exactly as empty when the server cannot be reached or answers with something unreadable: she is never shown
// an error, a retry button or a cloud, and nothing here ever says "no signal". The cause goes to the debug log.
//
// WHAT IT DOES. On a server-connected device it asks for its inbox (OliveApi.fetchInbox) when it opens, whenever the
// app returns to the front, and about once a minute while it is open (the delivery worker moves a due message into
// the inbox every half minute; a wake-up push, once one exists on this client, only makes the next ask sooner).
// What the server returns is exactly what it decided is ready: the bedtime, the day-part and the custody rules run
// on the server, so this screen has no clock logic of its own for deciding what to show. [parseInbox]
// (child_receive.dart) whitelists what is drawn.
//
// OPENING. Opening a tile she has not opened marks it opened here at once, tells the server through
// POST .../inbox/:id/opened, and opens its receipt. If the server cannot be told, the receipt waits in the offline
// outbox ([ReceiptQueue]) and goes later; the tile stays opened for her either way. It never delays the screen she
// asked for and she is never told it is waiting.
//
// A LOCALLY PAIRED TABLET has no server session: it is not "live" here, it is handed no messages, and so this
// screen is empty. The demo build (the preview with no server address at all) is the only caller that passes the
// example messages below.
//
// `deliveredAtLabel` for a real fetched entry is ALREADY formatted in her real frame server-side (server/routes.mjs'
// relativeInboxLabel()); this screen never does its own time-zone math. `dayPartKind` is honestly left null for a
// real fetched entry (the server does not compute one): receipt_screen.dart handles that absence.
//
// Not built: playing the picture or the recording (no player exists in this client; the signed media URL route
// GET .../inbox/:id/media-url is declared in api_client.dart and unused). Until it is, "opened" is recorded when she
// opens the tile, and the receipt sentence is the one receipt_screen.dart has always shown.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'calendar_day_logic.dart';
import 'child_receive.dart';
import 'form_factors.dart' as ff;
import 'grownup_labels.dart' show GrownupLabelScope, GrownupLabels, asSubject, neutralGrownUp;
import 'receipt_screen.dart';

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.senderName,
    required this.deliveredAtLabel,
    this.dayPartKind,
    this.watched = false,
    this.senderId,
    this.kind = 'video_msg',
  });

  /// A real fetched message's id is a real database UUID, not a small int —
  /// hence String, not int (the demo fixtures below use string literals of
  /// the same small numbers for exactly this reason).
  final String id;
  final String senderName;

  /// The sender's id, when the server gives one: lets a [GrownupLabelScope] show HER word for them
  /// (nickname, age default) instead of [senderName], the name the sender goes by.
  final String? senderId;
  /// Already formatted, her frame, e.g. "7:04 AM" or "Yesterday, 7:58 PM".
  /// Relative wording only — never a calendar date (§8.2.5's "sleeps, not
  /// dates" rule extends to every child-facing timestamp, not just
  /// countdowns).
  final String deliveredAtLabel;
  final String? dayPartKind;
  final bool watched;

  /// The delivery kind ('video_msg', 'voice_note', 'drawing', 'photo', 'nudge', ...): chooses the words and the picture.
  final String kind;

  InboxMessage markWatched() => InboxMessage(
    id: id, senderName: senderName, deliveredAtLabel: deliveredAtLabel,
    dayPartKind: dayPartKind, watched: true, senderId: senderId, kind: kind,
  );
}

/// Demo-only inbox contents, for the preview build that has no server at all. A server-connected or locally paired
/// device never shows these.
const List<InboxMessage> demoInboxMessages = <InboxMessage>[
  InboxMessage(id: '1', senderName: neutralGrownUp, deliveredAtLabel: '7:04 AM', dayPartKind: 'before_school'),
  InboxMessage(id: '2', senderName: neutralGrownUp, deliveredAtLabel: 'Yesterday, 7:58 PM',
    dayPartKind: 'wind_down', watched: true),
  InboxMessage(id: '3', senderName: 'another grown-up', deliveredAtLabel: '2 days ago, 6:10 PM',
    dayPartKind: 'dinner', watched: true),
];

/// What SHE calls the sender: her word through a [GrownupLabelScope] when the sender's id is known there,
/// else the name the server gave.
String _senderLabel(GrownupLabels labels, InboxMessage m) =>
    m.senderId != null && labels.contact(m.senderId) != null ? labels.nameFor(m.senderId) : m.senderName;

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.childName,
    required this.messages,
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
    this.receiptQueue,
    this.refreshEvery = const Duration(seconds: 60),
  });
  final String childName;
  /// The preview build's example messages. Ignored when the screen is live (it shows only what the server sent).
  final List<InboxMessage> messages;
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  /// Injectable for tests (package:http/testing.dart's MockClient) — matches
  /// HomeworkScreen/ReceiptScreen/child_home_live.dart's own convention.
  final http.Client? httpClient;
  /// Injectable for tests. Defaults to this device's queue for the child.
  final ReceiptQueue? receiptQueue;
  /// How often an open screen asks again. Null turns the timer off (tests).
  final Duration? refreshEvery;

  bool get _isLive => baseUrl != null && childId != null && sessionToken != null;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  late List<InboxMessage> _messages;
  Timer? _timer;
  bool _loading = false;
  ReceiptQueue? _queueOrNull;
  /// Ids she opened on this screen. A fetch that raced her tap can come back 'delivered'; these stay opened.
  final Set<String> _openedHere = <String>{};

  ReceiptQueue get _queue => _queueOrNull ??= widget.receiptQueue ?? ReceiptQueue.forChild(widget.childId!);

  @override
  void initState() {
    super.initState();
    // A live screen never starts from example messages: it shows what the server sent, or nothing.
    _messages = widget._isLive ? <InboxMessage>[] : List<InboxMessage>.of(widget.messages);
    if (widget._isLive) {
      WidgetsBinding.instance.addObserver(this);
      final Duration? every = widget.refreshEvery;
      if (every != null) _timer = Timer.periodic(every, (_) => unawaited(_load()));
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget._isLive) unawaited(_load());
  }

  /// The ONLY place this screen reads the network. First the receipts that are waiting go out, then the inbox is
  /// asked for. A failure at any point changes nothing she sees (what is already on the screen stays, an empty
  /// screen stays empty) and is only logged.
  Future<void> _load() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      await withChildApi<void>(
        baseUrl: widget.baseUrl!, sessionToken: widget.sessionToken!, httpClient: widget.httpClient,
        body: (OliveApi api) async {
          await _queue.drain((String id) => api.markInboxOpened(widget.childId!, id));
          final List<InboxMessage> fetched = parseInbox(await api.fetchInbox(widget.childId!));
          // A receipt still waiting to go is already opened as far as she is concerned.
          final Set<String> waiting = await _queue.pendingIds();
          if (!mounted) return;
          setState(() => _messages = <InboxMessage>[
            for (final InboxMessage m in fetched)
              (waiting.contains(m.id) || _openedHere.contains(m.id)) ? m.markWatched() : m,
          ]);
        },
      );
    } catch (e) {
      debugPrint('[olive.inbox] not loaded this time (nothing is shown to her): $e');
    } finally {
      _loading = false;
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
      // present a fabricated day-part as if it were hers. Honestly left null
      // for a live message (the server does not send one).
      if (!widget._isLive) {
        final List<StripSegment> segments = scheduleStrip(demoDayParts, nowHhmm);
        dayPartKind = currentSegment(segments)?.kind;
      } else {
        dayPartKind = null;
      }
      _openedHere.add(m.id);
      final int i = _messages.indexWhere((InboxMessage x) => x.id == m.id);
      if (i >= 0) setState(() => _messages[i] = m.markWatched());
      // Fire-and-forget — not awaited, deliberately: it must never delay the Navigator.push just below. A failure
      // leaves the receipt in the offline outbox and is never shown to her.
      if (widget._isLive) unawaited(_recordOpened(m.id));
    }

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(
      childName: widget.childName,
      senderName: asSubject(_senderLabel(GrownupLabelScope.read(context), m)),
      watchedAtLabel: watchedAtLabel,
      dayPartKind: dayPartKind,
      baseUrl: widget.baseUrl,
      childId: widget.childId,
      sessionToken: widget.sessionToken,
      httpClient: widget.httpClient,
    )));
  }

  Future<void> _recordOpened(String messageId) async {
    try {
      await withChildApi<void>(
        baseUrl: widget.baseUrl!, sessionToken: widget.sessionToken!, httpClient: widget.httpClient,
        body: (OliveApi api) => _queue.record(messageId, (String id) => api.markInboxOpened(widget.childId!, id)),
      );
    } catch (e) {
      debugPrint('[olive.inbox] receipt not sent (kept for later, not shown to her): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
        // Empty is nothing: no icon, no sentence, no greeting.
        final Widget content = _messages.isEmpty
            ? const SizedBox.expand()
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
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

IconData _iconFor(String kind) => switch (kind) {
      'voice_note' => Icons.graphic_eq_rounded,
      'drawing' => Icons.brush_outlined,
      'photo' => Icons.photo_outlined,
      'nudge' => Icons.favorite_border,
      _ => Icons.play_arrow_rounded,
    };

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.message, required this.onTap});
  final InboxMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String phrase = kReceivedPhrase[message.kind] ?? kReceivedPhrase['video_msg']!;
    final String line = '${asSubject(_senderLabel(GrownupLabelScope.of(context), message))} $phrase';
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
              child: Icon(_iconFor(message.kind),
                color: message.watched ? scheme.onSurfaceVariant : scheme.onPrimary)),
            const SizedBox(width: 12),
            Expanded(child: Text(line,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }
}
