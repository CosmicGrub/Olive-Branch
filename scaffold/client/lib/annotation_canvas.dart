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

  /// Cache for [visible()] — a committed-layer `CustomPainter` calls this
  /// every build, and an unchanged, `identical()` list lets its
  /// `shouldRepaint` return false instead of repainting the whole stroke
  /// history on every pointer-move frame. Invalidated (set back to null) by
  /// every method below that actually mutates what `visible()` would
  /// return; never by anything else.
  List<Stroke>? _visibleCache;

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
    _visibleCache = null;
    return AddOk(s);
  }

  /// Undo the actor's own most recent live stroke. Three properties a
  /// last-on-canvas implementation gets wrong, preserved from canvas.ts:
  ///
  ///  - It must skip strokes belonging to anyone else.
  ///  - It must skip strokes already undone, so repeated undo walks
  ///    backwards rather than toggling one stroke.
  ///  - It must skip ERASED strokes entirely — including ones the same
  ///    actor erased themselves. Erase and undo are deliberately distinct,
  ///    one-way mechanisms (see [Stroke.erasedBy]): undo only ever
  ///    manipulates [Stroke.undoneAt], and erase only ever manipulates
  ///    [Stroke.erasedBy]. Letting a self-erased stroke re-enter the
  ///    undoneAt bookkeeping here would hand it a timestamp that competes
  ///    with real draw-undos in redo()'s "most recently undone" ordering
  ///    (redo() picks by comparing undoneAt across all of the actor's
  ///    strokes) — corrupting which stroke a later redo() actually
  ///    restores, and reporting a stroke as "undone" when nothing about
  ///    its visibility ever changed. An erased stroke is simply gone from
  ///    undo's perspective, same as one erased by someone else.
  Stroke? undo(String actorId, int at) {
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final Stroke s = _strokes[i];
      if (s.actorId != actorId) continue;
      if (s.undoneAt != null) continue;
      if (s.erasedBy != null) continue;
      s.undoneAt = at;
      _visibleCache = null;
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
    if (best != null) {
      best.undoneAt = null;
      _visibleCache = null;
    }
    return best;
  }

  bool erase(String strokeId, String byActorId) {
    Stroke? s;
    for (final Stroke candidate in _strokes) {
      if (candidate.id == strokeId) { s = candidate; break; }
    }
    if (s == null || s.erasedBy != null) return false;
    s.erasedBy = byActorId;
    // A stroke must never simultaneously carry a live undoneAt AND a set
    // erasedBy — undo()'s own guard (above) already keeps an ALREADY-erased
    // stroke from ever being handed a fresh undoneAt, but the reverse
    // ordering (undo a stroke first, legitimately, THEN erase that same
    // stroke) was a real, live-found gap: erase() left the stale undoneAt in
    // place, so redo()'s "most recently undone" comparison could still pick
    // the now-erased stroke as its restoration target — a silent no-op on
    // the wrong stroke that shadowed the actually-expected one. Clearing it
    // here closes the invariant at its one real source, rather than adding
    // a second erasedBy check to every future undoneAt reader.
    s.undoneAt = null;
    _visibleCache = null;
    return true;
  }

  /// Deterministic render order regardless of arrival order. Cached and
  /// invalidated only on real mutation (add/undo/redo/erase above), so a
  /// caller that rebuilds every frame without mutating the canvas (e.g. a
  /// `CustomPainter` re-reading this during a live pointer-move) gets back
  /// the exact same `List<Stroke>` instance — letting `shouldRepaint` skip
  /// repainting the whole committed stroke history on every frame.
  List<Stroke> visible() {
    final List<Stroke>? cached = _visibleCache;
    if (cached != null) return cached;
    final List<Stroke> vis = _strokes
        .where((Stroke s) => s.undoneAt == null && s.erasedBy == null)
        .toList();
    vis.sort((Stroke a, Stroke b) {
      final int bySeq = a.seq.compareTo(b.seq);
      return bySeq != 0 ? bySeq : a.actorId.compareTo(b.actorId);
    });
    return _visibleCache = vis;
  }

  void point(CanvasPointer e) => _pointers[e.actorId] = e;

  List<CanvasPointer> activePointers(int now) => _pointers.values
      .where((CanvasPointer p) => now - p.at < pointerTtl.inMilliseconds)
      .toList();

  /// What gets written to the artifact. Pointers deliberately absent.
  List<Stroke> serialize() => visible();
}
