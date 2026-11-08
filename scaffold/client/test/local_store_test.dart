// OLIVE BRANCH — LocalStore tests: atomic, versioned, bounded, safe on
// corruption, sealed for private namespaces. Every refusal is a real assertion.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

class _MemorySecure implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

Uint8List _key([int fill = 7]) => Uint8List.fromList(List<int>.filled(32, fill));
Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

LocalStore _store(MemoryStoreBackend b, {int keyFill = 7}) =>
    LocalStore(backend: b, cipher: AesGcmStoreCipher(_key(keyFill)));

void main() {
  group('names and keys', () {
    test('namespace names are a safe, separator-free alphabet', () {
      for (final String ok in <String>['journal', 'child.abc-1.journal', 'a', 'x_y.z-9']) {
        expect(isValidNamespaceName(ok), isTrue, reason: ok);
      }
      for (final String bad in <String>[
        '', 'Journal', '../etc', 'a/b', 'a\\b', 'a..b', '.hidden', '-x', 'a b', 'é', 'x' * 121,
      ]) {
        expect(isValidNamespaceName(bad), isFalse, reason: bad);
      }
    });

    test('an illegal namespace or key is refused, never turned into a path', () {
      final LocalStore s = _store(MemoryStoreBackend());
      expect(() => s.open(const NamespaceSpec(name: '../x')), throwsA(isA<LocalStoreBadName>()));
      final LocalNamespace ns = s.open(const NamespaceSpec(name: 'ok'));
      expect(ns.put('bad/key', 1), throwsA(isA<LocalStoreBadName>()));
      expect(ns.get(''), throwsA(isA<LocalStoreBadName>()));
    });
  });

  group('basic get / put / delete / list', () {
    test('round-trips JSON, lists keys sorted, deletes, and hands out copies', () async {
      final LocalNamespace ns = _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't'));
      expect(await ns.get('a'), isNull);
      await ns.put('b', <String, Object?>{'n': 1, 'l': <Object?>[1, 'two', null]});
      await ns.put('a', 'text');
      expect(await ns.list(), <String>['a', 'b']);
      expect(await ns.get('b'), <String, Object?>{'n': 1, 'l': <Object?>[1, 'two', null]});
      final Object? copy = await ns.get('b');
      (copy! as Map<String, Object?>)['n'] = 99;
      expect(((await ns.get('b'))! as Map<String, Object?>)['n'], 1, reason: 'callers get a private copy');
      await ns.delete('a');
      await ns.delete('never-existed'); // a no-op, not an error
      expect(await ns.list(), <String>['b']);
    });

    test('a value that is not plain JSON is refused and nothing is stored', () async {
      final LocalNamespace ns = _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't'));
      await expectLater(ns.put('k', Object()), throwsA(isA<LocalStoreNotJson>()));
      await expectLater(ns.put('k', double.nan), throwsA(isA<LocalStoreNotJson>()));
      expect(await ns.list(), isEmpty);
    });

    test('concurrent writers never lose an update (writes are serialized)', () async {
      final LocalNamespace ns = _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't'));
      await Future.wait(<Future<void>>[for (int i = 0; i < 25; i++) ns.put('k$i', i)]);
      expect((await ns.list()).length, 25);
    });

    test('typed codec: decode failures read as absent, never a crash', () async {
      final LocalNamespace ns = _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't'));
      const StoreCodec<int> codec = StoreCodec<int>(
          encode: _enc, decode: _dec);
      await ns.putTyped<int>('n', 5, codec);
      await ns.put('bad', 'not an int');
      expect(await ns.getTyped<int>('n', codec), 5);
      expect(await ns.getTyped<int>('bad', codec), isNull);
      expect(await ns.getTyped<int>('missing', codec), isNull);
      expect(await ns.listTyped<int>(codec), <int>[5]);
    });
  });

  group('persistence across a restart', () {
    test('a second store over the same backend sees what the first wrote', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(const NamespaceSpec(name: 't')).put('k', 'v');
      expect(await _store(b).open(const NamespaceSpec(name: 't')).get('k'), 'v');
    });

    test('namespaces are isolated from each other', () async {
      final LocalStore s = _store(MemoryStoreBackend());
      await s.open(const NamespaceSpec(name: 'child.a.journal')).put('k', 'A');
      await s.open(const NamespaceSpec(name: 'child.b.journal')).put('k', 'B');
      expect(await s.open(const NamespaceSpec(name: 'child.a.journal')).get('k'), 'A');
      expect(await s.open(const NamespaceSpec(name: 'child.b.journal')).get('k'), 'B');
    });

    test('the real directory backend round-trips, replaces atomically, leaves no .tmp', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_store_test_');
      addTearDown(() => dir.delete(recursive: true));
      final LocalStore s = LocalStore(backend: DirectoryStoreBackend(dir), cipher: AesGcmStoreCipher(_key()));
      final LocalNamespace ns = s.open(const NamespaceSpec(name: 'child.x.lists'));
      await ns.put('wants', <Object?>['a']);
      await ns.put('wants', <Object?>['a', 'b']);
      final LocalStore again = LocalStore(backend: DirectoryStoreBackend(dir), cipher: AesGcmStoreCipher(_key()));
      expect(await again.open(const NamespaceSpec(name: 'child.x.lists')).get('wants'), <Object?>['a', 'b']);
      final List<String> names = dir.listSync().map((FileSystemEntity e) => e.uri.pathSegments.last).toList();
      expect(names, <String>['child.x.lists.json']);
      expect(await again.namespaces(), <String>['child.x.lists']);
    });

    test('a stale .tmp from a crashed write is never read as data', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_store_test_');
      addTearDown(() => dir.delete(recursive: true));
      final LocalStore s = LocalStore(backend: DirectoryStoreBackend(dir));
      await s.open(const NamespaceSpec(name: 't')).put('k', 'good');
      await File('${dir.path}${Platform.pathSeparator}t.json.tmp').writeAsString('{"half written');
      final LocalStore again = LocalStore(backend: DirectoryStoreBackend(dir));
      final LocalNamespace ns = again.open(const NamespaceSpec(name: 't'));
      expect(await ns.get('k'), 'good');
      expect(ns.recovery, RecoveryKind.none);
    });
  });

  group('corruption is safe, never fatal', () {
    test('unparseable bytes: namespace starts empty, a copy is quarantined, app keeps going', () async {
      final MemoryStoreBackend b = MemoryStoreBackend()..plant('t', _bytes('{not json'));
      final LocalNamespace ns = _store(b).open(const NamespaceSpec(name: 't'));
      expect(await ns.list(), isEmpty);
      expect(ns.recovery, RecoveryKind.corrupt);
      expect(await _store(b).quarantined(), 1);
      await ns.put('k', 'fresh'); // and it is writable again
      expect(await ns.get('k'), 'fresh');
    });

    test('valid JSON of the wrong shape is corrupt too', () async {
      for (final String body in <String>['[]', '{"olive_store":1}', '{"olive_store":1,"schema":1,"enc":false,"data":[]}',
        '{"olive_store":2,"schema":1,"enc":false,"data":{}}', '{"olive_store":1,"schema":0,"enc":false,"data":{}}']) {
        final MemoryStoreBackend b = MemoryStoreBackend()..plant('t', _bytes(body));
        final LocalNamespace ns = _store(b).open(const NamespaceSpec(name: 't'));
        expect(await ns.list(), isEmpty, reason: body);
        expect(ns.recovery, RecoveryKind.corrupt, reason: body);
      }
    });

    test('a file written by a NEWER schema is preserved in quarantine, not trusted or destroyed', () async {
      final MemoryStoreBackend b = MemoryStoreBackend()
        ..plant('t', _bytes('{"olive_store":1,"schema":9,"enc":false,"data":{"k":"future"}}'));
      final LocalNamespace ns = _store(b).open(const NamespaceSpec(name: 't', schema: 2));
      expect(await ns.get('k'), isNull);
      expect(ns.recovery, RecoveryKind.newerSchema);
      expect(await _store(b).quarantined(), 1);
    });

    test('the quarantine copy on a real disk is the original bytes', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_store_test_');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}${Platform.pathSeparator}t.json').writeAsString('garbage!');
      final LocalStore s = LocalStore(backend: DirectoryStoreBackend(dir));
      expect(await s.open(const NamespaceSpec(name: 't')).list(), isEmpty);
      final Directory q = Directory('${dir.path}${Platform.pathSeparator}quarantine');
      final List<File> files = q.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.readAsStringSync(), 'garbage!');
      expect(await s.quarantined(), 1);
    });
  });

  group('versioning and migrations', () {
    test('an older file is migrated step by step and rewritten at the new version', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(const NamespaceSpec(name: 't', schema: 1)).put('n', 1);
      final LocalStore upgraded = _store(b);
      final LocalNamespace ns = upgraded.open(NamespaceSpec(
        name: 't',
        schema: 3,
        migrations: <int, Migration>{
          1: (Map<String, Object?> d) => <String, Object?>{for (final MapEntry<String, Object?> e in d.entries) e.key: (e.value as int) + 10},
          2: (Map<String, Object?> d) => <String, Object?>{...d, 'added': true},
        },
      ));
      expect(await ns.get('n'), 11);
      expect(await ns.get('added'), true);
      expect(ns.recovery, RecoveryKind.none);
      // Rewritten: a reader that only knows schema 3 now opens it with NO migrations.
      final LocalNamespace plain = _store(b).open(const NamespaceSpec(name: 't', schema: 3));
      expect(await plain.get('n'), 11);
      expect((jsonDecode(utf8.decode(b.rawFor('t')!)) as Map<String, dynamic>)['schema'], 3);
    });

    test('a missing migration step quarantines instead of guessing', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(const NamespaceSpec(name: 't', schema: 1)).put('n', 1);
      final LocalNamespace ns = _store(b).open(const NamespaceSpec(name: 't', schema: 2));
      expect(await ns.get('n'), isNull);
      expect(ns.recovery, RecoveryKind.missingMigration);
      expect(await _store(b).quarantined(), 1);
    });
  });

  group('size bounds', () {
    test('a write past the ceiling is refused and leaves what was stored untouched', () async {
      final LocalNamespace ns =
          _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't', maxBytes: 200));
      await ns.put('small', 'x' * 50);
      await expectLater(ns.put('big', 'y' * 500), throwsA(isA<LocalStoreFull>()));
      expect(await ns.list(), <String>['small']);
      expect(await ns.get('small'), 'x' * 50);
    });

    test('nothing is evicted to make room: filling up fails the NEW write only', () async {
      final LocalNamespace ns =
          _store(MemoryStoreBackend()).open(const NamespaceSpec(name: 't', maxBytes: 300));
      int stored = 0;
      for (int i = 0; i < 50; i++) {
        try {
          await ns.put('k$i', 'v' * 40);
          stored++;
        } on LocalStoreFull {
          break;
        }
      }
      expect(stored, greaterThan(0));
      expect((await ns.list()).length, stored);
    });
  });

  group('encryption at rest for private namespaces', () {
    const NamespaceSpec priv = NamespaceSpec(name: 'child.a.journal', encrypted: true);

    test('the bytes on disk never contain the plaintext, and it reads back', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(priv).put('e1', <String, Object?>{'body': 'my secret diary words'});
      final String onDisk = utf8.decode(b.rawFor('child.a.journal')!, allowMalformed: true);
      expect(onDisk, isNot(contains('secret')));
      expect(onDisk, isNot(contains('diary')));
      expect(onDisk, contains('"enc":true'));
      expect(await _store(b).open(priv).get('e1'), <String, Object?>{'body': 'my secret diary words'});
    });

    test('two seals of the same data differ (fresh nonce each write)', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      final LocalNamespace ns = _store(b).open(priv);
      await ns.put('k', 'v');
      final Uint8List first = b.rawFor('child.a.journal')!;
      await ns.put('k', 'v');
      expect(b.rawFor('child.a.journal'), isNot(equals(first)));
    });

    test('opening a private namespace with no cipher is refused, never plaintext', () {
      final LocalStore noCipher = LocalStore(backend: MemoryStoreBackend());
      expect(() => noCipher.open(priv), throwsA(isA<LocalStoreException>()));
    });

    test('a tampered file fails authentication: quarantined, namespace empty', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(priv).put('k', 'v');
      final Map<String, dynamic> env = jsonDecode(utf8.decode(b.rawFor('child.a.journal')!)) as Map<String, dynamic>;
      final Uint8List box = base64Decode(env['box'] as String);
      box[box.length ~/ 2] ^= 0x01;
      env['box'] = base64Encode(box);
      b.plant('child.a.journal', _bytes(jsonEncode(env)));
      final LocalNamespace ns = _store(b).open(priv);
      expect(await ns.get('k'), isNull);
      expect(ns.recovery, RecoveryKind.corrupt);
      expect(await _store(b).quarantined(), 1);
    });

    test('a different key cannot read it (the lost-key case is quarantined, not a crash)', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b, keyFill: 1).open(priv).put('k', 'v');
      final LocalNamespace ns = _store(b, keyFill: 2).open(priv);
      expect(await ns.get('k'), isNull);
      expect(ns.recovery, RecoveryKind.corrupt);
    });

    test('a sealed file moved to another namespace will not open there (name is bound in)', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      await _store(b).open(priv).put('k', 'v');
      b.plant('child.b.journal', b.rawFor('child.a.journal')!);
      final LocalNamespace other = _store(b).open(const NamespaceSpec(name: 'child.b.journal', encrypted: true));
      expect(await other.get('k'), isNull);
      expect(other.recovery, RecoveryKind.corrupt);
    });

    test('a plaintext file in a namespace declared private is never read as data', () async {
      final MemoryStoreBackend b = MemoryStoreBackend()
        ..plant('child.a.journal', _bytes('{"olive_store":1,"schema":1,"enc":false,"data":{"k":"planted"}}'));
      final LocalNamespace ns = _store(b).open(priv);
      expect(await ns.get('k'), isNull);
      expect(ns.recovery, RecoveryKind.corrupt);
    });

    test('reopening a namespace with a different encryption setting is refused', () {
      final LocalStore s = _store(MemoryStoreBackend());
      s.open(priv);
      expect(() => s.open(const NamespaceSpec(name: 'child.a.journal')), throwsA(isA<LocalStoreBadName>()));
    });
  });

  group('the cipher and its keyring', () {
    test('AES-GCM round-trips, binds associated data, rejects a wrong key', () async {
      final AesGcmStoreCipher c = AesGcmStoreCipher(_key());
      final Uint8List box = await c.seal(_bytes('hello'), _bytes('ns-a'));
      expect(utf8.decode(await c.open(box, _bytes('ns-a'))), 'hello');
      await expectLater(c.open(box, _bytes('ns-b')), throwsA(anything));
      await expectLater(AesGcmStoreCipher(_key(9)).open(box, _bytes('ns-a')), throwsA(anything));
      expect(() => AesGcmStoreCipher(<int>[1, 2, 3]), throwsArgumentError);
    });

    test('the keyring creates a key once, reuses it, and erase makes old data unreadable', () async {
      final _MemorySecure secure = _MemorySecure();
      final StoreCipherKeyring ring = StoreCipherKeyring(secure);
      final StoreCipher first = await ring.cipher();
      final Uint8List box = await first.seal(_bytes('x'), _bytes('a'));
      expect(secure.data.keys, <String>[StoreCipherKeyring.keyName]);
      final StoreCipher second = await StoreCipherKeyring(secure).cipher();
      expect(utf8.decode(await second.open(box, _bytes('a'))), 'x');
      await ring.erase();
      expect(secure.data, isEmpty);
      final StoreCipher fresh = await ring.cipher();
      await expectLater(fresh.open(box, _bytes('a')), throwsA(anything));
    });

    test('a damaged stored key is replaced rather than crashing boot', () async {
      final _MemorySecure secure = _MemorySecure()..data[StoreCipherKeyring.keyName] = 'not base64 !!';
      final StoreCipher c = await StoreCipherKeyring(secure).cipher();
      expect(utf8.decode(await c.open(await c.seal(_bytes('y'), _bytes('a')), _bytes('a'))), 'y');
    });
  });

  group('wipe', () {
    test('wipe removes every document and quarantined copy; prefix delete removes one profile', () async {
      final MemoryStoreBackend b = MemoryStoreBackend()..plant('junk', _bytes('{bad'));
      final LocalStore s = _store(b);
      await s.open(const NamespaceSpec(name: 'child.a.lists')).put('k', 1);
      await s.open(const NamespaceSpec(name: 'child.b.lists')).put('k', 2);
      await s.open(const NamespaceSpec(name: 'junk')).list(); // quarantines junk
      expect(await s.quarantined(), 1);

      await s.deleteWithPrefix('child.a.');
      expect(await s.open(const NamespaceSpec(name: 'child.a.lists')).get('k'), isNull);
      expect(await s.open(const NamespaceSpec(name: 'child.b.lists')).get('k'), 2);

      await s.wipe();
      expect(await s.namespaces(), isEmpty);
      expect(await s.quarantined(), 0);
      expect(await s.open(const NamespaceSpec(name: 'child.b.lists')).get('k'), isNull,
          reason: 'in-memory caches are dropped too, not just the files');
    });

    test('a wiped namespace is writable again', () async {
      final LocalStore s = _store(MemoryStoreBackend());
      final LocalNamespace ns = s.open(const NamespaceSpec(name: 't'));
      await ns.put('k', 1);
      await s.wipe();
      await ns.put('k', 2);
      expect(await ns.get('k'), 2);
    });
  });
}

Object? _enc(int v) => v;
int _dec(Object? j) => j as int;
