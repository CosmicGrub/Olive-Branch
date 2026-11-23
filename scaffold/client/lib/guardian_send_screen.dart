// OLIVE BRANCH — "Send to her": a grown-up makes something and chooses when it arrives. Verified headless
// (client/test/guardian_send_screen_test.dart). MASTERFILE section 8.31.
//
// UNVERIFIED on a real device or against a live server from the phone: covered by flutter test only.
//
// This is the guardian half of the delivery chain made real. It sends through the real routes
// (guardian_send_service.dart), warns with the real send-time guard fed by her real schedule and the real
// clock check (guardian_send_logic.dart sendGuard), and shows what really happened to everything sent in plain
// adult words: waiting, delivered, opened, with her time and the server's own receipt sentence. Nothing here
// says "sent" until the server has taken it, and what could not be sent is shown as saved on this phone, with
// the reason, never as a quiet success.
//
// It replaces the demo "Message banking" screen on a phone that has a live session. The demo stays in the
// offline preview, where it is labelled for what it is. What it does not do: take a message back once the
// server has it (there is no such route), send text on its own (the server carries recordings and photos), or
// retry while the app is closed.
//
// This is a grown-up's screen. She never sees it, and nothing on it is drawn to her.
import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'auth_session.dart';
import 'day_parts_editor_screen.dart';
import 'day_parts_service.dart';
import 'guardian_send_logic.dart';
import 'guardian_send_service.dart';

enum PickSource { recordVideo, takePhoto, chooseFromPhone }

/// Something the grown-up made or chose, read into memory.
class PickedMedia {
  const PickedMedia({required this.bytes, required this.kind, required this.durationMs});
  final List<int> bytes;
  final MediaKind kind;
  final int durationMs;
}

typedef MediaPicker = Future<PickedMedia?> Function(PickSource source);
typedef NightPicker = Future<DateTime?> Function(BuildContext context, DateTime first, DateTime last);

/// The longest a recording made here may run, so it fits on the phone while it waits.
const Duration kRecordLimit = Duration(seconds: 20);

Future<PickedMedia?> _defaultPick(PickSource source) async {
  final ImagePicker picker = ImagePicker();
  final DateTime started = DateTime.now();
  XFile? f;
  switch (source) {
    case PickSource.recordVideo:
      f = await picker.pickVideo(source: ImageSource.camera, maxDuration: kRecordLimit);
    case PickSource.takePhoto:
      f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
    case PickSource.chooseFromPhone:
      f = await picker.pickMedia();
  }
  if (f == null) return null;
  final List<int> bytes = await File(f.path).readAsBytes();
  final MediaKind? kind = sniffSendKind(bytes);
  if (kind == null) throw const FormatException('unsupported');
  final int elapsed = DateTime.now().difference(started).inMilliseconds;
  // No video metadata probe exists in this app, so a recording's length is the time spent in the camera (floored at
  // 1 ms: the server only needs it above zero). A photo has none.
  final int ms = kind == MediaKind.photo ? 1 : (elapsed > 0 ? elapsed : 1);
  return PickedMedia(bytes: bytes, kind: kind, durationMs: ms);
}

Future<DateTime?> _defaultNightPicker(BuildContext context, DateTime first, DateTime last) =>
    showDatePicker(context: context, initialDate: first, firstDate: first, lastDate: last);

class GuardianSendScreen extends StatefulWidget {
  const GuardianSendScreen({
    super.key,
    required this.childName,
    required this.childId,
    required this.openApi,
    required this.outbox,
    this.closeApi = true,
    this.pickMedia,
    this.pickNight,
    this.retryEvery = const Duration(seconds: 45),
    this.nowMs,
  });

  /// The live screen: a real session for [guardianId] against [baseUrl], the sealed on-device outbox.
  factory GuardianSendScreen.live({
    Key? key,
    required String baseUrl,
    required String guardianId,
    required String childId,
    required String childName,
    http.Client? httpClient,
  }) =>
      GuardianSendScreen(
        key: key,
        childName: childName,
        childId: childId,
        openApi: () => apiFor(baseUrl, userId: guardianId, childId: childId, client: httpClient),
        outbox: LocalStoreSendOutbox.forGuardian(guardianId),
        closeApi: httpClient == null,
      );

