// OLIVE BRANCH — the care profile ("About <child>"), the stored half: one sealed document per child on THIS
// device, the rules that guard it, and the PIN that opens its locked parts. UNVERIFIED until CI runs
// client/test/care_profile_store_test.dart. MASTERFILE section 8.24.8.
//
// TWO CATALOGUED AREAS (local_services.dart), both child-scoped and sealed:
//   'aboutchild'  the profile document: entries, today's heads-up, the people it is shown to and the
//                 time-boxed grants, the review dates, the birthday the yearly prompt uses.
//   'aboutplans'  the photos of a doctor's plan a grown-up chose to keep.
// Neither is ever uploaded, synced, backed up or put in the court export, and neither is readable from her app.
//
// RULES, held here and not left to screens:
//  - GUARDIAN ONLY. Every call takes the principal; a child (or no) principal is refused 'guardian_only' for
//    reads and writes alike.
//  - LOCKED PARTS. Health history and Moods and habits are readable and writable only after [unlock] has
//    verified the guardian PIN, and only for [cpUnlockWindow] after the last use. [read] without the PIN returns
//    the document with those entries taken out, so a screen cannot show what it was never given.
//  - NEVER A SILENT OVERWRITE. A grown-up changes only what they wrote ('not_yours' otherwise); to differ with
//    the other parent they add their own version beside it, and the screen shows both until one is chosen.
//    Choosing puts the other away (it stays, and can be brought back).
//  - THE TONE GUARD runs before an entry or a heads-up is created, on the parts that describe her (everyday,
//    what helps, today's heads-up, moods). A refused note never enters the document.
//  - TODAY'S HEADS-UP is one note for one local day. It is replaced, never revised, and [read] drops it for good
//    once the day has passed.
//  - SHARING ON ONE DEVICE. People and grants are stored and enforced by [cpViewFor] (care_profile_logic.dart).
//    A part that cannot be shared cannot be granted; a view-only person can be given Keep-safe alone.
//  - BOUNDED. Counts and lengths are capped; a full box refuses the write.
import 'dart:convert';
import 'dart:typed_data';

import 'care_local.dart' show CareResult;
import 'care_profile_logic.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'growing_care_logic.dart' show CareSection;
import 'local_services.dart';
import 'local_store.dart';

// ============================================================ repositories ===
abstract class CareProfileRepository {
  Future<CareProfileDoc> load();

  /// Throws [LocalStoreFull] / [LocalStoreException] on a failed save.
  Future<void> save(CareProfileDoc d);
}

class MemoryCareProfileRepository implements CareProfileRepository {
  Object? _j;
  @override
  Future<CareProfileDoc> load() async => CareProfileDoc.fromJson(_j == null ? null : jsonDecode(jsonEncode(_j)));
  @override
  Future<void> save(CareProfileDoc d) async => _j = jsonDecode(jsonEncode(d.toJson()));
}

class LocalStoreCareProfileRepository implements CareProfileRepository {
  LocalStoreCareProfileRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<CareProfileDoc> load() async {
    try {
      return CareProfileDoc.fromJson(await _ns.get(_key));
    } catch (_) {
      return const CareProfileDoc();
    }
  }

  @override
  Future<void> save(CareProfileDoc d) => _ns.put(_key, d.toJson());
}

/// Thrown by [CareProfileService.read] for a non-guardian.
class CareProfileRefused implements Exception {
  const CareProfileRefused(this.reason);
  final String reason;
  @override
  String toString() => 'CareProfileRefused($reason)';
}

class _Refuse implements Exception {
  const _Refuse(this.reason, [this.detail]);
  final String reason;
  final Map<String, Object?>? detail;
}

