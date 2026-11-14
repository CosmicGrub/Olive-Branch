// OLIVE BRANCH — the LiveKit call engine behind [CallProvider]. UNVERIFIED on
// real devices in this build (it ran on hardware in the LiveKit era; the move
// behind the provider seam is covered by flutter analyze/test, not re-run on a
// device). MASTERFILE §16.2 #6: LiveKit is the SELECTABLE provider now
// (CALL_PROVIDER=livekit on the server); Jitsi is the default.
//
// Everything here was call_screen.dart's own LiveKit logic, moved, not
// rewritten: relay-only ICE (§5.21.1), adaptiveStream/dynacast, the ladder's
// per-track quality hint, the data-message transport for the voice-only line
// (§5.23.1), the bounded reconnect that works around a confirmed
// livekit_client race, and "resuming asks first" (§5.23.2). Each decision's
// full account is in the comments that travelled with it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'call_modes.dart' show CallMode;
import 'call_provider.dart';
import 'degradation_banner.dart' show Condition, Quality;

/// §5.21.1 — "all media is relayed, always." LiveKit's SFU never offers a
/// peer-to-peer path, so forcing relay-only ICE is defense in depth: this
/// client's own address is visible exclusively to the LiveKit edge.
const _connectOptions = lk.ConnectOptions(
  rtcConfiguration: lk.RTCConfiguration(iceTransportPolicy: lk.RTCIceTransportPolicy.relay),
);

/// Network-resilience A1: both default to false in this SDK; adaptiveStream
/// serves a lower simulcast layer to a small/off-screen tile, dynacast stops
/// publishing a layer nobody subscribes to.
const _roomOptions = lk.RoomOptions(adaptiveStream: true, dynacast: true);

/// Maps the hysteresis ladder's three video tiers onto LiveKit's per-track
/// subscription quality (the real `RemoteTrackPublication.setVideoQuality`).
lk.VideoQuality videoQualityFor(Quality q) => switch (q) {
  Quality.q720 => lk.VideoQuality.HIGH,
  Quality.q360 => lk.VideoQuality.MEDIUM,
  Quality.q180 => lk.VideoQuality.LOW,
};

/// poor/lost are the only two "strained" states; unknown (no report yet) and
/// good/excellent are all fine — never blame an unreported connection.
Condition conditionFor(lk.ConnectionQuality q) =>
    (q == lk.ConnectionQuality.poor || q == lk.ConnectionQuality.lost)
        ? Condition.strained
        : Condition.good;

class LiveKitCallProvider implements CallProvider {
  LiveKitCallProvider();

  @override
  CallProviderKind get kind => CallProviderKind.livekit;
  @override
  bool get rendersOwnScreen => false;

  // Deliberately NOT constructed eagerly: livekit_client's Room constructor
  // starts an internal cache-cleanup timer with no way to cancel it, so a
  // provider that never reaches join() must never start one (flutter_test's
  // pending-timer check would catch it on every test).
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;

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

  lk.VideoTrack? _localVideoTrack;
  lk.VideoTrack? _remoteVideoTrack;
  lk.RemoteTrackPublication? _remoteVideoPublication;
  final ValueNotifier<int> _tracksChanged = ValueNotifier<int>(0);
  void _bumpTracks() {
    _tracksChanged.value++;
    _set(_state.copyWith(
      hasRemoteVideo: _remoteVideoTrack != null, hasLocalVideo: _localVideoTrack != null));
  }

  String? _lastToken;
  String? _lastWsURL;
  // Set right before our own hang-up so RoomDisconnectedEvent can tell "she
  // hung up" from "the SDK dropped us"; only the latter reconnects.
  bool _hangingUp = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 2;
  bool _reconnecting = false;
  bool _disposed = false;

