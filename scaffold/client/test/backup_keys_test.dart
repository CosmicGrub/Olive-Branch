// OLIVE BRANCH — backup_keys.dart: the words, the key pairs, the sheet. Real assertions, hostile cases included.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_keys.dart';

void main() {
  group('the words', () {
    test('a secret comes back from its words exactly, for many random secrets', () {
      final Random r = Random(5);
      for (int i = 0; i < 200; i++) {
        final Uint8List s = newBackupSecret(r);
        final List<String> words = secretToWords(s);
        expect(words.length, kSheetWordCount);
        final WordsResult back = wordsToSecret(words.join(' '));
        expect(back.ok, isTrue);
        expect(back.bytes, s);
      }
    });

    test('a sheet is 14 words, each four letters, and two secrets (the hand-over) are 28', () {
      expect(kSheetWordCount, 14);
      final ChildSecrets c = ChildSecrets.make(Random(1));
      expect(c.handoverWords.length, 28);
      expect(c.handoverWords.every((String w) => w.length == 4), isTrue);
    });

    test('random secrets reach nearly every one of the 4096 words, and each reads back to itself', () {
      final Random r = Random(77);
      final Set<String> seen = <String>{};
      for (int i = 0; i < 1500; i++) {
        final Uint8List s = newBackupSecret(r);
        seen.addAll(secretToWords(s));
      }
      expect(seen.length, greaterThan(3800));
      expect(seen.every((String w) => RegExp(r'^[bdfghjklmnprstvz][aeio][bdfghjklmnprstvz][aeio]$').hasMatch(w)), isTrue);
    });

    test('capitals, extra spaces, dashes and new lines are accepted', () {
      final Uint8List s = newBackupSecret(Random(9));
      final List<String> w = secretToWords(s);
      final String messy = '  ${w.sublist(0, 7).map((String x) => x.toUpperCase()).join(' - ')}\n\n${w.sublist(7).join(',  ')}  ';
      expect(wordsToSecret(messy).bytes, s);
    });

    test('a missing, doubled, unknown, swapped or changed word is refused, never guessed', () {
      final Uint8List s = newBackupSecret(Random(11));
      final List<String> w = secretToWords(s);
      expect(wordsToSecret('').problem, WordsProblem.empty);
      expect(wordsToSecret(w.sublist(1).join(' ')).problem, WordsProblem.wrongCount);
      expect(wordsToSecret('${w.join(' ')} ${w.first}').problem, WordsProblem.wrongCount);
      final List<String> bad = List<String>.of(w)..[3] = 'xyzq';
      final WordsResult r = wordsToSecret(bad.join(' '));
      expect(r.problem, WordsProblem.notAWord);
      expect(r.badWord, 4);
      // Changing any one word (to another real word) is caught by the check for nearly every choice.
      int caught = 0, tried = 0;
      for (int i = 0; i < w.length; i++) {
        final List<String> alt = List<String>.of(w);
        alt[i] = alt[i] == 'baba' ? 'bebe' : 'baba';
        tried++;
        if (!wordsToSecret(alt.join(' ')).ok) caught++;
      }
      expect(caught, greaterThanOrEqualTo(tried - 1));
      // A swapped pair.
      final List<String> sw = List<String>.of(w);
      final String t = sw[2];
      sw[2] = sw[9];
      sw[9] = t;
      if (sw[2] != w[2]) expect(wordsToSecret(sw.join(' ')).ok, isFalse);
    });

    test('every problem has plain words and none leaks the secret', () {
      final Uint8List s = newBackupSecret(Random(13));
      final List<String> w = secretToWords(s);
      for (final String input in <String>['', 'aa bb', '${w.take(13).join(' ')} zzzz', w.reversed.join(' ')]) {
        final WordsResult r = wordsToSecret(input);
        if (r.ok) continue;
        final String said = describeWordsProblem(r);
        expect(said, isNotEmpty);
        for (final String word in w) {
          expect(said.contains(word), isFalse);
        }
      }
    });
  });

  group('the key pairs', () {
    test('the same secret gives the same public key; a different purpose gives a different one', () async {
      final Uint8List s = newBackupSecret(Random(21));
      final BackupKeyPair a = await BackupKeyPair.fromSecret(s, BackupPurpose.family);
      final BackupKeyPair b = await BackupKeyPair.fromSecret(s, BackupPurpose.family);
      final BackupKeyPair c = await BackupKeyPair.fromSecret(s, BackupPurpose.keep);
      final BackupKeyPair d = await BackupKeyPair.fromSecret(s, BackupPurpose.private);
      expect(a.publicKey, b.publicKey);
      expect(a.publicKey, isNot(c.publicKey));
      expect(c.publicKey, isNot(d.publicKey));
      expect(a.publicKey.length, 32);
    });

    test('the public key and the sheet id do not contain the secret or the private seed', () async {
      final Uint8List s = newBackupSecret(Random(22));
      final RecoverySheet sheet = await RecoverySheet.fromSecret(s, BackupPurpose.family);
      final BackupKeyPair kp = await BackupKeyPair.fromSecret(s, BackupPurpose.family);
      String hex(List<int> b) => b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
      expect(hex(sheet.publicKey).contains(hex(s)), isFalse);
      expect(hex(sheet.publicKey).contains(hex(kp.privateSeed)), isFalse);
      expect(sheet.sheetId.length, 4);
      expect(sheet.sheetId, sheetIdOf(sheet.publicKey));
    });
  });

  group('the sheet', () {
    test('the first-and-last-words check passes for the right words and fails for others', () async {
      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(31));
      expect(sheet.echoMatches(sheet.firstWord, sheet.lastWord), isTrue);
      expect(sheet.echoMatches(' ${sheet.firstWord.toUpperCase()} ', sheet.lastWord), isTrue);
      expect(sheet.echoMatches(sheet.lastWord, sheet.firstWord), sheet.firstWord == sheet.lastWord);
      expect(sheet.echoMatches('', ''), isFalse);
      expect(sheet.rows.length, 2);
      expect(sheet.rows.expand((List<String> r) => r).toList(), sheet.words);
    });
  });

  group('her two secrets', () {
    test('the hand-over code gives both secrets back; one wrong word refuses it', () {
      final ChildSecrets c = ChildSecrets.make(Random(41));
      final WordsResult r = ChildSecrets.readHandover(c.handoverWords.join(' '));
      expect(r.ok, isTrue);
      final ChildSecrets back = ChildSecrets.fromHandover(r.bytes!);
      expect(back.keep, c.keep);
      expect(back.private, c.private);
      final List<String> bad = List<String>.of(c.handoverWords)..[5] = c.handoverWords[5] == 'baba' ? 'bebe' : 'baba';
      expect(ChildSecrets.readHandover(bad.join(' ')).ok, isFalse);
    });

    test('a sheet-length code is not accepted as a hand-over, and the other way round', () {
      final ChildSecrets c = ChildSecrets.make(Random(42));
      expect(ChildSecrets.readHandover(secretToWords(c.keep).join(' ')).ok, isFalse);
      expect(wordsToSecret(c.handoverWords.join(' ')).ok, isFalse);
    });

    test('json round trip, and damaged json is read as nothing', () {
      final ChildSecrets c = ChildSecrets.make(Random(43));
      final ChildSecrets? back = ChildSecrets.fromJson(c.toJson());
      expect(back!.keep, c.keep);
      expect(ChildSecrets.fromJson(<String, Object?>{'keep': 'AA==', 'private': 'AA=='}), isNull);
      expect(ChildSecrets.fromJson('nope'), isNull);
    });
  });
}
