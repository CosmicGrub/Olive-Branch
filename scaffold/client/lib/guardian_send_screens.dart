// OLIVE BRANCH — the guardian side of sending: the screens. UNVERIFIED on a real device and against a
// live server; its logic is run by CI (client/test/guardian_send_screens_test.dart). MASTERFILE §8.31, §8.2.3.
//
// Three screens, all for a grown-up, none reachable from her app:
//
//   GuardianComposeScreen   record or choose a video, say when it should arrive (a part of
//                           her day, or one named night), send. The video is saved on this
//                           phone before anything goes over the network, so a dropped signal
//                           loses nothing.
//   GuardianSentScreen      what is waiting on this phone and what the server says about what
//                           you sent: waiting, delivered, opened, in plain sentences. No counts.
//   DayPartsScreen          her day as a list of parts you can read and edit, with the same
//                           checks the server applies, shown before you save.
//
// Every time shown is HER wall clock (§8.2.3). A grown-up's own clock is never subtracted from it.
// Nothing here pretends: there is no "send right now" because the server has no such route
// (guardian_send_logic.dart says why), and a message the server has not confirmed is never
// described as sent.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'guardian_send_logic.dart';
import 'guardian_send_service.dart';

/// A video a grown-up recorded or chose: the bytes and how long it ran.
class PickedVideo {
  const PickedVideo(this.bytes, this.durationMs);
  final List<int> bytes;
  final int durationMs;
}

enum VideoSource { camera, gallery }

typedef VideoPickerFn = Future<PickedVideo?> Function(VideoSource source);

/// The real picker: image_picker's camera or gallery. No video-metadata probe exists in this
/// codebase, so the duration is the time spent inside the picker, floored at 1 ms (the same
/// honest approximation receipt_screen.dart makes), and it is never shown to the grown-up.
Future<PickedVideo?> defaultVideoPicker(VideoSource source) async {
  final DateTime started = DateTime.now();
  final XFile? f = await ImagePicker().pickVideo(
      source: source == VideoSource.camera ? ImageSource.camera : ImageSource.gallery);
  if (f == null) return null;
  final List<int> bytes = await f.readAsBytes();
  final int ms = DateTime.now().difference(started).inMilliseconds;
  return PickedVideo(bytes, ms > 0 ? ms : 1);
}

typedef NightPickerFn = Future<DateTime?> Function(BuildContext context, DateTime first, DateTime last);

Future<DateTime?> _defaultNightPicker(BuildContext context, DateTime first, DateTime last) =>
    showDatePicker(context: context, initialDate: first, firstDate: first, lastDate: last);

typedef TimePickerFn = Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial);

Future<TimeOfDay?> _defaultTimePicker(BuildContext context, TimeOfDay initial) =>
    showTimePicker(context: context, initialTime: initial);

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

Widget _note(BuildContext context, String text, {Key? key, bool problem = false}) {
  final ColorScheme c = Theme.of(context).colorScheme;
  return Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: problem ? c.errorContainer : c.secondaryContainer, borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(color: problem ? c.onErrorContainer : c.onSecondaryContainer)),
  );
}

// ==================================================================== compose

class GuardianComposeScreen extends StatefulWidget {
  const GuardianComposeScreen({
    super.key,
    required this.childName,
    required this.service,
    this.pickVideo = defaultVideoPicker,
    this.pickNight = _defaultNightPicker,
    this.pickTime = _defaultTimePicker,
    this.today,
  });

  final String childName;
  final GuardianSendService service;
  final VideoPickerFn pickVideo;
  final NightPickerFn pickNight;
  final TimePickerFn pickTime;
  /// For tests; the phone's date when null.
  final DateTime? today;

  @override
  State<GuardianComposeScreen> createState() => _GuardianComposeScreenState();
}

