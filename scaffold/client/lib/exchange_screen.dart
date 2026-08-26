// OLIVE BRANCH — guardian shell, the exchange. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §4, §9.7,
// prohibition P3. Renders MARKUP screen 'exchange'.
//
// Ported from packages/custody/src/schedule.ts (pattern rotation, holiday
// override, "sleeps until" — §4.1/§8.2.5) and packages/care/src/care.ts
// (bag manifest §9.7.1, arrival event §9.7.2, running-late log §9.7.3). Only
// the pure, zone-agnostic parts of schedule.ts are ported: `dayIndex` /
// `patternSideOn` / `holidayOn` operate on plain child-local calendar dates,
// exactly as the TypeScript does (it anchors those computations at
// `{zone: 'utc'}` too — that is calendar-date math, not real timezone
// conversion). The one piece of schedule.ts that DOES need a live IANA
// timezone resolver (`exchanges()`'s cross-zone instant math) is not ported:
// this preview build has no backend and no timezone package dependency to
// do that honestly, so the "zone flips here" fact and the order-time label
// below arrive as pre-rendered fields on the demo data, the same posture
// guardian_home.dart already takes for its dual clock ("All times arrive
// pre-rendered from /now and /ribbon so the client does no zone maths").
//
// P3, enforced structurally, not just by convention: `ArrivalEvent` below has
// no latitude/longitude/address field anywhere in its shape, and
// `auditArrivalPayload` — a straight port of care.ts's `auditArrival` — is
// run against every event this screen ever constructs, so a future edit that
// tries to smuggle a coordinate back in fails loudly instead of silently.
//
// LIVE WIRING (baseUrl/guardianId/childId/httpClient, all optional and
// additive — same convention expenses_screen.dart/meds_care.dart already
// establish for a guardian_more.dart screen): when supplied, this screen
// fetches the real bag manifest + running-late log + arrival status via
// OliveApi.fetchExchangeBagItems()/fetchExchangeRunningLate()/
// fetchExchangeArrival() on init, and writes via setExchangeBagItemStatus()/
// logExchangeRunningLate()/recordExchangeArrival(), minting a fresh
// devLoginFor() session per call — same reasoning those files' own headers
// give. Scope, disclosed (matching server/routes.mjs's own registration
// comment): ONLY the bag manifest/running-late/arrival sections go live —
// the Handoff/Coming-up sections below stay on `_demoOrder`'s demo data even
// when this screen IS live-wired, since making those live would mean
// porting schedule.ts's full timezone-aware `exchanges()`, a separate task.
// `scheduledAt`/`delayMinutes` on a live arrival are computed server-side
// from the child's real active custody order, never from this client — a
// 409 `no_active_custody_order` response (honest absence, no order on file)
// is shown as a real message, never silently swallowed or guessed around.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'form_factors.dart' as ff;

// ============================================================ schedule.ts ===
// §4, §9.4 — the custody rotation. A faithful port of the pure calendar-date
// arithmetic only (see file header for what is deliberately NOT ported).

enum Side { a, b }

class HolidayRule {
  const HolidayRule({required this.name, required this.startMonthDay,
    required this.endMonthDay, required this.evenYearSide, required this.priority});
  final String name;
  final String startMonthDay; // 'MM-DD'
  final String endMonthDay;   // 'MM-DD'
  final Side evenYearSide;
  final int priority;
}

class Order {
  const Order({required this.pattern, required this.anchorLocalDate,
    required this.holidays, required this.orderTimeLabel});
  /// '2-2-3' is the only pattern this demo ports; the TS module also defines
  /// '2-2-5-5', 'alternating_weeks' and 'week_on_week_off' over the same
  /// 14-day cycle shape — omitted here because this screen's demo family
  /// uses one pattern, not because the port is partial by accident.
  final List<Side> pattern;
  final DateTime anchorLocalDate;
  final List<HolidayRule> holidays;
  /// Pre-rendered, verbatim, in the decree's own zone — see file header.
  final String orderTimeLabel;
}

