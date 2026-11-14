// OLIVE BRANCH — the Match step, pure logic: three pictures and a colour from three key bytes, four candidate sets for
// the adult with exactly one real. UNVERIFIED until CI runs it. Design: docs/planning/PERSISTENT-QR-PAIRING.md J8.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/pairing_match.dart';

void main() {
  test('64 distinct picture names and 8 colours each with its own shape', () {
    expect(kMatchPictures, hasLength(64));
    expect(kMatchPictures.toSet(), hasLength(64));
    expect(kMatchColours.toSet(), hasLength(8));
    expect(kMatchShapes.toSet(), hasLength(8));
  });

  test('fromBytes uses 6 bits per picture and 3 bits of colour (about 21 bits)', () {
    final MatchSet m = MatchSet.fromBytes(<int>[0xff, 0xff, 0xff]);
    expect(m.pictures, <int>[63, 63, 63]);
    expect(m.colour, 7);
    final MatchSet z = MatchSet.fromBytes(<int>[0, 0, 0]);
    expect(z.pictures, <int>[0, 0, 0]);
    expect(z.colour, 0);
    // Every one of the 2^21 combinations is reachable: spot check that single bits change the set.
    expect(MatchSet.fromBytes(<int>[1, 0, 0]), isNot(z));
    expect(MatchSet.fromBytes(<int>[0, 0, 0x40]), z, reason: 'the top two bits of the third byte are unused');
  });

  test('four choices: one real, all different, decoys differ from the real set in at least two pictures', () {
    for (int seed = 0; seed < 300; seed++) {
      final Random r = Random(seed);
      final MatchSet real = MatchSet.fromBytes(<int>[r.nextInt(256), r.nextInt(256), r.nextInt(256)]);
      final MatchChoices c = buildMatchChoices(real, r);
      expect(c.sets, hasLength(4));
      expect(c.sets.toSet(), hasLength(4), reason: 'seed $seed');
      expect(c.sets[c.correct], real);
      for (int i = 0; i < 4; i++) {
        if (i == c.correct) continue;
        int same = 0;
        for (int p = 0; p < 3; p++) {
          if (c.sets[i].pictures[p] == real.pictures[p]) same++;
        }
        expect(same, lessThanOrEqualTo(1), reason: 'a decoy must not be nearly the real set');
      }
    }
  });

  test('the position of the real set is not fixed', () {
    final Set<int> seen = <int>{};
    for (int seed = 0; seed < 100; seed++) {
      final Random r = Random(seed);
      seen.add(buildMatchChoices(MatchSet.fromBytes(<int>[1, 2, 3]), r).correct);
    }
    expect(seen, <int>{0, 1, 2, 3});
  });

  test('the same bytes always give the same set (both devices agree)', () {
    final Uint8List b = Uint8List.fromList(<int>[9, 200, 31]);
    expect(matchFromKeyBytes(b), matchFromKeyBytes(Uint8List.fromList(b)));
  });
}
