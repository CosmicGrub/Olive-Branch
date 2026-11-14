// OLIVE BRANCH — who a device may play with, and the keys it plays with. UNVERIFIED on a device (the stores are
// the real sealed areas; CI runs them in memory, client/test/play_credentials_test.dart).
//
// A "Play together" session is allowed only between two devices that were PAIRED by the adult-gate work
// (pairing_protocol.dart, device_keys.dart): a child's device holds the certificate and the key of the grown-up
// that approved it; a grown-up's device holds the keys of the child devices it approved. This file is the one place
// that reads those records and turns them into what [PlayAdmission] needs. A device with no such record has
// nothing to play with ([PlayCredentials] is null) and the game says so calmly instead of opening a socket:
// an unpaired device cannot play.
//
// WHICH SIDE. The role string every game screen already passes decides: 'ivy' is the child's device, anything else
// is a grown-up's (local_pairing.dart's own `mySide` rule).
//
// REMEMBERING THE GROWN-UP'S YES. The first connection of a child device waits for the grown-up's confirmation
// card; the answer is kept (fingerprints only) inside the sealed 'pairedkids' area under its own key, so the
// next game does not ask again, and "Forget this tablet" (which removes the kid) removes the way in with it.
import 'dart:typed_data';

import 'device_keys.dart';
import 'local_pin.dart' show LocalStoreLocalPinRepository, kLocalGuardianScope;
import 'local_services.dart';
import 'local_store.dart';
import 'pairing_protocol.dart' show ChildPairing, PairedKid;
import 'pairing_records.dart';
import 'play_admission.dart';

/// Everything a device needs to take part in an admitted play session.
class PlayCredentials {
  PlayCredentials({
    required this.own,
    required this.peerKeys,
    required this.adult,
    Set<String>? confirmed,
    this.onConfirmed,
  }) : confirmed = confirmed ?? <String>{};

  /// This device's own signing key.
  final DeviceKey own;

  /// The device keys this device is paired with: the one grown-up on a child's device, every approved child device
  /// on a grown-up's.
  final List<Uint8List> peerKeys;

  /// A grown-up's device (it confirms a first connection); false for a child's (it never asks).
  final bool adult;

  /// Fingerprints (base64url) the grown-up already said yes to.
  final Set<String> confirmed;
  final void Function(String fingerprint)? onConfirmed;

  PlayAdmission buildAdmission({DateTime Function()? now}) => adult
      ? PlayAdmission.forAdult(own, <PairedKid>[for (final Uint8List k in peerKeys) _asKid(k)],
          confirmed: confirmed, onConfirmed: onConfirmed, now: now)
      : PlayAdmission.forChild(own, peerKeys.first, now: now);

  static PairedKid _asKid(Uint8List key) =>
      PairedKid(certId: '', childDeviceKey: key, childId: '', deviceName: '', issuedAtMs: 0);
}

/// Where credentials come from. The real one reads the sealed local areas; a test installs a fixed one.
abstract class PlayCredentialsSource {
  /// Null when this device was never paired (so it cannot play).
  Future<PlayCredentials?> load({required bool adult});

  /// The source every game screen uses. Tests replace it.
  static PlayCredentialsSource current = const LocalStorePlayCredentials();
}

/// A fixed answer, for tests and previews.
class FixedPlayCredentials implements PlayCredentialsSource {
  FixedPlayCredentials({this.adultSide, this.childSide});
  final PlayCredentials? adultSide, childSide;
  @override
  Future<PlayCredentials?> load({required bool adult}) async => adult ? adultSide : childSide;
}

/// Reads [LocalServices.current]: the device key, the child's pairing record, the grown-up's approved children.
class LocalStorePlayCredentials implements PlayCredentialsSource {
  const LocalStorePlayCredentials();

  static const String confirmedKey = 'playconfirmed';

  @override
  Future<PlayCredentials?> load({required bool adult}) async {
    try {
      final LocalServices services = LocalServices.current;
      final DeviceKey own = await DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(services.area('devicekey')));
      if (!adult) {
        final ChildPairing? p = await LocalStoreChildPairingRepository(
                services.area('childpairing'), LocalStoreLocalPinRepository(services.area('adultunlock')))
            .load();
        if (p == null) return null;
        return PlayCredentials(own: own, peerKeys: <Uint8List>[p.adultKey], adult: false);
      }
      final LocalNamespace ns = services.area('pairedkids', ownerId: kLocalGuardianScope);
      final List<PairedKid> kids = await LocalStorePairedKidsRepository(ns).load();
      if (kids.isEmpty) return null;
      final Set<String> confirmed = <String>{};
      final Object? raw = await ns.get(confirmedKey);
      if (raw is List) {
        for (final Object? e in raw) {
          if (e is String && e.length <= 64) confirmed.add(e);
        }
      }
      return PlayCredentials(
        own: own,
        peerKeys: <Uint8List>[for (final PairedKid k in kids) k.childDeviceKey],
        adult: true,
        confirmed: confirmed,
        onConfirmed: (String fp) {
          confirmed.add(fp);
          // Fire and forget: failing to remember only means the grown-up is asked once more.
          ns.put(confirmedKey, confirmed.toList()).then((_) {}, onError: (Object _) {});
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// The calm line a device shows when it cannot play because it was never paired. No blame, no codes, no jargon.
String unpairedPlayLine({required bool adult}) => adult
    ? "Set up a child's device with this phone first, then you can play together."
    : 'A grown-up sets this up first.';
