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
// OPENING. On a server-connected device a tile opens the calm player ([MessagePlayerScreen], message_player.dart):
// the sentence, and the video, the voice, the drawing or the photo when there is one. The message counts as OPENED
// the first time it really plays or is really shown, never on the tap alone: only then does the tile become a plain
// one, the server hear about it through POST .../inbox/:id/opened, and her receipt screen follow. A message that
// could not be played (no signal, expired, no file) stays as it was and can be tried again, with no error or retry
// on her screen. If the server cannot be told, the receipt waits in the offline outbox ([ReceiptQueue]) and goes
// later; the tile stays opened for her either way. It never delays the screen she asked for and she is never told
// it is waiting. The preview build (no server) keeps the old behaviour: the tap opens the receipt.
//
// A LOCALLY PAIRED TABLET has no server session: it is not "live" here, it is handed no messages, and so this
// screen is empty. The demo build (the preview with no server address at all) is the only caller that passes the
// example messages below.
//
// `deliveredAtLabel` for a real fetched entry is ALREADY formatted in her real frame server-side (server/routes.mjs'
// relativeInboxLabel()); this screen never does its own time-zone math. `dayPartKind` is honestly left null for a
// real fetched entry (the server does not compute one): receipt_screen.dart handles that absence.
//
// The receipt sentence is the one receipt_screen.dart has always shown. An end-to-end encrypted video cannot be
// opened by this client (no key exchange yet): it is shown as its sentence only and never recorded as opened.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'calendar_day_logic.dart';
import 'child_receive.dart';
import 'form_factors.dart' as ff;
import 'grownup_labels.dart' show GrownupLabelScope, GrownupLabels, asSubject, neutralGrownUp;
import 'message_player.dart';
import 'receipt_screen.dart';
import 'server_transport_policy.dart' show OliveTransport;

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
    this.mediaFetcher,
    this.playbackFactory,
    this.pictureBuilder = defaultPictureBuilder,
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

  /// Injectable for tests: how a vetted media address becomes a local file. Defaults to the app's own http client.
  final MediaFetcher? mediaFetcher;

  /// Injectable for tests: the audio/video player. Defaults to the video_player plugin.
  final MessagePlaybackPort Function()? playbackFactory;

  /// Injectable for tests: how a picture is drawn.
  final PictureBuilder pictureBuilder;

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
  /// The receipt wording captured at the moment a message first played (her frame, her clock).
  final Map<String, ({String label, String? part})> _openedAt = <String, ({String label, String? part})>{};

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

  /// What SHE reads on the player: her word for the grown-up and what they sent.
  String _lineFor(InboxMessage m) {
    final String phrase = kReceivedPhrase[m.kind] ?? kReceivedPhrase['video_msg']!;
    return '${asSubject(_senderLabel(GrownupLabelScope.read(context), m))} $phrase';
  }

  Future<MediaTicket?> _ticketFor(InboxMessage m) async {
    try {
      return await withChildApi<MediaTicket?>(
        baseUrl: widget.baseUrl!, sessionToken: widget.sessionToken!, httpClient: widget.httpClient,
        body: (OliveApi api) async =>
            parseMediaTicket(await api.fetchInboxMediaUrl(widget.childId!, m.id), widget.baseUrl!),
      );
    } on ApiException catch (e) {
      // 404 is simply "no file for this message (any more)"; the player shows its sentence and nothing else.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<LocalMedia> _fetchMedia(Uri uri) async {
    final MediaFetcher? injected = widget.mediaFetcher;
    if (injected != null) return injected(uri);
    final http.Client client = widget.httpClient ?? OliveTransport.clientFor(widget.baseUrl!);
    try {
      return await httpMediaFetcher(client)(uri);
    } finally {
      if (widget.httpClient == null) client.close();
    }
  }

  /// The first time a message really plays or is really shown: the tile becomes a plain one, the server is told
  /// (or the receipt waits in the outbox), and the receipt wording is fixed to this moment.
  Future<void> _playedFirstTime(InboxMessage m) async {
    if (m.watched || _openedHere.contains(m.id)) return;
    final String nowHhmm = hhmmNow();
    // A live message's day-part is honestly left null (the server does not send one); see _open's demo branch.
    _openedAt[m.id] = (label: formatTimeOfDay(nowHhmm), part: null);
    _openedHere.add(m.id);
    final int i = _messages.indexWhere((InboxMessage x) => x.id == m.id);
    if (mounted && i >= 0) setState(() => _messages[i] = m.markWatched());
    unawaited(_recordOpened(m.id));
  }

  Future<void> _openLive(InboxMessage m) async {
    final bool wasWatched = m.watched;
    final String line = _lineFor(m);
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => MessagePlayerScreen(
          line: line,
          payloadKind: m.kind,
          loadTicket: () => _ticketFor(m),
          fetchMedia: _fetchMedia,
          onOpened: () => _playedFirstTime(m),
          playbackFactory: widget.playbackFactory,
          pictureBuilder: widget.pictureBuilder,
        )));
    if (!mounted) return;
    // Her receipt screen follows only a message she really saw or heard (now, or before).
    final ({String label, String? part})? at = _openedAt[m.id];
    if (!wasWatched && at == null) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(
          childName: widget.childName,
          senderName: asSubject(_senderLabel(GrownupLabelScope.read(context), m)),
          watchedAtLabel: at?.label ?? m.deliveredAtLabel,
          dayPartKind: at?.part,
          baseUrl: widget.baseUrl,
          childId: widget.childId,
          sessionToken: widget.sessionToken,
          httpClient: widget.httpClient,
        ))));
  }

  void _open(InboxMessage m) {
    if (widget._isLive) {
      unawaited(_openLive(m));
      return;
    }
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
