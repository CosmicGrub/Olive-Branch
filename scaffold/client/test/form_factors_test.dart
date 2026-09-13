// OLIVE BRANCH — form_factors.dart tests. MASTERFILE §8.11.1.
// A deliberately partial 1:1 port of devices.ts's §8.11.1 section — this
// file proves the port matches the TS source's own behavior, mirroring how
// device_channels_test.dart proves devices.ts's §8.11.4 port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/form_factors.dart';

void main() {
  group('formFactors — same nine rows as devices.ts', () {
    test('nine postures', () {
      expect(formFactors.length, 9);
    });

    test('the narrowest supported width is the folded Fold', () {
      expect(narrowest, 344);
    });

    test('every posture declares a real minimum viewport', () {
      for (final f in formFactors) {
        expect(f.min.w, greaterThan(0));
        expect(f.min.h, greaterThan(0));
      }
    });

    test('and at least one orientation', () {
      for (final f in formFactors) {
        expect(f.orientations, isNotEmpty);
      }
    });
  });

  group('postureFor — detected from the viewport alone', () {
    test('a folded Fold is recognised', () {
      expect(postureFor(const Viewport(w: 344, h: 882)), Posture.foldCover);
    });
    test('an unfolded one too', () {
      expect(postureFor(const Viewport(w: 673, h: 841)), Posture.foldMain);
    });
    test('a 10-inch tablet', () {
      expect(postureFor(const Viewport(w: 800, h: 1280)), Posture.tabletLarge);
    });
    test('a PC', () {
      expect(postureFor(const Viewport(w: 1100, h: 700)), Posture.desktop);
    });
    test('DeX', () {
      expect(postureFor(const Viewport(w: 1400, h: 800)), Posture.dex);
    });
    test('an ordinary phone', () {
      expect(postureFor(const Viewport(w: 360, h: 740)), Posture.phone);
    });
    test('half-open is recognised as tabletop -- the posture nothing used '
        'and everything should', () {
      expect(postureFor(const Viewport(w: 700, h: 440)), Posture.foldTabletop);
    });
    test('and it is landscape-only', () {
      expect(factor(Posture.foldTabletop)!.orientations, [Orientation.landscape]);
    });
    test('because it stands by itself with the camera up', () {
      expect(factor(Posture.foldTabletop)!.note, contains('camera at eye level'));
    });
  });

  group('columnsAt — computed from EFFECTIVE width, viewport / textScale', () {
    test('a PC gets three', () {
      expect(columnsAt(const Viewport(w: 1280, h: 800), 1), 3);
    });
    test('an unfolded Fold gets two', () {
      expect(columnsAt(const Viewport(w: 673, h: 841), 1), 2);
    });
    test('a folded one gets one', () {
      expect(columnsAt(const Viewport(w: 344, h: 882), 1), 1);
    });
    test('a 10-inch tablet at 2.0x type has the effective width of a '
        'phone -- one column, not two', () {
      expect(columnsAt(const Viewport(w: 800, h: 1280), 2.0), 1);
    });
    test('even a PC-width viewport at 2.0x type drops to one column', () {
      expect(columnsAt(const Viewport(w: 1280, h: 800), 2.0), 1);
    });
    test('a genuinely huge viewport still gets two columns at 2.0x type', () {
      expect(columnsAt(const Viewport(w: 1600, h: 900), 2.0), 2);
    });
    test('the effective-width equivalence holds: 1320/2.0 == 660/1.0', () {
      expect(columnsAt(const Viewport(w: 1320, h: 800), 2.0),
        columnsAt(const Viewport(w: 660, h: 800), 1));
    });
  });
}
