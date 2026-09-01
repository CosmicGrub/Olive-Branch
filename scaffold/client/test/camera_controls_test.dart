// OLIVE BRANCH — camera_controls.dart tests. MASTERFILE §5.24.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/camera_controls.dart';

void main() {
  group('§5.24.1 "show me", live', () {
    test('starts front-facing and mirrored', () {
      final c = newCameraState();
      expect(c.facing, Facing.front);
      expect(c.mirrored, true);
      expect(c.zoom, 1);
      expect(c.torch, false);
    });

    test('flipping to the rear camera turns mirroring OFF and resets zoom', () {
      final c = setZoom(newCameraState(), 3);
      final flipped = flip(c);
      expect(flipped.facing, Facing.rear);
      expect(flipped.mirrored, false);
      expect(flipped.zoom, 1);
    });

    test('flipping back to front restores mirroring', () {
      final flipped = flip(newCameraState());
      final back = flip(flipped);
      expect(back.facing, Facing.front);
      expect(back.mirrored, true);
    });

    test('zoom is clamped to the real range', () {
      expect(setZoom(newCameraState(), 10).zoom, maxZoom);
      expect(setZoom(newCameraState(), -1).zoom, 1);
    });

    test('the torch is only offered on the rear camera', () {
      expect(canTorch(newCameraState()), false);
      expect(canTorch(flip(newCameraState())), true);
    });

    test('auto-framing never pans beyond the frame -- no such option exists', () {
      expect(framing(true).autoFrame, true);
      expect(framing(true).pansBeyondFrame, false);
      expect(framing(false).pansBeyondFrame, false);
    });

    test('lighting advice fires only when genuinely dark, and is about the room', () {
      expect(lightingAdvice(39), isNotNull);
      expect(lightingAdvice(40), isNull);
      expect(lightingAdvice(100), isNull);
    });

    test('auditLighting catches a real banned phrase about her, not the room', () {
      expect(auditLighting(null).ok, true);
      expect(auditLighting('It is very dark in there.').ok, true);
      expect(auditLighting('We cannot see you.').ok, false);
      expect(auditLighting('Your face is too dark for us.').ok, false);
    });
  });

  group('§5.24.2 P10 -- no appearance modification', () {
    test('P10 is on', () {
      expect(p10NoAppearanceModification, true);
    });

    test('every real banned effect is refused', () {
      for (final e in bannedVideoEffects) {
        final v = admitEffect(e);
        expect(v.ok, false, reason: '$e should be refused');
        expect(v.reason, 'appearance_modification');
      }
    });

    test('every real allowed effect is admitted -- silly is fine', () {
      for (final e in allowedVideoEffects) {
        expect(admitEffect(e).ok, true, reason: '$e should be allowed');
      }
    });

    test('a substring match catches a disguised variant', () {
      expect(admitEffect('BeautyFilterPro').ok, false);
    });

    test('backgrounds: allowed for a guardian, refused for a child', () {
      expect(backgroundAllowed(Role.guardian), true);
      expect(backgroundAllowed(Role.child), false);
    });
  });

  group('§5.24.3 audio out', () {
    test('a child defaults to speaker; a guardian defaults to earpiece', () {
      expect(defaultRoute(Role.child, wired: false, bluetooth: false), Route.speaker);
      expect(defaultRoute(Role.guardian, wired: false, bluetooth: false), Route.earpiece);
    });

    test('wired beats bluetooth beats the role default', () {
      expect(defaultRoute(Role.child, wired: true, bluetooth: true), Route.wired);
      expect(defaultRoute(Role.child, wired: false, bluetooth: true), Route.bluetooth);
    });

    test('headphone note is stated neutrally, never as a status about her', () {
      expect(headphoneNote(true), 'She has headphones in.');
      expect(headphoneNote(false), isNull);
      expect(auditHeadphoneNote('She has headphones in.').ok, true);
      expect(auditHeadphoneNote('She is alone and safe to talk.').ok, false);
    });

    test('a hearing ceiling a child cannot raise', () {
      expect(clampVolume(1.0, Role.child), maxChildVolume);
      expect(clampVolume(1.0, Role.guardian), 1.0);
      expect(clampVolume(-1, Role.child), 0);
    });

    test('echo risk only warns for real same-room multi-device', () {
      expect(echoRisk(2, true).advice, isNotNull);
      expect(echoRisk(1, true).advice, isNull);
      expect(echoRisk(2, false).advice, isNull);
    });
  });

  group('§5.24.4 PiP -- conflicts with the child lock', () {
    test('a locked child gets no PiP at all -- there is nothing for it to solve', () {
      final p = pipFor(Role.child, kioskLocked: true);
      expect(p.kind, PipKind.none);
    });

    test('an unlocked child gets the in-layout pane, never an OS window', () {
      final p = pipFor(Role.child, kioskLocked: false);
      expect(p.kind, PipKind.inLayout);
    });

    test('a guardian always gets real OS-native PiP', () {
      expect(pipFor(Role.guardian, kioskLocked: true).kind, PipKind.osNative);
      expect(pipFor(Role.guardian, kioskLocked: false).kind, PipKind.osNative);
    });

    test('a PiP window is never smaller than a recognisable face', () {
      expect(const PipWindow().minPx, 96);
      expect(const PipWindow().remembered, true);
      expect(const PipWindow().tapReturns, true);
    });

    test('the in-layout pane is explicitly not the same thing as PiP', () {
      expect(inLayoutIsNotPip, true);
    });
  });

  group('§5.24.5 screen recording -- detectable, not preventable', () {
    test('a real disclosure exists for the two detectable platforms', () {
      expect(recordingDisclosure('ios'), isNotNull);
      expect(recordingDisclosure('android_play'), isNotNull);
    });

    test('an undetectable platform gets no fabricated claim', () {
      expect(recordingDisclosure('android_sideload'), isNull);
    });

    test('recording is never claimed to be preventable', () {
      expect(recordingPreventable, false);
    });
  });
}
