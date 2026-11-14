// OLIVE BRANCH — suite I COMPASS, the guardian's screens: two gentle questions,
// the suggestions, the suites shelf and the two accessibility profiles. No longer
// UNVERIFIED — verified by CI (client/test/compass_screens_test.dart).
//
// GUARDIAN-ONLY AND ON THIS DEVICE ONLY. There is no child-side Compass screen,
// and the child shell never imports this file. Nothing is sent; the answers are
// sealed in a local area a child principal cannot read.
//
// TONE, AND ITS LIMITS. The questions describe the family's days and supports,
// never the child: nothing is called a condition, a diagnosis, a need-level or a
// type. "Not sure" and "skip" are complete answers. Suggestions are a short list
// from a plain table, each with a sentence of why and the answers that led to it;
// nothing is switched on until a guardian does it, and "Not now" remembers
// nothing. The shelf shows on or off and what a suite adds, never how much it was
// used. It is not a store and sells nothing (P4).
import 'package:flutter/material.dart';

import 'access_settings.dart' show AccessSettings;
import 'compass_logic.dart';
import 'compass_repositories.dart';
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'picture_icons.dart' show QuietNote;

/// The plain-words explanation of a refusal.
String compassRefusalText(String reason) => switch (reason) {
      'guardian_only' => 'Only a grown-up can change this.',
      'full' => 'There is no more room on this device.',
      'unknown_suite' || 'unknown_profile' => 'That is not one of the choices.',
      _ => 'That did not save.',
    };

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
      );
}

mixin _Say<T extends StatefulWidget> on State<T> {
  /// True when the device refused to read the document (only a guardian
  /// principal can): the screen then shows [deniedNote] and nothing else.
  bool denied = false;

  Widget get deniedNote => const QuietNote('Only a grown-up can change this.', icon: Icons.lock_outline);

  void say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void reportResult(CompassResult r) => say(r.ok ? 'Saved on this device.' : compassRefusalText(r.reason));
}

class _LocalNote extends StatelessWidget {
  const _LocalNote();
  @override
  Widget build(BuildContext context) =>
      const QuietNote('Kept on this device only. Nothing here is sent, and nothing is switched on without you.',
          icon: Icons.phone_android_outlined);
}

/// Facts the family builder already holds, as option ids (see [builderHints]).
typedef BuilderHints = Future<List<String>> Function();

// ================================================================== HUB ======
class CompassHubScreen extends StatelessWidget {
  const CompassHubScreen({
    super.key, required this.childName, required this.service, required this.principal, this.hints,
  });
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;
  final BuilderHints? hints;

  void _push(BuildContext context, Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) => _Page(title: 'Family compass', children: <Widget>[
        const _LocalNote(),
        const SizedBox(height: 8),
        Text(
            'Two short questions about $childName\'s days, so the app can point at tools that may help. '
            'This only shapes suggestions. You can skip, change or forget your answers at any time.',
            key: const Key('compassPromise')),
        const SizedBox(height: 8),
        _tile(context, 'rowWho', Icons.diversity_3_outlined, 'Who is in her life', 'Step 1: ways families look',
            () => _push(context, CompassQuestionScreen(step: CompassStep.who, childName: childName, service: service, principal: principal, hints: hints))),
        _tile(context, 'rowNeeds', Icons.lightbulb_outline, 'What would help her', 'Step 2: things that help her day go well',
            () => _push(context, CompassQuestionScreen(step: CompassStep.needs, childName: childName, service: service, principal: principal))),
        _tile(context, 'rowSuggest', Icons.checklist_rtl_outlined, 'Suggested for your family', 'A few suites to look at, each with a reason',
            () => _push(context, CompassSuggestScreen(childName: childName, service: service, principal: principal))),
        _tile(context, 'rowShelf', Icons.view_agenda_outlined, 'Suites shelf', 'What is on and off for her',
            () => _push(context, SuitesShelfScreen(childName: childName, service: service, principal: principal))),
        _tile(context, 'rowProfiles', Icons.accessibility_new_outlined, 'Accessibility profiles', 'Away from home; alerts she can see',
            () => _push(context, ProfilesScreen(childName: childName, service: service, principal: principal))),
      ]);

