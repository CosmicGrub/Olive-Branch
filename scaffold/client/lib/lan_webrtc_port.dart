// UNVERIFIED on a real device in the change that added it: this file is the only place that touches flutter_webrtc,
// and a peer connection cannot run under `flutter test`. Everything it feeds (lan_call_engine.dart) is tested with a
// fake [RtcPort]; this adapter is a thin translation and is what the two-device check exercises.
// OLIVE BRANCH - the real media stack behind the 'lan-p2p' provider. MASTERFILE 5.19, 5.21, 5.23, 16.2 #6.
//
// What it does: gets the microphone (and the camera when asked), makes one peer connection with the ICE list the
// server's grant gave it (EMPTY on the home Wi-Fi: host candidates only, no outside service), keeps gathering
// candidates so a change of network is noticed, and turns the platform's callbacks into [RtcEvent]s.
//
// What it never does: record (no recorder, no MediaRecorder, no stats upload), talk to any server of its own, or
// put a candidate, an address or a path in anything a person can see.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Widget, SizedBox;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'lan_call_engine.dart';

class WebRtcPort implements RtcPort {
  rtc.RTCPeerConnection? _pc;
  rtc.MediaStream? _local;
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();
  final StreamController<RtcEvent> _events = StreamController<RtcEvent>.broadcast();
  bool _closed = false;
  bool _wantVideo = false;

  @override
  Stream<RtcEvent> get events => _events.stream;

  void _emit(RtcEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required bool relayOnly,
    required bool wantVideo,
  }) async {
    _wantVideo = wantVideo;
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    // Audio first: the microphone is asked for in every call. The camera only when this side chose video.
    final rtc.MediaStream stream = await rtc.navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': <String, dynamic>{'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': wantVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': <String, dynamic>{'ideal': 640},
              'height': <String, dynamic>{'ideal': 480},
              'frameRate': <String, dynamic>{'ideal': 24},
            }
          : false,
    });
    _local = stream;
    _localRenderer.srcObject = stream;
    final rtc.RTCPeerConnection pc = await rtc.createPeerConnection(<String, dynamic>{
      'iceServers': iceServers,
      // 'relay' sends everything through TURN (and hides each device's address from the other); 'all' otherwise.
      'iceTransportPolicy': relayOnly ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      // Keep looking for candidates for the whole call: this is what notices a new network (Wi-Fi to cellular).
      'continualGatheringPolicy': 'gather_continually',
    });
    _pc = pc;
    for (final rtc.MediaStreamTrack t in stream.getTracks()) {
      await pc.addTrack(t, stream);
    }
    if (!wantVideo) {
      // We send no picture, but we can still SEE theirs if they chose video.
      await pc.addTransceiver(
        kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: rtc.RTCRtpTransceiverInit(direction: rtc.TransceiverDirection.RecvOnly));
    }
    pc.onIceCandidate = (rtc.RTCIceCandidate c) {
      final String? line = c.candidate;
      if (line == null || line.isEmpty) return;
      _emit(RtcLocalCandidate(<String, dynamic>{
        'candidate': line, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}));
    };
    pc.onIceConnectionState = (rtc.RTCIceConnectionState s) {
      _emit(RtcTransportState(switch (s) {
        rtc.RTCIceConnectionState.RTCIceConnectionStateConnected ||
        rtc.RTCIceConnectionState.RTCIceConnectionStateCompleted => 'connected',
        rtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected => 'disconnected',
        rtc.RTCIceConnectionState.RTCIceConnectionStateFailed => 'failed',
        rtc.RTCIceConnectionState.RTCIceConnectionStateClosed => 'closed',
        _ => 'connecting',
      }));
    };
    pc.onTrack = (rtc.RTCTrackEvent e) {
      if (e.track.kind == 'video' && e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams.first;
        _emit(const RtcRemoteVideo(true));
      }
    };
    if (wantVideo) _emit(const RtcLocalVideo(true));
    // Video goes to the loudspeaker (the tablet is held away from the face); a voice-only call stays quiet and near.
    try {
      await rtc.Helper.setSpeakerphoneOn(wantVideo);
    } catch (_) {/* some devices refuse; the call still carries sound */}
  }

  Map<String, dynamic> _desc(rtc.RTCSessionDescription d) => <String, dynamic>{'type': d.type, 'sdp': d.sdp};

  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    final rtc.RTCPeerConnection pc = _pc!;
    if (iceRestart) await pc.restartIce();
    final rtc.RTCSessionDescription o = await pc.createOffer(<String, dynamic>{});
    await pc.setLocalDescription(o);
    return _desc(o);
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    final rtc.RTCPeerConnection pc = _pc!;
    final rtc.RTCSessionDescription a = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(a);
    return _desc(a);
  }

  @override
  Future<void> setRemoteDescription(Map<String, dynamic> description) async {
    await _pc!.setRemoteDescription(
        rtc.RTCSessionDescription(description['sdp'] as String, description['type'] as String));
  }

  @override
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    await _pc!.addCandidate(rtc.RTCIceCandidate(
        candidate['candidate'] as String?, candidate['sdpMid'] as String?, candidate['sdpMLineIndex'] as int?));
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    for (final rtc.MediaStreamTrack t in _local?.getAudioTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    for (final rtc.MediaStreamTrack t in _local?.getVideoTracks() ?? <rtc.MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
    _emit(RtcLocalVideo(enabled && _wantVideo));
  }

  @override
  Future<String?> selectedPathSummary() async {
    final rtc.RTCPeerConnection? pc = _pc;
    if (pc == null) return null;
    final List<rtc.StatsReport> reports = await pc.getStats();
    final Map<String, Map<dynamic, dynamic>> byId = <String, Map<dynamic, dynamic>>{
      for (final rtc.StatsReport r in reports) r.id: r.values};
    for (final rtc.StatsReport r in reports) {
      if (r.type != 'candidate-pair') continue;
      final Map<dynamic, dynamic> v = r.values;
      final bool picked = v['nominated'] == true || v['selected'] == true || v['state'] == 'succeeded';
      if (!picked) continue;
      final Object? lt = byId['${v['localCandidateId']}']?['candidateType'];
      final Object? rt = byId['${v['remoteCandidateId']}']?['candidateType'];
      if (lt is String && rt is String) return '$lt/$rt';
    }
    return null;
  }

  @override
  Widget? remoteView() => rtc.RTCVideoView(_remoteRenderer, objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);

  @override
  Widget? localView() => rtc.RTCVideoView(_localRenderer, mirror: true, objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      for (final rtc.MediaStreamTrack t in _local?.getTracks() ?? <rtc.MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
    } catch (_) {/* best effort: the call is over */}
    try {
      await _pc?.close();
      await _pc?.dispose();
    } catch (_) {/* likewise */}
    try {
      _remoteRenderer.srcObject = null;
      _localRenderer.srcObject = null;
      await _remoteRenderer.dispose();
      await _localRenderer.dispose();
    } catch (_) {/* likewise */}
    if (!_events.isClosed) await _events.close();
  }
}

/// A view that draws nothing, for an engine whose picture is not there yet.
Widget emptyView() => const SizedBox.shrink();