class Block {
  Block({required this.side, required this.startLocalDate, required this.endLocalDate,
    required this.source, this.holidayName});
  final Side side;
  final DateTime startLocalDate;
  DateTime endLocalDate;
  final String source; // 'pattern' | 'holiday'
  final String? holidayName;
}

// A A B B A A A | B B A A B B B — index 0 is the anchor date.
const List<Side> cycle223 = <Side>[
  Side.a, Side.a, Side.b, Side.b, Side.a, Side.a, Side.a,
  Side.b, Side.b, Side.a, Side.a, Side.b, Side.b, Side.b,
];

int _dayIndex(DateTime anchor, DateTime local) {
  final int diff = local.difference(anchor).inDays;
  return ((diff % 14) + 14) % 14;
}

Side patternSideOn(Order order, DateTime localDate) =>
  order.pattern[_dayIndex(order.anchorLocalDate, localDate)];

String _monthDay(DateTime d) =>
  '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

({HolidayRule rule, Side side})? holidayOn(Order order, DateTime localDate) {
  final String md = _monthDay(localDate);
  final int year = localDate.year;
  final List<HolidayRule> matches = order.holidays.where((HolidayRule h) =>
    h.startMonthDay.compareTo(h.endMonthDay) <= 0
      ? md.compareTo(h.startMonthDay) >= 0 && md.compareTo(h.endMonthDay) <= 0
      : md.compareTo(h.startMonthDay) >= 0 || md.compareTo(h.endMonthDay) <= 0
  ).toList();
  if (matches.isEmpty) return null;
  matches.sort((HolidayRule x, HolidayRule y) => y.priority != x.priority
    ? y.priority - x.priority
    : y.startMonthDay.compareTo(x.startMonthDay));
  final HolidayRule rule = matches.first;
  final Side side = year.isEven
    ? rule.evenYearSide
    : (rule.evenYearSide == Side.a ? Side.b : Side.a);
  return (rule: rule, side: side);
}

({Side side, String source, String? holidayName}) sideOn(Order order, DateTime localDate) {
  final ({HolidayRule rule, Side side})? h = holidayOn(order, localDate);
  if (h != null) return (side: h.side, source: 'holiday', holidayName: h.rule.name);
  return (side: patternSideOn(order, localDate), source: 'pattern', holidayName: null);
}

/// Contiguous blocks across a child-local date range, inclusive.
List<Block> blocks(Order order, DateTime fromLocal, DateTime toLocal) {
  final List<Block> out = <Block>[];
  Block? cur;
  DateTime d = fromLocal;
  while (!d.isAfter(toLocal)) {
    final ({Side side, String source, String? holidayName}) s = sideOn(order, d);
    if (cur != null && cur.side == s.side && cur.source == s.source &&
        cur.holidayName == s.holidayName) {
      cur.endLocalDate = d;
    } else {
      if (cur != null) out.add(cur);
      cur = Block(side: s.side, startLocalDate: d, endLocalDate: d,
        source: s.source, holidayName: s.holidayName);
    }
    d = d.add(const Duration(days: 1));
  }
  if (cur != null) out.add(cur);
  return out;
}

/// §8.2.5 — "N sleeps until Dad's week." Counts child-local day boundaries.
({int sleeps, Side nextSide, DateTime onLocalDate})? sleepsUntilSideChange(
  Order order, DateTime nowLocalDate, {int maxLookahead = 60}) {
  final Side today = sideOn(order, nowLocalDate).side;
  DateTime d = nowLocalDate;
  for (int i = 1; i <= maxLookahead; i++) {
    d = d.add(const Duration(days: 1));
    final Side s = sideOn(order, d).side;
    if (s != today) return (sleeps: i, nextSide: s, onLocalDate: d);
  }
  return null;
}

