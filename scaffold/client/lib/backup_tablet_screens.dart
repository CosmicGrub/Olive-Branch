// OLIVE BRANCH — the two grown-up screens on HER tablet: moving her to a new tablet, and bringing her home back on the
// replacement. UNVERIFIED on a device; widget-tested headless (client/test/backup_screens_test.dart).
// Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// BEHIND THE GROWN-UP GATE ONLY. These are reached from the tablet's "Guardian mode" page (PIN and biometric), never from
// anything she sees. She sees no words, no count, no error and no key; her backups run silently (backup_places.dart). The
// words these screens show are two of her secrets: they are only on screen while a grown-up looks at them and are never copied.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'backup_classes.dart';
import 'backup_keys.dart';
import 'backup_places.dart';
import 'backup_service.dart';
import 'backup_targets.dart';
import 'backup_widgets.dart';
import 'local_services.dart';
import 'restore_engine.dart';

// ================================================================== her tablet: moving away from the old one

/// On HER tablet, behind the grown-up gate: the words that carry her to a new tablet, and the optional keepsake sheet.
class HerKeysScreen extends StatefulWidget {
  const HerKeysScreen({super.key, required this.services, this.confirmAdult});
  final LocalServices services;
  final Future<bool> Function()? confirmAdult;

  @override
  State<HerKeysScreen> createState() => _HerKeysScreenState();
}

class _HerKeysScreenState extends State<HerKeysScreen> {
  bool _allowed = false;
  bool _showHandover = false;
  bool _showKeepsake = false;
  ChildSecrets? _secrets;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final bool ok = widget.confirmAdult == null ? true : await widget.confirmAdult!();
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop();
      return;
    }
    final ChildSecrets s = await ChildKeyKeeper(widget.services.area('childkeys')).ensure();
    if (!mounted) return;
    setState(() {
      _secrets = s;
      _allowed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    if (!_allowed) return Scaffold(appBar: AppBar(title: const Text('Moving to a new tablet')), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Moving to a new tablet')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Text('Keep her home, drawings and memories', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'This tablet backs up her pictures, her memory box and her private areas by itself, each locked with a key that stays on this tablet. '
              'Her private journal, worry box and feelings are locked with a key that no grown-up\'s phone ever holds.'),
          const SizedBox(height: 16),
          Text('While you still have this tablet', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Show the hand-over words, then type them on the new tablet. They bring back everything, including her private areas, '
              'which nobody else can open. Put this tablet away safely until the new one is set up.'),
          const SizedBox(height: 8),
          if (!_showHandover)
            FilledButton(key: const Key('showHandover'), onPressed: () => setState(() => _showHandover = true), child: const Text('Show the hand-over words'))
          else ...<Widget>[
            WordGrid(_secrets!.handoverWords, key: const Key('handoverWords')),
            const SizedBox(height: 8),
            const NeverAskCard(),
            TextButton(key: const Key('hideHandover'), onPressed: () => setState(() => _showHandover = false), child: const Text('Hide the words')),
          ],
          const SizedBox(height: 20),
          Text('If this tablet might be lost or broken', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'You can write her keepsake words on paper. They can bring back her pictures and memory box on a new tablet even if this one is gone. '
              'But whoever holds that paper, with a copy of her backup, can open those pictures and memories. They do not open her private areas. '
              'If you would rather no grown-up ever could, do not make one: her pictures and memories then come back only with the hand-over words.'),
          const SizedBox(height: 8),
          if (!_showKeepsake)
            OutlinedButton(key: const Key('showKeepsake'), onPressed: () => setState(() => _showKeepsake = true), child: const Text('Show her keepsake words'))
          else ...<Widget>[
            WordGrid(secretToWords(_secrets!.keep), key: const Key('keepsakeWords')),
            const SizedBox(height: 8),
            const NeverAskCard(),
            TextButton(key: const Key('hideKeepsake'), onPressed: () => setState(() => _showKeepsake = false), child: const Text('Hide the words')),
          ],
        ]),
      ),
    );
  }
}

// ================================================================== her tablet: the replacement

enum _TStep { where, key, review, working, done, failed }

/// On the REPLACEMENT tablet, behind the grown-up gate: bring her home, her drawings and her memories back.
class ReplacementTabletScreen extends StatefulWidget {
  const ReplacementTabletScreen({super.key, required this.services, required this.places, this.confirmAdult, this.clock});
  final LocalServices services;
  final BackupPlaces places;
  final Future<bool> Function()? confirmAdult;
  final DateTime Function()? clock;

