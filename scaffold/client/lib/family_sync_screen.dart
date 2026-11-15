// OLIVE BRANCH — the grown-ups' screen for sharing between their own phones: the emergency card side by side, and the
// copy/paste update. UNVERIFIED on a device; headless widget tests in CI (client/test/family_sync_screen_test.dart).
// Spec: docs/planning/FAMILY-SYNC-DESIGN.md sections 6.2, 6.4 and 7 (first slice). MASTERFILE 8.24.
//
// GROWN-UPS ONLY. The screen builds nothing for a child or a missing principal (an empty page), and it is meant to be
// opened only from the grown-up shell behind the adult gate. It is NOT reachable from any menu yet: founding a
// family on a phone and joining a second grown-up's phone are not wired into the app (identity PRs 3 to 5), so
// there is nothing for it to share between. It is built and tested so that wiring is the only step left.
//
// WORDS. Plain adult words: "update", "share", "card", "this phone", "the other phone". Never a technical word
// (no key, ledger, sync, epoch, event). Never a count or a score. Nothing it says is medical advice, and the only
// card text it shows is text a grown-up typed.
//
// NEVER A SILENT CHANGE. Nothing on this page changes the card on this phone until a grown-up taps "Use this card
// on this phone", and that goes through EmergencyCardService.save (stale-version, size and history rules intact).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emergency_card_local.dart';
import 'family_ledger_state.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'family_sync_bundle.dart';
import 'family_sync_emergency.dart';
import 'family_sync_engine.dart';

/// Where an update is copied to and pasted from. The default is the system clipboard; tests pass a fake.
abstract class SyncClipboardPort {
  Future<void> write(String text);
  Future<String?> read();
}

class SystemClipboardPort implements SyncClipboardPort {
  const SystemClipboardPort();
  @override
  Future<void> write(String text) => Clipboard.setData(ClipboardData(text: text));
  @override
  Future<String?> read() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

String syncRefusalText(String reason) => switch (reason) {
      'empty' => 'Write the card first, then share it.',
      'forked' => 'Choose between the two cards first.',
      'unreadable' => 'The shared card could not be read, so nothing was changed.',
      'same' => 'That card is already the shared one.',
      'not_member' => 'This phone is not set up to share with the other phone yet.',
      'no_key' => 'This phone is not set up to share with the other phone yet.',
      'full' => 'There is no room left to keep shared updates.',
      'moved' => 'The cards changed while you were looking. Nothing was changed.',
      'stale_version' => 'The card on this phone changed. Nothing was changed; look again.',
      'guardian_only' => 'Only a grown-up can do this.',
      _ => 'That did not work. Nothing was changed.',
    };

class FamilySyncScreen extends StatefulWidget {
  const FamilySyncScreen({
    super.key,
    required this.engine,
    required this.childId,
    required this.principal,
    required this.cardService,
    required this.ledger,
    this.myName = '',
    this.childName = 'her',
    this.clipboard = const SystemClipboardPort(),
  });

  final SyncEngine engine;
  final String childId;
  final FamilyPrincipal? principal;
  final EmergencyCardService cardService;

  /// The family ledger as this phone sees it right now.
  final Future<LedgerState> Function() ledger;

  /// The grown-up's own name as they want the other phone to see it ("Mom"). Optional.
  final String myName;
  final String childName;
  final SyncClipboardPort clipboard;

  @override
  State<FamilySyncScreen> createState() => _FamilySyncScreenState();
}

class _FamilySyncScreenState extends State<FamilySyncScreen> {
  EmergencyView? _view;
  EmergencyCardDoc? _doc;
  String? _status;
  bool _busy = false;

  EmergencySync get _sync => EmergencySync(widget.engine, widget.childId);
  bool get _allowed => canEditStructure(widget.principal);

  @override
  void initState() {
    super.initState();
    if (_allowed) _reload();
  }

  Future<void> _reload() async {
    final EmergencyView v = await _sync.view();
    final EmergencyCardDoc d = await widget.cardService.read(widget.principal);
    if (mounted) {
      setState(() {
        _view = v;
        _doc = d;
      });
    }
  }

