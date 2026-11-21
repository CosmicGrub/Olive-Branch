// OLIVE BRANCH - the direct-call state machine behind the 'lan-p2p' provider. MASTERFILE 5.19, 5.21, 5.23, 16.2 #6.
//
// ENGINE-FREE ON PURPOSE. This file imports neither flutter_webrtc nor anything that draws: it talks to the media
// stack through [RtcPort] and to the other device through [CallSignaling]. That is what lets every rule below be
// tested without a phone: the real ports are WebRtcPort (lan_webrtc_port.dart) and ServerCallSignaling
// (call_signaling.dart); the tests use an in-memory pair.
//
// THE FLOW
//   caller:  open media -> offer -> (waits for) answer -> connected
//   callee:  open media -> (waits for) offer -> answer -> connected
//   Candidates are TRICKLED: sent as soon as they are found, in small batches, and held on the receiving side
//   until the remote description is set.
//
// STAYING UP WHEN THE NETWORK CHANGES (Wi-Fi to cellular, a router blip)
//   The media stack keeps gathering candidates (RtcPort.open asks for it). When the connection reports
//   "disconnected" and does not come back within [restartAfter], or reports "failed", the CALLER makes a new offer
//   with an ICE restart and the callee answers it; if the CALLEE is the one that notices, it sends "restart" and
//   the caller does it. Restarts are bounded ([maxRestarts] within [restartWindow]); past that the call ends calmly.
//   The picture is dropped while this happens and only comes back on her own tap (5.23.2 "resuming asks first").
//
// WHAT IS NEVER DONE HERE: recording (there is no recorder anywhere in this path), counting, scoring, or telling
// the user a technical reason. The chosen network path (host, server-reflexive or relay) goes to the debug log
// only, so a developer can tell whether a call was direct or relayed. It is never shown, least of all to a child.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Widget;

import 'call_modes.dart' show CallMode;
import 'call_provider.dart';
import 'call_signaling.dart';

// ---------------------------------------------------------------- the media port

/// What the media stack tells the engine.
sealed class RtcEvent {
  const RtcEvent();
}

/// A local ICE candidate was found: `{candidate, sdpMid, sdpMLineIndex}`.
class RtcLocalCandidate extends RtcEvent {
  const RtcLocalCandidate(this.candidate);
  final Map<String, dynamic> candidate;
}

/// The transport state: 'connecting' | 'connected' | 'disconnected' | 'failed' | 'closed'.
class RtcTransportState extends RtcEvent {
  const RtcTransportState(this.state);
  final String state;
}

class RtcRemoteVideo extends RtcEvent {
  const RtcRemoteVideo(this.present);
  final bool present;
}

class RtcLocalVideo extends RtcEvent {
  const RtcLocalVideo(this.present);
  final bool present;
}

/// The media stack, as the engine needs it. Real: WebRtcPort. Test: a fake.
abstract class RtcPort {
  /// Gets the microphone (and the camera when [wantVideo]) and creates the peer connection with this ICE list.
  /// [relayOnly] sends every packet through the TURN relay. Always keeps gathering candidates.
  Future<void> open({required List<Map<String, dynamic>> iceServers, required bool relayOnly, required bool wantVideo});
  Stream<RtcEvent> get events;

  /// `{type, sdp}`.
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false});
  Future<Map<String, dynamic>> createAnswer();
  Future<void> setRemoteDescription(Map<String, dynamic> description);
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate);

  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);

  /// "host/host", "srflx/host", "relay/relay"... of the pair in use, or null when not known. For the debug log only.
  Future<String?> selectedPathSummary();

  Widget? remoteView();
  Widget? localView();
  Future<void> close();
}

// ---------------------------------------------------------------- the engine

class LanCallEngine {
  LanCallEngine({
    required this.rtc,
    required this.signaling,
    required this.grant,
    this.restartAfter = const Duration(seconds: 4),
    this.candidateBatch = const Duration(milliseconds: 120),
    this.answerWait = const Duration(seconds: 90),
    this.maxRestarts = 5,
    this.restartWindow = const Duration(minutes: 2),
    this.pathReport,
  });

  final RtcPort rtc;
  final CallSignaling signaling;
  final CallGrant grant;

