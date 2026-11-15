// OLIVE BRANCH — the pure building blocks of pairing channel v2: the channel identifier that binds a family into the
// PAKE, the per-window family commitment, the member claim, member refusal, the post-join key-confirmation tag, and the
// version rules. UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md
// section 3.4 and the village design's `join-member` mode (section 9, PR 3).
//
// NOT WIRED. This file is not imported by pairing_protocol.dart, lan_pairing_transport.dart or any connect screen:
// another PR (#197, persistent QR pairing) owns those files and the live handshake is unchanged. What is here are the
// functions the wired version will call, tested on their own, including the hostile cases. cpace.dart (the PAKE) is
// not touched and not needed.
//
// What the v2 channel changes, in one paragraph. Today the channel identifier holds the family id in the clear, taken
// from the adult's own hello, so it always agrees and protects only integrity. v2 sends a per-window COMMITMENT to the
// family id (fresh every window, so nothing stable that names the family crosses the Wi-Fi), the head of the adult's
// ledger, and the MODE of the window (chosen by the adult, never by the joiner), and a device that already belongs to a
// family REFUSES a window whose commitment is not its own family's. A child never sees any of it: every new refusal is
// silent on a child device (P1 to P11).
//
// The composition is custom code over vetted primitives and needs the external review that decision D2 already requires.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'family_keys.dart';
import 'family_ledger.dart';
import 'family_ledger_state.dart';

/// The first element of every v2 channel identifier. The v1 identifier starts with a random session id, so a v1 and a
/// v2 transcript can never confirm each other.
const String kChannelV2Label = 'olive-pair-v2';

/// What kind of window the adult opened. It is part of the identifier: a transcript made in one mode cannot be
/// replayed or downgraded into another.
enum PairMode {
  joinChild('join-child'),
  joinGuardian('join-guardian'),
  reconnect('reconnect'),
  joinMember('join-member');

  const PairMode(this.wire);
  final String wire;

  static PairMode? fromWire(Object? s) {
    for (final PairMode m in PairMode.values) {
      if (m.wire == s) return m;
    }
    return null;
  }
}

Future<Uint8List> _sha(List<int> b) async => Uint8List.fromList((await Sha256().hash(b)).bytes);

/// `fc`: a commitment to the family id that is different in every window (the session id is random per window). The
/// joiner cannot invert it (the family id is 128 random bits); it learns the real family id only inside the sealed
/// credential, then checks the commitment. 16 bytes.
Future<Uint8List> familyCommit(List<int> fid, List<int> sid) async => Uint8List.fromList((await _sha(
        cat(<List<int>>[lv(utf8.encode('olive-fid-commit-v1')), lv(fid), lv(sid)])))
    .sublist(0, 16));

/// "I already belong to a family": the commitment to MY family id for THIS window, plus a proof under a key only
/// members of that family hold. It reveals nothing stable and cannot be replayed into another window (it binds the
/// session id and the joiner's channel key).
class MemberClaim {
  MemberClaim(this.fcOwn, this.proof);
  final Uint8List fcOwn, proof;

  Uint8List encode() => cat(<List<int>>[lv(fcOwn), lv(proof)]);

  static MemberClaim? decode(List<int> b) {
    try {
      if (b.length != 1 + 16 + 1 + 32 || b[0] != 16 || b[17] != 32) return null;
      return MemberClaim(Uint8List.fromList(b.sublist(1, 17)), Uint8List.fromList(b.sublist(18)));
    } catch (_) {
      return null;
    }
  }
}

Future<Uint8List> _claimProof(List<int> memberKey, List<int> sid, List<int> cpk) async => Uint8List.fromList((await Hmac.sha256()
        .calculateMac(cat(<List<int>>[lv(utf8.encode('olive-member-claim-v1')), lv(sid), lv(cpk)]), secretKey: SecretKey(memberKey)))
    .bytes);

Future<MemberClaim> makeMemberClaim({
  required FamilyKeyring ring,
  required List<int> ownFid,
  required List<int> sid,
  required List<int> cpk,
}) async {
  final int epoch = ring.newestEpoch;
  final Uint8List memberKey = await ring.familySubkey(epoch, kFkMember);
  return MemberClaim(await familyCommit(ownFid, sid), await _claimProof(memberKey, sid, cpk));
}

enum ClaimVerdict {
  /// No claim: an unclaimed device. A normal join; an adult approves.
  absent,

  /// The claim names this family and the proof verifies: one of our own devices.
  sameFamily,

  /// The claim names a different family. Nothing is shared and no PAKE secret is derived.
  otherFamily,

  /// The claim names this family but the proof does not verify (a guess, a replay from another window or key).
  forged,
}

