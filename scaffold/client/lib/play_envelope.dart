// No longer UNVERIFIED — verified by CI (client/test/play_envelope_test.dart replays the shared golden vectors).
// OLIVE BRANCH — the play envelope: the versioned, sequenced wrapper around every ad-hoc "Play together"
// message. Dart port of packages/play-envelope/src/envelope.ts, which is the reference; the vectors in
// packages/play-envelope/test/vectors.json are generated from that file and replayed here, value for value,
// so the two devices can never disagree about what a message means. Design source:
// docs/superpowers/research/gamesuite-multiplayer-for-play-together.md section 5.1 (decisions D1-D12 accepted).
//
// Pure of widgets, sockets and clocks. Rules (numbered as in the reference):
//  E1  The SENDER is never in the message; the transport supplies `senderSeat` from the connection.
//  E2  Every inbound envelope is untrusted: size-capped, parsed, range-checked and audited for the
//      child-safety forbidden keys at any depth before anything reads it. Never throws.
//  E3  `n` is the sender's own counter: duplicates, replays and old messages are dropped, a skipped message is
//      held back and the receiver asks for the state, and a `state` snapshot is idempotent (newest wins).
//  E4  An unknown session id is dropped. The authority mints the id.
//  E5  Only the authority may send `state`.
//  E6  Hidden information: [hiddenLeaks] is the pure check that a state sent across never carries data the
//      sender must keep (other seats' hands, the draw pile, the seed).
//  E7  `ack` frees what the peer has seen and can never exceed what we sent.
import 'dart:convert';

import 'live_games.dart' show liveForbidden;

const int playProtocolVersion = 1;
const int maxEnvelopeBytes = 8192;

/// The most a game may ask its own messages to be (a game that sends a picture, [PlayGameSpec.maxMessageBytes]). One
/// encrypted frame carries 32766 bytes of payload (play_frame.dart), so nothing may ever exceed this.
const int maxEnvelopeBytesCeiling = 30 * 1024;
const int maxUnacked = 32;
const int maxPayloadDepth = 12;
const int _maxSafe = 9007199254740991;

/// Keys that, in a hidden-information game, may never be in anything sent to the other device.
const List<String> alwaysHiddenKeys = <String>['seed', 'rngSeed', 'rng', 'drawPile', 'deck'];

/// Keys that may never cross in ANY game, hidden-information or not, on send or on receive: the dealer's seed stays
/// on the dealing device (a seeded deal exists only so a test can be deterministic, and a seed on the wire would let
/// the other device, or anyone who got through, work out every card still to come).
const List<String> neverSentKeys = <String>['seed', 'rngSeed', 'rng', 'seedForTest'];

enum PlayKind {
  hello('hello'),
  reqState('req_state'),
  state('state'),
  move('move'),
  bye('bye'),
  rematch('rematch'),
  rematchOk('rematch_ok');

  const PlayKind(this.wire);
  final String wire;

  static PlayKind? fromWire(Object? s) {
    for (final PlayKind k in PlayKind.values) {
      if (k.wire == s) return k;
    }
    return null;
  }

  /// Kept until acknowledged, and resent when the other device returns.
  bool get retained => this == move || this == rematch || this == rematchOk;
}

class PlayEnvelope {
  const PlayEnvelope({
    required this.sid, required this.n, required this.ack, required this.t, required this.g, this.p, this.d,
    this.v = playProtocolVersion,
  });
  final int v;
  final String sid;
  final int n;
  final int ack;
  final PlayKind t;
  final String g;
  final Map<String, dynamic>? p;
  final String? d;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': v, 'sid': sid, 'n': n, 'ack': ack, 't': t.wire, 'g': g,
        if (p != null) 'p': p,
        if (d != null) 'd': d,
      };

  String encode() => jsonEncode(toJson());
}

/// Why a raw message was refused. The wire spelling is [wire].
enum ParseFailure {
  tooLarge('too_large'), notJson('not_json'), notObject('not_object'), legacy('legacy'),
  unsupportedVersion('unsupported_version'), badField('bad_field'), badType('bad_type'),
  forbiddenKey('forbidden_key');

