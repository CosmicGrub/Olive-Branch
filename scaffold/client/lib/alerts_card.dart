// UNVERIFIED on a real device and against Google: covered by flutter test only (MASTERFILE 7.20).
// OLIVE BRANCH — "Alerts on this tablet": the grown-up's card for what the phone allows. MASTERFILE §11, §7.18.
//
// WHERE IT LIVES: inside Guardian mode (guardian_escalation_screen.dart), which a grown-up reaches only after the
// PIN and the biometric. A child never sees this card and never sees the system's own "allow notifications" box,
// because nothing on her side ever asks for it: the box is shown here, when a grown-up taps Allow.
//
// WHAT IT SAYS: two plain facts a grown-up can act on.
//   * Pop-up alerts: on or off. Without them the tablet is not rung and "something new" alerts do not show.
//     (On Android 13 and later the permission is off until it is allowed once.)
//   * Rings over the lock screen: on or off. On Android 14 and later a sideloaded app starts with this off.
// Nothing else, no counts, nothing about the child. Where there is no native side (Windows, tests) the card draws
// nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'incoming_call_channel.dart';

class AlertsCard extends StatefulWidget {
  const AlertsCard({super.key, this.channel});

  /// Test seam; the real bridge by default.
  final IncomingCallChannel? channel;

  @override
  State<AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<AlertsCard> {
  late final IncomingCallChannel _channel = widget.channel ?? IncomingCallChannel();
  AlertStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final AlertStatus? s = await _channel.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _allowAlerts() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool allowed = await _channel.requestNotifications();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!allowed) {
      // The system only shows its box a limited number of times; after that the phone's own settings page is the
      // way. Opening it is the grown-up's own tap on a clearly labelled button.
      try {
        await const MethodChannel('olive/app_settings').invokeMethod<void>('open');
      } on MissingPluginException {
        // No settings page to open here.
      } on PlatformException {
        // Nothing more to do; the card keeps saying "Off".
      }
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AlertStatus? s = _status;
    if (s == null) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        key: const Key('alertsCard'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Alerts on this tablet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'These decide whether this tablet can be rung and can show a quiet "something new" alert. '
            'They only matter once the tablet is connected to your server.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _row(
            context,
            key: 'alertsNotifications',
            label: 'Pop-up alerts',
            on: s.notifications,
            action: s.notifications ? null : FilledButton(
              key: const Key('alertsAllow'),
              onPressed: _busy ? null : _allowAlerts,
              child: const Text('Allow'),
            ),
          ),
          _row(
            context,
            key: 'alertsFullScreen',
            label: 'Rings over the lock screen',
            on: s.fullScreen,
            action: s.fullScreen ? null : OutlinedButton(
              key: const Key('alertsFullScreenSettings'),
              onPressed: () async {
                await _channel.openFullScreenSettings();
                await _refresh();
              },
              child: const Text('Open settings'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, {required String key, required String label, required bool on, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: <Widget>[
        Icon(on ? Icons.check_circle_outline : Icons.error_outline,
            size: 20, color: on ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text('$label: ${on ? 'on' : 'off'}', key: Key(key))),
        ?action,
      ]),
    );
  }
}
