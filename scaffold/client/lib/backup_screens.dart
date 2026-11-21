// OLIVE BRANCH — the grown-up's screens for backup and recovery: setup (keep your recovery sheet), "last backup" in
// plain words, the restore wizard, and the replacement-tablet flow that keeps her home, her drawings and her memories.
// UNVERIFIED on a device; widget-tested headless (client/test/backup_screens_test.dart). Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// FOR GROWN-UPS ONLY. Every screen here is reached from a grown-up's settings, or from the grown-up gate on her tablet. None
// is reachable from anything she sees, none shows her a count, a score, a streak, a place or an error, and the engine
// that makes her tablet's backups runs silently (backup_places.dart). A source test keeps these screens out of the child
// shell's imports.
//
// PLAIN WORDS. A word of the recovery sheet is only ever on screen while a grown-up is looking at it, and is never stored
// (the phone keeps only the public half). Olive never asks for the sheet by call, text or email, and the screens that show
// or take it say so every time.
import 'dart:math';

import 'package:flutter/material.dart';

import 'backup_classes.dart';
import 'backup_keys.dart';
import 'backup_places.dart';
import 'backup_service.dart';
import 'backup_targets.dart';
import 'backup_widgets.dart';
import 'local_services.dart';
import 'restore_engine.dart';

// ================================================================== the hub

/// "Backup and recovery" in a grown-up's settings.
class BackupHubScreen extends StatefulWidget {
  const BackupHubScreen({super.key, required this.services, required this.places, this.confirmAdult, this.clock});
  final LocalServices services;
  final BackupPlaces places;

  /// Asks the grown-up for their PIN before a sheet is shown. Null means no extra check (the screen itself is behind one).
  final Future<bool> Function()? confirmAdult;
  final DateTime Function()? clock;

  @override
  State<BackupHubScreen> createState() => _BackupHubScreenState();
}

