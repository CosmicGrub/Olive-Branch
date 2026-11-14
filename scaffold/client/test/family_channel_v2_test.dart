// OLIVE BRANCH — the pure parts of pairing channel v2: the identifier that binds a family into the PAKE, the per-window
// commitment, the member claim, member refusal, the post-join tag and the version rules. Verified by CI, headless.
// Nothing here is wired into the live handshake.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_channel_v2.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';

import 'family_test_support.dart';

Uint8List b(int n, int len) => Uint8List.fromList(List<int>.filled(len, n));

void main() {
  late P mom, kid;
  final Uint8List fidA = b(9, 16), fidB = b(8, 16), sid1 = b(1, 16), sid2 = b(2, 16), cpk = b(4, 32);
  FamilyKeyring ringWith(Uint8List fk, {int epoch = 0}) => FamilyKeyring(guardianDevice: true)..putFk(epoch, fk);

  setUp(() async {
    mom = await P.make(1);
    kid = await P.make(3);
  });

  Uint8List ci({
    PairMode mode = PairMode.joinChild,
    Uint8List? sid,
    Uint8List? fc,
    Uint8List? head,
    Uint8List? afp,
    Uint8List? key,
    String name = 'Mom',
    MemberClaim? claim,
  }) =>
      channelIdV2(
        mode: mode, sid: sid ?? sid1, fc: fc ?? b(5, 16), ledgerHead: head ?? b(6, 32), adultFingerprint: afp ?? b(7, 16),
        childDeviceKey: key ?? cpk, adultName: name, claim: claim,
      );

  group('the family commitment', () {
    test('it is different in every window and the same for the same family and window; it does not contain the family id', () async {
      final Uint8List a1 = await familyCommit(fidA, sid1);
      expect(a1.length, 16);
      expect(await familyCommit(fidA, sid1), a1);
      expect(hexOf(await familyCommit(fidA, sid2)), isNot(hexOf(a1)));
      expect(hexOf(await familyCommit(fidB, sid1)), isNot(hexOf(a1)));
      expect(hexOf(a1), isNot(contains(hexOf(fidA).substring(0, 8))));
    });
  });

  group('the channel identifier', () {
    test('every field changes it: mode, session, commitment, ledger head, adult, joiner key, name, and a claim', () async {
      final Uint8List base = ci();
      final Map<String, Uint8List> variants = <String, Uint8List>{
        'mode': ci(mode: PairMode.joinGuardian),
        'sid': ci(sid: sid2),
        'fc': ci(fc: b(55, 16)),
        'head': ci(head: b(66, 32)),
        'afp': ci(afp: b(77, 16)),
        'key': ci(key: b(44, 32)),
        'name': ci(name: 'Dad'),
        'claim': ci(claim: MemberClaim(b(1, 16), b(2, 32))),
      };
      final Set<String> seen = <String>{hexOf(base)};
      for (final MapEntry<String, Uint8List> v in variants.entries) {
        expect(seen.add(hexOf(v.value)), isTrue, reason: v.key);
      }
    });

    test('a transcript run in one mode cannot be replayed into another', () {
      final Set<String> all = <String>{for (final PairMode m in PairMode.values) hexOf(ci(mode: m))};
      expect(all.length, PairMode.values.length);
    });

    test('a missing claim is a different byte string from an empty or any real claim', () {
      expect(hexOf(ci()), isNot(hexOf(ci(claim: MemberClaim(Uint8List(16), Uint8List(32))))));
    });

    test('a v2 identifier can never equal a v1 one: it begins with a fixed label, v1 begins with the random session id', () {
      final Uint8List v2 = ci();
      expect(String.fromCharCodes(v2.sublist(1, 1 + kChannelV2Label.length)), kChannelV2Label);
      expect(PairMode.fromWire('join-child'), PairMode.joinChild);
      expect(PairMode.fromWire('nonsense'), isNull);
    });
  });

  group('member claim: "I already belong to a family"', () {
    test('our own device proves it; the verdict is sameFamily, and the claim is bound to this window and this joiner key', () async {
      final FamilyKeyring ring = ringWith(b(33, 32));
      final MemberClaim c = await makeMemberClaim(ring: ring, ownFid: fidA, sid: sid1, cpk: cpk);
      expect(await checkMemberClaim(claim: c, ring: ring, ownFid: fidA, sid: sid1, cpk: cpk), ClaimVerdict.sameFamily);
      expect(await checkMemberClaim(claim: c, ring: ring, ownFid: fidA, sid: sid2, cpk: cpk), ClaimVerdict.otherFamily,
          reason: 'replayed into another window the commitment no longer matches');
      expect(await checkMemberClaim(claim: c, ring: ring, ownFid: fidA, sid: sid1, cpk: b(5, 32)), ClaimVerdict.forged,
          reason: 'a different joiner key: the proof does not verify');
    });

    test('a device of another family is told apart, and nothing is shared', () async {
      final MemberClaim other = await makeMemberClaim(ring: ringWith(b(44, 32)), ownFid: fidB, sid: sid1, cpk: cpk);
      expect(await checkMemberClaim(claim: other, ring: ringWith(b(33, 32)), ownFid: fidA, sid: sid1, cpk: cpk), ClaimVerdict.otherFamily);
    });

    test('naming the right family without holding its key is forged (a guess at the family id is not enough)', () async {
      final MemberClaim guess = await makeMemberClaim(ring: ringWith(b(99, 32)), ownFid: fidA, sid: sid1, cpk: cpk);
      expect(await checkMemberClaim(claim: guess, ring: ringWith(b(33, 32)), ownFid: fidA, sid: sid1, cpk: cpk), ClaimVerdict.forged);
    });

    test('no claim at all is an unclaimed device; a tablet that is slow to rekey may claim with an older epoch', () async {
      expect(await checkMemberClaim(claim: null, ring: ringWith(b(33, 32)), ownFid: fidA, sid: sid1, cpk: cpk), ClaimVerdict.absent);
      final MemberClaim old = await makeMemberClaim(ring: ringWith(b(33, 32), epoch: 0), ownFid: fidA, sid: sid1, cpk: cpk);
      final FamilyKeyring adult = ringWith(b(33, 32), epoch: 0)..putFk(1, b(34, 32));
      expect(await checkMemberClaim(claim: old, ring: adult, ownFid: fidA, sid: sid1, cpk: cpk), ClaimVerdict.sameFamily);
    });

    test('a claim survives a wire round trip and a damaged one does not decode', () async {
      final MemberClaim c = await makeMemberClaim(ring: ringWith(b(33, 32)), ownFid: fidA, sid: sid1, cpk: cpk);
      final MemberClaim? back = MemberClaim.decode(c.encode());
      expect(back!.proof, c.proof);
      expect(MemberClaim.decode(c.encode().sublist(1)), isNull);
      expect(MemberClaim.decode(<int>[]), isNull);
    });
  });

  group('member refusal: a device that has a family answers only its own family\'s window', () {
    test('an unclaimed device answers any window; a member refuses a foreign one and answers its own; a moved device answers', () async {
      final Uint8List fcOwn = await familyCommit(fidA, sid1), fcOther = await familyCommit(fidB, sid1);
      expect(await memberRefusesWindow(ownFid: null, offeredFc: fcOther, sid: sid1), isFalse);
      expect(await memberRefusesWindow(ownFid: fidA, offeredFc: fcOwn, sid: sid1), isFalse);
      expect(await memberRefusesWindow(ownFid: fidA, offeredFc: fcOther, sid: sid1), isTrue);
      expect(await memberRefusesWindow(ownFid: fidA, offeredFc: fcOther, sid: sid1, beingMoved: true), isFalse);
    });

    test('a neighbour with the same PIN cannot talk a member in: a window opened for another family is refused before any PAKE message', () async {
      // The neighbour's window commits to the neighbour's family id with ITS session id.
      final Uint8List neighbour = await familyCommit(fidB, sid2);
      expect(await memberRefusesWindow(ownFid: fidA, offeredFc: neighbour, sid: sid2), isTrue);
      // Our own old commitment replayed against a new session is refused too.
      expect(await memberRefusesWindow(ownFid: fidA, offeredFc: await familyCommit(fidA, sid1), sid: sid2), isTrue);
    });
  });

  group('the post-join tag proves the joiner got this family\'s key', () {
    test('the right key and transcript verify; a wrong key, another epoch, a truncated credential or another transcript do not', () async {
      final FamilyKeyring ring = ringWith(b(33, 32));
      final Uint8List th = b(12, 32);
      final Uint8List tag = await postJoinTag(ring, 0, th);
      expect(await verifyPostJoinTag(ring, 0, th, tag), isTrue);
      expect(await verifyPostJoinTag(ringWith(b(34, 32)), 0, th, tag), isFalse);
      expect(await verifyPostJoinTag(ring, 1, th, tag), isFalse, reason: 'no such epoch held');
      expect(await verifyPostJoinTag(ring, 0, b(13, 32), tag), isFalse);
      expect(await verifyPostJoinTag(ring, 0, th, tag.sublist(0, 31)), isFalse);
    });
  });

  group('what the joiner checks in the sealed credential', () {
    test('a ledger that is the family named in the window, ending at the head the transcript named, is accepted', () async {
      final Fam f = await Fam.found(mom);
      await f.addChild(mom, kid);
      final LedgerState s = await f.state();
      final Uint8List sid = b(3, 16);
      final Uint8List fc = await familyCommit(s.fid!, sid);
      final Uint8List head = s.heads.single;
      expect(await credentialMatchesWindow(entries: f.entries, votes: f.votes, fc: fc, sid: sid, ledgerHead: head, nowMs: f.clock + hour), isTrue);
    });

    test('it is discarded when the family does not match the commitment, the head is missing or was refused, or the ledger is not a family', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry kidAdd = await f.addChild(mom, kid);
      final LedgerState s = await f.state();
      final Uint8List sid = b(3, 16);
      final Uint8List fc = await familyCommit(s.fid!, sid);
      Future<bool> check({Uint8List? fcx, Uint8List? head, List<LedgerEntry>? entries}) => credentialMatchesWindow(
          entries: entries ?? f.entries, votes: f.votes, fc: fcx ?? fc, sid: sid, ledgerHead: head ?? s.heads.single, nowMs: f.clock + hour);
      expect(await check(fcx: await familyCommit(fidB, sid)), isFalse, reason: 'another family');
      expect(await check(head: b(1, 32)), isFalse, reason: 'a head the credential does not contain');
      expect(await check(entries: <LedgerEntry>[f.genesis], head: kidAdd.hash), isFalse, reason: 'truncated: the named head is not there');
      expect(await check(entries: <LedgerEntry>[kidAdd]), isFalse, reason: 'no genesis, not a family');
      final LedgerEntry bad = await f.add(kid, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      expect(await check(head: bad.hash), isFalse, reason: 'the named head is an entry the ledger refuses');
    });
  });

  group('version rules', () {
    test('a v2 window never answers v1, except a legacy single-grown-up family; a v1 window answers only v1', () {
      bool a(PairWireVersion w, PairWireVersion m, {bool legacy = false}) =>
          windowAnswers(window: w, message: m, legacySingleGuardianFamily: legacy);
      expect(a(PairWireVersion.v2, PairWireVersion.v2), isTrue);
      expect(a(PairWireVersion.v2, PairWireVersion.v1), isFalse);
      expect(a(PairWireVersion.v2, PairWireVersion.v1, legacy: true), isTrue);
      expect(a(PairWireVersion.v1, PairWireVersion.v1), isTrue);
      expect(a(PairWireVersion.v1, PairWireVersion.v2), isFalse);
    });

    test('a v2 joiner shown a v1 hello proceeds only when the adult device is a legacy single-grown-up family', () {
      expect(joinerProceeds(hello: PairWireVersion.v2, adultIsLegacySingleGuardianFamily: false), isTrue);
      expect(joinerProceeds(hello: PairWireVersion.v1, adultIsLegacySingleGuardianFamily: false), isFalse);
      expect(joinerProceeds(hello: PairWireVersion.v1, adultIsLegacySingleGuardianFamily: true), isTrue);
    });
  });

  group('a child never sees any of it, and nothing here is wired yet', () {
    test('no child-facing file and no live pairing file imports the ledger, keys, state or channel v2', () {
      final Directory lib = Directory('lib');
      final List<File> files = lib.listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
      final RegExp family = RegExp(r"import\s+'(package:olive_client/)?family_(ledger|ledger_state|keys|state|channel_v2|profiles)\.dart'");
      final List<String> offenders = <String>[];
      for (final File f in files) {
        final String name = f.uri.pathSegments.last;
        if (name.startsWith('family_') && !name.startsWith('family_structure')) continue;
        final String src = f.readAsStringSync();
        if (family.hasMatch(src) && (name.startsWith('child_') || name.contains('pairing') || name.startsWith('connect_') || name.startsWith('lan_'))) {
          offenders.add(name);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
