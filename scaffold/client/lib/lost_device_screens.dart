// OLIVE BRANCH — the screens of a lost or stolen phone or tablet. UNVERIFIED on a device; widget-tested headless
// (client/test/lost_device_screens_test.dart).
//
// TWO PLACES.
//  1. [PhonesAndTabletsScreen], on a GROWN-UP'S phone: every phone and tablet of the family, what each one's standing is,
//     and the five things a grown-up can say about one (mark it as lost, I have it, it is lost, erase it when it next
//     connects, call the erase off). Each behind that grown-up's own PIN. Plain adult words from lost_device_words.dart.
//  2. [DeviceStandingGuard], around a grown-up's app: when THIS phone was marked as lost, brought back and waiting for
//     its owner's PIN, cut off, or erased, the app is covered and says so calmly. It stays alive underneath (nothing is
//     lost) but is neither drawn nor reachable.
//
// A CHILD NEVER SEES ANY OF THIS. Neither widget is ever built by the child shell, a child's tablet shows no notice,
// count or reason, and nothing here has a place, a map or a name of a network in it (MASTERFILE section 2.1; P1 to P11).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter, TextInputFormatter;

import 'auth_session.dart';
import 'device_standing.dart';
import 'lost_device_logic.dart';
import 'lost_device_words.dart';

// ---------------------------------------------------------------------------------------------------------------
// 1. Phones and tablets
// ---------------------------------------------------------------------------------------------------------------

class PhonesAndTabletsScreen extends StatefulWidget {
  const PhonesAndTabletsScreen({super.key, required this.actions, this.childName, this.now});
  final LostDeviceActions actions;

  /// The first name of her whose tablet it is, for "Ivy's tablet". Null reads "A child's tablet".
  final String? childName;
  final DateTime Function()? now;

  @override
  State<PhonesAndTabletsScreen> createState() => _PhonesAndTabletsScreenState();
}

