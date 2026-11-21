// OLIVE BRANCH — two grown-up phones, end to end over the real HTTP road (loopback): add a grown-up with a code, share the
// emergency card both ways, send and take back a screen, and every way a stranger, a child's device or a bad network can
// go wrong. Verified by CI, headless. mDNS is replaced by a fake that records what would be advertised.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_hub.dart';
import 'package:olive_client/family_join.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/family_sync_emergency.dart';
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_lan.dart';
import 'package:olive_client/pairing_protocol.dart' show PairingTransport;
import 'package:olive_client/screen_share.dart';

import 'family_hub_test_support.dart';

void main() {
  late Clk clock;
  final List<Phone> up = <Phone>[];
  Future<Phone> mk(int n, {List<InternetAddress>? bind, MemoryFamilyRepository? fam}) async {
    final Phone p = await phone(n, clock, bind: bind, fam: fam);
    up.add(p);
    return p;
  }

  setUp(() => clock = Clk(DateTime.now().millisecondsSinceEpoch));
  tearDown(() async {
    for (final Phone p in up) {
      await p.hub.stopRoad();
    }
    up.clear();
  });

  test('a phone with no family does nothing: no road, no advertisement, nobody to share with', () async {
    final Phone mom = await mk(1);
    expect((await mom.hub.status()).standing, FamilyStanding.none);
    expect(await mom.hub.startRoad(), RoadStart.notNeeded);
    expect(mom.hub.roadUp, isFalse);
    expect(mom.disc.adverts, isEmpty);
    expect(await mom.hub.shares.recipients(), isEmpty);
    expect(await mom.hub.syncEngine(), isNull);
    expect((await mom.hub.syncNow()).met, 0);
  });

  test(
    'add a grown-up with a code over the real road: both phones end up listing both, and the road advertises only what it should',
    () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      for (final Phone ph in <Phone>[mom, dad]) {
        final FamilyStatus s = await ph.hub.status();
        expect(s.standing, FamilyStanding.pair);
      }
      expect((await mom.hub.status()).others, <String>['Dad']);
      expect((await dad.hub.status()).others, <String>['Mom']);
      // While the window was open it said so; once the join finished it stopped saying so.
      expect(mom.disc.adverts.any((a) => a.join), isTrue);
      expect(mom.disc.adverts.last.join, isFalse);
      for (final a in mom.disc.adverts) {
        expect(a.handle.length, 16);
        expect(a.tag.length, kRoadTagBytes);
      }
      // The newcomer is settling in for the default 24 hours.
      expect((await dad.hub.status()).settlingHours, greaterThan(0));
      // A third grown-up cannot be added this way.
      expect(await mom.hub.openJoinWindow(myName: 'Mom'), isNull);
      expect(mom.hub.lastJoinProblem, 'not_alone');
    },
  );

  test('the emergency card travels over the road both ways and never changes a phone\'s own card by itself', () async {
    final Phone mom = await mk(1), dad = await mk(2);
    await pairUp(mom, dad);
    await mom.hub.startRoad();
    await dad.hub.startRoad();
    await meet(mom, dad);
    final SyncEngine me = (await mom.hub.syncEngine())!, de = (await dad.hub.syncEngine())!;
    final LedgerState ms = await (await mom.hub.context())!.state(nowMs: clock.ms);
    final SyncAppend a = await EmergencySync(me, 'ivy').share(card('penicillin'), byName: 'Mom', state: ms);
    expect(a.event, isNotNull, reason: a.reason);

    final SyncRun r = await dad.hub.syncNow();
    expect(r.met, 1, reason: '$r');
    expect(r.updates, greaterThan(0));
    final EmergencyView v = await EmergencySync(de, 'ivy').view();
    expect(v.settled?.card?.allergies, <String>['penicillin']);
    expect(v.settled?.byName, 'Mom');
    // Dad's own card, kept elsewhere, is untouched: a shared card is only ever shown beside it.
    final EmergencyCardService dadCard = EmergencyCardService.memory();
    expect((await dadCard.read(const FamilyPrincipal(roleName: 'guardian', userId: 'dad'))).card, isNull);

    // And back: Dad shares a card that follows Mom's, Mom's next meeting brings it.
    final LedgerState ds = await (await dad.hub.context())!.state(nowMs: clock.ms);
    expect((await EmergencySync(de, 'ivy').share(card('peanuts'), byName: 'Dad', state: ds)).event, isNotNull);
    final SyncRun r2 = await mom.hub.syncNow();
    expect(r2.met, 1);
    expect((await EmergencySync(me, 'ivy').view()).settled?.card?.allergies, <String>['peanuts']);
  });

  test('a stranger gets nothing: not an update, not the ledger, not a share, not a join window', () async {
    final Phone mom = await mk(1), dad = await mk(2), eve = await mk(3);
    await pairUp(mom, dad);
    await mom.hub.startRoad();
    final int before = (await mom.hub.syncEngine())!.eventCount;
    // Eve founds a family of her own and tries to swap updates with Mom.
    await eve.hub.found('Eve');
    final SyncEngine ee = (await eve.hub.syncEngine())!;
    await EmergencySync(ee, 'ivy').share(
      card('fake'),
      byName: 'Eve',
      state: await (await eve.hub.context())!.state(nowMs: clock.ms),
    );
    final RoadPeer momPeer = RoadPeer(host: '127.0.0.1', port: mom.hub.port!, handle: Uint8List(16), tag: Uint8List(8));
    expect(await eve.hub.exchangeWith(momPeer), -1);
    expect((await mom.hub.syncEngine())!.eventCount, before);
    final RoadHttpTransport raw = RoadHttpTransport('127.0.0.1', mom.hub.port!, allowLoopback: true);
    expect(await raw.send(<String, dynamic>{'t': 'x', 'b': 'OLIVE-UPDATE-1.AAAA'}), isNull);
    expect(await raw.send(<String, dynamic>{'t': 'x'}), isNull);
    expect(await raw.send(<String, dynamic>{'t': 'x', 'b': 5, 'l': 'no'}), isNull);
    expect(await raw.send(<String, dynamic>{'t': 'j0'}), isNull, reason: 'no window is open');
    expect(await raw.send(<String, dynamic>{'t': 'j3'}), isNull);
    expect((await raw.send(<String, dynamic>{'t': 'sh', 's': 'AAAA'}))?['o'], 'refused');
    expect((await raw.send(<String, dynamic>{'t': 'sh', 's': 7}))?['o'], 'refused');
    expect(await raw.send(<String, dynamic>{'t': 'unknown'}), isNull);
    // Mom's family record is exactly as it was.
    expect((await mom.hub.status()).others, <String>['Dad']);
    // Eve cannot see Mom, because Mom's tag is not one Eve's key makes.
    mom.hub.seePeerForTest(RoadPeer(host: '127.0.0.1', port: 1, handle: Uint8List(16), tag: Uint8List(8)));
    eve.hub.seePeerForTest(momPeer);
    expect(await eve.hub.familyPeers(), isEmpty);
  });

  test('a screen: not to a phone still settling in; then sent, received, and taken back', () async {
    final Phone mom = await mk(1), dad = await mk(2);
    await pairUp(mom, dad);
    await mom.hub.startRoad();
    await dad.hub.startRoad();
    await meet(mom, dad);
    expect(await mom.hub.shares.recipients(), isEmpty, reason: 'Dad\'s phone is settling in');
    clock.ms += 25 * 3600 * 1000;
    await meet(mom, dad); // the tag is a keyed hash of the ten-minute bucket: look again after the clock moved
    final List<ShareRecipient> who = await mom.hub.shares.recipients();
    expect(who.map((ShareRecipient r) => r.name), <String>['Dad']);

    expect(
      await mom.hub.shares.send(png: png(), to: who.single, namesHidden: false, note: 'look'),
      ShareSendOutcome.sent,
    );
    final List<ReceivedShare> got = await dad.hub.shares.inbox();
    expect(got.single.fromName, 'Mom');
    expect(got.single.note, 'look');
    expect((await mom.hub.shares.sent()).single.status, 'sent');
    expect((await mom.hub.shares.sent()).single.sealed, isNull, reason: 'the picture is not kept once Dad has it');

    await mom.hub.shares.takeBack(got.single.idHex);
    expect(await dad.hub.shares.inbox(), isEmpty);
  });

  test('a screen for a phone that is not nearby waits sealed and goes when the phones meet', () async {
    final Phone mom = await mk(1), dad = await mk(2);
    await pairUp(mom, dad);
    clock.ms += 25 * 3600 * 1000;
    await mom.hub.startRoad();
    // Dad's road is down: Mom sees nobody.
    final List<ShareRecipient> who = await mom.hub.shares.recipients();
    expect(await mom.hub.shares.send(png: png(), to: who.single, namesHidden: false), ShareSendOutcome.waiting);
    expect((await mom.hub.shares.sent()).single.status, 'waiting');
    await dad.hub.startRoad();
    await meet(mom, dad);
    final SyncRun r = await mom.hub.syncNow();
    expect(r.sent, 1);
    expect((await dad.hub.shares.inbox()).length, 1);
  });

  test('a screen addressed to Dad that lands on the wrong phone is refused and stays in the outbox', () async {
    final Phone mom = await mk(1), dad = await mk(2), eve = await mk(3);
    await pairUp(mom, dad);
    clock.ms += 25 * 3600 * 1000;
    await eve.hub.found('Eve');
    await eve.hub.startRoad(); // not a pair: the road stays down
    final List<ShareRecipient> who = await mom.hub.shares.recipients();
    await mom.hub.startRoad();
    // Mom thinks Eve's port is a family phone (a hostile or mistaken mDNS answer).
    final Uint8List bytes = await _sealedFor(mom, who.single);
    final ShareReceiveOutcome o = await eve.hub.shares.receive(bytes);
    expect(o, ShareReceiveOutcome.refused);
    expect(await eve.hub.shares.inbox(), isEmpty);
  });

  test('a child\'s device has no road, no engine, no recipients and answers nothing', () async {
    final Phone mom = await mk(1), dad = await mk(2);
    await pairUp(mom, dad);
    // The same family record as it is held by a CHILD device: the family key, no guardian key.
    final FamilySnapshot g = (await mom.fam.load())!;
    final MemoryFamilyRepository childRepo = MemoryFamilyRepository();
    await childRepo.save(
      FamilySnapshot(
        entries: g.entries,
        votes: g.votes,
        agreementSeed: Uint8List.fromList(List<int>.filled(32, 5)),
        guardianDevice: false,
        fk: g.fk,
        gk: const <int, Uint8List>{},
      ),
    );
    final Phone kid = await mk(3, fam: childRepo);
    expect(await kid.hub.syncEngine(), isNull);
    expect(await kid.hub.startRoad(), RoadStart.notNeeded);
    expect(kid.hub.roadUp, isFalse);
    expect(kid.disc.adverts, isEmpty);
    expect(await kid.hub.shares.recipients(), isEmpty);
    expect(await kid.hub.familyPeers(), isEmpty);
    expect((await kid.hub.syncNow()).met, 0);
    final ScreenShareService childService = ScreenShareService.childDevice();
    expect(await childService.recipients(), isEmpty);
    expect(await childService.receive(Uint8List.fromList(<int>[1, 2, 3])), ShareReceiveOutcome.refused);
    expect(await childService.inbox(), isEmpty);
  });

  test('no Wi-Fi: the add-a-grown-up window will not open, and a paired phone says so instead of pretending', () async {
    final Phone lone = await mk(1, bind: <InternetAddress>[]);
    expect(await lone.hub.openJoinWindow(myName: 'Mom'), isNull);
    expect(lone.hub.lastJoinProblem, 'no_wifi');
    expect(lone.hub.joinWindow, isNull);
    // A record on a phone with no network: the family was founded, but nothing is open.
    expect(lone.hub.roadUp, isFalse);
    final Phone mom = await mk(2), dad = await mk(4);
    await pairUp(mom, dad);
    final Phone dadNoWifi = await mk(4, bind: <InternetAddress>[], fam: dad.fam);
    expect((await dadNoWifi.hub.syncNow()).noWifi, isTrue);
  });

  test('a damaged family record is never replaced: nothing opens and the record is untouched', () async {
    final MemoryFamilyRepository bad = MemoryFamilyRepository();
    final Phone mom = await mk(1);
    await pairUp(mom, await mk(2)); // make a real record on mom
    final FamilySnapshot good = (await mom.fam.load())!;
    // Same entries but a genesis that no longer reduces (the first entry is dropped).
    await bad.save(
      FamilySnapshot(
        entries: good.entries.sublist(1),
        votes: good.votes,
        agreementSeed: good.agreementSeed,
        guardianDevice: true,
        fk: good.fk,
        gk: good.gk,
      ),
    );
    final Phone broken = await mk(1, fam: bad);
    expect((await broken.hub.status()).standing, FamilyStanding.unusable);
    expect(await broken.hub.openJoinWindow(myName: 'Mom'), isNull);
    expect(broken.hub.lastJoinProblem, 'unreadable');
    expect((await bad.load())!.entries.length, good.entries.length - 1);
    expect(await broken.hub.startRoad(), RoadStart.notNeeded);
  });
  group('review fixes', () {
    // A look-alike phone: it replays a tag it saw on the air, listens on loopback and records what it is sent.
    Future<(HttpServer, List<String>)> rogue(Map<String, dynamic>? reply) async {
      final HttpServer srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final List<String> seen = <String>[];
      srv.listen((HttpRequest r) async {
        seen.add(await utf8.decoder.bind(r).join());
        if (reply == null) {
          r.response.statusCode = HttpStatus.noContent;
        } else {
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode(reply));
        }
        await r.response.close();
      });
      addTearDown(() => srv.close(force: true));
      return (srv, seen);
    }

    Future<RoadPeer> lookAlike(Phone mom, HttpServer srv) async => RoadPeer(
      host: '127.0.0.1',
      port: srv.port,
      handle: Uint8List(16),
      tag: await roadTag((await mom.hub.context())!.keyring, mom.hub.now()),
    );

    test('a phone that copies a family tag is sent a sealed update only: never the ledger', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      final (HttpServer srv, List<String> seen) = await rogue(null);
      expect(await mom.hub.exchangeWith(await lookAlike(mom, srv)), -1);
      expect(seen, hasLength(1));
      final Map<String, dynamic> body = jsonDecode(seen.single) as Map<String, dynamic>;
      expect(body.containsKey('l'), isFalse, reason: 'no ledger before the peer has proved it holds the key');
      expect(body['t'], 'x');
    });

    test('a phone that answers with an update it could not have opened is not proven: still no ledger', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      final (HttpServer srv, List<String> seen) = await rogue(<String, dynamic>{'t': 'x', 'b': 'OLIVE-UPDATE-1.AAAA'});
      expect(await mom.hub.exchangeWith(await lookAlike(mom, srv)), -1);
      expect(seen, hasLength(1));
      expect((jsonDecode(seen.single) as Map<String, dynamic>).containsKey('l'), isFalse);
    });

    test('nothing is ever sent to an address that is not on the home network', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      final Uint8List tag = await roadTag((await mom.hub.context())!.keyring, mom.hub.now());
      for (final String host in <String>['198.51.100.7', '203.0.113.9', 'example.com', '']) {
        expect(await mom.hub.exchangeWith(RoadPeer(host: host, port: 9, handle: Uint8List(16), tag: tag)), -1);
      }
      expect(await RoadHttpTransport('198.51.100.7', 9).send(<String, dynamic>{'t': 'x'}), isNull);
      expect(await RoadHttpTransport('127.0.0.1', 9).send(<String, dynamic>{'t': 'x'}), isNull);
    });

    test('a real exchange still works end to end once the peer is proven', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      await mom.hub.startRoad();
      await dad.hub.startRoad();
      await meet(mom, dad);
      final List<RoadPeer> peers = await dad.hub.familyPeers();
      expect(peers, hasLength(1));
      expect(await dad.hub.exchangeWith(peers.single), greaterThanOrEqualTo(0));
    });

    test('a lost "yes" still finishes: the waiting grown-up brings the road up again after a restart', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      final FamilyJoinWindow? w = await mom.hub.openJoinWindow(myName: 'Mom');
      expect(w, isNotNull);
      autoApproveJoin(w!);
      dad.hub.joinTransportWrap = (PairingTransport t) => _DropYes(t);
      final JoinOutcome o = await dad.hub.joinFamily(
        window: RoadPeer(host: '127.0.0.1', port: mom.hub.port!, handle: w.handle, tag: Uint8List(8), join: true),
        code: w.code,
        myName: 'Dad',
        pollEvery: const Duration(milliseconds: 5),
      );
      expect(o.ok, isTrue, reason: o.reason);
      w.close('finish_later');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      FamilyStatus s = await mom.hub.status();
      expect(s.standing, FamilyStanding.alone);
      expect(s.waitingFor, isNotNull);
      // The app goes to the background and comes back: the road must come up for the unfinished welcome.
      await mom.hub.stopRoad();
      expect(await mom.hub.startRoad(), RoadStart.up);
      await dad.hub.startRoad();
      await meet(mom, dad);
      final SyncRun r = await mom.hub.syncNow();
      expect(r.met, 1, reason: '$r');
      s = await mom.hub.status();
      expect(s.standing, FamilyStanding.pair);
      expect(s.others, <String>['Dad']);
    });

    test('a sender that trickles its body does not stop other requests being answered', () async {
      final FamilyRoadServer srv = FamilyRoadServer(
        backend: (Map<String, dynamic> m, String s) async => <String, dynamic>{'ok': 1},
        bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4],
        allowLoopback: true,
      );
      expect(await srv.start(), isTrue);
      addTearDown(srv.stop);
      expect(kRoadBodyDeadline, lessThan(const Duration(seconds: 20)));
      final HttpClient c = HttpClient();
      addTearDown(() => c.close(force: true));
      final HttpClientRequest req = await c.postUrl(Uri.parse('http://127.0.0.1:${srv.port}/f'));
      req.headers.contentType = ContentType.json;
      req.contentLength = 100000;
      req.add(<int>[0x7b]);
      await req.flush();
      expect(
        await RoadHttpTransport('127.0.0.1', srv.port!, allowLoopback: true).send(<String, dynamic>{'t': 'x'}),
        isNotNull,
      );
    });

    test('two phones sending a screen to each other at the same moment both go through, without a timeout', () async {
      final Phone mom = await mk(1), dad = await mk(2);
      await pairUp(mom, dad);
      clock.ms += 25 * 3600 * 1000;
      await mom.hub.startRoad();
      await dad.hub.startRoad();
      await meet(mom, dad);
      final ShareRecipient toDad = (await mom.hub.shares.recipients()).single;
      final ShareRecipient toMom = (await dad.hub.shares.recipients()).single;
      final Stopwatch t = Stopwatch()..start();
      final List<ShareSendOutcome> got = await Future.wait(<Future<ShareSendOutcome>>[
        mom.hub.shares.send(png: png(), to: toDad, namesHidden: false),
        dad.hub.shares.send(png: png(), to: toMom, namesHidden: false),
      ]);
      expect(got, <ShareSendOutcome>[ShareSendOutcome.sent, ShareSendOutcome.sent]);
      expect(t.elapsed, lessThan(const Duration(seconds: 8)));
      expect(await mom.hub.shares.inbox(), hasLength(1));
      expect(await dad.hub.shares.inbox(), hasLength(1));
    });
  });
}

Future<Uint8List> _sealedFor(Phone from, ShareRecipient to) async {
  final ShareIdentity id = (await from.hub.shares.identity())!;
  return sealShare(sender: id.device, state: id.state, to: to, png: png(), namesHidden: false, nowMs: from.hub.now());
}

/// Loses the joining phone's final "yes".
class _DropYes implements PairingTransport {
  _DropYes(this.inner);
  final PairingTransport inner;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> m) async => m['t'] == 'j4' ? null : inner.send(m);
}
