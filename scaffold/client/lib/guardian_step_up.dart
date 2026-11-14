// OLIVE BRANCH — the adult-side "type your PIN" step for actions the server guards with the
// guardian's own PIN (S-B3 step-up, MASTERFILE section 7.12). UNVERIFIED on a device; runs
// headless in CI (client/test/guardian_step_up_test.dart).
//
// WHAT NEEDS IT. Exports (raw and certified: the family's whole message log leaves the building),
// creating an invite (handing out access to a child), adding a passkey, and generating a pairing
// code. The server checks the PIN against the CALLER'S OWN pin_credential, with the same
// five-tries-then-fifteen-minutes lockout every other PIN check shares. This file only asks for
// the PIN and says plainly what went wrong; it never checks one itself.
//
// WHO SEES IT. Grown-ups only. Every screen that uses it is on the guardian side, and each of the
// routes behind it already answers a child session with 403, so a child never reaches a PIN
// prompt and never reads one of these messages (MASTERFILE section 2.1: a child sees no error
// text). The words are plain adult words ("That PIN doesn't match"), not the soft kid wording.
//
// HONEST ERRORS. A wrong PIN says so and asks again. A locked PIN says it is locked and does not
// ask again (another try cannot help and would only look like a bypass). A PIN that was never set
// says so. Any other failure (a denial, no network) is NOT swallowed here: [runWithGuardianPin]
// rethrows it for the screen to explain in its own words. Nothing is ever reported as done when
// the server refused.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'api_client.dart' show ApiException;
import 'local_pin.dart' show kLocalPinMaxDigits, kLocalPinMinDigits;

/// The server's step-up refusals (routes.mjs `requireOwnPin`).
const Set<String> kPinStepUpErrors = <String>{
  'pin_required', 'pin_incorrect', 'pin_locked', 'pin_not_set', 'invalid_pin_format',
};

/// Typing the PIN again can fix these; it cannot fix `pin_locked` or `pin_not_set`.
const Set<String> kPinStepUpRetryable = <String>{'pin_required', 'pin_incorrect', 'invalid_pin_format'};

bool isPinStepUpError(Object e) => e is ApiException && kPinStepUpErrors.contains(e.error);

/// Plain adult words for a step-up refusal. Matches the account PIN's own wording
/// (guardian_setup.dart) where one exists.
String guardianStepUpMessage(String error) => switch (error) {
      'pin_required' || 'invalid_pin_format' => 'Enter your $kLocalPinMinDigits-$kLocalPinMaxDigits digit PIN.',
      'pin_incorrect' => "That PIN doesn't match. Try again.",
      'pin_locked' => 'Too many wrong tries. Try again in 15 minutes.',
      'pin_not_set' => "You haven't set a PIN yet. Set one under Account first, then come back.",
      _ => "That didn't work. Check your connection and try again.",
    };

/// Where the PIN comes from. The default opens [askGuardianPinDialog]; a test passes its own.
/// Returns null when the grown-up cancels.
typedef GuardianPinSource = Future<String?> Function(
  BuildContext context, {
  required String title,
  String? why,
  String? error,
});

/// A small dialog with one PIN field. Returns the typed PIN (not yet checked: the server checks
/// it) or null on Cancel. [error] is shown above the field when this is a second ask.
Future<String?> askGuardianPinDialog(
  BuildContext context, {
  required String title,
  String? why,
  String? error,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _PinDialog(title: title, why: why, error: error),
    );

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.why, this.error});
  final String title;
  final String? why;
  final String? error;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    if (_c.text.length < kLocalPinMinDigits) return;
    Navigator.of(context).pop(_c.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (widget.why != null) ...<Widget>[Text(widget.why!), const SizedBox(height: 12)],
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(widget.error!,
                  key: const Key('guardianPinError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextField(
            key: const Key('guardianPinField'),
            controller: _c,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            maxLength: kLocalPinMaxDigits,
            decoration: const InputDecoration(labelText: 'Your PIN', counterText: '', border: OutlineInputBorder()),
            onSubmitted: (_) => _ok(),
          ),
        ]),
        actions: <Widget>[
          TextButton(
            key: const Key('guardianPinCancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(key: const Key('guardianPinOk'), onPressed: _ok, child: const Text('Continue')),
        ],
      );
}

/// Asks for the PIN, runs [run] with it, and asks again while the server says the PIN is wrong
/// or missing. Returns [run]'s result, or null when the grown-up cancels.
///
/// Failures that are not PIN failures (a denial, no network, a 5xx) are rethrown untouched for the
/// caller to explain. For `pin_locked` and `pin_not_set` the ApiException is rethrown too, so the
/// caller can show [guardianStepUpMessage] in its own place (a snackbar, a card): asking again
/// would not help and must not look like a way around the lockout.
Future<T?> runWithGuardianPin<T>(
  BuildContext context, {
  required String title,
  String? why,
  required Future<T> Function(String pin) run,
  GuardianPinSource? source,
}) async {
  final GuardianPinSource ask = source ?? askGuardianPinDialog;
  String? error;
  while (true) {
    final String? pin = await ask(context, title: title, why: why, error: error);
    if (pin == null) return null;
    try {
      return await run(pin);
    } on ApiException catch (e) {
      if (!kPinStepUpRetryable.contains(e.error)) rethrow;
      error = guardianStepUpMessage(e.error);
      if (!context.mounted) return null;
    }
  }
}

/// The same ask as an in-page card, for a screen that needs the PIN before it can show anything
/// (the certified export loads on open). [onSubmit] gets the typed PIN; [error] is the last
/// refusal in plain words; [working] disables the button while a call is out.
class GuardianPinCard extends StatefulWidget {
  const GuardianPinCard({
    super.key,
    required this.title,
    required this.why,
    required this.actionLabel,
    required this.onSubmit,
    this.error,
    this.working = false,
  });
  final String title, why, actionLabel;
  final String? error;
  final bool working;
  final void Function(String pin) onSubmit;

  @override
  State<GuardianPinCard> createState() => _GuardianPinCardState();
}

class _GuardianPinCardState extends State<GuardianPinCard> {
  final TextEditingController _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (widget.working || _c.text.length < kLocalPinMinDigits) return;
    final String pin = _c.text;
    _c.clear();
    widget.onSubmit(pin);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Icon(Icons.lock_outline, size: 36, color: scheme.primary),
            const SizedBox(height: 12),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(widget.why, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(widget.error!, key: const Key('guardianPinCardError'), style: TextStyle(color: scheme.error)),
              ),
            TextField(
              key: const Key('guardianPinCardField'),
              controller: _c,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              maxLength: kLocalPinMaxDigits,
              decoration: const InputDecoration(labelText: 'Your PIN', counterText: '', border: OutlineInputBorder()),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('guardianPinCardGo'),
                onPressed: widget.working ? null : _go,
                child: widget.working
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(widget.actionLabel),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