  Widget _tile(BuildContext context, String key, IconData icon, String title, String sub, VoidCallback onTap) => Card(
        child: ListTile(
            key: Key(key), minVerticalPadding: 12, leading: Icon(icon), title: Text(title), subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}

// ============================================================== questions ====
enum CompassStep { who, needs }

class CompassQuestionScreen extends StatefulWidget {
  const CompassQuestionScreen({
    super.key, required this.step, required this.childName, required this.service, required this.principal, this.hints,
  });
  final CompassStep step;
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;
  final BuilderHints? hints;
  @override
  State<CompassQuestionScreen> createState() => _QuestionState();
}

class _QuestionState extends State<CompassQuestionScreen> with _Say<CompassQuestionScreen> {
  CompassAnswers _a = const CompassAnswers();
  List<String> _hints = const <String>[];
  bool _loaded = false;

  bool get _who => widget.step == CompassStep.who;
  List<CompassOption> get _options => _who ? compassWhoOptions : compassNeedsOptions;
  Set<String> get _chosen => _who ? _a.who : _a.needs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<String> hints = const <String>[];
    try {
      hints = await widget.hints?.call() ?? const <String>[];
    } catch (_) {}
    try {
      final CompassDoc d = await widget.service.load(widget.principal);
      if (mounted) {
        setState(() { _a = d.answers; _hints = hints; _loaded = true; });
        if (!_wordsSet) { _wordsSet = true; _words.text = _wordsNow; }
      }
    } on CompassRefused {
      if (mounted) setState(() => denied = true);
    }
  }

  late final TextEditingController _words = TextEditingController();
  bool _wordsSet = false;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  String get _wordsNow => _who ? _a.whoWords : _a.needsWords;

  void _toggle(String id, bool on) => setState(() => _a = _who ? _a.withWho(id, on) : _a.withNeed(id, on));

  Future<void> _save() async {
    _a = _who ? _a.copyWith(whoWords: _words.text) : _a.copyWith(needsWords: _words.text);
    final CompassResult r = await widget.service.saveAnswers(widget.principal, _a);
    reportResult(r);
    if (r.ok && mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => _Page(
        title: _who ? 'Who is in her life' : 'What would help her',
        children: <Widget>[
          const _LocalNote(),
          const SizedBox(height: 8),
          if (denied) deniedNote,
          Text(_who ? 'Which of these sound like ${widget.childName}\'s family?' : 'Anything here that helps ${widget.childName}\'s day go well?',
              style: Theme.of(context).textTheme.titleMedium),
          const Text('Choose any, or none. This only shapes suggestions.', key: Key('questionPromise')),
          const SizedBox(height: 8),
          if (_loaded && _who && _hints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Your family builder already shows: ${<String>[for (final String h in _hints) optionLabel(h) ?? h].join('; ')}.',
                  key: const Key('builderHint')),
            ),
          if (_loaded)
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final CompassOption o in _options)
                FilterChip(
                  key: Key('opt_${o.id}'), label: Text(o.label), selected: _chosen.contains(o.id),
                  onSelected: (bool v) => _toggle(o.id, v),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ]),
          if (_loaded) ...<Widget>[
            const SizedBox(height: 16),
            TextField(
              key: const Key('compassWords'), controller: _words, maxLength: maxCompassWords, minLines: 2, maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: _who ? 'In your own words (optional)' : 'Anything else that helps (optional)',
                  helperText: 'Only you see this, on this device. It does not change the suggestions.',
                  helperMaxLines: 2, border: const OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(key: const Key('compassSave'), onPressed: _save, child: const Text('Save')),
          TextButton(
              key: const Key('compassNotSure'),
              onPressed: () async {
                // "Not sure" is a complete answer: nothing is ticked, nothing is saved for this step.
                final CompassAnswers cleared = _who
                    ? CompassAnswers(needs: _a.needs, needsWords: _a.needsWords)
                    : CompassAnswers(who: _a.who, whoWords: _a.whoWords);
                _words.clear();
                setState(() => _a = cleared);
                await _save();
              },
              child: const Text('Not sure')),
          TextButton(key: const Key('compassSkip'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Skip for now')),
        ],
      );
}

// ============================================================ suggestions ====
class CompassSuggestScreen extends StatefulWidget {
  const CompassSuggestScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;
  @override
  State<CompassSuggestScreen> createState() => _SuggestState();
}

class _SuggestState extends State<CompassSuggestScreen> with _Say<CompassSuggestScreen> {
  List<Suggestion> _sug = const <Suggestion>[];
  Map<String, bool> _suiteOn = <String, bool>{};
  Set<String> _profilesOn = <String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final CompassDoc d = await widget.service.load(widget.principal);
      final List<ShelfRow> rows = await widget.service.shelf(widget.principal);
      if (!mounted) return;
      setState(() {
        _sug = suggest(d.answers);
        _suiteOn = <String, bool>{for (final ShelfRow r in rows) r.suite.key: r.on};
        _profilesOn = d.profiles;
        _loaded = true;
      });
    } on CompassRefused {
      if (mounted) setState(() => denied = true);
    }
  }

  String _title(Suggestion s) => s.kind == SuggestionKind.suite
      ? shelfSuites.firstWhere((ShelfSuite x) => x.key == s.key).title
      : (profileById(s.key)?.title ?? s.key);

  bool _isOn(Suggestion s) => s.kind == SuggestionKind.suite ? (_suiteOn[s.key] ?? true) : _profilesOn.contains(s.key);

  Future<void> _set(Suggestion s, bool v) async {
    final CompassResult r = s.kind == SuggestionKind.suite
        ? await widget.service.setSuite(widget.principal, s.key, v)
        : await widget.service.setProfile(widget.principal, s.key, v);
    reportResult(r);
    await _load();
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Suggested for your family', children: <Widget>[
        const _LocalNote(),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        const Text('Nothing is switched on for her until you switch it. These come from a short, plain list, in the same order every time.',
            key: Key('suggestNote')),
        const SizedBox(height: 8),
        if (_loaded && _sug.isEmpty)
          const QuietNote('Nothing to suggest from what you have chosen. You can still look at everything on the suites shelf.', icon: Icons.view_agenda_outlined),
        for (final Suggestion s in _sug)
          Card(
            key: Key('sug_${s.kind.name}_${s.key}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text(_title(s), style: Theme.of(context).textTheme.titleMedium)),
                  Switch(key: Key('sugSwitch_${s.key}'), value: _isOn(s), onChanged: (bool v) => _set(s, v)),
                ]),
                for (final String r in s.reasons) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r)),
                const SizedBox(height: 4),
                Text('You chose: ${<String>[for (final String id in s.because) optionLabel(id) ?? id].join('; ')}',
                    key: Key('sugBecause_${s.key}'), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        TextButton(key: const Key('sugNotNow'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Not now')),
      ]);
}

// ================================================================= shelf =====
class SuitesShelfScreen extends StatefulWidget {
  const SuitesShelfScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;
  @override
  State<SuitesShelfScreen> createState() => _ShelfState();
}

class _ShelfState extends State<SuitesShelfScreen> with _Say<SuitesShelfScreen> {
  List<ShelfRow> _rows = const <ShelfRow>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<ShelfRow> rows = await widget.service.shelf(widget.principal);
      if (mounted) setState(() { _rows = rows; _loaded = true; });
    } on CompassRefused {
      if (mounted) setState(() => denied = true);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Suites shelf', children: <Widget>[
        const _LocalNote(),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        Text('What is on for ${widget.childName}. Each switch is the same one on the suite\'s own page. A suite shows her nothing until you have written something for it. Voice starts off and stays off until you switch it on.',
            key: const Key('shelfIntro')),
        const SizedBox(height: 8),
        if (_loaded)
          for (final ShelfRow r in _rows)
            Card(
              key: Key('shelfRow_${r.suite.key}'),
              child: SwitchListTile(
                key: Key('shelfSwitch_${r.suite.key}'),
                title: Text(r.suite.title), subtitle: Text(r.suite.adds), value: r.on,
                onChanged: (bool v) async {
                  reportResult(await widget.service.setSuite(widget.principal, r.suite.key, v));
                  await _load();
                },
              ),
            ),
      ]);
}

