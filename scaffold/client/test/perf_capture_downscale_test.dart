// OLIVE BRANCH — the homework photo is scaled down before it is held, encoded
// and uploaded (on-device performance pass). Pure Dart: no camera, no plugin.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/capture_downscale.dart';

void main() {
  group('fitWithin — what image_picker hands back for maxWidth/maxHeight', () {
    test('a 12 MP landscape sensor image becomes 1600 x 1200', () {
      expect(fitWithin(4000, 3000), (width: 1600, height: 1200));
    });

    test('a 12 MP portrait image becomes 1200 x 1600 (orientation is not swapped)', () {
      expect(fitWithin(3000, 4000), (width: 1200, height: 1600));
    });

    test('a square image becomes maxEdge square', () {
      expect(fitWithin(3000, 3000), (width: 1600, height: 1600));
    });

    test('an image already inside the limit is left alone, never upscaled', () {
      expect(fitWithin(800, 600), (width: 800, height: 600));
      expect(fitWithin(1600, 1600), (width: 1600, height: 1600));
      expect(fitWithin(1600, 1), (width: 1600, height: 1));
    });

    test('only the long edge over the limit triggers scaling', () {
      expect(fitWithin(1601, 100), (width: 1600, height: 100));
      expect(fitWithin(100, 1601), (width: 100, height: 1600));
    });

    test('the aspect ratio is kept to within one pixel and the short side never reaches zero', () {
      for (final (int w, int h) in <(int, int)>[(4032, 3024), (4608, 3456), (9999, 7), (7, 9999), (5000, 3333)]) {
        final ({int width, int height}) r = fitWithin(w, h);
        expect(r.width, lessThanOrEqualTo(kCaptureMaxEdge));
        expect(r.height, lessThanOrEqualTo(kCaptureMaxEdge));
        expect(r.width, greaterThanOrEqualTo(1));
        expect(r.height, greaterThanOrEqualTo(1));
        final double aspectIn = w / h, aspectOut = r.width / r.height;
        final double tolerance = (w >= h ? 1 / r.height : 1 / r.width) * aspectIn + 1e-9;
        expect((aspectIn - aspectOut).abs(), lessThanOrEqualTo(tolerance), reason: '$w x $h -> $r');
      }
    });

    test('a custom limit works, and bad inputs are refused', () {
      expect(fitWithin(4000, 3000, maxEdge: 1000), (width: 1000, height: 750));
      expect(() => fitWithin(0, 10), throwsArgumentError);
      expect(() => fitWithin(10, -1), throwsArgumentError);
      expect(() => fitWithin(10, 10, maxEdge: 0), throwsArgumentError);
    });
  });

  group('the cost it saves, measured in pixels and bytes', () {
    test('base64Length is the padded length', () {
      expect(base64Length(0), 0);
      expect(base64Length(1), 4);
      expect(base64Length(2), 4);
      expect(base64Length(3), 4);
      expect(base64Length(4), 8);
      expect(base64Length(3 * 1024 * 1024), 4 * 1024 * 1024);
      expect(() => base64Length(-1), throwsArgumentError);
    });

    test('the Fold5 / Tab S9 FE sensor size drops from 48 MB to 7.7 MB decoded', () {
      final int before = decodedBitmapBytes(4000, 3000);
      final ({int width, int height}) s = fitWithin(4000, 3000);
      final int after = decodedBitmapBytes(s.width, s.height);
      debugPrint('MEASURED capture 4000x3000: decoded bitmap $before B -> $after B '
          '(${(before / after).toStringAsFixed(2)}x smaller); pixels 12.0 MP -> '
          '${(s.width * s.height / 1e6).toStringAsFixed(2)} MP');
      expect(before, 48000000);
      expect(after, 7680000);
      expect(before / after, closeTo(6.25, 1e-9));
    });
  });

  group('capture_gate.dart actually asks the camera for the downscale', () {
    final String src = File('lib/capture_gate.dart').readAsStringSync();

    test('the picker call passes the shared limits, with no hard-coded size', () {
      final int at = src.indexOf('pickImage(');
      expect(at, greaterThan(0));
      final String call = src.substring(at, src.indexOf(');', at));
      expect(call, contains('maxWidth: kCaptureMaxEdge'));
      expect(call, contains('maxHeight: kCaptureMaxEdge'));
      expect(call, contains('imageQuality: kCaptureJpegQuality'));
    });

    test('the limits are the documented ones', () {
      expect(kCaptureMaxEdge, 1600);
      expect(kCaptureJpegQuality, 90, reason: 'quality is unchanged: the server gate reads fine detail');
    });
  });
}