class _PhonesAndTabletsScreenState extends State<PhonesAndTabletsScreen> {
  List<FamilyDeviceView>? _devices;
  String? _loadError;
  String? _done;
  bool _busy = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<FamilyDeviceView> d = await widget.actions.load();
      if (!mounted) return;
      setState(() {
        _devices = d;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = LostDeviceWords.loadError);
    }
  }

  /// Asks for the PIN, runs [call], and shows either the plain "done" line or the plain refusal.
  Future<void> _act({
    required String title,
    required List<String> lines,
    required String button,
    required String doneLine,
    required Future<LostActionResult> Function(String pin) call,
    Key? confirmKey,
  }) async {
    final String? pin = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => _PinDialog(title: title, lines: lines, button: button, confirmKey: confirmKey),
    );
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _done = null;
    });
    final LostActionResult r = await call(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = r.ok ? doneLine : _refusalLine(r.error ?? 'error');
    });
    await _load();
  }

  String _refusalLine(String error) => switch (error) {
        'pin_incorrect' => LostDeviceWords.pinWrong,
        'pin_locked' => LostDeviceWords.pinLocked,
        _ => LostDeviceWords.refusal(error),
      };

  String _name(FamilyDeviceView d) => d.displayName(childName: widget.childName);

  String _stateLine(FamilyDeviceView d) {
    if (d.erased) return LostDeviceWords.erasedLine;
    if (d.isRevoked) return LostDeviceWords.removedLine;
    if (d.isPaused) {
      final DateTime? due = d.revokeDueAt;
      final String base = LostDeviceWords.pausedLine(
          markedBy: d.markedByMe ? null : d.markedByName, endsIn: due == null ? 'about 3 days' : LostDeviceWords.endsIn(due, _now));
      final DateTime? erase = d.eraseDueAt;
      if (d.eraseOrdered && erase != null) {
        return '$base ${LostDeviceWords.eraseOrderedLine(LostDeviceWords.endsIn(erase, _now))}';
      }
      return base;
    }
    return '';
  }

  List<Widget> _buttons(FamilyDeviceView d) {
    final String name = _name(d);
    final String inc = d.incidentId ?? '';
    return <Widget>[
      if (d.canMarkLost)
        OutlinedButton(
          key: Key('mark-${d.id}'),
          onPressed: _busy
              ? null
              : () => _act(
                    title: LostDeviceWords.markTitle(name: d.isChild ? (widget.childName ?? '') : (d.ownerName ?? ''), isChild: d.isChild, isOwn: d.isOwn),
                    lines: <String>[
                      ...LostDeviceWords.markLines,
                      LostDeviceWords.markToldLine(isOwn: d.isOwn, isChild: d.isChild, name: d.ownerName ?? ''),
                      LostDeviceWords.pinWhy,
                    ],
                    button: LostDeviceWords.markButton,
                    doneLine: LostDeviceWords.markedDone(name),
                    call: (String pin) => widget.actions.mark(d.id, pin),
                    confirmKey: const Key('pinConfirm'),
                  ),
          child: const Text(LostDeviceWords.markButton),
        ),
      if (d.canFound)
        FilledButton(
          key: Key('found-${d.id}'),
          onPressed: _busy
              ? null
              : () => _act(
                    title: LostDeviceWords.foundButton,
                    lines: const <String>[LostDeviceWords.pinWhy],
                    button: LostDeviceWords.foundButton,
                    doneLine: LostDeviceWords.foundDone,
                    call: (String pin) => widget.actions.found(d.id, inc, pin),
                    confirmKey: const Key('pinConfirm'),
                  ),
          child: const Text(LostDeviceWords.foundButton),
        ),
      if (d.canConfirmLost)
        OutlinedButton(
          key: Key('confirm-${d.id}'),
          onPressed: _busy
              ? null
              : () => _act(
                    title: LostDeviceWords.confirmLostTitle,
                    lines: const <String>[LostDeviceWords.confirmLostBody, LostDeviceWords.pinWhy],
                    button: LostDeviceWords.confirmLostButton,
                    doneLine: LostDeviceWords.lostDone,
                    call: (String pin) => widget.actions.confirmLost(d.id, inc, pin),
                    confirmKey: const Key('pinConfirm'),
                  ),
          child: const Text(LostDeviceWords.lostButton),
        ),
      if (d.canOrderErase)
        OutlinedButton(
          key: Key('erase-${d.id}'),
          onPressed: _busy
              ? null
              : () => _act(
                    title: LostDeviceWords.eraseTitle(name),
                    lines: <String>[...LostDeviceWords.eraseLines, LostDeviceWords.pinWhy],
                    button: LostDeviceWords.eraseButton,
                    doneLine: LostDeviceWords.eraseOrderedDone,
                    call: (String pin) => widget.actions.orderErase(d.id, inc, pin),
                    confirmKey: const Key('pinConfirm'),
                  ),
          child: const Text(LostDeviceWords.eraseButton),
        ),
      if (d.canCancelErase)
        OutlinedButton(
          key: Key('cancelErase-${d.id}'),
          onPressed: _busy
              ? null
              : () => _act(
                    title: LostDeviceWords.eraseCancelButton,
                    lines: const <String>[LostDeviceWords.pinWhy],
                    button: LostDeviceWords.eraseCancelButton,
                    doneLine: LostDeviceWords.eraseCancelDone,
                    call: (String pin) => widget.actions.cancelErase(d.id, inc, pin),
                    confirmKey: const Key('pinConfirm'),
                  ),
          child: const Text(LostDeviceWords.eraseCancelButton),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<FamilyDeviceView>? list = _devices;
    return Scaffold(
      appBar: AppBar(title: const Text(LostDeviceWords.screenTitle)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              const Text(LostDeviceWords.screenIntro),
              const SizedBox(height: 8),
              const Text(kLostHonestLimit, key: Key('honestLimit')),
              if (_done != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_done!, key: const Key('doneLine'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
              if (_loadError != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_loadError!, key: const Key('loadError')),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
              if (list == null && _loadError == null) const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              for (final FamilyDeviceView d in list ?? const <FamilyDeviceView>[])
                Card(
                  key: Key('device-${d.id}'),
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(_name(d), style: Theme.of(context).textTheme.titleMedium),
                      if (_stateLine(d).isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_stateLine(d), key: Key('state-${d.id}')),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: _buttons(d)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grown-up's own PIN, asked for in the plain sentences that say what is about to happen. Returns the PIN typed, or
/// null when they chose Not now. It never remembers the PIN.
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.lines, required this.button, this.confirmKey});
  final String title, button;
  final List<String> lines;
  final Key? confirmKey;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  bool get _ok => RegExp(r'^[0-9]{4,8}$').hasMatch(_pin.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            for (final String l in widget.lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l)),
            TextField(
              key: const Key('pinField'),
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(labelText: LostDeviceWords.pinTitle),
              onChanged: (_) => setState(() {}),
            ),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(LostDeviceWords.notNow)),
          FilledButton(
            key: widget.confirmKey,
            onPressed: _ok ? () => Navigator.of(context).pop(_pin.text) : null,
            child: Text(widget.button),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------------------------------------------
// 2. The cover on a lost phone
// ---------------------------------------------------------------------------------------------------------------

/// Asks the family's server again where this phone stands, with the owner's PIN when it was brought back. Returns the
/// standing afterwards. Never throws.
typedef CheckBack = Future<DeviceStandingState> Function(String? ownerPin);

Future<DeviceStandingState> _defaultCheckBack(String? ownerPin) async {
  final AuthSession? s = AuthSession.current;
  if (s == null) return DeviceStanding.value;
  return s.checkBack(ownerPin: ownerPin);
}

class DeviceStandingGuard extends StatelessWidget {
  const DeviceStandingGuard({super.key, required this.child, this.checkBack = _defaultCheckBack});
  final Widget child;
  final CheckBack checkBack;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DeviceStandingState>(
        valueListenable: DeviceStanding.state,
        child: child,
        builder: (BuildContext context, DeviceStandingState s, Widget? app) {
          final bool covered = s != DeviceStandingState.active;
          return Stack(textDirection: TextDirection.ltr, children: <Widget>[
            Positioned.fill(child: Visibility(visible: !covered, maintainState: true, child: app!)),
            if (covered)
              Positioned.fill(
                // keyed by the standing: an Overlay reads its entries once, so a new standing needs a new Overlay
                child: Overlay(key: ValueKey<DeviceStandingState>(s), initialEntries: <OverlayEntry>[
                  OverlayEntry(builder: (BuildContext _) => StandingCover(state: s, checkBack: checkBack)),
                ]),
              ),
          ]);
        },
      );
}

/// What the lost phone itself says. Plain, calm, no fear words, no name of anyone, no place.
class StandingCover extends StatefulWidget {
  const StandingCover({super.key, required this.state, required this.checkBack});
  final DeviceStandingState state;
  final CheckBack checkBack;

  @override
  State<StandingCover> createState() => _StandingCoverState();
}

class _StandingCoverState extends State<StandingCover> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  String? _line;

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check({String? pin}) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final DeviceStandingState was = DeviceStanding.value;
    final DeviceStandingState now = await widget.checkBack(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (now == was && pin == null) {
        _line = LostDeviceWords.pausedStillPaused;
      } else if (now == was && pin != null) {
        _line = (AuthSession.current?.lastPinError == null) ? null : LostDeviceWords.pinWrong;
      }
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final (String title, String body) = switch (widget.state) {
      DeviceStandingState.paused => (LostDeviceWords.pausedCoverTitle, LostDeviceWords.pausedCoverBody),
      DeviceStandingState.needsOwnerPin => (LostDeviceWords.pinCoverTitle, LostDeviceWords.pinCoverBody),
      DeviceStandingState.cutOff => (LostDeviceWords.cutOffCoverTitle, LostDeviceWords.cutOffCoverBody),
      DeviceStandingState.erased => (LostDeviceWords.erasedCoverTitle, LostDeviceWords.erasedCoverBody),
      DeviceStandingState.active => ('', ''),
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(title, key: const Key('coverTitle'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(body, key: const Key('coverBody')),
                const SizedBox(height: 16),
                if (widget.state == DeviceStandingState.paused)
                  FilledButton(
                    key: const Key('checkAgain'),
                    onPressed: _busy ? null : () => _check(),
                    child: const Text(LostDeviceWords.checkAgain),
                  ),
                if (widget.state == DeviceStandingState.cutOff || widget.state == DeviceStandingState.erased)
                  const FilledButton(
                    key: Key('addAgain'),
                    onPressed: DeviceStanding.addedAgain,
                    child: Text(LostDeviceWords.addAgainButton),
                  ),
                if (widget.state == DeviceStandingState.needsOwnerPin) ...<Widget>[
                  TextField(
                    key: const Key('coverPin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(labelText: LostDeviceWords.pinTitle),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('checkPin'),
                    onPressed: _busy ? null : () => _check(pin: _pin.text),
                    child: const Text(LostDeviceWords.pinCoverButton),
                  ),
                ],
                if (_line != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_line!, key: const Key('coverLine')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// 3. The quiet notice on a grown-up's home
// ---------------------------------------------------------------------------------------------------------------

/// What a grown-up is told, on their own home, when a phone or tablet of the family is marked as lost (screens L2 and
/// L3), or when a lost phone has been told to erase its own copy. Calm, dismissible for this run, never red, never a
/// count. It asks the family's server when the home opens and again when the app comes back to the front; with no
/// signal it shows nothing and says nothing (the list screen is where a missing connection is said). Nothing in it is
/// ever shown to a child: only a grown-up's home builds it.
class LostDeviceNotice extends StatefulWidget {
  const LostDeviceNotice({super.key, required this.actions, required this.onOpen, this.childName});
  final LostDeviceActions actions;

  /// Opens "Phones and tablets" (the grown-up then answers behind their own PIN).
  final VoidCallback onOpen;
  final String? childName;

  @override
  State<LostDeviceNotice> createState() => _LostDeviceNoticeState();
}

class _LostDeviceNoticeState extends State<LostDeviceNotice> with WidgetsBindingObserver {
  List<FamilyDeviceView> _paused = const <FamilyDeviceView>[];
  final Set<String> _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<FamilyDeviceView> all = await widget.actions.load();
      if (!mounted) return;
      setState(() => _paused = <FamilyDeviceView>[
            for (final FamilyDeviceView d in all)
              if (d.isPaused && !d.isThisDevice && d.incidentId != null) d,
          ]);
    } catch (_) {
      // no signal, or not signed in yet: nothing to say
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<FamilyDeviceView> shown = <FamilyDeviceView>[
      for (final FamilyDeviceView d in _paused)
        if (!_dismissed.contains('${d.id}/${d.incidentId}/${d.eraseOrdered}')) d,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(children: <Widget>[
      for (final FamilyDeviceView d in shown.take(2))
        Container(
          key: Key('lostNotice-${d.id}'),
          width: double.infinity,
          color: cs.secondaryContainer,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(
              d.isOwn
                  ? LostDeviceWords.ownerTitle()
                  : LostDeviceWords.noticeTitle(d.displayName(childName: widget.childName)),
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: 2),
            Text(
              d.isOwn
                  ? LostDeviceWords.ownerBody(d.markedByMe ? '' : (d.markedByName ?? ''))
                  : LostDeviceWords.noticeLines.join(' '),
              style: TextStyle(color: cs.onSecondaryContainer),
            ),
            if (d.eraseOrdered) Text(
              '${LostDeviceWords.noticeEraseOrderedTitle}. ${LostDeviceWords.noticeEraseOrderedLine}',
              key: Key('lostNoticeErase-${d.id}'),
              style: TextStyle(color: cs.onSecondaryContainer),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
              TextButton(
                key: Key('lostNoticeOk-${d.id}'),
                onPressed: () => setState(() => _dismissed.add('${d.id}/${d.incidentId}/${d.eraseOrdered}')),
                child: const Text('OK'),
              ),
              TextButton(
                key: Key('lostNoticeOpen-${d.id}'),
                onPressed: widget.onOpen,
                child: Text(d.isOwn ? LostDeviceWords.foundButton : LostDeviceWords.screenTitle),
              ),
            ]),
          ]),
        ),
    ]);
  }
}
