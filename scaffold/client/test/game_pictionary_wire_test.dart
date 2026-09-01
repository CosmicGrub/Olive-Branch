// OLIVE BRANCH — game_pictionary.dart wire tests. Network resilience &
// ad-hoc mode roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic
// tests, no Flutter widget/network involved. The one test that actually
// matters most here: word secrecy is a payload-shape discipline, not
// something the type system enforces — this is the real guardrail, not
// just the comment in game_pictionary.dart's own header.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/annotation_canvas.dart';
import 'package:olive_client/game_pictionary.dart';
import 'package:olive_client/live_games.dart' show auditLiveView;

void main() {
  group('real transport — every real wire payload actually clears the shared P2 audit', () {
    // REGRESSION for a real bug: encodeStroke used to name its coordinate
    // list 'points', which collided with live_games.dart's own
    // liveForbidden guardrail (meant to catch 'score points', not stroke
    // coordinates) — auditLiveView silently refused every drawing, always,
    // found only on real 2-device hardware. This test would have caught it
    // immediately, without needing a device at all.
    test('a real drawingRevealed payload, with real strokes, passes auditLiveView', () {
      final stroke = Stroke(
        id: 'a-1', actorId: 'ivy', actorKind: ActorKind.child, seq: 1,
        points: const [StrokePoint(0.1, 0.2), StrokePoint(0.3, 0.4)],
        color: '#3A7CA5', widthPx: 6.0,
      );
      final payload = encodeDrawingRevealed(rounds: 0, drawerCode: 'b', strokes: [stroke]);
      final audit = auditLiveView(payload);
      expect(audit.ok, isTrue, reason: 'a real stroke payload must never be refused: ${audit.leaks}');
    });

    test('guessSubmitted and a solved guessResult also pass the audit', () {
      expect(auditLiveView(encodeGuessSubmitted(rounds: 0, drawerCode: 'b', guessText: 'a bicycle')).ok, isTrue);
      expect(auditLiveView(encodeGuessResult(rounds: 0, drawerCode: 'b', solved: true, correct: true, word: 'a bicycle')).ok, isTrue);
    });
  });

  group('word secrecy — the real guardrail', () {
    test('drawingRevealed never carries the word, even implicitly', () {
      final payload = encodeDrawingRevealed(rounds: 1, drawerCode: 'b', strokes: const []);
      expect(payload.containsKey('word'), isTrue);
      expect(payload['word'], isNull);
    });

    test('guessSubmitted never carries the word', () {
      final payload = encodeGuessSubmitted(rounds: 1, drawerCode: 'b', guessText: 'a bicycle');
      expect(payload['word'], isNull);
    });

    test('guessResult withholds the word on an incorrect guess', () {
      final payload = encodeGuessResult(rounds: 1, drawerCode: 'b', solved: false, correct: false, word: 'a bicycle');
      expect(payload['word'], isNull, reason: 'an incorrect guess must never reveal the answer');
      expect(payload['solved'], false);
      expect(payload['lastGuessCorrect'], false);
    });

    test('guessResult reveals the word ONLY when solved is true', () {
      final payload = encodeGuessResult(rounds: 1, drawerCode: 'b', solved: true, correct: true, word: 'a bicycle');
      expect(payload['word'], 'a bicycle');
      expect(payload['solved'], true);
    });
  });

  group('stroke encode/decode round-trip', () {
    test('a real stroke survives encode then decode unchanged', () {
      final stroke = Stroke(
        id: 'a-1', actorId: 'ivy', actorKind: ActorKind.child, seq: 1,
        points: const [StrokePoint(0.1, 0.2), StrokePoint(0.3, 0.4)],
        color: '#3A7CA5', widthPx: 6.0,
      );
      final decoded = decodeStroke(encodeStroke(stroke));
      expect(decoded, isNotNull);
      expect(decoded!.id, stroke.id);
      expect(decoded.actorId, stroke.actorId);
      expect(decoded.seq, stroke.seq);
      expect(decoded.points.length, 2);
      expect(decoded.points[0].x, 0.1);
      expect(decoded.points[1].y, 0.4);
      expect(decoded.color, stroke.color);
      expect(decoded.widthPx, 6.0);
    });

    test('a malformed stroke payload decodes to null, never throws', () {
      expect(decodeStroke(null), isNull);
      expect(decodeStroke('not a map'), isNull);
      expect(decodeStroke(<String, dynamic>{}), isNull);
      expect(decodeStroke(<String, dynamic>{'id': 'a', 'actorId': 'ivy', 'seq': 1, 'coords': 'not a list', 'color': '#fff', 'widthPx': 2}), isNull);
      expect(decodeStroke(<String, dynamic>{'id': 'a', 'actorId': 'ivy', 'seq': 1, 'coords': [{'x': 'bad', 'y': 1}], 'color': '#fff', 'widthPx': 2}), isNull);
    });
  });

  group('side codes', () {
    test('round-trip through encodeSide/decodeSide', () {
      for (final s in [0, 1]) {
        final side = s == 0 ? 'a' : 'b';
        expect(encodeSide(decodeSide(side)!), side);
      }
    });

    test('an unknown code decodes to null, never throws or guesses', () {
      expect(decodeSide('c'), isNull);
      expect(decodeSide(null), isNull);
      expect(decodeSide(42), isNull);
    });
  });
}
