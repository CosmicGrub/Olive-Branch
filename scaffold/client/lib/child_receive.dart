// OLIVE BRANCH — the child's receive path: what a server-connected device does with the things the delivery worker
// made ready. No longer UNVERIFIED — verified by CI (client/test/child_receive_test.dart,
// client/test/inbox_screen_test.dart). MASTERFILE section 7.19.
//
// Three small, separately testable pieces:
//
// 1. [parseInbox]: turns the server's GET .../inbox body into the rows she may see. The server has already decided
//    WHAT is ready and WHEN (the day-part, bedtime and custody rules run on the server: a message that is not yet due
//    is simply not in this list). The client adds no second opinion about timing; it only refuses what it should
//    never draw: a row that is not 'delivered' or 'opened', a kind it has no wording for, an id that is not a plain
//    id (it goes into a URL), and any text that is not a plain name or a plain time. Everything else on the row,
//    and every extra field a hostile or newer server adds, is dropped on the floor (a whitelist, not a blacklist),
//    so a score, a streak, an unread count or a link can never reach a screen from here.
// 2. [childSafeName] / [childSafeWhen]: the two strings from the wire that are drawn to her. A name or a time that
//    carries a word from the global child-payload sweep (packages/globalaudit GLOBAL_CHILD_FORBIDDEN, mirrored in
//    [kChildForbiddenWords] and held in step by client/test/child_receive_test.dart) is not drawn: the neutral
//    grown-up word is used instead.
// 3. [ReceiptQueue]: "she opened it" is told to the server through POST .../inbox/:id/opened. If the answer cannot
//    be had (no signal, the server down, a session that needs renewing) the receipt waits in the EXISTING offline
//    outbox (area 'outbox', offline_outbox.dart's own state machine, nothing new on the device) and is sent the
//    next time the app has a reason to ask: opening Messages, or the home loading. She is never told it is waiting.
//
// A locally paired tablet has no server account and no session: it never constructs any of this, and shows nothing.
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_session.dart';
import 'grownup_labels.dart' show neutralGrownUp;
import 'inbox_screen.dart' show InboxMessage;
import 'local_repositories.dart';
import 'local_services.dart';
import 'offline_outbox.dart';

/// Mirror of packages/globalaudit/src/globalaudit.ts GLOBAL_CHILD_FORBIDDEN. client/test/child_receive_test.dart
/// reads the TypeScript source and fails if the two lists differ in either direction.
const List<String> kChildForbiddenWords = <String>[
  'score', 'points', 'rank', 'ranking', 'rating', 'grade', 'stars', 'level', 'best', 'record', 'highscore',
  'high_score', 'leaderboard', 'percentile', 'streak', 'combo', 'daysinarow', 'days_in_a_row',
  'consecutive', 'percent', 'percentcomplete', 'percent_complete', 'completion', 'progress', 'total',
  'remaining', 'missing', 'goal', 'target', 'quota', 'unfinished', 'timeleft', 'time_left', 'countdown',
  'elapsed', 'seconds', 'deadline', 'wpm', 'reactionms', 'reaction_ms', 'accuracy', 'attempts', 'misses',
  'mood', 'sentiment', 'feeling', 'emotion', 'trend', 'concern', 'flag', 'volatility', 'stability', 'risk',
  'engagement', 'unread', 'unanswered', 'overdue', 'ignored', 'missed', 'lastseen', 'last_seen',
  'inactive', 'absent', 'daysago', 'days_ago', 'expenses', 'courtexport', 'court_export', 'messagelog',
  'message_log', 'carenote', 'care_note', 'custody', 'litigation', 'invoice', 'journal', 'diary',
  'privatenote', 'private_note', 'therapistnote', 'therapist_note', 'latitude', 'longitude', 'lat', 'lng',
  'coords', 'coordinates', 'address', 'postcode', 'zip', 'geo', 'placeid', 'place_id', 'price', 'amount',
  'cost', 'fee', 'copay', 'balance', 'total_due', 'order_ref', 'orderref', 'invoice_id', 'card', 'payment',
  'elo', 'wins', 'losses', 'winrate', 'win_rate', 'skill', 'mmr', 'seed', 'mastery', 'assessment', 'quiz',
  'test_result', 'passed', 'failed', 'reading_level', 'gpa', 'marks', 'count', 'completed', 'ratio',
  'claimedby', 'claimed_by', 'declinedby', 'declined_by', 'daysaway', 'days_away', 'url', 'messages',
  'archive', 'expense', 'wrong', 'incorrect', 'correct', 'test', 'suggested', 'expected', 'reminder',
  'incomplete', 'reconsider', 'darker', 'lighter', 'alert', 'pending', 'waiting', 'age', 'quality',
  'featured', 'improvement', 'timesread', 'times_read', 'mostread', 'most_read',
];

