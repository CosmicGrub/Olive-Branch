// OLIVE BRANCH — the guardian side of sending: the service. UNVERIFIED on a real device and against a
// live server; its logic is run by CI (client/test/guardian_send_service_test.dart and
// guardian_send_contract_test.dart). MASTERFILE §8.31, §5.22, §8.16.4.
//
// ONE JOB. Take a recording a grown-up made and get it to the child through the REAL
// routes, and tell the truth about where it is:
//
//   1. The message is written to this phone FIRST (the sealed `sendoutbox` area), so
//      nothing a grown-up recorded is ever lost to a dropped signal, a crash or a
//      closed app.
//   2. Then one attempt: POST .../media (the bytes), then POST .../messages (the
//      storage key, the duration and the delivery choice).
//   3. A server that answers "no" (a night already gone, no bedtime set, a format it
//      will not take) is a "needs your attention" message: kept, with the reason in
//      plain words and a way to change it. A server that does not answer, is busy, or
//      wants the phone to sign in again is "waiting": kept, retried on its own with
//      offline_outbox.dart's doubling wait, and told to the grown-up as such.
//   4. A message leaves the outbox only when the server has it. Never earlier.
//
// DOUBLE SENDS. The upload is cached on the item as soon as it succeeds, so a retry of the
// second half never uploads twice. If the second half reached the server but its answer was
// lost, the retry gets `storage_key_in_use` (the server refuses a key already attached to a
// message); this service knows that key is its own (the server also checks the uploader), so
// it treats that as "the server has it" and drops the item. Two screens flushing at once
// cannot send the same item twice either: a message is claimed in memory for the length of an
// attempt, across every instance of this service.
//
// WHAT THIS DOES NOT DO (kept honest, listed in MASTERFILE §8.31):
//   - It has no "send right now" (see guardian_send_logic.dart: no route reaches the engine's
//     immediate policy).
//   - It cannot take a queued message back from the server after the server has it (no route).
//   - It does not call anything while there is nothing waiting: an empty outbox costs no
//     network.
//   - It never runs on its own in the background; it runs when a screen asks (home loads, the
//     Sent screen is open and on a timer while it is). A phone that is off or closed simply
//     keeps the message until the next time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_session.dart';
import 'guardian_send_logic.dart';
import 'local_services.dart';
import 'local_store.dart';

/// The routes this feature touches, as one narrow interface, so every behaviour is testable
/// with a fake and so the contract test can prove the real adapter hits exactly these paths.
abstract class GuardianSendApi {
  Future<String> uploadMedia(String childId, List<int> bytes);
  Future<Map<String, dynamic>> sendMessage(String childId,
      {required String storageKey, required int durationMs, required String daypart, String? targetLocalDate});
  Future<Map<String, dynamic>> fetchSent(String childId);
  Future<Map<String, dynamic>> fetchDayParts(String childId);
  Future<Map<String, dynamic>> putDayParts(String childId, List<Map<String, Object?>> parts);
  Future<Map<String, dynamic>> fetchNow(String childId);
  void close();
}

/// The real adapter over [OliveApi].
class OliveGuardianSendApi implements GuardianSendApi {
  OliveGuardianSendApi(this._api, {this.ownsClient = true});
  final OliveApi _api;
  final bool ownsClient;

  @override
  Future<String> uploadMedia(String childId, List<int> bytes) => _api.uploadMedia(childId, bytes);

  @override
  Future<Map<String, dynamic>> sendMessage(String childId,
          {required String storageKey, required int durationMs, required String daypart, String? targetLocalDate}) =>
      _api.sendMessage(childId,
          storageKey: storageKey, durationMs: durationMs, daypart: daypart, targetLocalDate: targetLocalDate);

  @override
  Future<Map<String, dynamic>> fetchSent(String childId) => _api.fetchSentMessages(childId);

  @override
  Future<Map<String, dynamic>> fetchDayParts(String childId) => _api.fetchDayParts(childId);

