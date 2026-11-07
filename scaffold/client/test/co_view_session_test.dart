// OLIVE BRANCH — co-viewing sessions: the leader and the follower talking over a
// loopback transport. Every rule from the design is a test: only a guardian
// leads, the child can only join, decline or end her own view, stale messages
// are ignored, time ends a session with the right goodbye, and the channel can
// change mid-story without losing the place.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/co_view_logic.dart';
import 'package:olive_client/co_view_session.dart';

const guardian = Principal(kind: 'guardian', role: 'guardian');
const child = Principal(kind: 'child');
const sitter = Principal(kind: 'adult', role: 'sitter');
const story = CoViewStory(id: 'owl-1', title: 'The owl and the moon', pages: [
  CoViewStoryPage('Far above the olive grove, a small owl asked the moon a big question.'),
  CoViewStoryPage('The moon smiled and glowed a little brighter.'),
  CoViewStoryPage('Down in the valley one small window glowed.'),
]);

class Rig {
  Rig({int limitMin = 120, int usedS = 0, BudgetState Function()? childBudget}) {
    final (g, c) = LoopbackTransport.pair(guardian, child);
    gt = g;
    ct = c;
    leader = CoViewLeader(transport: g, me: guardian, story: story, limitMin: limitMin, usedSeconds: usedS, nowMs: () => now);
    follower = CoViewFollower(transport: c, me: child, story: story, budget: childBudget ?? (() => leader.budget));
  }
  late final LoopbackTransport gt, ct;
  late final CoViewLeader leader;
  late final CoViewFollower follower;
  double now = 1000000;

  /// A session that is live: started, joined.
  Rig live() {
    leader.start();
    follower.join();
    return this;
  }
}

