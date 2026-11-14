// OLIVE BRANCH — the adult screens for local_pin_recovery.dart: link another grown-up's phone, reset a forgotten PIN
// from it, and approve such a reset on this phone. UNVERIFIED on a device; widget-tested headless
// (client/test/guardian_pin_recovery_screens_test.dart). MASTERFILE section 7.12.
//
// WHO SEES THESE. Grown-ups only. They are reached from the guardian shell (the Safety group of Settings, and the "Forgot
// your PIN?" line under the PIN prompt), never from the child side, and the words are plain adult words. A child sees
// no error text anywhere (MASTERFILE 2.1).
//
// HONEST. With no linked phone [ForgotPinScreen] says [kNoRecoveryWords] and offers nothing that looks like a reset.
// A picture that is not for this phone, or has run out, says so in one plain line and offers a new one. Nothing is
// ever shown as approved unless the signature checked out; nothing is sent anywhere.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'local_pin.dart';
import 'local_pin_recovery.dart';
import 'local_pin_screens.dart' show LocalPinSetupForm;

/// Tests supply a stand-in for the camera: it is handed a callback to call with the scanned text.
typedef ScannerBuilder = Widget Function(void Function(String value) onValue);

Widget _scanner(ScannerBuilder? custom, Key key, void Function(String) onValue) {
  if (custom != null) return custom(onValue);
  return MobileScanner(
      key: key,
      onDetect: (BarcodeCapture c) {
        final String? v = c.barcodes.isNotEmpty ? c.barcodes.first.rawValue : null;
        if (v != null) onValue(v);
      });
}

Widget _scanBox(Widget child) => SizedBox(height: 280, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child));

Widget _qr(Key key, String data) => Center(child: SizedBox(width: 240, height: 240, child: PrettyQrView.data(key: key, data: data)));

Widget _pinField(Key key, TextEditingController c, VoidCallback onSubmit, {String label = 'Your PIN'}) => TextField(
      key: key,
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      maxLength: kLocalPinMaxDigits,
      decoration: InputDecoration(labelText: label, counterText: '', border: const OutlineInputBorder()),
      onSubmitted: (_) => onSubmit(),
    );

// ================================================================================ forgot: the forgetful phone

/// "I forgot my PIN" on THIS phone. Pops with true once a new PIN is really stored.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.pin, required this.recovery, this.scannerBuilder});
  final LocalPinService pin;
  final GuardianRecovery? recovery;
  final ScannerBuilder? scannerBuilder;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

