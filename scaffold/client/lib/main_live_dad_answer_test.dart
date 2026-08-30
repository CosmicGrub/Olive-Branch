// OLIVE BRANCH — live-backend GUARDIAN CALL-TEST entry point, ANSWER side.
// DEV VERIFICATION ONLY, same status/posture as main_live_child_call_test
// .dart and main_live_guardian_call_test.dart (see both files' own headers)
// — UNVERIFIED by tools/verify.sh's automated pipeline, not shipped
// alongside main_live_guardian.dart, not a design decision. MASTERFILE §7,
// §16.2 #6.
//
// Exists for exactly one reason: main_live_guardian_call_test.dart already
// verifies "guardian starts a real call, child answers" (its own
// onCallStarted bridge + main_live_child_call_test.dart's poll loop). It has
// no way to verify the OTHER direction — "child starts a call (this file's
// sibling's own 'Call Dad (test)' FAB), guardian genuinely DETECTS it and
// answers via a real knock screen" — because that FAB used to call
// CallScreen(who: 'ivy', ...) directly with no notification hop at all.
//
// SECOND addition, alongside the FAB below: main_live_child_call_test.dart's
// FAB now bridges Dad's own separately-fetched token to
// local-call-room-server.mjs's own POST /pending-call-for-dad (see that
// file's own header for the fuller account of why this is a SEPARATE slot
// from /pending-call, not the same one used the other direction).
// `_pollForIncomingCall` below polls that slot every ~1s and, on seeing a
// new token, feeds it into the exact same real
// `buildCallIncomingHandler`/`CallKnockScreen`/Answer-button path
// main_live_child_call_test.dart's own poll loop already uses — just with
// who='dad' instead of 'ivy'. `buildCallIncomingHandler` was already fully
// generic (from/who/displayName all caller-supplied, see call_knock_screen
// .dart's own header) — no guardian-specific knock UI had to be built here.
//
// Real, unmodified GuardianMoreScreen underneath (byte-for-byte
// main_live_guardian_call_test.dart's own `home:`, minus that file's
// onCallStarted bridge — that bridge is a different, unrelated leg and has
// no bearing on this one). A separate, clearly-labeled floating action
// button — "Call Ivy (test)" — sits on top, calling the same real
// CallScreen(who: 'dad', ...) class main_live_child_call_test.dart's own FAB
// calls, just with the guardian identity instead of the child's.
//
// `flutter run --target=lib/main_live_dad_answer_test.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required) AND a running
// tools/local-call-room-server.mjs (or its Docker `callroom` service).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'call_knock_screen.dart' show buildCallIncomingHandler;
import 'call_screen.dart' show CallScreen, devRoomServerBase;
import 'guardian_more.dart';
import 'push_channel.dart';
import 'theme.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const _defaultGuardianId = String.fromEnvironment('OLIVE_GUARDIAN_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad

// LOCAL DEV/TEST ONLY — the reverse leg of main_live_child_call_test.dart's
// own _pendingCallUrl. See local-call-room-server.mjs's own header on
// POST/GET /pending-call-for-dad for the fuller account.
const _pendingCallForDadUrl = 'http://127.0.0.1:8787/pending-call-for-dad';

// This device's OWN outgoing leg — the same /pending-call slot
// main_live_guardian_call_test.dart's own _bridgeToPendingCall posts to,
// polled by main_live_child_call_test.dart's own _pollForIncomingCall
// (which tells the two real senders apart by shape — see that function's
// own doc comment). That file's FAB used to join CallScreen(who: 'dad')
// directly with no bridge at all (fine when it was only ever used
// standalone) — added here so THIS device's own "Call Ivy (test)" FAB
// gives the child device the same real detect-and-answer knock screen the
// reverse leg above already gets, mirroring main_live_child_call_test
// .dart's own _fetchTokenAndBridgeToDad exactly, just posting to the other
// slot.
const _pendingCallUrl = 'http://127.0.0.1:8787/pending-call';