  @override
  State<ReplacementTabletScreen> createState() => _ReplacementTabletScreenState();
}

class _ReplacementTabletScreenState extends State<ReplacementTabletScreen> {
  bool _allowed = false;
  _TStep _step = _TStep.where;
  String _from = 'folder';
  final TextEditingController _keepPath = TextEditingController();
  final TextEditingController _privPath = TextEditingController();
  final TextEditingController _words = TextEditingController();
  String? _problem;
  BackupSettings _settings = const BackupSettings();
  RestoreEngine? _engine;
  RestorePlan? _keepPlan;
  RestorePlan? _privPlan;
  ChildSecrets? _secrets;
  Uint8List? _keepOnly;
  final List<RestoreReport> _reports = <RestoreReport>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _keepPath.dispose();
    _privPath.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final bool ok = widget.confirmAdult == null ? true : await widget.confirmAdult!();
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop();
      return;
    }
    final BackupSettings s = await BackupJournal(widget.services.area('backup')).settings();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _allowed = true;
    });
  }

  Future<BackupTarget?> _target(BackupKind kind) async {
    if (_from == 'file') return widget.places.targetFromFile((kind == BackupKind.hersKeep ? _keepPath : _privPath).text.trim());
    return widget.places.sourceFor(_from, _settings);
  }

  Future<void> _open() async {
    final String text = _words.text;
    // 28 words: the hand-over from the old tablet. 14 words: a keepsake sheet.
    final WordsResult both = ChildSecrets.readHandover(text);
    final WordsResult one = wordsToSecret(text);
    if (!both.ok && !one.ok) {
      final int n = text.trim().split(RegExp(r'[\s,;.\-_/]+')).where((String w) => w.isNotEmpty).length;
      setState(() => _problem = n == 0
          ? 'Type the hand-over words from the old tablet, or the keepsake words from your paper.'
          : describeWordsProblem(n > kSheetWordCount ? both : one));
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      _engine = RestoreEngine(services: widget.services, clock: widget.clock);
      RestorePlan? priv;
      RestorePlan? keep;
      if (both.ok) {
        final ChildSecrets s = ChildSecrets.fromHandover(both.bytes!);
        _secrets = s;
        final BackupTarget? kt = await _target(BackupKind.hersKeep);
        final BackupTarget? pt = await _target(BackupKind.hersPrivate);
        if (kt == null || pt == null) throw const BackupTargetException('missing', 'place');
        final RestoreInspection ki = await _engine!.inspect(kt, BackupKind.hersKeep, await BackupKeyPair.fromSecret(s.keep, BackupPurpose.keep));
        keep = await _engine!.plan(ki, ownerMap: _engine!.suggestOwnerMap(ki));
        try {
          final RestoreInspection pi = await _engine!.inspect(pt, BackupKind.hersPrivate, await BackupKeyPair.fromSecret(s.private, BackupPurpose.private));
          priv = await _engine!.plan(pi, ownerMap: _engine!.suggestOwnerMap(pi));
        } on RestoreProblem catch (e) {
          if (e.code != 'nothing') rethrow; // no private backup made yet: only the keepsakes come back, and the review says so
        }
        _keepOnly = null;
      } else {
        _keepOnly = one.bytes;
        final BackupTarget? kt = await _target(BackupKind.hersKeep);
        if (kt == null) throw const BackupTargetException('missing', 'place');
        final RestoreInspection ki = await _engine!.inspect(kt, BackupKind.hersKeep, await BackupKeyPair.fromSecret(one.bytes!, BackupPurpose.keep));
        keep = await _engine!.plan(ki, ownerMap: _engine!.suggestOwnerMap(ki));
        _secrets = null;
      }
      if (!mounted) return;
      setState(() {
        _keepPlan = keep;
        _privPlan = priv;
        _busy = false;
        _step = _TStep.review;
      });
    } on RestoreProblem catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.words;
      });
    } on BackupTargetException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = 'Could not read that place. Check it and try again.';
      });
    }
  }

  Future<void> _apply() async {
    setState(() => _step = _TStep.working);
    try {
      final ChildKeyKeeper keeper = ChildKeyKeeper(widget.services.area('childkeys'));
      _reports
        ..clear()
        ..add(await _engine!.apply(_keepPlan!));
      if (_privPlan != null) _reports.add(await _engine!.apply(_privPlan!));
      if (_secrets != null) {
        await keeper.adopt(_secrets!);
      } else if (_keepOnly != null) {
        await keeper.adoptKeep(_keepOnly!);
      }
      if (!mounted) return;
      setState(() {
        _step = _TStep.done;
        _words.clear();
      });
    } on RestoreProblem catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.words;
        _step = _TStep.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    if (!_allowed) return Scaffold(appBar: AppBar(title: const Text('A new tablet for her')), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('A new tablet for her')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: switch (_step) {
            _TStep.where => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Bring her home back', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Her home, her drawings and her memories can come back on this tablet. Where are her backups?'),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _from,
                  onChanged: (String? v) => setState(() => _from = v ?? 'folder'),
                  child: Column(children: <Widget>[
                    const RadioListTile<String>(key: Key('tFromFolder'), value: 'folder', title: Text('In the backup folder on this tablet')),
                    if (widget.places.serverAvailable)
                      const RadioListTile<String>(key: Key('tFromServer'), value: 'server', title: Text('On our family\'s Olive server')),
                    const RadioListTile<String>(key: Key('tFromFile'), value: 'file', title: Text('In files I brought')),
                  ]),
                ),
                if (_from == 'file') ...<Widget>[
                  TextField(key: const Key('tKeepPath'), controller: _keepPath, autocorrect: false,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'The file for her pictures and memories')),
                  const SizedBox(height: 8),
                  TextField(key: const Key('tPrivPath'), controller: _privPath, autocorrect: false,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'The file for her private areas (if you have one)')),
                ],
                const SizedBox(height: 16),
                FilledButton(key: const Key('tWhereNext'), onPressed: () => setState(() => _step = _TStep.key), child: const Text('Next')),
              ]),
            _TStep.key => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Type the words', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Type the hand-over words the old tablet showed ($_handoverCount words). If you no longer have that tablet, '
                    'type her keepsake words from your paper ($_sheetCount words) if you made them. Capital letters and spaces do not matter.'),
                const SizedBox(height: 12),
                TextField(
                    key: const Key('tWords'),
                    controller: _words,
                    minLines: 4,
                    maxLines: 8,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'The words')),
                if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, key: const Key('tProblem'))),
                const SizedBox(height: 12),
                const NeverAskCard(),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  FilledButton(key: const Key('tOpen'), onPressed: _busy ? null : _open, child: const Text('Open her backups')),
                  const SizedBox(width: 8),
                  TextButton(key: const Key('tBack'), onPressed: () => setState(() => _step = _TStep.where), child: const Text('Back')),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
              ]),
            _TStep.review => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('We found her backups', key: const Key('tReviewTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Her pictures, memories and home: ${describeRestorePlan(_keepPlan!)}', key: const Key('tReviewKeep')),
                const SizedBox(height: 8),
                if (_privPlan != null)
                  Text('Her private areas: ${describeRestorePlan(_privPlan!)}', key: const Key('tReviewPrivate'))
                else
                  const Text(
                      'Her private areas (journal, worry box, feelings) are not coming back this time. They can only be opened with the hand-over '
                      'words from the old tablet, and that is on purpose: no grown-up can open them.',
                      key: Key('tReviewNoPrivate')),
                const SizedBox(height: 16),
                Row(children: <Widget>[
                  FilledButton(
                      key: const Key('tPutBack'),
                      onPressed: (_keepPlan!.canApply && (_privPlan?.canApply ?? true)) ? _apply : null,
                      child: const Text('Bring her home back')),
                  const SizedBox(width: 8),
                  TextButton(key: const Key('tCancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ]),
              ]),
            _TStep.working => const Center(
                child: Padding(padding: EdgeInsets.all(32), child: Column(children: <Widget>[CircularProgressIndicator(), SizedBox(height: 12), Text('Bringing her home back and checking it…')]))),
            _TStep.done => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Her home is back', key: const Key('tDoneTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    _reports.every((RestoreReport r) => r.roundTripOk)
                        ? 'Her drawings, memories and settings are here, and we checked every one matches her backup. Nothing was lost.'
                        : 'Some records did not read back the way they were saved.',
                    key: const Key('tDoneProof')),
                const SizedBox(height: 16),
                FilledButton(key: const Key('tDoneButton'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
              ]),
            _TStep.failed => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('This tablet was not changed', key: const Key('tFailedTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_problem ?? 'It could not finish.', key: const Key('tFailedWords')),
                const SizedBox(height: 16),
                FilledButton(key: const Key('tFailedBack'), onPressed: () => setState(() => _step = _TStep.key), child: const Text('Try again')),
              ]),
          },
        ),
      ),
    );
  }
}

final int _sheetCount = kSheetWordCount;
final int _handoverCount = kSheetWordCount * 2;
