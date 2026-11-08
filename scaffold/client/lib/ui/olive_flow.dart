// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — progress, time and sequence.
//
//   OliveStepper / OliveSteps / OliveProgress <- kit `K.stepper(total, active)`, `K.steps(labels, active)`,
//                                                `K.progress(p, tone)`
//   Timeline          <- kit `K.timeline(items)`: done / now / next states, shape + icon + words
//   ScheduleGrid + ScheduleBlock <- kit `K.schedule(blocks, o)` / `K.scheduleBlock(o)` (a day grid)
//   MonthCalendar + DayCell <- kit `K.calMonth(o)` / `K.dayCell(n, o)`: house A is a rounded square,
//                              house B a circle, a handover day a split cell; shape differs as well
//                              as tint, so the schedule never depends on colour alone
//
// Replaces (adoption wave): the hand-built calendar grids in calendar_day_logic / care screens' day
// rows, the dots rows in first_run_flow, LinearProgressIndicator usages.
import 'package:flutter/material.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';

/// Kit `K.stepper`: pills for "step 3 of 5". The current step is a long pill, finished steps a
/// mid-tone dot. [active] is 1-based.
class OliveStepper extends StatelessWidget {
  const OliveStepper({super.key, required this.total, required this.active});

  final int total;
  final int active;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Semantics(
      label: 'Step $active of $total',
      value: '$active of $total',
      container: true,
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= total; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 1 ? 0 : 6),
              child: AnimatedContainer(
                duration: OliveTiming.base(context),
                curve: OliveTiming.spring,
                width: i == active ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == active ? p.pri : (i < active ? Color.lerp(p.surface3, p.pri, 0.55) : p.surface3),
                  borderRadius: BorderRadius.circular(8),
                  border: i > active ? Border.all(color: p.line) : null,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Kit `K.steps`: a labelled stepper (numbers, a check for finished steps). [active] is 0-based.
class OliveSteps extends StatelessWidget {
  const OliveSteps({super.key, required this.labels, required this.active});

  final List<String> labels;
  final int active;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    Widget half(bool on, bool show) => Expanded(child: Container(height: 2, color: show ? (on ? p.pri : p.line) : Colors.transparent));
    return Semantics(
      container: true,
      label: 'Step ${active + 1} of ${labels.length}: ${labels[active.clamp(0, labels.length - 1)]}',
      child: ExcludeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Column(children: [
                Row(children: [
                  half(i <= active, i > 0),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < active ? p.pri : p.surface,
                      border: Border.all(color: i <= active ? p.pri : p.edge, width: 2),
                      boxShadow: i == active ? [BoxShadow(color: p.pri.withValues(alpha: 0.22), spreadRadius: 4)] : null,
                    ),
                    child: Center(
                      child: i < active
                          ? OliveIcon(OliveIcons.check, size: 14, strokeWidth: 3, color: p.onPri)
                          : Text('${i + 1}', style: OliveText.strong(context, color: i == active ? p.pri : p.ink2, size: 12)),
                    ),
                  ),
                  half(i + 1 <= active, i < labels.length - 1),
                ]),
                const SizedBox(height: 6),
                Text(labels[i], textAlign: TextAlign.center,
                    style: OliveText.strong(context, color: i == active ? p.ink : p.ink3, size: 11.5)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Kit `K.progress`: an 8dp bar. [value] is 0..1.
class OliveProgress extends StatelessWidget {
  const OliveProgress({super.key, required this.value, this.tone = OliveTone.pri, this.semanticLabel});

  final double value;
  final OliveTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()} percent',
      child: ExcludeSemantics(
        child: Container(
          height: 8,
          decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.line)),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: OliveTiming.base(context),
            curve: OliveTiming.easeOut,
            widthFactor: v,
            child: Container(color: tone == OliveTone.ok ? p.ok : p.pri),
          ),
        ),
      ),
    );
  }
}

/// State of a [TimelineItem].
enum TimelineState { done, now, next }

/// One entry of a [Timeline].
class TimelineItem {
  const TimelineItem({required this.title, this.sub, this.time, this.icon, this.tone, this.state = TimelineState.done});
  final String title;
  final String? sub;
  final String? time;
  final String? icon;
  /// ok, warn or bad colour the node (kit `li.ok.done`, `li.warn`, `li.bad`).
  final OliveTone? tone;
  final TimelineState state;
}