// ================================================================ service ===
class CareProfileService {
  CareProfileService(this.repo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  factory CareProfileService.memory({DateTime Function()? clock}) =>
      CareProfileService(MemoryCareProfileRepository(), clock: clock);

  /// Durable and sealed, scoped to [childId] (default: the device's child).
  factory CareProfileService.local(LocalServices services, {String? childId, DateTime Function()? clock}) =>
      CareProfileService(LocalStoreCareProfileRepository(services.area('aboutchild', ownerId: childId)), clock: clock);

  static CareProfileService? _shared;
  static String? _sharedFor;

  /// The one shared instance the guardian shell uses, bound to [LocalServices.current].
  static CareProfileService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    final String key = '${identityHashCode(s)}:${childId ?? s.childId}';
    if (_shared == null || _sharedFor != key) {
      _shared = CareProfileService.local(s, childId: childId);
      _sharedFor = key;
    }
    return _shared!;
  }

  static void resetShared() {
    _shared = null;
    _sharedFor = null;
  }

  final CareProfileRepository repo;
  final DateTime Function() _clock;

  /// One write at a time. The tail is made on first use (not at construction), so a service built in one zone and
  /// used in another (a widget test's setUp, then its body) still runs its steps in the zone that calls it.
  Future<void>? _tail;

  Future<T> _serial<T>(Future<T> Function() body) {
    final Future<T> r = (_tail ?? Future<void>.value()).then((_) => body());
    _tail = r.then((_) {}, onError: (Object _) {});
    return r;
  }

  bool _guardian(FamilyPrincipal? p) => canEditStructure(p);

  // ------------------------------------------------------------ the PIN ---
  DateTime? _openUntil;

  /// Whether the locked parts are open right now.
  bool get isUnlocked => _openUntil != null && _clock().isBefore(_openUntil!);

  /// Verifies [pin] with [verify] (the guardian PIN check) and, only if it is right, opens the locked parts for
  /// [cpUnlockWindow]. A null [verify] (no PIN on this device) keeps them locked.
  Future<bool> unlock(FamilyPrincipal? p, Future<bool> Function(String pin)? verify, String pin) async {
    if (!_guardian(p) || verify == null) return false;
    final bool ok = await verify(pin);
    if (ok) _openUntil = _clock().add(cpUnlockWindow);
    return ok;
  }

  /// Closes the locked parts now (a screen calls this when it goes away).
  void lock() => _openUntil = null;

  /// Reading or writing a locked part slides the window, so a grown-up who is writing is not cut off mid-way.
  void _touch() {
    if (isUnlocked) _openUntil = _clock().add(cpUnlockWindow);
  }

  // ----------------------------------------------------------- reading ---
  /// The document. Guardian only. While the PIN has not been given, the locked parts' entries are not in it.
  /// An expired heads-up is removed for good as part of the next read or write (nothing runs at midnight itself).
  Future<CareProfileDoc> read(FamilyPrincipal? p) async {
    if (!_guardian(p)) throw const CareProfileRefused('guardian_only');
    final CareProfileDoc d = await _serial<CareProfileDoc>(() async {
      CareProfileDoc cur = await repo.load();
      if (cur.heads != null && cur.heads!.day != cpDay(_clock())) {
        cur = cur.copyWith(clearHeads: true);
        try {
          await repo.save(cur);
        } catch (_) {
          // Not shown either way; removal is retried on the next read.
        }
      }
      return cur;
    });
    if (isUnlocked) {
      _touch();
      return d;
    }
    return d.withoutLocked();
  }

  // ----------------------------------------------------------- writing ---
  Future<CareResult<T>> _write<T>(
    FamilyPrincipal? p,
    String? byName,
    Future<(CareProfileDoc, T)> Function(CareProfileDoc d, String id, String who) body,
  ) {
    return _serial<CareResult<T>>(() async {
      if (!_guardian(p)) return CareResult<T>.no('guardian_only');
      try {
        final String id = p!.userId! as String;
        final CareProfileDoc d0 = _dropStaleHeads(await repo.load());
        final String given = _line(byName);
        if (given.length > cpMaxNameChars) return CareResult<T>.no('too_long');
        final Map<String, String> names = <String, String>{...d0.names, if (given.isNotEmpty) id: given};
        final String who = names[id] ?? '';
        final (CareProfileDoc nd, T v) = await body(d0.copyWith(names: names), id, who);
        await repo.save(nd);
        return CareResult<T>.ok(v);
      } on _Refuse catch (e) {
        return CareResult<T>.no(e.reason, detail: e.detail);
      } on LocalStoreFull {
        return CareResult<T>.no('full');
      } on LocalStoreException {
        return CareResult<T>.no('not_saved');
      }
    });
  }

