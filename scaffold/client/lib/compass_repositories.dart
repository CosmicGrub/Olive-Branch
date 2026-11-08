// OLIVE BRANCH — repositories, the suites shelf and the guarded service for suite
// I (Compass). No longer UNVERIFIED — verified by CI
// (client/test/compass_repositories_test.dart).
//
// One sealed area, `child.<id>.compass`, holds a guardian's answers and which of
// the two profiles are on. It is read and written by a GUARDIAN principal only:
// the child principal is refused every call (`guardian_only`), because these are
// a guardian's words about the family and there is no child-side screen that
// shows them. Nothing is sent anywhere.
//
// THE SHELF. [CompassService.shelf] reads each suite's OWN switch (Rhythm and
// Voice in rhythm_voice_repositories.dart, Village in village_repositories.dart,
// Growing and Care in growing_care_store.dart) through a [SuitePort]; it keeps no
// copy of the switches, so the shelf and each suite's own screen can never
// disagree. It shows on or off and what a suite adds to her home: never how much
// it has been used. A switch is changed only by a guardian.
//
// THE PROFILES. [CompassService.setProfile] records that a profile is on and, for
// "on", writes the profile's presentation defaults over the existing
// accessibility settings. Turning it off clears the flag and leaves the settings
// exactly where they are (the screen says so); it never reverts silently.
import 'dart:convert';

import 'access_settings.dart';
import 'compass_logic.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, Home, Person, canEditStructure;
import 'family_structure_store.dart' show localFamilyService;
import 'growing_care_logic.dart' show careSuiteKeys, growingSuiteKeys;
import 'growing_care_store.dart';
import 'local_services.dart';
import 'local_store.dart';
import 'rhythm_logic.dart' show RvRefused;
import 'rhythm_voice_repositories.dart';
import 'village_repositories.dart';

// ------------------------------------------------------------------- doc ----
class CompassDoc {
  const CompassDoc({this.answers = const CompassAnswers(), this.profiles = const <String>{}});
  final CompassAnswers answers;

  /// Ids from [profileKeys] that are on.
  final Set<String> profiles;

  CompassDoc copyWith({CompassAnswers? answers, Set<String>? profiles}) =>
      CompassDoc(answers: answers ?? this.answers, profiles: profiles ?? this.profiles);

  Map<String, Object?> toJson() => <String, Object?>{
        ...answers.toJson(),
        'profiles': <String>[for (final String k in profileKeys) if (profiles.contains(k)) k],
      };

  static CompassDoc fromJson(Object? j) {
    if (j is! Map) return const CompassDoc();
    final Object? p = j['profiles'];
    return CompassDoc(
        answers: CompassAnswers.fromJson(j),
        profiles: p is List ? <String>{for (final Object? x in p) if (x is String && profileKeys.contains(x)) x} : <String>{});
  }
}

abstract class CompassRepository {
  Future<CompassDoc> load();
  Future<void> save(CompassDoc d);
}

class MemoryCompassRepository implements CompassRepository {
  Object? _j;
  @override
  Future<CompassDoc> load() async => CompassDoc.fromJson(_j == null ? null : jsonDecode(jsonEncode(_j)));
  @override
  Future<void> save(CompassDoc d) async => _j = jsonDecode(jsonEncode(d.toJson()));
}

class LocalStoreCompassRepository implements CompassRepository {
  LocalStoreCompassRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<CompassDoc> load() async {
    try {
      return CompassDoc.fromJson(await _ns.get(_key));
    } catch (_) {
      return const CompassDoc();
    }
  }

  @override
  Future<void> save(CompassDoc d) => _ns.put(_key, d.toJson());
}

// ------------------------------------------------------------- the shelf ----
/// One suite's own on/off switch, as the suite itself keeps it.
abstract class SuitePort {
  Future<bool> isOn();
  Future<void> setOn(bool on);
}

