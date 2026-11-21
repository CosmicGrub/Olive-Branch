// OLIVE BRANCH — the host that puts the village welcome into the real guardian app: where this phone's family record
// lives, how a family is founded the first time a grown-up chooses to welcome someone, the road to the other phone,
// and the adult PIN. UNVERIFIED on a device; the wiring runs headless in CI (client/test/village_welcome_flow_test.dart
// drives two phones through the screens over an in-memory road, and village_lan_test.dart drives the HTTP half over
// loopback). Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3 and 9.
//
// NOTHING HERE RUNS UNTIL A GROWN-UP CHOOSES IT. Opening "Your village" only reads: it never founds a family, opens a
// port or advertises anything. A family record is founded on this phone (family_state.dart, [FamilyFounder.ensure]) at
// the moment a grown-up taps "Welcome someone" and types their PIN, from the phone's own paired-tablet list, which it
// only READS: no pairing record is written and a tablet keeps working exactly as before. The road to the other phone
// (an HTTP endpoint and an mDNS advertisement) exists only while a village screen that needs it is open.
//
// THE SERVER NEVER GATES THIS. Nothing here touches the network beyond the same Wi-Fi, and nothing waits on an account.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'device_keys.dart';
import 'family_ledger.dart' show AgreementKey, LedgerEntry, LedgerVote;
import 'family_state.dart';
import 'local_pin.dart' show kLocalGuardianScope, LocalPinService;
import 'local_pin_screens.dart' show askLocalPin;
import 'local_services.dart';
import 'local_store.dart' show LocalNamespace;
import 'pairing_protocol.dart' show PairedKid, PairingTransport;
import 'pairing_records.dart' show LocalStorePairedKidsRepository;
import 'village_lan.dart';
import 'village_link.dart';
import 'village_meet.dart';
import 'welcome_logic.dart';
import 'welcome_screens.dart' show WelcomeChild;

/// A road that is answering: the endpoint is up (and advertised) until [stop].
abstract class VillageServing {
  Uint8List get handle;
  Future<void> stop();
}

/// The way to the other phone. The real one is the same Wi-Fi; a test passes an in-memory one.
abstract class VillageNetwork {
  /// Starts answering the meet window and/or the door.
  Future<VillageServing> serve({VillageMeetWindow? meet, VillageDoor? door});

  /// Village endpoints seen nearby. Listening starts the search; cancelling the subscription stops it.
  Stream<NearbyVillage> nearby();

  /// A way to send one message to [n].
  PairingTransport open(NearbyVillage n);
}

class _LanServing implements VillageServing {
  _LanServing(this._host);
  final VillageLanHost _host;
  @override
  Uint8List get handle => _host.handle;
  @override
  Future<void> stop() => _host.stop();
}

class LanVillageNetwork implements VillageNetwork {
  const LanVillageNetwork();

  @override
  Future<VillageServing> serve({VillageMeetWindow? meet, VillageDoor? door}) async {
    final VillageLanHost host = VillageLanHost(meet: meet, door: door);
    await host.start();
    return _LanServing(host);
  }

  @override
  Stream<NearbyVillage> nearby() {
    VillageLanBrowser? b;
    StreamSubscription<NearbyVillage>? sub;
    late final StreamController<NearbyVillage> c;
    c = StreamController<NearbyVillage>(
      onListen: () async {
        b = VillageLanBrowser();
        try {
          await b!.start();
          sub = b!.found.listen(c.add);
        } catch (_) {
          // No discovery on this phone (permission, no Wi-Fi): the stream simply stays quiet.
        }
      },
      onCancel: () async {
        await sub?.cancel();
        await b?.stop();
      },
    );
    return c.stream;
  }

  @override
  PairingTransport open(NearbyVillage n) => VillageLanTransport(n.host, n.port);
}

/// Everything the village screens need from this phone, in one place. Built once per open of "Your village".
class VillageServices {
  VillageServices({
    required this.family,
    required this.reminders,
    required this.deviceKey,
    required this.pairedKids,
    required this.guardianName,
    required this.childName,
    required this.children,
    required this.network,
    required this.confirmPin,
    this.openHelpers,
    this.pollEvery = const Duration(seconds: 2),
    this.syncEvery = const Duration(seconds: 20),
    this.deviceLabel = 'This phone',
    int Function()? now,
    Random? random,
  })  : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _random = random; // ignore: prefer_initializing_formals

