// OLIVE BRANCH — the real transport's edges: the body cap on the local server (over a real socket on 127.0.0.1)
// and the seat mapping of the pairing transport. The conversation itself is tested over the in-memory twin
// (play_session_test.dart); only what is specific to the real wire is tested here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pairing.dart';
import 'package:olive_client/local_session.dart';
import 'package:olive_client/play_transport.dart';

void main() {
  group('LocalSessionServer body cap', () {
    Future<LocalSessionServer> start(List<Map<String, dynamic>> got) async {
      final s = LocalSessionServer(onTurnReceived: got.add);
      await s.start();
      addTearDown(s.stop);
      return s;
    }

    test('a normal turn still gets through', () async {
      final got = <Map<String, dynamic>>[];
      final s = await start(got);
      final c = HttpClient();
      final r = await c.postUrl(Uri.parse('http://127.0.0.1:${s.port}/turn'));
      r.write(jsonEncode(<String, dynamic>{'v': 1}));
      expect((await r.close()).statusCode, 200);
      c.close();
      expect(got, hasLength(1));
    });

    test('a body over the cap is refused with 413 and never parsed (declared length)', () async {
      final got = <Map<String, dynamic>>[];
      final s = await start(got);
      final c = HttpClient();
      final r = await c.postUrl(Uri.parse('http://127.0.0.1:${s.port}/turn'));
      final big = jsonEncode(<String, dynamic>{'pad': 'x' * (maxTurnBodyBytes + 10)});
      r.contentLength = utf8.encode(big).length;
      r.write(big);
      expect((await r.close()).statusCode, 413);
      c.close();
      expect(got, isEmpty);
    });

    test('a body over the cap is refused when it is sent chunked, with no length to check', () async {
      final got = <Map<String, dynamic>>[];
      final s = await start(got);
      final c = HttpClient();
      final r = await c.postUrl(Uri.parse('http://127.0.0.1:${s.port}/turn'));
      r.headers.chunkedTransferEncoding = true;
      r.write(jsonEncode(<String, dynamic>{'pad': 'x' * (maxTurnBodyBytes + 10)}));
      // The server stops reading at the cap and answers 413; a client still mid-upload may instead see the connection
      // closed on it. Either way nothing was parsed and nothing was delivered.
      try {
        expect((await r.close()).statusCode, 413);
      } on HttpException {
        // refused by closing the connection
      } on SocketException {
        // refused by closing the connection
      }
      c.close(force: true);
      expect(got, isEmpty);
    });
  });

  group('LocalPairingTransport', () {
    test('the child\'s device is seat a and the grown-up\'s is seat b, each seeing the other as its peer', () {
      final ivy = LocalPairingTransport(LocalPairingController(role: 'ivy', displayName: 'Ivy'));
      final dad = LocalPairingTransport(LocalPairingController(role: 'dad', displayName: 'Dad'));
      addTearDown(ivy.dispose);
      addTearDown(dad.dispose);
      expect((ivy.mySeat, ivy.peerSeat), ('a', 'b'));
      expect((dad.mySeat, dad.peerSeat), ('b', 'a'));
    });

    test('before anyone is found the other device is away, and a send says it did not go (it does not pretend)', () async {
      final c = LocalPairingController(role: 'ivy', displayName: 'Ivy');
      final t = LocalPairingTransport(c);
      addTearDown(t.dispose);
      expect(t.currentPresence, PeerPresence.away);
      expect(await t.send(<String, dynamic>{'v': 1}), isFalse);
      expect(c.phase, PairingPhase.searching, reason: 'and it is not turned into an error screen');
    });

    test('a send that does not get through is false, and with failureIsError off it leaves the pairing phase alone', () async {
      final c = LocalPairingController(role: 'ivy', displayName: 'Ivy');
      addTearDown(c.dispose);
      expect(await c.sendTurn(<String, dynamic>{'x': 1}, failureIsError: false), isFalse);
      expect(c.phase, PairingPhase.searching);
    });
  });
}
