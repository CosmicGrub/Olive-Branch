// OLIVE BRANCH — the size policy for a photographed worksheet.
// No longer UNVERIFIED — verified by CI (client/test/capture_downscale_test.dart).
//
// WHY. capture_gate.dart used to ask the camera for the full sensor image
// (about 12 MP on the Fold5 and the Tab S9 FE, 3-4 MB of JPEG), hold those
// bytes in memory, base64 them (another third larger) into one JSON request
// body, and later decode all of it again to paint a 140 dp thumbnail. A page
// of homework is legible at a much smaller size, so the camera is now asked to
// scale the longest edge down to [kCaptureMaxEdge] before the bytes ever reach
// Dart. The plugin does that natively (image_picker's maxWidth/maxHeight), so
// no image decoding happens in Dart and the EXIF orientation tag travels with
// the file exactly as the camera wrote it.
//
// This file is the pure part: the numbers, and the arithmetic that says what
// size the platform will hand back, so both are testable without a camera.
// Quality stays at the previous 90 on purpose: the server's blur/clip gate
// looks at fine detail, and the dimension cut alone is what saves the bytes.

/// The longest edge, in pixels, a captured worksheet is scaled down to.
const int kCaptureMaxEdge = 1600;

/// JPEG quality requested from the camera (unchanged from before this pass).
const int kCaptureJpegQuality = 90;

/// The pixel size image_picker returns for a [width] x [height] source when
/// asked for at most [maxEdge] on each side: the longest edge becomes
/// [maxEdge], the other follows the aspect ratio (rounded, never below 1), and
/// a source already inside the limit is returned unchanged (never upscaled).
({int width, int height}) fitWithin(int width, int height, {int maxEdge = kCaptureMaxEdge}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('image size must be positive, got ${width}x$height');
  }
  if (maxEdge <= 0) throw ArgumentError('maxEdge must be positive, got $maxEdge');
  if (width <= maxEdge && height <= maxEdge) return (width: width, height: height);
  if (width >= height) {
    final int h = (height * maxEdge / width).round();
    return (width: maxEdge, height: h < 1 ? 1 : h);
  }
  final int w = (width * maxEdge / height).round();
  return (width: w < 1 ? 1 : w, height: maxEdge);
}

/// Length of the base64 text for [byteCount] raw bytes (padded, no line breaks).
int base64Length(int byteCount) {
  if (byteCount < 0) throw ArgumentError('byteCount must not be negative');
  return ((byteCount + 2) ~/ 3) * 4;
}

/// Bytes a decoded RGBA bitmap of [width] x [height] occupies in memory.
int decodedBitmapBytes(int width, int height) => width * height * 4;
