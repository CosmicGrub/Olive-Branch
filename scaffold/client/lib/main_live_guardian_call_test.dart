// OLIVE BRANCH — live-backend GUARDIAN CALL-TEST entry point. UNVERIFIED
// (tools/verify.sh's automated pipeline never builds/runs this specific
// --target, only flutter analyze/flutter test against the shared test
// suite — same posture as every other dev-only entry point in this repo).
// Actually built and run on a real Galaxy Z Fold5 this pass, though: real
// devLoginFor()/OliveApi.startCall() call, real CONFERENCE_JOINED, real
// PARTICIPANT_JOINED on the other device — see CHANGELOG v0.49.34. DEV
// VERIFICATION ONLY, same status as main_live_child_call_test.dart — not a
// real product screen, not a design decision, and not shipped alongside
// main_live_guardian.dart. MASTERFILE §7, §16.2 #6.
//
// Byte-for-byte main_live_guardian.dart, with exactly one addition:
// GuardianMoreScreen.onCallStarted wired to POST the real room a real call
// just minted to local-call-room-server.mjs's dev-only /pending-call
// endpoint — see that file's own header comment on why this one hop (and
// only this one hop) is bridged rather than real, and why the bridge lives
// here and not in main_live_guardian.dart or guardian_more.dart itself.
// main_live_child_call_test.dart's own FAB-adjacent poll loop is the other
// half; together they let a real two-device test show a REAL knock screen
// on the child device when the guardian device taps "Call Ivy", with no
// real FCM/APNs credential anywhere in the loop.
//
// `flutter run --target=lib/main_live_guardian_call_test.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required) AND a running
// tools/local-call-room-server.mjs (or its Docker `callroom` service).
import 'dart:convert';
import 'dart:io';
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

// LOCAL DEV/TEST ONLY — see local-call-room-server.mjs's own header on
// POST/GET /pending-call. Same loopback-over-adb-reverse posture as
// call_screen.dart's own devRoomServerBase, for the identical reason.
const _pendingCallUrl = 'http://127.0.0.1:8787/pending-call';

/// Fire-and-forget by design: a failed bridge POST must never surface as a
/// visible error on the real call-start path it's riding along with — the
/// real call already succeeded by the time this runs (see guardian_more
/// .dart's own onCallStarted doc comment: it fires only after a real,
/// successful [OliveApi.startCall]). Swallowing this failure silently
/// (`catch (_) {}`) mirrors main_live_child_call_test.dart's own
/// best-effort posture for exactly the same class of dev-only scaffolding.
Future<void> _bridgeToPendingCall(Map<String, dynamic> started) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(_pendingCallUrl))
        .timeout(const Duration(seconds: 3));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'room': started['room'],
      'serverURL': started['serverURL'],
    }));
    await request.close().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('[olive.calltest] pending-call bridge POST failed: $e');
  } finally {
    client.close();
  }
}

/// The theme half of session bootstrap — same posture and same fail-closed
/// discipline as main_live.dart's own [_fetchInitialTheme] (that file's own
/// doc comment explains the reasoning this mirrors verbatim).
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
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }
  final initialTheme = await _fetchInitialTheme();
  runApp(_OliveLiveGuardianCallTest(initialTheme: initialTheme));
}

class _OliveLiveGuardianCallTest extends StatefulWidget {
  const _OliveLiveGuardianCallTest({this.initialTheme = defaultAppTheme});
  final AppTheme initialTheme;

  @override
  State<_OliveLiveGuardianCallTest> createState() => _OliveLiveGuardianCallTestState();
}

class _OliveLiveGuardianCallTestState extends State<_OliveLiveGuardianCallTest> {
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
        title: 'Olive (live guardian, call-test)',
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
        home: const GuardianMoreScreen(
          baseUrl: _defaultBaseUrl,
          guardianId: _defaultGuardianId,
          childId: _defaultChildId,
          onCallStarted: _bridgeToPendingCall,
        ),
      );
    },
  );
}
