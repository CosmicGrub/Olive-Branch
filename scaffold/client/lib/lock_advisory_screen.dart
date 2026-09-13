// OLIVE BRANCH — guardian shell, kiosk advisory. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). Renders MARKUP
// screen "lockAdvisory". MASTERFILE §5.20, §8.3.
//
// Calls the real lockAdvisory() from lock_controller.dart rather than
// reinventing that copy — this screen is a presentation layer over logic
// that already exists and is already tested (lock_controller_test.dart).
//
// This is the native setup flow's honesty check: before a guardian hands the
// device to their child, it says plainly what protection the ACTUAL platform
// underneath gives, rather than implying a uniform guarantee across Android,
// Windows and iOS that the platform primitives themselves don't provide (see
// lock_controller.dart's own doc comment on why defeat is expected, not
// exceptional).
import 'package:flutter/material.dart';
import 'lock_controller.dart' as lock;

String _platformLabel(lock.LockMode m) => switch (m) {
  lock.LockMode.locked => 'Android, fully managed',
  lock.LockMode.pinned => 'Android, screen pinning',
  lock.LockMode.assigned => 'Windows, Assigned Access',
  lock.LockMode.guided => 'iOS, Guided Access',
  lock.LockMode.none => 'No kiosk support detected',
};

IconData _platformIcon(lock.LockMode m) => switch (m) {
  lock.LockMode.locked => Icons.lock_outline,
  lock.LockMode.pinned => Icons.push_pin_outlined,
  lock.LockMode.assigned => Icons.desktop_windows_outlined,
  lock.LockMode.guided => Icons.accessibility_new_outlined,
  lock.LockMode.none => Icons.lock_open_outlined,
};

String _formatMinutes(Duration d) {
  final m = d.inMinutes;
  return m == 1 ? '1 minute' : '$m minutes';
}

/// MARKUP screen "lockAdvisory". `detectedMode` is what a real device
/// integration would report (see kiosk_channel.dart / KioskShell, which are
/// already wired elsewhere in this app for the child side) — this standalone
/// preview defaults to a selectable value so every platform's advisory copy
/// can actually be reviewed, and says so honestly rather than pretending to
/// read live hardware state.
class LockAdvisoryScreen extends StatefulWidget {
  const LockAdvisoryScreen({super.key, this.initialMode = lock.LockMode.pinned});
  final lock.LockMode initialMode;

  @override
  State<LockAdvisoryScreen> createState() => _LockAdvisoryScreenState();
}

class _LockAdvisoryScreenState extends State<LockAdvisoryScreen> {
  late lock.LockMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    final advisory = lock.lockAdvisory(_mode);
    final isEscapable = lock.escapable.contains(_mode);

    return Scaffold(
      appBar: AppBar(title: const Text('Before you hand this over')),
      // SingleChildScrollView over a plain Column, NOT ListView — a sliver
      // list only keeps items near the current scroll position built, and
      // scrolling down to the platform picker can un-mount the header
      // above. Every row here is real, permanent content, not a virtualized
      // feed.
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_platformIcon(_mode), size: 30,
              color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(_platformLabel(_mode),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 16),
          Card(
            color: isEscapable
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primaryContainer,
            child: Padding(padding: const EdgeInsets.all(16),
              child: Text(advisory, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35))),
          ),
          if (isEscapable) ...[
            const SizedBox(height: 16),
            const _InfoRow(icon: Icons.pin_outlined,
              text: 'If it happens, a shuffled PIN screen appears immediately — never '
                    'the app menu, never a settings screen.'),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.hourglass_bottom_outlined,
              text: 'After ${lock.maxPinAttempts} wrong PINs in a row, the device pauses for '
                    '${_formatMinutes(lock.cooldownDuration)} before trying again.'),
            const SizedBox(height: 12),
            const _InfoRow(icon: Icons.vpn_key_outlined,
              text: "If you're ever locked out yourself and it can't wait, a break-glass "
                    'path gets you back in — it is always recorded.'),
          ] else ...[
            const SizedBox(height: 16),
            const _InfoRow(icon: Icons.shield_outlined,
              text: 'No menu, home button, or app switch can get past this — only a '
                    'guardian unlocking it from here.'),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text('Preview — see another platform',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in lock.LockMode.values)
              ChoiceChip(label: Text(_platformLabel(m)), selected: _mode == m,
                onSelected: (_) => setState(() => _mode = m)),
          ]),
        ]),
      )),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
  ]);
}
