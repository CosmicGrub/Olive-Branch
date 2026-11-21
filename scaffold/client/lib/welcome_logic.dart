// OLIVE BRANCH — welcoming a new grown-up into the village: the words, the approval rule, the request lists, the
// asking and answering, and the limits on asking. UNVERIFIED on a device; pure Dart, runs headless in CI.
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3 (the steps), 4 (profiles), 5 (who must agree), 7.3 and
// 7.9 (deadlock and abuse) and 10 (the ledger entries). The reduce rule that makes a welcome real lives in
// family_ledger_state.dart; this file only builds the entries that rule reads and describes what it says.
//
// WHAT THIS IS. The adult-side service behind the "Welcome someone" screens (welcome_screens.dart): it signs a
// `member.add` proposal, signs a yes or a no, lists the requests waiting for this grown-up and the ones this
// grown-up sent, remembers "ask me later", and says all of it in adult words. Silence is never yes.
//
// WHAT THIS IS NOT. It does not do the in-person meet (village_meet.dart does; the candidate's device record is an
// input here), the new person's own yes is signed on their phone (village_link.dart) and read back here, and the
// 72 hour single-parent hold is not built. Pause, end, the limits agreement and the Standing OK live in
// village_people.dart; this file only refuses to start a welcome for a parent who is paused or has agreed not to. The
// guardian app reaches this through village_welcome_flow.dart. The limits on asking (one
// pending request, three in 30 days, the 7 day wait after a no) are checked on THIS phone before signing; another
// phone running modified code could still sign more, and the reduce rule does not count them. The child sees none
// of this: nothing in a child file imports this one (a test guards it).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'device_keys.dart' show DeviceKey;
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_profiles.dart';
import 'family_state.dart';
import 'local_store.dart';

// ---------------------------------------------------------------------------------------------------------------
// Limits on asking (section 5.2 rules 4 and 5, and 3.3 "Ask me later")
// ---------------------------------------------------------------------------------------------------------------

/// One request open per grown-up at a time, and at most three in any 30 days.
const int kMaxOpenRequestsPerProposer = 1;
const int kMaxRequestsPer30Days = 3;
const int kRequestWindowMs = 30 * kMsPerDay;

/// After a no, the same person cannot be asked again at the same or a wider level for this long.
const int kCooldownAfterNoMs = 7 * kMsPerDay;

/// "Ask me later": up to three snoozes of 24 hours, and at most two quiet reminders in all.
const int kMaxSnoozes = 3;
const int kSnoozeMs = 24 * 60 * 60 * 1000;
const int kMaxReminders = 2;

// ---------------------------------------------------------------------------------------------------------------
// Plain words
// ---------------------------------------------------------------------------------------------------------------

/// Words the history and every screen here must never use about a person (design 3.6 and 12).
const List<String> kBannedWelcomeWords = <String>[
  'blocked', 'refused', 'denied', 'controlling', 'suspended', 'tried to', 'opened it', 'read receipt', 'seen it',
  'ledger', 'epoch', 'tier', 'preset', 'electorate', 'quorum',
];

String presetTitle(Preset p) {
  switch (p) {
    case Preset.parent:
      return 'Another parent';
    case Preset.parentWithLimits:
      return 'Another parent, with limits';
    case Preset.trustedCarer:
      return 'A trusted carer';
    case Preset.visit:
      return 'A visit';
    case Preset.viewOnly:
      return 'Look only';
    case Preset.helperPage:
      return 'A helper page';
  }
}

String presetBlurb(Preset p, String child) {
  switch (p) {
    case Preset.parent:
      return 'Has the same say as you, including who else is welcomed.';
    case Preset.parentWithLimits:
      return 'Joins as a parent, with a short list of things switched off. They have to agree to that list themselves.';
    case Preset.trustedCarer:
      return 'A grandparent, aunt or uncle, or a regular sitter who helps with $child. Starts small and settles in.';
    case Preset.visit:
      return 'Someone who helps for a few days at most, then it ends by itself.';
    case Preset.helperPage:
      return 'Someone who only needs a page you hold up on your screen. No app and no vote.';
    case Preset.viewOnly:
      return 'Can look at what you choose to show, and nothing else.';
  }
}

String capabilityWords(Capability c, String child) {
  switch (c) {
    case Capability.history:
      return 'See the family history and who is in the village';
    case Capability.calendar:
      return 'See $child’s calendar and weeks';
    case Capability.emergencyCard:
      return 'See the emergency card and medicines list';
    case Capability.careNotes:
      return 'Write care notes and log a dose';
    case Capability.expenses:
      return 'See and add expenses';
    case Capability.settings:
      return 'Change family settings and parental controls';
    case Capability.ownPin:
      return 'Change their own PIN';
    case Capability.connectDevice:
      return 'Connect a child’s device';
    case Capability.unlockPlay:
      return 'Unlock $child’s tablet with their phone and play together';
    case Capability.messageChild:
      return 'Message or call $child';
    case Capability.startWelcome:
      return 'Welcome other people';
    case Capability.voteWelcome:
      return 'Say yes or no when someone new is welcomed';
    case Capability.pauseCarer:
      return 'Pause a carer';
  }
}

String reachLine(Reach r) {
  switch (r) {
    case Reach.look:
      return 'Can look only';
    case Reach.act:
      return 'Can help';
    case Reach.parent:
      return 'Same say as you';
  }
}

String daysWords(int ms) {
  final int d = (ms / kMsPerDay).round();
  return d == 1 ? '1 day' : '$d days';
}

/// "Ongoing", "for 3 days" or "until" and a date for a profile's time box (only the span is said, never a count of uses).
String timeBoxWords(MemberProfile p) {
  final int? f = p.fromMs, u = p.untilMs;
  if (u == null) return 'Ongoing';
  if (f != null) return 'For ${daysWords(u - f)}';
  return 'Until ${dateWords(u)}';
}

