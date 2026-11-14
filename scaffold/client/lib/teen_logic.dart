// OLIVE BRANCH — the rules of the 13 to 17 shell and the 18 handover, as pure Dart. UNVERIFIED until CI runs it
// (client/test/teen_logic_test.dart). Prototype: mod-child.js k.cal / k.free / k.privacy / k.ladder / k.copy /
// k.handover; round-3 mockups r3a-13-* and r3a-18-*. MASTERFILE §21 and §8.1.
//
// What is in here is only RULES, so each one has a unit test and none of them can drift into a screen:
//   - Her own calendar: an event is hers, a title of at most 60 characters, and nobody else sees it until she picks
//     who ([TeenEvent.share]; the default is nobody). From 14 she edits; before that she only looks.
//   - Her free times (rung 15): three parts of the day, school days and weekends. A grown-up sees WHAT she
//     published and never why she is busy.
//   - The privacy contract: ONE table of who sees what, symmetrical (the same rules run the other way), plain words.
//     The journal, where she is and what she hides are NO for everyone, always. Nothing in it is a count.
//   - The ask: a grown-up may ask her to share ONE of three things (free times, her calendar, pictures). She says
//     yes or no. A no is final for seven days: the same grown-up cannot ask the same thing again until the seventh
//     day has passed. Her journal, her messages with anyone else, where she is and what she hid can never be
//     asked for at all ([isAskable]).
//   - The consent log is DERIVED from the asks (every ask and every answer), so it can never say something the
//     asks do not.
//   - The 18 handover: three paths (take and go, keep as an archive, both) plus 'someday for my own family'. No
//     path is a default. Taking a copy and going keeps the app's copy for 30 days, and she can change her mind
//     inside them. Staying in touch needs BOTH sides, channel by channel, and either side ends it with one tap.
//
// Nothing here reads a clock, a store or a server: every rule takes `now` as an argument.

// ============================================================== constants ===
/// A no is final for this many days (the ask).
const int kAskWaitDays = 7;

/// The app's copy is kept this long after 'take and go' (she can still change her mind inside it).
const int kTakeAndGoKeepDays = 30;

/// A calendar event's title.
const int kEventTitleMax = 60;

/// A note a grown-up leaves for her 18th birthday.
const int kHandoverNoteMax = 600;

/// The calendar opens for editing at this age (rung 14); before it she can only look.
const int kOwnCalendarAge = 14;

/// Free times open at this age (rung 15).
const int kFreeTimesAge = 15;

/// Her age when the handover takes place.
const int kHandoverAge = 18;

/// The heads-up reaches both sides this many days before the birthday.
const int kHandoverHeadsUpDays = 90;

// ================================================================ calendar ===
/// Who else can see one of her events. [onlyMe] is the default and an event with no ids is hers alone.
class EventShare {
  const EventShare._(this.guardianIds);
  static const EventShare onlyMe = EventShare._(<String>{});
  const EventShare.with_(Set<String> ids) : guardianIds = ids;
  final Set<String> guardianIds;

  bool get isPrivate => guardianIds.isEmpty;
  bool sees(String guardianId) => guardianIds.contains(guardianId);
}

class TeenEvent {
  const TeenEvent({
    required this.id, required this.year, required this.month, required this.day, required this.title,
    this.share = EventShare.onlyMe,
  });
  final String id;
  final int year;
  final int month;
  final int day;
  final String title;
  final EventShare share;

  bool onDay(int y, int m, int d) => year == y && month == m && day == d;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'y': year, 'm': month, 'd': day, 'title': title,
        'to': (share.guardianIds.toList()..sort()),
      };

  static TeenEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], y = j['y'], m = j['m'], d = j['d'], title = j['title'], to = j['to'];
    if (id is! String || y is! int || m is! int || d is! int || title is! String) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return TeenEvent(
      id: id, year: y, month: m, day: d, title: title,
      share: to is List && to.isNotEmpty ? EventShare.with_(<String>{for (final Object? x in to) if (x is String) x}) : EventShare.onlyMe,
    );
  }
}

/// The title as it is kept: trimmed and cut to [kEventTitleMax]. Null when nothing is left.
String? cleanEventTitle(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return null;
  return t.length > kEventTitleMax ? t.substring(0, kEventTitleMax).trimRight() : t;
}

/// She edits from 14; before that she looks.
bool canEditOwnCalendar(int age) => age >= kOwnCalendarAge;

