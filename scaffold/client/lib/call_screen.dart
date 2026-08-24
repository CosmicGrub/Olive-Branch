// OLIVE BRANCH — real-time call, Jitsi Meet + Jitsi Videobridge. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze` / `flutter test` this session).
// §5.19/§5.23 the call. §16.2 #6 (originally "stay on Cloud [LiveKit]") was
// reversed in favor of Jitsi — see the decision note in MASTERFILE.md.
//
// This build points at the public meet.jit.si server by default so the
// original bug stays reproducible: meet.jit.si puts new rooms in a
// moderator-approval lobby the app can never clear (v0.46.0, verified on two
// physical devices — see the §16.2 #6 callout in MASTERFILE.md). §16.2 #6
// Step 2 (self-host Prosody/Jicofo/JVB) is now staged, not yet
// device-verified — see tools/jitsi-selfhost/README.md for setup and the
// real constraints it surfaced (UDP media can't ride the `adb reverse` trick
// below; the self-hosted stack's cert is self-signed). Point
// local-call-room-server.mjs at it with JITSI_SERVER_URL once ready to try.
// The one thing the two devices still need to agree on is which room to
// join, and that coordination reuses real, tested logic —
// packages/session-runtime/src/rooms.mjs's newRoomName()/mintToken(), which
// still enforce I1 (room name never guessable) and I4 (authorization gate)
// — served locally by scaffold/tools/local-call-room-server.mjs. That server
// is LOCAL DEV/TEST ONLY, not a stand-in for the production API.
//
// §8.1 — the child side has no settings affordance at any depth. The feature
// flags below strip Jitsi's own settings/server-change/security UI on both
// sides. A 2026-08-23 audit found this header's own claim was NOT actually
// true in code: `FeatureFlags.settingsEnabled` was never set, so Jitsi's
// native Settings screen stayed reachable mid-call on both devices,
// including the child's kiosk-locked one — fixed below, alongside two more
// findings from the same audit: `chatEnabled` was never disabled for the
// child (Jitsi's native, unmoderated, unarchived free-text chat was live
// for her, unlike every other text surface in this app), and PiP-related
// flags applied identically regardless of role despite MASTERFILE already
// declaring PiP a guardian-only, structural decision. `_featureFlagsFor()`
// below makes all three real, role-conditional facts instead of one flat
// constant silently applied to both roles alike.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'doodle_desk.dart';
import 'kiosk_channel.dart';

/// LOCAL DEV/TEST ONLY — tools/local-call-room-server.mjs. Not a production
/// endpoint.
///
/// Loopback rather than a LAN IP, on purpose: a hardcoded LAN address (the
/// previous value here, 192.168.1.78) goes stale the moment the dev
/// machine's network changes, and silently breaks two-device testing with
/// no clue why. `127.0.0.1` on the *device* reaches the dev machine's
/// `local-call-room-server.mjs` over `adb reverse tcp:8787 tcp:8787`, run
/// once per physical device before installing — see that script's own
/// header. This works over USB regardless of whether the phones and the
/// dev machine share a WiFi network at all.
const devRoomServerBase = 'http://127.0.0.1:8787';

/// The Jitsi deployment itself — a real per-deployment constant, not
/// per-call data. `_fetchRoom()`'s own response already carries this (dev-
/// room-server/the real POST /v1/children/:childId/calls route both read
/// the identical JITSI_SERVER_URL env var server-side, see routes.mjs's own
/// comment on why), but a `call_incoming` push cannot: push.ts's own
/// content-free PushInput carries only kind/ref/callHandle, deliberately —
/// see that file's own header for why a push payload is not the place for
/// deployment config. A knock answered from call_knock_screen.dart has a
/// real room name (the push's callHandle) but needs this constant to know
/// where to actually find it.
const _defaultJitsiServerURL = String.fromEnvironment('OLIVE_JITSI_SERVER_URL',
    defaultValue: 'https://meet.jit.si');