/// Kit `K.timeline`: a vertical rail of events. The three states differ in SHAPE: done is a filled
/// node with a check, now is a ringed node with a halo, next is a hollow node.
class Timeline extends StatelessWidget {
  const Timeline(this.items, {super.key});

  final List<TimelineItem> items;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < items.length; i++)
        _TimelineRow(item: items[i], last: i == items.length - 1, p: p),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.last, required this.p});
  final TimelineItem item;
  final bool last;
  final OlivePalette p;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final toned = it.tone != null && it.tone != OliveTone.pri;
    final strong = toned ? p.toneEdge(it.tone!) : p.pri;
    final onStrong = toned ? p.surface : p.onPri;
    final done = it.state == TimelineState.done;
    final now = it.state == TimelineState.now;
    final node = Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? strong : p.surface,
        border: Border.all(color: (now || (toned && !done)) ? strong : (done ? strong : p.edge), width: 2),
        boxShadow: now ? [BoxShadow(color: strong.withValues(alpha: 0.22), spreadRadius: 4)] : null,
      ),
      child: Center(
        child: it.icon != null
            ? OliveIcon(it.icon!, size: 15, strokeWidth: 2, color: done ? onStrong : (now ? strong : p.ink2))
            : (done ? OliveIcon(OliveIcons.check, size: 14, strokeWidth: 3, color: onStrong) : null),
      ),
    );
    final word = switch (it.state) { TimelineState.done => '', TimelineState.now => 'Now, ', TimelineState.next => 'Next, ' };
    return Semantics(
      container: true,
      label: '$word${it.title}${it.sub != null ? ', ${it.sub}' : ''}${it.time != null ? ', ${it.time}' : ''}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 28,
              child: Column(children: [
                node,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: done ? Color.lerp(p.edge, p.pri, 0.45)!.withValues(alpha: 0.7) : p.line,
                        borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 3, bottom: last ? 0 : 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(it.title, style: OliveText.strong(context, color: it.state == TimelineState.next ? p.ink2 : p.ink)),
                  if (it.sub != null) Text(it.sub!, style: OliveText.cap(context)),
                ]),
              ),
            ),
            if (it.time != null) ...[
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(it.time!, style: OliveText.mono(context, color: p.ink3, size: 12))),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A calendar block of the day grid. Times are hours as doubles (8.5 is 8:30).
class ScheduleBlockSpec {
  const ScheduleBlockSpec({required this.start, required this.end, required this.title, this.sub, this.tone = OliveTone.pri, this.col = 0, this.cols = 1});
  final double start, end;
  final String title;
  final String? sub;
  final OliveTone tone;
  /// Column index and column count for blocks that overlap in time.
  final int col, cols;
}

String _hh(double x) {
  final h = x.floor();
  final m = ((x - h) * 60).round();
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${m != 0 ? ':${m < 10 ? '0' : ''}$m' : ''}${h >= 12 ? 'p' : 'a'}';
}

/// Kit `K.scheduleBlock`: one event with a coloured left edge. Fills the height it is given; text
/// that does not fit is clipped (the semantic label always carries all of it).
class ScheduleBlock extends StatelessWidget {
  const ScheduleBlock(this.spec, {super.key});

