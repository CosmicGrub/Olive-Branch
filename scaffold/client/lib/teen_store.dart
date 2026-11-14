// OLIVE BRANCH — the 13 to 17 shell's and the 18 handover's own data, on the device. UNVERIFIED until CI runs it
// (client/test/teen_store_test.dart). MASTERFILE §21, §8.1; catalogue area 'teen' in local_services.dart.
//
// ONE sealed (AES-256-GCM) area, child.<id>.teen, holding exactly what teen_logic.dart models: her own calendar
// events (and who she chose to show each to), the free times she published, the asks and her answers, her choice at
// 18, the staying-in-touch offers and the notes a grown-up left for her birthday. Nothing is uploaded; there is no
// guardian read path in this file (a grown-up's screen gets only the slices teen_logic.dart hands it:
// [eventsSharedWith], the published free times, the asks that are theirs).
//
// It stores no count, score, streak or total, and never a coordinate (P2, P3). A document that cannot be read is
// treated as empty: the store has already quarantined it, and she simply starts a fresh calendar.
import 'dart:async';

import 'local_services.dart';
import 'local_store.dart';
import 'teen_logic.dart';

class TeenRepository {
  TeenRepository(this._ns);

  /// The app's repository for [childId] (default: this device's child).
  factory TeenRepository.forChild([String? childId]) =>
      TeenRepository(LocalServices.current.area('teen', ownerId: childId));

  final LocalNamespace _ns;

  static String _evKey(String id) => 'ev.${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}';

  Future<Object?> _get(String k) async {
    try {
      return await _ns.get(k);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- calendar ---
  /// Every event, in the order she made them (oldest first).
  Future<List<TeenEvent>> events() async {
    final List<TeenEvent> out = <TeenEvent>[];
    try {
      for (final String k in await _ns.list()) {
        if (!k.startsWith('ev.')) continue;
        final Object? raw = await _ns.get(k);
        final TeenEvent? e = TeenEvent.fromJson(raw);
        if (e != null) out.add(e);
      }
    } catch (_) {
      return out;
    }
    out.sort((TeenEvent a, TeenEvent b) => a.id.compareTo(b.id));
    return out;
  }

  /// Throws [LocalStoreFull] (nothing written) when the area is at its limit.
  Future<void> addEvent(TeenEvent e) => _ns.put(_evKey(e.id), e.toJson());

  Future<void> removeEvent(String id) => _ns.delete(_evKey(id));

  // ------------------------------------------------------------ free times ---
  Future<FreeTimes> freeTimes() async => FreeTimes.fromJson(await _get('free'));

  Future<void> saveFreeTimes(FreeTimes f) => _ns.put('free', f.toJson());

  // ------------------------------------------------------------------ asks ---
  Future<AskLedger> asks() async => AskLedger.fromJson(await _get('asks'));

  Future<void> saveAsks(AskLedger l) => _ns.put('asks', l.toJson());

  // -------------------------------------------------------------- handover ---
  Future<HandoverRecord> handover() async => HandoverRecord.fromJson(await _get('handover'));

  Future<void> saveHandover(HandoverRecord r) => _ns.put('handover', r.toJson());

  Future<StayInTouch> touch() async => StayInTouch.fromJson(await _get('touch'));

  Future<void> saveTouch(StayInTouch t) => _ns.put('touch', t.toJson());

  /// grown-up id -> the note that grown-up wrote for the day she is 18. In their words, kept as written.
  Future<Map<String, String>> notes() async {
    final Object? raw = await _get('notes');
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<dynamic, dynamic> e in raw.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  }

  /// An empty note removes it.
  Future<void> saveNote(String guardianId, String text) async {
    final Map<String, String> n = <String, String>{...await notes()};
    final String? clean = cleanHandoverNote(text);
    clean == null ? n.remove(guardianId) : n[guardianId] = clean;
    await _ns.put('notes', n);
  }
}

/// Removes this tablet's copy of her data when, and only when, she took and went, her own copy was saved and checked,
/// and 30 days have passed ([HandoverRecord.purgeDue]). Returns true when it ran. With no saved copy nothing is ever
/// removed, and 'keep' and 'both' never remove anything.
Future<bool> purgeIfDue(TeenRepository repo, DateTime now, Future<void> Function() purge) async {
  final HandoverRecord r = await repo.handover();
  if (!r.purgeDue(now)) return false;
  await purge();
  return true;
}
