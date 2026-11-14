// OLIVE BRANCH — the play window and daily time (the prototype's g-play). No
// longer UNVERIFIED — verified by CI (client/test/her_colour_screens_test.dart,
// client/test/play_window_daily_test.dart). MASTERFILE §8.6.6, §8.1, §5.19.
//
// Two halves of one setting. [PlayWindowScreen] is the guardian's: whether to use
// a window at all, when games open, when they rest, and how long the wind-down
// tail is (off, 15 or 30 minutes). [PlayWindowGate] is what her device does with
// it: for the tail AFTER the rest time a calm line appears in her own frame
// ("It's getting sleepy. One more, then goodnight."), and a game in progress can
// finish while new ones wait; after the tail the games door shows a goodnight
// card until the window opens again. (Rest time first, wind-down after: the
// prototype's order, parity ledger rule playWindow.states.)
//
// The ending is a goodnight, not a limit. It carries no number, no timer, no
// red and no lock; a game already in progress is never cut off (the gate only
// stands at the games door); and it gates GAMES ONLY — calls and family
// messages never pass through it, by construction: this file imports neither.
// Local-first: the window lives behind [GuardianColourStore]/[ChildColourStore].
//
// DAILY TIME is the grown-up's chosen ceiling for reading and watching together
// across both homes (off, 1, 2 or 3 hours). It is kept on this device
// (home_plan_store.dart). Be honest about what it does: nothing in her app counts
// minutes (P2 forbids showing her a count, and no screen keeps one), so today it
// records the total a guardian chose and does not stop anything; the card says so
// in words. A raise is something the other guardian will be told, which needs
// the network that is not built yet, and the card says that too. It never fakes
// either.
import 'package:flutter/material.dart';
import 'colour_day_logic.dart';
import 'her_colour_store.dart';
import 'home_plan_store.dart';
import 'ui/olive_ui.dart';

