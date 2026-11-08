// OLIVE BRANCH — LocalStore-backed repositories for the areas whose models are
// pure logic (no screen). No longer UNVERIFIED — verified by CI
// (client/test/local_repositories_test.dart).
//
// Each repository is a narrow class over ONE [LocalNamespace]: it owns the
// wire shape of what it keeps, and — more importantly — what it refuses to
// keep. The rule applied to every one of them: nothing is stored that the
// product refuses to SHOW. No scores, counts, streaks, rankings or
// completion states (P2); no prices (P4); no coordinates (P3). Where an
// in-memory model carries a counter (a story's timesRead, a lesson's
// askedAgain, an outbox item's attempts) the repository either drops it or
// reduces it to the one bit the product actually uses, and says so below.
//
// Tests hand these a namespace from an in-memory [LocalStore]
// (MemoryStoreBackend); the app hands them one from the directory backend.
// Repositories for areas whose models live in a screen file (journal, lists,
// pictures, lessons, ladder, Parent Learn) sit beside that model to avoid an
// import cycle.
import 'dart:typed_data';

import 'library_logic.dart';
import 'joke_logic.dart';
import 'local_store.dart';
import 'offline_outbox.dart';
import 'showcase_logic.dart';

Map<String, Object?>? _asMap(Object? v) => v is Map ? Map<String, Object?>.from(v) : null;
List<Object?>? _asList(Object? v) => v is List ? List<Object?>.from(v) : null;

/// Stories she starred and where she bookmarked. A favourite keeps its code,
/// title and date only: [Favourite.timesRead] is a read counter and is NOT
/// stored (a restored favourite counts as read once, which is what star()
/// itself starts it at).
class StoryShelfRepository {
  StoryShelfRepository(this._ns);
  final LocalNamespace _ns;

  static const String _favKey = 'favourites';
  static const String _markKey = 'bookmarks';

  Future<List<Favourite>?> loadFavourites() async {
    final List<Object?>? raw = _asList(await _ns.get(_favKey));
    if (raw == null) return null;
    final List<Favourite> out = <Favourite>[];
    for (final Object? o in raw) {
      final Map<String, Object?>? m = _asMap(o);
      if (m == null) continue;
      final Object? code = m['code'], title = m['title'], at = m['starredAt'];
      if (code is! String || title is! String || at is! String) continue;
      out.add(Favourite(code: code, title: title, starredAt: at, timesRead: 1));
    }
    return out;
  }

  Future<List<Bookmark>?> loadBookmarks() async {
    final List<Object?>? raw = _asList(await _ns.get(_markKey));
    if (raw == null) return null;
    final List<Bookmark> out = <Bookmark>[];
    for (final Object? o in raw) {
      final Map<String, Object?>? m = _asMap(o);
      if (m == null) continue;
      final Object? code = m['code'], line = m['lineIndex'], title = m['title'], at = m['savedAt'];
      if (code is! String || line is! int || title is! String || at is! String) continue;
      out.add(Bookmark(code: code, lineIndex: line, title: title, savedAt: at));
    }
    return out;
  }

  Future<void> save({required List<Favourite> favourites, required List<Bookmark> bookmarks}) async {
    await _ns.put(_favKey, <Object?>[
      for (final Favourite f in favourites)
        <String, Object?>{'code': f.code, 'title': f.title, 'starredAt': f.starredAt},
    ]);
    await _ns.put(_markKey, <Object?>[
      for (final Bookmark b in bookmarks)
        <String, Object?>{
          'code': b.code, 'lineIndex': b.lineIndex, 'title': b.title, 'savedAt': b.savedAt,
        },
    ]);
  }
}

/// Jokes she starred: id and date, nothing else (joke_logic.dart's own rule).
class JokeFavouritesRepository {
  JokeFavouritesRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'favourites';

  Future<List<JokeFavourite>?> load() async {
    final List<Object?>? raw = _asList(await _ns.get(_key));
    if (raw == null) return null;
    final List<JokeFavourite> out = <JokeFavourite>[];
    for (final Object? o in raw) {
      final Map<String, Object?>? m = _asMap(o);
      if (m == null) continue;
      final Object? id = m['id'], at = m['starredAt'];
      if (id is String && at is String) out.add(JokeFavourite(id: id, starredAt: at));
    }
    return out;
  }

