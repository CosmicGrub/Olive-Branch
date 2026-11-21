// OLIVE BRANCH — a lost or stolen phone or tablet: the adult screens. Verified headless
// (client/test/lost_device_screens_test.dart). MASTERFILE section 7.23.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.23).
//
// WHO SEES THESE. Grown-ups only. They are reached from Settings, Lost phone safety. They are NEVER reachable from a
// child's app, and a test fails if a child-side file imports this one. A child sees no PIN, code, count or error from
// any of it (P1 to P11), and no child's name, picture or score is on these screens.
//
// THE SCREEN. [YourDevicesScreen]: every phone and tablet of the family with one plain line about each ("Working
// normally", "You marked it as lost. It is paused ..."), and only the buttons that are true for that device right now:
//   Mark as lost       paused at once, nothing deleted, 3 days to change your mind.
//   I have it          it comes back; the owner types their own PIN once on that phone.
//   It is lost         the cut-off becomes final (a grown-up's phone: its owner only).
//   Erase it when it connects   (your OWN lost phone only, never a child's tablet) / Cancel the erase.
// Every action says what it does AND what it cannot do BEFORE the PIN is asked for, and asks for the grown-up's own PIN
// every time. Every failure is a sentence ([lostProblemFor]); nothing on a screen is a server code or a status.
//
// A phone that was itself marked as lost sees one card here instead of the list: what happened, that nothing was
// deleted, and a place to type its owner's own PIN once when it has been found ([PausedThisPhoneCard]).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'family_account_logic.dart';
import 'lost_device_logic.dart';
import 'lost_device_service.dart';
import 'recovery_paths_logic.dart' show RecoveryAction, recoveryProblemFor;
import 'screen_privacy.dart' show SensitiveScreen;

