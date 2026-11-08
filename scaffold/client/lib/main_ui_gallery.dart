// No longer UNVERIFIED — verified by CI (analysed by `flutter analyze`; the screen itself is exercised by
// client/test/ui/olive_ui_gallery_test.dart).
// OLIVE BRANCH — dev entry point for the component gallery (lib/ui/olive_ui_gallery.dart).
//
// `flutter run --target=lib/main_ui_gallery.dart` boots straight into the gallery with the app's real
// theme, no server, no pairing and no family data. This is how the owner compares the Flutter app
// against the HTML prototype (docs/superpowers/mockups/live/index.html) without walking through the
// guardian More hub. It is a development target: it is not the build the stores ship.
import 'package:flutter/material.dart';

import 'theme.dart';
import 'theme_data.dart';
import 'ui/olive_ui_gallery.dart';

void main() => runApp(const OliveUiGalleryApp());

/// The gallery in a bare app shell.
class OliveUiGalleryApp extends StatelessWidget {
  const OliveUiGalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Olive UI gallery',
        debugShowCheckedModeBanner: false,
        theme: buildThemeData(defaultAppTheme),
        home: const OliveUiGalleryScreen(),
      );
}
