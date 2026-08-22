// OLIVE BRANCH — live-backend GUARDIAN entry point. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §7.
//
// A THIRD build target, alongside main.dart (offline preview) and
// main_live.dart (live CHILD entry point — see that file's own header for
// why it's a separate target). Every guardian-facing live screen this repo
// already has (guardian_more.dart's hub, message banking, care note,
// emergency card, handover notes, availability, theme picker, kiosk PIN
// setup...) sat completely unreachable from any real, running build until
// this file existed — main_live.dart's own OliveLive.build() comment says so
// directly: "guardian_more.dart... is not (yet) wired into this live entry
// point's own tree." This file is that wiring, for the pieces that don't
// need a server endpoint this repo doesn't have yet.
//
// Deliberately does NOT boot into the real GuardianHome (guardian_home.dart)
// — that widget needs dual-clock/ribbon data from a `/ribbon` endpoint
// (see its own header: "All times arrive pre-rendered from /now and
// /ribbon") that api_client.dart only declares a path constant for
// (`OliveApi.childRibbon`) with no real server route and no client fetch
// method behind it — a `guardian_home_live.dart` honestly can't be written
// yet without inventing fake ribbon data, which this codebase's own
// established discipline (see child_home_live.dart's header on `presence`)
// treats as worse than an honest gap. Building the real endpoint is its own,
// separate, larger piece of work — tracked, not done here.
//
// Boots straight into GuardianMoreScreen instead: every tile it needs
// (baseUrl/guardianId/childId) is a plain identifier, not ribbon-computed
// display data, so it's honestly buildable today with zero fabricated
// fields. The real "Call $childName" tile (guardian_more.dart's Calls
// section) and the real kiosk-PIN-setup wiring (GuardianSetupScreen.
// setGuardianPin) both live under this hub, which is the actual reason this
// file exists — see MASTERFILE's own note on this pass for the fuller
// tiered plan (this tier; a real /ribbon endpoint + guardian_home_live.dart;
// a real first-time guardian-device onboarding UX to replace this dev
// shortcut entirely).
//
// `flutter run --target=lib/main_live_guardian.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required). guardianId
// defaults to the seed data in server/seed-dev.mjs ("Dad").
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'guardian_more.dart';
import 'push_channel.dart';
import 'theme.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const _defaultGuardianId = String.fromEnvironment('OLIVE_GUARDIAN_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad

/// The theme half of session bootstrap — same posture and same fail-closed
/// discipline as main_live.dart's own [_fetchInitialTheme] (that file's own
/// doc comment explains the reasoning this mirrors verbatim); duplicated
/// rather than shared because the two files intentionally have no common
/// import between them (separate entry points, separate `void main()`s —
/// sharing a helper would mean a fourth file just for two nine-line
/// functions, more indirection than the duplication it would remove).
Future<AppTheme> _fetchInitialTheme() async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, userId: _defaultGuardianId);
    final api = OliveApi(_defaultBaseUrl, token);
    final wire = await api.fetchTheme(_defaultChildId);
    api.close();
    return AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?);
  } catch (_) {
    return defaultAppTheme;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same try/catch, same reasoning, as main_live.dart's own `main()` — see
  // that file's header comment on why a missing google-services.json must
  // never crash this build before its first frame.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }
  final initialTheme = await _fetchInitialTheme();
  runApp(OliveLiveGuardian(initialTheme: initialTheme));
}

class OliveLiveGuardian extends StatefulWidget {
  const OliveLiveGuardian({super.key, this.initialTheme = defaultAppTheme});
  final AppTheme initialTheme;

  @override
  State<OliveLiveGuardian> createState() => _OliveLiveGuardianState();
}

class _OliveLiveGuardianState extends State<OliveLiveGuardian> {
  // Same shape as main_live.dart's own _OliveLiveState — see that class's
  // own comment. Nothing in THIS build's tree updates it yet either
  // (guardian_more.dart's theme picker calls onThemeApplied, left
  // unwired here for the same reason main_live.dart's own comment names:
  // a second, separate gap, not invented shut here either).
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _themeController,
    builder: (context, _) {
      final scheme = colorSchemeFor(_themeController.value);
      final themeData = ThemeData(colorScheme: scheme, useMaterial3: true);
      return MaterialApp(
        title: 'Olive (live guardian)',
        theme: themeData,
        darkTheme: themeData,
        themeMode: _themeController.value.brightness == ThemeBrightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (context, child) => AnimatedTheme(
          data: themeData,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOut,
          child: child!,
        ),
        // GuardianMoreScreen already owns a Scaffold+AppBar ('More') — see
        // its own build() method; no wrapping Scaffold needed here.
        home: const GuardianMoreScreen(
          baseUrl: _defaultBaseUrl,
          guardianId: _defaultGuardianId,
          childId: _defaultChildId,
        ),
      );
    },
  );
}
