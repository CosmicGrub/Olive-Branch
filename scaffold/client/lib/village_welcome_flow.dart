// OLIVE BRANCH — the screens that put the village welcome into the guardian app: "Your village" (reached from Settings,
// Family, Adults and helpers), the meeting where a grown-up welcomes someone in person, the new person's side, and the
// page where two grown-ups' phones share what has happened. UNVERIFIED on a device; headless widget tests in CI
// (client/test/village_welcome_flow_test.dart). Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3 and 12.
//
// ADULT WORDS ONLY, GROWN-UPS ONLY. These screens sit behind the Settings hub (and its PIN) and every yes, every
// request and the new person's own yes asks for the PIN again. A child never reaches them and no child file imports
// this one (a test guards it). They say "your village", "welcome", "share with the other grown-ups' phones"; never a
// technical word (record, key, ledger, sync), never a count of how often anyone answered, never "blocked" or "refused".
//
// WHAT RUNS AND WHEN. Opening "Your village" only reads. The road to the other phone (a small endpoint and an mDNS
// advertisement) is up only while the meeting screen or the sharing screen is open, and is stopped when it closes.
// A family record is founded on this phone only when a grown-up taps "Welcome someone" and types their PIN.
//
// PEOPLE ALREADY IN: "People in the village" (village_people_screens.dart) pauses, ends (together, or by a 14 day
// notice), suggests and answers a limits agreement (24 hour think-over) and gives a Standing OK.
//
// WHAT IS STILL HEADLESS (not on these screens): the 72 hour hold when a family of one welcomes a parent, the "Who must
// agree" settings, the settle-in cards, the carer's own page beyond one line, a tablet that refuses a paused phone, and
// key changes after someone is ended.
import 'dart:async';

import 'package:flutter/material.dart';

import 'device_keys.dart' show DeviceKey;
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_profiles.dart';
import 'family_state.dart';
import 'pairing_protocol.dart' show PairingTransport, Sas;
import 'ui/olive_ui.dart';
import 'village_lan.dart' show NearbyVillage;
import 'village_link.dart';
import 'village_meet.dart';
import 'village_people_screens.dart';
import 'village_welcome_host.dart';
import 'welcome_logic.dart';
import 'welcome_screens.dart';

const String kMeetRouteName = 'villageMeet';

/// Opens "Your village". [services] is built by the caller from this phone\'s local services.
Future<void> openYourVillage(BuildContext context, VillageServices services) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => VillageHomeScreen(services: services)));

/// Who is offering and what, read from the request itself (so the same words work for the grown-ups and for the person).
class InvitationFacts {
  InvitationFacts({required this.askerName, required this.personName, required this.profile, required this.expMs, required this.hash});
  final String askerName, personName, hash;
  final MemberProfile profile;
  final int expMs;

  static InvitationFacts? of(LedgerState s, LedgerEntry e) {
    final MemberProfile? p = MemberProfile.fromValue(e.body['profile']);
    final Object? pr = e.body['proposal'];
    final Object? name = e.body['name'];
    if (p == null || pr is! Map<String, Object?> || name is! String) return null;
    final LedgerDevice? signer = s.deviceFor(e.signer);
    String asker = 'A parent';
    for (final LedgerMember m in s.members) {
      if (m.gidHex == signer?.gidHex) asker = m.name;
    }
    return InvitationFacts(askerName: asker, personName: name, profile: p, expMs: pr['exp']! as int, hash: e.hashHex);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Your village
// ---------------------------------------------------------------------------------------------------------------

class VillageHomeScreen extends StatefulWidget {
  const VillageHomeScreen({super.key, required this.services});
  final VillageServices services;

  @override
  State<VillageHomeScreen> createState() => _VillageHomeScreenState();
}

class _VillageHomeScreenState extends State<VillageHomeScreen> {
  bool _loading = true, _unreadable = false;
  FamilyContext? _ctx;
  LedgerState? _state;
  DeviceKey? _me;

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final DeviceKey me = await _s.device();
      final FamilyContext? ctx = await _s.load();
      final LedgerState? st = ctx == null ? null : await ctx.state(nowMs: _s.now());
      if (!mounted) return;
      setState(() {
        _me = me;
        _ctx = ctx;
        _state = st;
        _loading = false;
        _unreadable = false;
      });
    } on FamilyRecordUnusable {
      if (mounted) {
        setState(() {
          _loading = false;
          _unreadable = true;
        });
      }
    }
  }