  /// How long "disconnected" may last before the engine acts on it.
  final Duration restartAfter;
  final Duration candidateBatch;

  /// How long the CALLER waits for anyone to answer before the call quietly ends (the knock waits ninety seconds).
  final Duration answerWait;
  final int maxRestarts;
  final Duration restartWindow;

  /// Receives the chosen path ("host/host", "relay/relay"...) once connected. Defaults to the debug log. Never UI.
  final void Function(String path)? pathReport;

  final StreamController<CallViewState> _states = StreamController<CallViewState>.broadcast();
  CallViewState _state = const CallViewState();
  CallViewState get state => _state;
  Stream<CallViewState> get states => _states.stream;

  StreamSubscription<RtcEvent>? _rtcSub;
  StreamSubscription<CallSignal>? _sigSub;
  Timer? _batchTimer, _restartTimer, _answerTimer;
  final List<Map<String, dynamic>> _outCandidates = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _heldRemote = <Map<String, dynamic>>[];
  bool _remoteSet = false;
  bool _started = false, _finished = false, _leaving = false;
  final List<DateTime> _restarts = <DateTime>[];
  bool _restarting = false;
  Future<void> _queue = Future<void>.value();

  /// For tests: how many ICE restarts this engine has made or been asked for.
  int get restartCount => _restarts.length;

