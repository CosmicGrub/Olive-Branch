// OLIVE BRANCH — the LOCAL emergency card: what a guardian writes, kept sealed on
// this device, with an append-only history. No longer UNVERIFIED — verified by CI
// (client/test/emergency_card_local_test.dart). MASTERFILE section 8.24.
//
// WHY. Hospital mode (care_screens.dart) and the emergency card screen
// (emergency_card.dart) are only as good as the card behind them. A live build
// with a session reads the server's card, exactly as before. With no session, or
// when the server cannot be reached, they read THIS card: a few plain fields a
// guardian typed. The app adds NO clinical content of its own: every field is empty
// until a guardian fills it, there are no suggestions, no dosing, no conditions list
// and no advice, and "Allergies" is labelled as written by a guardian.
//
// ONE DOCUMENT. The current card, its version counter, the whole history and the
// guardians' remembered names live in ONE sealed LocalStore document, so a write is
// atomic: the card can never move without its history entry, and a half-written
// state cannot exist. The namespace is catalogued ('emergencycard', encrypted) so
// the 'Data on this device' screen lists it and a wipe removes it.
//
// RULES, held here and not left to screens:
//  - GUARDIAN ONLY. Every call takes the principal; a child (or no) principal is
//    refused with 'guardian_only' inside the service, for reads and writes alike.
//  - CONFLICT-SAFE. [EmergencyCardService.save] takes the version the editor
//    loaded. If the card has moved since (another guardian saved on this device),
//    the write is refused with 'stale_version' and nothing changes: no silent
//    overwrite.
//  - APPEND-ONLY HISTORY. Every real change adds one [EcChange]: the new version,
//    when, who (id and name), and the PREVIOUS card in full. Nothing in the history
//    is ever edited or removed; a full box refuses the write ('full') instead of
//    dropping old entries. Saving a card identical to the current one adds nothing.
//  - BOUNDED. Counts and lengths are capped; text is stripped of control
//    characters; empty rows are dropped.
import 'dart:convert';

import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'local_services.dart';
import 'local_store.dart';

// ================================================================== limits ===
const int ecMaxAllergies = 20;
const int ecMaxConditions = 20;
const int ecMaxMedicines = 20;
const int ecMaxContacts = 10;
const int ecMaxLineChars = 200;
const int ecMaxNameChars = 100;
const int ecMaxPhoneChars = 40;
const int ecMaxRelationChars = 60;

/// Used when a guardian has not given a name for the history.
const String ecUnnamedGuardian = 'A guardian';

final RegExp _ctrl = RegExp('[\u0000-\u001f\u007f]');
String _t(Object? v) => v is String ? v.replaceAll(_ctrl, ' ').trim() : '';

/// Why a write or read was refused (a short stable code a screen words gently).
class EcRefused implements Exception {
  const EcRefused(this.reason);
  final String reason;
  @override
  String toString() => 'EcRefused($reason)';
}

/// The result of a write: ok (with the new version), or a stable [reason].
class EcResult {
  const EcResult.ok(this.version) : ok = true, reason = '';
  const EcResult.no(this.reason)
      : ok = false,
        version = 0;
  final bool ok;
  final String reason;
  final int version;
  @override
  String toString() => ok ? 'EcResult.ok($version)' : 'EcResult.no($reason)';
}

String ecRefusalText(String reason) => switch (reason) {
      'guardian_only' => 'Only a grown-up can change the emergency card.',
      'stale_version' => 'Someone changed this card while you were editing. Open it again to see their change.',
      'too_many' => 'There are more rows than fit. Remove one to make room.',
      'too_long' => 'One of those is longer than fits here. Please shorten it.',
      'empty' => 'A name is needed for that row.',
      'full' => "This device's box for the emergency card is full.",
      'not_saved' => 'That did not save. Please try again.',
      _ => 'That could not be saved.',
    };

// ================================================================== the card ==
class EcMedicine {
  const EcMedicine({required this.name, this.dose = ''});
  final String name;
  final String dose;
  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'dose': dose};
  static EcMedicine? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String n = _t(j['name']);
    return n.isEmpty ? null : EcMedicine(name: n, dose: _t(j['dose']));
  }
}

class EcContact {
  const EcContact({required this.name, this.relation = '', this.phone = ''});
  final String name;
  final String relation;
  final String phone;
  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'relation': relation, 'phone': phone};
  static EcContact? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String n = _t(j['name']);
    return n.isEmpty ? null : EcContact(name: n, relation: _t(j['relation']), phone: _t(j['phone']));
  }
}

