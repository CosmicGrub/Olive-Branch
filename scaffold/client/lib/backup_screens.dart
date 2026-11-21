// OLIVE BRANCH — the backup screens, in a grown-up's own words. UNVERIFIED on a device; covered by flutter test only.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// WHO SEES THEM. A grown-up, on a grown-up's phone (More > Back up your family's records) or in Guardian mode on her
// tablet (behind the PIN and the biometric). Nothing here is ever shown to a child, and no file that draws a child's
// screen imports this one (a source test keeps it so).
//
// WHAT THEY SAY. Plain, short, no jargon: "recovery sheet", "backup", "folder", "your family's server". No pre-written
// medical or legal advice. The two honest facts a person needs are said where they matter: the paper sheet is a house
// key (whoever holds it and a copy of the backup can read it), and a backup in only one place is lost with that place.
import 'package:flutter/material.dart';

import 'backup_crypto.dart';
import 'backup_engine.dart';
import 'backup_merge.dart' show ConflictChoice;
import 'backup_restore.dart';
import 'backup_server.dart';
import 'backup_service.dart';
import 'backup_sink.dart';
import 'backup_words.dart';

/// Everything the screens need from the app, so a test can give them a phone made of memory.
class BackupHost {
  BackupHost({
    required this.service,
    required this.defaultFolder,
    this.openFolder,
    this.identity,
    this.now,
  });
  final BackupService service;

  /// A folder on this phone the family copies backups out of (null when the phone has no place to give).
  final Future<String?> Function() defaultFolder;

  /// Test seam: reads a folder as a place to restore from. The real one opens the folder.
  final Future<BackupSource> Function(String path)? openFolder;

  /// Who this signed-in grown-up is on the server: their id and this phone's id (for the server restore).
  final Future<({String userId, String deviceId})?> Function()? identity;
  final DateTime Function()? now;

  BackupKind get kind => service.kind;
  bool get isTablet => service.role == BackupRole.child;
}

/// The words the screens use. One place, so a test can check every line for jargon and for what must be said.
class BackupCopy {
  static String title(BackupKind k) => k == BackupKind.family ? "Back up your family's records" : 'Back up her home and keepsakes';

  static String whatItIs(BackupKind k) => k == BackupKind.family
      ? "Olive locks a copy of your family's records on this phone and keeps it where you choose. Olive cannot open it, "
          'and neither can your server. Only your recovery sheet can.'
      : 'Olive locks a copy of her home and the things that are hers, and keeps it where you choose. It never takes her '
          'journal, her worry box or her feelings. Only the keepsake sheet can open it, and only on her tablet.';

  static String headline(BackupStatus s, DateTime now) {
    switch (s.attention) {
      case BackupAttention.notSetUp:
        return s.kind == BackupKind.family ? "Your family's records are not backed up yet." : 'Her home and keepsakes are not backed up yet.';
      case BackupAttention.sheetNotChecked:
        return 'Your recovery sheet was not checked against the paper. Make a new one so you can be sure.';
      case BackupAttention.lastTryFailed:
        return 'The last backup did not finish. ${failureWords(s.lastFailureCode)}';
      case BackupAttention.overdue:
        return s.lastOk == null ? 'No backup has been made yet.' : 'The last backup was ${ago(now, s.lastOk!.atMs)}. Time for a new one.';
      case BackupAttention.sheetOld:
        return 'Take a look at your paper recovery sheet. Is it still safe, and can you read it?';
      case BackupAttention.fine:
        return 'Backed up ${ago(now, s.lastOk!.atMs)}, to ${s.lastOk!.destination}.';
    }
  }

  static String failureWords(String? code) => switch (code) {
        'unreachable' => 'Olive could not reach the place. It will try again.',
        'full' => 'There is no room left there.',
        'refused' => 'The place said no.',
        'signed_out' => 'This phone needs to sign in again.',
        'paused' => "Your access to the family's server is paused.",
        'no_vault' => "Your family's server has no backup set up yet.",
        'not_enabled' => "Your family's server does not keep backups.",
        'damaged' => 'What was saved did not check out, so it was not counted.',
        _ => 'Please try again.',
      };

