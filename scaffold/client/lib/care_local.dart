// OLIVE BRANCH — Care and coordination on THIS device: medicines and their dose log,
// shared expenses, and the handover log. No longer UNVERIFIED — verified by CI
// (client/test/care_local_test.dart). MASTERFILE section 8.24.7.
//
// WHY. The server-backed half of these (two guardians seeing one list) is parked until a
// family is connected. Until then a grown-up still needs the screens to WORK: a medicine
// list with a dose log, a record of what was paid for, a log of notes. This file is the
// on-device half: one sealed document per child ('coordination', encrypted, guardian-only),
// the rules of each record held HERE and not left to screens, and nothing the app writes
// itself. Every word is a guardian's. The app adds no medical text, no dosing advice and no
// amounts of its own.
//
// RULES, held here:
//  - GUARDIAN ONLY. Every call takes the principal; a child (or no) principal is refused with
//    'guardian_only' for reads and writes alike (P6 for expenses; she never sees any of it).
//  - MEDICINES. A dose can only be logged once per slot (scheduled) or once per gap (as
//    needed). A second attempt is refused with who gave it and when and the next allowed
//    time; there is no override. The dose log is append-only: it is never edited or
//    deleted, and retiring a medicine keeps its log. A full box refuses the write.
//  - EXPENSES (mirrors the server's resolveExpense, PR #174). proposed -> accepted|disputed,
//    disputed -> accepted, accepted -> reimbursed, nothing else. The grown-up who proposed
//    cannot dispute their own, and cannot accept their own EXCEPT a sole guardian, whose
//    self-accept is recorded as such. A dispute needs a short reason. Every change is an
//    append-only event (who, when). Money never moves: this is a record.
//  - HANDOVER LOG. Append-only and hash-chained with the SAME framing the server and the
//    court export use (court_export.dart's computeEntryHash, hash version 1), so a chain
//    written here verifies in the court export unchanged. 1000 characters at most. A mistake
//    is explained by a correction, which is a new note. No edit and no delete exist.
//  - BOUNDED. Counts and lengths are capped; text has control characters stripped.
import 'dart:convert';

import 'court_export.dart' show LogEntry, appendEntry, verifyChain, ChainFault;
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'local_services.dart';
import 'local_store.dart';

// ================================================================== limits ===
const int careMaxMedicines = 30;
const int careMaxNameChars = 60;
const int careMaxDoseChars = 60;
const int careMaxNoteChars = 200;
const int careMaxSlots = 6;
const int careMaxGapHours = 24;
const int careMaxExpenses = 500;
const int careMaxExpenseTitleChars = 80;
const int careMaxExpenseCents = 1000000;
const int careMaxReasonChars = 200;
const int careHandoverMaxChars = 1000;
const int careMaxHandoverNotes = 2000;

/// Dose due window: a slot stays "due" for this long after its time.
const Duration careDueWindow = Duration(hours: 8);

/// A dose logged this early before its slot still counts for that slot.
const Duration careEarlyGrace = Duration(minutes: 30);

const String careUnnamedGuardian = 'A guardian';

final RegExp _ctrl = RegExp('[\u0000-\u001f\u007f]');
String _t(Object? v) => v is String ? v.replaceAll(_ctrl, ' ').trim() : '';
final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Why a call was refused: a short stable code a screen words gently.
class CareResult<T> {
  const CareResult.ok([this.value]) : ok = true, reason = '', detail = null;
  const CareResult.no(this.reason, {this.detail}) : ok = false, value = null;
  final bool ok;
  final String reason;
  final T? value;

  /// Extra facts for a refusal (for example who gave a dose, and when).
  final Map<String, Object?>? detail;
  @override
  String toString() => ok ? 'CareResult.ok($value)' : 'CareResult.no($reason)';
}

String careRefusalText(String reason) => switch (reason) {
  'guardian_only' => 'Only a grown-up can use this.',
  'name_needed' => 'A name is needed.',
  'slot_needed' => 'Add at least one time.',
  'bad_time' => 'That time is not valid.',
  'too_long' => 'One of those is longer than fits here. Please shorten it.',
  'too_many' => 'There is no room for more here.',
  'not_found' => 'That could not be found.',
  'retired' => 'This medicine was retired. Its log stays.',
  'description_needed' => 'Say what it was for.',
  'bad_amount' => 'That amount looks wrong.',
  'reason_needed' => 'Say briefly why.',
  'own_expense' => 'You cannot answer your own expense.',
  'invalid_transition' => 'That is already settled.',
  'text_needed' => 'Write something first.',
  'full' => "This device's box for these records is full.",
  'not_saved' => 'That did not save. Please try again.',
  _ => 'That could not be saved.',
};

