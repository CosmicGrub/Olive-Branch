// OLIVE BRANCH — losing a phone without losing anything: the adult screens. Verified headless
// (client/test/recovery_paths_screens_test.dart). MASTERFILE section 7.22.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.22).
//
// WHO SEES THESE. Grown-ups only (and the one trusted helper a grown-up names). They are reached from the lock
// screen's "Forgot your PIN?", from Settings, Family account, and from Settings, Safety. They are NEVER reachable from a
// child's app, and a test fails if a child-side file imports this one. A child sees no PIN, code, count or error from any
// of it (P1 to P11).
//
// THE SCREENS, in the order a person meets them:
//   [LostPhoneScreen]         "Lost your phone?": which way back is true for you. One question.
//   [UseSheetScreen]          one grown-up: type the key from the printed sheet.
//   [UseGrownUpCodeScreen]    two or more: type the code the other grown-up gave you.
//   [RecoveryWaitScreen]      the waiting period, said plainly; then the one last step; or how it ended.
//   [RecoveredScreen]         what came back, what was signed out, what to do next.
//   [RecoverySafetyScreen]    set up while your phone works: the sheet, the helper, notices, helping someone.
//   [MakeSheetScreen]         make the printed key (shown once), print it, type it back to show it was kept.
//   [CheckSheetScreen]        check the paper any time.
//   [NameHelperScreen]        name ONE trusted helper and get the code to hand them.
//   [HelpGrownUpScreen]       another grown-up lost their phone: your PIN is your yes.
//   [BecomeHelperScreen], [HelperHomeScreen]   the helper's side: say yes or no. Nothing else.
//   [RecoveryNoticeBanner]    a calm card on the account page when a recovery is waiting.
//
// ONE THING PER SCREEN. Adult words only. Every failure is a sentence ([recoveryProblemFor]); nothing on a screen is a
// server code or a status. Every screen asks the phone to block screenshots while a key, code or PIN is on it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'family_account_logic.dart';
import 'family_account_screens.dart' show RecoverAccountScreen;
import 'family_account_service.dart' show FamilyAccountService;
import 'lost_device_screens.dart' show YourDevicesScreen;
import 'recovery_paths_logic.dart';
import 'recovery_paths_service.dart';
import 'screen_privacy.dart' show SensitiveScreen;
import 'sheet_printer.dart';

// ---- shared pieces ----------------------------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SensitiveScreen(
        child: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Problem extends StatelessWidget {
  const _Problem(this.problem);
  final AccountProblem? problem;

  @override
  Widget build(BuildContext context) {
    final AccountProblem? p = problem;
    if (p == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Card(
          key: const Key('recoveryProblem'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(p.message, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, this.strong = false});
  final String text;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: strong ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyMedium),
      );
}

class _PinBox extends StatelessWidget {
  const _PinBox({super.key, required this.controller, required this.label, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: enabled,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
        ),
      );
}

/// A box for a key or code typed from paper: capitals, no suggestions, no autocorrect.
class _CodeBox extends StatelessWidget {
  const _CodeBox({super.key, required this.controller, required this.label, this.enabled = true});
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: enabled,
          enableSuggestions: false,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          keyboardType: TextInputType.visiblePassword,
          maxLength: 40,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
        ),
      );
}

/// A key or code in large type, in groups, so it can be copied by hand or read aloud.
class _BigCode extends StatelessWidget {
  const _BigCode(this.code, {super.key});
  final String code;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Code: ${code.split('-').join(', ')}',
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                border: Border.all(width: 3, color: Theme.of(context).colorScheme.onSurface),
                borderRadius: BorderRadius.circular(8)),
            child: Text(code.split('-').join('  '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap),
      );
}

/// Runs [body]; a failure becomes a sentence on the screen. Returns null on failure.
Future<T?> _guarded<T>(
  Future<T> Function() body, {
  required void Function(bool busy) setBusy,
  required void Function(AccountProblem? problem) setProblem,
}) async {
  setBusy(true);
  setProblem(null);
  try {
    final T r = await body();
    setBusy(false);
    return r;
  } on AccountFailure catch (e) {
    setBusy(false);
    setProblem(e.problem);
    return null;
  } catch (e) {
    setBusy(false);
    setProblem(recoveryProblemFor(e, RecoveryAction.checkStatus));
    return null;
  }
}

/// Asks for the grown-up's own PIN in a small box and returns it (null when they cancel). The PIN is not kept.
Future<String?> _askPin(BuildContext context, {required String title, required String body, required String yes}) {
  // Not disposed here: the dialog is still animating away when its future completes, and a disposed controller under
  // a live text field throws. It holds no listener, so the garbage collector takes it.
  final TextEditingController c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => SensitiveScreen(
      child: AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(body),
          const SizedBox(height: 12),
          _PinBox(key: const Key('askPinField'), controller: c, label: 'Your PIN'),
        ]),
        actions: <Widget>[
          TextButton(key: const Key('askPinCancel'), onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          FilledButton(
              key: const Key('askPinYes'),
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(yes)),
        ],
      ),
    ),
  );
}

// =====================================================================================================================
//  The new phone
// =====================================================================================================================

/// "Lost your phone?" Which way back is true for you. Nothing is sent until a grown-up asks.
class LostPhoneScreen extends StatefulWidget {
  const LostPhoneScreen({super.key, required this.service, required this.account});
  final RecoveryPathsService service;

  /// For the way that uses a code from whoever runs the server (the older path, still here).
  final FamilyAccountService account;

  @override
  State<LostPhoneScreen> createState() => _LostPhoneScreenState();
}

