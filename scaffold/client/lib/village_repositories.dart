// OLIVE BRANCH — repositories and the guarded service for suite D (Village). No
// longer UNVERIFIED — verified by CI (client/test/village_repositories_test.dart).
//
// THE PATTERN (as rhythm_voice_repositories.dart): an ABSTRACT repository per
// document, an in-memory implementation for tests and the preview, and a
// LocalStore-backed one for the app, over ONE namespace each, named per child by
// LocalServices (`child.<id>.<area>`). Both areas are SEALED (AES-256-GCM): they
// hold a family's private words (a story, allergies, phone numbers).
//
//   village  grandparent corner, welcome stories, sibling shelf, faces, the suite switch
//   passes   the sitter pass and the school bridge (guardian side only)
//
// A failed save THROWS (a full box, an unwritable disk) so the service can say so:
// a guardian is never told something was saved when it was not.
//
// [VillageService] is where WHO may do WHAT is enforced, in code and not only in
// the UI:
//  - a guardian principal writes everything and reads everything;
//  - the child principal (and only this child's id) reads a NARROW part: the
//    stories a guardian released, her siblings' names and pictures, the faces a
//    guardian picked; and she leaves and takes down a picture on the shelf;
//  - NO child principal can read, write or even list the passes: the sitter pass
//    and the school bridge have no child-side reader at all (`guardian_only`);
//  - with the suite switched off, the child side reads nothing.
import 'dart:convert';

import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'local_services.dart';
import 'local_store.dart';
import 'picture_library.dart' show isPictureIn;
import 'rhythm_logic.dart';
import 'village_logic.dart';

// ------------------------------------------------------------ abstractions ---
abstract class VillageRepository {
  Future<VillageDoc> load();
  Future<void> save(VillageDoc d);
}

abstract class PassesRepository {
  Future<PassesDoc> load();
  Future<void> save(PassesDoc d);
}

// ------------------------------------------------------------- in memory -----
// Held as JSON so a value handed out can never alias the stored one.
Object? _clone(Object? j) => j == null ? null : jsonDecode(jsonEncode(j));

class MemoryVillageRepository implements VillageRepository {
  Object? _j;
  @override
  Future<VillageDoc> load() async => VillageDoc.fromJson(_clone(_j));
  @override
  Future<void> save(VillageDoc d) async => _j = _clone(d.toJson());
}

class MemoryPassesRepository implements PassesRepository {
  Object? _j;
  @override
  Future<PassesDoc> load() async => PassesDoc.fromJson(_clone(_j));
  @override
  Future<void> save(PassesDoc d) async => _j = _clone(d.toJson());
}

// ------------------------------------------------------- LocalStore backed ---
/// A read failure is "nothing there", so a damaged file never stops the shell
/// (LocalStore has already quarantined it).
Future<Object?> _read(LocalNamespace ns, String key) async {
  try {
    return await ns.get(key);
  } catch (_) {
    return null;
  }
}

class LocalStoreVillageRepository implements VillageRepository {
  LocalStoreVillageRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<VillageDoc> load() async => VillageDoc.fromJson(await _read(_ns, _key));
  @override
  Future<void> save(VillageDoc d) => _ns.put(_key, d.toJson());
}

class LocalStorePassesRepository implements PassesRepository {
  LocalStorePassesRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<PassesDoc> load() async => PassesDoc.fromJson(await _read(_ns, _key));
  @override
  Future<void> save(PassesDoc d) => _ns.put(_key, d.toJson());
}

// ---------------------------------------------------------------- service ----
/// The result of a write: ok, or a short stable [reason] a screen words gently.
class VillageResult {
  const VillageResult.ok() : ok = true, reason = '';
  const VillageResult.no(this.reason) : ok = false;
  final bool ok;
  final String reason;
  @override
  String toString() => ok ? 'VillageResult.ok' : 'VillageResult.no($reason)';
}

/// What her side may know of the shelf: names and pictures, and the pictures
/// left for each sibling. No author, no time, no total.
class ChildShelfView {
  const ChildShelfView(this.siblings, this.notes);
  final List<SiblingSlot> siblings;
  final List<ShelfNote> notes;
  List<ShelfNote> notesFor(String id) => <ShelfNote>[for (final ShelfNote n in notes) if (n.toId == id) n];
}

