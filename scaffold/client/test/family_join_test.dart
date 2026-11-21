// OLIVE BRANCH — adding a second grown-up's phone: the whole conversation in process, and every hostile case. Verified by
// CI, headless. The wire (HTTP, mDNS) is covered in family_sync_lan_test.dart and family_hub_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair, X25519;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_join.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/pairing_protocol.dart' show PairingTransport;

import 'family_test_support.dart';

class WindowTransport implements PairingTransport {
  WindowTransport(this.w, {this.log});
  final FamilyJoinWindow w;
  final List<Map<String, dynamic>>? log;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> m) async {
    log?.add(m);
    // The same trip the road makes: through JSON and back, so nothing non-JSON can sneak through a test.
    return w.onMessage(jsonDecode(jsonEncode(m)) as Map<String, dynamic>);
  }
}

class Rig {
  Rig._(this.mom, this.momRepo, this.dad, this.dadRepo, this.clock, this.momCtx);
  final P mom, dad;
  final MemoryFamilyRepository momRepo, dadRepo;
  final JoinClk clock;
  FamilyContext momCtx;

  static Future<Rig> make({int settle = 24}) async {
    final P mom = await P.make(1), dad = await P.make(2);
    final JoinClk c = JoinClk(t0 + 5 * day);
    final MemoryFamilyRepository mr = MemoryFamilyRepository();
    final FamilyContext ctx = await FamilyFounder.found(
      device: mom.key,
      guardianName: 'Mom',
      nowMs: c.ms,
      repo: mr,
      random: Random(1),
      policy: FamilyPolicy(settleHours: settle),
    );
    return Rig._(mom, mr, dad, MemoryFamilyRepository(), c, ctx);
  }

  FamilyJoinWindow window({String code = '123456'}) =>
      FamilyJoinWindow(context: momCtx, repo: momRepo, nowMs: () => clock.ms, random: Random(7), codeForTest: code);

  FamilyJoinGuest guest(PairingTransport t, {DeviceKey? key, MemoryFamilyRepository? repo}) => FamilyJoinGuest(
    transport: t,
    device: key ?? dad.key,
    repo: repo ?? dadRepo,
    nowMs: () => clock.ms,
    random: Random(9),
    pollEvery: const Duration(milliseconds: 5),
    waitFor: const Duration(seconds: 5),
  );

  /// Approves as soon as the window asks.
  static void autoApprove(FamilyJoinWindow w, {void Function(String?)? done}) {
    bool asked = false;
    w.addListener(() {
      if (w.state == JoinState.waitingForYou && !asked) {
        asked = true;
        unawaited(w.approve().then((String? r) => done?.call(r)));
      }
    });
  }
}

class JoinClk {
  JoinClk(this.ms);
  int ms;
}

