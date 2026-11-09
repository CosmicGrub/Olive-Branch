// OLIVE BRANCH — the dealer's save: where it lives, what it may never hold, and that the wipe covers it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/clear_local_data_screen.dart' show kLocalDataAreaNames;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/play_save.dart';

void main() {
  group('the playsave area', () {
    test('is catalogued as a sealed child area with a small ceiling, and the wipe screen has a plain name for it', () {
      final e = localDataEntry('playsave');
      expect(e.scope, LocalScope.child);
      expect(e.encrypted, isTrue);
      expect(e.maxBytes, 64 * 1024);
      expect(kLocalDataAreaNames['playsave'], 'Games in progress');
      final what = e.what.toLowerCase();
      expect(what, contains('no winner, result or score'));
      expect(what, contains('never uploaded'));
    });

    test('MASTERFILE section 8.16.4 and section 22.1 describe exactly this catalogue (the count of areas and the sealed ones)', () {
      final doc = File('../../MASTERFILE.md').readAsStringSync();
      final sealed = localDataCatalogue.where((e) => e.encrypted).length;
      expect(doc, contains('**${localDataCatalogue.length} areas, $sealed of them sealed**'));
      expect(doc, contains('| `child.<id>.playsave` |'));
    });
  });

  group('LocalPlaySaveStore', () {
    late LocalServices services;
    late MemoryStoreBackend backend;
    late LocalPlaySaveStore store;

    setUp(() {
      backend = MemoryStoreBackend();
      services = LocalServices.memory(childId: 'ivy', backend: backend);
      store = LocalPlaySaveStore(services.area('playsave'));
    });

    final snap = <String, dynamic>{'columns': ['b', '', 'a', '', '', '', ''], 'toMove': 'b', 'first': 'b'};

    test('saves, loads and clears one game per kind', () async {
      expect(await store.load('connect4'), isNull);
      expect(await store.save('connect4', snap), isTrue);
      expect(await store.load('connect4'), snap);
      expect(await store.load('uno'), isNull);
      await store.clear('connect4');
      expect(await store.load('connect4'), isNull);
    });

    test('is sealed on disk: the board is not readable in the stored file', () async {
      await store.save('connect4', snap);
      final name = services.namespaceName(localDataEntry('playsave'));
      final bytes = await backend.read(name);
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!, allowMalformed: true), isNot(contains('columns')));
    });

    test('refuses a snapshot that carries an outcome, a winner, a result, a score or a tally, at any depth', () async {
      for (final bad in <String>['winner', 'outcome', 'result', 'won', 'lost', 'tally', 'history', 'score', 'streak', 'Points']) {
        expect(await store.save('connect4', <String, dynamic>{'columns': <String>[], 'extra': <String, dynamic>{bad: 1}}), isFalse, reason: bad);
      }
      expect(await store.load('connect4'), isNull, reason: 'nothing was written');
    });

    test('a refused snapshot leaves the previous save as it was', () async {
      await store.save('connect4', snap);
      expect(await store.save('connect4', <String, dynamic>{'winner': 'a'}), isFalse);
      expect(await store.load('connect4'), snap);
    });

    test('a value that is not a save reads as no save, never as a crash', () async {
      await services.area('playsave').put('connect4', 'garbage');
      expect(await store.load('connect4'), isNull);
      await services.area('playsave').put('connect4', <String, Object?>{'v': 2, 'game': 'connect4', 'state': snap});
      expect(await store.load('connect4'), isNull);
      await services.area('playsave').put('connect4', <String, Object?>{'v': 1, 'game': 'uno', 'state': snap});
      expect(await store.load('connect4'), isNull, reason: 'a save for another game is not this game\'s');
    });

    test('the device wipe and forgetting the child both remove it', () async {
      await store.save('connect4', snap);
      await services.forgetChild('ivy');
      expect(await LocalPlaySaveStore(services.area('playsave')).load('connect4'), isNull);
      await store.save('uno', snap);
      await services.wipeAll();
      expect(await LocalPlaySaveStore(services.area('playsave')).load('uno'), isNull);
    });
  });

  test('playSaveAcceptable is strict about size, depth and shape', () {
    expect(playSaveAcceptable(<String, dynamic>{'pad': 'x' * (maxPlaySaveBytes + 1)}), isFalse);
    expect(playSaveAcceptable(<String, dynamic>{'bad': Object()}), isFalse);
    expect(playSaveAcceptable(<String, dynamic>{'a': 1}), isTrue);
    expect(playSaveAcceptable(<String, dynamic>{'a': <Object?>[<String, dynamic>{'score': 1}]}), isFalse);
    var deep = <String, dynamic>{'x': 1};
    for (var i = 0; i < 20; i++) {
      deep = <String, dynamic>{'d': deep};
    }
    expect(playSaveAcceptable(deep), isFalse);
  });
}