class _BackupHubScreenState extends State<BackupHubScreen> {
  BackupSettings _settings = const BackupSettings();
  BackupLast? _last;
  BackupLast? _try;
  SheetRecord? _sheet;
  bool _loaded = false;
  bool _busy = false;
  String? _note;
  late final BackupService _svc = BackupService(services: widget.services, clock: widget.clock);
  int get _now => (widget.clock ?? DateTime.now)().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final BackupJournal j = _svc.journal;
    final BackupSettings s = await j.settings();
    final BackupLast? last = await j.newestSuccess(BackupKind.family);
    final BackupLast? tr = await j.lastTry(BackupKind.family);
    final SheetRecord? sh = await j.familySheet();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _last = last;
      _try = tr;
      _sheet = sh;
      _loaded = true;
    });
  }

  Future<void> _save(BackupSettings s) async {
    await _svc.journal.saveSettings(s);
    await _load();
  }

  Future<void> _backUpNow() async {
    final SheetRecord? sheet = _sheet;
    if (sheet == null || sheet.confirmedMs == null) {
      await _makeSheet();
      return;
    }
    setState(() {
      _busy = true;
      _note = null;
    });
    final Map<String, BackupDestination> d = widget.places.destinations(_settings);
    int ok = 0, failed = 0;
    bool nothing = false;
    for (final MapEntry<String, BackupDestination> e in d.entries) {
      if (e.key == 'folder' && !_settings.folderOn) continue;
      if (e.key == 'server' && !_settings.serverOn) continue;
      final BackupOutcome o = await _svc.run(BackupKind.family, e.value, sheet.publicKey);
      if (o.ok) {
        ok++;
        if (o.nothingToBackUp) nothing = true;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = failed > 0
          ? 'That did not finish. Your earlier backup is safe, and nothing on this phone was changed.'
          : nothing
              ? 'There is nothing to back up yet. It will back up by itself once there is.'
              : ok > 0
                  ? 'Backed up, and read back to check it.'
                  : 'Choose a place first.';
    });
    await _load();
  }

  Future<void> _makeSheet() async {
    final bool? done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => RecoverySheetScreen(service: _svc, confirmAdult: widget.confirmAdult)));
    if (done == true) await _load();
  }

  Future<void> _checkPaper() async {
    // Checking an existing sheet means typing it, so it is the same words-taking step a restore uses, without a restore.
    final bool? ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute<bool>(builder: (_) => CheckPaperScreen(service: _svc)));
    if (ok == true) await _load();
  }

  Future<void> _newSheet() async {
    final bool? sure = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
              title: const Text('Make a new recovery sheet?'),
              content: const Text(
                  'Backups from now on will need the NEW sheet. Your old backups still need the OLD sheet, so keep it until you '
                  'no longer need them. If someone else has seen the old sheet, also remove old backup copies from wherever '
                  'they are kept.'),
              actions: <Widget>[
                TextButton(key: const Key('newSheetCancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('Keep my sheet')),
                TextButton(key: const Key('newSheetConfirm'), onPressed: () => Navigator.of(c).pop(true), child: const Text('Make a new one')),
              ],
            ));
    if (sure == true) await _makeSheet();
  }

  Future<void> _saveCopy() async {
    final String? name = await widget.places.saveCopyFile(BackupKind.family, _settings);
    if (!mounted) return;
    setState(() => _note = name == null
        ? 'There is no backup to save yet. Back up first.'
        : 'Saved as $name in the backup folder. Copy that one file somewhere safe, such as a USB stick.');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ColorScheme c = Theme.of(context).colorScheme;
    if (!_loaded) return Scaffold(appBar: AppBar(title: const Text('Backup and recovery')), body: const Center(child: CircularProgressIndicator()));
    final BackupStatusView v = describeBackupStatus(settings: _settings, last: _last, lastTry: _try, sheet: _sheet, nowMs: _now);
    final bool hasSheet = _sheet != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and recovery')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Text(
              'A backup keeps a sealed copy of your family\'s records away from this phone. It is sealed here, before it goes '
              'anywhere, so nobody who keeps it can read it.',
              style: t.bodyMedium),
          const SizedBox(height: 16),
          Card(
            key: const Key('backupStatusCard'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Icon(switch (v.mood) {
                    BackupMood.ok => Icons.check_circle_outline,
                    BackupMood.behind => Icons.schedule,
                    BackupMood.failed => Icons.error_outline,
                    _ => Icons.cloud_off_outlined,
                  }, color: v.mood == BackupMood.ok ? c.primary : c.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text(v.headline, key: const Key('backupHeadline'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 6),
                Text(v.detail, key: const Key('backupDetail'), style: t.bodyMedium),
                if (v.action != null) ...<Widget>[
                  const SizedBox(height: 10),
                  FilledButton(
                      key: const Key('backupNowButton'),
                      onPressed: _busy ? null : _backUpNow,
                      child: Text(!hasSheet ? 'Set up backup' : v.action!)),
                ] else if (hasSheet) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton(key: const Key('backupNowButton'), onPressed: _busy ? null : _backUpNow, child: const Text('Back up now')),
                ],
                if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, key: const Key('backupNote'))),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Where it goes', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SwitchListTile(
              key: const Key('placeFolder'),
              title: const Text('A folder on this phone'),
              subtitle: const Text('You can copy it to a drive or another phone. Sealed, so it is safe to move.'),
              value: _settings.folderOn,
              onChanged: (bool x) => _save(_settings.copyWith(folderOn: x))),
          SwitchListTile(
              key: const Key('placeServer'),
              title: const Text('Your family\'s Olive server'),
              subtitle: Text(widget.places.serverAvailable
                  ? 'Kept sealed. The server cannot read it.'
                  : 'Not available. It needs a server of your own that this phone is connected to.'),
              value: _settings.serverOn && widget.places.serverAvailable,
              onChanged: widget.places.serverAvailable ? (bool x) => _save(_settings.copyWith(serverOn: x)) : null),
          SwitchListTile(
              key: const Key('placeAuto'),
              title: const Text('Back up by itself'),
              subtitle: const Text('About once a day, quietly, when this phone can reach the place.'),
              value: _settings.auto,
              onChanged: (bool x) => _save(_settings.copyWith(auto: x))),
          const SizedBox(height: 12),
          Text('Your recovery sheet', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (!hasSheet) ...<Widget>[
            const Text('You do not have one yet. It is a short list of words on paper, and it is the only thing that can open '
                'your backup. Make it before you need it.', key: Key('noSheetText')),
            const SizedBox(height: 8),
            FilledButton(key: const Key('makeSheetButton'), onPressed: _makeSheet, child: const Text('Make my recovery sheet')),
          ] else ...<Widget>[
            Text(
                'Sheet ${_sheet!.sheetId}, made ${agoWords(_now, _sheet!.madeMs)}. '
                '${_sheet!.confirmedMs == null ? 'Not checked yet.' : 'Checked ${agoWords(_now, _sheet!.confirmedMs!)}.'}',
                key: const Key('sheetLine')),
            if (sheetReminderDue(_sheet, _now))
              const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('It has been a while. Find your paper and make sure you can still read it.', key: Key('sheetReminder'))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: <Widget>[
              OutlinedButton(key: const Key('checkPaperButton'), onPressed: _checkPaper, child: const Text('Check my paper')),
              OutlinedButton(key: const Key('newSheetButton'), onPressed: _newSheet, child: const Text('Make a new sheet')),
            ]),
          ],
          const SizedBox(height: 16),
          Text('Bring a backup back', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('For a new phone, or after something went wrong. Nothing on this phone is overwritten: where a backup and this '
              'phone differ, the newer is used and the other is kept.'),
          const SizedBox(height: 8),
          FilledButton.tonal(
              key: const Key('restoreButton'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RestoreWizardScreen(services: widget.services, places: widget.places, clock: widget.clock))),
              child: const Text('Restore from a backup')),
          if (hasSheet) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(key: const Key('saveCopyButton'), onPressed: _saveCopy, child: const Text('Save one file I can carry')),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            key: const Key('leftOutTile'),
            title: const Text('What is not in a backup'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[for (final String w in kLeftOutWords) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(w))],
          ),
        ]),
      ),
    );
  }
}

