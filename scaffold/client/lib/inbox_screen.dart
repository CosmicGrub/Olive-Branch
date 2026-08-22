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
import 'package:flutter/material.dart';
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

  final int id;
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
  InboxMessage(id: 1, senderName: 'Dad', deliveredAtLabel: '7:04 AM', dayPartKind: 'before_school'),
  InboxMessage(id: 2, senderName: 'Dad', deliveredAtLabel: 'Yesterday, 7:58 PM',
    dayPartKind: 'wind_down', watched: true),
  InboxMessage(id: 3, senderName: 'Grandma', deliveredAtLabel: '2 days ago, 6:10 PM',
    dayPartKind: 'dinner', watched: true),
];

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.childName, required this.messages});
  final String childName;
  final List<InboxMessage> messages;
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late List<InboxMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = List<InboxMessage>.of(widget.messages);
  }

  void _open(InboxMessage m) {
    final bool wasUnwatched = !m.watched;
    String watchedAtLabel = m.deliveredAtLabel;
    String? dayPartKind = m.dayPartKind;

    if (wasUnwatched) {
      final String nowHhmm = hhmmNow();
      final List<StripSegment> segments = scheduleStrip(demoDayParts, nowHhmm);
      final StripSegment current = segments.firstWhere(
        (StripSegment s) => s.current,
        orElse: () => segments.first,
      );
      watchedAtLabel = formatTimeOfDay(nowHhmm);
      dayPartKind = current.kind;
      final int i = _messages.indexWhere((InboxMessage x) => x.id == m.id);
      setState(() => _messages[i] = m.markWatched());
    }

    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(
      childName: widget.childName,
      senderName: m.senderName,
      watchedAtLabel: watchedAtLabel,
      dayPartKind: dayPartKind,
    )));
  }

  @override
  Widget build(BuildContext context) {
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
