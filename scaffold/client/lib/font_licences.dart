// No longer UNVERIFIED — verified by CI (test/font_licences_test.dart).
// OLIVE BRANCH — the licence texts of the bundled typefaces, shown on Flutter's licences page.
// Flutter collects package licences by itself; font files are assets, so each SIL OFL 1.1 text
// that ships beside a font in assets/fonts is registered here. Call [registerFontLicences] once
// at start-up (the app entry points do).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// (package label shown on the licences page, licence asset).
const Map<String, String> kFontLicenceAssets = {
  'Atkinson Hyperlegible (font)': 'assets/fonts/OFL-AtkinsonHyperlegible.txt',
  'Bricolage Grotesque (font)': 'assets/fonts/OFL-Bricolage.txt',
  'JetBrains Mono (font)': 'assets/fonts/OFL-JetBrainsMono.txt',
};

bool _registered = false;

/// Registers the font licences once. Safe to call repeatedly.
void registerFontLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final e in kFontLicenceAssets.entries) {
      final text = await rootBundle.loadString(e.value);
      yield LicenseEntryWithLineBreaks([e.key], text);
    }
  });
}
