// OLIVE BRANCH — guardian shell, send-time guard. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). Renders MARKUP
// screen "sendguard". MASTERFILE §6.4, §8.2.3, §8.2.7.
//
// Two related but distinct guards, both ported from the reference
// implementation rather than re-derived:
//
//  1. The notification gate (packages/delivery-engine/src/gate.ts,
//     MASTERFILE §6.4) — blocks arrivals during asleep/school and tells the
//     SENDER, live, before he sends into the wrong hour. REAL as of this
//     pass when [dayPart]/[reachable] are supplied (guardian_home.dart's
//     own live path threads through what guardian_home_live.dart already
//     fetched from the real GET /now route — see that route's own header
//     for why this screen reads /now's plain fields rather than gate.ts's
//     richer, actor-timezone-aware `recipientContext()`, which /now has no
//     "actor" concept to carry). Falls back to the ORIGINAL demo behavior
//     (a manually-toggled fake hour) when either is null — every existing
//     demo/test call site keeps behaving exactly as before this pass.
//  2. The anchor distinction (MASTERFILE §6.4's own framing, restated in the
//     §03 MARKUP row): "next bedtime" and "the night of June 1st" are
//     different promises. Only a daypart-relative anchor may drift when her
//     schedule changes; a specific calendar date never does. STILL DEMO-
//     ONLY, disclosed rather than silently left looking real alongside
//     guard 1's new live path: no real per-child bedtime-schedule source
//     exists anywhere in this codebase yet for [_bedtimeLabel] to read from
//     — a real, separate, larger gap (a day-part *authoring* API,
//     MASTERFILE §7.2's undelivered `GET/PUT .../day-parts`), not something
//     this pass invents an answer for.
//
// §8.2.3 applies throughout: her time is dominant, his is never shown as
// arithmetic against it (no "+1", no raw offset, no UTC).
import 'package:flutter/material.dart';
import 'calendar_day_logic.dart' show dayPartLabel;

// ===================================== §6.4 the notification gate (ported) ==
class DayPart {
  const DayPart(this.name, this.startHour, this.endHour, this.reachable);
  final String name;
  final int startHour; // inclusive, her local hour, 0-23
  final int endHour; // exclusive; may wrap past midnight
  final bool reachable;

  bool contains(int hour) =>
    startHour <= endHour ? (hour >= startHour && hour < endHour)
                          : (hour >= startHour || hour < endHour);
}

/// A small, honest demo schedule — not a live custody/day-part backend
/// (none exists yet; see delivery-engine/src/gate.ts for the real thing).
const demoDayParts = [
  DayPart('asleep', 20, 7, false),
  DayPart('school', 8, 15, false),
  DayPart('free time', 15, 20, true),
];

DayPart currentDayPart(int hour) =>
  demoDayParts.firstWhere((p) => p.contains(hour), orElse: () => demoDayParts.last);

class GuardPrompt {
  const GuardPrompt({
    required this.localTimeLabel,
    required this.zoneAbbr,
    required this.reachable,
    required this.dayPartName,
    this.deferLabel,
  });
  final String localTimeLabel;
  final String zoneAbbr;
  final bool reachable;
  final String dayPartName;
  /// Her local time the message would land instead, if blocked. Never a raw
  /// offset from the actor's own clock.
  final String? deferLabel;
}

/// MASTERFILE §6.4, sender side — "called live as the parent composes."
GuardPrompt recipientContext(int localHour, String localTimeLabel, String zoneAbbr) {
  final part = currentDayPart(localHour);
  return GuardPrompt(
    localTimeLabel: localTimeLabel,
    zoneAbbr: zoneAbbr,
    reachable: part.reachable,
    dayPartName: part.name,
    deferLabel: part.reachable ? null : '7:00 AM her time',
  );
}

// ============================================ the anchor distinction ========
enum SendAnchor { nextBedtime, specificDate }

/// What the guardian is promising by picking an anchor. Only `nextBedtime`
/// may resolve differently after a schedule change — that asymmetry is the
/// entire point of offering both, so it is asserted, not just described.
class AnchorPreview {
  const AnchorPreview(this.label, this.movesWithSchedule);
  final String label;
  final bool movesWithSchedule;
}

AnchorPreview resolveAnchor(SendAnchor anchor, {
  required String currentBedtimeLabel,
  required String specificDateLabel,
}) => switch (anchor) {
  SendAnchor.nextBedtime => AnchorPreview(
      'Arrives at her next bedtime — right now that means $currentBedtimeLabel her time. '
      'If her evening shifts, this moves with it.',
      true),
  // Deliberately independent of currentBedtimeLabel: a calendar date is a
  // fixed promise regardless of what bedtime becomes between now and then.
  SendAnchor.specificDate => AnchorPreview(
      'Arrives the night of $specificDateLabel, whatever else changes between now and then.',
      false),
};

// ==================================================== the guardian-facing UI
/// MARKUP screen "sendguard". A message composer that demonstrates both
/// guards live rather than just describing them.
class SendTimeGuardScreen extends StatefulWidget {
  const SendTimeGuardScreen({super.key, this.childName = 'Ivy',
    this.childLocalTime, this.zoneAbbr, this.dayPart, this.reachable});

  final String childName;

  /// Real, already-fetched /now data — see this file's own header for why
  /// guardian_home.dart threads these through rather than this screen
  /// doing a second live fetch. All four null together in every existing
  /// demo/test call site (main.dart's static demo, guardian_home_test.dart)
  /// — that combination is what keeps the original manually-toggled demo
  /// behavior below active, not a broken/loading live state.
  final String? childLocalTime;
  final String? zoneAbbr;
  final String? dayPart;
  final bool? reachable;