  @override
  Future<Map<String, dynamic>> putDayParts(String childId, List<Map<String, Object?>> parts) =>
      _api.putDayParts(childId, parts);

  @override
  Future<Map<String, dynamic>> fetchNow(String childId) => _api.fetchNow(childId);

  @override
  void close() {
    if (ownsClient) _api.close();
  }
}

/// How a service reaches the server. Throws when there is no session (a signed-out phone).
typedef SendApiOpener = Future<GuardianSendApi> Function();

SendApiOpener liveSendApiOpener({
  required String baseUrl,
  required String guardianId,
  required String childId,
  http.Client? client,
}) =>
    () async {
      final OliveApi api = await apiFor(baseUrl, userId: guardianId, childId: childId, client: client);
      return OliveGuardianSendApi(api, ownsClient: client == null);
    };

enum ComposeOutcome {
  /// The server has it and has scheduled it.
  sent,
  /// Saved on this phone; the server has not answered. It will go by itself.
  savedWaiting,
  /// Saved on this phone; the server said no and something has to change.
  needsAttention,
  /// Not saved: the message was plainly not sendable (empty, too big, a night already gone, ...).
  refused,
}

class ComposeResult {
  const ComposeResult(this.outcome, this.words, {this.queuedId, this.messageId});
  final ComposeOutcome outcome;
  /// A sentence for the grown-up. Never a code, URL or server text.
  final String words;
  final String? queuedId;
  final String? messageId;
}

/// The sender's list as the server reports it, joined with what this phone remembers each was set for.
class SentView {
  const SentView(this.rows, this.setFor, this.skipped);
  final List<SentRow> rows;
  final Map<String, String> setFor;
  final int skipped;
}

enum DayPartsSaveStatus {
  saved,
  /// Refused on this phone before asking the server.
  invalid,
  /// Someone else changed her day since this screen loaded it; nothing was written.
  changedElsewhere,
  /// The server said no; nothing was written.
  refused,
  /// The phone could not tell whether the save happened; the edits are still on screen.
  unknown,
  /// A save for this child is already running from this phone.
  busy,
}

class DayPartsSaveResult {
  const DayPartsSaveResult(this.status, this.words, {this.view, this.problems = const <DayPartProblem>[]});
  final DayPartsSaveStatus status;
  final String words;
  /// For [saved] and [changedElsewhere]: the schedule as the server holds it now.
  final DayPartsView? view;
  final List<DayPartProblem> problems;
}

class GuardianSendService {
  GuardianSendService({
    required this.childId,
    required LocalNamespace outbox,
    required SendApiOpener open,
    int Function()? nowMs,
    String Function()? newId,
    this.saveTimeout = const Duration(seconds: 30),
  })  : _ns = outbox,
        // ignore: prefer_initializing_formals
        _open = open,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        // ignore: prefer_initializing_formals
        _newId = newId;

  /// The service for a live session, over the guardian's own sealed `sendoutbox` area.
  factory GuardianSendService.live({
    required String baseUrl,
    required String guardianId,
    required String childId,
    http.Client? httpClient,
    LocalServices? services,
  }) =>
      GuardianSendService(
        childId: childId,
        outbox: (services ?? LocalServices.current).area('sendoutbox', ownerId: guardianId),
        open: liveSendApiOpener(baseUrl: baseUrl, guardianId: guardianId, childId: childId, client: httpClient),
      );

  final String childId;
  final LocalNamespace _ns;
  final SendApiOpener _open;
  final int Function() _nowMs;
  final String Function()? _newId;
  final Duration saveTimeout;

