// OLIVE BRANCH — call_modes.dart tests. MASTERFILE §5.23, §5.23.2.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart';

void main() {
  group('§5.23.1 audio-only as a CHOICE', () {
    test('setMode records mode, cause, and when', () {
      final s = setMode(CallMode.audioOnly, ModeCause.chosen, '2026-08-30T18:00:00Z');
      expect(s.mode, CallMode.audioOnly);
      expect(s.cause, ModeCause.chosen);
      expect(s.changedAt, '2026-08-30T18:00:00Z');
    });

    test('modeForOther discloses the mode but never the cause -- '
        '"he is told the call is voice-only, never why"', () {
      final chosen = setMode(CallMode.audioOnly, ModeCause.chosen, 'x');
      final bedtime = setMode(CallMode.audioOnly, ModeCause.bedtime, 'x');
      final network = setMode(CallMode.audioOnly, ModeCause.network, 'x');

      // Every cause produces the SAME line -- the whole point.
      expect(modeForOther(chosen).line, 'Voice only just now.');
      expect(modeForOther(bedtime).line, 'Voice only just now.');
      expect(modeForOther(network).line, 'Voice only just now.');
    });

    test('modeForOther has no line at all for video mode', () {
      final s = setMode(CallMode.video, ModeCause.chosen, 'x');
      expect(modeForOther(s).line, '');
    });

    test('auditModeDisclosure catches a real leak of the cause', () {
      expect(auditModeDisclosure('Voice only just now.').ok, true);
      expect(auditModeDisclosure('Mode chosen by her.').ok, false);
      expect(auditModeDisclosure('It is bedtime, so audio only.').ok, false);
      expect(auditModeDisclosure('Camera off for now.').ok, false);
      expect(auditModeDisclosure('She turned it off.').ok, false);
      expect(auditModeDisclosure('She declined video.').ok, false);
    });

    test('camera switching is for yourself only', () {
      expect(canSwitchOwnCamera(), true);
      expect(canSwitchOthersCamera(), false);
    });

    test('the listening surface is calm, never a black screen', () {
      final l = listening('#5B6B3F');
      expect(l.surface, ListeningSurface.herColour);
      expect(l.colourHex, '#5B6B3F');
      expect(l.waveformHz, waveformHzCalm);
      expect(waveformHzCalm, 4); // slow -- a fast waveform is a stimulant at bedtime
      expect(neverBlank, true);
    });

    test('a child with no colour yet still gets a real surface, not a crash', () {
      final l = listening(null);
      expect(l.colourHex, isNull);
      expect(l.surface, ListeningSurface.herColour);
    });

    test('answer options are exactly three, equally weighted, video first', () {
      final o = answerOptions();
      expect(o.map((x) => x.kind).toList(),
        [AnswerKind.video, AnswerKind.voice, AnswerKind.notNow]);
      expect(o.map((x) => x.label).toList(), ['Answer', 'Just talking', 'Not now']);
      expect(optionsEquallyWeighted(o), true,
        reason: 'a smaller voice-only button is a judgement, and she will read it as one');
    });
  });

  group('§5.23.2 when it goes wrong', () {
    test('every trouble state gets its own real, distinct child-facing line', () {
      expect(troubleView(CallTrouble.frozen).line, 'The picture stopped. He is still there.');
      expect(troubleView(CallTrouble.slow).line, 'It has gone a bit slow.');
      expect(troubleView(CallTrouble.reconnecting).line, 'Finding him again.');
      expect(troubleView(CallTrouble.dropped).line, 'It stopped. We are getting him back.');
      expect(troubleView(CallTrouble.ended).line, 'That is the end of the call.');
    });

    test('a frozen father and an ended call are told apart by waiting', () {
      expect(troubleView(CallTrouble.frozen).waiting, true);
      expect(troubleView(CallTrouble.dropped).waiting, true);
      expect(troubleView(CallTrouble.reconnecting).waiting, true);
      expect(troubleView(CallTrouble.ended).waiting, false);
    });

    test('auditTrouble passes every real line this module ships', () {
      for (final t in CallTrouble.values) {
        expect(auditTrouble(troubleView(t)).ok, true,
          reason: '${t.name} must never leak a banned word');
      }
    });

    test('auditTrouble catches a real banned phrase', () {
      const bad = TroubleView(state: CallTrouble.dropped, line: 'Check your network.', waiting: true);
      final a = auditTrouble(bad);
      expect(a.ok, false);
      expect(a.found, contains('check your'));
    });

    test('the ladder never fails outright -- it always has a next rung down', () {
      expect(ladder, [Rung.hd, Rung.sd, Rung.audioOnly, Rung.banked]);
      expect(stepRungDown(Rung.hd), Rung.sd);
      expect(stepRungDown(Rung.sd), Rung.audioOnly);
      expect(stepRungDown(Rung.audioOnly), Rung.banked);
      expect(stepRungDown(Rung.banked), Rung.banked); // the floor -- BOTTOM_ALWAYS_WORKS
      expect(bottomAlwaysWorks, true);
    });

    test('the ladder restores one rung at a time going up too', () {
      expect(stepRungUp(Rung.banked), Rung.audioOnly);
      expect(stepRungUp(Rung.audioOnly), Rung.sd);
      expect(stepRungUp(Rung.sd), Rung.hd);
      expect(stepRungUp(Rung.hd), Rung.hd); // the ceiling
    });

    test('only the bottom rung gets a real line -- the others need none', () {
      expect(rungLine(Rung.hd), '');
      expect(rungLine(Rung.sd), '');
      expect(rungLine(Rung.audioOnly), '');
      expect(rungLine(Rung.banked),
        'The line is not good enough right now, so record him something instead.');
    });

    test('reconnecting preserves real call state, not a fresh blank one', () {
      const before = CallState(
        activity: 'pictionary', activityState: {'word': 'house'}, storyLine: 3, elapsedSeconds: 90);
      final after = preserve(before);
      expect(after.activity, 'pictionary');
      expect(after.activityState, {'word': 'house'});
      expect(after.storyLine, 3);
      expect(after.elapsedSeconds, 90);
      expect(reconnectPreservesState, true);
    });

    test('resuming asks first -- a reconnect never auto-transmits her room', () {
      final r = resumeOffer();
      expect(r.line, 'Ready to carry on?');
      expect(r.autoResumes, false);
    });

    test('a metered network change gets honest advice; an unmetered one gets none', () {
      expect(networkChangeAdvice(
        const NetworkChange(from: 'wifi', to: 'cellular', metered: true)),
        'You have moved off wi-fi. This will use data now.');
      expect(networkChangeAdvice(
        const NetworkChange(from: 'wifi', to: 'wifi', metered: false)), isNull);
      expect(survivesNetworkChange, true);
    });
  });
}