final Set<String> _forbidden = <String>{for (final String w in kChildForbiddenWords) w.toLowerCase()};

/// The most rows one inbox draws (the server sends at most 50).
const int kMaxReceivedRows = 50;

/// What each delivery kind is called when it arrives, in a kid's words. A kind that is not here is not drawn at all:
/// 'homework' is something she sends, not something she is handed.
const Map<String, String> kReceivedPhrase = <String, String>{
  'video_msg': 'sent a video',
  'e2e_video': 'sent a video',
  'call_clip': 'sent a video',
  'voice_note': 'sent a voice message',
  'drawing': 'sent a drawing',
  'photo': 'sent a picture',
  'nudge': 'is thinking of you',
};

final RegExp _plainId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// An id that is safe to put into a URL path and into the outbox.
bool isPlainId(Object? v) => v is String && _plainId.hasMatch(v);

bool _hasForbiddenWord(String s) {
  for (final String w in s.toLowerCase().split(RegExp(r'[^a-z0-9_]+'))) {
    if (w.isNotEmpty && _forbidden.contains(w)) return true;
  }
  return false;
}

/// A grown-up's name as she may see it: letters (any script), marks, spaces, apostrophes and hyphens, at most 24
/// characters; or null when nothing plain is left or the name carries a word she must never be shown.
String? childSafeName(Object? raw, {int maxChars = 24}) {
  if (raw is! String) return null;
  final String cleaned = raw
      .replaceAll(RegExp(r"[^\p{L}\p{M} '’-]", unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Checked on the raw text too, so 'days_in_a_row' (underscores) cannot slip through as 'days in a row'.
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(cleaned) || _hasForbiddenWord(cleaned) || _hasForbiddenWord(raw)) {
    return null;
  }
  final List<int> runes = cleaned.runes.toList();
  return runes.length <= maxChars ? cleaned : String.fromCharCodes(runes.take(maxChars)).trim();
}

/// A time label in her frame ("7:04 AM", "Yesterday, 7:58 PM") as she may see it; '' when it is anything else.
String childSafeWhen(Object? raw, {int maxChars = 40}) {
  if (raw is! String) return '';
  final String cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9 ,:]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty || cleaned.length > maxChars || _hasForbiddenWord(cleaned) || _hasForbiddenWord(raw)) return '';
  return cleaned;
}

/// The rows of a GET .../inbox body she may see. Anything that is not the expected shape is nothing (an empty list),
/// never an error: an unreadable answer must look exactly like an empty inbox.
List<InboxMessage> parseInbox(Object? body) {
  if (body is! Map) return const <InboxMessage>[];
  final Object? entries = body['entries'];
  if (entries is! List) return const <InboxMessage>[];
  final List<InboxMessage> out = <InboxMessage>[];
  final Set<String> seen = <String>{};
  for (final Object? e in entries) {
    if (out.length >= kMaxReceivedRows) break;
    if (e is! Map) continue;
    final Object? id = e['id'], state = e['state'], kind = e['payload_kind'];
    if (!isPlainId(id) || !seen.add(id as String)) continue;
    // 'ready' and 'pending' are not hers yet whatever a server says; 'expired' and 'revoked' are gone.
    if (state != 'delivered' && state != 'opened') continue;
    final String k = kind is String ? kind : 'video_msg';
    if (!kReceivedPhrase.containsKey(k)) continue;
    final Object? sid = e['sender_id'];
    out.add(InboxMessage(
      id: id,
      senderName: childSafeName(e['sender_name']) ?? neutralGrownUp,
      senderId: isPlainId(sid) ? sid as String : null,
      deliveredAtLabel: childSafeWhen(e['deliveredAtLabel']),
      watched: state == 'opened',
      kind: k,
    ));
  }
  return out;
}

