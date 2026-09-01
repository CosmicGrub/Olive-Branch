// OLIVE BRANCH — live-backed guardian home. UNVERIFIED at the live-device/
// live-server level (this screen has never been run against a real deployed
// backend). tools/verify.sh's own automated pipeline still has no Flutter
// toolchain, so this marker stays present. MASTERFILE §7, §8.2, §20.2b.
//
// Closes MASTERFILE §20.2b's own longest-standing tracked gap: "GuardianHome
// has no live-data screen" — first confirmed v0.49.15, still true at every
// re-check through v0.49.57 (24+ patch versions). main_live_guardian.dart's
// own header used to explain, in detail, exactly why: GuardianHome needs
// dual-clock/ribbon data from a `/ribbon` endpoint that api_client.dart only
// ever declared a dead path constant for (`OliveApi.childRibbon`), with no
// server route and no client fetch method behind it — "a guardian_home_live
// .dart honestly can't be written yet without inventing fake ribbon data."
// server/routes.mjs's real GET .../ribbon route (this same pass) closes
// that gap; this file is what it unblocks.
//
// Reuses GuardianHome unmodified — this widget's only job is fetching real
// data and mapping it onto GuardianHome's existing constructor, mirroring
// child_home_live.dart's own precedent for the identical reason: every
// invariant GuardianHome's own test suite already asserts (the CHILD's
// time dominant, never shown arithmetic, her state as a sentence, the
// 4-width no-overflow breakpoint) still holds for the live path with zero
// duplicated widget logic.
//
// Real divergences from child_home_live.dart's own shape, each disclosed
// rather than silently copied:
//   - No `wearSync`/`pushChannel`/`navigatorKey` params. GuardianHome has no
//     paired-watch touchpoint and no incoming-push affordance at all — its
//     "Call $childName" button is a plain, hardcoded FilledButton. Adding
//     those seams here would be speculative surface area with nothing to
//     wire them to.
//   - No secondary/non-fatal fetch split. child_home_live.dart's own house
//     rule keeps a supplementary fetch (presence) from trapping the primary
//     screen behind an error state. GuardianHome has no such supplementary
//     field: every value this wrapper fetches maps onto a REQUIRED,
//     non-nullable GuardianHome constructor field (unlike ChildHome, which
//     has real honest-absence fields for exactly this class of gap) — so
//     both fetches below are necessarily fatal-on-failure. This is a direct
//     consequence of GuardianHome's own current shape, not an oversight.
//   - No `sessionToken` threading. GuardianHome has no such field at all
//     (confirmed by direct read, not assumed) — `baseUrl`/`guardianId`/
//     `childId` are passed through unmodified, the same convention
//     main_live_guardian.dart already used for GuardianMoreScreen before
//     this pass; whether downstream guardian screens should eventually
//     adopt ChildHome-style token reuse is a separate, undecided question.
//   - `childStateSentence` is always passed `null`. No real data source for
//     a one-sentence guardian-facing status exists anywhere in this
//     codebase yet (confirmed by a dedicated research pass before writing
//     this file, not assumed) — GuardianHome's own field was loosened to
//     nullable for exactly this (see guardian_home.dart's own field doc
//     comment), rendering nothing rather than a fabricated sentence, the
//     same honest-absence posture ChildHome's own `sleepsUntilHandover`/
//     `presence` already established.
//   - `overlapLabel` is always passed `null` too. server/routes.mjs's own
//     GET .../ribbon route deliberately omits it from the wire — see that
//     route's own comment for why: an honest "child free" definition (is an
//     uncovered gap in her day-part schedule "free," or merely
//     "unstructured, not necessarily reachable"?) has no confirmed answer
//     yet. A wrong invented definition here would be worse than the honest
//     absence GuardianHome's own nullable field already renders as nothing.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'calendar_day_logic.dart';
import 'guardian_home.dart';

enum _LoadState { loading, error, ready }

class LiveGuardianHomeScreen extends StatefulWidget {
  const LiveGuardianHomeScreen({
    super.key,
    required this.baseUrl,
    required this.guardianId,
    required this.childId,
    this.httpClient,
  });

  final String baseUrl;
  final String guardianId;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient) —
  /// same seam as [LiveChildHomeScreen]'s own `httpClient` field. Also
  /// passed straight through to the wrapped [GuardianHome]'s own
  /// `availabilityHttpClient`, so its Availability/Care-note/More tiles
  /// share the same fake client a test injects here, rather than each
  /// needing its own separate wiring.
  final http.Client? httpClient;

  @override
  State<LiveGuardianHomeScreen> createState() => _LiveGuardianHomeScreenState();
}

