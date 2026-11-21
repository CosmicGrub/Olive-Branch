// OLIVE BRANCH — the on-device snapshot: a plain, consistent copy of every area a family backup may carry, a way to put
// one back that can never lose or overwrite anything, and the digest that proves a restore gave back what was there.
// UNVERIFIED on a device; pure Dart, runs headless in CI. Built for the data-loss harness (client/test/dataloss) and
// as the ground the recovery work stands on: it is NOT reachable from any screen yet, and it does no encryption, no
// upload and no waiting period (the family backup seals this on the phone before it leaves; that is a separate lane).
//
// WHAT A SNAPSHOT IS. For each area the family backup carries, the namespace name, its schema and its whole document as
// plain JSON, read under that namespace's own lock, so a write in flight is wholly in or wholly out and never half.
// Private areas are sealed ON the device by their own key; a snapshot holds them as plain data because the backup that
// carries it is sealed again before it leaves and a new phone has a new key (restore seals them under that key).
//
// WHAT IT LEAVES OUT, BY RULE ([kBackupClass], one row per catalogued area, a test fails when a new area has no row):
//  - the child's private areas (journal, worries, feelings, teen, her marks, her memory box): no grown-up key opens
//    them, so the family backup does not carry them (owner rule);
//  - what belongs to one device only (its signing key, its pairing certificate, its PIN hash, its role, its account
//    state, the child devices it approved): a copy of a device key on a second phone would be two phones that are one.
//  Each left-out area is LISTED in [LocalSnapshot.leftOut] with its reason, so "not in the backup" is something a screen
//  can say plainly, never something that silently went missing.
//
// RESTORE NEVER DELETES AND NEVER OVERWRITES ([restoreSnapshot]). It adds what this phone does not hold, one atomic write
// per area. A key this phone already holds with a different value keeps this phone's value, and the snapshot's value is
// first written to the store's quarantine (kept, never deleted). Two areas keep their whole record under ONE key (the
// sealed family record, and the waiting-to-send list); for those the two copies are JOINED, never one-or-the-other
// ([joinValue]), so a backup restored onto a phone that has already caught up still brings back everything the backup
// held and everything the phone held. A kill between any two steps leaves each area either
// as it was or complete; running the restore again finishes it, and running it twice changes nothing more.
// A snapshot is checked whole before anything is written; a hostile or damaged one cannot plant a device key or a
// child's private area, and one bad area never blocks the others.
import 'dart:convert';
import 'dart:typed_data';

import 'local_services.dart';
import 'local_store.dart';
import 'sha256.dart';

/// Where an area stands for the family backup.
enum BackupClass { family, childPrivate, deviceBound }

/// One row per catalogued area. The reasons are in the file header and in the catalogue's own words for each area.
const Map<String, BackupClass> kBackupClass = <String, BackupClass>{
  // The child's private areas: hers, sealed with no grown-up key.
  'journal': BackupClass.childPrivate,
  'worries': BackupClass.childPrivate,
  'feelings': BackupClass.childPrivate,
  'teen': BackupClass.childPrivate,
  'mymarks': BackupClass.childPrivate,
  'memorybox': BackupClass.childPrivate,
  // Belongs to this one device.
  'devicekey': BackupClass.deviceBound,
  'childpairing': BackupClass.deviceBound,
  'adultunlock': BackupClass.deviceBound,
  'localpin': BackupClass.deviceBound,
  'role': BackupClass.deviceBound,
  'account': BackupClass.deviceBound,
  'pairedkids': BackupClass.deviceBound,
  'trust': BackupClass.deviceBound,
  // Everything else the family would be sorry to lose.
  'lists': BackupClass.family,
  'pictures': BackupClass.family,
  'stories': BackupClass.family,
  'jokes': BackupClass.family,
  'lessons': BackupClass.family,
  'collections': BackupClass.family,
  'ladder': BackupClass.family,
  'colour': BackupClass.family,
  'family': BackupClass.family,
  'profile': BackupClass.family,
  'onboarding': BackupClass.family,
  'nicknames': BackupClass.family,
  'homegrowth': BackupClass.family,
  'outbox': BackupClass.family,
  'growing': BackupClass.family,
  'care': BackupClass.family,
  'emergencycard': BackupClass.family,
  'coordination': BackupClass.family,
  'aboutchild': BackupClass.family,
  'aboutplans': BackupClass.family,
  'explainers': BackupClass.family,
  'rhythm': BackupClass.family,
  'newplace': BackupClass.family,
  'voice': BackupClass.family,
  'access': BackupClass.family,
  'plan': BackupClass.family,
  'daytime': BackupClass.family,
  'village': BackupClass.family,
  'passes': BackupClass.family,
  'compass': BackupClass.family,
  'playsave': BackupClass.family,
  'localfamily': BackupClass.family,
  'familyledger': BackupClass.family,
  'familysync': BackupClass.family,
  'learn': BackupClass.family,
  'screenshares': BackupClass.family,
};

