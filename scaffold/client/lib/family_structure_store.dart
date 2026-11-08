// OLIVE BRANCH — Family structure storage seam and service (suites J and K).
// No longer UNVERIFIED — verified by CI (client/test/family_structure_store_test.dart).
//
// LOCAL-FIRST. Nothing here touches a network. The screens depend on [FamilyService],
// which depends on the narrow [FamilyStore] interface below; [MemoryFamilyStore] is the
// real in-process implementation (tests, the demo, and the app until a durable store
// exists). A durable on-device store (client/lib's LocalStore, being built separately)
// is swapped in later by implementing [FamilyStore] over it: the WHOLE seam is two
// methods, load() and save(), over one JSON-serialisable [FamilySnapshot].
//
// "Release to the child" means the structure becomes visible on THIS device's child
// shell. Guardian and child may share one device or be paired later; syncing the
// structure between devices comes later. Until then a change a guardian makes here is
// not on any other device, and the UI says so.
//
// The rules live HERE as well as in the UI (the same construction as parent_learn_store):
//  - every write needs a guardian principal (F1); the child principal can only read
//    her own released view (F2), derived by the pure core, never the raw structure;
//  - history is append-only: there is no edit and no delete method; an undo is a new
//    entry (and a release is a new entry);
//  - a story is guardian-authored text, bounded by validateStory (F7); this file has
//    no way to generate one.
import 'family_structure_logic.dart';

class FamilyStoreRefused implements Exception {
  const FamilyStoreRefused(this.reason);
  final String reason;
  @override
  String toString() => 'FamilyStoreRefused($reason)';
}

/// One row of the append-only history, with what the history screen needs.
class FamilyRecord {
  const FamilyRecord({
    required this.entry, required this.actorName, required this.createdOn,
    this.story, this.toldOn, this.undoes,
  });
  final HistoryEntry entry;
  final String actorName;
  /// Local date the row was written (yyyy-mm-dd).
  final String createdOn;
  /// Guardian-authored pages ({pages:[...]}) that travel with a change.
  final Map<String, Object?>? story;
  /// The date a guardian recorded telling her (a release), or the day it took effect.
  final String? toldOn;
  /// An undo says which change it puts back (the original stays).
  final String? undoes;

  Map<String, Object?> toJson() => <String, Object?>{
        'entry': entry.toJson(), 'actorName': actorName, 'createdOn': createdOn,
        'story': story, 'toldOn': toldOn, 'undoes': undoes,
      };

  static FamilyRecord fromJson(Map<String, Object?> j) => FamilyRecord(
        entry: HistoryEntry.fromJson((j['entry']! as Map).cast<String, Object?>()),
        actorName: j['actorName']! as String, createdOn: j['createdOn']! as String,
        story: (j['story'] as Map?)?.cast<String, Object?>(), toldOn: j['toldOn'] as String?,
        undoes: j['undoes'] as String?,
      );
}

/// Everything persisted for one child. JSON in, JSON out: this is the whole storage contract.
class FamilySnapshot {
  const FamilySnapshot({this.records = const <FamilyRecord>[], this.baselineBand, this.birthDate, this.nextSeq = 1});
  final List<FamilyRecord> records;
  /// Her natural band the first time anything touched this child. Set ONCE, so a birthday
  /// cannot move her until a guardian releases it ("hold until I've told her").
  final String? baselineBand;
  /// yyyy-mm-dd, entered by a guardian on this device; null = unknown (no birthday features).
  final String? birthDate;
  final int nextSeq;