/// §9.4 — friendly language only, never legal terms, for what the child sees
/// of her own calendar. This guardian screen never speaks in her voice
/// directly, but re-uses the exact same label so the two shells never
/// describe the same day differently.
String childCalendarLabel(Block block, Map<Side, String> sideNames) =>
  block.source == 'holiday'
    ? '${block.holidayName} with ${sideNames[block.side]}'
    : "${sideNames[block.side]}'s time";

// ================================================================ care.ts ===
// §9.7.1 the bag manifest, §9.7.2 arrival (P3), §9.7.3 running late.

class BagItem {
  BagItem({required this.id, required this.label, required this.essential,
    this.sent = false, this.returned = false});
  final String id;
  final String label;
  final bool essential;
  bool sent;
  bool returned;
}

/// Essential items first — the reader may only scan the top.
List<BagItem> manifestOrder(List<BagItem> items) {
  final List<BagItem> out = List<BagItem>.of(items);
  out.sort((BagItem a, BagItem b) => (b.essential ? 1 : 0) - (a.essential ? 1 : 0) != 0
    ? (b.essential ? 1 : 0) - (a.essential ? 1 : 0)
    : a.label.compareTo(b.label));
  return out;
}

class RunningLateEntry {
  const RunningLateEntry({required this.loggedAt, required this.etaMinutes});
  final DateTime loggedAt;
  final int etaMinutes;
}

class ArrivalEvent {
  const ArrivalEvent({required this.exchangeId, required this.arrivedAt,
    required this.delayMinutes});
  final String exchangeId;
  final DateTime arrivedAt;
  final int delayMinutes;
}

/// §9.7.2, P3 — accepts no location parameter. Nothing to smuggle a
/// coordinate through even if a future edit wanted to.
ArrivalEvent recordArrival(String exchangeId, DateTime scheduledAt, DateTime arrivedAt) {
  final int delay = arrivedAt.difference(scheduledAt).inMinutes;
  return ArrivalEvent(exchangeId: exchangeId, arrivedAt: arrivedAt,
    delayMinutes: delay < 0 ? 0 : delay);
}

const List<String> locationKeys = <String>['lat', 'latitude', 'lng', 'lon',
  'longitude', 'coords', 'geohash', 'accuracy', 'altitude', 'address'];

/// A straight port of care.ts's `auditArrival`, run defensively against a
/// plain map view of the event so a leak is structural, not just visual.
({bool ok, List<String> leaks}) auditArrivalPayload(Map<String, Object?> e) {
  final List<String> leaks = e.keys
    .where((String k) => locationKeys.contains(k.toLowerCase())).toList();
  return (ok: leaks.isEmpty, leaks: leaks);
}

// =================================================================== demo ===
final Order _demoOrder = Order(
  pattern: cycle223,
  anchorLocalDate: DateTime.utc(2026, 7, 27), // a Monday, Side A's day 0
  holidays: <HolidayRule>[
    const HolidayRule(name: 'Thanksgiving', startMonthDay: '11-22',
      endMonthDay: '11-29', evenYearSide: Side.b, priority: 10),
  ],
  orderTimeLabel: '6:00 PM Central, per the decree',
);

const Map<Side, String> _sideNames = <Side, String>{Side.a: 'Mom', Side.b: 'Dad'};

