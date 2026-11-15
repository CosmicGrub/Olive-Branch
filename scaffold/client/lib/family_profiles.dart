// OLIVE BRANCH — who a person in the family may be: tier, preset, capability list, computed reach, and the
// fixed-versus-set table that says which capability switches a proposer may flip. UNVERIFIED on a device; pure
// Dart, runs headless in CI. Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 4.1 to 4.4 and 5.
//
// This file is DATA plus validation. It carries no screen, no storage and no signing. The family ledger
// (family_ledger.dart) stores a [MemberProfile] inside a `member.add` entry and refuses an entry whose profile
// breaks a fixed cell, so a hostile or buggy proposer cannot hand a carer the expenses (C5) or the family settings
// (C6) by writing a bigger list than the table allows.
//
// What this does NOT do (not built, see the MASTERFILE "not built" section): the "Parent with limits" 4.4 floors
// beyond the fixed cells below (narrowing a limited parent's voice on Look-reach welcomes is not expressible; C12 is
// fixed on for a limited parent), the Helper page (it has no key and no ledger entry, so it is never a member), and
// any screen. A child never sees any of this (P1 to P11).
/// The three tiers. A [helperPage] is a page held up on a screen: it has no key and is never a ledger member.
enum MemberTier { parent, carer, helperPage }

/// The six presets of the village design, section 4.2.
enum Preset { parent, parentWithLimits, trustedCarer, visit, viewOnly, helperPage }

/// Look = can only read. Act = can write, unlock a tablet or reach the child. Parent = equal say.
enum Reach { look, act, parent }

/// C1 to C13 of section 4.1, in the table's order. [number] is what is written into a ledger entry.
enum Capability {
  history(1), // C1 see the family history and who is in the village
  calendar(2), // C2 calendar and weeks
  emergencyCard(3), // C3 emergency card and medicines (read)
  careNotes(4), // C4 write care notes, log a dose
  expenses(5), // C5 see and add expenses (parents only; never a child, P6)
  settings(6), // C6 family settings, parental controls, the age lock
  ownPin(7), // C7 their OWN PIN only
  connectDevice(8), // C8 open the pairing window for a child's device
  unlockPlay(9), // C9 unlock a tablet with their phone, play together
  messageChild(10), // C10 message or call her through the existing safe paths
  startWelcome(11), // C11 start a welcome (parents only)
  voteWelcome(12), // C12 say yes or no on welcomes (parents only)
  pauseCarer(13); // C13 pause a carer (parents only)

  const Capability(this.number);
  final int number;

  static Capability? fromNumber(int n) {
    for (final Capability c in Capability.values) {
      if (c.number == n) return c;
    }
    return null;
  }
}

/// One cell of the table. [fixed] cells cannot be flipped by the proposer; [setDefault] cells can.
class Cell {
  const Cell.fixed(this.on)
      : fixed = true,
        available = true;
  const Cell.setting(this.on)
      : fixed = false,
        available = true;

  /// "None": the preset has no account, so no capability exists at all (the Helper page).
  const Cell.none()
      : on = false,
        fixed = true,
        available = false;

  /// The value of a fixed cell, or the default of a settable one.
  final bool on;
  final bool fixed, available;
}

const Cell _y = Cell.fixed(true), _n = Cell.fixed(false);
const Cell _sy = Cell.setting(true), _sn = Cell.setting(false);
const Cell _none = Cell.none();

