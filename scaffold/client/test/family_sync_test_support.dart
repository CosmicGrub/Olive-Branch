// Helpers for the family sync tests: a family with two (or three) grown-ups, a child tablet, a shared guardian key and
// one engine per phone. Not a test file.
import 'dart:typed_data';

import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_sync_engine.dart';

import 'family_test_support.dart';

final Uint8List kTestGk = Uint8List.fromList(List<int>.generate(32, (int i) => 200 - i));
final Uint8List kTestFk = Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));

FamilyKeyring guardianRing({Uint8List? gk, int epoch = 0}) =>
    FamilyKeyring(guardianDevice: true)..putFk(epoch, kTestFk)..putGk(epoch, gk ?? kTestGk);

FamilyKeyring childRing() => FamilyKeyring(guardianDevice: false)..putFk(0, kTestFk);

class SyncRig {
  SyncRig._(this.mom, this.dad, this.sam, this.kid, this.fam, this.state);
  final P mom, dad, sam, kid;
  final Fam fam;
  final LedgerState state;

  Uint8List get fid => Uint8List.fromList(fam.pin.fid);

  static Future<SyncRig> make({bool third = false}) async {
    final P mom = await P.make(1), dad = await P.make(2), kid = await P.make(3), sam = await P.make(4);
    final Fam f = await Fam.found(mom);
    await f.welcomeParent(mom, dad, others: <P>[]);
    if (third) {
      f.clock += 4 * day; // dad's phone settles in before it can vote
      await f.welcomeParent(mom, sam, others: <P>[dad]);
    }
    await f.addChild(mom, kid);
    f.clock += 4 * day;
    return SyncRig._(mom, dad, sam, kid, f, await f.state());
  }

  /// An engine for [who] with its own clock cell, so a test can move one phone's clock alone.
  SyncEngine engine(P who, {Clock? clock, SyncRepository? repo, FamilyKeyring? ring}) {
    final Clock c = clock ?? Clock(t0 + 10 * day);
    return SyncEngine(fid: fid, device: who.key, ring: ring ?? guardianRing(), nowMs: () => c.ms, repo: repo);
  }
}

class Clock {
  Clock(this.ms);
  int ms;
}