  static String ago(DateTime now, int atMs) {
    final Duration d = now.difference(DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: now.isUtc));
    if (d.inMinutes < 2) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} minutes ago';
    if (d.inHours < 24) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
    return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
  }

  static const String sheetIntro =
      'Olive will show you 18 words. They are your recovery sheet. Write them on paper, in order, and keep the paper '
      'somewhere safe, like your important papers.\n\n'
      'Anyone who has this paper and a copy of your backup can read your records, so treat it like the key to a safe. '
      'Do not take a photo of it or save it on this phone. Only type these words in Olive. Olive will never ask for them '
      'by call, text or email.';

  static const String sheetWrite = 'Write the words down in this order. Olive will not show them again.';
  static const String sheetCheckAsk = 'Now check the paper. Type the first word and the last word from your paper.';
  static const String sheetCheckWrong = 'Those are not the first and last words. Look at your paper and try again.';
  static const String sheetDone = 'Your recovery sheet is saved on paper. Next, choose where your backups go.';

  static const String oneCopyWarning =
      'A backup that is only on this phone is lost with this phone. Copy the folder to a computer or a memory card now '
      'and then, or turn on your family\'s server.';

  static String sheetProblem(SheetProblem p, int? badIndex) => switch (p) {
        SheetProblem.wrongCount => 'There should be 18 words. Check that none are missing.',
        SheetProblem.unknownWord => 'Word number ${(badIndex ?? 0) + 1} is not one of Olive\'s words. Check how it is spelled.',
        SheetProblem.checkFailed => 'The words do not match each other. One may be wrong, swapped or missing. Check the paper.',
      };

  static String outcomeWords(SheetOutcome o) => switch (o) {
        SheetOutcome.ok => '',
        SheetOutcome.wrongCount => sheetProblem(SheetProblem.wrongCount, null),
        SheetOutcome.unknownWord => 'One word is not one of Olive\'s words. Check how it is spelled.',
        SheetOutcome.checkFailed => sheetProblem(SheetProblem.checkFailed, null),
        SheetOutcome.resting => 'Too many tries. Rest for a few minutes, then try again.',
      };

  static String restoreProblem(RestoreProblem p, {int? restLeftMs}) => switch (p) {
        RestoreProblem.nothingFound => 'No backup was found for this sheet there. Check the sheet and the place.',
        RestoreProblem.damaged => 'A backup was found, but it did not check out. It may be damaged. Try another copy.',
        RestoreProblem.resting => 'Too many wrong tries. Rest ${((restLeftMs ?? 900000) / 60000).ceil()} minutes, then try again.',
        RestoreProblem.older => 'This backup is older than the last one on this phone. If you meant to use it, say so below.',
        RestoreProblem.notCleared => 'This is still waiting. Nothing has been changed.',
        RestoreProblem.stopped => 'Someone in your family stopped this. Nothing has been changed.',
        RestoreProblem.notPaired => 'Connect this tablet to a grown-up first, then bring her things back.',
        RestoreProblem.wrongChild => 'These keepsakes belong to a different child. Nothing has been changed.',
        RestoreProblem.couldNotWrite => 'Olive could not finish, so it put everything back as it was. Nothing has been lost. Try again.',
        RestoreProblem.wrongDevice => 'This kind of backup cannot be opened on this device.',
      };

  static const String restoreIsRecordsOnly =
      "This brings back your records. It does not make this phone one of your family's. That is a separate step that "
      'another parent has to say yes to.';

  static String phaseWords(ServerRestorePhase p, {int? waitHours}) => switch (p) {
        ServerRestorePhase.waiting =>
          "Your family's server is holding this for ${waitHours ?? 72} hours, so nobody else can take your records. Anyone in "
              'your family can stop it from their phone.',
        ServerRestorePhase.needsYes => 'Waiting for another parent to say yes on their phone.',
        ServerRestorePhase.ready => 'Ready. Your records can be brought back now.',
        ServerRestorePhase.tokenIssued => 'Ready. Your records can be brought back now.',
        ServerRestorePhase.cancelled => 'Someone in your family stopped this.',
        ServerRestorePhase.completed => 'This was finished.',
        ServerRestorePhase.expired => 'This ran out. Start again if you still need it.',
        ServerRestorePhase.none => 'No request has been made.',
      };
}

DateTime _now(BackupHost h) => h.now?.call() ?? DateTime.now();