class EcDoctor {
  const EcDoctor({this.name = '', this.practice = '', this.phone = ''});
  final String name;
  final String practice;
  final String phone;
  bool get isEmpty => name.isEmpty && practice.isEmpty && phone.isEmpty;
  Map<String, Object?> toJson() => <String, Object?>{'name': name, 'practice': practice, 'phone': phone};
  static EcDoctor fromJson(Object? j) =>
      j is Map ? EcDoctor(name: _t(j['name']), practice: _t(j['practice']), phone: _t(j['phone'])) : const EcDoctor();
}

/// What a guardian wrote. Nothing here is supplied by the app.
class LocalEmergencyCard {
  const LocalEmergencyCard({
    this.allergies = const <String>[], this.conditions = const <String>[],
    this.medicines = const <EcMedicine>[], this.doctor = const EcDoctor(),
    this.contacts = const <EcContact>[],
  });

  /// Written by a guardian.
  final List<String> allergies;
  final List<String> conditions;
  final List<EcMedicine> medicines;
  final EcDoctor doctor;
  final List<EcContact> contacts;

  bool get isEmpty =>
      allergies.isEmpty && conditions.isEmpty && medicines.isEmpty && doctor.isEmpty && contacts.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'allergies': allergies, 'conditions': conditions,
        'medicines': <Object?>[for (final EcMedicine m in medicines) m.toJson()],
        'doctor': doctor.toJson(),
        'contacts': <Object?>[for (final EcContact c in contacts) c.toJson()],
      };

  /// Tolerant: unreadable rows are dropped, counts are capped. Never throws.
  static LocalEmergencyCard fromJson(Object? j) {
    if (j is! Map) return const LocalEmergencyCard();
    List<String> lines(Object? v, int max) => <String>[
          if (v is List)
            for (final Object? x in v.take(max))
              if (_t(x).isNotEmpty) _t(x),
        ];
    return LocalEmergencyCard(
      allergies: lines(j['allergies'], ecMaxAllergies),
      conditions: lines(j['conditions'], ecMaxConditions),
      medicines: <EcMedicine>[
        if (j['medicines'] is List)
          for (final Object? x in (j['medicines']! as List).take(ecMaxMedicines))
            ?EcMedicine.tryFromJson(x),
      ],
      doctor: EcDoctor.fromJson(j['doctor']),
      contacts: <EcContact>[
        if (j['contacts'] is List)
          for (final Object? x in (j['contacts']! as List).take(ecMaxContacts)) ?EcContact.tryFromJson(x),
      ],
    );
  }

  /// Same content (field for field).
  bool sameAs(LocalEmergencyCard o) => jsonEncode(toJson()) == jsonEncode(o.toJson());

  /// The card as it is read aloud and printed: allergies first, then the rest, in
  /// the words the guardian wrote. No word is added except the section names.
  String spokenText() {
    final StringBuffer b = StringBuffer();
    b.write(allergies.isEmpty ? 'No allergies written down. ' : 'Allergies: ${allergies.join('. ')}. ');
    if (conditions.isNotEmpty) b.write('Conditions: ${conditions.join('. ')}. ');
    if (medicines.isNotEmpty) {
      b.write('Medicines: ');
      b.write(medicines.map((EcMedicine m) => m.dose.isEmpty ? m.name : '${m.name}, ${m.dose}').join('. '));
      b.write('. ');
    }
    if (!doctor.isEmpty) {
      b.write('Doctor: ${<String>[
        if (doctor.name.isNotEmpty) doctor.name,
        if (doctor.practice.isNotEmpty) doctor.practice,
      ].join(', ')}');
      if (doctor.phone.isNotEmpty) b.write('. Phone: ${doctor.phone}');
      b.write('. ');
    }
    if (contacts.isNotEmpty) {
      b.write('Contacts: ');
      b.write(contacts.map((EcContact c) => <String>[
            c.name, if (c.relation.isNotEmpty) c.relation, if (c.phone.isNotEmpty) c.phone,
          ].join(', ')).join('. '));
      b.write('. ');
    }
    return b.toString().trim();
  }
}

