// OLIVE BRANCH — annotation_canvas.dart tests. MASTERFILE §9.1, §3.1.
//
// packages/annotation has no TS test suite to mirror (checked at time of
// writing), so this file asserts canvas.ts's own documented invariants
// directly against the Dart port — the header comment there describes
// exactly what "collaborative undo" must and must not do, and every group
// below is one of those sentences turned into an assertion.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/annotation_canvas.dart';

void main() {
  group('add — observers watch, they do not draw (§17.3)', () {
    test('a child can draw', () {
      final AnnotationCanvas c = AnnotationCanvas();
      final AddResult r = c.add(
        id: 's1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#000000', widthPx: 4);
      expect(r, isA<AddOk>());
    });

    test('a guardian can draw', () {
      final AnnotationCanvas c = AnnotationCanvas();
      final AddResult r = c.add(
        id: 's1', actorId: 'dad', actorKind: ActorKind.guardian,
        points: const [StrokePoint(0, 0)], color: '#000000', widthPx: 4);
      expect(r, isA<AddOk>());
    });

    test('an observer is refused, not silently ignored', () {
      final AnnotationCanvas c = AnnotationCanvas();
      final AddResult r = c.add(
        id: 's1', actorId: 'grandma', actorKind: ActorKind.observer,
        points: const [StrokePoint(0, 0)], color: '#000000', widthPx: 4);
      expect(r, isA<AddRefused>());
      expect((r as AddRefused).reason, AddRefusal.observerReadonly);
      expect(c.visible(), isEmpty);
    });

    test('an empty stroke is refused', () {
      final AnnotationCanvas c = AnnotationCanvas();
      final AddResult r = c.add(
        id: 's1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [], color: '#000000', widthPx: 4);
      expect(r, isA<AddRefused>());
      expect((r as AddRefused).reason, AddRefusal.empty);
    });
  });

  group('undo — scoped to the actor, never resurrects past an erase', () {
    test('undo only ever touches the calling actor\'s own strokes', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.add(id: 'd1', actorId: 'dad', actorKind: ActorKind.guardian,
        points: const [StrokePoint(1, 1)], color: '#00f', widthPx: 4);

      // A parent's undo must never erase the child's drawing — the exact
      // failure mode canvas.ts's header warns a naive implementation causes.
      final Stroke? undone = c.undo('dad', 100);
      expect(undone?.id, 'd1');
      final List<String> visibleIds = c.visible().map((s) => s.id).toList();
      expect(visibleIds, contains('a1'));
      expect(visibleIds, isNot(contains('d1')));
    });

    test('repeated undo walks backwards through the actor\'s own history', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.add(id: 'a2', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(1, 1)], color: '#f00', widthPx: 4);

      expect(c.undo('ivy', 1)?.id, 'a2');
      expect(c.undo('ivy', 2)?.id, 'a1');
      expect(c.undo('ivy', 3), isNull, reason: 'nothing left to undo, no error, just null');
      expect(c.visible(), isEmpty);
    });

    test('undo is unlimited — no cap on how many strokes can be undone', () {
      final AnnotationCanvas c = AnnotationCanvas();
      for (int i = 0; i < 50; i++) {
        c.add(id: 's$i', actorId: 'ivy', actorKind: ActorKind.child,
          points: const [StrokePoint(0, 0)], color: '#000', widthPx: 4);
      }
      for (int i = 0; i < 50; i++) {
        expect(c.undo('ivy', i), isNotNull, reason: 'stroke $i should still be undoable');
      }
      expect(c.visible(), isEmpty);
    });

    test('undo skips a stroke erased by someone else — cannot reach past it', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.erase('a1', 'dad');
      expect(c.undo('ivy', 10), isNull);
    });

    // REPRO for the audit's Tier-2 "redo() erased-stroke bug": a
    // self-erased stroke was still eligible for undo()'s undoneAt
    // bookkeeping (the skip condition only excluded strokes erased by
    // SOMEONE ELSE), which let an erased stroke acquire an undoneAt
    // timestamp and pollute the shared per-actor undo/redo ordering that
    // redo() relies on to pick "the most recently undone stroke".
    test('undo does not touch a stroke the actor erased themselves — erase is not undo', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.erase('a1', 'ivy'); // self-erase
      // Nothing left for undo to touch: draw then self-erase is not an
      // undoable "live" stroke — erase is a separate, one-way action.
      expect(c.undo('ivy', 10), isNull);
      expect(c.visible(), isEmpty);
    });

    test('a self-erased stroke never poisons the redo order of a later draw', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.erase('a1', 'ivy'); // self-erase a1
      c.add(id: 'a2', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(1, 1)], color: '#f00', widthPx: 4);

      // Undo the actor's one live stroke, a2.
      final Stroke? undone = c.undo('ivy', 100);
      expect(undone?.id, 'a2');
      expect(c.visible(), isEmpty);

      // A second undo() call must find nothing left (a1 is erased, not
      // undoable) rather than silently grabbing a1 and stamping it with a
      // later undoneAt than a2's.
      expect(c.undo('ivy', 200), isNull);

      // redo() must restore a2 on the very first call — not silently
      // "restore" the already-erased a1 (which would stay invisible and
      // require a second redo() press to actually bring a2 back).
      final Stroke? redone = c.redo('ivy');
      expect(redone?.id, 'a2');
      expect(c.visible().map((s) => s.id), contains('a2'));
    });
  });

  group('redo — restores the most recently undone stroke for that actor', () {
    test('redo brings back what undo just removed', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.undo('ivy', 5);
      expect(c.visible(), isEmpty);
      final Stroke? redone = c.redo('ivy');
      expect(redone?.id, 'a1');
      expect(c.visible().map((s) => s.id), contains('a1'));
    });

    // REPRO for the second half of the "redo() erased-stroke bug": the
    // reverse ordering from the "self-erased stroke" tests above. Undo a
    // stroke first (legitimately) — it now carries a real undoneAt — THEN
    // erase that same stroke. erase() used to leave the stale undoneAt in
    // place, so redo()'s "most recently undone" comparison could still
    // select the now-erased stroke as its restoration target: a silent
    // no-op that shadowed whichever stroke was actually meant to come back.
    // Fixed by erase() itself clearing undoneAt when it tombstones a
    // stroke — a stroke may never simultaneously carry a live undoneAt and
    // a set erasedBy.
    test('undo-then-erase on the same stroke does not poison a later redo', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      expect(c.undo('ivy', 10)?.id, 'a1'); // legitimate undo — a1 gets undoneAt=10
      c.erase('a1', 'ivy'); // then erased — must clear that undoneAt

      c.add(id: 'a2', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(1, 1)], color: '#f00', widthPx: 4);
      expect(c.undo('ivy', 20)?.id, 'a2');

      // redo() must restore a2 — not silently no-op on the erased a1.
      final Stroke? redone = c.redo('ivy');
      expect(redone?.id, 'a2');
      final List<String> visibleIds = c.visible().map((s) => s.id).toList();
      expect(visibleIds, contains('a2'));
      expect(visibleIds, isNot(contains('a1')), reason: 'erased strokes never come back');
    });
  });

  group('visible/serialize — deterministic order, pointers never included', () {
    test('visible order is by seq regardless of actor', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'a1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(0, 0)], color: '#f00', widthPx: 4);
      c.add(id: 'd1', actorId: 'dad', actorKind: ActorKind.guardian,
        points: const [StrokePoint(1, 1)], color: '#00f', widthPx: 4);
      expect(c.visible().map((s) => s.id).toList(), <String>['a1', 'd1']);
    });

    test('a pointer ping is never written into serialize()', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.point(const CanvasPointer(actorId: 'dad', x: 5, y: 5, at: 0));
      expect(c.serialize(), isEmpty);
    });

    test('a stale pointer is not returned as active', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.point(const CanvasPointer(actorId: 'dad', x: 5, y: 5, at: 0));
      expect(c.activePointers(pointerTtl.inMilliseconds + 1), isEmpty);
      expect(c.activePointers(100), isNotEmpty);
    });
  });

  group('stamps ride the same tombstoned-undo machinery as ink', () {
    test('a stamp placement can be undone exactly like a freehand stroke', () {
      final AnnotationCanvas c = AnnotationCanvas();
      c.add(id: 'stamp1', actorId: 'ivy', actorKind: ActorKind.child,
        points: const [StrokePoint(10, 10)], color: '#fff', widthPx: 40,
        stampGlyph: 'heart');
      expect(c.visible().single.stampGlyph, 'heart');
      expect(c.undo('ivy', 1)?.stampGlyph, 'heart');
      expect(c.visible(), isEmpty);
    });
  });
}
