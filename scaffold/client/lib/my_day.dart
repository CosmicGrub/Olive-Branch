// OLIVE BRANCH — child shell, my day. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §8.2, §8.2.2, §8.4.
// Renders MARKUP screen 'myday'.
//
// The Day Ribbon, in HER frame — the child-facing sibling of the ribbon
// guardian_home.dart renders for the guardian. Two invariants:
//   - Every part of the day is named and shown, not just "now" — §8.4's
//     visual-schedule-tool framing: ordered day-parts with "what happens
//     next" marked is close to what an occupational therapist builds by
//     hand for an autistic child, so it is built once, for everyone.
//   - No settings affordance exists at any depth (matches child_home.dart).
//
// This screen and its ribbon are a fresh implementation, not an import of
// guardian_home.dart's `RibbonBand`/`_Ribbon` — kept fully self-contained so
// this file has zero risk of colliding with any other in-flight change to
// that screen. The underlying technique is deliberately the same one,
// though: explicit-width `Positioned` segments inside a `LayoutBuilder`, NOT
// `Row` + `Expanded`/flex. See guardian_home.dart's `_Ribbon` for why —
// Expanded children inside a Row silently paint nothing on this engine build
// (Flutter 3.44.8 stable, Impeller/Vulkan), confirmed there by bisection.
import 'package:flutter/material.dart';
import 'calendar_day_logic.dart';

const Map<String, Color> _dayPartColor = <String, Color>{
  'wake': Color(0xFFFFB74D),
  'before_school': Color(0xFFFFD54F),
  'school': Color(0xFF64B5F6),
  'after_school': Color(0xFF81C784),
  'activity': Color(0xFFFF8A65),
  'dinner': Color(0xFFE57373),
  'wind_down': Color(0xFF9575CD),
  'bedtime': Color(0xFF7986CB),
  'asleep': Color(0xFF3949AB),
  'free': Color(0xFF4DD0E1),
};

const Color _fallbackColor = Color(0xFFBDBDBD);

Color _colorFor(String kind) => _dayPartColor[kind] ?? _fallbackColor;

// One friendly, concrete line per day-part — shown only when she taps a card
// open. Kept short on purpose: this is a glance tool, not a reading test.
const Map<String, String> _dayPartBlurb = <String, String>{
  'wake': 'Stretch, say good morning, let the day start.',
  'before_school': 'Breakfast, teeth, backpack — almost go time.',
  'school': 'Reading, math, and lunch with friends.',
  'after_school': 'Home base — a snack and a breather.',
  'activity': 'Off to your activity or practice.',
  'dinner': 'Food, family, a little chat about the day.',
  'wind_down': 'Slow it down — pajamas and a book.',
  'bedtime': 'Lights low, all tucked in.',
  'asleep': 'Sweet dreams — the whole house is quiet.',
  'free': 'Nothing scheduled — pick your own fun.',
};

class MyDayScreen extends StatelessWidget {
  const MyDayScreen({
    super.key,
    required this.childName,
    required this.parts,
    required this.nowLocal,
  });

  final String childName;
  final List<DayPartLite> parts;
  /// "HH:mm", 24h, her own local clock. See calendar_day_logic.dart's
  /// `hhmmNow()` for the honest-stub source a wiring pass can hand in.
  final String nowLocal;

  @override
  Widget build(BuildContext context) {
    final List<StripSegment> segments = scheduleStrip(parts, nowLocal);
    final StripSegment current = segments.firstWhere(
      (StripSegment s) => s.current,
      orElse: () => segments.first,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('My day')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text("$childName's day", style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Row(children: <Widget>[
            Text(current.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Expanded(child: Text('Right now: ${current.label}',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 14),
          _DayRibbon(parts: parts, nowLocal: nowLocal),
          const SizedBox(height: 22),
          for (final StripSegment s in segments) _DayPartCard(segment: s),
        ],
      )),
    );
  }
}

class _BandRect {
  const _BandRect(this.kind, this.startFrac, this.widthFrac);
  final String kind;
  final double startFrac;
  final double widthFrac;
}

const int _minutesPerDay = 24 * 60;

/// Lays each part on a 0..1 fraction of a single day. A part whose end is
/// *before* its start wraps past midnight (e.g. asleep 20:00→06:30) and is
/// split into two contiguous rectangles so the ribbon still reads as one
/// unbroken 24-hour strip starting at local midnight.
List<_BandRect> _bandRects(List<DayPartLite> parts) {
  final List<_BandRect> rects = <_BandRect>[];
  for (final DayPartLite p in parts) {
    final int s = minutesSinceMidnight(p.startsLocal);
    final int e = minutesSinceMidnight(p.endsLocal);
    if (e > s) {
      rects.add(_BandRect(p.kind, s / _minutesPerDay, (e - s) / _minutesPerDay));
    } else {
      rects
        ..add(_BandRect(p.kind, s / _minutesPerDay, (_minutesPerDay - s) / _minutesPerDay))
        ..add(_BandRect(p.kind, 0, e / _minutesPerDay));
    }
  }
  return rects;
}

class _DayRibbon extends StatelessWidget {
  const _DayRibbon({required this.parts, required this.nowLocal});
  final List<DayPartLite> parts;
  final String nowLocal;

  @override
  Widget build(BuildContext context) {
    final List<_BandRect> rects = _bandRects(parts);
    final double nowFrac = minutesSinceMidnight(nowLocal) / _minutesPerDay;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(height: 40, width: double.infinity,
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          return Stack(children: <Widget>[
            for (final _BandRect r in rects)
              Positioned(
                left: w * r.startFrac,
                width: w * r.widthFrac,
                top: 0,
                bottom: 0,
                child: Tooltip(
                  message: dayPartLabel(r.kind),
                  child: ColoredBox(color: _colorFor(r.kind)),
                ),
              ),
            Positioned(
              left: (w * nowFrac - 2).clamp(0.0, w > 4 ? w - 4 : 0.0),
              top: 0,
              bottom: 0,
              width: 4,
              child: DecoratedBox(decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
                boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black38, blurRadius: 2)],
              )),
            ),
          ]);
        })),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
  );
}

class _DayPartCard extends StatefulWidget {
  const _DayPartCard({required this.segment});
  final StripSegment segment;
  @override
  State<_DayPartCard> createState() => _DayPartCardState();
}

class _DayPartCardState extends State<_DayPartCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final StripSegment s = widget.segment;
    final Color bandColor = _colorFor(s.kind);
    final Color background = s.current
        ? Color.lerp(bandColor, Colors.white, 0.78)!
        : Theme.of(context).colorScheme.primaryContainer.withAlpha(80);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: background,
            border: s.current ? Border.all(color: bandColor, width: 2) : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Text(s.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(child: Text(s.label,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              if (s.current) _Pill('right now', color: bandColor)
              else if (s.next) _Pill('up next', color: bandColor.withAlpha(200)),
            ]),
            const SizedBox(height: 4),
            Text('${formatTimeOfDay(s.startsLocal)} – ${formatTimeOfDay(s.endsLocal)}',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _expanded
                ? Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text(_dayPartBlurb[s.kind] ?? '', style: const TextStyle(fontSize: 13.5)))
                : const SizedBox(width: double.infinity, height: 0),
            ),
          ]),
        ),
      ),
    );
  }
}
