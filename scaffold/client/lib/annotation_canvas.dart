// OLIVE BRANCH — shared annotation canvas engine. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.1,
// §3.1, §9.12.4.
//
// A 1:1 semantic port of packages/annotation/src/canvas.ts (same class
// shape, same undo/redo/erase semantics, same field names translated to
// Dart naming), in the lock_controller.dart tradition of keeping ported
// logic auditable side by side with its TS source.
//
// Collaborative undo is the whole difficulty the TS header calls out: a
// naive "pop the last stroke" implementation lets a parent's undo erase the
// child's drawing. Undo below is scoped to the actor's own strokes and can
// never resurrect a stroke someone else erased — ported unchanged.
//
// One superset addition beyond canvas.ts: the nullable `stampGlyph` field on
// [Stroke]. doodle_desk.dart uses it to place one of six fixed stamps
// through this exact same tombstoned-undo machinery, rather than building a
// second, parallel history just for stamps — which is also why this file
// exists standalone rather than living inside doodle_desk.dart: MARKUP's own
// note on the 0.42.0 live-pairing amendment is "the shared annotation
// canvas, reused, not rebuilt." Every other field and method matches
// canvas.ts exactly.
//
// This file is pure Dart — no Flutter import, no widget — for the same
// reason lock_controller.dart is: it is logic, not presentation, and stays
// testable without a widget harness.

enum ActorKind { child, guardian, observer }

/// §17.3 — an observer watches. They may point, they may not draw.
const Map<ActorKind, bool> canDraw = <ActorKind, bool>{
  ActorKind.child: true,
  ActorKind.guardian: true,
  ActorKind.observer: false,
};

const Duration pointerTtl = Duration(milliseconds: 1500);

/// A single (x, y) sample. Deliberately not `dart:ui`'s `Offset` — this file
/// stays free of any Flutter dependency, matching lock_controller.dart.
class StrokePoint {
  const StrokePoint(this.x, this.y);
  final double x;
  final double y;
}

class Stroke {
  Stroke({
    required this.id,
    required this.actorId,
    required this.actorKind,
    required this.seq,
    required this.points,
    required this.color,
    required this.widthPx,
    this.undoneAt,
    this.erasedBy,
    this.stampGlyph,
  });

  final String id;
  final String actorId;
  final ActorKind actorKind;

  /// Monotonic per-session ordering. Ties break on actorId for determinism.
  final int seq;
  final List<StrokePoint> points;
  final String color;
  final double widthPx;

  /// Set when undone. Strokes are tombstoned, never spliced out of the list.
  int? undoneAt;

  /// Set when someone erased it explicitly (distinct from undo).
  String? erasedBy;

  /// Superset addition (not in canvas.ts) — see file header. Null for a
  /// freehand stroke; one of doodle_desk.dart's six fixed stamp ids
  /// ('heart' | 'star' | 'smiley' | 'rainbow' | 'sun' | 'moon') otherwise.
  final String? stampGlyph;
}

/// A pointer is a gesture, not ink — mirrors canvas.ts's own comment. It
/// expires and is never persisted with the artifact.
class CanvasPointer {
  const CanvasPointer({required this.actorId, required this.x, required this.y, required this.at});
  final String actorId;
  final double x;
  final double y;
  final int at; // ms since epoch
}

sealed class AddResult {
  const AddResult();
}

class AddOk extends AddResult {
  const AddOk(this.stroke);
  final Stroke stroke;
}

enum AddRefusal { observerReadonly, empty }

class AddRefused extends AddResult {
  const AddRefused(this.reason);
  final AddRefusal reason;
}

class AnnotationCanvas {
  final List<Stroke> _strokes = <Stroke>[];
  int _seq = 0;
  final Map<String, CanvasPointer> _pointers = <String, CanvasPointer>{};

  AddResult add({
    required String id,
    required String actorId,
    required ActorKind actorKind,
    required List<StrokePoint> points,
    required String color,
    required double widthPx,
    String? stampGlyph,
  }) {
    if (!(canDraw[actorKind] ?? false)) return const AddRefused(AddRefusal.observerReadonly);
    if (points.isEmpty) return const AddRefused(AddRefusal.empty);
    final Stroke s = Stroke(
      id: id, actorId: actorId, actorKind: actorKind, seq: ++_seq,
      points: points, color: color, widthPx: widthPx, stampGlyph: stampGlyph);
    _strokes.add(s);
    return AddOk(s);
  }

  /// Undo the actor's own most recent live stroke. Three properties a
  /// last-on-canvas implementation gets wrong, preserved from canvas.ts:
  ///
  ///  - It must skip strokes belonging to anyone else.
  ///  - It must skip strokes already undone, so repeated undo walks
  ///    backwards rather than toggling one stroke.
  ///  - It must skip strokes ERASED by someone else. Undo is not a way to
  ///    reach past another person's deliberate erase.
  Stroke? undo(String actorId, int at) {
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final Stroke s = _strokes[i];
      if (s.actorId != actorId) continue;
      if (s.undoneAt != null) continue;
      if (s.erasedBy != null && s.erasedBy != actorId) continue;
      s.undoneAt = at;
      return s;
    }
    return null;
  }

  /// Redo the actor's most recently undone stroke.
  Stroke? redo(String actorId) {
    Stroke? best;
    for (final Stroke s in _strokes) {
      if (s.actorId != actorId || s.undoneAt == null) continue;
      if (best == null || s.undoneAt! > best.undoneAt!) best = s;
    }
    if (best != null) best.undoneAt = null;
    return best;
  }

  bool erase(String strokeId, String byActorId) {
    Stroke? s;
    for (final Stroke candidate in _strokes) {
      if (candidate.id == strokeId) { s = candidate; break; }
    }
    if (s == null || s.erasedBy != null) return false;
    s.erasedBy = byActorId;
    return true;
  }

  /// Deterministic render order regardless of arrival order.
  List<Stroke> visible() {
    final List<Stroke> vis = _strokes
        .where((Stroke s) => s.undoneAt == null && s.erasedBy == null)
        .toList();
    vis.sort((Stroke a, Stroke b) {
      final int bySeq = a.seq.compareTo(b.seq);
      return bySeq != 0 ? bySeq : a.actorId.compareTo(b.actorId);
    });
    return vis;
  }

  void point(CanvasPointer e) => _pointers[e.actorId] = e;

  List<CanvasPointer> activePointers(int now) => _pointers.values
      .where((CanvasPointer p) => now - p.at < pointerTtl.inMilliseconds)
      .toList();

  /// What gets written to the artifact. Pointers deliberately absent.
  List<Stroke> serialize() => visible();
}
