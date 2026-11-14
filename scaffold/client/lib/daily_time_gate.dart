// OLIVE BRANCH — the reading-and-watching door on HER device, with the daily total a grown-up
// chose. No longer UNVERIFIED — verified by CI (client/test/daily_time_test.dart).
// MASTERFILE §8.6.6, §8.1, §2.1 (P1-P11).
//
// [DailyTimeGate] wraps a reading or watching surface. While that surface is on screen, the
// app is in front and the total is not off, it counts seconds on THIS device (local clock;
// the day turns over at her local midnight and a new day starts from nothing). The count is
// kept in LocalStore (daily_time_store.dart), is never shown to her as a number, and is never
// a score, a streak or a history: one day, then gone.
//
//   * Plenty of time left: the surface is shown as it is. No clock, no bar, no counter.
//   * The last few minutes: ONE calm line over it, in kid words, with no number.
//   * Used up: a rest card replaces the surface. It is a rest, not a punishment; there is more
//     tomorrow. It never says minutes, hours, limit or locked, and it never blocks calls or
//     family messages (this file imports neither).
//   * A grown-up can allow 30 more minutes for TODAY (never past three hours extra). The kid
//     card has one quiet "I'm the grown-up" button; it opens the adult gate through
//     [GrownUpProofScope] (provided by the kiosk shell, which owns the PIN check), so a child
//     never sees a keypad flow here. After the proof, the plain adult wording and the choice.
//     Without a scope (no way to prove it) the button is simply absent: nothing fakes success.
//
// What it does NOT do: it does not count while the app is in the background or while another
// door (a game, a call, a message) is in front, because only a mounted gate counts. A device
// that was asleep adds at most a few ticks (a jump in the clock never adds a long stretch).
import 'dart:async';

import 'package:flutter/material.dart';

import 'daily_time_logic.dart';
import 'daily_time_store.dart';
import 'home_plan_store.dart';

/// How a grown-up proves they are one, on a child's device. The kiosk shell supplies it (its PIN
/// check and phone unlock); the gate only asks. Resolves true only after a real proof.
class GrownUpProofScope extends InheritedWidget {
  const GrownUpProofScope({super.key, required this.verify, required super.child});

  final Future<bool> Function(BuildContext context) verify;

  static GrownUpProofScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GrownUpProofScope>();

  @override
  bool updateShouldNotify(GrownUpProofScope old) => verify != old.verify;
}

class DailyTimeGate extends StatefulWidget {
  const DailyTimeGate({
    super.key,
    required this.child,
    this.childName,
    this.plan,
    this.usage,
    this.clock,
    this.tick = const Duration(seconds: 15),
  });

  final Widget child;

  /// Used only in the adult's plain line. Never shown to her.
  final String? childName;

  /// Null uses the on-device plan / usage for this device's child.
  final HomePlanRepository? plan;
  final DayUseRepository? usage;

  /// Her LOCAL clock (null = the device clock). Injected by tests.
  final DateTime Function()? clock;

  /// How often the count advances. Tests make it short.
  final Duration tick;

  @override
  State<DailyTimeGate> createState() => _DailyTimeGateState();
}

class _DailyTimeGateState extends State<DailyTimeGate> with WidgetsBindingObserver {
  late final HomePlanRepository _plan = widget.plan ?? LocalStoreHomePlanRepository.shared();
  late final DayUseRepository _usage = widget.usage ?? LocalStoreDayUseRepository.shared();

