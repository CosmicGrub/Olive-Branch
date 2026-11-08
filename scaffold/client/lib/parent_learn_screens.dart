// OLIVE BRANCH — Parent Learn screens (guardian app only).
// No longer UNVERIFIED — verified by CI (client/test/parent_learn_screens_test.dart).
// Mockups: docs/superpowers/mockups/parent-learn-suite-mockups.html. Rules and
// research: docs/superpowers/specs/2026-11-07-parenting-styles-education-research.md.
//
// Guardian-only (L1): every screen refuses a non-guardian principal and shows
// nothing from the content. The child shell never links here.
// Optional (owner decision 2026-11-07): private reflection, cultural framing,
// the message check and the two-home rules list are each a guardian's own
// choice, and each defaults to the most private setting.
import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'hub_widgets.dart';
import 'parent_learn_logic.dart';
import 'parent_learn_store.dart';

String _evidenceLabel(Evidence e) => switch (e) {
      Evidence.strong => 'Strong evidence',
      Evidence.moderate => 'Moderate evidence',
      Evidence.weak => 'Weak evidence',
      Evidence.contested => 'Contested',
    };

class EvidenceChip extends StatelessWidget {
  const EvidenceChip(this.evidence, {super.key});
  final Evidence evidence;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    // Shape and words carry the meaning, never colour alone.
    final (Color bg, Color fg, IconData icon) = switch (evidence) {
      Evidence.strong => (c.primaryContainer, c.onPrimaryContainer, Icons.verified_outlined),
      Evidence.moderate => (c.secondaryContainer, c.onSecondaryContainer, Icons.check_circle_outline),
      Evidence.weak => (c.tertiaryContainer, c.onTertiaryContainer, Icons.help_outline),
      Evidence.contested => (c.surfaceContainerHighest, c.onSurface, Icons.balance_outlined),
    };
    return Semantics(
      label: _evidenceLabel(evidence),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(_evidenceLabel(evidence),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _GuardiansOnly extends StatelessWidget {
  const _GuardiansOnly();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Learn')),
        body: const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This area is for guardians.', key: Key('learnGuardiansOnly')))),
      );
}

/// The Learn hub: cards by topic, plus the optional tools a guardian has turned on.
class LearnHomeScreen extends StatefulWidget {
  const LearnHomeScreen({
    super.key,
    required this.principal,
    required this.store,
    this.childAge,
    this.clock = DateTime.now,
  });
  final LearnPrincipal principal;
  final LearnStore store;
  final int? childAge;
  final DateTime Function() clock;

  @override
  State<LearnHomeScreen> createState() => _LearnHomeState();
}

class _LearnHomeState extends State<LearnHomeScreen> {
  LearnSettings _settings = defaultLearnSettings;
  bool _loaded = false;
  String? _topic;

  @override
  void initState() {
    super.initState();
    if (canReadLearn(widget.principal)) _load();
  }

  Future<void> _load() async {
    final LearnSettings s = await widget.store.loadSettings();
    if (mounted) setState(() { _settings = s; _loaded = true; });
  }

  void _open(Widget w) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => w))
      .then((_) => _load());

