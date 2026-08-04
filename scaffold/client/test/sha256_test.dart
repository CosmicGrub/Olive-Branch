// OLIVE BRANCH — SHA-256 port tests. MASTERFILE §16.1 #3.
//
// The two canonical NIST vectors packages/ledger/test checks the TS
// implementation against, plus a couple of properties that would catch the
// classic hand-rolled-hash bugs (padding boundary, avalanche).
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/sha256.dart';

void main() {
  group('sha256Hex — §16.1 #3', () {
    test('empty string matches the NIST vector', () {
      expect(sha256Hex(''),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('"abc" matches the NIST vector', () {
      expect(sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('is deterministic — same input, same digest, every call', () {
      const String s = 'the archive belongs to the child';
      expect(sha256Hex(s), sha256Hex(s));
    });

    test('a one-character change produces a completely different digest', () {
      final String a = sha256Hex('Pickup moved to 4:30 today.');
      final String b = sha256Hex('Pickup moved to 4:31 today.');
      expect(a, isNot(b));
    });

    test('handles a message that lands exactly on a 64-byte block boundary', () {
      // 55 bytes is the largest single-block message (64 - 1 tag byte - 8
      // length bytes); 56 bytes is the smallest that must spill into a
      // second block. Both are classic off-by-one spots in a hand-rolled
      // padder.
      final String h55 = sha256Hex(''.padLeft(55, 'a'));
      final String h56 = sha256Hex(''.padLeft(56, 'a'));
      expect(h55.length, 64);
      expect(h56.length, 64);
      expect(h55, isNot(h56));
    });

    test('every digest is 64 lowercase hex characters', () {
      final String h = sha256Hex('some export content');
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });
  });
}
