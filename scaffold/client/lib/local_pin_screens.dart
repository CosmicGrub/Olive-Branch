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

import 'guardian_local_scope.dart';
import 'local_pin.dart';
import 'guardian_pin_recovery_screens.dart';

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
    if (isEasyGuessLocalPin(_pin.text)) {
      setState(() => _error = kEasyGuessPinMessage);
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

/// Change the local PIN: the current one, a new one, the new one again (the prototype's
/// g-pin and ob.pinInfo, on this device). The explainer is true to THIS build: the PIN
/// guards settings, her locked age and clearing data, five wrong tries pause it for 15
/// minutes, and a child's app has no way to make or change one. A new PIN may not be
/// the old one or one anyone would guess first ([isEasyGuessLocalPin]). It is 4 to 8 digits
/// here (the prototype says exactly 4; an open owner decision), and the current PIN is
/// proved before anything changes ([LocalPinService.change]).
class LocalPinChangeScreen extends StatefulWidget {
  const LocalPinChangeScreen({super.key, required this.service, this.onChanged});
  final LocalPinService service;
  final VoidCallback? onChanged;

  @override
  State<LocalPinChangeScreen> createState() => _LocalPinChangeScreenState();
}

class _LocalPinChangeScreenState extends State<LocalPinChangeScreen> {
  final TextEditingController _cur = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  String? _done;
  bool _working = false;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    setState(() { _error = null; _done = null; });
    if (!isValidLocalPin(_new.text)) {
      setState(() => _error = 'Enter a 4-8 digit PIN.');
      return;
    }
    if (_new.text == _cur.text) {
      setState(() => _error = 'Pick a PIN that is different from the current one.');
      return;
    }
    if (isEasyGuessLocalPin(_new.text)) {
      setState(() => _error = kEasyGuessPinMessage);
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = "The two PINs don't match.");
      return;
    }
    setState(() => _working = true);
    PinCheck r;
    try {
      r = await widget.service.change(_cur.text, _new.text);
    } on EasyGuessPinException {
      if (!mounted) return;
      setState(() { _working = false; _error = kEasyGuessPinMessage; });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Could not keep your new PIN on this device. Your old PIN still works.';
      });
      return;
    }
    if (!mounted) return;
    _cur.clear();
    switch (r.outcome) {
      case PinOutcome.ok:
        _new.clear();
        _confirm.clear();
        setState(() { _working = false; _done = 'Your PIN is changed.'; });
        widget.onChanged?.call();
      case PinOutcome.locked:
        setState(() { _working = false; _error = kLocalPinLockedMessage; });
      case PinOutcome.notSet:
        setState(() { _working = false; _error = 'No PIN is set on this device yet.'; });
      case PinOutcome.wrong:
        setState(() { _working = false; _error = 'That is not your current PIN. ${r.attemptsLeft} ${r.attemptsLeft == 1 ? 'try' : 'tries'} left before it pauses.'; });
    }
  }

  Widget _field(Key k, TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: k,
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          maxLength: kLocalPinMaxDigits,
          decoration: InputDecoration(labelText: label, counterText: '', border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Card(
              key: const Key('pinInfoCard'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Your PIN protects your settings, her locked age and clearing data on this device. '
                  'A child can never make or change one. Five wrong tries pause it for 15 minutes.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _field(const Key('pinChangeCurrent'), _cur, 'Current PIN'),
            _field(const Key('pinChangeNew'), _new, 'New PIN'),
            _field(const Key('pinChangeConfirm'), _confirm, 'Confirm new PIN'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, key: const Key('pinChangeError'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
            if (_done != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_done!, key: const Key('pinChangeDone')),
              ),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('pinChangeSave'),
                onPressed: _working ? null : _submit,
                child: const Text('Change PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
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

  bool _isDevicePin(BuildContext context) =>
      identical(GuardianLocalScope.maybeOf(context)?.services.pin, widget.service);

  Future<void> _forgot(BuildContext context) async {
    final GuardianLocalController scope = GuardianLocalScope.maybeOf(context)!;
    final bool? reset = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (BuildContext _) => ForgotPinScreen(pin: widget.service, recovery: scope.services.recovery)));
    // A new PIN now exists, but the thing this dialog guards is NOT approved by it: type the new PIN to go on.
    if (reset == true && mounted) setState(() => _message = 'Your new PIN is saved. Enter it to continue.');
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
          // Forgot it: only for THIS device's own PIN, and only where the guardian shell supplied the local services.
          // With no linked phone the screen it opens says plainly that clearing the app is the only reset.
          if (_isDevicePin(context))
            TextButton(
              key: const Key('localPinForgot'),
              onPressed: _working ? null : () => _forgot(context),
              child: const Text('Forgot your PIN?'),
            ),
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