void main() {
  group('starting', () {
    test('start sends one start message and the follower is invited', () {
      final r = Rig();
      expect(r.leader.start(), isTrue);
      expect(r.leader.phase, CoViewPhase.waiting);
      expect(r.gt.sent.single, isA<StartMsg>());
      expect((r.gt.sent.single as StartMsg).assetId, 'owl-1');
      expect(r.follower.phase, CoViewPhase.waiting);
    });
    test('only a guardian may start: a child leader throws before anything is sent', () {
      final (g, _) = LoopbackTransport.pair(child, guardian);
      final bad = CoViewLeader(transport: g, me: child, story: story, limitMin: 120, usedSeconds: 0, nowMs: () => 0);
      expect(bad.start, throwsStateError);
      expect(g.sent, isEmpty);
    });
    test('a sitter may not start either', () {
      final (g, _) = LoopbackTransport.pair(sitter, child);
      final bad = CoViewLeader(transport: g, me: sitter, story: story, limitMin: 120, usedSeconds: 0, nowMs: () => 0);
      expect(bad.start, throwsStateError);
    });
    test('start is refused, and nothing is sent, when the daily time is off', () {
      final r = Rig(limitMin: 0);
      expect(r.leader.start(), isFalse);
      expect(r.leader.blockedBy, BudgetState.off);
      expect(r.leader.phase, CoViewPhase.idle);
      expect(r.gt.sent, isEmpty);
      expect(r.follower.phase, CoViewPhase.idle);
    });
    test('start is refused when today is used up', () {
      final r = Rig(usedS: 7200);
      expect(r.leader.start(), isFalse);
      expect(r.leader.blockedBy, BudgetState.exhausted);
      expect(r.gt.sent, isEmpty);
    });
    test('a start for a different story is ignored by the follower', () {
      final r = Rig();
      final other = CoViewFollower(transport: r.ct, me: child, story: const CoViewStory(id: 'other', title: 'x', pages: [CoViewStoryPage('a')]), budget: () => BudgetState.ok);
      r.leader.start();
      expect(other.phase, CoViewPhase.idle);
      expect(other.ignored, 1);
    });
  });

  group('joining and reading', () {
    test('Join takes the leader live and sends the first tick', () {
      final r = Rig()..live();
      expect(r.follower.phase, CoViewPhase.live);
      expect(r.leader.phase, CoViewPhase.live);
      expect(r.gt.sent.whereType<TickMsg>().length, 1);
      expect(r.ct.sent.single, isA<JoinMsg>());
    });
    test('Join is only meaningful in an invitation: a second Join sends nothing more', () {
      final r = Rig()..live();
      r.follower.join();
      expect(r.ct.sent.whereType<JoinMsg>().length, 1);
    });
    test('Join with no invitation does nothing', () {
      final r = Rig();
      r.follower.join();
      expect(r.follower.phase, CoViewPhase.idle);
      expect(r.ct.sent, isEmpty);
    });
    test('turning the page moves the follower, one seek per real change', () {
      final r = Rig()..live();
      r.leader.nextPage();
      expect(r.follower.page, 1);
      r.leader.nextPage();
      expect(r.follower.page, 2);
      expect(r.gt.sent.whereType<SeekMsg>().length, 2);
    });
    test('the last page clamps and sends nothing extra', () {
      final r = Rig()..live();
      r.leader.nextPage();
      r.leader.nextPage();
      final before = r.gt.sent.length;
      r.leader.nextPage();
      expect(r.leader.page, 2);
      expect(r.gt.sent.length, before);
    });
    test('back at the first page does nothing', () {
      final r = Rig()..live();
      final before = r.gt.sent.length;
      r.leader.prevPage();
      expect(r.leader.page, 0);
      expect(r.gt.sent.length, before);
    });
    test('page turns before she has joined go nowhere', () {
      final r = Rig();
      r.leader.start();
      r.leader.nextPage();
      expect(r.leader.page, 0);
      expect(r.gt.sent.whereType<SeekMsg>(), isEmpty);
    });
  });

  group('endings: each party, and what the other one is told', () {
    test('the guardian ends it: the follower hears guardian', () {
      final r = Rig()..live();
      r.leader.end();
      expect(r.leader.ending, CoViewEnding.guardian);
      expect(r.follower.ending, CoViewEnding.guardian);
      expect((r.gt.sent.last as StopMsg).by, StopBy.guardian);
    });
    test('All done: the leader hears child, and the child can always do it', () {
      final r = Rig()..live();
      r.follower.allDone();
      expect(r.follower.ending, CoViewEnding.child);
      expect(r.leader.ending, CoViewEnding.child);
      expect(r.leader.phase, CoViewPhase.ended);
    });
    test('Not now: the leader is told she is not ready, and the session ends', () {
      final r = Rig();
      r.leader.start();
      r.follower.decline();
      expect(r.leader.ending, CoViewEnding.declined);
      expect(r.follower.ending, CoViewEnding.declined);
    });
    test('All done works from the invitation too', () {
      final r = Rig();
      r.leader.start();
      r.follower.allDone();
      expect(r.follower.phase, CoViewPhase.ended);
    });
    test('an ended session cannot be ended again or turned', () {
      final r = Rig()..live();
      r.leader.end();
      final n = r.gt.sent.length;
      r.leader.end();
      r.leader.nextPage();
      expect(r.gt.sent.length, n);
    });
    test('a cancelled invitation reads as a guardian ending on the follower', () {
      final r = Rig();
      r.leader.start();
      r.leader.end();
      expect(r.follower.ending, CoViewEnding.guardian);
    });
  });

  group('C1 — nobody but a guardian steers the child device', () {
    test('a message from a non-guardian sender is dropped and counted, never obeyed', () {
      final (s, c) = LoopbackTransport.pair(sitter, child);
      final f = CoViewFollower(transport: c, me: child, story: story, budget: () => BudgetState.ok);
      s.send(const StartMsg(seq: 0, at: 1, assetId: 'owl-1'));
      expect(f.phase, CoViewPhase.idle);
      expect(f.ignored, 1);
    });
    test('another child cannot steer her either', () {
      final (s, c) = LoopbackTransport.pair(child, child);
      final f = CoViewFollower(transport: c, me: child, story: story, budget: () => BudgetState.ok);
      s.send(const StartMsg(seq: 0, at: 1, assetId: 'owl-1'));
      expect(f.phase, CoViewPhase.idle);
    });
    test('the leader refuses a stop forged as budget by the child', () {
      final r = Rig()..live();
      r.ct.send(const StopMsg(seq: 5, by: StopBy.budget));
      expect(r.leader.phase, CoViewPhase.live);
    });
    test('the leader refuses a child seek or tick', () {
      final r = Rig()..live();
      r.ct.send(const SeekMsg(seq: 6, pos: 2, sentAt: 1));
      r.ct.send(const TickMsg(seq: 7, pos: 2, rate: 1, paused: false, sentAt: 1));
      expect(r.leader.page, 0);
      expect(r.leader.phase, CoViewPhase.live);
    });
  });

  group('C3 — stale and replayed messages are ignored', () {
    test('a replayed seek does not move the page back', () {
      final r = Rig()..live();
      r.leader.nextPage(); // seq n
      final seek = r.gt.sent.whereType<SeekMsg>().last;
      r.leader.nextPage();
      r.gt.send(SeekMsg(seq: seek.seq, pos: 0, sentAt: 1)); // replay of an old seq
      expect(r.follower.page, 2);
      expect(r.follower.ignored, greaterThan(0));
    });
    test('seq numbers rise strictly across everything the leader sends', () {
      final r = Rig()..live();
      r.leader.nextPage();
      r.leader.prevPage();
      r.leader.end();
      final seqs = r.gt.sent.map((m) => m.seq).toList();
      for (var i = 1; i < seqs.length; i++) {
        expect(seqs[i], greaterThan(seqs[i - 1]));
      }
    });
    test('a page index outside the story is clamped, not trusted', () {
      final r = Rig()..live();
      r.gt.send(const SeekMsg(seq: 99, pos: 9000, sentAt: 1));
      expect(r.follower.page, 2);
    });
  });

  group('C4 — the day runs out, and the goodbye is the right one', () {
    test('spending time to the limit ends it with a budget goodbye on both sides', () {
      final r = Rig(limitMin: 1)..live();
      r.leader.spend(30);
      expect(r.leader.phase, CoViewPhase.live);
      r.leader.spend(30);
      expect(r.leader.ending, CoViewEnding.budget);
      expect(r.follower.ending, CoViewEnding.budget);
      expect((r.gt.sent.last as StopMsg).by, StopBy.budget);
    });
    test('time only counts while live', () {
      final r = Rig(limitMin: 1);
      r.leader.start();
      r.leader.spend(600);
      expect(r.leader.usedSeconds, 0);
    });
    test('the child gets the "last one" cue from the same totals, with no number', () {
      final r = Rig(limitMin: 120, usedS: 120 * 60 - 9 * 60)..live();
      expect(r.leader.budget, BudgetState.lastOne);
      expect(r.follower.lastOne, isTrue);
    });
    test('no cue when there is plenty left, and none outside a live session', () {
      final r = Rig();
      expect(r.follower.lastOne, isFalse);
      r.live();
      expect(r.follower.lastOne, isFalse);
    });
    test('lowering the daily time is free and takes effect at once', () {
      final r = Rig()..live();
      final res = r.leader.setAllowance(90);
      expect(res.ok, isTrue);
      expect(res.direction, AllowanceDirection.lower);
      expect(res.notifyCoGuardian, isFalse);
      expect(r.leader.limitMin, 90);
    });
    test('raising it tells the other guardian', () {
      final r = Rig();
      final res = r.leader.setAllowance(180);
      expect(res.direction, AllowanceDirection.raise);
      expect(res.notifyCoGuardian, isTrue);
    });
    test('an out-of-range change is refused and the limit is unchanged', () {
      final r = Rig();
      expect(r.leader.setAllowance(481).ok, isFalse);
      expect(r.leader.setAllowance(-1).ok, isFalse);
      expect(r.leader.limitMin, 120);
    });
    test('switching it off during a live session ends it as a budget ending', () {
      final r = Rig()..live();
      r.leader.setAllowance(0);
      expect(r.leader.ending, CoViewEnding.budget);
      expect(r.follower.ending, CoViewEnding.budget);
    });
    test('lowering below what is already used ends it', () {
      final r = Rig(usedS: 100 * 60)..live();
      r.leader.setAllowance(60);
      expect(r.leader.phase, CoViewPhase.ended);
    });
  });

  group('transport migration — a call starts or ends mid-story', () {
    test('the leader re-announces its place on the new channel with a higher seq', () {
      final r = Rig()..live();
      r.leader.nextPage();
      final lastOld = r.gt.sent.last.seq;
      final (g2, c2) = LoopbackTransport.pair(guardian, child, kind: TransportKind.livekit);
      final f2 = CoViewFollower(transport: c2, me: child, story: story, budget: () => BudgetState.ok);
      r.leader.migrateTo(g2);
      final tick = g2.sent.single as TickMsg;
      expect(tick.seq, greaterThan(lastOld));
      expect(tick.pos, 1);
      expect(r.leader.transportKind, TransportKind.livekit);
      expect(f2.ignored, 0);
    });
    test('after migrating, new page turns go out on the new channel only', () {
      final r = Rig()..live();
      final (g2, _) = LoopbackTransport.pair(guardian, child, kind: TransportKind.livekit);
      r.leader.migrateTo(g2);
      final oldCount = r.gt.sent.length;
      r.leader.nextPage();
      expect(r.gt.sent.length, oldCount);
      expect(g2.sent.whereType<SeekMsg>().length, 1);
    });
    test('migrating while not live announces nothing', () {
      final r = Rig();
      final (g2, _) = LoopbackTransport.pair(guardian, child);
      r.leader.migrateTo(g2);
      expect(g2.sent, isEmpty);
    });
  });
}