const List<String> _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
  'December',
];

String dateWords(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.day} ${_months[d.month - 1]}';
}

/// A short plain description of what a profile allows, for a list line: "Can look only, for 3 days".
String profileLine(MemberProfile p) => '${reachLine(p.reach)}, ${timeBoxWords(p).toLowerCase()}';

/// One entry per switch that is ON, then the ones that are OFF, in adult words, for the request screen's checklist.
class ChecklistLine {
  const ChecklistLine(this.words, this.on, this.fixed);
  final String words;
  final bool on, fixed;
}

List<ChecklistLine> checklistFor(MemberProfile p, String child) {
  final Map<Capability, Cell> row = kProfileTable[p.preset]!;
  return <ChecklistLine>[
    for (final Capability c in Capability.values)
      if (row[c]!.available) ChecklistLine(capabilityWords(c, child), p.has(c), row[c]!.fixed),
  ];
}

// ---------------------------------------------------------------------------------------------------------------
// The approval rule, in one place (section 5.2)
// ---------------------------------------------------------------------------------------------------------------

/// Who must say yes for a person at a given profile, how long the request stays open, and how long the new person
/// settles in. It reads the same inputs as the reduce rule and agrees with it (a test runs both on every preset).
class ApprovalNeed {
  const ApprovalNeed({
    required this.rule,
    required this.hardFloor,
    required this.lifetimeMs,
    required this.settleHours,
    required this.parentCount,
  });

  /// 'all' (every parent) or 'one' (the parent who asks).
  final String rule;

  /// True for a new parent: nobody can loosen it, not even the family's own settings.
  final bool hardFloor;
  final int lifetimeMs, settleHours, parentCount;

  bool get everyParent => rule == 'all';

  /// Sentences for the "Who has to agree" box, adult words.
  List<String> sentences({required bool newParent}) {
    final List<String> out = <String>[];
    if (newParent) {
      out.add(parentCount <= 1
          ? 'You are the only parent, so your yes is the whole vote. They will have the same say as you.'
          : 'Every parent has to say yes. This is always so, and no setting can change it.');
    } else if (everyParent) {
      out.add(parentCount <= 1
          ? 'You are the only parent, so your yes is the whole vote.'
          : 'Every parent has to say yes. You can change this in the family’s “Who must agree” setting.');
    } else {
      out.add('Your yes is enough. The other parents will see this on their Your village page.');
    }
    out.add('No answer is never a yes. If nobody answers, the request ends in ${daysWords(lifetimeMs)}.');
    out.add('They also say yes on their own phone before they are in.');
    if (settleHours > 0) out.add('They settle in for $settleHours hours first. They cannot welcome anyone or change settings in that time.');
    return out;
  }
}

ApprovalNeed approvalNeed({required MemberProfile profile, required FamilyPolicy policy, required int parentCount}) {
  final bool parent = tierOf(profile.preset) == MemberTier.parent;
  final String rule = parent ? 'all' : (profile.reach == Reach.look ? policy.carerLook : policy.carerAct);
  return ApprovalNeed(
    rule: rule,
    hardFloor: parent,
    lifetimeMs: proposalLifetimeMs(profile.preset),
    settleHours: parent ? policy.settleHours : defaultSettleHours(profile.preset),
    parentCount: parentCount,
  );
}