  /// A heads-up from an earlier local day is removed from whatever is about to be saved, so no write carries it on.
  CareProfileDoc _dropStaleHeads(CareProfileDoc d) =>
      d.heads != null && d.heads!.day != cpDay(_clock()) ? d.copyWith(clearHeads: true) : d;

  String _line(Object? v) => cpText(v).replaceAll(RegExp(r'\s+'), ' ');
  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(_clock().millisecondsSinceEpoch, isUtc: true);
  String _id(CareProfileDoc d, String prefix) => '$prefix${d.seq + 1}';

  void _needOpen(CareProfilePart part) {
    if (part.locked) {
      if (!isUnlocked) throw const _Refuse('locked');
      _touch();
    }
  }

  void _tone(CareProfilePart part, String text, {bool skip = false}) {
    if (skip || !part.tone) return;
    final List<String> found = careProfileToneFound(text);
    if (found.isNotEmpty) throw _Refuse('tone', <String, Object?>{'found': found});
  }

  CareProfileDoc _stamp(CareProfileDoc d) => d.createdAt == null ? d.copyWith(createdAt: _now()) : d;

  // ------------------------------------------------------------ entries ---
  /// Adds an entry to a part that holds entries. [title] is optional (a short name for the thing described).
  Future<CareResult<String>> addEntry(
    FamilyPrincipal? p,
    CareProfilePart part,
    String text, {
    String title = '',
    String? byName,
  }) => _write<String>(p, byName, (CareProfileDoc d, String gid, String who) async {
    if (!part.entries) throw const _Refuse('not_found');
    _needOpen(part);
    final String body = cpText(text), t = _line(title);
    if (body.isEmpty) throw const _Refuse('text_needed');
    if (body.length > cpMaxTextChars || t.length > cpMaxTitleChars) throw const _Refuse('too_long');
    if (d.entries.length >= cpMaxEntries) throw const _Refuse('too_many');
    _tone(part, '$t $body');
    final String eid = _id(d, 'e');
    final CpEntry e = CpEntry(id: eid, part: part, title: t, text: body, at: _now(), byId: gid, byName: who);
    return (_stamp(d).copyWith(entries: <CpEntry>[...d.entries, e], seq: d.seq + 1), eid);
  });

  CpEntry _find(CareProfileDoc d, String id) {
    for (final CpEntry e in d.entries) {
      if (e.id == id) return e;
    }
    throw const _Refuse('not_found');
  }

  CareProfileDoc _replace(CareProfileDoc d, CpEntry e) =>
      d.copyWith(entries: <CpEntry>[for (final CpEntry x in d.entries) x.id == e.id ? e : x]);

  /// Changes an entry you wrote. What it said before is kept as a plain revision (who changed it and when).
  /// Someone else's entry is refused 'not_yours': add your own version beside it instead.
  Future<CareResult<void>> editEntry(
    FamilyPrincipal? p,
    String id,
    String text, {
    String? title,
    String? byName,
  }) => _write<void>(p, byName, (CareProfileDoc d, String gid, String who) async {
    final CpEntry cur = _find(d, id);
    _needOpen(cur.part);
    if (cur.retired) throw const _Refuse('not_found');
    if (cur.byId != gid && !(cur.fromBinderId != null && cur.byId.isEmpty)) throw const _Refuse('not_yours');
    final String body = cpText(text), t = title == null ? cur.title : _line(title);
    if (body.isEmpty) throw const _Refuse('text_needed');
    if (body.length > cpMaxTextChars || t.length > cpMaxTitleChars) throw const _Refuse('too_long');
    if (body == cur.text && t == cur.title) return (d, null);
    _tone(cur.part, '$t $body');
    final List<CpRevision> revs = <CpRevision>[
      ...cur.revisions,
      CpRevision(at: _now(), byId: gid, byName: who, title: cur.title, text: cur.text),
    ];
    final List<CpRevision> kept = revs.length > cpMaxRevisions ? revs.sublist(revs.length - cpMaxRevisions) : revs;
    // A binder-copied entry belongs to whoever first edits it: from then on it is theirs.
    final CpEntry next = CpEntry(
      id: cur.id,
      part: cur.part,
      title: t,
      text: body,
      at: cur.at,
      byId: cur.byId.isEmpty ? gid : cur.byId,
      byName: cur.byId.isEmpty ? who : cur.byName,
      revisions: kept,
      retired: cur.retired,
      retiredBy: cur.retiredBy,
      fromBinderId: cur.fromBinderId,
    );
    return (_replace(d, next), null);
  });

