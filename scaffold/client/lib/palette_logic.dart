// OLIVE BRANCH — her colour, palette logic. Verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// CHANGELOG v0.49.61). MASTERFILE §8.6.
//
// A 1:1 semantic port of packages/palette/src/palette.ts, kept close to the
// TS original (same names, same shapes, same ordering) so the two stay
// auditable side by side — the same discipline lock_controller.dart already
// applies to lock.ts. `Color` values are parsed from the same hex strings the
// TS module owns, not re-picked by eye, so the two can never drift.
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ================================================================= palette ==
class Swatch {
  const Swatch({required this.id, required this.label, required this.hex, required this.inkHex});

  final String id;
  /// Her word for it, not a designer's.
  final String label;
  final String hex;
  /// Derived, WCAG-AA-safe against the light surface. Used for text.
  final String inkHex;

  Color get color => colorFromHex(hex);
  Color get ink => colorFromHex(inkHex);
}

Color colorFromHex(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

/// A curated set, not a colour picker. A free picker hands a five-year-old
/// the ability to choose #FEFEFE and wonder why nothing changed. Hues sit
/// away from the semantic set (§8.6.2) so even a near-collision reads as
/// different — there is deliberately no pure red.
const List<Swatch> palette = [
  Swatch(id: 'sunny',     label: 'sunny yellow', hex: '#F2B705', inkHex: '#7A5C00'),
  Swatch(id: 'tangerine', label: 'orange',       hex: '#E8730C', inkHex: '#8A4207'),
  Swatch(id: 'coral',     label: 'coral pink',   hex: '#F0757E', inkHex: '#8F2C34'),
  Swatch(id: 'bubblegum', label: 'bright pink',  hex: '#E056A8', inkHex: '#8A1F62'),
  Swatch(id: 'grape',     label: 'purple',       hex: '#8B6BB1', inkHex: '#4F3670'),
  Swatch(id: 'sea',       label: 'sea blue',     hex: '#2F8FC4', inkHex: '#14536F'),
  Swatch(id: 'sky',       label: 'sky blue',     hex: '#6BB8E8', inkHex: '#175A80'),
  Swatch(id: 'mint',      label: 'mint',         hex: '#5FC9A8', inkHex: '#186853'),
  Swatch(id: 'grass',     label: 'grass green',  hex: '#5AA84A', inkHex: '#2A5722'),
  Swatch(id: 'chocolate', label: 'chocolate',    hex: '#8A6244', inkHex: '#4E3524'),
  Swatch(id: 'storm',     label: 'storm grey',   hex: '#7C8698', inkHex: '#3E4653'),
  Swatch(id: 'midnight',  label: 'midnight',     hex: '#2B3358', inkHex: '#1B2138'),
];

Swatch? swatchFor(String? id) {
  if (id == null) return null;
  for (final s in palette) {
    if (s.id == id) return s;
  }
  return null;
}

// ====================================================== the placement budget =
/// §8.6.2 — where her colour may appear. The forbidden list is the important
/// half: every entry there is a colour that MEANS something elsewhere in the
/// product (a ribbon band, a prohibition), and her colour must never collide
/// with it.
const List<String> allowedPlacements = [
  'accent_stripe', 'avatar_ring', 'sleeps_number', 'game_piece',
  'header_flourish', 'loading_dots', 'collection_tile', 'show_frame',
];

const List<String> forbiddenPlacements = [
  'prohibition', 'error', 'warning', 'destructive',
  'ribbon_band', 'day_part', 'overlap_band', 'now_line',
  'medication_block', 'expiry_digest', 'court_export',
  'body_text', 'background', 'surface',
];

/// At most this many of her colour on one screen. Beyond it the colour stops
/// reading as hers and starts reading as a theme.
const int maxPlacementsPerScreen = 3;

class ApplyColourOutcome {
  const ApplyColourOutcome.ok(this.placements, this.dropped)
      : ok = true, reason = null, offending = null;
  const ApplyColourOutcome.err(this.reason, {this.offending})
      : ok = false, placements = const [], dropped = const [];

  final bool ok;
  final List<String> placements;
  final List<String> dropped;
  /// 'unknown_colour' | 'forbidden_placement'
  final String? reason;
  final String? offending;
}

ApplyColourOutcome applyColour(String colourId, List<String> requested) {
  if (swatchFor(colourId) == null) return const ApplyColourOutcome.err('unknown_colour');
  for (final p in requested) {
    if (forbiddenPlacements.contains(p)) {
      return ApplyColourOutcome.err('forbidden_placement', offending: p);
    }
  }
  final valid = requested.where(allowedPlacements.contains).toList();
  return ApplyColourOutcome.ok(
    valid.take(maxPlacementsPerScreen).toList(),
    valid.skip(maxPlacementsPerScreen).toList(),
  );
}

// ================================================================ contrast ==
double _srgb(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double luminance(String hex) {
  final h = hex.replaceFirst('#', '');
  final r = int.parse(h.substring(0, 2), radix: 16) / 255;
  final g = int.parse(h.substring(2, 4), radix: 16) / 255;
  final b = int.parse(h.substring(4, 6), radix: 16) / 255;
  return 0.2126 * _srgb(r) + 0.7152 * _srgb(g) + 0.0722 * _srgb(b);
}

double contrastRatio(String a, String b) {
  final la = luminance(a), lb = luminance(b);
  final l1 = la > lb ? la : lb, l2 = la > lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

const double aaText = 4.5, aaLarge = 3.0;

class TextColourResult {
  const TextColourResult(this.hex, this.usedInk, this.ratio);
  final String hex;
  final bool usedInk;
  final double ratio;
}

/// §8.4 — she picks yellow, and yellow text on white is unreadable. The
/// answer is not to refuse her choice: the pure hue is used for fills, and a
/// pre-derived inkHex carries text. She never learns her favourite colour was
/// a problem, because it was not one.
TextColourResult textColourFor(Swatch s, {String surface = '#FFFFFF'}) {
  final direct = contrastRatio(s.hex, surface);
  if (direct >= aaText) return TextColourResult(s.hex, false, direct);
  return TextColourResult(s.inkHex, true, contrastRatio(s.inkHex, surface));
}

// ============================================================== the choice ==
class ColourChoice {
  const ColourChoice({required this.colourId, required this.chosenAt, required this.via});

  final String colourId;
  final String chosenAt;
  /// 'first_run' | 'daily' — how it was picked, not why.
  final String via;
}

class DailyPair {
  const DailyPair(this.a, this.b);
  final Swatch a, b;
}

/// §8.6.3 — "What colour do you like more today?" A two-up A/B rather than
/// the full palette. One of the pair is always her current colour, and the
/// side is randomised so hers is not always on the left — a daily prompt that
/// nudges toward change would be manufacturing churn.
final math.Random _sharedRandom = math.Random();

DailyPair dailyPair(String current, {double Function()? rand}) {
  final r = rand ?? _sharedRandom.nextDouble;
  final cur = swatchFor(current) ?? palette.first;
  final others = palette.where((s) => s.id != cur.id).toList();
  final challenger = others[(r() * others.length).floor().clamp(0, others.length - 1)];
  return r() < 0.5 ? DailyPair(cur, challenger) : DailyPair(challenger, cur);
}

class ChooseOutcome {
  const ChooseOutcome.ok(this.history) : ok = true;
  const ChooseOutcome.err() : ok = false, history = const [];
  final bool ok;
  final List<ColourChoice> history;
}

ChooseOutcome choose(List<ColourChoice> history, String colourId, String at, {String via = 'daily'}) {
  if (swatchFor(colourId) == null) return const ChooseOutcome.err();
  return ChooseOutcome.ok([...history, ColourChoice(colourId: colourId, chosenAt: at, via: via)]);
}

Swatch? currentColour(List<ColourChoice> history) =>
    history.isEmpty ? null : swatchFor(history.last.colourId);

// ============================================================ the parent ====
class ParentColourView {
  const ParentColourView({required this.label, required this.hex,
    required this.changedToday, required this.line});

  final String label;
  final String hex;
  /// True only when today's choice differs from yesterday's.
  final bool changedToday;
  /// One neutral sentence. Never an interpretation.
  final String line;
}

/// §8.6.4 — THE PROHIBITION THIS MODULE EXISTS TO HOLD. "She picked grey
/// today — is she sad?" is the product making a psychological claim about a
/// child from a tap. The parent is told WHAT she picked and nothing else:
/// there is no sentiment field, no trend, and (see ParentColourView's own
/// shape above) no field in which one could even be recorded.
ParentColourView? parentView(List<ColourChoice> history, String today) {
  final cur = currentColour(history);
  if (cur == null) return null;
  final day = today.substring(0, 10);
  final todays = history.where((h) => h.chosenAt.substring(0, 10) == day).toList();
  final prior = history.where((h) => h.chosenAt.substring(0, 10).compareTo(day) < 0).toList();
  final changed = todays.isNotEmpty && (prior.isEmpty || prior.last.colourId != cur.id);
  return ParentColourView(
    label: cur.label, hex: cur.hex, changedToday: changed,
    line: changed ? 'Today her colour is ${cur.label}.' : 'Her colour is ${cur.label}.');
}

/// Fields that must never appear alongside a colour. Kept as a live list
/// (rather than only as a comment) so a screen or its test can assert against
/// it the same way auditColourPayload() does in the TS suite.
const List<String> colourForbidden = [
  'mood', 'sentiment', 'feeling', 'emotion', 'trend', 'darker', 'lighter',
  'concern', 'flag', 'alert', 'score', 'streak', 'stability', 'volatility',
];