/// The events of one day, in the order she made them.
List<TeenEvent> eventsOn(List<TeenEvent> all, int y, int m, int d) =>
    <TeenEvent>[for (final TeenEvent e in all) if (e.onDay(y, m, d)) e];

/// What one grown-up can see of her calendar: ONLY the events she shared with that grown-up. Everything else is
/// absent, not hidden, not counted.
List<TeenEvent> eventsSharedWith(List<TeenEvent> all, String guardianId) =>
    <TeenEvent>[for (final TeenEvent e in all) if (e.share.sees(guardianId)) e];

// =============================================================== free times ===
const List<(String, String)> kFreeParts = <(String, String)>[
  ('am', 'Before school'), ('pm', 'After school'), ('eve', 'Evening'),
];

/// Which parts of the day she is free, on school days and at weekends.
class FreeTimes {
  const FreeTimes({
    this.schoolDays = const <String>{}, this.weekends = const <String>{}, this.published = false,
  });
  final Set<String> schoolDays;
  final Set<String> weekends;

  /// She has pressed Save at least once: what is shown is what she set (rung 15), not inferred.
  final bool published;

  FreeTimes toggled(bool weekend, String part) {
    final Set<String> s = <String>{...(weekend ? weekends : schoolDays)};
    s.contains(part) ? s.remove(part) : s.add(part);
    return FreeTimes(schoolDays: weekend ? schoolDays : s, weekends: weekend ? s : weekends, published: published);
  }

  FreeTimes asPublished() => FreeTimes(schoolDays: schoolDays, weekends: weekends, published: true);

  String _words(Set<String> s) {
    final List<String> f = <String>[for (final (String id, String label) in kFreeParts) if (s.contains(id)) label.toLowerCase()];
    return f.isEmpty ? 'nothing shown' : 'free ${f.join(', ')}';
  }

  /// What a grown-up sees, in her words. It never says why she is busy.
  String describe() => 'School days ${_words(schoolDays)}. Weekends ${_words(weekends)}.';

  Map<String, Object?> toJson() => <String, Object?>{
        'wd': (schoolDays.toList()..sort()), 'we': (weekends.toList()..sort()), 'published': published,
      };

  static FreeTimes fromJson(Object? j) {
    if (j is! Map) return const FreeTimes();
    final Set<String> ok = <String>{for (final (String id, String _) in kFreeParts) id};
    Set<String> s(Object? v) => <String>{if (v is List) for (final Object? x in v) if (x is String && ok.contains(x)) x};
    return FreeTimes(schoolDays: s(j['wd']), weekends: s(j['we']), published: j['published'] == true);
  }
}

// ================================================================== the ask ===
/// What a grown-up may ask her to share. Three things, and only these.
enum ShareKind { freeTimes, calendar, pictures }

extension ShareKindWords on ShareKind {
  /// The words a grown-up sees when asking.
  String get askWords => switch (this) {
        ShareKind.freeTimes => 'when you are free',
        ShareKind.calendar => 'your calendar',
        ShareKind.pictures => 'pictures you made',
      };

  /// The words she sees when she is asked.
  String get title => switch (this) {
        ShareKind.freeTimes => 'Your free times',
        ShareKind.calendar => 'Your calendar',
        ShareKind.pictures => 'Pictures you made',
      };

  /// What a yes lets that one grown-up see, in plain words.
  String get yesMeans => switch (this) {
        ShareKind.freeTimes => 'They see the free times you set. Never why you are busy.',
        ShareKind.calendar => 'New events start shared with them. You can still pick only me on each one.',
        ShareKind.pictures => 'They see the pictures you pick. Only those.',
      };

  /// The age she must be for the ask to make sense (before it, the thing does not exist yet).
  int get minAge => switch (this) {
        ShareKind.freeTimes => kFreeTimesAge,
        ShareKind.calendar => kOwnCalendarAge,
        ShareKind.pictures => 13,
      };
}

/// Things that can NEVER be asked for, by anyone. A kind named here is refused before any screen is built.
const Set<String> kNeverAskable = <String>{
  'journal', 'worries', 'location', 'messages', 'hidden', 'archive_hidden', 'feelings',
};

/// True only for the three kinds in [ShareKind]. [name] is a plain string so the refusal is testable for the
/// forbidden ones too.
bool isAskable(String name) =>
    !kNeverAskable.contains(name) && ShareKind.values.any((ShareKind k) => k.name == name);

