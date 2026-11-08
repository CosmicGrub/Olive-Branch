// OLIVE BRANCH — suites G (Growing) and F (Care): repositories.
// No longer UNVERIFIED — verified by CI (client/test/growing_care_store_test.dart).
// MASTERFILE section 8.17.
//
// The repository pattern, as everywhere else on this device: an abstract
// interface ([ItemRepository]), an in-memory implementation for tests and the
// preview ([MemoryItemRepository]) and a LocalStore-backed one for the app
// ([LocalItemRepository]), namespaced per child. Four catalogued areas, ALL
// sealed (AES-256-GCM) because every one of them is private:
//   growing     time capsules, first times, pencil marks, the suite switches
//   memorybox   what she chose to keep
//   care        care binder sections and contacts, hospital notes, appointment prep
//   explainers  picture stories a guardian wrote
// See localDataCatalogue in local_services.dart for the plain-words entries.
//
// RULES HELD HERE, not left to screens:
//  - A write that breaks a bound (text length, photo size, count, item size)
//    or a rule (a capsule's date is in the past) is REFUSED with a [CareRefused]
//    reason, and the stored data is untouched.
//  - A full namespace refuses with 'full'; nothing is ever silently evicted.
//  - The child's side gets NARROWER types: [ChildGrowingLens] (opened letters,
//    firsts a guardian chose to show, her growth picture with no numbers) and
//    [ChildExplainerReader] (stories a guardian chose to show, read-only). No
//    child type can reach the care binder, hospital notes or appointment prep.
import 'dart:convert';

import 'dart:typed_data';

import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'growing_care_logic.dart';
import 'local_services.dart';
import 'local_store.dart';

final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// How one kind of item is keyed, bounded and decoded.
class ItemKind<T extends StoredItem> {
  const ItemKind(this.prefix, this.maxItems, this.fromJson);

  /// Key prefix inside the namespace, e.g. 'cap.'. A prefix without a dot is a
  /// singleton: one document under exactly that key.
  final String prefix;
  final int maxItems;
  final T? Function(Map<String, Object?> json) fromJson;
}

const ItemKind<TimeCapsule> capsuleKind = ItemKind<TimeCapsule>('cap.', maxCapsules, TimeCapsule.fromJson);
const ItemKind<FirstTime> firstKind = ItemKind<FirstTime>('first.', maxFirsts, FirstTime.fromJson);
const ItemKind<PencilMark> markKind = ItemKind<PencilMark>('mark.', maxPencilMarks, PencilMark.fromJson);
const ItemKind<SuiteSwitches> switchKind = ItemKind<SuiteSwitches>('switches', 1, SuiteSwitches.fromJson);
const ItemKind<MemoryItem> memoryKind = ItemKind<MemoryItem>('mem.', maxMemoryItems, MemoryItem.fromJson);
const ItemKind<GrownUpMemory> grownUpMemoryKind =
    ItemKind<GrownUpMemory>('gift.', maxGrownUpMemories, GrownUpMemory.fromJson);
const ItemKind<CareSection> sectionKind = ItemKind<CareSection>('sec.', maxCareSections, CareSection.fromJson);
const ItemKind<CareContact> contactKind = ItemKind<CareContact>('con.', maxCareContacts, CareContact.fromJson);
const ItemKind<HospitalNotes> hospitalKind = ItemKind<HospitalNotes>('hospital', 1, HospitalNotes.fromJson);
const ItemKind<AppointmentPrep> prepKind = ItemKind<AppointmentPrep>('prep.', maxPreps, AppointmentPrep.fromJson);
const ItemKind<ExplainerStory> storyKind = ItemKind<ExplainerStory>('story.', maxExplainers, ExplainerStory.fromJson);

String _keyFor(String prefix, String id) => prefix.endsWith('.') ? '$prefix$id' : prefix;

/// Throws [CareRefused] when [item] may not be stored.
void _validate<T extends StoredItem>(ItemKind<T> kind, T item, {required bool exists, required int count}) {
  if (!_idRe.hasMatch(item.id)) throw const CareRefused('invalid');
  final String? why = item.check();
  if (why != null) throw CareRefused(why);
  if (utf8.encode(jsonEncode(item.toJson())).length > maxItemBytes) throw const CareRefused('too_big');
  if (!exists && count >= kind.maxItems) throw const CareRefused('too_many');
}