/// Section 4.2 transcribed. "Yes" and "No" without "(default ...)" are treated as fixed; "Set" with no stated
/// default starts ON (a limited parent starts as a parent minus what is turned off). Where the table says C12 is
/// "Yes for Act and Parent reach (fixed), Set for Look reach" for a limited parent, v1 keeps it fixed ON (narrowing
/// the voice on Look-reach welcomes is not built).
const Map<Preset, Map<Capability, Cell>> kProfileTable = <Preset, Map<Capability, Cell>>{
  Preset.parent: <Capability, Cell>{
    Capability.history: _y, Capability.calendar: _y, Capability.emergencyCard: _y, Capability.careNotes: _y,
    Capability.expenses: _y, Capability.settings: _y, Capability.ownPin: _y, Capability.connectDevice: _y,
    Capability.unlockPlay: _y, Capability.messageChild: _y, Capability.startWelcome: _y,
    Capability.voteWelcome: _y, Capability.pauseCarer: _y,
  },
  Preset.parentWithLimits: <Capability, Cell>{
    Capability.history: _y, Capability.calendar: _y, Capability.emergencyCard: _y, Capability.careNotes: _sy,
    Capability.expenses: _sy, Capability.settings: _sn, Capability.ownPin: _y, Capability.connectDevice: _sy,
    Capability.unlockPlay: _y, Capability.messageChild: _y, Capability.startWelcome: _sn,
    Capability.voteWelcome: _y, Capability.pauseCarer: _y,
  },
  Preset.trustedCarer: <Capability, Cell>{
    Capability.history: _sy, Capability.calendar: _y, Capability.emergencyCard: _y, Capability.careNotes: _sy,
    Capability.expenses: _n, Capability.settings: _n, Capability.ownPin: _y, Capability.connectDevice: _sn,
    Capability.unlockPlay: _sy, Capability.messageChild: _sy, Capability.startWelcome: _n,
    Capability.voteWelcome: _n, Capability.pauseCarer: _n,
  },
  Preset.visit: <Capability, Cell>{
    Capability.history: _sn, Capability.calendar: _sy, Capability.emergencyCard: _y, Capability.careNotes: _sy,
    Capability.expenses: _n, Capability.settings: _n, Capability.ownPin: _y, Capability.connectDevice: _n,
    Capability.unlockPlay: _sy, Capability.messageChild: _sn, Capability.startWelcome: _n,
    Capability.voteWelcome: _n, Capability.pauseCarer: _n,
  },
  Preset.viewOnly: <Capability, Cell>{
    Capability.history: _sy, Capability.calendar: _sy, Capability.emergencyCard: _sy, Capability.careNotes: _n,
    Capability.expenses: _n, Capability.settings: _n, Capability.ownPin: _y, Capability.connectDevice: _n,
    Capability.unlockPlay: _n, Capability.messageChild: _n, Capability.startWelcome: _n,
    Capability.voteWelcome: _n, Capability.pauseCarer: _n,
  },
  Preset.helperPage: <Capability, Cell>{
    Capability.history: _none, Capability.calendar: _none, Capability.emergencyCard: _none,
    Capability.careNotes: _none, Capability.expenses: _none, Capability.settings: _none,
    Capability.ownPin: _none, Capability.connectDevice: _none, Capability.unlockPlay: _none,
    Capability.messageChild: _none, Capability.startWelcome: _none, Capability.voteWelcome: _none,
    Capability.pauseCarer: _none,
  },
};

MemberTier tierOf(Preset p) {
  switch (p) {
    case Preset.parent:
    case Preset.parentWithLimits:
      return MemberTier.parent;
    case Preset.trustedCarer:
    case Preset.visit:
    case Preset.viewOnly:
      return MemberTier.carer;
    case Preset.helperPage:
      return MemberTier.helperPage;
  }
}

/// How long a new person stays in "settle in" (hours), by preset: 72 for a parent, 24 for a trusted carer, none for
/// the rest. The family's own `settle` policy can only make this longer or shorter within 0, 24 and 72; the
/// ledger uses the policy value for a guardian and this default only as a documented reference.
int defaultSettleHours(Preset p) {
  switch (p) {
    case Preset.parent:
    case Preset.parentWithLimits:
      return 72;
    case Preset.trustedCarer:
      return 24;
    case Preset.visit:
    case Preset.viewOnly:
    case Preset.helperPage:
      return 0;
  }
}

const int kMsPerDay = 24 * 60 * 60 * 1000;

/// A Visit is time-boxed and required to be at most 14 days.
const int kVisitMaxDays = 14;

/// How long a request to welcome someone stays open before silence ends it (section 5.2): a parent 14 days, a
/// trusted carer 7, a Visit 3, a View only 7. Silence is never yes.
int proposalLifetimeMs(Preset p) {
  switch (p) {
    case Preset.parent:
    case Preset.parentWithLimits:
      return 14 * kMsPerDay;
    case Preset.trustedCarer:
    case Preset.viewOnly:
      return 7 * kMsPerDay;
    case Preset.visit:
      return 3 * kMsPerDay;
    case Preset.helperPage:
      return 0;
  }
}

/// A profile as it is written into a ledger entry: preset, the capability switches that are ON, which children
/// (null = all), and an optional time box (milliseconds since the epoch, [fromMs] inclusive, [untilMs] exclusive).
class MemberProfile {
  MemberProfile({required this.preset, required Iterable<Capability> caps, this.children, this.fromMs, this.untilMs})
      : caps = (caps.toSet().toList()..sort((Capability a, Capability b) => a.number - b.number));

