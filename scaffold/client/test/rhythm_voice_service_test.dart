// OLIVE BRANCH — who may do what in suites B and C, held in the SERVICE (so a
// screen that forgot to check cannot write). Every deny path is a real assertion.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/voice_logic.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'ivy');
const FamilyPrincipal leo = FamilyPrincipal(roleName: 'child', childId: 'leo');
const FamilyPrincipal sitter = FamilyPrincipal(roleName: 'sitter', userId: 's1');
const FamilyPrincipal guardianNoId = FamilyPrincipal(roleName: 'guardian');
const FamilyPrincipal childNoId = FamilyPrincipal(roleName: 'child');

DateTime _now = DateTime(2026, 11, 8, 19);

RhythmVoiceService make({bool local = false}) => local
    ? RhythmVoiceService.local(LocalServices.memory(childId: 'ivy'), clock: () => _now)
    : RhythmVoiceService.memory(childId: 'ivy', clock: () => _now);

Routine routine() => addStep(addStep(const Routine(title: 'Bedtime'), newStep('a', 'bath')), newStep('b', 'book'));

void both(String name, Future<void> Function(RhythmVoiceService s) body) {
  test('$name (memory)', () => body(make()));
  test('$name (LocalStore)', () => body(make(local: true)));
}

void main() {
  setUp(() => _now = DateTime(2026, 11, 8, 19));

  group('guardian-authored content: a guardian principal only', () {
    both('every guardian write is refused for the child, a sitter, anonymous and half-formed principals', (RhythmVoiceService s) async {
      final List<FamilyPrincipal?> nobody = <FamilyPrincipal?>[ivy, leo, sitter, guardianNoId, childNoId, null, const FamilyPrincipal()];
      for (final FamilyPrincipal? p in nobody) {
        final List<RvResult> r = <RvResult>[
          await s.saveRoutine(p, routine()),
          await s.clearRoutine(p),
          await s.saveBoard(p, makeBoard(boardCard('bath'), boardCard('play'))),
          await s.clearBoard(p),
          await s.savePacking(p, addPackItem(const PackingList(), newPackItem('o', 'owl'))),
          await s.newBag(p),
          await s.saveSensory(p, const SensoryProfile(sound: SoundLevel.off)),
          await s.savePlace(p, makePlan('x', const <PlaceStop>[], <String>['a'])),
          await s.setRhythmSuite(p, false),
          await s.setVoiceSuite(p, false),
          await s.saveHelpers(p, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]),
          await s.savePersonalSymbols(p, <String>['sym-owl']),
        ];
        for (final RvResult x in r) {
          expect(x.ok, isFalse, reason: '$p');
          expect(x.reason, 'guardian_only', reason: '$p');
        }
      }
      // ...and nothing was written.
      final RhythmDoc d = await s.rhythm.load();
      expect(d.routine, isNull);
      expect(d.board, isNull);
      expect(d.packing.items, isEmpty);
      expect(d.sensory.sound, SoundLevel.full);
      expect(d.suiteOn, isTrue);
      expect(await s.place.load(), isNull);
      expect((await s.voice.load()).helpers, isEmpty);
      expect((await s.voice.load()).suiteOn, isFalse, reason: 'Voice stays off; nothing was written');
      expect(d.twoHomes, isFalse);
    });

    both('a guardian can write each one, and the child then reads it', (RhythmVoiceService s) async {
      expect((await s.saveRoutine(guardian, routine())).ok, isTrue);
      expect((await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('play')))).ok, isTrue);
      expect((await s.savePacking(guardian, addPackItem(const PackingList(), newPackItem('o', 'owl')))).ok, isTrue);
      expect((await s.saveSensory(guardian, const SensoryProfile(reduceMotion: true))).ok, isTrue);
      expect((await s.savePlace(guardian, makePlan('Dad', <PlaceStop>[newStop('s', 'door', 'Door')], <String>['Hi']))).ok, isTrue);
      expect((await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)])).ok, isTrue);
      expect((await s.savePersonalSymbols(guardian, <String>['sym-owl'])).ok, isTrue);
      expect((await s.setRhythmSuite(guardian, false)).ok, isTrue);
      final RhythmDoc d = await s.loadRhythm(ivy);
      expect(d.routine!.steps.length, 2);
      expect(d.board!.first.picture, 'bath');
      expect(d.packing.items.length, 1);
      expect(d.sensory.reduceMotion, isTrue);
      expect(d.suiteOn, isFalse);
      expect((await s.loadPlace(ivy))!.name, 'Dad');
      expect((await s.loadVoice(ivy)).helpers.single.name, 'Nana');
    });

    both('a guardian write is refused when the content is bad, and nothing is half-saved', (RhythmVoiceService s) async {
      expect((await s.saveSensory(guardian, const SensoryProfile(brightnessCeiling: 17))).reason, 'bad_brightness');
      expect((await s.saveBoard(guardian, const FirstThenBoard(first: BoardCard(picture: 'bath', label: 'a'), then: BoardCard(picture: 'bath', label: 'b')))).reason, 'bad_board');
      expect((await s.saveBoard(guardian, const FirstThenBoard(first: BoardCard(picture: 'sunny', label: 'a'), then: BoardCard(picture: 'bath', label: 'b')))).reason, 'bad_board');
      expect((await s.saveRoutine(guardian, const Routine(title: 'x', steps: <RoutineStep>[RoutineStep(id: 'a', picture: 'sunny', label: 'nope')]))).reason, 'bad_routine');
      expect((await s.savePlace(guardian, const PlacePlan(name: 'Home', stops: <PlaceStop>[PlaceStop(id: 'a', room: 'door', caption: '12 Oak Street')]))).reason, 'bad_plan');
      expect((await s.saveHelpers(guardian, <Helper>[for (int i = 0; i <= maxHelpers; i++) makeHelper(id: 'h$i', name: 'N$i', picture: 'friend')])).reason, 'too_many_helpers');
      expect((await s.savePersonalSymbols(guardian, <String>['sym-want'])).reason, 'bad_picture');
      expect((await s.rhythm.load()).routine, isNull);
      expect((await s.rhythm.load()).board, isNull);
      expect(await s.place.load(), isNull);
    });

    both('a new routine clears yesterday\'s ticks; removing it removes it', (RhythmVoiceService s) async {
      await s.saveRoutine(guardian, routine());
      await s.tickRoutine(ivy);
      expect((await s.routineToday(ivy)).ticks.done, <String>['a']);
      await s.saveRoutine(guardian, routine());
      expect((await s.routineToday(ivy)).ticks.done, isEmpty);
      expect((await s.clearRoutine(guardian)).ok, isTrue);
      expect((await s.routineToday(ivy)).routine, isNull);
    });
  });

  group('the child ticks: this child only', () {
    both('the guardian, another child, a sitter and anonymous principals cannot tick', (RhythmVoiceService s) async {
      await s.saveRoutine(guardian, routine());
      await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('play')));
      await s.savePacking(guardian, addPackItem(const PackingList(), newPackItem('o', 'owl')));
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[guardian, leo, sitter, childNoId, null]) {
        expect((await s.tickRoutine(p)).reason, 'child_only', reason: '$p');
        expect((await s.routineAgain(p)).reason, 'child_only', reason: '$p');
        expect((await s.markBoardFirstDone(p)).reason, 'child_only', reason: '$p');
        expect((await s.togglePack(p, 'o')).reason, 'child_only', reason: '$p');
      }
      expect((await s.routineToday(ivy)).ticks.done, isEmpty);
      expect((await s.boardToday(ivy)).firstDone, isFalse);
      expect((await s.packedToday(ivy)).packed, isEmpty);
    });

    both('she ticks in order, ticks reset the next day, and "again" starts over', (RhythmVoiceService s) async {
      await s.saveRoutine(guardian, routine());
      expect((await s.tickRoutine(ivy)).ok, isTrue);
      expect((await s.routineToday(ivy)).ticks.done, <String>['a']);
      expect((await s.tickRoutine(ivy)).ok, isTrue);
      expect(firstThenOf(routine(), (await s.routineToday(ivy)).ticks).allDone, isTrue);
      _now = DateTime(2026, 11, 9, 7);
      expect((await s.routineToday(ivy)).ticks.done, isEmpty, reason: 'a new day is a fresh start');
      await s.tickRoutine(ivy);
      expect((await s.routineAgain(ivy)).ok, isTrue);
      expect((await s.routineToday(ivy)).ticks.done, isEmpty);
    });

    both('ticking with nothing set up is a refusal, not a crash', (RhythmVoiceService s) async {
      expect((await s.tickRoutine(ivy)).reason, 'no_routine');
      expect((await s.markBoardFirstDone(ivy)).reason, 'no_board');
      expect((await s.togglePack(ivy, 'nope')).reason, 'unknown_item');
    });

    both('first-then done is for today only', (RhythmVoiceService s) async {
      await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('play')));
      expect((await s.boardToday(ivy)).firstDone, isFalse);
      await s.markBoardFirstDone(ivy);
      expect((await s.boardToday(ivy)).firstDone, isTrue);
      _now = DateTime(2026, 11, 9, 7);
      expect((await s.boardToday(ivy)).firstDone, isFalse);
    });

    both('the bag: pack, un-pack, and an always-the-same item cannot be ticked', (RhythmVoiceService s) async {
      PackingList l = addPackItem(const PackingList(), newPackItem('o', 'owl'));
      l = addPackItem(l, newPackItem('n', 'night-light', same: true));
      await s.savePacking(guardian, l);
      expect((await s.togglePack(ivy, 'o')).ok, isTrue);
      expect((await s.packedToday(ivy)).packed, <String>['o']);
      expect((await s.togglePack(ivy, 'n')).reason, 'same_at_both');
      expect((await s.togglePack(ivy, 'o')).ok, isTrue);
      expect((await s.packedToday(ivy)).packed, isEmpty);
      await s.togglePack(ivy, 'o');
      expect((await s.newBag(guardian)).ok, isTrue);
      expect((await s.packedToday(ivy)).packed, isEmpty);
    });
  });

  group('guardian-authored content may be READ only by this child or a guardian', () {
    both('anyone else is refused', (RhythmVoiceService s) async {
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[leo, sitter, childNoId, guardianNoId, null]) {
        await expectLater(s.loadRhythm(p), throwsA(isA<RvRefused>()), reason: '$p');
        await expectLater(s.loadVoice(p), throwsA(isA<RvRefused>()), reason: '$p');
        await expectLater(s.loadPlace(p), throwsA(isA<RvRefused>()), reason: '$p');
        await expectLater(s.routineToday(p), throwsA(isA<RvRefused>()), reason: '$p');
      }
    });
  });

  group('feelings weather is private: no guardian read exists', () {
    both('only this child reads or writes it', (RhythmVoiceService s) async {
      expect((await s.pickTodayWeather(ivy, 'stormy')).ok, isTrue);
      expect((await s.weatherToday(ivy))!.weather, 'stormy');
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[guardian, leo, sitter, childNoId, null]) {
        await expectLater(s.weatherToday(p), throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', 'child_only')), reason: '$p');
        expect((await s.pickTodayWeather(p, 'sunny')).reason, 'child_only', reason: '$p');
        expect((await s.forgetWeather(p)).reason, 'child_only', reason: '$p');
      }
      expect((await s.weatherToday(ivy))!.weather, 'stormy', reason: 'unchanged by every refused call');
    });

    both('a bad sky is refused, only today counts, and she can clear it', (RhythmVoiceService s) async {
      expect((await s.pickTodayWeather(ivy, 'happy')).reason, 'bad_weather');
      expect(await s.weatherToday(ivy), isNull);
      await s.pickTodayWeather(ivy, 'rainy');
      await s.pickTodayWeather(ivy, 'sunny');
      expect((await s.weatherToday(ivy))!.weather, 'sunny', reason: 'one pick, replaced, not a list');
      _now = DateTime(2026, 11, 9, 7);
      expect(await s.weatherToday(ivy), isNull, reason: 'yesterday\'s pick is not today\'s');
      await s.pickTodayWeather(ivy, 'foggy');
      expect((await s.forgetWeather(ivy)).ok, isTrue);
      expect(await s.weatherToday(ivy), isNull);
    });

    both('the service offers no way to list past picks', (RhythmVoiceService s) async {
      await s.pickTodayWeather(ivy, 'rainy');
      _now = DateTime(2026, 11, 9, 7);
      await s.pickTodayWeather(ivy, 'sunny');
      final FeelingToday? stored = await s.feelings.load();
      expect(stored!.toJson().keys.toSet(), <String>{'weather', 'day'});
      expect(stored.weather, 'sunny');
    });
  });

  group('the worry box', () {
    both('nothing is shown to a guardian automatically', (RhythmVoiceService s) async {
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.putWorryDrawing(ivy, <List<double>>[<double>[0.1, 0.2, 0.3, 0.4]]);
      expect((await s.myWorries(ivy)).length, 2);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty);
    });

    both('a guardian sees ONLY the worries she chose to show, and can see them again hidden after she takes it back', (RhythmVoiceService s) async {
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await s.putWorryDrawing(ivy, <List<double>>[<double>[0.5, 0.5]], showGrownUp: true);
      List<Worry> seen = await s.worriesShownToGrownUp(guardian);
      expect(seen.length, 2);
      expect(seen.every((Worry w) => w.shown), isTrue);
      expect(seen.map((Worry w) => w.picture ?? 'drawing').toSet(), <String>{'worry-storm', 'drawing'});
      final String stormId = seen.firstWhere((Worry w) => w.picture == 'worry-storm').id;
      expect((await s.showWorryToGrownUp(ivy, stormId, false)).ok, isTrue);
      seen = await s.worriesShownToGrownUp(guardian);
      expect(seen.length, 1);
      final String darkId = (await s.myWorries(ivy)).firstWhere((Worry w) => w.picture == 'worry-dark').id;
      expect((await s.showWorryToGrownUp(ivy, darkId, true)).ok, isTrue);
      expect((await s.worriesShownToGrownUp(guardian)).length, 2);
    });

    both('only the child may open the box; only a guardian may open the window onto it', (RhythmVoiceService s) async {
      await s.putWorryPicture(ivy, 'worry-dark', showGrownUp: true);
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[guardian, leo, sitter, childNoId, null]) {
        await expectLater(s.myWorries(p), throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', 'child_only')), reason: '$p');
      }
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[ivy, leo, sitter, guardianNoId, null]) {
        await expectLater(s.worriesShownToGrownUp(p), throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', 'guardian_only')), reason: '$p');
      }
    });

    both('a guardian (or anyone else) cannot put in, show, hide or float away a worry', (RhythmVoiceService s) async {
      await s.putWorryPicture(ivy, 'worry-dark');
      final String id = (await s.myWorries(ivy)).single.id;
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[guardian, leo, sitter, childNoId, null]) {
        expect((await s.putWorryPicture(p, 'worry-dark')).reason, 'child_only', reason: '$p');
        expect((await s.putWorryDrawing(p, <List<double>>[<double>[0.1, 0.1]])).reason, 'child_only', reason: '$p');
        expect((await s.showWorryToGrownUp(p, id, true)).reason, 'child_only', reason: '$p');
        expect((await s.floatAwayWorry(p, id)).reason, 'child_only', reason: '$p');
      }
      final List<Worry> box = await s.myWorries(ivy);
      expect(box.length, 1);
      expect(box.single.shown, isFalse);
    });

    both('letting one float away deletes it for real, including from a guardian\'s window', (RhythmVoiceService s) async {
      await s.putWorryPicture(ivy, 'worry-dark', showGrownUp: true);
      await s.putWorryPicture(ivy, 'worry-storm');
      final String id = (await s.myWorries(ivy)).firstWhere((Worry w) => w.picture == 'worry-dark').id;
      expect((await s.floatAwayWorry(ivy, id)).ok, isTrue);
      expect((await s.myWorries(ivy)).map((Worry w) => w.picture), <String?>['worry-storm']);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty);
      expect((await s.floatAwayWorry(ivy, id)).reason, 'unknown_worry');
      expect((await s.showWorryToGrownUp(ivy, 'zz', true)).reason, 'unknown_worry');
    });

    both('bad contents are refused; a full box says so and drops nothing', (RhythmVoiceService s) async {
      expect((await s.putWorryPicture(ivy, 'sunny')).reason, 'bad_picture');
      expect((await s.putWorryDrawing(ivy, const <List<double>>[])).reason, 'empty_drawing');
      expect((await s.putWorryDrawing(ivy, <List<double>>[<double>[0.1, 2]])).reason, 'bad_point');
      expect(await s.myWorries(ivy), isEmpty);
      for (int i = 0; i < maxWorries; i++) {
        expect((await s.putWorryPicture(ivy, 'worry-dark')).ok, isTrue, reason: '$i');
      }
      final List<String> before = (await s.myWorries(ivy)).map((Worry w) => w.id).toList();
      expect((await s.putWorryPicture(ivy, 'worry-storm')).reason, 'box_full');
      expect((await s.myWorries(ivy)).map((Worry w) => w.id).toList(), before);
    });

    both('worry ids are unique even when made in the same instant', (RhythmVoiceService s) async {
      for (int i = 0; i < 5; i++) {
        await s.putWorryPicture(ivy, 'worry-dark');
      }
      final List<String> ids = (await s.myWorries(ivy)).map((Worry w) => w.id).toList();
      expect(ids.toSet().length, 5);
    });
  });

  group('a failed save is reported, never faked', () {
    test('a full area answers "full" and an unwritable one "not_saved"; the guardian is never told it saved', () async {
      final RhythmVoiceService s = RhythmVoiceService(
        childId: 'ivy', clock: () => _now,
        rhythm: MemoryRhythmRepository(), voice: MemoryVoiceRepository(), feelings: MemoryFeelingsRepository(),
        worries: _FailingWorries(const LocalStoreFull('child.ivy.worries', 10)),
        place: _FailingPlace(const LocalStoreException('io', 'disk')),
      );
      expect((await s.savePlace(guardian, makePlan('x', const <PlaceStop>[], <String>['a']))).reason, 'not_saved');
      expect((await s.putWorryPicture(ivy, 'worry-dark')).reason, 'full');
      expect((await s.putWorryPicture(ivy, 'worry-dark')).ok, isFalse);
    });

    test('the largest legal place still fits its area', () async {
      final RhythmVoiceService s = RhythmVoiceService.local(LocalServices.memory(childId: 'ivy'), clock: () => _now);
      final List<int> jpeg = <int>[0xFF, 0xD8, ...List<int>.filled(maxPhotoBytes - 2, 7)];
      final PlacePlan big = makePlan('Big', <PlaceStop>[for (int i = 0; i < maxPlaceStops; i++) newStop('s$i', 'door', 'door', photoBytes: jpeg)], const <String>[]);
      expect((await s.savePlace(guardian, big)).ok, isTrue);
      expect((await s.loadPlace(ivy))!.stops.length, maxPlaceStops);
    });
  });
}

class _FailingWorries implements WorryRepository {
  _FailingWorries(this.error);
  final Object error;
  @override
  Future<List<Worry>> load() async => const <Worry>[];
  @override
  Future<void> save(List<Worry> box) async => throw error;
}

class _FailingPlace implements NewPlaceRepository {
  _FailingPlace(this.error);
  final Object error;
  @override
  Future<PlacePlan?> load() async => null;
  @override
  Future<void> save(PlacePlan? p) async => throw error;
}