  final ScheduleBlockSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final (Color bg, Color fg, Color edge) = switch (spec.tone) {
      OliveTone.pri => (p.priC, p.onPriC, p.pri),
      OliveTone.accent => (p.accentC, p.ink, p.accent),
      _ => (p.toneBg(spec.tone), p.toneFg(spec.tone), p.toneFg(spec.tone)),
    };
    return Semantics(
      container: true,
      label: '${spec.title}${spec.sub != null ? ', ${spec.sub}' : ''}, ${_hh(spec.start)} to ${_hh(spec.end)}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: edge, width: 4)),
          ),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(spec.title, style: OliveText.head(context, color: fg).copyWith(fontSize: 13, height: 1.2)),
                if (spec.sub != null) Text(spec.sub!, style: OliveText.cap(context, color: fg).copyWith(height: 1.25)),
                Text('${_hh(spec.start)} to ${_hh(spec.end)}', style: OliveText.mono(context, color: fg, size: 10.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kit `K.schedule`: a day grid with hour rules, absolutely placed [ScheduleBlock]s and an optional
/// "now" line. [hourHeight] is in dp (the kit uses 40).
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({super.key, required this.blocks, this.from = 7, this.to = 20, this.hourHeight = 40, this.now});

  final List<ScheduleBlockSpec> blocks;
  final int from, to;
  final double hourHeight;
  final double? now;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final hh = hourHeight;
    return SizedBox(
      height: (to - from) * hh + 14,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
        final gridW = (w - 46).clamp(0.0, double.infinity);
        return Stack(clipBehavior: Clip.none, children: [
          for (var h = from; h <= to; h++)
            Positioned(
              top: (h - from) * hh, left: 0, right: 0,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 36,
                  child: Transform.translate(
                    offset: const Offset(0, -6),
                    child: Text(_hh(h.toDouble()), textAlign: TextAlign.right, maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
                        style: OliveText.mono(context, color: p.ink3, size: 10.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: p.line)),
              ]),
            ),
          for (final b in blocks)
            Positioned(
              top: (b.start - from) * hh + 1,
              height: ((b.end - b.start) * hh - 3).clamp(8.0, double.infinity),
              left: 46 + b.col * gridW / b.cols,
              width: (gridW / b.cols - 4).clamp(8.0, double.infinity),
              child: ScheduleBlock(b),
            ),
          if (now != null)
            Positioned(
              top: (now! - from) * hh, left: 38, right: 0,
              child: ExcludeSemantics(
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle)),
                  Expanded(child: Container(height: 2, color: p.ink)),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Which house (or event) marks a calendar day.
enum DayMark { none, houseA, houseB, handover, event }

/// Kit `K.dayCell`: one day. House A is a tinted rounded square, house B a circle, a handover a split
/// cell, an event a dot; today has an inset outline; the selected day is filled. 48dp tall, a seventh
/// of the width wide.
class DayCell extends StatelessWidget {
  const DayCell(this.day, {
    super.key,
    this.mark = DayMark.none,
    this.today = false,
    this.selected = false,
    this.dim = false,
    this.onTap,
    this.semanticLabel,
    this.houseAName = 'house A',
    this.houseBName = 'house B',
  });

  final int day;
  final DayMark mark;
  final bool today, selected, dim;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String houseAName, houseBName;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final tintA = Color.lerp(p.surface, p.pri, 0.24)!;
    final label = semanticLabel ??
        '$day${today ? ', today' : ''}${switch (mark) { DayMark.houseA => ', $houseAName', DayMark.houseB => ', $houseBName', DayMark.handover => ', handover day', DayMark.event => ', has an event', DayMark.none => '' }}';
    final fg = selected ? p.onPri : (dim ? p.ink3 : p.ink);
    final cell = CustomPaint(
      painter: _DayPainter(
        mark: selected ? DayMark.none : mark,
        tintA: tintA, tintB: p.accentC, fill: selected ? p.pri : null, today: today, todayColor: p.ink,
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        // The cell cannot grow with the text (seven to a row), so the number shrinks to fit instead.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$day', style: OliveText.tnum(OliveText.strong(context, color: fg, size: 14).copyWith(height: 1, fontWeight: dim ? FontWeight.w400 : FontWeight.w700))),
            if (mark == DayMark.event) ...[
              const SizedBox(height: 3),
              Container(width: 5, height: 5, decoration: BoxDecoration(color: selected ? p.onPri : p.ink2, shape: BoxShape.circle)),
            ],
          ]),
        ),
      ),
    );
    return OlivePressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      borderRadius: 14,
      minWidth: 0,
      child: SizedBox(height: 48, child: cell),
    );
  }
}

class _DayPainter extends CustomPainter {
  _DayPainter({required this.mark, required this.tintA, required this.tintB, required this.fill, required this.today, required this.todayColor});
  final DayMark mark;
  final Color tintA, tintB, todayColor;
  final Color? fill;
  final bool today;

