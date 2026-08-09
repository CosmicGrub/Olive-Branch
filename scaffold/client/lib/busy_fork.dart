// OLIVE BRANCH — guardian shell, busy fork. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). Renders MARKUP screen
// "busyFork". MASTERFILE §9.13.4.
//
// A 1:1 semantic port of packages/live/src/around.ts's busy-fork slice
// (busyFork/BUSY_BANNED/auditBusyFork/attemptVisibleToChild).
//
// He rings during school. The ribbon warned him, but the call attempt itself
// had nowhere to go — and a failed call is the worst possible output: it
// reads to him as rejection, and to her, later, as a missed call she caused.
// So an attempt at a blocked time is never a failure. It is a fork, and both
// branches are good: state the fact plainly, offer banking, name the next
// real window.
import 'package:flutter/material.dart';
import 'emergency_card.dart';
import 'message_banking.dart';

// ======================================== §9.13.4 she is busy, so bank it ===
enum Unavailable { school, asleep, windDown, withOtherParent, quietHours }

String _label(Unavailable u) => switch (u) {
  Unavailable.school => 'At school',
  Unavailable.asleep => 'Asleep',
  Unavailable.windDown => 'Winding down',
  Unavailable.withOtherParent => 'At her other house',
  Unavailable.quietHours => 'Quiet hours',
};

class BusyFork {
  const BusyFork({
    required this.reason,
    required this.line,
    required this.nextWindow,
    this.urgentPath,
  });

  final Unavailable reason;
  /// Plain, and it never suggests she chose it.
  final String line;
  /// Always true in this build — reuses §9.5 message banking unchanged.
  bool get offerBanking => true;
  /// The next window the schedule actually knows about.
  final String? nextWindow;
  /// Present only where the situation genuinely warrants it.
  final String? urgentPath;
}

BusyFork busyFork(Unavailable reason, String? nextWindow, {bool emergency = false}) {
  const lines = {
    Unavailable.school: 'She is at school.',
    Unavailable.asleep: 'She is asleep.',
    Unavailable.windDown: 'She is winding down for bed.',
    Unavailable.withOtherParent: 'She is in the middle of something at her other house.',
    Unavailable.quietHours: 'It is quiet hours there.',
  };
  return BusyFork(
    reason: reason,
    line: lines[reason]!,
    nextWindow: nextWindow,
    urgentPath: emergency ? 'If this cannot wait, the emergency card has the numbers.' : null,
  );
}

/// Nothing in this fork may imply refusal, rejection, or a decision by her.
const busyBanned = [
  'declined', 'rejected', 'refused', 'unavailable to you', 'she did not answer',
  'missed call', 'no answer', 'blocked', 'not allowed', 'denied',
];

/// Runtime self-check, not just a test assertion — runs on the exact text
/// this widget is about to render.
bool auditBusyFork(BusyFork f) {
  final text = '${f.line} ${f.urgentPath ?? ''}'.toLowerCase();
  return !busyBanned.any(text.contains);
}

/// And the other half, which matters just as much: she is never shown a
/// missed call. A five-year-old who sees "Dad tried to call you at 10:40"
/// has been handed a small guilt she did nothing to earn.
bool attemptVisibleToChild() => false;

// ==================================================== the guardian-facing UI
/// MARKUP screen "busyFork". This is what a guardian sees the instant a call
/// attempt lands on a blocked window — never a failure screen, never a
/// "she didn't answer".
class BusyForkScreen extends StatefulWidget {
  const BusyForkScreen({
    super.key,
    this.childName = 'Ivy',
    this.initialReason = Unavailable.school,
    this.emergencyPathOffered = true,
  });

  final String childName;
  final Unavailable initialReason;
  final bool emergencyPathOffered;

  @override
  State<BusyForkScreen> createState() => _BusyForkScreenState();
}

class _BusyForkScreenState extends State<BusyForkScreen> {
  late Unavailable _reason;
  bool _banked = false;

  static const _nextWindows = {
    Unavailable.school: 'after school, 4:00 PM her time',
    Unavailable.asleep: 'breakfast, 7:00 AM her time',
    Unavailable.windDown: 'tomorrow morning her time',
    Unavailable.withOtherParent: 'her next free window her time',
    Unavailable.quietHours: 'the next open hour her time',
  };

  @override
  void initState() {
    super.initState();
    _reason = widget.initialReason;
  }

  void _bankInstead(BuildContext context) {
    setState(() => _banked = true);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const MessageBankingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final fork = busyFork(_reason, _nextWindows[_reason],
      emergency: widget.emergencyPathOffered);
    assert(auditBusyFork(fork), 'a busy-fork line must never read as refusal');

    return Scaffold(
      appBar: AppBar(title: Text('Calling ${widget.childName}')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(child: Text(fork.line,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                ]),
                if (fork.nextWindow != null) ...[
                  const SizedBox(height: 12),
                  Text('Next window: ${fork.nextWindow}', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ])),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton.icon(
              onPressed: _banked ? null : () => _bankInstead(context),
              icon: const Icon(Icons.schedule_send),
              label: Text(_banked ? 'Sent to message banking' : 'Bank a message instead'))),
          const SizedBox(height: 12),
          Text(
            "She'll see it whenever she next looks — never that you tried and it didn't go through.",
            style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (fork.urgentPath != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 48,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const EmergencyCardScreen())),
                icon: const Icon(Icons.medical_information_outlined),
                label: const Text('Open the emergency card'))),
            const SizedBox(height: 8),
            Text(fork.urgentPath!, style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),
          Text('Preview — try another reason', style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in Unavailable.values)
              ChoiceChip(label: Text(_label(u)), selected: _reason == u,
                onSelected: (_) => setState(() { _reason = u; _banked = false; })),
          ]),
        ]),
      )),
    );
  }
}