class _LostPhoneScreenState extends State<LostPhoneScreen> {
  PendingRecovery? _pending;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final PendingRecovery? p = await widget.service.pending();
    if (mounted) setState(() => _pending = p);
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => screen));
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Lost your phone?', children: <Widget>[
        const _Note('You can get back into your family on this phone.', strong: true),
        const _Note('Nothing is lost. Your family, your child and everything in your account stay exactly as they were. '
            'Which of these is true for you?'),
        if (_pending != null)
          Card(
            key: const Key('resumeRecovery'),
            child: ListTile(
              leading: const Icon(Icons.hourglass_top_outlined),
              title: const Text('You already started'),
              subtitle: const Text('See how it is going.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(RecoveryWaitScreen(service: widget.service, account: widget.account)),
            ),
          ),
        _Tile(
          key: const Key('tileGrownUpHelp'),
          icon: Icons.people_outline,
          title: 'Another grown-up in my family can help me',
          subtitle: 'They give you a code from their phone.',
          onTap: () => _go(UseGrownUpCodeScreen(service: widget.service, account: widget.account)),
        ),
        _Tile(
          key: const Key('tileSheet'),
          icon: Icons.description_outlined,
          title: 'I have my printed recovery sheet',
          subtitle: 'For when there is no other grown-up to ask.',
          onTap: () => _go(UseSheetScreen(service: widget.service, account: widget.account)),
        ),
        _Tile(
          key: const Key('tileServerCode'),
          icon: Icons.vpn_key_outlined,
          title: 'Whoever runs my server gave me a code',
          subtitle: 'You also need your account PIN.',
          onTap: () => _go(RecoverAccountScreen(service: widget.account)),
        ),
        _Tile(
          key: const Key('tileBeHelper'),
          icon: Icons.volunteer_activism_outlined,
          title: 'Someone asked me to be their helper',
          subtitle: 'You say yes or no. That is all a helper does.',
          onTap: () => _go(BecomeHelperScreen(service: widget.service)),
        ),
        const SizedBox(height: 8),
        const _Note(
            'Please do not make a new account. A new account starts an empty family, and the one you have would be '
            'left behind. These ways bring back the one you already have.',
            key: Key('noNewAccountNote')),
      ]);
}

/// One grown-up: the key from the printed sheet.
class UseSheetScreen extends StatefulWidget {
  const UseSheetScreen({super.key, required this.service, required this.account});
  final RecoveryPathsService service;
  final FamilyAccountService account;

  @override
  State<UseSheetScreen> createState() => _UseSheetScreenState();
}

class _UseSheetScreenState extends State<UseSheetScreen> {
  final TextEditingController _key = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    final String typed = _key.text;
    final RecoveryStarted? r = await _guarded<RecoveryStarted>(() => widget.service.startWithSheet(typed),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (r == null || !mounted) return;
    _key.clear();
    await Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute<void>(
        builder: (BuildContext _) => RecoveryWaitScreen(service: widget.service, account: widget.account)));
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Your recovery sheet', children: <Widget>[
        const _Note('Type the key from your printed sheet.', strong: true),
        const _Note('It has six groups of four letters and numbers. Capitals, small letters and dashes do not matter.'),
        const _Note('Nothing changes right away. Olive waits 3 days, and tells every phone on your account, so '
            'someone can stop it if it was not you.'),
        _Problem(_problem),
        _CodeBox(key: const Key('sheetKeyField'), controller: _key, label: 'Recovery key', enabled: !_busy),
        FilledButton(
            key: const Key('startWithSheet'),
            onPressed: _busy ? null : _start,
            child: Text(_busy ? 'Checking…' : 'Start')),
      ]);
}

/// Two or more grown-ups: the code the other grown-up gave you.
class UseGrownUpCodeScreen extends StatefulWidget {
  const UseGrownUpCodeScreen({super.key, required this.service, required this.account});
  final RecoveryPathsService service;
  final FamilyAccountService account;

  @override
  State<UseGrownUpCodeScreen> createState() => _UseGrownUpCodeScreenState();
}

class _UseGrownUpCodeScreenState extends State<UseGrownUpCodeScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    if (_busy) return;
    final String typed = _code.text;
    final RecoveryStarted? r = await _guarded<RecoveryStarted>(() => widget.service.useGrownUpCode(typed),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (r == null || !mounted) return;
    _code.clear();
    await Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute<void>(
        builder: (BuildContext _) => RecoveryWaitScreen(service: widget.service, account: widget.account)));
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'A code from another grown-up', children: <Widget>[
        const _Note('Type the code the other grown-up gave you.', strong: true),
        const _Note('They make it on their own phone: Settings, Lost phone safety, "Help someone get back in". It has '
            'five groups of four letters and numbers.'),
        _Problem(_problem),
        _CodeBox(key: const Key('grownUpCodeField'), controller: _code, label: 'Code', enabled: !_busy),
        FilledButton(
            key: const Key('useGrownUpCode'),
            onPressed: _busy ? null : _use,
            child: Text(_busy ? 'Checking…' : 'Continue')),
      ]);
}

/// The waiting period, said plainly; then the one last step; or how it ended.
class RecoveryWaitScreen extends StatefulWidget {
  const RecoveryWaitScreen({super.key, required this.service, required this.account, this.now});
  final RecoveryPathsService service;
  final FamilyAccountService account;

  /// For a test.
  final DateTime Function()? now;

  @override
  State<RecoveryWaitScreen> createState() => _RecoveryWaitScreenState();
}

