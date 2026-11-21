// OLIVE BRANCH — data-loss harness: two grown-up phones and a child tablet over a bad network (cuts, delays that reorder,
// repeats, losses, and the app being killed and opened again) always end with the same family record on both phones,
// every acknowledged message, drawing, score and memory in it, and nothing the tablet made left waiting.
@Tags(<String>['dataloss'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'mesh_sim.dart';

const List<int> kSeeds = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

void main() {
  int cuts = 0, losses = 0, repeats = 0, acked = 0;

  group('three devices over a bad network', () {
    for (final int seed in kSeeds) {
      test('seed $seed: both phones end with the same record and every acknowledged item is in it', () async {
        final Sim s = await Sim.make(seed);
        s.sam.lost = true; // two grown-up phones and the tablet
        for (int i = 0; i < 70; i++) {
          await s.step();
          if (s.net.anyCut) cuts++;
        }
        final int rounds = await s.settle();
        expect(rounds, lessThan(60));

        final Set<String> momItems = s.mom.itemIds(), dadItems = s.dad.itemIds();
        expect(s.acked, isNotEmpty);
        for (final String id in s.acked.keys) {
          expect(momItems.contains(id), isTrue, reason: 'seed $seed: acknowledged $id is missing on mom\'s phone');
          expect(dadItems.contains(id), isTrue, reason: 'seed $seed: acknowledged $id is missing on dad\'s phone');
        }
        expect(s.mom.eventIds(), s.dad.eventIds(), reason: 'seed $seed: the two phones hold different records');
        expect(s.mom.engine.heldCount, 0, reason: 'something is still waiting for an event that never came');
        expect(s.dad.engine.heldCount, 0);
        expect(s.mom.engine.equivocations, isEmpty);
        expect(s.dad.engine.equivocations, isEmpty);
        expect(await s.tablet.waiting(), isEmpty, reason: 'seed $seed: something she made was never taken');
        // Nothing the network repeated became a repeat on a screen: one entry per item, and an item the tablet made is
        // written at most once per phone (both phones may take it from the tablet; the list shows it once).
        for (final PhoneNode p in <PhoneNode>[s.mom, s.dad]) {
          for (final MapEntry<String, int> c in p.copiesPerItem().entries) {
            expect(c.value, lessThanOrEqualTo(2), reason: 'seed $seed: ${c.key} written ${c.value} times on ${p.name}');
          }
        }
        for (final String id in s.acked.keys.where((String k) => !k.startsWith('ivy-'))) {
          expect(s.mom.copiesPerItem()[id], 1, reason: 'a grown-up\'s own item is one entry');
        }
        // Every kind travelled.
        expect(<String>{...s.acked.values}.length, greaterThan(1));
        losses += s.net.lost;
        repeats += s.net.repeated;
        acked += s.acked.length;
      });
    }

    test('the runs were not vacuous: the network really cut, lost and repeated', () {
      expect(cuts, greaterThan(50));
      expect(losses, greaterThan(50));
      expect(repeats, greaterThan(50));
      expect(acked, greaterThan(150));
    });
  });

  group('the same record without the tablet\'s help: a phone that was dark for a long time catches up whole', () {
    test('one phone writes while the other is unreachable, then they meet', () async {
      final Sim s = await Sim.make(99, drop: 0.3, dup: 0.5);
      s.sam.lost = true;
      s.net.cut('mom', 'dad');
      for (int i = 0; i < 12; i++) {
        await s.authorAt(s.mom);
        await s.authorAt(s.dad);
        s.share(s.mom, s.dad);
        s.share(s.dad, s.mom);
        await s.tickNet(3);
      }
      expect(s.mom.itemIds().intersection(s.dad.itemIds()), isEmpty, reason: 'the cut let something through');
      await s.settle();
      expect(s.mom.eventIds(), s.dad.eventIds());
      expect(s.mom.itemIds().length, 24);
      expect(s.acked.length, 24);
    });
  });
}
