// OLIVE BRANCH — DEV VERIFICATION ONLY entry point. UNVERIFIED
// (tools/verify.sh's automated pipeline never builds/runs this specific
// --target, only flutter analyze/flutter test against the shared test
// suite — same posture as every other dev-only entry point in this repo).
// Actually built and run on a real tablet this pass and earlier this
// session, though: real CONFERENCE_JOINED, real PARTICIPANT_JOINED on the
// other device — see CHANGELOG v0.49.34. Not a real product screen, not a
// design decision, and not shipped alongside main_live.dart. MASTERFILE
// §7, §16.2 #6.
//
// Exists for exactly one reason: to verify a real two-device call with the
// TABLET in the child role and a phone in the guardian role, the way
// main_live_guardian.dart already let the guardian side of that
// verification happen. ChildHome's own real "Call Dad" affordance
// (child_home.dart's _PresenceCard) is deliberately gated behind real
// parent-presence data — "{name} is free right now" — and no live
// day-part/overlap endpoint exists server-side to honestly source that
// from yet (see child_home_live.dart's own header: `presence: null`, "no
// live day-part/overlap endpoint exists server-side"). Faking that data
// here, even just for a test, would mean pretending a parent is free when
// nothing real backs that claim — exactly the kind of invented signal this
// codebase's own established discipline refuses (see child_home_live.dart's
// own comment on the same field). This file does not touch that gate, or
// child_home.dart, or child_more.dart, at all.
//
// Instead: the real, unmodified LiveChildHomeScreen renders exactly as it
// does in main_live.dart, and a SEPARATE, clearly-labeled floating action
// button — "Call Dad (test)" — sits on top of it, calling the same real
// CallScreen(who: 'ivy', ...) the presence-gated button would have called
// once real presence data exists. Same posture as guardian_more.dart's own
// "Guardian setup — passkey (dev verification)" tile: a real path to a real
// screen, deliberately and visibly labeled as verification scaffolding,
// not presented as a finished feature.
//
// Deliberately NOT wrapped in KioskShell, unlike main_live.dart. KioskShell's
// lock-task self-pinning + defensive PIN-relock-on-backgrounding is real,
// intentional child-safety behavior (§8.3) — and exercising it for real
// requires the guardian's own real, self-chosen PIN (see guardian_more.dart's
// setGuardianPin), which this file has no business knowing or guessing.
// That behavior is orthogonal to the one thing this file verifies (call
// connectivity), so it's left out here rather than faked or bypassed.
//
// `flutter run --target=lib/main_live_child_call_test.dart
//   --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
//
// SECOND addition, alongside the FAB above: a real-push-notification stand-
// in, so this file can also verify the OTHER real call path — a guardian
// device starting a real call (guardian_more.dart's "Call $childName" tile,
// wired to the real POST /v1/children/:childId/calls route via
// main_live_guardian_call_test.dart) and THIS device answering it, rather
// than this device always initiating. No real FCM/APNs credential exists in
// this environment (push_channel.dart's own header — no google-services.json
// anywhere in this repo) — a real `call_incoming` push genuinely cannot be
// delivered here, full stop. `_pollForIncomingCall` below polls
// local-call-room-server.mjs's own dev-only GET /pending-call (see that
// file's header, and this function's own doc comment, for the fuller
// account of the two real shapes that can land there) and, on seeing
// something new, feeds it into the SAME real, tested
// `buildCallIncomingHandler` callback `main_live.dart`'s own real
// `PushChannel.onForegroundPointer` wiring uses — a real `PushPointer`, a
// real `CallKnockScreen`, a real Answer button, a real `CallScreen` join.
// Only the undeliverable FCM hop itself is bridged; everything downstream of
// it is the unmodified real code path.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'call_knock_screen.dart' show buildCallIncomingHandler;
import 'call_screen.dart' show CallScreen, devRoomServerBase;
import 'child_home_live.dart';
import 'push_channel.dart';
import 'theme.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

// LOCAL DEV/TEST ONLY — see local-call-room-server.mjs's own header on
// POST/GET /pending-call. Same loopback-over-adb-reverse posture as
// call_screen.dart's own devRoomServerBase, for the identical reason.
const _pendingCallUrl = 'http://127.0.0.1:8787/pending-call';

// The REVERSE leg — see local-call-room-server.mjs's own header on
// POST/GET /pending-call-for-dad for the fuller account. Bridged from here
// (rather than left for CallScreen's own internal _fetchToken to handle)
// because the guardian side needs to learn his own token BEFORE this
// device joins the call, not after — same reason
// main_live_guardian_call_test.dart's own _bridgeToPendingCall bridges
// post-mint rather than leaving CallScreen to fetch silently.
const _pendingCallForDadUrl = 'http://127.0.0.1:8787/pending-call-for-dad';

