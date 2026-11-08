// OLIVE BRANCH — repositories and the guarded service for suites B and C. No
// longer UNVERIFIED — verified by CI (client/test/rhythm_voice_repositories_test.dart
// and client/test/rhythm_voice_service_test.dart).
//
// THE PATTERN (same as the family and Parent Learn stores): each feature has an
// ABSTRACT repository, an in-memory implementation for tests and the preview, and
// a LocalStore-backed one for the app. The LocalStore ones sit over ONE namespace
// each, named per child by LocalServices (`child.<id>.<area>`), so one child's
// data is never reachable through another's name.
//
//   rhythm   plain      routine, first-then, bag list, sensory profile, today's ticks
//   newplace plain      a place plan and its small room photos
//   voice    plain      helpers a guardian wrote and her personal symbols
//   feelings ENCRYPTED  today's weather pick only
//   worries  ENCRYPTED  worries she put in the box
//
// A failed save THROWS (a full box, an unwritable disk) so the service can say
// so: a guardian is never told something was saved when it was not. A damaged
// document is quarantined by LocalStore and loads as empty.
//
// [RhythmVoiceService] is where WHO may do WHAT is enforced, in code and not only
// in the UI:
//  - a guardian principal writes everything guardian-authored; the child
//    principal cannot (F1-style: `guardian_only`);
//  - the child principal (and only her own id) ticks, picks a weather, and
//    manages her own worries; a guardian cannot read her weather (`child_only`)
//    and sees ONLY the worries she chose to show.
import 'dart:convert';

import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'local_services.dart';
import 'local_store.dart';
import 'rhythm_logic.dart';
import 'voice_logic.dart';

// ------------------------------------------------------------ abstractions ---
abstract class RhythmRepository {
  Future<RhythmDoc> load();
  Future<void> save(RhythmDoc d);
}

abstract class NewPlaceRepository {
  Future<PlacePlan?> load();
  Future<void> save(PlacePlan? p);
}

abstract class VoiceRepository {
  Future<VoiceDoc> load();
  Future<void> save(VoiceDoc d);
}

abstract class FeelingsRepository {
  Future<FeelingToday?> load();
  Future<void> save(FeelingToday? f);
}

abstract class WorryRepository {
  Future<List<Worry>> load();
  Future<void> save(List<Worry> box);
}

// ------------------------------------------------------------- in memory -----
// Held as JSON so a value handed out can never alias the stored one, and so a
// swap to the durable store changes nothing about what a document can hold.
Object? _clone(Object? j) => j == null ? null : jsonDecode(jsonEncode(j));

class MemoryRhythmRepository implements RhythmRepository {
  Object? _j;
  @override
  Future<RhythmDoc> load() async => RhythmDoc.fromJson(_clone(_j));
  @override
  Future<void> save(RhythmDoc d) async => _j = _clone(d.toJson());
}

class MemoryNewPlaceRepository implements NewPlaceRepository {
  Object? _j;
  @override
  Future<PlacePlan?> load() async => PlacePlan.tryFromJson(_clone(_j));
  @override
  Future<void> save(PlacePlan? p) async => _j = p == null ? null : _clone(p.toJson());
}

class MemoryVoiceRepository implements VoiceRepository {
  Object? _j;
  @override
  Future<VoiceDoc> load() async => VoiceDoc.fromJson(_clone(_j));
  @override
  Future<void> save(VoiceDoc d) async => _j = _clone(d.toJson());
}

class MemoryFeelingsRepository implements FeelingsRepository {
  Object? _j;
  @override
  Future<FeelingToday?> load() async => FeelingToday.tryFromJson(_clone(_j));
  @override
  Future<void> save(FeelingToday? f) async => _j = f == null ? null : _clone(f.toJson());
}

class MemoryWorryRepository implements WorryRepository {
  Object? _j;
  @override
  Future<List<Worry>> load() async => _worriesFromJson(_clone(_j));
  @override
  Future<void> save(List<Worry> box) async => _j = _clone(<Object?>[for (final Worry w in box) w.toJson()]);
}

List<Worry> _worriesFromJson(Object? j) {
  final List<Worry> out = <Worry>[];
  if (j is List) {
    final Set<String> seen = <String>{};
    for (final Object? r in j) {
      final Worry? w = Worry.tryFromJson(r);
      if (w != null && seen.add(w.id) && out.length < maxWorries) out.add(w);
    }
  }
  return out;
}

// ------------------------------------------------------- LocalStore backed ---
/// Reads one key, treating a read failure as "nothing there" so a damaged file
/// never stops the shell.
Future<Object?> _read(LocalNamespace ns, String key) async {
  try {
    return await ns.get(key);
  } catch (_) {
    return null;
  }
}

