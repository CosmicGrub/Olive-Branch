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