// ================================================================== making the sheet

/// "Write down your recovery sheet", then "Let's check your paper". Pops true when the sheet was written and checked.
class RecoverySheetScreen extends StatefulWidget {
  const RecoverySheetScreen({super.key, required this.service, this.confirmAdult, this.random});
  final BackupService service;
  final Future<bool> Function()? confirmAdult;
  final Random? random;

  @override
  State<RecoverySheetScreen> createState() => _RecoverySheetScreenState();
}

enum _SheetStep { gate, show, check, done }

class _RecoverySheetScreenState extends State<RecoverySheetScreen> {
  _SheetStep _step = _SheetStep.gate;
  RecoverySheet? _sheet;
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    final Future<bool> Function()? gate = widget.confirmAdult;
    final bool ok = gate == null ? true : await gate();
    if (!mounted) return;
    if (!ok) {
      Navigator.of(context).pop(false);
      return;
    }
    final RecoverySheet s = await RecoverySheet.make(BackupPurpose.family, random: widget.random);
    if (!mounted) return;
    setState(() {
      _sheet = s;
      _step = _SheetStep.show;
    });
  }

  Future<void> _check() async {
    final RecoverySheet s = _sheet!;
    if (!s.echoMatches(_first.text, _last.text)) {
      setState(() => _wrong = true);
      return;
    }
    // Only now does the phone keep the PUBLIC half. A sheet that was never checked is never used to lock a backup, so a
    // backup can never be locked to words nobody has.
    await widget.service.rememberFamilySheet(s);
    await widget.service.confirmFamilySheet();
    if (!mounted) return;
    setState(() {
      _wrong = false;
      _step = _SheetStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final RecoverySheet? s = _sheet;
    return Scaffold(
      appBar: AppBar(title: const Text('Your recovery sheet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: switch (_step) {
            _SheetStep.gate => const Center(child: CircularProgressIndicator()),
            _SheetStep.show => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Write these words on paper', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('They bring your family\'s records back if every phone is lost. Write them in order, with the number '
                    'beside each, and keep the paper with your important papers.'),
                const SizedBox(height: 12),
                WordGrid(s!.words, key: const Key('sheetWords')),
                const SizedBox(height: 8),
                Text('Sheet ${s.sheetId}. Write that on the paper too, so you can tell sheets apart.', key: const Key('sheetIdText')),
                const SizedBox(height: 8),
                const Text(kSheetHouseKeyWords),
                const SizedBox(height: 12),
                const NeverAskCard(),
                const SizedBox(height: 16),
                FilledButton(
                    key: const Key('writtenDownButton'),
                    onPressed: () => setState(() => _step = _SheetStep.check),
                    child: const Text('I have written it down')),
              ]),
            _SheetStep.check => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Let\'s check your paper', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Type the first word and the last word from your paper. This only checks your writing. Nothing is sent anywhere.'),
                const SizedBox(height: 12),
                TextField(
                    key: const Key('echoFirst'),
                    controller: _first,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'First word', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    key: const Key('echoLast'),
                    controller: _last,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Last word', border: OutlineInputBorder())),
                if (_wrong)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Those do not match your sheet. Look at your paper again and check the first and last words.',
                          key: Key('echoWrong'))),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  FilledButton(key: const Key('echoCheckButton'), onPressed: _check, child: const Text('Check')),
                  const SizedBox(width: 8),
                  TextButton(
                      key: const Key('showAgainButton'),
                      onPressed: () => setState(() {
                            _wrong = false;
                            _step = _SheetStep.show;
                          }),
                      child: const Text('Show the words again')),
                ]),
              ]),
            _SheetStep.done => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Your recovery sheet is ready', key: const Key('sheetReady'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Backups from now on are locked to it. Keep the paper safe, and look at it twice a year to make sure you can still read it.'),
                const SizedBox(height: 16),
                FilledButton(key: const Key('sheetDoneButton'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
              ]),
          },
        ),
      ),
    );
  }
}

