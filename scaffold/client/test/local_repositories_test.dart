// OLIVE BRANCH — repositories over LocalStore: what each one keeps, what it
// refuses to keep (P2/P3/P4), and the offline-first onboarding answer (C-06).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/library_logic.dart';
import 'package:olive_client/joke_logic.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/showcase_logic.dart';

LocalNamespace _ns(String area, [LocalServices? s]) => (s ?? LocalServices.memory(childId: 'ivy')).area(area);

void main() {
  group('story shelf', () {
    test('favourites and bookmarks round-trip; null means never saved', () async {
      final StoryShelfRepository r = StoryShelfRepository(_ns('stories'));
      expect(await r.loadFavourites(), isNull);
      expect(await r.loadBookmarks(), isNull);
      await r.save(
        favourites: const <Favourite>[Favourite(code: 'c1', title: 'The Fox', starredAt: '2026-11-01T00:00:00Z', timesRead: 7)],
        bookmarks: const <Bookmark>[Bookmark(code: 'c1', lineIndex: 3, title: 'The Fox', savedAt: '2026-11-02T00:00:00Z')],
      );
      final List<Favourite> f = (await r.loadFavourites())!;
      expect(f.single.code, 'c1');
      expect(f.single.title, 'The Fox');
      final List<Bookmark> b = (await r.loadBookmarks())!;
      expect(b.single.lineIndex, 3);
    });

    test('P2: the read counter is never written to disk', () async {
      final LocalNamespace ns = _ns('stories');
      await StoryShelfRepository(ns).save(
        favourites: const <Favourite>[Favourite(code: 'c1', title: 'T', starredAt: 'x', timesRead: 42)],
        bookmarks: const <Bookmark>[],
      );
      final Object? raw = await ns.get('favourites');
      expect(raw.toString(), isNot(contains('42')));
      expect(raw.toString(), isNot(contains('timesRead')));
      expect((await StoryShelfRepository(ns).loadFavourites())!.single.timesRead, 1);
    });

    test('malformed rows are skipped, never thrown', () async {
      final LocalNamespace ns = _ns('stories');
      await ns.put('favourites', <Object?>[1, 'x', <String, Object?>{'code': 5}, <String, Object?>{'code': 'ok', 'title': 't', 'starredAt': 'd'}]);
      expect((await StoryShelfRepository(ns).loadFavourites())!.map((Favourite f) => f.code), <String>['ok']);
    });
  });

  group('joke favourites', () {
    test('id and date only', () async {
      final LocalNamespace ns = _ns('jokes');
      final JokeFavouritesRepository r = JokeFavouritesRepository(ns);
      expect(await r.load(), isNull);
      await r.save(const <JokeFavourite>[JokeFavourite(id: 'j1', starredAt: '2026-11-01')]);
      expect((await r.load())!.single.id, 'j1');
      final Map<Object?, Object?> row = ((await ns.get('favourites'))! as List).single as Map<Object?, Object?>;
      expect(row.keys.toSet(), <Object?>{'id', 'starredAt'});
    });
  });

  group('collections', () {
    test('entries round-trip with their dates and optional note', () async {
      final CollectionsRepository r = CollectionsRepository(_ns('collections'));
      expect(await r.load(), isNull);
      final DateTime t = DateTime.utc(2026, 11, 1, 10);
      await r.save(<Collection>[
        Collection(interestId: 'dino', entries: <CollectionEntry>[
          CollectionEntry(id: 'e1', interestId: 'dino', name: 'T. Rex', shownAt: t, note: 'big'),
          CollectionEntry(id: 'e2', interestId: 'dino', name: 'Stego', shownAt: t),
        ]),
        const Collection(interestId: 'rocks', entries: <CollectionEntry>[]),
      ]);
      final List<Collection> back = (await r.load())!;
      expect(back.map((Collection c) => c.interestId), <String>['dino', 'rocks']);
      expect(back.first.entries.first.note, 'big');
      expect(back.first.entries.last.note, isNull);
      expect(back.first.entries.first.shownAt, t);
      expect(back.last.entries, isEmpty, reason: 'saved-and-empty is different from never-saved');
    });
  });

  group('outbox', () {
    test('items round-trip with attempts and lastError; queue semantics stay in offline_outbox.dart', () async {
      final OutboxRepository r = OutboxRepository(_ns('outbox'));
      expect(await r.load(), isEmpty);
      final List<OutboxItem> items = <OutboxItem>[
        OutboxItem(id: 'a', kind: OutboxKind.drawing, createdAt: DateTime.utc(2026, 1, 1), payload: <String, Object?>{'k': 1}),
        OutboxItem(id: 'b', kind: OutboxKind.message, createdAt: DateTime.utc(2026, 1, 2), payload: 'hi', attempts: 3, lastError: 'offline'),
      ];
      expect(await r.save(items), 0);
      final List<OutboxItem> back = await r.load();
      expect(back.map((OutboxItem i) => i.id), <String>['a', 'b']);
      expect(back[1].attempts, 3);
      expect(back[1].lastError, 'offline');
      expect(back[0].kind, OutboxKind.drawing);
      // The restored list still drives the real state machine.
      expect(nextToSend(back)!.id, 'a');
    });

    test('an item with a non-JSON payload (raw bytes) cannot be written down, and says so', () async {
      final OutboxRepository r = OutboxRepository(_ns('outbox'));
      final int skipped = await r.save(<OutboxItem>[
        OutboxItem(id: 'ok', kind: OutboxKind.show, createdAt: DateTime.utc(2026), payload: 'fine'),
        OutboxItem(id: 'bytes', kind: OutboxKind.message, createdAt: DateTime.utc(2026), payload: Uint8List(4)),
      ]);
      expect(skipped, 1);
      expect((await r.load()).map((OutboxItem i) => i.id), <String>['ok']);
    });

    test('jsonSafe accepts plain JSON and rejects everything else', () {
      expect(jsonSafe(<String, Object?>{'a': <Object?>[1, 2.5, 'x', null, true]}), isA<Map<String, Object?>>());
      expect(() => jsonSafe(Object()), throwsFormatException);
      expect(() => jsonSafe(double.infinity), throwsFormatException);
      expect(() => jsonSafe(<Object?, Object?>{1: 'x'}), throwsFormatException);
    });
  });


  group('profile cache and the offline-first onboarding answer (audit C-06)', () {
    test('the cache keeps a name, an age, the onboarding bit and the grown-up\'s overrides', () async {
      final ProfileCacheRepository r = ProfileCacheRepository(_ns('profile'));
      expect(await r.load(), isNull);
      await r.rememberHome(displayName: 'Ivy', yearsOld: 8, overrides: <String, Object?>{'hidden': <Object?>['tile:homework']});
      await r.markOnboarded();
      final ProfileCache c = (await r.load())!;
      expect(c.displayName, 'Ivy');
      expect(c.yearsOld, 8);
      expect(c.hasOnboarded, isTrue);
      expect(c.overrides, <String, Object?>{'hidden': <Object?>['tile:homework']});
    });

    test('server says yes -> true and remembered; a later offline boot still says yes', () async {
      final ProfileCacheRepository r = ProfileCacheRepository(_ns('profile'));
      expect(await resolveHasOnboarded(fetch: () async => true, cache: r), isTrue);
      expect(await resolveHasOnboarded(fetch: () async => throw StateError('no signal'), cache: r), isTrue,
          reason: 'an onboarded child who boots offline does not restart onboarding');
    });

    test('a device that never heard a yes still fails CLOSED when offline', () async {
      final ProfileCacheRepository r = ProfileCacheRepository(_ns('profile'));
      expect(await resolveHasOnboarded(fetch: () async => throw StateError('no signal'), cache: r), isFalse);
    });

    test('server says NO -> false (the server wins) and the cache follows it', () async {
      final ProfileCacheRepository r = ProfileCacheRepository(_ns('profile'));
      await r.markOnboarded();
      expect(await resolveHasOnboarded(fetch: () async => false, cache: r), isFalse);
      expect((await r.load())!.hasOnboarded, isFalse);
      expect(await resolveHasOnboarded(fetch: () async => throw StateError('no signal'), cache: r), isFalse,
          reason: 'after the server said no, offline does not resurrect a stale yes');
    });

    test('a full or broken cache never turns a good server answer into a crash', () async {
      final LocalNamespace tiny = LocalServices.memory().store.open(const NamespaceSpec(name: 'child.x.profile', maxBytes: 5));
      final ProfileCacheRepository r = ProfileCacheRepository(tiny);
      expect(await resolveHasOnboarded(fetch: () async => true, cache: r), isTrue);
    });

    test('the cache keeps the name and overrides when only the onboarding answer changes', () async {
      final ProfileCacheRepository r = ProfileCacheRepository(_ns('profile'));
      await r.rememberHome(displayName: 'Ivy', yearsOld: 9);
      await resolveHasOnboarded(fetch: () async => true, cache: r);
      final ProfileCache c = (await r.load())!;
      expect(c.displayName, 'Ivy');
      expect(c.hasOnboarded, isTrue);
    });
  });
}