  Future<void> _run(Future<String?> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String? msg = await body();
      if (mounted) setState(() => _status = msg);
    } catch (_) {
      if (mounted) setState(() => _status = syncRefusalText('?'));
    } finally {
      await _reload();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareMine() => _run(() async {
        final LocalEmergencyCard? mine = _doc?.card;
        if (mine == null) return syncRefusalText('empty');
        final SyncAppend r = await _sync.share(mine, byName: widget.myName, state: await widget.ledger());
        return r.event != null
            ? 'Saved on this phone. It reaches the other phone when you copy an update and paste it there.'
            : syncRefusalText(r.reason ?? '?');
      });

  Future<void> _useHere(EmergencyVersion v) => _run(() async {
        final EmergencyCardDoc d = await widget.cardService.read(widget.principal);
        final EcResult r = await EmergencySync.useHere(widget.cardService, widget.principal, v, expectedVersion: d.version);
        return r.ok ? 'The shared card is now the card on this phone.' : syncRefusalText(r.reason);
      });

  Future<void> _keep(EmergencyVersion v) => _run(() async {
        final SyncAppend r = await _sync.choose(v, byName: widget.myName, state: await widget.ledger());
        if (r.event == null) return syncRefusalText(r.reason ?? '?');
        return 'Saved on this phone. It reaches the other phone when you copy an update and paste it there.';
      });

  Future<void> _copy() => _run(() async {
        final SyncBundleOut out = await exportBundle(widget.engine);
        if (out.count == 0 && out.text.isEmpty) return 'There is nothing new for the other phone.';
        await widget.clipboard.write(out.text);
        return out.more
            ? 'Copied part of the updates. Paste it on the other phone, then copy again for the rest.'
            : 'Copied. Paste it on the other phone.';
      });

  Future<void> _paste() async {
    final String? text = await showDialog<String>(context: context, builder: (BuildContext ctx) => const _PasteDialog());
    if (text == null || !mounted) return;
    await _run(() => _addUpdate(text));
  }

  Future<String?> _addUpdate(String text) async {
    final SyncBundleIn r = await importBundle(widget.engine, text, state: await widget.ledger());
    if (r.ingest == null) return 'That does not look like an update from your family. Nothing was changed.';
    final SyncIngest i = r.ingest!;
    if (i.added > 0) return i.added == 1 ? 'Added 1 update.' : 'Added ${i.added} updates.';
    if (i.refused > 0 && i.known == 0 && i.held == 0) return 'That update could not be used. Nothing was changed.';
    return 'Nothing new in that update.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const Scaffold(body: SizedBox.shrink());
    final EmergencyView? v = _view;
    final EmergencyCardDoc? d = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Share between our phones')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text(
          'Updates are sealed. Only the grown-ups\' phones can read them. Copying an update sends it nowhere by itself: '
          'you paste it on the other phone.',
        ),
        const SizedBox(height: 16),
        Text("${widget.childName == 'her' ? 'The' : "${widget.childName}'s"} emergency card",
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (v == null || d == null) const Center(child: CircularProgressIndicator()) else ..._cardSection(v, d),
        const SizedBox(height: 16),
        Text('Moving updates', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton(key: const Key('sync-copy'), onPressed: _busy ? null : _copy, child: const Text('Copy an update for the other phone')),
          OutlinedButton(key: const Key('sync-paste'), onPressed: _busy ? null : _paste, child: const Text('Paste an update from the other phone')),
        ]),
        if (widget.engine.heldCount > 0) ...<Widget>[
          const SizedBox(height: 12),
          const Text('Some updates are still missing. Ask the other phone to copy an update again.', key: Key('sync-missing')),
        ],
        if (_status != null) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_status!, key: const Key('sync-status'))),
        ],
      ]),
    );
  }

  List<Widget> _cardSection(EmergencyView v, EmergencyCardDoc d) {
    final LocalEmergencyCard? mine = d.card;
    final bool haveMine = mine != null && !mine.isEmpty;
    Widget cardBox(String who, EmergencyVersion e, {Widget? action}) => Card(
          key: Key('sync-version-${e.event.idHex.substring(0, 8)}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(who, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(e.readable ? e.card!.spokenText() : 'This card could not be read.'),
              if (action != null) ...<Widget>[const SizedBox(height: 8), action],
            ]),
          ),
        );
    if (!v.started) {
      return <Widget>[
        const Text('Nothing has been shared yet.'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('sync-share-mine'),
            onPressed: _busy || !haveMine ? null : _shareMine,
            child: const Text("Share this phone's card"),
          ),
        ),
        if (!haveMine) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Write the card on this phone first.')),
      ];
    }
    if (v.forked) {
      return <Widget>[
        const Text('Two grown-ups shared different cards. Nothing has been changed on this phone. Choose the one to keep.',
            key: Key('sync-forked')),
        const SizedBox(height: 8),
        for (final EmergencyVersion e in v.ends)
          cardBox(
            'From ${e.byName}',
            e,
            action: e.readable
                ? FilledButton(key: Key('sync-keep-${e.event.idHex.substring(0, 8)}'), onPressed: _busy ? null : () => _keep(e), child: const Text('Keep this card'))
                : null,
          ),
      ];
    }
    final EmergencyVersion e = v.ends.first;
    if (!e.readable) {
      return <Widget>[
        cardBox('Shared by ${e.byName}', e),
        const SizedBox(height: 8),
        const Text('This shared card could not be read. The card on this phone has not been changed.'),
      ];
    }
    final bool same = haveMine && mine.sameAs(e.card!);
    final bool theyHad = widget.engine.peers.keys.any((String p) => widget.engine.peerHad(p, e.event));
    return <Widget>[
      cardBox('Shared by ${e.byName}', e),
      const SizedBox(height: 8),
      if (same)
        Text(theyHad ? 'Both phones have this card.' : 'This phone has the shared card.', key: const Key('sync-same'))
      else ...<Widget>[
        const Text("The shared card is different from this phone's card.", key: Key('sync-differs')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton(key: const Key('sync-use-here'), onPressed: _busy ? null : () => _useHere(e), child: const Text('Use this card on this phone')),
          if (haveMine) OutlinedButton(key: const Key('sync-share-mine'), onPressed: _busy ? null : _shareMine, child: const Text("Share this phone's card instead")),
        ]),
      ],
    ];
  }
}

/// Owns its own text box, so the box is released only when the dialog is really gone (not while it is closing).
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();
  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Paste an update'),
        content: TextField(
          key: const Key('sync-paste-field'), controller: _c, maxLines: 4, minLines: 2,
          decoration: const InputDecoration(hintText: 'Paste what the other phone copied'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(key: const Key('sync-paste-add'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('Add')),
        ],
      );
}
