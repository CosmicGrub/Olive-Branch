// OLIVE BRANCH — the per-age child homes as data: the Dart tables equal the prototype's own render.
// No longer UNVERIFIED — verified by CI. The vector (test/parity/vectors/child_home_bands.json) is generated from
// the live prototype by tools/gen-child-home-vectors.mjs, which BOOTS the prototype, sets her age and records the
// tiles it really drew; tools/test/child_home_vectors.test.mjs fails if it is stale. This file holds the Dart side
// to it, for every age from 3 to 17.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home_bands.dart';

Map<String, Object?> _vec() =>
    jsonDecode(File('test/parity/vectors/child_home_bands.json').readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _m(Object? o) => o! as Map<String, Object?>;
List<String> _ids(Object? tiles) => <String>[for (final Object? t in tiles! as List<Object?>) _m(t)['id']! as String];

void main() {
  final Map<String, Object?> v = _vec();

  group('the registry equals the prototype\'s TL, BANDSET, MORE and GROW', () {
    test('every tile: title, line under it, icon, and its per-band renames', () {
      final Map<String, Object?> tl = _m(v['tiles']);
      expect(kBandTiles.keys.toSet(), tl.keys.toSet());
      for (final MapEntry<String, Object?> e in tl.entries) {
        final Map<String, Object?> t = _m(e.value);
        final BandTile d = kBandTiles[e.key]!;
        expect(d.title, t['t'], reason: e.key);
        expect(d.sub, t['s'], reason: e.key);
        expect(d.icon, t['ic'], reason: e.key);
        final Map<String, Object?> alt = t['alt'] == null ? <String, Object?>{} : _m(t['alt']);
        expect(d.alt.keys.toSet(), alt.keys.toSet(), reason: e.key);
        for (final String b in alt.keys) {
          expect(d.alt[b], (alt[b]! as List<Object?>)[0], reason: '${e.key} at $b');
        }
      }
    });

    test('BANDSET: which tiles each band carries', () {
      final Map<String, Object?> bs = _m(v['bandset']);
      expect(kBandSet.keys.toList(), bs.keys.toList());
      for (final String b in kBandSet.keys) {
        expect(kBandSet[b], (bs[b]! as List<Object?>).cast<String>(), reason: b);
      }
    });

    test('MORE lists and their limits', () {
      final Map<String, Object?> mo = _m(v['more']);
      for (final String b in kMoreSet.keys) {
        expect(kMoreSet[b], (mo[b]! as List<Object?>).cast<String>(), reason: b);
      }
      final Map<String, Object?> lim = _m(v['moreLimit']);
      expect(kMoreLimit, <String, int>{for (final MapEntry<String, Object?> e in lim.entries) e.key: e.value! as int});
    });

    test('GROW: keys, and every page line for line', () {
      expect(kGrowKeys, (v['growKeys']! as List<Object?>).cast<int>());
      final Map<String, Object?> g = _m(v['grow']);
      expect(kGrowPages.keys.map((int k) => '$k').toSet(), g.keys.toSet());
      for (final MapEntry<int, GrowPage> e in kGrowPages.entries) {
        final Map<String, Object?> p = _m(g['${e.key}']);
        expect(e.value.eyebrow, p['eb']);
        expect(e.value.lead, p['lead']);
        expect(e.value.dest, p['dest']);
        expect(e.value.cta, p['cta']);
        expect(e.value.scene, p['scene']);
        expect(e.value.say, p['say']);
        expect(e.value.teen, p['teen'] == true);
        expect(e.value.quiet, p['quiet'] == true);
        final List<Object?> items = p['items']! as List<Object?>;
        expect(e.value.items.length, items.length, reason: 'page ${e.key}');
        for (int i = 0; i < items.length; i++) {
          final List<Object?> it = items[i]! as List<Object?>;
          expect(<String>[e.value.items[i].kind, e.value.items[i].title, e.value.items[i].body], <Object?>[it[0], it[1], it[2]],
              reason: 'page ${e.key} item $i');
        }
      }
    });
  });

  group('the four homes: Dart draws exactly what the prototype drew, at every age 3 to 17', () {
    final Map<String, Object?> homes = _m(v['homes']);
    for (int age = 3; age <= 17; age++) {
      test('age $age', () {
        final Map<String, Object?> h = _m(homes['$age']);
        final String protoBand = h['band']! as String;
        // Her band by age is the prototype's (bandOf): 3-4, 5-7, 8-12, 13-17.
        final String mine = age <= 4 ? 't34' : age <= 7 ? 't57' : age <= 12 ? 't812' : 't1317';
        expect(mine, protoBand);
        final List<String> drawn = _ids(h['tiles']);
        if (age <= 4) {
          // The youngest home is AgeHome34 (its own widget); the table covers its three big tiles.
          expect(homeLayoutFor(protoBand).all, drawn.take(3).toList());
          return;
        }
        expect(homeLayoutFor(protoBand, age: age).all, drawn, reason: 'layout order, tile for tile');
        // The tier of every tile.
        final HomeLayout l = homeLayoutFor(protoBand, age: age);
        for (final Object? t in h['tiles']! as List<Object?>) {
          final Map<String, Object?> tt = _m(t);
          final String id = tt['id']! as String;
          final String tier = tt['tier']! as String;
          expect(
              tier == 'hero' ? l.hero.contains(id)
                  : tier == 'strip' ? l.strip.contains(id)
                  : tier == 'featured' ? l.featured.contains(id)
                  : l.standard.contains(id),
              isTrue, reason: '$id is $tier in the prototype at $age');
          expect(bandTileTitle(id, protoBand), tt['title'], reason: 'title of $id at $age');
        }
      });
    }

    test('the layout of a band is its BANDSET (as a set), at its first age', () {
      for (final String b in <String>['t57', 't812', 't1317']) {
        final int first = <String, int>{'t57': 5, 't812': 8, 't1317': 13}[b]!;
        expect(homeLayoutFor(b, age: first).all.toSet(), kBandSet[b]!.toSet(), reason: b);
      }
    });
  });

  group('the More page: moreIdsFor equals the prototype\'s render for every age and with or without a birthday', () {
    final Map<String, Object?> mores = _m(v['mores']);
    final Map<String, Object?> withB = _m(v['moresWithBirthday']);
    for (int age = 5; age <= 17; age++) {
      test('age $age, no birthday on file', () {
        final String band = age <= 7 ? 't57' : age <= 12 ? 't812' : 't1317';
        final List<String> drawn = _ids(mores['$age']).where((String i) => i != 'grownup').toList();
        expect(moreIdsFor(band, age, hasBirthday: false, shelfOn: true), drawn);
      });
    }
    for (int age = 5; age <= 12; age++) {
      test('age $age, a birthday on file', () {
        final String band = age <= 7 ? 't57' : 't812';
        final List<String> drawn = (withB['$age']! as List<Object?>).cast<String>().where((String i) => i != 'grownup').toList();
        expect(moreIdsFor(band, age, hasBirthday: true, shelfOn: true), drawn);
      });
    }
    test('a hidden tile leaves the page, Messages is not a thing that can be hidden', () {
      expect(moreIdsFor('t57', 6, hasBirthday: false, shelfOn: true, hidden: <String>{'jokes'}), isNot(contains('jokes')));
      expect(tileHideable('msgs'), isFalse);
      expect(tileHideable('play'), isTrue);
      expect(visibleHomeIds('t57', 6, hidden: <String>{'msgs', 'stories'}), contains('msgs'));
      expect(visibleHomeIds('t57', 6, hidden: <String>{'msgs', 'stories'}), isNot(contains('stories')));
    });
  });

  group('tiles appear only if their destination exists', () {
    test('feel, shelf and the grown-up door have none yet, so no home or More page draws them', () {
      for (final String id in <String>['feel', 'shelf', 'grownup']) {
        expect(kTilesWithDestination.contains(id), isFalse, reason: id);
      }
      for (final String b in kBandSet.keys) {
        for (int age in <int>[5, 8, 13, 14]) {
          final List<String> shown = visibleHomeIds(b, age);
          for (final String id in <String>['feel', 'shelf', 'grownup']) {
            expect(shown, isNot(contains(id)), reason: '$id in $b');
          }
        }
      }
    });

    test('wave 2b: cal and privacy have destinations now, and only the 13 to 17 home carries them', () {
      for (final String id in <String>['cal', 'privacy']) {
        expect(kTilesWithDestination.contains(id), isTrue, reason: id);
      }
      for (final String b in <String>['t34', 't57', 't812']) {
        for (final String id in <String>['cal', 'privacy']) {
          expect(visibleHomeIds(b, 9), isNot(contains(id)), reason: '$id in $b');
        }
      }
      expect(visibleHomeIds('t1317', 15), containsAll(<String>['cal', 'privacy', 'journal', 'ladder']));
    });

    test('a family structure switch removes a tile (Play when the games area is off), and only that tile', () {
      final List<String> all = visibleHomeIds('t57', 6);
      final List<String> noPlay = visibleHomeIds('t57', 6, viewTiles: <String>['myDay', 'messages', 'stories', 'showTell', 'myPeople', 'more']);
      expect(all.toSet().difference(noPlay.toSet()), <String>{'play'});
    });
  });

  group('the renames', () {
    test('Games at 8-12, Downtime at 13-17, Studio, Today', () {
      expect(<String>[bandTileTitle('play', 't57'), bandTileTitle('play', 't812'), bandTileTitle('play', 't1317')],
          <String>['Play together', 'Games', 'Downtime']);
      expect(<String>[bandTileTitle('draw', 't57'), bandTileTitle('draw', 't1317')], <String>['Draw & colour', 'Studio']);
      expect(<String>[bandTileTitle('day', 't57'), bandTileTitle('day', 't1317')], <String>['My day', 'Today']);
    });
    test('the client\'s 13-and-up band is the prototype\'s 13-17', () {
      expect(protoBand('t13'), 't1317');
      expect(protoBand('t57'), 't57');
    });
  });

  group('P1-P11: nothing in the table can carry a count, score, streak, reward or trophy', () {
    test('no title, line or page text uses the forbidden vocabulary', () {
      final RegExp bad = RegExp(r'\b(score|points?|streak|reward|trophy|badge|level|win|winner|prize|stars?)\b', caseSensitive: false);
      for (final BandTile t in kBandTiles.values) {
        expect(bad.hasMatch('${t.title} ${t.sub} ${t.alt.values.join(' ')}'), isFalse, reason: t.id);
      }
      for (final GrowPage p in kGrowPages.values) {
        final String text = '${p.eyebrow} ${p.lead} ${p.cta} ${p.items.map((GrowItem i) => '${i.title} ${i.body}').join(' ')}';
        expect(bad.hasMatch(text), isFalse, reason: p.eyebrow);
      }
    });
  });
}
