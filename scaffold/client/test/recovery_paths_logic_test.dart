// OLIVE BRANCH — recovery_paths_logic.dart and sheet_printer.dart: the words and the parsing. MASTERFILE section 7.22.
// Pure Dart: no screen, no storage, no network.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/recovery_paths_logic.dart';
import 'package:olive_client/sheet_printer.dart';

const String _id = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';

void main() {
  group('reading and writing codes', () {
    test('smudges, case, spaces and dashes are forgiven; the length and the alphabet are not', () {
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, 'k7q2-m9xd-abcd-efgh'), 'K7Q2M9XDABCDEFGH');
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, ' K7Q2 M9XD ABCD EFGH '), 'K7Q2M9XDABCDEFGH');
      // O reads as 0, I and L read as 1
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, 'OILO-OILO-OILO-OILO'), '0110011001100110');
      // U is not in the alphabet; too short; too long; empty; a huge paste
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, 'UUUU-UUUU-UUUU-UUUU'), isNull);
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, 'K7Q2-M9XD-ABCD'), isNull);
      expect(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, 'K7Q2-M9XD-ABCD-EFGH-J'), isNull);
      expect(normaliseRecoveryCode(RecoveryCodeKind.sheet, ''), isNull);
      expect(normaliseRecoveryCode(RecoveryCodeKind.sheet, 'A' * 5000), isNull);
    });

    test('each kind has the server\'s own length', () {
      expect(RecoveryCodeKind.sheet.length, 24);
      expect(RecoveryCodeKind.request.length, 20);
      expect(RecoveryCodeKind.helperInvite.length, 16);
    });

    test('groups of four, and what is sent never depends on how it was typed', () {
      expect(groupRecoveryCode('K7Q2M9XDABCDEFGH'), 'K7Q2-M9XD-ABCD-EFGH');
      expect(groupRecoveryCode('k7q2-m9xd abcd efgh'), 'k7q2-m9xd-abcd-efgh');
      expect(sendableRecoveryCode(RecoveryCodeKind.helperInvite, 'k7q2m9xdabcdefgh'), 'K7Q2-M9XD-ABCD-EFGH');
      expect(sendableRecoveryCode(RecoveryCodeKind.helperInvite, 'nope'), isNull);
    });

    test('a helper\'s name is a first name: no control characters, no @, not empty, not long', () {
      expect(cleanHelperName('  Aunt Sam '), 'Aunt Sam');
      expect(cleanHelperName('jo@example.test'), isNull);
      expect(cleanHelperName('   '), isNull);
      expect(cleanHelperName('A' * 41), isNull);
      expect(cleanHelperName('Jo\u0000'), 'Jo');
    });
  });

  group('time, in words', () {
    test('waiting', () {
      expect(waitWords(const Duration(minutes: 30)), 'less than an hour');
      expect(waitWords(const Duration(hours: 1, minutes: 5)), 'about 1 hour');
      expect(waitWords(const Duration(hours: 5)), 'about 5 hours');
      expect(waitWords(const Duration(hours: 47, minutes: 59)), 'about 2 days');
      expect(waitWords(const Duration(hours: 72)), 'about 3 days');
    });

    test('a time of day, in the phone\'s own clock', () {
      final DateTime now = DateTime(2026, 11, 21, 8);
      expect(whenWords(DateTime(2026, 11, 21, 21, 5), now), 'today at 9:05 PM');
      expect(whenWords(DateTime(2026, 11, 23, 0, 0), now), 'Monday at 12:00 AM');
      expect(whenWords(DateTime(2026, 12, 30, 9, 0), now), '2026-12-30 at 9:00 AM');
    });
  });

  group('what the server says', () {
    test('phases', () {
      expect(recoveryPhaseFromWire('waiting'), RecoveryPhase.waiting);
      expect(recoveryPhaseFromWire('waiting_for_helper'), RecoveryPhase.waitingForHelper);
      expect(recoveryPhaseFromWire('ready'), RecoveryPhase.ready);
      expect(recoveryPhaseFromWire('stopped'), RecoveryPhase.stopped);
      expect(recoveryPhaseFromWire('something new'), RecoveryPhase.unknown);
      expect(recoveryIsOpen(RecoveryPhase.waiting), isTrue);
      expect(recoveryIsOpen(RecoveryPhase.stopped), isFalse);
      expect(recoveryIsOpen(RecoveryPhase.unknown), isFalse);
    });

    test('a damaged answer is read as nothing, never as an error', () {
      expect(SheetState.parse('x').exists, isFalse);
      expect(HelperState.parse(null).phase, HelperPhase.none);
      expect(HelperState.parse(<String, Object>{'state': 'martian'}).phase, HelperPhase.none);
      expect(RecoveryNotice.tryParse(<String, Object>{'requestId': 'not-an-id'}), isNull);
      final RecoverySummary s = RecoverySummary.tryParse(<String, dynamic>{})!;
      expect(s.open, isEmpty);
      expect(s.secondParentHours, 48);
      expect(s.soleParentHours, 72);
    });

    test('a summary', () {
      final RecoverySummary s = RecoverySummary.tryParse(<String, dynamic>{
        'sheet': <String, Object?>{'exists': true, 'createdAt': '2026-11-01T10:00:00Z', 'confirmedAt': '2026-11-01T10:05:00Z'},
        'helper': <String, Object?>{'state': 'active', 'label': 'Aunt Sam'},
        'open': <Object>[
          <String, Object?>{'requestId': _id, 'phase': 'waiting', 'mode': 'second_parent', 'accountName': 'Mom', 'aboutMe': true,
            'startedByName': 'Dad', 'createdAt': '2026-11-21T10:00:00Z', 'readyAt': '2026-11-23T10:00:00Z'},
          <String, Object?>{'requestId': 'junk'},
        ],
        'canHelp': <Object>[<String, Object?>{'userId': _id, 'name': 'Dad'}, <String, Object?>{'userId': 'junk'}],
        'waits': <String, Object>{'secondParentHours': 48, 'soleParentHours': 72},
      })!;
      expect(s.sheet.kept, isTrue);
      expect(s.helper.label, 'Aunt Sam');
      expect(s.open, hasLength(1));
      expect(s.canHelp.single.name, 'Dad');
    });
  });

  group('the sentence for a notice', () {
    RecoveryNotice n({bool sole = false, bool aboutMe = false, bool byMe = false, bool helper = false, bool yes = false, String? by}) =>
        RecoveryNotice(
            requestId: _id, phase: RecoveryPhase.waiting, soleParent: sole, accountName: 'Mom', aboutMe: aboutMe,
            startedByMe: byMe, startedByName: 'Dad', createdAt: DateTime(2026, 11, 21), readyAt: DateTime(2026, 11, 23, 9),
            helperRequired: helper, helperConfirmed: yes, stoppedBy: by);
    final DateTime now = DateTime(2026, 11, 21, 8);

    test('the owner is told, and told what to do', () {
      final String s = noticeSentence(n(aboutMe: true), now);
      expect(s, contains('Dad started getting your account onto a new phone'));
      expect(s, contains('Monday at 9:00 AM'));
      expect(s, contains('stop it now'));
    });

    test('another grown-up is told, without being told to panic', () {
      final String s = noticeSentence(n(), now);
      expect(s, contains('Dad is helping Mom'));
      expect(s, isNot(contains('stop it now')));
    });

    test('the grown-up who started it is told they did', () {
      expect(noticeSentence(n(byMe: true), now), startsWith('You are helping Mom'));
    });

    test('the sheet, with and without a helper', () {
      expect(noticeSentence(n(sole: true, aboutMe: true), now), contains('printed recovery sheet'));
      expect(noticeSentence(n(sole: true, helper: true), now), contains('trusted helper also has to say yes'));
      expect(noticeSentence(n(sole: true, helper: true, yes: true), now), contains('has said yes'));
    });

    test('an ended recovery is never a mystery', () {
      for (final String by in <String>['owner_phone', 'other_parent', 'helper', 'new_phone', 'too_many_wrong', 'sheet_replaced', 'expired', 'unheard-of']) {
        expect(endedSentence(n(by: by)), endsWith('Nothing changed.'));
      }
      expect(endedSentence(n(by: 'helper')), contains('helper said no'));
    });
  });

  group('every answer has words', () {
    // Words a person should never meet. "server" and "account" are ordinary words; "session" and "token" are not.
    final RegExp jargon = RegExp(r'token|credential|hash|revoke|session|encrypt|exception|json|http|status code|null|rls|api\b', caseSensitive: false);

    test('every reason the recovery routes can answer with is worded, in plain words, and never as itself', () {
      for (final String reason in kRecoveryKnownReasons) {
        final AccountProblem p = recoveryProblemFor(ApiException.fromStatus(403, reason), RecoveryAction.finish);
        expect(p.message.trim(), isNotEmpty, reason: reason);
        expect(p.message, isNot(contains(reason)), reason: '$reason must not be shown as a code');
        expect(p.message.contains('_'), isFalse, reason: reason);
        expect(jargon.hasMatch(p.message), isFalse, reason: '$reason: ${p.message}');
        if (reason != 'rate_limited' && reason != 'recovery_rate_limited') expect(p.reason, isNotEmpty);
      }
    });

    test('too many tries, a server fault, a lost connection and an odd error are calm sentences', () {
      final List<Object> errors = <Object>[
        ApiException.fromStatus(429, 'recovery_rate_limited'),
        ApiException.fromStatus(500, 'boom'),
        ApiException.fromStatus(502, 'bad gateway'),
        const SocketException('refused'),
        TimeoutException('slow'),
        StateError('x'),
      ];
      for (final Object e in errors) {
        final AccountProblem p = recoveryProblemFor(e, RecoveryAction.startWithSheet);
        expect(jargon.hasMatch(p.message), isFalse, reason: p.message);
        expect(p.message, isNot(contains('StateError')));
        expect(p.message, isNot(contains('refused')));
        expect(p.message.length, lessThan(400));
      }
      expect(recoveryProblemFor(ApiException.fromStatus(429, 'x'), RecoveryAction.finish).message,
          contains('does not lock anyone out'));
    });

    test('an unknown reason still gets words, and never the code', () {
      final AccountProblem p = recoveryProblemFor(ApiException.fromStatus(403, 'brand_new_reason'), RecoveryAction.finish);
      expect(p.message, isNot(contains('brand_new_reason')));
      expect(p.kind, ProblemKind.tryAgain);
    });

    test('the sentences that say what is still true say so', () {
      expect(recoveryProblemFor(ApiException.fromStatus(403, 'too_many_wrong'), RecoveryAction.finish).message, contains('Nothing was changed'));
      expect(recoveryProblemFor(ApiException.fromStatus(403, 'invalid_sheet'), RecoveryAction.startWithSheet).message, contains('Nothing was changed'));
      expect(recoveryProblemFor(ApiException.fromStatus(403, 'ask_other_grownup'), RecoveryAction.startWithSheet).message, contains('Nothing was changed'));
      expect(recoveryProblemFor(ApiException.fromStatus(409, 'waiting_for_helper'), RecoveryAction.finish, helperName: 'Aunt Sam').message,
          contains('Aunt Sam'));
    });
  });

  group('the printed sheet', () {
    test('has the key in large type, a first name, and four short lines of plain words', () {
      final String html = recoverySheetHtml(key: 'K7Q2-M9XD-ABCD-EFGH-JKMN-PQRS', forName: 'Sam <b>', made: DateTime(2026, 11, 21));
      expect(html, contains('K7Q2-M9XD-ABCD-EFGH-JKMN-PQRS'));
      expect(html, contains('Sam &lt;b&gt;'), reason: 'a name cannot inject markup into the page');
      expect(html, isNot(contains('<b>Sam <b>')));
      expect(html, contains('2026-11-21'));
      expect(html, contains('never asks for this key by phone call, text or email'));
      expect(html, contains('Lost your phone?'));
    });

    test('carries no server address, no link and no child\'s name', () {
      final String html = recoverySheetHtml(key: 'K7Q2-M9XD-ABCD-EFGH-JKMN-PQRS', forName: '', made: DateTime(2026, 11, 21));
      expect(html, isNot(contains('http')));
      expect(html, isNot(contains('olive.')));
      expect(html, contains('My family'));
    });
  });
}
