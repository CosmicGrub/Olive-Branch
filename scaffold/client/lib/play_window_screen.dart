// OLIVE BRANCH — the play window and the gentle ending. No longer UNVERIFIED —
// verified by CI (a Flutter toolchain runs for real in tools/verify.sh's
// automated pipeline). MASTERFILE §8.6.6, §8.1, §5.19.
//
// Two halves of one setting. [PlayWindowScreen] is the guardian's: when games
// open, when they rest, and how long the wind-down tail is (off, 15 or 30
// minutes). [PlayWindowGate] is what her device does with it: during the tail a
// calm line appears in her own frame ("It's getting sleepy. One more, then
// goodnight."); after it, the games door shows a goodnight card until the
// window opens again.
//
// The ending is a goodnight, not a limit. It carries no number, no timer, no
// red and no lock; a game already in progress is never cut off (the gate only
// stands at the games door); and it gates GAMES ONLY — calls and family
// messages never pass through it, by construction: this file imports neither.
// Local-first: the window lives behind [GuardianColourStore]/[ChildColourStore].
import 'package:flutter/material.dart';
import 'colour_day_logic.dart';
import 'her_colour_store.dart';

/// 930 -> "3:30 PM".
String minuteLabel(int m) {
  final h24 = m ~/ 60, mm = m % 60;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:${mm.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
}

class PlayWindowScreen extends StatefulWidget {
  const PlayWindowScreen({super.key, required this.childName, this.store});

  final String childName;
  final GuardianColourStore? store;

  @override
  State<PlayWindowScreen> createState() => _PlayWindowScreenState();
}

class _PlayWindowScreenState extends State<PlayWindowScreen> {
  late final GuardianColourStore _store = widget.store ?? sharedColourStore;
  int _opens = 15 * 60 + 30, _rests = 19 * 60, _wind = 30;
  bool _loaded = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _store.playWindow().then((i) {
      if (!mounted) return;
      setState(() {
        final w = i.window;
        if (w != null) { _opens = w.opensMin; _rests = w.restsMin; _wind = w.windDownMin; }
        _loaded = true;
      });
    });
  }

  PlayWindow get _window => PlayWindow(opensMin: _opens, restsMin: _rests, windDownMin: _wind);

  Future<void> _save() async {
    final r = await _store.savePlayWindow(_window);
    if (!mounted) return;
    setState(() => _note = r.ok ? 'Saved.' : switch (r.reason) {
      'bad_restsMin' => 'Games have to rest after they open.',
      'window_too_short' => 'That window is too short for its wind-down.',
      _ => 'That could not be saved.',
    });
  }

  List<DropdownMenuItem<int>> _items(int from, int to) => [
    for (var m = from; m <= to; m += 15) DropdownMenuItem(value: m, child: Text(minuteLabel(m))),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = checkPlayWindow(_window.toJson());
    return Scaffold(
      appBar: AppBar(title: const Text('Play window')),
      body: SafeArea(child: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('When ${widget.childName}’s games are open', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Her day, her time. Calls and family messages are never affected.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Opens'),
                child: DropdownButton<int>(key: const Key('opensDrop'), isExpanded: true, underline: const SizedBox.shrink(),
                  value: _opens, items: _items(0, 1425), onChanged: (v) => setState(() => _opens = v!)))),
              const SizedBox(width: 12),
              Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Rests at'),
                child: DropdownButton<int>(key: const Key('restsDrop'), isExpanded: true, underline: const SizedBox.shrink(),
                  value: _rests, items: _items(15, 1425), onChanged: (v) => setState(() => _rests = v!)))),
            ]),
            const SizedBox(height: 16),
            Text('Wind-down', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<int>(key: const Key('windSeg'),
              segments: const [
                ButtonSegment(value: 0, label: Text('Off')),
                ButtonSegment(value: 15, label: Text('15 min')),
                ButtonSegment(value: 30, label: Text('30 min')),
              ],
              selected: {_wind}, onSelectionChanged: (s) => setState(() => _wind = s.first)),
            const SizedBox(height: 4),
            Text('The last stretch fades toward goodnight. A game in progress can finish.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What ${widget.childName} sees at ${minuteLabel(_rests - _wind)}', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(playWindowLine(_wind > 0 ? 'winding_down' : 'resting')!, key: const Key('windPreview'),
                style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Nothing is taken away. Games open again at ${minuteLabel(_opens)}.', style: theme.textTheme.bodySmall),
            ]))),
            if (!check.ok) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text('This window is not valid yet: games must rest after they open, with room for the wind-down.',
                key: const Key('windInvalid'), style: TextStyle(color: theme.colorScheme.error))),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_note!, key: const Key('windNote'))),
            const SizedBox(height: 16),
            FilledButton(key: const Key('saveWindow'), onPressed: check.ok ? _save : null, child: const Text('Save play window')),
          ]))),
    );
  }
}
