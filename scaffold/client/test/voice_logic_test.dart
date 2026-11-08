// OLIVE BRANCH — suite C pure logic: feelings weather, worry box, my helpers,
// symbols. Every deny path is a real assertion.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/picture_library.dart';
import 'package:olive_client/rhythm_logic.dart' show RvRefused;
import 'package:olive_client/voice_logic.dart';

Matcher refused(String reason) => throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', reason));

const String day = '2026-11-08';
List<List<double>> scribble() => <List<double>>[
      <double>[0.1, 0.1, 0.5, 0.5, 0.9, 0.2],
      <double>[0.2, 0.8],
    ];

void main() {
  group('feelings weather', () {
    test('six skies, and only those', () {
      expect(weatherIds, <String>['sunny', 'cloudy', 'rainy', 'stormy', 'windy', 'foggy']);
      for (final String id in weatherIds) {
        expect(pickWeather(id, day).weather, id);
      }
      expect(() => pickWeather('happy', day), refused('bad_weather'));
      expect(() => pickWeather('bath', day), refused('bad_weather'));
      expect(() => pickWeather('sunny', 'yesterday'), refused('bad_day'));
    });

    test('only TODAY counts: an earlier pick is gone, not "yesterday\'s feeling"', () {
      final FeelingToday f = pickWeather('stormy', day);
      expect(feelingForToday(f, day)!.weather, 'stormy');
      expect(feelingForToday(f, '2026-11-09'), isNull);
      expect(feelingForToday(f, '2026-11-07'), isNull);
      expect(feelingForToday(null, day), isNull);
    });

    test('the pick has exactly two fields: nothing to share, count, score or chart', () {
      expect(pickWeather('sunny', day).toJson().keys.toSet(), <String>{'weather', 'day'});
    });

    test('a damaged pick loads as absent', () {
      expect(FeelingToday.tryFromJson(<String, Object?>{'weather': 'happy', 'day': day}), isNull);
      expect(FeelingToday.tryFromJson(<String, Object?>{'weather': 'sunny', 'day': 'x'}), isNull);
      expect(FeelingToday.tryFromJson(5), isNull);
      expect(FeelingToday.tryFromJson(pickWeather('foggy', day).toJson())!.weather, 'foggy');
    });
  });

  group('the worry box', () {
    test('a worry is a tapped picture or a drawing, never text', () {
      final Worry p = Worry.picture(id: 'w1', picture: 'worry-dark', madeOn: day);
      expect(p.kind, WorryKind.picture);
      expect(p.shown, isFalse, reason: 'private until SHE chooses');
      final Worry d = Worry.drawing(id: 'w2', strokes: scribble(), madeOn: day);
      expect(d.kind, WorryKind.drawing);
      expect(d.shown, isFalse);
      for (final Worry w in <Worry>[p, d]) {
        expect(w.toJson().keys.any((String k) => <String>['text', 'note', 'tag', 'label', 'score', 'level', 'risk'].contains(k)), isFalse);
      }
    });

    test('only worry pictures are accepted, and ids and days must be real', () {
      expect(() => Worry.picture(id: 'w', picture: 'sunny', madeOn: day), refused('bad_picture'));
      expect(() => Worry.picture(id: 'w', picture: 'nope', madeOn: day), refused('bad_picture'));
      expect(() => Worry.picture(id: 'bad id', picture: 'worry-dark', madeOn: day), refused('bad_id'));
      expect(() => Worry.picture(id: 'w', picture: 'worry-dark', madeOn: 'x'), refused('bad_day'));
      expect(() => Worry.drawing(id: 'w', strokes: scribble(), madeOn: 'x'), refused('bad_day'));
      expect(() => Worry.drawing(id: '', strokes: scribble(), madeOn: day), refused('bad_id'));
    });

    test('a drawing is bounded, finite and inside the page; it is quantised', () {
      expect(() => checkedStrokes(const <List<double>>[]), refused('empty_drawing'));
      expect(() => checkedStrokes(<List<double>>[<double>[]]), refused('bad_stroke'));
      expect(() => checkedStrokes(<List<double>>[<double>[0.1]]), refused('bad_stroke'));
      expect(() => checkedStrokes(<List<double>>[<double>[0.1, 0.2, 0.3]]), refused('bad_stroke'));
      expect(() => checkedStrokes(<List<double>>[<double>[0.1, double.nan]]), refused('bad_point'));
      expect(() => checkedStrokes(<List<double>>[<double>[0.1, double.infinity]]), refused('bad_point'));
      expect(() => checkedStrokes(<List<double>>[<double>[0.1, 1.5]]), refused('bad_point'));
      expect(() => checkedStrokes(<List<double>>[<double>[-0.1, 0.5]]), refused('bad_point'));
      expect(() => checkedStrokes(<List<double>>[for (int i = 0; i <= maxStrokes; i++) <double>[0.5, 0.5]]), refused('too_many_strokes'));
      expect(() => checkedStrokes(<List<double>>[List<double>.filled(maxPointsPerStroke * 2 + 2, 0.5)]), refused('too_many_points'));
      expect(checkedStrokes(<List<double>>[List<double>.filled(maxPointsPerStroke * 2, 0.5)]).length, 1);
      expect(checkedStrokes(<List<double>>[<double>[0.123456, 0.999999]]).single, <double>[0.123, 1.0]);
    });

    test('the box is bounded and NEVER silently drops a worry to make room', () {
      List<Worry> box = <Worry>[];
      for (int i = 0; i < maxWorries; i++) {
        box = addWorry(box, Worry.picture(id: 'w$i', picture: 'worry-dark', madeOn: day));
      }
      final List<String> before = box.map((Worry w) => w.id).toList();
      expect(() => addWorry(box, Worry.picture(id: 'extra', picture: 'worry-dark', madeOn: day)), refused('box_full'));
      expect(box.map((Worry w) => w.id).toList(), before);
      expect(() => addWorry(<Worry>[box.first], box.first), refused('duplicate_id'));
    });

    test('"show my grown-up" is her choice, reversible, and the only way a grown-up sees one', () {
      List<Worry> box = <Worry>[
        Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day),
        Worry.drawing(id: 'b', strokes: scribble(), madeOn: day),
        Worry.picture(id: 'c', picture: 'worry-storm', madeOn: day),
      ];
      expect(shownToGrownUp(box), isEmpty, reason: 'nothing is shown automatically');
      box = setWorryShown(box, 'b', true);
      expect(shownToGrownUp(box).map((Worry w) => w.id), <String>['b']);
      box = setWorryShown(box, 'a', true);
      expect(shownToGrownUp(box).map((Worry w) => w.id), <String>['a', 'b']);
      box = setWorryShown(box, 'b', false);
      expect(shownToGrownUp(box).map((Worry w) => w.id), <String>['a']);
      expect(() => setWorryShown(box, 'zz', true), refused('unknown_worry'));
    });

    test('"let it float away" removes the worry for real', () {
      final List<Worry> box = <Worry>[
        Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day, shown: true),
        Worry.drawing(id: 'b', strokes: scribble(), madeOn: day),
      ];
      final List<Worry> after = floatAway(box, 'a');
      expect(after.map((Worry w) => w.id), <String>['b']);
      expect(shownToGrownUp(after), isEmpty);
      expect(jsonEncode(after.map((Worry w) => w.toJson()).toList()).contains('worry-dark'), isFalse);
      expect(() => floatAway(box, 'zz'), refused('unknown_worry'));
    });

    test('round-trip through JSON; damaged rows are skipped', () {
      final Worry d = Worry.drawing(id: 'b', strokes: scribble(), madeOn: day, shown: true);
      final Worry? back = Worry.tryFromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back!.shown, isTrue);
      expect(back.strokes, d.strokes);
      expect(Worry.tryFromJson(5), isNull);
      expect(Worry.tryFromJson(<String, Object?>{'id': 'a', 'kind': 'text', 'madeOn': day}), isNull);
      expect(Worry.tryFromJson(<String, Object?>{'id': 'a', 'kind': 'picture', 'picture': 'sunny', 'madeOn': day}), isNull);
      expect(Worry.tryFromJson(<String, Object?>{'id': 'a', 'kind': 'drawing', 'strokes': <Object?>[<Object?>[2, 2]], 'madeOn': day}), isNull);
      expect(Worry.tryFromJson(<String, Object?>{'id': 'a', 'kind': 'drawing', 'strokes': 'x', 'madeOn': day}), isNull);
    });
  });

  group('my helpers', () {
    test('a helper has a name, a person picture and a short line', () {
      final Helper h = makeHelper(id: 'h1', name: 'Nana', picture: 'grandparent', line: 'Knock on the door at the end of the hall');
      expect(h.saidYes, isFalse, reason: 'not until a grown-up records that they said yes');
      expect(() => makeHelper(id: 'h', name: '', picture: 'grandparent'), refused('empty_text'));
      expect(() => makeHelper(id: 'h', name: 'x' * 31, picture: 'grandparent'), refused('too_long'));
      expect(() => makeHelper(id: 'h', name: 'Nana', picture: 'sunny'), refused('bad_picture'));
      expect(() => makeHelper(id: 'h', name: 'Nana', picture: null), refused('bad_picture'));
      expect(() => makeHelper(id: 'bad id', name: 'Nana', picture: 'grandparent'), refused('bad_id'));
      expect(() => makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', line: 'x' * 61), refused('too_long'));
    });

    test('no phone number and no address in a name or a line', () {
      expect(() => makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', line: 'Call 555 123 4567'), refused('looks_like_number'));
      expect(() => makeHelper(id: 'h', name: '555 123 4567', picture: 'grandparent'), refused('looks_like_number'));
      expect(() => makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', line: '12 Oak Street'), refused('looks_like_location'));
    });

    test('she sees only the people who said yes, in the order a grown-up set', () {
      final List<Helper> hs = <Helper>[
        makeHelper(id: 'a', name: 'Nana', picture: 'grandparent', saidYes: true),
        makeHelper(id: 'b', name: 'Mr Reyes', picture: 'counsellor'),
        makeHelper(id: 'c', name: 'Aunt Mia', picture: 'aunt-uncle', saidYes: true),
      ];
      expect(helpersForChild(hs).map((Helper h) => h.id), <String>['a', 'c']);
    });

    test('the list is bounded and unique', () {
      final List<Helper> nine = <Helper>[for (int i = 0; i <= maxHelpers; i++) makeHelper(id: 'h$i', name: 'N$i', picture: 'friend')];
      expect(() => checkedHelpers(nine), refused('too_many_helpers'));
      expect(() => checkedHelpers(<Helper>[nine[0], nine[0]]), refused('duplicate_id'));
      expect(checkedHelpers(nine.take(maxHelpers).toList()).length, maxHelpers);
    });

    test('a damaged helper row is skipped', () {
      expect(Helper.tryFromJson(5), isNull);
      expect(Helper.tryFromJson(<String, Object?>{'id': 'a', 'name': 'Nana', 'picture': 'sunny'}), isNull);
      expect(Helper.tryFromJson(makeHelper(id: 'a', name: 'Nana', picture: 'grandparent', saidYes: true).toJson())!.saidYes, isTrue);
    });
  });

  group('symbols', () {
    test('the core board is always there, her personal symbols come after', () {
      expect(coreSymbolIds.length, 16);
      expect(coreSymbolIds, containsAll(<String>['sym-i', 'sym-want', 'sym-more', 'sym-stop', 'sym-help', 'sym-hurt', 'sym-tired', 'sym-play']));
      expect(boardSymbols(<String>['sym-owl']).last, 'sym-owl');
      expect(boardSymbols(const <String>[]), coreSymbolIds);
    });

    test('personal symbols: extras only, bounded, unique', () {
      expect(checkedPersonalSymbols(<String>['sym-owl', 'sym-bath']), <String>['sym-owl', 'sym-bath']);
      expect(() => checkedPersonalSymbols(<String>['sym-want']), refused('bad_picture'), reason: 'a core word is not an extra');
      expect(() => checkedPersonalSymbols(<String>['sunny']), refused('bad_picture'));
      expect(() => checkedPersonalSymbols(<String>['sym-owl', 'sym-owl']), refused('duplicate_id'));
      final List<String> extras = picturesIn(PictureGroup.symbolExtra).map((PictureDef p) => p.id).toList();
      expect(extras.length, maxPersonalSymbols);
      expect(checkedPersonalSymbols(extras).length, maxPersonalSymbols);
    });

    test('the strip is bounded and only takes symbols', () {
      List<String> s = const <String>[];
      s = stripAdd(s, 'sym-i');
      s = stripAdd(s, 'sym-want');
      s = stripAdd(s, 'sym-more');
      expect(s, <String>['sym-i', 'sym-want', 'sym-more']);
      expect(() => stripAdd(s, 'sunny'), refused('bad_picture'));
      expect(() => stripAdd(s, 'nope'), refused('bad_picture'));
      expect(stripBack(s), <String>['sym-i', 'sym-want']);
      expect(stripBack(const <String>[]), isEmpty);
      List<String> full = const <String>[];
      for (int i = 0; i < maxStripLength; i++) {
        full = stripAdd(full, 'sym-more');
      }
      expect(() => stripAdd(full, 'sym-more'), refused('strip_full'));
    });

    test('the sentence is the words as tapped: never rewritten, never grammar-corrected', () {
      expect(sentenceOf(<String>['sym-i', 'sym-want', 'sym-more']), 'I want more');
      expect(sentenceOf(<String>['sym-stop']), 'Stop');
      expect(sentenceOf(<String>['sym-more', 'sym-eat', 'sym-i']), 'More eat I', reason: 'order is hers; nothing is fixed for her');
      expect(sentenceOf(const <String>[]), '');
      expect(sentenceOf(<String>['sym-hurt', 'sym-help']), 'Hurt help');
    });
  });

  group('the voice document', () {
    test('round-trips; damaged parts are skipped; absent means on', () {
      final VoiceDoc d = VoiceDoc(
          helpers: <Helper>[makeHelper(id: 'a', name: 'Nana', picture: 'grandparent', saidYes: true)],
          personalSymbols: const <String>['sym-owl'], suiteOn: false);
      final VoiceDoc back = VoiceDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back.helpers.single.name, 'Nana');
      expect(back.personalSymbols, <String>['sym-owl']);
      expect(back.suiteOn, isFalse);
      final VoiceDoc odd = VoiceDoc.fromJson(<String, Object?>{
        'helpers': <Object?>[5, <String, Object?>{'id': 'a', 'name': 'Nana', 'picture': 'grandparent'}],
        'personalSymbols': <Object?>['sym-owl', 'sym-owl', 'sunny', 4],
      });
      expect(odd.helpers.length, 1);
      expect(odd.personalSymbols, <String>['sym-owl']);
      expect(odd.suiteOn, isTrue);
      expect(VoiceDoc.fromJson('x').helpers, isEmpty);
    });
  });
}