abstract class ItemRepository<T extends StoredItem> {
  ItemKind<T> get kind;

  /// Everything of this kind that decodes. An undecodable document is skipped.
  Future<List<T>> list();

  /// Stores [item] (replacing the same id). Throws [CareRefused].
  Future<void> save(T item);

  /// Removes one item. Removing an absent id is a no-op.
  Future<void> remove(String id);

  Future<T?> get(String id) async {
    for (final T t in await list()) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Held as JSON so a handed-out item can never alias the stored one, and so
/// swapping to the durable store changes nothing about what an item can hold.
class MemoryItemRepository<T extends StoredItem> extends ItemRepository<T> {
  MemoryItemRepository(this.kind);
  @override
  final ItemKind<T> kind;
  final Map<String, String> _docs = <String, String>{};

  @override
  Future<List<T>> list() async {
    final List<String> keys = _docs.keys.toList()..sort();
    final List<T> out = <T>[];
    for (final String k in keys) {
      final Object? j = jsonDecode(_docs[k]!);
      if (j is! Map) continue;
      final T? item = kind.fromJson(Map<String, Object?>.from(j));
      if (item != null) out.add(item);
    }
    return out;
  }

  @override
  Future<void> save(T item) async {
    final String key = _keyFor(kind.prefix, item.id);
    _validate(kind, item, exists: _docs.containsKey(key), count: _docs.length);
    _docs[key] = jsonEncode(item.toJson());
  }

  @override
  Future<void> remove(String id) async => _docs.remove(_keyFor(kind.prefix, id));
}

/// One key per item inside a (sealed) LocalStore namespace.
class LocalItemRepository<T extends StoredItem> extends ItemRepository<T> {
  LocalItemRepository(this._ns, this.kind);
  final LocalNamespace _ns;
  @override
  final ItemKind<T> kind;

  /// The namespace this repository writes (for tests).
  String get namespaceName => _ns.spec.name;

  Future<List<String>> _keys() async =>
      <String>[for (final String k in await _ns.list()) if (k.startsWith(kind.prefix)) k];

  @override
  Future<List<T>> list() async {
    final List<T> out = <T>[];
    for (final String k in await _keys()) {
      final Object? raw = await _ns.get(k);
      if (raw is! Map) continue;
      try {
        final T? item = kind.fromJson(Map<String, Object?>.from(raw));
        if (item != null) out.add(item);
      } catch (_) {
        // a damaged item is skipped, never fatal
      }
    }
    return out;
  }

  @override
  Future<void> save(T item) async {
    final List<String> keys = await _keys();
    final String key = _keyFor(kind.prefix, item.id);
    _validate(kind, item, exists: keys.contains(key), count: keys.length);
    try {
      await _ns.put(key, item.toJson());
    } on LocalStoreFull {
      throw const CareRefused('full');
    }
  }

  @override
  Future<void> remove(String id) => _ns.delete(_keyFor(kind.prefix, id));
}

// ==================================================================== switches
extension SuiteSwitchStore on ItemRepository<SuiteSwitches> {
  Future<SuiteSwitches> load() async => await get(SuiteSwitches.itemId) ?? const SuiteSwitches();
  Future<SuiteSwitches> setSuite(String suite, bool on) async {
    final SuiteSwitches next = (await load()).withSuite(suite, on);
    await save(next);
    return next;
  }
}

// ================================================================== the bundle
/// Every repository the screens use, for one child on this device.
class GrowingCareStores {
  GrowingCareStores({
    required this.capsules, required this.firsts, required this.marks, required this.switches,
    required this.memories, required this.sections, required this.contacts, required this.hospital,
    required this.preps, required this.stories, required this.grownUpMemories,
  });

  /// All in memory (tests, the preview before a store boots).
  factory GrowingCareStores.memory() => GrowingCareStores(
      capsules: MemoryItemRepository<TimeCapsule>(capsuleKind),
      firsts: MemoryItemRepository<FirstTime>(firstKind),
      marks: MemoryItemRepository<PencilMark>(markKind),
      switches: MemoryItemRepository<SuiteSwitches>(switchKind),
      memories: MemoryItemRepository<MemoryItem>(memoryKind),
      sections: MemoryItemRepository<CareSection>(sectionKind),
      contacts: MemoryItemRepository<CareContact>(contactKind),
      hospital: MemoryItemRepository<HospitalNotes>(hospitalKind),
      preps: MemoryItemRepository<AppointmentPrep>(prepKind),
      stories: MemoryItemRepository<ExplainerStory>(storyKind),
      grownUpMemories: MemoryItemRepository<GrownUpMemory>(grownUpMemoryKind));

  /// Durable and sealed: the namespaces of [services] (default
  /// [LocalServices.current]) for [childId] (default: its child).
  factory GrowingCareStores.forChild({String? childId, LocalServices? services}) {
    final LocalServices s = services ?? LocalServices.current;
    final LocalNamespace growing = s.area('growing', ownerId: childId);
    final LocalNamespace box = s.area('memorybox', ownerId: childId);
    final LocalNamespace care = s.area('care', ownerId: childId);
    final LocalNamespace tales = s.area('explainers', ownerId: childId);
    return GrowingCareStores(
        capsules: LocalItemRepository<TimeCapsule>(growing, capsuleKind),
        firsts: LocalItemRepository<FirstTime>(growing, firstKind),
        marks: LocalItemRepository<PencilMark>(growing, markKind),
        switches: LocalItemRepository<SuiteSwitches>(growing, switchKind),
        memories: LocalItemRepository<MemoryItem>(box, memoryKind),
        sections: LocalItemRepository<CareSection>(care, sectionKind),
        contacts: LocalItemRepository<CareContact>(care, contactKind),
        hospital: LocalItemRepository<HospitalNotes>(care, hospitalKind),
        preps: LocalItemRepository<AppointmentPrep>(care, prepKind),
        stories: LocalItemRepository<ExplainerStory>(tales, storyKind),
        grownUpMemories: LocalItemRepository<GrownUpMemory>(box, grownUpMemoryKind));
  }

  final ItemRepository<TimeCapsule> capsules;
  final ItemRepository<FirstTime> firsts;
  final ItemRepository<PencilMark> marks;
  final ItemRepository<SuiteSwitches> switches;
  final ItemRepository<MemoryItem> memories;
  final ItemRepository<CareSection> sections;
  final ItemRepository<CareContact> contacts;
  final ItemRepository<HospitalNotes> hospital;
  final ItemRepository<AppointmentPrep> preps;
  final ItemRepository<ExplainerStory> stories;

  /// Things a grown-up left in her memory box. Same sealed namespace as [memories]
  /// but a different key prefix, so the two are never mixed.
  final ItemRepository<GrownUpMemory> grownUpMemories;

  /// The narrow, read-only lens her own app gets. It has no way to reach
  /// [sections], [contacts], [hospital] or [preps].
  ChildGrowingLens childLens({DateTime Function()? now}) =>
      ChildGrowingLens(capsules, firsts, marks, now ?? DateTime.now);

  ChildExplainerReader childExplainers() => RepositoryExplainerReader(stories);
}

// ===================================================== grown-up memory desk =====
/// The ONLY door a guardian has into her memory box, and it opens onto the
/// grown-up's own section alone. It holds no reference to her items
/// ([GrowingCareStores.memories]), so a guardian can neither edit nor delete
/// anything she kept: that is true by construction, not by a check.
///
/// A child principal is refused ('guardian_only') for every call here.
class GrownUpMemoryDesk {
  GrownUpMemoryDesk(this._repo, {DateTime Function()? now, IdMaker? ids})
      : _now = now ?? DateTime.now,
        _ids = ids ?? IdMaker(now);
  final ItemRepository<GrownUpMemory> _repo;
  final DateTime Function() _now;
  final IdMaker _ids;

  bool _ok(FamilyPrincipal? p) => canEditStructure(p);

  /// Newest first. Guardian only.
  Future<List<GrownUpMemory>> list(FamilyPrincipal? p) async {
    if (!_ok(p)) throw const CareRefused('guardian_only');
    return _sorted(await _repo.list());
  }

  /// Leaves a note and/or a small photo, marked as from [fromName]. Throws
  /// [CareRefused] (a bound, 'empty', 'full', 'guardian_only').
  Future<GrownUpMemory> add(FamilyPrincipal? p, {required String fromName, String note = '', Uint8List? photo}) async {
    if (!_ok(p)) throw const CareRefused('guardian_only');
    // A new id that no earlier one shares (two desks, or a clock that has not moved, cannot overwrite).
    final Set<String> taken = <String>{for (final GrownUpMemory e in await _repo.list()) e.id};
    String id = _ids.next('g');
    while (taken.contains(id)) {
      id = _ids.next('g');
    }
    final GrownUpMemory m = GrownUpMemory(
        id: id, addedOn: isoOf(_now()), fromName: fromName.trim(), note: note.trim(), thumb: photo);
    await _repo.save(m);
    return m;
  }

  /// Takes back something a grown-up left. Only the grown-up section exists
  /// here, so nothing of hers can be reached by id.
  Future<void> remove(FamilyPrincipal? p, String id) async {
    if (!_ok(p)) throw const CareRefused('guardian_only');
    await _repo.remove(id);
  }
}

List<GrownUpMemory> _sorted(List<GrownUpMemory> l) =>
    l..sort((GrownUpMemory a, GrownUpMemory b) {
      final int c = b.addedOn.compareTo(a.addedOn);
      return c != 0 ? c : b.id.compareTo(a.id);
    });

/// What her memory box may read of the grown-up section: read-only, newest
/// first. There is no write on this type.
class ChildGrownUpMemoryReader {
  ChildGrownUpMemoryReader(this._repo);
  final ItemRepository<GrownUpMemory> _repo;
  Future<List<GrownUpMemory>> all() async => _sorted(await _repo.list());
}

// ============================================================== child lens ====
/// What her app may read of the growing suite. Read-only by construction.
class ChildGrowingLens {
  /// Positional and private on purpose: nothing outside can pull a writable
  /// repository back out of the lens.
  ChildGrowingLens(this._capsules, this._firsts, this._marks, this._now);
  final ItemRepository<TimeCapsule> _capsules;
  final ItemRepository<FirstTime> _firsts;
  final ItemRepository<PencilMark> _marks;
  final DateTime Function() _now;

  String get today => isoOf(_now());

  /// Letters whose day has come (or that a guardian unsealed). A sealed one is
  /// not returned at all: no title, no date, no countdown. Newest opening first.
  Future<List<TimeCapsule>> openedLetters() async {
    final String t = today;
    return <TimeCapsule>[for (final TimeCapsule c in await _capsules.list()) if (c.isOpen(t)) c]
      ..sort((TimeCapsule a, TimeCapsule b) => b.opensOn.compareTo(a.opensOn));
  }

  /// Only the firsts a guardian chose to show her, newest first. No total.
  Future<List<FirstTime>> shownFirsts() async =>
      firstsNewestFirst(<FirstTime>[for (final FirstTime f in await _firsts.list()) if (f.showHer) f]);

  /// Her doorframe: month labels and heights against her own other marks.
  /// No number, no percentile, no comparison.
  Future<List<GrowthMarkView>> growth() async => growthPicture(await _marks.list());
}

abstract class ChildExplainerReader {
  /// Only the stories a guardian chose to show her. Read-only: no write exists.
  Future<List<ExplainerStory>> shown();
}

class RepositoryExplainerReader implements ChildExplainerReader {
  RepositoryExplainerReader(this._repo);
  final ItemRepository<ExplainerStory> _repo;
  @override
  Future<List<ExplainerStory>> shown() async => <ExplainerStory>[
        for (final ExplainerStory s in await _repo.list()) if (s.shownToHer) s,
      ]..sort((ExplainerStory a, ExplainerStory b) => a.title.compareTo(b.title));
}

/// An id for a new item: prefix + microseconds + a sequence number.
class IdMaker {
  IdMaker([DateTime Function()? now]) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  int _n = 0;
  String next(String prefix) => '$prefix${_now().microsecondsSinceEpoch}_${_n++}';
}
