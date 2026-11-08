// OLIVE BRANCH — encryption at rest for LocalStore's private namespaces.
// No longer UNVERIFIED — verified by CI (client/test/local_store_test.dart).
//
// AES-256-GCM via the pinned, pure-Dart `cryptography` package (see
// pubspec.yaml for why a vetted cipher and not something built on
// sha256.dart). Each seal draws a fresh random 96-bit nonce; the stored box is
// `nonce | ciphertext | 128-bit tag`. The namespace name is bound in as
// associated data, so a sealed file moved to a different namespace fails to
// open rather than being read as that namespace's data.
//
// The 256-bit key is generated once per install from the platform CSPRNG and
// kept in flutter_secure_storage (Keystore/Keychain) through the same
// [SecureKeyValueStore] seam device_identity.dart already uses, so tests
// inject an in-memory fake. The key never sits on disk beside the data it
// protects. Dropping the key ([StoreCipherKeyring.erase]) makes every sealed
// document permanently unreadable, which is part of what a device wipe does.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'device_identity.dart' show SecureKeyValueStore;

/// Seals and opens whole documents. [open] throws if the box was tampered
/// with, sealed under another key, or sealed for different associated data.
abstract class StoreCipher {
  Future<Uint8List> seal(Uint8List plain, List<int> aad);
  Future<Uint8List> open(Uint8List box, List<int> aad);
}

class AesGcmStoreCipher implements StoreCipher {
  AesGcmStoreCipher(List<int> key) : _key = SecretKey(List<int>.of(key)) {
    if (key.length != 32) throw ArgumentError('AES-256 needs a 32-byte key');
  }

  final SecretKey _key;
  static final AesGcm _algo = AesGcm.with256bits();
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// A fresh random 32-byte key from the platform CSPRNG.
  static Uint8List newKey() {
    final Random r = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  @override
  Future<Uint8List> seal(Uint8List plain, List<int> aad) async {
    final SecretBox box = await _algo.encrypt(plain, secretKey: _key, aad: aad);
    return Uint8List.fromList(box.concatenation());
  }

  @override
  Future<Uint8List> open(Uint8List box, List<int> aad) async {
    final SecretBox parsed =
        SecretBox.fromConcatenation(box, nonceLength: _nonceLength, macLength: _macLength);
    return Uint8List.fromList(await _algo.decrypt(parsed, secretKey: _key, aad: aad));
  }
}

/// Finds (or creates) this install's key in secure storage.
class StoreCipherKeyring {
  StoreCipherKeyring(this._secure);
  final SecureKeyValueStore _secure;

  static const String keyName = 'olive_local_store_key_v1';

  /// The install's cipher. Creates and stores a key on first use.
  Future<StoreCipher> cipher() async {
    final String? stored = await _secure.read(keyName);
    if (stored != null) {
      try {
        final Uint8List bytes = base64Decode(stored);
        if (bytes.length == 32) return AesGcmStoreCipher(bytes);
      } catch (_) {
        // fall through: a damaged key is replaced; the data it sealed is
        // unrecoverable and LocalStore quarantines it on the next load.
      }
    }
    final Uint8List fresh = AesGcmStoreCipher.newKey();
    await _secure.write(keyName, base64Encode(fresh));
    return AesGcmStoreCipher(fresh);
  }

  /// Forgets the key. Everything sealed under it becomes unreadable.
  Future<void> erase() => _secure.delete(keyName);
}