class _RecoveryWaitScreenState extends State<RecoveryWaitScreen> {
  RecoveryStatus? _status;
  bool _loading = true;
  bool _busy = false;
  AccountProblem? _problem;
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _newPin = TextEditingController();
  bool _useKey = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _pin.dispose();
    _key.dispose();
    _newPin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final RecoveryStatus? s = await _guarded<RecoveryStatus?>(widget.service.status,
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  Future<void> _giveUp() async {
    final bool? yes = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
              title: const Text('Stop this recovery?'),
              content: const Text('Nothing was changed, and nothing will be. You can start again whenever you like.'),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep waiting')),
                FilledButton(key: const Key('confirmGiveUp'), onPressed: () => Navigator.pop(c, true), child: const Text('Stop it')),
              ],
            ));
    if (yes != true) return;
    await widget.service.giveUp();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _startAgain() async {
    await widget.service.clearPending();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    if (_busy) return;
    final RecoveryStatus s = _status!;
    final String pin = _pin.text, key = _key.text, newPin = _newPin.text;
    final RecoveredResult? r = await _guarded<RecoveredResult>(
        () => widget.service.finish(
            pin: (!s.soleParent && !_useKey) ? pin : null,
            sheetKey: (!s.soleParent && _useKey) ? key : null,
            newPin: (s.soleParent || _useKey) ? newPin : null),
        setBusy: (bool b) => setState(() => _busy = b),
        setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    _key.clear();
    _newPin.clear();
    if (!mounted) return;
    if (r == null) {
      // A recovery that is over (burned by wrong tries, stopped, finished): look again so the screen says how it ended.
      if (_problem?.reason == 'invalid_recovery' || _problem?.reason == 'too_many_wrong') {
        final AccountProblem? keep = _problem;
        await _check();
        if (mounted) setState(() => _problem = keep);
      }
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (BuildContext _) => RecoveredScreen(result: r, service: widget.service)));
  }

  @override
  Widget build(BuildContext context) {
    final RecoveryStatus? s = _status;
    final DateTime now = _now();
    return _Page(title: 'Getting back in', children: <Widget>[
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (!_loading && s == null) ...<Widget>[
        _Problem(_problem),
        const _Note('There is no recovery waiting on this phone.', key: Key('noRecovery')),
        FilledButton(key: const Key('waitBack'), onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      ],
      if (s != null) ..._body(s, now),
    ]);
  }

  List<Widget> _body(RecoveryStatus s, DateTime now) {
    final String who = s.accountName.isEmpty ? 'your account' : '${s.accountName}\'s account';
    switch (s.phase) {
      case RecoveryPhase.waiting:
        return <Widget>[
          const _Note('You are waiting.', strong: true, key: Key('phaseWaiting')),
          _Note('You can finish ${whenWords(s.readyAt, now)} (${waitWords(s.readyAt.difference(now))} from now).'),
          const _Note('Until then nothing changes. Every phone on the account has been told, and anyone can stop it. '
              'You do not need to keep Olive open. Come back then.'),
          _Problem(_problem),
          OutlinedButton(key: const Key('checkAgain'), onPressed: _busy ? null : _check, child: const Text('Check again')),
          TextButton(key: const Key('giveUp'), onPressed: _giveUp, child: const Text('Stop this recovery')),
        ];
      case RecoveryPhase.waitingForHelper:
        return <Widget>[
          const _Note('One more yes is needed.', strong: true, key: Key('phaseWaitingHelper')),
          const _Note('The waiting time is over. Your trusted helper has to say yes before you can finish. Ask them to '
              'open Olive and say yes. They can only do that if it really is you.'),
          _Problem(_problem),
          OutlinedButton(key: const Key('checkAgain'), onPressed: _busy ? null : _check, child: const Text('Check again')),
          TextButton(key: const Key('giveUp'), onPressed: _giveUp, child: const Text('Stop this recovery')),
        ];
      case RecoveryPhase.ready:
        return <Widget>[
          const _Note('You can finish now.', strong: true, key: Key('phaseReady')),
          if (s.soleParent) ...<Widget>[
            _Note('This phone will be signed in to $who. If you forgot your PIN, choose a new one here. If you '
                'remember it, leave this empty and keep your old one.'),
            _PinBox(key: const Key('newPinField'), controller: _newPin, label: 'New PIN (optional)', enabled: !_busy),
          ] else ...<Widget>[
            const _Note('To be sure it is you, type your own PIN. If you do not remember it, use your recovery sheet.'),
            if (!_useKey)
              _PinBox(key: const Key('proofPinField'), controller: _pin, label: 'Your PIN', enabled: !_busy)
            else ...<Widget>[
              _CodeBox(key: const Key('proofKeyField'), controller: _key, label: 'Recovery key from your sheet', enabled: !_busy),
              _PinBox(key: const Key('newPinField'), controller: _newPin, label: 'New PIN (optional)', enabled: !_busy),
            ],
            TextButton(
                key: const Key('toggleProof'),
                onPressed: _busy ? null : () => setState(() => _useKey = !_useKey),
                child: Text(_useKey ? 'Use my PIN instead' : 'Use my recovery sheet instead')),
          ],
          _Problem(_problem),
          FilledButton(
              key: const Key('finishRecovery'),
              onPressed: _busy ? null : _finish,
              child: Text(_busy ? 'Working…' : 'Finish')),
          TextButton(key: const Key('giveUp'), onPressed: _giveUp, child: const Text('Stop this recovery')),
        ];
      case RecoveryPhase.stopped:
      case RecoveryPhase.expired:
      case RecoveryPhase.done:
      case RecoveryPhase.unknown:
        final String how = switch (s.stoppedBy) {
          'owner_phone' => 'It was stopped from the account\'s own phone.',
          'other_parent' => 'It was stopped by another grown-up.',
          'helper' => 'The trusted helper said no.',
          'new_phone' => 'It was stopped from this phone.',
          'too_many_wrong' => 'It was stopped after too many wrong tries.',
          'sheet_replaced' => 'A new recovery sheet was made, so it stopped.',
          'expired' => 'Nobody finished it in time, so it ran out.',
          _ => s.phase == RecoveryPhase.done ? 'It already finished.' : 'It was stopped.',
        };
        return <Widget>[
          const _Note('This recovery is over.', strong: true, key: Key('phaseOver')),
          _Note('$how Nothing was changed. If it was you, you can start again.'),
          _Problem(_problem),
          FilledButton(key: const Key('startAgain'), onPressed: _startAgain, child: const Text('Start again')),
        ];
    }
  }
}

