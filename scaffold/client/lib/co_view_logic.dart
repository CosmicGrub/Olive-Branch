// OLIVE BRANCH — co-viewing ("Read together" / "Watch together"), pure logic.
// A 1:1 semantic port of packages/co-view/src/coview.ts, kept close to the TS
// original (same names, same shapes, same ordering) so the two stay auditable
// side by side — the same discipline palette_logic.dart applies to palette.ts.
// Design: docs/superpowers/specs/2026-11-07-co-viewing-design.md.
//
// Nothing here touches a socket, a timer, a clock or a widget. Every function
// takes the time as an argument. client/test/co_view_logic_test.dart runs this
// file against packages/co-view/test/vectors.json, which the TypeScript engine
// generates, so a change to either side that the other does not follow fails.
//
//  C1  Only a guardian may LEAD. A child principal is follower-only.
//  C2  Every inbound message is untrusted: parsed, size-capped, range-checked.
//  C3  Messages are sequence-numbered; a stale or replayed seq is ignored, which
//      is what makes a mid-session switch of transport safe.
//  C4  The daily time is the guardians' to change, bounded, and a raise is
//      always surfaced to the other guardian.
import 'dart:convert';
import 'dart:math' as math;

// ============================================================== constants ==
const double deadZoneS = 0.15;
const double hardSeekS = 2.0;
const double rateBand = 0.05;
const int tickS = 2;
const int tickStaleMs = 6 * tickS * 1000;
const int maxMessageBytes = 512;
const double maxPositionS = 24 * 3600.0;
const int defaultAllowanceMin = 120;
const int minAllowanceMin = 0;
/// Provisional (8 h) pending the owner's review, exactly as in coview.ts.
const int maxAllowanceMin = 480;
const int lastOneMin = 10;

// ================================================================ messages ==
sealed class CoViewMsg {
  const CoViewMsg(this.seq);
  final int seq;
  Map<String, Object?> toJson();
}

class TickMsg extends CoViewMsg {
  const TickMsg({required int seq, required this.pos, required this.rate, required this.paused, required this.sentAt}) : super(seq);
  final double pos, rate, sentAt;
  final bool paused;
  @override
  Map<String, Object?> toJson() => {'t': 'tick', 'seq': seq, 'pos': pos, 'rate': rate, 'paused': paused, 'sentAt': sentAt};
}

class SeekMsg extends CoViewMsg {
  const SeekMsg({required int seq, required this.pos, required this.sentAt}) : super(seq);
  final double pos, sentAt;
  @override
  Map<String, Object?> toJson() => {'t': 'seek', 'seq': seq, 'pos': pos, 'sentAt': sentAt};
}

class StartMsg extends CoViewMsg {
  const StartMsg({required int seq, required this.at, required this.assetId}) : super(seq);
  final double at;
  final String assetId;
  @override
  Map<String, Object?> toJson() => {'t': 'start', 'seq': seq, 'at': at, 'assetId': assetId};
}

enum StopBy { guardian, child, budget }

class StopMsg extends CoViewMsg {
  const StopMsg({required int seq, required this.by}) : super(seq);
  final StopBy by;
  @override
  Map<String, Object?> toJson() => {'t': 'stop', 'seq': seq, 'by': by.name};
}

/// The follower's answer to an invitation: she tapped Join. Carries nothing else.
class JoinMsg extends CoViewMsg {
  const JoinMsg({required int seq}) : super(seq);
  @override
  Map<String, Object?> toJson() => {'t': 'join', 'seq': seq};
}

enum ParseFailure { tooLarge, notJson, notObject, badType, badField }

String parseFailureName(ParseFailure f) => switch (f) {
      ParseFailure.tooLarge => 'too_large',
      ParseFailure.notJson => 'not_json',
      ParseFailure.notObject => 'not_object',
      ParseFailure.badType => 'bad_type',
      ParseFailure.badField => 'bad_field',
    };

class ParseResult {
  const ParseResult.ok(this.msg) : failure = null;
  const ParseResult.fail(this.failure) : msg = null;
  final CoViewMsg? msg;
  final ParseFailure? failure;
  bool get ok => msg != null;
}

final RegExp _assetId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool _isNum(Object? v) => v is num && v.isFinite;
bool _seqOk(Object? v) => v is num && v.isFinite && v == v.truncate() && v >= 0 && v <= 9007199254740991;
bool _posOk(Object? v) => _isNum(v) && (v as num) >= 0 && v <= maxPositionS;

