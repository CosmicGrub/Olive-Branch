// OLIVE BRANCH — the adult screens for welcoming a new grown-up into the village: who they are, how much they can
// do, the request, and the answer. UNVERIFIED on a device; headless widget tests only.
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3, 4.2, 5.2 and 12 (screens 1 to 5). Adult words only: a
// child never reaches any of these (they sit behind the adult gate, and no child file imports this one).
//
// NOT WIRED. The guardian shell does not open these yet: the family ledger is not wired into pairing, so there is no
// family for them to read. The Adults and helpers screen shows a "Welcome someone" row only when a host passes
// `onWelcome`; nothing does today, so the existing "Invite a co-parent (preview)" row is unchanged. The hosts for the
// meet (an in-person introduction that gives the new person's phone), the settle-in cards, the "Welcome with limits"
// summary, the limits agreement, pause and end screens, and the "Who must agree" settings are not built.
//
// WORDS. No "blocked", "refused", "denied", "controlling"; no "opened" or "seen" (the asker never learns whether a
// request was looked at); no counts of how often someone answered. "Not this time" is the no.
import 'package:flutter/material.dart';

import 'family_ledger.dart' show FamilyPolicy;
import 'family_profiles.dart';
import 'ui/olive_ui.dart';
import 'welcome_logic.dart';

/// Asks for the grown-up's PIN (the existing adult gate) and says whether it was right. Every yes, every request and
/// every cancel goes through it first: a child on an unlocked phone still cannot answer.
typedef ConfirmPin = Future<bool> Function();

/// A child the person may be around, for the "which children" choice.
class WelcomeChild {
  const WelcomeChild(this.id, this.name);
  final String id, name;
}

/// What the profile screen hands back: the name and the chosen limits. The host then runs the in-person meet and
/// calls [WelcomeService.propose] (not built yet).
class WelcomeChoices {
  const WelcomeChoices(this.personName, this.profile);
  final String personName;
  final MemberProfile profile;
}

String _shortDate(int ms) => dateWords(ms);

// ---------------------------------------------------------------------------------------------------------------
// 1. Who is it?
// ---------------------------------------------------------------------------------------------------------------

