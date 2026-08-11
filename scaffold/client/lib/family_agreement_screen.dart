// OLIVE BRANCH — guardian shell, family agreement (read-only custody order).
// UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated pipeline —
// manually built and run via `flutter analyze` / `flutter test` this
// session). MASTERFILE §5.4, §9.4, §4.1.
//
// No TS package in this codebase names a bespoke "family agreement" data
// model — grepped, there is none. Same posture deletion_screen.dart's own
// header takes for "deletion": the closest real, already-built,
// already-tested thing is the custody order/schedule engine
// (db/migrations/0007_custody_order.sql, table custody_order;
// packages/custody/src/schedule.ts's Order/HolidayRule types and
// patternSideOn/holidayOn/sideOn; packages/db/src/pool.ts's
// activeCustodyOrderFor()). server/routes.mjs's GET
// /v1/children/:childId/custody-order returns that row, verbatim, as JSON.
// This screen is a READ-ONLY view of it — no editing UI exists here,
// deliberately. An "agreement" is a legal document; rendering the real one
// honestly is this screen's whole job, not letting anyone quietly change it
// from a phone.
//
// Real loading/error/empty states, no faked success: a child can be real and
// still have no custody_order row at all (never entered, or mid-transition)
// — that shows a plain "no agreement on file" state, not a crash and not a
// guessed schedule.
import 'dart:async';
import 'package:flutter/material.dart';

// ============================================================ the model ===
/// Mirrors packages/custody/src/schedule.ts's `Order`, field for field, as
/// returned by GET /v1/children/:childId/custody-order's `order` key.
class CustodyOrderView {
  const CustodyOrderView({
    required this.pattern,
    required this.orderTz,
    required this.anchorLocalDate,
    required this.exchangeTime,
    required this.holidays,
    required this.effectiveFrom,
    required this.effectiveTo,
  });

  /// One of schedule.ts's Pattern union — '2-2-3' | '2-2-5-5' |
  /// 'alternating_weeks' | 'week_on_week_off'. See [patternInPlainWords].
  final String pattern;
  final String orderTz;
  final String anchorLocalDate; // 'YYYY-MM-DD'
  final String exchangeTime; // 'HH:mm', order-time wall clock
  final List<HolidayRuleView> holidays;
  final String effectiveFrom; // 'YYYY-MM-DD'
  final String? effectiveTo; // null = open-ended

  factory CustodyOrderView.fromJson(Map<String, dynamic> j) => CustodyOrderView(
        pattern: j['pattern'] as String,
        orderTz: j['orderTz'] as String,
        anchorLocalDate: j['anchorLocalDate'] as String,
        exchangeTime: j['exchangeTime'] as String,
        holidays: ((j['holidays'] as List<dynamic>?) ?? const <dynamic>[])
            .map((h) => HolidayRuleView.fromJson(h as Map<String, dynamic>))
            .toList(),
        effectiveFrom: j['effectiveFrom'] as String,
        effectiveTo: j['effectiveTo'] as String?,
      );
}

/// Mirrors schedule.ts's `HolidayRule`.
class HolidayRuleView {
  const HolidayRuleView({
    required this.name,
    required this.startMonthDay,
    required this.endMonthDay,
    required this.evenYearSide,
    required this.priority,
  });

  final String name;
  final String startMonthDay; // 'MM-DD'
  final String endMonthDay; // 'MM-DD'
  final String evenYearSide; // 'A' | 'B' — schedule.ts's Side
  final int priority;

  factory HolidayRuleView.fromJson(Map<String, dynamic> j) => HolidayRuleView(
        name: j['name'] as String,
        startMonthDay: j['startMonthDay'] as String,
        endMonthDay: j['endMonthDay'] as String,
        evenYearSide: j['evenYearSide'] as String,
        priority: (j['priority'] as num).toInt(),
      );

  String get oddYearSide => evenYearSide == 'A' ? 'B' : 'A';
}

