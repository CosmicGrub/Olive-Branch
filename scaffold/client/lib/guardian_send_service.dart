// OLIVE BRANCH — sending to the child from the grown-up's phone: the service and its on-device outbox.
// Verified headless (client/test/guardian_send_service_test.dart, guardian_send_contract_test.dart).
// MASTERFILE section 8.31.
//
// UNVERIFIED on a real device or against a live server from the phone: covered by flutter test only.
//
// WHAT IT DOES. A grown-up makes something for her (a video, a voice recording or a photo) and chooses when it
// should arrive. This sends it through the REAL routes, in the two steps the server has (server/routes.mjs):
//
//   POST .../media     the bytes, kept by the server; answers with a storage key
//   POST .../messages  the message itself: who, what, and WHEN (now, at the start of a part of her day, or a night)
//
// and it keeps what it could not send. THE SERVER ENABLES, NEVER GATES (DECISIONS.md, offline-first): with no
// server, or a server that does not answer, nothing is lost and nothing is faked. The message is written to an
// OUTBOX ON THIS PHONE first and stays there until the server has really taken it. A 2xx from the server is the
// only thing that ever counts as sent.
//
// THE OUTBOX is the existing offline outbox state machine (offline_outbox.dart: oldest first, a try limit, the
// doubling backoff) over a new sealed on-device area, `guardian.<id>.sendoutbox` (local_services.dart), because
// a message to her can be a video and the existing child `outbox` area is small and is hers. Four honest rules:
//
//   1. A server "no" is a refusal, not a retry. It is said in words and the bytes are let go.
//   2. "Not now" (no answer, busy, restarting, sign in again) keeps it and tries later, patiently.
//   3. A "right away" that has been waiting a while is NOT sent late on its own: a grown-up who said "now" at
//      4 p.m. does not want it appearing at 11 p.m. It waits for their choice (offline.ts: some things are
//      meaningless late). Day-part and night choices are still right later and go as chosen.
//   4. The same message is never sent twice. The upload is remembered across tries, and a "this key is already
//      attached" answer means an earlier try had in fact gone through.
//
// WHAT IT IS NOT. It does not retry while the app is closed (there is no background job: it tries when the
// screen opens, when the grown-up taps Try now, and on a timer while the screen is open), it keeps at most
// three waiting messages and none over 6 MiB (a short clip or a photo), and it cannot take a message back once
// the server has it (no such route exists yet).
import 'dart:async';
import 'dart:convert';

import 'api_client.dart';
import 'day_parts_service.dart' show ApiOpener;
import 'guardian_send_logic.dart';
import 'local_services.dart';
import 'local_store.dart';
import 'offline_outbox.dart' as ob;

/// The largest file this phone will try to send at all.
const int kMaxSendBytes = 24 * 1024 * 1024;

/// The largest file this phone will KEEP while waiting for the server (it lives inside a sealed document).
const int kMaxKeptBytes = 6 * 1024 * 1024;

/// How many messages may wait on this phone at once.
const int kMaxQueued = 3;

/// A "right away" older than this is no longer right away: it waits for a choice.
const Duration kStaleNowAfter = Duration(minutes: 30);

enum QueuePhase { waiting, needsChoice, refused }

/// One message waiting on this phone.
class QueuedSend {
  const QueuedSend({
    required this.id,
    required this.childId,
    required this.createdAtMs,
    required this.wire,
    required this.mediaKind,
    required this.durationMs,
    required this.mediaB64,
    this.storageKey,
    this.attempts = 0,
    this.lastTriedAtMs,
    this.lastCode,
    this.phase = QueuePhase.waiting,
    this.refusedText,
  });

  final String id;
  final String childId;
  final int createdAtMs;

  /// `delivery`, `daypart` and (for a night) `targetLocalDate`: exactly [DeliveryChoice.toWire].
  final Map<String, Object?> wire;
  final MediaKind mediaKind;
  final int durationMs;

  /// The bytes, base64. Empty once the message is refused (the bytes are let go).
  final String mediaB64;

