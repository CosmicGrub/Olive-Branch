// OLIVE BRANCH — the grown-up's send and day-parts rules (guardian_send_logic.dart), headless.
// MASTERFILE section 8.31.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_send_logic.dart';

DayPartSpan part(String kind, String s, String e,
        {List<int> days = const <int>[0, 1, 2, 3, 4, 5, 6], bool reachable = true}) =>
    DayPartSpan(kind: kind, startsLocal: s, endsLocal: e, daysOfWeek: days, reachable: reachable);

void main() {
  group('times and days in words', () {
    test('parseHhmm is as strict as the server\'s HHMM', () {
      expect(parseHhmm('00:00'), 0);
      expect(parseHhmm('20:30'), 1230);
      expect(parseHhmm('23:59'), 1439);
      for (final String bad in <String>['24:00', '8:30', '20:60', '20:30:00', ' 20:30', '', '20-30', '2030', 'ab:cd']) {
        expect(parseHhmm(bad), isNull, reason: bad);
      }
      expect(parseHhmm(null), isNull);
    });

    test('clock12 words a wall clock and says nothing for a bad one', () {
      expect(clock12('00:00'), '12:00 AM');
      expect(clock12('00:05'), '12:05 AM');
      expect(clock12('12:00'), '12:00 PM');
      expect(clock12('13:15'), '1:15 PM');
      expect(clock12('20:30'), '8:30 PM');
      expect(clock12('06:30'), '6:30 AM');
      expect(clock12('nonsense'), '');
    });

    test('describeDays', () {
      expect(describeDays(<int>[0, 1, 2, 3, 4, 5, 6]), 'every day');
      expect(describeDays(<int>[1, 2, 3, 4, 5]), 'weekdays');
      expect(describeDays(<int>[0, 6]), 'weekends');
      expect(describeDays(<int>[5, 1, 3]), 'Mon, Wed, Fri');
      expect(describeDays(<int>[0, 1]), 'Mon, Sun');
      expect(describeDays(<int>[]), 'no days');
      expect(describeDays(<int>[9, -1]), 'no days');
    });

    test('every kind has an adult name and a phrase; an unknown kind is never shown raw', () {
      for (final String k in kDayPartKinds) {
        expect(adultDayPartName(k), isNot(contains('_')), reason: k);
        expect(adultDayPartName(k), isNot('Another part of her day'));
        expect(adultDayPartPhrase(k), isNot(contains('_')));
      }
      expect(adultDayPartName('rm_rf'), 'Another part of her day');
      expect(adultDayPartPhrase('x_y'), 'that part of her day');
    });
  });

  group('reading the server\'s day-parts', () {
    test('a good entry parses; days default to every day only when left out', () {
      final DayPartSpan p = DayPartSpan.fromJson(<String, dynamic>{
        'kind': 'bedtime', 'startsLocal': '20:30', 'endsLocal': '21:00', 'reachable': true})!;
      expect(p.daysOfWeek, <int>[0, 1, 2, 3, 4, 5, 6]);
      final DayPartSpan q = DayPartSpan.fromJson(<String, dynamic>{
        'kind': 'school', 'startsLocal': '08:00', 'endsLocal': '15:00', 'reachable': false,
        'daysOfWeek': <int>[5, 1, 3]})!;
      expect(q.daysOfWeek, <int>[1, 3, 5]);
    });

    test('hostile entries are dropped, never half-drawn', () {
      final List<Object?> hostile = <Object?>[
        null, 5, 'x', <int>[1], <String, dynamic>{},
        <String, dynamic>{'kind': '', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true},
        <String, dynamic>{'kind': 'x' * 41, 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true},
        <String, dynamic>{'kind': 'free', 'startsLocal': '8:00', 'endsLocal': '09:00', 'reachable': true},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '25:00', 'reachable': true},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': 'yes'},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00'},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true, 'daysOfWeek': <int>[]},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true, 'daysOfWeek': <int>[7]},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true, 'daysOfWeek': 'all'},
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true, 'daysOfWeek': <Object>['1']},
        <String, dynamic>{'kind': 7, 'startsLocal': '08:00', 'endsLocal': '09:00', 'reachable': true},
      ];
      for (final Object? h in hostile) {
        expect(DayPartSpan.fromJson(h), isNull, reason: '$h');
      }
    });

    test('parseDayParts refuses a reply it cannot read in full rather than showing a partial schedule', () {
      expect(() => parseDayParts(<String, dynamic>{}), throwsFormatException);
      expect(() => parseDayParts(<String, dynamic>{'dayParts': 'x'}), throwsFormatException);
      expect(() => parseDayParts(<String, dynamic>{'dayParts': <Object>[<String, dynamic>{'kind': 'free'}]}),
          throwsFormatException);
      expect(parseDayParts(<String, dynamic>{'dayParts': <Object>[]}), isEmpty);
    });

    test('the seeded placeholder is recognised, and only while it is untouched', () {
      expect(isPlaceholderSchedule(kPlaceholderDayParts), isTrue);
      expect(isPlaceholderSchedule(<DayPartSpan>[...kPlaceholderDayParts].reversed.toList()), isTrue,
          reason: 'order does not matter');
      final List<DayPartSpan> edited = <DayPartSpan>[
        for (final DayPartSpan p in kPlaceholderDayParts) p.kind == 'bedtime' ? p.copyWith(startsLocal: '19:45') : p,
      ];
      expect(isPlaceholderSchedule(edited), isFalse);
      expect(isPlaceholderSchedule(<DayPartSpan>[...kPlaceholderDayParts]..removeLast()), isFalse);
    });

    test('describeSpan: a part that runs past midnight says so', () {
      expect(describeSpan(part('asleep', '20:30', '06:30', reachable: false)),
          'Asleep, 8:30 PM to 6:30 AM the next morning, every day');
      expect(describeSpan(part('school', '08:00', '15:00', days: <int>[1, 2, 3, 4, 5])),
          'School, 8:00 AM to 3:00 PM, weekdays');
    });
  });

  group('checking a schedule before it is sent', () {
    test('the seeded schedule is fine and needs no note', () {
      final ScheduleCheck c = checkDayParts(kPlaceholderDayParts);
      expect(c.canSave, isTrue);
      expect(c.notes, isEmpty);
    });

    test('an empty schedule is refused, with a way forward', () {
      final ScheduleCheck c = checkDayParts(<DayPartSpan>[]);
      expect(c.canSave, isFalse);
      expect(c.problems.single.text, contains('at least one part'));
    });

    test('more than the server\'s limit is refused', () {
      final List<DayPartSpan> many = <DayPartSpan>[
        for (int i = 0; i < kMaxDayParts + 1; i++) part('free', formatHhmm(i), formatHhmm(i + 1), days: <int>[i % 7]),
      ];
      expect(checkDayParts(many).canSave, isFalse);
      expect(checkDayParts(many).problems.first.text, contains('up to $kMaxDayParts'));
    });

    test('a part that starts and ends together, a bad time, a bad day and an unknown kind are each named', () {
      expect(checkDayParts(<DayPartSpan>[part('bedtime', '20:00', '20:00')]).problems.single.text,
          contains('same time'));
      expect(checkDayParts(<DayPartSpan>[part('bedtime', '8pm', '21:00')]).problems.single.text,
          contains('start time and an end time'));
      expect(checkDayParts(<DayPartSpan>[part('bedtime', '20:00', '21:00', days: <int>[])]).problems.single.text,
          contains('at least one day'));
      expect(checkDayParts(<DayPartSpan>[part('bedtime', '20:00', '21:00', days: <int>[1, 1])]).canSave, isFalse);
      expect(checkDayParts(<DayPartSpan>[part('bedtime', '20:00', '21:00', days: <int>[7])]).canSave, isFalse);
      expect(checkDayParts(<DayPartSpan>[part('nap', '13:00', '14:00')]).canSave, isFalse);
    });

    test('same-kind overlap follows the server\'s constraint exactly', () {
      // overlapping, same days: refused
      expect(sameKindOverlap(part('free', '08:00', '12:00'), part('free', '11:00', '15:00')), isTrue);
      // touching ranges are half-open: fine
      expect(sameKindOverlap(part('free', '08:00', '12:00'), part('free', '12:00', '15:00')), isFalse);
      // different weekdays: fine
      expect(sameKindOverlap(part('free', '08:00', '12:00', days: <int>[1]), part('free', '09:00', '10:00', days: <int>[2])),
          isFalse);
      // different kinds never clash here
      expect(sameKindOverlap(part('free', '08:00', '12:00'), part('school', '09:00', '10:00')), isFalse);
      // a wrapping part runs to the same clock time the next day on one dummy day:
      // 20:30 -> 06:30(+1) overlaps 22:00 -> 23:00, but not 01:00 -> 02:00 (the server models it exactly so)
      expect(sameKindOverlap(part('asleep', '20:30', '06:30'), part('asleep', '22:00', '23:00')), isTrue);
      expect(sameKindOverlap(part('asleep', '20:30', '06:30'), part('asleep', '01:00', '02:00')), isFalse);
      // two wrapping parts always overlap each other
      expect(sameKindOverlap(part('asleep', '20:30', '06:30'), part('asleep', '23:00', '05:00')), isTrue);
      // a degenerate part overlaps nothing (it is refused on its own)
      expect(sameKindOverlap(part('free', '08:00', '08:00'), part('free', '07:00', '09:00')), isFalse);
    });

    test('an overlap stops a save and points at the second part', () {
      final ScheduleCheck c = checkDayParts(<DayPartSpan>[
        part('bedtime', '19:30', '20:30'), part('bedtime', '20:00', '21:00')]);
      expect(c.canSave, isFalse);
      expect(c.problems.single.index, 1);
      expect(c.problems.single.text, contains('Bedtime is set twice'));
    });

    test('no bedtime is a note, not a block: "right away" still works without one', () {
      final ScheduleCheck c = checkDayParts(<DayPartSpan>[part('free', '08:00', '19:30')]);
      expect(c.canSave, isTrue);
      expect(c.notes.single.text, contains('no bedtime'));
    });

    test('different kinds that overlap are a note: the quieter one counts', () {
      final ScheduleCheck c = checkDayParts(<DayPartSpan>[
        part('bedtime', '19:30', '20:30'),
        part('dinner', '19:00', '20:00'),
      ]);
      expect(c.canSave, isTrue);
      expect(c.notes.where((DayPartProblem n) => n.text.contains('overlap')), hasLength(1));
      expect(c.notes.first.text, contains('quieter'));
    });

    test('a wrapping part spills onto the next weekday when looking for overlaps', () {
      // asleep starting Friday runs into Saturday morning; a Saturday 02:00-04:00 sleep-in (other kind) overlaps it
      final ScheduleCheck c = checkDayParts(<DayPartSpan>[
        part('bedtime', '19:30', '20:30'),
        part('asleep', '20:30', '06:30', days: <int>[5], reachable: false),
        part('activity', '02:00', '04:00', days: <int>[6]),
      ]);
      expect(c.notes.where((DayPartProblem n) => n.text.contains('overlap')), isNotEmpty);
    });
  });

  group('saving her day: what is said when it does not work', () {
    String say(int status, String reason) => dayPartSaveFailure(ApiException(status, reason));
    test('each of the server\'s reasons has its own sentence and promises nothing changed', () {
      for (final String r in <String>[
        'day_parts_overlap', 'day_parts_required', 'bad_day_part_kind', 'bad_day_part_time', 'empty_day_part',
        'bad_days_of_week', 'reachable_required', 'bad_day_part',
      ]) {
        final String t = say(r == 'day_parts_overlap' ? 409 : 400, r);
        expect(t, isNot(contains('_')), reason: r);
        expect(t, anyOf(contains('Nothing was changed'), contains('save again')), reason: r);
      }
    });
    test('401, 403, 404, 5xx and no network', () {
      expect(say(401, 'expired'), contains('sign in'));
      expect(say(403, 'forbidden'), contains('not allowed'));
      expect(say(404, 'nope'), contains('cannot find her'));
      expect(say(503, 'down'), contains('Try again'));
      expect(dayPartSaveFailure(StateError('socket')), contains('could not reach the server'));
    });
  });

  group('the delivery choice', () {
    test('toWire is exactly the three things the server takes', () {
      expect(const DeliveryChoice.now().toWire(), <String, Object?>{'delivery': 'now', 'daypart': 'bedtime'});
      expect(const DeliveryChoice.atDayPart('dinner').toWire(), <String, Object?>{'delivery': 'daypart', 'daypart': 'dinner'});
      expect(const DeliveryChoice.onNight('2026-12-24').toWire(),
          <String, Object?>{'delivery': 'date', 'daypart': 'bedtime', 'targetLocalDate': '2026-12-24'});
    });

    test('fromWire round-trips and refuses anything else', () {
      for (final DeliveryChoice c in <DeliveryChoice>[
        const DeliveryChoice.now(), const DeliveryChoice.atDayPart('wake'), const DeliveryChoice.onNight('2027-01-02')]) {
        expect(DeliveryChoice.fromWire(c.toWire())!.toWire(), c.toWire());
      }
      expect(DeliveryChoice.fromWire(<String, Object?>{'delivery': 'soon'}), isNull);
      expect(DeliveryChoice.fromWire(<String, Object?>{}), isNull);
      expect(DeliveryChoice.fromWire(<String, Object?>{'delivery': 'daypart', 'daypart': 5}), isNull);
      expect(DeliveryChoice.fromWire(<String, Object?>{'delivery': 'date', 'targetLocalDate': '2026-02-30'}), isNull);
      expect(DeliveryChoice.fromWire(<String, Object?>{'delivery': 'date', 'targetLocalDate': 'tomorrow'}), isNull);
    });

    test('describe', () {
      expect(const DeliveryChoice.now().describe(), 'Right away');
      expect(const DeliveryChoice.atDayPart('bedtime').describe(), 'At her bedtime');
      expect(const DeliveryChoice.onNight('2026-11-21').describe(), 'On Sat, Nov 21 at her bedtime');
    });

    test('dates: a real calendar day, and the night must not be long gone or far off', () {
      expect(parseLocalDate('2026-02-30'), isNull, reason: 'DateTime.parse would quietly call it March 2');
      expect(parseLocalDate('2026-13-01'), isNull);
      expect(parseLocalDate('2026-1-1'), isNull);
      expect(parseLocalDate('2028-02-29'), isNotNull);
      expect(parseLocalDate('2027-02-29'), isNull);
      final DateTime today = DateTime(2026, 11, 15);
      expect(checkNight('2026-11-15', today), isNull);
      expect(checkNight('2026-11-14', today), isNull, reason: 'her calendar can be a day behind the phone\'s');
      expect(checkNight('2026-11-13', today), contains('already passed'));
      expect(checkNight('2027-11-15', today), isNull);
      expect(checkNight('2027-11-17', today), contains('more than a year'));
      expect(checkNight(null, today), contains('Pick a night'));
      expect(checkNight('soon', today), contains('Pick a night'));
    });
  });

  group('the send-time guard', () {
    final List<DayPartSpan> seeded = kPlaceholderDayParts;
    SendGuard g(DeliveryChoice c, {List<DayPartSpan>? parts, String? now, bool? reachable}) =>
        sendGuard(choice: c, childName: 'Mia', parts: parts, nowDayPart: now, reachable: reachable);

    test('right away while she is asleep warns, in words, and leaves the choice to the sender', () {
      final SendGuard r = g(const DeliveryChoice.now(), parts: seeded, now: 'asleep', reachable: false);
      expect(r.warns, isTrue);
      expect(r.blocks, isFalse);
      expect(r.headline, 'Mia is asleep right now.');
      expect(r.detail, contains("won't buzz her"));
      expect(r.detail, contains('choose another time'));
    });

    test('school and an unnamed quiet part are worded', () {
      expect(g(const DeliveryChoice.now(), now: 'school', reachable: false).headline, 'Mia is at school right now.');
      expect(g(const DeliveryChoice.now(), now: 'activity', reachable: false).headline,
          "Mia's tablet is set to stay quiet right now.");
    });

    test('right away when she can be reached, or when it is not known, says nothing', () {
      expect(g(const DeliveryChoice.now(), reachable: true).level, GuardLevel.clear);
      expect(g(const DeliveryChoice.now(), reachable: null).level, GuardLevel.clear,
          reason: 'an unknown is not a block and not a warning');
    });

    test('at bedtime with no bedtime in her day is blocked, and says where to fix it', () {
      final SendGuard r = g(const DeliveryChoice.atDayPart('bedtime'),
          parts: <DayPartSpan>[part('free', '08:00', '19:30')]);
      expect(r.blocks, isTrue);
      expect(r.headline, "Mia's day has no bedtime yet.");
      expect(r.detail, contains("Mia's day"));
    });

    test('a night needs a bedtime too', () {
      expect(g(const DeliveryChoice.onNight('2026-12-24'), parts: <DayPartSpan>[part('free', '08:00', '19:30')]).blocks, isTrue);
      expect(g(const DeliveryChoice.onNight('2026-12-24'), parts: seeded).level, GuardLevel.clear);
    });

    test('a part she does not have is blocked; one she has is fine', () {
      expect(g(const DeliveryChoice.atDayPart('dinner'), parts: seeded).blocks, isTrue);
      expect(g(const DeliveryChoice.atDayPart('wake'), parts: seeded).level, GuardLevel.clear);
    });

    test('landing in a quiet part warns that it will not buzz', () {
      final SendGuard r = g(const DeliveryChoice.atDayPart('asleep'), parts: seeded);
      expect(r.warns, isTrue);
      expect(r.detail, contains('will not buzz'));
    });

    test('when her schedule could not be read nothing is invented', () {
      expect(g(const DeliveryChoice.atDayPart('bedtime'), parts: null).level, GuardLevel.clear);
    });
  });

  group('what a grown-up reads about something they sent', () {
    Map<String, dynamic> row(String state, {Map<String, dynamic>? extra}) => <String, dynamic>{
          'id': '0a0a0a0a-0000-4000-8000-000000000001',
          'kind': 'video_msg',
          'state': state,
          'sentAt': '2026-11-15T20:00:00.000Z',
          'delivery': 'daypart',
          'daypart': 'bedtime',
          'targetLocalDate': null,
          'deliversAt': null,
          'deliversHer': null,
          'deliveredAt': null,
          'deliveredHer': null,
          'openedAt': null,
          'receipt': null,
          ...?extra,
        };

    test('waiting for a day-part: her time, in her words', () {
      final SentEntry e = SentEntry.fromJson(row('waiting', extra: <String, dynamic>{
        'deliversHer': <String, dynamic>{'day': 'tomorrow', 'time': '8:30 PM'}}))!;
      expect(e.stateLabel, 'Waiting');
      expect(e.statusLine('Mia'), "Waiting for Mia's bedtime. It will arrive tomorrow at 8:30 PM, her time.");
    });

    test('waiting for a night names the date; a far date reads "on Sat, Nov 21 at ..."', () {
      final SentEntry e = SentEntry.fromJson(row('waiting', extra: <String, dynamic>{
        'delivery': 'date', 'daypart': null, 'targetLocalDate': '2026-11-21',
        'deliversHer': <String, dynamic>{'day': 'Sat, Nov 21', 'time': '8:30 PM'}}))!;
      expect(e.statusLine('Mia'), 'Waiting for Sat, Nov 21. It will arrive on Sat, Nov 21 at 8:30 PM, her time.');
    });

    test('waiting with no time because her day has no bedtime says why, not just "waiting"', () {
      final SentEntry e = SentEntry.fromJson(row('waiting'))!;
      expect(e.statusLine('Mia'), allOf(contains('no time for it yet'), contains('no bedtime')));
    });

    test('right away and still waiting is "on its way", not a time', () {
      final SentEntry e = SentEntry.fromJson(row('waiting', extra: <String, dynamic>{'delivery': 'now', 'daypart': null}))!;
      expect(e.statusLine('Mia'), "On its way. It should reach Mia's inbox shortly.");
    });

    test('delivered, then opened with the server\'s own receipt sentence', () {
      final SentEntry d = SentEntry.fromJson(row('delivered', extra: <String, dynamic>{
        'deliveredHer': <String, dynamic>{'day': 'today', 'time': '8:30 PM'}}))!;
      expect(d.stateLabel, 'Delivered');
      expect(d.statusLine('Mia'), "Delivered to Mia's inbox today at 8:30 PM, her time. She has not opened it yet.");
      final SentEntry o = SentEntry.fromJson(row('opened', extra: <String, dynamic>{
        'receipt': <String, dynamic>{'localTime': '8:42 PM', 'zone': 'America/Chicago',
          'phrase': 'Watched at 8:42 PM her time — at bedtime.'}}))!;
      expect(o.stateLabel, 'Opened');
      expect(o.statusLine('Mia'), 'Watched at 8:42 PM her time — at bedtime.');
      expect(SentEntry.fromJson(row('opened'))!.statusLine('Mia'), 'Opened by Mia.');
    });

    test('expired and revoked are told plainly, never as delivered', () {
      expect(SentEntry.fromJson(row('expired'))!.statusLine('Mia'), contains('never received it'));
      expect(SentEntry.fromJson(row('expired'))!.stateLabel, 'Not delivered');
      expect(SentEntry.fromJson(row('revoked'))!.statusLine('Mia'), contains('taken back'));
    });

    test('hostile rows are dropped and hostile text is cleaned', () {
      expect(SentEntry.fromJson(null), isNull);
      expect(SentEntry.fromJson(row('flying')), isNull);
      expect(SentEntry.fromJson(row('waiting', extra: <String, dynamic>{'id': '../../etc'})), isNull);
      expect(SentEntry.fromJson(row('waiting', extra: <String, dynamic>{'id': 7})), isNull);
      final SentEntry e = SentEntry.fromJson(row('opened', extra: <String, dynamic>{
        'receipt': <String, dynamic>{'phrase': '<b>Watched</b>‮ at 8:42 PM her time.\n'}}))!;
      expect(e.receiptPhrase, isNot(contains('<')));
      expect(e.receiptPhrase, isNot(contains('‮')));
      expect(e.receiptPhrase, isNot(contains('\n')));
      // an oversized phrase is not drawn at all
      expect(SentEntry.fromJson(row('opened', extra: <String, dynamic>{
        'receipt': <String, dynamic>{'phrase': 'x' * 400}}))!.statusLine('Mia'), 'Opened by Mia.');
      // a moment that is not two plain strings is dropped, the row still stands
      expect(SentEntry.fromJson(row('waiting', extra: <String, dynamic>{'deliversHer': <String, dynamic>{'day': 3}}))!.deliversHer,
          isNull);
      // unknown extra fields are ignored (a score cannot ride in)
      final SentEntry x = SentEntry.fromJson(row('waiting', extra: <String, dynamic>{'score': 9, 'streak': 3}))!;
      expect(x.statusLine('Mia'), isNot(contains('9')));
    });

    test('parseSent keeps order, drops what it cannot draw and refuses a non-list', () {
      final List<SentEntry> l = parseSent(<String, dynamic>{'messages': <Object>[
        row('waiting', extra: <String, dynamic>{'id': 'aaaaaaaa-0000-4000-8000-000000000001'}),
        'junk',
        row('opened', extra: <String, dynamic>{'id': 'aaaaaaaa-0000-4000-8000-000000000002'}),
      ]});
      expect(l.map((SentEntry e) => e.state), <SentState>[SentState.waiting, SentState.opened]);
      expect(() => parseSent(<String, dynamic>{'messages': 'x'}), throwsFormatException);
    });
  });

  group('when a send fails', () {
    SendFailure f(Object e) => explainSendFailure(e, 'Mia');

    test('no network, a timeout and a page that is not JSON are all "no answer": keep it', () {
      expect(f(const FormatException('<html>')).kind, FailureKind.keep);
      expect(f(StateError('socket')).kind, FailureKind.keep);
      expect(f(StateError('x')).code, 'offline');
    });

    test('busy, restarting and rate-limited keep it; sign-in-again keeps it and says so', () {
      for (final int s in <int>[408, 429, 500, 502, 503, 504]) {
        expect(f(ApiException(s, 'whatever')).kind, FailureKind.keep, reason: '$s');
      }
      final SendFailure u = f(UnauthorizedException('expired'));
      expect(u.kind, FailureKind.keep);
      expect(u.code, 'sign_in');
      expect(u.text, contains('sign in'));
    });

    test('a server "no" is a refusal, in words, without a code in it', () {
      final Map<String, int> refusals = <String, int>{
        'unsupported_media_type': 415, 'bad_bytes': 400, 'image_too_large': 413, 'media_quota_exceeded': 413,
        'daypart_undefined': 400, 'target_date_in_past': 400, 'already_expired': 400, 'delivery_unresolvable': 400,
        'not_authorized': 403, 'child_not_found': 404, 'bad_delivery': 400, 'now_has_no_date': 400,
        'date_required': 400, 'daypart_has_no_date': 400, 'child_cannot_send_now': 403,
      };
      for (final MapEntry<String, int> e in refusals.entries) {
        final SendFailure r = f(ApiException(e.value, e.key));
        expect(r.kind, FailureKind.refuse, reason: e.key);
        expect(r.text, isNot(contains('_')), reason: e.key);
        expect(r.text, isNot(matches(RegExp(r'\b[45]\d\d\b'))), reason: '${e.key} must not show a status code');
      }
    });

    test('a missing bedtime refusal tells the sender where to fix it', () {
      expect(f(ApiException(400, 'daypart_undefined')).text, allOf(contains('no bedtime'), contains("Mia's day")));
    });

    test('an answer nobody has worded is still a refusal in plain words, never a raw code', () {
      final SendFailure r = f(ApiException(418, 'teapot'));
      expect(r.kind, FailureKind.refuse);
      expect(r.text, isNot(contains('teapot')));
      expect(f(ForbiddenException('weird')).text, contains("isn't allowed"));
    });
  });

  group('what the bytes are', () {
    test('first bytes decide, as on the server', () {
      expect(sniffSendKind(<int>[0xff, 0xd8, 0xff, 1]), MediaKind.photo);
      expect(sniffSendKind(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), MediaKind.photo);
      expect(sniffSendKind(<int>[0x1a, 0x45, 0xdf, 0xa3, 0]), MediaKind.video);
      expect(sniffSendKind(<int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d]), MediaKind.video);
      expect(sniffSendKind(<int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20]), MediaKind.voice);
      expect(sniffSendKind(<int>[]), isNull);
      expect(sniffSendKind(<int>[0xff, 0xd8]), isNull);
      expect(sniffSendKind('GIF89a plus some more'.codeUnits), isNull);
      expect(sniffSendKind('<html><body>login'.codeUnits), isNull);
    });
  });
}