// ============================================================== profiles =====
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;
  @override
  State<ProfilesScreen> createState() => _ProfilesState();
}

class _ProfilesState extends State<ProfilesScreen> with _Say<ProfilesScreen> {
  Set<String> _on = <String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final CompassDoc d = await widget.service.load(widget.principal);
      if (mounted) setState(() { _on = d.profiles; _loaded = true; });
    } on CompassRefused {
      if (mounted) setState(() => denied = true);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Accessibility profiles', children: <Widget>[
        const _LocalNote(),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        const Text('A profile only changes how this device looks and behaves. It changes nothing about what is shown, who sees what or any family information, '
            'and it never labels her. Each setting it touches can still be changed one by one under Accessibility.',
            key: Key('profilesNote')),
        const SizedBox(height: 8),
        if (_loaded)
          for (final ProfileDefaults p in allProfiles)
            Card(
              key: Key('profile_${p.id}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  SwitchListTile(
                    key: Key('profileSwitch_${p.id}'), contentPadding: EdgeInsets.zero,
                    title: Text(p.title), subtitle: Text(p.summary), value: _on.contains(p.id),
                    onChanged: (bool v) async {
                      reportResult(await widget.service.setProfile(widget.principal, p.id, v));
                      await _load();
                    },
                  ),
                  const Text('It changes:'),
                  for (final String c in p.changes) Text('• $c'),
                  if (p.visualAlerts == true) ...<Widget>[
                    const SizedBox(height: 8),
                    _AlertPreview(cue: cueFor(const AccessSettings(visualAlerts: true), AlertKind.general)),
                  ],
                  if (_on.contains(p.id))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Turning it off leaves the settings as they are now; change them under Accessibility.',
                          key: Key('profileOffNote_${p.id}'), style: Theme.of(context).textTheme.bodySmall),
                    ),
                ]),
              ),
            ),
      ]);
}

/// What the alert looks like: a picture and words with a steady border (never
/// flashing), shown so the choice is made by eye.
class _AlertPreview extends StatelessWidget {
  const _AlertPreview({required this.cue});
  final AlertCue cue;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      key: const Key('alertPreview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: c.primary, width: 3), borderRadius: BorderRadius.circular(14)),
      child: Row(children: <Widget>[
        const Icon(Icons.notifications_active_outlined, size: 32),
        const SizedBox(width: 10),
        Expanded(child: Text('${cue.text}. Stays until she taps it. Never flashes.')),
      ]),
    );
  }
}
