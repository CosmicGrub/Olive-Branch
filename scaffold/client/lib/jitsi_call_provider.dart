// OLIVE BRANCH — the Jitsi call engine behind [CallProvider]. UNVERIFIED on
// real devices in this build (Jitsi-era builds were verified bidirectionally on
// a Galaxy Fold5 and tablet; this port onto the provider seam, the per-
// participant JWT and the https/pinned-cert transport are covered by
// flutter analyze/test and the owner's two-device plan, not yet run on
// hardware). MASTERFILE §16.2 #6, REVERSED a third time (2026-11-09): this is
// the DEFAULT provider; it talks to the owner's self-hosted Jitsi
// (tools/jitsi-selfhost/, switched on with calls-on.sh), never meet.jit.si.
//
// The SDK draws the call itself on its own native Activity, so
// [rendersOwnScreen] is true and there are no video widgets here. What this
// file adds around it, all recovered from the Jitsi-era call_screen.dart:
//  - the kiosk lock-task handoff (§16.2 #6 / §5.20) before launch, so the
//    child's pinned device can open the SDK's second task;
//  - conferenceTerminated vs readyToClose are NOT the same moment (they can
//    fire tens of seconds apart on a dropped connection): only readyToClose
//    ends the call, or the Navigator would pop twice;
//  - p2p off + relay-only ICE (§5.21.1, defense in depth beside the stack's
//    own ENABLE_P2P=0).
// And what is new: the per-participant JWT, a hang-up-only toolbar for an
// observer-only guardian (advisory: Jitsi has no publish-denied grant, see
// jitsi-token.ts), no chat/settings/invite/screen-share/recording for anyone,
// third-party requests and analytics off, and an https-only server address in
// release builds.
//
// TLS to the LAN stack's self-signed certificate is NOT handled here and never
// by disabling verification: android/.../network_security_config.xml pins ONE
// public certificate for ONE LAN address (tools/jitsi-selfhost/
// generate-dev-cert.sh keeps cert and scope in lockstep). The global http
// refusal and the system-CA-only base config are untouched.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter/widgets.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'call_modes.dart' show CallMode;
import 'call_provider.dart';
import 'degradation_banner.dart' show Quality;
import 'kiosk_channel.dart';

/// No chat for anyone (Jitsi's chat is unmoderated and unarchived, unlike every
/// other text surface in this app), no settings, invite, lobby, recording,
/// live streaming, screen sharing, reactions or hand-raising. PiP stays on for
/// both roles: an explicit, informed 2026-08-24 decision recorded in
/// MASTERFILE (the kiosk re-pin-on-resume work this needs is native and kept).
Map<String, Object?> jitsiFeatureFlagsFor({required bool isGuardian, bool observerOnly = false}) => {
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
  FeatureFlags.settingsEnabled: false,
  FeatureFlags.chatEnabled: false,
  FeatureFlags.raiseHandEnabled: false,
  FeatureFlags.reactionsEnabled: false,
  FeatureFlags.videoShareEnabled: false,
  FeatureFlags.androidScreenSharingEnabled: false,
  FeatureFlags.iosScreenSharingEnabled: false,
  FeatureFlags.breakoutRoomsEnabled: false,
  FeatureFlags.closeCaptionsEnabled: false,
  FeatureFlags.audioMuteButtonEnabled: !observerOnly,
  FeatureFlags.videoMuteEnabled: !observerOnly,
  FeatureFlags.pipEnabled: true,
  FeatureFlags.pipWhileScreenSharingEnabled: false,
};

/// Jitsi config.js overrides for a child's call.
Map<String, Object?> jitsiConfigOverridesFor(CallGrant grant, CallJoinOptions options) {
  final audioOnly = options.mode == CallMode.audioOnly;
  final observer = grant.observerOnly;
  return {
    // §5.23.1: audio-only is a choice, never a punishment.
    'startWithAudioMuted': observer,
    'startWithVideoMuted': observer || audioOnly,
    'startAudioOnly': audioOnly,
    'subject': 'Olive Branch call',
    'disableDeepLinking': true,
    'prejoinConfig': {'enabled': false},
    'enableWelcomePage': false,
    'disableInviteFunctions': true,
    'doNotStoreRoom': true,
    // No gravatar/analytics/stats beacons: a child's call talks to the home
    // server and nothing else.
    'disableThirdPartyRequests': true,
    'analytics': {'disabled': true},
    // §5.21.1: neither device learns the other's address. Server-side
    // ENABLE_P2P=0 is the robust control; this is defense in depth for any
    // other deployment this build might be pointed at.
    'p2p': {'enabled': false, 'iceTransportPolicy': 'relay'},
    // The toolbar IS the permission model on the client: an observer gets
    // hang-up only, everyone else mic, camera, hang-up. No chat, no settings,
    // no invite, no screen share by construction.
    'toolbarButtons': observer ? ['hangup'] : ['microphone', 'camera', 'hangup'],
  };
}