class _GuardianComposeScreenState extends State<GuardianComposeScreen> {
  List<DayPartEntry>? _parts; // null: not loaded (offline) or still loading
  bool _partsLoading = true;
  String? _nowLine;
  PickedVideo? _video;
  DeliveryKind _mode = DeliveryKind.atDayPart;
  String _partKind = 'bedtime';
  DateTime? _night;
  bool _sending = false;
  bool _waitingElsewhere = false;
  ComposeResult? _result;
  String? _pickProblem;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final DayPartsView v = await widget.service.loadDayParts();
      if (!mounted) return;
      setState(() {
        _parts = v.parts;
        if (v.parts.isNotEmpty && !v.parts.any((DayPartEntry p) => p.kind == _partKind)) {
          _partKind = v.parts.first.kind;
        }
      });
    } catch (_) {
      // Offline or refused: the composer still works with bedtime and the server checks.
    }
    try {
      final ({String? localTime, String? dayPart, bool? reachable}) n = await widget.service.fetchNow();
      if (mounted && n.localTime != null) {
        setState(() => _nowLine = "It is ${n.localTime} for ${widget.childName} right now.");
      }
    } catch (_) {/* optional */}
    try {
      // A message left from last time goes now if the server is back.
      await widget.service.flush();
      final bool waiting = await widget.service.hasQueued();
      if (mounted) setState(() => _waitingElsewhere = waiting);
    } catch (_) {/* optional */}
    if (mounted) setState(() => _partsLoading = false);
  }

  List<String> get _kinds {
    final List<DayPartEntry>? p = _parts;
    if (p == null || p.isEmpty) return const <String>['bedtime'];
    final Set<String> present = p.map((DayPartEntry e) => e.kind).toSet();
    final List<String> known = kDayPartKinds.where(present.contains).toList();
    return <String>[...known, ...present.where((String k) => !kDayPartKinds.contains(k))];
  }

  DeliveryChoice? get _choice {
    if (_mode == DeliveryKind.atDayPart) return DeliveryChoice.atDayPart(_partKind);
    final DateTime? n = _night;
    return n == null ? null : DeliveryChoice.onNight(formatNight(n), dayPart: _partKind);
  }

  DeliveryCheck? get _check {
    final DeliveryChoice? c = _choice;
    if (c == null) return null;
    return checkDelivery(c, _parts ?? const <DayPartEntry>[], today: _today);
  }

  Future<void> _pick(VideoSource s) async {
    setState(() => _pickProblem = null);
    try {
      final PickedVideo? v = await widget.pickVideo(s);
      if (!mounted || v == null) return;
      if (v.bytes.isEmpty) {
        setState(() => _pickProblem = 'That video was empty. Try again.');
      } else if (v.bytes.length > kMaxHeldBytes) {
        setState(() => _pickProblem =
            'That video is ${_mb(v.bytes.length)} MB, which is too large to send (the limit is '
            '${kMaxHeldBytes ~/ (1024 * 1024)} MB). Record a shorter one.');
      } else {
        setState(() {
          _video = v;
          _result = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickProblem = s == VideoSource.camera
          ? 'Olive could not open the camera. Check that it is allowed in your phone settings.'
          : 'Olive could not open your videos. Check that it is allowed in your phone settings.');
    }
  }

  Future<void> _pickNight() async {
    final DateTime t = DateTime(_today.year, _today.month, _today.day);
    final DateTime? d = await widget.pickNight(context, t, t.add(const Duration(days: kMaxNightsAhead)));
    if (d != null && mounted) setState(() => _night = DateTime.utc(d.year, d.month, d.day));
  }

  Future<void> _send() async {
    final PickedVideo? v = _video;
    final DeliveryChoice? c = _choice;
    final DeliveryCheck? chk = _check;
    if (_sending || v == null || c == null || chk == null || !chk.ok) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    ComposeResult r;
    try {
      r = await widget.service.compose(
          bytes: v.bytes, durationMs: v.durationMs, delivery: c, parts: _parts, today: _today);
    } catch (_) {
      r = const ComposeResult(ComposeOutcome.refused,
          'Something went wrong on this phone before the message could be saved. It was not sent.');
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = r;
      if (r.outcome == ComposeOutcome.sent || r.outcome == ComposeOutcome.savedWaiting ||
          r.outcome == ComposeOutcome.needsAttention) {
        _video = null; // it is saved (on the server or on this phone): do not offer it twice
        _waitingElsewhere = r.outcome != ComposeOutcome.sent || _waitingElsewhere;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryCheck? chk = _check;
    final bool canSend = !_sending && _video != null && chk != null && chk.ok;
    return Scaffold(
      appBar: AppBar(title: Text('Message to ${widget.childName}'), actions: <Widget>[
        IconButton(
          key: const Key('composeOpenSent'),
          tooltip: 'What you have sent',
          icon: const Icon(Icons.outbox_outlined),
          onPressed: _openSent,
        ),
      ]),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (_nowLine != null)
              Text(_nowLine!, key: const Key('composeNow'), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text('1. Your video', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Olive sends video messages. ${widget.childName} watches it on her tablet. '
                'It is kept for you in the archive.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              FilledButton.icon(
                key: const Key('composeRecord'),
                onPressed: _sending ? null : () => _pick(VideoSource.camera),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Record a video'),
              ),
              OutlinedButton.icon(
                key: const Key('composeChoose'),
                onPressed: _sending ? null : () => _pick(VideoSource.gallery),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Choose a video'),
              ),
            ]),
            if (_pickProblem != null) _note(context, _pickProblem!, key: const Key('composePickProblem'), problem: true),
            if (_video != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: <Widget>[
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Video ready (${_mb(_video!.bytes.length)} MB)', key: const Key('composeReady'))),
                  TextButton(
                      key: const Key('composeRemove'),
                      onPressed: _sending ? null : () => setState(() => _video = null),
                      child: const Text('Remove')),
                ]),
              ),
            const SizedBox(height: 20),
            Text('2. When should it arrive?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Times are on ${widget.childName}\'s clock, not yours. A message arrives when that part of her '
                'day starts. Olive cannot send one this very moment.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SegmentedButton<DeliveryKind>(
              key: const Key('composeMode'),
              segments: const <ButtonSegment<DeliveryKind>>[
                ButtonSegment<DeliveryKind>(value: DeliveryKind.atDayPart, label: Text('Next time')),
                ButtonSegment<DeliveryKind>(value: DeliveryKind.onNight, label: Text('A night I pick')),
              ],
              selected: <DeliveryKind>{_mode},
              onSelectionChanged: (Set<DeliveryKind> s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              for (final String k in _kinds)
                ChoiceChip(
                  key: Key('composePart_$k'),
                  label: Text(dayPartTitle(k)),
                  selected: _partKind == k,
                  onSelected: (_) => setState(() => _partKind = k),
                ),
            ]),
            if (_mode == DeliveryKind.onNight)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const Key('composeNight'),
                  onPressed: _pickNight,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_night == null ? 'Choose a night' : nightWords(formatNight(_night!))),
                ),
              ),
            if (_parts == null && !_partsLoading)
              _note(context,
                  'Olive could not check her day just now, so only Bedtime is offered. The server will confirm '
                  'the time when your message goes.',
                  key: const Key('composeNoParts')),
            if (_parts != null && _parts!.isEmpty)
              _note(context, "Her day has no parts yet. Set up her day first, so Olive knows when 'bedtime' is.",
                  key: const Key('composeEmptyDay'), problem: true),
            if (chk?.arrival != null) _note(context, chk!.arrival!, key: const Key('composeArrival')),
            if (chk != null)
              for (final String b in chk.blockers) _note(context, b, key: const Key('composeBlocker'), problem: true),
            if (chk != null)
              for (final String n in chk.notes) _note(context, n, key: const Key('composeCaution')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('composeSend'),
                onPressed: canSend ? _send : null,
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send'),
              ),
            ),
            if (_result != null)
              _note(context, _result!.words,
                  key: const Key('composeResult'),
                  problem: _result!.outcome == ComposeOutcome.refused ||
                      _result!.outcome == ComposeOutcome.needsAttention),
            if (_waitingElsewhere)
              _note(context, 'Some messages are waiting on this phone. You can see them under "What you have sent".',
                  key: const Key('composeWaitingNote')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: <Widget>[
              TextButton.icon(
                key: const Key('composeOpenSentLink'),
                onPressed: _openSent,
                icon: const Icon(Icons.outbox_outlined),
                label: const Text('What you have sent'),
              ),
              TextButton.icon(
                key: const Key('composeOpenDay'),
                onPressed: _openDay,
                icon: const Icon(Icons.schedule_outlined),
                label: Text("${widget.childName}'s day"),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _openSent() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GuardianSentScreen(childName: widget.childName, service: widget.service)));

  Future<void> _openDay() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DayPartsScreen(
            childName: widget.childName, service: widget.service, pickTime: widget.pickTime)));
    if (mounted) unawaited(_load()); // she may have a different day now
  }
}

