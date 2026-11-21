// OLIVE BRANCH - the direct-call state machine (lan_call_engine.dart), driven by a fake media port and an in-memory
// signalling pair, so every rule runs without a phone: the handshake in both directions, trickle ICE held until the
// remote description is set, the ICE list and relay-only reaching BOTH sides, restart after a network change from
// either side and its budget, hanging up from each side, the calm endings, and "nothing records".
// MASTERFILE 5.19, 5.23, 16.2 #6.
import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart';
import 'package:olive_client/call_provider.dart';
import 'package:olive_client/call_signaling.dart';
import 'package:olive_client/lan_call_engine.dart';

class FakeRtcPort implements RtcPort {
  FakeRtcPort({this.failOpen = false});
  final bool failOpen;
  final StreamController<RtcEvent> ctl = StreamController<RtcEvent>.broadcast();
  final List<String> log = <String>[];
  List<Map<String, dynamic>>? openedIce;
  bool? openedRelay, openedVideo;
  final List<Map<String, dynamic>> remoteCandidates = <Map<String, dynamic>>[];
  final List<bool> offerRestarts = <bool>[];
  Map<String, dynamic>? remote;
  bool closed = false;
  int _n = 0;
  String? path = 'host/host';

  @override
  Stream<RtcEvent> get events => ctl.stream;
  @override
  Future<void> open({required List<Map<String, dynamic>> iceServers, required bool relayOnly, required bool wantVideo}) async {
    if (failOpen) throw StateError('no microphone');
    openedIce = iceServers;
    openedRelay = relayOnly;
    openedVideo = wantVideo;
    log.add('open');
  }

  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    offerRestarts.add(iceRestart);
    log.add('offer${iceRestart ? '(restart)' : ''}');
    return <String, dynamic>{'type': 'offer', 'sdp': 'offer-sdp-${++_n}'};
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    log.add('answer');
    return <String, dynamic>{'type': 'answer', 'sdp': 'answer-sdp-${++_n}'};
  }

  @override
  Future<void> setRemoteDescription(Map<String, dynamic> d) async {
    remote = d;
    log.add('remote:${d['type']}');
  }

  @override
  Future<void> addRemoteCandidate(Map<String, dynamic> c) async {
    log.add('cand:${c['candidate']}');
    remoteCandidates.add(c);
  }

  @override
  Future<void> setMicrophoneEnabled(bool e) async => log.add('mic:$e');
  @override
  Future<void> setCameraEnabled(bool e) async => log.add('cam:$e');
  @override
  Future<String?> selectedPathSummary() async => path;
  @override
  Widget? remoteView() => null;
  @override
  Widget? localView() => null;
  @override
  Future<void> close() async {
    closed = true;
    log.add('close');
  }

  void emit(RtcEvent e) => ctl.add(e);
}

const CallGrant _callerGrant = CallGrant.lanP2p(sessionId: 's1', role: 'caller', displayName: 'Dad');
const CallGrant _calleeGrant = CallGrant.lanP2p(sessionId: 's1', role: 'callee', displayName: 'Ivy');
const CallJoinOptions _video = CallJoinOptions(displayName: 'x', isGuardian: true);
const CallJoinOptions _audio = CallJoinOptions(displayName: 'x', mode: CallMode.audioOnly, isGuardian: false);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

class _Pair {
  _Pair({CallGrant caller = _callerGrant, CallGrant callee = _calleeGrant, Duration restartAfter = const Duration(milliseconds: 40),
      Duration answerWait = const Duration(seconds: 5), int maxRestarts = 5, List<String>? paths}) {
    final (a, b) = MemoryCallSignaling.pair();
    sigCaller = a;
    sigCallee = b;
    callerPort = FakeRtcPort();
    calleePort = FakeRtcPort();
    callerEngine = LanCallEngine(rtc: callerPort, signaling: a, grant: caller, restartAfter: restartAfter,
        candidateBatch: const Duration(milliseconds: 5), answerWait: answerWait, maxRestarts: maxRestarts,
        pathReport: paths?.add);
    calleeEngine = LanCallEngine(rtc: calleePort, signaling: b, grant: callee, restartAfter: restartAfter,
        candidateBatch: const Duration(milliseconds: 5), answerWait: answerWait, maxRestarts: maxRestarts);
  }
  late final MemoryCallSignaling sigCaller, sigCallee;
  late final FakeRtcPort callerPort, calleePort;
  late final LanCallEngine callerEngine, calleeEngine;

