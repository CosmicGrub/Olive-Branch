// OLIVE BRANCH — plain colour names for screen readers and read-aloud: so a
// palette of swatches is not a row of unlabelled dots to a child who cannot see
// them well. No longer UNVERIFIED — verified by CI (client/test/
// game_semantics_test.dart). MASTERFILE §8.4.
//
// Pure Dart. The nearest of a short list of everyday colour words, by distance in
// RGB: close enough to tell "red" from "orange" from "pink", which is what a
// painting child needs, and nothing that pretends to be a colour-science name.
import 'dart:ui' show Color;

const Map<String, int> _named = <String, int>{
  'red': 0xFFE53935,
  'orange': 0xFFFF9F43,
  'yellow': 0xFFFDD835,
  'green': 0xFF43A047,
  'blue': 0xFF1E88E5,
  'purple': 0xFF8E24AA,
  'pink': 0xFFEC407A,
  'brown': 0xFF6D4C41,
  'black': 0xFF212121,
  'white': 0xFFFFFFFF,
  'grey': 0xFF9E9E9E,
};

int _d2(Color a, int b) {
  final int dr = (a.r * 255).round() - ((b >> 16) & 0xFF);
  final int dg = (a.g * 255).round() - ((b >> 8) & 0xFF);
  final int db = (a.b * 255).round() - (b & 0xFF);
  return dr * dr + dg * dg + db * db;
}

/// The everyday word for [c].
String colourName(Color c) {
  String best = 'grey';
  int bestD = 1 << 30;
  _named.forEach((String name, int rgb) {
    final int d = _d2(c, rgb);
    if (d < bestD) {
      bestD = d;
      best = name;
    }
  });
  return best;
}