// ===================================================================== sent

class GuardianSentScreen extends StatefulWidget {
  const GuardianSentScreen({
    super.key,
    required this.childName,
    required this.service,
    this.retryEvery = const Duration(seconds: 45),
  });

  final String childName;
  final GuardianSendService service;
  /// How often an open screen asks the outbox to try what is due. Tests pass a longer one.
  final Duration retryEvery;

  @override
  State<GuardianSentScreen> createState() => _GuardianSentScreenState();
}

class _GuardianSentScreenState extends State<GuardianSentScreen> {
  List<QueuedSend> _queued = const <QueuedSend>[];
  SentView? _sent;
  bool _loading = true;
  bool _couldNotAsk = false;
  List<DayPartEntry>? _parts;
  Timer? _timer;
  bool _busy = false;
  String? _line;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh(flush: true));
    _timer = Timer.periodic(widget.retryEvery, (_) {
      if (mounted && !_busy) unawaited(_refresh(flush: true));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool flush = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (flush) {
        try {
          await widget.service.flush();
        } catch (_) {/* shown below as a plain line */}
      }
      final List<QueuedSend> q = await widget.service.queued();
      SentView? s;
      bool failed = false;
      try {
        s = await widget.service.fetchSent();
      } catch (_) {
        failed = true;
      }
      if (_parts == null) {
        try {
          _parts = (await widget.service.loadDayParts()).parts;
        } catch (_) {/* only needed to change a time */}
      }
      if (!mounted) return;
      setState(() {
        _queued = q;
        _sent = s ?? _sent;
        _couldNotAsk = failed;
        _loading = false;
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _act(Future<ComposeResult> Function() run) async {
    final ComposeResult r = await run();
    if (!mounted) return;
    setState(() => _line = r.words);
    await _refresh();
  }

  Future<void> _discard(QueuedSend q) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Throw this message away?'),
        content: const Text('It has not reached the server. If you throw it away it is gone for good.'),
        actions: <Widget>[
          TextButton(key: const Key('discardNo'), onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(key: const Key('discardYes'), onPressed: () => Navigator.pop(c, true), child: const Text('Throw it away')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.service.discard(q.id);
    if (mounted) await _refresh();
  }

  Future<void> _change(QueuedSend q) async {
    final List<String> kinds = <String>[
      for (final String k in kDayPartKinds) if ((_parts ?? const <DayPartEntry>[]).any((DayPartEntry p) => p.kind == k)) k
    ];
    if (kinds.isEmpty) {
      setState(() => _line = "Her day has no parts to choose from. Set up her day first, then try again.");
      return;
    }
    final String? pick = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: const Text('When should it arrive?'),
        children: <Widget>[
          for (final String k in kinds)
            SimpleDialogOption(
                key: Key('changeTo_$k'), onPressed: () => Navigator.pop(c, k), child: Text(dayPartTitle(k))),
        ],
      ),
    );
    if (pick == null) return;
    await _act(() => widget.service.changeDelivery(q.id, DeliveryChoice.atDayPart(pick), parts: _parts));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('What you have sent'), actions: <Widget>[
        IconButton(
            key: const Key('sentRefresh'), tooltip: 'Check again', icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(flush: true)),
      ]),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                if (_line != null) _note(context, _line!, key: const Key('sentLine')),
                if (_queued.isNotEmpty) ...<Widget>[
                  Text('Waiting on this phone', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('These are saved here and have not reached the server yet.', style: theme.textTheme.bodySmall),
                  for (final QueuedSend q in _queued) _queuedCard(context, q),
                  const SizedBox(height: 16),
                ],
                Text('Sent to ${widget.childName}', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                if (_couldNotAsk)
                  _note(context,
                      'Olive could not check with the server just now, so this list may be out of date. '
                      'Messages waiting on this phone are shown above.',
                      key: const Key('sentOffline'), problem: true),
                if (_sent != null && _sent!.rows.isEmpty && !_couldNotAsk)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing sent yet.', key: const Key('sentEmpty'), style: theme.textTheme.bodyMedium)),
                if (_sent != null && _sent!.skipped > 0)
                  _note(context, 'Some entries could not be read by this version of Olive and are not shown.',
                      key: const Key('sentSkipped')),
                if (_sent != null)
                  for (final SentRow r in _sent!.rows) _sentCard(context, r, _sent!.setFor[r.id]),
              ]),
      ),
    );
  }

  Widget _queuedCard(BuildContext context, QueuedSend q) {
    final bool attention = q.phase == SendPhase.needsAttention;
    return Card(
      key: Key('queued_${q.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Video message · arrives ${deliveryPhrase(q.delivery)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(queuedStatusWords(q), key: Key('queuedStatus_${q.id}')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: <Widget>[
            if (attention)
              OutlinedButton(
                  key: Key('queuedChange_${q.id}'), onPressed: () => _change(q), child: const Text('Change when it arrives')),
            FilledButton.tonal(
                key: Key('queuedRetry_${q.id}'),
                onPressed: () => _act(() => widget.service.retry(q.id)),
                child: const Text('Try again')),
            TextButton(
                key: Key('queuedDiscard_${q.id}'), onPressed: () => _discard(q), child: const Text('Throw away')),
          ]),
        ]),
      ),
    );
  }

  Widget _sentCard(BuildContext context, SentRow r, String? setFor) {
    final String sent = r.sentAt == null ? 'Sent' : 'Sent ${dayWords(r.sentAt!)}';
    return Card(
      key: Key('sent_${r.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Video message · $sent', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(sentStatusWords(r, setFor: setFor), key: Key('sentStatus_${r.id}')),
        ]),
      ),
    );
  }
}