enum _F { loading, none, show, newPin }

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  _F _s = _F.loading;
  PinResetRequester? _requester;
  PinResetChallenge? _challenge;
  String? _message;
  bool _busy = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _requester?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final GuardianRecovery? r = widget.recovery;
    if (r == null) {
      setState(() => _s = _F.none);
      return;
    }
    try {
      final PinResetRequester q = await r.requester();
      final PinResetChallenge? c = await q.issue();
      if (!mounted) return;
      setState(() {
        _requester = q;
        _challenge = c;
        _s = c == null ? _F.none : _F.show;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _s = _F.none);
    }
  }

  Future<void> _fresh() async {
    final PinResetRequester? q = _requester;
    if (q == null) return;
    final PinResetChallenge? c = await q.issue();
    if (!mounted) return;
    setState(() {
      _challenge = c;
      _message = null;
      _scanning = false;
    });
  }

  Future<void> _onScanned(String raw) async {
    final PinResetRequester? q = _requester;
    if (_busy || q == null || _s != _F.show) return;
    _busy = true;
    final bool ok = await q.accept(raw);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _busy = false;
        _s = _F.newPin;
        _message = null;
      });
      return;
    }
    // One try per picture: the old challenge is spent, so a fresh one is made for the next attempt.
    final PinResetChallenge? c = await q.issue();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _challenge = c;
      _scanning = false;
      _message = "That didn't work. It may have run out of time, or come from a phone this one isn't linked to. "
          'Here is a new picture to show them.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot your PIN?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_s) {
            _F.loading => const Center(child: CircularProgressIndicator()),
            _F.none => ListView(children: <Widget>[
                Icon(Icons.lock_reset_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                const Text(kNoRecoveryWords, key: Key('forgotNoRecovery')),
                const SizedBox(height: 16),
                OutlinedButton(
                    key: const Key('forgotBack'), onPressed: () => Navigator.of(context).maybePop(false), child: const Text('Back')),
              ]),
            _F.show => ListView(children: <Widget>[
                Text("Ask your other grown-up's phone", style: tt.titleMedium),
                const SizedBox(height: 8),
                const Text("On their phone open Settings, Safety, Other grown-ups' phones, then \"Reset someone's PIN\", "
                    'and scan this picture. They will type their own PIN to say yes. It works once, for five minutes.'),
                const SizedBox(height: 12),
                if (_challenge != null) _qr(const Key('forgotChallengeQr'), _challenge!.toQr()),
                const SizedBox(height: 12),
                if (_scanning)
                  _scanBox(_scanner(widget.scannerBuilder, const Key('forgotScanner'), _onScanned))
                else
                  FilledButton(
                      key: const Key('forgotScanAnswer'),
                      onPressed: () => setState(() => _scanning = true),
                      child: const Text('Scan their answer')),
                if (_message != null)
                  Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, key: const Key('forgotMessage'))),
                TextButton(key: const Key('forgotFresh'), onPressed: _fresh, child: const Text('New picture')),
              ]),
            _F.newPin => ListView(children: <Widget>[
                Text('They said yes', key: const Key('forgotApproved'), style: tt.titleMedium),
                const SizedBox(height: 8),
                const Text('Choose a new PIN for this phone.'),
                const SizedBox(height: 16),
                LocalPinSetupForm(
                  service: widget.pin,
                  saveLabel: 'Save new PIN',
                  onSaved: () => Navigator.of(context).pop(true),
                ),
              ]),
          },
        ),
      ),
    );
  }
}

// ===================================================================== link: this phone and another one

/// Link another grown-up's phone (so each can reset the other's PIN), manage the links, and reach "Reset someone's
/// PIN". Needs THIS phone's PIN first: a link is trust, so only a grown-up who knows the PIN can add one.
class GuardianPhonesScreen extends StatefulWidget {
  const GuardianPhonesScreen({
    super.key,
    required this.pin,
    required this.recovery,
    this.myLabel = 'A grown-up',
    this.scannerBuilder,
  });
  final LocalPinService pin;
  final GuardianRecovery recovery;
  final String myLabel;
  final ScannerBuilder? scannerBuilder;

  @override
  State<GuardianPhonesScreen> createState() => _GuardianPhonesScreenState();
}

class _GuardianPhonesScreenState extends State<GuardianPhonesScreen> {
  final TextEditingController _pinText = TextEditingController();
  final TextEditingController _label = TextEditingController();
  bool _unlocked = false, _busy = false, _scanning = false;
  String? _message;
  String? _offer;
  GuardianLinker? _linker;
  List<GuardianPeer> _peers = <GuardianPeer>[];

  @override
  void initState() {
    super.initState();
    _label.text = widget.myLabel;
  }

  @override
  void dispose() {
    _pinText.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    final PinCheck c = await widget.pin.verify(_pinText.text);
    if (!mounted) return;
    _pinText.clear();
    if (!c.ok) {
      setState(() {
        _busy = false;
        _message = switch (c.outcome) {
          PinOutcome.locked => kLocalPinLockedMessage,
          PinOutcome.notSet => 'No PIN is set on this phone yet. Choose one first.',
          _ => 'That is not your PIN.',
        };
      });
      return;
    }
    final GuardianLinker l = await widget.recovery.linker();
    final List<GuardianPeer> peers = await l.peers();
    final String offer = await l.offer(_label.text);
    if (!mounted) return;
    setState(() { _busy = false; _unlocked = true; _linker = l; _peers = peers; _offer = offer; });
  }