/// 'ivy' is the only child identity any real call site uses (child_home
/// .dart, call_knock_screen.dart's own answer path); every other value —
/// today only 'dad' — is a guardian. A real, tested distinction, not a
/// guess: guardian_more.dart's own real call-start route already refuses a
/// child principal outright (child_cannot_start_call), so 'who' and "which
/// side of the ladder can this device leave kiosk lock" already agree in
/// every real call path this client has. A top-level function, not a
/// private method on [_CallScreenState], so [callFeatureFlagsFor] below and
/// this can both be exercised directly by a widget test without needing to
/// pump a whole [CallScreen] and force it through its own real (and, in a
/// test sandbox, unavoidably platform-channel-hanging) join attempt.
bool isGuardianWho(String who) => who != 'ivy';

/// Real, role-conditional feature flags — found and fixed by a 2026-08-23
/// audit named in this file's own header. Jitsi's native Settings UI is off
/// for EVERY role (closes a real containment gap on the kiosk-locked child
/// device); native in-call chat is off for the child specifically
/// (unmoderated, unarchived, unlike every other text surface in this app —
/// never routed anywhere, simply disabled).
///
/// PiP is enabled for BOTH roles as of 2026-08-24 — an explicit, informed
/// decision, not the default this file originally shipped with (guardian-
/// only, matching MASTERFILE's then-"structural conclusion"). Real PiP for
/// a kiosk-locked child device is a genuine tension with what that lock
/// exists to guarantee — a PiP window is not full-screen, so whatever sits
/// behind it is reachable — and this was accepted deliberately, not
/// invented unilaterally, specifically so [InCallActivitiesScreen] below
/// (drawing together while still on the call) has real OS PiP to build on.
/// The mitigation is native, not a Dart-side assumption: see kiosk_channel
/// .dart's own [KioskChannel.start] doc comment and KioskBridge.kt's
/// ACTION_CALL_ACTIVITY_DESTROYED for the real re-pin-on-every-resume fix
/// this decision required — a PiP entry resumes MainActivity exactly the
/// same way a genuine call end does, and the original one-shot handoff
/// flag would have left the child's device unpinned after a real call end
/// if PiP had been entered even once during that same call.
///
/// No custom "shrink to a mini window" UI exists anywhere in this file for
/// either role, deliberately: once `_jitsiMeet.join()` hands off, Jitsi's
/// own native Activity — not this screen's build() — owns the entire
/// display; setting `pip.enabled: true` here is what makes Jitsi's own
/// native in-call toolbar offer the real PiP entry point, the same
/// broadcast chain WrapperJitsiMeetActivity.kt's own `enterPiP()` already
/// wires end to end. A Flutter-side button in this screen's own build()
/// method would never be reachable during a real call at all — the way
/// back INTO the Flutter app (for either role) is a real PiP entry, not
/// anything this file draws.
Map<String, Object?> callFeatureFlagsFor(bool isGuardian) => {
  FeatureFlags.welcomePageEnabled: false,
  FeatureFlags.preJoinPageEnabled: false,
  FeatureFlags.inviteEnabled: false,
  FeatureFlags.addPeopleEnabled: false,
  FeatureFlags.recordingEnabled: false,
  FeatureFlags.liveStreamingEnabled: false,
  FeatureFlags.meetingPasswordEnabled: false,
  FeatureFlags.serverUrlChangeEnabled: false,
  FeatureFlags.securityOptionEnabled: false,
  FeatureFlags.meetingNameEnabled: false,
  FeatureFlags.calenderEnabled: false,
  FeatureFlags.helpButtonEnabled: false,
  FeatureFlags.kickOutEnabled: false,
  FeatureFlags.lobbyModeEnabled: false,
  // The fix — omitted before this pass despite this file's own header
  // already claiming it was done.
  FeatureFlags.settingsEnabled: false,
  FeatureFlags.chatEnabled: isGuardian,
  // 2026-08-24 — real PiP for BOTH roles now (was guardian-only). See this
  // function's own doc comment above for the full account of why, and for
  // the native re-pin fix this decision required.
  FeatureFlags.pipEnabled: true,
  FeatureFlags.pipWhileScreenSharingEnabled: true,
};

