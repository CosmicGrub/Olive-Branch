// The Jitsi engine behind CallProvider, driven through a fake SDK platform:
// options, feature flags, https policy, kiosk handoff, and the event mapping
// (conferenceTerminated is NOT an end; only readyToClose is).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:jitsi_meet_flutter_sdk/src/jitsi_meet_platform_interface.dart';
import 'package:jitsi_meet_flutter_sdk/src/method_response.dart';
import 'package:olive_client/call_modes.dart';
import 'package:olive_client/call_provider.dart';
import 'package:olive_client/jitsi_call_provider.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends JitsiMeetPlatform with MockPlatformInterfaceMixin {
  JitsiMeetConferenceOptions? options;
  JitsiMeetEventListener? listener;
  final List<String> calls = [];
  bool joinOk = true;
  bool joinThrows = false;
  @override
  Future<MethodResponse> join(JitsiMeetConferenceOptions o, JitsiMeetEventListener? l) async {
    calls.add('join'); options = o; listener = l;
    if (joinThrows) throw PlatformException(code: 'boom');
    return MethodResponse(isSuccess: joinOk, message: joinOk ? null : 'no');
  }
  @override
  Future<MethodResponse> hangUp() async { calls.add('hangUp'); return MethodResponse(isSuccess: true); }
  @override
  Future<MethodResponse> setAudioMuted(bool m) async { calls.add('audioMuted:$m'); return MethodResponse(isSuccess: true); }
  @override
  Future<MethodResponse> setVideoMuted(bool m) async { calls.add('videoMuted:$m'); return MethodResponse(isSuccess: true); }
}

class _FakeKiosk extends KioskChannel {
  _FakeKiosk(this.lock);
  final String lock;
  int handoffs = 0;
  @override
  Future<String> mode() async => lock;
  @override
  Future<void> beginCallHandoff() async { handoffs++; }
}

const _grant = CallGrant.jitsi(jwt: 'a.b.c', room: 'oroom', serverURL: 'https://192.168.1.50:8443', displayName: 'Dad');
const _opts = CallJoinOptions(displayName: 'Ivy', isGuardian: false);

