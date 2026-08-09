// OLIVE BRANCH — child shell, weeks. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §8.2, §8.2.5, P3.
// Renders MARKUP screen 'weeks': "Custody rhythm as she experiences it;
// countdowns in sleeps."
//
// Two invariants this widget tree enforces:
//   - Every date this screen touches (`CustodyNight.dateIso`, the ISO strings
//     `sleepsBetween` is computed from) is used ONLY as arithmetic input. Not
//     one of them is ever formatted to text and put in front of her — the
//     rhythm renders as sleeps and relative words ("Tonight", "in 3 sleeps"),
//     never as a calendar date. §8.2.5.
//   - This is a rhythm, not a place: it names who each night is with, never
//     where. No address, no city, no coordinates appears anywhere near a
//     night — that would smuggle location back in through a side door P3
//     was written to close.
import 'package:flutter/material.dart';
import 'calendar_day_logic.dart';

class CustodyNight {
  const CustodyNight({required this.dateIso, required this.withWhom});
  /// yyyy-MM-dd. Internal arithmetic input ONLY — see file header.
  final String dateIso;
  final String withWhom;
}

/// A simple, warm two-guardian palette. Any name present in a `CustodyNight`
/// but missing here falls back to `_fallbackBeadColor` rather than throwing —
/// a third or renamed guardian must never crash this screen.
const Map<String, Color> demoGuardianColors = <String, Color>{
  'Mom': Color(0xFFAD1457),
  'Dad': Color(0xFF00838F),
};

const Color _fallbackBeadColor = Color(0xFF6D4C41);

/// Demo-only custody rhythm: a 4-nights/3-nights repeating pattern, 14 nights
/// (two full cycles) starting tonight. No live scheduling backend exists yet
/// (see api_client.dart) — this stands in for it, honestly, in one place.
List<CustodyNight> demoCustodyNights({DateTime? today}) {
  final DateTime now = today ?? DateTime.now();
  final DateTime startUtc = DateTime.utc(now.year, now.month, now.day);
  const List<String> pattern = <String>['Mom', 'Mom', 'Mom', 'Mom', 'Dad', 'Dad', 'Dad'];
  return <CustodyNight>[
    for (int i = 0; i < 14; i++)
      CustodyNight(
        dateIso: isoDateOnly(startUtc.add(Duration(days: i))),
        withWhom: pattern[i % pattern.length],
      ),
  ];
}

String _relativeNightLabel(int sleepsFromToday) {
  if (sleepsFromToday <= 0) return 'Tonight';
  if (sleepsFromToday == 1) return 'Tomorrow night';
  return 'In $sleepsFromToday sleeps';
}

class WeeksScreen extends StatelessWidget {
  const WeeksScreen({
    super.key,
    required this.childName,
    required this.nights,
    required this.guardianColors,
  });

  final String childName;
  /// Chronological, starting with tonight. `nights.first` is treated as
  /// "who she's with right now" — see the class-level note on §8.2.5.
  final List<CustodyNight> nights;
  final Map<String, Color> guardianColors;

  Color _colorFor(String name) => guardianColors[name] ?? _fallbackBeadColor;

  @override
  Widget build(BuildContext context) {
    if (nights.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('My weeks')),
        body: SafeArea(child: Center(
          child: Padding(padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.nights_stay_outlined, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Nothing to show yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ])))),
      );
    }
    final String currentWith = nights.first.withWhom;
    final int changeIdx = nights.indexWhere((CustodyNight n) => n.withWhom != currentWith);
    final int? sleepsUntilChange = changeIdx == -1
        ? null
        : sleepsBetween(nights.first.dateIso, nights[changeIdx].dateIso);

    return Scaffold(
      appBar: AppBar(title: const Text('My weeks')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text("$childName's weeks", style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _RhythmHeader(
            currentWith: currentWith,
            currentColor: _colorFor(currentWith),
            nextWith: changeIdx == -1 ? null : nights[changeIdx].withWhom,
            nextColor: changeIdx == -1 ? null : _colorFor(nights[changeIdx].withWhom),
            sleeps: sleepsUntilChange,
          ),
          const SizedBox(height: 24),
          Text('Every circle is one sleep. Today is the bright one.',
            style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 14, children: <Widget>[
            for (int i = 0; i < nights.length; i++)
              _NightBead(
                night: nights[i],
                color: _colorFor(nights[i].withWhom),
                isToday: i == 0,
                relativeLabel: _relativeNightLabel(
                  sleepsBetween(nights.first.dateIso, nights[i].dateIso)),
              ),
          ]),
          const SizedBox(height: 24),
          Wrap(spacing: 16, runSpacing: 8, children: <Widget>[
            for (final MapEntry<String, Color> e in guardianColors.entries)
              _LegendChip(name: e.key, color: e.value),
          ]),
        ],
      )),
    );
  }
}

class _RhythmHeader extends StatelessWidget {
  const _RhythmHeader({
    required this.currentWith,
    required this.currentColor,
    required this.nextWith,
    required this.nextColor,
    required this.sleeps,
  });
  final String currentWith;
  final Color currentColor;
  final String? nextWith;
  final Color? nextColor;
  final int? sleeps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.lerp(currentColor, Colors.white, 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: currentColor, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          CircleAvatar(radius: 8, backgroundColor: currentColor),
          const SizedBox(width: 8),
          Expanded(child: Text("You're with $currentWith right now",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        if (sleeps != null && nextWith != null) ...<Widget>[
          const SizedBox(height: 12),
          // The sleeps numeral is a documented hero-number exception (§8.2.5)
          // — hand-set large/bold, not a themed text role. See child_home.dart's
          // _Sleeps for the same discipline applied to the same kind of number.
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
            Text('$sleeps', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: nextColor)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              sleeps == 1
                ? 'sleep until you\'re with $nextWith'
                : 'sleeps until you\'re with $nextWith',
              style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ] else
          Padding(padding: const EdgeInsets.only(top: 12),
            child: Text('No change coming up in the nights shown here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
      ]),
    );
  }
}

class _NightBead extends StatelessWidget {
  const _NightBead({
    required this.night,
    required this.color,
    required this.isToday,
    required this.relativeLabel,
  });
  final CustodyNight night;
  final Color color;
  final bool isToday;
  final String relativeLabel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$relativeLabel · with ${night.withWhom}',
    triggerMode: TooltipTriggerMode.tap,
    child: Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: isToday ? Border.all(color: Colors.white, width: 3) : null,
        // Soft, tinted toward the bead's own guardian colour rather than a
        // flat black shadow — the highlight should read as a glow, not a drop
        // shadow. See journal etc.'s Finding #5 sibling fix in my_day.dart.
        boxShadow: isToday
          ? <BoxShadow>[BoxShadow(color: color.withAlpha(90), blurRadius: 8, spreadRadius: 1)]
          : null,
      ),
      child: const Text('🌙', style: TextStyle(fontSize: 18)),
    ),
  );
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.name, required this.color});
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
    CircleAvatar(radius: 6, backgroundColor: color),
    const SizedBox(width: 8),
    // Flexible, not a bare Text: `guardianColors` is caller-supplied (see
    // WeeksScreen's constructor) and a real family's guardian label ("Step-mum
    // Jennifer", say) is not bounded the way the demo's "Mom"/"Dad" are. On
    // the Fold5 cover width (344px) an unprotected Text here overflows this
    // Row — found by actually rendering at that width, not by inspection.
    Flexible(child: Text(name, overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall)),
  ]);
}