class VillageService {
  VillageService({required this.childId, required this.village, required this.passes, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// An in-memory service (tests, and the preview before a store is wired).
  factory VillageService.memory({String childId = 'demo-child', DateTime Function()? clock}) =>
      VillageService(childId: childId, clock: clock, village: MemoryVillageRepository(), passes: MemoryPassesRepository());

  /// The durable, sealed service over [services]' LocalStore, scoped to [childId].
  factory VillageService.local(LocalServices services, {String? childId, DateTime Function()? clock}) =>
      VillageService(
        childId: childId ?? services.childId, clock: clock,
        village: LocalStoreVillageRepository(services.area('village', ownerId: childId)),
        passes: LocalStorePassesRepository(services.area('passes', ownerId: childId)),
      );

  static VillageService? _shared;
  static String? _sharedFor;

  /// The one shared instance the shells use, bound to [LocalServices.current].
  static VillageService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    final String key = '${identityHashCode(s)}:${childId ?? s.childId}';
    if (_shared == null || _sharedFor != key) {
      _shared = VillageService.local(s, childId: childId);
      _sharedFor = key;
    }
    return _shared!;
  }

  static void resetShared() {
    _shared = null;
    _sharedFor = null;
  }

  final String childId;
  final VillageRepository village;
  final PassesRepository passes;
  final DateTime Function() _clock;
  int _ids = 0;

  String today() => isoDayOf(_clock());
  String newId(String prefix) => '$prefix${_clock().microsecondsSinceEpoch}_${_ids++}';

  // ---- who ----
  bool _isGuardian(FamilyPrincipal? p) => canEditStructure(p);
  bool _isThisChild(FamilyPrincipal? p) =>
      p != null && p.roleName == 'child' && p.childId is String && p.childId == childId;

  Future<VillageResult> _guarded(FamilyPrincipal? p, Future<void> Function() body) async {
    if (!_isGuardian(p)) return const VillageResult.no('guardian_only');
    return _run(body);
  }

  Future<VillageResult> _childOnly(FamilyPrincipal? p, Future<void> Function() body) async {
    if (!_isThisChild(p)) return const VillageResult.no('child_only');
    return _run(body);
  }

  Future<VillageResult> _run(Future<void> Function() body) async {
    try {
      await body();
      return const VillageResult.ok();
    } on RvRefused catch (e) {
      return VillageResult.no(e.reason);
    } on LocalStoreFull {
      return const VillageResult.no('full');
    } on LocalStoreException {
      return const VillageResult.no('not_saved');
    }
  }

  // ---- guardian reads ----
  /// Everything a guardian wrote, held stories included.
  Future<VillageDoc> loadForGuardian(FamilyPrincipal? p) async {
    if (!_isGuardian(p)) throw const RvRefused('guardian_only');
    return village.load();
  }

  /// The sitter pass and the school bridge. A child principal is refused.
  Future<PassesDoc> loadPasses(FamilyPrincipal? p) async {
    if (!_isGuardian(p)) throw const RvRefused('guardian_only');
    return passes.load();
  }

  // ---- guardian writes ----
  Future<VillageResult> setSuite(FamilyPrincipal? p, bool on) =>
      _guarded(p, () async => village.save((await village.load()).copyWith(suiteOn: on)));

  Future<VillageResult> saveGrandCorner(FamilyPrincipal? p, GrandCorner? c) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        if (c == null) return village.save(d.copyWith(clearGrand: true));
        final GrandCorner clean = makeGrandCorner(name: c.name, cards: c.cards, phone: c.phone);
        await village.save(d.copyWith(grand: clean));
      });

  /// Adds a new story or replaces the one with the same id. A replaced story
  /// goes back to HELD: a changed story is never still "released".
  Future<VillageResult> saveStory(FamilyPrincipal? p, WelcomeStory s) => _guarded(p, () async {
        final WelcomeStory clean = makeStory(id: s.id, title: s.title, pages: s.pages);
        final VillageDoc d = await village.load();
        final bool exists = d.stories.any((WelcomeStory x) => x.id == clean.id);
        if (!exists && d.stories.length >= maxWelcomeStories) throw const RvRefused('too_many_stories');
        await village.save(d.copyWith(stories: <WelcomeStory>[
          for (final WelcomeStory x in d.stories) x.id == clean.id ? clean : x,
          if (!exists) clean,
        ]));
      });

  Future<VillageResult> removeStory(FamilyPrincipal? p, String id) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        await village.save(d.copyWith(stories: <WelcomeStory>[for (final WelcomeStory x in d.stories) if (x.id != id) x]));
      });

  /// The guardian's own choice to show her a story. Nothing releases one by itself.
  Future<VillageResult> releaseStory(FamilyPrincipal? p, String id) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        if (!d.stories.any((WelcomeStory x) => x.id == id)) throw const RvRefused('unknown_story');
        await village.save(d.copyWith(stories: <WelcomeStory>[
          for (final WelcomeStory x in d.stories) x.id == id ? x.copyWith(releasedOn: today()) : x,
        ]));
      });

  /// Takes it back out of her sight.
  Future<VillageResult> holdStory(FamilyPrincipal? p, String id) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        if (!d.stories.any((WelcomeStory x) => x.id == id)) throw const RvRefused('unknown_story');
        await village.save(d.copyWith(stories: <WelcomeStory>[
          for (final WelcomeStory x in d.stories) x.id == id ? x.copyWith(hold: true) : x,
        ]));
      });

  Future<VillageResult> saveSiblings(FamilyPrincipal? p, List<SiblingSlot> siblings) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        await village.save(d.copyWith(shelf: withSiblings(d.shelf, siblings)));
      });

  Future<VillageResult> clearShelfPictures(FamilyPrincipal? p) => _guarded(p, () async {
        final VillageDoc d = await village.load();
        await village.save(d.copyWith(shelf: clearNotes(d.shelf)));
      });

  /// Chooses the face she sees for [personId] (an id from the family builder);
  /// null puts back the plain initial.
  Future<VillageResult> setFace(FamilyPrincipal? p, String personId, String? picture) => _guarded(p, () async {
        if (!isIdLike(personId)) throw const RvRefused('bad_id');
        final VillageDoc d = await village.load();
        final Map<String, String> faces = <String, String>{...d.faces};
        if (picture == null) {
          faces.remove(personId);
        } else {
          if (!isPictureIn(picture, facePictures)) throw const RvRefused('bad_picture');
          if (!faces.containsKey(personId) && faces.length >= maxFaces) throw const RvRefused('too_many_faces');
          faces[personId] = picture;
        }
        await village.save(d.copyWith(faces: faces));
      });

  Future<VillageResult> saveSitterPass(FamilyPrincipal? p, SitterPass? pass) => _guarded(p, () async {
        final PassesDoc d = await passes.load();
        if (pass == null) return passes.save(d.copyWith(clearSitter: true));
        final SitterPass clean = makeSitterPass(
            title: pass.title, forWho: pass.forWho, when: pass.when, routine: pass.routine,
            allergies: pass.allergies, notes: pass.notes, contacts: pass.contacts).copyWith(writtenOn: today());
        await passes.save(d.copyWith(sitter: clean));
      });

  Future<VillageResult> saveSchoolBridge(FamilyPrincipal? p, SchoolBridge? bridge) => _guarded(p, () async {
        final PassesDoc d = await passes.load();
        if (bridge == null) return passes.save(d.copyWith(clearSchool: true));
        final SchoolBridge clean = makeSchoolBridge(
            school: bridge.school, className: bridge.className, helps: bridge.helps, allergies: bridge.allergies,
            pickup: bridge.pickup, notes: bridge.notes, contacts: bridge.contacts).copyWith(writtenOn: today());
        await passes.save(d.copyWith(school: clean));
      });

  // ---- the child's narrow side ----
  Future<VillageDoc?> _forChild(FamilyPrincipal? p) async {
    if (!_isThisChild(p)) throw const RvRefused('child_only');
    final VillageDoc d = await village.load();
    return d.suiteOn ? d : null;
  }

  /// Whether the suite is on, read by her side so a tile never flashes. A
  /// guardian-or-child question; nothing private is returned.
  Future<bool> suiteOn(FamilyPrincipal? p) async {
    if (!_isGuardian(p) && !_isThisChild(p)) throw const RvRefused('not_allowed');
    return (await village.load()).suiteOn;
  }

  /// Only stories a guardian released, as written. A held story is never returned.
  Future<List<WelcomeStory>> releasedStories(FamilyPrincipal? p) async {
    final VillageDoc? d = await _forChild(p);
    return d == null ? const <WelcomeStory>[] : <WelcomeStory>[for (final WelcomeStory s in d.stories) if (s.released) s];
  }

  /// The faces a guardian picked, by person id.
  Future<Map<String, String>> faces(FamilyPrincipal? p) async => (await _forChild(p))?.faces ?? const <String, String>{};

  Future<ChildShelfView> shelf(FamilyPrincipal? p) async {
    final VillageDoc? d = await _forChild(p);
    return d == null ? const ChildShelfView(<SiblingSlot>[], <ShelfNote>[]) : ChildShelfView(d.shelf.siblings, d.shelf.notes);
  }

  Future<VillageResult> leavePicture(FamilyPrincipal? p, String toId, String picture) => _childOnly(p, () async {
        final VillageDoc d = await village.load();
        if (!d.suiteOn) throw const RvRefused('suite_off');
        final ShelfNote n = ShelfNote(id: newId('n'), toId: toId, picture: picture);
        await village.save(d.copyWith(shelf: leaveNote(d.shelf, n)));
      });

  Future<VillageResult> takeDownPicture(FamilyPrincipal? p, String noteId) => _childOnly(p, () async {
        final VillageDoc d = await village.load();
        if (!d.suiteOn) throw const RvRefused('suite_off');
        await village.save(d.copyWith(shelf: takeDownNote(d.shelf, noteId)));
      });
}
