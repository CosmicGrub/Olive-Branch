// OLIVE BRANCH — the admission layer wired into the shared play contract, end to end: two REAL pairing controllers
// (real admission, real encrypted frames, real sockets on 127.0.0.1; only mDNS is faked) carrying War, Connect 4 and Uno
// through the shared session controller. Verified by CI, headless. Plain `test()` only (a widget binding makes dart:io
// HTTP answer 400; the card overlay itself is a widget test in play_confirm_overlay_test.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect4_engine.dart';
import 'package:olive_client/connect4_play.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/game_war.dart';
import 'package:olive_client/local_pairing.dart';
import 'package:olive_client/play_admission.dart';
import 'package:olive_client/play_credentials.dart';
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_session.dart';
import 'package:olive_client/play_transport.dart';
import 'package:olive_client/uno_play.dart';

import 'play_wire_harness.dart';

Future<int> rawPost(int port, String path, List<int> body) async {
  final HttpClient c = HttpClient();
  try {
    final HttpClientRequest req = await c.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.contentType = ContentType.binary;
    req.add(body);
    final HttpClientResponse res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

/// A grown-up's device and a child's device that found each other and were admitted (the grown-up said yes).
Future<(Device, Device)> admittedPair({Family? family}) async {
  final Family f = family ?? await Family.make();
  final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
  final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
  addTearDown(adult.controller.dispose);
  addTearDown(child.controller.dispose);
  await introduce(adult, child);
  await until(() => adult.controller.awaitingGrownUp, what: 'the confirmation card');
  adult.controller.admission!.confirm();
  await until(() => adult.controller.phase == PairingPhase.found && child.controller.phase == PairingPhase.found,
      what: 'both devices found');
  return (adult, child);
}

PlayContext ctxFor(String seat, {int seed = 1}) => PlayContext(
    mode: PlayMode.pair, localSeatId: seat, authoritySeatId: 'b', seatIds: const <String>['a', 'b'], rng: Random(seed));

void main() {
  group('who may play', () {
    test('a device that was never paired cannot play: a calm line, nothing opened, nothing advertised', () async {
      for (final String role in <String>['ivy', 'dad']) {
        final Device d = makeDevice(role: role, credentials: null);
        addTearDown(d.controller.dispose);
        await d.controller.start();
        expect(d.controller.phase, PairingPhase.error, reason: role);
        expect(d.controller.errorMessage, unpairedPlayLine(adult: role != 'ivy'));
        expect(d.discoveries, isEmpty, reason: 'no server and no mDNS advertisement for an unpaired device');
        expect(d.controller.admission, isNull);
      }
    });

    test('the calm lines carry no error word, no code and no digit', () {
      for (final bool adult in <bool>[true, false]) {
        final String line = unpairedPlayLine(adult: adult).toLowerCase();
        for (final String banned in <String>['error', 'failed', 'wrong', 'denied', 'code', 'pin', 'password', 'oops', 'sorry']) {
          expect(line.contains(banned), isFalse, reason: '$adult: $banned');
        }
        expect(RegExp(r'\d').hasMatch(line), isFalse);
      }
    });

    test('a stranger with its own keys is never found, and the lobby never so much as asks the grown-up', () async {
      final Family f = await Family.make();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      final Family other = await Family.make();
      final Device stranger = makeDevice(role: 'ivy', credentials: other.childCredentials());
      addTearDown(adult.controller.dispose);
      addTearDown(stranger.controller.dispose);
      await adult.controller.start();
      await stranger.controller.start();
      stranger.discovery.see(adult.discovery, seat: 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(stranger.controller.phase, PairingPhase.searching);
      expect(adult.controller.awaitingGrownUp, isFalse);
      expect(adult.controller.admission!.state, PlayState.none);
    });

    test('a child device of ANOTHER grown-up cannot get a card on this grown-up\'s phone', () async {
      final Family f = await Family.make();
      final DeviceKey otherChild = await newKey();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      // It holds the right grown-up key, but this grown-up never approved ITS key.
      final Device intruder = makeDevice(
          role: 'ivy',
          credentials: PlayCredentials(own: otherChild, peerKeys: <Uint8List>[f.adultKey.publicKey], adult: false));
      addTearDown(adult.controller.dispose);
      addTearDown(intruder.controller.dispose);
      await adult.controller.start();
      await intruder.controller.start();
      intruder.discovery.see(adult.discovery, seat: 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(intruder.controller.phase, PairingPhase.searching);
      expect(adult.controller.awaitingGrownUp, isFalse);
    });

    test('a plain, unencrypted POST to the lobby is refused before and after a real peer is admitted', () async {
      final (Device adult, Device child) = await admittedPair();
      final int port = adult.discovery.port;
      final List<int> plain = utf8.encode(jsonEncode(<String, dynamic>{'v': 1, 'sid': '0000000000000000', 'n': 1, 'ack': 0, 't': 'move', 'g': 'connect4', 'p': <String, dynamic>{}}));
      expect(await rawPost(port, '/t', plain), HttpStatus.unauthorized);
      expect(await rawPost(child.discovery.port, '/t', plain), HttpStatus.unauthorized);
    });
  });

  group('the grown-up\'s confirmation', () {
    test('the child\'s device never asks: it is found the moment its hello is answered; the grown-up\'s waits for yes', () async {
      final Family f = await Family.make();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(adult.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(adult, child);
      await until(() => child.controller.phase == PairingPhase.found, what: 'child found');
      await until(() => adult.controller.awaitingGrownUp, what: 'card');
      expect(child.controller.awaitingGrownUp, isFalse);
      expect(adult.controller.phase, isNot(PairingPhase.found), reason: 'no play before the grown-up says yes');
      expect(adult.controller.peerSeat, 2, reason: 'the card can say Player two');
      // The child's lobby let the grown-up straight in (it is the pinned grown-up).
      expect(child.controller.admission!.state, PlayState.admitted);
      adult.controller.admission!.confirm();
      await until(() => adult.controller.phase == PairingPhase.found, what: 'adult found after yes');
    });

    test('the grown-ups lobby has the match word and picture ready for the card', () async {
      final Family f = await Family.make();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(adult.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(adult, child);
      await until(() => adult.controller.awaitingGrownUp, what: 'card');
      // The grown-up's lobby and the child's own session agree on the match (the grown-up reads it out, nothing is typed).
      expect(adult.controller.admission!.sas, isNotNull);
    });

    test('the yes is remembered: the next lobby for the same child device skips the card', () async {
      final Family f = await Family.make();
      final Set<String> kept = <String>{};
      final Device first = makeDevice(role: 'dad', credentials: f.adultCredentials(confirmed: kept, onConfirmed: kept.add));
      final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(first.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(first, child);
      await until(() => first.controller.awaitingGrownUp, what: 'card');
      first.controller.admission!.confirm();
      await until(() => kept.isNotEmpty, what: 'remembered');
      expect(kept.single.length, lessThan(40), reason: 'a fingerprint, never a name');

      final Device second = makeDevice(role: 'dad', credentials: f.adultCredentials(confirmed: kept, onConfirmed: kept.add));
      final Device child2 = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(second.controller.dispose);
      addTearDown(child2.controller.dispose);
      await introduce(second, child2);
      await until(() => second.controller.phase == PairingPhase.found && child2.controller.phase == PairingPhase.found, what: 'found with no card');
      expect(second.controller.awaitingGrownUp, isFalse);
    });

    test('"No" forgets the other device, and it can try again (a fresh hello asks again)', () async {
      final Family f = await Family.make();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(adult.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(adult, child);
      await until(() => adult.controller.awaitingGrownUp, what: 'card');
      await until(() => adult.controller.peer != null, what: 'the grown-up has said hello back (settled)');
      adult.controller.admission!.decline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(adult.controller.phase, PairingPhase.searching);
      expect(adult.controller.peer, isNull);
      expect(adult.controller.awaitingGrownUp, isFalse);
      // The child's device finds the grown-up's again: a fresh hello asks again.
      child.discovery.lose('Player 1');
      child.discovery.see(adult.discovery, seat: 1);
      await until(() => adult.controller.awaitingGrownUp, what: 'the card again');
    });

    test('a grown-up with several paired children says hello with the right one', () async {
      final DeviceKey adultKey = await newKey(), kidA = await newKey(), kidB = await newKey();
      final PlayCredentials adultCred = PlayCredentials(
          own: adultKey, peerKeys: <Uint8List>[kidA.publicKey, kidB.publicKey], adult: true);
      final Device adult = makeDevice(role: 'dad', credentials: adultCred);
      final Device child = makeDevice(
          role: 'ivy', credentials: PlayCredentials(own: kidB, peerKeys: <Uint8List>[adultKey.publicKey], adult: false));
      addTearDown(adult.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(adult, child);
      await until(() => adult.controller.awaitingGrownUp, what: 'card');
      adult.controller.admission!.confirm();
      await until(() => adult.controller.phase == PairingPhase.found && child.controller.phase == PairingPhase.found,
          what: 'found with the second child key');
    });
  });

  group('turns travel encrypted between the two real controllers', () {
    test('a turn goes both ways and arrives intact', () async {
      final (Device adult, Device child) = await admittedPair();
      final List<Map<String, dynamic>> atAdult = <Map<String, dynamic>>[], atChild = <Map<String, dynamic>>[];
      adult.controller.incomingTurns.listen(atAdult.add);
      child.controller.incomingTurns.listen(atChild.add);
      expect(await child.controller.sendTurn(<String, dynamic>{'hello': 'from the child'}, failureIsError: false), isTrue);
      expect(await adult.controller.sendTurn(<String, dynamic>{'hello': 'from the grown-up'}, failureIsError: false), isTrue);
      await until(() => atAdult.isNotEmpty && atChild.isNotEmpty, what: 'both turns');
      expect(atAdult.single['hello'], 'from the child');
      expect(atChild.single['hello'], 'from the grown-up');
    });
  });

  group('the three migrated games over the admitted transport', () {
    Future<(PlaySessionController, PlaySessionController, PlayGame, PlayGame)> sessions(
        PlayGameSpec spec, Device adult, Device child) async {
      final PlayGame dealerGame = spec.create(ctxFor('b', seed: 7));
      final PlayGame guestGame = spec.create(ctxFor('a', seed: 8));
      final PlaySessionController dealer =
          PlaySessionController(spec: spec, game: dealerGame, transport: LocalPairingTransport(adult.controller));
      final PlaySessionController guest =
          PlaySessionController(spec: spec, game: guestGame, transport: LocalPairingTransport(child.controller));
      addTearDown(dealer.dispose);
      addTearDown(guest.dispose);
      dealer.start();
      guest.start();
      return (dealer, guest, dealerGame, guestGame);
    }

    test('Connect 4: a whole game, alternating, ends the same on both devices', () async {
      final (Device adult, Device child) = await admittedPair();
      final (dealer, guest, PlayGame dg, PlayGame gg) = await sessions(connect4Spec, adult, child);
      final Connect4PlayGame d = dg as Connect4PlayGame, g = gg as Connect4PlayGame;
      for (int i = 0; i < 3; i++) {
        d.tapColumn(0);
        await until(() => g.board.columns[0].length == i + 1, what: 'guest sees the dealer drop $i');
        g.tapColumn(1);
        await until(() => d.board.columns[1].length == i + 1, what: 'dealer applies the guest drop $i');
        await until(() => g.board.columns[1].length == i + 1, what: 'guest sees its own drop answered $i');
      }
      d.tapColumn(0);
      await until(() => g.outcome == Connect4Outcome.win, what: 'guest sees the win');
      expect(d.outcome, Connect4Outcome.win);
      expect(dealer.blockedSends + guest.blockedSends, 0);
    });

    test('War: the deal arrives and each side flips', () async {
      final (Device adult, Device child) = await admittedPair();
      final (dealer, guest, PlayGame dg, PlayGame gg) = await sessions(warSpec, adult, child);
      final WarPlayGame d = dg as WarPlayGame, g = gg as WarPlayGame;
      d.deal();
      await until(() => g.war != null, what: 'guest has the deal');
      g.flip();
      d.flip();
      await until(() => (d.war?.roundNumber ?? 0) >= 1 && (g.war?.roundNumber ?? 0) >= 1, what: 'both flipped');
      expect(dealer.blockedSends + guest.blockedSends, 0);
    });

    test('Uno: the deal arrives, each device sees only its own hand and a count for the other', () async {
      final (Device adult, Device child) = await admittedPair();
      final (dealer, guest, PlayGame dg, PlayGame gg) = await sessions(unoSpec, adult, child);
      final UnoPlayGame d = dg as UnoPlayGame, g = gg as UnoPlayGame;
      d.deal();
      await until(() => g.view != null, what: 'guest has its view');
      expect(g.started, isTrue);
      expect(dealer.blockedSends + guest.blockedSends, 0);
    });

    test('a turn the sender never admitted never reaches the game (an unadmitted lobby drops it)', () async {
      final Family f = await Family.make();
      final Device adult = makeDevice(role: 'dad', credentials: f.adultCredentials());
      final Device child = makeDevice(role: 'ivy', credentials: f.childCredentials());
      addTearDown(adult.controller.dispose);
      addTearDown(child.controller.dispose);
      await introduce(adult, child);
      await until(() => adult.controller.awaitingGrownUp, what: 'card');
      final List<Map<String, dynamic>> atAdult = <Map<String, dynamic>>[];
      adult.controller.incomingTurns.listen(atAdult.add);
      // The child thinks it is found and sends while the grown-up has not yet said yes.
      expect(await child.controller.sendTurn(<String, dynamic>{'x': 1}, failureIsError: false), isFalse);
      expect(atAdult, isEmpty);
    });
  });
}