  @override
  void paint(Canvas canvas, Size size) {
    final r = const Offset(2, 2) & Size(size.width - 4, size.height - 4);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    if (fill != null) {
      canvas.drawRRect(rr, Paint()..color = fill!);
    } else if (mark == DayMark.houseA) {
      canvas.drawRRect(rr, Paint()..color = tintA);
    } else if (mark == DayMark.houseB) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)), Paint()..color = tintB);
    } else if (mark == DayMark.handover) {
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawPath((Path()..moveTo(r.left, r.top)..lineTo(r.right, r.top)..lineTo(r.left, r.bottom)..close()), Paint()..color = tintA);
      canvas.drawPath((Path()..moveTo(r.right, r.top)..lineTo(r.right, r.bottom)..lineTo(r.left, r.bottom)..close()), Paint()..color = tintB);
      canvas.restore();
    }
    if (today) {
      canvas.drawRRect(
          mark == DayMark.houseB && fill == null ? RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)) : rr,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = todayColor);
    }
  }

  @override
  bool shouldRepaint(_DayPainter o) =>
      o.mark != mark || o.tintA != tintA || o.tintB != tintB || o.fill != fill || o.today != today || o.todayColor != todayColor;
}

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _dowNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// Kit `K.calMonth`: a month grid with previous / next buttons and a legend. [marks] maps day of month
/// to a [DayMark]. [weekStartsOn] is 0 for Sunday, 1 for Monday.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.year,
    required this.month,
    this.today,
    this.selected,
    this.marks = const {},
    this.weekStartsOn = 0,
    this.houseAName = 'Mom’s house',
    this.houseBName = 'Dad’s house',
    this.showLegend = true,
    this.onSelect,
    this.onPrevious,
    this.onNext,
  });

  final int year;
  /// 1..12.
  final int month;
  final int? today, selected;
  final Map<int, DayMark> marks;
  final int weekStartsOn;
  final String houseAName, houseBName;
  final bool showLegend;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final first = DateTime(year, month, 1).weekday % 7; // Sunday = 0
    final dim = DateUtils.getDaysInMonth(year, month);
    final prevDim = DateUtils.getDaysInMonth(month == 1 ? year - 1 : year, month == 1 ? 12 : month - 1);
    final pad = (first - weekStartsOn + 7) % 7;
    final tail = (7 - (pad + dim) % 7) % 7;
    final cells = <Widget>[
      for (var i = 0; i < pad; i++) DayCell(prevDim - pad + i + 1, dim: true),
      for (var d = 1; d <= dim; d++)
        DayCell(d,
            mark: marks[d] ?? DayMark.none,
            today: today == d,
            selected: selected == d,
            houseAName: houseAName,
            houseBName: houseBName,
            onTap: onSelect == null ? null : () => onSelect!(d)),
      for (var i = 1; i <= tail; i++) DayCell(i, dim: true),
    ];
    final title = '${_monthNames[month - 1]} $year';
    Widget legendItem(Widget swatch, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          swatch,
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: OliveText.cap(context, color: p.ink2).copyWith(fontSize: 11.5))),
        ]);
    Widget swatch(DayMark m) => SizedBox(
          width: 14, height: 14,
          child: CustomPaint(painter: _DayPainter(mark: m, tintA: Color.lerp(p.surface, p.pri, 0.24)!, tintB: p.accentC, fill: null, today: false, todayColor: p.ink)),
        );
    return Semantics(
      container: true,
      label: title,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          OliveIconButton(OliveIcons.chevL, label: 'Previous month', small: true, onPressed: onPrevious, iconSize: 16),
          Expanded(child: Center(child: Text(title, style: OliveText.head(context)))),
          OliveIconButton(OliveIcons.chevR, label: 'Next month', small: true, onPressed: onNext, iconSize: 16),
        ]),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: Center(child: Text(_dowNames[(i + weekStartsOn) % 7][0], style: OliveText.label(context).copyWith(letterSpacing: 0.6)))),
          ]),
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < cells.length / 7; r++)
          Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cells[r * 7 + c])]),
        if (showLegend) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            legendItem(swatch(DayMark.houseA), houseAName),
            legendItem(swatch(DayMark.houseB), houseBName),
            legendItem(swatch(DayMark.handover), 'Handover'),
          ]),
        ],
      ]),
    );
  }
}