/// True when the server heard the receipt and will never accept it, so keeping it cannot help: not found, not yet
/// delivered or expired (404, 410), not her session (403), a malformed request (400, 422), a state conflict (409).
bool _isFinalAnswer(ApiException e) => const <int>{400, 403, 404, 409, 410, 422}.contains(e.statusCode);

/// Sends one "she opened this" receipt. Throws on failure.
typedef OpenedSender = Future<void> Function(String messageId);

/// The receipts she has made that the server has not yet heard, kept in the offline outbox (area 'outbox').
class ReceiptQueue {
  ReceiptQueue._(this._load, this._save, this._now);

  /// A queue over explicit load/save functions (tests).
  factory ReceiptQueue.over({
    required Future<List<OutboxItem>> Function() load,
    required Future<void> Function(List<OutboxItem>) save,
    DateTime Function()? now,
  }) =>
      ReceiptQueue._(load, save, now ?? DateTime.now);

  static final Expando<Map<String, ReceiptQueue>> _byServices = Expando<Map<String, ReceiptQueue>>('receiptQueues');

  /// The queue for [childId] on this device, backed by the catalogued 'outbox' area. One instance per device store, so
  /// the Messages screen and the home share one lock. If the store refuses the area (a demo scope in a live build)
  /// the queue still works for this run, in memory only.
  factory ReceiptQueue.forChild(String childId) {
    final LocalServices services = LocalServices.current;
    final Map<String, ReceiptQueue> cache = _byServices[services] ??= <String, ReceiptQueue>{};
    return cache[childId] ??= () {
      try {
        final OutboxRepository repo = OutboxRepository(services.area('outbox', ownerId: childId));
        return ReceiptQueue._(repo.load, (List<OutboxItem> items) async {
          await repo.save(items);
        }, DateTime.now);
      } catch (e) {
        debugPrint('[olive.receipts] on-device outbox unavailable, queueing in memory: $e');
        List<OutboxItem> held = <OutboxItem>[];
        return ReceiptQueue._(() async => List<OutboxItem>.of(held), (List<OutboxItem> items) async {
          held = List<OutboxItem>.of(items);
        }, DateTime.now);
      }
    }();
  }

  final Future<List<OutboxItem>> Function() _load;
  final Future<void> Function(List<OutboxItem>) _save;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();
  // When each waiting receipt last failed, this run. Not persisted: a fresh start is a real reason to try again.
  final Map<String, DateTime> _lastFailedAt = <String, DateTime>{};

