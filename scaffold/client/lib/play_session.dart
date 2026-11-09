// No longer UNVERIFIED — verified by CI (client/test/play_session_test.dart and the per-game two-device tests).
// OLIVE BRANCH — the session controller every ad-hoc "Play together" game runs under. It owns the conversation
// between two devices so no game has to: the envelope (play_envelope.dart), order and resend, hello and resume,
// the calm away and ended notices, rematch, the quiet desync check, and the dealer's save. A game is a [PlayGame]
// (play_game.dart); the transport is a [PlayTransport] (play_transport.dart), real or in-memory.
//
// HOW A CONVERSATION GOES
//  1. Whenever the other device is reachable (at the start, and every time it comes back) each side says `hello`.
//     The dealing device (the authority) mints a fresh session id when it starts and answers a guest's hello
//     with its own hello and, if a game is under way, the current state for that seat.
//  2. A guest that has no game (or heard a new session id) asks `req_state`. A guest's move is a `move`; the
//     authority applies it and ALWAYS answers with the state, accepted or refused, so nobody is stranded on a
//     spinner (the Uno bug found in review, now a rule of the controller rather than a remark in one file).
//  3. Moves are kept until acknowledged and resent when the other device returns (the old sendTurn simply
//     returned when the peer was lost, so the move vanished). A skipped message is held back and the receiver asks
//     for the state; a duplicate or old one is dropped.
//  4. A state may carry a digest of the public view. A mismatch quietly asks for the state again; nobody is told.
//     After three tries in a row it stops asking, so a game that cannot agree with itself cannot loop.
//  5. Away is a notice, not an error, and it never ends the game: the game is simply waiting. Ended happens only by
//     choice (`bye`) or after a long quiet that is never shown as a clock.
//  6. The authority saves the game after each committed change (a finished game clears the save instead, so an
//     outcome is never kept), and can rebuild from it after the OS has killed the app. The other device saves nothing.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'live_games.dart' show auditLiveView;
import 'play_envelope.dart';
import 'play_game.dart';
import 'play_notice.dart';
import 'play_save.dart';
import 'play_transport.dart';

enum PlayRematch { none, asked, offered }

class PlaySessionController extends ChangeNotifier implements PlayLink {
  PlaySessionController({
    required this.spec,
    required this.game,
    required this.transport,
    this.store,
    List<int> Function()? sidBytes,
    this.quietEndAfter = const Duration(minutes: 30),
    this.onLegacy,
    Timer Function(Duration, void Function())? timerFactory,
  })  : _makeTimer = timerFactory ?? Timer.new,
        ctx = game.ctx {
    session = PlayEnvelopeSession(
      role: ctx.isAuthority ? PlayRole.authority : PlayRole.guest,
      mySeat: transport.mySeat,
      authoritySeat: ctx.authoritySeatId,
      sid: ctx.isAuthority ? makeSid((sidBytes ?? _secureBytes)()) : '',
    );
    game.link = this;
  }

  static List<int> _secureBytes() {
    final Random r = Random.secure();
    return <int>[for (int i = 0; i < 8; i++) r.nextInt(256)];
  }

  final PlayGameSpec spec;
  final PlayGame game;
  final PlayTransport transport;
  final PlayContext ctx;
  final PlaySaveStore? store;

  /// How long the other device may be away before the screen says the game has finished for now. Never shown as a
  /// countdown, and the saved game is kept. Null turns it off.
  final Duration? quietEndAfter;
  final Timer Function(Duration, void Function()) _makeTimer;

  /// The one-release shim for the old, un-enveloped dialects: called with the raw message when it has no `v`.
  final void Function(Map<String, dynamic> raw)? onLegacy;

  late final PlayEnvelopeSession session;
  StreamSubscription<PlayInbound>? _inSub;
  StreamSubscription<PeerPresence>? _presSub;
  Timer? _quietTimer;
  bool _disposed = false;

  PlayNoticeKind _notice = PlayNoticeKind.none;
  PlayNoticeKind get notice => _notice;

  bool _everPresent = false;

  /// The other device has been reachable at least once this session (so "away" means something).
  bool get hasMetPeer => _everPresent;

  bool _endedForGood = false;
  bool get endedForGood => _endedForGood;

