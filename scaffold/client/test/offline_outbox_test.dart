// OLIVE BRANCH — offline_outbox.dart tests. MASTERFILE §5.22.
// A deliberately partial 1:1 port of packages/offline/src/offline.ts's real
// outbox state machine — this file proves the port matches the TS source's
// own behavior, mirroring how device_channels_test.dart proves devices.ts's
// port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/offline_outbox.dart';

OutboxItem _item(String id, {DateTime? createdAt, int attempts = 0}) => OutboxItem(
      id: id,
      kind: OutboxKind.message,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      payload: const <String, Object>{'storageKey': 'k', 'durationMs': 1},
      attempts: attempts,
    );

void main() {
  group('OutboxKind.wireValue — matches offline.ts\'s own union exactly', () {
    test('every kind round-trips to its real snake_case wire value', () {
      const expected = {
        OutboxKind.show: 'show',
        OutboxKind.drawing: 'drawing',
        OutboxKind.message: 'message',
        OutboxKind.voice: 'voice',
        OutboxKind.colouring: 'colouring',
        OutboxKind.journal: 'journal',
        OutboxKind.listItem: 'list_item',
        OutboxKind.storyStar: 'story_star',
        OutboxKind.ping: 'ping',
      };
      for (final entry in expected.entries) {
        expect(entry.key.wireValue, entry.value);
      }
    });
  });

  group('enqueue — §5.22, ping is the one kind that must never be queued', () {
    test('a queueable kind is appended, not dropped', () {
      final result = enqueue(const <OutboxItem>[], _item('a'));
      expect(result.dropped, isFalse);
      expect(result.outbox.map((i) => i.id), <String>['a']);
    });

    test('a ping is silently dropped -- delivering it late would be a small lie',
        () {
      final ping = OutboxItem(
          id: 'p', kind: OutboxKind.ping, createdAt: DateTime(2026, 1, 1), payload: null);
      final result = enqueue(const <OutboxItem>[], ping);
      expect(result.dropped, isTrue);
      expect(result.outbox, isEmpty);
    });
  });

  group('nextToSend — oldest first, never an item at maxAttempts', () {
    test('picks the oldest eligible item', () {
      final outbox = <OutboxItem>[
        _item('newer', createdAt: DateTime(2026, 1, 2)),
        _item('older', createdAt: DateTime(2026, 1, 1)),
      ];
      expect(nextToSend(outbox)?.id, 'older');
    });

    test('an item at maxAttempts is never returned', () {
      final outbox = <OutboxItem>[_item('stuck', attempts: maxAttempts)];
      expect(nextToSend(outbox), isNull);
    });

    test('an empty outbox has nothing to send', () {
      expect(nextToSend(const <OutboxItem>[]), isNull);
    });
  });

  group('recordFailure / sent — the only two real transitions an item makes', () {
    test('recordFailure increments attempts and records the real error, '
        'leaving every other item untouched', () {
      final outbox = <OutboxItem>[_item('a'), _item('b')];
      final next = recordFailure(outbox, 'a', 'connection refused');
      final a = next.firstWhere((i) => i.id == 'a');
      final b = next.firstWhere((i) => i.id == 'b');
      expect(a.attempts, 1);
      expect(a.lastError, 'connection refused');
      expect(b.attempts, 0);
      expect(b.lastError, isNull);
    });

    test('sent removes exactly the confirmed item, nothing else', () {
      final outbox = <OutboxItem>[_item('a'), _item('b')];
      final next = sent(outbox, 'a');
      expect(next.map((i) => i.id), <String>['b']);
    });

    test('sent on an id never queued is a harmless no-op', () {
      final outbox = <OutboxItem>[_item('a')];
      expect(sent(outbox, 'never-queued').map((i) => i.id), <String>['a']);
    });
  });

  group('backoffMs — real exponential backoff, capped at six hours', () {
    test('doubles per attempt from a one-minute floor', () {
      expect(backoffMs(0), 60000);
      expect(backoffMs(1), 120000);
      expect(backoffMs(2), 240000);
    });

    test('never exceeds six hours', () {
      expect(backoffMs(20), 6 * 60 * 60000);
    });
  });

  group('offlineChildView — deliberately not a queue', () {
    test('nothing waiting: no line, nothing to reassure her about', () {
      final view = offlineChildView(const <OutboxItem>[]);
      expect(view.anythingWaiting, isFalse);
      expect(view.line, isEmpty);
    });

    test('something waiting: the one honest sentence, regardless of how '
        'many attempts or items -- never "3 pending, 2 failed"', () {
      final view = offlineChildView(<OutboxItem>[_item('a', attempts: 5), _item('b')]);
      expect(view.anythingWaiting, isTrue);
      expect(view.line, 'It will go when you have internet again. It is safe.');
    });
  });

  group('auditChildOfflineCopy — the same runtime self-check offline.ts '
      'itself would run before this copy ever reaches her', () {
    test('the real offlineChildView line passes', () {
      final line = offlineChildView(<OutboxItem>[_item('a')]).line;
      expect(auditChildOfflineCopy(line), isTrue);
    });

    test('every banned word fails the audit', () {
      for (final word in offlineForbidden) {
        expect(auditChildOfflineCopy('it is $word right now'), isFalse,
            reason: '"$word" must be caught by the audit');
      }
    });
  });
}