  FamilySnapshot copyWith({List<FamilyRecord>? records, String? baselineBand, String? birthDate, int? nextSeq,
          bool clearBirthDate = false}) =>
      FamilySnapshot(
        records: records ?? this.records, baselineBand: baselineBand ?? this.baselineBand,
        birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate), nextSeq: nextSeq ?? this.nextSeq);

  Map<String, Object?> toJson() => <String, Object?>{
        'records': <Object?>[for (final FamilyRecord r in records) r.toJson()],
        'baselineBand': baselineBand, 'birthDate': birthDate, 'nextSeq': nextSeq,
      };

  static FamilySnapshot fromJson(Map<String, Object?> j) => FamilySnapshot(
        records: <FamilyRecord>[
          for (final Object? r in (j['records'] as List? ?? const <Object?>[])) FamilyRecord.fromJson((r! as Map).cast<String, Object?>())
        ],
        baselineBand: j['baselineBand'] as String?, birthDate: j['birthDate'] as String?,
        nextSeq: (j['nextSeq'] as num?)?.toInt() ?? 1,
      );
}

/// THE seam. Implement over a durable key-value store by JSON-encoding the snapshot.
abstract class FamilyStore {
  Future<FamilySnapshot> load();
  Future<void> save(FamilySnapshot s);
}

class MemoryFamilyStore implements FamilyStore {
  MemoryFamilyStore([FamilySnapshot? initial]) : _json = initial?.toJson();
  // Held as JSON so a snapshot handed out can never alias the stored one, and so a swap
  // to a durable store changes nothing about what a snapshot can hold.
  Map<String, Object?>? _json;
  @override
  Future<FamilySnapshot> load() async => _json == null ? const FamilySnapshot() : FamilySnapshot.fromJson(_json!);
  @override
  Future<void> save(FamilySnapshot s) async => _json = s.toJson();
}

/// A write's outcome: the new change id and where it stands, or the refusal reason.
class FamilyWrite {
  const FamilyWrite.ok(String this.id, String this.state) : reason = null;
  const FamilyWrite.no(String this.reason) : id = null, state = null;
  final String? id;
  /// applied | held | scheduled
  final String? state;
  final String? reason;
  bool get ok => id != null;
}

class HistoryRow {
  const HistoryRow({required this.record, required this.state});
  final FamilyRecord record;
  /// applied | held | scheduled | told (a release row)
  final String state;
  HistoryEntry get entry => record.entry;
}

class FamilyOverview {
  const FamilyOverview({
    required this.released, required this.intended, required this.history, required this.pending,
    required this.naturalBand, required this.effectiveBand, required this.rungs, required this.birthDate,
    required this.birthday, required this.rhythmLocked, required this.yearsOld,
  });
  final FamilyStructure released;
  final FamilyStructure intended;
  /// Newest first.
  final List<HistoryRow> history;
  final List<String> pending;
  final String naturalBand;
  final String effectiveBand;
  final List<String> rungs;
  final String? birthDate;
  final BirthdayInfo? birthday;
  final bool rhythmLocked;
  final int yearsOld;

  bool get bandHeld => effectiveBand != naturalBand;
  Map<String, Object?>? get birthdayPreview => birthday == null
      ? null
      : birthdayPreviewOf(birthday!, released.holdBandChange, released.releasedBand);
}

/// What the child shell is given: her derived view (no role words), the quiet birthday
/// facts if a guardian left them on, and a recent released story.
class FamilyChildSnapshot {
  const FamilyChildSnapshot({required this.view, this.birthday, this.story, this.heroName});
  /// The label of the person the youngest band's big call tile is for (a name a guardian chose).
  final String? heroName;
  final ChildView view;
  final ChildBirthday? birthday;
  final ChildStory? story;
}

class ChildBirthday {
  const ChildBirthday({required this.sleepsUntil, required this.turnsYears, required this.monthDay, required this.lineShown});
  final int sleepsUntil;
  final int turnsYears;
  /// 'MM-DD'
  final String monthDay;
  final bool lineShown;
}

class ChildStory {
  const ChildStory({required this.from, required this.pages, required this.releasedOn});
  final String from;
  final List<String> pages;
  final String releasedOn;
}

Map<String, Object?> birthdayPreviewOf(BirthdayInfo b, bool hold, String? released) => birthdayPreview(b, hold, released);

