// OLIVE BRANCH — local_session.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2. Real dart:io networking on 127.0.0.1 — no
// platform channel involved (unlike local_discovery.dart's real mDNS,
// which needs a real device — see this file's own scope note at the
// bottom), so this is a genuine round-trip test, not a mock.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_discovery.dart';
import 'package:olive_client/local_session.dart';

void main() {
  group('LocalSessionServer / LocalSessionClient — a real HTTP round-trip', () {
    test('a real turn payload is received exactly as sent', () async {
      LocalTurnPayload? received;
      final server = LocalSessionServer(onTurnReceived: (p) => received = p);
      await server.start();
      addTearDown(server.stop);

      final peer = LocalPeer(host: '127.0.0.1', port: server.port!, role: 'ivy', name: 'Ivy');
      await LocalSessionClient(peer).sendTurn({'currentPrompt': 'Think of something.', 'rounds': 0, 'leader': 'b'});

      // A real HTTP round-trip needs a tick to land on the listener side.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isNotNull);
      expect(received!['currentPrompt'], 'Think of something.');
      expect(received!['rounds'], 0);
      expect(received!['leader'], 'b');
    });

    test('multiple real turns arrive in order, each one replacing the last', () async {
      final receivedRounds = <int>[];
      final server = LocalSessionServer(onTurnReceived: (p) => receivedRounds.add(p['rounds'] as int));
      await server.start();
      addTearDown(server.stop);

      final peer = LocalPeer(host: '127.0.0.1', port: server.port!, role: 'dad', name: 'Dad');
      final client = LocalSessionClient(peer);
      for (var i = 0; i < 3; i++) {
        await client.sendTurn({'currentPrompt': 'p$i', 'rounds': i, 'leader': 'a'});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedRounds, [0, 1, 2]);
    });

    test('a malformed payload is refused, not crashed on', () async {
      var receivedCount = 0;
      final server = LocalSessionServer(onTurnReceived: (_) => receivedCount++);
      await server.start();
      addTearDown(server.stop);

      // A bare, unreachable-looking request straight at the server's own
      // port, bypassing LocalSessionClient's own JSON encoding — the real
      // "a foreign/malformed sender" case this server's own doc comment
      // says must never crash it.
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/turn'));
      request.write('not json');
      final response = await request.close();
      expect(response.statusCode, 400);
      client.close();
      expect(receivedCount, 0);
    });

    test('an unknown path is refused with 404, not silently accepted', () async {
      final server = LocalSessionServer(onTurnReceived: (_) {});
      await server.start();
      addTearDown(server.stop);

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/nope'));
      final response = await request.close();
      expect(response.statusCode, 404);
      client.close();
    });

    test('sending to a real, closed port fails honestly, not silently', () async {
      // A server that was started and stopped -- the real "peer went
      // offline" case, using a genuinely closed real socket rather than a
      // guessed unused port.
      final server = LocalSessionServer(onTurnReceived: (_) {});
      await server.start();
      final closedPort = server.port!;
      await server.stop();

      final peer = LocalPeer(host: '127.0.0.1', port: closedPort, role: 'ivy', name: 'Ivy');
      expect(
        () => LocalSessionClient(peer).sendTurn({'rounds': 0}),
        throwsA(isA<LocalSessionException>()),
      );
    });

    test('the honest exception message carries no banned phrase', () async {
      const peer = LocalPeer(host: '127.0.0.1', port: 1, role: 'ivy', name: 'Ivy');
      try {
        await LocalSessionClient(peer).sendTurn({'rounds': 0});
        fail('should have thrown');
      } on LocalSessionException catch (e) {
        final t = e.message.toLowerCase();
        for (final banned in ['failed', 'poor connection', 'check your', 'your network', 'your wifi']) {
          expect(t.contains(banned), false, reason: '"$banned" should not appear in "${e.message}"');
        }
      }
    });
  });
}

// local_discovery.dart's own LocalDiscovery/mDNS side is not covered here —
// bonsoir needs a real platform channel (real Android/iOS mDNS), which
// does not exist in the flutter_test sandbox this file runs in. That half
// of Track B Option 2 has since been verified for real, on real hardware
// (2026-08-30) — see local_play_screen.dart's own header for the full
// two-device run, and this file's own [LocalSessionServer.start] fix
// (binding every interface instead of guessing one) that real run required.
