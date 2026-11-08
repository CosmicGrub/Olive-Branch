// OLIVE BRANCH — the LOCAL family bootstrap: the guardian phone as a family.
// No longer UNVERIFIED — verified by CI (client/test/local_family_test.dart).
// MASTERFILE §8.5.9.
//
// This is the local half of audit findings A-G1/A-G2: today a new parent cannot
// start at all (there is no sign-up, so a fresh guardian build can only pair with a
// code another guardian made) and an offline launch lands on a PIN-setup trap. The
// guardian onboarding (guardian_onboarding.dart) writes ONE record here, on the
// device, with no server:
//
//   * the guardian: their name, and the label the child sees (Mom, Dad, or a word
//     they chose: Grandma, Nana, Uncle Sam);
//   * the child: first name and age. The age is LOCKED the moment it is entered;
//     the kid picker offers 5 to 15, a guardian may set 3 to 17 here (the contact
//     rule, contact_labels.dart), and changing a locked age needs the guardian PIN
//     gate ([changeAgeWithPin]);
//   * the child's home time zone: "this phone" or one of [kHomeZones].
//
// THE GUARDIAN IS A CONTACT. [grownups] turns the record into the
// [GrownupContact]s the kid screens use, with a stable id ([kLocalGuardianContactId]),
// so a nickname she gave that contact ("Dada") keeps applying, and the guardian sees
// "Dad (Ivy calls you Dada)" but can never write the nickname.
//
// SYNC: none. The record is local to this device until the device is connected;
// connecting does not upload it (no route takes it). Nothing here is a score, a
// count or a location (P2, P3): a time zone is a region name, not a place.
//
// Storage: the sealed `localfamily` area (`guardian.local-guardian.localfamily`).
import 'contact_labels.dart';
import 'device_role.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_store.dart';

/// The contact id of the guardian who set this device up.
const String kLocalGuardianContactId = kLocalGuardianScope;

/// "The time zone of this phone": the child lives where the phone is.
const String kHomeZoneDevice = 'device';

const int kMaxNameLength = 40;

class HomeZone {
  const HomeZone(this.id, this.label);
  final String id;
  final String label;
}

/// A short list of region names. The phone has no zone database, so a zone other
/// than [kHomeZoneDevice] is remembered and not converted offline (the guardian
/// home shows no clock for it until the device is connected).
const List<HomeZone> kHomeZones = <HomeZone>[
  HomeZone(kHomeZoneDevice, 'Same as this phone'),
  HomeZone('America/New_York', 'US Eastern'),
  HomeZone('America/Chicago', 'US Central'),
  HomeZone('America/Denver', 'US Mountain'),
  HomeZone('America/Los_Angeles', 'US Pacific'),
  HomeZone('America/Anchorage', 'Alaska'),
  HomeZone('Pacific/Honolulu', 'Hawaii'),
  HomeZone('America/Toronto', 'Toronto'),
  HomeZone('America/Mexico_City', 'Mexico City'),
  HomeZone('America/Sao_Paulo', 'Sao Paulo'),
  HomeZone('Europe/London', 'London'),
  HomeZone('Europe/Paris', 'Paris, Berlin, Madrid'),
  HomeZone('Europe/Athens', 'Athens, Helsinki'),
  HomeZone('Europe/Moscow', 'Moscow'),
  HomeZone('Africa/Lagos', 'Lagos'),
  HomeZone('Africa/Johannesburg', 'Johannesburg'),
  HomeZone('Africa/Nairobi', 'Nairobi'),
  HomeZone('Asia/Dubai', 'Dubai'),
  HomeZone('Asia/Kolkata', 'India'),
  HomeZone('Asia/Singapore', 'Singapore'),
  HomeZone('Asia/Shanghai', 'China'),
  HomeZone('Asia/Tokyo', 'Tokyo'),
  HomeZone('Australia/Sydney', 'Sydney'),
  HomeZone('Pacific/Auckland', 'Auckland'),
];

bool isKnownHomeZone(String id) => kHomeZones.any((HomeZone z) => z.id == id);

String homeZoneLabel(String id) {
  for (final HomeZone z in kHomeZones) {
    if (z.id == id) return z.label;
  }
  return id;
}

class LocalFamily {
  const LocalFamily({
    required this.guardianName,
    required this.guardianLabel,
    required this.guardianKind,
    required this.childName,
    required this.age,
    this.ageLocked = true,
    this.homeZone = kHomeZoneDevice,
  });

  final String guardianName;
  final String guardianLabel;
  final GrownupKind guardianKind;
  final String childName;
  final int age;
  final bool ageLocked;
  final String homeZone;

  /// The age and whether it is locked, in the form the label rules take.
  AgeLockState get ageLock => AgeLockState(age: age, locked: ageLocked);

  GrownupContact get guardian =>
      GrownupContact(id: kLocalGuardianContactId, guardianLabel: guardianLabel, kind: guardianKind);

  /// Every grown-up in this local family (today: the one who set it up).
  List<GrownupContact> get grownups => <GrownupContact>[guardian];