  /// Set once the upload has been taken, so a retry never uploads the same bytes twice.
  final String? storageKey;
  final int attempts;
  final int? lastTriedAtMs;

  /// A fixed word, never a URL, address or text: offline, busy, sign_in.
  final String? lastCode;
  final QueuePhase phase;
  final String? refusedText;

  DeliveryChoice? get choice => DeliveryChoice.fromWire(wire);

  QueuedSend copyWith({
    Map<String, Object?>? wire,
    int? createdAtMs,
    String? mediaB64,
    String? storageKey,
    bool clearStorageKey = false,
    int? attempts,
    int? lastTriedAtMs,
    String? lastCode,
    QueuePhase? phase,
    String? refusedText,
  }) =>
      QueuedSend(
        id: id,
        childId: childId,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        wire: wire ?? this.wire,
        mediaKind: mediaKind,
        durationMs: durationMs,
        mediaB64: mediaB64 ?? this.mediaB64,
        storageKey: clearStorageKey ? null : (storageKey ?? this.storageKey),
        attempts: attempts ?? this.attempts,
        lastTriedAtMs: lastTriedAtMs ?? this.lastTriedAtMs,
        lastCode: lastCode ?? this.lastCode,
        phase: phase ?? this.phase,
        refusedText: refusedText ?? this.refusedText,
      );

  /// The same fact in the shape offline_outbox.dart's state machine works over.
  ob.OutboxItem asOutboxItem({bool freshTries = false}) => ob.OutboxItem(
        id: id,
        kind: ob.OutboxKind.message,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
        payload: null,
        attempts: freshTries ? 0 : attempts,
        lastError: lastCode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'childId': childId,
        'createdAtMs': createdAtMs,
        'wire': wire,
        'mediaKind': mediaKind.name,
        'durationMs': durationMs,
        'media': mediaB64,
        'storageKey': storageKey,
        'attempts': attempts,
        'lastTriedAtMs': lastTriedAtMs,
        'lastCode': lastCode,
        'phase': switch (phase) {
          QueuePhase.waiting => 'waiting',
          QueuePhase.needsChoice => 'needs_choice',
          QueuePhase.refused => 'refused',
        },
        'refusedText': refusedText,
      };

  static final RegExp _plainId = RegExp(r'^[a-z0-9]{1,48}$');
  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F-]{8,40}$');
  static final RegExp _word = RegExp(r'^[a-z_]{1,24}$');

  /// Null for a record that is not exactly what [toJson] writes: a damaged or hand-edited item is dropped, not
  /// sent.
  static QueuedSend? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], child = j['childId'], created = j['createdAtMs'], wire = j['wire'];
    final Object? kind = j['mediaKind'], dur = j['durationMs'], media = j['media'], phase = j['phase'];
    if (id is! String || !_plainId.hasMatch(id)) return null;
    if (child is! String || !_uuid.hasMatch(child)) return null;
    if (created is! int || created < 0) return null;
    if (wire is! Map) return null;
    final Map<String, Object?> w = <String, Object?>{for (final MapEntry<Object?, Object?> e in wire.entries) '${e.key}': e.value};
    if (DeliveryChoice.fromWire(w) == null) return null;
    final MediaKind? mk = MediaKind.values.where((MediaKind k) => k.name == kind).firstOrNull;
    if (mk == null) return null;
    if (dur is! int || dur < 1) return null;
    if (media is! String) return null;
    final QueuePhase? ph = switch (phase) {
      'waiting' => QueuePhase.waiting,
      'needs_choice' => QueuePhase.needsChoice,
      'refused' => QueuePhase.refused,
      _ => null,
    };
    if (ph == null) return null;
    if (ph != QueuePhase.refused && media.isEmpty) return null;
    final Object? key = j['storageKey'], att = j['attempts'], tried = j['lastTriedAtMs'], code = j['lastCode'];
    final Object? text = j['refusedText'];
    if (key != null && (key is! String || key.length > 200)) return null;
    if (att is! int || att < 0 || att > 1000) return null;
    if (tried != null && tried is! int) return null;
    if (code != null && (code is! String || !_word.hasMatch(code))) return null;
    if (text != null && (text is! String || text.length > 400)) return null;
    return QueuedSend(
      id: id,
      childId: child,
      createdAtMs: created,
      wire: w,
      mediaKind: mk,
      durationMs: dur,
      mediaB64: media,
      storageKey: key as String?,
      attempts: att,
      lastTriedAtMs: tried as int?,
      lastCode: code as String?,
      phase: ph,
      refusedText: text as String?,
    );
  }

  /// What a grown-up reads about it.
  String statusLine(String childName, {required DateTime now}) {
    switch (phase) {
      case QueuePhase.refused:
        return refusedText ?? 'The server did not accept this message.';
      case QueuePhase.needsChoice:
        return 'This was meant to go right away, but it has been waiting on this phone for a while. Send it now, '
            'pick another time, or discard it.';
      case QueuePhase.waiting:
        final StringBuffer b = StringBuffer(
            "Saved on this phone. It hasn't reached the server yet, so $childName does not have it.");
        if (lastCode == 'sign_in') {
          b.write(' This phone needs to sign in again first.');
        } else if (attempts >= ob.maxAttempts) {
          b.write(" It couldn't be sent after several tries. Try now, or discard it.");
        } else {
          b.write(' It goes when this phone can reach the server.');
        }
        return b.toString();
    }
  }
}