class WelcomeWhoScreen extends StatelessWidget {
  const WelcomeWhoScreen({
    super.key,
    required this.childName,
    required this.onParent,
    required this.onCarer,
    required this.onHelper,
  });
  final String childName;
  final VoidCallback onParent, onCarer, onHelper;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome someone')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('Who is it?', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Nobody is in until the right grown-ups have said yes to exactly what they are being given. '
                'They start small, and you can change that later.',
                style: t.bodyMedium),
            const SizedBox(height: 12),
            OliveCard(
              child: Column(children: <Widget>[
                OliveRow(
                  key: const Key('welcomeWhoParent'),
                  icon: OliveIcons.users,
                  title: 'Another parent',
                  sub: 'Mom, Dad, or a step-parent who will share the say. Every parent has to agree.',
                  onTap: onParent,
                ),
                OliveRow(
                  key: const Key('welcomeWhoCarer'),
                  icon: OliveIcons.user,
                  title: 'A carer',
                  sub: 'A grandparent, an aunt or uncle, a regular sitter or a childminder who helps with $childName.',
                  onTap: onCarer,
                ),
                OliveRow(
                  key: const Key('welcomeWhoHelper'),
                  icon: OliveIcons.file,
                  title: 'A helper (no app needed)',
                  sub: 'A neighbour or a school pickup person. You hold up a page on your screen. No vote needed.',
                  onTap: onHelper,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// 2. How much can they do?
// ---------------------------------------------------------------------------------------------------------------

class WelcomeProfileScreen extends StatefulWidget {
  const WelcomeProfileScreen({
    super.key,
    required this.childName,
    required this.parentTier,
    required this.policy,
    required this.parentCount,
    required this.children,
    required this.nowMs,
    required this.confirmPin,
    required this.onChosen,
  });
  final String childName;

  /// True for "Another parent", false for "A carer".
  final bool parentTier;
  final FamilyPolicy policy;
  final int parentCount;
  final List<WelcomeChild> children;
  final int Function() nowMs;
  final ConfirmPin confirmPin;
  final Future<void> Function(WelcomeChoices) onChosen;

  @override
  State<WelcomeProfileScreen> createState() => _WelcomeProfileScreenState();
}

class _WelcomeProfileScreenState extends State<WelcomeProfileScreen> {
  final TextEditingController _name = TextEditingController();
  late Preset _preset = widget.parentTier ? Preset.parent : Preset.trustedCarer;
  late Set<Capability> _caps = MemberProfile.defaults(_preset).caps.toSet();
  bool _allChildren = true;
  final Set<String> _kids = <String>{};
  int _days = 0; // 0 = ongoing
  int _visitDays = 3;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Preset> get _presets => widget.parentTier
      ? const <Preset>[Preset.parent, Preset.parentWithLimits]
      : const <Preset>[Preset.trustedCarer, Preset.visit, Preset.viewOnly];

  void _pick(Preset p) => setState(() {
        _preset = p;
        _caps = MemberProfile.defaults(p).caps.toSet();
        _message = null;
      });

  MemberProfile _profile() {
    final int now = widget.nowMs();
    int? from, until;
    if (_preset == Preset.visit) {
      from = now;
      until = now + _visitDays * kMsPerDay;
    } else if (_days > 0 && _preset != Preset.parent) {
      from = now;
      until = now + _days * kMsPerDay;
    }
    return MemberProfile(
      preset: _preset,
      caps: _caps,
      children: _preset == Preset.parent || _allChildren ? null : (_kids.toList()..sort()),
      fromMs: from,
      untilMs: until,
    );
  }

  Future<void> _send() async {
    final MemberProfile p = _profile();
    final String name = cleanName(_name.text);
    if (name.isEmpty) {
      setState(() => _message = 'Please type the person’s name.');
      return;
    }
    final String? why = p.violation();
    if (why != null) {
      setState(() => _message = 'Those choices do not fit together yet. Please check the list.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.confirmPin()) {
        if (mounted) setState(() => _message = 'That PIN did not match, so nothing was sent.');
        return;
      }
      await widget.onChosen(WelcomeChoices(name, p));
    } on WelcomeRefused catch (r) {
      if (mounted) setState(() => _message = r.words);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final MemberProfile p = _profile();
    final ApprovalNeed need = approvalNeed(profile: p, policy: widget.policy, parentCount: widget.parentCount);
    final Map<Capability, Cell> row = kProfileTable[_preset]!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.parentTier ? 'Welcome another parent' : 'Welcome a carer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            OliveFormField(key: const Key('welcomeName'), label: 'Their name', controller: _name, required: true),
            const SizedBox(height: 16),
            Text('How much can they do?', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: Column(children: <Widget>[
                for (final Preset x in _presets)
                  RadioRow(
                    key: Key('welcomePreset_${x.name}'),
                    title: presetTitle(x),
                    sub: presetBlurb(x, widget.childName),
                    selected: _preset == x,
                    onSelected: () => _pick(x),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(reachLine(p.reach), key: const Key('welcomeReach'), style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: Column(children: <Widget>[
                for (final Capability c in Capability.values)
                  if (row[c]!.available) _capRow(c, row[c]!),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Which children', style: t.titleSmall),
            const SizedBox(height: 6),
            if (_preset == Preset.parent)
              Text('A parent is around all the children.', style: t.bodyMedium)
            else
              OliveCard(
                child: Column(children: <Widget>[
                  ToggleRow(
                    key: const Key('welcomeAllChildren'),
                    title: 'All the children',
                    value: _allChildren,
                    onChanged: (bool v) => setState(() => _allChildren = v),
                  ),
                  if (!_allChildren)
                    for (final WelcomeChild k in widget.children)
                      CheckRow(
                        key: Key('welcomeChild_${k.id}'),
                        title: k.name,
                        value: _kids.contains(k.id),
                        onChanged: (bool v) => setState(() => v ? _kids.add(k.id) : _kids.remove(k.id)),
                      ),
                ]),
              ),
            const SizedBox(height: 16),
            Text('For how long?', style: t.titleSmall),
            const SizedBox(height: 6),
            _timeBox(),
            const SizedBox(height: 16),
            Text('Who has to agree', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                for (final String s in need.sentences(newParent: widget.parentTier))
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(s, style: t.bodyMedium)),
              ]),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('welcomeMessage'), style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('welcomeSend'),
              onPressed: _busy ? null : _send,
              child: const Text('Send the request'),
            ),
            const SizedBox(height: 6),
            Text(
                'Once it is sent it cannot be changed. To change it, cancel and send a new one.',
                style: t.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _capRow(Capability c, Cell cell) {
    final String words = capabilityWords(c, widget.childName);
    if (cell.fixed) {
      return OliveRow(
        key: Key('welcomeCap_${c.number}'),
        title: words,
        sub: cell.on ? 'Always included' : 'Not available for this kind of person',
        icon: cell.on ? OliveIcons.check : OliveIcons.lock,
      );
    }
    return ToggleRow(
      key: Key('welcomeCap_${c.number}'),
      title: words,
      value: _caps.contains(c),
      onChanged: (bool v) => setState(() {
        v ? _caps.add(c) : _caps.remove(c);
        _message = null;
      }),
    );
  }

  Widget _timeBox() {
    if (_preset == Preset.parent) {
      return Text('Ongoing.', style: Theme.of(context).textTheme.bodyMedium);
    }
    if (_preset == Preset.visit) {
      return OliveCard(
        child: Column(children: <Widget>[
          for (final int d in const <int>[1, 3, 7, 14])
            RadioRow(
              key: Key('welcomeVisit_$d'),
              title: d == 1 ? 'For 1 day' : 'For $d days',
              sub: d == 3 ? 'Counted from when you send it' : null,
              selected: _visitDays == d,
              onSelected: () => setState(() => _visitDays = d),
            ),
        ]),
      );
    }
    return OliveCard(
      child: Column(children: <Widget>[
        for (final int d in const <int>[0, 7, 30, 90])
          RadioRow(
            key: Key('welcomeDays_$d'),
            title: d == 0 ? 'Ongoing' : 'For ${daysWords(d * kMsPerDay)}',
            selected: _days == d,
            onSelected: () => setState(() => _days = d),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// 3. Waiting for others, and the list
// ---------------------------------------------------------------------------------------------------------------

class WelcomeCentreScreen extends StatefulWidget {
  const WelcomeCentreScreen({
    super.key,
    required this.service,
    required this.childName,
    required this.confirmPin,
    required this.onWelcomeSomeone,
    required this.onOpenRequest,
  });
  final WelcomeService service;
  final String childName;
  final ConfirmPin confirmPin;
  final VoidCallback onWelcomeSomeone;
  final void Function(WelcomeRequest) onOpenRequest;

  @override
  State<WelcomeCentreScreen> createState() => _WelcomeCentreScreenState();
}

class _WelcomeCentreScreenState extends State<WelcomeCentreScreen> {
  WelcomeOverview? _o;
  Set<String> _putOff = <String>{};
  List<WelcomeRequest> _due = <WelcomeRequest>[];
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final WelcomeOverview o = await widget.service.overview();
    final Set<String> off = <String>{};
    for (final WelcomeRequest r in o.forMe) {
      if (await widget.service.isPutOff(r.hashHex)) off.add(r.hashHex);
    }
    final List<WelcomeRequest> due = await widget.service.remindersDue();
    if (!mounted) return;
    setState(() {
      _o = o;
      _putOff = off;
      _due = due;
    });
    for (final WelcomeRequest r in due) {
      await widget.service.reminderShown(r.hashHex);
    }
  }

  Future<void> _cancel(WelcomeRequest r) async {
    if (!await widget.confirmPin()) {
      setState(() => _message = 'That PIN did not match, so nothing changed.');
      return;
    }
    try {
      await widget.service.cancel(r);
      _message = null;
    } on WelcomeRefused catch (x) {
      _message = x.words;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final WelcomeOverview? o = _o;
    final List<WelcomeRequest> now = o == null ? <WelcomeRequest>[] : <WelcomeRequest>[for (final WelcomeRequest r in o.forMe) if (!_putOff.contains(r.hashHex)) r];
    final List<WelcomeRequest> later = o == null ? <WelcomeRequest>[] : <WelcomeRequest>[for (final WelcomeRequest r in o.forMe) if (_putOff.contains(r.hashHex)) r];
    final List<WelcomeRequest> waiting = o == null ? <WelcomeRequest>[] : <WelcomeRequest>[for (final WelcomeRequest r in o.sent) if (r.open) r, ...o.others];
    final List<WelcomeRequest> past = o == null ? <WelcomeRequest>[] : <WelcomeRequest>[for (final WelcomeRequest r in o.sent) if (!r.open) r];
    return Scaffold(
      appBar: AppBar(title: const Text('Your village')),
      body: SafeArea(
        child: o == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  FilledButton(
                    key: const Key('welcomeStart'),
                    onPressed: widget.onWelcomeSomeone,
                    child: const Text('Welcome someone'),
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(_message!, key: const Key('welcomeCentreMessage'), style: t.bodyMedium),
                  ],
                  if (_due.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text('A request you put off is still waiting for you.', key: const Key('welcomeReminder'), style: t.bodyMedium),
                  ],
                  if (now.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('Waiting for your answer', style: t.titleSmall),
                    const SizedBox(height: 6),
                    OliveCard(child: Column(children: <Widget>[for (final WelcomeRequest r in now) _askRow(r, 'welcomeAsk')])),
                  ],
                  if (later.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('Put off for later', style: t.titleSmall),
                    const SizedBox(height: 6),
                    OliveCard(child: Column(children: <Widget>[for (final WelcomeRequest r in later) _askRow(r, 'welcomeLaterRow')])),
                  ],
                  const SizedBox(height: 16),
                  Text('Waiting for others', style: t.titleSmall),
                  const SizedBox(height: 6),
                  if (waiting.isEmpty)
                    const EmptyState(key: Key('welcomeNone'), title: 'Nothing is waiting', sub: 'Requests you send show here until everyone has answered.')
                  else
                    OliveCard(child: Column(children: <Widget>[for (final WelcomeRequest r in waiting) _waitingRow(r)])),
                  if (past.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('Finished', style: t.titleSmall),
                    const SizedBox(height: 6),
                    OliveCard(
                      child: Column(children: <Widget>[
                        for (final WelcomeRequest r in past)
                          OliveRow(
                            key: Key('welcomePast_${r.hashHex.substring(0, 8)}'),
                            icon: OliveIcons.user,
                            title: r.personName,
                            sub: r.status == 'welcomed'
                                ? 'Welcomed'
                                : (r.status == 'lapsed' ? 'Ended without an answer' : 'Not set up this time'),
                          ),
                      ]),
                    ),
                  ],
                  if (o.history.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('What has happened', style: t.titleSmall),
                    const SizedBox(height: 6),
                    OliveCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        for (int i = 0; i < o.history.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(o.history[i], key: Key('welcomeHistory_$i'), style: t.bodyMedium),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
      ),
    );
  }

  Widget _askRow(WelcomeRequest r, String keyBase) => OliveRow(
        key: Key('${keyBase}_${r.hashHex.substring(0, 8)}'),
        icon: OliveIcons.user,
        title: '${r.askerName} would like to welcome ${r.personName}',
        sub: '${presetTitle(r.profile.preset)}. ${reachLine(r.profile.reach)}.',
        onTap: () => widget.onOpenRequest(r),
      );

  Widget _waitingRow(WelcomeRequest r) {
    final String who = <String>[for (final ElectorStatus e in r.electors) e.words].join('. ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      OliveRow(
        key: Key('welcomeWait_${r.hashHex.substring(0, 8)}'),
        icon: OliveIcons.user,
        title: r.personName,
        sub: '${profileLine(r.profile)}. $who. Ends on ${_shortDate(r.expMs)} if nobody has answered.',
      ),
      if (r.mine)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: Key('welcomeCancel_${r.hashHex.substring(0, 8)}'),
            onPressed: () => _cancel(r),
            child: const Text('Cancel this request'),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// 4. The request
// ---------------------------------------------------------------------------------------------------------------

class WelcomeRequestScreen extends StatefulWidget {
  const WelcomeRequestScreen({
    super.key,
    required this.service,
    required this.request,
    required this.childName,
    required this.confirmPin,
    required this.onDone,
  });
  final WelcomeService service;
  final WelcomeRequest request;
  final String childName;
  final ConfirmPin confirmPin;

  /// Called after an answer is recorded (yes, not this time, later, or smaller) so the host can go back.
  final void Function(WelcomeAnswer) onDone;

  @override
  State<WelcomeRequestScreen> createState() => _WelcomeRequestScreenState();
}

class _WelcomeRequestScreenState extends State<WelcomeRequestScreen> {
  String? _message;
  bool _busy = false;
  bool _choosingSmaller = false;

  Future<void> _run(Future<void> Function() body, WelcomeAnswer a, {bool needPin = true}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (needPin && !await widget.confirmPin()) {
        if (mounted) setState(() => _message = 'That PIN did not match, so nothing was sent.');
        return;
      }
      await body();
      if (mounted) widget.onDone(a);
    } on WelcomeRefused catch (r) {
      if (mounted) setState(() => _message = r.words);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final WelcomeRequest r = widget.request;
    final String hash = r.hashHex;
    final List<ChecklistLine> list = checklistFor(r.profile, widget.childName);
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome request')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(r.sentence(widget.childName), key: const Key('welcomeRequestSentence'), style: t.titleMedium),
            const SizedBox(height: 12),
            KeyValueList(<(String, String)>[
              ('Who', r.personName),
              ('As', presetTitle(r.profile.preset)),
              ('What they can do', reachLine(r.profile.reach)),
              ('Children', r.profile.children == null ? 'All the children' : (r.profile.children!.length == 1 ? 'One child' : 'Chosen children')),
              ('For how long', timeBoxWords(r.profile)),
              ('Ends if nobody answers', _shortDate(r.expMs)),
            ]),
            const SizedBox(height: 12),
            Text('The list', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: Column(children: <Widget>[
                for (int i = 0; i < list.length; i++)
                  OliveRow(
                    key: Key('welcomeLine_$i'),
                    title: list[i].words,
                    sub: list[i].on ? 'Yes' : 'No',
                    icon: list[i].on ? OliveIcons.check : OliveIcons.lock,
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Text('Where it stands', style: t.titleSmall),
            const SizedBox(height: 6),
            OliveCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                for (final ElectorStatus e in r.electors)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(e.words, style: t.bodyMedium)),
              ]),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('welcomeRequestMessage'), style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (!r.needsMyAnswer)
              Text(
                  r.settling
                      ? 'This phone is still settling in. You can answer once that ends.'
                      : (r.myAnswer == null ? 'You are not asked about this one.' : 'You have answered.'),
                  key: const Key('welcomeNoAnswerNeeded'),
                  style: t.bodyMedium)
            else if (_choosingSmaller)
              ..._smallerList(r)
            else ...<Widget>[
              FilledButton(
                key: const Key('welcomeYes'),
                onPressed: _busy ? null : () => _run(() => widget.service.answer(hash, WelcomeAnswer.yes), WelcomeAnswer.yes),
                child: const Text('Yes'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('welcomeNo'),
                onPressed: _busy ? null : () => _run(() => widget.service.answer(hash, WelcomeAnswer.no), WelcomeAnswer.no),
                child: const Text('Not this time'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('welcomeLater'),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await widget.service.askLater(hash);
                        }, WelcomeAnswer.later, needPin: false),
                child: const Text('Ask me later'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('welcomeSmaller'),
                onPressed: _busy ? null : () => setState(() => _choosingSmaller = true),
                child: const Text('Yes to something smaller'),
              ),
              const SizedBox(height: 6),
              Text(
                  'No answer is not a yes. “Ask me later” keeps this here and tells nobody.',
                  style: t.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }

  List<Widget> _smallerList(WelcomeRequest r) {
    final List<MapEntry<String, MemberProfile>> choices = smallerChoices(r.profile, widget.service.nowMs());
    return <Widget>[
      Text('Say yes to something smaller. ${r.askerName} will be asked to agree to it, and this request will end.',
          style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 8),
      if (choices.isEmpty)
        const Text('There is nothing smaller to offer here. You can say not this time.', key: Key('welcomeNothingSmaller')),
      for (int i = 0; i < choices.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            key: Key('welcomeSmallerChoice_$i'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.service.yesToSmaller(r.hashHex, choices[i].value);
                    }, WelcomeAnswer.smaller),
            child: Text(choices[i].key),
          ),
        ),
      TextButton(
        key: const Key('welcomeSmallerBack'),
        onPressed: () => setState(() => _choosingSmaller = false),
        child: const Text('Back'),
      ),
    ];
  }
}