// ============================================================== medicines ===
enum MedKind { scheduled, prn }

class CareDose {
  const CareDose({required this.at, required this.byId, required this.byName});

  /// UTC instant, millisecond precision.
  final DateTime at;
  final String byId;
  final String byName;
  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
  };
  static CareDose? tryFromJson(Object? j) {
    if (j is! Map || j['at'] is! String) return null;
    final DateTime? t = DateTime.tryParse(j['at']! as String);
    if (t == null) return null;
    return CareDose(
      at: t.toUtc(),
      byId: _t(j['byId']),
      byName: _t(j['byName']).isEmpty ? careUnnamedGuardian : _t(j['byName']),
    );
  }
}

class CareMedication {
  const CareMedication({
    required this.id,
    required this.name,
    this.dose = '',
    this.kind = MedKind.scheduled,
    this.slots = const <String>[],
    this.gapHours = 4,
    this.note = '',
    this.retired = false,
    this.doses = const <CareDose>[],
  });
  final String id;
  final String name;
  final String dose;
  final MedKind kind;

  /// "HH:mm" times of day (scheduled only).
  final List<String> slots;

  /// Hours between doses (as needed only).
  final int gapHours;
  final String note;
  final bool retired;
  final List<CareDose> doses;

  CareMedication copyWith({
    String? name,
    String? dose,
    List<String>? slots,
    int? gapHours,
    String? note,
    bool? retired,
    List<CareDose>? doses,
  }) => CareMedication(
    id: id,
    name: name ?? this.name,
    dose: dose ?? this.dose,
    kind: kind,
    slots: slots ?? this.slots,
    gapHours: gapHours ?? this.gapHours,
    note: note ?? this.note,
    retired: retired ?? this.retired,
    doses: doses ?? this.doses,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'dose': dose,
    'kind': kind.name,
    'slots': slots,
    'gap': gapHours,
    'note': note,
    'retired': retired,
    'doses': <Object?>[for (final CareDose d in doses) d.toJson()],
  };

  static CareMedication? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String id = _t(j['id']), name = _t(j['name']);
    if (id.isEmpty || name.isEmpty) return null;
    final Object? g = j['gap'];
    return CareMedication(
      id: id,
      name: name,
      dose: _t(j['dose']),
      kind: j['kind'] == 'prn' ? MedKind.prn : MedKind.scheduled,
      slots: <String>[
        if (j['slots'] is List)
          for (final Object? s in (j['slots']! as List).take(careMaxSlots))
            if (s is String && _hhmm.hasMatch(s)) s,
      ],
      gapHours: g is int && g >= 1 && g <= careMaxGapHours ? g : 4,
      note: _t(j['note']),
      retired: j['retired'] == true,
      doses: <CareDose>[
        if (j['doses'] is List)
          for (final Object? d in j['doses']! as List) ?CareDose.tryFromJson(d),
      ],
    );
  }
}

/// What a medicine looks like right now. Pure: [now] is the phone's local time.
class MedState {
  const MedState({this.slot, this.given = false, this.due = false, this.next, this.last});

  /// The scheduled slot this state is about (latest one at or before now).
  final DateTime? slot;

  /// Already given for this slot (scheduled) or still inside the gap (as needed).
  final bool given;
  final bool due;

  /// The next time a dose is allowed or due.
  final DateTime? next;

  /// The dose that makes [given] true (scheduled), or the last dose (as needed).
  final CareDose? last;
}

List<DateTime> _slotsAround(CareMedication m, DateTime now) {
  final List<DateTime> out = <DateTime>[];
  for (final int dd in <int>[-1, 0, 1]) {
    for (final String hm in m.slots) {
      final int h = int.parse(hm.substring(0, 2)), mi = int.parse(hm.substring(3));
      out.add(DateTime(now.year, now.month, now.day + dd, h, mi));
    }
  }
  out.sort();
  return out;
}

