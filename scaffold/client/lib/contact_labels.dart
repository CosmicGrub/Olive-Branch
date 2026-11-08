// OLIVE BRANCH — what a child calls her grown-ups, and the age lock that picks
// the default words. No longer UNVERIFIED — verified by CI
// (client/test/contact_labels_test.dart). MASTERFILE §8.5.7.
//
// Pure logic plus one small repository. Nothing here touches a screen; the
// first-run flow and the child screens ADOPT it (the repo-wide adoption of the
// hard-coded 'Dad'/'Mom' strings is a listed follow-up, MASTERFILE §8.5.7).
//
// THE NICKNAME LAYER. Every grown-up contact has a guardian-chosen label
// ([GrownupContact.guardianLabel]) and an optional child-chosen nickname.
// ALL child-facing text shows, in this order: her nickname, else the
// age-default word for a Mom or a Dad, else the guardian's label. The
// guardian's own screens show both ("Ivy calls you Dada"). The nickname is the
// CHILD'S data: [NicknameRepository] has the only writer, and
// [NicknameReader] (all a guardian screen gets) cannot write.
//
// THE AGE RULE (owner's wording, 2026-11-08), in ONE place: [kLittleWordsAges].
// Before her age is locked the defaults are the neutral 'Mom' and 'Dad'. Once
// it is locked and falls inside 5 to 15 they become 'Mommy' and 'Daddy'; at 16
// and over, and in any unlocked state, they stay 'Mom' and 'Dad'.
//
// THE AGE LOCK. The picker she sees offers 5 to 15 ([kKidAgeMin]/[kKidAgeMax]);
// a guardian may set 3 to 17 in the family screens ([kGuardianAgeMin]/Max).
// Once locked, only a guardian who has passed the PIN gate can change it.
import 'local_store.dart';

const int kKidAgeMin = 5, kKidAgeMax = 15;
const int kGuardianAgeMin = 3, kGuardianAgeMax = 17;

/// The ages (inclusive, once locked) at which the default words are the
/// little-child ones. Change this one constant to change the rule.
const ({int min, int max}) kLittleWordsAges = (min: 5, max: 15);

/// The words offered in the rename bank; she can always type her own.
const List<String> kNicknameBank = <String>[
  'Mommy', 'Mama', 'Mum', 'Mom', 'Mummy', 'Daddy', 'Dada', 'Papa', 'Pop', 'Dad',
];

const int kMaxNicknameLength = 24;

enum GrownupKind { mom, dad, other }

class GrownupContact {
  const GrownupContact({required this.id, required this.guardianLabel, this.kind = GrownupKind.other});
  final String id;
  /// What the grown-up (or the family builder) called this person.
  final String guardianLabel;
  final GrownupKind kind;
}

class AgeLockState {
  const AgeLockState({this.age, this.locked = false});
  final int? age;
  final bool locked;
}

/// The kid picker: 5 to 15, anything else is clamped. Locks the age.
AgeLockState lockKidAge(int tapped) =>
    AgeLockState(age: tapped.clamp(kKidAgeMin, kKidAgeMax), locked: true);

/// Changes the age. Unlocked: anyone. Locked: only with [guardianPinOk] (the
/// caller passes the result of the PIN gate), within 3 to 17. A refusal returns
/// the state unchanged.
AgeLockState changeAge(AgeLockState s, int newAge, {required bool guardianPinOk}) {
  if (s.locked && !guardianPinOk) return s;
  final int lo = guardianPinOk ? kGuardianAgeMin : kKidAgeMin;
  final int hi = guardianPinOk ? kGuardianAgeMax : kKidAgeMax;
  return AgeLockState(age: newAge.clamp(lo, hi), locked: s.locked || guardianPinOk);
}

class ContactLabels {
  const ContactLabels._();

  /// The age-default word for a Mom or a Dad, or null for anyone else.
  static String? ageDefault(GrownupKind kind, AgeLockState age) {
    if (kind == GrownupKind.other) return null;
    final bool little = age.locked &&
        age.age != null &&
        age.age! >= kLittleWordsAges.min &&
        age.age! <= kLittleWordsAges.max;
    return kind == GrownupKind.mom ? (little ? 'Mommy' : 'Mom') : (little ? 'Daddy' : 'Dad');
  }

  /// What the CHILD sees: nickname, else age default, else the guardian label.
  static String forChild(GrownupContact c, {required AgeLockState age, Map<String, String> nicknames = const {}}) {
    final String? nick = cleanNickname(nicknames[c.id]);
    return nick ?? ageDefault(c.kind, age) ?? c.guardianLabel;
  }

  /// What a GUARDIAN sees: their own label, and how she says it if she renamed it.
  static String forGuardian(GrownupContact c, {required String childName, Map<String, String> nicknames = const {}}) {
    final String? nick = cleanNickname(nicknames[c.id]);
    if (nick == null || nick == c.guardianLabel) return c.guardianLabel;
    return '${c.guardianLabel} ($childName calls you $nick)';
  }

  /// Trimmed, non-empty, at most [kMaxNicknameLength]; otherwise null.
  static String? cleanNickname(String? raw) {
    final String t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    return t.length > kMaxNicknameLength ? t.substring(0, kMaxNicknameLength) : t;
  }
}

/// Read-only: what a guardian screen is handed.
abstract class NicknameReader {
  Future<Map<String, String>> load();
}

/// The child's own writer. Nothing a guardian screen holds can reach it.
abstract class NicknameRepository implements NicknameReader {
  /// An empty or blank name removes the nickname (back to the default).
  Future<void> set(String contactId, String? nickname);
}

class MemoryNicknameRepository implements NicknameRepository {
  final Map<String, String> _m = <String, String>{};
  @override
  Future<Map<String, String>> load() async => Map<String, String>.of(_m);
  @override
  Future<void> set(String contactId, String? nickname) async {
    final String? n = ContactLabels.cleanNickname(nickname);
    if (n == null) {
      _m.remove(contactId);
    } else {
      _m[contactId] = n;
    }
  }
}

class LocalNicknameRepository implements NicknameRepository {
  LocalNicknameRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'names';

  @override
  Future<Map<String, String>> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return <String, String>{};
    final Map<String, String> out = <String, String>{};
    raw.forEach((Object? k, Object? v) {
      final String? n = v is String ? ContactLabels.cleanNickname(v) : null;
      if (k is String && n != null) out[k] = n;
    });
    return out;
  }

  @override
  Future<void> set(String contactId, String? nickname) async {
    final Map<String, String> all = await load();
    final String? n = ContactLabels.cleanNickname(nickname);
    if (n == null) {
      all.remove(contactId);
    } else {
      all[contactId] = n;
    }
    await _ns.put(_key, all);
  }
}