enum AskAnswer { yes, no }

class ShareAsk {
  const ShareAsk({
    required this.id, required this.askerId, required this.kind, required this.askedAt,
    this.answer, this.answeredAt, this.stoppedAt,
  });
  final String id;
  final String askerId;
  final ShareKind kind;
  final DateTime askedAt;
  final AskAnswer? answer;
  final DateTime? answeredAt;

  /// She stopped sharing after a yes.
  final DateTime? stoppedAt;

  bool get pending => answer == null;
  bool get sharing => answer == AskAnswer.yes && stoppedAt == null;

  /// The moment her answer began to count as final (a no, or a yes she took back).
  DateTime? get declinedAt => answer == AskAnswer.no ? answeredAt : stoppedAt;

  ShareAsk answered(AskAnswer a, DateTime now) =>
      ShareAsk(id: id, askerId: askerId, kind: kind, askedAt: askedAt, answer: a, answeredAt: now, stoppedAt: stoppedAt);

  ShareAsk stopped(DateTime now) =>
      ShareAsk(id: id, askerId: askerId, kind: kind, askedAt: askedAt, answer: answer, answeredAt: answeredAt, stoppedAt: now);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'by': askerId, 'kind': kind.name, 'at': askedAt.toIso8601String(),
        if (answer != null) 'answer': answer!.name,
        if (answeredAt != null) 'answeredAt': answeredAt!.toIso8601String(),
        if (stoppedAt != null) 'stoppedAt': stoppedAt!.toIso8601String(),
      };

  static ShareAsk? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], by = j['by'], kind = j['kind'], at = j['at'];
    if (id is! String || by is! String || kind is! String || at is! String) return null;
    final ShareKind? k = ShareKind.values.where((ShareKind x) => x.name == kind).firstOrNull;
    final DateTime? when = DateTime.tryParse(at);
    if (k == null || when == null) return null;
    final AskAnswer? a = AskAnswer.values.where((AskAnswer x) => x.name == j['answer']).firstOrNull;
    final Object? ans = j['answeredAt'], stop = j['stoppedAt'];
    return ShareAsk(
      id: id, askerId: by, kind: k, askedAt: when, answer: a,
      answeredAt: a != null && ans is String ? DateTime.tryParse(ans) : null,
      stoppedAt: stop is String ? DateTime.tryParse(stop) : null,
    );
  }
}

/// The result of asking whether an ask may be made now.
class AskCheck {
  const AskCheck._(this.ok, this.reason, this.waitUntil);
  const AskCheck.allowed() : this._(true, null, null);
  final bool ok;

  /// 'pending' | 'waiting' | 'already_sharing' | 'not_askable' | 'too_young'
  final String? reason;

  /// For 'waiting': the first moment the same ask may be made again.
  final DateTime? waitUntil;
  static const AskCheck pending = AskCheck._(false, 'pending', null);
  static const AskCheck alreadySharing = AskCheck._(false, 'already_sharing', null);
  static const AskCheck notAskable = AskCheck._(false, 'not_askable', null);
  static const AskCheck tooYoung = AskCheck._(false, 'too_young', null);
  AskCheck.waiting(DateTime until) : this._(false, 'waiting', until);
}

/// Every ask ever made, oldest first. Append-only: an answer is added to an ask, an ask is never removed.
class AskLedger {
  const AskLedger([this.asks = const <ShareAsk>[]]);
  final List<ShareAsk> asks;

  /// May [askerId] ask for [kind] now? One open ask per grown-up and kind; no ask while she is already sharing it
  /// with them; and after a no (or after she stopped sharing) not until [kAskWaitDays] days have passed.
  AskCheck canAsk(String askerId, String kind, DateTime now, {required int herAge}) {
    if (!isAskable(kind)) return AskCheck.notAskable;
    final ShareKind k = ShareKind.values.firstWhere((ShareKind x) => x.name == kind);
    if (herAge < k.minAge) return AskCheck.tooYoung;
    DateTime? latestDecline;
    for (final ShareAsk a in asks) {
      if (a.askerId != askerId || a.kind != k) continue;
      if (a.pending) return AskCheck.pending;
      if (a.sharing) return AskCheck.alreadySharing;
      final DateTime? d = a.declinedAt;
      if (d != null && (latestDecline == null || d.isAfter(latestDecline))) latestDecline = d;
    }
    if (latestDecline != null) {
      final DateTime until = latestDecline.add(const Duration(days: kAskWaitDays));
      if (now.isBefore(until)) return AskCheck.waiting(until);
    }
    return const AskCheck.allowed();
  }

