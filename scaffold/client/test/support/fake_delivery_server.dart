// A stand-in for the real server's delivery routes, for the grown-up's send and day-parts tests. It is written
// from server/routes.mjs, not from the client: it refuses what the real handlers refuse (same status, same
// reason code, same order of checks) and answers in the real shapes. guardian_send_contract_test.dart then
// reads the real route table to hold THIS file, and the client, to what the server registers, so a drift in
// any of the three fails a test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String kChild = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';
const String kOtherChild = '9a8b7c6d-1111-4222-8333-444455556666';
const String kBase = 'https://olive.test';

class Seen {
  Seen(this.method, this.path, this.body, this.auth);
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final bool auth;
  @override
  String toString() => '$method $path';
}

/// A tiny valid JPEG/MP4/PNG/WebM by first bytes.
List<int> jpegBytes([int n = 64]) => <int>[0xff, 0xd8, 0xff, 0xe0, ...List<int>.filled(n, 7)];
List<int> mp4Bytes([int n = 64]) => <int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d, ...List<int>.filled(n, 1)];
List<int> m4aBytes([int n = 64]) => <int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20, ...List<int>.filled(n, 1)];

class SentRow {
  SentRow(this.id, this.delivery, this.daypart, this.date);
  final String id;
  final String delivery; // now | daypart | date
  final String? daypart;
  final String? date;
  String state = 'waiting';
  Map<String, String>? deliversHer;
  Map<String, String>? deliveredHer;
  String? receiptPhrase;
}

class FakeDeliveryServer {
  FakeDeliveryServer() {
    dayParts = <Map<String, dynamic>>[
      _part('wake', '06:30', '08:00', true),
      _part('free', '08:00', '19:30', true),
      _part('bedtime', '19:30', '20:30', true),
      _part('asleep', '20:30', '06:30', false),
    ];
  }

  static Map<String, dynamic> _part(String k, String s, String e, bool r) => <String, dynamic>{
        'kind': k, 'startsLocal': s, 'endsLocal': e, 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': r,
      };

  final List<Seen> log = <Seen>[];
  late List<Map<String, dynamic>> dayParts;
  final Map<String, Uint8List> uploads = <String, Uint8List>{};
  final Set<String> attached = <String>{};
  final List<SentRow> sent = <SentRow>[];
  int _n = 0;

  /// Every request throws a SocketException (no network at all).
  bool offline = false;

  /// The next N requests are answered with this status and an `error` of 'unavailable' (a busy or restarting server).
  int failNextWith = 0;
  int failStatus = 503;

  /// The next N POST /messages (not the uploads) are answered 503: the bytes got there, the message did not.
  int failMessageTimes = 0;

  /// The server takes the message but the client never hears (the answer is lost): the next POST /messages is
  /// recorded as accepted and then throws, like a connection dropped after the write.
  bool dropNextMessageReply = false;

  /// What GET /now answers.
  String? nowDayPart;
  bool? nowReachable = true;

  /// A held PUT: while set, PUT /day-parts waits for it to complete (to test one-save-at-a-time).
  Completer<void>? holdPut;
  int putCount = 0;
  int activePuts = 0;
  int maxConcurrentPuts = 0;

  /// The session says 401 for this many requests.
  int unauthorizedNext = 0;

  List<Seen> where(String method, String suffix) =>
      log.where((Seen s) => s.method == method && s.path.endsWith(suffix)).toList();

  int get uploadCalls => where('POST', '/media').length;
  int get messageCalls => where('POST', '/messages').length;

  http.Client get client => MockClient(_handle);

  http.Response _json(int status, Object? body) =>
      http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

  http.Response _err(int status, String reason) => _json(status, <String, dynamic>{'error': reason});