MedState medState(CareMedication m, DateTime now) {
  if (m.kind == MedKind.prn) {
    final CareDose? last = m.doses.isEmpty ? null : m.doses.last;
    final DateTime? next = last?.at.toLocal().add(Duration(hours: m.gapHours));
    return MedState(last: last, next: next, given: next != null && now.isBefore(next));
  }
  final List<DateTime> all = _slotsAround(m, now);
  final List<DateTime> past = all.where((DateTime s) => !s.isAfter(now)).toList();
  final DateTime? slot = past.isEmpty ? null : past.last;
  CareDose? dose;
  if (slot != null) {
    for (final CareDose d in m.doses) {
      if (!d.at.toLocal().isBefore(slot.subtract(careEarlyGrace))) {
        dose = d;
        break;
      }
    }
  }
  DateTime? next;
  for (final DateTime s in all) {
    if (s.isAfter(now)) {
      next = s;
      break;
    }
  }
  return MedState(
    slot: slot,
    given: dose != null,
    last: dose,
    due: slot != null && dose == null && now.difference(slot) < careDueWindow,
    next: next,
  );
}

// ============================================================== expenses ====
enum ExpenseStatus { proposed, accepted, disputed, reimbursed }

enum ExpenseAction { accept, dispute, reimburse }

class ExpenseEvent {
  const ExpenseEvent({
    required this.seq,
    required this.from,
    required this.to,
    required this.at,
    required this.byId,
    required this.byName,
    this.selfAccept = false,
  });
  final int seq;

  /// Null for the proposal itself.
  final ExpenseStatus? from;
  final ExpenseStatus to;
  final DateTime at;
  final String byId;
  final String byName;

  /// True only on a sole guardian accepting their own proposal.
  final bool selfAccept;

  Map<String, Object?> toJson() => <String, Object?>{
    'seq': seq,
    if (from != null) 'from': from!.name,
    'to': to.name,
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
    if (selfAccept) 'selfAccept': true,
  };
  static ExpenseStatus? _st(Object? v) {
    for (final ExpenseStatus s in ExpenseStatus.values) {
      if (s.name == v) return s;
    }
    return null;
  }

  static ExpenseEvent? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? seq = j['seq'];
    final ExpenseStatus? to = _st(j['to']);
    final DateTime? at = j['at'] is String ? DateTime.tryParse(j['at']! as String) : null;
    if (seq is! int || to == null || at == null) return null;
    return ExpenseEvent(
      seq: seq,
      from: _st(j['from']),
      to: to,
      at: at.toUtc(),
      byId: _t(j['byId']),
      byName: _t(j['byName']).isEmpty ? careUnnamedGuardian : _t(j['byName']),
      selfAccept: j['selfAccept'] == true,
    );
  }
}

class CareExpense {
  const CareExpense({
    required this.id,
    required this.description,
    required this.cents,
    required this.paidById,
    required this.paidByName,
    required this.createdAt,
    this.sharePercent = 50,
    this.status = ExpenseStatus.proposed,
    this.reason = '',
    this.events = const <ExpenseEvent>[],
  });
  final String id;
  final String description;
  final int cents;
  final String paidById;
  final String paidByName;
  final DateTime createdAt;

  /// What the payer keeps; the rest is owed back to them. The app only ever proposes 50.
  final int sharePercent;
  final ExpenseStatus status;
  final String reason;
  final List<ExpenseEvent> events;

  int get owedToPayerCents => (cents * (100 - sharePercent) / 100).round();

  CareExpense withStatus(ExpenseStatus s, ExpenseEvent e, {String? reason}) => CareExpense(
    id: id,
    description: description,
    cents: cents,
    paidById: paidById,
    paidByName: paidByName,
    createdAt: createdAt,
    sharePercent: sharePercent,
    status: s,
    reason: reason ?? this.reason,
    events: <ExpenseEvent>[...events, e],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'description': description,
    'cents': cents,
    'paidById': paidById,
    'paidByName': paidByName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'share': sharePercent,
    'status': status.name,
    if (reason.isNotEmpty) 'reason': reason,
    'events': <Object?>[for (final ExpenseEvent e in events) e.toJson()],
  };

