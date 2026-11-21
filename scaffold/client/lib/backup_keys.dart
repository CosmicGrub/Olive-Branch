// OLIVE BRANCH — the keys behind an encrypted backup, and the plain words a grown-up writes down. UNVERIFIED on a
// device; pure Dart, runs headless in CI (client/test/backup_keys_test.dart). Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// WRITE-ONLY BACKUPS. A backup is locked to a PUBLIC key. A phone that makes backups keeps only that public half, so
// a phone that is stolen while unlocked can still make a new backup but cannot open any backup it ever made. The
// matching secret half is not stored anywhere on the phone: it is shown once, as words, to be written on paper
// (the "recovery sheet"), and is typed back only to restore.
//
// ONE SECRET, ONE KEY PAIR. A secret is 20 random bytes (160 bits). The X25519 key pair is derived from it with
// HKDF-SHA256, so the paper IS the key: nothing else needs to be stored or recovered from the server, and the server
// never sees either half. The same shape serves three purposes, each with its own domain-separated derivation, so a
// secret for one purpose never yields the key for another:
//   family   the family backup (grown-ups' records). The sheet is held by the family.
//   keep     her pictures and memories on her tablet. Held on the tablet. May be written on a "keepsake sheet" ONLY if
//            the family chooses to (owner decision), because whoever holds that sheet can then open them.
//   private  her private areas (journal, worry box, feelings, teen choices, door marks). Held on the tablet ONLY. It is
//            never written on any sheet and never given to a grown-up's phone: no grown-up key opens it (P7).
//
// THE WORDS. 12 bits per word, from the 4096 pronounceable words "consonant vowel consonant vowel" (16 consonants,
// 4 vowels): no word list to ship, nothing that looks like a real sentence, easy to say and to copy. The secret's bytes
// plus an 8-bit check are cut into 12-bit pieces; 20 bytes make 14 words. A mistyped word or a swapped pair is caught
// by the check before anything is tried. The check is a typo guard only; the key's strength is the 160 random bits.
//
// This is a composition of vetted primitives (X25519, HKDF-SHA256, AES-256-GCM in backup_format.dart) with no outside
// review (decision D2); it is on the list the external cryptographer is given.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'sha256.dart';

/// What a secret locks. Values are wire/storage words; never change one.
enum BackupPurpose {
  family('family'),
  keep('keep'),
  private('private');

  const BackupPurpose(this.word);
  final String word;
}

/// How many bytes a secret has.
const int kSecretBytes = 20;

Uint8List newBackupSecret([Random? random]) {
  final Random r = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(kSecretBytes, (_) => r.nextInt(256)));
}

const String _consonants = 'bdfghjklmnprstvz';
const String _vowels = 'aeio';

/// Word number [i] (0 to 4095).
String _wordAt(int i) =>
    '${_consonants[(i >> 8) & 15]}${_vowels[(i >> 6) & 3]}${_consonants[(i >> 2) & 15]}${_vowels[i & 3]}';

int? _indexOf(String w) {
  if (w.length != 4) return null;
  final int c1 = _consonants.indexOf(w[0]), v1 = _vowels.indexOf(w[1]);
  final int c2 = _consonants.indexOf(w[2]), v2 = _vowels.indexOf(w[3]);
  if (c1 < 0 || v1 < 0 || c2 < 0 || v2 < 0) return null;
  return (c1 << 8) | (v1 << 6) | (c2 << 2) | v2;
}

int _check(List<int> bytes) =>
    sha256Bytes(Uint8List.fromList(<int>[...utf8.encode('olive-words-v1'), ...bytes]))[0];

/// Why words could not be read back. Plain-word versions are in [describeWordsProblem].
enum WordsProblem { empty, wrongCount, notAWord, checkFailed }

class WordsResult {
  const WordsResult.ok(this.bytes)
      : problem = null,
        badWord = null;
  const WordsResult.no(this.problem, {this.badWord}) : bytes = null;
  final Uint8List? bytes;
  final WordsProblem? problem;

