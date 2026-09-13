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
//
// LIVE WIRING (baseUrl/childId/guardianId/httpClient, all optional and
// additive — same convention AvailabilityScreen/ThemePickerScreen/
// LiveCourtExportScreen already use for a screen guardian_more.dart's hub
// opens): when supplied, this screen fetches the real handover log via
// OliveApi.fetchHandoverNotes() on init and posts new entries via
// OliveApi.postHandoverNote(), minting a fresh devLoginFor() session per
// call — same "nothing here should trust a token that might have outlived
// this widget's own lifecycle" posture guardian_more.dart's own
// _startRealCall/_liveSetGuardianPin already hold themselves to, rather
// than InboxScreen's externally-supplied-sessionToken shape (that one's
// caller, main_live.dart's child shell, holds a persisted child session
// this hub has no equivalent of). `guardianId` does double duty: it's
// devLoginFor's own `userId`, AND (matching AvailabilityScreen.guardianId's
// established meaning) the signed-in guardian's own id, used to decide
// whether a fetched entry's `authorId` renders as "You" or the real
// `authorName` the server sends — never trusted over the session for
// anything the server itself decides (message_log's own log_no_child RLS +
// this route's own child-role 403 guard are the real authorization
// boundary either way). `when` for a real fetched or just-posted entry is
// ALREADY formatted in the child's own resolved zone, server-side
// (server/routes.mjs's own whenLabel, both routes) — this screen never
// does its own timezone math for a live entry, the same "conversion
// belongs on the server side of the wire" discipline every other
// live-wired screen in this client already follows (no timezone package
// exists in client/pubspec.yaml). `_nowLabel` below stays exactly what it
// always was — a demo-only stand-in used ONLY on the pure offline/demo
// path, never called once this screen is live.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'api_client.dart';
import 'form_factors.dart' as ff;

class _HandoverEntry {
  const _HandoverEntry({required this.author, required this.when, required this.text});
  final String author, when, text;
}

enum _LoadState { ready, loading, error }

class HandoverNotesScreen extends StatefulWidget {
  const HandoverNotesScreen({
    super.key,
    this.speak,
    this.baseUrl,
    this.childId,
    this.guardianId,
    this.httpClient,
  });

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null reports
  /// itself honestly on tap (same "recorded, not glossed over" posture as
  /// the Call buttons on emergency_card.dart) rather than rendering nothing —
  /// unlike the deliberately-absent delete/edit buttons above, read-aloud is
  /// a real, working feature that's only ever missing its platform wiring,
  /// not a capability this screen refuses to offer.
  final Future<void> Function(String text)? speak;
  final String? baseUrl;
  final String? childId;
  /// The signed-in guardian's own id — devLoginFor's `userId` AND the "You"
  /// comparison; see this file's LIVE WIRING header.
  final String? guardianId;
  /// Injectable for tests (package:http/testing.dart's MockClient) — matches
  /// AvailabilityScreen/LiveCourtExportScreen's own convention.
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && childId != null && guardianId != null;

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
  _LoadState _loadState = _LoadState.ready;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    if (widget._isLive) _load();
  }

  /// Renders a fetched/posted row's `authorId` as "You" for the signed-in
  /// guardian's own entries, the real `authorName` otherwise — matches the
  /// demo fixtures' own author labeling exactly, just driven by real data.
  /// Falls back to 'A parent' only for the theoretical case of a real row
  /// whose author is neither the caller nor named (author_id always joins
  /// to a real app_user row server-side — see pool.ts's handoverNotesFor()
  /// — so this fallback is defensive, not an expected path).
  String _authorLabel(String authorId, String? authorName) =>
      authorId == widget.guardianId ? 'You' : (authorName ?? 'A parent');

  /// The ONLY place this screen calls the network to READ — mirrors
  /// LiveCourtExportScreen's own self-fetching pattern exactly: a fresh
  /// devLoginFor() per load, never a cached token (see this file's LIVE
  /// WIRING header), and `api.close()` only on the success path, same as
  /// that screen's own _load() — if devLoginFor/fetchHandoverNotes throws,
  /// there is either no [api] yet or a short-lived one this preview build
  /// doesn't chase down, matching that established precedent rather than
  /// inventing a stricter cleanup path here alone. A failure here is a
  /// real, honest error state with a retry affordance (InboxScreen's own
  /// established shape), never a silent fall-back to the demo fixtures and
  /// never an unhandled exception.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchHandoverNotes(widget.childId!);
      if (widget.httpClient == null) api.close();
      final List<dynamic> raw = result['entries'] as List<dynamic>? ?? <dynamic>[];
      final List<_HandoverEntry> fetched = raw.map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        return _HandoverEntry(
          author: _authorLabel(row['authorId'] as String? ?? '', row['authorName'] as String?),
          when: row['whenLabel'] as String? ?? '',
          text: row['body'] as String? ?? '',
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _entries..clear()..addAll(fetched);
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  Future<void> _addEntry() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget._isLive) {
      setState(() {
        _entries.add(_HandoverEntry(author: 'You', when: _nowLabel(), text: text));
        _controller.clear();
      });
      return;
    }
    // A real, court-tier append — see this file's own P8 header. A failure
    // here must be a visible, honest error (an ApiException the guardian
    // can see and retry), never a silent no-op that lets her believe the
    // other parent was actually told something.
    setState(() => _posting = true);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row = await api.postHandoverNote(widget.childId!, text);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        // POST's own response already carries a real seq/whenLabel — see
        // OliveApi.postHandoverNote's own doc comment for why this never
        // re-fetches the whole list just to render the entry it already
        // has. author is always 'You' here (the caller IS this entry's
        // author, by construction) — _authorLabel still routes through the
        // same real comparison rather than a literal, so a mismatched or
        // missing widget.guardianId fails honestly to 'A parent' instead of
        // silently asserting an identity this screen never verified.
        _entries.add(_HandoverEntry(
          author: _authorLabel(row['authorId'] as String? ?? '', null),
          when: row['whenLabel'] as String? ?? '',
          text: row['body'] as String? ?? text,
        ));
        _controller.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't send that note — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // Simple demo-precision timestamp — no intl dependency for a preview
  // build. Demo/offline path ONLY -- a live entry's `when` is always the
  // server's own whenLabel (see this file's LIVE WIRING header); this never
  // runs once widget._isLive is true.
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
    // Loading/error UI mirrors InboxScreen's own established shape (same
    // icon, same wording pattern, same real retry action) — both only ever
    // reachable when this screen is live-wired; the pure demo path (no live
    // params) never enters either state, matching _loadState's own initial
    // value of _LoadState.ready.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Handover notes')),
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
          onSubmitted: _posting ? null : (_) => _addEntry())),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _posting ? null : _addEntry,
          child: _posting
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Add note')),
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