/// Cleans and bounds a card a guardian typed. Throws [EcRefused].
LocalEmergencyCard checkedCard(LocalEmergencyCard c) {
  List<String> lines(List<String> l, int max) {
    final List<String> out = <String>[for (final String s in l) if (_t(s).isNotEmpty) _t(s)];
    if (out.length > max) throw const EcRefused('too_many');
    if (out.any((String s) => s.length > ecMaxLineChars)) throw const EcRefused('too_long');
    return out;
  }

  final List<EcMedicine> meds = <EcMedicine>[
    for (final EcMedicine m in c.medicines)
      if (_t(m.name).isNotEmpty || _t(m.dose).isNotEmpty) EcMedicine(name: _t(m.name), dose: _t(m.dose)),
  ];
  if (meds.length > ecMaxMedicines) throw const EcRefused('too_many');
  if (meds.any((EcMedicine m) => m.name.isEmpty)) throw const EcRefused('empty');
  if (meds.any((EcMedicine m) => m.name.length > ecMaxNameChars || m.dose.length > ecMaxLineChars)) {
    throw const EcRefused('too_long');
  }
  final List<EcContact> cons = <EcContact>[
    for (final EcContact x in c.contacts)
      if (_t(x.name).isNotEmpty || _t(x.phone).isNotEmpty || _t(x.relation).isNotEmpty)
        EcContact(name: _t(x.name), relation: _t(x.relation), phone: _t(x.phone)),
  ];
  if (cons.length > ecMaxContacts) throw const EcRefused('too_many');
  if (cons.any((EcContact x) => x.name.isEmpty)) throw const EcRefused('empty');
  if (cons.any((EcContact x) =>
      x.name.length > ecMaxNameChars || x.relation.length > ecMaxRelationChars || x.phone.length > ecMaxPhoneChars)) {
    throw const EcRefused('too_long');
  }
  final EcDoctor d = EcDoctor(name: _t(c.doctor.name), practice: _t(c.doctor.practice), phone: _t(c.doctor.phone));
  if (d.name.length > ecMaxNameChars || d.practice.length > ecMaxNameChars || d.phone.length > ecMaxPhoneChars) {
    throw const EcRefused('too_long');
  }
  return LocalEmergencyCard(
      allergies: lines(c.allergies, ecMaxAllergies), conditions: lines(c.conditions, ecMaxConditions),
      medicines: meds, doctor: d, contacts: cons);
}

// ================================================================= history ===
/// One entry of the append-only history. [previous] is the card as it was BEFORE
/// this change (null for the very first save), in full.
class EcChange {
  const EcChange({
    required this.version, required this.at, required this.byId, required this.byName, this.previous,
  });

  /// The card's version AFTER this change.
  final int version;
  final String at;
  final String byId;
  final String byName;
  final LocalEmergencyCard? previous;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version, 'at': at, 'byId': byId, 'byName': byName,
        if (previous != null) 'previous': previous!.toJson(),
      };

  static EcChange? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? v = j['version'];
    if (v is! int || v < 1 || j['at'] is! String) return null;
    return EcChange(
        version: v, at: j['at']! as String, byId: _t(j['byId']),
        byName: _t(j['byName']).isEmpty ? ecUnnamedGuardian : _t(j['byName']),
        previous: j['previous'] == null ? null : LocalEmergencyCard.fromJson(j['previous']));
  }
}

/// The whole stored document.
class EmergencyCardDoc {
  const EmergencyCardDoc({
    this.version = 0, this.card, this.history = const <EcChange>[], this.names = const <String, String>{},
  });

  /// 0 before the first save; +1 for every real change.
  final int version;
  final LocalEmergencyCard? card;
  final List<EcChange> history;

  /// A guardian's remembered name, by guardian id (the local profile name used in
  /// "changed by").
  final Map<String, String> names;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        if (card != null) 'card': card!.toJson(),
        'history': <Object?>[for (final EcChange c in history) c.toJson()],
        'names': names,
      };

  static EmergencyCardDoc fromJson(Object? j) {
    if (j is! Map) return const EmergencyCardDoc();
    final List<EcChange> h = <EcChange>[
      if (j['history'] is List)
        for (final Object? x in j['history']! as List) ?EcChange.tryFromJson(x),
    ];
    final Map<String, String> names = <String, String>{
      if (j['names'] is Map)
        for (final MapEntry<Object?, Object?> e in (j['names']! as Map).entries)
          if (e.key is String && _t(e.value).isNotEmpty) e.key! as String: _t(e.value),
    };
    final Object? v = j['version'];
    int version = v is int && v >= 0 ? v : 0;
    for (final EcChange c in h) {
      if (c.version > version) version = c.version;
    }
    return EmergencyCardDoc(
        version: version, card: j['card'] == null ? null : LocalEmergencyCard.fromJson(j['card']), history: h,
        names: names);
  }
}

// ============================================================== repositories ==
abstract class EmergencyCardRepository {
  Future<EmergencyCardDoc> load();

  /// Throws [LocalStoreFull] / [LocalStoreException] on a failed save.
  Future<void> save(EmergencyCardDoc d);
}

class MemoryEmergencyCardRepository implements EmergencyCardRepository {
  Object? _j;
  @override
  Future<EmergencyCardDoc> load() async =>
      EmergencyCardDoc.fromJson(_j == null ? null : jsonDecode(jsonEncode(_j)));
  @override
  Future<void> save(EmergencyCardDoc d) async => _j = jsonDecode(jsonEncode(d.toJson()));
}