  PlayRematch _rematch = PlayRematch.none;
  PlayRematch get rematch => _rematch;

  int _resyncs = 0;

  /// Why inbound messages were dropped, newest last (capped). For tests and debugging only; never shown.
  final List<String> rejected = <String>[];

  /// States the controller refused to send because they carried hidden information. Should always be 0.
  int blockedSends = 0;

  /// How many bots the game may drive right now: none, unless this device is the authority.
  bool get mayRunBots => ctx.isAuthority;

  PeerPresence get presence => transport.currentPresence;

  void _reject(String why) {
    rejected.add(why);
    if (rejected.length > 50) rejected.removeAt(0);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    _inSub = transport.incoming.listen(_onInbound);
    _presSub = transport.presence.listen(_onPresence);
    if (transport.currentPresence == PeerPresence.present) {
      _everPresent = true;
      unawaited(_announce());
    } else {
      _notice = PlayNoticeKind.away;
      _armQuiet();
    }
  }

  // ------------------------------------------------------------- presence --
  void _onPresence(PeerPresence p) {
    if (_endedForGood) return;
    if (p == PeerPresence.away) {
      _notice = PlayNoticeKind.away;
      _armQuiet();
      _changed();
    } else {
      _everPresent = true;
      _quietTimer?.cancel();
      _notice = PlayNoticeKind.none;
      _changed();
      unawaited(_announce());
    }
  }

  void _armQuiet() {
    _quietTimer?.cancel();
    final Duration? d = quietEndAfter;
    if (d == null) return;
    _quietTimer = _makeTimer(d, () {
      if (_disposed || _endedForGood || transport.currentPresence == PeerPresence.present) return;
      _notice = PlayNoticeKind.ended;
      _changed();
    });
  }

  Future<void> _announce() async {
    await _sendEnv(session.stamp(PlayKind.hello, spec.id, p: <String, dynamic>{'resume': session.sid.isNotEmpty && game.started}));
    if (ctx.isAuthority && game.started) {
      await _resendRetained(); // anything kept goes first, so a newer state never overtakes an older ordered message
      await _sendState();
    }
  }

  // ------------------------------------------------------------- sending --
  Future<bool> _sendEnv(PlayEnvelope e) => transport.send(e.toJson());

  Future<void> _resendRetained() async {
    for (final PlayEnvelope e in session.pendingResend()) {
      // A message kept from before the dealer restarted is sent under the session it is now in.
      await _sendEnv(PlayEnvelope(sid: session.sid, n: e.n, ack: session.lastPeerN, t: e.t, g: e.g, p: e.p, d: e.d));
    }
  }

  @override
  Future<void> sendMove(Map<String, dynamic> payload) async {
    if (_endedForGood) return;
    if (!auditLiveView(payload).ok) {
      debugPrint('play_session: refusing to send a move with forbidden keys');
      return;
    }
    await _sendEnv(session.stamp(PlayKind.move, spec.id, p: payload));
  }

  @override
  Future<void> broadcastState() async {
    if (!ctx.isAuthority || _endedForGood) return;
    await _sendState();
    await _persist();
  }

  Future<void> _sendState() async {
    final Map<String, dynamic>? payload = game.stateFor(transport.peerSeat);
    if (payload == null) return;
    // The hidden-information rule (E6): a state sent to the other device never carries what this one must keep.
    if (hiddenLeaks(payload, spec.allHiddenKeys).isNotEmpty || !auditLiveView(payload).ok) {
      blockedSends++;
      debugPrint('play_session: refusing to send a state that carries hidden or forbidden keys');
      return;
    }
    await _sendEnv(session.stamp(PlayKind.state, spec.id, p: payload, d: stateDigest(game.publicDigestInput())));
  }

  Future<void> _requestState() async {
    await _sendEnv(session.stamp(PlayKind.reqState, spec.id));
  }