/// Fetches THIS device's own token (who=ivy, to actually join herself) AND,
/// separately, DAD's own correctly-identity-bound token (who=dad) to bridge
/// to his device — two real fetches against the same shared dev session,
/// not one token reused for both. A real, previously-shipped mistake this
/// pass found and fixed: bridging Ivy's OWN token to Dad's poll target
/// would mean his device joining the room AS Ivy — a real identity
/// impersonation, the exact class of bug I3 exists to prevent everywhere
/// else in this codebase. local-call-room-server.mjs's dev-only session is
/// process-lifetime-fixed and hands out a real, correctly-bound token to
/// anyone who asks who=dad|ivy — asking twice, once per real identity, is
/// the honest way to get two devices each their own real token for the
/// same real room. Mirrors main_live_guardian_call_test.dart's own
/// _bridgeToPendingCall in spirit: real data, best-effort bridge, never lets
/// a failed bridge POST block the real call this device is about to join.
Future<Map<String, dynamic>> _fetchTokenAndBridgeToDad() async {
  final client = HttpClient();
  try {
    final ivyUri = Uri.parse('$devRoomServerBase/room?who=ivy');
    final ivyRequest = await client.getUrl(ivyUri).timeout(const Duration(seconds: 6));
    final ivyResponse = await ivyRequest.close().timeout(const Duration(seconds: 6));
    final ivyBody = await ivyResponse.transform(utf8.decoder).join();
    if (ivyResponse.statusCode != 200) {
      throw Exception('Room server refused (${ivyResponse.statusCode}): $ivyBody');
    }
    final ivyData = jsonDecode(ivyBody) as Map<String, dynamic>;

    try {
      final dadUri = Uri.parse('$devRoomServerBase/room?who=dad');
      final dadRequest = await client.getUrl(dadUri).timeout(const Duration(seconds: 6));
      final dadResponse = await dadRequest.close().timeout(const Duration(seconds: 6));
      final dadBody = await dadResponse.transform(utf8.decoder).join();
      if (dadResponse.statusCode != 200) {
        throw Exception('Room server refused Dad\'s own token (${dadResponse.statusCode}): $dadBody');
      }
      final dadData = jsonDecode(dadBody) as Map<String, dynamic>;

      final bridgeRequest = await client.postUrl(Uri.parse(_pendingCallForDadUrl))
          .timeout(const Duration(seconds: 3));
      bridgeRequest.headers.contentType = ContentType.json;
      bridgeRequest.write(jsonEncode({
        'token': dadData['token'],
        'wsURL': dadData['wsURL'],
      }));
      await bridgeRequest.close().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[olive.calltest] pending-call-for-dad bridge POST failed: $e');
    }
    return ivyData;
  } finally {
    client.close();
  }
}

/// Bundles the theme fetch with a real child session token this device
/// keeps around for the rest of its lifetime — needed now that
/// [_pollForIncomingCall] has a real join call to make on Ivy's behalf
/// (see [CallKnockScreen.baseUrl]/[childId]/[sessionToken]'s own doc
/// comment). One real [devLoginFor] call serves both needs rather than
/// logging in twice; a login failure here means BOTH the theme falls back
/// to [defaultAppTheme] AND the token stays null (buildCallIncomingHandler's
/// sessionId path degrades to CallScreen's own token-fetch fallback in that
/// case — see this file's `_pollForIncomingCall`).
class _Bootstrap {
  const _Bootstrap({required this.theme, required this.childSessionToken});
  final AppTheme theme;
  final String? childSessionToken;
}

Future<_Bootstrap> _bootstrap() async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
    final api = OliveApi(_defaultBaseUrl, token);
    final wire = await api.fetchTheme(_defaultChildId);
    api.close();
    return _Bootstrap(
      theme: AppTheme.fromWire(wire['theme'] as Map<String, dynamic>?),
      childSessionToken: token,
    );
  } catch (_) {
    return const _Bootstrap(theme: defaultAppTheme, childSessionToken: null);
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
  final boot = await _bootstrap();
  runApp(_OliveLiveChildCallTest(
    initialTheme: boot.theme,
    childSessionToken: boot.childSessionToken,
  ));
}

class _OliveLiveChildCallTest extends StatefulWidget {
  const _OliveLiveChildCallTest({
    this.initialTheme = defaultAppTheme,
    this.childSessionToken,
  });
  final AppTheme initialTheme;
  final String? childSessionToken;

  @override
  State<_OliveLiveChildCallTest> createState() => _OliveLiveChildCallTestState();
}

class _OliveLiveChildCallTestState extends State<_OliveLiveChildCallTest> {
  late final ThemeController _themeController = ThemeController(widget.initialTheme);

