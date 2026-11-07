// OLIVE BRANCH — co-viewing sessions: the leader (a guardian) and the follower
// (the child's device), as plain ChangeNotifiers over an abstract transport.
// Design: docs/superpowers/specs/2026-11-07-co-viewing-design.md.
//
// Pure of widgets and of platform channels, so it is tested with an in-memory
// loopback transport. The real transports (the call data channel and the
// game-sync table) implement [CoViewTransport] in a later wave; the sender's
// authenticated Principal arrives WITH each message, supplied by the transport
// from the verified session, never read from the message body. That is what
// makes C1 ("only a guardian may lead") enforceable on the receiving device as
// well as on the server.
//
// For "Read together" the `pos` field of seek and tick carries the PAGE INDEX
// (the design's prototype did the same); "Watch together" will carry seconds.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'co_view_logic.dart';

class InboundCoView {
  const InboundCoView(this.msg, this.sender);
  final CoViewMsg msg;
  final Principal sender;
}

abstract class CoViewTransport {
  Stream<InboundCoView> get incoming;
  void send(CoViewMsg msg);
  TransportKind get kind;
}

/// An in-memory transport pair for tests and the offline demo: whatever one end
/// sends arrives at the other tagged with the sender's principal.
class LoopbackTransport implements CoViewTransport {
  LoopbackTransport._(this.me, this.kind);
  final Principal me;
  @override
  final TransportKind kind;
  late LoopbackTransport _peer;
  final StreamController<InboundCoView> _in = StreamController<InboundCoView>.broadcast(sync: true);

  static (LoopbackTransport, LoopbackTransport) pair(Principal a, Principal b, {TransportKind kind = TransportKind.table}) {
    final x = LoopbackTransport._(a, kind), y = LoopbackTransport._(b, kind);
    x._peer = y;
    y._peer = x;
    return (x, y);
  }

  /// Messages sent by either end, in order, for assertions.
  final List<CoViewMsg> sent = [];

  @override
  Stream<InboundCoView> get incoming => _in.stream;
  @override
  void send(CoViewMsg msg) {
    sent.add(msg);
    _peer._in.add(InboundCoView(msg, me));
  }
}

class CoViewStoryPage {
  const CoViewStoryPage(this.text);
  final String text;
}

class CoViewStory {
  const CoViewStory({required this.id, required this.title, required this.pages});
  final String id;
  final String title;
  final List<CoViewStoryPage> pages;
}

enum CoViewPhase { idle, waiting, live, ended }

/// Why a session ended, from the point of view of the one reading about it.
enum CoViewEnding { guardian, child, budget, declined }

// ================================================================== leader ==
class CoViewLeader extends ChangeNotifier {
  CoViewLeader({
    required this._transport,
    required this.me,
    required this.story,
    required this._limitMin,
    required int usedSeconds,
    required double Function() nowMs,
  })  : _usedS = usedSeconds,
        _now = nowMs {
    _listen();
  }

  CoViewTransport _transport;
  StreamSubscription<InboundCoView>? _sub;
  final Principal me;
  final CoViewStory story;
  final double Function() _now;
  final SeqState _inSeq = SeqState();
  int _limitMin;
  int _usedS;
  int _seq = -1;
  CoViewPhase phase = CoViewPhase.idle;
  CoViewEnding? ending;
  int page = 0;
  /// Set when a start was refused, so the screen can say why.
  BudgetState? blockedBy;

  int get limitMin => _limitMin;
  int get usedSeconds => _usedS;
  BudgetState get budget => budgetState(_limitMin, _usedS);
  num get remainingS => remainingSeconds(_limitMin, _usedS);
  TransportKind get transportKind => _transport.kind;

  int _next() => ++_seq;
  void _send(CoViewMsg m) => _transport.send(m);

  void _listen() {
    _sub?.cancel();
    _sub = _transport.incoming.listen((e) {
      if (!acceptSeq(_inSeq, e.msg.seq)) return; // C3
      // The leader only ever accepts a follower's own two words.
      if (!principalMayEmit(e.sender, e.msg) || canLead(e.sender)) return;
      final m = e.msg;
      if (m is JoinMsg && phase == CoViewPhase.waiting) {
        phase = CoViewPhase.live;
        _send(TickMsg(seq: _next(), pos: page.toDouble(), rate: 1, paused: false, sentAt: _now()));
        notifyListeners();
      } else if (m is StopMsg && m.by == StopBy.child && (phase == CoViewPhase.waiting || phase == CoViewPhase.live)) {
        _end(phase == CoViewPhase.waiting ? CoViewEnding.declined : CoViewEnding.child, send: false);
      }
    });
  }

  /// Send the invitation. Refused (and nothing sent) when this principal may not
  /// lead, or when today's time is off or used up.
  bool start() {
    if (!canLead(me)) throw StateError('only a guardian may start a co-viewing session');
    final b = budget;
    if (b == BudgetState.off || b == BudgetState.exhausted) {
      blockedBy = b;
      notifyListeners();
      return false;
    }
    blockedBy = null;
    page = 0;
    phase = CoViewPhase.waiting;
    _send(StartMsg(seq: _next(), at: _now() + 3000, assetId: story.id));
    notifyListeners();
    return true;
  }