/// What came back, what was signed out, what to do next.
class RecoveredScreen extends StatelessWidget {
  const RecoveredScreen({super.key, required this.result, required this.service, this.printer});
  final RecoveredResult result;
  final RecoveryPathsService service;
  final SheetPrinter? printer;

  @override
  Widget build(BuildContext context) => _Page(title: "You're back", children: <Widget>[
        const _Note("You're back in your family.", strong: true, key: Key('recoveredDone')),
        const _Note('This phone is now signed in to your own account. Nothing was made new and nothing was moved: your '
            'family, your child and everything in the account are as you left them.'),
        if (result.devicesSignedOut > 0)
          _Note('${result.devicesSignedOut == 1 ? 'Your older phone was' : 'Your ${result.devicesSignedOut} older phones were'} '
              'signed out, so a lost phone can no longer open the account. The other grown-ups can see this in the history.'),
        const _Note('If your family does not show up straight away, close Olive and open it again.'),
        if (result.sheetSpent)
          Card(
            key: const Key('sheetWasUsed'),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Make a new recovery sheet'),
              subtitle: const Text('The one you used is finished. A new one takes a minute.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                  builder: (BuildContext _) => MakeSheetScreen(service: service, printer: printer))),
            ),
          ),
        FilledButton(
            key: const Key('recoveredContinue'),
            onPressed: () => Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst),
            child: const Text('Continue')),
      ]);
}

// =====================================================================================================================
//  A grown-up whose phone works
// =====================================================================================================================

/// A recovery that waits, as a card with the one thing to do about it.
class RecoveryNoticeCard extends StatelessWidget {
  const RecoveryNoticeCard({super.key, required this.notice, required this.onStop, this.now});
  final RecoveryNotice notice;
  final VoidCallback onStop;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('A recovery is waiting', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
          const SizedBox(height: 6),
          Text(noticeSentence(notice, (now ?? DateTime.now)()),
              key: Key('notice_${notice.requestId}'), style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
          const SizedBox(height: 10),
          FilledButton(key: Key('stop_${notice.requestId}'), onPressed: onStop, child: const Text('Stop it')),
        ]),
      ),
    );
  }
}

/// A calm card on the account page when a recovery is waiting. It never shows a failure: a phone that cannot ask
/// simply shows nothing here.
class RecoveryNoticeBanner extends StatefulWidget {
  const RecoveryNoticeBanner({super.key, required this.service, required this.onOpen, this.now});
  final RecoveryPathsService service;
  final VoidCallback onOpen;
  final DateTime Function()? now;

  @override
  State<RecoveryNoticeBanner> createState() => _RecoveryNoticeBannerState();
}

class _RecoveryNoticeBannerState extends State<RecoveryNoticeBanner> {
  List<RecoveryNotice> _open = const <RecoveryNotice>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final RecoverySummary s = await widget.service.summary();
      if (mounted) setState(() => _open = s.open);
    } catch (_) {
      // Silent on purpose: this is a notice, not a place for errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_open.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Card(
      key: const Key('recoveryBanner'),
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: theme.colorScheme.onTertiaryContainer),
        title: Text('A recovery is waiting', style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
        subtitle: Text(noticeSentence(_open.first, (widget.now ?? DateTime.now)()),
            style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpen,
      ),
    );
  }
}

/// "Lost phone safety": set up while your phone works. The sheet, the helper, the notices, helping someone.
class RecoverySafetyScreen extends StatefulWidget {
  const RecoverySafetyScreen({super.key, required this.service, this.printer, this.now});
  final RecoveryPathsService service;
  final SheetPrinter? printer;
  final DateTime Function()? now;

  @override
  State<RecoverySafetyScreen> createState() => _RecoverySafetyScreenState();
}