  void _set(CallViewState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> start(CallJoinOptions options) async {
    if (_started) return;
    _started = true;
    _set(_state.copyWith(phase: CallPhase.connecting, cameraEnabled: options.mode == CallMode.video));
    try {
      await rtc.open(
        iceServers: grant.iceServers, relayOnly: grant.relayOnly, wantVideo: options.mode == CallMode.video);
    } catch (e) {
      // No microphone, no permission, no media stack: the call never started. Calm, and the reason stays in the log.
      debugPrint('[olive.call] lan-p2p could not open media: ${e.runtimeType}');
      await _teardown();
      throw CallUnavailableException(CallUnavailableReason.unreachable, 'media: ${e.runtimeType}');
    }
    _rtcSub = rtc.events.listen(_onRtc);
    // One message at a time, in the order they came: an offer must be applied before the candidates behind it.
    _sigSub = signaling.signals.listen((CallSignal s) {
      _queue = _queue.then((_) => _onSignal(s));
    }, onError: (Object _) {});
    unawaited(signaling.ended.then(_onSignalingEnded));
    if (grant.isCaller) {
      // The caller waits for an answer only so long: the knock on the other side waits ninety seconds and ends
      // quietly, and so does this.
      _answerTimer = Timer(answerWait, () {
        if (!_state.everConnected) unawaited(_end());
      });
      await _makeAndSendOffer(iceRestart: false);
    }
    // The callee does nothing yet: it answers when the offer arrives (it may already be waiting in the mailbox).
    await _publishMode();
  }

  // ------------------------------------------------------------ outgoing

  Future<void> _makeAndSendOffer({required bool iceRestart}) async {
    try {
      final Map<String, dynamic> offer = await rtc.createOffer(iceRestart: iceRestart);
      await signaling.send('offer', <String, dynamic>{'description': offer});
    } catch (e) {
      debugPrint('[olive.call] could not make the offer: ${e.runtimeType}');
    }
  }

  void _queueCandidate(Map<String, dynamic> c) {
    _outCandidates.add(c);
    _batchTimer ??= Timer(candidateBatch, _flushCandidates);
  }

  void _flushCandidates() {
    _batchTimer = null;
    if (_outCandidates.isEmpty || _finished) return;
    final List<Map<String, dynamic>> batch = List<Map<String, dynamic>>.of(_outCandidates);
    _outCandidates.clear();
    unawaited(signaling.send('ice', <String, dynamic>{'candidates': batch}));
  }

  Future<void> _publishMode() async {
    // The mode only (never why), so the other side shows the calm listening surface instead of a black square.
    await signaling.send('mode', <String, dynamic>{'mode': _state.cameraEnabled ? 'video' : 'audio_only'});
  }

  // ------------------------------------------------------------ incoming

  Future<void> _onSignal(CallSignal s) async {
    if (_finished) return;
    try {
      switch (s.kind) {
        case 'offer':
          await _onOffer(s.payload);
        case 'answer':
          await _onAnswer(s.payload);
        case 'ice':
          await _onIce(s.payload);
        case 'restart':
          // Only the caller restarts (it owns the offer). A callee never sends one to a callee.
          if (grant.isCaller) await _restart();
        case 'mode':
          _set(_state.copyWith(remoteMode: s.payload['mode'] == 'audio_only' ? CallMode.audioOnly : CallMode.video));
        case 'bye':
          await _end();
        default:
          break; // an unknown kind from a newer build is ignored, never a failure
      }
    } catch (e) {
      debugPrint('[olive.call] lan-p2p signal ${s.kind} not applied: ${e.runtimeType}');
    }
  }

  Map<String, dynamic>? _description(Map<String, dynamic> payload) {
    final Object? d = payload['description'];
    if (d is! Map) return null;
    final Object? type = d['type'], sdp = d['sdp'];
    if (type is! String || sdp is! String || sdp.isEmpty) return null;
    return <String, dynamic>{'type': type, 'sdp': sdp};
  }

  Future<void> _onOffer(Map<String, dynamic> payload) async {
    if (grant.isCaller) return; // a caller never answers; a stray offer is ignored
    final Map<String, dynamic>? d = _description(payload);
    if (d == null || d['type'] != 'offer') return;
    await rtc.setRemoteDescription(d);
    _remoteSet = true;
    await _drainHeld();
    final Map<String, dynamic> answer = await rtc.createAnswer();
    await signaling.send('answer', <String, dynamic>{'description': answer});
  }

  Future<void> _onAnswer(Map<String, dynamic> payload) async {
    if (!grant.isCaller) return;
    final Map<String, dynamic>? d = _description(payload);
    if (d == null || d['type'] != 'answer') return;
    await rtc.setRemoteDescription(d);
    _remoteSet = true;
    _answerTimer?.cancel();
    await _drainHeld();
  }

  Future<void> _onIce(Map<String, dynamic> payload) async {
    final Object? list = payload['candidates'];
    if (list is! List) return;
    for (final Object? c in list) {
      if (c is! Map) continue;
      final Map<String, dynamic> cand = Map<String, dynamic>.from(c);
      if (cand['candidate'] is! String) continue;
      if (_remoteSet) {
        await _addRemote(cand);
      } else {
        _heldRemote.add(cand);
      }
    }
  }

  Future<void> _addRemote(Map<String, dynamic> c) async {
    try {
      await rtc.addRemoteCandidate(c);
    } catch (e) {
      debugPrint('[olive.call] a remote candidate was not usable: ${e.runtimeType}');
    }
  }

  Future<void> _drainHeld() async {
    final List<Map<String, dynamic>> held = List<Map<String, dynamic>>.of(_heldRemote);
    _heldRemote.clear();
    for (final Map<String, dynamic> c in held) {
      await _addRemote(c);
    }
  }

  // ------------------------------------------------------------ the media stack

  void _onRtc(RtcEvent e) {
    if (_finished) return;
    switch (e) {
      case RtcLocalCandidate(:final candidate):
        _queueCandidate(candidate);
      case RtcRemoteVideo(:final present):
        _set(_state.copyWith(hasRemoteVideo: present));
      case RtcLocalVideo(:final present):
        _set(_state.copyWith(hasLocalVideo: present));
      case RtcTransportState(:final state):
        _onTransport(state);
    }
  }

  void _onTransport(String s) {
    switch (s) {
      case 'connected':
        _restartTimer?.cancel();
        _answerTimer?.cancel();
        _restarting = false;
        // After a restart the picture stays off until her own tap (5.23.2): the camera state was already dropped.
        _set(_state.copyWith(phase: CallPhase.connected));
        unawaited(_reportPath());
      case 'disconnected':
        if (!_state.everConnected) return; // still setting up: the answer timer and the media stack decide
        _set(_state.copyWith(phase: CallPhase.reconnecting));
        _restartTimer?.cancel();
        _restartTimer = Timer(restartAfter, () => unawaited(_recover()));
      case 'failed':
        if (!_state.everConnected) {
          unawaited(_recover());
          return;
        }
        _set(_state.copyWith(phase: CallPhase.reconnecting));
        unawaited(_recover());
      case 'closed':
        if (!_leaving) unawaited(_end());
    }
  }

  Future<void> _reportPath() async {
    try {
      final String? path = await rtc.selectedPathSummary();
      if (path == null) return;
      (pathReport ?? (String p) => debugPrint('[olive.call] lan-p2p path $p'))(path);
    } catch (_) {
      // a log line only
    }
  }

  /// The caller restarts; the callee asks the caller to.
  Future<void> _recover() async {
    if (_finished || _restarting) return;
    if (grant.isCaller) {
      await _restart();
    } else {
      _restarts.add(DateTime.now());
      if (_overBudget()) {
        await _end();
        return;
      }
      await signaling.send('restart', const <String, dynamic>{});
      // Ask again if nothing comes of it, until the budget runs out.
      _restartTimer?.cancel();
      _restartTimer = Timer(restartAfter * 2, () {
        if (_state.phase != CallPhase.connected) unawaited(_recover());
      });
    }
  }

  bool _overBudget() {
    final DateTime cutoff = DateTime.now().subtract(restartWindow);
    _restarts.removeWhere((DateTime t) => t.isBefore(cutoff));
    return _restarts.length > maxRestarts;
  }

  Future<void> _restart() async {
    if (_finished) return;
    _restarts.add(DateTime.now());
    if (_overBudget()) {
      await _end();
      return;
    }
    _restarting = true;
    // The picture is dropped and asks first before it comes back; the voice stays (8.14: audio is never shed).
    if (_state.cameraEnabled) {
      try {
        await rtc.setCameraEnabled(false);
      } catch (_) {/* best effort */}
      _set(_state.copyWith(cameraEnabled: false, awaitingResumeConsent: true));
      unawaited(_publishMode());
    }
    _set(_state.copyWith(phase: CallPhase.reconnecting));
    _remoteSet = true; // the remote description already stands; new candidates may be added at once
    await _makeAndSendOffer(iceRestart: true);
    _restartTimer?.cancel();
    _restartTimer = Timer(restartAfter * 3, () {
      _restarting = false;
      if (!_finished && _state.phase != CallPhase.connected) unawaited(_recover());
    });
  }

  void _onSignalingEnded(CallSignalingEnd why) {
    if (_finished) return;
    switch (why) {
      case CallSignalingEnd.closed:
        // The server says the call is over (the other side hung up, or ended it).
        unawaited(_end());
      case CallSignalingEnd.lost:
        // The server has been out of reach for a long time. A call already carrying sound keeps going (the media
        // does not depend on it); one still being set up cannot finish.
        if (!_state.everConnected) unawaited(_end());
    }
  }

  // ------------------------------------------------------------ controls

  Future<void> setMicrophoneEnabled(bool enabled) async {
    await rtc.setMicrophoneEnabled(enabled);
    _set(_state.copyWith(micEnabled: enabled));
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (enabled == _state.cameraEnabled) return;
    await rtc.setCameraEnabled(enabled);
    _set(_state.copyWith(cameraEnabled: enabled, awaitingResumeConsent: enabled ? false : null));
    unawaited(_publishMode());
  }

  /// Hang up: tells the other side, then closes everything. [CallPhase.ended] arrives through [states].
  Future<void> leave() async {
    if (_finished) return;
    _leaving = true;
    try {
      await signaling.send('bye', const <String, dynamic>{});
    } catch (_) {/* hanging up never waits on the network */}
    await _end();
  }

  Future<void> _end() async {
    if (_finished) return;
    _finished = true;
    await _teardown();
    _set(_state.copyWith(phase: CallPhase.ended));
  }

  Future<void> _teardown() async {
    _batchTimer?.cancel();
    _restartTimer?.cancel();
    _answerTimer?.cancel();
    await _rtcSub?.cancel();
    await _sigSub?.cancel();
    // The channel first: it must stop polling whatever the media stack does. The media stack gets a bounded time to
    // let go, so a hang-up is never stuck behind a platform call that does not come back.
    try {
      await signaling.close();
    } catch (_) {/* closing twice is fine */}
    try {
      await rtc.close().timeout(const Duration(seconds: 3));
    } catch (_) {/* likewise */}
  }

  Future<void> dispose() async {
    if (!_finished) {
      _finished = true;
      await _teardown();
    }
    if (!_states.isClosed) await _states.close();
  }
}