class LocalStoreEmergencyCardRepository implements EmergencyCardRepository {
  LocalStoreEmergencyCardRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'doc';
  @override
  Future<EmergencyCardDoc> load() async {
    try {
      return EmergencyCardDoc.fromJson(await _ns.get(_key));
    } catch (_) {
      return const EmergencyCardDoc();
    }
  }

  @override
  Future<void> save(EmergencyCardDoc d) => _ns.put(_key, d.toJson());
}

// ================================================================== service ===
class EmergencyCardService {
  EmergencyCardService(this.repo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  factory EmergencyCardService.memory({DateTime Function()? clock}) =>
      EmergencyCardService(MemoryEmergencyCardRepository(), clock: clock);

  /// Durable and sealed, scoped to [childId] (default: the device's child).
  factory EmergencyCardService.local(LocalServices services, {String? childId, DateTime Function()? clock}) =>
      EmergencyCardService(
          LocalStoreEmergencyCardRepository(services.area('emergencycard', ownerId: childId)), clock: clock);

  /// The one shared instance the shells use, bound to [LocalServices.current].
  static EmergencyCardService? _shared;
  static String? _sharedFor;
  static EmergencyCardService forChild(String? childId) {
    final LocalServices s = LocalServices.current;
    final String key = '${identityHashCode(s)}:${childId ?? s.childId}';
    if (_shared == null || _sharedFor != key) {
      _shared = EmergencyCardService.local(s, childId: childId);
      _sharedFor = key;
    }
    return _shared!;
  }

  /// Puts the shared instance back, for test tear-downs.
  static void resetShared() {
    _shared = null;
    _sharedFor = null;
  }

  final EmergencyCardRepository repo;
  final DateTime Function() _clock;

  bool _guardian(FamilyPrincipal? p) => canEditStructure(p);

  /// The stored document (card, version, history). Guardian only: throws
  /// [EcRefused] ('guardian_only') for a child or no principal.
  Future<EmergencyCardDoc> read(FamilyPrincipal? p) async {
    if (!_guardian(p)) throw const EcRefused('guardian_only');
    return repo.load();
  }

  /// The guardian's remembered name for the history, or [ecUnnamedGuardian].
  Future<String> nameOf(FamilyPrincipal? p) async {
    final EmergencyCardDoc d = await read(p);
    return d.names[p!.userId! as String] ?? ecUnnamedGuardian;
  }

  /// Saves [card] if the stored version is still [expectedVersion]. [byName] (the
  /// guardian's name for the history) is remembered for next time. Nothing is
  /// stored on a refusal.
  Future<EcResult> save(FamilyPrincipal? p, LocalEmergencyCard card,
      {required int expectedVersion, String? byName}) {
    // One write at a time per service, so two quick saves cannot both read the same version.
    final Future<EcResult> r =
        _lock.then((_) => _saveNow(p, card, expectedVersion: expectedVersion, byName: byName));
    _lock = r.then((_) {}, onError: (Object _) {});
    return r;
  }

  Future<void> _lock = Future<void>.value();

  Future<EcResult> _saveNow(FamilyPrincipal? p, LocalEmergencyCard card,
      {required int expectedVersion, String? byName}) async {
    if (!_guardian(p)) return const EcResult.no('guardian_only');
    try {
      final LocalEmergencyCard clean = checkedCard(card);
      final EmergencyCardDoc d = await repo.load();
      if (d.version != expectedVersion) return const EcResult.no('stale_version');
      final String id = p!.userId! as String;
      final String given = _t(byName);
      if (given.length > 40) return const EcResult.no('too_long');
      final Map<String, String> names = <String, String>{...d.names, if (given.isNotEmpty) id: given};
      final String who = names[id] ?? ecUnnamedGuardian;
      final LocalEmergencyCard? before = d.card;
      // Identical to what is stored (or still blank): nothing changed, nothing recorded.
      if ((before != null && before.sameAs(clean)) || (before == null && clean.isEmpty)) {
        if (given.isNotEmpty && d.names[id] != given) {
          await repo.save(EmergencyCardDoc(version: d.version, card: d.card, history: d.history, names: names));
        }
        return EcResult.ok(d.version);
      }
      final int next = d.version + 1;
      final EmergencyCardDoc nd = EmergencyCardDoc(
        version: next, card: clean, names: names,
        history: <EcChange>[
          ...d.history,
          EcChange(version: next, at: _clock().toUtc().toIso8601String(), byId: id, byName: who, previous: before),
        ],
      );
      await repo.save(nd);
      return EcResult.ok(next);
    } on EcRefused catch (e) {
      return EcResult.no(e.reason);
    } on LocalStoreFull {
      return const EcResult.no('full');
    } on LocalStoreException {
      return const EcResult.no('not_saved');
    }
  }
}