class _RecoverySafetyScreenState extends State<RecoverySafetyScreen> {
  RecoverySummary? _s;
  bool _loading = true;
  AccountProblem? _problem;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final RecoverySummary? s = await _guarded<RecoverySummary>(widget.service.summary,
        setBusy: (bool _) {}, setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (!mounted) return;
    setState(() {
      _s = s ?? _s;
      _loading = false;
    });
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => screen));
    if (mounted) unawaited(_load());
  }

  Future<void> _stop(RecoveryNotice n) async {
    final String? pin = await _askPin(context,
        title: 'Stop this recovery?',
        body: 'Type your own PIN to stop it. Nothing will change, and whoever asked can start again if it was really them.',
        yes: 'Stop it');
    if (pin == null || !mounted) return;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.stop(requestId: n.requestId, pin: pin);
      return true;
    }, setBusy: (bool _) {}, setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == true && mounted) unawaited(_load());
  }

  String _date(DateTime d) => whenWords(d, _now());

  @override
  Widget build(BuildContext context) {
    final RecoverySummary? s = _s;
    return _Page(title: 'Lost phone safety', children: <Widget>[
      const _Note('If a phone is lost, you can get back in, and nothing is lost. Set this up now, while your phone works.'),
      _Problem(_problem),
      if (_busy && s != null) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
      if (_loading && s == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (s != null) ..._sections(s),
    ]);
  }

  List<Widget> _sections(RecoverySummary s) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      for (final RecoveryNotice n in s.open) RecoveryNoticeCard(notice: n, now: _now, onStop: () => _stop(n)),
      // --- the sheet
      Card(
        key: const Key('sheetCard'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Printed recovery sheet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              s.sheet.spentNeedsNew
                  ? 'Your sheet was used to get back in, so it is finished. Make a new one.'
                  : !s.sheet.exists
                      ? 'A paper with a key on it. If you lose your phone and there is no other grown-up to ask, it is '
                          'how you get back in. You have not made one yet.'
                      : s.sheet.kept
                          ? 'Made ${_date(s.sheet.createdAt ?? _now())}. You checked it and it matches.'
                          : 'Made ${_date(s.sheet.createdAt ?? _now())}. You have not shown that you kept it yet.',
              key: const Key('sheetStatus'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              FilledButton(
                  key: const Key('makeSheet'),
                  onPressed: () => _go(MakeSheetScreen(service: widget.service, printer: widget.printer)),
                  child: Text(s.sheet.exists ? 'Make a new sheet' : 'Make my sheet')),
              if (s.sheet.exists && !s.sheet.kept)
                OutlinedButton(
                    key: const Key('checkSheet'),
                    onPressed: () => _go(CheckSheetScreen(service: widget.service)),
                    child: const Text('Check my sheet')),
              if (s.sheet.kept)
                TextButton(
                    key: const Key('checkSheet'),
                    onPressed: () => _go(CheckSheetScreen(service: widget.service)),
                    child: const Text('Check it again')),
            ]),
          ]),
        ),
      ),
      // --- the helper
      Card(
        key: const Key('helperCard'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('One trusted helper', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              switch (s.helper.phase) {
                HelperPhase.none => 'Someone you trust who can say yes, that is me, if you lose your phone and have no '
                    'other grown-up. That is all they can do. They cannot see your family or sign in as you. You have '
                    'not named anyone.',
                HelperPhase.invited => 'Waiting for ${s.helper.label} to open the code you gave them'
                    '${s.helper.inviteExpiresAt == null ? '' : ' (until ${_date(s.helper.inviteExpiresAt!)})'}.',
                HelperPhase.active => '${s.helper.label} is your trusted helper. They can only say yes or no to a '
                    'recovery of your account.',
              },
              key: const Key('helperStatus'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              FilledButton(
                  key: const Key('nameHelper'),
                  onPressed: () => _go(NameHelperScreen(service: widget.service)),
                  child: Text(s.helper.phase == HelperPhase.none ? 'Name a helper' : 'Choose someone else')),
              if (s.helper.phase != HelperPhase.none)
                TextButton(
                    key: const Key('removeHelper'),
                    onPressed: () async {
                      final String? pin = await _askPin(context,
                          title: 'Take ${s.helper.label} off?',
                          body: 'They will no longer be able to say yes for you. Type your PIN to do this.',
                          yes: 'Take them off');
                      if (pin == null || !mounted) return;
                      final bool? ok = await _guarded<bool>(() async {
                        await widget.service.removeHelper(pin: pin);
                        return true;
                      },
                          setBusy: (bool _) {},
                          setProblem: (AccountProblem? p) => setState(() => _problem = p));
                      if (ok == true && mounted) unawaited(_load());
                    },
                    child: const Text('Take them off')),
            ]),
          ]),
        ),
      ),
      // --- a phone or tablet that is lost right now: mark it, bring it back, make it final, erase it when it connects
      _Tile(
        key: const Key('tileLostDevices'),
        icon: Icons.phonelink_lock_outlined,
        title: 'Lost or stolen phone or tablet',
        subtitle: 'Mark it as lost so it gets nothing new. Nothing is deleted, and you can change your mind for 3 days.',
        onTap: () => _go(YourDevicesScreen(service: widget.service.lostDevices, now: widget.now)),
      ),
      // --- helping another grown-up
      if (s.canHelp.isNotEmpty)
        _Tile(
          key: const Key('tileHelpSomeone'),
          icon: Icons.people_outline,
          title: 'Help someone get back in',
          subtitle: 'Another grown-up in your family lost their phone.',
          onTap: () => _go(HelpGrownUpScreen(service: widget.service, people: s.canHelp, waitHours: s.secondParentHours)),
        ),
      _Tile(
        key: const Key('tileImHelper'),
        icon: Icons.volunteer_activism_outlined,
        title: "I'm someone's helper",
        subtitle: 'Say yes or no to a recovery that names you.',
        onTap: () => _go(BecomeHelperScreen(service: widget.service)),
      ),
      if (s.recentEnded.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text('Lately', style: theme.textTheme.titleSmall),
        for (final RecoveryNotice n in s.recentEnded)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${n.accountName.isEmpty ? 'A recovery' : '${n.accountName}\'s recovery'}: ${endedSentence(n)}'),
          ),
      ],
    ];
  }
}

enum _SheetStage { pin, show, check, done }

/// Make the printed key: shown ONCE, printed or written, typed back to show it was kept.
class MakeSheetScreen extends StatefulWidget {
  const MakeSheetScreen({super.key, required this.service, this.printer, this.accountName = '', this.now});
  final RecoveryPathsService service;
  final SheetPrinter? printer;
  final String accountName;
  final DateTime Function()? now;

  @override
  State<MakeSheetScreen> createState() => _MakeSheetScreenState();
}