  // One writer at a time across every instance: the namespace serializes single calls, this
  // serializes the read-then-write sequences built from them.
  static Future<void> _chain = Future<void>.value();
  // Messages being sent right now, across instances, so two screens cannot send one twice.
  static final Set<String> _claimed = <String>{};
  // Children whose day-parts are being saved from this phone right now.
  static final Set<String> _saving = <String>{};

  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await body());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  static final Random _rng = Random();

  String _makeId() {
    final String? fixed = _newId?.call();
    if (fixed != null) return fixed;
    final String salt = List<String>.generate(8, (int _) => _rng.nextInt(36).toRadixString(36)).join();
    return 'm${_nowMs().toRadixString(36)}-$salt';
  }

  static String _key(String id) => 's.$id';

  // ------------------------------------------------------------------ outbox

  /// Every message waiting on this phone for this child, oldest first. Items this build cannot
  /// read are left in the store untouched (never deleted) and not listed.
  Future<List<QueuedSend>> queued() async {
    final List<QueuedSend> out = <QueuedSend>[];
    for (final String k in await _ns.list()) {
      if (!k.startsWith('s.')) continue;
      final QueuedSend? q = QueuedSend.fromJson(await _ns.get(k));
      if (q != null && q.childId == childId) out.add(q);
    }
    out.sort((QueuedSend a, QueuedSend b) => a.createdAtMs.compareTo(b.createdAtMs));
    return out;
  }

  Future<bool> hasQueued() async => (await queued()).isNotEmpty;

  Future<QueuedSend?> _get(String id) async => QueuedSend.fromJson(await _ns.get(_key(id)));

  /// Writes [q] only if it is still there, so a message the grown-up discarded while an attempt
  /// was in flight is not brought back.
  Future<void> _putIfPresent(QueuedSend q) async {
    if (await _ns.get(_key(q.id)) == null) return;
    await _ns.put(_key(q.id), q.toJson());
  }

  /// Compose and send. The recording is saved on this phone first.
  Future<ComposeResult> compose({
    required List<int> bytes,
    required int durationMs,
    required DeliveryChoice delivery,
    List<DayPartEntry>? parts,
    DateTime? today,
  }) async {
    if (bytes.isEmpty || durationMs <= 0) {
      return const ComposeResult(ComposeOutcome.refused, 'The recording was empty. Record it again.');
    }
    if (bytes.length > kMaxHeldBytes) {
      return const ComposeResult(ComposeOutcome.refused,
          'That video is too large to send (over ${kMaxHeldBytes ~/ (1024 * 1024)} MB). Record a shorter one.');
    }
    if (parts != null) {
      final DeliveryCheck c = checkDelivery(delivery, parts, today: today ?? DateTime.now());
      if (!c.ok) return ComposeResult(ComposeOutcome.refused, c.blockers.first);
    }
    final String id = _makeId();
    final QueuedSend item = QueuedSend(
      id: id, childId: childId, createdAtMs: _nowMs(), delivery: delivery,
      mediaB64: encodeMedia(bytes), durationMs: durationMs);
    try {
      await _locked(() => _ns.put(_key(id), item.toJson()));
    } on LocalStoreFull {
      return const ComposeResult(ComposeOutcome.refused,
          'There is not enough room on this phone to keep this message safely while it waits. '
          'Let the waiting messages go first, or record a shorter one.');
    }
    return _resultFor(await _attempt(id), id);
  }

  ComposeResult _resultFor(_Attempt a, String id) {
    if (a.sent) {
      return ComposeResult(ComposeOutcome.sent,
          'Sent. ${a.setForPhrase == null ? 'It is scheduled.' : 'It will arrive ${a.setForPhrase}.'}',
          queuedId: id, messageId: a.messageId);
    }
    final SendFailure f = a.failure!;
    return ComposeResult(
      f.cls == FailureClass.retryLater ? ComposeOutcome.savedWaiting : ComposeOutcome.needsAttention,
      f.words, queuedId: id);
  }

  /// One attempt for one item. Claims it so nothing else touches it meanwhile.
  Future<_Attempt> _attempt(String id) async {
    if (!_claimed.add(id)) {
      return _Attempt.failed(const SendFailure(FailureClass.retryLater, 'in_flight',
          'This message is being sent right now.'));
    }
    try {
      final QueuedSend? start = await _locked(() => _get(id));
      if (start == null) {
        return _Attempt.failed(const SendFailure(FailureClass.retryLater, 'gone', 'This message is no longer waiting.'));
      }
      GuardianSendApi? api;
      try {
        api = await _open();
        return await _runItem(api, start);
      } catch (e) {
        final SendFailure f = _failureOf(e);
        // Re-read: the upload may have succeeded and cached its key before the failure.
        final QueuedSend cur = (await _locked(() => _get(id))) ?? start;
        final QueuedSend failed = cur.copyWith(
          attempts: cur.attempts + 1, lastAttemptMs: _nowMs(),
          phase: f.cls == FailureClass.needsAttention ? SendPhase.needsAttention : SendPhase.waiting,
          failureCode: f.code);
        await _locked(() => _putIfPresent(failed));
        return _Attempt.failed(f);
      } finally {
        api?.close();
      }
    } finally {
      _claimed.remove(id);
    }
  }

  static SendFailure _failureOf(Object e) {
    if (e is ApiException) return classifyFailure(statusCode: e.statusCode, error: e.error);
    return classifyFailure();
  }

  Future<_Attempt> _runItem(GuardianSendApi api, QueuedSend start) async {
    QueuedSend item = start;
    // Half one: the bytes. Skipped when an earlier attempt already got them to the server.
    if (item.storageKey == null) {
      final String key = await api.uploadMedia(childId, base64Decode(item.mediaB64));
      item = item.copyWith(storageKey: key);
      await _locked(() => _putIfPresent(item));
    }
    // Half two: the message.
    Map<String, dynamic>? res;
    bool alreadyThere = false;
    try {
      res = await api.sendMessage(childId,
          storageKey: item.storageKey!, durationMs: item.durationMs, daypart: item.delivery.dayPart,
          targetLocalDate: item.delivery.kind == DeliveryKind.onNight ? item.delivery.night : null);
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.error == 'storage_key_in_use') {
        // The key is ours (the server only hands out keys per uploader), so an earlier attempt
        // reached it and only the answer was lost. The server has the message.
        alreadyThere = true;
      } else if (e.statusCode == 400 && (e.error == 'storage_key_unknown' || e.error == 'bad_storage_key')) {
        // The server no longer has the upload (swept or lost). Forget the key and upload again next try.
        item = item.copyWith(
          clearStorageKey: true, attempts: item.attempts + 1, lastAttemptMs: _nowMs(),
          failureCode: 'no_answer');
        await _locked(() => _putIfPresent(item));
        return _Attempt.failed(classifyFailure());
      } else {
        rethrow;
      }
    }
    final Object? idRaw = res?['id'];
    final String? messageId = idRaw is String && isPlainLedgerId(idRaw) ? idRaw : null;
    final String phrase = deliveryPhrase(item.delivery);
    await _locked(() async {
      await _ns.delete(_key(item.id));
      if (messageId != null) await _remember(messageId, phrase);
    });
    return _Attempt.ok(messageId, alreadyThere ? null : phrase);
  }

  /// Retries what is due. [force] ignores the waiting time and the attempt ceiling (a grown-up
  /// tapped Try again). Stops the pass at the first "no answer" so a down server is asked once,
  /// not once per message. Returns how many were handed to the server.
  Future<int> flush({bool force = false}) async {
    int sent = 0;
    final int now = _nowMs();
    for (final QueuedSend q in await queued()) {
      if (q.phase != SendPhase.waiting) continue;
      if (!force && !q.dueAt(now)) continue;
      final _Attempt a = await _attempt(q.id);
      if (a.sent) {
        sent++;
      } else if (a.failure != null && const <String>['no_answer', 'busy', 'sign_in'].contains(a.failure!.code)) {
        break;
      }
    }
    return sent;
  }

  /// A grown-up chose Try again on one message: one attempt now, regardless of the wait.
  Future<ComposeResult> retry(String id) async {
    final QueuedSend? q = await _locked(() => _get(id));
    if (q == null) return const ComposeResult(ComposeOutcome.refused, 'That message is no longer waiting.');
    await _locked(() => _putIfPresent(q.copyWith(attempts: 0, phase: SendPhase.waiting, clearFailure: true)));
    return _resultFor(await _attempt(id), id);
  }

  /// Change when a waiting message arrives, then try once. Valid only for a message the server
  /// does not have yet, which is every message still in the outbox.
  Future<ComposeResult> changeDelivery(String id, DeliveryChoice delivery,
      {List<DayPartEntry>? parts, DateTime? today}) async {
    if (parts != null) {
      final DeliveryCheck c = checkDelivery(delivery, parts, today: today ?? DateTime.now());
      if (!c.ok) return ComposeResult(ComposeOutcome.refused, c.blockers.first, queuedId: id);
    }
    final QueuedSend? q = await _locked(() => _get(id));
    if (q == null) return const ComposeResult(ComposeOutcome.refused, 'That message is no longer waiting.');
    await _locked(() => _putIfPresent(
        q.copyWith(delivery: delivery, attempts: 0, phase: SendPhase.waiting, clearFailure: true)));
    return _resultFor(await _attempt(id), id);
  }

  /// Throw a waiting message away. Only the grown-up's own choice ever calls this.
  Future<void> discard(String id) => _locked(() => _ns.delete(_key(id)));

  // ------------------------------------------------------------------ ledger

  static String _ledgerKey(String messageId) => 'l.$messageId';

  Future<void> _remember(String messageId, String phrase) async {
    await _ns.put(_ledgerKey(messageId), <String, Object?>{'p': phrase, 'at': _nowMs()});
    final List<String> keys = (await _ns.list()).where((String k) => k.startsWith('l.')).toList();
    if (keys.length <= _ledgerKeep) return;
    final List<({String key, int at})> aged = <({String key, int at})>[];
    for (final String k in keys) {
      final Object? v = await _ns.get(k);
      aged.add((key: k, at: v is Map && v['at'] is int ? v['at'] as int : 0));
    }
    aged.sort((a, b) => a.at.compareTo(b.at));
    for (final ({String key, int at}) e in aged.take(keys.length - _ledgerKeep)) {
      await _ns.delete(e.key);
    }
  }

  static const int _ledgerKeep = 60;

  /// "What you sent": the server's own list (the last 50 you sent to her) with what this phone
  /// remembers each was set for. Throws if the server cannot be reached; the caller says so.
  Future<SentView> fetchSent() async {
    final GuardianSendApi api = await _open();
    try {
      final ({List<SentRow> rows, int skipped}) p = parseSent(await api.fetchSent(childId));
      final Map<String, String> setFor = <String, String>{};
      for (final SentRow r in p.rows) {
        if (!isPlainLedgerId(r.id)) continue;
        final Object? v = await _ns.get(_ledgerKey(r.id));
        if (v is Map && v['p'] is String && (v['p'] as String).length <= 80) setFor[r.id] = v['p'] as String;
      }
      return SentView(p.rows, setFor, p.skipped);
    } finally {
      api.close();
    }
  }

  /// Her time at this moment, for the line above the composer. Null when it cannot be had; the
  /// composer works without it.
  Future<({String? localTime, String? dayPart, bool? reachable})> fetchNow() async {
    final GuardianSendApi api = await _open();
    try {
      final Map<String, dynamic> n = await api.fetchNow(childId);
      return (
        localTime: n['childLocalTime'] is String ? n['childLocalTime'] as String : null,
        dayPart: n['dayPart'] is String ? n['dayPart'] as String : null,
        reachable: n['reachable'] is bool ? n['reachable'] as bool : null,
      );
    } finally {
      api.close();
    }
  }

  // --------------------------------------------------------------- day-parts

  Future<DayPartsView> loadDayParts() async {
    final GuardianSendApi api = await _open();
    try {
      return DayPartsView.parse(await api.fetchDayParts(childId));
    } finally {
      api.close();
    }
  }

  /// Save an edited day. The server replaces the whole schedule in one transaction under a
  /// per-child writer lock, so two grown-ups saving at once are serialized there; the lock does
  /// not stop the second save from overwriting the first. This method does:
  ///   - one save per child at a time from this phone;
  ///   - the schedule is checked here first, with the server's own rules;
  ///   - the server's current schedule is read just before writing and compared with
  ///     [baseline] (what this screen loaded). If it moved, nothing is written and the new
  ///     schedule is returned for the grown-up to look at. (A change landing in the instant
  ///     between that read and the write is still possible; the server cannot detect it.)
  ///   - a save whose answer never came is checked by reading the schedule back.
  Future<DayPartsSaveResult> saveDayParts(List<DayPartEntry> edited, {required List<DayPartEntry> baseline}) async {
    final DayPartsCheck check = checkDayParts(edited);
    if (!check.canSave) {
      return DayPartsSaveResult(DayPartsSaveStatus.invalid, check.errors.first.text, problems: check.errors);
    }
    if (!_saving.add(childId)) {
      return const DayPartsSaveResult(DayPartsSaveStatus.busy, 'A save is already in progress. Wait for it to finish.');
    }
    GuardianSendApi? api;
    try {
      api = await _open();
      // Read first: has someone else changed her day since this screen loaded it?
      final DayPartsView now = DayPartsView.parse(await api.fetchDayParts(childId));
      if (now.skipped > 0) {
        return const DayPartsSaveResult(DayPartsSaveStatus.refused,
            'Her day has a part this version of Olive cannot read, so saving could lose it. '
            'Update Olive, then try again. Nothing was changed.');
      }
      if (!sameSchedule(now.parts, baseline)) {
        return DayPartsSaveResult(DayPartsSaveStatus.changedElsewhere,
            'Another grown-up changed her day while you were editing. Nothing was saved. '
            'Look at the new version, then make your change again.',
            view: now);
      }
      try {
        final Map<String, dynamic> res = await api
            .putDayParts(childId, <Map<String, Object?>>[for (final DayPartEntry e in edited) e.toWire()])
            .timeout(saveTimeout);
        return DayPartsSaveResult(DayPartsSaveStatus.saved, 'Saved. Messages waiting to arrive have been re-timed to match.',
            view: DayPartsView.parse(res));
      } on ApiException catch (e) {
        return DayPartsSaveResult(DayPartsSaveStatus.refused, dayPartsErrorWords(e.error));
      } catch (_) {
        // No answer in time, or the connection dropped mid-save. Find out what happened.
        try {
          final DayPartsView after = DayPartsView.parse(await api.fetchDayParts(childId));
          if (sameSchedule(after.parts, edited)) {
            return DayPartsSaveResult(DayPartsSaveStatus.saved,
                'Saved. Messages waiting to arrive have been re-timed to match.', view: after);
          }
          if (sameSchedule(after.parts, baseline)) {
            return const DayPartsSaveResult(DayPartsSaveStatus.refused,
                'The save did not go through. Nothing was changed. Your edits are still here.');
          }
          return DayPartsSaveResult(DayPartsSaveStatus.changedElsewhere,
              'Her day is different from both versions. Look at it, then make your change again.', view: after);
        } catch (_) {
          return const DayPartsSaveResult(DayPartsSaveStatus.unknown,
              'Olive could not tell whether that saved. Your edits are still here: check your connection, then save again.');
        }
      }
    } on ApiException catch (e) {
      return DayPartsSaveResult(DayPartsSaveStatus.refused, dayPartsErrorWords(e.error));
    } catch (_) {
      return const DayPartsSaveResult(DayPartsSaveStatus.unknown,
          'Olive could not reach the server. Nothing was changed. Your edits are still here.');
    } finally {
      api?.close();
      _saving.remove(childId);
    }
  }
}

/// A message id the server returned that is safe to use as a key in the on-device store.
bool isPlainLedgerId(String s) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{5,63}$').hasMatch(s);

class _Attempt {
  _Attempt.ok(this.messageId, this.setForPhrase)
      : sent = true,
        failure = null;
  _Attempt.failed(SendFailure this.failure)
      : sent = false,
        messageId = null,
        setForPhrase = null;
  final bool sent;
  final String? messageId;
  final String? setForPhrase;
  final SendFailure? failure;
}