  /// 1-based position of the first word that is not one of ours.
  final int? badWord;
  bool get ok => bytes != null;
}

/// The words for [secret] (a whole number of bytes).
List<String> secretToWords(Uint8List secret) {
  final List<int> bits = <int>[];
  void push(int byte) {
    for (int i = 7; i >= 0; i--) {
      bits.add((byte >> i) & 1);
    }
  }
  for (final int b in secret) {
    push(b);
  }
  push(_check(secret));
  while (bits.length % 12 != 0) {
    bits.add(0);
  }
  final List<String> out = <String>[];
  for (int i = 0; i < bits.length; i += 12) {
    int v = 0;
    for (int j = 0; j < 12; j++) {
      v = (v << 1) | bits[i + j];
    }
    out.add(_wordAt(v));
  }
  return out;
}

/// Reads [text] (words separated by spaces, dashes, commas or new lines, any capitals) back into [expectedBytes]
/// bytes, or says why it could not.
WordsResult wordsToSecret(String text, {int expectedBytes = kSecretBytes}) {
  final List<String> words = text
      .toLowerCase()
      .split(RegExp(r'[\s,;.\-_/]+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const WordsResult.no(WordsProblem.empty);
  final int needBits = expectedBytes * 8 + 8;
  final int needWords = (needBits + 11) ~/ 12;
  final List<int> bits = <int>[];
  for (int i = 0; i < words.length; i++) {
    final int? idx = _indexOf(words[i]);
    if (idx == null) return WordsResult.no(WordsProblem.notAWord, badWord: i + 1);
    for (int j = 11; j >= 0; j--) {
      bits.add((idx >> j) & 1);
    }
  }
  if (words.length != needWords) return const WordsResult.no(WordsProblem.wrongCount);
  int byteAt(int bitStart) {
    int v = 0;
    for (int j = 0; j < 8; j++) {
      v = (v << 1) | bits[bitStart + j];
    }
    return v;
  }
  final Uint8List secret = Uint8List(expectedBytes);
  for (int i = 0; i < expectedBytes; i++) {
    secret[i] = byteAt(i * 8);
  }
  final int check = byteAt(expectedBytes * 8);
  for (int i = needBits; i < bits.length; i++) {
    if (bits[i] != 0) return const WordsResult.no(WordsProblem.checkFailed);
  }
  if (check != _check(secret)) return const WordsResult.no(WordsProblem.checkFailed);
  return WordsResult.ok(secret);
}

/// What to tell a grown-up when [r] did not read. Plain words, one next step.
String describeWordsProblem(WordsResult r) {
  switch (r.problem) {
    case WordsProblem.empty:
      return 'Type the words from your paper.';
    case WordsProblem.wrongCount:
      return 'That is not the right number of words. Your sheet has $kSheetWordCount words in a row. '
          'Check that none is missing or doubled.';
    case WordsProblem.notAWord:
      return 'Word number ${r.badWord} is not one of the words on a sheet. Check it against your paper, '
          'letter by letter.';
    case WordsProblem.checkFailed:
      return 'The words are all real, but they do not fit together. One may be copied wrongly or out of order. '
          'Check each one against your paper.';
    case null:
      return '';
  }
}

/// How many words a one-secret sheet has.
final int kSheetWordCount = secretToWords(Uint8List(kSecretBytes)).length;

/// Both halves of a backup key. The seed is the secret half: keep it in memory only as long as a restore needs it.
class BackupKeyPair {
  BackupKeyPair._(this.purpose, this._seed, this.publicKey);
  final BackupPurpose purpose;
  final Uint8List _seed;
  final Uint8List publicKey;

  /// The secret half, as X25519 private bytes. Used only to open a backup.
  Uint8List get privateSeed => Uint8List.fromList(_seed);

  /// Derives the pair for [secret] and [purpose].
  static Future<BackupKeyPair> fromSecret(Uint8List secret, BackupPurpose purpose) async {
    final SecretKey k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: SecretKey(secret), info: utf8.encode('olive/backup/seed/v1/${purpose.word}'));
    final Uint8List seed = Uint8List.fromList(await k.extractBytes());
    final SimpleKeyPair kp = await X25519().newKeyPairFromSeed(seed);
    final SimplePublicKey pub = await kp.extractPublicKey();
    return BackupKeyPair._(purpose, seed, Uint8List.fromList(pub.bytes));
  }
}

/// A short code printed on the sheet and shown in the status line so a grown-up can tell which sheet goes with which
/// backup. Four letters or digits from a hash of the PUBLIC key: it reveals nothing about the secret.
String sheetIdOf(List<int> publicKey) {
  final Uint8List h = sha256Bytes(Uint8List.fromList(<int>[...utf8.encode('olive-sheet-id-v1'), ...publicKey]));
  const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return String.fromCharCodes(<int>[for (int i = 0; i < 4; i++) alphabet.codeUnitAt(h[i] % alphabet.length)]);
}

/// Everything the paper says, in order, for display and printing. Never stored by the app.
class RecoverySheet {
  RecoverySheet._(this.purpose, this.secret, this.words, this.sheetId, this.publicKey);
  final BackupPurpose purpose;
  final Uint8List secret;
  final List<String> words;
  final String sheetId;
  final Uint8List publicKey;

  static Future<RecoverySheet> make(BackupPurpose purpose, {Random? random}) async {
    final Uint8List secret = newBackupSecret(random);
    return fromSecret(secret, purpose);
  }

  static Future<RecoverySheet> fromSecret(Uint8List secret, BackupPurpose purpose) async {
    final BackupKeyPair kp = await BackupKeyPair.fromSecret(secret, purpose);
    return RecoverySheet._(purpose, secret, secretToWords(secret), sheetIdOf(kp.publicKey), kp.publicKey);
  }

  String get firstWord => words.first;
  String get lastWord => words.last;

  /// Words in rows of seven, the way the paper is laid out.
  List<List<String>> get rows => <List<String>>[
        for (int i = 0; i < words.length; i += 7) words.sublist(i, min(i + 7, words.length)),
      ];

  /// The "type the first and last words" check, straight after the sheet is shown. Capitals and spaces do not matter.
  bool echoMatches(String first, String last) =>
      first.trim().toLowerCase() == firstWord && last.trim().toLowerCase() == lastWord;
}

/// The two secrets a child's tablet keeps, and the single code a grown-up carries from the old tablet to the new
/// one. The code is both secrets back to back, so a grown-up types or scans ONE thing.
class ChildSecrets {
  ChildSecrets({required this.keep, required this.private})
      : assert(keep.length == kSecretBytes),
        assert(private.length == kSecretBytes);
  final Uint8List keep;
  final Uint8List private;

  static ChildSecrets make([Random? random]) =>
      ChildSecrets(keep: newBackupSecret(random), private: newBackupSecret(random));

  List<String> get handoverWords => secretToWords(Uint8List.fromList(<int>[...keep, ...private]));

  Map<String, Object?> toJson() => <String, Object?>{'keep': base64Encode(keep), 'private': base64Encode(private)};

  static ChildSecrets? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final Object? k = raw['keep'], p = raw['private'];
      if (k is! String || p is! String) return null;
      final Uint8List kb = base64Decode(k), pb = base64Decode(p);
      if (kb.length != kSecretBytes || pb.length != kSecretBytes) return null;
      return ChildSecrets(keep: kb, private: pb);
    } catch (_) {
      return null;
    }
  }

  /// Reads a hand-over code typed or scanned on the new tablet.
  static WordsResult readHandover(String text) => wordsToSecret(text, expectedBytes: kSecretBytes * 2);

  static ChildSecrets fromHandover(Uint8List both) => ChildSecrets(
      keep: Uint8List.fromList(both.sublist(0, kSecretBytes)),
      private: Uint8List.fromList(both.sublist(kSecretBytes)));
}