  /// A receipt older than this, or tried this many times, is let go: it is a courtesy to the sender, not a record.
  static const Duration maxAge = Duration(days: 30);

  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await body());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  static String _itemId(String messageId) => 'receipt:$messageId';
  static bool _isReceipt(OutboxItem i) => i.kind == OutboxKind.receipt;
  static String? _messageIdOf(OutboxItem i) {
    final Object? p = i.payload;
    final Object? id = p is Map ? p['messageId'] : null;
    return isPlainId(id) ? id as String : null;
  }

  /// The message ids she has opened that the server has not confirmed yet.
  Future<Set<String>> pendingIds() async {
    try {
      return await _locked(() async {
        final Set<String> ids = <String>{};
        for (final OutboxItem i in await _load()) {
          if (!_isReceipt(i)) continue;
          final String? id = _messageIdOf(i);
          if (id != null) ids.add(id);
        }
        return ids;
      });
    } catch (_) {
      return <String>{};
    }
  }

  /// She opened [messageId]: tell the server now; if that cannot be done, keep it for later. Never throws.
  Future<void> record(String messageId, OpenedSender send) async {
    if (!isPlainId(messageId)) return;
    try {
      await _locked(() async {
        try {
          await send(messageId);
          // Heard: a queued duplicate of the same receipt is no longer needed.
          final List<OutboxItem> items = await _load();
          final List<OutboxItem> kept = items.where((OutboxItem i) => i.id != _itemId(messageId)).toList();
          if (kept.length != items.length) await _save(kept);
        } on ApiException catch (e) {
          if (_isFinalAnswer(e)) return;
          await _enqueue(messageId, 'server');
        } catch (_) {
          await _enqueue(messageId, 'network');
        }
      });
    } catch (e) {
      debugPrint('[olive.receipts] could not keep a receipt: $e');
    }
  }

  Future<void> _enqueue(String messageId, String why) async {
    final List<OutboxItem> items = await _load();
    if (items.any((OutboxItem i) => i.id == _itemId(messageId))) return;
    final EnqueueResult r = enqueue(
        items,
        OutboxItem(
            id: _itemId(messageId),
            kind: OutboxKind.receipt,
            createdAt: _now().toUtc(),
            payload: <String, Object?>{'messageId': messageId},
            attempts: 1,
            lastError: why));
    _lastFailedAt[_itemId(messageId)] = _now();
    await _save(r.outbox);
  }

  /// Tries every waiting receipt once, oldest first. Stops at the first answer that says "not now" so a server that is
  /// down is not asked fifty times. Never throws.
  Future<void> drain(OpenedSender send) async {
    try {
      await _locked(() async {
        List<OutboxItem> items = await _load();
        final DateTime now = _now();
        // Let go of the exhausted and the stale, and of anything whose payload is not a plain id (never sent anywhere).
        final List<OutboxItem> live = items
            .where((OutboxItem i) =>
                !_isReceipt(i) ||
                (i.attempts < maxAttempts && now.difference(i.createdAt) < maxAge && _messageIdOf(i) != null))
            .toList();
        bool changed = live.length != items.length;
        items = live;
        final List<OutboxItem> due = items.where(_isReceipt).toList()
          ..sort((OutboxItem a, OutboxItem b) => a.createdAt.compareTo(b.createdAt));
        for (final OutboxItem item in due) {
          // The 8 tries are meant to span hours, not the minutes of a 60 s poll: a receipt that failed less than its
          // backoff ago is not tried (and so not counted) yet.
          final DateTime? failedAt = _lastFailedAt[item.id];
          if (failedAt != null && now.difference(failedAt).inMilliseconds < backoffMs(item.attempts)) continue;
          final String id = _messageIdOf(item)!;
          try {
            await send(id);
            items = sent(items, item.id);
            changed = true;
          } on ApiException catch (e) {
            changed = true;
            if (_isFinalAnswer(e)) {
              items = sent(items, item.id);
              continue;
            }
            items = recordFailure(items, item.id, 'server');
            _lastFailedAt[item.id] = now;
            break;
          } catch (_) {
            items = recordFailure(items, item.id, 'network');
            _lastFailedAt[item.id] = now;
            changed = true;
            break;
          }
        }
        if (changed) await _save(items);
      });
    } catch (e) {
      debugPrint('[olive.receipts] drain skipped: $e');
    }
  }
}

/// Builds a session for [baseUrl] with [sessionToken], runs [body], and closes what it opened.
Future<T> withChildApi<T>({
  required String baseUrl,
  required String sessionToken,
  http.Client? httpClient,
  required Future<T> Function(OliveApi api) body,
}) async {
  final OliveApi api = OliveApi(baseUrl, sessionToken, client: httpClient, session: AuthSession.current);
  try {
    return await body(api);
  } finally {
    if (httpClient == null) api.close();
  }
}

/// Sends the receipts that are waiting. Best effort and silent: any failure stays in the outbox for next time.
Future<void> drainOpenedReceipts({
  required String baseUrl,
  required String childId,
  required String sessionToken,
  http.Client? httpClient,
  ReceiptQueue? queue,
}) async {
  try {
    await withChildApi<void>(
      baseUrl: baseUrl,
      sessionToken: sessionToken,
      httpClient: httpClient,
      body: (OliveApi api) =>
          (queue ?? ReceiptQueue.forChild(childId)).drain((String id) => api.markInboxOpened(childId, id)),
    );
  } catch (e) {
    debugPrint('[olive.receipts] not sent this run: $e');
  }
}