  Future<void> _welcomeSomeone() async {
    if (!await _s.confirmPin(context) || !mounted) return;
    try {
      await _s.found();
    } on FamilyRecordUnusable {
      await _reload();
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        settings: const RouteSettings(name: kMeetRouteName), builder: (BuildContext _) => VillageMeetHostScreen(services: _s)));
    await _reload();
  }

  Future<void> _join() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => VillageJoinScreen(services: _s)));
    await _reload();
  }

  Future<void> _people() async {
    await openVillagePeople(context, _s);
    await _reload();
  }

  Future<void> _share() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => VillageShareScreen(services: _s)));
    await _reload();
  }

  Future<void> _requests() async {
    final FamilyContext ctx = _ctx!;
    final WelcomeService svc = _s.welcome(ctx);
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext c) => WelcomeCentreScreen(
        service: svc,
        childName: _s.childName,
        confirmPin: () => _s.confirmPin(c),
        onWelcomeSomeone: () {
          Navigator.of(c).pop();
          unawaited(_welcomeSomeone());
        },
        onOpenRequest: (WelcomeRequest r) => Navigator.of(c).push<void>(MaterialPageRoute<void>(
          builder: (BuildContext rc) => WelcomeRequestScreen(
            service: svc,
            request: r,
            childName: _s.childName,
            confirmPin: () => _s.confirmPin(rc),
            onDone: (WelcomeAnswer _) => Navigator.of(rc).pop(),
          ),
        )),
      ),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your village')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(padding: const EdgeInsets.all(16), child: _body(t)),
      ),
    );
  }

  Widget _body(TextTheme t) {
    if (_unreadable) {
      return const EmptyState(
          key: Key('villageUnreadable'),
          title: 'This phone could not read its village',
          sub: 'Nothing was changed. It is left exactly as it was.');
    }
    final FamilyContext? ctx = _ctx;
    final LedgerState? st = _state;
    if (ctx == null || st == null || !st.ok) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('Welcome another grown-up to ${_s.childName}’s village, or join one a grown-up has started.', style: t.bodyMedium),
        const SizedBox(height: 12),
        OliveCard(
          child: Column(children: <Widget>[
            OliveRow(
              key: const Key('villageWelcome'),
              icon: OliveIcons.users,
              title: 'Welcome someone',
              sub: 'You and the new person sit together, on the same Wi-Fi. Nobody is in until you have both said yes.',
              onTap: _welcomeSomeone,
            ),
            OliveRow(
              key: const Key('villageJoin'),
              icon: OliveIcons.user,
              title: 'Join someone’s village',
              sub: 'A grown-up gives you a code. You say yes on this phone.',
              onTap: _join,
            ),
          ]),
        ),
      ]);
    }
    final LedgerDevice? mine = st.deviceFor(_me!.publicKey);
    if (mine == null) return _invited(ctx, st, t);
    if (mine.kind == 'carer') return _carer(ctx, st, mine, t);
    return _parent(st, t);
  }

  Widget _parent(LedgerState st, TextTheme t) {
    final List<String> names = <String>[for (final LedgerMember m in st.members) m.name];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('In ${_s.childName}’s village: ${names.join(', ')}.', key: const Key('villageMembers'), style: t.bodyMedium),
      if (st.paused.isNotEmpty || st.endNotices.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text('A pause or a notice is running. You can see it in People in the village.', key: const Key('villageAttention'), style: t.bodyMedium),
      ],
      const SizedBox(height: 12),
      OliveCard(
        child: Column(children: <Widget>[
          OliveRow(
            key: const Key('villagePeople'),
            icon: OliveIcons.user,
            title: 'People in the village',
            sub: 'Who is here. Pause someone, end a place, agree limits, say yes in advance.',
            onTap: _people,
          ),
          OliveRow(
            key: const Key('villageRequests'),
            icon: OliveIcons.users,
            title: 'Requests and who is here',
            sub: 'Answer a request, see what is waiting for others, and what has happened.',
            onTap: _requests,
          ),
          OliveRow(
            key: const Key('villageWelcome'),
            icon: OliveIcons.user,
            title: 'Welcome someone',
            sub: 'In person, on the same Wi-Fi. The other parents are asked before anyone is in.',
            onTap: _welcomeSomeone,
          ),
          OliveRow(
            key: const Key('villageShare'),
            icon: OliveIcons.mail,
            title: 'Share with the other grown-ups’ phones',
            sub: 'Answers and requests travel between your phones when they are on the same Wi-Fi.',
            onTap: _share,
          ),
        ]),
      ),
    ]);
  }

  Widget _carer(FamilyContext ctx, LedgerState st, LedgerDevice mine, TextTheme t) {
    LedgerMember? me;
    for (final LedgerMember m in st.members) {
      if (m.gidHex == mine.gidHex) me = m;
    }
    final MemberProfile? p = me?.profile;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('You are welcomed to ${_s.childName}’s village.', key: const Key('villageWelcomed'), style: t.titleMedium),
      const SizedBox(height: 6),
      // A paused carer is told only that it is not available right now: no reason, no name, no blame.
      if (st.isPaused(mine.gidHex ?? '')) Text('Not available right now.', key: const Key('villageNotAvailable'), style: t.bodyMedium)
      else if (p != null) Text(profileLine(p), style: t.bodyMedium),
      const SizedBox(height: 12),
      OliveCard(
        child: OliveRow(
          key: const Key('villageShare'),
          icon: OliveIcons.mail,
          title: 'Share with the other grown-ups’ phones',
          sub: 'Changes reach this phone when you are on the same Wi-Fi.',
          onTap: _share,
        ),
      ),
    ]);
  }

  Widget _invited(FamilyContext ctx, LedgerState st, TextTheme t) {
    final LedgerEntry? inv = findInvitation(st, ctx.entries, _me!.publicKey);
    if (inv == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('There is nothing waiting for you here.', key: const Key('villageNothingForYou'), style: t.titleMedium),
        const SizedBox(height: 6),
        Text('A request ends by itself if nobody answers in time. You can ask the grown-up for a new one.', style: t.bodyMedium),
        const SizedBox(height: 12),
        OliveCard(
          child: OliveRow(
            key: const Key('villageShare'),
            icon: OliveIcons.mail,
            title: 'Check for news',
            sub: 'Looks for the grown-ups’ phones on the same Wi-Fi.',
            onTap: _share,
          ),
        ),
      ]);
    }
    return VillageInvitationView(
      key: const Key('villageInvitation'),
      services: _s,
      facts: InvitationFacts.of(st, inv)!,
      onYes: () async {
        if (!await _s.confirmPin(context)) return false;
        await candidateSaysYes(ctx: ctx, repository: _s.family, invitation: inv, nowMs: _s.now());
        await _reload();
        return true;
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// What the new person is offered
// ---------------------------------------------------------------------------------------------------------------

class VillageInvitationView extends StatefulWidget {
  const VillageInvitationView({super.key, required this.services, required this.facts, required this.onYes, this.onNotNow});
  final VillageServices services;
  final InvitationFacts facts;

  /// Signs the yes (the host asks for the PIN first). True when it was signed and kept.
  final Future<bool> Function() onYes;
  final VoidCallback? onNotNow;

  @override
  State<VillageInvitationView> createState() => _VillageInvitationViewState();
}

class _VillageInvitationViewState extends State<VillageInvitationView> {
  bool _busy = false, _said = false;
  String? _message;

  Future<void> _yes() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bool ok = await widget.onYes();
      if (!mounted) return;
      setState(() {
        _said = ok;
        if (!ok) _message = 'That PIN did not match, so nothing was sent.';
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'That could not be saved on this phone, so nothing was sent. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final InvitationFacts f = widget.facts;
    final String child = widget.services.childName;
    final bool limited = f.profile.preset == Preset.parentWithLimits;
    final List<ChecklistLine> list = checklistFor(f.profile, child);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text(
          limited
              ? '${f.askerName} would like you to join $child’s village as a parent, with these limits.'
              : '${f.askerName} would like to welcome you to $child’s village as ${_asWords(f.profile.preset)}.',
          key: const Key('invitationSentence'),
          style: t.titleMedium),
      const SizedBox(height: 6),
      Text(
          limited
              ? 'You can say no. Nothing changes if you do. The limits are exactly the ones below, and you can only be in with them.'
              : 'You can say no. Nothing changes if you do.',
          key: const Key('invitationNoPressure'),
          style: t.bodyMedium),
      const SizedBox(height: 12),
      KeyValueList(<(String, String)>[
        ('What you could do', reachLine(f.profile.reach)),
        ('For how long', timeBoxWords(f.profile)),
        ('This offer ends', dateWords(f.expMs)),
      ]),
      const SizedBox(height: 12),
      OliveCard(
        child: Column(children: <Widget>[
          for (int i = 0; i < list.length; i++)
            OliveRow(
              key: Key('invitationLine_$i'),
              title: list[i].words,
              sub: list[i].on ? 'Yes' : 'No',
              icon: list[i].on ? OliveIcons.check : OliveIcons.lock,
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(
          'Other parents may also be asked. You are in only when everyone who has to agree has, and then you settle in for a while first.',
          style: t.bodySmall),
      if (_message != null) ...<Widget>[
        const SizedBox(height: 12),
        Text(_message!, key: const Key('invitationMessage'), style: t.bodyMedium),
      ],
      const SizedBox(height: 16),
      if (_said)
        Text('Your yes is saved on this phone and goes to the other grown-ups’ phones when they meet.',
            key: const Key('invitationSaid'), style: t.bodyMedium)
      else ...<Widget>[
        FilledButton(
            key: const Key('invitationYes'), onPressed: _busy ? null : _yes, child: const Text('Yes, I would like that')),
        const SizedBox(height: 8),
        OutlinedButton(
            key: const Key('invitationNotNow'),
            onPressed: _busy ? null : (widget.onNotNow ?? () => Navigator.of(context).maybePop()),
            child: const Text('Not now')),
      ],
    ]);
  }
}

String _asWords(Preset p) {
  switch (p) {
    case Preset.parent:
    case Preset.parentWithLimits:
      return 'a parent';
    case Preset.visit:
      return 'a visitor';
    default:
      return 'a carer';
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The meeting (a grown-up welcomes someone, in person)
// ---------------------------------------------------------------------------------------------------------------

class VillageMeetHostScreen extends StatefulWidget {
  const VillageMeetHostScreen({super.key, required this.services});
  final VillageServices services;

  @override
  State<VillageMeetHostScreen> createState() => _VillageMeetHostScreenState();
}

class _VillageMeetHostScreenState extends State<VillageMeetHostScreen> {
  VillageMeetWindow? _window;
  VillageServing? _serving;
  FamilyContext? _ctx;
  String? _error;
  bool _flowStarted = false;
  String? _requestHash;
  String _status = '';

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final FamilyContext ctx = await _s.found();
      final VillageMeetWindow w = VillageMeetWindow.open();
      final VillageDoor door = _s.door(ctx, onChanged: () => unawaited(_refresh()));
      final VillageServing serving = await _s.network.serve(meet: w, door: door);
      w.addListener(_onWindow);
      if (!mounted) {
        w.close();
        await serving.stop();
        return;
      }
      setState(() {
        _ctx = ctx;
        _window = w;
        _serving = serving;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'This phone could not start looking for the other phone. Check that Wi-Fi is on and try again.');
    }
  }

  void _onWindow() {
    if (!mounted) return;
    setState(() {});
    final VillageMeetWindow? w = _window;
    if (w != null && w.state == MeetState.matched && !_flowStarted) {
      _flowStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_choose());
      });
    }
  }

  Future<void> _refresh() async {
    final FamilyContext? ctx = _ctx;
    final String? hash = _requestHash;
    if (ctx == null || hash == null || !mounted) return;
    final WelcomeOverview o = await _s.welcome(ctx).overview();
    final WelcomeRequest? r = o.sent.where((WelcomeRequest x) => x.hashHex == hash).firstOrNull;
    if (r == null || !mounted) return;
    setState(() {
      switch (r.status) {
        case 'welcomed':
          _status = '${r.personName} is welcomed. They settle in first.';
        case 'declined':
          _status = '${r.personName} was not set up this time.';
        case 'lapsed':
          _status = 'The request to welcome ${r.personName} ended without an answer.';
        default:
          _status = <String>[for (final ElectorStatus e in r.electors) e.words].join('. ');
      }
    });
  }

  @override
  void dispose() {
    final VillageMeetWindow? w = _window;
    w?.removeListener(_onWindow);
    w?.close();
    unawaited(_serving?.stop());
    super.dispose();
  }

  Future<void> _choose() async {
    final FamilyContext ctx = _ctx!;
    final VillageMeetWindow w = _window!;
    final LedgerState st = await ctx.state(nowMs: _s.now());
    if (!mounted) return;
    final WelcomeService svc = _s.welcome(ctx);
    final NavigatorState nav = Navigator.of(context);
    await nav.push<void>(MaterialPageRoute<void>(
      builder: (BuildContext c) => WelcomeWhoScreen(
        childName: _s.childName,
        onParent: () => _profile(c, parentTier: true, st: st, w: w, svc: svc, ctx: ctx),
        onCarer: () => _profile(c, parentTier: false, st: st, w: w, svc: svc, ctx: ctx),
        onHelper: () {
          w.decline();
          Navigator.of(c).popUntil((Route<dynamic> r) => r.settings.name == kMeetRouteName || r.isFirst);
          _s.openHelpers?.call();
        },
      ),
    ));
    if (mounted && w.state == MeetState.matched) {
      // The grown-up backed out of choosing: nothing was proposed and nothing was sent.
      w.decline();
    }
  }

  void _profile(BuildContext c, {required bool parentTier, required LedgerState st, required VillageMeetWindow w, required WelcomeService svc, required FamilyContext ctx}) {
    Navigator.of(c).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext pc) => WelcomeProfileScreen(
        childName: _s.childName,
        parentTier: parentTier,
        policy: st.policy,
        parentCount: st.guardians.length,
        children: _s.children,
        nowMs: _s.now,
        confirmPin: () => _s.confirmPin(pc),
        onChosen: (WelcomeChoices ch) async {
          final MeetIntro intro = w.intro!;
          final LedgerEntry e = await svc.propose(WelcomeDraft(personName: ch.personName, profile: ch.profile, candidate: intro.record));
          await w.offer(entries: ctx.entries, votes: ctx.votes);
          _requestHash = e.hashHex;
          await _refresh();
          if (pc.mounted) Navigator.of(pc).popUntil((Route<dynamic> r) => r.settings.name == kMeetRouteName || r.isFirst);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final VillageMeetWindow? w = _window;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome someone')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _error != null
              ? Text(_error!, key: const Key('meetError'), style: t.bodyMedium)
              : (w == null ? const Center(child: CircularProgressIndicator()) : _body(w, t)),
        ),
      ),
    );
  }

  Widget _body(VillageMeetWindow w, TextTheme t) {
    switch (w.state) {
      case MeetState.open:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Ask the new person to open Olive on their phone, then Settings, Family, Adults and helpers, Your village, Join someone’s village.',
              style: t.bodyMedium),
          const SizedBox(height: 12),
          Text('Their phone asks for this code. Both phones must be on the same Wi-Fi.', style: t.bodyMedium),
          const SizedBox(height: 12),
          Center(child: Text(w.code, key: const Key('meetCode'), style: t.displaySmall)),
          const SizedBox(height: 12),
          Text('It works for 15 minutes. Nothing happens until you both say yes.', style: t.bodySmall),
        ]);
      case MeetState.introduced:
        final Sas sas = w.sas!;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('A phone is here. It calls itself “${w.intro!.deviceName}”.', key: const Key('meetIntroduced'), style: t.titleMedium),
          const SizedBox(height: 12),
          Text('Their screen should show this word and picture. Check that it does.', style: t.bodyMedium),
          const SizedBox(height: 8),
          Center(child: Text('${sas.word} ${sas.picture}', key: const Key('meetSas'), style: t.headlineMedium)),
          const SizedBox(height: 16),
          FilledButton(key: const Key('meetMatch'), onPressed: w.confirmMatch, child: const Text('Yes, they match')),
          const SizedBox(height: 8),
          OutlinedButton(key: const Key('meetNoMatch'), onPressed: w.decline, child: const Text('No, they are different')),
        ]);
      case MeetState.matched:
        return Text('Choose what they can do…', key: const Key('meetChoosing'), style: t.bodyMedium);
      case MeetState.offered:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Sent. ${w.intro?.deviceName ?? 'Their phone'} now shows what they are being offered.', key: const Key('meetOffered'), style: t.titleMedium),
          const SizedBox(height: 8),
          Text('They say yes on their own phone. Keep this screen open until they have, or share again later from Your village.',
              style: t.bodyMedium),
          if (_status.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(_status, key: const Key('meetStatus'), style: t.bodyMedium),
          ],
          const SizedBox(height: 16),
          OutlinedButton(key: const Key('meetDone'), onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ]);
      case MeetState.declined:
      case MeetState.closed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('This meeting has ended. Nothing was sent and nobody was added.', key: const Key('meetEnded'), style: t.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton(key: const Key('meetClose'), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ]);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The new person\'s phone
