// OLIVE BRANCH — DEV VERIFICATION ONLY entry point. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — same posture as every
// other dev-only entry point named below). MASTERFILE §5.20, §5.24.4, §8.3,
// §16.2 #6.
//
// Exists for exactly one reason, narrower than either file it borrows from:
// verifying v0.49.36's real child-PiP/kiosk-re-pin fix on a REAL, genuinely
// kiosk-pinned tablet, which neither existing live entry point can do alone.
// `main_live_child_call_test.dart` gets a real incoming call via the same
// pending-call poll bridge this file reuses verbatim, but is "Deliberately
// NOT wrapped in KioskShell" (its own header) — a real device running that
// build is never actually pinned, so it cannot exercise
// stillExpectingCallHandoff()/the ACTION_CALL_ACTIVITY_DESTROYED re-pin at
// all. `main_live.dart` DOES wrap in KioskShell — engaged automatically on
// mount, no PIN needed (see kiosk_shell.dart's own `_engage()`, called from
// `initState()`) — but has no way to receive a call at all: no real FCM
// credential exists anywhere in this environment, and the child's own real
// "Call Dad" affordance is presence-gated behind data no live endpoint
// serves yet (see child_home_live.dart's own header). Neither gap is
// invented around; this file just combines the two already-real halves.
//
// `flutter run --target=lib/main_live_child_kiosk_call_test.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
//
// Verifies, and only verifies: (a) real PiP entry on a genuinely
// kiosk-pinned device; (b) the native re-pin (stillExpectingCallHandoff()
// -> startLockTask()) genuinely re-engages once the child returns to
// MainActivity, however she gets there; (c) a real call end still
// correctly re-pins. A same-2026-08-24 fourth goal — an automatic
// navigate-to-a-drawing-screen the moment PiP is entered — was built,
// tested with this exact file, and reverted: entering PiP via a Home
// press does NOT reliably resume MainActivity at all (Android's own
// WindowManagerService re-asserts the launcher as the PiP host once Home
// has been pressed — confirmed via dumpsys, not assumed), so this file no
// longer tries to verify that. Not a real product screen, not a design
// decision, not shipped alongside
// main_live.dart or main.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'call_knock_screen.dart' show buildCallIncomingHandler;
import 'child_home_live.dart';
import 'kiosk_shell.dart';
import 'push_channel.dart';
import 'theme.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

// LOCAL DEV/TEST ONLY — see local-call-room-server.mjs's own header on
// POST/GET /pending-call. Identical to main_live_child_call_test.dart's own
// constant, for the identical reason.
const _pendingCallUrl = 'http://127.0.0.1:8787/pending-call';

// Byte-for-byte main_live.dart's own _verifyGuardianPin/_liveVerifyBiometricStub
// — real backend PIN check, honest biometric stand-in. Reproduced rather than
// exported: main_live.dart declares neither as public API, matching every
// other dev-only entry point's own posture of duplicating a small real seam
// rather than reaching into another main_*.dart file.
Future<bool> _verifyGuardianPin(String pin) async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
    final api = OliveApi(_defaultBaseUrl, token);
    final ok = await api.verifyKioskPin(_defaultChildId, pin);
    api.close();
    return ok;
  } catch (_) {
    return false;
  }
}

Future<bool> _liveVerifyBiometricStub() async => true;

Future<AppTheme> _fetchInitialTheme() async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
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
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }
  final initialTheme = await _fetchInitialTheme();
  runApp(_OliveLiveChildKioskCallTest(initialTheme: initialTheme));
}

class _OliveLiveChildKioskCallTest extends StatefulWidget {
  const _OliveLiveChildKioskCallTest({this.initialTheme = defaultAppTheme});
  final AppTheme initialTheme;

  @override
  State<_OliveLiveChildKioskCallTest> createState() =>
      _OliveLiveChildKioskCallTestState();
}

class _OliveLiveChildKioskCallTestState extends State<_OliveLiveChildKioskCallTest> {
  late final ThemeController _themeController = ThemeController(widget.initialTheme);
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _pendingCallPoll;
  String? _lastSeenRoom;

  @override
  void initState() {
    super.initState();
    _pendingCallPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollForIncomingCall());
  }

  // Byte-for-byte main_live_child_call_test.dart's own _pollForIncomingCall
  // — see that file's own doc comment for the full account of what's real
  // (everything downstream of this one call) and what isn't (the poll
  // itself, standing in for an undeliverable real FCM push). The one
  // difference here: buildCallIncomingHandler's real Navigator.push reaches
  // THIS file's own KioskShell-wrapped tree, so the CallScreen it opens is
  // genuinely running inside a genuinely pinned Activity.
  Future<void> _pollForIncomingCall() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_pendingCallUrl))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final room = decoded['room'] as String?;
      if (room == null || room == _lastSeenRoom) return;
      _lastSeenRoom = room;
      buildCallIncomingHandler(
        navigatorKey: _navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy',
      )(PushPointer(kind: 'call_incoming', ref: 'dev-test-poll', callHandle: room));
    } catch (_) {
      // Best-effort, every tick — same posture as the file this is copied from.
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _pendingCallPoll?.cancel();
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
        navigatorKey: _navigatorKey,
        title: 'Olive (live, child kiosk+call test)',
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
        // Real KioskShell, engaged automatically on mount (kiosk_shell.dart's
        // own _engage(), called from initState() — no PIN needed to PIN the
        // device; a PIN is only ever needed to escape it). This is the one
        // real difference from main_live_child_call_test.dart, and the
        // entire reason this file exists.
        home: KioskShell(
          verifyPin: _verifyGuardianPin,
          verifyBiometric: _liveVerifyBiometricStub,
          child: LiveChildHomeScreen(
            baseUrl: _defaultBaseUrl,
            childId: _defaultChildId,
            navigatorKey: _navigatorKey,
          ),
        ),
      );
    },
  );
}
