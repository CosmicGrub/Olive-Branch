// OLIVE BRANCH — the grown-ups' "Share with another grown-up" screens: add a second grown-up's phone, join one, share now
// over the same Wi-Fi, and the way into the shared emergency card and the screens sent between grown-ups. UNVERIFIED on
// a device; headless widget tests in CI (client/test/family_phones_screen_test.dart). Spec:
// docs/planning/FAMILY-SYNC-DESIGN.md (first slice), FAMILY-IDENTITY-DESIGN.md (second grown-up). MASTERFILE 8.24.
//
// GROWN-UPS ONLY. Reached from More, Safety, in the grown-up app, and nowhere in a child's app. A child's device has no
// guardian service, so none of this is ever built there. It is not a PIN screen: the grown-up app is already behind the
// adult gate and the phone's own PIN.
//
// WORDS. Plain adult words: "phone", "Wi-Fi", "card", "share". Never a technical word (no key, ledger, sync, epoch,
// event, bundle, seal). No counts or scores. Nothing it says is medical advice. Honest limits are said where they bite:
// both phones need the same Wi-Fi with Olive open, a newly added phone settles in first, and an added phone can see what
// the family shares with grown-ups.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emergency_card_local.dart';
import 'family_hub.dart';
import 'family_join.dart';
import 'family_state.dart' show FamilyContext;
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'family_sync_engine.dart';
import 'family_sync_lan.dart';
import 'family_sync_screen.dart';
import 'pairing_protocol.dart' show Sas;
import 'screen_share_ui.dart';

/// What the screen says after "Share now". Pure, so it is tested without a phone.
String syncRunText(SyncRun r) {
  if (r.noWifi) return 'This phone is not on a Wi-Fi network, so it cannot find the other phone.';
  if (r.met == 0) {
    return r.failed > 0
        ? 'The other phone did not answer. Check that Olive is open on it.'
        : 'The other phone was not found. Both phones need the same Wi-Fi, with Olive open.';
  }
  final String got = r.updates > 0
      ? (r.updates == 1 ? 'Got 1 update.' : 'Got ${r.updates} updates.')
      : 'Both phones are up to date.';
  return r.sent > 0 ? '$got ${r.sent == 1 ? 'A screen was' : 'Screens were'} sent.' : got;
}

class FamilyPhonesScreen extends StatefulWidget {
  const FamilyPhonesScreen({
    super.key,
    required this.hub,
    required this.childId,
    required this.principal,
    required this.cardService,
    this.childName = 'her',
    this.defaultName = '',
    this.clipboard = const SystemClipboardPort(),
  });

  final FamilyHub hub;
  final String childId;
  final FamilyPrincipal? principal;
  final EmergencyCardService cardService;
  final String childName;

  /// What the name box starts with (the grown-up's label on this phone).
  final String defaultName;
  final SyncClipboardPort clipboard;

  @override
  State<FamilyPhonesScreen> createState() => _FamilyPhonesScreenState();
}