  Future<void> connectBoth() async {
    await callerEngine.start(_video);
    await calleeEngine.start(_video);
    await _settle();
    callerPort.emit(const RtcTransportState('connected'));
    calleePort.emit(const RtcTransportState('connected'));
    await _settle();
  }

  Future<void> dispose() async {
    await callerEngine.dispose();
    await calleeEngine.dispose();
  }
}

void main() {
  group('the handshake', () {
    test('caller offers, callee answers, both connect, and the chosen path is logged only', () async {
      final paths = <String>[];
      final p = _Pair(paths: paths);
      await p.connectBoth();
      expect(p.callerPort.log.take(3), ['open', 'offer', 'remote:answer']);
      expect(p.calleePort.log.take(3), ['open', 'remote:offer', 'answer']);
      expect(p.callerEngine.state.phase, CallPhase.connected);
      expect(p.calleeEngine.state.phase, CallPhase.connected);
      expect(p.callerEngine.state.everConnected, true);
      expect(paths, ['host/host'], reason: 'the chosen path goes to the log callback, nowhere else');
      await p.dispose();
    });

    test('the callee that joins late still gets the offer that was waiting for it', () async {
      final p = _Pair();
      await p.callerEngine.start(_video);
      await _settle();
      expect(p.sigCaller.sent.map((s) => s.kind), contains('offer'));
      await p.calleeEngine.start(_video);
      await _settle();
      expect(p.calleePort.log, containsAllInOrder(['remote:offer', 'answer']));
      await p.dispose();
    });

    test('the ICE list and relay-only reach the media stack on BOTH sides', () async {
      const servers = <Map<String, dynamic>>[
        <String, dynamic>{'urls': <String>['stun:192.0.2.1:3478']},
        <String, dynamic>{'urls': <String>['turn:192.0.2.1:3478'], 'username': 'u', 'credential': 'c'},
      ];
      final p = _Pair(
        caller: const CallGrant.lanP2p(sessionId: 's1', role: 'caller', iceServers: servers, relayOnly: true),
        callee: const CallGrant.lanP2p(sessionId: 's1', role: 'callee', iceServers: servers, relayOnly: true));
      await p.connectBoth();
      for (final port in [p.callerPort, p.calleePort]) {
        expect(port.openedIce, servers);
        expect(port.openedRelay, true, reason: 'TURN-only mode: every packet through the relay');
      }
      await p.dispose();
    });

    test('with no ICE servers (the home Wi-Fi) the list is empty and nothing is forced', () async {
      final p = _Pair();
      await p.connectBoth();
      expect(p.callerPort.openedIce, isEmpty);
      expect(p.callerPort.openedRelay, false);
      await p.dispose();
    });

    test('audio is the floor: a voice-only side opens no camera, a video side does', () async {
      final p = _Pair();
      await p.callerEngine.start(_video);
      await p.calleeEngine.start(_audio);
      expect(p.callerPort.openedVideo, true);
      expect(p.calleePort.openedVideo, false);
      await _settle();
      expect(p.callerEngine.state.remoteMode, CallMode.audioOnly, reason: 'told the mode only, never why');
      await p.dispose();
    });

    test('trickled candidates travel in small batches and are held until the remote description is set', () async {
      final p = _Pair();
      await p.callerEngine.start(_video);
      // the callee's candidates arrive at the caller BEFORE the answer
      await p.sigCallee.send('ice', <String, dynamic>{'candidates': <Map<String, dynamic>>[
        <String, dynamic>{'candidate': 'candidate:early 1 udp 1 192.0.2.7 5000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0}]});
      await _settle();
      expect(p.callerPort.remoteCandidates, isEmpty, reason: 'no remote description yet: held, not applied');
      await p.calleeEngine.start(_video);
      await _settle();
      expect(p.callerPort.log.indexOf('remote:answer') < p.callerPort.log.indexWhere((l) => l.startsWith('cand:')), true);
      expect(p.callerPort.remoteCandidates.length, 1);
      // local candidates: three found within one batch window go out as ONE message
      for (var i = 0; i < 3; i++) {
        p.callerPort.emit(RtcLocalCandidate(<String, dynamic>{'candidate': 'candidate:$i', 'sdpMid': '0', 'sdpMLineIndex': 0}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await _settle();
      final ice = p.sigCaller.sent.where((s) => s.kind == 'ice').toList();
      expect(ice.length, 1);
      expect((ice.single.payload['candidates'] as List).length, 3);
      await p.dispose();
    });

    test('a hostile signal changes nothing: wrong shapes, a stray offer to a caller, an unknown kind', () async {
      final p = _Pair();
      await p.connectBoth();
      final before = List<String>.of(p.callerPort.log);
      await p.sigCallee.send('offer', <String, dynamic>{'description': <String, dynamic>{'type': 'offer', 'sdp': 'x'}});
      await p.sigCallee.send('answer', <String, dynamic>{'description': 'not a map'});
      await p.sigCallee.send('answer', <String, dynamic>{'description': <String, dynamic>{'type': 'offer', 'sdp': 'x'}});
      await p.sigCallee.send('ice', <String, dynamic>{'candidates': 'nope'});
      await p.sigCallee.send('ice', <String, dynamic>{'candidates': <Object>[1, <String, dynamic>{'candidate': 7}]});
      await p.sigCallee.send('teleport', <String, dynamic>{});
      await _settle();
      expect(p.callerPort.log, before, reason: 'none of it reached the media stack');
      expect(p.callerEngine.state.phase, CallPhase.connected);
      await p.dispose();
    });
  });

  group('staying up when the network changes', () {
    test('the caller restarts ICE (a new offer) when the connection drops and does not come back', () async {
      final p = _Pair();
      await p.connectBoth();
      p.callerPort.emit(const RtcTransportState('disconnected'));
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.reconnecting);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await _settle();
      expect(p.callerPort.offerRestarts.last, true);
      expect(p.calleePort.log.where((l) => l == 'answer').length, 2, reason: 'the callee answers the restart offer');
      p.callerPort.emit(const RtcTransportState('connected'));
      p.calleePort.emit(const RtcTransportState('connected'));
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.connected);
      await p.dispose();
    });

    test('a blip that heals on its own does not restart anything', () async {
      final p = _Pair();
      await p.connectBoth();
      p.callerPort.emit(const RtcTransportState('disconnected'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      p.callerPort.emit(const RtcTransportState('connected'));
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await _settle();
      expect(p.callerPort.offerRestarts.where((r) => r), isEmpty);
      expect(p.callerEngine.restartCount, 0);
      await p.dispose();
    });

    test('a failed connection restarts at once', () async {
      final p = _Pair();
      await p.connectBoth();
      p.callerPort.emit(const RtcTransportState('failed'));
      await _settle();
      expect(p.callerPort.offerRestarts.last, true);
      await p.dispose();
    });

    test('when the CALLEE notices, it asks the caller, who makes the new offer', () async {
      final p = _Pair();
      await p.connectBoth();
      p.calleePort.emit(const RtcTransportState('failed'));
      await _settle();
      expect(p.sigCallee.sent.map((s) => s.kind), contains('restart'));
      expect(p.callerPort.offerRestarts.last, true);
      await p.dispose();
    });

    test('the picture is dropped and only comes back on her own tap; the voice stays', () async {
      final p = _Pair();
      await p.connectBoth();
      p.callerPort.emit(const RtcTransportState('failed'));
      await _settle();
      expect(p.callerEngine.state.cameraEnabled, false);
      expect(p.callerEngine.state.awaitingResumeConsent, true);
      expect(p.callerPort.log, contains('cam:false'));
      expect(p.callerPort.log, isNot(contains('mic:false')), reason: 'audio is never shed');
      await p.callerEngine.setCameraEnabled(true);
      expect(p.callerEngine.state.awaitingResumeConsent, false);
      expect(p.callerPort.log.last, 'cam:true');
      await p.dispose();
    });

    test('restarts are bounded: past the budget the call ends calmly instead of looping', () async {
      final p = _Pair(maxRestarts: 2);
      await p.connectBoth();
      for (var i = 0; i < 6 && p.callerEngine.state.phase != CallPhase.ended; i++) {
        p.callerPort.emit(const RtcTransportState('failed'));
        await _settle();
        await Future<void>.delayed(const Duration(milliseconds: 130)); // longer than one restart attempt's own wait
      }
      expect(p.callerEngine.state.phase, CallPhase.ended);
      expect(p.callerPort.closed, true);
      await p.dispose();
    });
  });

  group('ending', () {
    test('hanging up tells the other side and both end; nothing is left open', () async {
      final p = _Pair();
      await p.connectBoth();
      await p.callerEngine.leave();
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.ended);
      expect(p.calleeEngine.state.phase, CallPhase.ended);
      expect(p.callerPort.closed && p.calleePort.closed, true);
      await p.dispose();
    });

    test('the callee can hang up too, and the caller is told', () async {
      final p = _Pair();
      await p.connectBoth();
      await p.calleeEngine.leave();
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.ended);
      await p.dispose();
    });

    test('the server closing the call ends it (the other side ended it through the end route)', () async {
      final p = _Pair();
      await p.connectBoth();
      p.sigCaller.endWith(CallSignalingEnd.closed);
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.ended);
      await p.dispose();
    });

    test('a call that never connected ends without ever having been connected (calm unavailable, no end record)', () async {
      final p = _Pair();
      await p.callerEngine.start(_video);
      await p.sigCaller.send('bye', const <String, dynamic>{}); // nobody answered; the other side cancelled
      await p.callerEngine.leave();
      await _settle();
      expect(p.callerEngine.state.everConnected, false);
      expect(p.callerEngine.state.phase, CallPhase.ended);
      await p.dispose();
    });

    test('nobody answers: the caller gives up quietly after the wait', () async {
      final p = _Pair(answerWait: const Duration(milliseconds: 50));
      await p.callerEngine.start(_video);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _settle();
      expect(p.callerEngine.state.phase, CallPhase.ended);
      expect(p.callerEngine.state.everConnected, false);
      await p.dispose();
    });

    test('signalling lost while still setting up ends the attempt; lost mid-call keeps the call', () async {
      final a = _Pair();
      await a.callerEngine.start(_video);
      a.sigCaller.endWith(CallSignalingEnd.lost);
      await _settle();
      expect(a.callerEngine.state.phase, CallPhase.ended);
      await a.dispose();

      final b = _Pair();
      await b.connectBoth();
      b.sigCaller.endWith(CallSignalingEnd.lost);
      await _settle();
      expect(b.callerEngine.state.phase, CallPhase.connected, reason: 'the media does not depend on the server');
      await b.dispose();
    });

    test('media that cannot open (no microphone, no permission) is a calm unavailable, never a raw error', () async {
      final sig = MemoryCallSignaling.pair().$1;
      final e = LanCallEngine(rtc: FakeRtcPort(failOpen: true), signaling: sig, grant: _callerGrant);
      await expectLater(e.start(_video), throwsA(isA<CallUnavailableException>()
          .having((x) => x.reason, 'reason', CallUnavailableReason.unreachable)
          .having((x) => '$x'.contains('microphone'), 'no raw text', false)));
      await e.dispose();
    });
  });

  group('controls and mode', () {
    test('mute and camera reach the media stack; the camera choice is published as a mode, never a reason', () async {
      final p = _Pair();
      await p.connectBoth();
      await p.callerEngine.setMicrophoneEnabled(false);
      expect(p.callerEngine.state.micEnabled, false);
      await p.callerEngine.setCameraEnabled(false);
      await _settle();
      expect(p.callerPort.log, containsAll(['mic:false', 'cam:false']));
      expect(p.calleeEngine.state.remoteMode, CallMode.audioOnly);
      final modes = p.sigCaller.sent.where((s) => s.kind == 'mode').map((s) => s.payload.keys.join(',')).toSet();
      expect(modes, {'mode'}, reason: 'the mode message carries one key and nothing else');
      await p.dispose();
    });

    test('nothing in a direct call records: no recorder, no capture-to-file, no stats upload anywhere in the path', () {
      for (final f in ['lan_call_engine.dart', 'lan_webrtc_port.dart', 'lan_p2p_call_provider.dart', 'call_signaling.dart']) {
        final code = File('lib/$f').readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join(' ');
        for (final banned in ['MediaRecorder', 'startRecording', 'RecordingManager', 'captureFrame', 'writeAsBytes', 'File(', 'VideoCapturer']) {
          expect(code.contains(banned), false, reason: '$f must not contain $banned');
        }
      }
    });
  });
}