  int _hours = 0;
  DayUse? _use;
  Timer? _timer;
  DateTime? _last;
  bool _foreground = true;
  bool _dirty = false;
  int _unsavedSeconds = 0;
  int _ticks = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    HomePlan p;
    DayUse u;
    try {
      p = await _plan.load();
    } catch (_) {
      p = HomePlan.defaults;
    }
    final DateTime now = _now();
    try {
      u = await _usage.load(localDayKey(now));
    } catch (_) {
      u = DayUse(day: localDayKey(now));
    }
    if (!mounted) return;
    setState(() {
      _hours = p.dailyHours;
      _use = u;
    });
    _last = now;
    _syncTimer();
  }

  void _syncTimer() {
    if (_hours > 0 && _timer == null) {
      _timer = Timer.periodic(widget.tick, (_) => _onTick());
    } else if (_hours <= 0 && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _reloadPlan() async {
    try {
      final HomePlan p = await _plan.load();
      if (!mounted || p.dailyHours == _hours) return;
      setState(() => _hours = p.dailyHours);
      _syncTimer();
    } catch (_) {/* keep the last known total */}
  }

  void _onTick() {
    final DateTime now = _now();
    final DayUse? before = _use;
    if (before == null) return;
    DayUse use = before;
    final String today = localDayKey(now);
    if (use.day != today) {
      // Local midnight: a new day starts from nothing, and yesterday's extra time is gone too.
      use = DayUse(day: today);
      _unsavedSeconds = 0;
      _dirty = true;
    }
    final DailyTimeState was = dailyTimeState(_hours, use);
    final int cap = widget.tick.inSeconds * 3 + 1;
    final int elapsed = (_last == null ? 0 : now.difference(_last!).inSeconds).clamp(0, cap);
    _last = now;
    if (_foreground && was != DailyTimeState.done && elapsed > 0) {
      use = use.copyWith(seconds: use.seconds + elapsed);
      _unsavedSeconds += elapsed;
      _dirty = true;
    }
    final DailyTimeState nowState = dailyTimeState(_hours, use);
    final bool changed = use != before;
    if (changed && mounted) setState(() => _use = use);
    if (_dirty && (_unsavedSeconds >= 30 || nowState != was || use.day != before.day)) _flush();
    if (++_ticks % 4 == 0) _reloadPlan();
  }

  void _flush() {
    final DayUse? u = _use;
    if (u == null || !_dirty) return;
    _dirty = false;
    _unsavedSeconds = 0;
    () async {
      try {
        await _usage.save(u);
      } catch (_) {/* the count carries on in memory for this visit */}
    }();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool front = state == AppLifecycleState.resumed;
    if (front == _foreground) return;
    _foreground = front;
    if (front) {
      _last = _now(); // time spent away never counts
    } else {
      _flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _flush();
    super.dispose();
  }

  Future<void> _grownUp() async {
    final GrownUpProofScope? scope = GrownUpProofScope.maybeOf(context);
    if (scope == null) return;
    final bool proved = await scope.verify(context);
    if (!proved || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _AdultSheet(
        childName: widget.childName ?? 'her',
        canAllowMore: canAllowMore(_use?.bonusMinutes ?? 0),
        onAllow: () {
          final DayUse? u = _use;
          if (u != null) {
            setState(() => _use = u.copyWith(bonusMinutes: nextBonusMinutes(u.bonusMinutes)));
            _dirty = true;
            _flush();
          }
          Navigator.of(ctx).pop();
        },
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DayUse? use = _use;
    if (use == null || _hours <= 0) return widget.child;
    final DailyTimeState s = dailyTimeState(_hours, use);
    if (s == DailyTimeState.done) {
      return _RestCard(
        line: dailyKidLine(s)!,
        onGrownUp: GrownUpProofScope.maybeOf(context) == null ? null : _grownUp,
      );
    }
    final String? line = dailyKidLine(s);
    // The same structure in both states so the surface under it keeps its place.
    return Stack(fit: StackFit.expand, children: <Widget>[
      widget.child,
      if (line != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: Semantics(
              liveRegion: true,
              child: Material(
                key: const Key('dailyWindDown'),
                elevation: 3,
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(line, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _RestCard extends StatelessWidget {
  const _RestCard({required this.line, required this.onGrownUp});
  final String line;
  final VoidCallback? onGrownUp;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rest time')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Icon(Icons.bedtime_outlined, size: 56),
                const SizedBox(height: 12),
                Text(line,
                    key: const Key('dailyRestLine'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                if (onGrownUp != null) ...<Widget>[
                  const SizedBox(height: 28),
                  TextButton(
                    key: const Key('dailyGrownUp'),
                    onPressed: onGrownUp,
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text("I'm the grown-up"),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
}

/// Plain words and one choice, for a grown-up who proved they are one. Never shown before the proof.
class _AdultSheet extends StatelessWidget {
  const _AdultSheet({
    required this.childName,
    required this.canAllowMore,
    required this.onAllow,
    required this.onClose,
  });
  final String childName;
  final bool canAllowMore;
  final VoidCallback onAllow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('Daily time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(dailyAdultLine(childName), key: const Key('dailyAdultLine')),
            const SizedBox(height: 16),
            if (canAllowMore)
              FilledButton(
                key: const Key('dailyAllowMore'),
                onPressed: onAllow,
                child: const Text('Allow $kDailyBonusStepMinutes more minutes today'),
              )
            else
              const Text('You have already allowed the most extra time for one day.',
                  key: Key('dailyAllowedMax')),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('dailyNotNow'),
              onPressed: onClose,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Not now'),
            ),
          ]),
        ),
      );
}