// ---------------------------------------------------------------------------------------------------------------

class VillageJoinScreen extends StatefulWidget {
  const VillageJoinScreen({super.key, required this.services});
  final VillageServices services;

  @override
  State<VillageJoinScreen> createState() => _VillageJoinScreenState();
}

enum _JoinStep { code, looking, compare, waiting, offered, sent, failed, hasFamily }

class _VillageJoinScreenState extends State<VillageJoinScreen> {
  final TextEditingController _code = TextEditingController();
  _JoinStep _step = _JoinStep.code;
  JoinMeeting? _meeting;
  PairingTransport? _transport;
  AgreementKey? _agreement;
  List<LedgerEntry> _entries = <LedgerEntry>[];
  List<LedgerVote> _votes = <LedgerVote>[];
  InvitationFacts? _facts;
  LedgerEntry? _invitation;
  bool _cancelled = false;

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_checkFamily());
  }

  Future<void> _checkFamily() async {
    if (await _s.family.hasRecord() && mounted) setState(() => _step = _JoinStep.hasFamily);
  }

  @override
  void dispose() {
    _cancelled = true;
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final String code = _code.text.trim();
    if (code.length != kMeetCodeDigits) return;
    setState(() => _step = _JoinStep.looking);
    final DeviceKey dev = await _s.device();
    final AgreementKey agree = await AgreementKey.generate();
    final VillageJoiner joiner = VillageJoiner(device: dev, agreement: agree, deviceName: _s.deviceLabel);
    final Set<String> tried = <String>{};
    final Completer<JoinMeeting?> done = Completer<JoinMeeting?>();
    PairingTransport? via;
    final StreamSubscription<NearbyVillage> sub = _s.network.nearby().listen((NearbyVillage n) async {
      if (done.isCompleted || !tried.add(n.key)) return;
      final PairingTransport tr = _s.network.open(n);
      final JoinMeeting? m = await joiner.meet(transport: tr, handle: n.handle, code: code);
      if (m != null && !done.isCompleted) {
        via = tr;
        done.complete(m);
      }
    });
    final JoinMeeting? m = await done.future.timeout(const Duration(seconds: 25), onTimeout: () => null);
    await sub.cancel();
    if (!mounted || _cancelled) return;
    if (m == null) {
      setState(() => _step = _JoinStep.failed);
      return;
    }
    _meeting = m;
    _transport = via;
    _agreement = agree;
    setState(() => _step = _JoinStep.compare);
  }

  Future<void> _same() async {
    setState(() => _step = _JoinStep.waiting);
    final JoinMeeting m = _meeting!;
    final int deadline = _s.now() + kMeetTtl.inMilliseconds;
    while (mounted && !_cancelled && _s.now() < deadline) {
      final JoinPoll p = await m.poll(nowMs: _s.now());
      if (!mounted || _cancelled) return;
      if (p.kind == JoinPollKind.failed) {
        setState(() => _step = _JoinStep.failed);
        return;
      }
      if (p.kind == JoinPollKind.offered) {
        final LedgerState st = await reduceLedger(entries: p.entries, votes: p.votes, nowMs: _s.now());
        final LedgerEntry? inv = findInvitation(st, p.entries, (await _s.device()).publicKey);
        final InvitationFacts? f = inv == null ? null : InvitationFacts.of(st, inv);
        if (inv == null || f == null) {
          setState(() => _step = _JoinStep.failed);
          return;
        }
        setState(() {
          _entries = p.entries;
          _votes = p.votes;
          _invitation = inv;
          _facts = f;
          _step = _JoinStep.offered;
        });
        return;
      }
      await Future<void>.delayed(_s.pollEvery);
    }
    if (mounted) setState(() => _step = _JoinStep.failed);
  }

  Future<bool> _yes() async {
    if (!await _s.confirmPin(context)) return false;
    final FamilyContext ctx =
        await _s.adopt(agreement: _agreement!, entries: _entries, votes: _votes);
    await candidateSaysYes(ctx: ctx, repository: _s.family, invitation: _invitation!, nowMs: _s.now());
    // Tell the grown-up\'s phone now, while it is still next to this one; if it cannot be reached the yes waits here and
    // goes the next time the two phones share.
    try {
      final PairingTransport? tr = _transport;
      if (tr != null) await _s.door(ctx).exchange(tr.send);
    } catch (_) {}
    if (mounted) setState(() => _step = _JoinStep.sent);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Join someone’s village')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _body(t))),
    );
  }

  Widget _body(TextTheme t) {
    switch (_step) {
      case _JoinStep.hasFamily:
        return Text('This phone already has a village of its own, so it cannot join another. Nothing was changed.',
            key: const Key('joinHasFamily'), style: t.bodyMedium);
      case _JoinStep.code:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Sit next to the grown-up who is welcoming you, on the same Wi-Fi. Their phone shows a code. Type it here.',
              style: t.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('joinCode'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: kMeetCodeDigits,
            decoration: const InputDecoration(labelText: 'The code on their phone'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
              key: const Key('joinFind'),
              onPressed: _code.text.trim().length == kMeetCodeDigits ? _find : null,
              child: const Text('Find their phone')),
        ]);
      case _JoinStep.looking:
        return Column(children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Looking for their phone…', key: const Key('joinLooking'), style: t.bodyMedium),
        ]);
      case _JoinStep.compare:
        final Sas sas = _meeting!.sas;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Their screen should show this word and picture. Check that it does.', style: t.bodyMedium),
          const SizedBox(height: 8),
          Center(child: Text('${sas.word} ${sas.picture}', key: const Key('joinSas'), style: t.headlineMedium)),
          const SizedBox(height: 16),
          FilledButton(key: const Key('joinSame'), onPressed: _same, child: const Text('Yes, the same')),
          const SizedBox(height: 8),
          OutlinedButton(
              key: const Key('joinDifferent'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('No, it is different')),
        ]);
      case _JoinStep.waiting:
        return Column(children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Waiting for the grown-up to choose what to offer you…', key: const Key('joinWaiting'), style: t.bodyMedium),
        ]);
      case _JoinStep.offered:
        return VillageInvitationView(
            key: const Key('joinInvitation'), services: _s, facts: _facts!, onYes: _yes, onNotNow: () => Navigator.of(context).maybePop());
      case _JoinStep.sent:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Your yes is saved.', key: const Key('joinSent'), style: t.titleMedium),
          const SizedBox(height: 8),
          Text(
              'The other parents may still be asked. You are in once everyone who has to agree has. You can check later from Your village.',
              style: t.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton(key: const Key('joinDone'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
        ]);
      case _JoinStep.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('That did not work. Check that you are on the same Wi-Fi and that the code is right, then try again.',
              key: const Key('joinFailed'), style: t.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton(
              key: const Key('joinAgain'),
              onPressed: () => setState(() => _step = _JoinStep.code),
              child: const Text('Try again')),
        ]);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Sharing between the grown-ups\' phones