/// The area a namespace name belongs to (its last dot-separated part), or null for a name that is not a store name.
String? areaOfNamespace(String name) {
  if (!isValidNamespaceName(name)) return null;
  final int i = name.lastIndexOf('.');
  return i < 0 ? null : name.substring(i + 1);
}

bool _scopeMatches(LocalDataEntry e, String name) => switch (e.scope) {
      LocalScope.child => name.startsWith('child.') && name.split('.').length == 3,
      LocalScope.guardian => name.startsWith('guardian.') && name.split('.').length == 3,
      LocalScope.device => name.startsWith('device.') && name.split('.').length == 2,
    };

NamespaceSpec _specFor(LocalDataEntry e, String name) =>
    NamespaceSpec(name: name, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes);

/// One area as the snapshot holds it.
class AreaImage {
  const AreaImage(this.namespace, this.schema, this.data);
  final String namespace;
  final int schema;
  final Map<String, Object?> data;

  String get area => areaOfNamespace(namespace) ?? '';

  /// Over the namespace, the schema and the canonical (sorted-key) JSON of the document: two phones holding the same
  /// area give the same digest whatever order the keys were written in, and a changed byte gives another one.
  String get digest => sha256Hex('$namespace\n$schema\n${canonicalJson(data)}');
}

class LocalSnapshot {
  const LocalSnapshot(this.areas, {this.leftOut = const <String, String>{}});

  /// Namespace name to its image, family areas only.
  final Map<String, AreaImage> areas;

  /// Namespace name to why it is not in this snapshot ('child_private', 'device_bound', 'not_listed').
  final Map<String, String> leftOut;

  /// Namespace name to digest, for [compareDigests].
  Map<String, String> get digests => <String, String>{
        for (final String k in (areas.keys.toList()..sort())) k: areas[k]!.digest,
      };

  /// One digest over every area, for "is this the same backup".
  String get digest => sha256Hex(digests.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('\n'));

  Object toJson() => <String, Object?>{
        'v': 1,
        'areas': <String, Object?>{
          for (final String k in (areas.keys.toList()..sort()))
            k: <String, Object?>{'schema': areas[k]!.schema, 'data': areas[k]!.data},
        },
      };

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(canonicalJson(toJson())));

  /// Reads a snapshot back. Null for anything that is not exactly this shape (never throws): the caller keeps the
  /// original and tells the person it could not be read, instead of restoring part of it.
  static LocalSnapshot? fromJson(Object? j) {
    if (j is! Map || j['v'] != 1 || j['areas'] is! Map || j.length != 2) return null;
    final Map<String, AreaImage> out = <String, AreaImage>{};
    for (final MapEntry<dynamic, dynamic> e in (j['areas'] as Map).entries) {
      final Object? name = e.key, v = e.value;
      if (name is! String || !isValidNamespaceName(name) || v is! Map || v.length != 2) return null;
      final Object? schema = v['schema'], data = v['data'];
      if (schema is! int || schema < 1 || data is! Map) return null;
      final Map<String, Object?> doc = <String, Object?>{};
      for (final MapEntry<dynamic, dynamic> d in data.entries) {
        if (d.key is! String || !isValidKey(d.key as String)) return null;
        doc[d.key as String] = d.value;
      }
      out[name] = AreaImage(name, schema, doc);
    }
    return LocalSnapshot(out);
  }

  static LocalSnapshot? fromBytes(Uint8List b) {
    try {
      return fromJson(jsonDecode(utf8.decode(b)));
    } catch (_) {
      return null;
    }
  }
}