/// Checking an existing paper: type all the words, and be told if they are the sheet this phone knows (by its public half).
class CheckPaperScreen extends StatefulWidget {
  const CheckPaperScreen({super.key, required this.service});
  final BackupService service;
  @override
  State<CheckPaperScreen> createState() => _CheckPaperScreenState();
}

class _CheckPaperScreenState extends State<CheckPaperScreen> {
  final TextEditingController _words = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final WordsResult r = wordsToSecret(_words.text);
    if (!r.ok) {
      setState(() => _problem = describeWordsProblem(r));
      return;
    }
    final SheetRecord? have = await widget.service.journal.familySheet();
    final BackupKeyPair kp = await BackupKeyPair.fromSecret(r.bytes!, BackupPurpose.family);
    if (have == null || sheetIdOf(kp.publicKey) != have.sheetId || !_same(kp.publicKey, have.publicKey)) {
      if (!mounted) return;
      setState(() => _problem = 'Those words are real, but they are not the sheet this phone is making backups for. '
          'Check you have the right paper.');
      return;
    }
    await widget.service.confirmFamilySheet();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Check my paper')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('Type the words from your paper, in order. This only checks them against this phone. Nothing is sent anywhere.'),
              const SizedBox(height: 12),
              TextField(
                  key: const Key('checkWords'),
                  controller: _words,
                  minLines: 3,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'The words on your paper')),
              if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, key: const Key('checkProblem'))),
              const SizedBox(height: 12),
              const NeverAskCard(),
              const SizedBox(height: 12),
              FilledButton(key: const Key('checkPaperGo'), onPressed: _check, child: const Text('Check')),
            ]),
          ),
        ),
      );
}

// ================================================================== the restore wizard

enum _RStep { where, words, review, working, done, failed }

/// Restore the family's records onto this phone: where, the words, a plain review, the restore, and the proof.
class RestoreWizardScreen extends StatefulWidget {
  const RestoreWizardScreen({super.key, required this.services, required this.places, this.clock});
  final LocalServices services;
  final BackupPlaces places;
  final DateTime Function()? clock;

  @override
  State<RestoreWizardScreen> createState() => _RestoreWizardScreenState();
}

