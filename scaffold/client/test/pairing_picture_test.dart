// OLIVE BRANCH — the persistent pairing picture, pure logic: the payload and its strict parser, the recognition tag,
// the hello proof of possession, the glyph, and the salt and epoch (refresh). UNVERIFIED until CI runs it.
// Hostile inputs on purpose: tampered, truncated, duplicated, oversized, wrong-scheme, cross-scheme and stale
// payloads must all fail closed and silent. Design: docs/planning/PERSISTENT-QR-PAIRING.md.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_qr.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

Uint8List _bytes(int n, int fill) => Uint8List.fromList(List<int>.filled(n, fill));

String _good({String r = 'a', String? k, String? s, String e = '3'}) =>
    'olive://id/1?r=$r&k=${k ?? b64(_bytes(32, 7))}&s=${s ?? b64(_bytes(16, 9))}&e=$e';

void main() {
  group('payload and parser', () {
    test('a picture round-trips and carries only the four public fields', () async {
      final DeviceKey k = await _key();
      final PairingPicture p = PairingPicture(role: PictureRole.child, publicKey: k.publicKey, salt: _bytes(16, 5), epoch: 41);
      final PairingPicture? back = parsePairingPicture(p.payload);
      expect(back, isNotNull);
      expect(back!.role, PictureRole.child);
      expect(back.publicKey, k.publicKey);
      expect(back.salt, _bytes(16, 5));
      expect(back.epoch, 41);
      expect(await back.fingerprint(), k.fingerprint, reason: 'the scanner recomputes the fingerprint, it is not carried');
      expect(p.payload.length, lessThan(120));
      expect(Uri.parse(p.payload).queryParameters.keys.toSet(), <String>{'r', 'k', 's', 'e'});
      for (final String forbidden in <String>['q=', 'sid', 'pin', 'fp=', 'a=', 'name', 'family']) {
        expect(p.payload, isNot(contains(forbidden)));
      }
    });

    test('the epoch bounds: 0 and 65535 pass, 65536 and signs and leading zeros do not', () {
      expect(parsePairingPicture(_good(e: '0')), isNotNull);
      expect(parsePairingPicture(_good(e: '65535')), isNotNull);
      for (final String e in <String>['65536', '-1', '+1', '01', '1.5', '', 'x', '99999', '1e3', ' 1']) {
        expect(parsePairingPicture(_good(e: e)), isNull, reason: 'epoch "$e"');
      }
    });

    test('wrong scheme, host, path, version, role: all refused', () {
      final String g = _good();
      expect(parsePairingPicture(g), isNotNull);
      for (final String bad in <String>[
        g.replaceFirst('olive://', 'https://'),
        g.replaceFirst('olive://', 'OLIVE://'),
        g.replaceFirst('//id/', '//ID/'),
        g.replaceFirst('//id/', '//pair/'),
        g.replaceFirst('/1?', '/2?'),
        g.replaceFirst('/1?', '/?'),
        g.replaceFirst('r=a', 'r=x'),
        g.replaceFirst('r=a', 'r=A'),
        g.replaceFirst('r=a', 'r='),
        '',
        'olive://id',
        'garbage',
      ]) {
        expect(parsePairingPicture(bad), isNull, reason: bad);
      }
    });

    test('key and salt lengths are exact; bad base64 and non-canonical padding bits are refused', () {
      for (final int n in <int>[0, 1, 31, 33, 64]) {
        expect(parsePairingPicture(_good(k: b64(_bytes(n, 1)))), isNull, reason: 'key of $n bytes');
      }
      for (final int n in <int>[0, 15, 17, 32]) {
        expect(parsePairingPicture(_good(s: b64(_bytes(n, 1)))), isNull, reason: 'salt of $n bytes');
      }
      expect(parsePairingPicture(_good(k: '${b64(_bytes(32, 1))}=')), isNull, reason: 'padding is not part of the format');
      expect(parsePairingPicture(_good(k: '${b64(_bytes(32, 1)).substring(0, 42)}!')), isNull);
      // 32 bytes encode to 43 chars; the last char carries 4 spare bits that must be zero.
      final String canonical = b64(_bytes(32, 0));
      expect(canonical.length, 43);
      expect(parsePairingPicture(_good(k: '${canonical.substring(0, 42)}B')), isNull, reason: 'non-canonical trailing bits');
    });

    test('missing, duplicate, extra and reordered-ok keys', () {
      final String k = b64(_bytes(32, 7)), s = b64(_bytes(16, 9));
      expect(parsePairingPicture('olive://id/1?r=a&k=$k&s=$s'), isNull, reason: 'missing e');
      expect(parsePairingPicture('olive://id/1?k=$k&s=$s&e=1'), isNull, reason: 'missing r');
      expect(parsePairingPicture('olive://id/1?r=a&r=c&k=$k&s=$s&e=1'), isNull, reason: 'duplicate r');
      expect(parsePairingPicture('olive://id/1?r=a&k=$k&k=$k&s=$s&e=1'), isNull, reason: 'duplicate k');
      expect(parsePairingPicture('olive://id/1?r=a&k=$k&s=$s&e=1&q=${b64(_bytes(16, 1))}'), isNull, reason: 'an extra secret-looking key');
      expect(parsePairingPicture('olive://id/1?r=a&k=$k&s=$s&e=1&a=10.0.0.1:80'), isNull, reason: 'an address hint');
      expect(parsePairingPicture('olive://id/1?e=1&s=$s&k=$k&r=c'), isNotNull, reason: 'order does not matter');
    });

    test('trailing data, whitespace, userinfo, port, fragment, control characters, oversize', () {
      final String g = _good();
      for (final String bad in <String>[
        '$g#frag', '$g ', ' $g', '$g\n', '$g\r\n', '$g\u0000', 'olive://user@id/1?${g.split('?')[1]}',
        'olive://id:99/1?${g.split('?')[1]}', '$g&', '$g%20', 'olive://id/1/?${g.split('?')[1]}',
        '${g}x' * 3,
      ]) {
        expect(parsePairingPicture(bad), isNull, reason: bad.replaceAll('\n', r'\n'));
      }
      expect(parsePairingPicture('$g${'a' * 200}'), isNull, reason: 'over the length cap');
    });

    test('the two QR schemes refuse each other and a picture is never a pairing QR', () {
      final String pic = _good();
      expect(parsePairingQr(pic), isNull, reason: 'the one-shot parser must not accept a persistent picture');
      final String legacy = 'olive://pair/1?s=${b64(_bytes(16, 1))}&k=${b64(_bytes(16, 2))}&q=${b64(_bytes(16, 3))}&a=192.168.1.5:4242';
      expect(parsePairingQr(legacy), isNotNull);
      expect(parsePairingPicture(legacy), isNull, reason: 'a one-shot QR (it holds a secret) is never read as a picture');
    });

    test('legacy parsePairingQr fails closed on malformed input (the missing negative tests)', () {
      final String s = b64(_bytes(16, 1)), k = b64(_bytes(16, 2)), q = b64(_bytes(16, 3));
      expect(parsePairingQr('olive://pair/1?s=$s&k=$k&q=$q'), isNotNull);
      for (final String bad in <String>[
        '', 'garbage', 'https://pair/1?s=$s&k=$k&q=$q', 'olive://pair/2?s=$s&k=$k&q=$q', 'olive://other/1?s=$s&k=$k&q=$q',
        'olive://pair/1?s=$s&k=$k', 'olive://pair/1?s=$s&q=$q', 'olive://pair/1?k=$k&q=$q',
        'olive://pair/1?s=${b64(_bytes(15, 1))}&k=$k&q=$q', 'olive://pair/1?s=$s&k=${b64(_bytes(17, 2))}&q=$q',
        'olive://pair/1?s=$s&k=$k&q=${b64(_bytes(8, 3))}', 'olive://pair/1?s=!!&k=$k&q=$q',
      ]) {
        expect(parsePairingQr(bad), isNull, reason: bad);
      }
    });

    test('a fuzz of random strings never parses and never throws', () {
      final Random r = Random(20261114);
      const String alphabet = 'olive:/id1?&=rkse0123456789_-AaBbCc%# \n';
      for (int i = 0; i < 3000; i++) {
        final String s = String.fromCharCodes(List<int>.generate(r.nextInt(150), (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))));
        expect(parsePairingPicture(s), isNull, reason: s);
      }
    });
  });

  group('recognition tag', () {
    test('only the right salt and the right window recognise a tag', () async {
      final Uint8List salt = _bytes(16, 1), other = _bytes(16, 2), sidA = _bytes(16, 3), sidB = _bytes(16, 4);
      final Uint8List tag = await rendezvousTag(salt, sidA);
      expect(tag.length, kPictureTagBytes);
      expect(await tagMatches(salt, sidA, tag), isTrue);
      expect(await tagMatches(other, sidA, tag), isFalse, reason: 'a different device');
      expect(await tagMatches(salt, sidB, tag), isFalse, reason: 'a different window');
      expect(await rendezvousTag(salt, sidB), isNot(tag), reason: 'unlinkable across windows without the salt');
    });

    test('a tampered, short, long or empty tag never matches', () async {
      final Uint8List salt = _bytes(16, 1), sid = _bytes(16, 3);
      final Uint8List tag = await rendezvousTag(salt, sid);
      for (int i = 0; i < tag.length; i++) {
        final Uint8List t = Uint8List.fromList(tag)..[i] ^= 1;
        expect(await tagMatches(salt, sid, t), isFalse, reason: 'flipped byte $i');
      }
      expect(await tagMatches(salt, sid, tag.sublist(0, 7)), isFalse);
      expect(await tagMatches(salt, sid, <int>[...tag, 0]), isFalse);
      expect(await tagMatches(salt, sid, <int>[]), isFalse);
    });
  });

  group('hello proof of possession', () {
    test('verifies for the same sid and key; fails for another sid, another key, or a tampered signature', () async {
      final DeviceKey k = await _key(), other = await _key();
      final Uint8List sid = _bytes(16, 8), otherSid = _bytes(16, 9);
      final Uint8List hs = await signHello(k, sid);
      expect(await verifyHello(k.publicKey, sid, hs), isTrue);
      expect(await verifyHello(k.publicKey, otherSid, hs), isFalse, reason: 'replayed into another window');
      expect(await verifyHello(other.publicKey, sid, hs), isFalse, reason: 'presented under someone else\'s key');
      expect(await verifyHello(k.publicKey, sid, Uint8List.fromList(hs)..[0] ^= 1), isFalse);
      expect(await verifyHello(k.publicKey, sid, hs.sublist(0, 63)), isFalse);
      expect(await verifyHello(k.publicKey, sid, <int>[]), isFalse);
      expect(await verifyHello(<int>[1, 2, 3], sid, hs), isFalse);
    });
  });

  group('window glyph', () {
    test('is derived from the session id, deterministic, and carries no name', () {
      final Uint8List sid = Uint8List.fromList(<int>[3, 10, ...List<int>.filled(14, 0)]);
      expect(windowGlyph(sid), windowGlyph(Uint8List.fromList(sid)));
      expect(windowGlyph(sid).colour, inInclusiveRange(0, 5));
      final Set<WindowGlyph> seen = <WindowGlyph>{};
      for (int a = 0; a < 16; a++) {
        for (int b = 0; b < 6; b++) {
          seen.add(windowGlyph(Uint8List.fromList(<int>[a, b, ...List<int>.filled(14, 0)])));
        }
      }
      expect(seen.length, 96, reason: '16 pictures by 6 colours');
    });
  });

  group('salt, epoch and refresh', () {
    test('the first state is made once and kept; the picture is built from it and the device key', () async {
      final MemoryPairingPictureRepository repo = MemoryPairingPictureRepository();
      final PairingPictureService svc = PairingPictureService(repo, random: Random(1));
      final DeviceKey k = await _key();
      final PairingPicture a = await svc.own(k, PictureRole.adult), again = await svc.own(k, PictureRole.adult);
      expect(a.salt, again.salt);
      expect(a.epoch, 0);
      expect(a.publicKey, k.publicKey);
      expect(a.role, PictureRole.adult);
      expect(a.salt.length, 16);
    });

    test('refresh changes the salt and bumps the epoch; the device key is untouched; old copies find nothing', () async {
      final PairingPictureService svc = PairingPictureService(MemoryPairingPictureRepository(), random: Random(2));
      final DeviceKey k = await _key();
      final PairingPicture before = await svc.own(k, PictureRole.child);
      final Uint8List sid = _bytes(16, 6);
      final Uint8List oldTag = await rendezvousTag(before.salt, sid);
      await svc.refresh();
      final PairingPicture after = await svc.own(k, PictureRole.child);
      expect(after.epoch, 1);
      expect(after.salt, isNot(before.salt));
      expect(after.publicKey, before.publicKey, reason: 'refresh never rotates the device key: connected devices stay connected');
      expect(await tagMatches(after.salt, sid, oldTag), isFalse, reason: 'a window addressed to the refreshed picture is invisible to the old copy');
      expect(await tagMatches(before.salt, sid, await rendezvousTag(after.salt, sid)), isFalse);
    });

    test('the epoch wraps at 65535', () async {
      final MemoryPairingPictureRepository repo = MemoryPairingPictureRepository();
      await repo.save(PairingPictureState(_bytes(16, 1), 65535));
      final PairingPictureService svc = PairingPictureService(repo);
      expect((await svc.refresh()).epoch, 0);
    });

    test('a store that cannot be read or written still gives a working picture for this run', () async {
      final PairingPictureService svc = PairingPictureService(_BrokenRepo());
      final PairingPictureState s = await svc.state();
      expect(s.salt.length, 16);
      expect(s.epoch, 0);
    });

    test('the local-store repository round-trips and rejects a damaged record', () async {
      final LocalStore store = LocalStore(backend: MemoryStoreBackend());
      final LocalNamespace ns = store.open(const NamespaceSpec(name: 'devicekey'));
      final LocalStorePairingPictureRepository repo = LocalStorePairingPictureRepository(ns);
      expect(await repo.load(), isNull);
      await repo.save(PairingPictureState(_bytes(16, 4), 12));
      final PairingPictureState? back = await repo.load();
      expect(back!.salt, _bytes(16, 4));
      expect(back.epoch, 12);
      await ns.put('picture', <String, Object?>{'s': 'AAAA', 'e': 1});
      expect(await repo.load(), isNull, reason: 'a short salt is not accepted');
      await ns.put('picture', <String, Object?>{'s': b64(_bytes(16, 4)), 'e': 70000});
      expect(await repo.load(), isNull, reason: 'an out-of-range epoch is not accepted');
      await ns.put('picture', 'junk');
      expect(await repo.load(), isNull);
    });
  });
}

class _BrokenRepo implements PairingPictureRepository {
  @override
  Future<PairingPictureState?> load() async => throw StateError('no disk');
  @override
  Future<void> save(PairingPictureState state) async => throw StateError('no disk');
}