class _FnPort implements SuitePort {
  _FnPort(this._get, this._set);
  final Future<bool> Function() _get;
  final Future<void> Function(bool) _set;
  @override
  Future<bool> isOn() => _get();
  @override
  Future<void> setOn(bool on) => _set(on);
}

/// What a suite adds to her home, in plain words, for the shelf.
class ShelfSuite {
  const ShelfSuite(this.key, this.title, this.adds);
  final String key;
  final String title;
  final String adds;
}

const List<ShelfSuite> shelfSuites = <ShelfSuite>[
  ShelfSuite('rhythm', 'Rhythm', 'One routine, first-then, my bag, a new place, how the app feels'),
  ShelfSuite('voice', 'Voice', 'The sky in me, worry box, my helpers, say it with pictures'),
  ShelfSuite('village', 'Village', 'Her people in pictures, a story you release, sibling shelf; sitter pass, school summary and grandparent page for you'),
  ShelfSuite('growing', 'Growing', 'Time capsule, first times, memory box, growing marks'),
  ShelfSuite('care', 'Care', 'Care binder, hospital mode, appointment lists, picture stories (grown-ups only)'),
];

/// A row on the shelf: on or off, and nothing about use.
class ShelfRow {
  const ShelfRow(this.suite, this.on);
  final ShelfSuite suite;
  final bool on;
}

/// The ports of the five suites for one child. Growing and Care are each a group
/// of four switches: the row is on when any is on, and a change sets all four.
Map<String, SuitePort> suitePortsFor(
    {required RhythmVoiceService rhythmVoice, required VillageService village, required GrowingCareStores growingCare,
    required FamilyPrincipal principal}) {
  SuitePort group(List<String> keys) => _FnPort(() async {
        final switches = await growingCare.switches.load();
        return keys.any(switches.on);
      }, (bool on) async {
        for (final String k in keys) {
          await growingCare.switches.setSuite(k, on);
        }
      });
  return <String, SuitePort>{
    'rhythm': _FnPort(() async => (await rhythmVoice.loadRhythm(principal)).suiteOn, (bool on) async {
      final RvResult r = await rhythmVoice.setRhythmSuite(principal, on);
      if (!r.ok) throw CompassRefused(r.reason);
    }),
    'voice': _FnPort(() async => (await rhythmVoice.loadVoice(principal)).suiteOn, (bool on) async {
      final RvResult r = await rhythmVoice.setVoiceSuite(principal, on);
      if (!r.ok) throw CompassRefused(r.reason);
    }),
    'village': _FnPort(() async => (await village.loadForGuardian(principal)).suiteOn, (bool on) async {
      final VillageResult r = await village.setSuite(principal, on);
      if (!r.ok) throw CompassRefused(r.reason);
    }),
    'growing': group(growingSuiteKeys),
    'care': group(careSuiteKeys),
  };
}

// --------------------------------------------------------------- service ----
class CompassResult {
  const CompassResult.ok() : ok = true, reason = '';
  const CompassResult.no(this.reason) : ok = false;
  final bool ok;
  final String reason;
}

class CompassService {
  CompassService({required this.childId, required this.repo, required this.access, this.ports = const <String, SuitePort>{}});

  factory CompassService.memory({
    String childId = 'demo-child', AccessRepository? access, Map<String, SuitePort> ports = const <String, SuitePort>{},
  }) =>
      CompassService(childId: childId, repo: MemoryCompassRepository(), access: access ?? MemoryAccessRepository(), ports: ports);

  /// Durable and sealed over [services], scoped to [childId]; [ports] are the
  /// five suites' own switches (see [suitePortsFor]).
  factory CompassService.local(LocalServices services, {String? childId, Map<String, SuitePort> ports = const <String, SuitePort>{}}) =>
      CompassService(
          childId: childId ?? services.childId, repo: LocalStoreCompassRepository(services.area('compass', ownerId: childId)),
          access: LocalStoreAccessRepository(services.area('access', ownerId: childId)), ports: ports);

  final String childId;
  final CompassRepository repo;
  final AccessRepository access;
  final Map<String, SuitePort> ports;