  @override
  Widget build(BuildContext context) {
    if (!canReadLearn(widget.principal)) return const _GuardiansOnly();
    final List<LearnCard> all = learnCardsFor(widget.principal, _settings, age: widget.childAge);
    final List<String> topics = <String>{for (final LearnCard c in all) c.topic}.toList();
    final List<LearnCard> shown = _topic == null ? all : all.where((LearnCard c) => c.topic == _topic).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('Short, sourced, and honest about what is known.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Your reflections and choices stay on this phone. Rules you add under Rules that match are shared with the other guardian.',
                      key: Key('learnPrivacyLine')),
                  const SizedBox(height: AppSpacing.md),
                  HubSection(title: 'Your tools', children: <Widget>[
                    if (_settings.reflection != 'off')
                      HubTile(
                          key: const Key('learnToolReflection'),
                          icon: Icons.self_improvement_outlined,
                          title: 'Where was today?',
                          subtitle: _settings.reflection == 'saved'
                              ? 'Two sliders. Saved privately for you.'
                              : 'Two sliders. Cleared when you close it.',
                          onTap: () => _open(ReflectionScreen(
                              principal: widget.principal, store: widget.store, clock: widget.clock))),
                    if (_settings.messageCheck)
                      HubTile(
                          key: const Key('learnToolMessage'),
                          icon: Icons.mark_email_read_outlined,
                          title: 'Check before you send',
                          subtitle: 'A mirror, not a monitor. Nothing is sent or saved.',
                          onTap: () => _open(MessageCheckScreen(principal: widget.principal, settings: _settings))),
                    if (_settings.rulesList)
                      HubTile(
                          key: const Key('learnToolRules'),
                          icon: Icons.rule_outlined,
                          title: 'Rules that match',
                          subtitle: 'Bedtime, screens, homework, safety. You choose what to send.',
                          onTap: () => _open(RulesScreen(principal: widget.principal, store: widget.store))),
                    HubTile(
                        key: const Key('learnToolSettings'),
                        icon: Icons.tune_outlined,
                        title: 'Your choices',
                        subtitle: 'Each extra is optional and off or private by default.',
                        onTap: () => _open(LearnSettingsScreen(principal: widget.principal, store: widget.store))),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: <Widget>[
                    ChoiceChip(
                        key: const Key('learnTopicAll'),
                        label: const Text('All'),
                        selected: _topic == null,
                        onSelected: (_) => setState(() => _topic = null)),
                    for (final String t in topics)
                      ChoiceChip(
                          key: Key('learnTopic_$t'),
                          label: Text(t),
                          selected: _topic == t,
                          onSelected: (_) => setState(() => _topic = t)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  for (final LearnCard c in shown)
                    Card(
                      key: Key('learnCard_${c.id}'),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => _open(LearnCardScreen(card: c)),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(c.title, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: AppSpacing.xs),
                            Text(c.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: AppSpacing.sm),
                            EvidenceChip(c.evidence),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
    );
  }
}

class LearnCardScreen extends StatelessWidget {
  const LearnCardScreen({super.key, required this.card});
  final LearnCard card;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(card.title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              EvidenceChip(card.evidence),
              const SizedBox(height: AppSpacing.md),
              Text(card.body, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.lg),
              Text('Sources', style: Theme.of(context).textTheme.titleSmall),
              for (final LearnSource s in card.sources)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: SelectableText('${s.label}\n${s.url}', key: Key('learnSource_${card.id}')),
                ),
              const SizedBox(height: AppSpacing.lg),
              const Text('This is education, not clinical advice. If you are worried about your child, talk to your pediatrician.'),
            ]),
          ),
        ),
      );
}

/// Optional extras. Each is the guardian's own choice; defaults are the most private.
class LearnSettingsScreen extends StatefulWidget {
  const LearnSettingsScreen({super.key, required this.principal, required this.store});
  final LearnPrincipal principal;
  final LearnStore store;
  @override
  State<LearnSettingsScreen> createState() => _LearnSettingsState();
}