class _LiveGuardianHomeScreenState extends State<LiveGuardianHomeScreen> {
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  String _childName = '';
  String _childLocalTime = '';
  String _childZoneAbbr = '';
  String _actorLocalTime = '';
  String? _dayPart;
  bool? _reachable;
  List<RibbonBand> _childBands = const [];
  List<RibbonBand> _actorBands = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final token = await devLoginFor(widget.baseUrl,
          userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final now = await api.fetchNow(widget.childId);
      final ribbon = await api.fetchRibbon(widget.childId);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      final dayParts = (ribbon['dayParts'] as List).cast<Map<String, dynamic>>();
      final actorWindows = (ribbon['actorWindows'] as List).cast<Map<String, dynamic>>();
      setState(() {
        // /now — real, unmodified, the same route ChildHome's own live
        // wrapper already calls. Guardian-callable too: /now's own gate is
        // the wider calendar.view grant, not /ribbon's narrower real-
        // parent-guardian one.
        _childLocalTime = now['childLocalTime'] as String;
        _childZoneAbbr = now['zoneAbbr'] as String;
        // Real as of this pass — send_time_guard.dart's own live path
        // reads these straight through GuardianHome rather than doing a
        // second fetch. Both genuinely nullable on the wire (a null
        // dayPart/reachable is /now's own honest-absence answer if the
        // server-side gate() call comes back empty), not just Dart-side
        // defensive casting.
        _dayPart = now['dayPart'] as String?;
        _reachable = now['reachable'] as bool?;
        // /ribbon — real, new this pass. childName has no GET /v1/me analog
        // for a guardian caller (that route returns the CALLER's own name).
        _childName = (ribbon['childName'] as String?) ?? 'her';
        _childBands = bandsFromDayParts(dayParts);
        _actorBands = bandsFromWindows(actorWindows);
        // No server tz column exists for app_user (confirmed directly, not
        // assumed) — the guardian's own clock is legitimately device-local,
        // same honest-stub posture calendar_day_logic.dart's own hhmmNow()
        // already documents for the identical reason. Formatted to match
        // /now's own "h:mm a" wire shape, not reformatted client-side twice.
        _actorLocalTime = _formatNowLocal();
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
        _state = _LoadState.error;
      });
    }
  }

  String _formatNowLocal() => formatTimeOfDay(hhmmNow());

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _LoadState.error:
        return Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )));
      case _LoadState.ready:
        return Scaffold(body: SafeArea(child: Column(children: [
          Container(width: double.infinity,
            color: Theme.of(context).colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "Live: $_childName's name, clock, and day are real, fetched "
              'from the server just now.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onTertiaryContainer))),
          Expanded(child: GuardianHome(
            childName: _childName,
            childLocalTime: _childLocalTime,
            childZoneAbbr: _childZoneAbbr,
            actorLocalTime: _actorLocalTime,
            childStateSentence: null, // no real source yet — see file header
            childBands: _childBands,
            actorBands: _actorBands,
            overlapLabel: null, // deliberately omitted — see file header
            baseUrl: widget.baseUrl,
            guardianId: widget.guardianId,
            childId: widget.childId,
            availabilityHttpClient: widget.httpClient,
            dayPart: _dayPart,
            reachable: _reachable,
          )),
        ])));
    }
  }
}

const int _minutesPerDay = 24 * 60;

/// Real day-parts (already weekday-filtered server-side) -> GuardianHome's
/// own [RibbonBand] shape, same fractional-layout technique my_day.dart's
/// private `_bandRects` already established for the identical wrap-past-
/// midnight case (an overnight part like asleep 20:00->06:30 splits into
/// two contiguous rectangles, one ending at midnight, one starting from it,
/// so the ribbon still reads as one unbroken 24-hour strip). Colors/labels
/// come from calendar_day_logic.dart's own shared `dayPartColor()`/
/// `dayPartLabel()` — the same lookup my_day.dart's own Day Ribbon uses, so
/// a given kind reads as the same color in both her frame and his.
List<RibbonBand> bandsFromDayParts(List<Map<String, dynamic>> dayParts) {
  final bands = <RibbonBand>[];
  for (final p in dayParts) {
    final kind = p['kind'] as String;
    final s = minutesSinceMidnight(p['startsLocal'] as String);
    final e = minutesSinceMidnight(p['endsLocal'] as String);
    final color = dayPartColor(kind);
    final label = dayPartLabel(kind);
    if (e > s) {
      bands.add(RibbonBand(s / _minutesPerDay, (e - s) / _minutesPerDay, color, label));
    } else {
      bands
        ..add(RibbonBand(s / _minutesPerDay, (_minutesPerDay - s) / _minutesPerDay, color, label))
        ..add(RibbonBand(0, e / _minutesPerDay, color, label));
    }
  }
  return bands;
}

/// The calling guardian's own real availability windows (already scoped to
/// today and to her alone, server-side) -> [RibbonBand]s for the "you"
/// ribbon. Unlike day-parts, a window can never wrap past midnight —
/// guardian_availability_window's own real CHECK constraint (`end_local >
/// start_local`, db/migrations/0010_availability.sql) enforces that at the
/// database layer, so there is no analogous split-rectangle case here.
///
/// One fixed color (dayPartColor('free') — the same "free time" cyan
/// my_day.dart's own ribbon already uses for the identical concept) rather
/// than inventing a second palette: a window is the one thing this route
/// has real data for at all, and it always means the same thing — she is
/// reachable. Everything NOT covered by a window is left as an honest gap
/// (no band), never labelled "busy"/"asleep"/"work" — this route has no
/// real signal for what she's doing outside her own declared windows, and
/// guessing one would be exactly the fabrication this codebase's own
/// established discipline refuses everywhere else.
List<RibbonBand> bandsFromWindows(List<Map<String, dynamic>> windows) {
  final color = dayPartColor('free');
  return [
    for (final w in windows)
      RibbonBand(
        minutesSinceMidnight(w['startLocal'] as String) / _minutesPerDay,
        (minutesSinceMidnight(w['endLocal'] as String) -
            minutesSinceMidnight(w['startLocal'] as String)) / _minutesPerDay,
        color,
        (w['note'] as String?) ?? 'available',
      ),
  ];
}
