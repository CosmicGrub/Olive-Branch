// OLIVE BRANCH — test doubles for the guardian send path. Not a test file (no main).
//
// [FakeSendApi] stands in for the server and records every call, so a test can say exactly what
// went over the wire and in what order, without a device or a network.
import 'dart:async';

import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_send_service.dart';
import 'package:olive_client/local_services.dart';

class FakeSendApi implements GuardianSendApi {
  final List<String> calls = <String>[];
  final List<List<int>> uploads = <List<int>>[];
  final List<Map<String, Object?>> sends = <Map<String, Object?>>[];
  final List<List<Map<String, Object?>>> putBodies = <List<Map<String, Object?>>>[];
  int closed = 0;

  /// False plays a server that predates the `delivery` field: it ignores it and answers without the echo.
  bool echoDelivery = true;

  /// Scripted behaviours; each is consulted for every call and may throw.
  FutureOr<void> Function(int n)? onUpload;
  FutureOr<Map<String, dynamic>> Function(int n, Map<String, Object?> body)? onSend;
  FutureOr<Map<String, dynamic>> Function()? onSent;
  FutureOr<Map<String, dynamic>> Function()? onGetDayParts;
  FutureOr<Map<String, dynamic>> Function(List<Map<String, Object?>> parts)? onPutDayParts;
  FutureOr<Map<String, dynamic>> Function()? onNow;

  int _uploadN = 0;
  int _sendN = 0;

  /// What the server holds now, for day-parts.
  Map<String, dynamic> dayPartsBody = <String, dynamic>{
    'dayParts': <Map<String, Object?>>[
      <String, Object?>{'kind': 'wake', 'startsLocal': '06:30', 'endsLocal': '08:00', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
      <String, Object?>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '19:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
      <String, Object?>{'kind': 'bedtime', 'startsLocal': '19:30', 'endsLocal': '20:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
      <String, Object?>{'kind': 'asleep', 'startsLocal': '20:30', 'endsLocal': '06:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': false},
    ],
    'hasBedtime': true,
  };

  @override
  Future<String> uploadMedia(String childId, List<int> bytes) async {
    calls.add('upload');
    uploads.add(bytes);
    _uploadN++;
    await onUpload?.call(_uploadN);
    return 'children/$childId/messages/00000000-0000-4000-8000-00000000000$_uploadN';
  }

  @override
  Future<Map<String, dynamic>> sendMessage(String childId,
      {required String storageKey,
      required int durationMs,
      required String daypart,
      String? targetLocalDate,
      String? delivery}) async {
    calls.add('send');
    final Map<String, Object?> body = <String, Object?>{
      'storageKey': storageKey, 'durationMs': durationMs, 'daypart': daypart,
      'targetLocalDate': ?targetLocalDate,
      'delivery': ?delivery,
    };
    sends.add(body);
    _sendN++;
    if (onSend != null) return onSend!(_sendN, body);
    // Like the real route: says which choice it stored. A test of an OLD server sets [echoDelivery] false.
    final String stored = delivery == 'now' ? 'now' : (targetLocalDate != null ? 'date' : 'daypart');
    return <String, dynamic>{
      'id': 'intent-0000$_sendN', 'artifactId': 'art-$_sendN', 'state': 'ready',
      if (echoDelivery) 'delivery': stored,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchSent(String childId) async {
    calls.add('sent');
    if (onSent != null) return onSent!();
    return <String, dynamic>{'messages': <Object?>[]};
  }

  @override
  Future<Map<String, dynamic>> fetchDayParts(String childId) async {
    calls.add('getDayParts');
    if (onGetDayParts != null) return onGetDayParts!();
    return dayPartsBody;
  }

  @override
  Future<Map<String, dynamic>> putDayParts(String childId, List<Map<String, Object?>> parts) async {
    calls.add('putDayParts');
    putBodies.add(parts);
    if (onPutDayParts != null) return onPutDayParts!(parts);
    dayPartsBody = <String, dynamic>{
      'dayParts': parts,
      'hasBedtime': parts.any((Map<String, Object?> p) => p['kind'] == 'bedtime'),
    };
    return dayPartsBody;
  }

  @override
  Future<Map<String, dynamic>> fetchNow(String childId) async {
    calls.add('now');
    if (onNow != null) return onNow!();
    return <String, dynamic>{'childLocalTime': '9:14 PM', 'zoneAbbr': 'EST', 'dayPart': 'asleep', 'reachable': false};
  }

  @override
  void close() => closed++;
}

/// A fixed clock the test can move.
class FakeClock {
  FakeClock([this.ms = 1000000000000]);
  int ms;
  int call() => ms;
}

GuardianSendService serviceWith(
  FakeSendApi api, {
  String childId = 'child-a',
  LocalServices? services,
  FakeClock? clock,
  int Function()? nowMs,
  Duration saveTimeout = const Duration(seconds: 30),
  Object? openError,
}) {
  final LocalServices s = services ?? LocalServices.memory(childId: 'ivy', guardianId: 'dad-a');
  return GuardianSendService(
    childId: childId,
    outbox: s.area('sendoutbox', ownerId: 'dad-a'),
    open: () async {
      if (openError != null) throw openError;
      return api;
    },
    nowMs: nowMs ?? clock?.call,
    saveTimeout: saveTimeout,
  );
}

ApiException answer(int status, String error) => ApiException.fromStatus(status, error);