class _LearnSettingsState extends State<LearnSettingsScreen> {
  LearnSettings _s = defaultLearnSettings;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (canReadLearn(widget.principal)) {
      widget.store.loadSettings().then((LearnSettings s) {
        if (mounted) setState(() { _s = s; _loaded = true; });
      });
    }
  }

  Future<void> _set(LearnSettings s) async {
    setState(() => _s = s);
    await widget.store.saveSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    if (!canReadLearn(widget.principal)) return const _GuardiansOnly();
    return Scaffold(
      appBar: AppBar(title: const Text('Your choices')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
                const Text('Every one of these is optional. Nothing here is visible to your co-parent or your child.'),
                const SizedBox(height: AppSpacing.md),
                Text('Where was today? (private reflection)', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: _s.reflection,
                  onChanged: (String? v) => v == null ? null : _set(_s.copyWith(reflection: v)),
                  child: const Column(children: <Widget>[
                    RadioListTile<String>(
                        key: Key('reflectionOff'), value: 'off', title: Text('Off'), subtitle: Text('Hide this tool.')),
                    RadioListTile<String>(
                        key: Key('reflectionSession'),
                        value: 'session',
                        title: Text('Just for now'),
                        subtitle: Text('Nothing is kept. It clears when you close it.')),
                    RadioListTile<String>(
                        key: Key('reflectionSaved'),
                        value: 'saved',
                        title: Text('Save privately'),
                        subtitle: Text('Kept for you only. Never shown to anyone else, never exported.')),
                  ]),
                ),
                const Divider(),
                Text('How things are framed', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: _s.framing,
                  onChanged: (String? v) => v == null ? null : _set(_s.copyWith(framing: v)),
                  child: const Column(children: <Widget>[
                    RadioListTile<String>(key: Key('framingNeutral'), value: 'neutral', title: Text('Plain')),
                    RadioListTile<String>(
                        key: Key('framingCulture'),
                        value: 'culture-note',
                        title: Text('Add a culture note'),
                        subtitle: Text('Reminds you that what a style means can differ by family and culture.')),
                    RadioListTile<String>(
                        key: Key('framingValues'),
                        value: 'values-first',
                        title: Text('Start from my family’s values'),
                        subtitle: Text('Reads the cards as ideas to weigh against what matters to you.')),
                  ]),
                ),
                const Divider(),
                SwitchListTile(
                    key: const Key('toggleMessageCheck'),
                    value: _s.messageCheck,
                    onChanged: (bool v) => _set(_s.copyWith(messageCheck: v)),
                    title: const Text('Message check'),
                    subtitle: const Text('Offers hints before you send a message to the other guardian. Runs on this phone. Nothing is sent or saved.')),
                SwitchListTile(
                    key: const Key('toggleRulesList'),
                    value: _s.rulesList,
                    onChanged: (bool v) => _set(_s.copyWith(rulesList: v)),
                    title: const Text('Rules that match'),
                    subtitle: const Text('A short list of core routines you can choose to share with the other guardian. Turning it off clears your list.')),
              ]),
            ),
    );
  }
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Two sliders and a mirror. Describes the day, never the person.
class ReflectionScreen extends StatefulWidget {
  const ReflectionScreen({super.key, required this.principal, required this.store, this.clock = DateTime.now});
  final LearnPrincipal principal;
  final LearnStore store;
  final DateTime Function() clock;
  @override
  State<ReflectionScreen> createState() => _ReflectionState();
}

/// Spoken value for a reflection slider: words, never the 0-100 number.
String _lessMore(double v) => v < 34 ? 'less' : (v > 66 ? 'more' : 'in the middle');

