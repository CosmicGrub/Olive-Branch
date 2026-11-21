// OLIVE BRANCH - DEVELOPER-ONLY "simulate the other end of a call". Compiled to nothing in a normal build.
//
// To look at the call screens and the ring on ONE real device (the other device is not to hand), a build made with
//   --dart-define=OLIVE_DEV_CALL_SIM=true
// shows a small strip with two buttons:
//   on the grown-up's phone   "Simulate: she answers"      opens the call screen as if Ivy had picked up;
//   on the child's tablet     "Simulate: a grown-up calls" shows the knock exactly as a real ring would, and Answer
//                             goes on to a call screen as if the grown-up were there.
// Everything it shows is marked "simulated", and none of it touches the server, the call log or the network: a
// simulated call is not a call. The strip and the simulated engine are only ever reachable through [kDevCallSim], a
// compile-time constant, so a build without the define contains none of it, and tools/check-dev-call-sim.mjs fails CI
// if anything other than this file and the one device script names the define.
//
// Passed ONLY by tools/device-sync.sh, and only when OLIVE_DEV_CALL_SIM=1 is set in its environment. A store or
// release build never carries it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'call_knock_screen.dart';
import 'call_modes.dart' show CallMode;
import 'call_provider.dart';
import 'call_screen.dart';
import 'degradation_banner.dart' show Quality;

/// True only in a build made with --dart-define=OLIVE_DEV_CALL_SIM=true.
const bool kDevCallSim = bool.fromEnvironment('OLIVE_DEV_CALL_SIM');

/// The grant the simulated calls carry. Names no server and no session.
const CallGrant kSimulatedGrant = CallGrant.lanP2p(sessionId: 'simulated', role: 'callee', displayName: 'simulated');

/// A call engine with nobody on the other end: "connects" after a moment and ends when asked. Marks the other side
/// "(simulated)" so nothing on screen can be mistaken for a real call.
class SimulatedCallProvider implements CallProvider {
  SimulatedCallProvider({this.who = 'Someone', this.connectAfter = const Duration(milliseconds: 1500)});

  final String who;
  final Duration connectAfter;
  Timer? _t;
  CallViewState _state = const CallViewState();
  final StreamController<CallViewState> _ctl = StreamController<CallViewState>.broadcast();

  @override
  CallProviderKind get kind => CallProviderKind.lanP2p;
  @override
  bool get rendersOwnScreen => false;
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
    _set(CallViewState(phase: CallPhase.connecting, cameraEnabled: options.mode == CallMode.video));
    _t = Timer(connectAfter, () => _set(_state.copyWith(phase: CallPhase.connected, remoteName: '$who (simulated)')));
  }

  @override
  Future<void> leave() async => _set(_state.copyWith(phase: CallPhase.ended));
  @override
  Future<void> setMicrophoneEnabled(bool enabled) async => _set(_state.copyWith(micEnabled: enabled));
  @override
  Future<void> setCameraEnabled(bool enabled) async => _set(_state.copyWith(cameraEnabled: enabled));
  @override
  void applyQuality(Quality quality) {}
  @override
  Widget? buildRemoteVideo() => null;
  @override
  Widget? buildLocalVideo() => null;

  @override
  Future<void> dispose() async {
    _t?.cancel();
    if (!_ctl.isClosed) await _ctl.close();
  }
}

enum DevCallSimSide { guardian, tablet }

/// The strip. Empty (a zero-size box) unless [kDevCallSim].
class DevCallSimBar extends StatelessWidget {
  const DevCallSimBar({super.key, required this.side, required this.otherName, this.navigatorKey});

  final DevCallSimSide side;

  /// Who is on the other end: her name on the phone, the grown-up's on the tablet.
  final String otherName;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    if (!kDevCallSim) return const SizedBox.shrink();
    final bool phone = side == DevCallSimSide.guardian;
    return Material(
      color: const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: <Widget>[
          const Text('Dev only', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              key: const Key('devCallSimButton'),
              onPressed: () => phone ? _simulateAnswer(context) : _simulateRing(context),
              child: Text(phone ? 'Simulate: $otherName answers (simulated)' : 'Simulate: a grown-up calls (simulated)'),
            ),
          ),
        ]),
      ),
    );
  }

  void _simulateAnswer(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CallScreen(
        who: 'dad', displayName: 'Dad', remoteLabel: otherName, knownGrant: kSimulatedGrant,
        providerFactory: (_) => SimulatedCallProvider(who: otherName)),
    ));
  }

  void _simulateRing(BuildContext context) {
    // The very same knock a real ring shows; "Answer" then opens a simulated call instead of joining a real one.
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CallKnockScreen(
        from: '$otherName (simulated)', who: 'ivy', displayName: 'Ivy', simulated: true),
    ));
  }
}
