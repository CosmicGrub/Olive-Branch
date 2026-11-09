// OLIVE BRANCH — the ADULT side of "use my phone to unlock": scan the tablet's one-time challenge, type your PIN,
// show the answer for the tablet to scan. UNVERIFIED on a device; widget-tested headless
// (client/test/unlock_child_screen_test.dart). Spec 2026-11-08-adult-gate-and-simple-pairing-design.md 7.2.
//
// The phone only answers a challenge that names a tablet THIS phone connected and has not forgotten, that has not
// expired, and only after the grown-up's own PIN checked out on this phone (the local PIN service: lockout,
// constant time). It says in plain words what it is about to allow. The answer it shows is useful once, to that
// tablet, for those seconds.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'local_pin.dart';
import 'unlock_challenge.dart';

class UnlockChildScreen extends StatefulWidget {
  const UnlockChildScreen({super.key, required this.pin, required this.responder, required this.childName, this.scannerBuilder});
  final LocalPinService pin;
  final UnlockResponder responder;
  final String childName;

  /// Tests supply a stand-in for the camera.
  final Widget Function(void Function(String value) onValue)? scannerBuilder;

  @override
  State<UnlockChildScreen> createState() => _UnlockChildScreenState();
}

enum _S { scan, confirm, answer }

class _UnlockChildScreenState extends State<UnlockChildScreen> {
  final TextEditingController _pin = TextEditingController();
  _S _s = _S.scan;
  ChallengeView? _view;
  String? _answer;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _onScanned(String raw) async {
    if (_busy || _s != _S.scan) return;
    _busy = true;
    final ChallengeView? v = await widget.responder.inspect(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (v == null) {
        _message = "That is not a picture from a tablet you connected, or it ran out of time. Ask the tablet for a new one.";
      } else {
        _view = v;
        _message = null;
        _s = _S.confirm;
      }
    });
  }

  Future<void> _approve() async {
    if (_busy || _view == null) return;
    setState(() { _busy = true; _message = null; });
    final PinCheck c = await widget.pin.verify(_pin.text);
    if (!mounted) return;
    _pin.clear();
    if (!c.ok) {
      setState(() {
        _busy = false;
        _message = c.outcome == PinOutcome.locked ? kLocalPinLockedMessage : 'That is not your PIN.';
      });
      return;
    }
    // Re-check at the moment of signing: the tablet may have been forgotten, or the challenge may have run out.
    final ChallengeView? again = await widget.responder.inspect(_view!.challenge.toQr());
    if (!mounted) return;
    if (again == null) {
      setState(() { _busy = false; _s = _S.scan; _message = 'That picture ran out of time. Ask the tablet for a new one.'; });
      return;
    }
    final String grant = await widget.responder.grant(again);
    if (!mounted) return;
    setState(() { _busy = false; _answer = grant; _s = _S.answer; });
  }

  String _what(UnlockPurpose p) => p == UnlockPurpose.forget
      ? 'disconnect ${_view!.kid.deviceName} from you'
      : 'unlock ${_view!.kid.deviceName}';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text("Unlock ${widget.childName}'s device")),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_s) {
              _S.scan => ListView(children: <Widget>[
                  const Text("On her device, tap \"A grown-up does this\", then \"Use my phone\", and scan the picture it shows."),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 320,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: widget.scannerBuilder != null
                          ? widget.scannerBuilder!(_onScanned)
                          : MobileScanner(
                              key: const Key('unlockScanner'),
                              onDetect: (BarcodeCapture c) {
                                final String? v = c.barcodes.isNotEmpty ? c.barcodes.first.rawValue : null;
                                if (v != null) _onScanned(v);
                              }),
                    ),
                  ),
                  if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, key: const Key('unlockMessage'))),
                ]),
              _S.confirm => ListView(children: <Widget>[
                  Text('Do you want to ${_what(_view!.challenge.purpose)}?',
                      key: const Key('unlockConfirmTitle'), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('unlockPinField'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                    maxLength: kLocalPinMaxDigits,
                    decoration: const InputDecoration(labelText: 'Your PIN', counterText: '', border: OutlineInputBorder()),
                    onSubmitted: (_) => _approve(),
                  ),
                  if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('unlockMessage'))),
                  const SizedBox(height: 12),
                  SizedBox(height: 52, child: FilledButton(key: const Key('unlockApprove'), onPressed: _busy ? null : _approve, child: const Text('Yes'))),
                ]),
              _S.answer => ListView(children: <Widget>[
                  const Text('Now scan this with her device.', key: Key('unlockAnswerTitle')),
                  const SizedBox(height: 12),
                  Center(child: SizedBox(width: 240, height: 240, child: PrettyQrView.data(key: const Key('unlockAnswerQr'), data: _answer!))),
                  const SizedBox(height: 12),
                  const Text('It works once, for the next two minutes.'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
                ]),
            },
          ),
        ),
      );
}
