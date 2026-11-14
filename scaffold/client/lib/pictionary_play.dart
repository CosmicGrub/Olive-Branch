// OLIVE BRANCH — Draw and guess for two devices, as a [PlayGame] (play_game.dart). The words, the guess check and the canvas
// stay in live_games.dart and annotation_canvas.dart; this file is only the two-device conversation. UNVERIFIED on a
// device; the conversation runs headless over the in-memory and the real encrypted transports
// (client/test/pictionary_play_test.dart, play_wiring_test.dart).
//
// WHAT CHANGED FROM THE OLD SCREEN: it sent its own `{kind: pictionary, turnKind: ...}` bodies, kept the round
// number on each device and recomputed it from what arrived (so a device that restarted mid-round could never agree
// again), and drew its own "stepped out of range" view. Now the dealing device (the grown-up's) holds the public
// truth (whose turn it is to draw, whether the picture is shown, the picture, the last wrong guess) and answers every
// move with it; the other device is rebuilt from that state after an away or a restart.
//
// THE WORD NEVER CROSSES. The drawer's word is picked and kept on the drawer's own device and judged there: the
// guesser's text goes to the drawer, the drawer's device answers only "right" or "not quite". The old wire sent the
// word back on a solved round; it was never shown, so it is simply gone now. `word` is a hidden key of the spec, so
// the session controller refuses to send any state or move that carries it (play_session.dart), and a test asserts it.
//
// THE PICTURE is sent once, on "Show them", as one compact list per stroke (whole numbers only, a flat x,y list), not
// the old one-map-per-point form; a long scribble is thinned (every other point dropped, the line stays the same
// shape) until it fits this game's message size ([pictionarySpec].maxMessageBytes), so a picture never fails to send.
//
// P2 (MASTERFILE section 2.1): no score, no streak, no tally of right guesses, no round counter is on the wire or on
// the screen. The internal round id exists only to ignore a message meant for a round that is over.
import 'dart:convert';

import 'annotation_canvas.dart';
import 'game_logic.dart' show localPlayMinAge;
import 'live_games.dart' show Side, LiveKind, DeckState, newDeck, draw, Pictionary, newPictionary, guessDrawing;
import 'play_envelope.dart' show maxEnvelopeBytesCeiling;
import 'play_game.dart';

Side? _sideOf(Object? s) => s == 'a' ? Side.a : s == 'b' ? Side.b : null;
String _seat(Side s) => s == Side.a ? 'a' : 'b';

/// The most strokes, points and guess characters one message may carry (an untrusted peer can send anything).
const int maxPictureStrokes = 150;
const int maxStrokePoints = 1500;
const int maxGuessChars = 60;

/// One stroke, compact: `{c: '#rrggbb', w: width, p: [x, y, x, y, ...]}` with whole numbers only.
Map<String, dynamic> encodeStrokeCompact(Stroke s, {int thin = 0}) {
  List<StrokePoint> pts = s.points;
  for (int i = 0; i < thin && pts.length > 3; i++) {
    final List<StrokePoint> next = <StrokePoint>[
      for (int j = 0; j < pts.length; j++)
        if (j.isEven || j == pts.length - 1) pts[j],
    ];
    pts = next;
  }
  return <String, dynamic>{
    'c': s.color,
    'w': s.widthPx.round().clamp(1, 40),
    'p': <int>[for (final StrokePoint p in pts) ...<int>[p.x.round(), p.y.round()]],
  };
}

final RegExp _colourRe = RegExp(r'^#[0-9a-fA-F]{6}$');

/// A stroke from the wire, or null when it is not exactly the compact shape (never half-applied).
Stroke? decodeStrokeCompact(Object? raw, int index) {
  if (raw is! Map) return null;
  final Object? c = raw['c'], w = raw['w'], p = raw['p'];
  if (c is! String || !_colourRe.hasMatch(c) || w is! int || w < 1 || w > 40 || p is! List) return null;
  if (p.length.isOdd || p.length > maxStrokePoints * 2) return null;
  final List<StrokePoint> pts = <StrokePoint>[];
  for (int i = 0; i < p.length; i += 2) {
    final Object? x = p[i], y = p[i + 1];
    if (x is! int || y is! int || x < -50 || x > 400 || y < -50 || y > 400) return null;
    pts.add(StrokePoint(x.toDouble(), y.toDouble()));
  }
  return Stroke(id: 'r$index', actorId: 'peer', actorKind: ActorKind.child, seq: index, points: pts, color: c, widthPx: w.toDouble());
}