class _FamilyPhonesScreenState extends State<FamilyPhonesScreen> {
  FamilyStatus? _status;
  String? _line;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_refresh);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    widget.hub.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final FamilyStatus s = await widget.hub.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _shareNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _line = null;
    });
    try {
      final SyncRun r = await widget.hub.syncNow();
      if (mounted) setState(() => _line = syncRunText(r));
    } catch (_) {
      if (mounted) setState(() => _line = 'That did not work. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(_refresh());
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    unawaited(_refresh());
  }

  Future<void> _openCard() async {
    final SyncEngine? e = await widget.hub.syncEngine();
    final FamilyContext? c = await widget.hub.context();
    if (!mounted || e == null || c == null) return;
    await _push(
      FamilySyncScreen(
        engine: e,
        childId: widget.childId,
        principal: widget.principal,
        cardService: widget.cardService,
        ledger: () async => (await widget.hub.context())!.state(nowMs: widget.hub.now()),
        myName: widget.defaultName,
        childName: widget.childName,
        clipboard: widget.clipboard,
        shareNow: () async => syncRunText(await widget.hub.syncNow()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FamilyStatus? s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Share with another grown-up')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'Two grown-ups can share the emergency card and pictures of a screen between their own phones. It goes straight '
              'from phone to phone on the same Wi-Fi. Nothing goes to a child, and nothing leaves your home network.',
              key: Key('phonesIntro'),
            ),
            const SizedBox(height: 16),
            if (s == null) const Center(child: CircularProgressIndicator()) else ..._body(s),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(FamilyStatus s) {
    switch (s.standing) {
      case FamilyStanding.unusable:
        return const <Widget>[
          Text(
            "This phone's family record could not be read, so nothing was changed. Nothing is shared until that is sorted out.",
            key: Key('phonesUnusable'),
          ),
        ];
      case FamilyStanding.none:
      case FamilyStanding.alone:
        return <Widget>[
          Text(
            s.standing == FamilyStanding.none
                ? 'This phone is not sharing with anyone yet.'
                : 'Only you are in the family so far.',
            key: const Key('phonesAlone'),
          ),
          if (s.waitingFor != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${s.waitingFor} was invited but has not finished. Keep both phones on the same Wi-Fi with Olive open.',
                key: const Key('phonesWaiting'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('phonesAdd'),
            onPressed: () => _push(AddGrownUpScreen(hub: widget.hub, defaultName: widget.defaultName)),
            child: const Text("Add another grown-up's phone"),
          ),
          const SizedBox(height: 8),
          if (s.standing == FamilyStanding.none)
            OutlinedButton(
              key: const Key('phonesJoin'),
              onPressed: () => _push(JoinGrownUpScreen(hub: widget.hub, defaultName: widget.defaultName)),
              child: const Text("Join another grown-up's phone"),
            ),
        ];
      case FamilyStanding.pair:
        return <Widget>[
          Text('Shared with ${_names(s.others)}.', key: const Key('phonesPair')),
          if (s.settlingHours > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A newly added phone settles in for a while. Until then you can share the emergency card with it, but not '
                'pictures of a screen.',
                key: const Key('phonesSettling'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('phonesShareNow'),
            onPressed: _busy ? null : _shareNow,
            child: const Text('Share now over Wi-Fi'),
          ),
          if (_line != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(liveRegion: true, child: Text(_line!, key: const Key('phonesLine'))),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('phonesCard'),
            onPressed: _openCard,
            child: Text('${_possessive(widget.childName)} emergency card'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('phonesScreens'),
            onPressed: () => _push(ScreenShareInboxScreen(service: widget.hub.shares)),
            child: const Text('Screens shared between grown-ups'),
          ),
        ];
    }
  }
}

String _possessive(String childName) => childName == 'her' ? 'The' : "$childName's";

String _names(List<String> n) => n.length <= 1
    ? (n.isEmpty ? 'another grown-up' : n.first)
    : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';

// ============================================================================================== adding a phone ===

class AddGrownUpScreen extends StatefulWidget {
  const AddGrownUpScreen({super.key, required this.hub, this.defaultName = ''});
  final FamilyHub hub;
  final String defaultName;
  @override
  State<AddGrownUpScreen> createState() => _AddGrownUpScreenState();
}

class _AddGrownUpScreenState extends State<AddGrownUpScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.defaultName);
  FamilyJoinWindow? _w;
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _w?.close();
    _name.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final FamilyJoinWindow? w = await widget.hub.openJoinWindow(
      myName: _name.text.trim().isEmpty ? 'Grown-up' : _name.text.trim(),
    );
    if (!mounted) {
      w?.close();
      return;
    }
    setState(() {
      _busy = false;
      _w = w;
      _problem = w == null
          ? (widget.hub.lastJoinProblem == 'no_wifi' ? 'no_wifi' : widget.hub.lastJoinProblem ?? 'x')
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final FamilyJoinWindow? w = _w;
    return Scaffold(
      appBar: AppBar(title: const Text("Add another grown-up's phone")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (w == null)
              ..._start()
            else
              AnimatedBuilder(
                animation: w,
                builder: (BuildContext c, Widget? _) =>
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: _window(w)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _start() => <Widget>[
    const Text(
      'Both phones need to be on the same Wi-Fi with Olive open. This phone shows a code; the other grown-up types it on '
      'their phone.',
      key: Key('addIntro'),
    ),
    const SizedBox(height: 12),
    TextField(
      key: const Key('addName'),
      controller: _name,
      maxLength: kJoinMaxName,
      decoration: const InputDecoration(labelText: 'Your name, as the other grown-up will see it'),
    ),
    if (_problem != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          _problem == 'no_wifi' ? 'This phone is not on a Wi-Fi network.' : joinRefusalText(_problem!),
          key: const Key('addProblem'),
        ),
      ),
    FilledButton(key: const Key('addStart'), onPressed: _busy ? null : _open, child: const Text('Show a code')),
  ];

  List<Widget> _window(FamilyJoinWindow w) {
    switch (w.state) {
      case JoinState.open:
        return <Widget>[
          const Text('On the other phone choose "Join another grown-up\'s phone", pick this window and type the code.'),
          const SizedBox(height: 12),
          Text('Window', style: Theme.of(context).textTheme.labelLarge),
          Text(w.label, key: const Key('addLabel'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('Code', style: Theme.of(context).textTheme.labelLarge),
          Text(w.code, key: const Key('addCode'), style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          const Text('It works for five minutes and one phone.'),
        ];
      case JoinState.waitingForYou:
        return <Widget>[
          Text('${w.guestName} wants to join your family.', key: const Key('addWho')),
          const SizedBox(height: 8),
          const Text(
            'Their screen should show this same word and picture. Only say yes if it does and you know who this is.',
          ),
          const SizedBox(height: 8),
          Text('${w.sas}', key: const Key('addWords'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('They will be able to see what you share with grown-ups, such as the emergency card.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(
                key: const Key('addApprove'),
                onPressed: () async {
                  final String? why = await w.approve();
                  if (why != null && mounted) setState(() => _problem = why);
                },
                child: const Text('Yes, add them'),
              ),
              OutlinedButton(key: const Key('addDecline'), onPressed: w.decline, child: const Text('No')),
            ],
          ),
        ];
      case JoinState.sending:
        return const <Widget>[Text('Adding their phone. Keep both phones on the Wi-Fi.', key: Key('addSending'))];
      case JoinState.done:
        return <Widget>[
          Text("${w.guestName ?? 'The other phone'} is added.", key: const Key('addDone')),
          const SizedBox(height: 8),
          const Text(
            'A new phone settles in for a while before it can receive pictures of a screen. The emergency card can be shared now.',
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
        ];
      case JoinState.closed:
        return <Widget>[
          Text(joinRefusalText(w.endedBecause ?? 'timeout'), key: const Key('addClosed')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => setState(() => _w = null), child: const Text('Start again')),
        ];
    }
  }
}

// ============================================================================================ joining a phone ===

class JoinGrownUpScreen extends StatefulWidget {
  const JoinGrownUpScreen({super.key, required this.hub, this.defaultName = ''});
  final FamilyHub hub;
  final String defaultName;
  @override
  State<JoinGrownUpScreen> createState() => _JoinGrownUpScreenState();
}

class _JoinGrownUpScreenState extends State<JoinGrownUpScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.defaultName);
  final TextEditingController _code = TextEditingController();
  List<RoadPeer> _windows = const <RoadPeer>[];
  String? _picked;
  Timer? _timer;
  bool _busy = false;
  Sas? _words;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.hub.browseForJoinWindows());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  void _poll() {
    if (!mounted || _busy) return;
    setState(() => _windows = widget.hub.joinWindowsSeen());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(widget.hub.stopBrowsingForJoin());
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final RoadPeer? win = _windows
        .where((RoadPeer p) => p.key == (_picked ?? (_windows.length == 1 ? _windows.first.key : null)))
        .firstOrNull;
    if (_busy || win == null) return;
    setState(() {
      _busy = true;
      _result = null;
      _words = null;
    });
    final JoinOutcome o = await widget.hub.joinFamily(
      window: win,
      code: _code.text.trim(),
      myName: _name.text.trim().isEmpty ? 'Grown-up' : _name.text.trim(),
      onWords: (Sas w) {
        if (mounted) setState(() => _words = w);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = o.ok;
      _result = o.ok
          ? 'You joined. Your phone settles in for a while before it can receive pictures of a screen.'
          : joinRefusalText(o.reason ?? 'x');
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? sel = _picked ?? (_windows.length == 1 ? _windows.first.key : null);
    return Scaffold(
      appBar: AppBar(title: const Text("Join another grown-up's phone")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'On the other phone choose "Add another grown-up\'s phone". Then pick its window here and type the code it shows.',
              key: Key('joinIntro'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('joinName'),
              controller: _name,
              maxLength: kJoinMaxName,
              decoration: const InputDecoration(labelText: 'Your name, as the other grown-up will see it'),
            ),
            const SizedBox(height: 8),
            Text('Windows nearby', style: Theme.of(context).textTheme.titleMedium),
            if (_windows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Looking. Both phones need the same Wi-Fi, with Olive open.', key: Key('joinNone')),
              ),
            RadioGroup<String>(
              groupValue: sel,
              onChanged: (String? v) => setState(() => _picked = v),
              child: Column(
                children: <Widget>[
                  for (final RoadPeer p in _windows)
                    RadioListTile<String>(key: Key('joinWindow_${p.label}'), title: Text(p.label), value: p.key),
                ],
              ),
            ),
            TextField(
              key: const Key('joinCode'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: kJoinCodeDigits,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'The six-digit code'),
            ),
            if (_words != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'This should be the same word and picture on the other phone. Waiting for them to say yes.',
                    ),
                    Text('$_words', key: const Key('joinWords'), style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_result!, key: const Key('joinResult')),
              ),
            if (_ok)
              FilledButton(
                key: const Key('joinDone'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              )
            else
              FilledButton(
                key: const Key('joinGo'),
                onPressed: _busy || sel == null || _code.text.trim().length != kJoinCodeDigits ? null : _join,
                child: const Text('Join'),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================================== keeping the road up ===

/// Sits above the grown-up app's navigator. Keeps the same-Wi-Fi road up while the app is in front and the family has
/// another grown-up (or an "add a grown-up" window is open), and takes it down when the app goes to the background. A
/// phone with no hub, and a child's device, never build this.
class FamilyRoadKeeper extends StatefulWidget {
  const FamilyRoadKeeper({super.key, required this.hub, required this.child});
  final FamilyHub? hub;
  final Widget child;
  @override
  State<FamilyRoadKeeper> createState() => _FamilyRoadKeeperState();
}

class _FamilyRoadKeeperState extends State<FamilyRoadKeeper> with WidgetsBindingObserver {
  bool _front = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.hub?.addListener(_changed);
    _go();
  }

  @override
  void didUpdateWidget(FamilyRoadKeeper old) {
    super.didUpdateWidget(old);
    if (!identical(old.hub, widget.hub)) {
      old.hub?.removeListener(_changed);
      widget.hub?.addListener(_changed);
      unawaited(old.hub?.stopRoad());
      _go();
    }
  }

  void _changed() {
    if (_front) _go();
  }

  void _go() {
    final FamilyHub? h = widget.hub;
    if (h != null && _front) unawaited(h.startRoad());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool front = state == AppLifecycleState.resumed;
    if (front == _front) return;
    _front = front;
    final FamilyHub? h = widget.hub;
    if (h == null) return;
    unawaited(front ? h.startRoad() : h.stopRoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hub?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