  static CareExpense? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String id = _t(j['id']), d = _t(j['description']);
    final Object? c = j['cents'];
    final DateTime? at = j['createdAt'] is String ? DateTime.tryParse(j['createdAt']! as String) : null;
    final ExpenseStatus? st = ExpenseEvent._st(j['status']);
    if (id.isEmpty || d.isEmpty || c is! int || c <= 0 || at == null || st == null) return null;
    final Object? sh = j['share'];
    return CareExpense(
      id: id,
      description: d,
      cents: c,
      paidById: _t(j['paidById']),
      paidByName: _t(j['paidByName']).isEmpty ? careUnnamedGuardian : _t(j['paidByName']),
      createdAt: at.toUtc(),
      sharePercent: sh is int && sh >= 0 && sh <= 100 ? sh : 50,
      status: st,
      reason: _t(j['reason']),
      events: <ExpenseEvent>[
        if (j['events'] is List)
          for (final Object? e in j['events']! as List) ?ExpenseEvent.tryFromJson(e),
      ],
    );
  }
}

/// The refusal for [action] on [e] by [actorId], or null when it is allowed. [guardianCount] is how many
/// guardians the family has: a SOLE guardian may accept their own proposal. This is the same table as the
/// server's resolveExpense; the screens never decide it themselves.
String? expenseRefusal(CareExpense e, ExpenseAction action, String actorId, int guardianCount, {String reason = ''}) {
  final bool own = e.paidById == actorId;
  switch (action) {
    case ExpenseAction.accept:
      if (e.status != ExpenseStatus.proposed && e.status != ExpenseStatus.disputed) return 'invalid_transition';
      if (own && guardianCount != 1) return 'own_expense';
      return null;
    case ExpenseAction.dispute:
      if (e.status != ExpenseStatus.proposed) return 'invalid_transition';
      if (own) return 'own_expense';
      if (_t(reason).isEmpty) return 'reason_needed';
      if (_t(reason).length > careMaxReasonChars) return 'too_long';
      return null;
    case ExpenseAction.reimburse:
      return e.status == ExpenseStatus.accepted ? null : 'invalid_transition';
  }
}

/// Accepted but not yet reimbursed, from [me]'s point of view: positive means the other side owes me. With
/// a sole guardian nobody else is in the family, so the figure is only a total of what is recorded.
({int owedToMe, int recordedTotal}) expenseBalance(List<CareExpense> all, String me) {
  int owed = 0, total = 0;
  for (final CareExpense e in all) {
    if (e.status != ExpenseStatus.accepted) continue;
    total += e.cents;
    owed += e.paidById == me ? e.owedToPayerCents : -e.owedToPayerCents;
  }
  return (owedToMe: owed, recordedTotal: total);
}

