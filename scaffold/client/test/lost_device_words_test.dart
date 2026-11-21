// OLIVE BRANCH — every sentence a grown-up is shown about a lost or stolen phone or tablet, read as a whole. Verified by
// CI, headless. The words are checked as a set: short sentences, calm, no promise the app cannot keep, the honest limit
// said wherever "Mark as lost" is offered, and nothing a child could be shown.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/lost_device_words.dart';

void main() {
  final List<String> all = LostDeviceWords.everySentence();

  test('there are sentences, and none is empty', () {
    expect(all.length, greaterThan(40));
    for (final String s in all) {
      expect(s.trim(), isNotEmpty);
    }
  });

  test('every sentence is short enough to read at a glance (30 words at most)', () {
    for (final String s in all) {
      for (final String sentence in s.split(RegExp(r'(?<=[.?!])\s+'))) {
        final int words = sentence.trim().split(RegExp(r'\s+')).length;
        expect(words, lessThanOrEqualTo(30), reason: sentence);
      }
    }
  });

  test('calm: none of the frightening words, and the app never says "stolen"', () {
    final RegExp fear = RegExp(r'\b(stolen|steal|thief|thieves|hack|hacked|attack|danger|dangerous|panic|urgent|warning|alert|breach|compromised)\b', caseSensitive: false);
    for (final String s in all) {
      expect(fear.hasMatch(s), isFalse, reason: s);
    }
  });

  test('no place, map, network or tracking word anywhere (MASTERFILE P3): the erase line says what it cannot do', () {
    final RegExp place = RegExp(r'\b(gps|map|coordinates|location|locate|track|tracking|wi-?fi|ssid|ip address|nearby|latitude|longitude)\b', caseSensitive: false);
    for (final String s in all) {
      expect(place.hasMatch(s), isFalse, reason: s);
    }
    expect(LostDeviceWords.eraseLines.join(' '), contains('cannot find the phone'));
  });

  test('the honest limit is on every screen that offers "Mark as lost" and never over-promises', () {
    expect(LostDeviceWords.markLines, contains(kLostHonestLimit));
    expect(kLostHonestLimit, contains('cannot take back what was already on the phone'));
    expect(kLostHonestLimit, contains('open'));
    for (final String s in all) {
      expect(s.toLowerCase(), isNot(contains('locked behind')), reason: 'no unconditional "stays locked" promise: $s');
    }
    // the cover on a cut-off phone says what stays on it, not that nothing does
    expect(LostDeviceWords.cutOffCoverBody, contains('What was already on this phone stays on it'));
  });

  test('nothing is ever promised that the app does not do: no "remote lock", no "remote control", no "wipe"', () {
    for (final String s in all) {
      final String l = s.toLowerCase();
      expect(l, isNot(contains('remote')), reason: s);
      expect(l, isNot(contains('wipe')), reason: s);
      expect(l, isNot(contains('lock your phone from')), reason: s);
    }
  });

  test('"Nothing is deleted" is never said about an erase, and "Your records are safe" is said wherever one is', () {
    expect(LostDeviceWords.eraseLines.first, contains('erase its own copy'));
    expect(LostDeviceWords.eraseLines.join(' '), contains('Your records are not lost'));
    expect(LostDeviceWords.erasedCoverBody, contains('safe with the family'));
    expect(LostDeviceWords.erasedLine, contains('safe with the family'));
    expect(LostDeviceWords.noticeErasedLine, contains('safe'));
  });

  test('an erase says it starts after 24 hours and that any grown-up can call it off', () {
    expect(LostDeviceWords.eraseLines.join(' '), contains('24 hours'));
    expect(LostDeviceWords.eraseLines.join(' '), contains('any grown-up can call it off'));
    expect(LostDeviceWords.noticeEraseOrderedLine, contains('24 hours'));
  });

  test('a tablet is never offered an erase, in words either', () {
    expect(LostDeviceWords.eraseNotForTablets, contains("child's tablet"));
    expect(LostDeviceWords.refusal('not_a_grown_up_phone'), LostDeviceWords.eraseNotForTablets);
  });

  test('names are used as the family gave them, with no surname and no label', () {
    expect(LostDeviceWords.deviceName(isChild: false, ownerName: 'Alex', childName: null, isThisDevice: false), "Alex's phone");
    expect(LostDeviceWords.deviceName(isChild: false, ownerName: 'Jess', childName: null, isThisDevice: false), "Jess' phone");
    expect(LostDeviceWords.deviceName(isChild: true, ownerName: null, childName: null, isThisDevice: false), "A child's tablet");
    expect(LostDeviceWords.deviceName(isChild: true, ownerName: null, childName: 'Ivy', isThisDevice: false), "Ivy's tablet");
    expect(LostDeviceWords.deviceName(isChild: false, ownerName: 'Alex', childName: null, isThisDevice: true), 'This phone');
  });

  test('how long is left reads in plain units', () {
    final DateTime now = DateTime.utc(2026, 11, 1, 12);
    expect(LostDeviceWords.endsIn(now.add(const Duration(minutes: 20)), now), 'less than an hour');
    expect(LostDeviceWords.endsIn(now.add(const Duration(hours: 5)), now), 'about 5 hours');
    expect(LostDeviceWords.endsIn(now.add(const Duration(hours: 71)), now), 'about 2 days');
  });

  test('every refusal the server can send has its own plain sentence, and an unknown one still reads kindly', () {
    for (final String e in <String>['rate_limited', 'owner_only', 'already_revoked', 'too_late', 'stale_incident', 'not_paused', 'this_device', 'not_found', 'no_other_copy', 'not_a_grown_up_phone', 'no_erase_ordered', 'already_erased']) {
      expect(LostDeviceWords.refusal(e), isNot(LostDeviceWords.refusal('something_new')), reason: e);
    }
    expect(LostDeviceWords.refusal('something_new'), contains("didn't work"));
  });
}