  bool _ok(FamilyPrincipal? p) => canEditStructure(p);

  Future<CompassResult> _run(Future<void> Function() body) async {
    try {
      await body();
      return const CompassResult.ok();
    } on CompassRefused catch (e) {
      return CompassResult.no(e.reason);
    } on LocalStoreFull {
      return const CompassResult.no('full');
    } on LocalStoreException {
      return const CompassResult.no('not_saved');
    }
  }

  Future<CompassDoc> load(FamilyPrincipal? p) async {
    if (!_ok(p)) throw const CompassRefused('guardian_only');
    return repo.load();
  }

  /// Saves the answers (an empty set is a complete answer).
  Future<CompassResult> saveAnswers(FamilyPrincipal? p, CompassAnswers a) async {
    if (!_ok(p)) return const CompassResult.no('guardian_only');
    return _run(() async => repo.save((await repo.load()).copyWith(answers: CompassAnswers.fromJson(a.toJson()))));
  }

  /// "Start again": forgets the answers (the profiles and suites are untouched).
  Future<CompassResult> forgetAnswers(FamilyPrincipal? p) async {
    if (!_ok(p)) return const CompassResult.no('guardian_only');
    return _run(() async => repo.save((await repo.load()).copyWith(answers: const CompassAnswers())));
  }

  /// The suggestions for what is saved. Pure on top of the stored answers.
  Future<List<Suggestion>> suggestions(FamilyPrincipal? p) async => suggest((await load(p)).answers);

  // ---- the shelf ----
  Future<List<ShelfRow>> shelf(FamilyPrincipal? p) async {
    if (!_ok(p)) throw const CompassRefused('guardian_only');
    final List<ShelfRow> rows = <ShelfRow>[];
    for (final ShelfSuite s in shelfSuites) {
      final SuitePort? port = ports[s.key];
      try {
        rows.add(ShelfRow(s, port == null ? true : await port.isOn()));
      } on RvRefused catch (e) {
        // A suite refused the read (the shelf was wired for the wrong principal): never guess "on".
        throw CompassRefused(e.reason);
      }
    }
    return rows;
  }

  Future<CompassResult> setSuite(FamilyPrincipal? p, String key, bool on) async {
    if (!_ok(p)) return const CompassResult.no('guardian_only');
    final SuitePort? port = ports[key];
    if (port == null || !suiteKeysOnShelf.contains(key)) return const CompassResult.no('unknown_suite');
    return _run(() => port.setOn(on));
  }

  // ---- the profiles ----
  Future<bool> profileOn(FamilyPrincipal? p, String id) async => (await load(p)).profiles.contains(id);

  Future<CompassResult> setProfile(FamilyPrincipal? p, String id, bool on) async {
    if (!_ok(p)) return const CompassResult.no('guardian_only');
    final ProfileDefaults? def = profileById(id);
    if (def == null) return const CompassResult.no('unknown_profile');
    return _run(() async {
      final CompassDoc d = await repo.load();
      if (on) await access.save(applyProfileTo(await access.load(), def));
      final Set<String> next = <String>{...d.profiles};
      on ? next.add(id) : next.remove(id);
      await repo.save(d.copyWith(profiles: next));
    });
  }
}

/// A refusal to read: Compass has no child-side reader.
class CompassRefused implements Exception {
  const CompassRefused(this.reason);
  final String reason;
  @override
  String toString() => 'CompassRefused($reason)';
}

/// What the family builder already holds, as Compass answer ids (a quiet hint
/// beside the question, never ticked for her). Reads only counts: how many homes
/// she sleeps in and whether anyone is marked away. A guardian-only read.
Future<List<String>> builderHintsFor(FamilyPrincipal principal, int yearsOld) async {
  final o = await localFamilyService.overview(principal, yearsOld: yearsOld);
  return builderHints(
      sleepingHomes: o.intended.homes.where((Home h) => h.childSleeps).length,
      someoneAway: o.intended.people.any((Person p) => p.isAwayFlag));
}
