// OLIVE BRANCH — degradation banner + quality ladder tests. MASTERFILE
// §5.28, §8.14. Asserts the same properties packages/live/src/stream.ts's
// own suite asserts, plus what actually renders in the widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/degradation_banner.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('quality ladder — pure logic', () {
    test('quick to shed: one strained tick short of 2s changes nothing', () {
      final r = evaluate(newStream(), const StreamTick(Condition.strained, 1999));
      expect(r.changed, StreamChange.none);
      expect(r.state.quality, Quality.q720);
    });

    test('one step per evaluation, never two: 2s strained drops exactly one rung', () {
      final r = evaluate(newStream(), const StreamTick(Condition.strained, 2000));
      expect(r.changed, StreamChange.down);
      expect(r.state.quality, Quality.q360);
    });

    test('walks the floor before ever touching video: 720 -> 360 -> 180 -> audio', () {
      var s = newStream();
      s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      expect(s.quality, Quality.q360);
      expect(s.video, isTrue);
      s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      expect(s.quality, Quality.q180);
      expect(s.video, isTrue);
      s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      expect(s.video, isFalse, reason: 'only after the floor does audio-only trigger');
    });

    test('restoring is six times slower than dropping — asserted, not incidental', () {
      expect(restoreIsSlower, isTrue);
      expect(restoreAfter.inMilliseconds / dropAfter.inMilliseconds, 6.0);
    });

    test('good condition for less than 12s restores nothing', () {
      var s = evaluate(newStream(), const StreamTick(Condition.strained, 2000)).state;
      s = evaluate(s, const StreamTick(Condition.good, 11999)).state;
      expect(s.quality, Quality.q360, reason: 'still degraded — restore window has not elapsed');
    });
  });

  group('what she is told — §5.28.3', () {
    test('no notice while video is present', () {
      expect(noticeFor(newStream()), isNull);
    });

    test('a notice appears once video is lost', () {
      var s = newStream();
      for (var i = 0; i < 3; i++) {
        s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      }
      expect(s.video, isFalse);
      final n = noticeFor(s);
      expect(n, isNotNull);
      expect(n!.line, 'It has gone a bit slow — you can still hear him.');
    });

    test('marking told suppresses the notice for the rest of the call', () {
      var s = newStream();
      for (var i = 0; i < 3; i++) {
        s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      }
      s = markTold(s);
      expect(noticeFor(s), isNull);
    });

    test('NEVER a connection meter', () {
      expect(noConnectionMeter, isTrue);
    });

    test('nothing shown to her may blame her, her network, or her device', () {
      const bad = StreamNotice('Your connection is unstable, try moving closer to the wifi.');
      expect(auditNotice(bad), isFalse);
      const good = StreamNotice('It has gone a bit slow — you can still hear him.');
      expect(auditNotice(good), isTrue);
    });

    test('the real notice text always passes its own audit', () {
      var s = newStream();
      for (var i = 0; i < 3; i++) {
        s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      }
      expect(auditNotice(noticeFor(s)), isTrue);
    });

    test('the voice survives every scenario, on every tier', () {
      var s = newStream();
      for (var i = 0; i < 5; i++) {
        s = evaluate(s, const StreamTick(Condition.strained, 2000)).state;
      }
      expect(audioSurvives(s), isTrue);
      expect(audioFloor, isTrue);
    });
  });

  group('DegradationBanner widget', () {
    testWidgets('renders nothing when there is no notice', (t) async {
      await t.pumpWidget(wrap(const DegradationBanner(notice: null)));
      expect(find.byType(DegradationBanner), findsOneWidget);
      expect(find.text('It has gone a bit slow — you can still hear him.'), findsNothing);
    });

    testWidgets('renders the exact once-only line when a notice is present', (t) async {
      await t.pumpWidget(wrap(const DegradationBanner(
        notice: StreamNotice('It has gone a bit slow — you can still hear him.'))));
      expect(find.text('It has gone a bit slow — you can still hear him.'), findsOneWidget);
    });

    testWidgets('never renders a percentage, bar, or numeric quality readout', (t) async {
      await t.pumpWidget(wrap(const DegradationBanner(
        notice: StreamNotice('It has gone a bit slow — you can still hear him.'))));
      expect(find.textContaining('%'), findsNothing);
      expect(find.byIcon(Icons.signal_cellular_alt), findsNothing);
      expect(find.byIcon(Icons.network_check), findsNothing);
    });
  });

  group('LiveDegradeScreen — end to end', () {
    testWidgets('a wobbly line eventually shows the once-only notice, never a meter', (t) async {
      await t.pumpWidget(wrap(const LiveDegradeScreen(childName: 'Ivy', callerName: 'Dad')));
      final wobble = find.text('Wobble the line');
      await t.ensureVisible(wobble);
      await t.pump();
      await t.tap(wobble);
      await t.pump();
      // 3 rungs to shed (720->360->180->audio) at 2s hysteresis each = 6s+.
      await t.pump(const Duration(seconds: 7));
      expect(find.text('It has gone a bit slow — you can still hear him.'), findsOneWidget);
      expect(find.textContaining('your connection'), findsNothing);
      expect(find.textContaining('your network'), findsNothing);
      expect(find.textContaining('your wifi'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      // Told once: pumping further does not duplicate or replace the banner.
      await t.pump(const Duration(seconds: 2));
      expect(find.text('It has gone a bit slow — you can still hear him.'), findsOneWidget);
      // Tear down so the internal periodic Timer is cancelled before the test ends.
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a steady line keeps full quality and shows no banner', (t) async {
      await t.pumpWidget(wrap(const LiveDegradeScreen()));
      await t.pump(const Duration(seconds: 2));
      expect(find.text('It has gone a bit slow — you can still hear him.'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the demo harness is visually separated from the child-facing frame', (t) async {
      await t.pumpWidget(wrap(const LiveDegradeScreen()));
      expect(find.text('Preview harness — not part of what she sees'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });
}