  @override
  Future<void> join(CallGrant grant, CallJoinOptions options) async {
    final token = grant.token, wsURL = grant.wsURL;
    if (grant.kind != CallProviderKind.livekit || token == null || wsURL == null) {
      throw const CallUnavailableException(CallUnavailableReason.refused, 'not a livekit grant');
    }
    _lastToken = token;
    _lastWsURL = wsURL;
    _hangingUp = false;
    _reconnectAttempts = 0;
    _set(_state.copyWith(
      phase: CallPhase.connecting,
      cameraEnabled: options.mode == CallMode.video,
    ));
    try {
      final room = lk.Room(roomOptions: _roomOptions);
      _room = room;
      _listener = room.createListener()..listen(_handleRoomEvent);
      await room.connect(wsURL, token, connectOptions: _connectOptions);
      // Respects her real choice (§5.23.1). Mic is unconditional: audio is
      // §8.14's NEVER_SHED, never gated by mode.
      await room.localParticipant?.setCameraEnabled(_state.cameraEnabled);
      await room.localParticipant?.setMicrophoneEnabled(true);
      unawaited(_publishMode());
      _set(_state.copyWith(phase: CallPhase.connected, micEnabled: true));
    } on SocketException catch (e) {
      throw CallUnavailableException(CallUnavailableReason.unreachable, e.message);
    } on TimeoutException catch (e) {
      throw CallUnavailableException(CallUnavailableReason.unreachable, e.message);
    } catch (e) {
      // Anything the engine refused to start with: the screen turns this into
      // calm wording; the text stays in logs only.
      debugPrint('[olive.call] livekit join did not start: $e');
      throw CallUnavailableException(CallUnavailableReason.unreachable, '$e');
    }
  }

