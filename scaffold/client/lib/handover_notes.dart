// OLIVE BRANCH — parent-to-parent handover log. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and
// run via `flutter analyze` / `flutter test` this session). MASTERFILE P8,
// §21.7, §8.8.5.
//
// P8: "Deletion or editing of parent<->parent log entries [is prohibited].
// Court-tier integrity (§12 Phase 3). A log with an unsend button is not
// evidence." This log is not the child's to clear — it's the parents', and
// that makes it append-only regardless of who's annoyed by what's in it.
//
// So this State object exposes exactly one mutation: add. There is no
// _deleteEntry, no _editEntry, no long-press menu, no Dismissible, no
// delete/edit IconButton — not hidden, not disabled, just absent. "This will
// be the hardest button anyone builds here. If it is not real, §2.10 is
// decoration." (§21.7)
//
// §8.8.5 read-aloud: each entry gets its own speaker action, reading that
// entry's author and text verbatim — no summarizing across entries, no
// composed digest. Tap-gated per entry (admitSpeech(tap)), never
// autonomous — a parent scanning a long handover log on a bad day should
// never have entries start reading themselves.
import 'package:flutter/material.dart';
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'form_factors.dart' as ff;

class _HandoverEntry {
  const _HandoverEntry({required this.author, required this.when, required this.text});
  final String author, when, text;
}

class HandoverNotesScreen extends StatefulWidget {
  const HandoverNotesScreen({super.key, this.speak});

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null reports
  /// itself honestly on tap (same "recorded, not glossed over" posture as
  /// the Call buttons on emergency_card.dart) rather than rendering nothing —
  /// unlike the deliberately-absent delete/edit buttons above, read-aloud is
  /// a real, working feature that's only ever missing its platform wiring,
  /// not a capability this screen refuses to offer.
  final Future<void> Function(String text)? speak;

  @override
  State<HandoverNotesScreen> createState() => _HandoverNotesScreenState();
}

class _HandoverNotesScreenState extends State<HandoverNotesScreen> {
  final List<_HandoverEntry> _entries = <_HandoverEntry>[
    const _HandoverEntry(author: 'Sarah', when: 'Jul 28, 4:12 PM',
      text: "Running about 15 minutes late for pickup today — meeting overran. "
            "She's got her coat and backpack ready by the door."),
    const _HandoverEntry(author: 'You', when: 'Jul 28, 4:20 PM',
      text: "No problem, we'll wait inside where it's warm."),
    const _HandoverEntry(author: 'Sarah', when: 'Jul 30, 7:45 AM',
      text: "Picture day is Thursday — she needs the collared shirt, "
            "it's already in her backpack."),
    const _HandoverEntry(author: 'You', when: 'Aug 1, 8:02 AM',
      text: 'Packed her lunch peanut-free today since her class went nut-free this term.'),
  ];

  final TextEditingController _controller = TextEditingController();

  void _addEntry() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _entries.add(_HandoverEntry(author: 'You', when: _nowLabel(), text: text));
      _controller.clear();
    });
  }

  // Simple demo-precision timestamp — no intl dependency for a preview build.
  String _nowLabel() {
    const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final DateTime now = DateTime.now();
    final int hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final String minute = now.minute.toString().padLeft(2, '0');
    final String ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '${months[now.month - 1]} ${now.day}, $hour12:$minute $ampm';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<_HandoverEntry> newestFirst = _entries.reversed.toList();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // Pane A — compose: the disclaimer plus the add-note field and button,
    // grouped together as the form. Only ever pulled into a named list so
    // the wide/narrow branches below can share it verbatim rather than
    // diverging — same discipline message_banking.dart uses for its own
    // two panes.
    final List<Widget> composeChildren = <Widget>[
      Text(
        "Entries here can't be edited or removed — this log is admissible if it's ever needed.",
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: TextField(controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Add a note for the other parent…',
            border: OutlineInputBorder()),
          minLines: 1, maxLines: 4,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _addEntry())),
        const SizedBox(width: 8),
        FilledButton(onPressed: _addEntry, child: const Text('Add note')),
      ]),
    ];

    // Pane B — the entries list: every _EntryTile, newest first, same
    // widgets and same order as this screen always rendered.
    final List<Widget> listChildren = <Widget>[
      for (int i = 0; i < newestFirst.length; i++)
        _EntryTile(newestFirst[i], index: i, speak: widget.speak),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Handover notes')),
      // SingleChildScrollView + Column, NOT Expanded/ListView.builder — a
      // sliver list only realizes children near the viewport, which would
      // silently drop entries scrolled below the fold from the widget tree
      // (same fix message_banking.dart/letters_screen.dart already document
      // for the same bug class). It also lets the compose form and the
      // entries list become genuine independent panes at width, instead of
      // the compose row staying pinned to the bottom of a fixed-height
      // Column the way it did before this pass.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same threshold message_banking.dart/letters_screen.dart
        // use for their own two-pane splits.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: wide
            ? Row(key: const Key('handoverNotesTwoPaneRow'),
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: composeChildren)),
                  const SizedBox(width: 24),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: listChildren)),
                ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...composeChildren,
                const SizedBox(height: 20),
                ...listChildren,
              ]),
        );
      })),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry, {required this.index, this.speak});
  final _HandoverEntry entry;
  final int index;
  final Future<void> Function(String text)? speak;

  void _readAloud(BuildContext context) {
    if (speak == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Read aloud — not built yet.'), duration: Duration(seconds: 2)));
      return;
    }
    if (admitSpeech(SpeechTrigger.tap) != null) return;
    speak!('${entry.author}, ${entry.when}: ${entry.text}');
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      Row(children: <Widget>[
        Text(entry.author, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(width: 8),
        Text(entry.when, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        const Spacer(),
        SizedBox(width: 36, height: 36, child: IconButton(
          key: Key('readAloudButton_$index'),
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: const Icon(Icons.volume_up_outlined),
          tooltip: 'Read this entry aloud',
          onPressed: () => _readAloud(context))),
      ]),
      const SizedBox(height: 6),
      Text(entry.text, style: const TextStyle(fontSize: 14)),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      ),
    );
  }
}