// ---------------------------------------------------------------------------------------------------------------

class VillageShareScreen extends StatefulWidget {
  const VillageShareScreen({super.key, required this.services});
  final VillageServices services;

  @override
  State<VillageShareScreen> createState() => _VillageShareScreenState();
}

class _VillageShareScreenState extends State<VillageShareScreen> {
  VillageServing? _serving;
  VillageDoor? _door;
  FamilyContext? _ctx;
  StreamSubscription<NearbyVillage>? _sub;
  Timer? _timer;
  final Map<String, NearbyVillage> _seen = <String, NearbyVillage>{};
  final List<String> _lines = <String>[];
  bool _nobody = false, _alone = false, _error = false;
  bool _busy = false;

  VillageServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final FamilyContext? ctx = await _s.load();
      if (ctx == null) {
        if (mounted) setState(() => _nobody = true);
        return;
      }
      final VillageDoor door = _s.door(ctx, onChanged: () {
        if (mounted) setState(() {});
      });
      final VillageServing serving = await _s.network.serve(door: door);
      if (!mounted) {
        await serving.stop();
        return;
      }
      _ctx = ctx;
      _door = door;
      _serving = serving;
      _sub = _s.network.nearby().listen((NearbyVillage n) {
        if (bytesEqualHandle(n.handle, serving.handle)) return;
        _seen[n.key] = n;
        unawaited(_exchangeWith(n));
      });
      _timer = Timer.periodic(_s.syncEvery, (_) => unawaited(_again()));
      final LedgerState st = await ctx.state(nowMs: _s.now());
      final DeviceKey me = await _s.device();
      if (mounted) setState(() => _alone = villagePeers(st, ctx.entries, me.publicKey).isEmpty);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _again() async {
    for (final NearbyVillage n in _seen.values.toList()) {
      await _exchangeWith(n);
    }
  }