  /// A new ledger with the ask added, or null when [canAsk] refuses.
  AskLedger? ask(String id, String askerId, String kind, DateTime now, {required int herAge}) {
    if (!canAsk(askerId, kind, now, herAge: herAge).ok) return null;
    return AskLedger(<ShareAsk>[
      ...asks,
      ShareAsk(id: id, askerId: askerId, kind: ShareKind.values.firstWhere((ShareKind x) => x.name == kind), askedAt: now),
    ]);
  }

  AskLedger answer(String id, AskAnswer a, DateTime now) => AskLedger(<ShareAsk>[
        for (final ShareAsk x in asks) x.id == id && x.pending ? x.answered(a, now) : x,
      ]);

  /// She stops sharing: a no from then on, so the seven days run from now.
  AskLedger stop(String id, DateTime now) => AskLedger(<ShareAsk>[
        for (final ShareAsk x in asks) x.id == id && x.sharing ? x.stopped(now) : x,
      ]);

  List<ShareAsk> get open => <ShareAsk>[for (final ShareAsk a in asks) if (a.pending) a];

  /// Who sees [kind] right now: only the grown-ups she said yes to and has not stopped.
  Set<String> sharingWith(ShareKind kind) => <String>{
        for (final ShareAsk a in asks) if (a.kind == kind && a.sharing) a.askerId,
      };

  Map<String, Object?> toJson() => <String, Object?>{'asks': <Object?>[for (final ShareAsk a in asks) a.toJson()]};

  static AskLedger fromJson(Object? j) {
    if (j is! Map || j['asks'] is! List) return const AskLedger();
    return AskLedger(<ShareAsk>[
      for (final Object? o in j['asks'] as List<Object?>) ?ShareAsk.fromJson(o),
    ]);
  }
}

/// One line of her consent log: an ask or an answer, in time order.
class ConsentLine {
  const ConsentLine(this.at, this.askId, this.kind, this.askerId, this.event);
  final DateTime at;
  final String askId;
  final ShareKind kind;
  final String askerId;

  /// 'asked' | 'yes' | 'no' | 'stopped'
  final String event;
}

/// Every ask and every answer, newest first, built from the ledger and nothing else.
List<ConsentLine> consentLog(AskLedger l) {
  final List<ConsentLine> out = <ConsentLine>[];
  for (final ShareAsk a in l.asks) {
    out.add(ConsentLine(a.askedAt, a.id, a.kind, a.askerId, 'asked'));
    if (a.answer != null && a.answeredAt != null) out.add(ConsentLine(a.answeredAt!, a.id, a.kind, a.askerId, a.answer!.name));
    if (a.stoppedAt != null) out.add(ConsentLine(a.stoppedAt!, a.id, a.kind, a.askerId, 'stopped'));
  }
  out.sort((ConsentLine x, ConsentLine y) => y.at.compareTo(x.at));
  return out;
}

// ============================================================ privacy contract ===
enum Seen { see, choose, no }

class ContractRow {
  const ContractRow(this.title, this.sub, this.values);
  final String title;
  final String sub;

  /// One value per grown-up, in the order the grown-ups were given.
  final List<Seen> values;
}

/// The table of who can see what. [guardians] are the names SHE uses for them. The shape of the answer is the
/// contract: messages go to one grown-up only, free times are what she publishes (from 15), events and pictures are
/// her choice, and the journal, her whereabouts and what she hides are NO for everyone.
List<ContractRow> privacyContract(List<String> guardians, {required int age}) {
  final int n = guardians.length;
  List<Seen> all(Seen s) => List<Seen>.filled(n, s);
  return <ContractRow>[
    for (int i = 0; i < n; i++)
      ContractRow('Messages you send to ${guardians[i]}', 'Only the two of you read them.',
          <Seen>[for (int j = 0; j < n; j++) i == j ? Seen.see : Seen.no]),
    ContractRow('Your free times', age >= kFreeTimesAge ? 'What you publish.' : 'From 15, what you publish.',
        all(age >= kFreeTimesAge ? Seen.see : Seen.no)),
    ContractRow('Events you add', 'You choose each one.', all(Seen.choose)),
    ContractRow('Pictures you show', 'You choose each one.', all(Seen.choose)),
    ContractRow('Your journal', 'Nobody can open it.', all(Seen.no)),
    ContractRow('Where you are', 'We never ask your device.', all(Seen.no)),
    ContractRow('Things you hide in your archive', 'Nobody is told.', all(Seen.no)),
  ];
}

