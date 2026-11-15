// OLIVE BRANCH — family sync, the first thing that uses it: the emergency card shared between two grown-ups' phones.
// UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-SYNC-DESIGN.md sections 3.1, 5.3
// and 6.2 (first slice, the emergency-card half of "S5"). MASTERFILE 8.24.
//
// WHAT IT DOES. A grown-up taps "share this phone's card". That writes one `emergency.set` event holding the whole
// card (the words they typed, nothing added). The other phone receives it as an update and shows it NEXT TO its own
// card; a grown-up there chooses "use it here" (which goes through [EmergencyCardService.save], so the stale-version,
// size and guardian-only rules and the append-only history all still apply) or "share mine instead".
//
// WHAT IT DELIBERATELY DOES NOT DO.
//  - It never changes the card on this phone by itself. Hospital mode and the card screen read the local card exactly
//    as before; a shared card reaches them only after a grown-up taps "use it here". So a hostile or damaged update can
//    never alter what a paramedic sees.
//  - It never picks between two cards. Two grown-ups who share different cards at the same time produce two ends of
//    the stream: both are shown, and a grown-up chooses. The choice is itself an event that names both, so every
//    phone converges on it.
//  - It never shares a blank card (that would look like erasing the other phone's card) and never shares while the
//    stream is in disagreement.
//  - The design's "hospital mode shows both versions while forked" is NOT built (design question 9 needs the owner and
//    a clinician). Hospital mode keeps showing this phone's own card.
import 'dart:convert';
import 'dart:typed_data';

import 'emergency_card_local.dart';
import 'family_ledger.dart' show hexOf;
import 'family_ledger_state.dart';
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'family_sync_engine.dart';
import 'family_sync_event.dart';

const String kEmergencyKind = 'emergency.set';
const String kEmergencyArea = 'emergencycard';

/// One card somebody shared. [card] is null when the event arrived but its card could not be read or broke the
/// card's own limits; such a version is shown as unreadable and can never be chosen.
class EmergencyVersion {
  const EmergencyVersion(this.event, this.card, this.byName);
  final SyncEvent event;
  final LocalEmergencyCard? card;
  final String byName;
  bool get readable => card != null;
}

class EmergencyView {
  const EmergencyView(this.ends, this.known);

  /// The ends of the stream, oldest clock first. Empty: nothing has been shared yet.
  final List<EmergencyVersion> ends;

  /// Applied events in the stream (zero before the first share).
  final int known;
  bool get started => ends.isNotEmpty;
  bool get forked => ends.length > 1;

  /// The one shared card when the grown-ups agree (a single readable end).
  EmergencyVersion? get settled => ends.length == 1 && ends.first.readable ? ends.first : null;
}

class EmergencySync {
  EmergencySync(this.engine, this.childId);
  final SyncEngine engine;
  final String childId;

  Future<Uint8List> streamId() => syncStreamId(engine.fid, kEmergencyArea, childId);

  Future<EmergencyView> view() async {
    final String sid = hexOf(await streamId());
    final List<EmergencyVersion> ends = <EmergencyVersion>[
      for (final SyncEvent e in engine.heads(sid)) if (e.kind == kEmergencyKind) _read(e),
    ];
    return EmergencyView(ends, engine.events(sid).length);
  }

  static EmergencyVersion _read(SyncEvent e) {
    final Object? by = e.payload['by'];
    final String name = by is String && by.trim().isNotEmpty && by.length <= 40 ? by.trim() : ecUnnamedGuardian;
    try {
      final Object? raw = e.payload['card'];
      if (raw is! Map) return EmergencyVersion(e, null, name);
      // Strict, not tolerant: the card must be EXACTLY what a card that passed the grown-up's own limits writes out.
      // The card's reader quietly trims and drops rows it dislikes; a shared card that needed that is unreadable here
      // (otherwise a card cut down to twenty allergies could pass for the one somebody wrote).
      final Object? plain = jsonDecode(jsonEncode(raw));
      final LocalEmergencyCard c = LocalEmergencyCard.fromJson(plain);
      if (c.isEmpty || !_same(plain, c.toJson()) || !c.sameAs(checkedCard(c))) return EmergencyVersion(e, null, name);
      return EmergencyVersion(e, c, name);
    } catch (_) {
      return EmergencyVersion(e, null, name);
    }
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length && a.keys.every((Object? k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  Map<String, Object?> _payload(LocalEmergencyCard c, String byName) => <String, Object?>{
        'child': childId,
        'by': byName.length > 40 ? byName.substring(0, 40) : byName,
        'card': jsonDecode(jsonEncode(c.toJson())),
      };

  /// Shares [card] (this phone's card) as the next version. Refused: 'empty' (a blank card), 'forked' (choose first), 'unreadable' (the shared card cannot be read),
  /// 'same' (already the shared card), or any engine reason ('not_member', 'no_key', 'full', ...).
  Future<SyncAppend> share(LocalEmergencyCard card, {required String byName, required LedgerState state}) async {
    final LocalEmergencyCard clean;
    try {
      clean = checkedCard(card);
    } on EcRefused catch (e) {
      return SyncAppend.no(e.reason);
    }
    if (clean.isEmpty) return const SyncAppend.no('empty');
    final EmergencyView v = await view();
    if (v.forked) return const SyncAppend.no('forked');
    final EmergencyVersion? now = v.settled;
    if (now != null && now.card!.sameAs(clean)) return const SyncAppend.no('same');
    if (v.started && now == null) return const SyncAppend.no('unreadable'); // the single end cannot be read: do not stack on it
    return engine.append(kind: kEmergencyKind, streamId: await streamId(), payload: _payload(clean, byName), state: state);
  }

  /// Settles a disagreement: writes [chosen] as a new version that follows every current end.
  Future<SyncAppend> choose(EmergencyVersion chosen, {required String byName, required LedgerState state}) async {
    final LocalEmergencyCard? c = chosen.card;
    if (c == null) return const SyncAppend.no('unreadable');
    final EmergencyView v = await view();
    if (!v.ends.any((EmergencyVersion e) => e.event.idHex == chosen.event.idHex)) return const SyncAppend.no('moved');
    return engine.append(kind: kEmergencyKind, streamId: await streamId(), payload: _payload(c, byName), state: state);
  }

  /// Puts a shared card on THIS phone, through the card service so every local rule still holds. [expectedVersion] is
  /// the version the screen showed; if the card moved since, 'stale_version' comes back and nothing changes.
  static Future<EcResult> useHere(
    EmergencyCardService service,
    FamilyPrincipal? principal,
    EmergencyVersion v, {
    required int expectedVersion,
  }) async {
    final LocalEmergencyCard? c = v.card;
    if (c == null) return const EcResult.no('unreadable');
    return service.save(principal, c, expectedVersion: expectedVersion);
  }
}
