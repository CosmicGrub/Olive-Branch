// Shared helpers for the village road tests (village_link, village_meet, village_lan and the screens): several PHONES
// of one family, each with its OWN copy of the record, so that what one phone knows reaches another only through the
// road under test. Not a test file.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;

import 'package:olive_client/device_keys.dart' show b64, unb64;
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/pairing_protocol.dart' show PairedKid, PairingTransport;
import 'package:olive_client/village_lan.dart' show NearbyVillage;
import 'package:olive_client/village_link.dart';
import 'package:olive_client/village_people.dart';
import 'package:olive_client/village_meet.dart';
import 'package:olive_client/village_welcome_host.dart';
import 'package:olive_client/welcome_screens.dart' show WelcomeChild;
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';

/// One phone: its person, its own copy of the record, and a door over it.
class Phone {
  Phone._(this.p, this.ctx, this.repo, this.clock);
  final P p;
  final FamilyContext ctx;
  final MemoryFamilyRepository repo;
  final Clock clock;
  int changes = 0;

  late final VillageDoor door = VillageDoor(
      context: ctx, repository: repo, nowMs: () => clock.now, onChanged: () => changes++);

  WelcomeService welcome() => WelcomeService(
      context: ctx, repository: repo, reminders: MemoryWelcomeReminders(), nowMs: () => clock.now, childName: 'Ivy');

  PeopleService people() => PeopleService(context: ctx, repository: repo, nowMs: () => clock.now, childName: 'Ivy');

  static Phone of(P p, {required List<LedgerEntry> entries, required List<LedgerVote> votes, required FamilyPin pin, required Clock clock}) =>
      Phone._(
        p,
        FamilyContext(
          device: p.key,
          agreement: p.agree,
          keyring: FamilyKeyring(guardianDevice: true),
          entries: List<LedgerEntry>.of(entries),
          votes: List<LedgerVote>.of(votes),
          pin: pin,
        ),
        MemoryFamilyRepository(),
        clock,
      );

  Future<LedgerState> state() => ctx.state(nowMs: clock.now);

  /// An order-stable description of what this phone believes, to prove two phones agree.
  Future<String> summary() async => Fam.summary(await state());

  /// Sends everything this phone has to [other] over the door and takes the answer back, as the road would.
  Future<DoorOutcome> reach(Phone other) => door.exchange((Map<String, dynamic> m) => other.door.handle(m));
}

class Clock {
  Clock(this.now);
  int now;
}

/// Mom founded the family; Dad was welcomed and has finished settling in. Each has their own copy.
class Village {
  Village._(this.fam, this.mom, this.dad, this.clock, this.tablet);
  final Fam fam;

  /// A child's tablet the family lists (null unless asked for).
  final P? tablet;
  final Phone mom, dad;
  final Clock clock;

  static Future<Village> make({bool tablet = false, FamilyPolicy policy = const FamilyPolicy()}) async {
    final P m = await P.make(1), d = await P.make(2);
    final Fam fam = await Fam.found(m, policy: policy);
    await fam.welcomeParent(m, d, others: <P>[]);
    final P? tab = tablet ? await P.make(8) : null;
    if (tab != null) await fam.addChild(m, tab);
    final Clock clock = Clock(fam.clock + 4 * day);
    return Village._(
      fam,
      Phone.of(m, entries: fam.entries, votes: fam.votes, pin: fam.pin, clock: clock),
      Phone.of(d, entries: fam.entries, votes: fam.votes, pin: fam.pin, clock: clock),
      clock,
      tab,
    );
  }

  /// A phone that is not (yet) in the family at all.
  Future<P> stranger(int n) => P.make(n);

  /// A copy of the family for a phone that has just been offered the record.
  Phone join(P p) =>
      Phone.of(p, entries: mom.ctx.entries, votes: mom.ctx.votes, pin: fam.pin, clock: clock);
}

MemberProfile carerProfile() => MemberProfile.defaults(Preset.trustedCarer);
extension PendingFor on LedgerState {
  PendingItem? pendingFor(String hashHex) {
    for (final PendingItem p in pending) {
      if (p.hashHex == hashHex) return p;
    }
    return null;
  }

  bool hasMember(String gidHex) => members.any((LedgerMember m) => m.gidHex == gidHex);

  /// Whether this person's phone is an active device in the family. (A request gives the person a fresh random id, so
  /// a test asks by the phone's key, never by a guessed id: asking by a guessed id is false for everyone.)
  bool hasPerson(P p) => deviceFor(p.key.publicKey) != null;
}

Uint8List flip(Uint8List b, int i) => Uint8List.fromList(b)..[i] ^= 1;