  /// Adds the caller's own entry beside [id], same part and same title, so both versions show. Returns the new id.
  Future<CareResult<String>> addMyVersion(FamilyPrincipal? p, String id, String text, {String? byName}) =>
      _write<String>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final CpEntry cur = _find(d, id);
        _needOpen(cur.part);
        if (cur.title.isEmpty) throw const _Refuse('name_needed');
        final String body = cpText(text);
        if (body.isEmpty) throw const _Refuse('text_needed');
        if (body.length > cpMaxTextChars) throw const _Refuse('too_long');
        if (d.entries.length >= cpMaxEntries) throw const _Refuse('too_many');
        _tone(cur.part, '${cur.title} $body');
        final String eid = _id(d, 'e');
        final CpEntry e = CpEntry(id: eid, part: cur.part, title: cur.title, text: body, at: _now(), byId: gid, byName: who);
        return (d.copyWith(entries: <CpEntry>[...d.entries, e], seq: d.seq + 1), eid);
      });

  /// Chooses one version among entries that disagree: the others in its group are put away (kept, and can be
  /// brought back). Returns how many were put away.
  Future<CareResult<int>> settle(FamilyPrincipal? p, String keepId, {String? byName}) =>
      _write<int>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final CpEntry keep = _find(d, keepId);
        _needOpen(keep.part);
        List<CpEntry>? group;
        for (final List<CpEntry> g in cpDisagreements(d, keep.part)) {
          if (g.any((CpEntry e) => e.id == keepId)) group = g;
        }
        if (group == null) throw const _Refuse('not_found');
        final Set<String> away = <String>{for (final CpEntry e in group) if (e.id != keepId) e.id};
        return (
          d.copyWith(
            entries: <CpEntry>[
              for (final CpEntry e in d.entries)
                away.contains(e.id) ? e.copyWith(retired: true, retiredBy: who.isEmpty ? gid : who) : e,
            ],
          ),
          away.length,
        );
      });

  /// Puts away an entry you wrote (it leaves every view and sheet; it can be brought back).
  Future<CareResult<void>> putAway(FamilyPrincipal? p, String id, {String? byName}) =>
      _write<void>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final CpEntry cur = _find(d, id);
        _needOpen(cur.part);
        if (cur.byId != gid && !(cur.fromBinderId != null && cur.byId.isEmpty)) throw const _Refuse('not_yours');
        return (_replace(d, cur.copyWith(retired: true, retiredBy: who.isEmpty ? gid : who)), null);
      });

  /// Brings a put-away entry back (any grown-up may: nothing is lost by putting it back in view).
  Future<CareResult<void>> bringBack(FamilyPrincipal? p, String id, {String? byName}) =>
      _write<void>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final CpEntry cur = _find(d, id);
        _needOpen(cur.part);
        return (_replace(d, cur.copyWith(retired: false, retiredBy: '')), null);
      });

  // -------------------------------------------------------- heads-up ---
  /// Writes today's heads-up (replacing any earlier one). It is for today only and is not kept as a log.
  Future<CareResult<void>> setHeads(FamilyPrincipal? p, String text, {String? byName}) =>
      _write<void>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final String body = cpText(text);
        if (body.isEmpty) throw const _Refuse('text_needed');
        if (body.length > cpMaxHeadsChars) throw const _Refuse('too_long');
        _tone(CareProfilePart.heads, body);
        final DateTime now = _now();
        return (
          _stamp(d).copyWith(heads: CpHeads(text: body, day: cpDay(_clock()), at: now, byId: gid, byName: who)),
          null,
        );
      });

  Future<CareResult<void>> clearHeads(FamilyPrincipal? p) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async => (d.copyWith(clearHeads: true), null));

  // --------------------------------------------------- people, sharing ---
  Future<CareResult<String>> addPerson(FamilyPrincipal? p, String name, CpPersonKind kind, {String? byName}) =>
      _write<String>(p, byName, (CareProfileDoc d, String gid, String who) async {
        final String n = _line(name);
        if (n.isEmpty) throw const _Refuse('name_needed');
        if (n.length > cpMaxNameChars) throw const _Refuse('too_long');
        if (d.people.length >= cpMaxPeople) throw const _Refuse('too_many');
        final String pid = _id(d, 'p');
        return (
          d.copyWith(
            people: <CpPerson>[...d.people, CpPerson(id: pid, name: n, kind: kind, grants: cpDefaultGrants(kind, _clock()))],
            seq: d.seq + 1,
          ),
          pid,
        );
      });

  Future<CareResult<void>> removePerson(FamilyPrincipal? p, String personId) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
        if (!d.people.any((CpPerson x) => x.id == personId)) throw const _Refuse('not_found');
        return (d.copyWith(people: <CpPerson>[for (final CpPerson x in d.people) if (x.id != personId) x]), null);
      });

  CpPerson _person(CareProfileDoc d, String id) {
    for (final CpPerson x in d.people) {
      if (x.id == id) return x;
    }
    throw const _Refuse('not_found');
  }

  CareProfileDoc _putPerson(CareProfileDoc d, CpPerson np) =>
      d.copyWith(people: <CpPerson>[for (final CpPerson x in d.people) x.id == np.id ? np : x]);

  /// Shows [part] to [personId] until [until] (UTC; null = until you take it back), or takes it back with
  /// [on] false. A parents-only part, or a part the person's kind cannot have, is refused.
  Future<CareResult<void>> setGrant(
    FamilyPrincipal? p,
    String personId,
    CareProfilePart part, {
    bool on = true,
    DateTime? until,
  }) => _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
    final CpPerson person = _person(d, personId);
    if (!part.shareable) throw const _Refuse('not_shareable');
    if (on && !cpMayGrant(person.kind, part)) throw const _Refuse('not_allowed');
    if (on && until != null) {
      final DateTime u = until.toUtc();
      if (!u.isAfter(_now()) || u.isAfter(_now().add(const Duration(days: 366)))) throw const _Refuse('bad_time');
    }
    final Map<CareProfilePart, CpGrant> g = <CareProfilePart, CpGrant>{...person.grants};
    if (on) {
      g[part] = CpGrant(until: until?.toUtc());
    } else {
      g.remove(part);
    }
    return (_putPerson(d, person.copyWith(grants: g)), null);
  });

  /// "Show for tonight": Keep-safe and today's heads-up (and any other [parts] the person's kind allows) until the
  /// next 6 in the morning. One tap; the access ends by itself.
  Future<CareResult<void>> grantTonight(
    FamilyPrincipal? p,
    String personId, {
    Set<CareProfilePart> parts = const <CareProfilePart>{CareProfilePart.safe, CareProfilePart.heads},
  }) => _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
    final CpPerson person = _person(d, personId);
    final DateTime end = cpTonightEnds(_clock());
    final Map<CareProfilePart, CpGrant> g = <CareProfilePart, CpGrant>{...person.grants};
    for (final CareProfilePart part in parts) {
      if (cpMayGrant(person.kind, part)) g[part] = CpGrant(until: end);
    }
    return (_putPerson(d, person.copyWith(grants: g)), null);
  });

  // ------------------------------------------------- review, birthday ---
  Future<CareResult<void>> setBirthday(FamilyPrincipal? p, int? month, int? day) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
        if (month == null || day == null) return (d.copyWith(clearBirthday: true), null);
        // Any real month and day; 29 February is allowed.
        if (month < 1 || month > 12 || day < 1 || day > DateTime(2024, month + 1, 0).day) throw const _Refuse('bad_date');
        return (d.copyWith(birthMonth: month, birthDay: day), null);
      });

  /// Remembers the medicine list as it is now, the first time, so a later change can prompt a review. Does not
  /// mark the profile reviewed.
  Future<CareResult<void>> ensureBaseline(FamilyPrincipal? p, String medFingerprint) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
        if (d.reviewedMedFingerprint != null) return (d, null);
        return (d.copyWith(reviewedMedFingerprint: medFingerprint), null);
      });

  /// "Yes, it is still right": the dates and the medicine list the next prompt counts from.
  Future<CareResult<void>> markReviewed(FamilyPrincipal? p, String medFingerprint) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async {
        return (_stamp(d).copyWith(lastReviewedAt: _now(), reviewedMedFingerprint: medFingerprint), null);
      });

  Future<CareResult<void>> setTeenPreview(FamilyPrincipal? p, bool on) =>
      _write<void>(p, null, (CareProfileDoc d, String gid, String who) async => (d.copyWith(teenPreview: on), null));

  // ------------------------------------------------------ the binder ---
  /// Copies the care binder's sections into the profile, once each. The binder is not changed or emptied. A
  /// section with nothing written is skipped (and copied later if it gets text). Returns how many were copied.
  /// Routines, school and notes become Her everyday; allergies become Keep-safe. The tone guard does not run
  /// here: this is what a grown-up already wrote.
  Future<CareResult<int>> importBinder(FamilyPrincipal? p, List<CareSection> sections) =>
      _write<int>(p, null, (CareProfileDoc d, String gid, String who) async {
        final List<CpEntry> add = <CpEntry>[];
        final List<String> done = <String>[...d.importedBinderIds];
        int seq = d.seq;
        for (final CareSection s in sections) {
          if (done.contains(s.id)) continue;
          final String body = cpText(s.body);
          if (body.isEmpty) continue;
          if (d.entries.length + add.length >= cpMaxEntries) throw const _Refuse('too_many');
          // A date with no time: kept as local noon so it reads as the same day in any time zone.
          final DateTime? day = DateTime.tryParse('${s.updatedOn}T12:00:00');
          final DateTime? at = day?.toUtc();
          seq++;
          add.add(
            CpEntry(
              id: 'e$seq',
              part: s.kind == 'allergies' ? CareProfilePart.safe : CareProfilePart.everyday,
              title: _line(s.title).length > cpMaxTitleChars ? _line(s.title).substring(0, cpMaxTitleChars) : _line(s.title),
              text: body.length > cpMaxTextChars ? body.substring(0, cpMaxTextChars) : body,
              at: at ?? _now(),
              fromBinderId: s.id,
            ),
          );
          done.add(s.id);
        }
        if (add.isEmpty) return (d, 0);
        return (_stamp(d).copyWith(entries: <CpEntry>[...d.entries, ...add], importedBinderIds: done, seq: seq), add.length);
      });
}

