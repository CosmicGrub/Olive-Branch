// UNVERIFIED on a real device in the change that added it (see lan_webrtc_port.dart). The state machine under it is
// tested in test/lan_call_engine_test.dart with a fake media port.
// OLIVE BRANCH - the 'lan-p2p' call engine behind [CallProvider]. MASTERFILE 5.19, 5.23, 16.2 #6 (2026-11-21).
//
// A direct device-to-device WebRTC call. The server's grant says "lan-p2p" and carries the ICE list; the two
// devices find each other through the server's authenticated signalling routes and then talk directly (or through
// a TURN relay when the operator configured one and it is needed). No media server, no account, no recording.
//
// Same rules as every provider: the call screens depend on call_provider.dart only; this file and
// call_provider_registry.dart are the only places that know it exists.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'call_provider.dart';
import 'call_signaling.dart';
import 'degradation_banner.dart' show Quality;
import 'lan_call_engine.dart';
import 'lan_webrtc_port.dart';

class LanP2pCallProvider implements CallProvider {
  /// [signaling] is required in practice (the registry refuses to build one without it); [portFactory] lets a test
  /// or the dev "simulate the other end" seam supply a different media port.
  LanP2pCallProvider({required this.signaling, RtcPort Function()? portFactory}) : _portFactory = portFactory ?? WebRtcPort.new;

  final CallSignaling signaling;
  final RtcPort Function() _portFactory;
  LanCallEngine? _engine;
  StreamSubscription<CallViewState>? _sub;
  RtcPort? _port;

  CallViewState _state = const CallViewState();
  final StreamController<CallViewState> _ctl = StreamController<CallViewState>.broadcast();
  bool _disposed = false;

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
    if (grant.kind != CallProviderKind.lanP2p || grant.sessionId == null) {
      throw const CallUnavailableException(CallUnavailableReason.refused, 'not a lan-p2p grant');
    }
    final RtcPort port = _portFactory();
    _port = port;
    final LanCallEngine engine = LanCallEngine(rtc: port, signaling: signaling, grant: grant);
    _engine = engine;
    _sub = engine.states.listen(_set);
    _set(const CallViewState(phase: CallPhase.connecting));
    await engine.start(options); // throws CallUnavailableException when media could not open
  }

  @override
  Future<void> leave() async {
    final LanCallEngine? e = _engine;
    if (e == null) {
      _set(_state.copyWith(phase: CallPhase.ended));
      return;
    }
    await e.leave();
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async => _engine?.setMicrophoneEnabled(enabled);

  @override
  Future<void> setCameraEnabled(bool enabled) async => _engine?.setCameraEnabled(enabled);

  /// The call carries no quality knob of its own; the platform's congestion control adapts the picture.
  @override
  void applyQuality(Quality quality) {}

  @override
  Widget? buildRemoteVideo() => _port?.remoteView();
  @override
  Widget? buildLocalVideo() => _port?.localView();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    await _engine?.dispose();
    if (!_ctl.isClosed) await _ctl.close();
  }
}