/// Where waiting messages live. [LocalStoreSendOutbox] is the sealed on-device one; tests use the memory one.
abstract class SendOutbox {
  Future<List<QueuedSend>> load();

  /// Throws [LocalStoreFull] when there is no room.
  Future<void> save(QueuedSend item);
  Future<void> remove(String id);
}

class MemorySendOutbox implements SendOutbox {
  final Map<String, QueuedSend> items = <String, QueuedSend>{};
  bool failSaves = false;
  int saves = 0;

  @override
  Future<List<QueuedSend>> load() async => items.values.toList();

  @override
  Future<void> save(QueuedSend item) async {
    if (failSaves) throw const LocalStoreFull('guardian.test.sendoutbox', 0);
    items[item.id] = item;
    saves++;
  }

  @override
  Future<void> remove(String id) async => items.remove(id);
}

/// Durable, sealed, on this phone: the `sendoutbox` area, one key per message.
class LocalStoreSendOutbox implements SendOutbox {
  LocalStoreSendOutbox(LocalNamespace ns) : _ns = ns;

  /// Bound to [LocalServices.current], for this grown-up.
  LocalStoreSendOutbox.forGuardian(String guardianId)
      : _ns = LocalServices.current.area('sendoutbox', ownerId: guardianId);

  final LocalNamespace _ns;

  /// Records that could not be read and were skipped on the last [load].
  int skipped = 0;

  static const String _prefix = 'q.';

  @override
  Future<List<QueuedSend>> load() async {
    skipped = 0;
    final List<QueuedSend> out = <QueuedSend>[];
    for (final String k in await _ns.list()) {
      if (!k.startsWith(_prefix)) continue;
      QueuedSend? q;
      try {
        q = QueuedSend.fromJson(await _ns.get(k));
      } catch (_) {
        q = null;
      }
      if (q == null || '$_prefix${q.id}' != k) {
        skipped++;
        continue;
      }
      out.add(q);
    }
    return out;
  }

  @override
  Future<void> save(QueuedSend item) => _ns.put('$_prefix${item.id}', item.toJson());

  @override
  Future<void> remove(String id) => _ns.delete('$_prefix$id');
}

/// What was made, and when it should arrive.
class SendDraft {
  const SendDraft({required this.bytes, required this.kind, required this.durationMs, required this.choice});
  final List<int> bytes;
  final MediaKind kind;

  /// The length of a recording as best known; at least 1 for a photo. The server only needs it above zero.
  final int durationMs;
  final DeliveryChoice choice;
}

enum SubmitKind {
  /// The server took it. [SubmitOutcome.intentId] is its id.
  sent,

  /// The server did not answer: it is saved on this phone.
  queued,

  /// The server answered no: nothing is kept.
  refused,

