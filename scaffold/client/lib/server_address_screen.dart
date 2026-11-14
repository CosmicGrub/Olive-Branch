// OLIVE BRANCH — guardian-only "Server address". No longer UNVERIFIED —
// verified by CI (client/test/server_address_screen_test.dart).
//
// Where a grown-up changes which server this install talks to (see
// server_address.dart for the rules: https only, an origin only, kept in
// LocalStore, built-in address as the default). Built for a server reached
// through a free quick tunnel, whose address changes whenever the tunnel is
// restarted: one edit here instead of a new build.
//
// Same shape and the same gate as clear_local_data_screen.dart. Guardian-only
// (reached from guardian_more.dart; child_no_settings_contract_test.dart holds
// the child side). PIN-gated and FAIL CLOSED: both "Save" and "Use the built-in
// address" need the grown-up's PIN, checked by [verifyPin]; with none wired the
// screen says so and changes nothing, and a verifier that throws counts as a
// wrong PIN.
//
// It does not unpair anyone and does not touch the server. A change is read at
// the next start, so the screen says to close and reopen Olive.
import 'package:flutter/material.dart';

import 'local_services.dart';
import 'server_address.dart';

class ServerAddressScreen extends StatefulWidget {
  const ServerAddressScreen({super.key, required this.verifyPin, this.services});

  /// Checks the grown-up's PIN; true only for a PIN that was really verified.
  /// Null means there is nothing to check it against, and nothing can change.
  final Future<bool> Function(String pin)? verifyPin;

  /// Null means [LocalServices.current].
  final LocalServices? services;

  @override
  State<ServerAddressScreen> createState() => _ServerAddressScreenState();
}

enum _Phase { idle, checking, wrongPin, badAddress, saved, reset, failed }

class _ServerAddressScreenState extends State<ServerAddressScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  _Phase _phase = _Phase.idle;
  String? _problem;

  LocalServices get _services => widget.services ?? LocalServices.current;

  @override
  void dispose() {
    _address.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<bool> _pinOk() async {
    final verify = widget.verifyPin;
    if (verify == null || _pin.text.isEmpty) return false;
    try {
      return await verify(_pin.text);
    } catch (_) {
      return false; // fail closed: a check that cannot run is a wrong PIN
    }
  }

  Future<void> _save() async {
    final String? why = ServerAddress.problem(_address.text);
    if (why != null) {
      setState(() {
        _phase = _Phase.badAddress;
        _problem = why;
      });
      return;
    }
    setState(() => _phase = _Phase.checking);
    if (!await _pinOk()) {
      if (mounted) setState(() => _phase = _Phase.wrongPin);
      return;
    }
    try {
      final String? refused =
          await ServerAddress.save(_services.area(kServerAddressArea), _address.text);
      if (!mounted) return;
      _pin.clear();
      setState(() {
        _phase = refused == null ? _Phase.saved : _Phase.badAddress;
        _problem = refused;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _useBuiltIn() async {
    setState(() => _phase = _Phase.checking);
    if (!await _pinOk()) {
      if (mounted) setState(() => _phase = _Phase.wrongPin);
      return;
    }
    try {
      await ServerAddress.reset(_services.area(kServerAddressArea));
      if (!mounted) return;
      _pin.clear();
      _address.clear();
      setState(() => _phase = _Phase.reset);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool canVerify = widget.verifyPin != null;
    final bool busy = _phase == _Phase.checking;
    return Scaffold(
      appBar: AppBar(title: const Text('Server address')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(
                'This is the server Olive connects to. You only need this if the address you were '
                'given has changed. Everything you set up on this phone stays on this phone either way.',
                style: text.bodyMedium),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('In use now', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  SelectableText(ServerAddress.current, key: const Key('serverAddressCurrent')),
                  const SizedBox(height: 8),
                  Text(
                      ServerAddress.usingOverride
                          ? 'An address you typed here.'
                          : 'The address this copy of Olive was built with.',
                      key: const Key('serverAddressSource'),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  if (ServerAddress.usingOverride) ...<Widget>[
                    const SizedBox(height: 4),
                    Text('Built-in: $kBuiltInBaseUrl',
                        key: const Key('serverAddressBuiltIn'),
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (!canVerify)
              Container(
                key: const Key('serverAddressUnavailable'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(
                    'Changing the address needs your PIN, and there is no way to check it in this '
                    'build yet. Nothing has been changed.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
              )
            else ...<Widget>[
              TextField(
                key: const Key('serverAddressField'),
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'New address',
                    hintText: 'https://example.com',
                    border: OutlineInputBorder()),
                onChanged: (_) => setState(() => _phase = _Phase.idle),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('serverAddressPin'),
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    const InputDecoration(labelText: 'Your PIN', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {
                  if (_phase == _Phase.wrongPin) _phase = _Phase.idle;
                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  key: const Key('serverAddressSave'),
                  onPressed:
                      busy || _pin.text.isEmpty || _address.text.trim().isEmpty ? null : _save,
                  child: const Text('Save this address'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('serverAddressReset'),
                  onPressed: busy || _pin.text.isEmpty || !ServerAddress.usingOverride
                      ? null
                      : _useBuiltIn,
                  child: const Text('Use the built-in address'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_phase == _Phase.wrongPin)
              Text('That PIN did not match. Nothing was changed.',
                  key: const Key('serverAddressWrongPin'),
                  style: text.bodyMedium?.copyWith(color: scheme.error)),
            if (_phase == _Phase.badAddress)
              Text(_problem ?? 'That address cannot be used.',
                  key: const Key('serverAddressBad'),
                  style: text.bodyMedium?.copyWith(color: scheme.error)),
            if (_phase == _Phase.saved)
              Text('Saved. Close Olive completely and open it again to use the new address.',
                  key: const Key('serverAddressSaved'), style: text.bodyMedium),
            if (_phase == _Phase.reset)
              Text('The built-in address will be used. Close Olive completely and open it again.',
                  key: const Key('serverAddressWasReset'), style: text.bodyMedium),
            if (_phase == _Phase.failed)
              Text('Something stopped that. Nothing was changed. Try again.',
                  key: const Key('serverAddressFailed'),
                  style: text.bodyMedium?.copyWith(color: scheme.error)),
            const SizedBox(height: 20),
            Text('What to know', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                'Only https:// addresses are used; a plain http:// address is refused. '
                'This address is not pinned to a certificate, because a temporary address '
                'gets a new certificate often. A stable address with a pinned certificate '
                'is the safer long-term setup.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