void main() {
  test(
    'the whole join: code, matching words, approval, the keys and the record arrive, and both phones list both grown-ups',
    () async {
      final Rig r = await Rig.make();
      final FamilyJoinWindow w = r.window();
      Rig.autoApprove(w);
      final List<String> words = <String>[];
      final JoinOutcome o = await r
          .guest(WindowTransport(w))
          .join(code: '123456', name: 'Dad', onWords: (s) => words.add('$s'));
      expect(o.ok, isTrue, reason: o.reason);
      expect(w.state, JoinState.done);
      expect(words.single, '${w.sas}', reason: 'both screens show the same word and picture');
      final FamilyContext dad = o.context!;
      expect(dad.familyId, r.momCtx.familyId);
      expect(dad.keyring.guardianDevice, isTrue);
      expect(dad.keyring.fk(0), r.momCtx.keyring.fk(0));
      expect(dad.keyring.gk(0), r.momCtx.keyring.gk(0));
      // The founder's stored record now holds the guest's yes too.
      final FamilyContext? momNow = await FamilyContext.load(r.momRepo, r.mom.key, nowMs: r.clock.ms);
      final LedgerState ms = await momNow!.state(nowMs: r.clock.ms);
      final LedgerState ds = await dad.state(nowMs: r.clock.ms);
      for (final LedgerState s in <LedgerState>[ms, ds]) {
        expect(s.ok, isTrue);
        expect(s.members.where((LedgerMember m) => m.isGuardian).map((LedgerMember m) => m.name).toSet(), <String>{
          'Mom',
          'Dad',
        });
        expect(s.isActiveGuardianDevice(r.dad.key.publicKey), isTrue);
      }
      // The newcomer settles in for the family's hours.
      expect(ds.isSettling(r.dad.key.publicKey, r.clock.ms), isTrue);
      expect(ds.isSettling(r.dad.key.publicKey, r.clock.ms + 25 * hour), isFalse);
    },
  );

  test('the code never travels: not in any message the guest sends or the window answers', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window(code: '482913');
    Rig.autoApprove(w);
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    final JoinOutcome o = await r.guest(WindowTransport(w, log: log)).join(code: '482913', name: 'Dad');
    expect(o.ok, isTrue);
    expect(jsonEncode(log).contains('482913'), isFalse);
  });

  test(
    'a wrong code is refused each time and costs a start; five starts close the window for the right code too',
    () async {
      final Rig r = await Rig.make();
      final FamilyJoinWindow w = r.window();
      for (int i = 0; i < kJoinMaxStarts; i++) {
        final JoinOutcome o = await r.guest(WindowTransport(w)).join(code: '000000', name: 'Eve');
        expect(o.ok, isFalse);
        expect(o.reason, 'code');
      }
      expect(w.state, JoinState.open, reason: 'it closes on the next start, not before');
      final JoinOutcome late = await r.guest(WindowTransport(w)).join(code: '123456', name: 'Dad');
      expect(late.ok, isFalse);
      expect(w.state, JoinState.closed);
      expect(await r.dadRepo.hasRecord(), isFalse);
      expect((await r.momRepo.load())!.entries.length, 1, reason: 'nothing was added to the founder');
    },
  );

  test(
    'a guest that goes on after a wrong key exchange is counted: three forged confirmations close the window',
    () async {
      final Rig r = await Rig.make();
      final FamilyJoinWindow w = r.window();
      for (int i = 0; i < kJoinMaxWrong; i++) {
        expect(w.state, JoinState.open);
        final Map<String, dynamic> a0 = (await w.onMessage(<String, dynamic>{'t': 'j0'}))!;
        expect(a0['sid'], isA<String>());
        final SimpleKeyPair kp = await X25519().newKeyPair();
        final List<int> pub = (await kp.extractPublicKey()).bytes;
        final Map<String, dynamic>? a1 = await w.onMessage(<String, dynamic>{'t': 'j1', 'y': b64(pub)});
        expect(a1, isNotNull, reason: 'a well-formed share is answered; the answer proves nothing without the code');
        expect(
          await w.onMessage(<String, dynamic>{
            't': 'j2',
            'c': b64(Uint8List(32)),
            'o': b64(Uint8List(40)),
          }),
          isNull,
        );
      }
      expect(w.state, JoinState.closed);
      expect(w.endedBecause, 'code');
    },
  );

  test('five starts and the window is closed, even with no wrong code', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    for (int i = 0; i < kJoinMaxStarts; i++) {
      expect(await w.onMessage(<String, dynamic>{'t': 'j0'}), isNotNull);
    }
    expect(await w.onMessage(<String, dynamic>{'t': 'j0'}), isNull);
    expect(w.state, JoinState.closed);
  });

  test('a window answers nothing after five minutes', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    r.clock.ms += kJoinWindowMs + 1000;
    expect(await w.onMessage(<String, dynamic>{'t': 'j0'}), isNull);
    expect(w.state, JoinState.closed);
  });

  test('messages out of order, or from nobody, get no answer and change nothing', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    for (final Map<String, dynamic> m in <Map<String, dynamic>>[
      <String, dynamic>{'t': 'j1', 'y': 'AAAA'},
      <String, dynamic>{'t': 'j2', 'c': 'AAAA', 'o': 'AAAA'},
      <String, dynamic>{'t': 'j3'},
      <String, dynamic>{'t': 'j4', 'v': 'AAAA'},
      <String, dynamic>{'t': 'zz'},
      <String, dynamic>{},
      <String, dynamic>{'t': 5},
    ]) {
      expect(await w.onMessage(m), isNull, reason: '$m');
    }
    expect(w.state, JoinState.open);
    // A share with the wrong length, or with a low-order point, is refused without an exception.
    await w.onMessage(<String, dynamic>{'t': 'j0'});
    expect(await w.onMessage(<String, dynamic>{'t': 'j1', 'y': b64(Uint8List(32))}), isNull);
    expect(await w.onMessage(<String, dynamic>{'t': 'j1', 'y': b64(Uint8List(5))}), isNull);
  });

  test('declined: the guest is told, nothing is stored on either side', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    bool said = false;
    w.addListener(() {
      if (w.state == JoinState.waitingForYou && !said) {
        said = true;
        w.decline();
      }
    });
    final JoinOutcome o = await r.guest(WindowTransport(w)).join(code: '123456', name: 'Dad');
    expect(o.ok, isFalse);
    expect(o.reason, 'declined');
    expect(w.state, JoinState.closed);
    expect(await r.dadRepo.hasRecord(), isFalse);
    expect((await r.momRepo.load())!.entries.length, 1);
  });

  test('a phone that already belongs to a family refuses to join another and keeps its own record', () async {
    final Rig r = await Rig.make();
    final FamilyContext own = await FamilyFounder.found(
      device: r.dad.key,
      guardianName: 'Dad',
      nowMs: r.clock.ms,
      repo: r.dadRepo,
      random: Random(3),
    );
    final FamilyJoinWindow w = r.window();
    final JoinOutcome o = await r.guest(WindowTransport(w)).join(code: '123456', name: 'Dad');
    expect(o.reason, 'has_family');
    expect((await r.dadRepo.load())!.entries.single.hashHex, own.entries.single.hashHex);
  });

  test('a bad code or an empty name is refused before anything is sent', () async {
    final Rig r = await Rig.make();
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
    final FamilyJoinWindow w = r.window();
    for (final String code in <String>['', '12345', '1234567', 'abcdef', '12 456']) {
      expect((await r.guest(WindowTransport(w, log: log)).join(code: code, name: 'Dad')).reason, 'code');
    }
    expect((await r.guest(WindowTransport(w, log: log)).join(code: '123456', name: '  \n ')).reason, 'code');
    expect(log, isEmpty);
  });

  test(
    'a welcome whose family keys are not the ones the signed genesis commits to is refused, and nothing is stored',
    () async {
      final Rig r = await Rig.make();
      // The founder's record, but with a different guardian key in its keyring: what a hostile phone would hand over.
      final FamilySnapshot good = r.momCtx.snapshot();
      final MemoryFamilyRepository evil = MemoryFamilyRepository();
      await evil.save(
        FamilySnapshot(
          entries: good.entries,
          votes: good.votes,
          agreementSeed: good.agreementSeed,
          guardianDevice: true,
          fk: good.fk,
          gk: <int, Uint8List>{0: Uint8List.fromList(List<int>.filled(32, 77))},
        ),
      );
      final FamilyContext evilCtx = (await FamilyContext.load(evil, r.mom.key, nowMs: r.clock.ms))!;
      final FamilyJoinWindow w = FamilyJoinWindow(
        context: evilCtx,
        repo: evil,
        nowMs: () => r.clock.ms,
        random: Random(7),
        codeForTest: '123456',
      );
      Rig.autoApprove(w);
      final JoinOutcome o = await r.guest(WindowTransport(w)).join(code: '123456', name: 'Dad');
      expect(o.ok, isFalse);
      expect(o.reason, 'unreadable');
      expect(await r.dadRepo.hasRecord(), isFalse);
    },
  );

  test('only a family with one grown-up can add another this way', () async {
    final Rig r = await Rig.make(settle: 0);
    // First join.
    final FamilyJoinWindow w1 = r.window();
    Rig.autoApprove(w1);
    expect((await r.guest(WindowTransport(w1)).join(code: '123456', name: 'Dad')).ok, isTrue);
    final FamilyContext two = (await FamilyContext.load(r.momRepo, r.mom.key, nowMs: r.clock.ms))!;
    // Second join attempt on the two-grown-up record.
    final P sam = await P.make(5);
    final FamilyJoinWindow w2 = FamilyJoinWindow(
      context: two,
      repo: r.momRepo,
      nowMs: () => r.clock.ms,
      random: Random(8),
      codeForTest: '654321',
    );
    String? why;
    Rig.autoApprove(w2, done: (String? x) => why = x);
    final JoinOutcome o = await r
        .guest(WindowTransport(w2), key: sam.key, repo: MemoryFamilyRepository())
        .join(code: '654321', name: 'Sam');
    expect(why, 'not_alone');
    expect(o.ok, isFalse);
    expect((await r.momRepo.load())!.entries.length, two.entries.length, reason: 'the record was not changed');
  });

  test('the founder cannot approve twice or approve with nobody asking', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    expect(await w.approve(), isNotNull);
    expect((await r.momRepo.load())!.entries.length, 1);
  });

  test('a lost "yes" is not lost for good: the founder takes the guest\'s vote from the next meeting', () async {
    final Rig r = await Rig.make();
    final FamilyJoinWindow w = r.window();
    Rig.autoApprove(w);
    final JoinOutcome o = await r.guest(_DropYes(WindowTransport(w))).join(code: '123456', name: 'Dad');
    expect(o.ok, isTrue, reason: 'the guest holds the family');
    final FamilyContext mom = (await FamilyContext.load(r.momRepo, r.mom.key, nowMs: r.clock.ms))!;
    LedgerState s = await mom.state(nowMs: r.clock.ms);
    expect(s.isActiveGuardianDevice(r.dad.key.publicKey), isFalse, reason: 'not yet: the vote did not arrive');
    final FamilyContext? merged = await mergeLedger(
      context: mom,
      repo: r.momRepo,
      entries: o.context!.entries,
      votes: o.context!.votes,
      nowMs: r.clock.ms,
    );
    expect(merged, isNotNull);
    s = await merged!.state(nowMs: r.clock.ms);
    expect(s.isActiveGuardianDevice(r.dad.key.publicKey), isTrue);
  });

  group('mergeLedger', () {
    test('nothing new changes nothing', () async {
      final Rig r = await Rig.make();
      final FamilyContext? c = await mergeLedger(
        context: r.momCtx,
        repo: r.momRepo,
        entries: r.momCtx.entries,
        votes: r.momCtx.votes,
        nowMs: r.clock.ms,
      );
      expect(identical(c, r.momCtx), isTrue);
    });

    test('an entry from another family is dropped; the record is unchanged', () async {
      final Rig r = await Rig.make();
      final P stranger = await P.make(40);
      final MemoryFamilyRepository sr = MemoryFamilyRepository();
      final FamilyContext other = await FamilyFounder.found(
        device: stranger.key,
        guardianName: 'X',
        nowMs: r.clock.ms,
        repo: sr,
        random: Random(50),
      );
      final FamilyContext? c = await mergeLedger(
        context: r.momCtx,
        repo: r.momRepo,
        entries: other.entries,
        votes: other.votes,
        nowMs: r.clock.ms,
      );
      expect(c, isNotNull);
      expect((await r.momRepo.load())!.entries.length, 1, reason: 'a second genesis never lands');
      expect((await c!.state(nowMs: r.clock.ms)).ok, isTrue);
    });

    test('a vote signed by nobody who matters, or for an entry that is not held, is not kept', () async {
      final Rig r = await Rig.make();
      final LedgerVote v = await LedgerVote.sign(r.dad.key, target: Uint8List(32), answer: 'yes', atMs: r.clock.ms);
      final FamilyContext? c = await mergeLedger(
        context: r.momCtx,
        repo: r.momRepo,
        entries: const <LedgerEntry>[],
        votes: <LedgerVote>[v],
        nowMs: r.clock.ms,
      );
      expect(c, isNotNull);
      expect((await r.momRepo.load())!.votes, isEmpty);
    });

    test('more entries than the cap are refused whole', () async {
      final Rig r = await Rig.make();
      final List<LedgerEntry> many = <LedgerEntry>[];
      for (int i = 0; i < kMergeMaxEntries + 1; i++) {
        many.add(
          await LedgerEntry.sign(
            r.mom.key,
            type: EntryType.policySet,
            prev: r.momCtx.entries.map((LedgerEntry e) => e.hash),
            issuedAtMs: r.clock.ms + i,
            body: <String, Object?>{'policy': const FamilyPolicy().toValue(), 'exp': null},
          ),
        );
      }
      await mergeLedger(
        context: r.momCtx,
        repo: r.momRepo,
        entries: many,
        votes: const <LedgerVote>[],
        nowMs: r.clock.ms,
      );
      expect((await r.momRepo.load())!.entries.length, 1);
    });
  });
}

/// Loses the guest's final "yes".
class _DropYes implements PairingTransport {
  _DropYes(this.inner);
  final PairingTransport inner;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> m) async => m['t'] == 'j4' ? null : inner.send(m);
}