  // ------------------------------------------------------------ receiving --
  Future<void> _onInbound(PlayInbound inbound) async {
    if (_disposed) return;
    final ParsedEnvelope parsed = parsePlayEnvelope(inbound.raw);
    if (!parsed.ok) {
      final ParseFailure f = parsed.failure!;
      if (f == ParseFailure.legacy) {
        final Object? raw = inbound.raw;
        if (raw is Map<String, dynamic>) onLegacy?.call(raw);
        _reject('legacy');
      } else if (f == ParseFailure.unsupportedVersion) {
        // The other device speaks a newer version than this one understands. Say nothing alarming; the game has
        // finished for now. (One release of overlap, so this is only ever a version too far ahead.)
        _reject('unsupported_version');
        _endForGood();
      } else {
        _reject(f.wire);
      }
      return;
    }
    final PlayEnvelope env = parsed.env!;
    if (env.g != spec.id) {
      _reject('wrong_game');
      return;
    }
    if (_endedForGood) return;
    final PlayVerdict v = session.receive(env, inbound.senderSeat);
    if (!v.accept) {
      _reject(v.reason ?? 'refused');
      // Ask once per gap. Without this a message that can never be filled is asked about for ever.
      if (v.needState && _gapAskedAt != session.lastPeerN) {
        _gapAskedAt = session.lastPeerN;
        await _requestState();
      }
      return;
    }
    if (!v.control) _gapAskedAt = -1;
    switch (env.t) {
      case PlayKind.hello:
        await _onHello(env);
      case PlayKind.reqState:
        // Kept messages first (so a newer state never overtakes an older ordered one), then where the game stands.
        await _resendRetained();
        if (ctx.isAuthority) {
          if (game.started) await _sendState();
        } else {
          await _rebaseIfLost(env.ack);
        }
      case PlayKind.state:
        await _onState(env);
      case PlayKind.move:
        await _onMove(env, inbound.senderSeat);
      case PlayKind.bye:
        _endForGood();
      case PlayKind.rematch:
        await _onRematch();
      case PlayKind.rematchOk:
        await _onRematchOk();
    }
  }

  String _lastHelloSid = '';
  int _gapAskedAt = -1;

  Future<void> _onHello(PlayEnvelope env) async {
    if (ctx.isAuthority) {
      // A guest is here (again). Tell it which session this is and, if a game is under way, where it stands.
      await _sendEnv(session.stamp(PlayKind.hello, spec.id, p: <String, dynamic>{'resume': game.started}));
      await _resendRetained();
      if (game.started) await _sendState();
      return;
    }
    final bool newSession = session.sid != _lastHelloSid;
    _lastHelloSid = session.sid;
    if (newSession) {
      // A new dealer session: say hello back so it counts us from here, and ask where the game stands.
      await _sendEnv(session.stamp(PlayKind.hello, spec.id, p: <String, dynamic>{'resume': game.started}));
    }
    if (newSession || !game.started) await _requestState();
    await _resendRetained();
  }

  /// The dealer is missing a message of ours that we no longer have (more than [maxUnacked] piled up while it was
  /// away). Start counting afresh from here; the dealer answers with where the game stands, which is the truth.
  Future<void> _rebaseIfLost(int peerHasSeen) async {
    if (!session.overflowed) return;
    if (session.unacked.isNotEmpty && session.unacked.first.n == peerHasSeen + 1) return;
    session.overflowed = false;
    session.unacked = <PlayEnvelope>[];
    await _sendEnv(PlayEnvelope(sid: '', n: session.sendN, ack: session.lastPeerN, t: PlayKind.hello, g: spec.id,
        p: <String, dynamic>{'resume': false}));
  }

  Future<void> _onState(PlayEnvelope env) async {
    if (ctx.isAuthority) return; // only the dealer holds the truth; the envelope already refused a guest's state
    if (!game.applyState(env.p!)) {
      _reject('bad_state');
      return;
    }
    final String? theirs = env.d;
    if (theirs != null) {
      final String? mine = stateDigest(game.publicDigestInput());
      if (mine != null && mine != theirs) {
        // The two views disagree: quietly ask again, a few times at most. No alarm, nothing shown.
        if (_resyncs < 3) {
          _resyncs++;
          await _requestState();
        }
      } else {
        _resyncs = 0;
      }
    }
    if (!game.finished && _rematch != PlayRematch.none) _rematch = PlayRematch.none;
    _changed();
  }

  Future<void> _onMove(PlayEnvelope env, String senderSeat) async {
    final PlayMoveOutcome o = game.onMove(senderSeat, env.p!);
    if (o == PlayMoveOutcome.refused) _reject('move_refused');
    if (spec.authorityModel && ctx.isAuthority) await broadcastState(); // always answer, accepted or not
    _changed();
  }