/// "12.50" -> 1250. Null when it is not a positive amount with at most two decimals.
int? parseCents(String raw) {
  final String s = raw.trim().replaceAll(',', '');
  final RegExpMatch? m = RegExp(r'^\$?(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final int whole = int.parse(m.group(1)!);
  final String frac = (m.group(2) ?? '').padRight(2, '0');
  final int c = whole * 100 + (frac.isEmpty ? 0 : int.parse(frac));
  return c > 0 ? c : null;
}

String formatCents(int c) => '\$${(c ~/ 100)}.${(c % 100).toString().padLeft(2, '0')}';

// =========================================================== handover log ===
/// The reference to a note's number the way a person reads it (the chain's seq starts at 0).
int noteNumber(LogEntry e) => e.seq + 1;

class HandoverNoteView {
  const HandoverNoteView({required this.entry, required this.byName});
  final LogEntry entry;
  final String byName;
  int get number => noteNumber(entry);
  String get text => entry.body;
  String get byId => entry.authorId;
  DateTime get at => DateTime.parse(entry.at);
  String get hash => entry.hash;
  String get prevHash => entry.prevHash;
}

class ChainStatus {
  const ChainStatus({required this.intact, required this.count, this.brokenAtNumber});
  final bool intact;
  final int count;

  /// The first note (as a person counts) the chain stops agreeing at.
  final int? brokenAtNumber;
}

ChainStatus chainStatus(List<LogEntry> chain) {
  final v = verifyChain(chain);
  if (v.ok) return ChainStatus(intact: true, count: chain.length);
  final List<int> seqs = <int>[
    for (final ChainFault f in v.faults)
      if (f.seq != null) f.seq!,
  ];
  seqs.sort();
  return ChainStatus(intact: false, count: chain.length, brokenAtNumber: (seqs.isEmpty ? 0 : seqs.first) + 1);
}

/// Text that starts a correction to note [n].
String correctionStarter(int n) => 'Correction to note #$n: ';

// ================================================================ document ===
/// The whole stored document (one atomic write).
class CareDoc {
  const CareDoc({
    this.meds = const <CareMedication>[],
    this.expenses = const <CareExpense>[],
    this.notes = const <LogEntry>[],
    this.noteAuthors = const <int, String>{},
    this.names = const <String, String>{},
    this.seq = 0,
  });
  final List<CareMedication> meds;
  final List<CareExpense> expenses;
  final List<LogEntry> notes;

  /// Display name of each note's author, by seq (the chain itself only carries the id).
  final Map<int, String> noteAuthors;
  final Map<String, String> names;

  /// Counter for ids.
  final int seq;

  CareDoc copyWith({
    List<CareMedication>? meds,
    List<CareExpense>? expenses,
    List<LogEntry>? notes,
    Map<int, String>? noteAuthors,
    Map<String, String>? names,
    int? seq,
  }) => CareDoc(
    meds: meds ?? this.meds,
    expenses: expenses ?? this.expenses,
    notes: notes ?? this.notes,
    noteAuthors: noteAuthors ?? this.noteAuthors,
    names: names ?? this.names,
    seq: seq ?? this.seq,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'meds': <Object?>[for (final CareMedication m in meds) m.toJson()],
    'expenses': <Object?>[for (final CareExpense e in expenses) e.toJson()],
    'notes': <Object?>[
      for (final LogEntry n in notes)
        <String, Object?>{
          'seq': n.seq,
          'childId': n.childId,
          'authorId': n.authorId,
          'at': n.at,
          'body': n.body,
          'prev': n.prevHash,
          'hash': n.hash,
          'by': noteAuthors[n.seq] ?? careUnnamedGuardian,
        },
    ],
    'names': names,
    'seq': seq,
  };

  static CareDoc fromJson(Object? j) {
    if (j is! Map) return const CareDoc();
    final List<LogEntry> notes = <LogEntry>[];
    final Map<int, String> by = <int, String>{};
    if (j['notes'] is List) {
      for (final Object? x in j['notes']! as List) {
        if (x is! Map) continue;
        final Object? s = x['seq'];
        if (s is! int ||
            x['childId'] is! String ||
            x['authorId'] is! String ||
            x['at'] is! String ||
            x['body'] is! String ||
            x['prev'] is! String ||
            x['hash'] is! String) {
          continue;
        }
        // The body and hash are kept EXACTLY as written: nothing is trimmed or cleaned on read, so a chain
        // always verifies against what was hashed.
        notes.add(
          LogEntry(
            seq: s,
            childId: x['childId']! as String,
            authorId: x['authorId']! as String,
            at: x['at']! as String,
            body: x['body']! as String,
            prevHash: x['prev']! as String,
            hash: x['hash']! as String,
          ),
        );
        by[s] = _t(x['by']).isEmpty ? careUnnamedGuardian : _t(x['by']);
      }
    }
    final Object? sq = j['seq'];
    return CareDoc(
      meds: <CareMedication>[
        if (j['meds'] is List)
          for (final Object? m in (j['meds']! as List).take(careMaxMedicines)) ?CareMedication.tryFromJson(m),
      ],
      expenses: <CareExpense>[
        if (j['expenses'] is List)
          for (final Object? e in (j['expenses']! as List).take(careMaxExpenses)) ?CareExpense.tryFromJson(e),
      ],
      notes: notes,
      noteAuthors: by,
      names: <String, String>{
        if (j['names'] is Map)
          for (final MapEntry<Object?, Object?> e in (j['names']! as Map).entries)
            if (e.key is String && _t(e.value).isNotEmpty) e.key! as String: _t(e.value),
      },
      seq: sq is int && sq >= 0 ? sq : 0,
    );
  }
}

// ============================================================ repositories ===
abstract class CareRepository {
  Future<CareDoc> load();

  /// Throws [LocalStoreFull] / [LocalStoreException] on a failed save.
  Future<void> save(CareDoc d);
}

class MemoryCareRepository implements CareRepository {
  Object? _j;
  @override
  Future<CareDoc> load() async => CareDoc.fromJson(_j == null ? null : jsonDecode(jsonEncode(_j)));
  @override
  Future<void> save(CareDoc d) async => _j = jsonDecode(jsonEncode(d.toJson()));
}

class LocalStoreCareRepository implements CareRepository {
  LocalStoreCareRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<CareDoc> load() async {
    try {
      return CareDoc.fromJson(await _ns.get(_key));
    } catch (_) {
      return const CareDoc();
    }
  }

  @override
  Future<void> save(CareDoc d) => _ns.put(_key, d.toJson());
}

// ================================================================ service ====
class CareService {
  CareService(this.repo, {required this.childScope, this.guardianCount = 1, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  factory CareService.memory({String childScope = 'demo-child', int guardianCount = 1, DateTime Function()? clock}) =>
      CareService(MemoryCareRepository(), childScope: childScope, guardianCount: guardianCount, clock: clock);

  /// Durable and sealed, scoped to [childId] (default: the device's child).
  factory CareService.local(
    LocalServices services, {
    String? childId,
    int guardianCount = 1,
    DateTime Function()? clock,
  }) => CareService(
    LocalStoreCareRepository(services.area('coordination', ownerId: childId)),
    childScope: services.scopeChild(childId),
    guardianCount: guardianCount,
    clock: clock,
  );

  static CareService? _shared;
  static String? _sharedFor;

  /// The one shared instance the shells use, bound to [LocalServices.current].
  static CareService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    final String key = '${identityHashCode(s)}:${childId ?? s.childId}';
    if (_shared == null || _sharedFor != key) {
      _shared = CareService.local(s, childId: childId);
      _sharedFor = key;
    }
    return _shared!;
  }

  static void resetShared() {
    _shared = null;
    _sharedFor = null;
  }

  final CareRepository repo;

  /// The child scope that goes into every handover hash.
  final String childScope;

  /// How many guardians the family has. A local-only device knows one.
  final int guardianCount;
  final DateTime Function() _clock;

  bool _guardian(FamilyPrincipal? p) => canEditStructure(p);
  Future<void> _lock = Future<void>.value();

  /// The stored document. Guardian only.
  Future<CareDoc> read(FamilyPrincipal? p) async {
    if (!_guardian(p)) throw const CareLocalRefused('guardian_only');
    return repo.load();
  }

  /// Serialised read-modify-write. [body] returns the new document and a value, or throws a [_Refuse].
  Future<CareResult<T>> _write<T>(
    FamilyPrincipal? p,
    String? byName,
    Future<(CareDoc, T)> Function(CareDoc d, String id, String who) body,
  ) {
    final Future<CareResult<T>> r = _lock.then((_) async {
      if (!_guardian(p)) return CareResult<T>.no('guardian_only');
      try {
        final String id = p!.userId! as String;
        final CareDoc d0 = await repo.load();
        final String given = _t(byName);
        if (given.length > 40) return CareResult<T>.no('too_long');
        final Map<String, String> names = <String, String>{...d0.names, if (given.isNotEmpty) id: given};
        final String who = names[id] ?? careUnnamedGuardian;
        final (CareDoc nd, T v) = await body(d0.copyWith(names: names), id, who);
        await repo.save(nd);
        return CareResult<T>.ok(v);
      } on _Refuse catch (e) {
        return CareResult<T>.no(e.reason, detail: e.detail);
      } on LocalStoreFull {
        return CareResult<T>.no('full');
      } on LocalStoreException {
        return CareResult<T>.no('not_saved');
      }
    });
    _lock = r.then((_) {}, onError: (Object _) {});
    return r;
  }

  DateTime _nowMs() => DateTime.fromMillisecondsSinceEpoch(_clock().millisecondsSinceEpoch, isUtc: true);
  String _nextId(CareDoc d, String prefix) => '$prefix${d.seq + 1}';

  // ------------------------------------------------------------ medicines ---
  CareMedication _cleanMed(CareMedication m) {
    final String name = _t(m.name), dose = _t(m.dose), note = _t(m.note);
    if (name.isEmpty) throw const _Refuse('name_needed');
    if (name.length > careMaxNameChars || dose.length > careMaxDoseChars || note.length > careMaxNoteChars) {
      throw const _Refuse('too_long');
    }
    final List<String> slots = <String>{...m.slots.map(_t)}.toList()..sort();
    if (slots.any((String s) => !_hhmm.hasMatch(s))) throw const _Refuse('bad_time');
    if (slots.length > careMaxSlots) throw const _Refuse('too_many');
    if (m.kind == MedKind.scheduled && slots.isEmpty) throw const _Refuse('slot_needed');
    final int gap = m.gapHours.clamp(1, careMaxGapHours);
    return CareMedication(
      id: m.id,
      name: name,
      dose: dose,
      kind: m.kind,
      slots: m.kind == MedKind.scheduled ? slots : const <String>[],
      gapHours: gap,
      note: note,
      retired: m.retired,
      doses: m.doses,
    );
  }

  Future<CareResult<String>> addMedication(FamilyPrincipal? p, CareMedication m, {String? byName}) =>
      _write<String>(p, byName, (CareDoc d, String id, String who) async {
        if (d.meds.length >= careMaxMedicines) throw const _Refuse('too_many');
        final String mid = _nextId(d, 'm');
        final CareMedication clean = _cleanMed(
          CareMedication(
            id: mid,
            name: m.name,
            dose: m.dose,
            kind: m.kind,
            slots: m.slots,
            gapHours: m.gapHours,
            note: m.note,
          ),
        );
        return (d.copyWith(meds: <CareMedication>[...d.meds, clean], seq: d.seq + 1), mid);
      });

  /// Edits name, dose, times, gap and note. Past doses are unchanged; the kind never changes.
  Future<CareResult<void>> editMedication(FamilyPrincipal? p, String id, CareMedication changes, {String? byName}) =>
      _write<void>(p, byName, (CareDoc d, String who, String name) async {
        final int i = d.meds.indexWhere((CareMedication x) => x.id == id);
        if (i < 0) throw const _Refuse('not_found');
        final CareMedication cur = d.meds[i];
        if (cur.retired) throw const _Refuse('retired');
        final CareMedication clean = _cleanMed(
          CareMedication(
            id: id,
            name: changes.name,
            dose: changes.dose,
            kind: cur.kind,
            slots: changes.slots,
            gapHours: changes.gapHours,
            note: changes.note,
            doses: cur.doses,
          ),
        );
        final List<CareMedication> l = <CareMedication>[...d.meds]..[i] = clean;
        return (d.copyWith(meds: l), null);
      });

  /// Retires a medicine. Its dose log stays.
  Future<CareResult<void>> retireMedication(FamilyPrincipal? p, String id, {String? byName}) =>
      _write<void>(p, byName, (CareDoc d, String who, String name) async {
        final int i = d.meds.indexWhere((CareMedication x) => x.id == id);
        if (i < 0) throw const _Refuse('not_found');
        final List<CareMedication> l = <CareMedication>[...d.meds]..[i] = d.meds[i].copyWith(retired: true);
        return (d.copyWith(meds: l), null);
      });

  /// Logs a dose just given. Refused with 'already_given' (and who, when, next allowed in [CareResult.detail])
  /// when this slot or gap already has one. There is no override.
  Future<CareResult<DateTime>> logDose(FamilyPrincipal? p, String id, {String? byName}) =>
      _write<DateTime>(p, byName, (CareDoc d, String gid, String who) async {
        final int i = d.meds.indexWhere((CareMedication x) => x.id == id);
        if (i < 0) throw const _Refuse('not_found');
        final CareMedication m = d.meds[i];
        if (m.retired) throw const _Refuse('retired');
        final DateTime now = _clock();
        final MedState st = medState(m, now);
        if (st.given && st.last != null) {
          throw _Refuse('already_given', <String, Object?>{
            'byId': st.last!.byId,
            'byName': st.last!.byName,
            'at': st.last!.at,
            'next': m.kind == MedKind.prn ? st.next : null,
            'name': m.name,
          });
        }
        final DateTime at = _nowMs();
        final List<CareMedication> l = <CareMedication>[...d.meds]
          ..[i] = m.copyWith(
            doses: <CareDose>[
              ...m.doses,
              CareDose(at: at, byId: gid, byName: who),
            ],
          );
        return (d.copyWith(meds: l), at);
      });

  // ------------------------------------------------------------- expenses ---
  Future<CareResult<String>> proposeExpense(FamilyPrincipal? p, String description, String amount, {String? byName}) =>
      _write<String>(p, byName, (CareDoc d, String gid, String who) async {
        final String title = _t(description);
        if (title.isEmpty) throw const _Refuse('description_needed');
        if (title.length > careMaxExpenseTitleChars) throw const _Refuse('too_long');
        final int? cents = parseCents(amount);
        if (cents == null || cents > careMaxExpenseCents) throw const _Refuse('bad_amount');
        if (d.expenses.length >= careMaxExpenses) throw const _Refuse('too_many');
        final DateTime at = _nowMs();
        final String eid = _nextId(d, 'x');
        final CareExpense e = CareExpense(
          id: eid,
          description: title,
          cents: cents,
          paidById: gid,
          paidByName: who,
          createdAt: at,
          events: <ExpenseEvent>[
            ExpenseEvent(seq: 0, from: null, to: ExpenseStatus.proposed, at: at, byId: gid, byName: who),
          ],
        );
        return (d.copyWith(expenses: <CareExpense>[...d.expenses, e], seq: d.seq + 1), eid);
      });

  Future<CareResult<ExpenseStatus>> resolveExpense(
    FamilyPrincipal? p,
    String id,
    ExpenseAction action, {
    String reason = '',
    String? byName,
  }) => _write<ExpenseStatus>(p, byName, (CareDoc d, String gid, String who) async {
    final int i = d.expenses.indexWhere((CareExpense x) => x.id == id);
    if (i < 0) throw const _Refuse('not_found');
    final CareExpense e = d.expenses[i];
    final String? no = expenseRefusal(e, action, gid, guardianCount, reason: reason);
    if (no != null) throw _Refuse(no);
    final ExpenseStatus to = switch (action) {
      ExpenseAction.accept => ExpenseStatus.accepted,
      ExpenseAction.dispute => ExpenseStatus.disputed,
      ExpenseAction.reimburse => ExpenseStatus.reimbursed,
    };
    final bool self = action == ExpenseAction.accept && e.paidById == gid;
    final ExpenseEvent ev = ExpenseEvent(
      seq: e.events.length,
      from: e.status,
      to: to,
      at: _nowMs(),
      byId: gid,
      byName: who,
      selfAccept: self,
    );
    final List<CareExpense> l = <CareExpense>[...d.expenses]
      ..[i] = e.withStatus(to, ev, reason: action == ExpenseAction.dispute ? _t(reason) : null);
    return (d.copyWith(expenses: l), to);
  });

  // ------------------------------------------------------------- handover ---
  /// Appends a note to the chain. Returns its number (as a person counts).
  Future<CareResult<int>> appendNote(FamilyPrincipal? p, String text, {String? byName}) =>
      _write<int>(p, byName, (CareDoc d, String gid, String who) async {
        // The text is kept as written (only an outer trim): what is hashed is what is shown.
        final String body = text.trim();
        if (body.isEmpty) throw const _Refuse('text_needed');
        if (body.length > careHandoverMaxChars) throw const _Refuse('too_long');
        if (d.notes.length >= careMaxHandoverNotes) throw const _Refuse('too_many');
        final LogEntry e = appendEntry(
          d.notes,
          childId: childScope,
          authorId: gid,
          at: _nowMs().toIso8601String(),
          body: body,
        );
        return (
          d.copyWith(notes: <LogEntry>[...d.notes, e], noteAuthors: <int, String>{...d.noteAuthors, e.seq: who}),
          noteNumber(e),
        );
      });
}

class _Refuse implements Exception {
  const _Refuse(this.reason, [this.detail]);
  final String reason;
  final Map<String, Object?>? detail;
}

/// Thrown by [CareService.read] for a non-guardian.
class CareLocalRefused implements Exception {
  const CareLocalRefused(this.reason);
  final String reason;
  @override
  String toString() => 'CareLocalRefused($reason)';
}
