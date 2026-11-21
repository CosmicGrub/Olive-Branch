// Helpers for the family hub tests: two or three grown-up phones on loopback with a fake mDNS. Not a test file.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_hub.dart';
import 'package:olive_client/family_join.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/family_sync_engine.dart' show MemorySyncRepository;
import 'package:olive_client/family_sync_lan.dart';
import 'package:olive_client/screen_share.dart';

import 'family_test_support.dart';

class FakeDiscovery implements RoadDiscovery {
  final List<({int port, Uint8List handle, Uint8List tag, bool join})> adverts =
      <({int port, Uint8List handle, Uint8List tag, bool join})>[];
  int stops = 0;
  bool browsing = false;
  final StreamController<RoadPeer> _f = StreamController<RoadPeer>.broadcast();
  final StreamController<String> _g = StreamController<String>.broadcast();
  @override
  Future<void> advertise({
    required int port,
    required Uint8List handle,
    required Uint8List tag,
    bool join = false,
  }) async {
    adverts.add((port: port, handle: handle, tag: tag, join: join));
  }

  @override
  Future<void> stopAdvertising() async {
    stops++;
  }

  @override
  Future<void> startBrowsing() async {
    browsing = true;
  }

  @override
  Future<void> stopBrowsing() async {
    browsing = false;
  }

  @override
  Stream<RoadPeer> get found => _f.stream;
  @override
  Stream<String> get gone => _g.stream;
}

class Clk {
  Clk(this.ms);
  int ms;
}

class Phone {
  Phone(this.p, this.hub, this.fam, this.disc);
  final P p;
  final FamilyHub hub;
  final MemoryFamilyRepository fam;
  final FakeDiscovery disc;
}

Future<Phone> phone(int n, Clk clock, {List<InternetAddress>? bind, MemoryFamilyRepository? fam}) async {
  final P p = await P.make(n);
  final MemoryFamilyRepository repo = fam ?? MemoryFamilyRepository();
  final FakeDiscovery d = FakeDiscovery();
  final FamilyHub hub = FamilyHub(
    familyRepo: repo,
    syncRepo: MemorySyncRepository(),
    deviceKey: () async => p.key,
    shareBox: MemoryShareBoxRepository(),
    discovery: d,
    nowMs: () => clock.ms,
    bindAddresses: bind ?? <InternetAddress>[InternetAddress.loopbackIPv4],
    allowLoopback: true,
    discoverWait: const Duration(milliseconds: 600),
    readvertiseEvery: null,
  );
  return Phone(p, hub, repo, d);
}

Uint8List png() {
  final Uint8List b = Uint8List(48);
  b.setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.setRange(12, 16, 'IHDR'.codeUnits);
  b[19] = 2;
  b[23] = 2;
  return b;
}

/// Mom founds and opens a window; Dad joins it. Returns once both phones list both grown-ups.
Future<void> pairUp(Phone mom, Phone dad) async {
  final FamilyJoinWindow? w = await mom.hub.openJoinWindow(myName: 'Mom');
  expect(w, isNotNull, reason: mom.hub.lastJoinProblem);
  autoApproveJoin(w!);
  final JoinOutcome o = await dad.hub.joinFamily(
    window: RoadPeer(host: '127.0.0.1', port: mom.hub.port!, handle: w.handle, tag: Uint8List(8), join: true),
    code: w.code,
    myName: 'Dad',
    pollEvery: const Duration(milliseconds: 5),
  );
  expect(o.ok, isTrue, reason: o.reason);
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void autoApproveJoin(FamilyJoinWindow w) {
  bool asked = false;
  w.addListener(() {
    if (w.state == JoinState.waitingForYou && !asked) {
      asked = true;
      unawaited(w.approve());
    }
  });
}

/// Makes each phone see the other on the road, as mDNS would.
Future<void> meet(Phone a, Phone b) async {
  for (final List<Phone> pair in <List<Phone>>[
    <Phone>[a, b],
    <Phone>[b, a],
  ]) {
    final FamilyContext c = (await pair[0].hub.context())!;
    pair[0].hub.seePeerForTest(
      RoadPeer(
        host: '127.0.0.1',
        port: pair[1].hub.port!,
        handle: Uint8List.fromList(List<int>.generate(16, (int i) => i + pair[1].p.n)),
        tag: await roadTag((await pair[1].hub.context())!.keyring, pair[0].hub.now()),
      ),
    );
    expect(c.keyring.guardianDevice, isTrue);
  }
}

LocalEmergencyCard card(String allergy) => LocalEmergencyCard(
  allergies: <String>[allergy],
  doctor: const EcDoctor(name: 'Dr A', phone: '555-0100'),
  contacts: const <EcContact>[EcContact(name: 'Nan', relation: 'grandmother', phone: '555-0101')],
);
