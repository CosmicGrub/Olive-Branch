// No longer UNVERIFIED — verified by CI.
// OLIVE BRANCH — bundled typefaces and their licences: every font family the theme names is
// declared in pubspec.yaml with a file that exists, and every SIL OFL text is a registered asset
// that really is the licence and reaches Flutter's licences page.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/font_licences.dart';
import 'package:olive_client/olive_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the three families the theme names are declared in pubspec with files that exist', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    for (final family in [kBodyFont, kDisplayFont, kMonoFont]) {
      expect(pub, contains('- family: $family'), reason: family);
    }
    for (final f in ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf', 'BricolageGrotesque.ttf', 'JetBrainsMono.ttf']) {
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
      expect(pub, contains('assets/fonts/$f'), reason: f);
    }
  });

  test('JetBrains Mono is a valid TrueType file (variable weight)', () {
    final bytes = File('assets/fonts/JetBrainsMono.ttf').readAsBytesSync();
    expect(bytes.sublist(0, 4), [0, 1, 0, 0]);
    expect(bytes.length, greaterThan(100000));
    // an fvar table means the wght axis exists, so the label style's weight 500 is real
    expect(String.fromCharCodes(bytes.sublist(0, 4000)).contains('fvar'), isTrue);
  });

  test('the mono styles use the bundled face at the exact weight', () {
    for (final n in ['label', 'mono']) {
      final st = designTextStyle(n);
      expect(st.fontFamily, kMonoFont);
      expect(st.fontVariations!.single.axis, 'wght');
      expect(st.fontVariations!.single.value, 500);
    }
  });

  test('each OFL text is a registered asset and is the licence', () async {
    for (final e in kFontLicenceAssets.entries) {
      final t = await rootBundle.loadString(e.value);
      expect(t, contains('SIL OPEN FONT LICENSE'), reason: e.key);
      expect(t, contains('Version 1.1'), reason: e.key);
    }
    expect(kFontLicenceAssets.keys, contains('JetBrains Mono (font)'));
    final jb = await rootBundle.loadString('assets/fonts/OFL-JetBrainsMono.txt');
    expect(jb, contains('JetBrains Mono Project Authors'));
  });

  test('registerFontLicences puts the fonts on the licences page', () async {
    registerFontLicences();
    registerFontLicences(); // idempotent
    final names = <String>[];
    await for (final l in LicenseRegistry.licenses) {
      names.addAll(l.packages);
    }
    expect(names, containsAll(kFontLicenceAssets.keys));
    expect(names.where((n) => n == 'JetBrains Mono (font)').length, 1);
  });
}