// ================================================================== day-parts

class DayPartsScreen extends StatefulWidget {
  const DayPartsScreen({
    super.key,
    required this.childName,
    required this.service,
    this.pickTime = _defaultTimePicker,
  });

  final String childName;
  final GuardianSendService service;
  final TimePickerFn pickTime;

  @override
  State<DayPartsScreen> createState() => _DayPartsScreenState();
}

class _DayPartsScreenState extends State<DayPartsScreen> {
  List<DayPartEntry> _baseline = const <DayPartEntry>[];
  List<DayPartEntry> _edited = const <DayPartEntry>[];
  int _skipped = 0;
  bool _loading = true;
  bool _saving = false;
  String? _loadProblem;
  String? _saveLine;
  bool _saveLineIsProblem = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadProblem = null;
    });
    try {
      final DayPartsView v = await widget.service.loadDayParts();
      if (!mounted) return;
      setState(() {
        _baseline = v.parts;
        _edited = v.parts;
        _skipped = v.skipped;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadProblem = "Olive could not reach the server to read her day. Nothing has changed. Try again when you are online.";
        _loading = false;
      });
    }
  }

  bool get _dirty => !sameSchedule(_baseline, _edited);

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveLine = null;
    });
    final DayPartsSaveResult r = await widget.service.saveDayParts(_edited, baseline: _baseline);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveLine = r.words;
      _saveLineIsProblem = r.status != DayPartsSaveStatus.saved;
      if (r.status == DayPartsSaveStatus.saved && r.view != null) {
        _baseline = r.view!.parts;
        _edited = r.view!.parts;
      } else if (r.status == DayPartsSaveStatus.changedElsewhere && r.view != null) {
        // Show their version; the grown-up's edits are discarded on purpose, because applying
        // them over a schedule they have not seen is the very mistake this check prevents.
        _baseline = r.view!.parts;
        _edited = r.view!.parts;
      }
    });
  }

  Future<void> _editPart(int? index) async {
    final DayPartEntry start = index == null
        ? const DayPartEntry(kind: 'free', startsLocal: '08:00', endsLocal: '15:00', reachable: true)
        : _edited[index];
    final DayPartEntry? result = await showDialog<DayPartEntry>(
      context: context,
      builder: (BuildContext c) => _PartDialog(initial: start, pickTime: widget.pickTime, isNew: index == null),
    );
    if (result == null || !mounted) return;
    setState(() {
      final List<DayPartEntry> next = <DayPartEntry>[..._edited];
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      _edited = next;
      _saveLine = null;
    });
  }

  void _remove(int i) => setState(() {
        _edited = <DayPartEntry>[..._edited]..removeAt(i);
        _saveLine = null;
      });

  @override
  Widget build(BuildContext context) {
    final DayPartsCheck check = checkDayParts(_edited);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s day")),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadProblem != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Text(_loadProblem!, key: const Key('dayLoadProblem'), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(key: const Key('dayRetry'), onPressed: _load, child: const Text('Try again')),
                      ]),
                    ))
                : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    Text(
                        'The parts of ${widget.childName}\'s day, in her own time. Messages you set for a part '
                        'arrive when it starts. Times are on her clock, whatever yours says.',
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                        'When a family is first set up, Olive fills in a plain starting day (waking, free time, '
                        'bedtime and sleep). Check these match her real days, and change what does not.',
                        key: const Key('dayPlaceholderNote'), style: theme.textTheme.bodySmall),
                    if (_skipped > 0)
                      _note(context,
                          'Her day holds a part this version of Olive cannot read, so it is not shown. '
                          'Saving is turned off so it cannot be lost. Update Olive to edit her day.',
                          key: const Key('daySkipped'), problem: true),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _edited.length; i++) _partCard(context, i, check),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('dayAdd'),
                      onPressed: _edited.length >= kMaxDayParts ? null : () => _editPart(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a part'),
                    ),
                    for (final DayPartProblem p in check.errors.where((DayPartProblem p) => p.index == null))
                      _note(context, p.text, key: const Key('dayError'), problem: true),
                    for (final String w in check.warnings) _note(context, w, key: const Key('dayWarning')),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        key: const Key('daySave'),
                        onPressed: (_dirty && check.canSave && !_saving && _skipped == 0) ? _save : null,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save her day'),
                      ),
                    ),
                    if (_dirty)
                      TextButton(
                          key: const Key('dayDiscard'),
                          onPressed: _saving ? null : () => setState(() => _edited = _baseline),
                          child: const Text('Undo my changes')),
                    if (_saveLine != null)
                      _note(context, _saveLine!, key: const Key('daySaveLine'), problem: _saveLineIsProblem),
                  ]),
      ),
    );
  }

  Widget _partCard(BuildContext context, int i, DayPartsCheck check) {
    final DayPartEntry p = _edited[i];
    final List<DayPartProblem> mine = check.errors.where((DayPartProblem e) => e.index == i).toList();
    return Card(
      key: Key('dayPart_$i'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(describeDayPart(p), key: Key('dayPartText_$i')),
          for (final DayPartProblem e in mine)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(e.text, key: Key('dayPartProblem_$i'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Wrap(spacing: 8, children: <Widget>[
            TextButton(key: Key('dayEdit_$i'), onPressed: () => _editPart(i), child: const Text('Change')),
            TextButton(
                key: Key('dayRemove_$i'),
                onPressed: _edited.length <= 1 ? null : () => _remove(i),
                child: const Text('Remove')),
          ]),
        ]),
      ),
    );
  }
}

