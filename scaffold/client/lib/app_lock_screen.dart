// OLIVE BRANCH — the adult-safety settings screen: app lock, recent apps, quick hide.
// No longer UNVERIFIED — verified by CI (client/test/app_lock_test.dart). Plain adult
// words (§8.1). Logic lives in app_lock.dart.
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'local_pin.dart';

/// The one calm sentence shown before screenshots are allowed (owner-approved wording, QR-VETTING-BRAINSTORM.md).
const String kScreenshotsAllowedWarning =
    'Anyone with this phone can then take pictures of what is on screen, and send them anywhere.';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key, required this.controller, required this.pinIsSet});
  final AppLockController controller;
  final bool pinIsSet;

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  AppLockController get c => widget.controller;
  String? _error;

  /// Private needs nothing. Screenshots allowed needs the grown-up's PIN on this phone and one yes to the sentence above.
  Future<void> _chooseScreens(AppLockPrefs p, bool allowed) async {
    if (allowed == p.screenshotsAllowed) return;
    if (!allowed) {
      await _set(p.copyWith(hideRecents: true));
      return;
    }
    if (!widget.pinIsSet) {
      setState(() => _error = 'Set a PIN for this phone first (Settings, Change PIN). Screenshots stay off until then.');
      return;
    }
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _AllowScreenshotsDialog(controller: c),
    );
    if (yes == true) await _set(p.copyWith(hideRecents: false));
  }

  Future<void> _set(AppLockPrefs next) async {
    try {
      await c.update(next);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'That could not be saved on this phone. Nothing changed.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (BuildContext context, Widget? _) {
          final AppLockPrefs p = c.prefs;
          return Scaffold(
            appBar: AppBar(title: const Text('App lock and privacy')),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  if (!widget.pinIsSet)
                    const Card(
                      key: Key('appLockNeedsPin'),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('The lock uses your PIN, and no PIN is set on this phone yet. '
                            'Set one under Change PIN, then come back.'),
                      ),
                    ),
                  SwitchListTile(
                    key: const Key('appLockSwitch'),
                    title: const Text('Lock Olive when I leave it'),
                    subtitle: const Text('Asks for your PIN when you come back, and when the app starts.'),
                    value: p.lockOnLeave,
                    onChanged: (bool v) => _set(p.copyWith(lockOnLeave: v)),
                  ),
                  if (p.lockOnLeave) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Text('Ask for the PIN', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    RadioGroup<AppLockDelay>(
                      groupValue: p.delay,
                      onChanged: (AppLockDelay? v) {
                        if (v != null) _set(p.copyWith(delay: v));
                      },
                      child: Column(children: <Widget>[
                        for (final AppLockDelay d in AppLockDelay.values)
                          RadioListTile<AppLockDelay>(
                              key: Key('appLockDelay_${d.name}'), title: Text(d.label), value: d),
                      ]),
                    ),
                  ],
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8, right: 16),
                    child: Text('Screens on this phone', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  RadioGroup<bool>(
                    groupValue: p.screenshotsAllowed,
                    onChanged: (bool? v) {
                      if (v != null) _chooseScreens(p, v);
                    },
                    child: const Column(children: <Widget>[
                      RadioListTile<bool>(
                        key: Key('screensPrivate'),
                        title: Text('Private'),
                        subtitle: Text('The recent apps preview is a blank card, and screenshots and screen '
                            'recordings of Olive are blocked.'),
                        value: false,
                      ),
                      RadioListTile<bool>(
                        key: Key('screensAllowed'),
                        title: Text('Screenshots allowed'),
                        subtitle: Text('Needs your PIN. PIN screens, locked health history and moods, and the '
                            'pairing picture stay blocked.'),
                        value: true,
                      ),
                    ]),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_error!,
                          key: const Key('appLockError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const Divider(),
                  ListTile(
                    key: const Key('quickHideNow'),
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Hide now'),
                    subtitle: const Text('Covers Olive with a plain notes page. Press and hold the word '
                        '“Notes” to come back.'),
                    onTap: () {
                      Navigator.of(context).maybePop();
                      c.quickHide();
                    },
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

/// Asks for the PIN (this phone's own), then shows the sentence. Pops true only after both.
class _AllowScreenshotsDialog extends StatefulWidget {
  const _AllowScreenshotsDialog({required this.controller});
  final AppLockController controller;
  @override
  State<_AllowScreenshotsDialog> createState() => _AllowScreenshotsDialogState();
}

class _AllowScreenshotsDialogState extends State<_AllowScreenshotsDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _message;
  bool _working = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_working) return;
    setState(() => _working = true);
    final PinCheck r = await widget.controller.pin.verify(_pin.text);
    if (!mounted) return;
    _pin.clear();
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _working = false;
      _message = r.outcome == PinOutcome.locked ? kLocalPinLockedMessage : 'That is not your PIN.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Allow screenshots?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text(kScreenshotsAllowedWarning, key: Key('screensWarning')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('screensPinField'),
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Your PIN'),
            onSubmitted: (_) => _go(),
          ),
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('screensMessage'))),
        ]),
        actions: <Widget>[
          TextButton(
              key: const Key('screensCancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it private')),
          FilledButton(
              key: const Key('screensConfirm'), onPressed: _working ? null : _go, child: const Text('Allow screenshots')),
        ],
      );
}