class _MakeSheetScreenState extends State<MakeSheetScreen> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _typed = TextEditingController();
  _SheetStage _stage = _SheetStage.pin;
  String? _key;
  bool _busy = false;
  AccountProblem? _problem;
  String? _printNote;

  SheetPrinter get _printer => widget.printer ?? const PlatformSheetPrinter();

  @override
  void dispose() {
    _pin.dispose();
    _typed.dispose();
    _key = null;
    super.dispose();
  }

  Future<void> _make() async {
    if (_busy) return;
    final String pin = _pin.text;
    final String? k = await _guarded<String>(() => widget.service.makeSheet(pin: pin),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (k == null || !mounted) return;
    setState(() {
      _key = k;
      _stage = _SheetStage.show;
    });
  }

  Future<void> _print() async {
    final String? k = _key;
    if (k == null) return;
    final bool ok = await _printer.printSheet(
        title: 'Olive recovery sheet',
        html: recoverySheetHtml(key: k, forName: widget.accountName, made: (widget.now ?? DateTime.now)()));
    if (mounted) {
      setState(() => _printNote = ok
          ? 'The print screen is open. Check the page is printed, then carry on.'
          : 'This phone cannot print from here. Write the key down by hand, exactly as it is shown.');
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    final String typed = _typed.text;
    final bool? ok = await _guarded<bool>(() => widget.service.checkSheet(typed),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok != true || !mounted) return;
    _typed.clear();
    setState(() {
      _stage = _SheetStage.done;
      _key = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Until the key was typed back, leaving would lose it for good: it is shown once, and the server cannot show it again.
    final bool holding = _stage == _SheetStage.show || _stage == _SheetStage.check;
    return PopScope<Object?>(
      canPop: !holding,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        final bool? leave = await showDialog<bool>(
            context: context,
            builder: (BuildContext c) => AlertDialog(
                  title: const Text('Leave without checking?'),
                  content: const Text('The key is shown only once. If you leave now it is gone, and you will need to make '
                      'a new sheet. Nothing else is lost.'),
                  actions: <Widget>[
                    TextButton(key: const Key('stayOnSheet'), onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
                    FilledButton(key: const Key('leaveSheet'), onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
                  ],
                ));
        if (leave == true && context.mounted) {
          setState(() {
            _stage = _SheetStage.pin;
            _key = null;
          });
          Navigator.of(context).pop();
        }
      },
      child: _Page(title: 'Recovery sheet', children: switch (_stage) {
        _SheetStage.pin => <Widget>[
            const _Note('Make your recovery sheet.', strong: true),
            const _Note('Olive makes a key. You print it or write it down, and keep the paper somewhere safe. Olive does '
                'not keep the key, so nobody at Olive can read it to you.'),
            const _Note('A new sheet replaces any older one.'),
            _Problem(_problem),
            _PinBox(key: const Key('sheetPinField'), controller: _pin, label: 'Your PIN', enabled: !_busy),
            FilledButton(
                key: const Key('sheetMake'),
                onPressed: _busy ? null : _make,
                child: Text(_busy ? 'Making…' : 'Make my key')),
          ],
        _SheetStage.show => <Widget>[
            const _Note('This is your key. It is shown only once.', strong: true, key: Key('sheetShown')),
            _BigCode(_key ?? '', key: const Key('sheetKey')),
            const _Note('Print it or write it down exactly, and keep it somewhere safe, like with your important papers. '
                'Do not take a photo of it. Olive never asks for it by call, text or email.'),
            if (_printNote != null) _Note(_printNote!, key: const Key('printNote')),
            OutlinedButton(key: const Key('sheetPrint'), onPressed: _print, child: const Text('Print it')),
            const SizedBox(height: 8),
            FilledButton(
                key: const Key('sheetSaved'),
                onPressed: () => setState(() => _stage = _SheetStage.check),
                child: const Text('I have it on paper')),
          ],
        _SheetStage.check => <Widget>[
            const _Note('Now type it back from the paper.', strong: true),
            const _Note('This shows that the paper is right and you can read it. The key is no longer on this screen.'),
            _Problem(_problem),
            _CodeBox(key: const Key('sheetTypedField'), controller: _typed, label: 'Key from your paper', enabled: !_busy),
            FilledButton(
                key: const Key('sheetCheck'),
                onPressed: _busy ? null : _check,
                child: Text(_busy ? 'Checking…' : 'Check it')),
          ],
        _SheetStage.done => <Widget>[
            const _Note('You kept it.', strong: true, key: Key('sheetKept')),
            const _Note('Your sheet matches. Keep the paper safe. If you lose your phone and no other grown-up can help, '
                'this is how you get back in. You can check it again any time in Lost phone safety.'),
            FilledButton(key: const Key('sheetDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
      }),
    );
  }
}

/// Check the paper any time: type the key back and see that it matches.
class CheckSheetScreen extends StatefulWidget {
  const CheckSheetScreen({super.key, required this.service});
  final RecoveryPathsService service;

  @override
  State<CheckSheetScreen> createState() => _CheckSheetScreenState();
}

class _CheckSheetScreenState extends State<CheckSheetScreen> {
  final TextEditingController _typed = TextEditingController();
  bool _busy = false;
  bool _ok = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    final String typed = _typed.text;
    final bool? ok = await _guarded<bool>(() => widget.service.checkSheet(typed),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _typed.clear();
    if (ok == true && mounted) setState(() => _ok = true);
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Check my sheet', children: <Widget>[
        if (_ok) ...<Widget>[
          const _Note('It matches.', strong: true, key: Key('checkOk')),
          const _Note('Your paper is right. Keep it safe.'),
          FilledButton(key: const Key('checkDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ] else ...<Widget>[
          const _Note('Type the key from your paper.', strong: true),
          _Problem(_problem),
          _CodeBox(key: const Key('checkField'), controller: _typed, label: 'Key from your paper', enabled: !_busy),
          FilledButton(
              key: const Key('checkSubmit'),
              onPressed: _busy ? null : _check,
              child: Text(_busy ? 'Checking…' : 'Check it')),
        ],
      ]);
}

/// Name ONE trusted helper. The code that comes back is handed over by you, in person or by a call.
class NameHelperScreen extends StatefulWidget {
  const NameHelperScreen({super.key, required this.service});
  final RecoveryPathsService service;

  @override
  State<NameHelperScreen> createState() => _NameHelperScreenState();
}

class _NameHelperScreenState extends State<NameHelperScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;
  HelperInvite? _invite;
  String _named = '';

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (_busy) return;
    final String name = _name.text, pin = _pin.text;
    final HelperInvite? i = await _guarded<HelperInvite>(() => widget.service.nameHelper(name: name, pin: pin),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (i == null || !mounted) return;
    setState(() {
      _invite = i;
      _named = name.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final HelperInvite? i = _invite;
    if (i != null) {
      return _Page(title: 'Your helper', children: <Widget>[
        _Note('Give this code to $_named.', strong: true, key: const Key('helperCodeShown')),
        _BigCode(i.code, key: const Key('helperCode')),
        const _Note('Hand it over yourself, in person or on a call. Olive does not send it. It works once, and it runs '
            'out in 3 days.'),
        const _Note('They open Olive on their own phone, go to Settings, Family account, "Lost your phone?", then '
            '"Someone asked me to be their helper", and type it.'),
        const _Note('A helper can only say yes or no when your account is being recovered. They cannot see your family, '
            'your child or anything else, and they cannot sign in as you.'),
        FilledButton(key: const Key('helperDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ]);
    }
    return _Page(title: 'Name a helper', children: <Widget>[
      const _Note('Who is one person you trust?', strong: true),
      const _Note('If you lose your phone and there is no other grown-up to ask, they say yes, that is you. That is the '
          'only thing they can do. You can name one person, and you can take them off any time.'),
      _Problem(_problem),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: const Key('helperNameField'),
          controller: _name,
          enabled: !_busy,
          maxLength: kHelperNameMax,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Their first name', border: OutlineInputBorder(), counterText: ''),
        ),
      ),
      _PinBox(key: const Key('helperPinField'), controller: _pin, label: 'Your PIN', enabled: !_busy),
      FilledButton(
          key: const Key('helperMake'),
          onPressed: _busy ? null : _make,
          child: Text(_busy ? 'Working…' : 'Make their code')),
    ]);
  }
}

/// Another grown-up lost their phone. Your own PIN is your yes. Then you give them the code.
class HelpGrownUpScreen extends StatefulWidget {
  const HelpGrownUpScreen({super.key, required this.service, required this.people, this.waitHours = 48});
  final RecoveryPathsService service;
  final List<CanHelp> people;
  final int waitHours;

  @override
  State<HelpGrownUpScreen> createState() => _HelpGrownUpScreenState();
}

class _HelpGrownUpScreenState extends State<HelpGrownUpScreen> {
  final TextEditingController _pin = TextEditingController();
  late String? _who = widget.people.length == 1 ? widget.people.first.userId : null;
  bool _busy = false;
  AccountProblem? _problem;
  HelpStarted? _started;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    final String? who = _who;
    if (who == null) {
      return setState(() => _problem = const AccountProblem('Choose who you are helping.', ProblemKind.fixInput));
    }
    final String pin = _pin.text;
    final HelpStarted? s = await _guarded<HelpStarted>(() => widget.service.startFor(targetUserId: who, pin: pin),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    _pin.clear();
    if (s != null && mounted) setState(() => _started = s);
  }

  @override
  Widget build(BuildContext context) {
    final HelpStarted? s = _started;
    final String days = widget.waitHours % 24 == 0 ? '${widget.waitHours ~/ 24} days' : '${widget.waitHours} hours';
    if (s != null) {
      return _Page(title: 'Help someone get back in', children: <Widget>[
        _Note('Give this code to ${s.targetName.isEmpty ? 'them' : s.targetName}.', strong: true, key: const Key('helpCodeShown')),
        _BigCode(s.code, key: const Key('helpCode')),
        const _Note('Hand it over yourself, in person or on a call, only to the person you know. Olive does not send it.'),
        _Note('Nothing changes for $days. Every phone on the account has been told, and you or anyone else can stop it '
            'in Settings, Lost phone safety. After that they finish on their new phone with their own PIN or their '
            'recovery sheet.'),
        FilledButton(key: const Key('helpDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ]);
    }
    return _Page(title: 'Help someone get back in', children: <Widget>[
      const _Note('Who lost their phone?', strong: true),
      const _Note('Only say yes if you have spoken to them yourself and you know it is them. You will be asked for your '
          'own PIN: that is your yes.'),
      _Problem(_problem),
      RadioGroup<String>(
        groupValue: _who,
        onChanged: (String? v) => setState(() => _who = v),
        child: Column(children: <Widget>[
          for (final CanHelp p in widget.people)
            RadioListTile<String>(
                key: Key('who_${p.userId}'),
                value: p.userId,
                title: Text(p.name.isEmpty ? 'A grown-up in your family' : p.name)),
        ]),
      ),
      _PinBox(key: const Key('helpPinField'), controller: _pin, label: 'Your PIN', enabled: !_busy),
      FilledButton(
          key: const Key('helpStart'),
          onPressed: _busy ? null : _start,
          child: Text(_busy ? 'Working…' : 'Yes, help them')),
    ]);
  }
}

// =====================================================================================================================
//  The trusted helper's side
// =====================================================================================================================

/// The person handed a helper code types it here. They get a key that opens one screen, not an account.
class BecomeHelperScreen extends StatefulWidget {
  const BecomeHelperScreen({super.key, required this.service});
  final RecoveryPathsService service;

  @override
  State<BecomeHelperScreen> createState() => _BecomeHelperScreenState();
}

class _BecomeHelperScreenState extends State<BecomeHelperScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  bool _checking = true;
  AccountProblem? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(_existing());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _existing() async {
    final HelperKey? k = await widget.service.helperIdentity();
    if (!mounted) return;
    if (k != null) {
      await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (BuildContext _) => HelperHomeScreen(service: widget.service)));
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _accept() async {
    if (_busy) return;
    final String typed = _code.text;
    final HelperKey? k = await _guarded<HelperKey>(() => widget.service.acceptHelperInvite(typed),
        setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (k == null || !mounted) return;
    _code.clear();
    await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (BuildContext _) => HelperHomeScreen(service: widget.service)));
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Be a helper', children: <Widget>[
        if (_checking) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!_checking) ...<Widget>[
          const _Note('Type the code you were given.', strong: true),
          const _Note('It has four groups of four letters and numbers. A helper can only say yes or no when the person '
              'who named them is getting their account back. A helper cannot see their family or sign in as them.'),
          _Problem(_problem),
          _CodeBox(key: const Key('helperInviteField'), controller: _code, label: 'Helper code', enabled: !_busy),
          FilledButton(
              key: const Key('helperAccept'),
              onPressed: _busy ? null : _accept,
              child: Text(_busy ? 'Checking…' : 'Continue')),
        ],
      ]);
}

/// A helper's one screen: who they help, and any recovery that names them. Yes or no. Nothing else.
class HelperHomeScreen extends StatefulWidget {
  const HelperHomeScreen({super.key, required this.service, this.now});
  final RecoveryPathsService service;
  final DateTime Function()? now;

  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  HelperKey? _me;
  List<HelperRequest> _requests = const <HelperRequest>[];
  bool _loading = true;
  bool _busy = false;
  AccountProblem? _problem;
  String? _note;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final HelperKey? me = await widget.service.helperIdentity();
    List<HelperRequest>? list;
    if (me != null) {
      list = await _guarded<List<HelperRequest>>(widget.service.helperRequests,
          setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    }
    // A helper key the server no longer knows was forgotten by the service: look again so the screen says so.
    final HelperKey? still = await widget.service.helperIdentity();
    if (!mounted) return;
    setState(() {
      _me = still;
      _requests = list ?? const <HelperRequest>[];
      _loading = false;
    });
  }

  Future<void> _answer(HelperRequest r, bool yes) async {
    final bool? sure = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
              title: Text(yes ? 'Say yes?' : 'Say no?'),
              content: Text(yes
                  ? 'Only say yes if you have spoken to ${r.accountName.isEmpty ? 'them' : r.accountName} yourself and you know it '
                      'is really them. Your yes does not make it faster: they still wait.'
                  : 'This stops the recovery. Nothing will change for ${r.accountName.isEmpty ? 'them' : r.accountName}, and they can '
                      'start again if it was really them.'),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
                FilledButton(key: const Key('confirmAnswer'), onPressed: () => Navigator.pop(c, true), child: Text(yes ? 'Yes, it is them' : 'No, stop it')),
              ],
            ));
    if (sure != true) return;
    final bool? ok = await _guarded<bool>(() async {
      await widget.service.answer(requestId: r.requestId, yes: yes);
      return true;
    }, setBusy: (bool b) => setState(() => _busy = b), setProblem: (AccountProblem? p) => setState(() => _problem = p));
    if (ok == true && mounted) {
      setState(() => _note = yes ? 'You said yes. Thank you.' : 'You said no. The recovery was stopped.');
      unawaited(_load());
    }
  }

  Future<void> _stopBeing() async {
    await widget.service.forgetHelper();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final HelperKey? me = _me;
    return _Page(title: 'Trusted helper', children: <Widget>[
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (!_loading && me == null) ...<Widget>[
        _Problem(_problem),
        const _Note('This phone is not anyone\'s helper.', key: Key('notAHelper')),
        FilledButton(key: const Key('helperBack'), onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      ],
      if (!_loading && me != null) ...<Widget>[
        _Note('You are ${me.accountName.isEmpty ? 'their' : '${me.accountName}\'s'} trusted helper.', strong: true, key: const Key('helperIdentity')),
        const _Note('If they lose their phone, they may ask you to say yes. That is all a helper does. You cannot see '
            'their family, and you cannot sign in as them.'),
        if (_note != null) _Note(_note!, key: const Key('helperNote')),
        _Problem(_problem),
        if (_requests.isEmpty)
          const _Note('Nothing is waiting for you right now.', key: Key('helperNothing'))
        else
          for (final HelperRequest r in _requests)
            Card(
              key: Key('request_${r.requestId}'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('${r.accountName.isEmpty ? 'Someone' : r.accountName} is getting their account back on a new phone.',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('Started ${whenWords(r.startedAt, _now())}. They can finish ${whenWords(r.readyAt, _now())}.'),
                  const SizedBox(height: 6),
                  Text(r.confirmed ? 'You have said yes.' : 'Is this really them?'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
                    if (!r.confirmed)
                      FilledButton(key: Key('yes_${r.requestId}'), onPressed: _busy ? null : () => _answer(r, true), child: const Text('Yes, it is them')),
                    OutlinedButton(key: Key('no_${r.requestId}'), onPressed: _busy ? null : () => _answer(r, false), child: const Text('No, stop it')),
                  ]),
                ]),
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton(key: const Key('helperRefresh'), onPressed: _busy ? null : _load, child: const Text('Check again')),
        TextButton(key: const Key('helperStop'), onPressed: _stopBeing, child: const Text('Stop being their helper on this phone')),
      ],
    ]);
  }
}
