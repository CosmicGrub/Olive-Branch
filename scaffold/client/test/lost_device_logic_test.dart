// OLIVE BRANCH — lost_device_logic.dart: the plain-words and parsing half of the lost or stolen phone or tablet.
// MASTERFILE section 7.23. Pure: no screen, no storage, no network.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/lost_device_logic.dart';

final DateTime _now = DateTime.utc(2026, 11, 21, 12);

Map<String, Object?> _dev({
  String id = 'aaaaaaaa-0000-4000-a000-000000000001',
  String role = 'guardian',
  String state = 'active',
  Map<String, Object?> over = const <String, Object?>{},
}) =>
    <String, Object?>{
      'id': id, 'role': role, 'label': 'Pixel', 'ownerName': 'Sam', 'isThisDevice': false, 'isOwn': false,
      'state': state, 'pausedAt': null, 'revokeDueAt': null, 'incidentId': null, 'markedByName': null,
      'markedByMe': false, 'canMarkLost': false, 'canFound': false, 'canConfirmLost': false, 'wipe': 'none',
      'canOrderWipe': false, 'canCancelWipe': false,
      ...over,
    };


void main() {
  group('parsing a device', () {
    test('a good record keeps what it says, and nothing it did not say is offered', () {
      final FamilyDevice d = FamilyDevice.tryParse(_dev())!;
      expect(d.standing, DeviceStanding.active);
      expect(d.canMarkLost || d.canFound || d.canConfirmLost || d.canOrderWipe || d.canCancelWipe, isFalse);
      expect(d.wipe, WipeProgress.none);
    });

    test('a record with no usable id is dropped, not shown', () {
      expect(FamilyDevice.tryParse(<String, Object?>{'role': 'guardian'}), isNull);
      expect(FamilyDevice.tryParse(_dev(id: '')), isNull);
      expect(FamilyDevice.tryParse(_dev(id: 'x' * 65)), isNull);
      expect(FamilyDevice.tryParse('nope'), isNull);
      expect(FamilyDevice.tryParse(null), isNull);
    });

    test('anything unexpected falls back to the SAFEST reading: no action offered, standing "active" only for the word "active"', () {
      final FamilyDevice d = FamilyDevice.tryParse(_dev(over: <String, Object?>{
        'canMarkLost': 'yes', 'canFound': 1, 'canOrderWipe': 'true', 'wipe': 'maybe', 'state': 'exploded'}))!;
      expect(d.canMarkLost, isFalse);
      expect(d.canFound, isFalse);
      expect(d.canOrderWipe, isFalse);
      expect(d.wipe, WipeProgress.none);
    });

    test('a very long label or name is cut, never rendered whole', () {
      final FamilyDevice d = FamilyDevice.tryParse(_dev(over: <String, Object?>{'label': 'L' * 500, 'ownerName': 'N' * 500}))!;
      expect(d.label.length, 60);
      expect(d.ownerName!.length, 80);
    });

    test('titles are plain: your phone, another grown-up\'s phone, a tablet; never an id', () {
      expect(FamilyDevice.tryParse(_dev(over: <String, Object?>{'isOwn': true}))!.title, 'Your phone: Pixel');
      expect(FamilyDevice.tryParse(_dev())!.title, "Sam's phone: Pixel");
      expect(FamilyDevice.tryParse(_dev(over: <String, Object?>{'ownerName': null}))!.title, "Another grown-up's phone: Pixel");
      expect(FamilyDevice.tryParse(_dev(role: 'child', over: <String, Object?>{'ownerName': null}))!.title, 'Tablet: Pixel');
    });

    test('the list puts a device that is cut off for good last, and drops what it cannot read', () {
      final List<FamilyDevice> l = parseFamilyDevices(<String, Object?>{
        'devices': <Object?>[
          _dev(id: 'a', state: 'revoked'),
          'junk',
          _dev(id: 'b'),
          _dev(id: 'c', state: 'paused'),
        ]
      });
      expect(l.map((FamilyDevice d) => d.id), <String>['b', 'c', 'a']);
      expect(parseFamilyDevices(<String, Object?>{'devices': 'no'}), isEmpty);
      expect(parseFamilyDevices(null), isEmpty);
    });

    test('an answer to an action needs a device id', () {
      expect(DeviceActionResult.tryParse(<String, Object?>{'state': 'paused'}), isNull);
      final DeviceActionResult r = DeviceActionResult.tryParse(<String, Object?>{
        'deviceId': 'd1', 'state': 'paused', 'incidentId': 'i1', 'already': true, 'revokeDueAt': '2026-11-24T12:00:00.000Z'})!;
      expect(r.standing, DeviceStanding.paused);
      expect(r.already, isTrue);
      expect(r.revokeDueAt, DateTime.utc(2026, 11, 24, 12));
    });
  });

  group('the sentences', () {
    test('a working phone, this phone, a paused one (who and when), a cut-off one', () {
      expect(deviceStatusLine(FamilyDevice.tryParse(_dev())!, _now), 'Working normally.');
      expect(deviceStatusLine(FamilyDevice.tryParse(_dev(over: <String, Object?>{'isThisDevice': true}))!, _now),
          'This is the phone in your hand.');
      final String paused = deviceStatusLine(
          FamilyDevice.tryParse(_dev(state: 'paused', over: <String, Object?>{
            'markedByName': 'Sam', 'revokeDueAt': '2026-11-24T12:00:00.000Z'}))!,
          _now);
      expect(paused, startsWith('Sam marked it as lost.'));
      expect(paused, contains('paused'));
      expect(paused, contains('cut off for good'));
      expect(deviceStatusLine(FamilyDevice.tryParse(_dev(state: 'paused', over: <String, Object?>{'markedByMe': true}))!, _now),
          startsWith('You marked it as lost'));
      expect(deviceStatusLine(FamilyDevice.tryParse(_dev(state: 'revoked'))!, _now), contains('Cut off for good'));
    });

    test('every sentence the screens can say passes the adult-words audit', () {
      final List<FamilyDevice> all = <FamilyDevice>[
        for (final String s in <String>['active', 'paused', 'revoked'])
          for (final String role in <String>['guardian', 'child'])
            for (final String w in <String>['none', 'ordered', 'done'])
              FamilyDevice.tryParse(_dev(role: role, state: s, over: <String, Object?>{
                'wipe': w, 'markedByName': 'Sam', 'revokeDueAt': '2026-11-24T12:00:00.000Z'}))!,
      ];
      final Set<String> sentences = <String>{
        for (final FamilyDevice d in all) ...<String>[
          deviceStatusLine(d, _now), wipeStatusLine(d) ?? '', markLostExplanation(d), markLostLimits(d), d.title],
        kNothingDeleted, kEraseExplanation, kEraseLimits, kPausedPhoneTitle, kPausedPhoneBody, kErasedPhoneBody,
      }..remove('');
      for (final String s in sentences) {
        expect(s.toLowerCase(), isNot(matches(RegExp(r'token|credential|hash|session|revoke|encrypt'))), reason: s);
        expect(s, isNot(matches(RegExp(r'\b(401|403|404|409|429|500)\b'))), reason: s);
      }
    });

    test('the limits are said out loud, always with the explanation (never hidden)', () {
      final FamilyDevice phone = FamilyDevice.tryParse(_dev())!;
      expect(markLostLimits(phone), contains('cannot find'));
      expect(markLostLimits(phone), contains('offline'));
      expect(markLostExplanation(phone), contains('Nothing is deleted'));
      expect(markLostExplanation(phone), contains('3 days'));
      expect(kEraseLimits, contains('online'));
      expect(kEraseExplanation, contains('stay with your family'));
      expect(kEraseExplanation, contains('phone\'s owner'));
    });

    test('the lost phone is told what happened, that nothing was deleted, and what to do next', () {
      expect(kPausedPhoneBody, contains('Nothing on your family'));
      expect(kPausedPhoneBody, contains('I have it'));
      expect(kErasedPhoneBody, contains('safe'));
    });

    test('a child is never named, shown a count or given a score in any of it', () {
      final String all = <String>[kEraseExplanation, kEraseLimits, kPausedPhoneBody, kErasedPhoneBody, kNothingDeleted,
        markLostExplanation(FamilyDevice.tryParse(_dev(role: 'child'))!)].join(' ').toLowerCase();
      for (final String w in <String>['score', 'streak', 'location', 'diagnos']) {
        expect(all, isNot(contains(w)));
      }
    });

    test('a deadline reads as a span, not a count-down', () {
      expect(deadlineWords(_now.add(const Duration(hours: 71)), _now), 'in about 71 hours');
      expect(deadlineWords(_now.add(const Duration(hours: 60)), _now), 'in about 3 days');
      expect(deadlineWords(_now.subtract(const Duration(minutes: 1)), _now), 'now');
    });
  });

  group('every reason has a sentence', () {
    test('each known reason, with its usual status, makes a sentence with no code, status or exception text in it', () {
      for (final String reason in kLostKnownReasons) {
        for (final int status in <int>[400, 401, 403, 404, 409]) {
          for (final LostAction a in LostAction.values) {
            final AccountProblem p = lostProblemFor(ApiException(status, reason), a);
            expect(p.message, isNotEmpty);
            expect(p.message, isNot(contains(reason)), reason: '$reason/$status/$a');
            expect(p.message.toLowerCase(), isNot(matches(RegExp(r'token|credential|hash|session|revoke|encrypt'))), reason: p.message);
            expect(p.message, isNot(matches(RegExp(r'\b(400|401|403|404|409)\b'))), reason: p.message);
          }
        }
      }
    });

    test('an unknown reason is still words, and says nothing was changed', () {
      final AccountProblem p = lostProblemFor(ApiException(418, 'teapot'), LostAction.mark);
      expect(p.message, contains('Nothing was changed'));
      expect(p.message, isNot(contains('teapot')));
    });

    test('the same reason can be worded differently for the action it answers', () {
      expect(lostProblemFor(ApiException(403, 'owner_only'), LostAction.confirm).message, contains('cut-off final'));
      expect(lostProblemFor(ApiException(403, 'owner_only'), LostAction.orderWipe).message, contains('erased'));
      expect(lostProblemFor(ApiException(403, 'owner_only'), LostAction.found).message, contains('bring it back'));
      expect(lostProblemFor(ApiException(409, 'not_paused'), LostAction.orderWipe).message, contains('marked as lost'));
    });

    test('a lost connection and a server error are the shared sentences, and neither says it worked', () {
      final AccountProblem net = lostProblemFor(const SocketException('x'), LostAction.mark);
      expect(net.message, contains('look again'));
      expect(lostProblemFor(TimeoutException('x'), LostAction.mark).reason, 'network');
      final AccountProblem srv = lostProblemFor(ApiException(500, 'x'), LostAction.mark);
      expect(srv.message, contains('cannot be sure'));
    });

    test('a phone that is itself paused is told so, plainly', () {
      final AccountProblem p = lostProblemFor(UnauthorizedException('device_paused'), LostAction.load);
      expect(p.reason, 'device_paused');
      expect(p.message, contains('marked as lost'));
      expect(p.message, contains('Nothing was deleted'));
    });
  });
}