// ---------------------------------------------------------------------------------------------------------------
// An in-memory Wi-Fi, and an app on a phone
// ---------------------------------------------------------------------------------------------------------------

class _Ep {
  _Ep(this.meet, this.door);
  final VillageMeetWindow? meet;
  final VillageDoor? door;
}

/// The air between phones: whoever serves is findable by everyone who looks, until they stop.
class Air {
  final Map<String, _Ep> _eps = <String, _Ep>{};
  final List<StreamController<NearbyVillage>> _listeners = <StreamController<NearbyVillage>>[];

  /// How many endpoints were EVER started: zero proves nothing opened a port.
  int started = 0;
  int get live => _eps.length;
  List<Uint8List> get handles => <Uint8List>[for (final String k in _eps.keys) unb64(k)];

  VillageNetwork phone() => _AirNet(this);

}

class _Serving implements VillageServing {
  _Serving(this.air, this.key, this.handle);
  final Air air;
  final String key;
  @override
  final Uint8List handle;
  @override
  Future<void> stop() async => air._eps.remove(key);
}

class _AirNet implements VillageNetwork {
  _AirNet(this.air);
  final Air air;

  NearbyVillage _near(String key) => NearbyVillage(handle: unb64(key), host: 'air', port: 0);

  @override
  Future<VillageServing> serve({VillageMeetWindow? meet, VillageDoor? door}) async {
    final Uint8List handle = meet?.discoveryHandle ?? Uint8List.fromList(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final String key = b64(handle);
    air._eps[key] = _Ep(meet, door);
    air.started++;
    for (final StreamController<NearbyVillage> l in air._listeners) {
      if (!l.isClosed) l.add(_near(key));
    }
    return _Serving(air, key, handle);
  }

  @override
  Stream<NearbyVillage> nearby() {
    late final StreamController<NearbyVillage> c;
    c = StreamController<NearbyVillage>(
      onListen: () {
        air._listeners.add(c);
        for (final String k in air._eps.keys.toList()) {
          c.add(_near(k));
        }
      },
      onCancel: () => air._listeners.remove(c),
    );
    return c.stream;
  }

  @override
  PairingTransport open(NearbyVillage n) => _AirTransport(air, n.key);
}

class _AirTransport implements PairingTransport {
  _AirTransport(this.air, this.key);
  final Air air;
  final String key;

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final _Ep? ep = air._eps[key];
    if (ep == null) return null;
    final Map<String, dynamic> m = jsonDecode(jsonEncode(message)) as Map<String, dynamic>;
    final Map<String, dynamic>? r = m['t'] == 'door' ? await ep.door?.handle(m) : await ep.meet?.handle(m, source: 'air');
    return r == null ? null : jsonDecode(jsonEncode(r)) as Map<String, dynamic>;
  }
}

/// One phone running the village screens: its own device key, its own family record, its own PIN answers.
class AppPhone {
  AppPhone._(this.p, this.repo, this.services, this.clock);
  final P p;
  final FamilyRepository repo;
  final VillageServices services;
  final Clock clock;

  /// Whether the next PIN check passes, and how many were asked.
  static final Map<VillageServices, PinBox> _pins = <VillageServices, PinBox>{};
  PinBox get pinBox => _pins[services]!;
  bool get pinOk => pinBox.ok;
  set pinOk(bool v) => pinBox.ok = v;
  int get pinAsked => pinBox.asked;

  static Future<AppPhone> make(int n, Air air, {String name = 'Mom', FamilyRepository? repo, Clock? clock, int Function()? now}) async {
    final P p = await P.make(n);
    final Clock c = clock ?? Clock(t0 + 10 * day);
    final FamilyRepository r = repo ?? MemoryFamilyRepository();
    final PinBox box = PinBox();
    late final VillageServices s;
    s = VillageServices(
      family: r,
      reminders: MemoryWelcomeReminders(),
      deviceKey: () async => p.key,
      pairedKids: () async => <PairedKid>[],
      guardianName: () async => name,
      childName: 'Ivy',
      children: const <WelcomeChild>[WelcomeChild('c1', 'Ivy')],
      network: air.phone(),
      confirmPin: (BuildContext _) async {
        box.asked++;
        return box.ok;
      },
      openHelpers: () => box.helpersOpened++,
      pollEvery: const Duration(milliseconds: 10),
      syncEvery: const Duration(milliseconds: 200),
      deviceLabel: '$name\'s phone',
      now: now ?? (() => c.now),
    );
    _pins[s] = box;
    return AppPhone._(p, r, s, c);
  }

  int get helpersOpened => pinBox.helpersOpened;
}

class PinBox {
  bool ok = true;
  int asked = 0;
  int helpersOpened = 0;
}