/// C2: parse an untrusted wire message. Never throws.
ParseResult parseCoViewMessage(Object? raw) {
  Object? o = raw;
  if (raw is String) {
    if (utf8.encode(raw).length > maxMessageBytes) return const ParseResult.fail(ParseFailure.tooLarge);
    try {
      o = jsonDecode(raw);
    } catch (_) {
      return const ParseResult.fail(ParseFailure.notJson);
    }
  }
  if (o is! Map) return const ParseResult.fail(ParseFailure.notObject);
  const bad = ParseResult.fail(ParseFailure.badField);
  final m = o;
  if (!_seqOk(m['seq'])) return bad;
  final seq = (m['seq'] as num).toInt();
  switch (m['t']) {
    case 'tick':
      final rate = m['rate'];
      if (!_posOk(m['pos']) || !_isNum(rate) || (rate as num) < 0.5 || rate > 2 || m['paused'] is! bool || !_isNum(m['sentAt'])) return bad;
      return ParseResult.ok(TickMsg(seq: seq, pos: (m['pos'] as num).toDouble(), rate: rate.toDouble(), paused: m['paused'] as bool, sentAt: (m['sentAt'] as num).toDouble()));
    case 'seek':
      if (!_posOk(m['pos']) || !_isNum(m['sentAt'])) return bad;
      return ParseResult.ok(SeekMsg(seq: seq, pos: (m['pos'] as num).toDouble(), sentAt: (m['sentAt'] as num).toDouble()));
    case 'start':
      final id = m['assetId'];
      if (!_isNum(m['at']) || id is! String || !_assetId.hasMatch(id)) return bad;
      return ParseResult.ok(StartMsg(seq: seq, at: (m['at'] as num).toDouble(), assetId: id));
    case 'join':
      return ParseResult.ok(JoinMsg(seq: seq));
    case 'stop':
      final by = m['by'];
      final parsed = StopBy.values.where((b) => b.name == by).firstOrNull;
      if (by is! String || parsed == null) return bad;
      return ParseResult.ok(StopMsg(seq: seq, by: parsed));
    default:
      return const ParseResult.fail(ParseFailure.badType);
  }
}

// ============================================================ authorization ==
class Principal {
  const Principal({required this.kind, this.role});
  /// 'guardian' | 'child' | 'adult'
  final String kind;
  final String? role;
}

/// C1: who may lead. Guardian principals only; everything else follows. Fail closed.
bool canLead(Principal? p) => p != null && p.kind == 'guardian' && (p.role == null || p.role == 'guardian');

/// TS name: mayEmit. Renamed here because flutter_test exports a matcher called `mayEmit`.
bool principalMayEmit(Principal? p, CoViewMsg msg) {
  if (canLead(p)) return true;
  // A follower may answer an invitation (join) or end her own view; nothing else.
  return p != null && p.kind == 'child' && (msg is JoinMsg || (msg is StopMsg && msg.by == StopBy.child));
}

// ============================================================ sequencing ==
class SeqState {
  int last = -1;
}

/// C3: accept only strictly increasing seq. Mutates [s] only when the message is fresh.
bool acceptSeq(SeqState s, num seq) {
  if (!seq.isFinite || seq != seq.truncate() || seq <= s.last) return false;
  s.last = seq.toInt();
  return true;
}

// =========================================================== clock offset ==
class PingSample {
  const PingSample(this.offsetMs, this.rttMs);
  final double offsetMs, rttMs;
}

PingSample? sampleFromPing(double t0, double t1, double t2, double t3) {
  if (![t0, t1, t2, t3].every((v) => v.isFinite)) return null;
  final rtt = (t3 - t0) - (t2 - t1);
  if (rtt < 0) return null;
  return PingSample(((t1 - t0) + (t2 - t3)) / 2, rtt);
}

class OffsetEstimate {
  const OffsetEstimate(this.offsetMs, this.rttMs, this.samples);
  final double offsetMs, rttMs;
  final int samples;
}

/// The minimum-RTT sample, needing at least 3 usable ones; otherwise null.
OffsetEstimate? estimateOffset(List<PingSample?> samples) {
  final ok = samples.whereType<PingSample>().toList();
  if (ok.length < 3) return null;
  final best = ok.reduce((a, b) => b.rttMs < a.rttMs ? b : a);
  return OffsetEstimate(best.offsetMs, best.rttMs, ok.length);
}

// =========================================================== drift control ==
class CorrectCfg {
  const CorrectCfg({this.dead = deadZoneS, this.seek = hardSeekS, this.band = rateBand});
  final double dead, seek, band;
}

enum CorrectionAction { none, rate, seek }

class Correction {
  const Correction(this.action, [this.rate]);
  final CorrectionAction action;
  final double? rate;
}

/// `err` = followerPos - expectedPos in seconds (positive = ahead). Dead zone:
/// nothing. Soft zone: nudge the rate by half the error, clamped to the band
/// (bang-bang with the default zones, as coview.ts documents). Beyond the seek
/// threshold, or an unknowable error: hard seek.
Correction correct(double err, [CorrectCfg cfg = const CorrectCfg()]) {
  if (!err.isFinite) return const Correction(CorrectionAction.seek);
  final a = err.abs();
  if (a > cfg.seek) return const Correction(CorrectionAction.seek);
  if (a <= cfg.dead) return const Correction(CorrectionAction.none);
  final nudge = math.max(-cfg.band, math.min(cfg.band, err * 0.5));
  return Correction(CorrectionAction.rate, 1 - nudge);
}