JitsiMeetConferenceOptions buildJitsiOptions(CallGrant grant, CallJoinOptions options) =>
    JitsiMeetConferenceOptions(
      serverURL: grant.serverURL,
      room: grant.room!,
      token: grant.jwt,
      userInfo: JitsiMeetUserInfo(displayName: options.displayName),
      configOverrides: jitsiConfigOverridesFor(grant, options),
      featureFlags: jitsiFeatureFlagsFor(isGuardian: options.isGuardian, observerOnly: grant.observerOnly),
    );

class JitsiCallProvider implements CallProvider {
  JitsiCallProvider({
    JitsiMeet? sdk,
    KioskChannel? kiosk,
    bool? release,
  })  : _sdk = sdk ?? JitsiMeet(),
        _kioskOverride = kiosk,
        _release = release ?? kReleaseMode;

  final JitsiMeet _sdk;
  final KioskChannel? _kioskOverride;
  final bool _release;

  @override
  CallProviderKind get kind => CallProviderKind.jitsi;
  @override
  bool get rendersOwnScreen => true;

  CallViewState _state = const CallViewState();
  final StreamController<CallViewState> _ctl = StreamController<CallViewState>.broadcast();
  @override
  CallViewState get state => _state;
  @override
  Stream<CallViewState> get states => _ctl.stream;
  void _set(CallViewState s) {
    _state = s;
    if (!_ctl.isClosed) _ctl.add(s);
  }

  @override
  Future<void> join(CallGrant grant, CallJoinOptions options) async {
    final server = grant.serverURL, room = grant.room, jwt = grant.jwt;
    if (grant.kind != CallProviderKind.jitsi || server == null || room == null || jwt == null) {
      throw const CallUnavailableException(CallUnavailableReason.refused, 'not a jitsi grant');
    }
    if (!jitsiServerUrlAllowed(server, release: _release)) {
      // Never reaches the SDK: a release build does not speak http to a call server.
      throw const CallUnavailableException(CallUnavailableReason.refused, 'call server address is not https');
    }
    _set(_state.copyWith(
      phase: CallPhase.connecting,
      cameraEnabled: options.mode == CallMode.video && !grant.observerOnly,
      micEnabled: !grant.observerOnly,
    ));

    final listener = JitsiMeetEventListener(
      conferenceJoined: (_) => _set(_state.copyWith(phase: CallPhase.connected)),
      // NOT an end: on a dropped connection this and readyToClose can be tens
      // of seconds apart; ending on both would pop the Navigator twice.
      conferenceTerminated: (url, error) {
        if (error != null) debugPrint('[olive.call] jitsi conference terminated: $error');
      },
      readyToClose: () => _set(_state.copyWith(phase: CallPhase.ended)),
      participantJoined: (email, name, role, id) {
        if (name != null && name.isNotEmpty) _set(_state.copyWith(remoteName: name));
      },
      participantLeft: (_) => _set(_state.copyWith(clearRemoteName: true)),
      audioMutedChanged: (muted) => _set(_state.copyWith(micEnabled: !muted)),
      videoMutedChanged: (muted) => _set(_state.copyWith(cameraEnabled: !muted)),
    );

    try {
      // §16.2 #6 / §5.20: the SDK opens the call in its own singleTask
      // Activity, which kiosk lock-task pinning refuses to launch as a second
      // task. Hand the pin to it instead of dropping it. A no-op on a device
      // that is not kiosk-locked (the guardian side).
      final kiosk = _kioskOverride ?? KioskChannel();
      String lockMode;
      try {
        lockMode = await kiosk.mode();
      } on MissingPluginException {
        lockMode = 'none'; // no native kiosk handler on this platform
      }
      if (lockMode != 'none') await kiosk.beginCallHandoff();
      final r = await _sdk.join(buildJitsiOptions(grant, options), listener);
      if (!r.isSuccess) {
        throw CallUnavailableException(CallUnavailableReason.unreachable, r.message);
      }
    } on CallUnavailableException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint('[olive.call] jitsi join did not start: ${e.code}');
      throw CallUnavailableException(CallUnavailableReason.unreachable, e.code);
    } catch (e) {
      debugPrint('[olive.call] jitsi join did not start: $e');
      throw CallUnavailableException(CallUnavailableReason.unreachable, '$e');
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _sdk.hangUp();
    } catch (e) {
      debugPrint('[olive.call] hangUp threw (non-fatal, ending from our side): $e');
      _set(_state.copyWith(phase: CallPhase.ended));
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _sdk.setAudioMuted(!enabled);
    _set(_state.copyWith(micEnabled: enabled));
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    await _sdk.setVideoMuted(!enabled);
    _set(_state.copyWith(cameraEnabled: enabled));
  }

  // Jitsi adapts its own video internally; the ladder's hint has no knob here.
  @override
  void applyQuality(Quality quality) {}

  @override
  Widget? buildRemoteVideo() => null;
  @override
  Widget? buildLocalVideo() => null;

  @override
  Future<void> dispose() async {
    await _ctl.close();
  }
}