void main() {
  late _FakePlatform platform;
  setUp(() { platform = _FakePlatform(); JitsiMeetPlatform.instance = platform; });

  JitsiCallProvider make({String lock = 'none', bool release = true}) =>
      JitsiCallProvider(sdk: JitsiMeet(), kiosk: _FakeKiosk(lock), release: release);

  test('it is the engine that draws its own screen', () {
    final p = make();
    expect(p.kind, CallProviderKind.jitsi);
    expect(p.rendersOwnScreen, true);
    expect(p.buildRemoteVideo(), isNull);
  });

  test('join hands the SDK the server, the derived room and the JWT', () async {
    await make().join(_grant, _opts);
    final o = platform.options!;
    expect(o.serverURL, 'https://192.168.1.50:8443');
    expect(o.room, 'oroom');
    expect(o.token, 'a.b.c');
    expect(o.userInfo?.displayName, 'Ivy');
  });

  test('config: p2p off + relay, no third parties, mic/camera/hang-up toolbar only', () async {
    await make().join(_grant, _opts);
    final c = platform.options!.configOverrides!;
    expect((c['p2p'] as Map)['enabled'], false);
    expect((c['p2p'] as Map)['iceTransportPolicy'], 'relay');
    expect(c['disableThirdPartyRequests'], true);
    expect(c['prejoinConfig'], {'enabled': false});
    expect(c['toolbarButtons'], ['microphone', 'camera', 'hangup']);
    expect(c['startWithVideoMuted'], false);
  });

  test('audio-only is her choice: video starts muted', () async {
    await make().join(_grant, const CallJoinOptions(displayName: 'Ivy', isGuardian: false, mode: CallMode.audioOnly));
    final c = platform.options!.configOverrides!;
    expect(c['startWithVideoMuted'], true);
    expect(c['startAudioOnly'], true);
  });

  test('an observer-only guardian joins muted with a hang-up-only toolbar', () async {
    const g = CallGrant.jitsi(jwt: 'a.b.c', room: 'r', serverURL: 'https://h', observerOnly: true);
    await make().join(g, const CallJoinOptions(displayName: 'Dad', isGuardian: true));
    final o = platform.options!;
    expect(o.configOverrides!['toolbarButtons'], ['hangup']);
    expect(o.configOverrides!['startWithAudioMuted'], true);
    expect(o.featureFlags![FeatureFlags.audioMuteButtonEnabled], false);
  });

  test('feature flags: no chat, settings, invite, recording, screen share for anyone', () {
    for (final guardian in [true, false]) {
      final f = jitsiFeatureFlagsFor(isGuardian: guardian);
      for (final k in [FeatureFlags.chatEnabled, FeatureFlags.settingsEnabled, FeatureFlags.inviteEnabled,
          FeatureFlags.recordingEnabled, FeatureFlags.liveStreamingEnabled, FeatureFlags.androidScreenSharingEnabled,
          FeatureFlags.lobbyModeEnabled, FeatureFlags.serverUrlChangeEnabled]) {
        expect(f[k], false, reason: '$k for guardian=$guardian');
      }
    }
  });

  test('release refuses a non-https server before the SDK ever sees it', () async {
    const g = CallGrant.jitsi(jwt: 'a.b.c', room: 'r', serverURL: 'http://192.168.1.50:8000');
    await expectLater(make(release: true).join(g, _opts),
        throwsA(isA<CallUnavailableException>().having((e) => e.reason, 'reason', CallUnavailableReason.refused)));
    expect(platform.calls, isEmpty);
  });

  test('a livekit grant is refused by this engine', () async {
    await expectLater(make().join(const CallGrant.livekit(token: 't', wsURL: 'w'), _opts),
        throwsA(isA<CallUnavailableException>()));
  });

  test('SDK failures become calm unavailable reasons, never raw text', () async {
    platform.joinOk = false;
    await expectLater(make().join(_grant, _opts), throwsA(isA<CallUnavailableException>()));
    platform.joinOk = true; platform.joinThrows = true;
    await expectLater(make().join(_grant, _opts), throwsA(isA<CallUnavailableException>()));
  });

  test('kiosk handoff happens only on a locked device', () async {
    final locked = _FakeKiosk('pinned');
    await JitsiCallProvider(sdk: JitsiMeet(), kiosk: locked, release: true).join(_grant, _opts);
    expect(locked.handoffs, 1);
    final free = _FakeKiosk('none');
    await JitsiCallProvider(sdk: JitsiMeet(), kiosk: free, release: true).join(_grant, _opts);
    expect(free.handoffs, 0);
  });

  test('events: joined connects; terminated is NOT an end; readyToClose ends', () async {
    final p = make();
    await p.join(_grant, _opts);
    expect(p.state.phase, CallPhase.connecting);
    platform.listener!.conferenceJoined!('u');
    expect(p.state.phase, CallPhase.connected);
    expect(p.state.everConnected, true);
    platform.listener!.conferenceTerminated!('u', 'dropped');
    expect(p.state.phase, CallPhase.connected);
    platform.listener!.participantJoined!(null, 'Dad', null, 'p1');
    expect(p.state.remoteName, 'Dad');
    platform.listener!.participantLeft!('p1');
    expect(p.state.remoteName, isNull);
    platform.listener!.readyToClose!();
    expect(p.state.phase, CallPhase.ended);
  });

  test('mute, camera and hang-up reach the SDK', () async {
    final p = make();
    await p.join(_grant, _opts);
    await p.setMicrophoneEnabled(false);
    await p.setCameraEnabled(false);
    await p.leave();
    expect(platform.calls, containsAll(['audioMuted:true', 'videoMuted:true', 'hangUp']));
    expect(p.state.micEnabled, false);
    expect(p.state.cameraEnabled, false);
  });
}
