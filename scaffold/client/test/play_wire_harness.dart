// OLIVE BRANCH — test harness: two REAL pairing controllers (real admission, real encrypted frames, real sockets on
// 127.0.0.1) that find each other through a fake discovery instead of mDNS. Plain `test()` only: a widget binding makes
// dart:io HTTP answer 400 (see play_confirm_card_test.dart).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_discovery.dart';
import 'package:olive_client/local_pairing.dart';
import 'package:olive_client/play_credentials.dart';

class FakeDiscovery implements PeerDiscovery {
  FakeDiscovery(this.port, this.token);
  final int port;
  final String? token;
  final StreamController<LocalPeer> _p = StreamController<LocalPeer>.broadcast();
  final StreamController<String> _l = StreamController<String>.broadcast();
  bool started = false;

  @override
  Stream<LocalPeer> get peers => _p.stream;
  @override
  Stream<String> get lost => _l.stream;
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async {
    await _p.close();
    await _l.close();
  }

  /// This device "resolves" [other] on the network.
  void see(FakeDiscovery other, {int seat = 1}) => _p.add(LocalPeer(
      host: '127.0.0.1', port: other.port, role: 'seat$seat', name: 'Player $seat', token: other.token));

  void lose(String name) => _l.add(name);
}

Future<DeviceKey> newKey() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

/// One device: a controller, and the discovery it was given once started.
class Device {
  Device(this.controller, this.discoveries);
  final LocalPairingController controller;
  final List<FakeDiscovery> discoveries;
  FakeDiscovery get discovery => discoveries.last;
}

Device makeDevice({required String role, required PlayCredentials? credentials}) {
  final List<FakeDiscovery> made = <FakeDiscovery>[];
  final LocalPairingController c = LocalPairingController(
    role: role,
    displayName: 'x',
    credentials: FixedPlayCredentials(adultSide: role == 'ivy' ? null : credentials, childSide: role == 'ivy' ? credentials : null),
    network: PlayNetworkSeams(
      ownAddress: '127.0.0.1',
      bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4],
      allowLoopback: true,
      lifecycleGuard: false,
      discoveryFactory: (int port, String? token) {
        final FakeDiscovery d = FakeDiscovery(port, token);
        made.add(d);
        return d;
      },
    ),
  );
  return Device(c, made);
}

/// A paired family: the grown-up's device and the child's device, each holding the other's key.
class Family {
  Family(this.adultKey, this.childKey);
  final DeviceKey adultKey, childKey;

  static Future<Family> make() async => Family(await newKey(), await newKey());

  PlayCredentials adultCredentials({Set<String>? confirmed, void Function(String)? onConfirmed}) =>
      PlayCredentials(own: adultKey, peerKeys: <Uint8List>[childKey.publicKey], adult: true, confirmed: confirmed, onConfirmed: onConfirmed);

  PlayCredentials childCredentials() => PlayCredentials(own: childKey, peerKeys: <Uint8List>[adultKey.publicKey], adult: false);
}

/// Starts both and lets each resolve the other (the adult is "Player one", the child "Player two").
Future<void> introduce(Device adult, Device child) async {
  await adult.controller.start();
  await child.controller.start();
  adult.discovery.see(child.discovery, seat: 2);
  child.discovery.see(adult.discovery, seat: 1);
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8), String what = 'condition'}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) throw StateError('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