/// The drawing as a list of compact strokes that fits [maxBytes] of JSON, thinning points until it does. Never null:
/// at the thinnest it keeps each line's first and last points, and drops the oldest lines if even that is too big.
List<Map<String, dynamic>> encodeDrawing(List<Stroke> strokes, {int maxBytes = 20 * 1024}) {
  List<Stroke> use = strokes.length > maxPictureStrokes ? strokes.sublist(strokes.length - maxPictureStrokes) : strokes;
  for (int thin = 0; thin < 14; thin++) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[for (final Stroke s in use) encodeStrokeCompact(s, thin: thin)];
    if (utf8.encode(jsonEncode(out)).length <= maxBytes) return out;
  }
  while (use.length > 1) {
    use = use.sublist(1);
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[for (final Stroke s in use) encodeStrokeCompact(s, thin: 13)];
    if (utf8.encode(jsonEncode(out)).length <= maxBytes) return out;
  }
  return <Map<String, dynamic>>[for (final Stroke s in use) encodeStrokeCompact(s, thin: 13)];
}

List<Stroke>? decodeDrawing(Object? raw) {
  if (raw is! List || raw.length > maxPictureStrokes) return null;
  final List<Stroke> out = <Stroke>[];
  for (int i = 0; i < raw.length; i++) {
    final Stroke? s = decodeStrokeCompact(raw[i], i);
    if (s == null) return null;
    out.add(s);
  }
  return out;
}

/// A guess made safe to keep and show: control and invisible characters become spaces, trimmed, limited by characters.
String cleanGuess(String raw) {
  final StringBuffer b = StringBuffer();
  for (final int c in raw.runes) {
    final bool bad = c < 0x20 || (c >= 0x7f && c <= 0x9f) || (c >= 0x200b && c <= 0x200f) || (c >= 0x202a && c <= 0x202e) ||
        (c >= 0x2066 && c <= 0x2069) || c == 0xfeff;
    b.write(bad ? ' ' : String.fromCharCode(c));
  }
  final List<int> runes = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim().runes.toList();
  return String.fromCharCodes(runes.length > maxGuessChars ? runes.take(maxGuessChars) : runes);
}

class PictionaryPlayGame extends PlayGame {
  PictionaryPlayGame(super.ctx);

  Side get mySide => _sideOf(ctx.localSeatId) ?? Side.a;
  bool get iAmDrawer => _drawer == mySide;

  bool _begun = false;
  Side _drawer = Side.b; // the grown-up's device draws first, as in every other two-device game
  int _round = 0; // internal only: it lets a message for a finished round be ignored; never shown, never a count
  bool _shown = false;
  List<Map<String, dynamic>> _shownEncoded = const <Map<String, dynamic>>[];
  List<Stroke> _shownStrokes = const <Stroke>[];
  String? _lastGuess;
  bool _lastGuessWrong = false;

  // Private to this device.
  String? _word;
  Pictionary? _pictionary;
  DeckState _deck = newDeck(LiveKind.pictionary);

  /// My own canvas while I am the drawer (a fresh one every round).
  AnnotationCanvas? canvas;

  /// I tapped "Show them" and the picture is on its way (the canvas is locked, and so is the button).
  bool pictureSent = false;

  /// I sent a guess and the drawer's device has not answered yet.
  bool awaitingVerdict = false;

  /// The word, on the drawer's own device only. Null everywhere else, and never sent.
  String? get word => iAmDrawer ? _word : null;

  /// The picture the guesser sees (and the drawer's own, once sent).
  List<Stroke> get shownStrokes => _shownStrokes;
  bool get pictureShown => _shown;
  String? get lastGuessText => _lastGuess;
  bool get lastGuessWasWrong => _lastGuessWrong;

  @override
  bool get started => _begun;

  @override
  bool get finished => false; // a round after a round: there is no end to be told about

  /// Both devices call this when they find each other. The dealer opens the first round; the other waits for its state.
  void begin() {
    if (_begun) return;
    _begun = true;
    if (ctx.isAuthority) {
      _enterRound(first: true);
      notifyListeners();
      link?.broadcastState();
    } else {
      notifyListeners();
    }
  }