  Future<http.Response> _handle(http.Request r) async {
    final Map<String, dynamic> body =
        r.body.isEmpty ? <String, dynamic>{} : (jsonDecode(r.body) as Map<String, dynamic>);
    log.add(Seen(r.method, r.url.path, body, r.headers.containsKey('authorization')));
    if (offline) throw const SocketException('no network');
    if (unauthorizedNext > 0) {
      unauthorizedNext--;
      return _err(401, 'expired');
    }
    if (failNextWith > 0) {
      failNextWith--;
      return _err(failStatus, 'unavailable');
    }
    final String p = r.url.path;
    final RegExpMatch? m = RegExp(r'^/v1/children/([^/]+)/(.+)$').firstMatch(p);
    if (m == null) return _err(404, 'not_found');
    if (m.group(1) != kChild) return _err(m.group(1) == kOtherChild ? 403 : 404, 'wrong_child');
    final String route = m.group(2)!;
    switch ('${r.method} $route') {
      case 'GET now':
        return _json(200, <String, dynamic>{
          'childLocalTime': '9:14 PM', 'zoneAbbr': 'CST', 'dayPart': nowDayPart, 'reachable': nowReachable,
          'dayParts': <Object>[],
        });
      case 'POST media':
        return _upload(body);
      case 'POST messages':
        if (failMessageTimes > 0) {
          failMessageTimes--;
          return _err(503, 'unavailable');
        }
        return _message(body);
      case 'GET sent':
        return _json(200, <String, dynamic>{'messages': <Object>[for (final SentRow s in sent.reversed) _sentJson(s)]});
      case 'GET day-parts':
        return _json(200, _view());
      case 'PUT day-parts':
        return _putDayParts(body);
    }
    return _err(404, 'not_found');
  }

  Map<String, dynamic> _view() => <String, dynamic>{
        'dayParts': dayParts,
        'hasBedtime': dayParts.any((Map<String, dynamic> p) => p['kind'] == 'bedtime'),
      };

  http.Response _upload(Map<String, dynamic> body) {
    final Object? b64 = body['bytes'];
    if (b64 is! String || b64.isEmpty) return _err(400, 'bytes_required');
    final Uint8List bytes = base64Decode(b64);
    if (bytes.isEmpty) return _err(400, 'bad_bytes');
    final bool jpeg = bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final bool ftyp = bytes.length >= 12 && String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';
    if (!jpeg && !ftyp) return _err(415, 'unsupported_media_type');
    final String key = 'children/$kChild/messages/${_uuid()}';
    uploads[key] = bytes;
    return _json(201, <String, dynamic>{'storageKey': key, 'etag': 'e', 'mime': jpeg ? 'image/jpeg' : 'video/mp4'});
  }

  String _uuid() {
    _n++;
    final String h = _n.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$h';
  }

  http.Response _message(Map<String, dynamic> body) {
    final Object? key = body['storageKey'];
    final Object? dur = body['durationMs'];
    if (key is! String || key.isEmpty || dur is! num) {
      return _err(400, 'storage_key_and_duration_ms_required');
    }
    final String prefix = 'children/$kChild/messages/';
    if (!key.startsWith(prefix)) return _err(400, 'bad_storage_key');
    if (!uploads.containsKey(key)) return _err(400, 'storage_key_unknown');
    if (attached.contains(key)) return _err(409, 'storage_key_in_use');
    final Object? target = body['targetLocalDate'];
    final String? targetDate = target is String ? target : null;
    final Object? d = body['delivery'];
    final String? delivery = d == null ? null : '$d';
    if (delivery != null && !<String>['now', 'daypart', 'date'].contains(delivery)) {
      return _err(400, 'bad_delivery');
    }
    if (delivery == 'now' && targetDate != null) return _err(400, 'now_has_no_date');
    if (delivery == 'date' && targetDate == null) return _err(400, 'date_required');
    if (delivery == 'daypart' && targetDate != null) return _err(400, 'daypart_has_no_date');
    final String daypart = body['daypart'] is String ? body['daypart'] as String : 'bedtime';
    final bool now = delivery == 'now';
    if (!now) {
      if (targetDate != null) {
        final DateTime? t = DateTime.tryParse('${targetDate}T00:00:00Z');
        if (t != null && t.isBefore(DateTime.utc(2026, 11, 14))) return _err(400, 'target_date_in_past');
      }
      if (!dayParts.any((Map<String, dynamic> p) => p['kind'] == (targetDate != null ? 'bedtime' : daypart)) &&
          targetDate == null) {
        return _err(400, 'daypart_undefined');
      }
    }
    attached.add(key);
    final SentRow row = SentRow(_uuid(), delivery ?? (targetDate != null ? 'date' : 'daypart'),
        delivery == 'now' ? null : daypart, targetDate)
      ..deliversHer = now ? null : <String, String>{'day': 'today', 'time': '7:30 PM'};
    sent.add(row);
    if (dropNextMessageReply) {
      dropNextMessageReply = false;
      throw const SocketException('connection reset');
    }
    return _json(201, <String, dynamic>{'id': row.id, 'artifactId': _uuid(), 'state': 'ready'});
  }

