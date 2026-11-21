// OLIVE BRANCH — the tablet update path over the REAL transport: two real pairing controllers (real admission, real
// encrypted padded frames, real sockets on 127.0.0.1; only mDNS is faked), the phone's sender and the tablet's receiver,
// and the reference engine. Shows the update crosses the sealed, authenticated link and that a device that is not the
// paired one never gets an offer or a card. Plain `test()` only (a widget binding makes dart:io HTTP answer 400).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pairing.dart';
import 'package:olive_client/play_admission.dart';
import 'package:olive_client/play_credentials.dart';
import 'package:olive_client/play_transport.dart';
import 'package:olive_client/tablet_update_receiver.dart';
import 'package:olive_client/tablet_update_sender.dart';
import 'package:olive_client/tablet_update_store.dart';

import 'play_wire_harness.dart';
import 'tablet_update_harness.dart';

void main() {
  test('an update crosses the real encrypted link, is verified on the tablet, and is staged byte for byte', () async {
    final Directory root = await Directory.systemTemp.createTemp('olive_wiring_');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final Family fam = await Family.make();
    final Device phone = makeDevice(role: 'dad', credentials: fam.adultCredentials());
    final Device tablet = makeDevice(role: 'ivy', credentials: fam.childCredentials());
    addTearDown(phone.controller.dispose);
    addTearDown(tablet.controller.dispose);
    await introduce(phone, tablet);
    await until(() => phone.controller.awaitingGrownUp, what: 'the confirmation card on the phone');
    phone.controller.admission!.confirm();
    await until(() => phone.controller.phase == PairingPhase.found && tablet.controller.phase == PairingPhase.found, what: 'both found');

    final Directory phoneDir = await Directory('${root.path}/phone').create();
    final Directory tabletDir = await Directory('${root.path}/tablet').create();
    final ReferenceEngine phoneEngine = ReferenceEngine(dir: phoneDir);
    final ReferenceEngine tabletEngine = ReferenceEngine(dir: tabletDir, installedVersionCode: 5100);
    final Fixture f = await makeFixture(size: 150 * 1024 + 77, chunkSize: 48 * 1024);
    final MemoryStagedUpdateStore store = MemoryStagedUpdateStore();

    final LocalPairingTransport phoneT = LocalPairingTransport(phone.controller);
    final LocalPairingTransport tabletT = LocalPairingTransport(tablet.controller);
    final TabletUpdateReceiver receiver = TabletUpdateReceiver(engine: tabletEngine, store: store, adultPresent: () => true);
    await receiver.listen(tabletT);
    final TabletUpdateSender sender = TabletUpdateSender(
        transport: phoneT, held: await heldFrom(f, phoneEngine, phoneDir), grownUpDevice: true, adultPresent: () => true);
    await sender.start();
    await until(() => receiver.phase == ReceivePhase.offered, what: 'the tablet was offered the update');
    expect(receiver.offered!.versionName, '0.52.0');
    await receiver.accept();
    await until(() => receiver.phase == ReceivePhase.ready, what: 'staged', timeout: const Duration(seconds: 30));
    final StagedUpdate st = (await store.loadStaged())!;
    expect(await File('${tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
    await until(() => sender.phase == SenderPhase.delivered, what: 'the phone told it is done');
    await sender.stop();
    await receiver.stop();
    phoneT.dispose();
    tabletT.dispose();
  });

  test('a tablet that holds ANOTHER family\'s keys never finds the phone, so no offer reaches it and no card appears', () async {
    final Family fam = await Family.make();
    final Family other = await Family.make();
    final Device phone = makeDevice(role: 'dad', credentials: fam.adultCredentials());
    final Device stranger = makeDevice(role: 'ivy', credentials: other.childCredentials());
    addTearDown(phone.controller.dispose);
    addTearDown(stranger.controller.dispose);
    await phone.controller.start();
    await stranger.controller.start();
    stranger.discovery.see(phone.discovery, seat: 1);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(stranger.controller.phase, PairingPhase.searching);
    expect(phone.controller.awaitingGrownUp, isFalse, reason: 'the grown-up is never even asked');

    final Directory root = await Directory.systemTemp.createTemp('olive_wiring2_');
    addTearDown(() => root.delete(recursive: true));
    final ReferenceEngine tabletEngine = ReferenceEngine(dir: root);
    final LocalPairingTransport strangerT = LocalPairingTransport(stranger.controller);
    final TabletUpdateReceiver r = TabletUpdateReceiver(engine: tabletEngine, store: MemoryStagedUpdateStore(), adultPresent: () => true);
    await r.listen(strangerT);
    final Fixture f = await makeFixture(size: 50 * 1024);
    final LocalPairingTransport phoneT = LocalPairingTransport(phone.controller);
    final TabletUpdateSender sender = TabletUpdateSender(
        transport: phoneT, held: await heldFrom(f, ReferenceEngine(dir: root), root), grownUpDevice: true, adultPresent: () => true,
        offerEvery: const Duration(milliseconds: 50));
    await sender.start();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(r.phase, ReceivePhase.listening, reason: 'the stranger was never offered anything');
    expect(phoneT.currentPresence, PeerPresence.away);
    await sender.stop();
    await r.stop();
    phoneT.dispose();
    strangerT.dispose();
  });

  test('a device that was never paired cannot even open the link: nothing is advertised, and the receiver has nothing to listen on', () async {
    final Device tablet = makeDevice(role: 'ivy', credentials: null);
    addTearDown(tablet.controller.dispose);
    await tablet.controller.start();
    expect(tablet.controller.phase, PairingPhase.error);
    expect(tablet.discoveries, isEmpty);
  });

  test('the tablet\'s own key is the only one a phone lets in: a second child device of the same phone is not this tablet', () async {
    // The phone pinned ONE tablet. Another device with a valid-looking key but never approved gets no card.
    final Family fam = await Family.make();
    final Device phone = makeDevice(role: 'dad', credentials: fam.adultCredentials());
    final newcomerKey = await newKey();
    final Device newcomer = makeDevice(
        role: 'ivy',
        credentials: PlayCredentials(own: newcomerKey, peerKeys: <Uint8List>[fam.adultKey.publicKey], adult: false));
    addTearDown(phone.controller.dispose);
    addTearDown(newcomer.controller.dispose);
    await phone.controller.start();
    await newcomer.controller.start();
    newcomer.discovery.see(phone.discovery, seat: 1);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(phone.controller.awaitingGrownUp, isFalse);
    expect(phone.controller.admission!.state, PlayState.none);
  });
}
