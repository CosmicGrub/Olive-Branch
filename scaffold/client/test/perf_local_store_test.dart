// OLIVE BRANCH — LocalStore startup and write cost (on-device performance pass).
//
//  1. Startup is lazy: building the services and opening a namespace reads
//     NOTHING from disk; the first access reads that one namespace once and
//     every later access is served from memory. (An audit suspected the app
//     read every namespace at boot; it does not, and this keeps it so.)
//  2. A put serialises the document once. The file it writes is the same
//     envelope the previous build wrote (same keys, same order), for plain and
//     sealed namespaces, including text that needs JSON escaping.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

/// A memory backend that counts how often each document is read.
class CountingBackend extends MemoryStoreBackend {
  final Map<String, int> reads = <String, int>{};
  int get totalReads => reads.values.fold(0, (int a, int b) => a + b);
  @override
  Future<Uint8List?> read(String name) {
    reads[name] = (reads[name] ?? 0) + 1;
    return super.read(name);
  }
}

LocalStore storeOver(MemoryStoreBackend b) =>
    LocalStore(backend: b, cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey()));

void main() {
  group('startup reads nothing until a namespace is used', () {
    test('services construction and opening areas touch no document', () async {
      final CountingBackend b = CountingBackend();
      final LocalServices s = LocalServices(
          store: storeOver(b), childId: 'kid1', isLive: true, demoSeeds: false);
      for (final String area in <String>['journal', 'pictures', 'care', 'growing', 'family', 'outbox']) {
        s.area(area);
      }
      expect(b.totalReads, 0, reason: 'opening is declaring, not loading');
    });

    test('the first access reads that namespace once; later accesses are served from memory', () async {
      final CountingBackend b = CountingBackend();
      final LocalServices s = LocalServices(
          store: storeOver(b), childId: 'kid1', isLive: true, demoSeeds: false);
      final LocalNamespace j = s.area('journal');
      await j.put('a', <String, Object?>{'x': 1});
      final int afterFirst = b.totalReads;
      expect(afterFirst, 1, reason: 'exactly one read, for the namespace touched');
      expect(b.reads.keys.single, contains('journal'));
      await j.get('a');
      await j.list();
      await j.put('b', 2);
      expect(b.totalReads, afterFirst, reason: 'cached after the first load');
    });
  });

  group('a put writes the same envelope as before', () {
    const String tricky = 'quote " backslash \\ newline \n tab \t unicode é中\u{1F33F} </script>';

    test('plain namespace: same keys in the same order, data round-trips', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      final LocalNamespace ns = storeOver(b).open(const NamespaceSpec(name: 'device.plain', schema: 3));
      await ns.put('k', <String, Object?>{'body': tricky, 'n': 1.5, 'list': <int>[1, 2]});
      final Map<String, dynamic> file = jsonDecode(utf8.decode(b.rawFor('device.plain')!)) as Map<String, dynamic>;
      expect(file.keys.toList(), <String>['olive_store', 'schema', 'enc', 'data']);
      expect(file['olive_store'], 1);
      expect(file['schema'], 3);
      expect(file['enc'], false);
      expect((file['data'] as Map)['k'], <String, Object?>{'body': tricky, 'n': 1.5, 'list': <int>[1, 2]});
      // A fresh store over the same bytes reads it back.
      final LocalNamespace again = storeOver(b).open(const NamespaceSpec(name: 'device.plain', schema: 3));
      expect(await again.get('k'), <String, Object?>{'body': tricky, 'n': 1.5, 'list': <int>[1, 2]});
    });

    test('sealed namespace: no plaintext on disk, opens again with the same key', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      final AesGcmStoreCipher cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
      final LocalNamespace ns = LocalStore(backend: b, cipher: cipher)
          .open(const NamespaceSpec(name: 'child.k.journal', encrypted: true));
      await ns.put('k', <String, Object?>{'body': tricky});
      final String text = utf8.decode(b.rawFor('child.k.journal')!);
      expect(text.contains('quote'), isFalse);
      final Map<String, dynamic> file = jsonDecode(text) as Map<String, dynamic>;
      expect(file.keys.toList(), <String>['olive_store', 'schema', 'enc', 'box']);
      expect(file['enc'], true);
      final LocalNamespace again = LocalStore(backend: b, cipher: cipher)
          .open(const NamespaceSpec(name: 'child.k.journal', encrypted: true));
      expect(await again.get('k'), <String, Object?>{'body': tricky});
    });

    test('the ceiling is still measured on the serialised document and refuses without writing', () async {
      final MemoryStoreBackend b = MemoryStoreBackend();
      final LocalNamespace ns =
          storeOver(b).open(const NamespaceSpec(name: 'device.tiny', maxBytes: 64));
      await ns.put('a', 'x' * 20);
      final Uint8List? before = b.rawFor('device.tiny');
      await expectLater(ns.put('b', 'y' * 60), throwsA(isA<LocalStoreFull>()));
      expect(b.rawFor('device.tiny'), before, reason: 'the stored file is untouched');
      expect(await ns.list(), <String>['a']);
    });
  });
}
