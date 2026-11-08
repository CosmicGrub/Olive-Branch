// OLIVE BRANCH — the screens for the LOCAL guardian PIN: choose one, and be asked for
// it. No longer UNVERIFIED — verified by CI (client/test/local_pin_screens_test.dart).
// MASTERFILE §8.5.9.
//
// [LocalPinSetupForm] is the two-field "choose a PIN" form (used inside the guardian
// onboarding and by [LocalPinSetupScreen], the exit from the old offline server-PIN trap).
// [askLocalPin] is the gate: a small dialog that returns true only when the PIN checked
// out. Both talk to [LocalPinService] and never see the PIN again after the call.
//
// The words are the account PIN's words where there is one (guardian_setup.dart): "Enter
// a 4-8 digit PIN.", "The two PINs don't match.", and the lockout line
// ([kLocalPinLockedMessage]). A wrong or locked PIN never reveals anything else.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'local_pin.dart';

/// The two-field form. [onSaved] fires after the PIN is really stored; a store that cannot
/// be written shows a message and does NOT call it (the PIN would not exist after a restart).
class LocalPinSetupForm extends StatefulWidget {
  const LocalPinSetupForm({super.key, required this.service, required this.onSaved, this.saveLabel = 'Save PIN'});
  final LocalPinService service;
  final VoidCallback onSaved;
  final String saveLabel;

  @override
  State<LocalPinSetupForm> createState() => _LocalPinSetupFormState();
}

class _LocalPinSetupFormState extends State<LocalPinSetupForm> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_working) return;
    if (!isValidLocalPin(_pin.text)) {
      setState(() => _error = 'Enter a 4-8 digit PIN.');
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = "The two PINs don't match.");
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.service.setPin(_pin.text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Could not keep your PIN on this device. Please try again.';
      });
      return;
    }
    if (!mounted) return;
    _pin.clear();
    _confirm.clear();
    setState(() => _working = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      TextField(
        key: const Key('localPinNew'),
        controller: _pin,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        maxLength: kLocalPinMaxDigits,
        decoration: const InputDecoration(labelText: 'New PIN', counterText: '', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('localPinConfirm'),
        controller: _confirm,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        maxLength: kLocalPinMaxDigits,
        decoration: const InputDecoration(labelText: 'Confirm PIN', counterText: '', border: OutlineInputBorder()),
        onSubmitted: (_) => _save(),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!,
              key: const Key('localPinError'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
        ),
      const SizedBox(height: 16),
      SizedBox(
        height: 56,
        child: FilledButton(
          key: const Key('localPinSave'),
          onPressed: _working ? null : _save,
          child: _working
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Text(widget.saveLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/// A whole screen around [LocalPinSetupForm]: what an offline grown-up with no PIN sees
/// (the exit from the old undismissable server-PIN trap). It works with no server.
class LocalPinSetupScreen extends StatelessWidget {
  const LocalPinSetupScreen({super.key, required this.service, required this.onDone});
  final LocalPinService service;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose a PIN for this device')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Icon(Icons.pin_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'This PIN is only for this device. It guards your settings, her locked age and '
                'clearing data, and works with no connection.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              LocalPinSetupForm(service: service, onSaved: onDone, saveLabel: 'Save PIN and continue'),
            ]),
          ),
        ),
      );
}

/// Asks for the local PIN. True only when it checked out; false when cancelled. A locked
/// PIN says so and stays on screen until cancelled.
Future<bool> askLocalPin(BuildContext context, LocalPinService service,
    {String title = 'Enter your PIN', String? why}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => _AskDialog(service: service, title: title, why: why),
  );
  return ok == true;
}

class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.service, required this.title, this.why});
  final LocalPinService service;
  final String title;
  final String? why;

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  final TextEditingController _c = TextEditingController();
  String? _message;
  bool _working = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    setState(() => _working = true);
    final PinCheck r = await widget.service.verify(_c.text);
    if (!mounted) return;
    _c.clear();
    switch (r.outcome) {
      case PinOutcome.ok:
        Navigator.of(context).pop(true);
      case PinOutcome.locked:
        setState(() {
          _working = false;
          _message = kLocalPinLockedMessage;
        });
      case PinOutcome.notSet:
        setState(() {
          _working = false;
          _message = 'No PIN is set on this device yet.';
        });
      case PinOutcome.wrong:
        setState(() {
          _working = false;
          _message = 'That is not your PIN.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (widget.why != null) ...<Widget>[Text(widget.why!), const SizedBox(height: 12)],
          TextField(
            key: const Key('localPinField'),
            controller: _c,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            maxLength: kLocalPinMaxDigits,
            decoration: const InputDecoration(labelText: 'PIN', counterText: '', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!,
                  key: const Key('localPinAskMessage'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
        actions: <Widget>[
          TextButton(
            key: const Key('localPinCancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('localPinOk'),
            onPressed: _working ? null : _submit,
            child: const Text('OK'),
          ),
        ],
      );
}