/// The same rules the other way: what SHE does not see of them, and what she does.
String privacyReverse(int guardianCount) =>
    'The same rules, the other way. You never see ${guardianCount > 1 ? "their messages to each other, their money, or where they are" : "their money or where they are"}. You do see when they are free to talk.';

// ===================================================================== 18 ===
enum HandoverChoice { take, keep, both, later }

extension HandoverChoiceWords on HandoverChoice {
  String get title => switch (this) {
        HandoverChoice.take => 'Take your data and go',
        HandoverChoice.keep => 'Keep it as your archive',
        HandoverChoice.both => 'Both',
        HandoverChoice.later => 'Someday, for your own family',
      };

  String get sub => switch (this) {
        HandoverChoice.take => 'You keep a copy. We keep ours for 30 days, then it goes.',
        HandoverChoice.keep => 'You look after it. Your parents cannot open it.',
        HandoverChoice.both => 'Take a copy now and keep the archive going.',
        HandoverChoice.later => 'What you were handed can become the first page of theirs. Nothing to decide now.',
      };

  /// True when she leaves with a copy she made on this tablet.
  bool get makesCopy => this == HandoverChoice.take || this == HandoverChoice.both;
}

/// What the tablet remembers about her handover. Hers alone: no counts, nothing in it a grown-up reads.
class HandoverRecord {
  const HandoverRecord({this.choice, this.chosenAt, this.copyMadeAt, this.copyPath});
  final HandoverChoice? choice;
  final DateTime? chosenAt;

  /// The copy was written to a file on this tablet and read back.
  final DateTime? copyMadeAt;
  final String? copyPath;

  bool get chosen => choice != null && chosenAt != null;

  /// The first day the app's own copy may go. Only 'take and go' ever removes it ('both' and 'keep' keep it).
  DateTime? get keepUntil =>
      chosen && choice == HandoverChoice.take ? chosenAt!.add(const Duration(days: kTakeAndGoKeepDays)) : null;

  /// She can still change her mind: inside the 30 days for take and go, any time for the others.
  bool canChange(DateTime now) => !chosen || keepUntil == null || now.isBefore(keepUntil!);

  /// The app's copy on this tablet is due to go: she took and went, her own copy is saved and checked, and the 30 days
  /// have passed. Without a saved copy nothing is ever removed.
  bool purgeDue(DateTime now) => keepUntil != null && copyMadeAt != null && !now.isBefore(keepUntil!);

  HandoverRecord chose(HandoverChoice c, DateTime now) => HandoverRecord(
        choice: c, chosenAt: now, copyMadeAt: c.makesCopy ? copyMadeAt : null, copyPath: c.makesCopy ? copyPath : null);

  HandoverRecord copyMade(DateTime now, String path) =>
      HandoverRecord(choice: choice, chosenAt: chosenAt, copyMadeAt: now, copyPath: path);

  Map<String, Object?> toJson() => <String, Object?>{
        if (choice != null) 'choice': choice!.name,
        if (chosenAt != null) 'chosenAt': chosenAt!.toIso8601String(),
        if (copyMadeAt != null) 'copyMadeAt': copyMadeAt!.toIso8601String(),
        if (copyPath != null) 'copyPath': copyPath,
      };

  static HandoverRecord fromJson(Object? j) {
    if (j is! Map) return const HandoverRecord();
    final HandoverChoice? c = HandoverChoice.values.where((HandoverChoice x) => x.name == j['choice']).firstOrNull;
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return HandoverRecord(
        choice: c, chosenAt: d(j['chosenAt']), copyMadeAt: d(j['copyMadeAt']),
        copyPath: j['copyPath'] is String ? j['copyPath'] as String : null);
  }
}

// ------------------------------------------------------------ heads-up (90 days) ---
/// The heads-up shows for the 90 days before the 18th birthday, to her and to her grown-ups alike (the same words).
/// [turnsYears] is the age the next birthday brings and [sleepsUntil] the days to it (ChildBirthday's own numbers).
bool handoverHeadsUp({required int turnsYears, required int sleepsUntil}) =>
    turnsYears == kHandoverAge && sleepsUntil > 0 && sleepsUntil <= kHandoverHeadsUpDays;

