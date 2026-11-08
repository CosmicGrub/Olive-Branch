// OLIVE BRANCH — suites G (Growing) and F (Care): the pure rules. Every deny
// path is a real assertion: a capsule that opens too early, a height that is a
// number no child has, a story with seven pages, a photo that is too big, a
// suite the age band does not allow.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_logic.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 7));

TimeCapsule _cap({String id = 'c1', String title = 'For thirteen', String note = 'You were brave.',
    String sealed = '2026-11-08', String opens = '2039-06-01', String? unsealed, Uint8List? thumb}) =>
    TimeCapsule(id: id, title: title, note: note, sealedOn: sealed, opensOn: opens, unsealedOn: unsealed, thumb: thumb);

void main() {
  group('dates and labels', () {
    test('monthYear and dayMonthYear read an ISO date and never guess at a bad one', () {
      expect(monthYear('2026-11-08'), 'Nov 2026');
      expect(dayMonthYear('2026-01-05'), '5 Jan 2026');
      expect(monthYear('not-a-date'), 'not-a-date');
      expect(dayMonthYear('2026-13-40'), '2026-13-40');
    });

    test('isoOf pads', () => expect(isoOf(DateTime(2027, 3, 4)), '2027-03-04'));
  });

  group('time capsule: it opens by the clock, and sealed means sealed', () {
    test('sealed before its day, open on the day and after', () {
      final TimeCapsule c = _cap(opens: '2027-01-01');
      expect(c.isOpen('2026-12-31'), isFalse);
      expect(c.isOpen('2027-01-01'), isTrue);
      expect(c.isOpen('2030-05-05'), isTrue);
    });

    test('changing the clock opens it early: the rule is the clock, and the note says so', () {
      final TimeCapsule c = _cap(opens: '2039-06-01');
      expect(c.isOpen('2026-11-08'), isFalse);
      expect(c.isOpen('2040-01-01'), isTrue, reason: 'a clock set forward opens it; that is disclosed, not hidden');
      expect(capsuleClockNote, contains("device's clock"));
      expect(capsuleClockNote, contains('early'));
    });

    test('a guardian can unseal it early, and only that makes it open before its day', () {
      final TimeCapsule c = _cap(opens: '2039-06-01');
      final TimeCapsule u = c.unsealed('2026-11-09');
      expect(u.isOpen('2026-11-09'), isTrue);
      expect(u.unsealedOn, '2026-11-09');
      expect(c.isOpen('2026-11-09'), isFalse, reason: 'unsealing returns a new value, never mutates');
    });

    test('while sealed a guardian sees the title and dates but not the words or the photo', () {
      final GuardianCapsuleView v = _cap(thumb: _bytes(10)).forGuardian('2026-11-08');
      expect(v.open, isFalse);
      expect(v.title, 'For thirteen');
      expect(v.note, isNull);
      expect(v.thumb, isNull);
    });

    test('once open the guardian view carries the words and the photo', () {
      final GuardianCapsuleView v = _cap(opens: '2026-11-09', thumb: _bytes(10)).forGuardian('2026-11-09');
      expect(v.open, isTrue);
      expect(v.note, 'You were brave.');
      expect(v.thumb, isNotNull);
    });

    test('a valid capsule passes check()', () => expect(_cap().check(), isNull));

    test('refused: no title, no words and no photo, a title too long, words too long', () {
      expect(_cap(title: '  ').check(), 'empty');
      expect(_cap(note: ' ').check(), 'empty');
      expect(_cap(note: ' ', thumb: _bytes(5)).check(), isNull, reason: 'a photo alone is enough');
      expect(_cap(title: 'x' * (maxTitleChars + 1)).check(), 'too_long');
      expect(_cap(note: 'x' * (maxCapsuleNoteChars + 1)).check(), 'too_long');
    });

    test('refused: an opening date that is not a date, today, the past, or more than 18 years away', () {
      expect(_cap(opens: 'someday').check(), 'bad_date');
      expect(_cap(sealed: '2026-11-08', opens: '2026-11-08').check(), 'date_not_future');
      expect(_cap(sealed: '2026-11-08', opens: '2020-01-01').check(), 'date_not_future');
      expect(_cap(sealed: '2026-11-08', opens: '2026-11-09').check(), isNull);
      expect(_cap(sealed: '2026-11-08', opens: '2060-01-01').check(), 'date_too_far');
    });

    test('refused: a photo over the thumbnail cap', () {
      expect(_cap(thumb: _bytes(maxThumbBytes)).check(), isNull);
      expect(_cap(thumb: _bytes(maxThumbBytes + 1)).check(), 'photo_too_big');
    });

    test('round-trips through JSON, photo included', () {
      final TimeCapsule c = _cap(thumb: _bytes(20), unsealed: '2026-11-09');
      final TimeCapsule? back = TimeCapsule.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(back!.title, c.title);
      expect(back.unsealedOn, '2026-11-09');
      expect(back.thumb, c.thumb);
    });

    test('a damaged document decodes to null, never throws', () {
      expect(TimeCapsule.fromJson(<String, Object?>{'id': 'c', 'title': 3}), isNull);
      expect(TimeCapsule.fromJson(<String, Object?>{}), isNull);
    });
  });

  group('first times: a record of what happened, never a count', () {
    test('newest first', () {
      final List<FirstTime> l = firstsNewestFirst(<FirstTime>[
        const FirstTime(id: 'a', title: 'tooth', on: '2026-09-12'),
        const FirstTime(id: 'b', title: 'bike', on: '2026-08-03'),
        const FirstTime(id: 'c', title: 'swim', on: '2026-10-01'),
      ]);
      expect(l.map((FirstTime f) => f.id), <String>['c', 'a', 'b']);
    });

    test('hidden from her by default; a guardian chooses per item', () {
      expect(const FirstTime(id: 'a', title: 't', on: '2026-01-01').showHer, isFalse);
    });

    test('refused: no title, a bad date, a note too long, a photo too big', () {
      expect(const FirstTime(id: 'a', title: '', on: '2026-01-01').check(), 'empty');
      expect(const FirstTime(id: 'a', title: 't', on: '2026-1-1').check(), 'bad_date');
      expect(FirstTime(id: 'a', title: 't', on: '2026-01-01', note: 'x' * (maxFirstNoteChars + 1)).check(), 'too_long');
      expect(FirstTime(id: 'a', title: 't', on: '2026-01-01', thumb: _bytes(maxThumbBytes + 1)).check(), 'photo_too_big');
    });

    test('round-trips and keeps showHer', () {
      const FirstTime f = FirstTime(id: 'a', title: 'tooth', on: '2026-09-12', note: 'wobbly', showHer: true);
      final FirstTime? back = FirstTime.fromJson(f.toJson());
      expect(back!.showHer, isTrue);
      expect(back.note, 'wobbly');
    });

    test('the model carries no counter, streak or score field', () {
      final String keys = jsonEncode(const FirstTime(id: 'a', title: 't', on: '2026-01-01').toJson()).toLowerCase();
      for (final String bad in <String>['count', 'streak', 'score', 'total', 'rank']) {
        expect(keys, isNot(contains(bad)));
      }
    });
  });

  group('pencil marks: her own growth, no percentile, no comparison', () {
    test('a height must be a plausible number of centimetres', () {
      expect(const PencilMark(id: 'm', on: '2026-11-01', cm: 110).check(), isNull);
      expect(const PencilMark(id: 'm', on: '2026-11-01', cm: 29).check(), 'bad_height');
      expect(const PencilMark(id: 'm', on: '2026-11-01', cm: 221).check(), 'bad_height');
      expect(const PencilMark(id: 'm', on: 'yesterday', cm: 110).check(), 'bad_date');
    });

    test('the picture is ordered by date and uses her own marks only', () {
      final List<GrowthMarkView> v = growthPicture(const <PencilMark>[
        PencilMark(id: 'b', on: '2026-06-01', cm: 108),
        PencilMark(id: 'a', on: '2025-06-01', cm: 100),
        PencilMark(id: 'c', on: '2026-11-01', cm: 112),
      ]);
      expect(v.map((GrowthMarkView m) => m.id), <String>['a', 'b', 'c']);
      expect(v.first.fraction, 0.25);
      expect(v.last.fraction, 1.0);
      expect(v[1].fraction, inExclusiveRange(0.25, 1.0));
    });

    test('labels are month and year: no centimetres, no number she could compare', () {
      final List<GrowthMarkView> v = growthPicture(const <PencilMark>[PencilMark(id: 'a', on: '2026-06-01', cm: 100)]);
      expect(v.single.label, 'Jun 2026');
      expect(v.single.label, isNot(contains('cm')));
      expect(v.single.fraction, 1.0);
    });

    test('an empty doorframe is empty, and only the latest marks are drawn', () {
      expect(growthPicture(const <PencilMark>[]), isEmpty);
      final List<PencilMark> many = <PencilMark>[
        for (int i = 0; i < 20; i++) PencilMark(id: 'm$i', on: '2020-01-${(i + 1).toString().padLeft(2, '0')}', cm: 90 + i),
      ];
      expect(growthPicture(many, maxShown: 12), hasLength(12));
      expect(growthPicture(many, maxShown: 12).last.id, 'm19');
    });

    test('the view type has no number field (no percentile, no average)', () {
      const GrowthMarkView v = GrowthMarkView(id: 'a', label: 'Jun 2026', fraction: 0.5);
      expect(<Object>[v.id, v.label, v.fraction].whereType<int>(), isEmpty);
    });
  });

  group('memory box', () {
    test('a photo needs bytes; a picture needs its strokes; nothing else is a kind', () {
      expect(const MemoryItem(id: 'a', kind: 'photo', addedOn: '2026-11-08').check(), 'empty');
      expect(MemoryItem(id: 'a', kind: 'photo', addedOn: '2026-11-08', thumb: _bytes(9)).check(), isNull);
      expect(const MemoryItem(id: 'a', kind: 'doodle', addedOn: '2026-11-08').check(), 'empty');
      expect(const MemoryItem(id: 'a', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 1}).check(), isNull);
      expect(const MemoryItem(id: 'a', kind: 'audio', addedOn: '2026-11-08').check(), 'invalid',
          reason: 'no audio capture exists in this app, so no audio kind');
    });

    test('a picture over its size cap and a caption over its length are refused', () {
      final MemoryItem big = MemoryItem(id: 'a', kind: 'colouring', addedOn: '2026-11-08',
          pictureData: <String, Object?>{'fills': 'x' * (maxMemoryPictureBytes + 10)});
      expect(big.check(), 'too_big');
      expect(MemoryItem(id: 'a', kind: 'photo', addedOn: '2026-11-08', thumb: _bytes(9), caption: 'x' * 81).check(), 'too_long');
    });

    test('round-trips', () {
      const MemoryItem m = MemoryItem(id: 'a', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 3});
      expect(MemoryItem.fromJson(m.toJson())!.pictureData, <String, Object?>{'w': 3});
    });
  });

  group('care binder: guardian words only', () {
    test('the labels the app supplies are neutral and carry no medical content', () {
      expect(careSectionLabels.keys, careSectionKinds);
      expect(careSectionLabels['allergies'], 'Allergies (written by a guardian)');
      final String all = careSectionLabels.values.join(' ').toLowerCase();
      for (final String clinical in <String>['dose', 'mg', 'treat', 'diagnos', 'medicine', 'condition', 'symptom']) {
        expect(all, isNot(contains(clinical)));
      }
    });

    test('a section needs a known kind, a title, and bounded text', () {
      expect(const CareSection(id: 's', kind: 'routines', title: 'Routines', body: '', updatedOn: '2026-11-08').check(), isNull,
          reason: 'an empty body is allowed: the app never fills it');
      expect(const CareSection(id: 's', kind: 'diagnosis', title: 'x', body: '', updatedOn: '2026-11-08').check(), 'invalid');
      expect(const CareSection(id: 's', kind: 'school', title: ' ', body: '', updatedOn: '2026-11-08').check(), 'empty');
      expect(CareSection(id: 's', kind: 'school', title: 'School', body: 'x' * (maxSectionChars + 1), updatedOn: '2026-11-08').check(), 'too_long');
    });

    test('a contact needs a name and bounded fields', () {
      expect(const CareContact(id: 'p', name: 'Dr A').check(), isNull);
      expect(const CareContact(id: 'p', name: '').check(), 'empty');
      expect(CareContact(id: 'p', name: 'x', phone: '1' * 41).check(), 'too_long');
    });

    test('the print text carries only what was written, and says where it is kept', () {
      final String t = binderAsText('Ivy',
          const <CareSection>[
            CareSection(id: 'a', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts, per Mom.', updatedOn: '2026-11-08'),
            CareSection(id: 'b', kind: 'school', title: 'School', body: '', updatedOn: '2026-11-08'),
          ],
          const <CareContact>[CareContact(id: 'p', name: 'Nana', relation: 'grandmother', phone: '555-0101')]);
      expect(t, contains('Ivy: care binder'));
      expect(t, contains('Written by a guardian. Kept on this device only.'));
      expect(t, contains('Peanuts, per Mom.'));
      expect(t, contains('(nothing written yet)'));
      expect(t, contains('Nana - grandmother - 555-0101'));
    });
  });

  group('hospital mode: only what a guardian wrote', () {
    test('allergies come only from allergy sections that have words in them', () {
      final HospitalSummary s = hospitalSummary(
          const <CareSection>[
            CareSection(id: 'a', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts', updatedOn: '2026-11-08'),
            CareSection(id: 'b', kind: 'allergies', title: 'Allergies (written by a guardian)', body: '  ', updatedOn: '2026-11-08'),
            CareSection(id: 'c', kind: 'routines', title: 'Routines', body: 'Bath at 7', updatedOn: '2026-11-08'),
          ],
          const <CareContact>[], null);
      expect(s.allergies.map((CareSection x) => x.id), <String>['a']);
      expect(s.hasAnything, isTrue);
    });

    test('with nothing written there is nothing to show, and nothing is invented', () {
      final HospitalSummary s = hospitalSummary(const <CareSection>[], const <CareContact>[], null);
      expect(s.hasAnything, isFalse);
      expect(s.notes.isBlank, isTrue);
    });

    test('notes are bounded and round-trip', () {
      expect(HospitalNotes(happeningToday: 'x' * (maxHospitalFieldChars + 1)).check(), 'too_long');
      const HospitalNotes n = HospitalNotes(happeningToday: 'Scan at 2', toBring: 'Owl');
      final HospitalNotes back = HospitalNotes.fromJson(n.toJson())!;
      expect(back.happeningToday, 'Scan at 2');
      expect(back.toBring, 'Owl');
      expect(back.id, 'hospital');
    });
  });

  group('picture stories: guardian-written, bounded, off until shown', () {
    ExplainerStory story({List<String>? pages, String title = 'The hospital', bool shown = false, Uint8List? thumb}) =>
        ExplainerStory(id: 'e', title: title, pages: pages ?? <String>['One'], updatedOn: '2026-11-08', shownToHer: shown, thumb: thumb);

    test('not shown to her until a guardian turns it on', () => expect(story().shownToHer, isFalse));

    test('between one and six pages, each non-empty and within the model\'s page length', () {
      expect(story().check(), isNull);
      expect(story(pages: <String>[]).check(), 'bad_page_count');
      expect(story(pages: List<String>.filled(maxStoryPages + 1, 'p')).check(), 'bad_page_count');
      expect(story(pages: List<String>.filled(maxStoryPages, 'p')).check(), isNull);
      expect(story(pages: <String>[' ']).check(), 'empty');
      expect(story(pages: <String>['x' * (maxStoryPageChars + 1)]).check(), 'too_long');
    });

    test('refused: no title, a photo too big', () {
      expect(story(title: '').check(), 'empty');
      expect(story(thumb: _bytes(maxThumbBytes + 1)).check(), 'photo_too_big');
    });

    test('round-trips', () {
      final ExplainerStory back = ExplainerStory.fromJson(story(pages: <String>['a', 'b'], shown: true).toJson())!;
      expect(back.pages, <String>['a', 'b']);
      expect(back.shownToHer, isTrue);
    });
  });

  group('appointment prep: a list, no reminders', () {
    AppointmentPrep prep({String title = 'Check-up', String? on, List<PrepLine>? list, List<String>? qs}) => AppointmentPrep(
        id: 'a', title: title, createdOn: '2026-11-08', on: on,
        checklist: list ?? const <PrepLine>[], questions: qs ?? const <String>[]);

    test('needs a title; the date is optional and, if given, a real date', () {
      expect(prep().check(), isNull);
      expect(prep(title: '').check(), 'empty');
      expect(prep(on: '2026-12-01').check(), isNull);
      expect(prep(on: 'tuesday').check(), 'bad_date');
    });

    test('lines and questions are bounded in number and length', () {
      expect(prep(list: List<PrepLine>.filled(maxPrepLines + 1, const PrepLine('x'))).check(), 'too_many');
      expect(prep(qs: List<String>.filled(maxPrepLines + 1, 'x')).check(), 'too_many');
      expect(prep(list: <PrepLine>[PrepLine('x' * (maxPrepLineChars + 1))]).check(), 'too_long');
      expect(prep(qs: <String>['x' * (maxPrepLineChars + 1)]).check(), 'too_long');
    });

    test('ticking a line is kept; there is nothing in the model that schedules or notifies', () {
      final AppointmentPrep p = prep(list: const <PrepLine>[PrepLine('Insurance card', done: true)], qs: const <String>['How long?']);
      final AppointmentPrep back = AppointmentPrep.fromJson(p.toJson())!;
      expect(back.checklist.single.done, isTrue);
      expect(back.questions, <String>['How long?']);
      final String keys = jsonEncode(p.toJson()).toLowerCase();
      for (final String bad in <String>['remind', 'notify', 'schedule', 'alarm']) {
        expect(keys, isNot(contains(bad)));
      }
    });
  });

  group('suite switches', () {
    test('every suite is on until a guardian switches it off', () {
      const SuiteSwitches s = SuiteSwitches();
      for (final String k in allGrowingCareSuites) {
        expect(s.on(k), isTrue);
      }
    });

    test('switching one off affects only that one', () {
      final SuiteSwitches s = const SuiteSwitches().withSuite('memoryBox', false);
      expect(s.on('memoryBox'), isFalse);
      expect(s.on('pencilMarks'), isTrue);
    });

    test('an unknown suite is refused, and unknown keys in storage are ignored', () {
      expect(() => const SuiteSwitches().withSuite('nope', false), throwsArgumentError);
      final SuiteSwitches s = SuiteSwitches.fromJson(<String, Object?>{'flags': <String, Object?>{'nope': false, 'careBinder': false, 'x': 3}})!;
      expect(s.flags.keys, <String>['careBinder']);
    });

    test('all eight suites have a title, four growing and four care', () {
      expect(growingSuiteKeys, hasLength(4));
      expect(careSuiteKeys, hasLength(4));
      for (final String k in allGrowingCareSuites) {
        expect(suiteTitles[k], isNotNull);
      }
    });
  });

  group('age gating: the family-structure model decides what her app offers', () {
    ChildView view(String band, {Map<String, bool>? suites}) =>
        deriveChildView(const FamilyStructure(), band, suites, const <String>[]);

    test('the youngest band has no More hub, so nothing of this reaches her', () {
      final ChildView v = view('t34');
      expect(v.hasTile('more'), isFalse);
      expect(childSuitesFor(view: v).any, isFalse);
      expect(childSuitesFor(yearsOld: 4).any, isFalse);
    });

    test('from five up her app may offer all five child-facing suites', () {
      for (final String b in <String>['t57', 't812', 't13']) {
        final ChildSuites s = childSuitesFor(view: view(b));
        expect(s.memoryBox && s.pencilMarks && s.firstTimes && s.timeCapsule && s.explainerCards, isTrue, reason: b);
      }
      expect(childSuitesFor(yearsOld: 7).memoryBox, isTrue);
    });

    test('an unknown age fails closed to five, not to the youngest band and not to an adult', () {
      expect(failClosedYears, 5);
      expect(childSuitesFor().memoryBox, isTrue);
      expect(childSuitesFor(yearsOld: -3).any, isFalse, reason: 'junk years go to the youngest band, as bandForYears does');
    });

    test('a guardian switch turns one suite off and leaves the others', () {
      final ChildSuites s = childSuitesFor(view: view('t57'), switches: const SuiteSwitches().withSuite('memoryBox', false));
      expect(s.memoryBox, isFalse);
      expect(s.pencilMarks, isTrue);
    });

    test('there is no care suite in what her app may offer', () {
      final Set<String> childFields = <String>{'memoryBox', 'pencilMarks', 'firstTimes', 'timeCapsule', 'explainerCards'};
      expect(childFields.intersection(careSuiteKeys.toSet()), <String>{'explainerCards'},
          reason: 'only the guardian-authored, guardian-shown picture stories');
      expect(<String>['careBinder', 'hospitalMode', 'appointmentPrep'].where(childFields.contains), isEmpty);
    });
  });

  group('refusal messages and photo bounds', () {
    test('every refusal reason has plain words and none blames her', () {
      for (final String r in <String>[
        'empty', 'too_long', 'bad_date', 'date_not_future', 'date_too_far', 'date_in_future', 'bad_height',
        'photo_too_big', 'too_many', 'too_big', 'full', 'bad_page_count', 'invalid',
      ]) {
        final String m = refusalMessage(r);
        expect(m.length, greaterThan(10), reason: r);
        expect(m.toLowerCase(), isNot(contains('wrong')), reason: r);
      }
      expect(const CareRefused('full').message, contains('full'));
    });

    test('thumbRefusal only refuses what is over the cap', () {
      expect(thumbRefusal(null), isNull);
      expect(thumbRefusal(_bytes(maxThumbBytes)), isNull);
      expect(thumbRefusal(_bytes(maxThumbBytes + 1)), 'photo_too_big');
    });

    test('a bad thumb string decodes to no photo', () {
      expect(decodeThumb('%%%not base64'), isNull);
      expect(decodeThumb(5), isNull);
      expect(encodeThumb(null), isNull);
    });
  });
}