  const ParseFailure(this.wire);
  final String wire;
}

class ParsedEnvelope {
  const ParsedEnvelope.ok(PlayEnvelope this.env) : failure = null;
  const ParsedEnvelope.fail(ParseFailure this.failure) : env = null;
  final PlayEnvelope? env;
  final ParseFailure? failure;
  bool get ok => env != null;
}

int? _asInt(Object? v) {
  if (v is int) return v >= 0 && v <= _maxSafe ? v : null;
  // JSON "5.0" decodes as a double in Dart; JavaScript treats it as the integer 5.
  if (v is double && v.isFinite && v == v.truncateToDouble() && v >= 0 && v <= _maxSafe) return v.toInt();
  return null;
}

final RegExp _sidRe = RegExp(r'^[0-9a-f]{16}$');
final RegExp _gameRe = RegExp(r'^[a-z0-9_]{1,24}$');
final RegExp _digestRe = RegExp(r'^[0-9a-f]{8}$');

/// 'ok' | 'forbidden' | 'deep'
String _auditPayload(Object? x, int depth) {
  if (depth > maxPayloadDepth) return 'deep';
  if (x is List) {
    for (final Object? e in x) {
      final String r = _auditPayload(e, depth + 1);
      if (r != 'ok') return r;
    }
    return 'ok';
  }
  if (x is Map) {
    for (final MapEntry<dynamic, dynamic> e in x.entries) {
      final String k = e.key.toString().toLowerCase();
      if (liveForbidden.any((String f) => f.toLowerCase() == k)) return 'forbidden';
      final String r = _auditPayload(e.value, depth + 1);
      if (r != 'ok') return r;
    }
  }
  return 'ok';
}

/// E2: parse an untrusted wire message (a JSON string or an already-decoded map). Never throws. [maxBytes] is the
/// game's own cap (default [maxEnvelopeBytes], never above [maxEnvelopeBytesCeiling]).
ParsedEnvelope parsePlayEnvelope(Object? raw, {int maxBytes = maxEnvelopeBytes}) {
  final int cap = maxBytes.clamp(maxEnvelopeBytes, maxEnvelopeBytesCeiling);
  Object? o = raw;
  if (raw is String) {
    if (utf8.encode(raw).length > cap) return const ParsedEnvelope.fail(ParseFailure.tooLarge);
    try {
      o = jsonDecode(raw);
    } on FormatException {
      return const ParsedEnvelope.fail(ParseFailure.notJson);
    }
  } else {
    String text;
    try {
      text = jsonEncode(raw);
    } catch (_) {
      return const ParsedEnvelope.fail(ParseFailure.notJson);
    }
    if (utf8.encode(text).length > cap) return const ParsedEnvelope.fail(ParseFailure.tooLarge);
  }
  if (o is! Map) return const ParsedEnvelope.fail(ParseFailure.notObject);
  const ParsedEnvelope bad = ParsedEnvelope.fail(ParseFailure.badField);
  if (!o.containsKey('v')) return const ParsedEnvelope.fail(ParseFailure.legacy);
  final int? v = _asInt(o['v']);
  if (v == null || v < 1) return bad;
  if (v > playProtocolVersion) return const ParsedEnvelope.fail(ParseFailure.unsupportedVersion);
  final PlayKind? t = PlayKind.fromWire(o['t']);
  if (t == null) return const ParsedEnvelope.fail(ParseFailure.badType);
  final Object? sid = o['sid'];
  if (sid is! String) return bad;
  if (!(_sidRe.hasMatch(sid) || (sid == '' && t == PlayKind.hello))) return bad;
  final int? n = _asInt(o['n']);
  final int? ack = _asInt(o['ack']);
  if (n == null || ack == null) return bad;
  final Object? g = o['g'];
  if (g is! String || !_gameRe.hasMatch(g)) return bad;
  final Object? d = o['d'];
  if (d != null && (d is! String || !_digestRe.hasMatch(d))) return bad;
  if (o.containsKey('d') && d == null) return bad;
  Map<String, dynamic>? p;
  if (o.containsKey('p')) {
    final Object? pr = o['p'];
    if (pr is! Map) return bad;
    final String a = _auditPayload(pr, 1);
    if (a == 'forbidden') return const ParsedEnvelope.fail(ParseFailure.forbiddenKey);
    if (a == 'deep') return bad;
    p = pr.map((dynamic k, dynamic val) => MapEntry<String, dynamic>(k.toString(), val));
  }
  if ((t == PlayKind.state || t == PlayKind.move) && p == null) return bad;
  return ParsedEnvelope.ok(PlayEnvelope(v: v, sid: sid, n: n, ack: ack, t: t, g: g, p: p, d: d as String?));
}

