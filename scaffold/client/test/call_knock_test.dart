// OLIVE BRANCH — call_knock.dart tests. MASTERFILE §5.25.2.
// A deliberately partial 1:1 port of lifecycle.ts's §5.25.2 "knocking"
// section — this file proves the port matches the TS source's own behavior,
// mirroring how a11y_speech_test.dart proves a11y.ts's port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_knock.dart';

void main() {
  group('knock() / Knock — waits, never escalates', () {
    test('builds with the real 90-second wait by default', () {
      final k = knock('Dad', '2026-08-19T10:00:00Z');
      expect(k.from, 'Dad');
      expect(k.at, '2026-08-19T10:00:00Z');
      expect(k.waitsSeconds, knockWaitsSeconds);
    });

    test('KNOCK_WAITS_SECONDS is really 90', () {
      expect(knockWaitsSeconds, 90);
    });

    test('never escalates, unconditionally', () {
      expect(knock('Dad', 'now').escalates, isFalse);
    });
  });

  group('knockUnanswered — never reported as missed, declined, or ignored', () {
    test('becomes a banked message', () {
      expect(knockUnanswered.becomes, 'banked_message');
    });

    test("the sender is told she did not come to it, never that she declined", () {
      expect(knockUnanswered.toldToSender, contains('did not come to it'));
      expect(knockUnanswered.toldToSender.toLowerCase(), isNot(contains('declin')));
      expect(knockUnanswered.toldToSender.toLowerCase(), isNot(contains('missed')));
      expect(knockUnanswered.toldToSender.toLowerCase(), isNot(contains('ignor')));
    });

    test('and reassures it is saved for her', () {
      expect(knockUnanswered.toldToSender, contains('saved for her'));
    });
  });

  group('answerWords — the real three, in order', () {
    test('exactly Answer, Just talking, Not now', () {
      expect(answerWords, ['Answer', 'Just talking', 'Not now']);
    });

    test('"Not now" is a real answer and it is not a decline', () {
      expect(answerWords, contains('Not now'));
    });
  });

  group('auditAnswerWords — the answer surface must never say decline/reject/etc.', () {
    test('the real shipped words all pass', () {
      expect(auditAnswerWords(answerWords).ok, isTrue);
    });

    test('a word containing "decline" fails', () {
      final audit = auditAnswerWords(['Decline']);
      expect(audit.ok, isFalse);
      expect(audit.found, contains('Decline'));
    });

    test('case-insensitive: "REJECT" still caught', () {
      expect(auditAnswerWords(['REJECT']).ok, isFalse);
    });

    test('every banned word is actually banned', () {
      for (final w in answerBanned) {
        expect(auditAnswerWords([w]).ok, isFalse, reason: '"$w" should be caught');
      }
    });

    test('an unrelated, unbanned word passes cleanly', () {
      expect(auditAnswerWords(['Later']).ok, isTrue);
    });
  });

  group('notNowOutcome — a real answer, framed gently on both ends', () {
    test('the line told to her carries no guilt or urgency', () {
      expect(notNowOutcome.line, 'Alright. He knows you are busy.');
    });

    test('the sender is offered a real next step, not just informed', () {
      expect(notNowOutcome.senderTold, contains('Record her something?'));
    });

    test('neither string uses a banned word', () {
      final audit = auditAnswerWords([notNowOutcome.line, notNowOutcome.senderTold]);
      expect(audit.ok, isTrue);
    });
  });
}