// ---- shared pieces ----------------------------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children, this.onRefresh});
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final Widget body = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
    return SensitiveScreen(
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body)),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.problem);
  final AccountProblem? problem;

  @override
  Widget build(BuildContext context) {
    final AccountProblem? p = problem;
    if (p == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Card(
          key: const Key('lostProblem'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(p.message, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PinBox extends StatelessWidget {
  const _PinBox({super.key, required this.controller, this.label = 'Your PIN'});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.number,
        maxLength: 8,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
      );
}

/// What an action does, what it cannot do, and the grown-up's own PIN. Returns the PIN, or null when they say "Not now".
/// The PIN is not kept.
Future<String?> _confirmWithPin(
  BuildContext context, {
  required String title,
  required String does,
  String? limits,
  required String yes,
}) {
  // Not disposed here: the dialog is still animating away when its future completes, and a disposed controller under a
  // live text field throws. It holds no listener, so the garbage collector takes it.
  final TextEditingController c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => SensitiveScreen(
      child: AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(does, key: const Key('confirmDoes')),
            if (limits != null) ...<Widget>[
              const SizedBox(height: 10),
              Text('What this cannot do', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(limits, key: const Key('confirmLimits')),
            ],
            const SizedBox(height: 14),
            _PinBox(key: const Key('confirmPinField'), controller: c),
          ]),
        ),
        actions: <Widget>[
          TextButton(key: const Key('confirmCancel'), onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          FilledButton(key: const Key('confirmYes'), onPressed: () => Navigator.pop(ctx, c.text), child: Text(yes)),
        ],
      ),
    ),
  );
}

// =====================================================================================================================
//  The list
// =====================================================================================================================

/// "Lost or stolen phone or tablet": every phone and tablet of the family, and what may be done about each.
class YourDevicesScreen extends StatefulWidget {
  const YourDevicesScreen({super.key, required this.service, this.now});
  final LostDeviceService service;
  final DateTime Function()? now;

  @override
  State<YourDevicesScreen> createState() => _YourDevicesScreenState();
}

class _YourDevicesScreenState extends State<YourDevicesScreen> {
  List<FamilyDevice>? _devices;
  bool _loading = true;
  bool _busy = false;
  bool _thisPhonePaused = false;
  AccountProblem? _problem;
  String? _done;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<FamilyDevice> d = await widget.service.devices();
      if (!mounted) return;
      setState(() {
        _devices = d;
        _loading = false;
        _thisPhonePaused = false;
        _problem = null;
      });
    } on AccountFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _thisPhonePaused = e.problem.reason == 'device_paused';
        _problem = _thisPhonePaused ? null : e.problem;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = lostProblemFor(e, LostAction.load);
      });
    }
  }

  /// Runs one action; its sentence goes on the screen either way, then the list is read again.
  Future<void> _run(Future<DeviceActionResult> Function() action, String doneText) async {
    setState(() {
      _busy = true;
      _problem = null;
      _done = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = doneText;
      });
    } on AccountFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.problem;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = lostProblemFor(e, LostAction.load);
      });
    }
    if (mounted) await _load();
  }

  Future<void> _mark(FamilyDevice d) async {
    final String? pin = await _confirmWithPin(context,
        title: 'Mark ${d.title} as lost?',
        does: markLostExplanation(d),
        limits: markLostLimits(d),
        yes: 'Mark as lost');
    if (pin == null || !mounted) return;
    await _run(() => widget.service.markLost(deviceId: d.id, pin: pin),
        '${d.title} is marked as lost and paused. $kNothingDeleted');
  }

  Future<void> _found(FamilyDevice d) async {
    final String? incident = d.incidentId;
    if (incident == null) return;
    final String? pin = await _confirmWithPin(context,
        title: 'You have ${d.title}?',
        does: d.isTablet
            ? 'It comes back and gets updates again. Nothing was lost while it was paused.'
            : 'It comes back. The owner types their own PIN once on that phone, and then it works as before. Nothing was lost '
                'while it was paused.',
        yes: 'I have it');
    if (pin == null || !mounted) return;
    await _run(() => widget.service.found(deviceId: d.id, incidentId: incident, pin: pin),
        d.isTablet ? '${d.title} is back.' : '${d.title} is back. Its owner types their own PIN once on it.');
  }

  Future<void> _confirmLost(FamilyDevice d) async {
    final String? incident = d.incidentId;
    if (incident == null) return;
    final String? pin = await _confirmWithPin(context,
        title: 'Cut ${d.title} off for good?',
        does: 'It will never get anything from your family again. $kNothingDeleted If it turns up, it can only come back by '
            'being added to your family again, like a new one.',
        limits: markLostLimits(d),
        yes: 'It is lost');
    if (pin == null || !mounted) return;
    await _run(() => widget.service.confirmLost(deviceId: d.id, incidentId: incident, pin: pin),
        '${d.title} is cut off for good. $kNothingDeleted');
  }

  Future<void> _erase(FamilyDevice d) async {
    final String? pin = await _confirmWithPin(context,
        title: "Erase Olive's copy on ${d.title}?",
        does: kEraseExplanation,
        limits: kEraseLimits,
        yes: 'Erase it when it connects');
    if (pin == null || !mounted) return;
    await _run(() => widget.service.orderWipe(deviceId: d.id, pin: pin),
        "Done. The next time that phone is online it will erase Olive's copy. Your family's records are not touched.");
  }

  Future<void> _cancelErase(FamilyDevice d) async {
    final String? pin = await _confirmWithPin(context,
        title: 'Cancel the erase?',
        does: 'The phone will keep its copy, and Olive on it will not be told to erase anything. You can ask again later.',
        yes: 'Cancel the erase');
    if (pin == null || !mounted) return;
    await _run(() => widget.service.cancelWipe(deviceId: d.id, pin: pin), 'The erase was cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    final List<FamilyDevice>? devices = _devices;
    return _Page(
      title: 'Lost or stolen phone or tablet',
      onRefresh: _load,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'If a phone or tablet is lost, mark it here. It stops getting anything new from your family right away, and '
            'nothing is deleted. You can change your mind for 3 days.',
            style: Theme.of(context).textTheme.bodyMedium,
            key: const Key('devicesIntro'),
          ),
        ),
        if (_done != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Card(
                key: const Key('lostDone'),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_done!)),
              ),
            ),
          ),
        _Problem(_problem),
        if (_thisPhonePaused)
          PausedThisPhoneCard(
              service: widget.service,
              onBack: () {
                setState(() => _loading = true);
                unawaited(_load());
              }),
        if (_loading && devices == null && !_thisPhonePaused)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (devices != null && devices.isEmpty)
          const Text('There are no other phones or tablets in your family yet.', key: Key('noDevices')),
        if (devices != null)
          for (final FamilyDevice d in devices) _DeviceCard(
            device: d,
            now: _now(),
            busy: _busy,
            onMark: () => _mark(d),
            onFound: () => _found(d),
            onConfirm: () => _confirmLost(d),
            onErase: () => _erase(d),
            onCancelErase: () => _cancelErase(d),
          ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.now,
    required this.busy,
    required this.onMark,
    required this.onFound,
    required this.onConfirm,
    required this.onErase,
    required this.onCancelErase,
  });
  final FamilyDevice device;
  final DateTime now;
  final bool busy;
  final VoidCallback onMark, onFound, onConfirm, onErase, onCancelErase;

  @override
  Widget build(BuildContext context) {
    final FamilyDevice d = device;
    final ThemeData theme = Theme.of(context);
    final String? wipeLine = wipeStatusLine(d);
    return Card(
      key: Key('device_${d.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(d.isTablet ? Icons.tablet_android_outlined : Icons.smartphone_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(d.title, style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 6),
          Text(deviceStatusLine(d, now), key: Key('status_${d.id}')),
          if (wipeLine != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(wipeLine, key: Key('wipe_${d.id}')),
          ],
          if (d.canMarkLost || d.canFound || d.canConfirmLost || d.canOrderWipe || d.canCancelWipe) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              if (d.canMarkLost)
                OutlinedButton(key: Key('markLost_${d.id}'), onPressed: busy ? null : onMark, child: const Text('Mark as lost')),
              if (d.canFound)
                FilledButton(key: Key('found_${d.id}'), onPressed: busy ? null : onFound, child: const Text('I have it')),
              if (d.canConfirmLost)
                OutlinedButton(key: Key('confirmLost_${d.id}'), onPressed: busy ? null : onConfirm, child: const Text('It is lost')),
              if (d.canOrderWipe)
                OutlinedButton(
                    key: Key('erase_${d.id}'), onPressed: busy ? null : onErase, child: const Text('Erase it when it connects')),
              if (d.canCancelWipe)
                TextButton(key: Key('cancelErase_${d.id}'), onPressed: busy ? null : onCancelErase, child: const Text('Cancel the erase')),
            ]),
          ],
        ]),
      ),
    );
  }
}

