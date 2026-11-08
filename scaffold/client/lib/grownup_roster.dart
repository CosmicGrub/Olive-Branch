// OLIVE BRANCH — who her grown-ups are, as far as THIS device knows. No longer
// UNVERIFIED — verified by CI (client/test/grownup_roster_test.dart). MASTERFILE §8.5.10.
//
// The kid screens ("who are my grown-ups", "what do you call them", "My people") need a list of
// [GrownupContact]s and her locked age. Where they come from depends on what the device holds:
//
//  * A LOCAL FAMILY exists (a grown-up set the device up, local_family.dart): the contacts are
//    that family's grown-ups, with their real labels and kinds, and the age is the family's
//    locked age. A Mom or a Dad shows as Mommy or Daddy at a locked 5 to 15.
//  * Nothing known yet (a child's own device, before it is connected): two generic placeholders
//    with NEUTRAL names ("Your grown-up", "Your other grown-up"), so no screen invents a Dad or
//    a Mom who may not exist (the reason #150 left the "who" step out before pairing). She can
//    still give each a name of her own; that is a word, not a claim about a person.
//
// After the device is connected the real contacts come from the server (a follow-up, MASTERFILE
// §22); until then the nickname map keeps applying by contact id. When the connected child's
// storage is opened, nicknames she gave before connecting are copied over by
// [adoptPendingNicknames] (same ids, nothing renamed or dropped).
import 'contact_labels.dart';
import 'local_family.dart';
import 'local_repositories.dart';
import 'onboarding_draft.dart';

const String kPlaceholderGrownupOne = 'placeholder-1';
const String kPlaceholderGrownupTwo = 'placeholder-2';

List<GrownupContact> placeholderGrownups() => const <GrownupContact>[
      GrownupContact(id: kPlaceholderGrownupOne, guardianLabel: 'Your grown-up'),
      GrownupContact(id: kPlaceholderGrownupTwo, guardianLabel: 'Your other grown-up'),
    ];

/// What the kid screens use: the contacts, whether they are real people the device knows (so the
/// "who is here" step may name them), and her age lock.
class KidRoster {
  const KidRoster({required this.contacts, required this.known, required this.age, this.childName = ''});
  final List<GrownupContact> contacts;

  /// Her first name as the local family has it, or empty when the device does not know it.
  final String childName;
  final bool known;
  final AgeLockState age;
}

/// The roster for this device. [families] is the device's local family store, or null in a build
/// that has none. A read that throws counts as "no local family": a kid is never blocked by it.
Future<KidRoster> loadKidRoster(LocalFamilyRepository? families, {AgeLockState fallbackAge = const AgeLockState()}) async {
  LocalFamily? family;
  try {
    family = await families?.load();
  } catch (_) {
    family = null;
  }
  if (family != null) {
    return KidRoster(
        contacts: family.grownups, known: true, age: family.ageLock, childName: family.childName);
  }
  return KidRoster(contacts: placeholderGrownups(), known: false, age: fallbackAge);
}

/// Moves every nickname in [from] (the pending-device store) into [to] (the connected child's). Hers
/// win: a name already in [to] is never overwritten. Each moved name is removed from [from] so it is
/// done once. Returns how many were copied. Never throws, and never loses a name: a name leaves
/// [from] only after [to] has it.
Future<int> adoptPendingNicknames({required NicknameRepository from, required NicknameRepository to}) async {
  try {
    final Map<String, String> pending = await from.load();
    if (pending.isEmpty) return 0;
    final Map<String, String> have = await to.load();
    int copied = 0;
    for (final MapEntry<String, String> e in pending.entries) {
      if (!have.containsKey(e.key)) {
        await to.set(e.key, e.value);
        copied++;
      }
      await from.set(e.key, null);
    }
    return copied;
  } catch (_) {
    return 0;
  }
}

/// What she decided BEFORE this device was connected stays hers after it is: the age she tapped (locked,
/// remembered with her profile on THIS device) and the names she gave her grown-ups (moved from the
/// pending-device store to hers, nothing overwritten). Both best effort: a store that cannot be written
/// must never stop her reaching her home. Called by main_live.dart's boot gate once there is an identity.
Future<void> carryOverFirstRun({
  required String childId,
  required ProfileCacheRepository profile,
  required OnboardingDraftRepository draftRepo,
  required NicknameRepository pendingNicknames,
  required NicknameRepository hersNicknames,
}) async {
  try {
    final OnboardingDraft? waiting = await draftRepo.load();
    if (waiting != null && waiting.complete && waiting.ageLocked && waiting.age != null) {
      await profile.lockAge(waiting.age!);
    }
  } catch (_) {
    // The draft stays where it is; the next boot tries again.
  }
  if (childId == kPendingDeviceScope) return;
  await adoptPendingNicknames(from: pendingNicknames, to: hersNicknames);
}