  void _enterRound({required bool first}) {
    if (!first) {
      _drawer = _drawer == Side.a ? Side.b : Side.a;
      _round += 1;
    }
    _shown = false;
    _shownEncoded = const <Map<String, dynamic>>[];
    _shownStrokes = const <Stroke>[];
    _lastGuess = null;
    _lastGuessWrong = false;
    pictureSent = false;
    awaitingVerdict = false;
    _prepareMyPart();
  }

  void _prepareMyPart() {
    if (iAmDrawer) {
      final result = draw(_deck, ctx.rng);
      if (result == null) return;
      _deck = result.deck;
      _word = result.prompt;
      _pictionary = newPictionary(result.prompt, _drawer);
      canvas = AnnotationCanvas();
    } else {
      _word = null;
      _pictionary = null;
      canvas = null;
    }
  }

  /// The drawer sends the picture ("Show them"). A picture with nothing in it is not sent.
  void showThem() {
    final AnnotationCanvas? c = canvas;
    if (!_begun || !iAmDrawer || _shown || pictureSent || c == null || c.visible().isEmpty) return;
    final List<Map<String, dynamic>> encoded = encodeDrawing(c.visible(), maxBytes: _pictureBudget);
    pictureSent = true;
    if (ctx.isAuthority) {
      _shown = true;
      _shownEncoded = encoded;
      _shownStrokes = decodeDrawing(encoded) ?? const <Stroke>[];
      notifyListeners();
      link?.broadcastState();
    } else {
      notifyListeners();
      link?.sendMove(<String, dynamic>{'t': 'draw', 'r': _round, 's': encoded});
    }
  }

  /// What the picture may take of one message: the rest is the envelope and the other fields of the state.
  int get _pictureBudget => 20 * 1024;

  /// The guesser sends a guess to the drawer's device, which judges it.
  void guess(String text) {
    final String t = cleanGuess(text);
    if (!_begun || iAmDrawer || !_shown || awaitingVerdict || t.isEmpty) return;
    awaitingVerdict = true;
    notifyListeners();
    link?.sendMove(<String, dynamic>{'t': 'guess', 'r': _round, 'x': t});
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    final Map<String, dynamic> p = payload;
    final Side? from = _sideOf(senderSeat);
    final Object? t = p['t'], r = p['r'];
    // The seat is the one the transport says sent it, never anything in the body. A message for another round is old.
    if (from == null || from == mySide || t is! String || r is! int) return PlayMoveOutcome.refused;
    if (!_begun) return PlayMoveOutcome.ignored;
    if (r != _round) return PlayMoveOutcome.ignored;
    switch (t) {
      case 'draw':
        if (!ctx.isAuthority || from != _drawer || _shown) return PlayMoveOutcome.refused;
        final Object? raw = p['s'];
        final List<Stroke>? strokes = decodeDrawing(raw);
        if (strokes == null || strokes.isEmpty) return PlayMoveOutcome.refused;
        _shown = true;
        _shownEncoded = <Map<String, dynamic>>[for (final Object? e in raw! as List) Map<String, dynamic>.from(e! as Map)];
        _shownStrokes = strokes;
        notifyListeners();
        return PlayMoveOutcome.applied;
      case 'guess':
        // Meant for the drawer. Only the drawer's device holds the word, so only it can judge.
        if (!iAmDrawer || from == _drawer || !_shown) return PlayMoveOutcome.refused;
        final Object? x = p['x'];
        if (x is! String || cleanGuess(x).isEmpty || cleanGuess(x).length > maxGuessChars) return PlayMoveOutcome.refused;
        final Pictionary? pic = _pictionary;
        if (pic == null) {
          // This device restarted mid-round and has lost its word: ask for the round to start over (quietly).
          if (!ctx.isAuthority) link?.sendMove(<String, dynamic>{'t': 'redo', 'r': _round});
          return PlayMoveOutcome.ignored;
        }
        final String guess = cleanGuess(x);
        final result = guessDrawing(pic, from, guess);
        if (!result.ok || result.state == null) return PlayMoveOutcome.refused;
        final bool correct = result.correct ?? false;
        _pictionary = result.state;
        if (ctx.isAuthority) {
          _settle(guess, correct);
          return PlayMoveOutcome.applied;
        }
        link?.sendMove(<String, dynamic>{'t': 'verdict', 'r': _round, 'ok': correct, 'x': guess});
        return PlayMoveOutcome.applied;
      case 'verdict':
        if (!ctx.isAuthority || from != _drawer || !_shown) return PlayMoveOutcome.refused;
        final Object? ok = p['ok'], x = p['x'];
        if (ok is! bool || x is! String) return PlayMoveOutcome.refused;
        _settle(cleanGuess(x), ok);
        return PlayMoveOutcome.applied;
      case 'redo':
        if (!ctx.isAuthority || from != _drawer || !_shown) return PlayMoveOutcome.refused;
        _shown = false;
        _shownEncoded = const <Map<String, dynamic>>[];
        _shownStrokes = const <Stroke>[];
        _lastGuess = null;
        _lastGuessWrong = false;
        pictureSent = false;
        awaitingVerdict = false;
        notifyListeners();
        return PlayMoveOutcome.applied;
    }
    return PlayMoveOutcome.refused;
  }