  Map<String, dynamic> _sentJson(SentRow s) => <String, dynamic>{
        'id': s.id,
        'kind': 'video_msg',
        'state': s.state,
        'sentAt': '2026-11-15T20:00:00.000Z',
        'delivery': s.delivery,
        'daypart': s.daypart,
        'targetLocalDate': s.date,
        'deliversAt': s.state == 'waiting' ? '2026-11-16T01:30:00.000Z' : null,
        'deliversHer': s.state == 'waiting' ? s.deliversHer : null,
        'deliveredAt': s.state == 'delivered' || s.state == 'opened' ? '2026-11-16T01:30:00.000Z' : null,
        'deliveredHer': s.state == 'delivered' ? s.deliveredHer : null,
        'openedAt': s.state == 'opened' ? '2026-11-16T01:40:00.000Z' : null,
        'receipt': s.state == 'opened' && s.receiptPhrase != null
            ? <String, dynamic>{'localTime': '7:40 PM', 'zone': 'America/Chicago', 'phrase': s.receiptPhrase}
            : null,
      };

  static final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  static const List<String> _kinds = <String>[
    'wake', 'before_school', 'school', 'after_school', 'activity', 'dinner', 'wind_down', 'bedtime', 'asleep', 'free',
  ];

  Future<http.Response> _putDayParts(Map<String, dynamic> body) async {
    putCount++;
    activePuts++;
    if (activePuts > maxConcurrentPuts) maxConcurrentPuts = activePuts;
    try {
      final Completer<void>? hold = holdPut;
      if (hold != null) await hold.future;
      final Object? list = body['dayParts'];
      if (list is! List || list.isEmpty || list.length > 24) return _err(400, 'day_parts_required');
      final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];
      for (final Object? p in list) {
        if (p is! Map || !_kinds.contains(p['kind'])) return _err(400, 'bad_day_part_kind');
        final Object? s = p['startsLocal'], e = p['endsLocal'];
        if (s is! String || e is! String || !_hhmm.hasMatch(s) || !_hhmm.hasMatch(e)) {
          return _err(400, 'bad_day_part_time');
        }
        if (s == e) return _err(400, 'empty_day_part');
        final Object? days = p['daysOfWeek'] ?? <int>[0, 1, 2, 3, 4, 5, 6];
        if (days is! List ||
            days.isEmpty ||
            days.length > 7 ||
            !days.every((Object? d) => d is int && d >= 0 && d <= 6) ||
            days.toSet().length != days.length) {
          return _err(400, 'bad_days_of_week');
        }
        if (p['reachable'] is! bool) return _err(400, 'reachable_required');
        parts.add(<String, dynamic>{
          'kind': p['kind'], 'startsLocal': s, 'endsLocal': e,
          'daysOfWeek': <int>[...days.cast<int>()]..sort(), 'reachable': p['reachable'],
        });
      }
      // The overlap constraint (migration 0042): same kind, a weekday in common, overlapping time of day on one
      // dummy day with a wrapping part running on to the next.
      for (int i = 0; i < parts.length; i++) {
        for (int j = i + 1; j < parts.length; j++) {
          final Map<String, dynamic> a = parts[i], b = parts[j];
          if (a['kind'] != b['kind']) continue;
          if (!(a['daysOfWeek'] as List<int>).any((b['daysOfWeek'] as List<int>).contains)) continue;
          int mins(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3));
          (int, int) range(Map<String, dynamic> x) {
            final int st = mins(x['startsLocal'] as String), en = mins(x['endsLocal'] as String);
            return (st, en < st ? en + 1440 : en);
          }

          final (int, int) ra = range(a), rb = range(b);
          if (ra.$1 < rb.$2 && rb.$1 < ra.$2) return _err(409, 'day_parts_overlap');
        }
      }
      dayParts = parts;
      return _json(200, _view());
    } finally {
      activePuts--;
    }
  }
}

/// Lets a test answer or break some requests itself and pass the rest to [inner]. The hook must not read the body.
class InterceptingClient extends http.BaseClient {
  InterceptingClient(this.inner, this.hook);
  final http.Client inner;
  final FutureOr<http.StreamedResponse?> Function(http.BaseRequest request) hook;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => (await hook(request)) ?? inner.send(request);
}

http.StreamedResponse streamedJson(int status, String body) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)), status, headers: <String, String>{'content-type': 'application/json'});