/// She is 18 or over: the handover is hers to decide.
bool atHandover(int age) => age >= kHandoverAge;

// ------------------------------------------------------------ staying in touch ---
enum Channel { messages, calls, calendar }

extension ChannelWords on Channel {
  String get title => switch (this) {
        Channel.messages => 'Messages',
        Channel.calls => 'Calls',
        Channel.calendar => 'A shared calendar',
      };
  String get sub => switch (this) {
        Channel.messages => 'A thread with each of them',
        Channel.calls => 'They can ring you',
        Channel.calendar => 'Dates you both choose',
      };
}

enum TouchState { notAsked, waitingForThem, waitingForHer, ready, ended }

/// Staying in touch, by choice on BOTH sides, channel by channel. She offers; each grown-up asks; only the overlap
/// is live. Either side ends it with one tap and no reason.
class StayInTouch {
  const StayInTouch({
    this.offered = const <Channel>{}, this.wanted = const <String, Set<Channel>>{}, this.ended = const <String>{},
  });
  final Set<Channel> offered;

  /// grown-up id -> the channels that grown-up asked for.
  final Map<String, Set<Channel>> wanted;

  /// Grown-ups whose channel she ended, and grown-ups who ended it: either way it is over for that grown-up.
  final Set<String> ended;

  /// The channels live with [guardianId]: offered by her AND asked by them. Empty once ended.
  Set<Channel> liveWith(String guardianId) =>
      ended.contains(guardianId) ? const <Channel>{} : offered.intersection(wanted[guardianId] ?? const <Channel>{});

  TouchState stateWith(String guardianId) {
    if (ended.contains(guardianId)) return TouchState.ended;
    final Set<Channel> want = wanted[guardianId] ?? const <Channel>{};
    if (liveWith(guardianId).isNotEmpty) return TouchState.ready;
    if (want.isEmpty && offered.isEmpty) return TouchState.notAsked;
    if (offered.isEmpty) return TouchState.waitingForHer;
    return want.isEmpty ? TouchState.waitingForThem : TouchState.waitingForHer;
  }

  StayInTouch offer(Channel c, bool on) {
    final Set<Channel> o = <Channel>{...offered};
    on ? o.add(c) : o.remove(c);
    return StayInTouch(offered: o, wanted: wanted, ended: ended);
  }

  StayInTouch want(String guardianId, Set<Channel> channels) => StayInTouch(
        offered: offered, wanted: <String, Set<Channel>>{...wanted, guardianId: <Channel>{...channels}},
        ended: <String>{...ended}..remove(guardianId));

  /// One tap, either side, no reason asked.
  StayInTouch end(String guardianId) =>
      StayInTouch(offered: offered, wanted: wanted, ended: <String>{...ended, guardianId});

  Map<String, Object?> toJson() => <String, Object?>{
        'offered': <Object?>[for (final Channel c in offered) c.name],
        'wanted': <String, Object?>{
          for (final MapEntry<String, Set<Channel>> e in wanted.entries) e.key: <Object?>[for (final Channel c in e.value) c.name],
        },
        'ended': (ended.toList()..sort()),
      };

  static StayInTouch fromJson(Object? j) {
    if (j is! Map) return const StayInTouch();
    Set<Channel> chans(Object? v) => <Channel>{
          if (v is List)
            for (final Object? n in v)
              if (Channel.values.where((Channel c) => c.name == n).firstOrNull != null)
                Channel.values.firstWhere((Channel c) => c.name == n),
        };
    final Object? w = j['wanted'];
    return StayInTouch(
      offered: chans(j['offered']),
      wanted: <String, Set<Channel>>{if (w is Map) for (final MapEntry<dynamic, dynamic> e in w.entries) if (e.key is String) e.key as String: chans(e.value)},
      ended: <String>{if (j['ended'] is List) for (final Object? x in j['ended'] as List<Object?>) if (x is String) x},
    );
  }
}

/// A note a grown-up wrote for the day she is 18, cut to [kHandoverNoteMax]. Null when empty.
String? cleanHandoverNote(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return null;
  return t.length > kHandoverNoteMax ? t.substring(0, kHandoverNoteMax).trimRight() : t;
}