  Future<void> save(List<JokeFavourite> favourites) => _ns.put(_key, <Object?>[
        for (final JokeFavourite f in favourites)
          <String, Object?>{'id': f.id, 'starredAt': f.starredAt},
      ]);
}

/// What she has shown, kept (no totals, no denominator: showcase_logic.dart).
class CollectionsRepository {
  CollectionsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'collections';

  /// Null means "never saved" (the caller may then show demo seeds); an empty
  /// list means "saved, and empty".
  Future<List<Collection>?> load() async {
    final List<Object?>? raw = _asList(await _ns.get(_key));
    if (raw == null) return null;
    final List<Collection> out = <Collection>[];
    for (final Object? o in raw) {
      final Map<String, Object?>? m = _asMap(o);
      final Object? interest = m?['interestId'];
      final List<Object?>? entries = _asList(m?['entries']);
      if (interest is! String || entries == null) continue;
      final List<CollectionEntry> list = <CollectionEntry>[];
      for (final Object? e in entries) {
        final Map<String, Object?>? em = _asMap(e);
        if (em == null) continue;
        final Object? id = em['id'], name = em['name'], at = em['shownAt'];
        if (id is! String || name is! String || at is! String) continue;
        final DateTime? shown = DateTime.tryParse(at);
        if (shown == null) continue;
        list.add(CollectionEntry(
            id: id, interestId: interest, name: name, shownAt: shown,
            note: em['note'] is String ? em['note'] as String : null));
      }
      out.add(Collection(interestId: interest, entries: list));
    }
    return out;
  }

  Future<void> save(List<Collection> collections) => _ns.put(_key, <Object?>[
        for (final Collection c in collections)
          <String, Object?>{
            'interestId': c.interestId,
            'entries': <Object?>[
              for (final CollectionEntry e in c.entries)
                <String, Object?>{
                  'id': e.id, 'name': e.name, 'shownAt': e.shownAt.toIso8601String(),
                  if (e.note != null) 'note': e.note,
                },
            ],
          },
      ]);
}

/// The offline outbox's items, so a restart does not lose what she made.
/// The queue semantics (enqueue / backoff / maxAttempts) stay in
/// offline_outbox.dart and are untouched; this only remembers the list.
///
/// An item whose payload is not plain JSON (raw recorded bytes, for example)
/// cannot be written down, so it is NOT stored; [save] returns how many were
/// skipped so the caller can be honest about it instead of pretending.
class OutboxRepository {
  OutboxRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'items';

  Future<List<OutboxItem>> load() async {
    final List<Object?>? raw = _asList(await _ns.get(_key));
    if (raw == null) return <OutboxItem>[];
    final List<OutboxItem> out = <OutboxItem>[];
    for (final Object? o in raw) {
      final Map<String, Object?>? m = _asMap(o);
      if (m == null) continue;
      final Object? id = m['id'], kind = m['kind'], at = m['createdAt'];
      if (id is! String || kind is! String || at is! String) continue;
      OutboxKind? k;
      for (final OutboxKind v in OutboxKind.values) {
        if (v.wireValue == kind) k = v;
      }
      final DateTime? created = DateTime.tryParse(at);
      if (k == null || created == null) continue;
      out.add(OutboxItem(
        id: id, kind: k, createdAt: created, payload: m['payload'],
        attempts: m['attempts'] is int ? m['attempts'] as int : 0,
        lastError: m['lastError'] is String ? m['lastError'] as String : null,
      ));
    }
    return out;
  }

  /// Returns the number of items that could not be written (non-JSON payload).
  Future<int> save(List<OutboxItem> items) async {
    int skipped = 0;
    final List<Object?> rows = <Object?>[];
    for (final OutboxItem i in items) {
      final Map<String, Object?> row = <String, Object?>{
        'id': i.id,
        'kind': i.kind.wireValue,
        'createdAt': i.createdAt.toIso8601String(),
        'payload': i.payload,
        'attempts': i.attempts,
        if (i.lastError != null) 'lastError': i.lastError,
      };
      try {
        rows.add(jsonSafe(row));
      } catch (_) {
        skipped++;
      }
    }
    await _ns.put(_key, rows);
    return skipped;
  }
}