class LocalStoreRhythmRepository implements RhythmRepository {
  LocalStoreRhythmRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<RhythmDoc> load() async => RhythmDoc.fromJson(await _read(_ns, _key));
  @override
  Future<void> save(RhythmDoc d) => _ns.put(_key, d.toJson());
}

class LocalStoreNewPlaceRepository implements NewPlaceRepository {
  LocalStoreNewPlaceRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'plan';
  @override
  Future<PlacePlan?> load() async => PlacePlan.tryFromJson(await _read(_ns, _key));
  @override
  Future<void> save(PlacePlan? p) => p == null ? _ns.delete(_key) : _ns.put(_key, p.toJson());
}

class LocalStoreVoiceRepository implements VoiceRepository {
  LocalStoreVoiceRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<VoiceDoc> load() async => VoiceDoc.fromJson(await _read(_ns, _key));
  @override
  Future<void> save(VoiceDoc d) => _ns.put(_key, d.toJson());
}

class LocalStoreFeelingsRepository implements FeelingsRepository {
  LocalStoreFeelingsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'today';
  @override
  Future<FeelingToday?> load() async => FeelingToday.tryFromJson(await _read(_ns, _key));
  @override
  Future<void> save(FeelingToday? f) => f == null ? _ns.delete(_key) : _ns.put(_key, f.toJson());
}

class LocalStoreWorryRepository implements WorryRepository {
  LocalStoreWorryRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'box';
  @override
  Future<List<Worry>> load() async => _worriesFromJson(await _read(_ns, _key));
  @override
  Future<void> save(List<Worry> box) =>
      box.isEmpty ? _ns.delete(_key) : _ns.put(_key, <Object?>[for (final Worry w in box) w.toJson()]);
}

// ---------------------------------------------------------------- service ----
/// The result of a write: ok, or a short stable [reason] a screen can word
/// gently. Never an exception for an expected refusal.
class RvResult {
  const RvResult.ok() : ok = true, reason = '';
  const RvResult.no(this.reason) : ok = false;
  final bool ok;
  final String reason;
  @override
  String toString() => ok ? 'RvResult.ok' : 'RvResult.no($reason)';
}

