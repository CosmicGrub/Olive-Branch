// OLIVE BRANCH — the adult-safety settings screen: app lock, recent apps, quick hide.
// No longer UNVERIFIED — verified by CI (client/test/app_lock_test.dart). Plain adult
// words (§8.1). Logic lives in app_lock.dart.
import 'package:flutter/material.dart';

import 'app_lock.dart';

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
                  SwitchListTile(
                    key: const Key('hideRecentsSwitch'),
                    title: const Text('Hide Olive in the recent apps list'),
                    subtitle: const Text('The preview shows a blank card. This also stops screenshots in Olive.'),
                    value: p.hideRecents,
                    onChanged: (bool v) => _set(p.copyWith(hideRecents: v)),
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