/// The ends of a reflection slider, in words. The sliders show no number.
class _LessMore extends StatelessWidget {
  const _LessMore();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
          Text('less', style: Theme.of(context).textTheme.bodySmall),
          Text('more', style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _ReflectionState extends State<ReflectionScreen> {
  double _w = 60;
  double _e = 65;
  LearnSettings _s = defaultLearnSettings;
  List<Reflection> _saved = <Reflection>[];
  bool _loaded = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    if (canReadLearn(widget.principal)) _load();
  }

  Future<void> _load() async {
    final LearnSettings s = await widget.store.loadSettings();
    final List<Reflection> r = mayStoreReflection(s) ? await widget.store.reflections() : <Reflection>[];
    if (mounted) setState(() { _s = s; _saved = r; _loaded = true; });
  }

  Future<void> _save() async {
    await widget.store.saveReflection(
        Reflection(day: _dayKey(widget.clock()), warmth: _w.round(), expectations: _e.round()));
    final List<Reflection> r = await widget.store.reflections();
    if (mounted) setState(() { _saved = r; _note = 'Saved for you.'; });
  }

  @override
  Widget build(BuildContext context) {
    if (!canReadLearn(widget.principal)) return const _GuardiansOnly();
    final DayMirror m = describeDay(_w, _e);
    return Scaffold(
      appBar: AppBar(title: const Text('Where was today?')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  const Text('Two sliders. No grade. Just a mirror.'),
                  const SizedBox(height: AppSpacing.md),
                  Text('Warmth', style: Theme.of(context).textTheme.labelLarge),
                  Slider(
                      key: const Key('sliderWarmth'),
                      value: _w,
                      min: 0,
                      max: 100,
                      semanticFormatterCallback: _lessMore,
                      onChanged: (double v) => setState(() { _w = v; _note = null; })),
                  const _LessMore(),
                  Text('Expectations', style: Theme.of(context).textTheme.labelLarge),
                  Slider(
                      key: const Key('sliderExpectations'),
                      value: _e,
                      min: 0,
                      max: 100,
                      semanticFormatterCallback: _lessMore,
                      onChanged: (double v) => setState(() { _e = v; _note = null; })),
                  const _LessMore(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(m.headline, key: const Key('mirrorHeadline'), style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.xs),
                        Text(m.prompt, key: const Key('mirrorPrompt')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (mayStoreReflection(_s)) ...<Widget>[
                    FilledButton(key: const Key('reflectionSave'), onPressed: _save, child: const Text('Save privately')),
                    if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!)),
                    const SizedBox(height: AppSpacing.md),
                    for (final Reflection r in _saved)
                      ListTile(
                        key: Key('saved_${r.day}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.day),
                        subtitle: Text(describeDay(r.warmth, r.expectations).headline),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await widget.store.deleteReflection(r.day);
                            await _load();
                          },
                        ),
                      ),
                  ] else
                    const Text('Private. Cleared when you close this. Not shared with anyone.',
                        key: Key('reflectionSessionNote')),
                ]),
              ),
            ),
    );
  }
}

/// Hints before a message to the other guardian. A mirror, not a monitor:
/// the text lives only in this widget and is gone when it closes.
class MessageCheckScreen extends StatefulWidget {
  const MessageCheckScreen({super.key, required this.principal, required this.settings});
  final LearnPrincipal principal;
  final LearnSettings settings;
  @override
  State<MessageCheckScreen> createState() => _MessageCheckState();
}

class _MessageCheckState extends State<MessageCheckScreen> {
  final TextEditingController _c = TextEditingController();
  List<MessageHint>? _hints;

  @override
  void dispose() {
    _c.clear();
    _c.dispose();
    super.dispose();
  }

  void _check() => setState(() => _hints = checkMessage(widget.principal, widget.settings, _c.text));

  @override
  Widget build(BuildContext context) {
    if (!canReadLearn(widget.principal)) return const _GuardiansOnly();
    if (!widget.settings.messageCheck) {
      return Scaffold(
          appBar: AppBar(title: const Text('Check before you send')),
          body: const Center(child: Text('Turn on the message check in Your choices to use this.', key: Key('messageCheckOff'))));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Check before you send')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('A mirror, not a monitor. Runs on this phone. Nothing is sent, saved or shared. Closing this clears it.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
                key: const Key('messageDraft'),
                controller: _c,
                minLines: 3,
                maxLines: 8,
                maxLength: maxCheckChars,
                decoration: const InputDecoration(labelText: 'Your draft', border: OutlineInputBorder())),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(key: const Key('messageCheckRun'), onPressed: _check, child: const Text('Check')),
            const SizedBox(height: AppSpacing.md),
            if (_hints != null && _hints!.isEmpty)
              const Text('Nothing to flag. Brief, clear and friendly is a good place to be.', key: Key('messageClear')),
            if (_hints != null)
              for (final MessageHint h in _hints!)
                Card(
                  key: Key('hint_${h.flag}'),
                  child: ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(h.hint)),
                ),
            if (_hints != null && _hints!.isNotEmpty)
              const Text('These are suggestions. The words are yours to change.'),
          ]),
        ),
      ),
    );
  }
}

String _categoryLabel(String c) => c[0].toUpperCase() + c.substring(1);

/// The optional two-home rules list: your own short list, plus the other guardian's, read-only.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.principal, required this.store});
  final LearnPrincipal principal;
  final LearnStore store;
  @override
  State<RulesScreen> createState() => _RulesState();
}