class RhythmVoiceService {
  RhythmVoiceService({
    required this.childId,
    required this.rhythm,
    required this.place,
    required this.voice,
    required this.feelings,
    required this.worries,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// An in-memory service (tests, and the preview before a store is wired).
  factory RhythmVoiceService.memory({String childId = 'demo-child', DateTime Function()? clock}) =>
      RhythmVoiceService(
        childId: childId, clock: clock,
        rhythm: MemoryRhythmRepository(), place: MemoryNewPlaceRepository(), voice: MemoryVoiceRepository(),
        feelings: MemoryFeelingsRepository(), worries: MemoryWorryRepository(),
      );

  /// The durable service over [services]' LocalStore, scoped to [childId]
  /// (default: the device's child). Encrypted areas stay encrypted.
  factory RhythmVoiceService.local(LocalServices services, {String? childId, DateTime Function()? clock}) =>
      RhythmVoiceService(
        childId: childId ?? services.childId, clock: clock,
        rhythm: LocalStoreRhythmRepository(services.area('rhythm', ownerId: childId)),
        place: LocalStoreNewPlaceRepository(services.area('newplace', ownerId: childId)),
        voice: LocalStoreVoiceRepository(services.area('voice', ownerId: childId)),
        feelings: LocalStoreFeelingsRepository(services.area('feelings', ownerId: childId)),
        worries: LocalStoreWorryRepository(services.area('worries', ownerId: childId)),
      );

  /// The one shared instance the shells use, bound to [LocalServices.current]
  /// when first read for a given child.
  static RhythmVoiceService? _shared;
  static String? _sharedFor;
  static RhythmVoiceService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    final String key = '${identityHashCode(s)}:${childId ?? s.childId}';
    if (_shared == null || _sharedFor != key) {
      _shared = RhythmVoiceService.local(s, childId: childId);
      _sharedFor = key;
    }
    return _shared!;
  }

  /// Puts the shared instance back, for test tear-downs.
  static void resetShared() {
    _shared = null;
    _sharedFor = null;
  }

  final String childId;
  final RhythmRepository rhythm;
  final NewPlaceRepository place;
  final VoiceRepository voice;
  final FeelingsRepository feelings;
  final WorryRepository worries;
  final DateTime Function() _clock;
  int _ids = 0;

  String today() => isoDayOf(_clock());

  /// A new id, unique within this process and (through the clock) across runs.
  String newId(String prefix) => '$prefix${_clock().microsecondsSinceEpoch}_${_ids++}';

  // ---- who ----
  bool _isGuardian(FamilyPrincipal? p) => canEditStructure(p);
  bool _isThisChild(FamilyPrincipal? p) =>
      p != null && p.roleName == 'child' && p.childId is String && p.childId == childId;

  Future<RvResult> _guarded(FamilyPrincipal? p, Future<void> Function() body) async {
    if (!_isGuardian(p)) return const RvResult.no('guardian_only');
    return _run(body);
  }

  Future<RvResult> _childOnly(FamilyPrincipal? p, Future<void> Function() body) async {
    if (!_isThisChild(p)) return const RvResult.no('child_only');
    return _run(body);
  }

  Future<RvResult> _run(Future<void> Function() body) async {
    try {
      await body();
      return const RvResult.ok();
    } on RvRefused catch (e) {
      return RvResult.no(e.reason);
    } on LocalStoreFull {
      return const RvResult.no('full');
    } on LocalStoreException {
      return const RvResult.no('not_saved');
    }
  }

  // ---- reads that either side may do (guardian-authored content) ----
  Future<RhythmDoc> loadRhythm(FamilyPrincipal? p) async {
    if (!_isGuardian(p) && !_isThisChild(p)) throw const RvRefused('not_allowed');
    return rhythm.load();
  }

  Future<VoiceDoc> loadVoice(FamilyPrincipal? p) async {
    if (!_isGuardian(p) && !_isThisChild(p)) throw const RvRefused('not_allowed');
    return voice.load();
  }

  Future<PlacePlan?> loadPlace(FamilyPrincipal? p) async {
    if (!_isGuardian(p) && !_isThisChild(p)) throw const RvRefused('not_allowed');
    return place.load();
  }

  // ---- guardian writes: suite B ----
  Future<RvResult> setRhythmSuite(FamilyPrincipal? p, bool on) =>
      _guarded(p, () async => rhythm.save((await rhythm.load()).copyWith(suiteOn: on)));

  Future<RvResult> saveRoutine(FamilyPrincipal? p, Routine r) => _guarded(p, () async {
        final Routine? clean = Routine.tryFromJson(r.toJson());
        if (clean == null || clean.steps.length != r.steps.length) throw const RvRefused('bad_routine');
        final RhythmDoc d = await rhythm.load();
        await rhythm.save(d.copyWith(routine: clean, routineTicks: const DayTicks()));
      });

  Future<RvResult> clearRoutine(FamilyPrincipal? p) => _guarded(p, () async =>
      rhythm.save((await rhythm.load()).copyWith(clearRoutine: true, routineTicks: const DayTicks())));

  Future<RvResult> saveBoard(FamilyPrincipal? p, FirstThenBoard b) => _guarded(p, () async {
        if (FirstThenBoard.tryFromJson(b.toJson()) == null || b.first.picture == b.then.picture) {
          throw const RvRefused('bad_board');
        }
        await rhythm.save((await rhythm.load()).copyWith(board: b, boardState: const BoardState()));
      });

  Future<RvResult> clearBoard(FamilyPrincipal? p) => _guarded(p, () async =>
      rhythm.save((await rhythm.load()).copyWith(clearBoard: true, boardState: const BoardState())));

  Future<RvResult> savePacking(FamilyPrincipal? p, PackingList l) => _guarded(p, () async {
        final PackingList clean = PackingList.tryFromJson(l.toJson());
        if (clean.items.length != l.items.length || l.alwaysSame.length > maxSameItems) {
          throw const RvRefused('bad_list');
        }
        await rhythm.save((await rhythm.load()).copyWith(packing: clean));
      });

  /// A new bag: the guardian clears what she has packed.
  Future<RvResult> newBag(FamilyPrincipal? p) =>
      _guarded(p, () async => rhythm.save((await rhythm.load()).copyWith(packTicks: const PackTicks())));

  Future<RvResult> saveSensory(FamilyPrincipal? p, SensoryProfile s) =>
      _guarded(p, () async => rhythm.save((await rhythm.load()).copyWith(sensory: validateSensory(s))));

  Future<RvResult> savePlace(FamilyPrincipal? p, PlacePlan? plan) => _guarded(p, () async {
        if (plan != null) {
          final PlacePlan? clean = PlacePlan.tryFromJson(plan.toJson());
          if (clean == null || clean.stops.length != plan.stops.length || clean.plan.length != plan.plan.length) {
            throw const RvRefused('bad_plan');
          }
        }
        await place.save(plan);
      });

  // ---- guardian writes: suite C ----
  Future<RvResult> setVoiceSuite(FamilyPrincipal? p, bool on) =>
      _guarded(p, () async => voice.save((await voice.load()).copyWith(suiteOn: on)));

  Future<RvResult> saveHelpers(FamilyPrincipal? p, List<Helper> helpers) => _guarded(p, () async {
        await voice.save((await voice.load()).copyWith(helpers: checkedHelpers(helpers)));
      });

  Future<RvResult> savePersonalSymbols(FamilyPrincipal? p, List<String> ids) => _guarded(p, () async {
        await voice.save((await voice.load()).copyWith(personalSymbols: checkedPersonalSymbols(ids)));
      });

  // ---- child writes: suite B ticks ----
  /// Her routine as it stands today (stale ticks dropped).
  Future<({Routine? routine, DayTicks ticks})> routineToday(FamilyPrincipal? p) async {
    final RhythmDoc d = await loadRhythm(p);
    final Routine? r = d.routine;
    return (routine: r, ticks: r == null ? const DayTicks() : ticksFor(r, d.routineTicks, today()));
  }

  Future<RvResult> tickRoutine(FamilyPrincipal? p) => _childOnly(p, () async {
        final RhythmDoc d = await rhythm.load();
        final Routine? r = d.routine;
        if (r == null) throw const RvRefused('no_routine');
        await rhythm.save(d.copyWith(routineTicks: tickCurrent(r, d.routineTicks, today())));
      });

  Future<RvResult> routineAgain(FamilyPrincipal? p) =>
      _childOnly(p, () async => rhythm.save((await rhythm.load()).copyWith(routineTicks: startAgain(today()))));

  Future<BoardState> boardToday(FamilyPrincipal? p) async =>
      boardStateFor((await loadRhythm(p)).boardState, today());

  Future<RvResult> markBoardFirstDone(FamilyPrincipal? p) => _childOnly(p, () async {
        final RhythmDoc d = await rhythm.load();
        if (d.board == null) throw const RvRefused('no_board');
        await rhythm.save(d.copyWith(boardState: markFirstDone(d.boardState, today())));
      });

  Future<PackTicks> packedToday(FamilyPrincipal? p) async {
    final RhythmDoc d = await loadRhythm(p);
    return packTicksFor(d.packing, d.packTicks, today());
  }

  Future<RvResult> togglePack(FamilyPrincipal? p, String itemId) => _childOnly(p, () async {
        final RhythmDoc d = await rhythm.load();
        await rhythm.save(d.copyWith(packTicks: togglePacked(d.packing, d.packTicks, today(), itemId)));
      });

  // ---- child only: feelings weather (private; no guardian read exists) ----
  Future<FeelingToday?> weatherToday(FamilyPrincipal? p) async {
    if (!_isThisChild(p)) throw const RvRefused('child_only');
    return feelingForToday(await feelings.load(), today());
  }

  Future<RvResult> pickTodayWeather(FamilyPrincipal? p, String id) =>
      _childOnly(p, () async => feelings.save(pickWeather(id, today())));

  /// "Clear it": she can take her pick away. Nothing remains.
  Future<RvResult> forgetWeather(FamilyPrincipal? p) => _childOnly(p, () async => feelings.save(null));

  // ---- the worry box ----
  Future<List<Worry>> myWorries(FamilyPrincipal? p) async {
    if (!_isThisChild(p)) throw const RvRefused('child_only');
    return worries.load();
  }

  /// What a guardian may see: only what she chose to show. A child principal is
  /// refused here too: this is the grown-up's window, nothing else.
  Future<List<Worry>> worriesShownToGrownUp(FamilyPrincipal? p) async {
    if (!_isGuardian(p)) throw const RvRefused('guardian_only');
    return shownToGrownUp(await worries.load());
  }

  /// Puts a worry in. [ending] is what she chose: keep it (private), or show her
  /// grown-up. ("Let it float away" before it is ever put in simply puts nothing
  /// in: see [floatAwayWorry] for one already in the box.)
  Future<RvResult> putWorryPicture(FamilyPrincipal? p, String picture, {bool showGrownUp = false}) =>
      _childOnly(p, () async {
        final Worry w = Worry.picture(id: newId('w'), picture: picture, madeOn: today(), shown: showGrownUp);
        await worries.save(addWorry(await worries.load(), w));
      });

  Future<RvResult> putWorryDrawing(FamilyPrincipal? p, List<List<double>> strokes, {bool showGrownUp = false}) =>
      _childOnly(p, () async {
        final Worry w = Worry.drawing(id: newId('w'), strokes: strokes, madeOn: today(), shown: showGrownUp);
        await worries.save(addWorry(await worries.load(), w));
      });

  Future<RvResult> showWorryToGrownUp(FamilyPrincipal? p, String id, bool show) =>
      _childOnly(p, () async => worries.save(setWorryShown(await worries.load(), id, show)));

  Future<RvResult> floatAwayWorry(FamilyPrincipal? p, String id) =>
      _childOnly(p, () async => worries.save(floatAway(await worries.load(), id)));
}