  /// The dealer records what the drawer's device decided.
  void _settle(String guess, bool correct) {
    awaitingVerdict = false;
    if (correct) {
      _enterRound(first: false);
    } else {
      _lastGuess = guess;
      _lastGuessWrong = true;
    }
    notifyListeners();
  }

  Map<String, dynamic> _view() => <String, dynamic>{
        'r': _round,
        'd': _seat(_drawer),
        'sh': _shown,
        's': _shown ? _shownEncoded : const <Map<String, dynamic>>[],
        'g': _lastGuess,
        'gw': _lastGuessWrong,
      };

  @override
  Map<String, dynamic>? stateFor(String seatId) => ctx.isAuthority && _begun ? _view() : null;

  @override
  Object? publicDigestInput() => _begun ? _view() : null;

  @override
  bool applyState(Map<String, dynamic> payload) {
    final Map<String, dynamic> p = payload;
    if (ctx.isAuthority) return false;
    final Object? r = p['r'], sh = p['sh'], g = p['g'], gw = p['gw'];
    final Side? d = _sideOf(p['d']);
    if (r is! int || r < 0 || r > 1000000 || d == null || sh is! bool || gw is! bool) return false;
    if (g != null && (g is! String || g.length > maxGuessChars * 4)) return false;
    final List<Stroke>? strokes = sh ? decodeDrawing(p['s']) : const <Stroke>[];
    if (strokes == null || (sh && strokes.isEmpty)) return false;
    final bool newRound = !_begun || r != _round || d != _drawer;
    _begun = true;
    _round = r;
    _drawer = d;
    if (newRound) {
      _shown = false;
      pictureSent = false;
      if (sh && iAmDrawer) {
        // The picture is already shown for a word this device never had (it restarted): do not make up a new word to
        // judge against; the round is started over below.
        _word = null;
        _pictionary = null;
        canvas = null;
      } else {
        _prepareMyPart();
      }
    }
    _shown = sh;
    _shownStrokes = strokes;
    _shownEncoded = sh ? <Map<String, dynamic>>[for (final Object? e in p['s'] as List) Map<String, dynamic>.from(e! as Map)] : const <Map<String, dynamic>>[];
    _lastGuess = g as String?;
    _lastGuessWrong = gw;
    awaitingVerdict = false;
    if (iAmDrawer && !_shown && _pictionary == null) _prepareMyPart(); // the round was started over: a fresh word and canvas
    if (iAmDrawer && _shown && _pictionary == null) {
      // The picture was shown for a word this device no longer has (it restarted): start the round over, quietly.
      link?.sendMove(<String, dynamic>{'t': 'redo', 'r': _round});
    }
    notifyListeners();
    return true;
  }
}

/// Draw and guess's registration (play_game.dart). The age comes from the one table the hub already uses.
final PlayGameSpec pictionarySpec = PlayGameSpec(
  id: 'pictionary', title: 'Draw and guess', minAge: localPlayMinAge['pictionary']!, minSeats: 2, maxSeats: 2,
  modes: const {PlayMode.pair},
  create: (ctx) => PictionaryPlayGame(ctx),
  // The drawer's word is judged on the drawer's own device and never crosses.
  hiddenInfo: true, hiddenKeys: const ['word'],
  // A picture is the one message that is bigger than a move: up to this many bytes of one encrypted frame.
  maxMessageBytes: maxEnvelopeBytesCeiling,
);
