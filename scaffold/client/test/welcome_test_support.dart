// Shared helpers for the village welcome tests: a small family under test, a clock the services share, and a
// service per phone. Not a test file.
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';

/// A small world: a family under test, a clock the services share, and a service per phone.
class World {
  World._(this.fam, this.mom, this.dad, this.cand);
  final Fam fam;
  final P mom;
  final P? dad;
  final P cand;
  int now = t0;

  static Future<World> make({bool twoParents = true, FamilyPolicy policy = const FamilyPolicy()}) async {
    final P mom = await P.make(1);
    final P? dad = twoParents ? await P.make(2) : null;
    final P cand = await P.make(5);
    final Fam fam = await Fam.found(mom, policy: policy);
    if (dad != null) {
      final LedgerEntry e = await fam.add(mom, EntryType.memberAdd, fam.memberBody(dad, electors: <P>[mom], name: 'Alex'));
      await fam.vote(dad, e, 'yes');
    }
    final World w = World._(fam, mom, dad, cand);
    w.now = fam.clock + 3 * day; // far enough that the second parent has finished settling in
    return w;
  }

  FamilyContext ctxFor(P p) => FamilyContext(
        device: p.key,
        agreement: p.agree,
        keyring: FamilyKeyring(guardianDevice: true),
        entries: fam.entries,
        votes: fam.votes,
        pin: fam.pin,
      );

  MemoryWelcomeReminders remindersFor = MemoryWelcomeReminders();

  WelcomeService svc(P p, {MemoryWelcomeReminders? reminders}) => WelcomeService(
        context: ctxFor(p),
        repository: MemoryFamilyRepository(),
        reminders: reminders ?? MemoryWelcomeReminders(),
        nowMs: () => now,
        childName: 'Ivy',
      );

  WelcomeDraft draft(MemberProfile p, {String name = 'Jo', P? who}) =>
      WelcomeDraft(personName: name, profile: p, candidate: (who ?? cand).rec);

  Future<LedgerState> state() => fam.state(now);

  /// The new person says yes on their own phone (the meet is not built; this is that one vote).
  Future<void> candidateAccepts(LedgerEntry e, {P? who}) => fam.vote(who ?? cand, e, 'yes', at: now);
}

extension WelcomeOverviewJo on WelcomeOverview {
  /// The request about Jo that this parent sent (the family's first welcome, of the second parent, is in `sent` too).
  WelcomeRequest get jo => sent.singleWhere((WelcomeRequest r) => r.personName == 'Jo');
}

MemberProfile trusted() => MemberProfile.defaults(Preset.trustedCarer);
MemberProfile lookOnly() => MemberProfile.defaults(Preset.viewOnly);
MemberProfile visit(int now, {int days = 3}) =>
    MemberProfile.defaults(Preset.visit, fromMs: now, untilMs: now + days * day);