/// The adult window's check of a joiner's claim. [ring] and [ownFid] are the ADULT's family.
Future<ClaimVerdict> checkMemberClaim({
  required MemberClaim? claim,
  required FamilyKeyring ring,
  required List<int> ownFid,
  required List<int> sid,
  required List<int> cpk,
}) async {
  if (claim == null) return ClaimVerdict.absent;
  if (!bytesEqual(claim.fcOwn, await familyCommit(ownFid, sid))) return ClaimVerdict.otherFamily;
  // Any epoch the adult still holds: a tablet that is slow to rekey may claim with an older one.
  for (final int e in ring.fkEpochs) {
    final Uint8List memberKey = await ring.familySubkey(e, kFkMember);
    if (bytesEqual(claim.proof, await _claimProof(memberKey, sid, cpk))) return ClaimVerdict.sameFamily;
  }
  return ClaimVerdict.forged;
}

/// The channel identifier mixed into the PAKE. All pieces are length-prefixed; a missing claim is a different byte
/// string from any claim.
Uint8List channelIdV2({
  required PairMode mode,
  required List<int> sid,
  required List<int> fc,
  required List<int> ledgerHead,
  required List<int> adultFingerprint,
  required List<int> childDeviceKey,
  required String adultName,
  MemberClaim? claim,
}) =>
    cat(<List<int>>[
      lv(utf8.encode(kChannelV2Label)),
      lv(utf8.encode(mode.wire)),
      lv(sid),
      lv(fc),
      lv(ledgerHead),
      lv(adultFingerprint),
      lv(childDeviceKey),
      lv(utf8.encode(adultName)),
      lv(claim == null ? const <int>[0] : <int>[1, ...claim.encode()]),
    ]);

/// A device that belongs to a family answers only a window whose commitment matches its own family id. An unclaimed
/// device (no family) answers any window, as today. A device an adult has put into the "being moved" state (with the
/// PIN) answers a window of another family. On a child device the refusal is silent.
Future<bool> memberRefusesWindow({
  required List<int>? ownFid,
  required List<int> offeredFc,
  required List<int> sid,
  bool beingMoved = false,
}) async {
  if (ownFid == null || beingMoved) return false;
  return !bytesEqual(await familyCommit(ownFid, sid), offeredFc);
}

/// After the sealed credential arrives, the joiner proves it really received this family's FK: a tag over the
/// transcript under a key derived from FK. FK cannot enter the PAKE itself (the joiner did not have it), so this is
/// the honest equivalent. The adult rejects a truncated or substituted credential here.
Future<Uint8List> postJoinTag(FamilyKeyring ring, int epoch, List<int> transcriptHash) async {
  final Uint8List k = await ring.familySubkey(epoch, kFkBind);
  return Uint8List.fromList((await Hmac.sha256()
          .calculateMac(cat(<List<int>>[lv(utf8.encode('olive-postjoin-v1')), lv(transcriptHash)]), secretKey: SecretKey(k)))
      .bytes);
}

Future<bool> verifyPostJoinTag(FamilyKeyring ring, int epoch, List<int> transcriptHash, List<int> tag) async {
  if (ring.fk(epoch) == null) return false;
  return bytesEqual(await postJoinTag(ring, epoch, transcriptHash), tag);
}

/// The joiner's check of what the adult sent inside the sealed credential, against what was said in the window:
/// the ledger reduces to a family (pinned to the genesis it contains), its family id matches the commitment from the
/// hello, and the head the transcript named is in it and was not refused. Anything else: discard, silently.
Future<bool> credentialMatchesWindow({
  required List<LedgerEntry> entries,
  required List<LedgerVote> votes,
  required List<int> fc,
  required List<int> sid,
  required List<int> ledgerHead,
  required int nowMs,
}) async {
  final LedgerState st = await reduceLedger(entries: entries, votes: votes, nowMs: nowMs);
  if (!st.ok) return false;
  if (!bytesEqual(await familyCommit(st.fid!, sid), fc)) return false;
  final String head = hexOf(ledgerHead);
  if (!entries.any((LedgerEntry e) => e.hashHex == head)) return false;
  return !st.rejected.containsKey(head);
}

/// Wire versions. A v2 window never answers a v1 first message, except for a legacy single-grown-up family that has
/// not moved on yet (so existing families keep working through the migration). The legacy path ends after the number
/// of releases the owner decides (open question 10).
enum PairWireVersion { v1, v2 }

bool windowAnswers({
  required PairWireVersion window,
  required PairWireVersion message,
  bool legacySingleGuardianFamily = false,
}) {
  if (window == PairWireVersion.v1) return message == PairWireVersion.v1;
  if (message == PairWireVersion.v2) return true;
  return legacySingleGuardianFamily;
}

/// A v2 joiner that is shown a v1 hello from a window the person chose completes the old protocol only when the
/// adult device is a legacy single-grown-up family; otherwise it stops.
bool joinerProceeds({required PairWireVersion hello, required bool adultIsLegacySingleGuardianFamily}) =>
    hello == PairWireVersion.v2 || adultIsLegacySingleGuardianFamily;