  /// True only when guardian_home_live.dart's real /now fetch supplied
  /// BOTH a local-time string and a real (non-null) reachable verdict —
  /// [dayPart] alone is deliberately not part of this check, since gate()
  /// itself never sets a `reason`/dayPart when the child IS reachable (see
  /// gate.ts's own doc comment) — a real "she's in free time right now"
  /// result is [reachable] == true with [dayPart] == null, not an
  /// incomplete fetch.
  bool get _isLive => childLocalTime != null && reachable != null;

  @override
  State<SendTimeGuardScreen> createState() => _SendTimeGuardScreenState();
}

class _SendTimeGuardScreenState extends State<SendTimeGuardScreen> {
  final _controller = TextEditingController();
  int _localHour = 22; // 10:40 PM — the MASTERFILE §6.4 example, verbatim.
  String? _confirmation;

  SendAnchor _anchor = SendAnchor.nextBedtime;
  String _bedtimeLabel = '8:30 PM';
  bool _scheduleShifted = false;

  static const _demoHours = <int, String>{
    22: '10:40 PM',
    9: '9:15 AM',
    17: '5:30 PM',
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _shiftSchedule() => setState(() {
    _scheduleShifted = !_scheduleShifted;
    _bedtimeLabel = _scheduleShifted ? '8:00 PM' : '8:30 PM';
  });

  void _sendNow() => setState(() => _confirmation = 'Sent — landing with ${widget.childName} now.');

  void _deferSend(String label) =>
    setState(() => _confirmation = 'Set to deliver at $label.');

  @override
  Widget build(BuildContext context) {
    // Real /now data when guardian_home.dart's live path supplied it;
    // otherwise the original manually-toggled demo hour, unchanged — see
    // SendTimeGuardScreen._isLive's own doc comment. Live never offers a
    // specific "Deliver at X" time (deferLabel stays null): /now's own
    // documented MASTERFILE §7.2 contract is {localTime, zone, dayPart,
    // reachable} only — gate()'s richer deferTo needs the actor's own
    // timezone to render honestly (§8.2.3, never a raw offset), which /now
    // has no "actor" concept to supply. A real, disclosed scope trim, not
    // silently dropped.
    final prompt = widget._isLive
      ? GuardPrompt(
          localTimeLabel: widget.childLocalTime!,
          zoneAbbr: widget.zoneAbbr ?? 'her time',
          reachable: widget.reachable!,
          dayPartName: widget.dayPart != null ? dayPartLabel(widget.dayPart!) : 'now',
          deferLabel: null,
        )
      : recipientContext(_localHour, _demoHours[_localHour]!, 'her time');
    final anchorPreview = resolveAnchor(_anchor,
      currentBedtimeLabel: _bedtimeLabel, specificDateLabel: 'June 1st');

    return Scaffold(
      appBar: AppBar(title: Text('Message to ${widget.childName}')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _controller, maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder(),
              hintText: 'Type a message…')),
          const SizedBox(height: 16),

          // --- guard 1: the notification gate --------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: prompt.reachable
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // HER frame first, always — §8.2.3.
              Text("It's ${prompt.localTimeLabel} for ${widget.childName}"
                  '${prompt.reachable ? '' : ' — she is ${prompt.dayPartName}.'}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (prompt.reachable)
                SizedBox(width: double.infinity, height: 48,
                  child: FilledButton(onPressed: _sendNow, child: const Text('Send now')))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SizedBox(height: 48, child: OutlinedButton(
                    onPressed: _sendNow, child: const Text('Send now anyway'))),
                  // A specific deferred time is only ever offered in the
                  // demo path (recipientContext() above always sets one) —
                  // the live path's own prompt deliberately never does, see
                  // this screen's build() comment on why. No crash either
                  // way: this button simply doesn't render without one.
                  if (prompt.deferLabel != null)
                    SizedBox(height: 48, child: FilledButton(
                      onPressed: () => _deferSend(prompt.deferLabel!),
                      child: Text('Deliver at ${prompt.deferLabel}'))),
                ]),
              if (_confirmation != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(_confirmation!, style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
          // Hour-toggle chips only make sense against the demo path's own
          // fake, player-chosen hour — the live path shows the real "right
          // now," which isn't something a tap should be able to change.
          if (!widget._isLive) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, children: [
              for (final h in _demoHours.entries)
                ChoiceChip(label: Text(h.value), selected: _localHour == h.key,
                  onSelected: (_) => setState(() { _localHour = h.key; _confirmation = null; })),
            ])),
          ],

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text('When should this arrive?',
            style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('"Next bedtime" and "the night of June 1st" are different promises — '
              'only the first moves if her routine does.',
            style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SegmentedButton<SendAnchor>(
            segments: const [
              ButtonSegment(value: SendAnchor.nextBedtime, label: Text('Next bedtime')),
              ButtonSegment(value: SendAnchor.specificDate, label: Text('The night of June 1st')),
            ],
            selected: {_anchor},
            onSelectionChanged: (s) => setState(() => _anchor = s.first),
          ),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
            child: Text(anchorPreview.label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: 12),
          TextButton.icon(onPressed: _shiftSchedule,
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: Text(_scheduleShifted
              ? 'Undo: put her bedtime back to 8:30 PM'
              : 'Preview: her bedtime moves 30 minutes earlier this week')),
        ]),
      )),
    );
  }
}
