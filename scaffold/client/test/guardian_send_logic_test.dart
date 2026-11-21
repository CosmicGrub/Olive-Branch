// OLIVE BRANCH — guardian_send_logic.dart tests. Run by CI; nothing here has run on a device.
// MASTERFILE §8.31, §8.2.3. Pure logic: no widget, no network, no device.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_send_logic.dart';

DayPartEntry p(String kind, String s, String e, {List<int>? days, bool reachable = true}) => DayPartEntry(
    kind: kind, startsLocal: s, endsLocal: e, days: days ?? const <int>[0, 1, 2, 3, 4, 5, 6], reachable: reachable);

final List<DayPartEntry> seeded = <DayPartEntry>[
  p('wake', '06:30', '08:00'),
  p('free', '08:00', '19:30'),
  p('bedtime', '19:30', '20:30'),
  p('asleep', '20:30', '06:30', reachable: false),
];

void main() {
  group('times and words', () {
    test('parseHm accepts only strict 24-hour HH:MM', () {
      expect(parseHm('00:00'), 0);
      expect(parseHm('23:59'), 23 * 60 + 59);
      for (final Object? bad in <Object?>['24:00', '7:30', '07:60', '07:3', '07:30:00', ' 07:30', '', null, 730, '7am']) {
        expect(parseHm(bad), isNull, reason: '$bad');
      }
    });

    test('12-hour words, and a strange value is shown rather than hidden', () {
      expect(hmTo12h('00:00'), '12:00 AM');
      expect(hmTo12h('12:05'), '12:05 PM');
      expect(hmTo12h('20:30'), '8:30 PM');
      expect(hmTo12h('06:30'), '6:30 AM');
      expect(hmTo12h('nonsense'), 'nonsense');
    });

    test('days are described the way a person says them', () {
      expect(describeDays(<int>[0, 1, 2, 3, 4, 5, 6]), 'every day');
      expect(describeDays(<int>[1, 2, 3, 4, 5]), 'weekdays');
      expect(describeDays(<int>[6, 0]), 'weekends');
      expect(describeDays(<int>[5, 1, 3]), 'Mon, Wed, Fri');
    });

    test('every kind the server accepts has a title and a "when" phrase that is not the raw code', () {
      for (final String k in kDayPartKinds) {
        expect(dayPartTitle(k), isNot(contains('_')), reason: k);
        expect(dayPartWhen(k), isNot(contains('_')), reason: k);
      }
      expect(dayPartTitle('bedtime'), 'Bedtime');
      expect(dayPartWhen('bedtime'), 'at bedtime');
    });

    test('describeDayPart reads in adult words and marks an overnight part', () {
      expect(describeDayPart(seeded[3]), 'Asleep: 8:30 PM to 6:30 AM the next morning, every day. She cannot be reached.');
      expect(describeDayPart(seeded[2]), 'Bedtime: 7:30 PM to 8:30 PM, every day. She can be reached.');
    });
  });

  group('DayPartEntry.fromWire is defensive', () {
    Map<String, Object?> ok() => <String, Object?>{
          'kind': 'bedtime', 'startsLocal': '20:30', 'endsLocal': '07:00', 'daysOfWeek': <int>[3, 1], 'reachable': true};

    test('reads a real row and sorts the days', () {
      final DayPartEntry? e = DayPartEntry.fromWire(ok());
      expect(e, isNotNull);
      expect(e!.days, <int>[1, 3]);
      expect(e.wrapsMidnight, isTrue);
    });

    test('a missing daysOfWeek means every day', () {
      final Map<String, Object?> m = ok()..remove('daysOfWeek');
      expect(DayPartEntry.fromWire(m)!.days.length, 7);
    });

    test('any malformed row is null, never a crash and never a guess', () {
      final List<Object?> bad = <Object?>[
        null, 'x', 5, <Object?>[],
        <String, Object?>{...ok(), 'kind': 5},
        <String, Object?>{...ok(), 'kind': ''},
        <String, Object?>{...ok(), 'kind': 'x' * 500},
        <String, Object?>{...ok(), 'startsLocal': '25:00'},
        <String, Object?>{...ok(), 'endsLocal': null},
        <String, Object?>{...ok(), 'reachable': 'yes'},
        <String, Object?>{...ok(), 'daysOfWeek': <Object?>[1, 'a']},
        <String, Object?>{...ok(), 'daysOfWeek': <int>[7]},
        <String, Object?>{...ok(), 'daysOfWeek': <int>[-1]},
        <String, Object?>{...ok(), 'daysOfWeek': <int>[]},
        <String, Object?>{...ok(), 'daysOfWeek': 'all'},
      ];
      for (final Object? b in bad) {
        expect(DayPartEntry.fromWire(b), isNull, reason: '$b');
      }
    });

    test('DayPartsView counts the rows it could not read instead of hiding them', () {
      final DayPartsView v = DayPartsView.parse(<String, Object?>{
        'dayParts': <Object?>[ok(), 'junk', <String, Object?>{...ok(), 'startsLocal': 'bad'}],
      });
      expect(v.parts.length, 1);
      expect(v.skipped, 2);
      expect(v.hasBedtime, isTrue);
      expect(DayPartsView.parse(null).parts, isEmpty);
      expect(DayPartsView.parse(<String, Object?>{'dayParts': 'no'}).parts, isEmpty);
    });

    test('toWire round-trips and is order independent for comparison', () {
      final DayPartEntry e = DayPartEntry.fromWire(ok())!;
      expect(DayPartEntry.fromWire(e.toWire()), e);
      expect(sameSchedule(seeded, seeded.reversed.toList()), isTrue);
      expect(sameSchedule(seeded, <DayPartEntry>[...seeded.take(3)]), isFalse);
      expect(sameSchedule(seeded, <DayPartEntry>[...seeded.take(3), seeded[3].copyWith(reachable: true)]), isFalse);
    });
  });

  group('checkDayParts mirrors the server', () {
    test('the seeded day is valid and has no warnings', () {
      final DayPartsCheck c = checkDayParts(seeded);
      expect(c.errors, isEmpty);
      expect(c.warnings, isEmpty);
      expect(c.canSave, isTrue);
    });

    test('an empty schedule is refused, with the reason in words', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[]);
      expect(c.canSave, isFalse);
      expect(c.errors.single.code, 'day_parts_required');
      expect(c.errors.single.text, contains('at least one part'));
    });

    test('more than 24 parts is refused', () {
      final List<DayPartEntry> many = <DayPartEntry>[
        for (int i = 0; i < 25; i++) p('free', formatHm(i * 30), formatHm(i * 30 + 10), days: <int>[i % 7]),
      ];
      expect(checkDayParts(many).errors.any((DayPartProblem e) => e.code == 'too_many'), isTrue);
    });

    test('start equal to end is an empty part', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[p('bedtime', '20:00', '20:00')]);
      expect(c.errors.single.code, 'empty_day_part');
    });

    test('a bad time, an unknown kind and a bad day list are each named', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[
        p('bedtime', '8pm', '20:30'),
        p('lunchtime', '12:00', '13:00'),
        p('free', '09:00', '10:00', days: <int>[]),
        p('free', '09:00', '10:00', days: <int>[1, 1]),
        p('free', '09:00', '10:00', days: <int>[7]),
      ]);
      final Set<String> codes = c.errors.map((DayPartProblem e) => e.code).toSet();
      expect(codes, containsAll(<String>['bad_day_part_time', 'bad_day_part_kind', 'bad_days_of_week']));
      expect(c.errors.where((DayPartProblem e) => e.code == 'bad_days_of_week').length, 3);
    });

    test('same kind overlapping on a shared weekday is refused; touching ends are fine', () {
      expect(checkDayParts(<DayPartEntry>[p('free', '08:00', '12:00'), p('free', '11:00', '15:00')]).errors.single.code,
          'day_parts_overlap');
      expect(checkDayParts(<DayPartEntry>[p('free', '08:00', '12:00'), p('free', '12:00', '15:00'), p('bedtime', '19:30', '20:30')]).errors,
          isEmpty, reason: 'half-open ranges: ending when the next starts is not an overlap');
    });

    test('same kind at the same time on DIFFERENT days is fine (a weekday and a weekend school-free day)', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[
        p('free', '08:00', '19:30', days: <int>[0, 6]),
        p('free', '15:30', '19:30', days: <int>[1, 2, 3, 4, 5]),
        p('bedtime', '19:30', '20:30'),
      ]);
      expect(c.errors, isEmpty);
    });

    test('different kinds may overlap freely', () {
      expect(checkDayParts(<DayPartEntry>[p('school', '08:00', '15:00'), p('free', '12:00', '13:00'), p('bedtime', '20:00', '21:00')]).errors,
          isEmpty);
    });

    test('an overnight part is modelled as running to the same clock time the next day, as migration 0042 does', () {
      // Two overnight asleep parts that both cross midnight overlap...
      expect(checkDayParts(<DayPartEntry>[p('asleep', '20:30', '06:30'), p('asleep', '22:00', '05:00'), p('bedtime', '19:30', '20:30')]).errors.single.code,
          'day_parts_overlap');
      // ...and, exactly as on the server, an early-morning asleep part does NOT collide with the overnight one
      // (the server's range for a wrapped part ends the NEXT day, so 03:00-06:00 on day 0 is clear of it).
      expect(checkDayParts(<DayPartEntry>[p('asleep', '20:30', '06:30'), p('asleep', '03:00', '06:00'), p('bedtime', '19:30', '20:30')]).errors,
          isEmpty);
    });

    test('no bedtime is a warning, not an error: the server allows it', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[p('free', '08:00', '19:30')]);
      expect(c.canSave, isTrue);
      expect(c.warnings.single, contains('no Bedtime'));
    });

    test('a structurally bad part is not also reported as an overlap', () {
      final DayPartsCheck c = checkDayParts(<DayPartEntry>[p('free', 'zz', '12:00'), p('free', '08:00', '12:00')]);
      expect(c.errors.map((DayPartProblem e) => e.code), <String>['bad_day_part_time']);
    });

    test('every server refusal code has words that are not the raw code', () {
      for (final String code in <String>[
        'day_parts_required', 'bad_day_part_kind', 'bad_day_part_time', 'empty_day_part', 'bad_days_of_week',
        'reachable_required', 'day_parts_overlap', 'bad_day_part', 'not_a_child_surface', 'forbidden', 'who_knows'
      ]) {
        final String w = dayPartsErrorWords(code);
        expect(w, isNotEmpty);
        expect(w, isNot(contains('_')), reason: code);
      }
    });
  });

  group('DeliveryChoice', () {
    test('wire form is exactly what POST .../messages reads', () {
      expect(const DeliveryChoice.atDayPart('bedtime').toWire(), <String, Object?>{'daypart': 'bedtime'});
      expect(const DeliveryChoice.onNight('2026-12-24', dayPart: 'wake').toWire(),
          <String, Object?>{'daypart': 'wake', 'targetLocalDate': '2026-12-24'});
    });

    test('right away names itself and never carries a night (the route refuses both together)', () {
      final Map<String, Object?> w = const DeliveryChoice.now().toWire();
      expect(w['delivery'], 'now');
      expect(w.containsKey('targetLocalDate'), isFalse);
      expect(w['daypart'], isIn(kDayPartKinds), reason: 'whatever rides along must be a kind the route accepts');
      expect(const DeliveryChoice.atDayPart('bedtime').toWire().containsKey('delivery'), isFalse);
      expect(const DeliveryChoice.onNight('2026-12-24').toWire().containsKey('delivery'), isFalse);
    });

    test('json round-trips; anything off is null', () {
      for (final DeliveryChoice c in <DeliveryChoice>[
        const DeliveryChoice.atDayPart('free'),
        const DeliveryChoice.onNight('2026-02-28'),
        const DeliveryChoice.now(),
      ]) {
        expect(DeliveryChoice.fromJson(c.toJson()), c);
      }
      for (final Object? bad in <Object?>[
        null, 5, <String, Object?>{}, <String, Object?>{'k': 'part', 'p': 'lunch'},
        <String, Object?>{'k': 'night', 'p': 'bedtime'}, <String, Object?>{'k': 'night', 'p': 'bedtime', 'n': '2026-02-30'},
        <String, Object?>{'k': 'now', 'p': 'lunch'}, <String, Object?>{'k': 'now'},
        <String, Object?>{'k': 'later', 'p': 'bedtime'},
      ]) {
        expect(DeliveryChoice.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('parseNight rejects dates that are not on the calendar', () {
      expect(parseNight('2028-02-29'), isNotNull);
      expect(parseNight('2027-02-29'), isNull);
      expect(parseNight('2026-13-01'), isNull);
      expect(parseNight('26-01-01'), isNull);
      expect(parseNight('2026-1-1'), isNull);
      expect(nightWords('2026-11-21'), 'Sat 21 Nov');
      expect(nightWords('garbage'), 'garbage');
    });
  });

  group('right away', () {
    test('needs nothing from her day: it works with no parts at all, and with no bedtime', () {
      for (final List<DayPartEntry> day in <List<DayPartEntry>>[
        const <DayPartEntry>[],
        const <DayPartEntry>[DayPartEntry(kind: 'free', startsLocal: '08:00', endsLocal: '19:00', reachable: true)],
      ]) {
        final DeliveryCheck c = checkDelivery(const DeliveryChoice.now(), day, today: DateTime(2026, 11, 20));
        expect(c.ok, isTrue);
        expect(c.arrival, contains('as soon as Olive has it'));
      }
    });

    test('its phrase is "right away"', () {
      expect(deliveryPhrase(const DeliveryChoice.now()), 'right away');
      expect(sentStatusWords(const SentRow(id: 'abcdef1', state: 'waiting'), setFor: 'right away'),
          startsWith('Waiting to arrive right away.'));
    });

    test('the guard warns only when the server says she cannot be reached, in her clock, and never blocks', () {
      expect(rightAwayGuardNote('Ivy', localTime: '9:14 PM', dayPart: 'asleep', reachable: true), isNull);
      expect(rightAwayGuardNote('Ivy', localTime: '9:14 PM', dayPart: 'asleep', reachable: null), isNull,
          reason: 'unknown is not a warning');
      final String n = rightAwayGuardNote('Ivy', localTime: '9:14 PM', dayPart: 'asleep', reachable: false)!;
      expect(n, contains('It is 9:14 PM for Ivy right now.'));
      expect(n, contains('asleep'));
      expect(n, isNot(matches(RegExp(r'UTC|GMT|[+-]\d+ ?h'))), reason: 'her clock, never arithmetic in his');
      // No part named, no clock: still a sentence, never a crash or a "null".
      final String bare = rightAwayGuardNote('Ivy', reachable: false)!;
      expect(bare, isNot(contains('null')));
    });

    test('the new refusals have plain words and are never retried', () {
      for (final String code in <String>[
        'child_cannot_send_now', 'bad_delivery', 'now_has_no_date', 'date_required', 'daypart_has_no_date',
        'invalid_daypart',
      ]) {
        final SendFailure f = classifyFailure(statusCode: code == 'child_cannot_send_now' ? 403 : 400, error: code);
        expect(f.cls, FailureClass.needsAttention, reason: code);
        expect(f.words, isNot(contains('_')), reason: code);
        expect(classifyFailureByCode(f.code).words, f.words, reason: '$code survives a round trip through the store');
      }
      expect(classifyFailureByCode('stale_now').words, staleNowWords);
    });

    test('a queued right-away message survives the store, and an unknown kind is unreadable', () {
      const QueuedSend q = QueuedSend(
          id: 'm1abc-xyz123', childId: 'c', createdAtMs: 5, delivery: DeliveryChoice.now(),
          mediaB64: 'AAAA', durationMs: 10);
      expect(QueuedSend.fromJson(q.toJson())!.delivery, const DeliveryChoice.now());
      final Map<String, Object?> bad = q.toJson()..['delivery'] = <String, Object?>{'k': 'soon', 'p': 'bedtime'};
      expect(QueuedSend.fromJson(bad), isNull);
    });
  });

  group('checkDelivery (the send-time guard, on her day)', () {
    final DateTime today = DateTime(2026, 11, 20); // a Friday

    test('next bedtime reads her clock, not the sender\'s', () {
      final DeliveryCheck c = checkDelivery(const DeliveryChoice.atDayPart('bedtime'), seeded, today: today);
      expect(c.ok, isTrue);
      expect(c.arrival, 'Arrives at bedtime, from 7:30 PM her time.');
      expect(c.arrival, isNot(contains('UTC')));
      expect(c.notes, isEmpty);
    });

    test('a part she does not have is a blocker that says what to do', () {
      final DeliveryCheck c = checkDelivery(const DeliveryChoice.atDayPart('dinner'), seeded, today: today);
      expect(c.ok, isFalse);
      expect(c.blockers.single, contains('no Dinner part'));
    });

    test('a part marked unreachable warns but does not block: the guard is advisory', () {
      final DeliveryCheck c = checkDelivery(const DeliveryChoice.atDayPart('asleep'), seeded, today: today);
      expect(c.ok, isTrue);
      expect(c.notes.single, contains('cannot be reached while she is asleep'));
    });

    test('a night already gone is refused; tonight and yesterday-in-her-zone are allowed', () {
      expect(checkDelivery(const DeliveryChoice.onNight('2026-11-18'), seeded, today: today).ok, isFalse);
      expect(checkDelivery(const DeliveryChoice.onNight('2026-11-19'), seeded, today: today).ok, isTrue,
          reason: 'her calendar can be a day behind the sender\'s; the server settles it with its two-hour grace');
      expect(checkDelivery(const DeliveryChoice.onNight('2026-11-20'), seeded, today: today).ok, isTrue);
    });

    test('a night more than a year away is refused (a mistyped year)', () {
      expect(checkDelivery(const DeliveryChoice.onNight('2028-11-20'), seeded, today: today).ok, isFalse);
      expect(checkDelivery(const DeliveryChoice.onNight('2027-11-20'), seeded, today: today).ok, isTrue);
    });

    test('a named night with no date is a blocker', () {
      final DeliveryCheck c = checkDelivery(const DeliveryChoice.onNight('nope'), seeded, today: today);
      expect(c.ok, isFalse);
    });

    test('a part that does not run that weekday falls back to 8:30 PM, and says so (the server does the same)', () {
      final List<DayPartEntry> weekdaysOnly = <DayPartEntry>[
        p('bedtime', '19:30', '20:30', days: <int>[0, 1, 2, 3, 4]), p('free', '08:00', '19:30'),
      ];
      // 2026-11-21 is a Saturday (6): bedtime does not run.
      final DeliveryCheck c = checkDelivery(const DeliveryChoice.onNight('2026-11-21'), weekdaysOnly, today: today);
      expect(c.ok, isTrue);
      expect(c.arrival, contains('8:30 PM her time'));
      expect(c.notes.single, contains('does not run on Saturdays'));
      // A weekday: its own start.
      final DeliveryCheck d = checkDelivery(const DeliveryChoice.onNight('2026-11-23'), weekdaysOnly, today: today);
      expect(d.arrival, 'Arrives the night of Mon 23 Nov, at 7:30 PM her time.');
    });

    test('when her day could not be loaded nothing is blocked on a guess', () {
      expect(checkDelivery(const DeliveryChoice.atDayPart('bedtime'), const <DayPartEntry>[], today: today).ok, isTrue);
    });
  });

  group('failures, in words', () {
    test('no answer is retry-later and says the message is saved', () {
      final SendFailure f = classifyFailure();
      expect(f.cls, FailureClass.retryLater);
      expect(f.words, contains('saved on this phone'));
    });

    test('server refusals that retrying cannot fix need attention', () {
      for (final String e in <String>[
        'daypart_undefined', 'target_date_in_past', 'already_expired', 'delivery_unresolvable', 'empty_recording',
        'unsupported_media_type', 'media_quota_exceeded', 'not_authorized', 'child_not_found', 'storage_key_not_yours',
      ]) {
        expect(classifyFailure(statusCode: 400, error: e).cls, FailureClass.needsAttention, reason: e);
        expect(classifyFailure(statusCode: 400, error: e).words, isNot(contains('_')), reason: e);
      }
    });

    test('401, 408, 429 and 5xx are retry-later; an unknown 4xx needs attention', () {
      for (final int s in <int>[401, 408, 429, 500, 502, 503]) {
        expect(classifyFailure(statusCode: s, error: 'x').cls, FailureClass.retryLater, reason: '$s');
      }
      expect(classifyFailure(statusCode: 400, error: 'whatever').cls, FailureClass.needsAttention);
      expect(classifyFailure(statusCode: 403, error: 'x').cls, FailureClass.needsAttention);
    });

    test('no failure sentence ever contains a raw server code, a URL or an address', () {
      for (final String code in <String>[
        'daypart_undefined', 'target_date_in_past', 'unsupported_media_type', 'storage_key_in_use', 'x_y_z',
      ]) {
        final String w = classifyFailure(statusCode: 400, error: code).words;
        expect(w, isNot(contains('http')), reason: code);
        expect(w, isNot(contains('://')), reason: code);
        expect(w, isNot(contains('_')), reason: code);
      }
    });

    test('words for a stored code never break on an unknown code', () {
      expect(classifyFailureByCode('who knows').words, isNotEmpty);
      expect(classifyFailureByCode(null).words, isNotEmpty);
    });
  });

  group('what you sent, in plain sentences', () {
    test('parseSent reads the real shape and counts what it cannot read', () {
      final ({List<SentRow> rows, int skipped}) r = parseSent(<String, Object?>{
        'messages': <Object?>[
          <String, Object?>{'id': 'a1b2c3d4', 'kind': 'video_msg', 'state': 'waiting', 'sentAt': '2026-11-20T10:00:00.000Z', 'deliversAt': '2026-11-21T01:30:00.000Z', 'deliveredAt': null, 'openedAt': null, 'receipt': null},
          <String, Object?>{'id': 'b2c3d4e5', 'state': 'opened', 'openedAt': '2026-11-21T02:00:00.000Z', 'receipt': <String, Object?>{'localTime': '7:42 PM', 'zone': 'America/New_York', 'phrase': 'Watched at 7:42 PM her time — at bedtime.'}},
          'junk', 5, <String, Object?>{'id': 7, 'state': 'waiting'}, <String, Object?>{'id': 'x', 'state': 3},
        ],
      });
      expect(r.rows.length, 2);
      expect(r.skipped, 4);
      expect(r.rows[1].receipt, 'Watched at 7:42 PM her time — at bedtime.');
    });

    test('a hostile receipt phrase is cleaned and bounded', () {
      final SentRow row = SentRow.parse(<String, Object?>{
        'id': 'zzzzzz1', 'state': 'opened',
        'receipt': <String, Object?>{'phrase': 'Watched\u0000\n\u001b[31m at ${'x' * 1000}'},
      })!;
      expect(row.receipt!.length, lessThanOrEqualTo(200));
      expect(row.receipt, isNot(contains('\u0000')));
      expect(row.receipt, isNot(contains('\n')));
      expect(row.receipt, isNot(contains('\u001b')));
    });

    test('an empty or non-string phrase falls back to a plain sentence', () {
      expect(sentStatusWords(SentRow.parse(<String, Object?>{'id': 'zzzzzz1', 'state': 'opened', 'receipt': <String, Object?>{'phrase': '   '}})!),
          'She opened it.');
      expect(sentStatusWords(SentRow.parse(<String, Object?>{'id': 'zzzzzz1', 'state': 'opened', 'receipt': 'nope'})!), 'She opened it.');
    });

    test('every state has a sentence that does not claim more than the server said', () {
      SentRow row(String s) => SentRow(id: 'zzzzzz1', state: s, deliveredAt: DateTime(2026, 11, 18, 19));
      expect(sentStatusWords(row('waiting'), setFor: 'at bedtime'), 'Waiting to arrive at bedtime. It has not reached her tablet yet.');
      expect(sentStatusWords(row('delivered')), 'Delivered to her tablet on Wed 18 Nov. She has not opened it yet.');
      expect(sentStatusWords(row('expired')), contains('did not reach her'));
      expect(sentStatusWords(row('revoked')), contains('taken back'));
      expect(sentStatusWords(row('from_the_future')), contains('cannot tell'));
    });

    test('statuses are sentences, never counts, streaks or scores (P1, P2)', () {
      for (final String s in <String>['waiting', 'delivered', 'opened', 'expired', 'revoked', 'other']) {
        final String w = sentStatusWords(SentRow(id: 'zzzzzz1', state: s)).toLowerCase();
        for (final String bad in <String>['streak', 'score', 'points', 'in a row', 'rank', 'times']) {
          expect(w, isNot(contains(bad)), reason: '$s: $bad');
        }
      }
    });

    test('dates are a day only: no clock time of the sender is ever put against hers (§8.2.3)', () {
      expect(dayWords(DateTime(2026, 11, 18, 23, 59)), 'Wed 18 Nov');
      expect(sentStatusWords(SentRow(id: 'zzzzzz1', state: 'delivered', deliveredAt: DateTime(2026, 11, 18, 23, 59))),
          isNot(matches(RegExp(r'\d:\d\d'))));
    });
  });

  group('QueuedSend', () {
    QueuedSend q({int attempts = 0, int last = 0, SendPhase phase = SendPhase.waiting}) => QueuedSend(
        id: 'm1abc-xyz123', childId: 'child-a', createdAtMs: 5, delivery: const DeliveryChoice.atDayPart('bedtime'),
        mediaB64: 'AAAA', durationMs: 900, attempts: attempts, lastAttemptMs: last, phase: phase);

    test('json round-trips every field', () {
      final QueuedSend a = q(attempts: 3, last: 77).copyWith(storageKey: 'children/c/messages/u', failureCode: 'no_answer');
      final QueuedSend b = QueuedSend.fromJson(a.toJson())!;
      expect(b.toJson(), a.toJson());
    });

    test('strict decode: any wrong type makes the item unreadable, never guessed', () {
      final Map<String, Object?> good = q().toJson();
      expect(QueuedSend.fromJson(good), isNotNull);
      for (final Map<String, Object?> bad in <Map<String, Object?>>[
        <String, Object?>{...good, 'id': 5},
        <String, Object?>{...good, 'id': '../../evil'},
        <String, Object?>{...good, 'id': 'UPPER-CASE'},
        <String, Object?>{...good, 'child': ''},
        <String, Object?>{...good, 'at': '1'},
        <String, Object?>{...good, 'ms': 0},
        <String, Object?>{...good, 'ms': -4},
        <String, Object?>{...good, 'media': ''},
        <String, Object?>{...good, 'media': 12},
        <String, Object?>{...good, 'delivery': <String, Object?>{'k': 'soon', 'p': 'bedtime'}},
        <String, Object?>{...good, 'key': 5},
        <String, Object?>{...good, 'tries': -1},
        <String, Object?>{...good, 'phase': 'sent'},
        <String, Object?>{...good, 'fail': 'x' * 100},
      ]) {
        expect(QueuedSend.fromJson(bad), isNull, reason: '$bad');
      }
      expect(QueuedSend.fromJson(null), isNull);
      expect(QueuedSend.fromJson('x'), isNull);
    });

    test('automatic tries follow the doubling wait and stop at the ceiling; needs-attention is never automatic', () {
      expect(q().dueAt(0), isTrue);
      expect(q(attempts: 1, last: 1000).dueAt(1000 + 60000 * 1 - 1), isFalse, reason: 'one failure: wait a minute');
      expect(q(attempts: 1, last: 1000).dueAt(1000 + 60000 * 1), isTrue);
      expect(q(attempts: 3, last: 0).dueAt(60000 * 4 - 1), isFalse);
      expect(q(attempts: 3, last: 0).dueAt(60000 * 4), isTrue);
      expect(q(attempts: 8, last: 0).dueAt(1 << 40), isFalse);
      expect(q(attempts: 8).gaveUpAutomatically, isTrue);
      expect(q(phase: SendPhase.needsAttention).dueAt(1 << 40), isFalse);
    });

    test('what a waiting message says about itself is plain and never a code', () {
      expect(queuedStatusWords(q()).toLowerCase(), contains('saved on this phone'));
      expect(queuedStatusWords(q(attempts: 2)), contains('Waiting for a connection'));
      expect(queuedStatusWords(q(attempts: 8)), contains('Try again'));
      expect(queuedStatusWords(q(phase: SendPhase.needsAttention).copyWith(failureCode: 'daypart_undefined')),
          contains('Set her day first'));
    });

    test('ids are legal store keys', () {
      expect(isPlainSendId('m1abc-xyz123'), isTrue);
      expect(isPlainSendId('abc'), isFalse);
      expect(isPlainSendId('has space1'), isFalse);
      expect(isPlainSendId('A' * 10), isFalse);
    });
  });
}