/// Throws if [v] is not plain JSON; returns a deep copy otherwise.
Object? jsonSafe(Object? v) {
  if (v == null || v is String || v is bool || v is int) return v;
  if (v is double) {
    if (v.isNaN || v.isInfinite) throw const FormatException('non-finite number');
    return v;
  }
  // Raw bytes are a List<int> to Dart but are NOT something to write down as a
  // giant JSON array of numbers: recorded media has no business in this store.
  if (v is TypedData) throw const FormatException('raw bytes are not stored');
  if (v is List) return <Object?>[for (final Object? e in v) jsonSafe(e)];
  if (v is Map) {
    final Map<String, Object?> out = <String, Object?>{};
    for (final MapEntry<dynamic, dynamic> e in v.entries) {
      final Object? k = e.key;
      if (k is! String) throw const FormatException('non-string key');
      out[k] = jsonSafe(e.value);
    }
    return out;
  }
  throw FormatException('not JSON: ${v.runtimeType}');
}

/// The per-child cache that lets an onboarded child open the app with no
/// signal (audit C-06) and see her own name. Three facts, no more: her first
/// name, her age in whole years, and that onboarding finished.
class ProfileCache {
  const ProfileCache({this.displayName, this.yearsOld, required this.hasOnboarded, this.overrides});
  final String? displayName;
  final int? yearsOld;
  final bool hasOnboarded;

  /// The grown-up's last-known "hide / pace this" choices for her, exactly as
  /// the server sent them (activity_overrides.dart's wire shape). Remembered so
  /// that going offline cannot quietly UNHIDE something a guardian hid: without
  /// it the offline home would fail open to "show everything".
  final Map<String, Object?>? overrides;
}

class ProfileCacheRepository {
  ProfileCacheRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'cache';

  Future<ProfileCache?> load() async {
    final Map<String, Object?>? m = _asMap(await _ns.get(_key));
    if (m == null) return null;
    return ProfileCache(
      displayName: m['displayName'] is String ? m['displayName'] as String : null,
      yearsOld: m['yearsOld'] is int ? m['yearsOld'] as int : null,
      hasOnboarded: m['hasOnboarded'] == true,
      overrides: _asMap(m['overrides']),
    );
  }

  Future<void> save(ProfileCache c) => _ns.put(_key, <String, Object?>{
        if (c.displayName != null) 'displayName': c.displayName,
        if (c.yearsOld != null) 'yearsOld': c.yearsOld,
        'hasOnboarded': c.hasOnboarded,
        if (c.overrides != null) 'overrides': c.overrides,
      });

  /// Records only that onboarding finished, keeping everything else cached.
  Future<void> markOnboarded() async {
    final ProfileCache? e = await load();
    await save(ProfileCache(
        displayName: e?.displayName, yearsOld: e?.yearsOld, hasOnboarded: true,
        overrides: e?.overrides));
  }

  /// Remembers what the home screen last learned from the server (her name,
  /// age and the grown-up's overrides), keeping the onboarding answer as is.
  Future<void> rememberHome({String? displayName, int? yearsOld, Map<String, Object?>? overrides}) async {
    final ProfileCache? e = await load();
    await save(ProfileCache(
        displayName: displayName ?? e?.displayName,
        yearsOld: yearsOld ?? e?.yearsOld,
        hasOnboarded: e?.hasOnboarded ?? false,
        overrides: overrides ?? e?.overrides));
  }
}

/// The offline-first answer to "has this child finished onboarding?" (audit
/// C-06). [fetch] is the server's answer; it THROWS when the server cannot be
/// reached.
///  - server says yes  -> true, and remembered;
///  - server says no   -> false (the server wins), and the cache follows it;
///  - server unreachable -> the remembered answer, or false for a device that
///    never confirmed it (still fail-closed: an unknown child is not let past
///    the welcome tour).
Future<bool> resolveHasOnboarded({
  required Future<bool> Function() fetch,
  required ProfileCacheRepository cache,
}) async {
  bool answer;
  try {
    answer = await fetch();
  } catch (_) {
    final ProfileCache? cached = await _safeLoad(cache);
    return cached?.hasOnboarded ?? false;
  }
  final ProfileCache? cached = await _safeLoad(cache);
  if (cached == null || cached.hasOnboarded != answer) {
    try {
      await cache.save(ProfileCache(
          displayName: cached?.displayName, yearsOld: cached?.yearsOld, hasOnboarded: answer,
          overrides: cached?.overrides));
    } catch (_) {
      // A full or unwritable store must never turn a good answer into a crash.
    }
  }
  return answer;
}

Future<ProfileCache?> _safeLoad(ProfileCacheRepository cache) async {
  try {
    return await cache.load();
  } catch (_) {
    return null;
  }
}