  // See this file's own header ("SECOND addition") for the fuller account —
  // this navigator key is what lets buildCallIncomingHandler's real
  // navigator.push(...) reach this app's Navigator from outside any single
  // screen's own BuildContext, the same real reason main_live.dart's own
  // _OliveLiveState carries one.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _pendingCallPoll;
  String? _lastSeenKey;

  @override
  void initState() {
    super.initState();
    _pendingCallPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollForIncomingCall());
  }

  /// GET /pending-call every tick; on a payload this device hasn't already
  /// shown a knock screen for, feeds it into the real
  /// buildCallIncomingHandler callback as a real PushPointer — see this
  /// file's own header for the fuller account of what's real (everything
  /// downstream of this one call) and what isn't (the poll itself, standing
  /// in for an undeliverable real FCM push).
  ///
  /// `/pending-call` has TWO real writers, per local-call-room-server.mjs's
  /// own header — Dad's device can start a call two different ways, and
  /// each bridges a different real shape:
  ///  - main_live_guardian_call_test.dart's "Call Ivy" tile (the REAL
  ///    production `POST /v1/children/:childId/calls` route) bridges
  ///    `{sessionId}` — resolved here through the real production join
  ///    route (`pointer.ref` == sessionId, `buildCallIncomingHandler`'s own
  ///    `baseUrl`/`childId`/`sessionToken` params), the same route
  ///    call_knock_screen.dart's real Answer button uses for a genuine
  ///    push. `widget.childSessionToken` is null only if this device's own
  ///    boot-time [devLoginFor] failed — CallKnockScreen then falls back to
  ///    CallScreen's own token-fetch (its own doc comment covers that).
  ///  - main_live_dad_answer_test.dart's "Call Ivy (test)" FAB (a dev-only,
  ///    process-lifetime-fixed room-server session with no real `call_log`
  ///    row to resolve a sessionId against) bridges an already-resolved
  ///    `{token, wsURL}` instead — fed straight through as
  ///    `knownToken`/`knownWsURL`, bypassing the join route entirely (see
  ///    CallKnockScreen.knownToken's own doc comment; it's checked BEFORE
  ///    sessionId there, so supplying both would be harmless, but only one
  ///    is ever actually present per payload here).
  ///
  /// `_lastSeenKey` is deliberately never cleared: a guardian's next real
  /// call always mints a genuinely different session id (server/test
  /// /calls_route.test.mjs's own I1 assertion) and this dev-only room
  /// server mints a genuinely different token every request, so a plain
  /// not-equal check on whichever identifying field is present is enough
  /// to dedupe every poll tick without needing the dev server to clear its
  /// own state on read.
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
      final sessionId = decoded['sessionId'] as String?;
      final token = decoded['token'] as String?;
      final wsURL = decoded['wsURL'] as String?;
      final key = sessionId ?? token;
      if (key == null || key == _lastSeenKey) return;
      _lastSeenKey = key;
      buildCallIncomingHandler(
        navigatorKey: _navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy',
        baseUrl: _defaultBaseUrl, childId: _defaultChildId,
        sessionToken: widget.childSessionToken,
        knownToken: token, knownWsURL: wsURL,
        // ref must be non-null regardless of which shape this payload is —
        // when knownToken is present, CallKnockScreen never reads ref at
        // all (see its own _handleAnswer priority order), so the sessionId
        // fallback to a stand-in string is safe.
      )(PushPointer(kind: 'call_incoming', ref: sessionId ?? 'dev-test-poll'));
    } catch (_) {
      // Best-effort, every tick — a dev server that isn't running yet (or a
      // transient network hiccup) must never crash this poll loop or show
      // an error; the next tick tries again in 1 second either way.
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
        title: 'Olive (live, child call-test)',
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
        // Real, unmodified LiveChildHomeScreen underneath — nothing about
        // the real child experience changes. The test affordance is a
        // separate layer on top, not a change to this widget or anything
        // it renders.
        home: Builder(
          builder: (context) => Stack(children: [
            const LiveChildHomeScreen(
              baseUrl: _defaultBaseUrl,
              childId: _defaultChildId,
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                key: const Key('devCallDadTest'),
                heroTag: 'devCallDadTest',
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Call Dad (test)'),
                // Fetches + bridges Dad's own token BEFORE navigating (see
                // _fetchTokenAndBridgeToDad's own doc comment) so his
                // device's own poll loop can show a real CallKnockScreen
                // for this call, not just independently join the same
                // known room blind — and so it joins AS Dad, not as a
                // second Ivy.
                onPressed: () async {
                  final data = await _fetchTokenAndBridgeToDad();
                  if (!context.mounted) return;
                  unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CallScreen(
                      who: 'ivy',
                      displayName: 'Ivy',
                      knownToken: data['token'] as String,
                      knownWsURL: data['wsURL'] as String?,
                    ),
                  )));
                },
              ),
            ),
          ]),
        ),
      );
    },
  );
}
