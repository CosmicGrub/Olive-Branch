// OLIVE BRANCH — what a child's tablet may hold, and the source guards that keep every lost-phone screen and every
// erase away from her side. Verified by CI, headless.
//
// The point: a stolen tablet gives away HER side only. A grown-up's working records are never written on it, the
// grown-up-only key can never be stored on it, and nothing on it is ever erased, covered or counted by the lost-phone
// code (a child sees no notice, error, count or reason; MASTERFILE section 2.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_tablet_holdings.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

String _src(String f) => File('lib/$f').readAsStringSync();

List<String> _libFiles() => Directory('lib')
    .listSync()
    .whereType<File>()
    .map((File f) => f.uri.pathSegments.last)
    .where((String n) => n.endsWith('.dart'))
    .toList()
  ..sort();

void main() {
  group('the two lists cover the whole catalogue', () {
    test('every catalogued area is decided: grown-up only, or allowed on a child\'s tablet', () {
      expect(unclassifiedAreas(), isEmpty,
          reason: 'a new area needs a decision in child_tablet_holdings.dart: may a stolen child tablet hold it?');
    });

    test('no name in the lists is missing from the catalogue (a typo would silently weaken a guard)', () {
      expect(unknownAreasInLists(), isEmpty);
    });

    test('the lists do not overlap', () {
      expect(kGrownUpOnlyAreas.intersection(kChildTabletAreas), isEmpty);
    });

    test('her private areas are hers and are NOT among the grown-up-only ones (no grown-up key opens them)', () {
      for (final String a in <String>['journal', 'worries', 'feelings', 'mymarks']) {
        expect(kChildTabletAreas, contains(a));
        expect(kGrownUpOnlyAreas, isNot(contains(a)));
      }
    });

    test('the grown-up working records are all on the grown-up-only list', () {
      for (final String a in <String>['coordination', 'aboutchild', 'aboutplans', 'emergencycard', 'passes', 'compass',
        'localpin', 'localfamily', 'pairedkids', 'familyledger', 'familysync', 'trust', 'learn', 'screenshares']) {
        expect(kGrownUpOnlyAreas, contains(a));
      }
    });
  });

  group('on a child\'s tablet a grown-up\'s record cannot be written', () {
    test('writing to every grown-up-only area is refused (the store is "full": zero bytes), and reading gives nothing', () async {
      final LocalServices tablet = LocalServices.memory(childTablet: true);
      for (final String a in kGrownUpOnlyAreas) {
        final LocalNamespace ns = tablet.area(a);
        await expectLater(ns.put('k', 'v'), throwsA(isA<LocalStoreFull>()), reason: a);
        expect(await ns.get('k'), isNull, reason: a);
      }
    });

    test('her own areas and the device\'s own words write as normal', () async {
      final LocalServices tablet = LocalServices.memory(childTablet: true);
      for (final String a in <String>['journal', 'lists', 'colour', 'role', 'memorybox']) {
        await tablet.area(a).put('k', 'v');
        expect(await tablet.area(a).get('k'), 'v', reason: a);
      }
    });

    test('a grown-up\'s phone is unchanged: every area writes as before', () async {
      final LocalServices phone = LocalServices.memory();
      for (final LocalDataEntry e in localDataCatalogue) {
        await phone.area(e.area).put('k', 'v');
        expect(await phone.area(e.area).get('k'), 'v', reason: e.area);
      }
    });

    test('nothing is deleted by the guard: what a tablet already held can still be read', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices before = LocalServices.memory(backend: backend);
      await before.area('compass').put('k', 'was here');
      // the same storage, opened as a child's tablet: the old content is still there to read, and nothing erased it
      final LocalServices tablet = LocalServices(store: before.store, childId: 'demo-child', childTablet: true);
      expect(await tablet.area('compass').get('k'), 'was here');
    });
  });

  group('keys', () {
    test('a child\'s keyring can never store the grown-up-only key (the family key is all it can hold)', () {
      final FamilyKeyring tablet = FamilyKeyring(guardianDevice: false);
      expect(() => tablet.putGk(0, List<int>.filled(32, 7)), throwsStateError);
      tablet.putFk(0, List<int>.filled(32, 9));
      expect(tablet.fk(0), isNotNull);
      expect(tablet.gkEpochs, isEmpty);
      expect(() => tablet.guardianSealKey(0), throwsStateError);
    });
  });

  group('the lost-phone code stays off the child\'s side (source guards)', () {
    const List<String> lostPhoneFiles = <String>[
      'lost_device_screens.dart', 'lost_device_logic.dart', 'lost_device_boot.dart', 'lost_device_words.dart'
    ];

    test('no child screen, the kiosk shell or the child entry point imports a lost-phone file or the standing', () {
      final List<String> childSide = <String>[
        for (final String f in _libFiles())
          if (f.startsWith('child_') || f == 'kiosk_shell.dart' || f == 'main_live.dart' || f.startsWith('her_') || f == 'adult_gate.dart') f,
      ];
      expect(childSide, isNotEmpty);
      for (final String f in childSide) {
        final String s = _src(f);
        for (final String bad in <String>[...lostPhoneFiles, 'device_standing.dart']) {
          expect(s, isNot(contains("'$bad'")), reason: '$f must not import $bad');
        }
      }
    });

    test('A-05: the only code that erases the app\'s store is the owner-ordered erase, the clear-data screen a grown-up opens, and the store itself', () {
      final List<String> callers = <String>[
        for (final String f in _libFiles())
          if (_src(f).contains('.wipeAll(') || _src(f).contains('wipeAll,') || _src(f).contains('services.wipeAll')) f,
      ];
      expect(callers.toSet().difference(<String>{'lost_device_boot.dart', 'clear_local_data_screen.dart', 'local_services.dart'}), isEmpty);
    });

    test('the erase hook is installed only by the grown-up boot, never by a child path', () {
      final List<String> setters = <String>[
        for (final String f in _libFiles())
          if (_src(f).contains('onEraseOrdered =')) f,
      ];
      expect(setters.toSet(), <String>{'device_standing.dart', 'lost_device_boot.dart'},
          reason: 'the standing file only resets it to null');
      expect(_src('guardian_boot.dart'), contains('startLostDeviceWatch'));
      expect(_src('main_live.dart'), isNot(contains('startLostDeviceWatch')));
    });

    test('the child\'s tablet boots with the tablet guard on, in both child routes', () {
      final String s = _src('main_live.dart');
      expect(RegExp(r'_openLocalStorage\(childId, childTablet: true\)').hasMatch(s), isTrue);
      expect(RegExp(r'_openLocalStorage\(p\.cert\.childId, childTablet: true\)').hasMatch(s), isTrue);
    });

    test('no place, address or network name is asked for, kept or sent by the lost-phone code (MASTERFILE P3)', () {
      final RegExp place = RegExp(r'(latitude|longitude|geolocator|gps|ssid|bssid|ipaddress|ip_address|wifiname|macaddress)', caseSensitive: false);
      for (final String f in lostPhoneFiles) {
        expect(place.hasMatch(_src(f)), isFalse, reason: f);
      }
    });

    test('the standing is one word in secure storage next to the sign-in, not a catalogued area (an erase wipes the catalogue and its key)', () {
      expect(localDataCatalogue.any((LocalDataEntry e) => e.area == 'devicestanding'), isFalse);
      final String s = _src('device_standing.dart');
      expect(s, contains('olive.device_standing'));
      expect(s, isNot(contains('area(')));
    });
  });
}