  final FamilyRepository family;
  final WelcomeRemindersRepository reminders;
  final Future<DeviceKey> Function() deviceKey;
  final Future<List<PairedKid>> Function() pairedKids;
  final Future<String> Function() guardianName;
  final String childName;
  final List<WelcomeChild> children;
  final VillageNetwork network;

  /// Asks for the grown-up's PIN. True only when it checked out. A phone with no PIN answers false: welcoming needs one.
  final Future<bool> Function(BuildContext) confirmPin;

  /// Opens the helper pages (sitter pass, grandparent page, school summary) for the "helper, no app" choice.
  final VoidCallback? openHelpers;
  final Duration pollEvery, syncEvery;

  /// The name this phone gives itself when it is introduced. A grown-up can see it on the other phone to be sure.
  final String deviceLabel;
  final int Function() _now;
  final Random? _random;

  int now() => _now();

  FamilyContext? _ctx;
  DeviceKey? _device;

  Future<DeviceKey> device() async => _device ??= await deviceKey();

  /// The family this phone holds, or null when there is none. Throws [FamilyRecordUnusable] for a record that is stored
  /// but cannot be read (it is left exactly as it is).
  Future<FamilyContext?> load() async {
    final FamilyContext? cached = _ctx;
    if (cached != null) return cached;
    final DeviceKey d = await device();
    final FamilyContext? have = await FamilyContext.load(family, d, nowMs: now());
    if (have != null) return _ctx = have;
    if (await family.hasRecord()) throw FamilyRecordUnusable();
    return null;
  }

  /// Founds this phone\'s family (once). Reads the paired tablets, writes no pairing record.
  Future<FamilyContext> found() async {
    final FamilyContext? have = await load();
    if (have != null) return have;
    final FamilyContext c = await FamilyFounder.ensure(
        device: await device(),
        guardianName: await guardianName(),
        kids: await pairedKids(),
        nowMs: now(),
        repo: family,
        random: _random);
    return _ctx = c;
  }

  /// Keeps the record a grown-up offered this phone, after the new person said yes. Never replaces a family.
  Future<FamilyContext> adopt({
    required AgreementKey agreement,
    required List<LedgerEntry> entries,
    required List<LedgerVote> votes,
  }) async {
    final FamilyContext c = await adoptOfferedRecord(
        device: await device(), agreement: agreement, entries: entries, votes: votes, repository: family, nowMs: now());
    return _ctx = c;
  }

  WelcomeService welcome(FamilyContext c) => WelcomeService(
        context: c, repository: family, reminders: reminders, nowMs: now, childName: childName, random: _random);

  VillageDoor door(FamilyContext c, {void Function()? onChanged}) =>
      VillageDoor(context: c, repository: family, nowMs: now, onChanged: onChanged, random: _random);

  /// Over the real on-device store. [childId] and [childName] come from the local family; [localFamilyName] founds it.
  factory VillageServices.from(
    LocalServices s, {
    required LocalPinService pin,
    required String childId,
    required String childName,
    required String guardianName,
    VoidCallback? openHelpers,
    VillageNetwork network = const LanVillageNetwork(),
  }) {
    final LocalNamespace ledger = s.area('familyledger', ownerId: kLocalGuardianScope);
    return VillageServices(
      family: LocalStoreFamilyRepository(ledger),
      reminders: LocalStoreWelcomeReminders(ledger),
      deviceKey: () => DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(s.area('devicekey'))),
      pairedKids: () => LocalStorePairedKidsRepository(s.area('pairedkids', ownerId: kLocalGuardianScope)).load(),
      guardianName: () async => guardianName,
      childName: childName,
      children: <WelcomeChild>[WelcomeChild(childId, childName)],
      network: network,
      openHelpers: openHelpers,
      confirmPin: (BuildContext c) => askAdultPin(c, pin),
    );
  }
}

/// The adult gate for the village: the existing local PIN dialog. A phone with no PIN is told to set one first (a child
/// holding an unlocked phone must not be able to welcome anyone, or say yes to being welcomed).
Future<bool> askAdultPin(BuildContext context, LocalPinService pin) async {
  if (!await pin.isSet()) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Set a PIN on this phone first (Settings, Safety). Welcoming someone needs it.')));
    }
    return false;
  }
  if (!context.mounted) return false;
  return askLocalPin(context, pin, title: 'Enter your PIN', why: 'Welcoming someone is for grown-ups.');
}