// =====================================================================================================================
// the main screen

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.host});
  final BackupHost host;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupStatus? _status;
  String _result = '';
  bool _busy = false;

  BackupService get _svc => widget.host.service;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final BackupStatus s = await _svc.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _go(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _setUp() async {
    final bool? done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (BuildContext c) => SheetSetupScreen(host: widget.host)));
    if (done == true) await _refresh();
  }

  Future<void> _useFolder() => _go(() async {
        final String? path = await widget.host.defaultFolder();
        if (path == null) {
          setState(() => _result = 'This phone has no folder Olive can use.');
          return;
        }
        await _svc.chooseFolder(path);
      });

  Future<void> _backUp() => _go(() async {
        try {
          final BackupReport r = await _svc.backUpNow();
          final List<String> lines = <String>[
            for (final SinkReport s in r.sinks)
              s.ok ? 'Saved to ${s.label}.' : 'Could not save to ${s.label}. ${BackupCopy.failureWords(s.code)}',
          ];
          setState(() => _result = '${lines.join('\n')}\n${r.areas} kinds of records checked and saved.');
        } on BackupNotSetUp {
          setState(() => _result = 'Set up your recovery sheet first.');
        } on StateError {
          setState(() => _result = 'Choose where backups go first.');
        }
      });

  Future<void> _server(bool on) async {
    if (!on) {
      await _go(_svc.turnOffServer);
      return;
    }
    final ({String words, String pin})? got = await showDialog<({String words, String pin})>(
        context: context, builder: (BuildContext c) => const _ServerOnDialog());
    if (got == null) return;
    await _go(() async {
      final SheetParse p = RecoveryKey.parse(got.words);
      if (!p.ok) {
        setState(() => _result = BackupCopy.sheetProblem(p.problem!, p.badIndex));
        return;
      }
      try {
        await _svc.turnOnServer(key: p.key!, pin: got.pin);
      } on BackupSinkException catch (e) {
        setState(() => _result = e.detail == 'other_sheet'
            ? 'That is not the sheet for this phone\'s backups.'
            : BackupCopy.failureWords(e.code));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final BackupStatus? s = _status;
    final BackupKind kind = widget.host.kind;
    return Scaffold(
      appBar: AppBar(title: Text(BackupCopy.title(kind))),
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: <Widget>[
                Text(BackupCopy.whatItIs(kind), key: const Key('backupWhatItIs')),
                const SizedBox(height: 16),
                _StatusCard(text: BackupCopy.headline(s, _now(widget.host)), urgent: s.attention != BackupAttention.fine),
                const SizedBox(height: 16),
                if (!s.setUp)
                  FilledButton(key: const Key('backupSetUp'), onPressed: _busy ? null : _setUp, child: const Text('Set up a backup'))
                else ...<Widget>[
                  Text('Where backups go', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('backupFolderTile'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('A folder on this phone'),
                    subtitle: Text(s.folderSet ? 'On' : 'Off'),
                    trailing: s.folderSet
                        ? TextButton(onPressed: _busy ? null : () => _go(() => _svc.chooseFolder(null)), child: const Text('Turn off'))
                        : FilledButton.tonal(onPressed: _busy ? null : _useFolder, child: const Text('Turn on')),
                  ),
                  if (_svc.canUseServer)
                    SwitchListTile(
                      key: const Key('backupServerSwitch'),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.cloud_outlined),
                      title: const Text("Your family's server"),
                      subtitle: const Text('A locked copy. The server cannot read it.'),
                      value: s.serverOn,
                      onChanged: _busy ? null : _server,
                    ),
                  if (!s.hasPlace) const Text('Choose at least one place.', key: Key('backupNoPlace')),
                  if (s.folderSet && !s.serverOn) const Padding(padding: EdgeInsets.only(top: 8), child: Text(BackupCopy.oneCopyWarning, key: Key('backupOneCopy'))),
                  const SizedBox(height: 16),
                  FilledButton(
                      key: const Key('backupNow'), onPressed: (_busy || !s.hasPlace) ? null : _backUp, child: Text(_busy ? 'Working...' : 'Back up now')),
                  if (_result.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_result, key: const Key('backupResult'))),
                  const Divider(height: 40),
                  if (s.attention == BackupAttention.sheetOld)
                    FilledButton.tonal(
                        key: const Key('backupLooked'),
                        onPressed: () => _go(_svc.sheetLookedAt),
                        child: const Text('I looked at my paper. It is fine.')),
                  TextButton(key: const Key('backupNewSheet'), onPressed: _busy ? null : _setUp, child: const Text('Make a new recovery sheet')),
                  const Text('A new sheet protects future backups. Old backups still open with the old sheet. Remove old copies you no longer want.'),
                ],
                const Divider(height: 40),
                Text('Bring records back', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                OutlinedButton(
                    key: const Key('backupRestore'),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext c) => RestoreScreen(host: widget.host))),
                    child: Text(widget.host.isTablet ? 'Bring back her home and keepsakes' : 'Bring my records back')),
              ]),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.text, required this.urgent});
  final String text;
  final bool urgent;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      key: const Key('backupStatus'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: urgent ? c.tertiaryContainer : c.primaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(children: <Widget>[
        Icon(urgent ? Icons.info_outline : Icons.check_circle_outline),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _ServerOnDialog extends StatefulWidget {
  const _ServerOnDialog();
  @override
  State<_ServerOnDialog> createState() => _ServerOnDialogState();
}

class _ServerOnDialogState extends State<_ServerOnDialog> {
  final TextEditingController _words = TextEditingController(), _pin = TextEditingController();
  @override
  void dispose() {
    _words.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("Keep a copy on your family's server"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('Type your 18 recovery words, and your own PIN.'),
            const SizedBox(height: 12),
            TextField(key: const Key('serverWords'), controller: _words, minLines: 3, maxLines: 5, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Your 18 words')),
            const SizedBox(height: 12),
            TextField(key: const Key('serverPin'), controller: _pin, obscureText: true, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Your PIN')),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('serverOnGo'), onPressed: () => Navigator.pop(context, (words: _words.text, pin: _pin.text)), child: const Text('Turn on')),
        ],
      );
}

// =====================================================================================================================
// the sheet

class SheetSetupScreen extends StatefulWidget {
  const SheetSetupScreen({super.key, required this.host});
  final BackupHost host;
  @override
  State<SheetSetupScreen> createState() => _SheetSetupState();
}

enum _SheetStage { intro, words, check, done }

class _SheetSetupState extends State<SheetSetupScreen> {
  _SheetStage _stage = _SheetStage.intro;
  RecoveryKey? _key;
  final TextEditingController _first = TextEditingController(), _last = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    final RecoveryKey k = await widget.host.service.setUp();
    if (mounted) {
      setState(() {
        _key = k;
        _stage = _SheetStage.words;
      });
    }
  }

  Future<void> _check() async {
    final bool ok = await widget.host.service.confirmSheet(_key!, _first.text, _last.text);
    if (!mounted) return;
    setState(() {
      _error = ok ? '' : BackupCopy.sheetCheckWrong;
      if (ok) {
        _stage = _SheetStage.done;
        _key = null; // the words are gone from memory the moment the paper is checked
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final BackupKind kind = widget.host.kind;
    return Scaffold(
      appBar: AppBar(title: Text(kind == BackupKind.family ? 'Your recovery sheet' : 'Her keepsake sheet')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
          if (_stage == _SheetStage.intro) ...<Widget>[
            const Text(BackupCopy.sheetIntro, key: Key('sheetIntro')),
            const SizedBox(height: 20),
            FilledButton(key: const Key('sheetShow'), onPressed: _show, child: const Text('Show my 18 words')),
          ],
          if (_stage == _SheetStage.words) ...<Widget>[
            const Text(BackupCopy.sheetWrite),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, key: const Key('sheetWords'), children: <Widget>[
              for (int i = 0; i < _key!.words.length; i++)
                Chip(label: Text('${i + 1}. ${_key!.words[i]}', style: const TextStyle(fontSize: 18))),
            ]),
            const SizedBox(height: 20),
            FilledButton(key: const Key('sheetWritten'), onPressed: () => setState(() => _stage = _SheetStage.check), child: const Text('I have written them down')),
          ],
          if (_stage == _SheetStage.check) ...<Widget>[
            const Text(BackupCopy.sheetCheckAsk),
            const SizedBox(height: 12),
            TextField(key: const Key('sheetFirst'), controller: _first, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'First word')),
            const SizedBox(height: 12),
            TextField(key: const Key('sheetLast'), controller: _last, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Last word')),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, key: const Key('sheetError'))),
            const SizedBox(height: 16),
            FilledButton(key: const Key('sheetCheck'), onPressed: _check, child: const Text('Check')),
            TextButton(onPressed: () => setState(() => _stage = _SheetStage.words), child: const Text('Show the words again')),
          ],
          if (_stage == _SheetStage.done) ...<Widget>[
            const Text(BackupCopy.sheetDone, key: Key('sheetDone')),
            const SizedBox(height: 20),
            FilledButton(key: const Key('sheetFinish'), onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
          ],
        ]),
      ),
    );
  }
}

// =====================================================================================================================
// bringing records back

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key, required this.host});
  final BackupHost host;
  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

enum _RStage { source, sheet, waiting, review, done }

class _RestoreScreenState extends State<RestoreScreen> {
  _RStage _stage = _RStage.source;
  bool _fromServer = false;
  final TextEditingController _words = TextEditingController(), _path = TextEditingController(), _pin = TextEditingController();
  String _error = '';
  bool _busy = false;
  RecoveryKey? _key;
  RestoreOpen? _open;
  RestorePlan? _plan;
  ConflictChoice _choice = ConflictChoice.keepThisPhone;
  bool _acceptOlder = false;
  RestoreOutcome? _outcome;

  // server
  ServerRestore? _sr;
  String? _vaultId;
  ServerRestoreStatus? _srStatus;
  ServerFetch? _fetched;

  BackupService get _svc => widget.host.service;
  BackupKind get _kind => widget.host.kind;
  RestoreEngine get _engine => _svc.restoreEngine();

  @override
  void initState() {
    super.initState();
    widget.host.defaultFolder().then((String? p) {
      if (mounted && p != null && _path.text.isEmpty) _path.text = p;
    });
  }

  @override
  void dispose() {
    _words.dispose();
    _path.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _fail(String m) => setState(() {
        _error = m;
        _busy = false;
      });

  Future<void> _sheetNext() async {
    final SheetParse p = RecoveryKey.parse(_words.text);
    if (!p.ok) return _fail(BackupCopy.sheetProblem(p.problem!, p.badIndex));
    _key = p.key;
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      if (_fromServer) {
        await _serverAsk();
      } else {
        final BackupSource src = await (widget.host.openFolder ?? _defaultOpen)(_path.text.trim());
        await _openAndPlan(src);
      }
    } on RestoreBlocked catch (e) {
      _fail(BackupCopy.restoreProblem(e.problem, restLeftMs: e.restLeftMs));
    } on BackupSinkException catch (e) {
      _fail(BackupCopy.failureWords(e.code));
    } catch (_) {
      _fail('Olive could not read that place.');
    }
  }

  static Future<BackupSource> _defaultOpen(String path) async {
    final BackupSource? s = await _openDirectory(path);
    if (s == null) throw const BackupSinkException('unreachable');
    return s;
  }

  Future<void> _openAndPlan(BackupSource src) async {
    final RestoreEngine re = _engine;
    final RestoreOpen o = await re.open(source: src, key: _key!, kind: _kind);
    final RestorePlan plan = await re.plan(o, choice: _choice);
    if (!mounted) return;
    setState(() {
      _open = o;
      _plan = plan;
      _stage = _RStage.review;
      _busy = false;
    });
  }

  Future<void> _serverAsk() async {
    final BackupServerApi? api = _svc.canUseServer ? _svcApi() : null;
    final id = await widget.host.identity?.call();
    if (api == null || id == null) throw const BackupSinkException('signed_out');
    final ServerRestore sr = ServerRestore(api: api, state: _svc.state);
    final String? vault = await sr.findVault();
    if (vault == null) throw const BackupSinkException('no_vault');
    final BackupAuthority auth = await deriveBackupAuthority(_key!, _kind);
    final ServerRestoreStatus st = await sr.request(vaultId: vault, authority: auth, userId: id.userId, deviceId: id.deviceId, pin: _pin.text);
    if (!mounted) return;
    setState(() {
      _sr = sr;
      _vaultId = vault;
      _srStatus = st;
      _stage = _RStage.waiting;
      _busy = false;
    });
  }

  BackupServerApi? _svcApi() => _svc.serverApiForScreens();

  Future<void> _checkAgain() async {
    setState(() => _busy = true);
    try {
      final ServerRestoreStatus st = await _sr!.status(_vaultId!);
      if (st.phase == ServerRestorePhase.ready || st.phase == ServerRestorePhase.tokenIssued) {
        final BackupAuthority auth = await deriveBackupAuthority(_key!, _kind);
        final ServerFetch f = await _sr!.fetch(vaultId: _vaultId!, restoreId: st.restoreId!, authority: auth, kind: _kind);
        _fetched = f;
        _srStatus = st;
        await _openAndPlan(f.source);
        return;
      }
      if (!mounted) return;
      setState(() {
        _srStatus = st;
        _busy = false;
      });
    } on RestoreBlocked catch (e) {
      _fail(BackupCopy.restoreProblem(e.problem, restLeftMs: e.restLeftMs));
    } on BackupSinkException catch (e) {
      _fail(e.code == 'damaged' ? 'What the server held did not check out, so nothing was used.' : BackupCopy.failureWords(e.code));
    }
  }

  Future<void> _stopIt() async {
    final ServerRestoreStatus? st = _srStatus;
    if (st?.restoreId == null) return;
    try {
      await _sr!.cancel(_vaultId!, st!.restoreId!);
      final ServerRestoreStatus n = await _sr!.status(_vaultId!);
      if (mounted) setState(() => _srStatus = n);
    } on BackupSinkException catch (e) {
      _fail(BackupCopy.failureWords(e.code));
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final RestoreOutcome out = await _engine.apply(_open!, choice: _choice, acceptOlder: _acceptOlder, requirePaired: widget.host.isTablet);
      await _svc.adoptSheet(_key!);
      final ServerFetch? f = _fetched;
      if (f != null && _sr != null && _srStatus?.restoreId != null) await _sr!.complete(_vaultId!, _srStatus!.restoreId!, f);
      _key = null;
      if (!mounted) return;
      setState(() {
        _outcome = out;
        _stage = _RStage.done;
        _busy = false;
      });
    } on RestoreBlocked catch (e) {
      if (e.problem == RestoreProblem.older) setState(() => _acceptOlder = false);
      _fail(BackupCopy.restoreProblem(e.problem, restLeftMs: e.restLeftMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool tablet = widget.host.isTablet;
    return Scaffold(
      appBar: AppBar(title: Text(tablet ? 'Bring back her home and keepsakes' : 'Bring my records back')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
          if (_stage == _RStage.source) ...<Widget>[
            const Text('Where is your backup?'),
            const SizedBox(height: 12),
            RadioGroup<bool>(
              groupValue: _fromServer,
              onChanged: (bool? v) => setState(() => _fromServer = v ?? false),
              child: Column(children: <Widget>[
                const RadioListTile<bool>(key: Key('restoreFromFolder'), value: false, title: Text('A folder on this phone')),
                if (!tablet) const RadioListTile<bool>(key: Key('restoreFromServer'), value: true, title: Text("Your family's server")),
              ]),
            ),
            if (!_fromServer) ...<Widget>[
              const SizedBox(height: 8),
              TextField(key: const Key('restorePath'), controller: _path, decoration: const InputDecoration(labelText: 'Folder'), autocorrect: false),
              const SizedBox(height: 4),
              const Text('Copy your backup folder onto this phone first, then choose it here.'),
            ] else ...<Widget>[
              const SizedBox(height: 8),
              TextField(key: const Key('restorePin'), controller: _pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your PIN')),
              const SizedBox(height: 4),
              const Text('You must be signed in on this phone. The server will hold the request for a few days.'),
            ],
            const SizedBox(height: 16),
            FilledButton(key: const Key('restoreSourceNext'), onPressed: () => setState(() => _stage = _RStage.sheet), child: const Text('Next')),
          ],
          if (_stage == _RStage.sheet) ...<Widget>[
            Text(tablet ? 'Type the 18 words of her keepsake sheet.' : 'Type the 18 words of your recovery sheet.'),
            const SizedBox(height: 12),
            TextField(key: const Key('restoreWords'), controller: _words, minLines: 3, maxLines: 6, autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Your 18 words')),
            const SizedBox(height: 8),
            const Text('Only type these words here. Olive never asks for them by call, text or email.'),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, key: const Key('restoreError'))),
            const SizedBox(height: 16),
            FilledButton(key: const Key('restoreSheetNext'), onPressed: _busy ? null : _sheetNext, child: Text(_busy ? 'Looking...' : 'Next')),
          ],
          if (_stage == _RStage.waiting) ...<Widget>[
            Text(BackupCopy.phaseWords(_srStatus?.phase ?? ServerRestorePhase.none, waitHours: _srStatus?.waitHours), key: const Key('restoreWaiting')),
            if (_srStatus?.notBefore != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Earliest: ${_srStatus!.notBefore!.toLocal()}')),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, key: const Key('restoreError'))),
            const SizedBox(height: 16),
            FilledButton(key: const Key('restoreCheckAgain'), onPressed: _busy ? null : _checkAgain, child: const Text('Check again')),
            TextButton(key: const Key('restoreStop'), onPressed: _busy ? null : _stopIt, child: const Text('Stop this request')),
          ],
          if (_stage == _RStage.review) ..._review(context),
          if (_stage == _RStage.done) ..._done(context),
        ]),
      ),
    );
  }

  List<Widget> _review(BuildContext context) {
    final RestoreOpen o = _open!;
    final RestorePlan plan = _plan!;
    final int changing = plan.changing.length;
    return <Widget>[
      Text('Found a backup made ${BackupCopy.ago(_now(widget.host), o.newestAtMs)}, with ${o.areaCount} kinds of records from ${o.heads.length} ${o.heads.length == 1 ? 'phone' : 'phones'}.',
          key: const Key('restoreFound')),
      if (o.skippedDamaged > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${o.skippedDamaged} copy(s) were damaged and were not used.')),
      const SizedBox(height: 12),
      Text(changing == 0 ? 'This phone already has everything in it.' : '$changing kinds of records will be added or joined with what is here.', key: const Key('restorePlanText')),
      if (plan.conflicts.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text('${plan.conflicts.length} things are different on this phone and in the backup. Olive keeps both copies and nothing is lost.', key: const Key('restoreConflicts')),
        RadioGroup<ConflictChoice>(
          groupValue: _choice,
          onChanged: (ConflictChoice? v) => _rechoose(v!),
          child: const Column(children: <Widget>[
            RadioListTile<ConflictChoice>(value: ConflictChoice.keepThisPhone, title: Text('Use what is on this phone')),
            RadioListTile<ConflictChoice>(value: ConflictChoice.useBackup, title: Text("Use the backup's")),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      const Text('Something you deleted after the backup was made may come back. Nothing on this phone is removed.'),
      if (!widget.host.isTablet) const Padding(padding: EdgeInsets.only(top: 8), child: Text(BackupCopy.restoreIsRecordsOnly, key: Key('restoreRecordsOnly'))),
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, key: const Key('restoreError'))),
      if (_error == BackupCopy.restoreProblem(RestoreProblem.older))
        CheckboxListTile(key: const Key('restoreAcceptOlder'), value: _acceptOlder, onChanged: (bool? v) => setState(() => _acceptOlder = v ?? false), title: const Text('Yes, I mean to use this older backup')),
      const SizedBox(height: 16),
      FilledButton(key: const Key('restoreApply'), onPressed: _busy ? null : _apply, child: Text(_busy ? 'Working...' : 'Bring my records back')),
    ];
  }

  Future<void> _rechoose(ConflictChoice c) async {
    final RestorePlan p = await _engine.plan(_open!, choice: c);
    if (mounted) {
      setState(() {
        _choice = c;
        _plan = p;
      });
    }
  }

  List<Widget> _done(BuildContext context) {
    final RestoreOutcome o = _outcome!;
    return <Widget>[
      Text(o.restoredNamespaces.isEmpty ? 'Everything was already here.' : '${o.restoredNamespaces.length} kinds of records were brought back and checked.', key: const Key('restoreDone')),
      if (o.setAside > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${o.setAside} different things were set aside, not thrown away.')),
      const SizedBox(height: 12),
      const Text('Make a backup from this phone soon, so it is protected too.'),
      const SizedBox(height: 16),
      FilledButton(key: const Key('restoreFinish'), onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
    ];
  }
}

// kept out of the widget so the screen file has no direct dart:io dependency in tests that never open a folder
Future<BackupSource?> _openDirectory(String path) async => openBackupFolder(path);