  /// The first thing wrong with these answers, in plain words, or null. Used by the
  /// onboarding to hold the Next button and by [fromJson] to refuse a damaged record.
  static String? problem({
    required String guardianName,
    required String guardianLabel,
    required String childName,
    required int age,
    String homeZone = kHomeZoneDevice,
  }) {
    final String g = guardianName.trim(), l = guardianLabel.trim(), c = childName.trim();
    if (g.isEmpty) return 'Please add your name.';
    if (l.isEmpty) return 'Please choose what she should call you.';
    if (c.isEmpty) return 'Please add her first name.';
    if (g.length > kMaxNameLength || l.length > kMaxNicknameLength || c.length > kMaxNameLength) {
      return 'That is a little too long.';
    }
    if (age < kGuardianAgeMin || age > kGuardianAgeMax) {
      return 'Her age should be between $kGuardianAgeMin and $kGuardianAgeMax.';
    }
    if (!isKnownHomeZone(homeZone)) return 'Please choose a time zone from the list.';
    return null;
  }

  /// A new, locked record from the onboarding answers (trimmed). Throws
  /// [ArgumentError] with the plain-words problem when they are not valid.
  factory LocalFamily.fromAnswers({
    required String guardianName,
    required String guardianLabel,
    required GrownupKind guardianKind,
    required String childName,
    required int age,
    String homeZone = kHomeZoneDevice,
  }) {
    final String? p = problem(
        guardianName: guardianName, guardianLabel: guardianLabel, childName: childName,
        age: age, homeZone: homeZone);
    if (p != null) throw ArgumentError(p);
    return LocalFamily(
      guardianName: guardianName.trim(),
      guardianLabel: guardianLabel.trim(),
      guardianKind: guardianKind,
      childName: childName.trim(),
      age: age,
      ageLocked: true,
      homeZone: homeZone,
    );
  }

  /// Changes the locked age. [guardianPinOk] must be the result of the PIN gate
  /// (local_pin.dart); without it a locked age does not move. Within 3 to 17.
  LocalFamily changeAgeWithPin(int newAge, {required bool guardianPinOk}) {
    final AgeLockState next = changeAge(ageLock, newAge, guardianPinOk: guardianPinOk);
    return LocalFamily(
      guardianName: guardianName,
      guardianLabel: guardianLabel,
      guardianKind: guardianKind,
      childName: childName,
      age: next.age ?? age,
      ageLocked: next.locked,
      homeZone: homeZone,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'guardianName': guardianName,
        'guardianLabel': guardianLabel,
        'guardianKind': guardianKind.name,
        'childName': childName,
        'age': age,
        'ageLocked': ageLocked,
        'homeZone': homeZone,
      };

  /// Fail-closed decode: any field of the wrong type, or a value [problem] refuses,
  /// makes the whole record "no family" (the onboarding runs again) rather than a
  /// half-trusted one.
  static LocalFamily? fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != 1) return null;
    final Object? gn = raw['guardianName'], gl = raw['guardianLabel'], gk = raw['guardianKind'];
    final Object? cn = raw['childName'], age = raw['age'], zone = raw['homeZone'];
    if (gn is! String || gl is! String || cn is! String || age is! int) return null;
    final GrownupKind? kind = GrownupKind.values.where((GrownupKind k) => k.name == gk).firstOrNull;
    if (kind == null) return null;
    final String z = zone is String ? zone : kHomeZoneDevice;
    if (problem(guardianName: gn, guardianLabel: gl, childName: cn, age: age, homeZone: z) != null) {
      return null;
    }
    return LocalFamily(
      guardianName: gn,
      guardianLabel: gl,
      guardianKind: kind,
      childName: cn,
      age: age,
      ageLocked: raw['ageLocked'] != false,
      homeZone: z,
    );
  }
}

abstract class LocalFamilyRepository {
  Future<LocalFamily?> load();
  Future<void> save(LocalFamily family);
  Future<void> clear();
}

class MemoryLocalFamilyRepository implements LocalFamilyRepository {
  MemoryLocalFamilyRepository([this._f]);
  LocalFamily? _f;
  @override
  Future<LocalFamily?> load() async => _f;
  @override
  Future<void> save(LocalFamily family) async => _f = family;
  @override
  Future<void> clear() async => _f = null;
}

class LocalStoreLocalFamilyRepository implements LocalFamilyRepository {
  LocalStoreLocalFamilyRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'family';
  @override
  Future<LocalFamily?> load() async => LocalFamily.fromJson(await _ns.get(_key));
  @override
  Future<void> save(LocalFamily family) => _ns.put(_key, family.toJson());
  @override
  Future<void> clear() => _ns.delete(_key);
}

/// The guardian label to offer for a role: "Mom", "Dad", or empty for someone else.
String suggestedGuardianLabel(DeviceRole role) => role.defaultLabel;

/// A label that IS "Mom" or "Dad" is treated as one (so the age-default words apply: Mommy and
/// Daddy at a locked age of 5 to 15). Any other word the grown-up chose (Mama, Nana, Uncle
/// Sam) is theirs and is shown to the child as it is, so the kind is "other".
GrownupKind kindForGuardianLabel(String label) {
  final String t = label.trim().toLowerCase();
  if (t == 'mom') return GrownupKind.mom;
  if (t == 'dad') return GrownupKind.dad;
  return GrownupKind.other;
}