  Future<void> _refreshOffer() async {
    final GuardianLinker? l = _linker;
    if (l == null) return;
    final String offer = await l.offer(_label.text);
    if (mounted) setState(() => _offer = offer);
  }

  Future<void> _onScanned(String raw) async {
    final GuardianLinker? l = _linker;
    if (_busy || l == null) return;
    _busy = true;
    final LinkResult r = await l.accept(raw);
    final List<GuardianPeer> peers = await l.peers();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _peers = peers;
      if (r == LinkResult.linked) _scanning = false;
      _message = switch (r) {
        LinkResult.linked => 'Linked. Now do the same on their phone, so each of you can help the other.',
        LinkResult.alreadyLinked => 'That phone is already linked.',
        LinkResult.ownKey => 'That is this phone. Scan the picture on the other grown-up\'s phone.',
        LinkResult.full => 'This phone already has $kMaxGuardianPeers linked phones. Remove one first.',
        LinkResult.notAnOffer => "That isn't a link picture from another grown-up's phone.",
      };
    });
  }

  Future<void> _remove(int i) async {
    await _linker?.remove(i);
    final List<GuardianPeer> peers = await _linker?.peers() ?? <GuardianPeer>[];
    if (mounted) setState(() { _peers = peers; _message = 'Removed. That phone can no longer reset this one.'; });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Other grown-ups' phones")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: !_unlocked
              ? ListView(children: <Widget>[
                  const Text('Enter your PIN to link or manage other grown-ups\' phones.'),
                  const SizedBox(height: 12),
                  _pinField(const Key('phonesPin'), _pinText, _unlock),
                  if (_message != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('phonesMessage'))),
                  const SizedBox(height: 12),
                  SizedBox(height: 52, child: FilledButton(key: const Key('phonesUnlock'), onPressed: _busy ? null : _unlock, child: const Text('Continue'))),
                ])
              : ListView(children: <Widget>[
                  const Text(
                      'Linked phones can reset each other\'s forgotten PIN with no internet. Do this together, in person, '
                      'on both phones. A linked phone can only do that one thing: it sees nothing of your family.'),
                  const SizedBox(height: 16),
                  Text('Linked phones', style: tt.titleMedium),
                  if (_peers.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('None yet. Without one, a forgotten PIN can only be reset by clearing the app, which erases '
                            'the family on this phone.', key: Key('phonesNone'))),
                  for (int i = 0; i < _peers.length; i++)
                    ListTile(
                      key: Key('phonesPeer$i'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smartphone_outlined),
                      title: Text(_peers[i].label),
                      trailing: TextButton(key: Key('phonesRemove$i'), onPressed: () => _remove(i), child: const Text('Remove')),
                    ),
                  const Divider(height: 32),
                  Text('Link another phone', style: tt.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('phonesLabel'),
                    controller: _label,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'What the other phone calls this one', border: OutlineInputBorder()),
                    onChanged: (_) => _refreshOffer(),
                  ),
                  if (_offer != null) _qr(const Key('phonesOfferQr'), _offer!),
                  const SizedBox(height: 12),
                  if (_scanning)
                    _scanBox(_scanner(widget.scannerBuilder, const Key('phonesScanner'), _onScanned))
                  else
                    FilledButton(
                        key: const Key('phonesScan'),
                        onPressed: () => setState(() => _scanning = true),
                        child: const Text("Scan the other phone's picture")),
                  if (_message != null)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, key: const Key('phonesMessage'))),
                  const Divider(height: 32),
                  OutlinedButton(
                      key: const Key('phonesApprove'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (BuildContext _) => ApprovePinResetScreen(
                              pin: widget.pin, recovery: widget.recovery, scannerBuilder: widget.scannerBuilder))),
                      child: const Text("Reset someone's PIN")),
                ]),
        ),
      ),
    );
  }
}

