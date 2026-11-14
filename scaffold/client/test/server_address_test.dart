// The "Server address" setting's rules: https only, an origin only, saved in
// LocalStore, the build-time address as the default, and the transport policy
// (a release build with NO pins accepts https and still refuses http).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/server_address.dart';
import 'package:olive_client/server_transport_policy.dart';

void main() {
  late LocalServices services;

  setUp(() {
    ServerAddress.resetInMemory();
    services = LocalServices.memory(childId: 'ivy');
  });
  tearDown(() {
    ServerAddress.resetInMemory();
    OliveTransport.resetForTesting();
  });

  test('with nothing saved, the built-in (build-time) address is used', () {
    expect(ServerAddress.override, isNull);
    expect(ServerAddress.usingOverride, isFalse);
    expect(ServerAddress.current, kBuiltInBaseUrl);
  });

  test('a good https address is accepted and normalised to an origin', () {
    for (final (input, want) in <(String, String)>[
      ('https://karen-expand.trycloudflare.com', 'https://karen-expand.trycloudflare.com'),
      ('  https://Karen-Expand.TryCloudflare.com/  ', 'https://karen-expand.trycloudflare.com'),
      ('https://api.example.com:8443', 'https://api.example.com:8443'),
    ]) {
      expect(ServerAddress.problem(input), isNull, reason: input);
      expect(ServerAddress.normalise(input), want, reason: input);
    }
  });

  test('anything that is not a plain https origin is refused, http always', () {
    for (final bad in <String>[
      '', '   ', 'example.com', 'http://example.com', 'http://127.0.0.1:8123',
      'http://192.168.1.20:8123', 'http://10.0.2.2:8123', 'ftp://example.com', 'ws://example.com',
      'https://', 'https://localhost', 'https://u:p@example.com', 'https://example.com?x=1',
      'https://example.com#f', 'https://example.com/v1', 'https://example.com/a/b',
      'https://exa mple.com', 'javascript:alert(1)',
    ]) {
      expect(ServerAddress.problem(bad), isNotNull, reason: bad);
      expect(ServerAddress.normalise(bad), isNull, reason: bad);
    }
  });

  test('save stores the origin in the device.serveraddress namespace and switches current', () async {
    final ns = services.area(kServerAddressArea);
    expect(await ServerAddress.save(ns, ' https://a.example.com/ '), isNull);
    expect(ServerAddress.current, 'https://a.example.com');
    expect(await ns.get('url'), 'https://a.example.com');
    expect(services.namespaceName(localDataEntry(kServerAddressArea)), 'device.serveraddress');
    // Plain, not encrypted: it is not a secret.
    expect(localDataEntry(kServerAddressArea).encrypted, isFalse);
  });

  test('a refused address is not saved and does not change what is in use', () async {
    final ns = services.area(kServerAddressArea);
    await ServerAddress.save(ns, 'https://a.example.com');
    expect(await ServerAddress.save(ns, 'http://evil.example.com'), isNotNull);
    expect(ServerAddress.current, 'https://a.example.com');
    expect(await ns.get('url'), 'https://a.example.com');
  });

  test('reset ("Use the built-in address") removes it', () async {
    final ns = services.area(kServerAddressArea);
    await ServerAddress.save(ns, 'https://a.example.com');
    await ServerAddress.reset(ns);
    expect(ServerAddress.current, kBuiltInBaseUrl);
    expect(await ns.get('url'), isNull);
  });

  test('load restores a saved address at start-up and ignores a bad stored value', () async {
    final ns = services.area(kServerAddressArea);
    await ns.put('url', 'https://saved.example.com');
    await ServerAddress.load(ns);
    expect(ServerAddress.current, 'https://saved.example.com');

    await ns.put('url', 'http://tampered.example.com'); // someone edited the file
    await ServerAddress.load(ns);
    expect(ServerAddress.current, kBuiltInBaseUrl);

    await ns.put('url', 42);
    await ServerAddress.load(ns);
    expect(ServerAddress.current, kBuiltInBaseUrl);
  });

  test('bootLoad reads the real directory-backed store (and never throws)', () async {
    final dir = Directory.systemTemp.createTempSync('olive_server_addr');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(backend: DirectoryStoreBackend(dir));
    final ns = store.open(const NamespaceSpec(name: 'device.serveraddress', maxBytes: 4096));
    await ns.put('url', 'https://disk.example.com');
    await ServerAddress.bootLoad(rootOverride: dir);
    expect(ServerAddress.current, 'https://disk.example.com');

    ServerAddress.resetInMemory();
    final empty = Directory.systemTemp.createTempSync('olive_server_addr_empty');
    addTearDown(() => empty.deleteSync(recursive: true));
    await ServerAddress.bootLoad(rootOverride: empty);
    expect(ServerAddress.current, kBuiltInBaseUrl);
  });

  test('a device wipe forgets the in-memory choice too', () async {
    await ServerAddress.save(services.area(kServerAddressArea), 'https://a.example.com');
    await services.wipeAll();
    expect(ServerAddress.current, kBuiltInBaseUrl);
  });

  group('transport policy: release build, certificate pinning OFF (no pins)', () {
    setUp(() {
      OliveTransport.policy = const OliveTransportPolicy(release: true);
      OliveTransport.pins = PinSet.empty;
    });

    test('an https address works with no pins configured', () {
      expect(OliveTransport.refusalFor('https://karen-expand.trycloudflare.com'), isNull);
      expect(OliveTransport.clientFor('https://karen-expand.trycloudflare.com'),
          isNot(isA<RefusingClient>()));
    });

    test('http is still refused, loopback and LAN included', () {
      for (final u in <String>[
        'http://karen-expand.trycloudflare.com', 'http://127.0.0.1:8123',
        'http://10.0.2.2:8123', 'http://192.168.1.20:8123',
      ]) {
        expect(OliveTransport.refusalFor(u), contains('release'), reason: u);
        expect(OliveTransport.clientFor(u), isA<RefusingClient>(), reason: u);
      }
    });

    test('every address the setting accepts is one the transport accepts', () {
      for (final u in <String>['https://a.example.com', 'https://a.example.com:8443']) {
        expect(ServerAddress.normalise(u), isNotNull);
        expect(OliveTransport.refusalFor(ServerAddress.normalise(u)!), isNull);
      }
    });
  });
}
