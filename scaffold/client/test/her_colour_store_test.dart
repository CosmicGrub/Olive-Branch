// OLIVE BRANCH — the in-process colour store runs the real rules: one question
// a day, latest wins, a colour day holds, art settings and the play window obey
// the same checks the TypeScript module does. Local-first: no network anywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/her_colour_store.dart';

void main() {
  var clock = DateTime(2026, 11, 7, 8, 0);
  MemoryColourStore make({int age = 7, PlayWindow? window, ArtSettings? art}) {
    clock = DateTime(2026, 11, 7, 8, 0);
    return MemoryColourStore(ageYears: age, now: () => clock, window: window, art: art);
  }

  group('one question a day', () {
    test('first morning: no colour, the question is to be asked', () async {
      final s = make();
      final t = await s.today();
      expect(t.colourId, isNull);
      expect(t.ask, isTrue);
      expect(t.localDate, '2026-11-07');
    });

    test('answering ends the question and sets the colour', () async {
      final s = make();
      final t = await s.answer('sea');
      expect(t.colourId, 'sea');
      expect(t.ask, isFalse);
      expect(t.chosenBy, 'child');
      expect((await s.today()).ask, isFalse);
    });

    test('a later answer replaces an earlier one the same day', () async {
      final s = make();
      await s.answer('sea');
      clock = clock.add(const Duration(minutes: 5));
      expect((await s.answer('sunny')).colourId, 'sunny');
    });

    test('tomorrow she is asked again and yesterday’s colour carries over', () async {
      final s = make();
      await s.answer('sea');
      clock = clock.add(const Duration(days: 1));
      final t = await s.today();
      expect(t.ask, isTrue);
      expect(t.colourId, 'sea');
      expect(t.carriedOver, isTrue);
    });

    test('an unknown colour is not taken', () async {
      final s = make();
      expect((await s.answer('red')).colourId, isNull);
    });
  });

  group('a colour day', () {
    test('replaces her answer and is not replaced by her tap', () async {
      final s = make();
      await s.answer('sea');
      final day = await s.setColourDay('mint');
      expect(day.colourId, 'mint');
      expect(day.override, isTrue);
      clock = clock.add(const Duration(minutes: 1));
      expect((await s.answer('sunny')).colourId, 'mint');
      expect((await s.today()).ask, isFalse);
    });

    test('clearing hands the question back, and never deletes her own answer', () async {
      final s = make();
      await s.answer('sea');
      expect(await s.clearColourDay(), isFalse);
      expect((await s.today()).colourId, 'sea');
      await s.setColourDay('mint');
      expect(await s.clearColourDay(), isTrue);
      final t = await s.today();
      expect(t.ask, isTrue);
    });
  });

  group('what the guardian is told', () {
    test('one neutral sentence and the time, nothing else', () async {
      final s = make();
      await s.answer('sea');
      final v = await s.view();
      expect(v.line, 'Today her colour is sea blue.');
      expect(v.chosenAtLocal, '08:00');
      expect(v.devicesAgree, isTrue);
    });
    test('before she has chosen there is nothing to say', () async {
      final v = await make().view();
      expect(v.line, isNull);
      expect(v.chosenAtLocal, isNull);
    });
  });

  group('the daily question can be switched off', () {
    test('it is not asked, and her tap is not taken', () async {
      final s = make();
      expect((await s.saveArt({'dailyQuestion': false})).ok, isTrue);
      expect((await s.today()).ask, isFalse);
      expect((await s.answer('sea')).colourId, isNull);
      expect((await s.setColourDay('mint')).colourId, 'mint');
    });
  });

  group('art settings', () {
    test('defaults are paper with six styles', () async {
      final a = await make().art();
      expect(a.artStyle, 'paper');
      expect(a.allowedStyles.length, 6);
      expect(a.allowedStyles.contains('pixel'), isFalse);
    });
    test('a guardian picks a style; her device reads it', () async {
      final s = make();
      final r = await s.saveArt({'artStyle': 'watercolour'});
      expect(r.ok, isTrue);
      expect((await s.artStyle()).artStyle, 'watercolour');
    });
    test('pixel is refused under 8 and allowed from 8', () async {
      final young = make(age: 7);
      expect((await young.saveArt({'artStyle': 'pixel', 'allowedStyles': ['pixel', 'line']})).reason, 'style_not_for_age');
      final older = make(age: 8);
      expect((await older.saveArt({'artStyle': 'pixel', 'allowedStyles': ['pixel', 'line']})).ok, isTrue);
    });
    test('a bad patch changes nothing', () async {
      final s = make();
      expect((await s.saveArt({'mood': 'x'})).reason, 'unknown_field');
      expect((await s.saveArt({'allowedStyles': ['line']})).reason, 'style_not_allowed');
      expect((await s.art()).artStyle, 'paper');
    });
  });

  group('the play window', () {
    const w = PlayWindow(opensMin: 930, restsMin: 1140, windDownMin: 30);
    test('no window means games are open', () async {
      expect((await make().playWindow()).state, 'open');
    });
    test('open, winding down, resting — in her local time', () async {
      final s = make();
      await s.savePlayWindow(w);
      clock = DateTime(2026, 11, 7, 16, 0);
      expect((await s.playWindow()).state, 'open');
      clock = DateTime(2026, 11, 7, 18, 40);
      expect((await s.playWindow()).state, 'open', reason: 'the tail FOLLOWS the rest time (19:00), it does not precede it');
      clock = DateTime(2026, 11, 7, 19, 10);
      final wind = await s.playWindow();
      expect(wind.state, 'winding_down');
      expect(wind.line, 'It’s getting sleepy. One more, then goodnight.');
      clock = DateTime(2026, 11, 7, 19, 30);
      final rest = await s.playWindow();
      expect(rest.state, 'resting');
      expect(rest.line, contains('tomorrow'));
      clock = DateTime(2026, 11, 7, 8, 0);
      expect((await s.playWindow()).state, 'resting');
    });
    test('a longer window is flagged; a shorter one is not; a bad one is refused', () async {
      final s = make();
      expect((await s.savePlayWindow(w)).lengthened, isFalse);
      expect((await s.savePlayWindow(const PlayWindow(opensMin: 930, restsMin: 1200, windDownMin: 30))).lengthened, isTrue);
      expect((await s.savePlayWindow(const PlayWindow(opensMin: 960, restsMin: 1100, windDownMin: 30))).lengthened, isFalse);
      expect((await s.savePlayWindow(const PlayWindow(opensMin: 700, restsMin: 600, windDownMin: 0))).reason, 'bad_restsMin');
      expect((await s.playWindow()).window!.restsMin, 1100);
    });
  });

  test('the process-wide store is one object, so both shells see the same colour', () {
    expect(identical(sharedColourStore, sharedColourStore), isTrue);
    expect(sharedColourStore, isA<ChildColourStore>());
    expect(sharedColourStore, isA<GuardianColourStore>());
  });
}