// =====================================================================================================================
//  This phone, when it is the one that was marked as lost
// =====================================================================================================================

/// What a phone sees when a grown-up marked IT as lost: what happened, that nothing was deleted, and a place for its
/// owner to type their own PIN once when it has been found. The PIN is held only for that one request.
class PausedThisPhoneCard extends StatefulWidget {
  const PausedThisPhoneCard({super.key, required this.service, this.onBack});
  final LostDeviceService service;
  final VoidCallback? onBack;

  @override
  State<PausedThisPhoneCard> createState() => _PausedThisPhoneCardState();
}

class _PausedThisPhoneCardState extends State<PausedThisPhoneCard> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  AccountProblem? _problem;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _again() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.service.resumeThisPhone(pin: _pin.text);
      _pin.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onBack?.call();
    } on AccountFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.problem;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = recoveryProblemFor(e, RecoveryAction.loadSummary);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('pausedThisPhone'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(kPausedPhoneTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(kPausedPhoneBody),
            const SizedBox(height: 12),
            _Problem(_problem),
            _PinBox(key: const Key('resumePinField'), controller: _pin),
            const SizedBox(height: 12),
            FilledButton(
                key: const Key('resumeThisPhone'),
                onPressed: _busy ? null : _again,
                child: const Text('Use this phone again')),
          ]),
        ),
      );
}
