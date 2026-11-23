// OLIVE BRANCH — family_account_logic.dart: the input rules, the words for failures, the invite listing and the
// resume plan. Pure, headless. MASTERFILE section 8.5.13.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/api_client.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/server_transport_policy.dart' show TransportPolicyViolation;

const String _id = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';

void main() {
  group('what a grown-up types is cleaned the way the server will clean it', () {
    test('the operator invite code: no spaces, 20 to 128 visible characters', () {
      expect(cleanAllowanceCode('abcdefghij0123456789'), 'abcdefghij0123456789');
      expect(cleanAllowanceCode(' abcdefghij\n0123456789 '), 'abcdefghij0123456789');
      expect(cleanAllowanceCode('short'), isNull);
      expect(cleanAllowanceCode('a' * 19), isNull);
      expect(cleanAllowanceCode('a' * 128), isNotNull);
      expect(cleanAllowanceCode('a' * 129), isNull);
      expect(cleanAllowanceCode('${'a' * 20}\u0000'), isNull, reason: 'a control character is not a code');
      expect(cleanAllowanceCode('${'a' * 20}é'), isNull, reason: 'not visible ASCII');
    });

    test('an invite code is a UUID and nothing else: it goes into a URL path', () {
      expect(cleanInviteCode(_id), _id);
      expect(cleanInviteCode(' "${_id.toUpperCase()}"\n'), _id);
      expect(cleanInviteCode('(<$_id>)'), _id);
      for (final String bad in <String>[
        '', 'abc', '../../me', '$_id/../me', '$_id?x=1', '$_id#frag', '${_id}0', '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5g',
        '3f2a9c1e 4b7d 4c1a 9e3f 0a1b2c3d4e5f x',
      ]) {
        expect(cleanInviteCode(bad), isNull, reason: bad);
      }
    });

    test('names: collapsed, bounded by characters not bytes, no control characters', () {
      expect(cleanPersonName('  Sam   Lee ', 60), 'Sam Lee');
      expect(cleanPersonName('', 60), isNull);
      expect(cleanPersonName('   ', 60), isNull);
      expect(cleanPersonName('x' * 61, 60), isNull);
      expect(cleanPersonName('x' * 60, 60), isNotNull);
      expect(cleanPersonName('\u{1F600}' * 40, 40), isNotNull, reason: '40 characters, even though each is 2 UTF-16 units');
      expect(cleanPersonName('\u{1F600}' * 41, 40), isNull);
      expect(cleanPersonName('Sa\u0000m', 60), isNull);
      expect(cleanPersonName('Sa\u007fm', 60), isNull);
      // A line separator is whitespace to the server's own collapse too, so it becomes a space there as well.
      expect(cleanPersonName('Sa m', 60), 'Sa m');
      expect(cleanPersonName('Zoë', 60), 'Zoë');
    });

    test('email: plain shape only, nothing that can carry a second header line', () {
      expect(cleanEmail(' robin@example.com '), 'robin@example.com');
      for (final String bad in <String>[
        '', 'robin', 'robin@', '@example.com', 'robin@example', 'a b@example.com', 'robin@exa mple.com',
        'robin@example.com\nBcc: x@example.org', 'a@@b.co', '${'a' * 250}@b.co',
      ]) {
        expect(cleanEmail(bad), isNull, reason: bad);
      }
    });

    test('a masked email is enough to recognise and not enough to pass on', () {
      expect(maskEmail('robin@example.com'), 'r***@example.com');
      expect(maskEmail('nonsense'), 'an email address');
      expect(maskEmail(''), 'an email address');
    });

    test('birth date: real, not in the future, under 18, in whole calendar days', () {
      final DateTime now = DateTime(2026, 11, 15, 9);
      expect(problemForBirthDate(null, now), isNotNull);
      expect(problemForBirthDate(DateTime(2026, 11, 16), now), contains('not happened'));
      expect(problemForBirthDate(DateTime(2026, 11, 15), now), isNull, reason: 'born today');
      expect(problemForBirthDate(DateTime(2019, 3, 4), now), isNull);
      expect(problemForBirthDate(DateTime(2008, 11, 16), now), isNull, reason: 'still 17 until tomorrow');
      expect(problemForBirthDate(DateTime(2008, 11, 15), now), isNotNull, reason: '18 today');
      expect(birthDateWire(DateTime(2019, 3, 4)), '2019-03-04');
      expect(birthDateWire(DateTime(987, 1, 2)), '0987-01-02');
    });

    test('the age already set on this phone is only ever a soft note', () {
      final DateTime now = DateTime(2026, 11, 15);
      expect(ageMismatchNote(DateTime(2019, 3, 4), 7, now), isNull);
      expect(ageMismatchNote(DateTime(2019, 3, 4), 8, now), isNull, reason: 'within a year');
      expect(ageMismatchNote(DateTime(2019, 3, 4), 12, now), contains('keeps the age already set'));
      expect(ageMismatchNote(null, 12, now), isNull);
      expect(ageMismatchNote(DateTime(2019, 3, 4), null, now), isNull);
    });

    test('a new PIN: 4 to 8 digits, nothing obvious', () {
      expect(problemForNewPin('4821'), isNull);
      expect(problemForNewPin('48210937'), isNull);
      for (final String bad in <String>['123', '123456789', 'abcd', '48 21', '', '1111', '1234', '4321', '0000', '7890']) {
        expect(problemForNewPin(bad), isNotNull, reason: bad);
      }
      expect(looksLikePin('1234'), isTrue, reason: 'proving an existing PIN is not the same as choosing one');
    });
  });

  group('invites, as the sender sees them', () {
    Map<String, Object?> listing(String status, {String? claimant}) => <String, Object?>{
          'id': _id, 'role': 'guardian', 'label': 'Mama', 'invitedEmail': 'robin@example.com', 'status': status,
          'createdAt': '2026-11-01T00:00:00.000Z', 'expiresAt': '2026-11-20T00:00:00.000Z', 'claimantName': claimant,
        };

    test('every state reads as a calm sentence and offers only what can be done', () {
      final Map<String, (List<InviteAction>, Pattern)> expected = <String, (List<InviteAction>, Pattern)>{
        'sent': (<InviteAction>[InviteAction.cancel], 'Waiting for them to open it'),
        'accepted': (<InviteAction>[InviteAction.turnAway], 'not finished joining'),
        'waiting_for_you': (<InviteAction>[InviteAction.confirm, InviteAction.turnAway], 'Robin is asking to join'),
        'confirmed': (<InviteAction>[], 'Robin joined as parent or guardian'),
        'declined': (<InviteAction>[], 'turned this one away'),
        'revoked': (<InviteAction>[], 'cancelled'),
        'expired': (<InviteAction>[], 'ran out'),
      };
      for (final MapEntry<String, (List<InviteAction>, Pattern)> e in expected.entries) {
        final InviteView v = InviteView.tryParse(listing(e.key, claimant: 'Robin'))!;
        expect(v.actions, e.value.$1, reason: e.key);
        expect(v.statusLine(), contains(e.value.$2), reason: e.key);
        expect(v.statusLine(), isNot(contains('robin@example.com')), reason: 'the email is masked in the line');
        expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(v.statusLine()), isFalse, reason: '${e.key} leaks a code');
      }
    });

    test('a damaged listing from the server is dropped or softened, never trusted', () {
      expect(InviteView.tryParse(null), isNull);
      expect(InviteView.tryParse('x'), isNull);
      expect(InviteView.tryParse(<String, Object?>{'id': 42}), isNull);
      expect(InviteView.tryParse(<String, Object?>{'id': '../../x'}), isNull);
      final InviteView v = InviteView.tryParse(<String, Object?>{'id': _id, 'status': 'from_the_future', 'role': 7, 'label': null})!;
      expect(v.state, InviteState.unknown);
      expect(v.role, '');
      expect(v.actions, isEmpty);
      expect(v.statusLine(), isNotEmpty);
    });

    test('roles: the list is the server\'s, each with a plain name', () {
      expect(kInvitableRoles, containsAll(<String>['guardian', 'step_parent', 'trusted_adult', 'sitter', 'coordinator']));
      for (final String r in kInvitableRoles) {
        expect(inviteRoleWords(r), isNot(contains('_')));
      }
    });
  });

  group('where to resume', () {
    test('every combination lands on a sensible step', () {
      AccountStep plan({required bool sign, bool join = false, int? kids, bool rec = false}) =>
          planAccountStep(hasSignIn: sign, joiningInvite: join, childCount: kids, hasRecordedChild: rec);
      expect(plan(sign: false), AccountStep.start);
      expect(plan(sign: false, join: true), AccountStep.finishJoining);
      expect(plan(sign: true, kids: 0), AccountStep.addChild);
      expect(plan(sign: true, kids: 2), AccountStep.family);
      expect(plan(sign: true, kids: null), AccountStep.addChild, reason: 'offline, nothing remembered');
      expect(plan(sign: true, kids: null, rec: true), AccountStep.family, reason: 'offline, a child was added');
      expect(plan(sign: true, join: true, kids: 0), AccountStep.finishJoining, reason: 'waiting for the inviter');
      expect(plan(sign: true, join: true, kids: 1), AccountStep.family, reason: 'the inviter said yes');
    });
  });

  group('failures, in words', () {
    final List<AccountAction> all = AccountAction.values;

    test('every server reason has its own sentence under every action: no code, no status, no jargon', () {
      for (final String code in kKnownServerReasons) {
        for (final int status in <int>[400, 401, 403, 404, 409, 410]) {
          for (final AccountAction a in all) {
            final AccountProblem p = problemFor(ApiException(status, code), a);
            expect(p.message, isNotEmpty);
            expect(p.message, isNot(contains(code)), reason: '$code under $a leaks its code');
            expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(p.message), isFalse, reason: '"${p.message}" ($code, $a)');
            expect(RegExp(r'\b[1-5]\d\d\b').hasMatch(p.message), isFalse, reason: '"${p.message}" has a status');
            expect(p.message, isNot(contains('Exception')));
            expect(p.message.endsWith('.') || p.message.endsWith('?'), isTrue, reason: p.message);
          }
        }
      }
    });

    test('the ones that need care are worded for their context', () {
      for (final Object e in <Object>[TimeoutException('x'), const SocketException('x'), http.ClientException('x')]) {
        final AccountProblem p = problemFor(e, AccountAction.recover);
        expect(p.message, contains('may have been used'));
        expect(p.message, contains('new one'));
        expect(p.kind, ProblemKind.tryAgain);
      }
      expect(problemFor(ApiException(404, 'not_found'), AccountAction.lookUpInvite).message, contains('invite code'));
      expect(problemFor(ApiException(404, 'not_found'), AccountAction.useInviteWithAccount).message, contains('different email'));
      expect(problemFor(ApiException(404, 'not_found'), AccountAction.confirmInvite).message, contains('no longer there'));
      expect(problemFor(ApiException(409, 'already_accepted'), AccountAction.cancelInvite).message, contains('Turn them away'));
      expect(problemFor(ApiException(409, 'already_accepted'), AccountAction.joinInvite).message, contains('already opened'));
      expect(problemFor(ApiException(410, 'declined'), AccountAction.checkJoin).message, contains('decided not to add you'));
      expect(problemFor(ApiException(403, 'pin_locked'), AccountAction.confirmInvite).kind, ProblemKind.wait);
      expect(problemFor(ApiException(403, 'pin_incorrect'), AccountAction.confirmInvite).message, "That PIN isn't right.");
      expect(problemFor(ApiException(409, 'family_full'), AccountAction.confirmInvite).message, contains('4 parents and 8'));
      expect(problemFor(ApiException(401, 'device_revoked'), AccountAction.loadFamily).kind, ProblemKind.needsSignIn);
      expect(problemFor(ApiException(429, 'rate_limited'), AccountAction.signUp).kind, ProblemKind.wait);
    });

    test('a server code Olive has never heard of still reads as a sentence', () {
      for (final int status in <int>[400, 401, 403, 404, 409, 410, 500, 502, 503]) {
        final AccountProblem p = problemFor(ApiException(status, 'a_code_from_the_future'), AccountAction.createInvite);
        expect(p.message, isNot(contains('a_code_from_the_future')));
        expect(p.message, isNotEmpty);
      }
    });

    test('a lost reply on a change says the outcome is unknown; on a read it just says to try again', () {
      final AccountProblem change = problemFor(const SocketException('x'), AccountAction.createInvite);
      final AccountProblem read = problemFor(const SocketException('x'), AccountAction.loadFamily);
      expect(change.message, contains("can't be sure"));
      expect(read.message, isNot(contains("can't be sure")));
      for (final Object e in <Object>[
        TimeoutException('t'), const SocketException('s'), http.ClientException('c'), const HandshakeException('h'),
      ]) {
        expect(problemFor(e, AccountAction.addChild).kind, ProblemKind.tryAgain, reason: '$e');
      }
    });

    test('a build that may not reach a server says so', () {
      final AccountProblem p = problemFor(const TransportPolicyViolation('cleartext'), AccountAction.signUp);
      expect(p.kind, ProblemKind.cannot);
      expect(p.message, isNot(contains('cleartext')));
    });

    test('anything else is "nothing was changed on this phone"', () {
      final AccountProblem p = problemFor(StateError('boom'), AccountAction.signUp);
      expect(p.message, isNot(contains('boom')));
      expect(p.message, contains('Nothing was changed'));
    });
  });
}