  /// Not sent and not kept (it could not be, or there is no room): the grown-up still has it on screen.
  notKept,

  /// Not even tried: the draft is not something that can be sent.
  invalid,
}

class SubmitOutcome {
  const SubmitOutcome(this.kind, this.text, {this.intentId, this.queued});
  final SubmitKind kind;
  final String text;
  final String? intentId;
  final QueuedSend? queued;
}

typedef MsClock = int Function();

/// A summary of one pass over the outbox.
class FlushResult {
  const FlushResult({this.sent = 0, this.refused = 0, this.stillWaiting = 0, this.needChoice = 0, this.skipped = false});
  final int sent;
  final int refused;
  final int stillWaiting;
  final int needChoice;

  /// Another pass was already running.
  final bool skipped;
}

class GuardianSendService {
  GuardianSendService({
    required this.childId,
    required this.childName,
    required this.openApi,
    required this.outbox,
    this.closeApi = true,
    MsClock? nowMs,
    String Function()? newId,
    this.staleNowAfter = kStaleNowAfter,
  })  : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? _defaultId;

  final String childId;
  final String childName;
  final ApiOpener openApi;
  final SendOutbox outbox;

  /// Close the api after each use (a real one owns its http client; a test's shares one).
  final bool closeApi;
  final Duration staleNowAfter;
  final MsClock _nowMs;
  final String Function() _newId;