/// yyyy-mm-dd of a local DateTime.
String localIsoDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

class FamilyService {
  FamilyService(this.store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final FamilyStore store;
  final DateTime Function() _clock;
  int _ids = 0;

  String today() => localIsoDate(_clock());

  /// A new id for a person, a home or a change. Local-only, unique within this process
  /// and, via the clock, across runs.
  String newId(String prefix) => '$prefix${_clock().microsecondsSinceEpoch}_${_ids++}';

  void _guardian(FamilyPrincipal? p) {
    if (!canEditStructure(p)) throw const FamilyStoreRefused('guardian_only');
  }

  String _natural(FamilySnapshot s, int yearsOld, String today) {
    final BirthdayInfo? info = birthdayInfo(s.birthDate, today);
    return info != null ? info.bandNow : bandForYears(yearsOld);
  }

  FamilyStructure _base(FamilySnapshot s) => FamilyStructure(releasedBand: s.baselineBand);

  List<HistoryEntry> _entries(FamilySnapshot s) => <HistoryEntry>[for (final FamilyRecord r in s.records) r.entry];

  Future<FamilySnapshot> _ensureBaseline(FamilySnapshot s, int yearsOld, String today) async {
    if (s.baselineBand != null) return s;
    final FamilySnapshot n = s.copyWith(baselineBand: _natural(s, yearsOld, today));
    await store.save(n);
    return n;
  }

  FamilyStructure _withOrder(FamilyStructure s, Rhythm? order) =>
      order == null ? s : s.copyWith(rhythm: Rhythm(
          pattern: order.pattern, exchangeDay: order.exchangeDay, exchangeTime: order.exchangeTime, source: 'court_order'));

  /// The guardian's whole picture. [order] is a court-ordered rhythm, when one is known: shown locked.
  Future<FamilyOverview> overview(FamilyPrincipal? principal, {required int yearsOld, Rhythm? order}) async {
    _guardian(principal);
    final String t = today();
    final FamilySnapshot s = await _ensureBaseline(await store.load(), yearsOld, t);
    final List<HistoryEntry> entries = _entries(s);
    final FamilyStructure base = _base(s);
    final FamilyStructure released = _withOrder(foldReleased(base, entries, t), order);
    final FamilyStructure intended = _withOrder(foldIntended(base, entries), order);
    final Set<String> ids = releasedIds(entries, t);
    final Set<String> releasedByRow = <String>{for (final HistoryEntry e in entries) if (e.entry == 'release') e.ref!};
    final List<HistoryRow> history = <HistoryRow>[
      for (final FamilyRecord r in s.records.reversed)
        HistoryRow(record: r, state: _stateOf(r.entry, ids, releasedByRow)),
    ];
    final String natural = _natural(s, yearsOld, t);
    final BirthdayInfo? info = birthdayInfo(s.birthDate, t);
    return FamilyOverview(
      released: released, intended: intended, history: history,
      pending: <String>[for (final HistoryEntry e in pendingChanges(entries, t)) e.id],
      naturalBand: natural,
      effectiveBand: effectiveBand(natural, released.holdBandChange, released.releasedBand),
      rungs: rungsAt(info?.yearsOld ?? yearsOld), birthDate: s.birthDate, birthday: info,
      rhythmLocked: released.rhythm.source == 'court_order', yearsOld: info?.yearsOld ?? yearsOld,
    );
  }

  String _stateOf(HistoryEntry e, Set<String> released, Set<String> releasedByRow) {
    if (e.entry == 'release') return 'told';
    final Timing t = e.timing!;
    if (t.kind == 'now') return 'applied';
    if (t.kind == 'date') return released.contains(e.id) ? 'applied' : 'scheduled';
    return releasedByRow.contains(e.id) ? 'told' : 'held';
  }

  /// Record a guardian's birth-date entry for her (local only; null clears it).
  Future<bool> setBirthDate(FamilyPrincipal? principal, String? birthDate, {required int yearsOld}) async {
    _guardian(principal);
    if (birthDate != null && birthdayInfo(birthDate, today()) == null) return false;
    FamilySnapshot s = await store.load();
    s = birthDate == null ? s.copyWith(clearBirthDate: true) : s.copyWith(birthDate: birthDate);
    await store.save(s);
    return true;
  }

  Future<FamilyWrite> _append(FamilyPrincipal? principal, String actorName, int yearsOld, Rhythm? order,
      Object? op, Object? timingRaw, Object? story, String? undoes) async {
    _guardian(principal);
    final String t = today();
    FamilySnapshot s = await _ensureBaseline(await store.load(), yearsOld, t);
    final FamilyStructure intended = _withOrder(foldIntended(_base(s), _entries(s)), order);
    final TimingResult v = validateChange(intended, op, timingRaw, t);
    if (!v.ok) return FamilyWrite.no(v.reason!);
    if (story != null) {
      final Verdict sv = validateStory(story);
      if (!sv.ok) return FamilyWrite.no(sv.reason!);
    }
    final Map<String, Object?> full = withBefore(intended, (op! as Map).cast<String, Object?>());
    final Timing timing = v.timing!;
    final String id = 'c${s.nextSeq}';
    final FamilyRecord rec = FamilyRecord(
      entry: HistoryEntry.change(id: id, seq: s.nextSeq, op: full, timing: timing),
      actorName: actorName, createdOn: t,
      story: (story as Map?)?.cast<String, Object?>(),
      toldOn: timing.kind == 'now' ? t : timing.kind == 'date' ? timing.on : null, undoes: undoes,
    );
    s = s.copyWith(records: <FamilyRecord>[...s.records, rec], nextSeq: s.nextSeq + 1);
    await store.save(s);
    return FamilyWrite.ok(id, timing.kind == 'now' ? 'applied' : timing.kind == 'hold' ? 'held' : 'scheduled');
  }

  /// Add one change. [timing] is {kind: now|hold|date, on?}.
  Future<FamilyWrite> addChange(FamilyPrincipal? principal,
          {required String actorName, required int yearsOld, required Map<String, Object?> op,
          required Map<String, Object?> timing, Map<String, Object?>? story, Rhythm? order}) =>
      _append(principal, actorName, yearsOld, order, op, timing, story, null);

  /// "I have told her": a NEW row; the held change then reaches her on this device.
  Future<FamilyWrite> release(FamilyPrincipal? principal,
      {required String actorName, required int yearsOld, required String changeId, String? toldOn}) async {
    _guardian(principal);
    final String t = today();
    FamilySnapshot s = await _ensureBaseline(await store.load(), yearsOld, t);
    final String told = toldOn ?? t;
    if (!isIsoDate(told) || told.compareTo(t) > 0 || daysBetween(told, t) > 365) return const FamilyWrite.no('bad_date');
    HistoryEntry? ch;
    for (final FamilyRecord r in s.records) {
      if (r.entry.id == changeId) ch = r.entry;
    }
    if (ch == null || ch.entry != 'change') return const FamilyWrite.no('unknown_change');
    if (ch.timing!.kind != 'hold') return const FamilyWrite.no('not_held');
    if (s.records.any((FamilyRecord r) => r.entry.entry == 'release' && r.entry.ref == changeId)) {
      return const FamilyWrite.no('already_released');
    }
    final String id = 'c${s.nextSeq}';
    s = s.copyWith(records: <FamilyRecord>[
      ...s.records,
      FamilyRecord(entry: HistoryEntry.release(id: id, seq: s.nextSeq, ref: changeId), actorName: actorName, createdOn: t, toldOn: told),
    ], nextSeq: s.nextSeq + 1);
    await store.save(s);
    return FamilyWrite.ok(id, 'told');
  }

  /// An undo is a NEW change that puts it back; the original stays in the history.
  Future<FamilyWrite> undo(FamilyPrincipal? principal,
      {required String actorName, required int yearsOld, required String changeId, Map<String, Object?>? timing, Rhythm? order}) async {
    _guardian(principal);
    final String t = today();
    final FamilySnapshot s = await _ensureBaseline(await store.load(), yearsOld, t);
    HistoryEntry? ch;
    for (final FamilyRecord r in s.records) {
      if (r.entry.id == changeId) ch = r.entry;
    }
    if (ch == null || ch.entry != 'change') return const FamilyWrite.no('unknown_change');
    if (s.records.any((FamilyRecord r) => r.undoes == changeId)) return const FamilyWrite.no('already_undone');
    final FamilyStructure intended = _withOrder(foldIntended(_base(s), _entries(s)), order);
    final Map<String, Object?> inv = invertOp(ch.op!, intended);
    final bool reached = releasedIds(_entries(s), t).contains(changeId);
    // Undoing something that never reached her must not announce anything to her: now.
    final Map<String, Object?> tm = timing ?? (reached ? defaultTiming(inv).toJson() : Timing.now.toJson());
    return _append(principal, actorName, yearsOld, order, inv, tm, null, changeId);
  }

  /// The child's own read: only what has been released to her on this device.
  Future<FamilyChildSnapshot> childSnapshot(FamilyPrincipal? principal, {required String childId, required int yearsOld}) async {
    if (!canReadReleased(principal, childId)) throw const FamilyStoreRefused('child_only');
    final String t = today();
    final FamilySnapshot s = await _ensureBaseline(await store.load(), yearsOld, t);
    final List<HistoryEntry> entries = _entries(s);
    final FamilyStructure released = foldReleased(_base(s), entries, t);
    final BirthdayInfo? info = birthdayInfo(s.birthDate, t);
    final String natural = _natural(s, yearsOld, t);
    final String band = effectiveBand(natural, released.holdBandChange, released.releasedBand);
    final ChildView view = deriveChildView(released, band, null, rungsAt(info?.yearsOld ?? yearsOld), today: t);

    ChildBirthday? birthday;
    if (view.birthdayVisible && info != null) {
      birthday = ChildBirthday(
          sleepsUntil: info.sleepsUntil, turnsYears: info.turnsYears, monthDay: info.nextOn.substring(5),
          lineShown: birthdayLineShown(info.sleepsUntil, true));
    }

    // The latest released story within a fortnight of the day she was told.
    final Set<String> ids = releasedIds(entries, t);
    final Map<String, String?> releaseDay = <String, String?>{
      for (final FamilyRecord r in s.records) if (r.entry.entry == 'release') r.entry.ref!: r.toldOn
    };
    ChildStory? story;
    int bestSeq = -1;
    for (final FamilyRecord r in s.records) {
      final HistoryEntry e = r.entry;
      if (e.entry != 'change' || !ids.contains(e.id) || r.story == null) continue;
      final String? day = e.timing!.kind == 'hold' ? releaseDay[e.id] : e.timing!.kind == 'date' ? e.timing!.on : r.toldOn;
      if (day == null) continue;
      final int ago = daysBetween(day, t);
      if (ago < 0 || ago > storyShownDays || e.seq <= bestSeq) continue;
      bestSeq = e.seq;
      story = ChildStory(
          from: r.actorName, pages: <String>[for (final Object? p in (r.story!['pages']! as List)) p! as String], releasedOn: day);
    }
    String? heroName;
    for (final Person p in released.people) {
      if (p.id == view.heroPersonId) heroName = p.label.trim();
    }
    return FamilyChildSnapshot(view: view, birthday: birthday, story: story, heroName: heroName);
  }
}

/// The one in-process service the guardian and child shells share on this device until a
/// durable store is wired in. Swap [localFamilyService]'s store; nothing else changes.
final FamilyService localFamilyService = FamilyService(MemoryFamilyStore());
