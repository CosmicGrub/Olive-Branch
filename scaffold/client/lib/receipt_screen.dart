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
// Playback itself is an HONEST STUB: no video backend exists yet in this
// preview build (see api_client.dart), so "Send one back" reports itself
// rather than pretending to record anything, using the same `_notBuiltYet`
// snackbar convention child_home.dart and emergency_card.dart already use.
import 'package:flutter/material.dart';
import 'calendar_day_logic.dart';

void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    super.key,
    required this.childName,
    required this.senderName,
    required this.watchedAtLabel,
    required this.dayPartKind,
  });

  final String childName;
  final String senderName;
  /// Already formatted, e.g. "7:04 AM" — her frame, resolved by the caller.
  final String watchedAtLabel;
  /// e.g. 'before_school'. Nullable: a receipt is still honest with no
  /// day-part context, it just drops the "— before school" clause.
  final String? dayPartKind;

  @override
  Widget build(BuildContext context) {
    final String phrase = watchedReceiptPhrase(
      timeLabel: watchedAtLabel,
      possessive: "$childName's",
      dayPartKind: dayPartKind,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Message watched')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StampCard(senderName: senderName, phrase: phrase),
          const SizedBox(height: 26),
          SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
            onPressed: () => _notBuiltYet(context, 'Recording a message back'),
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Send one back'))),
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        const _DashedDivider(),
        const SizedBox(height: 14),
        Text(phrase,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14.5, fontStyle: FontStyle.italic)),
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