  // --------------------------------------------------------------- rematch --
  /// Either side may ask once the game is finished. The other side chooses.
  Future<void> askRematch() async {
    if (!game.finished || _rematch != PlayRematch.none || _endedForGood) return;
    _rematch = PlayRematch.asked;
    _changed();
    await _sendEnv(session.stamp(PlayKind.rematch, spec.id));
  }

  /// "Never mind": quietly forget the ask on this side. The other side is not told anything.
  void cancelRematchAsk() {
    if (_rematch == PlayRematch.asked) {
      _rematch = PlayRematch.none;
      _changed();
    }
  }

  /// The other side asked and this side says yes.
  Future<void> acceptRematch() async {
    if (_rematch != PlayRematch.offered || !game.finished) return;
    await _sendEnv(session.stamp(PlayKind.rematchOk, spec.id));
    if (ctx.isAuthority) {
      await _doRematch();
    } else {
      _rematch = PlayRematch.none;
      _changed();
    }
  }

  /// "Not now": quietly forget the offer on this side. The other side is not told anything.
  void declineRematch() {
    if (_rematch == PlayRematch.offered) {
      _rematch = PlayRematch.none;
      _changed();
    }
  }

  Future<void> _onRematch() async {
    // Honoured only after a finished game (GameSuite let a PlayAgain through at any time).
    if (!game.finished) {
      _reject('rematch_not_finished');
      return;
    }
    if (_rematch == PlayRematch.asked) {
      // Both asked: that is a yes.
      await _sendEnv(session.stamp(PlayKind.rematchOk, spec.id));
      if (ctx.isAuthority) await _doRematch();
      return;
    }
    _rematch = PlayRematch.offered;
    _changed();
  }

  Future<void> _onRematchOk() async {
    if (!game.finished || _rematch != PlayRematch.asked) {
      _reject('rematch_ok_unasked');
      return;
    }
    if (ctx.isAuthority) await _doRematch();
  }

  Future<void> _doRematch() async {
    game.startRematch();
    _rematch = PlayRematch.none;
    _changed();
    await broadcastState();
  }

  // ------------------------------------------------------------------ end --
  /// The grown-up chose "Finish for now": tell the other device and clear the save.
  Future<void> finishForNow() async {
    if (_endedForGood) return;
    await _sendEnv(session.stamp(PlayKind.bye, spec.id));
    _endForGood();
  }

  void _endForGood() {
    if (_endedForGood) return;
    _endedForGood = true;
    _quietTimer?.cancel();
    _notice = PlayNoticeKind.ended;
    if (ctx.isAuthority) unawaited(store?.clear(spec.id));
    _changed();
  }

  // ----------------------------------------------------------------- save --
  Future<void> _persist() async {
    final PlaySaveStore? s = store;
    if (s == null || !spec.saveable || !ctx.isAuthority) return;
    final Map<String, dynamic>? snap = game.finished ? null : game.snapshot();
    if (snap == null) {
      await s.clear(spec.id); // a finished or empty game is cleared, never kept as a result
    } else {
      await s.save(spec.id, snap);
    }
  }

  /// Authority: there is a saved game of this kind on this phone.
  Future<bool> hasSavedGame() async => ctx.isAuthority && spec.saveable && store != null && await store!.load(spec.id) != null;

  /// Authority: carry on from the save. False (and nothing changed) if it is stale or damaged.
  Future<bool> resumeSavedGame() async {
    final PlaySaveStore? s = store;
    if (s == null || !ctx.isAuthority || !spec.saveable) return false;
    final Map<String, dynamic>? snap = await s.load(spec.id);
    if (snap == null) return false;
    final bool ok = game.restore(snap);
    if (!ok) await s.clear(spec.id);
    if (ok) {
      _changed();
      if (transport.currentPresence == PeerPresence.present) await _announce();
    }
    return ok;
  }

  /// Authority: the grown-up chose to start a new one instead of carrying on.
  Future<void> discardSavedGame() async => store?.clear(spec.id);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _quietTimer?.cancel();
    unawaited(_inSub?.cancel());
    unawaited(_presSub?.cancel());
    super.dispose();
  }
}