/// Pure decision logic for [_CallScreenState.didChangeAppLifecycleState] —
/// see that method's own doc comment for why this lives at the top level.
/// `state == resumed` alone is not enough (fires on the very first launch
/// too, before any call exists); neither is `isInCall` alone (the screen
/// stays mounted, still "resumed", the whole time she's actually on-screen
/// watching the call, which must not repeatedly push a second copy);
/// `alreadyShown` guards the same call PiP'ing more than once; `!isGuardian`
/// is the one role check — see [callFeatureFlagsFor]'s doc comment for why
/// the guardian's own device resuming must never redirect her.
bool shouldShowInCallActivities({
  required AppLifecycleState state,
  required bool isInCall,
  required bool alreadyShown,
  required bool isGuardian,
}) => state == AppLifecycleState.resumed && isInCall && !alreadyShown && !isGuardian;

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.who,
    required this.displayName,
    this.kiosk,
    this.knownRoom,
    this.knownServerURL,
    this.onCallEnd,
  });

  /// 'dad' or 'ivy' — matches local-call-room-server.mjs's fixed identities.
  final String who;
  final String displayName;
  /// Injectable for widget tests; defaults to the real platform channel —
  /// mirrors kiosk_shell.dart's own `channel` param.
  final KioskChannel? kiosk;
  /// When [knownRoom] is supplied, [_fetchRoom] is skipped entirely and the
  /// call joins THIS exact room instead — the room a caller already minted
  /// (via the real `POST /v1/children/:childId/calls` route, or the room
  /// name a `call_incoming` push carried) rather than a possibly-different
  /// one this screen would otherwise fetch fresh from
  /// `local-call-room-server.mjs`. This is what lets a knock answered from
  /// call_knock_screen.dart join the room the CALLER is already in, instead
  /// of two devices independently minting two different rooms and never
  /// actually meeting. [knownServerURL] is optional even then — a push
  /// payload carries no deployment config (see [_defaultJitsiServerURL]'s
  /// own doc comment), only [knownRoom]; supplied together (the real POST
  /// route's own response shape), [knownServerURL] wins over the constant.
  /// Both null (the default) is byte-for-byte the original behavior — every
  /// existing call site (child_home.dart, guardian_home.dart,
  /// main_live_child_call_test.dart) is unaffected.
  final String? knownRoom;
  final String? knownServerURL;

  /// Fires once, right before this screen navigates away on a real,
  /// SDK-reported `readyToClose` — never on the error path (nothing was
  /// ever really joined there to end). Deliberately a caller-supplied
  /// callback rather than this screen knowing a baseUrl/session/childId/
  /// sessionId itself: mirrors guardian_more.dart's own onCallStarted
  /// seam, keeping CallScreen decoupled from OliveApi entirely, same as
  /// it already is today. A real call site supplies one that calls the
  /// real POST /v1/children/:childId/calls/:sessionId/end route
  /// (guardian_more.dart's own `_startRealCall`); null here is a safe,
  /// honest no-op for every call site that doesn't have a real sessionId
  /// to close (e.g. the dev room server's fixed session has none).
  final Future<void> Function()? onCallEnd;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallStatus { fetchingRoom, joining, inCall, error }

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  final _jitsiMeet = JitsiMeet();
  late final KioskChannel _kiosk;
  _CallStatus _status = _CallStatus.fetchingRoom;
  String? _errorMessage;
  // Set true the moment this screen's own PiP-entry-triggered navigation
  // has already fired once for this call, so a second resume (e.g. she
  // PiPs, comes back, PiPs again) doesn't stack a second copy of
  // InCallActivitiesScreen on the Navigator.
  bool _shownInCallActivities = false;

  @override
  void initState() {
    super.initState();
    _kiosk = widget.kiosk ?? KioskChannel();
    WidgetsBinding.instance.addObserver(this);
    _startCall();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The real trigger for [InCallActivitiesScreen] below — see
  /// [callFeatureFlagsFor]'s own doc comment for the fuller account. Jitsi's
  /// own call Activity runs OUTSIDE this Flutter engine entirely (it's a
  /// separate, non-Flutter Activity — WrapperJitsiMeetActivity.kt extends
  /// the SDK's own JitsiMeetActivity, not io.flutter.embedding.android
  /// .FlutterActivity), so `AppLifecycleState.resumed` genuinely reflects
  /// "this Flutter engine's own Activity is visible again" — real, not
  /// assumed: confirmed the two Activities share no Flutter engine by
  /// reading WrapperJitsiMeetActivity.kt directly before relying on this.
  /// A real PiP entry (voluntary or Home-button-triggered) is exactly the
  /// moment that becomes true again while `_status` is still `inCall` —
  /// unlike a genuine end, which routes through readyToClose instead and
  /// never reaches here with `_status == inCall` still true.
  ///
  /// The actual decision is [shouldShowInCallActivities] below — a pure,
  /// top-level function pulled out the same way [isGuardianWho] and
  /// [callFeatureFlagsFor] already are, so it's directly unit-testable
  /// without needing to force a real [CallScreen] through a platform-
  /// channel-dependent join just to reach `_status == inCall` in a test
  /// sandbox, which it never can (see call_screen_test.dart's own note on
  /// why the error state, not inCall, is the reachable proof-of-navigation
  /// signal there).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!shouldShowInCallActivities(
      state: state,
      isInCall: _status == _CallStatus.inCall,
      alreadyShown: _shownInCallActivities,
      isGuardian: _isGuardian,
    )) {
      return;
    }
    _shownInCallActivities = true;
    // Fire-and-forget: a real re-pin already happens natively on this same
    // resume (KioskBridge.stillExpectingCallHandoff(), MainActivity's own
    // onResume() — see that file's own comment), synchronously with the
    // Activity lifecycle rather than a separate, slower Dart round trip
    // through this platform channel. Nothing here needs to wait on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const InCallActivitiesScreen(),
        ));
      }
    });
  }

  /// 'ivy' is the only child identity any real call site uses (child_home
  /// .dart, call_knock_screen.dart's own answer path); every other value —
  /// today only 'dad' — is a guardian. A real, tested distinction, not a
  /// guess: guardian_more.dart's own real call-start route already refuses
  /// a child principal outright (child_cannot_start_call), so 'who' and
  /// "which side of the ladder can this device leave kiosk lock" already
  /// agree in every real call path this client has.
  bool get _isGuardian => isGuardianWho(widget.who);

  Future<Map<String, dynamic>> _fetchRoom() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$devRoomServerBase/room?who=${widget.who}');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Room server refused (${response.statusCode}): $body');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _startCall() async {
    setState(() {
      _status = _CallStatus.fetchingRoom;
      _errorMessage = null;
    });
    try {
      final String room;
      final String serverURL;
      if (widget.knownRoom != null) {
        room = widget.knownRoom!;
        serverURL = widget.knownServerURL ?? _defaultJitsiServerURL;
      } else {
        final data = await _fetchRoom();
        room = data['room'] as String;
        serverURL = data['serverURL'] as String;
      }

      if (!mounted) return;
      setState(() => _status = _CallStatus.joining);

      final options = JitsiMeetConferenceOptions(
        serverURL: serverURL,
        room: room,
        userInfo: JitsiMeetUserInfo(displayName: widget.displayName),
        configOverrides: {
          'startWithAudioMuted': false,
          'startWithVideoMuted': false,
          'subject': 'Olive Branch call',
          // §5.21.1: "all media is relayed, always" — neither device may
          // ever learn the other's real IP address, a protective-order-
          // relevant safety requirement, not a quality/performance choice.
          // The self-hosted stack now sets this server-side too
          // (tools/jitsi-selfhost/olive.env's ENABLE_P2P=0) — that's the
          // robust enforcement point, since a server default holds no
          // matter what any given client does. This client-side override
          // is defense-in-depth for the day this build points at some
          // OTHER Jitsi deployment (a different self-host, or back at a
          // public server for a quick repro) that hasn't made the same
          // choice — direct P2P defaults ON upstream (confirmed live:
          // config.js's own config.p2p.enabled: true), which is exactly
          // what this policy forbids. `iceTransportPolicy: 'relay'`
          // (2026-08-23) is the same defense-in-depth idea applied one
          // layer deeper: MASTERFILE §5.21.1 named this as a residual gap
          // after the ENABLE_P2P=0 fix, but lib-jitsi-meet only documents
          // `iceTransportPolicy` as a P2P-CONNECTION setting (confirmed
          // against upstream docs, not guessed) — with P2P already
          // disabled there is no live P2P path for it to apply to today.
          // Kept here anyway, nested under the same 'p2p' key, for the
          // identical reason `enabled: false` already is: the day P2P is
          // ever re-enabled on some other deployment this build points at,
          // this ensures that path can still only negotiate a TURN-relayed
          // candidate, never a direct one.
          'p2p': {'enabled': false, 'iceTransportPolicy': 'relay'},
        },
        featureFlags: callFeatureFlagsFor(_isGuardian),
      );

      // §16.2 #6 / §5.20 — the SDK opens the call in its own singleTask
      // Activity, which kiosk lock-task pinning refuses to launch as a
      // second task (`E/ActivityTaskManager: Attempted Lock Task Mode
      // violation`, confirmed on a real Galaxy Z Fold5 — see the MASTERFILE
      // §16.2 #6 callout). Without this, `_jitsiMeet.join` below never
      // actually starts the native Activity and this screen hangs on
      // "Joining…" forever with no error. Hand the pin off to that Activity
      // instead of just dropping it — see kiosk_channel.dart's
      // beginCallHandoff doc comment. A no-op when this device isn't
      // kiosk-locked at all (e.g. the guardian side placing the call).
      if (await _kiosk.mode() != 'none') {
        await _kiosk.beginCallHandoff();
      }

      final listener = JitsiMeetEventListener(
        conferenceJoined: (url) {
          if (mounted) setState(() => _status = _CallStatus.inCall);
        },
        // conferenceTerminated and readyToClose are NOT the same moment —
        // on a real dropped connection they can fire tens of seconds apart.
        // Only readyToClose ("no meeting is happening at this point", per
        // the SDK's own docs) is the safe-to-navigate-away signal; popping
        // on both double-pops the Navigator stack past this screen.
        conferenceTerminated: (url, error) {
          if (error != null) debugPrint('Jitsi conference terminated: $error');
        },
        readyToClose: () {
          // Fire-and-forget, deliberately: popping the Navigator must never
          // wait on a network call, and a failed end-call POST must never
          // strand the user on a screen that already knows the call is
          // over. See widget.onCallEnd's own doc comment for what this is
          // and is not (record-keeping only — no server-side media
          // revocation happens here, a real, disclosed, separate gap).
          widget.onCallEnd?.call();
          if (mounted) Navigator.of(context).maybePop();
        },
      );

      await _jitsiMeet.join(options, listener);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _CallStatus.error;
        _errorMessage = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: switch (_status) {
        _CallStatus.fetchingRoom => const _Status(message: 'Finding the call…'),
        _CallStatus.joining => const _Status(message: 'Joining…'),
        _CallStatus.inCall => const _Status(message: 'In call'),
        _CallStatus.error => _ErrorState(
            message: _errorMessage ?? 'Could not start the call.',
            onRetry: _startCall,
          ),
      },
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(message),
  ]);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.call_end, size: 40, color: Colors.redAccent),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back'),
      ),
    ]),
  );
}