/// 930 -> "3:30 PM".
String minuteLabel(int m) {
  final h24 = m ~/ 60, mm = m % 60;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:${mm.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}

/// The timeline on the screen runs 6 AM to 9 PM, like the prototype's.
const int kTimelineFrom = 6 * 60, kTimelineTo = 21 * 60;

class PlayWindowScreen extends StatefulWidget {
  const PlayWindowScreen({super.key, required this.childName, this.store, this.plan});

  final String childName;
  final GuardianColourStore? store;

  /// Null uses the on-device plan for the shared child.
  final HomePlanRepository? plan;

  @override
  State<PlayWindowScreen> createState() => _PlayWindowScreenState();
}

class _PlayWindowScreenState extends State<PlayWindowScreen> {
  late final GuardianColourStore _store = widget.store ?? sharedColourStore;
  late final HomePlanRepository _planRepo = widget.plan ?? LocalStoreHomePlanRepository.shared();
  int _opens = 15 * 60 + 30, _rests = 19 * 60, _wind = 30;
  bool _on = true;
  bool _loaded = false;
  String? _note;
  String? _state;
  HomePlan _plan = HomePlan.defaults;
  String? _dailyMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await _store.playWindow();
    final p = await _planRepo.load();
    if (!mounted) return;
    setState(() {
      final w = i.window;
      _on = w != null;
      if (w != null) { _opens = w.opensMin; _rests = w.restsMin; _wind = w.windDownMin; }
      _state = i.state;
      _plan = p;
      _loaded = true;
    });
  }

  PlayWindow get _window => PlayWindow(opensMin: _opens, restsMin: _rests, windDownMin: _wind);

  Future<void> _save() async {
    if (!_on) {
      await _store.clearPlayWindow();
      final i = await _store.playWindow();
      if (!mounted) return;
      setState(() { _state = i.state; _note = 'Saved. Games are open all day.'; });
      return;
    }
    final r = await _store.savePlayWindow(_window);
    final i = await _store.playWindow();
    if (!mounted) return;
    setState(() {
      _state = i.state;
      _note = r.ok
          ? (r.lengthened
              ? 'Saved. This window is longer than before. Telling the other guardian needs the network, which is not built yet, so nothing was sent.'
              : 'Saved.')
          : switch (r.reason) {
              'bad_restsMin' => 'Games have to rest after they open.',
              _ => 'That could not be saved.',
            };
    });
  }

  Future<void> _setDaily(int hours) async {
    final from = _plan.dailyHours;
    if (hours == from) return;
    final next = _plan.copyWith(dailyHours: hours, dailyNote: dailyChangeNote(from, hours));
    setState(() { _plan = next; _dailyMsg = null; });
    try {
      await _planRepo.save(next);
      if (mounted) {
        setState(() => _dailyMsg = hours > from
            ? 'Saved on this device. A raise is something the other guardian will be told; that needs the network, which is not built yet.'
            : 'Saved on this device.');
      }
    } catch (_) {
      if (mounted) setState(() => _dailyMsg = 'Changed for now, but this device could not keep it.');
    }
  }

  List<DropdownMenuItem<int>> _items(int from, int to) => [
    for (var m = from; m <= to; m += 15) DropdownMenuItem(value: m, child: Text(minuteLabel(m))),
  ];

  String _stateWords(String? s) => switch (s) {
    'winding_down' => 'winding down',
    'resting' => 'resting',
    _ => 'open',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = checkPlayWindow(_window.toJson());
    final name = widget.childName;
    return Scaffold(
      appBar: AppBar(title: const Text('Play window and daily time')),
      body: SafeArea(child: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('When $name’s games are open', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Her day, her time. Calls and family messages are never affected.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_on && check.ok) _Timeline(window: _window),
            if (_on && check.ok) const SizedBox(height: 12),
            OliveCard(child: ToggleRow(key: const Key('useWindow'), title: 'Use a play window',
              sub: _on ? 'Games follow the window below' : 'Games are open all day',
              icon: OliveIcons.moon, value: _on, onChanged: (v) => setState(() { _on = v; _note = null; }))),
            if (_on) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Opens'),
                  child: DropdownButton<int>(key: const Key('opensDrop'), isExpanded: true, underline: const SizedBox.shrink(),
                    value: _opens, items: _items(0, 1425), onChanged: (v) => setState(() { _opens = v!; _note = null; })))),
                const SizedBox(width: 12),
                Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Rests at'),
                  child: DropdownButton<int>(key: const Key('restsDrop'), isExpanded: true, underline: const SizedBox.shrink(),
                    value: _rests, items: _items(15, 1425), onChanged: (v) => setState(() { _rests = v!; _note = null; })))),
              ]),
              const SizedBox(height: 16),
              Text('Wind-down', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedControl(key: const Key('windSeg'), semanticLabel: 'Wind-down',
                items: const [SegmentItem('Off'), SegmentItem('15 min'), SegmentItem('30 min')],
                selected: windDownChoices.indexOf(_wind),
                onChanged: (i) => setState(() { _wind = windDownChoices[i]; _note = null; })),
              const SizedBox(height: 4),
              Text('After the rest time a game in progress can finish. The door to new games closes gently.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              OliveCard(variant: OliveCardVariant.tint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('What $name sees at ${minuteLabel(_rests)}', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(playWindowLine(_wind > 0 ? 'winding_down' : 'resting')!, key: const Key('windPreview'),
                  style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('Nothing is taken away. Games open again at ${minuteLabel(_opens)}.', style: theme.textTheme.bodySmall),
              ])),
              if (!check.ok) const Padding(padding: EdgeInsets.only(top: 8),
                child: OliveNotice(key: Key('windInvalid'), tone: OliveTone.warn, title: 'Opens must be before rests',
                  text: 'Pick an opening time earlier than the resting time.')),
            ],
            const SizedBox(height: 8),
            OliveNotice(key: const Key('windLive'), tone: _state == 'open' ? OliveTone.ok : OliveTone.info, icon: OliveIcons.clock,
              title: 'On $name’s tablet right now: games are ${_stateWords(_state)}',
              text: 'This is what the window you last saved says for her day.'),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_note!, key: const Key('windNote'))),
            const SizedBox(height: 16),
            FilledButton(key: const Key('saveWindow'), onPressed: !_on || check.ok ? _save : null, child: const Text('Save play window')),
            const SizedBox(height: 24),
            _dailyCard(theme, name),
          ]))),
    );
  }

  Widget _dailyCard(ThemeData theme, String name) => OliveCard(
    key: const Key('dailyCard'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Daily time', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Reading and watching share one daily total across both homes.', style: theme.textTheme.bodySmall),
      const SizedBox(height: 10),
      SegmentedControl(key: const Key('dailySeg'), semanticLabel: 'Daily time',
        items: [for (final h in dailyHourChoices) SegmentItem(dailyHoursWords(h))],
        selected: dailyHourChoices.indexOf(_plan.dailyHours),
        onChanged: (i) => _setDaily(dailyHourChoices[i])),
      const SizedBox(height: 8),
      Text(_plan.dailyNote ?? 'Lowering is free. A raise will be shown to the other guardian once families can connect.',
        key: const Key('dailyNote'), style: theme.textTheme.bodySmall),
      const SizedBox(height: 6),
      Text('Kept on this device. $name’s screens do not count minutes yet, so nothing stops at this total today; '
        'it records the total you chose.', key: const Key('dailyHonest'), style: theme.textTheme.bodySmall),
      if (_dailyMsg != null) Padding(padding: const EdgeInsets.only(top: 6),
        child: Text(_dailyMsg!, key: const Key('dailyMsg'))),
    ]),
  );
}

/// The 6 AM to 9 PM bar: open stretch, the wind-down tail after it. No bedtime
/// marker (this build keeps no bedtime to read). Positioned, not Expanded, so it
/// scales with any width and text size.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.window});
  final PlayWindow window;

  double _pc(int m) => ((m - kTimelineFrom) / (kTimelineTo - kTimelineFrom)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final o = _pc(window.opensMin), r = _pc(window.restsMin), t = _pc(window.restsMin + window.windDownMin);
    return Semantics(
      label: 'Games open from ${minuteLabel(window.opensMin)} to ${minuteLabel(window.restsMin)}',
      child: ExcludeSemantics(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(key: const Key('windowTimeline'), height: 14, child: LayoutBuilder(builder: (context, k) {
          final w = k.maxWidth;
          return Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(7)))),
            Positioned(left: w * o, width: w * (r - o), top: 0, bottom: 0,
              child: DecoratedBox(decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(7)))),
            Positioned(left: w * r, width: w * (t - r), top: 0, bottom: 0,
              child: DecoratedBox(decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(7)))),
          ]);
        })),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final s in const ['6a', '12p', '6p', '9p']) Text(s, style: Theme.of(context).textTheme.labelSmall),
        ]),
      ])),
    );
  }
}