// ============================================================================ approve: the helper phone

/// The OTHER grown-up's side: scan the forgetful phone's picture, type YOUR OWN PIN, show the answer.
class ApprovePinResetScreen extends StatefulWidget {
  const ApprovePinResetScreen({super.key, required this.pin, required this.recovery, this.scannerBuilder});
  final LocalPinService pin;
  final GuardianRecovery recovery;
  final ScannerBuilder? scannerBuilder;

  @override
  State<ApprovePinResetScreen> createState() => _ApprovePinResetScreenState();
}

enum _A { scan, confirm, answer }

class _ApprovePinResetScreenState extends State<ApprovePinResetScreen> {
  final TextEditingController _pinText = TextEditingController();
  _A _s = _A.scan;
  PinResetHelper? _helper;
  PinResetView? _view;
  String? _answer;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _pinText.dispose();
    super.dispose();
  }

  Future<void> _onScanned(String raw) async {
    if (_busy || _s != _A.scan) return;
    _busy = true;
    final PinResetHelper h = _helper ??= await widget.recovery.helper();
    final PinResetView? v = await h.inspect(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (v == null) {
        _message = "That isn't a reset picture from a phone linked to this one, or it ran out of time. Ask them for a new one.";
      } else {
        _view = v;
        _message = null;
        _s = _A.confirm;
      }
    });
  }

  Future<void> _approve() async {
    final PinResetHelper? h = _helper;
    final PinResetView? v = _view;
    if (_busy || h == null || v == null) return;
    setState(() { _busy = true; _message = null; });
    final PinCheck c = await widget.pin.verify(_pinText.text);
    if (!mounted) return;
    _pinText.clear();
    if (!c.ok) {
      setState(() {
        _busy = false;
        _message = c.outcome == PinOutcome.locked ? kLocalPinLockedMessage : 'That is not your PIN.';
      });
      return;
    }
    // Re-check at the moment of signing: the picture may have run out while the PIN was typed.
    final PinResetView? again = await h.inspect(v.challenge.toQr());
    if (!mounted) return;
    if (again == null) {
      setState(() { _busy = false; _s = _A.scan; _message = 'That picture ran out of time. Ask them for a new one.'; });
      return;
    }
    final String grant = await h.grant(again);
    if (!mounted) return;
    setState(() { _busy = false; _answer = grant; _s = _A.answer; });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Reset someone's PIN")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_s) {
            _A.scan => ListView(children: <Widget>[
                const Text('On their phone tap "Forgot your PIN?" and scan the picture it shows. Only do this if they are with you.'),
                const SizedBox(height: 12),
                _scanBox(_scanner(widget.scannerBuilder, const Key('approveScanner'), _onScanned)),
                if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, key: const Key('approveMessage'))),
              ]),
            _A.confirm => ListView(children: <Widget>[
                Text('Let ${_view!.peer.label} choose a new PIN?', key: const Key('approveTitle'), style: tt.titleMedium),
                const SizedBox(height: 8),
                const Text('Saying yes lets whoever is holding that phone set a new PIN on it. Type your own PIN to say yes.'),
                const SizedBox(height: 12),
                _pinField(const Key('approvePin'), _pinText, _approve),
                if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('approveMessage'))),
                const SizedBox(height: 12),
                SizedBox(height: 52, child: FilledButton(key: const Key('approveYes'), onPressed: _busy ? null : _approve, child: const Text('Yes, let them'))),
              ]),
            _A.answer => ListView(children: <Widget>[
                const Text('Now they scan this.', key: Key('approveAnswerTitle')),
                const SizedBox(height: 12),
                _qr(const Key('approveAnswerQr'), _answer!),
                const SizedBox(height: 12),
                const Text('It works once, for a few minutes. Your PIN was not sent anywhere.'),
                const SizedBox(height: 12),
                OutlinedButton(key: const Key('approveDone'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
              ]),
          },
        ),
      ),
    );
  }
}