/// Real, 2026-08-24 — what she gets while a real call is PiP'd (see
/// [callFeatureFlagsFor]'s own doc comment for the full account of why
/// PiP is real for the child now, and [_CallScreenState
/// .didChangeAppLifecycleState] for exactly when this screen is reached).
///
/// Deliberately honest, not oversold: this wraps the same real, tested
/// [DoodleDesk] engine `child_more.dart`'s own "Doodle desk" tile already
/// reaches — NOT a new, shared-in-real-time canvas. `annotation_canvas
/// .dart`'s own header says plainly why a second actor doesn't exist here
/// yet: "there is just one actor in this preview build because there's no
/// realtime transport yet to carry a second." Building that transport is
/// real, separately-scoped work (a genuine WebSocket-shaped feature, not a
/// PiP-adjacent wiring task) — not invented or faked here. What IS real
/// today: she can draw while the small PiP window keeps the call itself —
/// his voice, his face — right there the whole time, instead of the call
/// being the only thing she can do.
///
/// Public (not `_`-prefixed), unlike this file's other single-use display
/// widgets ([_Status], [_ErrorState]) — those two are always reachable
/// through [CallScreen] itself in a test sandbox (fetch failure lands on
/// the real error state), but this one is only ever pushed from inside
/// `_status == inCall`, which a widget test can never reach without a real
/// platform-channel join. Public visibility is what lets
/// call_screen_test.dart pump and verify this screen's own content
/// directly instead of leaving it unverified until a live device.
class InCallActivitiesScreen extends StatelessWidget {
  const InCallActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('While you talk')),
    body: const Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          "He's still right there — look for the small video window. "
          "This drawing isn't shared with his screen yet, but you can "
          'still show him what you made.',
          textAlign: TextAlign.center,
        ),
      ),
      Expanded(child: DoodleDesk()),
    ]),
  );
}