  final String childName;
  final String childId;
  final ApiOpener openApi;
  final SendOutbox outbox;
  final bool closeApi;
  final MediaPicker? pickMedia;
  final NightPicker? pickNight;

  /// How often to try the outbox again while the screen is open; null for never (tests).
  final Duration? retryEvery;
  final MsClock? nowMs;

  @override
  State<GuardianSendScreen> createState() => _GuardianSendScreenState();
}

enum _Tone { good, info, bad }

class _GuardianSendScreenState extends State<GuardianSendScreen> {
  late final GuardianSendService _service;
  late final DayPartsService _days;
  Timer? _timer;

  List<DayPartSpan>? _parts;
  String? _nowDayPart;
  bool? _reachable;
  List<SentEntry> _sent = const <SentEntry>[];
  bool _sentLoaded = false;
  String? _sentError;
  List<QueuedSend> _waiting = const <QueuedSend>[];

  PickedMedia? _media;
  SendMode _mode = SendMode.atDayPart;
  String _daypartKind = 'bedtime';
  String? _night;

  bool _busy = false;
  bool _loading = true;
  String? _result;
  _Tone _tone = _Tone.info;

  @override
  void initState() {
    super.initState();
    _service = GuardianSendService(
      childId: widget.childId,
      childName: widget.childName,
      openApi: widget.openApi,
      outbox: widget.outbox,
      closeApi: widget.closeApi,
      nowMs: widget.nowMs,
    );
    _days = DayPartsService(childId: widget.childId, openApi: widget.openApi, closeApi: widget.closeApi);
    _refresh();
    final Duration? every = widget.retryEvery;
    if (every != null) _timer = Timer.periodic(every, (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DeliveryChoice get _choice => switch (_mode) {
        SendMode.now => const DeliveryChoice.now(),
        SendMode.atDayPart => DeliveryChoice.atDayPart(_daypartKind),
        SendMode.onNight => DeliveryChoice.onNight(_night ?? ''),
      };

  /// Tries the outbox, then reads what the server says: her schedule, this moment in her day, and what was sent.
  Future<void> _refresh({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      await _service.flush();
    } catch (_) {/* shown below as still waiting */}
    List<DayPartSpan>? parts = _parts;
    String? nowPart = _nowDayPart;
    bool? reachable = _reachable;
    List<SentEntry> sent = _sent;
    bool sentLoaded = _sentLoaded;
    String? sentError;
    OliveApi? api;
    try {
      api = await widget.openApi();
      try {
        parts = parseDayParts(await api.fetchDayParts(widget.childId));
      } catch (_) {/* the guard then does not invent a block */}
      try {
        final Map<String, dynamic> now = await api.fetchNow(widget.childId);
        nowPart = now['dayPart'] as String?;
        reachable = now['reachable'] as bool?;
      } catch (_) {
        nowPart = null;
        reachable = null;
      }
      try {
        sent = parseSent(await api.fetchSent(widget.childId));
        sentLoaded = true;
      } catch (e) {
        sentError = e is ApiException && e.statusCode == 403
            ? 'Your account is not allowed to see what was sent.'
            : "Couldn't reach the server to see what happened to earlier messages, so what is listed here may be out of date.";
      }
    } catch (_) {
      sentError = "Couldn't reach the server to see what happened to earlier messages, so what is listed here may be out of date.";
    } finally {
      if (api != null && widget.closeApi) api.close();
    }
    final List<QueuedSend> waiting = await _service.waiting();
    if (!mounted) return;
    setState(() {
      _parts = parts;
      _nowDayPart = nowPart;
      _reachable = reachable;
      _sent = sent;
      _sentLoaded = sentLoaded;
      _sentError = sentError;
      _waiting = waiting;
      _loading = false;
    });
  }

  void _say(String text, _Tone tone) {
    if (!mounted) return;
    setState(() {
      _result = text;
      _tone = tone;
    });
  }

  Future<void> _pick(PickSource source) async {
    if (_busy) return;
    try {
      final PickedMedia? m = await (widget.pickMedia ?? _defaultPick)(source);
      if (m == null || !mounted) return;
      setState(() {
        _media = m;
        _result = null;
      });
    } on FormatException {
      _say("That kind of file can't be sent. Use a photo (JPEG or PNG) or a video (MP4 or WebM).", _Tone.bad);
    } catch (_) {
      _say("Couldn't open the camera or your files. Check that Olive is allowed to use them, then try again.", _Tone.bad);
    }
  }

  Future<void> _chooseNight() async {
    final DateTime today = DateTime.now();
    final DateTime first = DateTime(today.year, today.month, today.day);
    final DateTime last = first.add(const Duration(days: kMaxNightsAhead));
    final DateTime? d = await (widget.pickNight ?? _defaultNightPicker)(context, first, last);
    if (d == null || !mounted) return;
    setState(() => _night = localDateString(d));
  }

  SendGuard get _guard => sendGuard(
        choice: _mode == SendMode.onNight && (_night == null) ? const DeliveryChoice.atDayPart('bedtime') : _choice,
        childName: widget.childName,
        parts: _parts,
        nowDayPart: _nowDayPart,
        reachable: _reachable,
      );

  bool get _canSend {
    if (_busy || _media == null) return false;
    if (_mode == SendMode.onNight && checkNight(_night, DateTime.now()) != null) return false;
    return !_guard.blocks;
  }

  Future<void> _send() async {
    final PickedMedia? m = _media;
    if (m == null || !_canSend) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    SubmitOutcome out;
    try {
      out = await _service.submit(
          SendDraft(bytes: m.bytes, kind: m.kind, durationMs: m.durationMs, choice: _choice));
    } catch (_) {
      out = const SubmitOutcome(SubmitKind.notKept,
          'Something went wrong on this phone and it was not sent. Keep it open here and try again.');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Only a message that is safe (taken by the server, or kept on this phone) is cleared from the screen.
      if (out.kind == SubmitKind.sent || out.kind == SubmitKind.queued) _media = null;
    });
    _say(out.text, switch (out.kind) {
      SubmitKind.sent => _Tone.good,
      SubmitKind.queued => _Tone.info,
      _ => _Tone.bad,
    });
    await _refresh(quiet: true);
  }

  Future<void> _act(Future<SubmitOutcome> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    SubmitOutcome? out;
    try {
      out = await body();
    } catch (_) {
      out = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (out != null) {
      _say(out.text, out.kind == SubmitKind.sent ? _Tone.good : (out.kind == SubmitKind.queued ? _Tone.info : _Tone.bad));
    }
    await _refresh(quiet: true);
  }

  Future<void> _tryNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    FlushResult? r;
    try {
      r = await _service.flush(force: true);
    } catch (_) {
      r = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null && !r.skipped) {
      if (r.sent > 0) {
        _say(r.sent == 1 ? 'Sent. It is with the server now.' : 'Sent. They are with the server now.', _Tone.good);
      } else if (r.refused > 0) {
        _say('The server did not accept it. The reason is shown on the message.', _Tone.bad);
      } else if (r.stillWaiting > 0) {
        _say("Still couldn't reach the server. It stays saved on this phone.", _Tone.info);
      }
    }
    await _refresh(quiet: true);
  }

  Future<void> _openDay() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DayPartsEditorScreen(
            childName: widget.childName, service: _days)));
    if (mounted) await _refresh(quiet: true);
  }

  Color _toneColor(ColorScheme c) => switch (_tone) {
        _Tone.good => c.primaryContainer,
        _Tone.info => c.secondaryContainer,
        _Tone.bad => c.errorContainer,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String name = widget.childName;
    final SendGuard guard = _guard;
    final List<String> kinds = _parts == null
        ? kDayPartKinds
        : <String>[
            for (final String k in kDayPartKinds)
              if (_parts!.any((DayPartSpan p) => p.kind == k)) k,
          ];
    final List<String> menuKinds = kinds.contains(_daypartKind) ? kinds : <String>[...kinds, _daypartKind];
    final String sendLabel = _mode == SendMode.now
        ? (guard.warns ? 'Send now anyway' : 'Send now')
        : 'Send';
    return Scaffold(
      appBar: AppBar(title: Text('Send to $name')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text("Make something for $name, then choose when it should arrive. It goes through the server, and this "
                    'page tells you what happened to it.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                Text('What to send', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                      key: const Key('sendPickVideo'),
                      onPressed: _busy ? null : () => _pick(PickSource.recordVideo),
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text('Record a video (up to ${kRecordLimit.inSeconds} seconds)')),
                  OutlinedButton.icon(
                      key: const Key('sendPickPhoto'),
                      onPressed: _busy ? null : () => _pick(PickSource.takePhoto),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take a photo')),
                  OutlinedButton.icon(
                      key: const Key('sendPickGallery'),
                      onPressed: _busy ? null : () => _pick(PickSource.chooseFromPhone),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Choose from this phone')),
                ]),
                if (_media != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: <Widget>[
                      Icon(Icons.check_circle_outline, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Ready: a ${mediaKindWord(_media!.kind)}',
                              key: const Key('sendChosen'), style: theme.textTheme.bodyMedium)),
                      TextButton(
                          key: const Key('sendClearMedia'),
                          onPressed: _busy ? null : () => setState(() => _media = null),
                          child: const Text('Remove')),
                    ]),
                  ),
                const SizedBox(height: 20),
                Text('When should it arrive?', style: theme.textTheme.titleMedium),
                RadioGroup<SendMode>(
                  groupValue: _mode,
                  onChanged: (SendMode? v) {
                    if (v != null && !_busy) setState(() => _mode = v);
                  },
                  child: Column(children: <Widget>[
                    const RadioListTile<SendMode>(
                        key: Key('sendWhenNow'),
                        value: SendMode.now,
                        title: Text('Right away'),
                        subtitle: Text('It goes into her inbox as soon as the server next checks, usually within a minute.')),
                    const RadioListTile<SendMode>(
                        key: Key('sendWhenDayPart'),
                        value: SendMode.atDayPart,
                        title: Text('When a part of her day starts'),
                        subtitle: Text('The next time it comes round, in her time. Bedtime is the usual one.')),
                    const RadioListTile<SendMode>(
                        key: Key('sendWhenNight'),
                        value: SendMode.onNight,
                        title: Text('On a particular night'),
                        subtitle: Text('At the start of her bedtime that night, in her time.')),
                  ]),
                ),
                if (_mode == SendMode.atDayPart)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    child: DropdownButtonFormField<String>(
                      key: const Key('sendDaypartMenu'),
                      initialValue: _daypartKind,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Which part of her day', border: OutlineInputBorder()),
                      items: <DropdownMenuItem<String>>[
                        for (final String k in menuKinds)
                          DropdownMenuItem<String>(value: k, child: Text(adultDayPartName(k))),
                      ],
                      onChanged: _busy ? null : (String? v) => setState(() => _daypartKind = v ?? _daypartKind),
                    ),
                  ),
                if (_mode == SendMode.onNight)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                          key: const Key('sendPickNight'),
                          onPressed: _busy ? null : _chooseNight,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(_night == null ? 'Pick the night' : describeLocalDate(_night!))),
                    ),
                  ),
                if (guard.level != GuardLevel.clear)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      key: const Key('sendGuard'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: guard.blocks ? scheme.errorContainer : scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(guard.headline, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(guard.detail, style: theme.textTheme.bodyMedium),
                        if (guard.blocks)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                key: const Key('sendOpenDay'),
                                onPressed: _openDay,
                                child: Text("Open $name's day")),
                          ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                      key: const Key('sendButton'),
                      onPressed: _canSend ? _send : null,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(sendLabel)),
                ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      key: const Key('sendResult'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: _toneColor(scheme), borderRadius: BorderRadius.circular(12)),
                      child: Text(_result!, style: theme.textTheme.bodyMedium),
                    ),
                  ),
                if (_waiting.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text('Saved on this phone', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('These have not reached the server. They are kept safe here.', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final QueuedSend q in _waiting) _waitingCard(q, theme, scheme),
                ],
                const SizedBox(height: 24),
                Row(children: <Widget>[
                  Expanded(child: Text('What you have sent', style: theme.textTheme.titleMedium)),
                  IconButton(
                      key: const Key('sendRefresh'),
                      tooltip: 'Check again',
                      onPressed: _busy ? null : () => _refresh(),
                      icon: const Icon(Icons.refresh)),
                ]),
                if (_loading && !_sentLoaded)
                  const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                else ...<Widget>[
                  if (_sentError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_sentError!, key: const Key('sentError'), style: theme.textTheme.bodyMedium),
                    ),
                  if (_sentLoaded && _sent.isEmpty && _sentError == null)
                    Text('Nothing sent yet.', key: const Key('sentEmpty'), style: theme.textTheme.bodyMedium),
                  for (final SentEntry e in _sent) _sentCard(e, theme, scheme),
                  if (_sentLoaded && _sent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Only your own messages are listed, newest first.', style: theme.textTheme.bodySmall),
                    ),
                ],
                const SizedBox(height: 16),
                TextButton.icon(
                    key: const Key('sendOpenDayLink'),
                    onPressed: _openDay,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text("$name's day: when things arrive")),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waitingCard(QueuedSend q, ThemeData theme, ColorScheme scheme) {
    final String name = widget.childName;
    final DeliveryChoice? c = q.choice;
    final String when = c == null ? '' : c.describe();
    return Card(
      key: Key('waiting_${q.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('A ${mediaKindWord(q.mediaKind)} for $name${when.isEmpty ? '' : ' · $when'}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(q.statusLine(name, now: DateTime.now()), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
            if (q.phase == QueuePhase.waiting)
              OutlinedButton(
                  key: Key('sendTryNow_${q.id}'), onPressed: _busy ? null : _tryNow, child: const Text('Try now')),
            if (q.phase == QueuePhase.needsChoice) ...<Widget>[
              FilledButton(
                  key: Key('sendNowAnyway_${q.id}'),
                  onPressed: _busy ? null : () => _act(() => _service.resolve(q.id)),
                  child: const Text('Send it now')),
              OutlinedButton(
                  key: Key('sendAtBedtime_${q.id}'),
                  onPressed: _busy ? null : () => _act(() => _service.resolve(q.id, choice: const DeliveryChoice.atDayPart('bedtime'))),
                  child: const Text('Send at her bedtime')),
            ],
            TextButton(
                key: Key('sendDiscard_${q.id}'),
                onPressed: _busy
                    ? null
                    : () async {
                        await _service.discard(q.id);
                        await _refresh(quiet: true);
                      },
                child: Text(q.phase == QueuePhase.refused ? 'Dismiss' : 'Discard')),
          ]),
        ]),
      ),
    );
  }

  Widget _sentCard(SentEntry e, ThemeData theme, ColorScheme scheme) {
    final Color chip = switch (e.state) {
      SentState.opened => scheme.primaryContainer,
      SentState.delivered => scheme.secondaryContainer,
      SentState.waiting => scheme.tertiaryContainer,
      _ => scheme.errorContainer,
    };
    final String when = e.delivery?.describe() ?? '';
    return Card(
      key: Key('sentRow_${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(999)),
              child: Text(e.stateLabel, style: theme.textTheme.labelMedium),
            ),
            if (when.isNotEmpty) Text(when, style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 6),
          Text(e.statusLine(widget.childName), style: theme.textTheme.bodyMedium),
        ]),
      ),
    );
  }
}
