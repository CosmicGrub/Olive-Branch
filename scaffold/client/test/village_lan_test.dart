// OLIVE BRANCH — the village road's HTTP half over real loopback sockets (mDNS needs two phones and is not covered
// here). Verified by CI, headless. Covers: a door exchange and a whole meeting over HTTP, the LAN-only rule, garbage and
// oversized bodies, the per-source budget, and that the advertisement names nobody.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/pairing_limits.dart';
import 'package:olive_client/village_lan.dart';
import 'package:olive_client/village_link.dart';
import 'package:olive_client/village_meet.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'village_test_support.dart';

void main() {
  test('the advertisement is a label and a random handle: no name, no family, no key', () {
    final Uint8List h = Uint8List.fromList(List<int>.generate(16, (int i) => i + 1));
    final Map<String, String> txt = villageTxt(h);
    expect(txt.keys.toSet(), <String>{'v', 'h'});
    expect(txt['v'], 'vl1');
    final NearbyVillage? n = parseVillageService(host: '192.0.2.9', port: 7, attributes: txt);
    expect(n, isNotNull);
    expect(n!.handle, h);
    expect(parseVillageService(host: null, port: 7, attributes: txt), isNull);
    expect(parseVillageService(host: 'x', port: 7, attributes: <String, String>{'v': 'vl2', 'h': txt['h']!}), isNull);
    expect(parseVillageService(host: 'x', port: 7, attributes: <String, String>{'v': 'vl1', 'h': b64(Uint8List(5))}), isNull);
    expect(parseVillageService(host: 'x', port: 7, attributes: <String, String>{'v': 'vl1'}), isNull);
  });

  test('a child pairing browser does not take a village endpoint for a window, and the reverse', () {
    final Map<String, String> txt = villageTxt(Uint8List(16));
    expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: txt), isNull);
    expect(parseVillageService(host: 'x', port: 1, attributes: pairingTxt(Uint8List(16), Uint8List(8))), isNull);
  });

  test('a door exchange over real HTTP; a source that is not on a LAN gets nothing', () async {
    final Village v = await Village.make();
    final P joP = await P.make(5);
    await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec));
    final VillageLanHost refusing = VillageLanHost(door: v.mom.door); // loopback is NOT a LAN address
    await refusing.start(advertise: false);
    final VillageLanTransport t0 = VillageLanTransport('127.0.0.1', refusing.port!);
    expect((await v.dad.reach2(t0)).heardFrom, isEmpty);
    await refusing.stop();

    final VillageLanHost host = VillageLanHost(door: v.mom.door, allowLoopback: true);
    await host.start(advertise: false);
    final VillageLanTransport t = VillageLanTransport('127.0.0.1', host.port!);
    final DoorOutcome o = await v.dad.reach2(t);
    expect(o.changed, isTrue);
    expect((await v.dad.welcome().overview()).forMe.single.personName, 'Jo');
    expect(await v.dad.summary(), await v.mom.summary());
    await host.stop();
  });

  test('a whole meeting over real HTTP: the code, the pictures, the offer', () async {
    final Village v = await Village.make();
    final P joP = await P.make(5);
    final VillageMeetWindow w = VillageMeetWindow.open(code: '135790', bucket: SourceBucket(limit: 100));
    final VillageLanHost host = VillageLanHost(meet: w, door: v.mom.door, allowLoopback: true);
    await host.start(advertise: false);
    expect(host.handle, w.discoveryHandle, reason: 'the host advertises the window\'s own random handle');
    final VillageLanTransport t = VillageLanTransport('127.0.0.1', host.port!);
    final VillageJoiner joiner = VillageJoiner(device: joP.key, agreement: joP.agree, deviceName: 'Jo\'s phone');
    expect(await joiner.meet(transport: t, handle: w.discoveryHandle, code: '000000'), isNull);
    final JoinMeeting? m = await joiner.meet(transport: t, handle: w.discoveryHandle, code: '135790');
    expect(m, isNotNull);
    expect(m!.sas.toString(), w.sas.toString());
    w.confirmMatch();
    await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
    await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
    expect((await m.poll(nowMs: v.clock.now)).kind, JoinPollKind.offered);
    await host.stop();
  });

  test('garbage, wrong paths, wrong methods and oversized bodies get no answer, and the door stays up', () async {
    final Village v = await Village.make();
    final VillageLanHost host = VillageLanHost(door: v.mom.door, allowLoopback: true);
    await host.start(advertise: false);
    final int port = host.port!;
    Future<int> status(String method, String path, [String? body]) async {
      final HttpClient c = HttpClient();
      try {
        final HttpClientRequest r = await c.openUrl(method, Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
        if (body != null) r.write(body);
        final HttpClientResponse res = await r.close();
        await res.drain<void>();
        return res.statusCode;
      } on SocketException {
        return -1; // the host answered and hung up before the whole oversized body went out
      } on HttpException {
        return -1;
      } finally {
        c.close(force: true);
      }
    }

    expect(await status('GET', '/v'), HttpStatus.notFound);
    expect(await status('POST', '/pair', '{}'), HttpStatus.notFound);
    expect(await status('POST', '/v', 'not json'), HttpStatus.badRequest);
    expect(await status('POST', '/v', '[1,2,3]'), HttpStatus.noContent);
    expect(await status('POST', '/v', '{"t":"door"}'), HttpStatus.noContent);
    expect(await status('POST', '/v', '{"t":"m1"}'), HttpStatus.noContent, reason: 'no meeting is open on this host');
    expect(await status('POST', '/v', jsonEncode(<String, Object?>{'t': 'door', 'u': <String>['x' * (3 * 1024 * 1024)]})), anyOf(HttpStatus.requestEntityTooLarge, -1));
    // Still alive and still answering a real exchange.
    final DoorOutcome o = await v.dad.reach2(VillageLanTransport('127.0.0.1', port));
    expect(o.heardFrom, isNotEmpty);
    await host.stop();
  });

  test('one source is held to its budget on the door', () async {
    final Village v = await Village.make();
    final VillageLanHost host = VillageLanHost(door: v.mom.door, allowLoopback: true, bucket: SourceBucket(limit: 2));
    await host.start(advertise: false);
    final VillageLanTransport t = VillageLanTransport('127.0.0.1', host.port!);
    int answered = 0;
    for (int i = 0; i < 5; i++) {
      final DoorOutcome o = await v.dad.reach2(t);
      if (o.heardFrom.isNotEmpty) answered++;
    }
    expect(answered, 2);
    await host.stop();
  });
}

extension on Phone {
  Future<DoorOutcome> reach2(VillageLanTransport t) => door.exchange(t.send);
}