class _RestoreWizardScreenState extends State<RestoreWizardScreen> {
  _RStep _step = _RStep.where;
  String _from = 'folder';
  final TextEditingController _path = TextEditingController();
  final TextEditingController _words = TextEditingController();
  String? _problem;
  BackupSettings _settings = const BackupSettings();
  RestoreEngine? _engine;
  RestorePlan? _plan;
  RestoreReport? _report;
  bool _busy = false;
  int get _now => (widget.clock ?? DateTime.now)().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    BackupJournal(widget.services.area('backup')).settings().then((BackupSettings s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  void dispose() {
    _path.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<BackupTarget?> _target() async {
    if (_from == 'file') return widget.places.targetFromFile(_path.text.trim());
    return widget.places.sourceFor(_from, _settings);
  }

  Future<void> _open() async {
    final WordsResult w = wordsToSecret(_words.text);
    if (!w.ok) {
      setState(() => _problem = describeWordsProblem(w));
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final BackupTarget? t = await _target();
      if (t == null) {
        setState(() {
          _busy = false;
          _problem = 'That place is not available here.';
        });
        return;
      }
      final BackupKeyPair key = await BackupKeyPair.fromSecret(w.bytes!, BackupPurpose.family);
      _engine = RestoreEngine(services: widget.services, clock: widget.clock);
      final RestoreInspection i = await _engine!.inspect(t, BackupKind.family, key);
      final RestorePlan plan = await _engine!.plan(i, ownerMap: _engine!.suggestOwnerMap(i));
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _busy = false;
        _step = _RStep.review;
      });
    } on RestoreProblem catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.words;
      });
    } on BackupTargetException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.code == 'offline' ? 'Could not reach that place. Check the connection and try again.' : 'Could not read that place. Check it and try again.';
      });
    }
  }

  Future<void> _apply() async {
    setState(() => _step = _RStep.working);
    try {
      final RestoreReport r = await _engine!.apply(_plan!);
      if (!mounted) return;
      setState(() {
        _report = r;
        _step = _RStep.done;
        _words.clear();
      });
    } on RestoreProblem catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.words;
        _step = _RStep.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final RestorePlan? plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore from a backup')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: switch (_step) {
            _RStep.where => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Where is the backup?', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _from,
                  onChanged: (String? v) => setState(() => _from = v ?? 'folder'),
                  child: Column(children: <Widget>[
                    const RadioListTile<String>(key: Key('fromFolder'), value: 'folder', title: Text('In the backup folder on this phone')),
                    if (widget.places.serverAvailable)
                      const RadioListTile<String>(key: Key('fromServer'), value: 'server', title: Text('On our family\'s Olive server')),
                    const RadioListTile<String>(key: Key('fromFile'), value: 'file', title: Text('In a file I brought')),
                  ]),
                ),
                if (_from == 'file')
                  TextField(
                      key: const Key('filePath'),
                      controller: _path,
                      autocorrect: false,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Where the file is on this phone')),
                const SizedBox(height: 16),
                FilledButton(key: const Key('whereNext'), onPressed: () => setState(() => _step = _RStep.words), child: const Text('Next')),
              ]),
            _RStep.words => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Type your recovery sheet', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Type all $kSheetWordCount words from your paper, in order. Capital letters and spaces do not matter.'),
                const SizedBox(height: 12),
                TextField(
                    key: const Key('restoreWords'),
                    controller: _words,
                    minLines: 3,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'The words on your paper')),
                if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, key: const Key('restoreProblem'))),
                const SizedBox(height: 12),
                const NeverAskCard(),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  FilledButton(key: const Key('wordsNext'), onPressed: _busy ? null : _open, child: const Text('Open my backup')),
                  const SizedBox(width: 8),
                  TextButton(key: const Key('wordsBack'), onPressed: () => setState(() => _step = _RStep.where), child: const Text('Back')),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
              ]),
            _RStep.review => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('We found your backup', key: const Key('reviewTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Made ${agoWords(_now, plan!.inspection.manifest.createdMs)}${plan.inspection.manifest.from.isEmpty ? '' : ' on ${plan.inspection.manifest.from}'}.',
                    key: const Key('reviewWhen')),
                const SizedBox(height: 8),
                Text(describeRestorePlan(plan), key: const Key('reviewPlan')),
                if (plan.inspection.olderThanKnown)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('This phone has made a newer backup than this one. If you expected a newer one, check the place it is kept before you go on.',
                          key: Key('reviewOlder'))),
                if (plan.inspection.skippedDamaged > 0)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('The newest backup was damaged, so the one before it is being used.', key: Key('reviewDamaged'))),
                if (plan.inspection.manifest.unreadable.isNotEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('When this backup was made, some things on that phone could not be read, so they are not in it.')),
                const SizedBox(height: 8),
                const Text('Putting this back brings your records. It does not add this phone to your family: that is a separate step.'),
                const SizedBox(height: 16),
                Row(children: <Widget>[
                  FilledButton(key: const Key('putBackButton'), onPressed: plan.canApply ? _apply : null, child: const Text('Put it back')),
                  const SizedBox(width: 8),
                  TextButton(key: const Key('reviewCancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ]),
                if (!plan.canApply) Padding(padding: const EdgeInsets.only(top: 8), child: Text(plan.blocked.join(' '), key: const Key('reviewBlocked'))),
              ]),
            _RStep.working => const Center(
                child: Padding(padding: EdgeInsets.all(32), child: Column(children: <Widget>[CircularProgressIndicator(), SizedBox(height: 12), Text('Putting your records back and checking them…')]))),
            _RStep.done => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Your records are back', key: const Key('doneTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    _report!.roundTripOk
                        ? 'We read every record back and checked it matches. Nothing was lost.'
                        : 'Some records did not read back the way they were saved.',
                    key: const Key('doneProof')),
                if (_report!.setAside > 0)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Where this phone and the backup had different versions of the same thing, the newer one is in use and the other is kept safely.')),
                const SizedBox(height: 16),
                FilledButton(key: const Key('doneButton'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
              ]),
            _RStep.failed => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('This phone was not changed', key: const Key('failedTitle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_problem ?? 'The restore could not finish.', key: const Key('failedWords')),
                const SizedBox(height: 16),
                FilledButton(key: const Key('failedBack'), onPressed: () => setState(() => _step = _RStep.words), child: const Text('Try again')),
              ]),
          },
        ),
      ),
    );
  }
}