// ======================================================= plain language ===
/// Spells out schedule.ts's CYCLES rotation for a pattern code in words a
/// parent reading this on a phone can actually use — the raw code is never
/// shown alone. An unrecognized code is shown verbatim rather than guessed
/// at, matching this screen's own honest-absence posture elsewhere.
String patternInPlainWords(String pattern) {
  switch (pattern) {
    case '2-2-3':
      return '2 nights, then 2 nights, then 3 nights with each side in turn '
          '— the long weekend alternates. Repeats every 2 weeks.';
    case '2-2-5-5':
      return '2 nights, then 2 nights, then 5 nights with each side — '
          'repeats every 2 weeks.';
    case 'alternating_weeks':
      return 'A full week with each side, alternating.';
    case 'week_on_week_off':
      // schedule.ts's own CYCLES table gives this the exact same 7-and-7
      // rotation as 'alternating_weeks' today — said plainly here rather
      // than inventing a difference the engine doesn't actually have.
      return 'A full week with each side, alternating — the same rotation '
          "this build's schedule engine uses for \"alternating weeks.\"";
    default:
      return pattern;
  }
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'MM-DD' -> 'Mon D', e.g. '12-20' -> 'Dec 20'. Falls back to the raw code
/// if it isn't the expected shape — a real screen showing something honest
/// and odd beats one that throws.
String monthDayLabel(String md) {
  final parts = md.split('-');
  if (parts.length != 2) return md;
  final m = int.tryParse(parts[0]);
  final d = int.tryParse(parts[1]);
  if (m == null || d == null || m < 1 || m > 12) return md;
  return '${_months[m - 1]} $d';
}

/// 'YYYY-MM-DD' -> 'Mon D, YYYY'. Same honest-fallback posture as above.
String dateLabel(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;
  final label = monthDayLabel('${parts[1]}-${parts[2]}');
  return '$label, ${parts[0]}';
}

/// 'HH:mm' (24h, order-time) -> '6:00 PM'. Falls back to the raw string.
String timeLabel(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return hhmm;
  final period = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $period';
}

// ============================================================== screen ===
enum _LoadState { loading, error, empty, ready }

class FamilyAgreementScreen extends StatefulWidget {
  const FamilyAgreementScreen({
    super.key,
    required this.childId,
    required this.fetchOrder,
    this.childName = 'your child',
  });

  final String childId;
  final String childName;

  /// The entire integration point for real data — same DI pattern
  /// guardian_setup.dart's own [registerPasskey] uses. Real implementation:
  /// `(id) => OliveApi(baseUrl, token).getCustodyOrder(id)`. This screen has
  /// no opinion on how the network call is made, only on what it honestly
  /// does with a real result or a real failure.
  final Future<Map<String, dynamic>> Function(String childId) fetchOrder;

  @override
  State<FamilyAgreementScreen> createState() => _FamilyAgreementScreenState();
}

class _FamilyAgreementScreenState extends State<FamilyAgreementScreen> {
  _LoadState _state = _LoadState.loading;
  CustodyOrderView? _order;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final body = await widget.fetchOrder(widget.childId);
      final Object? raw = body['order'];
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _order = null;
          _state = _LoadState.empty;
        });
        return;
      }
      setState(() {
        _order = CustodyOrderView.fromJson(raw as Map<String, dynamic>);
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _state = _LoadState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Family agreement')),
        body: SafeArea(child: _body(context)),
      );

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text("Couldn't load the agreement",
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => unawaited(_load()), child: const Text('Try again')),
            ]),
          ),
        );
      case _LoadState.empty:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.description_outlined, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No agreement on file',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  '${widget.childName} has no custody order entered yet. Once one is '
                  'added, its real schedule will show here.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
        );
      case _LoadState.ready:
        return _ReadyView(order: _order!, childName: widget.childName);
    }
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.order, required this.childName});
  final CustodyOrderView order;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // SingleChildScrollView + Column, NOT ListView: same fix guardian_home.dart's
    // own comment documents — a sliver-backed list drops children scrolled
    // below the fold from the element tree, which this screen's own widget
    // tests (holiday rules, the trailing "does not itself record" notice)
    // caught directly.
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.visibility_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Read-only. This is the real custody order on file for $childName — '
                'nothing here can be changed from this screen.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Text('The pattern', style: textTheme.titleMedium),
      const SizedBox(height: 4),
      Card(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(patternInPlainWords(order.pattern), style: textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('Code: ${order.pattern}',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      )),
      const SizedBox(height: 16),
      Text('Schedule details', style: textTheme.titleMedium),
      const SizedBox(height: 4),
      Card(
          child: Column(children: [
        _DetailRow(icon: Icons.public, label: 'Order timezone', value: order.orderTz),
        _DetailRow(
            icon: Icons.swap_horiz,
            label: 'Exchange time',
            value: '${timeLabel(order.exchangeTime)} (${order.orderTz})'),
        _DetailRow(
            icon: Icons.flag_outlined, label: 'Anchor date', value: dateLabel(order.anchorLocalDate)),
        _DetailRow(
            icon: Icons.event_available_outlined,
            label: 'In effect from',
            value: dateLabel(order.effectiveFrom)),
        _DetailRow(
            icon: Icons.event_busy_outlined,
            label: 'In effect until',
            value: order.effectiveTo == null ? 'Open-ended' : dateLabel(order.effectiveTo!),
            isLast: true),
      ])),
      const SizedBox(height: 16),
      Text('Holidays', style: textTheme.titleMedium),
      const SizedBox(height: 4),
      if (order.holidays.isEmpty)
        Card(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              'No holiday rules on this order — the base pattern above applies '
              'year-round.',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ))
      else
        for (final HolidayRuleView h in order.holidays)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${monthDayLabel(h.startMonthDay)} – ${monthDayLabel(h.endMonthDay)}',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('Side ${h.evenYearSide} in even years · Side ${h.oddYearSide} in odd years',
                    style: textTheme.bodySmall),
              ]),
            ),
          ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'The order tracks two sides, A and B, but does not itself record '
                'which guardian is which — that mapping is not part of this build '
                'yet, so it is shown honestly as "Side A" / "Side B" rather than '
                'guessed.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
      ),
    ]));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.isLast = false});
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label),
          const SizedBox(width: 12),
          // The VALUE is the variable-length side of this row (e.g. "6:00 PM
          // (America/New_York)") -- it, not the short fixed label, is what
          // needs to be allowed to wrap/shrink on a narrow screen (Fold5
          // cover width caught this as a real RenderFlex overflow).
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      if (!isLast) const Divider(height: 1),
    ]);
  }
}