// ================================================================ session ==
enum PlayRole { authority, guest }

class PlayEnvelopeSession {
  PlayEnvelopeSession({required this.role, required this.mySeat, required this.authoritySeat, String sid = ''})
      : sid = role == PlayRole.authority ? sid : '';

  final PlayRole role;

  /// This device's seat id, e.g. 'a' or 'b'. Seat ids are strings so a third device is possible later.
  final String mySeat;
  final String authoritySeat;

  /// '' until a guest has heard the authority's hello.
  String sid;
  int sendN = 0;
  int lastPeerN = 0;
  int peerAck = 0;
  List<PlayEnvelope> unacked = <PlayEnvelope>[];
  bool overflowed = false;

  /// Build the next outgoing envelope and keep it if it must be kept.
  ///
  /// A control message (`hello`, `req_state`) carries the highest `n` used so far WITHOUT using a new one, so asking for
  /// the state in the middle of a game never makes the next move look like it skipped one.
  PlayEnvelope stamp(PlayKind t, String g, {Map<String, dynamic>? p, String? d}) {
    if (t != PlayKind.hello && t != PlayKind.reqState) sendN += 1;
    final PlayEnvelope env = PlayEnvelope(sid: sid, n: sendN, ack: lastPeerN, t: t, g: g, p: p, d: d);
    if (t.retained) {
      unacked.add(env);
      while (unacked.length > maxUnacked) {
        unacked.removeAt(0);
        overflowed = true;
      }
    }
    return env;
  }

  bool _takeAck(int ack) {
    if (ack > sendN) return false;
    if (ack > peerAck) {
      peerAck = ack;
      unacked = unacked.where((PlayEnvelope e) => e.n > ack).toList();
    }
    return true;
  }

  /// E1, E3, E4, E5, E7. [senderSeat] comes from the transport. Mutates the session only for what it accepts.
  PlayVerdict receive(PlayEnvelope env, String senderSeat) {
    if (senderSeat == mySeat) return const PlayVerdict.no('reflected');
    if (env.t == PlayKind.state && senderSeat != authoritySeat) return const PlayVerdict.no('wrong_sender');

    if (env.t == PlayKind.hello) {
      // The ack on a hello only means something inside the session we share; across a restart it is the old session's.
      final bool sameSession = env.sid == sid;
      if (sameSession && env.ack > sendN) return const PlayVerdict.no('bad_ack');
      if (role == PlayRole.guest) {
        if (senderSeat != authoritySeat) return const PlayVerdict.no('wrong_sender');
        if (!sameSession) {
          // A new authority session (first contact, or the dealer was restarted from its save): adopt it and count from
          // where it says it is. What we sent to the old session is not carried over: the state is the truth.
          sid = env.sid;
          lastPeerN = env.n;
          peerAck = 0;
          unacked = <PlayEnvelope>[];
          overflowed = false;
        } else {
          _takeAck(env.ack);
        }
        return const PlayVerdict.control();
      }
      // The authority hears a guest. A guest with no memory of this session starts counting again.
      if (!sameSession) {
        lastPeerN = env.n;
      } else {
        _takeAck(env.ack);
      }
      return const PlayVerdict.control();
    }

    if (sid == '' || env.sid != sid) return const PlayVerdict.no('unknown_sid');
    if (!_takeAck(env.ack)) return const PlayVerdict.no('bad_ack');
    if (env.t == PlayKind.reqState) return const PlayVerdict.control();

    if (env.t == PlayKind.state) {
      if (env.n <= lastPeerN) return PlayVerdict.no(env.n == lastPeerN ? 'duplicate' : 'stale');
      lastPeerN = env.n;
      return const PlayVerdict.applied();
    }

    if (env.n == lastPeerN + 1) {
      lastPeerN = env.n;
      return const PlayVerdict.applied();
    }
    if (env.n <= lastPeerN) return PlayVerdict.no(env.n == lastPeerN ? 'duplicate' : 'stale');
    return const PlayVerdict.no('gap', needState: true);
  }