double expectedPosition(TickMsg tick, double nowMs, double offsetMs) {
  if (tick.paused) return tick.pos;
  final leaderNowMs = nowMs + offsetMs;
  final elapsedS = math.max(0.0, (leaderNowMs - tick.sentAt) / 1000);
  return tick.pos + tick.rate * elapsedS;
}

enum FollowerKind { none, pause, rate, seek }

class FollowerAction {
  const FollowerAction(this.kind, {this.rate, this.to});
  final FollowerKind kind;
  final double? rate, to;
}

/// One follower decision. A tick older than [tickStaleMs] is not steered by.
FollowerAction followerStep({
  required TickMsg? tick,
  required double receivedAtMs,
  required double nowMs,
  required double localPos,
  required double offsetMs,
  CorrectCfg cfg = const CorrectCfg(),
}) {
  if (tick == null) return const FollowerAction(FollowerKind.none);
  if (nowMs - receivedAtMs > tickStaleMs) return const FollowerAction(FollowerKind.none);
  if (tick.paused) {
    return (localPos - tick.pos).abs() > cfg.dead
        ? FollowerAction(FollowerKind.seek, to: tick.pos)
        : const FollowerAction(FollowerKind.pause);
  }
  final expected = expectedPosition(tick, nowMs, offsetMs);
  final c = correct(localPos - expected, cfg);
  switch (c.action) {
    case CorrectionAction.seek:
      return FollowerAction(FollowerKind.seek, to: expected);
    case CorrectionAction.rate:
      return FollowerAction(FollowerKind.rate, rate: c.rate);
    case CorrectionAction.none:
      return const FollowerAction(FollowerKind.none);
  }
}

// ============================================================== allowance ==
enum AllowanceDirection { raise, lower, same, rejected }
enum AllowanceRejection { notAGuardian, notANumber, aboveCeiling, belowFloor }

String allowanceRejectionName(AllowanceRejection r) => switch (r) {
      AllowanceRejection.notAGuardian => 'not_a_guardian',
      AllowanceRejection.notANumber => 'not_a_number',
      AllowanceRejection.aboveCeiling => 'above_ceiling',
      AllowanceRejection.belowFloor => 'below_floor',
    };

class AllowanceChange {
  const AllowanceChange({required this.ok, required this.limitMin, required this.direction, required this.notifyCoGuardian, this.reason});
  final bool ok;
  final int limitMin;
  final AllowanceDirection direction;
  final bool notifyCoGuardian;
  final AllowanceRejection? reason;
}

/// C4: a guardian changes the daily limit. Bounded; a raise is flagged for the co-guardian.
AllowanceChange changeAllowance(Principal? actor, int currentMin, Object? requestedMin) {
  AllowanceChange rej(AllowanceRejection r) => AllowanceChange(
      ok: false, limitMin: currentMin, direction: AllowanceDirection.rejected, notifyCoGuardian: false, reason: r);
  if (!canLead(actor)) return rej(AllowanceRejection.notAGuardian);
  if (requestedMin is! num || !requestedMin.isFinite || requestedMin != requestedMin.truncate()) {
    return rej(AllowanceRejection.notANumber);
  }
  final r = requestedMin.toInt();
  if (r < minAllowanceMin) return rej(AllowanceRejection.belowFloor);
  if (r > maxAllowanceMin) return rej(AllowanceRejection.aboveCeiling);
  final dir = r > currentMin ? AllowanceDirection.raise : (r < currentMin ? AllowanceDirection.lower : AllowanceDirection.same);
  return AllowanceChange(ok: true, limitMin: r, direction: dir, notifyCoGuardian: dir == AllowanceDirection.raise);
}

enum BudgetState { off, ok, lastOne, exhausted }

String budgetStateName(BudgetState s) => switch (s) {
      BudgetState.off => 'off',
      BudgetState.ok => 'ok',
      BudgetState.lastOne => 'last_one',
      BudgetState.exhausted => 'exhausted',
    };

/// `usedS` is the child's total co-viewing seconds today across BOTH households.
BudgetState budgetState(int limitMin, num usedS) {
  if (limitMin <= 0) return BudgetState.off;
  final remainingS = limitMin * 60 - math.max(0, usedS);
  if (remainingS <= 0) return BudgetState.exhausted;
  if (remainingS <= lastOneMin * 60) return BudgetState.lastOne;
  return BudgetState.ok;
}

num remainingSeconds(int limitMin, num usedS) =>
    math.max(0, math.max(0, limitMin) * 60 - math.max(0, usedS));

// ============================================================== transport ==
enum TransportKind { livekit, table, none }

TransportKind chooseTransport({required bool callConnected, required bool tableAvailable}) {
  if (callConnected) return TransportKind.livekit;
  if (tableAvailable) return TransportKind.table;
  return TransportKind.none;
}

TickMsg reannounce({required double pos, required double rate, required bool paused, required int lastSeq, required double nowMs}) =>
    TickMsg(seq: lastSeq + 1, pos: pos, rate: rate, paused: paused, sentAt: nowMs);

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