// ============================================================ plan photos ===
abstract class CarePlanPhotoRepository {
  Future<List<CpPlanPhoto>> load();
  Future<void> save(List<CpPlanPhoto> photos);
}

class MemoryCarePlanPhotoRepository implements CarePlanPhotoRepository {
  Object? _j;
  @override
  Future<List<CpPlanPhoto>> load() async => _decode(_j == null ? null : jsonDecode(jsonEncode(_j)));
  @override
  Future<void> save(List<CpPlanPhoto> photos) async => _j = jsonDecode(jsonEncode(_encode(photos)));
}

Object? _encode(List<CpPlanPhoto> l) => <String, Object?>{'photos': <Object?>[for (final CpPlanPhoto p in l) p.toJson()]};

List<CpPlanPhoto> _decode(Object? j) => <CpPlanPhoto>[
  if (j is Map && j['photos'] is List)
    for (final Object? x in (j['photos']! as List).take(cpMaxPlanPhotos)) ?CpPlanPhoto.tryFromJson(x),
];

class LocalStoreCarePlanPhotoRepository implements CarePlanPhotoRepository {
  LocalStoreCarePlanPhotoRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<List<CpPlanPhoto>> load() async {
    try {
      return _decode(await _ns.get(_key));
    } catch (_) {
      return const <CpPlanPhoto>[];
    }
  }