  /// Retained messages the peer has not acknowledged, in the order they were sent.
  List<PlayEnvelope> pendingResend() => List<PlayEnvelope>.of(unacked);
}

class PlayVerdict {
  const PlayVerdict.applied() : this._(true, false, null, false);
  const PlayVerdict.control() : this._(true, true, null, false);
  const PlayVerdict.no(String this.reason, {this.needState = false}) : accept = false, control = false;
  const PlayVerdict._(this.accept, this.control, this.reason, this.needState);
  final bool accept;
  final bool control;
  final String? reason;
  final bool needState;
}

/// 16 lowercase hex characters from 8 bytes the caller drew from a secure source.
String makeSid(List<int> bytes) {
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < 8; i++) {
    b.write(((i < bytes.length ? bytes[i] : 0) & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

// ================================================================= digest ==
/// Canonical JSON of a PUBLIC state: object keys sorted, no whitespace, integers only. Null when it cannot be
/// canonicalised (a float or NaN would format differently on each platform).
String? canonicalJson(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is int) return v.abs() <= _maxSafe ? v.toString() : null;
  if (v is double) {
    if (v.isFinite && v == v.truncateToDouble() && v.abs() <= _maxSafe) return v.toInt().toString();
    return null;
  }
  if (v is String) return jsonEncode(v);
  if (v is List) {
    final List<String> parts = <String>[];
    for (final Object? e in v) {
      final String? c = canonicalJson(e);
      if (c == null) return null;
      parts.add(c);
    }
    return '[${parts.join(',')}]';
  }
  if (v is Map) {
    final List<String> keys = v.keys.map((dynamic k) => k.toString()).toList()..sort();
    final List<String> parts = <String>[];
    for (final String k in keys) {
      final String? c = canonicalJson(v[k]);
      if (c == null) return null;
      parts.add('${jsonEncode(k)}:$c');
    }
    return '{${parts.join(',')}}';
  }
  return null;
}

/// 32-bit FNV-1a over the UTF-8 bytes, as 8 lowercase hex characters.
String fnv1a32(String text) {
  int h = 0x811c9dc5;
  for (final int b in utf8.encode(text)) {
    h ^= b;
    // 32-bit multiply without ever exceeding 2^53 (safe on every platform Dart compiles to).
    h = (((h & 0xffff) * 16777619) + ((((h >>> 16) * 16777619) & 0xffff) << 16)) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// The digest of a public state, or null when it cannot be canonicalised. Never shown to anyone.
String? stateDigest(Object? publicState) {
  final String? c = canonicalJson(publicState);
  return c == null ? null : fnv1a32(c);
}

/// E6: the hidden key names found anywhere in [payload] (sorted, unique, exact-case). Empty means it is safe to send.
List<String> hiddenLeaks(Object? payload, Iterable<String> hiddenKeys) {
  final Set<String> keys = hiddenKeys.toSet();
  final Set<String> found = <String>{};
  void walk(Object? x, int depth) {
    if (depth > maxPayloadDepth + 4) return;
    if (x is List) {
      for (final Object? e in x) {
        walk(e, depth + 1);
      }
    } else if (x is Map) {
      for (final MapEntry<dynamic, dynamic> e in x.entries) {
        final String k = e.key.toString();
        if (keys.contains(k)) found.add(k);
        walk(e.value, depth + 1);
      }
    }
  }

  walk(payload, 0);
  return found.toList()..sort();
}