/// The parents who are asked at [atMs]: guardians with at least one device that has finished settling in. The same
/// definition the reduce rule uses, so the electorate signed into a request is the one it expects.
List<String> electorateAt(LedgerState s, int atMs) {
  final List<String> out = <String>[
    for (final LedgerMember m in s.members)
      if (m.isGuardian &&
          s.devices.any((LedgerDevice d) => d.kind == 'guardian' && d.gidHex == m.gidHex && !d.settlingAt(atMs)))
        m.gidHex,
  ]..sort();
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Smaller and wider
// ---------------------------------------------------------------------------------------------------------------

/// The switches on a parent that bundle seeing with doing ("See and add expenses", "Write care notes and log a dose").
/// A limit on a parent may only take away what they can do, never what they can see (section 2.6: neither parent can
/// hide family activity from the other), so a parent keeps these on at every level until the design is reconciled.
const Set<Capability> kSeeingCaps = <Capability>{Capability.careNotes, Capability.expenses};

/// True when a parent-level profile has switched off something that also lets that parent see.
bool hidesFromParent(MemberProfile p) =>
    tierOf(p.preset) == MemberTier.parent && kSeeingCaps.any((Capability c) => kProfileTable[p.preset]![c]!.available && !p.has(c));

int _presetRank(Preset p) {
  switch (p) {
    case Preset.helperPage:
    case Preset.viewOnly:
      return 0;
    case Preset.visit:
      return 1;
    case Preset.trustedCarer:
      return 2;
    case Preset.parentWithLimits:
      return 3;
    case Preset.parent:
      return 4;
  }
}

int? _span(MemberProfile p) {
  final int? f = p.fromMs, u = p.untilMs;
  return (f != null && u != null) ? u - f : null;
}

/// True when [a] gives something [b] does not: a higher level, a switch, a child, a longer time, or an end date that
/// is later. Used for the 7 day wait. The time is compared by its length and its end, never by the raw start, so a
/// visit asked again a minute later or moved later is still not smaller.
bool wider(MemberProfile a, MemberProfile b) {
  if (_presetRank(a.preset) > _presetRank(b.preset)) return true;
  for (final Capability c in a.caps) {
    if (!b.has(c)) return true;
  }
  final List<String>? ak = a.children, bk = b.children;
  if (ak == null && bk != null) return true;
  if (ak != null && bk != null && ak.any((String k) => !bk.contains(k))) return true;
  final int? ua = a.untilMs, ub = b.untilMs;
  if (ua == null && ub != null) return true;
  if (ua != null && ub != null) {
    if (ua > ub) return true;
    final int? sa = _span(a), sb = _span(b);
    if (sa != null && sb != null && sa > sb) return true;
  }
  return false;
}

/// True when [a] gives strictly less than [b] on at least one count: a lower level, fewer switches, fewer children,
/// a shorter time or an earlier end where [b] had none.
bool _givesLess(MemberProfile a, MemberProfile b) {
  if (_presetRank(a.preset) < _presetRank(b.preset)) return true;
  for (final Capability c in b.caps) {
    if (!a.has(c)) return true;
  }
  final List<String>? ak = a.children, bk = b.children;
  if (ak != null && bk == null) return true;
  if (ak != null && bk != null && bk.any((String k) => !ak.contains(k))) return true;
  final int? ua = a.untilMs, ub = b.untilMs;
  if (ua != null && ub == null) return true;
  if (ua != null && ub != null) {
    if (ua < ub) return true;
    final int? sa = _span(a), sb = _span(b);
    if (sa != null && sb != null && sa < sb) return true;
  }
  return false;
}

bool sameProfile(MemberProfile a, MemberProfile b) => jsonEncode(a.toValue()) == jsonEncode(b.toValue());

/// A profile that is not wider than [big] on any count and gives less on at least one: the only kind of "yes to
/// something smaller" that is allowed. A copy with only the dates moved is not smaller.
bool smallerThan(MemberProfile small, MemberProfile big) => !wider(small, big) && _givesLess(small, big);

/// Smaller choices to offer for "Yes to something smaller": each gives less than [big] on every count, and fits the
/// profile table. Never empty for a profile that can be made smaller.
List<MapEntry<String, MemberProfile>> smallerChoices(MemberProfile big, int nowMs) {
  final List<MapEntry<String, MemberProfile>> out = <MapEntry<String, MemberProfile>>[];
  void add(String label, MemberProfile p) {
    if (p.violation() == null && smallerThan(p, big) && !out.any((MapEntry<String, MemberProfile> e) => sameProfile(e.value, p))) {
      out.add(MapEntry<String, MemberProfile>(label, p));
    }
  }

  switch (big.preset) {
    case Preset.parent:
      add('As a parent with some limits', MemberProfile.defaults(Preset.parentWithLimits));
      add('As a trusted carer instead', MemberProfile.defaults(Preset.trustedCarer, children: big.children));
      break;
    case Preset.parentWithLimits:
      add('As a trusted carer instead', MemberProfile.defaults(Preset.trustedCarer, children: big.children));
      break;
    case Preset.trustedCarer:
      add('Look only', MemberProfile.defaults(Preset.viewOnly, children: big.children));
      add('A visit of 3 days', MemberProfile.defaults(Preset.visit, children: big.children, fromMs: nowMs, untilMs: nowMs + 3 * kMsPerDay));
      break;
    case Preset.visit:
      add('Look only', MemberProfile.defaults(Preset.viewOnly, children: big.children, fromMs: big.fromMs, untilMs: big.untilMs));
      final int? f = big.fromMs, u = big.untilMs;
      if (f != null && u != null && u - f > kMsPerDay) {
        add('A shorter visit', MemberProfile(preset: Preset.visit, caps: big.caps, children: big.children, fromMs: f, untilMs: f + ((u - f) ~/ 2)));
      }
      break;
    case Preset.viewOnly:
    case Preset.helperPage:
      break;
  }
  // The same preset with the optional switches off (what is left is what cannot be turned off).
  if (big.reach != Reach.look) {
    final Map<Capability, Cell> row = kProfileTable[big.preset]!;
    final bool parentTier = tierOf(big.preset) == MemberTier.parent;
    final List<Capability> kept = <Capability>[
      for (final Capability c in big.caps)
        if (row[c]!.fixed || (parentTier && kSeeingCaps.contains(c))) c,
    ];
    add('The same, with the extras switched off',
        MemberProfile(preset: big.preset, caps: kept, children: big.children, fromMs: big.fromMs, untilMs: big.untilMs));
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// The things you can be told "no" to, in words
// ---------------------------------------------------------------------------------------------------------------

/// Why a request could not be made or answered. [code] is for tests; [words] is what a grown-up reads.
class WelcomeRefused implements Exception {
  const WelcomeRefused(this.code, this.words);
  final String code, words;
  @override
  String toString() => 'WelcomeRefused($code)';
}

enum WelcomeAnswer { yes, no, later, smaller }

// ---------------------------------------------------------------------------------------------------------------
// The request, as read from the ledger
// ---------------------------------------------------------------------------------------------------------------

/// One parent's place in a request, in plain words.
class ElectorStatus {
  const ElectorStatus({required this.gidHex, required this.name, required this.answer, required this.isAsker});
  final String gidHex, name;

  /// 'yes', 'no' or 'waiting'. There is no "seen" or "opened": the asker never learns whether a request was looked at.
  final String answer;
  final bool isAsker;

  String get words {
    if (isAsker) return answer == 'no' ? '$name stepped back' : '$name asked';
    switch (answer) {
      case 'yes':
        return '$name said yes';
      case 'no':
        return '$name said not this time';
      default:
        return '$name has not answered yet';
    }
  }
}

/// 'waiting' (open), 'lapsed' (nobody answered in time), 'declined' (a no, or the asker stepped back) or 'welcomed'.
class WelcomeRequest {
  WelcomeRequest({
    required this.hashHex,
    required this.askerGidHex,
    required this.askerName,
    required this.personName,
    required this.personGidHex,
    required this.profile,
    required this.issuedAtMs,
    required this.expMs,
    required this.rule,
    required this.electors,
    required this.status,
    required this.candidateYes,
    required this.mine,
    required this.needsMyAnswer,
    required this.myAnswer,
    required this.settling,
  });
  final String hashHex, askerGidHex, askerName, personName, personGidHex;
  final MemberProfile profile;
  final int issuedAtMs, expMs;
  final String rule, status;
  final List<ElectorStatus> electors;

  /// The new person has said yes on their own phone (their signed vote for THIS request is in the record).
  final bool candidateYes;

  /// This grown-up is the one who asked.
  final bool mine;
  final bool needsMyAnswer;

  /// 'yes' | 'no' | null: what this phone has already answered.
  final String? myAnswer;

  /// This phone is still settling in, so it cannot answer yet.
  final bool settling;

  bool get open => status == 'waiting';
  bool get isParentWelcome => tierOf(profile.preset) == MemberTier.parent;

  /// Who asked and what for, in one sentence ("Sam asked to welcome Jo as a carer for Ivy").
  String sentence(String child) {
    final String role = isParentWelcome ? 'a parent' : (profile.preset == Preset.visit ? 'a visitor' : 'a carer');
    return '$askerName asked to welcome $personName as $role for $child (${profileLine(profile).toLowerCase()}).';
  }
}

class WelcomeOverview {
  const WelcomeOverview({required this.forMe, required this.sent, required this.others, required this.history});

  /// Open requests waiting for this grown-up's answer.
  final List<WelcomeRequest> forMe;

  /// Requests this grown-up asked, any status (newest first).
  final List<WelcomeRequest> sent;

  /// Open requests from other grown-ups that this grown-up has already answered.
  final List<WelcomeRequest> others;

  /// Plain-words history lines, oldest first.
  final List<String> history;
}

// ---------------------------------------------------------------------------------------------------------------
// "Ask me later"
// ---------------------------------------------------------------------------------------------------------------

class AskLater {
  const AskLater({this.snoozes = 0, this.untilMs = 0, this.reminders = 0});
  final int snoozes, untilMs, reminders;

  Map<String, Object?> toJson() => <String, Object?>{'s': snoozes, 'u': untilMs, 'r': reminders};
  static AskLater? fromJson(Object? v) {
    if (v is! Map) return null;
    final Object? s = v['s'], u = v['u'], r = v['r'];
    if (s is! int || u is! int || r is! int || s < 0 || s > kMaxSnoozes || r < 0 || r > kMaxReminders || u < 0) {
      return null;
    }
    return AskLater(snoozes: s, untilMs: u, reminders: r);
  }
}

/// Where "ask me later" is remembered. It is local to this phone, never sent, and never changes the ledger: asking
/// to be asked later signs nothing and the asker cannot see it.
abstract class WelcomeRemindersRepository {
  Future<Map<String, AskLater>> load();
  Future<void> save(Map<String, AskLater> all);
}

class MemoryWelcomeReminders implements WelcomeRemindersRepository {
  Map<String, AskLater> _m = <String, AskLater>{};
  bool failSaves = false;
  Map<String, AskLater> get snapshot => Map<String, AskLater>.of(_m);
  @override
  Future<Map<String, AskLater>> load() async => Map<String, AskLater>.of(_m);
  @override
  Future<void> save(Map<String, AskLater> all) async {
    if (failSaves) throw StateError('disk full');
    _m = Map<String, AskLater>.of(all);
  }
}

/// Kept under key 'welcomeasks' inside the existing sealed 'familyledger' area (guardian scope): the same
/// lifetime and the same wipe as the family record, so no new area is needed.
class LocalStoreWelcomeReminders implements WelcomeRemindersRepository {
  LocalStoreWelcomeReminders(this._ns);
  final LocalNamespace _ns;
  static const String key = 'welcomeasks';

  @override
  Future<Map<String, AskLater>> load() async {
    try {
      final Object? raw = await _ns.get(key);
      if (raw is! Map) return <String, AskLater>{};
      final Map<String, AskLater> out = <String, AskLater>{};
      for (final MapEntry<dynamic, dynamic> e in raw.entries) {
        final AskLater? a = AskLater.fromJson(e.value);
        if (e.key is String && (e.key as String).length == 64 && a != null) out[e.key as String] = a;
      }
      return out;
    } catch (_) {
      return <String, AskLater>{};
    }
  }

  @override
  Future<void> save(Map<String, AskLater> all) =>
      _ns.put(key, <String, Object?>{for (final MapEntry<String, AskLater> e in all.entries) e.key: e.value.toJson()});
}

// ---------------------------------------------------------------------------------------------------------------
// What the person typed
// ---------------------------------------------------------------------------------------------------------------

/// What a grown-up chose on the Welcome screens. [candidate] is the new person's device record from the in-person
/// meet (W2, not built): until then it is an input.
class WelcomeDraft {
  WelcomeDraft({required this.personName, required this.profile, required this.candidate});
  final String personName;
  final MemberProfile profile;
  final DeviceRecord candidate;
}

String cleanName(String s, {int max = 40}) {
  final StringBuffer b = StringBuffer();
  for (final int c in s.runes) {
    if (c >= 32 && c != 127) b.writeCharCode(c);
  }
  final String t = b.toString().trim();
  return t.length <= max ? t : t.substring(0, max);
}

// ---------------------------------------------------------------------------------------------------------------
// The service
// ---------------------------------------------------------------------------------------------------------------

class WelcomeService {
  WelcomeService({
    required this.context,
    required this.repository,
    required this.reminders,
    required this.nowMs,
    required this.childName,
    Random? random,
  }) : _random = random ?? Random.secure();

  final FamilyContext context;
  final FamilyRepository repository;
  final WelcomeRemindersRepository reminders;
  final int Function() nowMs;
  final String childName;
  final Random _random;

  DeviceKey get _me => context.device;

  Uint8List _bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  Future<void> _persist() => repository.save(context.snapshot());

  /// Runs [body] so that it either happens in full or not at all. The lists are copied first; if anything throws
  /// (a full disk, a failed save), both lists are put back as they were, so a half-finished change never sits in
  /// memory waiting to be written by the next save. A failure that is not already in plain words becomes one.
  Future<T> _all<T>(Future<T> Function() body) async {
    final List<LedgerEntry> entries = List<LedgerEntry>.of(context.entries);
    final List<LedgerVote> votes = List<LedgerVote>.of(context.votes);
    try {
      return await body();
    } catch (e) {
      context.entries
        ..clear()
        ..addAll(entries);
      context.votes
        ..clear()
        ..addAll(votes);
      if (e is WelcomeRefused) rethrow;
      throw const WelcomeRefused('not-saved', 'That could not be saved on this phone, so nothing was changed. Please try again.');
    }
  }

  /// The parents' names by gid, from the reduced state.
  Map<String, String> _names(LedgerState s) => <String, String>{for (final LedgerMember m in s.members) m.gidHex: m.name};

  // ---- reading ------------------------------------------------------------------------------------------------

  Future<WelcomeOverview> overview() async {
    final int now = nowMs();
    final LedgerState s = await context.state(nowMs: now);
    if (!s.ok) {
      return const WelcomeOverview(
          forMe: <WelcomeRequest>[], sent: <WelcomeRequest>[], others: <WelcomeRequest>[], history: <String>[]);
    }
    final Map<String, String> names = _names(s);
    final String? myGid = s.deviceFor(_me.publicKey)?.gidHex;
    final Map<String, List<LedgerVote>> votesBy = <String, List<LedgerVote>>{};
    for (final LedgerVote v in context.votes) {
      if (await v.verifySignature()) (votesBy[v.targetHex] ??= <LedgerVote>[]).add(v);
    }
    final List<WelcomeRequest> all = <WelcomeRequest>[];
    for (final LedgerEntry e in context.entries) {
      if (e.type != EntryType.memberAdd) continue;
      if (s.rejected.containsKey(e.hashHex)) continue;
      final WelcomeRequest? r = _read(e, s, names, myGid, votesBy[e.hashHex] ?? const <LedgerVote>[], now);
      if (r != null) all.add(r);
    }
    all.sort((WelcomeRequest a, WelcomeRequest b) => b.issuedAtMs - a.issuedAtMs);
    final List<WelcomeRequest> forMe = <WelcomeRequest>[
      for (final WelcomeRequest r in all)
        if (r.needsMyAnswer) r,
    ];
    return WelcomeOverview(
      forMe: forMe,
      sent: <WelcomeRequest>[for (final WelcomeRequest r in all) if (r.mine) r],
      others: <WelcomeRequest>[
        for (final WelcomeRequest r in all)
          if (r.open && !r.mine && !r.needsMyAnswer) r,
      ],
      history: _history(all),
    );
  }

  WelcomeRequest? _read(
      LedgerEntry e, LedgerState s, Map<String, String> names, String? myGid, List<LedgerVote> votes, int now) {
    final Map<String, Object?> b = e.body;
    final MemberProfile? profile = MemberProfile.fromValue(b['profile']);
    final Object? pr = b['proposal'];
    if (profile == null || pr is! Map<String, Object?>) return null;
    final String personGid = hexOf(b['gid']! as Uint8List);
    final LedgerDevice? signer = s.deviceFor(e.signer);
    final String askerGid = signer?.gidHex ?? '';
    final int exp = pr['exp']! as int;
    final List<String> electorate = <String>[for (final Object? x in pr['electorate']! as List) hexOf(x! as Uint8List)];
    PendingItem? pend;
    for (final PendingItem p in s.pending) {
      if (p.hashHex == e.hashHex) pend = p;
    }
    String status;
    if (s.members.any((LedgerMember m) => m.gidHex == personGid)) {
      status = 'welcomed';
    } else if (pend == null) {
      return null; // voided or not in effect for another reason: not shown as a request
    } else {
      status = pend.status == 'pending' ? 'waiting' : pend.status;
    }
    final Map<String, String> answers = <String, String>{};
    bool askerStepped = false;
    for (final LedgerVote v in votes) {
      if (v.atMs >= exp || v.atMs < e.issuedAtMs - kClockSkewMs) continue;
      final LedgerDevice? d = s.deviceFor(v.voter);
      final String? g = d?.gidHex;
      if (g == null || !electorate.contains(g)) continue;
      if (g == askerGid) {
        if (v.answer == 'withdraw' || v.answer == 'no') askerStepped = true;
        continue;
      }
      if (v.answer == 'withdraw') continue;
      final String prev = answers[g] ?? '';
      if (v.answer == 'no') {
        answers[g] = 'no';
      } else if (prev != 'no') {
        answers[g] = 'yes';
      }
    }
    final List<ElectorStatus> electors = <ElectorStatus>[
      for (final String g in electorate)
        ElectorStatus(
          gidHex: g,
          name: names[g] ?? 'A parent',
          answer: g == askerGid ? (askerStepped ? 'no' : 'yes') : (answers[g] ?? 'waiting'),
          isAsker: g == askerGid,
        ),
    ];
    bool candidateYes = false;
    final DeviceRecord? cand = DeviceRecord.fromValue(b['dev']);
    if (cand != null) {
      for (final LedgerVote v in votes) {
        if (v.answer == 'yes' && bytesEqual(v.voter, cand.key) && v.atMs < exp && v.atMs >= e.issuedAtMs - kClockSkewMs) candidateYes = true;
      }
    }
    final String? mine = myGid == null ? null : answers[myGid];
    final bool isElector = myGid != null && electorate.contains(myGid) && myGid != askerGid;
    final bool settling = isElector && s.isSettling(_me.publicKey, now);
    return WelcomeRequest(
      hashHex: e.hashHex,
      askerGidHex: askerGid,
      askerName: names[askerGid] ?? 'A parent',
      personName: b['name']! as String,
      personGidHex: personGid,
      profile: profile,
      issuedAtMs: e.issuedAtMs,
      expMs: exp,
      rule: pr['rule']! as String,
      electors: electors,
      status: status,
      candidateYes: candidateYes,
      mine: myGid != null && myGid == askerGid,
      needsMyAnswer: status == 'waiting' && isElector && mine == null && !settling,
      myAnswer: mine,
      settling: settling,
    );
  }

  List<String> _history(List<WelcomeRequest> all) {
    final List<String> out = <String>[];
    for (final WelcomeRequest r in all.reversed) {
      out.add(r.sentence(childName));
      for (final ElectorStatus x in r.electors) {
        if (x.isAsker) continue;
        if (x.answer == 'yes') out.add('${x.name} said yes.');
        if (x.answer == 'no') out.add('${x.name} said not this time.');
      }
      switch (r.status) {
        case 'welcomed':
          out.add('${r.personName} was welcomed by ${r.electors.map((ElectorStatus x) => x.name).join(' and ')}.');
          break;
        case 'lapsed':
          out.add('The request to welcome ${r.personName} ended without an answer.');
          break;
        case 'declined':
          out.add('${r.personName} was not set up this time.');
          break;
      }
    }
    return out;
  }

  // ---- asking -------------------------------------------------------------------------------------------------

  /// Checks everything this phone can check before a request is signed. Throws [WelcomeRefused] in plain words.
  Future<void> checkMayAsk(WelcomeDraft d) async {
    await _checkCandidate(d.candidate);
    final int now = nowMs();
    final LedgerState s = await context.state(nowMs: now);
    _checkMayAsk(s, d.profile, d.candidate.key, now);
  }

  /// The new phone must come with its agreement key signed by its own device key. A record that does not verify
  /// would be refused by every other phone, so it is not signed here.
  Future<void> _checkCandidate(DeviceRecord c) async {
    if (c.agree == null || !await verifyAgreementCert(c)) {
      throw const WelcomeRefused('bad-device', 'That phone did not introduce itself properly. Please try meeting again.');
    }
  }

  void _checkMayAsk(LedgerState s, MemberProfile profile, Uint8List candidateKey, int now) {
    if (!s.ok) throw const WelcomeRefused('no-family', 'There is no family set up on this phone yet.');
    final LedgerDevice? me = s.deviceFor(_me.publicKey);
    if (me == null || me.kind != 'guardian') {
      throw const WelcomeRefused('not-a-parent', 'Only a parent’s phone can welcome someone.');
    }
    if (me.settlingAt(now)) {
      throw const WelcomeRefused('settling', 'This phone is still settling in. You can welcome someone once that ends.');
    }
    if (s.isPaused(me.gidHex ?? '')) {
      throw const WelcomeRefused('paused', 'Your access is paused, so you cannot welcome anyone for now. Another parent can resume it.');
    }
    if (s.limitsOf(me.gidHex ?? '').contains(Capability.startWelcome.number)) {
      throw const WelcomeRefused('not-allowed', 'You agreed that welcoming people is switched off for you. You can ask the other parents to change that.');
    }
    final LedgerMember? mm = s.members.where((LedgerMember m) => m.gidHex == me.gidHex).firstOrNull;
    if (mm != null && mm.profile != null && !mm.profile!.has(Capability.startWelcome)) {
      throw const WelcomeRefused('not-allowed', 'Welcoming people is switched off for you. Ask the other parent if you want it on.');
    }
    if (profile.preset == Preset.helperPage) {
      throw const WelcomeRefused('helper-page', 'A helper page needs no welcome. Use the helper pages to write one.');
    }
    if (hidesFromParent(profile)) {
      throw const WelcomeRefused('hides-from-parent',
          'A parent can always see everything about the child, so those two switches stay on. You can limit what a parent does, not what they see.');
    }
    final String? why = profile.violation();
    if (why != null) throw WelcomeRefused('profile', 'Those choices do not fit together: ${_violationWords(why)}.');
    final String kind = tierOf(profile.preset) == MemberTier.parent ? 'guardian' : 'carer';
    if (kind == 'guardian' && s.guardians.length >= kMaxGuardians) {
      throw const WelcomeRefused('family-full', 'The village is full for parents.');
    }
    if (kind == 'carer' && s.members.where((LedgerMember m) => m.kind == 'carer').length >= kMaxCarers) {
      throw const WelcomeRefused('family-full', 'The village is full for carers.');
    }
    final String keyHex = hexOf(candidateKey);
    if (s.devices.any((LedgerDevice d) => d.keyHex == keyHex)) {
      throw const WelcomeRefused('already-in', 'That phone is already part of the village.');
    }
    // Limits on asking, from this grown-up's own record of requests.
    final String myGid = me.gidHex!;
    final List<LedgerEntry> mine = <LedgerEntry>[
      for (final LedgerEntry e in context.entries)
        if (e.type == EntryType.memberAdd && s.deviceFor(e.signer)?.gidHex == myGid) e,
    ];
    int open = 0, recent = 0;
    for (final LedgerEntry e in mine) {
      final int exp = (e.body['proposal']! as Map<String, Object?>)['exp']! as int;
      if (now - e.issuedAtMs < kRequestWindowMs) recent++;
      final String? st = s.pending.where((PendingItem p) => p.hashHex == e.hashHex).firstOrNull?.status;
      if (st == 'pending' && now < exp) open++;
    }
    if (open >= kMaxOpenRequestsPerProposer) {
      throw const WelcomeRefused('one-at-a-time',
          'You already have a request waiting. Wait for answers, or cancel it, before asking about someone else.');
    }
    if (recent >= kMaxRequestsPer30Days) {
      throw const WelcomeRefused('too-many', 'That is three requests in 30 days. Please wait a little before the next.');
    }
    // The 7 day wait after a no, for the same phone at the same or a wider level.
    for (final LedgerEntry e in mine) {
      if (!bytesEqual((DeviceRecord.fromValue(e.body['dev'])!).key, candidateKey)) continue;
      final MemberProfile? old = MemberProfile.fromValue(e.body['profile']);
      if (old == null) continue;
      final int? noAt = _noAt(e);
      if (noAt != null && now - noAt < kCooldownAfterNoMs && !smallerThan(profile, old)) {
        throw const WelcomeRefused('wait-a-week',
            'That did not go ahead this time. Please wait a week, or ask for something smaller.');
      }
    }
  }

  /// When a required parent first said no to [e], or null.
  int? _noAt(LedgerEntry e) {
    int? at;
    for (final LedgerVote v in context.votes) {
      if (v.targetHex != e.hashHex || v.answer != 'no') continue;
      if (at == null || v.atMs < at) at = v.atMs;
    }
    return at;
  }

  String _violationWords(String code) {
    if (code.startsWith('fixed-capability-')) return 'one of the switches cannot be changed for this kind of person';
    switch (code) {
      case 'visit-needs-time-box':
        return 'a visit needs an end date';
      case 'visit-too-long':
        return 'a visit can be at most $kVisitMaxDays days';
      case 'children-empty':
        return 'choose at least one child, or all of them';
      case 'time-box-backwards':
        return 'the end comes before the start';
      default:
        return 'please check the list';
    }
  }

  /// Signs and keeps a request. Needs the grown-up's PIN to have been asked for by the caller (the screen does).
  Future<LedgerEntry> propose(WelcomeDraft d) async {
    await _checkCandidate(d.candidate);
    final int now = nowMs();
    final LedgerState s = await context.state(nowMs: now);
    _checkMayAsk(s, d.profile, d.candidate.key, now);
    final String name = cleanName(d.personName);
    if (name.isEmpty) throw const WelcomeRefused('no-name', 'Please type the person’s name.');
    return _all(() => _sign(s, d.profile, d.candidate, name, _bytes(16), forceAll: false, now: now));
  }

  Future<LedgerEntry> _sign(LedgerState s, MemberProfile profile, DeviceRecord cand, String name, Uint8List gid,
      {required bool forceAll, required int now}) async {
    final LedgerDevice me = s.deviceFor(_me.publicKey)!;
    final ApprovalNeed need = approvalNeed(profile: profile, policy: s.policy, parentCount: s.guardians.length);
    final String rule = forceAll ? 'all' : need.rule;
    final List<String> electors = rule == 'all' ? electorateAt(s, now) : <String>[me.gidHex!];
    final LedgerEntry e = await LedgerEntry.sign(
      _me,
      type: EntryType.memberAdd,
      prev: s.heads,
      issuedAtMs: now,
      body: <String, Object?>{
        'gid': gid,
        'name': name,
        'kind': tierOf(profile.preset) == MemberTier.parent ? 'guardian' : 'carer',
        'profile': profile.toValue(),
        'dev': cand.toValue(),
        'proposal': <String, Object?>{
          'id': _bytes(16),
          'exp': now + need.lifetimeMs,
          'electorate': <Uint8List>[for (final String g in electors) fromHex(g)],
          'rule': rule,
        },
      },
    );
    context.entries.add(e);
    await _persist();
    return e;
  }

  /// The asker takes a request back. Allowed until the new person is in.
  Future<void> cancel(WelcomeRequest r) async {
    if (!r.mine || !r.open) {
      throw const WelcomeRefused('not-yours', 'Only the person who asked can cancel, and only while it is waiting.');
    }
    final LedgerVote v = await LedgerVote.sign(_me, target: fromHex(r.hashHex), answer: 'withdraw', atMs: nowMs());
    await _all(() async {
      context.votes.add(v);
      await _persist();
    });
  }

  // ---- answering ----------------------------------------------------------------------------------------------

  Future<WelcomeRequest> _find(String hashHex) async {
    final WelcomeOverview o = await overview();
    for (final WelcomeRequest r in <WelcomeRequest>[...o.forMe, ...o.others, ...o.sent]) {
      if (r.hashHex == hashHex) return r;
    }
    throw const WelcomeRefused('gone', 'That request is not here any more.');
  }

  /// Yes or not this time. A signed answer over this exact request. "Ask me later" is [askLater].
  Future<void> answer(String hashHex, WelcomeAnswer a) async {
    if (a != WelcomeAnswer.yes && a != WelcomeAnswer.no) {
      throw ArgumentError('answer is yes or no; later and smaller have their own methods');
    }
    final WelcomeRequest r = await _find(hashHex);
    if (!r.open) throw const WelcomeRefused('closed', 'That request has ended.');
    if (r.mine) throw const WelcomeRefused('own-request', 'You asked, so your yes is already in.');
    if (r.settling) {
      throw const WelcomeRefused('settling', 'This phone is still settling in. You can answer once that ends.');
    }
    if (!r.needsMyAnswer) {
      throw WelcomeRefused(r.myAnswer != null ? 'answered' : 'not-asked',
          r.myAnswer != null ? 'You have already answered this one.' : 'You are not one of the parents asked about this.');
    }
    final LedgerVote v = await LedgerVote.sign(_me,
        target: fromHex(hashHex), answer: a == WelcomeAnswer.yes ? 'yes' : 'no', atMs: nowMs());
    await _all(() async {
      context.votes.add(v);
      await _persist();
    });
    // The answer is in. Forgetting the put-off is tidying; if it cannot be saved, the answer still stands.
    try {
      final Map<String, AskLater> asks = await reminders.load();
      if (asks.remove(hashHex) != null) await reminders.save(asks);
    } catch (_) {}
  }

  /// "Yes to something smaller": says not this time to the big request and starts a smaller one in this grown-up's
  /// name, which the person who first asked has to accept. Always asks every parent, whatever the family setting.
  Future<LedgerEntry> yesToSmaller(String hashHex, MemberProfile smaller) async {
    final WelcomeRequest r = await _find(hashHex);
    if (!r.open || !r.needsMyAnswer) {
      throw const WelcomeRefused('not-yours-to-answer', 'You can offer something smaller only while a request is waiting for you.');
    }
    if (!smallerThan(smaller, r.profile)) {
      throw const WelcomeRefused('not-smaller', 'The smaller choice must give less than the first, not the same or more.');
    }
    final int now = nowMs();
    final LedgerState s = await context.state(nowMs: now);
    final LedgerEntry? original = context.entries.where((LedgerEntry e) => e.hashHex == hashHex).firstOrNull;
    if (original == null) throw const WelcomeRefused('gone', 'That request is not here any more.');
    final DeviceRecord cand = DeviceRecord.fromValue(original.body['dev'])!;
    await _checkCandidate(cand);
    // The wait after a no does not apply to a smaller offer (it is the way out of a flat no); everything else does.
    _checkMayAsk(s, smaller, cand.key, now);
    // Say no to the big one in the same step, so the person is never in at the bigger level by two roads.
    final LedgerVote no = await LedgerVote.sign(_me, target: fromHex(hashHex), answer: 'no', atMs: now);
    return _all(() async {
      context.votes.add(no);
      final LedgerState s2 = await context.state(nowMs: now);
      return _sign(s2, smaller, cand, r.personName, fromHex(r.personGidHex), forceAll: true, now: now);
    });
  }

  // ---- ask me later -------------------------------------------------------------------------------------------

  /// Remember to ask again in 24 hours. Signs nothing and sends nothing; it is never a yes.
  Future<AskLater> askLater(String hashHex) async {
    final WelcomeOverview o = await overview();
    final WelcomeRequest? r = o.forMe.where((WelcomeRequest x) => x.hashHex == hashHex).firstOrNull;
    if (r == null) {
      throw const WelcomeRefused('not-yours-to-answer', 'You can put off only a request that is waiting for your answer.');
    }
    final Map<String, AskLater> asks = await _pruned(o, await reminders.load());
    final AskLater cur = asks[hashHex] ?? const AskLater();
    if (cur.snoozes >= kMaxSnoozes) {
      throw const WelcomeRefused('no-more-later',
          'You have asked to be reminded three times. It will wait here until it ends.');
    }
    final AskLater next = AskLater(snoozes: cur.snoozes + 1, untilMs: nowMs() + kSnoozeMs, reminders: cur.reminders);
    asks[hashHex] = next;
    try {
      await reminders.save(asks);
    } catch (_) {
      throw const WelcomeRefused('not-saved', 'That could not be saved on this phone. Please try again.');
    }
    return next;
  }

  /// Drops the put-offs of requests that are no longer open (answered, cancelled, lapsed, or not in this family's
  /// record at all), so nothing piles up. Saved when something was dropped; if saving fails the clean list is still used.
  Future<Map<String, AskLater>> _pruned(WelcomeOverview o, Map<String, AskLater> asks) async {
    final Set<String> open = <String>{
      for (final WelcomeRequest r in <WelcomeRequest>[...o.forMe, ...o.others, ...o.sent])
        if (r.open) r.hashHex,
    };
    final int before = asks.length;
    asks.removeWhere((String k, AskLater _) => !open.contains(k));
    if (asks.length != before) {
      try {
        await reminders.save(asks);
      } catch (_) {}
    }
    return asks;
  }

  /// Open requests that were put off and are due a quiet reminder now. At most two reminders per request, ever.
  Future<List<WelcomeRequest>> remindersDue() async {
    final WelcomeOverview o = await overview();
    final Map<String, AskLater> asks = await _pruned(o, await reminders.load());
    final int now = nowMs();
    return <WelcomeRequest>[
      for (final WelcomeRequest r in o.forMe)
        if (asks[r.hashHex] != null &&
            asks[r.hashHex]!.snoozes > 0 &&
            now >= asks[r.hashHex]!.untilMs &&
            asks[r.hashHex]!.reminders < kMaxReminders)
          r,
    ];
  }

  Future<void> reminderShown(String hashHex) async {
    final Map<String, AskLater> asks = await reminders.load();
    final AskLater? cur = asks[hashHex];
    if (cur == null || cur.reminders >= kMaxReminders) return;
    asks[hashHex] = AskLater(snoozes: cur.snoozes, untilMs: nowMs() + kSnoozeMs, reminders: cur.reminders + 1);
    await reminders.save(asks);
  }

  /// True when this request is currently put off, so a list can show it below the ones to answer now.
  Future<bool> isPutOff(String hashHex) async {
    final AskLater? a = (await reminders.load())[hashHex];
    return a != null && a.snoozes > 0 && nowMs() < a.untilMs;
  }
}