  Future<void> _exchangeWith(NearbyVillage n) async {
    final VillageDoor? door = _door;
    final FamilyContext? ctx = _ctx;
    if (door == null || ctx == null) return;
    try {
      final DoorOutcome o = await door.exchange(_s.network.open(n).send);
      if (!mounted) return;
      if (o.heardFrom.isEmpty) return;
      final LedgerState st = await ctx.state(nowMs: _s.now());
      final String who = <String>{
        for (final String k in o.heardFrom) _nameOf(st, ctx, k),
      }.join(' and ');
      setState(() => _lines.insert(0, o.changed ? 'Updated from $who’s phone.' : 'Nothing new from $who’s phone.'));
    } catch (_) {}
  }

  String _nameOf(LedgerState st, FamilyContext ctx, String keyHex) {
    for (final LedgerDevice d in st.devices) {
      if (d.keyHex == keyHex) {
        for (final LedgerMember m in st.members) {
          if (m.gidHex == d.gidHex) return m.name;
        }
      }
    }
    for (final VillagePeer p in pendingCandidates(st, ctx.entries)) {
      if (p.keyHex == keyHex) return p.name;
    }
    return 'a grown-up';
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sub?.cancel());
    unawaited(_serving?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Share with the other grown-ups’ phones')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            if (_error)
              Text('This phone could not start looking. Check that Wi-Fi is on and try again.', key: const Key('shareError'), style: t.bodyMedium)
            else if (_nobody)
              Text('This phone has no village to share yet.', key: const Key('shareNobody'), style: t.bodyMedium)
            else ...<Widget>[
              Text('Keep this screen open on both phones, on the same Wi-Fi. Answers and requests move between them by themselves.',
                  key: const Key('shareHelp'), style: t.bodyMedium),
              const SizedBox(height: 12),
              if (_alone && _lines.isEmpty)
                Text('There is nobody else to share with yet. A person you welcome appears here once they have been introduced.', key: const Key('shareAlone'), style: t.bodyMedium)
              else if (_lines.isEmpty)
                Text('Looking for the other phones…', key: const Key('shareLooking'), style: t.bodyMedium)
              else
                OliveCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    for (int i = 0; i < _lines.length; i++)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(_lines[i], key: Key('shareLine_$i'), style: t.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                  key: const Key('shareAgain'),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await _again();
                          if (mounted) setState(() => _busy = false);
                        },
                  child: const Text('Look again')),
            ],
          ]),
        ),
      ),
    );
  }
}

bool bytesEqualHandle(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