  void _turn(int to) {
    if (phase != CoViewPhase.live) return;
    final clamped = to.clamp(0, story.pages.length - 1);
    if (clamped == page) return;
    page = clamped;
    _send(SeekMsg(seq: _next(), pos: page.toDouble(), sentAt: _now()));
    notifyListeners();
  }

  void nextPage() => _turn(page + 1);
  void prevPage() => _turn(page - 1);

  void end() => _end(CoViewEnding.guardian, send: true);

  void _end(CoViewEnding why, {required bool send}) {
    if (phase == CoViewPhase.ended) return;
    phase = CoViewPhase.ended;
    ending = why;
    if (send) {
      _send(StopMsg(seq: _next(), by: why == CoViewEnding.budget ? StopBy.budget : StopBy.guardian));
    }
    notifyListeners();
  }

  /// Time passes while the session is live. When the day's time runs out the
  /// leader ends it, with `by: budget`, so the child's goodbye is the right one.
  void spend(int seconds) {
    if (phase != CoViewPhase.live) return;
    _usedS += seconds;
    if (budget == BudgetState.exhausted) {
      _end(CoViewEnding.budget, send: true);
    } else {
      notifyListeners();
    }
  }

  /// C4. Returns the engine's verdict so the sheet can say what happened.
  AllowanceChange setAllowance(int requestedMin) {
    final r = changeAllowance(Principal(kind: me.kind, role: me.role), _limitMin, requestedMin);
    if (r.ok) {
      _limitMin = r.limitMin;
      // Switching it off, or lowering below what is already used, ends a live session.
      if (phase == CoViewPhase.live && (budget == BudgetState.off || budget == BudgetState.exhausted)) {
        _end(CoViewEnding.budget, send: true);
      } else {
        notifyListeners();
      }
    }
    return r;
  }

  /// The channel changed mid-session (a call started or ended): re-announce on the
  /// new one with a seq above everything sent so far. The follower keeps playing
  /// meanwhile, and a stale tick from the old channel is ignored (C3).
  void migrateTo(CoViewTransport next) {
    _transport = next;
    _listen();
    if (phase == CoViewPhase.live) {
      _send(reannounce(pos: page.toDouble(), rate: 1, paused: false, lastSeq: _seq, nowMs: _now()));
      _seq++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ================================================================ follower ==
class CoViewFollower extends ChangeNotifier {
  CoViewFollower({
    required this._transport,
    required this.me,
    required this.story,
    required this._budget,
  }) {
    _sub = _transport.incoming.listen(_onMessage);
  }

  final CoViewTransport _transport;
  late final StreamSubscription<InboundCoView> _sub;
  final Principal me;
  final CoViewStory story;
  final BudgetState Function() _budget;
  final SeqState _inSeq = SeqState();
  int _seq = -1;
  CoViewPhase phase = CoViewPhase.idle;
  CoViewEnding? ending;
  int page = 0;
  /// Messages that were refused, for tests and diagnostics. Never shown to her.
  int ignored = 0;

  /// "Last one for today", derived from the same per-child totals both devices
  /// can read. No number is ever shown to the child.
  bool get lastOne => phase == CoViewPhase.live && _budget() == BudgetState.lastOne;

  void _onMessage(InboundCoView e) {
    // C1: only a guardian steers this device. Anything else is dropped quietly.
    if (!canLead(e.sender)) {
      ignored++;
      return;
    }
    if (!acceptSeq(_inSeq, e.msg.seq)) {
      ignored++;
      return;
    }
    final m = e.msg;
    if (m is StartMsg) {
      if (m.assetId != story.id) {
        ignored++;
        return;
      }
      phase = CoViewPhase.waiting; // shown to her as the invitation
      page = 0;
      ending = null;
    } else if (m is SeekMsg && phase == CoViewPhase.live) {
      page = m.pos.round().clamp(0, story.pages.length - 1);
    } else if (m is TickMsg && phase == CoViewPhase.live) {
      page = m.pos.round().clamp(0, story.pages.length - 1);
    } else if (m is StopMsg && (phase == CoViewPhase.waiting || phase == CoViewPhase.live)) {
      phase = CoViewPhase.ended;
      ending = m.by == StopBy.budget ? CoViewEnding.budget : CoViewEnding.guardian;
    } else {
      return;
    }
    notifyListeners();
  }

  int _next() => ++_seq;

  /// She tapped Join.
  void join() {
    if (phase != CoViewPhase.waiting) return;
    phase = CoViewPhase.live;
    _transport.send(JoinMsg(seq: _next()));
    notifyListeners();
  }

  /// "Not now": nothing is shown as a refusal to the guardian beyond "not ready yet".
  void decline() {
    if (phase != CoViewPhase.waiting) return;
    phase = CoViewPhase.ended;
    ending = CoViewEnding.declined;
    _transport.send(StopMsg(seq: _next(), by: StopBy.child));
    notifyListeners();
  }

  /// "All done" — the one control a child always has.
  void allDone() {
    if (phase != CoViewPhase.live && phase != CoViewPhase.waiting) return;
    phase = CoViewPhase.ended;
    ending = CoViewEnding.child;
    _transport.send(StopMsg(seq: _next(), by: StopBy.child));
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