enum _LoadState { ready, loading, error }

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
  });
  final String childName;
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && guardianId != null && childId != null;

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  final DateTime _today = DateTime.utc(2026, 8, 4);

  List<BagItem> _manifest = manifestOrder(<BagItem>[
    BagItem(id: 'retainer', label: 'Retainer', essential: true),
    BagItem(id: 'inhaler', label: 'Inhaler', essential: true),
    BagItem(id: 'glasses', label: 'Glasses', essential: true),
    BagItem(id: 'homework', label: 'Homework folder', essential: true, sent: true),
    BagItem(id: 'bear', label: 'Mr. Bramble (stuffed bear)', essential: false, sent: true),
    BagItem(id: 'charger', label: 'Tablet charger', essential: false),
  ]);

  final List<RunningLateEntry> _lateLog = <RunningLateEntry>[];
  ArrivalEvent? _arrival;
  _LoadState _loadState = _LoadState.ready;
  // Per-item spinner state while a real live toggle is in flight — mirrors
  // expenses_screen.dart's own `_resolving` Set, same reasoning: disables
  // that one row's checkboxes so a slow connection can't be double-tapped
  // into two competing requests. Always empty on the demo path.
  final Set<String> _togglingItemIds = <String>{};
  bool _loggingLate = false;
  bool _loggingArrival = false;

  @override
  void initState() {
    super.initState();
    if (widget._isLive) _load();
  }

  /// The ONLY place this screen calls the network to READ — mirrors
  /// expenses_screen.dart/meds_care.dart's own self-fetching pattern: a
  /// fresh devLoginFor() per load, `api.close()` only on the success path.
  /// A failure here is a real, honest error state with a retry affordance,
  /// never a silent fall-back to the demo fixtures.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final results = await Future.wait([
        api.fetchExchangeBagItems(widget.childId!),
        api.fetchExchangeRunningLate(widget.childId!),
        api.fetchExchangeArrival(widget.childId!),
      ]);
      if (widget.httpClient == null) api.close();
      final List<dynamic> rawItems = results[0]['items'] as List<dynamic>? ?? <dynamic>[];
      final List<BagItem> items = manifestOrder(rawItems.map((dynamic i) {
        final Map<String, dynamic> row = i as Map<String, dynamic>;
        return BagItem(id: row['id'] as String, label: row['label'] as String,
          essential: row['essential'] as bool? ?? false, sent: row['sent'] as bool? ?? false,
          returned: row['returned'] as bool? ?? false);
      }).toList());
      // Server returns newest-first (running-late log's own GET); this
      // screen's `_lateLog` is oldest-first internally, same as the demo
      // path's own append order — build() reverses it for display either way.
      final List<dynamic> rawLate =
          (results[1]['entries'] as List<dynamic>? ?? <dynamic>[]).reversed.toList();
      final List<RunningLateEntry> lateLog = rawLate.map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        return RunningLateEntry(
          loggedAt: DateTime.tryParse(row['loggedAt'] as String? ?? '') ?? DateTime.now(),
          etaMinutes: row['etaMinutes'] as int? ?? 0);
      }).toList();
      final Map<String, dynamic>? rawArrival =
          results[2]['event'] as Map<String, dynamic>?;
      final ArrivalEvent? arrival = rawArrival == null ? null : ArrivalEvent(
        exchangeId: rawArrival['id'] as String,
        arrivedAt: DateTime.tryParse(rawArrival['arrivedAt'] as String? ?? '') ?? DateTime.now(),
        delayMinutes: rawArrival['delayMinutes'] as int? ?? 0);
      if (!mounted) return;
      setState(() {
        _manifest = items;
        _lateLog..clear()..addAll(lateLog);
        _arrival = arrival;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  void _toggleSent(BagItem item) {
    if (!widget._isLive) { setState(() => item.sent = !item.sent); return; }
    _toggleLive(item, sent: !item.sent);
  }

  void _toggleReturned(BagItem item) {
    if (!widget._isLive) { setState(() => item.returned = !item.returned); return; }
    _toggleLive(item, returned: !item.returned);
  }

  /// Live path for both toggles above — POSTs exactly the one field that
  /// changed (setExchangeBagItemStatus()'s own doc comment: omitting a field
  /// leaves it unchanged server-side), then updates local state from the
  /// real response rather than assuming the optimistic flip landed.
  Future<void> _toggleLive(BagItem item, {bool? sent, bool? returned}) async {
    setState(() => _togglingItemIds.add(item.id));
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row = await api.setExchangeBagItemStatus(
        widget.childId!, item.id, sent: sent, returned: returned);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        item.sent = row['sent'] as bool? ?? item.sent;
        item.returned = row['returned'] as bool? ?? item.returned;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't update that item — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _togglingItemIds.remove(item.id));
    }
  }

  // §9.7.3 — one tap, an ETA, immutably logged. Appended only: there is no
  // _editLateEntry and no _deleteLateEntry anywhere in this file.
  void _logRunningLate(int minutes) {
    if (!widget._isLive) {
      setState(() => _lateLog.add(RunningLateEntry(loggedAt: DateTime.now(), etaMinutes: minutes)));
      return;
    }
    _logRunningLateLive(minutes);
  }

  Future<void> _logRunningLateLive(int minutes) async {
    setState(() => _loggingLate = true);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row = await api.logExchangeRunningLate(widget.childId!, minutes);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() => _lateLog.add(RunningLateEntry(
        loggedAt: DateTime.tryParse(row['loggedAt'] as String? ?? '') ?? DateTime.now(),
        etaMinutes: row['etaMinutes'] as int? ?? minutes)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't log that — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _loggingLate = false);
    }
  }

  void _logArrival() {
    if (!widget._isLive) {
      final DateTime scheduled = DateTime.utc(_today.year, _today.month, _today.day, 18, 0);
      final ArrivalEvent event = recordArrival('exchange-demo-1', scheduled, DateTime.now());
      // Defense in depth (see file header): audit the event before it is
      // ever allowed to reach setState / the widget tree.
      final ({bool ok, List<String> leaks}) audit = auditArrivalPayload(<String, Object?>{
        'exchangeId': event.exchangeId, 'arrivedAt': event.arrivedAt.toIso8601String(),
        'delayMinutes': event.delayMinutes,
      });
      assert(audit.ok, 'P3 violation: arrival payload carries ${audit.leaks}');
      setState(() => _arrival = event);
      return;
    }
    _logArrivalLive();
  }

  /// Live path — `scheduledAt`/`delayMinutes` are computed server-side from
  /// the child's real active custody order, never from this client (see
  /// file header). A 409 `no_active_custody_order` response is a normal,
  /// honest outcome (no order on file to time the arrival against) — shown
  /// as a real message, never silently swallowed.
  Future<void> _logArrivalLive() async {
    setState(() => _loggingArrival = true);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row = await api.recordExchangeArrival(widget.childId!);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      if (row['error'] == 'no_active_custody_order') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No custody schedule is on file to time this arrival against.')));
        return;
      }
      setState(() => _arrival = ArrivalEvent(
        exchangeId: row['id'] as String,
        arrivedAt: DateTime.tryParse(row['arrivedAt'] as String? ?? '') ?? DateTime.now(),
        delayMinutes: row['delayMinutes'] as int? ?? 0));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't log the arrival — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _loggingArrival = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading/error UI mirrors expenses_screen.dart/meds_care.dart's own
    // established shape — only ever reachable when this screen is
    // live-wired; the pure demo path never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exchange')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )),
      );
    }
    final ({int sleeps, Side nextSide, DateTime onLocalDate})? next =
      sleepsUntilSideChange(_demoOrder, _today);
    final List<Block> upcoming = blocks(_demoOrder, _today,
      _today.add(const Duration(days: 21)));

    return Scaffold(
      appBar: AppBar(title: const Text('Exchange')),
      // Guardian-side, five stacked sections in a fixed order (see file
      // header). On a wide tablet/desktop viewport the single column is
      // only ever capped to a comfortable reading width and centered, never
      // split — section order and the manifest rows' fixed-width checkbox
      // columns are completely untouched. Same real columnsAt() gate every
      // other width decision in the app uses.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = ListView(padding: const EdgeInsets.all(16), children: [
          if (next != null) _HandoffCard(childName: widget.childName, sleeps: next.sleeps,
            nextSideName: _sideNames[next.nextSide]!, orderTimeLabel: _demoOrder.orderTimeLabel),
          const SizedBox(height: 20),
          const _SectionHeader('Bag manifest'),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final BagItem item in _manifest)
                _BagRow(item: item, onSent: () => _toggleSent(item),
                  onReturned: () => _toggleReturned(item),
                  busy: _togglingItemIds.contains(item.id)),
            ]))),
          const SizedBox(height: 20),
          const _SectionHeader('Running late'),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('One tap logs it — the log cannot be edited afterward.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final int m in <int>[10, 20, 30])
                  SizedBox(height: 48, child: OutlinedButton(
                    onPressed: _loggingLate ? null : () => _logRunningLate(m),
                    child: Text('Running $m min late'))),
              ]),
              if (_lateLog.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final RunningLateEntry e in _lateLog.reversed)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Logged ${_clock(e.loggedAt)} · ETA +${e.etaMinutes} min',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ],
            ]))),
          const SizedBox(height: 20),
          const _SectionHeader('Arrival'),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('An event, never a place. No location is ever recorded — P3.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (_arrival == null)
                SizedBox(height: 48, child: FilledButton(
                  onPressed: _loggingArrival ? null : _logArrival,
                  child: const Text('Log arrival')))
              else
                Text(_arrival!.delayMinutes == 0
                  ? '${widget.childName} arrived — right on time.'
                  : '${widget.childName} arrived — ${_arrival!.delayMinutes} min after '
                    'the scheduled time.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]))),
          const SizedBox(height: 20),
          const _SectionHeader('Coming up'),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final Block b in upcoming.take(4))
                ListTile(dense: true,
                  title: Text(childCalendarLabel(b, _sideNames)),
                  subtitle: Text('${_date(b.startLocalDate)} – ${_date(b.endLocalDate)}')),
            ]))),
          const SizedBox(height: 12),
        ]);
        return capWidth
            ? Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                    child: content))
            : content;
      })),
    );
  }
}

