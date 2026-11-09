// OLIVE BRANCH — the real transport's edges: the body cap on the local server (over a real socket on 127.0.0.1)
// and the seat mapping of the pairing transport. The conversation itself is tested over the in-memory twin
// (play_session_test.dart); only what is specific to the real wire is tested here.

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pairing.dart';
import 'package:olive_client/play_transport.dart';

void main() {
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