  static int _counter = 0;
  static String _defaultId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_counter.toRadixString(36)}';
  }

  Future<void> _tail = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() body) {
    final Completer<T> c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await body());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  bool _flushing = false;

  /// What is waiting for this child on this phone, oldest first.
  Future<List<QueuedSend>> waiting() async {
    final List<QueuedSend> all = await outbox.load();
    return all.where((QueuedSend q) => q.childId == childId).toList()
      ..sort((QueuedSend a, QueuedSend b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  /// Checks a draft the way the server and this phone will, before anything is tried.
  String? checkDraft(SendDraft d, {DateTime? today}) {
    if (d.bytes.isEmpty) return 'Pick or record something first.';
    if (d.bytes.length > kMaxSendBytes) {
      return 'That file is too big to send (the limit is ${kMaxSendBytes ~/ (1024 * 1024)} MB). Pick a shorter or smaller one.';
    }
    if (d.durationMs < 1) return 'That recording has no length. Record it again.';
    if (d.choice.mode == SendMode.onNight) {
      final String? why = checkNight(d.choice.localDate, today ?? DateTime.now());
      if (why != null) return why;
    }
    if (d.choice.mode == SendMode.atDayPart && !kDayPartKinds.contains(d.choice.daypartKind)) {
      return 'Pick a part of her day from the list.';
    }
    return null;
  }

  /// Sends one message. Written to the outbox first (when it fits), then tried; see the file header.
  Future<SubmitOutcome> submit(SendDraft d, {DateTime? today}) async {
    final String? bad = checkDraft(d, today: today);
    if (bad != null) return SubmitOutcome(SubmitKind.invalid, bad);
    return _serial<SubmitOutcome>(() async {
      final int now = _nowMs();
      QueuedSend q = QueuedSend(
        id: _newId(),
        childId: childId,
        createdAtMs: now,
        wire: d.choice.toWire(),
        mediaKind: d.kind,
        durationMs: d.durationMs,
        mediaB64: base64Encode(d.bytes),
      );
      // Written first so a crash or a killed app between the upload and the answer loses nothing. Not
      // possible for something large, or when three are already waiting or the area is full: then it is tried
      // straight away and, if the server does not answer, NOT kept (and the grown-up is told so).
      bool kept = false;
      String? whyNotKept;
      if (d.bytes.length > kMaxKeptBytes) {
        whyNotKept = 'It is too big to keep on this phone while it waits (${kMaxKeptBytes ~/ (1024 * 1024)} MB at most).';
      } else if ((await waiting()).length >= kMaxQueued) {
        whyNotKept = 'There are already $kMaxQueued messages waiting on this phone.';
      } else {
        try {
          await outbox.save(q);
          kept = true;
        } on LocalStoreFull {
          whyNotKept = 'There is no room to keep it on this phone.';
        }
      }
      final _Attempt a = await _transmit(q, d.bytes, kept: kept);
      if (a.sent) {
        return SubmitOutcome(SubmitKind.sent,
            'Sent. It is with the server now; the list below tells you when it has reached $childName.',
            intentId: a.intentId);
      }
      final SendFailure f = a.failure!;
      if (f.kind == FailureKind.refuse) {
        if (kept) await outbox.remove(q.id);
        return SubmitOutcome(SubmitKind.refused, f.text);
      }
      if (kept) {
        q = a.item ?? q;
        return SubmitOutcome(SubmitKind.queued, '${f.text} Nothing is lost: it will go when this phone can reach the server.',
            queued: q);
      }
      return SubmitOutcome(SubmitKind.notKept,
          "${f.text} $whyNotKept It wasn't sent, so keep it open here and try again when you are connected.");
    });
  }

  /// One pass over what is waiting. [force] ignores the wait between tries and the try limit (the Try now
  /// button). Never overlaps itself. Stops at the first "not now", since the rest would fail the same way.
  Future<FlushResult> flush({bool force = false}) async {
    if (_flushing) return const FlushResult(skipped: true);
    _flushing = true;
    try {
      return await _serial<FlushResult>(() => _flushLocked(force));
    } finally {
      _flushing = false;
    }
  }

  Future<FlushResult> _flushLocked(bool force) async {
    int sent = 0, refused = 0;
    final List<QueuedSend> mine = await waiting();
    // The shared state machine's own order and try limit; the wait between tries is applied here.
    final List<ob.OutboxItem> eligible = <ob.OutboxItem>[
      for (final QueuedSend q in mine)
        if (q.phase == QueuePhase.waiting) q.asOutboxItem(freshTries: force),
    ];
    final Map<String, QueuedSend> byId = <String, QueuedSend>{for (final QueuedSend q in mine) q.id: q};
    bool stopped = false;
    while (!stopped) {
      final ob.OutboxItem? next = ob.nextToSend(eligible);
      if (next == null) break;
      eligible.removeWhere((ob.OutboxItem i) => i.id == next.id);
      QueuedSend q = byId[next.id]!;
      final int now = _nowMs();
      final DeliveryChoice? c = q.choice;
      if (c != null && c.mode == SendMode.now && now - q.createdAtMs > staleNowAfter.inMilliseconds) {
        q = q.copyWith(phase: QueuePhase.needsChoice);
        await _saveQuietly(q);
        continue;
      }
      if (!force && q.lastTriedAtMs != null) {
        final int wait = ob.backoffMs(q.attempts);
        if (now - q.lastTriedAtMs! < wait) continue;
      }
      if (q.mediaB64.isEmpty) {
        await outbox.remove(q.id);
        continue;
      }
      final _Attempt a = await _transmit(q, base64Decode(q.mediaB64), kept: true);
      if (a.sent) {
        sent++;
      } else if (a.failure!.kind == FailureKind.refuse) {
        refused++;
      } else {
        stopped = true;
      }
    }
    final List<QueuedSend> after = await waiting();
    final int still = after.where((QueuedSend q) => q.phase == QueuePhase.waiting).length;
    return FlushResult(
        sent: sent,
        refused: refused,
        stillWaiting: still,
        needChoice: after.where((QueuedSend q) => q.phase == QueuePhase.needsChoice).length);
  }

  Future<void> _saveQuietly(QueuedSend q) async {
    try {
      await outbox.save(q);
    } on LocalStoreFull {
      // The record already exists on disk; an unchanged copy stays. Nothing is lost by this.
    }
  }

  /// Gives a message that was meant for "right away" a new time and sends it. [choice] null means right now.
  Future<SubmitOutcome> resolve(String id, {DeliveryChoice? choice}) async {
    return _serial<SubmitOutcome>(() async {
      final QueuedSend? q = (await waiting()).where((QueuedSend x) => x.id == id).firstOrNull;
      if (q == null) return const SubmitOutcome(SubmitKind.invalid, 'That message is no longer waiting.');
      if (q.phase == QueuePhase.refused || q.mediaB64.isEmpty) {
        return const SubmitOutcome(SubmitKind.invalid, 'That one was not accepted, so it cannot be sent again. Make it again.');
      }
      final DeliveryChoice c = choice ?? const DeliveryChoice.now();
      if (c.mode == SendMode.onNight) {
        final String? why = checkNight(c.localDate, DateTime.now());
        if (why != null) return SubmitOutcome(SubmitKind.invalid, why);
      }
      final QueuedSend next = q.copyWith(
          wire: c.toWire(), createdAtMs: _nowMs(), attempts: 0, phase: QueuePhase.waiting);
      await _saveQuietly(next);
      final _Attempt a = await _transmit(next, base64Decode(next.mediaB64), kept: true);
      if (a.sent) {
        return SubmitOutcome(SubmitKind.sent, 'Sent. It is with the server now.', intentId: a.intentId);
      }
      final SendFailure f = a.failure!;
      if (f.kind == FailureKind.refuse) return SubmitOutcome(SubmitKind.refused, f.text);
      return SubmitOutcome(SubmitKind.queued, '${f.text} It stays on this phone.', queued: a.item ?? next);
    });
  }

  /// Lets a waiting or refused message go.
  Future<void> discard(String id) => _serial<void>(() => outbox.remove(id));

  /// One real attempt: upload (once), then send. Updates or removes the stored copy by what happened.
  Future<_Attempt> _transmit(QueuedSend q, List<int> bytes, {required bool kept}) async {
    OliveApi? api;
    try {
      api = await openApi();
      String? key = q.storageKey;
      Future<String> upload() async {
        final String k = await api!.uploadMedia(childId, bytes);
        q = q.copyWith(storageKey: k);
        if (kept) await _saveQuietly(q);
        return k;
      }

      key ??= await upload();
      Map<String, dynamic> reply;
      try {
        reply = await _send(api, q, key);
      } on ApiException catch (e) {
        if (e.error == 'storage_key_unknown' && q.storageKey != null) {
          // The server no longer has the upload (it was swept). Upload the same bytes once more and send again.
          q = q.copyWith(clearStorageKey: true);
          reply = await _send(api, q, await upload());
        } else if (e.statusCode == 409 && e.error == 'storage_key_in_use') {
          // An earlier try had gone through and only its answer was lost. It is sent; it must not go twice.
          if (kept) await outbox.remove(q.id);
          return const _Attempt.sent(null);
        } else {
          rethrow;
        }
      }
      if (kept) await outbox.remove(q.id);
      final Object? id = reply['id'];
      return _Attempt.sent(id is String ? id : null);
    } on Exception catch (e) {
      final SendFailure f = explainSendFailure(e, childName);
      QueuedSend next = q;
      if (kept) {
        if (f.kind == FailureKind.refuse) {
          next = q.copyWith(phase: QueuePhase.refused, refusedText: f.text, mediaB64: '', clearStorageKey: true);
        } else {
          next = q.copyWith(attempts: q.attempts + 1, lastTriedAtMs: _nowMs(), lastCode: f.code);
        }
        await _saveQuietly(next);
      }
      return _Attempt.failed(f, next);
    } finally {
      if (api != null && closeApi) api.close();
    }
  }

  Future<Map<String, dynamic>> _send(OliveApi api, QueuedSend q, String key) {
    final Map<String, Object?> w = q.wire;
    return api.sendMessage(
      childId,
      storageKey: key,
      durationMs: q.durationMs,
      delivery: w['delivery'] as String?,
      daypart: (w['daypart'] as String?) ?? 'bedtime',
      targetLocalDate: w['targetLocalDate'] as String?,
    );
  }
}

class _Attempt {
  const _Attempt.sent(this.intentId)
      : sent = true,
        failure = null,
        item = null;
  const _Attempt.failed(SendFailure this.failure, this.item)
      : sent = false,
        intentId = null;
  final bool sent;
  final String? intentId;
  final SendFailure? failure;
  final QueuedSend? item;
}
