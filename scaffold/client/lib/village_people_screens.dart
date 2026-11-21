// OLIVE BRANCH — the screens for the people already in the village: who is here, pausing someone, ending a place (together,
// or with a 14 day notice), the limits agreement (with its think-over) and the Standing OK. UNVERIFIED on a device; headless
// widget tests in CI (client/test/village_people_screens_test.dart). Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections
// 4.4, 4.5, 6.2 and 12 (screens 6, 10, 11, 12) and the owner's co-parent rules (see village_people.dart).
//
// ADULT WORDS ONLY, GROWN-UPS ONLY. Reached from "Your village" (village_welcome_flow.dart), which sits behind the Settings
// hub and its PIN; every pause, end, notice, limit and yes asks for the PIN again. A child never reaches any of it and no
// child file imports this one (a test guards it). Words: "paused" and "ended", never "blocked", "refused" or "suspended";
// no counts of how often anyone answered; a person is never told who said no.
//
// WHAT IS NOT HERE. A tablet that refuses a paused phone, a carer's own "Not available right now" card beyond the one line
// on their Your village page, key changes after someone is ended, and a far-away meeting. See MASTERFILE 8.28.1.
import 'dart:async';

import 'package:flutter/material.dart';

import 'family_ledger_state.dart' show EndNotice;
import 'family_ledger.dart' show kApprovalLifetimeMs, kEndNoticeMs, kLimitableCapabilities, kStandingMaxMs;
import 'family_profiles.dart' show kMsPerDay;
import 'family_state.dart';
import 'ui/olive_ui.dart';
import 'village_people.dart';
import 'village_welcome_host.dart';
import 'welcome_logic.dart' show dateWords;

/// Opens "People in the village".
Future<void> openVillagePeople(BuildContext context, VillageServices services) => Navigator.of(context)
    .push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => VillagePeopleScreen(services: services)));

PeopleService _peopleFor(VillageServices s, FamilyContext c) =>
    PeopleService(context: c, repository: s.family, nowMs: s.now, childName: s.childName);

