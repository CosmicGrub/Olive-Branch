// OLIVE BRANCH — "Her colour and art", the guardian's screen. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.4, §8.6.5, §8.1.
//
// Today's colour is shown as a fact: one neutral sentence, the time she chose
// it, and that all her devices show it. There is no mood, no trend, no history
// of colours and no reading of why (§8.6.4 — a colour is a fact, not a mood).
//
// A guardian may set a "colour day" for today. It replaces her answer, she is
// not asked the question that day, and clearing it hands the question back to
// her; her own answer is never deleted by clearing. The art style is the
// guardian's: it changes how pictures are drawn, never her colour.
//
// Local-first: everything goes through [GuardianColourStore]; nothing here
// touches a network.
import 'package:flutter/material.dart';
import 'colour_critter_screen.dart' show styleName;
import 'colour_day_logic.dart';
import 'her_colour_store.dart';
import 'palette_logic.dart';

class HerColourGuardianScreen extends StatefulWidget {
  const HerColourGuardianScreen({super.key, required this.childName, required this.childAge, this.store});

  final String childName;
  final int childAge;
  /// Null uses the process-wide in-memory store.
  final GuardianColourStore? store;

  @override
  State<HerColourGuardianScreen> createState() => _HerColourGuardianScreenState();
}

class _HerColourGuardianScreenState extends State<HerColourGuardianScreen> {
  late final GuardianColourStore _store = widget.store ?? sharedColourStore;
  GuardianColourView? _view;
  ArtSettings? _art;
  String _pending = '';
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _store.view();
    final a = await _store.art();
    if (!mounted) return;
    setState(() { _view = v; _art = a; });
  }

  Future<void> _setDay(String id) async {
    await _store.setColourDay(id);
    final v = await _store.view();
    if (!mounted) return;
    setState(() { _view = v; _note = 'Colour day set for today.'; });
  }

  Future<void> _clearDay() async {
    await _store.clearColourDay();
    final v = await _store.view();
    if (!mounted) return;
    setState(() { _view = v; _note = 'Colour day cleared. ${widget.childName} can choose again.'; });
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final r = await _store.saveArt(patch);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _art = r.settings;
        _note = 'Saved.';
      } else {
        _note = switch (r.reason) {
          'style_not_for_age' => 'That style opens at $pixelMinAge.',
          'style_not_allowed' => 'The default style has to be one of the allowed styles.',
          _ => 'That could not be saved.',
        };
      }
      _pending = '';
    });
    final v = await _store.view();
    if (mounted) setState(() => _view = v);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view, art = _art;
    final name = widget.childName;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Her colour and art')),
      body: SafeArea(child: view == null || art == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                CircleAvatar(key: const Key('guardianSwatch'), radius: 28,
                  backgroundColor: view.today.swatch?.color ?? theme.colorScheme.surfaceContainerHighest),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(view.line ?? '$name has not chosen a colour yet.', key: const Key('colourLine'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (view.chosenAtLocal != null) Text('Chosen at ${view.chosenAtLocal}, her time.', style: theme.textTheme.bodySmall),
                  if (view.today.override) Text('This is a colour day you set.', key: const Key('colourDayNote'), style: theme.textTheme.bodySmall),
                  if (view.devicesAgree) Text('Every device $name uses shows the same colour.', style: theme.textTheme.bodySmall),
                ])),
              ]))),
              if (_note != null) Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(_note!, key: const Key('guardianNote'), style: theme.textTheme.bodyMedium)),
              const SizedBox(height: 16),
              Text('A colour day', style: theme.textTheme.titleMedium),
              Text('Choose a colour for today. It replaces $name’s answer and she is not asked. '
                  'Clearing it gives the question back to her.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in palette) Semantics(button: true, label: 'Set ${s.label} as today’s colour',
                  child: InkWell(key: Key('day_${s.id}'), customBorder: const CircleBorder(),
                    onTap: () => _setDay(s.id),
                    child: Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle,
                        border: view.today.override && view.today.colourId == s.id
                          ? Border.all(color: theme.colorScheme.primary, width: 4) : null)))),
              ]),
              if (view.today.override) TextButton(key: const Key('clearColourDay'),
                onPressed: _clearDay, child: const Text('Clear the colour day')),
              const Divider(height: 32),
              SwitchListTile(key: const Key('dailyQuestionSwitch'), contentPadding: EdgeInsets.zero,
                title: const Text('Ask which colour she likes more each day'),
                subtitle: const Text('Once a day, in the morning. Turn it off and her colour stays as it is.'),
                value: art.dailyQuestion, onChanged: (v) => _save({'dailyQuestion': v})),
              SwitchListTile(key: const Key('codeActivitiesSwitch'), contentPadding: EdgeInsets.zero,
                title: const Text('Coding activities'),
                subtitle: const Text('Path code from 5, Pixel garden from 8.'),
                value: art.codeActivities, onChanged: (v) => _save({'codeActivities': v})),
              const Divider(height: 32),
              Text('Art style', style: theme.textTheme.titleMedium),
              Text('How pictures are drawn in her activities. It never changes her colour.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in stylesForAge(widget.childAge)) ChoiceChip(
                  key: Key('artStyle_$s'), label: Text(styleName(s)),
                  selected: art.artStyle == s,
                  onSelected: (_) => _save({
                    'artStyle': s,
                    if (!art.allowedStyles.contains(s)) 'allowedStyles': [...art.allowedStyles, s],
                  })),
              ]),
              const SizedBox(height: 12),
              Text('Styles she can pick between', style: theme.textTheme.titleSmall),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in stylesForAge(widget.childAge)) FilterChip(
                  key: Key('allowed_$s'), label: Text(styleName(s)),
                  selected: art.allowedStyles.contains(s),
                  onSelected: (on) {
                    final next = on ? [...art.allowedStyles, s] : art.allowedStyles.where((x) => x != s).toList();
                    _save({'allowedStyles': next});
                  }),
              ]),
              if (widget.childAge < pixelMinAge) Padding(padding: const EdgeInsets.only(top: 6),
                child: Text('Pixel opens at $pixelMinAge and cannot be turned on earlier.', style: theme.textTheme.bodySmall)),
              const Divider(height: 32),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('You can', style: theme.textTheme.titleSmall),
                const Text('• Choose the art style and the styles she can pick between\n'
                    '• Turn the daily question and the coding activities off\n'
                    '• Set a colour day for today, and clear it'),
                const SizedBox(height: 10),
                Text('You can’t', style: theme.textTheme.titleSmall),
                const Text('• See why she chose a colour, or a history of her choices\n'
                    '• Show it to anyone as a reading of how she feels'),
              ]))),
              if (_pending.isNotEmpty) const SizedBox.shrink(),
            ]),
          )),
    );
  }
}