/// Copies every family area [store] holds. Read-only: a kill at any point changes nothing on the phone.
Future<LocalSnapshot> takeSnapshot(LocalStore store) async {
  final Map<String, AreaImage> areas = <String, AreaImage>{};
  final Map<String, String> left = <String, String>{};
  for (final String name in await store.namespaces()) {
    final String? area = areaOfNamespace(name);
    final LocalDataEntry? entry = area == null ? null : _entryOrNull(area);
    if (area == null || entry == null || !_scopeMatches(entry, name)) {
      left[name] = 'not_listed';
      continue;
    }
    switch (kBackupClass[area]) {
      case BackupClass.childPrivate:
        left[name] = 'child_private';
      case BackupClass.deviceBound:
        left[name] = 'device_bound';
      case BackupClass.family:
        // An area with nothing in it is the same as no area (a restore writes no file for it).
        final Map<String, Object?> data = await store.open(_specFor(entry, name)).readAll();
        if (data.isNotEmpty) areas[name] = AreaImage(name, entry.schema, data);
      case null:
        left[name] = 'not_listed';
    }
  }
  return LocalSnapshot(areas, leftOut: left);
}

LocalDataEntry? _entryOrNull(String area) {
  for (final LocalDataEntry e in localDataCatalogue) {
    if (e.area == area) return e;
  }
  return null;
}

/// Joins two different values of the same key into one that holds everything both hold, or null when this key is not
/// one that can be joined (the caller then keeps the held value and quarantines the other). Only two keys are joinable:
///  - 'familysync' / 'doc': the sealed events (a union by event bytes, held ones first), the other phones' last
///    summaries (held ones win), and the refused duplicate-counter notes (a union).
///  - 'outbox' / 'items': what was waiting to be sent (a union by item id, held ones first). An item that was already
///    sent from this phone and is still in an old backup comes back and is sent again; whoever receives it knows it by
///    its id, so that is a repeat, never a loss.
Object? joinValue(String area, String key, Object? held, Object? incoming) {
  if (area == 'familysync' && key == 'doc') {
    if (held is! Map || incoming is! Map) return null;
    if (held['v'] != 1 || incoming['v'] != 1) return null;
    final Object? he = held['e'], ie = incoming['e'], hp = held['p'], ip = incoming['p'], hq = held['q'], iq = incoming['q'];
    if (he is! List || ie is! List || hp is! Map || ip is! Map) return null;
    if (hq != null && hq is! List) return null;
    if (iq != null && iq is! List) return null;
    if (he.any((Object? x) => x is! String) || ie.any((Object? x) => x is! String)) return null;
    final Set<String> seen = <String>{...he.cast<String>()};
    final List<Object?> events = <Object?>[...he];
    for (final String w in ie.cast<String>()) {
      if (seen.add(w)) events.add(w);
    }
    final Map<String, Object?> peers = <String, Object?>{...ip.cast<String, Object?>(), ...hp.cast<String, Object?>()};
    final List<Object?> heldNotes = hq is List ? hq : <Object?>[], otherNotes = iq is List ? iq : <Object?>[];
    final Set<String> seenQ = <String>{for (final Object? q in heldNotes) jsonEncode(q)};
    final List<Object?> notes = <Object?>[...heldNotes];
    for (final Object? q in otherNotes) {
      if (seenQ.add(jsonEncode(q))) notes.add(q);
    }
    return <String, Object?>{...held.cast<String, Object?>(), 'e': events, 'p': peers, 'q': notes};
  }
  if (area == 'outbox' && key == 'items') {
    if (held is! List || incoming is! List) return null;
    String? idOf(Object? x) => x is Map && x['id'] is String ? x['id'] as String : null;
    if (held.any((Object? x) => idOf(x) == null) || incoming.any((Object? x) => idOf(x) == null)) return null;
    final Set<String> ids = <String>{for (final Object? x in held) idOf(x)!};
    return <Object?>[...held, for (final Object? x in incoming) if (ids.add(idOf(x)!)) x];
  }
  return null;
}

/// What [restoreSnapshot] did. Counts and names only; nothing here is worded for a screen.
class RestoreReport {
  final List<String> restored = <String>[];
  int keysAdded = 0, keysAlreadyHeld = 0, valuesKept = 0, keysJoined = 0;