class _RulesState extends State<RulesScreen> {
  List<RuleItem> _mine = <RuleItem>[];
  List<OtherGuardianRules> _others = <OtherGuardianRules>[];
  LearnSettings _s = defaultLearnSettings;
  bool _loaded = false;
  String _category = ruleCategories.first;
  final TextEditingController _text = TextEditingController();
  String? _note;
  bool _shareConfirmed = false;

  @override
  void initState() {
    super.initState();
    if (canReadLearn(widget.principal)) _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final LearnSettings s = await widget.store.loadSettings();
    final List<RuleItem> mine = s.rulesList ? await widget.store.myRules() : <RuleItem>[];
    final List<OtherGuardianRules> others = await widget.store.othersRules();
    if (mounted) setState(() { _s = s; _mine = mine; _others = others; _loaded = true; });
  }

  Future<void> _commit(List<RuleItem> next) async {
    await widget.store.setMyRules(next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!canReadLearn(widget.principal)) return const _GuardiansOnly();
    return Scaffold(
      appBar: AppBar(title: const Text('Rules that match')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : !_s.rulesList
              ? const Center(child: Text('Turn on “Rules that match” in Your choices to use this.', key: Key('rulesOff')))
              : SafeArea(
                  child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
                    const Text('Optional. You edit your own list. Nothing is compared for you. Only these four kinds of rule can be shared, never a style or a reflection.'),
                    const SizedBox(height: AppSpacing.md),
                    Text('Your list', style: Theme.of(context).textTheme.titleSmall),
                    if (_mine.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing yet.', key: Key('rulesEmpty'))),
                    for (int i = 0; i < _mine.length; i++)
                      ListTile(
                        key: Key('myRule_$i'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(_mine[i].text),
                        subtitle: Text(_categoryLabel(_mine[i].category)),
                        trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () => _commit(<RuleItem>[
                                  for (int j = 0; j < _mine.length; j++)
                                    if (j != i) _mine[j]
                                ])),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(spacing: 8, children: <Widget>[
                      for (final String c in ruleCategories)
                        ChoiceChip(
                            key: Key('ruleCat_$c'),
                            label: Text(_categoryLabel(c)),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c)),
                    ]),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                        key: const Key('ruleText'),
                        controller: _text,
                        maxLength: 200,
                        decoration: const InputDecoration(labelText: 'A rule at your house', border: OutlineInputBorder())),
                    FilledButton(
                        key: const Key('ruleAdd'),
                        onPressed: () async {
                          final String t = _text.text.trim();
                          if (t.isEmpty) return;
                          // One-time confirmation before anything is first shared
                          // (asked again only if the shared list was emptied).
                          if (_mine.isEmpty && !_shareConfirmed) {
                            final bool? ok = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext ctx) => AlertDialog(
                                      key: const Key('shareConfirmDialog'),
                                      title: const Text('Share this rule?'),
                                      content: const Text(
                                          'Rules you add here are shared with the other guardian. Your reflections and choices stay on this phone.'),
                                      actions: <Widget>[
                                        TextButton(
                                            key: const Key('shareConfirmNo'),
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('Not now')),
                                        FilledButton(
                                            key: const Key('shareConfirmYes'),
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('Share')),
                                      ],
                                    ));
                            if (ok != true) return;
                            _shareConfirmed = true;
                          }
                          _text.clear();
                          await _commit(<RuleItem>[..._mine, RuleItem(_category, t)]);
                          if (mounted) setState(() => _note = 'Added. The other guardian can now see it.');
                        },
                        child: const Text('Add and share')),
                    if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!)),
                    const Divider(height: AppSpacing.xxl),
                    Text('The other guardian’s list', style: Theme.of(context).textTheme.titleSmall),
                    if (_others.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('They have not shared a list.', key: Key('othersEmpty'))),
                    for (final OtherGuardianRules o in _others) ...<Widget>[
                      Text(o.guardianName, style: Theme.of(context).textTheme.labelLarge),
                      for (final RuleItem r in o.rules)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(r.text),
                            subtitle: Text(_categoryLabel(r.category))),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const Text('Differences are fine when it is calm. Low conflict matters more than matching.'),
                  ]),
                ),
    );
  }
}