/// See main_live_child_call_test.dart's own _fetchTokenAndBridgeToDad for
/// the fuller account of what this does and why (fetch-then-bridge instead
/// of letting CallScreen's own _fetchToken run silently, and fetching TWO
/// separate identity-bound tokens rather than reusing one) — this is that
/// same idea, mirrored for the guardian's own outgoing leg: fetches Dad's
/// own token (who=dad, for himself to join) AND, separately, Ivy's own
/// correctly-identity-bound token (who=ivy) to bridge to her device.
/// Bridging Dad's OWN token to Ivy's slot would mean her device joining the
/// room AS Dad — the identical impersonation bug this mirrors the fix for.
Future<Map<String, dynamic>> _fetchTokenAndBridgeToIvy() async {
  final client = HttpClient();
  try {
    final dadUri = Uri.parse('$devRoomServerBase/room?who=dad');
    final dadRequest = await client.getUrl(dadUri).timeout(const Duration(seconds: 6));
    final dadResponse = await dadRequest.close().timeout(const Duration(seconds: 6));
    final dadBody = await dadResponse.transform(utf8.decoder).join();
    if (dadResponse.statusCode != 200) {
      throw Exception('Room server refused (${dadResponse.statusCode}): $dadBody');
    }
    final dadData = jsonDecode(dadBody) as Map<String, dynamic>;

    try {
      final ivyUri = Uri.parse('$devRoomServerBase/room?who=ivy');
      final ivyRequest = await client.getUrl(ivyUri).timeout(const Duration(seconds: 6));
      final ivyResponse = await ivyRequest.close().timeout(const Duration(seconds: 6));
      final ivyBody = await ivyResponse.transform(utf8.decoder).join();
      if (ivyResponse.statusCode != 200) {
        throw Exception('Room server refused Ivy\'s own token (${ivyResponse.statusCode}): $ivyBody');
      }
      final ivyData = jsonDecode(ivyBody) as Map<String, dynamic>;

      final bridgeRequest = await client.postUrl(Uri.parse(_pendingCallUrl))
          .timeout(const Duration(seconds: 3));
      bridgeRequest.headers.contentType = ContentType.json;
      bridgeRequest.write(jsonEncode({
        'token': ivyData['token'],
        'wsURL': ivyData['wsURL'],
      }));
      await bridgeRequest.close().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[olive.calltest] pending-call bridge POST failed: $e');
    }
    return dadData;
  } finally {
    client.close();
  }
}

/// The theme half of session bootstrap — same posture as this file's
/// sibling entry points' own identically-named helper.
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
  runApp(_OliveLiveDadAnswerTest(initialTheme: initialTheme));
}

class _OliveLiveDadAnswerTest extends StatefulWidget {
  const _OliveLiveDadAnswerTest({this.initialTheme = defaultAppTheme});
  final AppTheme initialTheme;

  @override
  State<_OliveLiveDadAnswerTest> createState() => _OliveLiveDadAnswerTestState();
}

class _OliveLiveDadAnswerTestState extends State<_OliveLiveDadAnswerTest> {
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  // See main_live_child_call_test.dart's own identically-purposed field for
  // the fuller account — this is the mirror-image poll loop for the reverse
  // direction.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _pendingCallPoll;
  String? _lastSeenToken;

  @override
  void initState() {
    super.initState();
    _pendingCallPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollForIncomingCall());
  }

  /// GET /pending-call-for-dad every tick — see this file's own header and
  /// local-call-room-server.mjs's own header on that route for the fuller
  /// account. Unlike main_live_child_call_test.dart's own
  /// _pollForIncomingCall (which must handle two real, differently-shaped
  /// senders), this slot has exactly one real writer —
  /// main_live_child_call_test.dart's own _fetchTokenAndBridgeToDad — which
  /// always bridges an already-resolved `{token, wsURL}` (Ivy's own dev-only
  /// room-server token has no real `call_log` row / sessionId to resolve
  /// against, so there's nothing to join-route-resolve here at all). Fed
  /// straight through as `knownToken`/`knownWsURL`, bypassing the real join
  /// route entirely — see CallKnockScreen.knownToken's own doc comment.
  Future<void> _pollForIncomingCall() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_pendingCallForDadUrl))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final token = decoded['token'] as String?;
      final wsURL = decoded['wsURL'] as String?;
      if (token == null || token == _lastSeenToken) return;
      _lastSeenToken = token;
      buildCallIncomingHandler(
        navigatorKey: _navigatorKey, from: 'Ivy', who: 'dad', displayName: 'Dad',
        knownToken: token, knownWsURL: wsURL,
        // ref is unused whenever knownToken is supplied (CallKnockScreen
        // checks knownToken first — see its own _handleAnswer) but
        // PushPointer.ref is non-nullable, so a stand-in string is required
        // regardless of whether it's ever read.
      )(const PushPointer(kind: 'call_incoming', ref: 'dev-test-poll'));
    } catch (_) {
      // Best-effort, every tick — same posture as the sibling poll loop.
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
        title: 'Olive (live guardian, answer call-test)',
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
        home: Builder(
          builder: (context) => Stack(children: [
            const GuardianMoreScreen(
              baseUrl: _defaultBaseUrl,
              guardianId: _defaultGuardianId,
              childId: _defaultChildId,
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                key: const Key('devCallIvyTest'),
                heroTag: 'devCallIvyTest',
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Call Ivy (test)'),
                // Fetches + bridges Ivy's own token BEFORE navigating (see
                // _fetchTokenAndBridgeToIvy's own doc comment) so the
                // child device's own poll loop can show a real
                // CallKnockScreen for this call — and so it joins AS Ivy,
                // not as a second Dad.
                onPressed: () async {
                  final data = await _fetchTokenAndBridgeToIvy();
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CallScreen(
                      who: 'dad',
                      displayName: 'Dad',
                      knownToken: data['token'] as String,
                      knownWsURL: data['wsURL'] as String?,
                    ),
                  ));
                },
              ),
            ),
          ]),
        ),
      );
    },
  );
}