  /// Publishes THIS device's mode to the other side as a DATA MESSAGE, not
  /// participant metadata (every grant sets canUpdateOwnMetadata:false, so a
  /// metadata version would be silently rejected). Mode only, never why.
  /// Best-effort: a failure must never fail the call.
  Future<void> _publishMode() async {
    final audioOnly = !_state.cameraEnabled;
    try {
      await _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'mode': audioOnly ? 'audio_only' : 'video'})),
        reliable: true,
        topic: 'olive.call_mode');
    } catch (e) {
      debugPrint('[olive.call] publishData(mode) failed (non-fatal): $e');
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    _set(_state.copyWith(micEnabled: enabled));
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    if (enabled == _state.cameraEnabled) return;
    await _room?.localParticipant?.setCameraEnabled(enabled);
    _set(_state.copyWith(cameraEnabled: enabled, awaitingResumeConsent: enabled ? false : null));
    unawaited(_publishMode());
  }

  @override
  void applyQuality(Quality quality) {
    _remoteVideoPublication?.setVideoQuality(videoQualityFor(quality));
  }

  @override
  Future<void> leave() async {
    // Before disconnect() so the RoomDisconnectedEvent it triggers reads as
    // "she hung up". Room.disconnect() is confirmed, live, to sometimes hang
    // and throw inside the SDK; a hang-up tap must never strand her, so a
    // throw still ends the call from our side.
    _hangingUp = true;
    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[olive.call] disconnect() threw on hang-up (non-fatal): $e');
      _end();
    }
  }

  void _end() => _set(_state.copyWith(phase: CallPhase.ended));

  void _handleRoomEvent(lk.RoomEvent event) {
    if (_disposed) return;
    if (event is lk.RoomDisconnectedEvent) {
      debugPrint('[olive.call] RoomDisconnectedEvent — reconnecting=$_reconnecting '
          'hangingUp=$_hangingUp attempts=$_reconnectAttempts reason=${event.reason}');
      if (_reconnecting) return; // one attempt in flight is enough
      if (_hangingUp || _reconnectAttempts >= _maxReconnectAttempts) {
        _end();
        return;
      }
      // An UNEXPECTED disconnect: recover instead of stranding her on a dead
      // screen (a confirmed livekit_client race can tear a live room down).
      unawaited(_attemptReconnect());
      return;
    }
    if (event is lk.ParticipantConnectedEvent) {
      final p = event.participant;
      _set(_state.copyWith(remoteName: p.name.isNotEmpty ? p.name : p.identity));
      return;
    }
    if (event is lk.ParticipantDisconnectedEvent) {
      _remoteVideoTrack = null;
      _remoteVideoPublication = null;
      _bumpTracks();
      _set(_state.copyWith(clearRemoteName: true));
      return;
    }
    if (event is lk.LocalTrackPublishedEvent) {
      final t = event.publication.track;
      if (t is lk.LocalVideoTrack) { _localVideoTrack = t; _bumpTracks(); }
      return;
    }
    if (event is lk.LocalTrackUnpublishedEvent) {
      // Turning her own camera off must not leave a frozen last frame.
      if (event.publication.kind == lk.TrackType.VIDEO) { _localVideoTrack = null; _bumpTracks(); }
      return;
    }
    if (event is lk.DataReceivedEvent) {
      if (event.topic != 'olive.call_mode') return;
      try {
        final decoded = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
        _set(_state.copyWith(
          remoteMode: decoded['mode'] == 'audio_only' ? CallMode.audioOnly : CallMode.video));
      } catch (e) {
        debugPrint('[olive.call] could not parse remote mode data (non-fatal): $e');
      }
      return;
    }
    if (event is lk.TrackSubscribedEvent) {
      final track = event.track;
      if (track is lk.VideoTrack) {
        _remoteVideoTrack = track;
        _remoteVideoPublication = event.publication;
        _bumpTracks();
      }
      return;
    }
    if (event is lk.TrackUnsubscribedEvent) {
      if (event.track is lk.VideoTrack) {
        _remoteVideoTrack = null;
        _remoteVideoPublication = null;
        _bumpTracks();
      }
      return;
    }
    if (event is lk.ParticipantConnectionQualityUpdatedEvent) {
      // Only the remote participant's own report drives the ladder.
      if (event.participant is! lk.LocalParticipant) {
        _set(_state.copyWith(condition: conditionFor(event.connectionQuality)));
      }
      return;
    }
  }

  /// Reconnects with the SAME already-proven token (a LiveKit token is a
  /// reusable grant; the server TTL outlives the few seconds this needs),
  /// bounded and backed off so a real failure still ends honestly.
  Future<void> _attemptReconnect() async {
    _reconnecting = true;
    try {
      await _attemptReconnectImpl();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _attemptReconnectImpl() async {
    _reconnectAttempts++;
    _set(_state.copyWith(phase: CallPhase.reconnecting));
    // Deliberately NOT disposing/disconnecting the old room: by now it is in
    // the broken state that caused the disconnect, and disconnect() on it
    // awaits an event that never arrives (live-confirmed). Drop the reference.
    try {
      await _listener?.dispose();
    } catch (e) {
      debugPrint('[olive.call] listener dispose failed during reconnect (non-fatal): $e');
    }
    _room = null;
    final token = _lastToken, wsURL = _lastWsURL;
    if (token == null || wsURL == null) { _end(); return; }
    await Future<void>.delayed(Duration(milliseconds: 800 * _reconnectAttempts));
    if (_disposed) return;
    try {
      final room = lk.Room(roomOptions: _roomOptions);
      _room = room;
      _listener = room.createListener()..listen(_handleRoomEvent);
      await room.connect(wsURL, token, connectOptions: _connectOptions);
      // Audio restores unconditionally (§8.14). Video does not: §5.23.2
      // "resuming asks first" — a camera that was ON before an unexpected
      // drop stays off and waits for her own tap.
      final hadCameraOn = _state.cameraEnabled;
      await room.localParticipant?.setCameraEnabled(false);
      await room.localParticipant?.setMicrophoneEnabled(_state.micEnabled);
      _reconnectAttempts = 0; // a reconnect that holds earns back the budget
      _set(_state.copyWith(
        phase: CallPhase.connected, cameraEnabled: false, awaitingResumeConsent: hadCameraOn));
      unawaited(_publishMode());
    } catch (_) {
      // connect() never succeeded, so no disconnect event is guaranteed.
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _end();
      } else {
        unawaited(_attemptReconnect());
      }
    }
  }

  @override
  Widget? buildRemoteVideo() => ValueListenableBuilder<int>(
        valueListenable: _tracksChanged,
        builder: (_, _, _) => _remoteVideoTrack == null
            ? const SizedBox.shrink()
            : lk.VideoTrackRenderer(_remoteVideoTrack!),
      );

  @override
  Widget? buildLocalVideo() => ValueListenableBuilder<int>(
        valueListenable: _tracksChanged,
        builder: (_, _, _) => _localVideoTrack == null
            ? const SizedBox.shrink()
            : lk.VideoTrackRenderer(_localVideoTrack!, mirrorMode: lk.VideoViewMirrorMode.mirror),
      );

  @override
  Future<void> dispose() async {
    _disposed = true;
    // Fire-and-forget with catchError: these SDK teardowns are confirmed to
    // sometimes hang and throw, and a sync dispose cannot await them.
    unawaited(_listener?.dispose().catchError((Object e) {
      debugPrint('[olive.call] listener dispose failed on exit (non-fatal): $e');
      return false;
    }));
    unawaited(_room?.dispose().catchError((Object e) {
      debugPrint('[olive.call] room dispose failed on exit (non-fatal): $e');
      return false;
    }));
    _tracksChanged.dispose();
    await _ctl.close();
  }
}