  /// The preset's own defaults: every fixed cell as fixed, every settable cell at its default.
  factory MemberProfile.defaults(Preset preset, {List<String>? children, int? fromMs, int? untilMs}) {
    final Map<Capability, Cell> row = kProfileTable[preset]!;
    return MemberProfile(
      preset: preset,
      caps: <Capability>[for (final Capability c in Capability.values) if (row[c]!.available && row[c]!.on) c],
      children: children,
      fromMs: fromMs,
      untilMs: untilMs,
    );
  }

  final Preset preset;
  final List<Capability> caps; // sorted by number, no duplicates
  final List<String>? children; // null means every child
  final int? fromMs, untilMs;

  MemberTier get tier => tierOf(preset);
  bool has(Capability c) => caps.contains(c);

  /// Computed, never chosen: Parent tier, or C11 or C12 on, is Parent; any of C4, C6, C8, C9, C10 on is Act;
  /// otherwise Look. (The preset table's one-line summary says a Visit with only C4 is Look; the Notes under the
  /// table say C4 on makes it Act. This applies the Notes: it is the stricter reading, it asks for more approvals.)
  Reach get reach {
    if (tier == MemberTier.parent || has(Capability.startWelcome) || has(Capability.voteWelcome)) return Reach.parent;
    for (final Capability c in const <Capability>[
      Capability.careNotes, Capability.settings, Capability.connectDevice, Capability.unlockPlay,
      Capability.messageChild,
    ]) {
      if (has(c)) return Reach.act;
    }
    return Reach.look;
  }

  /// Null when this profile is allowed; otherwise a short reason for the first thing wrong. Pure; no clock.
  String? violation() {
    if (preset == Preset.helperPage) return 'helper-page-has-no-member';
    final Map<Capability, Cell> row = kProfileTable[preset]!;
    for (final Capability c in Capability.values) {
      final Cell cell = row[c]!;
      final bool on = has(c);
      if (!cell.available && on) return 'capability-not-available';
      if (cell.fixed && cell.available && on != cell.on) return 'fixed-capability-${c.number}';
    }
    if (preset == Preset.parent && children != null) return 'parent-has-all-children';
    final List<String>? kids = children;
    if (kids != null) {
      if (kids.isEmpty) return 'children-empty';
      if (kids.toSet().length != kids.length) return 'children-duplicate';
      for (final String k in kids) {
        if (k.isEmpty || k.length > 64) return 'child-id-bad';
      }
    }
    final int? f = fromMs, u = untilMs;
    if (f != null && u != null && u <= f) return 'time-box-backwards';
    if (preset == Preset.visit) {
      if (f == null || u == null) return 'visit-needs-time-box';
      if (u - f > kVisitMaxDays * kMsPerDay) return 'visit-too-long';
    }
    return null;
  }

  Map<String, Object?> toValue() => <String, Object?>{
        'preset': preset.name,
        'caps': <int>[for (final Capability c in caps) c.number],
        'children': children,
        'from': fromMs,
        'until': untilMs,
      };

  /// Strict parse of [toValue]. Null on anything that is not exactly that shape.
  static MemberProfile? fromValue(Object? v) {
    if (v is! Map<String, Object?>) return null;
    if (v.length != 5) return null;
    final Object? p = v['preset'], c = v['caps'], ch = v['children'], f = v['from'], u = v['until'];
    if (p is! String || c is! List || (ch != null && ch is! List) || (f != null && f is! int) || (u != null && u is! int)) {
      return null;
    }
    Preset? preset;
    for (final Preset x in Preset.values) {
      if (x.name == p) preset = x;
    }
    if (preset == null) return null;
    final List<Capability> caps = <Capability>[];
    int last = 0;
    for (final Object? n in c) {
      if (n is! int) return null;
      final Capability? cap = Capability.fromNumber(n);
      if (cap == null || n <= last) return null; // must be strictly ascending: one canonical form only
      last = n;
      caps.add(cap);
    }
    List<String>? kids;
    if (ch != null) {
      kids = <String>[];
      for (final Object? k in ch as List) {
        if (k is! String) return null;
        kids.add(k);
      }
    }
    return MemberProfile(preset: preset, caps: caps, children: kids, fromMs: f as int?, untilMs: u as int?);
  }
}