  @override
  Future<void> save(List<CpPlanPhoto> photos) => _ns.put(_key, _encode(photos));
}

/// The photos of a doctor's plan. The ONLY way a photo gets in is [add], with bytes a grown-up chose; the app
/// never makes, crops, enhances or reads one. Guardian only; a child (or no) principal is refused.
class CarePlanPhotoService {
  CarePlanPhotoService(this.repo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  factory CarePlanPhotoService.memory({DateTime Function()? clock}) =>
      CarePlanPhotoService(MemoryCarePlanPhotoRepository(), clock: clock);

  factory CarePlanPhotoService.local(LocalServices services, {String? childId, DateTime Function()? clock}) =>
      CarePlanPhotoService(LocalStoreCarePlanPhotoRepository(services.area('aboutplans', ownerId: childId)), clock: clock);

  static CarePlanPhotoService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    return CarePlanPhotoService.local(s, childId: childId);
  }

  final CarePlanPhotoRepository repo;
  final DateTime Function() _clock;
  Future<void>? _tail;

  Future<T> _serial<T>(Future<T> Function() body) {
    final Future<T> r = (_tail ?? Future<void>.value()).then((_) => body());
    _tail = r.then((_) {}, onError: (Object _) {});
    return r;
  }

  Future<List<CpPlanPhoto>> list(FamilyPrincipal? p) async {
    if (!canEditStructure(p)) throw const CareProfileRefused('guardian_only');
    return repo.load();
  }

