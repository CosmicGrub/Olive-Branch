// OLIVE BRANCH — suite B pure logic: one routine, first-then, packing buddy, a
// new place, how the app feels. Every deny path is a real assertion.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/rhythm_logic.dart';

Matcher refused(String reason) => throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', reason));

Routine three() {
  Routine r = const Routine(title: 'Bedtime');
  r = addStep(r, newStep('a', 'bath'));
  r = addStep(r, newStep('b', 'pyjamas'));
  r = addStep(r, newStep('c', 'book'));
  return r;
}

void main() {
  group('text', () {
    test('cleanText trims, collapses and bounds', () {
      expect(cleanText('  Bath   time  '), 'Bath time');
      expect(() => cleanText(''), refused('empty_text'));
      expect(() => cleanText('   '), refused('empty_text'));
      expect(cleanText('', allowEmpty: true), '');
      expect(() => cleanText('x' * 31), refused('too_long'));
      expect(cleanText('x' * 30), 'x' * 30);
      expect(() => cleanText(5), refused('bad_text'));
      expect(() => cleanText(null), refused('bad_text'));
      expect(() => cleanText('a\u0000b'), refused('bad_text'));
      expect(cleanText('a\tb\nc'), 'a b c');
    });

    test('P3: a street address or a coordinate pair is refused, plain words are not', () {
      expect(() => cleanText('12 Oak Street', max: 60), refused('looks_like_location'));
      expect(() => cleanText('Meet at 5 Main St', max: 60), refused('looks_like_location'));
      expect(() => cleanText('51.50735, -0.12776', max: 60), refused('looks_like_location'));
      expect(cleanText('We read 2 books on the way', max: 60), 'We read 2 books on the way');
      expect(cleanText('Knock on the door at the end of the hall', max: 60), isNotEmpty);
      expect(looksLikeLocation('Oak Road'), isFalse, reason: 'a name without a number is not an address');
    });

    test('a phone-number-looking run of digits is detected', () {
      expect(looksLikePhoneNumber('call 555 123 4567'), isTrue);
      expect(looksLikePhoneNumber('(555) 123-4567'), isTrue);
      expect(looksLikePhoneNumber('two books'), isFalse);
    });

    test('days: valid ISO only, and whole-day distance', () {
      expect(isIsoDay('2026-11-08'), isTrue);
      expect(isIsoDay('2026-02-30'), isFalse);
      expect(isIsoDay('26-11-08'), isFalse);
      expect(isIsoDay(null), isFalse);
      expect(daysApart('2026-11-08', '2026-11-10'), 2);
      expect(daysApart('2026-12-31', '2027-01-01'), 1);
      expect(() => daysApart('x', '2026-11-10'), refused('bad_day'));
      expect(isoDayOf(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('one routine', () {
    test('steps are ordered, bounded and unique', () {
      final Routine r = three();
      expect(r.steps.map((RoutineStep s) => s.label), <String>['Bath', 'Pyjamas', 'A book']);
      expect(() => addStep(r, newStep('a', 'song')), refused('duplicate_id'));
      Routine full = const Routine();
      for (int i = 0; i < maxRoutineSteps; i++) {
        full = addStep(full, newStep('s$i', 'bath'));
      }
      expect(() => addStep(full, newStep('extra', 'bath')), refused('too_many_steps'));
    });

    test('a step must be a routine picture with a plain label', () {
      expect(() => newStep('x', 'sunny'), refused('bad_picture'));
      expect(() => newStep('x', 'nope'), refused('bad_picture'));
      expect(() => newStep('bad id!', 'bath'), refused('bad_id'));
      expect(() => newStep('x', 'bath', label: ''), refused('empty_text'));
      expect(newStep('x', 'bath', label: 'Splash').label, 'Splash');
    });

    test('remove and move keep the rest in order; bad indexes are refused', () {
      final Routine r = three();
      expect(removeStep(r, 'b').steps.map((RoutineStep s) => s.id), <String>['a', 'c']);
      expect(() => removeStep(r, 'zz'), refused('unknown_step'));
      expect(moveStep(r, 0, 2).steps.map((RoutineStep s) => s.id), <String>['b', 'c', 'a']);
      expect(moveStep(r, 2, 0).steps.map((RoutineStep s) => s.id), <String>['c', 'a', 'b']);
      expect(() => moveStep(r, 3, 0), refused('bad_index'));
      expect(() => moveStep(r, 0, -1), refused('bad_index'));
      expect(renameRoutine(r, 'Evening').title, 'Evening');
      expect(() => renameRoutine(r, ''), refused('empty_text'));
    });

    test('she can only tick the step she is on, in order', () {
      final Routine r = three();
      const String day = '2026-11-08';
      DayTicks t = ticksFor(r, const DayTicks(), day);
      expect(firstThenOf(r, t).first!.id, 'a');
      expect(firstThenOf(r, t).then!.id, 'b');
      t = tickCurrent(r, t, day);
      expect(t.done, <String>['a']);
      expect(firstThenOf(r, t).first!.id, 'b');
      t = tickCurrent(r, t, day);
      final DayTicks all = tickCurrent(r, t, day);
      final FirstThen last = firstThenOf(r, all);
      expect(last.allDone, isTrue);
      expect(last.first, isNull);
      // ticking when done changes nothing
      expect(tickCurrent(r, all, day).done, <String>['a', 'b', 'c']);
    });

    test('the last step has no "then"', () {
      final Routine r = three();
      const DayTicks t = DayTicks(day: '2026-11-08', done: <String>['a', 'b']);
      final FirstThen ft = firstThenOf(r, t);
      expect(ft.first!.id, 'c');
      expect(ft.then, isNull);
      expect(ft.allDone, isFalse);
    });

    test('ticks are for ONE day: the next day starts fresh, nothing is carried', () {
      final Routine r = three();
      const DayTicks yesterday = DayTicks(day: '2026-11-07', done: <String>['a', 'b', 'c']);
      final DayTicks today = ticksFor(r, yesterday, '2026-11-08');
      expect(today.done, isEmpty);
      expect(today.day, '2026-11-08');
      expect(tickCurrent(r, yesterday, '2026-11-08').done, <String>['a']);
    });

    test('a step a grown-up removed is dropped from the ticks', () {
      final Routine r = removeStep(three(), 'b');
      final DayTicks t = ticksFor(r, const DayTicks(day: '2026-11-08', done: <String>['a', 'b']), '2026-11-08');
      expect(t.done, <String>['a']);
    });

    test('an empty routine shows nothing to do and is not "all done"', () {
      final FirstThen ft = firstThenOf(const Routine(), const DayTicks());
      expect(ft.first, isNull);
      expect(ft.allDone, isFalse);
    });

    test('start again clears today; a bad day is refused', () {
      expect(startAgain('2026-11-08').done, isEmpty);
      expect(() => startAgain('nope'), refused('bad_day'));
      expect(() => ticksFor(three(), const DayTicks(), 'nope'), refused('bad_day'));
    });

    test('P2: the stored shape has no counter, score, streak or total', () {
      final String j = jsonEncode(<Object?>[three().toJson(), const DayTicks(day: '2026-11-08', done: <String>['a']).toJson()]);
      for (final String bad in <String>['count', 'score', 'streak', 'total', 'points', 'stars', 'reward', 'rank']) {
        expect(j.toLowerCase().contains(bad), isFalse, reason: bad);
      }
    });

    test('a damaged routine document loads tolerantly', () {
      expect(Routine.tryFromJson('x'), isNull);
      expect(Routine.tryFromJson(<String, Object?>{'title': 5, 'steps': <Object?>[]}), isNull);
      final Routine? r = Routine.tryFromJson(<String, Object?>{
        'title': 'Bedtime',
        'steps': <Object?>[
          <String, Object?>{'id': 'a', 'picture': 'bath', 'label': 'Bath'},
          <String, Object?>{'id': 'a', 'picture': 'bath', 'label': 'dup'},
          <String, Object?>{'id': 'b', 'picture': 'sunny', 'label': 'wrong group'},
          5,
          <String, Object?>{'id': 'c', 'picture': 'book', 'label': ''},
        ],
      });
      expect(r!.steps.map((RoutineStep s) => s.id), <String>['a']);
      expect(DayTicks.fromJson('x').day, isNull);
      expect(DayTicks.fromJson(<String, Object?>{'day': 'bad', 'done': <Object?>['a']}).done, isEmpty);
      expect(DayTicks.fromJson(<String, Object?>{'day': '2026-11-08', 'done': <Object?>['a', 5, 'b c']}).done, <String>['a']);
    });
  });

  group('first, then', () {
    test('two different routine pictures, set by a grown-up', () {
      final FirstThenBoard b = makeBoard(boardCard('bath'), boardCard('book', label: 'Story'));
      expect(b.then.label, 'Story');
      expect(() => makeBoard(boardCard('bath'), boardCard('bath')), refused('same_card'));
      expect(() => boardCard('sunny'), refused('bad_picture'));
      expect(() => boardCard('bath', label: ''), refused('empty_text'));
    });

    test('done is one bit for one day', () {
      BoardState s = boardStateFor(const BoardState(), '2026-11-08');
      expect(s.firstDone, isFalse);
      s = markFirstDone(s, '2026-11-08');
      expect(boardStateFor(s, '2026-11-08').firstDone, isTrue);
      expect(boardStateFor(s, '2026-11-09').firstDone, isFalse);
      expect(() => boardStateFor(s, 'x'), refused('bad_day'));
      expect(BoardState.fromJson('x').day, isNull);
      expect(BoardState.fromJson(<String, Object?>{'day': 'x', 'firstDone': true}).firstDone, isFalse);
    });

    test('a damaged board loads as absent', () {
      expect(FirstThenBoard.tryFromJson(<String, Object?>{'first': <String, Object?>{'picture': 'bath', 'label': 'x'}}), isNull);
      expect(FirstThenBoard.tryFromJson(5), isNull);
      expect(FirstThenBoard.tryFromJson(makeBoard(boardCard('bath'), boardCard('play')).toJson()), isNotNull);
    });
  });

  group('packing buddy', () {
    PackingList sample() {
      PackingList l = const PackingList();
      l = addPackItem(l, newPackItem('o', 'owl'));
      l = addPackItem(l, newPackItem('b', 'boots'));
      l = addPackItem(l, newPackItem('n', 'night-light', same: true));
      return l;
    }

    test('to-bring and always-the-same are kept apart', () {
      final PackingList l = sample();
      expect(l.toBring.map((PackItem i) => i.id), <String>['o', 'b']);
      expect(l.alwaysSame.map((PackItem i) => i.id), <String>['n']);
    });

    test('bounds: items, same-items, duplicates, bad pictures', () {
      PackingList l = const PackingList();
      for (int i = 0; i < maxPackItems; i++) {
        l = addPackItem(l, newPackItem('i$i', 'owl'));
      }
      expect(() => addPackItem(l, newPackItem('x', 'owl')), refused('too_many_items'));
      PackingList s = const PackingList();
      for (int i = 0; i < maxSameItems; i++) {
        s = addPackItem(s, newPackItem('s$i', 'owl', same: true));
      }
      expect(() => addPackItem(s, newPackItem('y', 'owl', same: true)), refused('too_many_same'));
      expect(() => addPackItem(sample(), newPackItem('o', 'teddy')), refused('duplicate_id'));
      expect(() => newPackItem('z', 'bath'), refused('bad_picture'));
      expect(() => removePackItem(sample(), 'zz'), refused('unknown_item'));
      expect(removePackItem(sample(), 'o').items.length, 2);
    });

    test('she can pack and un-pack; an always-the-same item can never be ticked', () {
      final PackingList l = sample();
      const String day = '2026-11-08';
      PackTicks t = togglePacked(l, const PackTicks(), day, 'o');
      expect(t.packed, <String>['o']);
      t = togglePacked(l, t, day, 'b');
      expect(t.packed, <String>['o', 'b']);
      t = togglePacked(l, t, day, 'o');
      expect(t.packed, <String>['b']);
      expect(() => togglePacked(l, t, day, 'n'), refused('same_at_both'));
      expect(() => togglePacked(l, t, day, 'nope'), refused('unknown_item'));
    });

    test('ticks last the night before an exchange, then are dropped', () {
      final PackingList l = sample();
      final PackTicks t = togglePacked(l, const PackTicks(), '2026-11-08', 'o');
      expect(packTicksFor(l, t, '2026-11-09').packed, <String>['o']);
      expect(packTicksFor(l, t, '2026-11-10').packed, <String>['o']);
      expect(packTicksFor(l, t, '2026-11-11').packed, isEmpty, reason: 'kept for $packTicksKeptDays days only');
      expect(packTicksFor(l, t, '2026-11-07').packed, isEmpty, reason: 'a day before it started is not valid');
      expect(() => packTicksFor(l, t, 'x'), refused('bad_day'));
    });

    test('an item a grown-up removed leaves the ticks', () {
      final PackingList l = sample();
      final PackTicks t = togglePacked(l, const PackTicks(), '2026-11-08', 'o');
      expect(packTicksFor(removePackItem(l, 'o'), t, '2026-11-08').packed, isEmpty);
    });

    test('damaged list and ticks load tolerantly', () {
      expect(PackingList.tryFromJson('x').items, isEmpty);
      expect(PackingList.tryFromJson(<String, Object?>{
        'items': <Object?>[<String, Object?>{'id': 'a', 'picture': 'owl', 'label': 'Owl'}, 3, <String, Object?>{'id': 'a', 'picture': 'owl', 'label': 'dup'}],
      }).items.length, 1);
      expect(PackTicks.fromJson(5).startedOn, isNull);
      expect(PackTicks.fromJson(<String, Object?>{'startedOn': '2026-11-08', 'packed': <Object?>['a', 4]}).packed, <String>['a']);
    });
  });

  group('a new place', () {
    final List<int> jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
    final List<int> png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];

    test('rooms with captions and a short plan', () {
      final PlacePlan p = makePlan('Dad\'s new place', <PlaceStop>[
        newStop('s1', 'door', 'This is the door'),
        newStop('s2', 'my-room', 'This is your room', photoBytes: jpeg),
      ], <String>['We arrive', 'The owl goes on the bed']);
      expect(p.isEmpty, isFalse);
      expect(PlacePlan.tryFromJson(p.toJson())!.stops[1].photoB64, base64Encode(jpeg));
      expect(const PlacePlan().isEmpty, isTrue);
    });

    test('P3: no address, no coordinates in a name, a caption or a line', () {
      expect(() => newStop('s', 'door', '12 Oak Street'), refused('looks_like_location'));
      expect(() => makePlan('51.50735, -0.12776', const <PlaceStop>[], const <String>[]), refused('looks_like_location'));
      expect(() => makePlan('Home', const <PlaceStop>[], <String>['Go to 5 Main St']), refused('looks_like_location'));
    });

    test('bounds: stops, lines, duplicates, photo size and kind', () {
      final List<PlaceStop> nine = <PlaceStop>[for (int i = 0; i <= maxPlaceStops; i++) newStop('s$i', 'door', 'door')];
      expect(() => makePlan('x', nine, const <String>[]), refused('too_many_stops'));
      expect(() => makePlan('x', const <PlaceStop>[], <String>['a', 'b', 'c', 'd', 'e']), refused('too_many_lines'));
      expect(() => makePlan('x', <PlaceStop>[newStop('s', 'door', 'a'), newStop('s', 'bed', 'b')], const <String>[]),
          refused('duplicate_id'));
      expect(() => newStop('s', 'door', 'a', photoBytes: List<int>.filled(maxPhotoBytes + 1, 0xFF)), refused('photo_too_big'));
      expect(() => newStop('s', 'door', 'a', photoBytes: <int>[1, 2, 3, 4, 5]), refused('bad_photo'));
      expect(newStop('s', 'door', 'a', photoBytes: png).photoB64, isNotNull);
      expect(() => checkedPhoto('!!not base64!!'), refused('bad_photo'));
      expect(() => newStop('s', 'sunny', 'a'), refused('bad_picture'));
      expect(() => newStop('s', 'door', ''), refused('empty_text'));
    });

    test('a damaged plan loads: bad parts are skipped, never shown', () {
      expect(PlacePlan.tryFromJson(5), isNull);
      expect(PlacePlan.tryFromJson(<String, Object?>{'name': 5, 'stops': <Object?>[], 'plan': <Object?>[]}), isNull);
      final PlacePlan? p = PlacePlan.tryFromJson(<String, Object?>{
        'name': 'Home',
        'stops': <Object?>[
          <String, Object?>{'id': 'a', 'room': 'door', 'caption': 'Door', 'photo': 'AAAA'},
          <String, Object?>{'id': 'b', 'room': 'bed', 'caption': 'Bed'},
          7,
        ],
        'plan': <Object?>['ok', 5, '12 Oak Street'],
      });
      expect(p!.stops.map((PlaceStop s) => s.id), <String>['b'], reason: 'the stop with a bad photo is dropped');
      expect(p.plan, <String>['ok']);
    });
  });

  group('how the app feels', () {
    test('defaults are the app as it always was', () {
      final SensoryDefaults d = sensoryDefaults(const SensoryProfile());
      expect(d.volume, 1.0);
      expect(d.animate, isTrue);
      expect(d.haptics, isTrue);
      expect(d.maxBrightness, 1.0);
      expect(d.silent, isFalse);
    });

    test('sound levels map to volume; off is silent', () {
      expect(sensoryDefaults(const SensoryProfile(sound: SoundLevel.off)).silent, isTrue);
      expect(sensoryDefaults(const SensoryProfile(sound: SoundLevel.low)).volume, 0.3);
      expect(sensoryDefaults(const SensoryProfile(sound: SoundLevel.medium)).volume, 0.6);
    });

    test('motion, haptics and brightness follow the profile', () {
      final SensoryDefaults d = sensoryDefaults(const SensoryProfile(reduceMotion: true, hapticsOff: true, brightnessCeiling: 40));
      expect(d.animate, isFalse);
      expect(d.haptics, isFalse);
      expect(d.maxBrightness, 0.4);
    });

    test('a profile can only reduce motion further than the device, never switch it back on', () {
      expect(sensoryDefaults(const SensoryProfile(), osReduceMotion: true).animate, isFalse);
      expect(sensoryDefaults(const SensoryProfile(reduceMotion: true), osReduceMotion: true).animate, isFalse);
      expect(sensoryDefaults(const SensoryProfile(), osReduceMotion: false).animate, isTrue);
    });

    test('brightness is 30..100 in steps of 10; anything else is refused', () {
      for (final int bad in <int>[0, 20, 29, 35, 101, 110, -10]) {
        expect(() => validateSensory(SensoryProfile(brightnessCeiling: bad)), refused('bad_brightness'), reason: '$bad');
      }
      for (final int ok in <int>[30, 40, 100]) {
        expect(validateSensory(SensoryProfile(brightnessCeiling: ok)).brightnessCeiling, ok);
      }
    });

    test('flashing is a fact, not a setting', () {
      expect(const SensoryProfile().neverFlashes, isTrue);
      expect(const SensoryProfile().toJson().keys.any((String k) => k.toLowerCase().contains('flash')), isFalse);
    });

    test('a damaged profile falls back per field, never louder or brighter than the default', () {
      final SensoryProfile p = SensoryProfile.fromJson(<String, Object?>{'sound': 'deafening', 'brightnessCeiling': 999, 'reduceMotion': true});
      expect(p.sound, SoundLevel.full);
      expect(p.brightnessCeiling, 100);
      expect(p.reduceMotion, isTrue);
      expect(SensoryProfile.fromJson(null).sound, SoundLevel.full);
      expect(SensoryProfile.fromJson(const SensoryProfile(sound: SoundLevel.low, brightnessCeiling: 50).toJson()).brightnessCeiling, 50);
    });
  });

  group('the document', () {
    test('round-trips and a damaged one loads as the default', () {
      final RhythmDoc d = RhythmDoc(
        routine: three(), board: makeBoard(boardCard('bath'), boardCard('play')),
        packing: addPackItem(const PackingList(), newPackItem('o', 'owl')), suiteOn: false,
        sensory: const SensoryProfile(sound: SoundLevel.low),
      );
      final RhythmDoc back = RhythmDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back.routine!.steps.length, 3);
      expect(back.board!.first.picture, 'bath');
      expect(back.packing.items.single.id, 'o');
      expect(back.suiteOn, isFalse);
      expect(back.sensory.sound, SoundLevel.low);
      final RhythmDoc bad = RhythmDoc.fromJson('garbage');
      expect(bad.routine, isNull);
      expect(bad.suiteOn, isTrue, reason: 'absent means on');
    });
  });
}