String _date(DateTime d) => '${d.month}/${d.day}';
String _clock(DateTime d) {
  final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final String min = d.minute.toString().padLeft(2, '0');
  return '$h12:$min ${d.hour >= 12 ? 'PM' : 'AM'}';
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({required this.childName, required this.sleeps,
    required this.nextSideName, required this.orderTimeLabel});
  final String childName;
  final int sleeps;
  final String nextSideName;
  final String orderTimeLabel;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // HER frame is dominant — a sentence about her day, not a clock diff.
        Text('$childName goes to $nextSideName in',
          style: Theme.of(context).textTheme.bodyMedium),
        // §8.2.5 documented exception: the sleeps-countdown numeral is a
        // bespoke hero number, not a themed role — see the file's own
        // "HER frame is dominant" comment above.
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
            Text('$sleeps', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Text(sleeps == 1 ? 'sleep' : 'sleeps',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        const SizedBox(height: 8),
        // Subordinate aside: verbatim, never a computed offset.
        Text('The decree says $orderTimeLabel.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7))),
      ])));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700,
      letterSpacing: 0.5, color: Theme.of(context).colorScheme.primary));
}

class _BagRow extends StatelessWidget {
  const _BagRow({required this.item, required this.onSent, required this.onReturned,
    this.busy = false});
  final BagItem item;
  final VoidCallback onSent;
  final VoidCallback onReturned;
  /// True while a real live toggle for THIS item is in flight — disables
  /// both checkboxes so a slow connection can't be double-tapped into two
  /// competing requests. Always false on the demo path.
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(children: [
      if (item.essential)
        Padding(padding: const EdgeInsets.only(right: 4),
          child: Icon(Icons.priority_high, size: 16,
            color: Theme.of(context).colorScheme.tertiary)),
      Expanded(child: Text(item.label)),
      SizedBox(width: 96, child: CheckboxListTile(dense: true,
        contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
        title: Text('sent', style: Theme.of(context).textTheme.labelSmall),
        value: item.sent, onChanged: busy ? null : (_) => onSent())),
      SizedBox(width: 110, child: CheckboxListTile(dense: true,
        contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
        title: Text('returned', style: Theme.of(context).textTheme.labelSmall),
        value: item.returned, onChanged: busy ? null : (_) => onReturned())),
    ]));
}