/// Asks, says the plain words, asks for the PIN, then does it. Shows the refusal in words if the rule would not.
Future<bool> _confirmAndDo(
  BuildContext context, {
  required VillageServices services,
  required String title,
  required String body,
  required String yesLabel,
  required Future<void> Function() run,
  required void Function(String) say,
}) async {
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      key: const Key('confirmDialog'),
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(key: const Key('confirmNo'), onPressed: () => Navigator.of(c).pop(false), child: const Text('Not now')),
        FilledButton(key: const Key('confirmYes'), onPressed: () => Navigator.of(c).pop(true), child: Text(yesLabel)),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  if (!await services.confirmPin(context)) {
    say('That PIN did not match, so nothing was changed.');
    return false;
  }
  try {
    await run();
    return true;
  } on PeopleRefused catch (e) {
    say(e.words);
    return false;
  } catch (_) {
    say('That could not be saved on this phone, so nothing was changed. Please try again.');
    return false;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The list
// ---------------------------------------------------------------------------------------------------------------

class VillagePeopleScreen extends StatefulWidget {
  const VillagePeopleScreen({super.key, required this.services});
  final VillageServices services;

  @override
  State<VillagePeopleScreen> createState() => _VillagePeopleScreenState();
}

class _VillagePeopleScreenState extends State<VillagePeopleScreen> {
  FamilyContext? _ctx;
  PeopleOverview? _o;
  bool _loading = true;

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final FamilyContext? ctx = await _s.load();
      final PeopleOverview? o = ctx == null ? null : await _peopleFor(_s, ctx).overview();
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _o = o;
        _loading = false;
      });
    } on FamilyRecordUnusable {
      if (mounted) setState(() => _loading = false);
    }
  }

  PeopleService get _svc => _peopleFor(_s, _ctx!);

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => screen));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('People in the village')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _body(t)),
      ),
    );
  }

  Widget _body(TextTheme t) {
    final PeopleOverview? o = _o;
    if (o == null || o.people.isEmpty) {
      return Text('Nobody is here yet. Welcome someone from Your village.', key: const Key('peopleNone'), style: t.bodyMedium);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (o.notices.isNotEmpty) ...<Widget>[
        OliveCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Every parent sees these', style: t.titleSmall),
            const SizedBox(height: 6),
            for (int i = 0; i < o.notices.length; i++)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(o.notices[i], key: Key('peopleNotice_$i'), style: t.bodyMedium)),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (o.iAmPaused) ...<Widget>[
        Text('Your access is paused. You can still look, answer and leave. Another parent can resume it.',
            key: const Key('peopleIAmPaused'), style: t.bodyMedium),
        const SizedBox(height: 12),
      ],
      if (o.forMe.isNotEmpty) ...<Widget>[
        Text('Waiting for you', style: t.titleMedium),
        const SizedBox(height: 6),
        OliveCard(
          child: Column(children: <Widget>[
            for (final PendingAsk a in o.forMe)
              OliveRow(
                key: Key('ask_${a.hashHex.substring(0, 8)}'),
                icon: OliveIcons.bell,
                title: _askTitle(a),
                sub: _askSub(a),
                onTap: () => _open(PeopleAskScreen(services: _s, service: _svc, ask: a)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (o.waitingOnOthers.isNotEmpty) ...<Widget>[
        Text('Waiting for others', style: t.titleMedium),
        const SizedBox(height: 6),
        OliveCard(
          child: Column(children: <Widget>[
            for (final PendingAsk a in o.waitingOnOthers)
              OliveRow(
                key: Key('mine_${a.hashHex.substring(0, 8)}'),
                icon: OliveIcons.clock,
                title: _askTitle(a),
                sub: 'Waiting for an answer. It ends on ${dateWords(a.expMs)} if nobody answers.',
                onTap: () => _open(PeopleAskScreen(services: _s, service: _svc, ask: a)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      Text('Who is here', style: t.titleMedium),
      const SizedBox(height: 6),
      OliveCard(
        child: Column(children: <Widget>[
          for (final PersonCard p in o.people)
            OliveRow(
              key: Key('person_${p.gidHex}'),
              icon: p.isParent ? OliveIcons.users : OliveIcons.user,
              title: p.isMe ? '${p.name} (you)' : p.name,
              sub: _personSub(p),
              onTap: () => _open(VillagePersonScreen(services: _s, service: _svc, person: p)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      OliveCard(
        child: OliveRow(
          key: const Key('peopleMine'),
          icon: OliveIcons.sliders,
          title: 'Your own limits and advance yes',
          sub: 'Limit what you do, ask for fewer limits, or say yes in advance to look-only requests.',
          onTap: () => _open(VillageMineScreen(services: _s, service: _svc)),
        ),
      ),
    ]);
  }

  String _personSub(PersonCard p) {
    final List<String> bits = <String>[p.line];
    if (p.paused) bits.add('paused by ${p.pausedBy}');
    final EndNotice? n = p.notice;
    if (n != null) bits.add('notice: ends ${dateWords(n.effMs)}');
    if (p.limits.isNotEmpty) bits.add('has agreed limits');
    return bits.join('. ');
  }

  String _askTitle(PendingAsk a) {
    switch (a.kind) {
      case 'limits':
        return a.mine ? 'Limits you suggested for ${a.subjectName}' : '${a.askerName} suggests limits for you';
      case 'loosen':
        return a.mine ? 'Your request for fewer limits' : '${a.askerName} asks for fewer limits';
      case 'remove':
        return a.mine ? 'Ending ${a.subjectName}’s place together' : '${a.askerName} would like to end your place';
      default:
        return a.mine ? 'Ending ${a.subjectName}’s place' : '${a.askerName} would like to end ${a.subjectName}’s place';
    }
  }

  String _askSub(PendingAsk a) {
    if (a.kind == 'limits') return 'You can say no. Nothing changes if you do.';
    return 'Waiting for your answer. It ends on ${dateWords(a.expMs)} if nobody answers.';
  }
}

// ---------------------------------------------------------------------------------------------------------------
// One person
// ---------------------------------------------------------------------------------------------------------------

class VillagePersonScreen extends StatefulWidget {
  const VillagePersonScreen({super.key, required this.services, required this.service, required this.person});
  final VillageServices services;
  final PeopleService service;
  final PersonCard person;

  @override
  State<VillagePersonScreen> createState() => _VillagePersonScreenState();
}

class _VillagePersonScreenState extends State<VillagePersonScreen> {
  PersonCard? _p;
  PeopleOverview? _o;
  String _message = '';

  VillageServices get _s => widget.services;
  PeopleService get _svc => widget.service;
  PersonCard get p => _p ?? widget.person;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final PeopleOverview o = await _svc.overview();
    if (!mounted) return;
    setState(() {
      _o = o;
      _p = o.people.where((PersonCard x) => x.gidHex == widget.person.gidHex).firstOrNull;
    });
  }

  void _say(String m) {
    if (mounted) setState(() => _message = m);
  }

  Future<void> _do({required String title, required String body, required String yes, required Future<void> Function() run, String done = ''}) async {
    final bool ok = await _confirmAndDo(context, services: _s, title: title, body: body, yesLabel: yes, run: run, say: _say);
    if (ok) {
      _say(done);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final PersonCard c = p;
    final PeopleOverview? o = _o;
    final bool iAmParent = o != null && o.people.any((PersonCard x) => x.isMe && x.isParent);
    final String child = _s.childName;
    final List<Widget> actions = <Widget>[];
    if (iAmParent && !c.isMe) {
      if (c.paused) {
        actions.add(OliveRow(
          key: const Key('personResume'),
          icon: OliveIcons.check,
          title: 'Resume ${c.name}',
          sub: 'Gives back what was paused. Any parent except ${c.name} can do this.',
          onTap: () => _do(
            title: 'Resume ${c.name}?',
            body: '${c.name}’s access comes back, and every parent sees that it did.',
            yes: 'Resume',
            run: () => _svc.resume(c.gidHex),
            done: '${c.name}’s access is back.',
          ),
        ));
      } else {
        actions.add(OliveRow(
          key: const Key('personPause'),
          icon: OliveIcons.clock,
          title: 'Pause ${c.name}',
          sub: c.isParent
              ? 'Stops ${c.name} from starting anything, at once. ${c.name} can still see everything, answer requests and leave. Every parent sees it, and another parent can resume it.'
              : 'Stops ${c.name}’s access at once. Every parent sees it, and any other parent can resume it.',
          onTap: () => _do(
            title: 'Pause ${c.name}?',
            body: c.isParent
                ? 'This is not an ending. ${c.name} will see that it happened, and can still see everything, answer requests and leave.'
                : 'This is not an ending. Every parent will see that it happened, and you or any other parent can resume it.',
            yes: 'Pause',
            run: () => _svc.pause(c.gidHex),
            done: '${c.name} is paused.',
          ),
        ));
      }
      if (c.isParent) {
        actions.add(OliveRow(
          key: const Key('personEndTogether'),
          icon: OliveIcons.users,
          title: 'End ${c.name}’s place together',
          sub: '${c.name} has to agree on their own phone. Nothing changes unless they do.',
          onTap: () => _do(
            title: 'Ask ${c.name} to end their place?',
            body: 'This only happens if ${c.name} says yes on their own phone. If they say no, nothing changes.',
            yes: 'Ask',
            run: () => _svc.proposeEndTogether(c.gidHex),
            done: 'Asked. It ends on ${dateWords(_s.now() + kApprovalLifetimeMs)} if nobody answers.',
          ),
        ));
        actions.add(OliveRow(
          key: const Key('personLimits'),
          icon: OliveIcons.sliders,
          title: 'Suggest limits for ${c.name}',
          sub: '${c.name} has to say yes on their own phone, after a day to think it over. They are never limited without their own yes.',
          onTap: () async {
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
                builder: (BuildContext _) => LimitsProposeScreen(services: _s, service: _svc, person: c)));
            await _reload();
          },
        ));
      } else {
        actions.add(OliveRow(
          key: const Key('personEnd'),
          icon: OliveIcons.x,
          title: 'End ${c.name}’s place',
          sub: c.iWelcomedThem
              ? 'You welcomed ${c.name}, so this ends at once.'
              : 'The parent who welcomed ${c.name} has to say yes.',
          onTap: () => _do(
            title: 'End ${c.name}’s place?',
            body: c.iWelcomedThem
                ? '${c.name} will no longer be in $child’s village. They would need a new welcome to come back.'
                : 'The parent who welcomed ${c.name} is asked. If they say no, nothing changes. You can pause ${c.name} in the meantime.',
            yes: 'End',
            run: () async {
              final EndResult r = await _svc.endCarer(c.gidHex);
              _say(r == EndResult.ended ? '${c.name}’s place has ended.' : 'Asked the parent who welcomed ${c.name}.');
            },
          ),
        ));
      }
      final EndNotice? n = c.notice;
      if (n == null) {
        actions.add(OliveRow(
          key: const Key('personNotice'),
          icon: OliveIcons.bell,
          title: 'Give 14 days’ notice',
          sub: 'Every phone shows it. ${c.name}’s place ends on ${dateWords(_s.now() + kEndNoticeMs)} unless you take it back. ${c.name} cannot stop it, and can still see everything, answer requests and leave.',
          onTap: () => _do(
            title: 'Give ${c.name} 14 days’ notice?',
            body: 'Every parent’s phone, including ${c.name}’s, will show this for the whole wait. '
                'Nothing is taken away while it runs. You can take it back until ${dateWords(_s.now() + kEndNoticeMs)}. After that ${c.name}’s place in $child’s village ends.',
            yes: 'Give notice',
            run: () => _svc.giveNotice(c.gidHex),
            done: 'Notice given. It is shown on every phone.',
          ),
        ));
      } else if (n.byGidHex == _o?.people.where((PersonCard x) => x.isMe).firstOrNull?.gidHex) {
        actions.add(OliveRow(
          key: const Key('personTakeBack'),
          icon: OliveIcons.chevL,
          title: 'Take back my notice',
          sub: 'Until ${dateWords(n.effMs)}. Nothing changes if you do.',
          onTap: () => _do(
            title: 'Take back your notice?',
            body: '${c.name}’s place stays as it is.',
            yes: 'Take it back',
            run: () => _svc.cancelNotice(c.gidHex),
            done: 'Taken back.',
          ),
        ));
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(c.isMe ? '${c.name} (you)' : c.name, key: const Key('personName'), style: t.titleLarge),
            const SizedBox(height: 4),
            Text(c.line, key: const Key('personLine'), style: t.bodyMedium),
            if (c.welcomedBy != null) Text('Welcomed by ${c.welcomedBy}.', style: t.bodyMedium),
            if (c.paused) Text('Paused by ${c.pausedBy} on ${dateWords(c.pausedAtMs!)}.', key: const Key('personPaused'), style: t.bodyMedium),
            if (c.notice != null)
              Text('Notice: this place ends on ${dateWords(c.notice!.effMs)} unless it is taken back.', key: const Key('personNoticeLine'), style: t.bodyMedium),
            if (c.limits.isNotEmpty)
              Text('Agreed limits: ${<String>[for (final int l in c.limits) limitWords(l).toLowerCase()].join('; ')}.', key: const Key('personLimitsLine'), style: t.bodyMedium),
            if (c.settlingUntilMs != null)
              Text('Settling in until ${dateWords(c.settlingUntilMs!)}. Until then they cannot welcome anyone, answer requests or change anything.',
                  key: const Key('personSettling'), style: t.bodyMedium),
            if (_message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(_message, key: const Key('personMessage'), style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (actions.isNotEmpty) OliveCard(child: Column(children: actions)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Suggesting limits to another parent
// ---------------------------------------------------------------------------------------------------------------

class LimitsProposeScreen extends StatefulWidget {
  const LimitsProposeScreen({super.key, required this.services, required this.service, required this.person});
  final VillageServices services;
  final PeopleService service;
  final PersonCard person;

  @override
  State<LimitsProposeScreen> createState() => _LimitsProposeScreenState();
}

class _LimitsProposeScreenState extends State<LimitsProposeScreen> {
  final Set<int> _on = <int>{};
  String _message = '';
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String name = widget.person.name;
    return Scaffold(
      appBar: AppBar(title: Text('Limits for $name')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('You can suggest a short list. $name has to say yes on their own phone, after a day to think it over.', style: t.bodyMedium),
            const SizedBox(height: 8),
            Text(
                'Nothing changes before then, and nothing changes if they say no. $name will always be able to see everything, '
                'answer requests, pause someone who is not safe, and leave.',
                key: const Key('limitsReassure'), style: t.bodyMedium),
            const SizedBox(height: 12),
            OliveCard(
              child: Column(children: <Widget>[
                for (final int c in kLimitableCapabilities)
                  CheckboxListTile(
                    key: Key('limitCap_$c'),
                    value: _on.contains(c),
                    onChanged: _sent ? null : (bool? v) => setState(() => v == true ? _on.add(c) : _on.remove(c)),
                    title: Text(limitWords(c)),
                    subtitle: const Text('Switched off for them'),
                  ),
              ]),
            ),
            if (_message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(_message, key: const Key('limitsMessage'), style: t.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (_sent)
              OutlinedButton(key: const Key('limitsDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))
            else
              FilledButton(
                key: const Key('limitsSend'),
                onPressed: _on.isEmpty
                    ? null
                    : () async {
                        final bool ok = await _confirmAndDo(
                          context,
                          services: widget.services,
                          title: 'Send these limits to $name?',
                          body: 'Nothing changes unless $name says yes on their own phone, after a day.',
                          yesLabel: 'Send',
                          run: () => widget.service.proposeLimits(widget.person.gidHex, _on.toList()),
                          say: (String m) => setState(() => _message = m),
                        );
                        if (ok && mounted) {
                          setState(() {
                            _sent = true;
                            _message = 'Sent. $name can answer from tomorrow.';
                          });
                        }
                      },
                child: const Text('Send'),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Something waiting for an answer
// ---------------------------------------------------------------------------------------------------------------

class PeopleAskScreen extends StatefulWidget {
  const PeopleAskScreen({super.key, required this.services, required this.service, required this.ask});
  final VillageServices services;
  final PeopleService service;
  final PendingAsk ask;

  @override
  State<PeopleAskScreen> createState() => _PeopleAskScreenState();
}

class _PeopleAskScreenState extends State<PeopleAskScreen> {
  String _message = '';
  bool _done = false;

  VillageServices get _s => widget.services;
  PendingAsk get a => widget.ask;

  Future<void> _answer(bool yes) async {
    final bool ok = await _confirmAndDo(
      context,
      services: _s,
      title: yes ? 'Say yes?' : 'Say not this time?',
      body: yes ? 'This is your own yes, and it is final.' : 'Nothing changes.',
      yesLabel: yes ? 'Yes' : 'Not this time',
      run: () => widget.service.answer(a.hashHex, yes: yes),
      say: (String m) => setState(() => _message = m),
    );
    if (ok && mounted) {
      setState(() {
        _done = true;
        _message = yes ? 'Your yes is saved and goes to the other phones.' : 'Nothing changes.';
      });
    }
  }

  Future<void> _withdraw() async {
    final bool ok = await _confirmAndDo(
      context,
      services: _s,
      title: 'Take it back?',
      body: 'Nothing was changed by asking, and nothing changes now.',
      yesLabel: 'Take it back',
      run: () => widget.service.withdraw(a.hashHex),
      say: (String m) => setState(() => _message = m),
    );
    if (ok && mounted) {
      setState(() {
        _done = true;
        _message = 'Taken back.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool wait = _s.now() < a.answerFromMs;
    final String child = _s.childName;
    final List<Widget> body = <Widget>[];
    switch (a.kind) {
      case 'limits':
        if (a.mine) {
          body.add(Text('You suggested limits for ${a.subjectName}. They answer on their own phone, from ${dateWords(a.answerFromMs)}.', style: t.bodyMedium));
        } else {
          body.add(Text('${a.askerName} would like you to agree to these limits.', key: const Key('askSentence'), style: t.titleMedium));
          body.add(const SizedBox(height: 6));
          body.add(Text(
              'You can say no. Nothing changes if you do, and nothing changes before you say yes. '
              '${wait ? 'You can say yes from ${dateWords(a.answerFromMs)}, a day to think it over. ' : ''}'
              'You can say no at any moment. You will always be able to see everything, answer requests, pause someone who is not safe, and leave.',
              key: const Key('askNoPressure'), style: t.bodyMedium));
        }
        break;
      case 'loosen':
        body.add(Text(a.mine ? 'You asked for fewer limits.' : '${a.askerName} asks to have fewer limits.', key: const Key('askSentence'), style: t.titleMedium));
        break;
      case 'remove':
        body.add(Text(a.mine ? 'You asked to end ${a.subjectName}’s place together.' : '${a.askerName} would like to end your place in $child’s village.',
            key: const Key('askSentence'), style: t.titleMedium));
        body.add(const SizedBox(height: 6));
        body.add(Text(a.mine ? 'It only happens if they say yes.' : 'This only happens if you say yes. If you say no, nothing changes.', style: t.bodyMedium));
        break;
      default:
        body.add(Text(a.mine ? 'You asked to end ${a.subjectName}’s place.' : '${a.askerName} would like to end ${a.subjectName}’s place in $child’s village.',
            key: const Key('askSentence'), style: t.titleMedium));
        body.add(const SizedBox(height: 6));
        body.add(Text(a.mine ? 'It needs the yes of the parent who welcomed them.' : 'You welcomed ${a.subjectName}, so your yes is needed. If you say no, nothing changes.', style: t.bodyMedium));
    }
    if (a.limits.isNotEmpty) {
      body.add(const SizedBox(height: 12));
      body.add(OliveCard(
        child: Column(children: <Widget>[
          for (int i = 0; i < a.limits.length; i++)
            OliveRow(key: Key('askLimit_$i'), icon: OliveIcons.lock, title: limitWords(a.limits[i]), sub: 'Switched off'),
        ]),
      ));
    }
    if (_message.isNotEmpty) {
      body.add(const SizedBox(height: 12));
      body.add(Text(_message, key: const Key('askMessage'), style: t.bodyMedium));
    }
    body.add(const SizedBox(height: 16));
    if (_done) {
      body.add(OutlinedButton(key: const Key('askDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')));
    } else if (a.mine) {
      body.add(OutlinedButton(key: const Key('askWithdraw'), onPressed: _withdraw, child: const Text('Take it back')));
    } else {
      body.add(FilledButton(key: const Key('askYes'), onPressed: wait && a.kind == 'limits' ? null : () => _answer(true), child: const Text('Yes, I agree')));
      body.add(const SizedBox(height: 8));
      body.add(OutlinedButton(key: const Key('askNo'), onPressed: () => _answer(false), child: const Text('Not this time')));
      if (a.kind == 'limits') {
        body.add(const SizedBox(height: 8));
        body.add(TextButton(
          key: const Key('askTrust'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (BuildContext c) => AlertDialog(
              content: const Text('Talk it over with someone you trust before you decide. There is no hurry, and no answer is the same as nothing changing.'),
              actions: <Widget>[TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close'))],
            ),
          ),
          child: const Text('Ask someone I trust first'),
        ));
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('A request')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body))),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Your own limits and the Standing OK
// ---------------------------------------------------------------------------------------------------------------

class VillageMineScreen extends StatefulWidget {
  const VillageMineScreen({super.key, required this.services, required this.service});
  final VillageServices services;
  final PeopleService service;

  @override
  State<VillageMineScreen> createState() => _VillageMineScreenState();
}

class _VillageMineScreenState extends State<VillageMineScreen> {
  PeopleOverview? _o;
  final Set<int> _more = <int>{}, _keep = <int>{};
  int _days = 30;
  String _message = '';

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final PeopleOverview o = await widget.service.overview();
    if (!mounted) return;
    setState(() {
      _o = o;
      _keep
        ..clear()
        ..addAll(o.myLimits);
      _more.clear();
    });
  }

  Future<void> _do(String title, String body, String yes, Future<void> Function() run, String done) async {
    final bool ok = await _confirmAndDo(context, services: _s, title: title, body: body, yesLabel: yes, run: run, say: (String m) => setState(() => _message = m));
    if (ok) {
      setState(() => _message = done);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final PeopleOverview? o = _o;
    if (o == null) return Scaffold(appBar: AppBar(title: const Text('Your own limits')), body: const Center(child: CircularProgressIndicator()));
    final List<int> free = <int>[for (final int c in kLimitableCapabilities) if (!o.myLimits.contains(c)) c];
    return Scaffold(
      appBar: AppBar(title: const Text('Your own limits')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            if (_message.isNotEmpty) ...<Widget>[
              Text(_message, key: const Key('mineMessage'), style: t.bodyMedium),
              const SizedBox(height: 12),
            ],
            Text('Limits you have agreed to', style: t.titleMedium),
            const SizedBox(height: 6),
            if (o.myLimits.isEmpty)
              Text('None. You can limit yourself, or another parent can suggest limits, which only count if you say yes.', key: const Key('mineNoLimits'), style: t.bodyMedium)
            else
              OliveCard(
                child: Column(children: <Widget>[
                  for (final int c in o.myLimits) OliveRow(key: Key('mineLimit_$c'), icon: OliveIcons.lock, title: limitWords(c), sub: 'Switched off for you'),
                ]),
              ),
            if (free.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Limit yourself more', style: t.titleMedium),
              Text('Takes effect at once, and the other parents are told. To undo it you ask them.', style: t.bodySmall),
              OliveCard(
                child: Column(children: <Widget>[
                  for (final int c in free)
                    CheckboxListTile(
                      key: Key('mineAdd_$c'),
                      value: _more.contains(c),
                      onChanged: (bool? v) => setState(() => v == true ? _more.add(c) : _more.remove(c)),
                      title: Text(limitWords(c)),
                    ),
                ]),
              ),
              FilledButton(
                key: const Key('mineTighten'),
                onPressed: _more.isEmpty
                    ? null
                    : () => _do('Limit yourself?', 'This takes effect at once. To undo it, you ask the other parents.', 'Limit me',
                        () => widget.service.tightenMine(_more.toList()), 'Done. The other parents see it.'),
                child: const Text('Limit me'),
              ),
            ],
            if (o.myLimits.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Ask for fewer limits', style: t.titleMedium),
              Text('The other parents have to say yes. Untick what you would like back.', style: t.bodySmall),
              OliveCard(
                child: Column(children: <Widget>[
                  for (final int c in o.myLimits)
                    CheckboxListTile(
                      key: Key('mineKeep_$c'),
                      value: _keep.contains(c),
                      onChanged: (bool? v) => setState(() => v == true ? _keep.add(c) : _keep.remove(c)),
                      title: Text(limitWords(c)),
                    ),
                ]),
              ),
              FilledButton(
                key: const Key('mineLoosen'),
                onPressed: _keep.length >= o.myLimits.length
                    ? null
                    : () => _do('Ask for fewer limits?', 'The other parents are asked. Nothing changes unless they say yes.', 'Ask',
                        () => widget.service.askLoosen(_keep.toList()), 'Asked. It ends on ${dateWords(_s.now() + kApprovalLifetimeMs)} if nobody answers.'),
                child: const Text('Ask'),
              ),
            ],
            const SizedBox(height: 24),
            Text('Say yes in advance', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
                'While you are away, another parent can welcome someone who can only look, without waiting for your yes. '
                'It never covers a parent or anyone who can act. It ends by itself, and you can take it back at any time.',
                key: const Key('standingHelp'), style: t.bodyMedium),
            const SizedBox(height: 8),
            if (o.myStandingUntilMs != null) ...<Widget>[
              Text('Your yes in advance lasts until ${dateWords(o.myStandingUntilMs!)}.', key: const Key('standingOn'), style: t.bodyMedium),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('standingOff'),
                onPressed: () => _do('Take it back?', 'Look-only requests wait for your yes again.', 'Take it back', widget.service.takeBackStanding, 'Taken back.'),
                child: const Text('Take it back'),
              ),
            ] else ...<Widget>[
              SegmentedButton<int>(
                key: const Key('standingDays'),
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 7, label: Text('7 days')),
                  ButtonSegment<int>(value: 30, label: Text('30 days')),
                  ButtonSegment<int>(value: 90, label: Text('90 days')),
                ],
                selected: <int>{_days},
                onSelectionChanged: (Set<int> v) => setState(() => _days = v.first),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('standingGive'),
                onPressed: () => _do('Say yes in advance?',
                    'For $_days days, look-only requests from another parent do not wait for you. Every parent sees this.', 'Say yes in advance',
                    () => widget.service.standingOk(_days), 'Done. It lasts until ${dateWords(_s.now() + _days * kMsPerDay)}.'),
                child: const Text('Say yes in advance'),
              ),
              Text('At most ${kStandingMaxMs ~/ kMsPerDay} days.', style: t.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }
}
