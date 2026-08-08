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
// sides, not just the child's, so the two calling experiences stay identical
// while this is still a single dev build.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
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

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.who, required this.displayName, this.kiosk});

  /// 'dad' or 'ivy' — matches local-call-room-server.mjs's fixed identities.
  final String who;
  final String displayName;
  /// Injectable for widget tests; defaults to the real platform channel —
  /// mirrors kiosk_shell.dart's own `channel` param.
  final KioskChannel? kiosk;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallStatus { fetchingRoom, joining, inCall, error }

class _CallScreenState extends State<CallScreen> {
  final _jitsiMeet = JitsiMeet();
  late final KioskChannel _kiosk;
  _CallStatus _status = _CallStatus.fetchingRoom;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _kiosk = widget.kiosk ?? KioskChannel();
    _startCall();
  }

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
      final data = await _fetchRoom();
      final room = data['room'] as String;
      final serverURL = data['serverURL'] as String;

      if (!mounted) return;
      setState(() => _status = _CallStatus.joining);

      final options = JitsiMeetConferenceOptions(
        serverURL: serverURL,
        room: room,
        userInfo: JitsiMeetUserInfo(displayName: widget.displayName),
        configOverrides: const {
          'startWithAudioMuted': false,
          'startWithVideoMuted': false,
          'subject': 'Olive Branch call',
        },
        featureFlags: const {
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
        },
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