class _PartDialog extends StatefulWidget {
  const _PartDialog({required this.initial, required this.pickTime, required this.isNew});
  final DayPartEntry initial;
  final TimePickerFn pickTime;
  final bool isNew;

  @override
  State<_PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends State<_PartDialog> {
  late DayPartEntry _e = widget.initial;

  Future<void> _time(bool start) async {
    final int m = parseHm(start ? _e.startsLocal : _e.endsLocal) ?? 0;
    final TimeOfDay? t = await widget.pickTime(context, TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null || !mounted) return;
    final String hm = formatHm(t.hour * 60 + t.minute);
    setState(() => _e = start ? _e.copyWith(startsLocal: hm) : _e.copyWith(endsLocal: hm));
  }

  @override
  Widget build(BuildContext context) {
    final DayPartsCheck one = checkDayParts(<DayPartEntry>[_e]);
    final List<DayPartProblem> problems = one.errors;
    return AlertDialog(
      title: Text(widget.isNew ? 'Add a part of her day' : 'Change this part'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          DropdownButton<String>(
            key: const Key('partKind'),
            isExpanded: true,
            value: kDayPartKinds.contains(_e.kind) ? _e.kind : null,
            items: <DropdownMenuItem<String>>[
              for (final String k in kDayPartKinds) DropdownMenuItem<String>(value: k, child: Text(dayPartTitle(k))),
            ],
            onChanged: (String? v) => setState(() => _e = _e.copyWith(kind: v ?? _e.kind)),
          ),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(
                child: OutlinedButton(
                    key: const Key('partStart'), onPressed: () => _time(true), child: Text('From ${hmTo12h(_e.startsLocal)}'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    key: const Key('partEnd'), onPressed: () => _time(false), child: Text('To ${hmTo12h(_e.endsLocal)}'))),
          ]),
          if (_e.wrapsMidnight)
            const Padding(
                padding: EdgeInsets.only(top: 6), child: Text('This runs overnight, into the next morning.', key: Key('partWraps'))),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
            for (int d = 0; d < 7; d++)
              FilterChip(
                key: Key('partDay_$d'),
                label: Text(weekdayShort(d)),
                selected: _e.days.contains(d),
                onSelected: (bool on) => setState(() {
                  final Set<int> s = _e.days.toSet();
                  on ? s.add(d) : s.remove(d);
                  _e = _e.copyWith(days: s.toList()..sort());
                }),
              ),
          ]),
          SwitchListTile(
            key: const Key('partReachable'),
            contentPadding: EdgeInsets.zero,
            title: const Text('She can be reached'),
            subtitle: const Text('Turn this off for times like school or sleep.'),
            value: _e.reachable,
            onChanged: (bool v) => setState(() => _e = _e.copyWith(reachable: v)),
          ),
          for (final DayPartProblem p in problems)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(p.text, key: const Key('partProblem'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
      actions: <Widget>[
        TextButton(key: const Key('partCancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            key: const Key('partOk'), onPressed: problems.isEmpty ? () => Navigator.pop(context, _e) : null, child: const Text('Done')),
      ],
    );
  }
}