  /// Namespace name to why that area was not put back ('not_family', 'not_listed', 'schema', 'too_big', 'full').
  /// The snapshot still holds it: a refusal loses nothing.
  final Map<String, String> refused = <String, String>{};
}

/// Puts a snapshot back, never deleting and never overwriting (see the file header).
Future<RestoreReport> restoreSnapshot(LocalStore store, LocalSnapshot snap) async {
  final RestoreReport r = RestoreReport();
  final List<AreaImage> todo = <AreaImage>[];
  for (final String name in (snap.areas.keys.toList()..sort())) {
    final AreaImage img = snap.areas[name]!;
    final String? area = areaOfNamespace(name);
    final LocalDataEntry? entry = area == null ? null : _entryOrNull(area);
    if (area == null || entry == null || !_scopeMatches(entry, name)) {
      r.refused[name] = 'not_listed';
    } else if (kBackupClass[area] != BackupClass.family) {
      r.refused[name] = 'not_family';
    } else if (img.schema != entry.schema) {
      r.refused[name] = 'schema';
    } else if (utf8.encode(canonicalJson(img.data)).length > entry.maxBytes) {
      r.refused[name] = 'too_big';
    } else {
      todo.add(img);
    }
  }
  for (final AreaImage img in todo) {
    final LocalDataEntry entry = _entryOrNull(img.area)!;
    final LocalNamespace ns = store.open(_specFor(entry, img.namespace));
    try {
      final MergeResult m = await ns.mergeMissing(img.data,
          combine: (String key, Object? held, Object? other) => joinValue(img.area, key, held, other),
          keepConflicts: (Map<String, Object?> c) async {
        await store.backend.quarantine(
            img.namespace, Uint8List.fromList(utf8.encode(canonicalJson(c))), 'restore-conflict');
      });
      r.restored.add(img.namespace);
      r.keysAdded += m.added;
      r.keysAlreadyHeld += m.same;
      r.keysJoined += m.joined;
      r.valuesKept += m.conflicts.length;
    } on LocalStoreFull {
      r.refused[img.namespace] = 'full';
    }
  }
  return r;
}

/// Digest per namespace of what [store] holds in the given classes (family only by default).
Future<Map<String, String>> areaDigests(LocalStore store, {Set<BackupClass> classes = const <BackupClass>{BackupClass.family}}) async {
  final Map<String, String> out = <String, String>{};
  for (final String name in await store.namespaces()) {
    final String? area = areaOfNamespace(name);
    final LocalDataEntry? entry = area == null ? null : _entryOrNull(area);
    if (area == null || entry == null || !_scopeMatches(entry, name)) continue;
    final BackupClass? c = kBackupClass[area];
    if (c == null || !classes.contains(c)) continue;
    final Map<String, Object?> data = await store.open(_specFor(entry, name)).readAll();
    if (data.isNotEmpty) out[name] = AreaImage(name, entry.schema, data).digest;
  }
  return out;
}

/// The restore-equivalence verdict: [before] is what the source held, [after] what the restored phone holds.
class Equivalence {
  Equivalence(this.same, this.missing, this.changed, this.unexpected);

  /// Areas whose digest matches.
  final List<String> same;

  /// In [before], absent after: something was lost.
  final List<String> missing;

  /// In both with different digests: something was altered.
  final List<String> changed;

  /// Absent before, present after (only a fault when the phone was meant to start empty).
  final List<String> unexpected;

  bool get ok => missing.isEmpty && changed.isEmpty && unexpected.isEmpty;

  @override
  String toString() => 'same=${same.length} missing=$missing changed=$changed unexpected=$unexpected';
}

Equivalence compareDigests(Map<String, String> before, Map<String, String> after) {
  final List<String> same = <String>[], missing = <String>[], changed = <String>[], unexpected = <String>[];
  for (final String k in (before.keys.toList()..sort())) {
    final String? a = after[k];
    if (a == null) {
      missing.add(k);
    } else if (a == before[k]) {
      same.add(k);
    } else {
      changed.add(k);
    }
  }
  for (final String k in (after.keys.toList()..sort())) {
    if (!before.containsKey(k)) unexpected.add(k);
  }
  return Equivalence(same, missing, changed, unexpected);
}