  /// Keeps [bytes] (a JPEG or PNG, at most [cpMaxPlanPhotoBytes]) under a [label] the grown-up typed.
  Future<CareResult<String>> add(FamilyPrincipal? p, String label, Uint8List bytes, {String byName = ''}) {
    return _serial<CareResult<String>>(() async {
      if (!canEditStructure(p)) return const CareResult<String>.no('guardian_only');
      final String l = cpText(label).replaceAll(RegExp(r'\s+'), ' ');
      if (l.isEmpty) return const CareResult<String>.no('name_needed');
      if (l.length > cpMaxLabelChars) return const CareResult<String>.no('too_long');
      if (!cpLooksLikeImage(bytes)) return const CareResult<String>.no('not_an_image');
      if (bytes.length > cpMaxPlanPhotoBytes) return const CareResult<String>.no('photo_too_big');
      try {
        final List<CpPlanPhoto> cur = await repo.load();
        if (cur.length >= cpMaxPlanPhotos) return const CareResult<String>.no('too_many');
        int top = 0;
        for (final CpPlanPhoto x in cur) {
          final int? n = int.tryParse(x.id.substring(2));
          if (n != null && n > top) top = n;
        }
        final String id = 'ph${top + 1}';
        final CpPlanPhoto ph = CpPlanPhoto(
          id: id,
          label: l,
          bytes: Uint8List.fromList(bytes),
          at: DateTime.fromMillisecondsSinceEpoch(_clock().millisecondsSinceEpoch, isUtc: true),
          byId: p!.userId! as String,
          byName: cpText(byName),
        );
        await repo.save(<CpPlanPhoto>[...cur, ph]);
        return CareResult<String>.ok(id);
      } on LocalStoreFull {
        return const CareResult<String>.no('full');
      } on LocalStoreException {
        return const CareResult<String>.no('not_saved');
      }
    });
  }

  Future<CareResult<void>> remove(FamilyPrincipal? p, String id) {
    return _serial<CareResult<void>>(() async {
      if (!canEditStructure(p)) return const CareResult<void>.no('guardian_only');
      try {
        final List<CpPlanPhoto> cur = await repo.load();
        if (!cur.any((CpPlanPhoto x) => x.id == id)) return const CareResult<void>.no('not_found');
        await repo.save(<CpPlanPhoto>[for (final CpPlanPhoto x in cur) if (x.id != id) x]);
        return const CareResult<void>.ok();
      } on LocalStoreException {
        return const CareResult<void>.no('not_saved');
      }
    });
  }
}
