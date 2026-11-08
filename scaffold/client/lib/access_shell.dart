// OLIVE BRANCH — wires the accessibility settings and read-aloud into the app's
// MaterialApp: the one controller each, the builder that installs them, and the
// navigator observer that ends speech on every route change. No longer
// UNVERIFIED — verified by CI (client/test/access_screen_test.dart). MASTERFILE
// §8.8.5, §8.19.
//
// Used by the CHILD's builds (main.dart's preview, main_live.dart). The
// guardian-only build (main_live_guardian.dart) has no child screens to read
// aloud and does not install it; the guardian's settings screen still writes the
// shared settings there (kept on that device, as the screen says).
import 'package:flutter/material.dart';

import 'access_scope.dart';
import 'access_settings.dart';
import 'read_aloud.dart';
import 'tts_channel.dart';

/// The one read-aloud controller for the process, over the OS's offline
/// synthesizer. If the platform has no voice, speak() fails quietly and the
/// speaker shows its quiet icon (read_aloud.dart).
final ReadAloudController sharedReadAloud = ReadAloudController(engine: TtsChannel());

/// Add to MaterialApp.navigatorObservers: a screen opening or closing ends any
/// reading.
final NavigatorObserver sharedReadAloudObserver = ReadAloudRouteObserver(sharedReadAloud);

/// Wraps app content with the settings scope (reduced motion, roomier reading)
/// and the read-aloud scope. Call from MaterialApp.builder, inside any
/// AnimatedTheme so the roomier text theme builds on the live theme.
Widget withAccess(Widget child, {AccessController? access, ReadAloudController? readAloud}) => AccessHost(
      controller: access ?? sharedAccess,
      child: ReadAloudScope(controller: readAloud ?? sharedReadAloud, child: child),
    );

/// Convenience for apps with no builder of their own (the preview build).
Widget accessBuilder(BuildContext context, Widget? child) => withAccess(child ?? const SizedBox.shrink());
